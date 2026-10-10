export function counter(make) {
  let count = 0;
  return make(() => { count += 1; }, () => count);
}
export const handoff = build => build();
