\
    #!/bin/sh
    # Idempotent fixer for paths, permissions, fastresume case issues,
    # and (optional) WebUI hardening after you change the admin password.
    #
    # Usage:
    #   sh ./scripts/fix_after_login.sh            # patch paths/permissions, resume files; keep WebUI permissive
    #   sh ./scripts/fix_after_login.sh --harden   # also enable WebUI protections (after you changed the password)
    #   sh ./scripts/fix_after_login.sh --rehash-only   # only patch fastresume /downloads -> /Downloads
    #
    set -e

    # Load env
    if [ ! -f ".env" ]; then
      echo "[-] .env not found."; exit 1
    fi
    set -a; . ./.env; set +a

    HARDEN=0
    REHASH_ONLY=0
    for arg in "$@"; do
      case "$arg" in
        --harden) HARDEN=1 ;;
        --rehash-only) REHASH_ONLY=1 ;;
      esac
    done

    CFG_DIR="$HOST_CONFIG/qBittorrent"
    CFG_FILE="$CFG_DIR/qBittorrent.conf"
    BT_DIR="$CFG_DIR/BT_backup"

    echo "[*] Stopping qbittorrent"
    docker stop qbittorrent >/dev/null 2>&1 || true

    if [ "$REHASH_ONLY" -ne 1 ]; then
      echo "[*] Ensuring /Downloads structure exists"
      mkdir -p "$HOST_DOWNLOADS/Incomplete" "$HOST_DOWNLOADS/Torrents"

      # Create category subfolders from categories.json if present
      if [ -f "$CFG_DIR/categories.json" ]; then
        echo "[*] Creating category folders from categories.json"
        # Extract "save_path" values and strip /Downloads/ prefix
        awk -F'"' '/save_path/ {print $4}' "$CFG_DIR/categories.json" \
          | sed -e 's#^/Downloads/##' -e 's#^/*##' \
          | while read -r sub; do
              [ -n "$sub" ] && mkdir -p "$HOST_DOWNLOADS/$sub"
            done
      fi

      echo "[*] Setting permissions on $HOST_DOWNLOADS"
      chown -R "$PUID:$PGID" "$HOST_DOWNLOADS" || true
      chmod -R u+rwX,g+rwX "$HOST_DOWNLOADS" || true

      # Patch qBittorrent.conf keys (append if missing; update if present)
      if [ -f "$CFG_FILE" ]; then
        echo "[*] Patching qBittorrent.conf (paths, network, features)"

        # Remove any previous proxy leftovers (v4/v5)
        sed -i -e '/^Proxy\\\/d' -e '/^Preferences\\Proxy/d' "$CFG_FILE"
        sed -i -e '/^use_proxy=/d' -e '/^proxy_/d' "$CFG_FILE"

        # Force VPN bind to tun0, clean optional address/name
        if grep -q '^Connection\\Interface=' "$CFG_FILE"; then
          sed -i 's#^Connection\\Interface=.*#Connection\\Interface=tun0#' "$CFG_FILE"
        else
          printf '%s\n' 'Connection\Interface=tun0' >> "$CFG_FILE"
        fi
        sed -i '/^Connection\\InterfaceName=/d; /^Connection\\InterfaceAddress=/d' "$CFG_FILE"

        # Enable DHT/PeX/LSD; encryption "Allow" (0)
        if grep -q '^Session\\DHT=' "$CFG_FILE"; then
          sed -i 's#^Session\\DHT=.*#Session\\DHT=true#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\DHT=true' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\PeX=' "$CFG_FILE"; then
          sed -i 's#^Session\\PeX=.*#Session\\PeX=true#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\PeX=true' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\LSD=' "$CFG_FILE"; then
          sed -i 's#^Session\\LSD=.*#Session\\LSD=true#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\LSD=true' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\Encryption=' "$CFG_FILE"; then
          sed -i 's#^Session\\Encryption=.*#Session\\Encryption=0#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\Encryption=0' >> "$CFG_FILE"
        fi

        # Disable queueing
        sed -i '/^Queueing\\QueueingEnabled=/d' "$CFG_FILE"
        printf '%s\n' 'Queueing\QueueingEnabled=false' >> "$CFG_FILE"

        # Save path -> /Downloads ; Temp path -> /Downloads/Incomplete
        if grep -q '^Downloads\\SavePath=' "$CFG_FILE"; then
          sed -i 's#^Downloads\\SavePath=.*#Downloads\\SavePath=/Downloads/#' "$CFG_FILE"
        else
          printf '%s\n' 'Downloads\SavePath=/Downloads/' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\DefaultSavePath=' "$CFG_FILE"; then
          sed -i 's#^Session\\DefaultSavePath=.*#Session\\DefaultSavePath=/Downloads#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\DefaultSavePath=/Downloads' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\TempPathEnabled=' "$CFG_FILE"; then
          sed -i 's#^Session\\TempPathEnabled=.*#Session\\TempPathEnabled=true#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\TempPathEnabled=true' >> "$CFG_FILE"
        fi
        if grep -q '^Session\\TempPath=' "$CFG_FILE"; then
          sed -i 's#^Session\\TempPath=.*#Session\\TempPath=/Downloads/Incomplete#' "$CFG_FILE"
        else
          printf '%s\n' 'Session\TempPath=/Downloads/Incomplete' >> "$CFG_FILE"
        fi
        if grep -q '^Downloads\\TempPath=' "$CFG_FILE"; then
          sed -i 's#^Downloads\\TempPath=.*#Downloads\\TempPath=/Downloads/Incomplete/#' "$CFG_FILE"
        else
          printf '%s\n' 'Downloads\TempPath=/Downloads/Incomplete/' >> "$CFG_FILE"
        fi

        # Keep WebUI permissive until --harden is used
        if grep -q '^WebUI\\Enabled=' "$CFG_FILE"; then
          sed -i 's#^WebUI\\Enabled=.*#WebUI\\Enabled=true#' "$CFG_FILE"
        else
          printf '%s\n' 'WebUI\Enabled=true' >> "$CFG_FILE"
        fi
        if grep -q '^WebUI\\Address=' "$CFG_FILE"; then
          sed -i 's#^WebUI\\Address=.*#WebUI\\Address=*#' "$CFG_FILE"
        else
          printf '%s\n' 'WebUI\Address=*' >> "$CFG_FILE"
        fi
        if grep -q '^WebUI\\Port=' "$CFG_FILE"; then
          sed -i 's#^WebUI\\Port=.*#WebUI\\Port=8080#' "$CFG_FILE"
        else
          printf '%s\n' 'WebUI\Port=8080' >> "$CFG_FILE"
        fi
      fi
    fi

    # Patch .fastresume paths (if any) from /downloads -> /Downloads (case fix)
    if [ -d "$BT_DIR" ]; then
      echo "[*] Backing up and fixing BT_backup fastresume paths"
      cp -a "$BT_DIR" "${BT_DIR}.bak.$(date +%F-%H%M)"
      # BusyBox-friendly recursive grep (-r) + list (-l)
      grep -rl '/downloads' "$BT_DIR" | xargs -r sed -i 's#/downloads#/Downloads#g'
    fi

    # Optional: Harden WebUI after password change
    if [ "$HARDEN" -eq 1 ] && [ -f "$CFG_FILE" ]; then
      echo "[*] Enabling WebUI protections (after password change)"
      # Enable CSRF & Clickjacking protection, and host header validation
      # These keys work across v4/v5; extra keys are harmless if unused.
      if grep -q '^WebUI\\CSRFProtection=' "$CFG_FILE"; then
        sed -i 's#^WebUI\\CSRFProtection=.*#WebUI\\CSRFProtection=true#' "$CFG_FILE"
      else
        printf '%s\n' 'WebUI\CSRFProtection=true' >> "$CFG_FILE"
      fi
      if grep -q '^WebUI\\ClickjackingProtection=' "$CFG_FILE"; then
        sed -i 's#^WebUI\\ClickjackingProtection=.*#WebUI\\ClickjackingProtection=true#' "$CFG_FILE"
      else
        printf '%s\n' 'WebUI\ClickjackingProtection=true' >> "$CFG_FILE"
      fi
      if grep -q '^WebUI\\HostHeaderValidation=' "$CFG_FILE"; then
        sed -i 's#^WebUI\\HostHeaderValidation=.*#WebUI\\HostHeaderValidation=true#' "$CFG_FILE"
      else
        printf '%s\n' 'WebUI\HostHeaderValidation=true' >> "$CFG_FILE"
      fi
      # Optionally whitelist domains/IPs (adjust as needed)
      # printf '%s\n' 'WebUI\ServerDomains=localhost,127.0.0.1' >> "$CFG_FILE"
    fi

    echo "[*] Starting gluetun (in case it was down) and qbittorrent"
    docker start gluetun >/dev/null 2>&1 || true
    docker start qbittorrent >/dev/null 2>&1 || true

    echo "[OK] Done."
    echo "If some torrents show 'stalled' or 'missing files', in WebUI select them and 'Force recheck'."
