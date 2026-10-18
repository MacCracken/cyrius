#!/bin/sh
# native_region_literal_warns.sh — 6.7.12: a raw syscall literal inside a native-aarch64 region
# that an ESYSXLAT x86-compat row RENUMBERS is warned at compile time, and still translated.
# 6.7.14: the region carries through `include`, and a constant DECLARED inside one is judged too.
# 6.7.15 (D39): a constant declared in a file outside lib/ is judged by the region carried into it;
# a fn-local const is judged too.
#
# THE DEFECT (filed 2026-10-08, docs/development/issues/2026-10-08-aarch64-native-region-literal-
# translated-silently.md). In a region compiled only for aarch64 (`#ifdef CYRIUS_ARCH_AARCH64`,
# `#ifplat aarch64`, `#ifndef CYRIUS_ARCH_X86`) a raw number reads as the native one — 6.6.12
# silences the "this is x86 <name>" warning there for that reason — but the chain matches NUMBERS:
# `syscall(9, …)` meant as lgetxattr is renumbered to mmap (9 → 222) and `syscall(39, …)` meant as
# umount2 returns a PID (39 → 172 getpid). No warning, a clean build, the wrong call.
#
# THE DECISION (6.7.12's D1, the user, 2026-10-15): WARN ONLY — the literal is still translated, so no
# program changes behaviour. The warning names the number it becomes, what that runs, and the
# spelling that reaches the native call: `1000+N` when the private band has a row for it (derived
# by running the same chain with 1000+N), else that no alias exists.
#
# WHAT IS JUDGED (src/backend/aarch64/emit.cyr `_esx_native_warn`), the number spelled as ONE token:
#   · an integer literal inside a native-aarch64 region at the call. ⛔ 6.7.14 (D61, the user,
#     2026-10-16: "Yes: the region carries through include") — a region in an includer carries
#     into the files it includes, the rule PP_A64_NATIVE_AT gives the 6.6.12 x86-name check, so a
#     per-arch file included under the guard and written with native numbers is warned (6.7.12
#     judged only a region opened in the call's own file, and that file's `syscall(9, …)` ran mmap
#     silently: issues/2026-10-15-native-region-warning-misses-included-files-and-author-
#     constants.md). The stdlib's shared syscall files, inside lib/syscalls.cyr's aarch64 region,
#     spell their deliberate x86 numbers through `SYS_*` names (fd_wait_ready's SYS_POLL,
#     sys_epoll_wait's SYS_EPOLL_WAIT — raw literals until 6.7.14), so they stay silent;
#   · ⛔ 6.7.14 — an enum constant or a top-level const (bare, or `Enum.NAME`) DECLARED inside a
#     region: the author's own native number (`NR_UMOUNT2 = 39` under the guard ran getpid
#     silently). ⛔ 6.7.15 (D39, the user, 2026-10-18: "Yes, for files outside lib/") — in a file
#     outside lib/ the region carries through include, so a per-arch file included under the
#     guard is judged at its top level too (issues/2026-10-16-native-region-warning-skips-top-
#     level-constant-in-included-per-arch-file.md); in a file under lib/ (a leading `lib/` or a
#     `/lib/` component — the stdlib, a project's vendored deps) only a region opened in that
#     file counts: the stdlib's own constants renumber BY DESIGN (SYS_FSYNC = 74 → 82) and sit at
#     their peer file's top level. A constant declared OUTSIDE a region and used inside one is
#     not judged;
#   · ⛔ 6.7.15 — a fn-local const, by the same rule, judged where its name token sits
#     (issues/2026-10-16-native-region-warning-skips-fn-local-const.md): an `#inline` fn's const
#     by the inline body's declaration, never the call site.
#
#   axis 1  the 6.7.12 filed repro VERBATIM: one warning naming 9 → 222 (mmap) and 1009 for native
#           lgetxattr; under qemu-aarch64 it still exits 22 (mmap ran: warn only)
#   axis 2  the 1009 control: silent, exits 0 under qemu (native lgetxattr → -ENOENT)
#   axis 3  syscall(39) in a region names 172 (getpid) and 1039 for native umount2
#   axis 4  the same literal OUTSIDE a region prints no new warning
#   axis 5  a region literal with no ELF row (134, a pass-through) stays silent
#   axis 6  no alias: raw 1 in a region says no 1000+N alias exists for native io_destroy
#   axis 7  constants and includes: an enum constant declared OUTSIDE a region and used inside
#           stays silent; one declared INSIDE warns, bare and as `Enum.NAME`, and so does a
#           top-level const; a file included from inside a region IS judged by it (its raw 9
#           warns, naming the included file), and a region in the includer after that include
#           still warns (the file stack resumes); a constant declared at the top level of a lib/
#           file included from inside a region stays silent (the stdlib peers' shape)
#   axis 8  warn only: the repro's binary is byte-identical to the same source with its region
#           lines blanked (the warning changes nothing that is emitted)
#   axis 9  a stdlib hello (syscalls + alloc + io) builds for aarch64 with zero of these warnings
#           (syscall_xlat_generated.sh axes 2/7/8 hold the CLI and cycc's own aarch64 source to
#           zero `raw syscall` warnings, which covers this text too)
#   axis 10 every lib/*.cyr that builds on its own builds for aarch64 with zero of these warnings
#           (floor 85 files: a sweep that compiles nothing is not a sweep)
#   axis 11 the 6.7.14 filed repro VERBATIM (src/arch_aarch64.cyr included under the guard, an
#           enum constant declared in the region): two warnings, 9 → 222 in the included file and
#           NR_UMOUNT2 = 39 → 172; its binary is byte-identical to the region-free twin's and
#           under qemu it still exits 1 (warn only)
#   axis 12 the 6.7.15 fn-local const repro VERBATIM: one warning naming NR_UMOUNT2 = 39 → 172
#           on line 5, the binary byte-identical to the region-free twin's, still exits 1 under
#           qemu; a local const declared outside a region and used inside stays silent; an
#           `#inline` fn's local const declared in a region of its file warns there (inc/inl.cyr)
#           as often as its literal twin (the definition and each replay, called from outside
#           any region) and emits what the twin does; one declared outside, called from inside a
#           region, stays silent; D39's rule: a per-arch file outside lib/ warns, under lib/ not
#   axis 13 the 6.7.15 filed repro VERBATIM (D39: an enum constant at the top level of
#           src/arch_aarch64.cyr, included under the guard): one warning naming NR_UMOUNT2 = 39
#           → 172 at the per-arch file's line 2, the binary byte-identical to the region-free
#           twin's, still exits 2 under qemu; the same file under lib/, under vendor/lib/ and read
#           through the store-slot fallback (a throwaway CYRIUS_HOME) stays silent; a constant a
#           lib/ file declares inside a region of its OWN still warns (lib/ keeps the file-local
#           rule)
#
# MUTATION LEDGER (measured on the emitter, restored after each; the gate stops at its first red
# axis, so a later one is measured separately):
#   (a) no warning (`_esx_native_warn` returns at entry)          -> axis 1 FAILS (0 warnings)
#   (b) 6.7.14: the call-site region test file-local again
#       (`_esx_region_at` answers `_esx_rg_local`)                   -> axis 7 FAILS (inc/arm.cyr
#                                                                      not warned); axis 11 too
#   (c) 6.7.14: a constant judged where it is USED (the call-site
#       region) instead of where it was declared                    -> axis 7 FAILS (the enum
#                                                                      declared outside warned)
#   (d) the alias derived as "1000+N fits the cmp" instead of by
#       running the chain                                           -> axis 6 FAILS (write 1001)
#   (e) 6.7.14: a name never judged (`_esx_raw_lit_call` answers -1
#       for a name)                                                 -> axis 7 FAILS (the enum
#                                                                      declared inside silent)
#   (f) 6.7.15: the INHERITED region for lib/ files too
#       (`_esx_rg_decl` skips its `_esx_rg_in_lib` test)            -> axis 7 FAILS (lib/peer.cyr's
#                                                                      top-level constant warned);
#                                                                      axis 9 too: the peers'
#                                                                      SYS_* warn
#   (f2) 6.7.15: the file-local rule everywhere again
#       (`_esx_rg_decl` answers `_esx_rg_local`, 6.7.14's)          -> axis 13 FAILS (the repro
#                                                                      silent)
#   (f3) 6.7.15: only a LEADING `lib/` (no `/lib/` component)       -> axis 13 FAILS (vendor/lib/
#                                                                      warned)
#   (i) 6.7.15: a fn-local const never judged (`_esx_const_slot`
#       answers -1 without leaving `_esx_rl_lc`)                    -> axis 12 FAILS (the repro
#                                                                      silent)
#   (j) 6.7.15: a fn-local const judged at the call site
#       (`_esx_lc_in_region` asks `_esx_region_at`)                 -> axis 12 FAILS (declared
#                                                                      outside, used inside: warned)
#   (k) 6.7.15: a replay records no declaration (`_lc_push`
#       stores 0 while GIDEP > 0)                                   -> axis 12 FAILS (the #inline
#                                                                      fn's const: 1 warning, its
#                                                                      literal twin 3)
#   (l) 6.7.15: a fn-local const judged file-locally
#       (`_esx_lc_in_region` answers `_esx_rg_local`)               -> axis 12 FAILS (the per-arch
#                                                                      file's const silent)
#   (g) 6.7.14: the frontend record dropped (no SVDECL in
#       PARSE_ENUM_DEF)                                             -> axis 7 FAILS (the enum
#                                                                      declared inside silent)
#   (h) 6.7.14: fd_wait_ready back to a raw 7                       -> axis 9 FAILS (1 warning,
#                                                                      lib/syscalls_linux_common.cyr)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail() { echo "FAIL native_region_literal_warns: $1" >&2; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL native_region_literal_warns: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT

