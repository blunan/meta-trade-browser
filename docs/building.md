# Build it yourself

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

## This guide

The guide is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) from `docs/` and `mkdocs.yml`. `docs/requirements.txt` pins every package with its hash; it's generated from `docs/requirements.in` with `pip-compile --generate-hashes`. To preview it:

```sh
python3 -m venv .venv
.venv/bin/pip install --require-hashes -r docs/requirements.txt
.venv/bin/mkdocs serve
```

Then browse to `http://127.0.0.1:8000`. `mkdocs build --strict` fails on a broken link, as the repository's workflow does.
