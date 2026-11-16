---
name: secret-scan
description: Scan the repository and its git history for committed credentials with gitleaks (built-in fallback), write a dated redacted report, and say what to rotate and where each secret should live instead.
version: 0.4.0
argument-hint: "[--no-history]"
allowed-tools: Read, Glob, Grep, Bash, PowerShell
---

# Secret scan

Finds credentials that were committed — now or ever — and turns each into a decision: rotate,
move, or accept as a false positive.

**Never print, quote or read back a secret value.** The script redacts its output. Do not
`Read` a flagged line to look at what was matched, and do not paste a match into the
conversation: the conversation is not a safe place for a credential either.

## Run

Read `.claude/alrig.json` for `security.reportsDir`. Then, with `pwsh` when it exists, else
`powershell.exe`:

```
<ps> -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Invoke-SecretScan.ps1" -Root <repo root> [-ReportDir <security.reportsDir>] [-NoHistory]
```

- **The working tree and the history are both scanned by default** — the tree for uncommitted
  and untracked work, the history because a secret deleted in a later commit is still published
  to everyone with a clone. Each finding's `inTree` says which. Pass `-NoHistory` only when
  `$ARGUMENTS` says `--no-history`, and say that the result covers the working tree only.
- **Configuration**: the repository's own `.gitleaks.toml` when it exists — the project wins —
  else the one shipped with this plugin (gitleaks' defaults plus Business Central AL rules).
  Accepted false positives go in the repository's `.gitleaksignore`, by fingerprint.
- **The report** is written only when `security.reportsDir` is set and the directory exists.
  The script never creates it. When it is `null`, write nothing and say a dated report needs
  one, which `/alrig:scan` can record. Suggest the directory is git-ignored: the report is
  redacted, but it is still a map of where credentials were.

When `engine` is `builtin`, gitleaks is not installed. Say so first and plainly: the fallback
has fewer rules and **no history**, so a clean result from it is weak evidence. Name the fix —
install gitleaks (`winget install gitleaks`, `choco install gitleaks`, `brew install gitleaks`,
or a release binary) — and do not install it yourself.

## Triage each finding

For each, say which of these it is. Decide from the rule, the file and the commit — not from
the value.

| Case | What to tell the user |
|---|---|
| **In the current tree** (`inTree: true`) | Rotate the credential, then move it (below), then remove it. In that order: removal without rotation leaves a working key in the history. |
| **History only** (`inTree: false`) | Still published. Rotate it. Rewriting history (`git filter-repo`) is the user's call and needs every clone re-fetched; never suggest it as a substitute for rotating. |
| **A test or sample value** | Confirm with the user. If it is fake, it belongs in `.gitleaksignore` by fingerprint — the user adds it, with a reason. |
| **A generated or downloaded file** | `.alpackages`, `.app`, `.g.xlf` are allowlisted by the shipped config; anything similar is reported for the user to decide. |

Never decide on your own that a finding is a false positive and drop it from the report.

## Where each kind of secret belongs

This is key management, and it is the half of the answer that stops the next leak:

- **A credential a Business Central app uses at run time** — in `IsolatedStorage`, written
  with `SetEncrypted` and keyed by a `Guid` field on a setup table, never in a table field
  itself. Held in `SecretText` (runtime 12.0 and later) from the moment it is read; otherwise in
  `[NonDebuggable]` procedures. The `integration` theme of `al-conventions` has the detail.
- **A publisher-owned secret an AppSource app needs** — the app's Azure Key Vault
  (`keyVaultUrls` in `app.json`), read through the App Key Vault module. Never in source,
  never in `app.json`.
- **A secret the build or deployment needs** — the CI system's secret store: GitHub secrets
  for AL-Go, a variable group or Key Vault link for Azure Pipelines. Never in `.AL-Go`
  settings, `launch.json` or a script.
- **A developer's own credential** — their machine. `launch.json` and `.vscode/` are
  git-ignored in most AL repositories for this reason; if they are tracked here, say so.

## Report

```
ENGINE      gitleaks <version> | builtin (no history — install gitleaks)
SCOPE       working tree + git history | working tree only
CONFIG      <repository .gitleaks.toml | alrig default>
FINDINGS    <n>
  <rule>  <file>:<line>  <commit | working tree>  → <rotate+move | history: rotate | confirm fake | generated>
REPORT      <path> | not written — security.reportsDir is null
NEXT        <the credential to rotate first, and why that one>
```

Order findings with anything in the current tree first, then the most recent history.

This skill writes the report and nothing else. It never edits a file to remove a secret,
never rewrites history, and never edits `.gitleaksignore`.
