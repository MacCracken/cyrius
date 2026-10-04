#!/bin/sh
# tests/gates/frontend/lint_reports_unparseable.sh — v6.5.19
#
# `cyrius lint` never reports a clean bill of health on a file that does not parse —
# AND never refuses to lint a file it merely cannot RESOLVE.
#
# THE FILED DEFECT (hisab, the residual half of the dead-fn-body filing). On the
# filing's verbatim source, at 6.5.18:
#     cyrius build src/g.cyr build/g   exit=1   error:<source>:1:20: unexpected ';'
#     cyrius lint  src/g.cyr           exit=0   0 warnings
# `programs/cyrlint.cyr` is a line-based scanner with no parser — "does this file
# parse?" is not a question it can ask, so `0 warnings` was a true statement about its
# nine rules and a false one about the file. v6.5.19 runs a compiler syntax pre-pass in
# `cmd_lint` first (cbt/commands.cyr) and forwards the compiler's own diagnostic.
#
# ⭐ AXIS 3 IS THE ONE THAT MATTERS. The cheap implementation — gate on the compiler's
# EXIT CODE — passes axes 1 and 2 and is WRONG: 38 of the 191 files this repo lints
# exit non-zero standalone, 27 with `undefined variable 'X' (missing include or enum?)`
# through the same `_err_head` and the same exit 1 as a syntax error. That version of
# the fix makes `cyrius lint` refuse 20 % of the stdlib. Axis 3 copies `lib/fs.cyr`
# into a bare directory with no manifest and no lib/, checks with `cyrius check` that
# it genuinely cannot resolve there, and then REQUIRES lint to run anyway. A gate
# without it would bless the broken implementation.
#
# ⭐ AXIS 6 IS THE OTHER ONE THAT MATTERS (added v6.5.19, after this gate shipped
# GREEN over a live P1). Axis 3 proves an UNRESOLVABLE file is still linted, but it
# picks `lib/fs.cyr`, which takes `Str` params and never reads `.field` off one — so
# it sails past the actual hole. Six struct-field sites in `src/frontend/parse_decl.cyr`
# reported RESOLUTION failures through `ERR(S)`, the SYNTAX emitter, so a module doing
# `total = total + e.size;` with `Entry` declared in a SIBLING FILE — the ordinary
# layout for any project whose manifest concatenates modules — came back
# `unexpected ';'` and was condemned. 3 of stiva's 29 src files, i.e. the repo that
# filed this very issue. In-repo exposure is genuinely zero (246/246 lint), which is
# exactly why the first version of this gate could not see it. Axis 6 proves each
# fixture is WELL-FORMED (the same bytes compile once the sibling is concatenated in
# front) before demanding that lint run it.
#
# ANTI-VACUOUS: axis 2 (a clean file still prints `0 warnings`, exit 0) stops the gate
# being satisfiable by condemning everything; axis 5 requires unresolvable-but-
# well-formed shapes to pass through untouched; axis 7 stops axis 6 being satisfiable
# by switching the pre-pass off for anything containing a dot.
#
# MUTATION PROOF (all four run at v6.5.19, RED then GREEN):
#   * delete `if (_lint_syntax_prepass(file) != 0) { return 1; }` from `cmd_lint`
#     -> 13 RED: axes 1, 4 (all six shapes) and 7; axes 2/3/5/6 green.
#   * replace the message-class test with exit-code gating (`if (cr == 0) return 0`)
#     -> 19 RED: axis 3, axis 5 (u1/u3) and ALL FOUR of axis 6; axes 1/4/7 green.
#     Note it takes axis 6 down too — the cross-file shape exits 1 like any other
#     unresolvable file, which is the whole reason exit-code gating is wrong.
#   * ⭐ SEMANTIC mutation, not textual — revert `src/frontend/parse_decl.cyr`'s
#     `if (sid == 0) { ERR_IDENT(...); return 0; }` to the pre-6.5.19
#     `if (sid == 0) { ERR(S); }` and rebuild cycc -> axis 6 RED on x_read/x_write/
#     x_method/x_chain (premise C and the LINTED rows both flip), axes 1-5 green.
#     This is the real defect, reintroduced; a rename or a deleted string proves
#     nothing here.
#   * drop the `unexpected ` row from `_lint_msg_is_syntax` (the tempting "narrow
#     the predicate" shortcut) -> 8 RED across axes 1, 4 and 7, axis 6 green: the
#     filed repro IS `unexpected ';'`, so that shortcut buys axis 6 by gutting the
#     detection the issue asked for. That is why v6.5.19 fixed the compiler instead.
#
# ⛔ 6.6.11 (O4) — THE CLASSIFIER IS INVERTED. Lint used to refuse only when an error's
# message began with an entry of a SYNTAX allow-list, so any refusal the list did not name
# linted `0 warnings`, rc 0 — measured on `#derive(accessors)` over an enum and on a #derive
# over neither a struct nor an enum, both refused by `cyrius build`. Now EVERY compiler
# refusal fails lint, unless each error line is in the named CONTEXT set
# (`_lint_msg_is_context`: `… requires include "…"`, an array sized by another file's enum
# constant, a struct declared in a sibling module). The refusal line now reads "does not parse
# or compile" (a #derive refusal is not a parse failure). Axis 10 is the new refusal
# rows; axis 11 the context controls (ganita- and yukti-shaped); u3 (a duplicate variable,
# which no context can fix) moved from axis 5's lint-anyway set into axis 10.
# MUTATION (6.6.11): `_lint_capture_verdict` back to "refuse only on a syntax-class message"
# -> axis 10 RED (derive rows + u3), axes 1-9, 11 green.
# MUTATION (6.6.11, B10 review): `_lint_syntax_prepass`'s no-error-line branch back to
# "warn and lint anyway" (return 0) -> axis 12 RED (10 rows; its 2 ANTI-VACUOUS rows green), every other axis green.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CYRIUS="$ROOT/build/cyrius"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

