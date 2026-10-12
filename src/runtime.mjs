import { Ok, Error, toList } from './gleam.mjs';
import { AdmissionError } from './gargamelle.mjs';

// The factories are library-owned opaque Json constructors. Every argument is
// an actual JSON.parse result, never a fabricated provider value.
function convert(value, factories) {
  if (value === null) return factories[0]();
  if (typeof value === 'boolean') return factories[1](value);
  if (typeof value === 'string') { scalar_string(value); return factories[3](value); }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new RangeError('non-finite number');
    return factories[2](value);
  }
  if (Array.isArray(value)) {
    return factories[4](toList(value.map(item => convert(item, factories))));
  }
  return factories[5](toList(Object.keys(value).map(key => {
    scalar_string(key);
    return [key, convert(value[key], factories)];
  })));
}

function scalar_string(text) {
  if (!text.isWellFormed()) throw new RangeError('non-scalar string');
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
    if (error instanceof RangeError && ['non-finite number', 'non-scalar string'].includes(error.message)) {
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

// Walk state is local to one operation and keyed by binding scope and node.
function walkState(scopes, scope) {
  let state = scopes.get(scope);
  if (!state) { state = new Map(); scopes.set(scope, state); }
  return state;
}
export function identity_tracker(make, scope, key) {
  const scopes = new Map();
  return make(value => {
    const state = walkState(scopes, scope(value)), id = key(value);
    const seen = state.has(id);
    state.set(id, true);
    return seen;
  });
}
export function recursion_guard(make, scope, key) {
  const scopes = new Map();
  return make(value => {
    const state = walkState(scopes, scope(value)), id = key(value);
    const previous = state.get(id) ?? 0;
    if (previous === 0) state.set(id, 1);
    return previous;
  }, value => { walkState(scopes, scope(value)).set(key(value), 2); });
}
export const fresh_identity = () => Symbol();
export const with_walk = run => run();

// Direct JSON constructors preserve the admission string domain without parsing.
export const scalar = text => text.isWellFormed();
