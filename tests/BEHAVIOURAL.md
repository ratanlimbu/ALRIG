# Behavioural tests

`lint.mjs` is structural and scripted. These are behavioural: they need a Claude Code session
with the plugin installed, because what is under test is what `/alrig:scan` actually does.

Run them from a session opened **in the fixture directory**, not in this repository.

## Setup

```
/plugin marketplace add <path to this repo>
/plugin install alrig
```

Copy the fixture somewhere outside this repository first — the tests assert on `git status`,
and a fixture inside a working tree gives a misleading answer:

```bash
cp -r tests/fixtures/tiny-pte /tmp/bp-fixture && cd /tmp/bp-fixture && git init -q && git add -A && git commit -qm base
```

## Test 1 — the profile matches the golden file

Run `/alrig:scan` in the fixture, then compare what it wrote with the golden file:

```bash
node <path to this repo>/tests/profile-diff.mjs .claude/alrig.json expected-profile.json
```

It prints `profile: MATCH` and exits 0, or names every differing path as
`path  actual -> expected` and exits 1. Read the paths rather than the verdict — the point of a
golden file is telling you what moved, and a bare MATCH/DIFFERS makes you diff it by eye
anyway.

This used to be a `JSON.stringify` snippet inline in this file. The array form of its replacer
is an allowlist applied at **every** level, so every nested object came out empty and the
comparison silently ignored `build.command`, `policy.*`, `appsource.*`, `tests.*` and
`apps[].prefix` — a profile with a wrong build command compared equal. It is a script now, and
`lint.mjs` self-tests it against deliberately corrupted profiles, because a checker that cannot
fail is indistinguishable from one that passes.

| Fixture | Asserts |
|---|---|
| `tiny-pte` | `tier: customisation` · one app · prefix derived from object names, since there is no `AppSourceCop.json` · `build.command: null`, because nothing is detectable · `authority: []` — a repository with no documentation at all · `specs.mode: inline`, and **no `docs/` directory created** |
| `multi-app-product` | `tier: product`, selected by the second app · the test app detected by its `Library Assert` dependency **and** by its `Subtype = Test` codeunit · prefix `FFS` from `AppSourceCop.json`, not derived · `build.command` taken from the `tasks.json` AL build task **and confirmed at the prompt** · `authority` in precedence order, `CLAUDE.md` before `CONVENTIONS.md` · `specs.dir: docs/specs`, because it already exists |
| `al-go-onprem` | AL-Go: `ci.system: al-go` from `.github/AL-Go-Settings.json` · each app's `project` from its `.AL-Go/settings.json` · `target: OnPrem` on all three · `dependsOn` edges core → field service → test, and **`dependencies: []`**, because an in-repo app is an edge, not a dependency · analyzers from AL-Go's `enableCodeCop`/`enableUICop` · `build.provider: null` **and a `GAPS` line saying the repository builds only in CI** · `appsource.target: null` |

Every fixture also asserts:

- `policy` — the defaults written verbatim, with `scope`, `reachability`, `performance`,
  `hotspot` and `style` advisory and `requireTests: false`. `policy` is the one block `scan`
  must **not** detect; a strictness setting inferred from a repository's current state would
  ratchet a project tighter the cleaner it got.
- `appsource.target` — `pte` for `tiny-pte` from `PerTenantExtensionCop`, `appsource` for
  `multi-app-product` from its `AppSourceCop.json`.
- `appsource.previousVersionPath: null` and `tests.runCommand: null` in both. Neither fixture
  has a previous `.app` or a test task, so both must come back `null` — **a detection step that
  finds nothing must write `null`, not omit the field**, or the profile's shape changes with
  the repository and nothing downstream can rely on it.

`multi-app-product` also tests the confirmation gate: `scan` must **ask** before writing
`build.command`. A run that writes it without asking fails this test even if the value is
right.

## Test 2 — the footprint is one file

This is guarantee 2 of the adopt-in-place contract, and the one most likely to regress.

```bash
git status --porcelain
```

Must show `?? .claude/` and **nothing else**. No new directory, no touched `app.json`, no
generated `CLAUDE.md`, no reformatted file.

Then the before-and-after tree diff, which catches a file rewritten in place with identical
content but different line endings:

