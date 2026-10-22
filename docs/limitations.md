# What isn't supported

- **ARM.** MetaTrader is a 64-bit Windows program, so the image is amd64 only.
- **VNC.** The desktop streams to browsers only. VNC would mean a second login and a second open port.
- **Microphone and webcam.** They're off, and untested with MetaTrader.
- **Python.** There's no Python bridge or API for MetaTrader. Selkies, the desktop's streaming server, is itself a Python program; it listens only on a socket file inside the container.
- **`init: true`, or `docker run --init`.** The image's own supervisor (s6) has to be process 1: with Docker's init, the container stops at once.
- **EAs that need .NET.** Wine's Mono isn't included.
- **Wayland and WebRTC.** The desktop runs X11 and streams over WebSockets; the startup check refuses the alternatives.
