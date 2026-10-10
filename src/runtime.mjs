import { Ok, Error, toList } from './gleam.mjs';
import { AdmissionError } from './gargamelle.mjs';

// The factories are library-owned opaque Value constructors. Every argument is
// an actual JSON.parse result, never a fabricated provider value.
function convert(value, factories) {
  if (value === null) return factories[0]();
  if (typeof value === 'boolean') return factories[1](value);
  if (typeof value === 'string') return factories[3](value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new RangeError('non-finite number');
    return factories[2](value);
  }
  if (Array.isArray(value)) {
    return factories[4](toList(value.map(item => convert(item, factories))));
  }
  return factories[5](toList(Object.keys(value).map(key => [key, convert(value[key], factories)])));
}

export function parse(text, ...factories) {
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    if (error instanceof SyntaxError) return new Error(new AdmissionError('syntax: ' + error.message));
    throw error; // Operational failures must not become admission errors.
  }
  try {
    return new Ok(convert(value, factories));
  } catch (error) {
    if (error instanceof RangeError && error.message === 'non-finite number') {
      return new Error(new AdmissionError(error.message));
    }
    throw error;
  }
}

function sortedData(value) {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(sortedData);
  const output = Object.create(null);
  for (const key of Object.keys(value).sort()) output[key] = sortedData(value[key]);
  return output;
}

export const canonical = text => JSON.stringify(sortedData(JSON.parse(text)));
export const codepoints = text => [...text].length;
export function pattern_valid(pattern) {
  try {
    new RegExp(pattern, 'u');
    return true;
  } catch (error) {
    if (error instanceof SyntaxError) return false;
    throw error;
  }
}
export const pattern_matches = (pattern, text) => new RegExp(pattern, 'u').test(text);
export const sorted = values => toList([...values].sort());
export const integer = Number.isInteger;
export const finite = Number.isFinite;
// Gleam Int and Float share JavaScript's number representation. These are
// primitive numeric conversions, not generic opaque-value casts.
export const as_int = value => value;
export const as_float = value => value;
export const int_text = String;

export const same_reference = (a, b) => a === b;

// A single-assignment typed construction cell. No schema-author callback is
// called here. Failed graph finalization invalidates escaped placeholders.
export function recursive_cell(make, missing) {
  let state = 'unbound', value;
  return make(
    () => state === 'bound' ? new Ok(value) : new Error(missing),
    next => {
      if (state !== 'unbound') throw new globalThis.Error('Recursive cell already finalized');
      value = next; state = 'bound';
    },
    () => { state = 'rejected'; value = undefined; },
  );
}

// Tracking is local to one schema walk; it retains no process-wide cache.
export function identity_tracker(make) {
  const seen = new Set();
  return make(value => {
    if (seen.has(value)) return true;
    seen.add(value);
    return false;
  });
}

// Tri-color DFS identity state, scoped to one recursive finalization.
// Only completed traversals enter checked; active revisits are cycles.
export function recursion_guard(make) {
  const visiting = new Set(), checked = new Set();
  return make(node => {
    if (visiting.has(node)) return 1;
    if (checked.has(node)) return 2;
    visiting.add(node);
    return 0;
  }, node => { visiting.delete(node); checked.add(node); });
}
