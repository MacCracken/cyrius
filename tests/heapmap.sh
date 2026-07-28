#!/bin/sh
# Heap map audit — detects overlapping regions and tight gaps.
# Parses the authoritative heap map from src/main.cyr comments.
# Run: sh tests/heapmap.sh
# Exit 0 = clean, exit 1 = overlaps found.

set -e

MAIN="src/main.cyr"
if [ ! -f "$MAIN" ]; then
    echo "error: $MAIN not found (run from repo root)" >&2
    exit 1
fi

# Extract heap map entries from main.cyr.
# Format:  #   0xOFFSET  name  [BYTES]  description
# Some names have array syntax: name[N] — the [N] is element count, not byte size.
# The byte size is the LAST [NUMBER] on the line.

awk '
BEGIN { n = 0; errors = 0; warnings = 0 }

# Match heap map comment lines.
# v5.5.40: relaxed the space requirement from `  +` (2+) to ` +` (1+)
# — previously, entries where the hex offset was 7+ chars wide (e.g.
# 0x11A000, 0x150B000) had only ONE space before the name due to
# column alignment, which silently dropped them from the audit.
# Every region past 0xFC000 was invisible until this fix.
/^#   0x[0-9A-Fa-f]+ +[a-zA-Z_]/ {
    # Extract offset
    match($0, /0x[0-9A-Fa-f]+/)
    offset_str = substr($0, RSTART, RLENGTH)

    # Extract name (word after offset)
    split($0, parts)
    name = ""
    for (i = 1; i <= length(parts); i++) {
        if (parts[i] ~ /^0x/) {
            name = parts[i+1]
            break
        }
    }
    # Strip trailing array index from name for display
    gsub(/\[.*/, "", name)

    # Find byte size. v6.4.81 fixed TWO holes here that made this gate blind:
    #
    #  (a) The pattern was /\[([0-9]+)\]/ — a BARE integer only — so every map line
    #      whose size is written with a unit suffix was skipped entirely and the
    #      region simply did not exist as far as the auditor was concerned. That hid
    #      20.02 MB of LIVE heap: ir_nodes [16 MB], ir_cp [4 MB], lex_pp
    #      file-scratch [16KB] and the three PP #derive scratch regions. Worse than
    #      a missed region: the auditor then reported a phantom ~21.4 MB free gap
    #      above ir_live_out that is fully occupied, so a future allocation dropped
    #      "in the free space" would land inside ir_nodes and PASS.
    #
    #  (b) It took the LAST bracketed number on the line, so prose after the size
    #      won. The fn_param_struct_mask line ends (v6.3.36 issue [5]: bit N = ...
    #      and was parsed as FIVE BYTES — off by 13,107x. The same trap bit the
    #      v6.4.81 include_fname correction: the new map line carried the old
    #      0x190500 [256] in an explanatory parenthetical and the region was
    #      re-parsed as 256 B. Taking the FIRST bracketed size after the name fixes
    #      the class; keep prose on continuation lines regardless.
    #
    # Same parser-hole class as the v5.5.40 bug recorded in the header of this file
    # — a heap auditor that cannot see a region cannot guard it.
    # NOTE: this awk program is inside a SINGLE-QUOTED shell string. No apostrophes.
    size = 0
    line = $0
    if (match(line, /\[([0-9]+)[ ]?(KB|MB|K|M)?\]/, arr)) {
        size = arr[1] + 0
        unit = arr[2]
        if (unit == "KB" || unit == "K") { size = size * 1024 }
        else if (unit == "MB" || unit == "M") { size = size * 1048576 }
    }

    if (name != "" && size > 0) {
        # Skip entries marked (nested — intentionally inside a larger region
        if ($0 ~ /\(nested/) { next }
        offsets[n] = strtonum(offset_str)
        sizes[n] = size
        names[n] = name
        n++
    }
}

END {
    # Sort by offset (insertion sort)
    for (i = 1; i < n; i++) {
        j = i
        while (j > 0 && offsets[j] < offsets[j-1]) {
            t = offsets[j]; offsets[j] = offsets[j-1]; offsets[j-1] = t
            t = sizes[j]; sizes[j] = sizes[j-1]; sizes[j-1] = t
            t = names[j]; names[j] = names[j-1]; names[j-1] = t
            j--
        }
    }

    printf "Heap map: %d regions parsed from %s\n\n", n, "src/main.cyr"

    for (i = 0; i < n; i++) {
        end_addr = offsets[i] + sizes[i]
        printf "  0x%05X  +%-6d  -> 0x%05X  %s\n", offsets[i], sizes[i], end_addr, names[i]

        if (i < n - 1) {
            gap = offsets[i+1] - end_addr
            if (gap < 0) {
                printf "  ** OVERLAP: %s (ends 0x%05X) overlaps %s (starts 0x%05X) by %d bytes **\n", \
                    names[i], end_addr, names[i+1], offsets[i+1], -gap
                errors++
            } else if (gap >= 0 && gap < 16 && gap > 0) {
                printf "  ~~ WARNING: %d-byte gap before %s ~~\n", gap, names[i+1]
                warnings++
            }
        }
    }

    printf "\n"
    if (errors > 0) {
        printf "FAIL: %d overlap(s), %d warning(s)\n", errors, warnings
        exit 1
    } else {
        printf "PASS: no overlaps (%d regions, %d warnings)\n", n, warnings
    }
}
' "$MAIN"
