# Operations and updates

## Stopping and restarts

- **Stopping:** Run `docker compose stop` or `docker stop metatrader-docker`. The shutdown hook sends a graceful exit signal (like *File → Exit*), allowing MetaTrader up to 20s to persist charts and parameters before the container stops (configured via `stop_grace_period: 30s` / `--stop-timeout 30`).
- **Account credential restoration:** During shutdown, the container backs up `Config/accounts.dat` before MetaTrader closes and restores it immediately afterward. Under Wine, MetaTrader's shutdown rewrite of this file can trigger "Accounts deleted due security reason" on subsequent boots.
- **Auto-restart:** If MetaTrader closes or crashes during normal operation, the container watchdog restarts it automatically within seconds.

## Health check

`docker ps` indicates `healthy` once MetaTrader is running and the internal desktop server responds.

- Does not indicate broker connection status or EA execution (inspect MetaTrader's status bar and Journal tab for trading state).
- View health check output: `docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' metatrader-docker`.
- Container healthchecks have a 5-minute start period to accommodate initial provisioning.

## Stopping trading in a hurry

From mildest to most disruptive:

1. Click **Algo Trading** in the MetaTrader toolbar (halts EA execution; leaves open positions intact).
2. Stop the container: `docker stop metatrader-docker` (MetaTrader halts; broker retains server-side SL/TP orders).
3. Manually close positions in MetaTrader or your broker's mobile/web app, then stop the container.

## Updating the image

- **Image tags:**
    - `latest`: Tracks the most recent automated build.
    - Date tags (e.g. `20261019.1`): Pinned daily releases formatted for container update tools (e.g. WUD). Subsequent builds on the same date append `.2`, etc.
    - Commit tags (`sha-<commit>`): Specific git commit builds.
- **Rollbacks:** Pin the previous date tag instead of `latest`.
- **Python environments (`MT_PYTHON=true`):** Updated images automatically upgrade Python and pinned wheels in `/config` on boot. Rolling back restores previous pinned wheels while preserving newer Python binaries.

To update:

=== "Compose"

    ```sh
    docker compose pull && docker compose up -d
    ```

=== "docker run"

    ```sh
    docker pull ghcr.io/blunan/metatrader-docker:latest
    docker stop metatrader-docker && docker rm metatrader-docker
    ```

    Followed by the `docker run` command from the [quick start](quick-start.md#4-start-it).

## Updates inside the container

Two internal components update independently of the Docker image:

- **MetaTrader LiveUpdate:**
    - When *Welcome to LiveUpdate* indicates updates are ready, restart at a convenient time. LiveUpdate cannot be disabled in MetaTrader.
    - Always maintain backups of `/config` to protect against upstream regressions.
- **Microsoft Edge WebView2:** Edge Update runs in the background and applies runtime updates automatically.
