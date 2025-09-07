#!/usr/bin/env bash
set -euo pipefail

# 常量（运行时路径）
XRAY_BIN="/usr/local/bin/xray"
XRAY_ETC="/app/etc"
XRAY_TMPL_SOCKS="$XRAY_ETC/xray-socks.json.template"
XRAY_TMPL_HTTP="$XRAY_ETC/xray-http.json.template"
XRAY_CONF="$XRAY_ETC/xray.json"
XRAY_ASSETS="/app/assets"

die(){ echo "[xray] ERROR: $*" >&2; exit 1; }
info(){ echo "[xray] $*"; }

# MODE：socks / http
MODE="${MODE:-${XRAY_MODE:-}}"
[[ -n "${MODE:-}" ]] || die "Missing MODE (socks | http)"
case "$MODE" in
  socks|http) ;;
  *) die "Invalid MODE: $MODE (allowed: socks | http)";;
esac

# 公共必填（与出站&路由相关）
required_common_vars=(
  LOG_LEVEL
  OUTBOUND_PROTOCOL
  OUTBOUND_IP
  OUTBOUND_PORT
  RULE_PRIVATE_IP
  RULE_PROXY_SITE
  RULE_PROXY_IP
)

# 各 MODE 的必填
required_socks_vars=( SOCKS_LISTEN_PORT SOCKS_LISTEN_IP )
# HTTP 改为使用 HTTP_ACCOUNTS_JSON，多账号一次性注入
required_http_vars=( HTTP_LISTEN_PORT HTTP_LISTEN_IP HTTP_ACCOUNTS_JSON )

# 允许 XRAY_* 前缀兜底
backfill_from_xray_prefix(){
  for v in "$@"; do
    local pv="XRAY_${v}"
    if [[ -z "${!v-}" && -n "${!pv-}" ]]; then
      export "$v"="${!pv}"
    fi
  done
}

backfill_from_xray_prefix "${required_common_vars[@]}"
if [[ "$MODE" == "socks" ]]; then
  backfill_from_xray_prefix "${required_socks_vars[@]}"
else
  backfill_from_xray_prefix "${required_http_vars[@]}"
fi

# 校验必填
for v in "${required_common_vars[@]}"; do
  [[ -n "${!v-}" ]] || die "Missing required env: ${v}"
done
if [[ "$MODE" == "socks" ]]; then
  for v in "${required_socks_vars[@]}"; do
    [[ -n "${!v-}" ]] || die "Missing required env for MODE=socks: ${v}"
  done
else
  for v in "${required_http_vars[@]}"; do
    [[ -n "${!v-}" ]] || die "Missing required env for MODE=http: ${v}"
  done
  # 简单校验 JSON 形态（不引入 jq），要求以 [ 开始以 ] 结束
  case "${HTTP_ACCOUNTS_JSON}" in
    \[*\]) ;;  # ok
    *) die "HTTP_ACCOUNTS_JSON must be a JSON array, e.g. [] or [{\"user\":\"u\",\"pass\":\"p\"}].";;
  esac
fi

# 选择模板（运行时固定在 /app/etc）
if [[ "$MODE" == "socks" ]]; then
  XRAY_TMPL="$XRAY_TMPL_SOCKS"
else
  XRAY_TMPL="$XRAY_TMPL_HTTP"
fi
[[ -f "$XRAY_TMPL" ]] || die "Template not found: $XRAY_TMPL"

# 仅替换模板中出现的变量
mapfile -t vars_in_tmpl < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$XRAY_TMPL" | sed 's/[${}]//g' | sort -u)
repl_list=""
for v in "${vars_in_tmpl[@]}"; do repl_list+="\${$v} "; done

info "MODE=$MODE, rendering $XRAY_CONF from $(basename "$XRAY_TMPL")"
# shellcheck disable=SC2086
envsubst "$repl_list" < "$XRAY_TMPL" > "$XRAY_CONF"

# 可选：脱敏输出（默认显示；设置 SHOW_CONFIG=0 可关闭）
SHOW_CONFIG="${SHOW_CONFIG:-1}"
if [[ "$SHOW_CONFIG" != "0" ]]; then
  echo "[xray] Rendered config content:"
  echo "------------------ BEGIN xray.json ------------------"
  if [[ "$MODE" == "http" ]]; then
    # 避免在日志中直接暴露密码（粗粒度脱敏）
    sed -E 's/"pass"\s*:\s*"([^"]*)"/"pass":"******"/g' "$XRAY_CONF" || cat "$XRAY_CONF"
  else
    cat "$XRAY_CONF"
  fi
  echo
  echo "------------------- END  xray.json -------------------"
fi

# 资产目录
export XRAY_LOCATION_ASSET="$XRAY_ASSETS"

info "Starting Xray..."
exec "$XRAY_BIN" run -c "$XRAY_CONF"
