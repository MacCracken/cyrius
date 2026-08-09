# `sys_getuid` / `sys_geteuid` are broken on BOTH Mach-O targets, hidden by a hardcoded `is_root()`

**Filed:** 2026-08-09 (v6.5.16 cycle)
**Status:** 🟡 OPEN
**Severity:** Medium — a privilege check that cannot read the uid. No consumer is currently
wrong *because* `is_root()` doesn't call it, but that is a coincidence, not a design.
**Affects:** `lib/sys.cyr` (`sys_getuid`, `sys_geteuid`, `is_root` ~line 416), both Mach-O
backends. **Pre-existing** — measured identical on the v6.5.15 baseline, so v6.5.16's sysctl
work did not cause it.

## Measured on real hardware

| host | arch | `sys_getuid()` | truth (`id -u`) |
|---|---|---|---|
| **ecb** | macOS arm64 | **-9** (EBADF) | 501 |
| **ach** | macOS x86_64 | **SIGSYS, rc 140** | 501 |

Two different wrong answers on the two Mach-O targets — the arm64 side returns a bogus errno,
the x86 side kills the process outright. `rc 140` is the same unrouted-number signature that
`sys_fchmod` had until v6.5.15.

## ⭐ Why no test caught it — the gate cannot see it

`lib/sys.cyr:416` makes `is_root()` **hardcode `return 0` on macOS**. The only test that touches
this area therefore passes *without ever calling* `sys_getuid`. So:

- the wrapper is broken on both Macs,
- the one consumer that would expose it is short-circuited,
- and the test is green.

That is the same "the gate can't see this" shape as the original macOS rot (a CI job named
"Mach-O ARM64 Native ✓" that only ran hello-world), and the same shape as v6.5.16's discovery
that `sys_access` returning `-22` had been silently skipping `tls_native_scaffold`'s entire
OpenSSL block. A primitive that fails in a way that makes its caller skip is invisible.

## Fix sketch

1. Route the number on **both** Mach-O backends — Darwin `getuid` is BSD 24, `geteuid` BSD 25.
   x86: `_msx(S, <x86-linux num>, 0x2000000 | 24)` in `EMACHO_SYSXLAT`.
   arm64: the `cmp x8,#N / b.ne / movz x8,#24` triple in `ESYSXLAT`'s `_TARGET_MACHO == 2`
   branch, plus the `_macho_arm_routes` row. **Verify each number on the host first** — do not
   take BSD numbers from memory or a header grep.
2. Make `is_root()` on macOS actually call `sys_geteuid() == 0` instead of returning 0.
3. ⚠ **Only then** is a test meaningful. Assert the uid is a plausible value AND that it matches
   the host's `id -u`, on both ecb and ach — a wrapper that returns a constant would satisfy a
   `>= 0` check. Put it in `tests/tcyr/crossos/` so the release gate runs it on real hardware;
   `tests/tcyr/platform/` is NOT in the cross-OS selector.
4. Mutation-prove: reverting either route must turn the new test RED on that host specifically.

## Related, found in the same pass

`ach` carries a **larger pre-existing SIGSYS family** — `chrono`, `clock_monotonic`,
`bench_elapsed`, `syscalls_at_family`, `sakshi_full`, `tls_*` all fail there, consistent with an
unrouted `clock_gettime` (x86-Linux 228). ach's full corpus is **252 pass / 12 fail** at
v6.5.16 versus ecb's **259 / 5**, so the Intel-Mac route table is materially thinner. Tracked
structurally in
[`2026-08-09-macho-backend-route-tables-have-drifted-and-nothing-compares-them.md`](2026-08-09-macho-backend-route-tables-have-drifted-and-nothing-compares-them.md);
this file is the concrete first instance.

⚠ Note `lib/sys.cyr`'s `_uts_field` fails ALL of `sys_uname` with `-ENOMEM` if any sysctl string
node exceeds its 384-byte scratch, rather than truncating. `kern.version` measures 104 B (ecb) /
103 B (ach), so there is ample headroom today — but a future kernel with a longer version string
would take out `uname` entirely rather than degrade. Not urgent; worth a bound-and-truncate.
