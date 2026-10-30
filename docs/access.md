# Access and reverse proxy

The container serves the desktop over HTTPS on port 3001 (no plain-HTTP port). The [quick start](quick-start.md) publishes to `127.0.0.1` only. Choose an access method below.

!!! warning "Exposing your installation carries inherent security risks"
    Anyone who accesses the desktop can execute trades on your account. Never publish port 3001 directly to a public IP (`0.0.0.0:3001:3001`). When exposing via a reverse proxy or VPN, enforce strong pre-authentication (SSO/MFA via Cloudflare Access, Authelia, or Authentik) and restrict network access with firewall rules or [`TRUSTED_PROXIES`](settings.md#reverse-proxy-vpn-and-host-networking).

## SSH tunnel

The default method from the quick start. Exposes nothing new on the network:

```sh
ssh -N -L 3001:127.0.0.1:3001 you@your-server
```

Browse to `https://localhost:3001` (see [quick start step 5](quick-start.md#5-open-the-desktop) to trust the self-signed certificate).

## VPN and Tailscale

### Publish on the VPN address

Replace `127.0.0.1` in `compose.yaml`'s `ports` (or `docker run` `-p`) with the server's VPN/Tailscale IP, then recreate the container. Only VPN devices can access `https://<vpn-ip>:3001`.

The VPN interface must be up before the container starts. To trust this connection in your browser, see [Your own certificate](#your-own-certificate).

### Tailscale Serve

Keep `127.0.0.1` in `compose.yaml` and let Tailscale terminate TLS on your tailnet:

```sh
sudo tailscale serve --bg --https=3001 https+insecure://127.0.0.1:3001
```

Browse to `https://<machine>.<tailnet>.ts.net:3001`. `https+insecure` tells Tailscale to accept the container's local certificate.

## Behind a reverse proxy

A reverse proxy provides custom domain routing, public TLS certificates, and centralized authentication (Cloudflare Access, Authelia, Authentik). Desktop password authentication remains active behind the proxy.

### What every proxy needs

1. **Connect via HTTPS without certificate verification:** The local hop from proxy to container uses the container's self-signed certificate.
2. **Forward the original `Host` header:** WebSockets streaming checks origin against `Host`. If your proxy cannot preserve `Host`, list the public origin in [`SELKIES_ALLOWED_ORIGINS`](settings.md#reverse-proxy-vpn-and-host-networking) (e.g. `https://mt.example.com`).
3. **Optional network isolation (`TRUSTED_PROXIES`):** Place the proxy and container on a dedicated Docker network and specify the proxy IP/range in [`TRUSTED_PROXIES`](settings.md#reverse-proxy-vpn-and-host-networking). Other connections receive 403, and access logs reflect client IPs from `X-Forwarded-For`. Remove published `ports` if routing solely through the proxy.

### Proxy examples

=== "Caddy"

    In `Caddyfile`:

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

    In the `server` block for your domain:

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

    With this in the `http` block:

    ```nginx
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
    ```

=== "Traefik"

    Dynamic configuration file (file provider):

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

    With Docker labels, reference the transport file: `traefik.http.services.mt.loadbalancer.server.scheme=https`, `traefik.http.services.mt.loadbalancer.server.port=3001`, and `traefik.http.services.mt.loadbalancer.serverstransport=mt@file`.

=== "cloudflared"

    Locally managed tunnel (`config.yml`):

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

The container serves `/config/ssl/cert.pem` and `cert.key`. If missing, it generates a self-signed certificate valid for `localhost`, `127.0.0.1`, and `::1` (825-day validity, renewed when <=30 days remain).

Custom certificates are only required if browsers connect directly under another hostname (e.g. VPN IP with `tailscale cert`). Mount PEM-encoded certificate and private key files:

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

- `cert.pem` contains the server certificate and any intermediates; `cert.key` contains the unencrypted private key.
- Both files must exist on the host before starting the container.
- Restart the container after certificate renewals to reload nginx.
- Removing custom certificate mounts restores the container's generated certificate on next start.

## Host networking

With host networking, the container shares the server's network stack directly:

- Only nginx listens publicly on `127.0.0.1:3001` (configurable via [`LISTEN_ADDRESS`](settings.md#reverse-proxy-vpn-and-host-networking) and [`CUSTOM_HTTPS_PORT`](settings.md#reverse-proxy-vpn-and-host-networking)). Internal services communicate exclusively via Unix sockets.

!!! warning
    **With host networking, MetaTrader and all EAs can reach whatever listens on the server's loopback interface.** The default bridge network prevents this and is recommended.

=== "Compose"

    In `compose.yaml`, replace `ports` with `network_mode: host`.

=== "docker run"

    Use `--network host` instead of `-p`.
