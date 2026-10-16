# `agnos_sock_send_deadline`: rearm=1's ceiling refresh after a re-arm is pinned by no row — deleting it leaves both deadline gates GREEN — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-3, `5fe80f00`: gate-only, `lib/` unchanged. The fake kernel gains mode `dl03` (the first data `#109` answers 0, every later one `min(3, len)`), and `agnos_sock_send_deadline.sh` axis 8's new row — `sys_write(fd, &big, 100)` under a 1 s send timeout — sends all 100 bytes in 35 `#109` calls with ceilings `1000000 750000 1000000 1000000 …`. Mutation 9 (`left = _agnos_dl_whole_us(tmo_us);` deleted) is now RED (1 FAIL, ceilings `1000000 750000 750000 …`) where both deadline gates were GREEN; mutations 1–8 re-run, each still RED. Every gate that drives the fixture is green. Fake kernel only. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 stdlib lane tree (`338fabc0`), x86_64 Linux host, by the mutation below.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 stdlib lane's review of `20c0e160` (issues/archived/2026-10-13-agnos-sys-sock-send-dl-109-peer.md). The reviewer deleted the line in a scratch copy; the fix step re-ran it.
**Severity:** Low — a gate coverage gap, not a live defect. The line is present and correct in the tree. If it regressed, the deadline would still hold. The cost would be early 0 returns that the loop retries.
**Affects:** `tests/gates/platform/agnos_sock_send_deadline.sh` (and `agnos_tls_deadline.sh`, which reaches the same loop). The code under test is `_agnos_sock_send_dl` in `lib/syscalls_x86_64_agnos.cyr` (6.7.11).

## Summary

`_agnos_sock_send_dl(conn, buf, n, tmo_us, rearm)` hands each sock_send_dl#109 call the time
left as its ceiling (`left`). With `rearm != 0` (sys_write's route), a call that moves bytes
re-arms the stall window:

```
            if (rearm != 0) {
                _agnos_dl_start(&dl, tmo_us);   # progress: the stall bound starts again
                left = _agnos_dl_whole_us(tmo_us);
```

The second line refreshes the ceiling to the whole window. No gate row fails when it is deleted.
None of the fake kernel's (`tests/fixtures/agnos_sctrace.cyr`) modes mixes a no-progress call
with a progress call under rearm=1:

- `dl3` always makes progress. `left` never shrinks, so the refresh never matters (axis 8: 34
  sends, every ceiling 1000000).
- `dl0` never makes progress. The window is never re-armed, so the refresh is never reached
  (axis 8's second row: 1000000 750000 500000 250000, then -1).

If the line regressed, a stall would shrink `left` (say to 750000). A later call that moves
bytes would then re-arm the deadline, but every #109 after it would still get the shrunken
ceiling. Each of those calls would end early with a 0, and the loop would retry it. The ceiling
would be wrong, but the deadline would still hold.

## Reproduction

The lane tree is copied to a scratch directory (`git archive HEAD`, plus `build/cycc`), and the
one line is deleted there:

```
$ diff <(git show HEAD:lib/syscalls_x86_64_agnos.cyr) lib/syscalls_x86_64_agnos.cyr
2723d2722
<                 left = _agnos_dl_whole_us(tmo_us);
$ sh tests/gates/platform/agnos_sock_send_deadline.sh; echo rc=$?
…
  ok: with no progress the window is not re-armed: ceilings 1 s, 0.75, 0.5, 0.25 s, then -1

PASS: agnos_sock_send_deadline — rearm=0 bounds the whole send; sys_write keeps its stall bound
rc=0
$ sh tests/gates/platform/agnos_tls_deadline.sh; echo rc=$?
…
  ok:   …with no sock_recv#49 call

PASS: agnos_tls_deadline — the TLS deadline bounds agnos socket reads and writes; no deadline, no change
rc=0
```

Expected: at least one FAIL row.

## Fix

The fix is gate-only, so the lib does not change:

1. Add a mode to `tests/fixtures/agnos_sctrace.cyr` (for example `dl03`). The #109 probe answers
   0, as in `dl3`. The first send with len > 0 answers 0, and every later one answers
   `min(3, len)`. `uptime_us#95` keeps advancing 0.25 s per read.
2. Add a row to axis 8 of `agnos_sock_send_deadline.sh`:
   `probe "sock_set_send_timeout(fd, 1, 0); var r = sys_write(fd, &big, 100);"`, then
   `trace dl03`, then check the logged #109 ceilings. Expected: `1000000 750000 1000000 1000000 …`.
   With the refresh line deleted the result is `1000000 750000 750000 750000 …`, so the row goes
   RED.
3. Record the deletion as mutation 9 in the gate's ledger, with its measured FAIL count.

## Acceptance

- The new row passes on the tree.
- With `left = _agnos_dl_whole_us(tmo_us);` deleted from the `rearm != 0` branch, the row is RED.
- The other mutations in the ledger are still RED.
