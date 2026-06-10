# Invert the `lib/tls.cyr` backend default: native is the no-flag default, `-D CYRIUS_TLS_LIBSSL` is the opt-out

> **RESOLVED v6.1.21** — `lib/tls.cyr` polarity inverted (~16 `#ifdef
> CYRIUS_TLS_NATIVE` → `#ifndef CYRIUS_TLS_LIBSSL`; `_tls_backend` defaults to
> native). Verified 3-way exactly per the acceptance table: no-flag → native
> (`get_backend=1`, `set_native=0`), `-D CYRIUS_TLS_LIBSSL` → libssl
> (`get_backend=0`, `set_native=-1`), legacy `-D CYRIUS_TLS_NATIVE` → native (no-op
> alias). Live TLS connects on both build modes; check.sh 87/87, 170 tcyr, cross-OS
> self-host byte-identical. sandhi re-folded 1.4.8 alongside. See CHANGELOG [6.1.21].

- **Filed**: 2026-06-09
- **Reporter**: sandhi (downstream consumer; service-boundary layer, folds into `lib/sandhi.cyr`)
- **Affects**: `lib/tls.cyr` backend selection (`#ifdef CYRIUS_TLS_NATIVE`), all consumers that build with the native stack, and the `lib/sandhi.cyr` fold.
- **Severity**: Medium — blocks sandhi from shipping native-by-default cleanly. Today every native build (sandhi CI, release artifacts, downstream consumers) must thread `-D CYRIUS_TLS_NATIVE`, and a plain no-flag build silently resolves to the deprecated libssl bridge. Not a crash; a default-polarity + ergonomics gap.
- **Status (2026-06-09): OPEN.** `lib/tls.cyr` (6.1.20 and HEAD `ad26ab4f`) is still `#ifdef CYRIUS_TLS_NATIVE` (native **opt-IN**).
- **Resolution path**: cyrius-side change in `lib/tls.cyr` (this issue). Once it lands and sandhi re-pins, sandhi drops the interim `-D CYRIUS_TLS_NATIVE` from its CI/release/docs and the latest sandhi `dist/sandhi.cyr` folds into `lib/sandhi.cyr` under the new convention.

## Problem

sandhi switched its **default** TLS backend to native at 1.4.5 and, past 1.4.7,
inverted its documented build convention to match where the ecosystem is going:

- **target convention**: native is the **no-flag default**; `-D CYRIUS_TLS_LIBSSL`
  is the explicit opt-out for the deprecated libssl fdlopen bridge.

But cyrius `lib/tls.cyr` still encodes the **opposite** polarity:

```cyr
#ifdef CYRIUS_TLS_NATIVE
include "lib/tls_native.cyr"
#endif

var TLS_BACKEND_LIBSSL = 0;
var TLS_BACKEND_NATIVE = 1;
# Default backend: native when built with CYRIUS_TLS_NATIVE, else libssl.
#ifdef CYRIUS_TLS_NATIVE
var _tls_backend = 1;
#endif
#ifndef CYRIUS_TLS_NATIVE
var _tls_backend = 0;
#endif

fn tls_set_backend(b): i64 {
    if (b == TLS_BACKEND_LIBSSL) { _tls_backend = 0; return 0; }
    #ifdef CYRIUS_TLS_NATIVE
    if (b == TLS_BACKEND_NATIVE) { _tls_backend = 1; return 0; }
    #endif
    return 0 - 1;
}
```

So on 6.1.20, observed directly against the sandhi `src/` tree:

| build flag | `tls_native_available()` | `tls_get_backend()` |
|------------|--------------------------|---------------------|
| *(no flag)* | 0 | 0 (libssl) |
| `-D CYRIUS_TLS_LIBSSL` | 0 | 0 (libssl — **flag is a no-op**, undefined symbol) |
| `-D CYRIUS_TLS_NATIVE` | 1 | 1 (native) |

Consequences for sandhi:

- A plain `cyrius build` of any sandhi program links the **libssl** stack — the
  thing sandhi 1.4.5 deprecated. Native requires the explicit flag everywhere
  (CI, release, Quick Start, every consumer).
- sandhi's CI native gates (`_policy_runtime_probe`, `_https_native_loop_gate`,
  `_https_policy_threading_gate`) **skip or silently run on libssl** under a
  no-flag build, defeating the gate. sandhi is carrying an **interim** workaround
  that keeps `-D CYRIUS_TLS_NATIVE` on those steps and references this issue.
- `lib/sandhi.cyr` can't be folded into a "native-by-default" world until the
  vendoring toolchain makes native the default; otherwise consumers of the
  folded lib silently get libssl.

## Proposed fix (invert the polarity in `lib/tls.cyr`)

Make native the default; let `-D CYRIUS_TLS_LIBSSL` opt **out** to a
libssl-only, native-not-compiled-in build:

```cyr
# Native stack is compiled in by default. -D CYRIUS_TLS_LIBSSL opts out
# to a libssl-only build (lighter — native stack not linked).
#ifndef CYRIUS_TLS_LIBSSL
include "lib/tls_native.cyr"
#endif

var TLS_BACKEND_LIBSSL = 0;
var TLS_BACKEND_NATIVE = 1;
# Default backend: native unless built libssl-only.
#ifndef CYRIUS_TLS_LIBSSL
var _tls_backend = 1;
#endif
#ifdef CYRIUS_TLS_LIBSSL
var _tls_backend = 0;
#endif

fn tls_set_backend(b): i64 {
    #ifndef CYRIUS_TLS_LIBSSL
    if (b == TLS_BACKEND_NATIVE) { _tls_backend = 1; return 0; }
    #endif
    if (b == TLS_BACKEND_LIBSSL) { _tls_backend = 0; return 0; }
    return 0 - 1;
}
```

Every other `#ifdef CYRIUS_TLS_NATIVE` site in `lib/tls.cyr` (the typed
`tls_native_*` dispatch in `tls_get_peer_spki_der`, `tls_set_alpn`,
`tls_connect_*`, etc. — ~16 sites) flips to `#ifndef CYRIUS_TLS_LIBSSL` so the
native code path is compiled by default and dropped only on the libssl-only
opt-out.

### Backward-compatibility (important — do NOT hard-break the old flag)

`-D CYRIUS_TLS_NATIVE` is in active use across sandhi 1.4.5–1.4.7 CI/release and
likely other consumers. Keep it as a **recognized no-op alias** for a transition
window: with the inverted default, native is already compiled in, so a build
that still passes `-D CYRIUS_TLS_NATIVE` should behave identically (native
default) rather than error. Concretely, the inverted guards above are
`CYRIUS_TLS_LIBSSL`-only, so an extra `-D CYRIUS_TLS_NATIVE` is harmless. Note
its deprecation in the `lib/tls.cyr` header and the CHANGELOG; drop it after the
ecosystem has re-pinned.

## Trade-off (state it explicitly)

Inverting the default makes the **native stack compiled in by default**, so the
no-flag binary grows by the native-stack size (observed in sandhi's smoke link
proof: ~1.37 MB native vs ~562 KB libssl-only — the native path pulls
`lib/tls_native.cyr` + sigil's X.509/crypto chain). Libssl-only consumers who
want the smaller binary opt out with `-D CYRIUS_TLS_LIBSSL`. This is the right
default now that native is the recommended, crash-safe (6.1.19) backend and
libssl is deprecated — the cost lands on the deprecated path, not the default.

## Acceptance

- No-flag `cyrius build` of a TLS-using program: `tls_get_backend()` → 1
  (native), native code path linked, `tls_set_backend(TLS_BACKEND_NATIVE)` → 0.
- `-D CYRIUS_TLS_LIBSSL` build: native not compiled in,
  `tls_set_backend(TLS_BACKEND_NATIVE)` → -1, `tls_get_backend()` → 0 (libssl),
  smaller binary.
- `-D CYRIUS_TLS_NATIVE` build (legacy): still builds and behaves as native
  (no-op alias), no error.
- `check.sh` / `.tcyr` suites green on the no-flag (now native) default; the
  native + libssl live-TLS smoke set (example.com / 1.1.1.1 / …) passes on both
  build modes.
- self-host byte-identical where the change is `#ifdef`-gated (Linux/macOS/
  Windows cycc unaffected by the lib-only flip).

## Fold impact (what unblocks downstream once this lands)

1. cyrius re-folds the latest sandhi `dist/sandhi.cyr` → `lib/sandhi.cyr`
   (sandhi ≥ 1.4.7) under native-by-default.
2. sandhi re-pins to the cyrius release carrying this change and **drops the
   interim `-D CYRIUS_TLS_NATIVE`** from CI (`.github/workflows/ci.yml`),
   release (`release.yml`), Quick Start, and the gates — flipping to the no-flag
   native default + `-D CYRIUS_TLS_LIBSSL` opt-out its docs already describe
   (CLAUDE.md, `docs/architecture/004-native-tls-default.md`).
3. The interim banner in sandhi's `ci.yml` (which references this file) is
   removed.

## Related

- sandhi `docs/architecture/004-native-tls-default.md` — the consumer-side
  target convention + the "depends on the upstream cyrius inverted-default
  build" caveat.
- sandhi `docs/issues/2026-06-09-tls-policy-enforcement-live-segfault.md` — the
  native TLS-policy enforcement gate (the other half of full libssl retirement).
- cyrius 6.1.19 — the alloc-brk + native cert-chain fixes that made native the
  crash-safe, recommended default in the first place.
