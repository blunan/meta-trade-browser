# mt-browser

MetaTrader in your browser. The MetaTrader terminal and MetaEditor run on a small Linux desktop inside a container, and you use them from any browser as you would on your own computer: charts, Expert Advisors (EAs, the MQL5 programs that trade from a chart), MetaEditor and the Strategy Tester. One container runs one trading account.

It installs MetaTrader 5, MetaQuotes' current release, and runs it under WineHQ staging (Wine runs Windows programs on Linux) on [linuxserver.io's Selkies desktop](https://github.com/linuxserver/docker-baseimage-selkies), Debian 13. It's secure by default:
- a password is required, and the desktop is served over HTTPS only;
- Docker publishes it on the server's loopback address, `127.0.0.1`, unless you choose another;
- other websites can't open your desktop's stream or embed its page;
- the desktop has no terminal and no `sudo`;
- MetaQuotes' installer and Microsoft's WebView2 installer are downloaded at the first start, and run only if their code signatures check out. The image itself contains no MetaQuotes or Microsoft software.

Not affiliated with MetaQuotes or Microsoft.

## Quick start

**You need:**
- A Linux server with Docker Engine, on amd64 (x86-64). MetaTrader is a 64-bit Windows program, and there's no ARM build. Docker Compose v2 is optional: `docker run` works too.
- About 4 GB of memory, and about 5 GB of disk once MetaTrader has run for a while. The image itself takes about 4 GB.
- A way to reach the server: SSH is enough.

**1. Create the folders** on the server:

```sh
mkdir -p mt-browser && cd mt-browser
mkdir -p -m 700 data secrets
mkdir -p ea
```

`data` will hold your saved broker logins, so only you may open it. `ea` is the optional EA folder. The container works as user and group 1000. If `id -u` or `id -g` prints another number, set `PUID` and `PGID` to them (see *Settings*).

**2. Create the desktop password:**

```sh
openssl rand -base64 24 | tr -d '\n' > secrets/password
cat secrets/password; echo
```

Keep the password in your password manager. A password of your own works too: one line, at least 12 characters. Then make the file root's, so nothing inside the desktop can read it:

```sh
sudo chown root:root secrets/password
sudo chmod 0400 secrets/password
```

From then on, `sudo cat secrets/password` shows the password.

**3. Save this as `compose.yaml`** in the same folder. It's also [in this repository](compose.yaml).

```yaml
# mt-browser: MetaTrader in your browser, one container for one trading account.
# The README's quick start creates the folders and the password file first.
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

**4. Start it** and follow its log:

```sh
docker compose up -d
docker compose logs -f
```

Without Compose, this starts the same container:

```sh
docker run -d --name mt-browser \
  --restart unless-stopped --stop-timeout 30 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
  --cap-add SETUID --cap-add SETGID --cap-add KILL \
  --shm-size 1g --memory 4g \
  -e FILE__PASSWORD=/run/secrets/password \
  -v "$PWD/secrets/password:/run/secrets/password:ro" \
  -v "$PWD/data:/config" \
  -v "$PWD/ea:/mql5" \
  -p 127.0.0.1:3001:3001 \
  ghcr.io/blunan/mt-browser:latest
docker logs -f mt-browser
```

The first start installs Microsoft Edge WebView2 and MetaTrader. It takes about 2–3 minutes, and it's done when the log says `starting MetaTrader`. Ctrl+C stops following the log; the container keeps running.

**On a shared server,** also cap the container's processes and logs. In `compose.yaml`, add `pids_limit: 2048` and `logging: { driver: local, options: { max-size: 10m, max-file: "5" } }`. With `docker run`, add `--pids-limit 2048 --log-driver local --log-opt max-size=10m --log-opt max-file=5`.

**5. Open the desktop.** On your own computer, open an SSH tunnel to the server and leave it open:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Then browse to `https://localhost:3001`. The browser warns about the certificate, because the container made its own; accept it. Sign in as `trader` with the password. While MetaTrader is still installing, the desktop shows a small *Installing MetaTrader* window.

To stop the warning for good, trust that certificate on your computer: copy `data/ssl/cert.pem` from the server, and add it to your trusted certificates (on macOS, open it in Keychain Access and set it to *Always Trust*). It's issued to `localhost` and `127.0.0.1` only, and it can't vouch for any other site. The container renews it about every two years, when it needs trusting again.

**6. Set up MetaTrader.**
1. Log in to your trading account with *Save password* ticked.
2. If *Welcome to LiveUpdate* says updates have been downloaded, click *Restart*.
3. Under **Tools → Options → Experts**:
   - **Allow algorithmic trading:** on.
   - **Disable algorithmic trading when the account has been changed:** on.
   - **Disable algorithmic trading when the profile has been changed:** on.
   - **Disable algorithmic trading when the charts symbol or period has been changed:** on.
   - **Disable algorithmic trading via external Python API:** on. Nothing in this image uses MetaQuotes' Python API.
   - **Allow DLL imports:** off, unless an EA needs it.
   - **Allow WebRequest for listed URL:** off, unless an EA needs it.
4. To keep memory and traffic down: **Charts → Max bars in chart:** 50000, and **Server → Enable news:** off.

## Folders and files

| In the container | On the server | What's in it |
|---|---|---|
| `/config` (required) | `./data` | Everything for the account: Wine, the MetaTrader program, account logins and servers, charts with their EAs and inputs, settings, price history and logs, and the desktop's certificate. MetaTrader updates itself here. |
| `/mql5` (optional) | `./ea` | Your own EAs, indicators and scripts, laid out like MetaTrader's `MQL5` folder: `Experts`, `Indicators`, `Scripts`, `Include`, `Libraries`, `Presets`. |
| `/run/secrets/password` | `./secrets/password` | The desktop password. |

**`/config`:**
- It's a bind mount (a host folder), not a named Docker volume. `docker system prune --volumes` can't delete it while the container is stopped, and it's easy to back up.
- Keep it at mode `0700`: it holds saved broker logins. The container makes user 1000 (`PUID`) its owner at every start, and its log warns if other users on the host have any access to it.
- Back up `data` and the EA folder regularly, encrypted, and try a restore now and then.

**The EA folder (`/mql5`):**
- Each of its sections appears in MetaTrader as a subfolder named `Mounted`, such as `MQL5/Experts/Mounted`.
- `Files` is never linked, because EAs keep their own data there.
- A missing section is created when the folder is writable, and skipped when it's read-only (`./ea:/mql5:ro`).
- On its first start, MetaTrader compiles the sources it finds there.
- *Refresh* in the Navigator shows files added on the host.

## Reaching the desktop

The container serves the desktop over HTTPS on port 3001; there's no plain-HTTP port. The quick start publishes it on the server's `127.0.0.1` only. Pick one of these ways in.

### SSH tunnel

The quick start's way. Nothing else is needed, and nothing new is exposed:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

### A VPN

- **Publish on the VPN's address:** in `compose.yaml`'s `ports`, or `docker run`'s `-p`, replace `127.0.0.1` with the server's VPN address, such as its Tailscale IP, and recreate the container. Only devices on the VPN can then connect, at `https://<that address>:3001`. The address has to exist when the container starts: if the VPN starts after Docker at boot, run `docker compose up -d` once it's up.
- **Tailscale Serve:** keep `127.0.0.1`, and let Tailscale serve the desktop on your tailnet with its own certificate:

  ```sh
  sudo tailscale serve --bg --https=3001 https+insecure://127.0.0.1:3001
  ```

  Then browse to `https://<machine>.<tailnet>.ts.net:3001`. `https+insecure` means Tailscale doesn't check the container's certificate; that hop never leaves the server.

### Behind a reverse proxy

A reverse proxy gives you your own domain with a trusted certificate, and a place for a real login in front, such as Cloudflare Access, Authelia or Authentik. The desktop's own password still applies behind it.

Whatever the proxy:
1. **It connects over HTTPS, without checking the container's certificate.** The container's certificate is its own and self-signed, so the examples turn the check off. The hop from the proxy to the container stays on the server.
2. **It passes the browser's `Host` header on.** The desktop streams over a WebSocket, which the container accepts only from the page's own origin, and it learns that origin from `Host`. A proxy that replaces `Host` gets the stream refused (403). If yours can't keep it, list your public origin in `SELKIES_ALLOWED_ORIGINS`, such as `https://mt.example.com`.
3. **Optionally, only the proxy gets in.** Put the proxy and the container on a Docker network of their own, and list the proxy's address on it in `TRUSTED_PROXIES`. Everyone else gets 403, and the log shows the browser's address (`X-Forwarded-For`) for requests that come through the proxy. The SSH tunnel then gets 403 too: through a published port, the container sees Docker's gateway address. If the proxy is your only way in, remove `ports`.

The examples reach the container as `mt-browser:3001`, its name on a Docker network it shares with the proxy. A proxy installed on the server itself, outside Docker, uses `127.0.0.1:3001` instead, and leaves `TRUSTED_PROXIES` unset: the container sees Docker's gateway address rather than the proxy's. Add your login (Authelia, Authentik, and so on) the way your proxy's documentation shows.

**Caddy** (`Caddyfile`). When the upstream is HTTPS, Caddy sends the upstream's own address as `Host` unless told otherwise:

```
mt.example.com {
	reverse_proxy https://mt-browser:3001 {
		header_up Host {host}
		transport http {
			tls_insecure_skip_verify
		}
	}
}
```

**nginx**, in the `server` block for your domain. nginx sends its upstream's address as `Host` by default:

```nginx
location / {
    proxy_pass              https://mt-browser:3001;
    proxy_ssl_verify        off;
    proxy_http_version      1.1;
    proxy_set_header        Host $http_host;
    proxy_set_header        Upgrade $http_upgrade;
    proxy_set_header        Connection $connection_upgrade;
    proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header        X-Forwarded-Proto $scheme;
    proxy_read_timeout      3600s;
    proxy_send_timeout      3600s;
    proxy_buffering         off;
    proxy_request_buffering off;
    client_max_body_size    0;
}
```

with this in the `http` block:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

**Traefik**, a dynamic configuration file (file provider). Traefik passes `Host` on by default:

```yaml
http:
  routers:
    mt:
      rule: Host(`mt.example.com`)
      entryPoints: [websecure]
      tls: {}
      service: mt
  services:
    mt:
      loadBalancer:
        servers:
          - url: https://mt-browser:3001
        serversTransport: mt
  serversTransports:
    mt:
      insecureSkipVerify: true
```

With Docker labels instead, the servers transport still has to be in a file. The labels then include `traefik.http.services.mt.loadbalancer.server.scheme=https`, `traefik.http.services.mt.loadbalancer.server.port=3001` and `traefik.http.services.mt.loadbalancer.serverstransport=mt@file`, and `traefik.docker.network` names the network Traefik and the container share.

**cloudflared**, a locally managed tunnel's `config.yml`. Protect the hostname with a Cloudflare Access application:

```yaml
tunnel: <tunnel ID>
credentials-file: /etc/cloudflared/<tunnel ID>.json
ingress:
  - hostname: mt.example.com
    service: https://mt-browser:3001
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

### Host networking

Host networking works too. The container then shares the server's network:
- Only the HTTPS port listens on the server, on `127.0.0.1:3001` unless you set `LISTEN_ADDRESS`. Everything else inside stays on socket files or is off.
- If port 3001 is taken on the server, set `CUSTOM_HTTPS_PORT`.
- **But MetaTrader, and every EA, can reach whatever listens on the server's own loopback,** such as other containers' published ports. The default bridge network doesn't allow that, so prefer it.

In `compose.yaml`, replace `ports` with `network_mode: host`. With `docker run`, use `--network host` instead of `-p`.

## Settings

Set these under `environment` in `compose.yaml`, or with `-e` in `docker run`. Changes take effect when the container is recreated: `docker compose up -d`, or remove the container and run it again.

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
| `MT_AI_AGENTS` | off | `true` turns on MetaTrader's and MetaEditor's servers for AI agents (below). |

**For a reverse proxy, a VPN or host networking** (see *Reaching the desktop*):

| Setting | Default | What it does |
|---|---|---|
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | none | A certificate and key of your own to serve, as paths inside the container. Without them the container serves `/config/ssl/cert.pem` and `cert.key`. If they don't exist, it makes its own there: self-signed, issued to `localhost`, `127.0.0.1` and `::1`, unable to sign other certificates, and valid for 825 days. A start in its last 30 days renews it. You can put your own certificate in those two files instead; the container never touches it. A new certificate takes effect at the next container restart. |
| `TRUSTED_PROXIES` | none | IP addresses or ranges, such as `172.20.0.5` or `10.8.0.0/24`. When set, only they get in, and everyone else gets 403. Requests from them have their `X-Forwarded-For` logged. |
| `SELKIES_ALLOWED_ORIGINS` | none: the page's own origin only | Other origins allowed to open the stream, comma-separated, such as `https://mt.example.com`. `*` is refused. |
| `SUBFOLDER` | `/` | Serves the desktop under a path, such as `/mt/`. |
| `CUSTOM_HTTPS_PORT` | `3001` | The HTTPS port inside the container. |
| `LISTEN_ADDRESS` | all of the container's addresses; `127.0.0.1` with host networking | The one address the HTTPS port listens on. |

**Wine's own,** for troubleshooting:

| Setting | Default | What it does |
|---|---|---|
| `WINEDEBUG` | `fixme-all,err-toolbar` | What Wine writes to the log: its errors, minus the noise from MetaTrader's toolbar. During the first start's install, Wine writes nothing, unless you set `WINEDEBUG` yourself. For troubleshooting, `fixme-all` brings the toolbar's errors back, and an empty value restores Wine's defaults, which add its "fixme" notes. |
| `WINEDLLOVERRIDES` | `mscoree,mshtml=` | Turns off Wine's Mono (.NET) and Gecko (Internet Explorer's engine), so Wine never stops to offer them; MetaTrader uses neither. A value of your own replaces this one, so keep those two in it. |

