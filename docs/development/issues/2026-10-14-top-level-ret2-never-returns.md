# A top-level `ret2(a, b)` compiles with no diagnostic and does not return: x86_64 / PE run on past it, aarch64 / cx hang at it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F1: the compiler built from
the unit's tree, 2,189,744 B, and the cross compilers built from it). Unit F1 refuses a top-level `return` (the user's
decision (a), 2026-10-13, `issues/archived/2026-10-12-top-level-return-decision.md`); `ret2` is the same defect through a
different statement, and it still compiles.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
compile today, so the answer is the user's; the precedent is 6.7.11's top-level `return` decision (refused by name,
`return outside a fn body`) and the 6.6.7 context rules (a top-level `break` / `continue` / `defer` / `?` refused).
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F1 (probing the statements that leave a fn the way `return`
does, after the top-level `return` refusal landed).
**Severity:** High — the same class as the top-level `return` issue: a statement compiles with no diagnostic and does
not do what it says on any target (a silent fall-through on x86_64 / PE, a hang on aarch64 / cx).
**Affects:** cycc 5.11.69 (`build/cc5`: the repro exits 9 on x86_64) through the 6.7.11 genfe lane tree (measured on
all four targets); intermediate releases not bisected.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'ret2(6, 7);\nsyscall(60, 9);\n' > /tmp/r2t.cyr
build/cycc < /tmp/r2t.cyr > /tmp/r2t && chmod +x /tmp/r2t && /tmp/r2t; echo $?            # 9 (ret2 passed over)
build/cycc < src/main_aarch64.cyr > /tmp/cc_a64 && chmod +x /tmp/cc_a64
/tmp/cc_a64 < /tmp/r2t.cyr > /tmp/r2ta && chmod +x /tmp/r2ta
timeout 5 qemu-aarch64 /tmp/r2ta; echo $?                                                    # 124 (spins at ret2)
```

| program (top level) | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (cycc_win, wine) |
|---|---|---|---|---|
| `ret2(6, 7); syscall(60, 9);` | 9 | hangs (124) | hangs (124) | 9 |
| `ret2(6, 7);` | 6 | hangs (124) | hangs (124) | 6 |
| `var a = 1; if (a == 1) { ret2(6, 7); } syscall(60, 9);` | 9 | hangs (124) | hangs (124) | 9 |

Expected: refused by name at the `ret2`, once, as a top-level `return` is since 6.7.11 (`return outside a fn body`).
A `ret2` in a fn body, a closure body and an `#inline` fn are unaffected.

## Root cause

`ret2` is a factor builtin (`_PARSE_FACTOR_IMPL`'s `ptyp == 97` arm, `src/frontend/parse_expr.cyr:6196`). After its two
values it calls `_mret_land` (`src/frontend/parse_fn.cyr:898`), which records an `EJMP0` in `rp_vec` as the jump to the
fn's epilogue. Only a fn's end patches `rp_vec`, over the range that fn owns (`_rp_patch_here`, from `_rp_base`), so a
top-level entry is never patched and keeps displacement 0: `jmp +0` on x86_64 / PE (execution falls into the next
statement), a branch to itself on aarch64 / cx. This is the top-level `return` defect exactly; unit F1's
`_ret_toplevel` (`src/frontend/parse.cyr`, beside `_PARSE_DEFER`) guards PARSE_RETURN only, and `ret2` never reaches
PARSE_RETURN.

## Proposed fix

If the user extends the `return` decision to it: refuse `ret2` when `GINFN(S) != 1` in the `ptyp == 97` arm, by name
(for example `ret2 outside a fn body`), consuming its argument list so the stream stays in sync, and never recording the
`EJMP0`. Rows on x86_64, aarch64 (qemu, `timeout 5`), cx (cxvm, `timeout 5`) and PE (wine) beside
`tests/gates/frontend/toplevel_return_checked.sh`'s, with a mutation (the GINFN test dropped → the hang rows RED).

## Consumer-side workaround

End a program with `syscall(60, v);`, or put the two-value return in a fn.
