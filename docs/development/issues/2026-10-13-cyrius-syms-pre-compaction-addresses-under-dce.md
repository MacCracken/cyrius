# CYRIUS_SYMS writes pre-compaction addresses under CYRIUS_DCE=1 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 infra lane (noted in passing by the 6.7.11 triage of
[the agnos kernel-compaction item](archived/2026-10-10-agnos-kernel-dce-compaction-moves-data.md)).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 infra lane) — never 7.x.
**Discovered:** 2026-10-13.
**Severity:** Medium — the crash-localization map (docs/diagnosis-symbols.md) is wrong for every `CYRIUS_DCE=1`
build that eliminates anything: a RIP maps to the wrong function, and a removed fn is listed at a live fn's address.
agnos is moving its kernel to `CYRIUS_DCE=1`, whose crash reports read this file. No code change; a debugging
artifact only.
**Affects:** x86 `CYRIUS_DCE=1` with whole-program compaction (v6.5.72 on); since 6.7.11 kernel images and
`CYRIUS_WX=0` too.

## Reproduction

```sh
cat > sy.cyr <<'EOF'
fn dead_a(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
CYRIUS_DCE=1 CYRIUS_SYMS=sy.syms build/cycc < sy.cyr > sy.bin; cat sy.syms
objdump -d sy.bin | grep -E 'call|push   %rbp'
```

Output (6.7.11 infra lane):

```
note: 1 unreachable fns (84 bytes NOPed)
note: 84 bytes of dead code eliminated
00000000004000b5 dead_a
0000000000400109 live_fn
000000000040014c main
  4000b5:	55                   	push   %rbp
  4000f8:	55                   	push   %rbp
  400123:	e8 8d ff ff ff       	call   0x4000b5
  40013c:	e8 b7 ff ff ff       	call   0x4000f8
  ...
```

The image has `live_fn` at 0x4000b5 and `main` at 0x4000f8; the map names 0x4000b5 `dead_a` (removed) and puts
`live_fn` and `main` 84 bytes too high — the plain build's addresses, byte for byte.

## Root cause

`_emit_sym_dump(S, sym_base)` (runtime.cyr) is called near the top of the x86 FIXUP, before the patch loop, the DCE
sweep and `wp_compact`, so it reads `_fnt_offsets` before stage 3 shifts them. Moving the call after compaction is
not enough on its own: stage 3 shifts a removed fn's offset to the image of its start (the next surviving fn), so the
dump must also skip (or mark) the removed fns, which needs FIXUP's `live[]` bitmap or the run table.

## Fix direction

Dump after `wp_compact` when it ran, skipping fns whose pre-compaction start lies in a removed run; keep the current
call site when no compaction ran (output unchanged). A gate row: the repro's map equals the image's fn entries
(each listed address is a `push %rbp` the code calls), and a removed fn is absent.
