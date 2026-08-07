# Player2 · Linux 服务器完整搭建手册

> 适用系统：**Debian 12 (bookworm)** 为主要示例（手册以 apt/ufw 命令演示）。
> `deploy/init.sh` 已支持自动识别以下发行版，非 Debian 系会自动走对应包管理与防火墙：
> - **Debian 系**：Debian 11/12, Ubuntu 20.04+, LinuxMint, Pop!_OS（apt + ufw）
> - **RHEL 系**：RHEL 8/9, CentOS Stream, Rocky, AlmaLinux, Oracle Linux, Fedora（dnf/yum + firewalld，自动启用 EPEL）
> - **openSUSE 系**：Tumbleweed, Leap 15.5+（zypper + firewalld）
> - **Arch 系**：Arch, Manjaro（pacman + ufw）
>
> 下文遇到 `apt`/`ufw` 字样的命令，RHEL 系对应 `dnf`/`firewall-cmd`，openSUSE 对应 `zypper`/`firewall-cmd`，Arch 对应 `pacman`/`ufw`。直接跑 `bash deploy/init.sh` 即可自动适配。
>
> 服务域名：`player.qlm.org.cn`
> AI 大模型：`ai.bbsmc.org.cn` 上部署的 **DeepSeek R1**（OpenAI 兼容协议）
> 部署方式：Docker + Docker Compose v2（官方插件版 `docker compose`）

---

## 目录

