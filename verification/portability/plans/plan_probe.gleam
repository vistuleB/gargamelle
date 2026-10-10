import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import immutable_plan as p
import plan_helpers

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
    p.Null -> json.null()
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

pub type NamedTree {
  NamedTree(String, Option(Bool), List(NamedTree))
}

pub type PacketTree {
  PacketTree(String, Bool, List(PacketTree))
}

fn record_samples() {
  let leaf = p.Object([#("name", p.Text("leaf")), #("children", p.Array([]))])
  let combinations =
    list.flat_map([p.Text("x"), p.Boolean(True)], fn(name) {
      list.flat_map(
        [
          p.Array([]),
          p.Array([leaf]),
          p.Boolean(False),
          p.Array([p.Text("bad")]),
        ],
        fn(children) {
          list.map([p.Boolean(False), p.Text("bad")], fn(enabled) {
            p.Object([
              #("name", name),
              #("children", children),
              #("enabled", enabled),
            ])
          })
        },
      )
    })
  list.append(
    samples(),
    list.append(combinations, [
      leaf,
      p.Object([#("name", p.Text("root")), #("children", p.Array([leaf]))]),
      p.Object([
        #("name", p.Text("root")),
        #("children", p.Array([])),
        #("extra", p.Boolean(True)),
      ]),
    ]),
  )
}

fn tuple_samples() {
  let leaf = p.Array([p.Text("leaf"), p.Boolean(False), p.Array([])])
  let combinations =
    list.flat_map([p.Text("x"), p.Boolean(True)], fn(label) {
      list.flat_map([p.Boolean(False), p.Text("bad")], fn(enabled) {
        list.map(
          [
            p.Array([]),
            p.Array([leaf]),
            p.Boolean(False),
            p.Array([p.Text("bad")]),
          ],
          fn(children) { p.Array([label, enabled, children]) },
        )
      })
    })
  list.append(
    samples(),
    list.append(combinations, [
      leaf,
      p.Array([p.Text("root"), p.Boolean(True), p.Array([leaf])]),
      p.Array([p.Text("short"), p.Boolean(False)]),
      p.Array([p.Text("long"), p.Boolean(False), p.Array([]), p.Text("extra")]),
    ]),
  )
}

pub fn main() {
  let assert Ok(definition) = tree("tree/~")
  let assert Ok(outer) =
    p.recursive("tree/~", fn(self) {
      p.any_of([p.lift(definition), p.map(p.array(self), Branch)])
    })
  let assert Ok(default) =
    p.defaulted("tree/~", p.lift(definition), p.Text("default"))
  let assert Ok(exclusive) =
    p.recursive("exclusive", fn(self) {
      p.one_of([p.map(p.text(), Leaf), p.map(p.array(self), Branch)])
    })
  let assert Ok(overlapping) =
    p.one_of([p.text(), p.string_constant("special")])
  let assert Ok(duplicate) = p.one_of([p.text(), p.text()])
  let assert Ok(#(first, second)) =
    p.recursive_pair("a", "b", fn(a, b) {
      use second <- result.try(
        p.any_of([p.text(), p.map(p.array(a), fn(_) { "nested" })]),
      )
      Ok(#(p.map(p.array(b), fn(_) { "first" }), second))
    })
  let assert Ok(named) =
    p.recursive("named", fn(self) {
      use body <- result.try(plan_helpers.named_children(self))
      Ok(p.map(body, fn(value) { NamedTree(value.0, value.1, value.2) }))
    })
  let assert Ok(packet) =
    p.recursive("packet", fn(self) {
      Ok(
        p.map(plan_helpers.packet(p.array(self)), fn(value) {
          PacketTree(value.0, value.1, value.2)
        }),
      )
    })
  let assert Ok(fields) =
    p.required(
      p.record(fn(label) { fn(tree) { #(label, tree) } }),
      "label",
      p.text(),
    )
  let assert Ok(fields) =
    p.default_field(fields, "tree", p.lift(definition), p.Text("default"))
  let full_default = p.finish(p.finish_record(fields, p.Open))
  let assert Ok(provider) =
    p.recursive("provider", fn(self) {
      plan_helpers.provider(
        self,
        Leaf,
        fn(children) { Branch(option.unwrap(children, [])) },
        fn(entries) { Branch(list.map(entries, fn(entry) { entry.1 })) },
      )
    })
  let leaf = p.Object([#("kind", p.Text("leaf")), #("value", p.Text("x"))])
  let assert Ok(constrained) =
    p.recursive("constraints", fn(self) {
      use children <- result.try(plan_helpers.constrained_children(self))
      use keys <- result.try(plan_helpers.keyed_children(self))
      p.any_of([
        p.map(p.text(), Leaf),
        p.map(children, Branch),
        p.map(keys, fn(entries) {
          Branch(list.map(entries, fn(entry) { entry.1 }))
        }),
      ])
    })
  let constraint_values =
    list.append(
      samples(),
      list.flat_map(samples(), fn(value) {
        [
          p.Array([p.Text("x"), value]),
          p.Array([p.Text("x"), p.Text("y"), value]),
          p.Object([#("bad/~", value)]),
          p.Object([#("__proto__", value)]),
        ]
      }),
    )
  let provider_values =
    list.append(
      samples(),
      list.append(
        [
          leaf,
          p.Object([#("kind", p.Text("branch")), #("children", p.Null)]),
          p.Object([
            #("kind", p.Text("branch")),
            #("children", p.Array([leaf, leaf])),
          ]),
          p.Object([
            #("kind", p.Text("branch")),
            #("children", p.Array([leaf, leaf, leaf])),
          ]),
          p.Object([
            #("kind", p.Text("index")),
            #("entries", p.Object([#("__proto__", leaf)])),
          ]),
        ],
        list.flat_map(samples(), fn(value) {
          [
            p.Object([#("kind", p.Text("leaf")), #("value", value)]),
            p.Object([#("kind", p.Text("branch")), #("children", value)]),
            p.Object([#("kind", p.Text("index")), #("entries", value)]),
          ]
        }),
      ),
    )
  json.to_string(
    json.array(
      [
        fixture("self", definition, samples()),
        fixture("exclusive-recursive", exclusive, samples()),
        fixture("exclusive-duplicate", p.finish(duplicate), samples()),
        fixture(
          "exclusive-overlap",
          p.finish(overlapping),
          list.append(samples(), [p.Text("special"), p.Text("other")]),
        ),
        fixture("composed", outer, samples()),
        fixture(
          "default",
          p.finish(default),
          list.map(samples(), fn(value) { p.Object([#("tree/~", value)]) })
            |> list.append([p.Object([])]),
        ),
        fixture("pair-first", first, samples()),
        fixture("pair-second", second, samples()),
        fixture("provider-features", provider, provider_values),
        fixture("auxiliary-constraints", constrained, constraint_values),
        fixture("named-record", named, record_samples()),
        fixture("heterogeneous-tuple", packet, tuple_samples()),
        fixture(
          "full-default-record",
          full_default,
          list.map(samples(), fn(value) {
            p.Object([#("label", p.Text("x")), #("tree", value)])
          })
            |> list.append([
              p.Object([#("label", p.Text("x"))]),
              p.Object([#("label", p.Boolean(False))]),
              p.Object([#("label", p.Text("x")), #("extra", p.Boolean(True))]),
            ]),
        ),
        fixture(
          "empty-tuple",
          p.finish(p.finish_tuple(p.tuple(Nil))),
          samples(),
        ),
      ],
      fn(json) { json },
    ),
  )
  |> io.println
}
