# ALRIG

A Claude Code plugin for Microsoft Dynamics 365 Business Central AL development. Say it "AL-rig":
a rig is the harness the work runs inside — a contract before the code, your own compiler during
it, and an independent check after.

The name is ALRIG; commands and files use its lowercase plugin ID — `/alrig:scan`,
`.claude/alrig.json` — because Claude Code plugin IDs are lowercase.

`spec → implement → review` — with an optional design stage in front for the changes that need
one — command-driven, with a human gate between each stage — and the
constraint everything else is downstream of: **it is safe to add to a repository that is
already halfway through its life.**

```
/plugin install alrig --marketplace ratanlimbu/alrig
/alrig:scan
```

On Claude Code older than 2.1.275, add the marketplace first:

```
/plugin marketplace add ratanlimbu/alrig
/plugin install alrig
```

To update later: `/plugin marketplace update alrig`. What changed in each release is in
[CHANGELOG.md](CHANGELOG.md).

## Start here

Three commands cover most days:

| You want to | Run |
|---|---|
| Set it up in a repository — once | `/alrig:scan`, or `/alrig:new` in an empty one |
| Make a change | `/alrig:go <what you want>` — add `--quick` for a small one |
| Check a change you made by hand | `/alrig:check` |

Once, if your repository has no local build command — most Business Central repositories
don't — run `/alrig:mcp` to give the stages Microsoft's AL compiler. Without one, verdicts say
`UNVERIFIED`, because nothing compiled the code. Before you run it:

- run `/alrig:scan` first — `/alrig:mcp` reads your app paths from the profile;
- have the .NET 8 runtime and the AL Language extension installed;
- restart the Claude Code session afterwards, so the new server's tools load.

**`--quick`** is one approval: you approve the contract, then it writes the code, builds,
reviews, and shows you the diff and the verdict together. It skips the design stage and runs
without subagents; if triage finds the change HIGH-risk it says so and runs normally instead. It still stops before review if the change touches a `hotspots`
area or the implementation came back `BLOCKED`.

## The adopt-in-place contract

These are guarantees, not intentions. They are the reason this is safe to hand to a colleague
mid-project.

1. Its entire configuration footprint is one file: **`.claude/alrig.json`**. The only other
   things it ever writes are the change you asked for, the spec documents described in
   guarantee 4 on the `product` tier, `.mcp.json` — which only `/alrig:mcp` writes, only
   on an explicit yes, and never by merging over an entry you already had — and dated
   secret-scan reports, only into a `security.reportsDir` that already exists.
2. It **never creates a directory layout in an existing app**, and never moves or renames
   anything. The one command that creates files from nothing, `/alrig:new`, works only in a
   directory that holds no app yet, edits no existing file, and writes only after you have seen
   every path and said yes.
3. Its tooling **never edits** `CLAUDE.md`, `README`, `app.json`, or any other file it did not
   create. The change you asked for is the one exception, and the approved spec bounds it: stage
   2 edits only the files that spec names — which may include `app.json` or the document where
   your project records claimed object IDs.
4. Spec and design documents are written **only where your profile already points**, and only on the
   `product` tier.
5. What cannot be determined is recorded as `null`, and the affected stage degrades **loudly**
   — reporting `UNVERIFIED` — rather than guessing.
6. **Uninstalling is deleting one JSON file** — two if you took the optional MCP setup.

It works on a repository with uncommitted changes, a non-standard layout, several apps, or no
documentation at all.

## Every kind of Business Central project

| Project | What it does differently |
|---|---|
| **Empty repository** | `/alrig:scan` writes nothing and points at `/alrig:new`, which scaffolds an app from your answers — never from defaults it invented. |
| **Per-tenant extension** | `customisation` tier: no subagents, inline contract, PTE cop. |
| **AppSource app** | AppSourceCop-aware review, breaking-change readiness, `/alrig:appsource`. Public surface counts as reachable. |
| **OnPrem** | Each app's `target` is profiled; baseline rules tagged **[Cloud]** do not bind it, and `/alrig:appsource` says it does not apply. |
| **Several apps, one repository** | In-repo dependency edges are profiled; builds run upstream first and rebuild everything downstream of a change. |
| **AL-Go or Azure DevOps** | CI is recorded, never run. Where builds happen only in CI, Microsoft's AL MCP server gives the stages a local compiler — or they say `UNVERIFIED`. |
| **Older runtimes** | Rules tagged *runtime N and later* do not bind an app below N. Nothing ever raises your runtime for you. |
| **AI features** | A `copilot` theme, and a HIGH triage signal for any call to a model. |

