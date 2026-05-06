type Snoc<T extends any[], U> = [...T, U];
type WithSuffix = [...string[], number];
type FixedTail = [...readonly Foo[], Bar, Baz];
