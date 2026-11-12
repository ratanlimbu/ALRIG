---
description: Start a Business Central app in an empty repository or a new directory — asks every project fact, shows every file, writes only on yes
argument-hint: "[directory for the new app]"
allowed-tools: Skill, Read, Glob, Grep, Bash, Write, AskUserQuestion
---

Load the `alrig:al-scaffold` skill with the Skill tool and follow it exactly.

Target directory: `$ARGUMENTS` — ask for it when omitted.

This is the one command that creates a layout, so the adopt-in-place contract binds it more
tightly, not less:

- **It refuses a directory that already holds an app.** An existing app is profiled with
  `/alrig:scan`, never re-scaffolded.
- **It edits no existing file.** Where a file it would create already exists, it shows what it
  would have added and leaves the file alone.
- **It writes nothing until you have seen every path and said yes.**
