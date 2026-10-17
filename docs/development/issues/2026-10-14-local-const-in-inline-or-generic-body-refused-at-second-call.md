# A local `const` in an `#inline` fn or a generic fn makes its second call in one scope a refusal — "'L' is already declared in this scope" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F2: the lane's compiler
before the unit, 2,189,840 B) and on the installed 6.7.2 and 6.7.9 compilers: identical everywhere.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F2 (probing a private const fn called from a local const in an
`#inline` body, for `issues/archived/2026-10-09-const-context-calls-private-const-fn.md`), outside that issue's scope.
**Severity:** Medium — valid code is refused. A helper that names a local const cannot be called twice in one scope
when it is `#inline` or generic, and the error names the helper's own line, not the second call.
**Affects:** cycc 6.7.2 (local `const`) through the 6.7.11 genfe lane tree.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf '#inline\nfn w(): i64 { const L = 3; return L; }\nfn main(): i64 { return w() + w(); }\nsyscall(60, main());\n' > /tmp/il.cyr
build/cycc < /tmp/il.cyr > /tmp/il; echo $?
```

```
error:<source>:2:21: 'L' is already declared in this scope
    fn w(): i64 { const L = 3; return L; }
                        ^
1
```

Expected: builds, exits 6.

| program | result |
|---|---|
| `#inline fn w(): i64 { const L = 3; return L; }`, `return w() + w();` | refused, 2:21 |
| the same, `var a = w(); var b = w(); return a + b;` | refused, 2:21 |
| the same, `var a = w(); if (a == 3) { a = a + w(); } return a;` (the second call in a nested block) | builds, exits 6 |
| the same, one call `var a = w(); return a;` | builds, exits 3 |
| `fn gg<T>(x: T): i64 { const L = 3; return L; }`, `return gg(1) + gg(2);` (one instance, twice) | refused, 1:29 |
| the same, `gg(1) + gg(a)` with `a: i32` (two instances) | refused, 1:29 |
| the same, `var r = gg(a); var s = gg(a);` | refused, 1:29 |
| the same, the two calls in two different fns | builds, exits 6 |
| a plain `fn gg(x): i64 { const L = 3; return L; }`, `gg(1) + gg(2)` | builds, exits 6 |
| `#inline fn w(): i64 { var L = 3; return L; }`, `w() + w()` (a `var`: `#inline ignored`) | builds, exits 6 |
| two sibling `if` blocks in one fn, each `const L = ..;` | builds, exits 9 |

## Root cause

`src/frontend/parse_fn.cyr` at the lane tree (after unit F2):

- The inline replay (PARSE_FNCALL's INLINE PATH, `if (GFINL(S, fi) != 0) …`, :6579) re-parses the callee's
  body at the call site with the inline depth `GIDEP + 1` and the scope depth `GSDEP + 1`, and puts both back at the
  end. A generic fn's call takes the same path (`_bind_inl_generic`, :6682) — every generic call measured above.
- A local const is an `_lc_tab` row: name, scope depth, inline depth, kind, value (`_lc_push`, :9778). Rows are trimmed
  only when a fn ends (`PARSE_FN_DEF` saves and restores `_lc_n` / `_lc_floor`, ~:15106). `_lc_pop` (:9587) has no
  caller, and the replay does not save `_lc_n`, so the first replay's `L` row outlives the replay.
- `_lc_dup_check` (:9794) refuses a name whose row has the same scope depth AND the same inline depth. The second replay
  in the same enclosing scope runs at exactly the same `(GSDEP + 1, GIDEP + 1)` as the first, so it meets the first
  replay's row: "already declared in this scope". A replay in a nested block runs one scope deeper and passes.

## Proposed fix

Save `_lc_n` before the inline replay and restore it after (as `PARSE_FN_DEF` does for a body), so a replay's local
consts end with the replay. Rows: the table above (each builds and gives its value), on x86_64 and one cross target;
a replay's const is still invisible to the caller after the call (`w(); return L;` refused as an unknown name).
