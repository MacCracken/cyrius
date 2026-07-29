# `fmt_int_buf` renders `i64::MIN` as the single byte `-`, and bayan turns that into invalid JSON

**Status:** 🟡 **OPEN** — filed 2026-07-29. Verified against live code and at runtime on cycc 6.5.1:
`lib/fmt.cyr:99` negates with `n = 0 - n`, which is a no-op at `i64::MIN`, so both the `n == 0` and
`while (n > 0)` arms are skipped and only the sign byte is emitted. Confirmed end to end — the repro
prints `{"n":-}`.
**Placement:** unpinned — 6.x-line backlog. Self-contained fix in `lib/fmt.cyr`, supplied and
verified below (11/11 cases); a matching guard in `lib/bayan.cyr`'s `_jp_atoi` is a separate, larger
question (see the end).
**Discovered:** 2026-07-29 while porting agnosai's `orchestrator/durable_state` and auditing the
integer path its JSON snapshots go through.
**Severity:** Medium — silent data corruption, but only at one input value. It produces a JSON
document that no parser will accept, with no error raised anywhere along the way.
**Affects:** cycc 6.5.1 and every earlier version carrying `lib/fmt.cyr`'s `fmt_int_buf`. All arches
and targets — this is pure Cyrius, no `asm`, no `#ifdef`.

## Summary

`fmt_int_buf` handles a negative number by recording the sign and negating:

```cyrius
if (n < 0) { neg = 1; n = 0 - n; }
if (n == 0) { store8(buf + bi, 48); bi = bi - 1; }
while (n > 0) { store8(buf + bi, 48 + n % 10); bi = bi - 1; n = n / 10; }
```

At `n == i64::MIN` the negation overflows back to `i64::MIN`. It is still negative, so `n == 0` is
false and `n > 0` is false: **no digits are written at all**. The only byte emitted is the `-`, and
the function returns length 1.

Nothing reports a problem. `str_from_int(i64::MIN)` is a one-character string, and every consumer
that formats integers inherits it. The one that matters most is `lib/bayan.cyr:3772`, where every
JSON integer is written through this path — so a document containing `i64::MIN` serialises to

```json
{"n":-}
```

which is not JSON. A writer produced it, no error was raised, and it will fail at whatever reads it
back, arbitrarily far away from the cause.

`i64::MAX` and `i64::MIN + 1` both render correctly, which is what isolates the negation as the
mechanism rather than the digit loop.

## Reproduction

`docs/development/issues/repros/2026-07-29-fmt-int-buf-i64-min.cyr`

```sh
cyrius build docs/development/issues/repros/2026-07-29-fmt-int-buf-i64-min.cyr /tmp/imin && /tmp/imin
```

Exits 1 while the bug is present, 0 once it is fixed. Actual output on 6.5.1:

```
str_from_int(i64::MIN) = [-]
bayan_json_v_build     = {"n":-}
BUG: i64::MIN did not render as its decimal form
BUG: the JSON document is not valid JSON
```

The repro also asserts that `i64::MAX` and `i64::MIN + 1` are unaffected, so a fix that breaks
either shows up immediately.

## Root cause

`lib/fmt.cyr:99` — `if (n < 0) { neg = 1; n = 0 - n; }`.

`0 - i64::MIN` is not representable in i64 and wraps to `i64::MIN`. This is the classic
two's-complement absolute-value overflow; the same shape exists in C's `abs(INT_MIN)`.

## Proposed fix — written, compiled, and run

`docs/development/issues/repros/2026-07-29-fmt-int-buf-i64-min-candidate-fix.cyr`

```sh
cyrius build docs/development/issues/repros/2026-07-29-fmt-int-buf-i64-min-candidate-fix.cyr /tmp/fix && /tmp/fix
```

**11/11 cases pass on cycc 6.5.1** — `i64::MIN`, `i64::MAX`, `i64::MIN + 1`, `0`, `-1`, `-7`, `-10`,
`-100`, `1`, `42`, `1000000` — so this is a checked candidate rather than a sketch. Drop it into
`lib/fmt.cyr` as-is if you agree with the approach.

Extract the digits from the negative side instead of negating, so no absolute value is ever needed.
This relies on `%` and `/` truncating toward zero, which the repro confirms rather than assumes
(`(0-7) % 10 = -7`, `(0-7) / 10 = 0`, `(0-12) % 10 = -2`, `(0-12) / 10 = -1`), so `n % 10` lands in
`-9..0` and negating that single digit is always in range:

```cyrius
fn fmt_int_buf(n, buf): i64 {
    var bi = 23;
    var neg: i64 = 0;
    if (n < 0) { neg = 1; }
    if (n == 0) { store8(buf + bi, 48); bi = bi - 1; }
    while (n != 0) {
        var d = n % 10;
        if (d < 0) { d = 0 - d; }        # single digit: always representable
        store8(buf + bi, 48 + d);
        bi = bi - 1;
        n = n / 10;
    }
    if (neg == 1) { store8(buf + bi, 45); bi = bi - 1; }
    # ... shift to the start of the buffer, unchanged
}
```

Note the loop condition changes from `n > 0` to `n != 0`, which is the part that actually lets the
negative case iterate. The `neg` flag no longer participates in the digit extraction, only in the
sign byte.

The 24-byte scratch is already sufficient: `-9223372036854775808` is 20 bytes.

Worth checking whether `fmt_int` and any other integer formatter in `lib/fmt.cyr` share the same
`0 - n` shape — this repro only exercises the `fmt_int_buf` path that `str_from_int` and bayan use.

## Related but separate: bayan's parser has no overflow check

While confirming the above I read `lib/bayan.cyr:3504`'s `_jp_atoi`:

```cyrius
var n = 0;
while (i < len) {
    n = n * 10 + (load8(buf + i) - 48);
    i = i + 1;
}
return sign * n;
```

There is **no overflow check**, so an out-of-range integer literal in the *input* wraps silently
rather than being rejected. That much is from reading the code and is not in doubt.

What I could **not** confirm is the composed behaviour — whether feeding
`{"n":9223372036854775808}` (one past `i64::MAX`) through parse → serialise → parse actually lands on
`i64::MIN` and then on this bug's `{"n":-}`. My probe for it segfaults inside `bayan_json_v_parse` in
this repo, which I believe is a version skew rather than a finding: this tree's bayan has no
`bayan_json_v_parse_str`, while the copy agnosai consumes still does, so the probe may simply be
calling it wrong. I am flagging the missing check, not claiming the chain.

Either way it is a bayan design question — what *should* an out-of-range JSON integer do: clamp,
error, or promote to f64? — rather than a two-line fix, so it is noted here rather than folded in.
Fixing `fmt_int_buf` alone still removes the "valid i64 in, invalid JSON out" case, which is the one
a consumer reaches without doing anything unusual.

## Consumer-side workaround

None applied in agnosai, and none needed there: the integers its JSON carries are byte counts,
millisecond durations and micro-USD amounts, none of which can reach `i64::MIN`. It is filed because
the corruption is silent and general, not because it is currently biting.

A consumer that genuinely needs to format an arbitrary i64 today has to special-case the one value:

```cyrius
if (n == (0 - 9223372036854775807) - 1) { return str_from("-9223372036854775808"); }
return str_from_int(n);
```

which is worth avoiding by fixing the stdlib.
