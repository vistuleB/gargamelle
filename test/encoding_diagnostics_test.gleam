import gargamelle as s
import gargamelle/encoding as e
import gleam/option.{None, Some}
import gleeunit/should

@external(erlang, "encoding_support", "invalid_text")
@external(javascript, "./encoding_support.mjs", "invalid_text")
fn invalid_text() -> String

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

@external(erlang, "recursion_support", "handoff")
@external(javascript, "./recursion_support.mjs", "handoff")
fn handoff(build: fn() -> a) -> a

pub type Score {
  Score(score: Int)
}

pub type Answers {
  Answers(answers: List(Score))
}

fn score_encoder() {
  let assert Ok(fields) =
    e.field(e.record(), "score", e.safe_integer(), fn(value: Score) {
      value.score
    })
  e.finish(fields)
}

fn answers_encoder() {
  let assert Ok(fields) =
    e.field(e.record(), "answers", e.array(score_encoder()), fn(value: Answers) {
      value.answers
    })
  e.finish(fields)
}

pub fn nested_record_array_failure_identifies_encoded_field_test() {
  let bad = 9_007_199_254_740_991 + 1
  e.encode_json(answers_encoder(), Answers([Score(1), Score(2), Score(bad)]))
  |> should.equal(Error(e.InvalidValue("/answers/2/score", e.UnsafeInteger)))
  e.encode_json(answers_encoder(), Answers([Score(1), Score(2), Score(3)]))
  |> should.be_ok
}

pub fn pointers_escape_keys_and_refer_to_encoded_shape_test() {
  let assert Ok(fields) =
    e.field(e.record(), "a/~", e.array(e.safe_integer()), fn(values) { values })
  let bad = 9_007_199_254_740_991 + 1
  e.encode_json(e.finish(fields), [0, bad])
  |> should.equal(Error(e.InvalidValue("/a~1~0/1", e.UnsafeInteger)))
  let assert Ok(fields) =
    e.field(e.record(), "", e.array(e.safe_integer()), fn(values) { values })
  e.encode_json(e.finish(fields), [bad])
  |> should.equal(Error(e.InvalidValue("//0", e.UnsafeInteger)))
  let assert Ok(fields) =
    e.field(e.record(), "payload", e.array(e.safe_integer()), fn(value: Score) {
      [value.score]
    })
  e.encode_json(e.finish(fields), Score(bad))
  |> should.equal(Error(e.InvalidValue("/payload/0", e.UnsafeInteger)))
}

pub fn string_admission_retains_leaf_path_and_wrappers_add_no_segments_test() {
  e.encode_json(e.text(), invalid_text())
  |> should.equal(Error(e.InvalidValue("", e.NonScalarString)))
  let assert Ok(fields) =
    e.field(e.record(), "labels", e.array(e.nullable(e.text())), fn(values) {
      values
    })
  e.encode_json(e.finish(fields), [None, Some(invalid_text())])
  |> should.equal(Error(e.InvalidValue("/labels/1", e.NonScalarString)))
  let assert Ok(fields) =
    e.optional_field(e.record(), "alias", e.text(), fn(value) { value })
  e.encode_json(e.finish(fields), Some(invalid_text()))
  |> should.equal(Error(e.InvalidValue("/alias", e.NonScalarString)))
  e.encode_json(e.finish(fields), None) |> should.be_ok
  let encoder = e.choice(e.text(), e.safe_integer())
  e.encode_json(encoder, Ok(invalid_text()))
  |> should.equal(Error(e.InvalidValue("", e.NonScalarString)))
  e.encode_json(encoder, Error(9_007_199_254_740_991 + 1))
  |> should.equal(Error(e.InvalidValue("", e.UnsafeInteger)))
}

pub fn invalid_field_declarations_identify_key_without_running_getters_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let bad = invalid_text()
  e.field(e.record(), bad, e.text(), fn(value) {
    tick()
    value
  })
  |> should.equal(Error(e.InvalidField(bad, e.NonScalarKey)))
  let assert Ok(fields) =
    e.field(e.record(), "a/~", e.text(), fn(value) {
      tick()
      value
    })
  e.optional_field(fields, "a/~", e.text(), fn(value) {
    tick()
    Some(value)
  })
  |> should.equal(Error(e.InvalidField("a/~", e.DuplicateKey)))
  count() |> should.equal(0)
}

pub fn first_failure_stops_later_elements_and_fields_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let encoder =
    e.array(
      e.contramap(e.safe_integer(), fn(value) {
        tick()
        value
      }),
    )
  e.encode_json(encoder, [0, 9_007_199_254_740_991 + 1, 1])
  |> should.equal(Error(e.InvalidValue("/1", e.UnsafeInteger)))
  count() |> should.equal(2)
  let assert Ok(fields) =
    e.field(e.record(), "first", e.safe_integer(), fn(value) { value })
  let assert Ok(fields) =
    e.field(fields, "later", e.safe_integer(), fn(_) { panic as "Later getter" })
  e.encode_json(e.finish(fields), 9_007_199_254_740_991 + 1)
  |> should.equal(Error(e.InvalidValue("/first", e.UnsafeInteger)))
}

pub type Tree {
  Tree(score: Int, children: List(Tree))
}

pub fn recursive_error_paths_survive_creator_process_exit_test() {
  let encoder =
    handoff(fn() {
      let assert Ok(encoder) =
        e.recursive(fn(self) {
          let assert Ok(fields) =
            e.field(e.record(), "score", e.safe_integer(), fn(tree: Tree) {
              tree.score
            })
          let assert Ok(fields) =
            e.field(fields, "children", e.array(self), fn(tree) {
              tree.children
            })
          Ok(e.finish(fields))
        })
      encoder
    })
  let bad = Tree(0, [Tree(1, [Tree(9_007_199_254_740_991 + 1, [])])])
  e.encode_json(encoder, bad)
  |> should.equal(
    Error(e.InvalidValue("/children/0/children/0/score", e.UnsafeInteger)),
  )
}

pub fn encoding_failure_skips_receiving_callbacks_and_preserves_errors_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let contract =
    s.contract(
      s.map(s.safe_integer(), fn(value) {
        tick()
        value
      }),
    )
    |> s.require("Count callback", fn(_) {
      tick()
      Ok(Nil)
    })
  let receiver = s.json_boundary(contract, fn(_) { tick() })
  let output = e.output_boundary(e.safe_integer(), receiver)
  e.send(output, 9_007_199_254_740_991 + 1)
  |> should.equal(Error(e.InvalidValue("", e.UnsafeInteger)))
  e.encode(e.codec(e.safe_integer(), contract), 9_007_199_254_740_991 + 1)
  |> should.equal(Error(e.InvalidValue("", e.UnsafeInteger)))
  count() |> should.equal(0)
  e.send(output, 42) |> should.equal(Ok(Nil))
  count() |> should.equal(3)
}
