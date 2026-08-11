#!/bin/sh
# v6.5.18 — `cyrius fmt` must leave string-literal CONTINUATION LINES byte-identical.
#
# WHAT THIS GUARDS. A cyrius string literal may span physical lines two ways: a
# trailing `\` (which KEEPS the newline — it is NOT a C-style splice) and a bare
# raw newline. cyrfmt's line loop re-initialised its `in_string` / `in_char`
# tracking to 0 on EVERY physical line, so the state was thrown away at each
# newline and a continuation line was formatted as ordinary code. The enclosing
# statement's indentation then landed INSIDE THE STRING. fmt is supposed to be
# behaviour-preserving, and this is the one construct where whitespace is not
# free: agnosai's YAML fixture gained four spaces, which in YAML is a nesting
# change, and a passing suite began failing on a file nobody had edited except
# by running the formatter. Filed 2026-08-09 (High).
#
# `fmt --check` agreed with the writer, so a CI cleanliness gate actively pushed
# projects onto the corrupted form — inside a fn body the CORRECT program was
# unrepresentable in a --check-clean file. That is why this is a gate and not a
# lint: the damage is applied once, is idempotent afterwards, and looks settled.
#
# EACH AXIS ISOLATES A DIFFERENT HALF OF THE FIX (mutation-verified — a gate
# built only from the filed repro would pass with three of the four sub-fixes
# reverted, because the filed shape only exercises the indent suppression):
#   1. INDENT suppression      — filed repro; continuation line has no leading
#                                whitespace, so ONLY the emit_spaces() gate can
#                                fail it. Reverting the leading-STRIP gate alone
#                                leaves axis 1 green.
#   2. TRAILING-TRIM gate      — spaces at EOL that are inside the literal. The
#                                opening line starts OUTSIDE a string, so neither
#                                starts_in_str gate protects it. Deletion, not
#                                insertion: an insertion-only fix stays red here.
#   3. LEADING-STRIP gate      — a continuation line whose leading spaces are
#                                string content and which CLOSES the literal, so
#                                the trailing-trim gate is not involved either.
#   4. BRACE LEDGER            — a `}` that is string interior. Before the fix
#                                the closing quote of a continuation line read as
#                                an OPENING quote, so the ledger desynced and
#                                every LATER line in the file was re-indented.
#   5. IDEMPOTENCE             — fmt(fmt(x)) == fmt(x) on a deliberately messy file.
#   6. ANTI-VACUOUS            — fmt must still REFORMAT ordinary mis-indented
#                                code. Without this, `fmt = cat` scores 5/5.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f "$ROOT/programs/cyrfmt.cyr" ] || { echo "SKIP: programs/cyrfmt.cyr missing"; exit 0; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# Build cyrfmt from SOURCE (not build/cyrfmt, which may be stale).
cd "$ROOT"
cat programs/cyrfmt.cyr | "$CC" > "$W/cyrfmt" 2> "$W/build.err" || {
  echo "FAIL: cyrfmt did not compile"; sed -n '1,10p' "$W/build.err"; exit 1; }
chmod +x "$W/cyrfmt"
[ -s "$W/cyrfmt" ] || { echo "FAIL: cyrfmt binary is empty"; exit 1; }

FAILED=0

# ── Axes 1-4: each fixture is ALREADY correctly formatted. The contract is that
# fmt is a no-op on it. `cmp` compares bytes, which is the whole point — a
# diff-based check that ignores whitespace would be blind to this entire bug.
identity_axis() {
  _name=$1
  _f=$2
  "$W/cyrfmt" "$_f" > "$_f.out" 2> "$_f.err" || {
    echo "FAIL [$_name]: cyrfmt exited non-zero"; FAILED=1; return; }
  if cmp -s "$_f" "$_f.out"; then
    echo "  ok   [$_name] byte-identical"
  else
    echo "FAIL [$_name]: fmt CHANGED a string literal's bytes"
    od -c "$_f"     | sed -n '1,12p' | sed 's/^/    want /'
    od -c "$_f.out" | sed -n '1,12p' | sed 's/^/    got  /'
    FAILED=1
  fi
}

# Axis 1 — the FILED repro. Backslash continuation, depth 1, no leading
# whitespace on the continuation line.
cat > "$W/a1.cyr" <<'A1EOF'
fn main(): i64 {
    var s = str_from("abc\
def");
    return 0;
}
A1EOF
identity_axis "axis1 indent-suppression (filed repro)" "$W/a1.cyr"

# Axis 2 — trailing spaces that are INSIDE the literal (raw-newline form). The
# three spaces after `abc` are string content. Deletion vector.
printf 'fn main(): i64 {\n    var s = str_from("abc   \ndef");\n    return 0;\n}\n' > "$W/a2.cyr"
identity_axis "axis2 trailing-trim gate (deletion)" "$W/a2.cyr"

# Axis 3 — leading spaces that are string content, on a line that CLOSES the
# literal. Isolates the leading-strip gate from the trailing-trim gate.
printf 'fn main(): i64 {\n    var s = str_from("abc\n   def");\n    return 0;\n}\n' > "$W/a3.cyr"
identity_axis "axis3 leading-strip gate" "$W/a3.cyr"

