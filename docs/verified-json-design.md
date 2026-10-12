# JSON boundary and certificate implementation decisions

This contributor note records decisions for review; the usage guide is
`docs/boundaries.md`. The encoder remains an isolated prototype.

- Keep the types and functions in the main module, as discussed with the
  maintainer. Boundaries use `boundary`, `boundary_definition` and `forward`.
  Certificates use `verify`, `verified_json` and `verified_definition`.
- A boundary invokes a private `fn(a, Json) -> response` after calling `decode`
  once against its stored definition. It passes decoded data and original JSON
  separately, without constructing a certificate. A handler that needs only the
  decoded value can ignore the JSON argument. Peak decoding memory still includes
  both representations; application code determines whether either is retained.
- `VerifiedJson(a)` stores JSON and the actual checked `Definition(a)`, without
  a decoded value. It certifies acceptance, not that conversion has executed.
  `verify` calls `validate`; conversion callbacks do not run. Later decoding is
  explicit and does not reuse validation evidence.
- Remove `verified_data`; do not provide compatibility for the earlier unreleased
  interface. A generic output type does not encode the identity of a runtime
  definition. A recipient's boundary always checks its own definition, even when
  passed JSON obtained from another certificate.
- A public verifier is now appropriate for retained/output certificates because
  handlers receive plain values rather than accepting standalone certificates.
  Expose the stored certificate definition so callers can inspect what was
  checked. No public unchecked certificate constructor is provided.
- Checked encoding uses `verify`, avoiding decoded-value allocation and conversion
  callbacks. Encoder and definition remain independent declarations in the
  prototype, so output is still checked after encoding. Single-pass construction
  and certification is a separate optimization/design question.
- Expose a boundary's definition for host approval and schema emission, but not
  its handler. A component can export other unchecked functions; this API protects
  the invocation route the host chooses, not the entire component.
- Preserve validation/decode errors, callback ordering and operational failures.
  Do not catch exceptions or flatten application `Result` responses into data
  errors. Responses from boundary handlers remain unchecked.
- Opaqueness is a Gleam API guarantee, not isolation against untyped code or FFI.
  A certificate retains the definition and any state captured by its callbacks;
  it makes no guarantee about the purity or success of later conversion.
- Leave the published version and release handoff unchanged. This is unreleased
  work; previous archive fingerprints do not qualify it.

## Verification scope

The boundary tests cover one conversion and handler invocation, complete rejection
diagnostics, differing contracts with the same output type, original JSON versus
defaulted/projected output, application errors, and recursive boundary transfer.
Certificate tests cover zero conversion callbacks, exact stored definitions,
validation-error preservation and use after creator-process exit. Compile-negative
checks reject forged certificates/boundaries, incorrect handler types, private
handler access, the removed accessor, and forwarding certificates instead of JSON.

The isolated encoder gate checks that checked output invokes no conversion
callbacks, with explicit decoding only in its round-trip tests. Documentation
examples are compiled and run on both targets. Production regression gates still
compare historical JavaScript behavior, native behavior and independent validators.

On 2026-10-11 the revised implementation passed `npm test` (54 shared Gleam tests
and 151 Node checks). All 44 compile-negative programs were rejected on both
targets. The prototype gate passed 12 encoder tests per target and six output
cases against Ajv and Hyperjump. The production-plan gate passed 62 native tests,
32 existing negative checks and 3,636 independent cases across 36 schemas.
`gleam docs build`, formatting checks and `git diff --check` passed.
