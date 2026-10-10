# Native regex workload measurements

Recorded 2026-10-10 on macOS arm64, OTP 29, Gleam 1.18.1 and Node 24.10.0.
These are bounded synthetic measurements, not application benchmarks or timing
guarantees. Each operation has one warmup and three measured samples; the table
shows medians. Input parsing, definition construction and process startup for the
Gleam program are outside decode/validate timings. Timing runs were sequential,
without the verification suite running concurrently.

## Workload and results

The input contains provider-shaped records with identifier, URL, timestamp and
Unicode title fields. Patterned definitions apply four regexes per record. Plain
definitions have the same record shape and decoded output, with string checks.
The invalid case changes the final record's identifier and requires exactly one
diagnostic. Successful decoding verifies the output list length. Construction of
the four-pattern definition is measured separately.

| Workload | Previous Erlang decode | Scoped Erlang decode | Scoped Erlang validate | JavaScript decode |
|---|---:|---:|---:|---:|
| 1 patterned record | 14.82 ms | 3.98 ms | 3.62 ms | 0.045 ms |
| 16 patterned records | 233.50 ms | 4.98 ms | 5.69 ms | 0.186 ms |
| 64 patterned records | 886.78 ms | 10.49 ms | 11.23 ms | 0.473 ms |
| 64 records, invalid final identifier | 934.61 ms | 10.42 ms | 11.56 ms | 0.308 ms |
| 64 plain records | 0.338 ms | 0.307 ms | 0.291 ms | 0.546 ms |

The previous binding started one native executable per regex call. The current
binding lazily starts one helper per native validation walk, reuses it for that
walk and closes it before typed conversion callbacks execute. On this workload,
the 64-record decode became about 85 times faster. It remains about 22 times slower
than JavaScript's built-in regex path. The plain control shows that helper startup
and transport, rather than the shared record decoder, caused the observed cost.
These ratios apply only to these samples.

Four-pattern construction remains about 16 ms because standalone constructor
checks retain a private helper per call. That cost is not multiplied by the input
record count. No compiled-pattern cache was added; the helper compiles and frees
each expression per request.

## Ownership and JavaScript preservation

Only `src/gargamelle_regex.erl` and the Erlang `with_walk` adapter changed.
`src/gargamelle.gleam`, `src/runtime.mjs`, public types and callback rules are
unchanged from `af9acc5`. Native transport state is temporary process-local state;
definitions and decoded closures do not retain workers or ports. Nested walks
have independent scopes and restore the previous session. An operation with no
regex calls starts no helper.

Retained tests exercise both standalone and scoped transport on the same 594
cases; successful and exceptional cleanup; nested scope restoration; recovery
after native resource failure; owner exit while idle and while awaiting a reply;
and port closure before conversion, including a callback that reenters decoding.
Caller dictionaries, flags and mailboxes are restored. Operational failures still
escape auxiliary constraints and defaults. Existing historical JavaScript and
cross-target schema/output/diagnostic comparisons remain required.

The implementation keeps native crash isolation without a permanent service or
manual release obligation. This reuse decision should be reviewed independently
of regex conformance. In particular, process-local state must remain confined to
temporary transport, never become reference ownership or leak into returned
definitions.

## Reproduction and remaining work

Run the two measurements sequentially:

```sh
node verification/portability/regex-workloads.mjs per-call
node verification/portability/regex-workloads.mjs scoped
npm run verify:erlang-primitives
```

The `per-call` run substitutes the retained, hash-checked `af9acc5` Erlang binding
in a temporary package. Both runs use the current native engine and identical
workloads. Source files remain unchanged. Reports under `reports/` retain raw
samples, source fingerprints, runtime versions and the measurement scope.

Next gates are broader independent native oracle coverage, Linux/OTP version
checks, deployment packaging and representative application workloads. A compiled
pattern cache or batching is deferred until workload evidence warrants the added
state and resource policy. No JavaScript API or implementation change is needed
for this transport optimization, and no Erlang support release follows from these
measurements alone.
