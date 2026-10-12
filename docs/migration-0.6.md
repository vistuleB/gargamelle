# Migrating to 0.6.0

0.6.0 adds `gargamelle/encoding`. Existing definitions, decoding, Contract and
receiving-boundary signatures are unchanged.

Encoders are explicit and independent of definitions. Record encoders require
getters; decoding constructors cannot automatically be reversed.

- `encode_json` produces admitted `Json` without checking a Contract.
- `codec` pairs an encoder with a Contract; `encode` checks the emitted JSON and
  returns `VerifiedJson` on success.
- `output_boundary` pairs an encoder with a `JsonBoundary`; `send` checks the
  receiver's Contract once before invoking its handler.

Semantic requirements inspect the decoded emitted representation. Encoding and
decoding need not be inverses. Encoding errors identify output JSON Pointer paths;
field-construction errors identify the supplied field name.

See [Typed JSON encoding](encoding.html) for complete examples and limits.
