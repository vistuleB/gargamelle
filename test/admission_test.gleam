import gargamelle as s
import gleam/list
import gleam/string
import gleeunit/should

pub fn scalar_domain_test() {
  list.each(
    [
      "\"\\ud800\"",
      "[\"\\udfff\"]",
      "{\"\\ud800\":1}",
      "{\"x\":1,\"x\":\"\\ud800\"}",
    ],
    fn(source) {
      let assert Error(s.AdmissionError(message)) = s.parse(source)
      message |> should.equal("non-scalar string")
    },
  )
  let assert Ok(paired) = s.parse("\"\\ud83d\\udc9c\"")
  s.decode(s.text(), paired) |> should.equal(Ok("💜"))
  let assert Ok(discarded) = s.parse("{\"x\":\"\\ud800\",\"x\":1}")
  s.to_string(discarded, s.Compact) |> should.equal("{\"x\":1}")
  let assert Error(s.AdmissionError(message)) = s.parse("[\"\\ud800\",]")
  string.starts_with(message, "syntax") |> should.be_true
}
