// Test integration adapter: composite keys must use their primitive scope/node
// identities, not the identity of a freshly allocated Gleam tuple or Option.
function stateFor(scopes, key) {
  const scope = key[0]?.[0];
  let state = scopes.get(scope);
  if (!state) { state = new Map(); scopes.set(scope, state); }
  return [state, key[1]];
}
export function identity_tracker(make, key) {
  const scopes = new Map();
  return make(value => {
    const [state, id] = stateFor(scopes, key(value));
    const seen = state.has(id);
    state.set(id, true);
    return seen;
  });
}
export function recursion_guard(make, key) {
  const scopes = new Map();
  return make(value => {
    const [state, id] = stateFor(scopes, key(value));
    const previous = state.get(id) ?? 0;
    if (previous === 0) state.set(id, 1);
    return previous;
  }, value => {
    const [state, id] = stateFor(scopes, key(value));
    state.set(id, 2);
  });
}
