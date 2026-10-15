# `cyrius api-surface` counts a variadic tail `...` as a parameter (`va/2`, `zv/1`) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 tools lane (l6711-tools @ 50a981eb), with
`programs/cyrius_api_surface.cyr` built from that tree. Met while fixing
`2026-10-09-source-scanners-miss-const-fn-and-generic-commas.md` (whose repro has `fn va(n, ...)`; its
"want" names only `cf/1, mp/2, pp/2`, so the variadic arity was left as it was); filed.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D22 — name/MIN-.
**Severity:** Low — the snapshot records a variadic fn with a fixed arity it does not have. A caller may
pass any number of arguments from the named count up; the entry reads as an exact count, so a variadic
fn and a fixed-arity fn of the same count look the same, and a later change between the two is not a
signature change in the snapshot.
**Affects:** `cyrius api-surface` (`programs/cyrius_api_surface.cyr` `_asf_arity`) and the snapshots it
writes (docs/api-surface.snapshot here; no variadic fn in this tree's lib/ today).

## Reproduction

```sh
mkdir -p t/src && cd t
printf 'fn va(n, ...): i64 { return n; }\nfn zv(...): i64 { return 7; }\nfn two(a, b): i64 { return a + b; }\nsyscall(60, va(1, 2, 3) + zv() + two(1, 2));\n' > src/v.cyr
cycc < src/v.cyr > v.bin && chmod +x v.bin && ./v.bin; echo "exit=$?"   # exit=11: va(1, 2, 3) and zv() compile
cyrius_api_surface --update --scope=project --snapshot=v.snap && cat v.snap
```

Output:

```
v::two/2
v::va/2
v::zv/1
```

`va` takes 1 or more arguments and `zv` 0 or more; the entries say exactly 2 and exactly 1.

## Root cause

`_asf_arity` counts depth-1 commas plus one, and `...` is just more non-blank bytes, so the tail counts
as a parameter. The notation for "N or more" is the user's call (the defaulted form is `name/MIN-MAX`,
6.7.7): e.g. `va/1-` / `zv/0-`, or `va/1+`. removed_symbol_census.sh's strip (`s|/.*||`) reads any of
those as the bare name.
