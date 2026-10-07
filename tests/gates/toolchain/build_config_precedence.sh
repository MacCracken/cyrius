#!/bin/sh
# build_config_precedence.sh — 6.6.17 (P1 item 1). `[build] dce` and `defines` are read, each
# resolves argument > environment > manifest > default, and what the compiler RECEIVES is the
# resolved value. `[build] strict` is HELD (cycc --strict has had no effect since 6.3.2): warned,
# not read, no environment channel; `--strict` passes through. `[build] target` (held),
# `[build] features` (dropped) and an unknown `[build]` key are warned by name; the declared
# synonym `src` is not.
#
# WHY: `[build] defines` was declared by 3 manifests (ark, sakshi, sigil) and read by nothing —
# their CI lines repeat it as `-D`; DCE was set by env on ~200 CI lines across 57 repos with no
# manifest key. Each key is checked at every rung, and the effect is observed where it lands: a
# STUB compiler (a shell script standing in for cycc) records the argv and the CYRIUS_DCE it was
# handed and then runs the real cycc, and the built program's exit code encodes which defines
# reached it.
#
# ROWS, per read key: default; manifest beats default; environment beats manifest; argument beats
# environment. CYRIUS_DCE: empty = unset, 0 / 1 accepted, anything else refused by name. Plus: a
# mistyped value is refused by name and builds nothing; a define holding a newline is refused (it
# would start a new source line in the compiled unit); held / dropped / unknown keys warn by name
# and the build still succeeds; the consumer manifests that DECLARE defines (ark, sigil —
# verbatim fixtures) now resolve them.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build_config_precedence: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: build_config_precedence: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: build_config_precedence: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/stub/bin"
cat > "$W/stub/bin/cycc" <<STUB
#!/bin/sh
{ printf 'argv:'; for a in "\$@"; do printf ' %s' "\$a"; done; printf '\ndce:%s\n' "\${CYRIUS_DCE-unset}"; } > "$W/stub.log"
tr '\\0' '\\n' < /proc/\$\$/environ > "$W/stub.env" 2>/dev/null || true
exec "$CC" "\$@"
STUB
chmod +x "$W/stub/bin/cycc"

mkdir -p "$W/p/src"
cat > "$W/p/src/main.cyr" <<'CYR'
var code = 0;
#ifdef ALPHA
code = code + 1;
#endif
#ifdef BETA
code = code + 2;
#endif
#ifdef GAMMA
code = code + 4;
#endif
fn dead_one(): i64 { return 7; }
syscall(60, code);
CYR
# mk <extra [build] lines> — the fixture manifest
mk() { printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p"\n%b' "$1" > "$W/p/cyrius.cyml"; }
# bld <env assignments...> -- <cli args...> : build through the stub; sets RC, EXIT (program), ARGV, DCE
bld() {
    envs=""; while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs="$envs $1"; shift; done; [ "$#" -gt 0 ] && shift
    rm -f "$W/p/build/p" "$W/stub.log"
    RC=0
    ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT -u CYRIUS_DEFINES $envs CYRIUS_HOME="$W/stub" CYRIUS_RESOLVED=1 "$W/cyrius" build "$@" ) > "$W/out" 2>&1 || RC=$?
    EXIT=none; [ -x "$W/p/build/p" ] && { EXIT=0; "$W/p/build/p" || EXIT=$?; }
    ARGV=""; DCE=""
    if [ -f "$W/stub.log" ]; then ARGV=$(sed -n 's/^argv://p' "$W/stub.log"); DCE=$(sed -n 's/^dce://p' "$W/stub.log"); fi
}
pcfg() { ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT -u CYRIUS_DEFINES "$@" CYRIUS_HOME="$W/stub" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config ) 2>&1; }
want() {  # want <row> <got> <expected>
    [ "$2" = "$3" ] || { fail "$1: got '$2', expected '$3'"; sed 's/^/      /' "$W/out" | head -4; }
}
has_strict() { case " $ARGV " in *" --strict "*) echo yes ;; *) echo no ;; esac; }

# ── dce ─────────────────────────────────────────────────────────────────────────────────
x=$FAIL
mk ''; bld --; want "dce default" "$DCE" unset
mk 'dce = true\n'; bld --; want "dce manifest" "$DCE" 1
grep -q 'dead code eliminated' "$W/out" || fail "dce manifest: the compiler did not eliminate (no 'dead code eliminated' note)"
mk 'dce = true\n'; bld CYRIUS_DCE=0 --; want "dce environment beats manifest" "$DCE" 0
mk 'dce = true\n'; bld CYRIUS_DCE=0 -- --dce; want "dce argument beats environment (the inherited 0 is REPLACED)" "$DCE" 1
pcfg CYRIUS_DCE=0 > "$W/pc"; grep -qF '  build.dce = false  (environment: CYRIUS_DCE)' "$W/pc" || fail "dce: --print-config does not report the environment rung"
[ "$FAIL" = "$x" ] && echo "  ok dce: default unset -> manifest 1 (eliminated) -> CYRIUS_DCE=0 wins -> --dce wins over it"

