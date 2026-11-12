# `.claude/alrig.json` — the profile

One file. It is the plugin's entire configuration footprint, and deleting it is the complete
uninstall.

Before 0.2.0 the plugin was called `bp-al` and the file was `.claude/bp-al.json`. `/alrig:scan`
finds the old file and offers to move it; nothing else about it changed.

It is **data, not prose**, and it is hand-editable. `/alrig:scan` writes it and will refresh
it later, but **never overwrites a field a human has edited** — it shows what it would change
and asks.

Everything here is discovered from your repository or typed by you. **Nothing in this file
ships with the plugin.** The example below uses a fictional extension purely to show the
shape.

```jsonc
{
  "version": 2,
  "tier": "customisation",                 // "product" | "customisation"
  "apps": [
    { "path": "app",
      "name": "Contoso Warehouse Ext",
      "idRanges": [[50100, 50149]],
      "prefix": "CWE",
      "isTest": false,
      "target": "Cloud",                   // "Cloud" | "OnPrem" — absent in app.json means Cloud
      "runtime": "14.0",
      "application": "26.0.0.0",
      "dependsOn": [],                     // other apps in THIS repository it depends on
      "project": null }                    // AL-Go project folder, or null
  ],
  "dependencies": [
    { "name": "Contoso Core", "sourcePath": "../contoso-core" }
  ],
  "analyzers": ["CodeCop", "UICop", "PerTenantExtensionCop"],
  "build": {
    "provider": null,                      // "command" | "al-mcp" | null
    "command": null,                       // may contain {app}, run once per app
    "cwd": null,
    "warningPolicy": "no-new"              // "no-new" | "zero" | "ignore"
  },
  "tests": { "present": false, "path": null, "runCommand": null },
  "ci": { "system": null, "path": null },   // "al-go" | "azure-pipelines" | "github-actions" | null
  "authority": ["CONTRIBUTING.md"],
  "specs": { "mode": "inline", "dir": null },
  "appsource": {
    "target": "pte",                       // "appsource" | "pte" | null
    "previousVersionPath": null            // the published .app to compare against
  },
  "hotspots": ["**/Posting/**"],
  "forbidden": [
    { "pattern": "\\bCommit\\(", "why": "transaction boundaries belong to the caller" }
  ],
  "policy": {
    "blockOn":  ["error", "forbidden", "criterion-not-met", "warning-delta"],
    "advisory": ["scope", "reachability", "performance", "hotspot", "style"],
    "requireTests": false
  }
}
```

## Fields

