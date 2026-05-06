type CapKeys<T> = { [K in keyof T as Capitalize<string & K>]: T[K] };
type Filter<T, U> = { [K in keyof T as T[K] extends U ? K : never]: T[K] };
type Prefix<T> = { [K in keyof T as `_${string & K}`]: T[K] };
