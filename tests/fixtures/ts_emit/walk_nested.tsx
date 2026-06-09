// v6.1.10 AST-walk gate fixture — exercises every children-list builder
// that the pre-fix allocator corrupted (call args, block stmts, object
// props, array elems, destructuring, JSX attrs/children, template, switch,
// var bindings, ROOT). `cycc --emit-js` must walk it without a revisit /
// out-of-range list entry (exit 0).
interface Note { id: number; }
type F = <T,>(x: T) => T;

function row({ id, body }: Note, ...rest: number[]): JSX.Element {
  const parts = [id, body, fmt(id, 1)];
  const opts = { method: "POST", "data-id": id, ...rest };
  const msg = `id=${id} body=${body}`;
  switch (id) {
    case 0: return <li className="z" data-id={id}>{body}<span/></li>;
    default: return <ul>{parts}<time>{msg}</time></ul>;
  }
}

// v6.1.12: for / for-of / for-in headers (a var-decl binding must NOT carry its
// statement `;` here — regression guard for the stray/double-semicolon bug).
function loops(arr: number[], o: object): void {
  for (let i = 0; i < arr.length; i = i + 1) {
    console.log(arr[i]);
  }
  for (const x of arr) {
    console.log(x);
  }
  for (const k in o) {
    console.log(k);
  }
}

// v6.1.15: async must bind to the node it was parsed on, not migrate to the
// first nested arrow. `asyncWithNestedArrow` must emit `async function` on the
// OUTER and a PLAIN `.map` arrow inside (pre-fix the emitter moved `async`
// onto the inner arrow, leaving a bare `await` → invalid JS). Also covers an
// async class method and an async paren-arrow, both with nested arrows.
async function asyncWithNestedArrow(): Promise<void> {
  const xs = [1, 2, 3];
  const ys = xs.map((n) => n + 1);
  await Promise.resolve(ys);
}
class AsyncHolder {
  async render(): Promise<void> {
    const rows = [1, 2].map((m) => m * 2);
    await Promise.resolve(rows);
  }
}
const asyncArrow = async (n: number) => {
  const w = [n].map((m) => m);
  return await Promise.resolve(w);
};

export { row, loops, asyncWithNestedArrow, AsyncHolder, asyncArrow };
