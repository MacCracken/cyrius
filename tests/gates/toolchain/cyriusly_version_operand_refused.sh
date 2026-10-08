#!/bin/sh
# Gate: cyriusly's version operand must be a version — `uninstall`, `use` and `install` refuse
# anything else by name, and install / uninstall pass the operand as ARGV, never inside a
# `/bin/sh -c` line (6.6.20, RS-04). Both peers: the compiled programs/cyriusly.cyr (the Linux
# x86_64 tarball) and the shell twin scripts/cyriusly (the aarch64 and macOS tarballs, and
# install.sh's fallback). Since 6.7.3 (CVE-103) it also holds the binary's `cmdtools` to the
# ACTIVE install's twin, <home>/versions/<current>/scripts/cyriusly — never the current
# directory's `scripts/cyriusly` — and every store writer to shipping that twin (axes 7 and 9).
#
# THE BUG. `uninstall` built `rm -rf <home>/versions/<ver>` and ran it through /bin/sh -c with no
# check on <ver>; the active-version guard is a string compare. Measured on 6.6.19:
#     CYRIUS_HOME=H cyriusly uninstall ../versions   ->  "Uninstalled Cyrius ../versions", rc 0
# and H held only `current` afterwards — every version gone, the ACTIVE one included. The shell
# twin did the same (`rm -rf "$CYRIUS_HOME/versions/$2"`). `install` spliced the operand into
# `curl … | CYRIUS_VERSION=<ver> sh`, so `install '6.6.19;cmd'` ran `cmd`; `use ../x` wrote that
# pin into cyrius.cyml (or re-pointed ~/.cyrius/bin outside the store with --global).
#
# AXES (a throwaway CYRIUS_HOME holding 6.6.18 + the ACTIVE 6.6.19; a fake `curl` first on PATH,
# so nothing reaches the network: it logs its argv and emits a script recording CYRIUS_VERSION)
#   1  uninstall `../versions`, `..`, `6.6.19/`, `6.6.18/../6.6.19`, `./6.6.18`, `6..6` -> exit 1,
#      named, both versions and `current` intact (`6..6` is the ONLY row the `..` ban alone
#      refuses: the others also fail the leading digit or the `/`)          (binary + shell)
#   2  install `6.6.19;touch M`, `$(touch M)`, `6.6.19 | touch M` -> exit 1, named, curl never
#      run, no marker                                                         (binary + shell)
#   3  use `../versions` and `6..6` (the binary's local pin and --global, the shell's switch) ->
#      exit 1, cyrius.cyml and the bin/lib links untouched                   (binary + shell)
#   4  controls: uninstall 6.6.18 removes it and keeps 6.6.19; uninstall of the active 6.6.19 is
#      still refused; install 6.6.20 runs curl once, on the TAG's installer
#      (`/cyrius/6.6.20/scripts/install.sh` — never the mutable `main`, CVE-21), and install.sh sees
#      CYRIUS_VERSION=6.6.20; use 6.6.18 pins it                              (binary + shell)
#   5  STATIC: `_cmd_install` / `_cmd_uninstall` / `_cmd_cmdtools` in programs/cyriusly.cyr reach
#      no `_exec_shell(` / `exec_cmd(` — the operand never rides in a shell line, even behind the
#      validator
#   6  `use` with no operand (the binary's second [package].cyrius reader, CBT-01): an
#      escape-bearing traversal pin, `../../x`, `6..6` and an unquoted pin -> exit 1, named, the
#      escape shown as \xNN and never raw; controls: `6.6.19`, `6.6.20_rc` (the CLI's pin rule
#      allows `_`) and a literal-string `'6.6.18'` report as pinned                    (binary)
#   7  cmdtools (binary; the store's ACTIVE slot holds the shell twin at scripts/cyriusly):
#      `cmdtools 'list;touch M'` and `cmdtools '$(touch M)' starship` -> the twin ran (its usage
#      line), no marker — the operands are argv, never a shell line. 6.7.3 (CVE-103): the twin is
#      <home>/versions/<current>/scripts/cyriusly, NEVER the CWD's `scripts/cyriusly` —
#        7a  a hostile checkout (its scripts/cyriusly writes a marker): `cmdtools list` lists
#            through the STORE twin and `cmdtools install starship` runs it too; no marker
#        7b  control: an unrelated directory (no scripts/) lists
#        7c  the active slot has no twin -> exit 1, the twin's path named; the checkout's not run
#        7d  `current` = `../evil` (a planted <home>/evil/scripts/cyriusly) -> exit 1, "no active
#            version"; nothing run
#        7e  a RELATIVE CYRIUS_HOME (a plant under the CWD) -> exit 1, "not an absolute path"
#   8  STATIC: `CYRIUS_TARGET_WIN=1` still builds programs/cyriusly.cyr (MZ, no undefined fn)
#   9  every store writer ships the twin to versions/<v>/scripts/cyriusly (6.7.3, CVE-103) — a
#      throwaway HOME / CYRIUS_HOME each, never the live store:
#        9a  install.sh's TARBALL path (a fabricated 9.9.9 tarball, its bin/cyriusly the binary
#            built here): the twin lands byte-identical, and the installed `bin/cyriusly cmdtools
#            list`, run from the hostile checkout, runs the STORE twin
#        9b  install.sh --refresh-only from a mini repo (bins = []): the twin lands
#        9c  a mini repo whose bins ship cyriusly and that has no twin -> exit 1, "shell twin"
#            named, and NOTHING written (the refusal comes before the slot is created)
#        9d  STATIC: the source-bootstrap path installs it; release.yml stages it in both Linux
#            tarballs; both macOS builders stage it
#
# MUTATION LEDGER (2026-10-06, 6.6.20): `_cy_version_ok` answering 1 turns axes 1-3 RED on the
# binary (the store deleted, the injected `touch` RAN, the traversal pin written and --global
# re-pointing bin at versions/../versions/bin); `need_version` answering 0 does the same on the
# shell twin (it quoted the operand, so its axis-2 rows are caught by "curl ran" — it fetched
# `.../cyrius/6.6.19;touch …/scripts/install.sh`); routing uninstall's `rm -rf` back through
# `_exec_shell` turns axis 5 RED. The 6.6.19 tree (both peers) is RED on axes 1-3, and its
# `uninstall 6.6.18/../6.6.19` deleted the ACTIVE 6.6.19 outright.
# Review round 1 (same day): the binary fetching `.../cyrius/main/scripts/install.sh` (the base
# URL, a CVE-21 residual) turns axis 4 [bin] RED. Restoring the base no-operand `use` reader
# turns every axis-6 row RED (the ESC / BEL bytes reached the terminal, `../../x` and `6..6`
# reported as pins, the unquoted pin and the literal string read as the GLOBAL default); checking
# the pin with `_cy_version_ok`'s rule (no `_`) turns the `6.6.20_rc` control RED. The base
# `_cmd_cmdtools` (a `sh scripts/cyriusly cmdtools <a> <t>` line through `_exec_shell`) turns axis
# 5 and both axis-7 injection rows RED. Before the `6..6` rows, deleting the `..` ban from either
# peer left the gate green (every other row also fails the leading digit or the `/`); with them,
# dropping it from `_cy_shape_ok` turns axes 1 and 3 [bin] (and axis 6's `6..6` pin) RED, and
# dropping `|*..*` from `need_version` turns axes 1 and 3 [sh] RED. Dropping `_cy_run_argv`'s
# CYRIUS_TARGET_WIN arm turns axis 8 RED (rc 1, three undefined functions).
# 6.7.3 (CVE-103), measured in scratch copies of the tree: the 6.7.2 `_cmd_cmdtools` (the literal
# "scripts/cyriusly") turns both axis-7 injection rows (the twin never ran: they had passed
# vacuously, rc 127), 7a, 7b, 7c, 7d, 7e and 9a RED (the hostile checkout's script RAN); dropping
# the absolute-home check turns 7e alone RED, dropping the `current` shape check 7d alone, dropping
# the existence check 7c alone (rc 127). Dropping `_install_twin` from install.sh's tarball path
# turns 9a alone RED, from the refresh-only path 9b alone, and dropping the refresh-only pre-check
# 9c alone (the rebuild refusal fires instead, after versions/9.9.9/bin was created); dropping the
# source-bootstrap call, one release.yml copy or a macOS builder's copy turns 9d RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=cyriusly_version_operand_refused

