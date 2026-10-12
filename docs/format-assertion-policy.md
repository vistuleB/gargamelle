# Format assertion policy for review

`format(definition, name)` is metadata only. An arbitrary format name must not
silently activate runtime validation. The default 2020-12 dialect uses the
Format-Annotation vocabulary; declaring Format-Assertion would create broader
implementation obligations. See [validation vocabularies](https://json-schema.org/draft/2020-12/json-schema-validation#section-7.2).

The first explicit assertion is `assert_format(definition, Uuid)`. It is composed
from ordinary constraints: string-only conditional checking, exactly 36 Unicode
scalar characters, and ASCII hexadecimal/dash syntax. The `uuid` annotation is
attached to the constrained string branch, which also supplies its string type.
The schema enforces acceptance without enabling optional format validation.
Converters remain those of the base definition and run only after acceptance.

This matches the plain UUID syntax described by the
[2020-12 UUID format](https://json-schema.org/draft/2020-12/json-schema-validation#section-7.3.5)
and [UUID string representation](https://www.rfc-editor.org/rfc/rfc9562.html#section-4):
8-4-4-4-12 hexadecimal digits, case-insensitive. Accepted output preserves case.
Nil and all-ones UUIDs are accepted; version and variant bits are unrestricted.
The helper does not assert a UUID's origin, uniqueness, version or security
properties. URNs, braces, spaces and compact undashed representations are rejected.

Length is asserted as well as the pattern: JavaScript's `$` anchor can match
before a final line terminator, so pattern anchoring alone would be insufficient.
The explicit length requirement rejects trailing line terminators on both targets
and in the emitted schema. Regex resource failures remain operational failures,
including on native Erlang; they are not converted to successful certification.

The helper accepts a generic definition because JSON Schema formats only apply
to string instances. A boolean base remains valid for booleans; a text base plus
the UUID assertion accepts only UUID strings. Maps preserve their existing output
type. Bounds and other primitive modifiers should be supplied before the helper,
which composes a conditional definition.

Email, URI and date/time assertions are deferred. Their standards, normalization,
internationalization, parser behavior and validator compatibility need separate
decisions and corpora. Do not introduce a global validation switch that changes
decoder acceptance without corresponding schema constraints. Do not claim the
full Format-Assertion vocabulary from this single supported helper.

## Verification checkpoint

The complete feature-list run passed 70 shared Gleam tests and 158 Node checks.
The native production-plan gate passed 78 tests, 32 existing negative checks and
3,636 cases across 36 schemas against historical JavaScript and native behavior.
UUID-specific cases agree with Ajv (format assertions explicitly disabled) and
Hyperjump through the emitted ordinary constraints. They cover lower/upper case,
nil/all-ones UUIDs, invalid hex, compact syntax, URNs, spaces and trailing line
terminators. Shared native tests exercise the actual C regex helper.

`gleam docs build`, formatting and diff checks passed. This is development
evidence, not a prepared release or a new browser/Linux runtime qualification.
