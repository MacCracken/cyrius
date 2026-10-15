# `&x.f` — the address of a struct field — does not parse (`expected ')', got '.'`), while the guide cites `load64(&s.f)` and `&h.f` as expressions — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (is `&x.f` cyrius: the language grows it, or the guide stops citing
it). Measured 2026-10-14 on the 6.7.11 struct lane (`l6711-struct`, unit S4) and the installed 6.7.0, 6.7.5 and 6.7.9
compilers, x86_64: refused by every one.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S4), writing `deref_store_struct_copy.tcyr`: a row that
pointed a `*S` at a struct inside a larger local (`var p: *S3 = &o.s;`) did not compile; the rows now use `&o` (the
struct is o's first field).
**Severity:** Low — a parse error, never silent; but the guide documents the expression twice, and a reader following
it meets "expected ')', got '.'" with no hint that the address of a field is unsupported.
**Affects:** every compiler measured; every target (frontend).

## Reproduction

```sh
cat > /tmp/af.cyr <<'X'
struct E { a; g: u8; }
fn f(): i64 { var o = E { 1, 99 }; return load8(&o.g); }
syscall(60, f());
X
build/cycc < /tmp/af.cyr > /tmp/af; echo $?
# error:<source>:2:51: expected ')', got '.'      (exit 1)
```

The same for a global (`var q = &GO.g;` → `expected ';', got '.'`), a `*E` parameter (`load8(&p.g)`), a declaration
initialiser and a call argument at top level (`set(&GW.s)`). The guide: `docs/guides/cyrius-guide.md` § packed
structs ("Code that reached such a struct by hand — … `load64(&s.f)` on a narrow field (it now reads the next fields
too) …", line ~1230) and § trait objects (a `dyn` formed from "any other expression — … `&h.f`, `&a[i]` …", line
~2410); `&Color.RED` is refused by name (line ~4793), so the parser does reach a `.` after `&IDENT` for an enum.

## Root cause (read from the behaviour)

The `&` factor takes `IDENT` (and the enum-constant arm refuses `&E.V` by name); a `.field` after it is not a postfix
of the address-of, so the parse stops at the `.`. Workarounds today: the struct's own address plus the field offset
(`&o + 8`), or a typed pointer and its field (`var p: *E = &o; p.g`).

## Options

- **(a) `&x.f` is the field's address** (a `*T` of the field's type, or an untyped address) for a local, a global, a
  parameter and a chain through pointers — a language addition.
- **(b) Not cyrius** — refuse it by name (*the address of a field is not taken: write `&x + offset` or reach it
  through a `*T`*) and correct the guide's two citations.

Rows either way: a local, a global, a `*T` parameter, a nested field, a narrow field (`load8(&o.g)`), top level.
