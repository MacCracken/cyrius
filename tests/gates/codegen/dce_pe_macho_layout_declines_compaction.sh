#!/bin/sh
# Gate: CYRIUS_DCE=1 must not corrupt PE or x86 Mach-O layout (v6.6.1).
#
# WHY THIS EXISTS. v6.5.72 turned CYRIUS_DCE=1 from NOP-padding into real elimination:
# `wp_compact` physically removes dead bodies and shrinks GCP(S). But `_pe_layout(S)` runs at
# the TOP of FIXUP (x86/fixup.cyr:123) off the PRE-elimination code length, so every PE geometry
# field — section sizes, RVAs, PointerToRawData, and the IAT RVA the ftype=4 fixups are patched
# against — describes a layout the emitted code no longer has. EMITPE_EXEC then writes .idata at
# the POST-compaction cursor (`o = o + cp`) while the section header still names the
# pre-compaction offset. Measured on the filed repro: the whole import payload moved 128,512 B
# earlier, so the loader mapped the Import Address Table from what had become zero padding,
# every import resolved to 0, and the first `call *IAT(%rip)` faulted 0xC0000005 BEFORE main.
#
# ⛔ IT WAS NEVER PE-ONLY. main_x86_macho.cyr includes the same x86/fixup.cyr, so Intel-Mac
# Mach-O took the identical path — it SIGSEGV'd (exit 139) on real ach hardware, shrinking
# 376,832 -> 32,768. The filing named only `--win` because the reporter does not build that
# platform. A PE-only guard would have shipped half the repair and left a silent
# shipped-artifact crash live on a supported target.
#
# ⭐ AXIS 3 IS NOT DECORATION. Axes 1-2 assert that DCE stops changing the layout on these two
# targets. DELETING DCE ENTIRELY WOULD SATISFY BOTH. Axis 3 pins that ELF still performs real
# elimination, so the decline is proven TARGET-SCOPED rather than a blanket disable. A gate that
# passes when the feature is gone would be worse than no gate.
#
# 6.6.18 — A DECLINE MUST SAY SO, AND WHY (axes 4-7). Every declining target printed exactly what
# a compacting one prints, `note: N unreachable fns (M bytes NOPed)`, so nothing told a user that
# the binary kept its dead bytes. The worst case was silent AND a cliff: on static x86 ELF, 4,096
# dead fns compact (4,456 B) and 4,097 do not (201,064 B), because the repair registry holds
# 4,096 runs and a saturated registry declines the whole pass. The reason rides INSIDE that note
# line — `(M bytes NOPed; compaction declined on <target>: <why>)` — so every downstream
# `grep -v "unreachable fns"` filter still removes it. Old compiler: axes 4 and 5 FAIL (measured:
# those builds printed only "N bytes NOPed").
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dce_pe_macho_layout_declines_compaction: cannot cd to $ROOT"; exit 1; }
CYCC="${CYCC:-$ROOT/build/cycc}"
fail() { echo "FAIL: dce_pe_macho_layout_declines_compaction: $1"; exit 1; }
[ -x "$CYCC" ] || fail "build/cycc not found or not executable"

WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: dce_pe_macho_layout_declines_compaction: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/src" "$WORK/lib"

# The defect needs the (unreachable) stdlib set present — a bare file links nothing, yields a
# ~2.5 KB image and does NOT reproduce. Vendor the same set the filed repro declares.
for m in string alloc vec str fmt io syscalls fs tagged process args fnptr thread \
         assert bench freelist hashmap; do
    [ -f "$ROOT/lib/$m.cyr" ] && cp "$ROOT/lib/$m.cyr" "$WORK/lib/$m.cyr"
