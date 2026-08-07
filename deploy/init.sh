#!/usr/bin/env bash
# ============================================================
# Player2 Linux 服务器初始化脚本 (init.sh) — 跨发行版
#
# 支持发行版：
#   • Debian 系：Debian 11/12, Ubuntu 20.04/22.04/24.04, LinuxMint, Pop!_OS
#   • RHEL 系：RHEL 8/9, CentOS 8/9 Stream, Rocky 8/9, AlmaLinux 8/9, Oracle Linux 8/9, Fedora 38+
#   • openSUSE：Tumbleweed / Leap 15.5+
#   • Arch 系：Arch, Manjaro
#
# 运行：chmod +x deploy/init.sh && sudo bash deploy/init.sh
# ============================================================
set -euo pipefail

DOMAIN="${DOMAIN:-player.qlm.org.cn}"
EMAIL="${EMAIL:-admin@qlm.org.cn}"

log()  { printf "\033[1;32m[INIT]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "必须使用 root / sudo 运行"

# ---------------- 1. 发行版识别 ----------------
if [[ ! -f /etc/os-release ]]; then
  die "找不到 /etc/os-release，无法识别发行版。仅支持 Debian/RHEL/openSUSE/Arch 系"
fi
# shellcheck disable=SC1091
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_VERSION_ID="${VERSION_ID:-}"
OS_PRETTY="${PRETTY_NAME:-$OS_ID}"

# 归类到家族：debian / rhel / suse / arch
detect_family() {
  case "$OS_ID" in
    debian|ubuntu|linuxmint|pop|kali) echo "debian" ;;
    rhel|centos|rocky|almalinux|ol|fedora|virtuozzo) echo "rhel" ;;
    opensuse*|suse|sles) echo "suse" ;;
    arch|manjaro|garuda|endeavouros) echo "arch" ;;
    *)
      # 回退到 ID_LIKE
      for like in $OS_ID_LIKE; do
        case "$like" in
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

FAMILY=$(detect_family)

# 对于 RHEL 系，区分 fedora 和 el（影响 docker repo URL）
is_fedora=0
if [[ "$OS_ID" == "fedora" ]] || [[ "$OS_ID_LIKE" == *"fedora"* && "$OS_ID" != "rhel" && "$OS_ID" != "centos" && "$OS_ID" != "rocky" && "$OS_ID" != "almalinux" && "$OS_ID" != "ol" ]]; then
  is_fedora=1
fi

log "=== 检测到发行版 ==="
echo "  PRETTY_NAME : ${OS_PRETTY}"
echo "  ID          : ${OS_ID}"
echo "  ID_LIKE     : ${OS_ID_LIKE:-（无）}"
echo "  VERSION_ID  : ${OS_VERSION_ID:-（无）}"
echo "  家族归类    : ${FAMILY}"
[[ "$is_fedora" == "1" ]] && echo "  RHEL 子类  : Fedora（用 fedora docker repo）"
echo

case "$FAMILY" in
  debian) log "→ 走 Debian 系路径（apt）" ;;
  rhel)   log "→ 走 RHEL 系路径（dnf/yum）" ;;
  suse)   log "→ 走 openSUSE 系路径（zypper）" ;;
  arch)   log "→ 走 Arch 系路径（pacman）" ;;
  *)      die "不支持的发行版：${OS_ID}（ID_LIKE=${OS_ID_LIKE}）。请手动安装 Docker/certbot 后直接运行 deploy.sh" ;;
esac

# ---------------- 2. 包管理抽象 ----------------
pkg_install() {
  case "$FAMILY" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get install -y --no-install-recommends "$@"
      ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@"
      else
        yum install -y "$@"
      fi
      ;;
    suse)
      zypper --non-interactive --quiet install "$@"
      ;;
    arch)
      pacman -Sy --noconfirm --needed "$@"
      ;;
  esac
}

pkg_update() {
  case "$FAMILY" in
    debian) apt-get update -y ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then dnf makecache || true
      else yum makecache || true; fi
      ;;
    suse)   zypper --non-interactive refresh || true ;;
    arch)   pacman -Sy ;;
  esac
}

# ---------------- 3. 基础依赖安装 ----------------
log "=== 1. 系统更新与基础依赖 ==="
pkg_update

