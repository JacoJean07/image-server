# jaco-image-server

> Self-hosted S3-compatible image server — MinIO + Nginx reverse proxy with caching, CORS security, and public/private bucket support.

Built for and extracted from [JacoSaaS](https://jacosaas.com), a multi-tenant ERP/POS SaaS on Laravel. This setup runs on the **same server** as the main application with no additional cost — MinIO is only accessible via localhost; Nginx handles all public traffic.

---

## What this is

A production-ready configuration to run MinIO as a microservice on a Linux VPS and expose it securely through Nginx. It solves real problems that come up when using MinIO CE behind a reverse proxy:

- **MinIO CE allows all CORS origins by default** — we strip its headers and replace them with tightly controlled ones via an Nginx map
- **MinIO console and API bind to all interfaces by default** — we lock both to localhost
- **Large uploads need coordinated config** — PHP FPM, Nginx, and Livewire/app-level limits must all align
- **Cache invalidation** — public objects cached for 30 days in Nginx; private objects (signed URLs) never cached

---

## Architecture

```
Browser / Mobile app
        │  HTTPS
        ▼
   Nginx (public :443)
        │
        ├── /media/your-public-bucket/*  ──► MinIO :9000  (cached, CORS controlled)
        │
        ├── /media/your-private-bucket/* ──► MinIO :9000  (signed URL required, no cache)
        │
        └── /*  ──────────────────────────► Laravel / your app
```

MinIO listens **only on 127.0.0.1:9000** (API) and **127.0.0.1:9001** (console). No public exposure.

---

## Features

- **Public bucket** — objects served via Nginx with 30-day proxy cache, immutable `Cache-Control`, and security headers
- **Private bucket** — MinIO signed URLs required; Nginx validates `X-Amz-Signature` presence; no caching anywhere
- **CORS** — controlled entirely by Nginx; configurable per-domain map; wildcard origin from MinIO is stripped
- **Security headers** — `HSTS`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` on all media responses
- **Path traversal protection** — `../` patterns and executable extensions blocked at Nginx level
- **Systemd service** — hardened unit with `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`
- **Install script** — automated setup for Debian/Ubuntu

---

## Requirements

- Debian 11/12 or Ubuntu 20.04/22.04/24.04
- Nginx ≥ 1.18
- A domain with SSL (Let's Encrypt works fine)
- The main app running on the same server (or reachable on localhost)

---

## Quick start

### 1. Clone and install

```bash
git clone https://github.com/YOUR_ORG/jaco-image-server.git
cd jaco-image-server
sudo bash scripts/install.sh
```

The script will:
- Create a `minio-user` system account
- Download the MinIO binary to `/usr/local/bin/minio`
- Install the systemd service
- Create `/var/cache/nginx/minio` for the proxy cache
- Copy `minio.env.example` → `/etc/default/minio`

### 2. Configure MinIO credentials

```bash
sudo nano /etc/default/minio
```

Change **at minimum**:
```bash
MINIO_ROOT_USER=your_admin_username
MINIO_ROOT_PASSWORD=your_very_long_random_password_here
```

> Use a password manager or `openssl rand -base64 32` to generate a strong password.

### 3. Start MinIO

```bash
sudo systemctl start minio
sudo systemctl status minio
```

### 4. Create buckets and app credentials

```bash
sudo PUBLIC_BUCKET=myapp-public \
     PRIVATE_BUCKET=myapp-private \
     APP_ACCESS_KEY=myapp_app \
     bash scripts/create-buckets.sh
```

You will be prompted for the root password and the new app secret key.

### 5. Configure Nginx

Copy the conf.d files:

```bash
# Proxy cache zone
sudo cp nginx/cache.conf /etc/nginx/conf.d/minio-cache.conf

# CORS origin map — edit the domain patterns first
sudo cp nginx/cors-map.conf /etc/nginx/conf.d/minio-cors.conf
sudo nano /etc/nginx/conf.d/minio-cors.conf
```

Add the proxy locations to your server block. You can either:
- Copy the content of `nginx/minio-proxy.conf` into your existing `server{}` block, or
- Use an `include` directive: `include /path/to/nginx/minio-proxy.conf;`

Replace `YOUR_PUBLIC_BUCKET` and `YOUR_PRIVATE_BUCKET` with your actual bucket names.

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 6. Configure your application

Add to your `.env`:

```ini
MINIO_ACCESS_KEY=myapp_app
MINIO_SECRET_KEY=your_app_secret_key
MINIO_ENDPOINT=http://127.0.0.1:9000
MINIO_PUBLIC_BUCKET=myapp-public
MINIO_PRIVATE_BUCKET=myapp-private

# Public URL served via Nginx (not direct MinIO)
MINIO_PUBLIC_URL=https://yourdomain.com/media/myapp-public
```

For **Laravel** with the S3 driver, add to `config/filesystems.php`:

```php
'minio_public' => [
    'driver'                  => 's3',
    'key'                     => env('MINIO_ACCESS_KEY'),
    'secret'                  => env('MINIO_SECRET_KEY'),
    'region'                  => 'us-east-1',
    'bucket'                  => env('MINIO_PUBLIC_BUCKET'),
    'endpoint'                => env('MINIO_ENDPOINT'),
    'use_path_style_endpoint' => true,
    'url'                     => env('MINIO_PUBLIC_URL'),
    'visibility'              => 'public',
],

'minio_private' => [
    'driver'                  => 's3',
    'key'                     => env('MINIO_ACCESS_KEY'),
    'secret'                  => env('MINIO_SECRET_KEY'),
    'region'                  => 'us-east-1',
    'bucket'                  => env('MINIO_PRIVATE_BUCKET'),
    'endpoint'                => env('MINIO_ENDPOINT'),
    'use_path_style_endpoint' => true,
    'visibility'              => 'private',
],
```

---

## Accessing the MinIO console

The console is bound to `127.0.0.1:9001` — not publicly accessible by design. Use an SSH tunnel:

```bash
ssh -L 9001:127.0.0.1:9001 user@yourserver
```

Then open `http://localhost:9001` in your browser.

---

## CORS configuration

Edit `/etc/nginx/conf.d/minio-cors.conf` to allow the origins your frontend runs on:

```nginx
map $http_origin $cors_origin {
    default  "";

    # Allow your main domain
    "~^https://(www\.)?yourdomain\.com$"  "$http_origin";

    # Allow all tenant subdomains
    "~^https://[a-z0-9][a-z0-9\-]*\.yourdomain\.com$"  "$http_origin";
}
```

After editing: `sudo nginx -t && sudo systemctl reload nginx`

---

## Security notes

### What is protected

| Threat | Mitigation |
|--------|-----------|
| Wildcard CORS from MinIO CE | Nginx strips `Access-Control-*` headers from MinIO, emits its own controlled ones |
| MinIO console exposed publicly | Bound to `127.0.0.1:9001` only |
| Path traversal via media URLs | `../` patterns blocked at Nginx with `return 400` |
| Executable files served as media | Extensions `.php`, `.sh`, `.py` etc. blocked with `return 403` |
| Private files accessed without auth | `X-Amz-Signature` param required; missing → `403` |
| Non-GET requests to media endpoints | Only `GET` and `HEAD` allowed |
| Storage server identity disclosure | `Server`, `X-Amz-Id-2`, `X-Amz-Request-Id` headers stripped |

### What this does NOT cover

- **DDoS / rate limiting** — add `limit_req` in Nginx or use a CDN/WAF
- **MinIO data encryption at rest** — configure MinIO KMS if required
- **Audit logging** — enable MinIO audit log for compliance requirements
- **Bucket versioning / replication** — configure via MinIO console or `mc`

---

## Nginx proxy cache

Public objects are cached in Nginx for **7 days** after last access. Cache is stored at `/var/cache/nginx/minio` (configurable in `nginx/cache.conf`).

To manually purge the cache:

```bash
# Purge entire cache
sudo find /var/cache/nginx/minio -type f -delete

# Or use nginx proxy_cache_purge module if installed
```

Private objects (`/media/your-private-bucket/`) are **never cached** — `proxy_cache off` is set explicitly.

---

## Updating MinIO

```bash
# Download new binary
sudo curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio \
    -o /usr/local/bin/minio

# Restart service
sudo systemctl restart minio
sudo systemctl status minio
```

---

## File structure

```
jaco-image-server/
├── scripts/
│   ├── install.sh           # Automated installer (Debian/Ubuntu)
│   └── create-buckets.sh    # Creates buckets and app service account via mc
├── nginx/
│   ├── minio-proxy.conf     # location blocks for public and private buckets
│   ├── cors-map.conf        # CORS origin map (goes in conf.d/)
│   └── cache.conf           # proxy_cache_path declaration (goes in conf.d/)
├── systemd/
│   └── minio.service        # Hardened systemd unit file
├── docs/
│   ├── laravel-integration.md
│   └── troubleshooting.md
├── minio.env.example        # Environment variable template (safe to commit)
├── .gitignore               # Excludes credentials, data, and binary
└── LICENSE                  # MIT
```

---

## Contributing

Issues and PRs are welcome. Please do not include any credentials, real domain names, or IP addresses in contributions.

---

## License

MIT — see [LICENSE](LICENSE).
