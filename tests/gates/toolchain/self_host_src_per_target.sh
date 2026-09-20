#!/bin/sh
# self_host_src_per_target.sh — v6.6.6 (bite 23a).
#
# EVERY HOST SELF-HOSTS FROM ITS OWN FORK. `cyrius self` / `cyrius soak` compile THE
# COMPILER and report whether the result reproduces itself. Which source they compile is
# a per-target question: `src/main.cyr` is the x86-64 LINUX fork, and handing it to any
# other host's cycc does NOT error — it is valid cyrius everywhere — so the wrong choice
# produces a real binary and a real-looking verdict about a compiler nobody ships.
#
# MEASURED AT 5a583c1e, on real hardware, with the pre-fix script:
#   pi  (aarch64 Linux) `cat src/main.cyr | cycc > a; cat src/main.cyr | a > b; cmp a b`
#       -> a is an aarch64 ELF that EMITS x86, b is an x86-64 ELF. "FAIL: cycc!=cycc"
#          for a compiler that self-hosts byte-identical from its own fork.
#   ecb (macOS arm64) -> step 1 warns `syscall 12 not routed` (brk, a Linux-ism) and
#          step 2 is `Killed: 9` (AMFI refusing an unsigned arm64 Mach-O). Same FAIL.
# Windows was fixed at bite 9 because there the wrong fork page-faults loudly; on POSIX
# it compiles the WRONG THING instead, which is why it survived.
#
# ⭐ AXIS 2 IS AN EVALUATION, NOT A GREP. A static read of `_self_host_src()` can be
# satisfied by a mapping that mentions every fork and still returns the wrong one — the
# chain is five `#ifdef` arms whose ORDER decides the answer (TARGET_MACOS must be
# tested before ARCH_AARCH64, or an Apple-Silicon host takes the Linux-ARM arm). So the
# gate extracts the REAL fns from cbt/build.cyr, compiles them once per target macro set
# through build/cycc's own preprocessor, RUNS each probe and reads back the string.
#
# ⭐ AXIS 4 IS DERIVED FROM THE SHIPPING RECIPES, not from a list in this file: which
# fork a platform's `cycc` is built from is stated by the tarball scripts and by
# `cyrius pulsar`'s native-ARM chain. Axis 3 (distinctness) alone cannot see a host
# mapped to another ARCH-compatible fork — e.g. aarch64-Linux pointed at the x86-HOSTED
# cross fork `src/main_aarch64.cyr`, which is a plausible edit and still yields five
# distinct answers. M3 in the ledger is exactly that mutant.
#
# ⭐ AXES 6 AND 7 ARE THE REVIEW FIX (6.6.6, bite 23 round 2). Axis 5 knows two fn NAMES,
# and a THIRD self-host loop was already outside it (`_self_host_gate`,
# programs/checks/selfhost.cyr). Axis 6 therefore DISCOVERS the loops — any fn in cbt/ or
# programs/checks/ that names a fork and reports an equality verdict — and requires each
# to be either a HOST-compiler loop that asks `_self_host_src()`, or one pinned to the
# tracked x86-64 Linux `build/cycc`, whose own fork IS `src/main.cyr`. Axis 7 then pins
# the two things that decide whether a host-compiler loop can complete at all: it SIGNS
# the freshly built compiler before running it (AMFI SIGKILLs an unsigned arm64 Mach-O)
# and it compares BYTES, never sizes.
#
# MUTATION LEDGER (each applied to a copy of cbt/ in a temp tree, gate re-run against it)
#   M1. `_self_host_src` reverted to the 5a583c1e body (PE arm + src/main.cyr)  -> RED
#       (axis 3: 2 distinct forks for 5 hosts; axis 4: 3 rows disagree with their recipe)
#   M1b. the same revert INCLUDING deleting `_self_host_src_macos`                -> RED
#       (axis 2's `$NFN -lt 2` extraction floor — a shape change, named as one)
#   M2. macOS helper's ARCH_AARCH64 arm deleted (both macOS rows -> x86_macho)  -> RED
#   M3. aarch64-Linux -> src/main_aarch64.cyr (the CROSS fork; axis 3 still green) -> RED
#   M4. cmd_self re-hardcodes "src/main.cyr" instead of asking _self_host_src()  -> RED
#   M5. Windows arm -> src/main.cyr                                              -> RED
#   M6. cmd_soak compares `_file_size(cc5_t) != _file_size(cc4_t)` again        -> axis 7 RED
#       ("decides on _file_size()" — and see the discovery-predicate note below: the
#        FIRST cut of axis 6 met this mutant with its corpus floor instead)
#   M7. cmd_soak step 2 calls `_pulsar_raw_compile` directly (runs it UNSIGNED) -> axis 7 RED
#   M7b. cmd_self's /bin/sh script loses its `codesign`                         -> axis 7 RED
#   M8. `_self_host_gate` pointed at src/main_aarch64_native.cyr (not build/cycc's fork)
#                                                                                -> axis 6 RED
#   M9. `CC_PATH = _root_path("build/cyrius")` (shape (b)'s premise broken)     -> axis 6 RED
#   M10. the discovery predicate forced to 0 (the detector's own control)   -> axes 6+7 RED
#   M11. a NEW loop added to cbt/build.cyr that neither asks nor pins build/cycc
#                                                                                -> axis 6 RED
#        (this is the row that proves discovery is live rather than a list of names)
#   Real tree -> GREEN.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: self_host_src_per_target: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL self_host_src_per_target: no build/cycc"; exit 1; }

