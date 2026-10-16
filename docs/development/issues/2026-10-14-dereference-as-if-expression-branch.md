# A struct dereference as an IF-EXPRESSION BRANCH is typed an integer: `var v: S = if (c) { *p } else { *q };` binds `v` as a handle holding the word `*p` read (SIGSEGV at every size), and `if (c) { *p } else { s }` is refused as "branches differ in type" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane's tree (`l6711-struct`) and on `5fb211da` (the
wave-1 merge): identical output, x86_64.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D1 — (a).
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S1), probing the consumers of a dereference while fixing
issues/archived/2026-10-12-small-struct-dereference-reads-past-the-object.md and
issues/archived/2026-10-13-assignment-from-struct-dereference-copies-one-word.md.
**Severity:** High for the two-dereference shape (it compiles clean and faults: a wrong program with no diagnostic);
low for the mixed shape (a false refusal of valid source). Not a security id: the developer's own source.
**Decision note:** 6.7.10's decision 6 makes `*p` a struct VALUE in every spelling; an if-expression branch that is a
struct value over 8 B is refused by rule (`_ie_big_err`: "branch on a pointer"). What a dereference branch does over
8 B (refused by that rule, by name, or the pointer branch it already is in spirit) is the user's to settle; 8 B or
less it is a struct value like `t`.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
row() { printf '%s\nfn main(): i64 { var k = 1; var s: S; s.a = 1; var t: S; t.a = 5; var p: *S = &t; var q: *S = &s; %s }\nsyscall(60, main());\n' "$2" "$3" > /tmp/ie.cyr
  if build/cycc < /tmp/ie.cyr > /tmp/ie 2> /tmp/ie.err; then chmod +x /tmp/ie; /tmp/ie; echo "$1: exit $?"; else echo "$1: refused: $(grep -m1 '^error' /tmp/ie.err)"; fi; }
for st in 'struct S { a: i8; b: i8; c: i8; }' 'struct S { a; }' 'struct S { a; b; }'; do
  echo "-- $st"
  row "var v: S = if (k == 1) { *p } else { *q }" "$st" 'var v: S = if (k == 1) { *p } else { *q }; return v.a;'
  row "var v: S = if (k == 1) { *p } else { s }  " "$st" 'var v: S = if (k == 1) { *p } else { s }; return v.a;'
  row "control: var v: S = if (k == 1) { t } else { s }" "$st" 'var v: S = if (k == 1) { t } else { s }; return v.a;'
done
```

Actual:

```
-- struct S { a: i8; b: i8; c: i8; }
var v: S = if (k == 1) { *p } else { *q }: exit 139
var v: S = if (k == 1) { *p } else { s }  : refused: error:<source>:2:136: if expression branches differ in type: struct 'S' here, an integer before it
control: var v: S = if (k == 1) { t } else { s }: exit 5
-- struct S { a; }
var v: S = if (k == 1) { *p } else { *q }: exit 139
var v: S = if (k == 1) { *p } else { s }  : refused: error:<source>:2:136: if expression branches differ in type: struct 'S' here, an integer before it
control: var v: S = if (k == 1) { t } else { s }: exit 5
-- struct S { a; b; }
var v: S = if (k == 1) { *p } else { *q }: exit 139
var v: S = if (k == 1) { *p } else { s }  : refused: error:<source>:2:136: an if expression branch cannot be a struct value over 8 bytes: struct 'S' - branch on a pointer (`&x`, or a `*T` value)
control: var v: S = if (k == 1) { t } else { s }: refused: error:<source>:2:124: an if expression branch cannot be a struct value over 8 bytes: struct 'S' - branch on a pointer (`&x`, or a `*T` value)
```

Expected at 8 B or less: 5 on the first two rows (`v` takes the struct `t`, as the control does). Over 8 B: what the
decision note settles — never a compile-clean SIGSEGV.

## Root cause

The if-expression types each branch by SHAPE (`_ie_struct_sid`, `src/frontend/parse_ctrl.cyr`: a bare name, a whole
call, a method / operator result, a whole field); a dereference `* E` is none of them, so the branch is an integer and
the value is the word `_deref_read` loaded. `var v: S = <integer>` is then a HANDLE (the handle line) holding that
word as the struct's address — `v.a` reads through `{5, ..}` (8 B: the first field, an address of 5; 3 B: the
zero-padded bytes since 6.7.11) and faults. Mixed with a struct-value branch the two branch types differ and the
if-expression refuses. The typing the rest of the compiler uses for a dereference (`_hl_dstar` / `_hl_psid`: the `*T`
operand's T) is never asked.

## Proposed fix

Give `_ie_struct_sid` a dereference arm: a branch that is ONE dereference whose operand `_hl_psid` types `*T` is a
struct value of T (8 B or less: read byte-exact, as `_deref_small` reads it; over 8 B: whatever the decision note
settles). Rows: the three shapes at 3 / 8 / 16 / 24 B in a fn and at top level, a mutant RED.