BASE_PKGS=(
  ca-certificates curl gnupg jq git vim htop tzdata fail2ban
)
case "$FAMILY" in
  debian) BASE_PKGS+=(lsb-release software-properties-common apt-transport-https ufw) ;;
  rhel)   BASE_PKGS+=(firewalld); command -v dnf >/dev/null 2>&1 || BASE_PKGS+=(yum-utils) ;;
  suse)   BASE_PKGS+=(firewalld) ;;
  arch)   BASE_PKGS+=(ufw) ;;
esac
# RHEL 9 的 tzdata 在 tzdata 包里；CentOS 8+ 也有；openSUSE 用 timezone 包
[[ "$FAMILY" == "suse" ]] && BASE_PKGS+=(timezone) || true

pkg_install "${BASE_PKGS[@]}"

# 时区
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-timezone Asia/Shanghai || true
else
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  echo "Asia/Shanghai" > /etc/timezone
fi

# ---------------- 4. Docker 官方仓库 ----------------
log "=== 2. 安装 Docker ==="
setup_docker_repo() {
  case "$FAMILY" in
    debian)
      install -m 0755 -d /etc/apt/keyrings
      # Debian/Ubuntu 用各自 ID 的 repo；Mint/Pop 复用 ubuntu
      local repo_id="$OS_ID"
      case "$OS_ID" in
        linuxmint|pop) repo_id="ubuntu" ;;
      esac
      if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL "https://download.docker.com/linux/${repo_id}/gpg" \
          | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
      fi
      local codename
      codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
      # Mint/Pop 的 VERSION_CODENAME 可能是 Mint 自己的（如 vanessa），需映射到 Ubuntu 代号
      if [[ "$OS_ID" == "linuxmint" || "$OS_ID" == "pop" ]]; then
        case "$codename" in
          vanessa|vera|victoria|virginia) codename="jammy" ;;
          uma|una) codename="focal" ;;
          tara|tessa|tina|tricia) codename="bionic" ;;
        esac
      fi
      [[ -z "$codename" ]] && codename="stable"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${repo_id} ${codename} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update -y
      ;;
    rhel)
      local repo_url
      if [[ "$is_fedora" == "1" ]]; then
        repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
      else
        repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
      fi
      if command -v dnf >/dev/null 2>&1; then
        dnf config-manager --add-repo "$repo_url"
      else
        yum-config-manager --add-repo "$repo_url"
      fi
      ;;
    suse)
      # openSUSE 用 zypper addrepo
      local repo_distro
      case "$OS_ID" in
        opensuse-tumbleweed|opensuse*) repo_distro="opensuse" ;;
        sles|suse) repo_distro="sles" ;;
      esac
      zypper --non-interactive addrepo "https://download.docker.com/linux/${repo_distro}/docker-ce.repo" docker-ce-stable
      zypper --non-interactive --gpg-auto-import-keys refresh
      ;;
    arch)
      : # Arch 官方仓库已包含 docker，无需额外 repo
      ;;
  esac
}

install_docker() {
  case "$FAMILY" in
    debian|rhel)
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    suse)
      # SUSE 的 docker 包名不同
      zypper --non-interactive install docker docker-cli docker-compose
      ;;
    arch)
      pkg_install docker docker-compose
      ;;
  esac
}

setup_docker_repo
install_docker
docker --version
docker compose version 2>/dev/null || docker-compose version 2>/dev/null || warn "docker compose 插件未检测到"

log "=== 3. 启动 Docker & 开机自启 ==="
systemctl enable --now docker
systemctl enable --now containerd 2>/dev/null || true

# ---------------- 5. 防火墙 ----------------
log "=== 4. 防火墙配置 ==="
setup_firewall() {
  case "$FAMILY" in
    debian|arch)
      if command -v ufw >/dev/null 2>&1; then
        ufw default deny incoming || true
        ufw default allow outgoing || true
        ufw allow ssh || ufw allow 22/tcp || true
        ufw allow 80/tcp || true
        ufw allow 443/tcp || true
        ufw --force enable || warn "UFW enable 失败，忽略"
        ufw status verbose || true
      else
        warn "ufw 未安装，请手动配置防火墙放行 22/80/443"
      fi
      ;;
    rhel|suse)
      if command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable --now firewalld 2>/dev/null || true
        firewall-cmd --permanent --add-service=ssh || firewall-cmd --permanent --add-port=22/tcp || true
        firewall-cmd --permanent --add-port=80/tcp || true
        firewall-cmd --permanent --add-port=443/tcp || true
        firewall-cmd --reload || true
        firewall-cmd --list-all || true
      else
        warn "firewalld 未安装，请手动放行 22/80/443"
      fi
      ;;
  esac
}
setup_firewall

