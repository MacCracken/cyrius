#!/bin/sh
# esysxlat_fold.sh — 6.6.18: aarch64 folds a LITERAL syscall number's ESYSXLAT chain at compile
# time (src/backend/aarch64/emit.cyr `_esx_fold`, XLAT-1) and sends a VARIABLE number through
# one shared per-class stub (`_esx_stub_site` / `ESYSX_STUBS`, XLAT-2).
#
# Before 6.6.18 every `syscall(N, …)` site carried the whole x86->aarch64 translation chain
# inline — 82 rows, 1,184 B on ELF — 36 % of the native compiler (2,042,184 B -> 1,321,856 B
# folded). The fold emits the chain, then decodes and SIMULATES it in emission order with
# cur = N, keeping only the bodies that would run; every ordering rule in the chain holds by
# construction because the chain's own order is what runs.
#
#   axis 1  STRUCTURAL (fails on the old code): a probe whose numbers are all literals, one per
#           row SHAPE (pure renumber, the arg-shift rows, the insert-zero rows, poll's ms->timespec
#           block, the re-capture pairs 263/35/137/161, the 1049 alias, a native pass-through),
#           cross-built for ELF-aarch64, carries ZERO `cmp x8,#imm` words. Old: 82 per site.
#   axis 2  SEMANTIC: the same calls issued through a `var` number (the runtime chain) must make
#           the identical syscalls — every `qemu-aarch64 -strace` line equals its literal twin.
#           Harmless arguments only (paths under a parent that does not exist, fd -1, a zero
#           timespec). Skipped BY NAME when qemu-aarch64 is absent.
#   axis 3  Mach-O (CYRIUS_MACHO_ARM=1): the chain head `movz x16,#0xFFFF` survives only at a
#           literal site NO row routes — two unrouted numbers, pipe 59 at argc 1 (`_esx_short`)
#           and nanosleep 35 at argc 2 (EMACHO_NANOSLEEP_ARM is argc-3 only) — so exactly 4
#           heads among 9 sites. Old code: one head per site. (read 0 / write 1 are NOT used: on
#           arm64 Mach-O they are parse-time __got reroutes, never an ESCPOPS site.)
#   axis 4  XLAT-2 (fails on the old code): the twin probe's variable-number sites share ONE
#           chain — its `cmp x8` count equals ESYSXLAT's ELF row count, derived from the source
#           (old: one chain per site). Every aarch64 driver calls ESYSX_STUBS between EEXIT and
#           FIXUP, FIXUP asserts the site list drained, and a driver mutant WITHOUT the call is
#           refused at FIXUP instead of shipping `bl .` — an infinite loop (critic #8).
#   axis 5  a `#naked` fn keeps its own inline chain (x30 is its live return address): two
#           chains in the probe, and it returns correctly under qemu.
#   axis 6  arm64 Mach-O: variable numbers at arities 1, 2, 2, 3 share 3 class stubs (3 heads;
#           the chain depends on _esx_argc). Old code: 4.
#   axis 7  a CHAINED row (6.7.9): `_esx_fold` sets cur = d after a body's `movz x8,#d` so a LATER
#           row can match the renumbered value, and the shipped chain never reaches that update
#           (esysxlat_row_order.sh keeps it free of live re-captures). A cross compiler built from a
#           copy of the emitter with two synthetic ELF rows appended at the chain's end, 4000 -> 4001
#           then 4001 -> 4002 (numbers no shipped row compares), must fold `syscall(4000)` to
#           `movz x8,#4002` at its svc, carry both rows in the shared stub, and, under
#           `qemu-aarch64 -strace`, make the same call as its `var` twin. The qemu leg is skipped
#           BY NAME when qemu-aarch64 is absent.
#   axis 8  XLAT-3 (6.7.12, fails on the old code): at an arm64 Mach-O LITERAL site the folded x16
#           is a compile-time fact, so ESYSCALL's run-time pipe / fork fixups go where they cannot
#           fire. Axis 3's all-literal probe carries ZERO `cmp x16,#42` (f100aa1f) and ZERO
#           `cmp x16,#2` (f1000a1f) words (old: 18 and 9); a clone 220 site keeps only the fork
#           half (one cmp x16,#2, right after its csneg); a pipe2 59 site at argc 2 keeps only the
#           pipe halves (the stash before its svc, the store right after its csneg). Axis 6's
#           variable-number sites and a `#naked` inline chain keep both (x16 is a run-time value).
#
# MUTATION LEDGER (measured 6.6.18, outside the gate; (c) re-measured 6.7.9):
#   (a) bypass the fold (ESYSXLAT without _esx_fold for a literal)  -> axis 1 FAILS (1,804 cmp x8 words)
#   (b) keep only each kept body's LAST word                          -> axis 2 FAILS: ppoll gets a NULL
#                                                                         timeout and blocks (qemu bounded
#                                                                         at 30 s, the marker never runs)
#   (c) never update cur after a movz x8                              -> axis 7 FAILS: syscall(4000) folds
#                                                                         to movz x8,#4001 (the 4001 -> 4002
#                                                                         row is dropped). Axes 1-6 still pass
#                                                                         it: no shipped row's output is a
#                                                                         LATER row's source. With axis 7's
#                                                                         fold check removed, its qemu twin
#                                                                         fails it too (4001 against the
#                                                                         twin's 4002). A fold that stops at
#                                                                         the first matching row: the same.
#   (d) an ADR word placed in a row body (critic #7)                  -> every aarch64 build stops:
#       "error: internal: ESYSXLAT fold refused chain word 6 (the row cmp x8,#2): ADR/ADRP in a row body"
#   (e) drop the `#naked` carve-out in _esx_stub_site                 -> axis 5 FAILS (82 cmp x8 words,
#                                                                         want 164)
#   (f) per-site chains (XLAT-2 reverted)                             -> axis 4 FAILS (1,804 for 22 sites)
#   (g) the fold never records x16 (_esx_lit_x16 stays -1; measured 6.7.12) -> axis 8 FAILS (18 cmp
#                                                                         x16,#42 words in axis 3's probe)
#   (h) ESCPOPS never resets x16 (neither before the fold nor after
#       its ESYSCALL; measured 6.7.12)                                -> axis 8 FAILS: the variable and
#                                                                         #naked sites after a literal
#                                                                         inherit its x16 and lose their
#                                                                         fixups (0 and 0, want 4 and 2)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail() { echo "FAIL esysxlat_fold: $1" >&2; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL esysxlat_fold: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT

