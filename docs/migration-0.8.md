# Migrating to 0.8.0

0.8.0 improves modifier composition. Public function signatures and types are
unchanged. Existing direct definitions retain their acceptance and decoded output.

Naming and documentation annotations now preserve support for `bounds`,
`number_bounds`, `pattern`, `integer_multiple_of` and `unique_items`. Applicable
same-input assertions also preserve support: for example, array bounds can follow
uniqueness, and a pattern can follow a conditional assertion on a text base.
Repeated array membership checks retain all earlier membership and exclusion rules.

Modifiers constrain the JSON input shape, even when `map` changes the decoded
output type. They do not distribute over nullable/union/tagged alternatives or
resolve recursive references. Apply a modifier to the selected branch or recursive
body during construction. Unsupported combinations return construction errors.

Bounds, patterns and integer divisibility update an underlying named body while
retaining its name. Combining original and modified bodies under one name produces
the existing graph-conflict error. Distinct reusable bodies need distinct names.
Array/object assertion modifiers can instead constrain a use of a shared named
body. See the [modifier policy](advanced.html#modifier-composition) for the
supported input bases and naming rules.

JSON admission, parsing, semantic Contracts, receiving boundaries and explicit
encoding are unchanged. Native Erlang retains its existing parser and C helper
setup. No OTP parser replacement is included.
