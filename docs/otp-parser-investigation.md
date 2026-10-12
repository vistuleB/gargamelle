# OTP parser investigation for potential 0.8.0

This is an isolated investigation, not a library change or a prepared release.
The public parser, opaque JSON representation, number conversion and error contract
are unchanged. The branch retains 0.7.0 package metadata until there is a release
feature to prepare. Reproduction: `node verification/otp-parser/investigate.mjs`.

## Prototypes

1. Default `json:decode/1`, recorded as a baseline rather than a compatible adapter.
2. Callback-only `json:decode/3`: explicit last-value object updates with first-key
   insertion order, original-token binary64 conversion where OTP supplies it, and
   a private overflow sentinel checked after duplicate resolution and syntax.
3. A conservative hybrid: fallback to the unchanged parser if the source contains
   `-0` anywhere, or if the callback adapter reports a syntax error. The guard can
   match ordinary strings and negative fractions. No second custom token scanner
   or input rewriting is introduced.

The reference is compiled from an ignored copy with its existing ordered mode
exported for inspection. Its implementation is unchanged. Snapshots compare
binary64 bits, object first-insertion order, values and rejection classes. Node's
JSON.parse independently checks syntax, surviving value admission and numeric bits;
known domain-error precedence differences are not treated as new failures.

## Findings to second-guess

Callback adaptation fixes the default parser's duplicate-value direction and
arbitrary-precision integer representation. A private sentinel also allows an
otherwise overflowing number to disappear through a later duplicate before final
admission. Those concerns do not by themselves require owning a structural scanner.

The local OTP 29.0.5 source supplies `0` to the integer callback for `-0`, and loses
the sign in zero-mantissa exponent tokens such as `-0e0`. A postparse conversion
cannot recover that sign from the returned value or callback token.

OTP rejects an unpaired surrogate before the string callback executes. The valid
JSON text `{"x":"\ud800","x":1}` is admitted by Gargamelle after duplicate
replacement, but callback-only OTP rejects it. A string callback cannot defer a
rejection that has already occurred inside the parser. Raw malformed native UTF-8
is a further question; this corpus focuses on valid Gleam source strings.

Injected callback failures confirm that OTP preserves an integer-callback exception
but reclassifies a float-callback exception as a syntax error. These probes do not
invoke application decoding callbacks. They expose a complication for preserving
operational failures in an internal numeric adapter, especially resource failures.

The hybrid preserves the tested behavior because it retains the full existing
parser. It is consequently an optimization proposal, not a reduction in parser
maintenance. It parses OTP-rejected inputs twice. Its broad zero guard also loses
fast-path coverage on ordinary IDs or text containing `-0`.

## Evidence and performance scope

The corpus contains 9,637 cases: every individual surrogate unit, overwritten
surrogate values, targeted numeric/duplicate/syntax cases, 5,000 seeded generated
inputs (over 2,000 distinct inputs), and 500 truncations. It deliberately overweights
edge cases; route counts are not estimates of production traffic.

Seven timing samples per workload record parse-stage medians and reductions after
warmup and garbage collection. Payloads include a small provider-shaped result,
100 provider-like entries, long scalar text, a 1,000-number array, a false-positive
zero guard and an overwritten surrogate. Two versions of the entry payload expose
the guard cost on IDs containing `blank-0` versus IDs using `blank_0`.

On the first local macOS arm64 run, the compatible hybrid was faster on eligible
small/text/numeric payloads but gave no benefit when entry IDs caused fallback.
Fallback cases were slightly slower. These are bounded observations, not thresholds
or cross-platform performance claims. Callback-only timings on incompatible inputs
are not comparable performance results. Public opaque value construction is not
included, and reductions do not establish allocation or retained-memory savings.

Ignored reports retain exact source fingerprints, corpus hash, runtime versions,
examples, callback behavior and all timing samples. Linux OTP 28 and 29 repeat the
same investigation through the existing workflow's `parser_probe` input; that mode
is explicitly separate from normal release qualification.

## Initial recommendation

