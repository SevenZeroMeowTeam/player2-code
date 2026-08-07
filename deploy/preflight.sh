#!/usr/bin/env bash
# ============================================================
# Player2 部署前预检脚本 (preflight.sh)
# 在 init-debian.sh 之后、deploy.sh 之前跑。
# 任何 FAIL 都不要跳过，先解决！
# ============================================================
set -uo pipefail

cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
PROJECT_DIR="$(pwd)"

PASS=0
FAIL=0
WARN=0

pass()  { printf "\033[1;32m[PASS]\033[0m %s\n" "$*"; PASS=$((PASS+1)); }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; WARN=$((WARN+1)); }
fail()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; FAIL=$((FAIL+1)); }

echo
echo "======================================"
echo "  Player2 部署预检  (v1.0)"
echo "  项目根目录：${PROJECT_DIR}"
echo "======================================"
echo

# ---------------- 1. OS / 权限 ----------------
echo "[1] 系统环境"
ID=""
ID_LIKE=""
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  ID="${ID:-unknown}"
  ID_LIKE="${ID_LIKE:-}"
  echo "    系统: ${PRETTY_NAME:-unknown}"
fi

# 归类到家族：debian / rhel / suse / arch / unknown
detect_family() {
  case "$1" in
    debian|ubuntu|linuxmint|pop|kali) echo "debian" ;;
    rhel|centos|rocky|almalinux|ol|fedora|virtuozzo) echo "rhel" ;;
    opensuse*|suse|sles) echo "suse" ;;
    arch|manjaro|garuda|endeavouros) echo "arch" ;;
    *)
      for _like in $2; do
        case "$_like" in
          debian|ubuntu) echo "debian"; return ;;
          rhel|fedora|centos) echo "rhel"; return ;;
          suse|sles) echo "suse"; return ;;
          arch) echo "arch"; return ;;
        esac
      done
      echo "unknown"
      ;;
  esac
}
FAMILY=$(detect_family "$ID" "$ID_LIKE")
case "$FAMILY" in
  debian) pass "发行版家族：debian 系（$ID）— 走 apt" ;;
  rhel)   pass "发行版家族：rhel 系（$ID）— 走 dnf/yum" ;;
  suse)   pass "发行版家族：suse 系（$ID）— 走 zypper" ;;
  arch)   pass "发行版家族：arch 系（$ID）— 走 pacman" ;;
  *)      warn "发行版 $ID 不在自动支持列表（Debian/RHEL/openSUSE/Arch），可能需要手动安装依赖" ;;
esac
[[ $EUID -eq 0 ]] && pass "root 用户" || warn "非 root，若 docker 命令报权限错误请加 sudo 或把用户加入 docker 组"
MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_GB=$(( MEM_KB / 1024 / 1024 ))
echo "    内存: ~${MEM_GB} GB"
(( MEM_GB >= 4 )) && pass "内存 >= 4GB" || fail "内存小于 4GB，生产不足（2C4G 起步，建议 4C8G）"
DISK_AVAIL=$(df -k . | awk 'NR==2{print $4}')
DISK_GB=$(( DISK_AVAIL / 1024 / 1024 ))
echo "    磁盘可用: ~${DISK_GB} GB"
(( DISK_GB >= 20 )) && pass "磁盘 >= 20GB" || fail "磁盘小于 20GB，构建镜像容易失败"

