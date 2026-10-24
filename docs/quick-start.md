# Quick start

You need a Linux server with Docker Engine on amd64 (x86-64), about 4 GB of memory and 10 GB of disk, and SSH access (see [What you need](index.md#what-you-need)).

## 1. Create the folders

On the server:

```sh
mkdir -p meta-trade-browser && cd meta-trade-browser
mkdir -p -m 700 data secrets
mkdir -p ea
```

`data` will hold your saved broker logins, so only you may open it. `ea` is the optional EA folder.

The container works as user and group `1000`. Check yours with `id -u` and `id -g`: if either prints another number, add `PUID` and `PGID` under `environment` in `compose.yaml` (or `-e PUID=$(id -u) -e PGID=$(id -g)` in `docker run`; see [Folders and settings](settings.md#the-main-settings)).

## 2. Create the desktop password

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

## 3. Save `compose.yaml`

Save this as `compose.yaml` in the same folder. It's also [in the repository](https://github.com/blunan/meta-trade-browser/blob/main/compose.yaml). Without Compose, skip this step: the next one has the same container as a `docker run` command.

```yaml
--8<-- "compose.yaml"
```

!!! warning "Never add `init: true`"
    The image's own supervisor has to be process 1. With Docker's init (`init: true`, or `docker run --init`), the container stops at once.

## 4. Start it

Start it and follow its log:

=== "Compose"

    ```sh
    docker compose up -d
    docker compose logs -f
    ```

=== "docker run"

    ```sh
    docker run -d --name meta-trade-browser \
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
      ghcr.io/blunan/meta-trade-browser:latest
    docker logs -f meta-trade-browser
    ```

The first start installs Microsoft Edge WebView2 and MetaTrader. It takes about 2–3 minutes, and it's done when the log says `starting MetaTrader`. Ctrl+C stops following the log; the container keeps running.

!!! tip "On a shared server"
    Also cap the container's processes and logs.

    === "Compose"

        Add to the service in `compose.yaml`:

        ```yaml
        pids_limit: 2048
        logging: { driver: local, options: { max-size: 10m, max-file: "5" } }
        ```

    === "docker run"

        Add `--pids-limit 2048 --log-driver local --log-opt max-size=10m --log-opt max-file=5`.

## 5. Open the desktop

On your own computer, open an SSH tunnel to the server and leave it open:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Then browse to `https://localhost:3001`. The browser warns about the certificate, because the container made its own; accept it. Sign in as `trader` with the password. While MetaTrader is still installing, the desktop shows an *Installing MetaTrader* window with the step it's on.

To stop the warning for good, trust that certificate on your computer: copy `data/ssl/cert.pem` from the server, and add it to your trusted certificates (on macOS, open it in Keychain Access and set it to *Always Trust*). It's issued to `localhost` and `127.0.0.1` only, and it can't vouch for any other site. The container renews it about every two years, when it needs trusting again.

Other ways in, such as a VPN, Tailscale or your own domain behind a reverse proxy, are in [Access and reverse proxy](access.md).

## 6. Set up MetaTrader

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

Next: [Using MetaTrader](using.md) in the browser.