## Commands

| Command | What it does |
|---|---|
| `/alrig:design <request>` | Stage 0 — design a HIGH-complexity change before any spec. `go` runs it only when triage says HIGH. |
| `/alrig:scan` | Profile the repository, write or refresh `.claude/alrig.json`, report findings and gaps. Idempotent. |
| `/alrig:new [dir]` | Start an app in an empty repository or a new directory. Asks every project fact, shows every file, writes only on yes. |
| `/alrig:spec <request>` | Stage 1 — turn a request into a contract with checkable acceptance criteria. |
| `/alrig:implement [spec]` | Stage 2 — write the AL, run **your** build command, iterate to clean. |
| `/alrig:review [spec]` | Stage 3 — independent verification in a fresh context. |
| `/alrig:go <request>` | All three, chained, with a human gate between each. |
| `/alrig:check [range]` | The stage 3 checks over a diff with no spec behind it. No gate. |
| `/alrig:appsource [app]` | An AppSource submission readiness report. Never gates, never writes. |
| `/alrig:mcp` | Offer optional MCP servers — Microsoft's AL MCP server first — and write their configuration only if you say yes. |

### Scanning and release gates

| Skill | What it does |
|---|---|
| `/alrig:al-scan [app]` | Compile with every analyzer you run — CodeCop, AppSourceCop, UICop, PerTenantExtensionCop, and third-party ones such as LinterCop or ALCops that your settings declare — under your ruleset. Every diagnostic grouped by rule, and a check that the ruleset has not been weakened against a shared baseline. |
| `/alrig:secret-scan` | gitleaks over the working tree **and history**, redacted. Each finding triaged — rotate, move, or confirm it is fake — with where that secret should live instead. A dated report if you have given it a directory. |
| `/alrig:release-check [app]` | Version bumped, app `id` unchanged, objects inside their ranges, translations complete, secrets held in `SecretText`/`IsolatedStorage` and never in a table field, plus both scans. `READY`, `BLOCKED` or `UNVERIFIED`. |

All three read and report; none edits your code. They need PowerShell (Windows PowerShell 5.1
or PowerShell 7), the AL Language extension for the compiler, and gitleaks for a full secret
scan — without it a weaker built-in scan runs and says so.

**The write guard.** A hook blocks Claude from writing a credential literal, or an endpoint not
in `security.urlAllowlist`, into an `.al` file, and tells it where the value belongs instead.
Writes to any other file exit in the shell before PowerShell starts.

**Bring your own standard.** The plugin ships no ruleset. If your organisation keeps a shared
one — in its own repository, included by each app's ruleset — set
`security.rulesetBaseline` to it and `/alrig:al-scan` blocks on any rule a project lowered.

`--quick` and `--deep` override the tier for a single run; `--quick` also folds the
implementation gate into the final report, as described under **Start here**.

`/alrig:check` is the one to reach for on a repository where most changes did not come through
a spec. It runs everything stage 3 runs except the two checks that need a contract — acceptance
criteria and scope — and says so rather than reporting them as passed.

## Describe, don't prescribe

Comparable plugins initialise a project by *imposing* structure — a rules directory, a
generated `CLAUDE.md`, a plans folder. This one inverts that. It reads the repository as it
stands and records what it found in one file.

Where your project already has authority — `CONVENTIONS.md`, `ARCHITECTURE.md`, per-module
notes, an existing `CLAUDE.md` — the profile **records their paths**. It never copies their
content. That is three properties for the price of one:

