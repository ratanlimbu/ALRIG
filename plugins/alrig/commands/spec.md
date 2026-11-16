---
description: Write only the contract (checkable acceptance criteria) for an AL change — most users want /alrig:go
argument-hint: "<what you want built or changed>"
allowed-tools: Skill, Read, Glob, Grep, Bash, Write, AskUserQuestion
---

Load the `alrig:al-spec` skill with the Skill tool and follow it exactly.

The request: `$ARGUMENTS`

If the request is empty, ask for it rather than inventing one.

Read `.claude/alrig.json` first. If it does not parse, quote the error and stop. If it is
absent, say so and run the `alrig:al-profile`
skill first — a contract that names object IDs and authority documents cannot be written
without the profile.
