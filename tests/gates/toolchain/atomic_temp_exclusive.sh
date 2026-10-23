#!/bin/sh
# Gate: the sibling temp a crash-safe replace writes through is created EXCLUSIVELY — a name
# planted there is never opened, followed or truncated (6.6.20 SEC-05, CYRIUS-2026-0034).
#
# THE BUG. lib/io.cyr `file_write_atomic` and cbt/core.cyr `_aw_open` wrote through
# "<path>.cyrtmp.<pid>.<ctr>" — the pid and a counter from 1, so PREDICTABLE — opened
# O_WRONLY|O_CREAT|O_TRUNC. Whoever could create a name beside the file planted a symlink at the
# next one: the write truncated and overwrote the file the link named, and the rename then moved
# the LINK over the file. Measured at 2ac318b0 (x86_64 Linux): `cyrfmt --write x.cyr` wrote the
# formatted source into the victim and left x.cyr a symlink to it; `cyrius deps --lock` did the
# same with cyrius.lock. Writers since 6.6.6: cyrsign's .sig, cyrsign-efi, cyrfmt --write,
# cyrius-init, sigil's trust-store writes, the CLI's lock / vendored copy / distlib outputs.
#
# THE FIX. `_io_tmp_open` (lib/io.cyr) creates each candidate O_CREAT|O_EXCL|O_NOFOLLOW; a taken
# name is skipped and the next tried, up to 64; then -EEXIST with the file left as it was, and
# the CLI says so by name. `_aw_open` goes through it. The platform half (-EEXIST on Linux/macOS,
# the bare -1 classified on Windows/agnos) is tests/tcyr/crossos/atomic_write_temp_exclusive.tcyr,
# which the release gate runs on every cross-OS host.
#
# AXES (Linux; the tools are built from THIS tree with build/cycc; throwaway HOME / CYRIUS_HOME).
# The temp names are predicted exactly: each tool is started by `sh -c '...; exec tool'`, so the
# planting shell's $$ IS the tool's pid.
#   1  cyrfmt --write (lib file_replace_atomic -> file_write_atomic), symlinks planted at the
#      first 8 temp names -> rc 0, the source formatted, the victim byte-for-byte, the source not
#      a link, all 8 planted links left as they were
#   2  cyrius deps --lock (cbt _aw_open_replace -> _aw_open), the same plant -> rc 0, the lock
#      written, victim untouched, the lock not a link
#   3  64+ taken names: cyrius deps --lock with 128 planted FILES -> rc 1, the refusal NAMED
#      ("every temp name beside it is taken"), cyrius.lock byte-for-byte, every plant
#      intact; cyrfmt --write likewise rc != 0 with the source byte-for-byte
#   4  control: no plant -> deps --lock writes the lock and leaves no temp behind
#   5  STATIC: `_io_tmp_name` (the predictable name) is called only by `_io_tmp_open` and by
#      cyriusly's `_relink_atomic` (symlink(2), which never follows and fails on a taken name);
#      a new caller fails, and so does an allowlist entry matching no live site. Self-tested.
#      (6.7.14's cbt/deps.cyr `_dep_scr_next_tmp`, which named the next temp for the kill
#      handler without opening it, is gone: a scratch resolve records the temp `_aw_open`
#      created, signals held across the create — a predicted name could be a file another
#      process had put there. CHANGELOG [6.7.15])
#   6  CYRIUS-2026-0046 (6.7.18): the BUILD's own output temp. compile() wrote `<out>.tmp.<pid>`,
#      unlinked (result unchecked) and opened O_CREAT|O_TRUNC; where the unlink fails (a sticky
#      directory and another user's link, or here a 0555 directory) the open followed a link
#      planted there. The audit's repro: a link at `d/y.tmp.<pid>` -> victim, d made 0555,
#      `cyrius build hello.cyr d/y` -> the victim byte-for-byte (it became the ELF at b873a1eca).
#      Needs a non-root user (root writes a 0555 directory): SKIPPED BY NAME as root.
#   7  the temp is UNPREDICTABLE and created by the CLI itself: a stand-in compiler beside a copy
#      of the CLI records the name its stdout is open on — `<out>.tmp.<digits>`, the digits never
#      the CLI's pid, two runs never the same name, and a link planted at `<out>.tmp.<pid>` in a
#      writable directory left as it was (the old unlink removed it, the old open then wrote there)
#   8  STATIC: in cbt/, the `".tmp."` literal is built only by `_cbt_out_tmp_name` (every output
#      temp goes through `_cbt_out_tmp_open` / that name), and `".pulsar.new"` only by
#      `_pulsar_install_bin` (whose write is `_aw_open`'s exclusive temp). Self-tested.
#
# MUTATION LEDGER (2026-10-07, 6.6.20, each in a scratch copy of the tree):
#   a. `_io_tmp_open` opening O_WRONLY|O_CREAT|O_TRUNC (no O_EXCL|O_NOFOLLOW)  -> axes 1, 2, 3 RED
#      (both victims written, both links renamed over the file, every plant-128 write "succeeds")
#   b. `_aw_open` back on its own `_io_tmp_name` + O_TRUNC open (lib fixed)     -> axes 2, 3, 5 RED
#   c. the retry dropped (the first taken name gives up)                       -> axes 1, 2 RED
#   d. the named refusal dropped from `_aw_open`                               -> axis 3 RED
# 6.7.18 (CYRIUS-2026-0046): the parent commit's cbt/ (`<out>.tmp.<pid>`, O_CREAT|O_TRUNC in the
#   child)                                                                    -> axes 6, 7, 8 RED
#   e. `_cbt_name_nonce` answering the pid (a predictable name)                -> axis 7 RED
#   f. `_cbt_out_tmp_open` opening O_CREAT|O_TRUNC (no O_EXCL|O_NOFOLLOW) with
#      the name `<out>.tmp.<pid>`                                             -> axes 6, 7 RED
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=atomic_temp_exclusive

