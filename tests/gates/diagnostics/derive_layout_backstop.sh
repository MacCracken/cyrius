#!/bin/sh
# derive_layout_backstop.sh — 6.6.7 bite 5: a `#derive` whose field table disagrees with the
# parser's struct layout FAILS THE BUILD instead of generating code against the wrong offsets.
#
# ⛔ WHY. `#derive` computes field offsets itself, from its own read of the body, and the parser
# computes the struct's real layout; every accessor and codec trusts the derive's numbers. For
# years they disagreed SILENTLY on ordinary shapes (a comment in the body, `x : i8`), and the
# accessors stored past the struct. The body walk is fixed (PP_DERIVE_FIELDS); this backstop is
# what makes any REMAINING disagreement loud. The one known remaining case is a field typed with
# a struct that is not itself `#derive`d: the derive cannot see its size and uses 8, the parser
# uses the real size, and `Outer_y` read the wrong word with rc 0 (measured: 55 where 77 was
# stored, sizeof 24 against the derive's 16).
#
# ⚠ WHERE THE CHECK LIVES IS PART OF THE CONTRACT. It is an `#assert sizeof(<Name>) == <size>`
# inside the FIRST generated fn body, never after the struct: a top-level `#assert` is a
# statement, and the first top-level statement ends the declaration phase, so every struct or
# enum declared after a derived struct would be rejected (`unexpected struct`). Axis D pins that.
#
#   A  nested non-derived 16-byte struct under accessors  -> refused, message names the cause,
#      and the error points at the derived struct's line
#   B  the same under Serialize                           -> refused by the backstop FIRST
#   C  control: the nested struct IS derived               -> builds, accessor reads offset 16
#   D  a struct AND an enum declared after a derived struct -> build and run (placement)
#   E  a body the parser rejects                           -> the parser's located error, and
#      NO backstop message stacked on top of it (the walk stopped, so it is not armed)
#   F  a derived struct NAME declared twice                 -> builds and runs as before (the
#      parser keeps the first layout; live in five consumers' vendored kavach)
#
# Mutations: remove the backstop (6.6.7 bite 5's own V2) -> A and B build rc 0, RED. Emit it at
# top level after the struct -> C and D RED (`unexpected struct`). Arm it after a stopped walk
# -> E RED. Arm it for a redefined name -> F RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: derive_layout_backstop: no compiler at $CC"; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/dlb.XXXXXX") || { echo "FAIL: derive_layout_backstop: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
MSG='field offsets disagree with the struct layout'
HDR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/result.cyr"
include "lib/io.cyr"
include "lib/bayan.cyr"'
build() {   # <name> -> rc in $rc, stderr in $T/<name>.err
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
}

# --- A: accessors, nested non-derived struct ---
printf '%s\nstruct Inner { a; b; }\n#derive(accessors)\nstruct Outer {\n    x: Inner;\n    y;\n}\nfn main() { return 0; }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/a.cyr"
build a
want_line=$(grep -n '^}' "$T/a.cyr" | head -1 | cut -d: -f1)
if [ "$rc" -eq 0 ]; then bad "A: nested non-derived struct under accessors BUILT (rc 0) — the layout disagreement is silent"
elif ! grep -q "$MSG" "$T/a.err"; then bad "A: refused, but not by the backstop: $(grep -v '^ ' "$T/a.err" | head -1)"
elif ! grep -q "^error:<source>:$want_line:" "$T/a.err"; then bad "A: backstop fired but not at the struct's line $want_line: $(grep -v '^ ' "$T/a.err" | head -1)"
else ok "A: accessors over a non-derived nested struct are refused at line $want_line"; fi

# --- B: Serialize, same shape ---
printf '%s\nstruct Inner { a; b; }\n#derive(Serialize)\nstruct Outer { x: Inner; y; }\nfn main() { return 0; }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/b.cyr"
build b
first=$(grep -E '^(error|warning)' "$T/b.err" | grep -v 'unreachable' | head -1)
if [ "$rc" -eq 0 ]; then bad "B: nested non-derived struct under Serialize BUILT (rc 0)"
elif ! printf '%s' "$first" | grep -q "$MSG"; then bad "B: the first diagnostic is not the backstop: $first"
else ok "B: Serialize over a non-derived nested struct is refused by the backstop first"; fi