for b in cyrius cycc; do
    if [ ! -x "$ROOT/build/$b" ]; then
        echo "FAIL: lint-reports-unparseable — build/$b not built"
        exit 1
    fi
done
# `build/` is gitignored apart from the tracked compilers, and nothing upstream of this
# gate builds cyrlint — so BUILD it rather than skip. A gate that skips itself on a
# fresh clone is the placebo shape this repo keeps paying for.
if [ ! -x "$ROOT/build/cyrlint" ]; then
    "$ROOT/build/cycc" < "$ROOT/programs/cyrlint.cyr" > "$ROOT/build/cyrlint" 2> /dev/null
    chmod +x "$ROOT/build/cyrlint" 2> /dev/null
fi
if [ ! -s "$ROOT/build/cyrlint" ]; then
    echo "FAIL: lint-reports-unparseable — could not build build/cyrlint from programs/cyrlint.cyr"
    exit 1
fi

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: lint_reports_unparseable: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
# Hermetic toolchain: point CYRIUS_HOME at the binaries this tree just built, or the
# gate silently exercises whatever cycc/cyrlint happen to be installed.
mkdir -p "$T/home/bin"
cp "$ROOT/build/cycc" "$T/home/bin/cycc"
cp "$ROOT/build/cyrlint" "$T/home/bin/cyrlint"
chmod +x "$T/home/bin/cycc" "$T/home/bin/cyrlint"
CYRIUS_HOME="$T/home"
export CYRIUS_HOME

# lint $file (relative to $T/w) -> writes $T/o (stdout) and $T/e (stderr), echoes rc
lint() {
    rc=0
    ( cd "$T/w" && timeout 300 "$CYRIUS" lint "$1" > "$T/o" 2> "$T/e" ) || rc=$?
    echo "$rc"
}
mkdir -p "$T/w/src"

# ── AXIS 1 — the filed repro, verbatim.
echo "axis 1 — the filed repro: lint must not bless a file the compiler rejects:"
printf 'fn g_g() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/src/g.cyr"
rc=$(lint src/g.cyr)
check "exits non-zero" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
check "no bare '0 warnings' on stdout" 0 "$(grep -c '^0 warnings' "$T/o" || true)"
check "names the syntax error" 1 "$(grep -c "unexpected ';'" "$T/e" || true)"
check "cites line:column" 1 "$(grep -cE ':[0-9]+:[0-9]+: unexpected' "$T/e" || true)"
check "says lint checks did not run" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ── AXIS 2 — ANTI-VACUOUS: a well-formed file still lints normally.
echo "axis 2 — ANTI-VACUOUS: a clean file still lints and reports 0 warnings, exit 0:"
printf 'fn ok_one() { return 1; }\nfn main() { return ok_one(); }\nvar r = main();\n' > "$T/w/clean.cyr"
rc=$(lint clean.cyr)
check "exit" 0 "$rc"
check "prints '0 warnings'" 1 "$(grep -c '^0 warnings' "$T/o" || true)"

