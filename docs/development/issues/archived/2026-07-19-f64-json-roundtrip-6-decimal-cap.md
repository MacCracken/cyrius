# f64 JSON serialization is lossy and can emit invalid JSON — every emit path caps at 6 decimals — FIXED (6.4.69)

**Fixed 2026-07-20 (bayan 1.2.1 + cycc 6.4.69).** All three defects closed. The
6-decimal `fmt_float_buf(v, 6)` emit is replaced by a **Grisu2** (Loitsch;
integer-only, always-succeeds) round-trip-correct formatter `bayan_f64_to_json`
(non-finite → `null`, the serde_json / JS policy this issue recommended). The two
divergent-by-1-ULP atofs are replaced by ONE **Clinger-fast-path + normalized-DiyFp**
correctly-rounded, **exponent-saturating** parser `bayan_f64_from_json` — the O(exp)
DoS is gone (`1e100000000` now parses in microseconds, not 237 ms). Both live in bayan
`src/dtoa.cyr`; bayan's emit (`_jb_walk`) + parse (`_jp_atof`), `#derive(Serialize)`,
and `math.cyr`'s `f64_parse` (DoS clamp) all route through / adopt them. Validated
**bit-exact across the entire double range** — format→parse round-trip 0/7124 fail,
reference-`strtod` parse agreement 0/4017 fail (incl. all powers of two, subnormals,
5000+ randoms); the f64 codec LIBTEST passes on real ecb (macOS) + cass (Windows).
The only values that don't round-trip are `Inf`/`NaN`, which now serialize to a valid
`null` (JSON has no Inf/NaN literal). The `-0.0` `fmt_hex` diagnostic is fixed
separately ([`2026-07-19-fmt-hex-high-bit-prints-nothing.md`](./2026-07-19-fmt-hex-high-bit-prints-nothing.md)).
The derive's compiler-side half is [`2026-07-19-derive-serialize-f64-second-implementation.md`](./2026-07-19-derive-serialize-f64-second-implementation.md).

---

