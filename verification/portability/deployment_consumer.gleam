import gargamelle as s
import gargamelle/documentation
import gleam/io
import gleam/option.{Some}
import gleam/result
import gleam/string

pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

pub type User {
  User(name: String, active: Bool)
}

fn read_names(source: String) {
  let assert Ok(value) = s.parse(source)
  s.decode(s.array(s.text()), value)
}

fn user_definition() {
  let assert Ok(fields) =
    s.record(fn(name) { fn(active) { User(name, active) } })
    |> s.required("name", s.text())
  let assert Ok(fields) = s.required(fields, "active", s.boolean())
  s.finish(fields, s.Strict)
}

pub fn old_json(value: s.Value) -> s.Json {
  value
}

pub fn new_json(value: s.Json) -> s.Value {
  value
}

pub fn old_policy(policy: s.Policy) -> s.RecordPolicy {
  policy
}

pub fn new_policy(policy: s.RecordPolicy) -> s.Policy {
  policy
}

pub fn strict_policy(policy: s.RecordPolicy) -> Bool {
  case policy {
    s.Open -> False
    s.Strict | s.Closed -> True
  }
}

pub fn main() {
  let assert Ok(json) = s.parse("{\"name\":\"Ada\",\"active\":true}")
  let json: s.Json = old_json(new_json(json))
  let assert True = s.value_text(json) == s.to_string(json)
  let policy: s.RecordPolicy = old_policy(new_policy(s.Closed))
  let assert True = policy == s.Closed
  let assert False = s.Strict == s.Closed
  let assert True = strict_policy(s.Strict) && strict_policy(s.Closed)
  let assert False = strict_policy(s.Open)
  let legacy = s.finish(s.record(Nil), s.Closed)
  let strict = s.finish(s.record(Nil), s.Strict)
  let assert True = s.schema_string(legacy) == s.schema_string(strict)
  let assert Ok(empty) = s.parse("{}")
  let assert Ok(extra) = s.parse("{\"extra\":true}")
  let assert True = s.decode(legacy, empty) == s.decode(strict, empty)
  let assert Error(_) = s.validate(strict, extra)
  let assert True = s.validate(legacy, extra) == s.validate(strict, extra)
  let assert True =
    documentation.render(legacy, "record")
    == documentation.render(strict, "record")
  let assert True =
    s.emit_text(user_definition()) == s.schema_string(user_definition())
  let assert True =
    s.to_string(s.emit_json(user_definition()))
    == s.schema_string(user_definition())
  let assert Ok(["Ada", "Grace"]) = read_names("[\"Ada\",\"Grace\"]")
  let assert "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"type\":\"string\"},\"type\":\"array\"}" =
    s.schema_string(s.array(s.text()))
  let assert Ok(user) = s.parse("{\"name\":\"Ada\",\"active\":true}")
  let assert Ok(User("Ada", True)) = s.decode(user_definition(), user)
  let html = documentation.render(user_definition(), "user")
  let assert True = string.contains(html, "strict fields</span>")
  let assert Ok(leaf) = s.pattern(s.text(), "^\\p{L}+$")
  let leaf = s.map(leaf, Leaf)
  let assert Ok(tree) =
    s.recursive("tree", fn(self) {
      use children <- result.try(s.bounds(s.array(self), Some(0), Some(3)))
      s.any_of([s.lift(leaf), s.map(children, Branch)])
    })
  let assert Ok(input) = s.parse("[\"one\",[\"α\"]]")
  let assert Ok(Branch([Leaf("one"), Branch([Leaf("α")])])) =
    s.decode(tree, input)
  let assert Ok(Nil) = s.validate(tree, input)
  let assert True = string.contains(s.schema_string(tree), "#/$defs/tree")
  let html = documentation.render(tree, "Tree")
  let assert True = string.contains(html, "each item")
  let assert False = string.contains(html, "Invalid schema JSON")
  let assert Ok(duplicate) = s.pattern(s.text(), "(?:(?<x>a)|(?<x>b))\\k<x>")
  let assert Ok(bb) = s.parse("\"bb\"")
  let assert Ok("bb") = s.decode(duplicate, bb)
  io.println("native deployment passed")
}
