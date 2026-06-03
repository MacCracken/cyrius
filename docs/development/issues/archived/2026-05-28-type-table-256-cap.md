> **RESOLVED v6.0.47** — struct/type-table cap 256 → 1024 (+ struct field cap 32 → 256) via a packed field pool; the silent overflow now fails loud (`struct field pool exhausted` + `#derive` cap-64 guard). See CHANGELOG [6.0.47].

# 2026-05-28 — type/struct table caps at 256 entries (silent FAIL, no diagnostic)

**Filed:** 2026-05-28 (issue doc 2026-06-02; repro existed orphaned in
`issues/repros/`). **Severity:** Medium — hard ceiling on structs/enums/type
aliases per compilation unit, AND the overflow is a **silent failure** (bare
"compile … FAIL", exit 1, no error text) which is itself a diagnostics bug.
**Affects:** the compile-state type table. Verified cyrius 6.0.14, x86_64
Linux. Repro: `issues/repros/2026-05-28-type-table-256-cap.cyr` (257 structs).

## Summary

The type/struct table caps at **256 entries** — plain `struct`,
`#derive(accessors)` struct, `enum`, and type aliases all share the table and
count the same. A unit with 257 of them fails to build with **no diagnostic**:

```
cyrius build 2026-05-28-type-table-256-cap.cyr out    # -> "compile ... FAIL", exit 1
```

Delete any one (256 total) and it builds. Two distinct defects:

1. **The cap (256)** — a fixed-size table; raise it (and/or make it dynamic).
2. **The silent fail** — overflow must emit a real diagnostic
   (`error: too many types (max N)` with the table location), not a bare
   FAIL. This is the worse half: a wide-program author gets no clue.

## Fix

- Locate the type-table cap (compile-state struct; sibling of the struct-field
  cap at `lex_pp.cyr` S+0x194600 and the secret/defer block table at
  `parse.cyr` S+0x18F900). Raise the entry cap.
- Add the missing overflow diagnostic at the table-insert site.

## Bundle note

Part of the **compiler table-cap raises** cluster (one well-packed release):
- struct field cap 32→64/128 — `proposals/2026-06-02-struct-field-cap-raise.md`
  (avatara 2.5.0 blocked).
- secret/defer block per-fn cap 8→32 —
  `issues/2026-05-27-secret-defer-block-per-fn-cap.md` (sigil, P4).
- type table 256→larger + the silent-fail diagnostic (this issue).
All three are fixed-size tables in the compile-state struct; raising them is
the same shape of change and ships together.

## Target (user-set 2026-06-02)

type/struct table cap **256 → 1024** + add the overflow diagnostic. Table-cap bundle, after platform repairs.
