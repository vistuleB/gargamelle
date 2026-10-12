import gargamelle as s
import gleeunit/should

pub fn uuid_assertion_preserves_string_output_test() {
  let definition = s.assert_format(s.text(), s.Uuid)
  let assert Ok(json) = s.parse("\"f81d4fae-7dec-11d0-a765-00a0c91e6bf6\"")
  s.decode(definition, json)
  |> should.equal(Ok("f81d4fae-7dec-11d0-a765-00a0c91e6bf6"))
  let assert Ok(upper) = s.parse("\"F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6\"")
  s.decode(definition, upper)
  |> should.equal(Ok("F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6"))
  let assert Ok(nil) = s.parse("\"00000000-0000-0000-0000-000000000000\"")
  s.validate(definition, nil) |> should.be_ok
}

pub fn uuid_assertion_rejects_trailing_line_breaks_and_urn_test() {
  let definition = s.assert_format(s.text(), s.Uuid)
  let assert Ok(newline) =
    s.parse("\"f81d4fae-7dec-11d0-a765-00a0c91e6bf6\\n\"")
  s.validate(definition, newline) |> should.be_error
  let assert Ok(urn) =
    s.parse("\"urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6\"")
  s.validate(definition, urn) |> should.be_error
  let assert Ok(missing) = s.parse("\"f81d4fae7dec11d0a76500a0c91e6bf6\"")
  s.validate(definition, missing) |> should.be_error
}

pub fn format_assertion_applies_only_to_strings_and_preserves_maps_test() {
  let definition = s.assert_format(s.boolean(), s.Uuid)
  let assert Ok(boolean) = s.parse("true")
  s.decode(definition, boolean) |> should.equal(Ok(True))
  let mapped =
    s.assert_format(s.map(s.text(), fn(text) { #(text, True) }), s.Uuid)
  let assert Ok(json) = s.parse("\"00000000-0000-0000-0000-000000000000\"")
  s.decode(mapped, json)
  |> should.equal(Ok(#("00000000-0000-0000-0000-000000000000", True)))
}
