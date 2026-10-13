# `return GP;` (a `*S` global) and `return gp();` (a `: *S` call) from a fn returning a struct of 8 B or less return the POINTER's word; over 8 B both are refused by name — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (what `return <a *S>` means in a struct-returning fn). Verified
2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64): at 8 B `return GP;` and `return gp();` compile clean
and the caller's `s.v` is `&GS`; at 16 B both are refused by name; at 24 B both are refused (other messages). A
`*S` LOCAL (`return p;`) returns the pointer at 8 B and the pointee at 16 B and 24 B — that shape is already staged in
[`2026-10-12-small-struct-return-takes-another-structs-value.md`](2026-10-12-small-struct-return-takes-another-structs-value.md)
(its proposed fix 2: copy through it), and is listed here only so the decision covers the three together.
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** Medium — silent at 8 B or less: the caller reads an address as the struct's field.
**Affects:** the 6.7.10 tree (measured there only); the `return` classes are frontend-only, so every target.

## Summary

| `return` in `fn f(): S` | S of 8 B | S of 16 B | S of 24 B |
|---|---|---|---|
| `return p;` (`p: *S` local) | the pointer's word (staged issue) | the pointee (8) | the pointee (8) |
| `return GP;` (`var GP: *S`) | **the pointer's word** | refused: "… got `GP`" | refused: "identifier is not a local" |
| `return gp();` (`fn gp(): *S`) | **the pointer's word** | refused: "… got `gp`" | refused: "return must be a bare local identifier, or a call …" |

6.7.10's decision 6 makes struct copies size-independent (`l = GP`, `l = gp()` copy the pointee at every size); the
`return` side has no rule for a `*S` global or call.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/rg8.cyr <<'EOF'
struct S8 { v; }
var GS = S8 { 0 };
var GP: *S8 = 0;
fn gp(): *S8 { return &GS; }
fn f2(): S8 { return GP; }
fn f3(): S8 { return gp(); }
fn main(): i64 { GS.v = 9; GP = &GS; var b: S8 = f2(); var c: S8 = f3(); return (b.v == &GS) + (c.v == &GS) * 2; }
syscall(60, main());
EOF
build/cycc < /tmp/rg8.cyr > /tmp/rg8 && chmod +x /tmp/rg8 && /tmp/rg8; echo $?    # 3: both are &GS (9 and 9 if copied)
sed 's/S8 { v; }/S16 { v; w; }/; s/S8 { 0 }/S16 { 0, 0 }/; s/S8/S16/g' /tmp/rg8.cyr > /tmp/rg16.cyr
build/cycc < /tmp/rg16.cyr > /tmp/rg16; echo $?
# 1: a fn returning the 9-16 byte struct `S16` is returned in two registers, so `return` takes a local of that
#    struct or a call returning it — got `GP` (and `gp`)
```

## Root cause

`_ret_small_ptrp` (`src/frontend/parse_fn.cyr:2184`), the only `return IDENT;` struct arm at 8 B or less, takes a
`*T` PARAMETER or a handle; a global goes to `_ret_small_gh` (`src/frontend/parse_decl.cyr:8043`), which takes only a
handle global. A typed `*S` global is neither, and `return gp();` is not a name, so both reach the scalar tail, which
loads the pointer's word. The 9–16 B (`_ret_struct_pair`, `parse_fn.cyr:2124`) and > 16 B (`_ret_struct_big`, `:2026`)
classes accept only a local or a same-struct call and refuse the rest.

## Proposed fix

The user's call, one of:

- **(a) Return the pointee at every size** (decision 6's rule on the `return` side): a `*S` local, global or call copies
  the struct it points at, at 8 B or less, 9–16 B and > 16 B alike; a `*U` of another struct refused by name. Changes
  what 8 B programs compute; 16 / 24 B refusals start compiling.
- **(b) Refuse by name at every size** what is not a struct value (a `*S` global, a `: *S` call; and the `*S` local,
  which today returns the pointee over 8 B — that refusal would stop code compiling).
- **(c) Leave it**: the 8 B word return stays, documented in the guide.

Rows either way: each shape at 8 / 16 / 24 B in a `.tcyr` or a refusal gate, mutation-proven.

## Consumer-side workaround

Copy through the pointer first: `var c: S8 = GP; return c;` (decision 6 copies the pointee at every size).
