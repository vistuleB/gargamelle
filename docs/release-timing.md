# Release qualification timing investigation

Measured candidate: main `e962e35` (0.8.0). Instrumentation: research branch
`codex/release-timing`, commit `135454f`. Linux run `38284751665` retained both OTP
reports. All original checks passed: 129 shared tests, 184 Node tests, 17 native
groups, archive inspection and fresh consumers. Production source and the prepared
main archive were not modified.

## Wall-clock measurements

Seconds; one fresh run per platform. Nested tests run in parallel locally, so
individual test durations must not be added to these phase totals.

| Preparation phase | macOS arm64 OTP 29 | Linux OTP 28 | Linux OTP 29 |
| --- | ---: | ---: | ---: |
| JavaScript verification (includes both-target compile/integration checks) | 30.475 | 111.825 | 81.801 |
| Evidence/fingerprint review | 0.213 | 0.208 | 0.156 |
| Native verification | 24.739 | 131.435 | 85.489 |
| Documentation generation | 0.080 | 0.197 | 0.148 |
| Archive export | 0.114 | 0.239 | 0.179 |
| Archive extraction/listing | 0.022 | 0.021 | 0.017 |
| Fresh JavaScript archive consumers | 1.052 | 1.360 | 1.013 |
| Archive C helper compilation | 1.060 | 1.535 | 1.262 |
| Fresh Erlang archive consumers | 7.900 | 21.399 | 6.904 |
| Version recording | 0.462 | 0.444 | 0.342 |
| Other runner/inspection work | 0.420 | 0.417 | 0.365 |
| **Preparation total** | **66.536** | **269.081** | **177.676** |

The two Linux jobs run concurrently. The whole workflow took 300 seconds,
including 4 seconds of queueing, setup, qualification and upload/cleanup.

| GitHub workflow step | OTP 28 | OTP 29 |
| --- | ---: | ---: |
| Queue before job start | 4 | 4 |
| Set up job | 4 | 5 |
| Checkout | 1 | 1 |
| Node setup | 6 | 7 |
| BEAM/Gleam setup | 7 | 9 |
| Dependency fetch | 2 | 1 |
| Build-tool version checks | 0 | 0 |
| Qualification and archive checks | 269 | 178 |
| Artifact upload | 2 | 1 |
| Post-action cleanup | 0 | 1 |

Step timestamps have one-second resolution and omit small inter-step gaps.
Downloading the two completed evidence artifacts took approximately 1.19 seconds
per artifact, concurrently, using the tool's process wall-clock measurement.
The preceding uninstrumented main run `38283302275` took 326 seconds including
81 seconds of queueing and 185/223 seconds of qualification. Queue/host variation
therefore affects turnaround; these are observations rather than performance limits.

## Main scheduling difference

Node 24.10 defaults test-file concurrency to available CPU count minus one,
with a minimum of one. This was checked in the installed Node source and its
[official CLI documentation](https://nodejs.org/download/release/v24.10.0/docs/api/cli.html#--test-concurrency).
The Mac exposes ten available CPUs. The Linux jobs expose two BEAM schedulers;
recorded test durations show serial file execution, consistent with the default
one-worker policy on these runners. Neither release test command supplies an
explicit concurrency option.

The JavaScript suite's individual test durations sum to 103 seconds locally and
105 seconds on Linux OTP 28. Its suite wall time is approximately 30 versus 111
seconds. Native test durations sum to 117 versus 130 seconds, while suite wall
time is approximately 25 versus 131 seconds. The scheduling difference explains
most of the extra elapsed time; individual tests are not uniformly slower on Linux.

The local longest test is the 60 compile-negative programs on both targets:
122 compiler invocations including positive baselines. Total compiler time was
29.54 seconds locally, 25.75 on Linux OTP 28 and 21.49 on Linux OTP 29. It is a
large test cost, but does not by itself explain Linux's serial suite totals.
Historical encoder/recursion prototypes, duplicate guide compilations, native
operator mutations and generated oracles also contribute to those totals.

Recommendation: first measure an explicit test-file concurrency of two on the
existing Linux runners, retaining every check. Compare four only if useful; CPU
and memory contention make a speedup uncertain. Consolidating repeated compilations
and moving historical prototype work out of routine release qualification are
separate candidates. No concurrency setting or gate removal was made in this pass.

## Evidence and repeatability

`reports/release-timing-summary.json` retains every observed command with its
parent ID, timestamps, status and duration, all preparation phases, slowest test
records and every GitHub step. Raw `release-timings.jsonl` files accompany each
platform's qualification reports. Instrumentation wraps Node subprocess APIs;
internal native port operations and filesystem work are covered by their parent
command/group timings, rather than individually instrumented. Environments,
stdin and subprocess output are not captured by the tracer.

Pinned local dependencies were copied before timing. Linux dependency installation
was timed separately; VM/action setup uses workflow timestamps. Small tracing and
file-writing overhead is included. No library performance claim follows from
these release-harness timings.

Repeat with `node verification/release-timing.mjs prepare` and invoke the research
workflow on `codex/release-timing`. After downloading reports, pass a JSON config
containing `platforms` (name/directory), `ciRun`, `measurementCommit` and
`releaseCommit` to `node verification/analyze-release-timing.mjs config.json`.
