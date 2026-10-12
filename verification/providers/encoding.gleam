// Explicit typed output for the real cloze provider's evidence type.
import gargamelle/encoding as e
import providers_cloze as cloze

fn entry_encoder() {
  let assert Ok(fields) =
    e.field(e.record(), "blankId", e.text(), fn(value: cloze.Entry) {
      value.blank_id
    })
  let assert Ok(fields) =
    e.field(fields, "response", e.text(), fn(value) { value.response })
  let assert Ok(fields) =
    e.field(fields, "accepted", e.array(e.text()), fn(value) { value.accepted })
  let assert Ok(fields) =
    e.field(fields, "correct", e.boolean(), fn(value) { value.correct })
  e.finish(fields)
}

pub fn cloze_encoder() -> e.Encoder(cloze.Evidence) {
  let assert Ok(data) =
    e.field(
      e.record(),
      "entries",
      e.array(entry_encoder()),
      fn(value: cloze.Evidence) { value.entries },
    )
  let assert Ok(data) =
    e.field(data, "correct", e.safe_integer(), fn(value) { value.correct })
  let assert Ok(data) =
    e.field(data, "total", e.safe_integer(), fn(value) { value.total })
  let assert Ok(fields) =
    e.field(e.record(), "type", e.text(), fn(_: cloze.Evidence) { "cloze" })
  let assert Ok(fields) =
    e.field(fields, "version", e.safe_integer(), fn(_) { 1 })
  let assert Ok(fields) =
    e.field(fields, "data", e.finish(data), fn(value) { value })
  e.finish(fields)
}
