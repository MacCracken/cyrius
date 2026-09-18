# memfd_create / ftruncate / sendmsg have no stdlib name, so their x86_64 numbers pass through unrenumbered on ELF aarch64 — silently wrong calls

**Status:** ✅ **FIXED in 6.6.5 (bite 5)** — names in all five peers, seven shared wrappers, fourteen new
ESYSXLAT rows on the ELF arm and seventeen on the two Mach-O backends (twelve, plus the five raw-x86
parity rows arm64-macOS was missing, added in review), plus
`tests/tcyr/crossos/syscall_shm_fd_passing.tcyr` (**59 assertions / 52 reported**, run on real hardware by the
release gate — review round 2 added `sys_lseek`, an exact `sys_sched_yield` and moved the raw 83/84/87/89/33
group out of its Linux-only guard so the five arm64-macOS parity rows actually run on ecb/ach) and two new
static gates, plus a third axis and an anti-vacuity floor on `aarch64_syscall_shadow.sh`. See CHANGELOG [6.6.5].
**Placement:** shipped.
**Discovered:** 2026-09-17 during thoth's repair batch 8 (its Wayland window on aarch64 Linux), measured under
`qemu-aarch64 -strace`.
**Severity:** Medium — every call issues a *different, valid* syscall or ENOSYS with a successful, warning-free build;
thoth's window never had a buffer on aarch64 Linux for ~20 releases, and nothing said so.
**Affects:** cycc 6.6.4 (observed; not bisected).

## Summary

A Wayland client needs three calls the stdlib does not name: `memfd_create` (the shared-memory pixel buffer),
`ftruncate` (sizing it) and `sendmsg` (passing its fd with `SCM_RIGHTS`). Written with their x86_64 numbers — the
convention the rest of a portable source follows, relying on ESYSXLAT — they are not in the generated correspondence
table (`src/common/syscall_xlat.cyr` is derived from the calls BOTH `lib/syscalls_x86_64_linux.cyr` and
`lib/syscalls_aarch64_linux.cyr` define), so on ELF aarch64 they pass through unrenumbered. The build prints nothing
(the known open item in `archived/2026-08-23-darshana-aarch64-syscall-shadow-no-diagnostic.md`: a raw number with no
`SYS_*` name gets no ELF-aarch64 diagnostic).

## Reproduction

```cyr
include "lib/syscalls.cyr"
fn probe() {
    syscall(319, "x86-memfd", 1);     # memfd_create
    syscall(77, 999, 4096);           # ftruncate
    syscall(46, 999, 0, 0);           # sendmsg
    return 0;
}
var _r = probe();
syscall(60, 0);
```

`cyrius build --aarch64 nr.cyr nr && qemu-aarch64 -strace ./nr`:

```
Unknown syscall 319
tee(999,4096,0,0,0,0) = 0
ftruncate(999,0) = -1 errno=9 (Bad file descriptor)
```

So `memfd_create` is ENOSYS, `ftruncate` runs **tee** (aarch64 77) and `sendmsg` runs **ftruncate** (aarch64 46).
The same calls written with the aarch64 numbers (279, 46, 211) run as themselves, since none of those numbers is in the
table either. The translated neighbours behave: 41 → `socket`, 42 → `connect`, 9/11 → `mmap`/`munmap`, and 7 → `ppoll`
with the millisecond timeout converted (a 50 ms wait measured 51 ms).

## What the consumer does meanwhile (thoth 0.52.3)

`src/gui/gwindow.cyr` writes `#ifdef CYRIUS_ARCH_AARCH64` literals (211 / 46 / 279) beside the x86_64 ones, and its GUI
suite runs all three for real (`test_gui_shm_calls`: a socketpair stands in for the compositor; the memfd is sized and
its fd arrives on the other end), run natively and as an aarch64 binary under `qemu-aarch64`. ⚠ The stopgap is fragile
in exactly one direction: if a later stdlib names `SYS_SENDMSG` (46 ↔ 211) and `SYS_FTRUNCATE` (77 ↔ 46) in both tables,
the regenerated ESYSXLAT will renumber thoth's aarch64 literal **46** (meant as native ftruncate) into 211 (sendmsg).
The test catches it wherever it runs; a name would remove the hazard.

## Ask

