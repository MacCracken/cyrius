#!/bin/sh
# Gate: `private` scopes a fn at symbol INSERTION, so a private helper cannot be replaced
# by another file's same-named function (v6.5.38).
#
# THE DEFECT (owl 1.4.7, filed 2026-08-22 §1/§2). The fn table held exactly ONE entry per
# NAME. A second definition reused that entry and overwrote its body — `duplicate fn ...
# last definition wins` — so a private helper was silently replaced by any same-named fn in
# any other file, INCLUDING for its own file's internal calls. Declaring `private` on BOTH
# sides did not help, because visibility was enforced only at the REFERENCE site on top of
# an unchanged global symbol table. Measured at 6.5.37:
#
#     a.cyr:  private  fn _helper(s)   { return 1; }
#             public   fn a_entry(s)   { return _helper(s); }
#     b.cyr:  private  fn _helper(ctx) { return 0; }
#             public   fn b_entry(ctx) { return _helper(ctx); }
#     main:   a_entry(0) * 10 + b_entry(0)
#
#     exit 0    — a_entry was rebound to b.cyr's _helper. Correct is 10.
#
# v6.5.37 closed only the arity-DIFFERING case (as a hard error); the same-arity case above
# is the half it deliberately left open, and its gate says so. This gate closes that half.
#
# ⭐ WHY SAME-ARITY IS THE DANGEROUS ONE. The differing-arity case at least had a shape a
# check could see. The instance that prompted the filing does not: `vyakarana` and `sankoch`
# each define a private-by-convention `_stream_grow`, and they disagree about buffer offsets
# AND RETURN POLARITY (`0` means success in one, failure in the other). A wrong binding
# there does not fault — it reports every successful buffer grow as a FAILURE, inside a
# tokenizer, on file content. Neither library is doing anything wrong; they collide only
# because a consumer links both.
#
# ⚠ MUST BE A MULTI-FILE TEST, and that is not a style preference. The fix keys on the
# ORIGIN FILE of each definition, so a concatenated single-file probe cannot exercise it at
# all: both definitions get the same file id, which is the same-file redefinition case that
# deliberately still warns (axis 6). The v6.5.37 gate next door concatenates, which is
# exactly why it could not have caught this.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: private_scoped_at_insertion: build/cycc missing"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: private_scoped_at_insertion: $1"; exit 1; }

# Compiled against build/cycc DIRECTLY, never through the `cyrius` wrapper: in a scratch
# directory the wrapper resolves the INSTALLED compiler, so the gate would silently test the
# last released one. That mistake was made four separate times during v6.5.37.
# `include` resolves relative to the CWD, so every probe runs from inside $WORK.
build_run() {   # build_run <main-file> -> echoes "<compile_rc>:<run_exit>"; stderr in $WORK/err
    set +e
    ( cd "$WORK" && "$CC" < "$1" > out.bin 2> err )
    crc=$?
    if [ "$crc" -ne 0 ]; then set -e; printf '%s' "$crc:-"; return; fi
    chmod +x "$WORK/out.bin"
    ( cd "$WORK" && ./out.bin ); rrc=$?
    set -e
    printf '%s' "$crc:$rrc"
}

cat > "$WORK/main.cyr" <<'EOF'
include "a.cyr"
include "b.cyr"
fn main() { syscall(60, a_entry(0) * 10 + b_entry(0)); return 0; }
EOF

# ── axis 1: §2 — `private` on BOTH sides, SAME arity, different files ───────────────
# Each file's call must bind to its OWN helper. This is the exact filed repro.
cat > "$WORK/a.cyr" <<'EOF'
private
fn _helper(s) { return 1; }
public fn a_entry(s) { return _helper(s); }
EOF
cat > "$WORK/b.cyr" <<'EOF'
private
fn _helper(ctx) { return 0; }
public fn b_entry(ctx) { return _helper(ctx); }
EOF
R=$(build_run main.cyr)
[ "$R" = "0:10" ] || fail "axis 1 (§2, private both sides): expected compile 0 / exit 10, got $R — a_entry did not bind to its own file's _helper. stderr: $(head -2 "$WORK/err")"
# A correctly SPLIT pair is not a duplicate at all, so the misleading warning must be gone.
grep -q "duplicate fn" "$WORK/err" && fail "axis 1: two properly-scoped private fns still reported as a 'duplicate fn' — they are distinct symbols now, and the warning tells the consumer to go rename something that is already correct"

# ── axis 2: §1 — `private` on ONE side only ────────────────────────────────────────
# The filing's first case: b.cyr does not opt in at all, and must not capture a.cyr's
# private helper. b_entry keeps its own (0), a_entry keeps its private one (1).
cat > "$WORK/b.cyr" <<'EOF'
fn _helper(ctx) { return 0; }
fn b_entry(ctx) { return _helper(ctx); }
EOF
R=$(build_run main.cyr)
[ "$R" = "0:10" ] || fail "axis 2 (§1, private one side): expected compile 0 / exit 10, got $R"

