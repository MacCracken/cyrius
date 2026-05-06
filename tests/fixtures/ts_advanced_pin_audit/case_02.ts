// zod-shape: validate config against a record type
const palette = { red: "#f00", blue: "#00f" } satisfies Record<string, string>;

// react-shape: typed event handler
type Handler = (e: Event) => void;
const onClick = ((e) => console.log(e)) satisfies Handler;

// redux-shape: action creator return type
type Action = { type: string; payload?: unknown };
const setUser = (id: number) => ({ type: "user/set", payload: id }) satisfies Action;

// const + satisfies combo (TS 5.0 idiom)
const routes = {
    home: "/",
    user: "/u/:id",
    post: "/p/:slug",
} as const satisfies Record<string, string>;

// Tuple satisfies
const pair = [1, "x"] satisfies [number, string];

// Object satisfies with optional fields
type Cfg = { name: string; debug?: boolean };
const c = { name: "app" } satisfies Cfg;