```bash
# before /alrig:scan
find . -path ./.git -prune -o -type f -print | sort > /tmp/before.txt
md5sum $(find . -path ./.git -prune -o -type f -print) | sort > /tmp/before.md5
# after
find . -path ./.git -prune -o -type f -print | sort > /tmp/after.txt
md5sum $(find . -path ./.git -prune -o -type f -print) | sort > /tmp/after.md5
diff /tmp/before.txt /tmp/after.txt   # only .claude/alrig.json may be added
diff /tmp/before.md5 /tmp/after.md5   # no existing file may have changed hash
```

## Test 3 — line endings survive

The fixture `.al` files are stored CRLF on purpose, matching real AL repositories, and
`.gitattributes` marks them `-text` so git does not normalise them away.

After any command that edits AL in a fixture, every untouched file must still be CRLF and an
edited file must not have been silently converted:

```bash
for f in $(find . -name '*.al'); do
  printf '%-60s ' "$f"
  grep -qU $'\r' "$f" && echo CRLF || echo 'LF  <-- line endings were rewritten'
done
```

A scripted edit that rewrites a whole file through a naive read-modify-write converts every
line ending in it. The diff then shows the entire file as changed, and the real change is
invisible inside it.

## Test 4 — rescan is idempotent and does not clobber

Run `/alrig:scan` a second time with no changes: it must report no differences and write
nothing.

Then hand-edit one field — set `build.warningPolicy` to `zero` — and run it again. It must
**show** the difference and **ask**, not overwrite. Accepting nothing must leave the file
byte-identical.

## Test 5 — a tightened policy survives a rescan

Move `scope` from `policy.advisory` to `policy.blockOn` by hand, then run `/alrig:scan` again.

`policy` must not appear in the proposed-changes list at all — not as a difference, not as a
suggestion, not as a question. A rescan that re-proposes the defaults over a project's own
settings quietly loosens exactly the projects that had tightened, and it does it at the moment
nobody is reading carefully.

The one thing it may say: if the category vocabulary has grown since the profile was written,
it names the categories that sit in neither list and asks where they go.

## Test 6 — the design footprint

On `multi-app-product` (`product` tier, `specs.dir: docs/specs`), after `/alrig:scan`:

1. Run `/alrig:design add a field to sales orders that flows to posted sales invoices and is
   sent to an external service on posting`.
2. Triage must say **HIGH** and name a signal (document → posted document transfer, or
   external integration). Approve the design and the slug.
3. `git status --porcelain` must show `.claude/` and exactly one new file,
   `docs/specs/<slug>.design.md`, and nothing else. The file has `**Status:** Approved`, at
   least three `### TD-` headings, and no 5–8 digit number. No `SymbolReference.json` anywhere
   in the tree.
4. Run the same command again with the same slug. It must **not** overwrite the file: it shows
   what differs and asks, or offers `<slug>.design.v2.md`.
5. Variant: delete `docs/specs` and repeat. The design must come back **inline**, with a line
   saying the directory no longer exists; `docs/specs` must **not** be recreated.

On `tiny-pte` (`customisation`), the same request: inline design, `--deep` recommended exactly
once, `git status --porcelain` shows only `.claude/`.

## Test 7 — triage routes

On `tiny-pte`, via `/alrig:go`, stopping at the first gate each time:

1. `add a description field to the bin helper` → **LOW**, no design stage.
2. Add `"**/src/**"` to `hotspots` in `.claude/alrig.json` by hand, then repeat case 1 →
   **MEDIUM** (hotspot), no design stage.
3. `add the same field to sales orders and posted sales invoices` → **HIGH**, naming the
   `TransferFields` signal; the design gate appears before any spec.
4. Run `/alrig:design` with a request triaged HIGH on a weak signal, answer so that only one
   decision is genuine → the stage must say it was not HIGH and hand to `/alrig:spec`, with no
   padded TD entries.

## Test 8 — symbol verification picks the right package

Needs a session on a machine with real symbol packages. In a scratch copy of
`multi-app-product` **outside this repository** (as in Setup), create `app/.alpackages/` and
copy in **two** Base Application packages of different versions whose majors are at or above
the app's `application` floor.

1. Run `/alrig:design` with a request that subscribes to a sales-posting event that exists in
   both.
2. The design's **Symbols verified** table must name the event, **its owning codeunit** (from a
   structured parse, not a text match), the **lower** package as the floor version checked and
   the **higher** as the obsolescence check. If neither Node nor Python is installed, the entry
   must read *found, owner unconfirmed* instead.
3. Repeat with a request that relies on a method carrying an `Obsolete` attribute in the higher
   package → it must appear as a decision with alternatives, not a pass.
