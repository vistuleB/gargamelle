# Verified JSON implementation decisions

This contributor note records decisions for review; the usage guide is
`docs/boundaries.md`. An encoder and output boundaries are deferred.

- Keep the types and functions in the main module, as discussed with the
  maintainer. The small API is `boundary`, `boundary_definition`, `forward`,
  `verified_json` and `verified_data`.
- Store original JSON and decoded data, rather than validation evidence or a
  thunk. `forward` calls the existing `decode` once. Repeated access cannot
  repeat conversion callbacks. This intentionally retains both representations;
  it makes no fixed memory-overhead claim.
- Do not export a standalone certificate constructor or verifier. A generic
  output type cannot encode the identity of a runtime definition. The opaque
  boundary binds the definition to the handler; submission always takes raw
  admitted JSON and checks the boundary's own definition.
- Expose the stored definition for host approval and schema emission, but not
  the handler. A component can still export other unchecked functions; this
  API protects the invocation route the host chooses, not the entire component.
- Preserve `decode` errors, callback ordering and operational failures. Do not
  catch exceptions or flatten application `Result` responses into data errors.
- Opaqueness is a Gleam API guarantee, not a security boundary against untyped
  code or FFI. Likewise, retained decoded closures remain trusted application
  code and may themselves have mutable captured state.
- Leave the published version and release handoff unchanged. Record this as
  unreleased work; do not treat old archive fingerprints as evidence for it.

## Verification

On 2026-10-11, the shared suite passed 52 Gleam tests. Six new tests cover
single conversion and handler invocation, repeat access without callbacks,
complete rejection diagnostics, differing contracts with the same output type,
original JSON versus defaulted/projected output, application errors, and recursive
boundary/certificate transfer after creator-process exit.

The Node suite passed its 146 existing checks. Three additional checks confirmed
converter and handler exception propagation and compiled/ran the guide's actual
example on JavaScript and Erlang. All 41 compile-negative programs were rejected
on both targets, including forged certificates/boundaries, handler type mismatch,
private handler access and forwarding a certificate instead of admitted JSON.

The production-plan gate passed 60 native tests (52 shared plus eight process/graph
tests), 32 existing negative checks and 3,636 cases across 36 schemas, including
historical JavaScript and native comparisons. `gleam docs build` passed. These are
development checks, not a new prepared release or broader platform qualification.
