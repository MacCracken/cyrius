# A block-bodied closure as the FIRST top-level statement silently drops the rest of the program — OPEN

**Status:** 🟡 **OPEN** — pre-existing (identical with the installed 6.6.4 compiler); found by the review of
6.6.5 bite 9 (round 2) while building runtime oracles for cyrlint's init-order rule.
**Placement:** unpinned — 6.x line (parser / codegen). Not parked to 7.x.
**Discovered:** 2026-09-19.
**Severity:** Medium — SILENT. It compiles with no diagnostic; everything after the closure is
missing from the binary, and the program exits with a meaningless status.
**Affects:** the top-level `var` path in `src/frontend/parse_decl.cyr` (`PARSE_VAR`'s global
branch / the pre-statement global registration) together with the closure literal in
`src/frontend/parse_expr.cyr` (`|params| { … }`). Seen on x86_64 Linux; the other forks are
unmeasured.

## Reproduction

```sh
printf 'var f = |x| { return 7; };\nsyscall(1, 1, "hi\\n", 3);\nsyscall(60, 9);\n' \
    | ./build/cycc > /tmp/tl && chmod +x /tmp/tl && /tmp/tl; echo "rc=$?"
# rc=186        (no "hi", and not 9)
```

Measured at 6.6.5 with `build/cycc`, and the first row again with the installed 6.6.4 compiler
(`~/.cyrius/versions/6.6.4/bin/cycc`, same rc 186):

| program | result |
|---|---|
| `var f = \|x\| { return 7; };` then `syscall(1,1,"hi\n",3); syscall(60, 9);` | **rc 186, prints nothing** |
| `var f = \|x\| { var a = 1; return 7; };` then `syscall(60, 9);` | rc 186 |
| a `syscall(1, 1, "a\n", 2);` BEFORE the same closure line | prints `a`, `hi`, rc 9 — correct |
| `fn main(): i64 { return 4; }` before it, `syscall(60, main());` after | rc 4 — correct |
| the expression form `var f = \|x\| x + 1;` then `syscall(60, 7);` | rc 7 — correct |
| the block closure inside a fn body | correct |

The disassembly of the first program ends, right after storing `f`, with
`mov rax, [f]; mov rdi, rax; mov eax, 60; syscall` — the exit status is the closure's ADDRESS
(0x4000ba → 186), and none of the statements after the closure were emitted.

## Cause (to confirm)

Only the FIRST-statement position fails, and parse_decl.cyr documents that a top-level `var`
before the first statement goes through a different registration path than one after it
(`PARSE_GVAR_REG` vs the `PARSE_PROG` path — see the v6.6.4 `_GVAR_VIS` note there). The
block-bodied closure's body (`return 7;` ends it) is the likely point where that path loses
the rest of the token stream. `tests/tcyr/lang/closures.tcyr` keeps every closure inside a fn,
so nothing tests the top-level position.

## Acceptance

- The reproduction prints `hi` and exits 9, on every fork (x86, aarch64, PE, Mach-O, cx).
- A tcyr in `tests/tcyr/lang/` defines a block-bodied closure as the first top-level statement,
  calls it through `fncall1`, and asserts on every statement after it.
- Full tcyr corpus exit codes unchanged; `build/cycc` reproduces itself;
  `sh scripts/seed-derive-cycc.sh` stays machine-derivable.

## Why it was not packed into bite 9

Bite 9 is the cyrlint fix and changes no `src/` file. This is an unrelated compiler defect:
bundling it into bite 9's commit would break the one-change-per-commit rule, and it needs its
own seed-derive, self-host and cross-OS cycle.
