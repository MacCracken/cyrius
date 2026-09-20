#!/bin/sh
# build_temp_source_write_checked.sh — v6.6.6 (bite 26b). The PREPROCESSED SOURCE cycc
# actually compiles is written to completion, or the build FAILS BY NAME. A short write, a
# read error, or a `[build].modules` entry that cannot be opened must never yield a quiet
# `OK` over a file nobody wrote.
#
# ⛔ THE DEFECT (reproduced at 67ea9c17). `_materialize_source` (cbt/build.cyr) builds
# <tmpdir>/cpp_<pid> — the `#@incdir`/`#@pkgver` markers, the manifest's include lines, the
# `-D` defines, every `[build].modules` file, then the entry source — with bare
# `sys_write` / `syscall(1, …)` calls whose results were DISCARDED. Measured on a 4.8 MB
# source under RLIMIT_FSIZE (`ulimit -f 200`):
#     compile src/app.cyr -> out [x86_64] OK (4448 bytes)    exit 0    ./out -> 0
# The copy stopped at the limit, which cut the file's LAST line — `fn main()` — so the
# build SUCCEEDED and produced a program returning 0 where the source says 42. Not a
# visibly truncated artifact: a successful build of something the user never wrote. Two
# more doors to the same wrong translation unit were open beside it: a temp that could not
# be CREATED fell through to "compile the entry file with every prepend silently dropped",
# and a `[build].modules` entry that could not be OPENED was skipped in silence.
#
# ⚠ HOW A FULL DISK IS REPRODUCED WITHOUT A MOUNT (the recipe tool_writes_never_truncate.sh
# documents): RLIMIT_FSIZE with SIGXFSZ ignored — a shell `trap ''` survives exec — gives
# the writer a full disk's exact sequence, a SHORT write then EFBIG. `ulimit -f` counts
# 512-byte blocks under /bin/sh-as-bash (POSIX mode) and 1024-byte blocks under bash
# proper, so the fixture is sized to straddle 200 blocks under BOTH units: the source is
# ~1.2 MB (far above 204,800) and the output binary is a few KB (far below 102,400). The
# limit therefore bites the temp source and NOT the compiler's output — which is the whole
# point, since a limit that truncates both proves nothing about which write was unchecked.
#
# AXES
#   1. ANTI-VACUOUS. Unconstrained, the same fixture builds and the binary exits 42, and
#      the fixture is shown to actually need the temp (its `fn main` is the LAST line, so
#      any short copy loses it, and the source sits in a subdirectory, which is what makes
#      `_materialize_source` allocate a temp at all).
#   2. Under 200 blocks the build exits NON-ZERO, names the preprocessed source it could
#      not write, never prints `OK (`, and leaves NO output binary. Every expected value is
#      read a different way from the CLI's own report: the exit status, the presence of the
#      file on disk, and the binary's own exit code.
#   3. `[build].modules` — with the module present the build succeeds AND the module's fn
#      is really linked (the binary returns the module's value, so the axis cannot pass
#      against a build that ignored the manifest); with the module missing, and with the
#      module unreadable, the build exits non-zero and NAMES the module.
#   4. STATIC, over cbt/: nothing writes a temp SOURCE with an unchecked call any more.
#      `sys_write(tfd, …)` / `syscall(1, tfd, …)` in cbt/build.cyr and the doctest's
#      `syscall(1, fd, code, …)` in cbt/quality.cyr must be gone, the checked helpers must
#      be present with a derived floor of call sites, and the detector is self-tested on
#      both the forbidden and the accepted shapes so it cannot pass by matching nothing.
#
# ⚠ WHAT THIS GATE DOES NOT COVER, stated rather than implied: the doctest half is pinned
# STATICALLY only (axis 4). A dynamic proof there is not available with RLIMIT_FSIZE —
# a doc example is capped at 8 KB (`_DT_CODE_CAP`), so any limit small enough to truncate
# it also truncates the compiler's output, and the doctest then fails for the wrong reason
# both before and after the fix. It is pinned by reverting the writer in a scratch tree.
#
# MUTATION LEDGER (measured 6.6.6, each in a scratch copy of the tree, CLI rebuilt):
#   a. cbt/build.cyr `_materialize_source` as of 67ea9c17 (bare  -> axis 2 FAIL (rc 0, `OK (4448
#      sys_write / syscall(1, …), silent `tfd < 0` and             bytes)`, binary exits 0 not 42)
#      `mfd < 0` fall-throughs)                                    + axis 3 FAIL (missing module
#                                                                  silently dropped, rc 0)
#                                                                  + axis 4 FAIL (4 unchecked keys)
#   b. `_mat_write` reduced to ONE unchecked `sys_write`        -> axis 2 FAIL (rc 0, `OK`, binary
#      (the defect's essence, reached through the helper)          exits 0 not 42) — the STATIC
#                                                                  axis passes it, which is why
#                                                                  axis 2 has to run the binary
#   c. the temp-creation refusal removed (the `else` on the    -> axis 4 FAIL (the refusal is
#      `tfd >= 0` block), silently falling back to the raw source   part of the checked shape)
#   d. the `[build].modules` refusal removed only               -> axis 3 FAIL (missing + unreadable
#                                                                  module both rc 0)
#   e. cbt/quality.cyr's doctest writer back to the bare        -> axis 4 FAIL (quality.cyr|code)
#      `syscall(1, fd, code, code_len)`
#   f. the axis-4 detector's forbidden-shape arm disabled       -> axis 4 self-test FAIL
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: build_temp_source_write_checked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }
ulimit -c 0 2>/dev/null

