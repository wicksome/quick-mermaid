# QuickMermaid

> Instantly render selected Mermaid text into a diagram — from any app.

QuickMermaid is a lightweight macOS menu-bar app that turns Mermaid source text
into a rendered diagram in a floating quick-look panel. Select Mermaid text
anywhere, trigger it, and the diagram pops up — no editor, no context switch.

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
- **Friendly states** — clear empty / parse-error views instead of a raw error.
- **Offline** — Mermaid is vendored; no network required.
- **Localized** — English and Korean (follows the system language).

## Install

### Download

Grab the latest `QuickMermaid-x.y.z.dmg` from [Releases](https://github.com/wicksome/quick-mermaid/releases),
open it, and drag **QuickMermaid.app** to `/Applications`.

The app is unsigned (ad-hoc), so on first launch Gatekeeper will warn you. Either:

- Right-click the app → **Open** → **Open**, or
- `xattr -dr com.apple.quarantine /Applications/QuickMermaid.app`

### Build from source

Requires the Swift toolchain (Xcode or Xcode Command Line Tools). No IDE needed.

```bash
./build.sh            # build QuickMermaid.app
./build.sh --dmg      # build .app + QuickMermaid.dmg
./build.sh --selftest # build, then verify the offline render pipeline
./build.sh --install  # install to /Applications + put the qmmd CLI on PATH, then launch
```

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

Enable it in **Settings** (default `⌃⌘M`). With the shortcut on, select text in
any app and press it — QuickMermaid copies the selection and renders it. This
works everywhere, including Chrome.

> The shortcut grabs the selection by synthesizing `⌘C`, which requires
> **Accessibility** permission (macOS prompts you when you enable it).

### In the panel

- **Zoom**: `⌘+ / ⌘− / ⌘0`, `⌘`+scroll, pinch, or the toolbar buttons; drag to pan.
- **`</> Source`**: show the original Mermaid text, syntax-highlighted.
- **Copy PNG / `⌘C`**, **Save PNG / `⌘S`**: export the diagram only.
- **Esc** or click outside to close (configurable in Settings).

### Settings

Open via `qmmd` (no input) or the menu-bar icon → **Settings**. Configure the
default theme, default zoom, background color, the global shortcut, and whether
the panel closes when it loses focus. A live preview reflects your choices.

## Release

### GitHub Actions

Actions → **Release** → **Run workflow**. Inputs:

- `bump`: `patch` (default) / `minor` / `major` — increments from the latest tag.
- `version`: an explicit version (e.g. `1.2.0`); overrides `bump`.

The workflow injects the version, builds the dmg, commits the version bump,
pushes a `vX.Y.Z` tag, and creates a GitHub Release with the dmg attached.

### Local

```bash
./release.sh 1.2.0            # set version + build dmg
./release.sh 1.2.0 --publish  # also create the GitHub Release
```

## How it works

Native AppKit menu-bar app (no third-party dependencies). Diagrams render in a
`WKWebView` using a vendored Mermaid v10 build (`Resources/mermaid.min.js`).
PNG export rasterizes the SVG off-screen at natural size, so the result is the
diagram only — independent of on-screen zoom/scroll.

| File | Role |
|------|------|
| `Sources/QuickMermaid/main.swift` | Entry point; mode dispatch (`--stdin` / `--settings` / `--selftest`) |
| `AppDelegate.swift` | Menu-bar item, Services registration, CLI/Settings modes, global hotkey |
| `ServicesProvider.swift` | `renderMermaid` Services handler |
| `MermaidPanel.swift` | Floating panel, render, copy/save PNG |
| `HotkeyManager.swift` | Carbon global hotkey |
| `SelectionReader.swift` | Selection → clipboard source resolution |
| `Settings.swift` / `SettingsWindow.swift` | Preferences (UserDefaults) + window |
| `L10n.swift` | Native string localization |
| `Resources/renderer.html` | Mermaid loader, render, zoom/pan, source view, i18n |
| `build.sh` / `release.sh` | Build, package, release |
| `tools/make-icon.*` | Generate the app icon |

## Limitations

- Unsigned / not notarized — intended for personal use; Gatekeeper warns on first launch.
- Very large diagrams: Mermaid limits are raised (`maxTextSize`, `maxEdges`); beyond them the error view explains why. PNG export is capped at ~8192 px.

## License

[MIT](LICENSE)
