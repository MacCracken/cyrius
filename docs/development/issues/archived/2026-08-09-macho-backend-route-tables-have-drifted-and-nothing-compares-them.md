# The two Mach-O backends' syscall route tables have drifted, and NOTHING compares them

**Filed:** 2026-08-09 (v6.5.16 cycle), from the v6.5.15 post-mortem
**Status:** ✅ **RESOLVED in v6.5.16** — archived 2026-08-09, same cycle it was filed.

## Resolution

`tests/gates/platform/macho_route_parity.sh` (registered in `programs/checks/main.cyr`, so
`check.sh` runs it — static, no Mac required), **plus the drift it surfaced, fixed**. All
five acceptance criteria are met; the gate is keyed on **capability**, not source number,
exactly as this file argued.

**Three axes.** (1) every `SYS_*` a wrapper issues is routed on its OWN backend — this is
what catches a facility unreachable on both; (2) no capability is routed on exactly one
Mach-O backend; (3) `_macho_arm_routes` mirrors the `ESYSXLAT` sources exactly. Both parse
traps this file warned about are handled: the parser anchors on `fn ESYSXLAT` rather than
the `_TARGET_MACHO == 2` string (which also appears in `ESYSCALL`), decodes `cmp x8,#N`
with the full `0xF1000000 | (N<<10) | (8<<5) | 0x1F` mask, and carries a **corpus floor**
so a parse that silently returns 0 routes fails loudly instead of passing vacuously.
The allow-list carries a one-line reason per entry (criterion 4).

**Mutation-proven** (criterion 3): deleting `_msx(S, 91, 0x200007C)` — the real v6.5.15
fchmod bug — turns axes 1 and 2 RED and the gate exits **1**; restoring it exits **0**.

**The drift it found, all fixed rather than filed:**

| gap | backend | fix |
|---|---|---|
| whole credential family unrouted | both | see the companion issue |
| `sys_fstat` — peer issues 80, unrouted ⇒ dead on ecb | arm64 | `80 → fstat64 **339**`, NOT `fstat 189`: this peer uses the **stat64** layout (MODE=4, SIZE=96) and 189 fills the legacy one. Live-probed both on ecb — 189 would have returned rc=0 with every field silently wrong |
| whole at-family unrouted ⇒ SIGSYS on ach | x86 | `257→463 258→475 262→**469** 263→472 264→465 265→471 268→467`. ⚠ `262→469` (legacy `fstatat`), NOT the arm64 target 470 (`fstatat64`) — mirror-image of the fstat trap, live-probed on ach |
| `sys_fcntl` — peer issues 25, only raw x86 72 routed ⇒ every async O_NONBLOCK/CLOEXEC setup dead | arm64 | `25 → 92` |
| `sys_fdatasync` absent from the x86 peer ⇒ `platform/fsync` failed to **compile** on ach | x86 | added the wrapper + `75 → 187` on both |
| `lstat`, `dup`, `ioctl`, `kill`, `sync`, `gettid`, `recvfrom`, `recvmsg`, `setuid`, `setgid`, `setsid`, `setgroups` | both | routed on both backends |
| `file_lock` issued raw `syscall(92)` labelled "BSD flock" — Darwin 92 is **fcntl**, flock is 131, and 92 was unrouted ⇒ SIGSYS on ach | both | `lib/io.cyr` now issues the x86 number 73; `73 → 131` on both |
| 7 socket numbers live in `ESYSXLAT` but unregistered in `_macho_arm_routes` ⇒ spurious "not routed" warning on working code | arm64 | registered (axis 3 now blocks this) |

Route counts: **aarch64 67 → 86, x86 51 → 76.**

**Also fixed, found by the same sweep:** `programs/cyrius-lsp.cyr` called raw `syscall(80)`
for chdir on an "LSP is x86-only" assumption — 80 is the aarch64 peer's `SYS_FSTAT`, so the
new fstat route would have silently turned that chdir into an fstat. Now `sys_chdir()`.
And `lib/fdlopen.cyr`'s trust check reads x86-Linux `struct stat` offsets from a raw
`lstat`; once `6 → 190` was routed the call would have SUCCEEDED and read the wrong words,
so its macOS arm now declines — a security predicate misreading uid/mode is worse than one
that fails.

