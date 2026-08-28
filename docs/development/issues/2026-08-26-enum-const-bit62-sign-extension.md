# Enum constants ≥ 2^62 are silently corrupted — the fold table packs its "is enum const" tag into bit 63 of the value

**Status:** 🔴 **OPEN** — reproduced on released **6.5.31 → 6.5.35**; **6.5.30 and earlier are correct**.
Silent wrong-code: no warning, no error, `--strict` clean, corpus green. The value is simply wrong at
runtime.
**Placement:** unpinned — but this is a live miscompile in five shipped releases and a shipping consumer
hit it, so it wants a slot rather than the backlog.
**Discovered:** 2026-08-26 while bumping **szal 2.1.0 → 2.1.1** (pin 6.5.2 → 6.5.35). Five test suites
and one fuzz harness went red with no compiler diagnostic.
**Severity:** **Critical** — silent data corruption of a documented language construct, per the severity
guide in [`README.md`](README.md). It is *not* a bootstrap or self-host regression, and a one-line
consumer workaround exists (use `var`), so downgrade to High if triage weighs the workaround more
heavily than the silence. Nothing about it is loud.
**Affects:** cycc **6.5.31 – 6.5.35** (bisected on released toolchains, below). All targets — this is
front-end constant folding, not codegen.

## Summary

An `enum` member whose initialiser has **bit 62 set** is decoded with the fold table's marker bit still
attached, so it comes back sign-extended from bit 62. `enum { K = 0x7FFFFFFFFFFFFFFF }` evaluates to
**-1**. `var` initialisers and inline expression literals are unaffected, which is why this survived
five releases and a 282/282 corpus.

The cause is an in-band tag: `parse_types.cyr` stores each enum member as `(1 << 63) | val` and uses the
sign bit to mean "this slot holds an enum constant". That encoding cannot distinguish *a negative value*
from *a positive value with bit 62 set*, and the decoder's disambiguation heuristic resolves the
ambiguity in favour of negatives — silently sacrificing the entire top quarter of the positive i64 range.

The trade is visible in the bisect: **6.5.30 rejects negative enum initialisers outright**
(`error: expected number, got '-'`) and gets every positive value right; 6.5.35 accepts negatives and
gets them right, and corrupts every positive ≥ 2^62.

## Reproduction

Repro source is committed at
[`repros/2026-08-26-enum-const-bit62-sign-extension.cyr`](repros/2026-08-26-enum-const-bit62-sign-extension.cyr):

```cyrius
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
enum E {
    A = 0x3FFFFFFFFFFFFFFF;
    B = 0x4000000000000000;
    C = 0x7FFFFFFFFFFFFFFE;
    D = 0x7FFFFFFFFFFFFFFF;
}
enum F { G = 9223372036854775807; }
var vD = 0x7FFFFFFFFFFFFFFF;
var a1 = fmt_int(A); var x1 = print(" ", 1);
var a2 = fmt_int(B); var x2 = print(" ", 1);
var a3 = fmt_int(C); var x3 = print(" ", 1);
var a4 = fmt_int(D); var x4 = print(" ", 1);
var a5 = fmt_int(G); var x5 = print(" ", 1);
var a6 = fmt_int(vD); var x6 = print("\n", 1);
var z = syscall(60, 0);
```

```sh
cyrius build --strict --no-deps repro.cyr /tmp/ep && /tmp/ep
```

| member | source value | expected | 6.5.35 actual |
|---|---|---|---|
| `A` | `0x3FFFFFFFFFFFFFFF` (2^62−1) | `4611686018427387903` | `4611686018427387903` ✅ |
| `B` | `0x4000000000000000` (2^62) | `4611686018427387904` | **`-4611686018427387904`** ❌ |
| `C` | `0x7FFFFFFFFFFFFFFE` | `9223372036854775806` | **`-2`** ❌ |
| `D` | `0x7FFFFFFFFFFFFFFF` | `9223372036854775807` | **`-1`** ❌ |
| `G` | `9223372036854775807` (decimal spelling) | `9223372036854775807` | **`-1`** ❌ |
| `vD` | same literal as a **`var`** | `9223372036854775807` | `9223372036854775807` ✅ |

The threshold is exactly 2^62: `A` is the largest correct value.

### Version bisect — released toolchains, one shim `CYRIUS_HOME` per version

