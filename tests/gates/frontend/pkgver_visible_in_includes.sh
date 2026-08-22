#!/bin/sh
# Gate: `CYRIUS_PKG_VERSION` must resolve from an INCLUDED file, not only the entry file.
#
# THE BUG (filed by agnostic 2026-08-20 against 6.5.32, fixed v6.5.34). cbt writes
# `#@pkgver <version>` at byte 0 and cycc replaces it with a real declaration. v6.5.21 made
# that declaration CONDITIONAL — emit nothing unless the source names the constant — for a
# good reason kept below. But the scan ran inside PP_EMIT_PKGVER, whose buffer at that
# moment is the ENTRY FILE's raw text, because includes have not been expanded yet. So the
# constant resolved when the entry file named it and failed when only an `include`d file
# did, which is the exact reverse of what a byte-0 marker suggests:
#     error:src/routes/health.cyr:120:73: undefined variable 'CYRIUS_PKG_VERSION'
#
# ⚠ THE v6.5.33 ATTEMPT AT THIS RESTED ON A FALSE PREMISE and was reverted. It recorded the
# version at the marker and APPENDED the declaration after include expansion; the issue file
# records that "globals declared below their use ARE visible (verified separately)". They
# are NOT — `fn f() { return XYZ; } ... var XYZ = 7;` fails with `undefined variable 'XYZ'`
# on 6.5.33. Any future rework that wants to move the declaration must re-check that claim
# first; it is the reason two attempts went down a path that could not work.
#
# THE FIX. Emit the declaration at the top OPTIMISTICALLY, remember its span, and at the
# tail of PP_PASS — where the includes ARE expanded — scan the finished unit. If nothing
# names the constant, blank the declaration to SPACES: identical byte count, so no line and
# no column moves, and whitespace emits no code.
#
# ⚠ The conditional is not optional (axis 3). Declaring unconditionally puts an unused
# global plus its string data into every binary built through `cyrius build`, changing the
# bytes of programs that never asked for the feature. `auto_deps_verb_gate.sh` axis 5
# measures exactly that. ⚠ And the tail scan MUST skip the declaration's own bytes — it
# contains the prefix being searched for, so a whole-buffer scan matches itself, keeps the
# global on every build, and silently restores the unconditional behaviour while still
# looking like it has a test.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

mkdir -p "$D/proj/src/routes"
cat > "$D/proj/src/routes/health.cyr" <<'EOF'
fn health_version(): i64 { return CYRIUS_PKG_VERSION; }
EOF
cat > "$D/proj/body.cyr" <<'EOF'
include "src/routes/health.cyr"
fn main(): i64 { syscall(1, 1, health_version(), 5); return 0; }
var _r = main();
syscall(60, _r);
EOF
printf '#@pkgver 0.1.0\n' > "$D/proj/included.cyr"
cat "$D/proj/body.cyr" >> "$D/proj/included.cyr"

# ── AXIS 1: the filed repro — referenced ONLY from an included file.
# Mutation: move the reference scan back inside PP_EMIT_PKGVER (i.e. scan the marker's own
# buffer instead of the expanded unit) → this axis goes red, axis 2 stays green.
echo "axis 1 — CYRIUS_PKG_VERSION referenced only from an included file:"
( cd "$D/proj" && "$CC" < included.cyr > out.bin 2> err.txt ); rc=$?
check "compiles" 0 "$rc"
if [ "$rc" = "0" ]; then
    chmod +x "$D/proj/out.bin"
    check "prints the version" "0.1.0" "$("$D/proj/out.bin" 2>/dev/null)"
else
    echo "    compiler said: $(head -c 120 "$D/proj/err.txt")"
fi

# ── AXIS 2: the entry-file case, which worked before and must keep working.
printf '#@pkgver 0.1.0\nfn main(): i64 { syscall(1, 1, CYRIUS_PKG_VERSION, 5); return 0; }\nvar _r = main();\nsyscall(60, _r);\n' > "$D/entry.cyr"
echo "axis 2 — referenced from the entry file (regression guard):"
"$CC" < "$D/entry.cyr" > "$D/entry.bin" 2>/dev/null; check "compiles" 0 "$?"
chmod +x "$D/entry.bin" 2>/dev/null
check "prints the version" "0.1.0" "$("$D/entry.bin" 2>/dev/null)"

# ── AXIS 3: byte-neutrality. A marker on a source that never names the constant must
# produce a binary identical to the same source with no marker at all.
# Mutation: drop the blanking branch (always keep the declaration) → this axis goes red.
printf 'fn main(): i64 { return 0; }\nvar _r = main();\nsyscall(60, _r);\n' > "$D/plain.cyr"
printf '#@pkgver 9.9.9\n' > "$D/marked.cyr"; cat "$D/plain.cyr" >> "$D/marked.cyr"
echo "axis 3 — an unreferenced marker must not perturb the binary:"
"$CC" < "$D/plain.cyr"  > "$D/p.bin" 2>/dev/null
"$CC" < "$D/marked.cyr" > "$D/m.bin" 2>/dev/null
# Floor first, so cmp cannot pass on two empty files.
if [ -s "$D/p.bin" ]; then check "the no-marker build is non-trivial" "yes" "yes"
else check "the no-marker build is non-trivial" "yes" "no"; fi
if cmp -s "$D/p.bin" "$D/m.bin"; then check "marked == unmarked" "yes" "yes"
else check "marked == unmarked" "yes" "no"; fi

# ── AXIS 4: line neutrality. The marker occupies a source line but must not shift
# diagnostics — that is the whole reason this is a directive rather than a cbt prepend.
printf 'fn main(): i64 {\n    var a = 1;\n    return zzz;\n}\nvar _r = main();\n' > "$D/e.cyr"
printf '#@pkgver 9.9.9\n' > "$D/em.cyr"; cat "$D/e.cyr" >> "$D/em.cyr"
echo "axis 4 — the marker does not shift diagnostic line numbers:"
a=$("$CC" < "$D/e.cyr"  2>&1 >/dev/null | head -1 | sed 's/.*<source>:\([0-9]*\):.*/\1/')
b=$("$CC" < "$D/em.cyr" 2>&1 >/dev/null | head -1 | sed 's/.*<source>:\([0-9]*\):.*/\1/')
check "error line without marker" 3 "$a"
check "error line with marker"    3 "$b"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: pkgver-visible-in-includes — resolves from includes, byte- and line-neutral when unused"
    exit 0
fi
echo "FAIL: pkgver-visible-in-includes — $fails assertion(s) failed"
exit 1
