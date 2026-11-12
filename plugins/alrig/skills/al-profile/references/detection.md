# Detection order

Each step falls through to the next when it finds nothing. What no step finds is `null`.

## Apps

Glob `**/app.json`, excluding `.alpackages`, `.artifacts`, `.output`, `.snapshots`,
`node_modules`, `.git`, and any `out`/`bin` directory. Each match is one app. Its `path` is the
directory holding `app.json`, relative to the repository root.

From each `app.json`, record:

| Profile field | From |
|---|---|
| `name`, `idRanges` | the same keys (`idRanges` as `[[from, to], …]`) |
| `target` | `target`. **Absent means `"Cloud"`** — that is the platform default, not a guess |
| `runtime`, `application` | the same keys, as strings; `null` when absent |
| `dependsOn` | the `name` of every **other app in this repository** whose `id` appears in this app's `dependencies` — in-repo edges only, Microsoft and external apps excluded |
| `project` | the nearest ancestor directory holding `.AL-Go/settings.json`, relative to the root; `null` when there is none |

`dependencies[]` lists the non-Microsoft apps this repository depends on that are **not** apps in
it, each with a `sourcePath` if their source is on disk and `null` otherwise. An app in this
repository is a `dependsOn` edge, never a `dependencies[]` entry.

`dependsOn` is what lets a stage build a multi-app change in dependency order and rebuild the
apps downstream of the one it touched. A cycle is a profile error: report it, record no edges
for the apps in it, and do not guess an order.

**No apps at all** is not a failure of detection — it is an empty repository. Write nothing,
say so, and recommend `/alrig:new`.

## Test apps

An app is a test app if it depends on a Microsoft test library (`Library Assert`, `Any`,
`Library Variable Storage`, `Tests-TestLibraries`), or its `.al` files contain a codeunit with
`Subtype = Test`, or its name matches `*Test*`. (`app.json`'s `target` takes only `Cloud` and
`OnPrem`, so it says nothing about tests.)

## Prefix / affix

`AppSourceCop.json`'s `mandatoryPrefix` or `mandatoryAffixes` if present. Otherwise derive it:
list the quoted object names across `.al` files, take the most common leading token, and only
record it if it covers a clear majority. A prefix you had to squint at is `null`.

## Analyzers

`al.codeAnalyzers` in `.vscode/settings.json` (at the root, beside each app, or in a
`*.code-workspace` file's `settings`), plus the presence of `AppSourceCop.json` or
`PerTenantExtensionCop.json`, plus the cops an AL-Go settings file switches on
(`enableCodeCop`, `enableUICop`, `enableAppSourceCop`, `enablePerTenantExtensionCop`). Record
the names.
**Record no analyzer rule IDs** — see `al-conventions`, theme `warnings`.

## CI

Record where the project's builds actually run, because on many repositories that is the only
place they run:

| Found | `ci.system` |
|---|---|
| `.github/AL-Go-Settings.json` or any `.AL-Go/settings.json` | `al-go` |
| `azure-pipelines.yml`, or a `.azure-pipelines/` or `.pipelines/` directory | `azure-pipelines` |
| a `.github/workflows/*.yml` that names an AL compiler, `BcContainerHelper` or `Run-AlPipeline` | `github-actions` |
| none of these | `null` |

`ci.path` is the file or directory found. CI is **recorded, never run**: a pipeline is not a
local build command, and reading one into `build.command` is guessing.

## Build

`build.provider` is one of `al-mcp`, `command` or `null`. Candidates, in order:

1. **The Microsoft AL MCP server** — `.mcp.json` has a server keyed **`al`** whose arguments
   contain `launchmcpserver`. Candidate provider `al-mcp`. A server running `launchmcpserver`
   under any other key is reported in `GAPS`: the plugin's subagents are granted the `al`
   server's tools by name, so another key leaves them unable to build.
2. An AL build task in `.vscode/tasks.json`.
3. A `build.ps1` / `build.cmd` / `build.sh` at the repository root.
4. A root script calling `Compile-AppInBcContainer` or `Run-AlPipeline` (BcContainerHelper).
5. A resolvable `alc.exe`, or the `al` .NET tool on the path.

Otherwise `null`, and when `ci.system` is set, say in `GAPS` that this repository builds only
in CI, so every local verdict will be `UNVERIFIED` until `/alrig:mcp` or a local command is set.

**Multi-app.** When a candidate builds one app by path, propose it with the `{app}`
placeholder — the stages substitute each app's `path` and run it once per app, in `dependsOn`
order. A candidate that already builds every app needs no placeholder.

**Always show the candidate to the human and get confirmation before writing it.** Build
invocations go stale — compiler paths move between extension versions — so this field is
never inferred silently, even when a candidate looks obvious.

## Tests

Whether a test app exists and its path, then `tests.runCommand`, in order: a task in
`.vscode/tasks.json` whose label or command names tests; an `al-test-runner.*` block in
`.vscode/settings.json`; a `Run-AlTests` / `Invoke-ALTestRunner` / `Run-TestsInBcContainer` /
`al runtests` call in a script at the repository root; otherwise `null`. `{app}` works here as
it does for the build.

**Confirm it with the human exactly as you confirm `build.command`, and for the same reason** —
a stale test invocation fails in a way that reads like a broken test suite and is not. AL tests
run against a Business Central service; a repository whose tests run only in CI has no local
command, and that is `null`, not a guess at what the pipeline does.

## AppSource

`appsource.target` is `appsource` when `AppSourceCop.json` exists or `AppSourceCop` is in the
analyzer list, `pte` when `PerTenantExtensionCop.json` or its cop is, and `null` when neither
says. An app can be heading for AppSource without either file; `null` means undetermined, not
"no". An app whose `target` is `OnPrem` cannot ship to AppSource whatever this field says —
`apps[].target` already records that, so do not encode it here a second time.

`appsource.previousVersionPath` is the previously published `.app`, without which no
breaking-change analysis can run. Look in `.alpackages` and in `al.packageCachePath` for a
package matching this app's publisher and name at a lower version. **Confirm the candidate with
the human** — a stale previous version silently compares against the wrong thing. Otherwise
`null`.

## Authority documents

`CLAUDE.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `CONTRIBUTING.md`, and any
per-folder architecture notes. Record **paths in precedence order**, `CLAUDE.md` first.
**Record paths, never content.** A copied rule drifts from its source and is then confidently
wrong; a pointer cannot drift.

## Spec directory

An existing `docs/specs`, then `docs/adr`, then `docs/`. If none exists, set `specs.mode` to
`inline` and `specs.dir` to `null`. **Never create the directory.**

## Tier

`product` if any of: more than one app; a test app is present; a dependency on a non-Microsoft
app; more than 100 `.al` files. Otherwise `customisation`.

## Hotspots and forbidden

Leave both `[]`. They are the human's to fill in; a small project that leaves them empty loses
nothing. Offer one line saying what they are for, and move on.
