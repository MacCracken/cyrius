#!/bin/sh
# cli_fork_failure_named.sh — 6.6.20 (CBTB-03). When the `cyrius` CLI cannot fork (a process
# limit — `ulimit -u`, a cgroup pids.max — or memory) every verb says so BY NAME, exits
# non-zero, and leaves nothing behind; and no spawner decodes a wait status nobody wrote.
#
# THE DEFECT. `sys_fork` answers -errno when it fails, and the spawners went straight on to
# `sys_waitpid(-errno, ...)` — wait4 on a process GROUP, which fails and writes nothing — and
# decoded the unwritten status slot (cyrius does not zero locals). The stack decided the
# verdict. Measured at 6.6.19 under `ulimit -u 1`:
#   cyrius build src/main.cyr out  -> "OK (0 bytes)", exit 0, and the write-probe's EMPTY temp
#                                     renamed over a working 4456-byte `out` (which then "ran"
#                                     as an empty shell script, exit 0)
#   cyrius fmt --check bad.cyr     -> exit 184 / 110, no message
#   cyrius run / test              -> "the compiler did not exit normally" (a wrong reason)
# Only run_binary_timed (6.6.10) had a `pid < 0` arm. The same unwritten slot is decoded when
# the WAIT fails (an inherited SIGCHLD=SIG_IGN makes wait4 answer ECHILD), so every site now
# zeroes the slot and decodes it only when wait4 answered the child's pid.
#
# AXES
#   0  the detector (axis 4) is proved on synthetic shapes first.
#   1  precondition: a fork really fails under `ulimit -u 1` here (a tiny probe program). Not
#      enforced (root / CAP_SYS_RESOURCE) = SKIP by name — the rows below would test nothing.
#   2  ⭐ every forking verb under `ulimit -u 1`: non-zero, "fork failed" named, and no damage —
#      build keeps the old binary byte-for-byte and leaves no temp (not even the CLI's private
#      temp dir's contents); --target=js keeps the old .js; the cx compiler / cxvm JIT builds,
#      --target=cx, `run x.cyx`, fmt, run, capacity, self, `hooks install` (sys_system), and
#      distlib's per-target sidecar verify (refused for that reason, not "does not compile").
#   3  the LSP's two diagnostics spawns (raw cycc outside a project, the `cyrius` wrapper inside
#      one) log the fork failure instead of publishing silently empty diagnostics.
#   4  derived: every `sys_fork()` in cbt/ and programs/cyrius-lsp.cyr is checked for failure in
#      its fn (or handed back to the caller), and no `sys_waitpid` result is thrown away.
#   5  control: without the limit, the same build succeeds (the rows are about the limit).
#   6  ⭐ an inherited SIGCHLD ignore (`trap '' CHLD; exec cyrius ...` — under it the kernel reaps
#      every child and wait4 answers ECHILD): the CLI resets SIGCHLD at start-up, so a good
#      build succeeds and a failing one fails on the COMPILER's verdict, old binary kept. Then
#      the backstop, in a scratch CLI built with that reset deleted: the unreadable status is
#      named ("wait failed"), the old binary is kept and no temp is left — never decoded as
#      "exited 0" (6.6.19: `OK (0 bytes)`, exit 0, an empty file over a working binary).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=cli_fork_failure_named
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
[ "$(uname -s)" = Linux ] || { echo "SKIP: $G: driven on Linux (ulimit -u + /proc)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
ulimit -c 0 2>/dev/null
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── axis 0 + 4 — the detector, then the sources ─────────────────────────────────────────
cat > "$W/sites.awk" <<'AWK'
function flush(   i, v, ok) {
    for (i = 1; i <= nf; i++) {
        v = fv[i]
        ok = (body ~ ("[^A-Za-z0-9_]" v "[ \t]*[<>]=?[ \t]*0") || body ~ ("return[ \t]+" v "[ \t]*;"))
        printf "%s fn=%s pid=%s %s\n", fl[i], fname, v, (ok ? "checked" : "UNCHECKED")
    }
    nf = 0; body = ""
}
FNR == 1 { flush(); fname = "" }
/^fn [A-Za-z_]/ { flush(); fname = $2; sub(/\(.*/, "", fname) }
{ code = $0; gsub(/"[^"]*"/, "", code); sub(/#.*/, "", code); body = body "\n " code }
code ~ /=[ \t]*sys_fork\(\)/ {
    m = code; sub(/^[ \t]*(var[ \t]+)?/, "", m); sub(/[ \t]*=.*/, "", m)
    nf++; fv[nf] = m; fl[nf] = FILENAME ":" FNR
}
code ~ /^[ \t]*sys_waitpid\(/ { printf "%s:%d fn=%s BARE-WAIT\n", FILENAME, FNR, fname }
END { flush() }
AWK
cat > "$W/self.cyr" <<'EOF'
fn unchecked(): i64 {
    var pid = sys_fork();
    if (pid == 0) { sys_exit(0); }
    var st[8];
    sys_waitpid(pid, &st, 0);
    return 0;
}
fn checked_lt(): i64 {
    var pid = sys_fork();
    if (pid < 0) { return 1; }
    return 0;
}
fn checked_gt(): i64 {
    var gpid = sys_fork();
    if (gpid > 0) { var w = sys_waitpid(gpid, 0, 0); }
    return 0;
}
fn handed_back(): i64 {
    var pid = sys_fork();
    return pid;
}
fn prose_only(): i64 {
    # sys_fork() in a comment, and sys_waitpid( too
    var s = "var pid = sys_fork();";
    return 0;
}
EOF
awk -f "$W/sites.awk" "$W/self.cyr" > "$W/self.out"
x=$FAIL
[ "$(grep -c 'fn=' "$W/self.out")" = 5 ] || fail "axis 0: the detector should report 4 forks + 1 bare wait: $(tr '\n' '|' < "$W/self.out")"
grep -q 'fn=unchecked pid=pid UNCHECKED' "$W/self.out" || fail "axis 0: the unchecked fork was not flagged"
grep -q 'fn=unchecked BARE-WAIT' "$W/self.out" || fail "axis 0: the discarded wait was not flagged"
grep -q 'fn=checked_lt pid=pid checked' "$W/self.out" || fail "axis 0: a pid < 0 arm was not recognised"
grep -q 'fn=checked_gt pid=gpid checked' "$W/self.out" || fail "axis 0: a gpid > 0 guard was not recognised"
grep -q 'fn=handed_back pid=pid checked' "$W/self.out" || fail "axis 0: a pid handed back to the caller was not recognised"
grep -q 'fn=prose_only' "$W/self.out" && fail "axis 0: prose / a string literal was counted as a site"
[ "$FAIL" = "$x" ] && echo "  ok axis 0: the detector flags an unchecked fork and a discarded wait, and clears the three checked shapes"

x=$FAIL
awk -f "$W/sites.awk" cbt/*.cyr programs/cyrius-lsp.cyr > "$W/sites"
NS=$(grep -c ' pid=' "$W/sites" || true)
# A floor, not an equality: a new site is welcome, it just has to be checked. 17 at 6.6.20
# (build.cyr 9, deps.cyr 3, commands.cyr 2, pulsar.cyr 1, cyrius-lsp.cyr 2) — 18 until
# _ensure_cc_cx and _ensure_cxvm shared one fork in _cx_jit_build (6.6.20 sec-symlink).
[ "$NS" -ge 17 ] || fail "axis 4: only $NS fork sites found — the detector has stopped seeing them"
grep 'UNCHECKED' "$W/sites" | sed 's/^/      /' > "$W/bad" || true
[ -s "$W/bad" ] && { fail "axis 4: a fork whose failure nobody checks:"; cat "$W/bad"; }
grep 'BARE-WAIT' "$W/sites" | sed 's/^/      /' > "$W/bad" || true
[ -s "$W/bad" ] && { fail "axis 4: a sys_waitpid whose result is thrown away (its status slot may be unwritten):"; cat "$W/bad"; }
[ "$FAIL" = "$x" ] && echo "  ok axis 4: all $NS fork sites in cbt/ + cyrius-lsp check the fork, and no wait result is discarded"

# ── axis 1 — does a fork fail under the limit here? ─────────────────────────────────────
# RLIMIT_NPROC is `ulimit -u` in bash and `ulimit -p` in dash; it counts every process the user
# already has, so a limit of 1 fails any fork. The subshell takes the limit and then `exec`s the
# program without forking again; the limit dies with it, never reaching this script.
lim() { ( ulimit -u 1 2>/dev/null || ulimit -p 1 2>/dev/null || exit 3; exec "$@" ); }
cat > "$W/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
var pid = sys_fork();
if (pid == 0) { sys_exit(0); }
if (pid < 0) { sys_exit(0); }
var st[8];
sys_waitpid(pid, &st, 0);
sys_exit(1);
EOF
"$CC" < "$W/probe.cyr" > "$W/probe" 2> "$W/probe.err" && chmod +x "$W/probe" \
    || { echo "FAIL: $G: the fork probe does not build"; tail -3 "$W/probe.err"; exit 1; }
if ! lim "$W/probe"; then
    [ "$FAIL" = 0 ] || exit 1
    echo "SKIP: $G: a fork still succeeds under 'ulimit -u 1' here (root, or CAP_SYS_RESOURCE) — the verb rows cannot run (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "  ok axis 1: a fork fails under 'ulimit -u 1' on this host"

# ── setup — the CLI and LSP from this tree, a throwaway home and project ────────────────
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/b.err" && chmod +x "$W/cyrius" \
    || { echo "FAIL: $G: cbt/cyrius.cyr does not build"; tail -3 "$W/b.err"; exit 1; }
"$CC" < programs/cyrius-lsp.cyr > "$W/cyrius-lsp" 2> "$W/l.err" && chmod +x "$W/cyrius-lsp" \
    || { echo "FAIL: $G: programs/cyrius-lsp.cyr does not build"; tail -3 "$W/l.err"; exit 1; }
H="$W/home"; mkdir -p "$H/bin" "$W/p/src" "$W/x/src" "$W/t"
ln -s "$CC" "$H/bin/cycc"
printf '#!/bin/sh\nexit 0\n' > "$W/stubtool"; chmod +x "$W/stubtool"
cp "$W/stubtool" "$H/bin/cyrfmt"       # fmt's tool: present, so the verb gets as far as the spawn
printf 'fn main(): i64 { return 42; }\nvar r = main();\nsyscall(60, r);\n' > "$W/p/src/main.cyr"
printf 'fn  x( ) :i64{return 1;}\n' > "$W/p/bad.cyr"
printf 'let x: number = 1;\n' > "$W/p/t.ts"
printf 'stale js\n' > "$W/p/old.js"
# SIGCHLD ignored, as an exec'd program inherits it (bash and dash both pass `trap ''` on).
ign() { ( trap '' CHLD; exec "$@" ); }
# cyrius ($CLI, default the tree's) with an empty private TMPDIR per run; $1 = "lim" (under
# ulimit -u 1), "ign" (SIGCHLD ignored) or "free"
cy() {
    mode=$1; shift
    rm -rf "$W/t"; mkdir -p "$W/t"
    RC=0
    case $mode in
        lim) pre=lim ;;
        ign) pre=ign ;;
        *)   pre= ;;
    esac
    ( cd "$WD" && $pre env -i HOME="$H" PATH=/usr/bin:/bin TMPDIR="$W/t" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 \
        "${CLI:-$W/cyrius}" "$@" ) > "$W/out" 2>&1 || RC=$?
}
# named <row>: non-zero, and the fork failure named
named() {
    [ "$RC" -ne 0 ] || fail "$1: exited 0 under a process limit: $(head -2 "$W/out" | tr '\n' ' ')"
    grep -q 'fork failed' "$W/out" || fail "$1: the fork failure is not named: $(head -3 "$W/out" | tr '\n' ' ')"
}
left() { find "$W/t" -type f | sed "s|$W/t/||" | tr '\n' ' '; }

# ── axis 5 — control: no limit, the build works ─────────────────────────────────────────
WD="$W/p"
cy free build src/main.cyr out
[ "$RC" = 0 ] && [ -s "$W/p/out" ] || { echo "FAIL: $G: control: the unlimited build failed (rc $RC): $(head -3 "$W/out")"; exit 1; }
cp "$W/p/out" "$W/good"
echo "  ok axis 5: control — without the limit the same build succeeds ($(wc -c < "$W/good" | tr -d ' ') B)"

# ── axis 2 — every forking verb under the limit ─────────────────────────────────────────
x=$FAIL
cy lim build src/main.cyr out; named "build"
cmp -s "$W/p/out" "$W/good" || fail "build: the existing binary was replaced ($(wc -c < "$W/p/out" | tr -d ' ') B, was $(wc -c < "$W/good" | tr -d ' ') B)"
ls "$W/p" | grep -q '\.tmp\.' && fail "build: a temp output was left next to it: $(ls "$W/p" | grep '\.tmp\.' | tr '\n' ' ')"
[ -z "$(left)" ] || fail "build: files left in the CLI's private temp dir: $(left)"
cy lim build --target=js t.ts old.js; named "build --target=js"
[ "$(cat "$W/p/old.js")" = "stale js" ] || fail "build --target=js: the existing .js was replaced"
cy lim fmt --check bad.cyr; named "fmt --check (run_tool_vec)"
cy lim run src/main.cyr; named "run"
cy lim capacity src/main.cyr; named "capacity"
[ -z "$(left)" ] || fail "capacity: files left in the CLI's private temp dir: $(left)"
[ "$FAIL" = "$x" ] && echo "  ok axis 2a: build (old binary kept, no temp left), --target=js (old .js kept), fmt, run, capacity — each names the fork failure and exits non-zero"

x=$FAIL
# The cx toolchain, JIT-built (no cycc_cx / cxvm installed, sources present) and installed.
WD="$W/x"; printf '# placeholder\n' > "$W/x/src/main_cx.cyr"; mkdir -p "$W/x/programs"; printf '# placeholder\n' > "$W/x/programs/cxvm.cyr"
cp "$W/p/src/main.cyr" "$W/x/m.cyr"; printf 'not bytecode\n' > "$W/x/m.cyx"
cy lim build --target=cx m.cyr m.cyx; named "build --target=cx (the cycc_cx JIT build)"
cy lim run m.cyx; named "run x.cyx (the cxvm JIT build)"
cp "$W/stubtool" "$H/bin/cycc_cx"; cp "$W/stubtool" "$H/bin/cxvm"
cy lim build --target=cx m.cyr m.cyx; named "build --target=cx (cycc_cx installed)"
[ "$(cat "$W/x/m.cyx")" = "not bytecode" ] || fail "build --target=cx: the existing .cyx was replaced"
cy lim run m.cyx; named "run x.cyx (cxvm installed)"
rm -f "$H/bin/cycc_cx" "$H/bin/cxvm"
[ "$FAIL" = "$x" ] && echo "  ok axis 2b: the cx compiler and cxvm builds, --target=cx (old .cyx kept) and run .cyx — each names the fork failure"

x=$FAIL
WD="$W/x"; printf 'placeholder\n' > "$W/x/src/main.cyr"
cy lim self; named "self (_pulsar_raw_compile)"
mkdir -p "$W/x/.git/hooks" "$W/x/scripts/hooks"; printf '#!/bin/sh\n' > "$W/x/scripts/hooks/pre-commit"
cy lim hooks install; named "hooks install (sys_system)"
[ -f "$W/x/.git/hooks/pre-commit" ] && fail "hooks install: a hook was installed by a shell that never ran"
grep -q 'installed build-artifact pre-commit hook' "$W/out" && fail "hooks install: reported success"
[ "$FAIL" = "$x" ] && echo "  ok axis 2c: self and hooks install name the fork failure (no verdict, no hook)"

x=$FAIL
# distlib: a project with no [deps] (so nothing is hashed or vendored first, which would fork
# earlier) reaches the six concurrent per-target compiles. Its own home: the stdlib snapshot the
# verify needs, and a stub cycc_aarch64 (it is checked for, never run — no fork succeeds).
DH="$W/dlhome"; mkdir -p "$DH/bin" "$DH/versions/$(cat VERSION)" "$W/dl/src"
ln -s "$CC" "$DH/bin/cycc"; cp "$W/stubtool" "$DH/bin/cycc_aarch64"
cp -R lib "$DH/versions/$(cat VERSION)/lib"
printf '[package]\nname = "dlp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$(cat VERSION)" > "$W/dl/cyrius.cyml"
printf 'fn dlp_one(): i64 { return 1; }\n' > "$W/dl/src/lib.cyr"
WD="$W/dl"; H0=$H; H=$DH
cy lim distlib; named "distlib (the sidecar verify's per-target compiles)"
H=$H0
grep -q 'sidecar verify: the compile for x86_64-linux never started' "$W/out" \
    || fail "distlib: the refusal does not give the fork as its reason: $(grep 'sidecar' "$W/out" | tail -1)"
grep -q 'does not compile' "$W/out" && fail "distlib: a compile that never started was reported as one that does not compile"
ls "$W/dl/dist" 2>/dev/null | grep -q '\.deps$' && fail "distlib: a sidecar was written for a verify that never ran"
[ "$FAIL" = "$x" ] && echo "  ok axis 2d: distlib's sidecar verify names each target's fork failure and refuses for that reason (no sidecar)"

# ── axis 3 — the LSP's diagnostics spawns ───────────────────────────────────────────────
x=$FAIL
LH="$W/lhome"; mkdir -p "$LH/.cyrius/bin" "$W/lone" "$W/proj"
cp "$W/stubtool" "$LH/.cyrius/bin/cycc"; cp "$W/stubtool" "$LH/.cyrius/bin/cyrius"
printf 'var a = 1;\n' > "$W/lone/a.cyr"
printf '[package]\nname = "q"\n' > "$W/proj/cyrius.cyml"; printf 'var b = 1;\n' > "$W/proj/b.cyr"
msg() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{ msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$W/lone/a.cyr"'","languageId":"cyrius","version":1,"text":""}}}'
  msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$W/proj/b.cyr"'","languageId":"cyrius","version":1,"text":""}}}'
  msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'; } > "$W/lsp.in"
( cd "$W/lone" && lim env -i HOME="$LH" PATH=/usr/bin:/bin "$W/cyrius-lsp" ) \
    < "$W/lsp.in" > "$W/lsp.out" 2> "$W/lsp.err" || true
grep -q "could not start $LH/.cyrius/bin/cycc: fork failed" "$W/lsp.err" \
    || fail "axis 3: the raw-cycc diagnostics spawn did not log its fork failure: $(grep -v '^\[cyrius-lsp\] /' "$W/lsp.err" | tail -3 | tr '\n' ' ')"
grep -q "could not start $LH/.cyrius/bin/cyrius: fork failed" "$W/lsp.err" \
    || fail "axis 3: the wrapper diagnostics spawn did not log its fork failure"
grep -q '"id":2,' "$W/lsp.out" || fail "axis 3: the server did not answer shutdown after the failed spawns"
[ "$FAIL" = "$x" ] && echo "  ok axis 3: both LSP diagnostics spawns log the fork failure, and the server goes on"

# ── axis 6 — an inherited SIGCHLD ignore ────────────────────────────────────────────────
x=$FAIL
# Precondition: the exec'd program really starts with SIGCHLD (17, bit 16) ignored here.
sigign=$(ign grep '^SigIgn:' /proc/self/status | awk '{ print $2 }')
case $sigign in
    *[13579bdfBDF]????) ;;
    *) echo "FAIL: $G: axis 6: 'trap '' CHLD; exec' did not leave SIGCHLD ignored here (SigIgn $sigign) — the rows would test nothing"; exit 1 ;;
esac
WD="$W/p"
printf 'fn main(): i64 { return nope; }\nvar r = main();\n' > "$W/p/src/bad.cyr"
cp "$W/good" "$W/p/out"
cy ign build src/bad.cyr out
[ "$RC" -ne 0 ] || fail "axis 6: a failing compile exited 0 with SIGCHLD ignored: $(head -2 "$W/out" | tr '\n' ' ')"
grep -q "undefined variable 'nope'" "$W/out" && grep -q 'FAILED (compiler exit 1)' "$W/out" \
    || fail "axis 6: a failing compile was not judged on the compiler's own verdict: $(head -4 "$W/out" | tr '\n' ' ')"
cmp -s "$W/p/out" "$W/good" || fail "axis 6: a failing compile replaced the existing binary"
[ -z "$(left)" ] || fail "axis 6: files left in the CLI's private temp dir: $(left)"
rm -f "$W/p/out"
cy ign build src/main.cyr out
[ "$RC" = 0 ] && cmp -s "$W/p/out" "$W/good" \
    || fail "axis 6: a good build failed with SIGCHLD ignored (rc $RC) — the CLI did not make its children waitable: $(head -2 "$W/out" | tr '\n' ' ')"
[ "$FAIL" = "$x" ] && echo "  ok axis 6a: SIGCHLD ignored — the CLI resets it, so a good build succeeds and a failing one fails on the compiler's verdict (old binary kept)"

x=$FAIL
# The backstop: the same CLI with its start-up reset deleted, so wait4 really answers ECHILD.
sed '/^[ \t]*_cbt_children_waitable();/d' cbt/cyrius.cyr > "$W/noreset.cyr"
nd=$(( $(wc -l < cbt/cyrius.cyr) - $(wc -l < "$W/noreset.cyr") ))
[ "$nd" = 1 ] || fail "axis 6: expected to delete the one start-up _cbt_children_waitable() call in cbt/cyrius.cyr, deleted $nd"
"$CC" < "$W/noreset.cyr" > "$W/cyrius-noreset" 2> "$W/n.err" && chmod +x "$W/cyrius-noreset" \
    || { echo "FAIL: $G: the scratch CLI without the reset does not build"; tail -3 "$W/n.err"; exit 1; }
for src in src/bad.cyr src/main.cyr; do
    cp "$W/good" "$W/p/out"
    CLI="$W/cyrius-noreset" cy ign build "$src" out
    [ "$RC" -ne 0 ] || fail "axis 6 backstop ($src): exited 0 with no readable exit status: $(head -2 "$W/out" | tr '\n' ' ')"
    grep -q 'could not read the exit status of the compiler: wait failed (error 10)' "$W/out" \
        || fail "axis 6 backstop ($src): the unreadable status is not named: $(head -3 "$W/out" | tr '\n' ' ')"
    cmp -s "$W/p/out" "$W/good" || fail "axis 6 backstop ($src): the existing binary was replaced ($(wc -c < "$W/p/out" | tr -d ' ') B)"
    [ -z "$(left)" ] || fail "axis 6 backstop ($src): files left in the CLI's private temp dir: $(left)"
done
[ "$FAIL" = "$x" ] && echo "  ok axis 6b: backstop — without the reset, an unreadable exit status is named, the old binary kept and no temp left (never decoded as 'exited 0')"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: $G (a failed fork is named by every forking verb and the LSP, nothing is replaced or left behind, and no wait status is decoded unwritten — an inherited SIGCHLD ignore included)"
