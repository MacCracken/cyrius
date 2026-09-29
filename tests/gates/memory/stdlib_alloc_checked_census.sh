#!/bin/sh
# tests/gates/memory/stdlib_alloc_checked_census.sh — 6.6.10 (bite 12)
#
# EVERY FIRST-PARTY `alloc(` RESULT IS ZERO-CHECKED BEFORE IT IS USED — a census with a
# SHRINK-ONLY allowlist, so the unchecked-alloc sweep is checkable instead of a hand count.
#
# THE CLASS. alloc() returns 0 when it refuses (ALLOC_MAX, a failed brk/mmap, the agnos/PE/cx
# arms alike), and a store through 0 is a SIGSEGV natively, a page fault under Windows and a
# SILENT write to guest offset 0 on cx. 6.6.7/6.6.8 swept lib/io.cyr; the 6.6.10 triage then
# re-ran its heuristic over the rest of first-party lib/ and found ~112 more sites (test_scratch
# was one: rc 139 on x86/aarch64, a wine page fault, and on cx a name that was address 0).
#
# THE RULE (the awk below). A `v = alloc(` — `var` or plain assignment, globals included — is
# a HIT when the FIRST later line of the same fn that names `v` is not a zero check
# (`v == 0`, `v != 0`, `v <= 0`, `v < 1`, `v > 0`, `0 == v`, `!v`, `if (v)`) and not
# `return v;`. A reassignment `v = <rhs without v>` is not a use (it replaces the value); a use
# on the alloc line itself is a hit; no mention before the fn's closing `}` is a hit (the
# value escapes unchecked — e.g. into a global). Comments and string literals are masked.
# SCOPE: lib/*.cyr + lib/*/*.cyr minus the vendored folds, which are read from
# docs/ecosystem.md's fold table (fix those upstream, never in the fold).
#
# AXES
#   1  the detector, self-tested on a fixture with every shape above (exact hit set)
#   2  anti-vacuous floors: folds excluded >= 10, files scanned >= 80, alloc sites >= 200
#   3  the census: every hit must be on the ALLOWLIST (a NEW unchecked alloc fails, named), and
#      every allowlist entry must still be a hit — a fixed site FAILS until its line is deleted
#      here, so the list can only SHRINK
#   4  MUTATION ROW: the first live site whose next line is its `if (v == 0)` check is copied
#      with that line deleted, and the detector must flag exactly that site
#
# `--list` prints the live hits as `file:line fn var` and exits 0 (what each lane re-runs).
#
# ALLOWLIST FORMAT: `<file> <fn> <var>`, one per unchecked site (a repeat = two sites). Keyed
# on the fn and variable, not the line, so unrelated edits do not churn it. 6.6.10 bite 12
# set it at the 131 hits on 6d12c1e6; every lane removes its own lines as it fixes them, and
# the list is re-derived on the merged tree — it may only shrink.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=stdlib_alloc_checked_census
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

