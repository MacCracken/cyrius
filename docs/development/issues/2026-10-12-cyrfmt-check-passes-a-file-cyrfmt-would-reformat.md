# `cyrfmt --check` exits 0 on a file that `cyrfmt` itself reformats (a call's continuation-line indent) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (the run below). Found by cyim's 1.11.0 release, where `cyrius audit`'s fmt stage flagged a file that `cyrfmt --check` had passed. Also seen on 6.6.2.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D26 — keep the contract; audit uses cyrfmt --check.
**Discovered:** 2026-10-12, cyim 1.11.0's lint/fmt pass.
**Severity:** Low — a check that cannot fail. A CI that gates on `cyrfmt --check` passes code that `cyrfmt` and `cyrius audit` then disagree about.
**Affects:** 6.6.2 and 6.7.9 (both reported; 6.7.9 re-run by hand).

## Summary

For a call argument wrapped onto a continuation line, `cyrfmt` re-indents the continuation (to 6 spaces in the
example below), but `cyrfmt --check` reports the file as already formatted and exits 0. The two modes disagree, so
`--check` misses exactly the drift it exists to catch.

## Reproduction

```sh
printf 'fn f(a, b) {\n    return a + b;\n}\nfn main() {\n    f(1,\n        2);\n    return 0;\n}\n' > x.cyr
cyrfmt --check x.cyr; echo "check rc=$?"
cyrfmt x.cyr | diff x.cyr -
```

Actual (6.7.9):

```
check rc=0
6c6
<         2);
---
>       2);
```

Expected: `--check` exits non-zero (and names the file) whenever `cyrfmt x.cyr` would print something other than
`x.cyr`.

## Proposed fix

Implement `--check` as "format, then compare with the input", so the two modes cannot disagree. Whatever the
continuation rule is, it then applies to both.

## Consumer-side workaround

Gate on `cyrfmt x.cyr | diff -q x.cyr -` instead of `cyrfmt --check`.
