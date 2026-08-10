# `sys_getuid` / `sys_geteuid` are broken on BOTH Mach-O targets, hidden by a hardcoded `is_root()`

**Filed:** 2026-08-09 (v6.5.16 cycle)
**Status:** ✅ **RESOLVED in v6.5.16** — archived 2026-08-09, same cycle it was filed.

## Resolution

Routed the whole credential family on **both** Mach-O backends, using only numbers read off
the SDK `syscall.h` on ecb AND live-probed with a raw syscall on both hosts (501/501/20/20,
matching `id -u` / `id -g`). ⚠ Darwin's numbers are not sequential — `getegid` is 43 and
`getgid` is 47.

- `src/backend/aarch64/emit.cyr` — `ESYSXLAT`'s `_TARGET_MACHO == 2` branch: `174→24`,
  `175→25`, `176→47`, `177→43`, plus their `_macho_arm_routes` registration rows.
  Every encoding came from `as -arch arm64` on ecb and was read back with `otool -t -X`;
  the shipped `getpid 172→20` row was re-assembled as a control and matched the committed
  bytes exactly.
- `src/backend/x86/emit.cyr` — `EMACHO_SYSXLAT`: `_msx(S, 102, 0x2000018)`,
  `(107, 0x2000019)`, `(104, 0x200002F)`, `(108, 0x200002B)`.
- `lib/sys.cyr` — `is_root()`'s macOS arm now computes `sys_geteuid() == 0` instead of
  returning a hardcoded 0. That hardcode was the whole reason the breakage was invisible.
- `tests/tcyr/crossos/uid_identity.tcyr` — **new**, and deliberately not a `uid >= 0`
  check, since a constant-returning wrapper satisfies that. It creates a file and compares
  `sys_geteuid()` against the owner uid the kernel reports through `fstat` — an independent
  path into the kernel — so a stubbed or garbage credential cannot agree with it. The host's
  real uid is never hardcoded, so it is portable across ecb/ach/pi/cass and Linux.

**Verified:** ecb crossos 41/41, ach crossos 41/41, both on real hardware.
**Mutation-proven:** deleting the arm64 `174→24` row turns `uid_identity` RED on ecb
specifically (12 pass / 0 fail → 10 / 2) while ach stays green.

The sibling structural issue — nothing compared the two route tables — is also resolved in
this release by `tests/gates/platform/macho_route_parity.sh`, which is what found the
remaining drift (`sys_fstat` dead on ecb, the entire at-family dead on ach) beyond the
credential family this file reported.

The `_uts_field` 384-byte scratch note at the bottom of this file was NOT addressed and is
not a deferral of this issue: it is a separate hardening idea with ample headroom today
(104 B measured against a 384 B buffer) and no failure to reproduce.
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
