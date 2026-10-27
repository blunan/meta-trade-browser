# Folders and settings

What needs files, such as your EAs or a certificate of your own, needs no environment setting: you mount the files in the right place. Environment settings go under `environment` in `compose.yaml`, or with `-e` in `docker run`. Changes take effect when the container is recreated: `docker compose up -d`, or remove the container and run it again.

## Folders and files

| In the container | On the server | What's in it |
|---|---|---|
| `/config` (required) | `./data` | Everything for the account: Wine, the MetaTrader program, account logins and servers, charts with their EAs and inputs, settings, price history and logs, and the desktop's certificate. MetaTrader updates itself here. |
| `/mql5` (optional) | `./ea` | Your own EAs, indicators and scripts, laid out like MetaTrader's `MQL5` folder: `Experts`, `Indicators`, `Scripts`, `Include`, `Libraries`, `Presets`. |
| `/run/secrets/password` | `./secrets/password` | The desktop password. |
| `/config/ssl/cert.pem`, `/config/ssl/cert.key` (optional) | your certificate's files, such as `./tls/cert.pem` | A certificate of your own, and its key (see [Your own certificate](access.md#your-own-certificate)). |

### `/config`

- It's a bind mount (a host folder), not a named Docker volume. `docker system prune --volumes` can't delete it while the container is stopped, and it's easy to back up.
- Keep it at mode `0700`: it holds saved broker logins. The container makes user 1000 (`PUID`) its owner at every start, and its log warns if other users on the host have any access to it.
- Back up `data` and the EA folder regularly, encrypted, and try a restore now and then.

### The EA folder (`/mql5`)

