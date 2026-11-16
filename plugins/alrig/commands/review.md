---
description: Re-verify a change against its approved spec from a fresh context — use to resume a /alrig:go run
argument-hint: "[path to spec, or omit to use the spec from this conversation]"
allowed-tools: Skill, Read, Glob, Grep, Bash, Agent, Task, mcp__al__al_compile, mcp__al__al_getdiagnostics
---

Load the `alrig:al-review` skill with the Skill tool and follow it exactly.

Spec: `$ARGUMENTS`

The review re-runs the build itself and recomputes the warning delta. It does not accept a
reported result, including one reported earlier in this same conversation.

On the `product` tier the review runs in the `alrig:al-reviewer` subagent, which receives the
spec and the diff and **must not receive the implementer's transcript**. That independence is
the whole point of the stage: a reviewer who can see why each choice was made reviews the
reasoning instead of the result.
