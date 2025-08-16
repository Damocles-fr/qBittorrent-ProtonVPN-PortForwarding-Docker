# qBittorrent ProtonVPN PortForwarding Docker

## WIP, works on my QNAP HS-264 NAS, installation in /share/CACHEDEV3_DATA/SSD2TB/

**What this project does**  
Runs qBittorrent *entirely inside* ProtonVPN using Gluetun on a QNAP NAS — ensuring full VPN routing **and automatic port forwarding** for improved torrenting performance. The Web UI is published on your LAN while all BitTorrent traffic goes through Proton's WireGuard tunnel.

> Based on the excellent work by **torrentsec**: https://github.com/torrentsec/qbittorrent-protonvpn-docker — thank you, torrentsec ❤️

---

## Features
- ProtonVPN (**WireGuard**) via Gluetun
- Automatic **port forwarding** (Proton P2P servers)
- qBittorrent v5 (LinuxServer.io) running inside the VPN network namespace
- WebUI reachable on your LAN (port-mapped through Gluetun)
- QNAP/BusyBox–safe scripts
- Opinionated but safe defaults:
  - Bind to `tun0`
  - DHT/PeX/LSD **ON**
  - Encryption **Allow** (`0`)
  - Queueing **OFF**
  - English folder layout under `/Downloads` (`Movies`, `TV`, …)
  - Watched folder at `/Downloads/Torrents`
  - Incomplete at `/Downloads/Incomplete`
- **Two-stage WebUI security**: permissive until you log in and change the admin password, then `--harden` switches on protections (CSRF, Clickjacking, host header validation).

---

## Prerequisites (QNAP)
- Container Station with Docker/Compose
- A ProtonVPN **WireGuard** config (P2P/port-forwarding capable server)
  - You need the **PrivateKey** and **Address** from your Proton WG profile.
- Choose absolute host paths (examples below assume `CACHEDEV3_DATA/SSD2TB`).

---

## Quick start
1. Copy this folder to your QNAP, e.g.:  
   `/share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap`
2. Create your env file:
   ```sh
   cd /share/CACHEDEV3_DATA/SSD2TB/stacks/qbt-proton-qnap
   cp .env.example .env
   vi .env   # fill in Proton WG keys, paths, PUID/PGID…
   ```
   - `WG_PRIVATE_KEY` — from your Proton WireGuard config (`PrivateKey=`).
   - `WG_ADDRESSES` — from your Proton WireGuard config (`Address=`), e.g. `10.2.0.2/32`.
   - `HOST_CONFIG`, `HOST_DOWNLOADS`, `HOST_GLUE` — QNAP absolute paths.
   - `PUID` / `PGID` — your Container Station user/group IDs.
   - `LAN_SUBNETS` — your LAN (e.g. `192.168.1.0/24`).
3. Install & start:
   ```sh
   sh ./scripts/install.sh
   ```
4. Open qBittorrent WebUI: `http://<NAS_IP>:8080`  
   Default LinuxServer credentials: **admin / adminadmin**
**Or**
   Password may have automatically changed to a temporary one.  
To see it, run:
~~~sh
docker logs qbittorrent 2>&1 \
  | grep -A1 "WebUI administrator username is" \
  | tail -n 1 \
  | awk '{print $NF}'
~~~

5. **Immediately change the admin password** in WebUI.
6. Harden the WebUI and finalize fixes:
   ```sh
   sh ./scripts/fix_after_login.sh --harden
   ```
   If some torrents show *Missing files* or *Stalled*, select them and **Force recheck** in the WebUI.

---

## Files & layout
```
qbt-proton-qnap-en/
├─ docker-compose.yml
├─ .env.example
├─ templates/
│  ├─ qBittorrent.conf             # minimal, only used if missing
│  ├─ categories.json              # English categories under /Downloads
│  └─ watched_folders.json         # watches /Downloads/Torrents
└─ scripts/
   ├─ install.sh                   # create folders, rights, bring up stack
   └─ fix_after_login.sh           # patch paths/permissions/resume; --harden
```

qBittorrent data/config is stored on the host at:  
`${HOST_CONFIG}/qBittorrent` (includes `qBittorrent.conf`, `BT_backup`, `categories.json`, `watched_folders.json`).

---

## Proton WireGuard: where keys go
From your Proton `.conf`:
```ini
[Interface]
PrivateKey = <copy this to WG_PRIVATE_KEY>
Address    = <copy this to WG_ADDRESSES, e.g. 10.2.0.2/32>
```
You **do not** need to paste DNS or peer info — Gluetun handles servers/peers.

Optional filters you can set in `.env` if you want to pin regions:
- `SERVER_COUNTRIES=` (e.g. `Netherlands,Switzerland`)
- `SERVER_CITIES=`
- `SERVER_HOSTNAMES=`

### Port forwarding
`PORT_FORWARDING=on` is enabled in Gluetun. Use Proton **P2P** servers that support port forwarding. Gluetun opens the port and keeps firewall rules updated. Your qBittorrent listens on its usual port inside the VPN; the forwarded port is handled by Gluetun’s firewall/NAT layer.

---

## Security model (avoid “unauthorized” lockouts)
- On first boot, WebUI is **permissive** (`Address=*`, `Port=8080`) so you can reach it and change the password.
- After you change the password, run:
  ```sh
  sh ./scripts/fix_after_login.sh --harden
  ```
  This enables:
  - `WebUI\CSRFProtection=true`
  - `WebUI\ClickjackingProtection=true`
  - `WebUI\HostHeaderValidation=true`

  If you reverse-proxy the UI later, add appropriate host/domain whitelists in `qBittorrent.conf` (keys vary by version; see comments in the script).

---

## Troubleshooting
- **Stalled / missing files** after migration from `/downloads` (lowercase):  
  Run `sh ./scripts/fix_after_login.sh --rehash-only` then in WebUI **Force recheck**.
- **Permissions** on QNAP: scripts always `chown -R PUID:PGID` and grant group write on all `/Downloads` and config paths.
- **WebUI not reachable**:
  - Check you mapped the correct `WEBUI_PORT` in `.env`.
  - Ensure `LAN_SUBNETS` matches your LAN (e.g. `192.168.1.0/24`).
  - `docker logs gluetun` — you should see the composed iptables rules allowing that port.
- **Proton port forwarding**:
  - Use P2P servers that support PF.
  - See `docker logs gluetun` for the forwarded port status.
- **Bind to VPN**:
  - We set `Connection\Interface=tun0` in `qBittorrent.conf`. Traffic stays inside the tunnel.

---

## Credits
- Massive thanks to **torrentsec** for their original project and guidance:
  - Repo: https://github.com/torrentsec/qbittorrent-protonvpn-docker
  - Profile: https://github.com/torrentsec

---

## License
This project is licensed under the MIT License – see the LICENSE file for details.

---

## Github
[Damocles-fr](https://github.com/Damocles-fr)
