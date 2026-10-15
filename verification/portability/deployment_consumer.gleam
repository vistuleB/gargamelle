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
  s.decode(s.array(s.string()), value)
}

fn user_definition() {
  let assert Ok(fields) =
    s.record(fn(name) { fn(active) { User(name, active) } })
    |> s.required("name", s.string())
  let assert Ok(fields) = s.required(fields, "active", s.boolean())
  s.finish(fields, s.Strict)
}

pub fn strict_policy(policy: s.RecordPolicy) -> Bool {
  case policy {
    s.Open -> False
    s.Strict -> True
  }
}

pub fn main() {
  let assert True = strict_policy(s.Strict)
  let assert False = strict_policy(s.Open)
  let strict = s.finish(s.record(Nil), s.Strict)
  let assert Ok(empty) = s.parse("{}")
  let assert Ok(extra) = s.parse("{\"extra\":true}")
  let json: s.Json = empty
  let assert Ok(Nil) = s.decode(strict, json)
  let assert Error(_) = s.validate(strict, extra)
  let assert True =
    s.to_string(s.schema_json(user_definition()), s.Compact)
    == s.schema_string(user_definition(), s.Compact)
  let assert Ok(["Ada", "Grace"]) = read_names("[\"Ada\",\"Grace\"]")
  let assert "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"type\":\"string\"},\"type\":\"array\"}" =
    s.schema_string(s.array(s.string()), s.Compact)
  let assert Ok(user) = s.parse("{\"name\":\"Ada\",\"active\":true}")
  let assert Ok(User("Ada", True)) = s.decode(user_definition(), user)
  let html = documentation.render(user_definition(), "user")
  let assert True = string.contains(html, "strict</span>")
  let assert Ok(leaf) = s.pattern(s.string(), "^\\p{L}+$")
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
  let assert True =
    string.contains(s.schema_string(tree, s.Compact), "#/$defs/tree")
  let html = documentation.render(tree, "Tree")
  let assert True = string.contains(html, "each item")
  let assert False = string.contains(html, "Invalid schema JSON")
  let assert Ok(duplicate) = s.pattern(s.string(), "(?:(?<x>a)|(?<x>b))\\k<x>")
  let assert Ok(bb) = s.parse("\"bb\"")
  let assert Ok("bb") = s.decode(duplicate, bb)
  io.println("native deployment passed")
}
