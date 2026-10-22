# Diagnostics print the compiler's internal position or name: columns past an in-line expansion are the expanded line's, an undefined name's caret sits on the token after it, and a generic instance is named by its mangled table name (`B$i32`) — RESOLVED

> ✅ **RESOLVED in v6.7.17** (fed lane, unit FD1, `471eab165` + `a72858b60` (P1), `e81944b32` + `b83651bbf` + `8ff8d28ef` (P2, D34), `7908bbfea` (P3), `8f3fad73b`, review fixes `b32f07b2a`, `852029294`, `bb53ea074`; D34, "Point at the name"): a struct is named as the source spells it — a generic instance as `B<i32>`, never the minted `B$i32`, in every refusal and every backend's undefined-function warning; an undefined name is reported at the name with the caret under it, not at the token after it; a diagnostic past an in-line expansion (`#derive`, a macro) reports the source column and shows the source line. Met: an undefined `.field` base no longer skips the next statement; four struct-return refusals show their excerpt. Rows: dx_diag_format.sh MN1-MN20, CR1-CR12, EX1-EX4, XM1-XM11; in_sync_refusal_next_statement.sh B13 / B14. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — three repairs of a day or more each (row 2 also a decision: the guide's own example shows
today's caret); the f16 lane stopped on all three.
**Placement:** 6.7.17 — the cleanup of the remaining issues (fed lane, wave 2, unit FD1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D34 — Point at the name.
**Discovered:** the f16 lane — unit FF5 (expansion columns), unit FF6 (the undefined-name caret; the mangled name). The
s16 lane's SZ3 met the caret too and left it as a documented convention.
**Severity:** Low — where a diagnostic points and what it calls a type; nothing that compiles changes.
**Kind:** repair (rows 1 and 3); decision then repair (row 2).

## Summary

Three diagnostics report what the compiler holds rather than what the source says: a column counted on the line after
`#derive` / a macro expanded it, the cursor's position (the token after a name) rather than the name's, and a generic
instance's table name with its `$` mangling rather than `B<i32>` as written.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64
(the shared frontend).

**1. Columns past an in-line expansion:**

```cyrius
#derive(accessors)
struct Q { y; } var w = zz;
syscall(60, 0);
```

```
error:<source>:2:258: undefined variable 'zz' (missing include or enum?)
    ...n Q_set_y(p, v) { store64(p + 0, v); return 0; }  var w = zz;
                                                                   ^
```

(the column of the expanded line: in the source the `;` after `zz` — where this diagnostic's caret goes, row 2 — is
column 27; the excerpt shows the generated fns instead of the source line.)

```cyrius
#define ADD(a, b) ((a) + (b) + (a) + (b))
var x = ADD(1, 2) + zz;
syscall(60, 0);
```

```
error:<source>:2:39: undefined variable 'zz' (missing include or enum?)
    var x = ((1) + ( 2) + (1) + ( 2)) + zz;
                                          ^
```

(in the source, the `;` after `zz` is column 23.)

**2. The undefined-name caret is on the next token:**

```cyrius
fn main(): i64 { return zq + 1; }
syscall(60, main());
```

`error:<source>:1:28: undefined variable 'zq'` — column 28 is the `+` (`zq` is at 25); `return zz;` reports 1:27, the `;`.
The guide's block-scope example shows the same convention (`error:<source>:5:14: undefined variable 't'` with the caret
under `syscall(60, t);`'s `)`), and hundreds of gate rows pin these columns.

**3. A generic instance named by its table name:**

```cyrius
struct B<T> { v: T; }
fn main(): i64 { var x: B<i32>; x.zq = 1; return 0; }
syscall(60, main());
```

`error:<source>:2:38: unknown field 'zq' on struct 'B$i32'`. The f16 lane counted 33 diagnostics that print a struct by
its table name; `_fsn_one` already spells `B<i32>`.

## Repair plan

1. **Expansion columns** — a column map across PP_PASS / PP_IFDEF_PASS / PP_MACRO_PASS (each expansion records where
   its source span starts and how long it was), read by `_err_col`, plus a reconstructed excerpt: the original line is
   not kept after expansion, so the excerpt needs the source text or the map's inverse. `_err_col` today assumes the
   expanded column is the source column.
2. **The undefined-name caret** — the decision first: keep the documented convention (the guide's example stays), or
   point at the name (ERR_UNDEF's every position; the guide's example and every pinning gate row re-derived — a sweep of
   a day or more).
3. **Mangled names** — route the 33 sites through `_fsn_one`, each with a row, and give each an ERR_IDENT dedupe key
   that does not move with GNPOS (so an instance's refusal still prints once).

Rows: each repro points at / names the source's own spelling on x86_64, aarch64, cx and PE.
