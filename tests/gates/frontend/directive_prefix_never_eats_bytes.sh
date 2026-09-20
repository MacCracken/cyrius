#!/bin/sh
# directive_prefix_never_eats_bytes.sh — v6.6.6 bite 5c.
#
# A PREPROCESSOR DIRECTIVE USED TO CONSUME ITS BYTES ON THE PREDICATE MATCH, AND
# ONLY THEN CHECK WHETHER IT WAS REALLY A DIRECTIVE. Two places did it:
#
#   PP_REF_PASS   `#ref `  matched → `_rhandled = 1; ip = ip + 5;` → look for `"`
#   include x2    `include ` matched → `ip = ip + 8;`              → look for `"`
#
# When the `"` was absent the bytes were already gone. For `#ref ` that is a
# SILENT MUTILATION OF A COMMENT: `#` opens a comment, so `#ref counting is fine`
# is ordinary prose, and it reached the lexer as `counting is fine` — code. It is
# invisible until the same file also holds a real `#ref "x"`, because only that
# sets `found` and triggers PP_REF_PASS's copy-back; with one present, the
# comment's neighbour dies with `expected '=', got identifier 'is'`, naming a
# word from the middle of a comment. For `include ` the symptom is a diagnostic
# pointing at column 5 of a line whose column 5 is `u`.
#
# Fixed by checking the quote BEFORE anything moves: `#ref ` without one stays a
# comment (nothing else is correct — it IS a comment), and `include ` without one
# is a clear error, since `include` at column 0 is a directive and nothing else
# (census: zero such lines in this repo or any sibling under ~/Repos).
#
# ⭐ THE ORACLE FOR THE COMMENT AXES IS A TWIN PROGRAM. A comment must not change
# what is compiled, so each `#ref …` comment is scored against the same program
# with the comment written `# ref …` — a spelling no predicate can ever match —
# and the two binaries must be BYTE-IDENTICAL. Nothing asks the compiler what a
# comment ought to do.
#
# Axes:
#   1  the filed shape: a `#ref ` COMMENT alongside a real `#ref "x"` compiles,
#      runs, and is byte-identical to its spaced twin
#   2  a `#ref ` comment with NO real `#ref` in the file (the latent case)
#   3  anti-vacuous: the real `#ref "x"` still expands — the program returns the
#      value from the TOML file, which the gate wrote and never re-read
#   4  `include ` with no quoted name is a CLEAR error that names what it wants,
#      not a token from the middle of the mangled line
#   5  the same, in an INCLUDED file — PP_IFDEF_PASS carries its own copy of the
#      include handler and needed the same pre-check
#   6  over-correction guard: a real `include "x"` still resolves and runs
#   7  census, derived from the source: every `ISINCLUDE` handler site carries a
#      PP_INCLUDE_NEEDS_QUOTE pre-check
#
# MUTATION LEDGER (2026-09-19, cycc 1,310,920 B, measured). Each mutation is
# applied to the working tree, a compiler built from it with the good cycc, and
# the gate run against that compiler (CYRIUS_CC); the tree is restored after:
#   M1 PP_REF_PASS returned to the pre-6.6.6 order (`_rhandled = 1; ip = ip + 5;`
#      on the predicate match) → 1 FAIL / 6 ok: axis 1, with the original
#      diagnostic `<source>:2:10: expected '=', got identifier 'is'`
#      ⚠ AXIS 2 STAYS GREEN UNDER M1, AND THAT IS THE POINT OF HAVING BOTH: with
#      no real `#ref` in the file, `found` is never set, PP_REF_PASS's output is
#      discarded and the mutilation is invisible. A gate built only from the
#      "obvious" one-line case would have scored the defect GREEN.
#   M2 both `PP_INCLUDE_NEEDS_QUOTE();` pre-checks deleted
#      → 3 FAIL / 4 ok: axes 4 and 5 (each reporting a token from the middle of
#      the mangled line — `<source>:1:5`) and axis 7 (census 2 sites, 0 checks)
#   M3 only the PP_IFDEF_PASS pre-check deleted
#      → 2 FAIL / 5 ok: axis 5 and axis 7 (2 sites, 1 check). Axis 4 stays green,
#      which is why the two include sites are separate axes.
#   real tree → 7/7 green
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ulimit -c 0 2>/dev/null || true

