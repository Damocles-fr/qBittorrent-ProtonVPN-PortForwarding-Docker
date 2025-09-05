#!/bin/sh
set -eu

echo "[*] qbt-proton-qnap :: install.sh"

# Load .env
if [ ! -f ".env" ]; then
  echo "[-] .env not found. Copy envExample to .env and edit your values."
  exit 1
fi
# BusyBox compatible
# shellcheck disable=SC1091
. ./.env

: "${CONFIG_ROOT:?CONFIG_ROOT missing in .env}"
: "${DOWNLOADS_ROOT:?DOWNLOADS_ROOT missing in .env}"
: "${PUID:=1000}"
: "${PGID:=100}"
: "${HOST_WEBUI_PORT:=8081}"

echo "[i] Using CONFIG_ROOT=${CONFIG_ROOT}"
echo "[i] Using DOWNLOADS_ROOT=${DOWNLOADS_ROOT}"
echo "[i] PUID=${PUID} PGID=${PGID}"
echo "[i] WebUI on host port ${HOST_WEBUI_PORT}"

# Prepare folders
mkdir -p "${CONFIG_ROOT}/qBittorrent" "${DOWNLOADS_ROOT}"

# Create standard subfolders in /Downloads (must be empty or non-existent initially)
mkdir -p "${DOWNLOADS_ROOT}/Incomplete" "${DOWNLOADS_ROOT}/Torrents"

# Copy default qB files only if missing
copy_if_missing() {
  src="$1"; dst="$2"
  if [ ! -e "$dst" ]; then
    echo "[*] Installing default $(basename "$dst")"
    cp -a "$src" "$dst"
  fi
}

copy_if_missing "qBittorrent/qBittorrent.conf" "${CONFIG_ROOT}/qBittorrent/qBittorrent.conf"
copy_if_missing "qBittorrent/categories.json"   "${CONFIG_ROOT}/qBittorrent/categories.json"
copy_if_missing "qBittorrent/watched_folders.json" "${CONFIG_ROOT}/qBittorrent/watched_folders.json"

# Permissions for downloads
echo "[*] Setting ownership on ${DOWNLOADS_ROOT}"
chown -R "${PUID}:${PGID}" "${DOWNLOADS_ROOT}" || true
chmod -R u+rwX,g+rwX "${DOWNLOADS_ROOT}" || true

# Bring stack up
echo "[*] Bringing stack up"
docker compose up -d

# Show URL and (optional) temp WebUI password if any
IP_NAS=$(ip -4 addr show | awk '/inet .* brd/ {print $2}' | sed 's#/.*##' | head -n1 || echo "NAS_IP")
echo "[i] Open: http://${IP_NAS}:${HOST_WEBUI_PORT}"

echo "[i] If qB reset a temporary password, see Readme to retrieve it with:"
echo "[i] docker logs qbittorrent 2>&1 | grep -A1 'WebUI administrator username is' | tail -n 1 | awk '{print $NF}'"
