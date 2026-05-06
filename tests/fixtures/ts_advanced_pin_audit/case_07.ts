// Distributive (T extends bare-type-param)
type ToArr<T> = T extends any ? T[] : never;
type StrOrNumArr = ToArr<string | number>;   // string[] | number[]

type Filter<T, U> = T extends U ? T : never;
type StringOnly = Filter<"a" | 1 | "b" | 2, string>;   // "a" | "b"

type Exclude2<T, U> = T extends U ? never : T;

// Non-distributive (wrapped tuple)
type IsString<T> = [T] extends [string] ? "yes" : "no";
type R1 = IsString<string>;       // "yes"
type R2 = IsString<string | number>;   // "no" (not distributed)

// Mixed
type DeepArr<T> = T extends any
    ? T extends object ? T[] : T
    : never;
