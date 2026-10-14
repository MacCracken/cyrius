# A top-level `return` compiles with no diagnostic and does not return: execution continues past it on x86_64 / PE and it hangs on aarch64 / cx — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (is `return` outside a fn body valid cyrius, and if so what does it
do?), over a defect that exists under any answer. Probed 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B) and the cross compilers built from it. `return 5;` as a whole program exits 5 on x86_64,
which is why it looked like a working top-level return. That exit is an accident. On aarch64 (qemu) and cx (cxvm)
the same one-line program never exits: an infinite loop at the `return` (killed by `timeout`, exit 124). On x86_64
and PE (wine), `return 6; syscall(60, 9);` exits 9: the `return` is passed over. The installed 6.6.0, 6.6.20, 6.7.0
and 6.7.9 compilers and `build/cc5` (5.11.69) all exit 9 on x86_64.
**Placement:** 6.7.11 — repair 1, the frontend lane — a newly filed High, from 6.7.13 (pulled in at the open: user, 2026-10-13) — never 7.x. Was: 6.7.13 — repair 3, the decisions (roadmap.md § *6.7.13*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the FAQ re-verification: `docs/guides/faq.md` listed "`return`
outside a function body" as a syntax error; 6.7.9 compiles it, so the line was removed and `docs/doc-health.md`
records that the meaning is the user's call).
**Severity:** High. A statement compiles with no diagnostic and does not do what it says on any target: a silent
fall-through on x86_64 / PE and a hang on aarch64 / cx.
**Affects:** cycc 5.11.69 (`build/cc5`) – the 6.7.10 tree (measured at 5.11.69, 6.6.0, 6.6.20, 6.7.0, 6.7.9 and the
tree on x86_64; the tree on all four targets). Every top-level `return`, with or without a value, inside a top-level
block (`if (..) { return 6; }`) too.

## Summary

Neither the guide nor the CHANGELOG says whether a `return` outside a fn body is valid. The FAQ said it was a syntax
error until the 6.7.9 doc sweep. The compiler accepts it, and what it emits is not a return:

| program (top level) | x86_64 | aarch64 | cx | PE |
|---|---|---|---|---|
| `return 5;` | 5 | hangs | hangs | 5 |
| `return 6; syscall(60, 9);` | 9 | hangs | hangs | 9 |
| `var a = 1; a = 2; return a + 3;` | 2 | — | — | 2 |
| `var a = 1; return 4;` | 1 | — | — | — |
| `var a = 1; if (a == 1) { return 6; } syscall(60, 9);` | 9 | hangs | hangs | 9 |
| `return 5; var a = 7; syscall(60, a);` | 7 | — | — | — |
| `var a = 1; return;` / `return (1, 2);` | 1 / 1 | — | — | — |

("—": not run on that target. The defect is in the frontend's jump, so the x86_64 column stands for PE and the
aarch64 column for cx.)

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'return 6;\nsyscall(60, 9);\n' > /tmp/r69.cyr
cat /tmp/r69.cyr | build/cycc > /tmp/r69 && chmod +x /tmp/r69 && /tmp/r69; echo $?             # 9 (the return is passed over)
cat src/main_aarch64.cyr | build/cycc > /tmp/cc_a64 && chmod +x /tmp/cc_a64
cat /tmp/r69.cyr | /tmp/cc_a64 > /tmp/r69a && chmod +x /tmp/r69a
timeout 5 qemu-aarch64 /tmp/r69a; echo $?                                                         # 124 (spins at the return)
```

`objdump -D -b binary -m i386:x86-64` of `var a = 1; a = 2; return a + 3;` shows the `return` as the expression, then
`e9 00 00 00 00` (`jmp` with displacement 0, which falls into the next instruction), then the program's end, which
exits with `a` (2).

## Root cause

`PARSE_RETURN` (`src/frontend/parse_fn.cyr:907`) has no top-level arm. Its tail evaluates the value and records an
`EJMP0` in `rp_vec` as the jump to the fn's return landing (`:1348–1349`, and `:1338` for a bare `return;`). Only a
fn's end patches `rp_vec`, over the range that fn owns (`_rp_patch_here`, `src/frontend/parse.cyr:1607`, from
`_rp_base`). A fn defined after the `return` starts its range at the current length (`parse.cyr:1526`), so a
top-level entry is below every fn's range and is never patched. The displacement stays 0:

- x86_64 / PE: `jmp +0`, so execution falls through to the next statement;
- aarch64: `b .`, a branch to itself;
- cx: the same self-jump, so cxvm spins.

## Proposed fix

The options, stated neutrally. The user picks; nothing is decided here. Each one ends the fall-through and the hang.

- **(a) Refuse a top-level `return` by name** ("`return` outside a fn body"), at top level and inside a top-level
  block, as the FAQ described. Code that compiles today stops compiling (all of it is broken today, on at least two
  targets).
- **(b) A top-level `return v;` ends the program with exit status `v`** (and `return;` with 0), as if
  `syscall(60, v)`. The emit is a jump to one top-level landing that every fork's program end shares, or the exit
  itself. The guide documents it, and so does the FAQ. (A top-level `defer` is already refused, "defer only allowed
  inside a function", so there is no cleanup to order.)
- **(c) Something else the user names**, for example `return` valid only as a program's last statement.

Any answer gets rows on x86_64, aarch64 (qemu, then pi), cx (cxvm) and PE (wine, then cass), mutation-proven: the
table above. Under (a), one error naming the `return`. Under (b), each program's exit status is its `return`'s value,
and the code after it does not run. The aarch64 and cx rows also need a `timeout`, so a reintroduced self-jump fails
instead of hanging the gate. `PARSE_RETURN` sits near cybs's per-fn reference ceiling, so the arm goes in a small
fn and every bite runs the seed-derive gate.

## Consumer-side workaround

End a program with `syscall(60, v);` (or let it fall off the end) rather than a top-level `return`. Put an early exit
in a `fn main()` and `return` from that.
