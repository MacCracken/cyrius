#!/bin/sh
# tool_writes_never_truncate.sh — v6.6.6. A tool that REPLACES a file the user or the tree owns
# writes it crash-safe (temp + fsync + rename), and a short write is an ERROR — never a truncated
# file and an exit 0.
#
# ⛔ THE DEFECT (found by 6.6.6 bite 12, reproduced at the bite-12 tree). programs/
# gen_unicode_data.cyr wrote the three TRACKED lib/unicode/_*_data.cyr tables with
# `file_write_all` — open(O_TRUNC), then ONE write — and printed the count without checking it.
# On a full disk all three tables were truncated to 2048 bytes and the tool said
# `wrote … (2048 bytes)` and exited 0 (committed sizes 59010 / 96988 / 156750).
#
# ⚠ HOW A FULL DISK IS REPRODUCED WITHOUT A MOUNT. RLIMIT_FSIZE with SIGXFSZ ignored (a shell
# `trap ''` survives exec) gives the writer exactly a full disk's sequence: the write that
# crosses the limit comes back SHORT, the next one fails EFBIG. `ulimit -f` counts 512-byte
# blocks under /bin/sh-as-bash (POSIX mode) and 1024-byte blocks under bash proper; every limit
# below is chosen to hold under BOTH units.
#
# AXES
#   1. gen_unicode_data, unconstrained, regenerates the three committed tables byte-for-byte
#      into an OUTDIR (anti-vacuous: the rows below would otherwise test a tool that writes
#      nothing, and this is also the only place anything re-derives these tables).
#   2. Under a 4-block limit (every table is larger) it exits NON-ZERO, names the file, leaves
#      all three seeded tables byte-for-byte, and leaves no temp behind.
#   3. Under a 150-block limit (76,800 or 153,600 bytes — above the first table, below the
#      third) it fails PART-WAY: every table is either complete or exactly as seeded, never a
#      prefix, and at least one is left as seeded.
#   4. STATIC over programs/*.cyr + cbt/*.cyr: every `file_write_all(P, …)` and every O_TRUNC
#      open (spelled O_TRUNC, 0x241 or 577) is keyed "<file>|<P>" and must be on an allowlist of
#      temps / child-output captures / the linker's checked output, each with its reason; an
#      entry matching no live site fails too. Self-tested on 4 shapes. The same sweep found the
#      defect in 14 more writers (cyrfmt --write, cyriusly's cyrius.cyml + `current`, cbt's
#      cyrius.lock, vendored lib/<dep>.cyr copy, .cyrius-toolchain, toml->cyml migration,
#      distlib bundle / modules / index.cyml / .deps sidecar, the api-surface snapshot,
#      cyrsign's .sig, cyrsign-efi's output, cyrius-init's scaffold files, ark's database).
#   5-7. DYNAMIC, the replaced-file writers under a 2-block limit: `cyrfmt --write` (the user's
#      source), `cyrius deps --lock` (cyrius.lock), `cyrius distlib` (the committed bundle) —
#      each exits non-zero with the file byte-for-byte and no temp beside it, and unconstrained
#      writes the expected bytes (the formatted text from stdout mode; 80 lock lines for 80 lib
#      files; 120 bundled fns). Tools are built from the tree into $D, never the live store.
#   8. (6.6.6 bite 13 review) a replace keeps what the USER set: `cyrfmt --write` on a 0640
#      source and through a symlink to a 0600 one, and `deps --lock` through a symlinked 0600
#      cyrius.lock — each mode unchanged (under umask 022), each link still a link, and the file
#      it names holds the new bytes. lib/io.cyr file_write_atomic keeps the mode; file_replace_
#      atomic / cbt's _aw_open_replace also write through the link. The vendored lib/<dep>.cyr
#      copy deliberately does NOT follow a link (the v6.5.37 corruption).
#
# MUTATION LEDGER (measured 6.6.6, each in a scratch copy of the tree):
#   a. _ucd_write back to `file_write_all`, result unchecked   -> axis 2 FAIL (rc 0, 2048-byte
#                                                                 tables) and axis 3 FAIL
#   b. programs/gen_unicode_data.cyr as of 6.6.5                -> axis 1 FAIL (no OUTDIR: writes
#                                                                 lib/unicode under its cwd)
#   c. programs/cyrfmt.cyr as of 6.6.5                          -> axis 4 FAIL (cyrfmt.cyr|path)
#                                                                 + axis 5 FAIL (source 3684 -> 1024 B)
#   d. cbt/deps.cyr as of 6.6.5                                 -> axis 4 FAIL (4 keys) + axis 6
#                                                                 FAIL (rc 0, lock 6484 -> 1024 B)
#   e. cbt/commands.cyr as of 6.6.5                             -> axis 4 FAIL (4 keys) + axis 7
#                                                                 FAIL (bundle 4132 -> 1024 B)
#   f. ark / cyrius-init / cyrius_api_surface / cyriusly /      -> axis 4 FAIL, 8 keys, one per
#      cyrsign / cyrsign-efi as of 6.6.5                           reverted writer
#   g. cyrfmt + lib/io.cyr + cbt core/deps as first committed  -> axis 8 FAIL (mode 0640 -> 0644;
#      (13b: file_write_atomic, plain _aw_open)                    link replaced, target unformatted;
#                                                                 lock link replaced, 80 of 81 lines)
#   h. _io_keep_mode dropped from file_write_atomic             -> axis 8 FAIL (0640/0600 -> 0644)
#   i. cyrius.lock back on plain _aw_open                       -> axis 8 FAIL (lock link replaced)
#   j. _io_keep_mode dropped from cbt's _aw_open                -> axis 8 FAIL (lock 0600 -> 0644)
#   k. cyrfmt back on file_write_atomic                         -> axis 8 FAIL (link replaced)
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: tool_writes_never_truncate: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }
TABLES="_categories_data.cyr _casefold_data.cyr _normalize_data.cyr"
for t in $TABLES; do
    [ -s "lib/unicode/$t" ] || { echo "FAIL: lib/unicode/$t missing or empty — the committed tables are the expected values"; exit 1; }