done
# Pull in the per-OS sub-includes those modules dispatch to, so the Windows/macOS forks link.
for m in "$ROOT"/lib/*_win.cyr "$ROOT"/lib/*_windows.cyr "$ROOT"/lib/*_macos.cyr; do
    [ -f "$m" ] && cp "$m" "$WORK/lib/$(basename "$m")"
done

cat > "$WORK/src/main.cyr" <<'EOF'
fn main() {
    syscall(1, 1, "ok\n", 3);
    return 0;
}
EOF

# Build via the same include-prepend the CLI performs, without depending on a `cyrius` on PATH.
SRC="$WORK/all.cyr"
: > "$SRC"
for m in "$WORK"/lib/*.cyr; do cat "$m" >> "$SRC"; done
cat "$WORK/src/main.cyr" >> "$SRC"

build() {  # build <outfile> <env-assignments...>
    out="$1"; shift
    if ! env "$@" "$CYCC" < "$SRC" > "$out" 2>"$WORK/err.txt"; then
        fail "compile failed for $out: $(tail -1 "$WORK/err.txt")"
    fi
    [ -s "$out" ] || fail "compile produced an empty $out"
}

# ---- axis 1: PE import payload must not move under DCE -------------------------------------
build "$WORK/pe_off.exe" CYRIUS_TARGET_WIN=1
build "$WORK/pe_dce.exe" CYRIUS_TARGET_WIN=1 CYRIUS_DCE=1

pe_marker() { grep -abo 'ExitProcess' "$1" | head -1 | cut -d: -f1; }
A=$(pe_marker "$WORK/pe_off.exe")
B=$(pe_marker "$WORK/pe_dce.exe")
[ -n "$A" ] || fail "axis 1: no ExitProcess import string in the non-DCE PE — repro no longer valid"
[ -n "$B" ] || fail "axis 1: no ExitProcess import string in the DCE PE — import payload destroyed"
if [ "$A" != "$B" ]; then
    fail "axis 1: PE import payload MOVED under CYRIUS_DCE=1 ($A -> $B). The section header still
      names the pre-compaction offset, so the loader maps the IAT from zero padding and the
      first call *IAT(%rip) faults 0xC0000005 at startup."
fi

# ---- axis 2: x86 Mach-O layout must not move under DCE ------------------------------------
build "$WORK/mo_off" CYRIUS_MACHO=1
build "$WORK/mo_dce" CYRIUS_MACHO=1 CYRIUS_DCE=1
MA=$(wc -c < "$WORK/mo_off" | tr -d ' ')
MB=$(wc -c < "$WORK/mo_dce" | tr -d ' ')
if [ "$MA" != "$MB" ]; then
    fail "axis 2: x86 Mach-O image size changed under CYRIUS_DCE=1 ($MA -> $MB). Same root cause
      as axis 1 via main_x86_macho.cyr's include of x86/fixup.cyr; this SIGSEGV'd on real
      Intel-Mac hardware."
fi

# ---- axis 3: ANTI-VACUOUS — ELF must still really eliminate --------------------------------
build "$WORK/elf_off" CYRIUS_DCE_UNSET=1
build "$WORK/elf_dce" CYRIUS_DCE=1
EA=$(wc -c < "$WORK/elf_off" | tr -d ' ')
EB=$(wc -c < "$WORK/elf_dce" | tr -d ' ')
if [ "$EB" -ge "$EA" ]; then
    fail "axis 3: ELF did NOT shrink under CYRIUS_DCE=1 ($EA -> $EB). The PE/Mach-O decline has
      become a blanket disable — axes 1-2 would then pass with the feature deleted."
fi

# ---- axes 4-7: a decline is REPORTED, inside the unreachable-fns note, with its reason -------
# A small probe with exactly three dead fns; `shared;` needs its own copy (the directive is first).
cat > "$WORK/p3.cyr" <<'EOF'
fn dead_a(x): i64 { return x + 1; }
fn dead_b(x): i64 { return x * 2; }
fn dead_c(x): i64 { return x - 3; }
fn main(): i64 { return 7; }
var e = main();
EOF
{ echo 'shared;'; cat "$WORK/p3.cyr"; } > "$WORK/p3s.cyr"
# A dead fn the length decoder refuses (0x06 is invalid in 64-bit mode), so nothing is NOP-safe:
# dead code present, zero bytes padded.
printf 'fn dead_x(): i64 {\n    asm { 0x06; }\n    return 0;\n}\nfn main(): i64 { return 7; }\nvar e = main();\n' > "$WORK/p0.cyr"

pbuild() {  # pbuild <compiler> <src> <errfile> <env-assignments...> — stderr kept for the axes
    pcc="$1"; psrc="$2"; perr="$3"; shift 3
    prc=0
    env "$@" "$pcc" < "$psrc" > "$WORK/p.out" 2> "$perr" || prc=$?
    [ "$prc" = 0 ] || fail "compile of $(basename "$psrc") failed (rc $prc): $(tail -1 "$perr")"
    [ -s "$WORK/p.out" ] || fail "compile of $(basename "$psrc") produced an empty binary"
}
declined() {  # declined <axis> <errfile> <target word> <reason word>
    dn=$(grep -c 'compaction declined' "$2" || true)
    [ "$dn" = 1 ] || fail "$1: expected exactly one 'compaction declined on $3' report, got $dn: $(cat "$2")"
    dl=$(grep 'compaction declined' "$2")
    printf '%s\n' "$dl" | grep -Eq '^note: [0-9]+ unreachable fns \([0-9]+ bytes NOPed; compaction declined on ' \
        || fail "$1: the decline is not carried INSIDE the unreachable-fns note (a line of its own escapes every grep -v 'unreachable fns' filter): $dl"
    printf '%s\n' "$dl" | grep -Fq "declined on $3: " || fail "$1: wrong target word (want '$3'): $dl"
    printf '%s\n' "$dl" | grep -Fq "$4" || fail "$1: the reason does not name '$4': $dl"
}

# axis 4: each x86 decline path names its target and its reason
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a4pe.err" CYRIUS_DCE=1 CYRIUS_TARGET_WIN=1
declined "axis 4 (PE)" "$WORK/a4pe.err" "PE" "import table"
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a4mo.err" CYRIUS_DCE=1 CYRIUS_MACHO=1
declined "axis 4 (x86 Mach-O)" "$WORK/a4mo.err" "x86_64 Mach-O" "stub table"
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a4pie.err" CYRIUS_DCE=1 CYRIUS_PIE=1
declined "axis 4 (--pie)" "$WORK/a4pie.err" "x86_64 ELF (--pie)" "position-independent"
pbuild "$CYCC" "$WORK/p3s.cyr" "$WORK/a4so.err" CYRIUS_DCE=1
declined "axis 4 (shared;)" "$WORK/a4so.err" "x86_64 ELF (shared;)" "shared object"

# axis 5: the registry cliff, pinned on both sides. 4,096 one-line dead fns compact; 4,097
# saturate the 4,096-run registry and the whole pass declines — the reason must say exactly that.
for n in 4096 4097; do
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "fn d%d(): i64 { return %d; }\n", i, i;
                           print "fn main(): i64 { return 7; }"; print "var e = main();" }' > "$WORK/g$n.cyr"
    pbuild "$CYCC" "$WORK/g$n.cyr" "$WORK/a5_$n.err" CYRIUS_DCE=1
done
grep -q 'dead code eliminated' "$WORK/a5_4096.err" \
    || fail "axis 5: 4096 dead fns no longer compact — the cliff moved; re-measure it: $(cat "$WORK/a5_4096.err")"
if grep -q 'compaction declined' "$WORK/a5_4096.err"; then fail "axis 5: 4096 dead fns compacted AND reported a decline"; fi
declined "axis 5 (4097 dead fns)" "$WORK/a5_4097.err" "x86_64 ELF" "more than 4096 dead-code runs"
if grep -q 'dead code eliminated' "$WORK/a5_4097.err"; then fail "axis 5: 4097 dead fns reported a decline AND an elimination"; fi

# axis 6 (anti-vacuous): the compacting target says it compacted, and reports NO decline
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a6.err" CYRIUS_DCE=1
grep -q 'dead code eliminated' "$WORK/a6.err" || fail "axis 6: static x86 ELF no longer compacts the probe: $(cat "$WORK/a6.err")"
if grep -q 'compaction declined' "$WORK/a6.err"; then fail "axis 6: static x86 ELF compacted and ALSO reported a decline: $(cat "$WORK/a6.err")"; fi

# axis 7: nothing padded, nothing to decline — a PE build whose only dead fn is not NOP-safe
# reports "0 bytes NOPed" and no decline (anti-vacuous: the note itself must be there)
pbuild "$CYCC" "$WORK/p0.cyr" "$WORK/a7.err" CYRIUS_DCE=1 CYRIUS_TARGET_WIN=1
grep -q '^note: 1 unreachable fns (0 bytes NOPed' "$WORK/a7.err" \
    || fail "axis 7: the probe no longer yields a dead fn with 0 NOP-safe bytes — it proves nothing: $(cat "$WORK/a7.err")"
if grep -q 'compaction declined' "$WORK/a7.err"; then fail "axis 7: a PE build that padded 0 bytes reported a decline: $(cat "$WORK/a7.err")"; fi

# axis 8: every aarch64 target NOP-fills only, and says so. One FIXUP call site covers aarch64 ELF,
# native aarch64 and arm64 Mach-O, so the cross-compiler is built from THIS tree (never a stale
# build/cycc_aarch64). Target word and reason are asserted — NOT a NOP byte count, which moves
# whenever aarch64 codegen changes size.
xrc=0
"$CYCC" < src/main_aarch64.cyr > "$WORK/cc_x" 2> "$WORK/cc_x.err" || xrc=$?
[ "$xrc" = 0 ] && [ -s "$WORK/cc_x" ] || fail "axis 8: cannot cross-build cycc_aarch64 from src/main_aarch64.cyr (rc $xrc): $(tail -1 "$WORK/cc_x.err")"
chmod +x "$WORK/cc_x"
pbuild "$WORK/cc_x" "$WORK/p3.cyr" "$WORK/a8elf.err" CYRIUS_DCE=1
declined "axis 8 (aarch64 ELF)" "$WORK/a8elf.err" "aarch64 ELF" "no compaction repair model"
pbuild "$WORK/cc_x" "$WORK/p3.cyr" "$WORK/a8mo.err" CYRIUS_DCE=1 CYRIUS_MACHO_ARM=1
declined "axis 8 (arm64 Mach-O)" "$WORK/a8mo.err" "arm64 Mach-O" "no compaction repair model"

# axis 9: with CYRIUS_DCE UNSET, the hint stops promising elimination on a target that cannot
# eliminate. It read "set CYRIUS_DCE=1 to eliminate" everywhere (dce_eliminates.sh:5 records the
# same broken promise from v6.5.72); a declining target now says NOP-fill, and why.
hinted() {  # hinted <axis> <errfile> <target word>
    hl=$(grep 'unreachable fns' "$2" || true)
    [ -n "$hl" ] || fail "$1: no unreachable-fns note at all — the probe proves nothing: $(cat "$2")"
    if printf '%s\n' "$hl" | grep -q 'to eliminate'; then fail "$1: the hint still promises elimination on $3: $hl"; fi
    printf '%s\n' "$hl" | grep -Eq '^note: [0-9]+ unreachable fns \([0-9]+ bytes .*set CYRIUS_DCE=1 to NOP-fill them; no compaction on ' \
        || fail "$1: the hint does not say NOP-fill (inside the unreachable-fns note): $hl"
    printf '%s\n' "$hl" | grep -Fq "no compaction on $3: " || fail "$1: wrong target word (want '$3'): $hl"
}
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a9pe.err" CYRIUS_TARGET_WIN=1
hinted "axis 9 (PE)" "$WORK/a9pe.err" "PE"
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a9mo.err" CYRIUS_MACHO=1
hinted "axis 9 (x86 Mach-O)" "$WORK/a9mo.err" "x86_64 Mach-O"
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a9pie.err" CYRIUS_PIE=1
hinted "axis 9 (--pie)" "$WORK/a9pie.err" "x86_64 ELF (--pie)"
pbuild "$WORK/cc_x" "$WORK/p3.cyr" "$WORK/a9a64.err" CYRIUS_DCE_UNSET=1
hinted "axis 9 (aarch64 ELF)" "$WORK/a9a64.err" "aarch64 ELF"
# the eliminating target past the 4,096-run registry: =1 would decline, so unset must not promise
pbuild "$CYCC" "$WORK/g4097.cyr" "$WORK/a9cap.err" CYRIUS_DCE_UNSET=1
hinted "axis 9 (4097 dead fns, unset)" "$WORK/a9cap.err" "x86_64 ELF"
grep -q 'more than 4096 dead-code runs' "$WORK/a9cap.err" || fail "axis 9 (4097 dead fns, unset): the hint does not name the registry cap: $(cat "$WORK/a9cap.err")"
# anti-vacuous: the one target that DOES eliminate keeps the promise, word for word
pbuild "$CYCC" "$WORK/p3.cyr" "$WORK/a9elf.err" CYRIUS_DCE_UNSET=1
grep -q '^note: [0-9]* unreachable fns ([0-9]* bytes .*set CYRIUS_DCE=1 to eliminate, CYRIUS_DCE_VERBOSE=1 to list)$' "$WORK/a9elf.err" \
    || fail "axis 9 (static x86 ELF): the eliminating target lost its 'set CYRIUS_DCE=1 to eliminate' hint: $(cat "$WORK/a9elf.err")"

echo "PASS: dce_pe_macho_layout_declines_compaction (PE payload pinned at $A; Mach-O $MA B stable; ELF $EA -> $EB B; declines named on PE, x86 Mach-O, --pie, shared;, aarch64 ELF, arm64 Mach-O and past the 4096-run registry; the unset hint promises elimination only where it happens)"
