#!/bin/sh
# Gate: `cyrius build <foreign-src>` refuses to overwrite the compiler it is running.
#
# ⛔ THE INCIDENT (v6.6.0 cut). In the cyrius repo `cyrius.cyml` declares `output = build/cycc` —
# correct, that IS how the compiler is built — and the documented argument ladder says one
# positional argument means "that src + the manifest's output". So
# `cyrius build tests/tcyr/.../foo.tcyr` compiled the TEST and wrote an 842 KB test binary over
# `build/cycc`, replacing the compiler. It was recoverable only because a verified stage binary
# happened to still be sitting in /tmp; from a clean tree it costs a full bootstrap.
#
# ⭐ THE LADDER IS RIGHT AND DOCUMENTED, so the guard is narrower than changing it. Exactly one
# combination is destructive: an EXPLICIT FOREIGN SRC plus an INHERITED output that resolves to
# the running compiler. Building the manifest's own declared entry still writes it — that is the
# entire point of the key — and an explicit output is always honoured.
#
# ⛔ THIS GATE MUST NEVER POINT AT THE REAL `build/cycc`, or the gate IS the destructive act.
# The roadmap entry for this slot says so explicitly. Everything below happens in a temp tree with
# a FAKE compiler binary, and the axis that proves the guard fires checks that the fake survives.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0
[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }

# A scratch project whose [build] output is a binary we will pretend is the compiler.
mkdir -p "$D/p/src" "$D/p/build"
cd "$D/p"
printf '[package]\nname = "ovw"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/ovw"\n' > cyrius.cyml
printf 'fn main(): i64 { return 7; }\nvar r = main();\n' > src/main.cyr
printf 'fn other(): i64 { return 9; }\nvar r2 = other();\n' > src/other.cyr

# ── axis 1: the DECLARED ENTRY still builds to the manifest output ──────────────────────
# The guard must not break the legitimate one-argument form, which is what the key is for.
set +e
OUT1=$( "$CY" build 2>&1 ); RC1=$?
set -e
if [ "$RC1" -eq 0 ] && [ -f build/ovw ]; then
    echo "  ok: the declared entry still builds to the manifest output (1)"
else
    echo "  FAIL: a plain \`cyrius build\` of the declared entry was refused (rc $RC1): $OUT1"
    fails=$((fails + 1))
fi

# ── axis 2: an EXPLICIT output is always honoured, even for a foreign source ────────────
set +e
OUT2=$( "$CY" build src/other.cyr build/explicit 2>&1 ); RC2=$?
set -e
if [ "$RC2" -eq 0 ] && [ -f build/explicit ]; then
    echo "  ok: a foreign source with an EXPLICIT output is allowed (1)"
else
    echo "  FAIL: an explicit-output build was refused (rc $RC2): $OUT2"
    fails=$((fails + 1))
fi

# ── axis 3: THE DESTRUCTIVE COMBINATION — foreign src + inherited output = the compiler ──
# Simulated by making the manifest's output BE the cyrius binary this build is running, so the
# guard's `current_cc()` comparison has something to match without touching the real toolchain.
mkdir -p "$D/q/src" "$D/q/build"
cd "$D/q"
cp "$ROOT/build/cycc" "$D/q/build/cycc"
SENTINEL=$(sha256sum "$D/q/build/cycc" | awk '{print $1}')
printf '[package]\nname = "ovw2"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/cycc"\n' > cyrius.cyml
printf 'fn main(): i64 { return 7; }\nvar r = main();\n' > src/main.cyr
printf 'fn foreign(): i64 { return 3; }\nvar rf = foreign();\n' > src/foreign.cyr
set +e
OUT3=$( CYCC_BIN="$D/q/build/cycc" "$CY" build src/foreign.cyr 2>&1 ); RC3=$?
set -e
AFTER=$(sha256sum "$D/q/build/cycc" | awk '{print $1}')
case "$OUT3" in
  *"refusing to overwrite the running compiler"*)
      echo "  ok: foreign src + inherited compiler output is REFUSED (1)" ;;
  *)
      echo "  FAIL: the destructive combination was ALLOWED (rc $RC3): $OUT3"
      fails=$((fails + 1)) ;;
esac
# ⚠ The refusal must happen BEFORE anything is written, not after.
if [ "$SENTINEL" = "$AFTER" ]; then
    echo "  ok: the target binary was not touched (1)"
else
    echo "  FAIL: the compiler binary was OVERWRITTEN despite the refusal"
    fails=$((fails + 1))
fi

# ── axis 4 (ANTI-VACUOUS): the guard must not refuse EVERYTHING ─────────────────────────
# A guard that returned 1 unconditionally would pass axis 3 and break every build on the machine;
# axes 1 and 2 already cover that, and this asserts the message is specific rather than generic.
case "$OUT3" in
  *"src/foreign.cyr"*) echo "  ok: the refusal names the offending source (1)" ;;
  *) echo "  FAIL: the refusal does not name the source it refused"; fails=$((fails + 1)) ;;
esac

cd "$ROOT"
if [ "$fails" -eq 0 ]; then
    echo "PASS: build_refuses_compiler_overwrite (declared entry builds, explicit output allowed, foreign+inherited refused before writing)"
    exit 0
fi
echo "FAIL: build_refuses_compiler_overwrite — $fails assertion(s) failed"
exit 1
