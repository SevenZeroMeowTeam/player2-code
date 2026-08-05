#!/usr/bin/env bash
# ============================================================
# Player2 服务端一键部署脚本 (deploy.sh)
# 在 Debian 服务器的项目根目录执行：
#   chmod +x deploy/deploy.sh && bash deploy/deploy.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

log()  { printf "\033[1;32m[DEPLOY]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "未安装 docker，请先运行 init-debian.sh"
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || die "docker compose 不可用"

[[ -f .env ]] || { log ".env 缺失，复制 .env.example -> .env 请手动编辑"; cp .env.example .env; }
grep -q "change_this\|your_real\|please_change" .env 2>/dev/null \
  && warn ".env 中存在占位符！请编辑：nano ${PROJECT_DIR}/.env" \
  && read -p "是否继续？(y/N) " a && [[ "$a" =~ [yY] ]] || exit 2

mkdir -p deploy/certs deploy/logs/nginx

# SSL 证书检查：如果存在 let's encrypt 证书自动软链
if [[ -d /etc/letsencrypt/live ]]; then
  for d in player.qlm.org.cn "$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | xargs)"; do
    [[ -z "$d" ]] && continue
    LEPATH="/etc/letsencrypt/live/${d}"
    if [[ -d "${LEPATH}" ]]; then
      log "发现 Let's Encrypt 证书：${LEPATH}，复制到 deploy/certs/"
      cp -L "${LEPATH}/fullchain.pem" deploy/certs/fullchain.pem
      cp -L "${LEPATH}/privkey.pem"   deploy/certs/privkey.pem
      chmod 600 deploy/certs/privkey.pem
      break
    fi
  done
fi
if [[ ! -f deploy/certs/fullchain.pem || ! -f deploy/certs/privkey.pem ]]; then
  warn "SSL 证书缺失（deploy/certs/{fullchain,privkey}.pem）"
  warn "nginx 将无法启动 HTTPS。请先运行 certbot 或手动放置证书。"
  log "生成临时自签证书（仅测试用，浏览器会报警）..."
  command -v openssl >/dev/null && {
    openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
      -keyout deploy/certs/privkey.pem \
      -out  deploy/certs/fullchain.pem \
      -subj "/CN=player.qlm.org.cn" 2>/dev/null && log "自签证书已生成"
  } || warn "openssl 未安装，无法生成自签证书"
fi

log "拉取最新镜像 & 构建..."
docker compose build --pull

log "停止旧容器..."
docker compose down --remove-orphans || true

log "启动新容器..."
docker compose up -d

log "等待健康检查..."
sleep 5
for i in {1..30}; do
  STATUS_BACKEND="$(docker inspect -f '{{.State.Health.Status}}' player2-backend 2>/dev/null || echo unknown)"
  STATUS_WEB="$(docker inspect -f '{{.State.Health.Status}}' player2-web 2>/dev/null || echo unknown)"
  log "  backend=${STATUS_BACKEND}  web=${STATUS_WEB}"
  [[ "$STATUS_BACKEND" == "healthy" && "$STATUS_WEB" == "healthy" ]] && break
  sleep 2
done

log "容器状态："
docker compose ps

log "健康检查（本机 8080）："
curl -fsS http://127.0.0.1:8080/health 2>/dev/null && echo || warn "backend 8080 未响应"

log ""
log "============ 部署完成 ============"
echo "访问：  https://player.qlm.org.cn"
echo "日志：  docker compose logs -f --tail=200  backend / web / nginx"
echo "停止：  docker compose down"
echo "重启：  bash deploy/deploy.sh"
