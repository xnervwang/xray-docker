#!/usr/bin/env bash
set -euo pipefail

# Constants (runtime paths)
XRAY_BIN="/usr/local/bin/xray"
XRAY_ETC="/app/etc"
XRAY_TMPL_SOCKS="$XRAY_ETC/xray-socks.json.template"
XRAY_TMPL_HTTP="$XRAY_ETC/xray-http.json.template"
XRAY_CONF="$XRAY_ETC/xray.json"
XRAY_ASSETS="/app/assets"
# Allow override via environment variables
GEOSITE_URL="${GEOSITE_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat}"
GEOIP_URL="${GEOIP_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat}"

die(){ echo "[xray] ERROR: $*" >&2; exit 1; }
info(){ echo "[xray] $*"; }

# Parse duration string to seconds (leverages sleep's native format support)
# Supports: 3s, 5m, 2h, 7d, etc.
parse_duration() {
  local dur="$1"
  
  # Extract number and unit
  if [[ "$dur" =~ ^([0-9]+)([smhd]?)$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]:-s}"  # default to seconds if no unit
    
    case "$unit" in
      s) echo "$num" ;;
      m) echo $((num * 60)) ;;
      h) echo $((num * 3600)) ;;
      d) echo $((num * 86400)) ;;
      *) die "Invalid duration unit: $unit (use: s, m, h, d)" ;;
    esac
  else
    die "Invalid duration format: $dur (use: 3s, 5m, 2h, 7d, etc.)"
  fi
}

