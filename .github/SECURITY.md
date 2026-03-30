# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in jaco-image-server, please **do not open a public issue**.

Report it privately by emailing: **security@jacosaas.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge the report within 48 hours and aim to release a fix within 7 days for critical issues.

## Scope

In-scope:
- Nginx configuration bypasses (CORS, path traversal, method restrictions)
- Systemd service privilege escalation
- Install/setup scripts
- Documentation that recommends insecure practices

Out of scope:
- MinIO itself — report to https://github.com/minio/minio/security
- Issues requiring physical server access
- Denial of service attacks
