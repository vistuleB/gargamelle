// Auditable, test-only translations. Never a public arbitrary-schema importer.
const fail = why => { throw new Error(why); };
export function translate(raw, inheritedType) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('Boolean schema has no direct constructor in selected subset');
  const schema = { ...raw };
  delete schema.$schema; delete schema.$comment;
  const keys = Object.keys(schema);
  let type = schema.type ?? inheritedType;
  if (Array.isArray(type)) {
    if (type.length !== 1) fail('Multi-type source schema not selected; nullable/general unions tested through explicit constructors');
    [type] = type;
  }
  const only = allowed => {
    const extra = keys.filter(k => !allowed.includes(k));
    if (extra.length) fail(`Unsupported source-keyword combination: ${extra.join(', ')}`);
  };
  for (const keyword of ['anyOf', 'oneOf']) if (schema[keyword]) {
    only(['type', keyword]);
    return { kind: keyword === 'anyOf' ? 'any' : 'one', children: schema[keyword].map(child => translate(child, type)) };
  }
  if (Object.hasOwn(schema, 'const')) {
    only(['const']);
    const value = schema.const;
    if (value !== null && !['string', 'boolean'].includes(typeof value) && !Number.isSafeInteger(value)) fail('General JSON or unsafe-number constants are deferred');
    return { kind: 'constant', value };
  }
  if (schema.enum) {
    only(['enum']);
    if (!schema.enum.length || !schema.enum.every(v => typeof v === 'string')) fail('Only nonempty string enums selected');
    return { kind: 'enum', values: schema.enum };
  }
  if (type === 'string') {
    only(['type', 'minLength', 'maxLength', 'pattern']);
    return { kind: 'string', min: schema.minLength, max: schema.maxLength, patterns: schema.pattern ? [schema.pattern] : [] };
  }
  if (type === 'boolean' || type === 'null') { only(['type']); return { kind: type }; }
  if (type === 'integer') {
    only(['type', 'minimum', 'maximum']);
    if (!Number.isSafeInteger(schema.minimum) || !Number.isSafeInteger(schema.maximum)) fail('Unbounded integer schema is not equivalent to bounded safe-integer constructor');
    return { kind: 'integer', min: schema.minimum, max: schema.maximum };
  }
  if (type === 'array') {
    only(['type', 'items', 'minItems', 'maxItems']);
    if (!schema.items) fail('Unconstrained array items require unrestricted JSON-value constructor');
    return { kind: 'array', child: translate(schema.items), min: schema.minItems, max: schema.maxItems };
  }
  if (type === 'object') {
    only(['type', 'properties', 'required', 'additionalProperties', 'minProperties', 'maxProperties']);
    if (schema.additionalProperties && typeof schema.additionalProperties === 'object') {
      if (schema.properties || schema.required) fail('Mixed record/dictionary source rules deferred');
      return { kind: 'dictionary', child: translate(schema.additionalProperties), min: schema.minProperties, max: schema.maxProperties };
    }
    if (schema.minProperties != null || schema.maxProperties != null) fail('Record property-count constraints are not exposed');
    const props = schema.properties ?? {};
    if ((schema.required ?? []).some(k => !Object.hasOwn(props, k))) fail('Required unrestricted fields need an unrestricted JSON-value constructor');
    return { kind: 'record', open: schema.additionalProperties !== false, fields: Object.entries(props).map(([name, child]) => ({ name, child: translate(child), presence: schema.required?.includes(name) ? 'required' : 'optional' })) };
  }
  fail(type === 'number' ? 'General number constructor deferred' : 'Untyped keyword applicability or unsupported type cannot be strengthened to a typed constructor');
}
