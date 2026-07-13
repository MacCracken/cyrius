# AGNOS Ecosystem Migration Strategy

> ⚠️ **HISTORICAL SNAPSHOT — frozen at compiler v5.7.39 (≈2026-04-30).
> Superseded; not maintained.** The metrics, wave plan, and "compiler
> is on v5.7.39" framing below are a point-in-time snapshot and have
> NOT been updated through the v5.8–v6.x cycles (the compiler is now
> v6.4.62; many waves shipped piecemeal — niyama fold v5.9.0, sandhi
> 1.3.3 v5.10.34, mabda 3.0.1 fold v6.0.45, native TLS v6.0.x, the
> AGNOS userspace target v6.0.x). For the **current** ecosystem /
> consumer / pin state see [`docs/ecosystem.md`](../ecosystem.md) and
> [`state.md`](state.md); for shipped-arc history see
> [`completed-phases.md`](completed-phases.md) + [`CHANGELOG.md`](../../CHANGELOG.md).
> Kept as a record of the original migration framing, not as live
> guidance.

> **107 Rust repos. ~980K lines. One language to replace them all.**
>
> This document tracks the Rust → Cyrius migration across the entire AGNOS ecosystem.
> For language development, see [roadmap.md](roadmap.md).
> For completed work, see [completed-phases.md](completed-phases.md).

---

## Overview

| Metric | Count |
|--------|-------|
| Total Rust repos (original inventory) | 107 |
| Total lines of Rust (original) | ~980,000 |
| Already ported (confirmed `.cyr` source) | 19 |
| Remaining | ~88 |
| **Keystone: hisab ported** | unblocks Wave 4 (37 dependents) |
| bhava pending | 8 dependents |
| Repos using tokio (async) | 48 |
| Repos using serde | 90+ |

Compiler is on **v5.7.39** (deep into the v5.7.x cycle). Apple Silicon
Mach-O self-hosting + shared-library emission (`.so` / dynlib) shipped
in v5.3.x; foreign-dlopen (real glibc init via `lib/fdlopen.cyr` for
libssl etc.) shipped at v5.5.34; ALPN/mTLS hook surface in
`lib/tls.cyr` shipped at v5.6.40; sandhi (HTTP/2 + RPC + service
discovery) folded into stdlib at v5.7.0; cross-file LSP go-to-def
shipped at v5.7.39 — bridge strategies below are all available today
rather than "v1.1+ future work".

### Size Distribution

| Bracket | Repos | Strategy |
|---------|-------|----------|
| <1K lines | 18 | Direct port — minimal features needed |
| 1K–5K lines | 21 | Port with v1.0 features |
| 5K–15K lines | 51 | Need closures, iterators, generics |
| >15K lines | 17 | Need full Tier 2 + concurrency |

### Dependency Keystone

**hisab** (32K lines, math library) — the keystone. **Ported.** 37 repos
depend on it; their ports are now unblocked (Wave 4).

**bhava** (30K lines, emotion engine) — 8 direct dependents. Still Rust.
Requires: generics, operator overloading, const generics, derive macros.

---

## Migration Waves

### Wave 0 — Done

19 repos from the original Rust inventory now ship as `.cyr` source.
Versions as of cyrius v5.3.14 (2026-04-18):

**Original Wave 0 (v0.9.0):**

| Repo | Rust LOC | Cyrius version | Notes |
|------|----------|----------------|-------|
| agnostik | ~2K | 0.97.1 | 58 tests |
| agnosys | ~2K | 1.0.0 | 20 syscall modules |
| kybernet | 1,649 | 1.0.1 | 140 tests |
| nous | ~2K | 1.1.1 | dep resolver |
| ark | ~4K | — | package manager |

**Keystone + small ports (Wave 1/2/3):**

| Repo | Cyrius version | Notes |
|------|----------------|-------|
| **hisab** | ported | **keystone — unblocks Wave 4 (37 dependents)** |
| vidya | 2.2.0 | content loader + registry |
| vidhana | — | small port |

**Security + infrastructure (Wave 5 — 7 of 8 done):**

| Repo | Cyrius version | Notes |
|------|----------------|-------|
| sigil | 2.8.3 | 206 tests |
| majra | 2.2.0 | |
| nein | — | |
| bote | 2.5.1 | MCP core service (JSON-RPC 2.0) |
| t-ron | — | |
| phylax | 1.0.0 | |
| kavach | 3.0.0 | *last port blocking server-OS stack closeout* |

**AI + Platform (Wave 6 — partial):**

| Repo | Cyrius version | Notes |
|------|----------------|-------|
| ai-hwaccel | 2.0.0 | 491 tests |
| hoosh | 2.0.0 | |
| agnoshi | 1.0.0 | |
| avatara | 2.3.0 | |