[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0
bad() { echo "  FAIL $1"; sed -n '1,3p' "$W/err" 2>/dev/null | LC_ALL=C tr -c '[:print:]\n' '?' | sed 's/^/    /'; fail=1; }

( cd "$ROOT" && "$CC" < programs/cyriusly.cyr > "$W/cyriusly" 2>/dev/null ) && chmod +x "$W/cyriusly" \
    || { echo "FAIL: $NAME — could not build programs/cyriusly.cyr"; exit 1; }

mkdir -p "$W/fakebin"
# The installer it "serves" records CYRIUS_VERSION. 6.6.20 (SEC-07): cyriusly downloads the installer
# to a private file (`-o`) before running it — `curl | sh` exited 0 when the fetch failed — so the
# fake honours `-o`, and writes to stdout only when it is not given.
cat > "$W/fakebin/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/curl.log"
out=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out=\$2; shift 2 ;; *) shift ;; esac; done
if [ -n "\$out" ]; then exec > "\$out"; fi
printf 'printf "%%s\\\\n" "\$CYRIUS_VERSION" > "%s/installed"\n' "$W"
EOF
chmod +x "$W/fakebin/curl"

H="$W/home/.cyrius"
store() {   # a fresh store: 6.6.18 + the active 6.6.19, both linked the way install.sh links them
    rm -rf "$W/home" "$W/proj" "$W/curl.log" "$W/installed" "$W/pwned"
    for _sv in 6.6.18 6.6.19; do   # not `v`: sh variables are global, and the callers loop on v
        mkdir -p "$H/versions/$_sv/bin" "$H/versions/$_sv/lib"
        echo "$_sv" > "$H/versions/$_sv/bin/STAMP"
    done
    # the shell twin where every writer puts it since 6.7.3 (CVE-103) — `cmdtools` runs this one
    mkdir -p "$H/versions/6.6.19/scripts"
    cp "$ROOT/scripts/cyriusly" "$H/versions/6.6.19/scripts/cyriusly"
    echo 6.6.19 > "$H/current"
    ln -s "$H/versions/6.6.19/bin" "$H/bin"
    ln -s "$H/versions/6.6.19/lib" "$H/lib"
    mkdir -p "$W/proj"
    printf '[package]\nname = "p"\nversion = "0.1.0"\ncyrius = "6.6.19"\n' > "$W/proj/cyrius.cyml"
}
snap() { printf '%s|%s|%s|%s|%s' "$(ls "$H/versions" | tr '\n' ' ')" "$(cat "$H/current" 2>/dev/null)" \
    "$(readlink "$H/bin")" "$(readlink "$H/lib")" "$(cat "$W/proj/cyrius.cyml")"; }
