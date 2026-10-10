import Ajv2020 from 'ajv/dist/2020.js';

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
  const ajv = new Ajv2020(oracleOptions);
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
