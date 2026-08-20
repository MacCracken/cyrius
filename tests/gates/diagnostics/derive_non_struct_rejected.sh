#!/bin/sh
# v6.5.30 — `#derive(...)` on a non-struct must FAIL LOUDLY, naming the declaration.
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

# --- axis 1: THE FILED CASE — #derive(Serialize) on an enum must fail, not go silent ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
#derive(Serialize)
enum probe_e { PE_ONE = 0; PE_TWO = 1; }
syscall(60, 0);
EOF
build
if [ "$rc" -eq 0 ]; then
    echo "  FAIL axis 1: #derive(Serialize) on an enum compiled with rc=0 — the silent no-op is back"
    fail=1
else
    echo "  ok axis 1: an enum derive is rejected (rc=$rc)"
fi

# --- axis 2: the diagnostic must NAME the enum ---
# "it failed somehow" is not the fix; the filing's complaint is that nothing told the author
# which declaration was ignored.
if grep -q "probe_e" "$E"; then
    echo "  ok axis 2: the diagnostic names the offending enum"
else
    echo "  FAIL axis 2: the diagnostic does not name 'probe_e' — the author cannot tell which declaration was rejected"
    echo "      got: $(head -c 200 "$E")"
    fail=1
fi

# --- axis 3: it must say it is about #derive, and that the target is an enum ---
if grep -q "derive" "$E" && grep -q "enum" "$E"; then
    echo "  ok axis 3: the diagnostic identifies both the directive and the kind"
else
    echo "  FAIL axis 3: diagnostic missing 'derive' and/or 'enum': $(head -c 200 "$E")"
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

[ "$fail" -eq 0 ] || { echo "FAIL: derive-non-struct-rejected"; exit 1; }
echo "PASS: derive-non-struct-rejected — a derive on a non-struct fails loudly and names it; struct derives untouched"
