# Build it yourself

## Local build and tests

```sh
git clone https://github.com/blunan/metatrader-docker.git
cd metatrader-docker
docker build -t metatrader-docker:dev .
tests/access.sh
```

- `docker build --build-arg STRIP_WINE_DEBUG=false` keeps Wine's debug information, for crash backtraces with function names; the image grows by about 1 GB.
- `docker build --build-arg WINE_VERSION=<version>` installs another WineHQ staging release than the pinned one, for example to try a newer one. Versions look like `11.20~trixie-1`.
- `tests/access.sh` checks the access layer: logins, refusals, origins, headers, certificates, listening ports, and that the installers' signature check refuses an unsigned file, or a signer named `O=Spoof Ltd` that writes `O=MetaQuotes Ltd` into its common name. It also checks that a seccomp profile like Docker 29.4.2's, which refuses `socketcall`, stops the first install with a message that names the cause. It needs no internet and leaves nothing behind. `--host` adds the host-networking test, which binds `127.0.0.1:3911` on the machine.
- `tests/compose.dev.yaml` runs a local build with the example's settings, with its own container name, port (3201), folders and password, next to a real deployment:

    ```sh
    docker compose -f compose.yaml -f tests/compose.dev.yaml build
    docker compose -f compose.yaml -f tests/compose.dev.yaml up -d
    ```

    With `MT_PYTHON=true` in front of the second command, it installs Python too.

- `tests/python.sh` checks that container's Python, once MetaTrader has logged in to an account (a demo will do): the `MetaTrader5` package connects, and nothing listens on the network while a script is attached, only HTTPS on 3001. CI can't run it, since it doesn't install MetaTrader.

## In CI

`.github/workflows/image.yml` runs the same checks on every pull request and on `main`:

- `shellcheck` on every script;
- the build, then `tests/access.sh --host`, on the Docker Engine version set in the workflow (`DOCKER_VERSION`), started next to the runner's own, which can lag behind: Docker 29.4.2, which the runners had in October 2026, stops Wine from creating its prefix (see [Troubleshooting](troubleshooting.md));
- Trivy, which fails on any fixable HIGH or CRITICAL finding. Its exceptions, each with its reason, are in `.trivyignore.yaml`.

On `main` it then pushes the image it tested, signs it, and tags it (see [Security and verification](verify.md)). It runs on no schedule and can't be run by hand: the image changes only when a pull request is merged. Renovate proposes updates to the base image, Wine, Windows Python and its packages, the pinned actions and the tools as pull requests, and none merges by itself. Each action stays pinned to a commit SHA, with its version in a comment. On Monday mornings the workflows' actions, runners and the guide's Python version come together in one pull request, Wine comes in its own, Windows Python and its packages in a third, and the other minor and patch updates, which CI tests alone, in a fourth, so merging them publishes at most four new images a week rather than one per update. Wine and Windows Python carry the `manual-test` label, because CI doesn't install MetaTrader or Python: each new Wine is started once by hand before it's merged, and the Windows Python pull request, with a new Python or new versions of its packages, says how to start it once with `MT_PYTHON=true` before merging. Those packages, `MetaTrader5` and `numpy`, are pinned with the hashes of their files in `root/opt/mt/python-requirements.txt`, and Renovate updates the hashes with each version.

## This guide

The guide is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) from `docs/` and `mkdocs.yml`. `docs/requirements.txt` pins every package with its hash; it's generated from `docs/requirements.in` with `pip-compile --generate-hashes`, by hand, with the command in that file (Renovate leaves both files alone). To preview it:

```sh
python3 -m venv .venv
.venv/bin/pip install --require-hashes -r docs/requirements.txt
.venv/bin/mkdocs serve
```

Then browse to `http://127.0.0.1:8000`. `mkdocs build --strict` fails on a broken link, as the repository's workflow does.