# ── AXIS 3 — ⭐ THE DISCRIMINATOR. A real stdlib module, alone in a directory with no
# manifest and no lib/, cannot RESOLVE — and must still be linted.
echo "axis 3 — ⭐ a file that cannot RESOLVE (no manifest, no lib/) is still linted:"
# A file that PARSES but cannot RESOLVE: names nothing in scope defines. ⚠ This used to be a
# copy of lib/fs.cyr, which did not resolve alone only because it relied on its caller for its
# definers — 6.6.9 bite 7 made every stdlib module include its own, so that copy started to
# resolve and this axis's premise went false. A synthetic file keeps the premise independent of
# how self-sufficient the stdlib is. CHANGELOG [6.6.9]
printf '%s\n' \
  'fn fs_copy_probe(p): i64 {' \
  '    var fd = unresolved_open(p, CYR_NO_SUCH_FLAG, 0);' \
  '    if (fd < 0) { return CYR_NO_SUCH_ERR; }' \
  '    return unresolved_close(fd);' \
  '}' \
  'var r = fs_copy_probe("x");' > "$T/w/fs_copy.cyr"
crc=0
( cd "$T/w" && timeout 300 "$CYRIUS" check fs_copy.cyr > "$T/co" 2> "$T/ce" ) || crc=$?
check "premise: the file really does not resolve here (check exits non-zero)" "yes" \
    "$([ "$crc" != 0 ] && echo yes || echo no)"
# v6.5.23 (R1): the resolution sites became REPORT-AND-CONTINUE, so a compile now
# names EVERY unresolved symbol instead of dying on the first. This axis asserts the
# errors are the RESOLUTION class — not how many there are. Pinning the count to 1 was
# pinning the old stop-at-first-error limitation that R1 deliberately removed.
check "premise: and they are RESOLUTION errors, not syntax ones" "yes" \
    "$([ "$(grep -c 'undefined variable' "$T/ce" || true)" -ge 1 ] && echo yes || echo no)"
rc=$(lint fs_copy.cyr)
check "lint still runs (exit 0)" 0 "$rc"
check "lint still reports a count" 1 "$(grep -c 'warnings' "$T/o" || true)"
check "lint does NOT claim a parse failure" 0 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ── AXIS 4 — a spread of syntax shapes, so detection is not keyed on one message.
echo "axis 4 — every syntax shape is caught, not just the filed one:"
i=0
write_broken() { i=$((i + 1)); printf '%b' "$1" > "$T/w/b$i.cyr"; }
write_broken 'fn a() { var x = ; return 0; }\nfn main() { return 0; }\nvar r = main();\n'
write_broken 'fn a() { var x = 1 return x; }\nfn main() { return 0; }\nvar r = main();\n'
write_broken 'fn a() { var s = "unterminated;\n    return 0; }\nfn main() { return 0; }\nvar r = main();\n'
write_broken 'fn a() { return (1 + 2; }\nfn main() { return 0; }\nvar r = main();\n'
write_broken 'fn a(; ) { return 0; }\nfn main() { return 0; }\nvar r = main();\n'
write_broken 'fn main() { return 0; }\nvar r = main()\n}}} ]]] (((\n'
# 6.6.10 (CVE-52): a stray `@` was dropped by the LEXER, so `return @@@;` compiled at rc 0
# and lint printed `0 warnings` over it. Refused by name now, like `$`.
write_broken 'fn a() { return @@@; }\nfn main() { return a(); }\nvar r = main();\n'
write_broken 'fn a() { var y = 5 @- 3; return y; }\nfn main() { return a(); }\nvar r = main();\n'
n=$i
j=1
while [ "$j" -le "$n" ]; do
    rc=$(lint "b$j.cyr")
    check "broken shape $j rejected" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "broken shape $j: no bare '0 warnings'" 0 "$(grep -c '^0 warnings' "$T/o" || true)"
    j=$((j + 1))
done

# ── AXIS 5 — ANTI-VACUOUS the other way: well-formed but unresolvable shapes must be
# linted normally. These are the messages an exit-code-gated implementation would
# mistake for syntax errors.
echo "axis 5 — ANTI-VACUOUS: unresolvable-but-well-formed files are linted, not refused:"
printf 'fn a() { return SOME_UNDEFINED_CONST; }\nfn main() { return a(); }\nvar r = main();\n' > "$T/w/u1.cyr"
printf 'fn a() { return some_undefined_fn(1); }\nfn main() { return a(); }\nvar r = main();\n' > "$T/w/u2.cyr"
for f in u1.cyr u2.cyr; do
    rc=$(lint "$f")
    check "$f linted, not refused (exit 0)" 0 "$rc"
    check "$f no parse-failure claim" 0 "$(grep -c 'does not parse or compile' "$T/e" || true)"
done

