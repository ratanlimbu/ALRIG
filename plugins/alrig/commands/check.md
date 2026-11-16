---
description: Review AL changes made by hand (uncommitted work or a git range) — no spec, no gate, never writes
argument-hint: "[git range, or omit for the working tree]"
allowed-tools: Skill, Read, Glob, Grep, Bash, mcp__al__al_compile, mcp__al__al_getdiagnostics, mcp__al__al_downloadsymbols
---

Load the `alrig:al-review` skill with the Skill tool and run it in **no-spec mode**, described
in that skill.

Diff: `$ARGUMENTS` — a git range if given, otherwise the working tree.

This is the command for a change that did not come through the pipeline, which on a repository
already halfway through its life is most of them. It runs the build, the warning delta, the
`forbidden` patterns, the performance dimension, hotspots, reachability and the tests. With no
stage 2 baseline, the warning delta covers the lines the diff touched, and says so.

It cannot check acceptance criteria or scope, because both need a spec to check against. It
says so rather than reporting them as passed.

It never writes and it never gates. `/alrig:review` is the one with a contract behind it; this
one tells you what is true about a diff.

It runs in this conversation on every tier, never in a subagent: with no spec there is no
implementer reasoning to keep the review independent of, and a quick report should stay quick.
