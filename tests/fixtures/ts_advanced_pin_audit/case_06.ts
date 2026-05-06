// Standard utility shapes
type Unwrap<T> = T extends Promise<infer U> ? U : T;
type ElementOf<T> = T extends Array<infer E> ? E : never;
type ArgsOf<F> = F extends (...args: infer A) => any ? A : never;
type ReturnT<F> = F extends (...args: any[]) => infer R ? R : never;
type FirstArg<F> = F extends (first: infer F1, ...rest: any[]) => any ? F1 : never;

// Infer in object position
type Prop<T, K extends keyof T> = T extends { [P in K]: infer V } ? V : never;

// Infer in tuple position
type Head<T extends any[]> = T extends [infer H, ...any[]] ? H : never;
type Tail<T extends any[]> = T extends [any, ...infer R] ? R : never;