- Each of its sections appears in MetaTrader as a subfolder named `Mounted`, such as `MQL5/Experts/Mounted`.
- `Files` is never linked, because EAs keep their own data there.
- A missing section is created when the folder is writable, and skipped when it's read-only (`./ea:/mql5:ro`).
- On its first start, MetaTrader compiles the sources it finds there.
- *Refresh* in the Navigator shows files added on the host.
- With [file transfers](#the-main-settings) on, uploads land in its `Experts`, and appear in the Navigator under *Expert Advisors → Mounted* after *Refresh*. When it's read-only, or not mounted, they land in MetaTrader's own `MQL5/Experts`, in `data`.

## The main settings

| Setting | Default | What it does |
|---|---|---|
| `FILE__PASSWORD` | none | **Required:** the path of the desktop password's file. At least 12 characters, and not a well-known placeholder such as `password` or `changeme`. A line break at the end is ignored. `PASSWORD`, the password itself, works too, but `docker inspect` shows it. |
| `PUID`, `PGID` | `1000` | The user and group that own `/config` and the desktop's programs. Set them to your `id -u` and `id -g` when those aren't 1000. |
| `CUSTOM_USER` | `trader` | The desktop's login name. |
| `TITLE` | `MetaTrader` | The browser tab's name. |
| `TZ` | UTC | The desktop's time zone. MetaTrader shows its server's time anyway. |
| `SELKIES_CLIPBOARD_ENABLED` | `true` | The shared clipboard: `true`, `in` (browser to desktop only), `out` (desktop to browser only) or `false`. |
| `SELKIES_FILE_TRANSFERS` | `false` | `true` turns on file transfers through the browser, and the side panel's file panel with them. `upload` or `download` allows one direction only. Uploads land in the [EA folder](#the-ea-folder-mql5)'s `Experts` when it's mounted and writable, and appear in the Navigator under *Expert Advisors → Mounted* after *Refresh*. Otherwise they land in MetaTrader's own `MQL5/Experts`, in `/config`, and appear under *Expert Advisors*. The file panel offers downloads from the same folder, and can't choose another. |
| `MT_PYTHON` | off | `true` installs Windows Python and MetaQuotes' `MetaTrader5` package into `/config` at the next start, once the Python Software Foundation's signature passes. MetaTrader and MetaEditor find it by themselves (see [Python](using.md#python)). |
| `MT_AI_AGENTS` | off | `true` turns on MetaTrader's and MetaEditor's servers for AI agents (see [MetaTrader's AI-agent servers](verify.md#metatraders-ai-agent-servers)). |

## Reverse proxy, VPN and host networking

See [Access and reverse proxy](access.md). A certificate of your own needs no setting: see [Your own certificate](access.md#your-own-certificate).

| Setting | Default | What it does |
|---|---|---|
| `TRUSTED_PROXIES` | none | IP addresses or ranges, such as `172.20.0.5` or `10.8.0.0/24`. When set, only they get in, and everyone else gets 403. Requests from them have their `X-Forwarded-For` logged. |
| `SELKIES_ALLOWED_ORIGINS` | none: the page's own origin only | Other origins allowed to open the stream, comma-separated, such as `https://mt.example.com`. `*` is refused. |
| `SUBFOLDER` | `/` | Serves the desktop under a path, such as `/mt/`. |
| `CUSTOM_HTTPS_PORT` | `3001` | The HTTPS port inside the container. For host networking. |
| `LISTEN_ADDRESS` | all of the container's addresses; `127.0.0.1` with host networking | The one address the HTTPS port listens on. For host networking. |

## Settings that go together

- `PUID` and `PGID`: set both, to your `id -u` and `id -g`.
- `TRUSTED_PROXIES` needs the proxy and the container on a Docker network of their own. The SSH tunnel then gets 403, so if the proxy is your only way in, remove `ports` (see [What every proxy needs](access.md#what-every-proxy-needs)).
- `SELKIES_ALLOWED_ORIGINS` is needed only when your proxy replaces the `Host` header.
- `SUBFOLDER` needs a proxy that forwards the path as it is, without removing it.
- `LISTEN_ADDRESS` and `CUSTOM_HTTPS_PORT` are for host networking. On Docker's default network, change the server's port in `ports` instead: `127.0.0.1:3101:3001` serves the desktop on the server's port 3101.

## Wine's own

For troubleshooting:

| Setting | Default | What it does |
|---|---|---|
| `WINEDEBUG` | `fixme-all,err-toolbar` | What Wine writes to the log: its errors, minus the noise from MetaTrader's toolbar. During the first start's install, Wine writes nothing, unless you set `WINEDEBUG` yourself. For troubleshooting, `fixme-all` brings the toolbar's errors back, and an empty value restores Wine's defaults, which add its "fixme" notes. |
| `WINEDLLOVERRIDES` | `mscoree,mshtml=` | Turns off Wine's Mono (.NET) and Gecko (Internet Explorer's engine), so Wine never stops to offer them; MetaTrader uses neither. A value of your own replaces this one, so keep those two in it. |

## Other settings

The base image's and Selkies' other settings, such as `SELKIES_ENCODER` or `LC_ALL`, reach them unchanged: nothing filters the container's environment. They aren't tested with this image. A value you set replaces the image's own, its protections included: `SELKIES_MICROPHONE_ENABLED=true` brings the microphone back, for instance. The refusals below still apply.

Three have no effect, because the container replaces the base's web server setup with its own: `CUSTOM_PORT`, `CUSTOM_WS_PORT` and `DISABLE_IPV6`.

## Deprecated

Still read, with a warning in the log. Images from 2026-12-22 on ignore them.

| Setting | Instead |
|---|---|
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | Mount your certificate and key at `/config/ssl/cert.pem` and `cert.key` (see [Your own certificate](access.md#your-own-certificate)). |
| `FILE_MANAGER_PATH` | Nothing: uploads land in the EA folder's `Experts` when it's mounted and writable, otherwise in MetaTrader's own (see `SELKIES_FILE_TRANSFERS` above). |

## Refused

The container stops at once, and its log says why in a `[mt-access] REFUSED:` line. With `restart: unless-stopped`, `docker ps` then shows it *Restarting*. These settings remove a protection and have no use here:

- no password, a file that can't be read, fewer than 12 characters, or a well-known placeholder;
- `SELKIES_ALLOWED_ORIGINS` with `*`: any website could open your stream;
- a `TRUSTED_PROXIES` that covers every address (`0.0.0.0/0`, `::/0`), or holds something that isn't an address or range;
- a certificate and key in `/config/ssl` that can't be read or don't belong together, or only one of the two;
- while they're still read, only one of `TLS_CERT_FILE` and `TLS_KEY_FILE`, a path with unusual characters, or a file that can't be read;
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
- host networking, and `MT_AI_AGENTS=true` with host networking;
- the [deprecated](#deprecated) settings, and an upload folder the desktop's user can't create.
