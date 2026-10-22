# Folders and files

| In the container | On the server | What's in it |
|---|---|---|
| `/config` (required) | `./data` | Everything for the account: Wine, the MetaTrader program, account logins and servers, charts with their EAs and inputs, settings, price history and logs, and the desktop's certificate. MetaTrader updates itself here. |
| `/mql5` (optional) | `./ea` | Your own EAs, indicators and scripts, laid out like MetaTrader's `MQL5` folder: `Experts`, `Indicators`, `Scripts`, `Include`, `Libraries`, `Presets`. |
| `/run/secrets/password` | `./secrets/password` | The desktop password. |

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
