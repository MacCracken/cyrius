# Ecosystem migration — what changes at your cyrius pin bump

For every repo with a `cyrius.cyml`. cyrius does not migrate its consumers: a consumer adopts a release when IT
moves its pin, and this page is what it reads when it does — the changes that reach code built against cyrius, newest
first, from 6.6.0 (the oldest pin in use) to the current release. Each entry names the release that introduced it;
the full record is that release's [CHANGELOG](../../CHANGELOG.md) entry (its *Downstream* section where it has one).

*Consolidated 2026-10-08 from the per-release notes for 6.6.2 (the value-form sweep worklist), 6.6.13 (the f64
builtins census) and 6.6.18 (the sidecar delta) — those three are in [archive/](archive/) with their per-repo
censuses, which are history and are not re-derived. Add a section here when a release changes what consumer code
does or builds; never a per-repo worklist.*

---

## Moving a pin

1. Bump `cyrius` in `cyrius.cyml`. A nested manifest pins independently — bump each one you build.
2. If CI runs `cyrius lib sync`, run it BEFORE `cyrius deps` / `cyrius build` (6.6.17). Then `cyrius deps`
   re-vendors `lib/` — never hand-copy a stdlib file, and never stage anything into `~/.cyrius/deps`.
3. A tracked `cyrius.lock` goes stale the moment the pin moves: regenerate it (`cyrius deps --lock`). From 6.7.6,
   `cyrius deps --locked` checks it without writing.
4. Regenerate every `dist/` bundle — every `[lib.<profile>]`, not only the default
   (`grep -oE '^\[lib\.[a-z0-9_-]+\]' cyrius.cyml`, then `cyrius distlib <profile>` each). If a script of yours owns a
   `.deps` sidecar, let it.
5. Run your CI the way CI runs it, not a hand-picked subset. Before 6.7.6 a `path = "../sibling"` beside `git` / `tag`
   made a local build compile the sibling's working tree while CI compiled the tag; from 6.7.6 a default build always
   builds the tag. ⚠ A vendored `lib/` is often gitignored, so a clean `git status` says nothing about it.
6. Coming from below 6.5.28 with `cyrius fmt --check` in CI: run `cyrius fmt <file>` — continuation indent became
   paren-depth based; the diff is whitespace-only (`git diff -w` must be empty).

---

## 6.7.x — the language minor

### 6.7.13

Break 2, repair 3 — struct values. Each block names its CHANGELOG [6.7.13] bite; the decisions are the user's (2026-10-15,
D1–D45). The changes that went beyond a decision's text are filed for confirmation in 6.7.14
(`docs/development/issues/archived/2026-10-16-6713-behaviour-changes-beyond-the-decisions-text.md`). Decision ids are 6.7.13's
unless a block names another release ("6.7.12's D19").


#### Language — struct values (the structs lane)

The decisions are the user's at the 6.7.13 open (2026-10-15, D1 – D11). "6.7.12's Dn" / "6.7.11's Dn" are those opens'
ids. Each block names its CHANGELOG [6.7.13] bite.

**ST-4 — the `#derive` scanner walks a scalar field's value whole (no decision: the scanner now reads what the pairs form reads)**
- Changes what it computes: `T_from_json_str` on a document whose scalar field (an integer, `f64` / `f32`, `bool`, `Str`
  or `cstring`) holds an object, an array or a string where a number was expected. The scanner read that value's inner
  keys as the outer struct's — `{"a":{"q":7,"b":9},"b":4}` decoded `b` as 9; it decodes 4 now, as
  `P_from_json(bayan_json_parse(..))` does, and the mismatched field gets what its type can take (0 for an object; a
  `cstring` its text).
- Well-formed documents decode as before. If a caller relied on the old values, it was reading keys from inside another
  field's value; validate the document's shape, or decode it with the pairs form.

**ST-5 — `*(&p)` / `*&p` of an inline struct is the struct `p` names (no decision: 6.7.10's decision 6, a dereference is a struct value)**
- Changes what it computes: with `p` an inline struct (a local, a by-value parameter, a value global, a closure's
  captured copy), `l = *(&p)`, `G = *(&p)`, `o.s = *(&p)` and `*(&p) = v` copy the WHOLE struct — through 6.7.12 one word
  (with a 16-byte `P`, `l = *(&s)` left `l`'s second field as it was). `*(&p) + a` calls `S_add` where it added to p's
  first word (and is refused when there is no `S_add`). `take(*(&p))` / `var q: S = *(&p);` over 8 B now work (they
  faulted). An untyped `var w = *(&p);` is unchanged.
- Stops compiling: `*(&u)` with `u` of ANOTHER struct type where an S is taken — `take8(*(&u))`, `var s: S = *(&u);`,
  `l = *(&u)`, `o.s = *(&u)`, `*(&l) = u` — now refused with the existing another-struct message (`cannot pass 'u' to a
  parameter of a different struct type in a call to 'take8'`). They compiled and moved U's bytes or first word. Pass or
  copy a value of the right type.
- Starts working: `return *(&s)` / `return *(&s) + q` in a fn returning a struct over 8 B (refused through 6.7.12).
- Unchanged: `&h` of a handle or a `*T` is its slot, so `*(&h)` is still the slot's word; `&x + n` is still a byte
  pointer; `*(&s) OP= v` still operates on s's first word (filed, 6.7.14).

**ST-6 — a struct dereference as an if-expression branch is a struct value; over 8 B refused (D1 (a), the user 2026-10-15)**
- Stops compiling: `var v: S = if (c) { *p } else { *q };` (or `{ *p } else { s }`, `{ (*p) }`, `{ *gp() }`,
  `{ *(&t) }`) with S over 8 bytes — "an if expression branch cannot be a struct value over 8 bytes: struct 'S' - branch
  on a pointer (`&x`, or a `*T` value)", at each branch. It compiled and crashed. Branch on the pointers and copy:
  `var v: S = if (c) { p } else { q };`.
- Stops compiling: two dereferences of DIFFERENT small structs as branches (`if (c) { *pu } else { *ps }`), as
  `{ u } else { s }` already was. Pick one struct type.
- Changes what it computes: an untyped `var x = if (c) { *p } else { *q };` of a struct of 8 bytes or less is now the
  struct S (it was the integer word): `x.f` works, and `x + 1` dispatches `S_add` (or is refused when there is none) —
  write `x.f + 1`, or annotate `: i64` to keep the word.
- Starts working (no change needed): of 8 bytes or less, `var v: S = if (c) { *p } else { *q };` copies (it crashed:
  SIGSEGV on x86_64 / aarch64, exit 5 on Windows), and `{ *p } else { s }` compiles (refused as two kinds).

**ST-7 — a whole dereference of a `*S` as a tuple literal element is refused (D2 (a), the user 2026-10-15)**
- Stops compiling: a tuple element `*ps` with `ps` a `*S` — `(*ps, *pw)`, `((*ps), 1)`, `(*gp(), 1)`, `(1, *w.p)`,
  `(*(&s), 1)`, at top level and as a tuple argument — now "a tuple element is i64, f64 or bool, not struct 'P8'", once
  per element, as `(s, w)` already was. It compiled and stored the struct's first word. Write the field you meant,
  `(ps.a, ..)`, or the pointer, `(ps, ..)`.

**ST-10 — `return &s;` in a fn declared `: S` returns the struct (D4 (a), the user 2026-10-15)**
- Changes what it computes: `return &s;` (or `return (&s);`, `&G` of a value global, `&p` of a by-value parameter) in a fn
  returning a struct of 8 bytes or less now returns the struct `s` is. Through 6.7.12 it returned s's ADDRESS as the
  struct's word — for a local, a dead frame's — so the caller's fields read the address's bytes. Code that read that
  word back as an address read a dead frame; return the struct (as now) or declare the fn `: *S` and return a pointer
  to storage that outlives it.
- Stops compiling: `return &u;` with `u` of ANOTHER struct type at 8 bytes or less — "a fn returning the struct `S` takes
  a value of that struct, or a pointer to one — got `&u` (a `*U`)". It compiled and returned u's address. Return a value
  of the fn's struct.
- `return &w.s;` (the address of a field) is refused at every size — "the address of a field is not taken - write
  `&x + offset` or reach it through a `*T`" (it never compiled; over 8 B the message was another).
- Starts working: `return &s;` over 8 bytes (refused through 6.7.12 in other words).
- Unchanged: `return &h;` of a handle, a `*S` local or an untyped `self` still returns the slot's address as the word at
  8 bytes (filed, 6.7.14, a decision) — write `return h;` (a handle or a `*S` returns its pointee, 6.7.11's D1).

**ST-11 — a top-level scalar global from a 9-16 B struct call is refused (no new decision: 6.7.12's D28, "D24 at every path")**
- Stops compiling: a top-level `var G: <scalar> = f(..);` — `: i64`, `: u8`, `: f64`, `: cstring`, `: bool`, any
  annotation that names no struct — with `f` returning a 9-16 byte struct, directly, in parentheses or through
  `fncallN(&f, ..)` / `callptr(&f, ..)`, in the declaration zone or after the first statement (a redeclared global too):
  "cannot initialise 'G: i64' from 'f', which returns the struct 'P2' - declare 'G: P2' or bind a field". It compiled and
  stored the struct's first field. Make the call inside a fn (a struct result needs a frame) and store the field you
  want, or call a fn that returns that scalar. As in a fn since 6.7.11.
- Unchanged: a struct of 8 bytes or less and a `Str` still give their word; over 16 bytes the one no-frame refusal stays.

**ST-12 — a struct value passed to a pointer of another kind is refused (D5 (a), the user 2026-10-15)**
- Stops compiling: `f(s)` with `s` an inline struct — a local of any size, a by-value parameter, a value global (in a fn
  and at top level), a closure's captured copy, wrapped or not — passed to a `*i64` / `*u8` / `*f64` / `**T` parameter
  (any `*T` whose T is no struct and no vector): "cannot pass 's' to a parameter that is not a pointer to its struct type
  in a call to 'ri' - pass &s for its address". It passed s's first field as the pointer (a fault, or a read through
  whatever that field held). Write `f(&s)`.
- A struct into a `*V` parameter (`p: *f64v2`) is refused too, by the vectors lane's D33, in its own words: "cannot pass
  's' to a parameter that is a pointer to a vector type in a call to 'rd'" (see that block). `rd(&s)` still converts.
- Unchanged: a handle, a `*Pt` and a `Str` pass their word (the address); a `*Pt` parameter still takes `&s` itself; an
  untyped parameter takes the word. Still not refused (filed, 6.7.14): a field, a call result or a dereference
  (`ri(w.s)`, `ri(mk())`, `ri(*pp)`) — pass their address yourself.

**ST-13 — an untyped `var q = G;` in a fn copies the struct global (D6 (b), the user 2026-10-15: the global copies, a handle keeps the word)**
- Changes what it computes: `var q = G;` (or `var q = (G);`) in a fn, with `G` an inline struct global, declares `q` a
  copy of G, as `var q: P = G;` does. Through 6.7.12 `q` was G's first word. An arithmetic operator on `q` (`q + n`,
  `q - n`, …) now dispatches `P_add` / `P_sub` / … and is refused when the struct has none; `take(q)` passes the struct.
  Code that used `var q = G;` to read G's first word as an integer should write `G.x` (or `load64(&G)`).
- Starts working: `q.y` (read and write; G is untouched) and `take(q)` (it faulted).
- Unchanged — still a word: a handle (`var q = h;`, a handle global, a local or captured handle that shadows G) is the
  address, as a `*T` is, so `q.y` on it is still "no struct type in scope for 'q'" (annotate: `var q: P = h;`); every
  top-level `var H = G;`; a bare `q` as a value (`return q;`, `raw(q)`).

**ST-14 — an inline `Str` (`Str { .. }`) is its header's address where a `Str` is taken (D7 (1), the user 2026-10-15)**
- Changes what it computes: with `var t: Str = Str { p, n };` (or an inline `Str` global), `f(t)` into a `s: Str`
  parameter (stdlib ones — `str_len(t)`, `str_eq(h, t)`, `str_builder_add_json_str(sb, t)` — included), `fp(t)` into
  `p: *Str` and `h = t` into a `Str` handle now pass t's header; through 6.7.12 they passed its `data` word as the header
  (the length read from the bytes after the string). `var h: Str = t;` and `var h = t;` now BIND h to t's header — a write
  through h (`h.len = 3`) changes t — where they copied it. If a copy is wanted, copy the fields
  (`var h: Str = Str { t.data, t.len };`) or build a handle (`str_new(t.data, t.len)`).
- Stops compiling: `return t;` from a fn returning `Str`, and `G = t` (a `Str` global), `w.s = t` (a `Str` field),
  `W { t, .. }` (a literal's `Str` field) and `*ps = t` (through a `*Str`) with a frame's inline `Str` — "cannot return
  the inline Str 't' from a fn returning Str - its header lives in this frame and would dangle (return a handle:
  str_new(data, len))" / "cannot store the inline Str 't' into a global / into a field / through a pointer - …". They
  returned or stored the data word. Build the `Str` with `str_new(p, n)`. A global's inline `Str` and a closure's
  captured copy are never refused.
- Unchanged: a `var t: Str;` declared with no initialiser — its bare name, and a copy of it, is still its first word, so
  6.6.16's pun `var t: Str; t = a; str_len(t)` reads a's string as before (except that `h = t` into an inline `Str`
  declared from a literal copies t's half-written header, which `str_len(h)` now reads — an open question, 6.7.14).
  Positions that take no `Str` by their type (an untyped parameter such as `Str_eq`'s `other`, `fncallN(&f, t)`, a `*Str`
  local, `vec_push(v, t)`, a tuple element, an if-expression branch) still take the data word — pass `&t` there (filed,
  6.7.14). A handle bound to t (`var h: Str = t; return h;`) is not refused when it escapes the frame (filed, 6.7.14):
  never return or store a handle to a frame's inline `Str`.

**ST-16 — a bare `Vec` field whose own `struct Vec` is declared below it is refused (D10 (b), the user 2026-10-15)**
- Stops compiling: a file that declares its own `struct Vec` (or `union Vec`) BELOW a struct, union or generic struct
  with a bare `Vec` field — "struct field type 'Vec' is declared after its use; declare it before 'Ray'", one error per
  field. Through 6.7.12 that field was silently lib's 8-byte handle (the same text with `struct Vec` above gave another
  layout). Move the declaration above the field — the field then becomes that struct, a LAYOUT change (sizeof, offsets
  and the return class with it) — or write `Vec<T>` for lib's 8-byte handle.
- `cyrius header` refuses such a field by name instead of sizing it 8.
- Unchanged: declared above, the field is that struct; with no `Vec` of the file's own (an `enum Vec` included), the
  handle.

**ST-19 — `*pp` of a `pp: **T` is a `*T` (D9 (a), the user 2026-10-15)**
- Changes what it computes: with a `**T` / `***T` local, parameter, global, field, closure capture or `: **T` return,
  `*pp + n`, `*pp - n` and `*pp += n` now step `n * sizeof(T)` bytes (through 6.7.12 `n` bytes), and `*pp - *qq` is an
  element count. For a byte step, copy it untyped first: `var a = *pp; a + n`.
- Changes what it computes: `**pp`, `**pp = v` and `**pp OP= v` through `**u8` .. `**u32`, `**i8` .. `**i32` or `**f32`
  read and write the element at its width (sign- / zero-extended; an f32 in single precision); through 6.7.12 they read
  and wrote 8 bytes. For the word, write `load64(*pp)` / `store64(*pp, v)`.
- Stops compiling: `*pp - q` with `q` a pointer of another element size — a `*u8`, or `&x` (a byte pointer) —
  "pointer difference of pointers with different element sizes; for a byte count subtract plain addresses
  (`var a = p;`)". Subtract untyped copies for a byte count.
- A warning goes away: `var q: *T = *pp;` / `q = *pp;` no longer warn "assigning non-pointer to typed pointer".
- A program may name at most 126 distinct pointee types of a pointer to a pointer ("too many pointer-to-pointer pointee
  types (max 126)").
- Still not supported: a declaration-zone `var G: **T` (filed, 6.7.14 — declare it after the first statement);
  `**pp` through a `**S` as a struct value in a declaration (`var t: P = **pp;`: filed, 6.7.14).

Nothing to migrate (a wrong value, a fault or a compiler crash becomes the right answer, or refused code compiles):
ST-1 (a small struct's word has padding 0 — only bytes past `sizeof(S)` change, which held frame garbage), ST-2 (a
zero-size struct moves no byte: no neighbour clobbered, no read past a mapping), ST-3 (a 3 / 5 / 6 / 7 B field value is
read byte-exact: its padding 0), ST-8 (`&x.f` never compiled; only its message changes — D3 (b), the user 2026-10-15),
ST-15 (`gp().n = v` / `OP= v` through a `: *T` call now stores — D8 (a); nothing that compiled changes), ST-17
(`struct Vec { v: Vec; }` is refused where the compiler crashed), ST-18 (D4's untyped store through a `*S` keeps its
reading — D11 (a)).

#### Language — multi-value returns (the multi-value lane)

The decisions are the user's at the 6.7.13 open (2026-10-15, D19 – D28). "6.7.11's Dn" is the 6.7.11 open's id
(2026-10-13). Each block names its CHANGELOG [6.7.13] bite. Every refusal below is a frontend diagnostic, the same on
x86_64, aarch64, cx, PE and Mach-O.

**MV-1 — an undeclared multi-value call into a tuple parameter is refused (no decision: it crashed)**
- **Stops compiling:** `take(mku(..))` or `take(b.mku(..))`, where `take` has a tuple parameter (`fn take(t: (i64,
  i64))`) and `mku` is undeclared with every `return` `(a, b)` (counted by pass 1). The error is "a multi-value call
  'mku' is not a tuple argument - bind it first: `var t: (i64, i64) = mku(..);`, then pass `t`", as for a callee
  declared `: (i64, i64)`.
- It passed the first value as the tuple's address and crashed: SIGSEGV on x86_64 and aarch64, a cx guest error, exit
  5 on Windows.
- **Migrate:** `var t: (i64, i64) = mku(..); take(t);`. A callee whose returns mix arities is still not judged.

**MV-2 — an inherited `: stack` pair default above its trait / impl is a pair (no decision; 6.7.11's D23 rule)**
- **Stops compiling:** `var v = p.m(..);` where `m` is a `: stack` pair-returning method that the impl INHERITS from
  its trait's default body (`impl Tr for P { }`), and the trait / impl sit below the call. The error is "a `: stack`
  enum returns two values — bind both". It bound the TAG and dropped the payload. Write `var t, v = p.m(..);`.
- **Starts working (no change needed):** `p.m(..)?` there propagates. It crashed (SIGSEGV / cx guest error / exit 5).
  The workaround, keeping the trait and impl above every caller, still works.

**MV-3 — an inline-replayed pair generic no longer makes its caller a pair fn (no decision: false refusals lifted)**
- **Starts working (no change needed):** take a fn that calls a one-statement `: stack` pair generic, such as `fn
  main(): i64 { var t, v = gg<i64>(7); return v; }`.
  - Its callers' `var x = main();` is no longer refused "bind both".
  - Its `return v;` no longer warns "returns a `: stack` pair on another path but a SINGLE value here".
- **Stops compiling:** a DESTRUCTURE of such a caller, `var a, b = main();`. It bound `b` to a stale second register.
  It is now "multi-value destructure binds 2 names, but 'main' returns 1 value". Bind one name: `var x = main();`.

**MV-4 — the same for a replayed `?` (no decision: false refusals lifted)**
- **Starts working (no change needed):** a fn whose replayed one-statement generic uses `?` (`fn gq<T>(v: T) { return
  SOk(inner(v)? + 1); }`, called `var t, x = gq<i64>(v);`) is no longer a pair fn to its callers. `var y = mid(3);`
  compiles, and the false mixed-return warning is gone.
- **Stops compiling:** a destructure of such a caller, `var a, b = mid(3);`. It bound a stale second register. It is
  now "multi-value destructure binds 2 names, but 'mid' returns 1 value". Bind one name.

**MV-8 — parentheses around a whole `: stack` pair call are transparent (D19, the user 2026-10-15)**
- **Stops compiling,** "a `: stack` enum returns two values — bind both", as the unwrapped spelling is: every one-slot
  store of a parenthesised pair call. These kept the tag and dropped the payload (an `Err`'s code) in silence:
  - `var v = (f(7));`, `x = (f(7));`, `h.a = (f(7));`, `a[0] = (f(7));`, `x += (f(7));`, `*p = (f(7));`;
  - `store64(&s, (f(7)))`;
  - `P { (f(7)), 3 }` (positional, named or a nested leaf);
  - a global's initializer, in either zone.

  **Migrate:** bind both (`var t, v = f(7);`), or consume the pair with `?` (`var v = (f(7))?;` now works).
- **Stops compiling:** `var v = fw(..);` on a fn whose only spelling of the pair is `return (f(x));`. The forwarder is
  now pair-returning, as `return f(x);` makes it. Write `var t, v = fw(..);`.
- **Starts working (no change needed):** `var v = (f(7))?;` and `fw(..)?` propagate, through a free, generic or
  method call at any depth. They took the boxed `?` and crashed. The mixed-return warning no longer calls `return
  (f(x));` a single value.
- **Unchanged:** `g((f(7)))` into an untyped parameter still receives the tag (6.7.11's D22). An operand that starts
  with a pair call inside a wrap, `var v = (f(7) + 1);`, still keeps the tag (filed, 6.7.14): do not rely on it.
  `var a, b = (f(7));` is still refused "needs a call on the right-hand side" (filed, 6.7.14): drop the parentheses.

**MV-9 — `ret2(a, b)` outside a fn body is refused (D20, the user 2026-10-15)**
- **Stops compiling:** a `ret2(..)` at top level, in a top-level block (`if`, a loop, a `switch` case) or in a
  global's initializer. The error is "ret2 outside a fn body". It returned on no target: x86_64 and Windows ran on
  past it, and aarch64 and cx hung at it.
- **Migrate:** put it in a fn, or end the program with `syscall(60, v);`. A ret2 in a fn, a closure or an `#inline` fn
  is unchanged.

**MV-10 — `ret2(a, b)` in a three-value fn is refused (D21, the user 2026-10-15)**
- **Stops compiling:** `ret2(a, b)` (and `return ret2(..);`) in a fn declared `: (T1, T2, T3)`. The error is "'f'
  returns 3 values - return (a, b, c)". The caller's third value read whatever an earlier call left.
- **Migrate:** `return (a, b, c);`. In a fn declared `: (T1, T2)` ret2 still works.

**MV-11 — `ret2(a, b)` in a fn declared to return a named struct is refused, in every class (D22, the user 2026-10-15)**
- **Stops compiling:** `ret2(a, b);` or `return ret2(..);` in a fn declared `: S`, at any size. The error is "a fn
  returning the struct `S` returns that struct — `ret2` writes two values". It compiled with a different outcome in
  each class:
  - over 16 B the caller's struct was 0, 0, 0 (the hidden result pointer was never written);
  - at 8 B or less the second value was dropped;
  - at 9 – 16 B the two words came back only because that class's registers are the multi-value ones.

  This includes the 9 – 16 B form that returned the right words.
- **Migrate:** build the struct and return it: `var p: S = S { a, b }; return p;`. This is the migration cyrius's own
  tree made: about 13 pinned 9 – 16 B ret2 producers in 2 crossos files and 5 gates now say `return p;`. A fn meant to
  return two values declares `: (i64, i64)` (or nothing) and keeps its ret2. A fn returning a `dyn` keeps its own
  refusal.
- **Starts working (no change needed):** an `#inline` fn whose body is `return ret2(..);`, replayed inside a 9 – 16 B
  struct fn. It was refused "got `this expression`" through 6.7.12, because the replay was judged by the caller's
  class. A closure's ret2 and an `#inline` fn's `ret2(..);` statement inside a struct fn are unchanged.
- **Unchanged, not yet judged:** `ret2(a, b)` in a fn declared to return a vector (`: f64v2`, `f32v4`, `f64v4`) still
  compiles and returns no vector (filed, 6.7.14). Return the vector itself.

**MV-13 — an async fn's `return h(..);` of a multi-value call is refused (D24, the user 2026-10-15)**
- **Stops compiling:** `return h(..);` in an `async fn` not declared with several values, when `h` returns several
  values: declared `: (T1, T2[, T3])`, undeclared with every `return` `(a, b)`, a method or a generic instance,
  wrapped or not. The error, at the call, is "`async fn g` returns 2 values, and a Future carries one i64 - return a
  pointer to a struct holding them". A `: i64`-declared async fn is refused the same way.
- The Future memoised the first value, and `rethi()` after the `await` read whatever the last call left.
- **Migrate:** return a pointer to a struct holding the values: `var p = alloc(16); var a, b = h(); store64(p, a);
  store64(p + 8, b); return p;`. Or bind the values and return the one the awaiter needs. `return callptr(fp, ..);`
  (callee unknown) and a one-value forward are unchanged.

**MV-14 — `return mk(..);` of a multi-value call from a struct fn of 8 B or less is refused (D25, the user 2026-10-15)**
- **Stops compiling:** in a fn declared `: P1` (a struct of 8 bytes or less), `return mk(..);` (also `return
  (mk(..));` or `return b.mk(..);`) where `mk` returns several values: declared, counted by pass 1, a method or a
  generic. The error is "a multi-value call 'mk' is not returned as struct 'P1' - bind it first: `var a, b =
  mk(..);`". It returned the call's first value as the struct's word.
- **Migrate:** bind, build and return: `var a, b = mk(..); var p = P1 { a }; return p;`. The 9 – 16 B and over-16 B
  classes already refused it, with their texts unchanged.

**MV-15 — `*p = mk(..);` of a multi-value call through a `*S` is refused (D26, the user 2026-10-15)**
- **Stops compiling:** `*p = mk(..);` with `p: *S` (any struct size) and `mk` returning several values, in a fn, a
  classic-for step or at top level, through a method or wrapped. The error is "a multi-value call 'mk' is not assigned
  to struct 'S' - bind it first: `var a, b = mk(..);`", as `G = mk(..);` into a struct has been since 6.7.11. It
  stored the first value as the struct's first word and left the rest.
- **Migrate:** `var a, b = mk(..); var t = S { a, b }; *p = t;`. Through a `*i64` the first value is still stored.

**MV-16 — a fn ending in `while (true)` is proved to end in its returns (D27, the user 2026-10-15)**
- **Stops compiling:** `var a, b = one(..);` (or a two-tuple capture) against a ONE-value fn whose body ends in `while
  (true) { .. }` or `do { .. } while (true);` that no `break` leaves. The error is "multi-value destructure binds 2
  names, but 'one' returns 1 value", as with `while (1)` since 6.7.11. It bound a stale register.
- **Migrate:** bind one name. The same proof now counts an undeclared fn whose every `return` is `(a, b)` and that
  ends in such a loop, so binding another count of names to it is refused too.

**MV-17 — off the end of a declared multi-value fn every value is 0 (D28, the user 2026-10-15)**
- **Behaves differently (nothing stops compiling):** a fn declared `: (T1, T2[, T3])` whose body reaches its closing
  `}` without a `return` now returns 0 for every value, as a bool fn returns `false` there. Every `return` is
  untouched. It returned stale registers: the first value was whatever the last expression left, the second and third
  an earlier call's. The rule also covers a method, a generic instance, a defer and an `#inline` replay of such a fn;
  `rethi()` after it reads 0.
- **Migrate:** a caller that relied on the leftover value has the fn return it explicitly (`return (a, b);` on that
  path). A body that returns on every path (if / else, an infinite loop) is unaffected.

**No block — a newly accepted shape, a diagnostic or a kept rule (nothing that compiled changes what it does):**
- **MV-5:** a refused parameter default is one error, at the default. Short calls are no longer refused a second time
  by arity. A call over the maximum names the range ("expects 0 to 3 arguments").
- **MV-6:** `var a, b = callptr(fp, ..);` (also `a, b = ..`, a for step, a top-level zone) now destructures, as
  `fncall1(fp, ..)` does; it was refused "needs a call on the right-hand side". A tuple capture `var t: (i64, i64) =
  callptr(fp, ..);` is still refused (filed, 6.7.14): use `fncall1` there.
- **MV-7:** `const k: i64 = 3;` is one error, at the `:`, and the const is bound, so reads of `k` add no "undefined
  variable". Drop the annotation: a const's type is its value's.
- **MV-12, MV-12r, MV-19:** no behaviour change. The aarch64 struct-pair sync is gone with its last producer, and the
  corpus is byte-identical. The other two are a comment, and a lane-only compile-time regression fixed before merge.
- **MV-18 (D23, the user 2026-10-15: B, kept):** a sync fn declared ONE type that returns several values (`fn g2():
  i64 { return (1, 2); }`, `ret2(1, 2);`) compiles and runs as before. The guide recommends re-declaring it `: (T1,
  T2)`, which names each value's type and checks every return.
  - A `ret2` body is not counted by pass 1 (filed, 6.7.14), so `var a, b, c = g2();` on `fn g2(): i64 { ret2(1, 2); }`
    still binds a stale third value.
  - A tuple parameter does not refuse such a call: `take(g2(3))` still crashes (filed, 6.7.14). Bind it first.

#### Tools and the CLI

Each block names its CHANGELOG [6.7.13] bite (the tools lane, TL-*). D39 and D41 – D43 are the user's decisions at the
6.7.13 open (2026-10-15). "6.7.12's Dn" is an id from the 6.7.12 open.

**TL-2 — the aarch64 Linux CLI refuses `--win`; `--aarch64` and aarch64 bare metal run the host's cycc**
- On an aarch64 Linux host, `cyrius build --win` (and `cyrius run --win`) exits 1 with
  `error: --win is not available from the aarch64 Linux CLI: its cycc emits aarch64 only (build PE images on x86_64 Linux or Windows)`,
  and nothing is written. It used to write an aarch64 ELF named `.exe` at rc 0, never a PE. Build Windows images on an
  x86_64 Linux host or on Windows.
- On that host, `--aarch64`, `--target=aarch64-bare-metal-elf` and `cyrius run` / `test --aarch64` now work. They used
  to fail by name, rc 1, looking for `cycc_aarch64`, an x86_64 binary.
  - `--aarch64` builds what a plain build builds.
  - The bare-metal target writes the aarch64 kernel image.
  - `run` and `test` exec the program directly.

  Nothing to change. A workaround that built these on another host can go.
- ⚠ Not changed yet (filed, 6.7.14):
  - On a macOS host, `cyrius build --win` still writes a Mach-O named `.exe` at rc 0. Do not build Windows images
    there.
  - On a plain build, the aarch64 Linux CLI still resolves `[deps.X] target = "x86_64"` and skips
    `target = "aarch64"`.

**TL-3 — `cyrius build --pie` on macOS (D43)**
- On an Intel Mac, `cyrius build --pie` exits 1:
  `error: --pie is not available from the macOS x86_64 CLI: its cycc writes a fixed-address Mach-O (no MH_PIE mode)`,
  and nothing is written. It used to write the plain build's fixed-address image at rc 0. Drop the flag there; the
  image does not change.
- On Apple Silicon, `--pie` is accepted, unchanged. It builds the image a plain build writes, which is already
  position-independent (MH_PIE).
- Only the flag is refused, not an exported `CYRIUS_PIE=1`. Neither Mac's compiler reads that variable.

**TL-4 — `cyrius header` refuses a SIMD vector parameter**
- `cyrius header` now exits 1 on a public fn that takes a vector by value: `fn pv(v: f64v2)`, or any of the twelve
  vector types, in any parameter position. It prints
  ``error: cyrius header: '<f>' takes '<param>: <type>': a SIMD vector parameter, which no C11 type carries; no prototype written``,
  and the rest of the header still prints. It used to print `cyr_val <name>`, which a C caller passes in the wrong
  register.
  - To migrate, make the fn private (`_`-named), or take a pointer instead (`p: *f64v2`, which stays `cyr_val`).
  - A build step `cyrius header f.cyr > f.h` under `set -e` now fails on such a file.
  - In this tree, only lib/simd.cyr has such fns, and it already exited 1 because of its vector returns.
- ⚠ A parameter list wrapped over several lines is still read from its first line only (filed, 6.7.14). A vector
  parameter on a continuation line is not refused, and the prototype drops the continuation parameters. Keep a public
  signature on one line, or check its header by hand.

**TL-5 — `cyrius header` refuses a pair propagated by `?` under a word signature**
- Take a public fn whose signature says a word: no annotation, or a word type such as `: i64`. If its body applies `?`
  to a call of a pair-returning fn (`var v = parse(x)?;`), `cyrius header` now exits 1:
  ``error: cyrius header: '<f>' returns a `: stack` enum's (tag, payload) pair through '<callee>(..)?', which its signature does not declare (its `?` returns the Err pair, in rax:rdx, aarch64 x0:x2); declare it `: Result`, `: Option` or `: Tagged`; no prototype written``.
  It used to print `cyr_val f(..)`. On the `?` path a C caller then read only the Err tag.
  - To migrate, declare the fn `: Result`, `: Option` or `: Tagged`, or make it private.
  - A closure's `?` and a method call's `?` do not count.
  - Nothing in lib/ meets this.

**TL-9 — `cyrius deps` drops the lock row of a file removed from `lib/`**
- This affects a stdlib-only project whose cyrius.lock lists a file that is no longer in lib/: a leaf dropped from
  `[deps] stdlib` and `rm`'d. The next `cyrius deps` / `cyrius build` re-writes the lock once, without that row. Before,
  the row stayed, and `deps --verify` failed with `cannot hash`. Commit the re-written lock.
- `cyrius deps --verify` now names such a row `FAIL: lib/<f>.cyr (missing from lib/)`.
- The § 6.7.12 advice, `rm lib/<file> && cyrius deps --lock`, still works, and a plain `cyrius deps` now does the same.

**TL-11 — at a moved pin, `deps --lock` and a scoped `lib sync` / `update` are held to 6.7.12's D19 (D42)**
- After you bump `[package].cyrius`, a bare `cyrius deps --lock` exits 1 while any lib/ file differs from the new pin's
  snapshot. It prints `error: cyrius.lock not re-locked: … (a bare re-lock vendors nothing):` and the files, and leaves
  cyrius.lock unchanged. It used to stamp the new pin over the old pin's rows at rc 0.
  - To migrate, run `cyrius deps`, which re-vendors the declared closure and re-locks.
  - In a project that vendors the whole snapshot, run `cyrius lib sync --full` instead.
  - A closure-only project that ran `cyrius deps --lock` after a pin bump now gets rc 1, naming its closure files,
    until it runs `cyrius deps`.
- `cyrius publish` at a moved pin, with such files in lib/, stops at its lock step:
  `error: publish: cyrius.lock could not be written — not tagging`. Run `cyrius deps` or `cyrius lib sync --full`
  first.
- In a project that vendors the whole snapshot, a scoped `cyrius lib sync` (or `cyrius update`) at a moved pin exits 1
  before copying anything, while a file outside the declared `[deps].stdlib` subset differs:
  `error: lib sync: nothing was copied: …`. lib/ and the lock are unchanged.
  - To migrate, run `cyrius lib sync --full` or `cyrius update --full`.
  - `--dry-run` refuses the same way.
  - `--no-lock`, which writes no lock, is not refused.
- Two caveats from § 6.7.12's TL-12 block are gone:
  - A refused `deps` / `build` now writes nothing: lib/ stays at the old pin, and `--verify` stays green (TL-12, D41).
  - `deps --locked` names the same remedy as the refusal (TL-10).

  The recipe is unchanged: in a full-vendored project, run `cyrius lib sync --full` first after a pin bump.

**TL-13 — distlib no longer records a named dep's kept fold as the bundle's need**
- This affects a producer that declares a stdlib leaf L and depends on a named dep whose manifest selects a thin profile
  of L, as a `modules` file or a `modular` sub-module. At its next `cyrius distlib`, the producer gets a smaller
  `dist/<pkg>.deps` and requires block: the leaves recorded for that dep's uses of L, and for what L includes, are gone.
  In the filed case those were `sigil` and `ct`.
- Until the bundle is regenerated, `cyrius distlib --check` reads the committed bundle as stale. Regenerate with
  `cyrius distlib` (every profile) and commit dist/.
- A consumer then gets the dep's needs through the dep's own resolution.

**TL-16 — `cyrius header lib/result.cyr` writes a header again (D37)**
- lib/result.cyr's `ok_via` and `err_via` are now declared `: Result`; under `: i64` they already returned the pair.
  `cyrius header lib/result.cyr` gives rc 0 and prints `cyr_val2 ok_via(..)` and `cyr_val2 err_via(..)` under the
  x86_64 SysV guard. 6.7.12 refused both; 6.7.11 printed `cyr_val`.
  - Callers compile byte-identical, so there is nothing to change.
  - Regenerate any checked-in header generated from lib/result.cyr.
- § 6.7.12's TL-22 line naming lib/result.cyr is history. 6.7.12's D23 reach stays: your own `: i64` fn that returns a
  pair is still refused, so declare it `: Result`.
- The folds' `: i64` wrappers (bayan, mabda, sigil, vani, yukti) stay refused until each fold's own release.

**TL-18 — a signalled `cyrius` dies by the signal again (D39)**
- A `cyrius` run stopped by SIGTERM, SIGINT or SIGHUP still stops its children and removes its scratch and temp dir.
  Then it DIES OF THE SIGNAL (WIFSIGNALED, WTERMSIG N), which is what 6.7.11 and every non-cyrius tool report. 6.7.12
  alone exited 128+N (WIFEXITED).
- A shell's `$?` is unchanged: 143, 130 or 129.
- A program or script that waits on `cyrius` and read 6.7.12's WIFEXITED 128+N now sees a signal death.
  `exec_capture_status` gives st = (128+N, 1) instead of (128+N, 0). Test the signal bit (st[1]), or the wait status's
  WIFSIGNALED, where you tested WIFEXITED.
- bash's rule — "the child died of SIGINT, so stop the script" — fires again for a Ctrl-C'd `cyrius` in a
  non-interactive loop. The `[ $? -eq 130 ]` check that § 6.7.12 suggested still works, and is no longer needed.
- A signal ignored at start (nohup) stays ignored. Windows is unchanged.

No block for the lane's other bites:
- TL-1: on Windows, a drive-rooted, rooted or UNC `[deps.X] path` now resolves; it used to fail by name.
- TL-6, TL-7, TL-8: a killed `capacity`, git query or distlib verify leaves nothing behind, and a child forked just
  before the signal is stopped too.
- TL-10: only the text of `--locked`'s failure changes.
- TL-12: a refused resolve now leaves lib/ unchanged. Its refusal and remedies are unchanged; see TL-11 for the
  § 6.7.12 caveat it removes.
- TL-14: editor diagnostics only. A loose file's sibling `include` resolves. One side effect is filed for 6.7.14: under
  a working-directory project whose pin is not installed, that pin's error now shows.
- TL-15, TL-17, TL-19: D36, D38 and D40 keep 6.7.12's behaviour, and § 6.7.12 stands.
- TL-18r: a gate.

#### Language — receives and closures (the receives lane)

The decisions are the user's at the 6.7.13 open (2026-10-15, D12 – D18 and D35, each as recommended). "6.7.11's Dn" is
the 6.7.11 open's id (2026-10-13) and "6.7.12's Dn" the 6.7.12 open's; 6.7.13's own D24 and D28 are multi-value
decisions, not these. Each block names its CHANGELOG [6.7.13] bite.

**RC-1 — a parenthesised `&f` callee is the known callee (6.7.12's D28, the user 2026-10-15, for the refusal)**
- Stops compiling: inside a fn, `var n: <scalar> = fncallN((&f), ..);` / `= callptr((&f), ..);` — the callee `&f`
  inside parentheses, `f` returning a struct over 8 bytes (not `Str`), `<scalar>` any annotation that names no struct —
  is "cannot initialise 'n: i64' from 'f', which returns the struct 'P3' - declare 'n: P3' or bind a field", as the
  unwrapped `fncall1(&f, ..)` has been since 6.7.12. It compiled and faulted (exit 139 on x86_64). Declare the struct
  (`var p: P3 = fncall1((&mk3), 5);`) and read its field, or write `fncall1(&mk3, 5).a` (RC-9).
- Stops compiling: at top level, `var G: <scalar> = fncallN((&f), ..);` (it read the struct's first field) and
  `var G: <struct over 8 B> = fncallN((&f), ..);` (it faulted) are refused as the unwrapped `&f` is — the scalar with
  the words above, the struct "'f' returns a struct by value, and a struct result needs storage in a fn's frame — call
  it inside a fn". Move the call into a fn.
- Starts working (no change needed): inside a fn, a wrapped `&f` callee's struct or vector result reaches a
  declaration, an assignment, a field store, a by-value / `*T` / `*V` argument, `return`, an untyped receive and a
  value-form vector local, as the unwrapped spelling does. Through 6.7.12 these faulted (139 on x86_64 / aarch64, a cx
  guest error, exit 5 on Windows) or were refused; the 6.7.12 workaround — write `&f` unwrapped — still works.
- Unchanged: a callee held in a variable, wrapped or not (`callptr((fp), 5)`), is one word; an 8 B result is its word.

**RC-2 — `var x = (mk1());` binds an 8 B struct, a wrapped `: f64` call an f64 (no new decision: 6.7.10's decision 12 / 6.7.11's D42)**
- Changes what compiles: `var x = (mk1());` (also `((mk1()))`, a generic `(mkg(..))`) in a fn, with `mk1` returning a
  struct of 8 bytes or less, now declares `x` of that struct, as `var x = mk1();` does. Through 6.7.12 `x` was an
  untyped word. An arithmetic operator on `x` (`x + 1`, `x * 2`, …) now dispatches the struct's operator fn (`P1_add`,
  `P1_mul`, …) and is refused when there is none (the "undefined function 'P1_add'" warning, then "refusing to emit
  binary with 1 reachable undefined function(s)"); it computed on the word (`x + 1` was 34 for a 33). Write the field
  (`x.a + 1`), or annotate `: i64` to keep the word (`var x: i64 = (mk1());`).
- Changes what it computes: `var x = (f());` with `f` declared `: f64` is now an f64, as `var x = f();` is: `x + 1.5`
  adds floats (it added the bit patterns, with a kind-2 warning), and `x + 1` is a kind-1 f64 add with its warning.
- Starts working: `x.a` on such a binding (it was "no struct type in scope for 'x'").
- Unchanged — still the word: `return x;` from an `i64` fn, `x == 33`. Over 8 B the wrapped receive is 6.7.11's; a
  wrapped dyn call stays refused (`var x = (pass(o));`). Not yet (filed): a wrapped `: Str` call (`var s = (mks());`)
  is still an untyped word — drop the parentheses; `var a = (f()) * 2.0;` is still untyped — drop the parentheses.

**RC-4 — a comparison, `&&` / `||` and `& | ^ % << >> >>>` give an integer whatever their right operand (D12 (a), the user 2026-10-15)**
- Changes what it computes: with an integer left operand and an `f64` / `f32` right operand, a comparison, an `&&` /
  `||` link and `& | ^ % << >> >>>` now give an integer. `(n < x) * 3` is 3 (it was 0, the next operator taking the f64
  arm, with a false kind-1 warning); `(n & x) * 3` multiplies integers. An expression like `(n & x) + 1.0`,
  `(n % x) * 2.0` or `(n < x) + 0.5` is now an integer operation followed by a kind-2 mix (and its warning), where it was
  an f64 operation on the integer result's bits. Write the float side explicitly (`f64_from(n % k) * 2.0`).
- Unchanged: `+ - * /` keep an f64 right operand's type (kind 2); an f64 LEFT operand behaves as before.

**RC-5 — `var c = f() < 1.0;` with a `: f64` leading call binds an integer (no decision needed)**
- Changes what it computes: an untyped `var c = f() <cmp> ..;` (`<`, `==`, `<=`, `>=`, `f() > 0.1 && k == 1`) with `f`
  declared `: f64` now binds the integer 0 / 1, not an f64: `-c` is -1 for true (it flipped the sign bit:
  0x8000000000000001), and `0 - c` no longer warns. Code that used c's f64 type was reading a 0 / 1 as float bits.
- Unchanged: `var x = f() * 2.0;` and `var x = f();` are f64s.

**RC-6 — a method or operator result over 8 B into an annotation that names no struct is refused (D13 (A), the user 2026-10-15)**
- Stops compiling: `var x: <scalar> = s.m(..);` or `var x: <scalar> = a + b;` (an overloaded operator fn), with the
  method or the operator fn returning a struct over 8 bytes (not `Str`), `<scalar>` any annotation that names no struct
  (`i64`, `u8`, `f64`, `bool`, `cstring`, an enum, …), direct or in parentheses, through a generic method, in a closure
  or a chain, in a fn or at top level (the declaration zone and after the first statement): "cannot initialise 'x: i64'
  from 'Q_mk', which returns the struct 'Q' - declare 'x: Q' or bind a field" (a method by its compiler name). It kept
  the struct's first word narrowed to the annotation (`var y: u8 = a + c;` held 77 of 333); a `: f64` read the word as
  a float; a `: cstring` or an enum received the struct behind its annotation; a `: bool` was refused as "not a bool".
  Declare the struct (`var x: Q = s.m();`) or bind the field you want (`var x: i64 = s.m().a;`).
- Unchanged: a struct of 8 bytes or less and a `Str` keep their one word; an untyped receive and a struct annotation
  take the struct. Not judged yet (filed): the ASSIGNMENT `x = s.m();` / `x = a + c;` / `x = mkp();` into a scalar
  still stores the first word silently — write the field.

**RC-7 — a by-value struct over 8 B into a pointer annotation is refused in a fn (D14 (A), the user 2026-10-15)**
- Stops compiling: inside a fn, `var p: *T = f(..);` — or `= s.m(..)`, `= a + b`, `= fncall1(&f, ..)`, wrapped or
  generic — with the result a struct over 8 bytes and `*T` any pointer annotation (`*P2`, `*i64`, `*u8`, `*T` in a
  generic fn): "cannot initialise 'p: *P2' from 'mkp', which returns the struct 'P2' - declare 'p: P2' and take `&p`".
  It compiled with only "assigning non-pointer to typed pointer" and held the struct's first field as an address (`p.b`
  faulted: 139 on x86_64 / aarch64, 14 on cx, 5 on Windows). Write `var s: S = f(..);` and use `&s`.
- Unchanged: a struct of 8 bytes or less still stores its word, with the warning; `p = mkp();` into a `*P2` local copies
  through it. Not judged yet (filed): at top level `var P: *P2 = mkp();` after the first statement still compiles under
  the warning and faults — move it into a fn, or declare the struct and take its address.

**RC-11 — the typed-pointer warning at every `*T` site; a literal `0` exempt (D18 (a), the user 2026-10-15)**
- A warning only: nothing stops compiling, and no binary or exit code changes.
- New warnings: "assigning non-pointer to typed pointer" now fires for a declaration-zone `*T` global given a
  non-pointer (`var P: *i64 = SOME_INT;` before the first top-level statement, `= x + 1`, `= 3`) and for an assignment
  of a non-pointer to a `*T` local or a `p: *T` parameter of a scalar `T` (`p = x;`, `p = 3;`, `p = load64(q);`). Give
  the value a pointer type (a `: *T` fn, `&x`), or drop the `*T` annotation if the slot is not a pointer.
- Gone: `var p: *T = 0;`, `p = 0;` and `G = 0;` (the literal `0` alone, a null pointer) no longer warn anywhere. `0 - 0`
  and `(0)` still do.
- ⚠ A string literal into a `*u8` now warns at the new sites too (`t = "xyz";`, the zone `var s: *u8 = "abc";`), as
  the in-fn declaration already did; the code is right (filed as a false positive).

**RC-12 — a closure's capture of a narrow scalar local reads its value (no decision needed)**
- Changes what it computes: a closure that reads a captured `i8` / `i16` / `i32` / `u8` / `u16` / `u32` local now gets
  its value, sign-extended for a signed type: a captured `i8` holding -3 reads -3, not 253 (65533 / 4294967293 at 16 /
  32 bits), and a positive one no longer carries the slot's stale upper bytes (-249 for 7 on aarch64 / cx). Code that
  masked the read (`b & 0xFF`) gets the same result; code that used the raw word was reading garbage on aarch64 / cx.

**RC-13 — in a closure, a `var`'s initializer reads the enclosing name it declares (D35 A, the user 2026-10-15)**
- Changes what it computes: in a closure whose `var x = x ..` (or `var x: T = x ..`, `for (var x = x; ..)`, or a
  destructure's first name `var x, y = f(x);`) shares its name with an enclosing local, the initializer now reads that
  local (and captures it), where it read a same-named GLOBAL: a different value (the filed repro 101 → 6).
- Stops compiling: such a closure in a translation unit without lib/alloc.cyr, which compiled only because the read went
  to the global (or was refused "undefined variable 'x'" without one), is now refused as a capture — 'a capturing
  closure needs include "lib/alloc.cyr" for its heap env'. Include lib/alloc.cyr and call `alloc_init()`, or rename the
  closure's local.

**No block — refused source now compiles, or a message changes (nothing that compiled does anything else):**
- **RC-3:** a 9-16 B method or operator result in parentheses (`HE { 7, (q0.dupe()), 8 }`) and a wrapped struct-typed
  field (`(h.q)`) are nested-literal elements; they were "unexpected '}'". A wrapped struct NAME `(q0)` is still refused
  (filed) — drop the parentheses.
- **RC-8 (D15 (a), the user 2026-10-15):** `var a: dyn Shape = fncall1(&mkd, &q);` (callptr, the callee or the call
  wrapped) forms the dyn, as `mkd(&q)` does; it was refused. A callee held in a variable stays refused.
- **RC-9 (D16 (a), the user 2026-10-15):** `fncall1(&mk3, 5).b`, `callptr(&mk3, 1).dbl().c`, `fncall1(&gp, 5).b = 40;`
  and the statement `fncall1(&mk3, 5).tot();` work, as `mk3(5).b` does; they were "expected ';', got '.'". A variable
  callee's `.b` is now refused by name ("its callee is a value, not `&f`, so the result is a word"). Not yet (filed):
  `callptr(&gp, 5).b = 40;` is "expected ';', got '='" — write `fncall1(&gp, 5).b = 40;`.
- **RC-10 (D17 (a), the user 2026-10-15):** `H { 7, (pass(o)), 8 }` takes the dyn element as the unwrapped call does;
  it was refused twice. `var x = (pass(o));` stays refused.
- **RC-14:** a nested closure literal's parameters are its own — `|n| { var g = |m| m + 1; .. }` beside an enclosing `m`
  builds without lib/alloc.cyr (it was refused), and a closure that captured needlessly builds no heap env (its value is
  a bare fn pointer, dispatched the same way).
- **RC-15:** the captured-name refusal's fix-it reads `` (`var x_l = x;`) ``, where it always named the local `y`. A
  tool that matched the old text must match the new one.

#### Language — vector values (the vectors lane)

The decisions are the user's at the 6.7.13 open (2026-10-15, D29 – D34, each A); "6.7.12's D27" is the 6.7.12 open's
(a vector value into a `*V` parameter is an address; a vector into another pointer kind is refused by name). Each block
names its CHANGELOG [6.7.13] bite.

**VC-2 — a value-form `v: f32v8` parameter is its 32 bytes (no decision: a codegen fix)**
- ABI: a fn with a `v: f32v8` parameter, called from C or through `fncallN`, now takes it as a `v: f64v4` parameter is
  taken — two XMM registers (SysV), two V registers (aarch64), four cx slots, a pointer to a 32-byte copy on Win64 —
  where it took one integer register. A caller outside cyrius's own direct calls passes it that way, or the fn takes
  `p: *f32v8` (a pointer, one word) instead. No in-tree user: lib/simd.cyr's f32v8 wrappers are `_ptr` forms.
- Stops compiling, every target: an argument to a `v: f32v8` parameter that is not an f32v8 — a scalar or a literal
  (`lanes8(5)`), an f64v4 local ("value-form SIMD arg type mismatch (callee expects f32v8)"), `&e` (off Windows). Through
  6.7.12 each compiled — the parameter was one integer word — and the callee read past it (exit 0 for the measured
  repros on x86_64). Pass an f32v8 local or a call declared to return one. On Windows `lanes8(&e)` still compiles and now
  reads the vector (it read 0).
- Stops compiling, Windows only (the other targets already refused it): an f64v2 / f32v4 / integer-vector / f32v8 local
  passed to a `v: f64v4` parameter. Pass a local of the parameter's type. (A 16-byte value-form parameter is still
  unchecked on Windows — filed, 6.7.14.)
- Stops compiling: `async fn f(v: f32v8)` — as every value-form vector parameter of an async fn already was ("pass a
  pointer to it").
- Stops compiling: a program's own `struct f32v8 { .. }` used as a VALUE parameter type is now the vector type ("SIMD
  vector has no named fields"), as `struct f32v4` / `f64v2` / `f64v4` already were. Rename the struct; `*f32v8` to such
  a struct is unchanged. (Filed as the user's call: such a struct is a struct as a local and the vector as a parameter.)

**VC-3 — an explicit-instance vector call is a call by name; a vector annotation is never dropped (no decision: 6.7.11's D32, a call declared to return the vector)**
- Stops compiling (each compiled to a dropped type or a wrong value), with `fn mkg<T>(a: T, b: T): f64v2`:
  `var v: f64v4 = mkg<i64>(..)` and `var x: i64 = mkg<i64>(..)` ("vector return type does not match the declared
  type"); `x = mkg<i64>(..)` into a scalar or another vector's local (".. the assigned variable"); `var v: f64v2 =
  idg<i64>(5)` with a generic returning a scalar ("a value-form vector local is initialised only from .."). Each is what
  the same source with a non-generic call already met. Declare the local with the type the generic returns, or bind a
  scalar from it explicitly (`load64(&v)`).
- Behaves differently: an unannotated `var v = mkg<i64>(..)` is now an `f64v2` local; it was one word (the declaration
  dropped the type), so `v + 1` read 1 on x86_64 where it now reads lane 0 + 1. A program that used `v` as a word now
  uses a vector local's value / operator rules — write `load64(&v)` for the first lane's bits.
- Starts working (no change needed): the declaration and the assignment receive the whole vector (`load64(&v + 8)`
  read 0 on x86_64 / aarch64, 154 on cx, 195 on Windows), `return mkg<i64>(a, b)` from a `: f64v2` fn, and
  `rd(mkg<i64>(42, 7))` into a `p: *f64v2` parameter (it faulted).

**VC-4 — a vector method result, an untyped `var v = callptr(&f, ..)` and `return callptr(&f, ..)` are the vector (D29, the user 2026-10-15)**
- Behaves differently: an unannotated `var v = callptr(&f, ..);` / `var v = fncallN(&f, ..);` — the whole
  initialiser, the callee written `&f`, `f` declared to return a vector — is now that vector's local, as `var v =
  f(..);` is. It was one word: on x86_64 and aarch64 the integer return register (0 in the measured repro), on cx and
  Windows lane 0. A program that used `v` as a word (`v + 1`, `v == 0`, `raw(v)` into an untyped parameter) now uses a
  vector local: `raw(v)` passes lane 0's bits (41 where it passed 0 on x86_64), `v + 1` is lane 0 + 1, and `lanes(v)`
  into a value-form parameter now compiles (it was refused on x86_64 / aarch64 / cx and faulted on Windows). If the word
  was meant, declare it: `var w: i64 = load64(&v);`. Through a callee held in a variable (`callptr(fp, ..)`) the
  declaration stays one word.
- Starts compiling (was refused by name): a vector METHOD result into a vector local (`var v: f64v2 = s.mv();`,
  `v = s.mv();` — on Windows the local's address is the method's hidden result pointer); `return callptr(&f, ..)` /
  `return fncallN(&f, ..)` from a vector fn. A method declared to return another vector is refused as a by-name call is.
- Not covered yet (filed, 6.7.14): an unannotated `var v = s.mv();` still binds one word (wrong lanes,
  silently), `var x: i64 = s.mv()` compiles, `return s.mv();` is refused — annotate a method receive (`var v: f64v2 =
  s.mv();`).

**VC-6 — a vector call result into a value-form vector parameter is passed; Windows refuses a word there (D30, the user 2026-10-15)**
- Stops compiling, Windows only (x86_64 / aarch64 / cx already refused each): a word passed to a value-form vector
  parameter (`fn lanes(x: f64v2)`). A scalar local or a literal (`var x = 5; lanes(x)`, `lanes(5)`) faulted there. A
  pointer word holding a vector's address — `var pv: *f64v2 = &w; lanes(pv)`, `var p = &w; lanes(p)`,
  `lanes(load64(&pv))` — RAN there (42 under wine on the 6.7.13 lane base): Win64 passes the parameter by address, so
  the callee copied the vector the word pointed at. Pass the vector local, `lanes(w)`, which every target accepts; `&w`
  is still accepted on Windows only (filed: the user's call which way).
- Stops compiling, Windows only: a closure's captured vector passed to a value-form parameter, `var c = |k| lanes(b) +
  k;` — it ran there (42), and x86_64 / aarch64 / cx refused it. Copy the capture into a local inside the closure first
  (`var c = |k| { var w: f64v2 = b; return lanes(w) + k; };`). (Whether a capture should be accepted as the local is
  filed for the user.)
- Message change, x86_64 / aarch64 / cx: a value-form argument that is no local and no vector call is now refused on one
  line — "a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a
  method, or fncallN / callptr with the callee written `&f`) - got `5`" — where "value-form SIMD arg: IDENT not found as
  a local" / "must be a local IDENT (..)" and a cascaded "expected ';'" stood. A tool matching the old text re-matches.
- Starts compiling: a vector call result into a value-form parameter — `lanes(mkv(4, 2))`, `f64v2_add(a, mkv(3, 4))`,
  `lanes(s.mv())`, `mkg<i64>(..)`, `fncallN(&f, ..)` / `callptr(&f, ..)`; the workaround (bind it to a local first)
  still works. ⚠ On x86_64, with a callee the compiler replays inline (a small fn, or `#inline`) taking one vector,
  `lanes(callptr(&f, ..))` / `lanes(fncallN(&f, ..))` reads a wrong first lane (found after the lane; see CHANGELOG
  VC-6) — bind the call to a local first there.
- Unchanged on Windows (filed): `lanes(&w)`, a parenthesised argument `lanes((v))`, a struct local `lanes(p)` and an
  identifier-led expression `lanes(q + 1)` still compile there (the last reads garbage), and `lanes(*pb)` compiles and
  faults — the other targets refuse each.

**VC-7 — a vector call result or `*pv` into another pointer kind, and a vector into a by-value struct parameter, are refused (D31, the user 2026-10-15)**
- Stops compiling (each faulted or read a wrong value): a vector call result — by name, a method, an explicit instance,
  `callptr(&f, ..)` — or a `*pv` dereference passed to a `*S` / `*i64` / `*u8` / `**T` parameter: "cannot pass 'mkv' to
  a parameter that is not a pointer to its vector type in a call to 'rp'" (naming the callee, or `*pb`). Pass a pointer
  of the right type (`&b`, `pv`) if the callee really reads the vector's bytes through it, or give the parameter the
  vector's own pointer type (`p: *f64v2`).
- Stops compiling: a vector local, call result or `*pv` passed to a by-value struct parameter of any size ("cannot pass
  'b' to a by-value struct parameter in a call to 'bv' - a vector is not a struct") — `Str` too, when lib/str.cyr's
  `struct Str` is in scope. On Windows `bv(b)` with `p: Pt` (16 B) passed `&b` by accident and RAN; it stops there too.
  Copy the lanes into a struct and pass that.
- Not covered yet (filed): a `*V` dereference spelled other than `*name` — `ri(**ppb)`, `ri(*gp(pb))`, `ri(*h.pv)`,
  `ri(*GPV)`, `ri(*(pb + 0))`, `ri(*&b)` — into `*i64` / `*u8` / `**T` still compiles and faults.

**VC-8 — a closure's captured vector meets the vector local's argument rules (D32, the user 2026-10-15)**
- Stops compiling (each ran: the capture's address was passed unchecked, 42 on every target): inside a closure, a
  captured vector passed to a pointer of another kind (`*S`, `*i64`, `*u8`, `**T`) — "cannot pass 'b' to a parameter
  that is not a pointer to its vector type in a call to 'ri' - pass &b for its address" — to a `*V` of another vector
  type (A2's words), or to a by-value struct parameter (D31's words). Pass `&b` (a plain pointer converts freely), or
  copy the lanes. A captured vector into a `*V` of its own type is unchanged: it passes the captured copy's address.

**VC-9 — a struct value into a `*V` parameter is refused (D33, the user 2026-10-15)**
- Stops compiling (each ran, reading the struct's bytes as the vector): a struct value passed to a `*f64v2` / `*f32v4` /
  .. parameter — a local, a call or method result, `*ps`, a global, a closure's capture, parenthesised or not — "cannot
  pass 's' to a parameter that is a pointer to a vector type in a call to 'rd'". Pass `&s` (or a `*S`), the explicit view
  of its bytes. A struct FIELD (`rd(w.s)`) is still accepted silently (filed).

**VC-11 — a dereference through `&` or `**` is the value it names (no decision: the source names the value; `**pps` follows D9 (a))**
- Stops compiling (each faulted): `take(**ppq)` of a `**Q3` into a `*P3` parameter ("cannot pass 'ppq' to a parameter of
  a different struct type in a call to 'take'"); `rd(*&f)` of another vector type into a `*V` (A2's words); `rp(*&b)` of a
  vector into a pointer of another kind (D31's words). Pass a pointer of the parameter's type.
- Starts working (each faulted): `rd(*&b)` / `rd(*(&b))` into a `*V` pass `&b`; `take(**pps)` into a `*S` passes `*pps`;
  `take(**pp)` into a by-value struct over 8 B passes the struct. `&b` itself is still a byte pointer (`&b + 8` is
  lane 1).

**No block** — newly compiling shapes, a crash fixed into the right answer, or a message on code that never compiled:
- **VC-5:** `rd(s.mv(42, 7))` into a `*V` parameter passes a temporary's address (it faulted).
- **VC-10 (D34, the user 2026-10-15):** `var v: V = *p;` / `v = *p;` with `p: *V` compile and copy the vector (refused
  since 6.7.11). Message change: a `*q` of another vector type into a vector local now reads "cannot copy 'q' into a
  variable of a different struct/vector type: 'v'" (was the receive refusal "got `*q`"). Not covered yet (filed):
  `return *p;` from a vector fn is refused, and an unannotated `var v = *p;` binds one word silently — annotate it.
- **VC-12:** the vector local's refusal text — its accepted list gains "or a dereference of a pointer to its type
  (`*p`)", and the out-pointer tail appears only for a callee held in a variable (`callptr(fp, ..)`); a tool matching the
  whole 6.7.11 / 6.7.12 line re-matches. A call to a missing fn (`var v: f64v2 = f64v2_splat(1.0);` without the include)
  is reported by the undefined-function diagnostic again, and under `--allow-undef` builds and traps at the call (132), as
  through 6.7.10.
- **VC-1, VC-6r, VC-5r, VC-6r2:** a gate floor, a one-line refusal on Windows inside this release, a comment, docs.

#### The standard library — Windows `xflock` (the stdlib lane)

**LIB-1 — Windows `xflock`: a re-lock to the mode the handle holds keeps the lock**
- Windows only. `xflock(fd, LOCK_SH)` / `xflock(fd, LOCK_EX)` (with or without `LOCK_NB`) on a handle that already holds
  that mode now returns 0 and keeps the lock, as `flock(2)` does. Under 6.7.12 the lock was dropped and re-taken, so a
  handle waiting for it could get in between (patra lost a second handle's acknowledged writes that way), and a re-lock
  with `LOCK_NB` could fail -11 and leave the handle holding nothing.
- Unchanged: a mode change (SH ↔ EX) still drops the old lock first, then takes the new one — flock's conversion, not
  atomic (a waiter may get in, and `LOCK_NB` may then fail -11). `LOCK_UN` of a lock not held is still 0; the other
  results are 6.7.12's.
- A held lock now also locks one byte beside the sentinel (2^63 − 1): byte 2^63 − 2 while the handle holds `LOCK_EX`,
  byte 2^63 − 3 while it holds `LOCK_SH` — never the file's data. A lock taken by a 6.7.12-built process still excludes
  on the shared sentinel.
- **Migrate:**
  - Code that follows flock's contract needs no change; patra needs none (it relied on that contract all along).
  - Code that re-locked to let a waiter through (flock never allowed that) must `LOCK_UN` first.

No block for LIB-1r (a gate script).

#### Folds — patra 1.16.3, bayan 1.9.0, sandhi 1.13.1

Each fold is byte-identical to its tag; its own CHANGELOG is the full record.

**bayan 1.6.0 → 1.9.0 — csv, json, yaml and cyml answers change (bayan's "What to re-check" notes)**
- **csv (1.7.0).** `bayan_csv_parse_line` returns one more field for a line ending in a comma (`a,` is two fields), no
  longer keeps the line's own CR, LF or CRLF in its last field, and keeps the text after a closing quote in that field
  (`"a"b,c` is `ab`, `c`). `bayan_csv_write_line` ends a record in **CRLF**, not LF, and writes a row of one empty field
  as `""`; `bayan_csv_escape` quotes a field holding a CR. Drop any code that compensated for the old answers (a
  trailing `\n` stripped from the last field, a column re-added). 1.7.1: the csv entry points return 0 on a refused
  allocation — never a short row, a fault or an exit.
- **json (1.7.0).** `bayan_json_build` writes a parsed number, `true`, `false`, `null`, object or array unquoted, as it
  was read, and escapes a hand-built pair's key and value. **A pair is 24 bytes (`JSON_PAIR_SIZE`), up from 16**: code
  that allocated a pair itself, or assumed its size, must change. Pairs read through the accessors are unaffected.
- **yaml (1.8.0).** A quoted value, key or flow element comes back decoded (`"a\nb"` holds a newline, `"C:\\tmp"` one
  backslash): remove any code that decoded bayan's output itself, or it decodes twice. An escape YAML does not define,
  a malformed `\x` / `\u` / `\U`, or a code point past U+10FFFF / a surrogate is now refused; duplicate keys are
  compared decoded.
- **cyml (1.7.0 / 1.8.0).** Markers and `---` delimiters are whole lines wherever they fall (two adjacent `[[entries]]`
  lines are two entries; a `---` beside a marker or after a blank first line is a delimiter; a last line without its
  newline still counts), and a CRLF document parses into its entries (it gave no entries and one block of header text).
- **markdown (1.9.0, new).** `bayan_markdown_*` (CommonMark 0.31.2, GFM by flag) needs `lib/unicode/categories.cyr`
  and `lib/unicode/casefold.cyr` before `lib/bayan.cyr` in a hand-written include list; a program that never calls it
  builds without them (three undefined-function warnings).

**sandhi 1.10.9 → 1.13.1 — no API change for a caller.** A failed serve says why and closes its listen socket; pooled
servers check their workers; a shared client pool owns a mutex (one HTTP/2 connection used by several threads at once
is still not safe — sandhi's roadmap); the client and server transports dispatch through traits internally (the
`SANDHI_CONN_*` record layout is unchanged); pin 6.7.12.

**patra 1.16.2 → 1.16.3 — Windows only.** A contended `xflock` (-11) is read as contended, so a contended `patra_open`
defers to WAL recovery instead of judging the header unlocked. With this release's LIB-1 (a re-taken lock stays held),
a second handle's writes inside a transaction are no longer lost on Windows. Nothing to change in a caller.

### 6.7.18

The full security audit + the refactor / optimization review. Each block names its CHANGELOG [6.7.18] bite; the
decisions are the user's (2026-10-22: D1 — the network parsers read through slices, D2 — the folder layout, and the
audit's four: bayan's refusals, `cyrius deps` over plaintext, pam's `nullok` kept, the `ach` CI job kept) or the lanes'
agent defaults, which the CHANGELOG's head lists for the user's review. No language rule changed: beyond two codegen
fixes (an inline-asm fn's frame, a named argument after `>>>`) and one `CYRIUS_DCE=1` fix, the compiler's own changes
leave every program's bytes as 6.7.17's compiler made them. What a program meets is in the stdlib and the folds; the
folds are the last block.

#### Networking (net, D1)

- **`http_get` / `http_get_r` / `http_get_a` have deadlines (CYRIUS-2026-0049).** Every connect, send and read waits
  at most `HTTP_IDLE_TIMEOUT_MS` (5000) and the whole exchange `HTTP_TIMEOUT_MS` (30000); running out is HTTP_ERROR /
  `Err(HttpNetErr)`, never a truncated response. A fetch from a server slower than that now fails: raise either
  variable before the call, or set it to 0 to turn that bound off.
- **`http_get_r` on a refused allocation** returns `Err(HttpOther)` (it crashed). Nothing to change.
- **A non-digit HTTP status reads 0** (`2x0` read 920, `!!!` -1665). Treat 0 as "no valid status".
- **`ws_server_recv` (CYRIUS-2026-0043)** fails the call on a control frame (PING / PONG / CLOSE) over 125 bytes —
  RFC 6455 §5.5's limit — and returns each data frame in its own allocation (it was one process-global buffer every
  call and thread overwrote). A peer sending longer control frames must send ≤ 125 bytes; a caller no longer has to
  copy a payload out before the next call.
- **`ws_server_handshake` refuses a Sec-WebSocket-Key that is not 22 base64 characters and "=="** (RFC 6455 §4.1; any
  24 bytes passed). A client must send the RFC's key: 16 random bytes, base64.
- **`ws_connect` (finding 19)** reads the 101's whole header block, at most 8 KiB (longer: CLOSED), and keeps the
  frames that arrived with it for the first `ws_recv` (they were dropped). The ws handle is 56 bytes (was 32): take
  it from `ws_connect` / `ws_new`, never size it by a number.
- **`async_resolve` (CYRIUS-2026-0038)** refuses an empty name or one over 253 bytes (-1) before writing anything.
  Nothing to change for a valid DNS name.
- **D1** — the network parsers (async DNS, net.cyr's blocking resolver, the HTTP response parser, both WebSocket frame
  readers, the handshake key) read through slices checked in every build: a read past the peer's bytes, should a
  parser's own checks miss one, stops the program (SIGABRT, exit 134) where it read on. New: `slice_get_be(&s, i, w)`
  in lib/slice.cyr.

#### Local users, the CLI, the release channel (local)

- **`cyrius deps` refuses plaintext dependency URLs (Finding 26, the user's decision):** `git://`, `http://`,
  `ftp://`, a remote helper's `http::`, and a helper's plaintext URL (`https::http://…`), any case, by name (dep,
  owner, URL), before any fetch. Move the dependency's
  `git` URL in `cyrius.cyml` to `https://` or ssh (`git@host:owner/repo`).
- **`cyrius build`'s output temp is `<out>.tmp.<n>`** — n random (62 bits of the OS CSPRNG), created exclusively
  (CYRIUS-2026-0046); it was `<out>.tmp.<pid>`. A script that looked for the pid-named temp matches `.tmp.<digits>`.
- **`file_write_atomic`'s temp is born at the destination's mode** (0644 for a new file; CYRIUS-2026-0047). Nothing
  to change.
- **The Windows CLI** reads no `/proc/self/environ` and, with USERPROFILE and CYRIUS_HOME both unset, refuses by name
  (it used the drive-relative home `/root`; CYRIUS-2026-0048). Set USERPROFILE or CYRIUS_HOME.
- **fdlopen in a secure exec (CYRIUS-2026-0041).** When AT_SECURE is set, the real and effective uid or gid differ,
  or the auxv cannot be read, every fdlopen entry — lib/tls.cyr's libssl backend among them — takes only the
  root-owned, verified `/usr/lib/cyrius/dlopen-helper` and answers -9 without it; `$HOME/.cyrius/dlopen-helper` is
  never run there. `fdlopen_trusted_only(1)` (new) asks for the trusted helper in any process. A setuid program on the
  libssl backend installs the helper at `/usr/lib/cyrius/dlopen-helper`, root-owned.
- **`pam_unix_authenticate` (CYRIUS-2026-0050)** answers PAM_AUTH_FAIL for a password over 512 bytes (all unix_chkpwd
  reads) before anything runs, and a helper that exits unread is an authentication failure, never a SIGPIPE. The
  password is now sent NUL-terminated: a correct password verifies (before, unix_chkpwd read NO password, so it never
  did), and an account with an empty hash no longer accepts ANY password — with `nullok` kept, it still accepts the
  empty one (refusing that is placed at 6.8.0). `PAM_MAX_PASSWORD` (512) tells the bound; writing it changes nothing.
  Re-test a login path that relied on what pam answered before.
- **The release workflow signs in `environment: release` (Finding 22):** release.yml is `contents: read`, and only
  the job holding CYRIUS_RELEASE_SK writes. Releases are signed with the same key and verified as before; a fork that
  runs cyrius's release.yml needs a `release` environment holding that secret.
- **install.sh's header** advertises the README's raw.githubusercontent.com command (Finding 27); the
  `install.cyrius.dev` URL never resolved. Use the README's command.

#### Native TLS (tls, refold)

- **KeyUpdate (Finding 21).** A peer's KeyUpdate whose body is not exactly one byte of 0 or 1 fails the connection
  (`TLS_ERR_BAD_HANDSHAKE`); one that does not end its record, or the 33rd in a row with no application data between,
  fails it with `TLS_ERR_PROTOCOL`. A conforming peer (OpenSSL's, BoringSSL's limit is the same 32) sees no change.
- **`tls_native_close` zeroises every secret the ctx holds (Finding 28)**, after the close_notify: a seal or open on
  the ctx after it is `TLS_ERR_PROTOCOL` (it sealed under the live key), and its key schedule answers no secrets.
  Don't use a ctx after closing it.
- **`TLS_CTX_LEN` 632 → 640** (`TLS_CTX_OFF_KEY_UPDATES` = 632). Size a ctx through `TLS_CTX_LEN`, never a number.
- **CYRIUS-2026-0042 — nameConstraints.** A chain through a CA whose X.509 nameConstraints the leaf (or a lower CA)
  violates is `TLS_ERR_CERT_INVALID`, the trust root's constraints included; a CA constraining a name form cyrius does
  not evaluate (rfc822Name, URI, …) refuses the path; a CA with a CRITICAL nameConstraints now verifies for its
  permitted names (sigil 3.13.13 refused the certificate at parse). An intermediate is checked as a CA — its
  commonName is never read as a host name; the leaf's is. A CA that does not allow the path below it is skipped while
  the path is built, so a chain through an unconstrained twin still verifies; a path over 18 certificates (more than
  16 intermediates, only from a direct API call) is refused; a trailing-dot name is matched with one dot dropped, so
  it is refused where OpenSSL lets it out. Fix: a server whose chain is refused must be issued inside its CA's
  constraints.
- **The TLS 1.2 client keeps the server's intermediates** (up to 16; it kept only the leaf), so a TLS 1.2 server that
  sends its intermediate now verifies — every such verifying connect failed. A malformed entry after the leaf is
  `TLS_ERR_BAD_HANDSHAKE` (it was ignored). Nothing to change.

#### Thread-local slots (tls-slots)

- **arm64 macOS.** A thread past the 64th live one has its own slots (it shared main's, and every other overflow
  thread's). A slot access from a thread no `thread_create` started is refused by name (exit 70), and `thread_create`
  returns 0 when the thread's registry chunk, control block or slot block cannot be allocated, or `pthread_create`
  fails. Start threads with `thread_create` and check its 0.
- **Linux foreign-TLS mode (`thread_local_use_foreign_tls()`).** The slot array belongs to the thread that declared
  the mode; any other thread's slot access is refused by name (exit 70) — every thread shared the one array. A fork
  child's first thread takes the array over. Touch thread-local state, directly or through a library, only from the
  declaring thread in this mode.
- **Windows.** A thread's first slot writes are no longer lost to another thread's concurrent first access; a failed
  `TlsAlloc` is refused by name. Nothing to change.

#### The libs (libs)

- **`exec_capture_str` returns -1 with nothing run when no pipe can be made** (with no fd free it closed fd 0, read it
  as output, and ran the command uncaptured). Check its -1.
- **fdlopen's loader** gives the helper its path in argv[0] / AT_EXECFN (they read ""). Nothing to change.
- No public symbol's signature, semantics or presence changed in the 13 audited libs (net, http, ws, ws_server, async,
  fs, io, process, thread_local, fdlopen, tls, pam, slice); added: `fdlopen_trusted_only`, `slice_get_be`.

#### The compiler (giantfns, optimize)

- **An inline-asm fn returning `: *T`, `: (T1, T2)` or `: Box<T>` keeps the standard frame**, so its `[rbp - 8]` reads
  its argument (each such fn returned 0; a one-name return type was right before). Asm that worked around it reads the
  argument at `[rbp - 8]` again.
- **A named argument after a parameter whose type closes with `>>>`** (`nb3(x, b: 8)` with `a: Box<Box<Box<Pt>>>`)
  compiles; it was refused "'nb3' has no parameter named 'b'".
- **`CYRIUS_DCE=1`** no longer NOP-fills live fns in a program whose reachability took more than 512 rounds (a
  callee-first call chain deeper than that died of SIGILL); such a program's binary changes, every other one's does
  not.
- cybs (the bootstrap compiler) refuses a 17th open loop and a 321st pending `break` by name — they compiled to a wrong
  program. Only code built by cybs meets it.

#### Source layout (moves, splits, splits2, cbtsplit) — for anyone who reads cyrius's `src/` or `cbt/` paths

- `src/frontend/lex.cyr`, `lex_pp.cyr`, `lex_attr.cyr` are `src/frontend/lex/lex.cyr`, `lex/pp/` (directive,
  include, derive, serialize, accessor, macro, pass, preprocess) and `lex/attr.cyr`.
- `src/frontend/parse.cyr` is `src/frontend/parse/parse.cyr`, the entry the forks include, with its body in eleven
  files beside it (`stmt.cyr`, `prog.cyr`, …); `parse_ctrl.cyr` / `parse_cov.cyr` are `parse/ctrl.cyr` /
  `parse/cov.cyr`; `parse_fn.cyr` and `parse_fn_def.cyr` are `parse/fn/` (`def.cyr` the former fn_def);
  `parse_decl.cyr`, `parse_expr.cyr` and `parse_types.cyr` are `parse/decl/`, `parse/expr/` and `parse/types/`.
- `cbt/commands.cyr` is `cbt/commands/` (one file per verb; distlib's stages in `cbt/commands/distlib/`);
  `cbt/deps.cyr` is `cbt/deps/` (one file per stage).
- A tool, script or doc that names one of those paths reads the folder, recursively; a test that compiles a CLI module
  carries `cbt/cyrius.cyr`'s cbt/ include list, in order. The `#derive` field-cap error names `lex/pp/derive.cyr`.
  `lib/` did not move, and no compiled program changes.

#### Folds — sigil 3.13.15, sandhi 1.13.7, bayan 1.11.1

Vendored byte-identical from the user's tags: sigil 3.13.15 (`3c47656`), sandhi 1.13.7 (`6e649a3`), bayan 1.11.1
(`965298d`). A hand-written include list needs `lib/slice.cyr` and `lib/hashseed.cyr` before `lib/bayan.cyr`, and
`lib/slice.cyr` before `lib/sandhi.cyr`; sigil's is unchanged.

- **bayan 1.11.0 → 1.11.1 — new requirements and refusals (the user's decisions).** `lib/bayan.cyr` needs
  `lib/slice.cyr` and `lib/hashseed.cyr` before it in a hand-written include list (its Requires block names them; a
  `[deps] stdlib` / `cyrius deps` build needs nothing) — add both. Refused by name where they were accepted:
  - invalid or non-canonical base64 / base64url (`=` anywhere, `====`, a dangling character, mixed alphabets) — the
    decoders return 0 as before, and the new `bayan_base64_last_error()` says why;
  - a malformed JSON number — a leading zero (`01`), no digits, an out-of-range integer (the streaming parser wrapped
    it) — in the tree and streaming parsers;
  - a duplicate JSON object key, in the tree, flat (returns 0, "duplicate key" in `bayan_json_last_error`) and
    streaming parsers, keys compared decoded (the first one was answered). A `#derive(Deserialize)` `_from_json` of
    such a document gets 0 pairs, so every field takes its default.

  Fix the producer of such data; check `bayan_json_parse`'s 0 and read the last error. PDF: a stream that fails to
  decode is tried once per document; page content handed out is charged to a 512 MiB per-document budget and refused
  by name past it (`bayan_pdf_page_content` too); a refused filter stage names why. `bayan_base64url_encode` returns 0
  on a refused allocation (it wrote through it).
- **sandhi 1.13.6 → 1.13.7.** `lib/sandhi.cyr` needs `lib/slice.cyr` in a hand-written include list (its Requires block
  names it) — add it. An h2 exchange fails on a server's HPACK table-size update above 4096 and on an HPACK string
  holding a NUL (`SANDHI_ERR_PROTOCOL`), on a decoded header list over 65,536 octets (saying why;
  CYRIUS-2026-0044), and on an HPACK integer past 2^32 − 1; an HTTP/1 header field holding a NUL is dropped (it was read
  cut at the NUL), as CR / LF fields were. A conforming server sees no change. The HPACK table record is 40 B (was 32).
- **sigil 3.13.13 → 3.13.15 — crypto lanes.** Lanes are a pool of 64, held only while used, by one thread
  (CYRIUS-2026-0040). `cbank()` takes no lane any more: it answers the lane the thread holds, or 0 — a caller that
  indexed its own top-level array by `cbank()` now shares row 0 across threads: put the array on the fn's frame, or
  hold a lane with the new `crypto_lane_enter()` / `crypto_lane_leave()` (enter answers -1 when all 64 are busy).
  `crypto_bank_set` is a no-op; `crypto_banks_exhausted()` means a lane request was refused, `crypto_banks_claimed()`
  the lanes held now; `crypto_tls_main_init` no longer gives main lane 0. With all 64 busy, a 65th concurrent ECDSA
  verify or on-curve check answers 0 (refused, not queued) — under heavy oversubscription a handshake can fail where,
  on a shared lane, it went through before. A direct call into the P-256 / P-384 EC arithmetic outside any lane scope,
  with no lane free, exits 70: wrap it in `crypto_lane_enter()` / `crypto_lane_leave()`.
- **sigil 3.13.15 — X.509 and Poly1305.** `X509Cert` is 304 B (was 272): size it by `X509_CERT_SIZE`, never a number.
  nameConstraints are parsed critical or not and enforced by `x509_verify_chain` and the link check
  (CYRIUS-2026-0042): a chain whose leaf falls outside a CA's permitted (or inside its excluded) dNSName / iPAddress
  subtrees, or under a constrained form not evaluated, is refused; an intermediate is checked as a CA
  (`x509_name_constraints_check_ca`: every name but its commonName), the leaf as the leaf; a critically-constrained CA
  that failed to parse now parses. A pathLen that is no non-negative 1 – 7-byte INTEGER, and an empty TBS, are
  refused. New: `poly1305_init_into` / `_update_into` / `_finalize_into` over a caller-owned `POLY1305_STATE_SIZE`
  (168) context, `x509_name_constraints_check`, `x509_name_constraints_check_ca`, `x509_cert_has_name_constraints`,
  `x509_nc_subtree_count`, `x509_nc_subtree`, `X509_GN_*`. No symbol removed.

### 6.7.17

Break 2, repair 7 — the cleanup: the 22 issues left open after 6.7.16, and the fold wave. Each block names its
CHANGELOG [6.7.17] bite; the decisions are the user's (2026-10-22: D1 – D91 at the open, D92 – D109 at the finish pass,
all as recommended) or the agent's defaults D110 / D111, which the CHANGELOG's head lists for the user's review (D109's
boundary the user turned at the release: an array of pointers whose element IS the parameter's type still passes
element 0, as through 6.7.16). D39 – D90 keep every change 6.7.16 shipped beyond its decisions'
text, so nothing 6.7.16 changed is restored. Decision ids are 6.7.17's unless a block names another release ("6.7.16's
D72"). Every refusal below is a frontend diagnostic, the same on x86_64, aarch64, cx, PE and Mach-O, unless the block
names a target. The fold wave (bayan 1.11.0, sandhi 1.13.6, sankoch 2.8.9) is the last block.

#### Generic binding (genr)

- **GA2-1 (D1) — a rebound type-parameter name is its own untyped word.** A generic whose closure parameter, `for x in` variable or destructure later
  name shares a name with one of its `T`-typed parameters, and that calls a method or reads a field on that inner name,
  stops compiling: *no struct type in scope for 'x'* at the definition. Before 6.7.17 such a call ran the bound's impl on
  the inner word (`g(7)` returned through `impl Show for i64`) or crashed at a struct `T`; a never-called one compiled.
  Rename the inner name, or read the outer value under another name before the closure.
- **GA3-1 (D2) — a struct field or method result binds `T` to the struct.** A generic called with a struct-typed field or a struct-returning method result
  (`g(w.p)`, `g(o.mk())`, `g(o.w.p)`) now calls the struct's instance instead of the `i64` one: `sizeof(T)`, a `var y: T`,
  a `: T` result and `T` arithmetic follow the struct (`sizeof(T)` 8 -> the struct's size). Calls that were refused for it
  — a generic using `T` as a struct (`v.b`), `p: *T` given a struct field or method result, a `Box<T>` / `**Box<T>`
  carrier given a field or method — now compile. Pointer-shaped method results change instance too (beside D2, the
  same "as a free call does"): through `p: *T` a `: *S` method and a `*S` field after a method (`psz(b.mpp())`,
  `psz(b.mw(&w).q)`), and through `pp: **T` / `ppp: ***T` a `: **S` / `: ***S` method and a `**S` field after a method
  (`ppsz(b.mqq())`, `ppsz(b.mwq().qq)`), call S's instance — `sizeof(T)` 8 -> S's size. To keep the old instance, name
  it: `g<i64>(w.p)`.
- Nothing to migrate for the review's fixes (GA-r): a wrapped argument, a carrier's `T` field and a struct literal
  argument only make refused generics compile or change an error's words.

#### Type-parameter and type-argument lists (genb)

- A declaration's type-parameter list with an entry that is no name — a number, a keyword, a string, `<T<i64>>`, an
  empty entry, a trailing comma `fn f<T,>()` — is refused (D3). Write names only: `<T>`, `<T: Show>`, `<T, U>`.
- A trait member whose bound names an undeclared trait (or a malformed bound) is refused at the member, as the fn's
  spelling always was (D4).
- A type parameter written with a list in any annotation — `u: U<i64>`, `var l: U<i8>`, `*U<..>`, `[U<..>]`,
  `sizeof(U<..>)`, a `: *U<..>` return — is refused (D6); the list never meant anything: drop it (`U`).
- `fn f<T: Show>(y: Show)` (a bound's trait used as a type) is refused "unknown type 'Show'"; under
  CYRIUS_MONOMORPH=0, `fn f<T>>(x)` / `enum E<T>> {` (an extra closer) are refused.
- Under CYRIUS_MONOMORPH=0 an explicit call `g<i32>(3)` keeps failing, with D7's words (no new failure).
- An enum whose type-parameter bound names an undeclared trait (or a malformed bound), `enum E<T: Nope> { A }`, is
  refused as a struct's or a fn's is (D101, finish pass): declare the trait or drop the bound.
- Under CYRIUS_MONOMORPH=0, a list on a name that declares none — `Pt<i64>` with `struct Pt { x; }`, `i64<u8>`,
  `Color<i64>`, `cstring<i64>`, also inside a generic's list (`Box<Pt<i64>>`) — is refused, as the default build has
  refused it since 6.7.15 / 6.7.16 (D102, finish pass): drop the list.
- Nothing to migrate for GB1-6 / GB1-7 / GB1-r: diagnostics on code that never compiled (one line where a cascade was).

#### Fn-pointer and pointer types (genc)

- **GB2-1 (D8).** Newly compiles: `*fn( .. )` locals / globals / fields / slice elements (nothing that
  compiled changes for them). Stops compiling: a generic, async, const or `#naked` fn with a `*fn( .. )` parameter and a
  tuple-typed or dyn-typed local / parameter after it (`fn g<T>(cb: *fn(i64): i64, x: T) { var t: (i64, i64) = ..; }`) —
  the R4 / T11 refusal it escaped; hold the tuple / dyn in a non-generic helper, as without the parameter.
- **GB2-3 (D9).** Stops compiling: a trait member declaring a multi-value return with a fn-pointer element
  (`fn e(self): (*fn(i64): i64, i64);`) — no impl could implement it; return the pointer as an `i64` element.
- Newly compiles: a slice whose pointer element has two or more `*` — `[**T]`, `slice<**T>`, `[**fn( .. )]` (the user's
  D93). Nothing that compiled changes.
- Newly compiles: `sizeof` of a pointer type — `sizeof(*T)`, `sizeof(**T)`, `sizeof(*fn( .. ))` — is 8, in expressions,
  const contexts and `#assert` (the user's D94). Nothing that compiled changes.
- Newly compiles: a slice of `Vec<T>` handles (`[Vec<T>]`, `slice<Vec<T>>`), of pointers to them (`[*Vec<T>]`) and of
  `*u128` (the user's D105). Nothing that compiled changes.
- Stops compiling: a slice annotation whose element's `<..>` is closed by one `>` too many — `[Box<i64>>]`,
  `slice<Box<i64>>>` (and `[Result<..>>]`, behind `*`s too) — "expected ']', got '>>'" / "expected '=', got '>>>'";
  delete the extra `>`.
- Nothing to migrate for GB2-2 / GB2-4 / GB2-5: a false typed-pointer warning gone (`&f`, a closure literal into a
  `*T`), diagnostics on refused source.

#### Struct and pointer shapes (vala)

- **VA1-1 (D10 / D11).** A typed pointer of another struct into a by-value struct parameter, and a typed pointer of
  another depth (including `&h` of a handle into a `*S`) into any struct parameter, stop compiling — pass the struct
  itself, `*pp` / `**pp`, or a pointer of the parameter's own struct and depth.
- **VA1-2 (D12).** `var g: S = pp;` with pp a `**S` stops compiling — write `*pp`.
- **VA1-3 (D13).** `*p = mk()` through an untyped pointer, mk returning a struct over 8 B, stops compiling — store
  through a `*S`, or bind a field (`*p = mk().a`).
- **VA1-4 (D16).** `w.n = mk()` / `a[i] = mk()` / `S { mk(), .. }` with a struct result over 8 B into a word slot
  stop compiling — bind a field (`w.n = mk().a`).
- **VA1-5 (D15).** `x OP= mk()` with a struct result over 8 B stops compiling — combine a field (`x += mk().a`).
- **VA1-5 (D15, in a generic).** A generic doing `y OP= mk()` / `*p OP= mk()` / `p[i] OP= mk()` / `b.v OP= mk()` on a
  T-typed destination, mk returning a struct over 8 B, has no scalar instance — calling it at i64 / i32 stops compiling.
- **VA1-6 (D17).** `var p: *P = s;` (s an inline P) now points at s — it held s's first field before (a crash);
  `var p: *P = u;` with u another struct stops compiling.
- **VA1-7 (D14).** `*ppq = r` / `w.pq = r` with r a struct value now write into the pointee and keep the pointer
  (they rebound it before); to rebind, assign an address (`*ppq = &r`).
- **VA1-9 (D106).** Assigning, declaring or storing a struct value over 8 B into a scalar or pointer slot stops
  compiling — bind a field (`y = q.a`) or take its address (`p = &q`).
- **VA1-10 (D107).** `var u: *S = &h` (h a handle) / `= pp` (a `**S`) / `var pp: **S = u` stop compiling — write `h`,
  `*pp` or `&u`.
- **VA1-10 (D107, the assignment).** `p = &h` (h a handle) / `p = pp` into a `*S` name, and `pp = p` into a `**S` one, stop
  compiling — assign `h`, `*pp` or `&p`.
- **VA1-10 (D107, a `Str` handle).** `var p: *Str = &h` of a `Str` handle stops compiling — write `= h`, or
  `var p: **Str = &h` for the slot (before D107 `p.len()` read the slot as the header: 0 where 3 is right).
- **VA1-11 (D111, agent default).** Passing, returning or testing a whole struct over 8 B where a word is expected (a typed
  integer / float parameter, a builtin's argument, a `: i64` fn's `return`, a condition, an index, a comparison's left
  side) stops compiling — pass a field (`q.a`) or the address (`&q`).

#### `Str` shapes (valb)

- A struct value of another type into a `Str` slot stops compiling: `h = mkq();`, `w.s = q;`, `W { mkq(), 1 }`,
  `*ps = q;`, `return q;` from a fn returning `Str` — and a generic body doing it at its `T = Str` instance. Store a
  `Str`; to keep a pointer pun, store the struct's address (`&q`, a `*T`), which keeps the rebind.
- A nested struct field's literal element `*pq` (pq a `*S`) is the whole struct: `O { *pq, 7, 9 }` with a 16-byte `v`
  (was v.a = *pq's first word, v.b = 7, m = 9) stops compiling (`expected '}'`) — write `O { *pq, 9 }`; a dereference
  of another struct type there stops compiling.
- `O { *p, 1, 2 }` with p a `*Str` stores p in the nested `Str` leaf (was the data word); `*p` into a nested field
  that opens with no `Str` leaf, and `O { *(&t), 1, 2 }`, stop compiling.
- A closure's `*(&t) = v` (t a captured inline `Str`) changes the closure's t.len; `*(&t) += x` there stops compiling.
- A top-level untyped `var bb = <call returning Str>` is a `Str`: `bb.len` compiles, a generic call `gg(bb)` binds
  T = Str, and `bb = mkq();` (a struct of another type) stops compiling.
- `var a = (p.area());` (an f64 method, wrapped) is an f64 — `a + 1.0` is f64 arithmetic now.
- A zone global redeclared (`var g = mkf(1.5); var g = 7;`) takes the last declaration's type.
- `O { a, 1, 2 }` / `O { gt, 1, 2 }` (a `Str` name into a nested `Str` leaf) now compiles; `O { t, 1, 2 }` of a frame's
  inline `Str` changes its refusal to the would-dangle words.
- A multi-value call into any `Str` slot stops compiling (`var h: Str = two();`, `h = two();`, `w.s = two();`,
  `W { two(), 1 }`, `return two();` in a fn returning `Str`, `fs(two())` with `s: Str`) — bind it first
  (`var a, b = two();`) and build the `Str` from the values.

#### Vector values and `: stack` pairs (valc)

- **VC1-1 (D25).** `return (v, k);` with a vector v stops compiling — return `&v` / a `*V`, or its lanes
  (`load64(&v)`, `load64(&v + 8)`) as elements.
- **VC1-2 (D23).** `*pv = v` now writes both lanes (code that relied on a one-word store through a `*V` changes);
  `*pv = 5` / `*pv = load64(..)` / `*pv += x` through a `*V` stop compiling — store through a `*i64` view
  (`store64(pv, x)`) for a word.
- **VC1-3 (D24).** Code that read a vector local's lane 0 by naming it (`take(w)`, `1 + w`, `if (w)`, `var x: i64
  = w;`, `*pv` as a word) stops compiling — read the lane through the address (`load64(&w)`, `load64(&w + 8)`,
  `load64(pv)`). lib/simd.cyr and the corpus are unaffected (byte-identical).
- **VC1-5 (D95).** `var x = w;` of a vector w now copies the vector — x is a vector (16 / 32 bytes), so code that
  used it as a word (`take(x)`, `x + 1`, `if (x)`) stops compiling under D24 (read the lane: `load64(&w)`); a top-level
  `var X = *GP;` of a `*V` stops compiling — copy it inside a fn, or read its lanes (`load64(GP)`, `load64(GP + 8)`).
- **VC1-6 (D103).** An array of vectors read as a word (`take(wa)`, `x = wa`, `1 + wa`, `if (wa)`, `var x: i64 = wa;`,
  a tuple / multi-value element) stops compiling — pass its address (`&wa`) or read a lane (`load64(&wa)`).
- `var a, b, c = f(..);` (or `callptr(&f, ..)`) with f returning a `: stack` enum stops compiling — bind two names.
- `var x = wa;` / top-level `var X = GA;` from an array of vectors stops compiling — take `&wa`.
- An array's name passed to a pointer parameter (`tp(a)`, `o.m(a)`, `fncall1(fp, a)` through `*fn(*i64)`) stops
  compiling — pass `&a` (it passed the first element as the address and faulted). An array whose element IS the
  parameter's pointer type (`var ap: *i64[4]; tp(ap)`) still passes element 0; one of another pointer type or more
  stars (`*Pt[4]` / `**i64[2]` into `*i64`) stops compiling — pass `load64(&pq)` for element 0, or `&pq` for the
  array's address.
- `ts(&pa)` with `pa: *Pt[2]` into a `*Pt` parameter stops compiling (a `**Pt`, as `&hp` of a `*Pt` already was; it read
  element 0's address as the Pt) — pass `pa` for element 0.
- Inside a closure, a captured array's name read as a word is now its first element (it was the copy's address): code
  that passed a captured array by name to an untyped parameter as an address must pass `&a`.
- `var v = callptr(&f, ..);` / `fncallN(&f, ..)` (and `x = ..`, `store64(.., ..)`, a field / element / `*p` store,
  `+=`, a struct-literal element) with f returning a `: stack` enum stops compiling ('bind both'), as `var v = f(..);`
  does — destructure (`var tag, val = callptr(&f, ..);`) or propagate (`callptr(&f, ..)?`). lib/ and the corpus are
  unaffected (byte-identical); only lib/fnptr.cyr spells `fncallN(&`.
- `return f(x)?;` from a fn whose `?` makes it a `: stack` pair now warns "returns a `: stack` pair on another path
  but a SINGLE value here" (VC2-2), as `var v = f(x)?; return v;` did; a caller's `var t, v = g();` read the value as
  the tag. Return the pair on every path.

#### Coroutines (vald)

- **VD1-1 (D27).** A suspending `async fn` (CYRIUS_ASYNC=1, x86 targets) with an `i8` .. `u32`
  parameter now reads that parameter at its width (`y: u8` given 0x1FF is 255, not 511; an `i16` `+= 1` wraps), and a
  narrow local in such a fn, a compile error through 6.7.16, now compiles — as does a typed-pointer local whose
  pointee is a word (`*i64` / `*u64` / `*f64` / `*bool` / an enum's `*E`, or any `**T`), refused through 6.7.16 by
  the same "a sub-word local in an `async fn` is not supported yet".

#### Directives and statements (fea)

- **FA1-1 (D30).** `use` lines that are not `use module.name;` stop compiling (none in this repo's corpus).
- **FA1-3 (D28).** An `#assert` with anything but `;` / a `#` comment after its message on the same line stops
  compiling (none in this repo's corpus; `#derive`'s generated `#assert`s end in `; `).
- **FA1-4 (D29).** An include line with code or a second include after the file name stops compiling; put each on
  its own line (none in this repo's compiled corpus; tests/fixtures/lint_lexical/is_err_clash.cyr is a lint-only
  fixture, never compiled).
- **FA1-7 (D92).** A `#ref` line with code after its file name stops compiling; put the code on its own line (none
  in this repo's corpus).
- **FA1-8 (D100).** A `#ref` line in an included file now declares its keys there — a file that also declares one
  of those names (or carried the line as a stale comment naming a file that no longer exists) stops compiling:
  "cannot open #ref file", or the name's redeclaration (none in this repo's corpus; the one `#ref "` line in the tree,
  tests/tcyr/crossos/pp_directive_inside_multiline_string.tcyr:63, is string data and stays so).
- **FA2-1 (D32).** A statement that is only a value builtin — or headed by one (`load8(p) + 1;`) — stops compiling:
  `load8` `load16` `load32` `load64`; `f64_add` `f64_sub` `f64_mul` `f64_div` `f64_from` `f64_to` `f64_eq` `f64_lt`
  `f64_gt` `f64_le` `f64_ge` `f64_neg` `f64_abs` `f64_sqrt` `f64_floor` `f64_ceil` `f64_round` `f64_trunc` `f64_sin`
  `f64_cos` `f64_exp` `f64_ln` `f64_log2` `f64_exp2` `f64_atan`; `f32_from` `f32_to`; `bitget` `bitset` `bitclr`;
  `rethi`; `f64v_dot` `f32v_dot` `f32v8_dot` `f64v256_dot` `iv_dp8`. Use the value (`var v = load8(p);`) or drop the
  line. In this repo: benches/bench_float.bcyr and two .tcyr files, adjusted.
- Newly compiles, nothing that compiled changes: a file-level `private` line after the first top-level statement
  (FA1-6, D31). Nothing to migrate for FA1-2 / FA1-5 / FA2-2 (diagnostics on refused source).

#### Inner declarations and never-parsed bodies (feg)

- **FA3-1 (D33).** Code that compiled now stops compiling — a `struct` / `enum` / `union` / `trait` / `impl` /
  `mod` / `use` / `pub` declaration inside a trait default method that no impl inherits (or every impl overrides), or
  inside a bounded generic fn or method that is never called. Move the declaration to the declaration section (top
  level, before the first statement).
- **FA3-4 (v6.5.17's rule, D110).** Code that compiled now stops compiling — a syntax error, or a name defined nowhere, inside a trait
  default no impl inherits (or every impl overrides) or a generic fn / method no call instantiates. Fix the body.
- Nothing to migrate for FA3-2 / FA3-3 (only refused source changes; `cyrius lint` accepts valid
  `for y in x.a..10`).

#### Platform (plat)

- **PL1-1 (CYRIUS-2026-0037).** Nothing that compiled changes, and no handshake answer changes. One resource note: a
  1.3 server now takes 8 KB more from its ctx's allocator for a ClientHello listing more than 32 groups (as 6.7.16's
  extension walk does for more than 32 extensions); a server whose per-connection arena cannot spare it answers
  `TLS_ERR_OOM` for such a hello.
- **PL3-1 (D35 / D36).** Windows only: a rename of a directory onto an existing file that answered 0 (and
  replaced the file) now answers -20 and changes nothing; a file onto a directory answers -21 where it answered -13.
- **PL3-2 (D37).** Windows only: code that compared xflock's failure with -1 now reads -9 for a closed or
  negative fd, and a table errno (-13, -22, …) for other failures; contention's -11 is unchanged. Windows only:
  `xflock(h + 1, op)` with a bad op answers -22 again (6.7.16: -9).
- **PL3-3 (D96).** Windows only: a `file_rename` / `sys_rename` to another volume answers -18 (EXDEV)
  where it answered -1 — a copy-and-delete fallback keyed on -18 now runs there; code that compared the failure with -1
  reads -18.
- **PL3-4 (D97).** macOS only (natively and a cx guest on a Mac): `xflock(fd, op)` with an op that is not
  LOCK_SH / LOCK_EX / LOCK_UN (+ LOCK_NB) answers -22 and leaves the lock as it was — 3 (`LOCK_SH | LOCK_EX`) took the
  exclusive lock and answered 0, an op carrying LOCK_UN beside another lock bit unlocked, one with no lock bit answered
  -9; a bad op on a non-descriptor is -22 (it was -9).
- **PL3-4 (D104).** Linux only (x86_64, aarch64, and a cx guest on a Linux host): `xflock(fd, op)` with an
  op carrying `LOCK_MAND` (32), or with bits above 31, answers -22 and leaves the lock as it was — it answered 0 (an op
  with LOCK_MAND locked nothing, whatever the fd; one with high bits acted on its low 32 bits). Valid ops are unchanged.

#### Diagnostics (fed, zr, plst, feb, fec)

- **FD1-1 / FD1-2 / FD1-3 (D34).** Diagnostics' columns moved (no program's meaning changes): "undefined variable 'x'" is now at the name's own column
  (`return zq + 1;` 1:25, was 1:28 — any tool or test pinning `:L:C:` of an undefined name moves to the name), a line
  with a macro call or a `#derive` before the error now reports the source column, and a generic instance is named
  `B<i32>` (was `B$i32`) in every refusal. The LSP publishes the name's position (it reads the column from the message).
- **ZR1-1 — diagnostics in source order.** A tool that reads cycc's stderr sees the diagnostics in source order: a
  refused program's lines (and a valid program's warnings) can come in a different ORDER than 6.7.16 printed them — the
  same lines. `CYRIUS_DIAG_UNBUFFERED=1` restores the old order.
- **PL2-2.** A tool that parsed `cycc --parse-ts`'s stderr sees real line numbers instead of 0.
- Nothing to migrate for FB1 and FC1: a refused program reports fewer, truer errors (a missing `;` no longer takes the
  next statement or the fn's `}` with it; a refused source no longer cascades into its uses); nothing that compiled
  changes.

Nothing to migrate (values fixed or no consumer-visible change): GA1-1 / GA1-2 (a by-value struct argument takes the
copy it needed — a wrong value fixed — and a tail call through a non-writing helper keeps its `jmp`, so deep recursion
runs in constant stack again, as before 6.7.7); PL2-1 / PL2-3 (the compiler's own self-compile advisory, the check
driver's OVMF rows); TO1 (the repo's own developer, fold and release helpers, never shipped in a tarball: in a cyrius
checkout `python3 scripts/…` and `sh scripts/{dev,folds}/…` become `cyrius run programs/{dev,folds,release}/<name>.cyr`
from the checkout root, and `build-cycc-verify.sh --fixpoint|--install` becomes
`cyrius run programs/dev/fixpoint.cyr --fixpoint|--install`).

#### Folds — bayan 1.11.0, sandhi 1.13.6, sankoch 2.8.9

- **bayan 1.9.0 → 1.11.0.** The flat lookups name their key type: `bayan_json_get_by_cstr` / `_by_str`,
  `bayan_toml_get_by_cstr` / `_by_str` and their siblings; the 13 bare names and aliases are deprecated — they answer
  as before and every call warns, and a null pairs or key now returns 0. Move a call to the typed name for its key (a
  C string or a `Str`). A `#derive(Deserialize)` struct needs no change: the expansion now calls
  `bayan_json_get_by_str`, so its deprecation warning is gone. New: `bayan_toml_v_parse` (+ `_a` / `_buf` / `_ctx`)
  parses TOML 1.0.0 strictly into json's value tree. 1.10.0's 99 public constants are `const` and its 32 public
  predicates return `: bool` — no value or answer changed. 27 public fns and 4 constants added, none removed.
- **sandhi 1.13.3 → 1.13.6 — no public verb added or removed.** HTTP/2 flow control (a pooled connection no longer
  stalls after ~64 KiB of responses), request bodies over 16 KB and header blocks over 8 KB on h2, each request's own
  deadlines on h2 (a timeout is SANDHI_ERR_TIMEOUT), an h2 connection dropped from the pool when an exchange fails,
  per-hop credential digests on redirects, the TLS session cache under a mutex. `SANDHI_H2_CONN_STRUCT_SIZE` 88 → 144:
  size an h2 connection record by the constant, never a number. lib/sandhi.cyr's own includes gain lib/freelist.cyr
  (nothing to add to a caller's list).
- **sankoch 2.8.7 → 2.8.9 — no API or output change.** Batch inflate / deflate keep nothing on the global heap per
  call; the pin moves to cyrius 6.7.16.

### 6.7.16

Break 2, repair 6 — what 6.7.15 filed, and what 6.7.16's own lanes found. Each block names its CHANGELOG [6.7.16] bite;
the decisions are the user's (2026-10-19: D1 – D67 at the open; 2026-10-20: D68 – D93 on what waves 1 and 2 found,
D94 / D95 at the p16 / t16 integration, D96 – D105 at the wave-3 integration). D36 – D67 keep the 32 changes 6.7.15
shipped beyond its decisions' text, so nothing 6.7.15 changed is restored. The changes that went beyond a decision's
text are filed for confirmation
(`docs/development/issues/archived/2026-10-21-6716-behaviour-changes-beyond-the-decisions-text.md`). Decision ids are 6.7.16's
unless a block names another release ("6.7.15's D18"). Wave 0's gate work and the ProtectedRoots measurement change
nothing a consumer sees; its fold wave does: patra 1.16.6 refuses a negative BYTES / TEXT length at the write
(`patra_insert_row` / `_or_ignore` / `patra_bind_text` answer PATRA_ERR_PARAM, D34) and reads a stored one as length -1
and PATRA_ERR_PAGE (D35); sigil 3.13.13's `agnosys_run_capture` / `agnosys_run_checked` give a caller started with a std
fd closed its capture (it was Err); yukti 2.3.18 builds from `include "lib/yukti.cyr"` alone. The blocks follow by wave:
the frontend, structs, platform, tools and the stdlib defects (wave 1); the declaration zone and generic signatures
(wave 2); generic binding, receives, and wave 1's platform and tools finds, p16 and t16 (wave 3); the parser finds of
waves 1 – 3, f16 and f16b (the frontend and the generic signatures) and s16 and s16b (structs and the declaration zone),
and the p16 review's Windows finds, pw (wave 4). Where a later block changes what an earlier one describes, the earlier
block names the later change: the zone block's float list and generic operator fn (s16: D86 (a), D85 (a)) and its
startup fault for a source declared below (s16: refused), the receives block's `take(2 +| 1.5)` (f16b: D104, "an
integer"), the generic-binding block's `*Box<Pt>` argument (s16: D97, refused).


#### The frontend — refusals that swallow the next statement, bare declarations, intrinsic statements, refused-declaration stand-downs, separators, typed-pointer warnings (the frontend lane)

The decisions are the user's at the 6.7.16 open (2026-10-19: D11, D12; each answered as recommended). Ids of other
releases are written with their release ("6.7.15's D60", "6.7.13's D18 (a)"). Each block names its CHANGELOG [6.7.16]
bite. Every refusal and warning below is a frontend diagnostic, the same on x86_64, aarch64, cx, PE and Mach-O.

**FE-3 — `mulh64(a, b);` / `sizeof(T);` as a statement is refused by name (D11, the user 2026-10-19)**
- Stops compiling under `--allow-undef`: a statement that is only `mulh64(..)`, or `sizeof(x)` of a variable —
  `mulh64(2, 3);`, `var x = 1; sizeof(x);`, in a fn or at top level. With the flag it compiled as a call to an undefined
  fn named `mulh64` / `sizeof` and the binary died with SIGILL (exit 132) when it reached the line; without the flag it
  was already refused ("undefined function 'mulh64'" + "refusing to emit binary"). Now one error at the name, "the value
  of 'mulh64(..)' is discarded - a statement is an assignment or a call", with or without the flag. Delete the
  statement, or bind the value (`var hi = mulh64(a, b);`, `var n = sizeof(T);`).
- Changed message (refused before and after, with or without the flag): `sizeof(T);` of a type ("undefined variable
  'T'" + the undefined-function lines) and `sizeof(T) + 1;` ("undefined variable 'T'" + "expected ';', got '+'") now
  print D11's one line. A script grepping for the old text reads the new one.
- Unchanged: the value forms (`var hi = mulh64(a, b);`, `return sizeof(T);`); `fncall0` .. `fncall8(..);` stay calls;
  `mulh64(2, 3).n = 5;` keeps "expected ';', got '.'".

**FE-5 — a `*T` global whose T is no struct names no struct at `.field` (no decision asked: the lane's brief judged it
no semantics choice, since the local and parameter forms were already refused; ⚠ see the note)**
- Stops compiling: a `.field` read on a `*T` GLOBAL whose T is not a struct — `var g = 7; var x: *i64 = &g;
  syscall(60, x.a);` compiled (rc 0) and read through the program's FIRST declared struct (it exited 0, not g's 7) — and
  that global's `x.m()` under `--allow-undef` (a call to an undefined `P.m`, SIGILL). Both are now "no struct type in
  scope for 'x'; a '.field' access needs its struct declaration" (`... a method call ...`), as the same lines on a local
  or a parameter always were. Annotate the pointer with its struct (`var x: *P = ..`), or read through it explicitly
  (`load64(x)`, `load32(x)`, ...).
- Changed message (refused before and after): the field store `x.a = 3;` said "unknown field 'a' on struct 'struct'"
  and is now "... a '.field' assignment ..."; `x.m()` without the flag said "undefined function 'P.m'" + "refusing to
  emit binary". A `*Foo` global with Foo refused or unknown is its one error (it added "unknown field 'y' on struct
  'var'").
- Unchanged: a `*P` global (P a struct) reads and writes through P.
- ⚠ No 6.7.16 decision names this change. D68 (the user, 2026-10-20) refused the same reader's scalar-global band
  (`var g: i32; g.d`) with these words and cites this bite as its precedent.

**FE-16 — an enum's members are separated by `;` or `,` (D12, the user 2026-10-19; ⚠ the one-member-per-line form goes
beyond the answer's text — D69's reasons, 2026-10-20, restate "a line break is no separator")**
- Stops compiling: an enum whose members are separated only by spaces or line breaks — `enum E { A B }`, `enum E { A =
  1 B = 5 }`, `enum E: stack { Ok(x) Err(e) }`, or one member per line with no `;` / `,` — "expected ';' or ',' between
  enum members" at the second member, once per enum (a second enum reports its own), `--syntax-only` (`cyrius lint`)
  too. It compiled with the values the separated form gives. Add a `,` (or `;`) after each member but the last; the
  values do not change.
- Unchanged: a trailing separator (`enum E { A, B, }`), `;` and `,` mixed in one enum. `enum E { A 5 }` keeps
  "expected identifier, got number 5". cyrlint's own enum walk still tolerates a missing separator, so a refused file
  still gets its lint notes. (In cyrius's tree, the lint fixture's `enum Bare` and
  tests/tcyr/derive/derive_body_shapes.tcyr's newline-separated `ENl` gained their commas.)

Nothing to migrate (diagnostics on code that never compiled, a removed false warning, or gates): FE-1 (a subscript or
`*p` refusal whose statement parses on to its `;` no longer swallows the next statement and its error), FE-2 (a bare
`var c;` / `var c: ;` in a fn or after the first statement no longer reads the next statement as its initializer: no
invented "undefined variable 'd'" / "'c'"), FE-4 (the refused-annotation stand-down no longer silences a same-named
variable in a nested or sibling block: its "no struct type in scope" is reported), FE-6 (a refused annotation over a
tuple literal initializer adds no "a tuple literal cannot initialize 'b' - its declared type is not a tuple"), FE-7 (R9
on a `*T` declaration adds no "assigning non-pointer to typed pointer"), FE-8 (a const subscripted is "cannot subscript
const 'C' - a const has no storage", where it said "expected ';', got '['", "cannot subscript 'C': it is not a typed
array, ...", "expected ';' after a const's value" or a false "undefined variable 'L'"; `a.m<T>(..)` in a const fn is "a
method call is not in a const fn: it calls only const fns", not a field refusal + a false "undefined variable 'i64'"),
FE-9 (a second refused `case` label is its own "unknown name 'ww' in a const context", not "expected ':', got
identifier 'ww'"), FE-10 and FE-13 (a `mod` / `use` / `pub` / `public` in a fn body or block is "a `mod` declaration
belongs to the declaration section at top level, not inside a fn body" — it said "unexpected mod" / "unexpected
pub'/'public", plus a nested-fn error for `pub fn`; a `pub const fn` there, or two declarations on one line, no longer
swallow the next error or the body's `}`), FE-11 (a late `pub var x = 5;` after the first statement still declares x:
no "undefined variable 'x'"), FE-12 (a late or inner refused declaration's names add no error in a const context, a
trait bound, a no-initializer `var q: Q;`, an earlier use or a refused inclusion's `s: *Str` parameter), FE-14 (a gate
comment), FE-15 (a commaless tuple literal `(1, 2 3)` says "expected ',' between tuple literal elements", where since
6.7.15 it said "... struct literal elements"), FE-17 (`(0)` / `((0))` into a `*T` no longer warns "assigning non-pointer
to typed pointer", as `0` never did — 6.7.13's D18 (a); `(0) + 1` and `(1)` still warn; binaries unchanged), FE-18 (a
`: Str` call into a `*Str` declaration — a fn, the zone, after the first statement — or a `*Str` global's assignment no
longer warns, as the `*Str` local never did; any other struct's call keeps the warning; binaries unchanged). A build log
that treats warnings as failures stops seeing the FE-17 / FE-18 warnings; a script that greps a refused program's old
message text reads the new one.

#### Structs — `*pp` and `Str` sources into fields and handles, parenthesised bases, call-result fields, `*(&p) +=` (the structs lane)

The decisions are the user's at the 6.7.16 open (2026-10-19, asked once, "All as recommended"): D19 – D22. Ids from
other releases are written with their release:
- **6.7.15's** (2026-10-18): D14, D16, D19, D21 A.
- **6.7.14's** (2026-10-16): D24 (a), D26 (a).
- **6.7.13's** (2026-10-15): D7 (1), D8 (a), D9 (a), D16.
- **6.7.11's:** the field copy from a `*S` source, D15, D31. **6.7.10's:** decision 6.

Each block names its CHANGELOG [6.7.16] bite.

**ST-1 — `o.s = *pp` into a struct-typed field copies the struct (no decision: 6.7.13's D9 (a) makes `*pp` a `*S`, and a `*S` source copies its pointee into a field, 6.7.11)**
- Changes what it computes: `o.s = *pp` — o.s a struct-typed field of a local, a global, a by-value parameter or a
  struct reached through a `*W`; pp a `**S`; also `*GPP`, `*gpp()`, `*w.pp`, `**ppp`, wrapped, a for step, at top level —
  now copies the whole struct `*pp` points at. It stored that pointer into the field's first word and left the rest
  stale; code that read the field's first word back as an address (`o.s.x` used as a pointer) now reads S's first field.
  To keep a pointer in the struct, give it a `*S` field: `o.ps = *pp` stores the pointer, unchanged.
- Stops compiling: `o.s = *qq` with qq a `**Q` of ANOTHER struct type (in a fn or a top-level `GO.s = (*GQQ)`) — "cannot
  copy '*qq' into a struct field of a different struct type: 's'". It stored the pointer. Copy field by field, or fix
  the types.
- Unchanged: 6.7.15's workaround `var p: *S = *pp; o.s = p;` gives the same result as the direct line now does.

**ST-2 — `t = *pp` from a `**Str` copies the header into an inline `Str` (no decision: 6.7.15's D14 with 6.7.13's D9 (a))**
- Changes what it computes: `t = *pp` — t an inline `Str` (a `Str { .. }` local, a bare `var t: Str;`, an inline
  global); pp a `**Str`, also `*GPPS`, `*gpps()`, `*w.pp`, `**ppp`, wrapped, a for step, at top level — now copies the
  16-byte header. t.data held the header's address and t.len kept its old value; code that read t.data back as a
  pointer to the header now gets the string's data pointer, and t.len is the string's length.
- Unchanged: `q = *pp` into a `*Str` and `h = *pp` into a handle stay the rebind `q = p` is. The declaration
  `var u: Str = *pp;` is not this bite (the s16 lane's, D74).

**ST-3 — `h = *p` into a `Str` handle rebinds h (D20, the user 2026-10-19)**
- Changes what it computes: `h = *p;` — h a `Str` handle local, parameter or global; p any `*Str`-typed operand
  (`*GP`, `*gp()`, `*w.p`, wrapped, a for step, at top level) — makes h the header p points at, the same object:
  `h == p`, and a write through h (`h.len = 2`) is seen through p. h held the string's data pointer, read as a header (a
  wrong length), and the line warned "assigning non-pointer to typed pointer"; the warning is gone. For a copy write
  `h = str_clone(p);`.
- Unchanged: `h = *pp` (pp a `**Str`) was already the rebind. A `Str` FIELD destination `w.s = *p` is not this bite (the
  s16 lane's).

**ST-4 — an inline `Str` into a `*Str` field or through a `**Str` takes its header's address; a frame's is refused (D19, the user 2026-10-19)**
- Changes what it computes: `w.p = gt`, `GW.p = gt`, `pw.p = gt` (p a `*Str` field; gt an inline `Str` GLOBAL) — nested,
  a `: *W` call's field, a for step, at top level — and `*pp = gt` (pp a `**Str`) store gt's header address:
  `str_len(w.p)` is gt's length, and a write through `w.p` writes gt. They stored gt's data word (the string's bytes
  read as a header). A closure's captured copy stores its environment address, as before.
- Stops compiling: the same stores with t an inline `Str` declared in the same fn (`var t: Str = Str { .. };` or a bare
  `var t: Str;`) — into a local struct's `*Str` field (D19's decided shape), a global struct's, through a `*W`: "cannot
  store the inline Str 't' into a field - its header lives in this frame and would dangle (store a handle:
  str_new(data, len))"; through a `**Str` (`*pp = t`): "cannot store the inline Str 't' through a pointer - …". They
  stored t's data word. Store a handle that owns its header (`str_new(t.data, t.len)`, `str_from(..)`), or point at an
  inline `Str` global. (A `Str` field is no way round it: `v.s = t` of a frame's t is refused the same way, 6.7.13's
  D7 (1).)
- Unchanged: a struct LITERAL's `*Str` element (`W { gt, 1 }`) is not this bite (the s16 lane's).

**ST-5 — an untyped declaration from a method declared `: Str` is a `Str` (no decision asked; the overload change is listed among the behaviour changes)**
- Changes what it computes: in a fn, `var k = h.clone();` — any method declared `: Str`, or a chain ending in one
  (`w.s.clone()`, `h.clone().clone()`, `mks().clone()`) — makes k a `Str` handle, as `var k = str_clone(h);` always did.
  A call with a `_str` overload now reaches it: `println(k)` prints the string (it printed the header's bytes as a C
  string), `show(k)` takes `show_str`. Arithmetic and comparison on k (`k + 1`, `k - h`, `k == h`) are unchanged.
- Starts working: `k.len()`, `k.cat(..)` — refused "no struct type in scope for 'k'; a method call needs its struct
  declaration (missing include?)".
- Unchanged: at top level `var K = H.clone();` keeps the word, as `var K = str_clone(H);` does.

**ST-6 — a known `&f` callee's result is typed by its tokens as the direct call's (no decision: 6.7.14's D26 (a), 6.7.13's D16)**
- Changes what it computes: a struct destination fed by `fncallN(&f, ..)` / `callptr(&f, ..)` with f declared `: *T`
  (or `: **T`, dereferenced) — `l = fncall0(&gp);`, `o.s = fncall0(&gp);`, `m = *fncall0(&gp);`, a for step, at top
  level — now COPIES the struct f's pointer points at, as `l = gp();` always did. They stored the pointer word into the
  destination's first field and left the rest stale (`m = *fncall0(&gp)` also warned). `t = fncall0(&mks);` into an
  inline `Str` (mks `: Str`) now copies the whole header (t.len kept its old value). Code that read the first field back
  as an address now reads the struct's first field.
- Starts working: `var t: P2 = *fncall0(&gp);` (t was a handle on the pointee's FIRST FIELD: it faulted, 139 on x86_64
  and aarch64), `take(*fncall0(&gp))` (faulted), `return *fncall0(&gp);` from a `: P2` fn, `(fncall0(&gp)).b`,
  `(*fncall0(&gp)).b` and `(*callptr(&gp)).b` (refused "the value in these parentheses is not a struct").
- Unchanged: a callee held in a variable (`fncall0(fp)`) is a word (6.7.11's D31); `&gp` of a local, capture or global
  named gp is that variable.

**ST-10 — `*(&p) OP= n` on a typed pointer steps elements (no decision: 6.7.15's D21 A, `*(&p)` is p)**
- Changes what it computes: `*(&p) += n` / `-= n` — p a typed pointer (`*i32`, `*i64`, a `*S`, a `**T`) local, parameter
  or global; wrapped `*((&p))` / `*&p`; a for step; at top level — moves p by n elements, as `p += n` does, where it moved
  n bytes. For a byte step use an untyped copy (`var a = p; a = a + n;`).
- Unchanged: a `*u8` steps one byte; a handle's `*(&h) += 1` keeps its word op; `*(&p) = *(&p) + n` steps elements since
  6.7.15.

**ST-11 — `*(&x)` of a narrow integer is x at its width (D21, the user 2026-10-19)**
- Changes what it computes: `*(&x)` with x an `i8` .. `i32` / `u8` .. `u32` local or packed global reads x's width,
  sign- or zero-extended: `*(&a)` of an i32 -1 is -1 (it was 4294967295); `*(&GQ)` of a packed i32 is GQ (it read GQ
  and the next global as one word). `*(&x) = v` / `*(&x) OP= v` write x's width, so the bytes after x — the next packed
  global — are no longer overwritten or carried into. Code that read or wrote 8 bytes that way says so:
  `load64(&x)` / `store64(&x, v)`.
- Unchanged: `*(&x + 0)` and `&x + n` (the byte pointer's word, 6.7.11's D15); in this bite a narrow PARAMETER and a
  closure's capture keep the word, as their own reads do (the parameter's narrowing is the s16 lane's D72), and an `f32`
  / `f64` / `bool` variable keeps it (the s16 lane's D70).

Nothing to migrate in five bites:
- **ST-7** (D22, the user 2026-10-19). `(pn)[0] = 1;` and every subscript store through a parenthesised base stay
  refused, now in the read's words: "a subscript's base is a name, a *T field or a call returning *T - name the pointer
  first (var q: *T = ..; q[i])" (it was "unexpected '('"). Name the pointer first (`var q: *T = ..; q[i] = v;`):
  dropping the parentheses changes the meaning (`*pn[0]` is `*(pn[0])`).
- **ST-8** (D: none). `undefd(); undefd().n += 1;` is "undefined function 'undefd'" (it was "… does not return a
  struct"); refused before and after.
- **ST-9** (D: none). `cyrius lint` (`--syntax-only`) accepts `gp().n = 5;` with `fn gp(): *Foo` defined in the file and
  `Foo` a sibling module's struct; nothing compiles differently.
- **ST-12** (D: none). A refused struct value dereference is quoted as written — '*gps(&s)', '*gu(pu)', '*h.pu', and
  '*qq' where 6.7.15 printed 'qq'. Refused before and after; a script that greps the old text re-matches.
- **ST-13** (D: none). `l = *pq` of another struct is one error, without the "assigning non-pointer to typed pointer"
  beside it.

The review fix ST-12r changes the guide only.

#### Platform — PE std-fd close / ftruncate and pipe seeks, cxvm on macOS and Windows hosts, the native TLS 1.2 server's ClientHello, the Windows CTL's 16-byte entries, qemu-aarch64 without binfmt (the platform lane)

Each block names its CHANGELOG [6.7.16] bite (the platform lane, PL-*). D28 – D32 are the user's decisions at the 6.7.16
open (2026-10-19). "6.7.15's Dn" / "6.7.14's Dn" / "6.7.12's Dn" are ids from those opens. PL-4, PL-5, PL-7 and PL-10
needed no decision: each is fixed to what the source, the `.cyx` ABI (x86_64 Linux's) or the filing's own fix says.

**PL-2 — Windows: `sys_close(0 / 1 / 2)` closes the real std stream, and `sys_ftruncate(0 / 1 / 2, n)` truncates its file (D30; the ftruncate half the defect 6.7.15's PL-8 fixed for the seek)**
- Windows only. `sys_close(0)`, `(1)`, `(2)` (and `file_close` on them) now close the std stream and answer 0. 6.7.15
  answered -9 and left the stream open; 6.7.14 and before answered 0 and left it open.
- After the close, a write, read or seek on that fd answers -9 and a second close -9, as on Linux. Nothing written to
  the fd lands in a file opened afterwards (the std slot is cleared).
- A HANDLE another std slot still holds stays open for that slot: a child started by `run_capture` / `exec_capture` (one
  pipe as its stdout and stderr) that closes fd 2 keeps writing to fd 1.
- `sys_ftruncate(0 / 1 / 2, n)` of a redirected std stream truncates its file (it answered -1).
- **Migrate:**
  - A Windows program that closed stderr or stdout and kept writing to it now gets -9 from those writes, as on Linux:
    stop writing after the close, or do not close the stream.
  - A test of `sys_close(2) < 0` written against 6.7.15's -9 ("the std close is refused, the stream is still there")
    now reads 0, and the stream is gone.
  - Nothing to do for a truncate: a redirected std stream truncates as on Linux.

**PL-3 — Windows: a seek on a pipe or a console answers -29 (`ESPIPE`), as on Linux (D31)**
- Windows only. `xlseek` / `sys_lseek` on a pipe, a socket or a console answers -29. Real Windows answered the asked
  offset without moving the stream (6.7.15), sshd's pipes -22, wine -1.
- A disk file and NUL seek as before (`> nul` keeps Windows' answer; D31 leaves NUL unchanged).
- **Migrate:**
  - `xlseek(0, 0, SEEK_CUR) < 0` now tells a piped or console stdin from a file on every target — the POSIX idiom
    works on Windows.
  - Code that read a successful std-fd seek on Windows as "seekable" (6.7.15 let a pipe seek succeed) must test the
    result with `< 0`.
  - Code that ignored a seek's result on a pipe is unaffected (the stream never moved).

**PL-4 — cx: on a macOS host cxvm answers a failed call with x86_64 Linux's errno (no decision: the `.cyx` ABI)**
- cx only, macOS hosts only. Every host-served answer goes through a Darwin → Linux errno table: ELOOP -40 (was Darwin's
  -62), ENOTEMPTY -39 (-66), ENAMETOOLONG -36 (-63), ENOSYS -38 (-78), EAGAIN -11 (-35), EDEADLK -35 (-11). A
  Darwin-only errno reads as the nearest Linux code (EPROCLIM → EAGAIN, the Sun RPC band → EPROTO, EAUTH / ENEEDAUTH →
  EACCES, EPWROFF / EDEVERR → EIO, EBADEXEC / EBADARCH / EBADMACHO → ENOEXEC, ESHLIBVERS → ELIBBAD, ENOATTR → ENODATA,
  ENOPOLICY → EOPNOTSUPP, EQFULL → ENOBUFS, ENOTCAPABLE → EPERM); one past Darwin's ELAST (107) passes as it is.
- Linux and Windows hosts are unchanged (they already answered Linux's values).
- **Migrate:** a `.cyx` that compared a failure against Darwin's numbers on a Mac's cxvm now sees Linux's — the value
  every other host already gave. Compare against the Linux value: the `.cyx` ABI is x86_64 Linux's, and a per-target
  helper such as a test's `_eloop()` answers Linux's value under `CYRIUS_TARGET_CX`. Run a `.cyx` on its own release's
  cxvm.

**PL-5 — cx: on a macOS host `kill` sends the signal the guest names (no decision: the source names the signal)**
- cx only, macOS hosts only. cxvm maps the guest's x86_64-Linux signal number to Darwin's: `kill(pid, SIGUSR1)` delivers
  SIGUSR1 (it delivered Darwin's SIGBUS, 10), `SIGCHLD` no longer stops the target (17 is Darwin's SIGSTOP), `SIGSTOP`
  stops it (19 is Darwin's SIGCONT), and BUS, USR2, CONT, TSTP, URG, IO and SYS reach their Darwin numbers.
- A Linux signal Darwin lacks — SIGSTKFLT (16), SIGPWR (30), the realtime band 32 – 64 — answers -22 without reaching
  the host. 0, negatives and numbers past 64 go as before.
- Linux and Windows hosts are unchanged.
- **Migrate:** send Linux's signal numbers (the `.cyx` ABI). A `.cyx` that sent Darwin's numbers on purpose (none in the
  tree) now sends other signals. Check the result of a SIGSTKFLT / SIGPWR / realtime send on a Mac: it is -22.

**PL-6 — cx: `fcntl(fd, F_GETFL)` answers x86_64 Linux's word on every host, O_LARGEFILE included (D29)**
- cx only, aarch64 Linux and macOS hosts: F_GETFL now carries O_LARGEFILE (0x8000) for an opened file or device, as
  x86_64 Linux does — never for a pipe or a socket. aarch64 Linux's own O_LARGEFILE (0x20000) reads as 0x8000. On a Mac
  an `open()`ed FIFO reads without it (its st_mode cannot tell it from a pipe; x86_64 Linux sets it).
- The x86_64 Linux and Windows hosts are unchanged.
- **Migrate:** mask the access mode (`flags & 3`) instead of comparing the whole word (`== O_RDWR`) — already needed on
  x86_64 Linux. Test a status flag with `&`, never by equality.

**PL-7 — cx: a guest's getdents64, mknodat, wait4 and sleep run on every POSIX host's cxvm; macOS `sys_mknodat` makes a FIFO (no decision: 6.7.14's D55, one call at a time; with PL-7r)**
- cx: a raw guest getdents64, mknodat, wait4 or `poll(NULL, 0, ms)` answers the host's result on every POSIX host; they
  answered -38 since 6.7.14. So `xgetdents`, `sys_mknodat`, `sys_waitpid` and wait4 work under cxvm on Linux and macOS
  hosts. A Windows host still answers -38 for them (no route), and a poll with pollfds is -38 everywhere.
- cx: `sleep_ms` sleeps — it was a no-op on cx and returned at once.
- cx on a Darwin host:
  - wait4's status word is Linux's (a continued child 0xffff, Linux signal numbers) and WCONTINUED is honoured;
  - a getdents64 count under 64 answers -22 (Darwin's own floor);
  - on a filesystem without extended readdir (devfs: `/dev`), a buffer under 1048 bytes may end the listing early with
    -22 — never with an entry repeated (PL-7r; ecb's 96-byte `/dev` listing ends after 592 of 635).
- macOS (native): `sys_mknodat(AT_FDCWD, path, S_IFIFO | mode, 0)` — or an absolute path under any dirfd — makes a FIFO
  over Darwin's `mknod` (it answered -78). Any other node type, or a relative path under another dirfd, still answers
  -78.
- **Migrate:**
  - A cx program that tested for the -38 from getdents64 / mknodat / wait4 sees the host's answer. Keep handling -38 for
    a `.cyx` that may run on a Windows host.
  - A cx wait loop that calls `sleep_ms` now takes the time it asks.
  - On a Mac's cxvm, list a directory with a buffer of at least 1048 bytes (4096, what most callers pass, is fine); with
    a smaller one a `/dev` listing may end early with -22.
  - macOS: code that fell back to `/usr/bin/mkfifo` when `sys_mknodat` answered -78 keeps working; the fallback is no
    longer taken.
  - Run a `.cyx` on its own release's cxvm: an older cxvm answers these calls -38.

**PL-8 — cx on a Windows host: an exclusive create over an existing directory answers -17 (no decision for it: the `.cyx` ABI; the crossos rows' not-run lines are D28)**
- cx, Windows hosts only: `open(path, O_CREAT | O_EXCL, …)` that CreateFileW refuses with -13 over a name that exists
  (CREATE_NEW over an existing directory, Windows 11) answers -17, as on every other host. So `file_create_exclusive`
  and `file_write_atomic` past a directory planted at a temp name behave as elsewhere.
- The crossos test files print `not run: this host has no <call> route` for a row whose call answers cxvm's -38 on a
  Windows host (D28) — the tests' own change; no program changes with it.
- **Migrate:** a cx program that read -13 from an exclusive create over a directory on a Windows host reads -17: test
  `< 0`, or `== -17` for "exists", as on Linux. A cx program meant for a Windows host handles -38 from readlink,
  getdents64, mknodat, wait4 and fork there (no route), as the crossos rows now do.

**PL-9 — native TLS: the 1.2 server refuses with decode_error a ClientHello whose compression_methods or extension list does not parse (D32)**
- `tls_native_accept_12` (and `tls_native_accept` given a 1.2 hello, which it routes there) refuses with decode_error
  (`TLS_ERR_BAD_HANDSHAKE`, the alert sent) a TLS 1.2 ClientHello with:
  - no compression_methods byte, an empty compression_methods list, or one longer than the message — they negotiated;
  - an extension whose header or length overruns the extension block — it was read as absent, so the handshake went on
    without the extended master secret, without ALPN and on the server's first group.
- A ClientHello too short for its random, session id or cipher_suites was already refused; its decode_error alert is now
  sent (it got none).
- Well-formed hellos — OpenSSL's `s_client -tls1_2`, the native client's — are unaffected.
- **Migrate:** nothing for a program; the fix is on the peer. A test harness that hand-builds a 1.2 ClientHello must
  give it a non-empty compression_methods list inside the message and an extension block whose entries frame it exactly.

**PL-10 — Windows trust store: a 16-byte disallowed-CTL entry is applied under both readings, the public-key MD5 and an MD2 / MD5-signed certificate's signature hash (no decision of its own: 6.7.12's D9 direction, unconfirmed as 6.7.16's D51 keeps the other lengths)**
- Windows only, and latent: a native TLS ctx using the system roots (`tls_native_set_ca_system`) refuses a certificate
  whose MD5 / MD2 signature hash (crypt32's prop 15 of an md5WithRSA / md2WithRSA certificate) a 16-byte disallowed-CTL
  entry lists: path building skips it, and a leaf fails `TLS_ERR_CERT_INVALID`. None is listed today (cass's six MD2 /
  MD5-signed roots are not), so no connect changes now. A 16-byte entry still denies by the public-key MD5, as before.
- A trust policy holding only 16-byte deny keys now also reads each certificate's signature algorithm; a certificate
  whose shape cannot be read there is distrusted, as under any other list (no change on cass, whose CTL also has 48-byte
  entries).
- A ctx given a caller's bundle, and POSIX, are unchanged.
- The underscore-private API, for code that calls the stdlib's private fns (only the tests do):
  - `_tn_tbs_sigalg` answers a digest id: 16 for md5WithRSA and `_TN_DG_MD2` (2) for md2WithRSA, where it answered 0
    (not judged); the SHA ids are their lengths, as before;
  - `_tn_sighash_of(dg, p, n, out)` takes that id (it took a length) and hashes MD5 and MD2 too;
  - `_tn_tbs_sighash` answers 16 for an MD2 / MD5-signed certificate (it answered 0);
  - new: `_tn_md2(p, n, out)` (non-allocating MD2, RFC 1319) and `_tn_dg_len(dg)` (a digest id's hash length).
- **Migrate:** nothing for a caller of the public API. A caller of `_tn_tbs_sigalg` that used its answer as a hash
  length maps it through `_tn_dg_len` (MD2's id is 2, its hash 16 bytes).

No block for PL-1 (the guide's failure-table cell: docs), PL-11 (`docs/development/dev-tools-linux.md`'s qemu binfmt
note and `scripts/dev/xb.sh`'s stderr line: dev tooling), PL-7r (folded into PL-7's block: relative to 6.7.15, where
getdents64 answered -38 on cx, it is part of PL-7's change) or PL-10r (lib-tls-contract.md's row: docs).

#### Tools — the language server (include fragments, macOS), gates under pipefail, the scratch resolve, asm `param_load`, TypeScript paths, cx --syntax-only (the tools lane)

Each block names its CHANGELOG [6.7.16] bite (the tools lane, TL-*). D33 is the user's decision at the 6.7.16 open
(2026-10-19); D84 is the user's at the found issues' round (2026-10-20, the t16 lane); "6.7.14's D16" and "6.7.14's D59"
are the 6.7.14 open's (2026-10-16). The language server's unit model and the `[lsp] skip` key are the fragment issue's
own decision (the user, 2026-10-19), not one of D1 – D105. Everything else is fixed to what the source says. Outside the
blocks below, nothing in this lane changes what a build produces: TL-7 changes only a warning's count, and the gate,
comment and doc bites change nothing a consumer compiles.

**TL-8 — asm `param_load` reads its register by its whole name; any other operand is refused (D33, the user 2026-10-19, extending 6.7.14's D16)**
- Stops compiling, naming the operand, rc 1, nothing written: an `asm { param_load(reg, idx); }` whose register is a
  longer spelling of a register name — x86 `raxx`, `r8d`, `r8w`, `r10d` … `r15d`; aarch64 `x31` … `x39`, `x0abc`,
  `x1y` — with `param_load takes a 64-bit register (rax .. r15), not 'raxx'` / `param_load takes a 64-bit register
  (x0 .. x30), not 'x31'`. Through 6.7.15 each compiled clean and loaded the register its first letters matched:
  `raxx` → rax, `r8d` / `r8w` → a 64-bit r8 load (4c 8b 45 f8), `r10d` → r10, `x31` → x3 (F85F83A3), `x0abc` → x0.
- Changes only the message: a name that matches no register (`eax`, aarch64 `w0`) or a number was already refused, as
  `unexpected identifier 'eax'` / `unexpected number 0`; it now reads `param_load takes a 64-bit register (rax .. r15),
  not 'eax'`.
- Unchanged: whole names keep their bytes — `param_load(rax, 0)` 48 8b 45 f8, `(r12, 1)` 4c 8b 65 f0; aarch64
  `(x0, 0)` F85F83A0, `(x30, 0)` F85F83BE. Every param_load in lib/, programs/, src/, bootstrap/, tests/ and benches/
  names a whole register (lib/simd, atomic and thread and the sigil, bayan and sankoch folds compile unchanged on x86 and
  aarch64).
- **Migrate:** write the register's whole 64-bit name — `raxx` → `rax`, `r8d` / `r8w` → `r8`, `r10d` → `r10` (the load
  was always 64-bit, so the bytes are the same). On aarch64 `x31` … `x39` loaded x3: write `x3` to keep the bytes, or the
  register that was meant. param_load always loads the whole 8-byte parameter slot; narrow it after the load if a narrow
  value is wanted.

**TL-9 — the /proc compilers read the whole command line; one of 2 MiB or more is refused (no decision: a flag or path the command line holds was dropped or cut)**
- Changes what it does: on cycc, cycc_aarch64, the aarch64 native cycc, the Linux-hosted cycc_win and cycc_cx, a flag or
  a `--lex-ts` / `--parse-ts` / `--emit-js` path that sits past byte 255 of the command line takes effect. Through 6.7.15
  it was dropped with no message — `cycc <300-byte arg> --version` compiled its empty stdin and wrote an ELF, rc 0 — and a
  TS path ending past byte 255 was cut and the cut name opened (`error: cannot open '<prefix>'` for a file that exists,
  or another file's TypeScript when the prefix named one). `cyrius build --target=js <deep absolute path> out.js` reaches
  it.
- Stops the compiler, exit 1: a command line of 2,097,152 bytes or more (possible only under a raised `ulimit -s`):
  `error: the command line is longer than 2097151 bytes (/proc/self/cmdline is read whole; a cut copy is never
  scanned)`. Through 6.7.15 such a line was read as its first 255 bytes.
- Unchanged: the macOS compilers and cycc.exe, which already read the whole command line.
- **Migrate:** nothing for a command that meant its flags. A script that put a flag past byte 255 and relied on it being
  ignored now gets that flag; the "keep TS paths short there, or pipe the file on stdin" workaround can go. § 6.7.15's
  PL-13 line "⚠ A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path that … passes the 255-byte `/proc/self/cmdline`
  read is cut … (filed, 6.7.16)" is history.

**TL-10 — `cycc_cx --syntax-only` accepts a call to another file's fn and writes no `.cyx` (no decision: the guide's `--syntax-only` contract)**
- Changes what it does: under `--syntax-only` the cx compiler exits with the parse's status — 0 for a file whose only
  fault is a call to a fn another file defines, with `warning: undefined function 'gp'`, as every native compiler.
  Through 6.7.15 it refused that file (`undefined function(s) called (cx backend):`, one `- gp` line per call site, rc 1).
- Changes what it writes: under the flag no `.cyx` is written. Through 6.7.15 a file that compiled clean under the flag
  still wrote its `.cyx` to stdout (208 B for a two-line program). The `large static data` and capacity advisories are
  still printed.
- ⚠ A divergence the guide names: cx has no reachability data, so under the flag it also accepts a REACHABLE call to an
  undefined fn, which the native compilers refuse.
- Changes only the message: without the flag the refusal stands and names each undefined fn once (it listed one line per
  call site).
- **Migrate:** a script that used `cycc_cx --syntax-only` output as a `.cyx` drops the flag. A check that read cx's
  `--syntax-only` rc as "every called fn is defined" runs the full compile (or the native `cyrius lint`'s rule) instead.
  § 6.7.15's ST-18 line "The cx compiler's `--syntax-only` still refuses it (filed, 6.7.16)" is history.

**TL-11 — the macOS and Windows tarballs ship every `[release] bin`; cyrius-lsp runs on macOS; lib/io.cyr adds `env_block` (6.7.14's D59 applied to those builders — ⚠ beyond its text, which named the aarch64 tarball; the Windows `cyriusly.exe` decided by D84, the user 2026-10-20)**
- Changes what ships: both macOS tarballs gain cyrius-lsp, ark, cyrld, ts_test_runner and cyrsign-efi (16 → 21 and
  15 → 20 bin/ entries), and a macOS install's `bin/cyriusly` is the COMPILED version manager, a Mach-O — the shell
  script is installed beside it at versions/<v>/scripts/cyriusly, as on Linux since 6.7.14. The Windows tarball gains
  ark, cyrld, cyriusly, ts_test_runner and cyrsign-efi `.exe` (11 → 16); `cyriusly.exe`'s install / update / setup /
  uninstall / cmdtools / `use --global` refuse by name there (D84, the t16 lane). cyrius-lsp is not shipped for Windows
  (cycc_win refuses it).
- Changes what it does: cyrius-lsp on macOS finds its compiler — HOME / CYRIUS_HOME through getenv, its own directory
  through argv(0) + fcntl(F_GETPATH), its children's environment from `env_block` — and publishes diagnostics. Through
  6.7.15 it read all three from /proc, logged `cycc not found — diagnostics disabled` and published empty lists. On
  every OS the server now hands its children the whole environment (it cut at 32,767 B).
- Additive: lib/io.cyr's `env_block(lenp)` — the cached environment block getenv reads (NUL-terminated `NAME=value`
  entries; its length stored at `lenp`, which may be 0); 0, storing 0, on Windows and agnos or with no environment. The
  block is shared: read it, never write it.
- **Migrate:** a macOS script that ran `sh bin/cyriusly …` runs `bin/cyriusly …` (the Mach-O), or the shell twin at
  versions/<v>/scripts/cyriusly. A program that forwards its environment to a child builds the child's envp from
  `env_block` instead of reading /proc/self/environ, which macOS lacks. A program that defined its own `env_block` beside
  lib/io.cyr gets the `duplicate fn` warning (its definition still wins): rename it.

**TL-11r — `exec_cmd` hands its child the whole environment (no decision: the fn's own contract, the environment getenv reads)**
- Changes what it computes: on macOS every `exec_cmd` child — and so the compiled cyriusly's install / update / setup /
  cmdtools children — gets the caller's environment. Through 6.7.15 lib/process.cyr read /proc/self/environ, which macOS
  lacks, and every such child started with an EMPTY environment (no PATH, HOME, TMPDIR, `CYRIUS_*`). On Linux an
  environment over 65,535 bytes is no longer cut: every variable past the cut was missing in the child.
- Changes what is included: lib/process.cyr now includes lib/io.cyr on Linux and macOS (Windows and agnos unchanged). A
  program that includes lib/process.cyr without lib/io.cyr and defines a fn with one of io.cyr's names gets `duplicate fn
  '<name>' (last definition wins; first defined in lib/io.cyr)`; its own definition still wins.
- **Migrate:** a program that relied on a macOS `exec_cmd` child starting with no environment passes an exact one through
  `exec_env`. A program whose own fn now collides with an io.cyr name renames it (or keeps the warning: behaviour is
  unchanged).

**TL-13 — `[lsp] skip` is a declared manifest key (the fragment issue's decision, the user 2026-10-19: the `[lsp] skip` key is added)**
- New manifest key: `[lsp] skip = ["path", …]` (paths from the project root) — files cyrius-lsp never compiles. It is a
  declared key (`cyrius help manifest`, `--print-config`'s `lsp.skip`): the tree's CLI no longer warns `cyrius.cyml
  [lsp] is not a known section`; an unknown `[lsp]` key is warned, a value that is not a path or an array of paths is
  refused by name. An installed 6.7.15 CLI still warns `cyrius.cyml [lsp] is not a known section and nothing reads it`
  on every command in a project that has one — harmless.
- **Migrate:** a project whose `.cyr` is not cycc input (generated text, assembly, a fork built only raw by another
  compiler) lists it under `[lsp] skip` — cyrius's own manifest skips bootstrap/cybs.cyr and src/main_aarch64_native.cyr
  (TL-15r2). A project still pinned to a 6.7.15 CLI can add the key and live with the warning, or add it at its bump.

**TL-15 — cyrius-lsp checks each project file through its unit (the fragment issue's decision, the user 2026-10-19: the design's defaults stand)**
- Changes what the server publishes (docs/guides/editor-integration.md, "How a file's unit is chosen"): a file that is
  an `include` of another is checked through the entry that reaches it — the manifest's `[build] entry` first, then the
  fewest include hops, then path order — and its diagnostics are that unit's, read on that file; a file only a Windows /
  agnos / macOS / EFI entry includes is checked under that target's selector (on an x86_64 Linux server); one only an
  aarch64 or cx entry includes gets one Information note, not compiled; a public lib/ module is checked as
  `include "lib/<m>.cyr"` alone (no [deps] prepend), a lib/ peer through its nearest public module; an `[lsp] skip` file
  is never compiled. A clean fragment of a unit with errors elsewhere gets one Information line naming the unit; a
  location-less warning lands on the entry. Through 6.7.15 the open file was always compiled alone, and every name an
  earlier include declares read undefined (55 false errors on cyrius's own src/frontend/parse_ctrl.cyr).
- Changes what reaches a child: an inherited CYRIUS_TARGET_* / CYRIUS_MACHO* no longer reaches the server's project
  checks (each unit names its own target); a loose file's environment is unchanged. A project file now spawns the CLI
  twice (`cyrius build --print-config`, then the check), and a project entry is named relative to the root.
- Unchanged: nothing that compiles; no CLI flag; a loose file (no cyrius.cyml at or above it) is checked as before.
- **Migrate:** nothing to change for a project whose files are cycc input. A project that wants a fragment checked
  through a particular entry names it as `[build] entry` (the manifest's entry outranks every discovered one); an editor
  setup that exported CYRIUS_TARGET_* to steer the server's checks no longer does — the include graph picks each unit's
  target.

No block for the lane's other bites:
- TL-1, TL-2, TL-14: a doc-ledger line, a test header comment and a guide sentence (cyrius-lsp does read `[embed]`
  through its project check).
- TL-3, TL-4, TL-5: gates that now give their verdict under `bash -eo pipefail`.
- TL-6: a killed scratch resolve (`cyrius deps --locked`, a moved pin's dry pass) unlinked a file another same-user process
  had put, inside the CLI's private temp dir, at a temp name one of its copies had already renamed; it leaves it now, and
  a signal that arrives during a copy's commit is delivered right after it (CHANGELOG [6.7.15] IT-12's "Filed from this
  bite (6.7.16)" item is closed).
- TL-7: an aarch64 `#inline` fn's native-region renumber warning prints once per source site, not once per call; nothing
  emitted changes. § 6.7.15's PL-10 line "its warning repeats once per call (filed, 6.7.16)" is history.
- TL-12: a cyrius-lsp started with a std fd closed gives its compiler child an open /dev/null there (it ran the child with
  stdout closed).
- TL-10r, TL-15r, TL-15r2: review fixes inside this release (cx's advisories kept under `--syntax-only`; an x86_64 macOS
  server's own target carries no selector; this repo's `[lsp] skip`).

#### The stdlib defects — lib/regression.cyr's open flags, the capture-fd lift and reaped capture files, cbt/ and programs/ child redirects (the libfix lane)

Each block names its CHANGELOG [6.7.16] bite (the libfix lane, LF-*). No decision covers the lane: each of its four
issues was triaged "none needed", because each bite fixes a `lib/` or tooling defect to what the source, the verb's
documentation or the issue's fix direction says.

**LF-1 — on macOS, lib/regression.cyr's caller-file verbs truncate an existing `out_path` (no decision: a `lib/` defect — the verbs document "capture stdout to file", and their Linux bits always truncated)**
- macOS (arm64 and x86_64) only. `regression_exec_in_dir3`, `regression_exec_in_dir3_env`,
  `regression_pipe_to_bin_capture` and `regression_ssh_remote_exec_capture` open the caller's `out_path` with each
  target's `O_WRONLY | O_CREAT | O_TRUNC`.
- An existing file is truncated before the child writes. Before, it held the child's output followed by its old tail
  past that length: the filed repro read `"hi\ncious\n"` where Linux reads `"hi\n"`. The literal 577 is Linux's
  O_WRONLY | O_CREAT | O_TRUNC, and on Darwin it is O_WRONLY | O_ASYNC | O_CREAT.
- Linux, agnos and Windows are unchanged.
- **Migrate:**
  - Drop a workaround that unlinked `out_path` before the call, or trimmed the stale tail after it. This includes
    6.7.15's advice to pass a fresh path on macOS.
  - Code that relied on the old contents surviving past a shorter output (an accidental append) must keep them itself:
    the verbs overwrite.
  - In your own code, spell open flags with the `O_*` constants (lib/syscalls_*.cyr define each target's bits). Only 0,
    1 and 2, the access mode, mean the same on every target.

**LF-5 — the capture verbs' file has no name while the child runs (no decision: a `lib/` defect — a killed capture left its file for ever; every CYRIUS-2026-0036 guarantee is kept)**
- Linux and macOS. Six verbs: `regression_exec_capture[_status]`, `regression_exec_with_arg_capture[_status]` and
  `regression_exec_with_arg_capture_both[_status]`.
- `<base>/audit_x[ca]_<pid>[.N]` is unlinked right after its exclusive 0600 create. The verb keeps the fd, and its
  child writes through a dup of it. The verb then seeks to 0 and reads the capture back from the fd: nothing reaches
  a capture by name.
- A child or test that opened or stat-ed the name during the run finds nothing. The child's stdout is the same private
  0600 regular file, now unlinked and opened read-write (`O_RDWR`; it was `O_WRONLY`).
- During the call the calling process holds the capture fd, always ≥ 3, until the verb returns. Before, it closed its
  copy right after the fork.
- A capture killed mid-run (SIGKILL, a deadline) leaves nothing behind. Only the open → unlink window remains.
- Unchanged: the capture bytes, the status, the `<base>` rule (an absolute `$TMPDIR`, else `/tmp`), the 64-name walk,
  both refusal lines, and Windows' 0 bytes / status -1.
- The private helpers changed. `_regression_capture_open(prefix, fdp)`, which returned the name and stored the fd, is
  now `_regression_capture_open(prefix)`, which returns the fd or a negative errno. There is a new
  `_regression_capture_read(fd, buf, buflen)`. Neither is in the API surface.
- **Migrate:**
  - A child that inspects its own capture fstats its stdout (fd 1), not the name.
  - Code that cleaned up `audit_x[ca]_*` files after a killed run needs no cleanup for captures made under 6.7.16. Older
    leftovers are never reused (O_EXCL skips a taken name, since 6.7.15): remove them once, or let cyrius's check.sh
    reap them (LF-4).
  - A caller of the private `_regression_capture_open` takes the fd from the return, and reads the capture back with
    `_regression_capture_read` (or its own `lseek(fd, 0, 0)` and read loop) instead of reading a name.

No block for:
- LF-2 and LF-3: tests and gates only.
- LF-4: cyrius's own `scripts/check.sh`, which is not part of what a consumer installs. For a contributor: at its start
  it removes an `audit_x[ca]_<digits>[.<digits>]` from `$TMPDIR` (or `/tmp` when TMPDIR is unset or relative) that is
  a regular file the user owns, older than `CYRIUS_CHECK_REAP_MINS` (default 240 min; 0 turns the age gate off), whose
  pid is dead. It prints one `check: reaped N capture file(s)` line.
- LF-6, which changes nothing that worked: with every std fd open, the normal case, every child setup is identical.
  - A `cyrius` CLI, check driver or programs/ tool started with fd 0, 1 or 2 closed (a cron job, a daemon, a `<&-` in
    a script) now builds, emits, runs and resolves what it was asked.
  - Before 6.7.16, with stdin closed, `cyrius build` could report OK for an EMPTY program. It exits 0 on x86_64,
    aarch64 Linux and Intel macOS and 1 on arm64 macOS, never what the source says.
  - With stdout closed, it failed with errno 9.
  - With stdin closed, `cyrius deps` could refuse a clean git cache as tampered.
  - A script that worked around this by opening /dev/null on the closed fd can drop that. There is nothing to change in
    a caller.

#### The declaration zone — redeclaration lists and float order, generic instance calls and methods, the replay's latch, struct if-expressions, `Str` methods, `*GPP`, vector assignments (the zone lane)

The decisions are the user's at the 6.7.16 open (2026-10-19: D13 – D18, all as recommended). D85 – D87 (2026-10-20)
answer three of this lane's finds and are applied by the s16 lane. "6.7.15's Dn" and "6.7.14's Dn" are those releases'
ids, and 6.7.16's D45 keeps 6.7.15's FE-13. Each block names its CHANGELOG [6.7.16] bite.

Every change below is in the frontend, so it is the same on x86_64, aarch64, cx, PE and Mach-O. The value changes were
measured on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine), and on ecb, ach, pi and cass for the lane's crossos files.
Everything is about top-level globals. "The declaration zone" is the top-level `var` block before the first top-level
statement.

**ZN-1 — a list over a const- or enum-named scalar constant keeps the bytes it does not list (no decision: the guide's list rule; with the ZN-1r review fix)**
- Changes what it computes: a declaration-zone global redeclared as a byte list over a named scalar constant keeps the
  constant's bytes in the positions the list leaves alone.
  - `const C = 0x0506; var a = C; var a[1] = {9};` reads 0x0509. Through 6.7.15 it read 0x0009; an enum name behaves
    the same.
  - The kept bytes are the slot's LAST INTEGER constant before the list, however each is spelled. `var a = 0x0506; var
    a = D; var a[1] = {9};` with `D = 0x0708` reads 0x0709; it read the stale literal's 0x0509.
  - A const between two lists reaches the earlier one, as a literal does: `var a[1] = {7}; var a = C; var a[1] = {9};`
    reads 0x0509 (it read 0x0009).
- Unchanged: a computed initializer in between is passed over, and `var a = f(); var a[1] = {0, 4};` still reads 0x400.
  At this lane's head, a FLOAT constant in between stops the search: `var a = C; var a = 1.5; var a[1] = {9};` reads
  0x0009, as through 6.7.15. ⚠ The s16 lane's SZ3 changes the float case in this same release (D86 (a): the list keeps
  the float's bytes); its block carries that migration.
- To migrate: if the code meant the positions the list does not write to be zero, write them in the list, or drop the
  scalar declaration.

**ZN-2 — a redeclared float constant is the global's value from program start (D13 (a), the user 2026-10-19)**
- Changes what it computes: in the declaration zone, a float constant redeclaration (a float literal, `= CF`, constant
  f64 arithmetic such as `= 1.5 + 1.0`, an f32 too) is the global's value from program start. An earlier float constant
  declaration of it leaves no startup store.
  - A READ between the two declarations sees the later value: `var G: f64 = 1.5; var b = load64(&G); var G: f64 = 2.5;`
    gives b 2.5's bits. Through 6.7.15 it gave 1.5's.
  - A call between them that WRITES the global keeps its write: `var G: f64 = 1.5;`, then `var r = setg();` storing
    0.5, then `var G: f64 = 2.5;` ends at 0.5. It was reset to 2.5.
- Changes what it computes, the same rule with an earlier declaration that is no constant (D13 (a) with 6.7.16's D45):
  - An earlier computed initializer before a float constant still runs, and its result is discarded. A read between
    them sees the float.
  - A list before a float constant redeclaration of the slot is evaluated for its errors only. `var K[1] = {9}; var c =
    load8(&K); var K = 1.5;` gives c 0 (it gave 9).
- A new warning: two DIFFERENT float constants for one global warn "duplicate symbol 'G' redefined with conflicting
  value (last definition wins)" once, at the later `=`, compared bit for bit. A pair of `= 0` then a float also warns. A
  same-bits pair is silent. This is often two files' defaults (`var G: f64 = 0;` in one, `= 1.5;` in another). It is a
  warning only: the value is the last definition, as before.
- Unchanged: a computed float redeclaration (`var G: f64 = fx();`) still runs in declaration order.
- To migrate: if a read between the declarations meant the earlier value, give it another name (`var G0: f64 = 1.5; var
  b = load64(&G0);`). If the later constant must win over a call's write, assign it after the call, in a fn or as a
  top-level statement. To silence the warning, make the constants agree or rename one.

**ZN-3 — a redeclared struct or tuple literal of constants is the global's value from program start (D14 (a), the user 2026-10-19)**
- Changes what it computes: in the declaration zone, a struct or tuple literal whose every element is a constant, when
  it redeclares a global, is the global's value from program start. An earlier literal of the name leaves no startup
  store. This holds in every spelling: a tuple, the named form, a generic struct's literal, a wrap.
  - A READ between the two sees the later literal: `var p = P { 1, 2 }; var b = p.a; var p = P { 3, 4 };` gives b == 3,
    and `var t = (1, 2); var b = t.0; var t = (3, 4);` gives b == 3. Through 6.7.15 each gave 1.
  - A call between them that WRITES the global keeps its write: `P { 1, 2 }`, then `setp` storing `p.a = 9`, then
    `P { 3, 4 }` ends at `{ 9, 4 }`. It was `{ 3, 4 }`.
  - An earlier COMPUTED initializer of the name (`var p = P { f(), 2 };`, `var q: Q = mk();`) still runs, and its result
    is discarded under a later constant literal.
- Unchanged: a later computed literal (`P { f(), 4 }`) runs in declaration order. No new warning: the conflicting-value
  compare stays scalar.
- To migrate: as for ZN-2. Rename one of the declarations if the read meant the earlier literal, or assign the literal
  after the call.

**ZN-4 — a float initialized by f64 arithmetic with an integer or enum right operand is in the image (D15 (a), the user 2026-10-19)**
- Changes what it computes: a declaration-zone float global initialized by f64 arithmetic with an integer or enum
  operand on the RIGHT is in the image from program start. This covers `var M: f64 = 1.5 + 1;`, `= 1.5 * E.A`, a bare
  enum member `= 1.5 * A`, and an integer const `= 1.5 + C`. The value is the same as before: the integer is its raw
  bits, so `1.5 + 1` is 1.5 and `1.5 * 3` is the subnormal with bits 4.
  - An EARLIER initializer that reads the global now sees the value. It read 0.
  - A call in an earlier initializer that writes the global keeps its write. The startup store reset it.
  - An x86 `kernel;` build's program reads the value (it read 0), and no longer warns "the initializer of 'M' runs
    after the top-level program" for it.
- Unchanged: "f64 arithmetic with a non-f64 right operand" is still warned, once. An integer LEFT operand (`1 + 1.5`,
  integer arithmetic on the float's bits) and a NaN result remain startup stores, still late and named in a `kernel;`
  build.
- To migrate: reorder the declarations if a code path relied on the old reading. Better, write the float literal you
  mean (`1.5 + 1` is 1.5: the warning is the hint).

**ZN-5 — a zone untyped generic call binds its instance whatever carries the type argument (no new decision: 6.7.14's D29 (a), 6.7.15's RC-14)**
- Stops compiling: in the declaration zone, an untyped global from a generic call returning a generic struct's instance,
  used in arithmetic, when that struct has no operator fn.
  - The calls are `var x = mkg1(30 + 3);`, `mkg1(-3)`, `mkg1(1.5)`, `mkg1(id(1.5))`, `mkp1(&n)` (`p: *T`), a struct
    carrier `mkc(BX)` and a bounded `G1<T: Show>`'s call, with `fn mkg1<T>(v: T): G1<T>`.
  - The global now IS that instance, so `var y = x + 1;` dispatches `G1_add` and is refused without one ("undefined
    function 'G1_add'"). Through 6.7.15 the global was an untyped word in the zone, and `x + 1` added to it: 34 for
    `mkg1(30 + 3)`, measured.
  - After the first statement the line already behaved this way.
- To migrate: bind the field (`x.v + 1`), or annotate `var x: i64 = …` if a number was meant. Lines that were refused
  at `x.v` ("no struct type in scope for 'x'") now compile.

**ZN-7 — a zone generic method's generic struct result is the instance its call reaches (no new decision: 6.7.15's D34 (a))**
- Stops compiling: in the declaration zone, an untyped global from a GENERIC method's generic struct result, or from
  an explicit `.m<..>(` call returning a plain struct, used in arithmetic when the struct has no operator fn.
  - `var y = b.mkg(P);` with `fn mkg<T>(self, v: T): G1<T>` is now `G1<Pt>`, so `var z = y + 1;` is refused "undefined
    function 'G1$Pt_add'". It added to the word: 34, measured.
  - `var y = b.mk<i32>(30);` returning a plain `S8` is now `S8`, so `y + 1` is refused "undefined function 'S8_add'".
    It gave 31.
- At this lane's head, a generic OPERATOR fn's result is its base (`var y = b + 3;` with `fn B1_add<T>(l: B1, r: T):
  G1<T>` is `G1`). ⚠ The s16 lane's SZ4 changes the generic operator in this same release (D85 (a): it binds T as its
  call does); its block carries that migration.
- To migrate: bind the field, or annotate. Lines that were refused now compile: `y.v` "no struct type in scope", and
  `var G: S8 = b.mk<i32>(3);` "the declaration zone misread ...".

**ZN-9 — an untyped top-level if-expression of struct branches binds the struct (D16 (a), the user 2026-10-19)**
- Stops compiling or changes what it computes: an untyped top-level `var G = if (c) { B1 } else { B1 };` whose branches
  are a struct of 8 bytes or less is that struct, in the declaration zone and after the first statement.
  - `G + x` dispatches the struct's operator fn, and is refused without one. Through 6.7.15 it added to the word: `var y
    = G + 1;` gave 34 and is now refused "undefined function 'P1_add'".
  - G is its first branch's struct, as in a fn.
- Changed message (refused before and after): a 16-byte struct branch is "an if expression branch cannot be a struct
  value over 8 bytes: struct 'P2'". It was "... cannot be a vector, u128 or slice value", at top level and in a fn. A
  script grepping for the old text reads the new one.
- To migrate: bind the field (`G.a`, which now compiles where it was refused), or annotate `var G: i64 = …` to keep the
  word.

**ZN-10 — a top-level untyped global from a whole method call routes as one from a free call (no decision: the guide's routing rule)**
- Changes what it computes: a top-level untyped global from a `: Str` METHOD call routes to the overload's `_str`
  variant (`println`, `strlen`, a user `f` / `f_str` pair), as a free `: Str` call's global does.
  - This covers `var s = BB.mks();`, wrapped, a chain ending in one (`W.b.mks()`), a `*B` receiver and `.m<..>(..)`, in
    the declaration zone and after the first statement.
  - `println(s)` prints the string. It printed the Str header's bytes, exit 0.
- A new warning: a `: cstring` parameter receiving such a global warns "passing Str-typed ...", as for a free call's.
- To migrate: nothing; this is the fix, and the string is what the source says. Code that worked around the old output
  (an explicit `println_str(s)`) keeps working.

**ZN-11 — a top-level `var G: S = *GPP;` is a copy at every size (D17 (a), the user 2026-10-19; the two refusals ⚠ go beyond D17's text)**
- Changes what it computes: a top-level struct global declared from `*pp` of a `**S` global (`*GPP`, `(*GPP)`), a
  `: **S` call (`*gpp()`) or a `**S` field (`*W.pp`) is its OWN COPY at every size, in the declaration zone and after
  the first statement. It was a handle on the struct, so writes through either side are no longer seen by the other.
  The same line in a fn has copied since 6.7.15.
- ⚠ Stops compiling (beyond D17's text):
  - `var G: S = *GQQ;` with GQQ a `**Q` of ANOTHER struct: "cannot copy '*GQQ' into a variable of a different
    struct/vector type: 'G'". It read Q's bytes as an S. In a fn it has been refused since 6.7.15.
  - Over 8 bytes, a `**S` source global declared BELOW G: "cannot copy-init 'G' from a dereference of a global or fn
    declared below it (declare it first)". It compiled and faulted at startup.
- To migrate: for the alias, declare `var G: *S = *GPP;`. Copy another struct's bytes field by field. Declare the
  `**S` global before G.

**ZN-12 — a top-level `var G: S = P;` from a `*S` global's name is a copy at every size (D18 (a), the user 2026-10-19; ⚠ the two declared-below shapes go beyond D18's text)**
- Changes what it computes: `var G: S = P;`, `(P)` or `((P))`, with P a `*S` global of the declared struct, copies the
  struct P points at, at every size, in the declaration zone and after the first statement, as the same line in a fn
  does. This settles the guide's "⚠ Not yet settled" rule.
  - At 8 bytes or less, G held the POINTER WORD as its field (`G.v` read the address). It now holds the struct's bytes.
  - Over 8 bytes, G was a handle bound to P's object. It is now a copy, so a write through `G` or `*P` is no longer seen
    by the other.
  - The census found no such global in `lib/`, `programs/`, `cbt/` or the `.tcyr` corpus.
- ⚠ Stops compiling (beyond D18's text): over 8 bytes, a P declared BELOW G is "cannot copy-init 'G' from a global
  declared below it (declare the source first)". It compiled and faulted at startup.
- ⚠ Faults at startup (beyond D18's text; a regression filed and placed IN 6.7.16, the s16 lane's SZ3): at 8 bytes or
  less, a P declared BELOW G now compiles and SIGSEGVs at startup, as `*GP8` already did. Before, it read the pointer
  word, which was still 0. Declare P first.
- Unchanged: an untyped `var Q = P;` and `var R: *S = P;` are the pointer. A `*U` global of ANOTHER struct into an `S`
  keeps its old layout at this lane's head; the user's D87 (a) refuses it, and the s16 lane's SZ3 applies that in this
  same release.
- To migrate: for the alias, declare `var G: *S = P;`. Declare P before G.

**ZN-13 — a top-level assignment of a vector call to a global that is no vector is refused (no new decision: 6.7.14's D38 / D27 (a))**
- Stops compiling: a top-level ASSIGNMENT of a call declared to return a vector, to a scalar, struct or f64 global.
  - The spellings are `G = mkv(41, 7);`, `G = s.mv();`, wrapped, `fncall2(&mkv, ..)` / `callptr(&mkv, ..)`,
    `mkg<i64>(..)` and `G = mkv(..) + 1`, as the program's first statement, after it, or in a top-level for step.
  - The refusal is "vector return type does not match the assigned variable", as in a fn since 6.7.15.
  - It compiled with no diagnostic and stored one word: 0 on x86_64 / aarch64 and 41 on cx / Windows.
- Unchanged: a vector global keeps its own refusal. The top-level declaration was already refused (6.7.15's D26 / D27).
- To migrate: make the call in a fn. Store its lanes through `&g`, or read them into a scalar there.

Nothing to migrate (diagnostics on code that never compiled, or refused code that now compiles):
- ZN-6: a zone generic call with a refused type argument (`var x = mkg1<*u8>(33);`) gives the type argument's one
  refusal. `x.v` no longer adds "no struct type in scope for 'x'".
- ZN-8: the declaration zone reports one error per declaration, as a fn does. `var p = g(1 2); var q = g(3 4);` reports
  2:13 and 3:13; it reported only the first. A refused build stays refused. A script that counts error lines over a
  multi-error zone reads more of them. A zone use of a refused enum (`enum E { A 5 }` then `var q = E.A;`) adds "no
  struct type in scope for 'E'"; that cascade is filed and placed in the s16 lane.
- ZN-1r: a review fix inside ZN-1's block above. Against 6.7.15 it changes nothing: the float case reads 0x0009 before
  and after.

#### Generic signatures — impl and dyn checks, trait members' types, type-argument counts, Vec and `**G<..>` arguments, an impl above its struct, instance names in diagnostics (the gensig lane)

The decisions are the user's at the 6.7.16 open (2026-10-19, D5 – D10, all as recommended). "6.7.15's Dn" is the 6.7.15
open's id (2026-10-18). Each block names its CHANGELOG [6.7.16] bite. Every change below is in the frontend — measured
on x86_64, aarch64, cx and PE; Mach-O shares the frontend.

**GS-5 — a trait member's return is held to a fn's whole return set (D9, the user 2026-10-19)**
- Stops compiling, at the member: a trait member declared `: u8`, `: u16`, `: u32`, `: u64`, `: f32` or with an enum
  return — "type 'u8' cannot be a fn return type" with a fn's note — or with a `: *fn( .. )` return — "a fn-pointer type
  `*fn( .. )` cannot be a fn return type". A `: **fn( .. )` return gets the same line (beyond D9's text, which named
  `: *fn(i64): i64`). No impl could define such a member (an impl's `fn a(self): u8` was already refused). Through
  6.7.15 the trait compiled; an impl spelled `: i64` under it was refused with "'P.c' returns i64, trait 'T' declares
  u8", which is now the member's line alone.
- `cyrius lint` (`--syntax-only`) newly reports the `*fn( .. )` member line, as it reports a fn's `: *fn( .. )` return;
  the name members (`: u8` .. `: u64`, `: f32`, an enum) stay silent under lint, as a fn's are.
- **Migrate:** declare the member `: i64` (an enum's or a narrow integer's value is an i64) or a pointer (`: *Color`,
  `: *u8`), and its impls with it. `: i64`, `: f64`, `: bool`, a struct, `: *u8`, `: Result`, the member's own `: U`, a
  parameter `cb: *fn(i64): u128` and the rest of a fn's set are unchanged.

**GS-7 — a type-argument list longer than its generic declares (D5, the user 2026-10-19)**
- Stops compiling, at the first extra argument: `var b: Box<i64, i64>;` with `struct Box<T>` — "'Box' takes 1 type
  argument, 2 given" — and `g<i32, Pt>(5)` on `fn g<T>` ("'g' takes 1 type argument, 2 given"), `p.m<i32, Pt>(5)` on a
  generic method (named `'P.m'`), `Pair<i32, Pt, i64>` on a two-parameter struct ("'Pair' takes 2 type arguments, 3
  given"), in every position: a local, a parameter, a global, a return, `*Box<..>`, `sizeof`, a struct literal head, a
  field, a Vec element, a trait member, a `*fn( .. )` parameter, a nested list, an explicit fn or method call, a
  struct-valued receive. Through 6.7.15 the extra argument was read and dropped: the generic's declared arguments alone
  were used (`sizeof(Box<i64, i64>)` was `Box<i64>`'s 16). One line per list; nothing cascades. Silent under
  `--syntax-only`.
- **Migrate:** delete the extra arguments — they were ignored, so nothing the program computes changes.

**GS-8 — a third type parameter (D8, the user 2026-10-19)**
- Stops compiling, at the declaration: a generic fn, struct or method declaring a third type parameter — `fn g3<A, B,
  C>`, `struct Three<A, B, C>`, `fn m<A, B, C>` in an impl, bounded or not, four or more (refused at the third) — "a
  third type parameter 'C': a generic takes at most two type parameters". Its uses say nothing more. Through 6.7.15 the
  third parameter was never recorded: it was i64 whatever was passed (`g3(1, 2, s)` read `sizeof(C)` as 8 for a 24-byte
  struct), laid out as an i64, and every explicit three-argument use was a parse error. A bounded third (`<A, B, C:
  Show>`) gets this line instead of "a bound on a third type parameter ..". `cyrius lint` reports it too.
  `CYRIUS_MONOMORPH=0` is unchanged.
- **Migrate:** use at most two type parameters — pass a struct holding the rest, or a pointer. A bodiless trait member's
  own `fn g<A, B, C>(..);` still compiles in this bite (filed; D92 refuses it later in 6.7.16): change it too.

**GS-9 — a Vec element whose generic struct takes another instance, under a bound (D10, the user 2026-10-19)**
- Stops compiling, at the element: a `Vec<..>` element whose generic struct has a bounded parameter given another generic
  struct's instance — `var w: Vec<Box<Box<R>>> = 0;` with `struct Box<T: Show>` — "generic 'Box': its type argument does
  not implement trait 'Show'", the note naming `impl Show for Box$R`, as `var b: Box<Box<R>>;` always was. A local, a
  field, a parameter, a global and a generic's `Vec<Box<Box<T>>>` (per instance) alike; an `impl Show for Box` does not
  satisfy it. No impl can name an instance (`impl Show for Box<R>` is a parse error), so no source could meet the bound.
  Reported under `cyrius lint` too, as the by-value form is.
- **Migrate:** drop the outer bound, or the nesting. A Vec is a handle: nothing it compiled to changes. An unbounded
  outer struct over an instance (`Vec<UB<Box<R>>>`) and `Vec<Box<Box<i64>>>` (the inner `Box<i64>` is the base, judged as
  6.7.15 judged it) are unchanged.

**GS-11 (+ GS-11r, GS-12, GS-14) — `Name<..>` on a non-generic struct or a scalar in the remaining positions (D7, the user 2026-10-19)**
- Stops compiling, at the name: type arguments on a non-generic struct or a scalar in a pointer field (`struct H { p:
  *Pt<i64>; }`, its pointee above or below), a trait member's signature (a parameter `p: Pt<i64>` / `p: *Pt<i64>` /
  `k: i32<u8>`, the return `: Pt<i64>`, a tuple element), a multi-value return element (`fn mv(): (Pt<i64>, i64)`,
  `(i64<u8>, i64)`, `(*i32<u8>, i64)`), a `*fn( .. )` type (`cb: *fn(Pt<i64>): i64`, and its own return
  `*fn(i64): Pt<i64>`), a `**Pt<i64>` parameter, and `*i32<u8>` as a local, a global, a `: *T` return or a field —
  "'Pt' is not a generic struct: it takes no type arguments" / "'i32' takes no type arguments". Through 6.7.15 each
  compiled with the `<..>` ignored. (A member's return / `*T` / tuple element, a `*fn( .. )`'s own return, a
  `*i32<u8>` field or element and a scalar multi-value element go beyond D7's text; the lane applied D7 at each reader
  the filing named.)
- `cyrius lint` (`--syntax-only`) changes the other way for the shapes that were parse errors — a scalar return
  `fn f(): i64<u8>`, a by-value field `f: Pt<i64>` / `g: i64<u8>` (a struct's or a union's), a slice element
  `[Pt<i64>]` / `[*Pt<i64>]` / `slice<*i32<u8>>`: lint is now silent on them (the compile refuses them, at the name), as
  it is on 6.7.15's D6 shapes (beyond D7's text).
- **Migrate:** delete the `<..>` — it was ignored, so nothing the program computes changes. If you meant a generic
  struct, declare it `struct Pt<T> { .. }`. A generic struct's own list (`*Box<Pt>`, `Box<i64>`, `*fn(Box<Pt>)`) is
  unchanged. Still accepted in this bite, the list ignored (filed; D93 refuses it later in 6.7.16): a tuple element
  `(i64<u8>, i64)` in a local, a global, a parameter or a field — delete those `<..>` too.

**GS-13 — an `impl T { .. }` written above `struct T` (D6, the user 2026-10-19)**
- Stops compiling: with the impl above its struct, arithmetic on an untyped `self` — `load64(self + 8)`, `self[i]`,
  `self += n` — "arithmetic on an untyped `self` is refused - in an impl it points at 'R2': ..", as it always was with
  the struct first. Through 6.7.15 `self` was an untyped word in this order, so the line compiled (the filed shape,
  called as `t.get()`, exited 7).
- Changes what it computes: a direct call `T_m(t)` of such a method now passes `&t`, as `t.m()` does; it passed t's value
  (a fault — exit 139 on x86_64 / aarch64 — unless that word happened to be an address; PE already passed a 16-byte
  struct by reference).
- Starts working: `self.b` with the impl above (it was "no struct type in scope for 'self'").
- **Migrate:** read fields with `self.field`, or declare `self: *T` to step whole elements. `T_m(t)` and `T_m(&t)` now
  agree with `t.m()` in either order; nothing to rewrite for them.

Nothing to migrate (refused code now compiles, a crash becomes the right answer, or only error or warning output
changes): GS-1 (an impl's return mismatch no longer hides the next method's mismatch or a missing method: one compile
reports them all), GS-2 (a dyn forms from an impl whose method spells a member's type another way — `Box<i64>` /
`Box`, `Box<Box<i64>>` / `Box<Box<i64> >`, `*Box<i64>` / `*Box`; the "(.. is i64)" hint prints only for an unannotated
side), GS-3 (a generic trait member's own `<U>` after a `*fn(..)` compiles), GS-4 (a member's `cb: *fn(i64): u128`
compiles; a later `v: u128` is reported at its own token), GS-6 (an impl method's `*fn( .. )` return is one error),
GS-10 (a `**G<..>` parameter's refusal no longer hides the next parameter's error), GS-12 / GS-14 (a union's by-value
field and a slice's pointer element given type arguments: D6's line instead of a parse error), GS-15 (the bounded-forward
refusal and its notes say `P.bk` where they said `P_bk` — a tool matching `'P_bk'` should match `'P.bk'`), GS-16 (the
mixed `: stack` pair warning for an inherited trait default names `Dv.qd` where it named the first inheriting impl,
`Pt.qd`; a script counting or matching that warning sees the new name, same line, same count), GS-17 (a generic's
wrong-count `return` is one line naming `'gr'`; the per-instance `'gr$P'` lines are gone), GS-18 (a method's
wrong-count `return` says `'P.mv'` where it said `'P_mv'`), GS-5r / GS-7r / GS-7r2 (a type its own reader refuses in a
trait signature — a member's `: u8`, `b: *Box<i64, Pt>`, `p: *Pt<i64>`, `n: Nope`, a slice or `u128` parameter — is
that one error, with no "returns .." line from the impl check and no "does not match its declaration" line at a formed
dyn), GS-11r (no change against 6.7.15: a member's `: Result<Pt<i64>>` against an impl's `: i64` is the impl's refusal,
as it was), GS-13r (a gate).

#### Generic binding — compile time and nesting depth, bound contracts, closures' parameters and captures, `**Box<T>` inference, the stub scans, struct results at a scalar T (D1 / D2), `*Str` and multi-value elements (the genbind lane)

The decisions are the user's at the 6.7.16 open (2026-10-19, D1 – D4, all as recommended). "6.7.15's Dn" is the
6.7.15 open's id (2026-10-18), "6.7.14's Dn" the 6.7.14 open's (2026-10-16). Each block names its CHANGELOG [6.7.16]
bite. Every change below is in the frontend: the same on x86_64, aarch64, cx, PE and Mach-O.

**GB-4 — the explicit spelling `v.m<..>(..)` is held to a bound's contract (D4, the user 2026-10-19)**
- Stops compiling, at the generic's definition, called or not: a bounded generic that calls, with explicit type
  arguments, a method no trait of its bound declares — `fn g<T: Show>(v: T) { return v.other<i64>(1); }`, or
  `b.v.other<i64>(1)` on a carrier's `T` field (`b: Box<T>`) — "method 'other' is not in the bound on type parameter
  'T'", the note naming `'v'` / `'b.v'`. Through 6.7.15 it called the instance's own `other` (the inferred `v.other(1)`
  was already refused).
- Starts working: a bound's own generic member called with an explicit list at a scalar T (`v.show<i64>(1)` with
  `trait Show { fn show<V>(self, k: V): i64; }` and `impl Show for i64`), refused through 6.7.15.
- **Migrate:** call a method the bound declares, add a trait that declares it to the bound, or drop the bound (an
  unbounded T resolves per instance).

**GB-9 — a closure's parameter is untyped, whatever an earlier fn left in its frame slot (no decision: closure parameters are untyped since 6.7.14)**
- Stops compiling: a closure that reads a field (`|x| { return x.b; }`), stores a field or calls a method through an
  untyped parameter, where only an EARLIER fn's local or parameter in the same frame slot gave it a struct type (`fn
  h(w: *Q)` above it) — "no struct type in scope for 'x'"; and `x = mkp();` there — 6.7.15's D33 refusal ("cannot assign
  'x' from 'mkp', which returns the struct 'Q' ..."). Through 6.7.15 the parameter took that fn's `*Q`: the read went
  through it (a fault unless the argument happened to be such a pointer) and the assignment copied the struct through
  it. The same source without the unrelated fn was already refused.
- Changes what tools print: after `fn h(w: f64)`, `|x| x + 1` no longer warns "f64 arithmetic with a non-f64 right
  operand" (the value was and is right).
- **Migrate:** type the pointer in the closure body — `var p: *Q = x; return p.b;` (it compiles and runs, with the
  warning "assigning non-pointer to typed pointer" for the untyped source) — or capture a typed name.

**GB-11 — a closure's captured `f64` binds `T = f64` (D3, the user 2026-10-19)**
- Changes which fn runs: a generic called inside a closure with a captured f64 as its whole argument (`|| gid(h)`, `h:
  f64` captured), through `x: T` or `p: *T`, runs the f64 instance where it ran the i64 base on the double's bits; its
  `: T` result is an f64, so `|| f64_to(gid(h) * 2.0)` is 3 (it was 0, with "integer arithmetic with an f64 right
  operand"). The same for a captured parameter, a capture of a capture, a generic method, the second type parameter and
  a bound (the f64 impl runs). A captured i64, a captured `*f64` and a captured f32 bind as before.
- **Migrate:** nothing to rewrite where the f64 was meant; code that did integer arithmetic on the result now does float
  arithmetic. Stored into an untyped word, the result is the same bits as before.

**GB-14 — a `**G<..>` struct field mints its instance after the struct's `}` (no decision: a half-built instance)**
- Changes what it computes: a program whose struct field `qq: **G<X>` named `G<X>` before anything else did (or whose
  struct A holds `p: **G<A>`) and which used `G<X>` only through `sizeof` — every field use of `G<X>` was refused,
  "unknown field 'v' on struct 'Box$S16'" — compiled with a half-built instance: `sizeof(Box<S16>)` was 16 (it is 24),
  `sizeof(Box<A>)` with `p: **Box<A>` inside A was 16 (it is 32). Storage sized by it grows to the real size. Nothing to
  rewrite.
- Starts working: such a program's field uses of `G<X>`, and a generic struct's own-T `**` field (`struct HG<T> {
  qq: **Box<T>; }`, `struct LL<T> { next: **LL<T>; }`), refused "unknown type 'T' as a type argument" through 6.7.15.
- Still refused by this lane: a `**B` / `**Box<B>` field with B declared below the struct (the user's D103, 2026-10-20,
  accepts it as `*B`; placed in a wave-4 unit).

**GB-15 — a generic's `pp: **Box<T>` parameter carries `T` (no decision: a silent wrong layout)**
- Changes which fn runs: an inferred call of a generic declared `pp: **G<..T..>` (or deeper) given a `**G<X>` — `&q` of
  a `*Box<Pt>`, a `**Box<Pt>` local, parameter, global, field or `: **Box<Pt>` call, wrapped — runs G's X instance
  instead of the i64 base: the box's fields are read at `G<X>`'s offsets (the base read them at `G<i64>`'s — `b.n` of a
  `Box<Pt>` read `Pt.y`) and `sizeof(T)` is X's. A `Box<i32>` source calls the i32 instance. `&ps` of a `*Pt`, and a
  `*Box<Pt>` given to `**Box<T>`, bind nothing, as before.
- Starts working: a forwarder passing its `pp: **Box<T>` (or a `**Box<T>` local) into a stub generic, refused naming the
  stub through 6.7.15.
- **Migrate:** nothing to rewrite — the base read the wrong layout. A program that relied on the base's reading reads
  the instance's fields now; spell `nb<X>(..)` to name the instance explicitly.

**GB-18 — a generic's base reads its signature's type-argument list at `T = i64` (no decision: the base misread its own signature)**
- Stops compiling: passing the base struct (or `Box<i64>`) BY VALUE to a generic's parameter typed with another instance
  — `fn rd<T>(b: Box<Pt>, x: T)` called `rd(q, 5)` with `q: Box<i64>` — "cannot pass 'q' to a parameter of a different
  struct type in a call to 'rd'", as for a non-generic fn. Through 6.7.15 the base read `b: Box<Pt>` as the base `Box`,
  so the call compiled and read the base layout (and passing a real `Box<Pt>` was the refused one).
- Changes what it computes: a POINTER parameter typed with another instance (`b: *Box<Pt>`) is read at that instance's
  offsets in the base too, and a `*Box<i64>` argument is not checked at the call: `rd(&q, 5)` with `q: Box<i64>`, which
  read `q.n` (9), now reads `Box<Pt>`'s `n` offset, past q (0 in a probe). That pass is the shape the user decided to
  refuse (D97, a pointer to another struct at the argument; its wave-4 unit).
- Changes what tools print: a bound refusal on such a signature (`: Bx<Pt>`, Pt not Show) is reported at the signature,
  not at the body's local (once either way).
- Starts working: `fn mkn<T>(v: T): G1<Box<T>> { var g: G1<Box<T>>; g.v.v = v; return g; }` (a field of a field whose
  name a parameter also has), and a generic whose signature names a non-base instance — `: G1<Box<T>>`, `: Box<Pt>`,
  `: Box<i32>`, `b: Box<Pt>`, `b: *Box<Pt>`, `b: Box<i32>` — used at i64.
- **Migrate:** pass the instance the signature names (`var q: Box<Pt>`), or declare the parameter as the struct you pass.

**GB-19 (+ GB-19r) — a generic whose body needs `T` to be a struct has no scalar instance for two more lines (D1, the user 2026-10-19)**
- Stops compiling, at the call: a scalar call (`h(3)`, `g(5)`, `g(u)` with `u: u8`, `g<i64>(5)`, `h<i32>(4)`,
  `g<i32>(5)`), `&h`, or a scalar call of a generic forwarding its `T` to one, where the body returns `&n` of a name
  typed by `T` as a struct (`fn h<T>(x: T): S8 { var n: T = x; return &n; }` — also `p: *T`, an untyped `var n = x;`,
  wrapped, a generic method) or stores a struct result over 8 bytes in a name typed by `T` (`var y: T = mkp();`,
  `y = mkp();` into a `y: T` local or parameter, `p = mkp();` into a `p: *T` / `pp: **T`; the result from a call, a
  method, an operator or a known `&f`, wrapped) — "generic 'h' has no i64 (or other scalar) instance: it uses its type
  parameter as a struct (...)" with a note naming the line. Through 6.7.15 `h(3)` returned a dead slot's address as the
  struct and `g(5)` kept the struct's first word, silently; `h<i32>(4)` / `g<i32>(5)` were refused in the slot's / the
  declaration's words.
- Unchanged: a call with a struct (`h(s)`, `g(q)` copies); a fn returning its own `: T`; a closure's own `return &n`; an
  8-byte struct or a `Str` result (one word, which a scalar keeps); a store THROUGH the pointer, `*p = mkp();` /
  `**pp = mkp();` (GB-19r — not judged here; the user's D99 refuses its plain-fn and generic shapes in a wave-4 unit).
- Changes what tools print: every stub refusal — the `.field` one included — names the two new shapes in its words and
  prints a `  note:` line after its excerpt (a forwarder: the forward, then the line at the end of the chain). A script
  counting stderr lines sees one or two more; `^error` counts are unchanged.
- **Migrate:** call the generic with a struct, or bind a field — `var y: T = mkp().a;` — so the body works at a scalar
  T.

**GB-20 — `return &n;` of a name typed with no type parameter is refused in a generic's definition (D2, the user 2026-10-19)**
- Stops compiling, at the `&n`, called or not: a generic fn returning a struct whose body holds `return &n;` of a local
  or parameter typed with no type parameter — `var n = 5;`, `var n: i64`, `var n: *i64`, `var n: **S8`, a `k: i32` or
  untyped parameter, an untyped `var` reading nothing of `T` (`var n = k + 1;`, `var n = sizeof(T);`) — and, in a generic
  that has no scalar instance (a stub), `return &GN;` of a global holding no struct: "a fn returning the struct `S8`
  takes a value of that struct, or a pointer to one — `&n` is the address of n's slot, not a struct" (6.7.15's D18
  words). Through 6.7.15 the generic's base exempted the line: never called, or called only with an integer, it compiled,
  and `h(3)` returned the slot's address as the struct.
- **Migrate:** return a struct value, or `&` of a struct local (`var s: S8; ...; return &s;`). A name typed by `T` is
  GB-19's rule.

**GB-21 — a `*Str` dereference into a generic's `x: T` at `T = Str` passes the header (no decision: a silent wrong value)**
- Changes what it computes: `gg<Str>(*p)`, the inferred `gg(*p)` and a generic method's `o.gm(*p)` with `p: *Str` pass
  the header p points at, as `gg<Str>(p)` does — also wrapped, `*w.p`, `**pp`, `*gsp()`, a second argument, a tail call,
  a capture, a forwarder, top level. Through 6.7.15 they passed the string's data word as the header (`str_len(x)` 0, or
  a wild length). Nothing stops or starts compiling.
- **Migrate:** nothing to rewrite; drop any workaround (`var s: Str = *p; gg<Str>(s)` keeps working).

**GB-22 — a generic's multi-value element typed by its type parameter is the instance's binding (no decision: the instance returns `(f64, i64)`)**
- Changes what it computes: a destructure or multi-value assignment of a generic whose element is typed by a type
  parameter bound to f64 — `var a, b = mm2<f64>(h);` with `fn mm2<V>(x: V): (V, i64)`, the inferred `mm2(h)`,
  `p.mm<f64>(h)`, `p.mm(h)`, `P_mm<f64>(&p, h)` — binds an f64: `f64_to(a * 2.0) + b` is 10 (it was 7, integer arithmetic
  on the double's bits with a warning). A struct-bound element is the struct; a narrower integer stays an i64 slot.
- Stops compiling, as the same line against a fn written `(f64, i64)` / `(Pt, i64)` already does: `var t: (i64, i64) =
  mm2<f64>(h);` ("cannot capture 'mm2' into tuple (i64, i64) - it returns 2 values, (f64, i64)"; it held the double's
  bits as `t.0`), `var t: (i64, i64) = mm2<Pt>(p);` ("(Pt, i64)"; it held the struct's first word), and a generic body's
  `return G;` of a tuple global whose element types differ from an instance's (`(i64, i64)` returned from `mt<f64>`'s
  `(V, i64)`: "cannot return tuple 'G' (i64, i64) from 'mt<f64>' - it returns (f64, i64)").
- Starts working: `var t: (f64, i64) = mm2<f64>(h);` (and `t = ..`, the method spellings), refused "(i64, i64)" through
  6.7.15.
- Changes what tools print: a generic's tuple local is reported once (its type), no longer twice; the multi-value
  refusals spell the fn and its values as the source does (GB-23: `mt<f64>`, `Q.pair`, `(Box<Pt>, i64)` — they said
  `mt$f64`, `Q_pair`, `(Box$Pt, i64)`).
- **Migrate:** capture into the instance's values (`var t: (f64, i64) = mm2<f64>(h);`, `var t: (Pt, i64) = ..`), or
  destructure.

Nothing to migrate (compile time only, refused code now compiles, a crash or a wrong refusal becomes the right answer,
`cyrius lint` accepts more valid files, or only error output changes): GB-1 (compile time linear in generic definitions),
GB-2 (a forwarding chain compiles to ~300 links — 290 on Windows — and one fn may instantiate 300 generics on x86; a
longer chain's refusal reads "nesting too deep (N generic instances, each parsed inside the call that reaches it, used
over 6 MB of the compiler's stack)", it read "over 256 levels"), GB-3 (every bound-contract refusal of a compile prints),
GB-5 / GB-5r / GB-7 / GB-24 (`cyrius lint` / `--syntax-only` accept `a.m<i64>(1)`, `a.h.k(1)`, a named argument, `a.r(1).g`
and `var a: Foo;` with Foo in a sibling file), GB-6 (a type-argument list on a non-generic fn or method is one error at
its name — "'nf' is not a generic fn: it takes no type arguments"; a tool matching "unknown field 'm'" for that shape sees
the new text), GB-8 (a gate), GB-10 (`|k| w.s.gs(k)` binds i64; two faults become values), GB-12 (a SIMD vector's
`.m()` is one error), GB-13 / GB-13r (a field use of an untyped closure capture is "no struct type in scope for 'x'" where
it was "undefined variable 'x'"; a bounded generic's closure calling the bound on a captured scalar T, and `self` captured
in a trait default for a scalar, compile; ⚠ a capture named like a struct GLOBAL still reads the global's field — D96
refuses it in a wave-4 unit), GB-16 (the stub scan binds `gd2(&GPP)` / `gd(gpi(&GP0))` as the parser does), GB-17 (a
dropped global), GB-23 (the multi-value refusals' spelling, above).

#### Receives — tuple parameters, vector method and `callptr` sources, a vector call's operators, struct and vector fns' `return` errors, `ret2` after a case label (the receives lane)

The 6.7.16 decisions are the user's:
- at the 6.7.16 open (2026-10-19): D23 – D26;
- at the wave-3 integration (2026-10-20), on what this lane found: D100 and D104, placed in wave 4.

Ids from other releases are written with their release:
- **6.7.15's** (2026-10-18): D26, D28, D29, D36, D62;
- **6.7.14's** (2026-10-16): D27 (a), D37 – D39, D42, D43;
- **6.7.13's** (2026-10-15): D12, D20 – D22, D29. 6.7.13's D29 (a vector method is taken as the vector) is not 6.7.15's
  D29 (a vector method starting an integer initialiser is refused).

Each block names its CHANGELOG [6.7.16] bite. Every change below is in the frontend, so every target alike.

**RV-2 (with RV-2r) — a float literal into a tuple parameter is refused at the argument (D23, the user 2026-10-19)**
- Stops compiling: passing a tuple parameter an argument made only of literals and operators that includes a float
  literal. Examples: `take(1.5)`, `take(-1.5)`, `take((2.0))`, `take(1.5 + 1)`, `take(1 + 1.5)`, `take(2.0 * 1.5)`,
  `take(~1.5)`; a method's `x.take(1.5)`; any argument position; at top level too. The errors:
  - "cannot pass an f64 to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple": the value the compiler types
    f64;
  - "cannot pass a bool …": a float comparison, `take(1.5 < 2.0)`;
  - "cannot pass an integer …": an integer-typed mix, `take(1.5 & 1)`.

  It crashed at run time when the callee read the tuple: 139 on x86_64 / aarch64, 1 on cx, 5 on Windows. It ran only if
  the callee never read it. Pass a tuple of the parameter's type: `var t: (f64, f64) = (1.5, 0.0); take(t);`, or the
  literal `take((1.5, 0.0))`.
- Unchanged (6.7.15's D36): a name — an `f64` const too, `take(F)` — or `&t` or a call is still passed as the address,
  unchecked. `take(x_scale * 2.0)` holds a name, so it is not judged.
- In flight in 6.7.16: `take(2 +| 1.5)` says "an f64" (the compiler's current typing of a saturating op). D104 (the user,
  2026-10-20, the f16 lane's FG4) makes `+| +? -| -? *| *?` give an integer; with it, the words become "an integer". It is
  refused either way.

**RV-4 — a vector method on any receiver the method arm takes is the vector at every receive (no new decision: 6.7.13's D29 and 6.7.14's D37 – D39 name the method, not its receiver; row 4 is 6.7.14's D38)**
- Behaves differently: a method declared `: f64v2` (or f32v4 / f64v4) on a parenthesised head (`(*p).mv()`, `(s).mv()`,
  `(*pw).s.mv()`), a call's result (`f(&w).s.mv()`, `mks(1).mv()`, `callptr(&gw, &w).s.mv()`) or a method's result
  mid-chain (`o.get(&w).s.mv()`) is the whole vector:
  - `var v = (*p).mv();` is an `f64v2` local. It held one word of stack garbage, a different value per target and build.
  - `rd((*p).mv())` into a `*f64v2` passes a temporary's address. It pushed lane 0 as the address (139).
- Stops compiling: an integer, `: f64` or other-vector destination of such a method — `var x: i64 = (*p).mv();`,
  `x = f(&w).s.mv();`, `var x: f64 = (*p).mv();`, an f64v4 declaration, assignment, argument or return. The errors are
  "vector return type does not match the declared type" / ".. the assigned variable". It stored the result's first word
  (0, or 41 on cx / Windows). Bind the vector (`var v = (*p).mv();`) and read its lanes (`load64(&v)`).
- Starts compiling: `var v: f64v2 = (*p).mv();`, the assignment, `lanes((*p).mv())` and `return (*p).mv();` from an
  `f64v2` fn. These were refused, "… got `(...)`".

**RV-5 (with RV-5r) — a method or `callptr(&f, ..)` starting an assignment, and a vector call in parentheses starting an integer source, are refused (D25 and D26, the user 2026-10-19)**
- Stops compiling:
  - an integer local, global (in a fn or at top level) or for-step assignment whose right-hand side starts with a vector
    method, `callptr(&f, ..)` or `fncallN(&f, ..)`: `x = v.m() + 1;`, `x = callptr(&f, 41, 7) + 1;`. Error: "vector
    return type does not match the assigned variable" (D25).
  - an integer declaration, assignment or top-level `var X: i64` whose source starts with a vector call in parentheses:
    `(f(..)) + 1`, `((s.m())) + 1`, `(f(..) + 1)`. Error: the unwrapped spelling's "vector return type does not match the
    declared type" / ".. the assigned variable" (D26).
  - since RV-5r, also leading parentheses that close after an operator: `var x: i64 = (f(..) + 1) * 2;`. ⚠ This is
    beyond D26's text; D100 (2026-10-20) refuses a vector call wherever it sits.

  They computed with the vector's first word plus the rest: 1 on x86_64 / aarch64, 42 on cx / Windows. Bind the vector
  and read its lanes: `var w = f(..); x = load64(&w) + 1;`.
- In flight in 6.7.16: a vector call as a LATER operand (`var x: i64 = 1 + f(..);`, `x += f(..);`) and a whole vector call
  returned from a scalar fn or passed to an integer parameter. These are D100 / D101 (the user, 2026-10-20), the s16
  lane's SZ6, in this release; see that lane's block.

**RV-6 — an operator after a vector call is refused by name at a vector local and at an untyped declaration (D24, the user 2026-10-19; the vector destinations under 6.7.11's value-form rule)**
- Stops compiling: a declaration or vector assignment whose initialiser starts with a vector call followed by an operator
  — `var w = f(..) + 1;`, `var w: f64v2 = f(..) + 1;`, `w = f(..) + 1;`, `var w = s.m() * 2;`, `var w = (s.m()) + 1;`,
  and top-level `var w = f(..) + 1;`. This holds for every spelling of the call (by name, an explicit instance, a method,
  `callptr(&f, ..)`, wrapped), every operator and every vector width. The errors:
  - in a fn: "a value-form vector local is initialised only from .. - got `f`" (".. assigned only from ..",
    ".. got `s`", ".. got `(...)`");
  - at top level: "'f' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a
    fn".

  There is no vector `+`. x86_64 / aarch64 ignored the operator (the local held the call's vector), cx applied it to one
  lane, Windows refused it as a parse error ("expected ';', got '+'"), and the method spelling bound one word. Bind the
  vector, then compute with its lanes: `var w = f(..); var x = load64(&w) + 1;`.
- Unchanged: the whole call (`var w = f(..);`) at every destination; `var w: f64v2 = s.m() + 1;` keeps its refusal.

**RV-7 — `return f(..) + 1;` from a vector-returning fn is refused (no decision needed: the 6.6.6 return rule takes a local of the fn's vector type or a call declared to return it)**
- Stops compiling: in a vector-returning fn, `return f(..) + 1;`, `return f(..) * 2;`, `return f(..) == 1;` — any
  operator after a call declared to return the fn's own vector, by name or as an explicit instance. Error: "a
  vector-returning fn carries its result in a fixed register pair .. - got `f`". It never added anything on x86_64 /
  aarch64 (the call's vector was returned), cx added it to one lane, and Windows failed to compile it. Bind the call and
  return the local: `var w = f(..); return w;`. To change a lane, store it first.

**RV-12 — a `ret2(..);` right after a `case N:` / `default:` label is a two-value exit (within 6.7.14's D42, the user 2026-10-16; kept by 6.7.15's D62, the user 2026-10-18)**
- Stops compiling: a 3-name bind or 3-tuple capture of a fn whose two-value exits include a `ret2(..);` directly after a
  `case` / `default` label — in a switch, in a loop-ending switch, after an expression case value, in a method. The
  errors: "multi-value destructure binds 3 names, but 'g2' returns 2 values - bind 2 names: `var a, b = f(..);`" /
  "cannot capture 'g2' into tuple (i64, i64, i64) - it returns 2 values". The third name read whatever the third return
  register held (88 seeded in the filed repro). Bind two names, or declare the fn `: (T1, T2, T3)` and return three
  values.
- Unchanged: the two-name bind of the same fn.

**No block — a diagnostic changes, refused source now compiles, or the defect was the lane's own (nothing that compiled does anything else):**
- **RV-1:** a comparison, `!x`, `&&` / `||` argument into a tuple parameter (`take(1 == 1)`, `take(!0)`) is refused
  "cannot pass a bool …"; it said "an integer". An operator applied to one stays "an integer".
- **RV-3:** a literal argument that is no single expression (`take(1 < 2 < 3)`) gives the parse's error alone.
- **RV-6r:** a whole vector call followed by a stray token (`var w = mk2(41, 7) 5;`, `return s.m2() 5;`) gives the
  parse's error alone.
- **RV-8:** `ir_nop_harvest.sh` fails only on a larger IR=3 build (a gate).
- **RV-9:** the vector-call lookahead's cost; output byte-identical.
- **RV-10, RV-11, RV-10r, RV-15, RV-16:** a struct fn's or a vector fn's `return E;` reports E's own error alone, and its
  class refusal only when E parses. This covers `return zz;`, `return &(q);`, `return zz + 1;`, `return (zz, 1);`,
  `ret2(zz, 1);`, `return G;` of a vector global, and `return (1, 2, 3, 4);` (the class refusal alone).
- **RV-13:** an explicit-generic call of a name defined nowhere, `nofn<i64>(1)`, is "undefined function 'nofn'" once.
  `cyrius lint`'s `--syntax-only` pre-pass accepts a sibling module's generic called with explicit type arguments when
  every name in the list is a type here. That was a false syntax error, so a lint run that failed on it now passes. A
  list naming a type the file does not know (`g<Pt2>(x)` with a sibling module's struct) still reads as comparisons.
- **RV-14:** an `#inline` fn called inside a vector-returning fn (`store64(&w, one(40))`) compiles; it was refused
  ("… got `x`" at the callee's line).

#### Platform found by wave 1 — PE close of a negative fd and the Win32 errno table, macOS ENOSYS and getdents, the native TLS servers' ClientHello, timing tests under load (the p16 lane)

Each block names its CHANGELOG [6.7.16] bite (the p16 lane, PP-*). D75 – D83 are 6.7.16's, answered in the found
issues' round (the user, 2026-10-20: "D68–D93: all as recommended"). "6.7.16's D28 / D30 / D31 / D32" are the 6.7.16
open's (2026-10-19), and "6.7.14's D55" is cxvm's -38 for a call it does not serve. PP-4 needed no decision: it adds a
cxvm route one call at a time, as 6.7.15's PL-12 did.

**PP-1 — Windows: a close of a negative fd answers -9 and never reaches CloseHandle (D78)**
- Windows only. `sys_close(-1)`, `sys_close(-2)` and `file_close(-1)` answer -9 (EBADF), as on Linux and macOS. They
  answered 0: -1 and -2 are the current-process and current-thread pseudo-handles, which CloseHandle "closes" with
  TRUE.
- `file_close_r(-1)` is `Err(IoBadFd)`; it was `Ok(0)`.
- A cx guest's `close(-1)` on a Windows host answers -9; it answered 0.
- **Migrate:** a Windows program that closed a failed open's -1 and tested the result
  (`if (sys_close(fd) == 0)`) now reads -9 there, as on Linux. Do not close an fd you have not checked with `fd >= 0`.
  If you test a close, test `< 0` (the portable form), never `== 0` alone as "the fd was open".

**PP-2 — Windows: a failed mkdir / unlink / rmdir / ftruncate / truncate answers the negative errno (D79, D80)**
- Windows only. A failed `sys_mkdir`, `sys_unlink`, `sys_rmdir`, `xmkdir`, `xunlink` or `xrmdir` answers Linux's
  negative errno through the Windows error table. Each answered -1 for every failure. The answers:
  - an existing name: -17 (EEXIST);
  - a non-empty directory: -39 (ENOTEMPTY; macOS answers its own -66);
  - a missing path or parent: -2 (ENOENT);
  - access denied: -13.

  A path that is not valid UTF-8 still answers -1, because no Win32 call is made for it.
- `sys_ftruncate` answers:
  - -22 for a descriptor it cannot truncate: a pipe or console, a read-only one, and (Windows only; Linux truncates it)
    an O_APPEND one, whose handle has FILE_APPEND_DATA without FILE_WRITE_DATA;
  - -9 for a bad or closed fd;
  - another failure's own errno.

  Each was -1.
- `sys_truncate` answers its open's errno: -2 for a missing path. It was -1.
- The raw `syscall(0xF03F, h)` reroute (SetEndOfFile) answers 0 for success and -errno for failure. It was the BOOL:
  nonzero for success, 0 for failure.
- A cx guest's rmdir of a non-empty directory on a Windows host reads -39 (it read -1).
- **Migrate:**
  - Code that tested a Windows mkdir / unlink / rmdir / ftruncate / truncate result `== 0 - 1` (or `== -1`) for
    failure no longer matches: test `< 0`, or the specific errno. `xmkdir(d, m) == 0 - 17` now means "already exists"
    on Windows too.
  - A raw `syscall(0xF03F, h)` caller must read 0 as success: invert an `if (syscall(0xF03F, h) != 0)` success test to
    `== 0`. Prefer `sys_ftruncate`.
  - To truncate a file you opened O_APPEND on Windows, truncate by path (`sys_truncate`), or open it without O_APPEND.

**PP-2r — Windows: `sys_ftruncate` / `sys_truncate` of the null device answer -22 (D80)**
- Windows only. `sys_ftruncate` of a device such as `NUL`, opened for writing, answers -22, as Linux's ftruncate of
  /dev/null does. It answered -1 on real Windows, because SetEndOfFile's ERROR_INVALID_FUNCTION has no table row.
  Under wine it answered -9.
- `sys_truncate("NUL", n)` answers -22, as truncate of /dev/null does on Linux and macOS.
- Any ftruncate step whose Win32 failure the shared table leaves unmapped answers -22 (it was -1).
- macOS is unchanged: Darwin truncates its /dev/null by fd as a no-op and answers 0.
- **Migrate:** none beyond PP-2's `< 0` test. Do not test a Windows truncate failure against -1.

**PP-4 — cx: a guest's `sys_truncate` runs on the host (no decision: a cxvm route, 6.7.14's D55 one call at a time)**
- On cx, `sys_truncate(path, n)` acts on the host file on every host: 0 for a good truncate, the host's errno for a
  failed one. It answered -38 (ENOSYS) everywhere, while `sys_ftruncate` was served.
- **Migrate:** a cx program that tested `sys_truncate` for -38, or worked around it with open + `sys_ftruncate`, can
  drop the workaround. Run a `.cyx` on its own release's cxvm.

**PP-5 — macOS: `sys_prctl`, `sys_gettid` and `sys_sched_kicks` decline with -78, Darwin's ENOSYS (D76)**
- macOS only (both Macs). `sys_prctl(..)`, `sys_gettid()` and `sys_sched_kicks()` answer -78 where they answered -38.
  38 is Linux's ENOSYS, but on Darwin it is ENOTSOCK. Every other macOS decline, and the Mach-O syscall path's negated
  BSD errno, already answered in Darwin's numbering. Linux, Windows, agnos and cx are unchanged (cx `sys_gettid()` is
  still -38).
- **Migrate:** macOS code that tested any of the three against `0 - 38` for "not implemented" now reads -78 there. Test
  `< 0`, or the host's ENOSYS: sigil's `ENOSYS` is 78 on macOS.

**PP-6 — macOS: `xgetdents` answers the records that fit, then -22 (D77)**
- macOS only. `xgetdents(fd, buf, n)` with `n` under 1048 bytes answers as Linux's getdents64 does: the whole records
  that fit in `n`, then -22 (-EINVAL) when the next record does not fit.
  - On macOS 27 such a loop read 0, a false end of directory that lost the entry and every one after it.
  - On macOS 13 a buffer no record fits never returned: the process spun unkillably in the kernel.
- `n` under 64 is -22. `n` of 1048 or more passes straight through, as before.
- A /dev (devfs) listing under 1048 bytes may end early with -22 (ecb: 96 bytes ends after 591 of 634 entries). It
  never repeats an entry.
- **Migrate:**
  - Treat -22 from `xgetdents` as "the next record does not fit — grow the buffer", as on Linux. Do not read it as a
    hard error.
  - Or list with a buffer of 1048 bytes or more (`lib/fs.cyr`'s listers pass 4096).
  - A loop that stopped at 0 with a small buffer on macOS now sees -22 before the end; keep 0 as the end of the
    directory.

**PP-7 — native TLS 1.3 server: a ClientHello extension block ending in a 1 – 3 byte partial entry is refused (D81)**
- `tls_native_accept` / `tls_native_server_respond_hello` refuse a TLS 1.3 ClientHello whose extension block ends in
  1 – 3 bytes after its last whole extension. They return `TLS_ERR_BAD_HANDSHAKE` and send decode_error. The hello
  used to be answered with a ServerHello. The 1.2 server already refused this shape (6.7.16's D32).
- **Migrate:** nothing for a program. Real clients (OpenSSL `s_client`, browsers) send no such hello, and the OpenSSL
  interop gate is unchanged. A hand-built or fuzzing client must end its block on a whole extension.

**PP-8 — native TLS servers: a ClientHello naming an extension type twice is refused (D82)**
- The native 1.2 and 1.3 servers (`tls_native_accept`, `tls_native_accept_12`, `tls_native_server_respond_hello`,
  `tls_accept*` on the native backend) refuse a ClientHello that names an extension type twice. They return
  `TLS_ERR_HANDSHAKE_FAILED` and send illegal_parameter (RFC 5246 §7.4.1.4 / RFC 8446 §4.2). They negotiated on the
  first copy.
- A block that also fails to frame stays decode_error.
- **Migrate:** nothing for a program; the fix is on the client. A test harness that duplicates an extension to probe a
  server now gets the alert instead of a ServerHello.

**PP-9 — native TLS servers: compression_methods without the null method (1.2), or other than the single null method (1.3), is refused (D83)**
- The native 1.2 server refuses a ClientHello whose compression_methods list has no 0 anywhere. The native 1.3 server
  refuses one whose list is anything but exactly `01 00`. Each returns `TLS_ERR_HANDSHAKE_FAILED` and sends
  illegal_parameter. They negotiated, and the ServerHello named a method the client never offered.
- An empty 1.3 list is decode_error (`TLS_ERR_BAD_HANDSHAKE`): it does not parse (`<1..2^8-1>`). The 1.3 server used
  to skip the list unread.
- Lists that do not frame keep decode_error, as before (6.7.16's D32).
- **Migrate:** nothing for a program. A client must offer the null method (1.2) or exactly the one null method (1.3);
  every real client does.

No block for:
- PP-3: the Windows CLI's message for a missing %TEMP%; it fails either way.
- PP-10: docs.
- PP-11 – PP-13, PP-15: tests and gates.
- PP-14, PP-17 – PP-19: tests that name a not-run row on cx, wine or qemu, and docs.
- PP-16, PP-16r, PP-2r2: comments and the guide.

#### Tools found by wave 1 — exec_cmd on Windows, the language server's unit notes, cycc_cx on agnos, the Windows CLI's sign-efi and cyriusly, `--target=js` on arm64 macOS (the t16 lane)

Each block names its CHANGELOG [6.7.16] bite (the t16 lane, TT-*). D84 is the user's decision at 6.7.16's found issues'
round (2026-10-20); D50 is 6.7.16's at the open (2026-10-19); "6.7.12's D5 / D20" are the 6.7.12 open's. Everything else
is fixed to what the source says. No language rule changes in this lane, and no compiler output changes for a program
that compiled: the src/ changes are the agnos cx compiler's (which compiled nothing before) and the preprocessor's
refused-map message.

**TT-12 (+ TT-12r) — the Windows `cyriusly.exe` refuses `install`, `update`, `setup`, `uninstall`, `cmdtools` and `use --global` by name (D84, the user 2026-10-20: "Ship it; those verbs refuse by name"; ⚠ the kept verbs' hints and the read-only answers' order go beyond D84's text)**
- Changes what the tool does, Windows only: each of the six verbs now prints `cyriusly: <verb> is not available on
  Windows: <why>` and what to do instead on stderr, and exits 1, before any output or change — `install` and `use <v>
  --global`: the `powershell -ExecutionPolicy Bypass -File install.ps1 -Tarball cyrius-<v>-x86_64-windows.tar.gz`
  command; `update`: the releases URL and the same command with `<version>`; `setup`: install.ps1 `-Tarball` / `-Stage`;
  `uninstall`: `rmdir /s /q "<home>\versions\<v>"`; `cmdtools`: the prompt integrations are the POSIX shell twin's. `use
  --global` with no version is refused the same way (it was `--global needs a version: 'use <ver> --global'`, rc 1).
  Before (a `cyriusly.exe` built from the 6.7.15 source; the 6.7.15 Windows tarball shipped none): `install` printed
  "Installing Cyrius <v>..." and exited -1, `update` failed in cmd.exe (rc 255), `uninstall` printed "rm -rf failed",
  `cmdtools` refused every `C:\…` home, and `use <v> --global` failed and left a `bin.cyrtmp.<pid>.<n>` link in
  `<home>`.
- Unchanged, and still first: a malformed version operand (`install ../versions` → "not a version"), the active-version
  guard of `uninstall`, and `uninstall` of a version that is not installed ("Version <v> not installed.", rc 0) answer
  before the refusal.
- Changes what the tool prints (the kept verbs): `list` of an empty store, `use <v>` of a version not installed, `use
  <v>` outside a project and `uninstall` of the active version name install.ps1 (they named `cyriusly install`,
  `--global` or `cyriusly use <other>`); `--help` gains a two-line Windows note. `list`, `version`, `which`, `home`,
  `use <v>` (the project pin), `--help` and `--version` work (where they look for the install: TT-14).
- **Migrate:** install a release, or switch the active version, by running `install.ps1 -Tarball
  cyrius-<v>-x86_64-windows.tar.gz` from the tarball's top level; remove a version with `rmdir /s /q
  "%USERPROFILE%\.cyrius\versions\<v>"` (or under your `CYRIUS_HOME`). A script that ran these verbs on Windows and read
  rc -1 / 255 / 0 now reads 1. POSIX `cyriusly` is unchanged by this block.

**TT-14 — the Windows `cyriusly.exe` finds its install at `%USERPROFILE%\.cyrius` (no decision: D84 keeps `list` / `version` working, and on a default install they did not; ⚠ beyond D84's text where `HOME` is set)**
- Changes what the tool does, Windows only: with `CYRIUS_HOME` unset, the home is `%USERPROFILE%\.cyrius` —
  install.ps1's default, and the CLI's — ahead of `HOME`. Before, it read `HOME`: unset on a plain console, so every
  verb looked in `/root/.cyrius` (`version` printed `cyriusly none`, `list` nothing installed); set under an ssh session
  or a POSIX shell, so the home was `$HOME/.cyrius`.
- Changes what the tool prints: `cyriusly which` prints `<home>\bin\cycc.exe` (it printed `<home>/bin/cycc`, a file no
  Windows install has).
- **Migrate:** nothing for an install.ps1 install in the default place. If your store lives elsewhere — under an ssh
  `HOME` that differs from `%USERPROFILE%`, say — set `CYRIUS_HOME` to it; `CYRIUS_HOME` still wins. A script that
  parsed `which`'s output gets the backslashed `.exe` path.

No block for the lane's other bites:
- TT-1: a test (`crossos/exec_cmd_forwards_environment.tcyr` asserts W1 / W3 / W4 in a PE build); the cass leg is green.
- TT-2: cyrius-lsp's unit note follows the unit — an editor's diagnostics only, and the unit note itself is new in
  6.7.16 (the tools lane's T5). An open fragment whose own error was fixed while the unit still has another shows the
  note (it showed an empty list).
- TT-3: comment and line-wrap changes; the server's protocol bytes are identical.
- TT-4: on every target a preprocessor buffer the kernel refuses is named — `error: cannot map the preprocessor's 24 MiB
  source buffer`, exit 1 — where the compile crashed; nothing that compiled changes.
- TT-5, TT-7, TT-8, TT-9, TT-9r, TT-9r2, TT-10 — the agnos `cycc_cx` (`CYRIUS_TARGET_AGNOS=1 cycc < src/main_cx.cyr`)
  compiled nothing before TT-4 (every compile died in the preprocessor), so no existing build changes. It now compiles,
  reads `--version` / `--syntax-only` off the init stack, opens its includes with agnos `open` (#7), honours the
  `CYRIUS_*` variables in its environment (the first 256 entries; a name past them reads as unset), and runs the
  toolchain pin check (6.7.12's D5: a drifted cyrius.cyml pin warns, fails under `CYRIUS_STRICT_PIN=1`, is silent under
  `CYRIUS_NO_WARN_PIN_DRIFT=1`). Agnos builds of src/main_cx.cyr and src/main.cyr no longer print the four "duplicate
  symbol 'SYS_*'" warnings. Verified under the local fake agnos kernel only, not on agnos.
- TT-6: the fake agnos kernel (a test fixture).
- TT-11 (+ TT-11r): `cyrius sign-efi` on Windows runs the `cyrsign-efi.exe` beside `cyrius.exe` and exits with its code
  (it always failed, rc 127). On every target a missing helper still exits 127; its message is reworded — `sign-efi: the
  cyrsign-efi helper is not installed at <path> (build it with `cyrius build programs/cyrsign-efi.cyr
  build/cyrsign-efi`)` (it said "cyrsign-efi helper not found (Linux-only; …programs/cyrsign_efi.cyr…)") — and on POSIX
  an installed helper that cannot be exec'd says `could not run <path> (execve error N)`. A script matching the old text
  matches `the cyrsign-efi helper is not installed at`.
- TT-13 (+ TT-13r): cyriusly's atomic switch removes its temporary link as a link on Windows; no verb reaches it there
  (TT-12 refuses `use --global` first) and POSIX is unchanged.
- TT-15: on arm64 macOS `cyrius build --target=js <in.ts> <out.js>` with no selector writes the JavaScript (D50; it was
  refused, rc 1, "runs this host's cycc, not the compiler another target selector chose"); `--aarch64 --target=js` is
  still refused on every host (6.7.12's D20). Nothing that worked changes.
- TT-16: the POSIX `cyriusly` hints say `cyriusly use <v> --global` (the uninstall-active guard, `update`'s Run line),
  where they said `cyriusly use <v>` — which pins the project since v5.11.26 and switches nothing — and help lists `use
  <version>` (pin this project) and `use <ver> --global` (switch the active version) apart. Printed text only.
- TT-17: `cyriusly update` compares the active version of the install it manages (`CYRIUS_HOME` honoured, as `cyriusly
  version`); with `CYRIUS_HOME` set it said "Update available: none -> <latest>" for a version already active. With
  `CYRIUS_HOME` unset, `~/.cyrius` as before.

#### What waves 1 and 2 found in the frontend and the generic signatures — intrinsic statements, refusals that swallow the next statement, enum members and qualified names, tuple literals, `Str` typed-pointer warnings, per-item `private`, derive steps, type arguments on calls, members, enums, handles, tuples and slices, struct field separators, trait members' fn-pointer and type-parameter shapes, multi-value struct elements (the f16 lane)

The decisions are the user's at 6.7.16's found-issue round (2026-10-20, "D68–D93: all as recommended": D68, D69,
D88 – D93). "6.7.16's D7 / D8 / D11" are the 6.7.16 open's (2026-10-19); "6.7.15's D4 / D6 (a)" and "6.7.13's D18 (a)"
are those releases' opens. Each block names its CHANGELOG [6.7.16] bite. Every change below is in the frontend: the same
on x86_64, aarch64, cx, PE and Mach-O. No in-tree source stops compiling but the fixtures named at FF-33, and one test
gains FF-21's warning (the 913-file compile differential).

**FF-4 — `.field`, a field store and `.m()` on a scalar global are refused with the local's words (D68, the user 2026-10-20)**
- Stops compiling: `g.d`, `g.d = 9;`, `g.d += 1;` and `g.m()` on a global declared `i8`..`u32` — "no struct type in scope
  for 'g'; a '.field' access needs its struct declaration (missing include?)" (the assignment and method wordings for a
  store and a call). Through 6.7.15 they compiled and read or wrote the global through an unrelated struct: the one
  declared at the number of the type's byte width (`g.d` on an `i32` with four structs read the 4th struct's `d`). No such
  program meant it.
- Starts refusing instead of crashing: the same on an `f64` / `f32` global crashed the compiler (rc 139, no diagnostic);
  it is now that one error.
- **Migrate:** declare the global with its struct type (`var g: S = S { .. };`) or reach it through a `*S`. An `i64` /
  `u64` / `bool` global and a local were refused already.

**FF-21 — `p = str_from(..);` into a `*P` local warns (no decision: the declaration form already warned)**
- A new warning: a value assigned into a `*T` local or a `p: *T` parameter whose declared type is not T — `p =
  str_from(..)` into a `*P` (a `Str` header's address bound to a `*P`: `p.b` read the length), `q = str_from(..)` into a
  `*i64`, `h = mkq();` (an 8-byte struct's word) / `h = mkh().n;` / `h = str_from(..) + 0;` into a `*Str` — warns
  "assigning non-pointer to typed pointer", as `var d: *P = str_from(..);` and a `*P` global's assignment did. A warning
  only: no exit code or binary changes (cyrius has no warnings-as-errors mode).
- Unchanged: a `: Str` call, a call's `Str` field or a call's `Str` method into a `*Str`, a `: P` call copied through a
  `*P`, and any struct call into a handle (`var a: P3 = ..`; a rebind at any type).
- **Migrate:** the warned line binds the `*T` to something that is not a T: if it meant the other struct, declare the
  local with that struct's pointer type (`var p: *Str` for a `str_from(..)`); if the value is a word (an 8-byte struct's,
  an i64 field), the local should not be a `*T`. tests/tcyr/crossos/struct_receive_paren_call.tcyr:423 (`p = mk1();` into a `*i64`) gains this warning.

**FF-24 — a classic-for step into a `*T` warns (6.7.13's D18 (a): the warning at every `*T` site)**
- A new warning: `for (..; ..; p = 7)` — a step assigning a non-pointer into a `*T` local, parameter or global, or a
  struct handle, at top level too — warns "assigning non-pointer to typed pointer" at the step's `)`, as the same
  assignment as a statement always did. A warning only.
- Unchanged: `p = 0`, `p = (0)`, a string literal, a pointer, `&s` and a `: Str` call into a `*Str` stay quiet; a compound
  step (`q += 0`) is not warned.
- **Migrate:** as for the statement form — assign a pointer, or drop the `*T`.

**FF-33 — a struct's or a union's fields are separated by `;` (D69, the user 2026-10-20)**
- Stops compiling: a field that follows another with no `;` — `struct P { a b }`, `struct Q { x: i64 y: i64 }`, `union U {
  a: i64 b: i32 }`, one field per line with no `;` — "expected ';' between struct fields" ("... union fields") at the
  second field, once per declaration. Through 6.7.15 each compiled, every field at the offset the separated form gives.
  `cyrius lint` reports it too.
- Unchanged: the last field may omit its `;` (`struct P { a; b }`); a `,` between fields is still "expected identifier,
  got ','".
- **Migrate:** add the `;` after every field but the last; the layout does not change. cyrius's own tree had one fixture
  (tests/tcyr/derive/derive_body_shapes.tcyr) and two gate fixtures written in shell strings; each gained its `;`s.

**FF-42 — a trait member's own third type parameter is refused at the member (D92, the user 2026-10-20, extending 6.7.16's D8)**
- Stops compiling: a bodiless trait member declaring three type parameters — `trait T { fn g<A, B, C>(self, a: A, b: B,
  c: C): i64; }` — "a third type parameter 'C': a generic takes at most two type parameters", once, at the member's C, in
  source order with a fn's and a struct's, under `cyrius lint` too. It compiled, and so did an impl declaring `<A, B>`
  for it. A member with a default body was refused already (once, unchanged).
- **Migrate:** declare at most two type parameters (the guide's two-slot model): pass the third as a fixed type, or split
  the member.

**FF-45 — a tuple element given type arguments is refused at the element's name (D93, the user 2026-10-20, extending 6.7.15's D6 (a) / 6.7.16's D7)**
- Stops compiling: a tuple element written `i64<..>`, `f64<..>` or `bool<..>` — `var v: (i64<u8>, i64)`, a `(i64<u8>,
  f64<i32>)` struct field, a `(bool<u8>, i64)` global, a tuple parameter — "'i64' takes no type arguments", one line per
  element, at its name. The list was skipped unread (the same tuple as a trait member's parameter or a multi-value return
  was refused already). Silent under `cyrius lint`.
- **Migrate:** delete the `<..>`; it was ignored.

**FF-46 / FF-52 — a struct value over 8 bytes as a multi-value `return ( .. )` element is refused (D90, the user 2026-10-20)**
- Stops compiling: `return (b, 5);` in a multi-value fn — declared `(Pt, i64)`, `(i64, i64)` or undeclared — where `b` is
  a struct VALUE over 8 bytes (an inline local, a by-value parameter, a value global, a by-value field `w.v`, `*p` /
  `**pp`, a struct-returning call, method or operator, `((b))`): "'mv' returns struct 'Pt' (16 bytes) as a multi-value
  element - return its pointer, or its fields as elements", once, at the element. Through 6.7.15 it compiled and handed
  back only the struct's first word (`b.y` was lost; passing the binding on as a `Pt` faulted).
- Unchanged: the `(Pt, i64)` declaration itself, a word element, an 8-byte struct element (one word), `&b`, a `*Pt`, `b.x`,
  a `Str`, and a HANDLE named whole — a struct local initialised from an address (`var a: H = alloc(16);`, `var h: Pt =
  w;`) or a pointer-mode global, whose word is the struct's address (FF-52).
- **Migrate:** return `&b` (declare the element `*Pt`) or return the fields as separate elements (`return (b.x, b.y, 5);`).

**FF-49 — a type-argument list after an enum, `Result`, `Option`, `Tagged` or `cstring` is judged by what the name declares (D88, the user 2026-10-20; ⚠ the argument-kind refusals in a read list go beyond D88's text)**
- Stops compiling: `Color<..>` (an enum declaring no type parameters, above or below its use), `Option<..>`,
  `Tagged<..>`, `cstring<..>` and a program's own `enum Result` written without `<..>` given a list — "'Color' takes no
  type arguments", once, at the name, in every position (a local, a global, a parameter, a return, a by-value / pointer /
  union field, `*X`, `**X`, `*fn(X)`, a trait member, a multi-value element, `[X]`, `slice<X>`, `Vec<X>`, `Box<X>`, `sizeof`,
  `#assert`, an impl). Through 6.7.15 the list was stepped unread. Silent under `cyrius lint`.
- Stops compiling: a `Result<..>` list (lib/result.cyr's `enum Result<T, E>`, two parameters also when no enum declares
  it) and an enum's own declared `<..>` list are now READ — a name that is no type ("unknown type 'Nope' as a type
  argument"), D7's `Pt<i64>` inside it, and a third argument to Result (D5's "'Result' takes 2 type arguments, 3 given")
  are refused. ⚠ So is an argument the type-argument reader does not take — a pointer (`Result<*Pt, i64>`), an enum
  (`Result<i64, Color>`), another handle (`Result<i64, Option>`), `u8`..`u64` or `bool` (`Result<u8, i64>`) — each
  compiled with the list ignored; D88's text named only an unknown name and a third argument (measured at the docs pass;
  no in-tree source writes one).
- Stops compiling: a trait member whose return names no type inside such a list, against an impl's different return — the
  filing's `trait T2 { fn sh(self): Result<Nope>; }` / `fn sh(self): i64` compiled (exit 4); it is the member reader's
  line. And a member's own `: U<Nope>` (a type parameter given a list) against an impl's `: i64` compiled — the impl check
  counted the unread `Nope` as a refused side — and is now the impl's "returns .., trait declares .." line (6.7.15's D4).
- Starts working: `fn g(): Result<i64, Pt>` (and `: Result<T, E>`, an impl method's `: Result<..>` return) — a parse
  error with a cascade through 6.7.15 — compiles; a `Result<i64, Pt>` list naming a struct declared further down compiles.
- **Migrate:** delete the `<..>` after an enum that declares none, `Option`, `Tagged` and `cstring` — it was ignored. In a
  `Result<..>` list write type arguments (a struct, `i8`..`i64`, `f64`, a type parameter in scope), at most two; a list
  that named a pointer, an enum, a handle or an unsigned type meant nothing (the handle is 8 bytes whatever it holds) —
  write `Result<i64, E>` or drop the list.

Nothing to migrate (diagnostics on code that never compiled, refused code that now compiles, gates, or a debug flag):
FF-1, FF-2, FF-10, FF-23, FF-25, FF-38, FF-39, FF-43 and FF-47 (gate files: ir_nop_harvest.sh's rows and its
`bash -eo pipefail` FAIL lines, D11's axis 5 on six legs, corpus floors, axis labels, wine teardowns, pipefail-safe greps,
D90's NR rows); FF-3 (`mulh64(2, 3).n = 5;` / `sizeof(H).n;` as a statement is the one "expected ';', got '.'", no
undefined-fn lines); FF-5 (a refused `#assert` ends at its line; `{ #assert 1 == 1 }` is its one refusal, `{ #assert 1 ==
1, "m" }` "#assert: expected `;` or a line break before `}`"); FF-6 and FF-7 (an error in a block head's header no longer
swallows the block's second statement; a body written without braces is one "expected '{', got ..." and the enclosing
`}` is kept); FF-8 and FF-9 (a refused top-level `var c: S;` declares `c` as reported; a zone `var g: f64v2;` is one
error); FF-11 – FF-14, FF-18 – FF-20 and FF-12r (a refused enum, struct, union, trait header, or fn / impl signature over
an empty body ends its latch at its own `}`: the later declarations report their own errors; a refused enum member
registers nothing; a `)` / `]` closing nothing at the top level is "unexpected ')'"; "too many struct definitions" is said
once); FF-15 (`Color.NOPE` is "'NOPE' is not a variant of 'Color'" in every context); FF-16 (a tuple literal as a struct
literal element is R9's one error — `cyrius lint` now lints such a file, rc 0, where it called it unparseable; the full
compile still refuses); FF-17 (an untyped `var t = (1 2);`'s uses add nothing); FF-22 (a `: Str` field, a `Str` name, a
call result's `Str` field or method, and whole-wrapped spellings into a `*Str` declaration, global or local no longer
warn — fewer warnings, no exit code changes); FF-26 (a per-item `private` below module scope is one error; the marker is
stepped); FF-27 and FF-27r (a refused struct's / enum's derive step takes only the fns that derive emitted); FF-28,
FF-28r and FF-29 (a use before a declaration refused in a body, and a zone const context naming a late enum, add no
second error; a valid forward zone reference's "unknown name 'E' in a const context" now prints after the other pass-1
reports above the first statement — a script matching error lines in order reads the new order); FF-30 (a non-`fn` impl
member is "an impl body holds only `fn` definitions"); FF-31 and FF-32 (`x.m<i64>(1)` on a receiver with no struct, and a
type-argument list on an intrinsic or builtin, are one error); FF-34, FF-35 and FF-53 (field-type and type-argument
refusals reported at the name — a script matching their columns reads the new column); FF-36 (`cyrius lint` reports an
impl whose return differs from a member's `: u8` / enum / `Pt<i64>` return again, as 6.7.15 did); FF-37 (forming a dyn
adds nothing beside the impl's own parameter-count refusal); FF-40 and FF-44 (a fn's `*fn( .. )` return and a bodiless fn
signature are one error each); FF-41 (a trait member takes a bare `*fn` / `**fn` parameter — newly accepted); FF-48 and
FF-48r (`[Box<i64>]`, `slice<Box<i64>>` and `[*Box<i64>]` declare — newly accepted; a subscript read of an element of any
width but 1 / 2 / 4 / 8 / 16 bytes is refused by name, read it at `slice_ptr(&s) + i * sizeof(T)`); FF-50 and FF-51
(under the `CYRIUS_MONOMORPH=0` debug flag the cx, native aarch64 and aarch64 Mach-O compilers step type-argument lists in
pass 1, and a return, a by-value or union field and a slice element step them — default mode unchanged).

#### FG4 — a closure capture named like a struct global (D96), a generic's untyped local from a T value (D102), `**B` fields to a struct declared below (D103), the saturating / checked operators' integer result (D104) (the f16b lane, split from f16 in wave 4)

The decisions are the user's in 6.7.16's wave-3 round (2026-10-20: "D96–D105: all as recommended"). Each block names its
CHANGELOG [6.7.16] bite. Every change below is in the frontend, so it is the same on x86_64, aarch64, cx, PE and Mach-O.

**FB-1 — a closure's capture named like a struct global shadows it for `.field`, a field store and `.m()` (D96, the user 2026-10-20)**
- Stops compiling: inside a closure, `.field`, a field store or `.m()` on a captured name that has no struct type, when a
  global of the same name is a struct. This covers `+=`, `++`, a chain `x.a.b`, `x.m<i64>(..)`, `x.0` and `x.a[0]` too.
  It applies to an untyped capture (`var x = 5;`), an `i64` capture, an untyped `var x = &q;` capture, and a nested
  closure's capture of a capture. The error is *no struct type in scope for 'x'* (the field, assignment or method
  wording), as the same line gets outside the closure.
- Through 6.7.15 the closure's `.field` read or wrote the GLOBAL, while `x` alone in the same closure read the capture:
  `var x = 5; |k| x.a + k` beside `var x = Q { 7, 8 };` gave 7.
- **Migrate:** if you meant the global, rename the local (or the global) so that the closure does not capture its
  name, or read the global outside the closure into a typed local. If you meant the captured value, give the local a
  struct type (`var x: Q = ..`), or a `*Q` for a pointer. A struct-typed capture reads its own copy, and a closure that
  captures no `x` reads the global, both unchanged.

**FB-4 — the saturating / checked `+| +? -| -? *| *?` give an integer result whatever their right operand (D104, the user 2026-10-20)**
- Changes what it computes: when one of the six has an f64 right operand, its result is now an integer. So the next
  operator is an integer operation, with no warning: `(n +| x) * 3`, `(n +| x) + 1` and `(n +| x) < 3` with `x: f64`.
  Through 6.7.15 the result kept the f64 type of its right operand. The next operator took its f64 arm — a float
  multiply of the sum's bits, warned *f64 arithmetic with a non-f64 right operand* — and the comparison warned
  *comparison mixes f64 and integer operands*. With x = 1.5, `(2 +| x) * 3 & 255` was 5 and is now 6.
- Changes what tools print: those two warnings are gone. `take(2 +| 1.5)` into a tuple parameter is refused as *an
  integer* (it said *an f64*). An operand's own mix still warns (`2 +| x * 3`: the `x * 3`).
- **Migrate:** nothing to rewrite where integer arithmetic on the saturated / checked result was meant (the guide
  always said only `+ - * /` keep an f64 right operand's type). The six operators have no f64 form, and their result
  was the integer helper's word all along. If a float result was meant, compute it with `+ - * /` on f64 operands. No
  program in the corpus has the shape.

No block (nothing that compiled changes):
- FB-2 and its review fixes FB-2r / FB-2r2 (D102). A generic's untyped `var y = x;` holding a `T` value now takes `T`'s
  type in each instance, so a body using it as a struct newly compiles at a struct `T` or when never called. A scalar
  call of such a generic is refused at the call with the stub's words and a note; it was refused at the definition.
  The workaround `var y: T = x;` can stay.
- FB-3 (D103). A `**B` / `**G<B>` / `***B` field to a struct declared below newly compiles. `**B<i64>` (B no generic,
  below) is still refused, now with D7's words "'B' is not a generic struct: it takes no type arguments".
- FB-5. A 16-byte handle as a multi-value element returns its pointer, as through 6.7.15. It narrows lane f16's D90
  refusal to struct values.
- FB-6, FB-7 and FB-4r. A file move, a gate and a comment.

#### What waves 1 to 3 found in structs and the declaration zone — `Str` sources and destinations, narrow parameters and signed globals, `*(&f)`, redefined fns, `--syntax-only` stores, the zone's replay and generic instances, struct globals from pointers, generic operator fns, a pointer to another struct (D97), the zone's f64 destructure (D98), `*p = mkp()` (D99), a vector call as an operand or a scalar value (D100 / D101) (the s16 lane)

The decisions are the user's: D70 – D74 and D85 – D87 at the found issues' round (2026-10-20), D97 – D101 at wave 3's
round (2026-10-20), and D1, D16 (a), D17 (a), D18 (a), D19, D20 and D21 at the 6.7.16 open (2026-10-19). Ids from other
releases are written with their release ("6.7.15's D16", "6.7.14's D27 (a)", "6.7.13's D7 (1)"). Each block names its
CHANGELOG [6.7.16] bite. Every change below is in the frontend: the same on x86_64, aarch64, cx, PE and Mach-O.

**SS-3 — a redefined fn's `: *T` return records are its last definition's (no decision: last definition wins, 6.6.20)**
- Changes what it computes: only a program carrying the `duplicate fn ... last definition wins` warning. A call to such
  a fn — above, between or after the definitions — now steps and type-checks by its LAST definition, as the warning
  always said. With `fn gp(): *H` then `fn gp(): i64`, `gp() + 1` is 101 (it stepped `1` by sizeof(H): 124).
- Stops compiling: `gp().b = 5;` / `gp().b` when the last definition returns no struct pointer — "cannot take a field of
  the result of 'gp': it does not return a struct". It stored or read through the integer (`gp().b = 5` faulted).
  `cyrius lint` refuses `gp().n = 5;` for `fn gp(): *Foo` then `fn gp(): Foo`.
- **Migrate:** delete the earlier definition (the warning names it), or give the definitions one return type.

**SS-4 — a redefined fn's `bool` return and parameters at a call are its last definition's (no decision: last definition wins)**
- Stops compiling: a `bool` binding or argument at a call between two definitions that matched only the EARLIER one
  (`fn f(): bool` then `fn f(): i64`, `var x: bool = f();` between) — "cannot initialize bool 'x' with a value that is not
  a bool" / "cannot pass a value that is not a bool to bool parameter 'b'".
- Starts working: the reverse — a call between that matches the last definition — which was refused.
- **Migrate:** delete the earlier definition, or bind the call as the last definition declares it.

**SS-8 — `*p` of a `*Str` into a `Str` field, a literal's `Str` field or a `: Str` return is p (6.7.16's D20, the user 2026-10-19, carried to a field and a return)**
- Changes what it computes: `w.s = *p`, `GW.s = *p` (through a `*W`, nested, a for step, at top level, `**pp`),
  `W { *p, 1 }` and `return *p;` from a fn returning `Str` now hold p, the header's address, as `v.s = p` does. They
  stored the header's DATA word as the handle, so `str_len(w.s)` read the string's bytes as a header.
- **Migrate:** nothing to rewrite — the data word was never a valid handle. To keep a copy of the string, `str_new(..)`.

**SS-9 — a literal's `*Str` element from an inline `Str` (D19, the user 2026-10-19, carried to the literal)**
- Changes what it computes: `W { gt, 1 }` (gt a global's or a capture's inline `Str`, `p: *Str`) — named, a nested leaf,
  in a fn, the zone and after a statement — holds gt's header address (`str_len(w.p)` 7); it held gt's data word (0).
- Stops compiling: `W { t, 1 }` with t a fn's own inline `Str` — "cannot store the inline Str 't' into a field - its
  header lives in this frame and would dangle (store a handle: str_new(data, len))", as `w.p = t` is.
- **Migrate:** build a handle (`str_new(t.data, t.len)`) or use a global.

**SS-10 — `var u: Str = *pp;` is a copy (D74, the user 2026-10-20; at top level D17 (a) / D18 (a), 2026-10-19)**
- Changes what it computes: `var u: Str = *pp;` (pp a `**Str`; also `(*pp)`, a parameter's, a capture's, `*GPPS`,
  `*gpps()`, `*w.pp`, `**ppp`) is u's own copy of the header, as `var u: Str = p;` is. It was a handle on the header, so
  a later write through either showed in the other. At top level (zone and after the first statement) `var U: Str =
  *GPP;` and `var V: Str = GP;` (GP a `*Str` global) copy too.
- **Migrate:** to keep the alias, declare the pointer — `var u: *Str = *pp;` / `var V: *Str = GP;`.

**SS-11 — `*p` of a `*Str` into a `*Str` slot is p (D73, the user 2026-10-20, applied to every `*Str` slot)**
- Changes what it computes: `*q = *p` makes q's first word p (the header q points at keeps its own length), as
  `*q = *pp` and `*q = gt` already stored an address. The same for `**qq = *p`, `*pp = *p`, `x = *p` / `GX = *p` into a
  `*Str` name, `var y: *Str = *p;` (in a fn, the zone, after a statement), `w.p = *p`, `WP { *p, 1 }`, `fps(*p)` into
  `s: *Str` and `return *p;` from a `: *Str` fn. Each stored the header's data word (the names and the declaration with
  a false "assigning non-pointer to typed pointer").
- **Migrate:** to COPY the header through q, write `q.data = p.data; q.len = p.len;`.

**SS-13 — `*(&t)` of an inline `Str` is t (D71, the user 2026-10-20)**
- Changes what it computes: `var h: Str = *(&t);` (and untyped `var h = *(&t);`) is a handle on t's header;
  `f(*(&t))`, `fp(*(&t))`, `gg<Str>(*(&t))`, `gg(*&t)`, `h.eq(*(&t))` pass the header; `u = *(&t)` copies it;
  `k = *(&t)` rebinds k to t; `p = *(&t)` / `var p: *Str = *&t;` take its address. They took t's data word. `*(&t) = v`
  is `t = v` — it copies the header (it wrote one word into t.data).
- Stops compiling: through `*(&t)` of a fn's own inline `Str`, everything `t` itself is refused for — `return *(&t);`
  from a `: Str` fn, `G = *(&t);`, `w.s = *(&t);`, `*ps = *(&t);`, `*pp = *((&t));`, `W { *&t, 1 }`, `GP = *(&t);`,
  `w.p = *(&t);` — and `*(&t) OP= v`, refused as `t OP= v`.
- **Migrate:** write `t` (it is the same value); store a handle (`str_new(t.data, t.len)`) where a frame's header would
  dangle.

**SS-14 — an inline `Str` returned from a fn returning `*Str` (6.7.15's D16 and 6.7.13's D7 (1), carried to the return)**
- Changes what it computes: `return gt;` (and `((gt))`, `*(&gt)`, a method's) from a `: *Str` fn returns gt's header
  address; it returned gt's data word.
- Stops compiling: `return t;` of a fn's own inline `Str` from a `: *Str` fn — "cannot return the inline Str 't' from a
  fn returning *Str - its header lives in this frame and would dangle ...".
- **Migrate:** return a handle (`str_new(t.data, t.len)`), or return a global's.

**SS-15 — a signed narrow global declared after the first top-level statement reads sign-extended (no decision: as in the declaration zone)**
- Changes what it computes: an `i8` / `i16` / `i32` global declared after the first top-level statement (or in a
  top-level block) holding a negative value reads negative — `Z = 1; var GS: i16 = 0 - 2;` is -2 (it was 65534; an
  `i32` 4294967294, an `i8` 254) in a read, a comparison, arithmetic, an argument and `*(&GS)`.
- **Migrate:** if code compensated for the zero-extension (masking, adding 65536), drop the compensation.

**SS-16 — a narrow parameter is narrowed in the fn (D72, the user 2026-10-20) — with SS-18**
- Changes what it computes: a parameter declared `u8` / `i8` / `u16` / `i16` / `u32` / `i32` (and a generic `x: T` bound
  to i8 / i16 / i32) holds its type's value: `wid(0x1FF)` with `y: u8` reads 255 (it held 511), `w32(0x1FFFFFFFF)` with
  `y: i32` -1, an `i16` 32767 `+= 1` wraps to -32768 — through a fn pointer, a stack-passed parameter, an `#inline`
  replay, a capture, a method, a default, `#regalloc` and a non-suspending `async fn` alike. The caller still passes the
  whole word; the callee narrows.
- Changes what tools print: `z = y` from a narrow parameter into a narrower variable warns "narrowing assignment (value
  may truncate)", as from a narrow local.
- Unchanged: a SUSPENDING `async fn`'s narrow parameter still holds the caller's word (reported as the user's call).
- **Migrate:** to keep the whole word, declare the parameter `i64`.

**SS-17 — `*(&f)` of an `f64` / `f32` / `bool` variable is f, with f's type (D70, the user 2026-10-20) — with SS-19**
- Changes what it computes: `*(&f) OP x` of a float variable is a float operation — `*(&f) + 1.0` is 2.5 (it added the
  bits as integers, with a warning); `*(&f) = 2.5` / `*(&f) += 1.0` store and add as floats (an `f32` at its 4 bytes);
  `*(&b)` of a bool is a boolean (a `b: bool` argument, a bool declaration, an if-expression's bool branch take it).
- Stops compiling: `*(&b) = <non-bool>` and `*(&b) OP= v` of a bool — "cannot assign a value that is not a bool to bool
  'b'", as `b = 5` / `b += 1` are.
- Starts working: `*(&b)` / `*&f` / `*(&h)` (a narrow integer) as a dyn source takes its type's impl (it was refused
  "cannot form dyn Num from this expression").
- Unchanged: a closure's capture (its env word), `*(&x + 0)`, `*(&n)` of an i64.
- **Migrate:** write `b = v != 0` for a bool; for the bits of a float, `load64(&f)` (`&f + 0` stays a byte pointer).

**SS-37 — a byte list over an untyped float constant keeps the float's unlisted bytes (D86 (a), the user 2026-10-20)**
- Changes what it computes: `var K = 1.5; var K[1] = {9};` reads 0x3FF8000000000009 (it read 0x0000000000000009);
  `var a = 0x0506; var a = 1.5; var a[1] = {9};` reads 1.5's bytes under the 9 (it read the superseded literal's 0x0509).
  The same for `-1.5`, a constant f64 expression, an f64 const name, a float between two lists. A constant after the
  float still seeds; a computed float does not.
- **Migrate:** if the list was meant to start from zero, declare the global as the list alone (drop the float), or list
  every byte.

**SS-38 — a struct global of 8 B or less copied from a source declared below it is refused by name (no decision: the guide's "declare the source ABOVE the copy", at every size now)**
- Stops compiling: a declaration-zone struct global of 8 B or less copied from a global declared below it whose value is
  stored at run time — `var A: P8 = *GP8;` / `= GP8;` / `= *GPP8;` / `= (*GP8);` above `var GP8: *P8 = &GS8;`, and
  `var A: P8 = GS8;` above `var GS8 = P8 { f() };` (a whole struct global, a field chain's global, a call's value) —
  "cannot copy-init 'A' from a global declared below it (declare the source first): 'GP8'" (a pointer-to-pointer
  dereference: "... from a dereference of a global or fn declared below it (declare it first): 'GPP8'"). The pointer
  forms faulted at startup (SIGSEGV); the value forms compiled and read 0.
- Unchanged: a source the image holds from program start (a constant, a literal of constants declared below) is read; a
  pointer global an entry above already stored is read.
- **Migrate:** declare the source first.

**SS-39 — a `*U` source of another struct into a struct `S` declaration is refused by name (D87 (a), the user 2026-10-20) — with SS-39r**
- Stops compiling: `var t: P = GU;` with GU a `*U` global of another struct U — in a fn, in the declaration zone and
  after the first statement, at every size, wrapped, a `Str` declared from a `*U`, a `*Str` into a P, another generic
  instance (`*Box<i32>` into `Box<i64>`) — and (SS-39r) every other `*U` source the assignment refuses: a call or method
  declared `: *U` (`var l: P3 = gq(&q);`, `= h.mq()`, `callptr(&gq, &q)`, `gg<Q3>(&q)`), a `*U` field (`= h.pq`), pointer
  arithmetic (`= pq + 0`) — "cannot copy 'GU' into a variable of a different struct/vector type: 't'" (the source named
  as spelled: 'gq(&q)'). In a fn and over 8 B at top level t was a handle reading U's object as an S; at 8 B or less at
  top level t held the pointer word. A fn's tuple declaration from a `*U` global gets the same words.
- Unchanged: `var t: U = GU;` copies; `var t: *U = GU;` aliases; a `**U` global keeps its handle bind.
- **Migrate:** write `var t: *U = GU;` (an alias), `var t: U = GU;` (a copy), or fix the declared type.

**SS-41 — a generic operator fn binds its type parameters as its call does (D85 (a), the user 2026-10-20)**
- Changes what it computes: with `fn P1_add<T>(l: P1, r: T): G1<T>`, `b + p` (p a `Pt`) calls `P1_add$Pt`, exactly what
  `P1_add(b, p)` calls: y is a `G1<Pt>` and `y.v.a` reads p's field. It called the i64 base: y was the base `G1` and
  `y.v` held p's address. The same for a struct carrier, `*T` (`&p`), an f64 (`b + 1.5` binds f64), a type parameter on
  the left and a `: T` return, in a fn, the zone and after the first statement.
- Stops compiling: code that used the base's i64 field — `y.v * 1000` with y.v now a Pt (no `Pt_mul`: "undefined
  function 'Pt_mul'"); `s + 3` with a generic operator fn whose body uses T as a struct — "generic 'S1_add' has no i64
  (or other scalar) instance"; a 9 – 16 B or larger instance result at top level — "... a struct result needs storage
  in a fn's frame".
- Unchanged: `b + 32`, `b + p` with p an integer (T = i64: the base), and a non-whole operand (`b + w.s`, `b + P.a`,
  `b + p.dup()`), which binds nothing, as in the call.
- **Migrate:** read the struct (`y.v.a`) — it is the operand's value now, not its address; move a large instance result
  into a fn; give a stub generic operator fn a struct operand.

**SS-42 — a generic storing a generic callee's struct result over 8 B in a T-typed name has no scalar instance (6.7.16's D1, the user 2026-10-19) — with SS-47**
- Stops compiling: a scalar call (`g(5)`, `g<i32>(5)`, `&g`, a forwarder's) of a generic whose body stores a struct
  result over 8 B in (or through) a name typed by T, when the result is a generic call's, method's or operator's
  (`var y: T = mkg1(q);`, `mkg1<Q>(q)`, `y = mkg1(q);`, `b.mkg(q)`, `b.idm(q)`, `b + q`, `e + q`) or spelled as an
  operator chain (`a + c + a`), a receiver in parentheses (`(a + c).mk()`), a generic call's / method's result as a
  receiver, or a local from a generic call — "generic 'g' has no i64 (or other scalar) instance", with a note naming the
  line. Each compiled at i64 and kept the result's first word.
- Unchanged: a T-typed operand (`mkg1(x)`), an 8 B instance (keeps its word), the struct instance (copies).
- **Migrate:** call such a generic with the struct, or type the name as the struct.

**SS-43 — a pointer to another struct into a `*S` / `**S` parameter is refused (D97, the user 2026-10-20)**
- Stops compiling: passing a pointer to one struct where a `*S` / `**S` / `***S` of another is declared — `nc1(&y)` with
  `y: Box<Pt>` into `p: *Box<i64>`, `nc4(&q)` with `q: Qd` into `p: *Pt`, `nc4(pq)`, `nc2(&q)` into `pp: **Box<i64>` —
  through a call, a tail call, a method's arguments, `Pt_m(&q)`, a named argument, an operator's right operand; generic
  instances both ways; a callee below its call — "cannot pass 'y' to a parameter of a different struct type in a call
  to 'nc1'". The callee read the bytes at the declared struct's offsets (2 where 9 is right).
- Unchanged: a pointer to the declared struct, an untyped pointer, `alloc()`, `0`, a generic's own binding (`gb(&y)`),
  a pointer of another depth, and a typed pointer into a BY-VALUE struct parameter (6.7.3's "a typed pointer converts
  freely" holds there only).
- **Migrate:** pass a pointer of the declared struct — for `&c` of a struct whose first field is the S, aim a `*S` at
  the field (`var p: *S = &c;`); a `*Box<i32>` where a generic bound T to i64 from another argument (`g4sz(&bi, 5)`) needs
  the matching instance; or pass an untyped pointer deliberately.

**SS-45 — a zone destructure's f64 element, and an untyped top-level global from an f64 call, are f64s (D98, the user 2026-10-20)**
- Changes what it computes: `var ZA, ZB = mm3(1.5);` (mm3 `: (f64, i64)`) in the declaration zone binds ZA an f64 —
  `f64_to(ZA * 2.0) + ZB` is 10 (it was 7, with "integer arithmetic with an f64 right operand"). An untyped top-level
  `var Y = mkf(1.5);` (mkf `: f64`; a generic, wrapped, known `&f` or method call; `mkf(1.5) * 2.0`) is an f64 in the
  zone and after the first statement — `Y * 2.0` is 3.0 (it was 0, warned). Every fn body, later global and `kernel;`
  build sees it. `Y + 1` now adds as an f64 and warns "f64 arithmetic with a non-f64 right operand".
- Unchanged: a comparison or `% & | ^ << >>` on such a value stays an integer; `(mkf(1.5) * 2.0)` stays untyped, as in a
  fn.
- **Migrate:** for the bits as an integer, read `load64(&Y)` or annotate the global `: i64` (`var Y: i64 = mkf(1.5);`
  keeps the bits — measured at the docs pass).

**SS-46 — a struct result over 8 B stored through a pointer to a scalar is refused (D99, the user 2026-10-20) — with SS-46r**
- Stops compiling: `*p = f();` (f returning a struct over 8 B) through a typed pointer to an integer, float, bool or
  pointer — a local, parameter, global, field, call, `*(p + n)`, `**pp`, `*pp` of a `**i64` / `**Pt`, a capture; from a
  call, method, operator, known `&f`, wrapped, a for step — and (SS-46r) the subscript store `p[i] = f();` through the
  same pointers (`w.pi[0]`, `gi()[0]`, a `*i64` global, at top level too) — "cannot assign '*p: i64' from 'mkp', which
  returns the struct 'Q' - store it through a '*Q' or bind a field" ('p[0]: i64'). It stored Q's first word.
  `*(&x) = mkp()` is refused as `x = mkp()` is. A generic storing such a result through a `*T` (`*p`, `**pp`,
  `*(p + 0)`, `p[0]`, a carrier's `*T` field) has no scalar instance (`g(5)`, `g<i32>(5)` refused).
- Unchanged: 8 B results and `Str` keep their word; `*p = f().a`; `*pq = f()` through a `*Q` copies; a generic at a
  struct T copies. Still accepted, the first word kept: `w.n = mkp();` into a scalar field and `buf[0] = mkp();` into a
  local array's element (staged for the user's decision), and `*p = mkp();` through an UNTYPED pointer (reported as the
  user's call).
- **Migrate:** bind the field you want (`*p = f().a`) or store through a `*S`; call such a generic with the struct.

**SS-49 — a whole vector call returned as a scalar or passed where a word goes is refused (D101, the user 2026-10-20)**
- Stops compiling: returning a vector call from a fn declared `: i64` (or any non-vector type, or none) — `return
  mk2(41, 7);`, `return s.m2();`, `return mk2(41, 7) + 1;`, a closure's expression body `|k| mk2(k, 7)` — "a vector value
  cannot be returned as i64 - 'mk2' returns a vector"; passing a vector call to an untyped, integer or f64 parameter
  (`take(mk2(41, 7))`, `takei(..)`, `tf(..)`), or as a builtin's or an indirect call's argument (`syscall(60, mk2(..))`,
  `store64(&x, mk2(..))`, `fncall1(f, mk2(..))`) — "a vector value cannot be passed to an integer parameter - 'mk2'
  returns a vector, passed to parameter 'n' of 'takei'" / "... passed to 'syscall'". Each handed over one word (0 on
  x86_64 / aarch64, lane 0 on cx; a fault on Windows for the return). 6.7.12's "an argument to an untyped parameter runs
  and discards its vector" no longer holds.
- Unchanged: a vector fn's own `return mk2(..)`, a value-form `f64v2` or `*f64v2` parameter, a discarded call
  (`mk2(1, 2);`).
- **Migrate:** declare the fn's return (or the parameter) the vector, or bind the vector and pass / return a lane
  (`var w = mk2(..); return load64(&w);`).

**SS-50 — a vector call is no operand anywhere, and no word slot's whole value (D100, the user 2026-10-20) — with SS-50r, SS-50r2**
- Stops compiling: a vector call with an operator beside it anywhere in a source — `var x: i64 = 1 + mk2(41, 7);`,
  `x = 1 + mk2(..)`, `var w = 1 + mk2(..)` (a fn and top level), `x += mk2(41, 7)`, `x += s.m2()`, `-mk2(..)`,
  `take(mk2(41, 7) + 1)`, `rd(mk2(41, 7) + 1)` into a `*f64v2` (it crashed), `var q = *mk2(41, 7);` (it crashed) — and a
  whole vector call stored into a field, an element or through a pointer to no vector (`p.a = mk2(..)`, `*q = mk2(..)`,
  and (SS-50r2) `gp().b = mk2(..)`, `gi()[0] = mk2(..)`), used as a condition (`if (mk2(..))`), an index, a range bound
  or a struct literal's field, or (SS-50r) as a tuple literal's element (`var t = (mk2(41, 7), 3);`, `tk((mk2(..), 3))`,
  `return (mk2(..), 3);`) — "vector return type does not match the declared type" / "... the assigned variable" (in a
  `return`, SS-49's words). Each used one word, per target (1 / 0 on x86_64 and aarch64, 42 / 41 on cx and Windows).
- **Migrate:** bind the vector and read its lanes (`var w = mk2(41, 7); x += load64(&w);`); put a lane in a tuple.

**SS-52 — a vector call is refused as a destructure's source (6.7.14's D27 (a): one rule for a declaration and an assignment)**
- Stops compiling: `var a, b = mk2(41, 7);` (a method, an explicit instance, wrapped, three names, the zone and after the
  first statement, `callptr(&mk2, ..)` / `fncall2(&mk2, ..)`) and the assignment `a, b = fncall2(&mk2, ..)` — "cannot
  destructure 'mk2' - it returns a vector, not multiple values" / "cannot re-assign from 'mk2' - ..". They bound integer
  registers a vector return does not write (0 and 0 on x86_64 / aarch64, garbage on Windows). The assignment by name was
  refused since 6.7.11.
- **Migrate:** bind the vector (`var w = mk2(..);`) and read its lanes.

Nothing to migrate in the other bites:
- **SS-1, SS-44** (D: none). Gate scripts hold under `bash -eo pipefail`; test scripts only.
- **SS-2, SS-6** (D: none). `cyrius lint` (`--syntax-only`) refuses `Some(5).n = 1;` in a fn above its enum, and a store
  through parentheses (`(s).a = 1;`, the step `(s).a = 3`), as the build always did.
- **SS-5, SS-7** (D: none; 6.7.14's D24 (a), 6.7.15's D19, 6.7.16's D22 reused). A parenthesised for-step destination is
  refused in its statement's words; a refused `*T` struct source is named as spelled ('gq(&q)', not 'q'). Refused before
  and after.
- **SS-12** (D: none). A `Str` handle's name into a `*Str` no longer warns "assigning non-pointer to typed pointer".
- **SS-19** (D70). Part of SS-17's block (a dyn source of `*(&b)` now compiles).
- **SS-20, SS-21** (D: none). On PE, a refused `syscall(60 0);` is its one error; the non-literal-number routing warning
  names its site and arity, once per site.
- **SS-22 – SS-28, SS-30, SS-36, SS-40, SS-51, SS-53, SS-53r, SS-54 – SS-56** (D: none). Diagnostics of refused programs
  only: one error per mistake (the zone's last latch, a refused enum body's uses, a refused wide if-expression branch's
  variable, an undeclared struct's literal, an uninitialized zone vector global, a zone operator over generic calls, a
  zone tuple global from another type, a refused annotation, the PE literal global's lost name, a vector receive's
  refusal in sync, a float-type warning after an error); new words for a positional literal short of a field ("missing
  struct field in initializer", was "unexpected '}'") and a `.name` past a scalar field ("field 'n' is not a struct: it
  has no field 'b'", was "expected ';', got '.'") — a tool matching the old text sees the new.
- **SS-29** (D: none). A zone generic call's refused type-argument list is reported in source order.
- **SS-31 – SS-35** (SS-35 under D16 (a), the user 2026-10-19). Valid code the declaration zone refused now compiles, as
  after the first statement: an annotated zone global from a generic method's generic struct result, a generic method
  returning its own `: T`, a generic call carrying a generic instance call, a generic fn's fixed instance return, an
  if-expression whose branches are a generic instance.
- **SS-48** (D: none). Code moved between `parse_fn.cyr` and `parse_types.cyr`; byte-identical.

#### SZ7 — a multi-value method on a field-chain receiver as a destructure source, and every pair / multi-value lookahead on a chain (the s16b lane, split from s16 in wave 4)

No decision decides this lane: the filed issue is "no decision: a compiler failing valid cyrius is fixed", and every
refusal below is the one a single-name receiver `p.m(..)` already meets (v6.6.16's C4 for a `: stack` pair, 6.7.11 and
6.7.15's GN-21 for a multi-value call into a struct). D42 is 6.7.16's (the user, 2026-10-19, at the open). Each block names
its CHANGELOG [6.7.16] bite. Every change is in the frontend: the same on x86_64, aarch64, cx, PE and Mach-O. A
"chain" below is a method ending a chain on any receiver the method arm takes: a field chain `w.p.m(..)` (through a `*P`
field, at any depth, from a `*W` parameter, `self`, a global, a closure's capture), a method's result `w.gp().m(..)`, a
call's `mk().p.m(..)` / `callptr(&gw, &w).p.m(..)`, a parenthesised head `(*pw).p.m(..)` / `(w).p.m(..)`, a generic step
or generic call head in it (`w.p.idv(q).m(..)`, `gw(2).p.m(..)`).

**SB-1 — a method ending a chain is a method call to every pair / multi-value lookahead (no decision: the single name's
rules)**
- Stops compiling: a `: stack` pair method on a chain bound, assigned or stored one-wide — `var v = w.p.rs(3);`,
  `x = w.p.rs(3);`, `store64(&s, w.p.rs(3))`, `hh.a = w.p.rs(3);`, a struct-literal element `H2 { w.p.rs(3), 2 }`,
  `(w.p.rs(3) + 1)`, `w.p.rs(3) + 1` — "a `: stack` enum returns two values — bind both: `var tag, val = f();`". Through
  6.7.15 each kept the TAG and dropped the payload, in silence.
- Stops compiling: `var v = fwd(w);` above a `fwd` defined below it that forwards a chain's pair (`return w.p.rs(3);`) or
  whose only pair route is `w.p.rs(3)?` — "bind both". Through 6.7.15 the caller read the tag.
- Stops compiling: a multi-value method on a chain stored into a struct field (`hh.s = w.p.m2();`, `hh.s =
  (*pw).p.m2();`, `hh.s = callptr(&gw, &w).p.m2();`), returned from a fn returning a struct of 8 B or less (`return
  w.p.m2();` from a `: Q8` fn) or returned from an `async fn` — "a multi-value call 'm2' is not stored into a struct 'Q16'
  field - bind it first: `var a, b = w.p.m2(..);`", "... is not returned as struct 'Q8' ...", "`async fn af` returns 2
  values, and a Future carries one i64 ...". Through 6.7.15 each compiled and kept the FIRST value (`hh.s` held 3 and 0).
- Changes what it does: `?` on a chain's pair — `var v = w.p.rs(3)?;`, a statement `w.p.rs(0)?;`, `(w.p.rs(3))?` — and a
  caller's `fwd(w)?` on a forwarder of one now propagate. Through 6.7.15 each crashed (SIGSEGV: the boxed `?`).
- Changes what tools print: `return w.p.rs(4);` beside `return Err(2);` no longer draws "returns a `: stack` pair on
  another path but a SINGLE value here" (a false warning); `return w.p.one();` there still does. A refusal on a chain
  names the method as the call does and spells the receiver in its hint (`var a, b = w.p.m2(..);`; it was `P_m2` and
  `var a, b = ...;`).
- Starts working, where `var p = w.p; var c, d = p.m2();` was the workaround: `var c, d = w.p.m2();` (the filed repro,
  34), a re-assignment, three names, a 9-16 B struct destructured, `var t: (i64, i64) = w.p.m2();`, `w.p.mm(h)` /
  `w.p.mm<f64>(h)` with an f64 first value, a `*T` method as a dyn source (`var o: dyn Show = dw.d.me(1);`), both
  top-level zones (`var a, b = GW.p.m2();`, `var t: (i64, i64) = (GW).p.mm(5);`).
- **Migrate:** bind both (`var t, v = w.p.rs(3);`, `var t, v = fwd(w);`) or propagate with `?`; for a multi-value method
  into a struct field or a small-struct / async return, bind the values first (`var a, b = w.p.m2();`) and build the
  struct from them. The `var p = w.p;` workaround can go.

**SB-1r (+ SB-1r3, SB-4r2) — a generic step or a generic call head in the chain (no decision: SB-1's rules)**
- Stops compiling, as SB-1's shapes: a pair method after an inferred generic step bound one-wide (`var v =
  w.p.idv(q).rs(3);`, `q.idv(q).rs(3)` on a single name then a chain), after a `*T` generic step
  (`w.gpx(&w).p.rs(3)`), and `var v = fwd();` above a `fwd` below it that forwards such a chain or one on a generic call
  head — `return w.p.idv(q).rs(3);`, `return gw(2).p.rs(3);` / `return gw<i64>(2).p.rs(3);` with `fn gw<V>(x: V): *W`,
  `return gwp(&w).p.rs(3);` with `fn gwp<T>(p: *T): *T` — "bind both". Through 6.7.15 each kept the tag.
- Changes what it does: `w.p.idv(q).rs(3)?` / `q.idv(q).rs(3)?`, and a caller's `?` on such a forwarder, propagate (each
  crashed, 139).
- Starts working: `var a, b = w.p.idv(q).m2();`, `w.p.mkg(q).v.m2()` (a `: G<V>` step), `w.gpx(&w).p.m2()` (a `: *V`
  step), each "needs a call" through 6.7.15. A step whose argument is itself a generic call (`q.idv(q.idv(q)).m2()`) is
  still refused, as its `.field` is — bind the inner result with an annotation first (`var r: P = q.idv(q);`).
- **Migrate:** bind both, or propagate with `?`.

**SB-1r4 — a single name's explicit generic `p.rg<i64>(5)?` as a fn's only pair route (D42, the user 2026-10-19 — "Both
spellings compile, refuse and run alike")**
- Stops compiling: `var v = fwd(w);` above a `fwd` defined BELOW it whose only pair route is a single name's explicit
  generic `?` — `fn fwd(w: W): i64 { var p: P = w.p; var v = p.rg<i64>(5)?; return v + 0; }` — "a `: stack` enum returns
  two values — bind both". Through 6.7.15 it compiled (only the mixed-return warning at fwd's own `return v + 0;`) and the
  caller read 6 on the Ok path and the tag on the Err path. The inferred `p.rs(5)?`, and `fwd` defined above its caller,
  were already refused.
- **Migrate:** bind both at the caller (`var t, v = fwd(w);`), and return a variant on fwd's single-value path
  (`return ROk(v + 0);`) to clear the warning.

**SB-2 — a chain on a `callptr(&f, ..)` result as a by-value struct argument (no decision: every other head's refusal)**
- Stops compiling: a multi-value method on a `callptr(&f, ..)` chain passed into a by-value struct or tuple parameter —
  `take(callptr(&gw, &w).p.m2())` — "a multi-value call 'm2' is not a struct 'Q16' argument - bind it first: `var a, b =
  callptr(&gw, &w).p.m2(..);`" (a tuple parameter: "... is not a tuple argument ..."). Through 6.7.15 it compiled and
  passed the first value as the struct's address (a crash).
- Changes what it does: `take(callptr(&gw, &w).p.q16())`, `take(callptr(&gw, &w).q)` and the wrapped spelling pass the
  struct (34 / 56). Through 6.7.15 each pushed a word as the struct's address: SIGSEGV on x86_64 / aarch64, an access
  violation on PE, a guest address fault on cx.
- **Migrate:** bind the values first (`var a, b = callptr(&gw, &w).p.m2();`) and pass a struct or tuple built from them.

#### Windows found by the p16 review — an fd that is not a multiple of 4, rename / symlink / fsync errnos, a directory's unlink / truncate / open (the pw lane)

Each block names its CHANGELOG [6.7.16] bite (the pw lane, PW-*). Every change here is Windows-only; Linux, macOS,
aarch64, cx and agnos answers are unchanged.
- D94 and D95 are 6.7.16's, asked on their own at the p16 / t16 integration (the user, 2026-10-20).
- 6.7.16's D78 and D79 are the p16 lane's (a negative fd's close; mkdir / unlink / rmdir / ftruncate / truncate through
  the Win32 table).
- PW-1 and PW-2 had no decision asked: an fd cyrius never handed out is answered -9, as Linux answers it.

**PW-1 — Windows: an fd above 2 with a low bit set answers -9 in every fd reroute, before any Win32 call (no decision: an fd cyrius never handed out)**
- Take an fd above 2 whose two low bits are set — `h + 1`, `h + 2` or `h + 3` beside an open `h`, a stale or computed
  value. A `sys_close`, `sys_read` / `file_read`, `sys_write` / `file_write`, `xlseek` / `sys_lseek`, `xfsync` /
  `sys_fsync` / `sys_fdatasync` or `sys_ftruncate` of it now answers -9 (EBADF), as on Linux.
- Until 6.7.16 the NT kernel, which ignores a handle value's two low bits, resolved it to `h`:
  - `sys_close(h + 3)` answered 0 and closed `h`, and `h`'s own later calls failed -9;
  - a write to `h + 1` went into `h`'s file;
  - `sys_ftruncate(h + 2, n)` truncated it.
- A negative fd with a low bit set (`-1`, `-2`, `-3`, …) answers -9 in a read / write / seek / fsync / ftruncate too.
- **Migrate:** nothing for a correct program: every descriptor cyrius hands out on Windows (file, pipe, socket) is a
  multiple of 4, so no live fd is refused. A program whose fd arithmetic or stale fd "worked" on Windows was acting on
  another descriptor. It now gets -9: fix the fd it passes. Test failures with `< 0`, as everywhere.

**PW-2 — Windows: the stdlib's socket, lock and final-path wrappers answer -9 for an fd with a low bit set (no decision: the same issue)**
- With such an fd, the socket verbs answer -9: `sock_send` / `sock_recv` (`Err(9)`), `sock_close`, `sock_set_nodelay`,
  `sock_shutdown`, the rest of `sock_*`, `sys_getsockname` / `sys_getpeername` / `sys_listen` and `fd_wait_ready`.
- So do `xflock`, the native TLS transport's reads and writes, and the async reactor's recv / send / accept tasks.
- They used to act on the socket or file below it: `sock_close(s + 3)` closed the socket `s` and answered 0, and
  `xflock(h + 1, LOCK_EX)` locked `h`'s file.
- `win_handle_under(h, root)` answers -1 (its "cannot say") when either handle has a low bit set; it named `h`'s path.
- The non-blocking connect helper behind `net_connect_sa_nb` answers its `_NET_CONN_NB_ERR` (-1).
- **Migrate:** as PW-1 — no live socket or handle is refused. Treat -9 / `Err(9)` as "not a descriptor".

**PW-3 — Windows: `file_rename`, `xsymlink` and `xfsync` answer the failure's errno through the Win32 table (D94; with PW-3r)**
- `file_rename` / `sys_rename` of a missing source, or into a missing directory, answers -2.
- `xsymlink` / `sys_symlink` under a missing directory answers -2, and over an existing name -17 — elevated or not
  (PW-3r).
- `xfsync` / `sys_fsync` / `sys_fdatasync` of a closed or bad fd answers -9, and of a read-only fd -13. Linux and macOS
  flush a read-only fd and answer 0.
- Each of these answered -1 for every failure.
- Unchanged: a link that Windows policy refuses (no Developer Mode and not elevated: ERROR_PRIVILEGE_NOT_HELD, which the
  table leaves -1) is still -1. So is a path the UTF-16 widening refuses.
- ⚠ A raw `syscall(0xF03E, link, target, flags)` (CreateSymbolicLinkW) answers 0 for a made link — it answered the
  BOOLEAN 1 — and a negative errno for a failure, where it answered 0. A raw `syscall(0xF034, ..)` (MoveFileExW) and a
  raw `syscall(74 / 75, fd)` still answer 0 on success, and now -errno on failure where they answered -1.
- **Migrate:**
  - Code that tested these calls for `== -1` (or `== 0 - 1`) no longer sees a failure on Windows: test `< 0`, or the
    errno itself.
  - Code that read a Windows `xsymlink` -1 as "links are not allowed here" must now accept -2 / -17 as path errors;
    only the policy refusal is -1.
  - A raw `syscall(0xF03E, ..)` caller that tested `!= 0` (or `== 1`) for success must test `== 0`. Better, call
    `xsymlink`.

**PW-4 — Windows: a directory's unlink, truncate and open for writing answer -21, as Linux (D95)**
- On a DIRECTORY, these answer -21 (EISDIR), where they answered -13 (EACCES — CreateFileW / DeleteFileW's
  ERROR_ACCESS_DENIED):
  - `sys_unlink` / `xunlink`;
  - `sys_truncate`;
  - `file_open` / `sys_open` under write access (`O_WRONLY`, `O_RDWR`), `O_CREAT` or `O_TRUNC`.
- ⚠ `file_open` / `sys_open` of a directory under `O_CREAT|O_EXCL` answers -17 (EEXIST, as on Linux and as
  `file_create_exclusive` has since 6.7.14). It answered -13 on real Windows; wine already answered -17. D95's text
  names -21, so this is beyond it.
- Unchanged: a read-only open of a directory without `O_DIRECTORY` is still -13 on Windows (Linux opens it). A refusal of
  anything that is not a directory — a file another handle holds open, a real permission refusal — is still -13.
- macOS answers an unlink of a directory EPERM (-1), Darwin's own; its open and truncate answer -21.
- **Migrate:**
  - Code that read -13 on Windows as "it is a directory" tests -21 (and, for an unlink, -1 on macOS).
  - Code that treated every Windows -13 from these calls as "permission denied" no longer meets the directory case
    there.
  - An exclusive create over an existing directory reads -17 on every target.
  - The raw `syscall(SYS_OPEN, ..)` still answers -13 for a directory on Windows; the classification lives in
    `sys_open` / `sys_unlink` / `xunlink`.

No block for PW-1r (a test asks whether an fd is inherited before using it), PW-3r2 (a gate's comment) or PW-4r
(comments). PW-3r's change is part of PW-3's block: it makes D94's link errnos hold in a non-elevated process.

#### Folds — sandhi 1.13.3

**sandhi 1.13.1 → 1.13.3 — no API change for a caller.** A server's request framing allocates nothing on the global heap
(a long-running server's heap stays flat on body requests); `sandhi_server_content_length` allocates nothing, while
`sandhi_server_find_header` still copies (its contract — per-request callers use `_find_header_a`). A multi-threaded
client may share a pool across its h2 traffic: requests on one h2 connection are serialised, so a thread that needs
parallel h2 requests to one route gives each thread its own pool. `SANDHI_H2_CONN_STRUCT_SIZE` grows 80 → 88
(`SANDHI_H2_CONN_OFF_MUTEX` at +80): a struct built by hand to the old layout is used unlocked. `sandhi_h2_conn_new` /
`_new_a` and `sandhi_hpack_table_new_a` return 0 on any allocation failure, not only the first. The lower-level
`sandhi_h2_request_send_a` / `sandhi_h2_response_recv_a` pair stays unlocked — keep it on one thread.

### 6.7.15

Break 2, repair 5 — what 6.7.14 filed. Each block names its CHANGELOG [6.7.15] bite; the decisions are the user's
(2026-10-18: D1–D70 at the open, two at the wave-2 integration). The changes that went beyond a decision's text are filed
for confirmation at the 6.7.16 open (`docs/development/issues/archived/2026-10-19-6715-behaviour-changes-beyond-the-decisions-text.md`).
Decision ids are 6.7.15's unless a block names another release ("6.7.14's D30"). Wave 0 (the check driver's SIGPIPE, the
`parse_fn.cyr` split) changes nothing a consumer sees.


#### Generics — type-argument lists, pointer binding, trait signatures, the bound contract, diagnostics once (the generics lane)

The decisions are the user's at the 6.7.15 open (2026-10-18, D3 – D13; D13 asked on its own). "6.7.14's Dn" is the
6.7.14 open's id (2026-10-16). Each block names its CHANGELOG [6.7.15] bite. Every change below is in the frontend: the
same on x86_64, aarch64, cx, PE and Mach-O.

**GN-1 — a nested type argument closed by `>>` / `>>>` and followed by `,` (no decision: fixed to what the source says)**
- Changes what it computes: a type-argument list whose nested argument closes with `>>` / `>>>` right before a `,` now
  binds the following argument as written. Through 6.7.14 the `,` was read as part of the inner list, and the next
  argument was silently dropped: `g2<P<P<R>>, i16>(..)` bound B to i64 (it binds i16 now), and `Two<P<P<R>>, i16>` was
  24 bytes with an 8-byte `b` (it is 18, `b` an i16). If a size, a layout or an instance you relied on came from the
  dropped argument, it changes to the one you wrote. Nothing to rewrite.
- Starts working: a doubly nested generic parameter followed by another — `fn f(a: Box<Box<Pt>>, b: i64)`,
  `fn f(a: *Box<P<R>>, b: i64)`, `fn f(w: Vec<Box<Box<Pt>>>, b: i64)` — which was refused "unknown type 'b' as a type
  argument". The `> >` workaround can go.

**GN-3 — `Name<..>` on a non-generic struct or a scalar is refused at the name (D6 (a), the user 2026-10-18)**
- Stops compiling: type arguments on a struct that is not generic, or on a scalar — `var c: Pt<i64>;`, `g<Pt<i32>>(0)`,
  `g<i64<u8>>(0)`, `var b: Box<Pt<nosuch>>;`, `fn f(p: Pt<i64>)`, a `: Pt<i64>` return, `Vec<Pt<nosuch>>`, a global
  `Pt<i64>`, a `*Pt<i64>` local, `sizeof(Pt<i64>)`, a struct literal `Pt<i64> { .. }`, and a program's own non-generic
  `struct slice` written `slice<u8>` — "'Pt' is not a generic struct: it takes no type arguments" / "'i64' takes no type
  arguments". Through 6.7.14 the list was skipped unread (a name inside it was never checked).
- **Migrate:** delete the `<..>` — it was ignored. If you meant a generic struct, declare it `struct Pt<T> { .. }`.
- Still accepted, the list ignored (filed, 6.7.16): a pointer field `p: *Pt<i64>`, a trait member's parameter, a
  multi-value element `(Pt<i64>, i64)`, a `*fn(Pt<i64>)` parameter, a `**Pt<i64>` parameter, a `*i32<u8>` local, global
  or `: *T` return. Delete those `<..>` too: they will be refused.

**GN-4 — an explicit all-i64 struct type argument is the base struct (no decision: the annotation's rule)**
- Changes what tools print: an instance over `Box<i64>` is named over the base `Box` — `gx$Box` (it was `gx$Box$i64`;
  an outer two-parameter one `Pair$Box$..`, it was `Pair$<Box$i64>$..`) — in the coverage dump, `cyrius syms` and a
  call-site diagnostic (`'gx<Box>'`). The layout is the same. A script matching the old name matches the new one.
- Starts working: `gx<Box<i64>>(bx)` with `bx: Box<i64>` (and `gy<Box<i64>>(1, bx)`, `gx<Box<i64> >(bx)`, the call
  with `var bx = Box<i64> { 1 };`), refused "cannot pass 'bx' to a parameter of a different struct type". It reaches the
  instance `gx(bx)` reaches.

**GN-7 — a pointer field's `*G<..>` type arguments are checked at the field (D8 (a), the user 2026-10-18)**
- Stops compiling, at the field, even when the field is never used: a struct (or union) field `p: *G<..>`, G a generic
  struct, whose type argument names no type (`p: *Box<Zork>`), is a number or an expression (`*Box<1>`), a tuple, a
  slice, `u128`, `Result` / `Option` / `Tagged` / `cstring`, or an enum — "unknown type 'Zork' as a type argument (...)",
  "a type argument is a type name, got number 1", and the other type-argument refusals. Through 6.7.14 an unused field
  compiled and each use was refused. (The refusals other than an unknown name and a number go beyond D8's text; each is
  refused on a by-value `b: Box<..>` field already.)
- **Migrate:** fix the type argument, or delete the field — no use of it could compile. A struct declared further down
  is fine (`*Box<B>` / `*Box<A>` pointing two structs at each other still compiles).

**GN-9 — a multi-value element, a trait member's signature and a `*fn(..)` type read their type arguments (D7 (a), the user 2026-10-18)**
- Stops compiling, at the definition, used or not: a generic struct's type argument that names no type, or is any
  refused type argument, in a multi-value return element (`fn mv(): (Box<Zork>, i64)`), a trait member's parameter or
  return (`fn a(self, b: Box<nosuch>): i64;`) or a fn-pointer type (`cb: *fn(Box<Zork>): i64`) — "unknown type 'Zork' as
  a type argument (...)", once. Through 6.7.14 each compiled as the base struct. (`(Box<u8>, i64)`, a member's
  `Box<(i64, i64)>` and `*fn(Box<Result>)` are refused too — beyond D7's text, which named an unknown name; each is refused
  on a fn's own parameter since 6.7.14.)
- **Migrate:** write the type you meant — the argument was ignored (the base `Box`). A fn's or a trait member's own type
  parameter (`Box<U>`) and a struct declared below are fine.

**GN-10 — a trait member's `: Vec<..>` return is refused at the trait (D9 (a), the user 2026-10-18)**
- Stops compiling: a trait member declared `fn m(..): Vec<..>;` — or a bare `fn m(..): Vec;` (beyond D9's text; a fn's
  bare `: Vec` already is) — "type 'Vec' cannot be a fn return type", with a fn's note. No impl of such a member could
  compile (the impl's `fn m(..): Vec<i64>` was refused).
- **Migrate:** declare the member `: *Vec<T>`, or return the handle as `i64`, and its impls with it. `: *Vec<i64>`, a
  parameter `v: Vec<i64>` and `(Vec<i64>, i64)` are unchanged.

**GN-11 — a trait member's `: u128` return is refused (D3 (a), the user 2026-10-18)**
- Stops compiling: a trait member declared `fn m(..): u128;` — "`u128` is not supported as a fn return type yet" — also
  when an impl implements it as `: i64` (which compiled) and under `--syntax-only`. Every impl or default spelled `: u128`
  was already refused.
- **Migrate:** declare the member `: *u128` (and its impls with it). A `*fn( .. ): u128` type's own return is unchanged.

**GN-12 (+ GN-12r) — an impl method's return type is checked against its trait member's (D4 (a), the user 2026-10-18)**
- Stops compiling: an impl method whose return type differs from its trait member's — `fn c(self): i64` for
  `trait T { fn c(self): f64; }` — "'P.c' returns i64, trait 'T' declares f64", at the impl. An omitted return is i64 on
  either side, so `: bool`, `: i32`, `: f64`, a multi-value and a struct all count against an unannotated member (and the
  other way round). Through 6.7.14 only the parameter COUNT was compared, and a bounded generic caller declared `: f64`
  read the integer bits.
- Unchanged: a return that spells the same type two ways — `Box<i64>` / `Box`, `*Box<i64>` / `*Box`, `Box<Box<i64>>` /
  `Box<Box<i64> >` (GN-12r); a type parameter against a type parameter (`fn g<U>(..): U` for `fn g<V>(..): V`).
  Parameter types are not compared.
- **Migrate:** make the impl's return annotation agree with the member's (or the member's with the impl's). lib/'s traits
  (sandhi's two) already agree.

**GN-13 — a Vec element's generic struct is held to its bounds (D10 (a), the user 2026-10-18)**
- Stops compiling: a `Vec<G<..>>` — a local, a field, a parameter, a global, nested (`Vec<Two<Box<Pt>, i64>>`,
  `Vec<Vec<Box<Pt>>>`) — whose generic struct G has a bound its arguments do not meet: `var w: Vec<Box<Pt>> = 0;` with
  `struct Box<T: Show>` and no `impl Show for Pt` is "generic 'Box': its type argument does not implement trait 'Show'"
  with its note, as `var b: Box<Pt>;` already was. `Vec<Box<i64>>` and a bare `Vec<Box>` are judged at i64 (the bare form
  goes beyond D10's text, as `var b: Box;` is judged). A generic's `Vec<Box<T>>` is judged per instance.
- **Migrate:** add the impl the note names, or drop the bound. Nothing is minted, so a Vec's handle and code are
  unchanged.

**GN-14 — a `p: *T` / `pp: **T` parameter binds a scalar pointee (D11 (a), the user 2026-10-18)**
- Changes which fn runs: an inferred generic call whose `p: *T` argument points at an i8, i16, i32 or f64 — a `*i32`
  local, parameter, capture, global, field or `: *i32` call, `&h` of an f64 local, parameter or global, `&i` of a signed
  narrow local or global — and a `**i32` / `**i16` / `**f64` through `pp: **T`, now runs that instance where it ran the
  i64 base: `sizeof(T)` is the pointee's size, `p + 1` steps it, `*p` reads its width, and a `: T` result is that type
  (sign-extended at i32; an f64 in the float register). The filed `second(pa)` over an i32 array read a[2]'s 8-byte word;
  it reads a[1]. `*u8` .. `*u64`, `*f32`, `*bool`, `*i64` and `***T` still bind i64, and through `x: T` a pointer binds
  nothing (as before). A generic that is a stub at i64 is refused as before.
- **Migrate:** a call that relied on the i64 base (an 8-byte step over a narrow array) spells it: `second<i64>(pa)`.
  Inside the generic, name the stepped pointer `var q: *T = p + 1;` — an untyped `var q = p + 1` is an i64 word whose
  `*q` reads 8 bytes even in the i32 instance.

**GN-15 (+ GN-15r) — a parenthesised, dereferenced or captured argument binds T as its plain spelling (D12 (a), the user 2026-10-18)**
- Changes which fn runs: through a plain `x: T` / `p: *T` parameter, a parenthesised struct `gs((l))`, a whole
  dereference `gs(*p)` of a `*S`, a closure-captured struct `|| gs(l)`, `gsz((p))` and `gsz((&GS))` now call the S
  instance (`sizeof(T)` 24 for a 24-byte S; a `: T` result is the struct) where they ran the i64 base; and a
  parenthesised scalar binds as its plain spelling too — `g((h))` with `h: f64` is the f64 instance (it ran the i64 base
  on the double's bits; beyond D12's text, which named struct spellings). Where the plain spelling is refused, so is the
  wrapped one now (a body's `x + 1` on a struct T needs `S_add`).
- Starts working: a captured struct passed to `gsz(l)` through `p: *T` (it was refused as not a pointer): the call passes
  the capture's copy's address, so a store through it lands in the copy.
- **Migrate:** spell `g<i64>(..)` for the old base. A pointer through `x: T` (`gs((p))`) and an operator's operand
  (`gs(*p + 1)`) still bind i64.

**GN-18 — a method no bound declares, called on a carrier's `T` field, is refused (D5 (a), the user 2026-10-18)**
- Stops compiling, at the generic's definition, called or not: a bounded generic that calls, on a struct carrier's `T`
  field, a method no trait of the bound declares — `b.v.other()` under `fn gs<T: Show>(b: Box<T>)` — "method 'other' is
  not in the bound on type parameter 'T'", the note naming `'b.v'`; and a method two of its traits both declare
  (ambiguous). Through 6.7.14 the call resolved per instance (the filed program called Pt's own `other`).
- **Migrate:** add a trait that declares the method to the bound, or drop the bound (an unbounded `T` resolves per
  instance). `b.v.show()` of a bound's method, an unbounded `Box<T>` and a `p: *T` field are unchanged.

**GN-21 — `x.m<..>(..)` is a method call to every lookahead (no decision: 6.7.14's D7 (a) made it the method call)**
- Stops compiling, as the inferred spelling `x.m(..)` always was: the explicit spelling of a pair-returning (`: stack`
  enum) method bound
  to one name, assigned or stored (`var v = p.rs<i64>(3);`, `x = ..`, `store64(&x, ..)`, a field, a struct literal,
  `(p.rs<i64>(3) + 1)`) — it kept the pair's tag in silence; a vector-returning method's into a scalar
  (`var x: i64 = s.vv<i64>(..)`); a multi-value method's into a struct field, a small-struct return or an async fn.
- Changes what it computes: `?` on the explicit spelling (`var v = p.rs<i64>(3)?;`, `p.rs<i64>(0)?;`,
  `(p.rs<i64>(3))?`, a forwarded `return p.rs<i64>(3);`) propagates — it took the boxed lowering and crashed (SIGSEGV).
- Starts working: a multi-value destructure or re-assignment of the explicit spelling, a tuple capture, a vector receive,
  a `*T` method forming a dyn, a top-level zone.
- **Migrate:** bind both values of a `: stack` enum's pair (`var t, v = p.rs<i64>(3);` — the refusal reads "a `: stack`
  enum returns two values — bind both") or use `?`, exactly as for `p.rs(3)`. A field of the same name still wins, so
  `p.n < k >> (j)` still compares.

**GN-25 — a `: T` generic reaching a word instance, received into a struct-annotated local, is a handle (D13 (a), the user 2026-10-18)**
- Starts working: `var a: S = g(..)` with a `: T` generic whose call binds no struct (`gid(5)`, `gid<i32>(5)`, `gid(h)`
  with `h: f64`, `gid(w.v)`, `gid(alloc(24))`), then `a.f` / `a.f = v` — refused "no struct type in scope for 'a'" through
  6.7.14 — is a handle: a field use reads or writes at the returned word, as `var b: S = wid(5);` with `fn wid(x): i64`
  does (a fault when the word is no address).
- Stops compiling, as for the non-generic `wid(5)` (beyond D13's text, which named only shapes that start compiling;
  measured at the docs pass): such a local passed to a parameter of ANOTHER struct type — `fn tq(q: *Q)`, `fn ts(s: Q)`
  — compiled through 6.7.14 (the local was an untyped word) and is now "cannot pass 'a' to a parameter of a different
  struct type". `a = 7;` now warns "assigning non-pointer to typed pointer" (and `var b: *i64 = a;` no longer does).
- Unchanged: the local holds the same word, so `return a;`, arithmetic, comparisons and a pass to an untyped / `i64` /
  `*S` parameter compute what they did; `gid(p)` with `p: S` still receives the struct (a copy); `gid(q)` of another
  struct is still refused at the declaration.
- **Migrate:** to keep the word, declare the local untyped (`var a = gid(5);`) or `: i64`; to pass it as another struct,
  annotate it as that struct.

Nothing to migrate (refused code now compiles, a crash or a wrong refusal becomes the right answer, or only error output
changes): GN-2 (a `dyn` type argument is one error), GN-5 (a `var t: *T` local in an instance is T's struct receiver),
GN-6 (a generic struct's `p: *T` field hops: `b.p.y`), GN-8 (`fn mk(): **Box<Later>` with `Later` below compiles; a
caller ABOVE `mk` that dereferences the call (`**mk()`) compiles and faults, as `: *Later` / `: *Box<Later>` returns
already did — read through a typed local, `var q: **Box<Later> = mk();`, or declare the struct above; filed), GN-16 (the
stub scan binds `gd(&G)` and the other pointer spellings as the parser does), GN-17 (a generic passing its T value into a
stub carrier position compiles; `outer(5)` is refused at the call, naming `outer`), GN-19 (no orphan bound note), GN-20 /
GN-20r (a bounded forwarding chain of any length is judged — a called chain is still held to the nesting bound, about
120 forwards; a mutual-recursion refusal may name a different, equally true forward), GN-22 (a warning in a generic or
`#inline` body prints once per site — a script that counted one warning line per instance sees one), GN-23 (a direct
error in a generic body prints once), GN-24 (a generic METHOD's refusals name `P.pick` where they said `P_pick`; the free
spelling `P_pick(p, 9)` keeps its name — a tool matching `generic 'P_m'` should match `P.m` for the method spelling),
GN-25r (a comment).

#### The frontend — constants, declaration-zone globals, redeclarations, late declarations, struct-literal grammar (the frontend lane)

The decisions are the user's at the 6.7.15 open (2026-10-18: D1, D2, and D46's confirmation of 6.7.14's float-literal
bake). "6.7.14's Dn" are the 6.7.14 open's (2026-10-16). Each block names its CHANGELOG [6.7.15] bite. Every refusal
and warning below is a frontend diagnostic, the same on x86_64, aarch64, cx, PE and Mach-O; the value changes were
measured on x86_64, aarch64, cx and PE (and on the hardware hosts for the lane's crossos files).

**FE-5 — `#pure`'s `#io` / `#alloc` check warns on a call through a generic instance (no decision: the check's own contract)**
- A new warning: a `#pure` fn that calls an `#io` / `#alloc` generic through an instance — `h<i32>(1)`, `a<i32>(2)`, a
  tail call `return h<i32>(1);`, an impl method `p.m<i32>(1)` — warns "#pure fn calls #io fn 'h<i32>'" (`'P.m<i32>'`),
  as the all-i64 spelling (which binds the base) always did. A warning only: no exit code or binary changes. Drop
  `#pure`, or the effect.

**FE-6 — a `var` whose `:` has no type is one error at the token after the `:` (6.7.14's D15 (a) applied to `=` / `;`; ⚠ beyond D15's text)**
- Stops compiling: a declaration-zone `var c: ;` followed by another declaration — `var c: ; var d = 2;` compiled with
  `c` holding d's initializer and `d` never declared (silently wrong); it is now "expected a type for variable 'c', got
  ';'". Write the type (`var c: i64 = 0;`), or drop the `:`.
- Changed message (refused before and after): `var b: = 0;` is "expected a type for variable 'b', got '='" at the `=`
  (was "expected '=', got number 0" at the initializer), and `var G: ;` "... got ';'" (was "expected '=', got ..." at
  the next line). A script grepping for the old text reads the new one.

**FE-8 — a struct literal's elements are separated by commas (D1 (a), the user 2026-10-18)**
- Stops compiling: a struct literal with no comma between two elements — `var q = P { 3 4 };`, `var p = P { b: 1 a:
  2 };` — positional or named, in a fn, after the first statement, in the declaration zone (a `kernel;` build too), a
  nested struct's leaves, a generic literal `Box<i64> { 1 2 }`: "expected ',' between struct literal elements" at the
  second element. It compiled, the values landing where the commas would have put them. Add the commas. `cyrius lint`
  reports it too. (The census found none in cyrius's own tree.)
- Unchanged: literals written with commas, and a trailing comma (`P { 1, 2, }`, `P { a: 1, b: 2, }`).
- Changed message (refused before and after): a commaless tuple literal `(1, 2 3)` now says "expected ',' between
  struct literal elements" (was "expected ')', got number 3") — the tuple shares the element store; filed for 6.7.16.

**FE-13 — every constant redeclaration in the declaration zone is the value from program start (D2 (a), the user 2026-10-18; the two orderings marked ⚠ go beyond D2's text)**
- Changes what it computes: a declaration-zone global declared twice whose later declaration is a const- / enum-named
  or replay-folded constant (`= C`, `= E.B`, `= A + 1`) is that constant from program start, whatever the earlier
  declaration is. A READ between the two declarations sees the later constant: with `const C = 5; const D = 3;`,
  `var a = D; var b = a; var a = C;` gives b == 5 (through 6.7.14, 3); `var G = 0; var b = G; var G = C;` b == 5 (was
  0); `var a = E.A; var b = a; var a = E.B;` b == E.B (was E.A). A call between the two that WRITES it keeps its write:
  `var G = D;` (or `= 0`) then `var r = setg(); var G = C;` ends at setg's value (was reset to C). The literal
  spellings already behaved this way and are unchanged. If the read meant the earlier value, spell it under another
  name (`var a0 = D; var b = a0;`); if the constant must win over the call, assign it after the call (in a fn, or as a
  top-level statement).
- ⚠ Changes what it computes (beyond D2's text): an earlier COMPUTED initializer before a named constant — `var a =
  f(); var b = a; var a = C;` gives b == C (was f()'s value; f still runs, its result discarded, as before a literal
  constant); and a list before a named scalar — `var B[1] = {3}; var c = load8(&B); var B = A;` — is evaluated for its
  errors only, so the read between sees A (was 3). Rename one of the two declarations if the read meant the earlier
  one.
- Unchanged: a bool global and an initializer naming another file's private const keep their startup store; a float
  literal redeclaration keeps declaration order (filed for 6.7.16, the user's call). Code is smaller: an earlier
  constant declaration of the slot leaves no startup store.

**FE-14 — a redeclared global whose constant is const- or enum-named is compared (no decision: the guide's § Declaring a global twice)**
- A new warning: a declaration-zone global redeclared with a const- or enum-named constant of another value, on either
  side — `var a = 3; var a = C;`, `var a = C; var a = 3;`, `var a = 3; var a = E.B;`, `var a = D; var a = C;`,
  `var a = 0; var a = C;` — warns "duplicate symbol 'a' redefined with conflicting value (last definition wins)" once,
  at the later declaration, as a literal pair always did. A warning only: the value (the last definition) and the exit
  code are unchanged. Give the declarations the same value, or rename one. (No new warning in `lib/`.)
- Moved / added warnings in a chain: each later constant is compared with the last constant before it, so `var a = 3;
  var a = C; var a = 5;` (C 5) warns at the `C` line (it warned at the `5`), and `3`, `C`, `4` warns twice. A literal
  pair with a computed initializer between (`var a = 3; var a = f(); var a = 5;`) gives the same warning at the same
  position, printed later in the stderr. A script that matches warning lines in order reads the new order.

**FE-15 — a declaration-zone struct or tuple literal of constants is not stored again at startup (6.7.14's D11 (b) applied to a literal; ⚠ beyond D11's text — the literal-redeclaration question is filed for the user, 6.7.16)**
- Changes what it computes: a declaration-zone global initialized with an all-constant struct or tuple literal
  (`var p = P { 1, 2 };`, `P { b: 2, a: 1 }`, `var t = (1, 2);`) holds the literal from program start, with no startup
  store. A call in an EARLIER initializer that writes the global keeps its write — `fn setp(): i64 { p.a = 9; return 1;
  } var r = setp(); var p = P { 1, 2 };` ends with `p.a == 9` (through 6.7.14 the startup store reset it to 1) — and so
  does a call between two declarations of the same literal. If the literal must win, move the call after the
  declaration, or assign the literal in the program.
- Unchanged: a redeclared literal of OTHER bytes is still stored at its place in declaration order (`var p = P { 1, 2 };
  var b = p.a; var p = P { 3, 4 };` gives b == 1; a call's write between them is overwritten by the later literal) —
  unlike a scalar constant under D2 (a). Whether literals follow D2 (a) is the user's open question (filed, 6.7.16): do
  not rely on either reading of a redeclared literal across that boundary. Every diagnostic the elements get is still
  given. Startup code is smaller (71 of the corpus's test binaries).

**FE-16 — a declaration-zone float global's constant f64 expression is baked (D46, the user 2026-10-18 — Keep, for a float literal; ⚠ beyond D46's text: a constant f64 expression)**
- Changes what it computes: a declaration-zone float global whose initializer is an f64 const, a parenthesized literal
  or f64 arithmetic of them (`var G: f64 = CF;`, `= (1.5)`, `= 1.5 + 1.0`, `= -CF`, an `f32` `= CF` as its binary32
  rounding) is its value from program start, as a float literal has been since 6.7.14. An EARLIER initializer that
  reads it now sees the value (it read 0); a call in an earlier initializer that writes it keeps its write (the startup
  store reset it). Reorder the declarations if a code path relied on the old reading.
- An x86 `kernel;` build reads the value (it read 0) and no longer warns "the initializer of 'G' runs after the
  top-level program" for it.
- Unchanged: a call, a NaN result (`0.0 / 0.0`) and f64 arithmetic with an integer or enum operand (`1.5 + 1`, warned as
  a mix) remain startup stores (in a `kernel;` build still late and named — filed, 6.7.16).

Nothing to migrate (diagnostics on code that never compiled, refused code that now compiles, or gates): FE-1 (a
constant left operand then `+ - & | ^` and a literal before `*%` / `*|` / `*?` / `>>>` — `2 + 3 *% 4` — now compiles
with its value; it was refused "expected ';'"), FE-2 and FE-3 (gate files: `default_named_args_checked.sh` under
`bash -eo pipefail`, `cyriusly_setup_bootstrap_and_env.sh` C2), FE-4 (a default on a bare `u128` parameter is the one
type refusal, no "it takes no default"), FE-7 (an unclosed wrap around a declaration's struct literal initializer is
"expected ')', got ';'" alone), FE-9 (a method call / subscript in a `const fn` and a method on a const name their rule
— "a method call is not in a const fn: it calls only const fns", "a subscript is not in a const fn: ...", "const 'C' has
no methods - a const has no storage" — where they said "expected ';'", "no struct type in scope for 'a'" or "undefined
variable 'L'"), FE-10 (a refused const fn's run-time body: no false "undefined variable 'k'", no repeated refusal),
FE-11 (two refused in-place const contexts in a row — enum values, global array sizes, `#assert`s — each print; an
`#assert` after another declaration's error prints its own refusal, not "#assert failed"), FE-12 (a refused global type
change is one error with no conflicting-value warning; the mirror `var G = 5; var X: bool = G; var G: bool = true;` now
also reports X's own error), FE-17 (a `struct` / `enum` / `union` / `trait` / `impl` inside a fn body or block is one
error naming the rule, where it said "unexpected struct" and up to four more), FE-18 (a use of what a refused
declaration names adds no error of its own).

#### Infra and tools — IR=3, cybs, include-once, asm operands and barriers, the DCE seed pass, the CLI (the infra / tools lane)

Each block names its CHANGELOG [6.7.15] bite (the infra / tools lane, IT-*). D37 and D49 are the user's decisions at
the 6.7.15 open (2026-10-18); "6.7.14's D16" is the 6.7.14 open's (2026-10-16: refuse an asm block naming an instruction
or operand the assembler does not have, by name). Everything else is fixed to what the source says. Outside the four
blocks below, nothing in this lane changes what a default build (no `CYRIUS_IR`) produces: IT-9's output is
byte-identical on every target.

**IT-5 — include-once keys on the whole spelling (no decision: the documented include-once semantics)**
- Changes what it computes: a program that `include`s the same spelling of 128 or more characters twice — easy through
  directories, or an absolute `~/.cyrius/deps/<name>/<version>/…` path — now gets the file once: its top-level statements
  run once and its fns are defined once. Through 6.7.14 (since v4.8.4-alpha2, on every target) the second `include` ran
  the file's top-level statements again and defined its fns a second time (the later definition binding, 6.6.20), with
  no message.
- Unchanged: two different spellings of one file (`"./a.cyr"` / `"a.cyr"`) are still two includes; a compilation unit
  still holds at most 256 distinct includes, and the 257th is still `include-once table full (256 files)`.
- **Migrate:** nothing to change for code that meant to include the file once. Code that (unknowingly) depended on the
  double run — a top-level counter bumped twice, a second copy of a fn that differed — now sees the file once; if its
  top-level work must happen twice, put it in a fn and call that twice.

**IT-6 — x86 asm `lgdt` / `lidt` / `invlpg` / `mov crN` / `ltr` encode the register they name; an operand they cannot take, and an `int` vector over 255, are refused (no decision for the encodings; 6.7.14's D16, the user 2026-10-16, for the refusals)**
- Changes what it computes: an x86 `asm { }` block that names a register other than rax in `lgdt [reg]` /
  `lidt [reg]` / `invlpg [reg]` / `mov crN, reg` / `mov reg, crN`, or other than ax in `ltr`, now gets THAT register —
  `lgdt [rbx]` 0F 01 13, `lidt [rcx]` 0F 01 19, `invlpg [rdi]` 0F 01 3F, `mov cr3, rbx` 0F 22 DB, `mov rbx, cr3` 0F 20
  DB, `ltr bx` 0F 00 DB, r8 – r15 with their REX prefix (`lgdt [r12]` 41 0F 01 14 24, `mov cr0, r8` 41 0F 22 C0). Through
  6.7.14 each silently used rax / ax: `lgdt [rbx]` loaded the GDT from `[rax]`, and `mov rbx, cr3` overwrote rax and
  left rbx as it was.
- Changes what it computes: `asm { mov cr8, rax; }` now writes CR8 (44 0F 22 C0). Through 6.7.14 it wrote CR0
  (0F 22 C0).
- **Migrate:** kernel code that loaded the operand into the register it named gets what it wrote. Code that staged the
  value in rax but named another register must name rax, or move the value into the register it names. Code that wrote
  `mov cr8, rax` and was (unknowingly) writing CR0 must say `mov cr0, rax` if CR0 was meant.
- Stops compiling (D16), naming the operand, rc 1:
  - a control register other than cr0 / cr2 / cr3 / cr4 / cr8 — `mov cr9, rax` (was `mov cr1, rax`), `mov cr1, rax`:
    `mov takes a control register (cr0, cr2, cr3, cr4 or cr8) and a 64-bit register, not 'cr9'`;
  - a register that is not a whole 64-bit name beside crN or inside the brackets — `mov cr3, eax`, `lgdt [eax]`, a
    misspelled `lgdt [raxx]` (each assembled with rax): `lgdt takes one 64-bit register in brackets, [rax] to [r15], not
    'eax'`;
  - an `ltr` operand that is not a 16-bit register — `ltr eax`, `ltr r8d` (each was `ltr ax`): `ltr takes a 16-bit
    register, ax to di or r8w to r15w, not 'eax'`;
  - an `int` vector over 255 — `int 256` (was `int 0`), `int 0x1FF` (was `int 0xFF`): `int takes a vector from 0 to 255,
    not '256'`.
- **Migrate:** write the operand the instruction takes: a 64-bit register (`rax` – `r15`) for `lgdt` / `lidt` / `invlpg`
  and beside a control register, a 16-bit one for `ltr` (`ltr ax`, `ltr r8w`), a vector 0 – 255 for `int`.
- Unchanged: shapes the assembler already refused (`lgdt rax`, `lidt rax`, `invlpg [rax + 8]`, `int foo`,
  `mov rax, rbx` — `unexpected …`) are still refused; the message now names the operand. The guide's spellings
  (`lgdt [rax]`, `lidt [rax]`, `invlpg [rax]`, `mov cr3, rax`, `mov rax, cr3`, `mov cr0, rax`, `ltr ax`, `int 3`) and every
  spelling in lib/ and the corpus keep their bytes.

**IT-7 — aarch64 asm `dmb` / `dsb` / `isb` are the full-system barriers and `wfe` is WFE (no decision: the words were wrong instructions)**
- Changes what it computes: on aarch64 (Linux and macOS), `asm { dsb }` now emits DSB SY (D5033F9F). Through 6.7.14 it
  was SSBB (D503309F), a speculative-store-bypass barrier that orders no memory accesses: code relying on `dsb` for the
  completion of memory accesses — device or page-table writes, a kernel's TLB maintenance — gets that barrier for the
  first time.
- Changes what it computes: `asm { wfe }` now waits for an event (D503205F). Through 6.7.14 it was
  `msr S0_3_C1_C0_1, x0` (D5031020), UNDEFINED at EL0 — a user program died with SIGILL there; it now proceeds.
- The bytes change, the behaviour does not: `dmb` (D50330BF → D5033FBF) and `isb` (D50330DF → D5033FDF) encoded the
  reserved option #0, which the architecture runs as `sy`; they are now the `sy` words.
- **Migrate:** nothing to change in source. A test or gate that pinned the old words refreshes them. A bare barrier is
  the full-system one; for a narrower barrier, write its option (`asm { dmb ish }`, IT-8). qemu-user ran both the old and
  the new words without a trap, so check barrier words with a decode (`llvm-mc --disassemble`), not by running them.

**IT-11 — a killed `cyrius deps` gives its git 2 s, then SIGKILLs it (D49, the user 2026-10-18)**
- Changes what the CLI does: when `cyrius deps` (or a build that resolves) is stopped by SIGTERM / SIGINT / SIGHUP while
  its own git runs (the cached checkout's verify, a clone), git is still sent the signal, but one still running 2 s later
  is SIGKILLed and reaped; the CLI then dies by the signal (`$?` 128+N, 6.7.13's D39). 6.7.14 waited for as long as git
  ran, and a second Ctrl-C was held until then (7.75 s for the filed git that ignores SIGTERM and sleeps 8 s; now 2.0 s
  on x86_64 Linux and pi, 2.4 – 2.5 s on macOS).
- Unchanged: real git exits on the signal and runs its own cleanup (its `index.lock`, a killed clone's partial cache
  directory), as in 6.7.14; the CLI's own forked copies (the distlib verify) are still waited for; Windows (no fork, no
  POSIX signals) is unchanged.
- **Migrate:** a `git` wrapper first on `PATH` that traps the signal must finish its cleanup within 2 s, or it is
  SIGKILLed mid-cleanup. § 6.7.14's TL-6 line "⚠ Filed (6.7.15): the wait has no bound" is history.

No block for the lane's other bites:
- IT-1: a `CYRIUS_IR=3` constant fold over a dead store faulted (or held a wrong constant) and computes what the default
  build computes now; default builds are unchanged.
- IT-2: a gate — the whole `.tcyr` corpus under `CYRIUS_IR=3` + `CYRIUS_DCE=1` (~45 – 70 s of serial check.sh work).
- IT-3 / IT-4: cybs, which builds only cyrius's own `src/` and `bootstrap/asm.cyr` — a top-level indexed store to the
  last fn's local name is named (it got the class message); a 257th distinct include and an include path of 256+
  characters are refused by name (one was silently skipped, the other included twice); a 256th include with a 249 – 255
  character path, which was silently skipped, is included.
- IT-8 (D37): nothing that compiled changes. `dmb` / `dsb` with `sy`, `st`, `ld`, `ish`, `ishst`, `ishld`, `nsh`,
  `nshst`, `nshld`, `osh`, `oshst` or `oshld`, and `isb sy`, start compiling to that barrier — the guide's `#ifplat`
  example `asm { dmb ish }` among them — and a bare barrier stays the full-system one. A word after a barrier that is no
  option was refused before as an unknown mnemonic and is refused now naming the barrier's options (`dmb foo`,
  `isb ish`). lib/atomic.cyr's hand-written `dmb ish` bytes (BF 3B 03 D5) can now be spelled `asm { dmb ish }`. `svc #0`
  still cannot be written (`#` starts a comment); a bare `svc` is `svc #0`.
- IT-9: output byte-identical (763 inputs × 12 target / DCE modes, the notes included); compile time only — a
  16,000-fn program's FIXUP 9,934 → 114 ms, cycc's self_compile 1,980 → 1,278 ms.
- IT-10 / IT-9r: gates that now give their verdict under `bash -eo pipefail`.
- IT-12: a killed scratch resolve (`cyrius deps --locked`, a moved pin's dry pass) unlinked a file another same-user
  process had put at the copy's predicted temp name, inside the CLI's private temp dir; it unlinks only the temps it
  created now, and a signal that arrives during one exclusive create is delivered right after it. § 6.7.14's TL-7 line
  "⚠ Filed (6.7.15): a file … planted at the copy's predicted temp name … is unlinked by the kill" is history.

#### Platform — pipefail gates, TLS hello length, PE close / seek, the native-region warning, cxvm renumbering, the Windows CTL, the TypeScript front end on every compiler (the platform lane)

Each block names its CHANGELOG [6.7.15] bite (the platform lane, PL-*). D38, D39 and D40 are the user's decisions at the
6.7.15 open (2026-10-18); 6.7.15's D55 kept 6.7.14's Windows errno answers. "6.7.14's Dn" / "6.7.12's Dn" are ids from
those opens. PL-5, PL-7, PL-8, PL-10 – PL-12 needed no decision: each is fixed to what the source or the wrapper's
documented contract says.

**PL-5 — native TLS: the 1.2 client's ServerHello and the 1.3 server's ClientHello extension blocks fill their message (no decision: the 6.7.14 conformance precedent, the RFCs' decode_error)**
- A peer whose TLS 1.2 ServerHello carries bytes after its extension block now fails the native 1.2 client's handshake:
  `TLS_ERR_BAD_HANDSHAKE`, and a decode_error alert is sent. It used to complete.
- A TLS 1.3 ClientHello with bytes after its extension block is refused by `tls_native_accept` (decode_error). It used
  to be answered.
- Well-formed hellos — OpenSSL's, the native stack's — are unaffected.
- **Migrate:** nothing for a program; the fix is on the peer, which sends bytes no structure names (RFC 8446 §4 /
  RFC 5246 §7.4.1). A test harness that hand-builds a hello must set the handshake length to end at the block.

**PL-6 — native TLS: the 1.2 server refuses a ClientHello whose extension block does not fill the message (D40)**
- `tls_native_accept_12` (and `tls_native_accept`, through its version sniffer) refuses with decode_error
  (`TLS_ERR_BAD_HANDSHAKE`, the alert sent) a TLS 1.2 ClientHello that carries:
  - bytes after its extension block;
  - an extension block longer than the message — which used to negotiate as if the client had sent no extensions
    (no extended master secret, no ALPN, the server's first group);
  - one byte where the block's 2-byte length goes.
- Unchanged: a ClientHello with no extension block at all negotiates without extensions, as before.
- **Migrate:** nothing for a program. A client that a 6.7.14 native 1.2 server accepted with a malformed block now
  fails its handshake; fix the client's hello.

**PL-7 — Windows: a close answers 0, or a negative errno (no decision: fixed to what `sys_close` documents)**
- Windows only. `sys_close` / `file_close` answer 0 for a good close (it was 1) and a negative errno for a failed one (it
  was 0): a handle that is not open gives -9, as on Linux.
- `file_close_r` answers `Ok(0)` / `Err(IoBadFd)` (it was `Ok(1)` / `Ok(0)`).
- `sys_close(0 / 1 / 2)` answers -9 (it was 0), and the std stream stays open — ECLOSE_PE passes the std fds as raw
  HANDLE values (filed, 6.7.16). Linux closes it.
- **Migrate:**
  - Code that tested a Windows close with `!= 0` or `== 1` as success must test `== 0`, or `>= 0` (the portable form).
    No in-tree caller did: every one compares `< 0`, which now fires on a failure.
  - Code that matched `Ok(1)` from `file_close_r` on Windows matches `Ok(0)`, and handles `Err(IoBadFd)`.
  - Do not close fd 0 / 1 / 2 on Windows to release a std stream; it stays open there.

**PL-8 — Windows: a seek on fd 0 / 1 / 2 reaches the std stream (no decision: a codegen defect; 6.7.15's D55)**
- Windows only. With a redirected stdin, `xlseek(0, n, SEEK_SET)` moves where the next read starts, and `SEEK_CUR` /
  `SEEK_END` on a redirected stdout / stderr answer the position. They failed -9 (in 6.7.13, 0).
- A seek on a PIPED or console std stream now SUCCEEDS on real Windows (it was -9): it answers the offset asked and the
  stream does not move. Wine answers -1. Linux and macOS answer -29 (ESPIPE) — the Windows answer is filed (6.7.16).
- **Migrate:** code that told a pipe from a file on Windows by `xlseek(0, 0, SEEK_CUR) < 0` no longer can: there, a
  seek on a pipe looks like a seek on a file. Do not depend on a std-fd seek's failure to detect a pipe on Windows.

**PL-9 — ELF-aarch64: a syscall constant your own per-arch file declares is judged by the region it is included under (D39; 6.7.12's D1, warn only)**
- Warn only: no binary changes. On an aarch64 build, a constant (an `enum` member or a top-level `const`) declared at
  the top level of a file OUTSIDE `lib/` that is included from inside `#ifdef CYRIUS_ARCH_AARCH64`, and passed to
  `syscall()` with a number a compat row renumbers, now warns:
  `syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered → 172 (getpid); write 1039 for native umount2`.
  It ran the renumbered call silently before.
- A file under `lib/` — its include name starts `lib/` or has a `/lib/` component, as written — keeps the 6.7.14 rule:
  only a region opened in the file itself counts. So programs that include the stdlib stay at 0 warnings.
- **Migrate:** for each warning, spell the number the way the warning says — the `1000 + N` alias for a native number —
  or use the `SYS_*` name / wrapper from `lib/syscalls.cyr`. A vendored, stdlib-style peer belongs under `lib/`.

**PL-10 — ELF-aarch64: a fn-local `const` declared inside a native-aarch64 region is judged (no decision: the filing's fix; 6.7.12's D1, warn only)**
- Warn only: no binary changes. A `const` declared inside a fn body in an aarch64 region and passed to `syscall()` with a
  number a compat row renumbers now warns, with the same `syscall constant NAME = N, declared inside a native-aarch64
  region, …` text. A const declared outside a region and used inside stays silent. An `#inline` fn's local const is
  judged where it is declared in the inline body, never at the call site; its warning repeats once per call (filed,
  6.7.16).
- **Migrate:** as for PL-9 — the `1000 + N` alias, or the stdlib's `SYS_*` name.

**PL-11 — cx: a guest's listed syscalls run the call they name on every host (no decision: a cxvm defect; -38 where the host has no route is 6.7.14's D55)**
- On an aarch64 Linux or macOS host, a `.cyx` now runs the call it names for getppid / kill / dup / lseek / sched_yield /
  exit_group / fork, `open`'s flags and `fcntl`. It got other calls' answers before (on pi a guest lseek ran getxattr
  and fork ran close, so the parent took the child branch), or cxvm died of SIGSYS (ecb).
- socket / listen / unshare / timerfd_create / epoll_create1 answer -38 off Linux.
- On a Windows host: getpid, exit_group, fsync and ftruncate now work; getppid, kill, dup, dup2, flock, fchmod, fchown,
  the uid / gid getters, sched_yield, fork and fcntl answer -38 (the PE peer has only stubs for them). A guest open goes
  through the PE peer's `sys_open` (its O_NOFOLLOW / directory checks), as a native program's does.
- Off x86_64 Linux and Windows, `open` / `F_SETFL` flag bits outside the access mode and O_CREAT / O_EXCL / O_TRUNC /
  O_APPEND / O_NONBLOCK / O_DIRECTORY / O_NOFOLLOW / O_CLOEXEC are dropped (they reached the host raw, often as another
  flag), and `F_GETFL` reports only those nine (arm64's O_LARGEFILE is no longer seen: fd 1 reads 1 where the x86 cxvm
  reads 0x8001 — filed, 6.7.16).
- Still Darwin's on a macOS host (filed, 6.7.16): a failed call's errno (ELOOP reaches the guest as -62, not -40), and
  `kill`'s signal number (a guest SIGUSR1 10 is Darwin's SIGBUS).
- **Migrate:**
  - A `.cyx` that worked around the wrong calls on an aarch64 or macOS host (it should not have had to) drops the
    workaround.
  - Check every syscall result on cx: on Windows the stub calls answer -38.
  - On a macOS host, test a failure with `< 0` rather than a specific errno value, and do not send a signal that Linux
    and Darwin number differently (SIGUSR1, SIGCHLD and SIGSTOP among them) from a cx guest until the filed signal issue
    lands.
  - Run a `.cyx` on its own release's cxvm.

**PL-12 — cx: mkdir, rmdir, unlink, rename, symlink, readlink and stat work under cxvm (no decision: 6.7.14's D55, one call at a time)**
- On cx, `sys_unlink` / `xunlink`, `xmkdir`, `xrmdir`, `xsymlink`, `xreadlink`, `xstat`, `file_rename` and
  `file_write_atomic` now act on the host (they answered -38, and `file_write_atomic` left `<path>.cyrtmp.<pid>.1`
  behind). `sys_unlink`'s cx arm (-38 since 6.7.12) is removed.
- A path or buffer outside the guest segment answers -14 (EFAULT) without reaching the host.
- A cx `stat` fills the x86_64 Linux layout. Off x86_64 Linux it fills only mode, nlink, uid, gid, size, mtime and mtime
  nsec; st_dev / st_ino / st_blocks / atime / ctime read 0.
- On a Windows host readlink and stat answer -38 (no route); the rest are served.
- **Migrate:**
  - A cx program that tested for the -38 (as `uid_identity.tcyr`'s cx arm did) sees the host's answer: -2 for a missing
    name, 0 for a made directory.
  - A cx program that reads st_ino / st_dev / st_blocks or atime / ctime must not rely on them off an x86_64 Linux host.
  - A cx probe file is now really unlinked: a test that left one behind on purpose must not count on it staying.

**PL-13 — the TypeScript front end on every compiler (D38)**
- On aarch64 Linux (cross and native), both macOS compilers and Windows (`cycc.exe` and its Linux-hosted cross
  compiler), `cycc --lex-ts` / `--parse-ts` / `--emit-js` now run the TypeScript front end — exit 0 / 1, the same
  diagnostics and JS bytes as x86_64 Linux, from stdin or `<flag> <file>` — where they ignored the flag and compiled
  stdin as cyrius. `ts_test_runner` works on an aarch64 install (pi: 1/1).
- On Windows a `<file>` path may be quoted or non-ASCII: the command line is split as CommandLineToArgvW splits it.
- `cyrius build --target=js` now runs on aarch64 Linux and macOS (it refused by name since 6.6.6). On Windows it still
  refuses by name, now saying `cycc.exe` has `--emit-js` and to run `cycc.exe --emit-js <file.ts> > <out.js>` directly.
- The installed compilers there are ~0.26 – 0.34 MB larger. `cycc_cx` has no TS front end.
- ⚠ A `--parse-ts` / `--lex-ts` / `--emit-js <file>` path that, with argv[0] and the flag, passes the 255-byte
  `/proc/self/cmdline` read is cut, and the cut name is opened (filed, 6.7.16). That read is the x86_64 Linux driver's
  since v6.0.5, and since 6.7.15 also the aarch64 Linux drivers' and the Linux-hosted Windows cross compiler's; the
  macOS drivers and `cycc.exe` read the whole command line. Keep TS paths short there, or pipe the file on stdin.
- **Migrate:** a script that relied on the flag being ignored off x86_64 Linux (none should) now gets a TS verdict or JS.
  Drop any "run TS work on x86_64 only" workaround.

**PL-14 — Windows trust store: the disallowed CTL's 20, 32 and 64-byte entries are applied (no new decision: 6.7.14's D57 reading carried to every length)**
- Windows only, and latent: a native TLS ctx using the system roots (`tls_native_set_ca_system`) refuses a certificate
  whose signature hash the CTL lists at 20, 32 or 64 bytes — the tbsCertificate hashed with the certificate's own
  SHA-1, SHA-256 or SHA-512 signature digest (crypt32's prop 15). Today's CTL has no entry of those lengths. A
  certificate is judged only by the entries of its own digest's length; RSASSA-PSS, Ed25519 and MD2 / MD5-signed
  certificates are not judged by them. A ctx given a caller's bundle, and POSIX, are unchanged.
- The underscore-private API, for code that calls the stdlib's private fns (only the tests do):
  - `_tn_w_ctl_copy(ctl, pn, pt, pnt)` → `_tn_w_ctl_copy(ctl, pn, sig)`;
  - `_tn_w_ctl_keys(pn, pt, pnt)` → `_tn_w_ctl_keys(pn, sig)`;
  - `_tn_pol_set_tbs384(pol, n, h)` → `_tn_pol_set_sighash(pol, 48, n, h)`;
  - `_tn_tbs_sha384` (1 / 0 / -1) → `_tn_tbs_sighash` (20 / 32 / 48 / 64 / 0 / -1);
  - the trust-policy block is 112 B (`_TN_POL_LEN`, was 64); its 48-byte list moves +48 → +80 (`_tn_pol_sig_off`).
- **Migrate:** nothing for a caller of the public API. A caller of the private fns passes the 64-byte {count, ptr} table
  (`sig`) where it passed the 48-byte list's two out-parameters.

No block for PL-1 – PL-4 (gates only), PL-15 / PL-16 (patra 1.16.5's tests; the fold's own block is written at the
refold, after the user's tag — the libfix lane's later commits to 1.16.5 change `dist/` code) or PL-11r (comments, docs
and a gate message).

#### Structs — forward calls of a struct declared below, `*pp` copies, inline `Str` sources and destinations, `&` / `return &` / parenthesised destinations, call-result statements (the structs lane)

The 6.7.15 decisions are the user's at the 6.7.15 open (2026-10-18): D14 – D20, D58, D60. Ids from other releases are
written with their release:
- **6.7.14's** (2026-10-16): D18 (c), D19 (a), D20 (a), D21 (a), D24 (a), D41 A.
- **6.7.13's** (2026-10-15): D4 (a), D7 (1), D9 (a).
- **6.7.10's:** decisions 5 and 6.

Each block names its CHANGELOG [6.7.15] bite.

**ST-1 — a forward call reads the signature of a fn whose struct is declared below it (no decision: pass 1 read the signature before the struct was registered; 6.7.14's D41 A for a vector-named struct)**
- Starts working: a call parsed ABOVE a fn whose parameter or return names a struct declared BELOW that fn compiles
  and runs as with the struct declared first. A 16 / 24 B by-value argument, a `: S` return (any size), a method's
  parameter, `One<B16>` / `Low<B24>` instances and a struct named like a vector (`f32v4`) faulted (139 on x86_64 /
  aarch64, a cx guest fault, PE 5); `h(t)` into `x: *S` was refused "pass &t"; an untyped `var t = mk(10);` was "no
  struct type in scope"; a vector-named struct's return was "vector return type does not match". The `: *S` / `: **S` /
  `: *Box<S>` / `: **Box<S>` returns of such a fn are right too (`var t: S = *mk();`, `take(*mk())`, `mk().x`).
- Stops compiling: such a forward call that passes a struct of ANOTHER type to a struct parameter — "cannot pass 'p' to
  a parameter of a different struct type in a call to 'g'", as with the struct declared above. It compiled and passed
  the wrong layout (a word read as an address over 8 B). Pass a value of the parameter's own struct.
- Changes codegen, not behaviour: include order can put a library's struct below another library's fns. A program that
  includes `lib/sigil.cyr`, `lib/bayan.cyr`, `lib/tls_native.cyr` or `lib/ws*.cyr` BEFORE `lib/str.cyr` has
  `struct Str` below bayan's fns; their forward calls' `: Str` results and `s: Str` parameters now carry `Str`, as calls
  below the definitions already did. The binary can differ (a `Str` local is not register-allocated); the seven corpus
  programs with this order behave the same. A forward call passing a non-`Str` struct to such an `s: Str` parameter
  stops compiling, as above (it was a miscompile).
- Unchanged: a program whose structs precede their fns builds byte-identically (the signature is never re-read).

**ST-2 — `*pp` of a `**S` as the whole source of a copy copies the struct (no decision: 6.7.13's D9 (a) makes `*pp` a `*S`, and a `*S` source copies its pointee, 6.7.11)**
- Changes what it computes:
  - In a fn, `var t: S = *pp;` (and `var t: S = (*pp);`) with pp a `**S` now COPIES the struct. It bound t to the struct
    as a handle, so a write through t changed the original and a later write to the original showed in t. To keep the
    alias, declare the pointer: `var t: *S = *pp;`.
  - `l = *pp`, `G = *pp` (in a fn or at top level), `*q = *pp`, `**qq = *pp` and a for step `l = *pp` copy the whole
    struct. They stored the pointer `*pp` holds into the first field and left the rest stale.
- Stops compiling: `l = *qq` with qq a `**Q` and l an `S` of another struct (also `var t: S = *qq;`, `*p = *qq`, a
  top-level `G = *GQQ`) — refused by name ('qq'), as `l = q` from a `*Q` is. It stored the pointer. Copy from a value
  of l's own struct.
- Unchanged: `q = *pp` into a `*S` or a handle stays the rebind `q = p` is. A TOP-LEVEL declaration
  `var G: S = *GPP;` still binds a handle (filed, 6.7.16), and a struct-typed FIELD destination `o.s = *pp` still
  stores the pointer word (filed, 6.7.16): write `var p: *S = *pp; o.s = p;`.

**ST-6 — an inline `Str` assigned into a `*Str` takes its header's address (D16, the user 2026-10-18)**
- Changes what it computes: `p = t` and `p = gt` (p a `*Str` local or parameter; t / gt an inline `Str`, a
  `Str { .. }` literal or a bare `var t: Str;`) and `GP = gt` (GP a `*Str` global) now store the header's address, so
  `str_len(p)` is t's length and `p.len = 3` writes t.len. They stored t's data word, so the string's bytes were read
  as a header. Also wrapped, in a for step and at top level. `GP = gt` no longer warns "assigning non-pointer to typed
  pointer".
- Stops compiling: `GP = t` with t a fn's own inline `Str` and GP a `*Str` GLOBAL — "cannot store the inline Str 't'
  into a global - its header lives in this frame and would dangle (store a handle: str_new(data, len))". Store
  `str_new(t.data, t.len)` instead. (A closure's captured copy is not refused.)
- Unchanged (filed, 6.7.16): a `*Str` FIELD destination (`w.p = gt`) and `*pp = gt` through a `**Str` still store the
  data word; assign through a `*Str` local first.

**ST-7 — a `*Str` dereference into a `Str` parameter passes the header (no decision: 6.7.10's decision 6, `*p` of a `*Str` is the header)**
- Changes what it computes: `f(*p)` with p a `*Str` and f taking `s: Str` — `str_len(*p)`, `str_eq(*p, *q)`, the
  `Str` methods' operand (`h.eq(*p)`), user fns — and `**pp`, `*w.p`, `*gp()`, `*(p + 0)` of the same now pass the
  header p points at. The result changes from garbage (a length read from the string's bytes) to the right value.
- Changes what it computes: a program that typed a HANDLE'S SLOT as a `*Str` — `var p: *Str = &h;` with h a `Str`
  handle (`&h` is the slot, not a header: the guide's handle line) — and passed `*p` now gets the slot read as a header
  (`str_len(*p)` was h's length; now garbage, 0 in the measured program). Write `var p: *Str = h;` (the handle IS the
  header's address), or pass `h`.
- Unchanged: a `p: *Str` parameter given `*pp`, and an untyped parameter given `*p` (the word). A generic's `x: T` at
  T = Str given `*p` still passes the data word (filed, 6.7.16): pass `p` to a `Str` parameter.

**ST-8 — `t = p` / `t = *p` from a `*Str` copy the header into an inline `Str` (D14, the user 2026-10-18)**
- Changes what it computes: `t = p` and `t = *p` (t an inline `Str`, p a `*Str` local, parameter or global; also
  `*E` of any `*Str`-typed E — `**pp`, `*w.p`, `*gp()`) now COPY the 16-byte header. t.len is the string's length, and
  a later write through p no longer shows in t. They stored p (or the header's data word) into t.data and left t.len
  stale; code that relied on that pun (reading the string back through t.data) gets t's own copy. `t = *p` no longer
  warns.
- Unchanged: `t = *pp` with pp a `**Str` still stores one word (filed, 6.7.16): write `var p: *Str = *pp; t = p;`. An
  if-expression of handles keeps the one-word store (D15, ST-9): assign in each branch. `h = *p` into a `Str` HANDLE
  stores the data word (filed as a decision, 6.7.16).

**ST-11 — `*pu` through a typed `*u128` is refused (D20, the user 2026-10-18)**
- Stops compiling: `*pu`, `*pu = v` and `*pu OP= v` with pu a typed `*u128` — a local, parameter, global, field,
  capture, a call or method declared `: *u128`, `pu + n`, a wrap, `**pp` of a `**u128` — "cannot dereference 'pu': a
  u128 element does not fit one register - use load64/store64 on its two halves". They read / wrote the low 8 bytes
  only (`var x: u128 = *pa;` dropped the high word, `*pa = b` left the old one). Use `load64` / `store64` on the two
  halves: the low at `pu`, the high 8 bytes past it through an untyped address (`var w = pu; load64(w + 8)`, or
  `load64(&a + 8)` for a u128 `a`) — `pu + 8` on a typed `*u128` steps 8 ELEMENTS (128 bytes). Or copy the whole value
  through a u128 name (`var x: u128 = a;`).
- Unchanged: an untyped pointer (`var p = &b; *p`, `var q = pa; *q`) reads and writes the low word, as before; `*&a`;
  `var q: *u128 = *ppa;` (the `*u128` a `**u128` holds).

**ST-14 — `return &n;` of a name holding no struct, in a fn returning a struct, is refused (D18, the user 2026-10-18)**
- Stops compiling: `return &n;` (or `return (&n);`) in a fn declared to return a struct S, where n is an integer, a
  `*i64` / `*f64v2`, a `**S`, an array, an inline vector, an `f64` / `u128`, or a `Str` handle — a local, a parameter or
  a global — at 8 bytes or less: "a fn returning the struct `S` takes a value of that struct, or a pointer to one —
  `&n` is the address of n's slot, not a struct" (a `Str` handle adds ", and t is a `Str`"). It returned the slot's
  stack address as the struct's first field: a garbage value, different each run. Over 8 bytes it was already refused
  and now names n. Return the struct value (`return s;`) or, for a pointer to an S, `return p;` / `return *pp;`.
- Stops compiling: `return &t;` of an inline `Str` or a tuple in a fn returning a plain struct — "… — got `&t` (a
  `*Str`)", as `&u` of another struct is. It returned the aggregate's address as the struct's word.
- Unchanged: `return &s;` of an inline struct of the fn's own struct is still the struct (6.7.13's D4 (a)). A generic
  `fn hg<T>(x: T): S8 { var n: T = x; return &n; }` is judged per instance (`<S8>` compiles, `<i32>` is refused), but
  its i64 base, `hg(3)`, still compiles and returns the slot's address (filed, 6.7.16) — do not write it.

**ST-16 — a field read alone through parentheses is refused (D60, the user 2026-10-18)**
- Stops compiling: a statement that is only a field read through parentheses, with no call in it — `(s).a;`,
  `(p).a;`, `(*p).a;`, `(w).p.a;`, `(GS).a;` — "the field read 'a' is discarded - a statement is an assignment or a
  call". It compiled in 6.7.14 only, and did nothing; 6.7.13 refused it ("unexpected '('"). Delete the line, or assign
  the value (`var x = (s).a;`).
- Unchanged: a statement with a call in it — `(mk1()).a;`, `(s).m();`, `(s).me().a;`, `(x + y).b;` with a struct
  operator — compiles, as without the parentheses.

Nothing to migrate in twelve bites:
- **ST-3** (D: none). `**pp OP= v` is refused naming '*pp' with the hint `**pp = **pp + b`; refused before and after.
- **ST-4** (D: none). A generic's `pp: **Box<T>` parameter compiles; it was refused. Through it, an inferred call with a
  `*Box<Pt>` binds no T yet and runs the i64 base (filed, 6.7.16): write `nb<Pt>(&q)`.
- **ST-5** (D17, the user 2026-10-18). A declaration-zone `var H: Str = gt;` with gt declared below binds H to gt's
  header; it was refused.
- **ST-9** (D15, the user 2026-10-18). `t = if (c) { a } else { b };` into an inline `Str` keeps the one-word store,
  documented; nothing changes. Assign in each branch.
- **ST-10** (D: none). A method on a `Str` field (`w.s.len()`, `w.s.clone()`) parses, its `self` the header the field
  holds; it was refused.
- **ST-12** (D: none). `&(x)` and other non-names after `&` are one error, not two.
- **ST-13** (D58, the user 2026-10-18). `return &pu;` of another struct's `*U` or handle stays refused (since 6.7.14);
  its advice no longer suggests `return pu;`.
- **ST-15** (D19, the user 2026-10-18). A parenthesised assignment destination (`(*p) += 1;`) stays refused, now "an
  assignment's destination is not parenthesised - write `*p += 1`". For a struct, the quoted `*(&s) -= 1` is itself
  refused (6.7.14's D17): operate on a field or write `s = s - b` with an operator fn.
- **ST-17** (D: none). `undefd().n += 1;` is "undefined function 'undefd'", once; `--allow-undef` does not downgrade it.
- **ST-18** (D: none). `cyrius lint` (`--syntax-only`) accepts `gp().n = 5;` on a sibling module's fn; nothing compiles
  differently. The cx compiler's `--syntax-only` still refuses it (filed, 6.7.16).
- **ST-19, ST-20** (D: none). A top-level `o.mk().p[0] = 5;` / `var x = mk().p[0];` with a by-value result is one error
  instead of two; it never compiled.

The review fixes ST-2r and ST-7r change a comment, the guide and the gates' headers only.

#### Vectors — the inline-replay High, vector calls into non-vector destinations, `*(&p)`, the generic `**T` / `***T` argument shapes (the vectors lane)

The decisions are the user's at the 6.7.15 open (2026-10-18): D21 – D24 and D26 – D29, each A. Ids from other releases
are written with their release:
- **6.7.14's** (the user, 2026-10-16): D8 (a), D27 (a), D37, D38, D39, D40.
- **6.7.13's** (the user, 2026-10-15): D29 (a method and `callptr(&f, ..)` / `fncallN(&f, ..)` declared to return a
  vector are that vector), D40.
- **6.7.11's:** D15 (`&x` is a byte pointer).

Each block names its CHANGELOG [6.7.15] bite. Every change below is in the frontend, so it is the same on x86_64,
aarch64, cx and Windows.

**VC-4 — a method declared to return a vector, on a field-chain receiver, is that vector at every receive (no new decision: 6.7.13's D29 A and 6.7.14's D37 / D38 / D39 apply to any receiver spelling)**
- Behaves differently: an unannotated `var v = w.s.mv();` is now an f64v2 local, where `mv` is declared `: f64v2` (any
  vector, a generic method too) and the receiver is a field chain (`w.s`, `pw.s` through a pointer, `h.w.s`, `n.ps`
  through a `*S` field). It was one word of stack garbage that moved between targets and builds (x86_64 104, aarch64
  144, cx 98, Windows 195, where 161 is right). Code that used it as an integer meets the vector rules.
- Stops compiling, every target: such a method stored into a destination that is no vector of its type. The
  destinations are `var x: i64 = w.s.mv();` and `x = w.s.mv();` (a for step too), an `f64`, struct or pointer local, and
  another vector's local, parameter or return. They stored a word (0 on x86_64 / aarch64, 41 on cx / Windows). The
  message is "vector return type does not match the declared type" / ".. the assigned variable".
- Migrate: receive the vector, `var v: f64v2 = w.s.mv();`, and read a lane with `load64(&v)`.
- Starts compiling (no change needed): the annotated `var v: f64v2 = w.s.mv();`, the assignment, a value-form argument
  and `return w.s.mv();`. They were refused "got `w`". `rd(w.s.mv())` into a `*f64v2` parameter passes a temporary; it
  faulted (Windows exit 5).
- ⚠ A receiver whose head is a parenthesised dereference or a call (`(*ps).mv()`, `gw(&w).s.mv()`) still binds one word.
  That is filed (6.7.16). Name the head: `ps.mv()` for `(*ps).mv()`, and `var pw: *W = gw(&w); var v = pw.s.mv();`
  for a call head.

**VC-6 — a by-name vector call into a declaration annotated with a type of no integer width is refused (no new decision: the v6.5.61 rule, and parity with 6.7.14's D38 method arm, kept by 6.7.15's D67)**
- Stops compiling, every target: `var x: f64 = f(..);`, where `f` is declared to return a vector. So do `: f32`,
  `: bool`, `: cstring`, an enum, `: Vec`, `: Result`, `: Option`, and an explicit instance `g<i64>(..)` into them.
  - `x` was silently a two-slot vector local under a wrong label: `load64(&x + 8)` read the second lane.
  - The message is "vector return type does not match the declared type", as for `: i64` and the method spelling
    `var x: f64 = s.mv();`.
- Migrate: declare the vector type (`var v: f64v2 = f(..);`) and read the lane you want (`load64(&v)`), or drop the
  annotation.

**VC-7 — parentheses around a whole vector call are transparent at an untyped declaration and an integer destination; a method starting an integer initialiser is refused (D28 A, D29 A, the user 2026-10-18)**
- Behaves differently: an unannotated `var x = (f(..));` or `var x = (s.m(..));`, with `f` / `m` declared to return a
  vector, is now that vector's local, as the unwrapped call is. That covers any number of parentheses, an explicit
  instance, a field chain's method, a generic method, and `(callptr(&f, ..))` / `(fncallN(&f, ..))`. It held one word:
  lane 0's bits on x86_64 / aarch64 (0 or 1 in the filed rows), garbage on cx (154 / 155) and Windows (195), where 161
  is right.
- Stops compiling, every target:
  - `var x: i64 = (f(..));`, `var x: i64 = (s.m(..));`, `x = (f(..));` and `x = (s.m(..));` (D28);
  - `var x: i64 = s.m(..) + 1;` (D29), a method that STARTS an integer initialiser;
  - ⚠ also `var x: i64 = callptr(&f, ..) + 1;`, and any non-vector annotation (`: f64`, `: u8`, a struct, a pointer)
    in each of these shapes — beyond D28's / D29's text, which name the integer destination and the method;
  - a whole `var y: i64 = callptr(&f, ..);` / `x = callptr(&f, ..);` into a scalar (the VC-8 rule, landed in this
    bite).

  Each stored the result's first word (or the word plus 1). The message is "vector return type does not match the
  declared type" / ".. the assigned variable".
- Migrate: declare the vector type (`var v: f64v2 = (f(..));`) and read the lane wanted (`load64(&v)`), then do the
  arithmetic on that word.
- ⚠ Still compiling and storing a word plus the rest (filed, 6.7.16, awaiting a decision): `x = s.m(..) + 1;`,
  `x = callptr(&f, ..) + 1;` and a wrapped call that starts an initialiser or right-hand side (`var x: i64 = (f(..))
  + 1;`). An operator after a by-name vector call into a vector local (`var w = mk2(41, 7) + 1;`) is dropped on x86_64
  / aarch64 (filed, 6.7.16). Do not write either shape.

**VC-8 — a vector call assigned to a global that is no vector, and `fncallN(&f, ..)` / `callptr(&f, ..)` into a scalar local, are refused (no new decision: 6.7.14's D38 A for the same local; 6.7.14's D27 (a)'s one rule for variable and global destinations; 6.7.13's D29 A)**
- Stops compiling, every target:
  - `G = f(..);` in a fn or a closure, with `f` declared to return a vector and `G` a global that is no vector. The
    same holds for a method (a field chain's too), an explicit instance, `fncallN(&f, ..)` / `callptr(&f, ..)`, any
    wrap, and `G = f(..) + 1;`.
  - `x = fncallN(&f, ..);` / `x = callptr(&f, ..);` into a scalar local, and `var y: i64 = callptr(&f, ..);`.

  `G` held the result's first word: 0 on x86_64 / aarch64, lane 0 on cx / Windows (41 in the filed rows; 82 for row
  4's two). The message is "vector return type does not match the assigned variable" / ".. the declared type". A
  pointer global's also prints "assigning non-pointer to typed pointer" beside it.
- Migrate: receive the vector in a local of its type and store the lane wanted: `var v: f64v2 = f(..); G =
  load64(&v);`. A vector global keeps its own rule: set it through its address (`store64(&VG, ..)`, the `_ptr` forms).
- ⚠ At top level after the first statement, `G = f(..);` still stores a word (filed, 6.7.16): make the call in a fn.

**VC-9 — a call declared to return a vector into a top-level declaration is refused (D26 A, D27 A, the user 2026-10-18)**
- Stops compiling, every target, in the declaration zone and after the first statement:
  - An untyped top-level `var w = f(..);` or `var v = s.m(..);` (D26), with `f` / `m` declared to return a vector:
    "'f' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn". The
    same applies to an explicit instance, a field chain's method, `callptr(&f, ..)` / `fncallN(&f, ..)` and any wrap.
  - `var x: i64 = f(..);` (D27), and a call or method that starts the initialiser: "vector return type does not match
    the declared type".
  - ⚠ also every other non-vector annotation (`: f64`, `*i64`, a struct, `: bool`). D27's text names the integer
    annotation, and the lane applied the line's rule in a fn ("as the same line is inside a fn").

  Each global held the result's first word: 0 on x86_64 / aarch64, garbage on cx (154) and Windows (195), and 41 under
  `: i64`. In the declaration zone only a program's first such error prints (the zone replay's latch, filed 6.7.16):
  fix one, recompile, and the next shows.
- Migrate: make the call in a fn. Store its lanes through a vector global's address (`var g: f64v2 = 0;` at top level,
  then `store64(&g, ..)` or a `_ptr` form in the fn), or read them into scalar globals there.
- Unchanged: an annotated vector global (`var w: f64v2 = f(..);`) keeps "vector global 'w' takes no initializer but 0".
- ⚠ The top-level `var w = f(..) + 1;` still compiles to a word plus 1 (filed, 6.7.16).

**VC-13 — `*(&p)` of a typed pointer is `p`, its type kept (D21 A, the user 2026-10-18)**
- Behaves differently, every target. `p` may be a typed-pointer local, parameter, closure capture or global, inside any
  parentheses:
  - Through a narrow typed pointer (`*u8`, `*i16`, `*i32`, `*f32` ..), `**(&p)` reads and writes the element's width,
    as `*p` does. It read and wrote 8 bytes, so a store clobbered the bytes after the element.
  - `*(&p) + n` / `*(&p) - n` steps by p's element, as `p + n` does. It stepped bytes. ⚠ D21's option text names the
    reads; the step follows from "type kept".
  - An untyped `var v = **(&p);` with `p: *f64v2` (any `*V`) is the vector's local. It was one word and a stack word
    (garbage per target).
  - `**(&ps)` of a `ps: *S` is the struct: an operator on it dispatches `S_op`, as `*ps` does.
- Migrate: code that wanted the old 8-byte read writes `load64(*(&p))` (or `load64(p)`). Code that wanted the old byte
  step takes the slot's untyped word, `load64(&p) + n`.
- Starts compiling (no change needed): `lanes(**(&p))`, `return **(&p);`, `var v: f64v2 = **(&p);` and `(*(&ps)).y`.
- Unchanged: `&p` itself, `*(&p + 0)` (the word at that address) and a handle's `*(&h)`.
- ⚠ Two exceptions remain (filed, 6.7.16). The compound `*(&pi) += 1` still steps one byte; write `pi += 1` or
  `*(&pi) = *(&pi) + 1`. `*(&GQ)` of a packed `i32` global reads 8 bytes; read `GQ`.

**VC-14 — a wrapped or computed typed-pointer argument binds a generic's `T` as the pointer does (D22 A, D23 A, the user 2026-10-18)**
- Behaves differently: a generic called with no `<..>` and a wrapped or computed typed-pointer argument now runs the
  instance of what the pointer points at, not the i64 base.
  - The arguments are `g((pps))`, `g((&ps))`, `g(pps + n)`, `g(n + ps)` and `g(ps - n)`, through a `pp: **T` or
    `p: *T` parameter; a field, global or `: **S` call plus n too; a `*i32`'s `pa + 1` binds i32.
  - `sizeof(T)`, `p + 1`'s step, `*p`'s width, a `var x: T` local and a `: T` result change with it: a `: T` result
    becomes the struct.
  - Through 6.7.14 `tg((pps))` / `tg(pps + 0)` ran the i64 base and `take(**pp)` faulted (139, cx 254, Windows 5), and
    `g(ps + 1)` stepped 8 for a 24-byte S.
- Migrate: code that wanted the i64 base spells it, `g<i64>(ps + 1)`.
- Unchanged: `&s + n` (a byte pointer), a distance `ps - qs` and a bitwise result (`ps + 1 & 3`) bind nothing. Through
  `x: T` no pointer binds (6.7.14's D8 (a)).
- Starts compiling (no change needed): a generic forwarding such a call's T into a method, `var r = gd(pp + 0); return
  r.pick(t);`. ⚠ The same forward of a `**T` / `***T` argument (`gd2((ppp))`, `gd2(ppp + 0)`, `gd2(ppp)`) is still
  refused naming the stub method (filed, 6.7.16): spell the type argument, `gd2<P>(..)`.

**VC-15 — a generic's `ppp: ***T` (and any deeper `*..*T`) binds `T` from a `***S` argument (D24 A, the user 2026-10-18)**
- Behaves differently: a generic whose ONLY carrier of T is a parameter declared `***T` (or deeper), called with no
  `<..>`, now runs the struct's instance (or i8 / i16 / i32 / f64's) where it ran the i64 base.
  - The argument may be a `***S` local, parameter, capture, global, field or call, or `&pps` of a `**S`, wrapped or
    plus n.
  - `**ppp + 1` steps sizeof(S), and `take(***ppp)` gets the struct. Through 6.7.14 the step was 8 and it faulted.
  - A `****T` binds from a `****S` the same way.
- Migrate: code that relied on the i64 base spells it, `s3<i64>(ppps)`.
- Unchanged: a direct or struct carrier wins. A `**S` or `&ps` into `***T` binds nothing.

**No block** — a miscompile fixed into the right answer, a compile time, or a message on code that never compiled:
- **VC-1:** an `#inline` call (or a small fn the compiler replays) whose argument holds a u128 operation, or a `*S`
  dereference before a struct operator, as an operand of a larger expression, computes the right value. It read a
  clobbered slot: `id(a) + id(a + 1) + 2` gave 84 for 83 on x86_64, aarch64 and Windows, and 43 or 84 in a closure.
  Frames of such fns can grow by a slot or two.
- **VC-2:** a refused argument in a call to an `#inline` fn prints one refusal on x86_64, aarch64 and cx, as on Windows.
  The next statement is skipped, as after a non-inline call.
- **VC-3:** a unit with thousands of distinct `**T` pointees compiles in linear time (15360 pins: 4.5 s → 1.3 s); the
  output is byte-identical.
- **VC-5:** a wrapped call of another vector into a vector local (`var v: f64v2 = (mk4(41));`, `w = (s.mv());`) is
  refused "vector return type does not match ..", one column right of the old "got `(...)`" refusal, at the call inside
  the parentheses.
- **VC-10:** a struct refusal at a destination names a method result `'Pt.dup'` / `` `Pt.t1` `` (a top-level generic
  instance `'mkg<i32>'`), where it printed `'Pt_dup'` / `mkg$i32`. A script grepping those diagnostics re-matches. A
  free fn named `Pt_dup` keeps its name.
- **VC-11:** the false "assigning non-pointer to typed pointer" beside a refused `w = s.dup();` is gone.
- **VC-12:** a refused dereference argument is quoted as written, `'*gp(pb)'`, `'*&b'`, `'**ppb'`, `'*gq(pq)'`, where
  it was `'*pb'`, `'*b'`, `'*ppb'`, `'pq'`.
- **VC-1r / VC-6r:** a test header and the guide.

#### Receives — known-callee results, struct results into `*T` and untyped variables, top-level untyped method / operator results, tuple-parameter literals (the receives lane)

The 6.7.15 decisions are the user's at the 6.7.15 open (2026-10-18): D30 – D36 and D59. Ids from other releases are
written with their release: **6.7.14's** (2026-10-16) D27, D29, D30 (a top-level untyped 9 – 16 B free call refused —
not 6.7.15's D30), D42, D44, D53; **6.7.13's** D14; **6.7.11's** D31 (a callee held in a variable is a word — not
6.7.15's D31). Each block names its CHANGELOG [6.7.15] bite.

**RC-1 — a body ending in an infinite loop left only through `ret2(..);` counts as two values (within 6.7.14's D42, the user 2026-10-16; D62, the user 2026-10-18, kept D42's reach)**
- Stops compiling: three names or a 3-tuple from an undeclared fn whose body ends in an infinite loop — `loop { }`,
  `while (1) { }`, `while (true) { }`, `do { } while (1);` / `(true)` — that no `break` leaves and whose only exits are
  `ret2(..);` statements (a `ret2(..);` in a nested `while` / `for` or a switch's case block included): "multi-value
  destructure binds 3 names, but 'g2' returns 2 values" / "cannot capture 'g2' into tuple (i64, i64, i64) - it returns
  2 values". The third value read a stale register (88 in the filed repro). Bind two names, or declare the fn
  `: (T1, T2, T3)` and return three values.
- Unchanged: two names, a loop a `break` leaves, a `ret2` inside an expression. A `ret2(..);` written directly after a
  `case N:` label is not counted yet (filed, 6.7.16).

**RC-3 — an argument made only of literals and operators into a tuple parameter is refused by name (D36 (a), the user 2026-10-18)**
- Stops compiling: passing a negated literal, `true` / `false` or a constant expression to a tuple parameter —
  `take(-5)`, `take((-5))`, `take(5 + 0)`, `take(~0)`, `take((1 << 3))`, `take((1) + 2)`, `take('a' - 1)`, a method's
  `x.take(!true)`, any argument position: "cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it
  takes a tuple" ("cannot pass a bool …" when every literal is `true` / `false`). It crashed at run time (the callee
  read through the value as the tuple's address: 139 on x86_64 / aarch64, a cx guest error, exit 5 on Windows). Pass a
  tuple: `take((a, b))`, a tuple variable, or its address `&t`.
- Unchanged: a name — a const too — `&t` and a call are still passed as the address, unchecked (`take(C)` with a const
  compiles, as decided); a float literal (`take(1.5)`) still compiles and crashes (filed, 6.7.16).

**RC-4 — a top-level `var s = (mks());` with a `: Str` call is routed as `var s = mks();` is (no decision needed: a whole wrap is transparent, guide § Parentheses)**
- Behaves differently: an untyped top-level global initialised by a wrapped `: Str` call (`var s = (f());`,
  `((f()))`, the declaration zone or after the first statement) passed to an overloaded base — `println(s)`,
  `strlen(s)`, any base with a `_str` sibling — now reaches the `_str` sibling, as the unwrapped spelling always did;
  `println(s)` prints the string where it printed the `Str` header's address bytes through the cstring base.
- Unchanged: the global is still a word — `s.len()` is refused at top level, wrapped or not. A global from a `: Str`
  METHOD (`var s = o.mks();`) still takes the cstring base (filed, 6.7.16).

**RC-10 — a known `&f` callee's narrow `*T` result is read and written at its element (D31 (a), the user 2026-10-18)**
- Changes what it computes: with `f` declared `: *u8` .. `: *i32` (or `: *f32`), `*fncall0(&f)` and `*callptr(&f)`
  read the element, as `*f()` does — one byte for a `*u8`, four for a `*i32`, sign-extended for a `*i8` — where they
  read the whole word; `*(fncall0(&f) + n)` reads the element at that step. A store `*fncall0(&f) = v` /
  `*callptr(&f) = v` writes the element where it wrote 8 bytes (⚠ D31's text names the read; the store follows the
  same width rule). To keep a word, bind the call untyped and dereference that (`var w = fncall0(&f); *w`).
- Starts compiling: `fncall0(&f)[i]` / `callptr(&f)[i]` subscripts and stores at the element; with a `*S` callee the
  subscript refusal names the struct.
- Unchanged: a callee held in a variable (`fncall0(fp)`) is still a word: `*fncall0(fp)` reads 8 bytes and
  `fncall0(fp)[1]` is refused.

**RC-11 — a struct result over 8 B assigned to a `*T` is refused by name (D32 (a), the user 2026-10-18)**
- Stops compiling: `p = f();` — a free call, a method, an overloaded operator, `fncallN(&f, ..)` / `callptr(&f, ..)`,
  in a for step, in parentheses, in a fn or at top level — returning a struct over 8 bytes, into a local, parameter or
  global declared `*T` of any other type (`*i64`, `*u8`, `**Q`): "cannot assign 'p: *i64' from 'f', which returns the
  struct 'Q' - declare 'p: Q' and take `&p`". It stored the struct's first word as the pointer (the first dereference
  faulted), silently or under "assigning non-pointer to typed pointer". Declare `var s: Q = f();` and take `&s`, or bind
  a field.
- Unchanged: a `*Q` destination of the result's own struct copies the struct through the pointer; a struct of 8 bytes
  or less keeps its word. Inside a generic called with `T = i64` or `T = u8`, `p = mkp();` into `p: *T` still keeps the
  first word (filed, 6.7.16).

**RC-12 — a struct result over 8 B assigned to an untyped variable is refused by name (D33 (a), the user 2026-10-18)**
- Stops compiling: `x = f();` with `f` returning a struct over 8 bytes (a free call, a method, an operator, a known
  `&f`, a for step, wrapped, in a fn or at top level) and `x` UNTYPED — `var x = 0;`, an untyped parameter or global, a
  destructure's name, a `for (var x = 0; ..)` or `for x in ..` name (one shadowing an outer `x: i64` too, which 6.7.14
  pinned as keeping the word), a closure's parameter: "cannot assign 'x' from 'f', which returns the struct 'Q' -
  declare 'x: Q' or bind a field". It took the struct's first field. Declare the variable from the struct
  (`var x = f();`), or bind the field you meant (`x = f().a;`).
- Unchanged: a struct of 8 bytes or less and a `Str` keep their word; `var x = f(); x = f();` copies.

**RC-13 — a top-level untyped whole method, operator or known `&f` result binds its struct; 9 – 16 B is refused (D34 (a) and D35 (a), the user 2026-10-18)**
- Stops compiling: an untyped top-level global initialised from a whole method, operator or known `&f` result of a
  9 – 16 byte struct — `var G = x.m();`, `var G = a + b;`, `var G = fncall0(&f);`, `var G = callptr(&f);`, wrapped or
  not, the declaration zone or after the first statement: "'P2.mk' returns a struct by value, and a struct result needs
  storage in a fn's frame — call it inside a fn" (an operator names 'P2_add', a known callee its fn). It held the
  struct's first field, silently. Move it into a fn, or bind the field you meant (`var G = x.m().a;`).
- Behaves differently: one of 8 bytes or less is now that struct: `G.a` compiles, and `G + n` / `G - n` dispatch the
  struct's operator fn (`P1_add`, …) — refused when there is none ("undefined function 'P1_add'", then "refusing to emit
  binary") — where they did integer arithmetic on the word. A bare `G` as a value is still its word. Annotate
  `var G: i64 = x.m();` to keep an integer.
- Unchanged: an if-expression's struct result, a `Str` and a name keep the word at top level; a generic method's
  generic struct result in the declaration zone stays untyped (filed, 6.7.16).

**RC-14 — a declaration-zone untyped generic call returning a generic struct's instance binds it (6.7.14's D29 (a), the user 2026-10-16; no new decision)**
- Stops compiling / behaves differently: in the declaration zone, `var x = g(..);` with `g` a generic returning
  `: G<T>` (`fn mkg1<T>(v: T): G1<T>`) is now that instance, as after the first statement: `x + 1` dispatches G's
  operator fn, and is refused when there is none ("undefined function 'G1_add'", then "refusing to emit binary") —
  through 6.7.14 the zone line added to the word (34). Bind the field (`x.v + 1`).
- Unchanged: the 16-byte instance was already refused (now one error, not two); an argument that binds no type
  argument (`mkg1(30 + 3)`, a struct carrier, a bounded G) leaves the zone global untyped (filed, 6.7.16).

**No block — a diagnostic changes, refused source now compiles, or the defect was in-flight (nothing that compiled does anything else):**
- **RC-2:** `h.p = (two(3));` into a tuple field is one error (R17), not two.
- **RC-5 (with RC-5r):** a use of a variable or parameter whose annotation was refused (`var x: Foo = 5; x.a`) adds no
  "no struct type in scope" error; a top-level `var P: *Foo` global's uses still add one (filed, 6.7.16).
- **RC-6 (D59, the user 2026-10-18):** a string literal into any `*T` (`*i64`, `*f64`, `*i32`, `*B1`) no longer warns
  "assigning non-pointer to typed pointer"; binaries unchanged.
- **RC-7:** `"abc" + 1`, `"abc" - n`, `("xyz")`, `("abc") + 1` into a `*T` no longer warn; `"abc" + x * 2` still does;
  binaries unchanged.
- **RC-8:** the mixed-return warning ("`f` returns a `: stack` pair on another path but a SINGLE value here") now
  judges `impl` methods and inherited trait defaults; nothing compiles differently, but a build log that treats
  warnings as failures sees it. The defect it names reads the single value as the tag: return a variant on that path.
- **RC-9 (D30, the user 2026-10-18):** `var b: bool = fncall0(&isb);` (and `callptr`, an assignment, a wrap, a
  `return` from a bool fn, a bool parameter) with `isb(): bool` compiles; it was refused "not a bool".
- **RC-13r, RC-14r:** a compile-time defect of RC-13 inside the release (quadratic in the zone's untyped struct-call
  globals) and a gate; no released compiler had either.

#### The stdlib and fold defects found by the lanes — aarch64 / Windows `sys_dup2`, lib/process.cyr capture redirects, patra 1.16.5's read path (the libfix lanes, waves 2 and 3)

Each block names its CHANGELOG [6.7.15] bite (the libfix lanes, LF-*). Two decisions are the user's, 2026-10-18, at
the wave-2 integration: the PE `sys_dup2` (LF-5) and the oversized patra ref (LF-7). Both were asked after the open's
D1 – D70, so neither has a D number. LF-1 – LF-3 needed no decision: each is fixed to what POSIX or the read's
documented answer says. The patra blocks take effect when the integration refolds `lib/patra.cyr` from patra 1.16.5
(§ Folds — patra 1.16.5).

**LF-1 — aarch64 Linux: `sys_dup2(fd, fd)` answers `fd` or -9 (no decision: POSIX dup2, which x86_64 Linux and macOS already answer)**
- aarch64 Linux only, and a cx guest on an aarch64 cxvm (cxvm serves a guest's dup2 through the host's `sys_dup2`).
  `sys_dup2(fd, fd)` returns `fd` when it is open and -9 (EBADF) when it is not. It returned -22 (EINVAL): the peer
  issued `dup3(fd, fd, 0)`, which refuses equal fds.
- Distinct fds are unchanged. A raw `syscall(33, fd, fd)` is unchanged too: it is still renumbered to dup3 and still
  answers -22 on aarch64.
- **Migrate:**
  - Code that branched on the self-dup's failure (`if (sys_dup2(a, b) < 0)` with `a == b`) now takes the success path on
    aarch64, as it always did on x86_64 and macOS. Drop any aarch64-only workaround that treated -22 as "already in
    place".
  - A raw `syscall(33, …)` caller that leans on the self-dup still branches on `old == new` (the guide's aarch64 rule 4),
    or calls `sys_dup2`.

**LF-2 — patra: a chain that loops back, or a ref shorter than its chain, reads `PATRA_ERR_PAGE` (no decision: the read's documented answer on a malformed chain)**
- Every target, at the refold. A BYTES / TEXT chain whose pages run past the row's length — a `BY_NEXT` looping back
  to an earlier page, or a ref shorter than its chain — is refused. `patra_result_read_bytes` / `_read_text` return
  `PATRA_ERR_PAGE` (7) with nothing written (LF-3).
- They returned `PATRA_OK` with the wrong bytes (a loop: an earlier page's bytes where the tail's belong) or the bytes
  cut short.
- Databases patra wrote are unaffected: the writer's pages sum to the ref's length exactly.
- **Migrate:** check the read's return. A corrupt cell is an error now, never a value.

**LF-3 — patra: a malformed BYTES / TEXT chain keeps the row's length and reads `PATRA_ERR_PAGE` (no decision: both reads document `PATRA_ERR_PAGE` on a malformed chain)**
- Every target, at the refold. A malformed chain is a bad page marker, an oversized or negative page length, a link out
  of the file, or a loop (LF-2). For such a cell:
  - `patra_result_get_bytes_len` / `_get_text_len` return the row's length (they returned 0);
  - `patra_result_read_bytes` / `_read_text` return `PATRA_ERR_PAGE` (7) with nothing written (they returned
    `PATRA_OK`, an empty value).
- Unchanged: the query still answers, its other cells read as before, and a refused buffer still fails the query with
  `PATRA_ERR_IO`. Databases patra wrote are unaffected.
- **Migrate:** code that sizes a buffer from the length and ignores the read's return now gets an untouched buffer of
  that size where it got nothing. Check the read's return, and treat `PATRA_ERR_PAGE` as "this cell has no value".

**LF-5 — Windows: `sys_dup2` answers -38 for every call (the user, 2026-10-18, at the wave-2 integration)**
- Windows (PE) only. `sys_dup2(oldfd, newfd)` returns -ENOSYS (-38) for every call, as `sys_fcntl` does. It returned
  `newfd` whatever `oldfd` was, and redirected nothing:
  - a closed fd's self-dup `sys_dup2(99, 99)` answered 99;
  - `sys_dup2(1, 50)` answered 50 with nothing behind fd 50;
  - the open fd's self-dup `sys_dup2(1, 1)` answered 1, and is -38 now (POSIX answers 1).
- No redirect ever happened on Windows, so nothing that worked stops working.
- **Migrate:**
  - Code that read the return as the new fd (`if (sys_dup2(a, b) == b)`, or the result used as an fd) now takes its
    failure path. Test `< 0`, never the requested fd coming back.
  - On Windows a child's std handles are set at spawn (CreateProcessW's handles), not by an in-process dup2. Fence the
    redirect behind `#ifndef CYRIUS_TARGET_WIN`, or spawn with the handles.

**LF-7 — patra: a ref longer than the file answers length -1 and `PATRA_ERR_PAGE` (the user, 2026-10-18, at the wave-2 integration); ⚠ a negative stored length reads `PATRA_ERR_PAGE` too, beyond the decision's text**
- Every target, at the refold. Databases written with non-negative lengths are unaffected.
- A row ref that names more bytes than the file can hold (past `HDR_PGCOUNT * BY_DATA_MAX`):
  - `patra_result_get_bytes_len` / `_get_text_len` return **-1** (they returned 0);
  - `patra_result_read_bytes` / `_read_text` return `PATRA_ERR_PAGE` (7) with nothing written (they returned
    `PATRA_OK`, an empty value).
- ⚠ A cell with a NEGATIVE stored length reads `PATRA_ERR_PAGE` (it read `PATRA_OK`, an empty value), and its getter
  still answers the stored value (-5 stays -5). Two routes reach it:
  - `patra_insert_row` (and `_or_ignore`) with a negative BYTES / TEXT length, which they accept with `PATRA_OK` and
    store as is;
  - a crafted or corrupted file.

  The reads' new test reads every negative length alike, and the decision named only the oversized ref. Whether the
  insert should refuse a negative length and whether the getters should answer -1 for one is filed for the user's call
  (6.7.16).
- -1 is also the getters' answer for a column of another type and for a cell outside the result set. The read tells
  them apart: `PATRA_ERR_TYPE` / `PATRA_ERR_PARAM` there, `PATRA_ERR_PAGE` here.
- **Migrate:**
  - Treat a negative length from the getters as "no value": `fl_alloc(-1)` is not a buffer. Size the buffer only from a
    length >= 0, and check the read's return.
  - Never insert a negative BYTES / TEXT length. Pass the payload's real length (0 for an empty value): until the insert
    refuses one (filed), the cell reads back as `PATRA_ERR_PAGE`.

No block for LF-4 (patra's fuzz harness only), LF-1r (comments) or LF-6. LF-6 changes nothing that worked: with every
std fd open (the normal case) the child setup is identical. A caller started with fd 0, 1 or 2 closed now gets the
child's real output, where lib/process.cyr's and lib/regression.cyr's capture verbs returned an empty capture, and the
exec'd child starts with stdout and stderr open. There is nothing to change in a caller.

#### (libfix4)

Each block names its CHANGELOG [6.7.15] bite. These are the libfix4 lane's LF-8 and LF-9, which continue the libfix
section's numbering. No decision covers the lane:
- LF-8 fixes a security vulnerability, CYRIUS-2026-0036, in the issue's fix direction and after CYRIUS-2026-0034's
  precedent;
- LF-9 fixes a `lib/` defect.

**LF-8 — CYRIUS-2026-0036: lib/regression.cyr's capture verbs create their capture file exclusively, 0600, under `$TMPDIR` when it is absolute (no decision: a security fix, in the issue's fix direction and after CYRIUS-2026-0034's precedent)**
- This block covers Linux and macOS, and the verbs `regression_exec_capture[_status]`,
  `regression_exec_with_arg_capture[_status]` and `regression_exec_with_arg_capture_both[_status]`. The check driver
  runs every `.tcyr` through the first of these.
- **Where the file is.** When TMPDIR is an absolute path, the capture file is `$TMPDIR/audit_xc_<pid>` or
  `$TMPDIR/audit_xa_<pid>`, or one of `….1` … `.63`; trailing slashes are dropped. It was always `/tmp/audit_x?_<pid>`.
  A relative or empty TMPDIR is ignored, and with TMPDIR unset the file is in `/tmp`.
- **How it is created.** The file is created 0600. A name that already exists is skipped, never opened: a planted
  link, a planted file, or a file a killed earlier run left behind.
- **When no file can be created.** This happens when TMPDIR names a directory that does not exist or cannot be written,
  or when 64 names are taken. The verb prints one line on stderr and returns 0 bytes with status -1, without running the
  child. The line is one of:
  - `regression: cannot create the capture file <name> (errno N); nothing was run`;
  - `regression: cannot create the capture file <name> — it and every name before it were taken; nothing was run`.

  Before, only an unusable `/tmp` failed, with the same 0 / -1 and no message.
- **Removed:** the private helper `_regression_tmp_path`. It was never in the API surface.
- Unchanged:
  - with every name free, the capture, the status and the child are the same;
  - Windows answers 0 / -1 as before (it has no fork), and now creates nothing;
  - the verbs that write a caller's `out_path` are not part of this change.
- **Migrate:**
  - **A runner that sets TMPDIR to a directory it has not created** now sees the refusal line and an empty capture.
    Its tests read as not run, where the capture used to work through `/tmp`. Create the directory first, point TMPDIR
    at a writable one, or unset it.
  - **Code that looks for leftover capture files in `/tmp`** (to clean up after a killed run, say) must also look
    under `$TMPDIR`, and include the `.N` suffixes. A file left by a killed capture is never reused. Nothing reaps it
    yet (filed, 6.7.16).
  - **A caller of `_regression_tmp_path`** builds its own name and creates it with `file_create_exclusive(path, 0x180)`
    from lib/io.cyr, which returns the write fd or -17. Never open a predictable name in a shared directory with
    `O_CREAT | O_TRUNC`.

No block for LF-9, which changes nothing that worked. With every std fd open, the normal case, the child setup is
identical. A caller started with fd 0 closed now gets the child's output from `regression_exec_in_dir3[_env]`,
`regression_pipe_to_bin_capture` and `regression_ssh_remote_exec_capture`, where it got an empty file, and the exec'd
child starts with fds 0, 1 and 2 open. That is the verbs' documented "capture stdout to file", and a caller has
nothing to change. No block for LF-8r either: it touches only a test.

### 6.7.14

Break 2, repair 4 — generics, the frontend, infra (the heavier release). Each block names its CHANGELOG [6.7.14] bite;
the decisions are the user's (2026-10-16, D1–D61). The changes that went beyond a decision's text are filed for
confirmation in 6.7.15 (`docs/development/issues/archived/2026-10-17-6714-behaviour-changes-beyond-the-decisions-text.md`).
Decision ids are 6.7.14's unless a block names another release ("6.7.13's D30").


#### Infra — the IR arena, IR=3, DCE and compaction, cybs, asm, timing gates (the infra lane)

One decision is the user's at the 6.7.14 open (2026-10-16): D16, refuse an asm block naming an instruction or operand the
assembler does not have. "6.7.13's D45" (keep the aarch64 W^X layout) is the 6.7.13 open's. Everything else is fixed to
what the source says. Each block names its CHANGELOG [6.7.14] bite. A default build (no `CYRIUS_IR`, no `CYRIUS_DCE`)
of a program without an `asm` block is byte-identical to 6.7.13's.

**IN-1 — the IR tables are one `alloc()`'d arena that grows (no decision; the release's heap-layout change)**
- Starts working: a `CYRIUS_IR=1` / `CYRIUS_IR=3` build of a program past 1,048,576 IR nodes or 131,072 basic blocks. It
  stopped with `error: IR node buffer full` / `error: IR block table full` (rc 1) while the default build compiled it; it
  builds now, and the arena grows on demand.
- The limits move: the IR is capped only by runaway ceilings, 64M nodes and 16M blocks, named when hit
  (`error: IR node table exceeds 64M nodes`, `error: IR block table exceeds 16M blocks`); an arena the system refuses is
  `error: cannot allocate the IR arena (CYRIUS_IR)`. The two "full" messages no longer exist — a script that grepped them
  should look for the new ones. Memory under `CYRIUS_IR` starts smaller (262,144 nodes / 32,768 blocks) and grows 2x.
- The heap-layout change is the compiler's own: the six fixed IR regions of cycc's arena are retired (26 MB + 4 KB of
  free gaps; brk-final unchanged), proven by the two-step bootstrap (the 6.7.13 cycc builds gen1 from the new src, gen1
  == gen2 == gen3). Nothing a program sees moves, and a default build never takes the arena.

**IN-4 — `CYRIUS_DCE=1` compacts past 4,096 dead-code runs (no decision; consumer-filed)**
- Changes what a build produces: an x86_64 ELF `CYRIUS_DCE=1` build with more than 4,096 dead-code runs (a program that
  links far more than it uses) is now compacted — the binary shrinks to what the 4,096-or-fewer case gives, where the dead
  code used to stay NOP-filled. A `CYRIUS_IR=3` build past 4,096 IR NOP runs or switch tables compacts too.
- The notes change: the unreachable-fns note no longer says `compaction declined on x86_64 ELF: more than 4096 dead-code
  runs, the repair registry cap`, nor the switch-table and IR=3 seam variants. A decline now reads `… could not grow
  (alloc failed)` and appears only when memory runs out.
- **Migrate:** a gate or script that pinned the large binary size, or grepped the "more than 4096" note, refreshes its
  number / text. Nothing that runs changes.

**IN-6 (+ IN-6r) — a redefined fn's losing body keeps nothing alive under `CYRIUS_DCE=1` (no decision: 6.6.20's last-definition-wins rule; consumer-filed)**
- Changes what a build produces: in a `CYRIUS_DCE=1` build of a program that defines a fn twice, a fn that only the losing
  (earlier) definition calls is now unreachable — listed by `CYRIUS_DCE_VERBOSE=1`, counted in the unreachable-fns note
  and removed — on x86 (W^X and `CYRIUS_WX=0`), aarch64, and with `CYRIUS_IR=3`. The binary is smaller; in the kept
  losing body (never executed) a call to the removed fn is the `ud2` sentinel.
- Unchanged: every call still binds the last definition; a losing body that calls an UNDEFINED fn is still refused under
  `CYRIUS_DCE=1`; a program with no redefinition is byte-identical.
- **Migrate:** re-measure a `CYRIUS_DCE=1` binary that redefines stdlib fns (a refusal shim over a loader, say) and refresh
  any pinned dead-fn count or size. Nothing that runs changes.

**IN-13 — `asm { in al, dx; }` compiles; `in` / `out` encode the accumulator's width; a bad operand is refused (no decision for the width; D16, the user 2026-10-16, for the refusal)**
- Changes what it computes: `asm { out dx, ax; }` now assembles `out dx, ax` (66 EF) and `asm { out dx, eax; }` `out dx,
  eax` (EF): a 16- / 32-bit port write. Through 6.7.13 both assembled as `out dx, al` (EE), a one-byte write. Code that
  wrote `out dx, eax` but relied on the byte write must say `out dx, al`.
- Stops compiling (D16): `out` with operands other than `dx` and then `al` / `ax` / `eax` — `out dx, ebx`, the reversed
  `out al, dx` — which assembled as `out dx, al`: "out takes dx and then al, ax or eax, not 'ebx'". `in` with an operand
  other than `al` / `ax` / `eax` and then `dx` (`in bl, dx`, the immediate port `in al, 0x60`) is refused by name — it was
  refused before too (`unexpected in`). For an immediate port write raw bytes: `asm { 0xE4; 0x60; }` is `in al, 0x60`.
- Starts working: `asm { in al, dx; }`, `in ax, dx`, `in eax, dx` (EC / 66 ED / ED) — the guide's own spelling, refused
  through 6.7.13 because `in` lexes as the for-in keyword. The raw `asm { 0xEC; }` workaround can go.
- aarch64 and cx refuse `in` by name (`unknown aarch64 asm mnemonic 'in'`, `inline asm not supported in cyrius-x: 'in'`);
  they refused it before as `unexpected in`.

**IN-14 — an asm mnemonic is matched on its whole name; an unknown one is refused by name (D16, the user 2026-10-16)**
- Stops compiling: an asm block whose mnemonic the assembler does not have, which assembled as the mnemonic its name
  starts with — on x86 `clix` (cli), `stix` (sti), `nopx` (nop), `mfencex` (mfence), `inb al, dx` (in al, dx), `outb dx,
  al` (out dx, al), `param_loadx(rax, 0)`; on aarch64 `nopx`, `dmbx`, `retx`, `eretx`, `param_loadx(x0, 0)`. Now
  `unknown x86 asm mnemonic 'clix'` / `unknown aarch64 asm mnemonic 'nopx'`, with the column and the line.
- **Migrate:** write the real mnemonic (`inb` / `outb` are `in` / `out` with an `al` operand), or the raw bytes. Every
  spelling in the guide's Inline Assembly list, in lib/ and in the corpus assembles to the same bytes as before.
- cx: an asm mnemonic is still refused (cx has no inline asm); the error now names it and the build no longer ends in
  `parser recovery aborted`.

**IN-18 — the x86 dead-code call graph counts a call only where an instruction starts (no decision)**
- Changes what a build reports and produces (x86 ELF, PE, x86 Mach-O): the `note: N unreachable fns` count can rise, and a
  `CYRIUS_DCE=1` binary can shrink — a fn kept alive only by an `E8` byte inside an immediate or a displacement that
  happened to point at it is dead now, and removed. The dead set no longer moves when an unrelated global is added. Code
  the length decoder cannot walk exactly (a fn holding a raw `asm { 0x.. }` byte, the top level once it holds one, a fn
  holding a switch's jump table, instructions the decoder does not know) keeps the old byte scan, so nothing called is
  ever counted dead; the whole corpus runs the same under `CYRIUS_DCE=1`.
- **Migrate:** a gate or script that pins a dead-fn count or a `CYRIUS_DCE=1` binary size may need its number refreshed.

No block for the lane's other bites: IN-2 (`CYRIUS_IR=3` field reads computed wrong — an address, a stale register, a
fault — and compute what the default build computes now); IN-3 (only bytes that never run, past the compacted code, and
the IR=3 `wp-compact:` note's run count on stderr); IN-5 (a `CYRIUS_DCE=1` program using a forwarding generic crashed or
hung and runs now); IN-7 (a `#naked` redefinition past 49,152 jump sources died SIGILL under `CYRIUS_DCE=1`); IN-8
(`CYRIUS_SYMS` under `CYRIUS_DCE=1` now lists the compacted image's addresses and leaves out the removed fns — resolve a
crash address against the map of the binary that crashed; without compaction the map is unchanged); IN-9 (the guide);
IN-10 – IN-12 (cybs, which builds only cyrius's own `src/` and `bootstrap/asm.cyr`: a crash at end of input, an unnamed
undefined name — its class message now lists `x[i]` — and inputs past its 2 MB / 8-deep / 15 MB / 16 MB preprocessor
caps refused by name); IN-15 (no behaviour change — an aarch64 W^X executable is at least ~64 KB and grows in 64 KB
steps, kept by 6.7.13's D45; to compare aarch64 code growth read the code `PT_LOAD`'s `FileSiz`, `readelf -l -W <bin>`,
not the file size); IN-16 / IN-17 (gates); IN-6r2 / IN-4r (a fixture line, a comment).

#### Language — generics (the generics lane)

The decisions are the user's at the 6.7.14 open (2026-10-16, D1 – D8). "6.7.11's Dn" is the 6.7.11 open's id
(2026-10-13). Each block names its CHANGELOG [6.7.14] bite. Every change below is in the frontend: the same on x86_64,
aarch64, cx, PE and Mach-O.

**GN-1 — a two-parameter instance name brackets a type argument that is itself an instance (D1 (a), the user 2026-10-16)**
- Changes what it computes: a program that calls one two-parameter generic with a nested-instance argument in one slot
  and the bare generic struct in the other — `g2<P<R>, i32>(..)` beside `g2<P, R<i32>>(..)` — now runs a distinct
  instance for each. Through 6.7.13 both were `g2$P$R$i32`, and the second call silently ran the first's body (the filed
  program printed `1604 1604`; it prints `1604 812`). The struct form likewise: `Two<P, R<i32>>` gets its own layout
  where it took `Two<P<R>, i32>`'s. If a result you relied on came from the wrong instance, it changes to the right one;
  nothing to rewrite.
- Changes what tools print: those instances only are named `g2$<P$R>$i32` / `g2$P$<R$i32>` in diagnostics, the coverage
  dump and `cyrius syms`. Every other instance name is unchanged (`g2$i32$P`, `Two$i64$i32`, `Box$Pair$i32`,
  `gen$P$R`). A script matching the old nested spelling matches the bracketed one.

**GN-7 — a type argument that is no name is refused by what it is (no decision: a number, string or keyword is never a type name)**
- Stops compiling (an edge): a NUMBER as a type argument whose value happened to equal a type name's offset in the
  program's name pool compiled as that type — with `struct Pt { x; y; z; }` and `struct Box<T> { v: T; n; }`,
  `sizeof(Box<7>)` was 32 and `sizeof(Box<31>)` 16 on 6.7.13 (measured; which numbers hit depends on the program). It is
  now "a type argument is a type name, got number 7". Write the type you meant. Every other non-name argument
  (`Box<1 + 2>`, `Box<u128>`, `Box<"s">`) was refused before; only the message changes.

**GN-9 — an unknown `Name<..>`, a type parameter given arguments, and the built-in `slice<..>` are refused as type arguments (D2 (a), D3 (a), the user 2026-10-16)**
- Stops compiling: a type argument `Name<..>` whose Name is declared nowhere — `g<Nonexist<u8>>(0)`,
  `var c: Box<Nonexist<u8>>;`, nested `Box<Box<Nonexist<u8>>>` — "unknown type 'Nonexist' as a type argument (...)". It
  compiled and ran the i64 base (8-byte T, the base's layout). Write the type you meant.
- Stops compiling: a type parameter written with arguments — `h<T<u8>>(0)` inside a generic, a generic struct's field
  `Box<T<u8>>` — "a type parameter takes no type arguments: 'T'". It reached h's base (or took the base `Box`). Write `T`.
- Stops compiling: the built-in slice's word form as a type argument — `g<slice<u8>>(0)`, `var b: Box<slice<u8>>;` — "a
  slice cannot be a type argument (6.7.8: slices are fn-locals)", as `g<[u8]>` already was. It ran the base. A slice is a
  fn-local: pass `&s` and read `slice_ptr` / `slice_len`. A program's own `struct slice<T>` (`g<slice<i64>>`) still works.
- Unchanged: `Vec<..>`, a generic struct (`Box<Box<Pt>>`), a struct declared below the use (`g<Later<i32>>`). Still
  accepted (filed, 6.7.15): a NON-generic struct or a scalar given arguments (`var c: Pt<i64>;`, `g<Pt<i32>>`) — the
  arguments are ignored; drop them.

**GN-10 — every `Vec<..>` position reads its element; a generic Vec element's own list is read (D4 (a), D5 (a), the user 2026-10-16)**
- Stops compiling: a `Vec<..>` that names no element type in a position that skipped it — a struct field's nested
  `Vec<Vec<nosuch>>`, a trait member's parameter `v: Vec<nosuch>` (and a trait member's `: Vec<nosuch>` return), a
  multi-value return element `(Vec<nosuch>, i64)`, a generic struct's type argument `Box<Vec<nosuch>>`, an explicit
  call's `idv<Vec<1 + 2>>(c)` — "unknown type 'nosuch1' as the Vec element of 'items'", "expected a Vec element type, got
  number 1". Write the element type (`Vec<i64>` when it holds words).
- Stops compiling: a generic Vec element whose own arguments are no type arguments — `var w: Vec<Box<nosuch5>>`, a field
  `more: Vec<Box<(i64, i64)>>` — "unknown type 'nosuch5' as a type argument", "a tuple type cannot be a type argument", as
  `var b: Box<nosuch5>;` and `Box<(i64, i64)>` are.
- Stops compiling: a struct FIELD `Vec<Box<Later>>` whose `Later` is declared below the struct — "unknown type 'Later' as
  a type argument", as a field `b: Box<Later>` already was. Declare `Later` above the struct. A local's or a parameter's
  `Vec<Box<Later>>` still compiles.
- Unchanged: `Vec<i64>`, `Box<Vec<i64>>`, `idv<Vec<i64>>(x)`, `Vec<Box<i64>>`; the handle and its code. A non-generic
  element's own list (`Vec<Pt<..>>`) is still skipped (filed with the `Pt<i64>` issue, 6.7.15).

**GN-11 — a signature's generic struct reads its type arguments at the definition (D6 (a), the user 2026-10-16)**
- Stops compiling, at the definition, even when nothing calls the fn: a parameter or return that names a generic struct
  with a type argument that is no type — `fn gm(m: Mp<K, V>, b)` with K / V declared nowhere, `m: *Mp<K, V>`,
  `: Mp<K, V>`, `m: Box<Zork>` — "unknown type 'K' as a type argument (...)", once. `m: Box<Zork>` took a `Box<i64>`.
  Also refused there, as on a local: `m: Box<u8>`, `m: Box<Result>`, a tuple, `m: Box<Nonexist<u8>>`,
  `m: Box<Vec<nosuch>>`. Write the type, or make the name the fn's own type parameter (`fn gm<K, V>(m: Mp<K, V>, b)`).
- Unchanged: a generic's own type parameters, a struct declared below the fn (`m: Box<Later>`). Still unchecked (filed,
  6.7.15): a multi-value return element `(Box<Zork>, i64)`, a trait member's parameter, a `*fn(Box<Zork>)` parameter, a
  struct field `p: *Box<Zork>` until used.

**GN-17 — a `p: *T` parameter binds what its pointer argument points at; an `x: T` one binds no pointer (D8 (a), the user 2026-10-16)**
- Changes which fn runs: a call into a generic's `p: *T` parameter with `&G` / `&l` of a struct, a `*S` global, parameter
  (an untyped impl `self` included) or closure capture, a field declared `*S` (`w.p`, `wp.p`, `G.p`) or a `: *S` call now
  runs the `S` instance (`gsz$S`) where it ran the i64 base: `sizeof(T)` is `sizeof(S)` (24 where it was 8), a
  `var y: T` is an `S`, and a `: T` / `: *T` result is an `S` / a `*S`. A generic method's `w: *V` binds the same way.
  Only a `*S` LOCAL bound S before. To keep the base, spell it: `gsz<i64>(&GS)` (8, measured).
- Stops compiling: a declaration-zone global initialised from such a call that returns `: T` — `var G = gd(&GS);` with
  `fn gd<T>(x: *T): T` — now "'gd$S' returns a struct by value, and a struct result needs storage in a fn's frame — call
  it inside a fn" (it stored the base's word), as the explicit `gd<S>(&GS)` already was. Make the call inside a fn.
- Changes which fn runs: through an `x: T` parameter a `var q: *S` LOCAL now infers i64, as the guide says and as a
  `*S` parameter already did — `sizeof(T)` there reads 8 (24 before).
- Stops compiling: a generic that uses `T` as a struct, given a `*S` local through `x: T` —
  `fn gst<T>(x: T): i64 { return x.v; }`, `gst(q)` — is refused naming `gst` (it compiled and read through the
  pointer). Write `gst<S>(q)` (5, measured). `gst(*q)` does not bind S through a plain `x: T` yet either (filed, 6.7.15).
- Starts working: a generic that uses `T` as a struct through a `p: *T` pointer, refused as its stub before, compiles;
  `var q: Pt = gd(gpp)` no longer faults.
- Still i64 (filed, 6.7.15, a decision): a SCALAR pointee through `p: *T` — `second(pa)` with `pa: *i32` binds i64 and
  steps 8 bytes; spell it `second<i32>(pa)`. Inside a generic body, a receiver bound from such a call
  (`var r = gd(&GP0); return r.pick(t);`) is still refused — spell `gd<P>(&GP0)`.

Nothing to migrate (refused code now compiles, a crash or a wrong refusal becomes the right answer, or only error output
changes): GN-2 (a gate row only), GN-3 (a generic with more than 64 carriers, T-typed names or bounded receivers
compiles), GN-4 (an inline-replayed `return` inside a struct-returning fn compiles), GN-5 / GN-5r (`var h: S = gpg<S>();`
from a `: *T` generic is a handle; a use that compiled gives the same value, and the `: T` scalar shapes stay refused),
GN-6 (a generic `: *Box<T>` return compiles; `: *Box<Zork>` is reported once), GN-8 (a refused explicit type argument
reports one error), GN-12 (a generic forwarding T inside a struct carrier into a stub generic compiles), GN-13 (no orphan
bound note), GN-14 / GN-14r (a generic forwarding T to a bounded generic with no i64 impl compiles at the other types, up
to 64 forwards; a scalar call of it is refused naming the forward and the missing impl), GN-15 (a bounded call on a
carrier's T field compiles), GN-16 (explicit type arguments on a method call, `p.id<f64>(h)`, compile — D7 (a); they were
refused everywhere, and a comparison on a field, `p.n < k`, reads as before), GN-18 / GN-18r (an error in a generic body
and its notes print once — a script that counted one error line per instance sees one).

#### Language — the frontend: diagnostics, consts, globals, declarations (the frontend lane)

The decisions are the user's at the 6.7.14 open (2026-10-16, D9 – D15). "6.7.13's Dn" / "6.7.11's Dn" are those opens'
ids. Each block names its CHANGELOG [6.7.14] bite. Every refusal below is a frontend diagnostic, the same on x86_64,
aarch64, cx, PE and Mach-O.

**FE-4 — a const context's skipped arm is a call path too (no decision: the guide's `private` boundary covers every way of reaching a fn)**
- Stops compiling: a const context that names another file's `private` const fn only in an arm the evaluator skips —
  the right operand of a short-circuit (`const X = 1 || pk();`, `const X = 0 && pk() == 3;`) or an if-expression's
  untaken arm (`const X = if (1 == 1) { 3 } else { pk() };`), in a top-level or a local const — "'pk' is private to its
  file", once at the call. It compiled and ran; the run-time `var X = 1 || pk();` was already refused. Call a public fn
  there, or move the const into the file that defines `pk`.
- A new warning: a `#deprecated` const fn named in such an arm warns once ("'dk' is deprecated: …"), as in a run-time
  expression.

**FE-15 — a declaration-zone constant initializer runs nothing at startup (D11 (b), the user 2026-10-16; the two orderings below ⚠ go beyond D11's text)**
- Changes what it computes: a declaration-zone global whose initializer folds to a constant through a zero or an enum
  constant no longer re-runs its expression at startup — `var R = (INT_MIN) % (0 - 1);` starts as 0 and an enum-named
  `var Q = (0 - CF_MAX - 1) / (0 - 1);` as INT_MIN on every target. Through 6.7.13 they trapped at startup on x86_64
  and cx (SIGFPE, exit 136) and on PE (the divide exception, 148), and ran on aarch64. A program that relied
  on that startup crash now runs; if the trap was wanted, divide at run time in a fn.
- Changes what it computes: a call in an EARLIER declaration-zone initializer that writes a global declared later with
  a constant initializer (`= C`, `= E.A`, a folded expression, `= 0`) keeps its write — `fn setg() { G = 9; }
  var r = setg(); var G = C;` ends with G == 9 (through 6.7.13 the startup store reset it to C; with `= 0`, to 0). That is
  what a literal initializer (`var G = 5;`) always did. If the constant must win, assign it after the call (`G = C;` in
  a fn, or as a top-level statement after the first one).
- Changes what it computes: the same after an earlier NONZERO literal declaration of the name — `var G = 3; var r =
  setg(); var G = C;` (or `= E.B`) ends at setg's write, 9 (through 6.7.13, C): the later constant is the global's value
  from program start, as between two literals.
- Unchanged: when an earlier declaration of the name is computed, `= 0`, or a const- / enum-named constant of another
  value, the redeclaration keeps its order (`var G = D; var r = setg(); var G = C;` and `var G = 0; var r = setg();
  var G = C;` end at C; `var a = D; var b = a; var a = C;` reads D into b). Whether a named constant should order like a
  literal is an open question for the user (filed, 6.7.15) — do not rely on either reading across that boundary.
- No startup store is emitted for such a global (x86_64: 18 bytes and three instructions each), so the binary is
  smaller; a bool global, a slot an array list covers and an initializer naming another file's private const keep it.

**FE-17 — a declaration-zone float-literal global is baked into the image (no decision; ⚠ beyond its issue's text: D11 (b)'s reading applied to a float literal)**
- Changes what it computes: a declaration-zone `var G: f64 = <float literal>;`, `var F: f32 = <literal>;`, `= -<literal>`
  or an untyped `var K = 1.5;` is its value from program start on every target. An EARLIER declaration-zone initializer
  that reads it (`var b = load64(&G); var G: f64 = 1.5;`) now sees the literal (it read 0), and one whose fn call writes
  it keeps that write (the startup store used to reset it to the literal). Reorder the declarations if a code path
  relied on the old reading.
- An x86 `kernel;` build reads the value (it read 0) and no longer warns "the initializer of 'G' runs after the top-level
  program" for it.
- Unchanged: a float initializer that is not a bare literal (`(1.5)`, `1.5 + 1.0`, an f64 const, a call) is still a
  startup store (in a `kernel;` build still late and warned); a redeclared float keeps its order.

**FE-18 — a redeclared global's later folded constant is compared (no decision: the guide's § Declaring a global twice)**
- A new warning: a global redeclared with a later initializer that folds to a DIFFERENT constant — `var a = 5; var a =
  2 + 1;`, `= -5`, `= (7)`, `var a = 0; var a = 2 - 1;`, a bool redeclared to the other literal (`var B: bool = false;
  var B: bool = true;`: `true` / `false` compare as 1 / 0), `var a = 5; var a = true;` — warns "duplicate symbol 'a'
  redefined with conflicting value (last definition wins)", as `= 3` always did. A warning only: the value (the last
  definition) and the exit code are unchanged. Give the two declarations the same value, or rename one. The census found
  none in the tree or any fold.

**FE-19 — a global redeclared with another bool-ness is refused (D9 (a), the user 2026-10-16)**
- Stops compiling: a declaration-zone global declared both as an integer (untyped, an integer type, or a destructure
  target `var G, H = f();`) and as `bool`, in either order — `var G = 5; var G: bool = G;` (which built a bool holding
  5), `var G = 5; var G: bool = true;`, `var G = 5; var X: bool = G; var G: bool = true;`, `var G: bool = true;
  var G = 1;` — "global 'G' redeclared with a different type or size (a global has one definition; rename one)". Give
  both declarations the same type, or rename one. (No such pair in lib/, src/, cbt/, programs/ or tests/.)
- Unchanged: two `bool` declarations of one global still fold.

**FE-20 — a `var` annotation that is no type is refused by name (D15 (a), the user 2026-10-16)**
- Stops compiling: a `var` whose annotation is a number, an operator, a string or other punctuation — `var b: 1 = 0;`,
  `var c: + = 2;`, `var d: "s" = 3;`, `var b: , = 0;`, a for-init `var i: 3 = 0` — in a fn, in the declaration zone or
  after the first top-level statement: "expected a type for variable 'b', got number 1" (`got '+'`, `got string`).
  Through 6.7.13 the token was dropped and the variable was a plain i64. Write the type, or drop the `:`. `cyrius lint`
  reports it too. (None in the tree.)

**FE-21 — `#pure`'s `#io` / `#alloc` check sees a callee defined later (no decision: the check's own contract)**
- A new warning: a `#pure` fn that calls an `#io` / `#alloc` fn defined AFTER it — a plain call, a tail call, a method of
  a later `impl`, a fn after the first top-level statement or in a top-level block — warns "#pure fn calls #io fn
  'wr'", as it did for one defined before it. A warning only; nothing stops compiling. Drop `#pure`, or the effect.

**FE-22 — `#inline` on an `async fn` is warned (no decision: v6.5.63's "an ignored `#inline` says so")**
- A new warning: `#inline` on an `async fn` (a plain Future or a coroutine) warns "#inline ignored: async fn 'f' runs
  through its Future" at the body's `}`. It never had an effect; drop the `#inline`. The binary is unchanged.

**FE-23 — a call-site diagnostic names its callee as the source spells it (no decision: diagnostic text)**
- Renamed in diagnostics: a script or test that greps cycc's output for a method's mangled name (`'S_m'`, `'T_Tr_m'`)
  or a generic instance (`'g$i32'`) — in the vector / struct-type refusals, arity, named arguments, `#pure`,
  `#deprecated`, `#must_use`, `private`, the destructure, the bool / cstring parameter checks, and "undefined function
  'S_m'" (on every back end) — now reads `'S.m'` / `'g<i32>'` (`'g2<i32, i64>'`, `'gx<Box<i64>>'`).
- Changed count: a method call's arity message counts the arguments in its parentheses, without `self` — `s.two(1, 2)`
  on `fn two(self, a)` is "'S.two' expects 1 argument, got 2" (was "'S_two' expects 2 arguments, got 3"); a `dyn` call
  likewise. The free spelling `S_two(&s, 1, 2)` keeps its count (it is named `S.two`), and a method that declares no
  parameter at all keeps the receiver in its count.
- Unchanged: the generics lane's refusals naming a generic method (`generic 'P_pick' ...`) keep the mangled name
  (filed, 6.7.15); a free fn named `S_x` and a `mod` fn `mm_f` keep their names. Nothing that compiled stops compiling.

**FE-26 — a u128 parameter is refused by name; a captured u128 is its value (D10 (a), the user 2026-10-16)**
- Stops compiling: a fn, a method or a trait member with a bare `u128` parameter (`fn big(v: u128)`) — "`u128` is not
  supported as a parameter type yet - pass `*u128`". It only ever received the low word, compared SIGNED, and
  `&v + 8` read the next frame slot. Pass `*u128` (`fn f(v: *u128)`, called `f(&b)`) or the two halves as i64s.
  `*u128` and `*fn(u128)` are unchanged.
- Changes what it computes: a closure that reads a captured `u128` reads its value — `c == 5`, `c < k`, `c + 1`, a
  truth test, `!c`, `match c` — where it read the env copy's ADDRESS.
- The `u128` return and field types (`fn mk(): u128`, `struct S { w: u128; }`) never compiled; only their message
  changes ("... as a fn return type yet", "... as a field type yet"). A trait member's `: u128` return still compiles.

Nothing to migrate (diagnostics on code that never compiled, refused code that now compiles, or code size only): FE-1
(an operator / float-literal token is named where it said `got unknown`), FE-2 (a private call reported once per site),
FE-3 and FE-5 (a refused const no longer hides the errors after it), FE-6 (a local const in an `#inline` / generic body:
the second call in one scope compiles), FE-7 (one error per mistake: a const fn's unknown name, an unclosed call, a
for-step call with its note, the end of file located), FE-8 and FE-9 (a field of a const / an undeclared base named
once), FE-10 and FE-11 (a bare const statement is "expected '='"; the next statement's error is kept), FE-12 (`cyrius
lint` no longer refuses `a.f.g` through a `*T` declared elsewhere), FE-13 (a zone `**T` global compiles), FE-14 (a
named struct literal in the declaration zone compiles; the positional form keeps working), FE-16 (`2 * C` folds: values
unchanged, code smaller), FE-24 (D12 (a): a struct literal outside an initializer was refused before, now by name —
"a struct literal is an initializer: declare `var t: P = P { .. };` and assign or pass t" where it said "undefined
variable 'P'"; `var q: P = (P { 5, 6 });` now compiles), FE-25 (D13 (a): a declaration after the first top-level
statement was refused before, now one error naming the rule; D14 (a): an `async fn` there now compiles), FE-14r and
FE-15r (gates and the guide).

#### Tooling — the CLI, cyrius header, the kill handler, lsp (the tools lane)

Each block names its CHANGELOG [6.7.14] bite (the tools lane, TL-*). D47 and D54 are the user's decisions at the 6.7.14
open (2026-10-16). "6.7.13's Dn" is an id from the 6.7.13 open.

**TL-1 — the macOS CLIs refuse `--win`**
- On a macOS host (Apple Silicon and Intel), `cyrius build --win` exits 1 with
  `error: --win is not available from the macOS CLI: cycc emits Mach-O only (build PE images on x86_64 Linux or Windows)`,
  and nothing is written. So does every other verb that takes the target block (`cyrius run --win` included). It used
  to write a Mach-O named `.exe` and say OK at rc 0, never a PE, and an existing output of that name was overwritten.
- To migrate, build Windows images on an x86_64 Linux host or on Windows. A Mac build step that ran `--win` (under
  `set -e`, or checking only rc) now fails there by name; its output was never a PE.
- § 6.7.13's TL-2 line "⚠ Not changed yet: on a macOS host, `cyrius build --win` still writes a Mach-O named `.exe`" is
  history.

**TL-2 — the aarch64 Linux CLI resolves `[deps.X] target` for aarch64**
- On an aarch64 Linux host (pi), a `cyrius deps` / `cyrius build` without `--aarch64` now vendors the deps declared
  `target = "aarch64"` / `"arm64"` and skips those declared `target = "x86_64"` / `"x86"`. Through 6.7.13 it did the
  opposite, at rc 0: the x86_64 dep was vendored and prepended into the aarch64 build, and the aarch64 dep was missing.
  `--aarch64` already resolved this way, and still does.
- To migrate, re-run `cyrius deps` on that host and commit the changed lib/ and cyrius.lock if you track them. A
  project that leaned on the x86_64 dep being pulled on aarch64 now gets what its manifest declares: drop that dep's
  `target`, or declare the aarch64 one.
- Other hosts are unchanged. § 6.7.13's TL-2 line about this target axis is history.

**TL-3 — `cyrius header` reads a wrapped parameter list whole**
- A public fn whose parameter list wraps lines (`fn f(a, b,` / `  c): i64 {`) now gets every parameter in its
  prototype. Through 6.7.13 the header kept the first line's parameters only, at rc 0: lib/tls_native_keysched.cyr's
  nine-parameter `tls_native_hkdf_expand_label` printed four.
  - Regenerate any checked-in header made from such a file. In cyrius's own lib, the changed headers are
    lib/tls_native_keysched.cyr (4 prototypes) and the folded mabda (19), sigil (11) and sandhi (4).
  - A C caller written against the short prototype now meets a "too few arguments" error. The C call was already wrong:
    the dropped arguments were read from whatever the registers held. Pass every argument.
- A SIMD vector parameter on a continuation line is now refused by name, as the one-line spelling has been since 6.7.13:
  ``error: cyrius header: '<f>' takes '<param>: <type>': a SIMD vector parameter, which no C11 type carries; no prototype written``,
  rc 1, with the rest of the header still written. A `cyrius header f.cyr > f.h` step under `set -e` now fails on such
  a file. To migrate, as § 6.7.13's TL-4 says: make the fn private (`_`-named), or take a pointer (`p: *f64v2`).
- A parameter list of blanks alone (`fn e1( )`) prints `e1(void)`. It printed `e1()`, a C non-prototype declaration.
- § 6.7.13's TL-4 caveat ("keep a public signature on one line, or check its header by hand") is history.

**TL-4 — `cyrius header lib/net.cyr`: `sock_send_a` / `sock_recv_a` are `: Result`**
- lib/net.cyr's `sock_send_a` and `sock_recv_a` are now declared `: Result`. Under `: i64` they already returned
  lib/result.cyr's (tag, payload) pair through `ok_via` / `err_via`.
- `cyrius header lib/net.cyr` prints `cyr_val2 sock_send_a(..)` and `cyr_val2 sock_recv_a(..)` under the x86_64 SysV
  guard, with the named aarch64 / Win64 comment in the other arm. It used to print `cyr_val`, and a C caller read the
  tag alone. Regenerate any checked-in header generated from lib/net.cyr.
- Every caller compiles byte-identical (a 7,960-pair differential over eight targets), so cyrius code has nothing to
  change. `var x = sock_send_a(..);` was already refused "bind both", and still is.

**TL-8 — cyrius-lsp: a file outside any project reads no pin of the server's working directory (D47 / D54)**
- When the editor starts the server inside a project, a file with no cyrius.cyml at or above it is checked with the
  CLI's version redirect off and cycc's pin-drift warning off.
  - If that project pins a cyrius that is not installed, the loose file publishes `[]`. Since 6.7.13 it showed the
    project's `cyrius.cyml pins version … but cyrius binary is not installed` error on line 1; 6.7.12 showed nothing.
  - If that project pins a different cyrius that IS installed, the loose file is checked by the toolchain the server
    found, no longer by the pinned one (since 6.7.13, the pinned CLI ran on it).
- A project's own files keep their pin: the redirect and its error are unchanged. A loose file's sibling `include`
  still resolves as 6.7.13 made it.
- Nothing to change. To check a loose file under a project's pin, run `cyrius check <abs file>` from that project
  (unchanged); the editor no longer does.

No block for the lane's other bites:
- TL-5: a gate. `cli_temp_dir_no_leak.sh` is green under `nohup`.
- TL-6: a `cyrius deps` / `build` stopped by SIGTERM / SIGINT / SIGHUP while its own git runs now sends the signal to
  git and waits for it. It leaves no capture or temp dir, and a killed `git clone` removes its partial cache directory
  instead of finishing it after the CLI has died. `$?` is still 128+N, and the CLI still dies by the signal (6.7.13's
  D39). ⚠ Filed (6.7.15): the wait has no bound, so a `git` (or a PATH wrapper) that ignores the signal holds the
  killed CLI until it exits.
- TL-7: a `cyrius deps --locked`, or a resolve stopped in its pin-move dry pass, leaves no scratch resolve and no temp
  dir. lib/ and cyrius.lock were never touched, and still are not. ⚠ Filed (6.7.15): a file another process of the
  same user planted at the copy's predicted temp name, inside the CLI's own temp dir, is unlinked by the kill.

#### Platform — Windows PE failure answers, arm64 macOS, the native-region warning, tarballs, cyrius-watch, the Windows CTL (the platform lane)

Each block names its CHANGELOG [6.7.14] bite (the platform lane, PL-*). D56, D57 and D59 – D61 are the user's decisions
at the 6.7.14 open (2026-10-16). "6.7.12's Dn" is an id from the 6.7.12 open (2026-10-15). PL-1 – PL-3 and PL-5 needed
no decision: each is fixed to what the wrapper documents.

**PL-1 — Windows: a failed read or write answers a negative errno (no decision: fixed to what the wrappers document)**
- Windows only. `sys_read` / `file_read` / `file_read_r` and `sys_write` / `file_write` answer a negative errno for a
  failure where they answered 0:
  - a bad handle gives -9;
  - a write to a closed pipe gives -32;
  - a full disk gives -28;
  - access denied gives -13;
  - a Win32 code with no POSIX peer gives -1.

  `file_read_r` on a handle that is not open is an `Err` where it was `Ok(0)`.
- Unchanged: a read at the end of a file is 0, and so is a read from a pipe whose writer closed (ERROR_BROKEN_PIPE).
  That is how a piped stdin ends.
- **Migrate:**
  - A read loop that treated 0 as "done" must also stop on `< 0`, as it already must on Linux. It used to stop early on
    a failure with a short, complete-looking result.
  - A write loop that spun on a 0 return now sees a negative. Treat `< 0` as the error it is; never subtract it from
    the bytes left.

**PL-2 — Windows: a failed seek answers a negative errno, no longer a seek to 0 (no decision: fixed to what `sys_lseek` documents)**
- Windows only. A failed `sys_lseek` / `xlseek` answers a negative errno where it answered 0, and the position is
  unchanged:
  - a position before 0, or a bad `whence`, gives -22;
  - a bad handle gives -9.

  An `xlseek(...) < 0` test now fires. Before, a failed seek read as a seek to 0 while the file pointer stayed put, so
  the next write landed at the old position.
- A seek on fd 0, 1 or 2 (a redirected stdin / stdout / stderr) answers -9 where it answered 0. That seek has always
  failed on Windows: `ELSEEK_PE` passes the std fds as raw HANDLE values (filed, 6.7.15). Linux and macOS give the
  offset.
- **Migrate:** code that treated a 0 from a Windows seek as success, or that seeks a std fd on Windows, must handle
  `< 0`. Seek a handle you opened instead of a std fd.

**PL-3 — Windows: a failed open answers the errno that names the failure (no decision)**
- Windows only. `sys_open` / `file_open` answer a negative errno, no longer -1 for every failure:
  - not found / path not found: -2;
  - access denied / a sharing violation: -13;
  - exists: -17;
  - a name too long: -36;
  - an invalid parameter: -22.

  A Win32 code with no POSIX peer, and a path the widen refuses, stay -1. `file_open_r` / `file_read_all_r` now say
  `IoNotFound` for a missing file (they said `IoOther`).
- Two refusals change value and stay refusals:
  - A plain open of a directory (no `O_DIRECTORY`), or an `O_NOFOLLOW` read-only open of one: -1 → -13.
  - `O_CREAT|O_EXCL` over an existing file or link: -1 → -17. Over an existing DIRECTORY, `file_open` gives -13
    (Windows answers ERROR_ACCESS_DENIED there).
- Unchanged: `file_create_exclusive(path)` over a file, a link or a directory is -17 on every target. Its Windows arm
  now classifies a -13 by asking the name.
- **Migrate:**
  - Code comparing a Windows open result with `-1` exactly must use `< 0`, or the errno it wants (-2, -13, -17).
  - Code that took `IoOther` as "missing" on Windows can test `IoNotFound`, as on Linux.

**PL-5 — arm64 macOS: `sys_mkdirat` / `sys_fchmodat` act relative to the dirfd they are given (no decision)**
- arm64 macOS only. `sys_mkdirat(dirfd, rel, …)` / `sys_fchmodat(dirfd, rel, …)` now act on `rel` under `dirfd`.
  Before, they acted under the current directory: mkdirat made `./rel` and returned 0, and fchmodat changed (or failed
  to find) `./rel`. `AT_FDCWD` still means the current directory.
- `sys_fchmodat`'s flags now reach Darwin:
  - AT_SYMLINK_NOFOLLOW (the stdlib's per-target value, 0x20 on macOS) makes it act on a link itself. Linux's
    3-argument fchmodat syscall ignores the flags word and follows the link.
  - A raw Linux 0x100 is -22 (EINVAL) on macOS.
- x86 macOS, Linux and Windows are unchanged.
- **Migrate:**
  - Code that passed a dirfd and relied on the cwd behaviour now gets the dirfd's: pass `AT_FDCWD` (or an absolute path)
    to mean the cwd. Code that passed an absolute path to work around the defect (§ 6.7.12's WN-3 advised it) can pass
    the dirfd-relative name.
  - Code that passes AT_SYMLINK_NOFOLLOW to `sys_fchmodat` gets a link-only chmod on arm64 macOS where Linux follows the
    link. Pass 0 to follow on every target.

**PL-6 — aarch64: the native-region renumber warning carries through `include` and judges a declared constant (D61; 6.7.12's D1, warn only)**
- Warn only: a program whose syscall constants do not collide with the stdlib's builds the same binary. On an aarch64
  build two shapes gain the warning:
  - a file `include`d from inside an aarch64 region (`#ifdef CYRIUS_ARCH_AARCH64`, `#ifplat aarch64`, …) whose raw
    syscall number a compat row renumbers. Example: `raw syscall 9 inside a native-aarch64 region is renumbered → 222
    (mmap); write 1009 for native lgetxattr`, located in the included file;
  - an `enum` constant or a top-level `const` DECLARED inside such a region (in its own file) and passed to
    `syscall()`. Example: `syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered →
    172 (getpid); write 1039 for native umount2`.

  Both shapes ran the wrong syscall before, silently.
- New public enum constants: `SYS_POLL` (7, in the x86_64-Linux, x86-macOS and aarch64 peers) and `SYS_EPOLL_WAIT`
  (232, now in the aarch64 peer too; the x86 peers had it). A program that includes `lib/syscalls.cyr` carries one more
  unused enum slot (+8 B of data).
- ⚠ A program that declares its own `SYS_POLL` with a value other than 7 (or, on aarch64, its own `SYS_EPOLL_WAIT`
  other than 232) now gets `duplicate symbol 'SYS_POLL' redefined with conflicting value (last definition wins)`, and
  its binary changes. Measured on x86_64:
  - with the program's enum AFTER the include, the stdlib's `fd_wait_ready` issues the program's number;
  - with it BEFORE the include, the program's own `syscall(SYS_POLL, …)` issues 7.

  The same value changes nothing.
- **Migrate:**
  - For a warning, follow its advice: the `1000 + N` private alias for a native number, or the stdlib's `SYS_*` name /
    wrapper for the x86 number.
  - For a collision, rename the program's own constant (it is a different syscall on aarch64 and macOS), or drop it and
    use the stdlib's.
- ⚠ Still silent (filed, 6.7.15):
  - a `const` declared inside a fn body in a region;
  - a constant declared at the top level of a per-arch file included from inside the guard.

  Spell those numbers as the `1000 + N` alias.

**PL-7 — Windows: `_win_widen` / `_win_widen_n` are removed (D56)**
- `_win_widen(dst, src, cap)` and `_win_widen_n(dst, src, n, cap)` are gone from `lib/syscalls_windows.cyr`. A program
  that calls either underscore-private helper by name no longer compiles for Windows. Nothing in cyrius or its folds
  called them.
- **Migrate:** pass the UTF-8 path straight to the stdlib wrapper (`sys_open`, `sys_mkdir`, `sys_symlink`, …). It hands
  the path to a reroute that widens it in the emitter.

**PL-8 — `cyrius-watch.sh` builds through `cyrius build` (D60)**
- Each build (the first pass and every rebuild) is `cyrius build "$SRC" "$OUT"`:
  - the manifest's [deps] and includes are prepended, and `include` resolves relative to the entry file;
  - the output is signed on macOS, so it launches on Apple Silicon (it was killed at exec, 137);
  - the compiler's diagnostic is shown;
  - a failed build keeps the previous output (it left an empty one).
- The watcher needs the `cyrius` CLI: `CYRIUS_BIN`, else `cyrius` on PATH, else `$CYRIUS_HOME/bin/cyrius`. Without
  one it stops with `error: the cyrius CLI not found (set CYRIUS_BIN, or put cyrius on PATH)`. `CYRIUS_CC` is
  ignored. The banner line is `cyrius: <path>` (was `cycc: <path>`).
- **Migrate:**
  - Point `CYRIUS_BIN` at the CLI where you pointed `CYRIUS_CC` at a compiler.
  - A project that only built without its manifest's prepends may now differ, or fail where it used to build. Fix it
    so `cyrius build` builds it.
  - Run the script by its own name (`cyrius-watch.sh [src] [out]`). `cyrius watch` was never a verb.

**PL-9 — the aarch64-linux release tarball ships every [release] bin and script (D59; 6.7.12's D4)**
- An aarch64 Linux binary install gains these in `~/.cyrius/bin`:
  - `cyrius` (the CLI, so `cyrius build`, `test` and `repl` exist there);
  - cyrfmt, cyrlint, cyrdoc, cyaudit, ark, cyrld, `cyrius_api_surface`, `cyrius-lsp`, `ts_test_runner`, `cyrsign-efi`
    and cxvm;
  - the three [release] scripts (`cyrius-repl.sh`, `cyrius-watch.sh`, `cyrius-prompt-info`).

  cybs is not shipped there: it is x86_64 assembly with no aarch64 form.
- `bin/cyriusly` is now the compiled version manager, as on x86_64. The shell script stays at
  `versions/<v>/scripts/cyriusly`.
- ⚠ `ts_test_runner` reports every `.ts` file as a failure on aarch64, because the aarch64 compiler has no TS front end
  (filed, 6.7.15). Run TS tests on x86_64 meanwhile.
- **Migrate:** a source-installed CLI on an aarch64 box is no longer needed for a binary install. A script that
  expected `bin/cyriusly` to be a shell script should call `scripts/cyriusly` in the version slot.

**PL-10 — Windows: the disallowed CTL's 48-byte entries are applied (D57; the rule is confirmed)**
- Windows only. A native TLS ctx using the system roots (`tls_native_set_ca_system`) refuses a chain that contains any
  of the six certificates the CTL's 48-byte entries name: the DarkMatter intermediates QuoVadis issued in 2016 – 2017.
  The match is the SHA-384 of a SHA-384-signed certificate's tbsCertificate, crypt32's signature hash (prop 15),
  confirmed on Windows.
  - All six expired in 2024 – 2025, so a chain through them already failed on validity, and no live server is
    expected to change.
  - A ctx given a caller's bundle carries no policy and is unchanged. POSIX is unchanged.
  - The trust-store split line on Windows reads `CTL: 88 entries, 82 public-key MD5s + 6 SHA-384 TBS hashes applied,
    0 of other lengths not applied`.
- The underscore-private API, for code that calls the stdlib's private fns:
  - `_tn_w_ctl_copy(ctl, pn)` → `_tn_w_ctl_copy(ctl, pn, pt, pnt)`;
  - `_tn_w_ctl_keys(pn)` → `_tn_w_ctl_keys(pn, pt, pnt)`;
  - the trust-policy block is 64 B (`_TN_POL_LEN`, was 48). `_tn_pol_new` keeps its signature, and
    `_tn_pol_set_tbs384(pol, n, hashes)` adds the new list.
- **Migrate:** nothing for a caller of the public API. A caller of the private fns passes the two new out-parameters.

No block for PL-4 (the release gate runs the whole corpus on cass: no program changes), PL-11 (process docs) or PL-3r
(a comment).

#### Language — struct values and inline Str (the structs lane)

The 6.7.14 decisions are the user's at the 6.7.14 open (2026-10-16): D17 – D23. Ids from other releases are written
with their release:
- **6.7.13's** (2026-10-15): D1, D5, D6, D7, D9, D34.
- **6.7.11's** (2026-10-13): D4, D15.
- **6.7.10's:** decisions 6 and 7.

Each block names its CHANGELOG [6.7.14] bite.

**ST-5 — a program's own `struct Result` / `Option` / `Tagged` is a plain struct (no decision: the parameter classifier read the name as the stdlib's handle)**
- Starts working: an inline value of your own `struct Result { .. }` (or `Option`, `Tagged`) passed to a by-value
  parameter `x: Result` now passes the struct. It faulted on every target. A method with an untyped `self` in
  `impl Result { .. }` compiles. It was "no struct type in scope for 'self'".
- Changes what it computes: a HEAP HANDLE of such a struct (`var h: Result = alloc(16);`) passed to `x: Result` is now a
  copy, as for every other struct (6.6.16's by-value rule). Through 6.7.13 it was the handle's word, so the callee's
  writes (`x.b = 99`) reached the caller's object. To keep the alias, declare the parameter `x: *Result` and pass `h`.
  The same handle assigned from an inline value (`h = t`) now copies, where it faulted. `return h;` from a fn returning
  `Result` returns the struct, where it returned garbage.
- Unchanged: the stdlib's `Result` / `Option` / `Tagged` (`: stack` enums in `lib/result.cyr` / `lib/tagged.cyr`) build
  byte-identical, and `Str` stays a handle by name.

**ST-6 — `bs(n + &x)` with a narrow `n` passes the struct (no decision: 6.7.11's D15 with 6.7.10's decision 7)**
- Changes what it computes: `f(n + &x)` is a call with `n` a narrow local or parameter (`i8` / `i16` / `i32` / `u8`)
  into a by-value struct parameter of 8 B or less. It now passes the struct at `&x + n`, as `f(&x + n)` does. It passed
  the address itself as the struct's word, a value no program could have meant. `f(n + 5)` is still the value.

**ST-7 — `**pp` through a `pp: **S` is the struct value `*p` is (no decision for the reads: 6.7.10's decision 6 with 6.7.13's D9 (a); the store and compound rules are 6.7.11's D4)**
- Changes what it computes:
  - `**pp = u` copies `sizeof(S)` bytes. It stored one word into S's first field.
  - `l = **pp` and `l = *pp + n` into a struct `l` copy the struct. They stored S's first word or the pointer word into
    l's first field.
  - `return *pp;` from a fn returning `S` (8 B or less) returns the struct `*pp` points at. It returned the pointer's
    bits.
  - A 1..7-byte `**pp` reads only the struct's bytes. It read 8.
  - `**pp + a` calls `S_add`. It faulted.
- Stops compiling:
  - `**pp += v` / `-=` / … is refused "compound assignment to the struct 'pp' points at is refused …". It operated on
    S's first word. Write `**pp = **pp + b` with an `S_add`, or operate on the field: `var p: *S = *pp; p.x += v`.
    (`(*pp).x += v` is no spelling: a store after parentheses is refused by the receives lane's D24.)
  - An if-expression branch `{ **pp }` of a struct over 8 bytes is refused "an if expression branch cannot be a struct
    value over 8 bytes …". It compiled and crashed. Branch on the pointers into a pointer, then copy:
    `var r: *S = if (c) { *pp } else { *qq }; var v: S = r;`. Do not write `var v: S = if (c) { *pp } else { *qq };`:
    that binds v to the struct as a handle, the filed `var t: S = *pp;` defect.
- Starts working:
  - `var t: S = **pp;` copies (it faulted).
  - `return **pp;` and `return *pp;` from a fn returning a 9-16 B struct (refused before).
  - `{ **pp } else { **qq }` of 8 B or less into a `var v: S` (it crashed).
- Unchanged (filed, 6.7.15): a plain `l = *pp`, `G = *pp` or `*q = *pp` still stores the pointer word into the first
  field, and `var t: S = *pp;` binds a handle to the struct where `var t: S = p;` copies. Write `var p: *S = *pp;` and
  copy from `p`.

**ST-8 — a struct field, call or dereference into a pointer of another kind is refused (no new decision: 6.7.13's D5 (a), "a struct value … refused by name")**
- Stops compiling: a struct VALUE passed to a `*i64` / `*u8` / `**T` parameter (any `*T` that records no struct),
  wrapped or not, in a fn, a closure or at top level: "cannot pass 's' to a parameter that is not a pointer to its
  struct type in a call to 'ri' - a struct value is no address". The values are:
  - a struct-typed field `ri(w.s)`;
  - a by-value struct call `ri(mk())`;
  - a method or operator result `ri(o.dup())` / `ri(a + b)`;
  - a dereference `ri(*pp)` / `ri(**pp)`.

  Each pushed the value's first word as the address and faulted, or read through whatever that field held. Pass an
  address instead:
  - for a field, `&w + offset` (`&w.s` is refused since 6.7.13);
  - for a dereference, the pointer itself (`ri(pp)`);
  - for a call result, a local holding it (`var t = mk(); ri(&t)`).
- Unchanged: an address (`&w + 0`), a `*T` field, a `: *T` call or method, `*ppi` of a `**i64`, a scalar field and a
  `Str` field pass as before.

**ST-9 — a whole dereference of a `*V` as an if-expression branch is refused (no new decision: 6.7.13's D34 with the existing vector-branch refusal)**
- Stops compiling: `var x = if (c) { *pv } else { .. };` with `pv: *V`, any vector width, in a fn or at top level. Also
  `{ (*pv) }`, `{ *gpv() }`, `{ *&v }`, `{ **ppv }`, a `*V` field and `*(pv + 0)`. The message is "an if expression
  branch cannot be a vector, u128 or slice value - branch on a pointer (&x)". These yielded lane 0's bits as an
  integer. Branch on the pointers (`if (c) { pa } else { pb }`) and dereference after, or read the lane you want
  explicitly.

**ST-10 — `*(&s) OP= v` on a struct is refused (D17 (a), the user 2026-10-16)**
- Stops compiling: `*(&s) += v` (any compound operator; also `*&s`, `*((&s))`) with `s` a struct value, refused "compound
  assignment to struct 's' is refused - a struct value is not an integer or a float (write `a = a + b`)". `s` may be a
  local, a by-value parameter, a global or a capture, in a fn, at top level or in a for step. It added v to s's first
  field. Write the field (`s.x += v`), or `s = s + b` with an operator fn.
- Unchanged: `*(&h) OP= v` of a handle and `*(&n) OP= v` of a scalar keep the word op.

**ST-11 — `return &q;` of a handle, a `*T` or an untyped `self` in a struct-returning fn is refused (D19 (a), the user 2026-10-16)**
- Stops compiling: `return &q;` (or `return (&q);`) in a fn returning a struct, at every size: "a fn returning the
  struct `S8` takes a value of that struct, or a pointer to one — `&q` is the address of q's slot, not a struct —
  return q". `q` may be a handle (a local or global), a `*T` (a local, parameter or global) or an untyped `self`. At
  8 B or less it returned the slot's stack address as the struct's word. Over 8 B it was refused in other words. Write
  `return q;`, which returns the struct q points at. For a `*U` or a handle of ANOTHER struct the same refusal fires.
  There, return a value of the fn's own struct.
- Unchanged: `return &s;` of an inline struct is still the struct (6.7.13's D4 (a)). `return &n;` of a scalar, a `*i64`
  or a `Str` handle is not refused (filed, 6.7.15).

**ST-12 — `t = a` into an inline `Str` copies the header; a bare `var t: Str;` is an inline `Str` (D20 (a), the user 2026-10-16)**
- Changes what it computes: `t = a` with t an inline `Str` and a a `Str` HANDLE now copies the 16-byte header a points
  at. a may be a handle local, parameter or global, a call or method declared `: Str`, or a `Str` field. It stored a's
  address into `t.data` and left `t.len` stale. Consequences:
  - `t.len` is now a's length.
  - A later write through a (`a.len = 2`) no longer shows in t.
  - A literal-declared t (`var t: Str = Str { .. }; t = a;`) now takes a's length, where it kept the literal's.
  - An untyped source keeps the one-word store.
- Changes what it computes: a bare `var t: Str;` (no initialiser) is an inline `Str` under 6.7.13's D7 (1):
  - Its name where a `Str` is taken (`f(t)`, `str_len(t)`) is its header's address.
  - `var h: Str = t;` / `var h = t;` BIND h to its header: a write through h changes t.
  - In an untyped position (`vec_push(v, t)`, `store64(p, t)`, an untyped global) it gives its first word, which is
    the string's data pointer, NOT the handle a.

  Code that used a bare `var t: Str;` as a stand-in handle (6.6.16's pun `var t: Str; t = a;`) should declare the
  handle instead: `var t = a;` or `var t: Str = a;`.
- Stops compiling, for a frame's bare `var t: Str;`: `return t;` from a fn returning `Str`, and `G = t`, `w.s = t`,
  `W { t, .. }`, `*ps = t` ("… its header lives in this frame and would dangle (return a handle: str_new(data, len))").
  They returned or stored the first word. Return or store a handle, `str_new(t.data, t.len)`, or declare t as the
  handle (`var t = a;`).

**ST-13 — the stdlib's `Str` methods take a `Str` operand; `var p: *Str = t;` takes the header (D18 (c), the user 2026-10-16)**
- Changes what it computes:
  - `h.eq("lit")`, `h.contains("lit")`, `h.starts_with("lit")`, `h.ends_with("lit")` now answer what
    `str_eq(h, "lit")` etc. answer. They read the literal's own bytes as a header, so the answer depended on the bytes
    after the literal (usually 0).
  - `h.cat("lit")` appends the literal (it appended whatever those bytes read as).
  - With an inline `Str` t, `h.eq(t)` / `h.cat(t)` / `h.contains(t)` / `h.starts_with(t)` / `h.ends_with(t)` read t
    (they read its data word as a header).

  `lib/str.cyr` types those five methods' operand `Str`. A `Str` handle argument builds byte-identical.
- Changes what it computes: `var p: *Str = t;` of an inline `Str` now ALIASES t's header (`p.len = 3` writes `t.len`).
  It held t's data word. The same holds for an inline `Str` global, a capture and a top-level declaration.
  `var p: *Str = gt;` no longer warns "assigning non-pointer to typed pointer".
- Unchanged by the decision: fncallN, callptr, `vec_push`, a tuple element and an untyped if-expression branch still
  take an inline `Str`'s first word (pass `&t` there). A cstring VARIABLE passed to these methods is still its word:
  wrap it with `str_from(cs)`.

**ST-14 — a top-level `var H: Str = gt;` binds to the inline global (D21 (a), the user 2026-10-16)**
- Changes what it computes: a top-level `var H: Str = gt;` from an inline `Str` global now ALIASES gt (an 8-byte
  handle to gt's static header), in the declaration zone and after the first statement. A write through H
  (`H.len = n`, `H.data = p`) changes gt, and gt's later writes show in H. It was an independent 16-byte copy. To keep
  a copy, give H its own literal: `var H: Str = Str { "..", n };`. The zone's `var P: *Str = gt;` takes gt's address
  (it stored the data word, with a warning).
- Unchanged: a gt declared below H is still refused. The untyped `var H = gt;` keeps gt's first word (ST-15, D22 (b)):
  annotate it.

Nothing to migrate in five bites:
- **ST-1** (D: none). Under the opt-in `CYRIUS_IR=3`, a float literal no longer corrupts the code around it; the default
  pipeline is byte-identical.
- **ST-2, ST-3** (D: none). A top-level `mk().n = 5;` / `mkp().p[0] = 5;` / `o.mk().n = 5;` is one error instead of
  two; it never compiled.
- **ST-4** (6.7.13's D8 (a)). A for step `gp().n += 1` through a `: *T` call stores; refused code now compiles.
- **ST-15** (D22 (b), the user 2026-10-16). An untyped top-level `var H = gt;` keeps the word, documented; nothing
  changes.
- **ST-16** (D23 (b), the user 2026-10-16). A handle bound to a frame's inline `Str` dangles as `&t` does, documented.
  Never return or store one; return `str_new(t.data, t.len)`.

The review fixes ST-7r and ST-7r2 change the guide only.

#### Language — receives, closures and multi-value (the receives + multi-value lane)

The decisions are the user's at the 6.7.14 open (2026-10-16: D24 – D30, D42 – D46 and D53, each as recommended). An id
written "6.7.13's Dn" or "6.7.11's Dn" is that release's open's; 6.7.11's D24 (a struct over 8 B into an annotation
that names no struct is refused) is not 6.7.14's D24 (a `.field` after parentheses). Each block names its CHANGELOG
[6.7.14] bite.

**RC-1 — in a closure, a write to a captured name is refused even when a global has the name (no decision needed: 6.7.11's rule, "a captured name is not assignable in a closure")**
- Stops compiling: in a closure, an assignment to a name the closure captures from its enclosing fn — `y = ..`,
  `y += ..` / `-=` / any `OP=`, a classic-`for` init or step, a multi-value target (`a, y = f();`), in a nested closure
  too — when a top-level global has the same name: "'y' is captured by value; a captured name is not assignable in a
  closure — copy it into a local (`var y_l = y;`)". It compiled and silently wrote the GLOBAL while the closure's reads
  saw the capture (`y += d; return y;` returned the capture and moved the global). Copy the capture into a local
  (`var y_l = y; y_l += d;`), or give the global a name no enclosing local shadows.
- Unchanged: a closure that sees no enclosing local of that name writes the global; a closure-local `var y` writes its
  local.

**RC-5 — in a fn, `var s = (mks());` with a `: Str` call is a `Str` (no decision needed: the wrap is transparent, guide § Parentheses)**
- Behaves differently: an untyped `var s = (f());` (any number of wrapping parentheses) in a fn, with `f` declared
  `: Str`, is now a `Str`, as `var s = f();` always was. An overloaded call on it (`println(s)`, any `base` /
  `base_str` pair) now reaches the `_str` sibling — `println(s)` prints the string, where it printed the header's bytes
  through the cstring overload — and `s.len()` / `s.field` compile. Code that relied on the wrapped call being a plain
  word (passing it to a `: cstring` base) gets the `Str` overload; pass `s.data` explicitly if that is what you meant.
- Unchanged: at top level `var s = (mks());` is still a word (filed) — drop the parentheses there.

**RC-6 — `var a = (f()) * 2.0;` with a `: f64` call is an f64 (no decision needed)**
- Changes what it computes: an untyped `var a = (f()) op ...;` — any wrapping parentheses around a leading `: f64` call,
  followed by arithmetic — is now an f64 local, as `var a = f() op ...;` is: `a + 1.5`, `-a`, `a * b` are float
  operations where they were integer operations on the bits, and the "integer arithmetic with an f64 right operand"
  warning that came with them is gone. If you relied on the bits, annotate the local `: i64`.
- Unchanged: a comparison, `&&` / `||` and `& | ^ % << >>` after the wrap still give an integer.

**RC-9 — a struct result over 8 B assigned to a scalar variable is refused (D27 (a), the user 2026-10-16; with RC-9r)**
- Stops compiling: an assignment `x = mkp();` / `x = s.m(..);` / `x = a + b;` (an overloaded operator) /
  `x = fncallN(&f, ..);` / `x = callptr(&f, ..);` — the call returning a struct over 8 bytes, not `Str` — into a local,
  a parameter or a global declared with an annotation that names no struct (`: i64`, `: u8`, `: f64`, `: f32`, `: i32`,
  `: cstring`, an enum, `u128`), in a fn or at top level, in a classic-for init or step, in parentheses, and into a local
  declared in a classic `for` header and assigned in the loop's body: "cannot assign 'x: i64' from 'mkp', which returns
  the struct 'Q' - declare 'x: Q' or bind a field". It compiled and stored the struct's first word, narrowed to the
  destination's width (a `u8` held 77 of 333). Declare the destination with the struct type, or bind the field you
  meant (`x = mkp().a;`).
- Unchanged: a struct of 8 bytes or less and a `Str` keep their word; a `: bool` keeps its own refusal; an untyped
  destination (`var x = 0; x = mkp();`) and a `*T` destination still keep the first word (filed, the user's questions)
  — bind a field there too.

**RC-10 — a known `&f` callee's `: f64` / `: *T` result is the direct call's (D25 (a) and D26 (a), the user 2026-10-16)**
- Changes what it computes: `fncallN(&f, ..)` / `callptr(&f, ..)` with `f` declared `: f64` is an f64 whatever its
  last argument: arithmetic on it is float arithmetic (it was integer arithmetic on the bits, under "integer arithmetic
  with an f64 right operand", unless the last argument was an f64), and an untyped `var a = fncall0(&f);` binds an f64.
- Changes what it computes: with `f` declared `: *T`, `fncall0(&f) + n` steps n elements of T, as `f() + n` does (it
  stepped n bytes), and assigning it to a `*T` no longer warns. For byte arithmetic, copy the result untyped first
  (`var q = fncall0(&f); q + n` steps n bytes, as `var q = f();` does).
- Unchanged: a callee held in a variable (`fncall0(fp)`) is still a word.

**RC-12 — 6.7.13's D14 at top level: a struct over 8 B into a `*T` global is refused (D28 (a), the user 2026-10-16)**
- Stops compiling: at top level, a global annotated `*T` (any T: `*P2`, `*i64`, `*u8`, `**T`) and initialised from a
  struct result over 8 bytes — a free call, a method, an overloaded operator, `fncallN(&f, ..)` / `callptr(&f, ..)`,
  wrapped or generic — in the declaration zone or after the first statement: "cannot initialise 'X: *P2' from 'mkp',
  which returns the struct 'P2' - declare 'X: P2' and take `&X`". After the first statement it compiled with a warning
  and held the struct's first word as an address (a fault at the first field read); a method or operator result did the
  same in the zone. Declare the struct (a struct global, or `var X: P2 = ..` in a fn) and take its address.
- Unchanged: a struct of 8 bytes or less and a `Str` keep their word and the warning.

**RC-14 — a top-level untyped receive of a whole call binds the struct (D29 (a) and D30 (a), the user 2026-10-16)**
- Stops compiling: an untyped top-level global initialised from one whole call (wrapped or not) of a fn returning a
  struct of 9 – 16 bytes — `var x = mk2(30);` — is refused as `var x: P2 = mk2(30);` is: "'mk2' returns a struct by
  value, and a struct result needs storage in a fn's frame — call it inside a fn". It compiled and held the struct's
  first word. Declare it in a fn, or bind the field you meant (`var x = mk2(30).a;`).
- Behaves differently: such a global from a struct of 8 bytes or less is now that struct: `x.a` compiles, and `x + n` /
  `x - n` dispatch the struct's operator fn (`P1_add`, …) and are refused when there is none ("undefined function
  'P1_add'", then "refusing to emit binary"), where they did integer arithmetic on the word. A bare `x` as a value is
  still its word. Write `var x: i64 = mk1(30);` to keep an integer.
- Unchanged: a `Str` call, a method / operator / known `&f` result and a name keep the word at top level.

**RC-15 — a fn whose only pair route is `?` is a pair above its definition too (no decision needed: definition order must not change the verdict)**
- Stops compiling: a single bind (`var v = f(x);`, `x = f(x);`, a store) of a fn DEFINED BELOW it whose only `: stack`
  pair route is `f(..)?` — a free fn, an impl method, an inherited trait default — is refused "a `: stack` enum returns
  two values — bind both: `var tag, val = f();`", as it already was with the fn defined above. It compiled and bound the
  tag. Bind both (`var t, v = f(x);`) or propagate with `?`.
- Stops compiling: a `dyn T` formed above an impl whose slot method's only pair route is `?`, where T declares one
  value: "cannot form dyn T from P - its method 'm' … returns a `: stack` pair". It compiled and the call through the
  dyn read the tag as the value.
- Behaves differently: `f(x)?` above such a fn propagates the pair; it took the boxed `?` and crashed (139 on x86_64 /
  aarch64, a cx guest error, exit 5 on Windows).

**RC-16 — `ret2(a, b)` counts as two values (D42, the user 2026-10-16)**
- Stops compiling: three names or a 3-tuple from a fn left only through `ret2(..);`, `return ret2(..);` and
  `return (a, b);` — a final `ret2(..);`, or an if / elif / else whose every arm ends in one (an if / else of
  `return (a, b);` arms with no `ret2` included) — "multi-value destructure binds 3 names, but 'g2' returns 2 values" /
  "cannot capture 'g2' into tuple (i64, i64, i64) - it returns 2 values". The third value read a stale register. Bind
  two names.
- Stops compiling: such a fn into a by-value struct parameter or a struct variable ("a multi-value call 'g2' is not a
  struct 'P' argument"; it crashed), and `return g2(..);` from a fn declared `: (T1, T2, T3)` ("'f' returns 3 values";
  its third value was stale).
- Unchanged: two names (`var q, r = divmod_old(..);`), one name and `rethi()`, and a `ret2` inside an expression.

**RC-17 — `ret2(a, b);` in a vector-returning fn is refused (D43, the user 2026-10-16)**
- Stops compiling: `ret2(a, b);` as a statement in a fn declared to return a vector type (`: f64v2`, `f64v4`, `f32v4`,
  `i32v4`, …): "a vector-returning fn carries its result in a fixed register pair, so `return` takes a local of that
  vector type or a call to a fn declared to return the same one — got `ret2`". It returned no vector (the caller read
  the vector registers' leftovers). Store the lanes into a local of the vector type and `return` it.
- Unchanged: a `ret2` in a closure, or in an `#inline` fn replayed in the vector fn, is that fn's own.

**RC-18 — an integer literal or a scalar-declared multi-value call into a tuple parameter is refused (D44, the user 2026-10-16)**
- Stops compiling: an integer literal passed to a tuple parameter (`take(5)`, `take((5))`, a method's or an `#inline`
  callee's tuple parameter): "cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple";
  and a multi-value call of a fn declared ONE scalar (`fn g2(a): i64 { return (a, a + 1); }`, its `ret2` form, a
  method, an overloaded operator, a `: f64`) passed to one: "a multi-value call 'g2' is not a tuple argument - bind it
  first". Both crashed (the callee read through the value as the tuple's address). Bind the values first:
  `var t: (i64, i64) = g2(3); take(t);`.
- Unchanged: an untyped word is the tuple's address (`take(&t)`, a variable holding `&t`, a `: i64` call returning an
  address), and a one-value call is passed as that word (`take(one(3))` still compiles — and crashes unless it returns
  an address).

**RC-21 — a store whose whole value is parenthesised and starts with a pair call is refused (D46, the user 2026-10-16)**
- Stops compiling: a single bind or store whose whole value is parenthesised and starts with a `: stack` pair call —
  `var v = (f(x) + 1);`, `h.n = ((f(x) * 2));`, `x = (f(x) * 2);`, `P { (f(x) + 1), 3 }`, `((f(x)) + 1)`, in both
  top-level zones, a for step, `x +=`, an element, `*p`, `store64`, a struct- or tuple-literal element and an
  if-expression branch: "a `: stack` enum returns two values — bind both: `var tag, val = f();`", as the unwrapped
  spelling is. It kept the tag and dropped the payload. Bind both (`var t, v = f(x);`) or consume the pair with `?`
  (`(f(x)? + 1)`).
- Unchanged: `x = (3 + f(x));` keeps the tag, as `x = 3 + f(x);` does; `(f(x) + 1) * 2` is not a wrap around the whole
  value.

**No block — refused source now compiles, or a diagnostic changes (nothing that compiled does anything else):**
- **RC-2:** `var x: Foo = b.mk();` with an unknown `Foo` is one error ("unknown type"), not two.
- **RC-3:** a top-level `.field` / `.m()` on a method result over 16 B is one error per line, not two.
- **RC-4:** `|m: i64|` is refused once, "a closure's parameters are untyped — drop `: T`", at the `:`; it was "expected
  unknown, got ':'" and cascades. A tool that matched the old text must match the new one.
- **RC-7:** a struct name in parentheses as a nested-struct literal element (`HE { 7, (q0), 8 }`, `((q0))`, a global
  `(G)`) is the element; it was "unexpected '}'".
- **RC-8:** `callptr(&gp, 5).b = 40;` / `+= 40` as statements store through a `: *T` result, as the `fncall1` spelling
  does; they were "expected ';', got '='". A by-value callee is refused by name.
- **RC-11 (D24 (a), the user 2026-10-16):** `(s).a`, `(p).a`, `(*p).a`, `(s).m()`, `(mk1()).a`, a method / operator /
  known `&f` result, chains, and the statements `(s).m();` / `(s).a;` / `(mk1()).a;` read through the parentheses; they
  were "expected ';', got '.'" (a statement "unexpected '('"). `(x + 1).a` and a store `(s).a = v;` are refused by name.
  Parentheses-avoidance workarounds (`var t = mk(); t.a`) may be dropped.
- **RC-13 (D53, the user 2026-10-16):** a string literal alone into a `*u8` / `*i8` (`var s: *u8 = "abc";`,
  `t = "xyz";`, a parameter, a global, the declaration zone) no longer warns "assigning non-pointer to typed pointer",
  and a `p = &a[1];` refusal carries no warning beside it. A string literal into any other `*T`, and a string
  expression (`"abc" + 1`), still warn.
- **RC-19:** `var t: (i64, i64) = callptr(fp, ..);`, `t = callptr(..);` and a top-level `G = callptr(..);` capture
  every value, as `fncall1(fp, ..)` does; they were "cannot initialize tuple 't' with a value that is not a tuple".
- **RC-20 (D45, the user 2026-10-16):** `var a, b = (f(7));`, `a, b = ((f()));`, a for step, both top-level zones and
  `var t: (i64, i64) = (two(3));` compile as the unwrapped spelling; they were "multi-value destructure needs a call on
  the right-hand side" / "cannot initialize tuple". One refusal moves: `var t: (i64, i64) = (sf(7));` of a `: stack`
  pair call was "bind both" and now captures the tag and payload, as the unwrapped capture does.
- **RC-22:** a closure's own `?` in an expression body (`var f = |a| parse(a)?;`) stays the closure's — a regression
  of RC-15 inside the release, fixed before it; no released compiler had it.

#### Stdlib — the cx guest contract, TLS, epoll, ws tests, distlib, patra 1.16.4 (the stdlib lane)

Each block names its CHANGELOG [6.7.14] bite. D55 is the user's (2026-10-16). "6.7.12's Dn" is that open's (the user,
2026-10-15). LIB-1 and LIB-5 – LIB-7 change the cx target only.

**LIB-1 — cx: a conditional over more than 128 KiB of bytecode lands where the source says (no decision: fixed to what the source says)**
- What it computes: a cx program with an `if` / loop body, an `elif` / `else` arm, a `switch` case or a `match` arm
  longer than ~128 KiB of bytecode (about 1,300 statements) now runs its source on cxvm. It trapped (`cxvm: jump to a
  negative code offset`) or ran the wrong instructions.
- Size: every conditional is 4 B longer (the inverted short branch over a 24-bit `jmp`), so a `.cyx` grows ~1.5–2 %
  (yukti's crossos `.cyx` +1.6 %).
- What can stop compiling: a cx program already within ~2 % of the 4 MiB code region can now meet the existing by-name
  refusal, `error: cx bytecode exceeds the cx code region (4194304 B): …`.
- **Migrate:**
  - Nothing to change for a program that compiles.
  - Build a program that now meets the code-region refusal for a native target.
  - A `.cyx` from an older cycc_cx still runs on the 6.7.14 cxvm, and the reverse (no ISA change).

**LIB-2 — a write to `TLS_SHA256_CTX_LEN` is inert (6.7.12's D16, the user 2026-10-15, applied to a 15th name)**
- What it computes: a program that WRITES `TLS_SHA256_CTX_LEN` now sees the TLS stack ignore the write.
  - A raised value crashed inside `tls_native_transcript_digest`: SIGSEGV on Linux and macOS, an access violation on
    Windows.
  - A lowered value under-allocated the SHA-256 ctx, which then overran.
- Unchanged: reading it still gives 144, and a write still reads back (it stays a `var`).
- **Migrate:**
  - Drop any write to it: the size is sigil's SHA-256 ctx, 144 bytes, and it is not a knob.
  - The public-constants arc will make it a `const` with the other fourteen bounds. A program that writes it, takes
    `&TLS_SHA256_CTX_LEN` or declares its own `var TLS_SHA256_CTX_LEN` will stop compiling then, at that pin bump.

**LIB-4 — `epoll_event_set(ev, events, data)`, a new public fn in the x86_64 Linux, aarch64 Linux and x86-macOS peers (no decision: additive)**
- New: it fills an epoll_event in a buffer the caller owns, at least `EPOLL_EVENT_SIZE` bytes (a stack `var ev[16]`).
  The events go at 0 and the data at the peer's offset (@4 on x86_64 and x86-macOS, @8 on aarch64). It returns `ev`
  for `sys_epoll_ctl`. `epoll_event_new` is now `alloc(16)` plus this writer.
- What it computes: a program that defines its OWN `epoll_event_set` now gets "duplicate fn 'epoll_event_set' (last
  definition wins; first defined in lib/syscalls_….cyr)".
  - The last definition is the one every caller runs, the stdlib's `epoll_event_new` and `lib/async.cyr`'s three
    registrations included.
  - Measured: a program's `fn epoll_event_set(a, b, c): i64 { return 77; }` after the include makes
    `epoll_event_new(1, 5)` return 77.
- **Migrate:**
  - Rename a private `epoll_event_set`, or drop it for the stdlib's, which has the same layout as `epoll_event_new`.
  - Hand-gated `#ifdef CYRIUS_ARCH_AARCH64` `store64(&ev + 8, …)` / `+ 4` writes keep working.
    `epoll_event_set(&ev, mask, data)` replaces them.

**LIB-5 — cx: `mmap_stack` answers -1 and `fl_alloc` answers 0 (6.7.12's D13 extended; D55, the user 2026-10-16, names `mmap_stack` failing on cx)**
- What it computes, on cx only:
  - `mmap_stack(size)` (lib/thread.cyr) returns -1. It returned a positive HOST address that no guest load or store can
    reach.
  - `fl_alloc` (lib/freelist.cyr) returns 0, its documented failure. The program used to be killed by `cxvm: guest
    address out of range: <host address>` at the first store.
- Native, aarch64, PE and agnos builds are byte-identical.
- **Migrate:**
  - Check `mmap_stack(..) < 0` and `fl_alloc(..) == 0`, as the native targets already require.
  - A freelist user on cx takes its allocation-failure path. Use `alloc()` on cx, which serves the guest heap (LIB-7).

**LIB-6 — cx: cxvm answers -38 for a syscall it does not translate, serve or list as scalar-only (D55, the user 2026-10-16)**
- What it computes, on cx only: a guest syscall outside cxvm's lists answers -ENOSYS (-38) without reaching the host.
  - The lists:
    - translated: read / write / open, with lseek, close and exit at their own arity;
    - served: getrandom, clock_gettime, and brk in guest space (LIB-7);
    - scalar-only (`_cx_sys_scalar`): exit_group, fork, dup / dup2, getpid / getppid, kill, sched_yield, fsync /
      fdatasync, flock, ftruncate, fchmod / fchown, getuid / getgid / geteuid / getegid, socket, listen, unshare,
      timerfd_create, epoll_create1, and fcntl's scalar commands (F_DUPFD, F_GETFD, F_SETFD, F_GETFL, F_SETFL,
      F_DUPFD_CLOEXEC).
  - Before, those calls went to the host with the guest's raw registers. Most pointer calls answered -14 (since
    6.6.12).
  - A call whose pointer was null or happened to map got a REAL answer, and now gets -38:
    - `wait4(pid, 0, …)`;
    - `accept(fd, 0, 0)`;
    - `sys_ioctl` on a bad fd;
    - `getrlimit`.
  - Each of these now answers -38: stat, statfs, munmap, mprotect, mmap, nanosleep, mkdir (no directory is made),
    uname, wait4, futex, the address-taking socket calls (accept / accept4, getpeername, setsockopt, …), ioctl and
    `fcntl(F_GETLK)`.
  - A guest address inside cxvm's own Linux image (0x400000 / 0x600000) no longer reaches cxvm: `cyr_munmap(0x400000,
    …)` answers -38 (it killed cxvm), and `syscall(5, 1, 0x600100)` answers -38 (it wrote a `struct stat` over cxvm's
    globals).
  - On the Macs, a refused number answers -38 where it SIGSYS-killed cxvm.
  - Windows answers as before: its pass-through already answered -38.
- **Migrate:**
  - Check the result of every syscall a cx program issues. A wrapper outside the lists fails honestly; nothing it asks
    for is done.
  - Read `_cx_sys_scalar` in `programs/cxvm.cyr` and the cx guest contract in `docs/platform-status.md`.
  - Build the program for a native target, or file the call for translation (one call at a time, when a cx program
    needs it — D55's own note).
- ⚠ On aarch64 Linux and macOS hosts, a translated or scalar-listed call can still run a DIFFERENT host call: cxvm hands
  the guest's x86 numbers to the host's renumbering. On pi, lseek runs getxattr and fork runs close. This is filed for
  6.7.15 (`2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md`), and it is the same as in 6.7.13.

**LIB-7 — cx: `alloc()` bumps over the guest break cxvm serves; the 128 KB static heap is gone (no decision: a cap)**
- What it computes, on cx only:
  - An allocating program gets the guest's free memory, up to ~7 MiB less its image. It got 128 KB.
  - Its `.cyx` is ~128 KB smaller: an `alloc(16)` program goes 151,546 → 22,494 B.
  - A guest's raw `brk(addr)` answers a GUEST address in cxvm's segment. Through 6.7.13 it went to the host and answered
    the host's break.
  - The break moves while it stays 1 MiB below both the live guest sp and the segment's top; memory it grants reads
    zero.
  - The guest stack traps (`cxvm: guest stack overflow`) at the break, not at the image end.
- Changed text: exhaustion now prints `alloc: cx heap exhausted at <N> B (the guest break cannot grow by <M> B more)`
  and exits 1. It printed `alloc: cx static heap exhausted (128 KB)`.
- Removed (private): `_cx_heap_buf`, `enum CxHeap` / `_CX_HEAP_SLOTS`.
- ⚠ cycc_cx and cxvm ship together. A `.cyx` that allocates, built by the 6.7.14 cycc_cx, needs the 6.7.14 cxvm.
  - On a 6.7.13 or older cxvm it stops at its first allocation with `cxvm: guest address out of range: <host address>
    at pc <N>`, exit 1. The old cxvm hands brk to the host, and the host's break is no guest address.
  - A cxvm that answers brk -38 makes `alloc_init` say `alloc: this cxvm does not serve brk (12): a .cyx from cycc_cx
    6.7.14 or later needs cxvm 6.7.14 or later`.
  - A `.cyx` built by an older cycc_cx (static heap) still runs on the 6.7.14 cxvm.
- **Migrate:**
  - Run a `.cyx` on the cxvm of the release whose cycc_cx built it. If a `.cyx` must run on an older cxvm, build it with
    that release's cycc_cx.
  - Anything that greps for the old message must read `alloc: cx heap exhausted at`.
  - A program that needs more than ~7 MiB less its image is refused by name: build it for a native target.

**LIB-8 — native TLS: the client refuses repeated extensions, padded extension blocks, a lenient ALPN answer, and an unwalked 1.2 ServerHello (no decision: RFC MUSTs)**
- What it computes: the native TLS client now fails the handshake, with an alert, against a server that does any of
  these:
  - carries an extension type twice in a ServerHello or EncryptedExtensions block (illegal_parameter);
  - leaves bytes after a 1.3 ServerHello's or EncryptedExtensions' extension block (decode_error);
  - answers ALPN with anything but exactly one non-empty name filling the extension (decode_error), or with a name the
    client did not offer (illegal_parameter);
  - (TLS 1.2) sends an extension the client's ClientHello did not carry, ALPN when none was offered included
    (unsupported_extension);
  - (TLS 1.2) sends a session id over 32 bytes (decode_error).

  Each of these connected through 6.7.13, and the first ALPN name of two was selected.
- The 1.2 client now SENDS the alert its ServerHello refusal recorded (`tls_native_connect_12`); it sent none. The
  TLS_ERR_* codes are unchanged.
- An API precondition: `tls_native_client_parse_server_hello_12(ctx, …)` checks the server's extensions against the 1.2
  ClientHello built on that ctx. Called directly on a ctx that never built one, every extension is
  unsupported_extension. `tls_native_connect_12` always builds it.
- **Migrate:**
  - Nothing for a program that connects through `tls_native_connect` / sandhi to a conforming server.
  - A peer that now fails was sending out-of-contract messages; fix the peer.
  - A test or tool that calls `tls_native_client_parse_server_hello_12` directly must first call
    `tls_native_12_build_client_hello(ctx, buf, len)` on the same ctx, with the ALPN offer set
    (`tls_native_set_alpn`) if the ServerHello under test answers ALPN.

**LIB-9 — distlib reads the stdlib the manifest pins, under `CYRIUS_RESOLVED=1` (no decision: a tooling defect)**
- What it computes: nothing for a consumer, and nothing with the pin's own CLI (the default re-exec).
- A fold producer running `cyrius distlib` under `CYRIUS_RESOLVED=1` with a `cyrius =` pin other than the CLI's version
  gets the sidecar verify and the bundle self-check compiled against `versions/<pin>/lib`. A leaf the project's `./lib`
  vendors still resolves from `./lib`, and a `--locked` overlay is laid over the pin.
  - A home holding only the pinned slot now succeeds. It failed with `cannot open include file: lib/<leaf>.cyr`, rc 1.
  - A home holding both slots now verifies against the pin. It verified against the CLI's own slot, so a bundle that
    compiles only against the CLI's slot is now refused, rc 1, naming the pinned file's line.
- **Migrate:**
  - Regenerate a bundle whose sidecar was produced this way (`cyrius distlib`). Every fold's bundle regenerated
    byte-identical in the lane's control.
  - If the pinned slot refuses the bundle, the bundle needs that pin's stdlib: fix the source or move the pin.

No block for LIB-3 (tests only), LIB-7r (inside this release: LIB-7's break is bounded by the segment as well as the
sp, as LIB-7 states it) or LIB-10 (patra 1.16.4 changes its own suite only, and `lib/patra.cyr`'s code is byte-identical
to 1.16.3's — its `# Version:` line moves; nothing to change in a caller).

#### Language — vector values (the vectors lane)

The decisions are the user's at the 6.7.14 open (2026-10-16): D31 – D41, each A, and D51 (the Windows refusal kept so
that every target gives the same answer). Ids from other releases are written with their release:
- **6.7.13's** (the user, 2026-10-15): D29, D30, D31, D33, D34. Its D31 – D34 are other decisions than 6.7.14's of the
  same numbers.
- **6.7.12's:** D27 (B: a vector value into a `*V` parameter is an address).

Each block names its CHANGELOG [6.7.14] bite.

**VC-2 — Windows checks a value-form vector argument as x86_64 / aarch64 / cx do (no decision: the other targets refuse the same source by name; 6.7.13's D30 and 6.7.14's D51 keep one answer on every target)**
- Stops compiling, Windows only (x86_64, aarch64 and cx already refused each, with the same words). These are arguments
  to a value-form vector parameter (`fn lanes(x: f64v2)`, `v: f32v4`, an integer vector):
  - A vector local of another type into a 16-byte parameter: an f64v4 or f32v8 local into `x: f64v2` ("value-form SIMD
    arg must be a 16-byte vector"), or an f64v2 local into `v: f32v4` ("value-form SIMD arg type mismatch (callee
    expects f32v4)"). The callee read whatever bytes the address held: 2 / 3 / 0 in the filed probes.
  - A struct value: a local, a by-value parameter, a global, a call result or `*ps`. The struct's words were read as
    the lanes (`lanesn(p)`: 42).
  - An expression led by a name, such as `lanes(q + 1)` or `lanes(w + 1)`. Its value was taken as the vector's address,
    so it faulted (exit 5).
- Migrate: pass a vector local of the parameter's type (or a call declared to return it). The program computed garbage
  on Windows, so there is no value to preserve.

**VC-6 — `lanes(&w)` into a value-form vector parameter is refused on Windows too (D33, the user 2026-10-16)**
- Stops compiling, Windows only: `f(&w)` passed to a value-form vector parameter.
  - x86_64, aarch64 and cx already refused it: "a value-form vector argument to 'lanes' is .. - got `&w`".
  - Windows ran it (42), because its by-address ABI copied the vector the address named.
  - Migrate: write `f(w)`. `&` converts into a POINTER parameter only (`p: *f64v2`).
- Stops compiling, Windows only: a vector receive of your own value-form fn written with addresses, when it has no
  `_ptr` sibling.
  - For example `var c: f64v2 = vadd(&a, &b);`, with `fn vadd(a: f64v2, b: f64v2): f64v2` and no `vadd_ptr`.
  - It is now refused with x86_64's two lines.
  - Migrate: pass the locals (`vadd(a, b)`), or give the fn a `vadd_ptr(a: *f64v2, b: *f64v2): f64v2` form.
- Behaves differently, with the same value: on Windows a receive written `f64v2_add(&a, &b)` now calls
  `f64v2_add_ptr`, as on every other target. Before, it called the value form with the addresses. The receives are a
  declaration's initialiser, an assignment, a wrapped initialiser, a call temporary and a `return` from a vector fn. No
  change needed.

**VC-10 — every `*V` dereference into a pointer of another kind or a small by-value struct is refused by name (no new decision: 6.7.13's D31, the user 2026-10-15)**
- Stops compiling, every target. Each faulted: 139 on x86_64 and aarch64, a cx guest fault, exit 5 on Windows.
  - The arguments are a `*V` dereference spelled other than `*name` of a local, with `pb` a `*f64v2`: `ri(**ppb)`,
    `ri(*gp(pb))`, `ri(*h.pv)`, `ri(*GPV)`, `ri(*(pb + 0))` and `ri(*&b)`.
  - They were passed to a `*i64` / `*u8` / `**T` parameter or a by-value struct of 8 B or less — wrapped, in a closure,
    a method or an `#inline` fn, or at top level.
  - The message is "cannot pass '*ppb' to a parameter that is not a pointer to its vector type in a call to 'ri'", or
    ".. to a by-value struct parameter .. - a vector is not a struct".
- Migrate: pass the pointer the callee should get. `*ppb` itself is the `*f64v2`; `&b` is the vector's address as a
  byte pointer. Or give the callee a `*V` parameter.
- Unchanged: `ri(*ppi)` of a `**i64` and `ri(*pps)` of a `**Pt` still pass their word.

**VC-12 — a struct-typed field into a `*V` parameter is refused by name (D34, the user 2026-10-16)**
- Stops compiling, every target: a struct-typed field passed to a `*V` parameter, `rd(w.s)` with `s: Pt` and `fn rd(p:
  *f64v2)`.
  - The forms are wrapped, through a `*W`, a global's, a capture's or a nested field; into a method's, a generic's, an
    `#inline` fn's or an operator fn's `*V` parameter; or at top level.
  - Each ran: the callee read the field's struct bytes as the vector (42).
  - The message is "cannot pass 's' to a parameter that is a pointer to a vector type in a call to 'rd'".
- Migrate: if the bytes are meant, pass a plain pointer: `rd(&w)`, `rd(&w + offset)`, or a `*T` through which the field
  is reached. `&w.s` is no spelling ("the address of a field is not taken", 6.7.13's D3).

**VC-13 — `return *p;` and an untyped `var v = *p;` with `p: *V` are the vector (D35, D36, the user 2026-10-16)**
- Behaves differently: an unannotated `var v = *p;` with `p: *f64v2` (or any `*V`) is now a vector local copied through
  `p`. It was one untyped word, lane 0, and `&v + 8` read the next stack slot.
  - `lanes(v)` now passes it, where it was refused "must be a 16-byte vector".
  - `v + 1` is the vector operator.
  - `load64(&v)` is lane 0, and `load64(&v + 8)` lane 1.
- Migrate: code that meant the word annotates it, `var x: i64 = load64(p);` (or `var x: i64 = *pi;` through a `*i64`).
  A `*pi` of no vector binds one word, as before.
- Starts compiling (no change needed): `return *p;` from a vector fn — also `(*p)`, `**pp`, `*gp(p)`, `*h.pv` and
  `*&w`. It was refused "got `this expression`".

**VC-14 — a method declared to return a vector is the vector where a by-name call is (D37, D38, D39, the user 2026-10-16)**
- Behaves differently: an unannotated `var v = s.mv();`, where `mv` is declared `: f64v2` (any vector; a generic method
  too), is now a vector local. It was one word: 1 on x86_64 and aarch64, 155 on cx and 195 on Windows where 161 is
  right. Code that used it as an integer meets the vector rules. For lane 0's word write `var x: i64 = load64(&v);`.
- Stops compiling, every target: a method declared to return a vector, stored into a scalar destination. Each stored a
  word that differed per target (0 on x86_64 and aarch64, 41 on cx and Windows) or faulted (a struct destination, 139).
  - The destinations are `var x: i64 = s.mv();`, `x = s.mv();` (a for step too), a struct local (`var x: Pt =
    s.mv();`), an `f64` local and a pointer local.
  - The messages are "vector return type does not match the declared type" / ".. the assigned variable".
  - Migrate: receive the vector (`var v: f64v2 = s.mv();`) and read a lane with `load64(&v)`.
  - ⚠ The by-name `var x: f64 = mkv(..);` still compiles. The method is refused there.
- Starts compiling (no change needed): `return s.mv();` from a fn declared to return that vector. It was refused "got
  `s`".

**VC-15 — a generic's `pp: **T` called with no `<..>` binds T from a `**S` argument (D40, the user 2026-10-16)**
- Behaves differently: an implicit call of a generic whose ONLY carrier of `T` is a parameter declared exactly `pp: **T`
  now runs the `S` instance, where it ran the i64 base. That is, no `x: T` / `p: *T` parameter and no generic struct
  carries T.
  - It applies when the call is passed a `**S` — a local, parameter, capture, global, field, a `: **S` call — or `&p` /
    `&G` of a `*S`.
  - `sizeof(T)` is sizeof(S), `*pp + n` steps `n` elements of S, `take(**pp)` gets the struct, and a `: T` result is
    an S.
  - Through 6.7.13 the step was 8 and `take(**pp)` faulted.
- Migrate: code that relied on the i64 base spells it `st<i64>(pps)`.
- Unchanged: calls with a direct or struct carrier bind as before. A `*S`, a `**i32`, a `***S`, `(pps)` and `pps + 0`
  still bind nothing (i64). ⚠ So `tg((pps))` still faults where `tg(pps)` is right — pass the argument unwrapped.

**VC-16 — a program's own struct named like a vector type is that struct everywhere (D41, the user 2026-10-16)**
- Starts compiling: a by-value parameter of a program's own `struct f32v4 { .. }` (any vector name: `f64v2`, `f64v4`,
  `f32v8`, `i32v4`, `u8v16`, …), or of a union of that name. It is passed as any struct of its size.
  - Through 6.7.13 such a parameter was the SIMD vector, refused "SIMD vector has no named fields".
  - `struct f32v8` as a parameter compiled through 6.7.12 and compiles again.
- Behaves differently: in a program that declares such a struct, the name is the struct everywhere, `lib/simd.cyr`'s
  functions of that name included. A program that also used `lib/simd.cyr`'s vector of that name meets its struct in
  the stdlib's signatures. Migrate: rename the struct (`struct F32x3 { .. }`) to keep the vector.
- ⚠ A struct of that kind over 8 B, declared BELOW a fn that takes it by value, with a call ABOVE that fn's definition,
  was refused with a vector message. It now compiles and faults, as any struct name does there. That is the filed
  issues/archived/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md. Migrate: declare the struct above the
  fn that takes it.

**No block** — newly compiling shapes, a crash fixed into the right answer, or a message on code that never compiled:
- **VC-1:** 127 or more distinct `**S` pointees in one unit compile again. They were refused "(max 126)" in 6.7.13; the
  cap is 16383.
- **VC-3:** `lanes((v))` and `lanes((mkv(4, 2)))` into a value-form vector parameter compile on x86_64, aarch64 and cx,
  as they did on Windows.
- **VC-4 (D31, the user 2026-10-16):** a closure's captured vector passes a value-form vector parameter, `|k|
  lanes(b)`, on every target. The workaround `var w: f64v2 = b; lanes(w)` still works. A capture of another 16-byte type
  into `x: f64v2` passes, as the local does.
- **VC-5 (D32, the user 2026-10-16):** `lanes(*pb)` passes the vector `pb` points at. It was refused on x86_64, aarch64
  and cx, and was a page fault on Windows. Message change: the value-form argument refusal's list gains "or a
  dereference of a pointer to its type (`*p`)", so a tool matching "is a local of its type or a call declared to return
  it" re-matches. `lanes(*nosuch)` now prints only "undefined variable 'nosuch'".
- **VC-7:** a call to a missing fn as a wrapped vector-local source, a vector `return` or a value-form argument is
  reported as "undefined function 'f64v2_splat'" — add `include "lib/simd.cyr"`. A vector fn that returns such a call
  and is never called now builds with the warning, as an unwrapped vector local in such a fn already did.
- **VC-8:** `callptr(&f, ..)` / `fncallN(&f, ..)` of another vector into a vector local is refused "vector return type
  does not match the declared type" / ".. the assigned variable". It was the generic "got `callptr`" refusal.
- **VC-9:** the false "assigning non-pointer to typed pointer" on a vector local is gone.
- **VC-11:** a method result passed as an argument is named `'S2.dup'` (a generic method `'Pt.gd'`) in the struct-type
  and `*V` refusals, where they printed `'S2_dup'`. A script grepping those diagnostics re-matches.
- **VC-4r:** a captured vector or `*V` dereference passed to a value-form parameter, in a call that is an argument of
  an `#inline` fn inside a closure, reads the right value. So do integer-only nested inline calls in a closure. They
  read a clobbered frame slot (or faulted).
- **VC-17:** a gate's PASS line.

### 6.7.12

Break 2, repair 2 — the platform release. Each block names its CHANGELOG [6.7.12] bite; the decisions are the user's
(2026-10-15, D1–D31, and D3's per-thread scope). The changes that went beyond a decision's text are filed for confirmation
in 6.7.13 (`docs/development/issues/archived/2026-10-15-6712-behaviour-changes-beyond-the-decisions-text.md`).

#### Language — the fix-first items

#### The language — the fix-first items

The decisions are the user's at the 6.7.12 open (2026-10-15, D27 – D30). "6.7.11's Dn" is the 6.7.11 open's id
(2026-10-13). Each block names its CHANGELOG [6.7.12] bite.

**FX-1 — a vector value into a `*V` parameter is an address; a vector local into another pointer kind is refused (D27, the user 2026-10-15)**
- Stops compiling: a vector LOCAL passed to a pointer parameter that is not a pointer to its vector type —
  `fn rp(p: *Pt)` called `rp(b)`, and `p: *i64`, `p: *u8`, `p: **T` — now "cannot pass 'b' to a parameter that is not
  a pointer to its vector type in a call to 'rp' - pass &b for its address" (every such argument reported). It passed
  lane 0's bits as the address and faulted (139 on x86_64 and aarch64, a cx guest fault, exit 5 on Windows) — except
  on Windows, where `rp(b)` into `p: *Pt` happened to pass `&b` and ran. Pass `&b` if the callee really reads the
  vector's bytes through that pointer, or give the parameter the vector's own pointer type (`p: *f64v2`).
- Stops compiling: at top level, a vector call result into a `*V` parameter — `var r = rd(mkv(42, 7));` — is "'mkv'
  returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn" (it faulted on
  every target in 6.7.11; 6.7.10 refused it on x86_64). Move the call into a fn.
- Stops compiling: a call result or a dereference of ANOTHER vector type into a `*V` — `rd(mkv4(..))` with `mkv4`
  returning `f64v4` into `p: *f64v2`, `rd(*pq)` with `pq: *f32v4` — is "cannot pass 'mkv4' to a parameter of a
  different vector type in a call to 'rd'", as a local of another vector type already was (6.7.11); it compiled to a
  fault. Pass the vector type the parameter names.
- Starts working (no change needed): `rd(mkv(..))` — by name, wrapped, through `fncallN(&f, ..)` / `callptr(&f, ..)`,
  in a tail position — and `rd(*pv)` with `pv` a `*V` pass an address (a frame temporary's; `pv` itself) on every
  target. Through 6.7.11 they compiled to a fault (x86_64 refused them through 6.7.10); the 6.7.11 workaround — bind
  the vector to a local first, or pass `pv` — still works.
- `p: *f32v8` is now a pointer to an `f32v8` like the other `*V`: `r8(e)` with a vector local passes `&e` (it passed
  lane 0 and faulted). A value-form `v: f32v8` parameter is unchanged — it still receives only its first word (filed,
  6.7.13); pass `*f32v8` until then.

**FX-3 — a known fn-pointer call returning a struct over 8 B into a scalar annotation is refused (D28, the user 2026-10-15)**
- Stops compiling: inside a fn, `var x: <scalar> = fncallN(&f, ..);` / `= callptr(&f, ..);` — the callee written `&f`,
  `f` returning a struct over 8 bytes (not `Str`), `<scalar>` any annotation that names no struct (i64, u8, f64,
  bool, …), the initialiser wrapped or not — is "cannot initialise 'x: i64' from 'f', which returns the struct 'P3' -
  declare 'x: P3' or bind a field", as `var x: i64 = f(..);` has been since 6.7.11. It read the struct's first field.
  Declare the struct and read the field: `var p: P3 = fncall1(&mk3, 5); var x = p.a;`. A field of the call itself
  (`fncall1(&mk3, 5).a`) is not accepted yet ("expected ';', got '.'"; filed, 6.7.13).
- Unchanged: a struct of 8 bytes or less still gives its word; a callee held in a variable (`var fp = &mk3;
  callptr(fp, 5)`) is still one word, not refused; a top-level global is not judged. A parenthesised callee
  (`fncall1((&mk3), 5)`) still compiles and faults (exit 139 on x86_64) — write `&f` unwrapped; it is refused when the
  parenthesised-callee fix lands (6.7.13).

**FX-5 — an untyped `var q = p;` of a struct value is a typed copy (D29, the user 2026-10-15)**
- `var q = p;` (or `var q = (p);`) in a fn, with `p` an inline struct local, a by-value struct parameter (`self: T`
  included) or a closure's captured copy of one, now declares `q` a copy of `p`'s struct, as `var q: P = p;` does.
  Through 6.7.11 `q` was `p`'s FIRST WORD.
- Changes what compiles: an arithmetic operator on `q` (`q + n`, `q - n`, `q * n`, …) now dispatches the struct's
  operator fn (`P_add`, `P_sub`, …) and is refused when there is none (the "undefined function 'P_add'" warning, then
  "refusing to emit binary with 1 reachable undefined function(s)"); it computed on the first word. Write the field you
  meant (`p.x + n`), or `load64(&p) + n` for the raw first word.
- Starts working: `q.y` (read and write; `p` is untouched) in a fn and inside a closure that captures `q` — it was "no
  struct type in scope for 'q'" ("undefined variable 'q'" in a closure); `take(q)` into a by-value struct parameter
  passes the struct (it passed the word as an address and faulted).
- Unchanged — still the first word: `return q;` from an `i64` fn, `raw(q)` into an untyped parameter, `q == 3`. And
  still a plain word: `var q = pp;` with `pp` a `*T` (an untyped impl `self` is one), `var q = h;` from a handle,
  `var q = G;` naming a struct global inside a fn, and every top-level `var H = G;`. Annotate (`var q: P = G;`) for a
  copy of a global.
- No in-tree `lib/` or corpus code had the shape (an instrumented census found none).

**FX-6 — `var a = 0;` then `var a = 5;` warns (D30, the user 2026-10-15)**
- A warning only: nothing stops compiling, and no binary or exit code changes. A global first declared `= 0` (or a
  constant that folds to 0, `= 1 - 1`) and declared again with another value now prints "duplicate symbol 'a'
  redefined with conflicting value (last definition wins)", as every other differing pair did; the same goes for
  `var A = 0;` followed by an enum member `A` (it printed the enum-over-var warning, whose text now ends "(computed)").
- If a pin bump shows it, two files (or a file and a fold) declare one global with different initial values and share
  one cell — rename one side. A same-value redeclaration stays silent, as documented.

Kept, nothing to migrate: the six 6.7.11 changes that went beyond their decisions' text (D10's flip side, ST-8, RET-2,
ST-20, GF-12 / GF-16 / GF-2, D4's 8-byte store) are confirmed by D31 (the user, 2026-10-15); the § 6.7.11 blocks stand.

#### Darwin / aarch64

#### Darwin / aarch64

**DW-5 — `sys_sigprocmask` works on macOS, and changes the calling thread's mask (D3, the user 2026-10-15; per-thread, the user 2026-10-15)**
- On macOS (x86_64 and arm64), `sys_sigprocmask(how, set, oldset)` now returns 0 and changes the calling thread's
  mask, as on Linux. It is Darwin's `__pthread_sigmask` (329), reached through the private alias 1329.
- Through 6.7.11 it returned -78 and did nothing. Code that took -78 as "macOS has no signal mask, skip" now really
  blocks or unblocks. Drop the -78 branch. If the macOS path must stay a no-op, guard it with
  `#ifdef CYRIUS_TARGET_MACOS` instead of testing the result.
- `oldset` reads back with its upper 32 bits 0, because Darwin's set is 32 bits.
- Children started through `lib/process.cyr`'s exec family (`run`, `run_capture`, `spawn`, `exec_*`, `exec_cmd`) on
  macOS no longer inherit the parent's blocked signal mask: they start with an empty mask, as on Linux since 6.7.9. A
  SIGINT that a launcher or the program blocked no longer makes the child uninterruptible by it. A child that must keep
  a signal blocked blocks it itself. Ignored dispositions other than SIGPIPE / SIGXFSZ, such as a `nohup` SIGHUP, are
  still inherited, as before.

**No block — a new diagnostic, smaller binaries, an added file (nothing that compiled changes what it does):**
- **DW-1 (D1, the user 2026-10-15: warn only):** an ELF-aarch64 build may now print `raw syscall N inside a
  native-aarch64 region is renumbered → M (<call>); write 1000+N for native <call>`, or `… no 1000+N alias exists for
  native <call>`.
  - It fires where a program writes a native number as a raw literal inside its own `#ifdef CYRIUS_ARCH_AARCH64`,
    `#ifplat aarch64` or `#ifndef CYRIUS_ARCH_X86` region, and an x86-compat row renumbers that number.
  - The binary is unchanged. That call has always run the x86 meaning (`syscall(9, …)` ran mmap, not lgetxattr).
  - To reach the native call, write the `1000+N` alias the warning names, or the stdlib `SYS_*` name / `sys_*`
    wrapper.
  - Not judged yet (filed, 6.7.14): a per-arch file included from inside the region, and a constant declared there.
    Check those by hand.
- **DW-3 / DW-4:** arm64-macOS and x86-macOS binaries are smaller and behave the same. A literal syscall site carries
  only its Darwin number and the fixup it needs, and on x86 a run-time syscall number calls a shared stub instead of
  inlining the 92-row chain.
- **DW-6 (D4, the user 2026-10-15):** a macOS binary install gains `~/.cyrius/bin/cyrius-watch.sh`. It compiles with
  raw `cat | cycc`, so on Apple Silicon its output is unsigned and killed at exec (filed, 6.7.14). `cyrius build`
  ad-hoc signs its output.

#### Windows

#### Windows, the arm64-macOS `openat`, the passwd / group readers (the windows lane)

**WN-1 — `xflock` locks on Windows**
- Through 6.7.11 `xflock` returned -1 for every op on Windows. It now takes a real lock through kernel32 `LockFileEx` /
  `UnlockFileEx` on ONE sentinel byte at offset 2^63 − 1 — never the file's data, so reads and writes through every
  handle keep working while the lock is held, as with flock. Results: 0 when granted; -11 when `LOCK_NB` finds the
  lock held (`lib/syscalls_windows.cyr` declares no `EAGAIN`, so compare with -11 there); -22 for an op that is not
  `LOCK_SH` / `LOCK_EX` / `LOCK_UN`; 0 for `LOCK_UN` of a lock this handle does not hold; -1 for any other failure.
- A blocking `LOCK_EX` / `LOCK_SH` now WAITS while another handle holds a conflicting lock — it returned -1 at once.
  Code that called `xflock` on Windows expecting an immediate -1 ("no locking here") must pass `LOCK_NB` or expect to
  block. A held lock converts on one handle (SH ↔ EX) by dropping and re-taking it, as flock's own conversion does (not
  atomic).
- patra (folded) takes every lock through `xflock`: on Windows its locks are now real, and its open-time WAL recovery
  runs when the non-blocking exclusive lock is granted. A CONTENDED open on Windows is still read as "no lock can be
  had" (patra's `_pt_flock_contended` tests EAGAIN only on Linux / macOS) until patra's own release adopts -11.

**WN-3 — arm64 macOS: `sys_openat` keeps its dirfd; `[embed]` refuses a link at the open**
- macOS arm64: `sys_openat(dirfd, rel, flags, mode)` — and a raw `syscall(56, dirfd, rel, …)` — now opens `rel`
  RELATIVE TO `dirfd`, as on Linux and Intel macOS. Through 6.7.11 the dirfd was dropped (56 reached BSD `open`), so
  `rel` opened against the current directory. Code that passed a real dirfd and relied on cwd-relative answers now gets
  the dirfd's: pass `AT_FDCWD` (or an absolute path) to mean the cwd. A raw -100 still means the cwd (it is translated
  to Darwin's -2; the stdlib's `AT_FDCWD` is -2 there already). ⚠ `sys_mkdirat` / `sys_fchmodat` still drop the dirfd
  on arm64 macOS (filed, 6.7.14) — until then pass an absolute path to them there.
- `[embed]` / `${file:}` on Windows and macOS arm64: a file reached through a directory link or junction at the moment
  of the open is refused ("cannot be opened through a link-free path"), as on Linux and Intel macOS. A project that
  does not race its own build reads the same bytes (the link check already refused a link on the path).
- New public name on Windows: `win_handle_under(h, root_h)` in `lib/fs_win.cyr` (1 inside, 0 outside, -1 cannot
  tell). A program that defines its own fn of that name beside the stdlib now gets the duplicate-definition warning
  (its own, the last definition, still wins).

**WN-4, WN-4r — Windows `xsymlink`: long link paths and long absolute targets; the 0xF03E reroute takes UTF-8**
- `xsymlink` / `sys_symlink` callers: a link path over 260 units and an absolute target over 260 units now link (they
  failed -1, and 519+ units were refused before the call). An absolute target (`X:\…`, `\\server\…`) whose full form is
  248+ units reaches Windows `\\?\`-prefixed (`\\?\UNC\…`), normalized by GetFullPathNameW first — the shared rule
  every path reroute applies; between 248 and 259 units such a target used to reach Windows as written. A relative
  target is passed as written (`/` becoming `\`), never made absolute.
- A direct `syscall(0xF03E, link, target, flags)` caller (none in the tree but `sys_symlink`) must now pass
  NUL-terminated UTF-8, not UTF-16 — a wide buffer is read as a (short) UTF-8 string. Call `xsymlink` / `sys_symlink`
  instead.

**WN-6 — Windows native TLS: NotBefore roots, the disallowed CTL, `TLS_CTX_LEN` 632 (D9, the user 2026-10-15)**
- Windows, native TLS with the system store (`tls_native_set_ca_system`, the default for `tls_connect*`):
  (a) a server whose chain ends at a NotBefore-distrusted root (props 126 / 127) with a leaf issued BEFORE the date now
  verifies — it was `TLS_ERR_CERT_INVALID` (the root was refused whole); a leaf issued on or after the date is still
  refused;
  (b) a chain through any certificate whose public key the auto-updated disallowed CTL lists, or any certificate in the
  `Disallowed` store, now fails `TLS_ERR_CERT_INVALID` at any depth — leaf, intermediate or anchor (it was accepted
  unless it was the root);
  (c) a present but corrupt or unreadable `DisallowedCertEncodedCtl` makes `tls_native_set_ca_system` answer
  `TLS_ERR_IO` (no store) — as an unopenable Disallowed store already did;
  (d) `tls_native_ca_skipped` on Windows is lower by the NotBefore roots (cass 8, was 14).
- A root Windows would fetch on demand is still not there (D9): add it with `tls_ctx_load_verify_locations` /
  `tls_native_set_ca_bundle`. A ctx given a caller's bundle has no trust policy and is unaffected by (a)-(c).
- `TLS_CTX_LEN` is 632 (was 624; `TLS_CTX_OFF_CA_POLICY = 624` is new). Code that sizes a ctx buffer by `TLS_CTX_LEN`
  keeps working; a hard-coded 624 is 8 bytes short.

**WN-2r — `lib/pwd.cyr` / `lib/grp.cyr` read a uid / gid as one number**
- macOS: `pwd_getpwuid(0)` / `grp_getgrgid(0)` return root / wheel (they returned `nobody` — Darwin's first records
  carry uid / gid -2, read as 0), and `pwd_getpwuid(-2)` / `grp_getgrgid(-2)` find `nobody` (they found nothing).
  Code that worked around the old answer (looked up root by name, or special-cased `nobody` for uid 0 on macOS) can
  drop the workaround.
- Every target: an /etc/passwd or /etc/group line whose uid / gid field is not one number (empty, `12a`, `abc`, two
  signs) is skipped, like a short line — it was read as id 0 (or as its leading digits) and could answer a lookup for
  uid 0. `grp_getgrouplist` no longer adds a 0 for such a line. A lookup that relied on a malformed line now finds
  nothing there.

No block for the lane's other bites: WN-2 (the cass triage and D8's full-corpus default — test fixtures, gate scripts and
docs; nothing a consumer compiles changes); WN-5 (a gate script).

#### The standard library, agnos, cx, TLS

**LIB-1 — `lib/ws_server.cyr` includes `lib/ws.cyr` (D11, the user 2026-10-15)**
- `lib/ws_server.cyr` no longer declares its own copies of these nine vars: `WS_OP_CONTINUATION`, `WS_OP_TEXT`,
  `WS_OP_BINARY`, `WS_OP_CLOSE`, `WS_OP_PING`, `WS_OP_PONG`, `WS_OPEN`, `WS_CLOSING` and `WS_CLOSED`. It includes
  `lib/ws.cyr` instead, and the nine are ws.cyr's enum constants, with the same values.
- `include "lib/ws_server.cyr"` now also brings ws.cyr's client fns (DCE drops the unused ones), `WS_CONNECTING` and
  `WS_RECV_MAX_PAYLOAD`.
- With ws_server alone, two shapes stop compiling: a write to one of the nine (`WS_OPEN = 5;` gives "cannot assign to
  enum constant 'WS_OPEN'") and taking its address (`&WS_OPEN`). Reading them is unchanged.
- A program that defines its own `ws_*` fn beside ws_server now gets the duplicate-fn warning ("duplicate fn 'ws_new'
  (last definition wins; first defined in lib/ws.cyr)"). Its own definition, the last one, still wins.
- A program's own `WS_CONNECTING` warns only when its value differs from ws.cyr's 0. A same-value copy is silent
  (measured on the merged tree).
- `cyrius distlib` now records `ws` for a bundle that reads a `WS_*` name with neither leaf in its unit. 6.7.11 refused
  that as a tie: "more than one stdlib leaf could own it (ws, ws_server)". yantra's distlib converges again, and its
  bundle is byte-identical.
- **Migrate:**
  - Read the nine names as before.
  - If you assigned to one or took its address, declare a `var` of your own under another name.
  - Drop, or rename, a private `WS_CONNECTING` or `ws_*` copy.
  - Regenerate your `dist/` bundle. The `include "lib/ws.cyr"` workaround in a bundled module is no longer needed, but
    it is harmless.

**LIB-2 — agnos: the net arms take only a tagged socket fd**
- These calls now refuse any fd that `tcp_socket()` did not hand out: a failed open's `-1`, a file or stdio fd, and
  `AGNOS_SOCK_TAG + 8` and up. This is agnos only.
  - `sock_bind`, `sock_listen`, `sock_accept` and `sock_connect` return `Err(9)` (EBADF) for a negative fd and
    `Err(88)` (ENOTSOCK) for any other.
  - `net_connect_nb` returns `_NET_CONN_NB_ERR`.
  - None of them writes a table or makes a kernel call first.
- Before, they acted on socket slot `fd & 7` (a `-1` bound, listened, accepted and connected on slot 7) and could
  answer `Ok`. Linux already answered these errnos.
- **Migrate:** check a socket open's result before you bind, listen or connect, as on Linux. A program that passed only
  sockets sees no change.

**LIB-5 — epoll_event readers: `epoll_event_events` / `epoll_event_data` / `const EPOLL_EVENT_SIZE`**
- These are new, beside `epoll_event_new` in the x86_64 Linux, aarch64 and x86-macOS peers. They read one element of a
  `sys_epoll_wait` array (or an `epoll_event_new` result) in the peer's layout. Step through the array by
  `EPOLL_EVENT_SIZE`: 12 on x86_64 and x86-macOS, 16 on aarch64.
- A hand-gated `load64(ev + 4)` / `load64(ev + 8)` per arch can become `epoll_event_data(ev)`.
- ⚠ A program that declares its own `EPOLL_EVENT_SIZE` after including `lib/syscalls.cyr` now stops compiling:
  "'EPOLL_EVENT_SIZE' is already declared as a top-level const". Drop the copy.
- A program that defines its own `epoll_event_data` / `epoll_event_events` gets the duplicate-fn warning. Its own
  definition, the last one, still wins.
- ⚠ A build that includes a second syscall peer beside the one `lib/syscalls.cyr` picks also stops compiling, with
  "const 'EPOLL_EVENT_SIZE' is declared twice" (`lib/syscalls_macos.cyr` in a Linux build, for example). The peers'
  same-name vars only warned. Include `lib/syscalls.cyr` alone: it selects one peer per target.
- `lib/async.cyr`'s epoll reactor now reads each event at the peer's stride. It read every arch at 16, so on x86_64 the
  2nd..8th event of one wait were read off by 4, 8, … bytes: a stale or garbage fd, with the real one re-reported by the
  next wait. A reactor woken by several fds at once now wakes all their waiters from that one wait. aarch64 is
  unchanged.
- **Migrate:**
  - Drop any `EPOLL_EVENT_SIZE` you declared.
  - Never include two `lib/syscalls_*.cyr` peers in one build.
  - Replace hand-gated `+4` / `+8` reads and a hard-coded 16 stride with the readers. The 16 stride was wrong on x86_64.

**LIB-7 — cx programs up to 4 MiB of bytecode (D12, the user 2026-10-15)**
- `cycc_cx` holds 4 MiB of bytecode. It stopped at 512 KiB with a bare `error: codebuf overflow`.
- Past 4 MiB it refuses by name: `error: cx bytecode exceeds the cx code region (4194304 B): <n> B emitted when fn
  '<name>' (its code starts at byte <off>) reached it — build this program for a native target`.
- cxvm's guest memory is 8 MiB (it was 1 MB). cxvm reads a `.cyx` up to that size plus its 8-byte header. Past it, the
  error is `error: .cyx exceeds cxvm's guest memory (8388608 B of code and data)`.
- A `.cyx` an older cycc_cx wrote runs unchanged.
- Guest addresses from 1 MB to 8 MiB are now ordinary memory. They trapped as "guest address out of range".
- The guest stack starts at 8 MiB, so recursion runs about eight times deeper before "guest stack overflow". The VM
  stacks hold 524288 entries, so a runaway recursion still meets the guest-stack trap first.
- `lib/tls.cyr`, `lib/tls_native.cyr` and `lib/sigil.cyr` stay refused by name. The message no longer cites a 512 KiB
  `.cyx`.
- **Migrate:**
  - A program that compiled for cx needs nothing.
  - A cx test that relied on a trap at a guest address between 1 MB and 8 MiB must use an address of 8 MiB or more.
  - A script that matched `codebuf overflow` or `exceeds 1MB cxvm code buffer` must match the new messages.

**LIB-8 — cx: honest refusals from four wrappers (D13, the user 2026-10-15)**
- On cx, `cyr_mmap` returns -1, so `mmap_anon` returns 0. Before, it returned a HOST address that the guest could not
  use: a non-zero pointer whose first access trapped.
- `sys_pipe`, `sys_fstat` and `sys_unlink` return -38 (-ENOSYS) where they returned -14 (-EFAULT). `sys_pipe` leaves its
  buffer as it was.
- `sys_unlink` never removed the file on cx, and it still does not.
- A cx program that tested `< 0` or `== 0` takes the same branch as before. One that compared against -14 must read -38.
- Native targets are unchanged: the arms are `CYRIUS_TARGET_CX` only.
- ⚠ `mmap_stack` (`lib/thread.cyr`) and `fl_alloc` (`lib/freelist.cyr`) still map through a raw `mmap` on cx and return
  a host address. Measured on the merged tree; not covered by D13's four arms.
- **Migrate:**
  - Check `mmap_anon`'s result for 0 on cx, as on every target.
  - Read -38 where you matched -14.
  - Do not rely on `sys_unlink` removing a file under cxvm.

**LIB-11 — the native TLS stack's public bound vars are inert (D16, D17, the user 2026-10-15)**
- Seven vars no longer steer the stack: `TLS_HANDSHAKE_HEADER_LEN`, `TLS_MAX_DIGEST_LEN`, `TLS_RANDOM_LEN`,
  `TLS_RECORD_MAX_PLAINTEXT`, `TLS12_VERIFY_DATA_LEN`, `TLS12_RANDOM_LEN` and `TLS_SHA384_CTX_LEN`. Every read in
  `lib/tls_native*.cyr` and `lib/tls.cyr` now reads the `_X` const that sizes the storage.
- They are still writable vars holding the same values (LIB-12, D16), so read them freely. A write now changes nothing.
- Before, a write drove copies, indexes and allocations over const-sized storage:
  - `TLS12_RANDOM_LEN = 256` smashed the PRF seed (SIGSEGV);
  - a raised `TLS12_VERIFY_DATA_LEN` or `TLS_SHA384_CTX_LEN` overran the stack.
- ⚠ `TLS_RECORD_MAX_PLAINTEXT` is the protocol's 2^14, not a knob (D17):
  - A program that LOWERED it no longer gets smaller outgoing fragments (from `tls_write`, the handshake-record
    fragmenter and `tls_native_record_fragment_count`), and no longer refuses a peer's full 2^14-byte records.
  - A program that RAISED it no longer seals over-length records: 2^14 + 1 is `TLS_ERR_RECORD_OVERFLOW`.
  - A real max_fragment_length (RFC 6066) is a feature, not this var.
- The 14 public bound vars (these seven, `TLS_AEAD_NONCE_LEN`, `TLS_HKDF_LABEL_BUF_LEN`, `TLOCAL_MAX_SLOTS`,
  `TLS_REG_MAX`, `SPAWN_ARGV_MAX`, `SPAWN_ENV_MAX`, `KEV_SIZE`) stay vars. Their `const` conversion belongs to the
  public-constants arc, a later compile break announced at its slot.
- **Migrate:**
  - Remove writes to these vars. They no longer do anything.
  - A program that lowered `TLS_RECORD_MAX_PLAINTEXT` to cap its write size must split its own writes.

**LIB-14 — `args_init()`: a failure is a negative errno on Linux and Windows (D7, the user 2026-10-15)**
- `args_init()`'s failure return is a negative errno on Linux and Windows. It was 0.
  - Linux returns the open's or the read's -errno, or -12 when a buffer cannot be allocated.
  - Windows returns -5 when `GetCommandLineW` fails, and -12 when `CommandLineToArgvW` or the blob's alloc fails.
- Successful returns are unchanged: the bytes read on Linux and Windows, and 0 on macOS / agnos.
- On Linux a command line longer than 2 MiB is now read whole. Before, it was cut at 2,097,152 bytes with no error, and
  `argc()` / `argv()` saw only the prefix.
- **Migrate:**
  - Code that treated `args_init() == 0` as "could not read the command line" must test `< 0`. 0 is success on macOS
    and agnos.
  - A consumer that refused a 2,097,152-byte `_args_len` as "may be truncated" can drop that check (cmdit 1.3.2's
    workaround is one).

**LIB-15 — the native TLS client is stricter with non-conformant peers**
- A 1.3 server now fails the handshake, with the alert sent, when it sends any of these:
  - an extension the client did not offer, or one its message may not carry;
  - an ALPN protocol outside the client's list;
  - an ECDSA CertificateVerify on the other curve;
  - a byte after a signature.

  The errors are `TLS_ERR_HANDSHAKE_FAILED`, `TLS_ERR_AUTHN` or `TLS_ERR_BAD_HANDSHAKE`.
- A 1.2 ServerKeyExchange with a byte after its signature is refused too (`TLS_ERR_BAD_HANDSHAKE`). The 1.2 client sends
  no alert.
- A 1.2 client restricted with `tls_native_set_groups` refuses a server whose ECDSA certificate is on an unlisted curve
  (`TLS_ERR_HANDSHAKE_FAILED`).
- A native 1.2 server refuses a ClientHello whose session id is over 32 bytes (`TLS_ERR_BAD_HANDSHAKE`, decode_error).
- Conformant peers are unaffected, including OpenSSL's 68 interop rows.
- **Migrate:**
  - Fix the peer.
  - With `tls_native_set_groups`, list the server certificate's curve, as OpenSSL requires too.
  - A test double that answered with an unsolicited extension or an un-offered ALPN must answer as the RFC says.

**No block:**
- LIB-3: test-only.
- LIB-4: `lib/audit_walk.cyr`'s Linux lister on a FIFO now reports the error 20 a regular file already got, instead of
  blocking for good. A path of 4096+ bytes, or one with an embedded NUL, is -36. Nothing to change.
- LIB-6: the README and a gate.
- LIB-9, LIB-14r: docs.
- LIB-10: tests and the guide's D14 exception.
- LIB-12: comment-only; covered under LIB-11.
- LIB-13: D15 keeps `TLS_CA_MAX_ROOTS`; nothing changes.
- LIB-7r: comments.
- LIB-16: a gate.

#### Tools and the CLI

#### Tools and the CLI

Each block names its CHANGELOG [6.7.12] bite (the tools lane, TL-*); the decisions are the user's (2026-10-15).

**TL-3 — `cyrius self` and `cyrius soak` verify the default compiler**
- Both verifiers now run their two self-host steps without `CYRIUS_POISON`, `CYRIUS_BOUNDS`, `CYRIUS_COVERAGE` and
  `CYRIUS_COVERAGE_FILE`, as `cyrius pulsar` has since 6.7.11. A shell that exports one of them gets a verdict about
  the default compiler (it was about a mode-built pair), and an exported `CYRIUS_POISON=no` no longer fails a step.
  `cyrius soak`'s test suite and `.scyr` harnesses are your own compiles and still see the switches. Nothing to change;
  to self-host a mode build on purpose, run the compiler on `src/main.cyr` directly with the variable set.

**TL-4 — the compiled `cyriusly setup` refuses without `build/cycc`**
- `cyriusly setup` in a checkout with no `build/cycc` exits 1 before building anything:
  `error: bootstrap did not produce build/cycc — …`. `bootstrap/bootstrap.sh` builds cybs and asm, never cycc, so
  restore the tracked compiler with `git checkout build/cycc` and re-run. (`sh scripts/seed-derive-cycc.sh` proves the
  tracked file descends from the seed; it needs build/cycc to exist.)
- The tools `setup` builds and installs are the default build whatever the calling shell exports (an exported
  `CYRIUS_BOUNDS=1` installed a bounds-checked cyrfmt). Its cross-bin loop is gone; `install.sh --refresh-only` builds
  the cross bins, as before.

**TL-6 — `cyrius package` refuses a missing entry**
- `cyrius package` with a `[build] entry` that does not exist (or with no manifest and no `src/main.cyr`) exits 1 with
  `error: no such file: <entry>` — the words `cyrius build` uses — and creates no `build/`. It printed
  `package ready: build/<out>` at rc 0 with no artifact. Fix the entry path; a real entry builds as before.

**TL-7 — `cyrius tests` is removed (D21)**
- `cyrius tests [dir]` is an unknown command: `Unknown command: tests`, then
  ``error: `cyrius tests` was removed at 6.7.12: use `cyrius test <dir>` (`cyrius test tests` for tests/)``, rc 1,
  before anything resolves or runs (`tests --help` too). Replace it in CI lines and scripts: `cyrius tests <dir>` →
  `cyrius test <dir>`; a bare `cyrius tests` → `cyrius test tests` (the bare `cyrius test` also runs `[test] files`
  first, which `cyrius tests` never read).

**TL-8 — `cyrius type-audit` counts generic fns**
- A public `fn f<T>(..)` is now counted (it was invisible), so type-audit's totals rise and its coverage percentage
  may drop where generic fns are unannotated; an unannotated one is listed by name. A CI floor on that figure may need
  annotations or a new floor.

**TL-9 — `cyrius api-surface` writes a variadic fn as `name/MIN-` (D22)**
- `fn va(n, ...)` is recorded `va/1-` (it was `va/2`), and `fn zv(...)` `zv/0-` (was `zv/1`). A checked-in snapshot
  that lists a variadic fn reads as changed once: regenerate it with `cyrius api-surface --update` and commit the diff.
  A tool that parses the arity after `/` meets a trailing `-` on variadic fns (it has met `MIN-MAX` since 6.7.7); the
  removed-symbol census reads the bare name, as before.

**TL-10 — one emit target per run (D20)**
- Two target selectors on one command line — any two of `--aarch64`, `--win`, `--agnos`, `--target=<v>` — are refused
  by name before anything resolves or compiles: `error: --win and --aarch64 select two emit targets; pass one`, rc 1,
  no output. They exited 0 and built one of them (or neither): `--win --aarch64` wrote the aarch64 ELF,
  `--aarch64 --target=js` an aarch64 ELF named `.js`. Pass the one you meant. The one accepted pair is
  `--aarch64 --target=aarch64-bare-metal-elf`, which builds exactly what `--target=aarch64-bare-metal-elf` alone builds.
  Each single selector's output is byte-identical to 6.7.11's.

**TL-11 — `cyrius deps` names `lib/` files outside the declared footprint**
- After a successful resolve, `cyrius deps` / `cyrius build` (any resolving verb) print a `note:` on stderr listing
  every `lib/*.cyr` the resolve did not vendor — a leaf you dropped from `[deps] stdlib`, the module of a dep you
  removed — while it stays there. Nothing is written or deleted for it. To drop one from lib/ AND cyrius.lock:
  `rm lib/<file> && cyrius deps --lock` (a plain `cyrius deps`, even after `rm -rf lib/`, keeps the old lock row in a
  stdlib-only project). A `lib sync --full` project (lib/ holds the whole pinned snapshot) is not told. A script that
  asserts an empty stderr passes `-q`.

**TL-12 / TL-12r — a pin bump does not re-lock over stale vendored files (D19)**
- In a project that vendors the whole snapshot (`cyrius lib sync --full`), run `cyrius lib sync --full` FIRST after
  bumping `[package].cyrius`. Until then `cyrius deps`, `cyrius build` and every resolving verb exit 1 with
  `error: cyrius.lock not re-locked: [package].cyrius moved from <old> to <new>, …` and the list of lib/ files the new
  pin's snapshot ships with other bytes; cyrius.lock is left unchanged. Through 6.7.11 they stamped the new pin over the
  old pin's rows at rc 0, and the next `lib sync --full` refused. The two remedies the refusal names:
  `cyrius lib sync --full` (moves the files to the new pin and re-locks) or `rm <file> && cyrius deps` (drops them).
  `--relock` does not bypass the refusal.
- After that refusal the closure files are already re-vendored at the new pin, so `deps --verify` fails on them until
  one of the remedies runs (filed for 6.7.13), and `deps --locked` still says "run `cyrius deps`" (filed). Follow the
  refusal's remedy, not `--locked`'s.
- A project whose lib/ is only its declared closure is unaffected (it re-locks silently at a pin move).
- `lib sync`'s refusal summary no longer blames `deps` / `build`. For a lock re-stamped at a moved pin by
  `deps --lock`, a scoped `lib sync` or a pre-6.7.12 `deps` / `build`, it names `cyrius lib sync --relock`
  (`cyrius lib sync --full --relock` in a project that vendors the whole snapshot). `deps --lock` and a scoped
  `lib sync` still stamp a moved pin themselves (filed for 6.7.13): bump the pin with `cyrius lib sync --full` or a
  plain `cyrius deps`.

**TL-13 — a kept commit pin of a dep's old tag is named (D25)**
- After a `[deps.NAME] tag` bump, every resolve (`cyrius build` included) and `cyrius deps --locked` print one
  `note: cyrius.lock keeps NAME@OLD's pin (the manifest declares NAME at NEW), fail-closed; delete cyrius.lock to re-pin`
  per kept old-tag line. The row stays (fail-closed since 6.6.20, CYRIUS-2026-0030), `--locked` still passes, and
  nothing written changes. To drop the old row, delete cyrius.lock and run `cyrius deps` (re-pinning every dep); `-q`
  silences the note.

**TL-14 — `cyrius deps` prints the real error count; `lib sync --dry-run` prints paths**
- `cyrius deps`'s summary counts every refused section (`2 errors` for two; it printed `1 errors` for any number in one
  manifest). Exit statuses are unchanged (1 on any error). A script that parsed `N errors` sees the real count.
- `cyrius lib sync --dry-run` prints `would sync: lib/<file>.cyr` (it printed a number per file).
- A path joined to the CLI's absolute `.` no longer carries `/./` (error text and git's `-C` argument).

**TL-15 — physical paths under a symlinked working directory**
- Under a symlinked cwd, an absolute unit spelled with the shell's `$PWD` (`cyrius test $PWD/tests/sub/x.tcyr`) is
  inside the project and gets its directory's `test.cyml`, as the relative and physical spellings do. A unit that
  passed only because its `test.cyml` was not read (rare) now runs with it.
- A local dep reached through a symlink into another repository reports its own state: `(not a git checkout)` when it
  is not a checkout, no longer the enclosing repository's HEAD and dirt.

**TL-16 — `cyrius update` writes what `cyrius lib sync` writes (D18)**
- `cyrius update` copies the declared `[deps] stdlib` leaves (with their per-OS peers and the test scope's leaves) from
  the snapshot of `[package].cyrius` — the plan, lock guard, re-lock and source-repo refusal of `cyrius lib sync` — and
  writes that version into an existing `.cyrius-toolchain`. It copied every file of `$CYRIUS_HOME/current`'s snapshot,
  whatever the manifest declared or pinned. A project that relied on update filling lib/ with the whole stdlib runs
  `cyrius update --full` (or `cyrius lib sync --full`).
- It reads the manifest's pin, never `current`: that version must be installed (`cyrius install <pin>`; the refusal
  names it). Update's fallback to a sibling `../cyrius/lib` is gone. Under an unchanged pin, a lock row that disagrees
  with the installed snapshot is refused as `lib sync` refuses it (reinstall that version).
- The named-deps half (re-fetch untagged deps, newer tags) is unchanged.

**TL-17 — the lock's SHA-256 is computed in process**
- Nothing to do: lock bytes are identical. `cyrius deps` no longer runs `sha256sum` / `shasum` / `certutil.exe`, so a
  CI image does not need one, a full temp dir no longer loses the hash, and `cyrius.exe` under wine writes the lock it
  did not write. On a host with no hasher on PATH the first lock is written (it was a `cyrius.lock NOT written`
  warning), and the 6.6.4 snapshot guard checks the pinned snapshot: an unmoved leaf passes, and a leaf that moved
  under an unchanged pin is refused by name (`… DISAGREE under an unchanged pin`) where every check was refused as
  `cannot hash` — reinstall that version, as the refusal says.

**TL-18 — cyrius.exe reads its working directory**
- On Windows, `CYRIUS_TEST_FILE` and `CYRIUS_TEST_DIR` are absolute, drive-rooted paths (they were relative, `.` for
  the directory); a test that read them as relative must take an absolute path. A drive-rooted unit inside the project
  (`cyrius test C:\proj\tests\x.tcyr`, `c:/proj/…`) gets its `test.cyml`; a drive-relative `C:x` or a rooted `\x` is
  still outside the project.

**TL-19 — distlib credits a named dep's included leaves to the dep**
- A regenerated `dist/<name>.deps` sidecar may shrink: a stdlib leaf that only a named dep's sidecar leaf brings by its
  own include (`boxed` through `tagged`) is no longer recorded as the bundle's own, and a sidecar left with no leaves is
  removed (`sidecar: removed dist/<name>.deps (no stdlib leaves remain)`). `cyrius distlib --check` reads a committed
  bundle that recorded such a leaf as stale: regenerate with `cyrius distlib` and commit dist/.

**TL-20 — `cyrius audit`'s fmt stage asks `cyrfmt --check` (D26)**
- A source using the accepted 4-space continuation step now passes `cyrius audit`'s fmt stage, as it passes
  `cyrfmt --check`; nothing that passed starts failing. The formatting contract is unchanged: canonical 2, 4 accepted,
  deeper rejected, and `cyrius fmt <file>` rewrites an accepted 4 as 2. A CI that wants the canonical form exactly
  compares `cyrfmt <file>` with the file itself.

**TL-21 — cyrlint sizes const- and enum-sized arrays and checks top-level bare arrays**
- `cyrius lint` / `cyrlint` (and `cyrius audit`'s lint stage) can report NEW overrun warnings: a constant-offset
  `load*/store*(&a + K)` past a bare local `var a[N]` whose N is a `const`, an enum constant with a literal value, or
  `+ - *` over those (N BYTES in a fn, rounded up to 8), and past a top-level bare `var g[N]` (N i64 slots, N × 8 bytes)
  in any fn whose local or parameter does not shadow the name. A CI step on `--strict` / `--exit-with-count` turns red
  on them. Each is a real overrun: for slots declare `var a: i64[N]`; mark an intended offset with
  `# lint: offset-ok` on the call's line.

**TL-22 — `cyrius header` and a `: stack` enum's return (D23)**
- A public fn returning `: Result`, `: Option`, `: Tagged` (or the file's own `enum E: stack`) is now
  `cyr_val2 f(..);   /* returns Result: the tag in w0, the payload in w1 */` under
  `#if defined(__x86_64__) && !defined(_WIN64)`, with a named comment and no prototype on aarch64 (cycc returns the
  pair in x0:x2, not C's x0:x1) and Win64. C code that called such a fn through the old `cyr_val` prototype read the
  tag alone: regenerate the header and read `.w0` (the tag) and `.w1` (the payload); on aarch64 and Win64 wrap the fn
  in one that writes through an out-pointer.
- A public fn whose signature says a word — no annotation, or a word type such as `: i64` — but whose body returns a
  stack enum's pair (`return Ok(x);`, or `return g(..);` of such a fn of the same file) makes `cyrius header` exit 1,
  with ``error: cyrius header: '<f>' returns a `: stack` enum's (tag, payload) pair through '<ctor>(..)', which its
  signature does not declare …`` on stderr; the rest of the header is still printed. Declare it `: Result` /
  `: Option` / `: Tagged`, or make it private / `_`-named. A build step `cyrius header f.cyr > f.h` under `set -e` fails
  there. In this tree that hits lib/result.cyr (`ok_via`, `err_via`) and sources of bayan, mabda, sigil, vani and yukti
  (their `: i64` / unannotated `_r` and `*_err_*` wrappers).

**TL-23 — `cyrius header` refuses a SIMD vector return (D24)**
- A public fn returning a vector type (`f64v2`, `f32v4`, the 128-bit integer vectors, `f64v4`, `f32v8`) makes
  `cyrius header` exit 1 with ``error: cyrius header: '<f>' returns '<type>': a SIMD vector return, which no C11 return
  type carries; no prototype written``; the rest of the header is still printed. It printed `cyr_val f(..)`, which C
  read from the wrong register. Mark such a fn private, or generate the header from a file without it. lib/simd.cyr has
  80 such fns, so `cyrius header lib/simd.cyr` exits 1.

**TL-24 — a signalled `cyrius` cleans up and exits 128+N**
- A `cyrius` run stopped by SIGTERM, SIGINT or SIGHUP while a compile runs stops the compiler it started, removes its
  scratch and private temp dir, and EXITS 128+N (143 / 130 / 129) instead of dying by the signal. `$?` reads the same
  number, but a parent inspecting the wait status sees WIFEXITED, not WIFSIGNALED: bash's "the child died of SIGINT, so
  stop the script" rule no longer fires for a Ctrl-C'd `cyrius` inside a non-interactive loop. A script that must stop
  on Ctrl-C checks `[ $? -eq 130 ]` itself. A signal ignored when the CLI starts (nohup) stays ignored; SIGKILL still
  leaves scratch for check.sh's reaper; Windows is unchanged.
- A `.tcyr` or tool that includes `cbt/build.cyr` without `cbt/cyrius.cyr` must `include "cbt/sigclean.cyr"` before it
  (cbt/build.cyr now calls its `_cbt_scratch_track` / `_cbt_child_track`).

**TL-25 — cyrius-lsp diagnostics**
- Editors now receive publishDiagnostics on the URIs of included files (an error in `inc.cyr` shows in `inc.cyr`, not
  at the same line of the file you opened), empty lists that clear a file a recompile no longer names, a range that
  starts at cycc's column, and diagnostics for `.tcyr`, `.bcyr`, `.fcyr`, `.scyr` and `.smcyr`. Nothing to configure.
- `cyrius check --no-redirect` is new: with `--with-deps`, it checks the given file itself, never `src/main.cyr` in
  place of a file with no `include`. `--with-deps` alone is unchanged. The server falls back to the old run when the
  project's pinned CLI predates the flag.

**TL-27 — CRLF checkouts of a committed `lib/` are named (D10)**
- Nothing that verified changes: rc and verdicts are the same, and a CRLF checkout still fails `deps --verify` and
  `--locked` (the lock proves the exact bytes). The failure now says so —
  ``FAIL: lib/x.cyr (hash mismatch — CRLF checkout: add `lib/** -text` to .gitattributes)`` and one `note:` — and when
  every `--locked` difference is a CRLF checkout, its remedy is the `.gitattributes` line, not "run `cyrius deps`". A
  project that commits lib/ and runs CI on Windows (Git for Windows defaults to `core.autocrlf=true`) adds
  `lib/** -text` to `.gitattributes`, commits it, and checks lib/ out again; do not re-lock the converted bytes.
- `cyrius init` writes a `.gitattributes` holding `lib/** -text` (an in-place init skips an existing one). `cyrius port`
  creates `.gitattributes`, or appends `lib/** -text` to an existing one that lacks it (its other lines kept).

**TL-28 — the pin drift check on every host; `--pie` refused on Windows (D5)**
- On Windows and macOS, a build in a project whose `[package] cyrius` pin differs from the compiler's version now
  prints `warning: cyrius.cyml pins X but cycc is Y — toolchain drift (snapshot may be stale; set
  CYRIUS_NO_WARN_PIN_DRIFT=1 to silence)`, and a build under `cyrius build --strict-pin` / `CYRIUS_STRICT_PIN=1` FAILS
  there on drift (rc 1, nothing written), as it always did on Linux. Bump the pin or the toolchain; silence the warning
  with `CYRIUS_NO_WARN_PIN_DRIFT=1`.
- `cyrius build --pie` from the Windows CLI is rc 1:
  `error: --pie is not available from the Windows CLI: cycc.exe emits PE only, which has no --pie mode …`. It wrote the
  same image as a plain build; drop the flag. (`--pie` on macOS still writes a plain Mach-O at rc 0 — filed for 6.7.13.)

**TL-30 — the aarch64 Linux CLI refuses `--agnos` and the x86_64 bare-metal target (D6)**
- On an aarch64 Linux host, `cyrius build --agnos`, `cyrius build --target=x86_64-bare-metal-elf` and
  `cyrius run --agnos` exit 1 with `error: --agnos is not available from the aarch64 Linux CLI: its cycc emits aarch64
  only (build agnos / x86_64 bare-metal images on x86_64 Linux)`, nothing written. They wrote an aarch64 binary at rc 0
  (never the requested artifact). Build agnos and x86_64 bare-metal images on an x86_64 Linux host.
  `--target=aarch64-bare-metal-elf` is not refused there.
- The aarch64 Linux CLI's progress line says `[aarch64]` (it said `[x86_64]`); a script that matched the old label
  changes. ⚠ Not changed yet: `cyrius build --win` on that host still writes an aarch64 ELF named `.exe` at rc 0 (filed,
  High, 6.7.13) — do not build Windows images there.

No block for the lane's other bites: TL-1 (comment, doc and gate text only; cycc and the CLI byte-identical); TL-2
(cyrius's own gate names the legs it cannot run); TL-5 (`cyrius init` / `port` / `sign-efi` `--help` and `-h` print
their usage at rc 0 where they failed; every other `cyrsign-efi` `-` token is still refused); TL-26 (programs/wc.cyr, a
demo); TL-29 (cyrius's own cross-OS script); TL-31 (cyrius's dead-code floor fixture).

#### Folds

**bayan 1.6.0 (refolded from 1.5.14)**
- No public fn added, removed or answering differently; `bayan_cyml_parse` is faster (0.39×). Nothing to migrate.

### 6.7.11

Break 2, repair 1. Each block names its CHANGELOG [6.7.11] bite; the decisions are the user's (2026-10-13, D1–D45).
The changes that went beyond a decision's text are filed for confirmation in 6.7.12
(`docs/development/issues/archived/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md`).
⛔ **yantra:** its own `cyrius distlib` is refused on the 6.7.11 CLI (`lib/ws.cyr` / `lib/ws_server.cyr` declare the same
`WS_*` constants, a tie D26 refuses) until 6.7.12 fixes `lib/` — or its bundled module includes `lib/ws.cyr` itself.
⚠ **x86_64:** `rd(mkv(..))` / `rd(*pv)` into a `*V` parameter compile and fault in 6.7.11 (refused through 6.7.10; fixed first
in 6.7.12) — bind the vector to a local and pass it, or pass the pointer.

#### Multi-value receives and returns

**RET-1 — a body ending in an infinite loop is provably one value**
- `var a, b = f();` (or `var t: (i64, i64) = f();`, or `a, b = f();`) where `f`'s body ends in `loop { }`,
  `while (1) { }` or `do { } while (1);` and every `return` in it returns one value now stops compiling: "multi-value
  destructure binds 2 names, but 'f' returns 1 value - bind it to one name". The second name was a register `f`
  never wrote. Bind one name (`var a = f();`). A final loop that a `break` can leave is not judged (the body can
  fall off its end), and neither is a non-literal condition such as `while (true)`.

**RET-2 — an undeclared fn's provable value count is checked**
- A destructure, a tuple capture or `a, b[, c] = f();` that binds a different number of names than an UNDECLARED `f`
  provably returns (every `return` is `return (..);` of one arity, and the body is left only through them) now
  stops compiling: "multi-value destructure binds 3 names, but 'dm' returns 2 values", "cannot capture 'dm' into
  tuple (i64, i64, i64) - it returns 2 values". More names read a register the call never wrote. FEWER names are
  refused too — `var q, r = h3(..);` with `h3` returning `(a, b, c)` computed the right two values on 6.7.10 and is
  now "binds 2 names, but 'h3' returns 3 values", as the declared spelling (`fn h3(..): (i64, i64, i64)`) already
  refused it. Bind every value (`var q, r, _z = h3(..);`) or capture them in a tuple of the right arity. A fn that
  mixes arities, or whose body can fall off its end, is not judged.

**RET-3 — a fn declared `: (T1, T2[, T3])` returns its values**
- In a fn declared `: (T1, T2[, T3])`, a `return` is now one of: `return (a, b[, c]);` of the declared arity,
  `return t;` of a tuple local, or a whole forwarded call returning as many values (`return g(x);` with `g`
  declared, or provably returning, that arity; a fn pointer or `callptr` call is accepted unjudged). Anything else
  stops compiling with "'f' returns 2 values - return (a, b)" (or "... 3 values - return (a, b, c)"): a single value
  (`return 5;`, `return x?;`, `return t.0;`, `return (5);`), `return p;` of a struct local, a bare `return;`, a
  literal of another arity, and a forward of a one-value callee (`return one(x);`), a struct callee (`return mk();`)
  or another arity (`return g3(x);` from a 2-value fn). Each left the caller reading a stale register for the
  values not written. Write `return (a, b);` — for a struct local, `return (p.a, p.b);`.

**RET-4 — a destructure binds a struct callee's register words only**
- `var a, b = f();` where `f` is declared to return a struct over 16 B, `var a, b, c = f();` where it returns a
  9-16 B struct, and `var a, b = f();` where it returns a struct of 8 B or less or a `Str` now stop compiling ("cannot
  destructure 'f' - it returns struct 'Q', which is not in registers", "cannot destructure 'f' into 3 names - it
  returns struct 'P', whose 2 words are its return registers - bind 2 names", "... returns 1 value"). The extra
  names read registers the call never wrote (over 16 B the struct comes back through a hidden pointer). Bind the
  struct to one name (`var q = f();`) and read its fields. `var a, b = f();` from a 9-16 B struct keeps working
  (its two words).

**RET-5 — a multi-value call is not a struct value**
- A call returning several values — declared `: (T1, T2[, T3])`, or undeclared with every `return` `(a, b)` — used
  where a named struct is expected now stops compiling: as a by-value struct argument (a method's, a named one, at
  top level), as a struct-typed declaration's initialiser (`var p: P = mk(..);`, at top level too), stored into a
  struct field (`h.p = mk(..);`) or assigned to a struct variable (`p = mk(..);`, a classic-`for` step too) — "a
  multi-value call 'mk' is not a struct 'P' argument - bind it first: `var a, b = mk(..);`" (and "does not
  initialize struct 'P'", "is not stored into a struct 'P' field", "is not assigned to struct 'P'"). Each crashed
  (the first value taken as the struct's address) or built the struct from the first value alone. Bind the values
  and build the struct — `var a, b = mk(3); var p = P { a, b };` — or declare the callee `: P` and return a `P`
  local. A `*P` destination and a `Str` handle are unchanged (they take the first value).

**RET-6 — a `: stack` pair method used above its `impl` is a pair**
- `var v = p.m(..);`, `x = p.m(..);` or `store64(&s, p.m(..))` (any one-slot store), where `m` is an impl method
  returning a `: stack` pair (`Result` / `Option` / `Either`, a user `: stack` enum) and its `impl` block sits BELOW
  the caller, now stops compiling — "a `: stack` enum returns two values — bind both" — as it already did with the
  `impl` above. The bind kept the tag and dropped the payload. Write `var t, v = p.m(..);` or `p.m(..)?`. (`p.m(..)?`
  above the impl, which crashed, now propagates.) Not covered yet: a method the impl inherits from its trait's
  DEFAULT body — keep that trait and impl above the caller.

**RET-7 — a `: stack` pair is not a struct-literal element**
- A struct literal one of whose elements is a call returning a `: stack` pair — `P { f(x), 3 }`, `P { a: f(x), .. }`,
  a global's `var G = P { f(x), .. };`, a value filling a nested struct field — now stops compiling ("bind both"). The
  element held the tag, not the payload. Bind first — `var t, v = f(x); var p = P { v, 3 };` — or write `P { f(x)?, 3 }`
  to propagate the Err. Arguments (`is_ok(f(x))`, `g(f(x))`) and operands (`f(x) == 0`) are unchanged: they read the
  tag, as documented.

**RET-8 — a local's struct receive: parentheses are transparent, and an annotation is never overridden**
- `var x: <scalar> = f(..);` inside a fn (i64, u8, i32, f64, f32, bool, u128, a slice, cstring, an enum, `Result`,
  `Vec`, …), where `f` is a free or generic fn declared to return a struct over 8 B (not `Str`), now stops compiling:
  "cannot initialise 'x: i64' from 'f', which returns the struct 'P2' - declare 'x: P2' or bind a field". It made x
  the struct behind its annotation (`x.b` compiled; a `u8` held 333). Declare the struct (`var x: P2 = f(..);`) or
  bind a field (`var x: i64 = f(..).a;`). A method or operator call, a struct of 8 B or less, a `Str` and a
  top-level global are not affected.
- `var x = (f(..));` (an untyped local, the call wrapped in parentheses, `f` returning a struct over 8 B) now
  receives the struct, exactly as `var x = f(..);` does. It held the struct's first word, so `x.a` was refused and
  `dq(x)` into a by-value struct parameter crashed; code that used `x` as that word now has the struct — `x + 1`
  dispatches `Q_add` (refused when there is none: "refusing to emit binary with 1 reachable undefined function(s)"),
  where it added 1 to the first word (4 on 6.7.10 for a `{3, 4}` struct). Read the field you meant: `var x =
  f(..).a;` or `x.a`.

**RET-9 — an `async fn` returning several values is refused by name**
- None in the tree (no async fn returns several values). For a consumer: `async fn f(): (T1, T2[, T3])`, and
  `return (a, b);` / `ret2(a, b)` / `return ret2(a, b);` in an `async fn`, now stop compiling — "`async fn f`
  returns 2 values, and a Future carries one i64 - return a pointer to a struct holding them". The second value never
  reached the awaiter (and `rethi()` after `await` read a stale register on a memoised or reactor-driven force).
  Return a pointer to a struct (or a heap block) holding both, or split the fn.

#### Call arguments

**ARG-1 — a struct result through `fncallN(&f, ..)` / `callptr(&f, ..)` is that struct**
- A call through `fncall0`..`fncall8` or `callptr` whose callee is written `&f` (`fncall1(&mk3, 5)`, `callptr(&mk3,
  5)`) and whose `f` returns a struct is now that struct, as `f(..)` is — the hidden result pointer over 16 B and the
  register pair at 9-16 B are passed and received. Through 6.7.10 a struct over 8 B faulted (the callee wrote through
  its first argument) and an 8 B struct faulted since 6.7.10's handle line; those are right now with no source change.
- An OPERATOR on such a call dispatches as on `f(..)`: `fncall1(&mk1, 5) + 4` now calls `P1_add` (or is refused
  "undefined function 'P1_add'"), where it integer-added the struct's word (12 in the probe). For the old integer add,
  bind it first and add the field: `var p: P1 = fncall1(&mk1, 5);` then `p.a + 4`.
- A scalar receive `var n: i64 = fncall1(&mk3, 5);` reads the struct's first field (it crashed); an untyped `var x =
  fncall1(&mk3, 5);` now declares `x` a `P3` (`x.a` compiles), and `return fncall1(&mk3, a);` compiles in a fn returning
  `P3` (it was refused).
- Newly refused (each crashed before): at top level, a struct result over 8 B through a known callee — a statement, or
  a global initializer (`var g: P3 = fncall1(&mk3, 5);`; 9-16 B as a global initializer) — refused by name, as
  `mk3(5)`'s is: move the call into a fn. A declaration of ANOTHER struct type from such a call is refused: declare the
  callee's own struct.
- Unchanged: a callee held in a variable (`var fp = &mk3; callptr(fp, 5)`) — its result is one word, and a struct-typed
  receive binds it as a handle (the user's decision, 2026-10-13). That is right for a callee returning `*P3` and does
  not work for one returning a struct by value: receive a 9-16 B struct's two words (`var a, b = fncall1(fp, 5);`) or
  give the callee an out-pointer (`fn mk3o(a, out: *P3)`, then `var p: P3 = P3 { 0, 0, 0 }; var ig = callptr(fp, 5,
  &p);`). A parenthesised callee (`callptr((&mk3), 5)`) is still a callee in a variable (filed, 6.7.12) — write `&f`
  unwrapped.

**ARG-2 — a value-form vector local takes a vector, or nothing**
- Stops compiling: a value-form vector LOCAL (in a fn) declared or assigned from anything but a local of its type or a
  call declared to return it — `var v: f64v2 = callptr(fp, ..)` / `fncallN(fp, ..)` through a variable, `= 0`, `= 5`,
  `= load64(..)`, `= &w`, a scalar local or call, a method call (`s.mv()`), `*p`, and the same as an assignment
  (`v = 5`) or a for step. Each read wrong lanes (or faulted on PE). The refusal: "a value-form vector local is
  initialised only from a local of its type or a call declared to return it (by name, or fncallN / callptr with the
  callee written `&f`) - got `…`".
- Fix: declare the local bare (`var v: f64v2;`) and fill it (`store64(&v, a); store64(&v + 8, b);`, or a
  `lib/simd.cyr` maker), call the producer by name (`var v: f64v2 = mkv(41, 7);`), or give a target reached through a
  variable an out-pointer (`var ig = callptr(fp, &v, 41, 7);`). A `var v: f64v2 = 0;` written to zero a local becomes
  `var v: f64v2;` plus an explicit fill if the lanes must be zero.
- Starts working (no change needed): `callptr(&f, ..)`, `fncallN(&f, ..)` and `(f(..))` into a vector local are received
  whole on every target. Vector GLOBALS are unchanged (`= 0` only).
- Still refused, now by this rule (they read wrong lanes before): a method declared `: V` as the source, an
  explicit-instance generic `v = mkg<i64>(..)`, and `var v: f64v2 = *p;` with `p: *f64v2` — each filed for 6.7.12;
  until then bind through a by-name call or copy the lanes through `p`.

**ARG-3 — a fn parameter's type is read whole**
- Stops compiling: a fn parameter annotated with a token that is not a type — `fn f(a: 5)`, `(a: +)`, `(a: ;)`,
  `(a: "s")`, `(a: if)`, `(a:)`, `(a: *)`, `(cb: fn(i64))` (no `*`) — refused "expected a type for parameter 'a', got
  …". The token was ignored and the parameter was a plain word: delete the annotation, or write the type you meant. An
  unknown name inside `*fn( .. )` is refused as one in `a: T` is: declare or spell the type.
- Starts compiling: `p: **T` / `***T` (a pointer whose `p + 1` steps 8) and `cb: *fn(..)[: T]` parameters. A bare
  `a: *fn` is unchanged. No in-tree code (lib, programs, cbt, tests) was affected.

**ARG-4 — a pointer-to-vector parameter (`p: *f64v2`) is a pointer**
- A fn with a `p: *V` parameter (V a vector type) changes its calling convention: the pointer arrives in an integer
  register (as C passes a pointer), not as a vector value — an `#export`ed or C-called fn declared that way now matches
  C; one that relied on the old value-form arrival (it never worked through the pointer) must take `v: V` instead.
- Changes value: `rd(b)` with a vector local `b` passes `&b` (it faulted). Starts compiling: `rd(&b)` and any pointer
  argument into `*V`, and `fncall1(&rd, &b)` / `callptr(&rd, &b)` work.
- Stops compiling: a vector local of ANOTHER type into `*V` (an f32v4 into `*f64v2`, an i64v2 into `*i32v4`) — "cannot
  pass 'f' to a parameter of a different vector type in a call to 'rd'"; it faulted, or met "value-form SIMD arg type
  mismatch". Pass a vector of the parameter's type, or its address through an untyped or matching pointer.
- ⚠ On x86_64 a vector call result or `*pv` into `*V` (`rd(mkv(..))`, `rd(*pv)`) was refused by the value-form path's
  text; it now compiles and passes lane 0 as the address (139), as it already did on aarch64 / cx / PE — filed for
  6.7.12 as a question. Bind the vector to a local first (`var t: f64v2 = mkv(..); rd(t)`) or pass the pointer
  (`rd(pv)`).
- `p[1]` on a `*f64v2` parameter is refused with a `*f64v2` local's text (a vector element); step with `p + 1`.

**ARG-5 — parentheses around a whole argument into a by-value struct of 8 B or less**
- Stops compiling: a struct value of ANOTHER type wrapped in parentheses as an argument for a by-value struct parameter
  of 8 B or less (`bs1((t))`, `bs1(((t)))`, `bs1((mk(7)))`, `bs1((w.t))`), and a wrapped struct value as a tuple literal
  element (`((p), 1)`) — refused by name, as the unwrapped spellings are. Each passed / stored the other struct's first
  word. Fix: pass a value of the parameter's own struct, or a pointer (`bs1(&t)` converts), as for the unwrapped
  spelling.
- A wrapped value of the parameter's own struct, or a wrapped field / expression (`(t.w)`, `(x) + 1`), is unchanged; a
  generic carrier wrapped is ARG-5r.

**ARG-6 — a dereference of another struct's pointer into a by-value struct of 8 B or less**
- Stops compiling: a dereference of a pointer to ANOTHER struct as an argument for a by-value struct parameter of 8 B
  or less or a `Str` parameter — `take8(*pu)`, `take8((*pu))`, `take8(*gp())`, `take8(*w.pu)`, `take8(*(pu + n))`,
  `take8(*self)` in another struct's impl — "cannot pass 'pu' to a parameter of a different struct type in a call to
  'take8'" (over 8 B it was already refused). Fix: pass the pointer (`take8(pu)` converts and copies through it), or
  copy into the parameter's own struct first (`var s: S8; s.v = pu.u; take8(s);`).
- A dereference of the parameter's own struct (`take8(*ps)`) is unchanged; a generic carrier through a dereference is
  ARG-5r.

**ARG-8 — a pointer into a by-value struct of 8 B or less: an if-expression of pointers, an integer on the left**
- Changes value: a by-value struct argument of 8 B or less given an if-expression whose every branch is a pointer (of
  any steps: `t7(if (c == 1) { py } else { &s })`), or an integer plus a struct pointer with the integer on the left
  (`t1(m + pb)`, `t1(0 + pb)`, `t1(n + pb)`, `t2(n + pb2)`), now passes the struct the pointer points at — it passed
  the address's bits. Code that wanted the address in the parameter takes a `p: *S` parameter or an untyped value.
- Stops compiling: a pointer difference between `n + pb` (`pb` a pointer to a one-byte struct) and a pointer of another
  element size (`(1 + pb) - q32`) — "pointer difference of pointers with different element sizes"; it was a byte
  difference. Subtract plain addresses for a byte count (`var a = pb; var b = q32; a + 1 - b`).
- Loses a warning: `var r: *B1 = 1 + pb;`, `g = m + pb;` and `GB = 2 + pb;` are silent (they warned "assigning
  non-pointer to typed pointer"). No in-tree code was affected.

**ARG-5r — a generic struct carrier through a wrap or a dereference binds its T**
- Changes value: a generic struct carrier of 8 B or less given its argument in parentheses or as a whole dereference
  (`gw((w))`, `gw((mkw(-6)))`, `gw(*wp)` with `fn gw<T>(w: W1<T>)`, `w: W1<i32>`) now calls the instance (`gw$i32`);
  through 6.7.10 it called the i64 base and read the struct with the base's layout (a negative `i32` field tested
  non-negative). Code that leaned on the base call names it (`gw<i64>(..)`), which reads `W1<i64>`'s layout as before.
- Starts compiling: over 8 B, `gx((b))`, `gx(*bp)`, `gx((*bp))`, `gx(*gp())` (refused "a different struct type"
  before) call `gx$Pt`.

No block for the lane's other bites: ARG-7 (an integer constant passed to an `f64` / `f32` parameter now WARNS — "an
integer stored into an f64/f32 slot keeps its integer bits (write a float literal)" — and nothing stops compiling or
changes value; no in-tree site; a build that treats new stderr as a failure writes `3.0`, or `f64_from(n)` for a runtime
integer); ARG-9 (only the opt-in `CYRIUS_IR=3` output changes, from a wrong value to the right one); ARG-1r (a gate's PE
leg and row floor).

#### Struct copies and struct operators

**ST-1 — a dereference of a struct under 8 B reads exactly the struct**
- No source stops compiling. A dereference `*p` of a struct of 1..7 bytes now reads only the struct's bytes, and the
  rest of the one-word value is 0: a program that read the bytes past the object through the word — `load64(&G)` of a
  `var G: S3 = *p;`, a hash or `memeq` over the 8-byte cell, an untyped `var w = *p;` compared as an integer — sees 0
  there instead of whatever followed the object. Read the fields (`G.a`), or copy `sizeof(S3)` bytes.

**ST-2 — an assignment from a struct dereference copies the struct**
- `l = *p`, `G = *p` and `o.s = *p` with `p: *S` copy the whole struct, in every spelling (`(*p)`, `*(p + n)`,
  `*gp()`, `*w.p`), at top level and in a for step; through 6.7.10 they stored the first word and left the rest stale.
- `q = *p` with `q` a `*S` (or a handle) now writes the struct into q's POINTEE instead of rebinding `q` to the
  struct's first word. A program that used `q = *p` to load a pointer stored in the struct's first field must write
  `q = p.first` (or dereference an untyped `*x`).
- Stops compiling: `l = *pu` / `o.s = *pu` / `q = *pu` with `pu` a `*U` of a different struct (it stored U's first
  word) — *cannot copy 'pu' into a variable of a different struct/vector type* / *... into a struct field of a different
  struct type*. Copy the fields, or retype the pointer.
- The false "assigning non-pointer to typed pointer" warning on `l = *p` / `q = *p` is gone.

**ST-3 — a struct-typed field from a `*S` global, a `: *S` call or a `*S` field copies the struct**
- `o.s = GP`, `o.s = gp()` (`fn gp(): *S`, or a method declared `: *S`), `o.s = w.p` and `o.s = GP + n` into a
  struct-typed field copy the struct the pointer points at, directly, through a `*O`, at top level and in a for step;
  through 6.7.10 the field's first word held the address. Code that read the address back out of `o.s`'s first word
  must keep the pointer in a `*S` field or local.
- Stops compiling: the same sources typed `*U` of a different struct into an `S` field — *cannot copy 'GU' into a
  struct field of a different struct type: 's'*. Copy the fields, or retype the pointer.

**ST-4 — a generic call declared `: *T` is a struct source**
- `l = gpg<S>()` (with `fn gpg<T>(): *T`) copies the struct (it stored the address); `*gpg<S>()` as a declaration, an
  argument or either operand reads the struct (it crashed), in a fn, inside another generic's instance and at top
  level. An inferred call is a struct source when its arguments infer T = S (`gpi(p)` with `p: *S`, `gpv(s)` with `fn
  gpv<T>(x: T): *T`); `gpi(&s)` infers T = i64 and runs the base, unchanged.
- Newly compiling: `gpg<S>().v` (it was refused *it does not return a struct*).
- Stops compiling: a generic `: *T` instance of a DIFFERENT struct into an `S` destination (`l = gug<U>()`, `var q: S =
  *gug<U>()`, `o.s = gug<U>()`, `take(*gug<U>())`, `a - *gug<U>()`) — refused by name, naming the call (it stored or
  passed U's word); and a declaration-zone global over 8 B from a generic fn declared BELOW it (`var Z: S16 =
  *gpg<S16>();` above `gpg`) — *cannot copy-init 'Z' from a dereference of a global or fn declared below it (declare it
  first): 'gpg'* (it crashed). Declare the fn first, or move the declaration after the first statement.

**ST-5 — a top-level copy-init from a field reached through a pointer copies**
- `var G: S16 = P.s;` (P a `*W` global), `= (P.s)`, `= gp().s` (`fn gp(): *W`), `= VV.p.s` (through a `*W` field) at
  top level, over 8 B, now give G its own inline copy of the field (it was a one-slot global holding the field's first
  word, and the first `G.v` crashed).
- Stops compiling (both crashed before): such a declaration whose leaf is a different struct type; and one in the
  leading declaration block whose `*T` global, holder or callee is declared below it — *cannot copy-init 'G' from a
  global declared below it (declare the source first)* / *... from a field of a call to a fn declared below it (declare
  the fn first)*. Declare the source first, or move the declaration after the first statement.

**ST-6 — a fn returning a struct of 8 B or less checks the struct it returns (D3)**
- Stops compiling: in a fn declared `: S` with S of 8 bytes or less, `return x;` where x is a value of ANOTHER struct
  (a local, a by-value parameter, a global, `(u)`, a call — `return mk();` included —, a field, a method or operator
  result, `*pu`), a `*U` of another struct, or a handle of another struct (6.7.10 returned that struct's bytes on
  purpose) — *a fn returning the struct `S8` takes a value of that struct, or a pointer to one — got `u` (a `U8`)*.
  Build or copy a value of the declared struct: `var s: S8; s.v = u.u; return s;`.
- Computes differently: `return p;` with `p: *S8` a LOCAL returns the struct p points at (it returned the address),
  as a `*S8` parameter already did.

**ST-7 — `return E;` with E a pointer to the struct returns the struct it points at, at every size (D1)**
- Computes differently: in a fn declared `: S` of 8 bytes or less, `return GP;`, `return gp();`, `return w.p;` (a `*S`
  global, a `: *S` call or method, a `*S` field) and `return GP + n;` return the struct the pointer points at (they
  returned the pointer's word as the struct). Code that smuggled an address out through a small struct return must
  return the pointer from a `: *S` fn instead.
- Newly compiling: the same over 8 bytes, and `return *GP;` / `return *gp();` there.
- Stops compiling: returning a `*U` of another struct (at 8 B or less it returned the pointer word; over 8 B the old
  refusals are now this one, by name). Return a value of the declared struct.

**ST-8 — a struct value into a typed `*S` global copies into its pointee (D2)**
- `GP = v` with `GP` a `*S` global and `v` a struct value of S (a local, a value global, a by-value parameter, a call,
  a field, `*p`, a method or operator result) writes `*GP`, as a `*S` local or parameter destination does; through
  6.7.10 it stored v's first word into GP itself. A program that used it to load a pointer kept in the struct's first
  field must write `GP = v.first`. A zero-size struct copies nothing and keeps the pointer.
- Unchanged: `GP = q` from another `*S` or a handle, `GP = &x`, `GP = 0`, `GP = alloc(..)` rebind.
- Stops compiling: `GP = u` with `u` of another struct (*cannot copy 'u' into a variable of a different struct/vector
  type: 'GP'*), and at top level `GP = mk()` / `GP = a.m()` / `GP = a + b` whose result is over 8 B (*... a struct
  result needs storage in a fn's frame — call it inside a fn*; it stored the first word as the pointer). Move the
  statement into a fn.

**ST-9 — `*p = v` through a `*S` copies the struct (D4)**
- `*p = v` with `p` typed `*S` (a local or parameter, `*self`, `*GP`, `*(p + n)`, `*gp()`, `*w.p`) copies exactly
  sizeof(S) bytes: over 8 B it wrote the first 8 bytes only; under 8 B it wrote 8 bytes over whatever followed the
  object; a zero-size struct now writes nothing.
- `*p = q` with `q` a `*S` (or a handle) copies q's struct (it stored the pointer).
- `*p = 0` / an untyped word writes sizeof(S) bytes, at most 8 (it wrote 8). A program that used `*p = x` to write a
  full word through a pointer to a struct under 8 bytes must use `store64(p, x)`.
- Stops compiling: `*p = u` with `u` of another struct (it stored u's first word) — *cannot copy 'u' into a variable of
  a different struct/vector type: 'p'*; and `*p OP= v` through a `*S` (it combined the first word) — *compound
  assignment to the struct 'p' points at is refused ...*. Write `*p = *p + b`, or the field (`p.v += b`).

**ST-10 — an untyped declaration takes a leading call's struct only when the call ends it**
- Stops compiling: `var r = f(..) OP x;` followed by `r.field`, or `return r;` from a struct fn, where `f` returns a
  struct and `OP` returns an integer or is a comparison — *no struct type in scope for 'r'* (it read the integer as
  the struct and crashed). Use the integer as an integer (`r + 1`), or bind the struct first (`var a = f(..);`).

**ST-12 — an integer operator's result is an integer**
- Computes differently: `n OP s + x` (and `(n < s) + x`, `(~s) + x`, `(n & s) + x`, ...) with an integer left operand,
  a struct `s` and an `S_add` / `S_sub` / `S_mul` / `S_div` defined called that operator fn on `s` and discarded `n OP
  s`; it is an integer expression now (`n OP s` is first-word arithmetic, as before).
- Newly compiling: the same with no `S_op` defined (it was an undefined-function refusal).
- ⚠ The right-operand form `t + (n - s)` over 8 B passed `&s` (the leaked slot) and now passes the integer, as `t + 5`
  does; into a `*S` parameter of 8 B or less it passes the integer as the pointer, as `t - 5` does — both are an integer
  into a struct parameter. Name the struct operand if the operator call was meant.

**ST-13 — unary minus on a struct is integer negation of its word (D38)**
- Computes differently: `-s OP t` with a struct `s` and an `S_op` defined called `S_op` (over 8 B on `s` itself, the
  minus ignored; at 8 B on the negated word as the struct); it is an integer operation on `-s`'s word now, as `-w.s +
  t` already was. Nothing is refused.
- A declaration `var r: S = -s - t;` that relied on the dispatch's struct result is now a struct from an integer — a
  handle holding that integer (`r.f` faults). Write the operator call on a struct value: `var r: S = mk(-s.v) - t;`, or
  `(z - s) - t`.
- `t + -s` over 8 B passes the negated word (it passed `s`, the minus dropped) — into a `*S` parameter that is an
  integer as a pointer.
- At top level `-Gs - Gt` into a `*S1` operator was refused (no frame) and now compiles as integer arithmetic.

**ST-15 — a tuple literal returned from a fn declared to return a named struct is refused (D39)**
- Stops compiling: `return (a, b);` (or three values) in a fn declared `: S` for a named struct `S`, at any size — *a
  fn returning the struct `S` returns that struct — `(a, b)` is a tuple, another type*. The 9-16 B form returned the
  right words, by register coincidence; the 8 B form dropped `b`, the > 16 B form never wrote the result. Build the
  struct and return it (`var r: S = S { a, b }; return r;` — a struct literal is not a return value), or declare the
  fn `: (i64, i64)` and receive `var a, b = f();`.
  `ret2(a, b)` in such a fn still compiles (filed separately).

**ST-16 — `return f(..) OP x;` in a 9-16 B struct fn, OP not dispatching, is refused (D40)**
- Stops compiling: `return f(..) OP x;` in a fn returning a 9-16 B struct, `f` returning that struct and `OP` a
  comparison, `& | ^ % << >>` or `&& ||` — *... got `f`* (it returned the operator's value with a stale second word).
  Return a struct value (`var r = f(..); ...; return r;`). `return f(..);`, `return (f(..));` and a dispatching `return
  f(..) + p;` are unchanged.

**ST-18 — an untyped binding takes the struct of every whole struct result (D42)**
- Computes differently: an untyped `var c = a.m1().m2();` (a method chain of 8 B or less), `var c = if (..) { s1 } else
  { s2 };` (struct branches of 8 B or less) or `var c = (a OP b);` / `(a.m())` (a 9-16 B result in parentheses)
  declares `c` the struct, so `c + 1` dispatches `S_add` (refused when there is none; into a `*S` parameter the integer
  is the pointer, as with the annotated form) instead of adding to the first word, and `take(c)` passes the struct (the
  16 B wrap passed its first word as the address). Write `c.v + 1`, or annotate a scalar (`var c: i64 = ...;`) to keep
  the word.
- Newly compiling: `c.field` on those bindings.

**ST-20 — a free struct call in parentheses is the nested-literal element the unwrapped call is (D44)**
- Newly compiling: `H { 7, (mkq(4, 9)), 8 }` and every same-struct wrapped call as a nested literal element, at every
  size.
- Stops compiling: a parenthesised call returning a struct of 8 B or less with ONE leaf, of a type other than the nested
  field's, as a nested literal element (`H { 7, (mko(5)), 8 }` with `q: Q` and `mko` returning `O`) — *cannot copy
  'mko' into a struct field of a different struct type: 'q'* (it stored the call's word into the field unchecked, as
  the unwrapped call never did). Write the field it meant (`H { 7, mko(5).a, 8 }`: the one leaf from O's field), or
  return the field's struct.

**ST-21 — the `#derive` scanner decodes a nested derived struct field and skips any value whole**
- A `T_from_json_str` over a document with a nested `#derive(Serialize)` / `#derive(Deserialize)` struct field, or with
  an unknown key holding an object, an array or a string containing `,` or `}`, now fills the nested field and every
  field after it, and an inner or unknown object's keys no longer overwrite the outer struct's fields of the same name.
  A consumer that declared the nested field LAST (the old workaround) or decoded through the pairs form
  `T_from_json(bayan_json_parse(..))` keeps working. A nested value that is not an object leaves the field 0; a field
  typed with a struct no Serialize / Deserialize derive registered (accessors-only, hand-written codecs) is skipped, as
  before.
- Every derive-using program's bytes change (`_cy_json_skipval` is emitted for every derived struct).

#### Generics and the frontend

**GF-1 — a generic instance at `f64` and one at a struct named like a scalar are two instances**
- An `f64` generic instance is now named `Base$f64` (it was `Base$i`), and an instance at a struct named exactly `i8`
  / `i16` / `i32` / `i64` / `f64` is `Base$.<name>` (it was `Base$<name>`). The names show in the execution-coverage
  dump (`CYRIUS_COVERAGE`), `CYRIUS_DCE_VERBOSE`, diagnostics and a shared object's exported symbols. A tool that
  matches those names by their full spelling updates; `cyrius coverage` cuts at the first `$` and is unaffected.
- A program with a `struct i` (or a struct named like a scalar) and an `f64` instance of the same generic now runs the
  right body for each: through 6.7.10 the second instantiation ran the first's body. Nothing stops compiling.

**GF-2 — a bound with no `impl … for i64` is met at `f64`**
- A bounded generic METHOD called at `f64` with no `impl … for i64` (`p.bm(h)` with only `impl Show for f64`) now
  returns its impl's result where it returned 0 (the dead stub ran).
- The free spellings `gb(h)` / `gb<f64>(h)` were refused and now compile. A dummy `impl … for i64` added only to get
  an f64 call past the bound can be dropped (an i64 call still needs the real one).

**GF-3 — a generic method call `p.m(x)` reaches the instance its arguments bind**
- Code that compiled now stops compiling (decision D6): a generic method called with a scalar where its type parameter
  is used as a struct (`p.pick(9)`, an `f64` too), or where i64 fails its bound (`p.bm(7)` with only `impl Show for
  f64`); a bounded generic method called with a struct that lacks the impl (`p.bm(r)`); and a scalar call of a generic
  that forwards its T into such a method (`o(p, 5)` with `fn o<T>(p: P, t: T) { return p.pick(t); }`, or with the
  receiver a field chain or a call's result: `h.p.pick(t)`, `mk().pick(t)`, `h.gp().pick(t)`). Each returned 0 or ran
  the i64 body on a struct's address; the error names the fn. Pass a struct of the type the body reads, or drop the
  call.
- A generic method called with a struct (or through `self: V`, or forwarded through a generic) now runs its instance
  where it returned 0 (or faulted, for a `: V` return): a program that relied on the 0 changes value.

**GF-5 — a generic call's own result binds another generic's `T`**
- A generic called with another generic's call result that returns a struct, where the outer generic does not use its
  `T` as a struct (so the call compiled at its i64 base), now calls the struct instance: `g(id(p))` calls `g$Pt`, so
  `sizeof(T)` and every `T`-typed local follow the struct (`sizeof(T)` was 8, now the struct's size). If the i64 base
  was what the program meant, call `g` with an i64 (an untyped word), not with a struct result.
- A nested f64 call into a generic defined below it (`gid(gid(h))`) is now an f64 (it was an i64, warned at a float
  operand).
- Every other shape (`gx(mk1(p))`, `g(mk1(p))`, nested, explicit inner) was refused and now compiles.

**GF-6 — an overload sibling with no definition never takes its base's call**
- An `--allow-undef` build whose overloaded call was routed to an undefined `<base>_str` / `<base>_int` sibling now
  runs the base (it trapped there).
- A program whose only reference to an undefined sibling is unreachable code now builds by default (the routed call
  made it reachable and the build was refused).
- In an `object;` unit, `base(s)` no longer binds to a `base_str` defined in ANOTHER object: call `base_str(s)` by
  name there. Defined siblings route unchanged.

**GF-7 — a `Vec<T>` annotation reads its `T` as a struct field does**
- Code that compiled now stops compiling (decision D9): a `Vec<..>` annotation — a var, a global, a parameter,
  `*Vec<..>` / `**Vec<..>`, a `*fn(Vec<..>)` parameter, `Vec<Vec<..>>`, `sizeof(Vec<..>)` — whose brackets hold
  anything but a type the field form takes: a tuple, an unknown or misspelled name (`Vec<Strr>`, `Vec<i8x>`; also
  `Vec<Str>` without lib/str.cyr included), a vector type, a slice, u128, a pointer element (`Vec<*Pt>`), an
  expression (`Vec<1 + 2>`), a second argument; and a declaration-zone global whose element is declared BELOW it (`var
  G: Vec<Pt>` above `struct Pt`: "declared after its use", as `var G: Pt` is).
- Each error names the variable. Fix the element — `Vec<i64>` for a handle of words (a `Vec<*Pt>` holds words either
  way), the struct's real name, the missing include — or move the struct above the global. The compiled program is
  unchanged where it still compiles.

**GF-8 — a program's own `struct slice` is what a fn-local `slice` / `slice<T>` names**
- A program that declares its own `struct slice` (or `struct slice<T>`) and uses a fn-local `slice` / `slice<T>`
  annotation as the BUILT-IN slice (`.ptr`, `.len`, `s[i]`; `slice_of(&s, ..)` then `s.len`) stops compiling: the
  annotation now names the program's struct, so the built-in fields are "unknown field 'len' on struct 'slice'" (it
  exited 14 through 6.7.10). Respell the built-in `[T]` (`var s: [u8] = 0;`).
- A program with no `struct slice` is unchanged. One that used the word for its own struct in a fn-local annotation
  now gets the struct (it was refused, or mistyped as the built-in).

**GF-9 — a `return` outside a fn body is refused by name**
- A top-level `return` — at the end of a program, or in a top-level `if` / loop / `switch` / `match` — no longer
  compiles: `return outside a fn body`. Delete a trailing `return 0;`, or write the early exit as `syscall(60, v);`
  (`sys_exit(v)`), or move the code into `fn main` and return from that. Nothing that compiled worked as written:
  x86_64 / PE ran on past the return, and aarch64 / cx hung at it.

**GF-12 — a const context's call of a `const fn` is checked like any call**
- A const context that calls another file's `private` const fn no longer compiles: `'pk' is private to its file`. The
  const contexts are a `const` (top-level or local), an array size, an enum value, `#assert` and a `case` label, and a
  parameter default naming one from another file. Mark the const fn `public`, or compute the constant in its own file
  and export the const.
- A `#deprecated` const fn called in a const context now warns, once per call site, as its run-time call always did.

**GF-13 — a const fn's arity in a const context is the run time's**
- A const-context call that passed one argument too many to a const fn with a generic struct parameter (`const N =
  pick(0, 1, 7);` for `const fn pick(p: Pair<i64, i64>, b)`) is refused: "a const fn called with the wrong number of
  arguments". Pass the arguments the fn declares (`pick(0, 7)`), as its run-time call always required. `pick(0, 7)`,
  refused before, now compiles.

**GF-16 — the value of `await f` is an untyped word**
- `(await f) OP n`, where `f` is declared `*T` with `sizeof(T) > 1`, now computes the integer sum (it scaled `n` by
  `sizeof(T)`): `(await f) + 1` with `f: *i32` is 6 where it was 9. lib/async's handles are untyped words, so only a
  hand-typed handle is affected (its declaration already warned "assigning non-pointer to typed pointer"). Keep Future
  handles untyped.

**GF-17 — `+| +? -| -?` are integer operators**
- An expression that continues after `+| +? -| -?` on a typed pointer (`(q +| n) + m`, `k + (q -? n)`) computes a
  different value: `m` / `k` are no longer scaled by `sizeof(T)`. Such a sum assigned to a `*T` now warns "assigning
  non-pointer to typed pointer", and `((p8 +| 1) + 1) - q32` is `n - p` (it was refused). Use `p + n` for a pointer
  step. Nothing in the tree writes the shape.

**GF-18 — a narrow scalar local is an integer, and `n + &x` is the byte pointer `&x + n` is**
- `w + p` with a narrow local `w` (`u8` .. `i32`) and a `*T` `p` (`sizeof(T) > 1`) now steps `w * sizeof(T)` bytes (it
  added `w` bytes).
- `var r: *T = w;` / `= w + n;` from a narrow local now warns "assigning non-pointer to typed pointer", as from an i64
  local.
- `(n + &x) - q` with `q` of another element size is now refused ("pointer difference of pointers with different
  element sizes"), as `(&x + n) - q` always was: for a byte count subtract plain addresses (the error's own hint: `var
  a = p;`). `var r: *u32 = 4 + &B;` no longer warns.
- `w - q` with a narrow local `w` newly compiles (an integer minus a pointer).

**GF-19 — cx calls `fn main` from the entry epilogue**
- On cx (`--target=cx` / `cycc_cx`), a program that defines `fn main` now runs it, and its return value is the exit
  code. A program that relied on cx skipping it (its exit was the last global's value) now exits with `main`'s return
  value.
- A program that calls `main()` at top level and does not exit explicitly now runs `main` twice on cx too, exiting
  with the second run's value, as it always did on x86_64 / aarch64 / Mach-O / PE. Write `syscall(SYS_EXIT, main());`,
  or leave the call to the epilogue.
- A .tcyr that keeps its asserts in `main` now runs them on cxvm; one that touches a host-only buffer (`mmap_anon`,
  `pipe`, `fstat`, `unlink`) can now fail there where it passed vacuously.

#### Infrastructure

**INF-5 — `CYRIUS_DCE=1` compacts a `kernel;` image and a `CYRIUS_WX=0` executable; a kept dead body's call into removed code is `ud2`**
- Only a build under `CYRIUS_DCE=1` changes; without the flag every image is byte-identical to 6.7.10's.
- A `kernel;` image (ELF32 multiboot1 and `CYRIUS_ELF64_KERNEL=1`) and a `CYRIUS_WX=0` executable now have their dead
  fns REMOVED, where 6.6.20 – 6.7.10 only NOP-filled them: the image is smaller, and `.bss` / `.rodata` sit lower by
  the removed bytes, rounded so the move is a multiple of 16 (an array keeps its 16-byte alignment; up to 8 zero bytes
  pad the end of `.text`). Every data address the code holds moves with the data, so nothing that computed correctly
  before computes differently (the filed `k.cyr`: ELF64 1,720 → 984 B, ELF32 1,536 → 800 B; a compacted multiboot1
  kernel boots under QEMU). A kernel that hard-codes its own layout — section addresses written into a linker script,
  a boot shim or a loader that assumed the DCE image matches the plain one — must take them from the image
  (`readelf -SW`), or build without `CYRIUS_DCE=1`. A `--pie` kernel and every aarch64 / PE / Mach-O / `shared;` image
  still decline compaction and NOP-fill, as before.
- The unreachable-fns note for these two layouts no longer says `compaction declined on x86_64 ELF (kernel;)` /
  `(CYRIUS_WX=0)`: with the flag unset it reads `set CYRIUS_DCE=1 to eliminate`, and under `CYRIUS_DCE=1` the build
  reports `dead code eliminated`. A script that grepped the decline note must look for the new text.
- On every x86 layout that compacts (the plain W^X executable included): a dead fn the compiler keeps because it cannot
  size one of its instructions (an `in` / `out` in an `asm` block) now holds `ud2; ud2; nop` (`0f 0b 0f 0b 90`) where it
  called or tail-called a removed fn, and 0 where it took a removed fn's address. Through 6.7.10 those bytes were a call
  into whatever had moved there (an unrelated live fn, or the body itself). The body is dead, so nothing executes it; a
  tool that disassembles or patches such a body now finds the sentinel (on the 6.7.11 corpus: 206 sites in 38 of 573
  `.tcyr`, nothing else changed). Any other kind of surviving rel32 aimed into removed code now refuses the build by
  name (`error: dead-code elimination: the rel32 at code offset N (opcode byte B) survives but aims into removed code,
  and only a call or jmp can be neutralised; refusing to emit`). No known source produces one; if a build meets it,
  build without `CYRIUS_DCE=1` and report it.
- `--allow-undef` + `CYRIUS_DCE=1`: a taken call to an undefined fn now dies SIGILL (132), as it does without the flag;
  compaction no longer rewrites FIXUP's `ud2` sentinel into `maxps` bytes (it died SIGSEGV, 139).

No block for the lane's other bites: INF-1 (the preprocessor's walks — the output is byte-identical); INF-2 (a gate
row only); INF-3 (cybs now refuses `nosuch(1);` and `fp(5);` by name — it compiled them to a binary that died with
SIGSEGV, and cybs builds only `src/` and `bootstrap/asm.cyr`); INF-4 (cybs's refusal text only — nothing that compiled
changes); INF-5r / INF-5r2 (docs).

#### Tools and the CLI

**TL-1 / TL-2 — the source tools build from a cyrius checkout's root**
- cyrlint, cyrfmt, cyrdoc, cyrius_api_surface and cyaudit now `include "src/frontend/lex_attr.cyr"` (the lexer's own
  attribute list), and cyrdoc and cyrius_type_audit `include "cbt/srcscan.cyr"` (the CLI's declaration reader). Through
  6.7.10 the first five included only `lib/` files, so a copy of `programs/<tool>.cyr` built beside any `lib/`. A
  script that compiles one of these tools from outside a cyrius checkout now fails on the missing include: build them
  from the checkout's root, as the tarball, install and CI paths do, or use the installed binaries. The tools' output
  is unchanged by TL-1.

**TL-2 — the source scanners see `const fn`, `Pair<i64, i64>` and a variadic tail**
- `cyrdoc --check` now sees a public `const fn`, `async fn` and `#deprecated("…") fn`; an undocumented one fails the
  check. Add its doc comment (or make it private / `_`-named).
- `cyrius type-audit` counts more public fns (every `pub` / `public` / `async` / `const` / `#inline fn` spelling, not
  only a line starting `fn `), so its coverage percentage drops where those fns are unannotated (this repo: 97 % →
  93 %). A CI floor on that figure may need annotations or a new floor.
- `cyrius api-surface`: a public `const fn` is now recorded, and a parameter with a generic type holding a comma
  (`p: Pair<i64, i64>`) counts as one (`pp/2`, was `pp/3`). A checked-in snapshot reads as new entries / changed
  arities against it: regenerate it (`cyrius api-surface --update`) and review the diff once.
- `cyrius header`: const fns get prototypes; a generic-typed parameter is one `cyr_val` (the old `cyr_val i64>` line
  did not compile); a variadic tail is `...` (`cyr_val va(cyr_val n, ...);`) and a fully variadic `fn f(...)` is
  `cyr_val f(void); /* variadic in cyrius: it reads no argument */`. Regenerate a checked-in header.

**TL-3 — cyrlint's overrun and write-length rules**
- `cyrius lint` / `cyrlint` can report NEW warnings: a constant `load*/store*(&a + K)` that runs past a bare local
  `var a[N]` (N BYTES in a fn, rounded up to 8), and a `syscall(SYS_WRITE|1, …)` / `sys_write` / `_aw_write` whose
  literal length argument is not the literal's byte count. A CI step on `--strict` or `--exit-with-count` turns red on
  them. Each is a real truncation or overrun: for slots declare `var a: i64[N]`, count a literal's UTF-8 bytes (`—` is
  3, `"\x1b[0m"` is 4, `é` is 2), and mark a deliberate offset with `# lint: offset-ok` on the call's line (it does not
  silence the write rule; `#skip-lint` silences both). Code that compiled still compiles and behaves the same.

**TL-4 — `cyrius distlib`: one owner rule, ties refused**
- `cyrius distlib` may refuse where it used to pick by file name: `'X' is undefined on every target, and more than one
  stdlib leaf could own it (a, b) — include the right leaf from a bundled module. Sidecar NOT written`, rc 1, no
  sidecar. Fix: `include "lib/<the right leaf>.cyr"` from a bundled module, so the verify has it in its unit.
- ⚠ The one tie in lib/ today is the nine `WS_*` constants, declared by both `lib/ws.cyr` and `lib/ws_server.cyr`
  (filed for 6.7.12): a bundle that reads one of them without including either leaf is refused until that is fixed —
  yantra 1.0.11's own `cyrius distlib` is (measured). Include `lib/ws.cyr` (or `lib/ws_server.cyr`) from the module that
  uses them.
- A regenerated sidecar may list the same leaves in another order: a dispatcher peer's constant that an agnos arm also
  declares (`O_*` in io, `PROT_*` / `MAP_*` in mmap, `CLOCK_MONOTONIC` in chrono) records `syscalls` first and the agnos
  leaf a round later, so `distlib --check` reads the committed bundle as stale (mabda's does). Regenerate
  (`cyrius distlib --all`) and commit `dist/`.

**TL-7 — bench-history.csv's file-size row is `size/cycc_bytes`**
- cyrius's own `bench-history.csv` names its file-size row `size/cycc_bytes` (every historical `size/cc5_bytes` row
  renamed), and BENCHMARKS.md prints the size rows in bytes (`2,114,376 B`). A script that reads cyrius's CSV by the old
  name reads the new one. No consumer-facing change.

**TL-8 — `CYRIUS_POISON` takes `0` / `1` only**
- A build under `CYRIUS_POISON=0` or an empty `CYRIUS_POISON=` is no longer poisoned (before 6.7.11 any set value
  turned the mode on); a build under any other value (`CYRIUS_POISON=yes`, `=true`, `=no`) stops compiling:
  `error: CYRIUS_POISON must be 0 or 1 (or unset): <v>`, rc 1, nothing written — as `CYRIUS_BOUNDS` and
  `CYRIUS_COVERAGE` already do. Use `CYRIUS_POISON=1` (or `cyrius fuzz --poison`) to turn it on; unset it, or set `0`,
  for a normal build. A CI environment that exported the variable with a word must change it.

**TL-9 — `cyrius pulsar` and the first cx use always build the default compiler**
- `cyrius pulsar` and the on-demand `build/cycc_cx` / `build/cxvm` builds no longer see `CYRIUS_POISON`,
  `CYRIUS_BOUNDS`, `CYRIUS_COVERAGE` or `CYRIUS_COVERAGE_FILE` from the shell: an exported switch no longer produces a
  mode-built compiler or tool (and `CYRIUS_COVERAGE=1` no longer refuses them). User compiles (`cyrius build` / `test` /
  `fuzz` / `run` of your own program) still get the switches. To build a mode compiler on purpose, invoke the compiler on
  `src/main.cyr` directly with the variable set.

**TL-10 — the Windows and macOS CLIs refuse `--agnos` and the bare-metal targets**
- On a Windows or macOS host, `cyrius build --agnos …`, `--target=x86_64-bare-metal-elf`,
  `--target=aarch64-bare-metal-elf` (and `cyrius run --agnos`) stop with rc 1, writing nothing:
  `error: --agnos is not available from the Windows CLI: cycc.exe emits PE only (build agnos / bare-metal images on
  Linux)` (macOS: `… from the macOS CLI: cycc emits Mach-O only …`). They never produced the requested image there — a
  PE or Mach-O came out under its name at rc 0. Build agnos and x86_64 bare-metal images on an x86_64 Linux host.
  `--win` (a no-op on Windows), `--target=cx` / `js` and plain builds are unchanged.
- ⚠ Not changed yet: the aarch64 Linux CLI still drops `--agnos` and `--target=x86_64-bare-metal-elf` (an aarch64 binary
  at rc 0; filed, 6.7.12) — do not build agnos images there.

**TL-11 — `cyrius header` writes return types**
- `cyrius header` output changes for every public fn returning a struct over 8 bytes, a `dyn Tr` or a two-value tuple:
  new `cyr_val2` / `cyr_valN` typedefs (`typedef struct { int64_t w0, w1; } cyr_val2;`,
  `typedef struct { int64_t w[N]; } cyr_valN;`), `#ifndef _WIN64` and `#if defined(__x86_64__) && !defined(_WIN64)`
  arms with a named comment and no prototype in the other arm, and a `/* returns T, N B */` note. C code that called
  those fns through the old `cyr_val` prototypes misread the result (a 9–16 B value lost its second word; over 16 B the
  first argument landed in the result-pointer slot): regenerate the header and use the new return types. On Win64 a
  9–16 B struct or `dyn` return and a two-value return have no prototype (C uses a hidden pointer there) — wrap such a
  fn in one that writes through an out-pointer and returns a word.
- A file with a public fn whose return the tool cannot size from that file — another file's struct or enum, a generic
  instance or generic struct, a struct holding one, a struct declared twice or with `#ifdef`'d fields, three values —
  now makes `cyrius header` exit 1, with one `error: cyrius header: '<f>' returns '<T>': …; no prototype written` line
  per fn on stderr (the header for the other fns is still printed). A build step `cyrius header f.cyr > f.h` under
  `set -e` fails there: make the fn private / `_`-named, or wrap it in one returning a word.
- A SIMD vector return and a `: stack` enum return (`: Result` / `: Option`) still print `cyr_val` (both filed for
  6.7.12): keep hand-writing those prototypes.

#### Stdlib

**LIB-1 — sankoch 2.8.6 refolded (the release ships 2.8.7: the integration's refold on top, `3f8d1b4b`)**
- ⚠ **Stricter decoders.** Each of these now fails where the batch decoder returned the decoded prefix as success:
  - **LZ4F:** a frame cut before its end mark or before a declared content checksum, a bad header checksum, reserved BD
    bits, a wrong declared content size, or a block past the declared maximum → `ERR_CORRUPT_DATA` /
    `ERR_CHECKSUM_MISMATCH`.
  - **xz:** a stream whose Index does not describe its blocks, non-zero padding, mismatched block-header sizes, a
    dictionary byte over 40, or an LZMA chunk that does not decode to exactly its size → refused.

  `lz4 -d` / `xz -d` refuse the same inputs. A program that kept the prefix of a truncated or damaged frame now gets the
  error code. Treat it as the corrupt input it is, or decode with a tool that salvages.
- **DEFLATE** rejects the over-subscribed / incomplete code-length sets zlib rejects.
- **Linked-block LZ4F frames now decode** (the LZ4F library's default; they were rejected). A program that relied on the
  rejection — say, to detect such frames — now receives the data.
- **New:** `brotli_compress` / `brotli_compress_bound` / `brotli_compress_level`. No signature changes, nothing removed,
  and the Requires block is unchanged, so no include change.
- A binary that keeps the encoder grows ~71 KB on x86 (a bare `include "lib/sankoch.cyr"` program, DCE off: 635,128 →
  706,264 B).

**LIB-2 — `dir_list` / `dir_list_checked` / `dir_list_into` on a path that is not a directory**
- A FIFO at the listed path now fails at once — `dir_list_checked` -20 (`-ENOTDIR`), `dir_list_into` -1, `dir_list` an
  empty vec — instead of blocking in `open(2)` until a writer comes. Linux and macOS; Windows and agnos are unchanged.
- ⚠ On macOS, `dir_list_checked` of a REGULAR FILE is now -20 (`ENOTDIR`), not -22 (`EINVAL`), the value Linux already
  gave. A caller that matched -22 should match -20, or test `< 0`.
- A `stat`-first guard written only to dodge the hang (agora's `store_is_dir`) is no longer needed. The stat / open swap
  it left open is closed. Keep it only if you want a different error for a non-directory.

**LIB-3 — agnos: a negative fd is not socket slot 7**
- On agnos, `sys_close(-1)` / `file_close(-1)` (any negative fd) now return -1, not 0, and touch no socket slot.
- `sys_read` / `sys_write` (and the `_nb` forms) of a negative fd now go to the kernel and return -1. Before, they read
  from or wrote to the 8th tagged socket's connection.
- `AGNOS_SOCK_TAG + 8` and above are no longer taken for a socket slot.
- A program that closed or wrote an unchecked -1 used to tear down, or write into, its 8th socket silently. It now gets
  -1 and the socket is left alone. Nothing to change unless code matched the old 0 from `sys_close(-1)`. Check an open's
  result before using it, as on Linux (where these calls fail with `-EBADF`).

**LIB-6 — agnos: socket writes on an agnos 1.57.13+ kernel end at their deadline**
- On a 1.57.13+ kernel, `sys_write` on a tagged socket and native-TLS writes under `tls_native_set_deadline` /
  `tls_set_deadline` pass the time left to `sock_send_dl`#109 as each call's ceiling. So a stalled peer returns
  `TLS_ERR_TIMEOUT` (-22) or the partial count AT the deadline, instead of up to ~8 s later. A write that used to finish
  inside that overshoot now times out at the deadline you set. Set the deadline you mean.
- The first socket send in a process issues one extra zero-length `#109` call, the support probe. On a kernel before
  1.57.13 it answers -1, sends continue on `#48` as before, and the overshoot remains there. A syscall trace or a
  seccomp-style allowlist on agnos sees `#109`.
- A raw caller of the new `sys_sock_send_dl(conn, buf, len, timeout_us)` must never pass 0 to mean "time's up": 0 is
  "no ceiling" (exactly `#48`). Pass a negative value ("no wait"), or do not call.

**Additive — no block (LIB-4, LIB-5, and LIB-6's new names).** The agnos peer gains `SYS_CONSOLE_MODE`, `CM_NOECHO`,
`CM_FLUSH`, `sys_console_mode`, `SIGWINCH` (in `AgnosSignal`), `SYS_FD_KIND`, `FdKind` / `FDK_*`, `sys_fd_kind`,
`SYS_SOCK_SEND_DL` and `sys_sock_send_dl`. A program with its own agnos copy of one of these keeps compiling:
- a redeclared constant or enum is accepted silently;
- a redefined `sys_*` fn warns `duplicate fn '…' (last definition wins; first defined in lib/syscalls_x86_64_agnos.cyr)`
  (measured on the merged tree).

Drop the private copy. Two notes:
- the stdlib's `sys_fd_kind` answers `FDK_SOCKET` (6) for a cyrius tagged socket where the raw `#111` answers -1;
- cycc warns on a conflicting `SYS_*` redefinition.

#### Folds

**patra 1.16.2 (refolded from 1.16.0)**
- `patra_commit` that cannot make the transaction whole and durable now rolls it back and returns `PATRA_ERR_FULL` /
  `PATRA_ERR_IO` (it committed what it had, or reported a commit that was not durable): treat a failed commit as
  rolled back.
- Return values that used to be fixed can now report failure: `patra_close` (the rollback's or a sync failure; it
  returned 0), `patra_flush`, `patra_set_sync_mode`, `jsonl_append_obj(_lens)` (`PATRA_ERR_IO`); any statement can
  return `PATRA_ERR_PAGE` / `PATRA_ERR_MAGIC` / `PATRA_ERR_IO` for a header that fails verification or cannot be read;
  `ALTER … ADD / DROP COLUMN` can return `PATRA_ERR_FULL` / `PATRA_ERR_IO` with nothing changed. ⚠ An autocommit
  statement that fails its sync HAS been applied — retrying an `INSERT` on that error inserts it twice.
- A query refused part-way returns 0 (it could return unsorted or empty values).
- `patra_open` without `patra_init` returns 0 on every target (on agnos and cx it used to work): call `patra_init`
  first. `patra_initialized()` tells a wrapping library whether it has run.
- `CREATE TABLE t ()` is `PATRA_ERR_SYNTAX`; a direct `tbl_create` with no columns is `PATRA_ERR_COLCOUNT`.
- `tbl_scan_where` takes a 10th argument (an overflow out-parameter): a direct caller passes it.
- `BEGIN` syncs pending BATCH writes first; the DB handle is 96 B and `patra_init` reserves 48 KB more.

### 6.7.10
**B7-0 — a baked f32 struct field**
- A declaration-zone struct literal with an `f32` field (`var KS = KP { 1.5, 7 };` with `x: f32`) now puts the
  field's binary32 bits in the image, as the replayed store writes them. Only an x86 `kernel;` image read the
  difference (its replay runs after the program: the field read 0.0); a hosted program behaves as before. Code that
  read such a field with `load64` / as binary64 bits in a kernel image now reads binary32 bits — read it as the field
  (`KS.x`) or with `load32`.

**B7-1 — the handle line**
- A struct local of 8 B or less initialised from anything that is not a struct value of its type is now a HANDLE,
  as one over 8 B always was: `var q: S8 = alloc(8);`, `= &s`, `= gp()` with `fn gp(): *S8`, `= x` (an untyped
  value) hold the address, and `q.v = 5` writes the object. Through 6.7.9 such a local was an inline S8 whose field
  held the address, and its writes stayed in the frame. Code that relied on that (reading `q.v` to get the address
  back, or writing the fields as a scratch copy) changes behaviour: read the address with `load64(&q)` or keep it in
  an untyped local; for a scratch copy initialise from a struct value (`var q: S8 = *p;` with `p: *S8`, or
  `var q: S8;` then `q = r` from another inline S8).
- An integer initialiser is a handle too: `var a: Num = 1;` is a handle to address 1 (`a + b` is pointer arithmetic,
  no `Num_add` dispatch), and `var q: S8 = 0;` is a NULL handle (`q.v = 5` faults). For a zeroed inline struct write
  `var q: S8;` or a literal `S8 { 0 }`; for an operator operand initialise from a struct value (`var a: Num =
  mkn(1);`).
- ⚠ The common UNTYPED carriers of a small struct's word are untyped values, so a struct declared from one is now a
  handle to the address that word spells: `var q: S8 = vec_get(v, 0);` (after `vec_push(v, s)` pushed s's one word),
  `= load64(p)`, `= map_get(m, k)`, `= fncall1(f, x)` / a closure's result, a `?` / pair / `Result` / `Option`
  payload (`var q: S8 = mk()?;`), `= *x` with `x` untyped. Through 6.7.9 each was an inline S8 holding the word —
  the struct itself, so `q.v` read 4 and `q.v = q.v + 5` gave 9; now `q.v` reads memory at address 4 and faults
  (measured: 9 on 6.7.9, SIGSEGV on 6.7.10). Keep such a word untyped, or type the carrier as a pointer and
  dereference it — `var p: *S8 = vec_get(v, 0); var q: S8 = *p;` when the vector holds addresses — or store the
  struct's address in the container (`vec_push(v, &s)`) and declare `var q: *S8 = vec_get(v, 0);`.
- A declaration from a handle binds (`var c: S8 = h;` aliases h's object), as over 8 B; a declaration from a struct
  value still copies (a literal, a field, another inline local, a by-value parameter, a value global, a call /
  method / operator / if-expression result).
- ⚠ An operator whose LEFT operand is a struct-typed FIELD or a DEREFERENCE does not dispatch — it never did, at
  any size: `w.s + a` and `*p + a` add the first words (only a struct variable or a struct result types the left
  operand). Its result is an integer, so `var q: S8 = w.s + a;` / `= *p + a` is now a handle holding that sum and
  faults at its first field access (through 6.7.9, at 8 B or less, an inline q whose field was the sum — at 16 B
  it faulted already). Name the operand first for the `S8_add` dispatch: `var l: S8 = w.s; var q: S8 = l + a;`.
  (Whether a field / dereference operand should dispatch is open — the user's call.)
- `var q: S = *p;` with `p: *S` now copies at every size (over 8 B it was a handle holding the first field), and so
  does every other dereference of a `*S` — `(*p)`, `*(p + 1)`, `*(n + p)`, `*h.p` (a `*S` field), `*gp()` (`fn gp():
  *S`), `*w.mp()`, `(*self)` (a review fix: B7-1 first took only `* IDENT`); `var q: S8 = *pu;` with `pu: *U8`
  (another struct) is refused by name at every spelling (`(*pu)`, `*gu()`, `*w.pu`), as `var q: S8 = pu;` is. A
  dereference of an UNTYPED value (`var x = &s; var q: S8 = *x;`) is no struct value: q is a handle holding the
  word `*x` reads (decision 1; through 6.7.9 an inline copy of that word) — type the pointer (`var x: *S8 = &s;`).
- Every by-value use of a small handle (an argument, `return`, an operator's right operand, an if-expression branch,
  `q = a`, `a = q`, `a = mk()`) takes the struct it points at, as over 8 B; `a = h` between two handles rebinds.
- Struct GLOBALS of 8 B or less are unchanged by this bite (B7-1g applies the same line to them).

**B7-1g — the handle line for globals**
- A struct GLOBAL of 8 B or less initialised from anything that is not a struct value of its type is now a HANDLE,
  as one over 8 B always was (and as a local is since B7-1): `var G: S8 = alloc(8);`, `= &buf`, `= gp()` with
  `fn gp(): *S8`, `= ga()` (untyped), `= gu` (an untyped global) hold the address, and `G.v = 5` writes the object.
  Through 6.7.9 such a global was an inline S8 whose field held the address, and its writes stayed in the global.
  Code that relied on that (reading `G.v` to get the address back, or using the global as a scratch copy) changes
  behaviour: read the address with `load64(&G)` or keep it in an untyped global; for an inline value initialise from
  a struct value (a literal `S8 { .. }`, another inline global, `*p`, a field — through a `*T` too: `P.s`,
  `gp().s` —, a call / method / operator returning S8, a method through a `*T`: `P.dbl()`, `gp().dbl()`).
- An integer initialiser is a handle too: `var ga: Num = 1;` is a handle to address 1 — `ga + gb` is pointer
  arithmetic, no `Num_add` dispatch — and `var G: S8 = 0;` is a NULL handle (`G.v = 5` faults until it is rebound).
  For an operator operand or a zeroed inline global write a literal (`var ga = Num { 1 };`, `var G = S8 { 0 };`).
- A global declared from another handle global binds (`var G2: S8 = G1;` aliases G1's object), as over 8 B.
- Every by-value use of such a global — an argument, `return G`, an operator's right operand, an if-expression
  branch, `q = G`, `G = q`, `G = V`, `V = G`, `G = mk()` — takes the struct it points at, in a fn and at top level;
  `G = G2` between two handles rebinds.
- `var G: S = *P;` with `P: *S` now copies at every size (over 8 B it was a handle holding the word `*P` read),
  and so does every other dereference of a `*S` — `(*P)`, `*(P + 0)`, `*gp()`, `*GW.p` (the review fix);
  `var G: S = *PU;` with `PU: *U` of another struct is refused by name at every spelling. Over 8 B, P must be
  declared ABOVE G (else `cannot copy-init 'G' from a global declared below it`), as a whole source global always
  had to be, and so must a `: *S` fn it calls (`cannot copy-init 'G' from a dereference of a global or fn declared
  below it`); at 8 B or less a fn declared below is fine.
- A global declared twice in the declaration zone, once as a value and once as a handle, is refused by name
  (`redeclared with a different type or size`).
- Not changed (awaiting the user): a struct global declared from a `*T` global's NAME (`var G: S8 = P;`) keeps
  today's layout at every size (8 B or less: inline, holding the pointer word; over 8 B: a handle bound to P's
  object).

**B7-1b — a pointer into a by-value struct parameter of 8 B or less**
- A typed pointer or an address passed to a by-value struct parameter of 8 B or less now passes the STRUCT it points
  at, as one over 8 B always did: `fn bs1(b: S1)` called as `bs1(sp)` (`sp: *S1`), `bs1(&s)`, `bs1(gp())` with
  `fn gp(): *S1`, `bs1(h.p)` with `p: *S1`, `bs1(sp + i)`, `gw(wp)` into `w: W1<T>`, and an operator's right operand
  (`o + sp`, `o + &s` with `fn S1_add(a: S1, b: S1)`). Through 6.7.9 the pointer was passed as the struct's one word,
  so the callee read the ADDRESS as its fields (`b.u` was the pointer). Code that relied on that (reading the pointer
  back out of the parameter) now gets the pointee's fields: pass the pointer to a `p: *S1` parameter, or an untyped
  value, if the address is what the callee wants.
- A `*U` of another struct (or a `*i64`) still converts, as over 8 B, and is read with the parameter's layout.
- An UNTYPED value is unchanged — still the struct's word: an untyped local holding an address (`var u = &s;
  bs1(u)`), an integer, an i8 / i16 / i32 local or expression. The callee's write to its parameter never reaches the
  pointee (a copy, as over 8 B).

**B7-1c — struct copies through a `*T` of 8 B or less**
- `l = p` and `G = p` with `p: *S` (a local or a parameter, S of 8 B or less) now COPY the struct p points at, as
  over 8 B: through 6.7.9 they stored the POINTER into the first field (`l.v` read the address). `q = r` through a
  `q: *S` parameter (or a `*S` local, or `self: *S`) now copies r INTO the pointee, as over 8 B: through 6.7.9 it
  rebound q to r's one word, so the caller's struct never changed and the next `q.v` read through r's field as an
  address. Likewise `p = mk()`, `p = s.m()`, `p = a + b`, `p = if (c) { a } else { b }` and `p = w.s` copy the struct
  result into the pointee (they stored the struct's word as the pointer). Code that used `l = p` to get the address
  back, or `q = r` to repoint q at r's bits, changes behaviour: keep the address in a `*S` (`p2 = p` still rebinds),
  or write the field (`q.v = r.v`) / take the address (`q = &r`) explicitly.
- Unchanged: `*S` <- `*S`, `*S` <- a handle and a handle <- `*S` rebind at any pair of struct types; a `*i64` or an
  untyped address into a struct stores its word, as over 8 B.
- Newly refused, as over 8 B: a struct copy between two different struct types through a `*T` of 8 B or less —
  `l = pu`, `pu = l`, `G = pu`, `q = G` (`q: *U8`), `p = mku(1)` (`cannot copy 'pu' into a variable of a different
  struct/vector type: 'l'`). Each compiled and stored a word. Use the matching struct type, or `store64` for a raw word.
- Not changed (a pre-existing defect at every size, 16 B included, reported for placement): a `*T` GLOBAL, a `: *T`
  call and a `*T` field as a copy source or destination (`l = GP`, `GP = l`, `G = GP`, `l = gp()`, `l = w.p`) still
  store the word.

**B7-2 — u8 / u16 / u32 and f32 struct fields are their widths (packed)**
- A struct (or union) that declares a `u8` / `u16` / `u32` / `f32` field changes layout: those fields take 1 / 2 /
  4 / 4 bytes, with no padding (the rule i8 / i16 / i32 fields always followed); through 6.7.9 each took 8. So
  `sizeof` and every later field's offset shrink: `struct C4 { r: u8; g: u8; b: u8; a: u8; }` 32 → 4,
  `struct { a: u8; b: i64; }` 16 → 9 (`b` at offset 1), `struct { x: f32; y: f32; }` 16 → 8,
  `union { a: u8; b: u32; c: f32; }` 8 → 4; `*C4` steps 4 and `var a: C4[2]` is 8 bytes. `u64` and `i8`..`i64` /
  `f64` / `bool` / `cstring` / enum / `Str` / `Vec` / `*T` fields are unchanged. Code that read or wrote such a
  struct with hand-computed offsets (`load64(p + 8)` for the second field), wrote it to a file / socket / device
  with `sizeof`, or allocated it with a literal size must be re-checked: use the fields (`p.b`), `sizeof`, or the
  `#derive(accessors)` functions, which follow the layout.
- A u8 / u16 / u32 field now reads ZERO-extended at its width and a write stores only its bytes: `c.r = 250;
  c.r += 10;` gives 4 (it gave 260), `c.r = 0x1FF` stores 0xFF, a u32 field's `0 - 1` reads 4294967295, `c.r >>= 1`
  and `c.r /= 2` take the unsigned value. Code that kept a wider value in such a field (it fit in 8 bytes) must use
  `i64` / `u64` (or an untyped field). `load64(&s.f)` of a narrow field now reads the next fields too — read the
  field (`s.f`) or `load8` / `load16` / `load32`.
- An f32 field holds its binary32 bits in 4 bytes (it was the low half of an 8-byte slot): `p.x` is unchanged; a
  `load64(&p.x)` now reads the next field in its high half — use `load32`.
- The by-value class follows the new size: a struct that shrinks to 8 B or less is passed and returned in one
  register, held inline when initialised from a struct value and a HANDLE when initialised from an address (the
  handle line, B7-1: `var c: C4 = alloc(4);` holds the address and `c.r = 5` writes the heap); 9..16 B and over
  16 B take the classes their size has always picked. A caller that passed such a struct to a
  `fncallN` / fn pointer by its address because it was over 8 B (`fncall1(&f, &c)` for `fn f(c: C4)`) must pass it
  as the callee's class now expects (a 4-byte C4 arrives in a register: pass the value, or declare the parameter
  `c: *C4`).
- Packed means unaligned: a `u32` / `f32` after a `u8` sits at offset 1. Plain loads and stores are fine on every
  target cyrius ships (x86_64, aarch64 Linux / macOS, cx); an atomic or a futex word needs its natural alignment —
  put such a field first, or pad explicitly (`_pad: u8; _pad2: u16;`). cyrius passes no struct by value to C, so
  there is no FFI struct classification to match.
- Diagnostics that follow from the size: `dyn Tr` from a struct whose method takes `self: T` by value is refused
  once the struct is 8 B or less (dyn decision 2, 6.7.8): `dyn Show` from `C4` with `self: C4` (it formed one at
  32 B) — declare `self` untyped or `self: *C4`. A struct redefined with another narrow kind warns as before
  (`i8` vs `u8`, `i32` vs `f32`) and now also for `u8` vs `u16`, `u32` vs `f32`.
- `#derive(accessors)` follows the layout: a u8 / u16 / u32 getter zero-extends (255, not -1), an f32 getter
  returns the binary32 bits, a setter writes only its bytes. `#derive(Serialize)` of these types arrives in B7-3.
- An operator on a struct VALUE GLOBAL under 8 bytes now dispatches its `T_op`, as on a local or an 8 B global (a
  review fix, B7-2r): `A + B` with `var A = C4 { .. };` calls `C4_add`. Through 6.7.9 a value global of a struct
  of i8 / i16 / i32 fields under 8 B (`struct I4 { a: i32; }`) was read as an i8..i32 scalar, so `A + B` silently
  integer-added the two words (30 where `I4_add` gives 40) — code that relied on that sum now gets the operator's
  result; spell the integer add on the fields (`A.a + B.a`).

**B7-3 — `#derive(Serialize)` on u8 / u16 / u32 / f32 fields**
- Additive: a `#derive(Serialize)` / `#derive(Deserialize)` struct may now declare `u8` / `u16` / `u32` / `f32`
  fields (through 6.7.9 the build was refused: `undefined function 'u8_to_json'`), so nothing that built changes.
  The wire shapes, for a consumer that hand-rolled these codecs and wants to switch:
  - u8 / u16 / u32: a bare JSON number, the field read zero-extended (a u32 4000000000 is `4000000000`). Decoding
    stores at the field's width, so an out-of-range number truncates as any narrow store does (300 into a u8 is 44;
    there is no range check, as for i8..i32).
  - f32: the value WIDENED to f64 and printed by bayan's f64 printer (the user's decision, 2026-10-12): 0.1f is
    written `0.10000000149011612`, 1.5f `1.5`, the smallest subnormal `1.401298464324817e-45`. Decoding parses an
    f64 and rounds it to the nearest f32 (`f32_from`), so every written value comes back bit for bit, and a
    hand-written `0.1` decodes to 0.1f. A peer expecting the shortest f32 text (`0.1`) reads a longer number with the
    same value.
  - `u64` fields stay outside the codecs (`u64_to_json` undefined, as through 6.7.9).

**B7-4 — `#derive(Serialize)` on `: cstring` fields**
- Additive: a `#derive(Serialize)` / `#derive(Deserialize)` struct may now declare `: cstring` fields (through 6.7.9
  the build was refused: `undefined function 'cstring_to_json'`), so nothing that built changes. The wire shape (the
  user's decision, 2026-10-12) is the one sigil's hand-rolled `agnosys_json_emit_cstr_or_null` writes, byte for byte:
  a NULL pointer is `null`, any other the bytes as an escaped JSON string. Decoding gives NULL for `null` and
  otherwise a FRESH NUL-terminated copy (allocated with `alloc`; the field never points into the parsed text): a
  JSON string unescaped (`\uHHHH` as UTF-8, a surrogate pair joined, a lone surrogate U+FFFD), any other value its
  text (`42` → "42"). A decoded `\u0000` ends the C string there. A quoted `"null"` is the 4-byte string `null` in
  both decoders, never NULL.
- lib/str.cyr gains two public fns: `str_builder_add_json_cstr(sb, p)` and `str_json_unescape_cstr(p, n)`. A program
  that defines a fn of either name now meets the stdlib's (the duplicate-fn rule: the later definition wins, with a
  warning) — rename it.
- Every binary that includes lib/str.cyr changes bytes (its new fns are emitted, as every lib fn is, DCE or not); no
  program's behaviour changes.
- ⚠ The derive's cstring codec calls lib/str.cyr's `str_builder_add_json_cstr` / `str_json_unescape_cstr`, new in
  6.7.10's lib/str.cyr: a 6.7.10 compiler building against an OLDER vendored lib/str.cyr (a stale `lib/` copy, a
  pinned dep that vendors its own) fails such a struct with `undefined function 'str_json_unescape_cstr'`. Refresh
  `lib/` (`cyrius deps`) with the 6.7.10 stdlib.

**B7-4b — a `Str` field's JSON escapes are decoded**
- Changes what a program does (the user's decision, 2026-10-12: the derive's lossy `Str` decode is fixed). Through
  6.7.9 the two decoders of a `#derive(Serialize)` struct mangled a `Str` field's escapes differently:
  - the scanner (`T_from_json_str`) decoded only `\n` `\t` `\r` and kept the LETTER of every other escape, so
    `"\u0001\b"` read `u0001b` and `"é"` read `u00e9` (`\"` `\\` `\/` were right);
  - the pairs form (`T_from_json(bayan_json_parse(..))`) stored bayan's value itself, so EVERY escape stayed raw
    (`\\u0001\\b\\\"` came back, and re-encoding doubled each backslash).
  Both now decode every RFC 8259 escape (`\" \\ \/ \b \f \n \r \t`, `\uHHHH` as UTF-8, a surrogate pair one 4-byte
  code point, a lone surrogate U+FFFD; any other escaped byte stands for itself), so what `T_to_json` writes reads
  back as the same bytes. A decoded `\u0000` stays in the Str (its length counts it). A string with no escapes
  decodes as before.
- The pairs form's `Str` field is now a FRESH copy (its own buffer, NUL-terminated after the bytes), no longer a
  `Str` header pointing INTO the parsed document: changing or freeing the document after the decode no longer
  changes the field, and `str_data(field)` is no longer an address inside it. A program that relied on the
  borrow (rare) keeps its own reference to the document's bytes.
- A non-string value for a `Str` field is unchanged: the scanner leaves the field 0, the pairs form a Str of the
  value's text (now a copy).
- lib/str.cyr gains `str_json_unescape(p, n)` (the Str form of `str_json_unescape_cstr`) — the same duplicate-fn
  note as B7-4.
- ⚠ Both decoders now call lib/str.cyr's `str_json_unescape` (new in 6.7.10): a 6.7.10 compiler against an OLDER
  vendored lib/str.cyr fails EVERY `#derive(Serialize)` struct with a `Str` field (`undefined function
  'str_json_unescape'`) — including ones that built on 6.7.9 (measured: derive_str_deserialize,
  derive_str_field_global_init, derive_vec_primitive, derive_vec_struct and lang/regression against the slot-open
  lib/str.cyr). Refresh `lib/` (`cyrius deps`) with the 6.7.10 stdlib — compiler and stdlib move together.

**B7-5 — additions for ecosystem-migration § 6.7.10 (measured on the B7-4b compiler vs the installed 6.7.9 cycc)**
- Refusals that keyed on a struct being over 8 bytes stop applying to a struct that SHRINKS to 8 bytes or less
  with the packed layout (B7-2), so code that was refused now builds (nothing that built changes):
  - an if-expression branch of the struct (`var z: C4 = if (k) { a } else { b };` — 6.7.9: "an if expression branch
    cannot be a struct value over 8 bytes: struct 'C4'");
  - an `async fn` by-value parameter (`async fn af(c: C4)` — 6.7.9: "async fn parameter 'c' is a struct passed by
    value ... pass a pointer to it");
  - a top-level struct call result, as a global's initialiser (`var G: C4 = mk4(9);`) or a top-level argument
    (`var r = h(mk4(5));`) — 6.7.9: "'mk4' returns a struct by value, and a struct result needs storage in a fn's
    frame". A struct that shrinks from over 16 B into 9–16 B (`{ f32 x4 }` 32 → 16) is still refused there.
  And the one that newly applies: `dyn Tr` from a struct that shrinks to 8 B or less whose method takes `self: T`
  (B7-2's note).

**OPS-1 — a struct-typed field or a `*T` dereference as an operator's left operand dispatches**
- An operator whose LEFT operand is a struct-typed field (`w.s + a`, `p.s - a` through a `*W`, `mk(1).s * a`,
  `self.s / a`, `(w.s) + a`) or a dereference of a `*S` (`*p + a`, `(*p) + a`, `*gp() + a`) now calls `S_add` /
  `S_sub` / `S_mul` / `S_div`, as a struct variable in that place always did; its result is a struct value. Through
  6.7.9 it added (subtracted, ...) the field's FIRST WORD and the right operand's value, with no operator call and no
  diagnostic. Code that relied on that integer arithmetic changes value — and, when the struct has no such operator
  fn, stops compiling (*refusing to emit binary with 1 reachable undefined function(s)*, naming `S_add`), as `s + 1`
  on a struct variable always did. Read the word you meant explicitly: `w.s.v + 1` (the field's own field); for a
  dereference, `p.v + 1` or `load64(p) + 1`.
- A `*T` field (`w.p + 1` steps the pointer), a `Str` field and a negated operand (`-w.s + a`) are unchanged.
- `var q: S = w.s + a;` / `= *p + a` is now a copy of the operator's result (in 6.7.10 before this change, under the
  handle line, a handle holding the integer sum: its first field access faulted).

**OPS-2 — an untyped binding of a struct-returning operator takes the struct type at every size**
- `var c = a + b;` (untyped, in a fn) whose operator fn returns a struct of 8 B or less now declares `c` an inline
  struct of the operator's RETURN type, as over 8 B: `c.f` works and `c + c` / `c - x` dispatch. Through 6.7.9 `c` was
  an untyped word holding the struct's bytes. Code that did `+ - * /` (or `+% -% *%`) arithmetic on that word
  (`c + 1`, `c * 2`) now dispatches `S_add` / `S_sub` / `S_mul` / `S_div` (or is refused when the struct has none) —
  read the field (`c.v + 1`) or `load64(&c)`; the other operators (`c & 0xFF`, `c | m`, `c << 1`, `c % n`) still
  act on the word, unchanged. A
  binding from a leading call of another struct (`var c = mk8(4) * b;` with `S8_mul` returning `U8`) is now the
  operator's type (it was typed from the call). An integer-returning operator and a top-level untyped global are
  unchanged.
- Restores `var c = A + B; c.g = 1;` for a struct that 6.7.10's packed fields shrank to 8 B or less (refused since
  the layout change).

**OPS-3 — a struct copy through a `*T` global, a `: *T` call or a `*T` field copies the struct**
- `l = GP` / `G = GP` (`GP: *S` a global), `l = gp()` (`fn gp(): *S`, or a method declared `: *S`) and `l = w.p`
  (`p: *S` a field, at the end of any chain) into a struct VALUE now copy the struct the pointer points at, at every
  size — as `l = p` through a `*T` local does. Through 6.7.9 (over 8 B too) each stored the POINTER into the first
  field. Code that used such an assignment to carry the address in a struct's first word changes behaviour: keep the
  address in a `*S` (`var p: *S = GP;`) or an untyped local, or store it explicitly (`store64(&l, GP)`).
- Into a `*T` or a handle these still rebind (`q = GP` through `q: *S` repoints q).
- Newly refused: a `*U` of another struct into a struct value (`l = GU`, `l = gu()`, `l = w.pu`) — each compiled
  and stored a word. Use the matching struct type, or `store64` for a raw word.
- Not changed (see the guide): `GP = l` with GP a `*T` global (still a word store into GP); a struct-typed FIELD
  destination from these sources (`o.s = GP`, still the pointer word); an assignment from a dereference
  (`l = *p`, still one word — `var l2: S = *p;` copies).

**OPS-4 — a dereference-led operator result as a by-value argument over 8 B**
- `take(*p + a)` (and a method's or a named argument, `*gp() + a`, chained) with a struct parameter over 8 B now
  passes the operator's result; it pushed the result's first word as its address and crashed. At top level a
  9-16 B result (`var R = takeh(*GP + A);`) is refused by name, as `takeh(GW.s + A)` always was — compute it
  inside a fn.

**OPS-5 — a whole dereference of a `*S` as an address-passed argument or right operand**
- `take(*p)` (by-value struct parameter over 8 B, or a `*S` parameter of any size) and `a - *p` (the same
  for an operator fn's parameter) now pass the struct `p` points at — the pointer, as `take(p)` does; they
  passed the word the dereference read as the struct's address and crashed. Into a `*S` parameter the callee
  now writes the pointee.
- Newly refused: a dereference of a `*U` of ANOTHER struct into such a parameter (`takeh(*pu)`, `a - *pu`) —
  as a struct variable of another type always was. Use the matching struct type. An untyped `*x` is unchanged.

**OPS-6 — pointer arithmetic on a `*T` as a struct copy source**
- `l = p + 1` / `l = (p + 1)` / `l = 1 + GP` / `G = q - 1` with a `*S` operand and a struct VALUE destination now
  copy the struct the result points at; they stored the pointer into the first field. Keep an address in a
  `*S` (`var q: *S = p + 1;`) if that is what was meant. Into a `*T` or a handle the assignment still rebinds
  (`p = p + 1` steps the pointer, unchanged).
- Newly refused: pointer arithmetic on a `*U` of another struct into a struct value (`l = pu + 1`), as `l = pu`
  always was.

**P5B-6 — `cyrius coverage --exec` / `[coverage] exec`**

- **New, opt-in:** `cyrius coverage --exec[=<glob>]` or `[coverage] exec = ["programs/*_test.cyr"]` measures what
  RUNS: every `tests/**/*.tcyr` and every named program is built instrumented and run, and the report adds
  `Functions executed: E/T`. `[coverage] programs` and every text-mode figure are unchanged (6.7.9's stdout byte for
  byte). With the mode on, `--min` gates the executed %, and a failing run (an exit, a signal, a timeout, or no
  coverage record) fails `cyrius coverage` by name.

**P5B-1..8 — the execution-coverage mode (`CYRIUS_COVERAGE`)**

- **A new opt-in mode; no existing program, number or manifest changes.** `CYRIUS_COVERAGE=1` with
  `CYRIUS_COVERAGE_FILE=<absolute path>` builds a program that counts its fn entries and appends them to that file
  when it exits (the guide's *The execution-coverage mode*). Unset, `0` or empty, it changes nothing — not a byte of
  any compile's output.
- **One environment edge:** the variable is new, and like `CYRIUS_BOUNDS` it accepts only `0` / `1`. A build
  environment that happens to export `CYRIUS_COVERAGE` with any other value now has every compile refused by name
  (`CYRIUS_COVERAGE must be 0 or 1 (or unset): <v>`). One that exports `CYRIUS_COVERAGE=1` without a
  `CYRIUS_COVERAGE_FILE` is refused too. Unset it in such scripts, as this repo's own self-build scripts do.
- **Reserved names:** the dump's fns (`__cyrius_cov_cp` / `_num` / `_w` / `_dump`) join the compiler's `__cyrius_`
  prefix. They exist only under the mode.

**The folds (refolded byte-identical)**
- **bayan 1.5.14** — `bayan_f64_parse` / `bayan_f64_from_json` answer bit-identically; the bundle now pulls
  `lib/math.cyr` through its Requires block, so `include "lib/bayan.cyr"` alone still compiles (no include change).
  The private `_d_*` parser tiers are gone (nothing public).
- **yukti 2.3.17** — yukti no longer declares `SYS_PPOLL`. Linux x86_64 / Intel macOS get the stdlib's same 271; a
  Windows build that named yukti's `SYS_PPOLL` calls `sys_ppoll` instead.
- **yantra 1.0.11** — the CDP socket gets TCP_NODELAY on Windows; the bundle's Requires block drops `syscalls`
  (still reached through net / alloc / chrono / ws / sigil).
- **sakshi 2.5.9** — programs that include sakshi now compile and run on cx; native output unchanged.
- **sigil 3.13.12** — no API change; `include "lib/sigil.cyr"` / `"lib/tls.cyr"` stop printing two warnings; static
  data −256 KB.


### 6.7.9
- **`lib/yantra.cyr` (yantra 1.0.10) no longer pulls `lib/ws_server.cyr`** into scope: a program that called a
  `ws_server` fn and got it only through including yantra now includes `lib/ws_server.cyr` itself. `yantra_version()`
  is "1.0.10".
- **With `q: *T`, a value an operator computes from q is a plain integer, so `+ n` / `- n` on it adds n, not n ×
  sizeof(T)** (the user's decision, 2026-10-11): `(x == q) + n`, `(a && q) + n`, `(k * q) + n`, `(m & q) + n`, `(0 ^ q)
  + n`, `(~q) + n`, `(-q) + n`, `mk(q).n + n` (a call result's non-pointer field), `(q?) + n`, and a builtin's result
  (`bitget(m, 0, q) + 1`). Before 6.7.9 the pointer's step leaked through the operator (`(x == q) + 100` was 401 with
  `q: *i32`). A program that leaned on the leak — `(p & ~7) + 1` meant as one element — writes the bytes (`(p & ~7) +
  8`) or assigns the value to a `*T` first. `p16 - (k * q32)` now compiles as `p - n` (it was refused as a pointer
  difference). An operator fn that declares `: *T` gives a pointer stepping by T in every position (`(v + q) + n`, `v +
  q + n`, `v * q + n` — it stepped 1, or took q's leaked step); any other operator fn's result is a plain integer.
  Assigning such a value to a `*T` (`var r: *i32 = 0 | q;`) warns "assigning non-pointer to typed pointer", as the other
  operand order always did; the warning never stops a build.
- **Unary `-` / `~` on a constant binds tighter than a literal operator after it** (the user's decision, 2026-10-11):
  with `enum E { K = 5; }`, `-K + 10` is 5 (was 15), `-K * 2` is -10 (was 10), `~5 * 2` is -12 (was 10), `~K + 1` is -5
  (was 6); the same for a `const` operand and for `E.K`. Before 6.7.9 an unparenthesised `-` on an enum constant or
  `const`, or `~` on any constant, followed by `+ - * / << >> & | ^` and an integer literal, computed the operator over
  the operand and dropped the unary one (and left a stray word on the stack). `(-K) + 10` and `-5 + 10` are unchanged; a
  program that relied on the old value now computes the arithmetic as written.
- **A method call's result has its method's return type, whatever its last argument is** (the user's decision,
  2026-10-11): with `fn m(self, d: f64): i64`, `p.m(1.5) * 2` is 42 (was 0) and `p.m(1.5) / 2` is 10; with `fn
  area(self): f64`, `p.area() + 1.0` is an f64 add (it added the bits as integers); `p.m(q) * 10` with a struct `q`
  multiplies the integer (it dispatched `Q_mul`); a free struct-returning call's field, `mk(1.5).a * 2`, is 42 (was 0).
  An unannotated `var a = p.area();` — or any chain ending in the call, `w.v.area()`, `p.me().area()`, `mk(1.5).area()`
  — declares an f64, as `var a = fa(&p);` does, so `a + 1.0` is an f64 add. Warnings move with the type: `p.area() * 3`
  now warns (an f64 times an integer), as the free call does; `2 * p.m(1.5)` no longer does. A program that bound the
  result to a declared type or called the mangled name (`P_m(&p, 1.5)`) is unchanged.
- **A generic called with an `f64` argument runs its `f64` instance, and its `: T` result is an `f64`** (the user's
  decision, 2026-10-11): with `fn gid<T>(x: T): T` and `h: f64`, `gid(h) * 2.0` is 3.0 (it multiplied the bits as
  integers), `var v = gid(h);` declares an `f64`, and a body computing on `T` computes in f64 (`dbl(h)` with `x + x` is
  3.0; it added the bits). The same for a float literal, an `f64` global, an `f64`-returning call, a generic method
  (`p.id(h)`, `w.v.id(h)`), and an explicit call whose `T` is only the return type (`gg<f64>(&q) * 2.0`). A program that
  relied on the i64 base running for an f64 argument now gets the f64 value; `gid(h) * 2` now warns as `h * 2` does. An
  `f32` argument, and an `f64` expression that is not the whole argument (`gid(h * 2.0)`), still infer `i64`. ⚠ A
  BOUNDED generic called with an `f64` (`gb(h)`, `fn gb<T: Show>`) now needs `impl Show for f64`, as `gb<f64>(h)` always
  did: with only an i64 impl it is a compile error (it compiled and ran the i64 impl on the double's bits) — add the f64
  impl, or pass an integer.
- **`&q` of a `q: *P` parameter is the parameter's own slot, for every `P`** (the user's decision, 2026-10-11): with `P`
  a struct over 8 bytes, `&q` was `q` itself (the pointee), so `load64(&q)` read the struct's first field, `store64(&q,
  x)` wrote `x` into the CALLER's struct and `&q == q`. Now, as for a `*P` local, a `*Q` of 8 bytes or less, a `*i64`
  and in 6.6.5, `load64(&q)` is `q`, `store64(&q, o)` re-points `q`, and `&q` passed on is a pointer to the pointer. The
  same for an untyped impl `self` (`&self`), `self: *P` and a generic `q: *T` instance at a struct over 8 bytes. A
  program that wanted the struct's address writes `q`. `return f(&q);` in such a fn is an ordinary call now, not a tail
  call.
- **A pointer passed to `fn gx<T>(b: Box<T>)` calls the instance its pointee names** (the user's decision, 2026-10-11):
  `gx(&b)`, `gx(bp)` with `bp: *Box<Pt>` (a local, a parameter, a global, a call returning one, a `*Box<Pt>` field) call
  `gx$Pt`, as `gx<Pt>(&b)` does — they ran the `i64` base and read the struct with `Box<i64>`'s layout (`b.n` came back
  as `b.v.y`). A program that wanted the base writes `gx<i64>(..)`. Through a pointer, a generic that uses `T` as a
  struct or returns `T` now compiles where it was refused. An untyped pointer (`var u = &b; gx(u)`) still binds nothing.
- **A child the exec family starts (`run`, `run_capture`, `spawn`, `exec_*`, `exec_cmd`) no longer inherits its parent's
  ignored SIGPIPE / SIGXFSZ or (Linux) its blocked signal mask** (the user's decision, 2026-10-11). It starts at SIG_DFL
  with an empty mask, as a freshly launched program does: a pipeline in the child ends quietly again (`yes | head -1`),
  and a SIGINT the parent blocks no longer makes the child uninterruptible. A child that wants SIGPIPE ignored asks for
  it itself (`signal_ignore(SIGPIPE)`); other ignores, such as a `nohup` SIGHUP, are inherited as before. On macOS the
  mask is still inherited (no sigprocmask route; filed).
- **`fhm_set` (`lib/hashmap_fast.cyr`) overwriting a key that is already present no longer rebuilds the table** (the
  user's decision, 2026-10-11). At the 87.5 % trigger it used to double (or rebuild in place) first: `fhm_cap` grew,
  `alloc_used` moved, the arrays were replaced or their entries moved, and with the allocator exhausted it returned -1
  without storing the value. It now stores in place and returns 0 with nothing else changed (`lib/hashmap.cyr`'s
  `map_set` rule since 6.6.20); a new key rebuilds exactly as before. A walk over the arrays that overwrites as it goes
  stays valid.
- **Miscompiles fixed — a program that read the wrong value now reads the right one:** a store into a zero-size struct
  global (`struct E { }`, `G = v;`) stores nothing (it wrote eight bytes over the globals after it); a by-value struct
  over 8 B at parameter 62 or later is the value it had where it was written (`f(.., s, g(&s))` — `g`'s write no longer
  reaches `f`'s copy, and a self tail call beside it keeps its `jmp`); a closure made inside a suspending `async fn`
  sees a captured struct, tuple, `u128`, array or slice in field order (the words arrived reversed — a program that read
  them swapped must read each by its own name); a closure written at top level, and a coroutine, read a global by its
  own name even when the fn compiled just before has a parameter or local of that name (they read a dead stack slot, or
  the coroutine frame's address); on cx, a constant global holds its value from program start, as on every other target
  (a write from an earlier initialiser's call is kept, and a no-`main` program ending `var y = f(); var x = 5;` exits
  with `f()`'s value; `var Q = INT_MIN / -1;` no longer traps cxvm).
- **`n + p` with a `*u8` / `*i8` p is a `*u8` / `*i8`, as `p + n` is** (the user's decision, 2026-10-11): `(1 + p8) -
  q32` (a pointer difference of two element sizes) no longer compiles — before 6.7.9 it was a byte difference — and `var
  r: *u8 = 1 + p8;` no longer warns. For a byte count subtract plain addresses (`var a = p8; (1 + a) - q32`), as the
  error says. `(1 + p8) - p8` and every computed value are unchanged.
- **An unmatched `}` at module scope is a compile error** (`unmatched '}' at module scope`, exit 1; the user's decision,
  2026-10-11). Before 6.7.9 it silently ended the file: everything after it was dropped and the build reported OK. A
  program that built with one was missing every definition after the brace; delete the brace (or, when the error lands
  on a fn's closing brace, the extra `}` inside that fn that closed it early). `cyrius lint` (`--syntax-only`) refuses
  it too.
- **A `for` step must assign a declared variable** (the user's decision, 2026-10-11). `for (..; ..; j = i + 1)` or `yy
  += 1`, where the name is declared nowhere, is now `undefined variable 'j'`; before 6.7.9 it compiled and stored
  nothing, so the loop never moved. The same refusal covers a fn's name and a closure's captured name as the step's
  destination. Fix the misspelled name or declare the variable before the loop. `--syntax-only` (`cyrius lint`) is
  unchanged.
- **A global declared before the first top-level statement can no longer take a whole 9-16 byte struct method or
  operator result** (the user's decision, 2026-10-11). `var G: Q = Q0.mk();`, `= (Q0.mk())`, `= Q0.gmk(1)` and `= Q0 +
  Q1` (a 16 B `Q`) are refused by name, as `var G: Q = mkf();` and the same line after a statement already were; before
  6.7.9 they compiled and the program SIGSEGV'd at the first read of a field of `G` (one that never read `G` ran, and
  now stops compiling). Initialise `G` inside a fn (`fn init() { G = Q0.mk(); }`). An 8-byte struct result, and an
  untyped `var G = Q0.mk();` (which takes the first word), are unchanged. A struct global whose initialiser is already
  refused inside reports that one error, no longer a second one for its result.
- **Now compiles:** a closure that names an enclosing local only as a field (`p.y`, the `y:` in `Pt { x: n, y: 2 }`) no
  longer captures it — it was refused without `lib/alloc.cyr`, and with it carried a needless env; a top-level closure
  that named such a name as a field likewise; a coroutine local named like the previous fn's first local (it was
  "duplicate variable"); `var t, v = fncallN(..)` on cx; and a call routed to an overload sibling defined BELOW it whose
  arity does not fit — with `fn pr(x)` and a 2-parameter `fn pr_str(s: Str, k)` after the call, `pr(s)` runs `pr`, as
  with `pr_str` above (6.7.7 / 6.7.8 refused it, 6.7.6 and earlier ran `pr_str` with garbage for `k`; call `pr_str(s,
  k)` by name to reach it). The same holds for a `<base>_int` sibling.
- **Public bound vars no longer steer what the stdlib does: `TLOCAL_MAX_SLOTS`, `TLS_REG_MAX` (arm64 macOS),
  `SPAWN_ARGV_MAX` and `KEV_SIZE` are read-only in effect** — every loop, cap and allocation reads the const the storage
  is sized by. A program that RAISED `TLOCAL_MAX_SLOTS` (as `thread_local_alloc`'s old comment advised) now gets -1 from
  `thread_local_alloc` after slot 127 on every target; on x86_64 / aarch64 Linux it used to be handed slots up to the
  var, and elsewhere it corrupted memory. More slots means raising `_TLOCAL_MAX_SLOTS` in lib/thread_local.cyr. Read the
  vars freely; they still hold the values. Programs including lib/freelist.cyr or lib/dynlib.cyr have 504 / 1,792 fewer
  .bss bytes (layout only).
- **`TLS_CA_MAX_ROOTS` no longer bounds anything** (lib/tls_native_hs12.cyr). Its last reader,
  `tls_native_set_client_cert`'s PEM path, sizes from the file's own block count, so a client PEM with more than 300
  blocks installs its (first-block) leaf instead of failing `TLS_ERR_CERT_INVALID`, and assigning the var — the only way
  it ever changed a result — has no effect. The name still compiles.
- **CLI exit codes:** a bare `cyrius bench`, `cyrius fuzz` or `cyrius smoke` that finds nothing to run exits 1, with
  `error: no benchmarks found …` / `no fuzz harnesses found …` / `no smoke harnesses found …` on stderr (they exited 0
  after printing "No … found"), as bare `cyrius test` with no `.tcyr` always has. A CI step that runs one in a project
  with no `.bcyr` / `.fcyr` / `.smcyr` under its roots now fails — add a harness, or drop the step. `cyrius audit` is
  unchanged: its bench stage is non-fatal and prints a `skip:` line. `cyrius init` and `cyrius port` exit 1 when their
  templates are missing, naming the directory they looked in (init printed `Created <x>/` and exited 0); a greenfield
  init or a port with the template directory absent creates nothing. Reinstall the toolchain to restore
  `programs/cyrius-init-templates`.
- **`cyrius api-surface` may report changes at the pin bump in a project with a multi-line string literal.** Fns that
  follow a string whose inner lines hold a `{` are now listed (they were missing), and entries made from a string's own
  text (an inner line starting `fn name(`, or an inner `#derive` + `struct`) are gone, which shows as a removal. Neither
  is a real API change: check the diff, then run `cyrius api-surface --update`.
- **`scripts/ci.sh` links `$CYRIUS_HOME/lib` in every home** (it linked only the bins on a fresh CI home), so a project
  with no `cyrius =` pin finds the stdlib after a CI install. On a cached CI home whose `$CYRIUS_HOME/lib` is a link
  into an older slot, the link is re-pointed to the installed version; a real `$CYRIUS_HOME/lib` directory is replaced
  by the link, as install.sh does. The x86_64-linux release tarball now ships `cyrius-repl.sh`, so `cyrius repl` works
  on a tarball install.
- **Additive (new public names; nothing that compiled changes):** `sys_ppoll(fds, nfds, tsp, sigmask, sigsetsize)` on
  every target (x86_64 / aarch64 Linux issue ppoll; macOS declines -78, Windows, agnos and cx -38) with `SYS_PPOLL` (=
  271) on x86_64 Linux and, unrouted, x86-macOS; on agnos `sys_ioctl` / `sys_fstatat` (declining -38, so portable source
  needs no `#ifdef CYRIUS_TARGET_AGNOS` around them) and `SPAWN_ENV_MAX` (= 1024); `sock_set_nodelay(fd, on)`
  (lib/net.cyr) — TCP_NODELAY on Linux, macOS and Windows, -38 on agnos; a raw `sys_setsockopt(fd, 6, 1, &one, 4)` never
  set it on Windows (the raw wrapper still declines there), so move it to `sock_set_nodelay(fd, 1)`; `f64_parse_n(s, n)`
  (lib/math.cyr) — `f64_parse` over the span `s[0..n)`, no NUL or copy needed, nothing past `n` read (`f64_parse` /
  `f64_parse_ok` return the same bits as before). A program that defines its own `sys_ppoll`, `sock_set_nodelay` or
  `f64_parse_n` now duplicates the stdlib's (last definition wins, with a warning); its own `SYS_PPOLL` of the same
  value 271 is silent, a different value warns "duplicate symbol … conflicting value" on x86_64 Linux and x86-macOS. On
  ELF-aarch64 a raw `syscall(271, ..)` now warns (271 is `process_vm_writev` there).

### 6.7.8
- **`*p` through a narrow `*T` reads and writes the element, not a word** (`*u8`..`*u32`, `*i8`..`*i32`, `*f32`;
  `*p`, `*p = v`, `*p OP= v`, the for step). A program that compiled can compute differently: a read narrows (`*p`
  through a `*u8` was 8 bytes, now 1, zero-extended; through a `*i32` 4, sign-extended — `var x = *s;` read the pair
  `a[0] | a[1] << 32`, now `a[0]`); a store writes T's width (`*p = 0x41` through a `*u8` wrote 0x41 and seven zero
  bytes, now one; `*q = 5` through a `*i32` no longer zeroes the next element; `*p = 1.5` through a `*f32` stores
  binary32 1.5, not the f64 word); `*p OP= v` wraps at the element. `*(p + n)`, `*(n + p)`, a `*T` field (`*h.p`) and a
  `: *T` call (`*f()`) likewise. Such stores now warn as `p[0] = v` does ("narrowing assignment"; "an integer stored
  into an f64/f32 slot keeps its integer bits"), and a narrow read is a narrow value (`c = *p16;` with `c: u8` warns). To
  keep the word through a typed pointer write `load64(p)` / `store64(p, v)`, or launder it: `var w = p; *w`. `*i64` /
  `*u64` / `*f64` / `*bool` and untyped addresses are unchanged. No source in cyrius or its folds dereferences a narrow
  `*T`.
- **A signed slice element reads as the negative number it holds** (`[i8]` / `[i16]` / `[i32]`, `slice<i8>` ..): a
  byte 0xFD in an `[i8]` read 253, now -3, so `s[i] < 0` can hold and `/`, `%`, `>>`, `>>>` and every comparison see
  the negative value. For the unsigned value write `s[i] & 0xFF` (`& 0xFFFF`, `& 0xFFFFFFFF`) or declare the slice
  `[u8]` / `[u16]` / `[u32]`. `slice_unchecked_get_1/2/4` (lib/slice.cyr) still zero-extend. No source in cyrius or its
  folds declares a signed slice.
- **`*G<T>` parameters infer `T`** (the user's decision, 2026-10-10). A generic taking `b: *Box<T>` (any `*G<.., T,
  ..>`) called with `&b`, a `*Box<Pt>` name or call, a `Box<Pt>` value, or a field chain whose leaf is declared
  `*Box<Pt>` (`gx(h.bp)`) now runs the `Pt` instance; before 6.7.8 it ran the i64 base and read `Box<Pt>` with
  `Box<i64>`'s layout. A program that relied on the old value changes it — write `gx<i64>(..)` to keep the base. A
  by-value `G<T>` parameter starts inferring only where the call was refused before.
- **`dyn` is a reserved word.** A fn, variable, parameter, field, method or `[embed]` name spelled `dyn` no longer
  compiles ("expected identifier, got reserved keyword 'dyn'"): rename it. Checked trait objects (`o: dyn Show`) are
  opt-in per declaration — a program that spells no `dyn` compiles byte-identically — and `lib/trait.cyr` is unchanged.
- **A trait's signatures are parsed.** A trait member whose signature does not parse as a `fn` signature (junk tokens,
  a parameter that is not a name, a stray token before the `;`) or names a type that does not exist is a compile error
  — also in a default method every impl overrides, which was never parsed. Fix the declaration; a valid trait is
  unaffected.
- **A slice is a fn-local; every other position is refused by name.** A slice parameter, return type, struct / union
  field, `*[T]`, declaration-zone global, slice of slices, type argument or tuple element was already an error, under a
  misleading text a tool may have matched (`expected ')', got identifier 'u8'`, `unknown type 'slice' …`, `expected
  identifier, got '['`, `expected '=', got identifier 'u8'`); each is now "a slice cannot be a parameter (6.7.8: slices
  are fn-locals) - …" or its sibling. Pass `&s` and read `slice_ptr` / `slice_len`. A top-level slice after the first
  statement, a program's own `struct slice` and `g<slice<u8>>(..)` compile as before.
- **An untyped parameter that subscripted as a slice is refused.** Such code compiled only when an earlier fn of the
  same program declared a slice local in the same slot, and it read or wrote the frame, not a slice: `y[0]` is now
  "cannot subscript 'y': …", `y.len` "no struct type in scope for 'y'". Conversely `y += 1` on such a parameter,
  refused as "compound assignment to slice", compiles.
- **A classic-`for` step with tokens between its value and its `)` is refused** ("expected ')', got number 2"): `i += 1
  2`, `a[0] += 1 2`, `i += 1 ; junk`. They compiled and the extra tokens were ignored (on a struct step `a = b 2` they
  also turned the whole-struct copy into a one-word store). Delete the stray tokens; a second update goes in the body.
- **A constant subscript out of range warns in every build** — `a[5]` on a `u8[5]`, `a[K]` with a const `K` past N,
  `p[0 - 1]` / `s[-1]` on a `*T` / slice: "index 5 is out of range [0, 5) for 'a' (an error under the bounds-checked
  mode)". Nothing in cyrius's corpus, lib or folds draws it.
- **The bounds-checked mode is opt-in** — `--bounds` (build / run / test / fuzz), `CYRIUS_BOUNDS=1` / `=0`, `[build]
  bounds = true` / `false`, or a `#bounds` line in the entry file's leading block (argument > environment > manifest >
  source). A program built under it: `a[i]` past a typed array's DECLARED N exits 134 even inside its rounded storage
  (a `u8[5]` used as 8 bytes: declare `u8[8]`); a negative `p[i]` exits 134 (spell a deliberate one `*(p - 1)`, or wrap
  it in `@unsafe { }`); a constant index out of range is an error; a checked subscript in a `#naked` fn is refused
  (wrap it in `@unsafe { }`); a kernel / EFI image and a `shared;` / `object;` build are refused; `__cyrius_bounds_*` fn
  names are the compiler's. Each checked access is a call — measure a hot loop with the mode before shipping it on.
- **The mode's three spellings are taken.** An environment that exports `CYRIUS_BOUNDS` for another purpose: `1` turns
  the mode on for every compile, and any value but `1` / `0` / empty fails every compile by name ("CYRIUS_BOUNDS must
  be 0 or 1 (or unset)"). A source line that is exactly `#bounds` (a comment before 6.7.8) is a directive — in the
  entry file's leading block it switches the mode on; anywhere else, and `#bounds <text>`, it is refused by name
  (`#boundsx` and `# bounds` stay comments). `[build] bounds` is a known key and must be `true` / `false`.
- **Additive:** `p[i]` on a `*T` (`load16(p + i * 2)` stays valid), `a[i]` on `f64[N]` / `f32[N]` / `bool[N]`, `h.p[i]`
  / `f()[i]` / `o.m()[i]` on a field or callee declared `*T`, and `s[i] = v` / `s[i] OP= v` on a slice local — a slice
  store is bounds-checked in every build, out of range exiting 134 "slice bounds violation" as a read does
  (`store8(slice_ptr(&s) + i, v)` stays the unchecked spelling). Diagnostic texts a tool may match changed: "cannot
  subscript 'x': it is not a typed array, a *T or a slice local - …" (was "… a pointer or scalar is not an array"), "…
  a bare `var a[N]` states no element width - …", "… a subscript takes an integer, f64, f32 or bool element - …", and
  `a[1][2] = 5;` is "a subscript's result is an element, not an array - …" (was "expected '=', got '['"). cx now builds
  a program that returns or receives a 9-16 B struct.
- **Windows hosts:** `cyrius fuzz --poison` now builds each harness in the poison mode (cycc.exe never received
  CYRIUS_POISON before) — a harness that overwrites a redzone stops with exit 86 there, as on Linux and macOS. `cyrius
  build --strict-pin` / `--pie` now hand cycc.exe CYRIUS_STRICT_PIN=1 / CYRIUS_PIE=1, which it does not act on yet
  (filed) — a pin-faithful CI build still belongs on Linux.

### 6.7.7
- **A default in a trait method's parameter list is a compile error** — required signature or default method (it
  compiled and was ignored; the user's decision, 2026-10-09). Defaults go on plain fns and inherent impl methods.
- **Every forward call is arity-checked** (a call to a fn defined later in the file): a wrong count is the same error a
  backward call gets. It compiled and passed garbage for the missing argument.
- **A `: stack` pair stored into one slot through a field, a subscript, `*p` or `OP=` is refused by name** (`h.n =
  f()`, `a[0] = f()`, `*p = f()`, `x += f()` dropped the payload): bind both, `var t, v = f();`, or use `?`.
- **A by-value struct argument is the value it had where it was written** — a later argument's write no longer reaches
  the callee (`rd(b, bump(&b))` read the bumped `b`). Where the copy is needed in TAIL position (`return f(G, n - 1,
  g(acc));`) that call is an ordinary call and no longer runs in constant stack (the user's decision, 2026-10-09); bind
  the later argument first (`var a2 = g(acc); return f(G, n - 1, a2);`) to keep the jump.
- **aarch64: a 9–16 B struct return and a multi-value return agree** — `rethi()` after a struct return, `var a, b =
  f()` of a struct-returning `f`, and a struct received from a multi-value return read the right second word (they
  read a register the callee never wrote, on pi / ecb only).
- **A whole-struct store into a 3 / 5 / 6 / 7-byte global stores exactly its bytes** (it wrote 8, over the next global).
- **A closure literal's `|a, b|` comma no longer shifts the arguments after it** (generic inference, the Str tail-call
  divert, overload routing); an explicit generic call's type arguments `pk<i64, i64>(..)` separate no arguments.
- **`x += 1.5` on an integer place warns**, as `x = x + 1.5` did. **Additive:** tuples (`(a, b)`, `t.0`, `(i64, f64)`
  types, `var t: (i64, i64) = f()`, `a, b = f();`) and default / named arguments (`fn f(a, b = 2)`, `f(1, b: 3)`).
- **`scripts/ci.sh` installs the tarball release.yml packs** (one top-level `cyrius-<v>-x86_64-linux/`); a tarball in the
  old `versions/<v>/` layout is refused by name. A home install.sh made is re-pointed, never written through.

### 6.7.6
- **Every write into an `f32` rounds to f32** — initializers (`var x: f32 = 1.5`), assignments, field stores,
  struct-literal fields, arguments to an `f32` parameter. They stored the f64 bit pattern.
- **A top-level `var v = pair_fn();` is refused by name** (inside a fn it has been since v6.5.67): it kept the tag and
  dropped the payload. Bind both: `var t, v = pair_fn();`.
- **u128**: `+` / `-` carry and borrow across all 128 bits (`b + 1`, `b += 1` alike), comparisons compare all 128
  bits, a plain `b = c` copies the whole value; every other operator on a u128 is refused by name.
- **Refused by name**: `OP=` on a SIMD vector, a typed-array variable, a slice variable or a bare `var b[N]`, and a
  whole-array `a = 8` on a typed-array variable (each operated on the first word / element). Write the long form or
  index an element.
- **A struct-returning call / method / operator result dispatches its operator fn as either operand** (`p.dup() + p`
  calls `P_add`; it integer-added first words). No matching operator fn is refused by name.
- **`println(n)` on a name declared an integer** prints the number (it crashed); a name declared an integer that
  holds a string pointer now prints the number too — declare it `: cstring`.
- **`cyrius.cyml` — git first.** A `path` beside `git` / `tag` is a DEV OVERRIDE, used only in local mode
  (`CYRIUS_LOCAL=1`, `CYRIUS_LOCAL=sigil,libro` or `--local`); a default build builds the tag (commit pin checked) and
  prints one hint line naming the local checkouts it is not using. A dependency resolved from its tag has its own
  `path` entries ignored; an entry with only a local `path`, a local `git` or an absolute path is refused by name.
  The first default resolve adds commit pins to `cyrius.lock` (a one-time diff). `cyrius deps --locked`
  (`CYRIUS_LOCKED=1`) resolves, writes nothing and fails naming each difference — CI lock guards and
  `sed`-the-path-out steps can become `--locked`. Unknown keys are warned. Reference: the guide's *Git first; local
  development is a switch (6.7.6)*.
- **The test scope**: a `[test]` section (`files` — `[build] test` stays a synonym — `stdlib`, `modules`, `defines`,
  `timeout`, `[test.embed]`) and `[deps.X] scope = "test"`, applied to test / bench / fuzz compiles only and kept out
  of `dist/*.deps`; `assert` / `bench` can move to `[test] stdlib`; a per-directory `test.cyml`. Hand-written CI test
  loops can become `cyrius test <dir>`.
- **`cyrius test <file|dir>...`** walks directories recursively; `cyrius tests` is a deprecated alias for 6.7.6 only (removed at 6.7.12: an unknown command, rc 1).
- **`lib/fnptr.cyr`'s x86_64 `fncall8`** passes arguments 7 and 8 in cyrius's order (they arrived swapped for a
  cyrius callee); an 8+-argument C function on x86_64 now needs a shim (`docs/ffi/fncall-abi.md`).
- Folds: mabda **4.2.0** — the 11 `F64_*` are f64 `const`s (they read 0 unless `color_init()` ran; `color_init()` is
  a no-op); patra **1.16.0** — five silent wrong answers are errors or right (LIMIT 0, SUM / MIN / MAX on a non-INT
  column, identifiers over 31 bytes, ORDER BY an unknown or TEXT / BYTES column); niyama **1.1.0** — pcre matches
  past ~250 subject characters are right. Stale `dist/*.deps` sidecars clear on a regenerate.

### 6.7.5
- **`do` is a reserved word.** `loop` is contextual (a keyword only as `loop {` at a statement's start), so a
  variable named `loop` keeps working.
- **`OP=` on a struct value is refused by name** — `a += b` on a struct integer-operated on its first word and never
  called `T_add`; write `a = a + b`. Compound assignment now reaches every lvalue (fields, `p.f`, `*p`, subscripts,
  for-steps), with `>>>=`.

### 6.7.3
- **`true` / `false` are reserved words**, and `!` is a real operator — until 6.7.3 the lexer silently DROPPED a lone
  `!`, so `!x` compiled as `x` and `if (!ok)` meant `if (ok)`. Code that relied on the dropped `!` changes behaviour.
- **A write into a `bool` is checked**: a bool variable, field, parameter, return or const accepts only `true` /
  `false`, a comparison, `!`, `&&` / `||` or another bool — `var b: bool = 1;`, `f(1)` for `b: bool` and `return 1;`
  from a `: bool` fn are refused by name. Reads stay the integers 0 / 1. A bare `return;` in a bool fn is refused.
- **A struct argument whose static type differs from its parameter's is refused by name** (an untyped i64 pointer and
  a typed `*T` still convert). `A = 6;`, `A += 1;` and `&A` on an enum constant are refused by name.

### 6.7.2
- **`const` is a reserved word.** A `const` beside a same-name `var` is a hard error, and so is a const declared twice.

### 6.7.0
- **`trait` is a reserved word.** `impl Trait for T` is checked against the trait (a missing / extra method, a wrong
  arity or an undeclared trait is an error naming it); `impl NoSuchTrait for P` used to compile unchecked.
- **An untyped `self` inside `impl … for T` is `*T`**: `self.x` reads through it, and `T_m(o)` agrees with `o.m()`.
  ⛔ **Arithmetic on an untyped `self` is refused** (`self + n`, `self[i]`, `self += n`, …) — a `*T` steps
  `sizeof(T)`, so the old `load64(self + 8)` idiom would have changed meaning silently. Write `self.field`, or declare
  `self: *T` to step elements. (Free fns with a `self` parameter are untouched.)
- **`var q: T = p;` with `p: *T` copies `*p` at every size** (≤ 8 B it stored the pointer value). Aliasing is
  `var q: *T = p;`.
- **Two traits giving a type the same method name** define `T_A_m` and `T_B_m`, and the plain `p.m()` is an ambiguity
  error naming both (before, both became `T_m` and the last definition won).

---

## 6.6.x

### 6.6.20
- **A redefined fn binds every call to its LAST definition** — before, a non-tail call to an already-defined fn baked
  the FIRST definition. Duplicate fns whose bodies differ change what runs.
- A fn / var / param / enum variant / `use` alias named `sizeof`, `mulh64` or `fncall0`..`fncall8` is refused by name.
- `cyrius deps` refuses a `modules` entry with a `..` component.
- A `kernel;` build under `CYRIUS_DCE=1` NOP-fills instead of compacting (it no longer shrinks a kernel image).

### 6.6.19
- **`[embed]`** — a project embeds files at build time from its manifest; Python / shell embed generators can retire.
- x86 macOS starts real threads (`THREADS_CONCURRENT` = `CHAN_BLOCKING` = 1 on both Mach-O arches);
  `async_await_readable_ms` waits on macOS, Windows and agnos.

### 6.6.18 — a `.deps` sidecar is what the compile-verify proves
- `cyrius distlib`'s sidecar is derived ONLY by compiling the bundle on six targets (x86_64 Linux / Windows / macOS /
  agnos, aarch64 Linux / macOS); `[deps] stdlib` no longer leaks into it, so test-only leaves (`assert`, `bench`)
  stopped reaching consumers. Every bundle gains a compile-verified requires block (`include "dist/<pkg>.cyr"` alone
  compiles).
- **Producers**: `distlib --check` reads every pre-6.6.18 bundle stale — run `cyrius distlib --all` and commit; expect
  the sidecar to shrink. agnos is a verify target (a non-symbol failure on agnos alone is a warning); names nothing
  owns are reported.
- **Consumers**: declare every stdlib leaf you need in your own `[deps] stdlib` — including what a fold you declare
  calls — rather than relying on some producer's over-reporting sidecar. A failed compile prints
  `hint: '<fn>' is defined by stdlib leaf '<leaf>' — add it to [deps] stdlib`; add it, `cyrius deps`, rebuild. A
  stdlib family directory (`lib/unicode/`) is one sidecar entry expanded from the PRODUCER's snapshot — pin at least
  the producer's cyrius.
- `cyrius fuzz --poison` reaches `alloc()`, arenas, `fl_alloc` and any `_a` API through `poison_allocator()`, with
  redzones and `--poison=ab`; an overwrite stops the harness with exit 86 — poison runs can go red where they passed.

### 6.6.17 — the manifest is configuration
- `[build] defines` is read by every `cyrius build` (a `-D` on a CI build line becomes redundant); `[build] dce = true`
  replaces `CYRIUS_DCE=1` on build lines.
- Bare `cyrius test` runs the `[build] test` entry.
- `[coverage] programs` / `--programs` / `--per-entry` put RUN programs in the coverage corpus.
- `lib sync --full` after a pin move leaves a lock `deps --verify` accepts; `lib sync` refuses a lock that still
  carries the previous pin's rows (it names `--relock`) — a CI that runs `lib sync` → `deps` with no `deps --verify`
  can go red after a build-first pin move.
- `p + n` on a `*T` steps `n * sizeof(T)`.
- Scaffolds from `cyrius init --bin` / `cyrius port` before 6.6.17 have `output = "{PROJ}"`.

### 6.6.16
- **Plain-socket writers send with `MSG_NOSIGNAL`** (`sendto`): a seccomp filter that allows `write` but not `sendto`
  kills the process at its first `sock_send_all`.
- **A named struct argument over 8 bytes is a COPY** — the callee copies on entry (a callee mutating it changed the
  caller's struct). `p: *T` + `f(&x)` is the mutating spelling. An `async fn` refuses such a parameter by name.
- `#deprecated` warns through `&fn` too.
- Channels block on arm64 macOS and Windows as on Linux (a full channel dropped the send there), and a
  `max_concurrency` permit really limits there.
- `sys_setsockopt` resolves on every target (the agnos peer declines with -38).
- Fold ganita 1.2.13: `ganita_mat_svd` is a new algorithm (every SVD's bits change); non-convergence is −3 (was −1),
  non-finite input is refused across linalg (−2), `eigen_sym`'s allocation failure is −1 (was −2).

### 6.6.13 — `f64_le`, `f64_ge`, `f64_trunc` are compiler builtins
- The three were `lib/math.cyr` fns; they are builtins (no include needed), bit-for-bit the old results, and their
  names are RESERVED. Every `name(...)` call keeps compiling, faster.
- **At the pin bump, re-vendor `lib/math.cyr` in the same commit** (`cyrius deps`): a vendored pre-6.6.13
  `lib/math.cyr` defines them and fails with `expected identifier, got reserved keyword 'f64_le'`. Regenerate any
  `dist/` bundle that embeds it.
- Fold bayan 1.5.10: `bayan_json_parse` returns a nested object or array as ONE value (its raw source span), so its
  members are no longer top-level pairs; TAB / CR end a bare value; malformed input stops the parse.
  `bayan_json_v_obj_get` / `json_v_obj_get` are `#deprecated` — use `bayan_json_v_obj_get_by_cstr`.

### 6.6.12
- Fold sigil 3.13.5: `ENOSYS`, `ENOTEMPTY`, `ENODATA`, `EOVERFLOW`, `EOPNOTSUPP`, `EADDRINUSE`, `ECONNREFUSED` and
  `ETIMEDOUT` carry the BSD values on macOS (they were Linux values program-wide there).

### 6.6.11
- The qualified-enum check refuses a stale `Enum.X` spelling that compiled only because the qualifier was ignored.

### 6.6.10
- Every tree walker (`cyrius test` / `fuzz` / `bench` / `audit` / `coverage` / `deps --lock` / `--verify`, …) fails by
  name on a directory it cannot list — it used to read it as empty and pass.

### 6.6.9
- An aarch64 build that hides a reachable undefined TAIL call FAILS (it built and hit SIGILL at run time), and so does
  a build where an unreachable fn's undefined call masked a reachable one, on every target; `--allow-undef` still
  downgrades. aarch64 / Mach-O builds print the same `undefined function` warnings as x86.
- `#deprecated` / `#must_use` / `#pure` warnings appear on every backend; a bare `#deprecated` is an error.
- New warnings: `struct 'X' redefined with a different layout`; `duplicate symbol 'X' is an enum constant here and a
  global variable before it`.
- Windows `open()` gives `O_NOFOLLOW`, `O_DIRECTORY` and `O_CREAT|O_EXCL` their POSIX meaning.
- Every first-party `lib/` module includes what it calls; a stdlib-only project gains a `cyrius.lock` on its next
  `cyrius deps` / `build`; an absolute `$TMPDIR` moves the CLI's private temp dir.

### 6.6.8
- `cyrius coverage` counts a reference only as a WHOLE identifier in test code (substrings, comments and string
  literals counted before), so a `--min` floor can read lower; `cyrius -v coverage` lists what to cover.
- `cyrius vet` / `cyrius deny` see exactly the includes the compiler sees: a commented-out include no longer counts,
  and `..` anywhere in an include path is a traversal.

### 6.6.0 – 6.6.2 — `Result` / `Option` / `Either` are VALUES
- `Result` / `Option` / `Either` are the value form (a register pair; construction allocates nothing). **157 stdlib
  fns became pair-returning**, so `var fd = tcp_socket();` is enough to be hit.
- **Bind both halves**: `var t, v = f();`. A single-variable bind of a pair-returning call is refused by name (inside
  a fn since v6.5.67; at top level since 6.7.6).
- ⚠ There is no `t, v = f();` re-assignment form, and assigning a pair-returning call to an existing single variable
  (`rt = f();`) silently keeps only the tag — a loop that re-polls a `Result` binds a fresh pair per iteration and
  copies it into the carried one.
- `payload()` is DELETED (a Result read binds both halves; a boxed read is `boxed_payload`); `tag()` is RETIRED (on a
  box it silently returned the pointer; use `boxed_tag`). `tagged_new()` was restored at 6.6.2 in `lib/boxed.cyr`.
  `cyrius distlib` refuses a bundle that still calls `payload` or `tag`.
- Arity changed: `result_unwrap`, `err_code_of`, `unwrap`, `result_unwrap_or`.
- ⛔ A `Result` returned through `callptr` is truncated to its tag with NO diagnostic (the callee is a run-time pointer)
  — trace every fn-pointer dispatch by hand.
- Drive the site list from `cyrius build`, not from a grep for the deleted names: a site that binds a `Result` and
  tests it without unwrapping has nothing to grep.
