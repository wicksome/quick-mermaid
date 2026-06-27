# QuickMermaid — Design Notes

Initial design: 2026-06-26. This doc captures the architecture and the key
decisions; see the README for usage.

## Goal

Render Mermaid *source* text into a diagram with minimal friction, from any app
— so diagrams handed to you as text (e.g. by an LLM in a terminal, a code
review, or a doc) can be viewed in place without switching to an editor or a web
tool. It is a quick-look viewer, not an editor.

## Triggers

Three independent ways to render, all sharing one source-resolution rule:

1. **System Services** (`right-click → Services → Render Mermaid`) — the OS hands
   the selected text to the app's handler. Works in apps that expose selections
   to Services (Safari, TextEdit, Terminal, iTerm2, …). No Accessibility
   permission needed. Chrome does not show the Services submenu in its context
   menu, so use the shortcut there.
2. **Global keyboard shortcut** (Carbon, default `⌃⌘M`) — works in any app. It
   grabs the selection by synthesizing `⌘C`, which requires Accessibility
   permission.
3. **CLI `qmmd`** — `pbpaste | qmmd`, `qmmd file.mmd`, or `qmmd` (no input) to
   open Settings. Bypasses the Services cache entirely.

### Source-resolution priority

Selection → clipboard → nothing. The panel only opens when there is renderable
text; empty / non-text input shows nothing. Success or failure is then conveyed
inside the panel.

## Rendering

- A `WKWebView` loads a vendored Mermaid v10 build (`Resources/mermaid.min.js`),
  so rendering is fully offline.
- `suppressErrorRendering` is on; the app draws its own empty/error states
  instead of Mermaid's default error graphic, and cleans up any stray nodes
  Mermaid appends to the document.
- `maxTextSize` / `maxEdges` are raised so large diagrams render; beyond the
  limits the error view explains why.

## PNG export

Copy/Save extract the diagram SVG and rasterize it off-screen at natural size in
a separate `WKWebView`. The result contains the diagram only (no toolbar, no
whitespace) and the full diagram regardless of on-screen zoom/scroll. Output is
capped at ~8192 px.

## Settings

Stored in `UserDefaults` (shared across the resident app and transient CLI
instances via the bundle id). Theme, default zoom, background color, the global
shortcut, and close-on-focus-loss. The Settings window shows a live preview.
Cross-process changes (e.g. from `qmmd --settings`) notify the resident app via
a `DistributedNotification` so it can re-register the hotkey.

## Localization

English and Korean, chosen from the system language (English fallback). Native
strings live in `L10n.swift`; web strings in the `I18N` table in `renderer.html`.

## Packaging

- Built entirely from the CLI (`build.sh`) — no Xcode IDE. `swift build`, then a
  hand-assembled `.app` bundle, ad-hoc signed, optionally packaged into a `.dmg`.
- Unsigned / not notarized — personal use; Gatekeeper warns on first launch.
- Releases are automated via GitHub Actions (`.github/workflows/release.yml`):
  version bump → dmg build → tag + GitHub Release.

## Out of scope (for now)

Code signing / notarization, Sparkle-style auto-update, in-app update download.
