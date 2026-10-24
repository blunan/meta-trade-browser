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