# The file under test may be overridden so a mutant tree can be measured without
# touching the repo (the harness at the bottom of this header sets it).
BUILD_CYR="${SHSPT_BUILD_CYR:-$R/cbt/build.cyr}"
CMDS_CYR="${SHSPT_CMDS_CYR:-$R/cbt/commands.cyr}"
[ -f "$BUILD_CYR" ] || { echo "FAIL self_host_src_per_target: missing $BUILD_CYR"; exit 1; }
[ -f "$CMDS_CYR" ]  || { echo "FAIL self_host_src_per_target: missing $CMDS_CYR"; exit 1; }

fail=0
note() { printf '  %s\n' "$*"; }

# ── axis 1 — the fork corpus, DERIVED (never a list here) ────────────────────────────
FORKS=$(ls src/main*.cyr 2>/dev/null | sort || true)
NFORKS=$(printf '%s\n' "$FORKS" | grep -c 'src/main' || true)
if [ "$NFORKS" -lt 7 ]; then
  echo "FAIL axis1: expected >= 7 per-target forks under src/, found $NFORKS"
  fail=1
fi

# ── axis 2 — extract the REAL mapping fns and EVALUATE them per target ───────────────
awk '/^fn _self_host_src_macos\(\): i64 \{/,/^\}/' "$BUILD_CYR"  > "$D/fns.cyr"
awk '/^fn _self_host_src\(\): i64 \{/,/^\}/'       "$BUILD_CYR" >> "$D/fns.cyr"
NFN=$(grep -c '^fn ' "$D/fns.cyr" || true)
NIF=$(grep -c '#ifdef' "$D/fns.cyr" || true)
# Anti-vacuity ONLY: both fns present and at least one conditional arm survived. The
# floor must NOT encode the chain's current arm COUNT — a mapping reverted to the
# pre-6.6.6 two-arm body would then be rejected here with "did it move?" instead of by
# axes 3/4, which say what is actually wrong (four hosts sharing one fork). Measured:
# M1 hit a `-lt 3` floor and reported the wrong cause.
if [ "$NFN" -lt 2 ] || [ "$NIF" -lt 1 ]; then
  echo "FAIL axis2: extraction is vacuous ($NFN fns, $NIF #ifdef) — did _self_host_src move or change shape?"
  echo "FAIL self_host_src_per_target"
  exit 1
