# 0.5.0 release preparation

0.5.0 adds semantic contracts above structural definitions. Requirements inspect
decoded values, can only reject, and run once in declaration order. Structured
errors distinguish structural rejection from collected semantic failures.
Receiving boundaries and `verify` now require `Contract(a)`. Structural
definitions and schema equivalence are unchanged. JSON-only verification decodes only when semantic requirements exist;
certificates retain the full accepting contract and original admitted JSON.

HTML contract rendering lists all requirement descriptions without callbacks.
Generated JSON Schema contains structural assertions only. Descriptions are not
proof that their callbacks implement the described rules. Review assumptions and
decisions in `contract-design.md` and the preservation argument.

The isolated provider integration compiles all five production provider sources,
checks both receiver types, compares structural acceptance with two independent
schema validators, and separates historical cloze/diagram predicates from current
context. Session signatures and associations, verbatim versions 1–3 and foreign
certificates are covered. Results and source hashes are recorded in
`reports/provider-contract-integration.json`. The application dependency and
source remain unchanged; its maintainer owns production adoption.

The candidate is a new release. Hex metadata checked on 2026-10-12 lists 0.4.0 as
the latest published version and does not list 0.5.0. Only the maintainer publishes.
Typed encoder integration is deferred to 0.6.0; the existing prototype remains
unshipped. No accept-anything definition, JSON constructors or broad naming
changes are included in this release.

Local preparation checks both targets and fresh exported-package consumers,
including Contract rejection, certificate authority and requirement rendering.
Linux qualification must pass on the final source commit before the declared
Linux matrix is qualified for this candidate. Browser editorial review covers
README paragraph structure, the API overview, Contract guide and migration page.
Exact fingerprints, archive checksums, CI run IDs and review observations belong
in `reports/release-handoff-0.5.0.json`; the preparation result belongs in
`reports/release-preparation.json`. Follow `releasing.md`. Publication is separate.