log "=== 5. fail2ban 防爆破 ==="
systemctl enable --now fail2ban 2>/dev/null || warn "fail2ban 启动失败，继续"

# ---------------- 6. 目录结构 ----------------
log "=== 6. 创建目录结构 ==="
PROJECT_DIR="/opt/player2"
mkdir -p "${PROJECT_DIR}/deploy/certs"
mkdir -p "${PROJECT_DIR}/deploy/logs/nginx"
mkdir -p "${PROJECT_DIR}/backend" "${PROJECT_DIR}/web" "${PROJECT_DIR}/mod" "${PROJECT_DIR}/bridge"

# ---------------- 7. Certbot ----------------
log "=== 7. 安装 Certbot (Let's Encrypt) ==="
case "$FAMILY" in
  debian)
    pkg_install certbot python3-certbot-nginx 2>/dev/null || pkg_install certbot
    ;;
  rhel)
    # RHEL 系 certbot 在 EPEL 仓库，先启用 EPEL
    if ! rpm -q epel-release >/dev/null 2>&1; then
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y epel-release 2>/dev/null || warn "EPEL 安装失败，certbot 可能无法安装"
      else
        yum install -y epel-release 2>/dev/null || warn "EPEL 安装失败，certbot 可能无法安装"
      fi
      command -v dnf >/dev/null 2>&1 && dnf makecache || yum makecache || true
    fi
    pkg_install certbot python3-certbot-nginx 2>/dev/null || pkg_install certbot
    ;;
  suse)
    pkg_install certbot
    ;;
  arch)
    pkg_install certbot
    ;;
esac
command -v certbot >/dev/null 2>&1 && certbot --version || warn "certbot 安装失败，可后续手动安装"

# ---------------- 8. 系统调优 ----------------
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
sysctl -p /etc/sysctl.d/99-player2.conf 2>/dev/null || warn "sysctl 调优部分失败（可能是容器内运行）"

# limits.conf（所有发行版通用）
if [[ -f /etc/security/limits.conf ]]; then
  # 避免重复追加
  grep -q "99-player2" /etc/security/limits.conf 2>/dev/null || cat >> /etc/security/limits.conf <<'EOF'

# 99-player2-begin
* soft nofile 524288
* hard nofile 1048576
root soft nofile 524288
root hard nofile 1048576
# 99-player2-end
EOF
fi

# ---------------- 9. Docker daemon 调优 ----------------
log "=== 9. Docker daemon 配置 ==="
mkdir -p /etc/docker
# 原子写入：先写临时文件再替换，避免覆盖已有配置
TMP_DAEMON=$(mktemp)
cat > "$TMP_DAEMON" <<'EOF'
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
# 若已有 daemon.json 且包含 registry-mirrors，保留之
if [[ -f /etc/docker/daemon.json ]] && grep -q registry-mirrors /etc/docker/daemon.json 2>/dev/null; then
  warn "检测到已有 /etc/docker/daemon.json 含 registry-mirrors，保留原文件不覆盖"
  warn "如需应用 ulimit/log 调优，请手动合并 ${TMP_DAEMON} 到 /etc/docker/daemon.json"
else
  mv "$TMP_DAEMON" /etc/docker/daemon.json
fi
rm -f "$TMP_DAEMON"

# 中国网络环境可取消下面注释启用镜像加速
# if curl -sS --max-time 3 https://mirrors.aliyun.com/ >/dev/null 2>&1; then
#   warn "检测到中国网络环境，建议取消脚本中 registry-mirrors 注释启用加速"
# fi

systemctl restart docker

# ---------------- 完成 ----------------
log "=== 初始化完成（${FAMILY} / ${OS_PRETTY}） ==="
echo
echo "后续步骤："
echo "  1. 把项目代码上传到 ${PROJECT_DIR}"
echo "  2. cd ${PROJECT_DIR} && cp .env.example .env && nano .env   # 填 AI_API_KEY / JWT_SECRET"
echo "  3. 申请 SSL：certbot certonly --standalone -d ${DOMAIN} --register-unsafely-without-email --agree-tos"
echo "     或使用 DNS 验证（推荐）：certbot certonly --manual --preferred-challenges dns -d ${DOMAIN}"
echo "  4. 复制证书到 deploy/certs/：见 deploy/copy-certs.sh"
echo "  5. 预检：bash deploy/preflight.sh"
echo "  6. 启动服务：bash deploy/deploy.sh"
echo
