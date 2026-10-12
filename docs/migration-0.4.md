# Migrating to 0.4.0

Existing 0.3.0 decoding and schema APIs continue to work. The required `Compact`
or `Pretty` argument to `to_string` and `schema_string` is unchanged.

## Component boundaries

`Boundary(a, response)` binds a definition to a private handler receiving decoded
`a` and original `Json`. Construct it with `boundary`, inspect the stored contract
with `boundary_definition`, and submit JSON with `forward`. Decoding occurs once
before a successful handler invocation.

`JsonBoundary(a, response)` serves handlers that need only verified JSON. Construct
it with `json_boundary`, inspect it with `json_boundary_definition`, and submit
admitted JSON with `forward_json`. It validates once without conversion and invokes
the handler with `VerifiedJson(a)` only on success. The receiving definition is
authoritative; another contract's certificate cannot bypass this check.

`verify(definition, json)` creates a certificate independently. Use `verified_json`
and `verified_definition` to retrieve its original JSON and actual checked contract.
Certificates retain no decoded value. The parameter `a` describes a definition's
output type, not its identity or constraints. Boundary handlers returning `Result`
produce nested results; callback exceptions remain operational failures.

See [Verified JSON boundaries](boundaries.html) for complete examples.

## Added schema vocabulary

- `examples` and standalone `default` attach admitted JSON metadata, which need
  not satisfy the associated definition. Neither changes decoding. `defaulted`
  remains the distinct record-field operation applying a validated absent-field
  default, which overrides child default metadata.
- `format` attaches metadata without validation, including custom names. Keep
  optional format assertions disabled in external validators for matching
  acceptance semantics.
- `dependent_required` adds one-way input property dependencies. Null is present;
  decoded defaults do not count as input presence. Repeated rules merge their keys.
- `integer_multiple_of` adds exact divisibility to safe-integer definitions by
  positive safe-integer divisors. Fractional divisors and `number()` definitions
  are not supported by this helper.
- `assert_format(_, Uuid)` enforces UUID hexadecimal/dash syntax through emitted
  length and pattern constraints. It preserves case and does not restrict version
  or variant bits. Other asserted formats are not supplied.

These operations preserve the associated definition's decoded output type. Details
and composition restrictions are in [Advanced definitions](advanced.html).
