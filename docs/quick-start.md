# Quick start

You need a Linux server with Docker Engine on amd64 (x86-64), ~4 GB RAM, ~10 GB disk space, and SSH access (see [What you need](index.md#what-you-need)).

## 1. Create the folders

On the server:

```sh
mkdir -p metatrader-docker && cd metatrader-docker
mkdir -p -m 700 data secrets
mkdir -p ea
```

`data` stores saved broker credentials (keep mode `0700`); `ea` is the optional directory for custom EAs/scripts.

The container runs as UID/GID `1000`. If `id -u` or `id -g` returns another value, set `PUID` and `PGID` under `environment` in `compose.yaml` (or `-e PUID=$(id -u) -e PGID=$(id -g)` in `docker run`; see [Folders and settings](settings.md#the-main-settings)).

## 2. Create the desktop password

```sh
openssl rand -base64 24 | tr -d '\n' > secrets/password
cat secrets/password; echo
```

Save the password in your password manager (or use your own single-line password, minimum 12 characters). Restrict read permissions to root:

```sh
sudo chown root:root secrets/password
sudo chmod 0400 secrets/password
```

Use `sudo cat secrets/password` to view it later.

## 3. Save `compose.yaml`

Save as `compose.yaml` in the same directory (also [in the repository](https://github.com/blunan/metatrader-docker/blob/main/compose.yaml)). If using `docker run`, skip to step 4.

```yaml
--8<-- "compose.yaml"
```

!!! warning "Never add `init: true`"
    The container requires its built-in s6 supervisor as process 1. Enabling Docker's init halts the container immediately.

## 4. Start it

Start the container and follow the logs:

=== "Compose"

    ```sh
    docker compose up -d
    docker compose logs -f
    ```

=== "docker run"

    ```sh
    docker run -d --name metatrader-docker \
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
      ghcr.io/blunan/metatrader-docker:latest
    docker logs -f metatrader-docker
    ```

Initial provisioning downloads and installs WebView2 and MetaTrader (~2–3 minutes). The container is ready when logs show `starting MetaTrader`. Press `Ctrl+C` to detach from logs.

!!! tip "On a shared server"
    Cap container processes and log file growth:

    === "Compose"

        Add to the service in `compose.yaml`:

        ```yaml
        pids_limit: 2048
        logging: { driver: local, options: { max-size: 10m, max-file: "5" } }
        ```

    === "docker run"

        Add `--pids-limit 2048 --log-driver local --log-opt max-size=10m --log-opt max-file=5`.

## 5. Open the desktop

On your workstation, establish an SSH tunnel to the server:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Browse to `https://localhost:3001`, accept the self-signed certificate warning, and sign in as `trader` with your password. If installation is in progress, a desktop status window displays current setup steps.

To eliminate browser warnings, trust the certificate locally: copy `data/ssl/cert.pem` to your workstation and import it into your system certificate trust store (valid only for `localhost` and `127.0.0.1`; automatically renewed every ~825 days).

For remote access options (VPN, Tailscale, or reverse proxies), see [Access and reverse proxy](access.md).

## 6. Set up MetaTrader

1. Log in to your trading account with *Save password* checked.
2. If *Welcome to LiveUpdate* indicates updates were downloaded, click *Restart*.
3. Under **Tools → Options → Experts**:
    - **Allow algorithmic trading:** on.
    - **Disable algorithmic trading when the account has been changed:** on.
    - **Disable algorithmic trading when the profile has been changed:** on.
    - **Disable algorithmic trading when the charts symbol or period has been changed:** on.
    - **Disable algorithmic trading via external Python API:** on, unless using `MT_PYTHON=true` for Python trading scripts (see [Python](using.md#python)).
    - **Allow DLL imports:** off, unless explicitly required by an EA.
    - **Allow WebRequest for listed URL:** off, unless explicitly required by an EA.
4. To reduce memory and network usage: **Charts → Max bars in chart:** 50000, and **Server → Enable news:** off.

Next: [Using MetaTrader](using.md) in the browser.
