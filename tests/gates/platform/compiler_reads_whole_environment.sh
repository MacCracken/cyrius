#!/bin/sh
# compiler_reads_whole_environment.sh — 6.6.20. The compiler sees its WHOLE environment, and a
# value too long for it is refused by name, never cut.
#
# `_read_env` (src/backend/common/env.cyr) — the reader behind every CYRIUS_* knob and target
# selector on every Linux-hosted fork — made ONE 8191-byte read of /proc/self/environ. Every
# entry past that byte was invisible, and the CLI APPENDS the selectors it injects
# (CYRIUS_TARGET_WIN, CYRIUS_PIE, CYRIUS_TARGET_AGNOS, CYRIUS_DCE, CYRIUS_KERNEL*) after the
# inherited environment, so in a shell over ~8 KB (nix, CI runners, a long PATH or LS_COLORS)
# `cyrius build --win` wrote an ELF and reported OK, rc 0. An entry straddling byte 8191 was
# read SHORT: CYRIUS_KERNEL_BASE=0x40000000 linked a kernel at 0x400. And Linux and macOS cut a
# value to 255 bytes and handed it back, so a long CYRIUS_SYMS path wrote the symbol dump over
# the file named by its 255-byte prefix (Windows already refused).
#
# Rows (every probe under `env -i`, so the layout is exact):
#   past8k   — a 9000-byte variable FIRST, then the selector: x86 CYRIUS_TARGET_WIN=1 -> MZ and
#              CYRIUS_PIE=1 -> ET_DYN; the aarch64 cross and (qemu) native compiler
#              CYRIUS_PIE=1 -> ET_DYN; cycc_cx CYRIUS_ASYNC=1 -> an async fn compiles.
#              Anti-vacuous: the same pad without the selector gives ELF / ET_EXEC / the refusal.
#   straddle — pads of 8121..8128 bytes put byte 8191 inside CYRIUS_KERNEL_BASE's value; the
#              kernel's entry must still be 0x400000a8 at every one.
#   long     — CYRIUS_SYMS of 255 bytes is honoured; of 256 bytes it is refused with a warning
#              naming CYRIUS_SYMS, writes nothing, and leaves the file at its 255-byte prefix
#              untouched.
#
# MUTATION LEDGER (6.6.20, scratch copies of src/, never the repo):
#   real tree                                       -> GREEN
#   _read_env's Linux arm restored to the 6.6.19 single 8191-byte read (cycc rebuilt)
#                                                   -> RED past8k x86 win + pie, straddle (8 pads), long 256
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: compiler_reads_whole_environment: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: compiler_reads_whole_environment: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: compiler_reads_whole_environment: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0
fail=0; rows=0
bad() { echo "  FAIL: compiler_reads_whole_environment $1"; fail=$((fail + 1)); }
row() { rows=$((rows + 1)); }
pad() { head -c "$1" /dev/zero | tr '\0' x; }
magic() { od -An -N2 -c "$1" | tr -d ' \n'; }
etype() { od -An -j16 -N2 -tx1 "$1" | tr -d ' \n'; }   # 0200 = ET_EXEC, 0300 = ET_DYN
BIG=$(pad 9000)

printf 'var x = 42;\nsyscall(60, x);\n' > "$T/p.cyr"
printf 'fn main(): i64 { return 42; }\n' > "$T/m.cyr"

# ── past8k: x86 ─────────────────────────────────────────────────────────────────────────
row; env -i PAD="$BIG" CYRIUS_TARGET_WIN=1 "$CC" < "$T/p.cyr" > "$T/o" 2>/dev/null
[ "$(magic "$T/o")" = MZ ] || bad "past8k x86 CYRIUS_TARGET_WIN=1 after a 9000-byte variable: magic '$(magic "$T/o")' (want MZ)"
row; env -i PAD="$BIG" "$CC" < "$T/p.cyr" > "$T/o" 2>/dev/null
[ "$(magic "$T/o")" = 177E ] || bad "past8k x86 control: no selector gave '$(magic "$T/o")' (want an ELF)"
row; env -i PAD="$BIG" CYRIUS_PIE=1 "$CC" < "$T/p.cyr" > "$T/o" 2>/dev/null
[ "$(etype "$T/o")" = 0300 ] || bad "past8k x86 CYRIUS_PIE=1 after a 9000-byte variable: e_type $(etype "$T/o") (want 0300, ET_DYN)"

# ── past8k: aarch64 + cx ────────────────────────────────────────────────────────────────
cat src/main_aarch64.cyr | "$CC" > "$T/a64x" 2>/dev/null && chmod +x "$T/a64x" \
    || { echo "FAIL: compiler_reads_whole_environment: building the aarch64 cross failed"; exit 1; }
cat src/main_cx.cyr | "$CC" > "$T/cx" 2>/dev/null && chmod +x "$T/cx" \
    || { echo "FAIL: compiler_reads_whole_environment: building cycc_cx failed"; exit 1; }
AF="a64_cross|$T/a64x"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    cat src/main_aarch64_native.cyr | "$T/a64x" > "$T/a64n" 2>/dev/null && chmod +x "$T/a64n" \
        || { echo "FAIL: compiler_reads_whole_environment: building the native aarch64 compiler failed"; exit 1; }
    AF="$AF
