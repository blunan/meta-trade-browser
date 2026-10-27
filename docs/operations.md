# Operations and updates

## Stopping and restarts

- **Stopping:** `docker compose stop`, or `docker stop metatrader-docker`. MetaTrader gets a close request, as *File → Exit* sends, and saves its charts and settings; this usually takes about a second. The quick start's 30 s (`stop_grace_period`, `--stop-timeout`) gives it the time.
- **At every stop with a saved login, the log says the account file was put back:** "put back Config/accounts.dat from before the close". Under Wine, the copy of `accounts.dat` that MetaTrader writes while closing doesn't survive a container restart. At the next start MetaTrader would log "Accounts deleted due security reason" and not log in. So the copy from before the close is kept.
- **If MetaTrader closes or crashes,** the desktop starts it again within seconds.

## Health check

`docker ps` shows *healthy* when MetaTrader is running and the desktop answers.

- It doesn't show whether MetaTrader is connected to the broker, or whether an EA is running. MetaTrader's status bar and its Journal show that.
- `docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' metatrader-docker` shows why a check failed.
- The first start has 5 minutes before failed checks count.

## Stopping trading in a hurry

From mildest to strongest:

1. Click **Algo Trading** in the terminal. No EA can trade, and positions stay open.
2. `docker stop metatrader-docker`. The terminal stops. Open positions keep their stop-loss and take-profit on the broker's server.
3. Close positions by hand, on the desktop or in your broker's app, then stop.

## Updating the image

- **Tags:**
    - `latest` follows every new build;
    - a date tag, such as `20261019.1`, stays on one build. A second build that day gets `20261019.2`. Every date tag has this form, so update tools that compare tags, such as WUD, offer each newer one;
    - `sha-<commit>` names the first build of that source commit.
- **New builds** come with every change to the image, including updates of the base image it's built on, which also bring Debian's fixes.
- **Going back:** use the previous date tag in place of `latest`, the same way.
- **Python,** with `MT_PYTHON=true` (see [Python](using.md#python)): a new image that brings a newer Python 3.14 release, or newer packages, upgrades them at its first start. Going back to an older image keeps the newer Python, and puts back that image's packages.

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

    Then the same `docker run` as in the [quick start](quick-start.md#4-start-it).

## Updates inside the container

Two things update themselves, whatever the image:

- **MetaTrader, through LiveUpdate.**
    - When *Welcome to LiveUpdate* says updates have been downloaded, click *Restart* at a quiet moment. *Later* installs them at the next start.
    - MetaQuotes says LiveUpdate can't be turned off. It also brings MetaQuotes' machine-learning and AI components.
    - A new MetaTrader build could misbehave under Wine. Keep backups of `/config` to go back to.
- **WebView2, through Edge Update,** which keeps running in the background.
