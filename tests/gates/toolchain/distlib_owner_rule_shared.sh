#!/bin/sh
# Gate: `cyrius distlib`'s sidecar verify has ONE owner rule for an undefined symbol, whether
# EVERY target or only some left it undefined (6.7.11, user 2026-10-13).
#
# ⛔ WHAT IT DID BEFORE. A name every target left undefined went to `_distlib_leaf_defining`:
# the first non-fold declarer in BYTE order of the snapshot. The partial-target path
# (`_distlib_partial_owner`, 6.6.18 D3) skipped declarers already in the unit, preferred the one
# dispatcher whose peer declares the name, and refused a tie by name. So on the every-target
# path:
#   - two leaves declaring a name were settled by their NAMES — `foo` in dlt_one and dlt_two
#     recorded dlt_one at rc 0 (measured on 0f733aea's CLI: sidecar `dlt_one`);
#   - an in-unit declarer first in byte order that never defines the name (a dead `#ifdef` arm)
#     was taken as the owner, found already in the unit, and nothing was added: the name fell
#     to D2's "still undefined" warning, the sidecar was written SHORT (measured: `D3Z (every
#     target)` warned, dist/orp.deps = `aad3_decl`, no `zzd3_own`) and the bundle self-check
#     then failed at rc 1, "the generated bundle does not compile";
#   - a peer's name went to whichever leaf sorted first: O_RDWR (declared by the syscalls peers
#     and by lib/io.cyr's agnos arm) recorded `io` in round 1, the partial rule's answer is
#     `syscalls`.
# Both paths now ask `_distlib_symbol_owner`: the fold rule, the D3 skip, the one dispatcher
# whose peer declares it, else the one non-peer declarer, else a refusal naming every candidate,
# and the sidecar is not written.
#
# Axes (a hermetic CYRIUS_HOME whose snapshot is the tree's lib/ plus fixture leaves, and a
# private tool dir holding the CLI, cycc and a cycc_aarch64 built from src/ for this run):
#   T  `foo` is declared by two non-fold, non-peer leaves (dlt_one, dlt_two) and the bundle
#      calls foo() with nothing declared — undefined on every target: rc 1, the refusal names
#      'foo', "every target" and BOTH leaves, and no sidecar is written.
#   D  D3 on the every-target path: the bundle includes lib/aad3_decl.cyr (first in byte order,
#      declares D3Z only in an arm no target defines) and reads D3Z: the sidecar records the next
#      real owner zzd3_own, and no D2 warning names D3Z.
#   P  the dispatcher is preferred on the every-target path too: a bundle reading O_RDWR with
#      nothing declared records `syscalls` in round 1 (the -v trace), then `io` (the agnos arm)
#      in round 2 — never `io` first.
#   C  census: the live lib/ (this tree's) has no every-target tie beyond ALLOW below (empty since
#      6.7.12); every ALLOW row is still a tie (a fixed one is removed from the list); the census
#      finds the fixture's `foo` tie in the hermetic snapshot (self-test), it read a floor of
#      names, and the CLI refuses the first ALLOW row — or, with ALLOW empty, the first tie the
#      census finds in the hermetic snapshot (a fixture's: `D3Z: aad3_decl zzd3_own` sorts
#      first) — naming the same candidates (the two rules agree). Its reader is the CLI's own
#      (cbt/srcscan.cyr, compiled here); the rule is re-derived in shell, so it cannot share a
#      defect with `_distlib_symbol_owner`.
#   W  issues/2026-10-13-ws-and-ws-server-declare-the-same-constants.md's repro verbatim: a bundle
#      reading WS_OPEN with nothing declared records `ws` (ws_server.cyr includes ws.cyr and no
#      longer declares the nine WS_* names, D11 2026-10-15): rc 0, the sidecar is exactly `ws`.
# MUTATIONS (measured): CYRIUS_BIN=<0f733aea's CLI> (byte-order first restored) -> T RED ("distlib
# exited 0 — the tie was settled by byte order (sidecar: dlt_one)"), and with T removed D RED
# (exit 1, the self-check), with T and D removed P RED ("round 1: io recorded"), and C's
# cross-check RED (6.7.11: WS_CLOSED recorded `ws`; 6.7.12, ALLOW empty, with T / D / P removed:
# D3Z taken from aad3_decl, "the generated bundle does not compile"); a new tie pair in lib/ -> C
# RED naming it; an ALLOW row lib/ no longer has -> C RED ("remove it"); ws_server.cyr's nine
# `var WS_*` copies restored (6.7.11's lib/) -> C RED (the nine WS_* ties), and with C's new-tie
# check removed W RED (rc 1, "more than one stdlib leaf could own it (ws, ws_server)").
# Exit 77 when it could not run (no compiler, no CLI, the aarch64 compiler would not build).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
VER=$(cat "$ROOT/VERSION")
[ -x "$CC" ] || { echo "SKIP: distlib_owner_rule_shared: no compiler at $CC"; exit 77; }
[ -x "$CYRIUS" ] || { echo "SKIP: distlib_owner_rule_shared: no CLI at $CYRIUS"; exit 77; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: distlib_owner_rule_shared: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_owner_rule_shared: $1"; exit 1; }

# The tool dir: the CLI resolves cycc / cycc_aarch64 beside itself, so this run tests THESE.
mkdir -p "$WORK/bin" "$WORK/home/versions/$VER"
cp "$CYRIUS" "$WORK/bin/cyrius"; cp "$CC" "$WORK/bin/cycc"; chmod +x "$WORK/bin/cyrius" "$WORK/bin/cycc"
( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$WORK/bin/cycc_aarch64" 2>/dev/null ) \
    || { echo "SKIP: distlib_owner_rule_shared: cycc_aarch64 did not build from src/main_aarch64.cyr"; exit 77; }
chmod +x "$WORK/bin/cycc_aarch64"
L="$WORK/home/versions/$VER/lib"
cp -R "$ROOT/lib" "$L"

# ── fixtures ─────────────────────────────────────────────────────────────────────────
printf 'fn foo(): i64 { return 1; }\n' > "$L/dlt_one.cyr"
printf 'fn foo(): i64 { return 2; }\n' > "$L/dlt_two.cyr"
cat > "$L/aad3_decl.cyr" <<'EOF'
#ifdef CYRIUS_DLT_NEVER_DEFINED
var D3Z = 1;
#endif
fn aad3_decl_x(x): i64 { return x; }
EOF
printf 'var D3Z = 3;\n' > "$L/zzd3_own.cyr"

mkproj() {  # mkproj <dir> <body of src/lib.cyr>   — nothing declared
    d="$WORK/$1"; mkdir -p "$d/src"
    printf '[package]\nname = "orp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$VER" > "$d/cyrius.cyml"
    printf '%s\n' "$2" > "$d/src/lib.cyr"
    echo "$d"
}
# env -u: the target selectors of the CALLER's shell must not leak into the run.
run_distlib() { d=$1; shift; ( cd "$d" && env -u CYRIUS_TARGET_WIN -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM -u CYRIUS_TARGET_AGNOS \
    CYRIUS_HOME="$WORK/home" CYRIUS_RESOLVED=1 "$WORK/bin/cyrius" distlib "$@" 2>&1 ); }
leaves() { grep -v '^#' "$1/dist/orp.deps" 2>/dev/null | tr '\n' ' '; }

# ── T: a tie on every target is a named refusal ──────────────────────────────────────
T=$(mkproj t 'fn orp_t(): i64 { return foo(); }')
if OT=$(run_distlib "$T"); then
    fail "T: distlib exited 0 — the tie was settled by byte order (sidecar: $(leaves "$T"))"
fi
[ -f "$T/dist/orp.deps" ] && fail "T: a sidecar was written although 'foo' has two owners: [$(leaves "$T")]"
echo "$OT" | grep -q "'foo' is undefined on every target, and more than one stdlib leaf could own it" \
    || fail "T: the refusal did not name 'foo' on every target: $(echo "$OT" | grep -i error | head -3)"
echo "$OT" | grep -q '(dlt_one, dlt_two)' || fail "T: the refusal did not name both leaves in byte order: $(echo "$OT" | grep -i error | head -3)"
echo "$OT" | grep -q 'Sidecar NOT written' || fail "T: the refusal did not say the sidecar was not written: $(echo "$OT" | grep -i error | head -3)"

# ── D: an in-unit declarer first in byte order is skipped (D3) ───────────────────────────
D=$(mkproj d 'include "lib/aad3_decl.cyr"
fn orp_d(): i64 { return D3Z + aad3_decl_x(0); }')
rc=0; OD=$(run_distlib "$D") || rc=$?
[ "$rc" -eq 0 ] || fail "D: distlib exited $rc: $(echo "$OD" | grep -i error | head -3)"
grep -qx 'zzd3_own' "$D/dist/orp.deps" 2>/dev/null \
    || fail "D: the next real owner zzd3_own was not recorded: [$(leaves "$D")] — the in-unit aad3_decl was taken as the owner"
echo "$OD" | grep -q 'D3Z (' && fail "D: D2's warning still names D3Z: $(echo "$OD" | grep 'D3Z' | head -2)"

# ── P: the dispatcher whose peers declare it, on every target too ────────────────────────
P=$(mkproj p 'fn orp_p(): i64 { return O_RDWR; }')
rc=0; OP=$(run_distlib "$P" -v) || rc=$?
[ "$rc" -eq 0 ] || fail "P: distlib exited $rc: $(echo "$OP" | grep -i error | head -3)"
echo "$OP" | grep -q "round 1: syscalls recorded for 'O_RDWR' (every target)" \
    || fail "P: round 1 did not record the dispatcher syscalls for O_RDWR: $(echo "$OP" | grep 'round' | head -3)"
echo "$OP" | grep -q "round 1: io recorded" && fail "P: io (a non-peer declarer) was taken before the dispatcher: $(echo "$OP" | grep 'round' | head -3)"
[ "$(leaves "$P")" = "syscalls io " ] || fail "P: the sidecar is [$(leaves "$P")], not [syscalls io] (io: O_RDWR's agnos arm)"

# ── C: census of every-target ties in the live lib/ ──────────────────────────────────────
# A tie that is ALLOWED here is a FILED issue, never a silent pass. One "NAME: cand cand" row per
# tie. Empty since 6.7.12: the ws / ws_server WS_* tie (the only rows 6.7.11 listed) ended when
# ws_server.cyr took the names from ws.cyr (row W).
ALLOW=''
cat > "$WORK/dump.cyr" <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/args.cyr"
include "lib/syscalls.cyr"
include "cbt/srcscan.cyr"

# Each file's top-level fn / var / enum-member names, one per line — the set the CLI's snapshot
# index (_distlib_snap_index) adds for it.
fn main(): i64 {
    alloc_init();
    args_init();
    var i = 1;
    while (i < argc()) {
        var p = argv(i);
        i = i + 1;
        var n = 0;
        var b = file_read_whole(p, &n);
        if (b == 0) { sys_write(2, "census: unreadable file\n", 24); return 2; }
        if (n <= 0) { continue; }
        _src_blank_noncode(b, n);
        var offs = vec_new();
        var lens = vec_new();
        var kinds = vec_new();
        _src_decls(b, n, offs, lens, kinds);
        var k = 0;
        while (k < vec_len(offs)) {
            var kd = vec_get(kinds, k);
            if (kd == SRC_DECL_FN || kd == SRC_DECL_VAR || kd == SRC_DECL_MEMBER) {
                sys_write(1, b + vec_get(offs, k), vec_get(lens, k));
                sys_write(1, "\n", 1);
            }
            k = k + 1;
        }
    }
    return 0;
}
var r = main();
syscall(60, r);
EOF
( cd "$ROOT" && "$CC" < "$WORK/dump.cyr" > "$WORK/dump" 2>/dev/null ) || fail "C: the census reader did not build from cbt/srcscan.cyr"
chmod +x "$WORK/dump"
# census <snapshot> <out dir>: writes <out>/ties ("NAME: cand cand ...", sorted) and <out>/nmulti.
census() {
    S=$1; W=$2; mkdir -p "$W"
    : > "$W/decls"     # "<leaf> <name>", leaves in byte order of the entry names (the CLI's)
    ls -A "$S" | LC_ALL=C sort > "$W/ents"
    : > "$W/allleaves"
    while read -r e; do
        case $e in .*) continue ;; esac
        if [ -d "$S/$e" ]; then
            ls -A "$S/$e" | LC_ALL=C sort | grep '..*\.cyr$' > "$W/mem" || continue
            echo "$e" >> "$W/allleaves"
            while read -r f; do "$WORK/dump" "$S/$e/$f" | sed "s|^|$e |" >> "$W/decls" || return 1; done < "$W/mem"
        else
            case $e in ?*.cyr) ;; *) continue ;; esac
            echo "${e%.cyr}" >> "$W/allleaves"
            "$WORK/dump" "$S/$e" | sed "s|^|${e%.cyr} |" >> "$W/decls" || return 1
        fi
    done < "$W/ents"
    awk '{ if (!(($1 SUBSEP $2) in s)) { s[$1 SUBSEP $2] = 1; n[$2]++ } } END { for (k in n) if (n[k] >= 2) print k }' \
        "$W/decls" | LC_ALL=C sort > "$W/multi"
    wc -l < "$W/multi" | tr -d ' ' > "$W/nmulti"
    awk 'NR == FNR { m[$1] = 1; next } ($2 in m) { print $1 }' "$W/multi" "$W/decls" | LC_ALL=C sort -u > "$W/leaves"
    : > "$W/meta"      # "<leaf> <dispatcher> <fold 0|1>" — _distlib_resolve_dispatcher / _distlib_is_fold
    while read -r l; do
        f=0
        [ -f "$S/$l.cyr" ] && head -c 2048 "$S/$l.cyr" | grep -qE 'Generated by: cyrius distlib|Bundled distribution of' && f=1
        echo "$l $(_c_resolve "$S" "$W" "$l") $f" >> "$W/meta"
    done < "$W/leaves"
    # The rule: folds drop out while a non-fold declares it; one dispatcher whose peer declares it;
    # else one non-peer declarer; else a tie (the candidates listed as the refusal lists them).
    awk 'FILENAME == ARGV[1] { own[$1] = $2; fold[$1] = $3; next }
         FILENAME == ARGV[2] { m[$1] = 1; next }
         ($2 in m) { if (!(($1 SUBSEP $2) in s)) { s[$1 SUBSEP $2] = 1; d[$2] = d[$2] " " $1 } }
         END {
           for (k in d) {
             n = split(substr(d[k], 2), L, " ")
             nf = 0; for (i = 1; i <= n; i++) if (fold[L[i]] == 0) nf = 1
             np = 0; ns = 0; pl = ""; sl = ""; split("", P); split("", Q)
             for (i = 1; i <= n; i++) {
               x = L[i]; if (nf && fold[x] == 1) continue
               if (own[x] != x) { if (!(own[x] in P)) { P[own[x]] = 1; np++; pl = pl " " own[x] } }
               else if (!(x in Q)) { Q[x] = 1; ns++; sl = sl " " x }
             }
             if (np >= 2) print k ":" pl
             else if (np == 0 && ns >= 2) print k ":" sl
           }
         }' "$W/meta" "$W/multi" "$W/decls" | LC_ALL=C sort > "$W/ties"
}
_c_includes() { [ -f "$1/$2.cyr" ] && grep -qF "include \"lib/$3.cyr\"" "$1/$2.cyr"; }   # <snap> <file> <leaf>
_c_resolve() {  # <snap> <work> <leaf>: the dispatcher, or the leaf itself
    s=$1; w=$2; l=$3
    if [ -d "$s/$l" ]; then echo "$l"; return 0; fi
    # every prefix that ends before a `_` past the first byte, shortest first
    for pre in $(printf '%s\n' "$l" | awk '{ for (i = 2; i <= length($0); i++) if (substr($0, i, 1) == "_") print substr($0, 1, i - 1) }'); do
        [ -f "$s/$pre.cyr" ] || continue
        if _c_includes "$s" "$pre" "$l"; then echo "$pre"; return 0; fi
        # a peer of a peer: the first `<pre>_…` peer pre.cyr includes that includes the leaf, and
        # nothing but `<pre>_…` files (and the leaf) include it
        for pp in $(grep -o "include \"lib/${pre}_[^\"]*\.cyr\"" "$s/$pre.cyr" | sed 's/^include "lib\///; s/\.cyr"$//'); do
            [ "$pp" = "$l" ] && continue
            _c_includes "$s" "$pp" "$l" || continue
            only=1
            while read -r b; do
                [ "$b" = "$l" ] && continue
                case $b in "${pre}"_*) continue ;; esac
                if _c_includes "$s" "$b" "$l"; then only=0; break; fi
            done < "$w/allleaves"
            [ "$only" = 1 ] && { echo "$pre"; return 0; }
            break
        done
    done
    echo "$l"
}
census "$ROOT/lib" "$WORK/cl" || fail "C: the census could not read $ROOT/lib"
NM=$(cat "$WORK/cl/nmulti")
[ "$NM" -ge 200 ] || fail "C: the census found only $NM names declared by two or more lib/ leaves — the reader is not reading (floor 200)"
printf '%s\n' "$ALLOW" | sed '/^$/d' | LC_ALL=C sort > "$WORK/allow"
NEW=$(LC_ALL=C comm -23 "$WORK/cl/ties" "$WORK/allow")
[ -z "$NEW" ] || fail "C: lib/ has an every-target tie the owner rule refuses — a consumer bundle using it gets 'Sidecar NOT written': $(echo "$NEW" | head -5 | tr '\n' ';') (fix lib/, or file it and add it to ALLOW)"
GONE=$(LC_ALL=C comm -13 "$WORK/cl/ties" "$WORK/allow")
[ -z "$GONE" ] || fail "C: ALLOW lists a tie lib/ no longer has — remove it: $(echo "$GONE" | tr '\n' ';')"
census "$L" "$WORK/cf" || fail "C: the census could not read the fixture snapshot"
grep -qx 'foo: dlt_one dlt_two' "$WORK/cf/ties" || fail "C: self-test — the census did not find the fixture's 'foo' tie: $(head -3 "$WORK/cf/ties" | tr '\n' ';')"
# The census's rule and the CLI's agree on a tie: the first ALLOW row (a live lib/ tie) through
# distlib, or — ALLOW empty — the first tie the census found in the hermetic snapshot.
A1=$(sed -n 1p "$WORK/allow")
AK=live
if [ -z "$A1" ]; then A1=$(sed -n 1p "$WORK/cf/ties"); AK=snapshot; fi
[ -n "$A1" ] || fail "C: no tie to cross-check the CLI against (ALLOW empty and the snapshot census found none)"
an=${A1%%:*}; ac=$(echo "${A1#*: }" | sed 's/ /, /g')
A=$(mkproj a "fn orp_a(): i64 { return $an; }")
if OA=$(run_distlib "$A"); then fail "C: the CLI did not refuse the $AK tie $an (census: $ac): sidecar [$(leaves "$A")]"; fi
echo "$OA" | grep -qF "'$an' is undefined on every target, and more than one stdlib leaf could own it ($ac)" \
    || fail "C: the CLI's refusal for $an does not name the census's candidates ($ac): $(echo "$OA" | grep -i error | head -2)"

# ── W: the WS_* names have one owner (issues/2026-10-13-ws-and-ws-server-declare-the-same-constants.md)
WSP=$(mkproj w 'fn orp_a(): i64 { return WS_OPEN; }')
rc=0; OW=$(run_distlib "$WSP") || rc=$?
[ "$rc" -eq 0 ] || fail "W: distlib exited $rc for a bundle reading WS_OPEN: $(echo "$OW" | grep -i error | head -3)"
[ "$(leaves "$WSP")" = "ws " ] || fail "W: the sidecar is [$(leaves "$WSP")], not [ws] — WS_OPEN's one owner is lib/ws.cyr"

echo "PASS: distlib_owner_rule_shared (one owner rule on every target too: a tie is refused by name with no sidecar, an in-unit declarer is skipped, the dispatcher is preferred; census: $NM multi-declared lib/ names, $(wc -l < "$WORK/allow" | tr -d ' ') allowlisted ties, none new, the CLI agrees on the $AK tie $an; WS_OPEN records ws)"
exit 0