run() {   # run <peer: bin|sh> <args...> -> RC, $W/out, $W/err
    _p=$1; shift
    RC=0
    if [ "$_p" = bin ]; then
        ( cd "$W/proj" && env HOME="$W/home" CYRIUS_HOME="$H" PATH="$W/fakebin:$PATH" "$W/cyriusly" "$@" ) > "$W/out" 2> "$W/err" || RC=$?
    else
        ( cd "$W/proj" && env HOME="$W/home" CYRIUS_HOME="$H" PATH="$W/fakebin:$PATH" sh "$ROOT/scripts/cyriusly" "$@" ) > "$W/out" 2> "$W/err" || RC=$?
    fi
}
refused() {   # refused <label> <snapshot before> — exit 1, named, nothing touched, curl never ran
    _ok=1
    [ "$RC" -eq 1 ] && grep -q "not a version" "$W/err" || _ok=0
    [ "$(snap)" = "$2" ] || { echo "  (state changed: $(snap))"; _ok=0; }
    [ -e "$W/curl.log" ] && { echo "  (curl ran: $(head -1 "$W/curl.log"))"; _ok=0; }
    [ -e "$W/pwned" ] && { echo "  (the injected command RAN)"; _ok=0; }
    [ "$_ok" -eq 1 ] && return 0
    bad "$1: exit $RC"
    return 1
}

