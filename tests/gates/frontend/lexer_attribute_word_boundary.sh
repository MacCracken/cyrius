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
# v6.6.6 added LEXATTRBOUND: an attribute name must be followed by whitespace or
# end of input — or `(`, at the THREE sites that pass ap=1. Strictly more
# permissive — no program that compiled before could contain `#io<ident-byte>`,
# because the tail was parsed as code and failed.
#
# ⚠ THE FIRST CUT TOOK `(` AS A BOUNDARY AT ALL TEN SITES, which left the filed
# defect standing for a narrower input class: `#io(fd) reads a byte` still died
# with `unexpected '('`, and so did `#naked(truth)`, `#pure(ly)`, `#alloc(16)`,
# `#inline(always)`, `#must_use(result)` and `#regalloc(2)`. Only `#deprecated(`
# and `#pe_import(` are syntax. `#assert(` keeps ap=1 on purpose (axis B11): the
# compiler rejects that form OUT LOUD today, and a comment reading would silently
# drop an assertion — a loud error on rare prose beats a silent hole in a check.
#
# The review round found the same shape TWICE MORE, in the preprocessor's own
# scanners (PP_NAMEBOUND now bounds them) and once more in the api-surface tool.
# Group D covers those; the shape, not the name, is what this gate pins.
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
#   A0      the spaced twin itself still compiles (anti-vacuous)
#   A1..A7  each comment from the filing's table compiles AND is byte-identical
#           to its spaced twin (A1 is the filed repro verbatim)
#   A8..A9  the `(` shapes the first cut still refused: `#io(fd) reads a byte`,
#           `#naked(truth) hurts`
#   B0      census: lex.cyr's attribute set == the probe table == the boundary
#           call-site count
#   B1..B10 each attribute still arms, by its own observable effect
#   B11     `#assert(` is STILL A LOUD ERROR (the deliberate exception above)
#   C1      cyrlint reads `#ioctl notes {` as a COMMENT (no false brace warning)
#   C2      cyrfmt --check agrees with the compiler about the same line
#   C3      over-correction guard: cyrlint still reads `#naked fn f() {` as an
#           attribute (the v6.6.5 defect this must not undo)
#   C4      cyrdoc reads an attribute-prefixed comment as DOCUMENTATION — the
#           third mirror, which this gate claimed to cover from the day it landed
#           and did not; scored against the spaced twin so it cannot be vacuous
#   C5      over-correction guard for cyrdoc: a real `#inline` is still an
#           attribute, so the fn below it is still reported undocumented
#   E1..E6  the three probes left unbounded in the same file after D (bite 5h):
#           ISENDIF, ISENDPLAT, ISSRCLINE. ISELSE already carried the boundary
#           inline, which is why these three stood out. `#endifoo note` — a
#           COMMENT — CLOSED a conditional, so code inside a skipped `#ifdef`
#           was compiled in silently; `#@srclinex 10` shifted every diagnostic
#           in the file by one line. E2/E4/E6 are the arm axes.
#   D1..D6  the SAME root cause in the preprocessor (review round): PP_IS_HOST_ONLY
#           and the three ISDERIVE* probes in src/frontend/lex_pp.cyr, plus the
#           fourth reader of `#derive` (programs/cyrius_api_surface.cyr). These
#           fail SILENTLY rather than with a diagnostic, which is why they are here
#           and not left to the filing's table: `#host_onlyish note` marked a module
#           host-only and broke every bare-metal build that included it, and
#           `#derive(Serialize)x note` armed the derive machinery and CHANGED THE
#           EMITTED BINARY (4472 B vs the twin's 4456 B) with rc=0 either way.
#
# MUTATION LEDGER (2026-09-19, cycc 1,310,920 B, measured). Each mutation is
# applied to a scratch copy of the tree, a compiler is built from it with the good
# cycc, and the gate is run against that compiler (CYRIUS_CC) with ROOT set to the
# scratch tree; the tree is restored afterwards. Only the FAILING axes are listed.
#   M1  LEXATTRBOUND body replaced by `return 1;` (the pre-6.6.6 prefix match)
#       → 9 FAIL: A1..A9, each reproducing the filing's error message verbatim
#         (A1 `expected '=', got identifier 'numbers'`)
#   M2  LEXATTRBOUND body replaced by `return 0;` (nothing ever arms)
#       → 11 FAIL: B1..B11 — the axis group that stops the fix being "make every
#         `#` a comment"; A0..A9 stay green, which is the point of having both.
#   M3  the `b == 40` (`(`) row deleted from LEXATTRBOUND
#       → 3 FAIL: B3 (#deprecated), B9 (#pe_import() and B11 (#assert( goes silent)
#   M10 the `(` row made unconditional again — `if (b == 40) { return 1; }`, i.e.
#       the review round's first cut, `(` a boundary at all ten sites
#       → 2 FAIL: A8, A9 (`#io(fd) reads a byte`, `#naked(truth) hurts`)
#   M4  one LEXATTRBOUND call site neutered (`#io` → `if (1 == 1)`)
#       → 4 FAIL: B0 on the call-site census (9 != 10), plus A1, A7 and A8
#   M5  `_lx_attr_bound` in programs/cyrlint.cyr forced to 1 → 1 FAIL: C1
#   M6  `_cf_attr_bound` in programs/cyrfmt.cyr  forced to 1 → 1 FAIL: C2
#   M7  PP_NAMEBOUND body replaced by `return 1;` (the preprocessor's prefix match)
#       → 6 FAIL: D1 (a comment refuses the bare-metal build), D3 (the derive
#         comment compiles to DIFFERENT bytes), D4 (a comment generates
#         accessors), E1 (a comment closes a skipped #ifdef, and the code inside
#         it compiles), E3 (same for #ifplat), E5 (a comment shifts every
#         diagnostic line). D6 stays green — it is the mirror, and M9 is its
#         mutation.
#   M8  PP_NAMEBOUND body replaced by `return 0;` (nothing ever arms)
#       → D2, D5, E2, E4, E6 RED, and the mutated compiler can no longer build
#         cyrlint, cyrfmt, cyrdoc or api-surface AT ALL — every `#endif` in their
#         sources stops closing — so groups C and D6 report build failures rather
#         than axis results. Recorded as measured; it is the widest blast radius
#         of any mutation here and the clearest proof the boundary is load-bearing.
#   M9  `_api_derive_bound` in programs/cyrius_api_surface.cyr forced to 1
#       → 1 FAIL: D6, listing four accessors for a comment
#   M11 `_doc_attr_bound` in programs/cyrdoc.cyr forced to 1 → 1 FAIL: C4
#   M12 `_doc_attr_bound` in programs/cyrdoc.cyr forced to 0 → 1 FAIL: C5
#   real tree → 39/39 green
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
    printf '  FAIL: axis A0 — the spaced twin `# ioctl numbers` does not compile: %s\n' \
        "$(head -1 "$D/twin.err" | cut -c1-90)"
    fail=$((fail+1))
