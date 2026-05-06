type P<T> = { [K in keyof T]?: T[K] };
type Opt<T> = { [K in keyof T]+?: T[K] };
type Req<T> = { [K in keyof T]-?: T[K] };
