#!/bin/sh
# tests/gates/toolchain/regression_child_fd_shapes.sh — 6.7.16
#
# lib/regression.cyr opens and hands over file descriptors in shapes that are right on EVERY
# target the module runs on. Static, comments and string contents stripped first.
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
#   self     a clean fixture passes and one mutant per rule shape fails BEFORE the tree is scanned,
#            and copies of the LIVE lib/regression.cyr with 577 back at each of the three
#            caller-out_path opens must each go RED naming the verb — a scanner that went blind
#            cannot read GREEN.
#   floors   >= 25 open calls read in lib/regression.cyr.
#
# MUTATION LEDGER — run 2026-10-19 (lane libfix, unit L1; x86_64 Linux): 577 restored at
#   regression_pipe_to_bin_capture / regression_ssh_remote_exec_capture / regression_exec_in_dir3
#   -> RED `flags`, naming that verb (the built-in live mutants run the same three every time).
# No compiler needed. Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.16]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd) || { echo "FAIL: regression_child_fd_shapes: cannot resolve ROOT"; exit 1; }
cd "$ROOT" || { echo "FAIL: regression_child_fd_shapes: cannot cd to $ROOT"; exit 1; }
command -v awk > /dev/null 2>&1 || { echo "SKIP: regression_child_fd_shapes: no awk"; exit 77; }
LIB=lib/regression.cyr
[ -f "$LIB" ] || { echo "FAIL: regression_child_fd_shapes: $LIB is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: regression_child_fd_shapes: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

# scan FILE — one `BAD <rule> <file>:<line>: <fn>: <why>` per violation, then `OPENS <n>`.
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
    function opens(line,   rest, off, a, f) {
        rest = line; off = 0
        while (match(rest, /(^|[^A-Za-z0-9_])(sys_open|file_open)\(/)) {
            a = callarg(rest, RSTART + RLENGTH - 1, 1)
            rest = substr(rest, RSTART + RLENGTH)
            nopen++
            if (a == "\001") { printf "BAD flags %s:%d: %s: an open call split across lines (cannot read its flags)\n", FILENAME, FNR, fname; continue }
            f = trim(a)
            if (f == "0" || f == "1") continue
            if (f ~ /(^|[^A-Za-z0-9_])[0-9]/)
                printf "BAD flags %s:%d: %s: the open flag `%s` is a number — spell it with the per-target O_* constants (Linux bits are not Darwin bits)\n", FILENAME, FNR, fname, f
        }
    }
    BEGIN { nopen = 0; fname = "(file scope)" }
    {
        line = strip($0)
        if (line ~ /^fn[ \t]/) { fname = line; sub(/^fn[ \t]+/, "", fname); sub(/\(.*$/, "", fname) }
        opens(line)
    }
    END { printf "OPENS %d\n", nopen }' "$1"
}

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# ── self-test ───────────────────────────────────────────────────────────────────────────────────
mkdir -p "$D/fx/m"
cat > "$D/fx/clean.cyr" <<'EOF'
fn v1(out_path): i64 {
    var a = sys_open("/dev/null", 1, 0);
    var b = sys_open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 420);   # 577 in a comment is fine
    var c = sys_open(&path, 0, 0);
    var d = file_open(out_path, O_RDONLY, 0);
    var e = sys_open("x, 577, y", O_WRONLY, 0);
    return 0;
}
EOF
out=$(scan "$D/fx/clean.cyr")
if printf '%s\n' "$out" | grep -q '^BAD'; then bad "self: the clean fixture is flagged: $(printf '%s' "$out" | grep '^BAD' | head -2 | tr '\n' ' ')"
elif ! printf '%s\n' "$out" | grep -q '^OPENS 5$'; then bad "self: the clean fixture counts read '$(printf '%s' "$out" | tail -1)', want 'OPENS 5'"
else ok; fi
mutant() {  # $1 = rule, $2 = sed expression, $3 = label, $4 = the verb the RED line must name
    sed "$2" "$D/fx/clean.cyr" > "$D/fx/m/clean.cyr"
    if cmp -s "$D/fx/clean.cyr" "$D/fx/m/clean.cyr"; then bad "self: mutant '$3' did not apply"; return; fi
    if scan "$D/fx/m/clean.cyr" | grep -q "^BAD $1 [^ ]*: $4: "; then ok
    else bad "self: mutant '$3' is not caught as $1 naming $4"; fi
}
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/577, 420/' "Linux's 577" v1
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/0x241, 420/' "577 in hex" v1
mutant flags 's/O_WRONLY | O_CREAT | O_TRUNC, 420/O_WRONLY | 64 | 512, 420/' "a numeric bit or-ed in" v1
mutant flags 's/file_open(out_path, O_RDONLY, 0)/file_open(out_path, 2, 0)/' "file_open with 2" v1
mutant flags 's/sys_open("\/dev\/null", 1, 0);/sys_open("\/dev\/null",/' "a call split across lines" v1

# ── live mutants: the tree's own caller-out_path opens with 577 back ───────────────────────────
live=0
for verb in regression_pipe_to_bin_capture regression_ssh_remote_exec_capture regression_exec_in_dir3; do
    awk -v verb="$verb" '
        /^fn[ \t]/ { infn = (index($0, "fn " verb "(") == 1) }
        infn && !done && index($0, "sys_open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 420)") {
            sub(/O_WRONLY \| O_CREAT \| O_TRUNC, 420/, "577, 420"); done = 1
        }
        { print }' "$LIB" > "$D/live.cyr"
    if cmp -s "$LIB" "$D/live.cyr"; then bad "self: live mutant $verb: no \`sys_open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 420)\` in it to restore 577 into"; continue; fi
    if scan "$D/live.cyr" | grep -q "^BAD flags [^ ]*: $verb: "; then ok; live=$((live + 1))
    else bad "self: live mutant $verb (577 restored) is not RED naming the verb"; fi
done

# ── the tree ────────────────────────────────────────────────────────────────────────────────────
out=$(scan "$LIB")
bads=$(printf '%s\n' "$out" | grep '^BAD' || true)
if [ -n "$bads" ]; then
    printf '%s\n' "$bads" | while IFS= read -r l; do printf '  FAIL: %s\n' "${l#BAD }"; done
    fail=$((fail + $(printf '%s\n' "$bads" | wc -l)))
else ok; fi
no=$(printf '%s\n' "$out" | grep '^OPENS' | awk '{print $2}')
[ "${no:-0}" -ge 25 ] && ok || bad "floor: ${no:-0} open calls read in $LIB (want >= 25) — the scan went blind or the verbs moved"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: regression_child_fd_shapes: $fail failed, $pass passed"
    exit 1
fi
echo "PASS: regression_child_fd_shapes ($pass checks; $no open calls, every flag argument 0 / 1 or the O_* constants; $live live 577 mutants RED)"
exit 0
