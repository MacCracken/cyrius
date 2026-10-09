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
