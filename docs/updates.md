# Updates

## The image

- **Tags:**
    - `latest` follows every new build;
    - a date tag, such as `20261019`, stays on one build. A second build that day gets `20261019.2`;
    - `sha-<commit>` names the first build of that source commit.
- **New builds** come with every change to the image, including updates of the base image it's built on, which also bring Debian's fixes.
- **Going back:** use the previous date tag in place of `latest`, the same way.

To update:

=== "Compose"

    ```sh
    docker compose pull && docker compose up -d
    ```

=== "docker run"

    ```sh
    docker pull ghcr.io/blunan/mt-browser:latest
    docker stop mt-browser && docker rm mt-browser
    ```

    Then the same `docker run` as in the [quick start](quick-start.md#4-start-it).

## Inside the container

Two things update themselves, whatever the image:

- **MetaTrader, through LiveUpdate.**
    - When *Welcome to LiveUpdate* says updates have been downloaded, click *Restart* at a quiet moment. *Later* installs them at the next start.
    - MetaQuotes says LiveUpdate can't be turned off. It also brings MetaQuotes' machine-learning and AI components.
    - A new MetaTrader build could misbehave under Wine. Keep backups of `/config` to go back to.
- **WebView2, through Edge Update,** which keeps running in the background.