cat > "$W/scan.awk" <<'AWK'
function strip(s) {
    gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
    sub(/#.*$/, "", s)
    return s
}
function mentions(s, v) { return match(s, "(^|[^A-Za-z0-9_.])" v "([^A-Za-z0-9_]|$)") }
function zcheck(s, v) {
    if (match(s, "(^|[^A-Za-z0-9_.])" v "[ \t]*(==|!=|<=)[ \t]*0([^A-Za-z0-9_x]|$)")) return 1
    if (match(s, "(^|[^A-Za-z0-9_.])" v "[ \t]*(<[ \t]*1|>[ \t]*0)([^A-Za-z0-9_]|$)")) return 1
    if (match(s, "(^|[^A-Za-z0-9_])0[ \t]*(==|!=)[ \t]*" v "([^A-Za-z0-9_]|$)")) return 1
    if (match(s, "![ \t]*" v "([^A-Za-z0-9_]|$)")) return 1
    if (match(s, "(if|while)[ \t]*\\([ \t]*" v "[ \t]*\\)")) return 1
    return 0
}
# `v = <rhs not naming v>` replaces the value: not a use of the unchecked one
function reassigns(s, v,   r) {
    if (!match(s, "(^|[^A-Za-z0-9_.])" v "[ \t]*=[^=]")) return 0
    r = substr(s, RSTART + RLENGTH)
    return !mentions(r, v)
}
function hit(v) { print FILENAME ":" pline[v] " " pfn[v] " " v; delete pline[v]; delete pfn[v] }
function flush_all(   v) { for (v in pline) hit(v) }
FNR == 1 { flush_all(); fn = "<top>" }
{
    s = strip($0)
    if (match(s, /^[ \t]*((pub|public|private|shared|async)[ \t]+)*fn[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        flush_all()
        t = substr(s, RSTART, RLENGTH); sub(/.*fn[ \t]+/, "", t); fn = t
        next
    }
    if (s ~ /^}/) { flush_all(); fn = "<top>"; next }
    nv = ""
    if (match(s, /(^|[^A-Za-z0-9_.])(var[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[ \t]*[A-Za-z0-9_]+[ \t]*)?=[ \t]*alloc\(/)) {
        m = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH)
        sub(/^[^A-Za-z_]*/, "", m); sub(/^var[ \t]+/, "", m)
        nv = m; sub(/[^A-Za-z0-9_].*$/, "", nv)
        pre = substr(s, 1, RSTART)
    }
    for (v in pline) {
        if (v == nv) { hit(v); continue }
        if (!mentions(s, v)) continue
        if (zcheck(s, v) || match(s, "return[ \t]+" v "[ \t]*;")) { delete pline[v]; delete pfn[v] }
        else if (reassigns(s, v)) { }
        else hit(v)
    }
    if (nv != "" && !zcheck(rest, nv)) {
        pline[nv] = FNR; pfn[nv] = fn
        if (mentions(rest, nv) && !match(rest, "return[ \t]+" nv "[ \t]*;")) hit(nv)
    }
}
END { flush_all() }
AWK
scan() { awk -f "$W/scan.awk" "$@" | sort -t: -k1,1 -k2,2n; }

# ── the scan set ─────────────────────────────────────────────────────────────────────────
grep -oE '^\| `lib/[a-z0-9_]+\.cyr` \|' docs/ecosystem.md | sed -E 's/^\| `(lib\/[a-z0-9_]+\.cyr)` \|$/\1/' | sort -u > "$W/folds"
ls lib/*.cyr lib/*/*.cyr 2>/dev/null | sort | grep -vxF -f "$W/folds" > "$W/files"
NF=$(wc -l < "$W/folds" | tr -d ' ')
NS=$(wc -l < "$W/files" | tr -d ' ')
# shellcheck disable=SC2046
scan $(cat "$W/files") > "$W/hits"
# shellcheck disable=SC2046
NA=$(grep -hcE '(^|[^A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[ \t]*[A-Za-z0-9_]+[ \t]*)?=[ \t]*alloc\(' $(cat "$W/files") | awk '{s+=$1} END {print s+0}')
if [ "${1:-}" = "--list" ]; then cat "$W/hits"; exit 0; fi

echo "axis 1: the detector finds exactly the planted unchecked shapes"
cat > "$W/fx.cyr" <<'CYR'
fn ok_next(n): i64 {
    var a = alloc(n);
    if (a == 0) { return 0; }
    store64(a, 1);
    return a;
}
fn ok_joint(n): i64 {
    var a = alloc(n);
    var b = alloc(n);
    if (a == 0 || b == 0) { return 0; }
    return a;
}
fn ok_return(n): i64 {
    var a = alloc(n);
    return a;
}
fn ok_reassign(n, al): i64 {
    var h = 0;
    if (al == 0) { h = alloc(n); }
    if (al != 0) { h = alloc_via(al, n); }
    if (h == 0) { return 0; }
    return h;
}
fn ok_neg(n): i64 {
    var a = alloc(n);   # store64(a, 0) in a comment is not a use
    if (!a) { return 0 - 1; }
    return 0;
}
fn bad_next(n): i64 {
    var d = alloc(n);
    store64(d, 1);
    return d;
}
fn bad_sameline(n): i64 {
    var e = alloc(24); store64(e, 1); return e;
}
var _g = 0;
fn bad_escape(n): i64 {
    _g = alloc(n);
    return 0;
}
fn bad_late(n): i64 {
    var c = alloc(n);
    memcpy(c, "if (c == 0)", 4);
    if (c == 0) { return 0; }
    return c;
}
CYR
scan "$W/fx.cyr" | sed 's/^[^ ]* //' > "$W/fxhits"
printf 'bad_next d\nbad_sameline e\nbad_escape _g\nbad_late c\n' | sort > "$W/fxwant"
sort "$W/fxhits" > "$W/fxgot"
cmp -s "$W/fxgot" "$W/fxwant" || { _fail "axis 1: the detector's hits on the fixture are not the planted four:"; diff "$W/fxwant" "$W/fxgot" | sed 's/^/      /'; }

echo "axis 2: anti-vacuous floors"
[ "$NF" -ge 10 ] || _fail "axis 2: only $NF vendored folds read from docs/ecosystem.md (floor 10) — the fold table moved?"
while read -r f; do [ -f "$f" ] || _fail "axis 2: the fold table names $f, which is not in lib/"; done < "$W/folds"
[ "$NS" -ge 80 ] || _fail "axis 2: only $NS first-party lib files scanned (floor 80)"
[ "$NA" -ge 200 ] || _fail "axis 2: only $NA alloc sites in the scanned files (floor 200)"

echo "axis 3: the census against the shrink-only allowlist"
cat > "$W/allow" <<'ALLOW'
lib/args_agnos.cyr _agnos_getenv res
lib/assert.cyr test_scratch buf
lib/async_win.cyr _asw_wcmdline wbuf
lib/async_win.cyr _asw_wenvblock wbuf
lib/audit_walk.cyr _aw_is_generated buf
lib/audit_walk.cyr _aw_is_distlib_bundle buf
lib/audit_walk.cyr _aw_dir_list_typed buf
lib/audit_walk.cyr audit_fmt_walk orig_buf
lib/audit_walk.cyr audit_fmt_walk fmt_buf
lib/audit_walk.cyr audit_lint_walk lint_buf
lib/audit_walk.cyr audit_doc_walk doc_buf
lib/bench.cyr bench_new b
lib/boxed.cyr boxed_new b
lib/cffi.cyr cffi_struct_new layout
lib/chrono.cyr dur_new d
lib/chrono.cyr _chrono_init_mdays t
lib/chrono.cyr epoch_to_date r
lib/chrono.cyr iso8601 buf
lib/chrono.cyr dt_format out
lib/dynlib.cyr _parse_dynamic result
lib/dynlib.cyr dynlib_open h
lib/fs_win.cyr dir_list wpat
lib/fs_win.cyr dir_list fd
lib/fs_win.cyr dir_list name8
lib/fs_win.cyr is_dir wpath
lib/http.cyr _http_parse_url result
lib/http.cyr _http_parse_url host
lib/http.cyr _http_build_request buf
lib/http.cyr _http_parse_response result
lib/http.cyr http_get bad
lib/http.cyr http_get slot
lib/http.cyr http_get unr
lib/http.cyr http_get err
lib/http.cyr http_get err
lib/http.cyr http_get serr
lib/http.cyr http_get rbuf
lib/http.cyr http_get_r slot
lib/http.cyr http_get_r rbuf
lib/http.cyr http_get_a slot
lib/net.cyr sockaddr_in sa
lib/net.cyr sockaddr_in6 sa
lib/net.cyr sock_reuse val
lib/net.cyr sock_set_recv_timeout tv
lib/net.cyr sock_set_send_timeout tv
lib/process.cyr _proc_tree_collect _proc_tree
lib/process.cyr exec_vec argv
lib/process.cyr exec_vec envp
lib/process.cyr exec_capture_status argv
lib/process.cyr exec_capture_status envp
lib/process.cyr exec_env argv
lib/process.cyr exec_env envp
lib/process.cyr exec_vec_str argv
lib/process.cyr exec_vec_str envp
lib/process.cyr exec_capture_str argv
lib/process.cyr exec_capture_str envp
lib/process.cyr exec_env_str argv
lib/process.cyr exec_env_str envp
lib/process.cyr _read_environ_envp blob
lib/process.cyr _read_environ_envp envp
lib/process.cyr exec_cmd envp
lib/process_win.cyr _win_wcmdline3 wbuf
lib/process_win.cyr _win_wcmdline_vec wbuf
lib/process_win.cyr _win_wenvblock_vec wbuf
lib/regex.cyr str_glob buf
lib/regex.cyr str_replace buf
lib/regex.cyr _re_m_lazy_init _re_m_cur
lib/regex.cyr _re_m_lazy_init _re_m_next
lib/regex.cyr _re_m_lazy_init _re_m_lastgen
lib/regex.cyr regex_compile nfa
lib/regex.cyr _re_pike_run saves_scratch
lib/regex.cyr _re_pike_run match_saves
lib/regression.cyr _regression_tree_init _regression_tree_pids
lib/regression.cyr _regression_tree_init _regression_tree_dbuf
lib/regression.cyr _regression_tree_init _regression_tree_cbuf
lib/regression.cyr _regression_term_children_once _regression_termed
lib/regression.cyr regression_pipe_to_bin_capture src_buf
lib/regression.cyr regression_exec_in_dir3_env merged
lib/sha1.cyr sha1 buf
lib/sha1.cyr sha1 w
lib/str.cyr str_from_buf buf
lib/str.cyr str_cstr buf
lib/string.cyr str_lower_cstr dst
lib/string.cyr str_upper_cstr dst
lib/sync.cyr mutex_new m
lib/sync_macos.cyr mutex_new m
lib/sync_windows.cyr mutex_new m
lib/syscalls_aarch64_linux.cyr sigset_new set
lib/syscalls_aarch64_linux.cyr epoll_event_new ev
lib/syscalls_aarch64_linux.cyr timerspec_new ts
lib/syscalls_x86_64_agnos.cyr sigset_new set
lib/syscalls_x86_64_linux.cyr sigset_new set
lib/syscalls_x86_64_linux.cyr epoll_event_new ev
lib/syscalls_x86_64_linux.cyr timerspec_new ts
lib/thread.cyr thread_create t
lib/thread.cyr chan_new ch
lib/thread.cyr chan_new buf
lib/thread_agnos.cyr chan_new buf
lib/thread_local.cyr _tlocal_win_block blk
lib/thread_macos.cyr chan_new buf
lib/thread_win.cyr thread_create a
lib/thread_win.cyr chan_new ch
lib/thread_win.cyr chan_new buf
lib/tls.cyr _tls_native_alloc ctx
lib/tls.cyr tls_connect_alloc ctx
lib/tls.cyr tls_accept_alloc pcell
lib/tls.cyr tls_accept_alloc ctx
lib/trait.cyr trait_obj_new obj
lib/trait.cyr display_vtable vt
lib/trait.cyr default_vtable vt
lib/trait.cyr eq_vtable vt
lib/trait.cyr from_vtable vt
lib/trait.cyr _int_to_string buf
lib/unicode/casefold.cyr str_lower_unicode buf
lib/unicode/casefold.cyr str_lower_unicode cp_out
lib/unicode/casefold.cyr str_upper_unicode buf
lib/unicode/casefold.cyr str_upper_unicode cp_out
lib/unicode/normalize.cyr _uc_decompose_cp_recursive step_buf
lib/unicode/normalize.cyr _uc_decompose_cp_recursive_compat step_buf
lib/unicode/normalize.cyr str_normalize dec_buf
lib/unicode/normalize.cyr str_normalize cp_slot
lib/unicode/normalize.cyr str_normalize out_buf
lib/ws.cyr ws_new ws
lib/ws.cyr _ws_handshake_request buf
lib/ws.cyr _ws_send_frame masked
lib/ws.cyr ws_recv_frame payload
lib/ws_server.cyr ws_server_new ws
lib/ws_server.cyr ws_server_handshake concat
lib/ws_server.cyr ws_server_handshake digest
lib/ws_server.cyr ws_server_recv _wss_recv_buf
lib/ws_server.cyr ws_server_recv out
lib/ws_server.cyr ws_server_send_close payload_buf
ALLOW
awk '{split($1, a, ":"); print a[1], $2, $3}' "$W/hits" | sort > "$W/got"
grep -v '^[[:space:]]*$' "$W/allow" | sort > "$W/want"
comm -13 "$W/want" "$W/got" > "$W/new"
comm -23 "$W/want" "$W/got" > "$W/gone"
if [ -s "$W/new" ]; then
    _fail "axis 3: $(wc -l < "$W/new" | tr -d ' ') NEW unchecked alloc site(s) — check the result (return the fn's error sentinel) before the first use:"
    while read -r f fn v; do grep -E "^$f:[0-9]+ $fn $v\$" "$W/hits" | sed 's/^/      /'; done < "$W/new" | sort -u
fi
if [ -s "$W/gone" ]; then
    _fail "axis 3: $(wc -l < "$W/gone" | tr -d ' ') allowlisted site(s) are no longer hits — delete their lines from this gate's ALLOW list (it only shrinks):"
    sed 's/^/      /' "$W/gone"
fi

echo "axis 4: mutation — a real check deleted is caught"
M=$(awk 'FNR == 1 { pv = "" }
    pv != "" { if ($0 ~ "^[ \t]*if \\(" pv " == 0\\) \\{ return [^}]*\\}[ \t]*$") { print FILENAME ":" FNR ":" pv; exit } pv = "" }
    match($0, /^[ \t]*var [A-Za-z_][A-Za-z0-9_]* = alloc\(/) { v = $0; sub(/^[ \t]*var /, "", v); sub(/ .*/, "", v); pv = v }' $(cat "$W/files"))
if [ -z "$M" ]; then
    _fail "axis 4: no live \`var v = alloc(…);\` followed by \`if (v == 0) { return … }\` to mutate"
else
    mf=${M%%:*}; rest=${M#*:}; ml=${rest%%:*}; mv=${rest#*:}
    mkdir -p "$W/mut/$(dirname "$mf")"
    sed "${ml}d" "$mf" > "$W/mut/$mf"
    if scan "$W/mut/$mf" | grep -qE "^$W/mut/$mf:$((ml - 1)) [A-Za-z0-9_<>]+ $mv\$"; then
        echo "  ok: deleting $mf:$ml (the check of '$mv') is flagged"
    else
        _fail "axis 4: deleting the check at $mf:$ml did not make '$mv' a hit"
    fi
fi

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME ($(wc -l < "$W/hits" | tr -d ' ') allowlisted unchecked site(s) of $NA across $NS first-party files; $NF folds excluded; shrink-only)"
