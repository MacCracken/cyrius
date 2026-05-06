type Pick<T, K extends keyof T> = { [P in K]: T[P] };
type R<T> = { [K in keyof T]: T[K] };
type U = { [K in "a" | "b"]: number };
