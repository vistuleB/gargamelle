import gargamelle as g
import gargamelle/boundary as gargamelle_boundary
import gargamelle/codec_record
import gargamelle/encoding as gargamelle_encoding
import gargamelle/record
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

@external(erlang, "recursion_support", "counter")
@external(javascript, "./recursion_support.mjs", "counter")
fn counter(make: fn(fn() -> Nil, fn() -> Int) -> a) -> a

fn text() {
  gargamelle_encoding.codec(
    gargamelle_encoding.string(),
    g.contract(g.string()),
  )
}

fn integer() {
  gargamelle_encoding.codec(
    gargamelle_encoding.safe_integer(),
    g.contract(g.safe_integer()),
  )
}

fn definition(codec) {
  codec |> gargamelle_encoding.contract |> g.contract_definition
}

fn array(child) {
  gargamelle_encoding.codec(
    gargamelle_encoding.array(gargamelle_encoding.encoder(child)),
    g.contract(g.array(definition(child))),
  )
}

pub type Person {
  Person(name: String, nickname: Option(Option(String)), active: Bool)
}

pub fn person_codec(policy) {
  let nullable_text =
    gargamelle_encoding.codec(
      gargamelle_encoding.nullable(gargamelle_encoding.string()),
      g.contract(g.nullable(g.string())),
    )
  let boolean =
    gargamelle_encoding.codec(
      gargamelle_encoding.boolean(),
      g.contract(g.boolean()),
    )
  codec_record.start(record.start3(Person))
  |> codec_record.required("name", text(), fn(p: Person) { p.name })
  |> codec_record.optional("nickname", nullable_text, fn(p: Person) {
    p.nickname
  })
  |> codec_record.defaulted("active", boolean, g.json_bool(True), fn(p: Person) {
    p.active
  })
  |> codec_record.finish(policy)
}

pub fn optional_defaulted_null_and_actual_getter_value_test() {
  let assert Ok(codec) = person_codec(g.Strict)
  list.each(
    [
      #("{\"name\":\"Azrael\"}", Person("Azrael", None, True)),
      #(
        "{\"name\":\"Azrael\",\"nickname\":null,\"active\":false}",
        Person("Azrael", Some(None), False),
      ),
      #(
        "{\"name\":\"Azrael\",\"nickname\":\"A\"}",
        Person("Azrael", Some(Some("A")), True),
      ),
    ],
    fn(example) {
      let assert Ok(json) = g.parse(example.0)
      g.decode(definition(codec), json) |> should.equal(Ok(example.1))
      let assert Ok(verified) = gargamelle_encoding.encode(codec, example.1)
      g.decode(definition(codec), g.verified_json(verified))
      |> should.equal(Ok(example.1))
    },
  )
  let assert Ok(verified) =
    gargamelle_encoding.encode(codec, Person("Azrael", None, True))
  g.to_string(g.verified_json(verified), g.Compact)
  |> should.equal("{\"active\":true,\"name\":\"Azrael\"}")
  let assert Ok(verified) =
    gargamelle_encoding.encode(codec, Person("Azrael", Some(None), False))
  g.to_string(g.verified_json(verified), g.Compact)
  |> should.equal("{\"active\":false,\"name\":\"Azrael\",\"nickname\":null}")
  let assert Ok(json) = g.parse("{\"name\":\"Azrael\",\"active\":null}")
  g.decode(definition(codec), json) |> should.be_error
}

pub fn schema_decoding_and_errors_match_existing_record_test() {
  list.each([g.Strict, g.Open], fn(policy) {
    let assert Ok(codec) = person_codec(policy)
    let assert Ok(baseline) =
      record.start3(Person)
      |> record.required("name", g.string())
      |> record.optional("nickname", g.nullable(g.string()))
      |> record.defaulted("active", g.boolean(), g.json_bool(True))
      |> record.finish(policy)
    g.schema_string(definition(codec), g.Compact)
    |> should.equal(g.schema_string(baseline, g.Compact))
    list.each(
      [
        "{}", "[]", "{\"name\":false}", "{\"name\":\"A\"}",
        "{\"name\":\"A\",\"nickname\":12}", "{\"name\":\"A\",\"extra\":true}",
      ],
      fn(source) {
        let assert Ok(json) = g.parse(source)
        g.decode(definition(codec), json)
        |> should.equal(g.decode(baseline, json))
        g.validate(definition(codec), json)
        |> should.equal(g.validate(baseline, json))
      },
    )
  })
}

pub fn open_decoding_and_reencoding_discards_unknown_fields_test() {
  let assert Ok(open) = person_codec(g.Open)
  let assert Ok(strict) = person_codec(g.Strict)
  let assert Ok(json) = g.parse("{\"name\":\"A\",\"extra\":42}")
  g.decode(definition(strict), json) |> should.be_error
  let assert Ok(value) = g.decode(definition(open), json)
  let assert Ok(verified) = gargamelle_encoding.encode(open, value)
  g.to_string(g.verified_json(verified), g.Compact)
  |> should.equal("{\"active\":true,\"name\":\"A\"}")
}

