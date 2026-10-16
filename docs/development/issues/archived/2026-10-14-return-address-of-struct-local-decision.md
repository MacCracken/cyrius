# `return &s;` in a fn returning the struct `S`: at 8 B or less the ADDRESS is the struct's word; over 8 B it is refused in other words — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.13** (ST-10, `ac17a963`; ST-10r, `95516c2f`; ST-20, `f48f6904`: `return &s;` in a fn declared `: S` is `return s;` at every size — the user's decision D4 (a), 2026-10-15. The filed `ra.cyr` exits 1 (was 0: `c.v` held &s) on x86_64, aarch64, cx and PE; at 3 B the fields read 145 on the four (were the address's bytes), at 16 B 34 and at 24 B 145 (both were refused in other words). `&s` of a local, `&G` of a value global and `&p` of a by-value parameter, wrapped or not, are each a copy. `&u` of another struct is refused by name at every size ("… got `&u` (a `*U`)"), and `return &w.s;` — the address of a field — gets D3 (b)'s one message at every size (ST-10r: the pair and retptr classes' own refusals no longer come first or alone). Rows: new `crossos/struct_return_address_of.tcyr` (22 rows; `small_struct_handle_line.sh` R13a on x86_64 plain / IR=1 / IR=3 / DCE=1, aarch64, cx, PE), `small_struct_return_type_refused.sh` R17-R23, R23b-R23d and A11-A13 (refusal floor 27, acceptance floor 13), `hidden_temp_census.sh` counts `_ret_addr_field` (ST-20); mutations RED. Filed beside it (6.7.14, a decision): `return &h;` of a handle / `*S` local / untyped `self` still returns the slot's address as the word at 8 B. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN — a decision for the user** (what `return &s;` means in a fn declared `: S`). Measured 2026-10-14
on the 6.7.11 struct lane (`l6711-struct`, after unit S3), x86_64.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D4 — (a).
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S3), writing the guide paragraph for
issues/archived/2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md (decision (a): a `*S` local, global,
call or field returns the struct it points at, at every size). `&s` is no `*S` to the compiler's typing (`_hl_psid`
answers 0 for `&x`), so that decision does not reach it; the argument side treats it as a pointer (6.7.10 decision 7:
`bs1(&s)` into a by-value `S1` passes the struct).
**Severity:** Medium — silent at 8 B or less: the caller reads a stack address (of a dead frame) as the struct's
field.
**Affects:** every compiler measured (the 8 B behaviour is the scalar tail's); every target (frontend).

## Reproduction

```sh
cat > /tmp/ra.cyr <<'X'
struct S8 { v; }
fn h(): S8 { var s: S8; s.v = 3; return &s; }
fn main(): i64 { var c: S8 = h(); return c.v == 3; }
syscall(60, main());
X
build/cycc < /tmp/ra.cyr > /tmp/ra && chmod +x /tmp/ra && /tmp/ra; echo $?     # 0: c.v is &s, not 3
```

| `return &s;` in `fn h(): S` | S of 8 B | S of 16 B | S of 24 B |
|---|---|---|---|
| `s` a local of S | the address as the word (exit 0 above) | refused: "… two registers … got `this expression`" | refused: "struct-return fn: return must be a bare local identifier …" |

## Options

- **(a) The struct `&s` points at, at every size** — as decision 7 reads `&s` into a by-value parameter and decision
  (a) of the issue above reads a `*S`: `return &s;` is `return s;`. Changes what 8 B programs compute; the 16 / 24 B
  refusals start compiling.
- **(b) Refuse by name at every size** (`&s` is an address, not a struct value): stops 8 B programs compiling.
- **(c) Leave it** (documented: the guide's *Returning a struct by value* says `&s` is an untyped address).

Rows either way: 3 / 8 / 16 / 24 B, `&s` of a local, a global (`&G`), a field (`&w.s`), wrapped; a mutant RED.
