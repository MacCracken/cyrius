# CYRIUS_DCE=1 removes a LIVE generic instance emitted inside a dead instance's code range — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 infra lane, on the slot-open compiler (86592071's
build/cycc) and on the lane's compiler alike. Met while running the `CYRIUS_DCE=1` differential for
[the agnos kernel-compaction item](archived/2026-10-10-agnos-kernel-dce-compaction-moves-data.md): the corpus file
`tests/tcyr/lang/generic_instance_inline_binding.tcyr` passes without the flag and crashes with it.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 infra lane) — never 7.x.
**Discovered:** 2026-10-13.
**Severity:** High — a silent miscompile under an opt-in flag a consumer ships with (agnos is moving to
`CYRIUS_DCE=1` for image room): the program faults or hangs at run time, the build exits 0. Every target is hit:
the x86 compaction (SIGSEGV), the x86 NOP-fill path (`CYRIUS_WX=0` before 6.7.11, SIGSEGV), and the aarch64 NOP-fill
path (a hang). A bug on the developer's own source, not a vulnerability.
**Affects:** `CYRIUS_DCE=1` since v4.4.x's NOP-fill (not bisected); generic instances are emitted inline since
v6.3.10 (`_instantiate_generic_fn`, "jump-over").

## Reproduction

```sh
cat > g.cyr <<'EOF'
fn sv<T>(x: T) { var y: T = 253; return y; }
fn svh<T>(x: T) { return sv<T>(x); }
fn in_svh_i8() { return svh<i8>(1); }
var r = in_svh_i8();
syscall(60, r & 255);
EOF
build/cycc < g.cyr > g0 && chmod +x g0 && ./g0; echo $?                 # 253
CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 build/cycc < g.cyr > g1 && chmod +x g1 && ./g1; echo $?
```

Output, slot-open compiler (6.7.11 slot open, 86592071):

```
note: 3 unreachable fns (344 bytes NOPed)
  dead: sv
  dead: svh
  dead: svh$i8
note: 344 bytes of dead code eliminated
Segmentation fault (core dumped)
139
```

The same source: `CYRIUS_DCE=1 CYRIUS_WX=0` (NOP-fill only on the slot-open compiler) exits 139; the aarch64 cross
compiler with `CYRIUS_DCE=1` (NOP-fill) builds a binary that hangs under `qemu-aarch64` (`timeout 10` -> 124). On the
6.7.11 infra lane's compiler the x86 `CYRIUS_DCE=1` binary dies with SIGILL (132) instead: the call into the removed
code is now the `ud2` sentinel (6.7.11, a surviving call aimed at removed code), which shows exactly where it is.
The corpus file `tests/tcyr/lang/generic_instance_inline_binding.tcyr` shows the same: 18/18 without the flag,
139 (slot open) / 132 (lane) with it.

## Root cause

A generic instance is emitted INLINE, inside the code range of the fn being compiled when it is first needed
(`_instantiate_generic_fn`, parse_fn.cyr: `EJMP0` over the instance, `PARSE_FN_DEF`, `EPATCH`). A forwarder's
instance therefore nests the instance it forwards to. CYRIUS_SYMS on the plain build:

```
000000000040015b in_svh_i8        range [0x40015b, 0x400269)
0000000000400184 svh$i8           range [0x400184, 0x400236)   -- inside in_svh_i8
00000000004001b4 sv$i8            range [0x4001b4, 0x40020d)   -- inside svh$i8
```

`in_svh_i8` inlines `svh<i8>(1)`, so the replayed body calls `sv$i8` directly (`call 0x4001b4` at 0x400244):
`sv$i8` is live and `svh$i8` is dead. FIXUP's sweep (x86/fixup.cyr, the dead-fn walk before `_wpnr_add`) fills /
removes each dead fn's whole `[fn_start, fn_end)`, and `svh$i8`'s range CONTAINS `sv$i8`'s body. The aarch64 FIXUP's
NOP-fill has the same shape. Nothing checks that a dead fn's range holds no live fn.

## Fix direction

In the sweep (both FIXUPs), a dead fn whose `[start, end)` contains the start of a live fn is not filled / removed
(or only its sub-ranges outside the nested live bodies are). A gate row: the repro above under `CYRIUS_DCE=1` on
x86 (W^X and `CYRIUS_WX=0`), aarch64 (qemu-aarch64) and cx exits 253, and the corpus file passes under
`CYRIUS_DCE=1`. A `CYRIUS_DCE=1` sweep of the whole .tcyr corpus would have caught this; today none runs.
