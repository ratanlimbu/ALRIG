---
name: release-check
description: Pre-release gate for a Business Central app — version bump, app.json identity, ID ranges, XLIFF, secret handling (SecretText, NonDebuggable, IsolatedStorage), analyzers and ruleset. Reports a verdict; writes nothing.
version: 0.3.0
argument-hint: "[app path, or omit for every non-test app] [--base <git ref>]"
allowed-tools: Read, Glob, Grep, Bash, PowerShell
---

# Release check

The things that are cheap to fix before a version ships and expensive after: a version that
did not move, an app `id` that did, an object outside its range, a translation nobody
regenerated, a credential held where a debugger or a table export can see it.

**It writes nothing.** Not the version bump, not the translation, not the fix. Every finding
names the file and line and what would resolve it; the human or `/alrig:go` makes the change.

## Inputs

Read `.claude/alrig.json`. Scope: the app path in `$ARGUMENTS`, else every app with
`isTest: false`, in `dependsOn` order. `--base <ref>` sets what this release is compared to;
otherwise the script uses the last tag, then `origin/main`, then `main`.

Run each script with `pwsh` when it exists, else `powershell.exe`, always as
`<ps> -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/<script>"`.

## 1 — Mechanical checks

`"${CLAUDE_PLUGIN_ROOT}/scripts/Invoke-ReleaseCheck.ps1" -AppPath <app> [-BaseRef <ref>]` returns
one section per check, each `OK`, `GAP` or `UNVERIFIED`. Interpret them — the script cannot
make these calls:

- **version** — must be greater than the base. Equal is a `GAP`: the platform will not
  upgrade a tenant to the same version. `UNVERIFIED` on a first release is expected; say so.
- **identity** — a changed `id` is a different app to every tenant that has this one
  installed, and is almost never intended. A changed `name` or `publisher` breaks every app
  that depends on this one. Both block.
- **manifest** — which missing fields matter depends on the profile's `appsource.target`:
  for `appsource` every field listed matters (and `/alrig:appsource` has the full submission
  checklist); for `pte`, only `id`, `name`, `publisher`, `version`, `application`, `runtime`
  and `idRanges` do. Report the rest as advisory, never as blocking.
- **idRanges** — every object outside a range, and every duplicate, blocks. Report usage per
  range too; one nearly full is worth saying.
- **xliff** — `UNVERIFIED` when `TranslationFile` is on and no `.g.xlf` exists: the app has
  not been built since. Missing or untranslated units in a target language are a `GAP` the
  project decides on; obsolete units are noise unless there are many.
- **secrets** — see section 2.

## 2 — Secret handling and key management

From the `secrets` section. **Blocking**: `hardcoded` (a credential literal in source),
`manifestSecrets`, and `secretTableFields` (a credential stored in a table field, where a
configuration package or a table export can read it).

**Advisory, with the fix named**:

- `heldAsText` — a secret-named variable or parameter typed `Text`/`Code`. With
  `secretTextAvailable` (runtime 12.0+), the fix is `SecretText`. Without it, `[NonDebuggable]`
  on every procedure that holds it.
- `procedureWithoutNonDebuggable` — a procedure taking a secret as `Text` without
  `[NonDebuggable]`; the debugger shows its value to anyone allowed to attach.
- `isolatedStorageSetNotEncrypted` — `IsolatedStorage.Set` on what looks like a secret; the fix
  is `SetEncrypted` (or the `SecretText` overload).
- `authorizationHeaders` — check each passes its value through the `SecretText` overloads,
  never through `Text`; the `integration` theme of `al-conventions` has the detail.
- `hardcodedUrls` — an endpoint outside `security.urlAllowlist`. It belongs in a setup table.
- `suppressions` — every `alrig:allow-secret` / `alrig:allow-url` marker. List each one with its
  reason; a suppression without a reason is itself a finding.

Names are a heuristic. A field named `Token Expiry` is not a secret, and one named `Value` may
be. Say when a finding looks like a false positive rather than dropping it.

## 3 — Analyzers, ruleset and committed secrets

Run the scripts behind the two scans directly, once per app and once per repository:

- `${CLAUDE_PLUGIN_ROOT}/scripts/Invoke-AlScan.ps1` then
  `${CLAUDE_PLUGIN_ROOT}/scripts/Test-AlRuleset.ps1`, as in `alrig:al-scan`. Analyzer
  **errors** and a **blocking** ruleset finding block the release; warnings are counted, not
  blocking. Missing symbols make it `UNVERIFIED`; tell the user to download them, and do not.
- `${CLAUDE_PLUGIN_ROOT}/scripts/Invoke-SecretScan.ps1 -Root <repo>`, **without** `-ReportDir`
  — this skill writes nothing, so the dated report is `/alrig:secret-scan`'s job. A finding with
  `inTree: true` blocks; `inTree: false` (history only) is reported with "rotate" and does not
  block a release that no longer contains it.

Summarise each in one or two lines here; the user can run `/alrig:al-scan` or
`/alrig:secret-scan` for the full detail.

## Verdict

- `BLOCKED` — any blocking item above. List every one.
- `UNVERIFIED` — nothing blocks, but a check could not run: no compiler or symbols, no base
  version, no `.g.xlf`. Say which, and what running it would take.
- `READY` — every check ran and nothing blocks. Advisories are still listed in full.

`BLOCKED` outranks `UNVERIFIED`: a known problem is reported even when another check could not
run.

```
APP          <name> <version> (<path>) vs <base ref, previous version>
VERSION      OK | GAP — <detail>
IDENTITY     OK | GAP — <field: previous → current>
MANIFEST     OK | GAP — <missing fields, blocking ones first>
ID RANGES    OK | GAP — <outside / duplicates>; usage <range: used/size>
XLIFF        OK | GAP | UNVERIFIED — <per language: missing, untranslated>
SECRETS      OK | GAP — <blocking, then advisory, each file:line and the fix>
ANALYZERS    <status> — errors <n>, warnings <n>; ruleset <clean | findings>
COMMITTED    <n in tree, n in history> | engine builtin (weak)
VERDICT      READY | BLOCKED | UNVERIFIED
NEXT         <the first thing to do>
```
