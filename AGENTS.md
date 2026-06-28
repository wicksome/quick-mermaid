# AGENTS.md

Guidance for AI agents working on **QuickMermaid**. This project is developed
primarily by AI; keep it coherent, simple, and easy for the next agent to reason
about. Read this before making changes.

## What this is

A macOS menu-bar app that renders selected/clipboard/piped **Mermaid source text**
into a diagram in a floating quick-look panel. It is a *viewer*, not an editor.
It also renders **PlantUML** (`@startuml…@enduml` and other `@start…` diagrams),
auto-detected and routed to a vendored offline PlantUML engine. Mermaid remains
the primary focus — this is not a PlantUML tool.
See `README.md` for user-facing docs, **`docs/specs/behavior.md` for the behavior
spec** — what the renderer must do and must never do, as observable behavior; treat it
as a checklist when changing the renderer and keep its "must never" list bug-free — and
`docs/specs/` for design notes. The `--test` suite is the spec's automated enforcement;
update the spec and a test together.

## Core principles

- **Zero third-party dependencies.** Native AppKit + WebKit only. Mermaid is
  vendored at `Resources/mermaid.min.js`; the PlantUML engine is vendored at
  `Resources/plantuml.js` (TeaVM build, ~7.6MB) + `Resources/viz-global.js`
  (Viz.js/Graphviz, ~1.4MB). Do not add SwiftPM/CocoaPods deps or load anything
  from the network at runtime. See "Vendoring the PlantUML engine" below before
  updating those two files.
- **Always vet licenses before vendoring.** Any open-source code added to the
  bundle must have its license checked and confirmed compatible with this project's
  MIT license *before* it ships — check the upstream source-of-truth (repo
  `LICENSE`/README, not just a website), since a project may be multi-licensed.
  Permissive (MIT/BSD/Apache-2.0) and weak/file-level copyleft in object form
  (EPL, LGPL) are fine; avoid strong copyleft (GPL) unless a permissive option is
  offered. Record every bundled component, its license, and any required notice in
  `THIRD-PARTY-LICENSES.md`, and ship that file inside the `.app`.
- **Offline.** Everything must work with no network.
- **No Xcode IDE.** Build from the CLI only (`build.sh`). Do not introduce an
  `.xcodeproj` or require opening Xcode.
- **Keep it small.** Prefer the simplest thing that works over abstraction.
- **Stay lightweight — treat weight as a signal.** This is a focused diagram
  *viewer*, not a Swiss-army app. When something grows — bundle/`.app` size, launch
  or render latency, memory, the number of vendored engines, or the breadth of
  features — stop and ask: *is the app doing too much? should this be split out
  (a separate mode, tool, or app) instead of piled on here?* Prefer cutting or
  extracting over accreting. A new capability earns its place only if it fits the
  "render selected diagram source" purpose and its cost is contained (e.g. lazy-load
  heavy engines so users who don't need them don't pay for them). **Signals to stop
  and reconsider — split or cut rather than accrete:**
  - Adding *another* multi-MB renderer (D2, native Graphviz, Excalidraw, …): a
    renderer-plugin split or separate builds beats one ballooning bundle.
  - Adding a capability that isn't "view a diagram from source" (editing, cloud,
    sharing, accounts): that belongs in a separate mode/app.
  - Perceptible launch/render latency or memory growth on the common path.

  Reassess weight on every heavy addition. Current baseline: `.app` ~13MB, almost all
  of it vendored JS (Mermaid ~3.2MB + the lazy-loaded PlantUML engine ~8.7MB); the
  Swift binary is ~330KB.

## Build, run, verify

```bash
./build.sh             # build build/QuickMermaid.app (swift build + hand-assembled bundle)
./build.sh --dmg       # + build/QuickMermaid.dmg
./build.sh --selftest  # build, then headless render-pipeline check (MUST stay green)
./build.sh --install   # install to /Applications + put qmmd on PATH + launch
```

Build artifacts land in `build/` (gitignored). `--install` copies to
`/Applications` and unregisters the `build/` copy from Launch Services so it
can't shadow the installed app as a duplicate Services provider.

**Always verify before claiming done:**
1. `./build.sh --selftest` must print `SELFTEST PASS`. This loads `renderer.html`
   in an offscreen WKWebView and renders a sample diagram — it is the regression
   gate for the render pipeline.
2. `build/QuickMermaid.app/Contents/MacOS/QuickMermaid --test` runs the renderer JS test
   suite (`window.__test` in `renderer.html`) offscreen and prints
   `TEST {"pass":N,"total":N,"failed":[]}` — exit 0 only when `failed` is empty.
   It covers render/empty/error states, the source overlay, and history. Add cases
   to `window.__test` when you touch the renderer; keep it green. The test cases are
   the executable form of `docs/specs/behavior.md` — keep the two in sync.