Run outside any manifest directory, with a per-version `CYRIUS_HOME` (see
[`2026-08-22-versioned-wrapper-does-not-pin-cycc.md`](2026-08-22-versioned-wrapper-does-not-pin-cycc.md)
— invoking `versions/<v>/bin/cyrius` alone is **not** sufficient to select that `cycc`, which is what
made this take a while to see):

```
6.5.26   4611686018427387903  4611686018427387904  9223372036854775806  9223372036854775807  ✅
6.5.27   … ✅          6.5.28  … ✅          6.5.29  … ✅          6.5.30  … ✅
6.5.31   4611686018427387903 -4611686018427387904 -2 -1  ❌   <-- FIRST BAD
6.5.32   ❌   6.5.33  ❌   6.5.34  ❌   6.5.35  ❌
```

**Last good 6.5.30 · first bad 6.5.31.**

### The negative-initialiser discriminator

```
6.5.30:  enum N { NEG1 = -1; }   ->  error: expected number, got '-'
6.5.35:  enum N { NEG1 = -1; NEG42 = -42; }  ->  runs, prints "-1 -42"   (correct)
```

So negative enum initialisers became expressible in this window, and the encoding chosen to carry them
is what costs the large positives. Note `enum { X = 0 - 1; }` is still a parse error at 6.5.35
(`expected identifier, got '-'`) — only a bare negative literal is accepted.

## Root cause

Two sites, and the arithmetic between them reproduces every observed value.

**Encode — [`src/frontend/parse_types.cyr:436`](../../../src/frontend/parse_types.cyr):**

```cyrius
if (vcnt < 1024) {
    S64(_vecv_base + vcnt * 8, (1 << 63) | val);
}
```

The comment above it states the contract plainly: *"Bit 63 = 'is enum const' marker; low 63 bits =
value."* The value word is only 63 bits wide, but `val` is a full i64.

**Decode — [`src/common/util.cyr:57-60`](../../../src/common/util.cyr):**

```cyrius
fn ENUM_CONST_VAL(ecv): i64 {
    if ((ecv & 0x4000000000000000) != 0) { return ecv; }
    return ecv & 0x7FFFFFFFFFFFFFFF;
}
```

Line 58 is the defect. It asks "is bit 62 set?" as a proxy for "was this value negative?", and when the
answer is yes it returns `ecv` **unmasked** — with the bit-63 marker still in it. For any positive `val`
with bit 62 set, that marker *is* the sign bit of the result.

Worked through:

| `val` | stored `(1<<63)\|val` | bit 62? | returned | as i64 |
|---|---|---|---|---|
| `0x3FFFFFFFFFFFFFFF` | `0xBFFFFFFFFFFFFFFF` | no → mask | `0x3FFFFFFFFFFFFFFF` | `4611686018427387903` ✅ |
| `0x4000000000000000` | `0xC000000000000000` | yes → raw | `0xC000000000000000` | `-4611686018427387904` ❌ |
| `0x7FFFFFFFFFFFFFFF` | `0xFFFFFFFFFFFFFFFF` | yes → raw | `0xFFFFFFFFFFFFFFFF` | `-1` ❌ |
| `-1` | `0xFFFFFFFFFFFFFFFF` | yes → raw | `0xFFFFFFFFFFFFFFFF` | `-1` ✅ |

The last two rows are the same stored word. **The encoding is genuinely ambiguous** — `-1` and
`0x7FFFFFFFFFFFFFFF` are indistinguishable once packed — so no decoder heuristic can be correct for
both. Bit 62 is a reasonable guess and it is what makes negatives work; it is also why large positives
cannot.

I simulated the encode/decode pair in isolation against all six probe values plus `-1`/`-42`: it
reproduces the observed output exactly, in every row.

**Fold sites that consume it** (all read the same table, so all inherit the bug):
`parse_expr.cyr:647`, `parse_expr.cyr:801`, `parse_decl.cyr:56`, `parse_decl.cyr:779`,
`parse_types.cyr:759` (`CHKDUPVAL`).

At 6.5.30 `parse_expr.cyr:803` did the mask **unconditionally** (`_ecv & 0x7FFFFFFFFFFFFFFF`) — correct
for all positives, wrong for negatives, which were unparseable anyway. `ENUM_CONST_VAL` first appears in
tagged source at **6.5.32** (in `parse_types.cyr`; moved to `common/util.cyr` at 6.5.33), yet the
released **6.5.31** tarball already miscompiles. So the 6.5.31 release binary appears to have been built
from a tree ahead of its tag. Flagging as an observation, not a claim — worth a look either way, since
it means the 6.5.31 artifact and the 6.5.31 source are not the same compiler.

