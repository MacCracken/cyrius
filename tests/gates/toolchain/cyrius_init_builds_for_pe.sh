#!/bin/sh
# Gate: every tool the Windows tarball ships actually CROSS-BUILDS for PE with no
# reachable undefined function — and `cyrius init` / `cyrius port` work from the shipped
# Windows layout, including the templates the scaffolder resolves from its own path.
#
# ⛔ THE DEFECT (filed 2026-09-18, closed 6.6.6 bite 6). `programs/cyrius-init.cyr`
# resolved its own path with exactly two arms — macOS (`fcntl(F_GETPATH)`) and
# `readlink("/proc/self/exe")` — and moved the port's source tree aside with
# `sys_rename`. Windows has none of the three: `lib/syscalls_windows.cyr` defined
# neither wrapper, so the PE cross-build refused with
#
#   warning: undefined function 'sys_readlink'
#   warning: undefined function 'sys_rename'
#   error: refusing to emit binary with 2 reachable undefined function(s)
#
# and produced a 0-byte file. `build-windows-tarball.sh` therefore skipped the binary
# and the CLI answered `tool not found` for BOTH verbs on every Windows install.
#
# ⚠ THE HALF-FIX THIS GATE FORBIDS, and it is why axes 3 and 4 run the binary rather
# than trusting that it compiles: the easy repair is to guard the readlink arm and fall
# back to `argv(0)`. That COMPILES and it passes a `--dry-run`, but on Windows argv[0] is
# whatever the PARENT wrote on the command line — it can be relative, or a bare name off
# PATH — while `_resolve_templates_dir` needs this path's GRANDPARENT. So axis 3 invokes
# the exe by a RELATIVE path from an unrelated working directory: the real fix (the
# v6.6.6 0xF03A → kernel32!GetModuleFileNameW reroute) resolves the templates, the argv0
# fallback resolves a directory that does not exist and scaffolds "missing template" for
# every file. A shipped-but-useless binary is the outcome this whole filing is about.
#
# Axis 2 is the generalisation: the tool list is DERIVED from build-windows-tarball.sh
# itself, so the next tool added there is cross-built here automatically. "It is in the
# packaging list" is not "it builds"; that gap is exactly what shipped.
#
# MUTATION LEDGER (6.6.6 bite 6, run on this host against a staged copy of the tree, with
# the mutant compiler rebuilt to its own fixpoint where the mutation is in src/):
#   * delete `sys_rename` + `sys_self_exe_w` from lib/syscalls_windows.cyr
#       → axis 1 RED (rc=1, 5 undefined-fn warnings, 0-byte output), axis 5 RED on the
#         peer census, axes 3-4 RED (there is no binary to run). 11 checks red.
#   * put a `sys_readlink` ENOSYS stub BACK into lib/syscalls_windows.cyr
#       → axis 5 RED, 1 check. This is the mutation for the review fix: the stub leaves
#         axes 1-4 GREEN (it changes nothing about the build — same rc, same MZ, same
#         155,648 B, 0 undefined fns), which is the point. What it changes is that
#         `readlink("/proc/self/exe")` — the exact line this filing is about — starts
#         COMPILING for PE and silently degrading to argv(0), i.e. the half-fix axes 3-4
#         exist to catch gets waved through at the build step instead.
#   * make `_PE_ROUTE_MODULEPATH` (src/frontend/parse_expr.cyr) return 0, so the reroute
#     degrades to -38/-ENOSYS and `_self_path` falls back to argv0
#       → axes 1, 2 and 5 all stay GREEN — it still compiles and still ships, which is
#         precisely the shipped-but-useless outcome — and axes 3-4 go RED, 8 checks: the
#         relative-path init exits 1 with no CLAUDE.md written, and the port exits 1.
#         This is the mutation that justifies running the binary at all.
#   * drop the `cp -r programs/cyrius-init-templates` line from build-windows-tarball.sh
#       → axis 5 RED (1 check).
#   * real tree → all axes GREEN (axes 3-4 SKIP where wine is absent; cass runs them on
#     hardware).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cyrius_init_builds_for_pe: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$ROOT/build/cycc" ] || { echo "FAIL: cyrius_init_builds_for_pe: build/cycc missing"; exit 1; }
TARBALL=scripts/build-windows-tarball.sh
[ -f "$TARBALL" ] || { echo "FAIL: $TARBALL missing"; exit 1; }

