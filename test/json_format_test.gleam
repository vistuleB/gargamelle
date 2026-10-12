import gargamelle as s
import gleam/list
import gleeunit/should

pub fn json_formats_test() {
  let assert Ok(value) =
    s.parse("{\"empty\":[],\"nested\":{\"items\":[1,true,null,{}]}}")
  s.to_string(value, s.Pretty)
  |> should.equal(
    "{\n  \"empty\": [],\n  \"nested\": {\n    \"items\": [\n      1,\n      true,\n      null,\n      {}\n    ]\n  }\n}",
  )
  list.each(
    [
      "null",
      "false",
      "-0",
      "1e21",
      "5e-324",
      "[]",
      "{}",
      "{\"0\":\"́{},:\\\"\\\\💜\",\"é\":\"line\\nnext\",\"𐀀\":{\"2\":[],\"10\":{}}}",
    ],
    fn(source) {
      let assert Ok(value) = s.parse(source)
      let compact = s.to_string(value, s.Compact)
      let pretty = s.to_string(value, s.Pretty)
      let assert Ok(reparsed) = s.parse(pretty)
      s.to_string(reparsed, s.Compact) |> should.equal(compact)
      s.to_string(reparsed, s.Pretty) |> should.equal(pretty)
    },
  )
  let definition = s.array(s.text())
  s.schema_string(definition, s.Pretty)
  |> should.equal(s.to_string(s.schema_json(definition), s.Pretty))
  let assert Ok(schema) = s.parse(s.schema_string(definition, s.Pretty))
  s.to_string(schema, s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
}