- [0. 准备工作](#0-准备工作)
- [1. 上传项目代码到服务器](#1-上传项目代码到服务器)
- [2. Linux 系统初始化（跨发行版）](#2-linux-系统初始化跨发行版)
  - [2.1 一键脚本](#21-一键脚本)
  - [2.2 手动逐步执行（便于排查）](#22-手动逐步执行便于排查)
- [3. 配置环境变量 `.env`](#3-配置环境变量-env)
- [4. 测试 DeepSeek R1 连通性](#4-测试-deepseek-r1-连通性)
- [5. 申请 SSL 证书（HTTPS）](#5-申请-ssl-证书https)
- [6. 启动服务（deploy.sh 或手动）](#6-启动服务deploysh-或手动)
- [7. 验证服务可用](#7-验证服务可用)
- [8. 创建 AI 玩家并连接 Minecraft 服务器](#8-创建-ai-玩家并连接-minecraft-服务器)
- [9. 运维日常](#9-运维日常)
- [10. 国内网络环境加速专项](#10-国内网络环境加速专项)
- [11. 常见错误排查 (FAQ)](#11-常见错误排查-faq)

---

## 0. 准备工作

| 项目 | 要求 | 示例 |
|---|---|---|
| **服务器** | Debian 12 x86_64，2C4G 起步（建议 4C8G 跑 AI 决策网关）| 阿里云 / 腾讯云 / Vultr / 自建服务器 |
| **公网 IP** | 必须有，且开放 80/443 端口 | `1.2.3.4` |
| **域名** | 一个可配置 DNS 的域名 | `qlm.org.cn` |
| **DNS 记录** | 配置两条 A 记录指向服务器公网 IP | `A player.qlm.org.cn -> 1.2.3.4`<br>`A ai.bbsmc.org.cn -> 1.2.3.4`（若 AI 服务也在此机） |
| **AI API Key** | DeepSeek R1 的 API Key（或部署在 ai.bbsmc.org.cn 的自托管网关 Key） | `sk-xxxxxxxxxxxxxxxx` |
| **SSH 登录** | 有 root 权限或 sudo 权限的账号 | `ssh root@1.2.3.4` |
| **Minecraft 服务器** | 已经在运行的 Java 版 MC 服务器（可在同一台机或另一台） | `127.0.0.1:25565` |

> 💡 最低配置 2C4G 可跑：1 个后端 + 1 个前端 + Nginx + 5~10 个 AI 玩家决策。
> 💡 如果 `ai.bbsmc.org.cn` 的 **DeepSeek R1 服务本身**也部署在此机上，建议 8C32G + 24G 显存以上 GPU 单独跑模型。

### 0.1 域名 DNS 验证（本地先确认）

在自己的电脑上运行：

```bash
# macOS / Linux
dig +short player.qlm.org.cn
dig +short ai.bbsmc.org.cn

# Windows PowerShell
Resolve-DnsName player.qlm.org.cn
Resolve-DnsName ai.bbsmc.org.cn
```

返回值应该等于服务器公网 IP。如果没有生效，先到 DNS 控制台（阿里云 DNS / DNSPod / Cloudflare）确认。

### 0.2 云服务器安全组 / 防火墙开端口

**阿里云 / 腾讯云 Web 控制台安全组**必须放行：

| 协议 | 端口 | 来源 | 用途 |
|---|---|---|---|
| TCP | 22 | 0.0.0.0/0 | SSH 远程管理（建议改成你家 IP，更安全） |
| TCP | 80 | 0.0.0.0/0 | HTTP，Certbot 鉴权用 |
| TCP | 443 | 0.0.0.0/0 | HTTPS + WebSocket |
| TCP | 25565 | 0.0.0.0/0 | **如果 MC 服务器也在此机**，玩家连服用 |

---

## 1. 上传项目代码到服务器

### 方式 A：Git 仓库（推荐，便于后续升级）

本地电脑：

```bash
cd player22
git init && git add -A && git commit -m "init player2"
# 推送到 GitHub / Gitee / 自建 GitLab
git remote add origin git@gitee.com:你的用户名/player22.git
git push -u origin master
```

服务器上：

```bash
ssh root@你的服务器IP
apt-get update && apt-get install -y git
cd /opt
git clone git@gitee.com:你的用户名/player22.git
cd /opt/player22
```

### 方式 B：tar 包直传（无 Git）

本地电脑（Windows 下用 PowerShell / Git Bash）：

```powershell
cd C:\Users\Administrator\Desktop\player22
tar -czf player22.tar.gz --exclude=node_modules --exclude=.git --exclude=dist .
scp player22.tar.gz root@你的服务器IP:/opt/
```

服务器上：

```bash
cd /opt
tar -xzf player22.tar.gz && rm player22.tar.gz
# 项目根目录就是 /opt/player22，下面所有命令默认在这里执行
cd /opt/player22
```

---

## 2. Linux 系统初始化（跨发行版）

给脚本可执行权限：

```bash
cd /opt/player22
chmod +x deploy/*.sh
ls deploy/*.sh
# init.sh  init-debian.sh  deploy.sh  copy-certs.sh  logs.sh  preflight.sh  status.sh  test-ai.sh
```

### 2.1 一键脚本

```bash
sudo bash deploy/init.sh
# 全程无交互约 3~10 分钟，取决于网络
# Debian/Ubuntu 用户也可继续用 bash deploy/init-debian.sh（兼容入口，转发到 init.sh）
```

脚本会自动识别发行版并做这些事（详见 [init.sh](deploy/init.sh)）：

1. 刷新包索引并装基础工具（curl/fail2ban/git/vim/htop/jq/tzdata 等）
2. 装 **Docker 官方版** + **Compose v2 插件**（按发行版添加官方仓库；Arch 用官方源）
3. 启用 Docker 开机自启
4. 防火墙：Debian/Arch 用 ufw，RHEL/openSUSE 用 firewalld；只允许 22(ssh) / 80(http) / 443(https)
5. fail2ban 防爆破 SSH
6. 创建部署目录 `/opt/player2/...`
7. 装 **certbot**（Let's Encrypt 免费证书；RHEL 系自动启用 EPEL）
8. sysctl 调优：`fs.file-max=1M`、`somaxconn=65535`、`tcp_tw_reuse` 以撑 WebSocket 长连接
9. 写 `/etc/security/limits.conf` nofile 上限
10. Docker daemon.json：日志轮转 50M×3 份

#### 脚本跑完验证

```bash
docker --version           # 应显示 26.x 以上
docker compose version     # 应显示 v2.x（关键：不是 docker-compose）
ufw status verbose         # 应 Status: active + 22/80/443 ALLOW IN
systemctl is-enabled docker
systemctl is-enabled fail2ban
```

### 2.2 手动逐步执行（便于排查）

如果一键脚本中途失败，或你想手动控制每一步：

<details><summary>👉 点击展开手动步骤</summary>

```bash
# ========== 1. APT ==========
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common ufw fail2ban htop vim git jq tzdata
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# ========== 2. Docker ==========
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
systemctl enable --now containerd

# ========== 3. UFW ==========
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose

# ========== 4. fail2ban ==========
systemctl enable --now fail2ban

# ========== 5. Certbot ==========
apt-get install -y --no-install-recommends certbot python3-certbot-nginx

# ========== 6. sysctl + limits ==========
cat > /etc/sysctl.d/99-player2.conf <<'EOF'
fs.file-max = 1048576
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.netfilter.nf_conntrack_max = 1048576
EOF
sysctl -p /etc/sysctl.d/99-player2.conf || true

cat >> /etc/security/limits.conf <<'EOF'
*    soft nofile 524288
*    hard nofile 1048576
root soft nofile 524288
root hard nofile 1048576
EOF

# ========== 7. Docker 日志轮转 ==========
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" },
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 524288 }
  }
}
EOF
systemctl restart docker

mkdir -p /opt/player22/deploy/{certs,logs/nginx}
```
</details>

---

## 3. 配置环境变量 `.env`

所有密钥、域名、模型名都在项目根目录 **唯一一份 `.env`** 中管理（单一事实来源，避免配置漂移）。

```bash
cd /opt/player22
cp .env.example .env
nano .env
```

`.env` 每一项解释：

```ini
# ── AI 大模型 (DeepSeek R1 @ ai.bbsmc.org.cn) ──
# 如果 ai.bbsmc.org.cn 是你自己部署的 R1 兼容网关（OneAPI / vLLM / Ollama OpenAI 兼容层），
# 就填那个地址；官方 DeepSeek 则是 https://api.deepseek.com/v1
AI_API_URL=https://ai.bbsmc.org.cn/v1

# DeepSeek R1 的 API Key。一定不要提交到 Git！
AI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 决策用模型：推理模型名；若你是官方 DeepSeek 平台就是 "deepseek-reasoner"
# 若是自托管 R1 + vLLM/OneAPI，填部署时自定义的 model 名称
AI_MODEL=deepseek-reasoner

# 聊天用模型（可选，单独指定以节省推理成本；不填则复用 AI_MODEL）
# 官方 DeepSeek 是 "deepseek-chat"
AI_CHAT_MODEL=deepseek-chat

# ── 登录鉴权 ──
# 至少 32 位随机字符串，决定用户 Web/EXE 登录时签发的 JWT
# 生成命令：openssl rand -hex 32
JWT_SECRET=d0f3a1f9bd4c7a7c1b6d9e2c4f8a5b2d7c9e1f4a5b6c8d0e2f4a6b8c0d2e4f6

# ── 注释用，不被 compose 读取 ──
DOMAIN=player.qlm.org.cn
```

保存退出后：

```bash
# ⚠️  权限收紧，只允许 root 读（API Key 是明文）
chmod 600 .env
ls -la .env
# -rw------- 1 root root ... .env  ✅
```

快速验证读出来的内容：

```bash
grep -E '^[A-Z_]+=' .env | sed 's/=.*/=***/'
# AI_API_URL=***
# AI_API_KEY=***
# AI_MODEL=***
# ...
```

---

## 4. 测试 DeepSeek R1 连通性

**这一步必须先过，否则后端上线后 AI 玩家全呆站。**

```bash
cd /opt/player22
bash deploy/test-ai.sh
```

正常输出示例：

```
======== DeepSeek R1 连通性测试 ========
Endpoint : https://ai.bbsmc.org.cn/v1/chat/completions
Model    : deepseek-reasoner
Key      : sk-xxxxx...xxxx

HTTP 耗时 : 8342 ms

usage  : {"prompt_tokens": 42, "completion_tokens": 13, "total_tokens": 55}
thinking(1200chars):  我先分析任务：用户要求只输出 JSON。最简单...
content (28 chars): {"ok":true}

若以上有 usage + content 非空，则 ai.bbsmc.org.cn + DeepSeek R1 配置正确。
```

**常见失败：**

| 错误 | 排查方法 |
|---|---|
| `Could not resolve host: ai.bbsmc.org.cn` | DNS 没解析。`ping ai.bbsmc.org.cn` 或 `dig` 看 A 记录是否指向服务器；若 AI 就在本机，也可以写 `https://127.0.0.1:8000/v1` + `curl -k` 忽略证书 |
| `401 Unauthorized / invalid_api_key` | `AI_API_KEY` 错了；去 [.env](.env) 改；若用 OneAPI 记得给该 Key 绑 R1 模型权限 |
| `404 / model not found` | `AI_MODEL` 名不对；官方 DeepSeek 是 `deepseek-reasoner`；自托管要和启动 vLLM/OneAPI 时写的一致 |
| `curl: (28) Operation timed out` | 服务器出口被墙 / 云安全组没放 443 出站；`curl -I https://ai.bbsmc.org.cn` 单独测 |
| `429 Too Many Requests` | 并发限额；生产建议加请求队列 + 缓存同感知 |
| `502 Bad Gateway / 503 Upstream Error` | `ai.bbsmc.org.cn` 的 R1 网关挂了，找网关运维 |

---

## 5. 申请 SSL 证书（HTTPS）

必须有 HTTPS，因为：
1. 浏览器端 `wss://` 仅在 HTTPS 页面下才能连
2. 用户 Bridge EXE 用 `wss://player.qlm.org.cn` 加密通信，防抓包
3. Let's Encrypt 免费，certbot 自动续期

**前提**：DNS A 记录已生效。

### 方式 A：Standalone（最稳，推荐首次使用）

```bash
# ⚠️  先确保 80 端口没被占用：
ss -ltnp | grep :80   # 如果 nginx/apache 占了就 systemctl stop nginx

certbot certonly \
  --standalone \
  -d player.qlm.org.cn \
  -m admin@qlm.org.cn \
  --agree-tos \
  --no-eff-email
```

成功后证书位置：

```
/etc/letsencrypt/live/player.qlm.org.cn/fullchain.pem
/etc/letsencrypt/live/player.qlm.org.cn/privkey.pem
```

### 方式 B：DNS 手动验证（推荐用 Cloudflare / DNSPod API，或要做泛域名时用）

```bash
certbot certonly \
  --manual --preferred-challenges dns \
  -d player.qlm.org.cn \
  -m admin@qlm.org.cn --agree-tos
```

按提示去 DNS 控制台加一条 `_acme-challenge.player.qlm.org.cn` 的 TXT 记录即可。

### 方式 C：Nginx 插件（后续 renew 时用，现在还没 nginx 容器可跳过）

```bash
certbot --nginx -d player.qlm.org.cn -m admin@qlm.org.cn --agree-tos
```

### 5.1 复制证书到项目目录

一键部署脚本 `deploy.sh` 会**自动复制**；也可以手动跑一次：

```bash
bash deploy/copy-certs.sh player.qlm.org.cn
```

### 5.2 自动续期

Certbot 一般装好会自带 systemd timer：

```bash
systemctl list-timers certbot.timer
# NEXT LEFT LAST PASSED UNIT ACTIVATES
# 每月跑一次就对
```

**加一个 renew 后 reload nginx 的 deploy hook：**

```bash
cat > /etc/letsencrypt/renewal-hooks/deploy/player2.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# 针对 player.qlm.org.cn 续期成功时复制证书并重启 nginx 容器
for domain in $RENEWED_DOMAINS; do
  if [ "$domain" = "player.qlm.org.cn" ]; then
    bash /opt/player22/deploy/copy-certs.sh player.qlm.org.cn
  fi
done
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/player2.sh
```

然后测试 dry-run：

```bash
certbot renew --dry-run
# 最后看到 "dry run succeeded" = OK
```

---

## 6. 启动服务（deploy.sh 或手动）

### 6.1 推荐：一键部署脚本

```bash
cd /opt/player22
bash deploy/deploy.sh
```

脚本步骤：

1. 检查 `.env` 是否存在占位符（`change_this` / `your_real`），有则交互式询问
2. 自动把 `/etc/letsencrypt/live/player.qlm.org.cn/*.pem` 复制到 `deploy/certs/`
3. 没有证书则用 openssl 生成 7 天自签证书（仅测试，浏览器会报警）
4. `docker compose build --pull` 拉取 Debian 基础镜像并构建后端/前端
5. `docker compose down` 停旧容器
6. `docker compose up -d` 起新容器
7. 轮询 60s 等待 backend / web 健康 healthy
8. 最后 `docker compose ps` 展示状态

### 6.2 手动逐步（便于排查）

```bash
cd /opt/player22

# 1) 先构建，看清构建日志
docker compose build --progress=plain 2>&1 | tee /tmp/build.log
# 末尾应该 2 个镜像都 Successfully built

# 2) 先后台启动，不看日志
docker compose up -d

# 3) 看容器起来没
watch -n 2 docker compose ps
# 3 个容器：player2-backend / player2-web / player2-nginx  都应该 Up (healthy)
# 若还在 health: starting，等 10~30 秒
```

---

## 7. 验证服务可用

### 7.1 本机（服务器自身）

```bash
# 后端健康检查
curl -s http://127.0.0.1:8080/health
# {"status":"ok","onlineClients":{"bridges":0,"webs":0}}

# Nginx 80 -> 301 跳转
curl -I http://127.0.0.1/
# HTTP/1.1 301 Moved Permanently -> https://player.qlm.org.cn/

# HTTPS 主页
curl -skI https://127.0.0.1/ --resolve player.qlm.org.cn:443:127.0.0.1
# HTTP/2 200
```

### 7.2 外网（自己的电脑浏览器）

浏览器访问：<https://player.qlm.org.cn>

1. 地址栏小锁 ✅ （SSL 证书有效）
2. 跳转到登录页 ✅
3. 默认账号 `admin` / 密码 `admin123` 登录成功 ✅
4. 左上角连接状态显示 **已连接**（绿色标签）✅

> ⚠️  **生产一定要改 admin 密码！** 编辑文件 [backend/src/middleware/auth.js](backend/src/middleware/auth.js) 里的 `users` Map，或改成数据库/Redis 查表。部署完成后一定要重新 `bash deploy/deploy.sh` 生效。

### 7.3 WebSocket 连通

浏览器 F12 → Network → 筛选 `WS` 或 `WebSockets` → 刷新页面：

- 看到 `/?EIO=4&transport=websocket` 请求
- Status `101 Switching Protocols`
- Frames 标签页有持续双向 ping/pong

这表示前端控制台 ↔ 后端 Socket.IO **双向实时通道**通了。

### 7.4 完整健康巡检脚本

```bash
bash deploy/status.sh
```

会输出容器健康 / 磁盘占用 / 证书剩余天数 / AI 连通性，一眼看全。

---

## 8. 创建 AI 玩家并连接 Minecraft 服务器

### 路径 A：Bridge EXE（普通玩家用，无需服主改 MC 核心）

在要运行 AI 玩家的 **Windows 电脑**上：

1. 把项目 `bridge/` 文件夹拷过去（或发布到下载站）。
2. 改 `bridge/.env`：

```ini
BACKEND_WS=wss://player.qlm.org.cn
TOKEN=xxxxxxxxxxxxxxxx       # 这里的值先从下一步拿
MC_SERVER=你的MC服务器IP
MC_PORT=25565
MC_VERSION=1.20.1
PLAYER_NAME=AI_Miner_01
PERCEPTION_INTERVAL_MS=2000
```

**拿 JWT TOKEN（两种方法）**：

- **法 1：浏览器开发者工具** → 登录 `player.qlm.org.cn` → Application → Local Storage → `token` 字段，一整串复制。
- **法 2：命令行拿**（服务器上跑）：
  ```bash
  curl -sS -X POST https://player.qlm.org.cn/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' | jq -r .token
  ```

3. 启动 Bridge：
   - 已打包成 EXE → 双击 `dist/AIPlayer.exe`
   - 源码运行 → 装 Node 20 → `npm install && npm start`

4. 回到网页 <https://player.qlm.org.cn>：
   - 左侧玩家列表出现 `AI_Miner_01`（Bridge 连上 backend 后会自动有事件）
   - 发快速指令 **前进 / 跳跃 / 停止**，MC 客户端里看这个假玩家有相应动作 ✅
   - 发聊天：在 MC 里用另一个号对 AI 说 "你好"，几秒后 AI 回复 ✅

### 路径 B：Forge Mod（服主使用，直接在 MC 服务器里造假玩家）

1. 本地 `cd mod && ./gradlew build`，拿 `build/libs/player2-1.0.0.jar`
2. 丢入 MC 服务器 `mods/` 文件夹，重启服务器
3. 进游戏服主号输入：

```minecraft
/p2 connect wss://player.qlm.org.cn eyJhbGciOi..........（刚才拿的 JWT token）
/p2 spawn AI_Builder   # 在世界里创建一个叫 AI_Builder 的假玩家
/p2 list
# AI 玩家 (1): AI_Builder
```

4. Mod 会以 `type=bridge` 身份连后端 WebSocket，自动每 1.5s 推送感知，接收动作。

---

## 9. 运维日常

### 9.1 看日志

```bash
cd /opt/player22
# 实时 3 个服务混看
bash deploy/logs.sh all 300

# 只看后端（AI 决策、WebSocket 事件）
bash deploy/logs.sh backend

# 只看 Nginx（真实用户访问 IP / 404 / 502）
bash deploy/logs.sh nginx | grep -E ' 404 | 502 | socket.io'
```

### 9.2 升级

```bash
cd /opt/player22
git pull          # 拉新代码
# 或者手动上传覆盖文件

bash deploy/deploy.sh        # 全量构建重启（稳妥）

# 只改了前端代码？快速重构建一个服务：
docker compose up -d --build web
# 只改了后端代码：
docker compose up -d --build backend
```

### 9.3 备份

```bash
cd /opt/player22
# 把配置/证书/日志一起打包
mkdir -p /backup
tar -czf /backup/player22-backup-$(date +%F).tar.gz \
  .env deploy/certs deploy/logs deploy/nginx.conf docker-compose.yml \
  backend/.env backend/src  web/src
# 保留最近 7 天
find /backup -name 'player22-backup-*.tar.gz' -mtime +7 -delete
```

建议加到 crontab：

```bash
(crontab -l 2>/dev/null; echo "0 3 * * * cd /opt/player22 && mkdir -p /backup && tar -czf /backup/player22-backup-\$(date +\%F).tar.gz .env deploy/certs docker-compose.yml backend/src web/src > /dev/null 2>&1 && find /backup -name 'player22-backup-*.tar.gz' -mtime +7 -delete") | crontab -
```

---

## 10. 国内网络环境加速专项

如果服务器在中国大陆，**官方 Docker Hub / Debian apt / npm registry** 都会很慢甚至超时，下面的加速方案一定要做。

### 10.1 APT 换国内源

```bash
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Debian 12 bookworm (清华源)
cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
apt-get update -y
```

### 10.2 Docker 镜像加速

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" },
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 524288 }
  }
}
EOF
systemctl daemon-reload && systemctl restart docker

# 验证加速生效：拉一个小镜像测速
time docker pull --platform=linux/amd64 alpine:3.20
# 没加速可能 30~120s；加速后 3~10s
```

> ⚠️  上面写的公共加速站可能随时失效；如果 `docker pull` 仍然超时，换成阿里云「容器镜像服务 ACR」个人专属加速地址（每个账号唯一，登录阿里云控制台 ACR→镜像加速器获取）。

### 10.3 npm 加速（构建镜像里用，Dockerfile 里已经支持传入）

如果 `npm ci` 仍然慢，可以在 `docker compose build` 之前加一层 **npm proxy**：

```bash
# 临时在宿主机装 verdaccio 没必要；更快的做法是改 Dockerfile 加一层 npm config：
# 已下方式也可以：
cd /opt/player22
docker compose build --build-arg NPM_CONFIG_REGISTRY=https://registry.npmmirror.com backend web
```

或直接改 [backend/Dockerfile](backend/Dockerfile) 和 [web/Dockerfile](web/Dockerfile) 里的 `npm ci` 前面加一行：

```dockerfile
RUN npm config set registry https://registry.npmmirror.com
```

### 10.4 DeepSeek R1 自托管加速

如果 `ai.bbsmc.org.cn` 是你在国内服务器上部署的 R1（vLLM / LMDeploy / SGLang）：
- **和 player.qlm.org.cn 放同一机房 / 同一内网 VPC**，调用 AI 走内网 IP（`http://10.0.0.5:8000/v1`），省出口带宽 + 延迟从 50ms→<1ms
- `.env` 改成 `AI_API_URL=http://内网IP:端口/v1`，不用走 HTTPS 也省证书开销

---

## 11. 常见错误排查 (FAQ)

### ❌ Q1：`docker compose build` 时提示 `command not found`

```bash
# 检查安装
docker compose version
# -bash: docker-compose: command not found   ← 不是这个命令！
# Docker Compose v2 是插件版，命令是：
docker compose version     # （中间是空格，不是横杠）

# 如果真没装，手动补装 Compose v2：
apt-get install -y --no-install-recommends docker-compose-plugin
```

### ❌ Q2：容器都 `Up` 但浏览器打不开域名

```
症状：浏览器 ERR_CONNECTION_TIMED_OUT
```

1. **本机先测**：`curl -sS --resolve player.qlm.org.cn:443:服务器公网IP https://player.qlm.org.cn -I`
   - 本机能通，浏览器不通 → 是你本地网络/DNS 缓存问题；换 4G 热点测一次
   - 本机也不通 → 服务器侧问题，继续
2. **服务器上测监听**：`ss -ltnp | grep -E ':80|:443'`，应该看到 `nginx` 进程在 LISTEN
   - 没有监听 → `docker compose ps` 看 nginx 是不是没起来
3. **本机直连 IP**：`curl -sS -I http://服务器公网IP/` 看有没有 301/200
   - 直连 IP 能通，域名不通 → DNS A 记录没生效
   - 直连 IP 也不通 → 安全组 / UFW；`ufw status` 看 80/443 是否开了；阿里云/腾讯云控制台安全组看入站规则
4. **容器日志看 nginx 报错**：`bash deploy/logs.sh nginx 50`

### ❌ Q3：登录后浏览器左上角还是「未连接」

WebSocket 没连上。F12 → Console 应该看到 `WebSocket connection to 'wss://...' failed`

1. Nginx `/socket.io/` location 配置正确否？文件 [deploy/nginx.conf](deploy/nginx.conf#L59-L75)
2. 后端容器真的启动了吗？`curl http://127.0.0.1:8080/health`；不是 healthy 就 `bash deploy/logs.sh backend` 看崩溃日志
3. 最常见：**nginx 没 reload** 导致还是旧配置。`docker compose restart nginx` 或 `docker compose exec nginx nginx -s reload`
4. 如果前面挂了 Cloudflare CDN：Cloudflare SSL 必须选「Full (strict)」且启用 WebSocket（默认启用）。Network → Compression → WebSockets：On

### ❌ Q4：Bridge / Mod 连接 WebSocket 报 `401 Unauthorized`

JWT 无效。生成一个新的：

```bash
curl -sS -X POST https://player.qlm.org.cn/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

把完整 `.token` 字符串粘贴到 Bridge `.env` 的 `TOKEN=` 或 Mod 的 `/p2 connect <url> <token>` 后面。

### ❌ Q5：Bridge 成功连上 MC，但 AI 什么都不做（原地呆站）

**排查链路：Bridge 推感知 → 后端收 → 调 DeepSeek R1 → 返回动作 → Bridge 执行**

1. `bash deploy/logs.sh backend 200 | grep -E 'perception|AI'`
   - 完全看不到 `perception` 事件 → Bridge → Backend 的 WebSocket 没传；看 Bridge 控制台报错
   - 看到 `[AI Call failed]` → AI 网关问题；`bash deploy/test-ai.sh` 再测一次
   - 能看到 `perception` 进，但没有 `actions` → JSON 解析失败；`grep 'JSON parse fail' backend 日志`，通常是 R1 思维链太长，最后 JSON 被截断。临时缓解：
     - 提高 `AI_CHAT_MODEL` 决策用最大 tokens（当前代码未设置 `max_completion_tokens`，可在 `aiOrchestrator.js` 的 payload 里加 `max_tokens: 2000`）
     - 简化感知（减小 `PERCEPTION_INTERVAL_MS`？不，是截断长度；在 `_buildPerceptionPrompt` 里把附近方块从 20 条调到 10 条）

2. 后端能看到 `player:actions` emit，但 MC 里没动 → Bridge 收到但没执行；检查 Bridge 控制台 `[Actions] x action(s)` 有没有打印；没有就是 `playerId` 对不上（MC 的玩家名 vs 创建时写的 name）

### ❌ Q6：AI 动作卡顿 / 每 10 秒才动一次

DeepSeek R1 推理慢是正常的（670B 模型首 token 3~8s）。优化：

1. `PERCEPTION_INTERVAL_MS` 改成 3000~5000，不要密集推
2. 同一位置 + 周围没变化就跳过 AI 调用（代码里加 diff 判断 `perception` 和上次的差异度）
3. 开 "决策 + 短期行为脚本" 模式（例如 AI 一次输出「挖 3 个石头方块」，Bridge 收到后连续 3 次挖，中间不重新推感知）
4. 自托管 **DeepSeek R1-Distill-Lite 7B/8B 量化版**（vLLM AWQ 4bit），在 4090 上单卡首 token <0.5s
5. 决策用 R1、聊天用 deepseek-chat，聊天不要浪费推理算力（已在 `.env` 里 `AI_CHAT_MODEL=deepseek-chat`）

### ❌ Q7：容器日志撑爆磁盘

`deploy/init.sh` 和 compose 文件里都写了 Docker 日志轮转：`max-size=50m max-file=3`。单容器最多 150M，容器合计数百 MB。

如果还是磁盘满：

```bash
# 看谁占用大
docker system df -v
# 清未使用镜像 / 缓存 / 停止容器
docker system prune -af
# 手动截断某个大日志
truncate -s 0 $(docker inspect -f='{{.LogPath}}' player2-nginx)
```

### ❌ Q8：SSL 证书过期

`bash deploy/status.sh` 最后一块会看剩余天数；< 15 天就黄色告警。

```bash
# 手动续一次
certbot renew
bash deploy/copy-certs.sh player.qlm.org.cn
```

---

## 附录：关键文件 / 命令速查

| 想做的事 | 命令 / 位置 |
|---|---|
| 改默认 admin 密码 | [backend/src/middleware/auth.js](backend/src/middleware/auth.js#L7-L9) `users` Map |
| 改 AI 提示词 / 加策略 | [backend/src/services/aiOrchestrator.js](backend/src/services/aiOrchestrator.js#L10-L37) `promptTemplates` |
| 改 AI 模型名 | `.env` 的 `AI_MODEL` 和 `AI_CHAT_MODEL` |
| 改前端端口或 API 代理 | [web/vite.config.js](web/vite.config.js) |
| 改 Nginx 反代 | [deploy/nginx.conf](deploy/nginx.conf)，改完 `docker compose restart nginx` |
| 重启所有服务 | `cd /opt/player22 && docker compose restart` |
| 重新构建 + 启动 | `bash deploy/deploy.sh` |
| 看所有容器状态 | `bash deploy/status.sh` |
| 看实时日志 | `bash deploy/logs.sh all` |
| 测 AI 通不通 | `bash deploy/test-ai.sh` |

---

**祝部署顺利！** 🎉 如果某一步卡住，优先跑 `bash deploy/status.sh` + `bash deploy/logs.sh` 贴出来的报错信息做排查。
