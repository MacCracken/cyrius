# Standard Library — Module Index

> Categorized inventory of the Cyrius standard library: **106 `lib/*.cyr`
> modules** plus the `lib/unicode/` family (3 modules and 4 data / decoder sidecars), at 6.7.9 —
> the twelve folded stdlibs vendored byte-identical among them (sandhi-pattern), with **0 git
> deps**. Every module appears once in the category table below, the per-OS / per-target peers
> and the `tls_native_*` splits in a row of their own (their public surface IS the parent's).
> This is the *what-exists* map; for per-function signatures see
> [`stdlib-reference.md`](stdlib-reference.md). Re-derive the count with `ls lib/*.cyr | wc -l`
> and `ls lib/unicode/`.

## Fold-in lineage

Sibling-distfile **fold-in lineage** (sandhi-pattern: byte-identical
vendor at the patched tag, removed from `[deps]`):

⚠ This list records **fold-in events** — which release first vendored each dep.
It is history and does not move; current fold versions live in
[ecosystem.md](ecosystem.md)'s gated table.

- v5.7.0 — `sandhi` (HTTP/2 + JSON-RPC + service discovery + TLS policy)
- v5.8.0 — `vani` (audio distlib; replaced inlined `lib/audio.cyr`)
- **v5.8.65 stdlib foldin** — sakshi 2.2.3 (tracing), patra 1.9.3 (storage), sigil 3.0.1 (security), yukti 2.2.2 (hardware enumeration), sankoch 2.2.4 (compression), and re-folded vani at 0.9.2
- **v5.9.0** — niyama 1.0.1 (regex; 5 engines: bre / re2 / pcre / fuzzy / vim)
- **v6.0.x** — mabda 3.0.1 (GPU integration)
- **v6.1.25** — bayan 1.0.0 (data-format & big-integer **carve** OUT of stdlib: json / toml / cyml / csv / base64 / bigint / u128 → `lib/bayan.cyr`, public fns renamed `bayan_*` with back-compat aliases; opt-in `include "lib/bayan.cyr"`).
- **v6.1.26** — ganita 1.0.0 (linear-algebra & advanced-math **carve**: matrix + linalg + the advanced half of math → `lib/ganita.cyr`, renamed `ganita_*` with aliases. Closes Phase E — the stdlib data/math carve).
- **v6.2.26** — yantra 1.0.0 (UI / end-to-end testing: WebDriver + Appium + Chromium-CDP RPC).

Mabda (GPU integration) folded into stdlib at 3.0.1 (v6.0.x,
sandhi-pattern), removed from `[deps]`; with mabda vendored its
transitive `agnosys` is no longer pulled, leaving zero `[deps.*]`
git resolutions.

The folded distlibs keep their own upstream repos and own API docs —
this index only records the module's presence and the release that first
folded it. Every fold is re-vendored as it releases, so the release named in
the category table is the *initial* fold, not the current pin (see
[`ecosystem.md`](ecosystem.md) for live pins).

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
- **v6.6.x** — `lib/boxed.cyr` (v6.6.2: the runtime-tagged BOX primitives — `tagged_new()` restored under
  names that cannot be confused with the value form); `lib/alloc_cx.cyr` (v6.6.6: the cx bytecode target's
  allocator peer, a platform sub-module); `lib/tls_hostid.cyr` (6.6.13/6.6.14: one host-identity classifier —
  IP literal vs DNS name, RFC 9525 §6.3 — shared by the native and libssl TLS backends, internal to the TLS
  stack); `lib/poison.cyr` (6.6.18: the shared poison core behind `cyrius fuzz --poison` — fill byte,
  redzones, report, exit 86 — and `poison_allocator()`).
- **6.7.x — no new module files; new surface inside existing ones** (6.7.9): `sys_ppoll` in every
  syscall peer (and `sys_ioctl` / `sys_fstatat` on agnos, as -38 declines), `sock_set_nodelay` in
  `lib/net.cyr`, `f64_parse_n` in `lib/math.cyr`.

## Categories

| Category | Modules |
|----------|---------|
| Core | string, fmt, **alloc** (global bump + arenas + the `Allocator` vtable; growable arenas + `ARENA_FULL_*` exhaustion policy since v6.5.9), io, vec, slice, str, args, fnptr, flags |
| Types | **boxed** (runtime-tagged BOX primitives; v6.6.2), tagged (Option / Either), result (Result + `?` operator; v5.8.28-.32 — **all three are the value form since v6.6.0**: a payload variant returns `(tag, payload)` in a register pair, so construction allocates zero bytes), hashmap, hashmap_fast, **hashseed** (per-process hash seed + finalizer shared by both hashmap variants — closes a HashDoS where an attacker precomputes a colliding key set offline from published constants; measured 934× degradation on 8192 keys before it landed), trait, assert, bounds |
| System | syscalls, callback, process, bench, **sys** (uname / sysinfo / is_root introspection; v6.1.28) |
| Concurrency | thread (OS threads on Linux, macOS and Windows + a bounded MPMC channel), thread_local (128 per-thread slots + a slot allocator), atomic, async, sync (portable mutex: futex / `__ulock` / SRWLOCK), freelist (size-class allocator with individual free) |
| Testing & bench tooling | **test** (assertion/test-runner primitives), **regression** (the check-driver primitives carved from `programs/checks/`: process runs with deadlines, buffer scans, SSH / cross-host helpers), **audit_walk** (source-tree audit walker), **poison** (the `--poison` core: fill byte, redzones, `poison_allocator()`; 6.6.18) |
| Math/regex (stdlib primitives) | regex, math (F64 constants + basic ops + gcd/lcm + correctly rounded `f64_parse` / `f64_parse_n` + f64-builtin polyfills), **overflow** (the saturating `+\| -\| *\|` and checked `+? -? *?` operators' call targets) |
| **SIMD** | **simd** — typed vectors (f32v4/f64v2/f64v4/f32v8 + integer vectors i8v16/i16v8/i32v4/i64v2 + unsigned) + packed flat-array verbs (`f32v_`/`f64v_`/`iv_` add/sub/mul/div/sqrt/abs/fmadd/dot/scale/axpy, `iv_dp8`); **Phase 5 complete (v6.4.32)** on all four backends — x86 SSE+AVX2, aarch64 NEON, Win64 PE (value-form params + returns), cx bytecode (per-lane scalar). See `lib/simd.cyr`. |
| **Data (protobuf)** | **protobuf** — protobuf proto3 wire encode/decode (`lib/protobuf.cyr`). |
| **Data formats + big-int (bayan)** | **bayan** — json / toml / cyml / csv / base64 / yaml / pdf / round-trip f64 ↔ decimal / bigint (`u256`) / u128; folded v6.1.25, opt-in `include "lib/bayan.cyr"`; canonical `bayan_*` API + legacy aliases (`json_parse`, `u256_add`, …). The modules that call carved fns — `ws`, `ws_server`, the sigil and yantra folds — include it themselves (6.6.19); `tls_native` gets it through sigil. |
| **Linear algebra + advanced math (ganita)** | **ganita** — matrix (`ganita_mat_*`) + linalg (LU/det/inv/Cholesky/QR/least-squares/eigen/SVD) + advanced math (transcendental + fibonacci/binomial) + an f32 scalar tier; folded v6.1.26, opt-in `include "lib/ganita.cyr"`; `ganita_*` + legacy aliases (`mat_mul`, `f64_pow`, …). The bundle includes stdlib `math` itself (the f64 polyfills). |
| Unicode | unicode/categories, unicode/casefold, unicode/normalize (NFC/NFD/NFKC/NFKD) — Unicode 17.0.0; data sidecars unicode/_categories_data, unicode/_casefold_data, unicode/_normalize_data and the shared decoder unicode/_decode |
| Crypto | sha1, keccak, ct (constant-time primitives), **random** (kernel entropy via getrandom) |
| Sandboxing | **security** (Landlock policy enums; v5.7.35) |
| Network | net, http, ws, ws_server, tls, **tls_hostid** (the host-identity classifier both TLS backends share; internal), **tls_native** (sovereign TLS 1.2 + 1.3 client+server, sigil X.509 — default backend since v6.1.21; split since v6.2.5 into tls_native_lowlevel, tls_native_keysched, tls_native_ctx, tls_native_hs13, tls_native_hs12, tls_native_conn), **sandhi** (HTTP/2 + RPC; folded v5.7.0) |
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
| GPU | **mabda** (folded v6.0.x; opt-in `include "lib/mabda.cyr"`; current pin in [ecosystem.md](ecosystem.md)) |
| Platform sub-modules (included by their parent, never directly) | alloc_windows / alloc_macos / alloc_agnos / alloc_cx (alloc) · args_win / args_macos / args_agnos (args) · async_win / async_macos / async_agnos (async) · fs_win (fs) · process_win / process_agnos (process) · regression_agnos (regression) · sync_windows / sync_macos (sync) · syscalls_x86_64_linux / syscalls_aarch64_linux / syscalls_linux_common / syscalls_macos / syscalls_windows / syscalls_x86_64_agnos (syscalls) · thread_win / thread_macos / thread_agnos (thread) |

## See also

- [`stdlib-reference.md`](stdlib-reference.md) — per-function API reference
- [`ecosystem.md`](ecosystem.md) — live folded-distlib pins + downstream consumers
- [`api-surface.snapshot`](api-surface.snapshot) — generated public-symbol surface (gated in `check.sh`)