# Axis 4 — a brace inside the literal. `}` on the continuation line must not
# move the depth, and the literal's CLOSING quote must not read as an OPENING
# one. This axis is deliberately NOT a byte-identity check: when the ledger
# desyncs, every following line is (wrongly) treated as string interior and
# therefore emitted VERBATIM — so against an already-correct fixture the broken
# formatter reproduces the file perfectly and scores a false PASS. It was
# written that way first and the ledger mutation passed it. The input is
# mis-indented AFTER the literal, so only a formatter that correctly resumes
# code tracking can produce the expected output.
printf 'fn main(): i64 {\n    var s = str_from("a{b\nc}d");\nreturn 0;\n}\n' > "$W/a4.cyr"
printf 'fn main(): i64 {\n    var s = str_from("a{b\nc}d");\n    return 0;\n}\n' > "$W/a4.want"
"$W/cyrfmt" "$W/a4.cyr" > "$W/a4.out" 2> "$W/a4.err" || { echo "FAIL [axis4]: exited non-zero"; FAILED=1; }
if cmp -s "$W/a4.want" "$W/a4.out"; then
  echo "  ok   [axis4 brace ledger across continuation] literal kept, code resumed"
else
  echo "FAIL [axis4 brace ledger]: ledger desynced across the literal"
  diff "$W/a4.want" "$W/a4.out" | sed -n '1,12p' | sed 's/^/    /'
  FAILED=1
fi

# ── Axis 5 — idempotence on a MESSY file (wrong indent + a continuation).
cat > "$W/a5.cyr" <<'A5EOF'
fn main(): i64 {
var s = str_from("abc\
def");
        if (1 == 1) {
return 0;
}
    return 1;
}
A5EOF
"$W/cyrfmt" "$W/a5.cyr"     > "$W/a5.p1" 2> "$W/a5.err" || { echo "FAIL [axis5]: pass 1 exited non-zero"; FAILED=1; }
"$W/cyrfmt" "$W/a5.p1"      > "$W/a5.p2" 2>> "$W/a5.err" || { echo "FAIL [axis5]: pass 2 exited non-zero"; FAILED=1; }
if cmp -s "$W/a5.p1" "$W/a5.p2"; then
  echo "  ok   [axis5 idempotence] fmt(fmt(x)) == fmt(x)"
else
  echo "FAIL [axis5 idempotence]: second pass changed the file"
  diff "$W/a5.p1" "$W/a5.p2" | sed -n '1,12p' | sed 's/^/    /'
  FAILED=1
fi
# ...and the literal must have survived BOTH passes untouched. Idempotence alone
# is satisfied by a formatter that corrupts once and then sits still — which is
# exactly how this bug stayed invisible in review.
if grep -q '^def");$' "$W/a5.p2"; then
  echo "  ok   [axis5 literal] continuation survived reformatting"
else
  echo "FAIL [axis5 literal]: continuation line was altered while reindenting"
  sed -n '1,6p' "$W/a5.p2" | sed 's/^/    /'
  FAILED=1
fi

# ── Axis 6 — ANTI-VACUOUS. fmt must still do its job on ordinary code.
cat > "$W/a6.cyr" <<'A6EOF'
fn main(): i64 {
if (1 == 1) {
return 42;
}
return 0;
}
A6EOF
cat > "$W/a6.want" <<'A6WEOF'
fn main(): i64 {
    if (1 == 1) {
        return 42;
    }
    return 0;
}
A6WEOF
"$W/cyrfmt" "$W/a6.cyr" > "$W/a6.out" 2> "$W/a6.err" || { echo "FAIL [axis6]: exited non-zero"; FAILED=1; }
if cmp -s "$W/a6.want" "$W/a6.out"; then
  echo "  ok   [axis6 anti-vacuous] ordinary code is still reindented"
else
  echo "FAIL [axis6 anti-vacuous]: fmt no longer reformats ordinary code"
  diff "$W/a6.want" "$W/a6.out" | sed -n '1,12p' | sed 's/^/    /'
  FAILED=1
fi

# ── Axis 7 — --check must AGREE with the writer. The writer and the checker
# share format_file(), but the filing's sharpest symptom was --check condemning
# the correct program, so assert it directly: a file fmt leaves alone is clean.
# v6.5.18: --check MUST precede the path. cyrfmt tests argv(1) for the flag, so
# `cyrfmt <file> --check` never engages check mode — it formats to stdout and exits 0
# against ANY formatter, `cat` included. As first written this axis passed in the
# BASELINE tree, i.e. it was vacuous while advertising the filing's sharpest symptom.
# Correct order discriminates: old rc=1, new rc=0.
if "$W/cyrfmt" --check "$W/a1.cyr" > "$W/a1.chk" 2> "$W/a1.chkerr"; then
  echo "  ok   [axis7 --check agrees] correct program reports clean"
else
  echo "FAIL [axis7 --check agrees]: --check calls the CORRECT program dirty"
  sed -n '1,5p' "$W/a1.chk" | sed 's/^/    /'
  FAILED=1
fi

[ "$FAILED" -eq 0 ] || exit 1
echo "PASS: cyrfmt preserves string-literal continuation lines (7 axes)"
