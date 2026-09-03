# `sys_sysinfo` hardcodes len=40, so consumers cannot read AGNOS's extended tail

**Status:** 🟠 **OPEN — wrapper only. NO new syscall number, NO ABI-table row, NO agnos-side change.**
**Ask:** give `sys_sysinfo` a caller-supplied length (an overload or a second arity), so a consumer can
read the fields AGNOS appended past +40.
**Placement:** 6.x — one function.
**Reporter:** agnos (kernel), agnos **1.56.59**.
**Severity:** Low. Nothing is broken; the tail is reachable today by a raw `syscall(35, buf, 104)`,
which is what the agnos gate uses.

## The gap

`lib/sys.cyr:225-227`:

```cyrius
fn sys_sysinfo(out): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return syscall(SYS_SYSINFO, out, 40);   # v6.2.23: named const, was literal 35
    #endif
```

Arity 1, length **hardcoded to 40**. agnos 1.56.59 appended a per-core CPU block at **+40..+103**
(4 CPUs × {user, kernel} 100 Hz ticks, minimum length **104**), following that syscall's documented
rule — *"future fields append at the tail and bump the minimum len; the existing offsets are frozen
ABI the moment a consumer reads them."*

So the kernel exposes it, and every wrapper consumer still gets 40 bytes. **chakshu** — the system
monitor this was built for — reads `#35` only through `lib/mihi.cyr` → `sys_sysinfo`, so as shipped it
cannot see the new fields at all.

⚠ **The four vendored copies matter here.** `lib/sys.cyr:225` is duplicated byte-identically in
`iam`, `chakshu` and `agnoshi`. Whatever shape you pick has to reach them via the normal snapshot
resync, or three consumers keep the 40.

## Shape

Whatever fits the stdlib's conventions. The minimum that unblocks it:

```cyrius
fn sys_sysinfo_n(out, len): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return syscall(SYS_SYSINFO, out, len);
    #endif
}
```

`SysInfoConst.SYSINFO_SIZE = 40` (`lib/sys.cyr:216`) and the `SysInfoOffset` enum would want
`SYSINFO_SIZE_EXT = 104` plus the eight tick offsets in the same change — nothing reads past +32
today, so it is additive.

## ⚠ Why this is filed as ONE ask, and what it is atoning for

**Three agnos syscalls were minted in the 1.56.59 cut and filed as three separate asks — `#104`
(you shipped 6.5.43), `#105` (6.5.44), and a third that turned out not to need a number at all.** All
three came from a single consumer filing whose full surface was known at triage. That cost two
releases and two sibling re-pins where one would have done, and the cost lands on the operator, not
on agnos.

Two corrections have been made on the agnos side so it does not recur:

1. **The third capability was moved onto `sysinfo`#35's tail instead of a new number** — the change
   this filing supports. `syscall-abi-check.sh` reads `kernel 106 · abi-doc 106 · cyrius 106`, green,
   nothing pending.
2. **An extend-vs-mint audit of the whole 106-syscall surface** now records which calls can absorb new
   capability without a number: **9 length-carrying** (tail append) and **16 field/op selectors** (new
   ids free). It also found that **`#105 blkstats` should have been a `sysinfo` tail append too** — its
   tag space is a closed 5-value enum over flat by-tag arrays, 80 bytes at +104. ⛔ **It is NOT being
   moved**: the number is minted, the peer shipped in 6.5.44, and unwinding it would waste that release
   and break anything already bound. As built it is itself a free extension point — future block
   telemetry rides new field ids with no number and no peer change.

⇒ **This is the only outstanding peer need from that cut.** If more agnos numbers are minted later,
they go out in one ask.
