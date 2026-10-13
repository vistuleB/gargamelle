# Roundtrip and diagnostic decisions

This development branch leaves the 0.8.0 publication checkout unchanged. The
example and formatting module are unreleased additions, not a qualified release.

- No paired-boundary constructor yet. The example uses `boundary_contract(loader)`
  to construct the saving receiver, sharing one authority without redeclaring a
  contract. This establishes the workflow but does not evaluate boilerplate across
  multiple real providers. A convenience constructor remains conditional on that
  evidence. No app contracts, handlers, or persistence behavior were changed.
- The load/save example is deliberately not an inverse-codec guarantee. Output
  semantic checks inspect reconstruction from encoded JSON. A mapping regression
  demonstrates that resubmitting the decoded value can fail even when ingress
  succeeded. No new declaration-order semantics were introduced.
- Diagnostics live in an optional module and have two functions. Summary limits
  are conservative fixed ceilings: 100 details, eight branch levels, 160 graphemes
  per line. These are presentation policy, not validation limits. Reconsider the
  ceilings only against actual diagnostic consumers.
- JSON reports preserve all existing structural and semantic fields. They do not
  invent schema positions, reference traces, expected bounds, or input excerpts.
  JSON serialization still reparses for admission and can fail for non-scalar
  strings in application-authored diagnostics. This is not an optimization.
- Formatting includes application-authored messages, descriptions, and paths.
  Automatically excluding submitted values does not make reports safe for public
  exposure. No redaction framework or localization API was added.
- Error categories retain the existing pre-1.0 stability policy. Summary wording
  is presentation, not a machine protocol. Seeds, shrinking, domain codecs, and
  compilation optimizations remain deferred.
