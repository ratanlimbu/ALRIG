# Copilot: calling a model from AL

A model's answer is **untrusted input that sounds confident**. Everything below follows from
treating it that way. It compiles, it demos well, and it fails in production on the one record
whose description said something the prompt did not expect.

The platform modules named here — the `Copilot Capability` and `Azure OpenAI` codeunits and
their `AOAI` companions — change between versions. **Verify each procedure you use against the
target version's symbols** (the design stage's symbol lookup) rather than from this file.

## Register the capability, and respect its switch

A feature that calls a model is a **Copilot capability**: an enum value extending
`Copilot Capability`, registered from install and upgrade code if it is not registered already.
Registration is what puts the feature on the administrator's Copilot page — where it can be
**switched off**. Check that the capability is active before offering the action, and hide or
disable the action when it is not. A feature that calls the model regardless has taken a
decision that belonged to the customer's administrator.

## Calls go through the platform module

Call the model through the `Azure OpenAI` codeunit, with the capability set on it, rather than
hand-building an `HttpClient` request. The module carries the capability check, the telemetry
and the platform's own safety handling; a hand-built call carries none of them.

- Authorisation to your own Azure OpenAI resource uses a key that is a secret — `SecretText`,
  isolated storage, never a literal (see the `integration` theme).
- Check the operation response for success before reading the result. A throttled or filtered
  call is a normal outcome, not an exception path.

## The human approves before anything is saved

Model output is a **proposal**. Present it in a `PromptDialog` page, let the user edit or
discard it, and write to the database only on their confirmation. Label generated content as
AI-generated. A model that writes straight into posted or posting data has taken the one
decision AL cannot take back.

## Prompts are built from untrusted data

Record data — a description, an email body, an imported line — can contain instructions.

- System instructions go in the system message; record data goes in user messages, clearly
  delimited, and is never concatenated into the instructions.
- **Validate every value the model returns** against the database before using it: an item
  number exists, an amount is in range, a date parses. A model asked for a customer number will
  invent a plausible one.
- When the model calls functions, the arguments it supplies are untrusted exactly as its text
  is. Validate them, and never expose a function that writes without the human's approval.
- Ask for structured output (JSON mode) for anything the code parses, keep the temperature low
  for extraction, and treat malformed output as an expected branch with a readable message.

## Data leaving the tenant

A prompt sends data to a model service. Send only what the task needs, and check the
classification of every field you include (see the `privacy` theme): personal data in a prompt
is personal data leaving the tenant. The administrator's settings on data movement across
geographies decide whether the call may happen at all; respect the platform's refusal.

Telemetry follows its usual rule: no prompt or completion text, because both carry customer
content.

## Testing

Do not assert on a model's wording — it changes. Test the code around the call: the prompt a
given record produces, the parsing of a recorded response, the validation that rejects a bad
one, and the behaviour when the capability is inactive. Quality of the model's answers is an
evaluation, run with an evaluation dataset, not a unit test.
