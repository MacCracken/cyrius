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
