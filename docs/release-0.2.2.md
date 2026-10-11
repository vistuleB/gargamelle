# 0.2.2 publication and replacement preparation

The maintainer published 0.2.2 on 2026-10-11 at 20:27:38 UTC from commit
`c489b771be4643f611f72a9cc6bbd8428084f9e8`. The published archive checksum is
`e665dc0066acc180e9a13982def70cb12ebb89f08fae4f34b7f899679c5575c5`.
Its members match the original prepared archive; the outer tar checksums differ.
Original evidence and both archives are retained in `reports/published-0.2.2`.

## Replacement scope

Shorten the README contract link and demonstrate typed record decoding. Replace
the flat renderer recipe with the nested record shown in its screenshot. Clarify
construction-plan lifetimes and safe-integer exclusion, remove implementation
commentary from public guides, and label the public tarball as Source archive.
There are no runtime or API changes.

## Required evidence and handoff

Follow `docs/releasing.md`: final-source local preparation, directly compiled
README and renderer examples on both targets, fresh archive consumers, rendered
page review, all three browser reports, and both Linux OTP jobs. Retain the final
commit, fingerprints, archive checksum and CI run in
`reports/release-handoff-0.2.2.json`.

Only the maintainer publishes. The replacement command is
`gleam publish --replace`; the original one-hour replacement window ends at
21:27:38 UTC (5:27:38 PM EDT) on 2026-10-11. Verify the actual archive and live
HexDocs after publication. Do not move existing tags or application dependencies.

Runtime support remains the documented Node/browser and macOS/Linux OTP matrix.
Other runtimes and deployment tools remain unqualified. Test evidence and
preservation arguments are not a formal proof.
