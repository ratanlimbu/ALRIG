---
name: al-profile
description: Detect what a Business Central repository is (apps, build and test commands, analyzers, authority documents, tier) and record it in .claude/alrig.json. Loaded by /alrig:scan.
version: 0.4.0
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
---

# Profiling a repository

You describe the repository you found. You do not prescribe one.

**Write exactly one file: `.claude/alrig.json`.** Create the `.claude` directory if needed.
Create nothing else. Move nothing. Rename nothing. Edit no file you did not create — not
`CLAUDE.md`, not `README`, not `app.json`.

What you cannot determine is `null`. **Never guess a value into the profile**; a wrong build
command or a wrong prefix is worse than an absent one, because every later stage trusts it.

## Detection

Follow `references/detection.md`, top to bottom. It covers apps (with each app's `target`,
`runtime`, `application`, in-repo `dependsOn` edges and AL-Go `project`), test apps, prefix,
analyzers, CI, the build provider and command, tests, AppSource, authority documents, the spec
directory, the tier and security.

Three rules from it bind every step:

- **No apps at all is an empty repository**, not a detection failure. Write nothing, report it,
  and recommend `/alrig:new`.
- **Build, test and previous-version candidates are confirmed by the human** before they are
  written. Each goes stale silently, and a stale one fails in a way that reads like a project
  problem.
- **CI is recorded, never run, and never read into `build.command`.**

**Policy** — write the defaults below verbatim. **Detect nothing here**; a strictness setting
inferred from a repository's current state would ratchet a project tighter the cleaner it got,
which is exactly backwards. It starts loose and the human tightens it.

```json
"policy": {
  "blockOn":  ["error", "forbidden", "criterion-not-met", "warning-delta"],
  "advisory": ["scope", "reachability", "performance", "hotspot", "style"],
  "requireTests": false
}
```

Every category sits in exactly one list. The nine are `error`, `warning-delta`, `forbidden`,
`criterion-not-met`, `scope`, `reachability`, `performance`, `hotspot`, `style`. A category in
neither list is a profile error; report it rather than picking one.

`blockOn` decides only **stage 3's verdict**. It does not relax stage 2 — `build.warningPolicy`
still governs the iterate-to-clean loop, and an advisory category is still found, still
reported and still counted. Advisory means *stated, not silenced*.

## Refreshing an existing profile

`scan` is idempotent and **never overwrites a field a human has edited**. When
`.claude/alrig.json` already exists:

1. Compute what you would detect now.
2. Show every field that differs, as `field: current -> proposed`.
3. Ask which to apply. Apply only those. Leave the rest exactly as they are.

Never propose `build.provider: al-mcp -> null` while the `mcp__al__*` tools are available in
this session: the server is registered somewhere detection did not look.

`policy`, `hotspots`, `forbidden` and `security.urlAllowlist` are **never proposed on a refresh**. They hold human
judgement, not detection, and a rescan that re-suggests defaults over them is a rescan that
quietly loosens a project someone deliberately tightened. The one exception: if the category
vocabulary has grown since the profile was written, name the missing categories and ask where
they go — an unassigned category is otherwise invisible.

**A profile written by an older schema** (`version` lower than `3`) is refreshed the same way:
each field the newer schema adds is shown as `field: <absent> -> proposed` and applied only if
the human says so. `version` moves to `3` once every added field has been answered, applied or
set to `null`. Nothing already present is re-proposed because the schema moved. Schema 3 adds
only the `security` block.

**A profile under the plugin's former name**, `.claude/bp-al.json`, with no `.claude/alrig.json`
beside it: offer to move it to the new name, then refresh it as above. Move, never copy — two
profiles would disagree the first time one is edited. If both exist, use `alrig.json` and say
that the old file is ignored and can be deleted.

## Reporting

After writing, report in this shape:

```
TIER        <tier, and which rule selected it>
APPS        <name, path, target, runtime, id range, prefix, test/not, depends on — one line each>
BUILD       <provider and command, and that a human confirmed it | null>
CI          <system and path | none>
TESTS       <test app path and run command, both confirmed | present, no run command | none>
AUTHORITY   <paths, in precedence order | none found>
SPECS       <mode, dir>
APPSOURCE   <target, and whether a previous version is available to compare against>
SECURITY    <allowlisted hosts | none>; <ruleset baseline, confirmed | null>; <reports dir | null>
POLICY      <blockOn categories; advisory categories; requireTests>
GAPS        <every field left null, and what it costs you>
```

**The `GAPS` section is the point of the report, not a footnote.** A `null` build command
means every later stage returns `UNVERIFIED`; say that in those words, and name the fix —
`/alrig:mcp`, or a local build command. Then state the one-line uninstall: delete `.claude/alrig.json`.

`docs/PROFILE.md` in this plugin's repository documents every field and its shape.
