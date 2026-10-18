# W^X dead-code compaction leaves stale code bytes in .text's alignment pad — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-3, `458fb7cdc` (no decision needed: bytes that never run): FIXUP's post-compaction block zeroes `.text`'s 8-byte pad (`_wp_pad_to`, as the kernel / `CYRIUS_WX=0` layouts have since 6.7.11) instead of only realigning — the fix direction. The filed `sy.cyr` under `CYRIUS_DCE=1` ends `0f 05 syscall` followed by zeros to `.text`'s end (was `00 00` / `c1 58 48 29`), exit 0. Found in passing and fixed in the same bite: the `CYRIUS_IR=3` compaction left the same stale pad (e508fac17), and its `wp-compact:` note always said "(0 runs" (8b487fdef). Rows: `dce_eliminates.sh` axis 5 (`sy.cyr`, W^X and `CYRIUS_WX=0`: the last nonzero byte exactly ELIM bytes below the plain build's, `.text` ending at the next 8-byte boundary, exit 0; mutation, the realign without the zeroing, RED); `wp_compact_registry_caps.sh` axes 6 (the IR=3 pad) and 2 (a nonzero run count). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — seen 2026-10-13 on the 6.7.11 infra lane while reading compacted binaries.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
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
