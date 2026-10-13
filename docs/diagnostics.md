# Diagnostic presentation

`gargamelle/diagnostics` formats existing `ContractError` values. It does not
validate JSON, decode values, run semantic checks, or invoke handlers.

```gleam
import gargamelle
import gargamelle/diagnostics as gargamelle_diagnostics
import gleam/io

pub fn main() {
  let contract = gargamelle.contract(gargamelle.array(gargamelle.text()))
  let assert Ok(json) = gargamelle.parse("[\"Brainy\", false]")
  let assert Error(error) = gargamelle.decode_contract(contract, json)
  io.println(gargamelle_diagnostics.summary(error, 5))
  let assert Ok(report) = gargamelle_diagnostics.to_json(error)
  io.println(gargamelle.to_string(report, gargamelle.Compact))
}
```

Output:

```text
"/1" ["string_type"]: Expected a string
{"errors":[{"branches":[],"category":"string_type","matches":[],"missing_key":null,"path":"/1"}],"kind":"structural"}
```

## Bounded summaries

`summary(error, max_details)` produces readable text with at most the requested
number of detail lines and an additional omission marker when details were left
out. The limit is clamped to 0–100. Union branch expansion stops at depth eight;
each line is limited to 160 graphemes. Paths, categories, and application messages
are quoted with JSON escaping, preventing embedded line breaks from creating
additional lines. These limits affect presentation, not validation or its error
collection. The original structured error remains available to the caller.

Union alternatives and semantic requirement headings count toward the detail
budget. Indices are zero-based and retain declaration order. A zero limit returns
only an omission marker for nonempty errors; an empty error produces empty text.
Unknown categories retain their category with the explanation `Constraint failed`.
Categories and message wording may evolve before 1.0. Applications should inspect
structured fields rather than parse summary text.

## Complete JSON reports

`to_json(error)` returns admitted JSON containing the complete diagnostic tree.
Structural reports contain `kind: "structural"` and an `errors` array; each error
retains its category, input JSON Pointer, optional missing key, matching alternative
indices, and indexed branch errors. Semantic reports contain `kind: "semantic"`
and a `requirements` array retaining indices, descriptions, and path/message
violations. The report does not invent schema locations or reference traces that
are absent from the original errors. It carries no acceptance certificate.

JSON reports are not truncated. Serializing large error trees has a cost
proportional to their size; use a bounded summary for routine display and retain
the original errors when complete serialization is unnecessary. Non-scalar strings
in application-authored diagnostics return an admission error.

Neither format includes submitted JSON values automatically. Application-authored
requirement descriptions and violation messages are included and may themselves
contain sensitive data; the formatter does not redact them. Field names and paths
can also contain sensitive identifiers. Applications decide which reports to retain
or expose.

For structural `decode` errors, wrap the list with `gargamelle.Structural(errors)`.
For `encoding.Contract(error)` failures, format the enclosed contract error.
Other encoding errors retain their typed reasons and output paths, described in
[Typed JSON encoding](encoding.html). See the
[provider loading and saving example](provider-roundtrip.html) for semantic
rejection on both sides of a boundary.
