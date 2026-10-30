# Folders and settings

File-based configuration (custom EAs, scripts, TLS certificates) is managed via volume mounts. Environment variables are configured under `environment` in `compose.yaml` (or `-e` with `docker run`). Changes apply on container recreation (`docker compose up -d`).

## Folders and files

| Container path | Host path | Description |
|---|---|---|
| `/config` (required) | `./data` | Persistent account state: Wine prefix, MetaTrader installation, broker credentials, charts, price history, logs, SSL certificate, and optional Windows Python environment. |
| `/mql5` (optional) | `./ea` | Custom EAs, indicators, and scripts. Mirrors MetaTrader's `MQL5` folder structure (`Experts`, `Indicators`, `Scripts`, `Include`, `Libraries`, `Presets`). |
| `/run/secrets/password` | `./secrets/password` | Desktop access password file. |
| `/config/ssl/cert.{pem,key}` (optional) | Custom path e.g. `./tls/cert.{pem,key}` | Custom TLS certificate and unencrypted private key (see [Your own certificate](access.md#your-own-certificate)). |

### `/config`

- Host bind mount (not an anonymous Docker volume) protecting against `docker system prune --volumes` and simplifying backups.
- Keep mode `0700` (contains saved account credentials). Permissions are updated to `PUID` (`1000`) on container start.
- Maintain regular, encrypted backups of `data` and `ea`.

### The EA folder (`/mql5`)

- Subdirectories appear inside MetaTrader under `MQL5/<section>/Mounted` (e.g. `MQL5/Experts/Mounted`).
- `Files` is not symlinked (EAs store local data directly).
- Missing sections are created automatically if the mount is writable.
- New files appear in MetaTrader's Navigator after clicking *Refresh*.
- When [file transfers](#the-main-settings) are enabled, browser uploads land in `Experts` (or MetaTrader's native `Experts` directory if unmounted).

## The main settings

| Setting | Default | Description |
|---|---|---|
| `FILE__PASSWORD` | none | **Required:** Path to password file (minimum 12 characters, excluding common placeholders like `password` or `changeme`). Trailing newlines are stripped. `PASSWORD` is also accepted, but exposes credentials in `docker inspect`. |
| `PUID`, `PGID` | `1000` | UID and GID owning `/config` and desktop processes. Set to host `id -u` and `id -g` when different from 1000. |
| `CUSTOM_USER` | `trader` | Desktop login username. |
| `TITLE` | `MetaTrader` | Browser tab title. |
| `TZ` | `UTC` | Desktop time zone. MetaTrader displays broker server time regardless. |
| `SELKIES_CLIPBOARD_ENABLED` | `true` | Shared clipboard: `true`, `in` (client to desktop), `out` (desktop to client), or `false`. |
| `SELKIES_FILE_TRANSFERS` | `false` | Enables browser file transfers (`true`, `upload`, or `download`). Uses `/mql5/Experts` if mounted and writable, otherwise MetaTrader's `/config/.../MQL5/Experts`. |
| `MT_PYTHON` | off | `true` installs Windows Python 3.14 and verified `MetaTrader5` / `numpy` wheels into `/config` at startup (see [Python](using.md#python)). |
| `MT_AI_AGENTS` | off | `true` enables loopback MCP agent servers in MetaTrader and MetaEditor (see [MetaTrader's AI-agent servers](verify.md#metatraders-ai-agent-servers)). |

## Reverse proxy, VPN and host networking

See [Access and reverse proxy](access.md) for network integration patterns.

| Setting | Default | Description |
|---|---|---|
| `TRUSTED_PROXIES` | none | Allowed proxy IPs or CIDR blocks (e.g. `172.20.0.5`, `10.8.0.0/24`). All other traffic receives 403. Enables `X-Forwarded-For` logging. |
| `SELKIES_ALLOWED_ORIGINS` | none | Comma-separated list of additional allowed WebSocket origins (e.g. `https://mt.example.com`). Wildcards (`*`) are refused. |
| `SUBFOLDER` | `/` | Base URL path for reverse proxy sub-path routing (e.g. `/mt/`). |
| `CUSTOM_HTTPS_PORT` | `3001` | Internal HTTPS port; primarily used with host networking. |
| `LISTEN_ADDRESS` | `0.0.0.0` (`127.0.0.1` for host networking) | Specific interface address for nginx to bind. |

## Settings that go together

- `PUID` and `PGID`: configure together to match host user permissions.
- `TRUSTED_PROXIES`: requires placing proxy and container on a shared Docker network. Direct access via published `ports` will receive 403.
- `SELKIES_ALLOWED_ORIGINS`: required only if your reverse proxy overrides the incoming `Host` header.
- `SUBFOLDER`: requires a proxy configuration that forwards the subpath intact.
- `LISTEN_ADDRESS` and `CUSTOM_HTTPS_PORT`: used with host networking. On bridge networks, remap host ports in `ports` instead (e.g. `127.0.0.1:3101:3001`).

## Wine's own

Troubleshooting environment variables:

| Setting | Default | Description |
|---|---|---|
| `WINEDEBUG` | `fixme-all,err-toolbar` | Wine log filter. Suppresses noisy toolbar errors by default. Set to empty for full Wine debug output. |
| `WINEDLLOVERRIDES` | `mscoree,mshtml=` | Disables Mono (.NET) and Gecko prompts, which MetaTrader does not use. |

## Other settings

Unfiltered environment variables (e.g. `SELKIES_ENCODER`, `LC_ALL`) pass through directly to Selkies and the base image. Overriding security variables (e.g. `SELKIES_MICROPHONE_ENABLED=true`) will re-enable disabled features.

The following base settings have no effect due to customized web server routing: `CUSTOM_PORT`, `CUSTOM_WS_PORT`, `DISABLE_IPV6`.

## Deprecated

Retained for backwards compatibility (ignored in images built on/after 2026-12-22):

| Setting | Migration |
|---|---|
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | Mount files to `/config/ssl/cert.pem` and `cert.key` (see [Your own certificate](access.md#your-own-certificate)). |
| `FILE_MANAGER_PATH` | Managed automatically via `SELKIES_FILE_TRANSFERS` and `/mql5/Experts`. |

## Refused

The container halts immediately with `[mt-access] REFUSED:` when configured with unsafe settings:

- Missing, unreadable, or placeholder password (`password`, `changeme`), or fewer than 12 characters.
- `SELKIES_ALLOWED_ORIGINS` set to `*` (permits arbitrary sites to stream desktop).
- `TRUSTED_PROXIES` set to `0.0.0.0/0`, `::/0`, or invalid network syntax.
- Mismatched, unreadable, or incomplete certificates in `/config/ssl`.
- Container runs in privileged mode (`privileged: true` or `cap_add: SYS_ADMIN`), or Docker socket is mounted.
- Base image development or unsupported streaming modes (`DEV_MODE`, `PIXELFLUX_WAYLAND=true`, `SELKIES_MODE=webrtc`, `SELKIES_ENABLE_DUAL_MODE=true`, `SELKIES_COMPUTER_USE_BIND`).
- Invalid values for `CUSTOM_HTTPS_PORT`, `CUSTOM_USER`, `SUBFOLDER`, `LISTEN_ADDRESS`, `SELKIES_FILE_TRANSFERS`, or `SELKIES_CLIPBOARD_ENABLED`.

## Warned about

Logged as `[mt-access] WARNING:` during startup:

- `PASSWORD` passed directly in environment (visible via `docker inspect`).
- `CUSTOM_PORT` configured (plain HTTP is disabled).
- `HARDEN_DESKTOP=false` (restores terminal and sudo).
- `SELKIES_COMMAND_ENABLED=true` (allows web clients to run desktop commands).
- `DOCKER_MODS` enabled (runs unverified root modifications at boot).
- `no-new-privileges` disabled.
- `/config` world-readable on host.
- Host networking enabled, or `MT_AI_AGENTS=true` combined with host networking.
- Deprecated environment variables.