# The value lives in the TOML file the gate writes; the program's exit code must
# equal it, and the number is never read back out of the generated .cyr.
REFVAL=37
printf 'K = %s\n' "$REFVAL" > "$D/cfg.toml"

# compile $1.cyr -> $1.bin ; sets rc. Fails loudly on an empty binary.
compile() {
    rc=0
    ( cd "$D" && "$CC" < "$1.cyr" > "$1.bin" 2> "$1.err" ) || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/$1.bin" ]; then
        printf '  FAIL: %s compiled to an EMPTY binary\n' "$1"; fail=$((fail+1)); rc=99
    fi
    [ -s "$D/$1.bin" ] && chmod +x "$D/$1.bin"
    return 0
}

run_exit() { got=0; ( "$D/$1.bin" ) || got=$?; }

# ── axis 1 — the filed shape, plus its spaced twin.
printf '#ref "cfg.toml"\n#ref counting is fine\nvar A = K;\nsyscall(60, A);\n' > "$D/a1.cyr"
printf '#ref "cfg.toml"\n# ref counting is fine\nvar A = K;\nsyscall(60, A);\n' > "$D/a1t.cyr"
compile a1
compile a1t
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis 1 twin — the SPACED control did not compile: %s\n' \
        "$(head -1 "$D/a1t.err" | cut -c1-80)"
    fail=$((fail+1))
fi
if [ ! -s "$D/a1.bin" ]; then
    printf '  FAIL: axis 1 — a `#ref ` COMMENT broke the compile: %s\n' \
        "$(grep -m1 error "$D/a1.err" | cut -c1-80)"
    fail=$((fail+1))
else
    run_exit a1
    if [ "$got" != "$REFVAL" ]; then
        printf '  FAIL: axis 1 — exit=%s, want %s (the TOML value)\n' "$got" "$REFVAL"
        fail=$((fail+1))
    elif ! cmp -s "$D/a1.bin" "$D/a1t.bin"; then
        printf '  FAIL: axis 1 — compiled, but not to the spaced twin'"'"'s bytes\n'
        fail=$((fail+1))
    else
        printf '  ok: axis 1 — a `#ref ` comment beside a real #ref is inert (exit %s, twin-identical)\n' "$got"
        pass=$((pass+1))
    fi
fi

# ── axis 2 — the latent case: no real #ref in the file at all.
printf '#ref counting is fine\nvar A = 42;\nsyscall(60, A);\n'  > "$D/a2.cyr"
printf '# ref counting is fine\nvar A = 42;\nsyscall(60, A);\n' > "$D/a2t.cyr"
compile a2; compile a2t
if [ ! -s "$D/a2.bin" ] || [ ! -s "$D/a2t.bin" ]; then
    printf '  FAIL: axis 2 — a lone `#ref ` comment did not compile: %s\n' \
        "$(grep -m1 error "$D/a2.err" | cut -c1-80)"
    fail=$((fail+1))
else
    run_exit a2
    if [ "$got" = 42 ] && cmp -s "$D/a2.bin" "$D/a2t.bin"; then
        printf '  ok: axis 2 — a lone `#ref ` comment is inert (exit 42, twin-identical)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis 2 — exit=%s (want 42) or bytes differ from the spaced twin\n' "$got"
        fail=$((fail+1))
    fi
fi

