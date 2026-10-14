# `lib/syscalls_x86_64_agnos.cyr` has no `sys_sock_send_dl`#109 peer

**Status:** 🟡 **OPEN** — filed by agnos (2026-10-13). agnos has assigned and built the number in its 1.57.13 cut, where it is reviewed and gated. Do not mint it here before agnos's `1.57.13` tag.
**Placement:** 6.7.11 — repair 1, the stdlib lane — an agnos filing (pulled in at the open: user, 2026-10-13) — never 7.x. Was: `lib/syscalls_x86_64_agnos.cyr`. The constant goes in the `SysNrAgnos` enum next to `SYS_SOCK_SEND = 48` (:522). The wrapper `sys_sock_send_dl()` goes next to `sys_sock_send()` (:1985). Then `_agnos_sock_send_dl` passes it the time left.
**Filed:** 2026-10-13, by agnos. agnos minted and built the number; cyrius owns the peer.
**Affects:** cyrius **6.7.10**. `#109` exists from agnos **1.57.13**.
**Severity:** **Low as a defect, blocking for the consumer.** Until the peer lands, cyrius's agnos TLS write cannot honour its caller deadline (CVE-61's *Not covered*: a write overshoots the deadline by up to ~8 s). Ring 3 can call `#109` by raw number today.

## The ask

```
SYS_SOCK_SEND_DL = 109;   # sock_send_dl(conn_id, buf, len, timeout_us) → committed count (≤ len, maybe 0) / -1 (agnos 1.57.13)
fn sys_sock_send_dl(conn_id, buf, len, timeout_us): i64 {
    return syscall(SYS_SOCK_SEND_DL, conn_id, buf, len, timeout_us);
}
```

Then `_agnos_sock_send_dl` passes the **time left before the deadline, in µs**, as `timeout_us` on each call. It no longer only checks the deadline between `#48` calls.

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, row 109 — authoritative)

`#109` is `#48` with a caller ceiling. Validation, ownership and the one-segment-in-flight behaviour are the same as `#48`.
- **Returns -1** for a conn that is not the caller's, checked first, even when `len <= 0`. It also returns -1 for a bad range, and for a conn that is neither ESTABLISHED nor CLOSE_WAIT at entry.
- **`timeout_us` bounds the call's waiting.** It is measured **once from entry** and is **never re-armed by ACK progress**. Linux `tcp_sendmsg` keeps one `timeo` across the call the same way.
  - When it fires, the call returns the **committed count, possibly 0**. A 0 means "no progress yet" and is not fatal.
  - A chunk that can go out without waiting still goes. So the call may commit one chunk after its ceiling and return at once.
- **`timeout_us = 0` is exactly `#48`**: no ceiling, only `#48`'s ~8 s progress window.
- **`timeout_us < 0` means no wait at all**, as Linux treats a negative `SO_SNDTIMEO`. A caller whose time left is ≤ 0 should pass a negative value or not call.
  - ⚠ Never pass 0 to mean "time's up". 0 means "no ceiling".
- Values above 2^40 are clamped.
- The call is never early. It expires at the first timer tick at or after the ceiling, which is ≤ ~10 ms late plus wake latency.

**Probe:** `#109(conn, buf, 0, 0)` on a conn you own returns 0 on a supporting kernel and -1 before 1.57.13, where the number is unknown.

## Why it exists

This is agnos issue `2026-10-02-sock-send-ignores-the-caller-deadline`, filed from cyrius 6.6.14 (now `docs/development/issues/archived/` in agnos).

- The `#48` arm pinned its progress window at 8 s.
- cyrius's `_agnos_sock_send_dl` could check the deadline only between calls. So under a +1 s deadline, `tests/gates/platform/agnos_tls_deadline.sh` measured `TLS_ERR_TIMEOUT` ~8.25 s late.
- `#109` is a **new number, not an `a4` on `#48`**. On this ABI `a4` is a stale register in every shipped three-argument `#48` caller, so widening the arm would change their behaviour.

On agnos the gate is `scripts/smoke/sock-send-dl-smoke.sh` (`-smp 1` and `-smp 4`):
- A 300 ms ceiling against a zero-window peer returns in 303–310 ms.
- A trickling peer cannot stretch the call.
- `0` behaves as `#48`.

## Compatibility

Nothing existing changes: this adds one enum constant and one function. `#48` and `sys_sock_send` are untouched. After this lands, re-run `agnos_tls_deadline.sh` with a real-kernel leg and drop the item from CVE-61's *Not covered*.

## Related

- agnos `docs/development/agnos-userland-abi.md` § 3.2 row 109 — the authoritative contract.
- `2026-10-13-agnos-sys-console-mode-110-peer.md` and `2026-10-13-agnos-sys-fd-kind-111-peer.md` — the other two numbers agnos 1.57.13 adds.
- agnos's `scripts/check/syscall-abi-check.sh` reads "kernel 111 · cyrius 108" until all three peers land. It is red on the agnos side by design until then, as at agnos 1.57.10 for `#106`–`#108`.