[ -x "$CC" ] || { echo "FAIL: $NAME — $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $NAME: $*"; FAIL=1; }

mkdir -p "$W/bin" "$W/home/.cyrius" || { echo "FAIL: $NAME: cannot stage $W"; exit 1; }
( cd "$ROOT" && "$CC" < programs/cyrfmt.cyr > "$W/bin/cyrfmt" 2> "$W/fmt.err" ) && [ -s "$W/bin/cyrfmt" ] \
  || { echo "FAIL: $NAME: programs/cyrfmt.cyr does not build:"; tail -3 "$W/fmt.err"; exit 1; }
( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" ) && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: $NAME: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err"; exit 1; }
chmod +x "$W/bin/cyrfmt" "$W/bin/cyrius" || exit 1

# _run_planted <dir> <file> <n> <kind> <tool> <args...> — in <dir>, plant <n> names at
# "<file>.cyrtmp.<pid>.1..n" (kind `link` -> symlinks to ./victim, `file` -> files holding "P"),
# then exec the tool under that same pid. Output to <dir>/out.txt; returns the tool's rc.
_run_planted() {
    _d=$1; _f=$2; _n=$3; _k=$4; shift 4
    ( cd "$_d" && exec env HOME="$W/home" CYRIUS_HOME="$W/home/.cyrius" sh -c '
        f=$1; n=$2; k=$3; shift 3
        i=1
        while [ $i -le "$n" ]; do
            if [ "$k" = link ]; then ln -s victim "$f.cyrtmp.$$.$i" || exit 90
            else echo P > "$f.cyrtmp.$$.$i" || exit 90; fi
            i=$((i + 1))
        done
        exec "$@"' sh "$_f" "$_n" "$_k" "$@" ) > "$_d/out.txt" 2>&1
}
_nlinks() { find "$1" -maxdepth 1 -type l -name "$2.cyrtmp.*" | wc -l | tr -d ' '; }
_nplants() {  # files named <f>.cyrtmp.* still holding exactly "P"
    _c=0
    for _p in "$1/$2".cyrtmp.*; do [ -f "$_p" ] && [ "$(cat "$_p")" = P ] && _c=$((_c + 1)); done
    echo "$_c"
}

# ── axis 1: cyrfmt --write, symlinks at the first 8 temp names ──
A="$W/a1"; mkdir -p "$A"
i=1; while [ $i -le 20 ]; do printf 'fn g%d(): i64 {\n        return %d;\n}\n' $i $i; i=$((i + 1)); done > "$A/x.cyr"
cp "$A/x.cyr" "$W/x.orig"
"$W/bin/cyrfmt" "$A/x.cyr" > "$W/x.want" 2>/dev/null
cmp -s "$W/x.want" "$W/x.orig" && { echo "FAIL: $NAME: axis 1 fixture is already formatted — --write would not write"; exit 1; }
echo precious > "$A/victim"
rc=0; _run_planted "$A" x.cyr 8 link "$W/bin/cyrfmt" --write x.cyr || rc=$?
a1=0
[ "$rc" -eq 0 ] || { fail "axis 1: cyrfmt --write failed (rc=$rc):"; sed 's/^/      /' "$A/out.txt" | head -3; a1=1; }
[ "$(cat "$A/victim")" = precious ] || { fail "axis 1: cyrfmt --write wrote THROUGH a link planted at its temp name — the victim now holds $(wc -c < "$A/victim") bytes"; a1=1; }
[ -L "$A/x.cyr" ] && { fail "axis 1: the planted link was renamed over the source (x.cyr is now a symlink)"; a1=1; }
[ -L "$A/x.cyr" ] || cmp -s "$A/x.cyr" "$W/x.want" || { fail "axis 1: the source does not hold the formatted text"; a1=1; }
[ "$(_nlinks "$A" x.cyr)" = 8 ] || { fail "axis 1: $(_nlinks "$A" x.cyr) of the 8 planted links are left (one was consumed)"; a1=1; }
[ "$a1" = 0 ] && echo "  ok: axis 1: cyrfmt --write with links at its first 8 temp names formats the source and leaves the victim and all 8 links alone"

# ── axis 2: cyrius deps --lock, the same plant ──
P="$W/a2"; mkdir -p "$P/lib"
printf '[package]\nname = "lockp"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
i=1; while [ $i -le 3 ]; do echo "fn f$i(): i64 { return $i; }" > "$P/lib/mod_$i.cyr"; i=$((i + 1)); done
echo precious > "$P/victim"
rc=0; _run_planted "$P" cyrius.lock 8 link "$W/bin/cyrius" deps --lock || rc=$?
a2=0
[ "$rc" -eq 0 ] || { fail "axis 2: deps --lock failed (rc=$rc):"; sed 's/^/      /' "$P/out.txt" | head -3; a2=1; }
[ "$(cat "$P/victim")" = precious ] || { fail "axis 2: deps --lock wrote THROUGH a link planted at its temp name — the victim now holds: $(head -c 80 "$P/victim")"; a2=1; }
[ -L "$P/cyrius.lock" ] && { fail "axis 2: the planted link was renamed over cyrius.lock"; a2=1; }
nl=$(grep -c '  lib/mod_[0-9]\.cyr$' "$P/cyrius.lock" 2>/dev/null || echo 0)
[ "$nl" = 3 ] || { fail "axis 2: cyrius.lock does not lock the 3 lib files ($nl lines)"; a2=1; }
[ "$(_nlinks "$P" cyrius.lock)" = 8 ] || { fail "axis 2: $(_nlinks "$P" cyrius.lock) of the 8 planted links are left"; a2=1; }
[ "$a2" = 0 ] && echo "  ok: axis 2: cyrius deps --lock with links at its first 8 temp names writes the lock and leaves the victim and all 8 links alone"

# ── axis 3: every name taken -> refused by name, nothing replaced ──
X="$W/a3"; mkdir -p "$X/lib"
cp "$P/cyrius.cyml" "$X/cyrius.cyml" && cp "$P/lib/"*.cyr "$X/lib/" && echo old-lock > "$X/cyrius.lock" || exit 1
rc=0; _run_planted "$X" cyrius.lock 128 file "$W/bin/cyrius" deps --lock || rc=$?
a3=0
[ "$rc" -eq 1 ] || { fail "axis 3: deps --lock with every temp name taken exited $rc (want 1)"; a3=1; }
grep -q 'every temp name beside it is taken.*cyrius\.lock' "$X/out.txt" \
  || { fail "axis 3: the refusal is not named:"; sed 's/^/      /' "$X/out.txt" | head -3; a3=1; }
[ "$(cat "$X/cyrius.lock")" = old-lock ] || { fail "axis 3: cyrius.lock was changed by a refused write"; a3=1; }
[ "$(_nplants "$X" cyrius.lock)" = 128 ] || { fail "axis 3: only $(_nplants "$X" cyrius.lock) of 128 planted files are intact"; a3=1; }
F="$W/a3f"; mkdir -p "$F" && cp "$W/x.orig" "$F/x.cyr" || exit 1
rc=0; _run_planted "$F" x.cyr 128 file "$W/bin/cyrfmt" --write x.cyr || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 3: cyrfmt --write with every temp name taken reported success"; a3=1; }
cmp -s "$F/x.cyr" "$W/x.orig" || { fail "axis 3: cyrfmt --write changed the source although no temp could be made"; a3=1; }
[ "$(_nplants "$F" x.cyr)" = 128 ] || { fail "axis 3: only $(_nplants "$F" x.cyr) of 128 planted files are intact (cyrfmt)"; a3=1; }
[ "$a3" = 0 ] && echo "  ok: axis 3: with every temp name taken, deps --lock refuses by name (rc 1) and cyrfmt --write fails, each file and every plant left as it was"

# ── axis 4: control — nothing planted ──
C="$W/a4"; mkdir -p "$C/lib"
cp "$P/cyrius.cyml" "$C/cyrius.cyml" && cp "$P/lib/"*.cyr "$C/lib/" || exit 1
rc=0; ( cd "$C" && exec env HOME="$W/home" CYRIUS_HOME="$W/home/.cyrius" "$W/bin/cyrius" deps --lock ) > "$C/out.txt" 2>&1 || rc=$?
a4=0
nl=$(grep -c '  lib/mod_[0-9]\.cyr$' "$C/cyrius.lock" 2>/dev/null || echo 0)
{ [ "$rc" -eq 0 ] && [ "$nl" = 3 ]; } || { fail "axis 4: unplanted, deps --lock did not lock the 3 files (rc=$rc, $nl lines)"; a4=1; }
[ -z "$(ls -A "$C" | grep cyrtmp)" ] || { fail "axis 4: a temp was left behind: $(ls -A "$C" | grep cyrtmp | tr '\n' ' ')"; a4=1; }
[ "$a4" = 0 ] && echo "  ok: axis 4: control — unplanted, deps --lock writes the lock and leaves no temp"

# ── axis 5: STATIC — who calls the predictable-name builder ──
ALLOW='lib/io.cyr|_io_tmp_open|creates every candidate O_CREAT|O_EXCL|O_NOFOLLOW and skips a taken name
programs/cyriusly.cyr|_relink_atomic|symlink(2) at the name: it never follows a final link and fails on a taken name'
cat > "$W/callers.awk" <<'AWK'
# prints "<FILE>|<enclosing fn>" for each non-comment call of _io_tmp_name(
/^[ \t]*fn [A-Za-z_0-9]+[ \t]*\(/ { f = $0; sub(/^[ \t]*fn[ \t]+/, "", f); sub(/[ \t]*\(.*/, "", f) }
{
    line = $0
    sub(/^[ \t]*#.*/, "", line)
    sub(/[ \t]#[^"]*$/, "", line)
    if (line ~ /^[ \t]*fn _io_tmp_name[ \t]*\(/) next
    if (line ~ /_io_tmp_name\(/) print FILE "|" f
}
AWK
_callers() { awk -v FILE="$2" -f "$W/callers.awk" "$1"; }
mkdir -p "$W/fx"
printf 'fn _io_tmp_name(path): i64 {\n    return 0;\n}\nfn good(p): i64 {\n    # _io_tmp_name(p) in a comment is not a call\n    var t = _io_tmp_name(p);\n}\n' > "$W/fx/a.cyr"
st=0
[ "$(_callers "$W/fx/a.cyr" lib/x.cyr)" = 'lib/x.cyr|good' ] || { fail "axis 5 self-test: the detector saw '$(_callers "$W/fx/a.cyr" lib/x.cyr | tr '\n' ' ')' (want lib/x.cyr|good)"; st=1; }
: > "$W/sites"
nfile=0
for f in "$ROOT"/lib/*.cyr "$ROOT"/cbt/*.cyr "$ROOT"/programs/*.cyr "$ROOT"/src/*.cyr "$ROOT"/src/*/*.cyr; do
    [ -f "$f" ] || continue
    nfile=$((nfile + 1))
    _callers "$f" "${f#"$ROOT"/}" >> "$W/sites"
done
echo "$ALLOW" | cut -d'|' -f1,2 | LC_ALL=C sort -u > "$W/allow.keys"
bad=$(LC_ALL=C sort -u "$W/sites" | LC_ALL=C comm -23 - "$W/allow.keys")
dead=$(LC_ALL=C sort -u "$W/sites" | LC_ALL=C comm -13 - "$W/allow.keys")
a5=$st
[ "$nfile" -ge 200 ] || { fail "axis 5: scanned $nfile files (floor 200) — the scan read nothing"; a5=1; }
[ -z "$bad" ] || { echo "$bad" | sed "s/^/FAIL: $NAME: axis 5: a new caller of the predictable temp name (create it through _io_tmp_open): /"; FAIL=1; a5=1; }
[ -z "$dead" ] || { echo "$dead" | sed "s/^/FAIL: $NAME: axis 5: allowlist entry matches no live site (remove it): /"; FAIL=1; a5=1; }
[ "$a5" = 0 ] && echo "  ok: axis 5: _io_tmp_name is called only by _io_tmp_open and cyriusly's symlink relink ($nfile files scanned; detector self-tested)"

# ── axis 6: the build's own output temp in a directory the CLI cannot write (CYRIUS-2026-0046) ──
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/hello.cyr"
mkdir -p "$W/home/.cyrius/bin" && cp "$CC" "$W/home/.cyrius/bin/cycc" || exit 1
if [ "$(id -u)" = 0 ]; then
    echo "  SKIP: axis 6: needs a non-root user (root writes a 0555 directory, so the planted link is unlinked either way)"
else
    B="$W/a6"; mkdir -p "$B/d"
    printf 'precious-victim-bytes\n' > "$B/victim"
    rc=0; ( cd "$B" && exec env HOME="$W/home" CYRIUS_HOME="$W/home/.cyrius" sh -c '
        ln -s "$PWD/victim" "d/y.tmp.$$" || exit 90
        chmod 555 d || exit 90
        exec "$@"' sh "$W/bin/cyrius" build "$W/hello.cyr" d/y ) > "$B/out.txt" 2>&1 || rc=$?
    chmod 755 "$B/d"
    a6=0
    [ "$rc" -ne 0 ] || { fail "axis 6: cyrius build into a 0555 directory reported success"; a6=1; }
    [ "$(cat "$B/victim")" = precious-victim-bytes ] \
      || { fail "axis 6: cyrius build wrote THROUGH a link planted at <out>.tmp.<pid> — the victim now holds $(wc -c < "$B/victim") bytes ($(head -c 4 "$B/victim" | od -An -c | tr -s ' '))"; a6=1; }
    [ "$(find "$B/d" -maxdepth 1 -type l -name 'y.tmp.*' | wc -l | tr -d ' ')" = 1 ] \
      || { fail "axis 6: the planted link is gone"; a6=1; }
    [ "$a6" = 0 ] && echo "  ok: axis 6: cyrius build with a link planted at <out>.tmp.<pid> in a 0555 directory fails and leaves the victim byte-for-byte"
fi

# ── axis 7: the temp is the CLI's own, under a name nobody can give in advance ──
SB="$W/a7"; mkdir -p "$SB/bin" "$SB/home" "$SB/d"
cp "$W/bin/cyrius" "$SB/bin/cyrius" || exit 1
printf '#!/bin/sh\nreadlink /proc/$$/fd/1 >> "%s"\ncat > /dev/null\nprintf stub\n' "$SB/rec" > "$SB/bin/cycc"
chmod +x "$SB/bin/cycc" || exit 1
printf 'precious-victim-bytes\n' > "$SB/victim"
: > "$SB/rec"
a7=0
for run in 1 2; do
    rc=0; ( cd "$SB/d" && exec env HOME="$SB/home" CYRIUS_HOME="$SB/home/.cyrius" sh -c '
        echo $$ >> ../pids
        ln -s ../victim "x.tmp.$$" || exit 90
        exec "$@"' sh "$SB/bin/cyrius" build "$W/hello.cyr" x ) > "$SB/out$run.txt" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || { fail "axis 7: run $run: the stand-in build failed (rc=$rc):"; sed 's/^/      /' "$SB/out$run.txt" | head -3; a7=1; }
done
n1=$(sed -n 1p "$SB/rec"); n2=$(sed -n 2p "$SB/rec")
p1=$(sed -n 1p "$SB/pids"); p2=$(sed -n 2p "$SB/pids")
for pair in "1|$n1|$p1" "2|$n2|$p2"; do
    r=${pair%%|*}; rest=${pair#*|}; n=${rest%%|*}; p=${rest#*|}
    case "${n##*/}" in
        x.tmp.*) sfx=${n##*/x.tmp.}
                 case "$sfx" in ''|*[!0-9]*) fail "axis 7: run $r: the temp '${n##*/}' does not end in .tmp.<digits> (check.sh's reaper shape)"; a7=1 ;; esac
                 [ "$sfx" != "$p" ] || { fail "axis 7: run $r: the temp is <out>.tmp.<pid> ($sfx) — predictable"; a7=1; } ;;
        *) fail "axis 7: run $r: the compiler's stdout was '$n', not a <out>.tmp.<n> beside the output"; a7=1 ;;
    esac
done
[ -n "$n1" ] && [ "$n1" != "$n2" ] || { fail "axis 7: two builds used the same temp name ('$n1')"; a7=1; }
[ "$(cat "$SB/victim")" = precious-victim-bytes ] || { fail "axis 7: the victim behind <out>.tmp.<pid> was written"; a7=1; }
[ "$(find "$SB/d" -maxdepth 1 -type l -name 'x.tmp.*' | wc -l | tr -d ' ')" = 2 ] \
  || { fail "axis 7: $(find "$SB/d" -maxdepth 1 -type l -name 'x.tmp.*' | wc -l | tr -d ' ') of the 2 links planted at <out>.tmp.<pid> are left (the build removed one)"; a7=1; }
[ "$(cat "$SB/d/x" 2>/dev/null)" = stub ] || { fail "axis 7: the output does not hold the stand-in compiler's bytes"; a7=1; }
[ "$a7" = 0 ] && echo "  ok: axis 7: the build writes <out>.tmp.<digits> it created itself — never the pid, never the same twice — and a link at <out>.tmp.<pid> is left alone"

# ── axis 8: STATIC — who builds an output temp's name in cbt/ ──
cat > "$W/tmplit.awk" <<'AWK'
# prints "<FILE>|<enclosing fn>|<literal>" for each non-comment ".tmp." / ".pulsar.new" literal
/^[ \t]*fn [A-Za-z_0-9]+[ \t]*\(/ { f = $0; sub(/^[ \t]*fn[ \t]+/, "", f); sub(/[ \t]*\(.*/, "", f) }
{
    line = $0
    sub(/^[ \t]*#.*/, "", line)
    sub(/[ \t]#[^"]*$/, "", line)
    if (index(line, "\".tmp.\"") > 0) print FILE "|" f "|.tmp."
    if (index(line, "\".pulsar.new\"") > 0) print FILE "|" f "|.pulsar.new"
}
AWK
TALLOW='cbt/core.cyr|_cbt_out_tmp_name|.tmp.
cbt/pulsar.cyr|_pulsar_install_bin|.pulsar.new'
printf 'fn _a(o): i64 {\n    # str_builder_add_cstr(sb, ".tmp.") in a comment\n    str_builder_add_cstr(sb, ".tmp.");\n}\nfn _b(o): i64 {\n    var t = ".pulsar.new";\n}\n' > "$W/fx/t.cyr"
a8=0
[ "$(awk -v FILE=cbt/t.cyr -f "$W/tmplit.awk" "$W/fx/t.cyr" | tr '\n' ' ')" = 'cbt/t.cyr|_a|.tmp. cbt/t.cyr|_b|.pulsar.new ' ] \
  || { fail "axis 8 self-test: the detector saw '$(awk -v FILE=cbt/t.cyr -f "$W/tmplit.awk" "$W/fx/t.cyr" | tr '\n' ' ')'"; a8=1; }
: > "$W/tsites"; ncb=0
for f in "$ROOT"/cbt/*.cyr; do
    [ -f "$f" ] || continue
    ncb=$((ncb + 1))
    awk -v FILE="${f#"$ROOT"/}" -f "$W/tmplit.awk" "$f" >> "$W/tsites"
done
echo "$TALLOW" | LC_ALL=C sort -u > "$W/tallow"
tbad=$(LC_ALL=C sort -u "$W/tsites" | LC_ALL=C comm -23 - "$W/tallow")
tdead=$(LC_ALL=C sort -u "$W/tsites" | LC_ALL=C comm -13 - "$W/tallow")
[ "$ncb" -ge 10 ] || { fail "axis 8: scanned $ncb cbt/ files (floor 10) — the scan read nothing"; a8=1; }
[ -z "$tbad" ] || { echo "$tbad" | sed "s/^/FAIL: $NAME: axis 8: an output temp named outside _cbt_out_tmp_name (create it through _cbt_out_tmp_open): /"; FAIL=1; a8=1; }
[ -z "$tdead" ] || { echo "$tdead" | sed "s/^/FAIL: $NAME: axis 8: allowlist entry matches no live site (remove it): /"; FAIL=1; a8=1; }
[ "$a8" = 0 ] && echo "  ok: axis 8: every output temp name in cbt/ comes from _cbt_out_tmp_name ($ncb files scanned; detector self-tested)"

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
echo "PASS $NAME (a name planted at a crash-safe replace's temp is never followed or truncated: cyrfmt --write and cyrius deps --lock skip it, refuse by name when every name is taken, and only the exclusive creator builds the name; the build's own output temp is the CLI's, exclusive and unpredictable)"