native_qemu|qemu-aarch64 $T/a64n"
else
    echo "  SKIP (named): native aarch64 row — qemu-aarch64 is not installed"
fi
printf '%s\n' "$AF" | while IFS='|' read -r l c; do
    env -i PAD="$BIG" CYRIUS_PIE=1 $c < "$T/m.cyr" > "$T/a" 2>/dev/null
    [ "$(etype "$T/a")" = 0300 ] || { echo "  FAIL: compiler_reads_whole_environment past8k $l CYRIUS_PIE=1 after a 9000-byte variable: e_type $(etype "$T/a") (want 0300)"; echo x >> "$T/red"; }
    env -i PAD="$BIG" $c < "$T/m.cyr" > "$T/a" 2>/dev/null
    [ "$(etype "$T/a")" = 0200 ] || { echo "  FAIL: compiler_reads_whole_environment past8k $l control: e_type $(etype "$T/a") (want 0200)"; echo x >> "$T/red"; }
    echo x >> "$T/nrows"; echo x >> "$T/nrows"
done
cat > "$T/as.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn five(): i64 { return 5; }
fn main(): i64 { alloc_init(); var f = five(); var v = await f; return v + 30; }
syscall(60, main());
EOF
row; rc=0; env -i PAD="$BIG" CYRIUS_ASYNC=1 "$T/cx" < "$T/as.cyr" > "$T/o" 2> "$T/e" || rc=$?
[ "$rc" = 0 ] || bad "past8k cx CYRIUS_ASYNC=1 after a 9000-byte variable: rc $rc ($(grep -m1 error "$T/e"))"
row; rc=0; env -i PAD="$BIG" "$T/cx" < "$T/as.cyr" > "$T/o" 2> "$T/e" || rc=$?
{ [ "$rc" = 1 ] && grep -q 'async fn requires CYRIUS_ASYNC=1' "$T/e"; } || bad "past8k cx control: rc $rc without CYRIUS_ASYNC (want the refusal)"
[ -f "$T/nrows" ] && rows=$((rows + $(wc -l < "$T/nrows")))
[ -f "$T/red" ] && fail=$((fail + $(wc -l < "$T/red")))

# ── straddle: byte 8191 inside CYRIUS_KERNEL_BASE's value ───────────────────────────────
# Layout under env -i: "PAD=<n>\0" (n+5) "CYRIUS_KERNEL=1\0" (16) "CYRIUS_ELF64_KERNEL=1\0" (22)
# then "CYRIUS_KERNEL_BASE=" (19) — the value spans bytes n+62 .. n+71, so 8121..8128 cut it.
printf 'kernel;\nvar x = 1;\n' > "$T/k.cyr"
n=8121
while [ $n -le 8128 ]; do
    row
    env -i PAD="$(pad $n)" CYRIUS_KERNEL=1 CYRIUS_ELF64_KERNEL=1 CYRIUS_KERNEL_BASE=0x40000000 "$CC" < "$T/k.cyr" > "$T/k" 2>/dev/null
    e=$(od -An -j24 -N8 -tx8 "$T/k" | tr -d ' \n')
    [ "$e" = 00000000400000a8 ] || bad "straddle pad $n: kernel entry 0x$e (want 0x400000a8 — CYRIUS_KERNEL_BASE read short)"
    n=$((n + 1))
done

# ── long: a value over 255 bytes is refused by name, never cut ──────────────────────────
printf 'fn f1(): i64 { return 42; }\nvar x = f1();\nsyscall(60, x);\n' > "$T/f.cyr"
D="$T/sy"; mkdir -p "$D"
mkpath() { b="$D/"; printf '%s%s' "$b" "$(head -c $(($1 - ${#b})) /dev/zero | tr '\0' s)"; }
P255=$(mkpath 255); P256=$(mkpath 256); PRE=$(printf %s "$P256" | head -c 255)
row; env -i CYRIUS_SYMS="$P255" "$CC" < "$T/f.cyr" > "$T/o" 2>/dev/null
grep -q ' f1$' "$P255" 2>/dev/null || bad "long: a 255-byte CYRIUS_SYMS path was not honoured (no symbol dump there)"
rm -f "$P255"; echo precious > "$PRE"
row; rc=0; env -i CYRIUS_SYMS="$P256" "$CC" < "$T/f.cyr" > "$T/o" 2> "$T/e" || rc=$?
[ "$rc" = 0 ] || bad "long: a 256-byte CYRIUS_SYMS failed the compile (rc $rc) — refusing the knob must not fail the build"
grep -q 'ignoring CYRIUS_SYMS: its value is longer than 255 bytes' "$T/e" || bad "long: a 256-byte CYRIUS_SYMS was not refused by name on stderr"
[ "$(cat "$PRE")" = precious ] || bad "long: the 256-byte path's 255-byte prefix was overwritten (the value was cut, not refused)"
[ ! -e "$P256" ] || bad "long: something was written at the 256-byte path"

if [ "$fail" -ne 0 ]; then echo "FAIL compiler_reads_whole_environment: $fail of $rows row(s) red"; exit 1; fi
echo "PASS compiler_reads_whole_environment: $rows rows — knobs past 8 KB honoured (x86, aarch64 cross + native, cx), a value straddling byte 8191 read whole, a 256-byte value refused by name"
exit 0
