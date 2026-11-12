# Allocation failure: the `#derive(Serialize)` reader memsets a refused allocation, and serialization can only exit — OPEN

**Status:** 🟡 **OPEN**, filed 2026-11-07 against 6.7.18 @ a1cf8c026 with `repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation.cyr` and `repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation-real-heap.cyr`.
**Placement:** unpinned.
**Discovered:** 2026-11-07, from garjan 2.6.3's audit (`docs/audit/2026-11-07-audit-3.md` §3), whose fault-injection sweep refused each allocation in turn across 9,238 cases. Each case was re-verified here.
**Severity:** Medium. The reader segfaults or returns silently zeroed fields, and the writer can only exit. Reachable without a hook, under an address-space limit.
**Affects:** cycc 6.7.18 (tag `6.7.18`, `a1cf8c026`, also `main`), the derive pass and `lib/str.cyr`.

## Summary

garjan 2.6.3's fault-injection sweep found three defects on cyrius 6.7.18's allocation-failure path. The sweep refuses each allocation in turn, one process per case. All three are filed together because two of them meet in the derive's emitted writer.

1. **The derive reader faults.** The emitted `Name_from_json_str` begins `var ptr = alloc(N); memset(ptr, 0, N);` with no check, and `Name_from_json(pairs)` stores fields through the same unchecked pointer. Both segfault when that allocation is refused, even though 0 is already their failure return.
2. **The derive reader drops fields silently.** If a later allocation inside the reader is refused, the reader still returns a non-null struct, with that field left at 0. The allocations in question are the pairs form's `str_from("<field>")` key and a `Str` field's decoded copy. The caller cannot tell the result from a document that set the field to 0.
3. **Serialization has no way to report a refused allocation.** The emitted `Name_to_json(ptr, sb)` calls only the back-compat `str_builder` verbs and always returns 0. Those verbs exit(1) when a grow is refused, by design since CYRIUS-2026-0004. Four verbs have no `_a` form that reports instead: `str_builder_putc`, `str_builder_add_byte`, `str_builder_add_json_str` and `str_builder_add_json_cstr`. A program that serializes through the derive therefore cannot survive running out of memory. Separately, `str_join` does not check `str_builder_new()` and faults instead of exiting.

All three happen without any test hook. The stdlib's bump `alloc` returns 0 when it cannot map a new chunk (`lib/alloc.cyr:324-326`), for example under `ulimit -v`. Repro 2 below crashes the reader that way.


## Where

### 1 and 2: the derive reader, `src/frontend/lex/pp/serialize.cyr`

`Name_from_json_str`, `serialize.cyr:411-413`:

```cyrius
    op = op + PP_EMIT_STR(out, op, "_from_json_str(json) {\nif (json == 0) { return 0; }\nvar ptr = alloc(");
    op = op + PP_EMIT_INT(out, op, cumul_off);
    op = op + PP_EMIT_STR(out, op, ");\nmemset(ptr, 0, ");
```

For the repro's 24-byte `Probe`, this emits:

```cyrius
fn Probe_from_json_str(json) {
if (json == 0) { return 0; }
var ptr = alloc(24);
memset(ptr, 0, 24);
```

`Name_from_json(pairs)`, `serialize.cyr:293-298`:

```cyrius
    op = op + PP_EMIT_STR(out, op, "_from_json(pairs) {\nvar ptr = alloc(");
    op = op + PP_EMIT_INT(out, op, cumul_off);
    op = op + PP_EMIT_STR(out, op, ");\nvar v = 0;\n");
    fi = 0;
    while (fi < field_count) {
        op = op + PP_EMIT_STR(out, op, "v = bayan_json_get_by_str(pairs, str_from(\"");
```

A refused `str_from` passes 0 as the key. `bayan_json_get_by_str` answers 0 for a 0 key, so the field keeps its zero and the function goes on to return `ptr`.

### 3: the derive writer and `lib/str.cyr`

The writer emits only the aborting verbs and then a constant 0: `serialize.cyr:137` (`str_builder_add_cstr(sb, "...`), `:239` (`str_builder_add_json_str(sb, load64(ptr + ...`), `:253` and `:272` (`str_builder_add_int(sb, ...`), and `:279`:

```cyrius
    op = op + PP_EMIT_STR(out, op, "str_builder_add_cstr(sb, \"}\");\nreturn 0;\n}\n");
```

`lib/str.cyr:669-676`, quoted from garjan's vendored `lib/str.cyr`, which is byte-identical to the 6.7.18 stdlib:

```cyrius
fn str_builder_putc(sb, ch): i64 {
    if (_sb_grow(sb, 1) != 0) { syscall(1, 2, "str_builder: alloc failed\n", 26); _sb_die(); }
```

`str_builder_add_json_str` (`:121`) calls `str_builder_putc` once per output byte. `str_builder_add_json_cstr` (`:175`) and `str_builder_add_byte` (`:795`) have the same shape. Unlike `str_builder_add_a`, `str_builder_add_cstr_a` and `str_builder_add_int_a`, none of the four has an `_a` form.

