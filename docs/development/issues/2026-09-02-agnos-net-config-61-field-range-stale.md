# `sys_net_config` #61 — the documented field range is now stale (agnos added 8..11)

**Status:** 🟠 **OPEN — comment/doc only. No code change to the wrapper itself.**
**Ask:** update two comments in `lib/syscalls_x86_64_agnos.cyr` that state `#61`'s valid field range.
**Placement:** 6.x — documentation sync.
**Reporter:** agnos (kernel), agnos **1.56.59**.
**Severity:** Low, but filed rather than left because a stale documented RANGE is how a consumer
concludes a capability does not exist and builds a workaround for it — which is precisely what
happened to the same consumer twice this week (see the note at the bottom).

## What is stale

Two places describe `#61`'s fields:

* `lib/syscalls_x86_64_agnos.cyr:449` — `# net_config(field) → packed IPv4 (0..3) / counter (4..7) / -1 bad field.`
* `lib/syscalls_x86_64_agnos.cyr:1381-1389` — the block above `fn sys_net_config`.

agnos **1.56.59** added four fields:

```
 8  net_tx_packets    frames handed to the NIC and accepted
 9  net_rx_packets    frames taken off the wire
10  net_tx_bytes      their total length
11  net_rx_bytes      their total length
```

All four are **monotonic since boot and never reset** — a monitor differences two samples to draw a
rate, so anything that clears them yields a negative delta and a nonsense rate line.

## ⚠ No wrapper change is needed, and that is the point worth recording

`fn sys_net_config(field)` already takes an arbitrary field id and passes it through, so **a consumer
can read these today on cyrius 6.5.43 with no toolchain change at all.** That is exactly why agnos
extended `#61` instead of minting a number for network counters: it ships to consumers immediately
rather than waiting on a peer release. Only the comments are wrong.

## Why this is filed at all

agnos's tracker records two consumers this week that built or nearly built a workaround against a
capability that already existed, because a comment said it did not:

* **chakshu** nearly filed a phantom `statfs` gap — an agnos comment claimed FAT/exFAT were "filed as
  a follow-on rather than half-built" while both arms sat 20 lines beneath it.
* **crab** carried a blocker for **five releases** after the fix for it shipped, because nobody
  re-read the syscall table.

A range that says `4..7` when it means `4..11` is the same defect one layer up. Cheap to fix while it
is one line; expensive once someone has written the workaround.
