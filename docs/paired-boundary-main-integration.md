# PairedBoundary main-module integration

Historical decision, superseded by the boundary module refactor. The current API
uses `gargamelle/boundary`, a direct `Encoder(a)`, three type parameters, and
`EncodingError` for saving.

The development branch adds the paired API to `gargamelle`. It is additive and
unreleased; no package version, publication archive, or tag was changed. The original
prototype remains under `verification/experiments` as a preserved comparison.

## Dependency decision

The prototype imports both `gargamelle` and `gargamelle/encoding`. Moving that code
verbatim into the main module would create a module cycle: encoding already imports
the main module for JSON, contracts, certificates, and errors. Gleam rejects cyclic
module imports. Avoiding that through a large shared-type/module rewrite would add
unrelated API changes to a small convenience feature.

The integrated constructor accepts `fn(a) -> Result(Json, encoding_error)` instead
of `encoding.Encoder(a)`. The concrete adapter is
`encoding.encode_json(encoder, _)`. This preserves admitted JSON and the concrete
encoding error without FFI casts, dependencies from core to encoding, or manual
release/ownership obligations. No existing encoding or boundary API was renamed.

Consequently, the integrated type has four parameters:
`PairedBoundary(a, loaded, saved, encoding_error)`, compared with the prototype's
three. Calls generally rely on inference. `save` returns
`SaveError(encoding_error)` with `EncodingFailed(error)` and
`ContractRejected(ContractError)`; `load` retains its ordinary `ContractError`.
This is a deliberate signature change from the private prototype, not a transparent
relocation. An app moving from the copied prototype must update its encoder argument
and saving error patterns.

## Guarantees and limits

Construction stores one full contract in decoded and JSON receiving boundaries.
It runs no callbacks. Encoding failures preserve their typed reason and prevent
checks and the saving handler. Each successful encoding submission runs the stored
contract check once; arbitrary work done inside an application encoder is separate.
Check-free saving never decodes; semantic requirements reconstruct once from JSON.
Handlers retain independent response types and nested Result behavior. Operational
exceptions propagate. Loading and saving are neither an inverse-law guarantee nor
a transaction. No extraction/replacement endpoints were added.

Tests cover both targets, process transfer, callback counts, typed encoding failure,
complete semantic authority, and check-free saving. Compile-negative checks reject
opaque construction, certificate input, checked encoders, and unadmitted raw output.
A targeted mutation drops egress semantic requirements; the compiled example must
detect it while retaining its valid load/save path. The existing native comparison
against the frozen implementation is retained. This commit is not full release
qualification or a claim that the real app has adopted the integrated API.

Generation and shrinking follow-up files remain private and uncommitted. They are
not dependencies of the paired API and are excluded from this integration commit.
