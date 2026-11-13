# Changelog

Versions follow the `version` field in `plugins/alrig/.claude-plugin/plugin.json`. Claude Code
offers an update only when that field changes, so every release bumps it.

## 0.3.0

- `/alrig:go --quick`: one approval at the contract; implement and review then run back to
  back and report diff, build, warning delta and verdict together. The stop after
  implementation returns when the contract hits a hotspot or stage 2 is `BLOCKED`.
- Commands are granted the `mcp__al__` tools their stage uses, so the customisation tier can
  build through Microsoft's AL MCP server from the main context.
- `/alrig:check` runs in the main context on every tier.
- README opens with *Start here*, and installs in one step on Claude Code 2.1.275 or later.
- Display name ALRIG; repository renamed to `ratanlimbu/alrig` (GitHub redirects the old name).
- Tests: the `tiny-pte` and `multi-app-product` fixtures now ship the `.vscode/` files their
  golden profiles depend on; a root `.gitignore` rule had kept them out. CI runs `lint.mjs`
  and validates both manifests.

## 0.2.0

- Renamed from `bp-al` to `alrig`: commands `/alrig:*`, profile `.claude/alrig.json`. `scan`
  offers to move an existing `.claude/bp-al.json`.
- `/alrig:new` scaffolds an app in an empty repository; defers to AL-Go's own workflow in AL-Go
  repositories.
- Microsoft's AL MCP server as a build provider, set up by `/alrig:mcp`.
- Profile schema 2: per-app target, runtime, application, in-repo `dependsOn`, AL-Go project,
  `build.provider`, `ci`. Multi-app builds run upstream first.
- `[Cloud]`/`[OnPrem]` and runtime applicability for baseline rules.
- Themes: privacy, reports, copilot.

## 0.1.0

- First release as `bp-al`: `scan`, `spec`, `implement`, `review`, `check`, `go`, `appsource`
  and `mcp`, with the AL baseline themes. The optional `design` stage followed within 0.1.0.
