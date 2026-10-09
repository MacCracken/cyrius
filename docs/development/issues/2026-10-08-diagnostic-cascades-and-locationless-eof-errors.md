# Diagnostic cascades: duplicate const-fn scope errors, three errors from one unclosed call, a for-step call's "undefined function", and `error:0:1:` at EOF — OPEN

**Status:** 🟡 **OPEN** — all four reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc` (sources
and output below).
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 review / lane finds (roadmap commit e95f295d, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Low — every input is invalid and is refused; the extra or locationless errors mislead.
**Affects:** cycc 6.7.6 (1 since 6.7.2's `const fn`; the others not bisected).

## Summary / Reproduction

Each case is a fn body inside `fn main() { … } var r = main();` unless shown whole; run `build/cycc < f.cyr >/dev/null`.

1. **A const fn's scope error is reported twice** (with two different carets):
   ```cyr
   const fn f(n) {
       if (n > 0) { var t = 1; }
       return t;
   }
   ```
   ```
   error:<source>:3:12: unknown name 't' in a const context
   error:<source>:3:13: undefined variable 't' (missing include or enum?)
   ```
   Same for any unknown name (`return n + nosuch;`). Expected: one error.

2. **An unclosed call argument list followed by a loop cascades three errors:**
   ```cyr
   fn g(a, b) { return a + b; }
   fn main() {
       var x = 0;
       g(1, 2;
       for (var i = 0; i < 3; i = i + 1) { x = x + 1; }
       return x;
   }
   var r = main();
   ```
   ```
   error:<source>:4:11: expected ')', got ';'
   error:<source>:5:23: expected '=', got '<'
   error:<source>:6:13: undefined variable 'x' (missing include or enum?)
   ```
   Expected: the first only. (`var x = g(1, 2;` then a `while` gives the first and the bogus `undefined variable 'x'`.)

3. **A method-call for-step cascades "undefined function"** and the refusal-to-emit line:
   ```cyr
   struct C { n; }
   impl C { fn inc(self) { self.n = self.n + 1; return 0; } }
   fn main() {
       var c = C { 0 };
       for (var i = 0; c.n < 3; c.inc()) { i = i + 1; }
       return c.n;
   }
   var r = main();
   ```
   ```
   error:<source>:5:31: expected '=', got '.'
   warning: undefined function 'inc'
   warning: undefined function 'inc' (reachable call site)
   error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
   ```
   The refusal itself is by design (a step is an assignment — guide "For"; parse_ctrl.cyr:820 "A call … keeps
   'expected ='"); the three trailing lines are the bug, and the first could name the rule.

4. **A missing `}` at EOF with two or more blocks open prints every error after the first at `0:1`, with no file:**
   ```cyr
   fn main() {
       var x = 0;
       if (x == 0) {
           x = 1;
   ```
   ```
   error:<source>:4:15: expected '}', got end of file
   error:0:1: expected '}', got end of file
   ```
   Three open blocks print `error:0:1:` twice. Expected: each at the EOF token's real location (or one error).

## Root cause

1. The const-fn checker reports first (`_ce_badn(S, "unknown name ", …)`, `src/frontend/parse_fn.cyr:6178` / `6188`),
   then the ordinary runtime compile of the same body (a const fn is also a runtime fn) reports `undefined variable`
   from the expression parser; nothing suppresses the second once the first fired. Its caret is one column past the
   name (the cursor has consumed it).
2. Speculation: `_sync_skip` (`src/common/util.cyr:2683`) resyncs on the call's own `;`, but the `for` header is then
   mis-entered so `i < 3` is parsed as a statement, and the for body's `}` closes `main`'s block early — `return x;`
   lands outside the fn, hence `undefined variable 'x'`.
3. `_for_step_assign` (`src/frontend/parse_ctrl.cyr:781`) on a plain (non-`OP=`) step does
   `if (PEEKT(S) != 4) { ERR_EXPECT(S, 4); }  STI(S, GTI(S) + 1);` (parse_ctrl.cyr:789–790) and carries on: the `.` is
   skipped and `_for_step_aggregate` → PCMPE compiles `inc()` as a call to a FREE fn `inc`, recording an unresolved call
   site that the end-of-compile undefined-function check (a separate emitter, not gated on `_had_error`) then reports.
   `_for_step_replay` (parse_ctrl.cyr:822) sends `c.inc()` there because `_stmt_dot_chain_call` says it is a call
   (mc != 0), which by design is not a field store.
4. Speculation: every `ERR_EXPECT(S, 14)` site in parse_ctrl.cyr is followed by an unconditional
   `STI(S, GTI(S) + 1)` (e.g. parse_ctrl.cyr:140–141, 955, 1009), which steps the cursor PAST the EOF token; the
   enclosing block's error then reads a token slot with no line / offset, and `FM_LOOKUP` (`src/frontend/lex.cyr:220`)
   prints the raw line `0` with no file. `_wd_eof_tick` (util.cyr:2661–2676) documents and fixes exactly this
   `error:0:1:` for its own message by rewinding to `GTCNT - 1`; `_err_head_at` (util.cyr:2752) has no such clamp.

## Proposed fix

Diagnostic only — no change to what compiles. (1) Skip the runtime body's scope errors for a const fn whose check
already failed (or let only one side report). (2) After a call-argument error, resync to the statement's end without
entering a following statement's header (verify the R2 statement-keyword stop in `_sync_skip` sees `for`). (3) Return
after the `ERR_EXPECT(S, 4)` in `_for_step_assign` (and name the rule: "a for step is an assignment; `c.inc()` is a
call"); or have the undefined-function report stand down when `_had_error` is set. (4) Clamp `ti` to `GTCNT(S) - 1` in
`_err_head_at` — one point that covers every emitter — and/or stop stepping past token 12 after an `ERR_EXPECT(S, 14)`.