**Other settings.** The base image's and Selkies' other settings, such as `SELKIES_ENCODER` or `LC_ALL`, reach them unchanged: nothing filters the container's environment. They aren't tested with this image. A value you set replaces the image's own, its protections included: `SELKIES_MICROPHONE_ENABLED=true` brings the microphone back, for instance. The refusals below still apply. Three have no effect, because the container replaces the base's web server setup with its own: `CUSTOM_PORT`, `CUSTOM_WS_PORT` and `DISABLE_IPV6`.

**Refused:** the container stops at once, and its log says why in a `[mt-access] REFUSED:` line. With `restart: unless-stopped`, `docker ps` then shows it *Restarting*. These settings remove a protection and have no use here:
- no password, a file that can't be read, fewer than 12 characters, or a well-known placeholder;
- `SELKIES_ALLOWED_ORIGINS` with `*`: any website could open your stream;
- a `TRUSTED_PROXIES` that covers every address (`0.0.0.0/0`, `::/0`), or holds something that isn't an address or range;
- only one of `TLS_CERT_FILE` and `TLS_KEY_FILE`, a path with unusual characters, or a file that can't be read;
- privileged mode (`privileged: true`, or `cap_add: SYS_ADMIN`), or the Docker socket mounted: the desktop would control the server;
- `DEV_MODE`, `PIXELFLUX_WAYLAND=true`, `SELKIES_MODE=webrtc`, `SELKIES_ENABLE_DUAL_MODE=true`, `SELKIES_COMPUTER_USE_BIND`, or another `SELKIES_UNIX_SOCKET`. These are the base image's development mode, its Wayland desktop, WebRTC streaming, and extra servers outside the login;
- a malformed `CUSTOM_HTTPS_PORT`, `CUSTOM_USER`, `SUBFOLDER` or `LISTEN_ADDRESS`;
- a `SELKIES_FILE_TRANSFERS` or `SELKIES_CLIPBOARD_ENABLED` value other than those in the table: Selkies would read one such as `off` as on, both ways.

