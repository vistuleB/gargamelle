# Admitted JSON construction decisions for review

0.7.0 constructors retain opaque Json and the existing admitted domain. They do
not certify a definition or Contract. Scalars are checked directly; containers
trust already admitted children rather than serializing or recursively scanning.

Object constructors reject duplicate keys with the offending key in JsonError.
This is deliberate: manually assembling a duplicate usually indicates a caller
mistake. Parsing keeps its existing last-value behavior. Empty and hostile keys
remain valid. Invalid native UTF-8 and JavaScript unpaired surrogates reject.

json_int rejects integers outside the common safe range to avoid silent rounding;
json_number accepts all finite binary64 Floats. These are different input types
and promises. Constructor errors are separate from parser AdmissionError and
schema ConstructionError. Callback exceptions are not introduced or caught.

Encoder optimization is deferred: this feature alone changes no encoding path.
The potential OTP parser investigation is reserved for 0.8.0.
