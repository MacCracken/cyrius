# A user `var SYS_*` shadowing the stdlib's arch-aware value silently emits the wrong syscall on ELF aarch64 — no diagnostic

**Status:** 🟠 **HALF CLOSED at v6.5.38 — the ROUTING is fixed, the general DIAGNOSTIC is still missing.** Shipped at `.37`: the two live SHADOWS, found by sweeping the whole table, fixed via the ≥1000 alias band — `sys_umount2` was issuing **getpid(2)** on every ELF-aarch64 build (measured under qemu: returned 1179922, a PID), `sys_epoll_pwait` would have issued pipe2. Occurrences three and four of the v6.5.36 class. Structural gate: `tests/gates/platform/aarch64_syscall_shadow.sh`.
Shipped at `.38`: **this filing's first specific claim, the missing `16→29` row, is CLOSED** — the ELF-aarch64 arm now remaps the x86_64 ioctl number. ⚠ Worth recording precisely, because the filing's framing implied a live stdlib bug and it was not one: `lib/syscalls_aarch64_linux.cyr` correctly declares the NATIVE 29 and nothing shadows it, so `sys_ioctl` has always worked *through the stdlib*. The gap was real only for source that hardcodes the x86 number — which is exactly what this filing reported, and which raw 16 sent to **fremovexattr**. MEASURED under qemu-aarch64 by removing the new row: `-14` (EFAULT, fremovexattr with a NULL name) against `-25` (ENOTTY, real ioctl). Gate: `tests/tcyr/crossos/syscall_ioctl_x86_compat.tcyr`, which asserts an EQUIVALENCE (raw 16 behaves identically to the peer's own `SYS_IOCTL`) and never an errno — the v6.5.36 lesson about `</dev/null` making ENOTTY/ENODEV host-dependent.
⛔ **STILL OPEN — the second claim, re-verified live 2026-09-01:** the `syscall not routed` warning is still gated behind `if (_TARGET_MACHO == 2)` (`src/frontend/parse_expr.cyr:944`), so an ELF-aarch64 build gets NO diagnostic for an unrouted raw syscall. **This is not a small follow-on and should not be filed as one.** On Mach-O, "unrouted" reliably means "will fault", so the warning is sound. On ELF-aarch64 unrouted is the NORMAL case — native numbers pass through by design — so the same check would fire on virtually every stdlib syscall. A sound diagnostic needs the discriminator the `.37` sweep already named: *is the declared value the x86 number for that syscall (intended renumber) or the aarch64 native one (shadow)?* Answering that inside the compiler needs an x86_64→aarch64 syscall CORRESPONDENCE TABLE (~350 entries) that does not exist in `src/` today — the two tables live in `lib/syscalls_x86_64_linux.cyr` and `lib/syscalls_aarch64_linux.cyr`, which the compiler cannot read at compile time. Where that table should live, and whether it is generated from the stdlib peers or hand-maintained (a hand-maintained duplicate of a derivable fact is the exact self-drifting shape this cycle keeps finding), is a maintainer design call.
**Placement:** unpinned — 6.x-line backlog. Diagnostics/codegen, so **never 7.x** (7.x = the language book + legal).
**Discovered:** 2026-08-23 during a darshana aarch64 cross-build audit (darshana v0.9.1 → v0.9.2 fix cut).
**Severity:** Medium — see [Severity rationale](#severity-rationale); there is an argument for High and the maintainer may want to raise it.
**Affects:** cycc 6.5.35 (observed). **Not bisected** — I did not establish when the ELF-aarch64 passthrough or the Mach-O-only gating of the routing warning began, so treat the range as "at least 6.5.35".
**Reporter:** darshana (consumer). Currently on cycc **6.5.35**; recommended minimum for a fix to deploy: whatever release carries it — darshana can pin forward freely, it has no floor constraint beyond the repo-wide **v5.0.0**.

## Summary

A consumer that defines its own `var SYS_FOO = <x86_64 number>` — a very common
shape in this ecosystem — shadows the stdlib's arch-aware definition
(`lib/syscalls.cyr` → `syscalls_x86_64_linux.cyr` / `syscalls_aarch64_linux.cyr`).
On x86_64 the two values agree and nothing happens. On aarch64 the consumer's
value wins and the emitted `svc` issues **a different, valid syscall**.

The build **succeeds**. The only diagnostic is:

```
warning:<source>:1:15: duplicate symbol 'SYS_IOCTL' redefined with conflicting value (last definition wins)
```

which reads as a cosmetic name-collision note, not as *"this binary now calls
`fremovexattr` where you wrote `ioctl`"*. Nothing else fires, because:

1. `ESYSXLAT`'s ELF-aarch64 arm passes an **unmatched** number through to the
   `svc` verbatim. That is correct by design — native aarch64 numbers must pass
   through untouched — but it means a stray x86_64 number is indistinguishable
   from an intentional native one.
2. The `warning: syscall not routed ...` diagnostic exists only on the **Mach-O**
   branch (`src/frontend/parse_expr.cyr:954`, backed by `_macho_arm_routes`).
   There is no ELF-aarch64 equivalent — and a naive port would be wrong for the
   reason in (1).

Net effect: the compiler holds a precise signal and spends it on a warning that
looks like lint.

## Reproduction

Repro file: [`repros/2026-08-23-aarch64-syscall-shadow-silent.cyr`](./repros/2026-08-23-aarch64-syscall-shadow-silent.cyr)

`cyrius.cyml` needs only `[deps] stdlib = ["syscalls"]`.

```cyrius
var SYS_IOCTL = 16;          // delete this line for the CLEAN variant
var TIOCGWINSZ = 0x5413;

fn main() {
    var ws[8];
    var rc = syscall(SYS_IOCTL, 1, TIOCGWINSZ, &ws);
    return rc;
}
```

Build — both succeed:

```sh
cyrius build           src/g.cyr build/g       # x86_64: exit 0, NO warning at all
cyrius build --aarch64 src/g.cyr build/g-a64   # aarch64: exit 0, duplicate-symbol warning
```

Run the aarch64 output under `qemu-aarch64`. `SHADOWED` is the file as written;
`CLEAN` is the same file with the `var SYS_IOCTL = 16;` line deleted:

| variant | stdout redirected (not a tty) | against a real pty |
|---|---|---|
| SHADOWED (`SYS_IOCTL` = 16) | **242** = `-14` **EFAULT** | **242** = `-14` **EFAULT** |
| CLEAN (stdlib resolves 29)  | 231 = `-25` ENOTTY | **0** (success) |

```sh
qemu-aarch64 build/g-a64     > /dev/null; echo $?    # 242
qemu-aarch64 build/clean-a64 > /dev/null; echo $?    # 231
script -qec "qemu-aarch64 build/g-a64"     /dev/null >/dev/null; echo $?   # 242
script -qec "qemu-aarch64 build/clean-a64" /dev/null >/dev/null; echo $?   # 0
```

Two different syscalls, proven by their distinct errnos. On aarch64-Linux **16
is `fremovexattr`** and ioctl is **29** (`include/uapi/asm-generic/unistd.h:69`
and `:95`), so the shadowed build hands `0x5413` (TIOCGWINSZ) to
`fremovexattr` as its `name` pointer and faults.

Note the asymmetry that makes this hard to catch by eye: **the x86_64 build
emits no warning whatsoever**, because there the local 16 and the stdlib's 16
agree and there is no value conflict. The warning fires on exactly the target
where the shadow is wrong.

## Root cause

Not a single bug — a gap between two behaviors that are each individually
defensible:

- `src/backend/aarch64/emit.cyr`, `fn ESYSXLAT` — the ELF-aarch64 arm (after the
  `_TARGET_MACHO == 2` branch returns) is a `cmp x8,#N / b.ne / movz x8,#M`
  chain over the x86→aarch64 compat set. Decoding every `cmp` row
  (`cmp x8,#N = 0xF1000000 | (N<<10) | 0x11F`), the source numbers are:
  `0 1 2 3 4 7 9 10 11 12 22 39 41 42 43 48 49 50 51 54 55 60 72 73 74 75 79 82
  88 217 228 232 262 269 280` plus the `1049`/`1054` private aliases. **16 is
  absent**, so it reaches the `svc` unchanged. Verified two ways: no
  `0xF100411F` (`cmp x8,#16`) anywhere in the file, and no `0xD28003A8`
  (`movz x8,#29`) either.
- `src/frontend/parse_expr.cyr:954` — the `syscall not routed` warning is inside
  the Mach-O path only.

The duplicate-symbol warning itself is emitted correctly and at exactly the
right moment; it is only *classified* as a generic name collision.

## Proposed fix

I do not know the frontend well enough to prescribe, so these are ranked by my
confidence, not by preference. **(A) is the one I would actually ask for.**

**A. Escalate the duplicate-symbol diagnostic when the shadowed name is a stdlib
`SysNr` enum member and the values differ.** (High confidence this is right.)
The condition is already detected and already arch-precise: it fires only on
value conflict, i.e. only on the target where the shadow is wrong. Making it an
**error** for `SysNr` members specifically would have caught every instance of
this class at build time, with what looks like a near-zero false-positive rate —
a consumer that deliberately wants a different number for a stdlib-named
constant is doing something that deserves to be spelled out. If a hard error is
too aggressive, a distinct named warning class that CI can grep for, plus
wording that names both values and the arch peer, would still be a large
improvement:

```
error: 'SYS_IOCTL' shadows lib/syscalls_aarch64_linux.cyr:47 (29) with 16;
       16 is 'fremovexattr' on this target. Remove the local definition —
       the stdlib value is arch-aware.
```

**B. A diagnostic for a literal/`var` syscall number that is a known x86_64-only
number with no ESYSXLAT row, when targeting aarch64.** (Low confidence —
surfacing, not prescribing.) This is the more general catch but is genuinely
risky: unrouted is the *normal* case on ELF aarch64, so the whitelist approach
that works for Mach-O (`_macho_arm_routes`) cannot be lifted across. It would
need a curated "x86-only numbers that are live syscalls on aarch64 with a
different meaning" set, which is real maintenance. Maintainer's call whether
that is worth it; (A) covers the stdlib-shadowing subset for free.

⚠ **What will *not* work here:** the v6.5.25 PE approach — making an unrouted
literal return `-38`/`-ENOSYS` instead of emitting a raw trap (documented at
`lib/syscalls_windows.cyr:44`). On PE, unrouted genuinely means unsupported. On
ELF aarch64, unrouted means "native number, pass through", so blanket-ENOSYS'ing
unmatched numbers would break every correct native call. Flagging this so it is
not reached for by analogy.

## Consumer-side workaround

Delete the local definition; let `lib/syscalls.cyr` resolve it. The stdlib
values are enum constants, so they inline as immediates with no indirection —
strictly better codegen than the `var` they replace (darshana's `.text` shrank
by 20 instructions).

Keep local **only** values that are genuinely arch-stable and not stdlib-defined.
For darshana that was the ioctl *request* codes `TCGETS` (0x5401), `TCSETS`
(0x5402), `TIOCGWINSZ` (0x5413) — both Linux arches share
`asm-generic/ioctls.h` (x86_64's `asm/ioctls.h` is a one-line include of it),
and the stdlib does not define them, so there is nothing to shadow.

Shipped in **darshana v0.9.2**. Verification note for other consumers: to check
a fix in the emitted code, disassemble the cross-build and look at the
*callsite* immediate — the syscall number lands in **`x0`** first and only
reaches `x8` at the end, so grepping `mov x8, #...` finds only ESYSXLAT chain
rows and will mislead you.

## Prevalence — same-shape candidates elsewhere

darshana is the verified instance. A scan of first-party `src/` trees shows the
pattern is common:

```sh
grep -rn --include="*.cyr" -E "^\s*var SYS_[A-Z0-9_]+[[:space:]]*=" */src/
```

⚠ **These are leads, not findings.** I verified only that the hardcoded number
has no ESYSXLAT row; I did **not** check whether each repo actually cross-builds
to aarch64, so several may have zero exposure. Listed so the maintainer can
gauge blast radius:

| repo | site | hardcoded | on aarch64 that number is |
|---|---|---|---|
| attn11 | `src/main.cyr:75` | `SYS_IOCTL = 16` | `fremovexattr` — same defect as darshana |
| thoth | `src/vendor/darshana.cyr:129` | `SYS_IOCTL = 16` | vendored pre-0.9.2 darshana; carries the fixed bug |
| daimon | `src/server.cyr:11` | `SYS_GETPEERNAME = 52` | `fchmod` — and note `syscalls_aarch64_linux.cyr:221-223` records that mapping x86-52 was **deliberately rejected** upstream because it collides with that peer's own `SYS_FCHMOD = 52` (`:205`) — CI caught exactly that as `sandbox_syscalls` RED on pi |
| majra, hoosh, szal | `envelope.cyr:22`, `vendor/majra.cyr:185` ×2 | `SYS_GETRANDOM = 318` | **unassigned** → `-ENOSYS`. Security-adjacent: worth checking whether the callers detect the failure or proceed with an unfilled buffer. The aarch64 peer uses **278**. |
| shakti, darshini | `timestamp.cyr:21`, `walk.cyr:43` | `SYS_LSTAT`/`_X86 = 6` | `lsetxattr` |
| phylax | `src/types.cyr:40` | `SYS_FSTAT = 5` | `setxattr` |

Several of the numbers in that scan are **fine** — `41`/`42`/`43`/`49`/`50`/`55`
(sockets), `82`, `88`, `228`, `7` and others *are* in the ESYSXLAT compat set
and get renumbered correctly. That is precisely what makes the pattern hard to
reason about by inspection: hardcoding an x86_64 number is correct for most of
the common ones and silently wrong for the rest, with no way to tell which
without decoding the table.

The `SYS_GETRANDOM = 318` row is the one I would look at first if this gets
picked up.

## Severity rationale

Filed **Medium** rather than High because the workaround is trivial and known
(delete the line), which fails the guide's *"no workaround available"* test for
High. Filed above Low despite the surface symptom being a misleading warning,
because the underlying failure is a silently wrong syscall in a successfully
built binary, not a cosmetic message.

Arguments for raising it, left to triage: the failure is silent on the arch
where it matters and *completely* silent on the arch developers actually test
on; the compiler already has the exact signal and discards it; and the
`getrandom → ENOSYS` lead above is security-adjacent if any of those three
consumers ship aarch64.
