import gleam/result
import gleam/string
import gleeunit/should
import immutable_plan as p

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
