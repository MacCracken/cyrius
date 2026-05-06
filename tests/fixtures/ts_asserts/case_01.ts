function isString(x: any): asserts x is string {}
function chk(x: unknown): asserts x is number | bigint {}
function notNull<T>(x: T | null): asserts x is T {}
