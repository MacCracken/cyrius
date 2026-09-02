#!/bin/sh
# Gate: lazy-init publishes carry a RELEASE FENCE on aarch64 — and only on aarch64 (v6.5.39).
#
# THE DEFECT. v6.5.37 fixed the PROGRAM-ORDER half of the lazy-init class (fill a local,
# publish last) in `_chrono_init_mdays`. That is mutation-proven on x86: 0 of 400 threaded
# runs go wrong on the live tree against 29 of 400 with the pre-.37 publish-first shape.
# It does NOT fix the MEMORY-ORDER half. cyrius emits no ordering whatsoever for ordinary
# global access on aarch64 — a threaded aarch64 binary built from lib/chrono.cyr shows the
# guard read as a plain `ldr`, the publish as a plain `str`, and the whole binary containing
# zero `stlr`, zero `ldar`, and exactly one `dmb` (inside atomic_fence's own body). So on a
# weak model another thread can observe `_chrono_mdays` non-null before the twelve `store64`s
# that filled it — the same month-13 bug, one level down.
#
# ⚠ AARCH64 ONLY, AND THAT IS THE HALF MOST LIKELY TO BE "HELPFULLY" BROKEN. The proposal
# said to copy `lib/alloc.cyr:89-98`, which fences on BOTH arches. That is the OLD shape:
# x86-TSO already orders store-store, so a fence there is pure tax — measured ~22 ns, 83 %
# of the lock cost — and the project deliberately removed it in `lib/freelist.cyr:128-134`
# ("a correction, not an omission… the aarch64 release fence is REQUIRED and is kept").
# Axis 2 exists so nobody re-adds the x86 tax while "fixing" a fence.
#
# ⚠ WHY THERE IS NO RUNTIME TEST. qemu-aarch64 cannot settle this and that was PROVEN, not
# assumed: the known-broken pre-.37 mutant scores 0 bad runs in 150 under qemu, i.e. qemu
# does not exhibit the interleaving at all. Real pi hardware would not catch a 12-store
# window at any practical rate either. So the property is pinned at the CODEGEN level, which
# is exact and host-independent — the same reasoning as the f64v4 ymm disasm gate.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: lazy_init_release_fence: build/cycc missing"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: lazy_init_release_fence: $1"; exit 1; }

# ── axis 1: every lazy-init publish site is preceded by the fence ───────────────────
# Structural, and it is what catches a removal. The three sites are the ones a live-code
# sweep found; `lib/regex.cyr` is deliberately NOT among them (see axis 3's note).
check_site() {  # check_site <file> <publish-line-text> <label>
    awk -v pub="$2" -v lbl="$3" -v f="$1" '
        index($0, pub) && !seen {
            seen=1
            if (p1 !~ /#endif/ || p2 !~ /atomic_fence\(\)/ || p3 !~ /#ifdef CYRIUS_ARCH_AARCH64/) { exit 1 }
        }
        { p3=p2; p2=p1; p1=$0 }
        END { if (!seen) { exit 1 } }
    ' "$ROOT/$1" >/dev/null 2>&1 || {
        fail "axis 1: $3 in $1 has no aarch64-gated atomic_fence() immediately before its publishing store (or the site moved)"
    }
}
check_site "lib/chrono.cyr" "_chrono_mdays = t;"            "_chrono_mdays"
check_site "lib/tls.cyr"    "_tls_ok = 1;"                  "_tls_ok"
check_site "lib/tls.cyr"    "_tls_introspect_resolved = 1;" "_tls_introspect_resolved"

# ── axis 2: the fence is aarch64-GATED, never unconditional ────────────────────────
# ⛔ A both-arch fence would pass axis 1 and axis 3 while re-adding the x86 tax the project
# removed on purpose. Assert that neither file grew an ungated atomic_fence().
for f in lib/chrono.cyr lib/tls.cyr; do
    TOTAL=$(grep -c 'atomic_fence()' "$ROOT/$f" || true)
    GATED=$(grep -B1 'atomic_fence()' "$ROOT/$f" | grep -c '#ifdef CYRIUS_ARCH_AARCH64' || true)
    [ "$TOTAL" = "$GATED" ] || fail "axis 2: $f has $TOTAL atomic_fence() call(s) but only $GATED are #ifdef CYRIUS_ARCH_AARCH64-gated — an unguarded fence re-adds the ~22 ns x86 tax that lib/freelist.cyr deliberately removed"
