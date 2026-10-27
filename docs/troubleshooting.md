# Troubleshooting

## Where the logs are

- **`docker logs metatrader-docker`** (or `docker compose logs`) has everything:
    - the certificate, as an `[mt-cert]` line when it's made or renewed;
    - the startup check, as `[mt-access]` lines;
    - the install and every MetaTrader start, as `[mt]` lines;
    - the stop, as `[mt-stop]`;
    - nginx's log of logins and requests;
    - Wine's errors.
- **MetaTrader's start log** stays in `/config/log/mt/run-terminal.log` (`data/log/mt/` on the host) across restarts.

## Common problems

- **A failed install step** shows a window on the desktop with the reason, counting down to the next try 60 s later, and the log has the details. A lost download, or a signature check that failed because a revocation list couldn't be fetched, usually passes on a later try. A file whose signature is wrong is never run.
- **Python's step fails** (`MT_PYTHON=true`): during MetaTrader's first install, it's retried every 60 s like the other steps, and MetaTrader waits. Later, when you turn Python on for an account in use, or a new image brings a newer Python, MetaTrader starts all the same: the log has a `WARNING` line with the reason, and the next start tries again. Behind a filter, allow the hosts in [What the container connects to](verify.md#what-the-container-connects-to), or remove `MT_PYTHON` to finish a first install without Python.
- **The container keeps restarting:** the startup check refused a setting. The log's `[mt-access] REFUSED:` line says which (see [Refused](settings.md#refused)).
- **Behind a proxy, the page loads but the desktop never appears:** the proxy probably replaces `Host`, and the container refuses the stream (see [What every proxy needs](access.md#what-every-proxy-needs)).
- **More from Wine:** `WINEDEBUG=fixme-all`, or empty (see [Wine's own settings](settings.md#wines-own)).

## Harmless messages at every start

From the desktop the image is built on:

- `17` and `18`: the sound server numbering the two audio devices it creates;
- `_XSERVTransmkdir: Cannot create /tmp/.X11-unix with root ownership` and `screen 0 shmid 0`: the display starting as the desktop's user;
- `xsettingsd: Unable to open connection to X server`, now and then: it started a moment before the display, and is started again;
- `No hardware encoder … (nvenc)` and `Failed to init NVENC`: the stream looks for a GPU encoder, and without one encodes on the CPU;
- `Apps panel enabled`: the panel stays hidden, and its actions are off.