# The PE cross-compiler, built the way the release builds it.
if ! "$ROOT/build/cycc" < "$ROOT/src/main_win.cyr" > "$T/cc_win" 2> "$T/ccwin.err"; then
    echo "FAIL: cyrius_init_builds_for_pe: src/main_win.cyr did not compile"; sed -n '1,5p' "$T/ccwin.err"; exit 1
fi
chmod +x "$T/cc_win"

# build_pe <source> <dest> <label> — refuses a non-PE / short artifact, and reports any
# `undefined function` the compiler named (the exact signature of this filing).
build_pe() {
    if "$T/cc_win" < "$1" > "$2" 2> "$T/pe.err"; then rc=0; else rc=$?; fi
    UNDEF=$(grep -c "undefined function" "$T/pe.err" || true)
    if [ "$rc" -ne 0 ] || [ "$UNDEF" -ne 0 ]; then
        echo "  FAIL: $3 does not cross-build for PE (rc=$rc, $UNDEF undefined-fn warnings)"
        grep -E "undefined function|^error" "$T/pe.err" | sed 's/^/      /' | head -6
        fails=$((fails + 1))
        return 1
    fi
    MAGIC=$(head -c 2 "$2" 2> /dev/null)
    SZ=$(wc -c < "$2")
    if [ "$MAGIC" != "MZ" ] || [ "$SZ" -lt 20000 ]; then
        echo "  FAIL: $3 produced a non-PE / ${SZ}-byte artifact (magic='$MAGIC')"
        fails=$((fails + 1))
        return 1
    fi
    echo "  ok: $3 cross-builds for PE (${SZ} B, 0 undefined fns)"
    return 0
}

# ── AXIS 1: the filed repro, verbatim.
echo "axis 1 — programs/cyrius-init.cyr cross-builds for PE with no reachable undefined fn:"
build_pe "$ROOT/programs/cyrius-init.cyr" "$T/cyrius-init.exe" "cyrius-init"

# ── AXIS 2: every tool the Windows tarball packages, derived from the script itself.
echo "axis 2 — every tool build-windows-tarball.sh packages actually cross-builds:"
TOOLS=$(grep '^for tool in ' "$TARBALL" | sed 's/^for tool in //; s/; do.*//')
NTOOLS=$(printf '%s\n' $TOOLS | grep -c . || true)
check "tools found in the packaging loop (anti-vacuous floor >= 6)" yes "$([ "$NTOOLS" -ge 6 ] && echo yes || echo no)"
check "cyrius-init is one of them (it was exempted until 6.6.6)" 1 "$(printf '%s\n' $TOOLS | grep -cx 'cyrius-init' || true)"
for t in $TOOLS; do
    [ "$t" = "cyrius-init" ] && continue          # axis 1 already built it
    [ -f "$ROOT/programs/$t.cyr" ] || continue
    build_pe "$ROOT/programs/$t.cyr" "$T/$t.exe" "$t"
    rm -f "$T/$t.exe"
done

# ── AXIS 5 (static, run before the wine axes so it reports even on a SKIP):
echo "axis 5 — the packaging and the diagnostic agree with the code:"
check "the tarball copies the scaffolding templates" yes \
    "$(grep -q 'cp -r programs/cyrius-init-templates' "$TARBALL" && echo yes || echo no)"
check "the tarball validates cyrius-init.exe's PE magic" yes \
    "$(grep -q 'cyrius-init\.exe' "$TARBALL" && echo yes || echo no)"
check "install.ps1 copies programs\\ into the version slot" yes \
    "$(grep -q 'VerDir\\programs' scripts/install.ps1 && echo yes || echo no)"
check "install.ps1 copies programs\\ into the active home" yes \
    "$(grep -q 'CyriusHome\\programs' scripts/install.ps1 && echo yes || echo no)"
check "the Windows peer defines the module-path wrapper" 1 \
    "$(grep -c '^fn sys_self_exe_w(' lib/syscalls_windows.cyr || true)"
check "the Windows peer defines sys_rename" 1 \
    "$(grep -c '^fn sys_rename(' lib/syscalls_windows.cyr || true)"
# ⛔ AND DOES NOT STUB readlink. `readlink("/proc/self/exe")` is the shape this whole
# filing is about; an ENOSYS stub for it would make that line COMPILE for PE and then
# silently fall back to argv(0) — the half-fix axes 3-4 exist to catch, handed a free
# pass at the build step. Measured: with the scaffolder's call guarded, the stub changes
# nothing about the PE build (same rc, same MZ, same 155,648 B, 0 undefined fns), so it
# was pure diagnostic loss. A REAL readlink (DeviceIoControl + FSCTL_GET_REPARSE_POINT)
# is welcome and would need this line updated deliberately; a stub is not.
check "…and does NOT stub sys_readlink (the hard error is the diagnostic)" 0 \
    "$(grep -c '^fn sys_readlink(' lib/syscalls_windows.cyr || true)"
