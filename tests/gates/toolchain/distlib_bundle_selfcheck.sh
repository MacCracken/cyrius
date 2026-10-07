#!/bin/sh
# Gate: `cyrius distlib`'s bundle self-check ACTUALLY COMPILES the bundle, and a bundle
# that does not compile is a FAILURE rather than a reassuring note (v6.5.14).
#
# THE MOTIVATING DEFECT — a check that had never once run. The self-check was
#     var check_r = compile(out_path, "/dev/null");
# and `compile()` writes an intermediate `<output>.tmp.<pid>` for its atomic rename.
# `/dev/null.tmp.<pid>` cannot be created (/dev/ is not writable), so the call failed on
# the WRITE every single time — before cycc ever saw the bundle. The handler then printed
#     note: bundle has unresolved symbols (expected for consumer-included bundles...)
# and exited 0. So a syntactically broken bundle and a perfect one produced byte-identical
# reassuring output. This is the SAME defect v5.7.8 fixed for `cyrius check` (see the
# comment at cbt/commands.cyr ~line 566); distlib never got the same treatment.
#
# ⭐ TWO WRONGS THAT LOOKED LIKE ONE RIGHT. Fixing only the temp path exposes the second
# half: piping the bundle down cycc's STDIN hits the 1 MB `input_buf` cap, and sigil's main
# bundle passed 1 MB (1,079,068 B), so the largest and most load-bearing bundle in the
# ecosystem would have started failing for a reason no consumer ever meets — consumers
# `include` the bundle, which cycc resolves from DISK with no such cap. The check therefore
# compiles through a generated one-line entry that `include`s the bundle, which is exactly
# how a consumer uses it. Do not "simplify" this back to piping the bundle to stdin.
#
# ⚠ UNDEFINED FNS ARE THE ONE EXPECTED FAILURE and are downgraded with --allow-undef (a
# bundle deliberately ships no stdlib). EVERYTHING else must stay fatal — otherwise this
# is a green placebo again, just a slower one.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: distlib_bundle_selfcheck: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }
# 6.6.11 (K5): the sidecar verify compiles for EVERY target, so the CLI needs cycc AND
# cycc_aarch64 beside it (it resolves its tools from its own directory). Stage a private tool
# dir from this tree; a staging failure means the gate could not run (77), never a FAIL.
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$D/tools" && cp "$CY" "$D/tools/cyrius" && cp "$CC" "$D/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$D/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$D/tools/cyrius" "$D/tools/cycc" "$D/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_bundle_selfcheck: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CY="$D/tools/cyrius"

mkdir -p "$D/p/src" "$D/p/dist"
cd "$D/p" || exit 2
# Unpinned manifest so the CLI uses THIS build rather than re-execing a pinned version.
printf '[package]\nname = "bp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > cyrius.cyml
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 1 — a well-formed bundle passes cleanly, with NO 'unresolved symbols' note:"
timeout 300 "$CY" distlib > "$D/o1" 2>&1
check "exit 0" 0 "$?"
check "bundle written" 1 "$([ -f dist/bp.cyr ] && echo 1 || echo 0)"
check "no 'unresolved symbols' note on a clean bundle" 0 "$(grep -c 'unresolved symbols' "$D/o1" || true)"
check "no 'cannot write output' (the /dev/null tell)" 0 "$(grep -c 'cannot write output' "$D/o1" || true)"
check "no '1MB buffer' (the stdin-cap tell)" 0 "$(grep -c '1MB buffer' "$D/o1" || true)"
# 6.6.20 (REFACTOR-11): the header's version is the manifest's [package] version — this project
# has no VERSION file, and the header read `# Version: unknown`.
check "the header stamps [package] version" 1 "$(grep -cx '# Version: 0.1.0' dist/bp.cyr || true)"
check "and the report says v0.1.0" 1 "$(grep -c 'dist/bp.cyr: [0-9]* lines (v0.1.0)' "$D/o1" || true)"

