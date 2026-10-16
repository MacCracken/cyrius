# `cyrius type-audit` does not count a generic fn (`fn f<T>(..)`) as a public fn — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-8: `_match_fn_decl` steps over blanks and a balanced `<..>` (`>>` / `>>>` closing two / three levels) before the `(`, so the repro reads `g: 2/2 annotated`, `total public fns: 2` (was 1/1). No decision needed. Rows: `type_audit_generic_fns.sh` 1–2 (the repro; seven shapes, unannotated `gs::gun` listed); mutations RED. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 tools lane (l6711-tools @ 50a981eb), with
`programs/cyrius_type_audit.cyr` built from that tree. Met while fixing
`2026-10-09-source-scanners-miss-const-fn-and-generic-commas.md` (which gave type-audit the shared
declaration reader, `_src_decl_at`); outside that issue's filed surface, so filed.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Severity:** Low — a public generic fn is missing from the audit's counts and its unannotated list; no
wrong output elsewhere.
**Affects:** `cyrius type-audit` (`programs/cyrius_type_audit.cyr`), every version with generics.

## Reproduction

```sh
mkdir -p t/lib && cd t
printf 'fn gid<T>(a: T): T { return a; }\nfn plain(a): i64 { return a; }\nsyscall(60, plain(gid(3)));\n' > lib/g.cyr
cycc < lib/g.cyr > g.bin && chmod +x g.bin && ./g.bin; echo "exit=$?"     # exit=3: it compiles and runs
cyrius_type_audit --module=g
```

Output (the relevant lines):

```
  g: 1/1 annotated
  total public fns:       1
```

Expected: 2 public fns (`gid` and `plain`), both annotated.

## Root cause

`_match_fn_decl` (`programs/cyrius_type_audit.cyr`) takes the identifier after the declaration prefix and
then requires `(` IMMEDIATELY after it (`if (load8(buf + p) != 40) { return 0; }`), so a generic fn's
`<T>` between its name and its parameter list makes the line not a declaration. `cyrdoc` and
`cyrius_api_surface` step to the `(` (they list `gid`); `cyrius header` skips a generic deliberately (no
single C symbol). Fix: step over a balanced `<..>` after the name before the `(` test.