else
    got=0; ( "$D/twin.bin" ) || got=$?
    if [ "$got" = 42 ]; then
        printf '  ok: axis A0 — the spaced twin compiles and runs (exit 42)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis A0 — spaced twin exit=%s, want 42\n' "$got"
        fail=$((fail+1))
    fi
fi

ax=0
for row in 'ioctl numbers' 'allocator notes' 'inlined by hand' 'assertion holds' \
           'purely local' 'naked-eye check' 'iota' 'io(fd) reads a byte' \
           'naked(truth) hurts'; do
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
# B11 is the DELIBERATE EXCEPTION, and it is an axis so that a later "no paren
# anywhere" tidy-up cannot make it silent. `#assert(8 == 9)` is not syntax — the
# compiler rejects it — but it is plainly an assertion the author wrote, and
# reading it as a comment would DROP a compile-time check without a word. So
# `#assert` passes ap=1 like `#deprecated` and `#pe_import`, and stays loud.
arm B11 '#assert: expected constant expression' \
'#assert( stays a LOUD error rather than becoming a silent comment' \
'#assert(8 == 9)\nvar A = 42;\nsyscall(60, A);\n'

# ── Group C — the three mirror readers must take the same boundary as the lexer,
#    or a tool disagrees with the compiler about which `#` lines are comments.
build_tool() {
    "$CC" < "programs/$1.cyr" > "$D/$1" 2> "$D/$1.buildlog" || {
        printf '  FAIL: could not build %s\n' "$1"; fail=$((fail+1)); return 1; }
    [ -s "$D/$1" ] || { printf '  FAIL: %s built EMPTY\n' "$1"; fail=$((fail+1)); return 1; }
    chmod +x "$D/$1"
    return 0
}

