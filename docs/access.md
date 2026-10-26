# Access and reverse proxy

The container serves the desktop over HTTPS on port 3001; there's no plain-HTTP port. The [quick start](quick-start.md) publishes it on the server's `127.0.0.1` only. Pick one of these ways in.

!!! warning "Exposing your installation carries inherent security risks"
    While this image is hardened by design, **anyone who reaches the desktop and gets past the login can trade on your account.** Publishing the container beyond `127.0.0.1`—over a VPN, a reverse proxy or the internet—carries inherent security risks. You are solely responsible for hardening and securing access to your deployment: never publish port 3001 directly on a public IP (`0.0.0.0:3001:3001`), enforce strong authentication (such as multi-factor authentication through Cloudflare Access, Authelia or Authentik) in front of any internet-facing proxy, restrict network access with firewall rules or [`TRUSTED_PROXIES`](settings.md#reverse-proxy-vpn-and-host-networking), and keep your proxy, VPN and host system updated.

## SSH tunnel

The quick start's way. Nothing else is needed, and nothing new is exposed on the network:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Then browse to `https://localhost:3001` (see [step 5 of the quick start](quick-start.md#5-open-the-desktop) to trust the container's certificate).

## VPN and Tailscale

### Publish on the VPN's address

In `compose.yaml`'s `ports`, or `docker run`'s `-p`, replace `127.0.0.1` with the server's VPN address, such as its Tailscale IP, and recreate the container. Only devices on the VPN can then connect, at `https://<that address>:3001`.

The address has to exist when the container starts: if the VPN starts after Docker at boot, run `docker compose up -d` once it's up. For a certificate the browser trusts at that address, see [Your own certificate](#your-own-certificate).

### Tailscale Serve

Keep `127.0.0.1` in `compose.yaml`, and let Tailscale serve the desktop on your tailnet with its own certificate:

```sh
sudo tailscale serve --bg --https=3001 https+insecure://127.0.0.1:3001
```

Then browse to `https://<machine>.<tailnet>.ts.net:3001`. `https+insecure` means Tailscale doesn't check the container's certificate; that hop never leaves the server.

## Behind a reverse proxy

A reverse proxy gives you your own domain with a trusted certificate, and a place for a real login in front, such as Cloudflare Access, Authelia or Authentik. The desktop's own password still applies behind it.

!!! warning "Internet exposure and access hardening"
    Exposing the container through an internet-facing reverse proxy places your trading terminal behind whatever controls you configure on that proxy. Even though the image is secure by design, you are solely responsible for securing the proxy layer—including TLS configuration, strong pre-authentication (SSO/MFA), rate limiting and network isolation (`TRUSTED_PROXIES`).

### What every proxy needs

1. **It connects over HTTPS, without checking the container's certificate.** The container's certificate is its own and self-signed, so the examples turn the check off. The hop from the proxy to the container stays on the server.
2. **It passes the browser's `Host` header on.** The desktop streams over a WebSocket, which the container accepts only from the page's own origin, and it learns that origin from `Host`. A proxy that replaces `Host` gets the stream refused (403). If yours can't keep it, list your public origin in [`SELKIES_ALLOWED_ORIGINS`](settings.md#reverse-proxy-vpn-and-host-networking), such as `https://mt.example.com`.
3. **Optionally, only the proxy gets in.** Put the proxy and the container on a Docker network of their own, and list the proxy's address on it in [`TRUSTED_PROXIES`](settings.md#reverse-proxy-vpn-and-host-networking). Everyone else gets 403, and the log shows the browser's address (`X-Forwarded-For`) for requests that come through the proxy. The SSH tunnel then gets 403 too: through a published port, the container sees Docker's gateway address. If the proxy is your only way in, remove `ports`.

The examples reach the container as `metatrader-docker:3001`, its name on a Docker network it shares with the proxy. A proxy installed on the server itself, outside Docker, uses `127.0.0.1:3001` instead, and leaves `TRUSTED_PROXIES` unset: the container sees Docker's gateway address rather than the proxy's. Add your login (Authelia, Authentik, and so on) the way your proxy's documentation shows.

