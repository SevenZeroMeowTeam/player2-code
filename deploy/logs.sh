#!/usr/bin/env bash
# 查看各服务日志，支持参数：backend / web / nginx / all
SVC="${1:-all}"
N="${2:-200}"
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
case "$SVC" in
  backend|web|nginx) docker compose logs -f --tail="$N" "$SVC" ;;
  all)               docker compose logs -f --tail="$N" ;;
  *)                 echo "用法: bash deploy/logs.sh [backend|web|nginx|all] [tail_lines]" ;;
esac
