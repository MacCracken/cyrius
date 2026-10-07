#!/bin/sh
# macos_arm64_libsystem_fork.sh — 6.6.13 (I6)
#
# Pins the arm64-macOS fork: lib/syscalls_aarch64_linux.cyr's sys_fork spells `syscall(1701)`
# under CYRIUS_TARGET_MACOS, and the compiler lowers it to libSystem `fork()` through
# __got[7], reading errno through __got[8] `___error` when it fails.
#
# ⛔ WHY. The aarch64 peer's `clone(SIGCHLD, ...)` translates to Darwin's RAW BSD fork, which
# creates the child behind libSystem's back: no atfork handlers, no libpthread child
# re-initialisation. thread_create on arm64 macOS IS libSystem pthread_create (__got[5]), and
# in such a child it ran on libpthread state that still described the parent and died of
# SIGSEGV (docs/development/issues/archived/2026-10-01-macos-arm64-thread-create-in-fork-child-sigsegv.md).
# The behaviour is held on real hardware by tests/tcyr/crossos/fork_then_thread.tcyr on the
# release gate's ecb leg; this gate holds the couplings that leg cannot name:
#
#   axis 1  the 1701 reroute sits inside the `_TARGET_MACHO == 2` block, fires at argc 1, and
#           _macho_reroute_argc agrees — anywhere else it would emit a GOT call into a binary
#           with no GOT (x86 Mach-O, ELF, PE)
#   axis 2  EMACHO_FORK_ARM calls the slots the Mach-O writer actually binds `_fork` and
#           `___error` to (bind ORDER is the source of truth; a reorder would make it call
#           whatever now sits there)
#   axis 3  the writer's parallel tables agree: bind calls == GOT_SIZE/8 == INDIRECT_SIZE/4 ==
#           undef nlist count == SYMTAB_COUNT-2 == LC_DYSYMTAB nundefsym == nindirectsyms; each
#           undef's strx is the strtab offset of the name bound at the same slot (a one-byte
#           drift is a dyld "Symbol not found" at load); the indirect table maps __got[i] to
#           symtab[2+i]; BIND_SIZE / STRTAB_SIZE hold their contents, 8-aligned, with < 8 B slack
#   axis 4  return-0 stubs in every other backend (parse_expr references the emitter in every
#           fork — the v6.4.26 trap: a missing stub links only on the fork nobody builds locally)
#   axis 5  _macho_arm_routes claims 1701, or every sys_fork would warn "syscall not routed"
#   axis 6  sys_fork's macOS arm spells 1701 and its other arm still spells SYS_CLONE (real
#           aarch64 Linux stays on clone); the x86-macOS peer never spells 1701 (its static
#           no-libSystem Mach-O has no __got, so 1701 there is SIGSYS)
#   axis 7  EMACHO_FORK_ARM sign-extends the pid_t (sxtw) BEFORE its failure compare — AAPCS64
#           leaves x0's upper half unspecified for an int, and a -1 read as 4294967295 is a
#           "parent" with a bogus pid — then returns -errno via ldrsw/neg, and its b.ne skips
#           exactly the errno path
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PE="$ROOT/src/frontend/parse_expr.cyr"
AE="$ROOT/src/backend/aarch64/emit.cyr"
ME="$ROOT/src/backend/macho/emit_arm64.cyr"
SA="$ROOT/lib/syscalls_aarch64_linux.cyr"
SM="$ROOT/lib/syscalls_macos.cyr"
fail() { echo "FAIL macos_arm64_libsystem_fork: $1" >&2; exit 1; }
# ⚠ Piped matches use `grep -c … >/dev/null`, never `grep -q`: -q exits at the first match, the
# producer then dies of SIGPIPE, and under `bash -o pipefail` that reads as NO match.
for f in "$PE" "$AE" "$ME" "$SA" "$SM"; do [ -f "$f" ] || fail "missing $f"; done

# fn body (from `fn NAME(` to the first line that is exactly `}`)
_body() { awk -v n="fn $2(" 'index($0, n) == 1 {s = 1} s {print} s && /^}/ {exit}' "$1"; }

