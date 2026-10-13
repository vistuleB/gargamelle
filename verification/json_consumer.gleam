import gargamelle/boundary as gargamelle_boundary
import gargamelle as s
import gargamelle/encoding as gargamelle_encoding
import gleam/io

pub fn main() {
  let assert Ok(name) = s.json_string("Brainy")
  let metadata = s.json_array([s.json_null(), s.json_bool(True)])
  let assert Ok(json) =
    s.json_object([#("name", name), #("metadata", metadata)])
  let assert Error(s.DuplicateKey("name")) =
    s.json_object([#("name", name), #("name", name)])
  let assert Error(s.UnsafeInteger) = s.json_int(9_007_199_254_740_991 + 1)
  let assert Error(_) = s.parse("\"\\ud800\"")
  let assert Ok(original) = s.decode(s.anything(), json)
  let assert True = original == json
  let assert Ok(fields) =
    s.required(
      s.record(fn(name) { fn(metadata) { #(name, metadata) } }),
      "name",
      s.text(),
    )
  let assert Ok(fields) = s.required(fields, "metadata", s.anything())
  let definition = s.finish(fields, s.Strict)
  let assert Ok(#("Brainy", decoded_metadata)) = s.decode(definition, json)
  let assert True = decoded_metadata == metadata
  let assert Ok(bad) =
    s.json_object([#("name", s.json_null()), #("metadata", metadata)])
  let assert Error(_) = s.validate(definition, bad)
  let assert Ok(verified) =
    gargamelle_encoding.encode(gargamelle_encoding.codec(gargamelle_encoding.json(), s.contract(s.anything())), json)
  let assert True =
    s.to_string(s.verified_json(verified), s.Compact)
    == s.to_string(json, s.Compact)
  let receiver =
    gargamelle_boundary.json_boundary(s.contract(definition), fn(value) {
      s.to_string(s.verified_json(value), s.Compact)
    })
  let assert Ok(response) =
    gargamelle_boundary.send(
      gargamelle_boundary.output_boundary(
        gargamelle_encoding.json(),
        gargamelle_boundary.json_boundary(s.contract(s.anything()), fn(v) {
          s.to_string(s.verified_json(v), s.Compact)
        }),
      ),
      json,
    )
  let assert True = response == s.to_string(json, s.Compact)
  let assert Error(_) = gargamelle_boundary.forward_json(receiver, bad)
  io.println("release JSON consumer passed")
}
