\
#!/bin/sh
# qbt-proton-qnap :: fix_after_login.sh
# Goal:
# - Stop containers cleanly
# - Patch .fastresume paths (/downloads -> /Downloads)
# - Ensure /Downloads subfolders & permissions
# - Start Gluetun and wait healthy
# - Start qBittorrent and wait for WebUI API ready
# - Fetch forwarded port from Gluetun
# - Apply WebUI & runtime prefs through API (bypass local, host header off, csrf off, whitelist localhost)
# - Verify and restart qB to lock values
set -eu

echo "[*] qbt-proton-qnap :: fix_after_login.sh"

# Load .env
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  . ./.env
else
  echo "[-] .env not found. Run from project root after creating .env from envExample."
  exit 1
fi

: "${CONFIG_ROOT:?set in .env}"
: "${DOWNLOADS_ROOT:?set in .env}"
: "${PUID:?set}"
: "${PGID:?set}"
: "${WEBUI_HOST_PORT:=8081}"

CONF="${CONFIG_ROOT}/qBittorrent/qBittorrent.conf"
BT_BACKUP="${CONFIG_ROOT}/qBittorrent/BT_backup"

echo "[i] Using config: ${CONF}"
echo "[i] PUID=${PUID} PGID=${PGID}"

# Stop containers with patience
echo "[*] Stopping qbittorrent"
docker compose stop qbittorrent >/dev/null 2>&1 || true
for i in $(seq 1 20); do
  state="$(docker inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null || echo 'false')"
  [ "${state}" = "false" ] && break
  sleep 0.5
done

echo "[*] Stopping gluetun"
docker compose stop gluetun >/dev/null 2>&1 || true
for i in $(seq 1 20); do
  state="$(docker inspect -f '{{.State.Running}}' gluetun 2>/dev/null || echo 'false')"
  [ "${state}" = "false" ] && break
  sleep 0.5
done

# Patch /downloads to /Downloads in .fastresume (if any)
if [ -d "${BT_BACKUP}" ]; then
  echo "[*] Patching /downloads -> /Downloads in .fastresume"
  # BusyBox compatible grep -r
  find "${BT_BACKUP}" -type f -name "*.fastresume" -print0 | xargs -0 -r sed -i 's#/downloads#/Downloads#g'
fi

# Ensure folders and permissions
echo "[*] Ensuring folders & permissions under: ${DOWNLOADS_ROOT}"
mkdir -p "${DOWNLOADS_ROOT}/Incomplete" "${DOWNLOADS_ROOT}/Torrents"
chown -R "${PUID}:${PGID}" "${DOWNLOADS_ROOT}"
chmod -R u+rwX,g+rwX "${DOWNLOADS_ROOT}"

# Start Gluetun and wait healthy
echo "[*] Starting gluetun"
docker compose up -d gluetun >/dev/null
# Wait for health=healthy
for i in $(seq 1 60); do
  h="$(docker inspect -f '{{.State.Health.Status}}' gluetun 2>/dev/null || echo 'starting')"
  [ "${h}" = "healthy" ] && break
  sleep 2
done
docker inspect -f '{{.State.Health.Status}}' gluetun 2>/dev/null || true

# Start qB
echo "[*] Starting qbittorrent"
docker compose up -d qbittorrent >/dev/null

# Wait WebUI readiness (API version)
echo "[*] Waiting for qBittorrent API inside container..."
ok=false
for i in $(seq 1 60); do
  if docker exec qbittorrent sh -lc "wget -qO- http://localhost:8080/api/v2/app/version >/dev/null 2>&1"; then
    ok=true
    break
  fi
  sleep 2
done
if [ "${ok}" != "true" ]; then
  echo "[-] WebUI API did not become ready"
  exit 1
fi

# Get forwarded port from Gluetun
FWD="$(docker exec gluetun sh -lc 'cat /tmp/gluetun/forwarded_port 2>/dev/null || curl -fsS http://localhost:8000/v1/openvpn/portforwarded' | sed -E 's/[^0-9]//g' || true)"
FWD="${FWD:-0}"
echo "[i] Forwarded port = ${FWD}"

# Temp WebUI password if LSIO reset it
QBU="admin"
QBP="$(docker logs qbittorrent 2>&1 | awk '/WebUI administrator username is/{f=1;next} f{print $NF; exit}')"

# Login & apply preferences via API (payload param 'json=...' per qB API spec)
docker exec qbittorrent sh -lc "
u='${QBU}'; p='${QBP}';
curl -s -c /tmp/c.txt -X POST --data \"username=\$u&password=\$p\" http://localhost:8080/api/v2/auth/login >/dev/null && \
curl -s -b /tmp/c.txt -H 'Referer: http://localhost:8080' \
  -d 'json={\"bypass_local_auth\":true,\"web_ui_host_header_validation\":false,\"web_ui_csrf_protection_enabled\":false,\"bypass_auth_subnet_whitelist_enabled\":true,\"web_ui_auth_subnet_whitelist\":\"127.0.0.1/32,::1/128\",\"web_ui_address\":\"*\",\"save_path\":\"/Downloads\",\"temp_path_enabled\":true,\"temp_path\":\"/Downloads/Incomplete\"%s}' \
  http://localhost:8080/api/v2/app/setPreferences >/dev/null
" >/dev/null

# If forwarded port is valid, set it too
if [ "${FWD}" -gt 0 ]; then
  docker exec qbittorrent sh -lc "
u='${QBU}'; p='${QBP}';
curl -s -c /tmp/c.txt -X POST --data \"username=\$u&password=\$p\" http://localhost:8080/api/v2/auth/login >/dev/null && \
curl -s -b /tmp/c.txt -H 'Referer: http://localhost:8080' \
  -d 'json={\"listen_port\":${FWD}}' \
  http://localhost:8080/api/v2/app/setPreferences >/dev/null
" >/dev/null
fi

# Verify a subset
docker exec qbittorrent sh -lc "
u='${QBU}'; p='${QBP}';
curl -s -c /tmp/c.txt -X POST --data \"username=\$u&password=\$p\" http://localhost:8080/api/v2/auth/login >/dev/null && \
curl -s -b /tmp/c.txt http://localhost:8080/api/v2/app/preferences \
  | tr ',' '\n' | grep -E '\"listen_port\"|\"save_path\"|\"temp_path\"|\"bypass_local_auth\"|\"web_ui_host_header_validation\"|\"web_ui_csrf_protection_enabled\"|\"bypass_auth_subnet_whitelist_enabled\"' || true
" || true

# Final restart to ensure the runtime applies cleanly
docker restart qbittorrent >/dev/null

echo "[OK] Done. Open WebUI at your host:port. If some torrents error due to path updates, select them and 'Force recheck'."