rc=0; (cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$T/cca" 2> "$T/cca.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cca" ] || fail "cross-building cycc_aarch64 from src failed (rc $rc): $(head -3 "$T/cca.err")"
chmod +x "$T/cca"

# words of a binary, one lower-case hex word per line
_words() { od -An -v -tx4 "$1" | tr -s ' ' '\n' | grep -v '^$' || true; }
# `cmp x8,#imm` (0xF100011F | imm<<10, sh = 0)
_ncmp8() { _words "$1" | grep -cE '^f1[0-3][0-9a-f][0-9a-f][159d]1f$' || true; }

# number | arguments — one row per chain SHAPE
ROWS='0|0 - 1, &_fb, 0
1|0 - 1, &_fb, 0
3|0 - 1
2|_fp, 0, 0
4|_fp, &_fb
6|_fp, &_fb
82|_fp, _fq
88|_fp, _fq
83|_fp, 0
84|_fp
87|_fp
89|_fp, &_fb, 16
22|&_fb
33|0 - 1, 0 - 1
232|0 - 1, &_fb, 1, 0
7|0, 0, 0
263|0 - 100, _fp, 0
35|&_fts, 0
137|_fp, &_fb
161|_fp
1049|_fp
172|'
NSITE=$(printf '%s\n' "$ROWS" | grep -c '|')
_hdr() {
    printf 'var _fp = "/nonexistent-cyrius-esx-fold/a";\nvar _fq = "/nonexistent-cyrius-esx-fold/b";\n'
    printf 'var _fb[256];\nvar _fts[16];\nvar _fn = 0;\n'
}
_lit() { printf '%s\n' "$ROWS" | awk -F'|' '{ if ($2 == "") print "syscall(" $1 ");"; else print "syscall(" $1 ", " $2 ");" }'; }
_var() { printf '%s\n' "$ROWS" | awk -F'|' '{ print "_fn = " $1 ";"; if ($2 == "") print "syscall(_fn);"; else print "syscall(_fn, " $2 ");" }'; }

# ── axis 1: a literal-only probe carries no chain ────────────────────────────────────────────
{ _hdr; _lit; } > "$T/lit.cyr"
rc=0; "$T/cca" < "$T/lit.cyr" > "$T/lit.bin" 2> "$T/lit.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/lit.bin" ] || fail "the literal probe did not compile (rc $rc): $(head -3 "$T/lit.err")"
NSVC=$(_words "$T/lit.bin" | grep -c '^d4000001$' || true)
[ "$NSVC" -ge "$NSITE" ] || fail "the literal probe holds $NSVC svc #0 words for $NSITE sites — the reader is blind"
N1=$(_ncmp8 "$T/lit.bin")
[ "$N1" = 0 ] || fail "$N1 cmp x8,#imm words in a probe whose $NSITE syscall numbers are all literals — the ESYSXLAT chain was not folded"
echo "  axis 1: $NSITE literal sites, $NSVC svc, 0 cmp x8,#imm"

