# Settings

Set these under `environment` in `compose.yaml`, or with `-e` in `docker run`. Changes take effect when the container is recreated: `docker compose up -d`, or remove the container and run it again.

## The main settings

| Setting | Default | What it does |
|---|---|---|
| `FILE__PASSWORD` | none | **Required:** the path of the desktop password's file. At least 12 characters, and not a well-known placeholder such as `password` or `changeme`. A line break at the end is ignored. `PASSWORD`, the password itself, works too, but `docker inspect` shows it. |
| `PUID`, `PGID` | `1000` | The user and group that own `/config` and the desktop's programs. Set them to your `id -u` and `id -g` when those aren't 1000. |
| `CUSTOM_USER` | `trader` | The desktop's login name. |
| `TITLE` | `MetaTrader` | The browser tab's name. |
| `TZ` | UTC | The desktop's time zone. MetaTrader shows its server's time anyway. |
| `SELKIES_CLIPBOARD_ENABLED` | `true` | The shared clipboard: `true`, `in` (browser to desktop only), `out` (desktop to browser only) or `false`. |
| `SELKIES_FILE_TRANSFERS` | `false` | `true` turns on file transfers through the browser, and the side panel's file panel with them. `upload` or `download` allows one direction only. |
| `FILE_MANAGER_PATH` | MetaTrader's `MQL5/Experts`, in `/config` | Where uploads land, and the folder the file panel offers downloads from. The panel can't choose another folder. By default, an uploaded EA appears in the Navigator under *Expert Advisors* after *Refresh*, with or without an EA folder. |
| `MT_AI_AGENTS` | off | `true` turns on MetaTrader's and MetaEditor's servers for AI agents (see [What it connects to](network.md#metatraders-ai-agent-servers)). |

## Reverse proxy, VPN and host networking

See [Reaching the desktop](access.md).

| Setting | Default | What it does |
|---|---|---|
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | none | A certificate and key of your own to serve, as paths inside the container. Without them the container serves `/config/ssl/cert.pem` and `cert.key`. If they don't exist, it makes its own there: self-signed, issued to `localhost`, `127.0.0.1` and `::1`, unable to sign other certificates, and valid for 825 days. A start in its last 30 days renews it. You can put your own certificate in those two files instead; the container never touches it. A new certificate takes effect at the next container restart. |
| `TRUSTED_PROXIES` | none | IP addresses or ranges, such as `172.20.0.5` or `10.8.0.0/24`. When set, only they get in, and everyone else gets 403. Requests from them have their `X-Forwarded-For` logged. |
| `SELKIES_ALLOWED_ORIGINS` | none: the page's own origin only | Other origins allowed to open the stream, comma-separated, such as `https://mt.example.com`. `*` is refused. |
| `SUBFOLDER` | `/` | Serves the desktop under a path, such as `/mt/`. |
| `CUSTOM_HTTPS_PORT` | `3001` | The HTTPS port inside the container. |
| `LISTEN_ADDRESS` | all of the container's addresses; `127.0.0.1` with host networking | The one address the HTTPS port listens on. |

## Wine's own

For troubleshooting:

| Setting | Default | What it does |
|---|---|---|
| `WINEDEBUG` | `fixme-all,err-toolbar` | What Wine writes to the log: its errors, minus the noise from MetaTrader's toolbar. During the first start's install, Wine writes nothing, unless you set `WINEDEBUG` yourself. For troubleshooting, `fixme-all` brings the toolbar's errors back, and an empty value restores Wine's defaults, which add its "fixme" notes. |
| `WINEDLLOVERRIDES` | `mscoree,mshtml=` | Turns off Wine's Mono (.NET) and Gecko (Internet Explorer's engine), so Wine never stops to offer them; MetaTrader uses neither. A value of your own replaces this one, so keep those two in it. |

## Other settings

The base image's and Selkies' other settings, such as `SELKIES_ENCODER` or `LC_ALL`, reach them unchanged: nothing filters the container's environment. They aren't tested with this image. A value you set replaces the image's own, its protections included: `SELKIES_MICROPHONE_ENABLED=true` brings the microphone back, for instance. The refusals below still apply.

Three have no effect, because the container replaces the base's web server setup with its own: `CUSTOM_PORT`, `CUSTOM_WS_PORT` and `DISABLE_IPV6`.

## Refused

The container stops at once, and its log says why in a `[mt-access] REFUSED:` line. With `restart: unless-stopped`, `docker ps` then shows it *Restarting*. These settings remove a protection and have no use here:

- no password, a file that can't be read, fewer than 12 characters, or a well-known placeholder;
- `SELKIES_ALLOWED_ORIGINS` with `*`: any website could open your stream;
- a `TRUSTED_PROXIES` that covers every address (`0.0.0.0/0`, `::/0`), or holds something that isn't an address or range;
- only one of `TLS_CERT_FILE` and `TLS_KEY_FILE`, a path with unusual characters, or a file that can't be read;
- privileged mode (`privileged: true`, or `cap_add: SYS_ADMIN`), or the Docker socket mounted: the desktop would control the server;
- `DEV_MODE`, `PIXELFLUX_WAYLAND=true`, `SELKIES_MODE=webrtc`, `SELKIES_ENABLE_DUAL_MODE=true`, `SELKIES_COMPUTER_USE_BIND`, or another `SELKIES_UNIX_SOCKET`. These are the base image's development mode, its Wayland desktop, WebRTC streaming, and extra servers outside the login;
- a malformed `CUSTOM_HTTPS_PORT`, `CUSTOM_USER`, `SUBFOLDER` or `LISTEN_ADDRESS`;
- a `SELKIES_FILE_TRANSFERS` or `SELKIES_CLIPBOARD_ENABLED` value other than those in the table: Selkies would read one such as `off` as on, both ways.

## Warned about

In the log, because you might have a reason:

- `PASSWORD` set directly;
- `CUSTOM_PORT`, which has no effect: there's no plain HTTP;
- `HARDEN_DESKTOP=false`: terminals come back, and `sudo` too without `no-new-privileges`;
- `SELKIES_COMMAND_ENABLED=true`: the web page can run commands on the desktop, as a terminal would;
- `DOCKER_MODS`: linuxserver's add-ons, which run as root at every start;
- `no-new-privileges` off;
- a `/config` that other users on the host can read;
- host networking, and `MT_AI_AGENTS=true` with host networking.
