function mix<T, const U, V>(a: T, b: U, c: V) {}
function mix2<const A, B, const C>(a: A, b: B, c: C) {}
function mix3<A extends string, const B, C = number>(a: A, b: B, c: C) {}