# ── AXIS 6 — ⭐ THE SHAPE THAT ACTUALLY BROKE (v6.5.19, P1). A module that reads
# `.field` off a value whose STRUCT IS DECLARED IN A SIBLING FILE. This is the
# ordinary layout for any project whose manifest concatenates modules — no include
# in the consuming file — and it is what `cyrius lint <one file>` is FOR.
#
# At 6.5.18 the compiler reported all six of these through `ERR(S)`, the syntax
# emitter, so `total = total + e.size;` came back `unexpected ';'` and lint (which
# must classify on the message, never the exit code — see axis 3) condemned the
# file. Measured: 3 of stiva's 29 src files, i.e. the repo that FILED this issue.
# Axis 3 alone does NOT cover it: `lib/fs.cyr` takes `Str` params but never reads
# `.field` off one, so it sails straight past the hole.
#
# The premise rows are the load-bearing part. For each shape we prove the file is
# GENUINELY WELL-FORMED CYRIUS — it compiles the moment the sibling is concatenated
# in front of it — and that standalone it fails for a NAME reason. Only then is
# "lint must still lint it" a fair demand rather than a licence to bless garbage.
echo "axis 6 — ⭐ a module using '.field' on a struct declared in a SIBLING file:"
# The shape is copied from the real filing, not invented: stiva/src/build.cyr:619-621
#     var e: TarEntry = vec_get(entries, i);
#     total = total + e.size;
# with `struct TarEntry` in src/storage.cyr. A TYPED LOCAL whose struct name is not
# resolvable in this translation unit — that is what makes it a resolution failure.
printf 'struct Entry { size; kind; }\nstruct Outer { inner: Entry; tag; }\nfn Entry_size2(self) { return 2; }\n' > "$T/w/sib_types.cyr"
# read / write / method / chained — four of the six sites that shared the defect.
printf 'fn total_of(p) {\n    var total = 0;\n    var e: Entry = p;\n    total = total + e.size;\n    return total;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_read.cyr"
printf 'fn set_of(p) {\n    var e: Entry = p;\n    e.size = 7;\n    return 0;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_write.cyr"
printf 'fn call_of(p) {\n    var e: Entry = p;\n    return e.size2();\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_method.cyr"
printf 'fn deep_of(p) {\n    var o: Outer = p;\n    return o.inner.size;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_chain.cyr"
CYCC="$T/home/bin/cycc"
for f in x_read x_write x_method x_chain; do
    # PREMISE A — standalone it does NOT compile (it genuinely lacks context).
    src="$T/w/$f.cyr"
    src_rc=0
    ( cd "$T/w" && "$CYCC" < "$src" > /dev/null 2> "$T/pe" ) || src_rc=$?
    check "premise: $f alone does not compile" "yes" "$([ "$src_rc" != 0 ] && echo yes || echo no)"
    # PREMISE B — and the reason is a NAME, not the grammar: concatenating the
    # sibling struct declaration in front of it makes the SAME BYTES compile.
    cat "$T/w/sib_types.cyr" "$src" > "$T/w/joined_$f.cyr"
    j_rc=0
    ( cd "$T/w" && "$CYCC" < "$T/w/joined_$f.cyr" > /dev/null 2> "$T/pj" ) || j_rc=$?
    check "premise: $f compiles once the sibling struct is in scope" 0 "$j_rc"
    # PREMISE C — the standalone diagnostic is NOT of the syntax class.
    check "premise: $f standalone error is not 'unexpected …'/'expected …'" 0 \
        "$(grep -cE '^error:[^ ]*: (unexpected|expected) ' "$T/pe" || true)"
    # THE ASSERTION — lint runs it rather than condemning it.
    rc=$(lint "$f.cyr")
    check "$f is LINTED, not refused (exit 0)" 0 "$rc"
    check "$f reports a warning count" 1 "$(grep -c 'warnings' "$T/o" || true)"
    check "$f no parse-failure claim" 0 "$(grep -c 'does not parse or compile' "$T/e" || true)"
done

# ── AXIS 7 — ANTI-VACUOUS for axis 6: a file that mixes a cross-file field access
# with a REAL syntax error is still refused. Without this, axis 6 is satisfiable by
# switching the pre-pass off for anything containing a dot.
echo "axis 7 — ANTI-VACUOUS: a cross-file field access does NOT immunise a broken file:"
printf 'fn total_of(p) {\n    var total = ;\n    var e: Entry = p;\n    total = total + e.size;\n    return total;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_both.cyr"
rc=$(lint x_both.cyr)
check "still refused when a real syntax error is present" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
check "and it names the syntax error" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# The SIXTH site — a genuinely wrong field name in a CHAINED access, with both
# structs in scope. It has no other coverage here, and unlike the four above it is a
# real user error: it must still be REPORTED, still be named, and still not be
# dressed up as a syntax error (which is what would put it back on lint's chopping
# block). `cyrlint` cannot check names, so lint runs it and the compiler catches it.
printf 'fn deep_bad(p) {\n    var o: Outer = p;\n    return o.inner.nope;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_badfield.cyr"
cat "$T/w/sib_types.cyr" "$T/w/x_badfield.cyr" > "$T/w/joined_badfield.cyr"
bf_rc=0
( cd "$T/w" && "$CYCC" < "$T/w/joined_badfield.cyr" > /dev/null 2> "$T/pb" ) || bf_rc=$?
check "a wrong nested field IS an error even with both structs in scope" "yes" \
    "$([ "$bf_rc" != 0 ] && echo yes || echo no)"