Name the three in both peers — `SYS_MEMFD_CREATE` (319 / 279), `SYS_FTRUNCATE` (77 / 46), `SYS_SENDMSG` (46 / 211),
and `SYS_RECVMSG`'s partner is already there — ideally with `sys_memfd_create` / `sys_ftruncate` / `sys_sendmsg`
wrappers in `lib/syscalls_linux_common.cyr` beside `sys_socketpair` / `sys_recvmsg`. A consumer then writes names, the
table gains the rows, and the literals go. (macOS: `memfd_create` has no Darwin equivalent — `shm_open`, which is a
separate design; thoth refuses its window off Linux, so no Darwin route is needed for this consumer.)


---

## Corrections to this filing (added at close, 6.6.5)

Everything measured in the Reproduction section reproduced **verbatim** — `qemu-aarch64 -strace` gave the same
three lines from the same source. Five things — three in the filing, two found while closing it — were wrong or
incomplete, and they are recorded here rather than edited away, because each one changed the shape of the fix.

1. **"`src/common/syscall_xlat.cyr` … is derived from the calls BOTH peers define, so on ELF aarch64 they pass
   through unrenumbered" — the file is the DIAGNOSTIC, not the renumberer.** `programs/gen_syscall_xlat.cyr`
   derives it from SYS_* DECLARATIONS in the two peers and emits only `_SYSX_MEANT` / `_SYSX_USE` /
   `_SYSX_ACTUALLY`, which `src/frontend/parse_expr.cyr` consults to WORD A WARNING. The renumbering is the
   hand-written `cmp x8 / b.ne / movz x8` chain in `ESYSXLAT` (`src/backend/aarch64/emit.cyr`), and **it is never
   regenerated**. So naming the three calls in both peers — the filing's Ask — would have renumbered **nothing**.
   It would have added warning rows, and not even those for 46 and 77, which become "ambiguous" the moment the
   aarch64 peer declares them. The fix had to add the rows by hand, in a specific order.

2. **"if a later stdlib names SYS_SENDMSG and SYS_FTRUNCATE in both tables, the regenerated ESYSXLAT will
   renumber thoth's aarch64 literal 46 into 211" — correct conclusion, wrong mechanism, and the hazard is REAL.**
   ESYSXLAT is not regenerated (see 1), so nothing happens automatically. But the fix deliberately ADDS the
   `46 → 211` row, so the outcome the filing predicted is exactly what now happens: **thoth's
   `#ifdef CYRIUS_ARCH_AARCH64` literal 46, meant as native ftruncate, becomes sendmsg.** thoth must switch
   `src/gui/gwindow.cyr` to `sys_memfd_create` / `sys_ftruncate` / `sys_sendmsg` **before** moving its pin to
   6.6.5. Its own `test_gui_shm_calls` catches it under qemu-aarch64. kybernet has the mirror case:
   `qemu/landlock-fixture.cyr`'s aarch64 `SYS_TRUNCATE_NR = 45` becomes recvfrom.

3. **"macOS: memfd_create has no Darwin equivalent … so no Darwin route is needed for this consumer" — true for
   memfd, false for the file.** The wrappers are SHARED across peers, and `ftruncate`, `truncate`, `sendmsg` and
   `sendto` all exist on Darwin, so both Mach-O backends needed routes (x86 already had 77→201; 46, 44 and 76
   were added). `memfd_create` gets an in-body `-78` decline instead, which is what keeps the number out of the
   Mach-O emit entirely.

4. **The diagnostic the filing hoped would have caught this had a DEAD HALF — found while closing, fixed here.**
   `parse_expr.cyr` words the warning in two parts: "raw syscall N is x86_64 `name`", then "on ELF-aarch64 that
   number is `other`". The second clause had never printed, for any number, since v6.5.51. It was structural:
   `_SYSX_ACTUALLY` was generated from the aarch64 stdlib PEER's declarations, and `_row_wanted` emits a
   `_SYSX_MEANT` row only for x86 numbers that peer does NOT declare, so the two sets could not intersect.
   Measured: a probe carrying all 43 rows compiled to 43 warnings, 0 with the better text. It is regenerated from
   the committed kernel table now (`tests/data/syscalls/aarch64.tbl`), restricted to the `_SYSX_MEANT` numbers so
   every row is reachable — 35 of 43 carry it, the other 8 are genuinely unassigned on aarch64.