done

# ── axis 3: the fence is ACTUALLY EMITTED on aarch64 ───────────────────────────────
# Differential, so it needs no source mutation and no aarch64 host: a probe that includes
# chrono must call into atomic_fence's body strictly MORE times than one that does not.
# ⚠ The baseline cannot be zero — lib/alloc.cyr fences on both arches (the old shape), so
# alloc-only already calls it. Comparing against zero would be vacuous; comparing the two
# is what isolates chrono's contribution.
command -v llvm-objdump >/dev/null 2>&1 || { echo "SKIP: llvm-objdump not available"; exit 0; }
cat "$ROOT/src/main_aarch64.cyr" | "$CC" > "$WORK/cc-a64" 2>/dev/null \
    || fail "axis 3: could not build the x86-hosted aarch64 emitter"
chmod +x "$WORK/cc-a64"

cat > "$WORK/with_chrono.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/chrono.cyr"
fn main(): i64 { alloc_init(); var d = epoch_to_date(1756512000); return load64(d + 8); }
var ec = main();
syscall(60, ec);
EOF
cat > "$WORK/no_chrono.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn main(): i64 { alloc_init(); var p = alloc(64); return 0; }
var ec = main();
syscall(60, ec);
EOF

( cd "$ROOT" && cat "$WORK/with_chrono.cyr" | "$WORK/cc-a64" > "$WORK/with.bin" ) 2>/dev/null \
    || fail "axis 3: the chrono probe did not compile for aarch64"
( cd "$ROOT" && cat "$WORK/no_chrono.cyr"   | "$WORK/cc-a64" > "$WORK/without.bin" ) 2>/dev/null \
    || fail "axis 3: the baseline probe did not compile for aarch64"

# Count `bl` whose target lands in the 64-byte window ending at the single `dmb ish`
# (atomic_fence's body). Addresses, not symbol names — these binaries carry no symtab.
# ⚠ The disassembly goes through a FILE, not a shell variable. A multi-MB `$(...)` capture
# came back empty under `sh` while working interactively — and an empty capture here reads as
# "no fence", i.e. a silent false FAIL. Same class as the unmatched-glob-scores-a-pass trap,
# one polarity over. `[[:space:]]` rather than `[ \t]`: inside a POSIX bracket expression
# `\t` is backslash-or-t, NOT a tab, so the original pattern only matched by luck.
count_fence_calls() {
    llvm-objdump -d --no-show-raw-insn "$1" > "$WORK/dis.txt" 2>/dev/null || { echo "-1"; return; }
    DMB=$(grep -E 'dmb[[:space:]]+ish' "$WORK/dis.txt" | head -1 | grep -oE '^ *[0-9a-f]+:' | tr -d ' :')
    [ -n "$DMB" ] || { echo "-1"; return; }
    grep -oE 'bl[[:space:]]+0x[0-9a-f]+' "$WORK/dis.txt" | grep -oE '0x[0-9a-f]+' \
      | awk -v d=$((16#$DMB)) '{ t=strtonum($0); if (t <= d && t >= d-64) n++ } END{print n+0}'
}
WITH=$(count_fence_calls "$WORK/with.bin")
WITHOUT=$(count_fence_calls "$WORK/without.bin")
[ "$WITH" != "-1" ] || fail "axis 3: no 'dmb ish' anywhere in the aarch64 chrono probe — atomic_fence was not linked at all, so the fence cannot be firing"
[ "$WITHOUT" -ge 1 ] || fail "axis 3 anti-vacuous: the baseline counted $WITHOUT calls into atomic_fence, but lib/alloc.cyr fences on aarch64 so it must be >= 1 — the counter is broken, not the fence"
[ "$WITH" -gt "$WITHOUT" ] || fail "axis 3: including lib/chrono.cyr added NO call into atomic_fence on aarch64 (with=$WITH, without=$WITHOUT) — the #ifdef is not firing and the publish is unordered"

echo "PASS: lazy_init_release_fence (3 publish sites fenced, aarch64-gated only, and the fence is emitted: $WITHOUT -> $WITH calls into atomic_fence)"
