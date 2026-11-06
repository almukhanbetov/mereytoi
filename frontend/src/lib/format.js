export function formatPrice(n) {
  return n.toLocaleString('ru-RU') + ' ₸';
}

/** Russian plural form for a count — e.g. pluralRu(3, ['вариант', 'варианта', 'вариантов']) -> 'варианта'. */
export function pluralRu(n, [one, few, many]) {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
  return many;
}

// A whole-number count with spaces between thousands, the same on the server
// and in the browser whatever the locale.
export function formatCount(value) {
  return String(Math.max(0, Math.trunc(Number(value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, '\u00a0');
}
