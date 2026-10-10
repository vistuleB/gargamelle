import gargamelle as s
import gleeunit/should

pub type Captured {
  Captured(fn() -> s.Definition(Captured))
}

pub fn captured_definition() {
  s.recursive("captured", fn(self) {
    Ok(s.map(s.text(), fn(_) { Captured(fn() { self }) }))
  })
}

pub fn captured_placeholder_test() {
  let assert Ok(definition) = captured_definition()
  let assert Ok(input) = s.parse("\"value\"")
  let assert Ok(Captured(get)) = s.decode(definition, input)
  let captured = get()
  s.validate(captured, input) |> should.equal(Ok(Nil))
  s.emit_text(captured) |> should.equal(s.emit_text(definition))
  let assert Ok(Captured(get_again)) = s.decode(captured, input)
  s.validate(get_again(), input) |> should.equal(Ok(Nil))
}

pub type First {
  First(fn() -> s.Definition(Second))
}

pub type Second {
  Second(fn() -> s.Definition(First))
}

pub fn captured_pair_test() {
  let assert Ok(#(first, second)) =
    s.recursive_pair("first", "second", fn(a, b) {
      Ok(#(
        s.map(s.text(), fn(_) { First(fn() { b }) }),
        s.map(s.boolean(), fn(_) { Second(fn() { a }) }),
      ))
    })
  let assert Ok(text) = s.parse("\"value\"")
  let assert Ok(boolean) = s.parse("true")
  let assert Ok(First(get_second)) = s.decode(first, text)
  let captured_second = get_second()
  s.validate(captured_second, boolean) |> should.equal(Ok(Nil))
  s.emit_text(captured_second) |> should.equal(s.emit_text(second))
  let assert Ok(Second(get_first)) = s.decode(captured_second, boolean)
  s.validate(get_first(), text) |> should.equal(Ok(Nil))
}
