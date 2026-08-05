#!/usr/bin/env bash
# ============================================================
# Player2 Debian 服务器初始化脚本 (init-debian.sh)
# 适用系统：Debian 12 (bookworm) / Debian 11 (bullseye)
# 运行：chmod +x deploy/init-debian.sh && sudo bash deploy/init-debian.sh
# ============================================================
set -euo pipefail

DOMAIN="${DOMAIN:-player.qlm.org.cn}"
EMAIL="${EMAIL:-admin@qlm.org.cn}"

log()  { printf "\033[1;32m[INIT]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "必须使用 root / sudo 运行"

log "=== 1. 系统更新与基础依赖 ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common ufw fail2ban htop vim git jq tzdata
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

log "=== 2. 安装 Docker 官方仓库 ==="
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker --version
docker compose version

log "=== 3. 启动 Docker & 开机自启 ==="
systemctl enable --now docker
systemctl enable --now containerd

log "=== 4. 防火墙配置 (UFW) ==="
ufw default deny incoming || true
ufw default allow outgoing || true
ufw allow ssh || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw --force enable || warn "UFW enable failed, ignore"
ufw status verbose || true

log "=== 5. fail2ban 防爆破 ==="
systemctl enable --now fail2ban || warn "fail2ban 启动失败，继续"

log "=== 6. 创建目录结构 ==="
PROJECT_DIR="/opt/player2"
mkdir -p "${PROJECT_DIR}/deploy/certs"
mkdir -p "${PROJECT_DIR}/deploy/logs/nginx"
mkdir -p "${PROJECT_DIR}/backend" "${PROJECT_DIR}/web" "${PROJECT_DIR}/mod" "${PROJECT_DIR}/bridge"

log "=== 7. 安装 Certbot (Let's Encrypt SSL 证书自动申请) ==="
apt-get install -y --no-install-recommends certbot
# 如果后续 certbot --nginx 需要可以安装 python3-certbot-nginx
apt-get install -y --no-install-recommends python3-certbot-nginx || warn "certbot-nginx 未安装"

log "=== 8. 系统调优 (sysctl) ==="
cat > /etc/sysctl.d/99-player2.conf <<'EOF'
# 应对 WebSocket 大量长连接
fs.file-max = 1048576
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.netfilter.nf_conntrack_max = 1048576
EOF
sysctl -p /etc/sysctl.d/99-player2.conf || warn "sysctl 调优部分失败（可能是容器内运行）"

cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 524288
* hard nofile 1048576
root soft nofile 524288
root hard nofile 1048576
EOF

log "=== 9. Docker 国内镜像加速（可选，如果服务器在中国）==="
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 1048576,
      "Soft": 524288
    }
  }
}
EOF
# 中国网络环境取消下面注释以启用镜像加速
# cat >> /etc/docker/daemon.json <<'EOF'
# ,
#   "registry-mirrors": [
#     "https://docker.1ms.run",
#     "https://docker.m.daocloud.io"
#   ]
# }
# EOF
systemctl restart docker

log "=== 初始化完成 ==="
echo
echo "后续步骤："
echo "  1. 把项目代码上传到 ${PROJECT_DIR}"
echo "  2. cd ${PROJECT_DIR} && cp .env.example .env && nano .env   # 填 AI_API_KEY / JWT_SECRET"
echo "  3. 申请 SSL：certbot certonly --nginx -d ${DOMAIN} -m ${EMAIL} --agree-tos"
echo "     或使用 DNS 验证（推荐）：certbot certonly --manual --preferred-challenges dns -d ${DOMAIN}"
echo "  4. 复制证书到 deploy/certs/：见 deploy/copy-certs.sh"
echo "  5. 启动服务：bash deploy/deploy.sh"
echo
