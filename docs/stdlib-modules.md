# Standard Library — Module Index

> Categorized inventory of the Cyrius standard library: **99 `lib/*.cyr`
> modules** (vendored sibling distfiles folded byte-identical, sandhi-pattern)
> with **0 git deps**. This is the *what-exists* map; for per-function
> signatures see [`stdlib-reference.md`](stdlib-reference.md).

## Fold-in lineage

Sibling-distfile **fold-in lineage** (sandhi-pattern: byte-identical
vendor at the patched tag, removed from `[deps]`):

- v5.7.0 — `sandhi` (HTTP/2 + JSON-RPC + service discovery + TLS policy; 15,092 lines at the current 1.9.9 fold)
- v5.8.0 — `vani` (audio distlib; replaced inlined `lib/audio.cyr`)
- **v5.8.65 stdlib foldin** — sakshi 2.2.3 (tracing), patra 1.9.3 (storage), sigil 3.0.1 (security), yukti 2.2.2 (hardware enumeration), sankoch 2.2.4 (compression), and re-folded vani at 0.9.2
- **v5.9.0** — niyama 1.0.1 (regex; 5 engines: bre / re2 / pcre / fuzzy / vim; 6,689 lines at the current 1.0.6 fold)
- **v6.0.x** — mabda 3.0.1 (GPU integration)
- **v6.1.25** — bayan 1.0.0 (data-format & big-integer **carve** OUT of stdlib: json / toml / cyml / csv / base64 / bigint / u128 → `lib/bayan.cyr`, public fns renamed `bayan_*` with back-compat aliases; opt-in `include "lib/bayan.cyr"`).
- **v6.1.26** — ganita 1.0.0 (linear-algebra & advanced-math **carve**: matrix + linalg + the advanced half of math → `lib/ganita.cyr`, renamed `ganita_*` with aliases. Closes Phase E — the stdlib data/math carve).

Mabda (GPU integration) folded into stdlib at 3.0.1 (v6.0.x,
sandhi-pattern), removed from `[deps]`; with mabda vendored its
transitive `agnosys` is no longer pulled, leaving zero `[deps.*]`
git resolutions.

The folded distlibs keep their own upstream repos and own API docs —
this index only records the module's presence + fold tag. The folds at
sandhi / sigil bump regularly (e.g. sandhi 1.4.10 / sigil 3.7.8 at
v6.1.22); the version in the category table is the *initial* fold, not
the current pin (see [`ecosystem.md`](ecosystem.md) for live pins).

## First-party additions

- v5.7.35 — `lib/random.cyr` (kernel entropy via getrandom) and
  `lib/security.cyr` (Landlock policy enums).