fi

# label:macros — the macro set each HOST's cycc predefines when it compiles cbt/cyrius.cyr
# (src/main*.cyr's own PP_PREDEFINE calls: CYRIUS_TARGET_{LINUX,MACOS,WIN} + CYRIUS_ARCH_*).
ROWS='linux-x86:
linux-aarch64:CYRIUS_ARCH_AARCH64
macos-arm64:CYRIUS_TARGET_MACOS CYRIUS_ARCH_AARCH64
macos-x86:CYRIUS_TARGET_MACOS
windows:CYRIUS_TARGET_WIN'

: > "$D/answers"
nrows=0
printf '%s\n' "$ROWS" | while IFS= read -r row; do
  [ -n "$row" ] || continue
  lab=${row%%:*}
  defs=${row#*:}
  P="$D/p_$lab.cyr"
  : > "$P"
  for d in $defs; do echo "#define $d" >> "$P"; done
  cat "$D/fns.cyr" >> "$P"
  cat >> "$P" <<'PROBE'
fn _p_len(p): i64 { var n = 0; while (load8(p + n) != 0) { n = n + 1; } return n; }
var _r = _self_host_src();
syscall(1, 1, _r, _p_len(_r));
syscall(1, 1, "\n", 1);
syscall(60, 0);
PROBE
  if ! cat "$P" | "$CC" > "$D/b_$lab" 2>"$D/e_$lab"; then
    echo "  axis2 $lab: PROBE FAILED TO COMPILE"
    sed 's/^/    /' "$D/e_$lab"
    echo "BAD" >> "$D/answers"
    continue
  fi
  if [ ! -s "$D/b_$lab" ]; then
    echo "  axis2 $lab: probe binary is EMPTY (compiler produced nothing)"
    echo "BAD" >> "$D/answers"
    continue
  fi
  chmod +x "$D/b_$lab"
  ans=$(ulimit -c 0; "$D/b_$lab" 2>/dev/null || true)
  if [ -z "$ans" ]; then
    echo "  axis2 $lab: probe printed nothing"
    echo "BAD" >> "$D/answers"
    continue
  fi
  echo "$lab $ans" >> "$D/answers"
done
nrows=$(grep -c . "$D/answers" 2>/dev/null || true)
[ -n "$nrows" ] || nrows=0
if [ "$nrows" -ne 5 ]; then
  echo "FAIL axis2: expected 5 evaluated rows, got $nrows"
  fail=1
fi
if grep -q '^BAD$' "$D/answers" 2>/dev/null; then
  echo "FAIL axis2: at least one target probe did not produce an answer"
  fail=1
fi

# ── axis 3 — every answer is a real fork, and no two hosts share one ─────────────────
while read -r lab ans; do
  [ "$lab" = "BAD" ] && continue
  [ -n "${ans:-}" ] || continue
  if [ ! -f "$ans" ]; then
    echo "FAIL axis3: $lab maps to '$ans', which is not a file"
    fail=1
  elif ! printf '%s\n' "$FORKS" | grep -qx "$ans"; then
    echo "FAIL axis3: $lab maps to '$ans', which is not one of the derived src/main*.cyr forks"
    fail=1
  fi
done < "$D/answers"
ndistinct=$(awk '{print $2}' "$D/answers" | sort -u | grep -c . || true)
[ -n "$ndistinct" ] || ndistinct=0
if [ "$ndistinct" -ne 5 ]; then
  echo "FAIL axis3: 5 hosts share only $ndistinct distinct forks — at least one host self-hosts from another host's source"
  awk '{printf "        %-14s -> %s\n", $1, $2}' "$D/answers"
  fail=1
fi

# ── axis 4 — each answer equals the fork that platform's SHIPPING recipe names ───────
# Derived a different way from the mapping under test: the tarball builders and the
# native-ARM chain each name the source their `cycc` is built from.
expect_from() {   # <file> <anchor-regex> -> every distinct src/main*.cyr on the anchored lines
  # ⚠ ALL matching lines, not `head -1`: the first line matching `build/cycc-native-aarch64`
  # in cbt/pulsar.cyr is the COMMENT above the build, which names no fork — measured on
  # this gate's first run as "the shipping recipe moved or was reworded". More than one
  # distinct fork across the matches is reported as ambiguous rather than silently
  # resolved, because picking one would make the expected side a guess.
  _f=$1; _a=$2
  grep -E "$_a" "$_f" 2>/dev/null | grep -oE 'src/main[A-Za-z0-9_]*\.cyr' | sort -u | tr '\n' ' ' || true
}
check_row() {     # <label> <expected-source-file> <expected-one-fork>
  _lab=$1; _src=$2; _exp=$3
  _exp=$(printf '%s' "$_exp" | sed 's/ *$//')
  case "$_exp" in
    "")   echo "FAIL axis4: $_lab — no src/main*.cyr found in $_src; the shipping recipe moved or was reworded"; fail=1; return ;;
    *" "*) echo "FAIL axis4: $_lab — $_src names more than one fork ($_exp); anchor is ambiguous"; fail=1; return ;;
  esac
  [ -f "$_exp" ] || { echo "FAIL axis4: $_lab — $_src names '$_exp', which does not exist"; fail=1; return; }
  _got=$(awk -v l="$_lab" '$1==l{print $2}' "$D/answers" || true)
  if [ "$_got" != "$_exp" ]; then
    echo "FAIL axis4: $_lab self-hosts from '$_got' but ships '$_exp' (per $_src)"
    fail=1
  else
    note "$(printf '%-14s -> %-32s (agrees with %s)' "$_lab" "$_got" "$_src")"
  fi
}
check_row linux-x86     scripts/install.sh                     "$(expect_from scripts/install.sh 'src/main.*\$_sh1')"
check_row linux-aarch64 cbt/pulsar.cyr                         "$(expect_from cbt/pulsar.cyr 'build/cycc-native-aarch64')"
check_row macos-arm64   scripts/build-macos-arm64-tarball.sh   "$(expect_from scripts/build-macos-arm64-tarball.sh 'bin/cycc"')"
check_row macos-x86     scripts/build-macos-x86-tarball.sh     "$(expect_from scripts/build-macos-x86-tarball.sh 'bin/cycc"')"
check_row windows       scripts/build-windows-tarball.sh       "$(expect_from scripts/build-windows-tarball.sh 'bin/cycc\.exe"')"

