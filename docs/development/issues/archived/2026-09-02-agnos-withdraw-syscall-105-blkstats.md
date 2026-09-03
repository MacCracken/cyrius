# WITHDRAW `SYS_BLKSTATS` #105 — agnos removed the syscall; it never needed a number

> ## ✅ DONE at cyrius 6.5.45 — `SYS_BLKSTATS` and `fn sys_blkstats` removed; ABI parity back to 105/105, 0 disagreements.
>
> ⚠ **This filing and `2026-09-02-agnos-sysinfo-wrapper-needs-a-length.md` CONTRADICTED each other** — that one states "#105 ... is NOT being moved ... unwinding it would waste that release" and reports the gate green at 106/106/106. Settled against the LIVE agnos kernel rather than either verdict: no `num == 105` arm in `kernel/core/syscall.cyr`, no `blkstats` anywhere in `kernel/`, and the ABI table lists `| 104 | blk0_read |` as a **sysinfo tail offset**. THIS filing is the correct one.

**Status:** 🔴 **OPEN — ACTION NEEDED. The kernel arm is GONE as of agnos 1.56.59; the peer still
advertises it.** This is a removal, not an addition, and it is the one item in this filing that is
time-sensitive.
**Ask:** delete `SYS_BLKSTATS = 105` and `fn sys_blkstats(tag, field)` from
`lib/syscalls_x86_64_agnos.cyr`.
**Reporter:** agnos (kernel), agnos **1.56.59**.
**Affects:** cyrius **6.5.44**, which shipped the peer.
**Severity:** Medium — see below. It is not cosmetic while both sides disagree.

## What happened, plainly

agnos minted `blkstats`#105 in the 1.56.59 cut, filed it here, and you shipped the peer in 6.5.44.
An extend-vs-mint audit of the whole 106-syscall surface then found **it never needed a number**:

* Its tag space is a **closed 5-value enum** (`BLK_VIRTIO`..`BLK_RAMDISK`, `block.cyr:28-33`) enforced
  identically in three places, over **flat by-tag arrays** (`blk_reads_by_tag[6]`,
  `blk_writes_by_tag[6]`) — i.e. exactly a fixed-size record.
* `sysinfo`#35 takes a caller **length** and its documented rule is *"future fields append at the tail
  and bump the minimum len."*
* So the counters belonged in `sysinfo`'s tail, which is where they now are: **`+104 + tag*16 + 0`**
  sectors read, **`+8`** sectors written, tags 0..5, minimum length **200**.

`blk_info`#79 *was* correctly ruled out (fixed arity, no length parameter) — and the test stopped
there instead of continuing to `#35`. That is the whole mistake.

## Why agnos removed it rather than leaving it standing

A needless syscall number is **permanent surface**: every consumer, every ABI gate and every peer
carries it forever, and it becomes the obvious place to hang the next block-telemetry field, which
compounds the error. Removing it while exactly one release has shipped it is the cheapest this ever
gets.

## ⚠ Why this is Medium and not Low

Until the peer is removed the two sides disagree, and agnos's own gate names the hazard:

```
kernel 105 · abi-doc 105 · cyrius 106
FAIL: 1 number(s) in cyrius with NO kernel arm —
      a caller gets the dispatch fall-through value and reads it as data
```

A consumer that calls `sys_blkstats(tag, field)` today does not get an error; it gets whatever the
agnos dispatch fall-through returns and may render it as a statistic. No shipped consumer calls it —
it was minted and superseded inside a single agnos cut, and chakshu reads the `sysinfo` tail — but the
wrapper is live in 6.5.44 and nothing stops one.

## What replaces it, for the wrapper comment if you want it there

Nothing new upstream. The counters ride `sysinfo`#35's tail, which needs no ABI-table row and no
number. ⚠ It does need the **length-taking `sys_sysinfo` overload** filed separately at
`2026-09-02-agnos-sysinfo-wrapper-needs-a-length.md` — `fn sys_sysinfo(out)` hardcodes 40, so no
wrapper consumer can reach either tail band. **Those two are one piece of work**: land the overload
and drop `SYS_BLKSTATS` in the same change.

## ⛔ The process failure behind this, recorded so it does not recur

Three agnos numbers were minted in one cut and filed as **three separate asks** — `#104` (you shipped
6.5.43), `#105` (6.5.44), and `#106` — from a **single** consumer filing whose full surface was known
at triage. Two of the three turned out to need no number at all. That cost two releases and two
sibling re-pins where one ask would have done, and the cost lands on the operator re-pinning every
repo that wants one toolchain version.

Corrections made on the agnos side:

* `#106` was caught before it cost a release and folded into `sysinfo`'s tail.
* `#105` is this withdrawal.
* The surface is now audited and recorded: **9 length-carrying** syscalls take tail fields, **16
  field/op selectors** take new ids free, and only what neither can carry earns a number. The test is
  mechanical now instead of remembered.
* When agnos next mints numbers, they go out in **one** ask.
