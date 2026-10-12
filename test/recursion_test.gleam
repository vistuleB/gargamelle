import gargamelle as s
import gargamelle/documentation
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should

pub type Tree {
  Leaf(Float)
  Branch(List(Tree))
}

fn tree_definition() -> Result(s.Definition(Tree), s.ConstructionError) {
  s.recursive("tree", fn(self) {
    use leaf <- result.try(s.required(s.record(Leaf), "value", s.number()))
    use branch <- result.try(s.required(
      s.record(Branch),
      "children",
      s.array(self),
    ))
    s.tagged("kind", [
      s.variant("leaf", leaf, s.Strict),
      s.variant("branch", branch, s.Strict),
    ])
  })
}

pub fn typed_recursive_tree_test() {
  let assert Ok(definition) = tree_definition()
  let assert Ok(value) =
    s.parse(
      "{\"kind\":\"branch\",\"children\":[{\"kind\":\"leaf\",\"value\":1.25}]}",
    )
  s.decode(definition, value) |> should.equal(Ok(Branch([Leaf(1.25)])))
  let assert Ok(value) =
    s.parse(
      "{\"kind\":\"branch\",\"children\":[{\"kind\":\"leaf\",\"value\":\"bad\"}]}",
    )
  let assert Error([error]) = s.decode(definition, value)
  error.path |> should.equal("/children/0/value")
  error.category |> should.equal("number_type")
}

pub type First {
  First(List(Second))
}

pub type Second {
  Second(String, Option(First))
}

pub fn distinct_mutually_recursive_types_test() {
  let assert Ok(#(first, second)) =
    s.recursive_pair("first", "second", fn(a, b) {
      use ra <- result.try(s.required(s.record(First), "children", s.array(b)))
      use rb <- result.try(s.required(
        s.record(fn(name) { fn(next) { Second(name, next) } }),
        "name",
        s.text(),
      ))
      use rb <- result.try(s.optional(rb, "next", a))
      Ok(#(s.finish(ra, s.Strict), s.finish(rb, s.Strict)))
    })
  let assert Ok(value) =
    s.parse("{\"children\":[{\"name\":\"x\",\"next\":{\"children\":[]}}]}")
  s.decode(first, value)
  |> should.equal(Ok(First([Second("x", Some(First([])))])))
  let assert Ok(value) = s.parse("{\"name\":\"x\"}")
  s.decode(second, value) |> should.equal(Ok(Second("x", None)))
}

pub fn non_progressing_recursion_test() {
  s.recursive("loop", fn(self) { Ok(self) }) |> should.be_error
  s.recursive("loop", fn(self) { s.any_of([self, s.text()]) })
  |> should.be_error
  s.recursive_pair("a", "b", fn(a, b) { Ok(#(b, a)) }) |> should.be_error
}

pub fn recursive_documentation_links_test() {
  let assert Ok(definition) = tree_definition()
  let html = documentation.render(definition, "tree-docs")
  string.contains(html, "href=\"#tree-docs-definition-116-114-101-101\"")
  |> should.be_true
  should.be_true(string.length(html) < 5000)
  string.contains(
    s.schema_string(definition, s.Compact),
    "\"$ref\":\"#/$defs/tree\"",
  )
  |> should.be_true
}
