# Boundary module decision

The boundary APIs move to `gargamelle/boundary`. Core owns JSON, definitions,
contracts, decoding, validation, verification, and schema generation. Encoding
owns encoders and codecs. Boundary imports both; core and encoding do not import
boundary. This avoids a module cycle without splitting core types or introducing
an application-defined encoding adapter into the paired API.

The public module paths remain namespaced Gleam paths. Examples use
`gargamelle_encoding` and `gargamelle_boundary` aliases to identify the package at
call sites. No forwarding aliases remain in the previous modules.

PairedBoundary accepts a completed Encoder directly, retains three type parameters,
and uses EncodingError for saving. Both directions retain the same full Contract.
The paired implementation delegates to decoded receiving and typed output paths;
it adds no alternative validation authority. This supersedes the four-parameter
main-module experiment recorded in paired-boundary-main-integration.md.

The module move is the breaking API change in the 0.9.0 candidate. The shared
record and generation/shrinking experiments remain outside shipped source.
Release qualification and archive hashes are recorded separately in
release-0.9.0.md and ignored reports.