**Warned about** in the log, because you might have a reason:
- `PASSWORD` set directly;
- `CUSTOM_PORT`, which has no effect: there's no plain HTTP;
- `HARDEN_DESKTOP=false`: terminals come back, and `sudo` too without `no-new-privileges`;
- `SELKIES_COMMAND_ENABLED=true`: the web page can run commands on the desktop, as a terminal would;
- `DOCKER_MODS`: linuxserver's add-ons, which run as root at every start;
- `no-new-privileges` off;
- a `/config` that other users on the host can read;
- host networking, and `MT_AI_AGENTS=true` with host networking.

## Using MetaTrader in the browser

- **The clipboard** works both ways. The browser asks for permission once.
- **Sound:** MetaTrader's sounds, such as a finished backtest or an alert, play in the browser. The speaker button in the side panel turns them off. A browser may wait for your first click on the page before it plays any.
- **The side panel** opens with Ctrl+Shift+M. With file transfers on, it has the file panel. It has no video or audio settings, and no microphone or webcam buttons.
- **Keyboard shortcuts:**
  - On Windows and Linux, the browser keeps Ctrl+N, Ctrl+T and Ctrl+W for itself. On macOS it passes them on to MetaTrader, since its own shortcuts use Cmd.
  - F11 belongs to the browser.
