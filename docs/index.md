# metatrader-docker

MetaTrader in your browser. Run the MetaTrader 5 terminal and MetaEditor in a lightweight Linux desktop container accessible from any browser: charts, Expert Advisors (EAs), MetaEditor, and Strategy Tester. One container runs one trading account.

Runs under WineHQ staging on [linuxserver.io's Selkies desktop](https://github.com/linuxserver/docker-baseimage-selkies) (Debian 13). Secure defaults include:

- Required password authentication, served exclusively over HTTPS.
- Published to loopback (`127.0.0.1`) by default.
- Strict origin controls preventing external streaming or framing.
- Hardened desktop environment without terminal access or `sudo`.
- Authenticode signature verification on initial downloads (MetaQuotes, Edge WebView2, optional Python). Base image contains no proprietary binaries.

Not affiliated with or endorsed by MetaQuotes or Microsoft.

## What you need

- **System:** Linux host on amd64 (x86-64) with Docker Engine (Compose v2 optional). MetaTrader is 64-bit Windows software without ARM support.
- **Resources:** ~4 GB RAM and ~5–10 GB disk space (~4 GB base image + runtime data).
- **Access:** SSH or local console access to the host.

Follow the [quick start](quick-start.md) to begin.

## What isn't supported

- **ARM architecture:** MetaTrader 5 is a 64-bit x86 Windows binary; amd64 only.
- **VNC:** The desktop streams via WebSockets to browsers only.
- **Microphone and webcam:** Disabled by default.
- **Remote Python bridge:** `MT_PYTHON=true` provides Python and `MetaTrader5` locally inside the container (on charts or via `docker exec`), but does not expose an external network API.
- **`init: true` / `--init`:** The container requires its built-in s6 supervisor as process 1.
- **.NET-dependent EAs:** Wine Mono is not included.
- **Wayland / WebRTC:** The desktop runs X11 and WebSockets; alternative modes are refused at startup.

## License

Copyright (C) 2026 Brayan Luna

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. It is distributed in the hope it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](https://github.com/blunan/metatrader-docker/blob/main/LICENSE) for the full text.

Built on [linuxserver.io's](https://www.linuxserver.io/) Selkies base image (GPL-3.0). During initial setup, the container downloads MetaTrader 5 and Edge WebView2 Runtime from their respective publishers (and Python / packages if `MT_PYTHON=true`). These components are subject to their own license terms. Not affiliated with or endorsed by MetaQuotes or Microsoft.