# ── strict: HELD (cycc --strict has had no effect since 6.3.2) ──────────────────────────
# The manifest key is warned and NOT read, there is no environment channel, and the argument is
# still accepted and passed through (back-compat) — an inert key must not look like a setting.
x=$FAIL
mk ''; bld --; want "strict default" "$(has_strict)" no
mk 'strict = true\n'; bld --; want "strict manifest is not read" "$(has_strict)" no
grep -q 'warn: cyrius.cyml \[build\] strict is HELD and not read: has had no effect since 6.3.2' "$W/out" || fail "a manifest strict was not warned by name"
mk ''; bld CYRIUS_STRICT=1 --; want "CYRIUS_STRICT is not a channel" "$(has_strict)" no
mk ''; bld -- --strict; want "strict argument passed through" "$(has_strict)" yes
[ "$FAIL" = "$x" ] && echo "  ok strict: held — [build] strict warned and unread, CYRIUS_STRICT ignored, --strict passed through"

# ── environment values ──────────────────────────────────────────────────────────────────
x=$FAIL
mk 'dce = true\n'; bld CYRIUS_DCE= --; want "an EMPTY CYRIUS_DCE is unset (the manifest's true stands)" "$DCE" 1
mk ''; bld CYRIUS_DCE=true --
[ "$RC" -ne 0 ] && grep -q 'CYRIUS_DCE must be 0 or 1 (or unset): true' "$W/out" && [ "$EXIT" = none ] || fail "CYRIUS_DCE=true was not refused by name (rc $RC, built: $EXIT)"
[ "$FAIL" = "$x" ] && echo "  ok environment: CYRIUS_DCE empty = unset, 0/1 accepted, 'true' refused by name"

# ── defines ─────────────────────────────────────────────────────────────────────────────
x=$FAIL
mk ''; bld --; want "defines default (exit code = the defines that arrived)" "$EXIT" 0
mk 'defines = ["ALPHA"]\n'; bld --; want "defines manifest" "$EXIT" 1
mk 'defines = ["ALPHA"]\n'; bld CYRIUS_DEFINES=BETA --; want "defines environment beats manifest" "$EXIT" 2
mk 'defines = ["ALPHA"]\n'; bld CYRIUS_DEFINES=BETA -- -D GAMMA; want "defines argument beats environment" "$EXIT" 4
mk "defines = ['ALPHA', \"BETA\"]\n"; bld --; want "defines: a literal and a basic string" "$EXIT" 3
[ "$FAIL" = "$x" ] && echo "  ok defines: none -> manifest ALPHA -> CYRIUS_DEFINES=BETA wins -> -D GAMMA wins over it (by the program's exit code)"

# ── defines reach `cyrius fuzz` harnesses too (6.6.18; P1: defines apply to every build) ──
# Before, only `-D` reached a harness — `[build] defines` and CYRIUS_DEFINES were read by
# `cyrius build` alone. Same precedence as the build: -D > CYRIUS_DEFINES > manifest.
x=$FAIL
mkdir -p "$W/p/fuzz"
printf 'var code = 9;\n#ifdef ALPHA\ncode = 0;\n#endif\nsyscall(60, code);\n' > "$W/p/fuzz/f.fcyr"
fz() { ( cd "$W/p" && env -u CYRIUS_DEFINES CYRIUS_HOME="$W/stub" CYRIUS_RESOLVED=1 "$@" ) > "$W/fz.out" 2>&1 || true; }
mk 'defines = ["ALPHA"]\n'
fz "$W/cyrius" fuzz
grep -qE '^  fuzz/f\.fcyr +PASS$' "$W/fz.out" || fail "fuzz: [build] defines = [\"ALPHA\"] did not reach the harness: $(grep 'f\.fcyr' "$W/fz.out")"
fz env CYRIUS_DEFINES=BETA "$W/cyrius" fuzz
grep -qE '^  fuzz/f\.fcyr +FAIL$' "$W/fz.out" || fail "fuzz: CYRIUS_DEFINES=BETA did not replace the manifest's ALPHA: $(grep 'f\.fcyr' "$W/fz.out")"
fz env CYRIUS_DEFINES=BETA "$W/cyrius" fuzz -D ALPHA
grep -qE '^  fuzz/f\.fcyr +PASS$' "$W/fz.out" || fail "fuzz: -D ALPHA did not win over CYRIUS_DEFINES: $(grep 'f\.fcyr' "$W/fz.out")"
rm -rf "$W/p/fuzz"
[ "$FAIL" = "$x" ] && echo "  ok fuzz: [build] defines reach every harness; CYRIUS_DEFINES replaces them; -D wins"