REPRO="$ROOT/docs/development/issues/repros/2026-10-08-aarch64-native-region-literal-translated-silently.cyr"
[ -f "$REPRO" ] || fail "the filed repro is missing: $REPRO"

rc=0; (cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$T/cca" 2> "$T/cca.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cca" ] || fail "cross-building cycc_aarch64 from src failed (rc $rc): $(head -3 "$T/cca.err")"
chmod +x "$T/cca"

QEMU=0
if command -v qemu-aarch64 >/dev/null 2>&1; then QEMU=1; fi

# _cc <name> : compile $T/<name>.cyr from $T (so a relative include resolves there); rc 0 and a
# non-empty binary are required — a compile that failed prints no warning either.
_cc() {
    rc=0; (cd "$T" && "$T/cca" < "$1.cyr" > "$1.bin" 2> "$1.err") || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/$1.bin" ] || fail "$1: the probe did not compile (rc $rc): $(head -3 "$T/$1.err")"
    chmod +x "$T/$1.bin"
}
_nw() { grep -c 'inside a native-aarch64 region' "$T/$1.err" || true; }
_run() { rc=0; (cd "$T" && timeout 30 qemu-aarch64 "./$1.bin" > /dev/null 2>&1) || rc=$?; echo "$rc"; }

# ── axis 1: the filed repro, verbatim ───────────────────────────────────────────────
cp "$REPRO" "$T/repro.cyr"
_cc repro
[ "$(_nw repro)" = 1 ] || fail "axis 1: the filed repro printed $(_nw repro) native-region warnings, want 1: $(cat "$T/repro.err")"
grep -q 'raw syscall 9 inside a native-aarch64 region is renumbered → 222 (mmap); write 1009 for native lgetxattr' "$T/repro.err" \
  || fail "axis 1: the warning does not name 9 → 222 (mmap) and 1009 for native lgetxattr: $(cat "$T/repro.err")"
grep -q '^warning:<source>:10:' "$T/repro.err" || fail "axis 1: the warning does not point at the call's line (10): $(cat "$T/repro.err")"
if [ "$QEMU" = 1 ]; then
    r1=$(_run repro)
    [ "$r1" = 22 ] || fail "axis 1: the repro exits $r1 under qemu, want 22 — warn only: the literal must still be translated (mmap)"
    echo "  axis 1: the filed repro warns (9 → 222 mmap; write 1009 for native lgetxattr) and still exits 22 under qemu"
else
    echo "  axis 1: the filed repro warns (9 → 222 mmap; write 1009) — its qemu run SKIPPED: qemu-aarch64 absent"
fi

# ── axis 2: the 1009 control ────────────────────────────────────────────────────────
sed 's/syscall(9, /syscall(1009, /' "$REPRO" > "$T/ctl.cyr"
grep -q 'syscall(1009, ' "$T/ctl.cyr" || fail "axis 2: the control's sed did not apply to the repro"
_cc ctl
[ "$(_nw ctl)" = 0 ] || fail "axis 2: the 1009 alias spelling warned: $(cat "$T/ctl.err")"
if [ "$QEMU" = 1 ]; then
    r2=$(_run ctl)
    [ "$r2" = 0 ] || fail "axis 2: the 1009 control exits $r2 under qemu, want 0 (native lgetxattr → -ENOENT)"
    echo "  axis 2: the 1009 control is silent and exits 0 under qemu"
else
    echo "  axis 2: the 1009 control is silent — its qemu run SKIPPED: qemu-aarch64 absent"
fi

# ── axis 3: 39 names 1039 ───────────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(39, "/nonexistent", 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/r39.cyr"
_cc r39
grep -q 'raw syscall 39 inside a native-aarch64 region is renumbered → 172 (getpid); write 1039 for native umount2' "$T/r39.err" \
  || fail "axis 3: syscall(39) in a region does not name 172 (getpid) and 1039: $(cat "$T/r39.err")"
echo "  axis 3: syscall(39) in a region names 172 (getpid) and 1039 for native umount2"

# ── axis 4: the same literal outside a region ───────────────────────────────────────
printf '%s\n' 'fn f(): i64 { return syscall(9, 0, 4096, 3, 0x22, 0 - 1, 0); }' 'var x = f();' 'syscall(60, 0);' > "$T/out.cyr"
_cc out
[ "$(_nw out)" = 0 ] || fail "axis 4: syscall(9) OUTSIDE a region warned: $(cat "$T/out.err")"
echo "  axis 4: syscall(9) outside a region prints no new warning"

# ── axis 5: no ELF row → silent ─────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(134, 0, 0, 0, 8);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/r134.cyr"
_cc r134
[ "$(_nw r134)" = 0 ] || fail "axis 5: a region literal with no ELF row (134) warned: $(cat "$T/r134.err")"
echo "  axis 5: a region literal no row renumbers (134) stays silent"

# ── axis 6: no alias exists ─────────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifplat aarch64' '    r = syscall(1, 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/noal.cyr"
_cc noal
grep -q 'raw syscall 1 inside a native-aarch64 region is renumbered → 64 (write); no 1000+N alias exists for native io_destroy (the chain has no 1001 row)' "$T/noal.err" \
  || fail "axis 6: raw 1 in an #ifplat aarch64 region does not say no 1000+N alias exists: $(cat "$T/noal.err")"
echo "  axis 6: raw 1 in an #ifplat region: no 1000+N alias exists for native io_destroy"

# ── axis 7: constants and includes ──────────────────────────────────────────────────
printf '%s\n' 'enum MyNr { MY_LGX = 9; }' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(MY_LGX, "/x", "user.x", 0, 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/en.cyr"
_cc en
[ "$(_nw en)" = 0 ] || fail "axis 7: an enum constant declared OUTSIDE a region warned where it is used inside one: $(cat "$T/en.err")"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'enum ArchNr { NR_UMOUNT2 = 39; NR_LGX = 9; }' 'const NR_PIVOT = 41;' '#endif' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(NR_UMOUNT2, "/x", 0);' '    r = syscall(ArchNr.NR_LGX, "/x", "user.x", 0, 0);' '    r = syscall(NR_PIVOT, "/x", "/y");' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/enin.cyr"
_cc enin
[ "$(_nw enin)" = 3 ] || fail "axis 7: constants declared INSIDE a region printed $(_nw enin) warnings, want 3 (bare, Enum.NAME, const): $(cat "$T/enin.err")"
grep -q '^warning:<source>:8:.*syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered → 172 (getpid); write 1039 for native umount2' "$T/enin.err" \
  || fail "axis 7: the bare enum constant declared in the region does not name NR_UMOUNT2 = 39 → 172 and 1039: $(cat "$T/enin.err")"
grep -q '^warning:<source>:9:.*syscall constant NR_LGX = 9, declared inside .* → 222 (mmap); write 1009 for native lgetxattr' "$T/enin.err" \
  || fail "axis 7: the Enum.NAME spelling does not warn on line 9: $(cat "$T/enin.err")"
grep -q '^warning:<source>:10:.*syscall constant NR_PIVOT = 41, declared inside ' "$T/enin.err" \
  || fail "axis 7: the top-level const declared in the region does not warn on line 10: $(cat "$T/enin.err")"
mkdir -p "$T/inc"
printf '%s\n' 'fn armf(): i64 { return syscall(9, "/x", "user.x", 0, 0); }' > "$T/inc/arm.cyr"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'include "inc/arm.cyr"' '#endif' 'fn g(): i64 {' '#ifndef CYRIUS_ARCH_X86' '    return syscall(39, 0, 0);' '#endif' '    return 0;' '}' 'var x = g();' 'syscall(60, 0);' > "$T/incl.cyr"
_cc incl
[ "$(_nw incl)" = 2 ] || fail "axis 7: the include probe printed $(_nw incl) warnings, want 2 (the included file's raw 9 and the includer's own 39): $(cat "$T/incl.err")"
grep -q '^warning:inc/arm.cyr:1:.*raw syscall 9 inside a native-aarch64 region is renumbered → 222 (mmap)' "$T/incl.err" \
  || fail "axis 7: the file included from inside a region was not judged by it (D61): $(cat "$T/incl.err")"
grep -q '^warning:<source>:6:.*raw syscall 39 ' "$T/incl.err" || fail "axis 7: the includer's region after the include did not warn on its raw 39 (the file stack did not resume): $(cat "$T/incl.err")"
mkdir -p "$T/lib"
printf '%s\n' 'enum PeerNr { PEER_FSYNC = 74; }' 'fn peer_sync(fd): i64 { return syscall(PEER_FSYNC, fd); }' > "$T/lib/peer.cyr"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'include "lib/peer.cyr"' '#endif' 'var x = peer_sync(0 - 1);' 'syscall(60, 0);' > "$T/peer.cyr"
_cc peer
[ "$(_nw peer)" = 0 ] || fail "axis 7: a constant declared at the top level of a lib/ file included from inside a region warned (the stdlib peers' shape: their x86-numbered SYS_* renumber by design): $(cat "$T/peer.err")"
echo "  axis 7: a constant declared outside a region stays silent; declared inside it warns (bare, Enum.NAME, const); an included file is judged by its includer's region; a peer-shaped constant under lib/ stays silent"

# ── axis 8: warn only — nothing emitted changes ─────────────────────────────────────
sed 's/^#ifdef CYRIUS_ARCH_AARCH64$//; s/^#endif$//' "$REPRO" > "$T/flat.cyr"
[ "$(wc -l < "$T/flat.cyr")" = "$(wc -l < "$REPRO")" ] || fail "axis 8: blanking the region lines changed the line count"
_cc flat
[ "$(_nw flat)" = 0 ] || fail "axis 8: the region-free twin warned: $(cat "$T/flat.err")"
cmp -s "$T/repro.bin" "$T/flat.bin" || fail "axis 8: the repro's binary differs from its region-free twin — the warning changed what is emitted"
echo "  axis 8: the repro's binary is byte-identical to its region-free twin (warn only)"

# ── axis 9: the stdlib stays silent ─────────────────────────────────────────────────
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/alloc.cyr"' 'include "lib/io.cyr"' 'fn main(): i64 { return 0; }' 'var r = main();' 'syscall(60, r);' > "$T/hello.cyr"
rc=0; (cd "$ROOT" && "$T/cca" < "$T/hello.cyr" > "$T/hello.bin" 2> "$T/hello.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/hello.bin" ] || fail "axis 9: the stdlib hello did not build for aarch64 (rc $rc): $(head -3 "$T/hello.err")"
[ "$(_nw hello)" = 0 ] || fail "axis 9: the stdlib hello prints native-region warnings — a false positive on lib/: $(grep 'native-aarch64 region' "$T/hello.err" | head -3)"
echo "  axis 9: a stdlib hello (syscalls + alloc + io) builds for aarch64 with zero native-region warnings"

# ── axis 10: every lib/*.cyr stays silent ───────────────────────────────────────────
mkdir -p "$T/lib10"
nb=0; nl=0; nwl=0
for f in "$ROOT"/lib/*.cyr; do
    b=$(basename "$f" .cyr)
    nl=$((nl + 1))
    printf 'include "lib/%s.cyr"\nsyscall(60, 0);\n' "$b" > "$T/lib10/$b.cyr"
    rc=0; (cd "$ROOT" && "$T/cca" < "$T/lib10/$b.cyr" > "$T/lib10/$b.bin" 2> "$T/lib10/$b.err") || rc=$?
    if [ "$rc" = 0 ] && [ -s "$T/lib10/$b.bin" ]; then nb=$((nb + 1)); fi
    w=$(grep -c 'inside a native-aarch64 region' "$T/lib10/$b.err" || true)
    if [ "$w" != 0 ]; then nwl=$((nwl + w)); echo "    lib/$b.cyr: $(grep 'inside a native-aarch64 region' "$T/lib10/$b.err" | head -2)"; fi
done
[ "$nb" -ge 85 ] || fail "axis 10: only $nb of $nl lib/*.cyr built for aarch64 on their own (floor 85) — the sweep judged too little"
[ "$nwl" = 0 ] || fail "axis 10: $nwl native-region warning(s) across lib/*.cyr — a false positive on the stdlib"
echo "  axis 10: $nb of $nl lib/*.cyr build for aarch64 on their own, with zero native-region warnings"

# ── axis 11: the 6.7.14 filed repro, verbatim ───────────────────────────────────────
mkdir -p "$T/r14/src"
printf '%s\n' '# a per-arch file, included only on aarch64 — written with NATIVE numbers' \
  'fn arch_lgetxattr(path, name): i64 { return syscall(9, path, name, 0, 0); }' > "$T/r14/src/arch_aarch64.cyr"
cat > "$T/r14/main.cyr" <<'REPRO14'
#ifdef CYRIUS_ARCH_AARCH64
include "src/arch_aarch64.cyr"
enum ArchNr { NR_UMOUNT2 = 39; }
fn arch_umount(path): i64 { return syscall(NR_UMOUNT2, path, 0); }
#endif
fn main(): i64 {
    var a = arch_lgetxattr("/nonexistent", "user.x");   # native lgetxattr: -2 (ENOENT)
    var b = arch_umount("/nonexistent");                # native umount2: -2 (ENOENT)
    if (a != 0 - 2) { return 1; }                      # 9 ran mmap: -22
    if (b != 0 - 2) { return 2; }                      # 39 ran getpid: a PID
    return 0;
}
syscall(60, main());
REPRO14
sed 's/^#ifdef CYRIUS_ARCH_AARCH64$//; s/^#endif$//' "$T/r14/main.cyr" > "$T/r14/flat.cyr"
rc=0; (cd "$T/r14" && "$T/cca" < main.cyr > m.bin 2> m.err) || rc=$?
[ "$rc" = 0 ] && [ -s "$T/r14/m.bin" ] || fail "axis 11: the 6.7.14 repro did not compile (rc $rc): $(head -3 "$T/r14/m.err")"
rc=0; (cd "$T/r14" && "$T/cca" < flat.cyr > f.bin 2> f.err) || rc=$?
[ "$rc" = 0 ] && [ -s "$T/r14/f.bin" ] || fail "axis 11: the region-free twin did not compile (rc $rc): $(head -3 "$T/r14/f.err")"
n14=$(grep -c 'inside a native-aarch64 region' "$T/r14/m.err" || true)
[ "$n14" = 2 ] || fail "axis 11: the 6.7.14 repro printed $n14 native-region warnings, want 2: $(cat "$T/r14/m.err")"
grep -q '^warning:src/arch_aarch64.cyr:2:.*raw syscall 9 inside a native-aarch64 region is renumbered → 222 (mmap); write 1009 for native lgetxattr' "$T/r14/m.err" \
  || fail "axis 11: the included per-arch file's raw 9 is not warned: $(cat "$T/r14/m.err")"
grep -q '^warning:<source>:4:.*syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered → 172 (getpid); write 1039 for native umount2' "$T/r14/m.err" \
  || fail "axis 11: the author's constant is not warned: $(cat "$T/r14/m.err")"
cmp -s "$T/r14/m.bin" "$T/r14/f.bin" || fail "axis 11: the repro's binary differs from its region-free twin — the warning changed what is emitted"
if [ "$QEMU" = 1 ]; then
    chmod +x "$T/r14/m.bin"
    r14=0; (cd "$T/r14" && timeout 30 qemu-aarch64 ./m.bin > /dev/null 2>&1) || r14=$?
    [ "$r14" = 1 ] || fail "axis 11: the 6.7.14 repro exits $r14 under qemu, want 1 — warn only: the 9 must still run mmap"
    echo "  axis 11: the 6.7.14 filed repro warns twice (the included file's 9, NR_UMOUNT2), emits what its region-free twin does and still exits 1 under qemu"
else
    echo "  axis 11: the 6.7.14 filed repro warns twice and emits what its region-free twin does — its qemu run SKIPPED: qemu-aarch64 absent"
fi

# ── axis 12: a fn-local const (6.7.15), the filed repro verbatim ────────────────────
# A local const is judged where its name token sits (`_lc_decl`), by the top-level constants'
# rule: an `#inline` fn's const by the inline body's declaration, never the call site.
_c12() {   # _c12 <name>: compile $T/a12/<name>.cyr from $T/a12
    rc=0; (cd "$T/a12" && "$T/cca" < "$1.cyr" > "$1.bin" 2> "$1.err") || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/a12/$1.bin" ] || fail "axis 12: $1 did not compile (rc $rc): $(head -3 "$T/a12/$1.err")"
    chmod +x "$T/a12/$1.bin"
}
_n12() { grep -c 'inside a native-aarch64 region' "$T/a12/$1.err" || true; }
_q12() { r=0; (cd "$T/a12" && timeout 30 qemu-aarch64 "./$1.bin" > /dev/null 2>&1) || r=$?; echo "$r"; }
mkdir -p "$T/a12/inc" "$T/a12/lib"
cat > "$T/a12/lc.cyr" <<'REPRO12'
fn f(): i64 {
    var r = 0;
#ifdef CYRIUS_ARCH_AARCH64
    const NR_UMOUNT2 = 39;
    r = syscall(NR_UMOUNT2, "/nonexistent", 0);
#endif
    if (r == 0 - 2) { return 0; }   # native umount2: -ENOENT
    return 1;                       # 39 ran getpid: a PID
}
syscall(60, f());
REPRO12
sed 's/^#ifdef CYRIUS_ARCH_AARCH64$//; s/^#endif$//' "$T/a12/lc.cyr" > "$T/a12/lcflat.cyr"
_c12 lc
_c12 lcflat
[ "$(_n12 lc)" = 1 ] || fail "axis 12: the fn-local const repro printed $(_n12 lc) native-region warnings, want 1: $(cat "$T/a12/lc.err")"
grep -q '^warning:<source>:5:.*syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered → 172 (getpid); write 1039 for native umount2' "$T/a12/lc.err" \
  || fail "axis 12: the fn-local const declared in the region is not warned at its use (line 5): $(cat "$T/a12/lc.err")"
[ "$(_n12 lcflat)" = 0 ] || fail "axis 12: the region-free twin warned: $(cat "$T/a12/lcflat.err")"
cmp -s "$T/a12/lc.bin" "$T/a12/lcflat.bin" || fail "axis 12: the repro's binary differs from its region-free twin — the warning changed what is emitted"
# Declared OUTSIDE a region, used inside one: silent (judged by its declaration).
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '    const NR_X = 39;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(NR_X, "/nonexistent", 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/a12/out.cyr"
_c12 out
[ "$(_n12 out)" = 0 ] || fail "axis 12: a fn-local const declared OUTSIDE a region warned where it is used inside one: $(cat "$T/a12/out.err")"
# An `#inline` fn's const declared in a region of its own file, the fn called from outside any
# region: warned in the inline body's file, exactly as often as the literal twin (the definition
# and each replay), and the binaries are identical.
printf '%s\n' '#inline' 'fn inl_umount(p): i64 {' '#ifdef CYRIUS_ARCH_AARCH64' '    const NR_IU = 39;' '    return syscall(NR_IU, p, 0);' '#endif' '    return 0;' '}' > "$T/a12/inc/inl.cyr"
printf '%s\n' '#inline' 'fn inl_umount(p): i64 {' '#ifdef CYRIUS_ARCH_AARCH64' '' '    return syscall(39, p, 0);' '#endif' '    return 0;' '}' > "$T/a12/inc/inllit.cyr"
printf '%s\n' 'include "inc/inl.cyr"' 'fn g(): i64 {' '    var a = inl_umount("/nonexistent");' '    var b = inl_umount("/nonexistent");' '    if (a == 0 - 2 && b == 0 - 2) { return 0; }' '    return 1;' '}' 'syscall(60, g());' > "$T/a12/inl.cyr"
sed 's#^include "inc/inl.cyr"$#include "inc/inllit.cyr"#' "$T/a12/inl.cyr" > "$T/a12/inllit.cyr"
_c12 inl
_c12 inllit
nlit=$(_n12 inllit)
[ "$nlit" -ge 2 ] || fail "axis 12: the #inline literal twin printed $nlit warnings, want one per replay at least (2): $(cat "$T/a12/inllit.err")"
[ "$(_n12 inl)" = "$nlit" ] || fail "axis 12: the #inline fn's local const printed $(_n12 inl) warnings, its literal twin $nlit — every replay is judged by the declaration: $(cat "$T/a12/inl.err")"
[ "$(grep -c '^warning:inc/inl.cyr:5:.*syscall constant NR_IU = 39, declared inside ' "$T/a12/inl.err" || true)" = "$nlit" ] \
  || fail "axis 12: the #inline fn's warnings do not all name inc/inl.cyr:5 and NR_IU: $(cat "$T/a12/inl.err")"
cmp -s "$T/a12/inl.bin" "$T/a12/inllit.bin" || fail "axis 12: the #inline probe's binary differs from its literal twin's"
# An `#inline` fn's const declared outside any region, called from INSIDE one: silent.
printf '%s\n' '#inline' 'fn inl_x(p): i64 {' '    const NR_IX = 39;' '    return syscall(NR_IX, p, 0);' '}' > "$T/a12/inc/inl2.cyr"
printf '%s\n' 'include "inc/inl2.cyr"' 'fn g(): i64 {' '    var a = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    a = inl_x("/nonexistent");' '#endif' '    return a;' '}' 'var x = g();' 'syscall(60, 0);' > "$T/a12/inl2.cyr"
_c12 inl2
[ "$(_n12 inl2)" = 0 ] || fail "axis 12: an #inline fn's const declared outside a region warned at a call inside one — judged by the call site: $(cat "$T/a12/inl2.err")"
# D39's rule for a local const: in a file outside lib/ included under the guard it is judged by
# the carried region; the same file under lib/ stays silent.
printf '%s\n' 'fn lc_umount(p): i64 {' '    const NR_LU = 39;' '    return syscall(NR_LU, p, 0);' '}' > "$T/a12/inc/lcarch.cyr"
cp "$T/a12/inc/lcarch.cyr" "$T/a12/lib/lcarch.cyr"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'include "inc/lcarch.cyr"' '#endif' 'var r = lc_umount("/nonexistent");' 'if (r == 0 - 2) { syscall(60, 0); }' 'syscall(60, 2);' > "$T/a12/lca.cyr"
sed 's#^include "inc/lcarch.cyr"$#include "lib/lcarch.cyr"#' "$T/a12/lca.cyr" > "$T/a12/lcl.cyr"
_c12 lca
_c12 lcl
[ "$(_n12 lca)" = 1 ] && grep -q '^warning:inc/lcarch.cyr:3:.*syscall constant NR_LU = 39, declared inside ' "$T/a12/lca.err" \
  || fail "axis 12: a fn-local const in a file outside lib/ included under the guard is not warned (D39's carried region): $(cat "$T/a12/lca.err")"
[ "$(_n12 lcl)" = 0 ] || fail "axis 12: the same fn-local const under lib/ warned: $(cat "$T/a12/lcl.err")"
if [ "$QEMU" = 1 ]; then
    q12=$(_q12 lc); q12i=$(_q12 inl); q12a=$(_q12 lca)
    [ "$q12" = 1 ] && [ "$q12i" = 1 ] && [ "$q12a" = 2 ] \
      || fail "axis 12: under qemu the repro exits $q12 (want 1), the #inline probe $q12i (want 1), the per-arch probe $q12a (want 2) — warn only: 39 still runs getpid"
    echo "  axis 12: the fn-local const repro warns once (NR_UMOUNT2 = 39 → 172), emits what its region-free twin does and still exits 1 under qemu; declared outside a region: silent; an #inline fn's const is judged by its declaration ($nlit warnings in inc/inl.cyr, as its literal twin; silent when declared outside and called inside); D39's carried region for a per-arch file outside lib/"
else
    echo "  axis 12: the fn-local const repro warns once and emits what its region-free twin does; declared outside: silent; #inline judged by its declaration; D39's carried region — its qemu runs SKIPPED: qemu-aarch64 absent"
fi

# ── axis 13: the 6.7.15 filed repro (D39), verbatim ─────────────────────────────────
# A constant declared at the top level of the author's own per-arch file, included from inside
# `#ifdef CYRIUS_ARCH_AARCH64`: in a file outside lib/ the region carries (6.7.15's D39, the user,
# 2026-10-18: "Yes, for files outside lib/"); the same file under lib/ — spelled `lib/…`, with a
# `/lib/` component, or reached through the store-slot fallback — keeps the file-local rule.
_c13() {   # _c13 <dir> [env…]: compile <dir>/main.cyr from <dir>
    d="$1"; shift
    rc=0; (cd "$d" && env "$@" "$T/cca" < main.cyr > m.bin 2> m.err) || rc=$?
    [ "$rc" = 0 ] && [ -s "$d/m.bin" ] || fail "axis 13: $d/main.cyr did not compile (rc $rc): $(head -3 "$d/m.err")"
    chmod +x "$d/m.bin"
}
_n13() { grep -c 'inside a native-aarch64 region' "$1/m.err" || true; }
_q13() { r=0; (cd "$1" && timeout 30 qemu-aarch64 ./m.bin > /dev/null 2>&1) || r=$?; echo "$r"; }
mkdir -p "$T/r13/src"
cat > "$T/r13/src/arch_aarch64.cyr" <<'REPRO13A'
enum ArchNr { NR_UMOUNT2 = 39; }
fn arch_umount(path) { return syscall(NR_UMOUNT2, path, 0); }
REPRO13A
cat > "$T/r13/main.cyr" <<'REPRO13M'
#ifdef CYRIUS_ARCH_AARCH64
include "src/arch_aarch64.cyr"
#endif
var r = arch_umount("/nonexistent");
if (r == 0 - 2) { syscall(60, 0); }   # native umount2: -ENOENT
syscall(60, 2);                       # 39 ran getpid: a PID
REPRO13M
_c13 "$T/r13"
[ "$(_n13 "$T/r13")" = 1 ] || fail "axis 13: the 6.7.15 repro printed $(_n13 "$T/r13") native-region warnings, want 1: $(cat "$T/r13/m.err")"
grep -q '^warning:src/arch_aarch64.cyr:2:.*syscall constant NR_UMOUNT2 = 39, declared inside a native-aarch64 region, is renumbered → 172 (getpid); write 1039 for native umount2' "$T/r13/m.err" \
  || fail "axis 13: the per-arch file's top-level constant is not warned at its use (D39): $(cat "$T/r13/m.err")"
mkdir -p "$T/r13f/src"
cp "$T/r13/src/arch_aarch64.cyr" "$T/r13f/src/"
sed 's/^#ifdef CYRIUS_ARCH_AARCH64$//; s/^#endif$//' "$T/r13/main.cyr" > "$T/r13f/main.cyr"
_c13 "$T/r13f"
[ "$(_n13 "$T/r13f")" = 0 ] || fail "axis 13: the region-free twin warned: $(cat "$T/r13f/m.err")"
cmp -s "$T/r13/m.bin" "$T/r13f/m.bin" || fail "axis 13: the repro's binary differs from its region-free twin — the warning changed what is emitted"
# The same file under lib/: the include spelled `lib/…`, a `/lib/` component, and a lib/ file the
# store-slot fallback reads (a throwaway CYRIUS_HOME; the marker keeps the spelled `lib/` name).
mkdir -p "$T/r13l/lib" "$T/r13v/vendor/lib"
cp "$T/r13/src/arch_aarch64.cyr" "$T/r13l/lib/"
cp "$T/r13/src/arch_aarch64.cyr" "$T/r13v/vendor/lib/"
sed 's#^include "src/arch_aarch64.cyr"$#include "lib/arch_aarch64.cyr"#' "$T/r13/main.cyr" > "$T/r13l/main.cyr"
sed 's#^include "src/arch_aarch64.cyr"$#include "vendor/lib/arch_aarch64.cyr"#' "$T/r13/main.cyr" > "$T/r13v/main.cyr"
grep -q '^include "lib/arch_aarch64.cyr"$' "$T/r13l/main.cyr" && grep -q '^include "vendor/lib/arch_aarch64.cyr"$' "$T/r13v/main.cyr" \
  || fail "axis 13: the lib/ variants' sed did not apply"
_c13 "$T/r13l"
[ "$(_n13 "$T/r13l")" = 0 ] || fail "axis 13: the same file under lib/ warned — a constant declared in a lib/ file keeps the file-local rule: $(cat "$T/r13l/m.err")"
_c13 "$T/r13v"
[ "$(_n13 "$T/r13v")" = 0 ] || fail "axis 13: the same file under a /lib/ component (vendor/lib/) warned: $(cat "$T/r13v/m.err")"
V13=$("$T/cca" --version < /dev/null | awk '{print $2}')
[ -n "$V13" ] || fail "axis 13: could not read the cross compiler's version (the store slot's name)"
mkdir -p "$T/r13h/home/versions/$V13/lib" "$T/r13h/w"
sed 's/ArchNr/Arch13Nr/; s/NR_UMOUNT2/NR13_UMOUNT2/g' "$T/r13/src/arch_aarch64.cyr" > "$T/r13h/home/versions/$V13/lib/p3arch13.cyr"
sed 's#^include "src/arch_aarch64.cyr"$#include "lib/p3arch13.cyr"#' "$T/r13/main.cyr" > "$T/r13h/w/main.cyr"
[ ! -e "$T/r13h/w/lib" ] || fail "axis 13: the store-slot probe's directory has a lib/ of its own"
_c13 "$T/r13h/w" CYRIUS_HOME="$T/r13h/home" CYRIUS_LIB_OVERLAY=
[ "$(_n13 "$T/r13h/w")" = 0 ] || fail "axis 13: a lib/ file read through the store-slot fallback warned: $(cat "$T/r13h/w/m.err")"
# lib/ keeps 6.7.14's rule, not an exemption: a constant declared in a region its own lib/ file
# opens is still judged.
mkdir -p "$T/r13o/lib"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'enum OwnNr { OWN_UMOUNT2 = 39; }' '#endif' 'fn own_umount(path) { return syscall(OWN_UMOUNT2, path, 0); }' > "$T/r13o/lib/own.cyr"
sed 's#^include "src/arch_aarch64.cyr"$#include "lib/own.cyr"#; s/arch_umount(/own_umount(/' "$T/r13/main.cyr" > "$T/r13o/main.cyr"
_c13 "$T/r13o"
[ "$(_n13 "$T/r13o")" = 1 ] && grep -q '^warning:lib/own.cyr:4:.*syscall constant OWN_UMOUNT2 = 39, declared inside ' "$T/r13o/m.err" \
  || fail "axis 13: a constant a lib/ file declares inside a region of its own is not warned (lib/ keeps the file-local rule): $(cat "$T/r13o/m.err")"
if [ "$QEMU" = 1 ]; then
    q13=$(_q13 "$T/r13"); q13l=$(_q13 "$T/r13l")
    [ "$q13" = 2 ] && [ "$q13l" = 2 ] || fail "axis 13: the repro exits $q13 (under lib/: $q13l) under qemu, want 2 — warn only: 39 still runs getpid"
    echo "  axis 13: the 6.7.15 filed repro warns once (NR_UMOUNT2 = 39 → 172, in src/arch_aarch64.cyr), emits what its region-free twin does and still exits 2 under qemu; under lib/, vendor/lib/ and the store slot it stays silent; a lib/ file's own region still warns"
else
    echo "  axis 13: the 6.7.15 filed repro warns once and emits what its region-free twin does; under lib/, vendor/lib/ and the store slot it stays silent — its qemu runs SKIPPED: qemu-aarch64 absent"
fi

echo "PASS native_region_literal_warns (a raw region literal a compat row renumbers is warned — a region carrying through include — and so is a constant declared in one, with its 1000+N spelling or none; still translated; constants declared outside, peer-shaped constants and the whole stdlib stay silent; a fn-local const is judged by its declaration)"
