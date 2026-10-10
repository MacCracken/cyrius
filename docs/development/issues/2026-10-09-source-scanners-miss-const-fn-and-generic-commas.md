# Source scanners: `const fn` is invisible, `Pair<i64, i64>` is two parameters, `cyrius header` prints `cyr_val ...`, cyrdoc writes past its buffers — OPEN

**Status:** 🟡 **OPEN** — all four items reproduced 2026-10-09 against the merged 6.7.7 tip
(`/home/macro/.cache/c6/wt677/int` @ 06bd8981). The tools were built from that tree with its `build/cycc`
(1,916,288 B) and run on scratch copies of the repro. The `cyrius header`, `cyrius_api_surface` and `cyrdoc` binaries
in the installed 6.7.6 store give the same output.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
These are scanner bugs, so they go with that release's Scanners group (api-surface's multi-line strings, the
attribute word list in five tools).
**Discovered:** 2026-10-09 by the 6.7.7 B6 lane (default and named arguments), bite 5 ("the tools that read a parameter
list"), outside its scope; filed 2026-10-09.
**Severity:** Medium overall:
- Items 1–3 are silently wrong output: a C header that does not compile, a wrong api-surface snapshot, and public fns
  missing from the docs, the outline and the counts.
- ⚠ **Item 4 is memory corruption.** cyrdoc writes past the end of two fixed heap allocations with no bound. It is
  silent today because nothing is allocated after them. This is a bug, not a security issue: the input is the
  developer's own source.

**Affects:** the `cyrius` CLI (`header`, `coverage`, the distlib and `[embed]` indexes), `cyrius_api_surface`,
`cyrius_type_audit`, `cyrdoc` and `cyrius-lsp`, through the merged 6.7.7. Item 1 dates from 6.7.2 (`const fn`); the
others were not bisected.

## Summary / Reproduction

`docs/development/issues/repros/2026-10-09-source-scanners-miss-const-fn-and-generic-commas.cyr` compiles and exits 3.
Its five public fns are:

```cyrius
const fn cf(a: i64): i64 { return a; }
fn pp(p: Pair<i64, i64>, b): i64 { return b; }
fn mp(m: Mp<i64, i64>, b): i64 { return b; }
fn va(n, ...): i64 { return n; }
fn plain(a, b): i64 { return a + b; }
```

### 1. A `const fn` is invisible to every source scanner

The scanners below read a declaration line's prefix. They know `pub`, `public`, `async` and the attributes, but not
`const`, so a `const fn` is never seen as a fn.

- `cyrius header` prints four prototypes; `cf` is missing.
- `cyrius_api_surface --update` writes `scan::mp/3 scan::plain/2 scan::pp/3 scan::va/2`; `cf` is missing.
- `cyrius_type_audit` reports `total public fns: 4`.
- cyrdoc's markdown for a file with a documented `const fn cf` and a documented `fn pf` lists `pf` only, and
  `--check` never counts `cf`.
- cyrius-lsp's `textDocument/documentSymbol` (after `didOpen`) lists `pf` only. Its symbol index also feeds
  go-to-definition and hover.
- By reading, `cyrius coverage` and the distlib and `[embed]` owner indexes miss it too. They share the same reader.

type-audit's matcher is narrower still. It takes only a line that starts with `fn `, so a `lib/m.cyr` holding `fn`,
`pub fn`, `public fn`, `async fn`, `#inline` on its own line + `fn`, `#inline fn` on one line, and `const fn`
counts 2 of the 7.

### 2. A generic type with a comma splits its parameter in two

The scanners balance `( [ {` but not `<..>`.

- `cyrius header` prints:
  ```
  cyr_val pp(cyr_val p, cyr_val i64>, cyr_val b);
  cyr_val mp(cyr_val m, cyr_val i64>, cyr_val b);
  ```
  `cc -fsyntax-only` rejects both lines: "expected ';', ',' or ')' before '>' token".
- api-surface records `pp/3` and `mp/3`; the compiler's arity is 2.
- cyrius-lsp's parameter collector registers the type after the comma (`i64`, or `V` in `Mp<K, V>`) as a PARAMETER
  name. Its locals table is file-wide by design, so `textDocument/semanticTokens/full` colors EVERY `i64` in the repro
  as a parameter (token type 6), including `cf`'s `: i64` and every return type. With `Mp<K>` (no comma) nothing is
  miscolored.

### 3. `cyrius header` prints `cyr_val ...` for a variadic parameter

The output line is `cyr_val va(cyr_val n, cyr_val ...);`. `cc` rejects it: "expected ';', ',' or ')' before '...'
token". C spells a variadic tail `...` alone.

### 4. ⚠ cyrdoc copies a name and a signature into fixed buffers with no bound (memory corruption)

`process_file` allocates `namebuf = alloc(128)` and `sigbuf = alloc(256)` once per file. `extract_fn_name` and
`extract_fn_sig` `memcpy` the whole name or signature into them, whatever its length.
`docs/development/issues/repros/2026-10-09-source-scanners-miss-const-fn-and-generic-commas-cyrdoc.sh [cyrdoc]` writes
one documented 80-parameter fn line (~820 bytes) and runs cyrdoc on it:

```
cyrdoc rc=0; printed signature: 812 bytes (sigbuf is alloc(256))
```

The printed line is `syscall(.., sigbuf, strlen(sigbuf))` plus 6 bytes of markdown, so about 806 bytes and a NUL went
into the 256-byte allocation: about 550 bytes past its end. A 1.69 MB one-line signature wrote about 1.69 MB past it
and still exited 0. A name longer than 128 bytes runs into `sigbuf`. Nothing is allocated after `sigbuf` while a file
is processed, so today the write lands in unused chunk space and nothing visible breaks. Any allocation placed after
it, or the end of a chunk, turns this into corruption of live data or a SIGSEGV.

## Root cause

1. **`const` prefix.**
   - `_src_decl_at` (`cbt/srcscan.cyr:186`) steps over `private;`, attributes, `pub` / `public` and `async` (:207),
     but not `const`. `_src_public_fn_at` (:273) is built on it, and `cmd_header` (`cbt/quality.cyr:918`) and
     `cmd_coverage` (:269) call that. `_src_decls` (:419, through `_src_decls_line` :438) is also built on it, and the
     LSP index (`programs/cyrius-lsp.cyr:583`), distlib (`cbt/commands.cyr:4870`) and `[embed]` (:4986) call that.
   - api-surface's `_asf_decl_prefix` (`programs/cyrius_api_surface.cyr:330`) knows `public` / `pub` / `async` and
     the attributes.
   - cyrdoc's `_doc_fn_at` (`programs/cyrdoc.cyr:107`) knows one attribute and `pub` / `public`.
   - type-audit's `_match_fn_decl` (`programs/cyrius_type_audit.cyr:101`) takes only a line-initial `fn `.
2. **`<..>` not balanced.**
   - `_hdr_close` (`cbt/quality.cyr:853`, used for the list's end and for each parameter's `,`) balances
     `( [ {` only.
   - `_asf_arity` (`programs/cyrius_api_surface.cyr:550`, the depth bump at :560) balances `( [` only.
   - `_lsp_collect_locals` (`programs/cyrius-lsp.cyr:1906`, the depth bump at :1978) balances `( [` only, so a
     depth-0 `,` inside the type returns it to "expect a parameter name".
   - The B6 hand-off left `<` out on purpose, because in a DEFAULT `<` is an operator. The compiler draws that line
     itself: `_pl_next` (`src/frontend/parse_fn.cyr:2482`) balances the TYPE with `_pl_tdepth` (:2472: `( [ { <`
     open, and `>` / `>>` / `>>>` close one, two or three levels) and, after a depth-0 `=`, uses `_pl_dflt_end`.
3. **Variadic.** `cmd_header`'s parameter loop (`cbt/quality.cyr:945-975`) takes `...` as a parameter name and writes
   `cyr_val ` before it (:969).
4. **cyrdoc buffers.** The buffers are `programs/cyrdoc.cyr:265-266`. The unbounded copies are `extract_fn_name`
   (:152, `memcpy` at :168) and `extract_fn_sig` (:194, `memcpy` at :217).

## Proposed fix

1. **`const` prefix.**
   - Add `const` beside `async` in `_src_decl_at`. That fixes header, coverage, the LSP index, distlib and `[embed]`.
   - Add it in api-surface's `_asf_decl_prefix` too.
   - Give type-audit and cyrdoc the same prefix rule, by including `cbt/srcscan.cyr` as cyrius-lsp already does
     (`programs/cyrius-lsp.cyr:33`) rather than adding a fifth hand-kept copy.
   - Say in the CHANGELOG that `cyrdoc --check` and type-audit then count more fns: an undocumented public
     `const fn`, and for type-audit a `pub` / `public` / `async` fn.
2. **`<..>` in types.**
   - Balance `<` and `>` (`>>` / `>>>` as two / three) in a parameter's TYPE only, from its `:` to its depth-0 `=`, as
     `_pl_next` does. After the `=`, `<` stays an operator.
   - Apply it in `_hdr_close`'s callers, `_asf_arity` and `_lsp_collect_locals`.
   - Regenerate this tree's api-surface snapshot and diff it: a corrected arity reads as a changed signature.
3. **Variadic.** Write a variadic tail as `...`. Do this only after checking that cyrius's variadic tail travels as
   C's varargs do (SysV `al`, the stack tail); otherwise skip the fn with a `/* variadic: not callable from C */`
   comment.
4. **cyrdoc.** Write the name and the signature straight from the source buffer (`syscall(1, 1, line + si, slen)`)
   with no copy. Failing that, size each copy to `llen + 1`.

Gate rows: the existing tool rows (`tests/gates/toolchain/default_named_args_checked.sh` S-hdr / S-asf / S-doc /
S-lsp / S-ta) get one row per item:
- the `const fn` seen by each tool;
- `pp` / `mp` with two parameters in each tool, and a default `c = 1 < 2` still one parameter;
- the header compiling under `cc -fsyntax-only`;
- the 80-parameter line and a 200-byte name in cyrdoc, under a mutation that restores the fixed `alloc(256)`.