# ── axis 1: the reroute is arm64-Mach-O-guarded, at argc 1, and the arity table agrees ─────────
L=$(grep -n 'sc_num == 1701' "$PE" | head -1 | cut -d: -f1)
[ -n "$L" ] || fail "the 1701 (libSystem fork) reroute is missing from parse_expr"
[ "$(grep -c 'sc_num == 1701' "$PE")" = 1 ] || fail "more than one 1701 reroute in parse_expr"
OPEN=$(awk -v L="$L" 'NR < L && /if \(_TARGET_MACHO == [0-9]\) \{/ {o = NR; t = $0} END {print o}' "$PE")
[ -n "$OPEN" ] || fail "no _TARGET_MACHO block precedes the 1701 reroute"
sed -n "${OPEN}p" "$PE" | grep -c '_TARGET_MACHO == 2' >/dev/null \
    || fail "the nearest Mach-O block above the 1701 reroute is not _TARGET_MACHO == 2 (arm64) — elsewhere it emits a GOT call into a binary with no GOT"
DEPTH=$(sed -n "${OPEN},$((L - 1))p" "$PE" | sed 's/#.*//' \
    | awk '{n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); d += n - m} END {print d}')
[ "$DEPTH" -ge 1 ] || fail "the 1701 reroute sits AFTER the _TARGET_MACHO == 2 block closes (brace depth $DEPTH), so it is unguarded"
sed -n "$L,$((L + 4))p" "$PE" | grep -c 'argc == 1' >/dev/null \
    || fail "the 1701 reroute does not require argc == 1 — fork takes no arguments, and any other arity would mis-pop the stack"
sed -n "$L,$((L + 4))p" "$PE" | grep -c 'EMACHO_FORK_ARM(S);' >/dev/null \
    || fail "the 1701 reroute does not call EMACHO_FORK_ARM"
_body "$PE" _macho_reroute_argc | grep -c 'if (tgt == 2) { if (n == 1701) { return 1; } }' >/dev/null \
    || fail "_macho_reroute_argc does not report 1701 at argc 1 on arm64 Mach-O (tgt 2) — it must mirror the reroute block"

# ── axis 2: EMACHO_FORK_ARM's slots are the writer's _fork / ___error ────────────────────────
FB=$(_body "$AE" EMACHO_FORK_ARM)
[ -n "$FB" ] || fail "EMACHO_FORK_ARM missing from the aarch64 backend"
SLOTS=$(printf '%s\n' "$FB" | grep -oE '_EMACHO_BLR_GOT\(S, [0-9]+\)' | grep -oE '[0-9]+' | tr '\n' ' ')
set -- $SLOTS
[ "$#" = 2 ] || fail "EMACHO_FORK_ARM should make exactly two GOT calls (_fork, then ___error); found: '$SLOTS'"
S_FORK=$1; S_ERR=$2
MW=$(_body "$ME" EMITMACHO_ARM64)
[ -n "$MW" ] || fail "EMITMACHO_ARM64 missing from the Mach-O writer"
BINDS=$(printf '%s\n' "$MW" | grep -oE '_macho_wbindsym\(O, o, "[^"]*"\)' | sed 's/.*"\(.*\)").*/\1/')
_slot_of() { printf '%s\n' "$BINDS" | grep -nx -- "$1" | head -1 | cut -d: -f1; }
I_FORK=$(_slot_of _fork); I_ERR=$(_slot_of ___error)
[ -n "$I_FORK" ] || fail "no _fork bind in EMITMACHO_ARM64"
[ -n "$I_ERR" ] || fail "no ___error bind in EMITMACHO_ARM64"
[ "$S_FORK" = "$((I_FORK - 1))" ] \
    || fail "EMACHO_FORK_ARM calls __got[$S_FORK] for fork but _fork is bound at __got[$((I_FORK - 1))]"
[ "$S_ERR" = "$((I_ERR - 1))" ] \
    || fail "EMACHO_FORK_ARM calls __got[$S_ERR] for errno but ___error is bound at __got[$((I_ERR - 1))]"

