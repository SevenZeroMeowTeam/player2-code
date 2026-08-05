# Player2 · 基于 DeepSeek R1 的 Minecraft AI 玩家系统

[![Docker](https://img.shields.io/badge/Docker-Ready-blue)](#六生产部署)
[![Node 20](https://img.shields.io/badge/Node-20.x-green)](#一本地开发)
[![MC 1.20.1](https://img.shields.io/badge/Minecraft-1.20.1-green)](#模组mod)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](#LICENSE)

Player2 是一套完整的、可自托管的 Minecraft AI 玩家平台：使用 DeepSeek R1 推理模型做决策，Web 面板管生命周期，Forge 模组 / Mineflayer 双端接入，支持感知-决策-行动闭环。

```
 用户 (Web)
    │  (创建AI玩家 / 下发指令 / 看实时画面)
    ▼
┌─────────────────────────────────────────┐
│           backend (Node.js)             │
│  Express REST + Socket.IO 实时总线      │
│  ├─ auth : JWT 鉴权                     │
│  ├─ clientRegistry : Bridge/Web 注册   │
│  └─ aiOrchestrator : DeepSeek R1 调用  │
└──────────┬──────────────────────────────┘
           │ Socket.IO
     ┌─────┴────────────┐
     ▼                  ▼
 Bridge (Mineflayer)   Forge Mod (Kotlin)
 (Node 端假玩家)       (MC 1.20.1 服务端模组)
     │                  │
     └──────┬───────────┘
            ▼
     Minecraft 1.20.1 服务器
```

---

## 功能特性

- 🤖 **DeepSeek R1 原生推理**：支持 `reasoning_content` 思维链可视化，AI 边想边做
- 🎮 **双端接入**：Forge 服务端模组（无 Hack 客户端，合规） + Mineflayer（快速本地体验）
- 🧠 **感知-决策-行动闭环**：视野 / 背包 / 生命 / 坐标 → R1 → 移动/跳跃/挖掘/攻击
- 🌐 **Web 管理面板**：Vue 3 + Element Plus，创建、启停、调参、日志一站式
- 🔐 **JWT 多租户**：每个用户独立 AI 玩家配额，互不干扰
- 🐳 **Docker 一键部署**：nginx + HSTS + WebSocket 长连接 + 证书自动签
- ⚡ **双 AI 网关回退**：优先 `ai.bbsmc.org.cn`，失败自动切 `api.deepseek.com`

---

## 目录结构

```
player22/
├── backend/              # Node.js 服务端 (REST + Socket.IO + AI 编排)
│   ├── src/
│   │   ├── server.js
│   │   ├── middleware/auth.js
│   │   └── services/
│   │       ├── aiOrchestrator.js   # DeepSeek R1 适配层
│   │       └── clientRegistry.js   # Web/Bridge 连接注册表
│   ├── Dockerfile
│   └── .env.example
├── web/                  # Vue 3 管理面板 (Element Plus + Pinia)
│   ├── src/views/{Login,Dashboard,PlayerDetail}.vue
│   ├── Dockerfile
│   └── vite.config.js
├── bridge/               # Mineflayer 假玩家 (可 pkg 打包 Windows EXE)
│   ├── src/{bridge,perception,actions}.js
│   └── .env.example
├── mod/                  # Forge 1.20.1 服务端模组 (Kotlin)
│   └── src/main/kotlin/cn/qlm/player2/
│       ├── Player2Mod.kt
│       ├── Config.kt
│       ├── bridge/WsBridgeClient.kt
│       ├── command/Player2Commands.kt
│       └── manager/{FakePlayerManager,PerceptionCollector,ActionExecutor}.kt
├── deploy/               # Debian 12 生产部署脚本
│   ├── init-debian.sh    # 系统初始化 (docker/compose/certbot/防火墙)
│   ├── preflight.sh      # 部署前预检 (环境/权限/端口/依赖)
│   ├── deploy.sh         # 构建 + docker compose up -d
│   ├── test-ai.sh        # AI 网关连通性测试 (Linux)
│   ├── test-ai.ps1       # AI 网关连通性测试 (Windows)
│   ├── copy-certs.sh     # certbot 证书软链到 deploy/certs/
│   ├── logs.sh / status.sh
│   ├── nginx.conf        # HSTS + WebSocket 7200s + gzip + 80→301→443
│   └── LINUX_SETUP.md    # 11 章超详细部署手册
├── .env.example
├── .gitignore
├── docker-compose.yml    # backend + web + nginx 三容器编排
└── README.md
```

---

## 一、本地开发

### 0. 前置

- Node.js ≥ **20.x**
- JDK **17**（仅编译模组时需要）
- 一个可用的 DeepSeek API Key（[platform.deepseek.com](https://platform.deepseek.com/) 申请）

### 1. 启动后端

```bash
cd backend
cp .env.example .env
# 编辑器打开 .env，至少填 AI_API_KEY=sk-xxxx
npm install
npm run dev     # http://127.0.0.1:8080/health
```

Windows 下快速验证 AI 网关：
```powershell
powershell -ExecutionPolicy Bypass -File deploy\test-ai.ps1
```

### 2. 启动 Web 面板

```bash
cd web
npm install
npm run dev     # http://localhost:5173
```

默认登录（backend 默认管理员账号，可在 `auth.js` 修改）：
- 用户：`admin`
- 密码：`player2_admin`（**生产必须改**）

### 3. 启动 Bridge（Mineflayer 假玩家）

桥接端把 backend 的决策转成 Minecraft 协议动作：

```bash
cd bridge
cp .env.example .env
# 填 BACKEND_WS、MC_SERVER、MC_PORT、PLAYER_NAME
npm install
npm start
```

启动后在 MC 服务器内可看到 `AIPlayer_01` 加入游戏。

### 模组 (mod/)

Kotlin + Forge 1.20.1，需要服务端跑 MC 服务器时使用：

```bash
cd mod
./gradlew build      # 产出 mod/build/libs/player2-1.0.0.jar
```

放到 `mods/` 目录启动服务端，编辑 `config/player2.json` 填写后端 WebSocket 地址与 JWT。

---

## 二、环境变量（.env）

密钥**唯一事实来源**：项目根 `.env`。`backend/.env`、`bridge/.env` 仅作本地覆盖，**生产部署只有根 `.env` 生效**（docker-compose `env_file: .env`）。

| 变量 | 必填 | 说明 |
|------|:----:|------|
| `AI_API_URL` | ✅ | `https://ai.bbsmc.org.cn/v1`（推荐，国内稳定）或 `https://api.deepseek.com/v1` |
| `AI_API_KEY` | ✅ | `sk-` 开头的 DeepSeek Key |
| `AI_MODEL` | ✅ | `deepseek-reasoner`（R1 推理） / `deepseek-chat` |
| `AI_CHAT_MODEL` |  | 聊天模型，默认复用 `AI_MODEL` |
| `JWT_SECRET` | ✅ | 32 字节以上随机串，生产用 `openssl rand -hex 32` 生成 |
| `DOMAIN` |  | 生产域名，certbot/bridge 使用，如 `player.qlm.org.cn` |

---

## 三、AI 网关双回退策略

`aiOrchestrator.js` + `deploy/test-ai.{sh,ps1}` 统一按如下顺序尝试：

```
1) https://ai.bbsmc.org.cn/v1    (自建/中转，国内低延迟)
        ↓ 失败（DNS/TLS/4xx/5xx/超时）
2) https://api.deepseek.com/v1   (官方，海外 IP)
```

后端内部首次失败会自动切换到下一个可用 URL，无需重启。

---

## 四、常见问题

**Q：后端健康检查 `/health` 正常，但 Web 连接不上？**
A：检查 docker-compose `ports` 是否只绑定 `127.0.0.1:8080`（生产应只让 nginx 访问）；直接访问的话改为 `0.0.0.0:8080` 或走 nginx 反代。

**Q：AI 玩家创建后没加入服务器？**
A：① bridge / Forge mod 是否连上后端（看 `status.sh` 里 `clientRegistry` 有 bridge 吗）；② MC 服务器是否开启 `online-mode=false` 与白名单；③ 控制台报 `Invalid session` 就关正版验证。

**Q：调用 R1 返回 429 / 余额不足？**
A：登录 DeepSeek 控制台看额度；`test-ai.sh` 返回里的 `usage.prompt_tokens/completion_tokens` 可用来估算账单。

**Q：`openssl rand` 没有？**
A：Windows 用 PowerShell 生 JWT_SECRET：
```powershell
$b = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
($b | % { $_.ToString('x2') }) -join ''
```

更多问题见 [deploy/LINUX_SETUP.md](deploy/LINUX_SETUP.md) 的 FAQ 章节。

---

## 五、Docker 本地快速预览

```bash
# 1) 准备环境
cp .env.example .env && nano .env        # 填 AI_API_KEY + JWT_SECRET

# 2) 起服务（backend + web + nginx）
docker compose up -d --build

# 3) 验证
curl -I http://localhost/                  # nginx 返回 200
curl http://localhost/health               # {"status":"ok","onlineClients":0}
```

本地无证书时 nginx.conf 注释掉 `443 ssl` 块，只用 80。

---

## 六、生产部署（Debian 12 6 步速查）

域名：`player.qlm.org.cn`，提前把 A 记录指向服务器公网 IP。

```bash
# ① 克隆 + 系统初始化（docker/compose/certbot/UFW/自动更新）
git clone <YOUR_REPO> player22 && cd player22
bash deploy/init-debian.sh

# ② 填密钥（只改 AI_API_KEY 那行）
cp .env.example .env && nano .env
chmod 600 .env

# ③ 预检（任何 FAIL 先修）
bash deploy/preflight.sh

# ④ 签证书（域名 DNS 已生效）
certbot certonly --standalone -d player.qlm.org.cn
bash deploy/copy-certs.sh

# ⑤ 构建 + 启动（3-8 分钟）
bash deploy/deploy.sh

# ⑥ 三件套验证
bash deploy/status.sh          # 3 容器 healthy
bash deploy/test-ai.sh         # AI 返回 ok:true
curl -I https://player.qlm.org.cn   # HTTP/2 200 + HSTS
```

详细到每一条命令的手册：[deploy/LINUX_SETUP.md](deploy/LINUX_SETUP.md)。

---

## 七、安全清单（上线前必勾）

- [ ] `.env` 权限 `chmod 600`，未 git 提交
- [ ] JWT_SECRET 用 `openssl rand -hex 32` 重生成
- [ ] 已改默认 admin 密码
- [ ] nginx 80→301→443 + HSTS header 生效
- [ ] UFW 只放 22/80/443，25565 按需
- [ ] DeepSeek 控制台已启用子 Key + 额度告警
- [ ] certbot `--dry-run` 续签成功，`systemctl list-timers | grep certbot`

---

## LICENSE

MIT © 2026 Player2 Team
