# qbt-proton-qnap

**qBittorrent + ProtonVPN (WireGuard) on QNAP** using **Gluetun** with **Automatic port forwarding Mod**, safe defaults, and QNAP-friendly paths.  
Designed especially for **QNAP** NAS.

> Based on and big thanks to: https://github.com/torrentsec/qbittorrent-protonvpn-docker

---

## Features

- qBittorrent traffic forced through **Gluetun** (WireGuard, ProtonVPN)
- **Automatic port forwarding Mod** (keeps qB listening port synced with Gluetun)
- Proton **DNS** (10.2.0.1) and **DoT off**, avoiding Cloudflare DNS leaks
- WebUI published on **host :8081** (QNAP often uses :8080)
- Non-breaking performance tweaks (ulimits, DHT/PeX/LSD on, queueing off)
- All qB settings & JSONs live in **`${CONFIG_ROOT}/qBittorrent/`**

---

## Quick Start (SSH)

> Allow SSH in QNAP Control Panel, script works dine with PuTTY
> **Important:** The `/Downloads` folder **must be empty or non-existent on first run**. Create/move your old **files** **after** the stack is up, then *Force recheck* the torrents from the WebUI.

1. Upload this folder to your NAS, e.g.:
   ```
   /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
   ```

2. Copy `envExample` to `.env` and edit:
   Set :
   - `WIREGUARD_PRIVATE_KEY=REPLACE_WITH_YOUR_WG_PRIVATE_KEY`  
     Get it from **https://account.protonvpn.com** → *Downloads* → *WireGuard*.
   - `GSP_GTN_API_KEY=REPLACE_WITH_A_RANDOM_SECRET_STRING`  
     Put any **long random string** (e.g. `openssl rand -hex 24`). It authenticates the Mod to Gluetun's control server.
   - Adjust `CONFIG_ROOT` and `DOWNLOADS_ROOT` if your pool/volume is not `CACHEDEV3_DATA/SSD2TB`.
   - `SERVER_COUNTRIES=` `SERVER_CITIES=` ProtonVPN Servers location

3. Install & start:
   ```sh
   cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
   sh scripts/install.sh
   ```

4. Open WebUI: `http://<YOUR_NAS_IP>:8081`  
   If qB temporarily changed the password, retrieve it:
   ```sh
   docker logs qbittorrent 2>&1      | grep -A1 "WebUI administrator username is"      | tail -n 1 | awk '{print $NF}'
   ```
   Then **log in and set a new password** immediately. (YourNasLocalIP:8081 → Settings → WebUI )

5. **Mandatory patch after login** (fix paths, apply settings, set listening port):
   ```sh
   cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
   sh scripts/fix_after_login.sh
   ```
   Wait. Wait. Maximum 4 minutes.

7. Move your **files and torrents** into `/Downloads/...` 

8. May need to reboot the NAS or Stop then run again **qbt-proton-qnap** in Container Station

9. *Force recheck* torrents in Qbittorrent WebUI.

10. Done ! You can Change Qbittorrent settings, categories etc.

---

## Configuration

- **WebUI port** on host: `HOST_WEBUI_PORT` (default `8081`)
- **Proton location** defaults:  
  ```
  SERVER_COUNTRIES=France
  SERVER_CITIES=Paris
  ```
  Change them in `.env` as you like.

- **DNS / DoT:**  
  ```
  DOT=off
  DNS_ADDRESS=10.2.0.1
  BLOCK_OUTSIDE_DNS=on
  ```

- **Port Forwarding Mod** variables in `.env`:
  ```
  GSP_GTN_API_KEY=REPLACE_WITH_A_RANDOM_SECRET_STRING
  GSP_QBITTORRENT_PORT=53764
  ```
  `GSP_QBITTORRENT_PORT` is the initial port written to qB config; the Mod keeps it synced with Gluetun after.

---

## qBittorrent defaults (non-breaking)

- Anonymous mode: **disabled**
- Encryption: **Allow** (`Session\Encryption=0`)
- DHT/PeX/LSD: **ON**
- Queueing: **OFF**
- Bind interface: **tun0**
- WebUI HostHeaderValidation: **false** (prevents “Unauthorized” on QNAP hostnames)
- Auth subnet whitelist present but **disabled** by default: `127.0.0.1/32, 192.168.1.0/24`
- File logger enabled, small size (qB will rotate it)

You can further harden security (Host header validation, whitelist, HTTPS, etc.) **later from the WebUI**.

---

## Troubleshooting

- **Port 8080 already in use on QNAP**: We publish WebUI to host `:8081` by default. Change `HOST_WEBUI_PORT` in `.env` if needed.
- **Unauthorized on WebUI**: This repo ships `WebUI\HostHeaderValidation=false` by default to avoid that.
- **Forwarded port shows 0**: The Mod will update qB once Gluetun obtains a forwarded port. You can run `sh scripts/fix_after_login.sh` again after a minute.
- **Force recheck**: If you migrated from `/downloads` (lowercase), the patch replaced to `/Downloads`. Select all errored torrents → *Force recheck*.

---

## Credits

- Base idea & docs from **torrentsec**: https://github.com/torrentsec/qbittorrent-protonvpn-docker