- **MetaEditor** opens with F4 or MetaTrader's *IDE* button. The desktop's menu (right-click the desktop) has MetaTrader and MetaEditor, but MetaTrader usually covers the desktop.
- **The MQL Wizard's first page** ignores the mouse under Wine. Use the keyboard: the arrow keys, Tab and Enter.
- **The HTML panes:** Help (F1), Market, Signals, Mailbox messages and MetaEditor's Welcome page are web pages, shown through Microsoft Edge WebView2.
  - They need memory. With one open, the container can reach 4 GB, and Market alone reaches the quick start's 4 GB limit.
  - At the limit, the kernel stops one of Edge's processes first, not MetaTrader. The pane goes blank, and comes back when you close and reopen it. The log says when it happened.
  - If you use the panes a lot, set `mem_limit: 6g` (`--memory 6g`).
  - The MQL5 reference is also online, at <https://www.mql5.com/en/docs>.
- **After any manual login,** check the Algo Trading button. Switching accounts turns it off, if you ticked that protection in step 6.
- **Save your work in MetaEditor before stopping the container.** MetaTrader is asked to close and save when the container stops, but MetaEditor isn't: a "Save changes?" question would hold up the stop.

**Memory, for sizing:** about 0.5 GB with MetaTrader running EAs and nobody connected, 1.5 GB with a browser connected, 2.4 GB during a heavy backtest, and up to 4 GB with an HTML pane open.

