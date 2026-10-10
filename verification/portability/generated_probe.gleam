import gargamelle as s
import generated_definitions
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result

fn error_json(error: s.DataError) -> json.Json {
  json.object([
    #("category", json.string(error.category)),
    #("path", json.string(error.path)),
    #("missing_key", case error.missing_key {
      Some(key) -> json.string(key)
      None -> json.null()
    }),
    #(
      "branches",
      json.array(error.branches, fn(branch) {
        json.object([
          #("index", json.int(branch.0)),
          #("errors", json.array(branch.1, error_json)),
        ])
      }),
    ),
    #("matches", json.array(error.matches, json.int)),
  ])
}

fn entry(definition, input) {
  let assert Ok(value) = s.parse(input)
  let before = s.value_text(value)
  let decoded = s.decode(definition, value)
  let assert True = before == s.value_text(value)
  let errors = case decoded {
    Ok(_) -> []
    Error(errors) -> errors
  }
  json.object([
    #("input", json.string(input)),
    #("accepted", json.bool(result.is_ok(s.validate(definition, value)))),
    #("decoded", case decoded {
      Ok(output) -> output
      Error(_) -> json.null()
    }),
    #("errors", json.array(errors, error_json)),
  ])
}

fn checkpoint(index, input_index) {
  json.object([
    #("index", json.int(index)),
    #("inputIndex", json.int(input_index)),
  ])
  |> json.to_string
  |> fn(text) { io.println_error("GARGAMELLE_CASE " <> text) }
}

pub fn main() {
  generated_definitions.fixtures()
  |> list.map(fn(fixture) {
    let #(index, construct, inputs) = fixture
    checkpoint(index, -1)
    let definition = construct()
    let schema = s.emit_text(definition)
    let cases =
      list.index_map(inputs, fn(input, input_index) {
        checkpoint(index, input_index)
        entry(definition, input)
      })
    let assert True = schema == s.emit_text(definition)
    json.object([
      #("index", json.int(index)),
      #("schema", json.string(schema)),
      #("cases", json.array(cases, fn(x) { x })),
    ])
  })
  |> json.array(fn(x) { x })
  |> json.to_string
  |> io.println
}
