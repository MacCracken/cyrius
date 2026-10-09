#!/bin/sh
# operands_checked_before_resolve.sh — 6.7.6 (lane C, part R). A resolving verb's OPERANDS are
# checked before the dependency resolve. main() runs `_auto_deps` — clones, vendoring, the lock —
# ahead of each verb's own branch, so `cyrius run missing.cyr` fetched every dependency and only
# then said "no such file", and `cyrius build a b c` resolved before refusing the extra operand
# (`_cli_preflight`, cbt/cli_args.cyr: the branches' own counts, and a FILE operand must exist).
# `cyrius test`'s operands too — every one, a file or a directory — and the deprecated `cyrius
# tests`' directory: `cyrius test missing.tcyr` cloned, vendored and wrote cyrius.lock before
# refusing it (6.7.6 review).
#
# AXES (one file:// git dep, a throwaway CYRIUS_HOME; "nothing resolved" = no clone in the cache,
# no lib/, no cyrius.lock):
#   P1  `cyrius run missing.cyr`: "no such file", rc 1, nothing resolved
#   P2  `cyrius bench nothere`: "no such file or directory", rc 1, nothing resolved
#   P3  `cyrius build a.cyr b c`: the extra operand named, rc 1, nothing resolved
#   P4  `cyrius check ok.cyr missing.cyr`: the missing one named, rc 1, nothing resolved
#   P5  anti-over-reach: `cyrius run ok.cyr` resolves (the clone and lib/ exist) and runs (exit 5)
#   P6  `cyrius test missing.tcyr` and `cyrius test ok.tcyr missing.tcyr` (the second operand
#       checked too): "no such file or directory", rc 1, nothing resolved
#   P7  `cyrius tests nothere` and `cyrius tests ok.cyr` (a file — the deprecated verb takes a
#       directory): named, rc 1, nothing resolved
#   P8  anti-over-reach: `cyrius test t` (a directory) and `cyrius test t/ok.tcyr` resolve and pass
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree; real tree 8/8 green):
#   M1  main() no longer calls _cli_preflight ......................... P1 P2 P3 P4 P6 P7 red
#   M2  the preflight checks counts only, not that a file exists ....... P1 P2 P4 P6 P7 red
#   M3  the preflight leaves test / tests out (the pre-FXCL-3 shape) ... P6 P7 red
#   M4  test's operands: only the first is checked ..................... P6 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=operands_checked_before_resolve
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V/bin" "$H/deps" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
mkdir -p "$W/o/d/dist" && printf 'fn d_v(): i64 { return 5; }\n' > "$W/o/d/dist/d.cyr"
( cd "$W/o/d" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: origin"; exit 1; }
P="$W/p"; mkdir -p "$P"
printf '[package]\nname = "p"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["syscalls"]\n\n[deps.d]\ngit = "file://%s/o/d"\ntag = "v1"\nmodules = ["dist/d.cyr"]\n' "$V" "$W" > "$P/cyrius.cyml"
printf 'syscall(SYS_EXIT, d_v());\n' > "$P/ok.cyr"
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CY" "$@" ); }
nothing() { [ -z "$(ls -A "$H/deps")" ] && [ ! -e "$P/lib" ] && [ ! -e "$P/cyrius.lock" ]; }
# each refusal row starts from nothing resolved, so a mutant that resolves in one row cannot turn the next red
fresh() { rm -rf "$H/deps" "$P/lib" "$P/cyrius.lock"; mkdir -p "$H/deps"; }
rc=0; cy run missing.cyr > "$W/p1.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such file: missing.cyr' "$W/p1.out" && nothing && ok "P1 run missing.cyr: named, rc 1, nothing resolved" \
  || bad "P1 (rc=$rc): $(head -2 "$W/p1.out") cache=[$(ls -A "$H/deps")]"
fresh; rc=0; cy bench nothere > "$W/p2.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such file or directory: nothere' "$W/p2.out" && nothing && ok "P2 bench nothere: named, rc 1, nothing resolved" \
  || bad "P2 (rc=$rc): $(head -2 "$W/p2.out")"
fresh; rc=0; cy build ok.cyr b c > "$W/p3.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qF "error: cyrius build: unexpected extra argument 'c'" "$W/p3.out" && nothing && ok "P3 build ok.cyr b c: the extra operand named, rc 1, nothing resolved" \
  || bad "P3 (rc=$rc): $(head -2 "$W/p3.out")"
fresh; rc=0; cy check ok.cyr missing.cyr > "$W/p4.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such file: missing.cyr' "$W/p4.out" && nothing && ok "P4 check ok.cyr missing.cyr: the missing one named, rc 1, nothing resolved" \
  || bad "P4 (rc=$rc): $(head -2 "$W/p4.out")"
mkdir -p "$P/t" && printf 'syscall(SYS_EXIT, d_v() - 5);\n' > "$P/t/ok.tcyr"
p6=0
fresh; rc=0; cy test missing.tcyr > "$W/p6a.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such file or directory: missing.tcyr' "$W/p6a.out" && nothing && p6=$((p6+1))
fresh; rc=0; cy test t/ok.tcyr missing.tcyr > "$W/p6b.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such file or directory: missing.tcyr' "$W/p6b.out" && nothing && p6=$((p6+1))
[ "$p6" -eq 2 ] && ok "P6 test missing.tcyr / test t/ok.tcyr missing.tcyr: named, rc 1, nothing resolved" \
  || bad "P6 ($p6 of 2): $(head -2 "$W/p6a.out") / $(head -2 "$W/p6b.out") cache=[$(ls -A "$H/deps")]"
p7=0
fresh; rc=0; cy tests nothere > "$W/p7a.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qxF 'error: no such directory: nothere' "$W/p7a.out" && nothing && p7=$((p7+1))
fresh; rc=0; cy tests ok.cyr > "$W/p7b.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -qF 'error: not a directory (`cyrius test <file>` runs one file): ok.cyr' "$W/p7b.out" && nothing && p7=$((p7+1))
[ "$p7" -eq 2 ] && ok "P7 tests nothere / tests ok.cyr (a file): named, rc 1, nothing resolved" \
  || bad "P7 ($p7 of 2): $(head -2 "$W/p7a.out") / $(head -2 "$W/p7b.out")"
rc=0; cy run ok.cyr > "$W/p5.out" 2>&1 || rc=$?
[ "$rc" -eq 5 ] && [ -d "$H/deps/d" ] && [ -f "$P/lib/d.cyr" ] && ok "P5 run ok.cyr: resolved and ran (exit 5)" \
  || bad "P5 (rc=$rc): $(tail -2 "$W/p5.out")"
rc=0; cy test t > "$W/p8a.out" 2>&1 || rc=$?; r8a=$rc
rc=0; cy test t/ok.tcyr > "$W/p8b.out" 2>&1 || rc=$?
[ "$r8a" -eq 0 ] && grep -q '^1 passed, 0 failed$' "$W/p8a.out" && [ "$rc" -eq 0 ] && ok "P8 test t (a directory) and test t/ok.tcyr: resolved and passed" \
  || bad "P8 (dir rc=$r8a file rc=$rc): $(tail -2 "$W/p8a.out")"

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
