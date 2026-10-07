#!/bin/sh
# Gate: cyriusly's version operand must be a version — `uninstall`, `use` and `install` refuse
# anything else by name, and install / uninstall pass the operand as ARGV, never inside a
# `/bin/sh -c` line (6.6.20, RS-04). Both peers: the compiled programs/cyriusly.cyr (the Linux
# x86_64 tarball) and the shell twin scripts/cyriusly (the aarch64 and macOS tarballs, and
# install.sh's fallback).
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
#   1  uninstall `../versions`, `..`, `6.6.19/`, `6.6.18/../6.6.19`, `./6.6.18` -> exit 1, named,
#      both versions and `current` intact                                     (binary + shell)
#   2  install `6.6.19;touch M`, `$(touch M)`, `6.6.19 | touch M` -> exit 1, named, curl never
#      run, no marker                                                         (binary + shell)
#   3  use `../versions` (the binary's local pin and --global, the shell's switch) -> exit 1,
#      cyrius.cyml and the bin/lib links untouched                           (binary + shell)
#   4  controls: uninstall 6.6.18 removes it and keeps 6.6.19; uninstall of the active 6.6.19 is
#      still refused; install 6.6.20 runs curl once and install.sh sees CYRIUS_VERSION=6.6.20;
#      use 6.6.18 pins it                                                     (binary + shell)
#   5  STATIC: `_cmd_install` / `_cmd_uninstall` in programs/cyriusly.cyr reach no `_exec_shell(`
#      / `exec_cmd(` — the operand never rides in a shell line, even behind the validator
#
# MUTATION LEDGER (2026-10-06, 6.6.20): `_cy_version_ok` answering 1 turns axes 1-3 RED on the
# binary (the store deleted, the injected `touch` RAN, the traversal pin written and --global
# re-pointing bin at versions/../versions/bin); `need_version` answering 0 does the same on the
# shell twin (it quoted the operand, so its axis-2 rows are caught by "curl ran" — it fetched
# `.../cyrius/6.6.19;touch …/scripts/install.sh`); routing uninstall's `rm -rf` back through
# `_exec_shell` turns axis 5 RED. The 6.6.19 tree (both peers) is RED on axes 1-3, and its
# `uninstall 6.6.18/../6.6.19` deleted the ACTIVE 6.6.19 outright.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=cyriusly_version_operand_refused

[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0
bad() { echo "  FAIL $1"; sed -n '1,3p' "$W/err" 2>/dev/null | sed 's/^/    /'; fail=1; }

( cd "$ROOT" && "$CC" < programs/cyriusly.cyr > "$W/cyriusly" 2>/dev/null ) && chmod +x "$W/cyriusly" \
    || { echo "FAIL: $NAME — could not build programs/cyriusly.cyr"; exit 1; }

mkdir -p "$W/fakebin"
cat > "$W/fakebin/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/curl.log"
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
    for v in ../versions .. 6.6.19/ 6.6.18/../6.6.19 ./6.6.18; do
        store; B=$(snap)
        run "$P" uninstall "$v"
        refused "axis 1 [$P] uninstall '$v'" "$B" || a1=1
    done
    [ "$a1" -eq 0 ] && echo "  ok axis 1 [$P]: uninstall refuses five path-shaped operands; the store is intact"

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
    store; B=$(snap)
    run "$P" use ../versions
    refused "axis 3 [$P] use ../versions" "$B" || a3=1
    if [ "$P" = bin ]; then
        store; B=$(snap)
        run bin use ../versions --global
        refused "axis 3 [bin] use ../versions --global" "$B" || a3=1
    fi
    [ "$a3" -eq 0 ] && echo "  ok axis 3 [$P]: use refuses a path-shaped version; no pin written, no link moved"

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
    { [ "$RC" -eq 0 ] && [ "$(wc -l < "$W/curl.log" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q "scripts/install.sh" "$W/curl.log" \
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
    [ "$a4" -eq 0 ] && echo "  ok axis 4 [$P]: a real version still uninstalls, installs (curl once, CYRIUS_VERSION passed) and switches; the active one is still guarded"
done

# ── axis 5: static — no shell line in install / uninstall ───────────────────────────────
a5=0
for f in _cmd_install _cmd_uninstall; do
    body=$(awk -v f="$f" '$0 ~ "^fn " f "\\(" {on=1} on {print} on && /^}/ {exit}' "$ROOT/programs/cyriusly.cyr")
    [ -n "$body" ] || { echo "  FAIL axis 5: could not find fn $f in programs/cyriusly.cyr"; fail=1; a5=1; continue; }
    if printf '%s\n' "$body" | grep -v '^ *#' | grep -qE '_exec_shell\(|exec_cmd\('; then
        echo "  FAIL axis 5: $f runs a shell LINE (_exec_shell / exec_cmd) — its operand must ride as argv"; fail=1; a5=1
    fi
done
[ "$a5" -eq 0 ] && echo "  ok axis 5: _cmd_install and _cmd_uninstall run no shell line"

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (cyriusly uninstall / install / use refuse a non-version operand by name, in both peers; install and uninstall pass it as argv)"
