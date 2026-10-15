// Test-only cross-target observations; not part of the package's src modules.
import gargamelle as s
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}

fn named(def, name) {
  let assert Ok(def) =
    s.named(name, s.description(s.title(def, "title"), "description"))
  def
}

fn observe(name, def, inputs, encode) {
  let observations =
    list.map(inputs, fn(source) {
      let assert Ok(input) = s.parse(source)
      let validated = case s.validate(def, input) {
        Ok(_) -> True
        Error(_) -> False
      }
      let decoded = case s.decode(def, input) {
        Ok(output) ->
          json.object([
            #("accepted", json.bool(True)),
            #("output", encode(output)),
          ])
        Error(_) -> json.object([#("accepted", json.bool(False))])
      }
      json.object([
        #("source", json.string(source)),
        #("validated", json.bool(validated)),
        #("decoded", decoded),
      ])
    })
  json.object([
    #("name", json.string(name)),
    #("schema", json.string(s.schema_string(def, s.Compact))),
    #("cases", json.array(observations, fn(x) { x })),
  ])
}

pub fn main() {
  let assert Ok(text) =
    s.bounds(
      named(s.map(s.string(), fn(x) { "decoded:" <> x }), "text"),
      Some(2),
      Some(4),
    )
  let assert Ok(text) = s.pattern(text, "^a")
  let assert Ok(integer) =
    s.integer_multiple_of(
      named(s.map(s.safe_integer(), int.to_string), "integer"),
      2,
    )
  let assert Ok(integer) = s.bounds(integer, Some(0), Some(12))
  let assert Ok(integer) = s.integer_multiple_of(named(integer, "alias"), 3)
  let assert Ok(number) =
    s.number_bounds(
      named(s.number(), "number"),
      Some(s.Exclusive(0.0)),
      Some(s.Inclusive(1.0)),
    )
  let assert Ok(one) = s.integer_constant(1)
  let assert Ok(two) = s.integer_constant(2)
  let assert Ok(three) = s.integer_constant(3)
  let assert Ok(array) = s.contains(s.array(s.safe_integer()), one, 1, None)
  let assert Ok(array) = s.unique_items(named(array, "array"))
  let array = s.exclude(array, s.array(one))
  let assert Ok(array) = s.contains(array, two, 1, None)
  let assert Ok(array) = s.contains(array, three, 1, None)
  let assert Ok(array) = s.bounds(array, Some(3), Some(4))
  let assert Ok(key) = s.pattern(s.string(), "^[ab]$")
  let assert Ok(object) =
    s.property_names(named(s.dictionary(s.string()), "object"), key)
  let assert Ok(object) = s.dependent_required(object, "a", ["b"])
  let assert Ok(object) = s.bounds(s.map(object, list.length), Some(1), Some(2))
  let asserted =
    s.if_then(
      s.exclude(named(s.string(), "asserted"), s.string_constant("bad")),
      s.string(),
      s.string(),
    )
  let assert Ok(asserted) = s.pattern(asserted, "^a")
  let assert Ok(asserted) = s.bounds(asserted, Some(2), Some(3))
  let assert Ok(a) = s.pattern(s.string(), "^a")
  let assert Ok(b) = s.pattern(s.string(), "^b")
  let assert Ok(counted) = s.contains(s.array(s.string()), a, 1, Some(1))
  let assert Ok(counted) = s.unique_items(counted)
  let assert Ok(counted) = s.contains(counted, b, 1, None)
  [
    observe(
      "counted",
      counted,
      [
        "[\"a\",\"b\"]",
        "[\"a\",\"ab\",\"b\"]",
        "[\"b\"]",
        "[\"a\"]",
        "[\"a\",\"c\",\"b\"]",
        "[]",
      ],
      json.array(_, json.string),
    ),
    observe("text", text, ["\"ab\"", "\"a\"", "\"zz\"", "false"], json.string),
    observe("integer", integer, ["0", "12", "4", "18", "0.5"], json.string),
    observe("number", number, ["0.5", "0", "1", "2", "false"], json.float),
    observe(
      "array",
      array,
      [
        "[1,2,3]",
        "[1,2,3,4]",
        "[2,3,4]",
        "[1,3,4]",
        "[1,2,4]",
        "[1,2,3,3]",
        "[1,2]",
        "[1,2,3,4,5]",
      ],
      json.array(_, json.int),
    ),
    observe(
      "object",
      object,
      [
        "{\"a\":\"x\",\"b\":\"y\"}",
        "{\"b\":\"x\"}",
        "{}",
        "{\"a\":\"x\"}",
        "{\"c\":\"x\"}",
      ],
      json.int,
    ),
    observe(
      "asserted",
      asserted,
      ["\"ab\"", "\"abc\"", "\"bad\"", "\"a\"", "\"abcd\""],
      json.string,
    ),
  ]
  |> json.array(fn(x) { x })
  |> json.to_string
  |> io.println
}