| Field | Type | Meaning |
|---|---|---|
| `version` | number | Profile schema version. `2` today. A rescan of a `1` profile proposes each added field and asks. |
| `tier` | `"product"` \| `"customisation"` | Which pipeline shape runs by default. See below. |
| `apps[]` | array | One entry per `app.json` found. |
| `apps[].path` | string | Directory holding `app.json`, relative to the repository root. |
| `apps[].name` | string | From `app.json`. |
| `apps[].idRanges` | `[[from, to], …]` | From `app.json`. Used to check that claimed IDs are in range. |
| `apps[].prefix` | string \| null | Mandatory prefix or affix. `null` when the project has none, or when detection was not confident. |
| `apps[].isTest` | boolean | Test app, by a Microsoft test-library dependency, a `Subtype = Test` codeunit, or a `*Test*` name. |
| `apps[].target` | `"Cloud"` \| `"OnPrem"` | From `app.json`; **absent there means `Cloud`**, the platform default. Rules tagged **[Cloud]** or **[OnPrem]** in the baseline bind only matching apps. |
| `apps[].runtime` | string \| null | From `app.json`. A baseline rule tagged *runtime N and later* does not bind an app below N. |
| `apps[].application` | string \| null | From `app.json` — the oldest Business Central version the app promises to run on. Symbol checks use it as the floor. |
| `apps[].dependsOn` | string[] | Names of the **other apps in this repository** this app depends on. Builds run in this order, and a change rebuilds everything downstream of it. |
| `apps[].project` | string \| null | The AL-Go project folder holding the app, or `null`. |
| `dependencies[]` | array | Non-Microsoft dependencies whose source you have locally. |
| `dependencies[].name` | string | As it appears in `app.json`. |
| `dependencies[].sourcePath` | string \| null | Where that dependency's source lives. **Searched before anything is reported as missing** — the object you need may already exist one layer down. |
| `analyzers[]` | string[] | Which code analyzers the project runs. Recorded so the warning gate knows what the compiler will emit. **No rule IDs are stored** — see below. |
| `build.provider` | `"command"` \| `"al-mcp"` \| `null` | How stages build. `al-mcp` uses Microsoft's AL MCP server, registered under the key `al` by `/alrig:mcp`. `null` means no build, and every verdict is `UNVERIFIED`. |
| `build.command` | string \| null | The build invocation, used when `build.provider` is `command`. **Always confirmed by a human, never inferred silently.** May contain `{app}`, substituted with each app's `path` and run once per app in `dependsOn` order. |
| `build.cwd` | string \| null | Directory to run it from. `null` means the repository root. |
| `build.warningPolicy` | `"no-new"` \| `"zero"` \| `"ignore"` | The warning gate. Default `no-new`. |
| `tests.present` | boolean | Whether a test app exists. |
| `tests.path` | string \| null | Where it is. |
| `tests.runCommand` | string \| null | How to run the test suite. Detected from the VS Code tasks, an AL Test Runner setting or a root script, and **confirmed by a human** exactly as `build.command` is. `null` when the tests only run in CI, or at all. |
| `ci.system` | `"al-go"` \| `"azure-pipelines"` \| `"github-actions"` \| `null` | Where builds run remotely. **Recorded, never run.** When it is set and `build.provider` is `null`, the repository builds only in CI, and `/alrig:scan` says what that costs. |
| `ci.path` | string \| null | The file or directory that identified it. |
| `authority[]` | string[] | Paths to the documents that decide things here, **in precedence order**, most authoritative first. Paths only — content is read on demand by the stage that needs it. |
| `specs.mode` | `"file"` \| `"inline"` | Whether stage 1 writes a spec document or keeps the contract in the conversation. |
| `specs.dir` | string \| null | Where spec documents go. **Only a directory that already exists** — the plugin never creates one. Design documents from `/alrig:design` go here too. |
| `hotspots[]` | glob[] | Areas where any change is flagged for human review regardless of correctness. |
| `forbidden[]` | `{pattern, why}[]` | Regex patterns banned **in this project**, each with its reason. The reason is reported with the finding. |
| `appsource.target` | `"appsource"` \| `"pte"` \| null | Which cop's rules this app is held to. `null` means undetermined, not "not AppSource". |
| `appsource.previousVersionPath` | string \| null | The previously published `.app`, which AppSourceCop needs to detect breaking changes. `null` means that analysis has never run. |
| `policy.blockOn[]` | category[] | Finding categories that make stage 3's verdict `BLOCKED`. |
| `policy.advisory[]` | category[] | Categories reported in full but not blocking. Every category sits in exactly one of the two lists. |
| `policy.requireTests` | boolean | When `true`, a change whose tests did not run is `UNVERIFIED`. Default `false`. |

## The fields worth thinking about

### `build.provider` and `build.command`

Everything downstream depends on them. With `build.provider` `null`, stages 2 and 3 return
`UNVERIFIED` — they will still write and review code, but no one has compiled it, and they say
so.

Most Business Central repositories have no local build command: developers compile in VS Code,
and AL-Go or Azure DevOps builds in a container. That is what `al-mcp` is for. Microsoft's AL
MCP server compiles with the analyzers on, with no VS Code and no container, and `/alrig:mcp`
sets it up and offers to switch the provider. A repository with a working command keeps it.

On a multi-app repository, a command that builds one app takes `{app}`. Stages build the apps
the change touches and every app downstream of them in `dependsOn` order, because a change
that compiles in its own app can still break the app built on top of it.

It is never written without a human confirming it, because build invocations go stale:
compiler paths move between AL extension versions, and a stale one fails in a way that reads
like a project problem and is not.

### `hotspots` and `forbidden`

These are the generic mechanism behind project-specific safety rules — *"flag any change in
this area"* and *"this API is banned here even though it is fine elsewhere"*. The plugin ships
the mechanism; you supply the content.

`forbidden` is where a project overrules the shipped AL baseline. A helper that is best
practice platform-wide can be exactly wrong under a regulator that requires something else,
and the reviewer reports the override rather than conforming silently.

A small customisation leaves both `[]` and loses nothing.

### `analyzers`

