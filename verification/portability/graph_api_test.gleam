import gargamelle as s
import gleam/result
import gleeunit/should
import reference_lifetime_test.{Captured}

@external(erlang, "scalar_api", "handoff")
fn handoff(build: fn() -> a) -> a

@external(erlang, "scalar_api", "exception_cleanup")
fn exception_cleanup(run: fn() -> a) -> Bool

pub type Tree {
  Tree(List(Tree))
}

fn tree() {
  s.recursive("tree", fn(self) { Ok(s.map(s.array(self), Tree)) })
}

pub fn captured_completed_definition_handoff_test() {
  let assert Ok(Captured(get)) =
    handoff(fn() {
      let assert Ok(definition) = reference_lifetime_test.captured_definition()
      let assert Ok(input) = s.parse("\"value\"")
      s.decode(definition, input)
    })
  let assert Ok(input) = s.parse("\"value\"")
  s.validate(get(), input) |> should.equal(Ok(Nil))
}

pub fn process_handoff_test() {
  let assert Ok(definition) = handoff(tree)
  let assert Ok(value) = s.parse("[[],[[]]]")
  s.decode(definition, value)
  |> should.equal(Ok(Tree([Tree([]), Tree([Tree([])])])))
  s.validate(definition, value) |> should.equal(Ok(Nil))
  let schema = s.schema_string(definition, s.Compact)
  schema |> should.equal(s.schema_string(definition, s.Compact))
  let assert Ok(default) = s.parse("[]")
  let assert Ok(fields) =
    s.defaulted(s.record(fn(v) { v }), "tree", definition, default)
  let assert Ok(missing) = s.parse("{}")
  s.decode(s.finish(fields, s.Strict), missing) |> should.equal(Ok(Tree([])))
}

pub type First {
  First(List(Second))
}

pub type Second {
  Second(List(First))
}

pub fn pair_handoff_test() {
  let assert Ok(#(a, b)) =
    handoff(fn() {
      s.recursive_pair("first", "second", fn(first, second) {
        Ok(#(s.map(s.array(second), First), s.map(s.array(first), Second)))
      })
    })
  let assert Ok(value) = s.parse("[[]]")
  s.decode(a, value) |> should.equal(Ok(First([Second([])])))
  s.decode(b, value) |> should.equal(Ok(Second([First([])])))
  s.schema_string(a, s.Compact) |> should.not_equal("")
  s.schema_string(b, s.Compact) |> should.not_equal("")
}

pub fn foreign_context_composition_test() {
  let assert Ok(first) = handoff(tree)
  let assert Ok(second) =
    handoff(fn() {
      s.recursive("second", fn(self) {
        s.any_of([s.map(s.array(self), Tree), s.lift(first)])
      })
    })
  let assert Ok(input) = s.parse("[[]]")
  s.validate(second, input) |> should.equal(Ok(Nil))
  s.schema_string(second, s.Compact) |> should.not_equal("")
}

pub fn failure_cleanup_test() {
  s.recursive("invalid", fn(self) { Ok(self) }) |> should.be_error
  s.recursive("early", fn(_) { Error(s.DefinitionError("early")) })
  |> should.be_error
  let assert Ok(definition) = tree()
  let assert Ok(value) = s.parse("[]")
  s.decode(definition, value) |> should.equal(Ok(Tree([])))
}

pub fn operational_cleanup_test() {
  exception_cleanup(fn() {
    s.recursive("boom", fn(_) { panic as "builder failure" })
  })
  |> should.be_true
  let assert Ok(definition) = tree()
  let assert Ok(value) = s.parse("[]")
  exception_cleanup(fn() {
    s.decode(s.map(definition, fn(_) { panic as "converter failure" }), value)
  })
  |> should.be_true
  // A nested builder failure must not affect the enclosing immutable plan.
  let assert Ok(nested) =
    s.recursive("nested", fn(self) {
      exception_cleanup(fn() {
        s.recursive("boom", fn(_) { panic as "nested builder failure" })
      })
      |> should.be_true
      Ok(s.map(s.array(self), Tree))
    })
  s.decode(nested, value) |> should.equal(Ok(Tree([])))
  s.decode(definition, value) |> should.equal(Ok(Tree([])))
}

pub fn conflict_cleanup_test() {
  let assert Ok(a) = s.named("same", s.string())
  let assert Ok(b) = s.named("same", s.boolean())
  let assert Ok(definition) =
    s.any_of([s.map(a, fn(_) { Nil }), s.map(b, fn(_) { Nil })])
  exception_cleanup(fn() { s.schema_string(definition, s.Compact) }) |> should.be_true
  let assert Ok(valid) = tree()
  s.schema_string(valid, s.Compact) |> should.not_equal("")
}

pub fn shared_guard_layers_test() {
  let assert Ok(definition) =
    s.recursive("shared", fn(self) {
      use base <- result.try(
        s.any_of([s.string(), s.map(s.array(self), fn(_) { "tree" })]),
      )
      Ok(layers(base, 22))
    })
  should.not_equal(definition, s.string())
}

fn layers(
  def: s.Plan(String, recursion),
  count: Int,
) -> s.Plan(String, recursion) {
  case count {
    0 -> def
    _ -> {
      let assert Ok(next) = s.any_of([def, def])
      layers(next, count - 1)
    }
  }
}