**Discovered:** 2026-07-19 while implementing **samay** M4 (JSON `Serialize`/`Deserialize`
for every public type) against cycc 6.4.67.
**Severity:** **Critical** — silent data corruption, plus an algorithmic-complexity DoS on
untrusted input. Any `|x| < 5e-7` is silently written as `0.000000` and reads back as
exactly `0`; `1/3` silently loses ~9 mantissa bits; `+Inf` / `NaN` / any `|x| >= 2^63`
emit the token `-.00000-`, which is **not valid JSON** and will fail any conforming parser
(including Cyrius's own on re-read); and a 17-byte document (`{"x":1e100000000}`) costs
**237 ms** of wasted CPU to parse (see "Additional" under Root cause).
**Affects:** cycc **6.4.67** (the only version tested — the code paths date to v6.3.40, so
6.3.40 → 6.4.67 is the likely range). `#derive(Serialize)`, `lib/bayan.cyr` JSON/YAML/TOML
emit, and any direct `fmt_float_buf` caller.

## Summary

Three independent serialization paths all funnel f64 through `fmt_float_buf(v, buf, 6)`
— a fixed **6 decimal places, no exponent form, no non-finite handling**. Consequences:

| input | emitted | reads back as | verdict |
|---|---|---|---|
| `0.5`, `0.25`, `0.1`, `1e9`, `1e18` | `0.500000` … | identical bits | exact (must not regress) |
| `1/3` | `0.333333` | `0x3fd55553ef6b5d46` (orig `0x3fd5555555555555`) | **~9 mantissa bits lost** |
| `2/3` | `0.666667` | `0x3fe55556084a515d` | **lossy** |
| `1e-7` | `0.000000` | `0x0` | **annihilated** |
| `1e-9` | `0.000000` | `0x0` | **annihilated** |
| `2^63` | `-.00000-` | `0x0` | **invalid JSON** |
| `+Inf` | `-.00000-` | `0x0` | **invalid JSON** |
| `NaN` | `-.00000-` | `0x0` | **invalid JSON** |
| `-0.0` | `-0.000000` | `0x0` | sign lost |

Separately, the **two float parsers disagree by exactly 1 ULP on identical text**:

```
"0.333333"  ->  bayan _jp_atof : 0x3fd55553ef6b5d46
                math  f64_parse: 0x3fd55553ef6b5d47
"0.666667"  ->  bayan _jp_atof : 0x3fe55556084a515d
                math  f64_parse: 0x3fe55556084a515e
```

That matters because `#derive(Serialize)` **emits** via bayan-adjacent code but
**deserializes** via `f64_parse` — so a value can change bits merely by crossing the
derive's own round trip, independent of the 6-decimal truncation.

Consumer impact: samay is a task scheduler whose `SchedulingDecision.score` is
`1 - utilization`, where utilization averages resource ratios. Values like `1/3` and
`2/3` are therefore the **common** case, not an edge case — a scheduler snapshot cannot
be persisted and restored without perturbing placement decisions. samay's M4 milestone
is blocked on this.

## Reproduction

`docs/development/issues/repros/2026-07-19-f64-json-roundtrip-6-decimals.cyr`

```
$ cyrius build docs/development/issues/repros/2026-07-19-f64-json-roundtrip-6-decimals.cyr /tmp/f64rt
$ /tmp/f64rt
-- values that DO roundtrip (must not regress) --
1.0        emitted {"x":1.000000}  -> EXACT
0.5        emitted {"x":0.500000}  -> EXACT
0.25       emitted {"x":0.250000}  -> EXACT
0.1        emitted {"x":0.100000}  -> EXACT
1e9        emitted {"x":1000000000.000000}  -> EXACT

-- (1) precision loss: 6-decimal cap --
1/3        emitted {"x":0.333333}  -> LOSSY  orig=0x3fd5555555555555 bayan=0x3fd55553ef6b5d46 math=0x3fd55553ef6b5d47
2/3        emitted {"x":0.666667}  -> LOSSY  orig=0x3fe5555555555555 bayan=0x3fe55556084a515d math=0x3fe55556084a515e

-- (1) flush-to-zero below 5e-7 --
1e-7       emitted {"x":0.000000}  -> LOSSY  orig=0x3e7ad7f29abcaf48 bayan=0x0 math=0x0
1e-9       emitted {"x":0.000000}  -> LOSSY  orig=0x3e112e0be826d695 bayan=0x0 math=0x0

-- (3) huge + non-finite: is the output even valid JSON? --
1e18       emitted {"x":1000000000000000000.000000}  -> EXACT
2^63       emitted {"x":-.00000-}  -> LOSSY  orig=0x43e0000000000000 bayan=0x0 math=0x0
+Inf       emitted {"x":-.00000-}  -> LOSSY  orig=0x7ff0000000000000 bayan=0x0 math=0x0
NaN        emitted {"x":-.00000-}  -> LOSSY  orig=0x7ff8000000000000 bayan=0x0 math=0x0
-0.0       emitted {"x":-0.000000}  -> LOSSY  orig=0x bayan=0x0 math=0x0

-- (4) exponent loop is O(exponent VALUE): DoS on untrusted input --
1e10         doclen=10  ns=2374       bits=0x4202a05f20000000
1e1000       doclen=12  ns=5658       bits=0x7ff0000000000000
1e1000000    doclen=15  ns=2871751    bits=0x7ff0000000000000
1e10000000   doclen=16  ns=24958356   bits=0x7ff0000000000000
1e100000000  doclen=17  ns=239725517  bits=0x7ff0000000000000

lossy count: 8
$ echo $?
1
```

Deterministic. Exit 0 would mean every probe roundtripped; it exits 1.

**A warning for anyone extending this repro:** escaped quotes inside a `.cyr` source
literal (`"{\"x\":1e10}"`) do **not** reach the parser as intended here — every such probe
silently becomes a parse error, which looks like a fast, healthy 1.9 µs result. My first
three attempts at the DoS measurement were measuring the error path and showed flat timings
across all exponents. The repro therefore builds its documents with `str_builder`
(`mk_obj`) and **checks the returned value for 0** rather than trusting the timing. Any
probe here that reports `[PARSE ERROR]` is measuring nothing.

The same defect reproduces through `#derive(Serialize)` rather than the bayan DOM —
a `#derive(Serialize) struct B { x: f64; }` emits `{"x":0.333333}` and reads back
`0x3fd55553ef6b5d47`.

## Root cause (verified)

One formatter, three callers, two parsers.

**Formatter** — `lib/fmt.cyr:210` `fmt_float_buf(val, buf, decimals)`:
- Computes the integer part as `f64_to(f64_floor(val))`. For `|val| >= 2^63` (and for
  `Inf`/`NaN`) that conversion overflows i64; the resulting garbage is then run through
  `fmt_int_buf`, which is what produces `-.00000-`. There is no finite/NaN check anywhere.
- The fractional part is `f64_to(f64_round(f64_mul(f64_sub(val, whole), scale)))` with
  `scale = 10^decimals` — so precision is capped at whatever `decimals` the caller passes,
  and there is no exponent (`e±NN`) form at all. `decimals` is a parameter, but **every**
  serialization caller passes a literal `6`.

**Caller 1 — `#derive(Serialize)` emit**, `src/frontend/lex_pp.cyr`. **Two** sites, both
hardcoding `6`, writing into the shared `var _dfb[80]` scratch declared at `:763`:
```
:900-903   per-field f64 branch
           op = op + PP_EMIT_STR(out, op, "store8(&_dfb + fmt_float_buf(load64(ptr + ");
           op = op + PP_EMIT_INT(out, op, load64(S + 0x200000 + fi * 8));
           op = op + PP_EMIT_STR(out, op, "), &_dfb, 6), 0);\nstr_builder_add_cstr(sb, &_dfb);\n");

:882       vec-of-f64 branch
           op = op + PP_EMIT_STR(out, op, "store8(&_dfb + fmt_float_buf(vec_get(_vh");
```
This is emitted **inline into every generated `*_to_json`**, so it is not fixable by
changing any library — it needs a compiler change plus a rebuild of consumers.

**Caller 2 — bayan's value-tree builder**, `lib/bayan.cyr` `_jb_walk`, `JTAG_FLOAT` branch
(bayan source: `~/Repos/bayan/src/json.cyr:1090-1092`):
```
var fb[64];
var fl = fmt_float_buf(load64(v + 8), &fb, 6);
```
This one is bayan's to fix, but it cannot fix the derive.

**Caller 3** — the YAML/TOML emitters share `_jb_walk`, so they inherit it.

**Parser A — `lib/math.cyr:514` `f64_parse`** — used by the derive's deserialize side
(`src/frontend/lex_pp.cyr:1042`: `f64_parse(str_data(v))`).
**Parser B — bayan `_jp_atof`** — accumulates digits with repeated `f64_mul`/`f64_add`,
divides by `frac_div`, then applies the exponent as a **loop of `f64_mul`/`f64_div` by 10**.
Neither is correctly rounded; error compounds per digit and per exponent step, which is why
they land on adjacent ULPs.

### Additional: that exponent loop is an algorithmic-complexity DoS

`_jp_atof`'s exponent application (bayan `src/json.cyr:828-833`) runs **once per unit of
the exponent's value**, and the accumulator at `:825` (`exp = exp * 10 + (c3 - 48)`) is
unbounded. So work is linear in the *value* of the exponent — exponential in the input's
*length* — and the entire computation is wasted, because everything past ~1e309 saturates
to `+Inf` immediately.

Measured, parsing a complete JSON document via `bayan_json_v_parse`:

| document | bytes | parse time | result |
|---|---|---|---|
| `{"x":1e10}` | 10 | 8 µs | `0x4202a05f20000000` |
| `{"x":1e1000}` | 12 | 5 µs | `+Inf` |
| `{"x":1e1000000}` | 15 | **2.67 ms** | `+Inf` |
| `{"x":1e10000000}` | 16 | **24.9 ms** | `+Inf` |
| `{"x":1e100000000}` | 17 | **237 ms** | `+Inf` |

A 17-byte untrusted document costs a quarter-second of CPU. `1e1000000000` (one more
digit) costs ~2.4 s; the exponent field can hold ~19 digits before the i64 accumulator
itself overflows, so a sub-30-byte document can occupy a core effectively indefinitely.
A modest array of such literals is a trivial denial of service against anything parsing
untrusted JSON or YAML with bayan.

**Fix:** clamp the exponent during scanning. Any `|dp| > ~400` is already decidable
without looping — `10^400` overflows to `+Inf` and `10^-400` underflows to `0` — so
saturating the accumulator (e.g. stop growing it past 100000) and short-circuiting the
range makes this O(len) with no behavior change for representable values. This is worth
fixing independently of the precision work; it is the cheapest item in this report and
the only one that is remotely security-relevant.

## Proposed fix

Ordered so consumers get correctness first and prettiness later. Note the f64 bit pattern
is directly available as an i64 (`sign=(v>>63)&1`, `expo=(v>>52)&0x7FF`,
`mant=v&0xFFFFFFFFFFFFF`, verified reconstructing exactly), and `lib/bayan.cyr` already
ships u128/u256 arithmetic — so an exact integer-based algorithm is implementable without
new primitives.

1. **Stop emitting invalid JSON (Critical, smallest change).** Guard `fmt_float_buf` for
   non-finite and out-of-i64-range inputs instead of overflowing into `-.00000-`. Since
   JSON has no `Inf`/`NaN` literal, the *serializers* must additionally decide a policy —
   `null` is the common choice (serde_json, JavaScript) and should be stated in the docs
   either way. This alone turns "emits a corrupt document" into "emits a lossy but valid
   document".

2. **Make the round trip exact.** Give `fmt_float_buf` (or a new
   `fmt_float_shortest_buf`) enough precision to round trip: 17 significant digits is
   always sufficient for a double, and exponent form is needed for the magnitudes where
   fixed notation is untenable. Then point the derive and bayan at it. Shortest-form
   (Ryu / Grisu3-with-fallback) is a nice-to-have on top; **17-significant-digits is the
   correctness bar** and is far easier to audit.

3. **Unify the parsers.** Two divergent, both-incorrect `atof`s is a latent
   interop bug independent of the emit fix. Make one correctly-rounded implementation
   (Clinger / Eisel-Lemire with a bignum fallback) and have bayan's `_jp_atof` delegate to
   it — or vice versa — so the same text always yields the same bits.

4. **Regression tests** — none exist today: `~/Repos/bayan/tests/bayan.tcyr` has **no
   float roundtrip test at all**. The repro above is a ready-made matrix (exact set,
   lossy set, flush-to-zero boundary, non-finite, `-0.0`, `>= 2^63`).

Fixing this top-down in `lib/fmt.cyr` + `lib/math.cyr` + `src/frontend/lex_pp.cyr` fixes
every consumer at once. Fixing only bayan would leave `#derive(Serialize)` — the path most
consumers actually use — still broken, since it calls `fmt_float_buf` directly and never
enters bayan's emit code.

The derive half has its own report, because it needs a **compiler** change and a consumer
rebuild rather than a library release, and because sequencing it apart from the library fix
actively makes things worse (documents would carry two float formats at once):
[`2026-07-19-derive-serialize-f64-second-implementation.md`](./2026-07-19-derive-serialize-f64-second-implementation.md).

## Consumer-side workaround (samay, in progress)

None that preserves the JSON shape. The options samay weighed:

- Encode f64 as a hex bit-pattern string (`"0x3fd5555555555555"`) — exact, but
  non-human-readable and diverges from the type's natural JSON shape.
- Encode as scaled integers (millicores, ppm) — exact for the scaled precision, changes
  field semantics.
- Persist only inputs and recompute derived f64s on restore — dodges the issue for derived
  values but not for stored ones.

samay chose to **block its M4 milestone on this fix** rather than bake a workaround into
its on-disk format, since the wire format would be hard to change later. Its cstr → `Str`
migration (a separate prerequisite) has landed; JSON is waiting on this issue.

**Reporting on:** cycc 6.4.67, bayan 1.2.0. **Recommended floor for the fix:** whatever
release lands item (1) — emitting syntactically invalid JSON is the part that cannot be
worked around downstream, because the document is already corrupt by the time a consumer
sees it.

## Related

The `-0.0` row above shows `orig=0x` with no digits — that is **not** a JSON bug. It is a
separate, now-confirmed defect in `fmt_hex`/`fmt_hex0x`/`fmt_hex_buf`, which print nothing
for any high-bit-set value. Filed separately as
[`2026-07-19-fmt-hex-high-bit-prints-nothing.md`](./2026-07-19-fmt-hex-high-bit-prints-nothing.md)
with its own repro. It affects only the diagnostic output in this repro, not the
roundtrip results themselves (those compare bit patterns numerically).
