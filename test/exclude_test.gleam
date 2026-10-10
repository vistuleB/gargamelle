import gargamelle as s
import gleeunit/should

pub type Amount {
  Amount(Float)
}

pub fn typed_exclusion_test() {
  let assert Ok(zero) = s.integer_constant(0)
  let def = s.exclude(s.map(s.number(), Amount), zero)
  let assert Ok(value) = s.parse("1.5")
  s.decode(def, value) |> should.equal(Ok(Amount(1.5)))
  let assert Ok(value) = s.parse("-0")
  let assert Error([error]) = s.decode(def, value)
  error.category |> should.equal("excluded")
  error.path |> should.equal("")
}
