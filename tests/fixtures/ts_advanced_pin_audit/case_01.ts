// Scalar
const c1 = "foo" as const;
const c2 = 42 as const;
const c3 = true as const;

// Object literal
const cfg = { kind: "user", id: 42, admin: true } as const;
const palette = { red: "#f00", green: "#0f0", blue: "#00f" } as const;

// Array / tuple literal
const flags = [true, false, true] as const;
const triple = [1, "two", 3] as const;

// Nested
const nested = {
    name: "root",
    children: [
        { name: "a", id: 1 },
        { name: "b", id: 2 },
    ] as const,
} as const;
