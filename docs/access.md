# Reaching the desktop

The container serves the desktop over HTTPS on port 3001; there's no plain-HTTP port. The [quick start](quick-start.md) publishes it on the server's `127.0.0.1` only. Pick one of these ways in.

## SSH tunnel

The quick start's way. Nothing else is needed, and nothing new is exposed:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

## A VPN

- **Publish on the VPN's address:** in `compose.yaml`'s `ports`, or `docker run`'s `-p`, replace `127.0.0.1` with the server's VPN address, such as its Tailscale IP, and recreate the container. Only devices on the VPN can then connect, at `https://<that address>:3001`. The address has to exist when the container starts: if the VPN starts after Docker at boot, run `docker compose up -d` once it's up.
- **Tailscale Serve:** keep `127.0.0.1`, and let Tailscale serve the desktop on your tailnet with its own certificate:

    ```sh
    sudo tailscale serve --bg --https=3001 https+insecure://127.0.0.1:3001
    ```

    Then browse to `https://<machine>.<tailnet>.ts.net:3001`. `https+insecure` means Tailscale doesn't check the container's certificate; that hop never leaves the server.

## A reverse proxy

Your own domain with a trusted certificate, and a place for a real login in front: see [Behind a reverse proxy](reverse-proxy.md).

## Host networking

Host networking works too. The container then shares the server's network:

- Only the HTTPS port listens on the server, on `127.0.0.1:3001` unless you set `LISTEN_ADDRESS`. Everything else inside stays on socket files or is off.
- If port 3001 is taken on the server, set `CUSTOM_HTTPS_PORT`.

!!! warning
    **With host networking, MetaTrader, and every EA, can reach whatever listens on the server's own loopback,** such as other containers' published ports. The default bridge network doesn't allow that, so prefer it.

=== "Compose"

    In `compose.yaml`, replace `ports` with `network_mode: host`.

=== "docker run"

    Use `--network host` instead of `-p`.
