# Build it yourself

## Local build and tests

```sh
git clone https://github.com/blunan/metatrader-docker.git
cd metatrader-docker
docker build -t metatrader-docker:dev .
tests/access.sh
```

- `docker build --build-arg STRIP_WINE_DEBUG=false`: Retains Wine debug symbols for crash backtraces (adds ~1 GB).
- `docker build --build-arg WINE_VERSION=<version>`: Installs custom WineHQ staging release (e.g. `11.20~trixie-1`).
- `tests/access.sh`: Validates access controls, refusals, origins, TLS certificates, ports, and Authenticode verification (including spoofed signer names and Docker seccomp checks). Offline and leaves no artifacts. Add `--host` to test host networking (binds `127.0.0.1:3911`).
- `tests/compose.dev.yaml`: Runs a local development container on port 3201 alongside existing deployments:

    ```sh
    docker compose -f compose.yaml -f tests/compose.dev.yaml build
    docker compose -f compose.yaml -f tests/compose.dev.yaml up -d
    ```

    Prefix with `MT_PYTHON=true` to provision Python.

- `tests/python.sh`: Verifies Python IPC connection and port isolation against a running container logged into an account.
- `shellcheck`: Lints every shell script, as CI does, in a throwaway container:

    ```sh
    git ls-files | while read -r f; do head -n 1 "$f" | grep -q -E '^#!.*[/ ](ba)?sh$' && echo "$f"; done |
      xargs docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0
    ```

## In CI

`.github/workflows/image.yml` runs automated verification on pull requests and `main` pushes:

- `shellcheck` across all scripts.
- Image build and `tests/access.sh --host` on pinned Docker Engine (`DOCKER_VERSION`).
- Trivy vulnerability and secret scanning (fails on fixable HIGH/CRITICAL findings; exceptions documented in `.trivyignore.yaml`).

On `main`, the workflow pushes the verified image, signs the digest with Cosign, and tags the release (see [Security and verification](verify.md)).

Renovate batches dependency updates into scheduled pull requests (Actions/runners, Wine, Windows Python/packages, and minor/patch bumps). Wine and Python PRs carry the `manual-test` label for verification prior to merging because CI does not run full GUI installations. Dependencies (`MetaTrader5`, `numpy`) are pinned with SHA-256 hashes in `root/opt/mt/python-requirements.txt`.

## This guide

The documentation is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) from `docs/` and `mkdocs.yml`. Dependencies are pinned with hashes in `docs/requirements.txt` (generated from `docs/requirements.in` via `pip-compile --generate-hashes`).

To preview locally:

```sh
python3 -m venv .venv
.venv/bin/pip install --require-hashes -r docs/requirements.txt
.venv/bin/mkdocs serve
```

Without a local Python, preview in a throwaway container on the same Python version as CI (`python-version` in `.github/workflows/docs.yml`):

```sh
docker run --rm -it -p 127.0.0.1:8000:8000 -v "$PWD:/work:ro" -w /work python:3.15-slim-trixie \
  sh -c 'pip install -q --root-user-action=ignore --require-hashes -r docs/requirements.txt && mkdocs serve -a 0.0.0.0:8000'
```

Browse to `http://127.0.0.1:8000`. `mkdocs build --strict` verifies links, matching CI checks (in the container, add `--site-dir /tmp/site`, since the checkout is mounted read-only).
