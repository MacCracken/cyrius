# Diagnostic cascades after a 6.7.7 refusal: tuples, `: stack` pair stores, u128 compound ops and D19 — OPEN

**Status:** 🟡 **OPEN** — all eight shapes below reproduced 2026-10-09 against the merged 6.7.7 tip (`cycc_merged`,
1,916,288 B; tree @ 06bd8981), each with `cycc_merged < f.cyr > /dev/null` from the tree root. Outputs are quoted
with the excerpt lines dropped. Shape 5's swallow also reproduces on 6.7.6's `build/cycc` with `x = mk(7);` (the
6.6.0 refusal).
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
These are 6.7.7 follow-ons, in the code 6.7.10's lanes own: the tuple and pair refusals, the B6 marshaller, operator
dispatch. The older generic cascades stay in
[2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md](2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md),
which is placed in 6.7.12.
**Discovered:** the 6.7.7 B4 (tuples) and B6 (default + named arguments) lanes and their review rounds, reported out
of scope; filed 2026-10-09.
**Severity:** Low. Every input is invalid and is refused, and no binary is written. The extra lines mislead, and
shape 5 loses the next statement's real error until the first is fixed.
**Affects:** the merged 6.7.7 tip (shapes 1–4 and 6–8 are new code). Shape 5 since 6.6.0 for `x = f();` /
`store64(.., f())`, widened by 6.7.7 to the four T5b stores.

## Summary

Each refusal below is correct. The bug is what follows it: a second error for the same mistake, a warning about a
type the refusal just rejected, an "undefined variable" for a name whose declaration was refused, or a real error
that is never reported. One mistake should give one error, at the place that is wrong.

## Reproduction

1. **`t == u` with two tuple operands: two errors.**
   ```cyr
   fn main(): i64 {
       var t = (1, 2);
       var u = (3, 4);
       if (t == u) { return 1; }
       return 0;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:4:9: tuple 't' used as a value - take an element (`t.0`) or copy it whole into a tuple
   error:<source>:4:14: tuple 'u' used as a value - take an element (`t.0`) or copy it whole into a tuple
   ```

2. **`t = u;` inside a closure, both captured tuples: two errors, and the second is at the `;`.**
   ```cyr
   include "lib/alloc.cyr"
   fn main(): i64 {
       alloc_init();
       var t = (1, 2);
       var u = (3, 4);
       var f = || { t = u; return 0; };
       return 0;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:6:22: tuple 'u' used as a value - take an element (`t.0`) or copy it whole into a tuple
   error:<source>:6:23: undefined variable 't'
   ```
   The struct version (`s = q;` with two captured `P`s) reports only "undefined variable 's'", the existing
   captured-assignment rule. The tuple form adds the RHS error because the failed LHS lookup sends `u` down the plain
   value path.

3. **A stray "assigning non-pointer to typed pointer" after a tuple refusal.**
   ```cyr
   fn main(): i64 {
       var t = (1, 2);
       t = 5;
       var p: *(i64, i64) = 0;
       return 0;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:3:9: cannot assign a value that is not a tuple to tuple 't'
   warning:<source>:3:10: assigning non-pointer to typed pointer
   error:<source>:4:13: a tuple type cannot be a pointer target `*( .. )`
   warning:<source>:4:27: assigning non-pointer to typed pointer
   ```
   The line-3 warning is wrong in kind: `t` is a tuple, not a pointer. On line 4, `var p: *i64 = 0;` gets the same
   warning on its own, but here it is about a type the line before it just refused.

4. **A refused tuple literal leaves its name undeclared, so every later use cascades.**
   In a fn, an un-annotated literal refused for its shape (an empty element, a trailing comma, more than 256
   elements) declares nothing:
   ```cyr
   fn main(): i64 {
       var t = (1, 2, );
       var k = t.0;
       return k;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:2:18: a trailing comma in a tuple literal
   error:<source>:3:16: undefined variable 't'
   error:<source>:3:16: no struct type in scope for 't'; a '.field' access needs its struct declaration (missing include?)
   ```
   At top level, a literal of more than 256 elements leaves `G` an 8-byte non-tuple global. In the declaration zone
   the cascade even prints BEFORE the refusal:
   ```cyr
   var G = (1, 2, 3, /* … 257 elements … */ 257);
   fn main(): i64 { return G.0; }
   syscall(60, main());
   ```
   ```
   error:<source>:2:28: no struct type in scope for 'G'; a '.field' access needs its struct declaration (missing include?)
   error:<source>:1:9: a tuple literal has at most 256 elements
   ```
   The float-element refusal (`var t = (1, 2.5);`) and a wrong arity under a tuple annotation do declare the name,
   and their later uses are quiet.