check "…and it names the field and the struct" 1 \
    "$(grep -c "unknown field 'nope' on struct 'Entry'" "$T/pb" || true)"
check "…and it is not reported as a syntax error" 0 \
    "$(grep -cE '^error:[^ ]*: (unexpected|expected) ' "$T/pb" || true)"

# ── AXIS 8 — ⭐ THE ORDERING HOLE (v6.5.19). A file that is BOTH unresolvable AND
# syntactically broken, with the RESOLUTION failure FIRST.
#
# This is the axis the gate was missing, and its absence is why the originally filed
# hisab defect was still reachable after the fix that claimed to close it. Axes 3 and 5
# cover unresolvable-but-WELL-FORMED; axis 1 and 4 cover broken-but-RESOLVABLE. Nothing
# covered the intersection — and the intersection was still broken, in exactly the
# filed shape: `0 warnings`, exit 0, on a file that does not parse.
#
# WHY IT FAILED: the pre-pass classifies on the compiler's message, but an undefined
# VARIABLE is a parse-time abort (`--allow-undef` only reaches the fixup stage), and
# the compiler stopped at the FIRST error. So the syntax error on line 2 was never
# reported, no syntax-class message appeared, and lint concluded the file was fine.
# The order matters and nothing tested the order. Fixed by `--syntax-only`
# (src/common/util.cyr), which resolves unknown names to a benign constant so the
# grammar errors survive.
#
# The PREMISE row is the load-bearing part: it proves that a PLAIN compile still stops
# at the resolution error, i.e. the hazard this axis guards is real and not an artefact
# of the fixture. If someone ever makes plain compiles multi-error, that row fails
# loudly rather than the axis quietly becoming vacuous.
echo "axis 8 — ⭐ a file that is BOTH unresolvable AND broken, resolution error FIRST:"
printf 'fn a() { return SOME_UNDEFINED_CONST; }\nfn b() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/both.cyr"
CYCC="$T/home/bin/cycc"
p_rc=0
( cd "$T/w" && "$CYCC" < "$T/w/both.cyr" > /dev/null 2> "$T/be" ) || p_rc=$?
# v6.5.23 (R1): a plain compile no longer STOPS at the resolution error — it reports it
# and keeps parsing, so it now reaches the syntax error too. Both premises are restated
# for the post-R1 compiler. ⭐ The axis's real subject is UNCHANGED and still below: lint
# must REFUSE this file and NAME the syntax error. What changed is only that the raw
# compiler no longer hides the second error behind the first — which is the whole point
# of R1, so asserting the old behaviour here would assert the defect.
check "premise: a plain compile reports the RESOLUTION error" "yes" \
    "$([ "$(grep -c 'undefined variable' "$T/be" || true)" -ge 1 ] && echo yes || echo no)"
check "premise: …and R1 means it now reaches the syntax error too" "yes" \
    "$([ "$(grep -c "unexpected ';'" "$T/be" || true)" -ge 1 ] && echo yes || echo no)"
rc=$(lint both.cyr)
check "lint REFUSES it (exit non-zero)" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
check "no bare '0 warnings' on stdout" 0 "$(grep -c '^0 warnings' "$T/o" || true)"
check "names the syntax error hidden behind the resolution one" 1 \
    "$(grep -c "unexpected ';'" "$T/e" || true)"
check "says lint checks did not run" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ANTI-VACUOUS for axis 8: the SAME file with the syntax error removed is unresolvable
# ONLY, and must still be linted. Without this row, axis 8 is satisfiable by refusing
# every file that fails to resolve — which is precisely the P1 that shipped at 6.5.19
# and had to be reverted (see `_syntax_only`'s comment on why panic-mode recovery was
# rejected: it MANUFACTURED an `unexpected else` on a perfectly well-formed file).
printf 'fn a() { return SOME_UNDEFINED_CONST; }\nfn b() { var y = OTHER_UNDEFINED; return y; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/both_ok.cyr"
rc=$(lint both_ok.cyr)
check "ANTI-VACUOUS: unresolvable-only sibling is still LINTED (exit 0)" 0 "$rc"
check "ANTI-VACUOUS: and makes no parse-failure claim" 0 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# The cross-file struct shape (axis 6) with a syntax error added — the same ordering
# hole one class over, since a `.field` resolution failure also precedes the grammar
# error. Guards against fixing only the `undefined variable` half.
printf 'fn total_of(p) {\n    var e: Entry = p;\n    var t = e.size;\n    var q = ;\n    return t;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/both_struct.cyr"
rc=$(lint both_struct.cyr)
check "cross-file field access + a real syntax error is REFUSED" "yes" \
    "$([ "$rc" != 0 ] && echo yes || echo no)"
