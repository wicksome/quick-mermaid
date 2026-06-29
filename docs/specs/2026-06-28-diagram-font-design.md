# QuickMermaid — Diagram Font Setting (Design)

Date: 2026-06-28

Let the user pick a **font family** for diagram text, configured in Settings, applied
to both Mermaid and PlantUML renders. This is a *viewer* preference — it changes how
the rendered diagram text looks, not the source.

## Goal & scope

- One setting: **font family** for diagram text. No font size, weight, or per-element
  fonts (YAGNI — the request is "specify the font").
- Applies to the **diagram only**. The source-view overlay stays monospace (it shows
  code, not diagram text).
- Default = `"default"` → no override; each engine uses its built-in font. Existing
  behavior is preserved bit-for-bit when the user never touches the setting.
- Offline-only: the font list is the **system-installed** families
  (`NSFontManager.shared.availableFontFamilies`). No network/web fonts. A font WKWebView
  can't resolve simply falls back — same as any missing CSS font.

## Why two different application paths

Both engines are told the font *right before* rendering; only the delivery differs,
because the engines compute text layout differently:

| Engine | How font is applied | Layout correctness |
|--------|---------------------|--------------------|
| **Mermaid** | `mermaid.initialize({ fontFamily })` config (verified: `mermaid.render()` takes no font arg; font is a config option, propagated to SVG `<style>` + per-diagram fonts) | Mermaid measures text via the live DOM, so boxes re-fit the chosen font — no overflow |
| **PlantUML** | Inject `skinparam defaultFontName "<font>"` into a **copy** of the source, right after the `@start…` line | Engine lays out with its own metrics, so it must be *told* the font to size boxes correctly. A client-side SVG `font-family` swap would mis-size boxes → text overflow. So skinparam, not post-processing. |

## Data & settings

`Settings.swift`:
- New key `kFont = "fontFamily"`, property `fontFamily: String`.
- Default `"default"`.
- **Validated on read** (injection defense, mirrors `backgroundColor`'s hex check):
  the stored value must be `"default"` or a member of
  `NSFontManager.shared.availableFontFamilies`; otherwise fall back to `"default"`.

## Renderer (`renderer.html`)

- Extend the contract: `window.render(code, theme, zoomPercent, bg, lang, font)`.
  `font` is last so existing direct callers (tests/history) that omit it still work
  (treated as `"default"`).
- **Mermaid**: in `doRender()`'s `mermaid.initialize({...})`, add `fontFamily: font`
  only when `font && font !== 'default'`; otherwise omit the key (keep Mermaid's
  default).
- **PlantUML — generalized preamble injection** (designed for reuse, e.g. a future
  footer setting which is also a post-`@start` line):
  - `pumlPreamble(opts)` → returns an array of directive lines from settings. Now:
    `font && font !== 'default'` → `['skinparam defaultFontName "<font>"']`, else `[]`.
    Future footer adds one more line to this array — nothing else changes.
  - `injectAfterStart(code, lines)` → inserts `lines` immediately after the first line
    matching `/^\s*@start\w+/i`. No `@start` → returns code unchanged (best-effort).
  - Applied to the **engine copy only**, in `doRenderPlantUML()` and
    `renderPlantUMLToString()` (history thumbnails), so thumbnails and the main diagram
    share the font. `lastCode` (what the source view shows) is never mutated.

## Swift call sites

- `MermaidPanel.swift` and `SettingsWindow.swift` both build `window.render(...)`.
  Add the `font` argument, **JSON-encoded** like the diagram body
  (`\(json)`), because family names contain spaces and rarely an apostrophe —
  JSON-encoding closes the quote-break / injection gap.
- `MermaidPanel`: pass `selfTestMode ? "default" : Settings.fontFamily`.
- `SettingsWindow` preview: pass `Settings.fontFamily`.

## Settings UI (`SettingsWindow.swift`)

- Add `fontPopup: NSPopUpButton` in the Appearance tab, same layout pattern as
  `themePopup`.
- First item = localized "Default" mapping to `"default"`; then the sorted
  `availableFontFamilies`. Select the current `Settings.fontFamily`.
- `fontChanged` action → save → re-render the live preview → post the settings-changed
  `DistributedNotification` (same path as theme/background).
- `L10n.swift`: add `settings.font` label (en/ko). `renderer.html` needs no new web
  strings (the font value is data, not a UI string).

## Verification gate

1. `window.__test` cases: font arg → Mermaid `initialize.fontFamily`; font arg →
   PlantUML `skinparam defaultFontName`; `"default"` → neither injected; **source view
   shows the original (no injected directive leaks)**; history thumbnail uses the same
   injected copy. `--test` must report `failed:[]`.
2. `./build.sh --selftest` → `SELFTEST PASS`.
3. **Cannot be verified headlessly — needs user confirmation (stated explicitly):**
   the chosen font actually appears in the rendered diagram; the Settings dropdown +
   live preview update; PlantUML with a spaced font name (`Helvetica Neue`) — confirm
   quoting works and note any diagram types where `skinparam` has no effect
   (json/yaml/ditaa, etc.) as a documented limitation.

## Docs

- `docs/specs/behavior.md`: add font behavior + "must never" (don't leak the injected
  directive into the source view; `"default"` preserves prior behavior).
- `README.md`: document the font setting.

## Future extension (note, not in scope)

The PlantUML `injectAfterStart` helper + `pumlPreamble` array is the seam for a future
"footer" setting (`center footer © … All Rights Reserved.`) — also a post-`@start`
directive. Font is its first consumer.
