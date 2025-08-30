#!/usr/bin/env bash
set -euo pipefail

# 常量
XRAY_BIN="/usr/local/bin/xray"
XRAY_TMPL="/app/etc/xray.json.template"
XRAY_CONF="/app/etc/xray.json"
XRAY_ASSETS="/app/assets"

# 模板里会用到的变量（无前缀）
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

die(){ echo "[xray] ERROR: $*" >&2; exit 1; }
info(){ echo "[xray] $*"; }

# 允许用 XRAY_* 注入；若无前缀未设置且存在 XRAY_ 同名，则回填
for v in "${required_vars[@]}"; do
  pv="XRAY_${v}"
  if [[ -z "${!v-}" && -n "${!pv-}" ]]; then
    export "$v"="${!pv}"
  fi
done

# 校验必填
for v in "${required_vars[@]}"; do
  [[ -n "${!v-}" ]] || die "Missing required env: ${v} (or XRAY_${v})"
done

# 模板存在性
[[ -f "$XRAY_TMPL" ]] || die "Template not found: $XRAY_TMPL"

# 仅替换模板中出现的变量，避免把整个环境打进去
mapfile -t vars_in_tmpl < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$XRAY_TMPL" | sed 's/[${}]//g' | sort -u)
repl_list=""
for v in "${vars_in_tmpl[@]}"; do repl_list+="\${$v} "; done

info "Rendering $XRAY_CONF"
# shellcheck disable=SC2086
envsubst "$repl_list" < "$XRAY_TMPL" > "$XRAY_CONF"

# **打印渲染结果（便于你排查变量替换）**
echo "[xray] Rendered config content:"
echo "------------------ BEGIN xray.json ------------------"
cat "$XRAY_CONF"
echo
echo "------------------- END  xray.json -------------------"

# JSON 校验
jq . >/dev/null < "$XRAY_CONF" || die "Rendered config is not valid JSON"

# 确保 geosite/geoip 可读
export XRAY_LOCATION_ASSET="$XRAY_ASSETS"

info "Starting Xray..."
exec "$XRAY_BIN" run -c "$XRAY_CONF"
