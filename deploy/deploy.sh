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

# ---- SSL 证书自动化 ----
# 优先级：已有 Let's Encrypt → 已有 deploy/certs → certbot 自动申请 → 自签兜底
DOMAIN_SSL="$(grep -E '^DOMAIN=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | xargs)"
DOMAIN_SSL="${DOMAIN_SSL:-player.qlm.org.cn}"

certs_ready() { [[ -f deploy/certs/fullchain.pem && -f deploy/certs/privkey.pem ]]; }

# 1) 尝试从 Let's Encrypt 已有证书复制
if [[ -d /etc/letsencrypt/live ]]; then
  for d in "$DOMAIN_SSL" player.qlm.org.cn; do
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

# 2) 还没有证书 → 自动 certbot 申请
if ! certs_ready; then
  log "SSL 证书缺失，准备通过 certbot 自动申请（域名：${DOMAIN_SSL}）"

  # 安装 certbot
  if ! command -v certbot >/dev/null 2>&1; then
    log "安装 certbot..."
    apt-get update -qq && apt-get install -y -qq certbot >/dev/null 2>&1 \
      || die "certbot 安装失败，请手动执行：apt-get install -y certbot"
  fi

  # 检查 80 端口是否被占用（certbot standalone 需要 80 空闲）
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]80$"; then
    HOLDER_80="$(ss -ltnp 2>/dev/null | awk '$4~/:80$/{print $NF}' | head -1)"
    warn "80 端口被占用（${HOLDER_80}），certbot standalone 需要释放它"
    log "尝试停止可能占用 80 端口的服务..."

    # 停宿主机 nginx（宝塔等）
    systemctl is-active --quiet nginx 2>/dev/null && {
      systemctl stop nginx && log "已停止宿主机 nginx"
    }

    # 停旧 docker 容器（player2-nginx 等）
    docker compose down --remove-orphans 2>/dev/null || true

    # 再检查一次
    sleep 1
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]80$"; then
      HOLDER_80="$(ss -ltnp 2>/dev/null | awk '$4~/:80$/{print $NF}' | head -1)"
      warn "80 端口仍被占用：${HOLDER_80}"
      warn "请手动释放 80 端口后重试，或跳过 SSL 使用自签证书"
      read -p "尝试继续申请证书？可能失败。(y/N) " ca
      [[ "$ca" =~ ^[yY]$ ]] || SKIP_CERTBOT=1
    fi
  fi

  # 执行 certbot 申请
  if [[ "${SKIP_CERTBOT:-0}" != "1" ]]; then
    log "向 Let's Encrypt 申请证书（${DOMAIN_SSL}）..."
    if certbot certonly --standalone \
        -d "${DOMAIN_SSL}" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --keep-until-expiring 2>&1 | sed 's/^/  certbot | /'; then

      LEPATH="/etc/letsencrypt/live/${DOMAIN_SSL}"
      if [[ -d "${LEPATH}" ]]; then
        cp -L "${LEPATH}/fullchain.pem" deploy/certs/fullchain.pem
        cp -L "${LEPATH}/privkey.pem"   deploy/certs/privkey.pem
        chmod 600 deploy/certs/privkey.pem
        log "Let's Encrypt 证书申请成功，已复制到 deploy/certs/"

        # 设置自动续签 hook：续签后复制证书并重载 nginx
        (crontab -l 2>/dev/null | grep -v 'copy-certs.sh'; \
         echo "0 3 1 * * certbot renew --quiet --deploy-hook \"bash ${PROJECT_DIR}/deploy/copy-certs.sh ${DOMAIN_SSL}\"") \
         | crontab -
        log "已添加 crontab 自动续签（每月 1 号 03:00）"
      else
        warn "certbot 报告成功但证书目录不存在：${LEPATH}"
      fi
    else
      warn "certbot 申请失败（域名 DNS 未指向本机 / 80 端口不可达 / Let's Encrypt 限流）"
    fi
  fi
fi

# 3) 最终兜底：自签证书
if ! certs_ready; then
  warn "SSL 证书缺失（deploy/certs/{fullchain,privkey}.pem）"
  warn "nginx 将以自签证书启动 HTTPS（浏览器会报警，仅测试用）"
  log "生成临时自签证书..."
  command -v openssl >/dev/null && {
    openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
      -keyout deploy/certs/privkey.pem \
      -out  deploy/certs/fullchain.pem \
      -subj "/CN=${DOMAIN_SSL}" 2>/dev/null && log "自签证书已生成（7 天有效）"
  } || die "openssl 未安装且无任何 SSL 证书，无法启动 nginx HTTPS"
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
