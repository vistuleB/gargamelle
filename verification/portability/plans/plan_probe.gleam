import gleam/io
import gleam/json
import gleam/list
import gleam/result
import immutable_plan as p

pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

fn tree(name) {
  p.recursive(name, fn(self) {
    p.any_of([
      p.map(p.text(), Leaf),
      p.map(p.field("children", p.array(self)), Branch),
    ])
  })
}

fn encode(value) {
  case value {
    p.Text(text) -> json.string(text)
    p.Boolean(boolean) -> json.bool(boolean)
    p.Array(values) -> json.array(values, encode)
    p.Object(fields) ->
      json.object(list.map(fields, fn(field) { #(field.0, encode(field.1)) }))
  }
}

fn samples() {
  let base = [p.Text("x"), p.Boolean(True), p.Array([]), p.Object([])]
  let first =
    list.flat_map(base, fn(value) {
      [
        p.Array([value]),
        p.Object([#("children", p.Array([value]))]),
        p.Object([#("children", value)]),
        p.Object([#("extra", value)]),
      ]
    })
  list.append(
    base,
    list.append(
      first,
      list.flat_map(first, fn(value) {
        [p.Array([value]), p.Object([#("children", p.Array([value]))])]
      }),
    ),
  )
}

fn fixture(name, definition, values) {
  json.object([
    #("name", json.string(name)),
    #("schema", json.string(p.emit(definition))),
    #(
      "cases",
      json.array(values, fn(value) {
        json.object([
          #("value", encode(value)),
          #("accepted", json.bool(result.is_ok(p.validate(definition, value)))),
          #("decoded", json.bool(result.is_ok(p.decode(definition, value)))),
        ])
      }),
    ),
  ])
}

pub fn main() {
  let assert Ok(definition) = tree("tree/~")
  let assert Ok(outer) =
    p.recursive("tree/~", fn(self) {
      p.any_of([p.lift(definition), p.map(p.array(self), Branch)])
    })
  let assert Ok(default) =
    p.defaulted("tree/~", p.lift(definition), p.Text("default"))
  let assert Ok(#(first, second)) =
    p.recursive_pair("a", "b", fn(a, b) {
      use second <- result.try(
        p.any_of([p.text(), p.map(p.array(a), fn(_) { "nested" })]),
      )
      Ok(#(p.map(p.array(b), fn(_) { "first" }), second))
    })
  json.to_string(
    json.array(
      [
        fixture("self", definition, samples()),
        fixture("composed", outer, samples()),
        fixture(
          "default",
          p.finish(default),
          list.map(samples(), fn(value) { p.Object([#("tree/~", value)]) })
            |> list.append([p.Object([])]),
        ),
        fixture("pair-first", first, samples()),
        fixture("pair-second", second, samples()),
      ],
      fn(json) { json },
    ),
  )
  |> io.println
}
