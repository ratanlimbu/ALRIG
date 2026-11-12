---
name: al-mcp
description: Offer the optional MCP servers that let the alrig stages build, find symbols and cite documentation — Microsoft's AL MCP server, Microsoft Learn, and a symbol server of the human's choosing — and write their configuration only on an explicit yes. Used by /alrig:mcp.
version: 0.2.0
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
---

# Optional MCP servers

This is the **only** place that writes MCP configuration. It writes it only on an explicit yes,
to `.mcp.json` at the repository root — or, if the human prefers, to their own local scope with
`claude mcp add --scope local`, which writes nothing into the repository. Say all of that
before asking anything.

Nothing here is bundled. The plugin ships no server, vendors no package and starts no process;
it writes configuration the human approved, pointing at things they chose.

## 1. The cost goes first

An MCP server is a process or an endpoint that runs for the whole session, unlike everything
else in this plugin, which costs nothing when idle. That is the trade on offer, and it is
stated before the benefit.

## 2. Microsoft's AL MCP server — offer it first

It is first-party: it ships inside the AL Language extension (17.0 and later) as `altool`, and
as the `al` command of Microsoft's `Microsoft.Dynamics.BusinessCentral.Development.Tools` .NET
tool. It needs the .NET 8 runtime, and it runs without VS Code. For this plugin it is the
difference between `UNVERIFIED` and a verdict on most repositories, because it gives the stages:

- **a build** — `al_compile` and `al_build`, with the code analyzers on — where the repository
  has no local build command, which is most repositories that build in VS Code or only in CI;
- **diagnostics** — `al_getdiagnostics`;
- **symbols** — `al_symbolsearch`, and `al_downloadsymbols` to fill `.alpackages`;
- **object IDs** — `al_getnextobjectid`.

Set it up like this:

1. **Find the executable; do not assume it.** Check for `al` on the path, then `altool` inside
   the newest `ms-dynamics-smb.al-*` folder under the VS Code extensions directory (`bin`, then
   the platform folder). Show what you found. An extension-folder path carries a version and
   goes stale on the next extension update — say so, and mention the .NET tool as the stable
   alternative. **Installing it is the human's decision**; never run the install yourself.
2. **Ask the executable for its own syntax.** Run `<exe> launchmcpserver --help` and build the
   arguments from what it prints: the project folders (every non-test and test app `path` in
   the profile), the stdio transport, and the analyzer and package-cache options if it offers
   them. Microsoft's pages have shown more than one syntax across versions; the installed
   binary is the authority, not this file.
3. **Register it under the key `al`, exactly.** The plugin's subagents are granted this server's
   tools by name — `mcp__al__al_compile` and the rest — so any other key leaves them unable to
   build. If a server running `launchmcpserver` already exists under another key, say so and ask
   whether to add an `al` entry beside it; never rename theirs.
4. **Machine-specific paths do not belong in a shared file.** If the executable path or the
   project folders are absolute, recommend local scope over `.mcp.json`.
5. **Then offer the profile change** — `build.provider: "al-mcp"` in `.claude/alrig.json` —
   showing `current -> proposed` and writing it only on a yes, as `/alrig:scan` would. A repo
   with a confirmed `build.command` keeps it unless the human chooses otherwise.

## 3. Microsoft Learn

`https://learn.microsoft.com/api/mcp`, type `http`. First-party, no local process, no package
to trust. It lets a design or review cite Business Central documentation instead of asserting
from memory — the gap between a confident wrong answer and a checkable one.

## 4. A third-party symbol server — without naming a package

Where Microsoft's server is not an option, a community symbol server can resolve base objects
whose source is not on disk. **Do not propose a specific package or version.** Describe what it
must do, ask which one the human uses, and write exactly what they give you. A plugin that puts
`npx some-package@x.y.z` into a repository has made a supply-chain decision on someone else's
behalf, in a file that then runs on every session.

## Writing

- **Merge, never overwrite.** If `.mcp.json` exists, show each key you would add, ask, and add
  only those. Touch no existing entry. If it does not exist, show the whole file first.
- **Say how to undo it.** Delete the keys, or delete `.mcp.json` if this created it, or
  `claude mcp remove al --scope local`; and set `build.provider` back if it was changed. The
  plugin keeps working without any of this — the stages check less, and say so.
- Claude Code loads MCP configuration at session start: tell the human to restart the session
  before the next stage relies on the new server.

`--show` prints what would be written and changes nothing.
