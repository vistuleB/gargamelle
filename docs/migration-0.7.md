# Migrating to 0.7.0

0.7.0 adds direct JSON constructors, an unconstrained admitted-JSON definition,
and JSON pass-through encoding. Existing definition, Contract, decoding and
encoding signatures are unchanged.

- `json_*` constructors build opaque `Json` values. Fallible constructors return
  typed `JsonError` reasons. Object construction rejects duplicate keys; parsing
  retains its existing last-value behavior. Integer construction rejects values
  outside the common safe-integer range rather than rounding them.
- `anything()` returns a `Definition(Json)` that accepts every admitted JSON value
  unchanged. It can describe arbitrary metadata without relaxing surrounding
  record fields. It does not bypass admission or explicit semantic requirements.
- `encoding.json()` composes already admitted JSON with typed field encoders.
  Checked encoding and output boundaries retain their receiving Contract checks.
- `to_gleam_json` provides one-way conversion to the standard JSON representation.
  It does not expose opaque constructors or introduce a reverse admission path.

Encoding retains its existing serialization/admission path. No performance gain,
source-text preservation, or decode/encode inverse is claimed. The JSON-only
pass-through encoder preserves canonical JSON, including ordinary normalization
of zero signs during serialization.

See [Constructing JSON values](json-values.html) and
[Typed JSON encoding](encoding.html) for examples and limits.
