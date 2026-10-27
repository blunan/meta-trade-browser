# Using MetaTrader in the browser

## Desktop, clipboard and sound

- **The clipboard** works both ways. The browser asks for permission once.
- **Sound:** MetaTrader's sounds, such as a finished backtest or an alert, play in the browser. The speaker button in the side panel turns them off. A browser may wait for your first click on the page before it plays any.
- **The side panel** opens with Ctrl+Shift+M. With file transfers on, it has the file panel. It has no video or audio settings, and no microphone or webcam buttons.
- **Keyboard shortcuts:**
    - On Windows and Linux, the browser keeps Ctrl+N, Ctrl+T and Ctrl+W for itself. On macOS it passes them on to MetaTrader, since its own shortcuts use Cmd.
    - F11 belongs to the browser.

## MetaEditor and trading protections

- **MetaEditor** opens with F4 or MetaTrader's *IDE* button. The desktop's menu (right-click the desktop) has MetaTrader and MetaEditor, but MetaTrader usually covers the desktop.
- **The MQL Wizard's first page** ignores the mouse under Wine. Use the keyboard: the arrow keys, Tab and Enter.
- **After any manual login,** check the Algo Trading button. Switching accounts turns it off, if you ticked that protection in [step 6 of the quick start](quick-start.md#6-set-up-metatrader).
- **Save your work in MetaEditor before stopping the container.** MetaTrader is asked to close and save when the container stops, but MetaEditor isn't: a "Save changes?" question would hold up the stop.

## HTML panes and memory

- **The HTML panes:** Help (F1), Market, Signals, Mailbox messages and MetaEditor's Welcome page are web pages, shown through Microsoft Edge WebView2.
    - They need memory. With one open, the container can reach 4 GB, and Market alone reaches the quick start's 4 GB limit.
    - At the limit, the kernel stops one of Edge's processes first, not MetaTrader. The pane goes blank, and comes back when you close and reopen it. The log says when it happened.
    - If you use the panes a lot, set `mem_limit: 6g` (`--memory 6g`).
    - The MQL5 reference is also online, at <https://www.mql5.com/en/docs>.
- **Memory sizing:** about 0.5 GB with MetaTrader running EAs and nobody connected, 1.5 GB with a browser connected, 2.4 GB during a heavy backtest, and up to 4 GB with an HTML pane open.

## Python

With `MT_PYTHON=true` (see [Folders and settings](settings.md#the-main-settings)), the next start installs Windows Python 3.14 and MetaQuotes' [`MetaTrader5` package](https://www.mql5.com/en/docs/python_metatrader5) into `/config`. It downloads Python's 64-bit installer from python.org, and runs it only if the Python Software Foundation's signature checks out. Then pip installs `MetaTrader5`, and `numpy`, the one package it needs, from PyPI over HTTPS: those have no signature to check. This takes under a minute, and adds about 130 MB to `/config`. MetaTrader and MetaEditor find Python by themselves: MetaEditor shows its folder under **Tools → Options → Compilers**.

- **On a chart:** a `.py` script in `MQL5/Scripts`, or in the EA folder's `Scripts` (*Scripts → Mounted* in the Navigator), runs on a chart when you double-click it or drag it onto one. What it prints appears in the Toolbox's *Experts* tab.
- **The `MetaTrader5` package** connects to MetaTrader once MetaTrader has logged in to a trading account. Before the first login, `initialize()` fails with `(-10005, 'IPC timeout')`.
- **Trading from Python:** with the quick start's [step 6](quick-start.md#6-set-up-metatrader) settings, **Disable algorithmic trading via external Python API** is on. Scripts, on a chart or through `docker exec`, can read prices and the account, but `order_send` is refused with `10027` (*AutoTrading disabled by client*), as when Algo Trading is off. Untick that option, with **Allow algorithmic trading** on, when a script needs to trade.
- **From `docker exec`:** to run Python, or to install another package into `/config`:

    ```sh
    docker exec -u abc metatrader-docker wine python -c "import MetaTrader5 as mt5; print(mt5.initialize(), mt5.version()); mt5.shutdown()"
    docker exec -u abc metatrader-docker wine python -m pip install --only-binary=:all: pandas
    ```

- **Updates:** a new image with a newer Python 3.14 release upgrades Python and `MetaTrader5` at its first start, and going back to an older image keeps the newer Python. To follow MetaTrader's own updates in between: `docker exec -u abc metatrader-docker wine python -m pip install --upgrade MetaTrader5`.
- **If Python can't be installed:** during MetaTrader's first install, MetaTrader waits for it, as for the other steps: the window says why, and tries again 60 s later. Later on, when you turn `MT_PYTHON` on for an account in use, or a new image brings a newer Python, MetaTrader starts all the same: the log has a `WARNING` line with the reason, and the next start tries again.
- **Turning it off** leaves Python in `/config`, and stops its upgrades.
