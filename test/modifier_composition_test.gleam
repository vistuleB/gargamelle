import gargamelle as s
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn json(source) {
  let assert Ok(json) = s.parse(source)
  json
}

fn named(definition, name) {
  let assert Ok(definition) =
    s.named(name, s.title(s.description(definition, "description"), "title"))
  definition
}

pub fn named_string_modifiers_test() {
  let text = s.map(s.string(), fn(x) { "decoded:" <> x })
  let assert Ok(def) = s.bounds(named(text, "text"), Some(2), Some(4))
  let assert Ok(def) = s.pattern(def, "^a")
  s.decode(def, json("\"ab\"")) |> should.equal(Ok("decoded:ab"))
  s.decode(def, json("\"a\"")) |> should.be_error
  s.validate(def, json("\"zz\"")) |> should.be_error
  s.schema_string(def, s.Compact)
  |> should.equal(
    "{\"$defs\":{\"text\":{\"description\":\"description\",\"maxLength\":4,\"minLength\":2,\"pattern\":\"^a\",\"title\":\"title\",\"type\":\"string\"}},\"$ref\":\"#/$defs/text\",\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}",
  )
}

pub fn named_numeric_modifiers_test() {
  let assert Ok(def) =
    s.integer_multiple_of(
      named(s.map(s.safe_integer(), int.to_string), "integer"),
      2,
    )
  let assert Ok(def) = s.bounds(def, Some(0), Some(12))
  let assert Ok(def) = s.integer_multiple_of(named(def, "alias"), 3)
  s.decode(def, json("12")) |> should.equal(Ok("12"))
  s.validate(def, json("4")) |> should.be_error
  s.validate(def, json("18")) |> should.be_error
  let assert Ok(number) =
    s.number_bounds(
      named(s.number(), "number"),
      Some(s.Exclusive(0.0)),
      Some(s.Inclusive(1.0)),
    )
  s.decode(number, json("0.5")) |> should.equal(Ok(0.5))
  s.validate(number, json("0")) |> should.be_error
}

pub fn separated_array_modifiers_test() {
  let assert Ok(one) = s.integer_constant(1)
  let assert Ok(two) = s.integer_constant(2)
  let assert Ok(three) = s.integer_constant(3)
  let assert Ok(def) = s.contains(s.array(s.safe_integer()), one, 1, None)
  let assert Ok(def) = s.unique_items(named(def, "array"))
  let def = s.exclude(def, s.array(one))
  let assert Ok(def) = s.contains(def, two, 1, None)
  let assert Ok(def) = s.contains(def, three, 1, None)
  let assert Ok(def) = s.bounds(def, Some(3), Some(4))
  s.decode(def, json("[1,2,3]")) |> should.equal(Ok([1, 2, 3]))
  list.each(
    ["[2,3,4]", "[1,3,4]", "[1,2,4]", "[1,2,3,3]", "[1,2]", "[1,2,3,4,5]"],
    fn(source) {
      s.validate(def, json(source)) |> should.be_error
      s.decode(def, json(source)) |> should.be_error
    },
  )
  s.schema_string(def, s.Compact) |> should.not_equal("")
  let assert Ok(a) = s.pattern(s.string(), "^a")
  let assert Ok(b) = s.pattern(s.string(), "^b")
  let assert Ok(counted) = s.contains(s.array(s.string()), a, 1, Some(1))
  let assert Ok(counted) = s.unique_items(counted)
  let assert Ok(counted) = s.contains(counted, b, 1, None)
  s.decode(counted, json("[\"a\",\"b\"]")) |> should.equal(Ok(["a", "b"]))
  s.validate(counted, json("[\"a\",\"ab\",\"b\"]")) |> should.be_error
}

pub fn object_wrappers_and_defaults_test() {
  let assert Ok(key) = s.pattern(s.string(), "^[ab]$")
  let assert Ok(def) =
    s.property_names(named(s.dictionary(s.string()), "object"), key)
  let assert Ok(def) = s.dependent_required(def, "a", ["b"])
  let assert Ok(def) = s.bounds(s.map(def, list.length), Some(1), Some(2))
  s.decode(def, json("{\"a\":\"x\",\"b\":\"y\"}")) |> should.equal(Ok(2))
  list.each(["{}", "{\"a\":\"x\"}", "{\"c\":\"x\"}"], fn(source) {
    s.validate(def, json(source)) |> should.be_error
  })
  let assert Ok(child) =
    s.bounds(named(s.string(), "default-text"), Some(2), None)
  let assert Ok(record) =
    s.defaulted(s.record(fn(x) { x }), "a", child, json("\"ab\""))
  s.decode(s.finish(record, s.Strict), json("{}")) |> should.equal(Ok("ab"))
  s.defaulted(s.record(fn(x) { x }), "a", child, json("\"a\""))
  |> should.be_error
}

pub fn same_input_auxiliary_converters_test() {
  let forbidden =
    s.map(s.string_constant("bad"), fn(_) { panic as "forbidden conversion" })
  let condition = s.map(s.string(), fn(_) { panic as "condition conversion" })
  let consequence =
    s.map(s.string(), fn(_) { panic as "consequence conversion" })
  let def =
    s.if_then(
      s.exclude(named(s.string(), "guarded"), forbidden),
      condition,
      consequence,
    )
  let assert Ok(def) = s.pattern(def, "^a")
  let assert Ok(def) = s.bounds(def, Some(2), Some(3))
  s.validate(def, json("\"ab\"")) |> should.equal(Ok(Nil))
  s.decode(def, json("\"ab\"")) |> should.equal(Ok("ab"))
  s.validate(def, json("\"bad\"")) |> should.be_error
  s.schema_string(def, s.Compact) |> should.not_equal("")
}

pub fn unsupported_modifier_combinations_test() {
  s.bounds(s.nullable(s.string()), None, Some(3)) |> should.be_error
  s.bounds(s.string_constant("x"), None, Some(3)) |> should.be_error
  let assert Ok(union) =
    s.any_of([s.string(), s.map(s.boolean(), fn(_) { "boolean" })])
  s.bounds(named(union, "union"), None, Some(3)) |> should.be_error
  s.pattern(s.map(s.number(), fn(_) { "text" }), "a") |> should.be_error
  s.number_bounds(
    s.map(s.string(), fn(_) { 1.0 }),
    None,
    Some(s.Inclusive(2.0)),
  )
  |> should.be_error
  s.integer_multiple_of(s.number(), 2) |> should.be_error
  s.property_names(s.nullable(s.dictionary(s.string())), s.string())
  |> should.be_error
  s.dependent_required(s.array(s.string()), "a", ["b"]) |> should.be_error
  let tuple = s.finish_tuple(s.element(s.tuple(fn(x) { [x] }), s.string()))
  s.bounds(tuple, None, Some(2)) |> should.be_error
  s.unique_items(tuple) |> should.be_error
  s.contains(tuple, s.string(), 1, None) |> should.be_ok
}

type Tree {
  Branch(List(Tree))
}

pub fn recursive_modifier_policy_test() {
  let assert Ok(tree) =
    s.recursive("tree", fn(self) {
      let assert Ok(body) =
        s.bounds(named(s.array(self), "children"), None, Some(2))
      Ok(s.map(body, Branch))
    })
  s.decode(tree, json("[[]]")) |> should.equal(Ok(Branch([Branch([])])))
  s.validate(tree, json("[[],[],[]]")) |> should.be_error
  s.bounds(tree, None, Some(2)) |> should.be_error
  s.recursive("unfinished", fn(self) { s.bounds(self, None, Some(2)) })
  |> should.be_error
}
