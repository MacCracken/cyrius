#!/bin/sh
# tests/gates/toolchain/regression_wait_status_checked.sh — 6.6.20
#
# Every `_regression_wait_deadline` call in lib/regression.cyr and the check driver
# (programs/checks/*.cyr) CONSUMES its result before the status buffer it was handed is decoded.
#
# ⛔ WHY. `_regression_wait_deadline(pid, &stbuf, ms)` returns 1 (reaped: stbuf holds the status),
# 0 (the DEADLINE: the child's tree was ended and reaped) or -1 (waitpid failed — e.g. a parent
# that inherited SIGCHLD = SIG_IGN has its children auto-reaped — and stbuf was NEVER WRITTEN).
# 6.6.7 taught exec_capture / exec_run / pipe_to_bin to check it; five lib verbs
# (exec_in_dir3, ssh_skip_check, scp_to, ssh_remote_exit, ssh_remote_exec_capture) and fifteen
# fork helpers in the check driver (its private copies of exec_in_dir / exec_in_dir3 /
# exec_in_dir3_env, the ts / selfhost / services / efi compile pipes and crosshost's tar|ssh
# pipe) still discarded it and decoded the uninitialised stack word: /bin/false read as exit 0,
# an unreachable host as reachable, and a TERM-trapping child ended at the deadline as the 0 it
# exited with instead of -2. The runtime rows are tests/tcyr/platform/regression_wait_unobserved
# .tcyr; this gate is the static half, because a stale slot is non-deterministic and most of
# these helpers are private to the driver.
#
# THE RULES (per fn; comments and string contents stripped first)
#   bare     a call whose result is discarded (`_regression_wait_deadline(...);` as a statement)
#            is RED when the same fn later decodes that buffer (`load32(&BUF)`). A discarded wait
#            that never decodes (a reap for cleanup only) is allowed.
#   unused   `var R = _regression_wait_deadline(...)` where R is never tested afterwards in the
#            fn (an `if` / `while` condition, a `return`, or `_regression_store_status(..., R, ...)`)
#            is RED — assigning the result only to drop it is the same defect.
#   self     a clean fixture passes and one mutant per rule fails BEFORE the tree is scanned, so a
#            scanner that went blind cannot read GREEN.
#   floors   >= 10 checked calls in lib/regression.cyr, >= 15 in programs/checks/.
#
# MUTATION LEDGER — run 2026-10-06 (lane l-plat, RLM-01; x86_64 Linux):
#   the e696746d lib/regression.cyr + programs/checks/  ->  21 rows RED, every one `bare` (the 5
#   lib verbs; the 15 driver helpers, crosshost's tar|ssh pipe once per child).
# No compiler needed. Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.6.20]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd) || { echo "FAIL: regression_wait_status_checked: cannot resolve ROOT"; exit 1; }
cd "$ROOT" || { echo "FAIL: regression_wait_status_checked: cannot cd to $ROOT"; exit 1; }
command -v awk > /dev/null 2>&1 || { echo "SKIP: regression_wait_status_checked: no awk"; exit 77; }
[ -f lib/regression.cyr ] || { echo "FAIL: regression_wait_status_checked: lib/regression.cyr is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: regression_wait_status_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

# scan FILE... — one `BAD <rule> <file>:<line>: <why>` per violation, then `COUNT <calls>`.
scan() {
    awk '
    function strip(s,   out, i, c, q) {      # drop string contents and the trailing comment
        out = ""; q = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (q) { if (c == "\\") { i++; continue } if (c == "\"") { q = 0; out = out c } continue }
            if (c == "\"") { q = 1; out = out c; continue }
            if (c == "#") break
            out = out c
        }
        return out
    }
    function endfn(   k) {
        for (k = 1; k <= nr; k++) if (!RTEST[k]) printf "BAD unused %s:%d: `%s` holds the wait result but is never tested\n", RFILE[k], RLINE[k], RNAME[k]
        nb = 0; nr = 0
    }
    function hasword(s, w) { return match(s, "(^|[^A-Za-z0-9_])" w "([^A-Za-z0-9_]|$)") }
    BEGIN { calls = 0 }
    FNR == 1 { endfn() }
    {
        line = strip($0)
        if (line ~ /^fn[ \t]/) endfn()
        # a decode of a buffer whose wait was discarded
        for (k = 1; k <= nb; k++) {
            if (index(line, "load32(&" BB[k] ")") > 0)
                printf "BAD bare %s:%d: the wait on `%s` (line %d) was discarded, then its status decoded here\n", FILENAME, FNR, BB[k], BL[k]
        }
        # a tested result
        for (k = 1; k <= nr; k++) {
            if (!RTEST[k] && hasword(line, RNAME[k]) && line !~ /=[ \t]*_regression_wait_deadline\(/) {
                if (line ~ /(^|[^A-Za-z0-9_])(if|while)[ \t]*\(/ || line ~ /return[ \t]/ || line ~ /_regression_store_status\(/) RTEST[k] = 1
            }
        }
        if (match(line, /_regression_wait_deadline\(/)) {
            pre = substr(line, 1, RSTART - 1); post = substr(line, RSTART)
            buf = post; sub(/^[^,]*,[ \t]*&?/, "", buf); sub(/[ \t]*[,)].*$/, "", buf)
            if (line ~ /^[ \t]*fn[ \t]/) next
            calls++
            if (pre ~ /^[ \t]*$/) { nb++; BB[nb] = buf; BL[nb] = FNR }
            else if (pre ~ /(^|[ \t])(var[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*$/) {
                rn = pre; sub(/[ \t]*=[ \t]*$/, "", rn); sub(/^.*[^A-Za-z0-9_]/, "", rn)   # the last identifier
                if (rn == "") { printf "BAD unused %s:%d: cannot name the variable holding the wait result\n", FILENAME, FNR; next }
                nr++; RNAME[nr] = rn; RTEST[nr] = 0; RFILE[nr] = FILENAME; RLINE[nr] = FNR
            }
        }
    }
    END { endfn(); printf "COUNT %d\n", calls }' "$@"
}

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# ── self-test ───────────────────────────────────────────────────────────────────────────────────
mkdir -p "$D/fx/m"
cat > "$D/fx/clean.cyr" <<'EOF'
fn a(pid): i64 {
    var stbuf[4];
    var reaped = _regression_wait_deadline(pid, &stbuf, 100);
    if (reaped == 0) { return 0 - 2; }
    if (reaped < 0) { return 0 - 1; }
    var status = load32(&stbuf);
    return status;
}
fn b(pid, out): i64 {
    var st[4];
    var r = _regression_wait_deadline(pid, &st, 100);
    _regression_store_status(out, r, load32(&st));
    return 0;
}
fn c(pid): i64 {
    var s1[1];
    _regression_wait_deadline(pid, &s1, 100);
    return 0;
}
EOF
out=$(scan "$D/fx/clean.cyr")
if printf '%s\n' "$out" | grep -q '^BAD'; then bad "self: the clean fixture is flagged: $(printf '%s' "$out" | grep '^BAD' | head -2 | tr '\n' ' ')"
elif ! printf '%s\n' "$out" | grep -q '^COUNT 3$'; then bad "self: the clean fixture counts read '$(printf '%s' "$out" | tail -1)', want 'COUNT 3'"
else ok; fi
mutant() {  # $1 = rule, $2 = sed expression, $3 = label
    sed "$2" "$D/fx/clean.cyr" > "$D/fx/m/clean.cyr"
    if cmp -s "$D/fx/clean.cyr" "$D/fx/m/clean.cyr"; then bad "self: mutant '$3' did not apply"; return; fi
    if scan "$D/fx/m/clean.cyr" | grep -q "^BAD $1 "; then ok
    else bad "self: mutant '$3' is not caught as $1"; fi
}
mutant bare   's/    var reaped = _regression_wait_deadline(pid, \&stbuf, 100);/    _regression_wait_deadline(pid, \&stbuf, 100);/' "the result discarded, then decoded"
mutant bare   's/^    return 0;$/    return load32(\&s1);/' "a cleanup reap that starts decoding"
mutant unused 's/    if (reaped == 0) { return 0 - 2; }//; s/    if (reaped < 0) { return 0 - 1; }//' "assigned, never tested"

# ── the tree ────────────────────────────────────────────────────────────────────────────────────
FILES="lib/regression.cyr $(find programs/checks -name '*.cyr' | LC_ALL=C sort | tr '\n' ' ')"
# shellcheck disable=SC2086
out=$(scan $FILES)
bads=$(printf '%s\n' "$out" | grep '^BAD' || true)
if [ -n "$bads" ]; then
    printf '%s\n' "$bads" | while IFS= read -r l; do printf '  FAIL: %s\n' "${l#BAD }"; done
    fail=$((fail + $(printf '%s\n' "$bads" | wc -l)))
else ok; fi
nl=$(scan lib/regression.cyr | grep '^COUNT' | awk '{print $2}')
# shellcheck disable=SC2046
nd=$(scan $(find programs/checks -name '*.cyr' | LC_ALL=C sort) | grep '^COUNT' | awk '{print $2}')
[ "${nl:-0}" -ge 10 ] && ok || bad "floor: ${nl:-0} wait calls in lib/regression.cyr (want >= 10) — the scan went blind or the verbs moved"
[ "${nd:-0}" -ge 15 ] && ok || bad "floor: ${nd:-0} wait calls in programs/checks/ (want >= 15)"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: regression_wait_status_checked: $fail failed, $pass passed"
    exit 1
fi
echo "PASS: regression_wait_status_checked ($pass checks; $nl lib + $nd driver wait calls, every decoded status checked first)"
exit 0
