#!/bin/sh
# Gate: the `[deps] stdlib` key scan finds the REAL key, so the auto-prepend
# actually happens (v6.5.17).
#
# THE FILED DEFECT (bayan 1.4.1, 2026-08-10). In bayan, a source with no includes
# failed to build — `undefined variable 'SYS_WRITE'` — while the identical probe
# succeeded in kavach. bayan declares `syscalls` in `[deps] stdlib` and its
# `lib/syscalls_x86_64_linux.cyr` defines SYS_WRITE. The bundle and the sidecar were
# proven correct; only the auto-prepend was dead, so `cyrius distlib` exited 1 on a
# CORRECT bundle.
#
# ⭐ THE TRIGGER IS IN `[package]`, 533 BYTES ABOVE `[deps]`. bayan's description reads
# "... foldable into stdlib per the sandhi pattern". cmd_deps' Phase-1 scan walks the
# RAW MANIFEST BYTES for the literal "stdlib" and had exactly two guards: the preceding
# byte is not `[0-9A-Za-z_]`, and the line's first non-space byte is not `#`. A key
# spelled inside a QUOTED STRING VALUE passes both. `_parse_toml_str_array` is purely
# positional — it skipped to the next `[`, which was the `[build]` SECTION HEADER, read
# to the `]`, and returned an EMPTY vec. The scan then `break`ed unconditionally, so the
# genuine `stdlib = [` was never reached and `_dep_includes` stayed empty.
#
# It failed SILENTLY: `errors` was never incremented and `copied` stayed 0, so even the
# "N deps resolved" summary was suppressed. The absence of that line was the only tell.
#
# ⚠ FIVE HYPOTHESES WERE MEASURED AND FALSIFIED BEFORE THIS WAS FILED — do not repeat
# them: it is not the version pin / re-exec (running build/cyrius directly fails the
# same), not the multi-line array, not multiple leaves per line, not `[deps]`-before-
# `[lib]` section order, and not the `[lib]`/`[lib.*]` profile sections. Every one of
# those probed the `[deps]` region; the trigger was never there.
#
# TWO DEFECTS WERE FIXED, AND THEY OVERLAP ON bayan's OWN INPUT:
#   1. no "inside a quoted string" guard on the key match
#   2. it committed to a zero-length parse instead of continuing to scan
# ⚠ MEASURED, AND IT IS THE TRAP IN THIS GATE: reverting (1) alone leaves axis 1 GREEN,
# because bayan's mis-parse happens to land on the `[build]` SECTION HEADER and return
# EMPTY — so (2) rescues it. Reverting (2) alone leaves axis 2 red but also axis 1.
# A gate built only from the filed repro would therefore fail to pin guard (1) at all.
# Axes 2 and 3 exist to give each fix a shape the other cannot cover:
#   axis 2 — the mis-parse lands on a REAL, NON-EMPTY array (`keywords = [...]`), so the
#            scan commits to WRONG leaves and (2) cannot help. Pins guard (1). This is
#            the v5.5.26 patra shape, which is how we know it is not hypothetical.
#   axis 3 — a `stdlib` in a TRAILING inline comment passes all three boundary guards
#            (the comment guard inspects only the line's FIRST token, and the quote count
#            over `key = "value"   # ... stdlib ...` is EVEN), so only (2) saves it.
#            Trailing comments are common. Pins fix (2).
#
# ⚠ THE DECOY MUST COME **BEFORE** THE REAL KEY — the scan stops at its first accepted
# match, so a decoy placed after the declaration is never considered and the axis passes
# against a broken build. This is the same trap called out in distlib_deps_sidecar.sh
# axis 5, and it is why bayan's `[package]` description was able to do the damage.
#
# ⚠ NO `cyrius = "..."` KEY IN THESE MANIFESTS, and CYRIUS_RESOLVED=1 on every call:
# a pin makes the CLI re-exec ~/.cyrius/versions/<pin>/bin/cyrius, which would test an
# INSTALLED binary instead of build/cyrius and silently defeat mutation-proving.
# Likewise no `src/main.cyr` — that path is the cyrius-source-repo signal in
# _dep_find_stdlib_dir, and it would change which stdlib the probe resolves against.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }

# The filed repro verbatim: NO includes. SYS_WRITE/SYS_EXIT can only resolve if the
# `syscalls` leaf was auto-prepended from the declaration.
write_probe() {
    printf 'fn main(): i64 { syscall(SYS_WRITE, 1, "ok\\n", 3); return 0; }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' > "$1"
}

# $1 = case dir, $2 = manifest body. Builds the no-include probe; echoes "<exit> <stdout>".
run_case() {
    _d="$D/$1"
    mkdir -p "$_d" || return 1
    printf '%s' "$2" > "$_d/cyrius.cyml"
    write_probe "$_d/probe.cyr"
    ( cd "$_d" && CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_SHADOW_LIB=1 timeout 300 "$CY" build probe.cyr "$_d/out" ) > "$_d/log" 2>&1
    echo "$?"
}

echo "axis 1 - bayan's shape: 'stdlib' inside a quoted [package] value is NOT the key:"
M1='[package]
name = "ap1"
version = "0.1.0"
description = "ap1 - a distfile for the AGNOS-lineage Cyrius ecosystem; foldable into stdlib per the sandhi pattern"
license = "GPL-3.0-only"

[build]
entry = "probe.cyr"
output = "ap1"