Do not promise a full OTP parser replacement for 0.8.0. Original signed-token access
and deferred string-domain admission would need further API support or another
custom scanner/preprocessor. A hybrid can be considered only as a separately
measured optimization worth keeping alongside the current parser. Keep production
parsing unchanged until compatibility, operational failure handling and full-path
costs justify an integration.

## Completed cross-platform checkpoint

Probe commit `3eae10b` passed on macOS arm64 OTP 29.0.5 and Ubuntu 24.04 x86_64
OTP 28 and 29. Linux run `38276182470` retains both reports. Corpus hashes match:
9,637 cases, including 2,114 distinct generated inputs. The hybrid matched the
reference in all three runs; callback-only output differed on 5,640 edge cases
in each. Both negative-zero and overwritten-surrogate blockers persisted, as did
float-callback exception reclassification.

Within-machine parse-stage median ratios for the compatible hybrid were roughly
1.6–2.7x on the small provider-shaped result, 2.1–2.5x on eligible provider-like
entries, 8–11x on long scalar text, and 2.1–3.5x on the numeric array. The otherwise
identical entry payload containing blank-0 IDs received no consistent benefit.
The tiny guarded-text and overwritten-surrogate fallback cases were slower. These
measurements exclude public Json construction and do not establish full-path or
allocation savings; platform timings must not be compared as hardware rankings.

Recommendation: retain production parsing. Do not promise callback-only replacement
for 0.8.0. Before considering a hybrid integration, measure the complete public
parse path, allocation/retention behavior, realistic fallback frequency, and
operational failure handling. Direct JSON construction inside encoding remains a
separate, potentially simpler optimization for both targets. No contract relaxation
or upstream issue publication has been performed.

The final evidence summary is reports/otp-parser-investigation-summary.json. These
status notes follow the probe commit; they do not change its executable source.

## Public-path and retained-buffer follow-up

The isolated `full-path.escript` loads the freshly compiled public Gleam module
and replaces only its runtime dependency inside a disposable VM. The same
`gargamelle.parse` constructor callbacks execute in reference, hybrid, and
string-copying hybrid variants. Eleven representative inputs, including error
and duplicate-replacement cases, produced exactly equal public results. This is
additional smoke coverage, not another exhaustive compatibility run.

A concrete retention case exposed an additional integration cost. The input has
a 128-byte `keep` string and a 1 MiB `discard` string. Decoding an open record
retains only `keep`. `binary:referenced_byte_size` reports:

| Parser variant | Retained string bytes | Referenced backing bytes |
| --- | ---: | ---: |
| Existing parser | 128 | 128 |
| OTP hybrid | 128 | 1,048,728 |
| OTP hybrid with `string => fun binary:copy/1` | 128 | 128 |

Default OTP decoding shares that larger backing binary as well. Explicit copying
removes this particular retention hazard. These sizes describe backing-buffer
sharing, not total allocations or process memory. A future adapter must decide
its ownership policy deliberately; allowing a small decoded field to pin a large
discarded document is a material change in memory behavior.

On local macOS OTP 29, exploratory complete-public-parse measurements still show
benefits on eligible text and numeric payloads, including the copying variant.
However, the three variants run sequentially in one VM, and timings vary across
phases even on unchanged fallback paths. The harness does not control heap/phase
effects sufficiently for a release speed claim. Retention results repeated;
performance conclusions require randomized isolated runs, representative input
mixes, and Linux repetition. No production parser integration is justified yet.

To repeat this follow-up, first build a checkout whose source matches this
research branch's unchanged production modules with `gleam build --target erlang`.
Then run from the research worktree:

```sh
node verification/otp-parser/full-path.mjs /absolute/path/to/checkout/build/dev/erlang
```

The ignored report `reports/otp-parser-full-path.json` records the compiled public
module hash, source fingerprint, runtime, individual samples, routes, exact-result
comparison, and retained-buffer sizes. Temporary runtime/probe copies are ignored
under `reports/`; shipped source is unchanged.

## Controlled benchmark protocol