for P in bin sh; do
    # ── axis 1: uninstall ───────────────────────────────────────────────────────────────
    a1=0
    for v in ../versions .. 6.6.19/ 6.6.18/../6.6.19 ./6.6.18 6..6; do
        store; B=$(snap)
        run "$P" uninstall "$v"
        refused "axis 1 [$P] uninstall '$v'" "$B" || a1=1
    done
    [ "$a1" -eq 0 ] && echo "  ok axis 1 [$P]: uninstall refuses five path-shaped operands and '6..6'; the store is intact"

    # ── axis 2: install ─────────────────────────────────────────────────────────────────
    a2=0
    for v in "6.6.19;touch $W/pwned" "\$(touch $W/pwned)" "6.6.19 | touch $W/pwned"; do
        store; B=$(snap)
        run "$P" install "$v"
        refused "axis 2 [$P] install '$v'" "$B" || a2=1
    done
    [ "$a2" -eq 0 ] && echo "  ok axis 2 [$P]: install refuses shell-shaped operands; curl never ran, nothing injected"

    # ── axis 3: use ─────────────────────────────────────────────────────────────────────
    a3=0
    for v in ../versions 6..6; do
        store; B=$(snap)
        run "$P" use "$v"
        refused "axis 3 [$P] use $v" "$B" || a3=1
    done
    if [ "$P" = bin ]; then
        store; B=$(snap)
        run bin use ../versions --global
        refused "axis 3 [bin] use ../versions --global" "$B" || a3=1
    fi
    [ "$a3" -eq 0 ] && echo "  ok axis 3 [$P]: use refuses a path-shaped version and '6..6'; no pin written, no link moved"

    # ── axis 4: controls ────────────────────────────────────────────────────────────────
    a4=0
    store
    run "$P" uninstall 6.6.18
    { [ "$RC" -eq 0 ] && [ ! -e "$H/versions/6.6.18" ] && [ -f "$H/versions/6.6.19/bin/STAMP" ]; } \
        || { bad "axis 4 [$P] uninstall 6.6.18: exit $RC, versions: $(ls "$H/versions" | tr '\n' ' ')"; a4=1; }
    store
    run "$P" uninstall 6.6.19
    { [ "$RC" -eq 1 ] && [ -d "$H/versions/6.6.19" ] && grep -q "Cannot uninstall active" "$W/out" "$W/err"; } \
        || { bad "axis 4 [$P] uninstall of the ACTIVE 6.6.19: exit $RC"; a4=1; }
    store
    run "$P" install 6.6.20
    { [ "$RC" -eq 0 ] && [ "$(wc -l < "$W/curl.log" 2>/dev/null | tr -d ' ')" = 1 ] \
        && grep -q "https://raw.githubusercontent.com/MacCracken/cyrius/6\.6\.20/scripts/install\.sh" "$W/curl.log" \
        && [ "$(cat "$W/installed" 2>/dev/null)" = 6.6.20 ]; } \
        || { bad "axis 4 [$P] install 6.6.20: exit $RC, curl: $(cat "$W/curl.log" 2>/dev/null), install.sh saw '$(cat "$W/installed" 2>/dev/null)'"; a4=1; }
    store
    run "$P" use 6.6.18
    if [ "$P" = bin ]; then
        { [ "$RC" -eq 0 ] && grep -q '^cyrius = "6.6.18"$' "$W/proj/cyrius.cyml"; } \
            || { bad "axis 4 [bin] use 6.6.18: exit $RC, manifest: $(grep cyrius "$W/proj/cyrius.cyml")"; a4=1; }
    else
        { [ "$RC" -eq 0 ] && [ "$(cat "$H/current")" = 6.6.18 ] && [ "$(readlink "$H/bin")" = "$H/versions/6.6.18/bin" ]; } \
            || { bad "axis 4 [sh] use 6.6.18: exit $RC, current $(cat "$H/current")"; a4=1; }
    fi
    [ "$a4" -eq 0 ] && echo "  ok axis 4 [$P]: a real version still uninstalls, installs (curl once, on the tag's installer, CYRIUS_VERSION passed) and switches; the active one is still guarded"
