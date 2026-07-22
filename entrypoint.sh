#!/usr/bin/env bash
set -euo pipefail

# Constants (runtime paths)
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

# Common required (related to outbound & routing)
required_common_vars=(
  LOG_LEVEL
  OUTBOUND_PROTOCOL
  OUTBOUND_IP
  OUTBOUND_PORT
  RULE_PRIVATE_IP
  RULE_PROXY_SITE
  RULE_PROXY_IP
)

# Required for each MODE
required_socks_vars=( SOCKS_LISTEN_PORT SOCKS_LISTEN_IP )
# HTTP changed to use HTTP_ACCOUNTS_JSON, inject multiple accounts at once
required_http_vars=( HTTP_LISTEN_PORT HTTP_LISTEN_IP HTTP_ACCOUNTS_JSON )

# Allow XRAY_* prefix fallback
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

# Validate required
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
  # Simple JSON format validation (without jq), requires starting with [ and ending with ]
  case "${HTTP_ACCOUNTS_JSON}" in
    \[*\]) ;;  # ok
    *) die "HTTP_ACCOUNTS_JSON must be a JSON array, e.g. [] or [{\"user\":\"u\",\"pass\":\"p\"}].";;
  esac
fi

# Select template (fixed at /app/etc at runtime)
if [[ "$MODE" == "socks" ]]; then
  XRAY_TMPL="$XRAY_TMPL_SOCKS"
else
  XRAY_TMPL="$XRAY_TMPL_HTTP"
fi
[[ -f "$XRAY_TMPL" ]] || die "Template not found: $XRAY_TMPL"

# Only replace variables that appear in the template
mapfile -t vars_in_tmpl < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$XRAY_TMPL" | sed 's/[${}]//g' | sort -u)
repl_list=""
for v in "${vars_in_tmpl[@]}"; do repl_list+="\${$v} "; done

info "MODE=$MODE, rendering $XRAY_CONF from $(basename "$XRAY_TMPL")"
# shellcheck disable=SC2086
envsubst "$repl_list" < "$XRAY_TMPL" > "$XRAY_CONF"

# Optional: redacted output (default show; set SHOW_CONFIG=0 to disable)
SHOW_CONFIG="${SHOW_CONFIG:-1}"
if [[ "$SHOW_CONFIG" != "0" ]]; then
  echo "[xray] Rendered config content:"
  echo "------------------ BEGIN xray.json ------------------"
  if [[ "$MODE" == "http" ]]; then
    # Avoid exposing passwords directly in logs (coarse-grained redaction)
    sed -E 's/"pass"\s*:\s*"([^"]*)"/"pass":"******"/g' "$XRAY_CONF" || cat "$XRAY_CONF"
  else
    cat "$XRAY_CONF"
  fi
  echo
  echo "------------------- END  xray.json -------------------"
fi

# Asset directory
export XRAY_LOCATION_ASSET="$XRAY_ASSETS"

info "Starting Xray..."
exec "$XRAY_BIN" run -c "$XRAY_CONF"