done

# ── build the generator from the tree (raw cycc: includes resolve against $ROOT) ──
GEN="$D/gen_unicode_data"
"$CC" < programs/gen_unicode_data.cyr > "$GEN" 2> "$D/build.err"; brc=$?
if [ "$brc" -ne 0 ] || [ ! -s "$GEN" ]; then
    echo "FAIL: programs/gen_unicode_data.cyr does not build (rc=$brc):"; tail -3 "$D/build.err" | sed 's/^/      /'; exit 1
fi
chmod +x "$GEN"
# The generator reads tests/data/ucd/ relative to its cwd. It runs in $D/run over a COPY of
# those inputs, never in $ROOT: a regressed tool that ignored OUTDIR would otherwise rewrite
# the tree's lib/unicode under the size limit — the very damage this gate exists to catch.
mkdir -p "$D/run/tests/data" && cp -R tests/data/ucd "$D/run/tests/data/ucd" \
  || { echo "FAIL: cannot stage the UCD inputs into $D/run"; exit 1; }

# _seed <dir> — a copy of the committed tables with a sentinel line appended, so "left as it
# was" (== seed) is distinguishable from "rewritten with the same content" (== committed)
_seed() {
    mkdir -p "$1" || return 1
    for t in $TABLES; do
        { cat "lib/unicode/$t" && echo "# SENTINEL — must survive a failed regeneration"; } > "$1/$t" || return 1
    done
}

# ── axis 1: anti-vacuous — unconstrained, the committed tables come back exactly ──
mkdir -p "$D/ok"
rc=0; ( cd "$D/run" && exec "$GEN" "$D/ok" ) > "$D/a1.out" 2>&1 || rc=$?
a1=0
[ "$rc" -eq 0 ] || { fail "axis 1: the generator failed unconstrained (rc=$rc):"; tail -3 "$D/a1.out" | sed 's/^/      /'; a1=1; }
for t in $TABLES; do
    cmp -s "$D/ok/$t" "lib/unicode/$t" || { fail "axis 1: $t regenerated into OUTDIR differs from the committed table ($(wc -c < "$D/ok/$t" 2>/dev/null || echo 0) vs $(wc -c < "lib/unicode/$t") bytes) — tables stale, or OUTDIR ignored"; a1=1; }
done
[ -e "$D/run/lib" ] && { fail "axis 1: the generator wrote lib/ under its cwd although OUTDIR was given"; a1=1; }
[ "$a1" = 0 ] && echo "  ok: axis 1: unconstrained, gen_unicode_data reproduces all 3 committed tables into OUTDIR"

