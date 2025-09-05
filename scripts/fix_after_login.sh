#!/bin/sh
# qbt-proton-qnap :: fix_after_login.sh
#
# What this script does, safely:
# 1) Stop qbittorrent and gluetun cleanly, wait until stopped.
# 2) Patch .fastresume paths (/downloads -> /Downloads).
# 3) Ensure /Downloads subfolders & correct permissions (PUID/PGID).
# 4) Start gluetun then qbittorrent, and robustly wait for qB Web API:
#       - curl http://localhost:8080/api/v2/app/version
#       - wget same endpoint
#       - TCP open check
# 5) Try API login with QBT_WEBUI_USER/PASS (from .env). If it fails,
#    auto-fallback to the temporary WebUI password from container logs.
# 6) If API login succeeds, set WebUI preferences via API (no file edits):
#       - web_ui_host_header_validation=false
#       - web_ui_csrf_protection_enabled=false
#       - bypass_local_auth=true
#       - bypass_auth_subnet_whitelist_enabled=true
#       - bypass_auth_subnet_whitelist="127.0.0.1/32,::1/128"
#       - web_ui_use_https=false
#       - web_ui_address="*"
#       - save_path="/Downloads/", temp_path_enabled=true, temp_path="/Downloads/Incomplete"
# 7) If API never becomes ready, last-resort: stop qB, patch qBittorrent.conf
#    with the exact WebUI\ keys (backslashes), then start qB again.
# 8) Print a short status.

set -eu

log(){ printf '%s %s\n' "$1" "$2"; }
die(){ log "[-]" "$1" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="$ROOT/docker-compose.yml"
USE_COMPOSE=0
[ -f "$COMPOSE" ] && USE_COMPOSE=1

QB_NAME="${QB_NAME:-qbittorrent}"
GLUETUN_NAME="${GLUETUN_NAME:-gluetun}"

log "[*]" "qbt-proton-qnap :: fix_after_login.sh"

# Load .env if present (PUID/PGID, CONFIG_ROOT, DOWNLOADS_ROOT, QBT_WEBUI_USER/PASS, etc.)
if [ -f "$ROOT/.env" ]; then
  log "[*]" "Loading .env"
  # shellcheck disable=SC2046
  export $(grep -E '^[A-Za-z0-9_]+=' "$ROOT/.env" | xargs -n1) || true
fi

# Resolve host config/downloads paths from mounts (fallbacks if absent)
CFG_SRC="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' "$QB_NAME" 2>/dev/null || true)"
[ -z "${CFG_SRC:-}" ] && CFG_SRC="${CONFIG_ROOT:-/share/CACHEDEV3_DATA/SSD2TB/AppData/qbt-proton}"
DL_SRC="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/Downloads"}}{{.Source}}{{end}}{{end}}' "$QB_NAME" 2>/dev/null || true)"
[ -z "${DL_SRC:-}" ] && DL_SRC="${DOWNLOADS_ROOT:-/share/CACHEDEV3_DATA/SSD2TB/Downloads}"

CFG_DIR="$CFG_SRC/qBittorrent"
CFG_FILE="$CFG_DIR/qBittorrent.conf"
[ -f "$CFG_FILE" ] || [ -f "$CFG_SRC/qBittorrent.conf" ] || die "qBittorrent.conf not found (expected $CFG_DIR/qBittorrent.conf)"
[ -f "$CFG_FILE" ] || { mkdir -p "$CFG_DIR"; mv -f "$CFG_SRC/qBittorrent.conf" "$CFG_FILE"; }

# Get PUID/PGID from container env (fallbacks)
PUID="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$QB_NAME" 2>/dev/null | awk -F= '/^PUID=/{print $2}' | tail -n1 || true)"
PGID="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$QB_NAME" 2>/dev/null | awk -F= '/^PGID=/{print $2}' | tail -n1 || true)"
[ -z "${PUID:-}" ] && PUID=1000
[ -z "${PGID:-}" ] && PGID=100

log "[i]" "Using config: $CFG_FILE"
log "[i]" "PUID=$PUID PGID=$PGID"

wait_stopped() {
  cname="$1"
  i=0
  while docker ps --format '{{.Names}}' | grep -qx "$cname"; do
    i=$((i+1)); [ $i -gt 180 ] && die "Container $cname did not stop (timeout)"
    sleep 1
  done
}

