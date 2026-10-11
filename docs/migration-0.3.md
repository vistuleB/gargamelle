# Migrating to 0.3.0

Use these names in new code:

| Previous name | Preferred name | Purpose |
| --- | --- | --- |
| `Value` | `Json` | Gargamelle’s opaque JSON representation |
| `Policy` | `RecordPolicy` | Treatment of undeclared record keys |
| `Closed` | `Strict` | Reject undeclared record keys |
| `value_text` | `to_string` | Serialize a `Json` value as canonical JSON |
| `emit_json` | `schema_json` | Return a schema as `Json` |
| `emit_text` | `schema_string` | Return a schema as a canonical JSON `String` |

`parse` and `schema_json` return Gargamelle’s `Json`, which is distinct from
`gleam/json.Json`. Its finite-number and Unicode-scalar requirements are unchanged.
Decoded output still has the definition’s output type. The string functions
return strings; they do not print output.

`RecordPolicy.Strict` rejects undeclared keys; `Open` accepts them and omits
them from decoded output. HTML documentation labels rejection of undeclared
keys **strict fields**. The deprecated `Closed` constructor applies the same
rule as `Strict`, but they are distinct constructor values. Update exhaustive
policy matches to handle `Strict` as well as `Closed` and `Open`.

The previous type and function names remain deprecated aliases. Old names
produce compiler warnings; existing constructor and function calls still work.
Inferred types need no annotation changes. Schema bytes, validation, decoding
and JSON serialization are unchanged.

See the [API reference](gargamelle.html#Json) for the complete contracts.
