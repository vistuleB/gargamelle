# 0.8.0 release preparation

The bounded modifier-composability pass at `7899183` was promoted to main for
0.8.0 preparation. Scope: remove unjustified naming/annotation restrictions,
preserve applicable same-input constraints, document unsupported combinations,
and retain every array membership/conjunction clause in schema emission.
Public signatures, JSON admission, parsing, semantic Contracts and native helper
deployment are unchanged. Parser research and speculative features are excluded.

Before version preparation, 129 shared tests passed on each target, along with
184 Node tests and all 17 native verification groups. Composed schemas/decoded
outputs agree across targets and with Ajv and Hyperjump. Named-body conflicts,
unsupported alternatives/references, validated defaults, callback suppression,
recursive bodies, membership limits and targeted mutations have regressions.

`npm run prepare:release` qualifies the versioned source, builds docs, exports the
Hex archive, verifies its README and contents, and runs fresh extracted-archive
consumers on JavaScript and Erlang. Those consumers also exercise the new modifier
compositions and compare schemas and decoded outputs. The ignored
`reports/release-preparation.json` records exact source/archive hashes and logs.
Hosted native qualification repeats the release workflow on Linux OTP 28 and 29;
its reports are separate from local macOS qualification. External review of the
preservation argument remains separate from automated test evidence.

Publication is the maintainer's action. Preparation does not publish, create a
release tag, or move an existing tag. Further feature work is paused pending
consumer feedback after this bounded pass.
