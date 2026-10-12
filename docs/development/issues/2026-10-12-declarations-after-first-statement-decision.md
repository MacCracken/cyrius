# A declaration after the first top-level statement: `fn` / `const` are taken, `struct` / `enum` / `trait` / `impl` / `union` / `mod` / `use` / `public` / `async fn` are refused, `impl` with a cascade, `async fn` and `union` by a misleading message — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (whether declarations after a top-level statement are valid
cyrius, and which). Probed 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744 B),
x86_64, with each kind first placed before any statement as a control (every control compiles). After the first
statement (`a = 2;`, `syscall(39);`, `if (1) { }` and `while (0) { }` all give the same results), the set is:

- **Compile and run**: `fn` (also generic, `const fn` and `#inline`), `const`, `var`, and an `include` of a file that
  declares none of the refused kinds (`lib/alloc.cyr`).
- **Refused with `unexpected <kw>`**: `struct`, `enum` (also `enum E: stack`), `trait`, `impl T` and
  `impl Tr for T`, `mod`, `use`, and `public` / `pub` (spelled `unexpected pub'/'public`).
- **Refused with an unrelated message**: `async fn` (`expected identifier, got reserved keyword 'fn'`) and `union`
  (`expected ';', got union`).
- **Refused through what it contains**: an `include` of a file that declares a struct, such as
  `include "lib/str.cyr"` (`error:lib/str.cyr:24:1: unexpected struct`).

The two reports this filing merges were both partly right. `fn` compiles; `struct` and `trait` are refused, as the
guide says.
**Placement:** 6.7.13 — repair 3, the decisions (roadmap.md § *6.7.13*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the guide's *Functions* and *Traits* passages re-verified: two
sweep reports disagreed on which kinds compile after a statement).
**Severity:** Low. Every refused shape fails at compile time and nothing is silent. But `impl` cascades into
unrelated errors, `async fn` and `union` are refused with messages that do not say why, and an `include` placed
after code fails inside the included file.
**Affects:** the rule is as old as relaxed ordering (`PARSE_PROG` takes only `fn` after a statement). Measured on the
tree. The `impl` and `struct` refusals give the same first two errors at 6.6.0 and 6.7.9.

## Summary