check "…and the syntax error is named" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ── AXIS 9 — ⭐ THE RETURN-TYPE SITE (v6.5.19, the second half of the same P1).
#
# Axis 6 covers `.field` on a struct declared in a sibling file. The SAME resolution
# class reaches the parser by a second route — a `: T` RETURN TYPE whose struct is in a
# sibling file — and that site was still routed through `ERR_MSG`, the SYNTAX emitter.
# ERR_MSG sets `_panic`; `_sync_skip` then resyncs mid-declaration and the desynced
# parse MANUFACTURES `expected ';', got '='`, which IS in the syntax class. So lint
# condemned the file on an error the compiler invented.
#
# ⭐ FOUND BY MEASUREMENT, NOT BY READING: a sweep of every .cyr under ~/Repos found 10
# refusals, and agnosai's 3 were refusals of a repo whose `cyrius build` EXITS 0. The
# other two repos (abaco, prajna) genuinely do not build, and axis 9b keeps that
# distinction honest — this must not become "never refuse anything".
#
# Note the message `fn return type must be …` is NOT itself in `_lint_msg_is_syntax`.
# That is exactly why the bug was invisible to a reading of the predicate: the
# condemnation came from the CASCADE, not the diagnostic. Any fix that only widened or
# narrowed the message list would have missed it.
echo "axis 9 — ⭐ a fn RETURN TYPE whose struct is declared in a SIBLING file:"
# ⚠ THE `for` LOOP IN THE BODY IS LOAD-BEARING, NOT DECORATION. The cascade is what
# condemns the file, and it only happens when `_sync_skip` — resyncing to the next `;`
# after the return-type error set `_panic` — lands INSIDE a `for` header, where the
# following `i = i + 1` is then read as a fresh statement. A body of plain statements
# produces the return-type error ALONE, which is not in `_lint_msg_is_syntax` and so was
# never refused: that fixture would make this axis pass against the broken build.
# Copied from the real shape (agnosai/src/definitions/packaging.cyr:261-262).
# ⚠ 6.6.6 — `Str2` HAS ONE FIELD, AND THAT IS LOAD-BEARING. It carried two (16 B), which puts
# the fn in the rax:rdx PAIR return class — while the body `return i;` / `return 0;` hands back
# an integer. That only ever "compiled" because the pair-return path accepted ANY expression and
# silently left rdx unwritten, the defect bite 16c closed; with it closed, the premise row below
# ("compiles once the sibling struct is in scope") went RED, correctly — the FIXTURE was wrong,
# not the axis. At one field the struct is returned in rax alone, so `return <i64>;` is the
# documented "a struct as a plain value is its first word" form and the fn is well-formed. The
# cascade this axis needs is unaffected: it comes from the UNRESOLVABLE RETURN TYPE resyncing
# into the `for` header, not from the struct's width (still 2 syntax-class errors, measured).
printf 'struct Str2 { p; }\n' > "$T/w/sib_ret.cyr"
printf 'fn name_of(members): Str2 {\n    for (var i = 0; i < 4; i = i + 1) {\n        return i;\n    }\n    return 0;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_ret.cyr"
# PREMISE — standalone it does not compile, but it is WELL-FORMED: the same bytes
# compile once the sibling struct is concatenated in front.
r_rc=0
( cd "$T/w" && "$CYCC" < "$T/w/x_ret.cyr" > /dev/null 2> "$T/re" ) || r_rc=$?
check "premise: x_ret alone does not compile" "yes" "$([ "$r_rc" != 0 ] && echo yes || echo no)"
cat "$T/w/sib_ret.cyr" "$T/w/x_ret.cyr" > "$T/w/joined_ret.cyr"
jr_rc=0
( cd "$T/w" && "$CYCC" < "$T/w/joined_ret.cyr" > /dev/null 2> "$T/rj" ) || jr_rc=$?
check "premise: x_ret compiles once the sibling struct is in scope" 0 "$jr_rc"
# ⭐ The load-bearing premise: a PLAIN compile REFUSES this file, by a message lint does not
# excuse. Until 6.6.16 that was the manufactured syntax-class cascade (2 errors: the old
# `fn return type must be ...` latched `_panic` and the resync landed inside the `for`
# header). 6.6.16 (C8) names the type and clears its own latch, so the cascade is GONE —
# the second row pins that — and the refusal is `unknown type 'Str2' as a fn return type`,
# which is not in `_lint_msg_is_context` (cbt/commands.cyr): without lint's --syntax-only
# arm this file would still be condemned, so the axis below is not vacuous.
check "premise: a plain compile refuses the return type BY NAME" 1 \
    "$(grep -c "unknown type 'Str2' as a fn return type" "$T/re" || true)"
