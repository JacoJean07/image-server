#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# jaco-image-server — create-buckets.sh
# Creates the public and private buckets and an application service account
# using the MinIO Client (mc). Run after MinIO is up.
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Configuration — edit these ─────────────────────────────────────────────
MINIO_ENDPOINT="http://127.0.0.1:9000"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minio_admin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"      # read from env or prompt
PUBLIC_BUCKET="${PUBLIC_BUCKET:-myapp-public}"
PRIVATE_BUCKET="${PRIVATE_BUCKET:-myapp-private}"
APP_ACCESS_KEY="${APP_ACCESS_KEY:-myapp_app}"
APP_SECRET_KEY="${APP_SECRET_KEY:-}"                # read from env or prompt

# ── Colour helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Prompt for secrets if not set ─────────────────────────────────────────
if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
    read -rsp "MinIO root password: " MINIO_ROOT_PASSWORD; echo
fi
if [[ -z "$APP_SECRET_KEY" ]]; then
    read -rsp "App service account secret key (min 8 chars): " APP_SECRET_KEY; echo
fi

# ── Check mc is installed ──────────────────────────────────────────────────
if ! command -v mc &>/dev/null; then
    info "MinIO Client (mc) not found — downloading…"
    curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
    chmod +x /usr/local/bin/mc
fi

# ── Configure mc alias ────────────────────────────────────────────────────
mc alias set local "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --api S3v4

# ── Create buckets ─────────────────────────────────────────────────────────
for bucket in "$PUBLIC_BUCKET" "$PRIVATE_BUCKET"; do
    if mc ls "local/$bucket" &>/dev/null 2>&1; then
        warn "Bucket '$bucket' already exists — skipping"
    else
        mc mb "local/$bucket"
        info "Created bucket: $bucket"
    fi
done

# ── Set public bucket policy (read-only public) ────────────────────────────
mc anonymous set download "local/$PUBLIC_BUCKET"
info "Public bucket policy set (anonymous download)"

# ── Create application service account ────────────────────────────────────
# Policy: full access to both buckets
POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${PUBLIC_BUCKET}",
        "arn:aws:s3:::${PUBLIC_BUCKET}/*",
        "arn:aws:s3:::${PRIVATE_BUCKET}",
        "arn:aws:s3:::${PRIVATE_BUCKET}/*"
      ]
    }
  ]
}
EOF
)

POLICY_FILE=$(mktemp /tmp/minio-policy-XXXX.json)
echo "$POLICY_JSON" > "$POLICY_FILE"

mc admin policy create local myapp-policy "$POLICY_FILE" 2>/dev/null || \
    mc admin policy update local myapp-policy "$POLICY_FILE"
info "Policy 'myapp-policy' created/updated"

mc admin user add local "$APP_ACCESS_KEY" "$APP_SECRET_KEY" 2>/dev/null || \
    warn "User '$APP_ACCESS_KEY' already exists"
mc admin policy attach local myapp-policy --user "$APP_ACCESS_KEY"
info "Service account '$APP_ACCESS_KEY' configured"

rm -f "$POLICY_FILE"

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Buckets ready!${NC}"
echo ""
echo "  Public bucket  : $MINIO_ENDPOINT/$PUBLIC_BUCKET"
echo "  Private bucket : $MINIO_ENDPOINT/$PRIVATE_BUCKET"
echo ""
echo "Add to your app .env:"
echo "  S3_ACCESS_KEY_ID=$APP_ACCESS_KEY"
echo "  S3_SECRET_ACCESS_KEY=<the secret you entered>"
echo "  S3_ENDPOINT=$MINIO_ENDPOINT"
echo "  S3_PUBLIC_BUCKET=$PUBLIC_BUCKET"
echo "  S3_PRIVATE_BUCKET=$PRIVATE_BUCKET"