## Proposed fix

**Stop packing the tag into the value word.** The presence information already exists elsewhere: the
per-var enum-id table is written on the very next lines (`SVENUMID(S, vcnt, ee_eid)`,
`parse_types.cyr:444`) and is *already used* as an enum-ness test at `parse_types.cyr:801`
(`if (GVENUMID(S, pi) == 0) { return 0; }   # prior symbol is a plain var, not an enum const`).

So:

1. **Store `val` raw** at `parse_types.cyr:436`, and make the five read sites gate on
   `GVENUMID(S, idx) != 0` instead of on `ecv < 0`. `ENUM_CONST_VAL` then disappears entirely rather
   than needing a smarter heuristic. This restores the full i64 range in both directions and removes an
   ambiguity that cannot be fixed in the decoder.
2. If the enum-id table turns out not to be populated on every path that writes `_vecv_base`, a parallel
   1024-entry presence byte array next to the value table is the same fix with an extra 1 KB.

Either way, please add a corpus fixture pinning the boundary set — `{2^62 − 1, 2^62, 2^63 − 2, 2^63 − 1}`
in **both** hex and decimal spelling, plus `-1` and a mid-range negative, since the negative path is the
reason the current encoding exists and must not regress when it is replaced. The repro above is that
fixture minus the negatives (which need a separate file — `-1` does not parse before 6.5.31).

⚠ Related, and worth fixing in the same pass or filing separately: the fold table is capped at 1024
entries (`parse_types.cyr:435`, `if (vcnt < 1024)`), and `CHKDUPVAL` returns early past that
(`parse_types.cyr:758`). Enum constants registered at index ≥ 1024 fall back to the unfolded `EVLOAD`
path — correct, but it also means **the duplicate-value warning cannot fire for them at all**. A
consumer with a large global surface (szal's var_table is >2000) silently loses that lint over roughly
half its symbols. Already recorded in the comment at `parse_types.cyr:748`, but it deserves a number.

## Consumer-side workaround

szal 2.1.1 ships this — declare the constant as a `var`:

```diff
-enum StepSat { STEP_I64_MAX = 0x7FFFFFFFFFFFFFFF; }
+var STEP_I64_MAX = 0x7FFFFFFFFFFFFFFF;
```

`var` initialisers do not go through the fold table and are unaffected. Safe when the name is only ever
used as a *value*; it does **not** work if the constant is used as an array size (`var buf[K]`), which
requires an enum constant — that combination has no workaround short of a literal.

**The generalised rule for consumers, until this is fixed: no enum constant anywhere in a build closure
may have bit 62 set.** szal now audits for it — its whole closure (its own `src/`, three vendored
dependency dists, tests, fuzz, benches, and the entire 6.5.35 stdlib snapshot) contains exactly one such
constant, now converted. A grep is enough to check:

```sh
grep -rnE 'enum [A-Za-z_]* *\{[^}]*= *(0[xX][4-9a-fA-F][0-9a-fA-F]{15}|[4-9][0-9]{18})' .
```

## How it presented downstream (why "silent" is the expensive part)

szal's `STEP_I64_MAX` is the engine's *"no timeout"* sentinel. Folded to `-1`, and with Cyrius `>`/`>=`
being signed, it inverted two independent guards at once:

- `if (timeout_ms >= STEP_I64_MAX)` selected the synchronous no-timeout path — so **every** step ran
  untimed, and a step that should have timed out returned a NULL error pointer, which the test then
  dereferenced (SIGSEGV, masking the 22 assertions after it).
- The unbounded-flow deadline check `clock_now_ms() - start_ms > timeout_ms` became **always true**
  (elapsed ≥ 0 > −1), so every step was skipped as *"flow timeout exceeded"*.

Five suites plus a fuzz harness failed; the narrower per-executor suites stayed green because they pass
literal timeouts and never reach the sentinel. Nothing in the build output pointed anywhere near the
cause — the first hypotheses were symbol collisions and the `FINDVAR` 1024 cap. A one-line diagnostic on
an enum initialiser that does not round-trip its own encoding would have collapsed a multi-hour
investigation into a compile error.

Full downstream write-up:
[`szal/docs/development/issues/2026-08-26-cycc-enum-bit62-sign-extension.md`](https://github.com/MacCracken/szal/blob/main/docs/development/issues/2026-08-26-cycc-enum-bit62-sign-extension.md).