check "premise: ...with no syntax-class cascade (6.6.16: the refusal no longer resyncs)" 0 \
    "$(grep -cE "^error:[^ ]*: (unexpected|expected) " "$T/re" || true)"
rc=$(lint x_ret.cyr)
check "x_ret is LINTED, not refused (exit 0)" 0 "$rc"
check "x_ret reports a warning count" 1 "$(grep -c 'warnings' "$T/o" || true)"
check "x_ret no parse-failure claim" 0 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ── AXIS 9b — ANTI-VACUOUS for axis 9: a return-type file WITH a real syntax error is
# still refused, so axis 9 cannot be bought by exempting anything containing `: T`.
printf 'fn name_of(members): Str2 {\n    for (var i = 0; i < 4; i = i + 1) {\n        return i;\n    }\n    var q = ;\n    return 0;\n}\nfn main() { return 0; }\nvar r = main();\n' > "$T/w/x_ret_bad.cyr"
rc=$(lint x_ret_bad.cyr)
check "ANTI-VACUOUS: sibling return type + a REAL syntax error is refused" "yes" \
    "$([ "$rc" != 0 ] && echo yes || echo no)"
check "ANTI-VACUOUS: …and the syntax error is named" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"

# ── AXIS 10 (6.6.11, O4) — ⭐ EVERY REFUSAL, not only a syntax-shaped one. These three are
# refused by `cyrius build` and linted `0 warnings`, rc 0 at 6.6.10: two #derive-stage
# refusals with no `<loc>: ` part, and a duplicate variable (no context can make it compile).
echo "axis 10 — ⭐ a file the compiler refuses for a NON-syntax reason is refused, by name:"
printf '#derive(accessors)\nenum Color { RED = 0; GREEN = 1; }\nvar x = 42;\n' > "$T/w/r_acc_enum.cyr"
printf '#derive(accessors)\nfn not_a_type(): i64 { return 1; }\nvar x = 42;\n' > "$T/w/r_derive_neither.cyr"
printf 'fn a() { var x = 1; var x = 2; return x; }\nfn main() { return a(); }\nvar r = main();\n' > "$T/w/u3.cyr"
for f in r_acc_enum r_derive_neither u3; do
    b_rc=0
    ( cd "$T/w" && timeout 300 "$CYRIUS" build "$f.cyr" "$T/w/$f.bin" > /dev/null 2>&1 ) || b_rc=$?
    check "premise: cyrius build refuses $f" "yes" "$([ "$b_rc" != 0 ] && echo yes || echo no)"
    rc=$(lint "$f.cyr")
    check "$f refused by lint (exit non-zero)" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "$f: no bare '0 warnings'" 0 "$(grep -c '^0 warnings' "$T/o" || true)"
    check "$f: says lint checks did not run" 1 "$(grep -c 'does not parse or compile' "$T/e" || true)"
done
check "the accessors-on-enum diagnostic is forwarded" 1 \
    "$(lint r_acc_enum.cyr > /dev/null; grep -c 'applies to a struct; Color is an enum' "$T/e" || true)"

# ── AXIS 11 (6.6.11) — ANTI-VACUOUS for axis 10: the named CONTEXT errors still lint. Each is
# refused standalone and compiles once its context is in front (premise), and lint runs it.
# The shapes of the two in-repo files a standalone lint refuses under lint's own flags:
# lib/ganita.cyr (f64_sin without lib/math.cyr) and lib/yukti.cyr (an array sized by an enum
# constant another file declares).
echo "axis 11 — ANTI-VACUOUS: context-dependent refusals (ganita/yukti shapes) are still linted:"
printf 'fn gsin(x): i64 { return f64_sin(x); }\nvar r = gsin(0);\n' > "$T/w/c_sin.cyr"
printf 'include "lib/math.cyr"\n' > "$T/w/c_sin_ctx.cyr"
printf 'fn ybuf(): i64 {\n    var buf[YK_SZ];\n    return 0;\n}\nvar r = ybuf();\n' > "$T/w/c_enum.cyr"
printf 'enum YkSz { YK_SZ = 16; }\n' > "$T/w/c_enum_ctx.cyr"
mkdir -p "$T/w/lib" && cp "$ROOT/lib/math.cyr" "$T/w/lib/math.cyr"
for f in c_sin c_enum; do
    s_rc=0
    ( cd "$T/w" && "$CYCC" --allow-undef --syntax-only < "$f.cyr" > /dev/null 2> "$T/ce" ) || s_rc=$?
    check "premise: $f alone is refused under lint's flags" "yes" "$([ "$s_rc" != 0 ] && echo yes || echo no)"
    cat "$T/w/${f}_ctx.cyr" "$T/w/$f.cyr" > "$T/w/joined_$f.cyr"
    j_rc=0
    ( cd "$T/w" && "$CYCC" --allow-undef --syntax-only < "joined_$f.cyr" > /dev/null 2> "$T/cj" ) || j_rc=$?
    check "premise: $f compiles with its context in front" 0 "$j_rc"
    rc=$(lint "$f.cyr")
    check "$f is LINTED, not refused (exit 0)" 0 "$rc"
    check "$f reports a warning count" 1 "$(grep -c 'warnings' "$T/o" || true)"