fn checked_text(tick) {
  let contract =
    g.contract(g.string())
    |> g.require("nonempty", fn(value) {
      tick()
      case value == "" {
        True -> Error([g.Violation("", "empty")])
        False -> Ok(Nil)
      }
    })
  gargamelle_encoding.codec(gargamelle_encoding.string(), contract)
}

pub fn semantic_children_rejected_in_every_position_without_callbacks_test() {
  counter(fn(tick, count) {
    let child = checked_text(tick)
    codec_record.start(record.start1(fn(value) { value }))
    |> codec_record.required("required", child, fn(value) { value })
    |> codec_record.finish(g.Strict)
    |> should.equal(
      Error(codec_record.SemanticRequirements("required", ["nonempty"])),
    )
    codec_record.start(record.start1(fn(value) { value }))
    |> codec_record.optional("optional", child, fn(value) { value })
    |> codec_record.finish(g.Strict)
    |> should.equal(
      Error(codec_record.SemanticRequirements("optional", ["nonempty"])),
    )
    let assert Ok(default) = g.json_string("valid")
    codec_record.start(record.start1(fn(value) { value }))
    |> codec_record.defaulted("defaulted", child, default, fn(value) { value })
    |> codec_record.finish(g.Strict)
    |> should.equal(
      Error(codec_record.SemanticRequirements("defaulted", ["nonempty"])),
    )
    count() |> should.equal(0)
  })
}