# ── build the CLI from the tree, with cycc as its SIBLING ────────────────────
# `find_tools()` prefers the cycc sitting beside the wrapper (v6.5.42), so this pair is
# self-contained and nothing resolves out of the live store.
mkdir -p "$D/bin"
"$CC" < cbt/cyrius.cyr > "$D/bin/cyrius" 2> "$D/cli.err" && [ -s "$D/bin/cyrius" ] \
  || { echo "FAIL: cbt/cyrius.cyr does not build:"; tail -3 "$D/cli.err" | sed 's/^/      /'; exit 1; }
cp "$CC" "$D/bin/cycc" && chmod +x "$D/bin/cyrius" "$D/bin/cycc" \
  || { echo "FAIL: cannot stage $D/bin"; exit 1; }
CLI="$D/bin/cyrius"
mkdir -p "$D/home/.cyrius"
_run() { ( cd "$D/p" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" exec "$CLI" "$@" ); }
_lim() { ( cd "$D/p" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" && trap '' XFSZ && ulimit -f 200 && exec "$CLI" "$@" ); }

# ── the fixture: a big source in a SUBDIRECTORY, `fn main` on the last line ──
mkdir -p "$D/p/src"
{ yes '# filler ------------------------------------------------------------------' | head -n 15000
  printf 'fn main(): i64 { return 42; }\n'; } > "$D/p/src/app.cyr"
SRCB=$(wc -c < "$D/p/src/app.cyr" | tr -d ' ')
[ "$SRCB" -gt 204800 ] || { echo "FAIL: the fixture is $SRCB bytes — it must exceed 200 blocks in BOTH ulimit units (204800)"; exit 1; }
[ "$(tail -1 "$D/p/src/app.cyr")" = 'fn main(): i64 { return 42; }' ] \
  || { echo "FAIL: the fixture's last line is not fn main — a short copy would not lose it"; exit 1; }

# ── axis 1: anti-vacuous — unconstrained it builds and the binary exits 42 ───
a1=0
rc=0; _run build src/app.cyr out1 > "$D/a1.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { fail "axis 1: the fixture does not build unconstrained (rc=$rc):"; tail -3 "$D/a1.out" | sed 's/^/      /'; a1=1; }
[ -s "$D/p/out1" ] || { fail "axis 1: no output binary was produced"; a1=1; }
erc=0; ( ulimit -c 0; exec "$D/p/out1" ) >/dev/null 2>&1 || erc=$?
[ "$erc" -eq 42 ] || { fail "axis 1: the binary exits $erc, expected 42 — the fixture's main did not make it into the build"; a1=1; }
OUTB=$(wc -c < "$D/p/out1" 2>/dev/null || echo 0)
[ "$OUTB" -gt 0 ] && [ "$OUTB" -lt 102400 ] \
  || { fail "axis 1: the output is $OUTB bytes — it must stay under 200 blocks in BOTH units (102400) so the limit in axis 2 bites the SOURCE, not the compiler's output"; a1=1; }
[ "$a1" = 0 ] && echo "  ok: axis 1: unconstrained, a ${SRCB}-byte source in a subdirectory builds to a ${OUTB}-byte binary that exits 42"

# ── axis 2: a short write is a NAMED failure, not a quiet OK over a wrong file ─
a2=0
rm -f "$D/p/out2"
rc=0; _lim build src/app.cyr out2 > "$D/a2.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 2: a SHORT write of the preprocessed source was reported as SUCCESS (rc 0):"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
grep -q 'could not write the preprocessed source' "$D/a2.out" \
  || { fail "axis 2: the failure does not say the preprocessed source could not be written:"; sed 's/^/      /' "$D/a2.out" | head -3; a2=1; }
grep -q 'OK (' "$D/a2.out" && { fail "axis 2: the build printed OK for a compile it could not feed"; a2=1; }
if [ -e "$D/p/out2" ]; then
    erc=0; ( ulimit -c 0; exec "$D/p/out2" ) >/dev/null 2>&1 || erc=$?
    fail "axis 2: a binary was produced from a truncated source (it exits $erc; the source says 42)"; a2=1
fi
[ "$a2" = 0 ] && echo "  ok: axis 2: under RLIMIT_FSIZE (200 blocks) the build exits $rc, names the preprocessed source, and leaves no binary"

# ── axis 3: [build].modules — present and linked / missing / unreadable ──────
# `[build].modules` is only read when the manifest also carries a [deps] section, so the
# fixture stages a stdlib under the throwaway CYRIUS_HOME (branch (c) of
# _dep_find_stdlib_dir: $CYRIUS_HOME/lib).
a3=0
mkdir -p "$D/home/.cyrius/lib"
cp lib/*.cyr "$D/home/.cyrius/lib/" 2>/dev/null
[ -f "$D/home/.cyrius/lib/syscalls.cyr" ] || { echo "FAIL: axis 3: cannot stage a stdlib into the throwaway home"; exit 1; }
mkdir -p "$D/p/mod"
printf 'fn bite26_from_module(): i64 { return 23; }\n' > "$D/p/mod/m.cyr"
printf 'fn main(): i64 { return bite26_from_module(); }\n' > "$D/p/app2.cyr"
_manifest() { printf '[package]\nname = "p"\nversion = "0.1.0"\n\n[deps]\nstdlib = []\n\n[build]\nmodules = ["%s"]\n' "$1" > "$D/p/cyrius.cyml"; }
_manifest 'mod/m.cyr'
rc=0; _run build app2.cyr outm > "$D/a3a.out" 2>&1 || rc=$?
erc=0; [ -s "$D/p/outm" ] && { ( ulimit -c 0; exec "$D/p/outm" ) >/dev/null 2>&1 || erc=$?; }
{ [ "$rc" -eq 0 ] && [ "$erc" -eq 23 ]; } \
  || { fail "axis 3: with the module PRESENT the build did not link it (rc=$rc, binary exits $erc, expected 23):"; tail -3 "$D/a3a.out" | sed 's/^/      /'; a3=1; }
_manifest 'mod/absent.cyr'
rm -f "$D/p/outm2"
rc=0; _run build app2.cyr outm2 > "$D/a3b.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { fail "axis 3: a MISSING [build].modules entry was silently dropped (rc 0)"; a3=1; }
grep -q 'mod/absent.cyr' "$D/a3b.out" || { fail "axis 3: the failure does not name the module it could not read:"; sed 's/^/      /' "$D/a3b.out" | head -3; a3=1; }
[ -e "$D/p/outm2" ] && { fail "axis 3: a binary was produced although a declared module was missing"; a3=1; }
if [ "$(id -u)" = "0" ]; then
    echo "  note: axis 3: the unreadable-module case is skipped as root (mode bits do not bite)"
else
    _manifest 'mod/m.cyr'
    chmod 000 "$D/p/mod/m.cyr"
    rm -f "$D/p/outm3"
    rc=0; _run build app2.cyr outm3 > "$D/a3c.out" 2>&1 || rc=$?
    chmod 644 "$D/p/mod/m.cyr"
    [ "$rc" -ne 0 ] || { fail "axis 3: an UNREADABLE [build].modules entry was silently dropped (rc 0)"; a3=1; }
    grep -q 'mod/m.cyr' "$D/a3c.out" || { fail "axis 3: the unreadable module is not named:"; sed 's/^/      /' "$D/a3c.out" | head -3; a3=1; }
fi
rm -f "$D/p/cyrius.cyml"
[ "$a3" = 0 ] && echo "  ok: axis 3: [build].modules is linked when present (binary exits 23) and named when missing or unreadable"

# ── axis 4: STATIC — no unchecked write of a temp SOURCE left in cbt/ ────────
# Forbidden: a write into the materialised temp (`sys_write(tfd, …)`,
# `syscall(1, tfd, …)`) or the doctest's example (`syscall(1, fd, code, …)`), on a
# non-comment line. Required: the checked helpers, with a floor on their call sites so a
# "fix" that deleted the writes instead of checking them cannot pass.
a4=0
cat > "$D/unchecked.awk" <<'AWK'
{
    line = $0
    sub(/^[ \t]*#.*/, "", line)
    if (line ~ /sys_write\([ \t]*tfd[ \t]*,/)            print FILE "|tfd"
    else if (line ~ /syscall\([ \t]*1[ \t]*,[ \t]*tfd/)  print FILE "|tfd"
    else if (line ~ /syscall\([ \t]*1[ \t]*,[ \t]*fd[ \t]*,[ \t]*code/) print FILE "|code"
}
AWK
_unchecked() { awk -v FILE="$2" -f "$D/unchecked.awk" "$1"; }
# self-test: each forbidden spelling is seen, and the checked replacements are not
mkdir -p "$D/fx"
printf '    sys_write(tfd, "#@incdir ", 9);\n' > "$D/fx/a.cyr"
printf '                            if (mn > 0) { syscall(1, tfd, mbuf, mn); }\n' > "$D/fx/b.cyr"
printf '                        syscall(1, fd, code, code_len);\n' > "$D/fx/c.cyr"
printf '    # sys_write(tfd, "x", 1) in a comment is not a write\n    _mat_write(tfd, "\\n", 1);\n    var w = _dt_write_all(fd, code, code_len);\n' > "$D/fx/d.cyr"
st=0
[ "$(_unchecked "$D/fx/a.cyr" x)" = 'x|tfd' ] || { fail "axis 4 self-test: an unchecked sys_write(tfd, …) is not seen"; st=1; }
[ "$(_unchecked "$D/fx/b.cyr" x)" = 'x|tfd' ] || { fail "axis 4 self-test: an unchecked syscall(1, tfd, …) is not seen"; st=1; }
[ "$(_unchecked "$D/fx/c.cyr" x)" = 'x|code' ] || { fail "axis 4 self-test: the doctest's unchecked syscall(1, fd, code, …) is not seen"; st=1; }
[ -z "$(_unchecked "$D/fx/d.cyr" x)" ] || { fail "axis 4 self-test: a comment or a checked call was flagged: '$(_unchecked "$D/fx/d.cyr" x)'"; st=1; }
a4=$st
nfile=0; : > "$D/sites"
for f in $(ls cbt/*.cyr | LC_ALL=C sort); do
    nfile=$((nfile + 1))
    _unchecked "$f" "$f" >> "$D/sites"
done
[ "$nfile" -ge 8 ] || { fail "axis 4: scanned $nfile files in cbt/ (floor 8) — the scan read nothing"; a4=1; }
bad=$(LC_ALL=C sort -u "$D/sites")
if [ -n "$bad" ]; then
    echo "$bad" | sed 's/^/FAIL: axis 4: an unchecked write of a temp SOURCE a compiler then reads (use _mat_write \/ _mat_copy_fd, or _dt_write_all): /'
    FAIL=1; a4=1
fi
# the checked helpers, and a derived floor on their use (17 + 3 live at 6.6.6)
nmw=$(grep -c '_mat_write' cbt/build.cyr)
nmc=$(grep -c '_mat_copy_fd' cbt/build.cyr)
ndt=$(grep -c '_dt_write_all' cbt/quality.cyr)
[ "$nmw" -ge 14 ] || { fail "axis 4: only $nmw _mat_write references in cbt/build.cyr (floor 14) — the prepends were deleted, not checked"; a4=1; }
[ "$nmc" -ge 3 ]  || { fail "axis 4: only $nmc _mat_copy_fd references in cbt/build.cyr (floor 3) — the two stream copies are not going through the checked helper"; a4=1; }
[ "$ndt" -ge 2 ]  || { fail "axis 4: only $ndt _dt_write_all references in cbt/quality.cyr (floor 2)"; a4=1; }
# the three fail-closed refusals the dynamic axes exercise must be present by name
for pat in 'could not create the preprocessed source' 'build module cannot be read' 'could not read the entry source' 'could not write the preprocessed source'; do
    grep -q "$pat" cbt/build.cyr || { fail "axis 4: cbt/build.cyr no longer refuses by name: \"$pat\""; a4=1; }
done
grep -q 'if (actual_source == 0) { return 1; }' cbt/build.cyr || { fail "axis 4: compile() no longer treats a failed materialisation as a failed build"; a4=1; }
grep -q 'if (cap_source == 0) { return 1; }' cbt/commands.cyr || { fail "axis 4: cyrius capacity no longer treats a failed materialisation as a failure"; a4=1; }
[ "$a4" = 0 ] && echo "  ok: axis 4: no unchecked temp-source write over $nfile cbt files; $nmw _mat_write + $nmc _mat_copy_fd + $ndt _dt_write_all sites, 4 named refusals, both callers fail closed (detector self-tested on 4 shapes)"

if [ "$FAIL" != 0 ]; then echo "FAIL: build_temp_source_write_checked"; exit 1; fi
echo "PASS build_temp_source_write_checked (the preprocessed source is written to completion or the build fails by name: a short write, a missing or unreadable [build].modules entry, and every prepend; no unchecked temp-source write left in cbt/)"