echo "axis 2 — ⭐ THE REGRESSION: a bundle that does not compile must FAIL, not reassure:"
printf 'fn a_one(): i64 { return 1; }\nfn broken( {\n' > src/a.cyr
timeout 300 "$CY" distlib > "$D/o2" 2>&1
rc2=$?
check "exit NON-zero on a broken bundle" 1 "$([ "$rc2" -ne 0 ] && echo 1 || echo 0)"
check "the bundle is NAMED in the error" 1 "$(grep -c 'does not compile' "$D/o2" || true)"
check "and it does NOT claim 'unresolved symbols'" 0 "$(grep -c 'unresolved symbols' "$D/o2" || true)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 3 — undefined fns stay EXPECTED (a bundle ships no stdlib) and do not fail:"
# Reference a stdlib symbol the bundle deliberately does not carry.
printf 'fn a_one(): i64 { return strlen("x"); }\n' > src/a.cyr
timeout 300 "$CY" distlib > "$D/o3" 2>&1
check "exit 0 despite the undefined fn" 0 "$?"
check "bundle still written" 1 "$([ -f dist/bp.cyr ] && echo 1 || echo 0)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 4 — the check leaves no temp entry behind, on success OR failure:"
timeout 300 "$CY" distlib > /dev/null 2>&1
check "no distchk entry after success" 0 "$(ls -a dist/ | grep -c 'distchk' || true)"
printf 'fn a_one(): i64 { return 1; }\nfn broken2( {\n' > src/a.cyr
timeout 300 "$CY" distlib > /dev/null 2>&1
check "no distchk entry after failure" 0 "$(ls -a dist/ | grep -c 'distchk' || true)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 5 — a bundle over cycc's 1 MB stdin cap is still checked (the sigil case):"
# Past input_buf (1,048,576) with headroom, split across TWO modules — which is both the
# real sigil shape (many modules summing past 1 MB) and a necessity: distlib enforces its
# own 1024 KB PER-MODULE read cap, so a single 1.2 MB module fails there (loudly, exit 1)
# and never reaches the self-check this axis is about. ~87 B/line, 8000 lines/module
# ~= 700 KB each ~= 1.4 MB bundled.
# ⚠ A first attempt used 12000 lines in one module and came to 1,045,977 B — 2,599 B UNDER
# the cap, so the axis proved nothing. The explicit >1 MB assertion below is what caught
# that; do not drop it and trust the line count.
i=0
: > src/big1.cyr
: > src/big2.cyr
while [ "$i" -lt 8000 ]; do
    printf 'fn big1_%d(): i64 { return %d; }  # padding padding padding padding padding padding\n' "$i" "$i" >> src/big1.cyr
    printf 'fn big2_%d(): i64 { return %d; }  # padding padding padding padding padding padding\n' "$i" "$i" >> src/big2.cyr
    i=$((i + 1))
done
printf '[package]\nname = "bp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr", "src/big1.cyr", "src/big2.cyr"]\n' > cyrius.cyml
timeout 600 "$CY" distlib > "$D/o5" 2>&1
check "exit 0 on a >1 MB bundle" 0 "$?"
check "bundle really is over 1 MB" 1 "$([ "$(wc -c < dist/bp.cyr)" -gt 1048576 ] && echo 1 || echo 0)"
check "no '1MB buffer' error" 0 "$(grep -c '1MB buffer' "$D/o5" || true)"
# ...and it is genuinely CHECKED at that size, not skipped: break it and expect a failure.
printf 'fn a_one(): i64 { return 1; }\nfn broken3( {\n' > src/a.cyr
timeout 600 "$CY" distlib > "$D/o6" 2>&1
rc6=$?
check "a broken >1 MB bundle still FAILS" 1 "$([ "$rc6" -ne 0 ] && echo 1 || echo 0)"