done

# ── axis 5: static — no shell line in install / uninstall ───────────────────────────────
a5=0
for f in _cmd_install _cmd_uninstall _cmd_cmdtools; do
    body=$(awk -v f="$f" '$0 ~ "^fn " f "\\(" {on=1} on {print} on && /^}/ {exit}' "$ROOT/programs/cyriusly.cyr")
    [ -n "$body" ] || { echo "  FAIL axis 5: could not find fn $f in programs/cyriusly.cyr"; fail=1; a5=1; continue; }
    if printf '%s\n' "$body" | grep -v '^ *#' | grep -qE '_exec_shell\(|exec_cmd\('; then
        echo "  FAIL axis 5: $f runs a shell LINE (_exec_shell / exec_cmd) — its operand must ride as argv"; fail=1; a5=1
    fi
done
[ "$a5" -eq 0 ] && echo "  ok axis 5: _cmd_install, _cmd_uninstall and _cmd_cmdtools run no shell line"

# ── axis 6: `use` with NO operand reads the [package].cyrius pin — the CLI's pin rule, never echoed
#    raw (binary only: the shell twin's `use` requires an operand) ──────────────────────────────
a6=0
ESC=$(printf '\033'); BEL=$(printf '\007')
setpin() { printf '[package]\nname = "p"\nversion = "0.1.0"\ncyrius = %s\n' "$1" > "$W/proj/cyrius.cyml"; }
pinrefused() {   # pinrefused <label> <expected stderr text>
    { [ "$RC" -eq 1 ] && grep -q "$2" "$W/err" && ! grep -q "pinned in cyrius.cyml" "$W/out"; } && return 0
    bad "axis 6 [bin] use ($1): exit $RC, out: $(head -1 "$W/out" | LC_ALL=C tr -c '[:print:]' '?')"
    return 1
}
store; setpin "\"6.6${ESC}]0;owned${BEL}${ESC}[2J../../x\""
run bin use
pinrefused "an escape-bearing traversal pin" "is not a version" || a6=1
if grep -q "$ESC" "$W/out" "$W/err" || grep -q "$BEL" "$W/out" "$W/err"; then
    bad "axis 6 [bin] use: a raw ESC / BEL byte from the manifest reached the terminal"; a6=1
fi
grep -q '6\.6\\x1b\]0;owned\\x07\\x1b\[2J\.\./\.\./x' "$W/err" \
    || { bad "axis 6 [bin] use: the refusal did not show the pin with its non-printing bytes as \\xNN"; a6=1; }
store; setpin '"../../x"'
run bin use
pinrefused "../../x" "is not a version" || a6=1
store; setpin '"6..6"'
run bin use
pinrefused "6..6" "is not a version" || a6=1
store; setpin '6.6.19'
run bin use
pinrefused "an unquoted pin" "must be a quoted version string" || a6=1
# controls: a quoted pin reports as before; `_` (the CLI's pin rule allows it) and a TOML literal
# string are pins `cyrius` accepts, so cyriusly must too
for row in '"6.6.19"|6.6.19' '"6.6.20_rc"|6.6.20_rc' "'6.6.18'|6.6.18"; do
    store; setpin "${row%%|*}"
    run bin use
    { [ "$RC" -eq 0 ] && [ "$(cat "$W/out")" = "cyrius ${row#*|} (pinned in cyrius.cyml)" ]; } \
        || { bad "axis 6 [bin] use (control cyrius = ${row%%|*}): exit $RC, out: $(head -1 "$W/out" | LC_ALL=C tr -c '[:print:]' '?')"; a6=1; }
done
[ "$a6" -eq 0 ] && echo "  ok axis 6 [bin]: use with no operand refuses an escape-bearing, a traversal, a '..' and an unquoted pin (shown as \\xNN, never raw); '_' and a literal string still report"

