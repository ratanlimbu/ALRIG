---
name: al-scaffold
description: Start a Business Central app where none exists — an empty repository, or a new app directory beside existing ones — asking for every project fact rather than inventing it, showing the full file list, and writing only on an explicit yes. Then profiles it. Used by /alrig:new.
version: 0.2.0
allowed-tools: Read, Glob, Grep, Bash, Write, AskUserQuestion, Skill
---

# Starting an app

Everything else in this plugin adopts a repository as it stands. This is the one stage that
creates a layout, so it is bounded harder than any other: **it creates files only inside one
directory that holds no app yet, it never edits an existing file, and it writes nothing until
the human has seen every path and said yes.**

## 1. Preconditions — refuse rather than merge

- The target directory is the argument, or asked for. It must not exist, or be empty. A
  directory that already holds an `app.json` anywhere beneath it is an app: **stop**, and
  recommend `/alrig:scan` instead.
- **An AL-Go repository** (`.github/AL-Go-Settings.json` or any `.AL-Go/settings.json`) has its
  own *Create a new app* workflow, which also registers the app in the project's settings.
  Recommend that, then `/alrig:scan`. Continue here only if the human insists, and say that
  AL-Go will not know about the app until its settings name the folder.

## 2. Ask — never invent a project fact

Every value below is the project's, so every one is asked. Read what the repository can answer
first (another `app.json`'s publisher or versions, an existing `AppSourceCop.json`) and offer it
as the proposed answer.

| Ask | Why it cannot be defaulted |
|---|---|
| **Distribution** — AppSource, per-tenant extension, or OnPrem | decides `target`, the cop, and the affix rules |
| **Name, publisher, brief** | the app's identity, permanent once installed anywhere |
| **ID range** | AppSource ranges are assigned to the publisher; a PTE uses the range the customer's partner agreement allows. Both are commercial facts |
| **Affix** | mandatory and registered with Microsoft for AppSource; recommended for a PTE |
| **`application`, `platform`, `runtime`** | the oldest Business Central version the app must run on. If the `al` tool is present, its `GetLatestSupportedRuntimeVersion` command gives the newest runtime for a version; otherwise ask. Never pick "latest" on the human's behalf — it decides who can install the app |
| **Test app** — yes or no, and its directory | a second app, with its own identity and range |
| **Namespaces** — yes or no (runtime 12.0 and later) | a convention every later file follows |

## 3. Show the plan, then wait

List every file with its full path and contents before writing anything:

- `<dir>/app.json` — a new GUID `id` (generate it with the platform's tool: `[guid]::NewGuid()`,
  `uuidgen`, or a language runtime — never type one), the answers above, version `1.0.0.0`,
  `features: ["TranslationFile"]`, `target` only when it is `OnPrem`. For AppSource, the listing
  fields (`privacyStatement`, `EULA`, `help`, `url`, `logo`, `contextSensitiveHelpUrl`) are
  present and **empty** — `/alrig:appsource` reports them until a human fills them; a
  placeholder URL would pass for a real one.
- `<dir>/AppSourceCop.json` with `mandatoryAffixes` — AppSource only.
- `<dir>/src/` holding one permission set object for the app, `Assignable = true`, at the first
  ID of the range — the object every new object will be added to. Name files the way
  `<ObjectName>.<ObjectType>.al` does.
- **Test app**, if wanted: its own `app.json` (new GUID, its own range) depending on the main
  app, and the main app's `internalsVisibleTo` naming it. **Microsoft's test libraries are not
  added yet:** their IDs come from the symbol packages once symbols are downloaded, never from
  memory. Say so, and name the libraries the human will add (`Library Assert`, `Any`,
  `Library Variable Storage`).
- `.vscode/settings.json` at the repository root **only if absent**, enabling code analysis and
  the cops for the distribution — `CodeCop`, `UICop`, and `AppSourceCop` or
  `PerTenantExtensionCop`. If it exists, show the keys to add and let the human paste them.
- `.gitignore` **only if absent**: `.alpackages/`, `.alcache/`, `.snapshots/`, `.output/`,
  `*.app`, `rad.json`, `*.bclicense`, `*.flf`. If it exists, show the lines and change nothing.

Not created, ever: `CLAUDE.md`, `README`, `launch.json` (it names an environment, and VS Code
writes it on first publish), CI workflows. For CI, recommend Microsoft's AL-Go for GitHub
templates.

Stop. Write only on an explicit yes to this list. Silence, or a yes to something else, is a no.

## 4. Write, then profile

Write exactly the approved files. Then run the `alrig:al-profile` skill so `.claude/alrig.json`
reflects the new app — it asks before writing, as always. Recommend `/alrig:mcp` last: a new
repository has no build command, and without one every stage reports `UNVERIFIED`.

## Out

```
CREATED   <each path>
SKIPPED   <each file that existed, with the lines or keys offered instead>
ASKED     <each project fact and the answer given>
NEXT      download symbols; add the test libraries; /alrig:mcp; then /alrig:spec
```
