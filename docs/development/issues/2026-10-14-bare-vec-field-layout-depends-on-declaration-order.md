# A bare `Vec` struct field's size depends on whether a `struct Vec` is declared above or below the struct that uses it — the same text gives two layouts (the 6.6.10 order-dependent-layout class) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 with the 6.7.11 tools lane's `build/cycc` (the fixpoint of
l6711-tools @ a3d9837d; the arm below is unchanged since the 6.4.x `Vec<T>` field work).
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D10 — (b).
**Discovered:** 2026-10-14 by the 6.7.11 tools lane's review of the header struct-return bite. `cyrius header` now
mirrors today's behaviour (a bare `Vec` field is the file's own `struct Vec` when one is declared above it, else the
8-byte handle — commit 3624e00f); the compiler's order dependence itself is this issue.
**Severity:** Medium — a silent layout change at rc 0: moving a `struct Vec` declaration below its user shrinks every
struct holding a bare `Vec` field (48 B -> 16 B below), so `sizeof`, field offsets and the return class (pair vs result
pointer) all change with no diagnostic. Any other struct field type declared below its use is refused since 6.6.10.
**Affects:** src/frontend/parse_types.cyr PARSE_STRUCT_DEF and PARSE_UNION_DEF, the bare-`Vec` field arm.

## Reproduction

```sh
PZ='fn pz(n): i64 { var d[24]; var i = 22; store8(&d + 23, 10); if (n == 0) { store8(&d + i, 48); i = i - 1; } while (n > 0) { store8(&d + i, 48 + n % 10); n = n / 10; i = i - 1; } syscall(1, 1, &d + i + 1, 23 - i); return 0; }'
printf '%s\n' 'struct Vec { x; y; z; }' 'struct Ray { o: Vec; d: Vec; }' "$PZ" 'pz(sizeof(Ray));' 'syscall(60, 0);' > va.cyr
printf '%s\n' 'struct Ray { o: Vec; d: Vec; }' 'struct Vec { x; y; z; }' "$PZ" 'pz(sizeof(Ray));' 'syscall(60, 0);' > vb.cyr
printf '%s\n' 'struct Ray { o: Q; d: Q; }' 'struct Q { x; y; z; }' "$PZ" 'pz(sizeof(Ray));' 'syscall(60, 0);' > vq.cyr
for v in va vb vq; do build/cycc < $v.cyr > $v; echo "$v cycc rc=$?"; chmod +x $v; ./$v; done
```

```
actual:
va cycc rc=0
48                                 <- struct Vec declared above Ray: two 24-byte Vec fields
vb cycc rc=0
16                                 <- the same two declarations swapped: two 8-byte handles
vq cycc rc=1
error:<source>:1:18: struct field type 'Q' is declared after its use; declare it before 'Ray'
    struct Ray { o: Q; d: Q; }
                     ^             <- every other name declared below its use is refused (6.6.10)

expected: one layout for one text — the user's decision between (a) a bare `Vec` field is always the 8-byte handle
          (lib's untyped `Vec`, as `Vec<T>` is), a file's own `struct Vec` notwithstanding, or (b) a bare `Vec`
          field naming a file's own `struct Vec` declared BELOW its use is refused by name, as `_sfield_named`
          refuses any other such name.
```

## Root cause

PARSE_STRUCT_DEF's bare-`Vec` arm (src/frontend/parse_types.cyr, `ftname & 0xFFFFFFFF == 0x636556` without a
following `<`):

```cyrius
var _bsid = FINDSTRUCT(S, tnoff);   # a bare `Vec`: an untyped 8-byte handle
ADDFIELDTYPED(S, si, fnoff, _bsid);
```

FINDSTRUCT answers the file's own `struct Vec` when it has been parsed already, else -1 (the 8-byte handle). This arm
bypasses `_sfield_named`, which since 6.6.10 refuses a struct field type declared below its use. PARSE_UNION_DEF's
parallel copy has the same two lines.

## Proposed fix

Per the decision above, in both arms (struct and union). With (b), `cyrius header`'s mirror
(cbt/quality.cyr `_hdr_type_size`, the bare-`Vec` branch) keeps its declared-above rule and the declared-below case
becomes a compile error, so the header row H8 "declared below the field: the 8-byte handle" is replaced by the
refusal; with (a), the header's branch returns to `Vec -> 8`. Rows: a struct-layout gate (both orders, struct and
union), tests/gates/toolchain/header_spellings_and_size.sh H8.
