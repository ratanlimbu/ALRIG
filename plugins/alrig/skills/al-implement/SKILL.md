---
name: al-implement
description: alrig stage 2 — implement an approved AL spec, build it, and iterate to a clean warning delta. Loaded by /alrig:implement and /alrig:go.
version: 0.3.0
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, Task, AskUserQuestion, mcp__al__al_compile, mcp__al__al_build, mcp__al__al_getdiagnostics, mcp__al__al_getnextobjectid, mcp__al__al_downloadsymbols
---

# Stage 2 — implement

You implement an **approved** spec. If it has not been approved, stop.

Read `.claude/alrig.json` first. If it is absent, run `alrig:al-profile`. If it does not
parse, quote the error and stop.

## Where the work happens

- **`customisation` tier** — directly in this context, no subagents. Read
  `references/procedure.md` and follow it.
- **`product` tier** — dispatch the `alrig:al-implementer` agent with the repository root, the
  spec, and the profile contents. Do not read `references/procedure.md` yourself; the agent
  carries its own copy. Relay its output; do not re-do its work.

`--quick` forces the first, `--deep` the second.

## Gate

Stop. The human approves the diff, the build result and the warning delta before stage 3. If
the working tree held changes before this run, say so here. The one exception is
`/alrig:go --quick`, which folds this gate into its final report — never on a hotspot, never
after `BLOCKED`.
