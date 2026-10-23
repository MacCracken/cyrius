#!/bin/sh
# cbt_readers_recursive.sh — 6.7.18 (the refactor review: cbt/commands.cyr and cbt/deps.cyr split into
# cbt/commands/ and cbt/deps/).
#
# EVERY READER OF THE CLI'S SOURCE READS cbt/ RECURSIVELY.
#
# THE DEFECT. Twenty-two gates read the CLI's source through a flat `cbt/*.cyr` glob (or
# `"$ROOT"/cbt/*.cyr`, `ls cbt/*.cyr`, python's `'cbt/*.cyr'`): the fork-site, exec-site, temp-name,
# write-length, manifest-read, scp-pillar, raw-syscall and tool-lookup scans, the auto-deps verb
# graph, the include census. The verb and stage split moves the bulk of the CLI one level down, and a
# flat glob skips a subfolder in silence: each of those scans would have read core.cyr, build.cyr and
# the rest, found nothing wrong in what it read, and passed over the two files that hold most of the
# CLI. A floor of "8 files" or "10 files" does not notice — the top level still holds that many. The
# same class as the flat `tests/tcyr/*.tcyr` glob CLAUDE.md forbids. CHANGELOG [6.7.18]
#
# WHAT IS PINNED (static): no line of a gate, a script or a workflow — comments excluded — spells a
# flat glob over cbt/ (`cbt/*.cyr`, with any prefix). The readers use `find cbt -name '*.cyr'` (or
# `cbt/**/*.cyr` with python's recursive glob). The scanner is self-tested on a fixture: the four
# flat spellings are flagged, a comment and the two recursive spellings are not. Floor: the census
# reads every tracked gate (>= 500 files), so a broken reader cannot read green.
#
# AXIS 2 — THE INCLUDE LIST AND ITS MIRRORS. cbt/cyrius.cyr includes the split pieces itself, one
# after another (one parent, no nesting), and the tests that compile the CLI's modules
# (tests/tcyr/crossos/cli_*.tcyr, embed_open_under_root.tcyr) copy that include list by hand. Pinned:
# every .cyr under cbt/ but the entry is included exactly once — by cbt/cyrius.cyr's main block, or
# by another cbt/ file (core.cyr's srcscan.cyr) — and every .tcyr that includes a piece of a cbt/
# subfolder carries cbt/cyrius.cyr's cbt/ include list exactly, in its order (a dropped or reordered
# piece is named). Floors: the list holds >= 30 files, >= 5 mirrors are compared.
#
# AXIS 3 — NO POINTER TO THE SPLIT FILES. After the split, fourteen source comments in cbt/,
# lib/ and programs/ (and two gate headers) still sent a reader to cbt/commands.cyr or
# cbt/deps.cyr — "the sanctioned predicate (cbt/deps.cyr)", "see deps.cyr:_dep_is_cyrius_source_
# repo", "(~line 566 of this file)" — files that no longer exist. Pinned: no line of cbt/, lib/,
# programs/, src/ or scripts/ names `cbt/commands.cyr` / `cbt/deps.cyr` (or the bare
# `commands.cyr` / `deps.cyr`), but the 6.7.18 split notes ("split from / of cbt/…") and the
# HISTORY list below — sentences about a past release that were true of the file as it stood. A
# history entry that matches no line is RED too, so the list cannot outlive its sentence, and it is
# the axis's floor: the scan must find all of them. (The gates' mutation ledgers are history and
# are not scanned.)
#
# MUTATION LEDGER (measured at 6.7.18):
#   M1  the parent of this gate (the 22 flat readers)                        -> RED, 35 lines named
#   M2  one reader turned back (cbt_fork_sites_have_pe_arm.sh `scan cbt/*.cyr`) -> RED, that line
#   M3  cbt/commands/clean.cyr dropped from cli_dry_pass_mute.tcyr's include list -> RED, axis 2 names it
#   M4  cbt/commands/clean.cyr dropped from cbt/cyrius.cyr                    -> RED, axis 2 (not included)
#   M5  the parent of axis 3 (the fourteen stale pointers)                    -> RED, axis 3 names each
#   M6  one history sentence reworded (cbt/cyrius.cyr's v5.11.17 note)          -> RED, axis 3 (both ways)
#   Real tree -> GREEN.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
NAME=cbt_readers_recursive
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0

