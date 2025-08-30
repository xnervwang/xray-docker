#!/usr/bin/env bash
set -euo pipefail

XRAY_BIN="/app/bin/xray"
XRAY_CONFIG_TEMPLATE="/app/etc/xray.json.template"
XRAY_CONFIG="/app/etc/xray.json"

# 必填环境变量清单
required_vars=(
  LOG_LEVEL
  LISTEN_PORT
  LISTEN_IP
  LISTEN_PROTOCOL
  OUTBOUND_PROTOCOL
  OUTBOUND_IP
  OUTBOUND_PORT
  RULE_PRIVATE_IP
  RULE_PROXY_SITE
  RULE_PROXY_IP
)

die() { echo "[xray] ERROR: $*" >&2; exit 1; }
info(){ echo "[xray] $*"; }

# 检查必填环境变量
for v in "${required_vars[@]}"; do
  if [[ -z "${!v-}" ]]; then
    die "Missing required env: $v"
  fi
done

# 检查模板是否存在
[[ -f "$XRAY_CONFIG_TEMPLATE" ]] || die "Config template not found: $XRAY_CONFIG_TEMPLATE"

# 提取模板中出现的变量
mapfile -t vars_in_tmpl < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$XRAY_CONFIG_TEMPLATE" | sed 's/[${}]//g' | sort -u)
repl_list=""
for v in "${vars_in_tmpl[@]}"; do repl_list+="\${$v} "; done

# 渲染配置
info "Rendering config -> $XRAY_CONFIG"
# shellcheck disable=SC2086
envsubst "$repl_list" < "$XRAY_CONFIG_TEMPLATE" > "$XRAY_CONFIG"

# JSON 基本校验（可选）
if command -v jq >/dev/null 2>&1; then
  jq . >/dev/null < "$XRAY_CONFIG" || die "Rendered config is not valid JSON"
fi

# 启动 Xray
info "Starting Xray..."
exec "$XRAY_BIN" run -c "$XRAY_CONFIG"
