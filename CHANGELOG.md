# Changelog

Versions follow the `version` field in `plugins/alrig/.claude-plugin/plugin.json`. Claude Code
offers an update only when that field changes, so every release bumps it.

## 0.4.0

Code scanning, ruleset enforcement and credential handling.

- **`/alrig:al-scan`** compiles each app with every analyzer the project declares (CodeCop,
  AppSourceCop, UICop, PerTenantExtensionCop, and third-party ones such as LinterCop or ALCops
  by path) under its ruleset, and reports every diagnostic grouped by rule. It resolves the
  ruleset's include chain and blocks on a rule lowered below `security.rulesetBaseline`, an
  include that does not resolve, a `generalAction` that silences, or a blanket `#pragma`.
- **`/alrig:secret-scan`** runs gitleaks over the working tree and history with redacted output
  (the repository's `.gitleaks.toml` wins over the shipped AL rules), triages each finding, and
  says where the secret belongs. Without gitleaks a built-in scan runs and says it is weaker.
- **`/alrig:release-check`**: version bump and identity against the last release, ID ranges and
  duplicates, XLIFF completeness, and secret handling (`SecretText`, `[NonDebuggable]`,
  `IsolatedStorage.SetEncrypted`, no secrets in table fields or `app.json`), plus both scans.
- **Write guard**: a `PreToolUse` hook blocks a credential literal or a non-allowlisted endpoint
  from being written into an `.al` file. Non-AL writes exit before PowerShell starts; the guard
  fails open.
- **Profile schema 3** adds `security`: `urlAllowlist`, `rulesetBaseline`, `reportsDir`. A
  rescan proposes them and asks.
- `tests/lint.mjs` checks that every script the hook and skills name exists, and applies the
  no-customer-content rule to scripts and configuration too.
- `tests/lint.mjs` also checks that the write guard's secret rules and the shipped
  `gitleaks-al.toml` agree, so neither can gain a rule the other lacks.
- **`tests/scripts.test.ps1`** executes the hook and every script against known inputs, and
  CI runs it on Linux with PowerShell 7 and gitleaks, and on Windows PowerShell 5.1 without.
- CI pins the Claude Code CLI it validates with.

Fixes from the 0.3.0 review.

- **Verdicts:** `BLOCKED` now outranks `UNVERIFIED`, so a `forbidden` hit or unmet criterion is
  no longer hidden on a repository with no build. Every verdict carries a `NEXT` line.
- **Build loop:** at most five builds after the baseline (sooner on two identical results). A
  failing baseline build stops stage 2 with `BASELINE FAILED` before any edit. Warnings are
  matched by file, rule and message, without line numbers. Pre-existing working-tree changes
  are treated as baseline.
- **`/alrig:check`** compares warnings on the lines the diff touched when there is no stage 2
  baseline, instead of always returning `UNVERIFIED`.
- **`/alrig:go`:** triage runs inside the spec stage. LOW and MEDIUM no longer stop for a
  separate confirmation, and the design skill loads only on HIGH. `--quick` still checks for
  HIGH signals. A "no" at a gate revises and re-presents; "stop" prints how to resume.
  An empty repository stops with a pointer to `/alrig:new`. A malformed profile stops every
  stage with the parse error.
- **Spec:** a new `AUTHORITY` line names the project documents that override the baseline, and
  stages 2 and 3 apply it. A `null` or missing `specs.dir` falls back to an inline contract.
- **Tokens:** stage 2 and 3 rules moved to `references/` files, read only on the customisation
  tier — the product tier no longer loads them alongside the agents. Descriptions are cut to
  one line each.
- **Detection:** legacy `idRange`/`appId` keys, AL-Go `testFolders` and `"type": "AppSource
  App"`, a prefix per app, Azure DevOps pipelines outside the root, build scripts one directory
  down, a warning on `Run-AlPipeline`, the AL MCP server at local scope, and no plain `docs/`
  fallback for specs. A one-app build argument in a multi-app repo becomes `{app}` (the
  `multi-app-product` golden profile is corrected).
- **AL baseline:** runtime tags on partial records (6.0), `ErrorInfo` details and collectible
  errors (8.0) and `actionref` (10.0). New per-row error isolation: `Codeunit.Run`, its
  `Commit`, and `TryFunction` limits. `ModifyAll`/`DeleteAll` fall back to row-by-row when
  subscribers exist.
- README: what `/alrig:mcp` needs beforehand, and an accurate idle cost.

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
