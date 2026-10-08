#!/bin/sh
# tests/gates/memory/fmt_buf_callers_sized.sh — 6.6.20 (RLM-05)
#
# EVERY `&local` BUFFER HANDED TO fmt_hex_buf / fmt_int_buf HOLDS THE WORST CASE.
#
# THE CONTRACT (lib/fmt.cyr). fmt_hex_buf writes len + 1 <= 17 bytes (16 digits + NUL);
# fmt_int_buf writes len + 1 <= 21 (sign + 19 digits + NUL). A local `var b[N]` is N BYTES,
# rounded up to 8, so a caller needs `[24]`, never `[16]`.
#
# THE DEFECT. fmt_sprintf's %x scratch was `var xtmp[16]`: any value with a nibble at bit 60
# or higher (every negative, for one) is 16 digits, and the NUL landed on the neighbouring
# stack slot — CYRIUS-2026-0028's class, one byte wide. It was latent (that slot, `xval`, is dead after
# the call), so no run-time probe can see it, which is why this is a census: the size the
# caller DECLARED against the bytes the callee WRITES. cyrld's printhex had the same `[16]`,
# and five cyrld fmt_int_buf scratches were `[16]` against a 21-byte worst case.
#
# THE RULE (the awk below). A call `fmt_hex_buf(.., &NAME)` / `fmt_int_buf(.., &NAME)` is
# RESOLVED against the last `var NAME[N]` (N bytes rounded up to 8; a column-0 top-level
# `var NAME[N]` is N*8) or `var NAME: i64[N]` (N*8) in the same fn, else at top level. It is
# SHORT when that is below the contract and UNRESOLVED when no declaration is found — both
# fail. The call match stops at `;` (`[^;]*`, not `.*`): a greedy match resolved the LAST
# `, &NAME)` on the line, so `fmt_hex_buf(n, &a); foo(n, &b);` checked `&b` and missed a short
# `&a`. `buf + pos` / heap callers are not this census's shape (fmt_int_buf_bounded.tcyr
# covers fmt_int_buf's own write). Comments and string literals are masked.
# SCOPE: lib/ programs/ cbt/ (*.cyr), benches/ (*.bcyr) and fuzz/ (*.fcyr), recursive.
# (bench_fmt's `var buf[8]` for fmt_int_buf(42, ..) was the one site outside the first scope —
# safe for 42, below the contract all the same.) A short site in a vendored fold is fixed
# upstream and re-vendored, never in the fold.
#
# AXES
#   1  the detector, self-tested on a fixture with every shape above (exact verdict set)
#   2  anti-vacuous floor: resolved sites >= 60 (79 at 6.6.20, benches/ + fuzz/ included)
#   3  the census: no SHORT and no UNRESOLVED site in scope
#   4  MUTATION ROW: lib/fmt.cyr with fmt_sprintf's scratch put back to `[16]` is flagged
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=fmt_buf_callers_sized
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
_ok() { echo "  ok: $1"; }

