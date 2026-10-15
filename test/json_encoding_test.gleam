import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
import gleam/json
import gleam/list
import gleeunit/should

pub fn admitted_json_pass_through_test() {
  list.each(
    [
      "null", "false", "1.25", "-0", "1e308", "\"💜\"", "[]", "{}",
      "{\"__proto__\":\"safe\",\"nested\":[true,null,{\"x\":2}]}",
    ],
    fn(source) {
      let assert Ok(input) = s.parse(source)
      let assert Ok(output) =
        gargamelle_encoding.encode_json(gargamelle_encoding.json(), input)
      s.to_string(output, s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
      let assert Ok(converted) = s.parse(json.to_string(s.to_gleam_json(input)))
      s.to_string(converted, s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
      let assert Ok(verified) =
        gargamelle_encoding.encode(
          gargamelle_encoding.codec(
            gargamelle_encoding.json(),
            s.contract(s.anything()),
          ),
          input,
        )
      s.to_string(s.verified_json(verified), s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
    },
  )
}

pub fn metadata_encoding_still_obeys_receiving_contract_test() {
  let metadata = s.json_array([s.json_bool(True), s.json_null()])
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "metadata",
      gargamelle_encoding.json(),
      fn(value: s.Json) { value },
    )
  let encoder = gargamelle_encoding.finish(fields)
  let assert Ok(fields) =
    s.required(s.record(fn(value) { value }), "metadata", s.anything())
  let contract = s.contract(s.finish(fields, s.Strict))
  let output =
    gargamelle_boundary.output(
      encoder,
      gargamelle_boundary.json(contract, fn(verified) {
        s.to_string(s.verified_json(verified), s.Compact)
      }),
    )
  gargamelle_boundary.send(output, metadata)
  |> should.equal(Ok("{\"metadata\":[true,null]}"))
  let strict_contract =
    contract
    |> s.require("Metadata must be empty", fn(value) {
      case s.to_string(value, s.Compact) {
        "[]" -> Ok(Nil)
        _ -> Error([s.Violation("/metadata", "Expected empty metadata")])
      }
    })
  let strict_receiver =
    gargamelle_boundary.json(strict_contract, fn(_) {
      panic as "Rejected output invoked handler"
    })
  gargamelle_boundary.send(
    gargamelle_boundary.output(encoder, strict_receiver),
    metadata,
  )
  |> should.be_error()
}
