# Behind a reverse proxy

A reverse proxy gives you your own domain with a trusted certificate, and a place for a real login in front, such as Cloudflare Access, Authelia or Authentik. The desktop's own password still applies behind it.

## What every proxy needs

1. **It connects over HTTPS, without checking the container's certificate.** The container's certificate is its own and self-signed, so the examples turn the check off. The hop from the proxy to the container stays on the server.
2. **It passes the browser's `Host` header on.** The desktop streams over a WebSocket, which the container accepts only from the page's own origin, and it learns that origin from `Host`. A proxy that replaces `Host` gets the stream refused (403). If yours can't keep it, list your public origin in [`SELKIES_ALLOWED_ORIGINS`](settings.md#reverse-proxy-vpn-and-host-networking), such as `https://mt.example.com`.
3. **Optionally, only the proxy gets in.** Put the proxy and the container on a Docker network of their own, and list the proxy's address on it in [`TRUSTED_PROXIES`](settings.md#reverse-proxy-vpn-and-host-networking). Everyone else gets 403, and the log shows the browser's address (`X-Forwarded-For`) for requests that come through the proxy. The SSH tunnel then gets 403 too: through a published port, the container sees Docker's gateway address. If the proxy is your only way in, remove `ports`.

The examples reach the container as `mt-browser:3001`, its name on a Docker network it shares with the proxy. A proxy installed on the server itself, outside Docker, uses `127.0.0.1:3001` instead, and leaves `TRUSTED_PROXIES` unset: the container sees Docker's gateway address rather than the proxy's. Add your login (Authelia, Authentik, and so on) the way your proxy's documentation shows.

## Examples

=== "Caddy"

    In the `Caddyfile`. When the upstream is HTTPS, Caddy sends the upstream's own address as `Host` unless told otherwise:

    ```
    mt.example.com {
    	reverse_proxy https://mt-browser:3001 {
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
        proxy_pass              https://mt-browser:3001;
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
              - url: https://mt-browser:3001
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
        service: https://mt-browser:3001
        originRequest:
          noTLSVerify: true
      - service: http_status:404
    ```