cd "$ROOT" || exit 2
echo ""
# ⚠ 6.6.20: the RETIRED-name axes below used to sit INSIDE the `if [ "$fails" = "0" ]` that
# prints PASS and exits 0, so their own `fails=$((fails + 1))` could never reach the verdict — a
# bundle calling `payload` that self-checked clean printed "FAIL: …" and the gate still PASSED.
# They now run unconditionally and count like every other axis.
# ── axis 6: a RETIRED stdlib name must not walk through --allow-undef (v6.6.2) ────────
# ⛔ The self-check downgrades undefined fns because a bundle omits the stdlib and the consumer
# supplies it — correct. But the downgrade was BLANKET, so a bundle calling a name the stdlib no
# longer HAS also passed and shipped. At the v6.6.0 cut `payload()` was deleted while 18 publisher
# bundles still called it; each would have self-checked GREEN and detonated at the consumer,
# inside a function the bundle's author never wrote.
# ⭐ THE DISCRIMINATOR: an undefined name the stdlib still exports is the consumer's to supply; a
# RETIRED one can never be satisfied by anyone, on any version.
mkdir -p "$D/r/src"
( cd "$D/r" && printf '[package]\nname = "rc"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/m.cyr"]\n\n[deps]\nstdlib = ["syscalls", "alloc", "tagged"]\n' > cyrius.cyml )
printf 'fn rc_uses_retired(b) { return payload(b); }\n' > "$D/r/src/m.cyr"
ROUT=$( cd "$D/r" && "$CY" distlib 2>&1 || true )
case "$ROUT" in
  *"RETIRED stdlib name"*) echo "  ok: a bundle calling the deleted 'payload' is REFUSED (1)" ;;
  *) echo "  FAIL: a bundle calling the deleted 'payload' self-checked CLEAN — the --allow-undef downgrade is still blanket"; fails=$((fails + 1)) ;;
esac

# ANTI-VACUOUS: LIVE stdlib names must still be accepted, or every real publisher breaks.
# `tagged_new` is deliberately included — it was RESTORED at v6.6.2 and must NOT read as retired.
printf 'fn rc_live(n) { return alloc(n); }\nfn rc_boxed(t, v) { return tagged_new(t, v); }\n' > "$D/r/src/m.cyr"
LOUT=$( cd "$D/r" && "$CY" distlib 2>&1 || true )
case "$LOUT" in
  *"RETIRED stdlib name"*) echo "  FAIL: a bundle of LIVE names (alloc, tagged_new) was rejected — the check is too broad"; fails=$((fails + 1)) ;;
  *) echo "  ok: a bundle of live names still passes the self-check (1)" ;;
esac

# ── axis 7: the RETIRED-name scan reads the WHOLE capture (6.6.20, CBT-02) ──────────────
# ⛔ The scan read the self-check's stderr capture into a fixed 256 KB buffer, so a bundle whose
# --allow-undef compile warned past 256 KB BEFORE reaching a retired name was written at rc 0 —
# the blast door skipped by volume. 1,400 undefined hooks with ~190-byte names come to a ~310 KB
# capture with `payload` on its last line. The same bundle with a short capture is axis 6.
echo "axis 7 — a RETIRED name past 256 KB of warnings is still refused:"
PAD=$(printf '%0190d' 0 | tr 0 x)
{
    echo 'fn rc_big(b): i64 {'
    i=0
    while [ "$i" -lt 1400 ]; do echo "    zz_hook_${PAD}_$i();"; i=$((i + 1)); done
    echo '    payload(b);'
    echo '    return 0;'
    echo '}'
} > "$D/r/src/m.cyr"
rm -rf "$D/r/dist"
BRC=0
BOUT=$( cd "$D/r" && "$CY" distlib 2>&1 ) || BRC=$?
check "exit NON-zero" 1 "$([ "$BRC" -ne 0 ] && echo 1 || echo 0)"
check "refused as a RETIRED stdlib name" 1 "$(printf '%s\n' "$BOUT" | grep -c 'RETIRED stdlib name' || true)"
check "naming payload" 1 "$(printf '%s\n' "$BOUT" | grep -c 'symbol: payload' || true)"
# ANTI-VACUOUS: the capture really is past the old buffer, with the retired name beyond it. The
# bundle the run left behind is compiled here the way the self-check compiles it (--allow-undef),
# and the byte offset of the `payload` warning is read from the compiler's own stderr.
if [ -f "$D/r/dist/rc.cyr" ]; then
    ( cd "$D/r" && printf 'include "dist/rc.cyr"\n' | "$CC" --allow-undef > /dev/null 2> "$D/cap7" ) || true
    capsz=$(wc -c < "$D/cap7" | tr -d ' ')
    payoff=$(grep -b "undefined function 'payload'" "$D/cap7" | head -1 | cut -d: -f1)
    check "the capture is over 256 KB (${capsz} B)" 1 "$([ "$capsz" -gt 262144 ] && echo 1 || echo 0)"
    check "the payload warning starts past byte 262143 (at ${payoff:-none})" 1 "$([ -n "$payoff" ] && [ "$payoff" -gt 262143 ] && echo 1 || echo 0)"
else
    check "the bundle was written for the anti-vacuous measurement" 1 0
fi