[deps]
stdlib = [
    "syscalls",
]
'
RC=$(run_case c1 "$M1")
# ⭐ THE ASSERTION THE DEFECT FAILS. Pre-fix: exit 1, "undefined variable 'SYS_WRITE'".
check "build exits 0 (auto-prepend reached the real key)" 0 "$RC"
check "no 'undefined variable' error" 0 "$(grep -c "undefined variable 'SYS_WRITE'" "$D/c1/log" 2>/dev/null || true)"
check "the declared leaf was materialised into lib/" 1 "$([ -f "$D/c1/lib/syscalls.cyr" ] && echo 1 || echo 0)"
if [ -x "$D/c1/out" ]; then
    OUT=$("$D/c1/out" 2>/dev/null); RUNRC=$?
    check "the built binary runs (exit 0)" 0 "$RUNRC"
    check "and writes through SYS_WRITE" "ok" "$OUT"
else
    check "binary emitted" 1 0
fi

echo ""
echo "axis 2 - PINS GUARD 1: the quoted-value mis-parse lands on a REAL array, so the"
echo "         scan commits to WRONG leaves and 'continue on empty' cannot rescue it:"
# `_parse_toml_str_array` is positional — from the match inside `description` it skips to
# the NEXT `[` in the file, which here is the `[` of `keywords = ["bogus_leaf"]`. That
# parse is NON-EMPTY, so the scan commits and breaks: `bogus_leaf` is resolved as a
# stdlib leaf and the genuine `syscalls` is never reached. Deleting the quote guard turns
# this axis RED while axis 1 stays green — measured, and the reason this axis exists.
M2='[package]
name = "ap2"
version = "0.1.0"
description = "ap2 - foldable into stdlib per the sandhi pattern"
keywords = ["bogus_leaf"]

[build]
entry = "probe.cyr"

[deps]
stdlib = ["syscalls"]
'
RC=$(run_case c2 "$M2")
check "build exits 0 (the quoted value was not taken as the key)" 0 "$RC"
check "no 'undefined variable' error" 0 "$(grep -c "undefined variable 'SYS_WRITE'" "$D/c2/log" 2>/dev/null || true)"
check "the real leaf was materialised" 1 "$([ -f "$D/c2/lib/syscalls.cyr" ] && echo 1 || echo 0)"
check "the adjacent array was NOT read as the declaration" 0 "$([ -f "$D/c2/lib/bogus_leaf.cyr" ] && echo 1 || echo 0)"

echo ""
echo "axis 3 - PINS FIX 2: a TRAILING inline comment passes every boundary guard; the"
echo "         zero-length parse must keep scanning rather than commit:"
# `entry = "probe.cyr"   # stdlib leaves are auto-prepended` — line's first token is
# `entry` (not `#`), quote count before the match is 2 (EVEN), preceding byte is a space.
# All three guards pass. The next `[` after it is the `[deps]` HEADER, so the positional
# array parse returns empty. Only "don't break on an empty parse" recovers the real key.
M3='[package]
name = "ap3"
version = "0.1.0"

[build]
entry = "probe.cyr"   # stdlib leaves are auto-prepended before this entry
output = "ap3"

[deps]
stdlib = ["syscalls"]
'
RC=$(run_case c3 "$M3")
check "build exits 0 (empty parse did not end the scan)" 0 "$RC"
check "no 'undefined variable' error" 0 "$(grep -c "undefined variable 'SYS_WRITE'" "$D/c3/log" 2>/dev/null || true)"

echo ""
echo "axis 4 - the v5.5.26 guards are still live (no regression):"
# A leading comment mentioning stdlib, and a longer identifier `my_stdlib`, both BEFORE
# the real key. Neither may be taken as the declaration, and neither may end the scan.
M4='# this comment mentions stdlib and must not match
my_stdlib = ["bogus_leaf"]

[package]
name = "ap4"
version = "0.1.0"

[build]
entry = "probe.cyr"

[deps]
stdlib = ["syscalls"]
'
RC=$(run_case c4 "$M4")
check "build exits 0 (comment + identifier decoys skipped)" 0 "$RC"
check "the bogus leaf was NOT materialised" 0 "$([ -f "$D/c4/lib/bogus_leaf.cyr" ] && echo 1 || echo 0)"

echo ""
echo "axis 5 - a TAB between the key and '=' is a key separator:"
# The old test accepted only space or '='. `stdlib<TAB>= [...]` silently produced NO
# auto-prepend at all — the same silent-failure class, one byte away.
M5=$(printf '[package]\nname = "ap5"\nversion = "0.1.0"\n\n[build]\nentry = "probe.cyr"\n\n[deps]\nstdlib\t= ["syscalls"]\n')
RC=$(run_case c5 "$M5")
check "build exits 0 (tab-separated key resolved)" 0 "$RC"

echo ""
echo "axis 6 - a declaration that is genuinely absent still yields no prepend:"
# Guard against 'fix by always prepending'. No [deps] stdlib key at all => the probe
# MUST fail. If this passes, the axes above prove nothing.
M6='[package]
name = "ap6"
version = "0.1.0"

[build]
entry = "probe.cyr"

[deps.somedep]
path = "../nowhere"
'
RC=$(run_case c6 "$M6")
check "build FAILS without a stdlib declaration" 1 "$([ "$RC" = "0" ] && echo 0 || echo 1)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: stdlib-key-scan-boundary - quoted values / trailing comments are not the key"
    exit 0
fi
echo "FAIL: stdlib-key-scan-boundary - $fails assertion(s) failed"
exit 1
