# A branching fn in `src/common/util.cyr` makes cybs emit a broken `gen1` — mechanism UNKNOWN

**Status:** 🔴 **OPEN — P1, pinned to v6.5.33.** Reproduced repeatedly at v6.5.32; **not diagnosed**.
**Placement:** v6.5.33. `bootstrap/cybs.cyr` (the seed-assembled bootstrap compiler).
**Discovered:** 2026-08-20, while adding `ENUM_CONST_VAL` for the negative-enum work (v6.5.32).
**Severity:** **P1 — it constrains where compiler code may be written, for a reason nobody understands.**
No consumer impact and no shipped defect; the cost is that a core shared-helper file is
effectively closed to new branching code, and the constraint was found by accident.

## What was measured

Nine `seed-derive-cycc.sh` runs, each after a full `build/cycc` rebuild:

| what was added | where | seed chain |
|---|---|---|
| `fn F(x): i64 { return x; }` | `src/common/util.cyr` | ✅ OK |
| `fn F(x): i64 { var y = x; return y; }` | `src/common/util.cyr` | ✅ OK |
| `fn F(x): i64 { return x & 0x7FFFFFFFFFFFFFFF; }` | `src/common/util.cyr` | ✅ OK |
| `fn F(x): i64 { return x & 0x4000000000000000; }` | `src/common/util.cyr` | ✅ OK |
| `fn F(x): i64 { return (x >> 62) & 1; }` | `src/common/util.cyr` | ❌ BROKEN |
| `fn F(x): i64 { if (x != 0) { return x; } return 0; }` | `src/common/util.cyr` | ❌ BROKEN |
| `fn F(x): i64 { var r = x; if (x != 0) { r = 0; } return r; }` | `src/common/util.cyr` | ❌ BROKEN |
| literals hoisted to globals, branch kept | `src/common/util.cyr` | ❌ BROKEN |
| `fn F(x): i64 { if (x != 0) { return x; } return 0; }` | **`src/frontend/parse_expr.cyr`** | ✅ OK |

Failure mode: **cybs exits 0 and produces a `gen1` that links**, then `gen1` dies with
`SIGILL` (sometimes `SIGSEGV`) at step [4/5], compiling `src/main.cyr`. `build/cycc` compiles
every one of these variants correctly, so **only `seed-derive-cycc.sh` sees it**.

## What is NOT established

- **The mechanism.** "Position-specific to util.cyr" is a restatement of the table above, not a
  diagnosis. It is recorded that way in CLAUDE.md deliberately, as a hazard rather than a rule.
- **Whether it is a capacity ceiling.** Against: a branch-free fn of the same size is fine, and
  v6.5.31 added `PP_DERIVE_ENUM_BODY` — a large, heavily-branching fn — to `lex_pp.cyr` with
  the chain staying green. For: every branching fn tried in util.cyr failed, which is what a
  full table would look like.
- **Whether `>>` by a large shift count is a second, independent cybs bug.** The
  `(x >> 62) & 1` row has no `if` in it and still broke, so it may be its own defect rather
  than another instance of this one.
- **Which cybs structure is involved.** Its fixup table (r15+0x6200000, 16 B/entry, count at
  0x7600010) and return-patch table (r15+0x7500000, 8 B/entry, count at 0x7600040) were read
  and both have room in the tens of thousands of entries. Neither was instrumented.

## Reproducer

```sh
cd ~/Repos/cyrius
cp src/common/util.cyr /tmp/util.bak
python3 - <<'PY'
p='src/common/util.cyr'; s=open(p).read()
a='var _vecv_base = 0;    # 0x1D8000 enum_const_val'
open(p,'w').write(s.replace(a, a+'\nfn _cy_probe(x): i64 { if (x != 0) { return x; } return 0; }', 1))
PY
cat src/main.cyr | build/cycc > /tmp/p.bin && chmod +x /tmp/p.bin
cp /tmp/p.bin build/cycc.tmp && chmod +x build/cycc.tmp && mv -f build/cycc.tmp build/cycc
sh scripts/seed-derive-cycc.sh        # dies at [4/5] with SIGILL
cp /tmp/util.bak src/common/util.cyr  # restore
```

⚠ **Verify the artifact between rounds.** A first attempt at this bisection used a `re.sub`
with `DOTALL` that ate ~80 lines of `util.cyr`, and four "BROKEN" results were measuring a file
that no longer compiled at all. Check `wc -l` and that `build/cycc` still builds before
believing any round.

## Wanted (v6.5.33)

1. **Diagnose it.** Disassemble the bad `gen1` at its crash site and compare against the good
   one; find which cybs emit path produces the wrong bytes. `qemu`/`gdb` on `gen1` is the
   direct route — it is a static ELF with no dependencies.
2. **Determine whether `(x >> 62)` is a separate cybs bug** and file/fix it as such if so.
3. **Fix cybs**, or — if the cause turns out to be a genuine structural limit — raise it
   deliberately and record the new bound with a gate, rather than leaving a file-placement
   taboo in CLAUDE.md.
4. **A gate.** Whatever the cause, a probe that adds a branching fn to util.cyr and asserts the
   seed chain still derives would have caught this the day it appeared instead of years later.

## Why P1 rather than P2

Nothing is broken for a consumer today, but the constraint is invisible, undocumented until
now, and shaped like the class this project treats most seriously: **a bootstrap-compiler
defect that fails SILENTLY and is caught by exactly one gate.** If `seed-derive` had ever been
skipped — it was framed as a closeout-only check until v6.3.0 — this would have shipped a
broken seed chain.
