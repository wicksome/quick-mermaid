# AGENTS.md

Guidance for AI agents working on **QuickMermaid**. This project is developed
primarily by AI; keep it coherent, simple, and easy for the next agent to reason
about. Read this before making changes.

## What this is

A macOS menu-bar app that renders selected/clipboard/piped **Mermaid source text**
into a diagram in a floating quick-look panel. It is a *viewer*, not an editor.
See `README.md` for user-facing docs and `docs/specs/` for design notes.

## Core principles

- **Zero third-party dependencies.** Native AppKit + WebKit only. Mermaid is
  vendored at `Resources/mermaid.min.js`. Do not add SwiftPM/CocoaPods deps or
  load anything from the network at runtime.
- **Offline.** Everything must work with no network.
- **No Xcode IDE.** Build from the CLI only (`build.sh`). Do not introduce an
  `.xcodeproj` or require opening Xcode.
- **Keep it small.** Prefer the simplest thing that works over abstraction.

## Build, run, verify

```bash
./build.sh             # build QuickMermaid.app (swift build + hand-assembled bundle)
./build.sh --dmg       # + QuickMermaid.dmg
./build.sh --selftest  # build, then headless render-pipeline check (MUST stay green)
./build.sh --install   # install to /Applications + put qmmd on PATH + launch
```

**Always verify before claiming done:**
1. `./build.sh --selftest` must print `SELFTEST PASS`. This loads `renderer.html`
   in an offscreen WKWebView and renders a sample diagram — it is the regression
   gate for the render pipeline.
2. For changes to triggers/UI, also confirm the relevant process stays alive and
   doesn't crash (e.g. `printf 'graph TD\n A-->B\n' | ".../QuickMermaid" --stdin`).
3. **GUI behavior cannot be verified headlessly** (Services menu, the floating
   panel, copy/save dialogs, the global shortcut, accessibility prompts). State
   clearly what you verified vs. what needs the user to confirm. Never claim a
   GUI flow works without saying it is unverified.

Run long/log-heavy builds via a subagent when possible to keep the main context clean.

## Architecture (where things live)

| File | Responsibility |
|------|----------------|
| `Sources/QuickMermaid/main.swift` | Entry; mode dispatch via args (`--stdin`, `--settings`, `--selftest`, else service) |
| `AppDelegate.swift` | Menu-bar item, Services registration, CLI/Settings modes, global hotkey wiring + Accessibility prompt |
| `ServicesProvider.swift` | `@objc renderMermaid` Services handler |
| `MermaidPanel.swift` | Floating `NSPanel` + `WKWebView`; render injection; PNG copy/save via offscreen SVG render |
| `HotkeyManager.swift` | Carbon `RegisterEventHotKey` global shortcut |
| `SelectionReader.swift` | Source resolution: selection (synthesized ⌘C) → clipboard → nil |
| `Settings.swift` | `UserDefaults`-backed prefs (theme, zoom, background, shortcut, closeOnFocusLoss) |
| `SettingsWindow.swift` | Native settings window + live preview WebView |
| `L10n.swift` | Native string localization table |
| `Resources/renderer.html` | Mermaid loader, render, zoom/pan, source view, PNG export data, web i18n |
| `build.sh` / `release.sh` | Build/package/release |
| `.github/workflows/release.yml` | CI release (version bump → dmg → tag → GitHub Release) |
| `tools/make-icon.*` | Generate `Resources/AppIcon.icns` |

### renderer.html contract (Swift ↔ JS)

- Swift calls `window.render(code, theme, zoomPercent, bg, lang)`.
- Swift posts to message handlers: `result` (selftest), `copyPNG`, `savePNG`.
- JS calls back `window.copied()` / `window.saved()` after Swift confirms the action.
- `window.exportData()` returns `{svg, w, h, bg}` for diagram-only PNG export.
- `#preview` in the URL hash hides the toolbar (used by the Settings preview).
- Mermaid runs with `suppressErrorRendering: true`; the app draws its own
  empty/error states and `cleanupOrphans()` removes stray nodes Mermaid appends.
  **Do not re-enable Mermaid's default error graphic** (it caused a persistent
  "Syntax error" bomb overlay).

## Conventions

- **Localization:** user-facing strings are localized (en/ko, system-driven,
  English fallback). Add native strings to `L10n.swift`'s table and web strings
  to the `I18N` object in `renderer.html` — keep both `en` and `ko`. Never
  hardcode a user-facing string in a single language.
- **Comments and docs are in English.** (Localized `ko` *values* in the i18n
  tables are intentional data — leave them.)
- **PNG export = offscreen SVG render** (diagram only, full size regardless of
  on-screen zoom). Do not revert to snapshotting the visible WebView.
- The app is `.accessory` / `LSUIElement` (menu-bar only, no Dock icon).
- Bundle id is `me.wickso.quickmermaid` — reverse-DNS of the `wickso.me` domain (not a typo of the `wicksome` org). Changing it resets `UserDefaults`.

## Known gotchas

- **Services menu is cached by the consuming app at launch.** A newly registered
  service won't appear until that app is relaunched (or `pbs -update`). **Chrome
  does not show the Services submenu** in its right-click menu — the global
  shortcut is the universal trigger.
- **Global shortcut needs Accessibility permission** (it synthesizes ⌘C to grab
  the selection). The app prompts when the shortcut is enabled.
- **Unsigned / ad-hoc signed.** Gatekeeper warns on first launch; document the
  `xattr -dr com.apple.quarantine` / right-click-open workaround. Full
  auto-update (Sparkle) is out of scope unless signing/notarization is added.
- Settings can be changed from a separate process (`qmmd --settings`); the
  resident app re-reads them via a `DistributedNotification` to re-register the hotkey.

## Git conventions

- **Commit messages in English**, gitmoji style (e.g. `✨ ...`, `🐛 ...`, `📝 ...`).
- **Do NOT add AI/Claude/Co-Authored-By attribution** to commit messages — the
  history is kept attribution-free by choice.
- Don't `git push --force` without explicit user confirmation.
