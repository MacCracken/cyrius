# An inline `Str` (from a `Str { .. }` literal) used as a `Str` value passes its `data` word, not a handle: `f(t)` with `fn f(s: Str)` reads the wrong length, silently — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`bc8370b9`, `build/cycc`
2,057,744 B) and the cross compilers built from it: `f(t)` for `fn f(s: Str) { return str_len(s); }` and
`var t: Str = Str { "abcdefg", 7 };` compiles with no diagnostic and exits 0 on x86_64, aarch64 (qemu), cx (cxvm) and
PE (wine), where 7 is right. `f(&t)` exits 7 on all four. A user struct of the same shape (`struct U { data; len; }`,
`fn g(s: U) { return s.len; }`) passes right: `g(u)` with `len` 37 gives 37. The installed 6.6.0, 6.6.10, 6.7.0 and
6.7.9 compilers give 0 on x86_64.
**Placement:** unplaced — the user's call.
**Discovered:** 2026-10-12, the 6.7.10 B7 synthesis plan (probe S9): its first cstring encoder for `#derive(Serialize)`
wrapped the C string in a stack `Str` and passed it by name (`str_builder_add_json_str(sb, t)`), which encoded `""`.
B7-4 passes `&t` instead (its mutant M29 pins it).
**Severity:** Medium. A silently wrong value on every target from source that compiles clean, and nothing refuses or
warns. The shape is rare: no `Str { .. }` literal appears in `lib/`, `programs/`, `cbt/` or `tests/tcyr/`.
**Affects:** cycc 6.6.0 – the 6.7.10 tree (measured at 6.6.0, 6.6.10, 6.7.0 and 6.7.9 on x86_64, and at the tree on
all four targets; not bisected further). Every place an inline `Str` is used as a `Str` value: an argument to a `: Str`
parameter (stdlib fns included), a declaration or an assignment into a `Str`, and `return t;` from a `: Str` fn. Local
and global alike. `Result` / `Option` / `Tagged` (the other by-name types) were not probed.

## Summary

`Str` is a heap handle by name: a `Str` slot holds the address of a 16 B `{ data; len; }` header, so a `: Str`
parameter is passed by value (one word) and `a = b` between two `Str`s is a rebind (guide § *Where a struct lives*:
"`Str`, `Result`, `Option` and `Tagged` (heap handles by name) … are unchanged"). Every `Str` consumer is built on
that.

