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

### 6.7.12

#### The standard library

**`lib/ws_server.cyr` includes `lib/ws.cyr` (D11, the user 2026-10-15)**
- `lib/ws_server.cyr` no longer declares its own `WS_OP_CONTINUATION` / `WS_OP_TEXT` / `WS_OP_BINARY` / `WS_OP_CLOSE` /
  `WS_OP_PING` / `WS_OP_PONG` / `WS_OPEN` / `WS_CLOSING` / `WS_CLOSED` vars: it includes `lib/ws.cyr`, and the nine
  are ws.cyr's enum constants (same values). `include "lib/ws_server.cyr"` now also brings ws.cyr's client fns (DCE
  drops the unused ones), `WS_CONNECTING` and `WS_RECV_MAX_PAYLOAD`. With ws_server alone, a write to one of the nine
  (`WS_OPEN = 5;`: "cannot assign to enum constant 'WS_OPEN'") or its address (`&WS_OPEN`) stops compiling;
  reading them is unchanged. A program that defines its own `WS_CONNECTING` or a `ws_*` fn beside ws_server now
  gets the duplicate-definition warning (its own, the last definition, still wins).
- `cyrius distlib` records `ws` for a bundle that reads a `WS_*` name with neither leaf in its unit (6.7.11 refused it
  as a tie, "more than one stdlib leaf could own it (ws, ws_server)") — yantra's distlib converges again, its bundle
  byte-identical.

**agnos: the net arms take only a tagged socket fd**
- On agnos, `sock_bind` / `sock_listen` / `sock_accept` / `sock_connect` on an fd that is not one `tcp_socket()`
  handed out (a failed open's `-1`, a file or stdio fd, `AGNOS_SOCK_TAG + 8` and up) now return `Err(9)` (EBADF) for a
  negative fd and `Err(88)` (ENOTSOCK) for any other, and `net_connect_nb` returns `_NET_CONN_NB_ERR` — with no
  table write and no kernel call. They used to act on socket slot `fd & 7` (a `-1` bound, listened, accepted and
  connected on slot 7) and could answer `Ok`. Linux already answered these errnos; a program that passed only
  sockets sees no change.

**epoll_event readers: `epoll_event_events` / `epoll_event_data` / `const EPOLL_EVENT_SIZE`**
- New beside `epoll_event_new` in the x86_64 Linux, aarch64 and x86-macOS peers: read one element of a
  `sys_epoll_wait` array (or an `epoll_event_new` result) in the peer's layout, and step by `EPOLL_EVENT_SIZE` (12 on
  x86_64 and x86-macOS, 16 on aarch64). A hand-gated `load64(ev + 4)` / `load64(ev + 8)` per arch can become
  `epoll_event_data(ev)`. ⚠ A program that declares its own `EPOLL_EVENT_SIZE` after including `lib/syscalls.cyr`
  now stops compiling ("'EPOLL_EVENT_SIZE' is already declared as a top-level const") — drop the copy; one that
  defines its own `epoll_event_data` / `epoll_event_events` gets the duplicate-fn warning (its own, the last, wins).
- `lib/async.cyr`'s epoll reactor reads each event at the peer's stride. It read every arch at 16, so on x86_64 the
  2nd..8th event of one wait were read off by 4, 8, … bytes — a stale or garbage fd (the real one re-reported by the
  next wait). A reactor woken by several fds at once now wakes all their waiters from that one wait. aarch64 is
  unchanged.

#### The cx target

**cx programs up to 4 MiB of bytecode (D12, the user 2026-10-15)**
- `cycc_cx` holds 4 MiB of bytecode (it stopped at 512 KiB with a bare `error: codebuf overflow`); past it, it refuses
  by name: `error: cx bytecode exceeds the cx code region (4194304 B): <n> B emitted when fn '<name>' (its code starts
  at byte <off>) reached it — build this program for a native target`. cxvm's guest memory is 8 MiB (it was 1 MB) and
  it reads a `.cyx` up to that plus its 8-byte header (`error: .cyx exceeds cxvm's guest memory (8388608 B of code and
  data)` past it); a `.cyx` an older cycc_cx wrote runs unchanged. Guest addresses from 1 MB to 8 MiB are now ordinary
  memory (they trapped as "guest address out of range"), and the guest stack starts at 8 MiB, so recursion runs about
  eight times deeper before "guest stack overflow" (the VM stacks hold 524288 entries, so a runaway recursion still
  meets the guest-stack trap first). `lib/tls.cyr`, `lib/tls_native.cyr` and `lib/sigil.cyr` stay refused by name;
  the message no longer cites a 512 KiB `.cyx`.

**cx: honest refusals from four wrappers (D13, the user 2026-10-15)**
- On cx, `cyr_mmap` returns -1, so `mmap_anon` returns 0 — it returned a HOST address the guest could not use (a
  non-zero pointer; the first access trapped). `sys_pipe` (its buffer left as it was), `sys_fstat` and `sys_unlink`
  return -38 (-ENOSYS) where they returned -14 (-EFAULT); `sys_unlink` never removed the file on cx and still does
  not. A cx program that tested `< 0` or `== 0` sees the same branch; one that compared against -14 must read -38.
  Native targets are unchanged (the arms are `CYRIUS_TARGET_CX` only).

### 6.7.11

Break 2, repair 1. Each block names its CHANGELOG [6.7.11] bite; the decisions are the user's (2026-10-13, D1–D45).
The changes that went beyond a decision's text are filed for confirmation in 6.7.12
(`docs/development/issues/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md`).
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
- **`cyrius test <file|dir>...`** walks directories recursively; `cyrius tests` is a deprecated alias for 6.7.6 only.
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