pub fn construction_errors_retain_field_and_original_definition_cause_test() {
  let assert Error(cause) =
    record.start2(fn(a, b) { #(a, b) })
    |> record.required("same", g.string())
    |> record.required("same", g.string())
  codec_record.start(record.start2(fn(a, b) { #(a, b) }))
  |> codec_record.required("same", text(), fn(value: #(String, String)) {
    value.0
  })
  |> codec_record.required("same", text(), fn(value: #(String, String)) {
    value.1
  })
  |> codec_record.finish(g.Strict)
  |> should.equal(Error(codec_record.FieldDefinition("same", cause)))
  let assert Error(cause) =
    record.start1(fn(value) { value })
    |> record.defaulted("bad", g.string(), g.json_bool(True))
  codec_record.start(record.start1(fn(value) { value }))
  |> codec_record.defaulted("bad", text(), g.json_bool(True), fn(value) {
    value
  })
  |> codec_record.finish(g.Strict)
  |> should.equal(Error(codec_record.FieldDefinition("bad", cause)))
}

pub fn first_error_preserved_but_arguments_still_evaluate_test() {
  counter(fn(tick, count) {
    let cause = g.DefinitionError("original construction failure")
    let failed: Result(
      g.Record(fn(String) -> fn(String) -> String, Nil),
      g.DefinitionError,
    ) = Error(cause)
    let child = fn() {
      tick()
      checked_text(tick)
    }
    codec_record.start(failed)
    |> codec_record.required("one", child(), fn(value) { value })
    |> codec_record.required("two", child(), fn(value) { value })
    |> codec_record.finish(g.Strict)
    |> should.equal(Error(codec_record.Definition(cause)))
    count() |> should.equal(2)
  })
}

pub fn all_error_variants_propagate_unchanged_test() {
  list.each(
    [
      codec_record.Definition(g.DefinitionError("start")),
      codec_record.FieldDefinition("field", g.DefinitionError("definition")),
      codec_record.FieldEncoding(
        "field",
        gargamelle_encoding.InvalidField(
          "field",
          gargamelle_encoding.DuplicateKey,
        ),
      ),
      codec_record.SemanticRequirements("field", ["check"]),
    ],
    fn(error) {
      let failed: Result(
        codec_record.Fields(
          fn(String) -> fn(Option(String)) -> fn(String) -> String,
          String,
        ),
        codec_record.BuildError,
      ) = Error(error)
      let assert Ok(default) = g.json_string("default")
      failed
      |> codec_record.required("required", text(), fn(value) { value })
      |> codec_record.optional("optional", text(), fn(_) { None })
      |> codec_record.defaulted("defaulted", text(), default, fn(value) {
        value
      })
      |> codec_record.finish(g.Strict)
      |> should.equal(Error(error))
    },
  )
}

pub fn constructor_and_getter_execution_timing_test() {
  counter(fn(convert, conversions) {
    counter(fn(construct, constructions) {
      counter(fn(get, getters) {
        let child =
          gargamelle_encoding.codec(
            gargamelle_encoding.string(),
            g.contract(
              g.map(g.string(), fn(value) {
                convert()
                value
              }),
            ),
          )
        let assert Ok(default) = g.json_string("default")
        let assert Ok(codec) =
          codec_record.start(
            record.start1(fn(value) {
              construct()
              value
            }),
          )
          |> codec_record.defaulted("name", child, default, fn(value) {
            get()
            value
          })
          |> codec_record.finish(g.Strict)
        let _ = g.schema_string(definition(codec), g.Compact)
        constructions() |> should.equal(0)
        conversions() |> should.equal(0)
        getters() |> should.equal(0)
        let assert Ok(verified) = gargamelle_encoding.encode(codec, "value")
        constructions() |> should.equal(0)
        conversions() |> should.equal(0)
        getters() |> should.equal(1)
        g.decode(definition(codec), g.verified_json(verified))
        |> should.equal(Ok("value"))
        constructions() |> should.equal(1)
        conversions() |> should.equal(1)
      })
    })
  })
}

pub type Entry {
  Entry(amount: Int)
}

pub type History {
  History(entries: List(Entry))
}

fn history_codec() {
  let assert Ok(entry) =
    codec_record.start(record.start1(Entry))
    |> codec_record.required("a/~", integer(), fn(e: Entry) { e.amount })
    |> codec_record.finish(g.Strict)
  codec_record.start(record.start1(History))
  |> codec_record.required("entries", array(entry), fn(h: History) { h.entries })
  |> codec_record.finish(g.Strict)
}

pub fn nested_records_arrays_and_700_entry_roundtrip_test() {
  let assert Ok(codec) = history_codec()
  let history =
    History(
      int.range(1, 701, [], fn(entries, value) { [Entry(value), ..entries] }),
    )
  let assert Ok(verified) = gargamelle_encoding.encode(codec, history)
  g.decode(definition(codec), g.verified_json(verified))
  |> should.equal(Ok(history))
  let bad = History([Entry(1), Entry(9_007_199_254_740_991 + 1)])
  gargamelle_encoding.encode(codec, bad)
  |> should.equal(
    Error(gargamelle_encoding.InvalidValue(
      "/entries/1/a~1~0",
      gargamelle_encoding.UnsafeInteger,
    )),
  )
}

pub fn extracted_encoder_is_unchecked_and_receiver_contract_authoritative_test() {
  let assert Ok(codec) =
    codec_record.start(record.start1(fn(value) { value }))
    |> codec_record.required("value", integer(), fn(value) { value })
    |> codec_record.finish(g.Strict)
  let contract =
    gargamelle_encoding.contract(codec)
    |> g.require("positive", fn(value) {
      case value > 0 {
        True -> Ok(Nil)
        False -> Error([g.Violation("/value", "not positive")])
      }
    })
  let checked =
    gargamelle_encoding.codec(gargamelle_encoding.encoder(codec), contract)
  gargamelle_encoding.encode(checked, -1) |> should.be_error
  gargamelle_encoding.encode_json(gargamelle_encoding.encoder(checked), -1)
  |> should.be_ok
  counter(fn(tick, count) {
    let receiver = gargamelle_boundary.json(contract, fn(_) { tick() })
    let output =
      gargamelle_boundary.output(gargamelle_encoding.encoder(codec), receiver)
    gargamelle_boundary.send(output, -1) |> should.be_error
    count() |> should.equal(0)
    gargamelle_boundary.send(output, 1) |> should.equal(Ok(Nil))
    count() |> should.equal(1)
  })
}

pub fn mismatched_constructor_getter_is_not_an_inverse_guarantee_test() {
  let assert Ok(codec) =
    codec_record.start(record.start1(fn(value) { value <> "!" }))
    |> codec_record.required("value", text(), fn(value) { value })
    |> codec_record.finish(g.Strict)
  let assert Ok(verified) = gargamelle_encoding.encode(codec, "hello")
  g.decode(definition(codec), g.verified_json(verified))
  |> should.equal(Ok("hello!"))
}

pub fn checked_encoding_rejects_structurally_invalid_getter_output_test() {
  let child =
    gargamelle_encoding.codec(
      gargamelle_encoding.string(),
      g.contract(g.string_constant("accepted")),
    )
  let assert Ok(codec) =
    codec_record.start(record.start1(fn(value) { value }))
    |> codec_record.required("value", child, fn(value) { value })
    |> codec_record.finish(g.Strict)
  gargamelle_encoding.encode(codec, "accepted") |> should.be_ok
  let assert Error(gargamelle_encoding.Contract(g.Structural([
    g.ValidationError(_, path, _, _, _),
  ]))) = gargamelle_encoding.encode(codec, "rejected")
  path |> should.equal("/value")
  gargamelle_encoding.encode_json(
    gargamelle_encoding.encoder(codec),
    "rejected",
  )
  |> should.be_ok
}

pub type Choice {
  Choice(value: Result(Int, String))
}

pub fn child_union_codec_composes_without_changing_branch_semantics_test() {
  let assert Ok(child_definition) =
    g.one_of([
      g.map(g.safe_integer(), Ok),
      g.map(g.string(), Error),
    ])
  let child =
    gargamelle_encoding.codec(
      gargamelle_encoding.result(
        gargamelle_encoding.safe_integer(),
        gargamelle_encoding.string(),
      ),
      g.contract(child_definition),
    )
  let assert Ok(codec) =
    codec_record.start(record.start1(Choice))
    |> codec_record.required("choice", child, fn(value: Choice) { value.value })
    |> codec_record.finish(g.Strict)
  list.each([Choice(Ok(42)), Choice(Error("cancelled"))], fn(value) {
    let assert Ok(verified) = gargamelle_encoding.encode(codec, value)
    g.decode(definition(codec), g.verified_json(verified))
    |> should.equal(Ok(value))
  })
}