# flat <file>... — every non-comment line that globs cbt/ one level deep, as file:line:text.
flat() {
    awk '{ c = $0; sub(/^[ \t]*/, "", c); if (substr(c, 1, 1) == "#") next
           if (index($0, "cbt/*.cyr") > 0) printf "%s:%d:%s\n", FILENAME, FNR, $0 }' "$@"
}

# ── self-test ────────────────────────────────────────────────────────────────────────────
cat > "$W/fx.sh" <<'FX'
scan cbt/*.cyr > "$T/sites"
for f in "$ROOT"/cbt/*.cyr; do :; done
nfiles=$(ls cbt/*.cyr | wc -l)
files = glob.glob('cbt/*.cyr')
# a comment naming cbt/*.cyr is prose
for f in $(find cbt -name '*.cyr' | LC_ALL=C sort); do :; done
files = glob.glob('cbt/**/*.cyr', recursive=True)
FX
got=$(flat "$W/fx.sh" | cut -d: -f2 | tr '\n' ' ')
if [ "$got" = "1 2 3 4 " ]; then
    echo "  ok: self-test — the four flat spellings are flagged; a comment and the two recursive readers are not"
else
    echo "  FAIL: self-test — the scanner flagged lines [$got], want [1 2 3 4 ]"
    fail=1
fi

# ── the census ──────────────────────────────────────────────────────────────────────────
git ls-files 'tests/gates/*.sh' 'scripts/*.sh' 'scripts/*' '.github/workflows/*.yml' 2>/dev/null \
    | LC_ALL=C sort -u > "$W/files"
nf=$(grep -c . "$W/files" || true); [ -n "$nf" ] || nf=0
ng=$(grep -c '^tests/gates/' "$W/files" || true); [ -n "$ng" ] || ng=0
if [ "$ng" -lt 500 ]; then
    echo "  FAIL: the census read only $ng tracked gate(s) (floor 500) — the reader is not reading"
    fail=1
fi
: > "$W/hits"
while IFS= read -r f; do
    [ -f "$f" ] || continue
    # this file spells the flat glob on purpose: its fixture and its matcher
    [ "$f" = "tests/gates/toolchain/$NAME.sh" ] && continue
    flat "$f" >> "$W/hits"
done < "$W/files"
if [ -s "$W/hits" ]; then
    echo "  FAIL: a reader globs cbt/ one level deep — it skips cbt/commands/ and cbt/deps/ in silence (use find cbt -name '*.cyr'):"
    sed 's/^/    /' "$W/hits"
    fail=1
else
    echo "  ok: no flat cbt/ glob in $nf gates, scripts and workflows ($ng gates)"
fi

# ── axis 2: the include list and its mirrors ─────────────────────────────────────────────
# cbt_incs <file> — its `include "cbt/…"` lines, in order (an indented or commented line is not one).
cbt_incs() { sed -n 's/^include "\(cbt\/[^"]*\)".*/\1/p' "$1"; }
awk '/^#ifndef CYRIUS_TARGET_AGNOS/ { on = 1 } on' cbt/cyrius.cyr > "$W/main.cyr"
cbt_incs "$W/main.cyr" > "$W/list"
nl=$(grep -c . "$W/list" || true); [ -n "$nl" ] || nl=0
a2=0
if [ "$nl" -lt 30 ]; then
    echo "  FAIL: axis 2: cbt/cyrius.cyr's main block includes only $nl cbt/ file(s) (floor 30) — the reader is not reading"
    a2=1
fi
for f in $(find cbt -name '*.cyr' | LC_ALL=C sort); do [ "$f" = cbt/cyrius.cyr ] || cbt_incs "$f"; done > "$W/nested"
cat "$W/list" "$W/nested" | LC_ALL=C sort | uniq -d > "$W/twice"
if [ -s "$W/twice" ]; then
    echo "  FAIL: axis 2: included more than once: $(tr '\n' ' ' < "$W/twice")"
    a2=1
