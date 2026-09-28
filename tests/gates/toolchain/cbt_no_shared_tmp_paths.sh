#!/bin/sh
# cbt_no_shared_tmp_paths.sh — 6.6.9 bite 10, CVE-49. The CLI stages nothing at a shared
# `/tmp/<name>`, and `cyrius self` stages its compilers in the private temp dir and leaves
# nothing behind.
#
# ⛔ CVE-49 (cbt/commands.cyr, as of 6.6.8). `cyrius self`'s POSIX arm forked `/bin/sh -c`
# over a script that staged THREE compilers at predictable shared names —
#     cycc=/tmp/cyr_cc5_$$  ccr=/tmp/cyr_ccr_$$  cc4=/tmp/cyr_cc4_$$
# — wrote them with `>` and `cp` (no O_EXCL; a pre-planted symlink is followed) and then
# EXECUTED `$ccr`. PIDs are predictable, so another local user who creates those names first
# owns the file the verb runs. That is the CVE-35/CVE-36 class: v6.4.81 moved every other cbt
# temp into `_cbt_tmpdir()`'s 0700 exclusive-mkdir directory, and this verb predated it.
# Linux's protected_symlinks/protected_regular blunt it; macOS (ecb, ach) has no equivalent.
#
# THE FIX. The POSIX arm runs natively through the helpers `cmd_soak` already uses —
# `_self_host_step` twice and `_self_host_same` — over `_cbt_tmpexe`/`_cbt_tmpfile` names,
# removing what it staged on every path. And (bite 10's temp-hygiene half) `_copy_binary` no
# longer leaves a partial or empty dst when it fails, so the macOS stage cannot leak its copy —
# and with it the whole private dir, whose exit sweep is rmdir-only.
#
# AXES
#   0. SCANNER SELF-TEST: the string-literal scanner flags the 6.6.8 script line and a string
#      after a `'"'` char literal, and does NOT flag a `/tmp/` in a comment or the bare base
#      `"/tmp"`. Without it axis 1's "0 found" could be a scanner that sees nothing.
#   1. STATIC: no string literal in any cbt/*.cyr contains `/tmp/` (shell strings included).
#      Floor: the scan must see at least 2000 literals.
#   2. `cyrius self` with a stub compiler that writes itself: PASS, rc 0; step 2 ran from
#      under $TMPDIR (the private dir), never from a `/tmp/cyr_*` name; $TMPDIR is empty after.
#   3. step 1 fails (stub exits 42): the step and its status are NAMED, rc != 0, no PASS, and
#      $TMPDIR is empty after (nothing leaked on the failure path).
#   3b. a 0-byte compiler: no PASS, rc != 0 (the 6.6.8 script scored it PASS, rc 0).
#   4. step 2 fails (the staged copy exits 3): named as step 2, rc != 0, $TMPDIR empty.
#   5. the two outputs differ: `FAIL: cycc!=cycc`, rc 1, $TMPDIR empty.
#   6. `_copy_binary`, extracted from cbt/build.cyr and run: an EMPTY source and an unreadable
#      one (a directory) each return 1 AND leave no dst; a real file copies byte-identical.
#   7. STATIC: `_self_host_step_macos` removes its staged copy on every return (it compiles
#      only on macOS; the real-hardware run is ecb/ach, recorded in the CHANGELOG).
#
# MUTATION LEDGER (measured at 6.6.9)
#   M1. the 6.6.8 cmd_self (the /bin/sh script)          -> RED axes 1-5 and 3b (step 2 ran from
#       /tmp/cyr_ccr_<pid>; a failed step was an unnamed rc, or a PASS-less rc 0)
#   M2. `_copy_binary` without its failure unlink         -> RED axis 6 (both rows)
#   M3. `_self_host_step_macos` copy-failure branch without its unlink -> RED axis 7
#   M4. cmd_self's step-2 failure branch drops `sys_unlink(t1)` -> RED axis 4 (the private
#       dir survives, so axis 5's emptiness row reads it too)
#
# ⚠ NO `set -e`: failing verbs are the data.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cbt_no_shared_tmp_paths: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
bad() { echo "FAIL: $1"; FAIL=1; }
ok() { echo "  ok: $1"; }

