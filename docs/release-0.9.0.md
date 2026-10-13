# 0.9.0 release preparation

The candidate incorporates the reviewed development work through 5caa714.
The public additions are PairedBoundary, the optional diagnostics module, and
provider loading/saving documentation. Receiving and typed output boundaries
move to gargamelle/boundary without forwarding aliases. Core and encoding retain
their separate responsibilities. Admission, structural schema semantics, parsers,
and native-helper deployment are unchanged.

The boundary guide serves as the migration guide from 0.8.0. Public examples use
explicit gargamelle_boundary and gargamelle_encoding aliases. Package metadata,
installation instructions, source archive URLs and current guide links target
0.9.0. The repository is public and linked in the generated documentation.

Private shared-record and generation experiments remain verification artifacts;
they are not installed public API. No proposal from the Elixir package reviews
is added to this release. Consumer dependency pins and application source are
unchanged by release preparation.

Run npm run prepare:release for the final versioned source. The ignored
reports/release-preparation.json records source and archive fingerprints, command
logs, both target gates, documentation/link checks and fresh extracted-archive
consumers, including diagnostics and paired loading/saving. Linux qualification
runs the same command on Ubuntu 24.04 with OTP 28 and 29; inspect its reports before
claiming the existing Linux matrix for this candidate.

Independent review of preservation arguments remains distinct from automated
evidence. Browser qualification is the existing recorded matrix, not a new manual
browser-engine conformance run. No new runtime or platform support is claimed.
Publication is performed by the maintainer with gleam publish from the main
checkout after qualification. Preparation does not publish or move release tags.
Final source commit, archive checksum and hosted run IDs are retained in reports.
