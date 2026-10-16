#!/bin/sh
# deps_verify_crlf_checkout.sh — 6.7.12 (D10, the user 2026-10-15). `cyrius deps --verify` and
# `--locked` on a CRLF checkout of a committed lib/ keep the exact-bytes verdict (rc 1) and NAME
# the cause and its remedy; `cyrius init` / `cyrius port` ship `.gitattributes` with `lib/** -text`.
#
# THE DEFECT (issues/archived/2026-10-08-deps-verify-crlf-checkout-mismatch.md). cyrius.lock records the
# SHA-256 of each lib/ file as `cyrius deps` wrote it (LF). A `git -c core.autocrlf=true clone` —
# Git for Windows' default — converts lib/ to CRLF, so `--verify` printed `FAIL: lib/x.cyr (hash
# mismatch)` for every file and `--locked` `its bytes do not match cyrius.lock`, remedied with
# "run `cyrius deps` and commit", which would re-lock the CRLF bytes and churn the lock between a
# Windows and a Linux checkout. Nothing named the line-ending conversion.
#
# THE DECISION (D10): exact bytes stay the proof — a CRLF copy still FAILS (normalising would let
# a CRLF-only rewrite of a locked file pass). A mismatching file whose bytes with CRLF read as LF
# hash to the locked value is named `CRLF checkout: add \`lib/** -text\` to .gitattributes`, with
# one note; when every --locked difference is one, the remedy is that, not `cyrius deps`.
#
# ROWS
#   C1   the filed repro, LF clone: 2 verified, rc 0
#   C1b  its autocrlf clone (the files ARE CRLF): rc 1, 0 verified 2 failed, each FAIL line names
#        the CRLF checkout and the remedy, one note
#   C2   `--locked` on that clone: rc 1, both lines name the CRLF checkout, the lock's other pin is
#        a plain difference, so the remedy stays `run \`cyrius deps\`` + the note; nothing written
#   C2b  the lock's trailer at this VERSION: every difference is CRLF — the remedy is the
#        .gitattributes one, no `run \`cyrius deps\``
#   C3   a real edit is never called CRLF: an extra line in the CRLF alpha.cyr is a plain
#        `(hash mismatch)` beside beta's CRLF line; an LF edit in the LF clone, no note
#   C4   `lib/** -text` committed before the clone: the autocrlf clone keeps LF and verifies 2
#   C5   a resolved stdlib project (`[deps] stdlib`), committed and autocrlf-cloned: `--locked`
#        names each lib/ file `lib/ holds other bytes than the tags resolve — CRLF checkout`, the
#        .gitattributes remedy, nothing written; `--verify` names each; with `lib/** -text`
#        committed, both pass
#   C6   the fold itself, no git: a CRLF split across the 32 KiB read, a lone CR inside and at EOF
#        kept — each named; a CR-only rewrite (LF -> CR) is a plain mismatch
#   C7   `cyrius init` writes .gitattributes (the template, `lib/** -text`); `cyrius port` creates it,
#        appends the line to an existing one without it (its lines kept), leaves one with it
#        byte-unchanged; both --dry-run listings name it
#   W    (wine, named SKIP without it) cyrius.exe `deps --verify` on the C1b clone names the CRLF
#        checkout, rc 1
# Mutations (measured, one at a time): the verify arm dropped -> C1b C3 C5 C6 W RED; the --locked
# kept arm dropped -> C2 C2b RED; the stale arm dropped -> C5 RED; the remedy switch dropped ->
# C2b C5 RED; every CR dropped instead of CRLF -> C6 RED; a CRLF folded within one read only (the
# CR ending a read kept) -> C6 RED; a lone CR at EOF dropped -> C6 RED; the template's line
# removed -> C7a C7b RED.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_verify_crlf_checkout
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found (the rows are git checkouts)"; exit 77; }
command -v sha256sum > /dev/null 2>&1 || { echo "SKIP: $G: sha256sum missing (the filed repro writes its lock with it)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
pass=0; fail=0; skips=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

CLI=${CYRIUS_BIN:-}
if [ -z "$CLI" ]; then
    mkdir -p "$W/bin"
    "$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
      || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
    chmod +x "$W/bin/cyrius"
    CLI="$W/bin/cyrius"
fi
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V" "$H/deps" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

_cy() {   # $1 = the project dir; the rest = the CLI's arguments
    _d=$1; shift
    ( cd "$_d" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CLI" "$@" )
}
_crlf() { grep -c "$(printf '\r')\$" "$1" 2> /dev/null || true; }   # lines ending in CR
_commit() { ( cd "$1" && git add -A && git commit -qm "$2" ); }
_tree() { ( cd "$1" && find lib -type f | sort | xargs sha256sum; sha256sum cyrius.lock ) 2> /dev/null; }
REASON='CRLF checkout: add `lib/** -text` to .gitattributes'
NOTE='differ only by CRLF line endings'

# ── C1: the filed repro, verbatim ─────────────────────────────────────────────────────────────
S="$W/c1"; mkdir -p "$S/up/lib" "$S/up/src"
( cd "$S/up" \
  && printf '[package]\nname = "demo"\nversion = "0.1.0"\n' > cyrius.cyml \
  && printf 'fn a() {\n    return 1;\n}\n' > lib/alpha.cyr && printf 'fn c() {\n    return 3;\n}\n' > lib/beta.cyr \
  && printf 'fn main() { return 0; }\n' > src/main.cyr \
  && { sha256sum lib/alpha.cyr lib/beta.cyr; printf 'cyrius\t6.7.6\n'; } > cyrius.lock \
  && git init -q . && git add -A && git commit -qm init ) || bad "C1 setup: the filed repro's repository"
rc=0; _cy "$S/up" deps --verify > "$W/c1.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -q '^2 verified, 0 failed' "$W/c1.out"; then ok "C1 the LF clone: 2 verified, rc 0"
else bad "C1 the LF clone (rc $rc): $(tr '\n' ' ' < "$W/c1.out")"; fi
( cd "$S" && git -c core.autocrlf=true clone -q up co ) || bad "C1b setup: the autocrlf clone"
rc=0; _cy "$S/co" deps --verify > "$W/c1b.out" 2>&1 || rc=$?
ca=$(_crlf "$S/co/lib/alpha.cyr"); cb=$(_crlf "$S/co/lib/beta.cyr")
if [ "$ca" -eq 3 ] && [ "$cb" -eq 3 ] && [ "$rc" -eq 1 ] && grep -q '^0 verified, 2 failed' "$W/c1b.out" \
   && grep -qF "  FAIL: lib/alpha.cyr (hash mismatch — $REASON)" "$W/c1b.out" \
   && grep -qF "  FAIL: lib/beta.cyr (hash mismatch — $REASON)" "$W/c1b.out" \
   && [ "$(grep -c "^note: 2 files in lib/ $NOTE" "$W/c1b.out")" -eq 1 ] \
   && grep -qF 'Commit `lib/** -text` in .gitattributes and check lib/ out again' "$W/c1b.out"; then
    ok "C1b the autocrlf clone (3 + 3 CRLF lines): rc 1, both FAIL lines name the CRLF checkout, one note"
else bad "C1b the autocrlf clone (rc $rc, CRLF lines $ca/$cb): $(tr '\n' ' ' < "$W/c1b.out")"; fi

# ── C2 / C2b: --locked ───────────────────────────────────────────────────────────────────────
before=$(_tree "$S/co")
rc=0; _cy "$S/co" deps --locked > "$W/c2.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] \
   && grep -qF "  differs: lib/alpha.cyr: its bytes do not match cyrius.lock — $REASON" "$W/c2.out" \
   && grep -qF "  differs: lib/beta.cyr: its bytes do not match cyrius.lock — $REASON" "$W/c2.out" \
   && grep -qF '  differs: cyrius.lock records another stdlib pin than' "$W/c2.out" \
   && grep -qF 'error: --locked: 3 difference(s)' "$W/c2.out" && grep -qF 'run `cyrius deps` and commit the result' "$W/c2.out" \
   && grep -q "^note: 2 files in lib/ $NOTE" "$W/c2.out" && [ "$before" = "$(_tree "$S/co")" ]; then
    ok "C2 --locked: both files named CRLF, the other pin a plain difference (remedy kept + the note), nothing written"
else bad "C2 --locked (rc $rc): $(tr '\n' ' ' < "$W/c2.out")"; fi
sed -i "s/^cyrius\t6.7.6\$/cyrius\t$V/" "$S/up/cyrius.lock" && ( cd "$S/up" && git commit -qam pin ) || bad "C2b setup: the trailer"
( cd "$S" && rm -rf co2 && git -c core.autocrlf=true clone -q up co2 ) || bad "C2b setup: the clone"
rc=0; _cy "$S/co2" deps --locked > "$W/c2b.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && [ "$(grep -cF -- "do not match cyrius.lock — $REASON" "$W/c2b.out")" -eq 2 ] \
   && grep -qF "error: --locked: 2 difference(s) between what the tags resolve and the committed lib/ + cyrius.lock (named above); nothing was written — $REASON" "$W/c2b.out" \
   && ! grep -qF 'run `cyrius deps`' "$W/c2b.out" && grep -q "^note: 2 files in lib/ $NOTE" "$W/c2b.out"; then
    ok "C2b every --locked difference a CRLF checkout: the remedy is .gitattributes, not cyrius deps"
else bad "C2b (rc $rc): $(tr '\n' ' ' < "$W/c2b.out")"; fi

# ── C3: a real edit is not a CRLF checkout ──────────────────────────────────────────────────
printf 'fn extra() {\r\n}\r\n' >> "$S/co2/lib/alpha.cyr"
rc=0; _cy "$S/co2" deps --verify > "$W/c3.out" 2>&1 || rc=$?
printf 'fn b2() {}\n' >> "$S/up/lib/beta.cyr"
rc2=0; _cy "$S/up" deps --verify > "$W/c3l.out" 2>&1 || rc2=$?
if [ "$rc" -eq 1 ] && grep -qxF '  FAIL: lib/alpha.cyr (hash mismatch)' "$W/c3.out" \
   && grep -qF "  FAIL: lib/beta.cyr (hash mismatch — $REASON)" "$W/c3.out" && grep -q "^note: 1 file in lib/ differs only" "$W/c3.out" \
   && [ "$rc2" -eq 1 ] && grep -qxF '  FAIL: lib/beta.cyr (hash mismatch)' "$W/c3l.out" && ! grep -q '^note:' "$W/c3l.out"; then
    ok "C3 an edited CRLF file and an edited LF file are plain mismatches (no CRLF name, no note for the LF one)"
else bad "C3 (rc $rc / $rc2): $(tr '\n' ' ' < "$W/c3.out") || $(tr '\n' ' ' < "$W/c3l.out")"; fi
( cd "$S/up" && git checkout -q -- lib )

# ── C4: lib/** -text committed before the clone ─────────────────────────────────────────────
printf 'lib/** -text\n' > "$S/up/.gitattributes" && _commit "$S/up" attrs > /dev/null || bad "C4 setup"
( cd "$S" && rm -rf co4 && git -c core.autocrlf=true clone -q up co4 ) || bad "C4 setup: the clone"
rc=0; _cy "$S/co4" deps --verify > "$W/c4.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -q '^2 verified, 0 failed' "$W/c4.out" && [ "$(_crlf "$S/co4/lib/alpha.cyr")" -eq 0 ]; then
    ok "C4 with lib/** -text committed the autocrlf clone keeps LF: 2 verified, rc 0"
else bad "C4 (rc $rc): $(tr '\n' ' ' < "$W/c4.out")"; fi

# ── C5: a resolved stdlib project — the --locked stale arm ──────────────────────────────────
P="$W/c5/up"; mkdir -p "$P"
printf '[package]\nname = "crlfp"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "main.cyr"\noutput = "build/main"\n\n[deps]\nstdlib = ["string"]\n' "$V" > "$P/cyrius.cyml"
printf 'syscall(SYS_EXIT, 0);\n' > "$P/main.cyr"
_cy "$P" deps > "$W/c5d.out" 2>&1 || bad "C5 setup: deps: $(tail -2 "$W/c5d.out")"
( cd "$P" && git init -q . && git add -A && git commit -qm init ) || bad "C5 setup: commit"
nf=$(cd "$P" && find lib -name '*.cyr' | wc -l | tr -d ' ')
( cd "$W/c5" && git -c core.autocrlf=true clone -q up co ) || bad "C5 setup: the clone"
before=$(_tree "$W/c5/co")
rc=0; _cy "$W/c5/co" deps --locked > "$W/c5.out" 2>&1 || rc=$?
ns=$(grep -cF -- ": lib/ holds other bytes than the tags resolve — $REASON" "$W/c5.out" || true)
rv=0; _cy "$W/c5/co" deps --verify > "$W/c5v.out" 2>&1 || rv=$?
nv=$(grep -cF -- "(hash mismatch — $REASON)" "$W/c5v.out" || true)
if [ "$nf" -gt 0 ] && [ "$rc" -eq 1 ] && [ "$ns" -eq "$nf" ] \
   && grep -qF "difference(s) between what the tags resolve and the committed lib/ + cyrius.lock (named above); nothing was written — $REASON" "$W/c5.out" \
   && ! grep -qF 'run `cyrius deps`' "$W/c5.out" && [ "$before" = "$(_tree "$W/c5/co")" ] \
   && [ "$rv" -eq 1 ] && [ "$nv" -eq "$nf" ]; then
    ok "C5 a resolved stdlib project's autocrlf clone: --locked names all $nf files CRLF (the .gitattributes remedy, nothing written), --verify too"
else bad "C5 (locked rc $rc: $ns of $nf named; verify rc $rv: $nv): $(grep -v '^  differs' "$W/c5.out" | tr '\n' ' ')"; fi
printf 'lib/** -text\n' > "$P/.gitattributes" && _commit "$P" attrs > /dev/null || bad "C5b setup"
( cd "$W/c5" && rm -rf co2 && git -c core.autocrlf=true clone -q up co2 ) || bad "C5b setup: the clone"
rc=0; _cy "$W/c5/co2" deps --locked > "$W/c5b.out" 2>&1 || rc=$?
rv=0; _cy "$W/c5/co2" deps --verify > "$W/c5bv.out" 2>&1 || rv=$?
if [ "$rc" -eq 0 ] && grep -qF -- '--locked: lib/ and cyrius.lock are exactly what the tags resolve' "$W/c5b.out" \
   && [ "$rv" -eq 0 ] && grep -q "^$nf verified, 0 failed" "$W/c5bv.out"; then
    ok "C5b with lib/** -text committed: --locked clean, $nf verified"
else bad "C5b (locked rc $rc, verify rc $rv): $(tr '\n' ' ' < "$W/c5b.out") $(tail -1 "$W/c5bv.out")"; fi

# ── C6: the fold, no git ────────────────────────────────────────────────────────────────────
F="$W/c6"; mkdir -p "$F/lib"
# split: a 32767-byte first line, so the CRLF copy's CR is the first read's last byte
head -c 32767 /dev/zero | tr '\0' a > "$F/lib/split.cyr" && printf '\ntail\n' >> "$F/lib/split.cyr"
printf 'x\ry\nz\n' > "$F/lib/lonecr.cyr"     # a lone CR inside, kept by the fold
printf 'a\nb\r' > "$F/lib/eofcr.cyr"         # a lone CR as the last byte
printf 'p\nq\n' > "$F/lib/maccr.cyr"         # rewritten LF -> CR below: not a CRLF checkout
printf '[package]\nname = "fold"\nversion = "0.1.0"\n' > "$F/cyrius.cyml"
( cd "$F" && { sha256sum lib/eofcr.cyr lib/lonecr.cyr lib/maccr.cyr lib/split.cyr; printf 'cyrius\t%s\n' "$V"; } > cyrius.lock )
for f in split lonecr; do sed -i 's/$/\r/' "$F/lib/$f.cyr"; done
printf 'a\r\nb\r' > "$F/lib/eofcr.cyr"       # what autocrlf makes of it (the CR at EOF has no LF)
printf 'p\rq\r' > "$F/lib/maccr.cyr"
rc=0; _cy "$F" deps --verify > "$W/c6.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -q '^0 verified, 4 failed' "$W/c6.out" \
   && grep -qF "  FAIL: lib/split.cyr (hash mismatch — $REASON)" "$W/c6.out" \
   && grep -qF "  FAIL: lib/lonecr.cyr (hash mismatch — $REASON)" "$W/c6.out" \
   && grep -qF "  FAIL: lib/eofcr.cyr (hash mismatch — $REASON)" "$W/c6.out" \
   && grep -qxF '  FAIL: lib/maccr.cyr (hash mismatch)' "$W/c6.out" && grep -q "^note: 3 files in lib/ $NOTE" "$W/c6.out"; then
    ok "C6 the fold: a CRLF across the 32 KiB read, a lone CR inside and at EOF named; an LF -> CR rewrite plain"
else bad "C6 (rc $rc): $(tr '\n' ' ' < "$W/c6.out")"; fi

# ── C7: cyrius init / port ship the .gitattributes ──────────────────────────────────────────
R="$W/root"; mkdir -p "$R/bin" "$R/programs" "$W/ih"
"$CC" < programs/cyrius-init.cyr > "$R/bin/cyrius-init" 2> "$W/init.err" && chmod +x "$R/bin/cyrius-init" \
  || bad "C7 setup: programs/cyrius-init.cyr does not build: $(tail -2 "$W/init.err")"
cp -r programs/cyrius-init-templates "$R/programs/"
_ini() {   # $1 = the working directory; the rest = cyrius-init's arguments
    _d=$1; shift
    ( cd "$_d" && HOME="$W/ih" CYRIUS_HOME="$W/ih/.cyrius" XDG_CONFIG_HOME="$W/ih/.config" CYRIUS_VER="$V" exec "$R/bin/cyrius-init" "$@" )
}
mkdir -p "$W/i"
rc=0; _ini "$W/i" demo > "$W/c7i.out" 2>&1 || rc=$?
dr=0; _ini "$W/i" --dry-run other > "$W/c7d.out" 2>&1 || dr=$?
if [ "$rc" -eq 0 ] && cmp -s "$W/i/demo/.gitattributes" programs/cyrius-init-templates/gitattributes \
   && grep -qx 'lib/\*\* -text' "$W/i/demo/.gitattributes" && [ "$dr" -eq 0 ] && grep -q '/\.gitattributes ' "$W/c7d.out"; then
    ok "C7a cyrius init writes .gitattributes (lib/** -text); --dry-run lists it"
else bad "C7a init (rc $rc, dry $dr): $(tail -3 "$W/c7i.out" | tr '\n' ' ')"; fi
_rs() { rm -rf "$W/pt/$1"; mkdir -p "$W/pt/$1/src"; printf '[package]\nname = "%s"\n' "$1" > "$W/pt/$1/Cargo.toml"; printf 'fn main() {}\n' > "$W/pt/$1/src/main.rs"; }
_rs ra; _rs rb; _rs rc
printf '* text=auto\n*.png binary' > "$W/pt/rb/.gitattributes"          # no newline at its end
printf '* text=auto\nlib/** -text\n' > "$W/pt/rc/.gitattributes"; cp "$W/pt/rc/.gitattributes" "$W/rc.ga"
r1=0; _ini "$W/pt" --__mode=port ra > "$W/c7a.out" 2>&1 || r1=$?
r2=0; _ini "$W/pt" --__mode=port rb > "$W/c7b.out" 2>&1 || r2=$?
r3=0; _ini "$W/pt" --__mode=port rc > "$W/c7c.out" 2>&1 || r3=$?
_rs rd; r4=0; _ini "$W/pt" --__mode=port --dry-run rd > "$W/c7e.out" 2>&1 || r4=$?
if [ "$r1$r2$r3$r4" = "0000" ] && cmp -s "$W/pt/ra/.gitattributes" programs/cyrius-init-templates/gitattributes \
   && grep -qx 'lib/\*\* -text' "$W/pt/ra/.gitattributes" \
   && grep -q '^  Created .gitattributes' "$W/c7a.out" \
   && [ "$(sed -n 1p "$W/pt/rb/.gitattributes")" = '* text=auto' ] && [ "$(sed -n 2p "$W/pt/rb/.gitattributes")" = '*.png binary' ] \
   && [ "$(grep -cx 'lib/\*\* -text' "$W/pt/rb/.gitattributes")" -eq 1 ] && grep -q '^  Appended lib/\*\* -text to existing .gitattributes' "$W/c7b.out" \
   && cmp -s "$W/pt/rc/.gitattributes" "$W/rc.ga" && ! grep -q 'gitattributes' "$W/c7c.out" \
   && grep -q '^  \.gitattributes ' "$W/c7e.out" && [ ! -e "$W/pt/rd/.gitattributes" ]; then
    ok "C7b cyrius port creates .gitattributes, appends lib/** -text to one without it (its lines kept), leaves one with it; --dry-run lists it"
else bad "C7b port (rc $r1$r2$r3$r4): $(grep -i 'gitattributes\|error' "$W/c7a.out" "$W/c7b.out" "$W/c7c.out" | tr '\n' ' ')"; fi

# ── W: the PE CLI under wine ────────────────────────────────────────────────────────────────
if command -v wine > /dev/null 2>&1; then
    WP="$W/wine"; WHM="$W/whome"
    export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    _wine_down() {
        [ -d "$WP" ] || return 0
        _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
        WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
        WINEPREFIX="$WP" wineserver -w > /dev/null 2>&1 || true
        rm -rf "$_ws" || true
    }
    trap '_wine_down; rm -rf "$W"' EXIT
    HW=$(winepath -w "$H" 2> /dev/null)
    "$CC" < src/main_win.cyr > "$W/cc_win" 2> /dev/null && chmod +x "$W/cc_win" \
      && "$W/cc_win" < cbt/cyrius.cyr > "$W/cyrius.exe" 2> "$W/pe.err" && [ -s "$W/cyrius.exe" ] \
      || bad "W setup: the PE CLI does not cross-build: $(grep -m1 -E 'error' "$W/pe.err")"
    rc=0; ( cd "$S/co" && CYRIUS_HOME="$HW" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 timeout 300 wine "$W/cyrius.exe" deps --verify ) > "$W/w.out" 2>&1 || rc=$?
    tr -d '\r' < "$W/w.out" > "$W/w.txt"
    if [ "$rc" -eq 1 ] && grep -q '^0 verified, 2 failed' "$W/w.txt" \
       && [ "$(grep -cF -- "(hash mismatch — $REASON)" "$W/w.txt")" -eq 2 ] && grep -q "^note: 2 files in lib/ $NOTE" "$W/w.txt"; then
        ok "W wine: cyrius.exe deps --verify names both CRLF files, rc 1"
    else bad "W wine (rc $rc): $(tr '\n' ' ' < "$W/w.txt")"; fi
else
    echo "  SKIP: W — wine not found; the PE leg runs where wine is installed, and on cass"
    skips=$((skips+1))
fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$skips" -eq 0 ] || exit 77
exit 0
