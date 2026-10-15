# Every build that includes `lib/sandhi.cyr` (so every `lib/yantra.cyr` build) prints the large-static-data advisory — RESOLVED

> ✅ **RESOLVED in v6.7.11** (the cause was sakshi, not sandhi: four private sakshi buffers were declared as slots — a bare top-level `var x[N]` is N slots, 8N bytes — so `_sk_ring_buf[4096]` / `_sk_aring_buf[4096]` reserved 32,768 B each. sakshi 2.5.10 (`569e9f8`, the user's tag) declares them in bytes: sakshi's static data 69,232 → 9,088 B, and `include "lib/sandhi.cyr"` / `include "lib/yantra.cyr"` print no large-static advisory. No sandhi release, no yantra refold. Row: `tls_sigil_include_warning_free.sh` axis 1 widened to sakshi / sandhi / yantra (mutation b: 2.5.9 back → sandhi and yantra RED). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-12 in the 6.7.10 refold worktree (`build/cycc` 2,057,744 B; sigil 3.13.12,
yantra 1.0.11 refolded): `include "lib/sandhi.cyr"` alone compiles (rc 0) and prints
`warning: large static data (185200 bytes) — consider alloc() for buffers >4KB`; `include "lib/yantra.cyr"` alone
prints the same advisory at 185,656 B. `include "lib/tls.cyr"` alone is 111,232 B and warns nothing since sigil
3.13.12, so sandhi itself adds about 74 KB of static data on top of the TLS stack it builds on.
**Placement:** 6.7.11 — repair 1, the stdlib + folds lane (roadmap.md § *6.7.11*) — placed 2026-10-12 — never 7.x.
⛔ The fix is a sandhi release (the user tags it), then a byte-identical re-vendor (and yantra's refold).
**Discovered:** 2026-10-12, the 6.7.10 sigil refold: widening the sigil / tls "no warning on a bare include" check to
all twelve folds.
**Severity:** Low — no wrong value; one warning on every HTTP / RPC / UI-automation consumer's build (the noise class
sigil 3.13.12 just closed). A folded-stdlib defect, so high priority.
**Affects:** sandhi as vendored (1.10.9) and yantra (1.0.11) with cycc 6.7.10.

## Summary

The whole-program advisory (`_warn_large_static`, over 131,072 B) fires for any program that includes sandhi. sigil's
256 KB buffer used to carry TLS over the line; with it gone, sandhi's own static data does. No large top-level or
fn-local array declaration in `lib/sandhi.cyr` accounts for it by grep, so the investigation starts from a per-symbol
size listing of a sandhi-only build.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'include "lib/sandhi.cyr"\nsyscall(60, 0);\n' | build/cycc > /tmp/sd 2> /tmp/sd.err; echo "rc=$?"
grep '^warning' /tmp/sd.err      # warning: large static data (185200 bytes) — consider alloc() for buffers >4KB
```

## Root cause

To be located in sandhi's source: which globals / literal pools make up its ~74 KB of static data beyond `lib/tls.cyr`.

## Proposed fix

In sandhi's source repo: move the large static buffers to per-call or allocated storage where they are scratch (as
sigil 3.13.12 did), or confirm they are deliberately static and say so; then a sandhi release, a byte-identical
re-vendor, yantra's refold, and widening `tls_sigil_include_warning_free.sh` to sandhi and yantra.

## Consumer-side workaround

None needed — the advisory is noise; nothing behaves differently.