# The routable-number warning is what a consumer reads to decide whether a syscall is
# safe on PE; a route missing from it is a diagnostic that lies.
check "the routable-numbers warning names 0xF03A" 1 \
    "$(grep -c '0xF03A (kernel32: GetModuleFileNameW)' src/frontend/parse_expr.cyr || true)"

# ── AXES 3+4: run the thing, from the SHIPPED layout. Not hardware — cass does that.
if ! command -v wine > /dev/null 2>&1; then
    echo "axes 3-4 — SKIP: wine is not installed; the cass leg runs these on real Windows"
else
    echo "axes 3-4 — the shipped layout under wine (NOT hardware verification):"
    export WINEPREFIX="$T/wine" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    S="$T/stage"
    mkdir -p "$S/bin" "$S/programs" "$S/work" "$S/elsewhere" "$S/home"
    cp "$T/cyrius-init.exe" "$S/bin/cyrius-init.exe"
    cp -r "$ROOT/programs/cyrius-init-templates" "$S/programs/"
    VER=$(tr -d '[:space:]' < "$ROOT/VERSION")

    # axis 3: invoked by a RELATIVE path from a directory that is NOT the binary's —
    # the case argv(0) cannot answer.
    ( cd "$S/work" && HOME="$S/home" CYRIUS_VER="$VER" timeout 120 wine "..\\bin\\cyrius-init.exe" demo ) \
        > "$T/w.out" 2>&1
    check "init exits 0 (relative argv0, foreign cwd)" 0 "$?"
    check "no template went missing" 0 "$(grep -c 'missing template' "$T/w.out" || true)"
    check "the scaffold is not reported INCOMPLETE" 0 "$(grep -c 'scaffold INCOMPLETE' "$T/w.out" || true)"
    check "a template-rendered file was written" yes "$([ -f "$S/work/demo/CLAUDE.md" ] && echo yes || echo no)"
    # …and RENDERED, not copied: {PROJ} must be substituted, and the raw key must be gone.
    check "  …with its {PROJ} placeholder substituted" yes \
        "$(grep -q 'demo' "$S/work/demo/cyrius.cyml" 2> /dev/null && echo yes || echo no)"
    check "  …and no unsubstituted {PROJ} left behind" 0 \
        "$(grep -c '{PROJ}' "$S/work/demo/cyrius.cyml" 2> /dev/null || true)"

    # axis 4: port — the sys_rename half, which is MoveFileExW on PE.
    mkdir -p "$S/elsewhere/rs/src"
    printf '[package]\nname = "demo"\n' > "$S/elsewhere/rs/Cargo.toml"
    printf 'fn main() {}\n' > "$S/elsewhere/rs/src/main.rs"
    printf '/target\n' > "$S/elsewhere/rs/.gitignore"
    ( cd "$S/elsewhere" && HOME="$S/home" CYRIUS_VER="$VER" timeout 120 wine "..\\bin\\cyrius-init.exe" --__mode=port rs ) \
        > "$T/p.out" 2>&1
    check "port exits 0" 0 "$?"
    check "the source tree moved aside (sys_rename -> MoveFileExW)" yes \
        "$([ -f "$S/elsewhere/rs/rust-old/Cargo.toml" ] && echo yes || echo no)"
    check "  …and is gone from its old place" no \
        "$([ -f "$S/elsewhere/rs/Cargo.toml" ] && echo yes || echo no)"
    check "the existing .gitignore got the port lines" 1 \
        "$(grep -c '^/rust-old/target/$' "$S/elsewhere/rs/.gitignore" || true)"

    # Leave no wineserver or socket dir behind (same recipe as cli_args_never_dropped).
    SOCK="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WINEPREFIX" 2> /dev/null)-$(printf '%x' "$(stat -c '%i' "$WINEPREFIX" 2> /dev/null || echo 0)")"
    wineserver -k > /dev/null 2>&1 || true
    wineserver -w > /dev/null 2>&1 || true
    [ -d "$SOCK" ] && rm -rf "$SOCK"
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "PASS: cyrius_init_builds_for_pe — the scaffolder cross-builds, ships, and runs from the Windows layout"
    exit 0
fi
echo "FAIL: cyrius_init_builds_for_pe — $fails check(s) failed"
exit 1
