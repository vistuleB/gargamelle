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
