import gargamelle as s
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleeunit/should

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

pub type Tree {
  Leaf(String)
  Branch(List(Tree))
}

// Annotation does not expose Evidence or the actual recursion functions.
pub fn children(
  child: s.Plan(a, r),
) -> Result(s.Plan(List(a), r), s.ConstructionError) {
  use constrained <- result.try(s.contains(
    s.array(child),
    s.map(s.string(), fn(_) -> Nil { panic as "auxiliary conversion" }),
    0,
    Some(2),
  ))
  s.bounds(constrained, Some(0), Some(2))
}

fn tree() {
  s.recursive("tree", fn(self) {
    use branch <- result.try(children(self))
    s.one_of([s.map(s.string(), Leaf), s.map(branch, Branch)])
  })
}

pub fn completed_definition_and_closure_survive_creator_exit_test() {
  let assert Ok(definition) = handoff(tree)
  let assert Ok(value) = s.parse("[\"x\",[\"y\"]]")
  s.decode(definition, value)
  |> should.equal(Ok(Branch([Leaf("x"), Branch([Leaf("y")])])))
  let assert Ok(get) =
    handoff(fn() {
      use definition <- result.try(tree())
      let mapped = s.map(s.string(), fn(_) { fn() { definition } })
      let assert Ok(input) = s.parse("\"capture\"")
      Ok(s.decode(mapped, input))
    })
  let assert Ok(get) = get
  s.decode(get(), value)
  |> should.equal(Ok(Branch([Leaf("x"), Branch([Leaf("y")])])))
}

pub fn independent_pair_and_generic_helper_builder_once_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(#(first, second)) =
    handoff(fn() {
      s.recursive_pair("first", "second", fn(a, b) {
        tick()
        use body <- result.try(children(b))
        use other <- result.try(
          s.any_of([
            s.string(),
            s.map(s.array(a), fn(xs) { list.length(xs) |> int_label }),
          ]),
        )
        Ok(#(body, other))
      })
    })
  let assert Ok(input) = s.parse("[\"leaf\",[]]")
  s.decode(first, input) |> should.equal(Ok(["leaf", "array"]))
  let assert Ok(input) = s.parse("[[]]")
  s.decode(second, input) |> should.equal(Ok("array"))
  s.validate(second, input) |> should.be_ok
  s.schema_string(first, s.Compact) |> should.not_equal("")
  count() |> should.equal(1)
}

fn int_label(_count) {
  "array"
}

pub fn recursive_default_evidence_and_atomic_callback_suppression_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let assert Ok(tree) = tree()
  let assert Ok(default) = s.parse("[\"default\"]")
  let assert Ok(fields) =
    s.defaulted(
      s.record(fn(value) { fn(label) { #(value, label) } }),
      "tree",
      s.map(tree, fn(value) {
        tick()
        value
      }),
      default,
    )
  let assert Ok(fields) = s.required(fields, "a/~", s.string())
  let definition = s.finish(fields, s.Strict)
  let assert Ok(input) = s.parse("{\"a/~\":false,\"extra\":true}")
  let assert Error(errors) = s.decode(definition, input)
  list.map(errors, fn(error) { #(error.category, error.path) })
  |> should.equal([#("string_type", "/a~1~0"), #("extra_key", "/extra")])
  count() |> should.equal(0)
  let assert Ok(input) = s.parse("{\"a/~\":\"label\"}")
  s.validate(definition, input) |> should.be_ok
  s.schema_string(definition, s.Compact) |> should.not_equal("")
  count() |> should.equal(0)
  s.decode(definition, input)
  |> should.equal(Ok(#(Branch([Leaf("default")]), "label")))
  count() |> should.equal(1)
}

pub fn construction_resolution_names_and_guards_test() {
  s.recursive("same", fn(outer) {
    use _ <- result.try(
      s.recursive("same", fn(_) { Ok(s.map(s.array(outer), fn(_) { "inner" })) }),
    )
    Ok(s.string())
  })
  |> should.be_error
  let assert Ok(empty) = s.parse("[]")
  s.recursive("unresolved_default", fn(self) {
    s.defaulted(s.record(fn(value) { value }), "children", s.array(self), empty)
    |> result.map(fn(fields) {
      s.map(s.finish(fields, s.Strict), fn(_) { "unused" })
    })
  })
  |> should.be_error
  s.recursive("invalid/name", fn(_) { Ok(s.string()) }) |> should.be_error
  s.recursive("probe", fn(self) { Ok(s.exclude(s.string(), self)) })
  |> should.be_error
}

pub type Captured {
  Captured(fn() -> s.Plan(Captured, s.Recursive(Captured)))
}

pub fn captured_plan_cannot_hide_behind_imported_graph_sharing_test() {
  let assert Ok(completed) =
    s.recursive("captured", fn(self) {
      s.any_of([
        s.map(s.string(), fn(_) { Captured(fn() { self }) }),
        s.map(s.array(self), fn(_) { Captured(fn() { self }) }),
      ])
    })
  let assert Ok(input) = s.parse("\"capture\"")
  let assert Ok(Captured(get)) = s.decode(completed, input)
  s.recursive("inner", fn(inner) {
    s.any_of([
      s.lift(completed),
      s.map(s.array(get()), fn(_) { Captured(fn() { inner }) }),
    ])
  })
  |> should.be_error
}
