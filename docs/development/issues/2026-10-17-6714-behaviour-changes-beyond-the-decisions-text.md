# The 6.7.14 changes beyond the decisions' text — confirm or restore each — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-17 at the 6.7.14 integration from the release-docs pass (one drafter per lane,
reading each lane's handoff, commits and issues against the decisions asked at the open, D1–D61). Each change below
shipped in 6.7.14 and changes what an existing program does, compiles or prints in a way no decision's text names (or
narrower than its text). Each was taken by its lane as a false refusal lifted, a parity rule, or the consequence of a
decided binding; the user confirms or restores each one at the 6.7.15 open (the 6.7.11 – 6.7.13 precedent).
**Placement:** 6.7.15 — repair 5 (decisions at its open; filed at the 6.7.14 integration, 2026-10-17) — never 7.x.
**Severity:** Low — decisions to confirm, not defects; each change is in CHANGELOG [6.7.14] and
ecosystem-migration § 6.7.14.

## Generics
1. **D5 beyond:** a struct FIELD `Vec<Box<Later>>` whose `Later` is declared below the struct is refused (it compiled).
2. **D6 beyond:** in a signature, `m: Box<u8>`, `m: Box<Result>`, a tuple type argument, `m: Box<Nonexist<u8>>` and
   `m: Box<Vec<nosuch>>` are refused — each was already refused on a local; D6 named only undeclared type arguments.
3. **D8's consequences:** `gst(q)` with `fn gst<T>(x: T) { return x.v; }` and a `*S` local is refused (it exited 5);
   a declaration-zone `var G = gd(&GS);` with `fn gd<T>(x: *T): T` is refused "'gd$S' returns a struct by value" (it
   exited 0).

## The frontend
4. **No decision asked:** another file's private const fn called in a skipped const arm is refused (it compiled).
5. **D11's reading applied to a float literal:** a forward read of a declaration-zone float-literal global sees its
   value (it saw 0), and an earlier initializer's call that writes it keeps its write. (D11's ordering for a named
   constant is filed separately as a decision:
   [named-constant redeclaration ordered unlike a literal](2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md).)
6. **Beyond the filed shapes:** `var B: bool = false; var B: bool = true;` and `var a = 5; var a = true;` warn as a
   redeclared global with a different value (`true` / `false` compare as 1 / 0).

## Tools
7. **Beyond 6.7.13's D37:** `lib/net.cyr`'s `sock_send_a` / `sock_recv_a` are declared `: Result`, so `cyrius header`
   prints `cyr_val2` for them.
8. **A design question answered without the user:** a killed CLI forwards the signal to its git child and waits for it
   (a git that ignores TERM delays the exit — filed for 6.7.15:
   [the unbounded wait](2026-10-16-kill-handler-waits-unbounded-for-a-forwarded-git.md)).
9. **D47 beyond its question:** a loose file under a project that pins an INSTALLED different cyrius is checked by the
   language server's own CLI, not the pinned one (6.7.13 ran the pinned CLI).
10. **Beyond the filed surface:** `fn e1( )` prints `e1(void)` in a header (it printed `e1()`).

## Platform
11. **D57 beyond (stronger):** the six 48-byte CTL entries are applied as CONFIRMED (the lane identified the six
    DarkMatter intermediates and confirmed them on cass), not "marked unconfirmed".
12. **D61 beyond:** the stdlib's syscall peers gain public `SYS_POLL` (and `SYS_EPOLL_WAIT` on aarch64), so a program
    that declares its own `SYS_POLL` with another value now builds a different binary ("last definition wins").
13. **D59 narrower:** cybs is not in the aarch64 tarball (no aarch64 form), and `ts_test_runner` ships but fails every
    `.ts` file there (filed for 6.7.15).
14. **A consequence of making PE failures visible:** every failed Windows open answers its errno (it was -1), an
    `O_NOFOLLOW` read-only open of a directory answers -13, and a seek on fd 0 / 1 / 2 answers -9 (it was 0; the raw
    handle cause is filed for 6.7.15).

## Structs
15. **No decision asked:** a program's own `struct Result` (or `Option` / `Tagged`) passed by value is the struct — a
    heap handle `var h: Result = alloc(16); g(h)` now passes a COPY (the callee's write no longer reaches the caller:
    199 became 102); `h = t` copies and `return h;` from a `: Result` fn returns the struct.
16. **6.7.13's D1 read for `**pp`:** an over-8 B `if (c) { **pp } else { **qq }` is refused (it compiled and crashed).
17. **D19 beyond:** `return &pu;` of a `*U8` of ANOTHER struct, and of a handle global of another struct, are refused
    with the slot message.

## Receives and multi-value
18. **D53 narrower:** only `*u8` / `*i8` destinations exempt a string literal; `var s: *i64 = "abcdefgh";` and a one-byte
    struct's `*B1` still warn.
19. **D24 beyond:** the statement `(s).a;` compiles as a discarded read, while the unwrapped `s.a;` is still refused.
20. **D27 beyond:** the assignment refusal also covers `: f32`, `: i32`, `: cstring`, an enum, `u128` destinations and
    parameters (each compiled on the lane base).
21. **D42 beyond its question:** three names from a fn with no `ret2` whose if / else arms each `return (a, b);` are
    refused (it compiled, exit 88) — inside D42's option text, beyond its `ret2` question.

## Stdlib
22. **6.7.12's D16 beyond:** `TLS_SHA256_CTX_LEN` (a literal public var) is inert like the D16 twins — a fifteenth name.

## Infra
23. **The asm issue's own surface, no decision:** `out dx, ax` / `out dx, eax` emit a 16 / 32-bit write (66 EF / EF;
    they emitted the one-byte EE), which changes what an already-compiled kernel's port writes do.

## Vectors
24. **D31 beyond (wider):** a captured vector of ANOTHER 16-byte vector type passes a value-form parameter by the
    16-byte class rule (an `f32v4` capture into `x: f64v2` gives 42) — D31's text said another type is refused with the
    local's words; only exact-type parameters (`f32v4`, the 32-byte types) refuse it.
25. **D32 beyond (wider):** the same for a dereference — an `f32v4` `*pf` into `x: f64v2` is accepted.
26. **D38 beyond:** the method-result refusal also covers struct, `f64` and pointer destinations and a for step
    (`var x: Pt = s.mv();` faulted, `var x: f64 = s.mv();` compiled, `var x: *i64 = s.mv();` warned — all refused now);
    the by-name `var x: f64 = mkv(..);` still compiles (filed for 6.7.15).
27. **D41 beyond:** a `union` named like a vector type counts too; and a vector-named struct over 8 B, declared below a
    fn that takes it by value and called above that fn's definition, moves from a refusal to a fault (the filed
    forward-call parameter issue covers it).
28. **No decision asked:** a vector fn that returns a call to a missing fn and is never called builds with the
    undefined-function warning (it was refused), by 6.7.13's rule for the unwrapped local.
29. **D51 vs D31:** D51 (2026-10-16) kept a captured vector into a value-form parameter refused on Windows; D31 A (the
    same day) accepts it on every target — the lane applied D31 (same answer on every target), so D51's capture clause
    is superseded.

## Acceptance

Each item answered keep or restore at the 6.7.15 open; a restore is a bite in 6.7.15 with its row; a keep closes the
item with a line in CHANGELOG [6.7.15].
