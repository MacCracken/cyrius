# Standard Library — Module Index

> Categorized inventory of the Cyrius standard library: **94 `lib/*.cyr`
> modules** (85 first-party + 9 vendored sibling distfiles) with **0 git
> deps**. This is the *what-exists* map; for per-function signatures see
> [`stdlib-reference.md`](stdlib-reference.md).

## Fold-in lineage

Sibling-distfile **fold-in lineage** (sandhi-pattern: byte-identical
vendor at the patched tag, removed from `[deps]`):

- v5.7.0 — `sandhi` (HTTP/2 + JSON-RPC + service discovery + TLS policy, ~10,500 lines)
- v5.8.0 — `vani` (audio distlib; replaced inlined `lib/audio.cyr`)
- **v5.8.65 stdlib foldin** — sakshi 2.2.3 (tracing), patra 1.9.3 (storage), sigil 3.0.1 (security), yukti 2.2.2 (hardware enumeration), sankoch 2.2.4 (compression), and re-folded vani at 0.9.2
- **v5.9.0** — niyama 1.0.1 (regex; 5 engines: bre / re2 / pcre / fuzzy / vim; ~6,664 lines)
- **v6.0.x** — mabda 3.0.1 (GPU integration)

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
  libssl bridge).

## Categories

| Category | Modules |
|----------|---------|
| Core | string, fmt, alloc, io, vec, str, args, fnptr, flags |
| Types | tagged (Option), result (Result + ? operator; v5.8.28-.32), hashmap, hashmap_fast, trait, assert, bounds |
| System | syscalls, callback, process, bench |
| Concurrency | thread (clone+mmap, mutex, MPSC), thread_local, atomic, async, freelist |
| Data | json, toml, cyml, csv, base64, regex, math, matrix, linalg, bigint, u128 |
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
| Hardware | **yukti** (folded v5.8.65) |
| Compression | **sankoch** (folded v5.8.65) |
| GPU | **mabda** (folded v6.0.x at 3.0.1; opt-in `include "lib/mabda.cyr"`) |

## See also

- [`stdlib-reference.md`](stdlib-reference.md) — per-function API reference
- [`ecosystem.md`](ecosystem.md) — live folded-distlib pins + downstream consumers
- [`api-surface.snapshot`](api-surface.snapshot) — generated public-symbol surface (gated in `check.sh`)
