# cybs reports an indexed store to an undefined name (`zz[1] = 5;`) as the syntax-error class, never naming `zz` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 infra lane (cybs.cyr @ 4e5d1f90, seed-assembled, 22,320 B).
The routing predates 6.7.11: the slot-open cybs (0f733aea) printed a bare `syntax error` for the same input.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 infra lane's review of the cybs bare-syntax-error item
(`issues/archived/2026-10-08-cybs-bare-syntax-error-no-location.md`, decision A). That item's table and its undefined-name rows
(`var x = nosuch(1);`, `zz = 5;`, `a = zz;`, `&zz`) do not include a subscript, so this shape is beyond its filed
surface.
**Severity:** Low — a misleading diagnostic (right line, wrong class) on the developer's own source to the bootstrap
compiler; cybs only compiles `src/` and `bootstrap/asm.cyr` (a bug, not a vulnerability).
**Affects:** `bootstrap/cybs.cyr` (not bisected).

## Summary

For `zz[1] = 5;` in a fn body, with `zz` never declared, cybs prints the generic class message — "syntax error, or a
construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=)"
— with the right line, but never names `zz`. The read form `var a = zz[1];` does name it ("undefined variable or
function (cybs has no const): zz"), and cycc names it in both (`undefined variable 'zz'`).

A second, related gap the probe exposes: cybs has no subscript at all, read or store, even on a DECLARED array
(`var zz[16];` then `zz[1] = 5;` or `var a = zz[1];` gives the class message too). That message's list of what cybs
lacks does not mention `x[i]`, so a reader of it cannot tell that the subscript is the unsupported construct.

## Reproduction

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
printf 'fn main() {\n    var a = 1;\n    zz[1] = 5;\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > zi.cyr
printf 'fn main() {\n    var a = zz[1];\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > zj.cyr
printf 'var zz[16];\nfn main() {\n    var a = 1;\n    zz[1] = 5;\n    return a;\n}\nvar r = main();\nsyscall(60, r);\n' > zd.cyr
for t in zi zj zd; do ./cybs < $t.cyr > $t.bin 2> $t.err; echo "$t rc=$? out=$(wc -c < $t.bin)B $(tr '\n' '|' < $t.err)"; done
build/cycc < zi.cyr > /dev/null
```

Output:

```
zi rc=1 out=0B cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at:     zz[1] = 5;|
zj rc=1 out=0B cybs: undefined variable or function (cybs has no const): zz, at:     var a = zz[1];|
zd rc=1 out=0B cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at:     zz[1] = 5;|
error:<source>:3:7: undefined variable 'zz' (missing include or enum?)
        zz[1] = 5;
          ^
```

The slot-open cybs: `zi` -> `syntax error`, `zj` -> `undefined variable`, both rc 1.

Expected: `zi` names `zz` as the read form does (`cybs: undefined variable or function (cybs has no const): zz, at:
    zz[1] = 5;`), rc 1, nothing written.

## Root cause

`parse_assign_stmt` (`bootstrap/cybs.cyr`) takes the identifier's name into r8, consumes it, and dispatches on the
NEXT token (`(` call, `=` assign, `+ - * & | ^` compound) before it ever resolves the name; any other token — here
`[` — jumps straight to `parse_err`. The name is looked up only inside the `=` / compound arms (`find_var_index` ->
`find_var_undef`, which names it). The read form names it because `parse_expr` resolves the identifier before it
sees the `[`.

Fix shape: in `parse_assign_stmt`'s fall-through to `parse_err`, resolve r8 first (local, then global, then fn) and
route an unknown name to `find_var_undef`, so the undefined-name message wins over the class message; a known name
followed by `[` keeps the class message. Whether the class message's list should also name `x[i]` (cybs has no
subscript) is part of the same fix's wording. Gate rows: `zi` names `zz` with its line, rc 1, nothing written; `zd`
keeps the class message (`tests/gates/toolchain/cybs_diagnostics_named.sh`); labels / input / code within row S's
caps; seed-derive and the closure unchanged.
