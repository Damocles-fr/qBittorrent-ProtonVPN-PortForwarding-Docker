\
#!/bin/sh
set -eu

echo "[*] qbt-proton-qnap :: install.sh"

# 1) Load .env or offer to create it from envExample
if [ ! -f ".env" ]; then
  if [ -f "envExample" ]; then
    cp -n envExample .env
    echo "[-] .env was missing. A copy was created from envExample."
    echo "    -> Edit .env and set at least: WIREGUARD_PRIVATE_KEY, GLUETUN_API_KEY"
    exit 1
  else
    echo "[-] Neither .env nor envExample found. Aborting."
    exit 1
  fi
fi

# shellcheck disable=SC1091
. ./.env
: "${CONFIG_ROOT:?set in .env}"
: "${DOWNLOADS_ROOT:?set in .env}"
: "${PUID:?set}"
: "${PGID:?set}"
: "${WIREGUARD_PRIVATE_KEY:?set}"
: "${GLUETUN_API_KEY:?set}"

echo "[*] Preparing folders"
mkdir -p "${CONFIG_ROOT}/qBittorrent" "${CONFIG_ROOT}/gluetun/auth" "${DOWNLOADS_ROOT}"/{Incomplete,Torrents}
chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" "${DOWNLOADS_ROOT}"
chmod -R u+rwX,g+rwX "${CONFIG_ROOT}" "${DOWNLOADS_ROOT}"

# 2) Seed starter config if not present
if [ ! -f "${CONFIG_ROOT}/qBittorrent/qBittorrent.conf" ]; then
  echo "[*] Installing starter qBittorrent.conf"
  cp -a "qBittorrent/qBittorrent.conf" "${CONFIG_ROOT}/qBittorrent/qBittorrent.conf"
fi
for f in categories.json watched_folders.json; do
  if [ ! -f "${CONFIG_ROOT}/qBittorrent/${f}" ]; then
    cp -a "qBittorrent/${f}" "${CONFIG_ROOT}/qBittorrent/${f}"
  fi
done

# 3) Gluetun control server auth (API key)
AUTH_TOML="${CONFIG_ROOT}/gluetun/auth/config.toml"
if [ ! -f "${AUTH_TOML}" ]; then
  echo "[*] Creating Gluetun auth config (${AUTH_TOML})"
  cat >"${AUTH_TOML}" <<EOF
[[roles]]
name = "qbittorrent"
routes = ["GET /v1/openvpn/portforwarded", "GET /v1/wireguard/portforwarded"]
auth = "apikey"
apikey = "${GLUETUN_API_KEY}"
EOF
  chown "${PUID}:${PGID}" "${AUTH_TOML}"
  chmod 600 "${AUTH_TOML}"
fi

echo "[*] Bringing stack up"
docker compose up -d

echo "[i] WebUI URL:  http://$(ip -4 addr show | awk '/inet .* brd/ {print $2}' | sed 's#/.*##' | head -n1):${WEBUI_HOST_PORT:-8081}"
echo "[i] Temp WebUI password (if auto-reset by LSIO):"
echo "    docker logs qbittorrent 2>&1 | grep -A1 'WebUI administrator username is' | tail -n1 | awk '{print \$NF}'"

echo "[*] All set. After first login, run: sh scripts/fix_after_login.sh"
