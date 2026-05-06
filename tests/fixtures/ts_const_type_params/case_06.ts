function id<T>(x: T): T { return x; }
function f<T extends U, V = W>(x: T): V { return null as V; }
class Box<T, U = string> {}
type Pair<A, B> = [A, B];
const arrow = <T>(x: T): T => x;
