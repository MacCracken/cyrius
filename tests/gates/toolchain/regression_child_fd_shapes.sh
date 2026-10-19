#!/bin/sh
# tests/gates/toolchain/regression_child_fd_shapes.sh — 6.7.16
#
# lib/regression.cyr opens and hands over file descriptors in shapes that are right on EVERY
# target the module runs on, and whichever std fds its caller started with. Static, comments and
# string contents stripped first.
#
# THE RULES
#   flags    every `sys_open(` / `file_open(` passes a flag argument that is the literal 0 or 1
#            (O_RDONLY / O_WRONLY — the same bits on Linux and Darwin), or one spelled with no
#            numeric literal at all (the per-target O_* constants). ⛔ WHY: regression_exec_in_dir3
#            [_env], regression_pipe_to_bin_capture and regression_ssh_remote_exec_capture opened
#            the caller's out_path with 577 — Linux's O_WRONLY|O_CREAT|O_TRUNC, and on Darwin
#            (O_CREAT 0x200, O_TRUNC 0x400) O_WRONLY|O_ASYNC|O_CREAT: the file was not truncated,
#            and a shorter output kept the old tail (issues/archived/2026-10-18-regression-caller-
#            out-path-opened-with-linux-flag-bits-on-darwin.md). The runtime rows are
#            tests/tcyr/crossos/regression_out_path_truncated.tcyr (ecb, ach, pi).
#   lift     a fork child (`if (P == 0) {`, P from `_regression_fork()` / `sys_fork()`) that puts
#            an fd it did NOT open itself (the parent's out_fd) onto fd 1 AFTER its first redirect
#            onto fd 0 (`_regression_redirect(…, 0)` / `sys_dup2(…, 0)`) must redirect the result
#            of `_regression_lift_fd(…)`, assigned BEFORE that stdin redirect. ⛔ WHY (6.7.15):
#            a caller started with fd 0 closed has the parent open out_fd AT 0, and the stdin
#            redirect overwrote it before the output redirect read it — the capture came back
#            empty (issues/archived/2026-10-18-regression-output-fd-overwritten-by-stdin-redirect
#            .md). A child that puts out_fd onto 1 before touching fd 0 needs no lift (the capture
#            verbs). The lift in regression_ssh_remote_exec_capture was pinned by nothing
#            (issues/archived/2026-10-19-ssh-remote-exec-capture-fd-lift-unpinned.md); the runtime
#            rows are tests/tcyr/crossos/regression_capture_stdin_closed.tcyr (ssh -G for the ssh
#            verb). The RED line names the verb.
#   self     a clean fixture passes and one mutant per rule shape fails BEFORE the tree is scanned,
#            and copies of the LIVE lib/regression.cyr must each go RED naming the verb: 577 back
#            at each of the three caller-out_path opens, and each of the three children's lift
#            line deleted or turned into `var ofd = out_fd;` — a scanner that went blind cannot
#            read GREEN.
#   floors   >= 25 open calls and >= 10 fork children read in lib/regression.cyr, >= 3 of them
#            redirecting a lifted fd onto 1.
#
# MUTATION LEDGER — run 2026-10-19 (lane libfix, unit L1; x86_64 Linux): 577 restored at
#   regression_pipe_to_bin_capture / regression_ssh_remote_exec_capture / regression_exec_in_dir3
#   -> RED `flags`, naming that verb; the lift line of each of those three deleted, or replaced by
#   `var ofd = out_fd;` -> RED `lift`, naming that verb (the built-in live mutants run all nine
#   every time).
# No compiler needed. Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.16]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd) || { echo "FAIL: regression_child_fd_shapes: cannot resolve ROOT"; exit 1; }
cd "$ROOT" || { echo "FAIL: regression_child_fd_shapes: cannot cd to $ROOT"; exit 1; }
command -v awk > /dev/null 2>&1 || { echo "SKIP: regression_child_fd_shapes: no awk"; exit 77; }
LIB=lib/regression.cyr
[ -f "$LIB" ] || { echo "FAIL: regression_child_fd_shapes: $LIB is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: regression_child_fd_shapes: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

# scan FILE — one `BAD <rule> <file>:<line>: <fn>: <why>` per violation, then `OPENS <n>`,
# `CHILDREN <n>` and `LIFTED <n>`.
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
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # The argument `want` (0-based) of the call whose "(" is at `p` in `s`; "\001" when the call
    # does not close on this line.
    function callarg(s, p, want,   i, c, d, k, cur) {
        d = 0; k = 0; cur = ""
        for (i = p + 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "(") d++
            if (c == ")") { if (d == 0) return (k == want) ? cur : ""; d-- }
            if (c == "," && d == 0) { if (k == want) return cur; k++; cur = ""; continue }
            cur = cur c
        }
        return "\001"
    }
    # every open call on this line: its flag argument (the second) checked
    function opens(line,   rest, a, f) {
        rest = line
        while (match(rest, /(^|[^A-Za-z0-9_])(sys_open|file_open)\(/)) {
            a = callarg(rest, RSTART + RLENGTH - 1, 1)
            rest = substr(rest, RSTART + RLENGTH)
            nopen++
            if (a == "\001") { printf "BAD flags %s:%d: %s: an open call split across lines (cannot read its flags)\n", FILENAME, FNR, fname; continue }
            f = trim(a)
            if (f == "0" || f == "1") continue
            if (f ~ /(^|[^A-Za-z0-9_])[0-9]/)
                printf "BAD flags %s:%d: %s: the open flag `%s` holds a numeric literal — spell it with the per-target O_* constants (Linux bits are not Darwin bits)\n", FILENAME, FNR, fname, f
        }
    }
    function braces(s,   i, c) {
        for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "{") depth++; if (c == "}") depth-- }
    }
    # the source fd of the redirect onto `tgt` in the space-free line `t` ("" when none), its
    # position in RPOS
    function redir(t, tgt,   s) {
        RPOS = 0
        if (match(t, "(_regression_redirect|sys_dup2)\\([^,()]*," tgt "\\)")) {
            RPOS = RSTART; s = substr(t, RSTART, RLENGTH)
            sub(/^[^(]*\(/, "", s); sub(/,.*$/, "", s)
            return s
        }
        return ""
    }
    function endchild() {
        if (inchild) printf "BAD lift %s:%d: %s: cannot find the end of the fork child opened at line %d\n", FILENAME, cline, fname, cline
        inchild = 0
    }
    BEGIN { nopen = 0; nchild = 0; nlift = 0; fname = "(file scope)"; depth = 0 }
    FNR == 1 { endchild(); depth = 0; split("", FV) }
    {
        line = strip($0)
        if (line ~ /^fn[ \t]/) {
            endchild(); depth = 0; split("", FV)
            fname = line; sub(/^fn[ \t]+/, "", fname); sub(/\(.*$/, "", fname)
        }
        opens(line)
        t = line; gsub(/[ \t]/, "", t)
        # a fork result: `var P = _regression_fork()` / `P = sys_fork()`
        if (match(line, /[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(_regression_fork|sys_fork)\(/)) {
            v = substr(line, RSTART, RLENGTH); sub(/[ \t]*=.*$/, "", v); FV[v] = 1
        }
        if (!inchild) {
            for (v in FV) if (index(t, "if(" v "==0){") == 1) {
                inchild = 1; cdepth = depth; cline = FNR; first0 = 0; nchild++; split("", K)
            }
            braces(line)
            next
        }
        # in the child: what each assigned name holds
        if (match(line, /^[ \t]*(var[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=]/)) {
            v = substr(line, RSTART, RLENGTH - 1); rhs = substr(line, RSTART + RLENGTH - 1)
            sub(/[ \t]*=$/, "", v); sub(/^[ \t]*(var[ \t]+)?/, "", v)
            if (index(rhs, "_regression_lift_fd(")) K[v] = (first0 == 0) ? "lift" : "late"
            else if (rhs ~ /(^|[^A-Za-z0-9_])sys_(open|pipe|socket|dup)\(/) K[v] = "child"
            else K[v] = "other"
        }
        s0 = redir(t, "0"); p0 = RPOS
        s1 = redir(t, "1"); p1 = RPOS
        if (s0 != "" && first0 == 0 && (s1 == "" || p0 < p1)) first0 = FNR
        if (s1 != "" && s1 !~ /^[0-9]+$/ && K[s1] != "child") {
            if (K[s1] == "lift") nlift++
            else if (first0 != 0)
                printf "BAD lift %s:%d: %s: the fork child puts `%s` (an fd it did not open) onto fd 1 after its stdin redirect (line %d) without lifting it first — `var %s = _regression_lift_fd(...)` before line %d\n", FILENAME, FNR, fname, s1, first0, s1, first0
        }
        if (s0 != "" && first0 == 0) first0 = FNR   # the stdin redirect came after fd 1 on this line
        braces(line)
        if (depth <= cdepth) inchild = 0
    }
    END { endchild(); printf "OPENS %d\nCHILDREN %d\nLIFTED %d\n", nopen, nchild, nlift }' "$1"
}

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# ── self-test ───────────────────────────────────────────────────────────────────────────────────
mkdir -p "$D/fx/m"
cat > "$D/fx/clean.cyr" <<'EOF'
fn v1(out_path): i64 {
    var a = sys_open("/dev/zero", 1, 0);
    var b = sys_open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 420);   # 577 in a comment is fine
    var c = sys_open(&path, 0, 0);
    var d = file_open(out_path, O_RDONLY, 0);
    var e = sys_open("x, 577, y", O_WRONLY, 0);
    return 0;
}
fn lifted_pipe(out_fd, rfd): i64 {
    var pid = _regression_fork();
    if (pid == 0) {
        var ofd = _regression_lift_fd(out_fd);   # a closed fd 0 put it AT 0
        _regression_redirect(rfd, 0);
        _regression_redirect(ofd, 1);
        var dn2 = sys_open("/dev/null", 1, 0);
        if (dn2 >= 0) { _regression_redirect(dn2, 2); }
        sys_exit(127);
    }
    return 0;
}
fn ordered_capture(out_fd): i64 {
    var pid = _regression_fork();
    if (pid < 0) { return 0 - 1; }
    if (pid == 0) {
        _regression_redirect(out_fd, 1);
        var dn_r = sys_open("/dev/null", 0, 0);
        if (dn_r >= 0) { _regression_redirect(dn_r, 0); }
        sys_exit(127);
    }
    return 0;
}
fn child_opened(out_fd): i64 {
    var p = sys_fork();
    if (p == 0) {
        var dn0 = sys_open("/dev/null", 0, 0);
        if (dn0 >= 0) { _regression_redirect(dn0, 0); }
        var dn1 = sys_open("/dev/null", 1, 0);
        if (dn1 >= 0) { _regression_redirect(dn1, 1); }
        sys_exit(127);
    }
    _regression_redirect(out_fd, 1);
    return 0;
}
fn both_dup2(out_fd): i64 {
    var pid = _regression_fork();
    if (pid == 0) {
        sys_dup2(out_fd, 1);
        sys_dup2(out_fd, 2);
        var dn_r = sys_open("/dev/null", 0, 0);
        if (dn_r >= 0) { _regression_redirect(dn_r, 0); }
        sys_exit(127);
    }
    return 0;
}
EOF
out=$(scan "$D/fx/clean.cyr")
want='OPENS 10
CHILDREN 4
LIFTED 1'
if printf '%s\n' "$out" | grep -q '^BAD'; then bad "self: the clean fixture is flagged: $(printf '%s' "$out" | grep '^BAD' | head -2 | tr '\n' ' ')"
elif [ "$(printf '%s\n' "$out" | grep -v '^BAD')" != "$want" ]; then bad "self: the clean fixture counts read '$(printf '%s' "$out" | tr '\n' ' ')', want '$(printf '%s' "$want" | tr '\n' ' ')'"
else ok; fi
# check_mutant RULE LABEL VERB — the mutant in $D/fx/m/clean.cyr is RED as RULE naming VERB
check_mutant() {
    if cmp -s "$D/fx/clean.cyr" "$D/fx/m/clean.cyr"; then bad "self: mutant '$2' did not apply"; return; fi
    if scan "$D/fx/m/clean.cyr" | grep -q "^BAD $1 [^ ]*: $3: "; then ok
    else bad "self: mutant '$2' is not caught as $1 naming $3"; fi
}
mutant() {  # $1 = rule, $2 = sed expression, $3 = label, $4 = the verb the RED line must name
    sed "$2" "$D/fx/clean.cyr" > "$D/fx/m/clean.cyr"
    check_mutant "$1" "$3" "$4"
}
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/577, 420/' "Linux's 577" v1
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/0x241, 420/' "577 in hex" v1
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/O_WRONLY | 64 | 512, 420/' "a numeric bit or-ed in" v1
mutant flags 's/file_open(out_path, O_RDONLY, 0)/file_open(out_path, 2, 0)/' "file_open with 2" v1
mutant flags 's/sys_open("\/dev\/zero", 1, 0);/sys_open("\/dev\/zero",/' "a call split across lines" v1
mutant lift 's/var ofd = _regression_lift_fd(out_fd);/var ofd = out_fd;/' "the lift turned into a copy" lifted_pipe
mutant lift '/var ofd = _regression_lift_fd(out_fd);/d' "the lift deleted" lifted_pipe
mutant lift 's/_regression_redirect(ofd, 1);/_regression_redirect(out_fd, 1);/' "the lifted fd unused" lifted_pipe
# the lift moved below the stdin redirect
awk '/var ofd = _regression_lift_fd\(out_fd\);/ { held = $0; next } { print } /_regression_redirect\(rfd, 0\);/ { print held }' \
    "$D/fx/clean.cyr" > "$D/fx/m/clean.cyr"
check_mutant lift "the lift after the stdin redirect" lifted_pipe
# the capture shape with its stdin redirect first
awk '/^        _regression_redirect\(out_fd, 1\);/ { held = $0; next } { print } /if \(dn_r >= 0\) \{ _regression_redirect\(dn_r, 0\); \}/ && held != "" { print held; held = "" }' \
    "$D/fx/clean.cyr" > "$D/fx/m/clean.cyr"
check_mutant lift "the capture's stdin redirect first" ordered_capture
mutant lift 's/^        sys_dup2(out_fd, 1);$/        sys_dup2(dn_r, 0); sys_dup2(out_fd, 1);/' "dup2 onto 0, then out_fd onto 1, one line" both_dup2

# ── live mutants: the tree's own opens and lifts broken one at a time ──────────────────────────
live=0
# live VERB RULE LABEL AWK-PROGRAM — the program (verb in `verb`) applied to $LIB must change it
# and turn the scan RED as RULE naming VERB
live() {
    awk -v verb="$1" "$4" "$LIB" > "$D/live.cyr"
    if cmp -s "$LIB" "$D/live.cyr"; then bad "self: live mutant '$3' in $1 did not apply — the verb moved or changed shape"; return; fi
    if scan "$D/live.cyr" | grep -q "^BAD $2 [^ ]*: $1: "; then ok; live=$((live + 1))
    else bad "self: live mutant '$3' in $1 is not RED as $2 naming the verb"; fi
}
INFN='/^fn[ \t]/ { infn = (index($0, "fn " verb "(") == 1) }'
for verb in regression_pipe_to_bin_capture regression_ssh_remote_exec_capture regression_exec_in_dir3; do
    live "$verb" flags "577 restored" "$INFN"'
        infn && !done && index($0, "sys_open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 420)") { sub(/O_WRONLY \| O_CREAT \| O_TRUNC, 420/, "577, 420"); done = 1 }
        { print }'
    live "$verb" lift "the lift deleted" "$INFN"'
        infn && !done && index($0, "= _regression_lift_fd(") { done = 1; next }
        { print }'
    live "$verb" lift "the lift turned into a copy" "$INFN"'
        infn && !done && index($0, "= _regression_lift_fd(") { sub(/_regression_lift_fd\(out_fd\)/, "out_fd"); done = 1 }
        { print }'
done

# ── the tree ────────────────────────────────────────────────────────────────────────────────────
out=$(scan "$LIB")
bads=$(printf '%s\n' "$out" | grep '^BAD' || true)
if [ -n "$bads" ]; then
    printf '%s\n' "$bads" | while IFS= read -r l; do printf '  FAIL: %s\n' "${l#BAD }"; done
    fail=$((fail + $(printf '%s\n' "$bads" | wc -l)))
else ok; fi
no=$(printf '%s\n' "$out" | grep '^OPENS' | awk '{print $2}')
nc=$(printf '%s\n' "$out" | grep '^CHILDREN' | awk '{print $2}')
nl=$(printf '%s\n' "$out" | grep '^LIFTED' | awk '{print $2}')
[ "${no:-0}" -ge 25 ] && ok || bad "floor: ${no:-0} open calls read in $LIB (want >= 25) — the scan went blind or the verbs moved"
[ "${nc:-0}" -ge 10 ] && ok || bad "floor: ${nc:-0} fork children read in $LIB (want >= 10) — the scan went blind or the verbs moved"
[ "${nl:-0}" -ge 3 ] && ok || bad "floor: ${nl:-0} children redirect a lifted fd onto 1 in $LIB (want >= 3: pipe_to_bin_capture, ssh_remote_exec_capture, exec_in_dir3)"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: regression_child_fd_shapes: $fail failed, $pass passed"
    exit 1
fi
echo "PASS: regression_child_fd_shapes ($pass checks; $no open calls, every flag 0 / 1 or the O_* constants; $nc fork children, $nl lifting their out_fd before the stdin redirect; $live live mutants RED)"
exit 0