Other Cyrius-native projects shipping alongside (not Rust ports, but part of
the ecosystem): sakshi 2.0.0, patra 1.1.1, sankoch 1.2.0, yukti 1.2.0,
mabda 2.1.2, hadara 1.0.0, libro 1.0.3, shravan 2.3.2, cyrius-doom 0.24.5,
bsp 1.0.1, argonaut 1.2.0, daimon 1.1.1.

### Wave 1 — Small Repos (<1K lines)

18 repos, direct ports. No blocking language features.

| Repo | Lines | Notes |
|------|-------|-------|
| tanur | 924 | |
| abacus | 894 | |
| sutra | 829 | |
| nazar | 788 | |
| rahd | 521 | |
| taal | 453 | |
| kshetra | 426 | |
| natya | 399 | |
| shruti | 311 | |
| vinimaya | 269 | |
| mudra | 232 | |
| vidhana | 228 | |
| tazama | 0 | Skeleton |
| sutra-community | 0 | Skeleton |
| rasa | 0 | Skeleton |
| mneme | 0 | Skeleton |
| delta | 0 | Skeleton |
| aequi | 0 | Skeleton |

### Wave 2 — Medium Repos (1K–5K lines)

21 repos. Most need serde (JSON serialization). Subprocess bridge covers external deps.

| Repo | Lines | Key Deps | Status |
|------|-------|----------|--------|
| tara | 4,814 | hisab, serde | Rust |
| badal | 4,805 | hisab, serde | Rust |
| seema | 4,607 | tokio, serde | Rust |
| hisab-mimamsa | 4,519 | hisab, serde | Rust |
| brahmanda | 4,257 | hisab, serde | Rust |
| jnana | 4,130 | hisab, serde | Rust |
| selah | 4,096 | hisab, tokio, serde | Rust |
| shakti | 3,934 | serde | Rust |
| muharrir | 3,797 | serde | Rust |
| agnova | 3,656 | serde | Rust |
| prani | 3,527 | hisab, serde | Rust |
| ghurni | 3,054 | serde | Rust |
| vidya | 2,382 | serde | **Ported (2.2.0)** |
| jalwa | 2,076 | tokio, serde | Rust |
| takumi | 2,034 | serde | Rust |
| aegis | 1,893 | serde | Rust |
| murti | 1,525 | tokio, serde | Rust |
| samay | 1,479 | serde | Rust |
| taswir | 1,329 | tokio, serde | Rust |
| ark | 4,363 | serde | **Ported** |
| nous | 2,143 | serde | **Ported (1.1.1)** |

### Wave 3 — Keystone Libraries

Port the two libraries that unlock the rest:

| Repo | Lines | Dependents | Requires | Status |
|------|-------|------------|----------|--------|
| **hisab** | 31,795 | 37 repos | Generics, const generics, operator overloading, derive | **Ported — unblocks Wave 4** |
| **bhava** | 29,750 | 8 repos | Traits, iterators, closures, derive | Rust |

### Wave 4 — Hisab Dependents (5K–15K)

37 repos that depend on hisab. Port after hisab:

| Repo | Lines | Additional Deps |
|------|-------|----------------|
| vanaspati | 11,173 | hisab |
| goonj | 11,170 | hisab |
| naad | 10,503 | hisab |
| sankhya | 9,857 | hisab |
| ushma | 9,083 | hisab |
| svara | 8,785 | hisab |
| falak | 8,870 | hisab |
| dravya | 7,634 | hisab |
| pramana | 7,916 | hisab |
| nidhi | 7,180 | hisab |
| jivanu | 7,161 | hisab |
| kana | 7,015 | hisab |
| joshua | 6,657 | hisab, bhava |
| salai | 6,669 | hisab, bhava |
| bodh | 6,309 | hisab |
| pavan | 6,355 | hisab |
| sharira | 6,044 | hisab |
| sangha | 5,836 | hisab |
| jantu | 5,889 | hisab, bhava |

(Plus 18 more >10K lines: kiran, impetus, prakash, soorat, bijli, jyotish, khanij, pravash, kimiya, raasta, etc.)

### Wave 5 — Security + Infrastructure

Server-OS stack: 10 layers, 9 complete. **kavach is the last port**
blocking closeout of the hardened server.

| Repo | Lines | Requires | Status |
|------|-------|----------|--------|
| kavach | 25,935 | Ownership, sandbox borrow checker | **Ported (3.0.0) — closeout blocker** |
| phylax | 14,133 | Ownership | **Ported (1.0.0)** |
| sigil | ~5K | Ownership | **Ported (2.8.3)** |
| majra | 12,969 | | **Ported (2.2.0)** |
| nein | ~5K | | **Ported** |
| bote | ~5K | | **Ported (2.5.1)** — MCP core |
| t-ron | ~5K | | **Ported** |
| seema | 4,607 | tokio | Rust (only Wave 5 port remaining) |

### Wave 6 — AI + Platform

