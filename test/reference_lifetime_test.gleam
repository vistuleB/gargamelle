import gargamelle as s
import gleeunit/should

pub type Captured {
  Captured(fn() -> s.Definition(String))
}

pub fn captured_definition() {
  let assert Ok(completed) = s.recursive("captured", fn(_) { Ok(s.text()) })
  Ok(s.map(completed, fn(_) { Captured(fn() { completed }) }))
}

pub fn captured_completed_definition_test() {
  let assert Ok(definition) = captured_definition()
  let assert Ok(input) = s.parse("\"value\"")
  let assert Ok(Captured(get)) = s.decode(definition, input)
  s.validate(get(), input) |> should.equal(Ok(Nil))
  s.schema_string(get(), s.Compact)
  |> should.equal(s.schema_string(definition, s.Compact))
  s.decode(get(), input) |> should.equal(Ok("value"))
}

pub type First {
  First(fn() -> s.Definition(Bool))
}

pub type Second {
  Second(fn() -> s.Definition(String))
}

pub fn captured_completed_pair_test() {
  let assert Ok(#(first, second)) =
    s.recursive_pair("first", "second", fn(_, _) {
      Ok(#(s.text(), s.boolean()))
    })
  let assert Ok(text) = s.parse("\"value\"")
  let assert Ok(boolean) = s.parse("true")
  let assert Ok(First(get_second)) =
    s.decode(s.map(first, fn(_) { First(fn() { second }) }), text)
  let assert Ok(Second(get_first)) =
    s.decode(s.map(second, fn(_) { Second(fn() { first }) }), boolean)
  s.validate(get_second(), boolean) |> should.equal(Ok(Nil))
  s.schema_string(get_second(), s.Compact)
  |> should.equal(s.schema_string(second, s.Compact))
  s.decode(get_second(), boolean) |> should.equal(Ok(True))
  s.decode(get_first(), text) |> should.equal(Ok("value"))
}