# ── the twin probe: the literal block, a gettid marker, then the same calls through a `var` ──
{ _hdr; _lit; echo 'syscall(178);'; _var; } > "$T/twin.cyr"
rc=0; "$T/cca" < "$T/twin.cyr" > "$T/twin.bin" 2> "$T/twin.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/twin.bin" ] || fail "the twin probe did not compile (rc $rc): $(head -3 "$T/twin.err")"
chmod +x "$T/twin.bin"

# ── axis 4: the variable-number sites share ONE chain (XLAT-2) ───────────────────────────────
# The ELF row count is derived from the emitter source the way raw_syscall_literals_routed.sh
# derives it (`cmp x8,#N` words inside ESYSXLAT's body), so a new row moves both sides.
# ESRC: each ELF row's source number, one per line, in emission order (axis 7 reads it too).
ESRC=$(awk '/^fn ESYSXLAT\(/{on=1} on && /^fn / && !/^fn ESYSXLAT\(/{on=0} on' "$ROOT/src/backend/aarch64/emit.cyr" \
    | grep -o 'EW(S, 0xF1[0-9A-Fa-f]\{6\})' | sed 's/EW(S, //; s/)//' \
    | awk '{ w = strtonum($1); if (and(w, 0xFFC003FF) == 0xF100011F) print rshift(and(w, 0x3FFC00), 10) }')
NROWS=$(printf '%s\n' "$ESRC" | grep -c . || true)
[ "$NROWS" -ge 40 ] || fail "decoded only $NROWS ELF rows from ESYSXLAT — the reader or the emitter shape moved"
N4=$(_ncmp8 "$T/twin.bin")
[ "$N4" = "$NROWS" ] || fail "$N4 cmp x8,#imm words for $NSITE variable-number sites — want exactly one shared chain ($NROWS rows), not one per site"
for d in main_aarch64 main_aarch64_native main_aarch64_macho; do
    awk '/^EEXIT\(S\);/ {e = NR} /^ESYSX_STUBS\(S\);/ {s = NR} /^FIXUP\(S\);/ {f = NR} END {exit !(e && s && f && e < s && s < f)}' \
        "$ROOT/src/$d.cyr" || fail "src/$d.cyr does not call ESYSX_STUBS(S) between EEXIT(S) and FIXUP(S)"
