function pickK<const K extends string>(key: K) { return key; }
function pickN<const N extends number>(n: N) { return n; }
function tagged<const T extends Record<string, unknown>>(x: T) { return x; }
