#!/bin/sh
# Heap map audit — detects overlapping regions and tight gaps.
# Parses the authoritative heap map from src/main.cyr comments.
# Run: sh tests/gates/memory/heapmap.sh
# Exit 0 = clean, exit 1 = overlaps found.

set -e

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: heapmap: cannot cd to $ROOT"; exit 1; }

MAIN="src/main.cyr"
if [ ! -f "$MAIN" ]; then
    echo "error: $MAIN not found (cwd: $(pwd))" >&2
    exit 1
fi
FAILS=0

# 6.6.20 (HEAP-05): src/main.cyr is the ONE heap map. This gate used to read it and
# nothing else, while four of the six fork drivers carried their own map copies — and
# those had drifted: run through the parser below, the three aarch64 forks each reported
# an overlap (lexid_entries still mapped at its pre-v6.4.21 0x457C900) and main_win
# three (ir_nodes at 0xA3A000, ir_cp at 0xF7B000, lexid), under a header that still
# read "Authoritative offset registry (v3.6.10)". All seven drivers share one layout,
# so the copies were documentation that nothing checked. A fork now carries a pointer
# to main.cyr, and any map-shaped line in one fails here. The floor keeps an empty glob
# from passing vacuously.
NFORK=$(ls src/main_*.cyr 2>/dev/null | wc -l)
if [ "$NFORK" -lt 6 ]; then
    echo "FAIL: heapmap: expected at least 6 fork drivers src/main_*.cyr, found $NFORK"
    exit 1
fi
FORK_MAP=$(grep -nE '^#[[:space:]]{3,}0x[0-9A-Fa-f]+[[:space:]]+[a-zA-Z_(]' src/main_*.cyr || true)
if [ -n "$FORK_MAP" ]; then
    echo "FAIL: heapmap: a fork driver carries heap-map lines — src/main.cyr is the only map"
    echo "$FORK_MAP" | head -20 | sed 's/^/    /'
    FAILS=$((FAILS + 1))
fi

# Source files the reference check reads (every src/ module, main.cyr included). The floor
# keeps a broken find from making the check vacuous: there are 36 compiler modules (6.6.20).
SRCS=$(find src -name '*.cyr' | sort)
NSRC=$(printf '%s\n' "$SRCS" | grep -c . || true)
if [ "$NSRC" -lt 30 ]; then
    echo "FAIL: heapmap: expected at least 30 compiler sources under src/, found $NSRC"
    exit 1
fi

# Extract heap map entries from main.cyr.
# Format:  #   0xOFFSET  name  [BYTES]  description
# Some names have array syntax: name[N] — the [N] is element count, not byte size.
# The byte size is the FIRST bracketed size on the line (see below).
#
# 6.6.20 — TWO LAYOUTS, and the map tags which one a region belongs to. The cx bytecode
# driver (src/main_cx.cyr) shares every other driver's layout but adds regions of its own:
#   (cx only)  the region exists only in the cx driver's layout
#   (not cx)   the cx driver never touches it (it is free there)
#   (nested    the region deliberately sits inside another one (skipped by the overlap
#              checks, which is what the tag has always meant; still reference-checked)
# The overlap check runs once per layout: the shared layout is every untagged and
# (not cx) region, the cx layout every untagged and (cx only) one.
#
# 6.6.20 (HEAP-07) — every mapped region must be NAMED BY CODE: its offset must appear as
# a hex literal in code (comments and strings stripped) of the layout it belongs to — a
# (cx only) region in src/main_cx.cyr or src/backend/cx/, any other region outside them.
# The map had three regions no code of their layout used: pub_flags (never written or
# read), ir_edges (written, capped at 8192, never read — its writer is gone), and the 3 MB
# codebuf at 0x41A000, which since v6.4.49 only the cx driver touched. A phantom map entry
# is not harmless: the map is machine-read, so it reserves bytes and hides real overlaps
# (the v6.5.26 "DCE bitmap" phantom manufactured one).
#
# 6.6.20 (HEAP-06) — and the converse: every `S + 0x…` literal in code must land inside a
# region of its layout, or be the arena end the `brk-final` line records (no region may end
# past it either). The map was missing live state: the three WP-compaction registries at
# 0x60000-0x100000 (since v6.5.68, under a sentence calling that band FREE), the PP
# #derive/include/#if band at 0x197000, the pp-flag VALUES at 0x190880, the cx driver's
# bytecode buffer and fixup table, and five size-less lines the parser skipped (the core
# scalars, the fn state, the macro tables, eight fn tables). The macro-table line, once it
# had a size, showed the #ref read buffer and the macro tables time-share 14 KB — now a
# recorded invariant instead of an accident.

