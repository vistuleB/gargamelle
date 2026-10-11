# Migrating to 0.3.0

Use these names in new code:

| Previous name | Preferred name | Purpose |
| --- | --- | --- |
| `Value` | `Json` | Gargamelle’s opaque JSON representation |
| `Policy` | `RecordPolicy` | Treatment of undeclared record keys |
| `value_text` | `to_string` | Serialize a `Json` value as canonical JSON |
| `emit_json` | `schema_json` | Return a schema as `Json` |
| `emit_text` | `schema_string` | Return a schema as a canonical JSON `String` |

`parse` and `schema_json` return Gargamelle’s `Json`, which is distinct from
`gleam/json.Json`. Its finite-number and Unicode-scalar requirements are unchanged.
Decoded output still has the definition’s output type. `RecordPolicy` retains
`Closed` and `Open`, with their existing behavior. The string functions return
strings; they do not print output.

The previous names remain available as deprecated aliases. Explicit uses of the
old names produce compiler warnings; existing code still compiles and behaves
identically. Inferred types need no annotation changes. Schema bytes, validation,
decoding and JSON serialization are unchanged.

See the [API reference](gargamelle.html#Json) for the complete contracts.
