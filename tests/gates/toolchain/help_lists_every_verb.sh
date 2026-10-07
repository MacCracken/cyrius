#!/bin/sh
# tests/gates/toolchain/help_lists_every_verb.sh — 6.7.0
#
# `cyrius --help` LISTS EVERY VERB THE CLI DISPATCHES, EACH EXACTLY ONCE, AND NOTHING ELSE.
#
# THE DEFECT. Through 6.6.20 the top-level help was a hand-kept list that had drifted from the
# dispatcher in main() (cbt/cyrius.cyr) in every direction at once: six verbs main() dispatches
# (`api-surface`, `capacity`, `header`, `install`, `publish`, `pulsar`) had no line at all;
# `audit --internal=platform-check` had TWO lines saying the same thing (the second indented
# like a continuation, so a reader saw a stray flag); `build` had no description; the groups
# put test / tests / bench under "Build:" while coverage / doctest / soak / smoke sat under
# "Testing:" and fuzz under "Quality:"; and the description column wandered between six
# different offsets. No check read the help at all — the per-verb `cyrius <verb> --help` is
# generated from the parser's own table (cli_args_never_dropped.sh pins that), but the
# top-level list never was.
#
# WHAT IS PINNED, and where each expected value comes from (never from the help itself):
#   axis 1  the dispatched verb set is DERIVED from main()'s own `streq(cmd, "…")` sites (the
#           reader cli_args_never_dropped.sh axis 0 uses; the AUTO_DEPS_VERBS block is a list,
#           not dispatch, and is skipped). '-'-prefixed tokens (`--version`, `--help`, `-h`)
#           are aliases, not verbs, and must be NAMED somewhere in the help. ANTI-VACUOUS: a
#           reader that parses nothing finds nothing missing, so the derived count must reach
#           VERB_FLOOR (the real count when this gate was written) — lower it only when a verb
#           is really removed.
#   axis 2  every derived verb has EXACTLY ONE entry. An entry is a line indented two spaces;
#           its verb is its first token. A verb's first entry is its line; a LATER entry for
#           the same verb is legal only as a two-token sub-form (`audit --internal`,
#           `version --project`, `help manifest`), and a sub-form may not repeat.
#   axis 3  every entry names a dispatched verb (statically), and the BUILT CLI does not
#           answer "Unknown command" for it (at runtime — a second oracle). The runtime
#           oracle is proven able to fire on a verb that does not exist. Verbs whose whole
#           tail is forwarded to another binary (`_cli_raw_tail`: init, port, sign-efi) are
#           checked statically only — their `--help` belongs to that binary.
#   axis 4  layout: one description column for every entry, derived from the first entry
#           with a same-line description; an entry whose synopsis leaves no two-space gap
#           carries its description on the NEXT line, at that column; every entry HAS a
#           description; every line of the command section is a group header, a blank, an
#           entry or such a continuation — nothing else (the old 4-space duplicate of
#           `audit --internal=platform-check` is caught HERE: indented past an entry, it is no
#           entry of its own); no doubled blank line anywhere.
#   axis 5  `cyrius`, `cyrius help`, `cyrius -h` and `cyrius --help` print the same bytes, exit 0.
#
# MUTATION LEDGER (6.7.0) — every row RUN against a copy of the tree (cbt/ + lib/ +
# src/version_str.cyr, CYCC=build/cycc); "fails" = red assertions, the gate exits 1 on each:
#   M0  the 6.6.20 usage() itself                                            49 fails
#   M1  drop the `header` entry                                               1 fail  (axis 2)
#   M2  a second `lsp` entry                                                  1 fail  (axis 2)
#   M3  an entry for `frobnicate`, which main() does not dispatch             2 fails (axis 3 x2)
#   M4  restore the 6.6.20 4-space `--internal=platform-check` duplicate      1 fail  (axis 4)
#   M5  one description off the column (`which`)                             1 fail  (axis 4)
#   M6  `fn main(): i64  {` — the main() reader finds nothing                40 fails (floor)
#   M7  the 6.6.20 doubled blank line under the title                         1 fail  (axis 4)
#   M8  `audit --internal` listed twice                                       1 fail  (axis 2)
#   M9  `(also --version)` dropped — an alias named nowhere                   1 fail  (axis 1)
#   M10 `which` taken out of _cli_known_verb (main() still dispatches it)     1 fail  (axis 3, runtime)
#   M11 the `repl` entry printed with no description                          1 fail  (axis 4)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: help_lists_every_verb: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: help_lists_every_verb: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

