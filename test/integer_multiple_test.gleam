import gargamelle as s
import gleam/option.{Some}
import gleeunit/should

pub fn integer_divisibility_and_invalid_divisors_test() {
  let assert Ok(definition) = s.integer_multiple_of(s.safe_integer(), 3)
  let assert Ok(valid) = s.parse("-6")
  s.decode(definition, valid) |> should.equal(Ok(-6))
  let assert Ok(invalid) = s.parse("7")
  s.decode(definition, invalid) |> should.be_error
  let assert Ok(fraction) = s.parse("1.5")
  s.validate(definition, fraction) |> should.be_error
  s.integer_multiple_of(s.safe_integer(), 0) |> should.be_error
  s.integer_multiple_of(s.safe_integer(), -1) |> should.be_error
  s.integer_multiple_of(s.safe_integer(), 9_007_199_254_740_991 + 1)
  |> should.be_error
  s.integer_multiple_of(s.number(), 3) |> should.be_error
}

pub fn repeated_divisors_intersect_and_preserve_bounds_test() {
  let assert Ok(definition) = s.integer_multiple_of(s.safe_integer(), 2)
  let assert Ok(definition) =
    s.integer_multiple_of(s.title(definition, "count"), 3)
  let assert Ok(definition) = s.integer_multiple_of(definition, 2)
  let assert Ok(definition) = s.bounds(definition, Some(0), Some(12))
  let assert Ok(expected) =
    s.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"integer\",\"minimum\":0,\"maximum\":12,\"multipleOf\":2,\"allOf\":[{\"multipleOf\":3}],\"title\":\"count\"}",
    )
  s.schema_string(definition, s.Compact)
  |> should.equal(s.to_string(expected, s.Compact))
  let assert Ok(valid) = s.parse("12")
  s.decode(definition, valid) |> should.equal(Ok(12))
  let assert Ok(invalid) = s.parse("10")
  s.validate(definition, invalid) |> should.be_error
}

pub fn large_safe_integer_remainder_test() {
  let assert Ok(definition) =
    s.integer_multiple_of(s.safe_integer(), 9_007_199_254_740_991)
  let assert Ok(valid) = s.parse("9007199254740991")
  s.decode(definition, valid) |> should.equal(Ok(9_007_199_254_740_991))
  let assert Ok(invalid) = s.parse("9007199254740990")
  s.validate(definition, invalid) |> should.be_error
  let assert Ok(zero) = s.parse("0")
  s.decode(definition, zero) |> should.equal(Ok(0))
}
