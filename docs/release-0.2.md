# 0.2.0 candidate review

This candidate contains the completed native implementation and two deliberate
breaking changes. It is not yet published. JavaScript is verified on Node 24;
native evidence covers macOS arm64, OTP 29 and Gleam 1.18.1. Broad Erlang support
still requires platform qualification. No 0.1.0 tag or application dependency pin
is changed by this preparation.

## Audit findings

| Area | Review result |
| --- | --- |
| String domain | Both parsers admit scalar strings and keys after syntax and duplicate-key resolution. Lone surrogates are rejected; valid pairs survive. This changes JavaScript admission from 0.1.0 and is documented in the migration guide. |
| Recursion contract | Open construction plans cannot be decoded or emitted. Completed definitions retain immutable bodies and work across process transfer and creator exit. No permanent registry, release obligation or generic FFI cast is introduced. |
| Typed conversion | Conversion uses private validation evidence after structural acceptance. Auxiliary constraints do not run conversion callbacks. Existing independent mapped-output and compile-negative gates remain in place. |
| JavaScript preservation | The new native regex transport changes only Erlang modules. Generated schemas, acceptance, outputs and full diagnostics are compared across targets; intentional scalar and builder API changes are identified separately. |
| Native failures | Missing helpers, port failures and execution limits remain operational exceptions, including under defaults and auxiliary checks. Temporary workers close before converters; owner exit, nesting and exception cleanup have regressions. |
| Regex ownership and licensing | Vendored engine files have retained source hashes, patch descriptions and upstream MIT license. No interpreter or JavaScript runtime is required by the native backend. A generated host executable is not shipped in the Hex source archive. |
| Deployment | A Gleam shipment passes on macOS after all source checkouts are removed and the helper is explicitly installed. Missing-helper failure is tested. This is not evidence for every release tool or operating system. |
| Documentation | The changelog and migration guide describe both breaking changes. Obsolete temporary-regex-adapter statements are removed. Versioned links target 0.2.0 and remain pending until publication. |

The preservation arguments support the design but are not a formal proof. V08
remains marked for independent review by the evidence checker. This audit does
not silently convert that status to an automated pass.

## Decisions to review before publication

The package keeps exact Gleam dependency pins and requires Gleam 1.18.1 or later.
Only that compiler version is currently in the recorded candidate evidence;
compatibility with other compiler and dependency versions is not established.

The native helper build and installation are explicit. This avoids distributing
an executable for the maintainer's machine, but deployment tooling must copy a
binary built for its own destination. The helper uses POSIX APIs; Windows support
is not claimed. Native regex Unicode tables are pinned to Unicode 16, matching
the tested Node 24 reference; other JavaScript hosts require separate checks.

Native regex checks impose packet, stack, execution and timeout limits. Those
limits are operational boundaries, not extra schema rejection rules. The observed
synthetic speedup is not a throughput guarantee for applications. No compiled
regex cache or persistent service is introduced for this release.

The current recommendation is to finish Linux and OTP-range qualification before
claiming broad Erlang support. A release limited to JavaScript with a native
preview would be a separate support-scope decision; this preparation does not
make that decision implicitly. Additional vocabulary features should stay out
of 0.2.0.

## Preparation evidence and outstanding work

`npm run prepare:release` regenerates the JavaScript and native gates, checks
documentation and the exported archive, verifies vendor hashes and exercises
fresh archive consumers on both targets. The report in
`reports/release-preparation.json` records the source and archive hashes and logs.
It is a local preparation report, not publication approval.

The retained native corpus checks 886 definitions and 17,788 input cases with
Ajv and Hyperjump; 6,459 accepted outputs are checked by an independent recipe
interpreter. Sixteen portability groups include 53 native behavioral tests,
twelve cross-target compile-negative checks, an adapter mutation detected through
five API paths and the deployment check. Existing JavaScript evidence covers
45 Gleam tests, 144 Node tests and 109 selected official-suite cases.

Outstanding qualification: Linux, the supported OTP version range, and deployment
formats beyond the tested Gleam shipment. All 109 selected official cases now pass on both targets against their unchanged
expected results; 357 unsupported groups remain explicitly excluded. Broader native
operator mutation coverage would strengthen evidence. Linux CI has been prepared
for OTP 28 and 29, but no hosted pass is recorded yet. Publishing
account access, repository visibility and external release availability must be
checked when publication is requested. No tag, push or publication is included.