# ── the CLI's own entries beat inherited ones, at any environment size (6.6.20) ──────────
# compile() APPENDED what it injects after the inherited environment, and cycc takes the FIRST
# entry of a name and (Linux `_read_env`) reads only the first 8191 bytes. So an inherited
# CYRIUS_TARGET_WIN=0 / CYRIUS_PIE=0 / CYRIUS_STRICT_PIN=0 / CYRIUS_TARGET_AGNOS=0 beat the
# argument, an inherited CYRIUS_MACHO=1 turned `--win` into a Mach-O named .exe, and past 8 KiB of
# environment every injected entry was invisible (`--win` gave an ELF, `--dce` eliminated nothing,
# a bare-metal target came out ELF32) — rc 0 every time. These rows run the REAL compiler: the
# stub's `sh` re-exports its environment, which collapses duplicate names and reorders entries,
# i.e. it would hide exactly this. The stub row at the end checks the envp itself.
x=$FAIL
mkdir -p "$W/real/bin"; ln -s "$CC" "$W/real/bin/cycc"
PAD="PAD=$(head -c 9000 /dev/zero | tr '\0' x)"
printf 'kernel;\nvar k = 1;\n' > "$W/p/src/k.cyr"
rb() {  # rb <env assignments...> -- <cli args...> : build with the REAL compiler; sets RC
    envs=""; while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs="$envs $1"; shift; done; [ "$#" -gt 0 ] && shift
    rm -f "$W/p/o.bin"
    RC=0
    ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT -u CYRIUS_DEFINES -u CYRIUS_TARGET_WIN -u CYRIUS_TARGET_EFI \
        -u CYRIUS_TARGET_AGNOS -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM -u CYRIUS_PIE -u CYRIUS_STRICT_PIN \
        -u CYRIUS_KERNEL -u CYRIUS_ELF64_KERNEL $envs CYRIUS_HOME="$W/real" CYRIUS_RESOLVED=1 "$W/cyrius" build "$@" ) > "$W/out" 2>&1 || RC=$?
}
magic() { od -An -tx1 -N4 "$W/p/o.bin" 2>/dev/null | tr -d ' \n'; }
mk ''
rb CYRIUS_TARGET_WIN=0 -- --win src/main.cyr o.bin; want "--win beats an inherited CYRIUS_TARGET_WIN=0 (MZ)" "$(magic | cut -c1-4)" 4d5a
rb CYRIUS_MACHO=1 -- --win src/main.cyr o.bin; want "--win drops an inherited CYRIUS_MACHO=1 (MZ, not Mach-O)" "$(magic | cut -c1-4)" 4d5a
rb "$PAD" -- --win src/main.cyr o.bin; want "--win past 8 KiB of environment (MZ)" "$(magic | cut -c1-4)" 4d5a
rb CYRIUS_PIE=0 -- --pie src/main.cyr o.bin; want "--pie beats an inherited CYRIUS_PIE=0 (e_type ET_DYN)" "$(od -An -tu2 -j16 -N2 "$W/p/o.bin" 2>/dev/null | tr -d ' ')" 3
rb -- --agnos src/main.cyr o.bin; cp "$W/p/o.bin" "$W/agnos.bin" 2>/dev/null
rb -- src/main.cyr o.bin; cp "$W/p/o.bin" "$W/plain.bin" 2>/dev/null
cmp -s "$W/agnos.bin" "$W/plain.bin" && fail "--agnos: the agnos build equals the Linux build (the row cannot tell them apart)"
rb CYRIUS_TARGET_AGNOS=0 -- --agnos src/main.cyr o.bin
cmp -s "$W/p/o.bin" "$W/agnos.bin" || fail "--agnos does not beat an inherited CYRIUS_TARGET_AGNOS=0 (output is not the agnos build)"
mk 'dce = false\n'
rb "$PAD" -- --dce src/main.cyr o.bin
grep -q 'dead code eliminated' "$W/out" || fail "--dce past 8 KiB of environment: the compiler did not eliminate: $(grep 'unreachable' "$W/out" | head -1)"
mk ''
rb "$PAD" -- --target x86_64-bare-metal-elf src/k.cyr o.bin
want "a bare-metal target past 8 KiB of environment is ELF64 (EI_CLASS 2)" "$(od -An -tu1 -j4 -N1 "$W/p/o.bin" 2>/dev/null | tr -d ' ')" 2
printf '[package]\nname = "p"\ncyrius = "6.6.1"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p"\n' > "$W/p/cyrius.cyml"
rb -- src/main.cyr o.bin
[ "$RC" = 0 ] && grep -q 'drift' "$W/out" || fail "strict-pin control: a drifted pin without --strict-pin should warn and build (rc $RC)"
rb CYRIUS_STRICT_PIN=0 -- --strict-pin src/main.cyr o.bin
[ "$RC" -ne 0 ] && grep -q 'drift' "$W/out" || fail "--strict-pin does not beat an inherited CYRIUS_STRICT_PIN=0: a drifted pin built (rc $RC)"
# What the compiler RECEIVES: the injected entry FIRST, and the inherited one of the same name gone.
mk ''; bld CYRIUS_PIE=0 -- --pie
want "the child's first environment entry is the injected CYRIUS_PIE=1" "$(head -1 "$W/stub.env" 2>/dev/null)" CYRIUS_PIE=1
want "the inherited CYRIUS_PIE=0 is dropped (one CYRIUS_PIE entry)" "$(grep -c '^CYRIUS_PIE=' "$W/stub.env" 2>/dev/null)" 1
[ "$FAIL" = "$x" ] && echo "  ok injected entries: --win / --pie / --agnos / --strict-pin beat an inherited =0, --win drops CYRIUS_MACHO=1, and --win / --dce / bare metal hold past 8 KiB of environment (the injected entry is FIRST, the inherited same-name one dropped)"

