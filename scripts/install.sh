\
    #!/bin/sh
    set -e

    echo "[*] Loading .env"
    if [ ! -f ".env" ]; then
      echo "[-] .env not found. Copy .env.example to .env and fill your values."; exit 1
    fi
    # POSIX-friendly "source"
    set -a; . ./.env; set +a

    # Detect docker compose command (v2 or classic plugin)
    if command -v docker-compose >/dev/null 2>&1; then
      DC="docker-compose"
    else
      DC="docker compose"
    fi

    echo "[*] Ensuring host folders exist"
    mkdir -p "$HOST_CONFIG/qBittorrent" \
             "$HOST_DOWNLOADS/Incomplete" \
             "$HOST_DOWNLOADS/Torrents" \
             "$HOST_DOWNLOADS/Movies" \
             "$HOST_DOWNLOADS/TV" \
             "$HOST_DOWNLOADS/Music" \
             "$HOST_DOWNLOADS/Books" \
             "$HOST_DOWNLOADS/Games" \
             "$HOST_DOWNLOADS/Software" \
             "$HOST_DOWNLOADS/Other" \
             "$HOST_GLUE"

    echo "[*] Setting permissions on $HOST_DOWNLOADS and $HOST_CONFIG"
    chown -R "$PUID:$PGID" "$HOST_DOWNLOADS" "$HOST_CONFIG" || true
    chmod -R u+rwX,g+rwX "$HOST_DOWNLOADS" "$HOST_CONFIG" || true

    CFG_DIR="$HOST_CONFIG/qBittorrent"
    # Copy templates only if missing (non-destructive)
    if [ ! -f "$CFG_DIR/qBittorrent.conf" ]; then
      echo "[i] Installing default qBittorrent.conf (first-time only)"
      cp -n "./templates/qBittorrent.conf" "$CFG_DIR/qBittorrent.conf" || true
    fi
    if [ ! -f "$CFG_DIR/categories.json" ]; then
      echo "[i] Installing default categories.json (first-time only)"
      cp -n "./templates/categories.json" "$CFG_DIR/categories.json" || true
    fi
    if [ ! -f "$CFG_DIR/watched_folders.json" ]; then
      echo "[i] Installing default watched_folders.json (first-time only)"
      cp -n "./templates/watched_folders.json" "$CFG_DIR/watched_folders.json" || true
    fi

    echo "[*] Bringing stack up"
    $DC up -d --remove-orphans

    echo
    echo "[OK] Stack is up."
    echo "Open qBittorrent WebUI: http://<NAS_IP>:${WEBUI_PORT}"
    echo "Default credentials (Linuxserver.io image): admin / adminadmin"
    echo "IMPORTANT: Change the admin password first, then run:  sh ./scripts/fix_after_login.sh --harden"