# ── axis 7: cmdtools runs the INSTALL's shell twin, its operands as argv — never a
#    scripts/cyriusly from the current directory (6.7.3, CVE-103) ──────────────────────────────
a7=0
hostile() {   # the hostile checkout: $W/proj/scripts/cyriusly records that it ran
    mkdir -p "$W/proj/scripts"
    printf 'touch "%s/pwned"\necho PWNED\n' "$W" > "$W/proj/scripts/cyriusly"
}
ct() {   # ct <CYRIUS_HOME> <args...> — the binary, from $W/proj; the twin's starship edits stay in $W
    _ch=$1; shift
    RC=0
    ( cd "$W/proj" && env HOME="$W/home" CYRIUS_HOME="$_ch" XDG_CONFIG_HOME="$W/home/.config" \
        PATH="$W/fakebin:$PATH" "$W/cyriusly" "$@" ) > "$W/out" 2> "$W/err" || RC=$?
}
ran_hostile() { [ -e "$W/pwned" ] || grep -q PWNED "$W/out" "$W/err"; }
for row in "list;touch $W/pwned|" "\$(touch $W/pwned)|starship"; do
    store
    ct "$H" cmdtools "${row%%|*}" ${row#*|}
    if [ -e "$W/pwned" ]; then bad "axis 7 [bin] cmdtools '${row%%|*}': the injected command RAN"; a7=1
    elif ! grep -q "^Usage: cyriusly cmdtools" "$W/out"; then bad "axis 7 [bin] cmdtools '${row%%|*}': the store twin did not run (exit $RC) — the row is vacuous"; a7=1; fi
done
# 7a: a hostile checkout — `list` and `install starship` both run the STORE twin
store; hostile
ct "$H" cmdtools list
{ [ "$RC" -eq 0 ] && grep -q "^cmdtools integrations:" "$W/out" && ! ran_hostile; } \
    || { bad "axis 7a [bin] cmdtools list in a hostile checkout: exit $RC$(ran_hostile && echo ', the CHECKOUT script RAN')"; a7=1; }
store; hostile
ct "$H" cmdtools install starship
ran_hostile && { bad "axis 7a [bin] cmdtools install starship in a hostile checkout: the CHECKOUT script RAN"; a7=1; }
# 7b: control — an unrelated directory
store
ct "$H" cmdtools list
{ [ "$RC" -eq 0 ] && grep -q "^cmdtools integrations:" "$W/out"; } \
    || { bad "axis 7b [bin] cmdtools list from an unrelated directory (control): exit $RC"; a7=1; }
# 7c: the active slot ships no twin — refused by name, no fallback to the checkout
store; hostile; rm -rf "$H/versions/6.6.19/scripts"
ct "$H" cmdtools list
{ [ "$RC" -eq 1 ] && grep -q "needs the shell twin '$H/versions/6.6.19/scripts/cyriusly'" "$W/err" && ! ran_hostile; } \
    || { bad "axis 7c [bin] cmdtools list, the active slot without a twin: exit $RC"; a7=1; }
# 7d: `current` is a path, not a version
store; hostile; printf '../evil\n' > "$H/current"
mkdir -p "$H/evil/scripts"; cp "$W/proj/scripts/cyriusly" "$H/evil/scripts/cyriusly"
ct "$H" cmdtools list
{ [ "$RC" -eq 1 ] && grep -q "no active version" "$W/err" && ! ran_hostile; } \
    || { bad "axis 7d [bin] cmdtools list, current = ../evil: exit $RC"; a7=1; }
# 7e: a relative CYRIUS_HOME is CWD resolution again
store; hostile; mkdir -p "$W/proj/rel/versions/6.6.19/scripts"; echo 6.6.19 > "$W/proj/rel/current"
cp "$W/proj/scripts/cyriusly" "$W/proj/rel/versions/6.6.19/scripts/cyriusly"
ct rel cmdtools list
{ [ "$RC" -eq 1 ] && grep -q "not an absolute path" "$W/err" && ! ran_hostile; } \
    || { bad "axis 7e [bin] cmdtools list, CYRIUS_HOME=rel: exit $RC"; a7=1; }
[ "$a7" -eq 0 ] && echo "  ok axis 7 [bin]: cmdtools runs the active slot's twin with argv operands; a hostile checkout's scripts/cyriusly never runs; no twin, a path-shaped current and a relative home are refused by name"

# ── axis 8: the argv runner keeps the file compiling for PE ──────────────────────────────────
# `_cy_run_argv` uses lib/process.cyr's POSIX fork/execve internals; without its CYRIUS_TARGET_WIN
# arm the PE build failed (undefined `_read_environ_envp` / `_proc_child_guard` /
# `_proc_wait_deadline`), where 6.6.19's exec_cmd-based file built.
RC=0
( cd "$ROOT" && env CYRIUS_TARGET_WIN=1 "$CC" < programs/cyriusly.cyr > "$W/cyriusly.exe" 2> "$W/err" ) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(head -c 2 "$W/cyriusly.exe")" = MZ ] && ! grep -q "undefined function" "$W/err"; then
    echo "  ok axis 8: programs/cyriusly.cyr still builds for PE (MZ, no undefined function)"
else
    bad "axis 8: CYRIUS_TARGET_WIN=1 build of programs/cyriusly.cyr: exit $RC"
fi

# ── axis 9: every store writer ships the twin to versions/<v>/scripts/cyriusly (6.7.3, CVE-103) ──
# install.sh runs under `env -i` with a throwaway HOME, CYRIUS_HOME, TMPDIR and XDG_CONFIG_HOME
# (its starship block writes there), from a directory with no programs/dlopen-helper.c.
a9=0
IA=$(uname -m); case "$IA" in x86_64|amd64) IA=x86_64 ;; aarch64|arm64) IA=aarch64 ;; *) IA="" ;; esac
IO=$(uname -s | tr '[:upper:]' '[:lower:]'); case "$IO" in linux) IO=linux ;; darwin) IO=macos ;; *) IO="" ;; esac
inst() {   # inst <dir> <home> <args...> — install.sh from <dir> into <home>/store (never named
           # <home>/.cyrius: that is the user's store by definition, which the released-slot guard
           # treats as live — and an untagged mini repo then refuses)
    _d=$1; _h=$2; shift 2
    mkdir -p "$_h/tmp"
    RC=0
    ( cd "$_d" && env -i HOME="$_h" CYRIUS_HOME="$_h/store" PATH="/usr/bin:/bin" TMPDIR="$_h/tmp" \
        XDG_CONFIG_HOME="$_h/.config" "$@" ) > "$W/out" 2>&1 || RC=$?
}
if [ -n "$IA" ] && [ -n "$IO" ]; then
    # 9a: the tarball path
    T9="$W/t9"; S9="$T9/stage/cyrius-9.9.9-$IA-$IO"
    mkdir -p "$S9/bin" "$S9/lib" "$S9/scripts" "$T9/cwd"
    cp "$W/cyriusly" "$S9/bin/cyriusly"
    printf 'fn x(): i64 { return 0; }\n' > "$S9/lib/x.cyr"
    printf 'echo "STORE TWIN: $*"\n' > "$S9/scripts/cyriusly"
    ( cd "$T9/stage" && tar czf "$T9/tb.tar.gz" "cyrius-9.9.9-$IA-$IO" ) || { echo "FAIL: $NAME — cannot build the axis-9 tarball"; exit 1; }
    inst "$T9/cwd" "$T9/home" CYRIUS_VERSION=9.9.9 CYRIUS_INSTALL_TARBALL="$T9/tb.tar.gz" sh "$ROOT/scripts/install.sh"
    if [ "$RC" -ne 0 ] || ! cmp -s "$S9/scripts/cyriusly" "$T9/home/store/versions/9.9.9/scripts/cyriusly"; then
        bad "axis 9a: install.sh (tarball) exit $RC; versions/9.9.9/scripts/cyriusly $( [ -f "$T9/home/store/versions/9.9.9/scripts/cyriusly" ] && echo 'differs from the tarball' || echo 'MISSING')"
        tail -3 "$W/out" | sed 's/^/    /'; a9=1
    else
        store; hostile
        RC=0
        ( cd "$W/proj" && env HOME="$T9/home" CYRIUS_HOME="$T9/home/store" XDG_CONFIG_HOME="$T9/home/.config" \
            "$T9/home/store/bin/cyriusly" cmdtools list ) > "$W/out" 2> "$W/err" || RC=$?
        { [ "$RC" -eq 0 ] && [ "$(cat "$W/out")" = "STORE TWIN: cmdtools list" ] && ! ran_hostile; } \
            || { bad "axis 9a: the INSTALLED bin/cyriusly cmdtools list, from a hostile checkout: exit $RC, out '$(head -1 "$W/out")'"; a9=1; }
    fi
