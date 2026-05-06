type R<T> = { readonly [K in keyof T]: T[K] };
type AddR<T> = { +readonly [K in keyof T]: T[K] };
type Mut<T> = { -readonly [K in keyof T]: T[K] };