# ── axis 3 — anti-vacuous: the real directive still expands.
printf '#ref "cfg.toml"\nvar A = K;\nsyscall(60, A);\n' > "$D/a3.cyr"
compile a3
if [ "$rc" -ne 0 ] || [ ! -s "$D/a3.bin" ]; then
    printf '  FAIL: axis 3 — a real #ref no longer expands: %s\n' \
        "$(grep -m1 error "$D/a3.err" | cut -c1-80)"
    fail=$((fail+1))
else
    run_exit a3
    if [ "$got" = "$REFVAL" ]; then
        printf '  ok: axis 3 — a real `#ref "cfg.toml"` still expands (exit %s)\n' "$got"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 3 — exit=%s, want %s\n' "$got" "$REFVAL"
        fail=$((fail+1))
    fi
fi

# ── axis 4 — `include ` with no quoted name.
printf 'include foo bar\nvar A = 42;\nsyscall(60, A);\n' > "$D/a4.cyr"
compile a4
if [ "$rc" -eq 0 ]; then
    printf '  FAIL: axis 4 — `include foo bar` compiled\n'; fail=$((fail+1))
elif grep -q 'include expects a quoted filename' "$D/a4.err"; then
    printf '  ok: axis 4 — `include` with no quote names what it wants\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis 4 — refused, but the message names a downstream token: %s\n' \
        "$(head -1 "$D/a4.err" | cut -c1-80)"
    fail=$((fail+1))
fi

# ── axis 5 — the same inside an INCLUDED file (PP_IFDEF_PASS's own copy).
printf 'fn inner(): i64 { return 5; }\ninclude foo bar\n' > "$D/inner5.cyr"
printf 'include "inner5.cyr"\nvar A = inner();\nsyscall(60, A);\n' > "$D/a5.cyr"
compile a5
if [ "$rc" -eq 0 ]; then
    printf '  FAIL: axis 5 — a quote-less include INSIDE an include compiled\n'; fail=$((fail+1))
elif grep -q 'include expects a quoted filename' "$D/a5.err"; then
    printf '  ok: axis 5 — the nested include site carries the same pre-check\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis 5 — refused, but not by the include check: %s\n' \
        "$(head -1 "$D/a5.err" | cut -c1-80)"
    fail=$((fail+1))
fi

# ── axis 6 — over-correction guard: a real include still resolves.
printf 'fn six(): i64 { return 6; }\n' > "$D/six.cyr"
printf 'include "six.cyr"\nvar A = six();\nsyscall(60, A);\n' > "$D/a6.cyr"
compile a6
if [ "$rc" -ne 0 ] || [ ! -s "$D/a6.bin" ]; then
    printf '  FAIL: axis 6 — a real include stopped working: %s\n' \
        "$(grep -m1 error "$D/a6.err" | cut -c1-80)"
    fail=$((fail+1))
else
    run_exit a6
    if [ "$got" = 6 ]; then
        printf '  ok: axis 6 — a real `include "six.cyr"` still resolves (exit 6)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis 6 — exit=%s, want 6\n' "$got"
        fail=$((fail+1))
    fi
fi

# ── axis 7 — census, derived from the source. Every place that HANDLES an
#    ISINCLUDE match must carry the pre-check; the two counts are read from two
#    different strings so one cannot be satisfied by editing the other.
nsites=$(grep -c 'if (ISINCLUDE(' src/frontend/lex_pp.cyr || true)
nchecks=$(grep -c 'PP_INCLUDE_NEEDS_QUOTE();' src/frontend/lex_pp.cyr || true)
if [ "$nsites" = "$nchecks" ] && [ "$nsites" -ge 2 ]; then
    printf '  ok: axis 7 — %s ISINCLUDE handler sites, %s with the quote pre-check\n' \
        "$nsites" "$nchecks"
    pass=$((pass+1))
else
    printf '  FAIL: axis 7 — census: %s ISINCLUDE handler sites but %s pre-checks\n' \
        "$nsites" "$nchecks"
    fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: directive-prefix-never-eats-bytes — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: directive-prefix-never-eats-bytes — %s/%s axes green\n' "$pass" "$pass"