5. **A live sibling of the same root cause was found in the tree while closing: `lib/yukti.cyr:58`.** It declares
   `SYS_STATFS = 43` under `#ifdef CYRIUS_ARCH_AARCH64` — the correct native number — and ESYSXLAT has rewritten
   43 → 202 (x86 `accept`) since v6.2.10. Measured under `qemu-aarch64 -strace`:
   `accept(6293618, 0x7f254c000000, [0]) = -1 errno=14`, so `yukti_filesystem_usage` reports "statfs failed:
   errno 14" on every ARM host. It is the v6.5.36/.37 shadow class one level out from the two peer files every
   existing gate reads, and it is not cyrius's to fix — a patch to the vendored fold evaporates at the next
   `cyrius deps`. `aarch64_syscall_shadow.sh` axis 2 now sweeps the whole tree for the class and prints this one
   as a named LIVE DEFECT on every run.

**Wider than filed.** An ecosystem scan (141 repos, 7,296 syscall sites) found 467 arch-neutral unrouted sites
whose x86 meaning differs on aarch64. The same shape covers the whole send side of the socket band, `truncate`,
`nanosleep`, and the bare-name fs calls aarch64 dropped — about sixty ecosystem sites, mostly test cleanup that
silently did nothing on ARM. In-tree it was live in four places, one of which
(`tests/tcyr/stdlib/result_allocator_via.tcyr`) had a whole assertion group that **never ran on aarch64** because
its raw `syscall(53, ...)` failed into the test's own skip branch.

**Not fixed, deliberately — (a) six unrouted numbers.** Six x86 numbers stay unrouted because aarch64's native
meaning for each is a call the ecosystem uses: 24 sched_yield (aarch64 24 IS dup3), 53 socketpair (fchmodat),
52 getpeername (fchmod), 21 access (epoll_ctl), 90 chmod (kybernet declares native capget = 90), 17 pread64
(getcwd, and a product of the 79→17 row). `sys_sched_yield` and `sys_socketpair` exist so a consumer never has to
write those numbers.

**Not fixed, deliberately — (b) NINE MORE FAMILIES CONSUMERS HAND-ROLL, named here because the first cut of this
close dropped them in silence.** The premise-check's `widened_surface` listed them with collision notes; the
implementation neither shipped nor mentioned them, which is exactly the "shipping a subset labelled hardening"
deferral. They are NOT in the filing (thoth asked for memfd/ftruncate/sendmsg and got them); they come from the
141-repo scan. Each is a NEW PUBLIC STDLIB NAME plus a Darwin decision (route or decline), and each Darwin number
has to be read off an SDK on ecb/ach — this release already carries three that were derived from neighbouring
rows rather than an SDK read, and that is the open concern the cross-OS leg has to close. Adding nine more
families multiplies exactly that risk for calls nobody filed. Reasons per family, all measured against the live
58-row chain and the committed kernel tables:

| family | x86 → aarch64 | why it waits |
|---|---|---|
| `capget` / `capset` | 125/126 → 90/91 | **No technical blocker** — neither 125 nor 126 is a row source, neither 90 nor 91 is a row product. It is a pure API-surface addition with no filing. ⚠ `kybernet/src/lib/privdrop.cyr:88` and `shakti/src/caps.cyr:225,238` declare these themselves; measured, a duplicate `SYS_*` is a WARNING with "last definition wins", not an error, so it would not break them — it would add a warning to their build. |
| `chroot` | 161 → 51 | Clean renumber, but the row must sit BELOW the existing `51 → 204` getsockname row or every chroot is reissued as getsockname. Ordering-sensitive; `esysxlat_row_order.sh` would catch it, which is the point of having that gate before adding the row. `kavach/src/confine.cyr:123`. |
| `unshare` | 272 → 97 | Clean renumber (272 not a source, 97 not a product). Needs a macOS decline. `kavach/src/security.cyr:533`. |
| `ptrace` | 101 → 117 | ⛔ **Interacts with a row THIS release added.** 101 is now the PRODUCT of `35 → 101` (nanosleep), so a `101 → 117` row placed after it re-captures every nanosleep and turns it into ptrace. It only works ABOVE the nanosleep row — the kind of ordering invariant that wants its own release and its own mutation run, not a tail-end addition. `mirshi`. |
| `sched_getaffinity` | 204 → 123 | Same shape: 204 is the product of `51 → 204` (getsockname). Needs the ≥1000 private alias band or a placement above that row. `mirshi`, `szal`. |
| `pread64` / `pwrite64` | 17/18 → 67/68 | 17 is the product of `79 → 17` (getcwd) AND aarch64-native getcwd, which is why it is already on the deliberately-unrouted list above. Needs the alias band (`SYS_PREAD64 = 1067`). `bhumi/src/scanout.cyr:323`. |
| rlimit family | 97/160/302 → 261 | Not a renumber at all: aarch64 has no `getrlimit`/`setrlimit`, only `prlimit64`, and the argument lists differ (`setrlimit(res, rlim)` vs `prlimit64(pid, res, new, old)`). That is an arg-shifting row like `open → openat`, i.e. real hand-assembly. `daimon/src/agent.cyr:248,254` (raw 160 = aarch64 `uname`), `mirshi`. |
| `process_vm_readv` / `writev` | 310/311 → 270/271 | Clean renumbers; ptrace-class surface with one consumer (`mirshi/src/scratch.cyr`) and no filing. |