The guide states the rule today (§ *Functions*: "Relaxed ordering: functions can appear after top-level statements.
A `struct`, `enum`, `trait` or `impl` cannot — they belong to the declaration section, before the first top-level
statement (one after it is `unexpected struct` / `enum` / `trait` / `impl`)"; § *Traits*: "Traits and impls go in
the declaration section … unlike a `fn`, which may also follow statements"). The questions the probe raises are
these:

1. Is the rule itself what cyrius means (declarations in a leading section, `fn` / `const` / `var` anywhere), or may
   every declaration follow statements?
2. Under the current rule, are `async fn` (a function, which the guide's "functions can appear after top-level
   statements" reads as covering), `union`, `mod` / `use`, `public` and an `include` of a declaring file in or out?
   Today all five are out, three of them with messages that do not name the rule.
3. Whatever is out: is the refusal one named error ("a `struct` declaration must come before the first top-level
   statement (line N)") with no cascade? Today each refusal cascades:
   - `impl P { fn get(self): i64 { return self.x; } }` gives `unexpected impl`, then
     `no struct type in scope for 'self'`;
   - `impl Tr for P { .. }` gives `unexpected impl`, `expected '(', got identifier 'P'`, `unexpected var` on the next
     line, and `unexpected end of input` at EOF;
   - `struct Q { y; }` gives `unexpected struct`, `expected '=', got '{'`, `undefined variable 'y'` and
     `undefined variable 'Q'` (`enum` is alike).

⚠ **`async fn` reads as a defect rather than the rule.** `PARSE_PROG`'s relaxed-ordering arm admits it: its test is
`_IS_FN_KW`, which answers 1 for `async` (`src/frontend/parse.cyr:1908`). But the arm consumes only the `const fn`
prefix (`parse.cyr:4912`), not `async` as pass 2's `_tl_scan2_def` does (`src/frontend/parse_fn.cyr:13372`:
`_pending_async = 1`). So `PARSE_FN_DEF` takes `async` for its `fn` token and `fn` for the name. It is listed here
because whether "functions can appear after top-level statements" includes `async fn` is the user's to confirm.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'struct P { x; }\nvar a = 1;\na = 2;\nimpl P { fn get(self): i64 { return self.x; } }\nsyscall(60, a);\n' \
  | build/cycc > /tmp/d1
# error:<source>:4:1: unexpected impl
# error:<source>:4:43: no struct type in scope for 'self'; a '.field' access needs its struct declaration (missing include?)
printf 'struct P { x; }\nvar a = 1;\nimpl P { fn get(self): i64 { return self.x; } }\na = 2;\nvar p: P = P { 5 };\nsyscall(60, p.get() + a);\n' \
  | build/cycc > /tmp/d2 && chmod +x /tmp/d2 && /tmp/d2; echo $?          # 7 (the control: impl before the statement)
printf 'syscall(39);\nfn g(): i64 { return 5; }\nsyscall(60, g());\n' | build/cycc > /tmp/d3 && chmod +x /tmp/d3 && /tmp/d3; echo $?   # 5
printf 'syscall(39);\ninclude "lib/str.cyr"\nsyscall(60, 3);\n' | build/cycc > /tmp/d4
# error:lib/str.cyr:24:1: unexpected struct
printf 'include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/async.cyr"\nsyscall(39);\nasync fn af(): i64 { return 1; }\nsyscall(60, 3);\n' \
  | CYRIUS_ASYNC=1 build/cycc > /tmp/d5
# error:<source>:5:7: expected identifier, got reserved keyword 'fn' (...)
```

## Root cause

Pass 1 (`_tl_pass1` / `_tl_scan1`, `src/frontend/parse_fn.cyr:13226` / `:13246`) registers declarations up to the
first token that is not one, which is the first statement. Two exceptions see the whole file: `_tr_prepass` (every
trait and impl) and `_cst_prepass` (every const). `_prescan_tail` keeps registering fns after it. Pass 2's
`PARSE_PROG` (`src/frontend/parse.cyr:4891`) then takes, after a statement, only directives and
`fn` / `const fn` / `async fn` (`_IS_FN_KW`, `parse.cyr:4910`), with `async`'s prefix left unconsumed (above).
Everything else goes to `PARSE_STMT`, where a declaration keyword is a statement that does not parse (`ERR`'s
`unexpected <tok>`, `src/common/util.cyr:2908`; `union`, token 101, fails one step later as
`expected ';', got union`). The statement resync then re-enters inside the declaration's braces, which is where the
cascades come from.

## Proposed fix

The options, stated neutrally. The user picks; nothing is decided here.

- **(a) Keep the rule** (declarations in the leading section; `fn` / `const` / `var` anywhere), and make every
  out-of-place declaration ONE named error with no cascade. The error names the kind and the first statement's line
  for `struct` / `enum` / `trait` / `impl` / `union` / `mod` / `use` / `public`, and for an `include` of a declaring
  file it names the include. This changes no program that compiles today. Sub-question: is `async fn` after a
  statement taken, like `fn` (the guide's wording), or refused by name?
- **(b) Allow every declaration after statements.** Pass 1 would scan past statements to register structs, enums,
  unions, traits and impls (as `_tr_prepass` / `_cst_prepass` already do for traits, impls and consts), and
  `PARSE_PROG` would take each kind in pass 2. This makes code compile that is refused today, and the guide's rule
  is retired.
- **(c) A subset under (b)**, for example `impl` / `async fn` / an `include` after code, with the rest kept as in (a).

Any answer gets rows (a gate under `tests/gates/diagnostics/`): each kind above after `a = 2;`, `syscall(39);` and
a block statement. For (a), the one named message and an error count of 1 (no cascade). For (b) / (c), a run that
uses the late declaration. Mutation-proven. `PARSE_PROG` and pass 1 are compiled by cybs, so every bite runs the
seed-derive gate.

## Consumer-side workaround

Put every `struct`, `enum`, `union`, `trait`, `impl`, `mod` / `use`, `public` declaration, `async fn`, and every
`include` of a file that declares one, above the first top-level statement. A `fn` and a `const` may follow
statements.
