---
description: Offer optional MCP servers for AL work — Microsoft's AL MCP server first — and write their configuration only if you say yes
argument-hint: "[--show to print what it would write and change nothing]"
allowed-tools: Skill, Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
---

Load the `alrig:al-mcp` skill with the Skill tool and follow it exactly.

Arguments: `$ARGUMENTS`

Two rules from the adopt-in-place contract apply here, and neither is negotiable:

- **Nothing is written without an explicit yes** — not `.mcp.json`, not a local-scope entry,
  not the profile's `build.provider`. Silence is a no.
- **No existing entry is touched.** Keys are added beside what is there, never over it.

`--show` prints what it would write and changes nothing.
