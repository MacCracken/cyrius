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
#   F  a derived struct NAME declared twice with a different LAYOUT -> refused, by the
#      redefinition's own message naming the struct (6.6.11; it was exempt, and built rc 0 with
#      the second definition's accessors running against the first's layout). Four shapes: a
#      different size (two rows), the SAME size with the fields swapped, the same names and
#      offsets with a narrower last field, and the same names and size with a field moved
#   G  controls: the same name declared twice IDENTICALLY (agnosys + sigil vendored side by side
#      in nine repos), or with the same field names at the same offsets and other field TYPES
#      (garjan + prani's DcBlocker: f64 then i64) -> build and run
#
# Mutations: remove the backstop (6.6.7 bite 5's own V2) -> A and B build rc 0, RED. Emit it at
# top level after the struct -> C and D RED (`unexpected struct`). Arm it after a stopped walk
# -> E RED. Skip it for a redefined name (6.6.7-6.6.10) -> F RED. Compare the size only (the
# first 6.6.11 cut) -> the swapped-fields F row RED. Drop the size / name / offset comparison
# -> the narrower-last-field / swapped / moved F row RED. Refuse any second definition -> G RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: derive_layout_backstop: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: derive_layout_backstop: mktemp -d failed"; exit 1; }
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

# --- F: a REDEFINED derived struct name with a different layout is refused (6.6.11) ---
# The parser keeps the FIRST layout, so the second definition's accessors run against it:
# SP_set_backend (offset 8 in the 3-field SP) wrote over the first SP's `alive`, on a larger
# second definition past its sizeof, and with the fields swapped at the same size every setter
# wrote the other field (75 where 57 was meant). 6.6.7-6.6.10 exempted a redefined name for the
# older kavach (two `struct SpawnedProcess`); every consumer now vendors kavach 3.13.1 (one).
RMSG="is defined again with different field names, order or size"
frow() {   # <name> <struct> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "F: $3 BUILT (rc 0)"
    elif ! grep -q "#derive: struct '$2' $RMSG" "$T/$1.err"; then
        bad "F: $3 refused, but not by the redefinition message naming '$2': $(grep '^error' "$T/$1.err" | head -1)"
    elif grep -q "$MSG" "$T/$1.err"; then bad "F: $3: the nested-struct hint was printed for a redefinition"
    else ok "F: $3 is refused, naming '$2'"; fi
}
printf '%s\n#derive(accessors)\nstruct SP { pid; alive; exit_code; cg; lp; }\n#derive(accessors)\nstruct SP { pid; backend; started_at; }\nfn main() { var s = alloc(24); SP_set_backend(s, 7); return SP_backend(s) + sizeof(SP); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f.cyr"
frow f SP "a redefinition at a different size (40 B then 24 B)"
printf '%s\n#derive(accessors)\nstruct A { s; e; p; timestamp; h; ph; }\n#derive(accessors)\nstruct A { timestamp; op; c; i; u; r; rm; m; }\nfn main() { var a = alloc(64); A_set_m(a, 5); return A_m(a); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f2.cyr"
frow f2 A "the premise-S d2 shape (48 B then 64 B)"
printf '%s\n#derive(accessors)\nstruct SW { x; y; }\n#derive(accessors)\nstruct SW { y; x; }\nfn main() { var a: SW; SW_set_x(&a, 5); SW_set_y(&a, 7); return a.x * 10 + a.y; }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f3.cyr"
frow f3 SW "a same-size redefinition with the fields swapped"
printf '%s\n#derive(accessors)\nstruct NW { a; b; }\n#derive(accessors)\nstruct NW { a; b: i32; }\nfn main() { var n: NW; NW_set_b(&n, 3); return NW_b(&n); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f4.cyr"
frow f4 NW "the same names and offsets with a narrower last field (16 B then 12 B)"
printf '%s\n#derive(accessors)\nstruct MV { a: i32; b; }\n#derive(accessors)\nstruct MV { a; b: i32; }\nfn main() { var m: MV; MV_set_b(&m, 3); return MV_b(&m); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/f5.cyr"
frow f5 MV "the same names and size with a field moved (b at 4, then at 8; 12 B both)"

# --- G: controls — the same field names at the same offsets still build ---
printf '%s\n#derive(accessors)\nstruct CE { host; pin; }\n#derive(accessors)\nstruct CE { host; pin; }\nfn main() { var c = alloc(16); CE_set_pin(c, 9); return CE_pin(c) + sizeof(CE); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/g1.cyr"
build g1
if [ "$rc" -ne 0 ]; then bad "G: an IDENTICAL redefinition (agnosys + sigil) no longer builds: $(grep '^error' "$T/g1.err" | head -1)"
else
    chmod +x "$T/g1.bin"; grc=0; "$T/g1.bin" || grc=$?
    if [ "$grc" -eq 25 ]; then ok "G: an identical redefinition builds and runs (25)"
    else bad "G: an identical redefinition ran with $grc, want 25"; fi
fi
printf '%s\n#derive(accessors)\nstruct DB { xp: f64; yp: f64; r: f64; }\n#derive(accessors)\nstruct DB { xp: i64; yp: i64; r: i64; }\nfn main() { var d = alloc(24); DB_set_r(d, 4); return DB_r(d) + sizeof(DB); }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/g2.cyr"
build g2
if [ "$rc" -ne 0 ]; then bad "G: a same-layout redefinition with other field types (garjan + prani) no longer builds: $(grep '^error' "$T/g2.err" | head -1)"
else
    chmod +x "$T/g2.bin"; grc=0; "$T/g2.bin" || grc=$?
    if [ "$grc" -eq 28 ]; then ok "G: a same-layout redefinition with other field types builds and runs (28)"
    else bad "G: a same-layout redefinition with other field types ran with $grc, want 28"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: derive_layout_backstop — $fails axis(es) red"; exit 1; fi
echo "PASS: derive_layout_backstop — a derive/parser layout disagreement fails the build (A-B), agreement does not (C), declarations after a derive still parse (D), a parse error is not buried (E), a derived name redefined with a different layout is refused by name (F), and one with the same names and offsets still builds (G)"
