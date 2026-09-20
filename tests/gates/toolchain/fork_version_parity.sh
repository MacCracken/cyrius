#!/bin/sh
# FORK-PARITY AXIS — every src/main*.cyr driver answers `--version`.
#
# WHY THIS IS AN AXIS AND NOT A TEST LIST (v6.6.6): four of the seven drivers
# (main_aarch64.cyr, main_aarch64_native.cyr, main_aarch64_macho.cyr,
# main_cx.cyr) had NO `--version` arm, and main_x86_macho.cyr had no
# command-line scan at all. cycc's fall-through for an unrecognised invocation
# is "compile stdin", so on an ARM install `cycc --version` compiled EMPTY input
# and wrote a 65,888-byte ELF to stdout with exit 0 — and the `[custom.cyrius]`
# STARSHIP PROMPT SEGMENT scripts/install.sh installs runs
# `cycc --version | awk '{print $2}'` whenever the shell is inside a cyrius
# project, so the prompt showed a field of that binary as the toolchain version.
# (The installer itself never reads `cycc --version`; this header said it did
# until the review corrected it.) Nothing noticed, because no gate ever ran a
# fork's compiler with a flag.
#
# The fork list is DERIVED from the tree (src/main*.cyr), never written down
# here, so an eighth driver cannot be added without handling --version.
#
# Rows:
#   static   — every derived fork writes a _VERSION_STR_* to fd 1 and exits.
#   runtime  — each fork's BUILT compiler is run where it can run on this host:
#              x86-Linux directly, aarch64 under qemu-aarch64, PE under wine.
#              The two Mach-O drivers cannot execute on Linux; they are built
#              and their output is checked to be a real Mach-O (this is NOT
#              hardware verification — the release gate's cross-OS leg is).
#   expected — the version is read from the VERSION file, a DIFFERENT source
#              from the string compiled into the binary (src/version_str.cyr).
#   negative — --version output must be the version line, not a binary: no ELF
#              / MZ / CYX magic, and exactly one line.
#
# MUTATION LEDGER (v6.6.6, run against scratch trees, never the repo):
#   real tree                                                          -> GREEN
#     10 rows, 5.4 s wall
#   pre-fix src (git archive HEAD src, i.e. the four forks with no arm) -> RED
#     "FAIL: static: src/main_aarch64.cyr never references a _VERSION_STR_*"
#   fixed src, cx's "--ve" test flipped 118 -> 119 (static write intact) -> RED
#     "FAIL: runtime cx (main_cx.cyr): --version wrote 24 bytes of CYX magic
#      (compiled empty stdin)"
#   fixed src, main_aarch64.cyr's test flipped 118 -> 119               -> RED
#     "FAIL: runtime aarch64 host cross (main_aarch64.cyr): --version wrote
#      65888 bytes of ELF (compiled empty stdin)"
#   The last two matter: they are the mutants a grep-only gate would pass.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f VERSION ] || { echo "SKIP: VERSION missing"; exit 0; }
VER=$(cat VERSION)
[ -n "$VER" ] || { echo "FAIL: VERSION is empty"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: fork_version_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# ── the derived fork list ────────────────────────────────────────────────
FORKS=$(find src -maxdepth 1 -name 'main*.cyr' | sort)
NF=$(printf '%s\n' "$FORKS" | grep -c '\.cyr$' || true)
# Floor: the drivers that existed when the axis landed. A fork REMOVED without
# updating this number is as much a regression as one added without --version.
if [ "$NF" -lt 7 ]; then
    echo "FAIL: only $NF src/main*.cyr drivers found (floor 7) — did the glob break?"
    exit 1
fi

# ── static axis: every fork prints a version string ──────────────────────
for f in $FORKS; do
    if ! grep -q '_VERSION_STR_' "$f"; then
        echo "FAIL: static: $f never references a _VERSION_STR_* (src/version_str.cyr)"
        exit 1
    fi
    # Reference is not enough — an `include` mentions the file. Require an
    # actual write of the string to fd 1.
    # v6.6.6 INTEGRATION: the write may be the raw `syscall(SYS_WRITE, 1, …)` or the
    # checked `_write_out_all(…)` helper the output-write bite added in the same release
    # (a short write of the version string is an error too). Either is a write to fd 1;
    # neither is a mere `include` mention, which is what this axis exists to reject.
    if ! grep -qE '(syscall\(SYS_WRITE, 1, _VERSION_STR_|_write_out_all\(_VERSION_STR_)' "$f"; then
        echo "FAIL: static: $f has no _VERSION_STR_ write to fd 1 — \`cycc --version\` there"
        echo "      falls through to \"compile stdin\" and emits a BINARY on stdout"
        exit 1
    fi
done
echo "  static: $NF/$NF drivers write a version string"

# ── runtime helper ───────────────────────────────────────────────────────
# $1 = row label, $2.. = the command that runs the built compiler.
# Asserts: exit 0, single line, field 2 == $VER, no executable magic.
assert_version() {
    label=$1
    shift
    out="$T/out.$$"
    rc=0
    "$@" --version < /dev/null > "$out" 2> "$T/err.$$" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: runtime $label: --version exited $rc"
        head -3 "$T/err.$$" || true
        return 1
    fi
    bytes=$(wc -c < "$out" | tr -d ' ')
    if [ "$bytes" -eq 0 ]; then
        echo "FAIL: runtime $label: --version produced no output"
        return 1
    fi
    magic=$(od -An -N4 -tx1 "$out" | tr -d ' \n')
    case "$magic" in
        7f454c46*) echo "FAIL: runtime $label: --version wrote $bytes bytes of ELF (compiled empty stdin)"; return 1 ;;
        4d5a*)     echo "FAIL: runtime $label: --version wrote $bytes bytes of PE/MZ (compiled empty stdin)"; return 1 ;;
        cffaedfe*) echo "FAIL: runtime $label: --version wrote $bytes bytes of Mach-O (compiled empty stdin)"; return 1 ;;
        435958*)   echo "FAIL: runtime $label: --version wrote $bytes bytes of CYX magic (compiled empty stdin)"; return 1 ;;
    esac
    lines=$(wc -l < "$out" | tr -d ' ')
    if [ "$lines" -ne 1 ]; then
        echo "FAIL: runtime $label: --version printed $lines lines (want exactly 1)"
        return 1
    fi
    got=$(awk '{print $2}' < "$out")     # the field the installed starship prompt reads
    if [ "$got" != "$VER" ]; then
        echo "FAIL: runtime $label: --version field 2 is '$got', VERSION says '$VER'"
        return 1
    fi
    echo "  runtime $label: $(tr -d '\n' < "$out")"
    return 0
}

