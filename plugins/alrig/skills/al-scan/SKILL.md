---
name: al-scan
description: Compile AL apps with every code analyzer the project runs (CodeCop, AppSourceCop, UICop, PerTenantExtensionCop, LinterCop/ALCops) under its ruleset, check the ruleset was not weakened, and summarise. Read-only.
version: 0.3.0
argument-hint: "[app path, or omit for every app in the profile]"
allowed-tools: Read, Glob, Grep, Bash, PowerShell
---

# Analyzer scan

A full inventory of what the analyzers say about an app **as it stands**, and whether the
ruleset that decides their severity is still the one the project agreed to.

This is not the warning gate. Stage 2 and `/alrig:check` compare warnings before and after a
change, because a brownfield repository's existing warnings are not the change's fault. This
scan reports all of them — it is what you run before a release, when adopting the plugin, or
when someone asks how much debt is in an app.

**It writes nothing in the repository and fixes nothing.** It reports.

## Inputs

Read `.claude/alrig.json`. Without it, run on the path given and say the profile is missing —
there is then no `security.rulesetBaseline`, so ruleset enforcement reports only what the
ruleset says about itself.

Scope: the app path in `$ARGUMENTS`, else every app in `apps[]`, in `dependsOn` order.

## 1 — Compile with the analyzers

The scripts are PowerShell and run on Windows PowerShell 5.1 or PowerShell 7. Use `pwsh` when
it exists, else `powershell.exe`, always with `-NoProfile -ExecutionPolicy Bypass -File`:

```
<ps> -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Invoke-AlScan.ps1" -AppPath <app>
```

With no `-Analyzers`, the script uses the app's `.vscode/settings.json` (`al.codeAnalyzers`),
then the repository root's — which is where third-party analyzers such as LinterCop or ALCops
are declared, by path. When neither declares any, pass the profile's `analyzers` list:
`-Analyzers CodeCop,UICop,PerTenantExtensionCop`. **Never download an analyzer** the project
does not already have; name it as a gap instead.

The ruleset comes from `al.ruleSetPath` the same way; `-RuleSet` overrides it.

`status` in the output:

- `OK` / `ERRORS` — it compiled (or failed to, with the errors listed); every count is real.
- `UNVERIFIED` — no compiler, no symbols, or an unreadable `settings.json`. Report the
  `reason` verbatim. For missing symbols, tell the user to download them (VS Code: *AL:
  Download Symbols*) and rerun — **do not download them yourself**: that writes `.alpackages`
  into the app, which this read-only skill may not do.
  **An unverified scan has no counts** — never report zero findings for it.

`missing` lists analyzers or a ruleset that settings named but the disk does not have. Each one
is a check the developer believes is running and is not; report it before any finding.

## 2 — Ruleset enforcement

When a ruleset is in use:

```
<ps> ... -File "${CLAUDE_PLUGIN_ROOT}/scripts/Test-AlRuleset.ps1" -RuleSet <path> -Root <app> [-Baseline <security.rulesetBaseline>]
```

It follows `includedRuleSets`, computes each rule's effective action, and flags:

| Finding | Blocking | Why it matters |
|---|---|---|
| `baseline-weakened` | yes | the project lowered a rule the shared baseline sets — it may raise, never lower |
| `baseline-not-included` | yes | the baseline exists but the build never reads it |
| `include-unresolved` | yes | an included ruleset is not on disk (often a sibling repo not checked out) — its rules silently stop applying |
| `ruleset-unreadable` · `baseline-missing` | yes | a ruleset that does not parse, or a baseline path with nothing there — nothing it sets was checked |
| `include-cycle` | yes | a ruleset includes itself through its own chain |
| `general-action-silences` | yes | `generalAction` hides every rule not listed |
| `blanket-pragma` | yes | `#pragma warning disable` with no rule ID turns off everything below it |
| `disabled-without-justification` | no | a rule set to `None`/`Hidden` with no `justification` |
| `pragma-without-reason` | no | a suppression with no `// reason` after it |

Pass `security.rulesetBaseline` as recorded; the script resolves a relative path against the
repository root, and reports `baseline-missing` (blocking) when nothing is there. When it
is `null`, run without `-Baseline` and say that weakening against a shared standard was not
checked, and that `/alrig:scan` can record one.

**Do not edit the ruleset or remove a pragma.** A suppression may be right; the project decides.

## 3 — Report

```
APP         <name> (<path>) — <status>
ANALYZERS   <those that ran> | MISSING <declared but absent>
RULESET     <path> → <include chain> | none
COUNTS      errors <n> · warnings <n> · info <n> · suppressed in source <n>
BY SOURCE   compiler <n> · CodeCop <n> · AppSourceCop <n> · UICop <n> · PTE <n> · third-party <n>
TOP RULES   <rule> ×<count> — <one-line meaning>, for the ten largest
ERRORS      <file:line rule message>, every one
RULESET     <each blocking finding, then each advisory one> | clean
NEXT        <the single most valuable thing to fix first, and why>
```

Group warnings by rule, not by file: forty instances of one rule are one decision, and a list
of forty lines hides that. For the top rules, read the matching `al-conventions` theme only if
you need it to explain the rule — never the whole set.

`NEXT` is a judgement: an error before a warning, a blocking ruleset finding before either,
and among warnings the rule whose fix is mechanical and widespread first.

The full diagnostic list stays in the `outDir` the script reports; say where it is rather than
pasting it. The scan's `findings` are capped at 400 — say so when `truncated` is true.

## Rules that do not bend

- Ruleset severities come from the project's own ruleset. **Never pass a ruleset of your own,
  and never invent a rule ID** — codes come from the compiler that ran.
- A scan that could not compile is `UNVERIFIED`, not clean.
- A `baseline-weakened` finding is reported even when the weakened rule has a justification:
  the justification belongs in the baseline's repository, where the standard is owned.
