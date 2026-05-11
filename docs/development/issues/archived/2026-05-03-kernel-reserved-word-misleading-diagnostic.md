# Issue: `kernel` reserved word breaks parser at unrelated downstream line — RESOLVED v5.8.45

**Resolved:** v5.8.45 (2026-04-30). The lexer demoted `kernel` from
reserved token 56 to a plain identifier; top-level `kernel;` (AGNOS
kernel-mode switch) is now detected via `_TOK_IS_KERNEL(S)` at the
dispatch site in `main.cyr` / `main_*.cyr` instead of through a
reserved keyword. The repro below compiles clean at v5.10.42
(empirical verify during the v5.10.x roadmap-extension audit).
See `src/frontend/lex.cyr:687` and the v5.8.45 CHANGELOG entry.

**Discovered:** 2026-05-03 (vidya audio_dsp 11-lang port)
**Component:** `cyrius` compiler — parser / lexer
**Severity:** Medium (silent miscompile of error-reporting; correct code
paths work, but error messages point at innocent code making bugs
extremely hard to bisect)
**Toolchain:** `cyrius 5.8.34`

## Summary

Using `kernel` as a function parameter name (and presumably as any
identifier) breaks parsing in a way that fires the diagnostic
`expected identifier, got unknown` at a *different earlier function*
in the same file — not at the offending declaration. The cascading
parse failure makes the error reporter point miles from the actual
problem. Renaming the parameter to anything else (`taps`, `kern`,
`coefs`) makes the file parse cleanly.

This suggests `kernel` is treated as a reserved or special token
during signature parsing, but the parser doesn't emit a clear
"reserved identifier" diagnostic — it simply gets confused and
flags the next syntactically-similar construct it encounters.

## Reproduction

```cyrius
# In any .cyr file with these two functions in this order:

fn biquad_set(b0, b1, b2, a1, a2) {
    return 0;
}

fn biquad_lowpass_1pole(a_q15) {
    biquad_set(a_q15, 0, 0, a_q15 - ONE, 0);
}

fn fir_step(kernel, history, n_taps, x_new) {   # <-- uses `kernel`
    var i = n_taps - 1;
    return i;
}
```

Compile output:
```
error:<source>:11: expected identifier, got unknown
```

Line 11 is `fn biquad_lowpass_1pole(a_q15) {` — a perfectly valid
function declaration that has nothing to do with `kernel`. The
real problem is on line ~15 in `fir_step`.

## Workaround

Rename the parameter:

```cyrius
fn fir_step(taps, history, n_taps, x_new) {
    var i = n_taps - 1;
    return i;
}
```

Confirmed working alternates: `taps`, `kern`, `coefs`, `weights`,
single letters. Only `kernel` triggers the cascade.

## Suggested fix

Either:
1. Allow `kernel` as a normal identifier (preferred — it's a common
   variable name in DSP/graphics/AI code).
2. If `kernel` must remain reserved, emit a specific diagnostic
   at the declaration site: `error: 'kernel' is a reserved
   identifier; please rename`.

The current behaviour (silent reserved-word collision that
miscompiles the error reporter) is the worst of both options —
neither helpful for users who would have renamed if asked, nor
truly reserving the name for any visible feature.

## Bisection notes

Confirmed via systematic test of parameter names in a single
`fir_step(<name>, b, c, d)` signature:

- `kernel` → file fails to parse (error fires on earlier function)
- `history` → parses
- `n_taps` → parses
- `x_new` → parses
- `aa`, `bb`, `cc`, `dd` → parses
- `taps` → parses

Only `kernel` fails. Have not bisected other potentially-reserved
DSP/ML names (`weights`, `bias`, `tensor`, `layer`) — would be
worth a sweep.
