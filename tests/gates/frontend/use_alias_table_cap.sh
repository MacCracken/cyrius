#!/bin/sh
# Gate: the `use mod.fn;` alias table is bounded — the 65th alias is REFUSED by name, never
# stored (6.6.20, HEAP-02, the use-alias table overflow bug; SECURITY).
#
# THE DEFECT (measured at 6.6.19, x86_64 Linux, no diagnostic): `_tl_use_alias`
# (src/frontend/parse_fn.cyr) stored alias #uc at use_from[uc] / use_to[uc] with no cap. The two
# tables are 64 entries each and ABUT in the heap map (use_from @0x18FFD0, use_to @0x1901D0, the
# count @0x1903D0), so the 65th `use` wrote its source name into use_to[0] — alias #1 then
# resolved to whatever fn carried that bare name, and the program called it silently — and every
# later alias walked on through the parser's state (expr types, include names, the #define table)
# up to gvar_cnt: 66-120 aliases failed loud with a bogus "undefined function", 199-5062 compiled
# rc 0 and called the wrong fn, 5063+ died SIGSEGV. The same unguarded code was inline in 6.5.73.
#
# THE FIX: refuse at uc >= 64 with "too many `use` aliases (max 64)" BEFORE any store (ERR_MSG does
# not exit; the `return 0` is what stops the writes). MUTATION LEDGER (6.6.20):
#   cap removed (6.6.19)                  -> RED rows R65 R200 R5100 (R65 rc 0, exits 99: the bare global)
#   cap at 63                             -> RED row A64
#   the `return 0` dropped (ERR_MSG only) -> RED row R5100 (the stores still run: rc 139)
#
# Every fixture: a GLOBAL fn g64 (exit 99), then `mod m;` with g0..g(K-1) (g0 exits 7), then N
# `use m.gI;` lines, then a call of the bare name g0 — which resolves ONLY through the alias table
# (row C: with no `use`, g0 is undefined).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: use_alias_table_cap: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: use_alias_table_cap: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: use_alias_table_cap: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# fixture <uses> <module fns> <out>
fixture() {
    awk -v n="$1" -v k="$2" 'BEGIN {
        print "fn g64(): i64 { return 99; }"
        print "mod m;"
        print "fn g0(): i64 { return 7; }"
        for (i = 1; i < k; i++) printf "fn g%d(): i64 { return %d; }\n", i, i + 100
        for (i = 0; i < n; i++) printf "use m.g%d;\n", i
        print "var r = g0();"
        print "syscall(60, r);"
    }' > "$3"
}

# A64 — 64 aliases, the table full: g0 is alias #1 and resolves to m's g0 (exit 7)
NROWS=$((NROWS + 1))
fixture 64 65 "$D/a.cyr"
if "$CC" < "$D/a.cyr" > "$D/a.bin" 2> "$D/a.err" && [ -s "$D/a.bin" ]; then
    chmod +x "$D/a.bin"
    set +e; "$D/a.bin" > /dev/null 2>&1; r=$?; set -e
    [ "$r" = "7" ] || bad "row A64: 64 aliases ran with exit $r, want 7 (m's g0)"
else
    bad "row A64: 64 aliases did not compile: $(grep -v '^note' "$D/a.err" | head -c 200)"
fi

# R<N> — N > 64 aliases: refused by name, exit 1 (not a SIGSEGV), no binary that runs
refuse() {
    NROWS=$((NROWS + 1))
    fixture "$1" "$2" "$D/r.cyr"
    set +e; "$CC" < "$D/r.cyr" > "$D/r.bin" 2> "$D/r.err"; rc=$?; set -e
    if [ "$rc" = "0" ]; then
        set +e; chmod +x "$D/r.bin"; "$D/r.bin" > /dev/null 2>&1; r=$?; set -e
        bad "row R$1: $1 aliases COMPILED (rc 0; the program exits $r — 7 is m's g0, 99 the bare global)"
    elif [ "$rc" != "1" ]; then
        bad "row R$1: $1 aliases: the compiler died (rc $rc), want a refusal (rc 1)"
    elif ! grep -q 'too many `use` aliases (max 64)' "$D/r.err"; then
        bad "row R$1: refused without the cap diagnostic: $(grep -v '^note' "$D/r.err" | head -c 200)"
    fi
}
refuse 65 65      # the first entry past the table: re-bound alias #1 to the global g64 (exit 99)
refuse 200 200    # silently miscompiled
refuse 5100 5100  # reached gvar_cnt: SIGSEGV

# C — the premise: with no `use`, the bare g0 is undefined (so A64 / R65 measure the table)
NROWS=$((NROWS + 1))
fixture 0 65 "$D/c.cyr"
if "$CC" < "$D/c.cyr" > "$D/c.bin" 2> "$D/c.err"; then
    bad "row C: g0 resolved with no \`use\` — the fixture no longer measures the alias table"
elif ! grep -q "undefined function 'g0'" "$D/c.err"; then
    bad "row C: refused, but not as an undefined g0: $(grep -v '^note' "$D/c.err" | head -c 200)"
fi

[ "$NROWS" -eq 5 ] || bad "floor: $NROWS rows ran, want 5"
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: use_alias_table_cap: $NFAIL check(s) failed"
    exit 1
fi
echo "PASS: the use-alias table refuses its 65th entry by name and stores nothing past 64 ($NROWS rows) (6.6.20)"
exit 0