# ── axis 8: a self-check failure shows the COMPILER's diagnostic (6.6.20, CBT-03) ──────────
# The self-check captures the compiler's stderr for the RETIRED-name scan, which also silences
# compile()'s own relay — and the capture was read only for the scan, so a bundle that failed the
# self-check for any other reason printed "does not compile" and never WHY. A real bundle that
# passes the sidecar verify and fails only the self-check is hard to build on purpose, so a
# stand-in compiler fails exactly the self-check compile (--allow-undef, and not one of the
# verify's `#@incdir dist/.dlverify-*` entries) with an error line only it knows; every other
# compile is the real cycc. The CLI finds its compiler beside itself.
echo "axis 8 — a bundle that fails the self-check shows the compiler's own error:"
mkdir -p "$D/shim" "$D/s/src"
cp "$D/tools/cyrius" "$D/shim/cyrius" && cp "$CC" "$D/shim/cycc.real" && cp "$D/tools/cycc_aarch64" "$D/shim/cycc_aarch64"
cat > "$D/shim/cycc" <<'SHIM'
#!/bin/sh
D=$(dirname "$0")
T=$(mktemp) || exit 99
cat > "$T"
selfcheck=0
case " $* " in *" --allow-undef "*) grep -q '^#@incdir dist/.dlverify' "$T" || selfcheck=1 ;; esac
if [ "$selfcheck" = 1 ]; then
    rm -f "$T"
    echo 'error:<source>:1:1: SYNTHETIC self-check failure only the compiler can name' >&2
    exit 1
fi
"$D/cycc.real" "$@" < "$T"; rc=$?
rm -f "$T"; exit $rc
SHIM
chmod +x "$D/shim/cyrius" "$D/shim/cycc" "$D/shim/cycc.real" "$D/shim/cycc_aarch64"
printf '[package]\nname = "sc"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$D/s/cyrius.cyml"
printf 'fn sc_one(): i64 { return 1; }\n' > "$D/s/src/a.cyr"
SRC=0
SOUT=$( cd "$D/s" && timeout 300 "$D/shim/cyrius" distlib 2>&1 ) || SRC=$?
check "exit NON-zero" 1 "$([ "$SRC" -ne 0 ] && echo 1 || echo 0)"
check "it says the bundle does not compile" 1 "$(printf '%s\n' "$SOUT" | grep -c 'the generated bundle does not compile' || true)"
check "and relays the compiler's own error line" 1 "$(printf '%s\n' "$SOUT" | grep -c 'SYNTHETIC self-check failure only the compiler can name' || true)"

# ── axis 9: where the `# Version:` header comes from (6.6.20, REFACTOR-11) ─────────────────
# `[package] version` (with `${file:PATH}` expanded — the reader `#@pkgver` uses) wins; a manifest
# with no version falls back to ./VERSION. distlib read ./VERSION alone, so axis 1's project (a
# literal version, no VERSION file) shipped `# Version: unknown`.
echo "axis 9 — the bundle's # Version: is the manifest's [package] version:"
mkdir -p "$D/v/src"
printf 'fn vv_one(): i64 { return 1; }\n' > "$D/v/src/a.cyr"
vhdr() { ( cd "$D/v" && rm -rf dist && timeout 300 "$CY" distlib > "$D/ov" 2>&1 ); sed -n 's/^# Version: //p' "$D/v/dist/vv.cyr" 2>/dev/null | head -1; }
printf '[package]\nname = "vv"\nversion = "${file:VERSION}"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$D/v/cyrius.cyml"
printf '2.3.4\n' > "$D/v/VERSION"
check "version = \"\${file:VERSION}\" stamps VERSION's contents" "2.3.4" "$(vhdr)"
printf '[package]\nname = "vv"\nversion = "7.0.1"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$D/v/cyrius.cyml"
check "a literal [package] version wins over a VERSION file that disagrees" "7.0.1" "$(vhdr)"
printf '[package]\nname = "vv"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$D/v/cyrius.cyml"
check "no [package] version: ./VERSION, as before" "2.3.4" "$(vhdr)"

if [ "$fails" = "0" ]; then
    echo "PASS: distlib-bundle-selfcheck — the bundle is really compiled; broken bundles are fatal"
    exit 0
fi
echo "FAIL: distlib-bundle-selfcheck — $fails assertion(s) failed"
exit 1