VERB_FLOOR=39   # 6.7.0: the 39 non-alias verbs main() dispatches

# ── The CLI, built from THIS tree. cycc on empty stdin exits 0 and emits a runnable binary, so a
# failed or empty build must stop the gate rather than score a fake PASS.
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: help_lists_every_verb: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
[ "$(wc -c < "$W/cyrius")" -ge 20000 ] || { echo "FAIL: help_lists_every_verb: cbt/cyrius.cyr built a $(wc -c < "$W/cyrius")-byte binary"; exit 1; }
chmod +x "$W/cyrius"
# Hermetic: a throwaway CYRIUS_HOME and HOME, an empty working directory (no cyrius.cyml to
# redirect through), stdin closed.
mkdir -p "$W/home/bin" "$W/h" "$W/cwd"
cp "$CC" "$W/home/bin/cycc"
cy() { ( cd "$W/cwd" && env HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ) < /dev/null; }

# ── axis 1: the dispatched set, from main()'s own source.
awk '
    /^fn main\(\): i64 \{/ { inmain = 1 }
    inmain && /AUTO_DEPS_VERBS BEGIN/ { skip = 1 }
    inmain && /AUTO_DEPS_VERBS END/   { skip = 0; next }
    inmain && !skip {
        t = $0
        while (match(t, /streq\(cmd, "[^"]*"\)/)) {
            v = substr(t, RSTART, RLENGTH)
            sub(/^streq\(cmd, "/, "", v); sub(/"\)$/, "", v)
            print v
            t = substr(t, RSTART + RLENGTH)
        }
    }
' cbt/cyrius.cyr | LC_ALL=C sort -u > "$W/dispatched.all"
grep -v '^-' "$W/dispatched.all" > "$W/verbs" || true
grep '^-' "$W/dispatched.all" > "$W/aliases" || true
NV=$(grep -c . "$W/verbs" || true)
if [ "$NV" -lt "$VERB_FLOOR" ]; then
    fail "axis 1: derived only $NV dispatched verbs from main() (floor $VERB_FLOOR) — the reader is blind or a verb was removed"
else
    echo "  ok axis 1: $NV verbs dispatched by main() (floor $VERB_FLOOR): $(tr '\n' ' ' < "$W/verbs")"
fi
# The raw-tail verbs (their tail goes to another binary), from cli_args.cyr's own table.
awk '/^fn _cli_raw_tail\(/ { p = 1 } p && /^}/ { exit } p' cbt/cli_args.cyr \
    | grep -o 'streq(verb, "[^"]*")' | sed 's/^streq(verb, "//; s/")$//' > "$W/rawtail"
[ "$(grep -c . "$W/rawtail" || true)" -ge 3 ] || fail "axis 3: read fewer than 3 raw-tail verbs out of _cli_raw_tail — the reader is blind"

# ── The help, three spellings plus none.
RC=0; cy --help > "$W/help" 2> "$W/help.err" || RC=$?
[ "$RC" = 0 ] || fail "axis 5: cyrius --help exited $RC"
[ -s "$W/help" ] || { echo "FAIL: help_lists_every_verb: cyrius --help printed nothing"; cat "$W/help.err"; exit 1; }
for sp in "" "help" "-h"; do
    RC=0
    if [ -z "$sp" ]; then cy > "$W/help.alt" 2>&1 || RC=$?; else cy "$sp" > "$W/help.alt" 2>&1 || RC=$?; fi
    [ "$RC" = 0 ] || fail "axis 5: 'cyrius $sp' exited $RC"
    cmp -s "$W/help" "$W/help.alt" || fail "axis 5: 'cyrius $sp' does not print what 'cyrius --help' prints"
done
for a in $(cat "$W/aliases"); do
    grep -qE -- "(^|[ ,(])$a([ ,)]|\$)" "$W/help" || fail "axis 1: alias '$a' is dispatched by main() and named nowhere in the help"
done

# ── axes 2 + 4: one pass over the command section (from the first group header on).
: > "$W/entries"
awk -v OUT="$W" '
    function bad(m) { print "BAD " NR ": " m " :: " $0 > (OUT "/layout"); }
    /^$/ { if (prev_blank) bad("doubled blank line"); prev_blank = 1; } !/^$/ { prev_blank = 0 }
    !insec && /^[A-Z][A-Za-z &]*:$/ { insec = 1 }
    !insec { next }
    /^$/ { if (pending) bad("entry has no description: " pent); pending = 0; next }
    /^[A-Z][A-Za-z &]*:$/ { if (pending) bad("entry has no description: " pent); pending = 0; next }
    /^  [^ ]/ {
        if (pending) bad("entry has no description: " pent);
        rest = substr($0, 3)
        if (match(rest, /  +[^ ]/)) {
            syn = substr(rest, 1, RSTART - 1); d = RSTART + RLENGTH + 1; pending = 0
            if (col == 0) col = d
            else if (d != col) bad("description at column " d ", the help uses " col)
        } else { syn = rest; pending = 1; pent = $0 }
        n = split(syn, tk, " ")
        print tk[1] "\t" n "\t" tk[1] " " tk[2] > (OUT "/entries")
        next
    }
    /^ +[^ ]/ {
        match($0, /^ +/); d = RLENGTH + 1
        if (!pending) bad("a continuation line under an entry that already has a description")
        else if (col == 0) col = d
        else if (d != col) bad("continuation description at column " d ", the help uses " col)
        pending = 0; next
    }
    { bad("line fits no shape (group header, blank, entry, continuation)") }
    END { if (pending) bad("entry has no description: " pent); print col > (OUT "/col") }
' "$W/help"
NE=$(grep -c . "$W/entries" 2>/dev/null || true)
[ "$NE" -ge "$VERB_FLOOR" ] || fail "axis 2: parsed only $NE entries out of the help (floor $VERB_FLOOR) — the parser is blind"
if [ -s "$W/layout" ]; then
    while IFS= read -r l; do fail "axis 4: $l"; done < "$W/layout"
else
    echo "  ok axis 4: one description column ($(cat "$W/col")), every entry described, no stray or doubled lines"
fi

# axis 2: exactly one entry per verb; later entries only as distinct two-token sub-forms.
awk -F'\t' '
    { if (!($1 in seen)) { seen[$1] = 1; next }
      if ($2 != 2) { print "DUP " $1 " :: a second entry for this verb (not a two-token sub-form)"; next }
      if ($3 in sf) { print "DUP " $1 " :: sub-form \"" $3 "\" listed twice"; next }
      sf[$3] = 1 }
' "$W/entries" > "$W/dups"
while IFS= read -r l; do fail "axis 2: $l"; done < "$W/dups"
cut -f1 "$W/entries" | LC_ALL=C sort -u > "$W/listed"
missing=$(LC_ALL=C comm -23 "$W/verbs" "$W/listed")
for v in $missing; do fail "axis 2: verb '$v' is dispatched by main() and has NO entry in cyrius --help"; done
extra=$(LC_ALL=C comm -13 "$W/verbs" "$W/listed")
for v in $extra; do fail "axis 3: '$v' has an entry in cyrius --help but main() does not dispatch it"; done
[ -z "$missing$extra" ] && [ ! -s "$W/dups" ] && echo "  ok axis 2: all $NV verbs listed exactly once ($NE entries, sub-forms included)"

# ── axis 3 (runtime): the built CLI knows every listed verb. Negative control first, so an
# oracle that cannot fire cannot pass.
f3=$FAIL
cy zz-help-gate-probe --help > "$W/neg" 2>&1 || true
grep -q 'Unknown command' "$W/neg" || fail "axis 3: the oracle is blind — 'cyrius zz-help-gate-probe' did not say Unknown command"
nr=0
for v in $(cat "$W/listed"); do
    grep -qx -- "$v" "$W/rawtail" && [ "$v" != help ] && continue
    cy "$v" --help > "$W/probe" 2>&1 || true
    if grep -q 'Unknown command' "$W/probe"; then fail "axis 3: '$v' is listed in the help and the built CLI says Unknown command"; fi
    nr=$((nr + 1))
done
[ "$nr" -ge $((VERB_FLOOR - 4)) ] || fail "axis 3: probed only $nr listed verbs at runtime (floor $((VERB_FLOOR - 4)))"
[ "$FAIL" = "$f3" ] && echo "  ok axis 3: $nr listed verbs answered by the built CLI (raw-tail verbs checked statically)"

if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: help_lists_every_verb — $FAIL finding(s)"
    exit 1
fi
echo "PASS: help_lists_every_verb — $NV verbs, each listed exactly once, one description column"
exit 0