## Stopping, restarts and health

- **Stopping:** `docker compose stop`, or `docker stop mt-browser`. MetaTrader gets a close request, as *File → Exit* sends, and saves its charts and settings; this usually takes about a second. The quick start's 30 s (`stop_grace_period`, `--stop-timeout`) gives it the time.
- **At every stop with a saved login, the log says the account file was put back:** "put back Config/accounts.dat from before the close". Under Wine, the copy of `accounts.dat` that MetaTrader writes while closing doesn't survive a container restart. At the next start MetaTrader would log "Accounts deleted due security reason" and not log in. So the copy from before the close is kept.
- **If MetaTrader closes or crashes,** the desktop starts it again within seconds.
- **The health check:** `docker ps` shows *healthy* when MetaTrader is running and the desktop answers.
  - It doesn't show whether MetaTrader is connected to the broker, or whether an EA is running. MetaTrader's status bar and its Journal show that.
  - `docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' mt-browser` shows why a check failed.
  - The first start has 5 minutes before failed checks count.
- **To stop trading in a hurry,** from mildest to strongest:
  1. Click **Algo Trading** in the terminal. No EA can trade, and positions stay open.
  2. `docker stop mt-browser`. The terminal stops. Open positions keep their stop-loss and take-profit on the broker's server.
  3. Close positions by hand, on the desktop or in your broker's app, then stop.

