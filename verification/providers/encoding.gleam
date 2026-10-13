// Explicit typed output for the real cloze provider's evidence type.
import gargamelle/encoding as gargamelle_encoding
import providers_cloze as cloze

fn entry_encoder() {
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "blankId",
      gargamelle_encoding.text(),
      fn(value: cloze.Entry) { value.blank_id },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "response",
      gargamelle_encoding.text(),
      fn(value) { value.response },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "accepted",
      gargamelle_encoding.array(gargamelle_encoding.text()),
      fn(value) { value.accepted },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "correct",
      gargamelle_encoding.boolean(),
      fn(value) { value.correct },
    )
  gargamelle_encoding.finish(fields)
}

pub fn cloze_encoder() -> gargamelle_encoding.Encoder(cloze.Evidence) {
  let assert Ok(data) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "entries",
      gargamelle_encoding.array(entry_encoder()),
      fn(value: cloze.Evidence) { value.entries },
    )
  let assert Ok(data) =
    gargamelle_encoding.field(
      data,
      "correct",
      gargamelle_encoding.safe_integer(),
      fn(value) { value.correct },
    )
  let assert Ok(data) =
    gargamelle_encoding.field(
      data,
      "total",
      gargamelle_encoding.safe_integer(),
      fn(value) { value.total },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      gargamelle_encoding.record(),
      "type",
      gargamelle_encoding.text(),
      fn(_: cloze.Evidence) { "cloze" },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "version",
      gargamelle_encoding.safe_integer(),
      fn(_) { 1 },
    )
  let assert Ok(fields) =
    gargamelle_encoding.field(
      fields,
      "data",
      gargamelle_encoding.finish(data),
      fn(value) { value },
    )
  gargamelle_encoding.finish(fields)
}
