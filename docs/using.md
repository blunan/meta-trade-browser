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

With `MT_PYTHON=true` (see [Folders and settings](settings.md#the-main-settings)), the next start downloads the 64-bit Windows Python installer, checks the Python Software Foundation's signature, installs Python and MetaQuotes' [`MetaTrader5` package](https://www.mql5.com/en/docs/python_metatrader5) (`MetaTrader5` and `numpy`) into `/config`, and sets the Python path in **Tools → Options → Compilers**.

- **From a chart or MetaEditor:** `.py` scripts in `MQL5/Scripts` or `MQL5/Experts` (including `/mql5/Scripts` under *Scripts → Mounted* in the Navigator) run when dragged onto a chart, or with F5/F7 in MetaEditor. Their output appears in the *Experts* tab of the Toolbox.
- **Trading from Python:** by default, **Disable algorithmic trading via external Python API** under **Tools → Options → Experts** is on, so Python scripts can read market and account data (`initialize`, `symbol_info_tick`, `copy_rates_from_pos`, `account_info`, `positions_get`) but cannot place orders. Untick it, with **Allow algorithmic trading** on, when a Python script needs `order_send`.
- **From `docker exec`:** to run a script or install another wheel into `/config`:

    ```sh
    docker exec -u abc metatrader-docker wine python -c "import MetaTrader5 as mt5; mt5.initialize(); print(mt5.terminal_info()); mt5.shutdown()"
    docker exec -u abc metatrader-docker wine python -m pip install --only-binary=:all: pandas
    ```