| Repo | Lines | Requires | Status |
|------|-------|----------|--------|
| ifran | 53,612 | Concurrency, generics | Rust |
| tarang | 33,438 | Concurrency | Rust |
| agnosai | 27,686 | Concurrency, bhava | Rust |
| agnoshi | 27,251 | Concurrency | **Ported (1.0.0)** |
| aethersafha | 27,207 | Concurrency | Rust |
| hoosh | 21,833 | Concurrency, bhava | **Ported (2.0.0)** |
| dhvani | 23,695 | Concurrency | Rust |
| raasta | 20,043 | hisab, tokio | Rust |
| kiran | 19,976 | hisab, bhava | Rust |
| ai-hwaccel | 17,335 | FFI, subprocess | **Ported (2.0.0) — 491 tests** |
| stiva | 18,622 | | Rust |
| impetus | 18,414 | hisab | Rust |
| avatara | 18,804 | | **Ported (2.3.0)** |

---

## Bridge Strategies

For repos with external dependencies that can't be ported:

### Subprocess (available now)

```cyrius
var args = vec_new();
vec_push(args, "/usr/bin/nvidia-smi");
vec_push(args, "--query-gpu=name");
var buf = alloc(4096);
var len = exec_capture(args, buf, 4096);
```

Covers: GPU detection, system tools, Python scripts, Node.js tools.

### C FFI Headers (available now)

```bash
cyrius header lib/mylib.cyr > mylib.h
```

Generates C prototypes. Other languages can see what functions exist.

### Shared Library (.so) — available now (v5.3.x)

Emit position-independent ELF shared objects via `cyrius distlib [profile]`.
`lib/dynlib.cyr` wraps libc `dlopen`/`dlsym`. Enables loading Cyrius code from
C/Python/Rust and linking against system libraries.

### Protocol Bridge — available now

Cyrius services communicate via TCP/UDP (`lib/net.cyr`, `lib/http_server.cyr`).
TypeScript/Python frontends talk to Cyrius backends over HTTP, JSON-RPC 2.0
(see bote), or Unix domain sockets.

---

## Porting Patterns

### Rust → Cyrius Translation Guide

| Rust | Cyrius |
|------|--------|
| `fn foo(x: i64) -> i64` | `fn foo(x) { return ...; }` |
| `struct Point { x: f64, y: f64 }` | `struct Point { x; y; }` |
| `impl Point { fn sum(&self) }` | `impl Math for Point { fn sum(self) { } }` |
| `point.sum()` | `point.sum()` (same!) |
| `match result { Ok(v) => ..., Err(e) => ... }` | `match tag(result) { 0 => { var v = payload(result); } }` |
| `for i in 0..10` | `for i in 0..10` (same!) |
| `let f = \|x\| x * 2` | `var f = \|x\| x * 2;` |
| `vec![1, 2, 3]` | `var v = vec_new(); vec_push(v, 1); ...` |
| `String::from("hello")` | `var s: Str = str_from("hello");` |
| `s.len()` | `s.len()` (same!) |
| `HashMap::new()` | `map_new()` |
| `#[cfg(feature = "x")]` | `#ifdef X` |
| `mod math;` | `mod math;` (same!) |
| `use math::add;` | `use math.add;` |
| `pub fn` | `pub fn` (same!) |

### Per-Repo Workflow

1. Move Rust code to `rust-old/`
2. Create `src/`, `lib/`, `programs/`, `tests/` directories
3. Author `cyrius.cyml` manifest; pin toolchain to latest released tag
   (see `feedback_pin_released` — never a dev version)
4. Resolve deps: `cyrius deps` (auto-runs on build/run/test, symlinks into
   `lib/{depname}_{basename}`)
5. Port module by module, test incrementally with `cyrius test`
6. Use subprocess / dynlib / HTTP bridge for external deps
7. Run `sh scripts/check.sh` (or project equivalent) before each commit

---

## Tracking

| Wave | Repos | Lines | Status |
|------|-------|-------|--------|
| 0 (originals) | 5 | ~12K | **Done** |
| 1 (small) | 18 | ~6K | 1 done (vidhana); 11 Rust; 6 skeletons |
| 2 (medium) | 21 | ~65K | 3 done (ark, nous, vidya); 18 Rust |
| 3 (keystones) | 2 | ~62K | **hisab done**; bhava pending |
| 4 (hisab deps) | 37 | ~300K | **Unblocked** by hisab — all still Rust |
| 5 (security) | 8 | ~80K | **7/8 done**; seema is last Rust port; kavach closeout blocker for server-OS stack |
| 6 (AI/platform) | 13 | ~350K | **4/13 done** (agnoshi, hoosh, ai-hwaccel, avatara) |
| **Total ported** | **19** | — | |
| **Total inventory** | **107** | **~980K** | |

---

*This document is the source of truth for migration planning.*
*Language features are tracked in [roadmap.md](roadmap.md).*
*Completed ports are tracked in [completed-phases.md](completed-phases.md).*
