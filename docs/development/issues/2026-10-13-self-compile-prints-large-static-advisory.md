# The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line) — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-13: `cat src/main.cyr | build/cycc` (2,114,376 B, 6.7.10) exits 0 and prints
`warning: large static data (142016 bytes) — consider alloc() for buffers >4KB`; the installed 6.7.9 compiler on
6.7.9's own sources (`git archive 6.7.9 src lib`) prints the same advisory at 141,760 B. The output is
byte-identical to `build/cycc`; only stderr carries the noise.
**Placement:** 6.7.14 — the refactor / optimization review (roadmap.md § 6.7.14) — placed 2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** Low — no wrong value; one warning on every self-compile (the bootstrap chain, the fixpoint, the release
gate, every lane's rebuild), the noise that trains readers to skip the stderr real warnings land on.
**Affects:** cycc 6.7.9 and the 6.7.10 tree measured (not bisected); every target fork that includes the same
frontend.

## Summary

`_warn_large_static` prints its advisory for a program whose var data exceeds 131,072 B. cycc is such a program:
6.7.10's var data is 142,016 B, about 11 KB over. The single largest static is the TypeScript front end's node-index
scratch stack, `var _ts_cst[8192];` (`src/frontend/ts/parse.cyr:348`, 65,536 B, a bare top-level array is N × 8 B),
which a plain cyrius compile never touches.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat src/main.cyr | build/cycc > /tmp/cc_self; echo "rc=$?"
# rc=0, stderr:
# note: 52 unreachable fns (10597 bytes — set CYRIUS_DCE=1 to eliminate, CYRIUS_DCE_VERBOSE=1 to list)
# warning: large static data (142016 bytes) — consider alloc() for buffers >4KB
cmp /tmp/cc_self build/cycc && echo identical
```

Expected: no advisory on the compiler's own build.

## Root cause

`_warn_large_static` (`src/frontend/parse_fn.cyr:13052`): `if (totvar <= 131072) { return 0; }`, then the warning.
cycc's own statics (every global scalar plus its top-level arrays — `_ts_cst` 65,536 B; several 4,096 B tables:
`_priv_files`, `_coro_rcp`, `_pp_incdir`, `_pp_curfile`, `_rf_ov`, `_type_spans`, `_pe_imp_name_buf`,
`_pe_pending_imp_buf`) sum past the line.

## Proposed fix

Shrink cycc's own static data below the line rather than special-case the advisory: allocate `_ts_cst`'s 64 KB on
first TypeScript use (the heap map or `alloc()`), which alone takes cycc to about 76 KB (measured: a scratch copy of the tree with
`var _ts_cst[8];` self-compiles with no advisory); check the bootstrap chain
(cybs compiles the same source: a top-level array is N bytes there, `src/frontend/lex.cyr:734`'s note) and keep the
fixpoint and seed-derive green. Row: a gate that self-compiles and asserts no `large static data` line on stderr.

## Consumer-side workaround

None needed — the advisory is stderr-only; the compiler is unaffected.
