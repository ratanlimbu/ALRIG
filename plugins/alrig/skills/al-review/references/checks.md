# Stage 3 checks, findings and verdict

Each check is **performed, not accepted.**

## Checks

1. **Re-run the build yourself**, by `build.provider` and in `dependsOn` order — the `warnings`
   theme of `alrig:al-conventions` says how. Do not trust a reported exit code, including one
   written a moment ago in this conversation.
2. **Recompute the warning delta** against the baseline, by the identity rule in the `warnings`
   theme. **No baseline available** (a fresh session, or `/alrig:check`): compare only the
   warnings located on lines the diff added or changed, and label the line `diff-scoped, no
   baseline`. That is approximate, and says so; it is not a reason for `UNVERIFIED`.
3. **Every acceptance criterion, one at a time** — `MET`, `NOT MET` or `UNVERIFIED`, each with
   file:line evidence. A criterion you could not check did not pass.
4. **`forbidden` patterns over the diff.** Every hit is a `forbidden` finding.
5. **Performance** (`performance`) — load the `performance` theme from `alrig:al-conventions`
   and check the diff against it. Slow AL compiles and passes tests; nothing else here catches it.
6. **Hotspots** (`hotspot`) — any `hotspots` glob the diff touches is flagged for human review
   whether or not you found anything wrong there.
7. **Reachability** (`reachability`) — every new object and public procedure needs a call path,
   a subscription, an interface implementation, or an exemption below. Follow the chain back to
   an entry point. Do not shorten this check: an uncalled object passes every other one.
8. **Scope** (`scope`) — anything in the diff that no criterion asked for. When the working tree
   held changes before this run, judge only the files this run touched.
9. **Tests** — if `tests.runCommand` is set, run it (once per test app — `apps[].isTest` — when
   it contains `{app}`) and report the result. A test app with no run command is `present, not
   run`. Never infer a test result.

**Project authority wins.** Where a document on the spec's `AUTHORITY` line (or, with no spec,
the profile's `authority` list) contradicts the shipped baseline, apply the project's rule and
list the override under `OVERRIDES`. Never report a finding the project's own rule permits.

### Public surface is not unreachable

Uncalled inside the repository **by design**. Report as `PUBLIC SURFACE`, not `UNREFERENCED`:

- `[IntegrationEvent]`, `[BusinessEvent]` and `[InternalEvent]` publishers
- `[EventSubscriber]` procedures, and `[Test]` and handler procedures
- codeunits with `Subtype = Install` or `Subtype = Upgrade`, or `TableNo = "Job Queue Entry"`
- pages and reports whose `UsageCategory` is set and not `None`
- a codeunit named by an enum value's `Implementation`
- `PermissionSet` and `PermissionSetExtension` objects
- pages with `PageType = API` and queries with `QueryType = API`
- procedures implementing an `interface` the object declares
- public procedures of an app that declares `internalsVisibleTo`, that another app in this
  repository depends on, or whose `appsource.target` is `appsource`

**The list is closed.** Anything new not on it is `UNREFERENCED` — fix by adding a caller or
removing it.

## Categories and policy

Tag every finding with one of nine categories, then read `policy` from the profile. `blockOn`
decides the verdict; `advisory` is reported in full and does not. No `policy` block: use the
defaults below and say so.

| Category | Default |
|---|---|
| `error` · `forbidden` · `criterion-not-met` · `warning-delta` | blocking |
| `scope` · `reachability` · `performance` · `hotspot` · `style` | advisory |

**Advisory is not silent** — every finding is reported at full detail. Never re-tag a finding to
change the outcome; if you think the policy is wrong, say so in `NOTES`.

## Out

One line per entry. No prose outside this shape.

```
BUILD        <exit code from YOUR run, and the command>
WARNINGS     <baseline -> after, recomputed | diff-scoped, no baseline | UNVERIFIED + reason>
TESTS        <run + result | present, not run | none present>
CRITERIA     <each: MET | NOT MET | UNVERIFIED — evidence | "no spec">
BLOCKING     <file:line  category  defect  how it fails, concretely>
ADVISORY     <same shape; "none" if none>
HOTSPOTS     <each hotspot glob touched>
REACHABILITY <each new object/procedure: call path, PUBLIC SURFACE, or UNREFERENCED>
OVERRIDES    <where project authority overrode the baseline>
VERDICT      BLOCKED | UNVERIFIED | VERIFIED
BECAUSE      <blocking findings first; then each check that could not run, and why>
NEXT         <the one action that moves this on>
NOTES        <anything the human must know; "none" if none>
```

## Verdict — first match wins

1. **`BLOCKED`** — any finding in a `blockOn` category stands, or a criterion is `NOT MET`. This
   holds even when another check could not run: you can block on what you did see. List the
   checks that could not run under `BECAUSE` as well.
2. **`UNVERIFIED`** — nothing blocking was found, but a check could not run: no build
   (`build.provider` null, or the build could not start), a criterion nothing could decide, or
   `policy.requireTests` is `true` and the tests were not run.
3. **`VERIFIED`** — every check ran, every criterion is `MET`, nothing blocking stands.

`NEXT` by verdict: `BLOCKED` → fix the blocking findings (by hand, or re-run stage 2 with them)
then `/alrig:review`. `UNVERIFIED` because nothing builds → `/alrig:mcp`, or set
`build.command`. `VERIFIED` → commit.

**Say what is true.** With `requireTests: false` a change can be `VERIFIED` while its tests never
ran — so `TESTS` is always reported, and "compiles and was reviewed" is never written as "passes".
