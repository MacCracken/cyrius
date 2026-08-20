#!/bin/sh
# v6.5.30/.31 — `#derive(...)` must handle each declaration kind DELIBERATELY: generate a codec
# for a struct, generate a codec for an enum, and reject anything else loudly.
#
# ⚠ v6.5.31 INVERTED the enum rows. `.30` shipped the loud rejection because the wire shape was
# an open contract decision; the maintainer settled it (name string + Result) and `.31` ships
# the generation, so "an enum is rejected" became "an enum WORKS". The rejection rows now cover
# the residual case — a declaration that is neither struct nor enum — which is what the
# diagnostic still exists for.
#
# ⛔ THE DEFECT. `PP_PARSE_STRUCT_DEF` skipped `ip + 7` — the width of `"struct "` — with no
# check that the keyword WAS `struct`. On `enum probe_e { ... }` it skipped `"enum pr"` and
# read the name as `obe_e`, which is where ranga's long-recorded "misnamed, crashing codec"
# symptom came from. By 6.5.27 the downstream emit produced nothing at all, so
# `#derive(Serialize)` above an enum compiled **rc=0, no diagnostic, no codec** — the caller
# found out as `undefined function <name>_to_json` at link time, possibly long after writing
# the derive, and only if the codec was ever actually called. ranga hand-writes four enum
# codecs because of this.
#
# ⚠ WHY A GATE. The old behaviour was rc=0 with clean output, so no `.tcyr` could see it: a
# test that compiles and exits 0 is indistinguishable from a test whose derive worked. The
# assertion has to be on the DIAGNOSTIC and the EXIT CODE of a compile that must fail.
#
# The filing ranks the outcomes — support it, else reject loudly, else warn — and says
# rejecting "would be strictly better than the current silence, even if enum support never
# lands". Enum support is a separate feature (a name<->value codec plus the parse direction)
# whose JSON shape is a maintainer design call; this gate covers the end of the silence.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
T=$(mktemp --suffix=.cyr); O=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$O" "$E"' EXIT
fail=0
# Never merge stderr into the binary stream.
build() { rc=0; "$CC" < "$T" > "$O" 2>"$E" || rc=$?; }

# --- axis 1 (v6.5.31): #derive(Serialize) on an enum GENERATES a working codec ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/result.cyr"
#derive(Serialize)
enum probe_e { PE_ONE = 0; PE_TWO = 1; }
fn main(): i64 {
    var sb = str_builder_new();
    probe_e_to_json(PE_TWO, sb);
    var s = str_builder_build(sb);
    if (streq(str_data(s), "\"PE_TWO\"") == 0) { return 3; }
    var r = probe_e_from_json_str("\"PE_ONE\"");
    if (is_ok(r) == 0) { return 4; }
    if (result_unwrap(r) != PE_ONE) { return 5; }
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 1: #derive(Serialize) on an enum did not build (rc=$rc)"
    grep -m2 '^error' "$E" | sed 's/^/      /' || true
    fail=1
else
    chmod +x "$O" 2>/dev/null || true
    erc=0
    "$O" >/dev/null 2>&1 || erc=$?
    if [ "$erc" -ne 0 ]; then
        echo "  FAIL axis 1: the generated enum codec is wrong (probe exit $erc: 3=to_json, 4=parse Err, 5=wrong value)"
        fail=1
    else
        echo "  ok axis 1: an enum derive generates a working name-string codec pair"
    fi
fi

# --- axis 2 (ANTI-VACUOUS for axis 1): a bare #derive(Deserialize) must ALSO emit ---
# Before .31 this emitted NOTHING — on structs as well as enums — because the codec body was
# only reached when `Serialize` happened to be stacked. Axis 1 alone would not notice.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/result.cyr"
#derive(Deserialize)
enum bare_e { BE_A = 7; BE_B = 8; }
fn main(): i64 {
    var r = bare_e_from_json_str("\"BE_B\"");
    if (is_ok(r) == 0) { return 3; }
    if (result_unwrap(r) != 8) { return 4; }
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 2 (anti-vacuous): a bare #derive(Deserialize) on an enum did not build (rc=$rc)"
    fail=1
else
    chmod +x "$O" 2>/dev/null || true
    erc=0
    "$O" >/dev/null 2>&1 || erc=$?
    if [ "$erc" -ne 0 ]; then
        echo "  FAIL axis 2 (anti-vacuous): bare #derive(Deserialize) emitted no usable codec (exit $erc)"
        fail=1
    else
        echo "  ok axis 2: a bare #derive(Deserialize) emits a usable codec"
    fi
fi

# --- axis 3: a declaration that is NEITHER struct nor enum is still rejected, loudly ---
# This is what the .30 diagnostic still exists for, and it must not have been widened away
# while adding the enum arm.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
#derive(Serialize)
fn not_a_type(): i64 { return 0; }
syscall(60, 0);
EOF
build
if [ "$rc" -eq 0 ]; then
    echo "  FAIL axis 3: #derive on a fn compiled rc=0 — the silent no-op is back for non-struct, non-enum"
    fail=1
elif grep -q "derive" "$E"; then
    echo "  ok axis 3: a derive on a non-struct, non-enum declaration is rejected and says so"
else
    echo "  FAIL axis 3: rejected but the diagnostic does not mention 'derive': $(head -c 160 "$E")"
    fail=1
fi

# --- axis 4 (ANTI-VACUOUS): a #derive on a real STRUCT must still work ---
# Axes 1-3 assert a rejection; deleting derive support outright, or rejecting every derive,
# would satisfy all three. This is the row that keeps the feature alive.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/bayan.cyr"
#derive(Serialize)
struct ok_s { a; b; }
fn main(): i64 {
    # The generated codec is the documented 2-arg composable form,
    # `Name_to_json(ptr, sb)` — it writes into the caller's builder rather than returning a
    # string. (First draft of this axis called it with one arg and failed against correct
    # code, which is the kind of test bug that reads as a regression.)
    var v: ok_s = 0;
    var sb = str_builder_new();
    ok_s_to_json(&v, sb);
    return 0;
}
var e = main();
syscall(60, e);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 4 (anti-vacuous): #derive(Serialize) on a STRUCT no longer works (rc=$rc) — the rejection is too broad"
    grep -m2 '^error' "$E" | sed 's/^/      /' || true
    fail=1
else
    echo "  ok axis 4: #derive(Serialize) on a struct still generates a callable codec"
fi

# --- axis 5 (ANTI-VACUOUS, narrower): a struct derive with NO call must still be rc=0 ---
# Guards against a rejection that fires on the directive rather than on the declaration kind.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
#derive(Serialize)
struct bare_s { a; b; }
syscall(60, 0);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 5 (anti-vacuous): a bare struct derive was rejected (rc=$rc)"
    fail=1
else
    echo "  ok axis 5: a struct derive with no call site compiles clean"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: derive-declaration-kinds"; exit 1; }
echo "PASS: derive-declaration-kinds — struct and enum derives generate codecs; anything else is rejected loudly"
