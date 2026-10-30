# Using MetaTrader in the browser

## Desktop, clipboard and sound

- **Clipboard:** Bidirectional synchronization (browser requests permission on first use).
- **Sound:** MetaTrader audio events (order fills, alerts, backtest completion) stream to the browser. Toggle audio via the sidebar speaker icon. Note that modern browsers require an initial click on the page before playing sound.
- **Sidebar:** Toggle with `Ctrl+Shift+M`. Hosts the file manager panel when file transfers are enabled.
- **Keyboard shortcuts:**
    - Windows and Linux browsers intercept `Ctrl+N`, `Ctrl+T`, `Ctrl+W`, and `F11`. macOS passes these shortcuts through because it uses `Cmd` for browser navigation.

## MetaEditor and trading protections

- **MetaEditor:** Launch via `F4`, MetaTrader's *IDE* button, or the desktop right-click menu.
- **MQL Wizard:** The first wizard step does not capture mouse input under Wine; navigate using arrow keys, `Tab`, and `Enter`.
- **Algo Trading state:** Manual account switches automatically disable Algo Trading if the recommended protections in [quick start step 6](quick-start.md#6-set-up-metatrader) are enabled.
- **Saving work:** Always save changes in MetaEditor before stopping the container. Container shutdown signals MetaTrader to save and exit, but does not prompt MetaEditor.

## HTML panes and memory

- **WebView2 HTML panes:** Help (`F1`), Market, Signals, Mailbox, and MetaEditor Welcome tabs render through Microsoft Edge WebView2.
    - These panes increase memory footprint. Market alone can push usage toward 4 GB.
    - If the container hits its memory limit, the background OOM helper prioritizes stopping Edge renderer processes over MetaTrader. If a pane goes blank, close and reopen it.
    - For regular browsing of Market or Help, set `mem_limit: 6g` (`--memory 6g`).
    - The MQL5 reference is also available online at <https://www.mql5.com/en/docs>.
- **Typical memory footprint:** ~0.5 GB idle/headless, ~1.5 GB connected with charts/EAs, ~2.4 GB during backtests, up to 4 GB with HTML panes open.

## Python

Setting `MT_PYTHON=true` (see [Folders and settings](settings.md#the-main-settings)) installs Windows Python 3.14 and the verified [`MetaTrader5` package](https://www.mql5.com/en/docs/python_metatrader5) (plus `numpy`) into `/config` (~130 MB, takes <1 min). The installer Authenticode signature and wheel SHA-256 hashes are verified before installation. MetaTrader and MetaEditor automatically configure the interpreter path under **Tools → Options → Compilers**.

- **Running scripts on charts:** Drag or double-click `.py` files located in `MQL5/Scripts` or `/mql5/Scripts` (*Scripts → Mounted* in Navigator). Console output appears in the Toolbox *Experts* tab.
- **Permissions:** Python scripts execute natively under Wine with full access to container files and network. Standard MQL5 sandbox limits (**Allow DLL imports**, **WebRequest** whitelist) do not apply.
- **IPC connection:** `MetaTrader5.initialize()` connects over local IPC once MetaTrader has logged into an account. Calling it before initial login returns `(-10005, 'IPC timeout')`.
- **Algo trading flag:** When **Disable algorithmic trading via external Python API** is enabled ([quick start step 6](quick-start.md#6-set-up-metatrader)), scripts can read market and account data, but `order_send` fails with `10027` (*AutoTrading disabled by client*). Uncheck this option and enable **Allow algorithmic trading** to permit orders.
- **Container CLI (`docker exec`):**

    ```sh
    docker exec -u abc metatrader-docker wine python -c "import MetaTrader5 as mt5; print(mt5.initialize(), mt5.version()); mt5.shutdown()"
    docker exec -u abc metatrader-docker wine python -m pip install --only-binary=:all: pandas
    ```

- **Upgrades:** Newer image releases automatically upgrade Python or dependency wheels in `/config`. Reverting to an earlier image preserves newer Python versions and restores older pinned wheels.
- **Installation failures:** If Python provisioning fails during initial setup, setup pauses with an error dialog and retries every 60s. On existing setups, MetaTrader still launches and displays a persistent desktop notification.
- **Disabling:** Setting `MT_PYTHON=false` leaves existing Python files in `/config` but halts automatic upgrades.
