import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import immutable_plan as p
import plan_helpers

@external(erlang, "plan_support", "counter")
@external(javascript, "./plan_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "plan_support", "handoff")
@external(javascript, "./plan_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

fn tree() {
  p.recursive("tree", fn(self) {
    p.any_of([
      p.map(p.text(), Leaf),
      p.map(p.field("children", p.array(self)), Branch),
    ])
  })
}

pub fn self_recursion_builder_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(definition) =
    p.recursive("tree", fn(self) {
      tick()
      p.any_of([
        p.map(p.text(), Leaf),
        p.map(p.field("children", p.array(self)), Branch),
      ])
    })
  let input =
    p.Object([
      #(
        "children",
        p.Array([
          p.Text("leaf"),
          p.Object([#("children", p.Array([p.Text("deep")]))]),
        ]),
      ),
    ])
  p.decode(definition, input)
  |> should.equal(Ok(Branch([Leaf("leaf"), Branch([Leaf("deep")])])))
  p.validate(definition, input) |> should.equal(Ok(Nil))
  string.contains(p.emit(definition), "#/$defs/tree") |> should.be_true
  p.decode(definition, input) |> should.be_ok
  count() |> should.equal(1)
}

pub type First {
  First(List(Second))
}

pub type Second {
  Second(String)
  Next(List(First))
}

pub fn distinct_pair_builder_once_and_handoff_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(#(first, second)) =
    handoff(fn() {
      p.recursive_pair("first", "second", fn(a, b) {
        tick()
        use second <- result.try(
          p.any_of([
            p.map(p.text(), Second),
            p.map(p.array(a), Next),
          ]),
        )
        Ok(#(p.map(p.array(b), First), second))
      })
    })
  p.decode(first, p.Array([p.Text("x"), p.Array([p.Array([])])]))
  |> should.equal(Ok(First([Second("x"), Next([First([])])])))
  p.decode(second, p.Text("x")) |> should.equal(Ok(Second("x")))
  p.emit(first) |> should.not_equal("")
  count() |> should.equal(1)
}

pub fn completed_definition_and_decoded_closure_handoff_test() {
  let assert Ok(definition) = handoff(tree)
  let assert Ok(get_definition) =
    handoff(fn() {
      let assert Ok(local) = tree()
      let closed = p.finish(p.map(p.text(), fn(_) { fn() { local } }))
      p.decode(closed, p.Text("capture"))
    })
  p.decode(definition, p.Text("x")) |> should.equal(Ok(Leaf("x")))
  p.decode(get_definition(), p.Text("y")) |> should.equal(Ok(Leaf("y")))
  p.emit(get_definition()) |> should.equal(p.emit(definition))
}

pub fn composition_and_defaults_test() {
  let assert Ok(definition) = tree()
  let imported = p.lift(definition)
  let assert Ok(with_default) = p.defaulted("tree", imported, p.Text("default"))
  let closed = p.finish(with_default)
  p.decode(closed, p.Object([])) |> should.equal(Ok(Leaf("default")))
  p.decode(closed, p.Object([#("tree", p.Boolean(True))])) |> should.be_error
  let assert Ok(outer) =
    p.recursive("outer", fn(self) {
      p.any_of([p.lift(definition), p.map(p.array(self), Branch)])
    })
  p.decode(outer, p.Array([p.Text("x"), p.Array([])]))
  |> should.equal(Ok(Branch([Leaf("x"), Branch([])])))
  p.emit(outer) |> should.not_equal("")
}

pub fn unresolved_defaults_and_unguarded_recursion_test() {
  p.recursive("loop", fn(self) { Ok(self) }) |> should.be_error
  p.recursive("loop", fn(self) { p.any_of([self, p.text()]) })
  |> should.be_error
  p.recursive_pair("a", "b", fn(a, b) { Ok(#(b, a)) }) |> should.be_error
  p.recursive("default", fn(self) { p.defaulted("child", self, p.Text("x")) })
  |> should.be_error
}

pub fn callback_suppression_and_atomic_validation_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let auxiliary =
    p.map(p.text(), fn(text) {
      panic as "auxiliary converter must never execute"
      text
    })
  let primary =
    p.map(p.text(), fn(text) {
      tick()
      text
    })
  let assert Ok(default) =
    p.defaulted("value", p.requiring(primary, [auxiliary]), p.Text("x"))
  let definition = p.finish(default)
  count() |> should.equal(0)
  p.validate(definition, p.Object([])) |> should.be_ok
  p.emit(definition) |> should.not_equal("")
  count() |> should.equal(0)
  p.decode(definition, p.Object([])) |> should.equal(Ok("x"))
  count() |> should.equal(1)
  let children = p.finish(p.array(primary))
  p.decode(children, p.Array([p.Text("valid"), p.Boolean(True)]))
  |> should.be_error
  count() |> should.equal(1)
}

pub type LabeledTree {
  LabeledTree(String, Option(Bool), List(LabeledTree))
}

fn labeled_tree() -> Result(p.Definition(LabeledTree), String) {
  p.recursive("labeled", fn(self) {
    use body <- result.try(plan_helpers.named_children(self))
    Ok(p.map(body, fn(value) { LabeledTree(value.0, value.1, value.2) }))
  })
}

pub fn curried_records_optional_fields_and_helper_inference_test() {
  let assert Ok(definition) = handoff(labeled_tree)
  let leaf = p.Object([#("name", p.Text("leaf")), #("children", p.Array([]))])
  let input =
    p.Object([
      #("name", p.Text("root")),
      #("enabled", p.Boolean(False)),
      #("children", p.Array([leaf])),
    ])
  p.decode(definition, input)
  |> should.equal(
    Ok(LabeledTree("root", Some(False), [LabeledTree("leaf", None, [])])),
  )
  p.decode(definition, p.Object([#("name", p.Text("missing children"))]))
  |> should.be_error
  p.decode(
    definition,
    p.Object([
      #("name", p.Text("x")),
      #("children", p.Array([])),
      #("enabled", p.Text("bad")),
    ]),
  )
  |> should.be_error
  let assert Ok(closed) = plan_helpers.named_children(p.text())
  p.decode(p.finish(closed), leaf) |> should.equal(Ok(#("leaf", None, [])))
  let fields = p.record(fn(value) { fn(other) { #(value, other) } })
  let assert Ok(fields) = p.required(fields, "same", p.text())
  p.optional(fields, "same", p.boolean()) |> should.be_error
}

pub type PacketTree {
  PacketTree(String, Bool, List(PacketTree))
}

pub fn heterogeneous_tuple_recursive_helper_test() {
  let assert Ok(definition) =
    p.recursive("packet", fn(self) {
      Ok(
        p.map(plan_helpers.packet(p.array(self)), fn(value) {
          PacketTree(value.0, value.1, value.2)
        }),
      )
    })
  let leaf = p.Array([p.Text("leaf"), p.Boolean(False), p.Array([])])
  p.decode(
    definition,
    p.Array([p.Text("root"), p.Boolean(True), p.Array([leaf])]),
  )
  |> should.equal(Ok(PacketTree("root", True, [PacketTree("leaf", False, [])])))
  p.decode(definition, p.Array([p.Text("short"), p.Boolean(True)]))
  |> should.be_error
  p.decode(
    definition,
    p.Array([p.Text("extra"), p.Boolean(True), p.Array([]), p.Text("x")]),
  )
  |> should.be_error
  p.decode(
    definition,
    p.Array([p.Boolean(False), p.Text("swapped"), p.Array([])]),
  )
  |> should.be_error
}

pub type PacketFirst {
  PacketFirst(String, Bool, List(PacketSecond))
}

pub type PacketSecond {
  PacketSecond(String, Bool, List(PacketFirst))
}

pub fn pair_helpers_infer_independent_output_types_test() {
  let assert Ok(#(first, second)) =
    p.recursive_pair("packet_a", "packet_b", fn(a, b) {
      Ok(#(
        p.map(plan_helpers.packet(p.array(b)), fn(value) {
          PacketFirst(value.0, value.1, value.2)
        }),
        p.map(plan_helpers.packet(p.array(a)), fn(value) {
          PacketSecond(value.0, value.1, value.2)
        }),
      ))
    })
  let leaf = p.Array([p.Text("leaf"), p.Boolean(False), p.Array([])])
  p.decode(first, p.Array([p.Text("root"), p.Boolean(True), p.Array([leaf])]))
  |> should.equal(
    Ok(PacketFirst("root", True, [PacketSecond("leaf", False, [])])),
  )
  p.decode(second, leaf) |> should.equal(Ok(PacketSecond("leaf", False, [])))
}

pub fn full_record_defaults_and_constructor_suppression_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(tree) = tree()
  let fields =
    p.record(fn(label) {
      tick()
      fn(value) { #(label, value) }
    })
  let assert Ok(fields) = p.required(fields, "label", p.text())
  let assert Ok(fields) =
    p.default_field(fields, "tree", p.lift(tree), p.Text("default"))
  let definition = p.finish(p.finish_record(fields, p.Open))
  let input = p.Object([#("label", p.Text("x")), #("extra", p.Boolean(True))])
  p.validate(definition, input) |> should.be_ok
  p.emit(definition) |> should.not_equal("")
  count() |> should.equal(0)
  p.decode(definition, input) |> should.equal(Ok(#("x", Leaf("default"))))
  count() |> should.equal(1)
  p.decode(
    definition,
    p.Object([#("label", p.Text("x")), #("tree", p.Boolean(False))]),
  )
  |> should.be_error
  count() |> should.equal(1)
  p.recursive("empty_default", fn(self) {
    p.defaulted("children", p.array(self), p.Array([]))
    |> result.map(fn(_) { p.text() })
  })
  |> should.be_error
  let empty = p.finish(p.finish_tuple(p.tuple(Nil)))
  p.decode(empty, p.Array([])) |> should.equal(Ok(Nil))
  p.decode(empty, p.Array([p.Text("extra")])) |> should.be_error
}

pub fn independent_nested_recursion_and_unfinished_outer_rejection_test() {
  let assert Ok(outer) =
    p.recursive("outer", fn(self) {
      use inner <- result.try(
        p.recursive("inner", fn(inner) {
          plan_helpers.text_or(p.map(p.array(inner), fn(_) { "inner" }))
        }),
      )
      p.any_of([p.lift(inner), p.map(p.array(self), fn(_) { "outer" })])
    })
  p.decode(outer, p.Array([p.Array([p.Text("x")])])) |> should.be_ok
  p.recursive("outer", fn(outer) {
    use _ <- result.try(
      p.recursive("inner", fn(_) {
        Ok(p.map(p.array(outer), fn(_) { "inner" }))
      }),
    )
    Ok(p.text())
  })
  |> should.be_error
}
