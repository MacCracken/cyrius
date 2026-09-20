#!/bin/sh
# lexer_attribute_word_boundary.sh — v6.6.6 bite 5a.
#
# A COMMENT WHOSE FIRST WORD MERELY STARTS WITH AN ATTRIBUTE NAME WAS PARSED AS
# CODE. The `#` branch of src/frontend/lex.cyr compared a byte PREFIX for each of
# its ten attributes (`#assert`, `#regalloc`, `#deprecated`, `#must_use`, `#pure`,
# `#io`, `#alloc`, `#naked`, `#inline`, `#pe_import`) and, on a match, emitted the
# token and kept lexing the SAME line — with no check that the name had ENDED. So
#
#     #ioctl numbers
#
# lexed as `#io` + the identifier `ctl`, and the rest of the "comment" became
# code: `error: expected '=', got identifier 'numbers'`, pointing at the comment's
# SECOND WORD rather than at the cause. The set of words that broke a comment was
# invisible to the author. Filed as
# docs/development/issues/2026-09-19-lexer-attribute-prefix-swallows-comments.md.
#
# v6.6.6 added LEXATTRBOUND: an attribute name must be followed by whitespace, end
# of input, or `(` (the `#deprecated(` / `#pe_import(` form). Strictly more
# permissive — no program that compiled before could contain `#io<ident-byte>`,
# because the tail was parsed as code and failed.
#
# ⭐ HOW EXPECTED IS DERIVED THE OTHER WAY ROUND. Group A never asks the compiler
# what a comment should produce. It compiles the SPACED twin (`# ioctl numbers`),
# which no prefix rule can ever read as an attribute, and requires the unspaced
# form to produce a BYTE-IDENTICAL binary. The oracle is a different program.
#
# Group B is the over-correction guard: every attribute must still ARM. Its
# attribute list is DERIVED from src/frontend/lex.cyr itself (the
# `token NNN = HASH_*` comments in the `#` branch), and the gate fails if that
# census does not match the probe table below or the count of LEXATTRBOUND call
# sites — so a new attribute added without a boundary, or without a row here,
# turns this gate RED instead of being silently uncovered.
#
# Axes:
#   A1..A7  each comment from the filing's table compiles AND is byte-identical
#           to its spaced twin (A1 is the filed repro verbatim)
#   A8      the spaced twin itself still compiles (anti-vacuous)
#   B0      census: lex.cyr's attribute set == the probe table == the boundary
#           call-site count
#   B1..B10 each attribute still arms, by its own observable effect
#   C1      cyrlint reads `#ioctl notes {` as a COMMENT (no false brace warning)
#   C2      cyrfmt --check agrees with the compiler about the same line
#   C3      over-correction guard: cyrlint still reads `#naked fn f() {` as an
#           attribute (the v6.6.5 defect this must not undo)
#
# MUTATION LEDGER (2026-09-19, cycc 1,310,856 B, measured). Each mutation is
# applied to the working tree, a compiler is built from it with the good cycc,
# and the gate is run against that compiler (CYRIUS_CC); the tree is restored
# from a copy afterwards:
#   M1 LEXATTRBOUND body replaced by `return 1;` (the pre-6.6.6 prefix match)
#      → 7 FAIL / 15 ok: A1..A7, each reproducing the filing's error message
#        verbatim (A1 `expected '=', got identifier 'numbers'`)
#   M2 LEXATTRBOUND body replaced by `return 0;` (nothing ever arms)
#      → 10 FAIL / 12 ok: B1..B10 — the axis group that stops the fix being
#        "make every `#` a comment". A1..A8 stay green.
#   M3 the `b == 40` (`(`) row deleted from LEXATTRBOUND
#      → 2 FAIL / 20 ok: B3 (#deprecated) and B9 (#pe_import(), the two
#        attributes whose boundary byte is `(`
#   M4 one LEXATTRBOUND call site neutered (`#io` → `if (1 == 1)`)
#      → 3 FAIL / 19 ok: B0 on the call-site census (9 != 10), plus A1 and A7
#   M5 `_lx_attr_bound` in programs/cyrlint.cyr forced to 1 → 1 FAIL: C1
#   M6 `_cf_attr_bound` in programs/cyrfmt.cyr  forced to 1 → 1 FAIL: C2
#   real tree → 22/22 green
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ulimit -c 0 2>/dev/null || true

# Compile $D/<name>.cyr. Sets `rc`; fails the axis loudly on an empty binary.
compile() {
    rc=0
    ( cd "$D" && "$CC" < "$1.cyr" > "$1.bin" 2> "$1.err" ) || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/$1.bin" ]; then
        printf '  FAIL: %s compiled to an EMPTY binary\n' "$1"
        fail=$((fail+1)); rc=99
    fi
    [ -s "$D/$1.bin" ] && chmod +x "$D/$1.bin"
    return 0
}

