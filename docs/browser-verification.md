# Browser verification evidence

Recorded 2026-10-11 on macOS arm64. This is bounded verification evidence for
the JavaScript target, not a change to the published 0.2.0 support matrix.

| Browser | Installed version | Result |
| --- | --- | --- |
| Chrome | 155.0.8059.40 | Passed |
| Firefox | 157.0.1 | Passed |
| Safari | 27.0 | Passed |

Each browser executed 45 existing compiled Gleam tests, 886 generated definitions
with 17,788 input cases, and 594 regex probes. The generated cases compared schema
bytes, acceptance, 6,459 accepted decoded outputs and structured errors with a
Node 24.10.0 baseline. The baseline also checks independent recipe semantics,
Ajv and Hyperjump; the existing Ajv `__proto__` exception classification is retained.
Decoding must leave inputs and emitted schemas unchanged, and validation must
agree with decoding.

The 886 definitions use the existing JavaScript adapter over public library
constructors. They supplement the 45 typed Gleam tests rather than replacing them.
Generated outputs are compared after JSON normalization; this comparison alone
does not distinguish signed zero or prove arbitrary closure semantics.

Seventeen DOM checks cover escaped descriptions and examples, unique IDs, recursive
reference targets, folding controls, native disclosure toggling, hash navigation,
print-event expansion/restoration, suppression of example conversion callbacks,
and aligned record/alternative labels with children open and closed.
Safari's rendered page and actual print preview were also inspected: recursive
content expanded and fitted on one page. The preview was cancelled. The automated
print checks dispatch lifecycle events; they do not compare paginated output.

## Regex boundary and decisions for review

All 594 probes agree with each browser's own `RegExp` syntax and matching. Each
browser differs from the Node Unicode 16 reference in exactly two probes:
U+11DB0 matches `\p{L}` and `\p{Assigned}` in the browsers. This records host Unicode
table drift. It does not establish general equivalence between browser regex and
the native Unicode 16 helper.

The harness permits only those two specific false-to-true differences. Any other
browser/Node difference fails verification and requires investigation. No runtime
polyfill or library semantic change was introduced to force host regex parity.

The only compiled-test adaptation removes the Node-only gleeunit runner import
and unused `main` from a copied test module. Test bodies and production modules
are unchanged. The fixture server copies and hashes the compiled modules and
renderer assets, fingerprints source before and after baseline preparation, and
serves only copied fixture files on loopback. No bundler is involved.

## Reproduction and retained reports

With Gleam 1.18.1, Node 24.10.0 and installed dependencies:

```sh
npm run verify:browser
```

Open the printed loopback URL in each browser, adding `?browser=chrome`,
`?browser=firefox` or `?browser=safari`. Wait for the page's PASS status. Full
reports, baseline source fingerprint and copied-artifact hashes are written under
the ignored `reports/browser-verification/` directory. The server validates posted
results against its frozen baseline. Stop it after collecting results.

Browser execution is currently manual, not part of CI. Older versions, mobile
browsers, workers, Bun and Deno have not been covered. No browser performance
claim follows from these functional checks. Realistic large-contract measurements
remain the next verification task.

## Renderer alignment regression

The initial visual inspection missed a left-offset difference between native
disclosure markers and the fixed padding on plain rows. The user identified it
after the initial browser milestone. The new geometry assertion fails against
the original CSS in Safari. The CSS now reserves the same 18-pixel label offset
for both row types and draws its chevron inside that space. Native `details` and
`summary` continue to provide disclosure behavior and keyboard interaction.
The copyable HexDocs asset is updated together with the canonical stylesheet.