# ── axis 2: every table larger than the limit -> non-zero, all three kept, no temp left ──
_seed "$D/fsz" || { echo "FAIL: cannot seed $D/fsz"; exit 1; }
_seed "$D/seed" || { echo "FAIL: cannot seed $D/seed"; exit 1; }
rc=0; ( cd "$D/run" && trap '' XFSZ && ulimit -f 4 && exec "$GEN" "$D/fsz" ) > "$D/a2.out" 2>&1 || rc=$?
a2=0
[ "$rc" -ne 0 ] || { fail "axis 2: a SHORT write was reported as success (rc 0):"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
grep -q "write failed: $D/fsz/_categories_data.cyr" "$D/a2.out" || { fail "axis 2: the failure does not name the file it could not write:"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
for t in $TABLES; do
    cmp -s "$D/fsz/$t" "$D/seed/$t" || { fail "axis 2: $t was CHANGED by a failed regeneration ($(wc -c < "$D/fsz/$t") bytes, seeded $(wc -c < "$D/seed/$t"))"; a2=1; }
done
left=$(ls -A "$D/fsz" | LC_ALL=C sort | tr '\n' ' ')
[ "$left" = "_casefold_data.cyr _categories_data.cyr _normalize_data.cyr " ] || { fail "axis 2: a failed write left files behind: $left"; a2=1; }
[ "$a2" = 0 ] && echo "  ok: axis 2: under RLIMIT_FSIZE (4 blocks) the generator exits $rc, names the file, keeps all 3 tables, leaves no temp"

# ── axis 3: fails PART-WAY -> each table complete or untouched, never a prefix ──
_seed "$D/mid" || { echo "FAIL: cannot seed $D/mid"; exit 1; }
rc=0; ( cd "$D/run" && trap '' XFSZ && ulimit -f 150 && exec "$GEN" "$D/mid" ) > "$D/a3.out" 2>&1 || rc=$?
a3=0; nkept=0; nnew=0
[ "$rc" -ne 0 ] || { fail "axis 3: a part-way failure was reported as success (rc 0)"; a3=1; }
for t in $TABLES; do
    if cmp -s "$D/mid/$t" "$D/seed/$t"; then nkept=$((nkept + 1))
    elif cmp -s "$D/mid/$t" "lib/unicode/$t"; then nnew=$((nnew + 1))
    else fail "axis 3: $t is neither the old table nor the new one ($(wc -c < "$D/mid/$t") bytes) — a partial write replaced it"; a3=1
    fi
done
cmp -s "$D/mid/_categories_data.cyr" "lib/unicode/_categories_data.cyr" || { fail "axis 3: the first table (59,010 B, under the limit in both units) was not written — the limit did not land part-way"; a3=1; }
[ "$nkept" -ge 1 ] || { fail "axis 3: no table was left as seeded — the limit did not bite"; a3=1; }
[ "$(ls -A "$D/mid" | wc -l)" -eq 3 ] || { fail "axis 3: a failed write left files behind: $(ls -A "$D/mid" | tr '\n' ' ')"; a3=1; }
[ "$a3" = 0 ] && echo "  ok: axis 3: a part-way failure (150 blocks) leaves $nnew table(s) complete and $nkept exactly as they were, rc $rc"

# ── axis 4: STATIC — no truncating write of a user/tree file anywhere in programs/ or cbt/ ──
# Every `file_write_all(P, …)` and every open with O_TRUNC (spelled O_TRUNC, 0x241 or 577) is
# keyed "<file>|<P>". A key must be in the allowlist below, each entry with its reason; an
# entry that no longer matches a live site FAILS, so the list cannot rot into a blanket pass.
# programs/checks/ (the check driver's own scratch files) is out of scope here.
ALLOW='programs/cyrld.cyr|out_path|the linker output: every write is checked and fails rc 1 (a build artifact, the class of cycc'"'"'s own output)
cbt/build.cyr|tmp_out|the compiler child'"'"'s stdout (cycc'"'"'s own output write)
cbt/build.cyr|out|the compiler child'"'"'s stdout (cycc'"'"'s own output write)
cbt/build.cyr|_cc_stderr_to|a child'"'"'s stderr capture
cbt/pulsar.cyr|tmp|the compiler child'"'"'s stdout (cycc'"'"'s own output write)
cbt/commands.cyr|cc4_t|the compiler child'"'"'s stdout (cycc'"'"'s own output write)
cbt/commands.cyr|tmperr|a child'"'"'s stderr capture in the private temp dir
cbt/commands.cyr|entry|a _cbt_tmpfile probe source (short write checked: it then fails to compile)
cbt/commands.cyr|dl_entry|a _cbt_tmpfile probe source
cbt/core.cyr|tmp|_aw_open'"'"'s own sibling temp — the crash-safe writer itself
cbt/quality.cyr|tmpf|a _cbt_tmpfile doctest source
cbt/deps.cyr|tmpf|a _cbt_tmpfile capture of sha256sum'"'"'s stdout
cbt/deps.cyr|outf|a _cbt_tmpfile capture of git'"'"'s stdout
cbt/deps.cyr|errf|a _cbt_tmpfile capture of git'"'"'s stderr
cbt/deps.cyr|pl|a _cbt_tmpfile path list (length checked, unlinked on failure)'
cat > "$D/trunc.awk" <<'AWK'
# prints "<FILE>|<first arg>" for each truncating write on a non-comment line
{
    line = $0
    sub(/^[ \t]*#.*/, "", line)
    sub(/[ \t]#[^"]*$/, "", line)
    arg = ""
    if (match(line, /file_write_all\([^,]*,/)) {
        arg = substr(line, RSTART + 15, RLENGTH - 16)
    } else if (line ~ /O_TRUNC|0x241|, *577[,)]/) {
        if (match(line, /(sys_open|file_open)\([^,]*,/)) {
            t = substr(line, RSTART, RLENGTH); sub(/^[a-z_]*\(/, "", t); sub(/,$/, "", t); arg = t
        } else if (match(line, /syscall\((SYS_OPEN|2), *[^,]*,/)) {
            t = substr(line, RSTART, RLENGTH); sub(/^syscall\([A-Z_0-9]*, */, "", t); sub(/,$/, "", t); arg = t
        } else arg = "?"
    }
    if (arg != "") { gsub(/^[ \t]+|[ \t]+$/, "", arg); print FILE "|" arg }
}
AWK
_trunc_sites() {  # _trunc_sites <file> <display-name>
    awk -v FILE="$2" -f "$D/trunc.awk" "$1"
}
# self-test first: each forbidden shape is seen, and an allowlisted look-alike is not flagged
mkdir -p "$D/fx"
printf '    file_write_all("cyrius.cyml", out, out_n);\n' > "$D/fx/a.cyr"
printf '    var fd = sys_open(sigpath, O_WRONLY | O_CREAT | O_TRUNC, 0x1A4);\n' > "$D/fx/b.cyr"
printf '    var fd = syscall(SYS_OPEN, out, 0x241, 0x1ED);\n    var g = sys_open(path, 577, 420);\n' > "$D/fx/c.cyr"
printf '    # file_write_all(path, b, n) in a comment is not a write\n    var fd = file_open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0x1A4);\n' > "$D/fx/d.cyr"
st=0
[ "$(_trunc_sites "$D/fx/a.cyr" programs/x.cyr)" = 'programs/x.cyr|"cyrius.cyml"' ] || { fail "axis 4 self-test: file_write_all not seen: '$(_trunc_sites "$D/fx/a.cyr" programs/x.cyr)'"; st=1; }
[ "$(_trunc_sites "$D/fx/b.cyr" programs/x.cyr)" = 'programs/x.cyr|sigpath' ] || { fail "axis 4 self-test: an O_TRUNC sys_open not seen"; st=1; }
[ "$(_trunc_sites "$D/fx/c.cyr" programs/x.cyr | wc -l)" -eq 2 ] || { fail "axis 4 self-test: the 0x241 / 577 spellings not seen: $(_trunc_sites "$D/fx/c.cyr" programs/x.cyr | tr '\n' ' ')"; st=1; }
[ "$(_trunc_sites "$D/fx/d.cyr" cbt/core.cyr)" = 'cbt/core.cyr|tmp' ] || { fail "axis 4 self-test: comment/look-alike handling wrong: '$(_trunc_sites "$D/fx/d.cyr" cbt/core.cyr)'"; st=1; }
echo "$ALLOW" | cut -d'|' -f1,2 | LC_ALL=C sort -u > "$D/allow.keys"
nfile=0; : > "$D/sites"
for f in $(ls programs/*.cyr cbt/*.cyr | LC_ALL=C sort); do
    nfile=$((nfile + 1))
    _trunc_sites "$f" "$f" >> "$D/sites"
done
nsite=$(wc -l < "$D/sites" | tr -d ' ')
bad=$(LC_ALL=C sort -u "$D/sites" | LC_ALL=C comm -23 - "$D/allow.keys")
dead=$(LC_ALL=C sort -u "$D/sites" | LC_ALL=C comm -13 - "$D/allow.keys")
a4=$st
if [ "$nfile" -lt 60 ] || [ "$nsite" -lt 15 ]; then
    fail "axis 4: scanned $nfile files / $nsite sites (floors 60 / 15) — the scan read nothing"; a4=1
fi
if [ -n "$bad" ]; then
    echo "$bad" | sed 's/^/FAIL: axis 4: a truncating write of a user or tree file (use file_write_atomic, or cbt'"'"'s _aw_open for a stream): /'
    FAIL=1; a4=1
fi
if [ -n "$dead" ]; then
    echo "$dead" | sed 's/^/FAIL: axis 4: allowlist entry matches no live site (remove it): /'
    FAIL=1; a4=1
fi
[ "$a4" = 0 ] && echo "  ok: axis 4: $nsite truncating writes over $nfile files in programs/ + cbt/, every one a temp, a child's output, or the linker's checked output ($(wc -l < "$D/allow.keys" | tr -d ' ') allowlisted keys, all live; detector self-tested on 4 shapes)"

# ── axes 5-7: the replaced-file writers, run under the size limit ──
# cyrfmt --write replaces the USER'S SOURCE; `cyrius deps --lock` replaces cyrius.lock;
# `cyrius distlib` replaces the committed bundle. Each: unconstrained it writes the expected
# bytes (computed another way); under 2 blocks it exits non-zero, the file is byte-for-byte
# what it was, and no temp is left beside it.
mkdir -p "$D/bin"
"$CC" < programs/cyrfmt.cyr > "$D/bin/cyrfmt" 2> "$D/fmtb.err" && [ -s "$D/bin/cyrfmt" ] \
  || { echo "FAIL: programs/cyrfmt.cyr does not build:"; tail -3 "$D/fmtb.err"; exit 1; }
"$CC" < cbt/cyrius.cyr > "$D/bin/cyrius" 2> "$D/clib.err" && [ -s "$D/bin/cyrius" ] \
  || { echo "FAIL: cbt/cyrius.cyr does not build:"; tail -3 "$D/clib.err"; exit 1; }
cp "$CC" "$D/bin/cycc" && chmod +x "$D/bin/cyrfmt" "$D/bin/cyrius" "$D/bin/cycc" || { echo "FAIL: cannot stage $D/bin"; exit 1; }
mkdir -p "$D/home"
_lim() { ( trap '' XFSZ && ulimit -f 2 && exec "$@" ); }

# axis 5: cyrfmt --write
F5="$D/p5/x.cyr"; mkdir -p "$D/p5"
i=1; while [ $i -le 100 ]; do printf 'fn g%d(): i64 {\n        return %d;\n}\n' $i $i; i=$((i + 1)); done > "$F5"
cp "$F5" "$D/x5.orig"
"$D/bin/cyrfmt" "$F5" > "$D/x5.want" 2>/dev/null   # the formatted text, via stdout mode
a5=0
cmp -s "$D/x5.want" "$D/x5.orig" && { fail "axis 5: the fixture is already formatted — --write would not write"; a5=1; }
rc=0; _lim "$D/bin/cyrfmt" --write "$F5" > "$D/a5.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 5: cyrfmt --write reported a short write as success"; a5=1; }
cmp -s "$F5" "$D/x5.orig" || { fail "axis 5: cyrfmt --write TRUNCATED the source it was formatting ($(wc -c < "$F5") bytes, was $(wc -c < "$D/x5.orig"))"; a5=1; }
[ "$(ls -A "$D/p5")" = "x.cyr" ] || { fail "axis 5: a temp was left beside the source: $(ls -A "$D/p5" | tr '\n' ' ')"; a5=1; }
rc=0; "$D/bin/cyrfmt" --write "$F5" > /dev/null 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && cmp -s "$F5" "$D/x5.want"; } || { fail "axis 5: unconstrained, cyrfmt --write did not produce the formatted text (rc=$rc)"; a5=1; }
[ "$a5" = 0 ] && echo "  ok: axis 5: cyrfmt --write under a size limit fails and leaves the source byte-for-byte; unconstrained it writes the formatted text"

# axis 6: cyrius deps --lock
P6="$D/p6"; mkdir -p "$P6/lib"
printf '[package]\nname = "lockp"\nversion = "0.1.0"\n' > "$P6/cyrius.cyml"
i=1; while [ $i -le 80 ]; do echo "fn f$i(): i64 { return $i; }" > "$P6/lib/mod_$i.cyr"; i=$((i + 1)); done
a6=0
rc=0; ( cd "$P6" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" exec "$D/bin/cyrius" deps --lock ) > "$D/a6.out" 2>&1 || rc=$?
nlock=$(grep -c '  lib/mod_[0-9]*\.cyr$' "$P6/cyrius.lock" 2>/dev/null || echo 0)
{ [ "$rc" -eq 0 ] && [ "$nlock" -eq 80 ]; } || { fail "axis 6: unconstrained, deps --lock did not lock the 80 lib files (rc=$rc, $nlock lines)"; sed 's/^/      /' "$D/a6.out" | head -3; a6=1; }
cp "$P6/cyrius.lock" "$D/lock.orig"
rc=0; ( cd "$P6" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" _lim "$D/bin/cyrius" deps --lock ) > "$D/a6b.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 6: deps --lock reported a short write as success"; a6=1; }
cmp -s "$P6/cyrius.lock" "$D/lock.orig" || { fail "axis 6: deps --lock TRUNCATED cyrius.lock ($(wc -c < "$P6/cyrius.lock") bytes, was $(wc -c < "$D/lock.orig"))"; a6=1; }
[ -z "$(ls -A "$P6" | grep cyrtmp)" ] || { fail "axis 6: a temp was left beside the lock"; a6=1; }
[ "$a6" = 0 ] && echo "  ok: axis 6: cyrius deps --lock under a size limit fails and leaves cyrius.lock byte-for-byte; unconstrained it locks all 80 files"

# axis 7: cyrius distlib
P7="$D/p7"; mkdir -p "$P7/src" "$P7/dist"
printf '[package]\nname = "dlp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$P7/cyrius.cyml"
i=1; while [ $i -le 120 ]; do echo "fn dlp_f$i(): i64 { return $i; }"; i=$((i + 1)); done > "$P7/src/a.cyr"
a7=0
rc=0; ( cd "$P7" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" exec "$D/bin/cyrius" distlib ) > "$D/a7.out" 2>&1 || rc=$?
nfn=$(grep -c '^fn dlp_f[0-9]*()' "$P7/dist/dlp.cyr" 2>/dev/null || echo 0)
{ [ "$rc" -eq 0 ] && [ "$nfn" -eq 120 ]; } || { fail "axis 7: unconstrained, distlib did not bundle the 120 fns (rc=$rc, $nfn)"; sed 's/^/      /' "$D/a7.out" | head -3; a7=1; }
cp "$P7/dist/dlp.cyr" "$D/dl.orig"
rc=0; ( cd "$P7" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" _lim "$D/bin/cyrius" distlib ) > "$D/a7b.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 7: distlib reported a short write as success"; a7=1; }
cmp -s "$P7/dist/dlp.cyr" "$D/dl.orig" || { fail "axis 7: distlib TRUNCATED the committed bundle ($(wc -c < "$P7/dist/dlp.cyr") bytes, was $(wc -c < "$D/dl.orig"))"; a7=1; }
grep -q 'write failed' "$D/a7b.out" || { fail "axis 7: distlib failed without saying the write failed:"; sed 's/^/      /' "$D/a7b.out" | head -2; a7=1; }
[ "$(ls -A "$P7/dist")" = "dlp.cyr" ] || { fail "axis 7: a temp was left beside the bundle: $(ls -A "$P7/dist" | tr '\n' ' ')"; a7=1; }
[ "$a7" = 0 ] && echo "  ok: axis 7: cyrius distlib under a size limit fails, says so, and leaves the bundle byte-for-byte; unconstrained it bundles all 120 fns"

# ── axis 8: a replace keeps what the USER set on the file (6.6.6 bite 13 review) ──
# The rename that makes these writes crash-safe puts a NEW inode at the path. As first
# committed a 0600 source came back 0644 and a symlinked source was replaced by a regular copy
# while the file it named stayed unformatted — the O_TRUNC writes they replaced kept both.
# Modes are compared with `stat`'s own rendering of the fixture (a different route from the
# tool's STAT_MODE read); a link must still be a link, and its target must hold the new bytes.
_mode() { ls -ln "$1" | cut -c1-10; }
a8=0
P8="$D/p8"; mkdir -p "$P8/real"
cp "$D/x5.orig" "$P8/m640.cyr" && chmod 640 "$P8/m640.cyr"; want640=$(_mode "$P8/m640.cyr")
cp "$D/x5.orig" "$P8/real/src.cyr" && chmod 600 "$P8/real/src.cyr"; want600=$(_mode "$P8/real/src.cyr")
ln -s real/src.cyr "$P8/link.cyr" || { echo "FAIL: axis 8: cannot make the symlink fixture"; exit 1; }
rc=0; ( umask 022 && exec "$D/bin/cyrfmt" --write "$P8/m640.cyr" ) > /dev/null 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && cmp -s "$P8/m640.cyr" "$D/x5.want"; } || { fail "axis 8: cyrfmt --write did not format the 0640 fixture (rc=$rc)"; a8=1; }
[ "$(_mode "$P8/m640.cyr")" = "$want640" ] || { fail "axis 8: cyrfmt --write reset the source's mode: $(_mode "$P8/m640.cyr"), was $want640"; a8=1; }
rc=0; ( cd "$P8" && umask 022 && exec "$D/bin/cyrfmt" --write link.cyr ) > /dev/null 2>&1 || rc=$?
[ -L "$P8/link.cyr" ] || { fail "axis 8: cyrfmt --write REPLACED the symlink with a regular file (rc=$rc)"; a8=1; }
cmp -s "$P8/real/src.cyr" "$D/x5.want" || { fail "axis 8: cyrfmt --write via a symlink left the file it names unformatted (rc=$rc)"; a8=1; }
[ "$(_mode "$P8/real/src.cyr")" = "$want600" ] || { fail "axis 8: the symlinked source's mode was reset: $(_mode "$P8/real/src.cyr"), was $want600"; a8=1; }
# deps --lock over a symlinked, 0600 cyrius.lock (the lock lives in the user's project)
mkdir -p "$P6/shared"
mv "$P6/cyrius.lock" "$P6/shared/real.lock" && chmod 600 "$P6/shared/real.lock" && ln -s shared/real.lock "$P6/cyrius.lock" \
  || { echo "FAIL: axis 8: cannot make the lock fixture"; exit 1; }
wantl=$(_mode "$P6/shared/real.lock")
echo "fn f81(): i64 { return 81; }" > "$P6/lib/mod_81.cyr"
rc=0; ( cd "$P6" && umask 022 && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" exec "$D/bin/cyrius" deps --lock ) > "$D/a8.out" 2>&1 || rc=$?
n8=$(grep -c '  lib/mod_[0-9]*\.cyr$' "$P6/shared/real.lock" 2>/dev/null || echo 0)
[ -L "$P6/cyrius.lock" ] || { fail "axis 8: deps --lock REPLACED the symlinked cyrius.lock (rc=$rc)"; a8=1; }
[ "$n8" -eq 81 ] || { fail "axis 8: deps --lock via a symlink did not relock the file it names (rc=$rc, $n8 of 81 lines)"; a8=1; }
[ "$(_mode "$P6/shared/real.lock")" = "$wantl" ] || { fail "axis 8: deps --lock reset the lock's mode: $(_mode "$P6/shared/real.lock"), was $wantl"; a8=1; }
[ "$a8" = 0 ] && echo "  ok: axis 8: cyrfmt --write and deps --lock keep the file's mode (0640/0600 under umask 022) and write THROUGH a symlink (the link stays, the file it names gets the bytes)"

if [ "$FAIL" != 0 ]; then echo "FAIL: tool_writes_never_truncate"; exit 1; fi
echo "PASS tool_writes_never_truncate (a short write fails loudly and leaves the replaced file whole: gen_unicode_data, cyrfmt --write, deps --lock, distlib; no truncating write of a user or tree file in programs/ or cbt/; a replace keeps the file's mode and writes through a symlink)"
