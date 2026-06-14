# 2026-06-14 — stdlib/lib constant-name collisions with conflicting values (silent under co-link)

> **Class:** two modules in `cyrius/lib/` define the **same symbol name** with
> **different integer values**. Because cyrius has a flat symbol namespace and
> **does not warn** on duplicate `var`/`const`/enum-member definitions that
> disagree on value (it warns on duplicate `fn`, but not on data symbols), the
> "last definition wins" — and whichever consumer's translation unit pulls both
> modules silently gets one module's value substituted into the other's code.
>
> **Status:** filed for triage. The motivating instance (below) is already fixed
> downstream; this issue tracks the *stdlib/lib-side* duplications so the same
> footgun stops recurring.

## How this surfaced

owl 1.4.0 swaps its VCS gutter from `git` to the **sit** library (`sit_diff_path`).
That makes owl co-link **vyakarana** (its syntax tokenizer) and **sit → patra**
(sit's object store, a SQL/B+tree DB). Both define `TK_*` token-kind constants:

| symbol | patra `enum TokType` (src/sql.cyr) | vyakarana `var` (public token-kind palette) |
|--------|-----------------------------------:|--------------------------------------------:|
| `TK_IDENT` | `2` | `0` |
| `TK_COUNT` | `36` | `10` |

vyakarana's values won, so inside patra's SQL parser `TK_IDENT` became `0` —
**aliasing patra's own `TK_EOF = 0`**. Every SQL identifier tokenized as EOF,
`sql_parse()` failed on valid queries (`SELECT content FROM objects WHERE …`),
`patra_query` returned 0, and owl's diffs came back as "all lines added."

No `fn` collision, no build error, no warning. Proven by renaming patra's two
colliding constants and watching the bug vanish.

**Downstream fix shipped:** patra **1.11.2** namespaces its SQL enum
`TK_* → SQLT_*` (internal-only, 747/747 tests green). That clears the immediate
break. But the *enabling condition* lives here: (a) cyrius silently resolves
conflicting-value data-symbol collisions, and (b) several `cyrius/lib/` modules
duplicate constants that should have a single source of truth.

## Two cleanup buckets (the scan)

A sweep of `cyrius/lib/*.cyr` for same-named constants with **distinct** values,
excluding same-file `#ifdef` platform variants. (Per-OS values that genuinely
differ by target — e.g. macOS `O_CREAT = 0x200` vs Linux `64`, syscall numbers
that legitimately differ per arch inside `syscalls_*` — are **expected** and
excluded; the items below are cross-*module* duplications that collide on a
single target.)

### Bucket 1 — `ERR_*` error codes, each lib rolls its own (HIGH — same class as the owl bug)

Every lib defines its own error enum with conflicting values. Co-linking any two
(owl already pulls sigil + sankoch + sakshi via sit; yukti is widely consumed)
silently corrupts whichever loses:

| symbol | values (module) |
|--------|-----------------|
| `ERR_IO`              | `8` (agnosys), `6` (sigil), `14` (yukti) |
| `ERR_INVALID_INPUT`   | `1` (sankoch), `5` (sigil) |
| `ERR_UNKNOWN`         | `7` (agnosys), `1` (sakshi) |
| `ERR_PERMISSION_DENIED` | `3` (agnosys), `6` (yukti) |
| `ERR_TIMEOUT`         | `5` (sakshi), `9` (yukti) |

These are the dangerous ones: generic names, semantically "the same" error, but
divergent integers. A consumer that co-links e.g. sigil + yukti and compares a
returned code against `ERR_IO` gets a silent mismatch.

### Bucket 2 — `SYS_*` syscall numbers hardcoded outside `syscalls` (MEDIUM — collision + aarch64 breakage)

Several modules hardcode x86_64-Linux syscall numbers in their own
`var SYS_* = …` instead of using the arch-aware `syscalls_*` module. This both
collides with `syscalls`' canonical constant *and* is wrong on aarch64:

| symbol | hardcoded (module) | canonical `syscalls_aarch64_linux` |
|--------|--------------------|-----------------------------------:|
| `SYS_BIND`        | `49` (net)   | `200` |
| `SYS_SOCKET`      | `41` (net)   | (aarch64 differs) |
| `SYS_CONNECT`     | `42` (net)   | (aarch64 differs) |
| `SYS_LISTEN`      | `50` (net)   | `201` |
| `SYS_SETSOCKOPT`  | `54` (net)   | `208` |
| `SYS_GETDENTS64`  | `217` (fs)   | (aarch64 differs) |
| `SYS_GETRANDOM`   | `318` (patra)| `278` |
| `SYS_CLOCK_GETTIME` | `228` (bench) | (yukti also defines `113`) |
| `SYS_PPOLL`       | `271` (yukti)| `73` (syscalls x86_64) |

On x86_64-Linux these happen to match `syscalls_x86_64_linux`, so the collision
is currently value-identical there and harmless *today* — but it's a latent
aarch64 break and a name collision waiting for a value to drift.

> **Verify:** `EAGAIN` showed `11` (agnosys) vs `35` (syscalls) in the scan —
> may be a genuine agnos-vs-linux errno difference (expected, like the per-OS
> `O_*`/`MAP_*` values the scan otherwise excluded) rather than a collision.
> Confirm before touching.

## Recommended direction (for discussion)

1. **Single source of truth for shared constants.**
   - `SYS_*` / `O_*` / `MAP_*` / errno: `syscalls_*` (and its `linux_common`)
     own these per-target; other libs should reference, not redefine. Drop the
     hardcoded `SYS_*` from `net`/`fs`/`patra`/`bench`/`yukti`.
   - `ERR_*`: either a shared error-code module the ecosystem imports, or each
     lib namespaces its enum (`SIGIL_ERR_*`, `YUKTI_ERR_*`, …) the way patra
     1.11.2 just namespaced `SQLT_*`.

2. **Compiler guardrail (the real fix for the silent-corruption class).**
   Have cycc **warn (or error) on duplicate `var`/`const`/enum-member symbols
   whose initializers disagree**, mirroring the existing duplicate-`fn` warning.
   A value-identical redefinition can stay a note; a value-*conflicting* one is
   almost always a latent bug. This would have caught the patra/vyakarana
   `TK_IDENT` collision at compile time instead of as a wrong-output bug found
   by a downstream consumer.

## References

- Downstream fix: patra **1.11.2** (`enum TokType` `TK_* → SQLT_*`).
- Consumer that hit it: owl **1.4.0** (sit library swap; co-links vyakarana + sit→patra).
- Related ecosystem-lib issues: `2026-06-11-thoth-lib-sync-ignores-deps-stdlib.md`,
  `2026-06-12-ecosystem-lib-daimon-class-refold.md`.
