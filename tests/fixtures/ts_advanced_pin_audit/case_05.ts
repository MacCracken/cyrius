// Right-nested chain
type Triage<T> =
    T extends string ? "s" :
    T extends number ? "n" :
    T extends boolean ? "b" :
    "other";

// Mixed nesting + infer
type Awaited<T> =
    T extends null | undefined ? T :
    T extends Promise<infer U> ? Awaited<U> :
    T;

// Doubly nested
type Triage2<T> = T extends Array<infer U>
    ? U extends string ? "string-array" : "other-array"
    : T extends string ? "string"
    : "other";
