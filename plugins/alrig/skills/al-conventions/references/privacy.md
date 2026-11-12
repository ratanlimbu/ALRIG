# Privacy: what a field holds, who sees it, and how long it stays

Business Central decides what may leave a tenant, appear in telemetry, or be exported for a data
subject request by **the classification on each field**. A field classified wrongly is not a
compile problem; it is personal data flowing somewhere it should not, with nothing to say so.

## Every field is classified, deliberately

Set `DataClassification` on every table field, or once on the table and override it per field.
The values say what kind of data it is:

| Value | Holds |
|---|---|
| `CustomerContent` | content the customer's users created — descriptions, notes, documents |
| `EndUserIdentifiableInformation` | anything that identifies a person — names, emails, phone numbers |
| `EndUserPseudonymousIdentifiers` | an identifier standing in for a person — a user security ID |
| `AccountData` | the customer's billing and subscription data |
| `OrganizationIdentifiableInformation` | identifies the tenant organisation rather than a person |
| `SystemMetadata` | data the system generates that identifies nobody — timestamps, status codes |

`ToBeClassified` means *nobody decided yet*. It compiles and ships, and it is a gap: report it
as a `correctness` finding on any new field, and `/alrig:appsource` reports it as a submission
gap. **Classify by what the field can hold, not what it usually holds.** A free-text
`Description` that users routinely type a contact's name into is `CustomerContent` at least.

`SystemMetadata` is the classification most often claimed wrongly, because it is the one that
lets data go anywhere. A field is system metadata only when no user can put a person into it.

## Data does not lose its classification by being copied

Concatenating a customer name into a log message, a `Description`, a telemetry dimension or an
error text moves `EndUserIdentifiableInformation` into a place classified as something else.
The rule follows the data: telemetry carries no customer or personal data at all (see the
`telemetry` theme), and a log table that stores names is classified as storing names.

## Keep what you need, for as long as you need it

A table that only grows — a log, an integration journal, an archive — is a retention decision
whether or not anyone made it. Decide how long its rows matter and say so in the design:

- Register the table with the system **Retention Policy** feature from your install and upgrade
  code, so an administrator can set and enforce a period. Verify the registration API against
  the target version's symbols before relying on it.
- Store the minimum: an identifier that resolves to the person, not a copy of their details.
- Personal data in a table that has no retention story is the finding, even if nothing reads it.

## Company and tenant boundaries

`DataPerCompany = false` makes a table's rows visible from every company in the tenant. That is
a privacy decision as much as a design one — data entered in one legal entity becomes readable
in another — and like every `DataPerCompany` choice it cannot change after release.

## Secrets and the debugger

Secrets are covered in the `integration` theme. One addition belongs here: a procedure that
handles a secret or bulk personal data can be marked `[NonDebuggable]`, so a debugging session
cannot read its variables. For an app that ships to other tenants, `resourceExposurePolicy` in
`app.json` decides whether partners can debug it or download its source — a deliberate,
commercial choice, made once and recorded, never left at a template's default.
