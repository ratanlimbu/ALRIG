# Warnings: a delta gate, not a count

**The gate is the change in warnings, not the total.**

| `build.warningPolicy` | Fails on | Suits |
|---|---|---|
| `no-new` (default) | any warning not in the baseline set | any repository, on any day |
| `zero` | any warning at all | a repository that already holds a true zero |
| `ignore` | errors only — the delta is still reported | a project not ready to care yet |

## The baseline must be captured first

Run the build **before touching anything** and keep the warning set. A delta cannot be
reconstructed from a build you ran only at the end — that gives you the total, which is the
number this gate deliberately ignores.

Compare by identity, not by count. `47 -> 47` hides one warning fixed and a different one
introduced. **Identity is (file, rule ID, message with line and column numbers removed)**,
compared as counts per identity. A line number is not identity: inserting code above an old
warning moves it without making it new. An identity whose count rose is `NEW`; one whose count
fell is `RESOLVED`.

**If the baseline build fails**, stop before editing anything. Its warning list is truncated,
so every later warning would look new. Report `BASELINE FAILED` with the first five errors. If
they are missing-symbol errors and the provider is `al-mcp`, offer `al_downloadsymbols` (below)
and rebuild. Otherwise the delta is `UNVERIFIED — baseline broken before this change`, and the
human decides whether to continue. Never fix pre-existing errors outside the spec's file list.

**Working-tree changes that predate this run** (`git status --porcelain` at the start) are part
of the baseline, not of the change. Say they exist at the gate, and review only the files this
run touched.

## Running the build

The profile's `build.provider` says how. Whichever it is, the rest of this theme is unchanged.

- **`command`** — run `build.command` from `build.cwd`. If it contains `{app}`, run it once per
  app with that app's `path` substituted.
- **`al-mcp`** — call the `al` server's `al_compile` tool with `onlyErrors` set to false, code
  analysis on, and the analyzers the profile records. Set the diagnostics cap explicitly and
  high. **A result that returns exactly as many diagnostics as the cap is truncated**: the
  baseline built from it is incomplete, so the warning delta is `UNVERIFIED`, not a number.
  `al_build`, which also writes the `.app`, is for when a package is the point. If the server
  reports missing symbols, `al_downloadsymbols` fetches them into `.alpackages` — a cache, but
  still a write: ask once before running it.
- **`null`** — no build. The verdict is `UNVERIFIED`, whatever the code looks like.

**Several apps.** Build the apps the change touches **and every app whose `dependsOn` reaches
them**, upstream first. A change that compiles in its own app and breaks the app built on top
of it is the multi-app failure this exists to catch. Capture the baseline over the same set.

The build exit code, or the tool's error count, is read before any warning — next section.

## No analyzer IDs are bundled

Rule codes come from the compiler the project actually runs, never from this plugin.

## Iteration limit

At most **five** builds after the baseline. Stop sooner when two builds in a row leave the same
error and new-warning set — another attempt will not change it. Either way the result is
`BLOCKED`, listing what remains and what you tried.

## Check the exit code before reading the warning list

**An error aborts the build before the analyzers finish.** A short warning list after a failed
build is not good news; it is a truncated list. Read the exit code first, every time, and
never report a warning count from a build that did not complete.

## A warning is a finding, not lint

The ones that matter most read as pedantry:

- An unused variable is often a removed feature that left its declaration behind, or a
  dependency someone meant to call and did not.
- An unused parameter on a public procedure is a contract nobody is honouring.
- A shadowed name is a bug waiting for the two meanings to diverge.
- A missing `ApplicationArea` is an object nobody can reach.

Each of those compiles, ships and does nothing visible. That is what makes them worth reading.

## Never suppress to make a gate green

No `#pragma warning disable`, no suppression file entry, no rule downgraded in the ruleset,
to get past this gate. If new code cannot be made warning-free, **report the warning with the
reason** and let the human decide.

A suppression added to pass a gate is a defect in its own right, and it is invisible in every
later build — which is precisely why it is tempting.

## Analyzer coverage is a project decision

If the profile records no analyzers, say so in the report. A build with no cops running
produces a clean warning list that means nothing, and a `no-new` gate over it is theatre.
That is a finding about the project's setup, not about the change — report it once, do not
fix it, and do not edit the project's settings to turn cops on.