5. **A `: stack` pair refusal swallows the NEXT statement, error and all.**
   ```cyr
   enum SR: stack { SOk(v); SErr(e); }
   fn mk(x) { return SOk(x); }
   struct H { n; m; }
   fn main(): i64 {
       var h: H;
       var x = 0;
       h.n = mk(7);
       x = nosuch;
       h.m = mk(8);
       return h.n;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:7:11: a `: stack` enum returns two values — bind both: `var tag, val = f();`
   error:<source>:9:11: a `: stack` enum returns two values — bind both: `var tag, val = f();`
   ```
   Line 8's `undefined variable 'nosuch'` is never reported, because the statement was skipped. With two refusals on
   consecutive lines, the second one is lost the same way. On 6.7.6, `x = mk(7);` followed by `y = nosuch;` loses
   the second error identically.

6. **A refused u128 compound operator also reports "bind both".**
   ```cyr
   enum SR: stack { SOk(v); SErr(e); }
   fn mk(x) { return SOk(x); }
   fn main(): i64 {
       var b: u128 = 0;
       b *= mk(7);
       return 0;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:5:7: compound assignment `*=` to u128 'b' is refused - it is not implemented for u128 yet (only `+=` and `-=` are; lib/bayan.cyr's bayan_u128_* helpers cover the rest)
   error:<source>:5:10: a `: stack` enum returns two values — bind both: `var tag, val = f();`
   ```
   The same happens for every refused `OP=` (`/=`, `<<=`, `&=`, …). `b += mk(7);` correctly gives only the pair
   error.

7. **D19 is reported at every operator use and never at the definition, and after a definition refusal it reports
   again at each use.**
   ```cyr
   struct V2 { x; y; }
   trait Add { fn add(self, b); }
   impl Add for V2 { fn add(self, b, k = 1): i64 { return k; } }
   fn main(): i64 {
       var a = V2 { 1, 2 };
       var b = V2 { 3, 4 };
       var c = a + b;
       var d = a + b;
       return c + d;
   }
   syscall(60, main());
   ```
   ```
   error:<source>:3:37: 'add' implements trait 'Add': its parameters take no defaults (the trait's signature is the contract)
   error:<source>:3:19: method 'add' takes a different number of parameters than its declaration in trait 'Add'
   error:<source>:7: operator fn 'V2_add' declares a parameter default: an operator passes exactly its two operands
   error:<source>:8: operator fn 'V2_add' declares a parameter default: an operator passes exactly its two operands
   ```
   That is four errors for one `k = 1`. A plain `fn V2_add(a, b, k = 1)` gives one D19 line per `a + b` (two
   identical lines when both uses share a line), each without a column, and none at the definition, which is what is
   wrong.

8. **A declaration-zone tuple global copied from a tuple declared below it: two errors, and the generic one first.**
   ```cyr
   var A: (i64, i64) = B;
   var B = (1, 2);
   fn main(): i64 { return A.0; }
   syscall(60, main());
   ```
   ```
   error:<source>:1:8: cannot initialize tuple 'A' with a value that is not a tuple
   error:<source>:1:21: cannot copy-init 'A' from a global declared below it (declare the source first): 'B'
   ```
   The struct form (`var A: Pt = B; var B = Pt { 1, 2 };`) gives only the second line, which names the real fix.

## Root cause

1. `_tup_rchk` (`src/frontend/parse_expr.cyr:1891`) reports through `_tup_err` (`parse_types.cyr:351`), which reports
   "once per TOKEN, in sync" and by design leaves the panic latch alone. So each operand of one expression is its own
   report.
2. `t` is a capture, so the LHS lookup fails and PARSE_STMT's plain assignment parses the RHS as a value. `_tup_rchk`
   fires on `u`, then the FINDVAR-miss arm (`parse.cyr:4744`–`4765`) prints "undefined variable" with the cursor already
   at the `;`.
