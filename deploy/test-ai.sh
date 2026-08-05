#!/usr/bin/env bash
# ============================================================
# DeepSeek R1 (ai.bbsmc.org.cn) 连通性测试
# 用法：cd backend && cp .env.example .env && nano .env 填好 API
#       bash ../deploy/test-ai.sh
# ============================================================
set -euo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "${SCRIPT_DIR}/.."

# 优先使用根目录 .env，其次 backend/.env
for f in .env backend/.env; do
  [[ -f "$f" ]] && { echo "# 载入 $f"; set -a; source "$f"; set +a; break; }
done

: "${AI_API_URL:?需要设置 AI_API_URL (如 https://ai.bbsmc.org.cn/v1)}"
: "${AI_API_KEY:?需要设置 AI_API_KEY}"
MODEL="${AI_MODEL:-deepseek-reasoner}"

echo
echo "======== DeepSeek R1 连通性测试 ========"
echo "Endpoint : ${AI_API_URL}/chat/completions"
echo "Model    : ${MODEL}"
echo "Key      : ${AI_API_KEY:0:8}...${AI_API_KEY:(-4)}"
echo

BODY='{
  "model": "'"${MODEL}"'",
  "messages": [
    {"role":"system","content":"你是一个 JSON 输出器，只输出 {\"ok\":true}"},
    {"role":"user","content":"输出 {\"ok\":true}"}
  ],
  "max_tokens": 200
}'

START_NS=$(date +%s%N)
set +e
RESP=$(curl -sS --max-time 120 \
  -H "Authorization: Bearer ${AI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "${AI_API_URL}/chat/completions")
RC=$?
END_NS=$(date +%s%N)
MS=$(( (END_NS - START_NS)/1000000 ))
set -e

echo "HTTP 耗时 : ${MS} ms"
echo
if [[ $RC -ne 0 ]]; then
  echo "ERROR: curl 退出码 $RC"
  exit 1
fi

# 输出精简版结果
CHOICE=$(echo "$RESP" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  c = d['choices'][0]['message']
  content = c.get('content','')
  think = c.get('reasoning_content') or c.get('thinking_content') or ''
  usage = d.get('usage',{})
  print(f'usage  : {json.dumps(usage, ensure_ascii=False)}')
  if think:
    print(f'thinking({len(think)}chars): {think[:200]}...' )
  print(f'content ({len(content)}chars): {content[:400]}' )
except Exception as e:
  print('RAW:', repr(sys.stdin.read()[:500]))
  print('ParseErr:', e)
" 2>&1)
echo "$CHOICE"
echo
echo "若以上有 usage + content 非空，则 ai.bbsmc.org.cn + DeepSeek R1 配置正确。"