# ── the scanner: every "…" literal on a line, outside `#` comments and char literals ───────
cat > "$D/lits.awk" <<'AWK'
{
    line = $0; n = length(line); i = 1; ins = 0; cur = ""
    while (i <= n) {
        c = substr(line, i, 1)
        if (ins) {
            if (c == "\\") { cur = cur substr(line, i, 2); i += 2; continue }
            if (c == "\"") { print FILENAME ":" FNR "\t" cur; ins = 0; cur = ""; i++; continue }
            cur = cur c; i++; continue
        }
        if (c == "#") break
        if (c == "'") {
            if (substr(line, i + 1, 1) == "\\") { i += 4 } else { i += 3 }
            continue
        }
        if (c == "\"") { ins = 1; cur = "" }
        i++
    }
}
AWK

# 0 — self-test. The probe spells the shared root as @T@ and is expanded at run time, so this
# gate carries no fixed shared-temp path of its own (gates_never_write_tree.sh axis 5).
TMPROOT=/tmp
sed "s|@T@|$TMPROOT|g" > "$D/probe.cyr" <<'EOF'
        str_builder_add_cstr(sb, ";cycc=@T@/cyr_cc5_$$;ccr=@T@/cyr_ccr_$$;cc4=@T@/cyr_cc4_$$;rc=1;");
    if (c == '"') { x = "@T@/after_char_lit"; }
    # It printed "@T@/cyrius-lsp" — a comment
    return "@T@";
    var y = "a#b"; var z = "@T@/after_hash_in_string";
EOF
# Match the LITERAL column only: $D itself usually sits under /tmp.
PROBE=$(awk -f "$D/lits.awk" "$D/probe.cyr" | awk -F'\t' '$2 ~ /\/tmp\//' | grep -c .)
[ "$PROBE" = 3 ] && ok "scanner flags the 6.6.8 line, a literal after '\"' and after a '#' inside a string, and skips comments and the bare base" \
  || bad "scanner self-test found $PROBE /tmp/ literals in the probe, expected 3"