`controlled.mjs` replaces the sequential hot-reload benchmark with separate VMs.
Each of ten workloads runs five times per variant, with a reproducible shuffled
workload/variant order. Each VM loads either the reference runtime or the hybrid
with explicit string copying. One BEAM scheduler, 200 warmups and three timed
samples are used; startup and compilation are excluded. Parsing uses the actual
compiled public Gleam module. Public-result hashes must match, and each VM checks
that a small field decoded from a large open record retains only its own buffer.

The corpus includes small provider results, 100 provider entries with eligible or
fallback-triggering IDs, long Unicode text, numeric arrays, guarded ordinary text,
small configuration objects, mixed nested structures, and rejected/overwritten
surrogates. These are synthetic workload families rather than captured consumer
traffic; their frequency is unknown, so no weighted overall speedup is claimed.
Validation, decoding and handlers are excluded from timing. A copying-adapter
repeat of the 9,637-case compatibility corpus accompanies the benchmark.

Run `gleam build --target erlang`, then:

```sh
node verification/otp-parser/investigate.mjs --copy-strings
node verification/otp-parser/controlled.mjs
```

Reports are `reports/otp-parser-copying-investigation.json` and
`reports/otp-parser-controlled.json`. The latter retains every VM's samples,
median ranges, randomized execution order, source and compiled-module hashes,
workload hash, runtime version and retention checks. The research workflow's
`parser_probe` mode also runs this protocol on Linux OTP 28 and 29. This mode is
separate from normal release qualification.

## Controlled results and decision

Benchmark commit `b2ef3cc` completed on macOS arm64 OTP 29.0.5 and Linux x86_64
OTP 28 (ERTS 16.4.0.6) and 29 (ERTS 17.1). Linux run `38278637102` succeeded for
both jobs. Each platform completed 100 fresh benchmark VMs. Compiled public-module
hashes and workload hashes match across platforms; executed benchmark/parser source
hashes match the current research checkout. The copying compatibility adapter also
matched the reference on all 9,637 cases on each platform. Every VM's small-field
retention check passed, with 128 referenced bytes rather than the 1 MiB input.

Within-machine speedups below compare reference median time to copying-hybrid
median time. Values above 1 mean the hybrid is faster. Hardware/runtime results
must not be compared as platform rankings.

| Workload | macOS OTP 29 | Linux OTP 28 | Linux OTP 29 |
| --- | ---: | ---: | ---: |
| Small provider result | 1.88x | 1.86x | 2.00x |
| 100 provider entries, eligible IDs | 1.29x | 1.18x | 1.28x |
| 100 provider entries, fallback IDs | 1.03x | 1.03x | 0.99x |
| Long scalar text | 5.81x | 9.03x | 10.30x |
| Numeric array | 2.58x | 3.00x | 3.10x |
| Small configuration | 1.55x | 1.48x | 1.58x |
| Nested mixed JSON | 1.98x | 1.91x | 2.09x |
| Ordinary guarded text | 0.84x | 0.81x | 0.82x |
| Overwritten surrogate | 0.81x | 0.81x | 0.78x |
| Rejected surrogate | 0.23x | 0.13x | 0.17x |

Tiny fallback slowdowns are measured in microseconds: guarded text gains roughly
0.3–0.4 microseconds of overhead, overwritten surrogates roughly 0.8–1.7, and
rejected surrogates roughly 0.7–1.2. Large ID-triggered fallback differences are
near parity and within the measured ranges. Large eligible provider payloads gain
about 18–29% speed, while long-text/numeric gains are substantially larger. The
previous phase-dependent discrepancy disappeared with separate VMs.

Decision: retain production parsing. The copying hybrid is a technically credible
performance option, but not a simpler parser replacement. Integration should follow
a consumer profile showing that parsing is material and that its actual payloads
use the fast path frequently. Before shipping, operational failure classification,
broader full-public-path compatibility, and deployment qualification remain gates.
No contract relaxation is proposed. Encoding's serialize/reparse step remains a
separate optimization with potential benefit on both targets; this benchmark does
not measure or implement that optimization.

The ignored evidence index `reports/otp-parser-controlled-summary.json` links the
three controlled reports and copying-corpus reports and records the tested commit.
Production source, main, package version, published archives and tags are unchanged.
