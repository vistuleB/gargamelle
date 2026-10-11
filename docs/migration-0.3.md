# Migrating to 0.3.0

The schema functions have clearer names:

| Previous name | Preferred name | Returns |
| --- | --- | --- |
| `emit_json` | `schema_json` | A schema as Gargamelle’s opaque `Value` |
| `emit_text` | `schema_string` | The schema serialized as a canonical JSON `String` |

Update calls to the preferred names. Neither function prints output.
The schema bytes, validation and decoding behavior are unchanged.

The previous names remain available as deprecated aliases, so existing calls
still compile and behave identically. For their full contracts, see the
[API reference](gargamelle.html#schema_json).