# ── axis 3: a PUBLIC sibling stays reachable from everywhere ────────────────────────
# Splitting a name must not hide an ordinary API. a.cyr keeps its private helper; b.cyr's
# same-named PUBLIC one must serve both b.cyr and an unrelated third file.
cat > "$WORK/b.cyr" <<'EOF'
fn _helper(ctx) { return 7; }
fn b_entry(ctx) { return _helper(ctx); }
EOF
cat > "$WORK/c.cyr" <<'EOF'
fn c_entry() { return _helper(0); }
EOF
cat > "$WORK/m3.cyr" <<'EOF'
include "a.cyr"
include "b.cyr"
include "c.cyr"
fn main() { syscall(60, a_entry(0) * 100 + b_entry(0) * 10 + c_entry()); return 0; }
EOF
R=$(build_run m3.cyr)
[ "$R" = "0:177" ] || fail "axis 3 (public sibling reachable): expected compile 0 / exit 177 (a=1 private, b=7 public, c=7 public), got $R"

# ── axis 4: the boundary STILL HOLDS — no private capture from outside ──────────────
# ⛔ The anti-regression that matters most. A fix that resolved every name to "whatever is
# nearest" would pass axes 1-3 and quietly DELETE the feature. Referencing another file's
# private fn, with no public sibling to fall back to, must remain a hard error.
cat > "$WORK/m4.cyr" <<'EOF'
include "a.cyr"
include "c.cyr"
fn main() { syscall(60, c_entry()); return 0; }
EOF
R=$(build_run m4.cyr)
case "$R" in 0:*) fail "axis 4: a file reached INTO another file's private fn and compiled — the visibility boundary is gone";; esac
grep -q "is private to its file" "$WORK/err" || fail "axis 4: refused, but not with the privacy diagnostic: $(head -2 "$WORK/err")"

# ── axis 5: ANTI-VACUOUS — non-private duplicates still warn, unchanged ─────────────
# Same-arity shadowing between two NON-private files is load-bearing across the ecosystem
# (`_sk_emit_err` collides between lib/vani.cyr and lib/mabda.cyr in the corpus today).
# The split is keyed on `private`, so nothing here may change.
cat > "$WORK/a.cyr" <<'EOF'
fn _helper(s) { return 1; }
fn a_entry(s) { return _helper(s); }
EOF
cat > "$WORK/b.cyr" <<'EOF'
fn _helper(ctx) { return 0; }
fn b_entry(ctx) { return _helper(ctx); }
EOF
R=$(build_run main.cyr)
case "$R" in 0:*) : ;; *) fail "axis 5: two non-private duplicates no longer compile ($R) — the split escalated beyond `private`";; esac
grep -q "duplicate fn" "$WORK/err" || fail "axis 5: two non-private duplicates produced NO 'duplicate fn' warning — the split is firing without `private`, which silently changes existing programs"

# ── axis 6: a SAME-FILE redefinition is still a duplicate ───────────────────────────
# Two definitions in one private file are a genuine redefinition of one symbol, not a
# collision between two files. Splitting there would create an unreachable second symbol.
cat > "$WORK/a.cyr" <<'EOF'
private
fn _helper(s) { return 1; }
fn _helper(s) { return 2; }
public fn a_entry(s) { return _helper(s); }
EOF
cat > "$WORK/b.cyr" <<'EOF'
fn b_entry(ctx) { return 0; }
EOF
R=$(build_run main.cyr)
grep -q "duplicate fn" "$WORK/err" || fail "axis 6: a same-FILE redefinition inside a private file stopped warning — it was split into a second symbol nothing can reach"

# ── axis 7: arity mismatch between non-private duplicates still ERRORS (v6.5.37) ────
cat > "$WORK/a.cyr" <<'EOF'
fn _helper(s) { return 1; }
fn a_entry(s) { return _helper(s); }
EOF
cat > "$WORK/b.cyr" <<'EOF'
fn _helper(a, b, c) { return 0; }
fn b_entry(ctx) { return _helper(1, 2, 3); }
EOF
R=$(build_run main.cyr)
case "$R" in 0:*) fail "axis 7: an arity-differing duplicate compiled again — v6.5.37's check was lost";; esac
grep -q "disagrees about arity" "$WORK/err" || fail "axis 7: refused, but not with the arity diagnostic"

echo "PASS: private_scoped_at_insertion (private helpers bind per-file, public siblings stay reachable, the boundary still errors, non-private duplicates unchanged)"