else
    echo "  skip axis 9a: install.sh has no tarball name for $(uname -m)-$(uname -s)"
fi
# 9b / 9c: --refresh-only from a mini repo (untagged, so the released-slot guard proceeds)
M="$W/m9"; mkdir -p "$M/lib" "$M/scripts"
cp "$ROOT/scripts/install.sh" "$M/scripts/install.sh"
printf 'echo "REFRESHED TWIN: $*"\n' > "$M/scripts/cyriusly"
printf '9.9.9\n' > "$M/VERSION"
printf 'fn x(): i64 { return 0; }\n' > "$M/lib/x.cyr"
mini_cyml() { printf '[package]\nname = "m"\nversion = "9.9.9"\n\n[release]\nbins = [%s]\ncross_bins = []\nscripts = []\n' "$1" > "$M/cyrius.cyml"; }
mini_cyml ""
if command -v git >/dev/null 2>&1; then
    ( cd "$M" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm m ) >/dev/null 2>&1
fi
inst "$M" "$W/h9b" sh scripts/install.sh --refresh-only
{ [ "$RC" -eq 0 ] && cmp -s "$M/scripts/cyriusly" "$W/h9b/store/versions/9.9.9/scripts/cyriusly"; } \
    || { bad "axis 9b: install.sh --refresh-only exit $RC; versions/9.9.9/scripts/cyriusly not the tree's twin"; tail -3 "$W/out" | sed 's/^/    /'; a9=1; }
