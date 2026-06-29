# QuickMermaid — Behavior Spec

What the app **must do** and **must never do**, stated as observable behavior — not
how it's coded. When working on the renderer, treat this as a checklist: every item
must hold. (The automated enforcement is the `--test` suite; a behavior added here
without a matching test is unverified — add one.)

Scope: what happens once source text is being rendered/viewed. How text gets in
(shortcut, Services, CLI, clipboard) is in `README.md`.

---

## Must do

### Engine choice
- A diagram is rendered as **PlantUML** when its text starts with a PlantUML directive
  (`@startuml`, `@startmindmap`, …) **or** is fenced as ` ```puml `/` ```plantuml `.
  Everything else renders as **Mermaid**.
- An explicit fence label wins over the content: ` ```mermaid ` is Mermaid even if the
  body looks like PlantUML, and ` ```puml ` is PlantUML even if the body has no `@start`.
- A surrounding Markdown code fence is stripped before rendering; the diagram shows,
  not the fence.
- Both engines work fully **offline**, with no network at any point.

### Rendering
- Valid Mermaid and valid PlantUML (including diagrams that need graph layout, e.g.
  class diagrams) render to a diagram.
- While a render is in progress, the previous diagram is not treated as the current
  one (see "must never").
- Invalid source shows an error state; empty source shows an empty state.
- The toolbar shows which engine drew the current diagram and how long it took.

### Source view
- The user can toggle a view of the original source text, **syntax-highlighted for its
  language** (Mermaid or PlantUML).
- The source view toggles via the toolbar button **or the `/` key** — pressing `/` from
  the diagram opens it, pressing `/` again returns to the diagram.
- In the source view, **Copy copies the source text** (and the button/tooltip say so).
- In the source view, Save and the zoom controls are unavailable (they apply to the
  diagram, which isn't on screen).

### Diagram view
- Copy / Save export the **diagram image** (diagram only, full size regardless of zoom).
- Zoom (buttons, shortcuts, wheel, pinch) acts on the diagram.
- A **fit-to-window** control (and the **Space** key) re-fits the diagram to the current
  window size — e.g. after the user enlarges the window. It's disabled/inactive in the
  source and history views.

### History
- Recently rendered diagrams are listed, each with a thumbnail, an engine label, and
  the original first line.
- Reopening a history item renders it **exactly as it first rendered** — same engine,
  no failure, no relabeling.
- On hover, a row offers **copying that diagram as an image** (and deleting it) — copying
  stays in the history list, it does not navigate away.
- The user can delete history items.
- While history is open, the **source view is unavailable** — the source button is
  disabled and the `/` key is ignored (no single diagram is selected to show source for).

### Footprint
- Mermaid-only sessions never load the PlantUML engine; it loads on the first PlantUML
  render and not before.

### Font
- When a font family is configured (not "default"), diagram text renders in that font:
  Mermaid via its `fontFamily` config, PlantUML via an injected `skinparam defaultFontName`.
- "default" leaves each engine's built-in font — behavior identical to no setting.
- Only installed system fonts are selectable; a value that isn't installed falls back to "default".

---

## Must never (it's a bug if you observe this)

- **Rendering must never copy anything to the clipboard on its own.** The clipboard
  changes only when the user explicitly copies. (Triggering a render — especially via
  the shortcut, especially on a reused window — must not auto-fire a copy.)
- **A toolbar control must never describe or perform an action that doesn't match the
  current view** — e.g. the Copy tooltip saying "copy image" while in the source view
  where it copies code, or zoom appearing usable while viewing source/history.
- **Copy/Save must never export the *previous* diagram while a new one is rendering**,
  and the engine/time readout must never show the previous diagram's values for the
  one being rendered.
- **A diagram that rendered once must never fail to reopen, or reopen mislabeled /
  as the wrong engine,** from history.
- **The engine/time readout must never be shown when no diagram is on screen** (empty,
  error, or while an overlay covers the diagram).
- **Copying in the source view must never put an image on the clipboard** (it must be
  the text); copying in the diagram view must never put text instead of the image.
- **Opening history must never pull in the heavy PlantUML engine** just to draw a
  thumbnail; a not-yet-loadable PlantUML thumbnail shows a neutral marker instead.
- **Nothing may be fetched from the network** to render, ever.
- **A stuck state is a bug**: a render that fails, errors, or times out must always
  resolve to a diagram or a clear empty/error state — never a blank or spinning view.
- The font is applied to the diagram only. The source view must show the **original**
  source — the injected `skinparam defaultFontName` (or any preamble directive) must
  never appear in the source overlay or in the copied source text.
