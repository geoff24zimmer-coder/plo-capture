# Web build checks (headless Chrome over CDP)

Drive the real Flutter web build and screenshot it — the way every screen in
the tracker / equity / rebrand / home work was verified.

```sh
cd plo-app && ~/flutter/bin/flutter build web --release
python3 -m http.server 8765 --directory build/web &   # serve the build
cd tool/web_check && node check_home.mjs              # screenshots land here
```

- `cdp.mjs` — minimal driver (Node ≥22, built-in WebSocket). Launches its OWN
  headless Chrome on a dynamic port (`--remote-debugging-port=0` +
  `DevToolsActivePort`) so it can never attach to another session's browser.
  Clicks by Flutter semantics label (`tap('Session tracker')`); text fields
  still need coordinate clicks + `Input.insertText`. Viewport 500×717 @1x.
- `demo-backup.json` — ~7 weeks of sample sessions + captured hands (incl. a
  turn and a preflop all-in) for Tracker → ⋮ → Restore from backup.
  `check_tracker.mjs` restores it through the real file input (headless
  cancels native choosers, so it intercepts `Page.fileChooserOpened`).
- `check_home.mjs` home buttons → sub-menu → setup · `check_equity.mjs`
  calculator (and browser timing) · `check_brand.mjs` splash frames + page
  metadata · `check_quick.mjs` the "start then immediately end" session · `check_stacks.mjs`
  long-press a seat → set its stack; a refused edit; undo then re-edit.