# --- C: control — the nested struct is derived, so the sizes agree ---
printf '%s\n#derive(accessors)\nstruct Inner { a; b; }\n#derive(accessors)\nstruct Outer { x: Inner; y; }\nfn main() { var o = alloc(sizeof(Outer)); store64(o + 16, 77); store64(o + 8, 55); return Outer_y(o); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/c.cyr"
build c
if [ "$rc" -ne 0 ]; then bad "C: a derived nested struct was refused — the backstop fires on agreement: $(grep -v '^ ' "$T/c.err" | head -1)"
else
    chmod +x "$T/c.bin"; crc=0; "$T/c.bin" || crc=$?
    if [ "$crc" -eq 77 ]; then ok "C: derived nested struct builds; Outer_y reads offset 16 (77)"
    else bad "C: Outer_y returned $crc, want 77"; fi
fi

# --- D: declarations after a derived struct still parse (the check is not top-level) ---
printf '%s\n#derive(accessors)\nstruct P { a: i8; b: i64; }\nstruct Q { c; d; }\nenum E { E_A = 3; E_B = 4; }\n#derive(Serialize)\nstruct R { e: i32; }\nfn main() { var p = alloc(sizeof(P)); P_set_b(p, 30); return P_b(p) + sizeof(Q) + E_B + sizeof(R); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/d.cyr"
build d
if [ "$rc" -ne 0 ]; then bad "D: a struct/enum after a derived struct was rejected — the check ended the declaration phase: $(grep -v '^ ' "$T/d.err" | head -1)"
else
    chmod +x "$T/d.bin"; drc=0; "$T/d.bin" || drc=$?
    if [ "$drc" -eq 54 ]; then ok "D: struct + enum + derive after a derived struct build and run (54)"
    else bad "D: ran with $drc, want 54 (30 + 16 + 4 + 4)"; fi
fi

# --- E: a malformed body is the parser's error, alone ---
printf '#derive(accessors)\nstruct P { a = 3; b; }\nvar r = 0;\n' > "$T/e.cyr"
build e
if [ "$rc" -eq 0 ]; then bad "E: a malformed body built (rc 0)"
elif ! grep -q '^error:<source>:2:' "$T/e.err"; then bad "E: the parser's located error is missing: $(grep -v '^ ' "$T/e.err" | head -1)"
elif grep -q "$MSG" "$T/e.err"; then bad "E: the backstop fired on top of the parse error — it must not be armed after a stopped walk"
else ok "E: a malformed body reports the parser's error at line 2, and only that"; fi

# --- F: a REDEFINED derived struct name still builds, as it did before the backstop ---
# The parser keeps the first layout, so judging the second declaration against sizeof() would
# refuse a build that works today — the older kavach copies vendored by mehman / stiva /
# aethersafha / agnosai / agnostic carry exactly this (two `struct SpawnedProcess`).
printf '%s\n#derive(accessors)\nstruct SP { pid; alive; exit_code; cg; lp; }\n#derive(accessors)\nstruct SP { pid; backend; started_at; }\nfn main() { var s = alloc(24); SP_set_backend(s, 7); return SP_backend(s) + sizeof(SP); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f.cyr"
build f
if [ "$rc" -ne 0 ]; then bad "F: a redefined derived struct name no longer builds: $(grep -v '^ ' "$T/f.err" | grep -v warning | head -1)"
else
    chmod +x "$T/f.bin"; frc=0; "$T/f.bin" || frc=$?
    if [ "$frc" -eq 47 ]; then ok "F: a redefined derived struct name builds and runs as before (47)"
    else bad "F: ran with $frc, want 47 (7 + the FIRST layout's 40)"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: derive_layout_backstop — $fails axis(es) red"; exit 1; fi
echo "PASS: derive_layout_backstop — a derive/parser layout disagreement fails the build (A-B), agreement does not (C), declarations after a derive still parse (D), a parse error is not buried (E), and a redefined name builds as before (F)"