fi
for f in $(find cbt -name '*.cyr' | LC_ALL=C sort); do
    [ "$f" = cbt/cyrius.cyr ] && continue
    grep -qxF "$f" "$W/list" || grep -qxF "$f" "$W/nested" \
        || { echo "  FAIL: axis 2: $f is included by nothing (cbt/cyrius.cyr's main block includes every piece)"; a2=1; }
done
nm=0
for t in $(find tests -name '*.tcyr' | LC_ALL=C sort); do
    grep -q '^include "cbt/[a-z_]*/' "$t" || continue
    nm=$((nm + 1))
    cbt_incs "$t" > "$W/mirror"
    if ! cmp -s "$W/list" "$W/mirror"; then
        echo "  FAIL: axis 2: $t does not carry cbt/cyrius.cyr's cbt/ include list (- the CLI's, + the test's):"
        diff "$W/list" "$W/mirror" | grep '^[<>]' | sed 's/^</    -/; s/^>/    +/'
        a2=1
    fi
done
if [ "$nm" -lt 5 ]; then
    echo "  FAIL: axis 2: only $nm test(s) compile the CLI's split modules (floor 5) — the mirror scan is not reading"
    a2=1
fi
if [ "$a2" = 0 ]; then
    echo "  ok: axis 2: every cbt/ file is included exactly once ($nl by cbt/cyrius.cyr), and $nm tests carry its list in order"
else
    fail=1
fi

# ── axis 3: no pointer to the split files ────────────────────────────────────────────────
# HISTORY — file|substring: a sentence about a past release, true of the file as it stood.
HISTORY='cbt/cyrius.cyr|Part 1 shipped at v5.11.17 in cbt/deps.cyr
lib/syscalls_macos.cyr|`cbt/deps.cyr:_file_size` uses STAT_SIZE and was fine
programs/checks/main.cyr|`cyrius fmt --check cbt/commands.cyr` exited 1 at 6.6.6
programs/checks/main.cyr|(cbt/deps.cyr had a dry-run branch the CLI could never reach)
src/backend/aarch64/emit.cyr|_file_size in cbt/deps.cyr] ran as aarch64 io_getevents(4)
scripts/cross-os-selfhost.sh|papered-over since v6.0.40, deps.cyr'"'"'s'
printf '%s\n' "$HISTORY" > "$W/history"
{ grep -rnIE 'cbt/(commands|deps)\.cyr|(^|[^a-zA-Z0-9_/.-])(commands|deps)\.cyr' cbt lib programs src scripts || true; } \
    | { grep -vE '[Ss]plit (from|of) cbt/' || true; } > "$W/old"
awk -F'|' 'NR == FNR { hf[NR] = $1; hs[NR] = substr($0, length($1) + 2); nh = NR; next }
     { f = $0; sub(/:.*/, "", f); ok = 0
       for (i = 1; i <= nh; i++) if (hf[i] == f && index($0, hs[i]) > 0) { ok = 1; used[i] = 1 }
       if (!ok) print "  FAIL: axis 3: a pointer to a file the 6.7.18 split removed (name the piece): " substr($0, 1, 200) }
     END { for (i = 1; i <= nh; i++) if (!used[i]) print "  FAIL: axis 3: history entry matches no line (remove it): " hf[i] "|" hs[i] }' \
    "$W/history" "$W/old" > "$W/a3"
if [ -s "$W/a3" ]; then
    cat "$W/a3"
    fail=1
else
    echo "  ok: axis 3: no line of cbt/ lib/ programs/ src/ scripts/ points at cbt/commands.cyr or cbt/deps.cyr ($(grep -c . "$W/history") history sentences, each found)"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL $NAME"
    exit 1
fi
echo "PASS $NAME: every reader of the CLI's source reads cbt/ recursively ($nf files censused, scanner self-tested), and its include list has no drifted copy"
exit 0