done
awk -v n="fn FIXUP(" 'index($0, n) == 1 {s = 1} s && /_esx_stubs_drained\(\)/ {f = 1} s && /^}/ {exit} END {exit !f}' \
    "$ROOT/src/backend/aarch64/fixup.cyr" || fail "aarch64 FIXUP does not assert the stub-site list is drained (_esx_stubs_drained)"
# behavioural (critic #8): a driver that skips ESYSX_STUBS must stop at FIXUP, not ship `bl .`
sed '/^ESYSX_STUBS(S);$/d' "$ROOT/src/main_aarch64.cyr" > "$T/nostub.cyr"
[ "$(wc -l < "$T/nostub.cyr")" -lt "$(wc -l < "$ROOT/src/main_aarch64.cyr")" ] || fail "could not build the no-stub driver mutant"
rc=0; (cd "$ROOT" && "$CC" < "$T/nostub.cyr" > "$T/ccm" 2> "$T/ccm.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/ccm" ] || fail "cross-building the no-stub driver mutant failed (rc $rc)"
chmod +x "$T/ccm"
rc=0; "$T/ccm" < "$T/twin.cyr" > "$T/nostub.bin" 2> "$T/nostub.err" || rc=$?
[ "$rc" != 0 ] && grep -q 'reached FIXUP unpatched' "$T/nostub.err" \
    || fail "a driver without ESYSX_STUBS compiled variable-number sites (rc $rc) — FIXUP must refuse, or the output loops on 'bl .'"
echo "  axis 4: $NSITE variable-number sites, one shared chain ($NROWS rows); 3 drivers call ESYSX_STUBS; a driver without it is refused at FIXUP"

# ── axis 2: every literal site makes the syscall its runtime-chain twin makes ───────────────
if command -v qemu-aarch64 >/dev/null 2>&1; then
    # bounded: a wrongly-folded ppoll (NULL timeout) or nanosleep blocks for ever — mutant (b) did
    rc=0; (cd "$T" && timeout 30 qemu-aarch64 -strace ./twin.bin > /dev/null 2> "$T/st") || rc=$?
    sed 's/^[0-9]* //' "$T/st" | grep -v '^exit' > "$T/st2" || true
    MK=$(awk '/^gettid\(/ {print NR; exit}' "$T/st2")
    [ -n "$MK" ] || fail "the twin probe never reached its gettid marker (qemu rc $rc, 124 = hung 30 s) — last literal call: $(tail -1 "$T/st2")"
    head -n $((MK - 1)) "$T/st2" > "$T/sl"
    tail -n +$((MK + 1)) "$T/st2" > "$T/sv"
    NL=$(grep -c . "$T/sl" || true)
    [ "$NL" -ge "$NSITE" ] || fail "only $NL strace lines before the marker for $NSITE literal sites — the reader is blind"
    if ! cmp -s "$T/sl" "$T/sv"; then
        diff "$T/sl" "$T/sv" | head -12 >&2
        fail "a literal site made a different syscall than its runtime-chain twin (literal < > var)"
    fi
    grep -q '^openat(AT_FDCWD,"/nonexistent-cyrius-esx-fold/a"' "$T/sl" \
        || fail "open 2 did not become openat(AT_FDCWD, path, …) — the arg-shift body was lost: $(grep -m1 open "$T/sl")"
    grep -q '^ppoll(' "$T/sl" || fail "poll 7 did not become ppoll"
    echo "  axis 2: $NL strace lines, each identical to its runtime-chain twin"
else
    echo "  axis 2: SKIP (qemu-aarch64 absent) — the semantic twin check did not run"
fi

# ── axis 5: a #naked fn keeps its own inline chain (x30 is its live return address) ──────────
printf '%s\n' 'var _fn = 0;' 'var _nk = 0;' 'var _o = 0;' '#naked' 'fn _nk_call() {' '    _nk = syscall(_fn);' \
    '    asm { 0xC0; 0x03; 0x5F; 0xD6; }' '}' '_fn = 172;' '_o = syscall(_fn);' '_nk_call();' \
    'if (_nk == _o) { syscall(60, 42); }' 'syscall(60, 7);' > "$T/nk.cyr"
