# Generated native verification

The retained gate constructs 886 definitions through public, typed Gleam APIs
and checks 17,788 inputs on both JavaScript and Erlang. It reuses the JavaScript
generated corpus: ten seeds, depths zero through six, 345 supported parent/child
combinations, 23 nested constructors and fourteen depth-50 fixtures. The corpus
digest is also recorded by the existing JavaScript test during execution.

For each native definition, Ajv and Hyperjump independently validate its emitted
schema. A separate recipe interpreter checks acceptance and the 6,459 accepted
decoded outputs. Native and typed JavaScript runs must agree on emitted schema
text, JSON-normalized outputs and complete error structures. This comparison
checks diagnostics across targets; the independent validators do not derive the
library's diagnostic messages.

The corpus includes 151 known Ajv disagreements involving `__proto__`. The existing
classifier requires the disagreement to disappear after a semantics-preserving
key rename. Unclassified disagreements fail the gate. No general oracle exception
is added for Erlang.

JSON normalization does not establish signed-zero or host integer/float
representation equivalence. The separate numeric portability gates cover those
properties. Nested coverage records interpreter visits, rather than instrumenting
native constructor execution. The generated corpus is bounded evidence; it does
not replace exhaustive
parser or regex conformance, or checks on other platforms and OTP versions. The separate official gate now
runs all 109 selected cases unchanged; unsupported groups remain excluded.

## Reproduction and failure evidence

```sh
npm run verify:erlang-primitives
```

`generated-oracle.test.mjs` builds fresh temporary consumers for both targets,
compiles the native helper and retains `reports/native-generated-evidence.json`.
The report includes the source fingerprint, corpus digest, coverage, versions and
platform. Failures retain the corpus, generated Gleam source and a checkpoint;
the native probe writes the current fixture and input index before execution.
Reports are ignored artifacts and can be regenerated from the committed source.

`generated-native-mutations.test.mjs` changes only a temporary native adapter to
always accept regex matches. The independent checks detect this through string
patterns, exclusions, conditionals, array containment and property names. This is
one adapter mutation, not complete native operator mutation coverage.

`deployment.test.mjs` exports a Gleam Erlang shipment and removes all source and
build checkouts. It first verifies an operational failure without the helper,
then installs the helper and exercises recursive decoding, Unicode patterns,
duplicate named groups, schema emission and rendering. This deployment evidence
is limited to macOS arm64, OTP 29 and Gleam 1.18.1. Linux, Windows, minimum OTP
versions and other deployment tooling remain unverified.

These additions change verification code and documentation. Production shared
Gleam, JavaScript and Erlang sources are unchanged from commit `87c8c03`.

`official-conformance.test.mjs` verifies the pinned suite hashes and complete
selection inventory, compiles typed definitions and runs all 27 selected groups
on both targets. Original and emitted schemas are checked by Ajv and Hyperjump
against the fixtures' unchanged validity expectations. All 109 cases pass: 38
accepted and 71 rejected. The report is `reports/native-official-evidence.json`.
This adds no arbitrary-schema importer or claim of full-dialect support.
