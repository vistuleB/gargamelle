import gargamelle as s
import gleam/option.{None, Some}
import gleeunit/should

pub fn typed_membership_test() {
  let base = s.map(s.array(s.number()), fn(xs) { #(xs, "unchanged") })
  let assert Ok(def) = s.contains(base, s.safe_integer(), 1, Some(2))
  let assert Ok(value) = s.parse("[0.5,1,2.5]")
  s.decode(def, value) |> should.equal(Ok(#([0.5, 1.0, 2.5], "unchanged")))
  let assert Ok(value) = s.parse("[0.5]")
  let assert Error([error]) = s.decode(def, value)
  error.category |> should.equal("contains_count")
  error.path |> should.equal("")
  s.contains(s.text(), s.text(), 0, None) |> should.be_error
}
