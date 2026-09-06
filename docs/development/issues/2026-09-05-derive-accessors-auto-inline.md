# `#derive(accessors)` should emit its getters/setters as `#inline` — blocked by a preprocessor state-threading defect in the multi-derive path

- **Filed**: 2026-09-05, from the v6.5.63 slot (implemented, measured, reverted)
- **Severity**: P2 — a measured 3.45× left on the table for every consumer; no wrong answers
- **Status**: 🟡 OPEN. The *prize* is verified. The *blocker* is a real defect and is the actual
  deliverable of this filing.

## Why this is filed rather than fixed

Per the standing rule, filing is only legitimate when the fix genuinely cannot pack into the
patch being written, and the reason must be named. The reason here:

**Emitting `#inline` into the derive output breaks the NEXT `#derive` in the same file.** That is
a preprocessor state-threading defect that has to be understood and gated on its own; bodging it
under a release whose subject is the `#inline` directive would be exactly the hurried,
half-understood change this repo keeps paying for. It is not "a different subsystem" and not
"P2" — it is a live breakage of files that compile today.

## The prize, measured

`#derive(accessors)` generates, per field:

```
fn Name_field(p) { return load64(p + K); }
fn Name_set_field(p, v) { store64(p + K, v); return 0; }
```

One parameter, flat, ~10 tokens — the canonical inline candidate, and *generated* code nobody
hand-tunes. Both shapes were verified to qualify and to be correct under `#inline` (getter and
setter, 4/4).

Measured at v6.5.63 on an 8-accessor loop (1M iterations, best-of-25, pinned):

| | time | `callq` |
|---|---|---|
| without `#inline` | 20,837,075 ns | 239 |
| with `#inline` | 6,042,668 ns | 231 |

**3.45×**, for **+192 B** of `.text`. This is the same shape as the ~29 % of svara's formant
bench that eleven out-of-line getter CALLS per sample cost (see the v6.5.61 premise-check).
Consumers would get it with **no source change**.

## The blocker, with a minimal repro

The change is two `PP_EMIT_STR(out, op, "#inline ")` calls in `PP_DERIVE_ACCESSORS_BODY`
(`src/frontend/lex_pp.cyr`) — a space, never a newline, because that emitter runs under
`_pp_flatten` to preserve line numbering.

**ONE derive works.** Verified correct end to end (exit 42):

```cyrius
include "lib/syscalls.cyr"
#derive(accessors)
struct AA { p; q; }
fn main(): i64 { var b[16]; AA_set_p(&b, 41); syscall(60, AA_p(&b) + 1, 0,0,0,0); return 0; }
var e = main();
```

**TWO derives fail on the second:**

```cyrius
include "lib/syscalls.cyr"
#derive(accessors)
struct AA { p; q; }
#derive(accessors)
struct BB { r; s; }
fn main(): i64 { syscall(60, 0, 0,0,0,0); return 0; }
var e = main();
```

```
error:<source>:5:1: unexpected struct
    struct BB { r; s; }#inline fn BB_r(p) { return load64(p + 0); } #inline fn BB_set_r(p, v) { ...
```

The second struct's `struct` keyword reaches the **parser**, which the preprocessor should have
consumed. Regressed `tests/tcyr/derive/derive_cap.tcyr` and `tests/tcyr/lang/regression.tcyr`,
both of which compile today.

⚠ **It is NOT the 36-struct capacity limit `derive_cap.tcyr` exists to pin.** It fails at the
*second* struct, not the 33rd. Do not go looking at the `0x197500` per-struct tables first.

## Where to look

`PP_DERIVE_ACCESSORS` (`src/frontend/lex_pp.cyr`) threads output state through
`S + 0x197008` and finishes with `PP_COPY_TAIL(src_base, _pp_tail_ip, bl, out, op)`. The emitted
bytes shift `op`; `_pp_tail_ip` is an INPUT offset and should not shift. Something in that
handoff — or in `PP_IFDEF_PASS`, whose input is `PP_PASS`'s **output** and which therefore
re-scans the emitted `#` — leaves the next `#derive`/`struct` unconsumed. Start by dumping the
preprocessed text for the two-struct case and diffing it against the same file without the
emitted `#inline `.

## Acceptance

- The two-struct repro above compiles and runs.
- `derive_cap.tcyr` (36 structs), `regression.tcyr` and `derive_accessors_large.tcyr` stay green.
- A gate asserts a derived accessor is actually inlined (call-site count), mutation-proven, and
  that N-struct files with N > 2 still preprocess correctly.
- Ecosystem re-vendor, since this changes emitted code for every `#derive(accessors)` consumer.

## ⟳ v6.5.70 — ROOT-CAUSED. The blocker is that `#` opens a COMMENT.

The filing said the blocker was "a preprocessor state-threading defect" and left it at that.
Reproduced and root-caused today:

**`#` starts a comment in cyrius, and the preprocessor's own scanners implement that literally**
— `if (c == 35) { in_comment = 1; }` appears in the scan loops in `src/frontend/lex_pp.cyr`
(two occurrences). So when `PP_DERIVE_ACCESSORS_BODY` emits `#inline fn Name_field(p) { … }`,
a later scan treats the rest of that line as a comment. The generated accessor is swallowed, and
the comment state runs on far enough to eat the FOLLOWING `#derive(accessors)` line — which is
exactly the observed symptom: `error: <source>:5:1: unexpected struct`, the second derive never
firing and its `struct` reaching the parser.

Verified by rebuilding the compiler with `"fn "` changed to `"#inline fn "` in the accessors
emitter and compiling a two-struct fixture: correct without the change (exit 10), `unexpected
struct` with it.

**So the fix is not to emit `#inline` as TEXT at all.** The directive has to reach the parser
through a side channel, the way the derive metadata already does (struct name at `S+0x197020`,
field names at `S+0x1FC000`, offsets at `S+0x200000`): record the generated accessor names, or a
count, in a table the parser consults when it registers those functions. That is a bounded change
and it is the actual deliverable of this filing.

⚠ This is the same fact recorded at v6.4.81 — *"`#` is a COMMENT so `#include` probes are
inert"* — surfacing in a new place. Anything that emits a `#`-prefixed directive into
preprocessor OUTPUT hits it.
