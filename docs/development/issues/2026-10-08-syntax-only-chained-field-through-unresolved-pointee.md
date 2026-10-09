# `--syntax-only` invents "expected '=', got '.'" for `a.f.g` when `f: *Foo` and `Foo` is in another file — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc --syntax-only`: `a.f.g = 1;`
and `a.f.g += 1;` → `expected '=', got '.'`; `var v = a.f.g;` and `a.f.g(1);` → `expected ';', got '.'`; exit 1 on
each. The same files with `struct Foo { g; }` prepended pass (exit 0), as does the one-level `e.g = 1` with `e: *Foo`.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 review / lane finds (roadmap commit e95f295d, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — `cyrius lint`'s pre-pass refuses valid source with an invented syntax error (the v6.5.19
false-accusation class); workaround below.
**Affects:** cycc 6.6.17 – 6.7.6 (the `*T` field hop is 6.6.17's; not bisected further).

## Summary

`--syntax-only` (lint's pre-pass, v6.5.19) answers "does this file PARSE?" without resolving names, so a struct
declared in a sibling file must not produce an error. The one-level case is handled (`_synonly_fld_tail` /
`_synonly_skip_chain`). A two-level chain whose middle field is a pointer to a type this file does not declare is not:
the hop through `f` needs `Foo`'s struct id, finds none, stops walking, and the leftover `.g` is reported as a syntax
error the file does not contain — read, write, compound write and method-call forms alike.

## Reproduction

```cyr
struct Bar { f: *Foo; n; }      # Foo is declared in another file of the project
fn main() {
    var a: Bar;
    a.f.g = 1;                  # also: a.f.g += 1;  var v = a.f.g;  a.f.g(1);
    return 0;
}
var r = main();
```

```sh
build/cycc --syntax-only < so.cyr >/dev/null; echo $?
# 6.7.6: error:<source>:4:8: expected '=', got '.'   (exit 1)
# expected: exit 0, no output
```

## Root cause

- Write: `PARSE_FIELD_STORE` (`src/frontend/parse_decl.cyr:1802`) resolves `a.f`, then walks further hops only while
  `_fld_hop_sid(S) > 0` (parse_decl.cyr:1888; `_fld_hop_sid` at 1371 returns the field's pointee struct id, 0 when
  `Foo` is unknown). With no hop it reaches `if (PEEKT(S) != 4) { ERR_EXPECT(S, 4); }` (parse_decl.cyr:1900) while the
  cursor is on `.`.
- Read / method: `PARSE_FIELD_LOAD` hops only `if (_fld_hop_sid(S) > 0)` (parse_decl.cyr:1685) and otherwise returns
  with the cursor on `.`, which the statement layer reports as `expected ';'`.

## Proposed fix

Under `_syntax_only == 1`, after the hop loop / hop test, a remaining `.` (token 41) is consumed the way the
unresolved-base path already does it: `return _synonly_fld_tail(S, term);` in `PARSE_FIELD_STORE` and
`_synonly_skip_chain(S); return 0;` in `PARSE_FIELD_LOAD` (a trailing `(args)` for the method form must be consumed
too). A row per form (store, `OP=`, read, method call) in `tests/gates/frontend/lint_reports_unparseable.sh` (the
v6.5.19 "never refuse a file it merely cannot RESOLVE" gate), the pointee type declared only in a second file. Changes no compiled output (`--syntax-only` emits nothing).

## Workaround

Bind the intermediate pointer: `var p = a.f; p.g = 1;` passes `--syntax-only` (verified 2026-10-08).
