# Stopping, restarts and health

- **Stopping:** `docker compose stop`, or `docker stop mt-browser`. MetaTrader gets a close request, as *File → Exit* sends, and saves its charts and settings; this usually takes about a second. The quick start's 30 s (`stop_grace_period`, `--stop-timeout`) gives it the time.
- **At every stop with a saved login, the log says the account file was put back:** "put back Config/accounts.dat from before the close". Under Wine, the copy of `accounts.dat` that MetaTrader writes while closing doesn't survive a container restart. At the next start MetaTrader would log "Accounts deleted due security reason" and not log in. So the copy from before the close is kept.
- **If MetaTrader closes or crashes,** the desktop starts it again within seconds.
- **The health check:** `docker ps` shows *healthy* when MetaTrader is running and the desktop answers.
    - It doesn't show whether MetaTrader is connected to the broker, or whether an EA is running. MetaTrader's status bar and its Journal show that.
    - `docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' mt-browser` shows why a check failed.
    - The first start has 5 minutes before failed checks count.

## Stopping trading in a hurry

From mildest to strongest:

1. Click **Algo Trading** in the terminal. No EA can trade, and positions stay open.
2. `docker stop mt-browser`. The terminal stops. Open positions keep their stop-loss and take-profit on the broker's server.
3. Close positions by hand, on the desktop or in your broker's app, then stop.