# ── axis 3: the writer's parallel tables agree ───────────────────────────────────────────────
NB=$(printf '%s\n' "$BINDS" | grep -c .)
[ "$NB" -ge 9 ] || fail "anti-vacuous: only $NB binds read from EMITMACHO_ARM64 (expected >= 9)"
_lit() { printf '%s\n' "$MW" | grep -oE "var $1 = [0-9]+;" | grep -oE '[0-9]+' | head -1; }
GOT=$(_lit GOT_SIZE); IND=$(_lit INDIRECT_SIZE); SYC=$(_lit SYMTAB_COUNT); SYS=$(_lit SYMTAB_SIZE)
BSZ=$(_lit BIND_SIZE); STZ=$(_lit STRTAB_SIZE)
for v in GOT IND SYC SYS BSZ STZ; do eval "[ -n \"\$$v\" ]" || fail "could not read $v from EMITMACHO_ARM64"; done
[ "$((GOT / 8))" = "$NB" ] && [ "$((GOT % 8))" = 0 ] || fail "GOT_SIZE $GOT is not $NB slots × 8"
[ "$((IND / 4))" = "$NB" ] && [ "$((IND % 4))" = 0 ] || fail "INDIRECT_SIZE $IND is not $NB entries × 4"
[ "$((SYC - 2))" = "$NB" ] || fail "SYMTAB_COUNT $SYC is not 2 defined + $NB undefs"
[ "$SYS" = "$((SYC * 16))" ] || fail "SYMTAB_SIZE $SYS is not SYMTAB_COUNT $SYC × 16"
NUND=$(printf '%s\n' "$MW" | grep 'iundef=2' | grep -oE '_macho_w32\(O, o, [0-9]+\)' | tail -1 | grep -oE '[0-9]+\)' | tr -d ')')
NIND=$(printf '%s\n' "$MW" | grep 'indirectsymoff, nindirectsyms' | grep -oE '_macho_w32\(O, o, [0-9]+\)' | tail -1 | grep -oE '[0-9]+\)' | tr -d ')')
[ "$NUND" = "$NB" ] || fail "LC_DYSYMTAB nundefsym is '$NUND', not $NB"
[ "$NIND" = "$NB" ] || fail "LC_DYSYMTAB nindirectsyms is '$NIND', not $NB"
STRX=$(printf '%s\n' "$MW" | grep -oE '_macho_wsymundef\(O, o, [0-9]+\)' | grep -oE '[0-9]+\)' | tr -d ')')
[ "$(printf '%s\n' "$STRX" | grep -c .)" = "$NB" ] || fail "the undef nlist count is not $NB"
# strtab offsets, in write order: "name<TAB>offset"
STRS=$(printf '%s\n' "$MW" | grep -oE '_macho_wcstr\(O, o, "[^"]*"\)' | sed 's/.*"\(.*\)").*/\1/' \
    | awk '{printf "%s\t%d\n", $0, o; o += length($0) + 1} END {printf "__END__\t%d\n", o}')
SUSED=$(printf '%s\n' "$STRS" | awk -F'\t' '$1 == "__END__" {print $2}')
[ "$STZ" -ge "$SUSED" ] && [ "$((STZ % 8))" = 0 ] && [ "$((STZ - SUSED))" -lt 8 ] \
    || fail "STRTAB_SIZE $STZ does not hold its $SUSED bytes as the next multiple of 8"
i=1
for name in $BINDS; do
    want=$(printf '%s\n' "$STRS" | awk -F'\t' -v n="$name" '$1 == n {print $2; exit}')
    got=$(printf '%s\n' "$STRX" | sed -n "${i}p")
    [ -n "$want" ] || fail "bound symbol $name has no strtab entry"
    [ "$got" = "$want" ] || fail "symtab undef [$((i + 1))] has strx $got but $name (bound at __got[$((i - 1))]) is at strtab offset $want — dyld would bind the wrong name"
    i=$((i + 1))
done
BUSED=$(printf '%s\n' "$BINDS" | awk '{u += length($0) + 3} END {print u + 5}')
[ "$BSZ" -ge "$BUSED" ] && [ "$((BSZ % 8))" = 0 ] && [ "$((BSZ - BUSED))" -lt 8 ] \
    || fail "BIND_SIZE $BSZ does not hold its $BUSED bytes of bind opcodes as the next multiple of 8"
INDV=$(printf '%s\n' "$MW" | awk '/# indirect symtab/ {s = 1; next} s && /Pad to FILE_END/ {exit} s' \
    | grep -oE '_macho_w32\(O, o, [0-9]+\)' | grep -oE '[0-9]+\)' | tr -d ')' | tr '\n' ' ')