3. For changes to triggers/UI, also confirm the relevant process stays alive and
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
- **Engine routing + fence handling.** `window.render` runs `stripFence()` (strips a
  leading ` ```lang … ``` ` Markdown fence) then `detectEngine(lang, body)`: a
  ` ```puml `/` ```plantuml ` tag → PlantUML, ` ```mermaid ` → Mermaid, otherwise
  content (`isPlantUML` = `/^\s*@start\w+/i`) decides — so a fence tag overrides
  content. **Fence stripping lives in the renderer, not Swift** (`MermaidPanel.show`
  passes raw text), because the language tag must survive long enough to route.
  Both engines produce an SVG in `#diagram`, so zoom/pan, the source overlay, and
  `exportData()` (PNG export) are shared and engine-agnostic.
- **PlantUML is lazy-loaded.** `viz-global.js` then `plantuml.js` are injected via
  `<script>` only on the first PlantUML render (`ensurePlantUML()`), so Mermaid-only
  sessions never pay the ~9MB parse cost. The engine has no completion callback;
  `renderPlantUMLInto()` watches `#diagram` with a `MutationObserver` and settles on
  a quiet period (or a 15s timeout). On a syntax error PlantUML draws **its own**
  error graphic into the SVG — unlike Mermaid we can't suppress it (the engine is a
  black box), so a malformed PlantUML diagram resolves as a "successful" render
  showing PlantUML's error image. History thumbnails for PlantUML items are rendered
  offscreen (`renderPlantUMLToString`, cached by code) **only when the engine is
  already loaded** — opening history never pulls in the ~9MB engine just for a
  thumbnail; un-rendered rows show a neutral placeholder until the engine loads.
- **Toolbar readout.** After a successful render, `#meta` (next to the reset button)
  shows the engine (`Mermaid`/`PlantUML`) and render time via `setMeta()`; it's hidden
  on empty/error states. History rows show the same engine badge.
- **Source view is engine-aware.** `renderSource()` picks the highlighter by
  `activeEngine` (`highlight` for Mermaid, `highlightPlantUML` for PlantUML — a
  single-pass tokenizer so inserted spans aren't re-scanned). In the source view the
  toolbar adapts: Copy stays enabled and copies the source **text** (`copyText` →
  Swift writes it to the pasteboard), while Save and the zoom controls are disabled
  (they only apply to the diagram).

### Vendoring the PlantUML engine

`Resources/viz-global.js` is upstream **verbatim**. `Resources/plantuml.js` is the
upstream TeaVM build **with two mechanical transforms** — it is *not* byte-identical
to upstream. To update:

1. Download both from the canonical upstream — the `gh-pages` branch of
   `plantuml/plantuml`, dir `js-plantuml/`:
   `https://raw.githubusercontent.com/plantuml/plantuml/gh-pages/js-plantuml/{plantuml.js,viz-global.js}`
   (the `plantuml-for-github` extension ships the same `viz-global.js` and an older
   `plantuml.js`). The build is labeled **Beta** upstream.
2. Copy `viz-global.js` as-is.
3. Transform `plantuml.js`: replace the trailing ESM export and wrap the whole file
   in an IIFE so it loads as a classic script exposing only one global:
   ```sh
   { printf '(function(){'; \
     perl -0777 -pe 's/export\{C as render,D as renderToString\};?\s*$/globalThis.__puml={render:C,renderToString:D};/' plantuml.js; \
     printf '})();'; } > Resources/plantuml.js
   ```

**Why these transforms (do not "simplify" back to a plain `<script type="module">`):**

- Upstream loads `plantuml.js` as an **ES module** (`import { render }`). WKWebView
  loads `renderer.html` via `loadFileURL` (`file://`), and **ES-module imports over
  `file://` are blocked by CORS** ("Cross-origin script load denied"). So the module
  must become a classic script — hence the `export{…}` → `globalThis.__puml` swap.
- A classic script shares the page's **global scope**, and the TeaVM bundle declares
  hundreds of top-level globals (including a class named `L`) that would **clobber
  `renderer.html`'s own globals** (its i18n object is also `L`). The **IIFE wrapper**
  contains them so only `globalThis.__puml` leaks. (`viz-global.js` is UMD and already
  self-contained, so it needs no wrapper; `plantuml.js` reads it as the global `Viz`,
  so viz must load first.)
- The Graphviz layout in `viz-global.js` runs as **WebAssembly from an inline base64
  blob** (no external `.wasm` fetch). This works in WKWebView with no COOP/COEP /
  SharedArrayBuffer / custom headers — verified by rendering a class diagram (which
  needs the Graphviz path) offscreen via `file://`.

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
- **The selection-grab ⌘C can echo into the panel.** On a reused panel, the ⌘C
  synthesized by the shortcut may be delivered to our own WebView and would trigger
  the ⌘C-copies-PNG handler (auto-copying the diagram). `renderer.html` guards this
  by ignoring keyboard ⌘C for ~600ms after each `window.render` (`suppressKeyCopyUntil`);
  the copy button and a deliberate later ⌘C are unaffected.
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
