import Ajv2020 from 'ajv/dist/2020.js';
import assert from 'node:assert/strict';

// Independent of the Gleam implementation. Keep these options in evidence reports.
export const oracleOptions = Object.freeze({
  strict: true,
  validateSchema: true,
  allErrors: true,
  unicodeRegExp: true,
  coerceTypes: false,
  useDefaults: false,
  removeAdditional: false,
  ownProperties: true,
});

export function compileOracle(schema) {
  return compileWithOptions(schema, oracleOptions);
}

// Explicit, exact-fixture exception: property names are strings, so a numeric
// key schema rejects every present key. This is valid, albeit unsatisfiable for
// nonempty objects. Ajv strictTypes lints it as incompatible with its context.
export function compileNumericPropertyNamesOracle(schema) {
  assert.deepEqual(schema, {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    type: 'object', additionalProperties: { type: 'number' },
    propertyNames: { type: 'number' },
  }, 'Numeric propertyNames exception is limited to the retained audit fixture');
  return compileWithOptions(schema, { ...oracleOptions, strictTypes: false });
}

function compileWithOptions(schema, options) {
  const ajv = new Ajv2020(options);
  if (!ajv.validateSchema(schema)) {
    throw new Error(`Invalid emitted schema: ${ajv.errorsText()}`);
  }
  const validate = ajv.compile(schema);
  return (value) => ({
    accepted: validate(value),
    errors: structuredClone(validate.errors ?? []),
  });
}

// A crash is deliberately not converted into "rejected" by this helper.
export function compareAcceptance({ schema, value, decode }) {
  value = JSON.parse(JSON.stringify(value));
  const before = JSON.stringify(value);
  const expected = compileOracle(schema)(value);
  const actual = decode(value);
  if (typeof actual?.accepted !== 'boolean') {
    throw new Error('Decoder bridge must explicitly report acceptance');
  }
  if (JSON.stringify(value) !== before) throw new Error('Input mutated');
  if (expected.accepted !== actual.accepted) {
    throw new Error(`Acceptance mismatch: ${JSON.stringify({ schema, value, expected, actual })}`);
  }
  return { expected, actual };
}