### Proxy examples

=== "Caddy"

    In the `Caddyfile`. When the upstream is HTTPS, Caddy sends the upstream's own address as `Host` unless told otherwise:

    ```
    mt.example.com {
    	reverse_proxy https://metatrader-docker:3001 {
    		header_up Host {host}
    		transport http {
    			tls_insecure_skip_verify
    		}
    	}
    }
    ```

=== "nginx"

    In the `server` block for your domain. nginx sends its upstream's address as `Host` by default:

    ```nginx
    location / {
        proxy_pass              https://metatrader-docker:3001;
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

=== "Traefik"

    A dynamic configuration file (file provider). Traefik passes `Host` on by default:

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
              - url: https://metatrader-docker:3001
            serversTransport: mt
      serversTransports:
        mt:
          insecureSkipVerify: true
    ```

    With Docker labels instead, the servers transport still has to be in a file. The labels then include `traefik.http.services.mt.loadbalancer.server.scheme=https`, `traefik.http.services.mt.loadbalancer.server.port=3001` and `traefik.http.services.mt.loadbalancer.serverstransport=mt@file`, and `traefik.docker.network` names the network Traefik and the container share.

=== "cloudflared"

    A locally managed tunnel's `config.yml`. Protect the hostname with a Cloudflare Access application:

    ```yaml
    tunnel: <tunnel ID>
    credentials-file: /etc/cloudflared/<tunnel ID>.json
    ingress:
      - hostname: mt.example.com
        service: https://metatrader-docker:3001
        originRequest:
          noTLSVerify: true
      - service: http_status:404
    ```

## Your own certificate

The container serves `/config/ssl/cert.pem` and `cert.key`. When they don't exist, it makes its own there: self-signed, issued to `localhost`, `127.0.0.1` and `::1`, unable to sign other certificates, and valid for 825 days. A start in its last 30 days renews it.

You need one of your own only when the browser connects straight to the container under another name, such as the server's VPN address with a certificate from `tailscale cert`. The SSH tunnel uses the container's own ([how to trust it](quick-start.md#5-open-the-desktop)), and a reverse proxy or Tailscale Serve shows the browser a certificate of its own.

Mount the two files there, read-only:

=== "Compose"

    ```yaml
        volumes:
          - ./data:/config
          - ./ea:/mql5
          - ./tls/cert.pem:/config/ssl/cert.pem:ro
          - ./tls/cert.key:/config/ssl/cert.key:ro
    ```

=== "docker run"

    Add `-v "$PWD/tls/cert.pem:/config/ssl/cert.pem:ro" -v "$PWD/tls/cert.key:/config/ssl/cert.key:ro"`.

- `cert.pem` holds the certificate, followed by any intermediate certificates, and `cert.key` its private key, without a passphrase. Both in PEM format.
- Both files must exist on the server before the container starts: Docker turns a missing one into a folder, and the container stops.
- Copying the two files into `data/ssl` works too. Either way, the container never touches yours.
- After a renewal, restart the container: nginx reads the files when it starts.
- A certificate and key that don't belong together, or only one of the two, stop the container, and its log says why.
- Removing the mounts brings the container's own certificate back at the next start. Docker may leave two empty files in `data/ssl`; the container makes its own over them.

## Host networking

Host networking works too. The container then shares the server's network:

- Only the HTTPS port listens on the server, on `127.0.0.1:3001` unless you set [`LISTEN_ADDRESS`](settings.md#reverse-proxy-vpn-and-host-networking). Everything else inside stays on socket files or is off.
- If port 3001 is taken on the server, set [`CUSTOM_HTTPS_PORT`](settings.md#reverse-proxy-vpn-and-host-networking).

!!! warning
    **With host networking, MetaTrader, and every EA, can reach whatever listens on the server's own loopback,** such as other containers' published ports. The default bridge network doesn't allow that, so prefer it.

=== "Compose"

    In `compose.yaml`, replace `ports` with `network_mode: host`.

=== "docker run"

    Use `--network host` instead of `-p`.
