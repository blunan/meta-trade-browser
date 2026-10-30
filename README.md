# 📈 metatrader-docker

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-metatrader--docker.blunan.com-526CFE?logo=materialformkdocs&logoColor=white)](https://metatrader-docker.blunan.com/)
[![Image](https://img.shields.io/badge/image-ghcr.io%2Fblunan%2Fmetatrader--docker-2496ED?logo=docker&logoColor=white)](https://github.com/blunan/metatrader-docker/pkgs/container/metatrader-docker)
[![Image build](https://github.com/blunan/metatrader-docker/actions/workflows/image.yml/badge.svg?branch=main)](https://github.com/blunan/metatrader-docker/actions/workflows/image.yml)
[![Signed with cosign](https://img.shields.io/badge/signed-cosign-6D28D9)](https://metatrader-docker.blunan.com/verify/)
![Platform: linux/amd64](https://img.shields.io/badge/platform-linux%2Famd64-lightgrey?logo=linux&logoColor=white)
![MetaTrader 5](https://img.shields.io/badge/MetaTrader-5-4A76B8)
![Wine staging](https://img.shields.io/badge/Wine-staging-800000?logo=wine&logoColor=white)
![Debian 13 trixie](https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white)
![Python 3.14](https://img.shields.io/badge/Python-3.14-3776AB?logo=python&logoColor=white)

**MetaTrader in your browser.** Run the MetaTrader 5 terminal and MetaEditor in a lightweight Linux desktop container accessible from any browser: charts, Expert Advisors (EAs), MetaEditor, and Strategy Tester. One container runs one trading account.

Runs under WineHQ staging on [linuxserver.io's Selkies desktop](https://github.com/linuxserver/docker-baseimage-selkies) (Debian 13).

> 📖 **Full guide at [metatrader-docker.blunan.com](https://metatrader-docker.blunan.com/):** reverse proxies, VPNs, settings, updates, and troubleshooting.

## ✨ Features

* 🌐 **Any browser** — Charts, EAs, MetaEditor, and Strategy Tester with shared clipboard and audio support.
* 🔐 **HTTPS & password** — Required password authentication; served strictly over HTTPS.
* 🏠 **Private by default** — Binds to loopback (`127.0.0.1`) by default. Access via SSH tunnel, VPN, or reverse proxy.
* 🛡️ **Hardened desktop** — No terminal or `sudo`; origin checks prevent stream hijacking and framing.
* ✅ **Verified installers** — Downloads MetaQuotes, Microsoft Edge WebView2, and optional Python installers at first boot only after verifying Authenticode signatures. Base image contains no proprietary binaries.
* 📂 **Custom EA directory** — Mount host directories into MetaTrader under `MQL5/<section>/Mounted`.
* 🐍 **Optional Python** — Set `MT_PYTHON=true` to install Windows Python and MetaQuotes' `MetaTrader5` package for Python scripting.
* 💾 **Graceful shutdown** — Saves charts and settings across stops; automatically relaunches on unexpected exit.

> ⚠️ Not affiliated with or endorsed by MetaQuotes or Microsoft.

## 📋 Table of contents

* [Quick start](#-quick-start)
* [The guide](#-the-guide)
* [License](#-license)

## 🚀 Quick start

**🧰 You need** a Linux server with Docker Engine and Compose v2, on amd64 (x86-64), with about 4 GB of memory and 10 GB of disk, and SSH access to it.

**1. Create the folders and the desktop password** on the server:

```sh
mkdir -p metatrader-docker && cd metatrader-docker
mkdir -p -m 700 data secrets
mkdir -p ea
openssl rand -base64 24 | tr -d '\n' > secrets/password
cat secrets/password; echo
sudo chown root:root secrets/password
sudo chmod 0400 secrets/password
```

Keep the password in your password manager (`sudo cat secrets/password` to view). `data` stores broker credentials (mode 700), and `ea` holds custom MQL5 files. If your host user/group differs from 1000, set `PUID` and `PGID` in `compose.yaml`.

**2. Save this as `compose.yaml`** in the same folder:

```yaml
# metatrader-docker: MetaTrader in your browser, one container for one trading account.
services:
  metatrader-docker:
    image: ghcr.io/blunan/metatrader-docker:latest    # or pinned date tag e.g. :20261019.1
    container_name: metatrader-docker
    restart: unless-stopped
    stop_grace_period: 30s                     # allow MetaTrader to persist state cleanly
    # Never add init: true: image s6 supervisor must be process 1.
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]   # required for desktop startup
    shm_size: 1gb
    mem_limit: 4g                              # 6g for heavy HTML pane usage (Help, Market)
    environment:
      FILE__PASSWORD: /run/secrets/password
    secrets: [password]
    volumes:
      - ./data:/config                         # persistent account data
      - ./ea:/mql5                             # optional: custom EAs, indicators and scripts
    ports:
      - "127.0.0.1:3001:3001"                  # localhost only: reach via SSH tunnel or reverse proxy

secrets:
  password:
    file: ./secrets/password
```

Without Compose, see the [quick start](https://metatrader-docker.blunan.com/quick-start/#4-start-it) for equivalent `docker run` syntax.

**3. Start it** and follow its log:

```sh
docker compose up -d
docker compose logs -f
```

Initial setup downloads and installs WebView2 and MetaTrader (~2–3 minutes), completing when the log reports `starting MetaTrader`.

**4. Open the desktop.** On your computer, open an SSH tunnel to the server:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Browse to `https://localhost:3001` and accept the self-signed certificate (see guide to [trust it locally](https://metatrader-docker.blunan.com/quick-start/#5-open-the-desktop)). Sign in as `trader` with your password.

**5. Configure MetaTrader.** Log in with *Save password* enabled. Configure algorithmic trading protections in **Tools → Options → Experts** as shown in [step 6](https://metatrader-docker.blunan.com/quick-start/#6-set-up-metatrader).

## 📖 The guide

| Page | What's in it |
| :--- | :--- |
| 🚀 [Quick start](https://metatrader-docker.blunan.com/quick-start/) | Complete setup guide, `docker run` flags, and local certificate trust |
| 🌍 [Access and reverse proxy](https://metatrader-docker.blunan.com/access/) | SSH tunnel, VPN, Tailscale, Caddy, nginx, Traefik, cloudflared, custom certificates, and host networking |
| ⚙️ [Folders and settings](https://metatrader-docker.blunan.com/settings/) | Volume mounts, backups, environment variables, validation rules, and warnings |
| 🖱️ [Using MetaTrader](https://metatrader-docker.blunan.com/using/) | Clipboard, audio, shortcuts, MetaEditor, HTML panes, memory sizing, and Python scripting |
| 🔄 [Operations and updates](https://metatrader-docker.blunan.com/operations/) | Graceful shutdown, restarts, health check, image tags, updates, and LiveUpdate |
| 🩺 [Troubleshooting](https://metatrader-docker.blunan.com/troubleshooting/) | Log locations, common installation failures, and benign startup warnings |
| 🔏 [Security and verification](https://metatrader-docker.blunan.com/verify/) | Image digest pinning, Cosign verification, outbound traffic, and AI-agent servers |
| 🛠️ [Build it yourself](https://metatrader-docker.blunan.com/building/) | Local Docker builds, test suite, CI workflows, and documentation preview |

## 📄 License

Copyright (C) 2026 Brayan Luna

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.

Built on [linuxserver.io's](https://www.linuxserver.io/) Selkies base image (GPL-3.0). During initial setup, the container downloads MetaTrader 5 and Edge WebView2 Runtime from their respective publishers (and Python / packages if `MT_PYTHON=true`). These components are subject to their own license terms. Not affiliated with or endorsed by MetaQuotes or Microsoft.