build_fork() {   # $1 = source, $2 = out, $3.. = env prefix for the compiler
    src=$1; out=$2; shift 2
    if ! cat "$src" | env "$@" "$CC" > "$out" 2> "$T/b.err"; then
        echo "FAIL: build $src failed"
        head -3 "$T/b.err" || true
        return 1
    fi
    sz=$(wc -c < "$out" | tr -d ' ')
    if [ "$sz" -lt 1024 ]; then
        echo "FAIL: build $src produced $sz bytes (empty/truncated binary)"
        return 1
    fi
    chmod +x "$out"
    return 0
}

# main.cyr — the committed x86-Linux compiler, run directly.
assert_version "x86-linux (main.cyr)" "$CC" || exit 1

# main_cx.cyr — the cx driver is an x86-Linux ELF that emits .cyx.
build_fork src/main_cx.cyr "$T/cycc_cx" || exit 1
assert_version "cx (main_cx.cyr)" "$T/cycc_cx" || exit 1

# main_win.cyr — built by build/cycc it is an x86-Linux host binary that emits
# PE; built by ITSELF it is the shipped cycc.exe. Exercise both: the host stage
# natively, the PE stage under wine when wine is installed.
build_fork src/main_win.cyr "$T/cycc_win" || exit 1
assert_version "win host stage (main_win.cyr)" "$T/cycc_win" || exit 1
if ! cat src/main_win.cyr | "$T/cycc_win" > "$T/cycc.exe" 2>/dev/null; then
    echo "FAIL: build cycc.exe (main_win.cyr through its own host stage) failed"
    exit 1
fi
if command -v wine > /dev/null 2>&1; then
    WINEDEBUG=-all
    export WINEDEBUG
    assert_version "win PE under wine (main_win.cyr)" wine "$T/cycc.exe" || exit 1
    build_fork src/main_cx.cyr "$T/cx_win.exe" CYRIUS_TARGET_WIN=1 || exit 1
    assert_version "cx PE under wine (main_cx.cyr)" wine "$T/cx_win.exe" || exit 1
else
    echo "  note: wine absent — PE rows not executed (NOT hardware verification either way)"
fi

# main_aarch64.cyr — build/cycc turns it into an x86-Linux HOST cross-compiler
# (runs here); that cross turns it into the aarch64 binary (qemu-aarch64).
build_fork src/main_aarch64.cyr "$T/a64x" || exit 1
assert_version "aarch64 host cross (main_aarch64.cyr)" "$T/a64x" || exit 1
if ! cat src/main_aarch64.cyr | "$T/a64x" > "$T/a64" 2>/dev/null; then
    echo "FAIL: build the aarch64 stage of main_aarch64.cyr failed"
    exit 1
fi
chmod +x "$T/a64"
if ! cat src/main_aarch64_native.cyr | "$T/a64x" > "$T/a64n" 2>/dev/null; then
    echo "FAIL: build main_aarch64_native.cyr through the aarch64 cross failed"
    exit 1
fi
chmod +x "$T/a64n"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    assert_version "aarch64 ELF under qemu (main_aarch64.cyr)" qemu-aarch64 "$T/a64" || exit 1
    assert_version "aarch64 ELF under qemu (main_aarch64_native.cyr)" qemu-aarch64 "$T/a64n" || exit 1
else
    echo "  note: qemu-aarch64 absent — aarch64 rows built but not executed"
fi

# The two Mach-O drivers. Nothing on Linux can execute a Mach-O, so the runtime
# proof for these is the release gate's cross-OS leg on ecb/ach. Here: they must
# BUILD and the output must be a real Mach-O, so a driver that stopped compiling
# after a --version change is caught.
build_fork src/main_x86_macho.cyr "$T/macho_x86" CYRIUS_MACHO=1 || exit 1
# main_aarch64_macho.cyr needs the AARCH64 backend — build it through the host
# cross above, exactly as .github/workflows/ci.yml does.
if ! cat src/main_aarch64_macho.cyr | env CYRIUS_MACHO_ARM=1 "$T/a64x" > "$T/macho_arm" 2>/dev/null; then
    echo "FAIL: build main_aarch64_macho.cyr through the aarch64 cross failed"
    exit 1
fi
for m in "$T/macho_x86" "$T/macho_arm"; do
    mg=$(od -An -N4 -tx1 "$m" | tr -d ' \n')
    if [ "$mg" != "cffaedfe" ]; then
        echo "FAIL: $m is not a Mach-O (magic $mg)"
        exit 1
    fi
done
echo "  built: 2 Mach-O drivers (executed on ecb/ach by the release gate, not here)"

echo "PASS: all $NF src/main*.cyr drivers answer --version with $VER"
exit 0
