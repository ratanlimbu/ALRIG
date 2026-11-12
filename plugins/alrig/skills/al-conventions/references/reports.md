# Reports: the dataset, the layout, and who prints what

A report is two things that fail differently. The **dataset** is AL and fails like AL — slowly,
on volume. The **layout** is a document that fails silently — a column that never appears, a
caption that never translates. Neither shows up in a build.

## Filter at the dataitem, not in the trigger

The database can only filter what it is told about before the read.

- Put fixed filters in `DataItemTableView`, user filters in `RequestFilterFields`, and parent–
  child joins in `DataItemLink`. All three reach the query.
- `CurrReport.Skip()` in `OnAfterGetRecord` still **reads every row** it skips. On a ledger
  table that is the whole ledger. Skip is for conditions the database cannot express.
- FlowFields the layout needs belong in the dataitem's `CalcFields`, not in a `CalcFields`
  call per record (see the `performance` theme).
- A dataitem used only to drive a loop of counters — `Integer` — needs explicit bounds. An
  unbounded `Integer` dataitem is an infinite report.

## Logic lives in the dataset, not in the layout

Compute totals, conditions and formatted values in AL and expose them as columns. Logic in a
Word field code, an RDLC expression or an Excel formula is invisible to review, untested, and
duplicated in every layout the report has. A layout should place values, not decide them.

## Layouts

Declare layouts in the `rendering` section — Word, RDLC and Excel side by side — and name the
default with `DefaultRenderingLayout`. Each layout type sees the same dataset; an Excel layout
sees it **flattened**, so a nested dataitem repeats its parent's columns on every row. Design
the dataset with that in mind if Excel is a target.

Text the layout prints — headings, labels — comes from the `labels` section or `IncludeCaption`
on columns, so it reaches the translation file. Text typed into the layout itself never
translates, and never raises a warning.

## Extending a report you do not own

A `reportextension` adds columns, dataitems, request-page fields and layouts to a base report.
It cannot remove anything, and **the base report's own layouts do not know your new columns** —
a column added without a layout that uses it is reachable by nothing. Ship the layout with the
extension, and say which layout a user must select.

## Which report prints a document

Document reports — invoices, orders, statements — are chosen by **report selections**, keyed
by the `Report Selection Usage` enum. Point the selection at your report, through setup or
install code, rather than replacing the base report everywhere. Substituting a report
globally through a subscriber is the bigger hammer: it changes every caller, including ones
you did not mean to touch. Verify any event you would subscribe to for it per the design
stage's symbol lookup — never from memory.

## Reachable, or not

A report with `UsageCategory` and `ApplicationArea` set is reachable from search; one without
is reachable only from an action or a report selection. Both are legitimate. A report with
neither, and no action, is reachable from nowhere — the review's reachability check applies.

`ProcessingOnly = true` reports are batch jobs with a request page. If they modify data, the
`correctness` theme's rules on commits and batch paths apply exactly as they do to a codeunit.
