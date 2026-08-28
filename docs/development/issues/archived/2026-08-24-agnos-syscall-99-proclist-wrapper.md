> ## ✅ SATISFIED in this edit — `SYS_PROCLIST = 99` + `fn sys_proclist(buf, max)` are in
> `lib/syscalls_x86_64_agnos.cyr`, and `tests/gates/platform/syscall_wrapper_pass.sh` axis 5
> asserts both. Filed anyway, per the standing rule that an agnos↔cyrius syscall is recorded
> on **both** sides rather than in whichever repo happened to notice it.
>
> ⚠ Presence is not compatibility. This was verified only by compiling for the agnos target;
> nothing here has been exercised against a booted kernel through the wrapper. That is the
> lesson `sys_readlink` taught this file — it turned out to take 4 args, not 3.

# agnos peer: `SYS_PROCLIST = 99` + a `sys_proclist` wrapper for process enumeration

> ## ➕ 2026-08-26 — **THIS TICKET NOW ALSO COVERS `#100` AND FOUR `net_config` FIELDS.**
> agnos **1.56.48** minted `#100 icmp_echo_ex(dst_ip, timeout_ms)` and extended
> `net_config`#61 with ICMP counter fields 4..7. Both are **unreachable from cyrius
> today** — there is no `SYS_ICMP_ECHO_EX` constant and no wrapper for the new fields,
> so `yo` cannot consume either without hardcoding raw numbers, which is the exact bug
> class agnos's roadmap tracks. Filed here rather than as a second ticket because it is
> the same work in the same file, on the same standing rule (an agnos↔cyrius syscall is
> recorded on **both** sides). Design owner: agnos —
> [`2026-08-26-syscall-100-icmp-echo-ex.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-26-syscall-100-icmp-echo-ex.md).
> **What to add** is in § Additions for #100 at the bottom.



**Status:** ✅ **Built** 2026-08-24 (cyrius side).
**Repo owning the design:** agnos — `docs/development/issues/2026-08-24-syscall-99-proclist.md`.
**Cross-repo:** filed in **both** repos.
**Severity:** Low for cyrius — two additions, no behaviour change to any existing target.
**Precedent:** identical in shape to `#98 ptrscan` (6.5.13) and `#97 chan_op` (6.5.8).

---

## What was added

In `lib/syscalls_x86_64_agnos.cyr`:

1. `SYS_PROCLIST = 99;` in the agnos `Sys` enum.
2. `fn sys_proclist(buf, max)` — a thin wrapper beside `sys_ptrscan`, same shape.

Contract (kernel side; agnos owns it):

```
proclist(buf, max) -> records written, -1 on a bad user range or max < 1
```

Record, 64 B little-endian, one per live slot:

| off | type | field |
|---|---|---|
| +0 | u64 | `pid` |
| +8 | u64 | `state` — 1 ready · 2 running · 3 claiming (0 dead is skipped) |
| +16 | u64 | `ppid` — 0 = init |
| +24 | u8[32] | `name` — NUL-terminated basename, recorded by the ELF loader |
| +56 | u64 | `reserved` — always 0 today |

---

## Why the number is `#99`

Verified mechanically on the agnos side, not assumed:

- Every `num == N` dispatch arm in `agnos/kernel/core/syscall.cyr` covers 0-95 and 97-98.
  `99` had none (`grep -c '(num == 99)'` returned 0 before this edit).
- ⚠ **`#96` looks free and is reserved** for `fork` by the operator ruling of 2026-08-05
  (`agnos/docs/development/roadmap.md`). Not taken.
- ⚠ **`#44` looks free to that grep and is not** — `sched_yield` dispatches in the ring-3
  entry stub (`kernel/arch/x86_64/syscall_hw.cyr`), not in `ksyscall`.
- The `#98` ticket already recorded *"Next free is `#99`"* the last time this was adjudicated.

---

## Why it exists at all

AGNOS had **no enumeration primitive of any kind**. The ring-3 surface offered
`getpid`/`spawn`/`waitpid`/`kill` and nothing that could answer *"what is running?"*, and
there is no procfs. So a system monitor was not merely degraded on AGNOS, it was
impossible: chakshu's `--agnos` build rendered its column header and zero rows, which is
what blocked its v1.0 *"ship as the AGNOS default monitor"* milestone.

Every field the record exposes already existed in the kernel (`proc_table`, `proc_ppid`).
None of it was reachable from ring 3. The one genuinely new piece of kernel state is the
per-process **name** — `struct Process` is pure register state and `proc_create_user` never
saw a path, so a process's only identity was its pid. agnos 1.56.47 records the basename in
`proc_names[]` at ELF load, the one point where a path and a pid are both in hand.

---

## ⚠ Guarding — this is the part consumers get wrong

A kernel older than 1.56.47 has no `#99` arm. **Treat a negative return as "this kernel
cannot enumerate" and say so**, rather than rendering an empty table. "No processes" and
"this kernel cannot tell me about processes" are different facts, and a monitor that
conflates them reports a lie in the quieter direction.

Consumers must also not hard-code `99`. A raw `syscall(99, …)` is exactly the bug class
agnos's `roadmap.md` tracks — raw Linux numbers compiling clean on agnos and dispatching a
different arm (`read(0)` → `exit` was found shipping).

---

## Acceptance

- `SYS_PROCLIST` resolves on the agnos target and is inert elsewhere, matching the other
  agnos-only `SYS_*` constants. ✅
- `sys_proclist` compiles for the agnos target and perturbs no Linux/host build. ✅
- `tests/gates/platform/syscall_wrapper_pass.sh` axis 5 asserts both. ✅
- ⚠ **Not yet done:** exercised end-to-end against a booted 1.56.47 kernel *through the
  wrapper*. chakshu is the first consumer and carries that verification.

---

# Additions for `#100` + `net_config` counters (agnos 1.56.48)

## 1. `SYS_ICMP_ECHO_EX = 100` in the agnos `Sys` enum

Beside `SYS_ICMP_ECHO = 55`. Verified free on the agnos side before minting: no
`num == 100` arm existed, and `#96` remains reserved for `fork`.

## 2. `fn sys_icmp_echo_ex(dst_ip, timeout_ms)`

```
fn sys_icmp_echo_ex(dst_ip, timeout_ms): i64 { return syscall(SYS_ICMP_ECHO_EX, dst_ip, timeout_ms); }
```

Contract (kernel side; agnos owns it):

```
icmp_echo_ex(dst_ip, timeout_ms) -> RTT in ms (>= 0), or -1 (timeout / NIC down)
```

`timeout_ms <= 0` selects the kernel default (~3 s), so it degrades to `#55`. Clamped
to 60 s. Resolution is the 100 Hz tick — the bound rounds **down** to whole ticks with a
floor of 1, so a sub-10 ms request waits one tick, not zero.

⛔ **Do NOT implement this by adding a second argument to `sys_icmp_echo`.** That is
precisely what agnos refused to do kernel-side, and the reason is a *cyrius* fact
measured on 6.5.35: the compiler pops only as many registers as the call site passes, so
unused syscall argument registers carry stale values rather than zero.

```
syscall(39)          ->  pop %rax                              ; rsi/rdx untouched
syscall(39, 1234)    ->  pop %rdx ; pop %rsi ; pop %rdi ; pop %rax
```

Keep `sys_icmp_echo(dst_ip)` at one argument, byte-for-byte as it is. Widening it would
hand the kernel garbage from every existing call site. **Two wrappers, two arities.**

## 3. Four named readers over `net_config`#61

The existing `sys_net_config(field)` already reaches these, but the named peers are what
`sys_net_ip` / `sys_net_gateway` established for fields 0..3, and a consumer should not
be writing bare field numbers:

```
fn sys_net_icmp_tx(): i64           { return syscall(SYS_NET_CONFIG, 4); }
fn sys_net_icmp_rx(): i64           { return syscall(SYS_NET_CONFIG, 5); }
fn sys_net_icmp_replies_sent(): i64 { return syscall(SYS_NET_CONFIG, 6); }
fn sys_net_icmp_timeouts(): i64     { return syscall(SYS_NET_CONFIG, 7); }
```

⚠ Note the semantic stretch, and document it beside them: fields 0..3 are
**configuration** (packed IPv4, `0` = unset), fields 4..7 are **free-running counters**
(monotonic, never reset, `-1` only for an unknown field). A caller must not apply the
"treat `<= 0` as fall back" rule of the config fields to the counters, where `0` is a
legitimate value meaning "nothing sent yet".

## Guarding

A kernel older than **1.56.48** has no `#100` arm and no fields 4..7. `#100` falls
through the dispatch chain; `net_config(4)` returns `-1`. Consumers must treat a negative
return as *"this kernel cannot tell me"* and say so, rather than rendering `0` — the same
lesson `#99` records. "No packets sent" and "this kernel does not count packets" are
different facts.

## Acceptance

- `SYS_ICMP_ECHO_EX` resolves on the agnos target and is inert elsewhere.
- `sys_icmp_echo_ex` compiles for the agnos target; `sys_icmp_echo` keeps arity 1.
- The four `sys_net_icmp_*` readers compile and perturb no other target.
- `tests/gates/platform/syscall_wrapper_pass.sh` asserts the new constant + wrappers,
  as axis 5 does for `proclist`.
- ⭐ **Already exercised kernel-side against a booted 1.56.48** (see the agnos ticket:
  a 200 ms deadline against a black hole returned `-1` after exactly 200 ms, and the
  counters closed as `tx = rx + timeouts`). What is unproven is the path *through these
  wrappers* — `yo` 0.6.1 is the first consumer and carries that.
