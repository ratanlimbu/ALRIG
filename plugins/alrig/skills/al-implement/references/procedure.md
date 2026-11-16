# Stage 2 procedure

## 1. Baseline first

Load `alrig:al-conventions` and read its `warnings` theme: how to build for this
`build.provider`, which apps, in what order, how to compare warnings, the iteration limit, and
what to do when the baseline build fails. Then:

- Record `git status --porcelain`. Changes already present are baseline, not this change.
- **Run the build before touching anything** and keep the warning set.
- `build.provider` `null`, or the build cannot run (for example the MCP server is not
  connected): skip it, and your verdict is `UNVERIFIED` however the code turns out.
- The baseline build fails: stop, report `BASELINE FAILED` as the theme says, edit nothing.

## 2. Write the AL

Read **only the other themes this change touches**. Precedence, highest first:

1. The project's `forbidden` patterns — absolute.
2. The documents on the spec's `AUTHORITY` line.
3. The shipped AL baseline.

When 2 contradicts 3, **the project wins, and you record the override** under `OVERRIDES`.

Edit only the files the spec's `OBJECTS` names. Match the surrounding code's idiom, naming and
comment density. Claim object IDs by the project's own rule — `al_getnextobjectid` only where it
has none and the profile builds through `al-mcp` — and **edit the document that records claimed
IDs in the same change**.

## 3. Iterate to clean

Re-run the build. **Check the exit code before reading the warning list** — an error aborts the
build before the analyzers finish. Iterate, within the theme's limit, until errors are zero and
the delta satisfies `build.warningPolicy`:

| Policy | Fails on |
|---|---|
| `no-new` | any warning identity not in the baseline set |
| `zero` | any warning at all |
| `ignore` | errors only; the delta is still reported |

**Never suppress a warning to make the gate go green.** One you cannot fix is reported with its
reason. The profile's `policy` block governs stage 3's verdict, not this loop.

## 4. Tests

If `tests.runCommand` is set, run it (per test app when it contains `{app}`). A failing test is
blocking. If it is `null`, report `present, not run` or `none present` — **never infer a result**.
A test you changed to make pass is named in `NOTES`, with why.

## Out

One line per entry. No narration outside this shape.

```
FILES        <path — one line each, with what changed>
BUILD        <exit code, and the command actually run | BASELINE FAILED + first errors>
TESTS        <command, pass/fail counts | present, not run | none present>
ERRORS       <count; then each, file:line + message>
WARNINGS     <baseline -> after>
  NEW        <each warning identity not in the baseline>
  RESOLVED   <each baseline warning now gone>
IDS CLAIMED  <IDs taken, and where the claim is recorded>
OVERRIDES    <each place the project's authority overrode the baseline>
VERDICT      DONE | BLOCKED | UNVERIFIED
NOTES        <pre-existing working-tree changes, edited tests, anything else; "none" if none>
```

`DONE` — builds clean and the delta passes the policy. `BLOCKED` — errors or failing delta left
after the iteration limit, a failing test, or a spec too vague to locate. `UNVERIFIED` — nothing
could build, or the baseline failed.