# Check if remote file has been modified using HTTP HEAD request
check_remote_modified() {
  local url="$1"
  local local_file="$2"
  local metadata_file="$3"
  
  # Get remote file metadata
  local remote_last_modified=$(curl -fsSI "$url" | grep -i "last-modified:" | cut -d' ' -f2- | tr -d '\r' 2>/dev/null || echo "")
  local remote_etag=$(curl -fsSI "$url" | grep -i "etag:" | cut -d' ' -f2- | tr -d '\r' | tr -d '"' 2>/dev/null || echo "")
  
  # If we can't get remote metadata, assume it's modified
  if [[ -z "$remote_last_modified" && -z "$remote_etag" ]]; then
    info "  Cannot get remote metadata for $(basename "$local_file"), assuming modified"
    return 0  # assume modified
  fi
  
  # If local file or metadata doesn't exist, consider it modified
  if [[ ! -f "$local_file" || ! -f "$metadata_file" ]]; then
    return 0  # modified
  fi
  
  # Read stored metadata
  local stored_last_modified=""
  local stored_etag=""
  if [[ -f "$metadata_file" ]]; then
    stored_last_modified=$(grep "^last-modified:" "$metadata_file" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//')
    stored_etag=$(grep "^etag:" "$metadata_file" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//')
  fi
  
  # Compare metadata
  if [[ -n "$remote_last_modified" && "$remote_last_modified" == "$stored_last_modified" ]]; then
    info "  Remote file $(basename "$local_file") not modified (Last-Modified match)"
    return 1  # not modified
  fi
  
  if [[ -n "$remote_etag" && "$remote_etag" == "$stored_etag" ]]; then
    info "  Remote file $(basename "$local_file") not modified (ETag match)"
    return 1  # not modified
  fi
  
  return 0  # assume modified if we can't determine
}

# Calculate file hash
calculate_file_hash() {
  local file="$1"
  if [[ -f "$file" ]]; then
    sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo ""
  else
    echo ""
  fi
}

# Store remote file metadata
store_remote_metadata() {
  local url="$1"
  local metadata_file="$2"
  
  {
    curl -fsSI "$url" | grep -i "last-modified:" | tr -d '\r' || true
    curl -fsSI "$url" | grep -i "etag:" | tr -d '\r' || true
  } > "$metadata_file" 2>/dev/null || true
}

# Download and update a single geodata file if changed
download_geodata_file() {
  local url="$1"
  local filename="$2"
  local force="${3:-}"
  
  local local_file="$XRAY_ASSETS/$filename"
  local tmp_file="$XRAY_ASSETS/${filename}.tmp"
  local metadata_file="$XRAY_ASSETS/.${filename}.metadata"
  local hash_file="$XRAY_ASSETS/.${filename}.hash"
  
  # Check if remote file is modified (skip if force download)
  if [[ "$force" != "force" ]] && ! check_remote_modified "$url" "$local_file" "$metadata_file"; then
    return 1  # not modified, no update needed
  fi
  
  info "  Downloading $filename from: $url"
  if curl -fsSL -o "$tmp_file" "$url"; then
    local size=$(stat -c%s "$tmp_file" 2>/dev/null || stat -f%z "$tmp_file" 2>/dev/null || echo "unknown")
    info "  $filename downloaded (${size} bytes)"
    
    # Calculate hashes
    local new_hash=$(calculate_file_hash "$tmp_file")
    local old_hash=$(cat "$hash_file" 2>/dev/null || echo "")
    
    # Compare hashes to detect actual content changes
    if [[ "$force" != "force" && -n "$new_hash" && "$new_hash" == "$old_hash" ]]; then
      info "  $filename content unchanged (hash: ${new_hash:0:16}...)"
      rm -f "$tmp_file"
      # Update metadata even if content is same
      store_remote_metadata "$url" "$metadata_file"
      return 1  # no content change
    fi
    
    # Content has changed, replace the file
    mv "$tmp_file" "$local_file"
    
    # Store new hash and metadata
    echo "$new_hash" > "$hash_file"
    store_remote_metadata "$url" "$metadata_file"
    
    if [[ -n "$old_hash" && "$old_hash" != "$new_hash" ]]; then
      info "  $filename updated (hash: ${old_hash:0:16}... → ${new_hash:0:16}...)"
    else
      info "  $filename installed (hash: ${new_hash:0:16}...)"
    fi
    
    return 0  # content changed
  else
    rm -f "$tmp_file"
    die "Failed to download $filename"
  fi
}

# Download geodata files with change detection
download_geodata() {
  local force="${1:-}"
  
  # Check if update is needed based on timestamp
  if [[ "$force" != "force" ]] && [[ -f "$XRAY_ASSETS/.last_update" ]]; then
    local last_update=$(cat "$XRAY_ASSETS/.last_update")
    local now=$(date +%s)
    local elapsed=$((now - last_update))
    info "Last update check: ${elapsed}s ago"
    if [[ $elapsed -lt ${UPDATE_INTERVAL_SEC:-0} ]]; then
      info "Update interval not reached, skipping check"
      return 1  # no check needed
    fi
  fi
  
  info "Checking for geodata file updates..."
  
  local geosite_changed=false
  local geoip_changed=false
  
  # Download geosite.dat if changed
  if download_geodata_file "$GEOSITE_URL" "geosite.dat" "$force"; then
    geosite_changed=true
  fi
  
  # Download geoip.dat if changed
  if download_geodata_file "$GEOIP_URL" "geoip.dat" "$force"; then
    geoip_changed=true
  fi
  
  # Update timestamp regardless of whether files changed
  date +%s > "$XRAY_ASSETS/.last_update"
  
  # Return success only if at least one file was actually updated
  if [[ "$geosite_changed" == "true" || "$geoip_changed" == "true" ]]; then
    info "Geodata files updated successfully"
    return 0  # files changed
  else
    info "All geodata files are up to date"
    return 1  # no files changed
  fi
}

# Count active connections on listen port
count_active_connections() {
  local port="$1"
  local hex_port=$(printf "%04X" "$port")
  # Count ESTABLISHED connections (state 01)
  awk -v h="$hex_port" 'NR>1 {split($2,a,":"); if(a[2]==h && $4=="01") count++} END{print count+0}' /proc/net/tcp /proc/net/tcp6 2>/dev/null || echo 0
}

# Wait for idle period (low connection count)
wait_for_idle() {
  local port max_wait=300 check_interval=10
  [[ "$MODE" == "socks" ]] && port="${SOCKS_LISTEN_PORT}" || port="${HTTP_LISTEN_PORT}"
  
  info "Waiting for idle period before restart (max ${max_wait}s)..."
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local conns=$(count_active_connections "$port")
    info "  Active connections on port $port: $conns"
    if [[ $conns -eq 0 ]]; then
      info "No active connections detected, safe to restart"
      return 0
    fi
    sleep $check_interval
    elapsed=$((elapsed + check_interval))
  done
  info "Timeout waiting for idle period, proceeding with restart anyway"
}

# Background updater loop
geodata_updater() {
  local interval_sec="$1"
  info "[updater] Started with interval: ${interval_sec}s ($(($interval_sec/3600))h)"
  
  while true; do
    sleep "$interval_sec"
    info "[updater] Checking for geodata updates..."
    
    # Only restart xray if files actually changed
    if download_geodata; then
      info "[updater] Geodata files were updated, restarting xray..."
      
      if [[ -n "${XRAY_PID:-}" ]]; then
        wait_for_idle
        info "[updater] Sending SIGHUP to xray process (PID: $XRAY_PID)"
        if kill -HUP "$XRAY_PID" 2>/dev/null; then
          info "[updater] Reload signal sent successfully"
        else
          info "[updater] Failed to send reload signal (process may have exited)"
        fi
      fi
    else
      info "[updater] No geodata changes detected, xray restart skipped"
    fi
  done
}

# ========== Main Entry Point ==========

# MODE: socks / http
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

# Setup routing outbound tags based on mode
setup_routing_config() {
  local reverse_mode="${REVERSE_MODE:-0}"
  local private_ip_proxy="${RULE_PRIVATE_IP_PROXY:-0}"
  
  # Normalize boolean values
  case "$reverse_mode" in
    1|true|yes|on) reverse_mode=1 ;;
    *) reverse_mode=0 ;;
  esac
  
  case "$private_ip_proxy" in
    1|true|yes|on) private_ip_proxy=1 ;;
    *) private_ip_proxy=0 ;;
  esac
  
  if [[ "$reverse_mode" == "1" ]]; then
    info "Reverse mode enabled - specified domains/IPs go direct, others go proxy"
    # Reverse mode: specified sites/IPs go direct, others go proxy
    export PROXY_SITE_OUTBOUND="direct"
    export PROXY_IP_OUTBOUND="direct"
    export DEFAULT_OUTBOUND="proxy"
    
    # Private IP handling in reverse mode
    if [[ "$private_ip_proxy" == "1" ]]; then
      info "  Private IPs will go through proxy"
      export PRIVATE_IP_OUTBOUND="proxy"
    else
      info "  Private IPs will go direct (default)"
      export PRIVATE_IP_OUTBOUND="direct"
    fi
  else
    info "Normal mode enabled - specified domains/IPs go proxy, others go direct"
    # Normal mode: specified sites/IPs go proxy, others go direct
    export PROXY_SITE_OUTBOUND="proxy"
    export PROXY_IP_OUTBOUND="proxy"
    export DEFAULT_OUTBOUND="direct"
    export PRIVATE_IP_OUTBOUND="direct"
  fi
  
  info "Routing configuration:"
  info "  Private IPs -> ${PRIVATE_IP_OUTBOUND}"
  info "  Proxy Sites -> ${PROXY_SITE_OUTBOUND}"  
  info "  Proxy IPs -> ${PROXY_IP_OUTBOUND}"
  info "  Default -> ${DEFAULT_OUTBOUND}"
}

# Download geodata files on first run or if missing
if [[ ! -f "$XRAY_ASSETS/geosite.dat" ]] || [[ ! -f "$XRAY_ASSETS/geoip.dat" ]]; then
  info "Geodata files not found, downloading..."
  download_geodata force
fi

# Setup routing configuration based on mode
setup_routing_config

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

# Start background updater if UPDATE_INTERVAL is set and not "0"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-0}"
if [[ "$UPDATE_INTERVAL" != "0" ]]; then
  UPDATE_INTERVAL_SEC=$(parse_duration "$UPDATE_INTERVAL")
  info "Auto-update enabled: interval=$UPDATE_INTERVAL (${UPDATE_INTERVAL_SEC}s)"
  geodata_updater "$UPDATE_INTERVAL_SEC" &
  UPDATER_PID=$!
  trap "info 'Stopping updater...'; kill $UPDATER_PID 2>/dev/null || true" EXIT
else
  info "Auto-update disabled (UPDATE_INTERVAL=0)"
fi

info "Starting Xray..."
"$XRAY_BIN" run -c "$XRAY_CONF" &
XRAY_PID=$!
info "Xray started (PID: $XRAY_PID)"

# Wait for xray process
wait $XRAY_PID
