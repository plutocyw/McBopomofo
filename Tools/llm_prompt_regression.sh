#!/bin/zsh
set -euo pipefail

MODEL="${1:-qwen3:0.6b}"
ENDPOINT="${OLLAMA_ENDPOINT:-http://127.0.0.1:11434/api/generate}"
RUNS="${RUNS:-8}"

typeset -a CASES=(
  "他剛剛們開著|他剛剛門開著"
  "我希望掌月費|我希望漲月費"
  "我覺得沒系了|我覺得沒戲了"
)

build_prompt() {
  local input="$1"
  local len=${#input}
  cat <<EOF
你是繁體中文校稿編輯。
任務：修正句子中不自然或錯誤的用字。
輸入句子：${input}
限制：不可刪字、不可加字、不可調換順序，輸出必須維持 ${len} 字。
只輸出修正後的一整句，不要解釋，不要標點外的額外文字。
EOF
}

extract_text() {
  local raw="$1"
  local compact="${raw//$'\r'/}"
  compact="${compact//$'\n'/}"
  compact="${compact##\`\`\`json}"
  compact="${compact##\`\`\`}"
  compact="${compact%%\`\`\`}"
  compact="$(printf "%s" "$compact" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "$compact" == \[*\] ]]; then
    printf "%s" "$compact" | jq -r 'if type=="array" then join("") else . end' 2>/dev/null || true
    return
  fi
  if [[ "$compact" == \"*\" ]]; then
    printf "%s" "$compact" | jq -r '.' 2>/dev/null || printf "%s" "$compact"
    return
  fi
  printf "%s" "$compact"
}

call_model() {
  local prompt="$1"
  local body
  body=$(jq -n --arg model "$MODEL" --arg prompt "$prompt" \
    '{model:$model,stream:false,options:{temperature:0},prompt:$prompt}')
  local response
  response="$(curl --max-time 30 -sS "$ENDPOINT" -d "$body" 2>/dev/null || true)"
  if [[ -z "$response" ]]; then
    echo ""
    return
  fi
  printf "%s" "$response" | jq -r '.response // empty' 2>/dev/null || true
}

total=0
passed=0

for pair in "${CASES[@]}"; do
  input="${pair%%|*}"
  expected="${pair##*|}"
  case_pass=0
  echo "=== ${input} ==="
  for ((i=1; i<=RUNS; i++)); do
    prompt="$(build_prompt "$input")"
    raw="$(call_model "$prompt")"
    text="$(extract_text "$raw")"
    if [[ "$text" == "$expected" ]]; then
      ((case_pass++))
      result="PASS"
    else
      result="FAIL"
    fi
    echo "${i}) ${result} => ${text}"
  done
  echo "case result: ${case_pass}/${RUNS}"
  echo
  : $((total += RUNS))
  : $((passed += case_pass))
done

echo "summary: ${passed}/${total}"
if [[ "$passed" -ne "$total" ]]; then
  exit 1
fi