# ── Group A — the filing's table. Every row must compile and match its spaced twin.
printf '# ioctl numbers\nvar A = 42;\nsyscall(60, A);\n' > "$D/twin.cyr"
compile twin
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis A8 — the spaced twin `# ioctl numbers` does not compile: %s\n' \
        "$(head -1 "$D/twin.err" | cut -c1-90)"
    fail=$((fail+1))
else
    got=0; ( "$D/twin.bin" ) || got=$?
    if [ "$got" = 42 ]; then
        printf '  ok: axis A8 — the spaced twin compiles and runs (exit 42)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis A8 — spaced twin exit=%s, want 42\n' "$got"
        fail=$((fail+1))
    fi
fi

ax=0
for row in 'ioctl numbers' 'allocator notes' 'inlined by hand' 'assertion holds' \
           'purely local' 'naked-eye check' 'iota'; do
    ax=$((ax+1))
    printf '#%s\nvar A = 42;\nsyscall(60, A);\n' "$row" > "$D/a$ax.cyr"
    compile "a$ax"
    if [ "$rc" -ne 0 ]; then
        printf '  FAIL: axis A%s — `#%s` did not compile: %s\n' \
            "$ax" "$row" "$(grep -m1 error "$D/a$ax.err" | cut -c1-90)"
        fail=$((fail+1)); continue
    fi
    if ! cmp -s "$D/a$ax.bin" "$D/twin.bin"; then
        printf '  FAIL: axis A%s — `#%s` compiled, but not to the spaced twin'\''s bytes\n' \
            "$ax" "$row"
        fail=$((fail+1)); continue
    fi
    got=0; ( "$D/a$ax.bin" ) || got=$?
    if [ "$got" = 42 ]; then
        printf '  ok: axis A%s — `#%s` is a comment (binary == spaced twin)\n' "$ax" "$row"
        pass=$((pass+1))
    else
        printf '  FAIL: axis A%s — `#%s` exit=%s, want 42\n' "$ax" "$row" "$got"
        fail=$((fail+1))
    fi
    rm -f "$D/a$ax.bin"
done

# ── Axis B0 — census. Three independent counts of "how many attributes are there".
#    (a) the token comments in the `#` branch of lex.cyr
#    (b) the LEXATTRBOUND call sites in the same file
#    (c) the probe table below
grep -oE 'token [0-9]+ = HASH_[A-Z_]+' src/frontend/lex.cyr \
    | sed 's/.*HASH_//' | tr 'A-Z' 'a-z' | sort -u > "$D/census.txt"
ncensus=$(grep -c . "$D/census.txt" || true)
nbound=$(grep -c 'LEXATTRBOUND(S, p + ' src/frontend/lex.cyr || true)
PROBED='alloc assert deprecated inline io must_use naked pe_import pure regalloc'
for a in $PROBED; do printf '%s\n' "$a"; done | sort > "$D/probed.txt"
nprobed=$(grep -c . "$D/probed.txt" || true)
missing=$(comm -3 "$D/probed.txt" "$D/census.txt" | tr -d '\t' | tr '\n' ' ')
if [ "$ncensus" = "$nbound" ] && [ "$ncensus" = "$nprobed" ] && [ -z "$(printf '%s' "$missing" | tr -d ' ')" ]; then
    printf '  ok: axis B0 — %s attributes in lex.cyr, %s boundary call sites, %s probed\n' \
        "$ncensus" "$nbound" "$nprobed"
    pass=$((pass+1))
else
    printf '  FAIL: axis B0 — census mismatch: lex.cyr lists %s, %s boundary call sites, %s probed; set difference: %s\n' \
        "$ncensus" "$nbound" "$nprobed" "$missing"
    fail=$((fail+1))
fi

# Each attribute still arms. `want` is a string that must appear in the compiler's
# stderr (or `exit:N` for an exit code) and that a COMMENT can never produce.
arm() {
    ax=$1; want=$2; desc=$3
    printf '%b' "$4" > "$D/$ax.cyr"
    compile "$ax"
    case "$want" in
        exit:*)
            if [ "$rc" -ne 0 ]; then
                printf '  FAIL: axis %s — %s: did not compile: %s\n' \
                    "$ax" "$desc" "$(grep -m1 error "$D/$ax.err" | cut -c1-90)"
                fail=$((fail+1)); return 0
            fi
            got=0; ( "$D/$ax.bin" ) || got=$?
            if [ "$got" = "${want#exit:}" ]; then
                printf '  ok: axis %s — %s (exit %s)\n' "$ax" "$desc" "$got"
                pass=$((pass+1))
            else
                printf '  FAIL: axis %s — %s: exit=%s, want %s\n' \
                    "$ax" "$desc" "$got" "${want#exit:}"
                fail=$((fail+1))
            fi
            ;;
        *)
            if grep -qF "$want" "$D/$ax.err"; then
                printf '  ok: axis %s — %s\n' "$ax" "$desc"
                pass=$((pass+1))
            else
                printf '  FAIL: axis %s — %s: no "%s" in the diagnostics (%s)\n' \
                    "$ax" "$desc" "$want" "$(head -1 "$D/$ax.err" | cut -c1-70)"
                fail=$((fail+1))
            fi
            ;;
    esac
    rm -f "$D/$ax.bin"
}