printf '#ioctl notes here {\n#io(fd) reads a byte {\n#naked\nfn isr(): i64 { return 1; }\n' > "$D/tool.cyr"
printf '#naked fn isr(): i64 { return 1; }\n' > "$D/tool_attr.cyr"

if build_tool cyrlint; then
    out=$("$D/cyrlint" "$D/tool.cyr" 2>&1) || true
    if printf '%s' "$out" | grep -q '^0 warnings'; then
        printf '  ok: axis C1 — cyrlint reads `#ioctl notes here {` and `#io(fd) ... {` as comments\n'
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

# C4/C5 — cyrdoc, the THIRD mirror reader. ⚠ This axis did not exist until the
# review round, although this gate's registration in programs/checks/main.cyr and
# the archived filing BOTH claimed it covered "all three mirror readers", and that
# claim was the stated reason for not putting the coverage in cyrlint_cross_line.sh
# where the filing's acceptance asked for it. cyrdoc's observable is different from
# cyrlint's and cyrfmt's: `_doc_attr_len` decides whether a `#` line above a fn is
# DOCUMENTATION (a comment) or an ATTRIBUTE, so an attribute-prefixed comment read
# as an attribute leaves the fn undocumented and `--check` exits 1.
if build_tool cyrdoc; then
    printf '#ioctl notes here {\nfn dd(): i64 { return 1; }\n' > "$D/doc_c.cyr"
    printf '#io(fd) reads a byte\nfn dd(): i64 { return 1; }\n' > "$D/doc_p.cyr"
    printf '# ioctl notes here {\nfn dd(): i64 { return 1; }\n' > "$D/doc_t.cyr"
    printf '#inline\nfn dd(): i64 { return 1; }\n' > "$D/doc_a.cyr"
    rcd=0; "$D/cyrdoc" --check "$D/doc_t.cyr" >/dev/null 2>&1 || rcd=$?
    rcc=0; "$D/cyrdoc" --check "$D/doc_c.cyr" >/dev/null 2>&1 || rcc=$?
    rcp=0; "$D/cyrdoc" --check "$D/doc_p.cyr" >/dev/null 2>&1 || rcp=$?
    if [ "$rcd" -ne 0 ]; then
        printf '  FAIL: axis C4 — the SPACED twin is not documentation to cyrdoc either (rc=%s); the axis would be vacuous\n' "$rcd"
        fail=$((fail+1))
    elif [ "$rcc" -eq 0 ] && [ "$rcp" -eq 0 ]; then
        printf '  ok: axis C4 — cyrdoc reads `#ioctl notes here {` and `#io(fd) ...` as documentation\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis C4 — cyrdoc read an attribute-prefixed comment as an attribute (word form rc=%s, paren form rc=%s)\n' \
            "$rcc" "$rcp"
        fail=$((fail+1))
    fi
    rca=0; "$D/cyrdoc" --check "$D/doc_a.cyr" >/dev/null 2>&1 || rca=$?
    if [ "$rca" -ne 0 ]; then
        printf '  ok: axis C5 — cyrdoc still reads a real `#inline` as an attribute (fn stays undocumented)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis C5 — cyrdoc lost the attribute reading: `#inline` counted as the fn'"'"'s doc comment\n'
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

# ── Group D — THE SAME ROOT CAUSE IN THE PREPROCESSOR (v6.6.6, review round).
#    LEXATTRBOUND fixed the lexer's `#` branch. Two more `#`-name probes in
#    src/frontend/lex_pp.cyr matched a byte PREFIX with no boundary, and there the
#    failure is SILENT rather than a diagnostic: `#host_onlyish note` marked a module
#    host-only (breaking every bare-metal build that included it) and
#    `#derive(Serialize)x note` armed the derive machinery and CHANGED THE EMITTED
#    BINARY. Both are scored against a spaced twin, as group A is.