## Updates

**The image.**
- **Tags:**
  - `latest` follows every new build;
  - a date tag, such as `20261019`, stays on one build;
  - `sha-<commit>` names the source commit.
- **Updating:** `docker compose pull && docker compose up -d`. With `docker run`: `docker pull ghcr.io/blunan/mt-browser:latest`, then `docker stop mt-browser && docker rm mt-browser`, and the same `docker run` again.
- **Going back:** use the previous date tag in place of `latest`, the same way.

**Inside the container, two things update themselves,** whatever the image:
- **MetaTrader, through LiveUpdate.**
  - When *Welcome to LiveUpdate* says updates have been downloaded, click *Restart* at a quiet moment. *Later* installs them at the next start.
  - MetaQuotes says LiveUpdate can't be turned off. It also brings MetaQuotes' machine-learning and AI components.
  - A new MetaTrader build could misbehave under Wine. Keep backups of `/config` to go back to.
- **WebView2, through Edge Update,** which keeps running in the background.

## What the container connects to

For networks that filter outgoing traffic:

| When | Host | What for |
|---|---|---|
| First start | `msedge.sf.dl.delivery.mp.microsoft.com` | The WebView2 installer |
| First start | `www.microsoft.com` | Revocation lists, for the WebView2 installer's signature check |
| First start, then in the background | `config.edge.skype.com`, `msedge.api.cdp.microsoft.com`, `msedge.f.tlu.dl.delivery.mp.microsoft.com` | Edge Update, which installs WebView2 and keeps it current |
| First start | `download.mql5.com` | The MetaTrader installer, and the files it installs |
| First start | `crl3.digicert.com` | A revocation list, for the MetaTrader installer's signature check |
| First start | `content.finteza.com` | MetaQuotes' analytics service, contacted by the MetaTrader installer |
| From the first start on | `download.terminal.free` | LiveUpdate, MetaTrader's own updates |
| Once you log in | your broker's servers | Trading, and LiveUpdate through them |
| When you use them | MetaQuotes' MQL5 services | Market, Signals, Code Base and the like |

That's what a first start looked up, with MetaTrader idle afterwards. Your broker, and the features you use, add their own hosts.

**MetaTrader's AI-agent servers.** MetaTrader and MetaEditor can run servers for AI agents (MCP) on the container's own loopback: MetaTrader on port 22346, and MetaEditor on 22345. They're protected only by an API key that MetaTrader keeps in `Config/assistant.ini`. In this image they're off at every start unless `MT_AI_AGENTS=true`; changing it takes a restart. With host networking, they would listen on the server's own loopback.

## What isn't supported

- **ARM.** MetaTrader is a 64-bit Windows program, so the image is amd64 only.
- **VNC.** The desktop streams to browsers only. VNC would mean a second login and a second open port.
- **Microphone and webcam.** They're off, and untested with MetaTrader.
- **Python.** There's no Python bridge or API for MetaTrader. Selkies, the desktop's streaming server, is itself a Python program; it listens only on a socket file inside the container.
- **`init: true`, or `docker run --init`.** The image's own supervisor (s6) has to be process 1: with Docker's init, the container stops at once.
- **EAs that need .NET.** Wine's Mono isn't included.
- **Wayland and WebRTC.** The desktop runs X11 and streams over WebSockets; the startup check refuses the alternatives.