rc=0; "$T/cca" < "$T/nk.cyr" > "$T/nk.bin" 2> "$T/nk.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/nk.bin" ] || fail "the #naked probe did not compile (rc $rc): $(head -3 "$T/nk.err")"
N5=$(_ncmp8 "$T/nk.bin")
[ "$N5" = $((2 * NROWS)) ] || fail "$N5 cmp x8,#imm words in the #naked probe — want $((2 * NROWS)): the shared stub plus the #naked fn's own inline chain"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    chmod +x "$T/nk.bin"
    rc=0; (cd "$T" && timeout 30 qemu-aarch64 ./nk.bin > /dev/null 2>&1) || rc=$?
    [ "$rc" = 42 ] || fail "the #naked probe exited $rc (want 42; 124 = hung) — its variable-number syscall lost x30 or its result"
    echo "  axis 5: #naked keeps its inline chain (2 chains) and returns under qemu"
else
    echo "  axis 5: 2 chains (the qemu run of the #naked probe SKIPPED: qemu-aarch64 absent)"
fi

# ── axis 3: Mach-O keeps the chain head only where no row routes ─────────────────────────────
printf 'var _fb[64];\nvar _fts[16];\n%s\n' \
'syscall(39);
syscall(4, &_fb, &_fb);
syscall(3, 0 - 1);
syscall(82, &_fb, &_fb);
syscall(500, 0);
syscall(501, 0);
syscall(59);
syscall(35, &_fts, 0);
syscall(35, &_fts);' > "$T/mo.cyr"
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/mo.cyr" > "$T/mo.bin" 2> "$T/mo.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/mo.bin" ] || fail "the Mach-O probe did not compile (rc $rc): $(head -3 "$T/mo.err")"
NSV80=$(_words "$T/mo.bin" | grep -c '^d4001001$' || true)
[ "$NSV80" -ge 9 ] || fail "the Mach-O probe holds $NSV80 svc #0x80 words for 9 sites — the reader is blind"
NHEAD=$(_words "$T/mo.bin" | grep -c '^d29ffff0$' || true)
[ "$NHEAD" = 4 ] || fail "$NHEAD chain heads (movz x16,#0xFFFF) for 9 literal Mach-O sites, 4 of them unrouted — want exactly 4"
N3=$(_ncmp8 "$T/mo.bin")
[ "$N3" = 0 ] || fail "$N3 cmp x8,#imm words left in the all-literal Mach-O probe"
_words "$T/mo.bin" | grep -c '^d2800290$' > /dev/null || fail "getpid 39 lost its Darwin route (movz x16,#20)"
echo "  axis 3: Mach-O 9 literal sites, $NHEAD heads (the 4 unrouted), 0 cmp x8,#imm"

# ── axis 6: Mach-O variable numbers share one stub PER ARITY (the chain reads _esx_argc) ────
printf '%s\n' 'var _fn = 0;' 'var _fb[64];' '_fn = 20; syscall(_fn);' '_fn = 6; syscall(_fn, 0 - 1);' \
    '_fn = 92; syscall(_fn, 0 - 1);' '_fn = 188; syscall(_fn, &_fb, &_fb);' > "$T/mv.cyr"
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/mv.cyr" > "$T/mv.bin" 2> "$T/mv.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/mv.bin" ] || fail "the Mach-O variable-number probe did not compile (rc $rc): $(head -3 "$T/mv.err")"
NH6=$(_words "$T/mv.bin" | grep -c '^d29ffff0$' || true)
[ "$NH6" = 3 ] || fail "$NH6 chain heads for 4 variable-number Mach-O sites at arities 1, 2, 2, 3 — want 3 (one stub per arity class)"
_words "$T/mv.bin" | grep -c '^d65f03c0$' > /dev/null || fail "no ret in the Mach-O probe — the class stubs are missing"
echo "  axis 6: Mach-O 4 variable-number sites at 3 arities -> $NH6 class stubs"