**Verified:** ach full corpus **252 pass / 12 fail → 264 / 0**; ecb crossos 41/41.
Every Darwin number used came from the SDK table on ecb and was live-probed; nothing was
taken from memory or a header grep alone.
**Severity:** Medium — each missing route is a **SIGSYS kill or a wrong-syscall** on one Mac
architecture only, invisible on the other and invisible on Linux.
**Affects:** `src/backend/x86/emit.cyr` (`EMACHO_SYSXLAT`, ach / Intel-Mac) and
`src/backend/aarch64/emit.cyr` (`ESYSXLAT`'s `_TARGET_MACHO == 2` branch, ecb / Apple Silicon).

## Why this is being filed now

v6.5.15 turned the release gate RED on ach with **two** defects that were the same shape:

1. `SIGPWR = 30` was fixed on the aarch64 Darwin arm and left live on the x86-macOS peer —
   and 30 IS Darwin's `SIGUSR1`, so `kill(pid, SIGPWR)` delivered the wrong signal.
2. `sys_fchmod` had **no `EMACHO_SYSXLAT` route at all**, so the number reached Darwin
   unprefixed and every Intel-Mac call died with **SIGSYS (rc 140)** — for as long as the
   wrapper has existed. It surfaced only because .15 added the first crossos assertion that
   actually CALLS it.

Both are the "fixed one fork, not the other" pattern. The gate caught them, but only because a
new test happened to exercise those two calls. Nothing systematically compares the tables.

## Measured (v6.5.16, by parsing both tables)

| backend | routes |
|---|--:|
| aarch64 macho (`ESYSXLAT`, `_TARGET_MACHO == 2`, lines 624-867) | **65** |
| x86 macho (`EMACHO_SYSXLAT`, `_msx` entries) | **47** |

⚠ **DO NOT diff the SOURCE numbers — that comparison is meaningless.** The two peers issue
different source numbers by design: `lib/syscalls_macos.cyr` emits x86-Linux numbers and
`lib/syscalls_aarch64_linux.cyr` emits aarch64-Linux numbers, each renumbered by its own
backend. Comparing by **destination BSD number** instead:

```
BSD targets routed on x86-macOS only  (9): 9 10 15 33 58 136 137 189 201
BSD targets routed on aarch64-macOS only (10): 344 465 466 470 471 472 473 474 500 2079
```

⚠ **AND THAT DIFF ALSO OVER-REPORTS — triage each, do not bulk-add.** Much of the asymmetry is
CORRECT: aarch64-Linux has no bare `unlink`/`access`/`chmod`/`mkdir`, only the at-family
(`unlinkat`/`faccessat`/`fchmodat`/`mkdirat`), so its peer legitimately targets Darwin's
at-family numbers (465-474) while x86's targets the bare ones (9/10/15/33/136/137). Those pairs
are two correct spellings of the same capability, not a gap.

The real question per row is **capability**, not number: *can a program on this host reach this
kernel facility at all, by whichever spelling its peer uses?* `fchmod` failed that test on x86
(BSD 124 was reachable on ecb, unreachable on ach) and nothing noticed.

## What to build

A gate that compares the two tables **by capability**, with an explicit allow-list of pairs that
are legitimately spelled differently (bare vs at-family). It must fail when a facility is
reachable on one Mac architecture and not the other.

⚠ Two traps this gate must avoid, both hit while producing the numbers above:
- A first parse of the aarch64 side returned **0 routes** because it looked for the branch in
  `ESYSCALL` (the `svc` emitter at ~line 422) instead of `ESYSXLAT` (~line 616). Both contain a
  `_TARGET_MACHO == 2`. Anchor on the function, not the string.
- `cmp x8,#N` encodes as `0xF1000000 | (N<<10) | (8<<5) | 0x1F`. Dropping the Rn field silently
  yields plausible-but-wrong numbers.

## Acceptance criteria

1. The gate enumerates both tables from source and reports counts (65 / 47 today).
2. It fails when a capability is routed on exactly one Mach-O backend, allow-list aside.
3. **Mutation-proven**: deleting the `_msx(S, 91, 0x200007C)` fchmod route (the real v6.5.15
   bug) must turn it RED, and re-adding it green.
4. The allow-list carries a one-line reason per entry — an unexplained allow-list entry is how
   this rots again.
5. It runs in `check.sh` (host-side static analysis; no Mac needed), so drift is caught at
   commit time rather than at the cross-OS leg.

## Related

- `crossos/syscall_wrappers.tcyr` — the runtime counterpart. It proves a wrapper RUNS on each
  host, which is stronger, but only for the calls it happens to make. This gate is the static
  complement: it covers every route, not every call.
- `2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md` — 6 failures remain on ecb.