arm B1 '#assert' '#assert still evaluates (a false assert is an error)' \
'#assert 1 == 2\nvar A = 42;\nsyscall(60, A);\n'
arm B2 'exit:7' '#regalloc still arms (same-line fn survives)' \
'#regalloc fn f(): i64 { return 7; }\nvar A = f();\nsyscall(60, A);\n'
arm B3 "is deprecated: old" '#deprecated("...") still warns at the call site' \
'#deprecated("old")\nfn f(): i64 { return 1; }\nvar A = f();\nsyscall(60, A);\n'
arm B4 '#must_use result' '#must_use still warns on a discarded result' \
'#must_use\nfn f(): i64 { return 1; }\nfn g(): i64 { f(); return 0; }\nvar A = g();\nsyscall(60, A);\n'
arm B5 '#pure fn calls #io fn' '#pure and #io still arm (the purity warning)' \
'#io\nfn w(): i64 { return 0; }\n#pure\nfn p(): i64 { w(); return 3; }\nvar A = p();\nsyscall(60, A);\n'
arm B6 '#pure fn calls #alloc fn' '#alloc still arms' \
'#alloc\nfn a1(): i64 { return 8; }\n#pure\nfn p(): i64 { a1(); return 3; }\nvar A = p();\nsyscall(60, A);\n'
arm B7 '#naked fn' '#naked still arms (return rejected in a naked body)' \
'#naked fn f(): i64 { return 7; }\nvar A = 1;\nsyscall(60, A);\n'
arm B8 '#inline ignored' '#inline still arms (the cannot-honour warning)' \
'#inline\nfn f(a, b, c): i64 { return a + b + c; }\nvar A = f(1,2,3);\nsyscall(60, A);\n'
# B9 uses the `(` form on purpose: it is the second attribute (with #deprecated)
# whose boundary byte is `(` rather than whitespace, so dropping that row from
# LEXATTRBOUND would turn every real `#pe_import("dll", "sym")` into a comment and
# silently drop the PE import table.
arm B9 'expected string, got number 3' '#pe_import( still arms (the `(` boundary)' \
'#pe_import(3)\nvar A = 42;\nsyscall(60, A);\n'
arm B10 "expected '('" '#pe_import arms at end of line too (the whitespace boundary)' \
'#pe_import\nvar A = 42;\nsyscall(60, A);\n'

# ── Group C — the three mirror readers must take the same boundary as the lexer,
#    or a tool disagrees with the compiler about which `#` lines are comments.
build_tool() {
    "$CC" < "programs/$1.cyr" > "$D/$1" 2> "$D/$1.buildlog" || {
        printf '  FAIL: could not build %s\n' "$1"; fail=$((fail+1)); return 1; }
    [ -s "$D/$1" ] || { printf '  FAIL: %s built EMPTY\n' "$1"; fail=$((fail+1)); return 1; }
    chmod +x "$D/$1"
    return 0
}

printf '#ioctl notes here {\n#naked\nfn isr(): i64 { return 1; }\n' > "$D/tool.cyr"
printf '#naked fn isr(): i64 { return 1; }\n' > "$D/tool_attr.cyr"

if build_tool cyrlint; then
    out=$("$D/cyrlint" "$D/tool.cyr" 2>&1) || true
    if printf '%s' "$out" | grep -q '^0 warnings'; then
        printf '  ok: axis C1 — cyrlint reads `#ioctl notes here {` as a comment\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis C1 — cyrlint warned on an attribute-prefixed comment: %s\n' \
            "$(printf '%s' "$out" | grep -m1 warning | cut -c1-90)"
        fail=$((fail+1))
    fi
    out=$("$D/cyrlint" "$D/tool_attr.cyr" 2>&1) || true
    if printf '%s' "$out" | grep -q '^0 warnings'; then
        printf '  ok: axis C3 — cyrlint still reads `#naked fn f() {` as an attribute\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis C3 — cyrlint lost the attribute reading: %s\n' \
            "$(printf '%s' "$out" | grep -m1 warning | cut -c1-90)"
        fail=$((fail+1))
    fi
fi

if build_tool cyrfmt; then
    rcf=0; "$D/cyrfmt" --check "$D/tool.cyr" >/dev/null 2>&1 || rcf=$?
    if [ "$rcf" -eq 0 ]; then
        printf '  ok: axis C2 — cyrfmt --check agrees the line is a comment\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis C2 — cyrfmt --check rejected an attribute-prefixed comment (rc=%s)\n' "$rcf"
        fail=$((fail+1))
    fi
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: lexer-attribute-word-boundary — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: lexer-attribute-word-boundary — %s/%s axes green\n' "$pass" "$pass"