# ── axis 5 — the callers ASK, they do not hard-code ──────────────────────────────────
# `cmd_self` and `cmd_soak` are the two verbs that self-host. A fork path written into
# either body is the defect coming back, one caller at a time.
for fnname in cmd_self cmd_soak; do
  body=$(awk -v f="^fn $fnname\\\\(" '$0 ~ f {inb=1} inb {print} inb && /^\}/ {exit}' "$CMDS_CYR")
  if [ -z "$body" ]; then
    echo "FAIL axis5: could not extract $fnname from $CMDS_CYR"
    fail=1
    continue
  fi
  if ! printf '%s\n' "$body" | grep -q '_self_host_src()'; then
    echo "FAIL axis5: $fnname does not call _self_host_src()"
    fail=1
  fi
  # Ignore comment lines: the WHY-invariant above the fix names src/main.cyr on purpose.
  hard=$(printf '%s\n' "$body" | grep -vE '^[[:space:]]*#' | grep -oE '"src/main[A-Za-z0-9_]*\.cyr"' | sort -u || true)
  if [ -n "$hard" ]; then
    echo "FAIL axis5: $fnname hard-codes a compiler fork: $hard"
    fail=1
  fi
done

# ── axis 6 — EVERY self-host loop in the tree, DERIVED, not the two verbs named above ──
# Axis 5 knows two fn NAMES. That is exactly as much as it can see, and a third loop was
# already sitting outside it at 6.6.6 (`_self_host_gate` in programs/checks/selfhost.cyr,
# found by review). So this axis DISCOVERS the loops instead: any fn, anywhere in cbt/ or
# programs/checks/, that names a compiler fork (literally or by asking) AND reports an
# equality verdict about two binaries. A new loop is admitted automatically and has to
# answer for itself.
#
# Two legitimate shapes, and nothing else:
#   (a) it ASKS `_self_host_src()` and writes no fork path of its own — the loop runs THIS
#       HOST's compiler, so the fork is a per-target question;
#   (b) it is pinned to `build/cycc` / `CC_PATH` — the TRACKED x86-64 Linux compiler, whose
#       own fork IS `src/main.cyr`, so naming that fork is correct and asking would be
#       WRONG (it would hand an x86 ELF a macOS fork on a Mac).
# `CC_PATH = _root_path("build/cycc")` is re-derived from programs/checks/main.cyr rather
# than assumed, so pointing CC_PATH at a host compiler turns this red.
#
# ⚠ HONEST LIMIT, stated rather than hidden: under (b) the axis checks that `src/main.cyr`
# is among the forks the body names, not that every OTHER fork on those lines is a
# cross-compile target. `cmd_pulsar` legitimately names `src/main_aarch64{,_native}.cyr`
# in the same body, as the sources of the cross-compilers it builds, and telling those
# apart from a self-host step needs semantics a text scan does not have.
echo "axis 6 — every self-host loop in the tree, discovered:"
# ⚠ THE DISCOVERY PREDICATE IS TWO-PRONGED, and the second prong is the one that survives
# a mutation. "Names a fork AND reports an equality verdict" alone is satisfied by DELETING
# the verdict: the first cut of this axis met mutant M6 (cmd_soak back on `_file_size`) with
# "the loop scan found 4, expected 5 — did the detector stop matching?", which is the same
# "did it move?" answer axis 2's floor comment already calls the wrong one. So a fn that
# ASKS `_self_host_src()` AND runs something is a loop no matter what it then compares —
# asking is what only a host-compiler self-host loop does. (`_target_cc_has_js` and
# `_emit_js_refuse` ask too and run nothing, which is why the second half of that prong is
# there.) Broadening the VERDICT list to `_file_size` instead was measured and rejected: it
# drags in five cross-compile gates in programs/checks that are not self-host loops at all.
cat > "$D/loops.awk" <<'AWK'
function flush() {
    if (fname == "") return
    fork = ""; asks = 0; verdict = 0; ccpin = 0; runs = 0; sized = 0
    shell = 0; cs = 0; step = 0; raw = 0
    n = split(body, L, "\n")
    for (i = 1; i <= n; i++) {
        l = L[i]
        # v6.6.6: a `_gate("…")` REGISTRATION is prose, not code. Its description names the
        # verbs and helpers this gate covers — `_self_host_src()` among them — so matching it
        # made this axis flag programs/checks/main.cyr's _run_regression_gates for a call it
        # never makes. Blank the description ONLY: blanking every string also hides the
        # "/bin/sh" and "src/main*.cyr" literals the axes below genuinely read (measured —
        # it turned cmd_self into a false FAIL). Same shape as the exec census in this release.
        if (l ~ /_gate\(/) gsub(/"[^"]*"/, "\"\"", l)
        if (l ~ /_self_host_src\(\)/) asks = 1
        if (l ~ /_files_identical\(|_win_files_equal\(|_self_host_same\(|cmp -s/) verdict = 1
        if (l ~ /CC_PATH|build\/cycc/) ccpin = 1
        if (l ~ /sys_execve\(|_win_compile_spawn\(|_self_host_step\(|_pulsar_raw_compile\(|\/bin\/sh/) runs = 1
        if (l ~ /\/bin\/sh/) shell = 1
        if (l ~ /codesign/) cs = 1
        if (l ~ /_self_host_step\(/) step = 1
        if (l ~ /sys_execve\(|_win_compile_spawn\(|_pulsar_raw_compile\(/) raw = 1
        if (l ~ /_file_size\(/) sized = 1
        while (match(l, /"src\/main[A-Za-z0-9_]*\.cyr"/)) {
            f = substr(l, RSTART + 1, RLENGTH - 2)
            if (index(" " fork " ", " " f " ") == 0) fork = fork " " f
            l = substr(l, RSTART + RLENGTH)
        }
    }
    if ((asks == 1 && runs == 1) || (fork != "" && verdict == 1))
        printf "%s %s asks=%d ccpin=%d runs=%d sized=%d shell=%d cs=%d step=%d raw=%d forks=%s\n", \
               FILENAME, fname, asks, ccpin, runs, sized, shell, cs, step, raw, (fork == "" ? "-" : substr(fork, 2))
    fname = ""; body = ""
}
/^fn [A-Za-z_]/ { flush(); fname = $2; sub(/\(.*/, "", fname); body = "" }
{
    code = $0
    # Strip a `#` comment but never a preprocessor directive (same rule as the PE gate's
    # detector). The WHY-invariants above these loops quote fork paths on purpose.
    if (code !~ /^[ \t]*#(ifdef|ifndef|endif|else|elif)/) sub(/#.*/, "", code)
    if (fname != "") body = body "\n" code
}
END { flush() }
AWK
: > "$D/loops"
for f in cbt/*.cyr programs/checks/*.cyr; do
  [ -f "$f" ] || continue
  awk -f "$D/loops.awk" "$f" >> "$D/loops" || true
done
NLOOP=$(grep -c . "$D/loops" 2>/dev/null || true)
[ -n "$NLOOP" ] || NLOOP=0
# Floor, not an equality: a new loop is welcome, it just has to answer for itself. Five at
# 6.6.6 — cmd_self, cmd_soak, _win_cmd_self, cmd_pulsar, _self_host_gate. A detector that
# matches nothing must fail loudly rather than report "0 wrong loops".
if [ "$NLOOP" -lt 5 ]; then
  echo "FAIL axis6: the loop scan found $NLOOP self-host loops, expected at least 5 — did the detector stop matching?"
  fail=1
fi
# The x86-64-Linux-compiler premise for shape (b), re-derived every run.
CCPATH_SRC=$(grep -oE 'CC_PATH[[:space:]]*=[[:space:]]*_root_path\("[^"]*"\)' programs/checks/main.cyr | grep -oE '"[^"]*"' | tr -d '"' | head -1 || true)
if [ "$CCPATH_SRC" != "build/cycc" ]; then
  echo "FAIL axis6: CC_PATH resolves to '${CCPATH_SRC:-<not found>}', not build/cycc — shape (b)'s premise no longer holds"
  fail=1
fi
while read -r lfile lfn lasks lccpin lruns lsized lshell lcs lstep lraw lforks; do
  [ -n "${lfn:-}" ] || continue
  a=${lasks#asks=}; c=${lccpin#ccpin=}; fks=${lforks#forks=}
  if [ "$a" = "1" ] && [ "$fks" = "-" ]; then
    note "$(printf '%-34s %-18s asks _self_host_src()' "$lfile" "$lfn")"
  elif [ "$c" = "1" ] && printf '%s\n' "$fks" | tr ' ' '\n' | grep -qx 'src/main.cyr'; then
    note "$(printf '%-34s %-18s pinned to build/cycc + its own fork' "$lfile" "$lfn")"
  elif [ "$a" = "1" ]; then
    echo "FAIL axis6: $lfile $lfn asks _self_host_src() AND hard-codes a fork ($fks) — one of the two is wrong"
    fail=1
  else
    echo "FAIL axis6: $lfile $lfn self-hosts from '$fks' without asking _self_host_src() and without pinning build/cycc"
    fail=1
  fi
done < "$D/loops"

# ── axis 7 — a HOST-compiler loop SIGNS what it runs and compares BYTES ───────────────
# Scoped to the loops that answer shape (a): those are the ones that run on Apple Silicon,
# where the two facts below decide whether the verb can complete at all.
#   * An UNSIGNED arm64 Mach-O is SIGKILLed by AMFI. `compile()` does not sign — only
#     `run_binary_timed` does — so `cmd_soak` executing its step-1 output directly could
#     never finish step 2 on ecb: measured at 5a583c1e as `FAIL: self-host size mismatch`
#     on a box where `cyrius self` PASSes.
#   * SIZE IS NOT A SELF-HOST VERDICT. Measured on real ach (Intel macOS) at 5a583c1e:
#     step 1 and step 2 were both 1,699,840 bytes and DIFFERED at byte 217 — Mach-O pads
#     to a page, so the 16 bytes of `#@pkgver` disappeared into the padding and soak
#     scored a PASS over two different compilers. A green placebo, not a pass.
# THE SIGNING TEST IS "EVERY RUN GOES THROUGH `_self_host_step`", not "the word codesign
# appears somewhere in the body": mutant M7 moved ONE of soak's two steps back to a direct
# `_pulsar_raw_compile` and a per-body flag still read as signed, because the OTHER step
# was fine. `cmd_self` hands the whole two-step to `/bin/sh`, so its script is checked for
# `codesign` instead. `_win_*` loops are exempt from the signing half only: PE has no
# codesign and its spawn helper IS `_win_compile_spawn`.
echo "axis 7 — ⭐ host-compiler loops sign what they run and compare bytes:"
NHOST=0
while read -r lfile lfn lasks lccpin lruns lsized lshell lcs lstep lraw lforks; do
  [ -n "${lfn:-}" ] || continue
  [ "${lasks#asks=}" = "1" ] || continue
  NHOST=$((NHOST + 1))
  if [ "${lsized#sized=}" = "1" ]; then
    echo "FAIL axis7: $lfile $lfn decides on _file_size() — a self-host verdict is a BYTE compare"
    fail=1
  fi
  if [ "${lruns#runs=}" != "1" ]; then
    echo "FAIL axis7: $lfile $lfn reports a self-host verdict without running anything"
    fail=1
  fi
  case "$lfn" in _win_*) continue ;; esac
  if [ "${lshell#shell=}" = "1" ]; then
    if [ "${lcs#cs=}" != "1" ]; then
      echo "FAIL axis7: $lfile $lfn hands the self-host to /bin/sh without a codesign (AMFI SIGKILLs an unsigned arm64 Mach-O)"
      fail=1
    fi
  elif [ "${lstep#step=}" != "1" ] || [ "${lraw#raw=}" = "1" ]; then
    echo "FAIL axis7: $lfile $lfn runs a compiler outside _self_host_step() — that is the only path that signs a copy before executing it"
    fail=1
  fi
done < "$D/loops"
if [ "$NHOST" -lt 3 ]; then
  echo "FAIL axis7: only $NHOST host-compiler loops found, expected at least 3 (cmd_self, cmd_soak, _win_cmd_self)"
  fail=1
fi
note "$(printf '%d host-compiler loops checked' "$NHOST")"

if [ "$fail" -ne 0 ]; then
  echo "FAIL self_host_src_per_target"
  exit 1
fi
echo "PASS self_host_src_per_target: $nrows hosts, $ndistinct distinct forks agreeing with their shipping recipe; $NLOOP self-host loops, $NHOST of them on the host compiler"
exit 0
