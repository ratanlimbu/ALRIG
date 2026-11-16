---
description: Make an AL change end to end — contract, code, build, independent review — with your approval between steps (--quick for a small change)
argument-hint: "<what you want built or changed> [--quick: one approval | --deep: design files + subagents]"
allowed-tools: Skill, Read, Glob, Grep, Bash, Write, Edit, Agent, Task, AskUserQuestion, mcp__al__al_compile, mcp__al__al_build, mcp__al__al_getdiagnostics, mcp__al__al_getnextobjectid, mcp__al__al_symbolsearch, mcp__al__al_downloadsymbols
---

Sequence the stages. All behaviour lives in the stage skills; this command only orders them
and holds the gates. The request: `$ARGUMENTS`

1. Read `.claude/alrig.json`. **Absent** → run the `alrig:al-profile` skill and show the
   profile; if it wrote nothing (an empty repository), stop and recommend `/alrig:new`.
   **Does not parse** → quote the error, point to `/alrig:scan`, and stop.
2. Tier: the profile's `tier`, unless `--quick` (force `customisation`) or `--deep` (force
   `product`). State it and why in one line.
3. **Stage 1 with triage** — load `alrig:al-spec`; it triages first (silently with `--quick`).
   - **HIGH, confirmed** → **Stage 0**: load `alrig:al-design` at section 2. **Gate: design
     approval.** Then back to the spec, bound by it. Fewer than three genuine decisions → it
     was MEDIUM: carry them into the spec as `OPEN` entries, no design gate.
   - **LOW / MEDIUM** → the spec, with the `TRIAGE` line at its top.
   **Gate: spec approval.** Never proceed on silence or an implied yes.
4. **Stage 2** — load `alrig:al-implement`. **Gate: approval** of the diff, build and warning
   delta. **With `--quick`, go straight to Stage 3** and show diff, build, delta and verdict
   together — unless `HOTSPOTS HIT` is not `none` or Stage 2 returned `BLOCKED`.
5. **Stage 3** — load `alrig:al-review`. Report the verdict and its `NEXT` line.

**Gates.** Every gate is a real stop. On a **no**: ask what to change, revise that stage, and
present it again. On **stop**: end, and print how to resume (`/alrig:implement <spec>` or
`/alrig:review <spec>` for a file spec; an inline spec ends with the conversation).

If a stage reports `BLOCKED`, `UNVERIFIED` or `BASELINE FAILED`, say which at the gate — the
human decides whether it matters. Advisory findings are reported at the gate too; they never
stop the run and are never left out.
