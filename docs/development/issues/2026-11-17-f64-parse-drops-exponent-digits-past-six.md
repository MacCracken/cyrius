# `_f64_parse_n` drops exponent digits past six, so a long number with a 7-digit exponent reads wrong — open

**Status:** 🟡 **OPEN** (bug): verified on cyrius 6.7.18 (x86_64), 2026-11-17; `lib/math.cyr:1364` at `c105c37fc`.
**Discovered:** 2026-11-17, by pramana's 2.0.1 bug audit of its JSON readers (bayan's float reader ends in
`_f64_parse_n`).
**Reporter:** pramana 2.0.1 (conversion ledger L16; `pramana/docs/development/pramana-port-plan.md` §10).
**Severity:** **Low.** Only a number token of about 100 KB or more can be read wrong: the token needs enough digits to
move the decimal point by 100,000 or more. When it happens, though, the value is silently wrong (1e299 reads as 0.0),
and serde_json reads the same text exactly.

## Summary

`_f64_parse_n` accumulates the exponent with a saturating loop, so a huge exponent can't make it loop or overflow:

```
if (ev < 100000) { ev = ev * 10 + (load8(s + i) - 48); }   # SATURATE -> no DoS
```

Past six significant digits the remaining digits are dropped, so 1000000 reads as 100000. The exponent is then added
to `dexp`, the mantissa's own decimal offset (+1 per integer digit past the 19th, −1 per fraction digit). That offset
can be as large as the token, so the saturated exponent is wrong in exactly the case where the sum would have been in
range:

| Token | Its value | `_f64_parse_n` |
|---|---|---|
| `0.` + 999,700 zeros + `1e1000000` (999,711 bytes) | exactly 1e299 (`0x7E031CFD3999F7B0`) | 0.0 (the exponent read as 100000: 10^(100000 − 999701)) |
| `1` + 999,700 zeros + `e-1000000` (999,710 bytes) | exactly 1e-300 (`0x01A56E1FC2F8F359`) | ∞ (10^(999700 − 100000)); bayan's reader then refuses it |
| `1` + 999,999 zeros + `e-999999` | 1.0 | 1.0: six digits, read exactly |

A token without such an offset is unaffected: `1e1000000` is ∞ either way.

## Repro

pramana's audit repro (any consumer of bayan's JSON reader sees the same):
`pramana/tests/json.tcyr`, group "the pre-pass rewrites numbers as serde_json reads them", builds both tokens.
pramana's stand-in is now in place, so the repro there passes; without it the two reads give 0.0 and a refusal.

## Fix

Saturate past any offset the text can produce, not at a fixed 100000. The digit loop already knows the token's
length `n`, and |`dexp`| ≤ `n`. So a bound of `n + 400` (or any larger constant such as 2³⁰, with a
document-length cap) keeps the DoS guard and makes `dexp + xe` exact whenever the result is finite and nonzero:

```
var cap = n + 400;
if (ev <= cap) { ev = ev * 10 + (load8(s + i) - 48); }
```

`ev` then stays below 10·(n + 400), far inside i64 for any `n` a buffer can hold.

## Consumers

- **pramana 2.0.1** (`src/json.cyr`, `_pmn_json_big_exp`, ledger L16): its JSON pre-pass rewrites a token whose
  exponent has 7 or more significant digits to the same value with a small exponent (its significant digits and the
  exponent of the first). It is converted to the stdlib parser once this is fixed, with pramana's JSON decode rows
  re-run.