# ── axis 7: a chained row — one row's movz x8 output is a LATER row's source ────────────────
# _esx_fold's `cur = d` update is what lets a literal match a second row after the first one
# renumbered it. Nothing above reaches it: the shipped chain holds no live re-capture. So build a
# cross compiler whose ESYSXLAT ends with two synthetic ELF rows, 4000 -> 4001 then 4001 -> 4002,
# in the chain's own shape (cmp x8,#src / b.ne +8 / movz x8,#dst; cmp takes a 12-bit immediate).
# The emitter copy is spliced into a copy of the driver in place of its include, and the build
# runs from $ROOT, so every other file is the live tree's. Words: _esx_arm's formulas with
# Rd = x8 for the movz, checked with llvm-mc (cmp x8,#4000 = F13E811F, movz x8,#4001 = D281F428,
# movz x8,#4002 = D281F448).
for s in 4000 4001 4002; do
    if printf '%s\n' "$ESRC" | grep -qx "$s"; then
        fail "a shipped ESYSXLAT row already compares x8 with #$s — axis 7 needs three numbers no row uses"
    fi
done
_cmp8w() { printf '0x%08X' $((0xF100011F | ($1 << 10))); }
_movz8w() { printf '0x%08X' $((0xD2800008 | ($1 << 5))); }
EMIT="$ROOT/src/backend/aarch64/emit.cyr"
EE=$(awk '/^fn ESYSXLAT\(/{on=1} on && /^}/{print NR; exit}' "$EMIT")
[ -n "$EE" ] && [ "$(sed -n "$((EE - 1))p" "$EMIT")" = '    return 0;' ] \
    || fail "ESYSXLAT no longer ends in '    return 0;' then '}' — axis 7 cannot append its rows before the return"
R1="    EW(S, $(_cmp8w 4000)); EW(S, 0x54000041); EW(S, $(_movz8w 4001));  # axis 7: 4000 -> 4001"
R2="    EW(S, $(_cmp8w 4001)); EW(S, 0x54000041); EW(S, $(_movz8w 4002));  # axis 7: 4001 -> 4002"
awk -v n=$((EE - 1)) -v r1="$R1" -v r2="$R2" 'NR == n { print r1; print r2 } { print }' "$EMIT" > "$T/emit7.cyr"
awk -v f="$T/emit7.cyr" '$0 == "include \"src/backend/aarch64/emit.cyr\"" { while ((getline l < f) > 0) print l; n++; next }
    { print } END { exit (n != 1) }' "$ROOT/src/main_aarch64.cyr" > "$T/d7.cyr" \
    || fail "src/main_aarch64.cyr does not include src/backend/aarch64/emit.cyr exactly once — axis 7 cannot splice its copy"