## Troubleshooting

- **`docker logs mt-browser`** (or `docker compose logs`) has everything:
  - the certificate, as an `[mt-cert]` line when it's made or renewed;
  - the startup check, as `[mt-access]` lines;
  - the install and every MetaTrader start, as `[mt]` lines;
  - the stop, as `[mt-stop]`;
  - nginx's log of logins and requests;
  - Wine's errors.
- **MetaTrader's start log** stays in `/config/log/mt/run-terminal.log` (`data/log/mt/` on the host) across restarts.
- **A failed install step** shows a small window on the desktop, and the log says why. It's tried again every 60 s: a lost download, or a signature check that failed because a revocation list couldn't be fetched, usually passes on a later try. A file whose signature is wrong is never run.
- **Behind a proxy, the page loads but the desktop never appears:** the proxy probably replaces `Host`, and the container refuses the stream (see *Behind a reverse proxy*).
- **More from Wine:** `WINEDEBUG=fixme-all`, or empty (see *Settings*).
- **Harmless messages at every start,** from the desktop the image is built on:
  - `17` and `18`: the sound server numbering the two audio devices it creates;
  - `_XSERVTransmkdir: Cannot create /tmp/.X11-unix with root ownership` and `screen 0 shmid 0`: the display starting as the desktop's user;
  - `xsettingsd: Unable to open connection to X server`, now and then: it started a moment before the display, and is started again;
  - `No hardware encoder … (nvenc)` and `Failed to init NVENC`: the stream looks for a GPU encoder, and without one encodes on the CPU;
  - `Apps panel enabled`: the panel stays hidden, and its actions are off.

## Advanced: pin a digest and check its signature

A tag can move to another build; a digest (`sha256:…`) names exactly one. Every image this repository's CI builds is signed with cosign, keyless, by its GitHub Actions workflow. To check one before you run it:

```sh
docker buildx imagetools inspect ghcr.io/blunan/mt-browser:20261019
cosign verify ghcr.io/blunan/mt-browser@sha256:<digest> \
  --certificate-identity https://github.com/blunan/mt-browser/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The first command prints the digest. Then pin it in `compose.yaml` (or `docker run`): `ghcr.io/blunan/mt-browser:20261019@sha256:<digest>`. Docker uses the digest, and the tag stays only as a reminder.

## Building it yourself

```sh
git clone https://github.com/blunan/mt-browser.git
cd mt-browser
docker build -t mt-browser:dev .
tests/access.sh
```

- `docker build --build-arg STRIP_WINE_DEBUG=false` keeps Wine's debug information, for crash backtraces with function names; the image grows by about 1 GB.
- `tests/access.sh` checks the access layer: logins, refusals, origins, headers, certificates, listening ports. It needs no internet and leaves nothing behind. `--host` adds the host-networking test, which binds `127.0.0.1:3911` on the machine.
- `tests/compose.dev.yaml` runs a local build with the example's settings, with its own container name, port (3201), folders and password, next to a real deployment:

  ```sh
  docker compose -f compose.yaml -f tests/compose.dev.yaml build
  docker compose -f compose.yaml -f tests/compose.dev.yaml up -d
  ```

## License

Copyright (C) 2026 Brayan Luna

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.

The image is built on [linuxserver.io's](https://www.linuxserver.io/) Selkies base image, also GPL-3.0. At the first start it downloads MetaQuotes' MetaTrader 5 and Microsoft's Edge WebView2 Runtime from their publishers. They come under their own license terms, not this project's. This project isn't affiliated with or endorsed by MetaQuotes or Microsoft.
