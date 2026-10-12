# Divisibility policy for review

JSON Schema requires a positive `multipleOf` divisor and an integral quotient.
See the [2020-12 validation specification](https://json-schema.org/draft/2020-12/json-schema-validation#section-6.2.1).
Gargamelle admits finite binary64 numbers, not arbitrary-precision decimal values.

The first implementation deliberately exposes `integer_multiple_of`, restricted
to safe-integer definitions and positive safe-integer divisors. It uses integer
remainders on both targets. Repeated constraints intersect, without taking an LCM
that could exceed the supported integer range. It preserves existing converters.
It rejects `number()` definitions and fractional divisors rather than silently
introducing a tolerance or a rounded-quotient rule.

General fractional divisibility remains deferred. The independent validators
already disagree on small examples, as well as overflow-sized quotients:

| Value | Divisor | Ajv 8.20.0 | Hyperjump 1.18.0 |
| --- | --- | --- | --- |
| 0.3 | 0.1 | Reject | Accept |
| 0.7 | 0.1 | Reject | Accept |
| 0.29 | 0.01 | Reject | Accept |
| 9007199254740991 | 0.01 | Accept | Reject |
| 1e308 | 0.25 | Reject | Accept |

Observed 2026-10-11 with default numeric policies. Reproduce with
`node verification/multiple-of-policy.mjs`. These observations are not a decision
that one validator defines the specification. They show why claiming agreement
with both across the complete floating-point domain would be premature.

The safe-integer implementation is checked against exact BigInt remainders and
both independent validators across 3,626 cases, including negative inputs and
safe-integer endpoints. Shared tests exercise divisor validation, intersecting
constraints, bounds and exact schema emission on both targets.

Before generalizing, choose and document how admitted binary64 values correspond
to the specification's mathematical numbers; decide how canonical decimal text,
rounding, quotient overflow and validator discrepancies are handled. Do not add
an epsilon only to make common decimal examples pass. That can admit genuinely
non-divisible values and silently widen the decoder's acceptance relation.