- **Adoption** — nothing to restructure, so it can be added on any day of a project.
- **Tokens** — authority is read on demand by the stage that needs it, not injected per turn.
- **Correctness** — copied rules drift from their source and are then confidently wrong. A
  pointer cannot drift.

### What ships, and what is yours

| Ships with the plugin | Supplied by your project |
|---|---|
| The pipeline, its stages and gates | Object ID ranges, prefixes and affixes |
| The AL quality baseline — platform-level practice, true on every BC project | Publisher, app names, folder layout |
| The profile *schema* | Dependency names and where their source lives |
| Detection logic for filling the profile in | The build command |
| Review checks that are language- or platform-level | Which areas are sensitive (`hotspots`) |
| | Which APIs are banned here (`forbidden`) |
| | Which documents are authoritative |

**No customer name, no publisher, no ID range, no naming convention and no business rule is
bundled.** Everything in the right-hand column is discovered by `/alrig:scan` or typed by you,
and lives only in your own `.claude/alrig.json`. `tests/lint.mjs` enforces this by grepping
the whole repository, so it cannot erode over time.

### Your project wins

When your own authority contradicts the shipped baseline, **the project wins**, and the
reviewer states that it was overridden rather than silently conforming.

Generic Business Central advice is sometimes precisely wrong for a given project — a rounding
helper that is best practice platform-wide can be forbidden where a regulator requires
truncation. A plugin that cannot be overruled by the repository it runs in is a hazard in
exactly the projects that need it most.

## What it costs

**Almost nothing when idle.** No always-on rules, no injected context — only the one-line
command and skill descriptions Claude Code lists in every session. The one hook, the write
guard, adds no tokens and exits in the shell for every write that is not an `.al` file. The profile is read once per run by the stage that needs it; the quality baseline is fifteen reference files
behind an index, and a stage loads only the theme its change touches.

Subagent definitions **pin no model**, so a colleague on a smaller model stays on it and
nobody inherits a pinned model's cost. The `customisation` tier spawns no subagents at all.

The one exception is the one you opt into. An MCP server configured by `/alrig:mcp` *is*
always-on — that is the trade, and it is why the command states the cost before the benefit and
writes nothing without an explicit yes. Everything else here still costs almost nothing when idle, and
the pipeline works with no MCP at all: the stages check less and say so.

## Three things it insists on

**The warning gate is a delta, not a count.** Demanding zero warnings breaks instantly on a
brownfield repository that already has hundreds; demanding nothing destroys the discipline of
one that has none. Stage 2 captures the warning set before it touches anything and compares
after. No analyzer rule IDs are bundled — which cops run differs per project, so the codes come
from the compiler you actually run.

**Reachability is checked.** Every new object and public procedure must have a call path, a
subscription, or one of a closed list of exemptions. A complete, correct, reviewed and entirely
uncalled object passes every other mechanical check there is. The exemptions matter as much as
the check: event publishers, subscribers, `Install`/`Upgrade` codeunits, permission sets, API
pages and the public surface of an app others depend on are uncalled **by design**, and report
as `PUBLIC SURFACE` rather than as findings.

**Strictness is a setting, not a stance.** The profile's `policy` block splits findings into
blocking and advisory, and the defaults sit at the loose end: only build errors, `forbidden`
hits, unmet criteria and the warning delta stop the pipeline. `scope` and `reachability` are
advisory, because on a repository halfway through its life both are routinely *correct* —
adjacent fixes are normal, and an AppSource app publishes surface nothing in its own tree
calls. Nothing is switched off by this. Every category is still looked for, still found and
still reported in full; `policy` decides only what stops. Tightening it is one line of JSON,
and `/alrig:scan` never loosens it back.

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — the full design, and why each decision went the way it did.
- [`docs/PROFILE.md`](docs/PROFILE.md) — every profile field, its shape and its consequences.

## Licence

MIT. See [`LICENSE`](LICENSE).

The design stage is adapted from ALDC's `al-architect` (MIT); see
[`THIRD-PARTY-NOTICES.md`](plugins/alrig/THIRD-PARTY-NOTICES.md).
