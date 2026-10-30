# Troubleshooting

## Where the logs are

- **`docker logs metatrader-docker`** (or `docker compose logs`):
    - `[mt-cert]`: TLS certificate creation and renewals.
    - `[mt-access]`: Security and environment validation results.
    - `[mt]`: Component downloads, signature verification, and MetaTrader startup.
    - `[mt-stop]`: Graceful shutdown and account state preservation.
    - nginx request and authentication logs.
    - Wine runtime output.
- **Terminal output log:** Persisted across container restarts in `/config/log/mt/run-terminal.log` (`data/log/mt/` on host).

## Common problems

- **Failed installation step:** The desktop displays an error countdown window and retries every 60 seconds. Transient network timeouts or CRL lookup failures typically resolve on retry. Installers with invalid signatures are never run.
- **Install fails at step 1 with `wine: socket : Function not implemented`:** Docker 29.4.2 seccomp profile blocks the `socketcall` syscall required by 32-bit Wine processes. Upgrade Docker to 29.4.3+ (check with `docker version`).
- **Python provisioning fails (`MT_PYTHON=true`):** Retried every 60s during initial setup. On existing accounts or image upgrades, MetaTrader launches normally while displaying a desktop notification and logging a `WARNING`. If operating behind a firewall, ensure endpoints in [What the container connects to](verify.md#what-the-container-connects-to) are allowed.
- **Container continuously restarts:** A configuration setting was rejected during startup validation. Inspect logs for `[mt-access] REFUSED:` (see [Refused](settings.md#refused)).
- **Web page loads but desktop stream fails behind reverse proxy:** The proxy likely rewrote or dropped the `Host` header, triggering WebSocket origin rejection (see [What every proxy needs](access.md#what-every-proxy-needs)).
- **Verbose Wine debug output:** Configure `WINEDEBUG` (see [Wine's own settings](settings.md#wines-own)).

## Harmless startup messages

Normal base image initialization messages:

- `17` / `18`: PulseAudio device initialization indices.
- `_XSERVTransmkdir: Cannot create /tmp/.X11-unix with root ownership` and `screen 0 shmid 0`: Xvfb running under non-root desktop user.
- `xsettingsd: Unable to open connection to X server`: Benign race condition resolved automatically on immediate retry.
- `No hardware encoder … (nvenc)`: Fallback to software CPU video encoding when no Nvidia GPU is present.
- `Apps panel enabled`: Informational base desktop log; applications panel remains disabled.
