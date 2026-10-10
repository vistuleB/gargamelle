import gargamelle as s
import gleam/option.{None, Some}
import gleeunit/should

pub type Entry {
  Entry(Float)
}

pub fn conditional_output_and_paths_test() {
  let base = s.map(s.number(), Entry)
  let assert Ok(positive) =
    s.number_bounds(s.number(), Some(s.Exclusive(0.0)), None)
  let assert Ok(negative) =
    s.number_bounds(s.number(), None, Some(s.Inclusive(-1.0)))
  let def = s.if_then_else(base, positive, s.safe_integer(), negative)
  let assert Ok(value) = s.parse("1")
  s.decode(def, value) |> should.equal(Ok(Entry(1.0)))
  let assert Ok(value) = s.parse("1.5")
  s.decode(def, value) |> should.be_error
  let assert Ok(value) = s.parse("-1.5")
  s.decode(def, value) |> should.equal(Ok(Entry(-1.5)))
  let assert Ok(value) = s.parse("0")
  let assert Error([error]) = s.decode(def, value)
  error.path |> should.equal("")
}
