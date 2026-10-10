# Erlang string and regex investigation

Recorded 2026-10-10 after graph integration commit `08fd1b2`. This is development
research, not an Erlang support claim or a change to the published contract.

## String boundary and proposed 0.2.0 decision

The 0.1.0 contract admits lone UTF-16 surrogates and promises exact decoded
`String` values. Gleam's Erlang String is a UTF-8 binary. The retained
`verification/portability/string-representation.escript` exercises the same OTP
functions used by the pinned Gleam string and JSON externals. A valid astral
scalar works. Encoding a surrogate as WTF-8 or raw UTF-16 makes string length,
lowercase and JSON encoding raise operational errors. Returning the literal
six-character sequence `\ud800` produces valid UTF-8 but changes the value.
Replacing it with U+FFFD also changes the value. Neither is a compatible String
implementation. See the [Gleam externals guide](https://gleam.run/documentation/externals/).

Authorized decision for 0.2.0: admit JSON whose final string values and object
keys contain only Unicode scalar values, on both targets. Keep all valid surrogate
pairs, with no normalization or replacement. Unpaired surrogates produce a domain
admission error after JSON syntax and duplicate-key resolution, just as nonfinite
numbers do. Keep decoded `String` output and the current constructor API.
Document the domain change explicitly; leave 0.1.0 and its tag unchanged.

The alternative is preserving the full JavaScript domain through a new opaque
UTF-16 text API, including dictionary keys and affected record/string outputs.
That would require an API redesign and explicit conversion into ordinary Gleam
String. An internal parser adapter cannot supply that public representation.
The user authorized the scalar domain on 2026-10-10. It is now implemented in
JavaScript admission and the native Erlang parser. Metadata marks the working
tree as 0.2.0 in development; no 0.2.0 publication or tag has been created.

## Standalone regex experiment

QuickJS's [standalone libregexp](https://bellard.org/quickjs/) does not require
the JavaScript interpreter. The retained C probe calls that library directly and
exchanges length-prefixed packets through an Erlang port. Pattern bytes are UTF-8;
input is explicit UTF-16, preserving both pairs and lone surrogates in this
experiment. Syntax failure, match/no-match and operational failure are separate.
A deliberately exhausted execution budget returns operational failure, and the
same port handles its next request successfully.

The corpus has 13,572 pattern/input pairs: syntax restrictions, anchoring,
whitespace, astral and surrogate matching, backreferences, named groups and
duplicate names, lookaround, quantifiers, scoped flags, generated compositions,
and Unicode properties with Unicode 16/17 boundary characters. Node v24.10.0
with Unicode 16.0 is the reference.

- QuickJS 2025-09-13 rejects duplicate named groups allowed by Node.
- QuickJS 2026-06-04 supports that syntax but its Unicode 17 tables differ from
  Node's Unicode 16 property matches.
- QuickJS 2026-06-04 with `libunicode-table.h` and `unicode_gen_def.h` from
  2025-09-13 had zero differences in this corpus. No engine code was patched.

This is bounded empirical evidence, not complete ECMAScript conformance. The
table overlay is experimental and needs broader property/Test262 coverage before
production adoption. The 2026 `libunicode.h` version macro still says 17 in the
temporary copy; production packaging must correct metadata to the actual tables.
The 2026 executor requires `lre_get_alloc_count`, including internal registers,
rather than allocating only visible capture slots as in the 2025 API.

No native dependency or production binding has been added. A separate rebar3
dependency is a possible way to compile/distribute a native helper; Gleam supports
[rebar3 dependency packages](https://gleam.run/documentation/gleam-toml-reference/).
Clean-consumer builds, executable lookup, platform support, request lifecycle,
resource failure handling and caching still need implementation and verification.

## Reproduction

Download and extract the official source archives outside the repository:

| Archive | SHA-256 |
|---|---|
| [2025-09-13](https://bellard.org/quickjs/quickjs-2025-09-13.tar.xz) | `6f1f322aea3bb3a90858db85c9fe717013fde4df7dfcafe2f57e78f5bb4b4a0c` |
| [2026-06-04](https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz) | `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a` |

With Node 24, OTP 29 and a C compiler installed, run:

```sh
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2025-09-13
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2026-06-04
node verification/portability/quickjs-probe.mjs /path/to/quickjs-2026-06-04 /path/to/quickjs-2025-09-13
escript verification/portability/string-representation.escript
```

Set `PROBE_SANITIZERS=1` for an additional AddressSanitizer/UndefinedBehaviorSanitizer
run of the native engine and transport probe. This requires compiler sanitizer
support and writes a separate report.

The first two commands deliberately fail the parity gate when differences remain.
Reports under `reports/` record source hashes and every counterexample; they are
ignored build evidence. The overlay command copies into a temporary directory,
changes only the two table files, and removes that copy after testing. It does
not alter the downloaded archives or introduce a JavaScript subprocess on Erlang.
