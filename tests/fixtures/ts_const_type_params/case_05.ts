class Box<const T> {
    constructor(public v: T) {}
    method<const U>(u: U): U { return u; }
}
interface I<const T> {
    method<const U>(u: U): U;
}
type Wrap<const T> = T;
type Pair<const A, const B> = [A, B];
const arrow = <const T>(x: T): T => x;
const generic = <const T extends string>(x: T) => x;