⛔ **And the diagnostic does NOT cover them meanwhile — stated plainly because the first draft of this paragraph
claimed it did.** That draft said a consumer writing raw 160 would now be told *"on ELF-aarch64 that number is
…"*, thanks to the `_SYSX_ACTUALLY` revival. Measured against the aarch64 fork: raw 160 produces **no warning at
all**. `_SYSX_MEANT` only carries numbers whose name is declared in BOTH peers, so a NAMELESS number is
structurally invisible to it — which is this filing's own root cause, restated. So these nine families stay in
exactly the silent class thoth reported, until each is named. (The revived `_SYSX_ACTUALLY` helps the 43 numbers
that ARE named and differ; it cannot help a number with no name.) Writing "the diagnostic covers the class" would
have been a check-shares-a-defect reassurance in the close of the issue about silent failure.

**"thoth's window never had a buffer on aarch64 Linux for ~20 releases"** was not checked — it is thoth-side
history and was not load-bearing. What WAS checked: `git log -S` on the would-be row encodings finds nothing, and
the ELF socket block added at v6.2.10 skipped 44-47, so these calls have been unrouted for as long as the aarch64
backend has existed — not since a particular regression.

## Review round 2 (same release) — and where the nine families now live

⛔ **The nine families above are now PINNED, not left in this archived file.** `docs/development/roadmap.md`'s
"Potential backlog — 6.x-cycle, unscheduled" carries an entry for them, split into the four with no technical
blocker (`capget`/`capset`, `chroot`, `unshare`, `process_vm_readv`/`writev`) and the five with real ones, with
acceptance criteria and a pointer back to this table. Per CLAUDE.md a deferral is real only when it is filed AND
pinned somewhere still open; an archived issue is neither. The CHANGELOG entry names them too. *(Round 2's
finding: the first close documented all nine here beautifully and mentioned them nowhere a reader would look.)*

Four further defects found in review of this close, all in the checks rather than the fix — see CHANGELOG [6.6.5]:

- `aarch64_syscall_shadow.sh` axis 2 printed `PASS … 0 declarations over 0 files` and exited 0 over an **empty
  tree walk**, taking the `KNOWN LIVE DEFECT lib/yukti.cyr:58` line with it. Each KNOWN entry is now re-derived
  by opening its own file directly, so a broken walk fails instead of going quiet.
- That axis's `SYS_*` regex could see **neither consumer shape this filing's close names** — thoth's
  `GWL_NR_FTRUNCATE = 46` nor attn11's `n = 83;`. New axis 3 covers both, and the walk now includes `src/` —
  where the compiler's own `syscall(113, …)` under `#ifdef CYRIUS_ARCH_AARCH64` had survived the release that
  wrote the rule against it.
- `assert_lte(sys_sched_yield(), 0, …)` accepted every failure: mis-declaring that syscall number still scored
  50/50, exit 0. Now an exact `assert_eq` per target.
- The five arm64-macOS raw-x86 parity rows added in round 1 were asserted inside `#ifdef CYRIUS_TARGET_LINUX`,
  so they ran on no Mac at all. Moved out; the readlink assertion's `/proc/self/exe` fixture (Linux-only) is now
  a symlink the test makes.
- `sys_lseek` — the seventh `widened_surface` asymmetry — was shipped nowhere and mentioned nowhere. Added.
