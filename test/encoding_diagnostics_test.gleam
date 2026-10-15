import gargamelle as s
import gargamelle/boundary as gargamelle_boundary
import gargamelle/encoding as gargamelle_encoding
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
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "score",
      gargamelle_encoding.safe_integer(),
      fn(value: Score) { value.score },
    )
  gargamelle_encoding.finish(fields)
}

fn answers_encoder() {
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "answers",
      gargamelle_encoding.array(score_encoder()),
      fn(value: Answers) { value.answers },
    )
  gargamelle_encoding.finish(fields)
}

pub fn nested_record_array_failure_identifies_encoded_field_test() {
  let bad = 9_007_199_254_740_991 + 1
  gargamelle_encoding.encode_json(
    answers_encoder(),
    Answers([Score(1), Score(2), Score(bad)]),
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/answers/2/score",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  gargamelle_encoding.encode_json(
    answers_encoder(),
    Answers([Score(1), Score(2), Score(3)]),
  )
  |> should.be_ok
}

pub fn pointers_escape_keys_and_refer_to_encoded_shape_test() {
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "a/~",
      gargamelle_encoding.array(gargamelle_encoding.safe_integer()),
      fn(values) { values },
    )
  let bad = 9_007_199_254_740_991 + 1
  gargamelle_encoding.encode_json(gargamelle_encoding.finish(fields), [0, bad])
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/a~1~0/1",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "",
      gargamelle_encoding.array(gargamelle_encoding.safe_integer()),
      fn(values) { values },
    )
  gargamelle_encoding.encode_json(gargamelle_encoding.finish(fields), [bad])
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "//0",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "payload",
      gargamelle_encoding.array(gargamelle_encoding.safe_integer()),
      fn(value: Score) { [value.score] },
    )
  gargamelle_encoding.encode_json(
    gargamelle_encoding.finish(fields),
    Score(bad),
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/payload/0",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
}

pub fn string_admission_retains_leaf_path_and_wrappers_add_no_segments_test() {
  gargamelle_encoding.encode_json(gargamelle_encoding.text(), invalid_text())
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "",
      gargamelle_encoding.NonScalarString,
    )),
  )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "labels",
      gargamelle_encoding.array(
        gargamelle_encoding.nullable(gargamelle_encoding.text()),
      ),
      fn(values) { values },
    )
  gargamelle_encoding.encode_json(gargamelle_encoding.finish(fields), [
    None,
    Some(invalid_text()),
  ])
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/labels/1",
      gargamelle_encoding.NonScalarString,
    )),
  )
  let assert Ok(fields) =
    gargamelle_encoding.optional_field(
      gargamelle_encoding.record(),
      "alias",
      gargamelle_encoding.text(),
      fn(value) { value },
    )
  gargamelle_encoding.encode_json(
    gargamelle_encoding.finish(fields),
    Some(invalid_text()),
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/alias",
      gargamelle_encoding.NonScalarString,
    )),
  )
  gargamelle_encoding.encode_json(gargamelle_encoding.finish(fields), None)
  |> should.be_ok
  let encoder =
    gargamelle_encoding.choice(
      gargamelle_encoding.text(),
      gargamelle_encoding.safe_integer(),
    )
  gargamelle_encoding.encode_json(encoder, Ok(invalid_text()))
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "",
      gargamelle_encoding.NonScalarString,
    )),
  )
  gargamelle_encoding.encode_json(encoder, Error(9_007_199_254_740_991 + 1))
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
}

pub fn invalid_field_declarations_identify_key_without_running_getters_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let bad = invalid_text()
  gargamelle_encoding.field(
    gargamelle_encoding.record(),
    bad,
    gargamelle_encoding.text(),
    fn(value) {
      tick()
      value
    },
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidField(
      bad,
      gargamelle_encoding.NonScalarKey,
    )),
  )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "a/~",
      gargamelle_encoding.text(),
      fn(value) {
        tick()
        value
      },
    )
  gargamelle_encoding.optional_field(
    fields,
    "a/~",
    gargamelle_encoding.text(),
    fn(value) {
      tick()
      Some(value)
    },
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidField(
      "a/~",
      gargamelle_encoding.DuplicateKey,
    )),
  )
  count() |> should.equal(0)
}

pub fn first_failure_stops_later_elements_and_fields_test() {
  let #(tick, count) = counter(fn(tick, count) { #(tick, count) })
  let encoder =
    gargamelle_encoding.array(
      gargamelle_encoding.contramap(
        gargamelle_encoding.safe_integer(),
        fn(value) {
          tick()
          value
        },
      ),
    )
  gargamelle_encoding.encode_json(encoder, [0, 9_007_199_254_740_991 + 1, 1])
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/1",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  count() |> should.equal(2)
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "first",
      gargamelle_encoding.safe_integer(),
      fn(value) { value },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "later",
      gargamelle_encoding.safe_integer(),
      fn(_) { panic as "Later getter" },
    )
  gargamelle_encoding.encode_json(
    gargamelle_encoding.finish(fields),
    9_007_199_254_740_991 + 1,
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/first",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
}

pub type Tree {
  Tree(score: Int, children: List(Tree))
}

pub fn recursive_error_paths_survive_creator_process_exit_test() {
  let encoder =
    handoff(fn() {
      let assert Ok(encoder) =
        gargamelle_encoding.recursive(fn(self) {
          let assert Ok(fields) =
            gargamelle_encoding.field(
              gargamelle_encoding.record(),
              "score",
              gargamelle_encoding.safe_integer(),
              fn(tree: Tree) { tree.score },
            )
          let assert Ok(fields) =
            gargamelle_encoding.field(
              fields,
              "children",
              gargamelle_encoding.array(self),
              fn(tree) { tree.children },
            )
          Ok(gargamelle_encoding.finish(fields))
        })
      encoder
    })
  let bad = Tree(0, [Tree(1, [Tree(9_007_199_254_740_991 + 1, [])])])
  gargamelle_encoding.encode_json(encoder, bad)
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/children/0/children/0/score",
      gargamelle_encoding.UnsafeInteger,
    )),
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
  let receiver = gargamelle_boundary.json(contract, fn(_) { tick() })
  let output =
    gargamelle_boundary.output(gargamelle_encoding.safe_integer(), receiver)
  gargamelle_boundary.send(output, 9_007_199_254_740_991 + 1)
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  gargamelle_encoding.encode(
    gargamelle_encoding.codec(gargamelle_encoding.safe_integer(), contract),
    9_007_199_254_740_991 + 1,
  )
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
  count() |> should.equal(0)
  gargamelle_boundary.send(output, 42) |> should.equal(Ok(Nil))
  count() |> should.equal(3)
}
