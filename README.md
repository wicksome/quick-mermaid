# QuickMermaid

> Instantly render selected Mermaid text into a diagram — from any app.

QuickMermaid is a lightweight macOS menu-bar app that turns Mermaid source text
into a rendered diagram in a floating quick-look panel. Select Mermaid text
anywhere, trigger it, and the diagram pops up — no editor, no context switch.

<p align="center">
  <img src="docs/screenshots/render-example.png" alt="QuickMermaid rendering a Mermaid diagram in its floating panel" width="800">
</p>

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## Why

When a tool (an LLM in your terminal, a code review, a doc) hands you Mermaid
*source*, you can't see the diagram without pasting it into an editor or a web
page. QuickMermaid renders it in place: select → shortcut (or right-click
Services, or pipe via CLI) → diagram. Think Quick Look, not Preview.app.

## Features

- **Render from anywhere** — system Services menu, a global keyboard shortcut, or the `qmmd` CLI.
- **Source priority** — uses the current selection; falls back to the clipboard; shows nothing if there is no renderable text.
- **Zoom & pan** — buttons, `⌘+ / ⌘− / ⌘0`, `⌘`+scroll, trackpad pinch; drag to pan; auto-centered.
- **Themes & background** — pick a Mermaid theme and a canvas background color.
- **Source view** — toggle the original Mermaid text with syntax highlighting.
- **PNG export** — copy (`⌘C`) or save (`⌘S`) the **diagram only** (no toolbar, full size even off-screen).
- **Offline** — Mermaid is vendored; no network required.

## Install

Download the latest `QuickMermaid-x.y.z.dmg` from
[Releases](https://github.com/wicksome/quick-mermaid/releases), open it, and drag
**QuickMermaid.app** to `/Applications`.

The app is unsigned (ad-hoc), so on first launch Gatekeeper will warn you. Either:

- Right-click the app → **Open** → **Open**, or
- `xattr -dr com.apple.quarantine /Applications/QuickMermaid.app`

Prefer to build it yourself? `./build.sh --install` (see [AGENTS.md](AGENTS.md)).

## Usage

QuickMermaid runs in the menu bar. There are three ways to render — the CLI is
the most reliable for terminal workflows.

### A) CLI — `qmmd`

```bash
pbpaste | qmmd      # render the clipboard
qmmd flow.mmd       # render a file
qmmd                # no input → open Settings
```

### B) Services (right-click)

Select Mermaid text in any app that exposes selections to macOS Services
(Safari, TextEdit, Terminal, iTerm2, …) → **right-click → Services → Render Mermaid**.

> Apps cache the Services menu at launch. If the item doesn't appear, fully quit
> and relaunch that app, or run `/System/Library/CoreServices/pbs -update`.
> Note: Chrome doesn't show the Services submenu in its context menu — use the
> global shortcut there.

### C) Global shortcut

Enable it in **Settings** (default `⌃⌘M`). With the shortcut on, press it to
render — QuickMermaid uses the current **selection** (it copies it for you), or
falls back to whatever is on the **clipboard** when nothing is selected. This
works everywhere, including Chrome.

> The shortcut grabs the selection by synthesizing `⌘C`, which requires
> **Accessibility** permission (macOS prompts you when you enable it).
>
> The app is unsigned, so **every update is a new binary and macOS drops the
> previous grant.** After updating, re-allow QuickMermaid under **System Settings
> → Privacy & Security → Accessibility** (toggle it off/on, or remove and re-add
> it). Until you do, the shortcut still renders the clipboard but can't grab
> selections.

### In the panel

- **Zoom**: `⌘+ / ⌘− / ⌘0`, `⌘`+scroll, pinch, or the toolbar buttons; drag to pan.
- **`</> Source`**: show the original Mermaid text, syntax-highlighted.
- **Copy PNG / `⌘C`**, **Save PNG / `⌘S`**: export the diagram only.
- **Esc** or click outside to close (configurable in Settings).

### Settings

Open via `qmmd` (no input) or the menu-bar icon → **Settings**. Configure the
default theme, default zoom, background color, the global shortcut, and whether
the panel closes when it loses focus. A live preview reflects your choices.

## Limitations

- Unsigned / not notarized — intended for personal use; Gatekeeper warns on first launch.
- Very large diagrams: Mermaid limits are raised; beyond them the error view explains why. PNG export is capped at ~8192 px.

## Development

This project is developed primarily by AI. Architecture, build/verify steps,
conventions, and release process are in **[AGENTS.md](AGENTS.md)**.

## License

[MIT](LICENSE)