# 1 — static.
awk -f "$D/lits.awk" cbt/*.cyr > "$D/lits"
NLIT=$(grep -c . "$D/lits")
if [ "$NLIT" -lt 2000 ]; then bad "the scan saw only $NLIT string literals in cbt/ — did the scanner stop matching?"; fi
HITS=$(awk -F'\t' '$2 ~ /\/tmp\//' "$D/lits")
if [ -n "$HITS" ]; then
  bad "a cbt string literal names a shared /tmp/ path (use _cbt_tmpfile / _cbt_tmpexe):"
  printf '%s\n' "$HITS" | sed 's/^/      /'
else
  ok "no /tmp/ path in any of $NLIT cbt string literals"
fi

# ── the stub compiler for axes 2-5 ─────────────────────────────────────────────────────────
# Logs the path it runs from, then (mode 0) writes ITSELF to stdout, so step 1's output is
# the stub and step 2 runs it from wherever the CLI staged it. Modes 1-3 fail one step.
mkdir -p "$D/bin" "$D/proj/src" "$D/t"
cp "$CY" "$D/bin/cyrius" || bad "could not copy the CLI"
echo 'x' > "$D/proj/src/main.cyr"
cat > "$D/stub.cyr" <<'EOF'
var MODE = @MODE@;
var LOG = "@LOG@";
var PRIV = "@PRIV@";
var buf[8192];   # 64 KB (a top-level array is N x 8)
var pth[512];
fn has_priv(p, n): i64 {
    var i = 0;
    while (load8(PRIV + i) != 0) {
        if (i >= n) { return 0; }
        if (load8(p + i) != load8(PRIV + i)) { return 0; }
        i = i + 1;
    }
    return 1;
}
fn main(): i64 {
    if (MODE == 1) { return 42; }
    var n = syscall(89, "/proc/self/exe", &pth, 4000);
    if (n < 0) { return 90; }
    var lfd = syscall(2, LOG, 1089, 420);
    if (lfd >= 0) { syscall(1, lfd, &pth, n); syscall(1, lfd, "\n", 1); syscall(3, lfd); }
    var priv = has_priv(&pth, n);
    if (MODE == 2 && priv == 1) { return 3; }
    if (MODE == 3 && priv == 1) { syscall(1, 1, "x", 1); return 0; }
    var fd = syscall(2, "/proc/self/exe", 0, 0);
    if (fd < 0) { return 91; }
    var r = syscall(0, fd, &buf, 65536);
    while (r > 0) {
        syscall(1, 1, &buf, r);
        r = syscall(0, fd, &buf, 65536);
    }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
stub() {
  sed "s|@MODE@|$1|;s|@LOG@|$D/log|;s|@PRIV@|$D/t/|" "$D/stub.cyr" | "$CC" > "$D/bin/cycc" 2>/dev/null
  chmod +x "$D/bin/cycc"
  rm -f "$D/log"
}
self_run() {
  OUT=$( cd "$D/proj" && ulimit -c 0; TMPDIR="$D/t" CYRIUS_RESOLVED=1 "$D/bin/cyrius" self 2>&1 ); RC=$?
}
tmp_empty() {
  LEFT=$(ls -A "$D/t")
  [ -z "$LEFT" ] && ok "$1: nothing left under \$TMPDIR" || bad "$1: left behind under \$TMPDIR: $LEFT"
}

# 2 — the pass path.
stub 0
if [ ! -s "$D/bin/cycc" ]; then bad "the stub compiler did not build — axes 2-5 would be vacuous"; else
  self_run
  [ "$RC" = 0 ] && echo "$OUT" | grep -q 'PASS: cycc==cycc' && ok "a self-host of a fixpoint PASSes (rc 0)" \
    || bad "a fixpoint did not PASS (rc $RC): $OUT"
  STEP2=$(sed -n 2p "$D/log" 2>/dev/null)
  case "$STEP2" in
    "$D/t/cyrius-"*) ok "step 2 ran the staged compiler from the private dir ($STEP2)" ;;
    *) bad "step 2 did not run from the private temp dir under \$TMPDIR (ran: '${STEP2:-nothing}')" ;;
  esac
  grep -q "$TMPROOT/cyr_" "$D/log" 2>/dev/null && bad "a compiler ran from a shared \$TMPROOT/cyr_* name"
  tmp_empty "pass"
fi

# 3 — step 1 fails.
stub 1; self_run
if [ "$RC" != 0 ] && echo "$OUT" | grep -q 'self-host step 1 .* exited 42' && ! echo "$OUT" | grep -q PASS; then
  ok "a failed step 1 is named with its status (42), rc $RC"
else bad "step-1 failure not named or not failing (rc $RC): $OUT"; fi
tmp_empty "step 1 failed"

# 3b — a 0-byte "compiler" is not a fixpoint. The 6.6.8 script PASSED here, rc 0 — measured on
# x86-64 Linux, pi and ach: /bin/sh runs an empty executable as an empty SCRIPT (exit 0, no
# output), so both steps "succeeded", and `cmp` of two empty files is equal.
: > "$D/bin/cycc"; chmod +x "$D/bin/cycc"; self_run
if [ "$RC" != 0 ] && ! echo "$OUT" | grep -q PASS; then ok "a 0-byte compiler does not PASS (rc $RC)"
else bad "a 0-byte compiler scored a self-host verdict (rc $RC): $OUT"; fi
tmp_empty "0-byte compiler"

# 4 — step 2 fails.
stub 2; self_run
if [ "$RC" != 0 ] && echo "$OUT" | grep -q 'self-host step 2 .* exited 3' && ! echo "$OUT" | grep -q PASS; then
  ok "a failed step 2 is named with its status (3), rc $RC"
else bad "step-2 failure not named or not failing (rc $RC): $OUT"; fi
tmp_empty "step 2 failed"

# 5 — the outputs differ.
stub 3; self_run
if [ "$RC" = 1 ] && echo "$OUT" | grep -q 'FAIL: cycc!=cycc'; then ok "differing outputs FAIL (rc 1)"
else bad "differing outputs not reported (rc $RC): $OUT"; fi
tmp_empty "outputs differed"

# 6 — `_copy_binary`, the real fn, extracted and run.
{
  printf 'include "lib/string.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/io.cyr"\ninclude "lib/syscalls.cyr"\n'
  awk '/^var _copy_bin_buf = 0;/{p=1} p{print} p && /^}/{exit}' cbt/build.cyr
  printf 'alloc_init();\nvar r = _copy_binary("%s", "%s");\nsyscall(60, r);\n' "$D/cp_src" "$D/cp_dst"
} > "$D/cp.cyr"
if ! grep -q '^fn _copy_binary' "$D/cp.cyr"; then bad "could not extract _copy_binary from cbt/build.cyr"
else
  "$CC" < "$D/cp.cyr" > "$D/cp" 2>/dev/null; chmod +x "$D/cp"
  : > "$D/cp_src"; "$D/cp"; R1=$?
  [ "$R1" = 1 ] && [ ! -e "$D/cp_dst" ] && ok "an EMPTY source fails (1) and leaves no dst" \
    || bad "_copy_binary of an empty source: rc $R1, dst $( [ -e "$D/cp_dst" ] && echo LEFT BEHIND || echo absent)"
  rm -f "$D/cp_src" "$D/cp_dst"; mkdir "$D/cp_src"; "$D/cp"; R2=$?
  [ "$R2" = 1 ] && [ ! -e "$D/cp_dst" ] && ok "an unreadable source fails (1) and leaves no dst" \
    || bad "_copy_binary of a directory: rc $R2, dst $( [ -e "$D/cp_dst" ] && echo LEFT BEHIND || echo absent)"
  rmdir "$D/cp_src"; printf 'payload\n' > "$D/cp_src"; "$D/cp"; R3=$?
  [ "$R3" = 0 ] && cmp -s "$D/cp_src" "$D/cp_dst" && ok "a real file copies byte-identical (anti-vacuous)" \
    || bad "_copy_binary of a real file: rc $R3, copy differs or is missing"
fi

# 7 — `_self_host_step_macos` removes its stage on every return.
BODY=$(awk '/^fn _self_host_step_macos\(/{p=1} p{print} p && /^}/{exit}' cbt/build.cyr | sed 's/#.*//')
NRET=$(printf '%s\n' "$BODY" | grep -c 'return')
NUNL=$(printf '%s\n' "$BODY" | grep -c 'sys_unlink(ccr)')
if [ "$NRET" -lt 2 ]; then bad "could not extract _self_host_step_macos (found $NRET returns)"
elif [ "$NUNL" -lt "$NRET" ]; then bad "_self_host_step_macos has $NRET returns but only $NUNL sys_unlink(ccr) — a path leaks its staged copy"
else ok "_self_host_step_macos: $NRET returns, $NUNL unlinks of its staged copy"; fi

if [ "$FAIL" != 0 ]; then echo "FAIL cbt_no_shared_tmp_paths"; exit 1; fi
echo "PASS cbt_no_shared_tmp_paths ($NLIT cbt literals, no shared /tmp/ path; cyrius self stages privately and leaves nothing)"
exit 0
