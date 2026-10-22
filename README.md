# 📈 mt-browser

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-mt--browser.blunan.com-526CFE?logo=materialformkdocs&logoColor=white)](https://mt-browser.blunan.com/)
[![Image](https://img.shields.io/badge/image-ghcr.io%2Fblunan%2Fmt--browser-2496ED?logo=docker&logoColor=white)](https://github.com/blunan/mt-browser/pkgs/container/mt-browser)
![Platform: linux/amd64](https://img.shields.io/badge/platform-linux%2Famd64-lightgrey?logo=linux&logoColor=white)
![MetaTrader 5](https://img.shields.io/badge/MetaTrader-5-4A76B8)
![Wine staging](https://img.shields.io/badge/Wine-staging-800000?logo=wine&logoColor=white)
![Debian 13 trixie](https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white)

**MetaTrader in your browser.** The MetaTrader terminal and MetaEditor run on a small Linux desktop inside a container, and you use them from any browser as you would on your own computer: charts, Expert Advisors (EAs, the MQL5 programs that trade from a chart), MetaEditor and the Strategy Tester. One container runs one trading account.

It installs MetaTrader 5, MetaQuotes' current release, and runs it under WineHQ staging (Wine runs Windows programs on Linux) on [linuxserver.io's Selkies desktop](https://github.com/linuxserver/docker-baseimage-selkies), Debian 13.

> 📖 **The full guide is at [mt-browser.blunan.com](https://mt-browser.blunan.com/):** reverse proxies and VPNs, settings, updates and troubleshooting.

## ✨ Features

* 🌐 **Any browser** — charts, EAs, MetaEditor and the Strategy Tester, as on your own computer, with the clipboard and MetaTrader's sounds.
* 🔐 **Password and HTTPS** — a password is required, and the desktop is served over HTTPS only.
* 🏠 **Private by default** — Docker publishes it on the server's loopback address, `127.0.0.1`, unless you choose another. Reach it through an SSH tunnel, a VPN or your own reverse proxy.
* 🛡️ **A locked-down desktop** — no terminal and no `sudo`, and other websites can't open your desktop's stream or embed its page.
* ✅ **Signature-checked installers** — MetaQuotes' installer and Microsoft's WebView2 installer are downloaded at the first start, and run only if their code signatures check out. The image itself contains no MetaQuotes or Microsoft software.
* 📂 **Your EAs, your folder** — an optional folder of your EAs, indicators and scripts appears in MetaTrader as `Mounted`.
* 💾 **Clean stops** — MetaTrader saves its charts and settings at every stop, and starts again by itself if it closes or crashes.

> ⚠️ Not affiliated with or endorsed by MetaQuotes or Microsoft.

## 📋 Table of contents

* [Quick start](#-quick-start)
* [The guide](#-the-guide)
* [License](#-license)

## 🚀 Quick start

**🧰 You need** a Linux server with Docker Engine and Compose v2, on amd64 (x86-64), with about 4 GB of memory and 10 GB of disk, and SSH access to it.

**1. Create the folders and the desktop password** on the server:

```sh
mkdir -p mt-browser && cd mt-browser
mkdir -p -m 700 data secrets
mkdir -p ea
openssl rand -base64 24 | tr -d '\n' > secrets/password
cat secrets/password; echo
sudo chown root:root secrets/password
sudo chmod 0400 secrets/password
```

Keep the password in your password manager; from then on, `sudo cat secrets/password` shows it. `data` will hold your saved broker logins, and `ea` is the optional EA folder. The container works as user and group 1000: if `id -u` or `id -g` prints another number, set `PUID` and `PGID` to them.

**2. Save this as `compose.yaml`** in the same folder:

```yaml
# mt-browser: MetaTrader in your browser, one container for one trading account.
# The quick start creates the folders and the password file first.
services:
  mt-browser:
    image: ghcr.io/blunan/mt-browser:latest    # or a date tag such as :20261019, to stay on one build
    container_name: mt-browser
    restart: unless-stopped
    stop_grace_period: 30s                     # time for MetaTrader to save its charts and settings
    # Never add init: true: the image's own supervisor has to be process 1.
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]   # the desktop's startup needs all six
    shm_size: 1gb
    mem_limit: 4g                              # 6g for heavy use of the HTML panes (Help, Market)
    environment:
      FILE__PASSWORD: /run/secrets/password
    secrets: [password]
    volumes:
      - ./data:/config                         # everything for the account
      - ./ea:/mql5                             # optional: your EAs, indicators and scripts
    ports:
      - "127.0.0.1:3001:3001"                  # this machine only: an SSH tunnel or a proxy reaches it

secrets:
  password:
    file: ./secrets/password
```

Without Compose, the guide's [quick start](https://mt-browser.blunan.com/quick-start/#4-start-it) has the same container as a `docker run` command.

**3. Start it** and follow its log:

```sh
docker compose up -d
docker compose logs -f
```

The first start installs Microsoft Edge WebView2 and MetaTrader. It takes about 2–3 minutes, and it's done when the log says `starting MetaTrader`.

**4. Open the desktop.** On your own computer, open an SSH tunnel to the server and leave it open:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Then browse to `https://localhost:3001`, and accept the certificate warning: the container made its own certificate (the guide shows [how to trust it](https://mt-browser.blunan.com/quick-start/#5-open-the-desktop)). Sign in as `trader` with the password.

**5. Set up MetaTrader.** Log in to your trading account with *Save password* ticked. Before an EA trades, turn on MetaTrader's algo-trading protections, as the guide's [step 6](https://mt-browser.blunan.com/quick-start/#6-set-up-metatrader) shows.

## 📖 The guide

| Page | What's in it |
| :--- | :--- |
| 🚀 [Quick start](https://mt-browser.blunan.com/quick-start/) | Every step in full, with `docker run` as well as Compose, and how to trust the certificate |
| 🗂️ [Folders and files](https://mt-browser.blunan.com/folders/) | What `data`, `ea` and the password file hold, and backups |
| 🌍 [Reaching the desktop](https://mt-browser.blunan.com/access/) | SSH tunnel, VPN, Tailscale and host networking |
| 🔀 [Behind a reverse proxy](https://mt-browser.blunan.com/reverse-proxy/) | Your own domain with Caddy, nginx, Traefik or cloudflared |
| 🖱️ [Using MetaTrader](https://mt-browser.blunan.com/using/) | Clipboard, sound, shortcuts, MetaEditor, the HTML panes and memory |
| ⚙️ [Settings](https://mt-browser.blunan.com/settings/) | Every setting, and what the startup check refuses or warns about |
| 🔄 [Updates](https://mt-browser.blunan.com/updates/) | Image tags, updating and going back, and MetaTrader's LiveUpdate |
| 🩺 [Troubleshooting](https://mt-browser.blunan.com/troubleshooting/) | Where the logs are, failed installs and harmless messages |
| 🔏 [Verify the image](https://mt-browser.blunan.com/verify/) | Pin a digest and check its cosign signature |

## 📄 License

Copyright (C) 2026 Brayan Luna

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.

The image is built on [linuxserver.io's](https://www.linuxserver.io/) Selkies base image, also GPL-3.0. At the first start it downloads MetaQuotes' MetaTrader 5 and Microsoft's Edge WebView2 Runtime from their publishers. They come under their own license terms, not this project's. This project isn't affiliated with or endorsed by MetaQuotes or Microsoft.
