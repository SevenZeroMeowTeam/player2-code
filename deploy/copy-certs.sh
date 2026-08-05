#!/usr/bin/env bash
# ============================================================
# 复制 Let's Encrypt 证书到 deploy/certs/ 并重启 nginx
# 建议加到 crontab 每月运行，或 certbot renew --deploy-hook
# ============================================================
set -euo pipefail

DOMAIN="${1:-player.qlm.org.cn}"
LE_DIR="/etc/letsencrypt/live/${DOMAIN}"
TARGET_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/certs"

[[ -d "${LE_DIR}" ]] || { echo "ERROR: 找不到证书目录 ${LE_DIR}"; exit 1; }

mkdir -p "${TARGET_DIR}"
cp -L "${LE_DIR}/fullchain.pem" "${TARGET_DIR}/fullchain.pem"
cp -L "${LE_DIR}/privkey.pem"   "${TARGET_DIR}/privkey.pem"
chmod 644 "${TARGET_DIR}/fullchain.pem"
chmod 600 "${TARGET_DIR}/privkey.pem"

echo "证书已复制，正在重载 nginx..."
cd "${TARGET_DIR}/../.." && command -v docker >/dev/null 2>&1 && {
  docker compose exec -T nginx nginx -s reload 2>/dev/null \
    || docker compose restart nginx
}
echo "完成。"
