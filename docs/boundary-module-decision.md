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

This is a breaking module/API change for a future release. The development package
metadata remains at 0.8.0 until release preparation is requested; exported local
archives are verification artifacts, not replacements for the published release.
Generation and shrinking experiments remain outside shipped source and outside
this refactor commit.
