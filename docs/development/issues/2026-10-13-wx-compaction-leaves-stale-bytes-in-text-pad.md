# W^X dead-code compaction leaves stale code bytes in .text's alignment pad — OPEN

**Status:** 🟡 **OPEN** — seen 2026-10-13 on the 6.7.11 infra lane while reading compacted binaries.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13.
**Severity:** Low — the bytes are past the last instruction and never execute; output is merely not clean (a
disassembler shows a stale `ud2` or a stray instruction past the program's exit, which reads like a miscompile when
diagnosing one). Not a vulnerability.
**Affects:** x86 W^X `CYRIUS_DCE=1` with compaction (v6.5.72 on). Since 6.7.11 the kernel / `CYRIUS_WX=0` layouts zero
their pad (`_wp_pad_to`); the W^X path does not.

## Reproduction

```sh
cat > sy.cyr <<'EOF'
fn dead_a(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
CYRIUS_DCE=1 build/cycc < sy.cyr > sy.bin; objdump -d sy.bin | tail -3
```

Output (6.7.11 infra lane):

```
  400180:	0f 05                	syscall
  400182:	00 00                	add    %al,(%rax)
  400184:	c1 58 48 29          	rcrl   $0x29,0x48(%rax)
```

The plain build ends `4001d4: 0f 05 syscall` followed by zeros (`...`): FIXUP's 8-alignment leaves the pad zero.
With `--allow-undef` the stale tail can hold a copy of the `0f 0b 0f 0b` sentinel.

## Root cause

`wp_compact` stage 6 moves the bytes down and sets the code end to the moved length `wp`; FIXUP then rounds it up to
8 (`_cp2 = (GCP + 7) & -8`) without clearing `[wp, _cp2)`, which still holds the pre-compaction bytes at those
offsets.

## Fix direction

Zero `[wp, align8(wp))` before the realign (the kernel / WX=0 path's `_wp_pad_to` already does this for its own end).
It changes only never-executed bytes of `CYRIUS_DCE=1` builds; a row: the bytes between the last instruction and
`.text`'s end are zero.
