#!/bin/bash
# ============================================================
# Player2 Forge Mod JAR 构建脚本（服务器端）
# 在服务器上直接运行： bash mod/build-jar.sh
# 产物：mod/build/libs/player2-1.0.0.jar
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

log() { echo "[BUILD] $*"; }
die() { log "FATAL: $*"; exit 1; }

# ---- 1. 检查 Java 17 ----
log "检查 Java 环境..."
JAVA_VER=$(java -version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' | cut -d. -f1)
if [[ "$JAVA_VER" != "17" ]]; then
    die "需要 Java 17，当前版本: $JAVA_VER。请安装: apt install openjdk-17-jdk"
fi
log "Java 版本: $(java -version 2>&1 | head -1)"

# ---- 2. 安装 Gradle 8.5（如果没有）----
GRADLE_VERSION="8.5"
GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"

if [[ ! -d "$GRADLE_HOME" ]]; then
    log "下载 Gradle ${GRADLE_VERSION}..."
    if [[ -f /etc/debian_version ]]; then
        apt-get update -qq && apt-get install -y -qq wget unzip 2>/dev/null || true
    fi
    wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip
    unzip -q /tmp/gradle.zip -d /opt/
    rm -f /tmp/gradle.zip
    log "Gradle ${GRADLE_VERSION} 已安装到 ${GRADLE_HOME}"
fi

export PATH="${GRADLE_HOME}/bin:$PATH"
GRADLE_BIN="${GRADLE_HOME}/bin/gradle"

# ---- 3. 生成 Gradle Wrapper ----
if [[ ! -f "gradlew" ]] || [[ ! -f "gradle/wrapper/gradle-wrapper.jar" ]]; then
    log "生成 Gradle Wrapper..."
    "$GRADLE_BIN" wrapper --gradle-version "$GRADLE_VERSION"
    chmod +x gradlew
    log "Gradle Wrapper 已生成"
fi

# ---- 4. 清理旧构建 ----
log "清理旧构建..."
"$GRADLE_BIN" clean 2>/dev/null || rm -rf build

# ---- 5. 构建 JAR ----
log "构建 Forge mod JAR..."
"$GRADLE_BIN" build --no-daemon --console=plain

# ---- 6. 确认产物 ----
JAR_FILE=$(find build/libs -name "*.jar" -not -name "*dev*" -not -name "*sources*" -not -name "*javadoc*" 2>/dev/null | head -1)

if [[ -z "$JAR_FILE" ]]; then
    die "构建产物未找到！检查 build/libs/ 目录"
fi

JAR_SIZE=$(du -h "$JAR_FILE" | cut -f1)
log "============================================="
log "  JAR 构建成功！"
log "  文件: $SCRIPT_DIR/$JAR_FILE"
log "  大小: $JAR_SIZE"
log "============================================="

# 复制到 deploy 目录
mkdir -p ../deploy/libs
cp "$JAR_FILE" "../deploy/libs/"
log "已复制到 deploy/libs/"