# D1/D2 — PP_IS_HOST_ONLY. A CYRIUS_KERNEL build is a bare-metal ELF, so these axes
# compare BYTES and exit codes of the COMPILER, never run the output.
mkdir -p "$D/ho"
printf 'include "m.cyr"\nvar A = hf();\nsyscall(60, A);\n' > "$D/ho/e.cyr"
ho_build() {
    printf '%b' "$2" > "$D/ho/m.cyr"
    horc=0
    ( cd "$D/ho" && CYRIUS_KERNEL=1 "$CC" < e.cyr > "$1.bin" 2> "$1.err" ) || horc=$?
}
ho_build hosp '# host_onlyish note\nfn hf(): i64 { return 7; }\n'
if [ "$horc" -ne 0 ]; then
    printf '  FAIL: axis D1 — the spaced twin `# host_onlyish` does not build: %s\n' \
        "$(head -1 "$D/ho/hosp.err" | cut -c1-90)"
    fail=$((fail+1))
else
    ho_build hoat '#host_onlyish note\nfn hf(): i64 { return 7; }\n'
    if [ "$horc" -ne 0 ]; then
        printf '  FAIL: axis D1 — `#host_onlyish note` (a COMMENT) refused the bare-metal build: %s\n' \
            "$(head -1 "$D/ho/hoat.err" | cut -c1-90)"
        fail=$((fail+1))
    elif cmp -s "$D/ho/hoat.bin" "$D/ho/hosp.bin"; then
        printf '  ok: axis D1 — `#host_onlyish note` is a comment (bytes == spaced twin)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis D1 — `#host_onlyish note` built, but not to the spaced twin'"'"'s bytes\n'
        fail=$((fail+1))
    fi
fi
ho_build hoarm '#host_only\nfn hf(): i64 { return 7; }\n'
if [ "$horc" -ne 0 ] && grep -q 'host-only module' "$D/ho/hoarm.err"; then
    printf '  ok: axis D2 — a real `#host_only` module is still refused under CYRIUS_KERNEL\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis D2 — `#host_only` no longer arms (rc=%s): %s\n' \
        "$horc" "$(head -1 "$D/ho/hoarm.err" | cut -c1-70)"
    fail=$((fail+1))
fi

# D3 — ISDERIVE. The comment form must be byte-identical to its spaced twin; on the
# defect it COMPILED TOO, just to different bytes, so rc alone would not have caught it.
printf '# derive(Serialize)x note\nstruct P { a: i64 }\nvar A = 42;\nsyscall(60, A);\n' > "$D/dvsp.cyr"
printf '#derive(Serialize)x note\nstruct P { a: i64 }\nvar A = 42;\nsyscall(60, A);\n' > "$D/dvat.cyr"
compile dvsp
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis D3 — the spaced twin `# derive(Serialize)x` does not compile\n'
    fail=$((fail+1))
else
    compile dvat
    if [ "$rc" -ne 0 ]; then
        printf '  FAIL: axis D3 — `#derive(Serialize)x note` did not compile: %s\n' \
            "$(grep -m1 error "$D/dvat.err" | cut -c1-90)"
        fail=$((fail+1))
    elif cmp -s "$D/dvat.bin" "$D/dvsp.bin"; then
        printf '  ok: axis D3 — `#derive(Serialize)x note` is a comment (binary == spaced twin)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis D3 — `#derive(Serialize)x note` armed the derive (binary != spaced twin)\n'
        fail=$((fail+1))
    fi
fi

# D4/D5 — #derive(accessors), by the generated getters rather than by bytes: the
# comment form must leave `P_a` UNDEFINED, the real form must run.
accbody='struct P { a: i64; b: i64; }\nvar p[2];\nfn main() { P_set_a(&p, 20); P_set_b(&p, 22); syscall(60, P_a(&p) + P_b(&p)); }\n'
printf "#derive(accessors)x note\n$accbody" > "$D/dacc0.cyr"
printf "#derive(accessors)\n$accbody" > "$D/dacc1.cyr"
rc=0; ( cd "$D" && "$CC" < dacc0.cyr > dacc0.bin 2> dacc0.err ) || rc=$?
if [ "$rc" -ne 0 ] && grep -q "undefined function 'P_a'" "$D/dacc0.err"; then
    printf '  ok: axis D4 — `#derive(accessors)x note` does not generate accessors\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis D4 — a comment armed #derive(accessors) (compiler rc=%s)\n' "$rc"
    fail=$((fail+1))
fi
compile dacc1
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis D5 — a real `#derive(accessors)` did not compile: %s\n' \
        "$(grep -m1 error "$D/dacc1.err" | cut -c1-90)"
    fail=$((fail+1))
