#!/usr/bin/env bash
# 状态巡检脚本：容器 / 磁盘 / 证书到期 / AI 连通性
set -uo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."

echo "============== 容器状态 =============="
if command -v docker >/dev/null 2>&1; then
  docker compose ps
  echo
  echo "=== 健康检查详细 ==="
  for c in player2-backend player2-web player2-nginx; do
    echo -n "$c : "
    docker inspect -f '{{.State.Status}} / Health:{{.State.Health.Status}}' "$c" 2>/dev/null || echo "(不存在)"
  done
fi

echo
echo "============== 资源占用 =============="
df -h / deploy/logs/nginx 2>/dev/null | head -20
echo
free -h
echo
echo "=== 最占空间的镜像/容器卷 ==="
docker system df 2>/dev/null || true

echo
echo "============== SSL 证书到期 =============="
CERT="deploy/certs/fullchain.pem"
if [[ -f "$CERT" ]]; then
  openssl x509 -in "$CERT" -noout -subject -dates 2>/dev/null
  EXP=$(openssl x509 -in "$CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -n "$EXP" ]]; then
    EXP_S=$(date -d "$EXP" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXP" +%s 2>/dev/null || echo 0)
    NOW_S=$(date +%s)
    DAYS_LEFT=$(( (EXP_S - NOW_S)/86400 ))
    echo "剩余天数: ${DAYS_LEFT} 天"
    (( DAYS_LEFT < 15 )) && echo "⚠️  证书将在 ${DAYS_LEFT} 天内过期，请执行 bash deploy/copy-certs.sh"
  fi
else
  echo "（证书不存在）"
fi

echo
echo "============== AI 服务连通 =============="
bash deploy/test-ai.sh 2>&1 | tail -15
