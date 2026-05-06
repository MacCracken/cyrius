type Concat<A extends any[], B extends any[]> = [...A, ...B];
type Three<A extends any[], B extends any[], C extends any[]> = [...A, ...B, ...C];
type Mixed = [P, ...A, ...B, Q];
