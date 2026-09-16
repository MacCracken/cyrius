# cyrlint's untracked-deferral check misses a multi-word term wrapped across two comment lines — OPEN

**Status:** 🟡 **OPEN** — filed from mabda 4.1.3 verification; not yet triaged.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-09-16, mabda 4.1.3 deferral audit. `cyrlint --strict-deferrals` reported 0
untracked deferrals across mabda's 186 files while three untracked ones sat in `src/`, each
wrapped across a line break.
**Severity:** Low. It hides deferral markers from the gate; it breaks nothing at build or run time.
**Affects:** cyrlint in cyrius 6.6.4; unchanged at HEAD 4f3731e8. Component: `programs/cyrlint.cyr`.

## Summary

`_line_deferral_term` (`programs/cyrlint.cyr:93`, called per line at `:275`) matches each term
against one line at a time. The multi-word terms (`for now`, `not yet`, `later bite`,
`future bite`, `out of scope`) are missed when a comment wraps between the two words, which is
exactly where a formatter or a 120-column limit tends to break them. The tracking-pointer check
has the same per-line scope, so the fix has to join both.

## Reproduction

```sh
cat > split.cyr <<'EOF'
# The immediate-offset form is a later
# bite.
# Uniform operands are rejected for
# now.
fn main() { return 0; }
var rc = main();
syscall(60, rc);
EOF
cyrlint --strict-deferrals split.cyr; echo "rc=$?"     # rc=0: both deferrals missed
printf '# The immediate-offset form is a later bite.\nfn main() { return 0; }\nvar rc = main();\nsyscall(60, rc);\n' > one.cyr
cyrlint --strict-deferrals one.cyr; echo "rc=$?"       # rc=2: same text on one line is caught
```

Real cases in mabda at tag 4.1.2: `src/gfx9_compile.cyr:326-327` and `:532-533` ("a later /
bite"), `src/compute.cyr:346-348` ("not / yet", "for / now").

## Root cause (if known)

Per-line scanning in `_line_deferral_term` and `_line_has_tracking_ptr`; there is no notion of a
comment block.

## Proposed fix

Treat consecutive `#` comment lines as one block: join them with single spaces, match terms on the
joined text, accept a tracking pointer anywhere in the same block, and report the first line of the
block. Single-line behaviour stays the same.

## Consumer-side workaround

mabda 4.1.3 ships `scripts/check-split-deferrals.py`, which joins adjacent comment lines and runs
the same term list, wired into `make test-all` and CI next to a per-file
`cyrlint --strict-deferrals` loop.
