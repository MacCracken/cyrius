# `lib/hashseed.cyr` blocks on `getrandom(…, 0)` until the kernel CRNG is seeded: PID 1 waits ~0.9 s on a board with no entropy source — OPEN

**Status:** 🟡 **OPEN**: verified 2026-09-23 against the installed 6.6.6 snapshot: `_hm_seed_get`
(`~/.cyrius/lib/hashseed.cyr:61`) still calls `syscall(SYS_GETRANDOM, &_hm_seed_buf, 8, 0)` (`:68`),
and flags 0 blocks until the CRNG is initialised. Re-measured the same day in kybernet 1.7.8's aarch64
boot gate (numbers below).
**Placement:** unpinned — 6.6.x-line backlog (never 7.x).
**Discovered:** 2026-09-22 during kybernet 1.7.2, when its aarch64 boot gate started booting with the
device-tree RNG seed turned off.
**Severity:** Medium: a silent stall of more than 2× in a boot path, with nothing the consumer can do
about it.
**Affects:** every cycc since 6.5.39, when the per-process seed landed
(`archived/2026-08-30-hashmap-unseeded-fnv1a-collision-dos.md`). The call is the same on every Linux
target; measured at 6.6.6 on aarch64.

## Summary

The per-process hash seed is drawn on a program's first map operation with `getrandom(buf, 8, 0)`.
Flags 0 waits for the kernel CRNG. In a program that runs early in boot, before the CRNG is seeded,
the first `map_new` / `map_set` therefore stops until the kernel seeds itself.

kybernet is PID 1. Its first map operation is inside argonaut's `argonaut_init_new`, at boot phase 6,
before PID 1's event loop exists, so nothing is reaped and no timer is serviced while it waits. On a
board with no hardware RNG and no firmware seed, that is where boot stops.

The seed only has to be unpredictable enough to defeat precomputed hash-flooding sets, and the file
already accepts a weaker source for that: when `getrandom` fails it falls back to a time mix (`:76`,
"weaker, but still not a published constant, which is the property that matters here"). Blocking for
the CSPRNG is stricter than the file's own requirement.

## Reproduction

kybernet's aarch64 boot gate (`qemu/boot-test-aarch64.sh` in kybernet) boots `kybernet-aarch64` as
PID 1 under `qemu-system-aarch64 -M virt,dtb-randomness=off` (TCG), which is the shape of a board
without a hardware RNG. Kernel timestamps from kybernet 1.7.8's run on 2026-09-23, built with cycc
6.6.6:

```
[    1.201850] phase 4: signals ready
[    2.093376] random: crng init done
[    2.105358] phase 6: argonaut ready
```

Phase 4 to phase 6 takes 903 ms. 891 ms of it passes before the kernel seeds the CRNG, and phase 6
completes 12 ms after the seed arrives. At kybernet 1.7.2 the same gate was run both ways: with the
device-tree seed turned back on (`crng init done` at 0.000000), kybernet's whole PID-1 span fell from
~1.4 s to 548 ms.

## Root cause

`lib/hashseed.cyr`, `_hm_seed_get` (6.6.6 snapshot):

```cyrius
#ifdef CYRIUS_TARGET_WIN
var nr = sys_getrandom(&_hm_seed_buf, 8, 0);
#else
var nr = syscall(SYS_GETRANDOM, &_hm_seed_buf, 8, 0);
#endif
```

Flags 0 is "block until the CRNG is initialised" on Linux.

## Proposed fix

On the Linux targets, do not wait for the CSPRNG for a hash seed:

- **(a)** `getrandom(buf, 8, GRND_INSECURE)` (`0x0004`; the kernel's uapi header describes it as
  "Return non-cryptographic random bytes"). It never blocks. It is available from Linux 5.6, and on
  older kernels it fails with `EINVAL`, where the existing time mix takes over, as it already does for
  any failed draw.
- **(b)** `getrandom(buf, 8, GRND_NONBLOCK)` and the time mix on `EAGAIN`. This works back to 3.17,
  but a starved boot then always gets the time mix, the weaker seed.

Either keeps the CAS publication as it is. The agnos, macOS and Windows peers keep their own
semantics. Which to pick is the Cyrius agent's call; (a) matches the file's stated requirement most
closely.

## Consumer-side workaround

None that the consumer controls. The first map operation happens inside a dependency (argonaut), and
the seed is the stdlib's. kybernet's aarch64 gate asserts that the boot really was starved (the CRNG
seeds after kybernet's phase 1) and that its span budget still holds, so the fix will show up there as
a shorter phase 4 → 6.