3. `_tup_asg_chk` (`parse.cyr:3312`) reports, but the plain-assignment path still runs its pointer check: the tuple
   local's SLTYPE is `0 - sid`, so `lt < 0` → `WARN(.., "assigning non-pointer to typed pointer")`
   (`parse.cyr:4732`–`4733`). For `*( .. )`, `_ptr_annot` (`parse_types.cyr:743`) refuses but still returns a pointer
   step, so PARSE_VAR's `pscale > 0` check (`parse_decl.cyr:6676`–`6677`) warns about the `0`.
4. `_tup_var_lit` (`parse_decl.cyr:2773`): with `n == 0` (a shape refusal) and an un-annotated literal it returns
   `_tup_lit_skip(S, st, 5)` = 1 ("declared") and declares nothing. That contradicts `_tup_var`'s own comment ("A
   refused literal still lets the name be declared, so its later uses do not cascade", `:2757`–`2763`). At top level,
   pass 1's `_tup_gci_in` (`parse_decl.cyr:5429`, `if (n > 256) { return 0; }`) registers a > 256 literal as a plain
   8-byte global.
5. `_refuse_lossy_pair` / `_refuse_single_pair_bind` (`parse.cyr:853` / `:871`) report through `ERR_MSG`
   (`util.cyr:3010`), which sets `_panic = 1`, but the statement is parsed on in sync and ends at its own `;`. PARSE_STMT's
   wrapper then sees the latch (`parse.cyr:4206`, `if (_panic == 1) { _sync_skip(S); }`), and `_sync_skip`
   (`util.cyr:2683`) consumes the NEXT statement through its `;`. It stops early only at a statement keyword, which is
   why a following `var` / `return` line survives. The same left-set latch, reached from pass 1's const evaluation,
   is filed separately as
   [2026-10-09-const-sweep-swallows-later-const-errors.md](2026-10-09-const-sweep-swallows-later-const-errors.md).
   It is a different site with the same mechanism, so fix the two together.
6. `_w128_cop` (`parse_expr.cyr:2067`) refuses a non-`+=` / `-=` operator through `_w128_refuse_at`, which does not set
   the latch, and returns 0. `_asg_compound_op` (`parse.cyr:3158`) then runs `_refuse_lossy_pair` on the same RHS.
7. D19 lives in `_pd_arity_mode`'s mode 4 (`parse_fn.cyr:3225`), which runs at each operator dispatch's arity check.
   Nothing checks at the definition, and nothing remembers that a fn was already refused (the trait-impl refusals at
   `parse_fn.cyr:2728` and `:6546` report at the definition, then D19 fires again per use).
8. Pass 1 registers `A` before `B` exists, so the source is not a whole tuple and `A` is not inline. The pointer-mode
   backstop `_tup_ptr_refuse` (`parse_types.cyr:587`) reports R12's generic text at the annotation. The replay's
   `_gci_init` → `_gci_below` (`parse_decl.cyr:5490` / `:5497`) then reports the real cause.

## Proposed fix

Diagnostic only, with no change to what compiles:

- (1) At most one "used as a value" per expression: clear `GESTYPE` / latch per binary expression, or report the
  left operand only.
- (2) Leave a captured tuple's `t = u;` to the captured-assignment error alone: check the LHS before parsing the RHS
  as a value, and put the caret on `t`.
- (3) Skip the pointer warning when the store was refused (`_tup_asg_chk` returned 1), and have `_ptr_annot` return
  0 after a tuple refusal.
- (4) Declare the name after every shape refusal, as `var t: (i64 x n);` with the commas' count, the way the
  annotated arm does. At top level, register a > 256 literal as the 256-cap tuple, or mark it refused so its uses
  stay quiet.
- (5) The pair refusals are reported IN SYNC, so clear `_panic` after reporting (the `_bx_refuse` /
  `parse_types.cyr:237` pattern) instead of leaving it for the statement wrapper. That also covers the 6.6.0
  shapes.
- (6) Return 1 ("handled") from `_w128_cop` after its refusal, skipping the RHS with `_masg_skip`, or latch and
  resync.
- (7) Report D19 once, at the operator fn's definition when it is registered as an operator, and suppress the
  per-use report for a fn already refused. At minimum, report once per fn with a column.
- (8) In pass 1, leave a tuple annotation over a lone name (`_gci_src`-shaped) to the replay, so only `_gci_below`'s
  message prints.

Each needs a gate row asserting the exact error count, for example in `tests/gates/frontend/tuple_checked.sh`,
`stack_enum_lossy_context.sh` and `default_named_args_checked.sh`.
