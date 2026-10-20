# A use of an enum whose body was refused (`enum E { A 5 }` then `E.A`) cascades "no struct type in scope for 'E'" wherever the panic latch does not hide it — in the declaration zone since 7a4f9ecdf — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at aa0d05620, x86_64; the shared
front end, every target) against the slot-open compiler (b73e8d5fe's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone review, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — the program is refused (rc 1) and the enum's own error is printed first; one invented error follows
(one mistake, two errors: the dx_multi_error.sh K rows' rule).
**Kind:** bug (diagnostic cascade).
**Discovered:** by the 6.7.16 zone lane's review, checking issues/2026-10-18-zone-replay-reports-only-first-latched-
error.md's fix (7a4f9ecdf: EMIT_GVAR_INITS releases the panic latch at each replayed zone entry). The cascade is older
than the lane — it prints after the first top-level statement and in a fn's later statement on b73e8d5fe too — but the
zone's single latch used to hide it there, and the per-entry release exposes it. Related, not the same:
staged frontend 2026-10-19-pass-one-enum-member-refusal-swallows-later-declaration-errors.md (the same refusal's latch
swallowing later DECLARATION errors in pass 1) and issues/2026-10-18-refused-declaration-names-cascade-in-const-
contexts-bounds-and-uninit.md (6.7.15's `_dl_names` stand-down for a refused declaration's names).

## Reproduction

```sh
printf 'enum E { A 5 }\nvar a = 1;\nvar q = E.A;\nsyscall(60, 0);\n' | build/cycc > /dev/null; echo rc=$?
# lane (aa0d05620):
# error:<source>:1:12: expected identifier, got number 5
# error:<source>:3:12: no struct type in scope for 'E'; a '.field' access needs its struct declaration (missing include?)
# rc=1
# b73e8d5fe: the 1:12 line alone (the enum's latch held through the whole zone replay)
printf 'enum E { A 5 }\nvar q = E.A;\nsyscall(60, 0);\n' | build/cycc > /dev/null
# lane: 1:12 + 2:12 "no struct type in scope for 'E'"; b73e8d5fe: 1:12 alone
```

The same use where the latch does not reach it prints the pair on BOTH compilers:

```sh
printf 'enum E { A 5 }\nvar a = 1;\na = 2;\nvar q = E.A;\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:12: expected identifier, got number 5
# error:<source>:4:12: no struct type in scope for 'E'; ...           (after the first statement)
printf 'enum E { A 5 }\nfn f(): i64 { var z = 1; z = 2; var q = E.A; return q; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:12: expected identifier, got number 5
# error:<source>:2:44: no struct type in scope for 'E'; ...           (a fn's later statement)
```

A fn's FIRST statement (`fn f(): i64 { var q = E.A; return q; }`) and the program's first statement
(enum_member_separator.sh S8, `syscall(60, E.A);`) print 1:12 alone — the latch, not a stand-down. A bare `var q = E;`
prints 1:12 alone everywhere.

## Root cause

`enum E { A 5 }` is refused INSIDE its body (PARSE_ENUM_DEF's member loop, "expected identifier", src/frontend/
parse_types.cyr): E is left with no member A, and its name is not entered through `_dl_names` (src/frontend/
parse_fn_def.cyr — a late declaration, a refused inclusion, one in a fn body or a block), so `E.A` reaches the
`.field` arm's `sid == 0` reporter (src/frontend/parse_decl.cyr, `no struct type in scope for`), whose stand-downs
(`_cst_fld_at`, `_fld_sid0_said`) do not know E. Where the panic latch the enum set still holds, the report is
swallowed; elsewhere it prints.

## Fix direction

Enter a body-refused enum's name (and the members it did read) as reported, as `_dl_names` does for a refused
declaration's — at the member loop's refusal, or by running `_dl_name_at` over the enum's tokens when its parse latched —
so the `.field` / undefined-variable reporters stand down for `E.A`. Rows: the four shapes above give the one 1:12 error
(zone, zone-first, after the first statement, a fn's later statement), on x86_64 / aarch64 / cx / PE; an enum declared
nowhere (`var q = Z.A;`) is still "undefined variable 'Z'".