else
    got=0; ( "$D/dacc1.bin" ) || got=$?
    if [ "$got" = 42 ]; then
        printf '  ok: axis D5 — a real `#derive(accessors)` still arms (exit 42)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis D5 — #derive(accessors) stopped arming: exit=%s, want 42\n' "$got"
        fail=$((fail+1))
    fi
fi
rm -f "$D/dacc1.bin" "$D/dacc0.bin" "$D/dvat.bin" "$D/dvsp.bin"

# D6 — the FOURTH reader of this directive: programs/cyrius_api_surface.cyr copies the
# compiler's derive detection to list synthesized accessors, and copied the missing
# boundary with it. Expected is computed a different way again: the comment form's
# snapshot must equal the snapshot of a file carrying NO derive line at all.
if build_tool cyrius_api_surface; then
    api_snap() {
        rm -rf "$D/api"; mkdir -p "$D/api/src" "$D/api/lib"
        printf "$1" > "$D/api/src/m.cyr"
        ( cd "$D/api" && "$D/cyrius_api_surface" --update --snapshot="$2" ) >/dev/null 2>&1 || true
    }
    apibody='struct P { a: i64; b: i64; }\nfn keep(): i64 { return 1; }\n'
    api_snap "$apibody"                          "$D/none.snap"
    api_snap "#derive(accessors)x note\n$apibody" "$D/cmt.snap"
    api_snap "#derive(accessors)\n$apibody"       "$D/arm.snap"
    nnone=$(grep -c . "$D/none.snap" 2>/dev/null || echo 0)
    narm=$(grep -c . "$D/arm.snap" 2>/dev/null || echo 0)
    if [ "$narm" -le "$nnone" ]; then
        printf '  FAIL: axis D6 — api-surface no longer lists derived accessors (%s vs %s entries)\n' \
            "$narm" "$nnone"
        fail=$((fail+1))
    elif cmp -s "$D/cmt.snap" "$D/none.snap"; then
        printf '  ok: axis D6 — api-surface reads `#derive(accessors)x note` as a comment (%s entries, armed %s)\n' \
            "$nnone" "$narm"
        pass=$((pass+1))
    else
        printf '  FAIL: axis D6 — api-surface listed accessors for a COMMENT: %s\n' \
            "$(comm -13 "$D/none.snap" "$D/cmt.snap" | tr '\n' ' ')"
        fail=$((fail+1))
    fi
fi

# ── Group E — the THREE remaining unbounded probes in the same file (v6.6.6 bite
#    5h). ISELSE already carried a word boundary inline; ISENDIF, ISENDPLAT and
#    ISSRCLINE did not, and all three fail silently: `#endifoo note` — a COMMENT —
#    CLOSED a conditional, so code inside a skipped `#ifdef` was compiled in with
#    no diagnostic, and `#@srclinex 10` shifted every diagnostic in the file by a
#    line. Scored against the spaced twin, the same way group A is.

# Compare $1.cyr against its twin $1_t.cyr: same compiler rc and same first error.
twin_axis() {
    ax=$1; desc=$2
    rcu=0; ( cd "$D" && "$CC" < "$ax.cyr" > "$ax.bin" 2> "$ax.err" ) || rcu=$?
    rct=0; ( cd "$D" && "$CC" < "${ax}_t.cyr" > "${ax}_t.bin" 2> "${ax}_t.err" ) || rct=$?
    gu=$(head -1 "$D/$ax.err" | cut -c1-60); gt=$(head -1 "$D/${ax}_t.err" | cut -c1-60)
    if [ "$rcu" = "$rct" ] && [ "$gu" = "$gt" ]; then
        printf '  ok: axis %s — %s (matches its spaced twin: rc=%s)\n' "$ax" "$desc" "$rcu"
        pass=$((pass+1))
    else
        printf '  FAIL: axis %s — %s: unspaced rc=%s [%s], twin rc=%s [%s]\n' \
            "$ax" "$desc" "$rcu" "$gu" "$rct" "$gt"
        fail=$((fail+1))
    fi
    rm -f "$D/$ax.bin" "$D/${ax}_t.bin"
}

printf '#ifdef NOPE_XYZ\nvar A = 1;\n#endifoo note\nvar A = 42;\n#endif\nsyscall(60, A);\n'  > "$D/E1.cyr"
printf '#ifdef NOPE_XYZ\nvar A = 1;\n# endifoo note\nvar A = 42;\n#endif\nsyscall(60, A);\n' > "$D/E1_t.cyr"
twin_axis E1 '`#endifoo note` does not close a skipped #ifdef'

