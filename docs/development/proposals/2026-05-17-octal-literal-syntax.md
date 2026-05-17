# Octal Integer Literal Syntax

**Filed:** 2026-05-17 during kriya M2 implementation
**Severity:** Quality-of-life — no current consumer is blocked (decimal literals work), but every syscall-flag / POSIX-mode call site in every Cyrius consumer pays an ongoing readability tax. First concrete instance: `kriya mkdir` at [kriya `src/cmd/mkdir.cyr`](https://github.com/MacCracken/kriya/blob/main/src/cmd/mkdir.cyr).
**Affects:** `src/frontend/lex.cyr` (LEXNUM dispatch, new LEXOCT routine). One concentrated change. No backend / codegen impact — octal is just another integer-literal *spelling*.
**Target slot:** v5.12.x — quality-of-life, no ABI impact, lands in the cycle that wants it.

## Summary

Cyrius today accepts decimal integer literals (`493`) and hex integer literals (`0x1ED`). Octal literals — `0o755`, the value `493` written in the base the kernel and POSIX manuals use — are not lexed. Consumers writing file-mode constants, syscall-flag bitmasks, ioctl numbers, or any other domain that historically reads in base 8 must either spell the value in decimal (`493`) or hex (`0x1ED`) and add a comment translating it back to octal.

This proposal asks Cyrius to grow `0o`-prefixed octal literal support, with optional underscore separators matching the existing decimal and hex behavior.

## Motivation — the concrete tax

kriya's M2 lead-in landed `mkdir` on 2026-05-17. The implementation needed three of these constants:

```cyrius
# kriya/src/cmd/mkdir.cyr — what we wrote (today, no octal literal):
sys_mkdir(path, 511);     # 0o777 = 511 (Cyrius has no octal literal syntax)
sys_mkdir(prefix, 511);   # same
# S_IFMT = 0o170000 (61440); S_IFDIR = 0o040000 (16384).
if ((st_mode & 61440) == 16384) { return 1; }
```

Every one of those four constants is a base-8 quantity in POSIX. POSIX manual pages, every coreutils/BusyBox/toybox source tree, every kernel header — they all spell these values in octal because each octal digit is exactly three permission bits or one nibble of `S_IF*`. The decimal forms (`493`, `511`, `61440`, `16384`) require the reader to either trust the comment or do mental math; the comment then becomes load-bearing for code review and rots when a value is changed.

Each Cyrius consumer that touches the filesystem owes a chain of these comments:

- **kriya** — `mkdir`, `chmod`, `umask`, every `S_IFMT`/`S_IFDIR`/`S_IFREG`/`S_IFLNK`/`S_IFSOCK`/`S_IFIFO`/`S_IFCHR`/`S_IFBLK` test, the entire upcoming M2 surface (`rmdir`, `touch`, `cp`, `mv`, `rm`, `ln`).
- **agnos** (kernel) — page-table permission bits (some platforms use octal-natural triples), syscall mode arguments.
- **agnoshi** (shell) — `umask` builtin, mode arguments propagated to spawned utilities.
- **owl** — file-type checks for the syntax-highlight path.
- **sit** — git's permission model is octal (`100644`, `100755`, `040000`); every tree-object parse touches these.
- **cyim** — same file-type checks as owl.

That's six first-party Cyrius consumers, all paying the same tax. The cost is small per site (~one comment) but pervasive (every fs-touching path), and it grows linearly with first-party consumer count. Solving it once in the lexer eliminates the tax everywhere.

## Why not just keep using decimal/hex + comments

- **Comment rot.** A `0o755` literal that becomes `0o775` updates in one place. A `493` literal that becomes `509` updates the constant *and* the comment; the comment will lag in some PR somewhere.
- **No compile-time signal when a maintainer mistypes.** If someone "fixes" `493` to `483` thinking it's still POSIX-meaningful (it isn't — `0o743` is unusual), no validation catches it. With `0o755` the wrong values are visibly weird (`0o758` would not lex at all — `8` is not an octal digit).
- **Asymmetry with hex.** Cyrius already accepts `0xDEAD_BEEF` because hex is the natural form for bitmasks. The same argument that gave us hex applies to octal for permission bits. Adding octal closes the natural-base-coverage gap.
- **Cross-language familiarity.** Python (`0o755`), Rust (`0o755`), Go (`0o755` since 1.13), modern JavaScript (`0o755`), Swift (`0o755`) all use the `0o` prefix. C uses the **bare-leading-zero** form (`0755`) which is a [well-known footgun](https://www.cve.org/CVERecord?id=CVE-2002-1531) — `0123` parsing as octal 83 instead of decimal 123 has caused real outages. The `0o` prefix is the [post-C consensus](#prefix-choice) on doing this without ambiguity.

## Proposed syntax

```cyrius
# Octal literal: `0o` prefix, then digits 0..7, optionally with `_` separators.
var mode_755   = 0o755;        # = 493
var mode_full  = 0o777;        # = 511
var s_ifmt     = 0o170000;     # = 61440
var s_ifdir    = 0o040000;     # = 16384
var s_ifreg    = 0o100000;     # = 32768
var grouped    = 0o7_5_5;      # = 493 (underscore separators)
var leading_0  = 0o0644;       # = 420 (leading-zero digit allowed inside the literal)
```

**Hard rules:**

1. `0o` prefix is **mandatory**. Bare leading-zero (`0755`) continues to lex as decimal `755` exactly as today — no silent semantic change. This avoids the C footgun.
2. The `o` is lowercase only. `0O755` is a lex error. (Matches hex, which is `0x` lowercase only in the existing lexer.)
3. Only digits `0..7` are valid. `0o9` is a lex error, not "octal until the 9 then a new token starts."
4. Underscore separators are allowed between digits (consistent with `0xDEAD_BEEF` and `1_000_000`). Trailing underscore (`0o755_`) is rejected, matching decimal/hex behavior.
5. Empty digit run is a lex error: `0o` alone is rejected.
6. Float-style fractional suffix is **not** supported. `0o7.5` is a lex error. (Octal fractions are not a thing we need.)

## Codegen scope — what changes

| File | Change |
|---|---|
| `src/frontend/lex.cyr` — `LEXNUM` | After matching leading `0`, check second char for `o` (current branch already handles `x` → `LEXHEX`). On `o`, dispatch to new `LEXOCT`. |
| `src/frontend/lex.cyr` — new `LEXOCT` | Mirrors `LEXHEX`: accumulate `val = val << 3 \| (c - 48)` while `c` is in `48..55`. Underscore = skip. Anything else terminates the literal. Emit `ADDTOK(S, 1, val)`. |
| Codegen | **None.** Octal is a lexer-only feature; the parser sees an integer token identical to `0x1ED` or `493`. |
| Type system | **None.** Same `i64` value as the decimal form. |
| Stdlib | **None required** (no existing stdlib relies on octal literals being absent). Optional follow-up: re-write the `0o170000`-shaped constants in `syscalls_x86_64_linux.cyr` to use the new form once available. |

Estimated surface: **~30 LOC** in `lex.cyr` plus a handful of test cases.

## Test plan

`cyrius` has a strong byte-exact testing discipline (per AGNOS work). The new feature gets:

1. **Positive lex tests** — `0o0`, `0o7`, `0o755`, `0o7777`, `0o0644`, `0o7_5_5`, max value (`0o7_77777_77777_77777_77777` = 2^63 − 1).
2. **Negative lex tests** — `0o` (empty), `0o8` (non-octal digit), `0o9`, `0o7_`, `0O755` (uppercase), `0o7.5` (no fractional support).
3. **Non-regression** — `0755` still lexes as decimal `755`. `0x1ED` still lexes as `493`. Bare `0` still lexes as `0`.
4. **Cross-base equivalence** — `0o755 == 493`, `0o755 == 0x1ED`, all three constants behave identically in every codegen and arithmetic test.
5. **Mixed-in-expression** — `0o755 & 0o077`, `0o100000 | 0o644`, `(st_mode & 0o170000) == 0o040000`.

## Alternatives considered

### Bare leading zero (C-style: `0755`)

C and POSIX shell both interpret bare `0755` as octal 493. The C convention is the most widely-deployed; using it would be familiar to systems programmers.

**Rejected** because of a well-documented class of bug: `0123` parsing as octal `83` (1×64+2×8+3) when a developer meant decimal `123`. Real production outages have come from this — IP addresses copied with leading zeros, version strings, log-level constants. Cyrius doesn't have this footgun today (`0755` is decimal); adding C-style octal would introduce it. The `0o` prefix is the post-C consensus precisely because every major modern language hit this and converged on disambiguation.

### `0t755` or `0q755` (non-`o` prefix)

The letter `o` looks like the digit `0` in some fonts. Suggested alternatives over the years include `0t` ("trinary triplet"), `0q` ("quaternary" — no, that's already wrong), `0c` ("count by 8"). None has caught on.

**Rejected** — the readability concern is real for `1` vs `l`, less acute for `0` vs `o` (the digit is round and the letter is round; in most fonts the letter is wider). `0o` is the lingua franca and matches what every developer types in Python/Rust/Go. Inventing a new prefix gains nothing and costs muscle memory.

### `8r755` (Smalltalk / Common Lisp style: `<radix>r<digits>`)

General-radix syntax: `8r755`, `16rDEADBEEF`, `2r10110001`. Strictly more general than per-base prefixes.

**Rejected as out of scope.** If a Cyrius consumer wants base-7 or base-12 literals, that's a separate proposal with separate motivation. Octal is the immediate need; hex is already done; binary (`0b`) is a probable follow-up but doesn't need to ride along.

### `Octal(755)` or `mode!(0,7,5,5)` (macro/intrinsic instead of literal syntax)

Some languages (e.g. older Ada dialects) handle bases via macros or constructor functions. Cyrius could ship `octal(value)` as a stdlib function.

**Rejected** because the resulting code (`sys_mkdir(path, octal(755))`) is verbose at every call site, doesn't compose into bitmasks naturally (`octal(755) & octal(077)` is a mouthful), and isn't a constant expression in any meaningful sense — the lexer/parser would still see a function call. The whole point is to put the constant directly into the source where the eye expects to find it.

## Adjacent: binary literals (`0b...`)?

Binary literals (`0b1101`) are the same shape of change: another `LEXNUM` branch + a `LEXBIN` routine identical to `LEXOCT` but with `<< 1` and digits `0..1`. Several current call sites would benefit — bitmask construction is the use case (e.g. AGNOS page-table flags).

**Recommendation: separate proposal**, filed when a concrete consumer asks. This proposal stays scoped to octal so the decision is clean (octal has obvious immediate consumers; binary's consumers can speak for themselves).

## Work breakdown

1. **Lexer change.** Add the `0o` branch to `LEXNUM`; implement `LEXOCT` mirroring `LEXHEX`. ~30 LOC in `src/frontend/lex.cyr`.
2. **Negative-path error messages.** Match the quality of existing `\x` / `\u` escape errors in the lexer — clear, specific, file:line correct.
3. **Test suite.** Positive, negative, non-regression, cross-base equivalence, mixed-expression — itemized above.
4. **CHANGELOG.** Cyrius CHANGELOG entry under the version that lands it (likely `[Unreleased] / Added`).
5. **Vidya documentation.** Update `vidya/content/cyrius/language.toml` (or wherever integer-literal syntax is documented) to add the octal form alongside hex and decimal.
6. **Stdlib follow-up (optional, same release or later).** Rewrite the obvious octal-natural constants in `syscalls_*_linux.cyr` to use `0o` form. Cosmetic; no behavior change.

## Open questions

- **Should `0o0` be valid?** Yes — degenerate but consistent with `0x0` and `0`. No special-case in the lexer.
- **Should uppercase `0O` be accepted?** No — matches the existing `0x` lowercase-only policy. Easier to teach a single rule than two rules with the same outcome.
- **Should this also enable octal in `\x##`-style string escapes (i.e. `\o###`)?** No — separate change, separate motivation, separate proposal if anyone asks.
- **Interaction with float literals.** None. The decimal lexer's `digits.digits` float path runs only in `LEXDEC`; `LEXOCT` does not branch into it. `0o7.5` is a lex error, as specified.

## Decision required

Not blocking for any current Cyrius version. Slot for **v5.12.x** acceptance whenever a quality-of-life slot is being chosen.

- [ ] Approve `0o`-prefix octal literals as a v5.12.x candidate.
- [ ] Approve the syntax rules (mandatory `0o`, lowercase only, underscores allowed, no float fractional, `0..7` only).
- [ ] Approve the lexer-only scope (no parser/codegen/type-system impact).
- [ ] Approve the optional stdlib cleanup follow-up (rewrite octal-natural `syscalls_*_linux.cyr` constants).
- [ ] Approve deferring binary literals (`0b...`) to a separate proposal.

Promote to an ADR if approved before implementation — the "why `0o` not bare-leading-zero" and "why not the radix-prefix general form" reasoning is durable language-design content and the next person to wonder about it deserves the answer.

## Cross-references

- First concrete consumer: kriya `mkdir` 2026-05-17 — see [`kriya/src/cmd/mkdir.cyr`](https://github.com/MacCracken/kriya/blob/main/src/cmd/mkdir.cyr) for the `511 # 0o777` lines this proposal would eliminate.
- Existing hex-literal implementation: `src/frontend/lex.cyr::LEXHEX` (model for the new `LEXOCT`).
- CVE example of bare-leading-zero footgun: https://www.cve.org/CVERecord?id=CVE-2002-1531
- Cross-language convergence on `0o` prefix: Python (PEP 3127), Rust (RFC 0879), Go 1.13 release notes.