done
# …but a context error does not immunise a real refusal in the same file.
printf 'fn gsin(x): i64 { return f64_sin(x); }\nfn a() { var x = 1; var x = 2; return x; }\nvar r = gsin(0);\n' > "$T/w/c_mixed.cyr"
rc=$(lint c_mixed.cyr)
check "a context error beside a real refusal is still refused" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"

# ── AXIS 12 (6.6.11, B10 review) — a compiler that FAILS after writing something that is not an
# `error:` line (a crash after a warning; an abort in its own words) is a refusal, not "could not
# tell, linting anyway" — which printed a warning, then `0 warnings`, rc 0, the fail-open shape
# axis 10 closed for error lines. Stub compilers in a private home that also holds the CLI: the
# CLI resolves the compiler beside ITSELF first, so `$ROOT/build/cyrius` would run build/cycc.
# The empty-capture path (a failure that writes nothing) is deliberately not this axis.
echo "axis 12 — a compiler that fails with no error line (crash, own-worded abort) is a refusal:"
mkdir -p "$T/sh/bin"
cp "$CYRIUS" "$T/sh/bin/cyrius" && cp "$ROOT/build/cyrlint" "$T/sh/bin/cyrlint"
printf '#!/bin/sh\necho "warning: something" >&2\nkill -SEGV $$\n' > "$T/sh/segv"
printf '#!/bin/sh\necho "cycc: internal table full" >&2\nexit 3\n' > "$T/sh/ex3"
printf 'var x = 1;\n' > "$T/w/stubbed.cyr"
for stub in segv ex3; do
    cp "$T/sh/$stub" "$T/sh/bin/cycc" && chmod +x "$T/sh/bin/cycc" "$T/sh/bin/cyrius" "$T/sh/bin/cyrlint"
    rc=0
    ( cd "$T/w" && CYRIUS_HOME="$T/sh" timeout 300 "$T/sh/bin/cyrius" lint stubbed.cyr > "$T/o" 2> "$T/e" ) || rc=$?
    check "$stub: refused (exit non-zero)" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "$stub: no bare '0 warnings'" 0 "$(grep -c '^0 warnings' "$T/o" || true)"
    check "$stub: says lint checks were NOT run" 1 "$(grep -c 'without an error line, so lint checks were NOT run' "$T/e" || true)"
    check "$stub: forwards what the compiler wrote" 1 "$(grep -cE '^(warning: something|cycc: internal table full)$' "$T/e" || true)"
done
check "segv: says the compiler did not exit normally" 1 \
    "$(cp "$T/sh/segv" "$T/sh/bin/cycc"; ( cd "$T/w" && CYRIUS_HOME="$T/sh" timeout 300 "$T/sh/bin/cyrius" lint stubbed.cyr > /dev/null 2> "$T/e" ); grep -c 'did not exit normally' "$T/e" || true)"
check "ex3: quotes the compiler's exit status" 1 \
    "$(cp "$T/sh/ex3" "$T/sh/bin/cycc"; ( cd "$T/w" && CYRIUS_HOME="$T/sh" timeout 300 "$T/sh/bin/cyrius" lint stubbed.cyr > /dev/null 2> "$T/e" ); grep -c 'the compiler exited 3' "$T/e" || true)"
# ANTI-VACUOUS: the same private home with the REAL compiler lints the same file clean.
cp "$ROOT/build/cycc" "$T/sh/bin/cycc"
rc=0
( cd "$T/w" && CYRIUS_HOME="$T/sh" timeout 300 "$T/sh/bin/cyrius" lint stubbed.cyr > "$T/o" 2> "$T/e" ) || rc=$?
check "ANTI-VACUOUS: the real compiler in the same home lints it (exit 0)" 0 "$rc"
check "ANTI-VACUOUS: …and reports 0 warnings" 1 "$(grep -c '^0 warnings' "$T/o" || true)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: lint-reports-unparseable — lint tells the truth about parsing AND still lints"
    exit 0
fi
echo "FAIL: lint-reports-unparseable — $fails assertion(s) failed"
exit 1
