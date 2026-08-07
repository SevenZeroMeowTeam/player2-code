#!/usr/bin/env bash
# ============================================================
# Player2 Debian 服务器初始化脚本（兼容入口）
#
# 本脚本是 deploy/init.sh 的薄包装，保留是为了向后兼容
# 已有的 README / 部署手册引用。它会把控制权转交给跨发行版
# 的 init.sh（自动识别为 Debian 系走 apt 路径）。
#
# 新部署建议直接使用：
#   chmod +x deploy/init.sh && sudo bash deploy/init.sh
#
# 适用系统：Debian 12 (bookworm) / Debian 11 (bullseye) /
#           Ubuntu 20.04+ / LinuxMint / Pop!_OS
# 运行：chmod +x deploy/init-debian.sh && sudo bash deploy/init-debian.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [[ ! -f "${SCRIPT_DIR}/init.sh" ]]; then
  printf "\033[1;31m[FAIL]\033[0m 找不到 %s/init.sh，请确认项目文件完整\n" "$SCRIPT_DIR" >&2
  exit 1
fi

printf "\033[1;34m[INFO]\033[0m 转发到通用初始化脚本 init.sh（自动识别 Debian 系）...\n\n"
exec bash "${SCRIPT_DIR}/init.sh" "$@"