# ---------------- 2. Docker ----------------
echo
echo "[2] Docker 环境"
if command -v docker >/dev/null 2>&1; then
  pass "docker 已安装: $(docker --version 2>&1 | head -1)"
  if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose v2: $(docker compose version 2>&1 | head -1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    pass "docker-compose（独立二进制）: $(docker-compose version 2>&1 | head -1)"
  else
    fail "未检测到 docker compose；请执行：bash deploy/init.sh（或对应家族：apt/dnf/zypper/pacman 安装 docker-compose-plugin）"
  fi
  systemctl is-active --quiet docker 2>/dev/null && pass "Docker 服务运行中" || fail "Docker 服务未启动；systemctl enable --now docker"
else
  fail "未安装 Docker，请先执行 bash deploy/init.sh"
fi

# ---------------- 3. 端口占用 ----------------
echo
echo "[3] 端口占用（80 / 443 / 8080）"
for p in 80 443 8080; do
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
    HOLDER="$(ss -ltnp 2>/dev/null | awk -v p=":$p" '$4~p{print $0}' | head -1)"
    if [[ "$p" == "8080" ]]; then
      # 8080 只允许 docker-compose 起的 backend，宿主机不应监听
      warn "端口 $p 已被占用。若这是 docker compose 之前的实例，可忽略。详情：${HOLDER}"
    else
      warn "端口 $p 已被占用（${HOLDER:-不明}）。certbot standalone 时要先停 nginx；日常应只允许 player2-nginx 占用 80/443"
    fi
  else
    pass "端口 $p 空闲"
  fi
done

# ---------------- 4. 防火墙 / 安全组 ----------------
echo
echo "[4] 防火墙 / 安全组提示（仅提示）"
if command -v ufw >/dev/null && ufw status 2>/dev/null | head -1 | grep -q active; then
  for p in 22/tcp 80/tcp 443/tcp; do
    ufw status | grep -qw "$p" && pass "UFW 允许 $p" || warn "UFW 未见明确允许 $p；如果外部访问失败，请：ufw allow $p"
  done
elif command -v firewall-cmd >/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  for p in 22/tcp 80/tcp 443/tcp; do
    if firewall-cmd --list-ports 2>/dev/null | grep -qw "${p%/*}" || firewall-cmd --list-services 2>/dev/null | grep -qw "$( [[ $p == 22/* ]] && echo ssh || echo '' )"; then
      pass "firewalld 允许 $p"
    else
      warn "firewalld 未见明确允许 $p；如外部访问失败，请：firewall-cmd --permanent --add-port=$p && firewall-cmd --reload"
    fi
  done
else
  warn "未检测到 ufw / firewalld。确保云厂商安全组/硬件防火墙放行了 22 / 80 / 443"
fi

# ---------------- 5. .env 配置文件 ----------------
echo
echo "[5] .env 配置文件"
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  pass ".env 存在：${ENV_FILE}"
  chk() {
    local key="$1" placeholder_regex="$2" label="$3"
    local v="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')"
    if [[ -z "$v" ]]; then fail ".env 中 ${key} 为空"; return; fi
    if [[ "$v" =~ $placeholder_regex ]]; then fail ".env 中 ${key} 仍是占位符 (${label})"; return; fi
    pass ".env 中 ${key} 已填写"
  }
  chk AI_API_URL  '^(https?://[^/]+|)$'                 "端点"
  chk AI_API_KEY  '^(sk-.*|your_real.*|please.*|)$'     "API Key"
  chk AI_MODEL    '^(deepseek.*|please.*|your.*|)$'      "模型名"
  chk JWT_SECRET  '^(please.*|change.*|)$'               "JWT Secret"
  # 额外校验 JWT_SECRET 长度
  JWTS="$(grep -E '^JWT_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\r')"
  (( ${#JWTS} >= 32 )) && pass "JWT_SECRET 长度 ${#JWTS} >= 32" || fail "JWT_SECRET 太短，建议 openssl rand -hex 32 生成"
  # API Key 占位符更严格：包含 "your_real" "your-deepseek" "change" "please"
  KEYVAL="$(grep -E '^AI_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\r')"
  if [[ "$KEYVAL" =~ (your_real|your-deepseek|change_this|please_change) ]]; then
    fail "AI_API_KEY 仍是占位符，需填写 DeepSeek R1 真实 API Key"
  fi
else
  fail "根目录缺少 .env ；请：cp .env.example .env && nano .env"
fi

# ---------------- 6. DNS 解析 ----------------
echo
echo "[6] 域名 DNS（根据 .env DOMAIN 解析）"
DOMAIN_FROM_ENV="$(grep -E '^DOMAIN=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')"
DOMAIN="${DOMAIN_FROM_ENV:-player.qlm.org.cn}"
echo "    待检查域名: ${DOMAIN}"
if command -v dig >/dev/null; then
  IP="$(dig +short "${DOMAIN}" | tail -1)"
elif command -v host >/dev/null; then
  IP="$(host "${DOMAIN}" | awk '/has address/{print $NF; exit}')"
else
  IP="$(getent hosts "${DOMAIN}" | awk '{print $1; exit}')"
fi
if [[ -z "$IP" ]]; then
  fail "无法解析 ${DOMAIN} 的 A 记录。请在 DNS 控制台添加：A ${DOMAIN} -> 你的服务器公网 IP"
else
  pass "${DOMAIN} -> ${IP}"
  # 猜测本机公网 IP
  MY_PUB="$(curl -sS --max-time 5 https://api.ipify.org 2>/dev/null || echo '')"
  if [[ -n "$MY_PUB" ]]; then
    if [[ "$MY_PUB" == "$IP" ]]; then
      pass "DNS 解析 IP 与本机公网 IP 一致（${MY_PUB}）"
    else
      warn "DNS 解析到 ${IP}，但本机公网 IP 是 ${MY_PUB}。如果本机不是 player.qlm.org.cn 服务器则忽略"
    fi
  fi
fi

# ---------------- 7. 证书（可暂时没） ----------------
echo
echo "[7] SSL 证书"
CERT_DIR="${PROJECT_DIR}/deploy/certs"
mkdir -p "$CERT_DIR"
if [[ -f "$CERT_DIR/fullchain.pem" && -f "$CERT_DIR/privkey.pem" ]]; then
  if command -v openssl >/dev/null; then
    DAYS=$(openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -enddate 2>/dev/null \
      | cut -d= -f2 \
      | xargs -I{} date -d "{}" +%s 2>/dev/null)
    NOW=$(date +%s)
    if [[ -n "$DAYS" ]]; then
      LEFT=$(( (DAYS - NOW)/86400 ))
      (( LEFT >= 7 )) && pass "证书有效，剩余 ${LEFT} 天"
      (( LEFT >= 1 && LEFT < 7 )) && warn "证书 ${LEFT} 天内过期，建议 bash deploy/copy-certs.sh ${DOMAIN}"
      (( LEFT <= 0 )) && fail "证书已过期，请重新 certbot certonly 然后 copy-certs.sh"
    else
      pass "证书文件存在"
    fi
  else
    pass "证书文件存在"
  fi
  PRIV_PERM="$(stat -c '%a' "$CERT_DIR/privkey.pem" 2>/dev/null)"
  [[ "$PRIV_PERM" == "600" ]] && pass "证书私钥权限 600" || warn "私钥权限 $PRIV_PERM（建议 chmod 600 $CERT_DIR/privkey.pem）"
else
  warn "deploy/certs/ 下没有证书。deploy.sh 会自动尝试从 /etc/letsencrypt/ 复制，或生成 7 天自签证书（仅测试）。正式上线请 certbot certonly"
fi

# ---------------- 8. Docker Hub 连通 / 加速 ----------------
echo
echo "[8] Docker 镜像源（仅测 Docker Hub 是否可访问）"
if command -v docker >/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
  if docker manifest inspect library/node:20-bookworm-slim >/dev/null 2>&1; then
    pass "Docker Hub 可访问 / 可用加速"
  else
    # 拉取测试更快：用 2 层的小镜像
    TIME_BEFORE=$(date +%s)
    if docker pull --quiet library/node:20-bookworm-slim >/dev/null 2>&1; then
      TIME_AFTER=$(date +%s)
      pass "成功拉取 node:20-bookworm-slim（用时 $((TIME_AFTER-TIME_BEFORE))s）"
    else
      fail "无法拉取 Docker Hub 镜像。如在中国大陆，请执行部署手册 [10.2] 配置 registry-mirrors"
    fi
  fi
else
  warn "Docker 未运行，跳过连通测试"
fi

# ---------------- 9. AI 连通性 (可选) ----------------
echo
echo "[9] AI 网关 (ai.bbsmc.org.cn) 连通性（需要 .env 正确）"
if [[ -f "$ENV_FILE" ]]; then
  if grep -qE '^AI_API_KEY=(sk-|eyJhbGci)' "$ENV_FILE" 2>/dev/null; then
    if command -v bash >/dev/null; then
      bash deploy/test-ai.sh 2>&1 | tail -10
    fi
  else
    warn ".env 的 AI_API_KEY 非 sk- 开头或为空，跳过自动测试"
  fi
else
  warn "缺少 .env，跳过自动测试"
fi

# ---------------- 结论 ----------------
echo
echo "=================================================="
echo "  预检结束： PASS=${PASS}  WARN=${WARN}  FAIL=${FAIL}"
echo "=================================================="
if (( FAIL > 0 )); then
  echo
  echo -e "\033[1;31m存在 ${FAIL} 项失败！请先解决上述 FAIL 后再运行 bash deploy/deploy.sh\033[0m"
  exit 2
fi
if (( WARN > 0 )); then
  echo
  echo -e "\033[1;33m有 ${WARN} 项警告。如果这是首次部署且全部是端口/证书类提示，可以先继续。\033[0m"
fi
if (( FAIL == 0 )); then
  echo
  echo -e "\033[1;32m无失败项。可直接执行：bash deploy/deploy.sh\033[0m"
fi
