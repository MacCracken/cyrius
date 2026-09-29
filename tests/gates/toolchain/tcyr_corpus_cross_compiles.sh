#!/bin/sh
# Gate: the WHOLE .tcyr corpus compiles for PE, both Mach-O targets and agnos — or the file
# is on that leg's allowlist, and the allowlists only SHRINK (6.6.10).
#
# ⛔ WHY. Nothing cross-compiled tests/tcyr outside crossos/. CI's Test (AGNOS) job builds the
# corpus as x86-LINUX binaries (inside an agnosticos container), darwin_syscall_literals_routed.sh
# covers crossos only, and the release gate's cross-OS leg runs crossos only. So a test that did
# not even COMPILE for a target it claims to support was invisible: measured on the 6.6.10 tree,
# 9 files failed for PE, 1 for both Mach-O targets and 37 for agnos. Every one was a missing guard
# or a missing wrapper — `net_v6_connect.tcyr` reached a PRIVATE Linux-peer helper and raw
# SYS_BIND; PE had the listen (0xF033) and RemoveDirectoryW (0xF03B) reroutes but no `sys_listen`
# / `sys_rmdir`; `derive_enum_inside_ifdef.tcyr` defined its enum only under LINUX. The full-corpus
# run on real ecb and ach found the Mach-O one independently.
#
# RULES.
#   * A file that fails to compile on a leg and is NOT on that leg's allowlist is a FAIL: guard it
#     (a named SKIP where the target has no such call) or give the peer its wrapper.
#   * A file ON an allowlist that now compiles is ALSO a FAIL: take it off. That is the ratchet —
#     the lists can only get shorter, so a fix cannot silently regress back under an old entry.
#   * An output that is empty or has the wrong magic (MZ / Mach-O / ELF) counts as a failure: a
#     compiler that exits 0 and writes nothing must not score a pass.
#   * Axis 0 is the anti-vacuous half: a fixture that cannot compile anywhere must FAIL on every
#     leg, and a trivial one must PASS on every leg, or the gate is reading nothing.
#   * The corpus has a FLOOR — an unmatched find (the v6.5.11 flat-glob shape) is a failure, never
#     a green run over zero files.
#
# The cross compilers are BUILT FROM THIS TREE (src/main_win.cyr, src/main_aarch64.cyr), never
# taken from build/ — those artifacts are gitignored and routinely stale. The x86 Mach-O and agnos
# legs are `$CC` with CYRIUS_MACHO=1 / CYRIUS_TARGET_AGNOS=1. The cx leg is deliberately absent:
# cx is not a stdlib-complete target (96 corpus files fail there, 26 in crossos) and has its own
# gates (cx_tcyr_runs.sh). CHANGELOG [6.6.10]
#
# MUTATION LEDGER (measured 6.6.10, ~55 s wall): restoring the 6.6.9 net_v6_connect.tcyr and
# derive_enum_inside_ifdef.tcyr → six FAIL rows ([pe] x2, [mx], [ma], [agnos] x2); adding a file
# that compiles (platform/fs.tcyr) to the PE allowlist → "on the pe allowlist but compiles now".
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: tcyr_corpus_cross_compiles: $CC missing"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: tcyr_corpus_cross_compiles: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
fail() { echo "FAIL: tcyr_corpus_cross_compiles: $1"; exit 1; }

# ── allowlists (paths under tests/tcyr/; one per line; SHRINK ONLY) ───────────────────────────
# PE: a fork + socket-interop TLS suite whose POSIX-only groups are unguarded (the agnos leg lists
# it too; one guard pass serves both).
cat > "$T/allow.pe" <<'EOF'
EOF
: > "$T/allow.mx"
: > "$T/allow.ma"
# agnos: the peer keeps its own arity (1-arg sys_waitpid, length-carrying sys_unlink/sys_lstat) —
# the 6.6.10 default — so Linux-arity test calls need a named-SKIP guard; lane T's bite 13 owns
# that pass and shrinks this list toward empty.
cat > "$T/allow.agnos" <<'EOF'
stdlib/result_stdlib_pass2.tcyr
EOF

# ── the cross compilers, from this tree ────────────────────────────────────────────────────────
"$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null || true
chmod +x "$T/cc_win" 2> /dev/null || true
[ -s "$T/cc_win" ] || fail "could not build the PE cross compiler from src/main_win.cyr"
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null || true
chmod +x "$T/cc_a64" 2> /dev/null || true
[ -s "$T/cc_a64" ] || fail "could not build the aarch64 cross compiler from src/main_aarch64.cyr"

