---
name: al-review
description: alrig stage 3 — independently re-verify an AL change against its spec, or a bare diff for /alrig:check. Loaded by /alrig:review, /alrig:go and /alrig:check.
version: 0.4.0
allowed-tools: Read, Glob, Grep, Bash, Agent, Task, mcp__al__al_compile, mcp__al__al_getdiagnostics, mcp__al__al_downloadsymbols
---

# Stage 3 — review

You verify the result. **Not the reasoning** — the result.

Read `.claude/alrig.json` first. If it is absent, say so and recommend `/alrig:scan`. If it
does not parse, quote the error and stop.

## Where the work happens

- **`product` tier, with a spec** — dispatch the `alrig:al-reviewer` agent. Give it the
  repository root, the profile contents, the spec, the warning baseline from stage 2 if this
  conversation has one, the files stage 2 touched, and how to obtain the diff. **Do not give it
  the implementer's transcript**, a summary of one, or your account of why a choice was made —
  a reviewer that can see the reasoning reviews the reasoning. Relay its output unchanged; do
  not read `references/checks.md` yourself, the agent carries its own copy.
- **`customisation` tier, or no-spec mode** — read `references/checks.md` and run it here.
  On `customisation`, say in `NOTES` that the review shared a context with the implementation.

## No-spec mode — `/alrig:check`

Everything in `references/checks.md` applies except the two checks that need a contract:

- **Criteria** — report `no spec`. Never derive criteria from the diff and then mark them met.
- **Scope** — unreportable; nothing said what the change was for.

The warning delta is diff-scoped unless a baseline exists (check 2). `VERIFIED` here means
*nothing blocking was found in this diff*, **not** that the change is right — say so in the
output. No-spec mode never gates, never writes, and never uses a subagent.
