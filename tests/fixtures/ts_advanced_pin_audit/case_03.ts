// Type aliases
type T1 = never;
type T2 = unknown;
type T3 = never[];
type T4 = unknown[];

// Function return positions
function fail(): never { throw new Error("unreachable"); }
function asUnknown(x: any): unknown { return x; }

// Variable declarations
let x: never = (() => { throw 0; })();
let y: unknown = 1;

// Object members
type State = {
    last_error: never | null;
    payload: unknown;
};

// Union / intersection
type T5 = string | never;
type T6 = unknown & { tag: "x" };

// Conditional with never (the "no match" idiom)
type Filter<T, U> = T extends U ? T : never;

// Generic constraints
function assertNever(x: never): never { throw new Error("unreachable"); }
function unwrap<T>(x: T | unknown): T { return x as T; }