`str_join`, `lib/str.cyr:723-735`:

```cyrius
    var sb = str_builder_new();
    var ji = 0;
    while (ji < plen) {
        if (ji > 0) { str_builder_add(sb, sep); }
```

## Reproduction

Both programs are also in this folder: [`repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation.cyr`](repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation.cyr) is `repro.cyr` and [`repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation-real-heap.cyr`](repros/2026-11-07-derive-serialize-reader-memsets-a-refused-allocation-real-heap.cyr) is `real.cyr`. Copy them into a scratch project next to the `cyrius.cyml` shown below.

### 1. Refuse the Nth allocation (deterministic)

The compiler keeps the last definition of a function, and says so: `warning: duplicate fn 'alloc' (last definition wins; first defined in lib/alloc.cyr)`. The repro therefore defines its own `alloc`. It refuses the Nth request made after `fi_arm(N)` and serves every other request from a private zeroed mmap, as the stdlib does.

`cyrius.cyml`:

```toml
[package]
name = "cyrius_oom_repro"
version = "0.1.0"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "repro.cyr"
output = "build/repro"

[deps]
stdlib = ["syscalls", "string", "alloc", "str", "fmt", "vec", "io", "args", "math", "bayan"]
```

`repro.cyr`:

```cyrius
# cyrius 6.7.18: allocation failure in #derive(Serialize) and lib/str.cyr.
#
# Replaces the stdlib `alloc` (the compiler keeps the last definition) with a
# bump allocator that refuses the Nth allocation made after fi_arm(N). Every
# other request is served from a private zeroed mmap, as the stdlib does.
#
# usage: repro CASE N
#   1 Probe_from_json_str("{\"rate\":1.5,\"kind\":2}")       (derive reader)
#   2 Probe_to_json(p, sb) into a 64-byte builder, 70 bytes   (derive writer)
#   3 str_builder_putc on a full builder                       (no fallible form)
#   4 str_join(["a","b"], ",")                                 (unchecked str_builder_new)
#   5 Probe_from_json(pairs)                                   (derive reader, pairs form)
# Prints the return value if the call returns; a segfault is 139.

#derive(Serialize)
struct Probe {
    rate: f64;
    kind: i64;
    label: Str;
}

var FI_ARMED = 0;
var FI_COUNT = 0;
var FI_N = 0;
var FI_BASE = 0;
var FI_PTR = 0;
var FI_END = 0;

fn alloc(size): i64 {
    if (size <= 0) { return 0; }
    if (FI_ARMED == 1) {
        FI_COUNT = FI_COUNT + 1;
        if (FI_COUNT == FI_N) { return 0; }
    }
    if (FI_BASE == 0) {
        FI_BASE = syscall(9, 0, 0x4000000, 3, 0x22, 0 - 1, 0);   # 64 MiB, RW, private anon
        FI_PTR = FI_BASE;
        FI_END = FI_BASE + 0x4000000;
    }
    size = (size + 7) & (0 - 8);
    if (FI_PTR + size > FI_END) { return 0; }
    var p = FI_PTR;
    FI_PTR = p + size;
    return p;
}

fn fi_arm(n) { FI_COUNT = 0; FI_N = n; FI_ARMED = 1; return 0; }
fn fi_disarm() { FI_ARMED = 0; return FI_COUNT; }

fn main() {
    args_init();
    var which = atoi(argv(1));
    var n = atoi(argv(2));
    var r = 0;
    # Everything the cases need is built before arming.
    var p = alloc(sizeof(Probe));
    store64(p, f64_div(f64_from(3), f64_from(2)));
    store64(p + 8, 2);
    store64(p + 16, str_from("a label long enough to overflow the inline buffer"));
    var sb = str_builder_new();
    var full = str_builder_new();
    var i = 0;
    while (i < 64) { str_builder_putc(full, 120); i = i + 1; }
    var parts = vec_new();
    vec_push(parts, str_from("a"));
    vec_push(parts, str_from("b"));
    var sep = str_from(",");
    var pairs = bayan_json_parse(str_from("{\"rate\":1.5,\"kind\":2,\"label\":\"x\"}"));

    fi_arm(n);
    if (which == 1) { r = Probe_from_json_str("{\"rate\":1.5,\"kind\":2,\"label\":\"x\"}"); }
    if (which == 2) { r = Probe_to_json(p, sb); }
    if (which == 3) { r = str_builder_putc(full, 121); }
    if (which == 4) { r = str_join(parts, sep); }
    if (which == 5) { r = Probe_from_json(pairs); }
    fi_disarm();
    fmt_int(r);
    syscall(1, 1, " returned", 9);
    if ((which == 1 || which == 5) && r != 0) {
        syscall(1, 1, ", kind = ", 9);
        fmt_int(load64(r + 8));
        syscall(1, 1, ", label = ", 10);
        if (load64(r + 16) == 0) { syscall(1, 1, "(null)", 6); }
        else { syscall(1, 1, str_data(load64(r + 16)), str_len(load64(r + 16))); }
    }
    syscall(1, 1, "\n", 1);
    return 0;
}
```