rc=0; (cd "$ROOT" && "$CC" < "$T/d7.cyr" > "$T/cc7" 2> "$T/cc7.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cc7" ] || fail "cross-building the synthetic-row compiler failed (rc $rc): $(head -3 "$T/cc7.err")"
chmod +x "$T/cc7"
W4002=$(_movz8w 4002 | sed 's/^0x//' | tr 'A-F' 'a-f')
# the fold check: a one-literal probe, no chain left, and x8 = 4002 at the svc
printf 'syscall(4000);\n' > "$T/l7.cyr"
rc=0; "$T/cc7" < "$T/l7.cyr" > "$T/l7.bin" 2> "$T/l7.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/l7.bin" ] || fail "the chained-row literal probe did not compile (rc $rc): $(head -3 "$T/l7.err")"
N7=$(_ncmp8 "$T/l7.bin")
[ "$N7" = 0 ] || fail "$N7 cmp x8,#imm words in a probe whose one syscall number is the literal 4000 — the chain was not folded"
X7=$(_words "$T/l7.bin" | awk -v m="$W4002" 'p == m && $0 == "d4000001" {n++} {p = $0} END {print n + 0}')
[ "$X7" = 1 ] || fail "syscall(4000) did not fold to movz x8,#4002 at its svc (words before each svc: $(_words "$T/l7.bin" | awk '$0 == "d4000001" {printf "%s ", p} {p = $0}')) — the 4000 -> 4001 row's output is the 4001 -> 4002 row's source, so _esx_fold must set cur = 4001 after the first body"
# the stub and qemu checks: the literal, a gettid marker, then the same number through a `var` (the shared stub)
printf '%s\n' 'var _fn = 0;' 'syscall(4000);' 'syscall(178);' '_fn = 4000;' 'syscall(_fn);' > "$T/t7.cyr"
rc=0; "$T/cc7" < "$T/t7.cyr" > "$T/t7.bin" 2> "$T/t7.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/t7.bin" ] || fail "the chained-row twin probe did not compile (rc $rc): $(head -3 "$T/t7.err")"
N7T=$(_ncmp8 "$T/t7.bin")
[ "$N7T" = $((NROWS + 2)) ] || fail "$N7T cmp x8,#imm words in the chained-row twin probe — want $((NROWS + 2)): the shared stub with the 2 synthetic rows"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    chmod +x "$T/t7.bin"
    rc=0; (cd "$T" && timeout 30 qemu-aarch64 -strace ./t7.bin > /dev/null 2> "$T/st7") || rc=$?
    sed 's/^[0-9]* //' "$T/st7" | grep -v '^exit' > "$T/st7b" || true
    MK7=$(awk '/^gettid\(/ {print NR; exit}' "$T/st7b")
    [ -n "$MK7" ] || fail "the chained-row twin never reached its gettid marker (qemu rc $rc, 124 = hung 30 s)"
    [ "$MK7" = 2 ] || fail "the literal syscall(4000) made $((MK7 - 1)) strace lines before the marker, want 1"
    L7=$(head -n 1 "$T/st7b")
    V7=$(tail -n +3 "$T/st7b")
    [ "$L7" = "$V7" ] || fail "the literal 4000 made '$L7' and its runtime-chain twin '$V7' — the fold and the chain disagree on a chained row"
    printf '%s\n' "$L7" | grep -qw 4002 || fail "the literal 4000 reached the kernel as '$L7', not syscall 4002"
    echo "  axis 7: synthetic rows 4000 -> 4001 -> 4002: the literal folds to movz x8,#4002, the stub carries $N7T rows, and qemu sees '$L7' from both"
else
    echo "  axis 7: synthetic rows 4000 -> 4001 -> 4002: the literal folds to movz x8,#4002 (the qemu twin SKIPPED: qemu-aarch64 absent)"
fi

