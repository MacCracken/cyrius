# cyrius `--target=js` / `cycc --emit-js`: `async` is misplaced when an `async function` contains a nested arrow

> **RESOLVED — cycc 6.1.15 (2026-06-08).** Root cause confirmed exactly as the
> "Likely root cause" section guessed: the TS parser tracked `async` in a single
> ambient pending slot (`TS_PS_PENDING_ASYNC`), but `TS_PARSE_DECL_FUNCTION`, the
> class/object method parsers, and `TS_PARSE_ARROW_PAREN` all parsed their body
> **before** pushing+consuming their own node — so the first nested arrow's
> `CONSUME_ASYNC` stole the flag. Fix: new `TS_PS_TAKE_ASYNC` (take-and-clear at
> each node-owner's entry, before params/body) + `TS_AST_SET_ASYNC` (apply after
> push), wired into all five body-before-consume sites. The single-ident arrow
> already consumed before its body (correct, unchanged). Verified across the full
> matrix (async function / async class method / async object method / block- and
> **expression**-body async arrows), each enclosing a nested `.map(arrow)`:
> `async` stays on the owner, nested arrows are plain, `node --check` passes.
> Regression guard added: `walk_nested.tsx` gains the async-nested-arrow shapes +
> a node-free `_emit_async_misplaced` scanner in the emit-js check gate. x86 cycc
> self-host byte-identical; ecb/cass cross-OS green; check.sh 87/87. The
> `yeo-cy-test/web/app.tsx` `noteRows` hoist stopgap can be reverted to idiomatic
> `async render()` + inline `.map`. See CHANGELOG [6.1.15].

> **FILE INTO:** `cyrius/docs/development/issues/` — written from the yeo-cy-test
> probe session (hands-off on the cyrius repo). Reproduced on the installed
> toolchain via `cyrius build --target=js`; node-confirmed.

- **Severity:** HIGH for the TS/TSX→JS emitter — it produces **syntactically invalid JS** (`SyntaxError` under `node --check`) for an extremely common shape: an `async` function whose body contains any nested arrow (e.g. `xs.map(x => …)`). Real consumer code (`yeo-cy-test/web/app.tsx`) hit it on the first `.map` inside an `async render()`.
- **Component:** `cycc --emit-js` (surfaced via `cyrius build --target=js <in.tsx> <out.js>`).
- **Toolchain reproduced on:** cycc **6.1.13** and **6.1.14** (still present on 6.1.14).
- **Target:** JS emit only. Native codegen unaffected.

## Symptom

The emitter emits the `async` keyword on the **wrong function node**: it strips
`async` from the owning function declaration and stamps it onto a *nested,
non-async* arrow inside that function. The owning function then contains a bare
`await` (→ `SyntaxError: await is only valid in async functions`), and the inner
arrow becomes spuriously `async`.

A function with no nested arrow (e.g. `async function plain()`) emits correctly,
so the trigger is specifically **an async function enclosing a nested function
expression**. The `async` "migrates" inward to the first nested arrow.

## Minimal reproducer

`repro.tsx`:

```ts
async function outer(): Promise<void> {
  const xs = [1, 2, 3];
  const ys = xs.map((n) => n + 1);
  await Promise.resolve(ys);
}
async function plain(): Promise<number> {
  return await Promise.resolve(1);
}
```

`cyrius build --target=js repro.tsx repro.js` emits:

```js
function outer() {                       // ← async DROPPED from owner
  const xs = [1, 2, 3];
  const ys = xs.map(async (n) => n + 1); // ← async ADDED to nested arrow
  await Promise.resolve(ys);             // ← now a bare await → SyntaxError
}
async function plain() {                 // ← correct (no nested arrow)
  return await Promise.resolve(1);
}
```

`node --check repro.js` →
`SyntaxError: await is only valid in async functions and the top level bodies of modules`.

The bug count is exactly one displaced keyword: `async` is emitted once, but on
the innermost nested function rather than the declaration that owns the `await`.

## Likely root cause

The emitter appears to carry an "is-async" flag while walking and attaches it at
the wrong scope boundary — it writes `async` when it *enters* a nested function
expression that lexically sits inside an async function, instead of binding the
flag to the `FunctionDeclaration` / `ArrowFunction` node that actually declared
it. Net effect: the flag is shifted from the outer (async) node to the inner
(non-async) node. Functions with no nested function expression never trigger the
misattachment.

## Suggested fix

Bind `async` to the function node it was parsed on (each `FunctionDeclaration` /
`ArrowFunction` / `MethodDefinition` should emit `async` iff *its own*
`isAsync`), rather than tracking a single ambient flag across the walk. A
regression fixture: an `async function` containing `xs.map(x => …)` must emit
`async function` on the outer and a plain arrow on the inner, and pass
`node --check`.

## Consumer-side workaround (in use)

In `yeo-cy-test/web/app.tsx`, the nested `.map` arrow was hoisted out of the
`async render()` into a plain sync helper (`noteRows(notes)`), so neither
function nests an arrow under an async function. The emit is then valid and the
generated `web/app.js` passes `node --check` and runs (verified in a DOM shim:
fetch + JSX→`h` lowering + XSS-safe text-node rendering + form submit). This is
a stopgap; idiomatic `async` + `.map(arrow)` should emit correctly.
