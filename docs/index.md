# metatrader-docker

MetaTrader in your browser. The MetaTrader terminal and MetaEditor run on a small Linux desktop inside a container, and you use them from any browser as you would on your own computer: charts, Expert Advisors (EAs, the MQL5 programs that trade from a chart), MetaEditor and the Strategy Tester. One container runs one trading account.

It installs MetaTrader 5, MetaQuotes' current release, and runs it under WineHQ staging (Wine runs Windows programs on Linux) on [linuxserver.io's Selkies desktop](https://github.com/linuxserver/docker-baseimage-selkies), Debian 13. It's secure by default:

- a password is required, and the desktop is served over HTTPS only;
- Docker publishes it on the server's loopback address, `127.0.0.1`, unless you choose another;
- other websites can't open your desktop's stream or embed its page;
- the desktop has no terminal and no `sudo`;
- MetaQuotes' installer and Microsoft's WebView2 installer are downloaded at the first start, and run only if their code signatures check out. The image itself contains no MetaQuotes or Microsoft software.

Not affiliated with MetaQuotes or Microsoft.

## What you need

- A Linux server with Docker Engine, on amd64 (x86-64). MetaTrader is a 64-bit Windows program, and there's no ARM build. Docker Compose v2 is optional: `docker run` works too.
- About 4 GB of memory, and about 5 GB of disk once MetaTrader has run for a while. The image itself takes about 4 GB.
- A way to reach the server: SSH is enough.

Then follow the [quick start](quick-start.md).

## What isn't supported

- **ARM.** MetaTrader is a 64-bit Windows program, so the image is amd64 only.
- **VNC.** The desktop streams to browsers only. VNC would mean a second login and a second open port.
- **Microphone and webcam.** They're off, and untested with MetaTrader.
- **Python.** There's no Python bridge or API for MetaTrader. Selkies, the desktop's streaming server, is itself a Python program; it listens only on a socket file inside the container.
- **`init: true`, or `docker run --init`.** The image's own supervisor (s6) has to be process 1: with Docker's init, the container stops at once.
- **EAs that need .NET.** Wine's Mono isn't included.
- **Wayland and WebRTC.** The desktop runs X11 and streams over WebSockets; the startup check refuses the alternatives.

## License

Copyright (C) 2026 Brayan Luna

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](https://github.com/blunan/metatrader-docker/blob/main/LICENSE) for the full text.

The image is built on [linuxserver.io's](https://www.linuxserver.io/) Selkies base image, also GPL-3.0. At the first start it downloads MetaQuotes' MetaTrader 5 and Microsoft's Edge WebView2 Runtime from their publishers. They come under their own license terms, not this project's. This project isn't affiliated with or endorsed by MetaQuotes or Microsoft.
