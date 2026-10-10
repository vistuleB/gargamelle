export function counter(make) {
  let count = 0;
  return make(() => { count += 1; }, () => count);
}
// Only the Erlang runner demonstrates process transfer and creator exit.
export function handoff(build) { return build(); }
export function measure(run) {
  const before = performance.now();
  run();
  return [Math.round((performance.now() - before) * 1000), 0];
}
export function fresh_identity() { return Symbol(); }
