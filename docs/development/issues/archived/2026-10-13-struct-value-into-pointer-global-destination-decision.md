# `GP = l` with `GP` a `*S` GLOBAL stores `l`'s first word into `GP` (a garbage pointer), where a `*S` local or parameter destination copies `l` into its pointee — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-8, the user's decision D2 (2026-10-13, (a)): a struct value assigned to a typed `*S` global copies into `*GP`, as a `*S` local or parameter destination does — from a local, a value global, a by-value parameter, a call, a field, `*p`, a method or operator result, wrapped, in a for step, in a fn and at top level, 0 to 24 B (a zero-size struct copies nothing); `GP = q` from a `*S` or a handle, `GP = &x`, `GP = 0` still rebind; another struct, and at top level a struct result over 8 B, are refused by name. gd.cyr exits 11 (it gave 13: GP became 5) on x86_64, aarch64, cx and PE. Rows: `crossos/struct_value_into_ptr_global.tcyr` (143, `small_struct_handle_line.sh` R14 on seven legs), `struct_copy_type_checked.sh` R10–R16, A8 (the repro verbatim), A9. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN — a decision for the user** (what a struct value assigned to a `*S` global means). Verified
2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64): with `l = {5, 8}`, `lp = l` (`lp: *S` local) and `q = l`
(`q: *S` parameter) copy `l` into the pointee; `GP = l` leaves `GS` untouched and makes `GP` the word 5, silently.
The guide records it as "⚠ Not settled" (`docs/guides/cyrius-guide.md:1339`).
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** Medium — silent: the next `GP.a` dereferences 5 (SIGSEGV), or a later store through `GP` writes a wild
address.
**Affects:** the 6.7.10 tree (measured there only, x86_64); the assignment arms are frontend-only, so every target.

## Summary

6.7.10's handle line and decision 6 made a `*S` LOCAL or PARAMETER destination of a struct value a copy into the
pointee (`_agc_pp` 2 / 1). A `*S` GLOBAL destination was not given that rule: the one-word store writes the value's
first word into the pointer itself. A `*S` destination from another `*S` (`GP = q`) is a rebind everywhere, and is
not in question.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/gd.cyr <<'EOF'
struct S { a; b; }
var GS = S { 0, 0 };
var GP: *S = 0;
fn viap(q: *S, l: S): i64 { q = l; return 0; }
fn main(): i64 {
    GP = &GS;
    var t: S; t.a = 0; t.b = 0;
    var lp: *S = &t;
    var l: S; l.a = 5; l.b = 8;
    lp = l;
    var r = (t.a == 5 && t.b == 8);
    GP = l;
    r = r + (GS.a == 5) * 2 + (GP == 5) * 4;
    var u: S; u.a = 0; u.b = 0; viap(&u, l); return r + (u.a == 5 && u.b == 8) * 8;
}
syscall(60, main());
EOF
build/cycc < /tmp/gd.cyr > /tmp/gd && chmod +x /tmp/gd && /tmp/gd; echo $?
# 13 = 1 (local copies) + 4 (GP is now 5) + 8 (parameter copies); 11 if GP = l copied into *GP
# (the workaround below, `var gq: *S = GP; gq = l;`, gives 11)
```

## Root cause

`_agc_operand`'s global rung (`src/frontend/parse.cyr:2909-2925`) takes a global whose slot IS the struct (`GVPM` 2)
or a pointer-mode handle global (`_agc_handle_global`, `:2875`); a typed `*S` global is neither, so it is no aggregate
operand and the plain store writes `l`'s first word. The local rung makes a `*T` local a handle (`_agc_handle_local`,
`:2862`: `_small_sptr` at 8 B or less, `_agc_plain_big` over 8 B). (Read from the code.)

## Proposed fix

The user's call, one of:

- **(a) Copy into `*GP`**, as a `*S` local or parameter destination does: the global rung answers a typed `*S` global as
  a handle in the deref band (`0 - 1000 - gvi`); a struct value of another type refused by name. Changes what
  compiling code does.
- **(b) Refuse by name**: a struct value into a `*S` global (bind a `*S` local, as below) — stops code compiling,
  and leaves the local / global asymmetry as a refusal instead of a silent store.
- **(c) Keep the word store**, documented in the guide as the global's rule.

Rows either way: the local, parameter and global destinations at 8, 16 and 24 B, in a fn and at top level.

## Consumer-side workaround

Go through a `*S` local: `var gq: *S = GP; gq = l;` (copies into `GS`), or assign the fields.
