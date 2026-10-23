# Folders and files

| In the container | On the server | What's in it |
|---|---|---|
| `/config` (required) | `./data` | Everything for the account: Wine, the MetaTrader program, account logins and servers, charts with their EAs and inputs, settings, price history and logs, and the desktop's certificate. MetaTrader updates itself here. |
| `/mql5` (optional) | `./ea` | Your own EAs, indicators and scripts, laid out like MetaTrader's `MQL5` folder: `Experts`, `Indicators`, `Scripts`, `Include`, `Libraries`, `Presets`. |
| `/run/secrets/password` | `./secrets/password` | The desktop password. |
| `/config/ssl/cert.pem`, `/config/ssl/cert.key` (optional) | your certificate's files, such as `./tls/cert.pem` | A certificate of your own, and its key (see [Your own certificate](#your-own-certificate)). |

## `/config`

- It's a bind mount (a host folder), not a named Docker volume. `docker system prune --volumes` can't delete it while the container is stopped, and it's easy to back up.
- Keep it at mode `0700`: it holds saved broker logins. The container makes user 1000 (`PUID`) its owner at every start, and its log warns if other users on the host have any access to it.
- Back up `data` and the EA folder regularly, encrypted, and try a restore now and then.

## The EA folder (`/mql5`)

- Each of its sections appears in MetaTrader as a subfolder named `Mounted`, such as `MQL5/Experts/Mounted`.
- `Files` is never linked, because EAs keep their own data there.
- A missing section is created when the folder is writable, and skipped when it's read-only (`./ea:/mql5:ro`).
- On its first start, MetaTrader compiles the sources it finds there.
- *Refresh* in the Navigator shows files added on the host.
- With [file transfers](settings.md#the-main-settings) on, uploads land in its `Experts`, and appear in the Navigator under *Expert Advisors → Mounted* after *Refresh*. When it's read-only, or not mounted, they land in MetaTrader's own `MQL5/Experts`, in `data`.

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
