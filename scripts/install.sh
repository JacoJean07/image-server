#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# jaco-image-server — install.sh
# Installs MinIO + configures it as a systemd service on Debian/Ubuntu.
# Run as root or with sudo.
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

MINIO_BINARY_URL="https://dl.min.io/server/minio/release/linux-amd64/minio"
MINIO_BIN="/usr/local/bin/minio"
MINIO_USER="minio-user"
MINIO_DATA_DIR="/data/minio"
ENV_FILE="/etc/default/minio"
SERVICE_FILE="/etc/systemd/system/minio.service"

# ── Colour helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Root check ─────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root (sudo $0)"

# ── 1. Create dedicated system user ───────────────────────────────────────
if ! id "$MINIO_USER" &>/dev/null; then
    useradd --system --shell /sbin/nologin --create-home --home-dir /home/minio-user "$MINIO_USER"
    info "Created system user: $MINIO_USER"
else
    warn "User $MINIO_USER already exists — skipping"
fi

# ── 2. Create data directory ───────────────────────────────────────────────
mkdir -p "$MINIO_DATA_DIR"
chown "$MINIO_USER:$MINIO_USER" "$MINIO_DATA_DIR"
chmod 750 "$MINIO_DATA_DIR"
info "Data directory: $MINIO_DATA_DIR"

# ── 3. Download MinIO binary ───────────────────────────────────────────────
if [[ ! -f "$MINIO_BIN" ]]; then
    info "Downloading MinIO binary…"
    curl -fsSL "$MINIO_BINARY_URL" -o "$MINIO_BIN"
    chmod +x "$MINIO_BIN"
    info "MinIO installed at $MINIO_BIN"
else
    warn "MinIO binary already exists at $MINIO_BIN — skipping download"
    warn "To update, run:  curl -fsSL $MINIO_BINARY_URL -o $MINIO_BIN"
fi

# ── 4. Copy environment file ───────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    warn "$ENV_FILE already exists — skipping (edit manually if needed)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    EXAMPLE_ENV="$SCRIPT_DIR/../minio.env.example"
    if [[ -f "$EXAMPLE_ENV" ]]; then
        cp "$EXAMPLE_ENV" "$ENV_FILE"
        chmod 640 "$ENV_FILE"
        chown root:"$MINIO_USER" "$ENV_FILE"
        info "Copied minio.env.example → $ENV_FILE"
        echo ""
        warn "IMPORTANT: Edit $ENV_FILE and change MINIO_ROOT_PASSWORD before starting!"
        echo ""
    else
        error "minio.env.example not found at $EXAMPLE_ENV"
    fi
fi

# ── 5. Install systemd service ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SRC="$SCRIPT_DIR/../systemd/minio.service"
if [[ ! -f "$SERVICE_SRC" ]]; then
    error "systemd/minio.service not found at $SERVICE_SRC"
fi

cp "$SERVICE_SRC" "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable minio
info "Systemd service installed and enabled"

# ── 6. Create Nginx cache directory ───────────────────────────────────────
mkdir -p /var/cache/nginx/minio
chown www-data:www-data /var/cache/nginx/minio 2>/dev/null || \
    chown nginx:nginx /var/cache/nginx/minio 2>/dev/null || true
info "Nginx cache directory created: /var/cache/nginx/minio"

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit /etc/default/minio  — set a strong MINIO_ROOT_PASSWORD"
echo "  2. Copy nginx/cors-map.conf  → /etc/nginx/conf.d/"
echo "  3. Copy nginx/cache.conf     → /etc/nginx/conf.d/"
echo "  4. Add nginx/minio-proxy.conf content to your server{} block"
echo "  5. sudo systemctl start minio"
echo "  6. sudo systemctl reload nginx"
echo "  7. Open http://127.0.0.1:9001 via SSH tunnel to create buckets"
echo ""
echo "See README.md for full configuration details."
