import gargamelle as s
import gleam/option.{None, Some}
import gleeunit/should

pub fn float_output_test() {
  let def: s.Definition(Float) = s.number()
  let assert Ok(value) = s.parse("1.25")
  let assert Ok(decoded) = s.decode(def, value)
  decoded +. 0.5 |> should.equal(1.75)
}

pub fn typed_coordinate_record_test() {
  let assert Ok(r) =
    s.record(fn(x: Float) { fn(y: Float) { #(x, y) } })
    |> s.required("x", s.number())
  let assert Ok(r) = s.required(r, "y", s.number())
  let assert Ok(value) = s.parse("{\"x\":1.25,\"y\":-0.5}")
  s.decode(s.finish(r, s.Closed), value) |> should.equal(Ok(#(1.25, -0.5)))
}

pub fn typed_number_bounds_test() {
  let assert Ok(def) =
    s.number_bounds(s.number(), Some(s.Exclusive(0.0)), Some(s.Inclusive(1.0)))
  let assert Ok(value) = s.parse("0.5")
  s.decode(def, value) |> should.equal(Ok(0.5))
  let assert Ok(value) = s.parse("0")
  s.decode(def, value) |> should.be_error
}

pub fn signed_zero_bounds_test() {
  let assert Ok(value) = s.parse("-0")
  let assert Ok(negative_zero) = s.decode(s.number(), value)
  let assert Ok(exact_zero) =
    s.number_bounds(
      s.number(),
      Some(s.Inclusive(negative_zero)),
      Some(s.Inclusive(0.0)),
    )
  s.validate(exact_zero, value) |> should.equal(Ok(Nil))
  let assert Ok(exclusive) =
    s.number_bounds(s.number(), Some(s.Exclusive(negative_zero)), None)
  let assert Ok(repeated) =
    s.number_bounds(exclusive, Some(s.Inclusive(0.0)), None)
  s.validate(repeated, value) |> should.be_error
}
