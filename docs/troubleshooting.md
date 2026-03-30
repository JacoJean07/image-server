# Troubleshooting

Common issues and how to fix them.

---

## MinIO won't start

**Check logs first:**
```bash
sudo journalctl -u minio -n 50 --no-pager
```

### `Permission denied` on data directory

```
ERROR Unable to initialize backend: mkdir /data/minio: permission denied
```

```bash
sudo chown minio-user:minio-user /data/minio
sudo chmod 750 /data/minio
sudo systemctl restart minio
```

### `address already in use` on port 9000

Another process is using port 9000:
```bash
sudo ss -tlnp | grep 9000
sudo kill -9 <PID>
sudo systemctl restart minio
```

### Environment file not found

```
execve(/usr/local/bin/minio) failed: No such file or directory
```

Check the binary exists and is executable:
```bash
ls -la /usr/local/bin/minio
sudo chmod +x /usr/local/bin/minio
```

---

## Nginx errors

### `client intended to send too large body`

```
client intended to send too large body: 2041957 bytes
```

`client_max_body_size` is too small or nginx hasn't reloaded since it was set.

1. Make sure `client_max_body_size 10M;` is inside the **server{}** block (not inside a location):
```nginx
server {
    listen 443 ssl;
    client_max_body_size 10M;   # ← here
    ...
}
```

2. Reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### `proxy_cache_path` — zone not found

```
nginx: [emerg] "proxy_cache" zone "minio_cache" is unknown
```

The `nginx/cache.conf` is not loaded at the http{} level. Ensure it's in `/etc/nginx/conf.d/`:
```bash
sudo cp nginx/cache.conf /etc/nginx/conf.d/minio-cache.conf
sudo nginx -t && sudo systemctl reload nginx
```

### `$cors_origin` variable not defined

The `nginx/cors-map.conf` is not loaded. Ensure it's in `/etc/nginx/conf.d/`:
```bash
sudo cp nginx/cors-map.conf /etc/nginx/conf.d/minio-cors.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

## CORS issues

### Browser: `No 'Access-Control-Allow-Origin' header`

The request Origin doesn't match any pattern in the CORS map. Check:

1. What origin is the browser sending? (DevTools → Network → request headers → `Origin`)
2. Does it match the patterns in `/etc/nginx/conf.d/minio-cors.conf`?

Example: if your app is at `https://app.example.com` and the map only has `example.com`, update the map:
```nginx
"~^https://app\.example\.com$"  "$http_origin";
```

Then reload nginx.

### MinIO CORS errors when using mc or SDK directly

This is expected. MinIO CE doesn't support custom CORS configurations. All public access must go through Nginx. Do not expose MinIO port 9000 publicly.

---

## Upload errors (413 / "file too large")

Check all three limits are aligned:

| Layer | Setting | Where |
|-------|---------|-------|
| Nginx | `client_max_body_size 10M` | `server{}` block |
| PHP FPM | `upload_max_filesize = 8M` | `/etc/php/X.Y/fpm/php.ini` |
| PHP FPM | `post_max_size = 16M` | `/etc/php/X.Y/fpm/php.ini` |

After changing PHP FPM:
```bash
sudo systemctl reload phpX.Y-fpm
# Verify (must use FPM, not CLI):
php -r "echo ini_get('upload_max_filesize');"   # shows CLI value (may differ)
```

The FPM value applies to web requests. If you use phpinfo() from a browser request you'll see the actual FPM value.

---

## 403 on public objects

### Missing bucket policy

The public bucket needs an anonymous read policy:
```bash
mc anonymous set download local/your-public-bucket
```

### Nginx blocking the file type

If the file extension matches the blocked list in `minio-proxy.conf`:
```nginx
if ($uri ~* \.(php|php5|phtml|sh|py|rb|pl|exe|...)$) {
    return 403;
}
```

This is intentional. Do not upload executable files to the public bucket.

---

## Signed URLs not working (403 on private objects)

### Missing `X-Amz-Signature` query parameter

The Nginx location block for the private bucket requires the signature:
```nginx
if ($arg_X-Amz-Signature = "") {
    return 403;
}
```

Make sure you're generating the URL with `temporaryUrl()` (Laravel) or the equivalent in your SDK — not with `url()`.

### Expired signature

Signed URLs expire. Check the `X-Amz-Expires` parameter in the URL. If it's expired, regenerate.

### Clock skew

MinIO validates the timestamp in the signature. If the server clock is off by more than 15 minutes, all signed URLs will fail:
```bash
timedatectl status
# If NTP is not synced:
sudo timedatectl set-ntp true
```

---

## Laravel Storage errors

### `NoSuchBucket` / `The specified bucket does not exist`

The bucket name in `.env` doesn't match what was created in MinIO:
```bash
mc ls local/
# Lists all buckets
```

### `InvalidAccessKeyId`

The access key in `.env` doesn't match any MinIO user. Re-check `scripts/create-buckets.sh` output and update `.env`.

### `Connection refused` on MinIO endpoint

MinIO is not running or the endpoint is wrong:
```bash
sudo systemctl status minio
curl -s http://127.0.0.1:9000/minio/health/live && echo "OK"
```

If the endpoint in `.env` uses `https://` but MinIO has no TLS configured (it shouldn't when behind Nginx), change it to `http://127.0.0.1:9000`.

---

## Checking MinIO health

```bash
# Service status
sudo systemctl status minio

# Health endpoint (no auth needed)
curl -s http://127.0.0.1:9000/minio/health/live && echo "MinIO is up"

# List buckets (requires credentials)
mc alias set local http://127.0.0.1:9000 ADMIN_USER ADMIN_PASS
mc ls local/

# Disk usage
mc du local/
```
