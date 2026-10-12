# Encoder integration decisions for review

## Scope and release isolation

The maintainer authorized 0.6.0 encoder work after the 0.5.0 candidate was prepared.
Work is isolated on `codex/encoder-060`; the main checkout remains at the reviewed
0.5.0 source and retains its prepared archive. No package publication is authorized
for the agent. Decoding-only definitions retain their existing API and behavior.

## Decisions

- The public module is `gargamelle/encoding`. Encoders are explicit independent
  plans. Record fields supply getters; no reflection or decoder reversal is used.
- `Codec(a)` stores an Encoder and full Contract, rather than only a Definition.
  Checked encoding verifies the emitted representation against that Contract.
  Equal type parameters do not establish matching constraints or inverse behavior.
- A typed `OutputBoundary` pairs an Encoder with an existing JsonBoundary.
  The receiving Contract is authoritative. `send` performs unchecked encoding,
  then forwards once; using checked encode first would repeat verification.
- Semantic requirements inspect decoded emitted JSON. That value may differ
  from the encoder input after mapping, defaulting or projection. Checking the
  original encoder input instead would not establish the receiving Contract.
- Encoding first produces gleam/json.Json, serializes, and calls admission once.
  This retains the proven admission path and avoids exposing opaque JSON internals.
  Temporary text and a second representation are explicit costs. Direct admitted
  JSON construction and integrated certification require separate optimization
  work; correctness does not depend on them.
- Primitive and field failures stop encoding at the first rejection; callback
  exceptions are operational failures. Structural receiving errors keep JSON
  Pointer attribution; primitive/admission encoding errors lack a field path.
- Self-recursion uses a builder executed once and a completed immutable body.
  No registry, mutable cells, casts or release obligation is added. Lift adapts
  completed encoders to construction environments. Mutual pairs are deferred.
- Encoder recursion is not structurally guarded. Immediate recursion can diverge,
  like a nonterminating getter. Trusted functions must be total and input values
  must be finite. No resource bound or hostile-FFI sandbox is claimed.

## Remaining integration work

Measure serialization/admission overhead on representative provider payloads;
review direct JSON constructors, encoding diagnostics and record ergonomics.
Exercise the public module against independent schema validators, compile-negative
programs, native transfer and fresh package consumers. The initial integration
is not a 0.6.0 release handoff.

## Cost checkpoint

`node verification/encoding-costs.mjs` records bounded Node 24.10.0 measurements
for arrays of 10 and 1,000 strings (approximately 161 bytes and 18 KB). The first
run measured plain encoding at approximately 4 and 248 microseconds, respectively;
semantic checked encoding and send were approximately 12 and 580–590 microseconds.
These are observations on one machine, not thresholds or native performance claims.
The reference stringify/admit path is a cost comparison, not a substitute typed
encoder. Direct construction remains a useful optimization candidate; the measured
cost does not justify weakening admission or repeating receiving verification.
