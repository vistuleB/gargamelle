import { registerSchema, unregisterSchema, validate } from '@hyperjump/json-schema/draft-2020-12';

let sequence = 0;
// Supplementary independent evidence for a documented Ajv discrepancy, not a
// replacement that is silently selected whenever two results disagree.
export async function compileSupplementary(schema) {
  const uri = `https://schema-contract.invalid/fixture/${sequence++}`;
  registerSchema({ ...schema, $schema: 'https://json-schema.org/draft/2020-12/schema' }, uri);
  try {
    const check = await validate(uri);
    return value => ({ accepted: check(value).valid });
  } finally {
    unregisterSchema(uri);
  }
}