# build_one <leg> <src> <out>  — exit status 0 iff the compile succeeded AND the output carries
# the leg's magic.
build_one() {
    case "$1" in
        pe)    "$T/cc_win" < "$2" > "$3" 2> /dev/null || return 1; want="4d5a" ;;
        mx)    env CYRIUS_MACHO=1 "$CC" < "$2" > "$3" 2> /dev/null || return 1; want="cffaedfe" ;;
        ma)    env CYRIUS_MACHO_ARM=1 "$T/cc_a64" < "$2" > "$3" 2> /dev/null || return 1; want="cffaedfe" ;;
        agnos) env CYRIUS_TARGET_AGNOS=1 "$CC" < "$2" > "$3" 2> /dev/null || return 1; want="7f454c46" ;;
    esac
    [ -s "$3" ] || return 1
    case "$want" in
        4d5a) got=$(head -c 2 "$3" | od -An -tx1 | tr -d ' \n') ;;
        *)    got=$(head -c 4 "$3" | od -An -tx1 | tr -d ' \n') ;;
    esac
    [ "$got" = "$want" ]
}

# ── axis 0: the check can tell a failure from a pass on every leg ─────────────────────────────
printf 'fn main(): i64 { return _tcc_no_such_fn(); }\nvar r = main();\nsyscall(60, r);\n' > "$T/never.cyr"
printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$T/always.cyr"
for leg in pe mx ma agnos; do
    if build_one "$leg" "$T/never.cyr" "$T/ax0.$leg"; then
        fail "axis 0: [$leg] a program calling an undefined fn compiled clean — this leg cannot see a failure, so every file would score a pass"
    fi
    build_one "$leg" "$T/always.cyr" "$T/ax0.$leg" \
        || fail "axis 0: [$leg] a trivial program did not compile to a $leg binary — the leg is broken, not the corpus"
done

# ── the corpus ─────────────────────────────────────────────────────────────────────────────────
find tests/tcyr -name '*.tcyr' | sed 's|^tests/tcyr/||' | sort > "$T/corpus"
N=$(wc -l < "$T/corpus" | tr -d ' ')
[ "$N" -ge 350 ] || fail "only $N .tcyr files found under tests/tcyr (floor 350) — a broken find must not read as a green corpus"

# One background job per leg; each writes its failing files to $T/fail.<leg>.
run_leg() {
    : > "$T/fail.$1"
    while read -r f; do
        build_one "$1" "tests/tcyr/$f" "$T/bin.$1" || echo "$f" >> "$T/fail.$1"
    done < "$T/corpus"
    echo done > "$T/done.$1"
}
for leg in pe mx ma agnos; do run_leg "$leg" & done
wait
for leg in pe mx ma agnos; do
    [ -f "$T/done.$leg" ] || fail "[$leg] the compile loop did not finish"
done

bad=0
for leg in pe mx ma agnos; do
    sort -u "$T/fail.$leg" > "$T/f.$leg"
    sort -u "$T/allow.$leg" > "$T/a.$leg"
    # failing and not allowlisted
    comm -23 "$T/f.$leg" "$T/a.$leg" > "$T/new.$leg"
    # allowlisted and compiling now (or deleted) — the ratchet
    comm -13 "$T/f.$leg" "$T/a.$leg" > "$T/fixed.$leg"
    while read -r f; do
        [ -n "$f" ] || continue
        echo "  FAIL [$leg] tests/tcyr/$f does not compile — guard it (a named SKIP where the target has no such call) or give the peer its wrapper"
        bad=1
    done < "$T/new.$leg"
    while read -r f; do
        [ -n "$f" ] || continue
        echo "  FAIL [$leg] tests/tcyr/$f is on the $leg allowlist but compiles now (or is gone) — remove it from the allowlist in $0 (the lists only shrink)"
        bad=1
    done < "$T/fixed.$leg"
done
[ "$bad" = 0 ] || fail "see the rows above"

echo "PASS: tcyr_corpus_cross_compiles ($N files; allowlisted pe=$(wc -l < "$T/a.pe" | tr -d ' ') mx=$(wc -l < "$T/a.mx" | tr -d ' ') ma=$(wc -l < "$T/a.ma" | tr -d ' ') agnos=$(wc -l < "$T/a.agnos" | tr -d ' '))"
