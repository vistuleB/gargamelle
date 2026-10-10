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

pub fn main() {
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
  let assert True = string.contains(s.emit_text(tree), "#/$defs/tree")
  let html = documentation.render(tree, "Tree")
  let assert True = string.contains(html, "each item")
  let assert False = string.contains(html, "Invalid schema JSON")
  let assert Ok(duplicate) = s.pattern(s.text(), "(?:(?<x>a)|(?<x>b))\\k<x>")
  let assert Ok(bb) = s.parse("\"bb\"")
  let assert Ok("bb") = s.decode(duplicate, bb)
  io.println("native deployment passed")
}
