# Constructing JSON values

`Json` remains opaque. Public constructors create admitted values without
serializing and parsing temporary JSON text.

| Constructor | Result |
| --- | --- |
| `json_null()` | `Json` |
| `json_bool(value)` | `Json` |
| `json_string(value)` | `Result(Json, JsonError)` |
| `json_int(value)` | `Result(Json, JsonError)` |
| `json_number(value)` | `Result(Json, JsonError)` |
| `json_array(children)` | `Json` |
| `json_object(fields)` | `Result(Json, JsonError)` |

Strings and object keys must contain Unicode scalar values. Float numbers must
be finite. Integer construction requires the common safe-integer range,
−9007199254740991 through 9007199254740991; larger values fail instead of being
rounded. `json_number` accepts any finite binary64 Float, including integral ones
outside the safe-integer range.

Arrays and objects take already admitted `Json` children. Object construction
rejects duplicate keys and reports the first invalid or repeated key.
This differs from parsing, which retains the last value of a duplicate key.
Declaration order is retained internally; serialization uses canonical key order.
Keys such as `__proto__` and `constructor` have no special meaning.

```gleam
import gargamelle as s
import gleam/io

pub fn main() {
  let assert Ok(name) = s.json_string("Brainy")
  let assert Ok(count) = s.json_int(2)
  let assert Ok(json) = s.json_object([
    #("name", name),
    #("count", count),
    #("active", s.json_bool(True)),
  ])
  io.println(s.to_string(json, s.Compact))
}
```

Output:

```text
{"active":true,"count":2,"name":"Brainy"}
```

These values can be supplied to schema annotations, decoded defaults, validation,
decoding or receiving boundaries. Construction establishes the admitted JSON
domain, not acceptance by any particular definition or Contract.

Typed encoders remain a separate API: they describe how to convert a Gleam value
into JSON. The current encoder implementation still serializes and reparses its
intermediate representation; it does not yet use these direct constructors.

## Arbitrary admitted JSON

`anything()` defines an unconstrained admitted JSON value and decodes to `Json`,
returning the original representation unchanged. It can describe arbitrary
metadata inside an otherwise constrained record. The emitted subschema is `{}`;
the root schema also contains the dialect annotation.

Surrounding record fields, required presence and Strict policy remain enforced.
An unconstrained subtree makes no application-specific acceptance claim, and
semantic Contract requirements can still reject it. Nonfinite numbers and
non-scalar strings/keys remain outside admission. This definition accepts JSON,
not arbitrary runtime objects or a dynamically untyped Gleam value.

## Encoding JSON metadata

`encoding.json()` composes admitted JSON with typed field encoders. The usual
encoding serialization/admission path applies. A receiving Contract is still
needed to establish structural and semantic acceptance.

```gleam
import gargamelle as s
import gargamelle/encoding as e
import gleam/io

pub fn main() {
  let metadata = s.json_array([s.json_bool(True), s.json_null()])
  let assert Ok(fields) = e.field(e.record(), "metadata", e.json(), fn(value: s.Json) { value })
  let encoder = e.finish(fields)
  let assert Ok(fields) = s.required(s.record(fn(value) { value }), "metadata", s.anything())
  let codec = e.codec(encoder, s.contract(s.finish(fields, s.Strict)))
  let assert Ok(verified) = e.encode(codec, metadata)
  io.println(s.to_string(s.verified_json(verified), s.Compact))
}
```

Output:

```text
{"metadata":[true,null]}
```

`to_gleam_json(json)` converts an admitted value to the standard `gleam/json.Json`
representation without parsing text. It establishes no new certificate and does
not admit values in the reverse direction. Standard serialization may normalize
negative zero; original source formatting is not retained.