# ── refusals ────────────────────────────────────────────────────────────────────────────
x=$FAIL
mk 'dce = "yes"\n'; bld --
[ "$RC" -ne 0 ] && grep -q '\[build\] dce must be true or false' "$W/out" && [ "$EXIT" = none ] || fail "a mistyped dce was not refused by name (rc $RC, built: $EXIT)"
mk 'defines = ["A\\nB"]\n'; bld --
[ "$RC" -ne 0 ] && grep -q 'control character' "$W/out" && [ "$EXIT" = none ] || fail "a define holding a newline was not refused (rc $RC, built: $EXIT)"
[ "$FAIL" = "$x" ] && echo "  ok refusals: dce = \"yes\" and a define holding a newline are refused by name; nothing built"

# ── held / dropped / unknown ────────────────────────────────────────────────────────────
x=$FAIL
mk 'target = "aarch64"\nfeatures = ["gpu"]\noutptu = "build/typo"\n'; bld --
[ "$RC" = 0 ] && [ "$EXIT" = 0 ] || fail "held/dropped/unknown keys broke the build (rc $RC)"
grep -q 'warn: cyrius.cyml \[build\] target is HELD' "$W/out" || fail "a held [build] target was not warned by name"
grep -q 'warn: cyrius.cyml \[build\] features is DROPPED' "$W/out" || fail "a dropped [build] features was not warned by name"
grep -q 'warn: cyrius.cyml \[build\] outptu is not a known key' "$W/out" || fail "an unknown [build] key was not warned by name"
mk 'dce = false\ndefines = []\ntest = "src/main.cyr"\nmodules = []\n'; bld --
grep -q 'warn:' "$W/out" && fail "a manifest of known keys warned: $(grep 'warn:' "$W/out" | head -1)"
# the declared synonym: `src` for `entry` (cyrius itself, hisab, prakash, cyrius-doom ... write it)
printf '[package]\nname = "p"\n\n[build]\nsrc = "src/main.cyr"\noutput = "build/p"\n' > "$W/p/cyrius.cyml"; bld --
[ "$EXIT" = 0 ] || fail "[build] src did not build (rc $RC)"
grep -q 'warn:' "$W/out" && fail "the declared synonym src warned: $(grep 'warn:' "$W/out" | head -1)"
[ "$FAIL" = "$x" ] && echo "  ok warnings: held target, dropped features and a typo'd key are named; known keys and the src synonym are not"

# ── what consumers declared ─────────────────────────────────────────────────────────────
x=$FAIL
for c in ark sigil; do
    mkdir -p "$W/c/$c"; cp "tests/fixtures/manifest/consumers/$c.cyml" "$W/c/$c/cyrius.cyml"
    d=$(awk '/^---/ { exit } /^\[/ { b = ($0 ~ /^\[build\]/) } b && /^defines *=/ { sub(/^[^"]*"/, ""); sub(/".*/, ""); print; exit }' "$W/c/$c/cyrius.cyml")
    [ -n "$d" ] || { fail "$c: the fixture parse found no defines"; continue; }
    ( cd "$W/c/$c" && env -u CYRIUS_DEFINES CYRIUS_HOME="$W/stub" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config ) > "$W/c/$c.out" 2>&1
    grep -qF "  build.defines = [\"$d\"]  (manifest: [build] defines)" "$W/c/$c.out" || fail "$c: [build] defines = [\"$d\"] did not resolve"
done
[ "$FAIL" = "$x" ] && echo "  ok consumers: ark's and sigil's [build] defines (verbatim) resolve from the manifest"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: build_config_precedence (dce / defines at every rung, for build and fuzz; strict held; refusals; held, dropped, unknown keys)"
