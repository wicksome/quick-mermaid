# CLAUDE.md

Project guidance for Claude Code. The canonical instructions live in
[`AGENTS.md`](AGENTS.md) — read it.

@AGENTS.md

## Claude Code notes

- Use `Skill` / subagents for long, log-heavy steps (e.g. `swift build`) to keep
  the main context clean; report results back.
- The render-pipeline gate is `./build.sh --selftest` — run it after any change
  to Swift, `renderer.html`, or the bundle, and paste the `SELFTEST` line as
  evidence. GUI flows (panel, Services, shortcut, copy/save dialogs) can't be
  verified headlessly — say so explicitly and ask the user to confirm.