awk -v mainf="$MAIN" '
BEGIN { n = 0; errors = 0; warnings = 0; arena_end = 0; nlit = 0 }

function is_cx_file(f) {
    return (f ~ /(^|\/)main_cx\.cyr$/ || f ~ /(^|\/)backend\/cx\//)
}
function in_layout(i, lay) {
    if (nest[i]) { return 0 }
    if (lay == "shared") { return !cxo[i] }
    return !notcx[i]
}
# Sort the regions of one layout by offset and report overlaps (and, for the shared
# layout, the listing and tight gaps). Returns the overlap count.
function check_layout(lay, listing,    idx, m, i, j, k, t, e, gap, errs) {
    m = 0
    for (i = 0; i < n; i++) { if (in_layout(i, lay)) { idx[m] = i; m++ } }
    for (i = 1; i < m; i++) {
        j = i
        while (j > 0 && offsets[idx[j]] < offsets[idx[j-1]]) {
            t = idx[j]; idx[j] = idx[j-1]; idx[j-1] = t
            j--
        }
    }
    errs = 0
    for (k = 0; k < m; k++) {
        i = idx[k]
        e = offsets[i] + sizes[i]
        if (listing) { printf "  0x%05X  +%-6d  -> 0x%05X  %s\n", offsets[i], sizes[i], e, names[i] }
        if (k < m - 1) {
            j = idx[k+1]
            gap = offsets[j] - e
            if (gap < 0) {
                printf "  ** OVERLAP (%s layout): %s (ends 0x%05X) overlaps %s (starts 0x%05X) by %d bytes **\n", \
                    lay, names[i], e, names[j], offsets[j], -gap
                errs++
            } else if (listing && gap > 0 && gap < 16) {
                printf "  ~~ WARNING: %d-byte gap before %s ~~\n", gap, names[j]
                warnings++
            }
        }
    }
    nlay[lay] = m
    return errs
}

# Match heap map comment lines (main.cyr only).
# v5.5.40: relaxed the space requirement from `  +` (2+) to ` +` (1+)
# — previously, entries where the hex offset was 7+ chars wide (e.g.
# 0x11A000, 0x150B000) had only ONE space before the name due to
# column alignment, which silently dropped them from the audit.
# Every region past 0xFC000 was invisible until this fix.
FILENAME == mainf && /^#   0x[0-9A-Fa-f]+ +[a-zA-Z_]/ {
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

    if (name == "brk-final") { arena_end = strtonum(offset_str) }
    if (name != "" && size > 0) {
        offsets[n] = strtonum(offset_str)
        sizes[n] = size
        names[n] = name
        nest[n] = ($0 ~ /\(nested/) ? 1 : 0
        cxo[n] = ($0 ~ /\(cx only\)/) ? 1 : 0
        notcx[n] = ($0 ~ /\(not cx\)/) ? 1 : 0
        if (cxo[n] && notcx[n]) {
            printf "  ** %s is tagged both (cx only) and (not cx) **\n", name
            errors++
        }
        n++
    }
    next
}

# Code lines of every source: collect the hex literals each layout names.
{
    code = $0
    if (code ~ /^[ \t]*#/) { next }
    gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
    sub(/#.*/, "", code)
    cxf = is_cx_file(FILENAME)
    scan = code
    while (match(scan, /(^|[^A-Za-z0-9_])S[ \t]*\+[ \t]*0x[0-9A-Fa-f]+/)) {
        ms = RSTART; ml = RLENGTH
        lit = substr(scan, ms, ml)
        sub(/^.*0x/, "0x", lit)
        key = (cxf ? "cx" : "shared") SUBSEP strtonum(lit)
        if (!(key in litwhere)) { litwhere[key] = FILENAME ":" FNR; nlit++ }
        scan = substr(scan, ms + ml)
    }
    while (match(code, /0x[0-9A-Fa-f]+/)) {
        v = strtonum(substr(code, RSTART, RLENGTH))
        if (cxf) { refcx[v] = 1 } else { refshared[v] = 1 }
        code = substr(code, RSTART + RLENGTH)
    }
}

END {
    printf "Heap map: %d regions parsed from %s\n\n", n, mainf
    errors += check_layout("shared", 1)
    errors += check_layout("cx", 0)
    printf "\n  shared layout: %d regions; cx layout: %d regions\n", nlay["shared"], nlay["cx"]

    unref = 0
    for (i = 0; i < n; i++) {
        if (cxo[i]) {
            if (!(offsets[i] in refcx)) {
                printf "  ** UNREFERENCED: %s at 0x%X is (cx only), but no cx code (src/main_cx.cyr, src/backend/cx/) names that offset **\n", names[i], offsets[i]
                unref++
            }
        } else if (!(offsets[i] in refshared)) {
            if (offsets[i] in refcx) {
                printf "  ** UNREFERENCED: %s at 0x%X is named only by cx code — tag it (cx only), or free it **\n", names[i], offsets[i]
            } else {
                printf "  ** UNREFERENCED: %s at 0x%X — no code names that offset (a phantom region: free it) **\n", names[i], offsets[i]
            }
            unref++
        }
    }
    errors += unref

    # The arena end, and every `S + 0x…` literal inside a region of its layout.
    if (arena_end == 0) {
        printf "  ** no `brk-final` line: the map must record the arena end **\n"
        errors++
    }
    for (i = 0; i < n; i++) {
        if (arena_end > 0 && offsets[i] + sizes[i] > arena_end) {
            printf "  ** %s ends 0x%X, past the arena end 0x%X (brk-final) **\n", names[i], offsets[i] + sizes[i], arena_end
            errors++
        }
    }
    if (nlit < 100) {
        printf "  ** only %d distinct S + 0x... literals found under src/ — the scan is broken **\n", nlit
        errors++
    }
    unmapped = 0
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (key in litwhere) {
        split(key, kp, SUBSEP)
        lay = kp[1]
        v = kp[2] + 0
        if (v == arena_end) { continue }
        hit = 0
        for (i = 0; i < n; i++) {
            if (lay == "shared" && cxo[i]) { continue }
            if (lay == "cx" && notcx[i]) { continue }
            if (v >= offsets[i] && v < offsets[i] + sizes[i]) { hit = 1; break }
        }
        if (!hit) {
            printf "  ** UNMAPPED: S + 0x%X (%s) lies in no %s-layout region of the map **\n", v, litwhere[key], lay
            unmapped++
        }
    }
    errors += unmapped
    printf "  %d distinct S + 0x... literals checked against the map\n", nlit

    printf "\n"
    if (errors > 0) {
        printf "FAIL: %d error(s) (overlaps, unreferenced or unmapped regions), %d warning(s)\n", errors, warnings
        exit 1
    } else {
        printf "PASS: no overlaps, every region named by code, every literal mapped (%d regions, %d warnings)\n", n, warnings
    }
}
' $SRCS || FAILS=$((FAILS + 1))

if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: heapmap: $FAILS check(s) failed"
    exit 1
fi
