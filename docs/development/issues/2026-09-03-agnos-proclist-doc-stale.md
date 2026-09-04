# 2026-09-03 — `sys_proclist`'s doc block is stale, and it hides two live fields

**Filed by:** chakshu (the AGNOS system monitor), during v0.9.9.
**Affects:** `lib/syscalls_x86_64_agnos.cyr` — documentation only, no code defect.
**Checked against:** cyrius **6.5.45**, agnos **1.56.60**.

## What is wrong

`sys_proclist`'s doc block still describes `proclist`#99's `+56` slot as dead:

```
#   +56  u64 reserved    always 0 today
...
# ⚠ THE RESERVED FIELD IS NOT SPARE SPACE. Per-process rss and cpu time are not tracked by
# the kernel yet; when they are, they land at +56 and the record size does NOT change.
```

**agnos 1.56.59 filled it.** `kernel/core/syscall.cyr:10424`:

```
store64(pl_rec + 56, (pl_rs << 32) | pl_tk);
```

One `store64` of a packed pair — low u32 is cpu ticks (100 Hz), high u32 is rss pages
(4 KiB). The text is byte-identical to 6.5.41's; the 6.5.43/6.5.44/6.5.45 edits touched
only the `#104`/`#105` hunks around it.

## Why it matters more than a stale comment usually would

This is the *only* description of the record a consumer reads. A caller who trusts it
does one of two things, and both are bad:

1. **Zero-checks the u64 and skips it.** That consumer stays *correct* — a zero u64 does
   mean "neither field present" — but silently reads no data, exactly as chakshu did
   between agnos 1.56.59 and this cut. This is the second time chakshu has lost a release
   to a stale upstream note (the previous one: `proclist` itself was recorded as "blocked
   upstream" for five releases after it shipped).

2. **Reads `load64(rec + 56)` and renders it.** On a live process the packed value is
   ~6.6e12. It is positive and formats fine — but it is 2,000 years as a tick count and
   25 PB as a page count. A plausible-looking wrong number in a system monitor.

## Suggested text

```
#   +56  u64 packed      LOW u32 = cpu ticks (100 Hz) · HIGH u32 = rss pages (4 KiB)
#                        (agnos 1.56.59; the record size did not change)
```

plus, replacing the "not tracked yet" paragraph:

> ⛔ READ THE HALVES, NEVER THE SLOT. `load32(rec + 56)` is the tick count and
> `load32(rec + 60)` is the rss page count on little-endian targets; the equivalent
> `load64(rec + 56) & 0xFFFFFFFF` / `(load64(rec + 56) >> 32) & 0xFFFFFFFF` is also
> correct. Rendering the packed u64 as either field yields a positive, plausible,
> nonsensical number.
>
> ⚠ The rss half is 4 KiB pages but its RESOLUTION is 2 MB: the kernel counts
> present-AND-user PDEs and adds 512 pages each, so the value is always a multiple of
> 512. It is honest as "physical memory committed to this process", not as
> Linux-comparable RSS.
>
> ⚠ The tick half counts wall-clock ticks while the slot was current, INCLUDING time
> halted in a blocking syscall — it is not CPU utilisation. Filed against agnos as
> `2026-09-03-per-process-ticks-include-halt.md`.

## Optional: accessors

There are none for these halves anywhere in `lib/` — `grep -rn proclist` returns only the
raw `fn sys_proclist(buf, max)`. That is a fair contrast with `sysinfo`'s tail, which
*did* get the `sysinfo_cpu_user` / `sysinfo_blk_read` family precisely because, in that
band's own words, *"hand-computing `+104 + tag*16 + 8` at every call site is how an
off-by-one band read becomes a plausible-looking statistic"*. The same argument applies
to a packed-u32-pair extraction.

Two would cover it:

```
fn proclist_cpu_ticks(rec): i64 { return load32(rec + 56); }
fn proclist_rss_pages(rec): i64 { return load32(rec + 60); }
```

⚠ Not a blocker — chakshu does the arithmetic itself today and it is three lines. The
doc fix is the part that matters, because it is what stops the next consumer losing a
release to it.
