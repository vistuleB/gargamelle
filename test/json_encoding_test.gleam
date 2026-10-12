import gargamelle as s
import gargamelle/encoding as e
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
      let assert Ok(output) = e.encode_json(e.json(), input)
      s.to_string(output, s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
      let assert Ok(converted) = s.parse(json.to_string(s.to_gleam_json(input)))
      s.to_string(converted, s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
      let assert Ok(verified) =
        e.encode(e.codec(e.json(), s.contract(s.anything())), input)
      s.to_string(s.verified_json(verified), s.Compact)
      |> should.equal(s.to_string(input, s.Compact))
    },
  )
}

pub fn metadata_encoding_still_obeys_receiving_contract_test() {
  let metadata = s.json_array([s.json_bool(True), s.json_null()])
  let assert Ok(fields) =
    e.field(e.record(), "metadata", e.json(), fn(value: s.Json) { value })
  let encoder = e.finish(fields)
  let assert Ok(fields) =
    s.required(s.record(fn(value) { value }), "metadata", s.anything())
  let contract = s.contract(s.finish(fields, s.Strict))
  let output =
    e.output_boundary(
      encoder,
      s.json_boundary(contract, fn(verified) {
        s.to_string(s.verified_json(verified), s.Compact)
      }),
    )
  e.send(output, metadata) |> should.equal(Ok("{\"metadata\":[true,null]}"))
  let strict_contract =
    contract
    |> s.require("Metadata must be empty", fn(value) {
      case s.to_string(value, s.Compact) {
        "[]" -> Ok(Nil)
        _ -> Error([s.Violation("/metadata", "Expected empty metadata")])
      }
    })
  let strict_receiver =
    s.json_boundary(strict_contract, fn(_) {
      panic as "Rejected output invoked handler"
    })
  e.send(e.output_boundary(encoder, strict_receiver), metadata)
  |> should.be_error()
}
