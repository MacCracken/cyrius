type X<T> = { -readonly [K in keyof T as `_${string & K}`]-?: T[K] };
type Y<T> = { +readonly [K in keyof T as Lowercase<K & string>]+?: T[K] };
