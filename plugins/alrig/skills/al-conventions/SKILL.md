---
name: al-conventions
description: The AL quality baseline — platform-level Business Central practice for performance, warning discipline, correctness, extension-model judgement, testing, events, APIs, integration, upgrade, permissions, pages, telemetry, privacy, reports and Copilot. An index of fifteen themes, each loaded only when the work touches it.
version: 0.2.0
allowed-tools: Read
---

# The AL quality baseline

Platform-level knowledge — true on every Business Central project, independent of customer,
publisher or domain. **The plugin ships this; your project ships everything specific.**

## Precedence

This baseline **yields** to the project's own authority documents and to the `forbidden`
patterns in `.claude/alrig.json`. When they contradict it, the project wins and you record
that it overrode the baseline. A plugin that cannot be overruled by the repository it runs in
is a hazard in exactly the projects that need it most.

## Applicability — read the app before the rule

A rule tagged **[Cloud]** does not bind an app whose profile `target` is `OnPrem`, and
**[OnPrem]** the reverse. A rule tagged *runtime N and later* does not bind an app whose
`runtime` is lower. Skip such a rule, and say you skipped it and why. **Never raise an app's
`runtime` or change its `target` to make a rule apply** — that is the human's decision. The
compiler decides which language features exist: when a build runs, believe it over this file.

## Themes — read only what your change touches

| Theme | Read it when | File |
|---|---|---|
| **performance** | the change reads, filters, loops over or aggregates records; touches a page trigger that fires per row; or adds a key | `references/performance.md` |
| **warnings** | you are about to run a build (how, per `build.provider`), interpret its output, or are tempted to suppress something | `references/warnings.md` |
| **correctness** | the change adds an object, user-facing text, validation, a subscriber, a batch path, or alters persisted shape | `references/correctness.md` |
| **extension-model** | the change adds a table or table extension, alters something others subscribe to, or spans an app boundary | `references/extension-model.md` |
| **testing** | the change adds or edits a test, or you are deciding what a test would have to assert to be worth writing | `references/testing.md` |
| **events** | the change publishes an event, subscribes to one, or puts logic inside a subscriber | `references/events.md` |
| **api** | the change adds or alters an API page, a bound action, or anything else a caller outside Business Central reaches | `references/api.md` |
| **integration** | the change calls out of Business Central, stores or uses a secret, authenticates to anything, or moves work into the background (Job Queue, task, session) | `references/integration.md` |
| **upgrade** | the change obsoletes anything, alters persisted shape on an app that has already shipped, or touches an install or upgrade codeunit | `references/upgrade.md` |
| **permissions** | the change adds any object, or you are designing or extending a permission set | `references/permissions.md` |
| **pages** | the change adds or extends a page, an action or a control, or puts logic in a page trigger | `references/pages.md` |
| **telemetry** | the change adds an error path worth diagnosing in production, or you are deciding what signal to emit | `references/telemetry.md` |
| **privacy** | the change adds a table field, stores anything about a person, or keeps data that should not live forever | `references/privacy.md` |
| **reports** | the change adds or extends a report, a layout, or a document's report selection | `references/reports.md` |
| **copilot** | the change calls an AI model, adds a Copilot capability, or builds a prompt from data | `references/copilot.md` |

**Read one. Read two if the change genuinely spans them. Never read the set** — the index
exists so their bodies stay out of context until a branch reaches for one. Fifteen themes is a
menu, not a reading list; a change that appears to need most of them is a change that should
have been more than one change.

`correctness` and `extension-model` remain the two most often skipped and most often needed.
If the change adds an object or alters persisted shape, one of them applies whatever else does.

Each file is a checklist with the reason attached. The reason is what makes it usable: a rule
you can only apply by pattern-matching is a rule you will apply in the wrong place.