4. Remove `.alpackages/` and repeat step 1 → the event is listed under `UNVERIFIED`, with the
   reason and a single mention of `/alrig:mcp`.
5. `git status --porcelain` shows no extracted file inside the repository at any point.

## Test 9 — an empty repository is scaffolded, never guessed

On `empty-repo`:

1. `/alrig:scan` writes **nothing** — `git status --porcelain` is empty — and recommends
   `/alrig:new`.
2. `/alrig:new app`. It must **ask** for distribution, name, publisher, brief, ID range, affix,
   `application`/`platform`/`runtime`, test app and namespaces, offering no invented value as
   settled. Answer: per-tenant extension, a test app in `test`.
3. Before writing it lists every path and its contents, and stops. Answer *no*:
   `git status --porcelain` is still empty.
4. Repeat and answer *yes*. `git status --porcelain` shows exactly `app/`, `test/`,
   `.vscode/settings.json`, `.gitignore` and — after the profile step asks — `.claude/`.
   No `CLAUDE.md`, no `README` change, no `launch.json`, no workflow file.
5. Both `app.json` files carry a GUID `id` that differs from every GUID in this repository;
   the test app depends on the main app; the main app's `internalsVisibleTo` names the test
   app; **no Microsoft test library is listed**, and the report says how to add them.
6. `/alrig:new app` again → refused, recommending `/alrig:scan`.
7. On `al-go-onprem`, `/alrig:new extra` → recommends AL-Go's *Create a new app* workflow
   before doing anything.

## Test 10 — target and runtime decide which rules bind

On `al-go-onprem`, after `/alrig:scan`:

1. Add a procedure to `fieldservice/app` that uses a .NET type, then run `/alrig:check`. No
   finding cites the **[Cloud]** sections of the `integration` theme; the report says the
   section was skipped because the app's target is `OnPrem`.
2. `/alrig:appsource` says once per app that an `OnPrem` app does not submit, and reports no
   manifest gaps for it.
3. Edit `tiny-pte/app/app.json` to `"runtime": "10.0"` and rescan. A change that would be told
   to use `ReadIsolation` (*runtime 11.0 and later*) is not told to; the skip is stated.

## Test 11 — multi-app builds run in dependency order

On `al-go-onprem`, set `build.provider: "command"` and a `build.command` containing `{app}`
by hand (any command that echoes its argument will do). Change `core/app`, then
`/alrig:check`: the build runs for `core/app`, then `fieldservice/app`, then
`fieldservice/test` — the touched app and everything downstream of it, upstream first. Change
only `fieldservice/test`: the build runs for it alone.

## Test 12 — MCP setup writes only what was approved

1. `/alrig:mcp --show` → prints the Microsoft AL MCP entry under the key `al`, with arguments
   taken from the installed binary's own `launchmcpserver --help`, and changes nothing.
2. With an `.mcp.json` holding an unrelated server, accept only the `al` entry → the unrelated
   entry is byte-identical afterwards, and `build.provider` changes only after its own yes.
3. Register the server under another key by hand, rescan → `GAPS` says the subagents cannot use
   it under that key; nothing is renamed.

## Test 13 — a version 1 profile upgrades by asking

Write the version 1 profile from this repository's history (`git show
b9b3f7f:tests/fixtures/tiny-pte/expected-profile.json`, the last commit on schema 1) to
`.claude/bp-al.json` — the plugin's former name — in a `tiny-pte` copy, with `policy.blockOn`
tightened by hand. Rescan: it offers to **move** the file to `.claude/alrig.json` (afterwards
only the new file exists), then
each schema 2 field is proposed as `<absent> -> value` and asked about; `version` becomes `2`
only once all are answered; `policy` is untouched and not proposed.

## Test 14 — `--quick` is one approval, except where it must not be

On `tiny-pte`, after `/alrig:scan`:

1. `/alrig:go --quick add a description field to the bin helper` → no triage line, one stop
   at the contract. Approve it. The run continues through implementation **and** review
   without stopping, and ends with one report holding the diff, build, warning delta and
   verdict. No subagent is started.
2. Add `"**/src/**"` to `hotspots` and repeat → the contract shows `HOTSPOTS HIT`, and the run
   **stops after implementation** as without `--quick`.
3. Add a `forbidden` pattern the change cannot avoid, so stage 2 returns `BLOCKED` → the run
   stops there and does not review.