normalize_ini() {
  f="$1"
  # Strip BOM + CRLF safely
  awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {sub(/\r$/,""); print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

patch_conf_webui_keys() {
  # last-resort writer: ensure single correct WebUI\ keys
  f="$1"
  normalize_ini "$f"

  # delete any problematic duplicates / wrong keys written by other tools
  sed -i -e '/^WebUIAddress=/d' \
         -e '/^WebUIHostHeaderValidation=/d' \
         -e '/^WebUIHTTPSEnabled=/d' \
         -e '/^WebUIAuthSubnetWhitelist=/d' \
         -e '/^WebUIAuthSubnetWhitelistEnabled=/d' \
         "$f"

  # enforce desired keys (escaped backslashes)
  # we also keep Port untouched; only “safe to apply” flags go here
  grep -q '^WebUI\\HostHeaderValidation=' "$f" \
    && sed -i 's#^WebUI\\HostHeaderValidation=.*#WebUI\\HostHeaderValidation=false#' "$f" \
    || printf '%s\n' 'WebUI\HostHeaderValidation=false' >> "$f"

  grep -q '^WebUI\\CSRFProtection=' "$f" \
    && sed -i 's#^WebUI\\CSRFProtection=.*#WebUI\\CSRFProtection=false#' "$f" \
    || printf '%s\n' 'WebUI\CSRFProtection=false' >> "$f"

  grep -q '^WebUI\\BypassLocalAuth=' "$f" \
    && sed -i 's#^WebUI\\BypassLocalAuth=.*#WebUI\\BypassLocalAuth=true#' "$f" \
    || printf '%s\n' 'WebUI\BypassLocalAuth=true' >> "$f"

  grep -q '^WebUI\\AuthSubnetWhitelistEnabled=' "$f" \
    && sed -i 's#^WebUI\\AuthSubnetWhitelistEnabled=.*#WebUI\\AuthSubnetWhitelistEnabled=true#' "$f" \
    || printf '%s\n' 'WebUI\AuthSubnetWhitelistEnabled=true' >> "$f"

  grep -q '^WebUI\\AuthSubnetWhitelist=' "$f" \
    && sed -i 's#^WebUI\\AuthSubnetWhitelist=.*#WebUI\\AuthSubnetWhitelist=127.0.0.1/32,::1/128#' "$f" \
    || printf '%s\n' 'WebUI\AuthSubnetWhitelist=127.0.0.1/32,::1/128' >> "$f"

  grep -q '^WebUI\\HTTPS\\Enabled=' "$f" \
    && sed -i 's#^WebUI\\HTTPS\\Enabled=.*#WebUI\\HTTPS\\Enabled=false#' "$f" \
    || printf '%s\n' 'WebUI\HTTPS\Enabled=false' >> "$f"

  grep -q '^WebUI\\Address=' "$f" \
    && sed -i 's#^WebUI\\Address=.*#WebUI\\Address=*#' "$f" \
    || printf '%s\n' 'WebUI\Address=*' >> "$f"
}

# --- Stop order: qbittorrent then gluetun ---
log "[*]" "Stopping qbittorrent"
if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" stop "$QB_NAME" >/dev/null 2>&1 || true
else docker stop "$QB_NAME" >/dev/null 2>&1 || true; fi
wait_stopped "$QB_NAME"

log "[*]" "Stopping gluetun"
if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" stop "$GLUETUN_NAME" >/dev/null 2>&1 || true
else docker stop "$GLUETUN_NAME" >/dev/null 2>&1 || true; fi
wait_stopped "$GLUETUN_NAME"

# Backup & normalize
TS="$(date +%F-%H%M%S)"
[ -d "$CFG_DIR/BT_backup" ] && cp -a "$CFG_DIR/BT_backup" "$CFG_DIR/BT_backup.bak.$TS" || true
cp -a "$CFG_FILE" "$CFG_FILE.bak.$TS"
normalize_ini "$CFG_FILE"

# Patch .fastresume only
log "[*]" "Patching /downloads -> /Downloads in .fastresume"
[ -d "$CFG_DIR/BT_backup" ] && grep -rl '/downloads' "$CFG_DIR/BT_backup" | xargs -r sed -i 's#/downloads#/Downloads#g' || true

# Move JSONs to right place + path fix
for j in categories.json watched_folders.json; do
  [ -f "$CFG_SRC/$j" ] && [ ! -f "$CFG_DIR/$j" ] && mv -f "$CFG_SRC/$j" "$CFG_DIR/$j"
  [ -f "$CFG_DIR/$j" ] && sed -i 's#"/downloads#"/Downloads#g' "$CFG_DIR/$j"
done

# Ensure folders & permissions
log "[*]" "Ensuring folders & permissions under: $DL_SRC"
mkdir -p "$DL_SRC/Incomplete" "$DL_SRC/Torrents"
if [ -f "$CFG_DIR/categories.json" ]; then
  awk -F'"' '/"save_path":/ {print $4}' "$CFG_DIR/categories.json" \
    | sed -e 's#^/Downloads/##' -e 's#^/*##' \
    | while read -r sub; do [ -n "$sub" ] && mkdir -p "$DL_SRC/$sub"; done
fi
chown -R "$PUID:$PGID" "$DL_SRC" "$CFG_SRC"
chmod -R u+rwX,g+rwX "$DL_SRC" "$CFG_SRC"

# --- Start order: gluetun then qbittorrent ---
log "[*]" "Starting gluetun"
if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" up -d "$GLUETUN_NAME"
else docker start "$GLUETUN_NAME" >/dev/null; fi

# Wait for gluetun health (best effort)
i=0
while :; do
  state="$(docker inspect -f '{{.State.Health.Status}}' "$GLUETUN_NAME" 2>/dev/null || echo '')"
  [ "$state" = "healthy" ] && break
  i=$((i+1)); [ $i -ge 120 ] && break
  sleep 1
done

log "[*]" "Starting qbittorrent"
if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" up -d "$QB_NAME"
else docker start "$QB_NAME" >/dev/null; fi

# --- Robust wait for Web API (up to ~180s) ---
log "[*]" "Waiting for qBittorrent API inside container..."
READY=0
docker exec "$QB_NAME" sh -lc '
  try_curl()  { command -v curl  >/dev/null 2>&1 && curl -fsS http://localhost:8080/api/v2/app/version >/dev/null 2>&1; }
  try_wget()  { command -v wget  >/dev/null 2>&1 && wget -qO-   http://localhost:8080/api/v2/app/version >/dev/null 2>&1; }
  try_tcp()   { (exec 3<>/dev/tcp/127.0.0.1/8080) >/dev/null 2>&1; }

  for i in $(seq 1 180); do
    if try_curl || try_wget || try_tcp; then exit 0; fi
    sleep 1
  done
  exit 1
' && READY=1 || READY=0

if [ "$READY" -ne 1 ]; then
  log "[!]" "WebUI API did not become ready in time — applying last-resort file patch and restarting qB."
  # Stop qB, patch config keys, restart
  if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" stop "$QB_NAME" >/dev/null 2>&1 || true
  else docker stop "$QB_NAME" >/dev/null 2>&1 || true; fi
  wait_stopped "$QB_NAME"

  patch_conf_webui_keys "$CFG_FILE"

  if [ "$USE_COMPOSE" -eq 1 ]; then docker compose -f "$COMPOSE" up -d "$QB_NAME"
  else docker start "$QB_NAME" >/dev/null; fi
  # Give it a few seconds
  sleep 5
fi

# --- Try API login & apply prefs via API ---
API_USER="${QBT_WEBUI_USER:-admin}"
API_PASS="${QBT_WEBUI_PASS:-}"
COOKIE_JAR="/tmp/qb_cookies.txt"
LOGIN_OK=0

# If no pass provided or login fails, try temporary password from logs
get_temp_pass() {
  docker logs "$QB_NAME" 2>&1 \
    | awk '/WebUI administrator username is/{flag=1; next} flag{print $NF; flag=0}' \
    | tail -n 1
}

try_login() {
  docker exec "$QB_NAME" sh -lc "
    curl -s -c $COOKIE_JAR -X POST \
      --data \"username=$API_USER&password=$1\" \
      http://localhost:8080/api/v2/auth/login | grep -q ok
  "
}

if [ -n "$API_PASS" ] && try_login "$API_PASS"; then
  LOGIN_OK=1
else
  TMP_PASS="$(get_temp_pass || true)"
  if [ -n "$TMP_PASS" ] && try_login "$TMP_PASS"; then
    LOGIN_OK=1
    API_PASS="$TMP_PASS"
    log "[i]" "Logged in using temporary WebUI password from logs."
  fi
fi

if [ "$LOGIN_OK" -eq 1 ]; then
  log "[*]" "Applying WebUI flags required by GSP (via API)"
  docker exec "$QB_NAME" sh -lc "
    curl -s -b $COOKIE_JAR -X POST \
      --data-urlencode 'json={
        \"web_ui_host_header_validation\": false,
        \"web_ui_csrf_protection_enabled\": false,
        \"bypass_local_auth\": true,
        \"bypass_auth_subnet_whitelist_enabled\": true,
        \"bypass_auth_subnet_whitelist\": \"127.0.0.1/32,::1/128\",
        \"web_ui_use_https\": false,
        \"web_ui_address\": \"*\"
      }' \
      http://localhost:8080/api/v2/app/setPreferences >/dev/null 2>&1 || true
  "

  log "[*]" "Re-asserting Downloads paths (via API)"
  docker exec "$QB_NAME" sh -lc "
    curl -s -b $COOKIE_JAR -X POST \
      --data-urlencode 'json={
        \"save_path\": \"/Downloads/\",
        \"temp_path_enabled\": true,
        \"temp_path\": \"/Downloads/Incomplete\"
      }' \
      http://localhost:8080/api/v2/app/setPreferences >/dev/null 2>&1 || true
  "
else
  log "[!]" "Could not authenticate to WebUI API (no valid creds). WebUI flags may already be fine from last-resort patch."
fi

echo "----- WebUI keys in qBittorrent.conf (sanity) -----"
docker exec "$QB_NAME" sh -lc 'grep -n -E "WebUI\\\\|HostHeader|Bypass|Whitelist|CSRF" /config/qBittorrent/qBittorrent.conf || true'

log "[OK]" "Done. Open WebUI at your host:port. If some torrents error due to path updates, select them and 'Force recheck'."
