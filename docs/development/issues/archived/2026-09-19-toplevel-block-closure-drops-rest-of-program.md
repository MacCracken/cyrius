# A block-bodied closure as the FIRST top-level statement silently drops the rest of the program — FIXED

**Status:** ✅ **FIXED in 6.6.6 (bite 3)** — pre-existing (identical with the installed 6.6.4 compiler); found by the review of
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


---

## Resolution (6.6.6, bite 3)

**Root cause — neither of the two files this filing named, and not a first-statement
condition.** A `var` in the DECLARATION ZONE (anywhere before the first top-level statement, not
only the first line) is registered by pass 1 (`PARSE_GVAR_REG`) and stepped over by pass 2 (the
`var` arm of each fork's top-level loop); its initializer is compiled later by `EMIT_GVAR_INITS`.
Both passes found the end of the declaration by scanning to the FIRST `;` — and a block-bodied
closure carries one inside its body. Both stopped mid-closure, at its `}`, which ends every
top-level loop: pass 1 registered nothing after the declaration and pass 2 handed `PARSE_PROG` a
`}`, so everything below was dropped. Nothing in `parse_expr.cyr`'s closure literal is involved —
it is never reached by either pass.

**Fix.** One shared skip, `_skip_gvar_decl` (`src/frontend/parse_decl.cyr`), that ends at the first
`;` outside every `{ }`; called from `PARSE_GVAR_REG` (its plain arm and its destructure arm) and
from the pass-2 `var` arm of all SEVEN `src/main*.cyr` forks. Only BRACE depth counts — a `;`
inside parens alone is never valid, and counting parens would make a malformed `var x = f(1;`
swallow the rest of the file (pinned as row M of the gate).

**Gates.** `tests/tcyr/crossos/toplevel_block_closure.tcyr` (15 assertions, real hardware via the
release gate — the only leg that reaches Mach-O) and
`tests/gates/frontend/toplevel_decl_block_closure.sh` (registered in `scripts/check.sh`: 7 rows x
host/cx/aarch64-qemu + 3 under wine, each against a CONTROL that routes the same declarations
through `PARSE_PROG`, plus a malformed-declaration guard and a static 7-fork parity axis).
Mutation-proven six ways; ledger in the gate header.

## Corrections to this filing

- **"Only the FIRST-statement position fails"** — no. ANY declaration-zone `var` fails: measured on
  the 6.6.5 compiler, `var a = 1;` before the same closure still exits 186, and a `fn` before it
  exits 234. What the filing's third row actually shows is that a top-level STATEMENT before the
  closure moves the declaration onto the `PARSE_PROG` path, which was always correct.
- **"Affects … together with the closure literal in `src/frontend/parse_expr.cyr`"** — the closure
  literal is not involved: neither pass reaches it. Any initializer carrying a `;` inside a brace
  block hits this, and a block-bodied closure is the only such form the language has today.
- **"the pre-statement global registration (`PARSE_GVAR_REG` vs the `PARSE_PROG` path — see the
  v6.6.4 `_GVAR_VIS` note)"** — the two paths are real, but visibility stamping has nothing to do
  with it; the defect is the token skip both the pass-1 and pass-2 declaration-zone paths use.
- **Acceptance asked for the tcyr in `tests/tcyr/lang/`; it is in `tests/tcyr/crossos/`.** The same
  acceptance asks for "every fork (x86, aarch64, PE, Mach-O, cx)", and only the `crossos/`
  directory is run on real ecb / ach / cass / pi by the release gate. `lang/` would have tested
  x86_64 Linux alone. The host-side cx / aarch64 / PE legs are in the shell gate.
- The filing's disassembly reading ("the exit status is the closure's ADDRESS") is correct, and is
  the reason the defect is silent: the program exits with the last global's value.
