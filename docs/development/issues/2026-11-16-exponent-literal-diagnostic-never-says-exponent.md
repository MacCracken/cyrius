# An exponent literal (`1e-14`) is refused with a misleading warning and an error that never says "exponent" — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-16. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-16, by rasayan's Rust → Cyrius port (M0 step 9, probe 12, trap 10;
`rasayan/docs/development/port-parity.md` §3).
**Reporter:** rasayan 2.0.0 port.
**Severity:** **Low.** The build fails, so nothing computes wrong; the diagnostics send the reader the wrong way.
**Affects:** cycc 6.7.18.

## Summary

The guide says Cyrius has "no exponent form (`1e-9`): spell small constants out". A port meets the form at every
tolerance Rust writes (`1e-14`, `1e-12`). cycc refuses it, but neither diagnostic names the form:

- `var tol: f64 = 1e-14;` first warns *an integer stored into an f64/f32 slot keeps its integer bits (write a float
  literal)* — about the `1` — then errors *expected ';', got identifier 'e'*. The warning's advice ("write a float
  literal") is what the writer thought they did.
- `var big: f64 = 1.5e3;` errors *expected ';', got identifier 'e3'*.

## Reproduction

[`repros/2026-11-16-exponent-literal-diagnostic-never-says-exponent.sh`](repros/2026-11-16-exponent-literal-diagnostic-never-says-exponent.sh)
from the repo root:

```sh
bash docs/development/issues/repros/2026-11-16-exponent-literal-diagnostic-never-says-exponent.sh; echo $?
# warning:<source>:2:21: an integer stored into an f64/f32 slot keeps its integer bits (write a float literal)
# error:<source>:2:21: expected ';', got identifier 'e'
# error:<source>:3:23: expected ';', got identifier 'e3'
# repro: DEFECT PRESENT (refused, but no diagnostic says exponent notation is unsupported)
# 1
```

## Proposed fix

In the lexer, a decimal literal immediately followed by `e` / `E` and a digit or sign: one error, *exponent notation
is not supported in literals; write the value positionally (1e-14 → 0.00000000000001)*, and no integer-store warning
for the half-read literal. (Supporting the form is the other fix; the guide's rule says it is not wanted.)

## Consumer-side workaround

rasayan's generators write every constant positionally, and its CLAUDE.md says so ("No exponent notation in
literals"); probe 12 builds the trap with `-D P12_EXPONENT` and requires the error, so a fix that changes the message
shows up there.
