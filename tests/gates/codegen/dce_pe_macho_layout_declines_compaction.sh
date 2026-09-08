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
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC="$ROOT/build/cycc"
fail() { echo "FAIL: dce_pe_macho_layout_declines_compaction: $1"; exit 1; }
[ -x "$CYCC" ] || fail "build/cycc not found or not executable"

WORK=$(mktemp -d)
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

echo "PASS: dce_pe_macho_layout_declines_compaction (PE payload pinned at $A; Mach-O $MA B stable; ELF $EA -> $EB B)"
