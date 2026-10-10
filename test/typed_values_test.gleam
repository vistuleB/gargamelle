import concord as s
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

type Person {
  Person(name: String, nickname: Option(Option(String)), age: Int)
}

type Event {
  Named(Person)
  Empty
}

fn person_record() {
  let assert Ok(r) =
    s.record(fn(name) {
      fn(nickname) { fn(age) { Person(name, nickname, age) } }
    })
    |> s.required("name", s.text())
  let assert Ok(r) = s.optional(r, "nickname", s.nullable(s.text()))
  let assert Ok(default) = s.parse("42")
  let assert Ok(r) = s.defaulted(r, "age", s.safe_integer(), default)
  r
}

pub fn typed_record_test() {
  let d = s.finish(person_record(), s.Closed)
  let assert Ok(v) = s.parse("{\"name\":\"Ada\",\"nickname\":null}")
  s.decode(d, v) |> should.equal(Ok(Person("Ada", Some(None), 42)))
  let assert Ok(v) = s.parse("{\"age\":20,\"name\":\"Ada\"}")
  s.decode(d, v) |> should.equal(Ok(Person("Ada", None, 20)))
}

pub fn typed_variant_test() {
  let person =
    s.variant("person", person_record(), s.Closed)
    |> s.variant_map(Named)
    |> s.variant_description("A person")
  let empty = s.variant("empty", s.record(Empty), s.Closed)
  let assert Ok(d) = s.tagged("kind", [person, empty])
  let assert Ok(v) = s.parse("{\"kind\":\"person\",\"name\":\"Ada\"}")
  s.decode(d, v) |> should.equal(Ok(Named(Person("Ada", None, 42))))
  let assert Ok(v) = s.parse("{\"kind\":\"empty\"}")
  s.decode(d, v) |> should.equal(Ok(Empty))
}

pub fn dictionary_and_array_values_test() {
  let d = s.dictionary(s.array(s.safe_integer()))
  let assert Ok(v) = s.parse("{\"__proto__\":[3,1,3],\"\":[]}")
  let assert Ok(values) = s.decode(d, v)
  list.key_find(values, "__proto__") |> should.equal(Ok([3, 1, 3]))
  list.key_find(values, "") |> should.equal(Ok([]))
}

pub fn annotated_two_fields_regression_test() {
  let assert Ok(r) =
    s.record(fn(a) { fn(b) { #(a, b) } }) |> s.required("a", s.text())
  let assert Ok(r) = s.required(r, "b", s.description(s.text(), "second"))
  let d = s.description(s.finish(r, s.Closed), "outer")
  let assert Ok(v) = s.parse("{\"a\":\"one\",\"b\":\"two\"}")
  s.decode(d, v) |> should.equal(Ok(#("one", "two")))
  let assert Ok(v) = s.parse("{\"a\":\"one\"}")
  s.decode(d, v) |> should.be_error
}