# ── axis 8: XLAT-3 — a literal Mach-O site carries only the fixups its folded x16 can need ──
_n42() { _words "$1" | grep -c '^f100aa1f$' || true; }
_n2() { _words "$1" | grep -c '^f1000a1f$' || true; }
# the word right after each `csneg x0,x0,x0,cc` (da803400), space-separated
_aftercs() { _words "$1" | awk 'p == "da803400" {printf "%s ", $0} {p = $0}'; }
A42=$(_n42 "$T/mo.bin"); A2=$(_n2 "$T/mo.bin")
[ "$A42" = 0 ] && [ "$A2" = 0 ] || fail "axis 8: the 9-site all-literal Mach-O probe (no 220, no 59 at argc >= 2) carries $A42 cmp x16,#42 and $A2 cmp x16,#2 words — want 0 and 0: a folded x16 that is neither 42 nor 2 needs no pipe / fork fixup"
printf 'syscall(220, 17, 0, 0, 0, 0);\nsyscall(39);\n' > "$T/mf.cyr"
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/mf.cyr" > "$T/mf.bin" 2> "$T/mf.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/mf.bin" ] || fail "axis 8: the clone-220 probe did not compile (rc $rc): $(head -3 "$T/mf.err")"
[ "$(_n2 "$T/mf.bin")" = 1 ] && [ "$(_n42 "$T/mf.bin")" = 0 ] || fail "axis 8: a literal clone 220 (-> fork 2) site plus a getpid site carry $(_n2 "$T/mf.bin") cmp x16,#2 and $(_n42 "$T/mf.bin") cmp x16,#42 — want 1 and 0 (the fork half only)"
case "$(_aftercs "$T/mf.bin")" in "f1000a1f "*) ;; *) fail "axis 8: the fork half does not follow the clone-220 site's csneg (words after each csneg: $(_aftercs "$T/mf.bin"))" ;; esac
printf 'var _fb[16];\nsyscall(59, &_fb, 0);\nsyscall(39);\n' > "$T/mp.cyr"
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/mp.cyr" > "$T/mp.bin" 2> "$T/mp.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/mp.bin" ] || fail "axis 8: the pipe2-59 probe did not compile (rc $rc): $(head -3 "$T/mp.err")"
[ "$(_n42 "$T/mp.bin")" = 2 ] && [ "$(_n2 "$T/mp.bin")" = 0 ] || fail "axis 8: a literal pipe2 59 (-> pipe 42, argc 2) site plus a getpid site carry $(_n42 "$T/mp.bin") cmp x16,#42 and $(_n2 "$T/mp.bin") cmp x16,#2 — want 2 and 0 (the pipe stash and store only)"
_words "$T/mp.bin" | awk 'p2 == "f100aa1f" && p1 == "54000041" && $0 == "f81f0fe0" {f = 1} {p2 = p1; p1 = $0} END {exit !f}' \
    || fail "axis 8: the pipe2-59 site lost its pre-svc stash (cmp x16,#42 / b.ne / str x0,[sp,#-16]!)"
case "$(_aftercs "$T/mp.bin")" in "f100aa1f "*) ;; *) fail "axis 8: the pipe store does not follow the pipe2-59 site's csneg (words after each csneg: $(_aftercs "$T/mp.bin"))" ;; esac
V42=$(_n42 "$T/mv.bin"); V2=$(_n2 "$T/mv.bin")
[ "$V42" = 8 ] && [ "$V2" = 4 ] || fail "axis 8: axis 6's 4 variable-number Mach-O sites carry $V42 cmp x16,#42 and $V2 cmp x16,#2 — want 8 and 4 (x16 is a run-time value there: both fixups at every site)"
# a literal site, then a variable site and a #naked inline-chain site emitted AFTER it: the
# literal's x16 must not leak into either
printf '%s\n' 'var _fn = 0;' 'syscall(39);' '_fn = 20;' 'syscall(_fn);' '#naked' 'fn _nk_call() {' '    syscall(_fn);' \
    '    asm { 0xC0; 0x03; 0x5F; 0xD6; }' '}' '_nk_call();' > "$T/mn.cyr"
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/mn.cyr" > "$T/mn.bin" 2> "$T/mn.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/mn.bin" ] || fail "axis 8: the Mach-O #naked probe did not compile (rc $rc): $(head -3 "$T/mn.err")"
[ "$(_n42 "$T/mn.bin")" = 4 ] && [ "$(_n2 "$T/mn.bin")" = 2 ] || fail "axis 8: a variable site and a #naked inline-chain site after a literal site carry $(_n42 "$T/mn.bin") cmp x16,#42 and $(_n2 "$T/mn.bin") cmp x16,#2 — want 4 and 2 (both fixups at each; the literal's x16 must not leak into them)"
echo "  axis 8: Mach-O literal sites keep only the fixups their folded x16 needs (0 in axis 3's probe; fork half at 220, pipe halves at 59/argc 2); variable and #naked sites keep both"

echo "PASS esysxlat_fold (literal syscall numbers carry no ESYSXLAT chain on ELF-aarch64 or arm64 Mach-O and match their runtime twins; a chained row folds through both renumbers; variable numbers share one stub per class; #naked keeps its inline chain; a literal Mach-O site carries only the pipe / fork fixups its x16 can need)"