cat > "$W/scan.awk" <<'AWK'
function reset_locals(   k) { for (k in loc) delete loc[k] }
FNR == 1 { reset_locals(); for (k in top) delete top[k] }
{
    line = $0
    gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
    sub(/#.*$/, "", line)
    if (line ~ /^((pub|public|private|shared|async)[ \t]+)*fn[ \t]+[A-Za-z_]/) reset_locals()
    s = line
    while (match(s, /var [A-Za-z_][A-Za-z0-9_]*(: *i64)?\[[0-9]+\]/)) {
        d = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        nm = d; sub(/^var /, "", nm); sub(/[:\[].*$/, "", nm)
        n = d; sub(/^.*\[/, "", n); sub(/\].*$/, "", n); n = n + 0
        if (d ~ /: *i64/ || line ~ /^var /) bytes = n * 8
        else bytes = int((n + 7) / 8) * 8
        if (line ~ /^var /) top[nm] = bytes; else loc[nm] = bytes
    }
    s = line
    while (match(s, /fmt_(int|hex)_buf\([^;]*, *&[A-Za-z_][A-Za-z0-9_]*\)/)) {
        c = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        need = (c ~ /^fmt_hex/) ? 17 : 21
        nm = c; sub(/^.*, *&/, "", nm); sub(/\).*$/, "", nm)
        sz = (nm in loc) ? loc[nm] : ((nm in top) ? top[nm] : -1)
        st = (sz < 0) ? "UNRESOLVED" : ((sz >= need) ? "ok" : "SHORT")
        printf "%s %s:%d &%s %d/%d\n", st, FILENAME, FNR, nm, sz, need
    }
}
AWK

# ── axis 1: the detector on a fixture ────────────────────────────────────────────────────
cat > "$W/fx.cyr" <<'FX'
var gtop[3];
fn a(n): i64 { var b[16]; fmt_hex_buf(n, &b); return 0; }
fn b(n): i64 { var b[24]; fmt_hex_buf(n, &b); return 0; }
fn c(n): i64 { var t: i64[3]; fmt_int_buf(n, &t); return 0; }
fn d(n): i64 { fmt_int_buf(n, &gtop); return 0; }
fn e(n): i64 {
    var x[17];
    var y[16];
    fmt_int_buf(n, &x);
    fmt_int_buf(load64(n + 8), &y);
    return 0;
}
fn f(n): i64 { fmt_hex_buf(n, &y); return 0; }
fn g(n): i64 {
    var z[8];
    # fmt_hex_buf(n, &z);
    syscall(1, 1, "fmt_hex_buf(n, &z)", 18);
    var w[16]; var l = fmt_int_buf(n, &w);
    return l;
}
fn z(n): i64 { var a[8]; var b[24]; fmt_hex_buf(n, &a); foo(n, &b); return 0; }
FX
awk -f "$W/scan.awk" "$W/fx.cyr" | sed "s|$W/||" > "$W/fx.got"
cat > "$W/fx.want" <<'WANT'
SHORT fx.cyr:2 &b 16/17
ok fx.cyr:3 &b 24/17
ok fx.cyr:4 &t 24/21
ok fx.cyr:5 &gtop 24/21
ok fx.cyr:9 &x 24/21
SHORT fx.cyr:10 &y 16/21
UNRESOLVED fx.cyr:13 &y -1/17
SHORT fx.cyr:18 &w 16/21
SHORT fx.cyr:21 &a 8/17
WANT
if cmp -s "$W/fx.want" "$W/fx.got"; then
    _ok "detector: 9 fixture sites, exact verdicts (short, sized, typed, top-level, rounded, nested call, out-of-fn, comment/string masked, two statements on one line)"
else
    _fail "detector fixture verdicts differ:"; diff "$W/fx.want" "$W/fx.got" | sed 's/^/      /'
fi

# ── axes 2 + 3: the census ──────────────────────────────────────────────────────────────
{ find lib programs cbt -name '*.cyr'; find benches -name '*.bcyr'; find fuzz -name '*.fcyr'; } | LC_ALL=C sort > "$W/files"
xargs awk -f "$W/scan.awk" < "$W/files" > "$W/census"
RES=$(grep -c -v '^UNRESOLVED' "$W/census" || true)    # grep -c exits 1 on a 0 count
if [ "$RES" -ge 60 ]; then _ok "floor: $RES resolved call sites (>= 60)"
else _fail "floor: only $RES resolved call sites (< 60) — the scan matched almost nothing"; fi
BAD=$(grep -c -v '^ok ' "$W/census" || true)
if [ "$BAD" -eq 0 ]; then _ok "census: every &local buffer holds fmt_hex_buf's 17 / fmt_int_buf's 21 bytes"
else
    _fail "census: $BAD site(s) short or unresolved (declare the buffer as var NAME[24] in the calling fn):"
    grep -v '^ok ' "$W/census" | sed 's/^/      /'
fi

# ── axis 4: mutation row ────────────────────────────────────────────────────────────────
mkdir -p "$W/mut/lib"
sed 's/var xtmp\[24\];/var xtmp[16];/' lib/fmt.cyr > "$W/mut/lib/fmt.cyr"
if cmp -s lib/fmt.cyr "$W/mut/lib/fmt.cyr"; then
    _fail "mutation: could not find fmt_sprintf's \`var xtmp[24];\` to revert (has the scratch moved?)"
elif (cd "$W/mut" && awk -f "$W/scan.awk" lib/fmt.cyr) | grep -q '^SHORT lib/fmt.cyr:[0-9]* &xtmp 16/17$'; then
    _ok "mutation: fmt_sprintf's %x scratch back at [16] is flagged SHORT"
else
    _fail "mutation: fmt_sprintf's %x scratch back at [16] was NOT flagged"
fi

if [ "$FAILS" -eq 0 ]; then echo "PASS: $NAME"; exit 0; fi
echo "FAIL: $NAME ($FAILS axis failure(s))"
exit 1