A `Str { .. }` literal breaks it. `var t: Str = Str { p, 7 };` makes an INLINE 16 B aggregate on the frame, with no
handle word anywhere. Field reads are right (`t.len` is 7), but every use of the bare name `t` as a `Str` value takes
the slot's content, which is field 0, the `data` pointer. The callee then treats `data` as the header and reads
`load64(data + 8)` as the length (whatever bytes follow the string). `fn f(s: Str) { return s; }` called with `f(t)`
returns `p`, not `&t` (measured). The encoder case: `str_builder_add_json_str(sb, t)` writes `""`, while
`str_builder_add_json_str(sb, &t)` writes `"a\"b"`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
fn main() { var t: Str = Str { "abcdefg", 7 }; return f(t); }
var r = main();
syscall(SYS_EXIT, r);
```

```sh
cd /home/macro/Repos/cyrius
cat /tmp/istr.cyr | build/cycc > /tmp/istr && chmod +x /tmp/istr && /tmp/istr; echo $?   # 0, want 7
cat src/main_aarch64.cyr | build/cycc > /tmp/cc_a64 && chmod +x /tmp/cc_a64
cat /tmp/istr.cyr | /tmp/cc_a64 > /tmp/istr_a && chmod +x /tmp/istr_a && qemu-aarch64 /tmp/istr_a; echo $?   # 0
```

Every row compiles with no diagnostic. Each is the program above with its `f` / `main` replaced; "want" is the length
a `Str` handle to `t`'s header gives. Measured on x86_64 / aarch64 (qemu) / cx (cxvm) / PE (wine), all four equal:

| shape | want | all four targets |
|---|---|---|
| `return f(t);` | 7 | 0 |
| `return f((t));` | 7 | 0 |
| `return str_len(t);` (a stdlib `s: Str` parameter) | 7 | 0 |
| `fn f(k, s: Str) { return str_len(s) + k; }` … `return f(30, t);` | 37 | 30 |
| `var gt: Str = Str { "abcdefg", 7 };` (a global) … `return f(gt);` | 7 | 0 |
| `var h: Str = t; return f(h);` | 7 | 0 |
| `var h = str_from("zz"); h = t; return f(h);` | 7 | 122 (the byte after `"abcdefg"`'s NUL: the next literal's `z`) |
| `fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return t; }` … `var h = mk(); return f(h);` | 7 (or a refusal: `t` dies with the frame) | 0 |
| `return f(&t);` (the workaround) | 7 | 7 |
| `return t.len;` | 7 | 7 |
| control: `struct U { data; len; }`, `fn g(s: U) { return s.len; }`, `var u: U = U { "abc", 37 }; return g(u);` | 37 | 37 |

## Root cause

The by-name convention ("a `Str` slot holds a heap handle") is asked by name, never of the slot. Each consumer that
skips `Str` assumes the slot holds the handle, and an inline `Str`'s slot holds field 0:

- **Arguments.** `_param_wants_struct_ptr` (`src/frontend/parse_fn.cyr:11901`) returns 0 for a
  `_classify_param_type` class-1 (`Str`) parameter, so the callee's `_fnt_structmask` bit is clear and
  `_try_push_struct_addr_arg` (`parse_fn.cyr:1569`) never pushes `&t`; the argument takes the plain value push, which
  loads `t`'s first slot.
- **Assignment.** `_agc_plain_big` (`src/frontend/parse.cyr:2826`) excludes `Str` by the same classifier, so `h = t`
  is not a copy-assign operand pair and falls to the one-word store of `t`'s first slot.
- **Declaration and return.** `var h: Str = t;` and `return t;` from a `: Str` fn move the same first word.

Nothing marks an inline `Str` as different from a handle `Str`: both are `SLTYPE = -sid` of the same sid; only `GLAGG`
(inline 1, handle 0) tells them apart, and none of the by-name exclusions read it.

## Proposed fix

What an inline `Str` MEANS where a `Str` handle is taken is the user's call (it changes what such a program does, or
makes it stop compiling). One-line question: **should `var t: Str = Str { .. }` (1) make the bare name `t` its header's
address wherever a `Str` value is taken, refusing by name the uses that escape the frame (`return t;`, a store into a
global, a field or the heap); (2) allocate the 16 B header, so `t` is an ordinary handle and every consumer is right;
or (3) be refused by name (a by-name handle type has no inline form; `str_new(p, n)` is the spelling)?**

(1) is the `&t` workaround made automatic, with no allocation; it keys on `GLAGG(S, li) == 1` at the argument push
(`_try_push_struct_addr_arg` / `_sarg_byval_small`), the copy-assign classifier, PARSE_VAR's copy-init and the return
path. (2) moves the literal's storage class (the assignment `t.len = 3` would then write the heap header). (3) breaks
only `tests/gates/diagnostics/str_cstring_arg_shapes.sh`'s `var gv: Str = Str { 0, 0 };` row, which declares its own
`struct Str` to test a warning and would take `0` instead.

**Rows**, mutation-proven (each arm reverted → RED), on x86_64, aarch64 (qemu, then pi), cx (cxvm) and PE (wine, then
cass): the table above, plus a `#derive(Serialize)` struct with a `Str` field encoded from an inline `Str`, and the
same shapes through a method (`self`), a generic `T = Str`, a closure capture of `t` and `defer`. The control row and
`f(&t)` stay green.

## Consumer-side workaround

Pass `&t` (`f(&t)`, `str_builder_add_json_str(sb, &t)`) — right on all four targets — or build the `Str` as a handle
(`var t = str_new(p, n);`). Never return or store an inline `Str`: its header dies with the frame.
