type IsString<T> = T extends string ? true : false;
type IsArray<T> = T extends any[] ? true : false;
type IsFn<T> = T extends (...args: any[]) => any ? true : false;

// Instantiations
type R1 = IsString<"x">;
type R2 = IsString<42>;
type R3 = IsArray<number[]>;
type R4 = IsFn<() => void>;
