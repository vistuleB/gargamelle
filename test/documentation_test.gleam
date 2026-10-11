import gargamelle as s
import gargamelle/documentation as docs
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn nested_definition_test() {
  let assert Ok(r) =
    s.record(fn(name) { fn(tags) { #(name, tags) } })
    |> s.required("name", s.text() |> s.description("Name <not markup>"))
  let assert Ok(r) = s.optional(r, "tags", s.array(s.nullable(s.text())))
  let html = docs.render(s.finish(r, s.Strict), "person")
  string.contains(html, "<details class=\"node\" open>") |> should.be_true
  string.contains(html, "Name &lt;not markup&gt;") |> should.be_true
  string.contains(html, "each item") |> should.be_true
  string.contains(html, "any matching alternative") |> should.be_true
  string.contains(html, "optional") |> should.be_true
  string.contains(html, "class=\"badge policy\"") |> should.be_true
  string.contains(html, "strict</span></summary>") |> should.be_true
  string.contains(html, "unknown fields rejected") |> should.be_false
  let html = docs.render(s.dictionary(s.text()), "dictionary")
  string.contains(html, "class=\"type\">dictionary</span>") |> should.be_true
  string.contains(html, "each map value") |> should.be_true
  string.contains(html, "strict") |> should.be_false
  string.contains(html, "values validated by map contract") |> should.be_false
}

pub fn named_definition_test() {
  let assert Ok(item) = s.named("shared-item", s.text())
  let html = docs.render(s.array(item), "items")
  string.contains(html, "Shared definitions") |> should.be_true
  string.contains(html, "See shared structure") |> should.be_true
  string.contains(html, "<code>shared-item</code>") |> should.be_true
}

pub fn defaults_and_annotations_test() {
  let assert Ok(default) = s.parse("null")
  let assert Ok(r) =
    s.record(fn(x) { x })
    |> s.defaulted("value", s.nullable(s.text()), default)
  let html = docs.render(s.finish(r, s.Strict) |> s.title("<Example>"), "a\"b")
  string.contains(html, "default: null") |> should.be_true
  string.contains(html, "&lt;Example&gt;") |> should.be_true
  string.contains(html, "id=\"a&quot;b\"") |> should.be_true
}

pub fn alias_validation_test() {
  let schema =
    "{\"$defs\":{\"old\":{\"type\":\"string\"},\"shown\":{\"type\":\"string\"}},\"$ref\":\"#/$defs/old\"}"
  let assert Ok(html) =
    docs.render_emitted(schema, "example", [#("old", "shown")])
  string.contains(html, "<code>old</code>") |> should.be_false
  string.contains(html, "<code>shown</code>") |> should.be_true
  docs.render_emitted(schema, "example", [#("old", "missing")])
  |> should.be_error
  docs.render_emitted(schema, "example", [#("old", "shown"), #("shown", "old")])
  |> should.be_error
  docs.render_emitted("not JSON", "example", []) |> should.be_error
}

pub fn arbitrary_tag_test() {
  let assert Ok(r) = s.record(fn(text) { text }) |> s.required("text", s.text())
  let assert Ok(definition) =
    s.tagged("mode", [s.variant("custom", r, s.Strict)])
  let html = docs.render(definition, "tagged")
  string.contains(html, "mode = &quot;custom&quot;") |> should.be_true
}

pub fn integer_schema_values_test() {
  let assert Ok(bounded) =
    s.array(s.safe_integer()) |> s.bounds(Some(0), Some(3))
  let html = docs.render(bounded, "bounded")
  string.contains(html, "Invalid schema JSON") |> should.be_false
  string.contains(html, "each item") |> should.be_true
  let assert Ok(html) =
    docs.render_emitted(
      "{\"const\":3,\"default\":9007199254740991,\"minimum\":0.5}",
      "numbers",
      [],
    )
  string.contains(html, "default: 9007199254740991") |> should.be_true
  string.contains(html, "class=\"type\">3</") |> should.be_true
}
