# qbt-proton-docker

**qBittorrent + ProtonVPN (WireGuard) on QNAP**, fully routed through VPN with **automatic port forwarding Mod**, DNS set to **Proton (10.2.0.1)**, and a startup that avoids the qB WebUI *Unauthorized* issue with QNAP Container Station.

## UPDATE v09 : Should works with latest Gluetun, mod, and qBittorrent

## What you get

- qBittorrent behind **Gluetun (ProtonVPN WireGuard)**  
- **Automatic port forwarding GSP Mod** (keeps qB's listen port synced with Gluetun)
- WebUI exposed on **host `:8081`** (QNAP already uses `:8080`)
- Proton **DNS 10.2.0.1** and WG address **10.2.0.2/32** (no Cloudflare)
- Safe first-boot WebUI options to avoid *Unauthorized*
- Clean structure, consistent paths:
  - Config: `${CONFIG_ROOT}/qBittorrent/`
  - Downloads: `/Downloads` (host `${DOWNLOADS_ROOT}`)
  - Categories & watched folders for new .torrent

Tested on **QNAP HS-264 + 2.5" SSD**

---

## 1) Prepare

1. **Upload this repo** to your NAS, e.g. `/share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap`
2. Copy `envExample` to `.env` and **edit it**:
   - `WIREGUARD_PRIVATE_KEY` → get it from **https://account.protonvpn.com/**
   - `GLUETUN_API_KEY` → generate with `docker run --rm qmcgaw/gluetun genkey` and copy the output, Or write any **long random string**
   - Adjust `CONFIG_ROOT` and `DOWNLOADS_ROOT` if your pool is not `CACHEDEV3_DATA` or not `SSD2TB`
   - Adjust `SERVER_COUNTRIES` / `SERVER_CITIES` to any ProtonVPN server location (with P2P/port‑forwarding).

> **Important:** The `/Downloads` folder **must be empty or non‑existent** for the first start. Move your **files** after the stack is up, then *Force recheck* in qBittorrent.

## 2) Install

- Allow SSH in QNAP Control Panel, the script works fine with PuTTY
```sh
cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
sh scripts/install.sh
```

- WebUI is at: `http://<your-nas-ip>:8081` (user `admin`)
- If qBittorrent changed the password automatically, to print it:
  ```sh
  docker logs qbittorrent 2>&1     | grep -A1 "WebUI administrator username is"     | tail -n 1     | awk '{print $NF}'
  ```

- **Mandatory : Log in once**
- (Optional) Move your own **torrents** into `/Downloads/...` and your **BT_backup** into into `AppData/qbt-proton/qBittorrent` 

## 3) After login — run the fix

- **Mandatory**: Run this script once after initial login or when you restored torrents

```sh
cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
sh scripts/fix_after_login.sh
```
- Wait. Wait. 1 to 5 minutes.

What it does:

	- Stops qB & Gluetun cleanly (with waits)
	- Patches `.fastresume` from `/downloads` → `/Downloads`
	- Ensures `/Downloads/Incomplete` and `/Downloads/Torrents` exist
	- Starts Gluetun (waits until **healthy**), then qB
	- Reads the **forwarded port** from Gluetun
	- Applies qB settings **via WebUI API** (not file edits) to avoid *Unauthorized*:
	- `bypass_local_auth=true`
	- `web_ui_host_header_validation=false`
	- `web_ui_csrf_protection_enabled=false`
	- whitelist `127.0.0.1/32,::1/128`
	- save path `/Downloads`, temp `/Downloads/Incomplete`
	- listen port = forwarded port
	- Restarts qB and verifies
	
- Some may need to reboot the NAS or stop then run again **qbt-proton-qnap** in Container Station
- If you have put your torrents in the correct paths, *Force recheck* them in Qbittorrent WebUI.

## 4) Done !

- **log in and set a new password** (qBittorrent → Settings → WebUI )
- Security note : after everything works **and after you changed the admin password**, consider enabling tighter options in qB WebUI
- New .torrent added in /Downloads/Torrents are automatically added to qBittorrent. (You can set qBittorrent → Settings → Downloads → Default Save Path → Copy .torrent files for finished downloads to: /Downloads/torrentsfiles)
- Use categories to move your files, e.g. create categories like "FILM_To_Move" and and set the NAS to automatically relocate the folder contents.
- Qnap has an app called Qfilling that is easy to use and perfect for that.


## 5) Check everything (optional)

```sh
# VPN public IP
docker run --rm --network=container:gluetun alpine:3.20   sh -c 'apk add -q --no-progress curl >/dev/null && curl -s https://ipinfo.io'

# DNS leak test (script default)
docker run --rm --network=container:gluetun alpine:3.20 sh -c '  apk add -q --no-progress curl wget >/dev/null &&   curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/master/dnsleaktest.sh -o /tmp/d &&   chmod +x /tmp/d && /tmp/d'

# Forwarded port from Gluetun
docker exec gluetun sh -lc 'cat /tmp/gluetun/forwarded_port || curl -s http://localhost:8000/v1/openvpn/portforwarded'
```
---

## Files & Structure

```
qbt-proton-qnap/
├─ envExample                 # copy to .env and edit
├─ docker-compose.yml
├─ scripts/
│  ├─ install.sh
│  └─ fix_after_login.sh
└─ qBittorrent/
   ├─ qBittorrent.conf
   ├─ categories.json
   └─ watched_folders.json
```

- All qB config files end up in `${CONFIG_ROOT}/qBittorrent/`
- Downloads are in `${DOWNLOADS_ROOT}` mounted at `/Downloads`

## Notes on Gluetun DNS & API

- We use **Proton DNS 10.2.0.1** and set `DOT=off` so DNS is not routed via Gluetun’s Unbound.
- The Gluetun **control server** (port 8000 **inside** the container) is protected by an **API key** defined in `.env` (`GLUETUN_API_KEY`) and written to `/gluetun/auth/config.toml`.
- The qB **GSP Mod** uses the same API key (`GSP_GTN_API_KEY`) to read the forwarded port and keep qB in sync.

## Defaults

- Country/City: `France / Paris`
- WebUI: host `:8081`
- qB: anonymous mode **disabled**, encryption **Allow**, UPnP **off**
- ulimits: `nofile` soft `32768`, hard `65536`

You can change `SERVER_COUNTRIES` / `SERVER_CITIES` in `.env`. See Proton’s list for other P2P/port‑forwarding cities.

## Troubleshooting

- **Unauthorized on WebUI**  
  Always run `scripts/fix_after_login.sh` once after first login. It applies the API settings that prevent the 401 with LSIO + Mod.

- **Port 8081 busy**  
  Change `WEBUI_HOST_PORT` in `.env`, then `docker compose down && docker compose up -d`.

- **Paths mismatch or torrents “missing files”**  
  Ensure you moved your **files** only **after** the first start. Then select torrents and *Force recheck*.

- **Forwarded port is 0**  
  Wait until Gluetun is healthy. Check `docker logs gluetun | grep -i forward`.

- **You messed up with qBittorrent settings**  
  Stop the app **qbt-proton-qnap** in Container Station  
  Copy **qBittorrent.conf** from `stacks\qbt-proton-qnap\qBittorrent` and paste/replace into `AppData\qbt-proton\qBittorrent`  
  Re-run the fix script :
  ```sh
  cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
  sh scripts/fix_after_login.sh
  ```

- If qBittorrent changed the password automatically, to print it:
  ```sh
  docker logs qbittorrent 2>&1     | grep -A1 "WebUI administrator username is"     | tail -n 1     | awk '{print $NF}'
  ```
  
## Security note (what to change later if needed)

This starter is intentionally permissive for WebUI to avoid “Unauthorized” on QNAP.  
After everything works **and after you changed the admin password**, consider enabling tighter options in qB WebUI:

- Enable **Host header validation**
- Enable **CSRF protection**
- Restrict **Auth subnet whitelist** to your LAN
- Optionally close WebUI exposure and use a reverse proxy with Auth

Edit through the WebUI (recommended, settings there can break the WebUI identification) or adjust and re-run the fix script with your desired values.

---

## Credits

- Based on: <https://github.com/torrentsec/qbittorrent-protonvpn-docker>
- Thanks <https://github.com/torrentsec>
- Thanks <https://github.com/t-anc/GSP-Qbittorent-Gluetun-sync-port-mod>
- Thanks <https://github.com/qdm12/gluetun>

## License
This project is licensed under the MIT License – see the LICENSE file for details.

## Github
[https://github.com/Damocles-fr/](https://github.com/Damocles-fr)