WANT=$(i=0; while [ "$i" -lt "$NB" ]; do printf '%s ' "$((i + 2))"; i=$((i + 1)); done)
[ "$INDV" = "$WANT" ] || fail "the indirect symtab is '$INDV', expected '$WANT' (__got[i] → symtab[2+i])"

# ── axis 4: return-0 stubs in every other backend ─────────────────────────────────────────────
for f in src/backend/x86/emit.cyr src/backend/cx/emit.cyr; do
    grep -qE '^fn EMACHO_FORK_ARM\(S\): i64 \{ return 0; \}' "$ROOT/$f" \
        || fail "$f has no return-0 EMACHO_FORK_ARM stub — the non-aarch64 forks will not link"
done

# ── axis 5: 1701 is registered as routed ──────────────────────────────────────────────────────
_body "$AE" _macho_arm_routes | grep -c 'if (n == 1701) { return 1; }' >/dev/null \
    || fail "_macho_arm_routes does not claim 1701 — every sys_fork would warn 'syscall not routed'"

# ── axis 6: the stdlib spells it on arm64 macOS only ──────────────────────────────────────────
SF=$(_body "$SA" sys_fork)
[ -n "$SF" ] || fail "sys_fork missing from lib/syscalls_aarch64_linux.cyr"
printf '%s\n' "$SF" | awk '/#ifdef CYRIUS_TARGET_MACOS/ {m = 1; next} /#else/ {m = 2; next} /#endif/ {m = 0}
    m == 1 && /return syscall\(1701\);/ {a = 1} m == 2 && /return syscall\(SYS_CLONE, SIGCHLD/ {b = 1}
    END {exit !(a && b)}' \
    || fail "sys_fork must be '#ifdef CYRIUS_TARGET_MACOS / return syscall(1701); / #else / return syscall(SYS_CLONE, SIGCHLD, ...)'"
if grep -v '^[[:space:]]*#' "$SM" | grep -c 'syscall(1701' >/dev/null; then
    fail "lib/syscalls_macos.cyr (x86 macOS) spells 1701 — its static Mach-O has no __got, so that is SIGSYS"
fi

# ── axis 7: sxtw before the compare; -errno; the branch skips exactly the errno path ──────────
_line() { printf '%s\n' "$FB" | grep -n "$1" | head -1 | cut -d: -f1; }
LB1=$(printf '%s\n' "$FB" | grep -n '_EMACHO_BLR_GOT' | head -1 | cut -d: -f1)
LSX=$(_line '0x93407C00'); LCMP=$(_line '0xB100041F'); LBNE=$(_line '0x540000')
LLD=$(_line '0xB9800000'); LNEG=$(_line '0xCB0003E0')
[ -n "$LSX" ] || fail "EMACHO_FORK_ARM has no sxtw x0, w0 (0x93407C00) — pid_t's upper 32 bits are unspecified"
[ -n "$LCMP" ] || fail "EMACHO_FORK_ARM has no cmn x0, #1 (0xB100041F)"
[ "$LB1" -lt "$LSX" ] && [ "$LSX" -lt "$LCMP" ] \
    || fail "the sxtw must come after the fork call and BEFORE the failure compare"
[ -n "$LLD" ] && [ -n "$LNEG" ] || fail "EMACHO_FORK_ARM does not return -errno (ldrsw x0, [x0] then neg x0, x0)"
[ -n "$LBNE" ] || fail "EMACHO_FORK_ARM has no b.ne over the errno path"
BNE=$(printf '%s\n' "$FB" | sed -n "${LBNE}p" | grep -oE '0x540000[0-9A-Fa-f]{2}')
NAFTER=$(printf '%s\n' "$FB" | sed -n "$((LBNE + 1)),\$p" | awk '/_EMACHO_BLR_GOT\(/ {n += 3} /EW\(S, 0x/ {n += 1} END {print n}')
WANTBNE=$(printf '0x%08X' $((0x54000001 | ((NAFTER + 1) << 5))))
[ "$(printf '0x%08X' "$BNE")" = "$WANTBNE" ] \
    || fail "the b.ne is $BNE but $NAFTER instructions follow it, so it should be $WANTBNE"

echo "PASS macos_arm64_libsystem_fork (1701 -> __got[$S_FORK] _fork + __got[$S_ERR] ___error; $NB-import tables consistent; arm64-Mach-O-guarded at argc 1; stubbed in every fork; sxtw + -errno)"