rm -f "$M/scripts/cyriusly"; mini_cyml '"cyriusly"'
inst "$M" "$W/h9c" sh scripts/install.sh --refresh-only
{ [ "$RC" -eq 1 ] && grep -q "shell twin scripts/cyriusly does not exist" "$W/out" && [ ! -e "$W/h9c/store/versions/9.9.9" ]; } \
    || { bad "axis 9c: bins ship cyriusly, no twin: exit $RC, slot $( [ -e "$W/h9c/store/versions/9.9.9" ] && echo CREATED || echo absent)"; tail -2 "$W/out" | sed 's/^/    /'; a9=1; }
# 9d: static — the writers this gate cannot run here
[ "$(grep -c '^ *if _install_twin scripts/cyriusly "\$_BINS"; then' "$ROOT/scripts/install.sh")" = 1 ] \
    || { bad "axis 9d: install.sh's source-bootstrap path does not install the twin (_install_twin scripts/cyriusly \"\$_BINS\")"; a9=1; }
[ "$(grep -c '^ *cp scripts/cyriusly "\$STAGE/scripts/"$' "$ROOT/.github/workflows/release.yml")" = 2 ] \
    || { bad "axis 9d: release.yml does not stage the twin at \$STAGE/scripts/ in BOTH Linux tarballs"; a9=1; }
for mb in build-macos-arm64-tarball.sh build-macos-x86-tarball.sh; do
    grep -q '^cp scripts/cyriusly "\$WORK/\$STAGE/scripts/"$' "$ROOT/scripts/$mb" \
        || { bad "axis 9d: scripts/$mb does not stage the twin at \$WORK/\$STAGE/scripts/"; a9=1; }
done
[ "$a9" -eq 0 ] && echo "  ok axis 9: the tarball and refresh-only paths install the twin at versions/<v>/scripts/cyriusly (the installed binary runs it), a tree whose bins ship cyriusly without it is refused before anything is written, and the source-bootstrap path and all four POSIX tarball builders stage it"

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (cyriusly uninstall / install / use refuse a non-version operand by name, in both peers; install, uninstall and cmdtools pass their operands as argv; cmdtools runs only the active install's shell twin, which every writer ships)"