```sh
cyrius deps
CYRIUS_SYMS=syms.txt cyrius build repro.cyr build/repro
for c in 1 2 3 4 5; do for n in 0 1 2 3 4 5; do ./build/repro $c $n; echo "case $c N=$n exit=$?"; done; done
```

Observed results follow. Exit 139 is SIGSEGV. N=0 refuses nothing and is the control, and every case passes with it: the decoded struct reads `kind = 2, label = x`. The faulting function was resolved against the `CYRIUS_SYMS` file under gdb.

| Case | Call | Refused allocation | Exit | Result |
|---|---|---|---:|---|
| 1 | `Probe_from_json_str(...)` | N=1, the struct | 139 | faults in `memset` ← `Probe_from_json_str` |
| 1 | | N=2, N=3, the `label` decode | 0 | non-null, `label = (null)`; the document says `"x"` |
| 5 | `Probe_from_json(pairs)` | N=1, the struct | 139 | faults in `Probe_from_json` |
| 5 | | N=3, `str_from("kind")` | 0 | non-null, `kind = 0`; the document says `2` |
| 5 | | N=4, `str_from("label")`; N=5, its decoded copy | 0 | non-null, `label = (null)` |
| 2 | `Probe_to_json(p, sb)` | N=1, the first grow | 1 | `str_builder: alloc failed`, process exits |
| 3 | `str_builder_putc(full, 'y')` | N=1, the grow | 1 | `str_builder: alloc failed`, process exits |
| 4 | `str_join(["a","b"], ",")` | N=1, `str_builder_new` | 139 | faults in `_sb_grow_a` ← `str_builder_add` ← `str_join` |
| 4 | | N=2, N=3, the build | 0 | returns 0, which is correct |

### 2. A really exhausted heap (no override)

`real.cyr`, in the same project:

```cyrius
# No fault injection: the real stdlib alloc, run under `ulimit -v`.
# Exhaust the heap, then decode through #derive(Serialize).
#derive(Serialize)
struct Probe {
    rate: f64;
    kind: i64;
}

fn main() {
    var p = 1;
    while (p != 0) { p = alloc(1048576); }
    p = 1;
    while (p != 0) { p = alloc(8); }
    syscall(1, 1, "heap exhausted; calling Probe_from_json_str\n", 44);
    var r = Probe_from_json_str("{\"rate\":1.5,\"kind\":2}");
    fmt_int(r);
    syscall(1, 1, " returned\n", 10);
    return 0;
}
```

```text
$ cyrius build real.cyr build/real
$ (ulimit -v 1048576; ./build/real; echo "exit=$?")
heap exhausted; calling Probe_from_json_str
exit=139
```

## Expected

1. `Name_from_json_str` and `Name_from_json` should return 0 when their struct allocation is refused. 0 is already their failure value: the v6.5.37 comment above `serialize.cyr:411` makes the same argument for a null `json`.
2. They should also return 0 when an allocation needed to read a field is refused, rather than a struct with that field zeroed. Today the reader treats a refused allocation as an absent value. They need to be told apart.
3. Serialization should have a path that reports a refused allocation instead of exiting:
   - `_a` forms of `str_builder_putc`, `str_builder_add_byte`, `str_builder_add_json_str` and `str_builder_add_json_cstr` that return -1 on a refused grow, like the existing `_a` verbs.
   - An emitted writer that uses them and returns -1 when any append fails, for example `Name_to_json_a(a, ptr, sb)`. Changing `Name_to_json` itself to return -1 would also work. But a caller that ignores its return would then get truncated JSON where today the process exits, so a separate form looks safer. The aborting verbs and the current `Name_to_json` can stay as they are.
   - `str_join` should return 0 when `str_builder_new()` is refused, as it already does when `str_builder_build` is refused.

## Suggested fix

- **Reader:** emit the check after each struct allocation. At `serialize.cyr:413`:

  ```cyrius
      op = op + PP_EMIT_STR(out, op, ");\nif (ptr == 0) { return 0; }\nmemset(ptr, 0, ");
  ```

  At `:295`:

  ```cyrius
      op = op + PP_EMIT_STR(out, op, ");\nif (ptr == 0) { return 0; }\nvar v = 0;\n");
  ```

  I have not compiled this. I did not rebuild cycc.
- **`str_join`:** add `if (sb == 0) { return 0; }` after `lib/str.cyr:726`. I checked this one by redefining `str_join` over 6.7.18 and rerunning case 4: N=1 now returns 0 and nothing faults.

## Context

These are items U2 and U3 in garjan's 2.6.3 audit (`docs/audit/2026-11-07-audit-3.md` §3). garjan uses `#derive(Serialize)` on 30 structs. It already checks every `str_builder_new` and `*_from_json_str` result, so a fixed reader needs no change in garjan. A new fallible writer would need garjan to switch to it.

The pairs form's nested-struct field has the same shape, though I did not reproduce it: `var np = <Nested>_from_json(bayan_json_parse(v)); memcpy(ptr + off, np, size);` (`serialize.cyr:367-373`) copies from `np` without checking it.