# E2 — the arm axis: a real #endif must still RESUME the skipped region, or
# everything after it stays swallowed and E1 passes for the wrong reason.
printf '#ifdef NOPE_XYZ\nvar Z = UNDEFINED_THING;\n#endif\nvar A = 7;\nsyscall(60, A);\n' > "$D/E2.cyr"
compile E2
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis E2 — a real `#endif` no longer closes the block: %s\n' \
        "$(grep -m1 error "$D/E2.err" | cut -c1-80)"
    fail=$((fail+1))
else
    got=0; ( "$D/E2.bin" ) || got=$?
    if [ "$got" = 7 ]; then
        printf '  ok: axis E2 — a real `#endif` still closes the block (exit 7)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis E2 — #endif stopped arming: exit=%s, want 7\n' "$got"
        fail=$((fail+1))
    fi
fi
rm -f "$D/E2.bin"

# E3/E4 — #endplat. Written so the answer does not depend on the host arch: one
# #ifplat block is taken and the other skipped whichever way round it runs.
printf '#ifplat aarch64\nvar Q = 1;\n#endplatx note\nvar R = UNDEFINED_THING_X;\n#endplat\nvar B = 7;\nsyscall(60, B);\n'  > "$D/E3.cyr"
printf '#ifplat aarch64\nvar Q = 1;\n# endplatx note\nvar R = UNDEFINED_THING_X;\n#endplat\nvar B = 7;\nsyscall(60, B);\n' > "$D/E3_t.cyr"
twin_axis E3 '`#endplatx note` does not close an #ifplat'

printf '#ifplat x86\nvar A = 5;\n#endplat\n#ifplat aarch64\nvar A = 5;\n#endplat\nvar B = 7;\nsyscall(60, B);\n' > "$D/E4.cyr"
compile E4
if [ "$rc" -ne 0 ]; then
    printf '  FAIL: axis E4 — a real `#endplat` no longer closes the block: %s\n' \
        "$(grep -m1 error "$D/E4.err" | cut -c1-80)"
    fail=$((fail+1))
else
    got=0; ( "$D/E4.bin" ) || got=$?
    if [ "$got" = 7 ]; then
        printf '  ok: axis E4 — a real `#endplat` still closes the block (exit 7)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis E4 — #endplat stopped arming: exit=%s, want 7\n' "$got"
        fail=$((fail+1))
    fi
fi
rm -f "$D/E4.bin"

# E5/E6 — #@srcline. The observable is the LINE NUMBER in a diagnostic, so the
# comment form must report its twin's line and the real directive must not.
printf '#@srclinex 10\nvar BAD = UNDEFINED_X;\n'  > "$D/E5.cyr"
printf '# @srclinex 10\nvar BAD = UNDEFINED_X;\n' > "$D/E5_t.cyr"
twin_axis E5 '`#@srclinex 10` does not shift the diagnostic line'

printf '#@srcline 10\nvar BAD = UNDEFINED_X;\n'  > "$D/E6.cyr"
printf '# @srcline 10\nvar BAD = UNDEFINED_X;\n' > "$D/E6_t.cyr"
( cd "$D" && "$CC" < "E6.cyr"   > /dev/null 2> "E6.err" )   || true
( cd "$D" && "$CC" < "E6_t.cyr" > /dev/null 2> "E6_t.err" ) || true
l6=$(head -1 "$D/E6.err" | sed -n 's/^error:<source>:\([0-9]*\):.*/\1/p')
l6t=$(head -1 "$D/E6_t.err" | sed -n 's/^error:<source>:\([0-9]*\):.*/\1/p')
if [ -n "$l6" ] && [ -n "$l6t" ] && [ "$l6" != "$l6t" ]; then
    printf '  ok: axis E6 — a real `#@srcline` still arms (line %s vs the comment form'"'"'s %s)\n' "$l6" "$l6t"
    pass=$((pass+1))
else
    printf '  FAIL: axis E6 — #@srcline stopped arming: real=[%s] comment=[%s]\n' "$l6" "$l6t"
    fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: lexer-attribute-word-boundary — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: lexer-attribute-word-boundary — %s/%s axes green\n' "$pass" "$pass"
