# cyrlint's overrun rule sizes only a fn-local `var a[N]` with a LITERAL N — a const / enum / expression size and a top-level bare array are never checked — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-21: cyrlint sizes N as an integer literal, a `const NAME = <literal>;`, an enum constant with a literal value (bare or `E.X`), or `+ - *` over those, and checks a top-level bare `var g[N]` at N × 8 bytes in every fn whose local or parameter does not shadow it; the warning names the spelling and its value. The repro's gap.cyr lints `7 warnings` where it said 0 — SEVEN, not the filed six: the filing counted the a / b / c accesses, and `store64(&g + 16, 4)` is the seventh by its own reasoning. Tree census 0 hits. No decision needed. Rows: `cyrlint_overrun_and_write_length.sh` axes K and G; mutations m10–m19 RED. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 tools lane (l6711-tools, unit T2), with
`programs/cyrlint.cyr` built from that tree (the commit that adds the overrun rule for
`2026-10-08-cyrlint-array-overrun-and-write-length-checks.md`). That issue's filed surface is a bare LOCAL
`var a[N]` and a constant `&a + K`; the two shapes below lie outside it, so they are filed, not widened in.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Severity:** Low — preventive lint; no in-tree site is known (the 6.7.11 census found none of either shape
with an overrun, but it could not look).
**Affects:** cyrlint from 6.7.11 (the rule's first release).

## Reproduction

`gap.cyr`:

```
const BUF = 8;
enum Sz { SMALL = 8; }
var g[2];
fn f(): i64 {
    var a[BUF];
    var b[Sz.SMALL];
    var c[4 + 4];
    store64(&a + 8, 1);
    store64(&b + 8, 2);
    store64(&c + 8, 3);
    store64(&g + 16, 4);
    return load64(&a + 8) + load64(&b + 8) + load64(&c + 8);
}
var r = f();
syscall(60, 0);
```

```sh
cat programs/cyrlint.cyr | build/cycc > cyrlint && chmod +x cyrlint
./cyrlint gap.cyr          # 0 untracked deferrals / 0 warnings   (rc 0)
cat gap.cyr | build/cycc > gap && chmod +x gap && ./gap; echo $?   # builds (rc 0), runs, exit 0
```

Every one of the six stores / loads is past its array: `a`, `b` and `c` are 8 bytes each (a bare local
`var x[N]` is N bytes rounded up to 8, and N is 8 in all three spellings — the guide: "`N` is any integer
**const expression** (6.7.2)"), so `&x + 8` is the first byte past; `g` is a top-level bare array, `2 * 8 = 16`
bytes ("at top level: `N` **i64 slots**"), so `&g + 16` is the first byte past. Expected: six warnings.

## Root cause

`_ov_decl` (programs/cyrlint.cyr) records a size only when the `[ ]` holds one integer literal (decimal or
`0x`); any other N is recorded as UNKNOWN (it still shadows an outer name, so nothing false fires). The table
is per fn body, so a top-level `var g[N]` is never recorded at all — and its size rule differs (N * 8).

## Proposed fix

(1) Evaluate the size the way the compiler does for the shapes a scanner can see: a `const NAME = <literal>`,
an enum constant (bare or `E.X`) with a literal value, and literal arithmetic — or keep UNKNOWN for anything
else. (2) Record top-level bare arrays at `N * 8` bytes, visible in every fn that does not shadow the name.
Each with rows in `tests/gates/toolchain/cyrlint_overrun_and_write_length.sh`, and a fresh tree census.