- v5.8.49–.52 + .60 — the `lib/unicode/` family (categories / casefold /
  NFC / NFD / NFKC / NFKD per UAX #15 against Unicode 17.0.0). The
  compat-decomp data uses a 2-table IDX+DATA encoding (~87 KB total — 80%
  smaller than fixed-width would have been; per the v5.8.60 mid-slot
  redesign).
- v6.0.x — `lib/tls_native.cyr`, the sovereign native TLS 1.3 stack
  (client + server, sigil-backed X.509 chain verification). The **default**
  TLS backend since v6.1.21 (`-D CYRIUS_TLS_LIBSSL` opts back to the
  libssl bridge). v6.2.4 added a pluggable transport vtable
  (`tls_native_set_transport`); v6.2.5 split the 5,857-line monolith into a
  302-line hub + 6 focused modules (`tls_native_{lowlevel,keysched,ctx,hs13,
  hs12,conn}.cyr`) — logic-preserving, the public API is unchanged.
- **v6.5.7–.9 — no new module files; new surface inside existing ones.** The
  syscall-wrapper pass extended `lib/io.cyr`'s portable `x*` family with
  `xmkdir` / `xmkdir_p` / `xsymlink` / `xreadlink` / `xlink`, added
  `signal_default` to `lib/syscalls.cyr` and `sys_chdir` to the syscall peers
  (v6.5.7); `lib/thread.cyr` gained `thread_create_detached` + `thread_is_done`
  (v6.5.8); `lib/alloc.cyr` gained growable arenas and the `ARENA_FULL_*`
  exhaustion policy (v6.5.9). Per-function detail in
  [`stdlib-reference.md`](stdlib-reference.md).

## Categories

| Category | Modules |
|----------|---------|
| Core | string, fmt, **alloc** (global bump + arenas + the `Allocator` vtable; growable arenas + `ARENA_FULL_*` exhaustion policy since v6.5.9), io, vec, slice, str, args, fnptr, flags |
| Types | tagged (Option), result (Result + ? operator; v5.8.28-.32), hashmap, hashmap_fast, trait, assert, bounds |
| System | syscalls, callback, process, bench, **sys** (uname / sysinfo / is_root introspection; v6.1.28) |
| Concurrency | thread (clone+mmap, mutex, MPSC), thread_local, atomic, async, sync (mutex/once over futex), freelist |
| Testing & bench tooling | **test** (assertion/test-runner primitives), **regression** (bench-regression harness), **audit_walk** (source-tree audit walker) |
| Math/regex (stdlib primitives) | regex, math (F64 constants + basic ops + gcd/lcm + f64_parse + f64-builtin polyfills) |
| **SIMD** | **simd** — typed vectors (f32v4/f64v2/f64v4/f32v8 + integer vectors i8v16/i16v8/i32v4/i64v2 + unsigned) + packed flat-array verbs (`f32v_`/`f64v_`/`iv_` add/sub/mul/div/sqrt/abs/fmadd/dot/scale/axpy, `iv_dp8`); **Phase 5 complete (v6.4.32)** on all four backends — x86 SSE+AVX2, aarch64 NEON, Win64 PE (value-form params + returns), cx bytecode (per-lane scalar). See `lib/simd.cyr`. |
| **Data (protobuf)** | **protobuf** — protobuf proto3 wire encode/decode (`lib/protobuf.cyr`). |
| **Data formats + big-int (bayan)** | **bayan** — json / toml / cyml / csv / base64 / bigint (`u256`) / u128; folded v6.1.25, opt-in `include "lib/bayan.cyr"`; canonical `bayan_*` API + legacy aliases (`json_parse`, `u256_add`, …). Consumers of `ws`/`sigil`/`patra`/`tls` (which call carved fns) must include bayan. |
| **Linear algebra + advanced math (ganita)** | **ganita** — matrix (`ganita_mat_*`) + linalg (LU/det/inv/Cholesky/QR/least-squares/eigen/SVD) + advanced math (transcendental + fibonacci/binomial); folded v6.1.26, opt-in `include "lib/ganita.cyr"`; `ganita_*` + legacy aliases (`mat_mul`, `f64_pow`, …). Keep stdlib `math` in scope (f64-exp/ln polyfills). |
| Unicode | unicode/categories, unicode/casefold, unicode/normalize (NFC/NFD/NFKC/NFKD), unicode/_decode |
| Crypto | sha1, keccak, ct (constant-time primitives), overflow, **random** (kernel entropy via getrandom) |
| Sandboxing | **security** (Landlock policy enums; v5.7.35) |
| Network | net, http, ws, ws_server, tls, **tls_native** (sovereign TLS 1.3 client+server, sigil X.509 — default backend since v6.1.21), **sandhi** (HTTP/2 + RPC; folded v5.7.0) |
| Regex | **niyama** (5 engines: bre / re2 / pcre / fuzzy / vim; folded v5.9.0) |
| Filesystem | fs |
| Audio | **vani** (ALSA PCM + ring buffer + mixer; folded v5.8.0, refolded v5.8.65) |
| Logging | log (structured, over sakshi) |
| Time | chrono |
| Interop | mmap, dynlib, fdlopen (foreign-dlopen), cffi |
| Identity | pwd, grp, shadow, pam |
| Tracing | **sakshi** (folded v5.8.65) |
| Database | **patra** (folded v5.8.65) |
| Security | **sigil** (folded v5.8.65) |
| Hardware | **yukti** (folded v5.8.65), **dxgi** (Windows DXGI GPU/adapter enumeration) |
| UI / E2E testing | **yantra** (folded v6.2.26; UI + end-to-end test framework) |
| Compression | **sankoch** (folded v5.8.65) |
| GPU | **mabda** (folded v6.0.x, now 4.0.8; opt-in `include "lib/mabda.cyr"`) |

## See also

- [`stdlib-reference.md`](stdlib-reference.md) — per-function API reference
- [`ecosystem.md`](ecosystem.md) — live folded-distlib pins + downstream consumers
- [`api-surface.snapshot`](api-surface.snapshot) — generated public-symbol surface (gated in `check.sh`)
