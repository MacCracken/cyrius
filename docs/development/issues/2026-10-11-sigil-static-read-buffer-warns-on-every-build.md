# Every build that includes `lib/sigil.cyr` (so every `lib/tls.cyr` program) prints two warnings for sigil's deliberately static 256 KB `hash_file_into` buffer — OPEN

**Status:** 🟡 **OPEN** — reported in passing by the 6.7.9 quick lane (bite 9, in every yantra build). Verified
2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B): `include "lib/sigil.cyr"` alone, and
`include "lib/tls.cyr"` alone, each compile with rc 0 and print the two warnings below. Not covered by any open issue
(the 2026-06-30 stack-arrays filing recorded this buffer as the sole `note:` case; 6.6.5 made that note a warning).
**Placement:** 6.7.12 — repair 2, the fold refolds beside bayan's (roadmap.md § *The releases after 6.7.8*) — placed
2026-10-11 — never 7.x. ⛔ The fix is a sigil release (the user tags it), then a byte-identical re-vendor: cyrius
6.7.12 cannot tag with the refold pending.
**Discovered:** 2026-10-11 during 6.7.9's yantra test-include fix (the warning-noise class that issue closed).
**Severity:** Low — no wrong value; two warnings on every TLS / crypto consumer's build, the noise that teaches a
reader to skip warnings. A folded-stdlib defect, so high priority.
**Affects:** `lib/sigil.cyr` (sigil 3.13.11 today; the buffer since sigil 3.6's banking) with cycc 6.6.5 – 6.7.9 (the
warning; a `note:` before 6.6.5).

## Summary

`hash_file_into` (`lib/sigil.cyr:28092`) declares its file-read scratch as `var buf[262144];` — 4096 B ×
`SIGIL_CRYPTO_BANKS` — inside the fn and indexes it per thread (`&buf + cbank() * 4096`). That is over the per-fn
frame budget, so the compiler gives it STATIC storage, which is exactly what sigil intends (the banking is the thread
safety), and says so on every build that parses the fn, called or not:

```
warning:lib/sigil.cyr:28103:12: array local over the per-fn frame budget gets STATIC storage: one buffer shared by all calls and all threads; use alloc() for per-call storage
warning: large static data (367664 bytes) — consider alloc() for buffers >4KB
```

The second line is the whole-program advisory (`_warn_large_static`, over 131,072 B); the 256 KB buffer is what
carries sigil past it (the rest of its static data is about 100 KB).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'include "lib/sigil.cyr"\nsyscall(60, 0);\n' | build/cycc > /tmp/sg 2> /tmp/sg.err; echo "rc=$?"
grep -c '^warning' /tmp/sg.err      # 2 (the STATIC-storage warning and the large-static advisory)
printf 'include "lib/tls.cyr"\nsyscall(60, 0);\n' | build/cycc > /tmp/sg2 2> /tmp/sg2.err; grep -c '^warning' /tmp/sg2.err   # 2
```

Expected: a program that includes sigil and never asks for anything unusual compiles with no warning.

## Root cause

sigil's source (`hash_file_into`): a banked static buffer spelled as a fn-local array, which the compiler can only
read as an over-budget local (`parse_decl.cyr:423`, the 6.6.5 warning).

## Proposed fix

In sigil's source repo (never the vendored copy). The fn's own comment already says the 4 KB read buffer "remains a
stack-local — fine for concurrent workers, each thread gets its own stack": make it one — `var buf[4096];` per call
(under the frame budget, so per-thread by construction) with the banking dropped for it; the 32-byte digest bank
likewise, or kept as it is (2 KB, under the budget). Both warnings go (sigil's static data falls under the
advisory's 131,072 B), and 256 KB leaves every TLS consumer's `.bss`. It also ends a coupling seen in passing: the
buffer's size is the literal 262144 = 4096 × 64, while `SIGIL_CRYPTO_BANKS` (`lib/sigil.cyr:5182`) is a writable
public `var` of 64 — the TLS bound-var class
([2026-10-11-tls-public-bound-vars-drive-const-storage.md](2026-10-11-tls-public-bound-vars-drive-const-storage.md)). Then a sigil release (the user tags it), a
byte-identical re-vendor, its `docs/ecosystem.md` row, and a cyrius-side row: `include "lib/tls.cyr"` compiles with no
warning (a gate under `tests/gates/` that greps the stderr of the bare include).

## Consumer-side workaround

None needed — the warnings are noise; the buffer behaves as sigil intends.
