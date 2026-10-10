export function counter(make) {
  let count = 0;
  return make(() => { count += 1; }, () => count);
}
// Only the Erlang runner demonstrates process transfer and creator exit.
export function handoff(build) { return build(); }
