# Contributing

Thank you for your interest in contributing to jaco-image-server!

## Before opening a PR

- Make sure your contribution does not include any credentials, real domain names, IP addresses, or server-specific paths
- Test your changes on a real Debian/Ubuntu server if possible
- Keep configuration files generic — use placeholders like `YOUR_DOMAIN`, `YOUR_PUBLIC_BUCKET`, etc.

## What to check before committing

Run this to catch accidental secrets:
```bash
git diff --staged | grep -iE "(password|secret|key|token)\s*=" | grep -v "example\|placeholder\|change_me\|your_"
```

## Code style

- Shell scripts: `set -euo pipefail`, `shellcheck`-clean when possible
- Nginx: 4-space indent, comment every non-obvious directive
- Keep docs updated when changing configuration files

## Sensitive file checklist

Never commit:
- `/etc/default/minio` (real credentials)
- Any `.pem`, `.key`, `.crt` files
- Real bucket names, access keys, or endpoint URLs
- Server IP addresses or hostnames