Names only. **The plugin deliberately stores and ships no analyzer rule IDs** — which cops run
differs per project, and a bundled list would be wrong somewhere and stale everywhere. Codes
come from the compiler the project actually runs.

### `appsource`

`target` records which cop's rules the app is held to, detected from `AppSourceCop.json` or
`PerTenantExtensionCop.json`. `null` means undetermined — an app can be heading for AppSource
with neither file present yet — so it is not read as "not AppSource".

`previousVersionPath` points at the previously published `.app`. It is the input AppSourceCop
needs to detect breaking changes, and without it that analysis has never run on the app at all.
`/alrig:appsource` reports that as `UNVERIFIED` rather than as a pass, because it is the check
whose failure costs a version number.

It is confirmed by a human like `build.command`, and for a sharper version of the same reason:
a stale previous version compares against the wrong thing, which is worse than comparing
against nothing, and produces a clean report either way.

### `policy`

The strictness knob. It exists because a repository halfway through its life and a greenfield
one need the same checks and different consequences — and the way that usually gets resolved
is someone turning a check off. Here nothing is turned off: every category is still looked
for, still found and still reported. `policy` decides only which ones stop the pipeline.

The nine categories, each in exactly one list:

| Category | Raised when |
|---|---|
| `error` | the build returned a non-zero exit code |
| `warning-delta` | the warning set violates `build.warningPolicy` |
| `forbidden` | a `forbidden[]` pattern matched the diff |
| `criterion-not-met` | an acceptance criterion is demonstrably not satisfied |
| `scope` | the diff contains something no criterion asked for |
| `reachability` | a new object or public procedure has no call path and no exemption |
| `performance` | the diff contravenes the `performance` theme |
| `hotspot` | the diff touched a `hotspots` glob |
| `style` | idiom, naming or convention deviation |

Defaults block on `error`, `forbidden`, `criterion-not-met` and `warning-delta`; the rest are
advisory. That is deliberately the loose end of the range. **`scope` and `reachability` are
advisory by default because both are routinely correct on a brownfield repository** — adjacent
fixes are normal, and an AppSource app publishes surface that no caller in the repository ever
touches. Tightening them is a decision a project makes when it is ready to, not a default it
has to fight.

`policy` governs **stage 3's verdict only**. `build.warningPolicy` still drives stage 2's
iterate-to-clean loop, and `advisory` never means unfixed — it means the pipeline does not stop
for it.

`/alrig:scan` writes the defaults once and **never proposes changes to `policy` on a refresh**.
A rescan that re-suggested defaults over a project's own settings would quietly loosen exactly
the projects that had tightened.

### `policy.requireTests`

Stages 2 and 3 run the tests when `tests.runCommand` is set, and it is detected and confirmed
like `build.command`. It is still `null` on every repository whose tests run only in CI, so
`requireTests` defaults to `false`. Without that default, every such repository returns
`UNVERIFIED` forever, and a verdict that is always the same carries no information.

It is not a licence to be vague. The review's `TESTS` line is printed whatever the setting
says, so `VERIFIED` never gets to mean "the tests passed" when what happened is that they did
not run.

## Verdicts

| Verdict | Means |
|---|---|
| `VERIFIED` | every check ran, every criterion `MET`, nothing blocking outstanding |
| `BLOCKED` | every check ran, and something in a `blockOn` category stands |
| `UNVERIFIED` | a check could not run at all — no build command, no baseline, an undecidable criterion |

`UNVERIFIED` outranks `BLOCKED`: you cannot block on what you did not see. The two were one
word in the first draft, and the conflation cost real information — *"this is wrong"* and *"I
could not tell"* call for different things from the human reading it.

## Tier

`product` is selected when any of these hold: more than one app · a test app is present · a
dependency on a non-Microsoft app · more than 100 `.al` files. Otherwise `customisation`.

| | `customisation` | `product` |
|---|---|---|
| Contract | inline in the conversation | written to `specs.dir` |
| Implementation | directly in the main context | bounded `al-implementer` subagent |
| Review | a pass in the same context | `al-reviewer` in a fresh context |
| Files written | the code only | the code, plus the spec and any design |

Override for one run with `--quick` (force `customisation`) or `--deep` (force `product`).

## `null` is a real value

What could not be determined is recorded as `null`, and the stage that needed it degrades
**loudly** — reporting `UNVERIFIED` — rather than guessing. A guessed value is worse than an
absent one, because every later stage trusts the profile.
