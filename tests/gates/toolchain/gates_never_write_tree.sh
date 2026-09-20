#!/bin/sh
# gates_never_write_tree.sh — v6.6.6. A gate READS the tree it checks; it never writes it, not
# even "temporarily", and a broken temp dir can fail a gate but can never damage the tree.
#
# ⛔ THE INCIDENT (measured 2026-09-19, the 6.6.5 close). tests/gates/platform/
# syscall_xlat_generated.sh copied the committed src/common/syscall_xlat.cyr to mktemp,
# regenerated the table IN PLACE, and on a diff copied the backup back. /tmp was full: the
# backup copy was created EMPTY, the regenerated table "differed" from it, and the gate
# restored the EMPTY file over the tracked source in the middle of check.sh — then reported
# the table STALE, a false diagnosis on top of the damage. Reproduced on the 6.6.5 tree with
# TMPDIR on a 476 KiB tmpfs (the generator binary fits, the backup does not): the tracked file
# went 7450 -> 0 bytes.
#
# ⭐ THE ROOT CAUSE IS "A GATE WRITES THE TREE", NOT "THE BACKUP FAILED". Save/modify/restore
# is only as safe as the restore, and the restore is exactly the step that runs when things
# are already going wrong (full disk, a timeout kill, ^C). The gate-wide audit found four:
#   * syscall_xlat_generated.sh — the incident. Now regenerates to $D and diffs; the generator
#     takes an OUT path and writes crash-safe (programs/gen_syscall_xlat.cyr).
#   * cybs_if_else_rbx.sh — backed up src/common/util.cyr, injected a probe IN PLACE, ran cybs,
#     restored; a kill in between left the probe in the tree. Now injects into a copy of src/.
#   * lexid_buckets_by_content.sh — with an unusable TMPDIR `mktemp -d` printed nothing and
#     its fixture writer joined "" + "uni.cyr": two 20000-fn files landed in the REPO ROOT, and
#     the gate then PASSED on timings of compiling nothing. Now checks the temp dir.
#   * audit_scope_covers_suite.sh — wrote its probe into tests/tcyr/lang/ and relied on rm + an
#     EXIT trap; SIGKILL runs no trap, and a killed run left the probe in the tree (measured).
#     Now runs `cyrius audit` in a scratch copy. MISSED by the first audit round: its method
#     (TMPDIR missing / read-only, then `git status`) cannot see a write the gate cleans up
#     itself, and the static detector did not follow a write through a variable.
# AUDIT METHOD (6.6.6, round 2 — the one that works): every gate run in NORMAL mode against a
# scratch copy of the tree (HEAD + the working changes + build/, its own git repo, HOME and
# CYRIUS_HOME scratch with every store slot COPIED), then `find -cnewer <stamp>` over it. ctime,
# not mtime and not `git status`: a gate that restores the same bytes, with the original
# mtime, still moves the ctime. Result: the only gate that changed anything outside the
# gitignored build/ outputs was the 6.6.5 audit_scope_covers_suite.sh, which the same run
# confirms. Two gates were not RUN, because they wrote FIXED /tmp names and would clobber a
# concurrent check.sh (io_rdwr_agnos.sh, syscall_wrapper_pass.sh); both were read by hand and
# wrote only /tmp — and since 6.6.6 bite 13 no gate names a fixed /tmp path at all (axis 5).
#
# ⚠ WHAT THIS GATE PINS, AND WHAT IT DOES NOT. Axis 1 is static and covers EVERY gate plus
# scripts/check.sh, but only the shapes it can see: a write spelled against "$ROOT/..." or a
# variable assigned "$ROOT/...", a backup/write-back pair, an in-place editor. A write to a
# cwd-relative path after `cd "$ROOT"` (lexid's shape) is not statically decidable and is
# pinned only for the gates axis 2 runs. Gitignored build/ outputs are EXEMPT — check.sh and
# several gates build tools there by design; the three TRACKED build/ files (derived from
# .gitignore's `!/build/` lines) are not.
#
# AXES
#   1. STATIC, every gate + scripts/check.sh: no gate backs a tracked file up into a temp var
#      and writes it back, edits a tracked path in place (`sed -i`, `perl -i`, python
#      `open('<tracked>', 'w')`), or writes/creates/deletes a path under $ROOT — spelled out or
#      through a variable assigned "$ROOT/..." (followed through two further assignments).
#      Self-tested first on fixtures carrying each shape, and on clean look-alikes, so a
#      detector that matches nothing — or everything — cannot read green.
#   2. DYNAMIC: the four gates above run against a SCRATCH copy of the tree under a normal, a
#      missing, a read-only and a cp-fails-into-temp ("disk full") TMPDIR. Every file and dir
#      in the copy is stamped to 2000-01-01 first, so ANY write — including a restore that puts
#      the same bytes back — shows up under `find -newer`, and a cksum manifest catches content.
#      Under a missing/read-only TMPDIR each must also FAIL (not pass vacuously). The scratch
#      tree carries build/cyrfmt and an EMPTY tests/tcyr/lang, benches/ and fuzz/, so
#      audit_scope_covers_suite.sh's three `cyrius audit` sweeps cost <1 s here (fmt over
#      src/lib/cbt, one probe test) instead of ~5 min, and its pre-6.6.6 version reaches its write.
#   3. DYNAMIC: a STALE committed table is reported STALE and left EXACTLY as it was — the gate
#      neither "fixes" it by regenerating in place nor restores anything over it.
#   4. DYNAMIC: the generator's own write. A short write is an ERROR — under RLIMIT_FSIZE (the
#      kernel's full-disk sequence: a short count, then EFBIG) and into an unwritable dir it
#      exits non-zero, creates no OUT, leaves an existing OUT byte-for-byte, and leaves no temp
#      behind; unconstrained it reproduces the committed table (anti-vacuous). And end to end:
#      syscall_xlat_generated.sh with a generator that cannot write says "could not write",
#      never STALE, and does not touch the tree.
#   5. STATIC (6.6.6 bite 13), every gate + check.sh + the check driver: every temp dir is a
#      CHECKED mktemp (one per line, `V=$(mktemp …) && [ -d|-f "$V" ] || { …; exit N; }`; a
#      hand-built "${TMPDIR:-/tmp}/name.$$" is refused), and no FIXED /tmp name — in a gate, or
#      as a "/tmp/<name>" literal in programs/checks/*.cyr. See the axis for the two exempt,
#      read-only namespaces. Self-tested on 14 shapes and 2 clean files.
#   6. STATIC (6.6.6 bite 13 review), every tests/tcyr + tests/fixtures file — what check.sh RUNS:
#      no "/tmp/<name>" string literal (a non-path literal is allowlisted with its reason, and a
#      stale allowlist entry fails) and no fixed port bound (sock_bind with a non-zero literal or
#      a name assigned one; a raw bind whose sockaddr gets non-zero port bytes or is built by
#      sockaddr_in[6](a, P)). Self-tested on 6 shapes and a clean file.
#
# MUTATION LEDGER (measured 6.6.6, each in a scratch copy of the tree):
#   a. 6.6.5 syscall_xlat_generated.sh + 6.6.5 generator  -> axis 2 FAIL (normal: table
#      rewritten in place; cp-fault: 7450 -> 0 bytes) and axis 1 FAIL (backup/restore pair)
#   b. 6.6.5 cybs_if_else_rbx.sh                          -> axis 2 FAIL (util.cyr rewritten)
#                                                            and axis 1 FAIL
#   c. 6.6.5 lexid_buckets_by_content.sh                  -> axis 2 FAIL (uni.cyr/var.cyr
#      created in the tree root; rc 0 under a missing TMPDIR)
#   d. detector write-back pattern disabled               -> axis 1 self-test FAIL (restore_cp;
#      restore_redirect is still caught, by the $ROOT-path writer below — two nets on one shape)
#   e. detector in-place-editor report disabled           -> axis 1 self-test FAIL (sed_inplace,
#                                                            py_inplace)
#   f. 6.6.5 audit_scope_covers_suite.sh                  -> axis 1 FAIL ($PROBE = $ROOT/tests/
#      tcyr/lang/_audit_scope_probe.tcyr: rm + redirect) and axis 2 FAIL (normal and cp-fault
#      runs: tests/tcyr/lang written — the probe created and removed again)
#   g. detector's $ROOT-path writer disabled              -> axis 1 self-test FAIL (var_probe,
#      root_literal, var_chain, tracked_build); with the 6.6.5 audit gate put back as well, only
#      axis 2 still sees it (normal + cp-fault) — which is exactly how round 1 missed it
#   h. generator back to file_write_all + `<= 0` (OUT     -> axis 4 FAIL (rc 0 and a 2048-byte
#      kept)                                                 OUT under the size limit; the gate
#                                                            then says STALE, not "could not write")
#   i. 6.6.5 folds_agnos_parity.sh (bare `D=$(mktemp -d)`)  -> axis 5 FAIL (unchecked, line 28)
#   j. 6.6.5 io_rdwr_agnos.sh                              -> axis 5 FAIL (hand-built TMPDIR dir;
#                                                            /tmp/cyrius_agnos_* fixed names)
#   k. 6.6.5 programs/checks/platform_win_macho.cyr        -> axis 5 FAIL ("/tmp/cyr_macho_exit",
#                                                            _write, _peep, _derive)
#   l. 6.6.5 freelist_agnos_mmap.sh                        -> axis 5 FAIL (hand-built TMPDIR dir)
#   m. axis-5 fixed-/tmp detector disabled                 -> axis 5 self-test FAIL
#   n. axis-5 mktemp detector accepting everything         -> axis 5 self-test FAIL (bare, trap,
#                                                            wrongvar, noexit, handmade)
#   o. 6.6.5 tests/tcyr/platform/fs.tcyr                   -> axis 6 FAIL (/tmp/cyrius_fs_bare_gate…)
#   p. 6.6.5 tests/fixtures/async/async_sendrecv.cyr       -> axis 6 FAIL (sock_bind(…, port),
#                                                            port = 47663)
#   q. 6.6.5 tests/tcyr/crypto/tls_native_scaffold.tcyr    -> axis 6 FAIL (store8(&sa23 + 2, 0xAD)
#                                                            into the sockaddr sys_bind binds)
#   r. 6.6.5 tests/tcyr/crossos/syscall_wrappers.tcyr      -> axis 6 FAIL (/tmp/cyr_vr01_wrap…)
#   s. axis-6 "/tmp/" literal detector disabled            -> axis 6 self-test FAIL (tmp_lit, tmp_two)
#   t. axis-6 port detector disabled                       -> axis 6 self-test FAIL (port_var,
#                                                            port_lit, port_raw, port_sockaddr)
#   u. an allowlist entry naming a literal that is gone    -> axis 6 FAIL (stale entry)
#   v. axis-5 failure branch may `exit 0` again            -> axis 5 self-test FAIL (skip0: a
#                                                            `{ echo SKIP; exit 0; }` is a vacuous pass)
#   w. axis-5 TMPDIR-path check back to `${TMPDIR:-/tmp}/`  -> axis 5 self-test FAIL (quoted_tmpdir
#      only                                                  "${TMPDIR:-/tmp}"/x, bare_tmpdir, braced_tmpdir)
#   x. axis-5 mktemp-spelling check disabled               -> axis 5 self-test FAIL (backtick,
#                                                            spaced `$( mktemp`, pathed /usr/bin/mktemp)
#   w. axis 7 (bite 17f), each of 9 scripts restored  -> axis 7 FAIL, one per script (install.sh
#      to its 6.6.5 body                                  unchecked TMPDIR; bench-history's
#                                                         hand-made "/tmp/cyr_bench_$$";
#                                                         cass-install-gate, mac-diagnose,
#                                                         cyrius-watch, version-bump and ci.sh
#                                                         fixed /tmp names; differential and
#                                                         verify-store unchecked mktemp)
#   x2. the axis-7 allowlist entry made stale         -> axis 7 FAIL, and cross-os-selfhost.sh's
#                                                         own fixed names are then reported
#   x3. axis 7 (bite 17j), each of the 3 scripts      -> axis 7 FAIL, one per script (cyrius-repl
#      BELOW scripts/ restored to its pre-fix body       /tmp/cyrius_repl_$$ at 3 lines;
#                                                        audit-walk /tmp/aw_fmt_$$ at 3;
#                                                        bench_capacity_overhead unchecked
#                                                        mktemp + /tmp/bench_cap_$$_*)
#   x4. the sweep back to `find scripts -maxdepth 1`  -> axis 7 reads GREEN on 26 files with all
#      with those 3 pre-fix bodies live                  THREE offenders live — the gap the bite
#                                                        17 review found, and why the sweep is
#                                                        by shape (scripts/**, benches/**) now
#   y. axis 8 (bite 17h), each of 5 tests restored    -> axis 8 FAIL, one per file (atomic_write
#      to its 6.6.5 body                                  4 sites, syscalls_meta 2, uid_identity
#                                                         1, syscalls_fileops 1, aarch64_cluster/
#                                                         syscalls_combined 1)
#   z. fs.tcyr's sys_chdir removed while it stays     -> axis 8 FAIL (the allowlist entry is
#      allowlisted                                        hiding a real fixed cwd fixture)
#   z2. RETIRED at bite 9h with the `win_guarded` rule itself: it proved that syscalls_meta's
#      PE-only fixed-name branch really was guarded. Wiring the RemoveDirectoryW reroute
#      (`syscall(0xF03A)`) let that test use `test_scratch` on EVERY target, so the rule, its
#      one allowlist entry and this row are gone — the standing permission went with the
#      defect it was written for. `z` still covers the surviving `chdir` rule.
# Real tree -> PASS.
#
# ⚠ Runs ONLY against a scratch copy. It never runs a gate against the real tree it lives in.
# ⚠ This file is excluded from its own static scan: its fixtures spell the forbidden shapes.
# ⚠ Root can write a chmod-555 dir, so the read-only mode derives whether it IS read-only
#   before demanding a failure, rather than assuming it.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: gates_never_write_tree: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
FAIL=0
SELF="tests/gates/toolchain/gates_never_write_tree.sh"

# ── axis 1: the static shape ──────────────────────────────────────────────────────────
# Prints each tracked path that file $1 backs up into a temp var AND writes back, or edits in
# place, and each write whose target is a path under $ROOT.
_rx_escape() { printf '%s' "$1" | sed 's/[][\.*^$]/\\&/g'; }
# The tracked build/ files, from .gitignore's re-include lines — works without git.
TRACKED_BUILD=$(sed -n 's|^!/build/\([A-Za-z0-9_.-]*\)$|\1|p' .gitignore 2>/dev/null | tr '\n' ' ')
[ -n "$TRACKED_BUILD" ] || { echo "FAIL: axis 1: no '!/build/<file>' lines in .gitignore — cannot tell a tracked build/ file from an output"; exit 1; }
# (c) writes whose target is a TREE path. POSIX awk only (CI's awk is mawk: no intervals, no
# gensub). A variable counts as a tree path when assigned "$ROOT/..." or "$<tree var>/...".
cat > "$W/treewrite.awk" <<'AWK'
function lastref(seg, v,    tmp, off, k) {
    tmp = seg; off = 0; k = 0
    while (match(tmp, "\\$(\\{" v "\\}|" v ")([^A-Za-z0-9_]|$)")) {
        k = off + RSTART; RL = RLENGTH
        off = off + RSTART; tmp = substr(seg, off + 1)
    }
    return k
}
function nosubst(s,    t) {   # blank out $( ... ) command substitutions, innermost first
    t = s
    while (match(t, /\$\([^()]*\)/)) t = substr(t, 1, RSTART - 1) "X" substr(t, RSTART + RLENGTH)
    return t
}
BEGIN { n = split(tracked, tw, " "); for (j = 1; j <= n; j++) TB["build/" tw[j]] = 1 }
{
    line = $0
    if (line ~ /^[ \t]*#/) line = ""
    L[NR] = line
    if (match(line, /^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\/[^" \t;&|)]*/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^[ \t]*(export[ \t]+)?/, "", s)
        name = s; sub(/=.*/, "", name)
        base = s; sub(/^[^=]*="?\$\{?/, "", base); sub(/[}\/].*/, "", base)
        path = s; sub(/^[^=]*="?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//, "", path)
        if (name != "ROOT") { A[name] = base; P[name] = path }
    }
}
END {
    tv["ROOT"] = ""
    for (pass = 0; pass < 3; pass++)
        for (nm in A) if ((A[nm] in tv) && !(nm in tv)) tv[nm] = (tv[A[nm]] == "" ? "" : tv[A[nm]] "/") P[nm]
    for (i = 1; i <= NR; i++) {
        line = L[i]; ns = nosubst(line)
        for (v in tv) {
            r = "\"?\\$(\\{" v "\\}|" v ")([^A-Za-z0-9_]|$)"
            op = ""; src = line
            if (match(line, ">>?\\|?[ \t]*" r)) op = "redirect"
            else if (match(line, "(^|[^A-Za-z0-9_])tee[ \t]+(-[a-z]+[ \t]+)*" r)) op = "tee"
            else if (match(line, "(^|[ \t])of=" r)) op = "dd of="
            else {
                src = ns
                if (match(ns, "(^|[^A-Za-z0-9_-])(touch|rm|rmdir|mkdir|truncate)[ \t]([^;&|]*[ \t])?" r)) op = "create/delete"
                else if (match(ns, "(^|[^A-Za-z0-9_-])(sed[ \t]+-i|perl[ \t]+-[a-z]*i)[^;&|]*[ \t]" r)) op = "in-place edit"
                else if (match(ns, "(^|[^A-Za-z0-9_-])(cp|mv|ln|install)[ \t][^;&|]*[ \t]\"?\\$(\\{" v "\\}|" v ")(/[^ \t\";&|)]*)?\"?[ \t]*($|[;&|)])")) op = "copy/move destination"
            }
            if (op == "") continue
            st = RSTART; seg = substr(src, st, RLENGTH)
            k = lastref(seg, v)
            after = substr(src, st + k - 1 + RL - 1)
            suf = ""
            if (match(after, /^[}]?\/[^ \t";&|)<>]*/)) { suf = substr(after, 1, RLENGTH); sub(/^[}]?\//, "", suf) }
            full = tv[v]; if (suf != "") full = (full == "" ? suf : full "/" suf)
            if (full ~ /^\.\.(\/|$)/) continue
            if (full ~ /^build\// && !(full in TB)) continue
            print (v == "ROOT" ? "" : "$" v " = ") "$ROOT/" full " (" op ", line " i ")"
        }
    }
}
AWK
_detect() {
    grep -v '^[[:space:]]*#' "$1" > "$W/nc" 2>/dev/null || return 0
    # (a) backup: `cp [-flags] P "$VAR/..."` with VAR != ROOT, P an existing tree file
    sed -nE 's/.*(^|[^A-Za-z0-9_])cp[[:space:]]+(-[A-Za-z]+[[:space:]]+)*"?(\$\{?ROOT\}?\/)?([A-Za-z0-9_][A-Za-z0-9_.\/-]*)"?[[:space:]]+"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\/.*/\5 \4/p' "$W/nc" \
    | while read -r var p; do
        [ "$var" = ROOT ] && continue
        [ -f "$ROOT/$p" ] || continue
        pe=$(_rx_escape "$p")
        # write-back: P as the LAST operand of cp/mv, or the target of > / >>
        if grep -Eq "((^|[^A-Za-z0-9_])(cp|mv)[[:space:]].*[[:space:]]|>>?[[:space:]]*)\"?(\\\$\\{?ROOT\\}?/)?$pe\"?[[:space:]]*(\$|[;&|)])" "$W/nc"; then
            echo "$p (backed up to \$$var and written back)"
        fi
    done
    # (b) in-place editors on a literal tree path
    for p in $(sed -nE "s/.*(sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i[a-z]*)[^|;&]*[[:space:]]\"?(\\\$\\{?ROOT\\}?\\/)?([A-Za-z0-9_][A-Za-z0-9_.\\/-]*)\"?[[:space:]]*(\$|[;&|)]).*/\\3/p" "$W/nc") \
             $(sed -nE "s/.*open\\(['\"]([A-Za-z0-9_][A-Za-z0-9_.\\/-]*)['\"][[:space:]]*,[[:space:]]*['\"][wa].*/\\1/p" "$W/nc"); do
        [ -f "$ROOT/$p" ] && echo "$p (edited in place)"
    done
    # (c) a write, create or delete whose target is under $ROOT (spelled, or via a variable)
    awk -v tracked="$TRACKED_BUILD" -f "$W/treewrite.awk" "$1"
}

# Self-test FIRST — the detector must see each shape, and must not see a temp-only write.
mkdir -p "$W/fx"
{ printf 'cp src/common/syscall_xlat.cyr "$D/committed.cyr"\n'
  printf './gen\ncp "$D/committed.cyr" src/common/syscall_xlat.cyr\n'; } > "$W/fx/restore_cp.sh"
{ printf 'cp "$ROOT/src/common/util.cyr" "${D}/util.bak"\n'
  printf 'cat "$D/util.bak" > "$ROOT/src/common/util.cyr"\n'; } > "$W/fx/restore_redirect.sh"
printf "sed -i 's/a/b/' lib/string.cyr\n" > "$W/fx/sed_inplace.sh"
printf "open('src/common/util.cyr','w').write(s)\n" > "$W/fx/py_inplace.sh"
# the 6.6.5 audit_scope_covers_suite.sh shape: a NEW file under the tree, through a variable
{ printf 'PROBE="$ROOT/tests/tcyr/lang/_probe.tcyr"\n'
  printf 'cat > "$PROBE" <<%sEOF%s\nfn main(): i64 { return 0; }\nEOF\n' "'" "'"; } > "$W/fx/var_probe.sh"
printf 'echo x >> "${ROOT}/tests/tcyr/new.tcyr"\n' > "$W/fx/root_literal.sh"
{ printf 'TD=$ROOT/tests\nF="${TD}/fixtures/x.cyr"\n'
  printf 'cp "$W/gen.cyr" "$F"\n'; } > "$W/fx/var_chain.sh"
printf 'cp "$D/cycc.new" "$ROOT/build/cycc"\n' > "$W/fx/tracked_build.sh"
{ printf 'cp "$ROOT/lib/fs.cyr" "$T/w/fs_copy.cyr"\n'
  printf 'cp src/common/util.cyr "$D/u.cyr"; sed -i s/a/b/ "$D/u.cyr"\n'
  printf 'SRC="$ROOT/src/main.cyr"\ncat "$SRC" | "$CC" > "$D/out" 2>&1\ncp "$SRC" "$D/src_copy.cyr"\n'
  printf 'mkdir -p "$T/home/versions/$(cat "$ROOT/VERSION")"\n'
  printf '"$ROOT/build/cycc" < "$ROOT/programs/cyrlint.cyr" > "$ROOT/build/cyrlint" 2> /dev/null\n'
  printf 'PROBE_DIR="$D/p"; mkdir -p "$PROBE_DIR"\necho ok >&2\n'; } > "$W/fx/clean.sh"
st_ok=1; nshape=0
for f in restore_cp restore_redirect sed_inplace py_inplace var_probe root_literal var_chain tracked_build; do
    nshape=$((nshape + 1))
    [ -n "$(_detect "$W/fx/$f.sh")" ] || { echo "FAIL: axis 1 self-test: the detector did not flag the '$f' shape"; st_ok=0; }
done
[ -z "$(_detect "$W/fx/clean.sh")" ] || { echo "FAIL: axis 1 self-test: the detector flagged a temp-only write or a read: $(_detect "$W/fx/clean.sh")"; st_ok=0; }
[ "$st_ok" = 1 ] || FAIL=1

nscan=0; nbad=0
for g in $(find tests/gates -name '*.sh' | LC_ALL=C sort) scripts/check.sh; do
    [ "$g" = "$SELF" ] && continue
    nscan=$((nscan + 1))
    hits=$(_detect "$g")
    if [ -n "$hits" ]; then
        echo "$hits" | sed "s|^|FAIL: axis 1: $g writes the tree it checks: |"
        nbad=$((nbad + 1))
    fi
done
# Floor: 176 gate scripts at 6.6.6 including this one (derive: find tests/gates -name '*.sh' | wc -l).
if [ "$nscan" -lt 150 ]; then
    echo "FAIL: axis 1: only $nscan files scanned (floor 150) — the gate tree moved"; FAIL=1
elif [ "$nbad" -ne 0 ]; then
    FAIL=1
elif [ "$st_ok" = 1 ]; then
    echo "  ok: axis 1: $nscan gate scripts carry no backup/restore, in-place edit, or write under \$ROOT outside the gitignored build/ outputs (detector self-tested on $nshape shapes + 1 clean)"
fi

# ── axes 2+3: run the rewriting-shaped gates against a SCRATCH tree ──────────────────
T="$W/tree"
mkdir -p "$T/build" "$T/programs" "$T/tests/data" "$T/tests/gates/platform" \
         "$T/tests/gates/toolchain" "$T/tests/gates/frontend" "$T/tests/tcyr/lang" \
         "$T/benches" "$T/fuzz" || { echo "FAIL: cannot stage $T"; exit 1; }
# (tests/tcyr/lang, benches/ and fuzz/ are empty on purpose: they are what audit_scope_covers_suite
#  walks and where its pre-6.6.6 version wrote its probe, so that version reaches the write here;
#  with them empty and no cyrlint/cyrdoc staged, its three audit sweeps take under a second)
for x in src lib cbt bootstrap; do cp -R "$x" "$T/$x" || { echo "FAIL: cannot stage $x/ into the scratch tree"; exit 1; }; done
cp -R tests/data/syscalls "$T/tests/data/syscalls" \
  && cp programs/gen_syscall_xlat.cyr "$T/programs/" \
  && cp cyrius.cyml VERSION "$T/" \
  && cp tests/gates/platform/syscall_xlat_generated.sh "$T/tests/gates/platform/" \
  && cp tests/gates/toolchain/cybs_if_else_rbx.sh "$T/tests/gates/toolchain/" \
  && cp tests/gates/toolchain/audit_scope_covers_suite.sh "$T/tests/gates/toolchain/" \
  && cp tests/gates/frontend/lexid_buckets_by_content.sh "$T/tests/gates/frontend/" \
  || { echo "FAIL: cannot stage the scratch tree"; exit 1; }
[ -f cyrius.lock ] && cp cyrius.lock "$T/"
for b in cycc cyrius cyrfmt; do
    [ -x "build/$b" ] || { echo "FAIL: build/$b missing — check.sh stages it; run from check.sh or build it"; exit 1; }
    cp "build/$b" "$T/build/$b" || { echo "FAIL: cannot stage build/$b"; exit 1; }
done
find "$T" -exec touch -t 200001010000 {} + || { echo "FAIL: cannot stamp the scratch tree"; exit 1; }
touch -t 200101010000 "$W/stamp"
_manifest() { ( cd "$T" && find . -type f | LC_ALL=C sort | xargs cksum ); }
_manifest > "$W/m0"
[ "$(wc -l < "$W/m0")" -gt 150 ] || { echo "FAIL: the scratch manifest has $(wc -l < "$W/m0") files (floor 150)"; exit 1; }

# A `cp` that fails exactly the way a full disk makes it fail — destination created, nothing
# lands, exit 1 — but ONLY for destinations under the fault dir. Everything else is the real cp.
REAL_CP=$(command -v cp)
mkdir -p "$W/shim" "$W/tmpfault" "$W/tmpok" "$W/ro"
cat > "$W/shim/cp" <<EOF
#!/bin/sh
for a; do last=\$a; done
case "\$last" in
    "$W/tmpfault"/*)
        isdir=0; n=\$#; i=0
        for a; do i=\$((i + 1)); [ \$i -lt \$n ] || break; case \$a in -*) ;; *) [ -d "\$a" ] && isdir=1 ;; esac; done
        if [ \$isdir = 1 ]; then mkdir -p "\$last"; else : > "\$last"; fi
        echo "cp: error writing '\$last': No space left on device" >&2
        exit 1 ;;
esac
exec "$REAL_CP" "\$@"
EOF
chmod +x "$W/shim/cp"
chmod 555 "$W/ro"
ro_real=1; ( : > "$W/ro/probe" ) 2>/dev/null && { ro_real=0; rm -f "$W/ro/probe"; }

nrun=0; A2=0
_run() {  # _run <gate-rel> <mode> -> checks the tree afterwards
    g=$1; mode=$2
    case $mode in
        normal)  td="$W/tmpok";            pth=$PATH ;;
        missing) td="$W/absent/tmp";       pth=$PATH ;;
        ro)      td="$W/ro";               pth=$PATH ;;
        cpfault) td="$W/tmpfault";         pth="$W/shim:$PATH" ;;
    esac
    rm -rf "$W/absent"
    rc=0
    ( cd "$T" && TMPDIR="$td" PATH="$pth" timeout 300 sh "$g" ) > "$W/out" 2>&1 || rc=$?
    nrun=$((nrun + 1))
    newer=$(find "$T" -newer "$W/stamp" | head -5)
    _manifest > "$W/m1"
    if [ -n "$newer" ] || ! cmp -s "$W/m0" "$W/m1"; then
        echo "FAIL: axis 2: $g [$mode TMPDIR] WROTE THE TREE it checks:"
        [ -n "$newer" ] && echo "$newer" | sed -e "s|^$T\$|      written: the tree root (a file was created or removed there)|" -e "s|^$T/|      written: |"
        diff "$W/m0" "$W/m1" | grep '^[<>]' | head -4 | sed 's/^/      /'
        FAIL=1; A2=1
        # re-stage what it touched so the next run starts clean
        ( cd "$ROOT" && for f in $(diff "$W/m0" "$W/m1" | awk '/^[<>]/ {print $4}' | sort -u); do   # "< CRC SIZE ./path"
              f=${f#./}; if [ -f "$f" ]; then "$REAL_CP" "$f" "$T/$f"; else rm -f "$T/$f"; fi
          done )
        find "$T" -newer "$W/stamp" -exec touch -t 200001010000 {} +
        return 1
    fi
    case $mode in
        missing|ro)
            if [ "$mode" = ro ] && [ "$ro_real" = 0 ]; then return 0; fi
            if [ "$rc" -eq 0 ]; then
                echo "FAIL: axis 2: $g PASSED with an unusable TMPDIR ($mode) — it tested nothing"
                FAIL=1; A2=1; return 1
            fi ;;
        cpfault)
            # audit_scope's first act is to copy the tree into its temp dir; with that copy
            # failing it must stop, not measure a partial tree
            if [ "$g" = tests/gates/toolchain/audit_scope_covers_suite.sh ] && [ "$rc" -eq 0 ]; then
                echo "FAIL: axis 2: $g PASSED although copying the tree into its temp dir failed"
                FAIL=1; A2=1; return 1
            fi ;;
        normal)
            if [ "$rc" -ne 0 ]; then
                echo "FAIL: axis 2: $g does not pass on the scratch tree (rc=$rc) — the harness is not testing it:"
                tail -3 "$W/out" | sed 's/^/      /'; FAIL=1; A2=1; return 1
            fi ;;
    esac
    return 0
}

for m in normal missing ro cpfault; do _run tests/gates/platform/syscall_xlat_generated.sh $m; done
for m in normal missing ro cpfault; do _run tests/gates/toolchain/cybs_if_else_rbx.sh $m; done
for m in missing ro; do _run tests/gates/frontend/lexid_buckets_by_content.sh $m; done
for m in normal missing ro cpfault; do _run tests/gates/toolchain/audit_scope_covers_suite.sh $m; done
if [ "$nrun" -ne 14 ]; then
    echo "FAIL: axis 2: $nrun gate runs, expected 14"; FAIL=1
elif [ "$A2" = 0 ]; then
    echo "  ok: axis 2: 14 runs of the 4 formerly tree-writing gates (normal / missing / read-only$([ "$ro_real" = 0 ] && echo ' [not enforced: running as root]') / cp-fails-into-temp TMPDIR) left the scratch tree byte- and mtime-identical"
fi

# ── axis 3: a STALE table is reported, and left exactly as it is ──────────────────────
X="$T/src/common/syscall_xlat.cyr"
awk '!/if \(n == 294\) \{ return "inotify_init1"; \}/' "$ROOT/src/common/syscall_xlat.cyr" > "$W/stale.cyr"
if cmp -s "$W/stale.cyr" "$ROOT/src/common/syscall_xlat.cyr"; then
    echo "FAIL: axis 3: the 294 row is not in src/common/syscall_xlat.cyr — pick another row to drop"; FAIL=1
else
    "$REAL_CP" "$W/stale.cyr" "$X"; touch -t 200001010000 "$X" "$T/src/common"
    _manifest > "$W/m0"
    rc=0; ( cd "$T" && TMPDIR="$W/tmpok" timeout 300 sh tests/gates/platform/syscall_xlat_generated.sh ) > "$W/out" 2>&1 || rc=$?
    _manifest > "$W/m1"
    if [ "$rc" -eq 0 ] || ! grep -q 'syscall_xlat.cyr is STALE' "$W/out"; then
        echo "FAIL: axis 3: a stale committed table was not reported STALE (rc=$rc)"; FAIL=1
    elif [ -n "$(find "$T" -newer "$W/stamp")" ] || ! cmp -s "$W/m0" "$W/m1" || ! cmp -s "$X" "$W/stale.cyr"; then
        echo "FAIL: axis 3: reporting the stale table REWROTE it — the gate must diff, never regenerate in place"; FAIL=1
    else
        echo "  ok: axis 3: a stale table is reported STALE and left byte-for-byte as committed"
    fi
    "$REAL_CP" "$ROOT/src/common/syscall_xlat.cyr" "$X"; touch -t 200001010000 "$X" "$T/src/common"
fi

# ── axis 4: the generator treats a short write as an ERROR, and the gate calls it that ──
# RLIMIT_FSIZE reproduces a full disk exactly as the writer sees it — the write that crosses
# the limit comes back SHORT, the next one fails EFBIG (SIGXFSZ ignored, as a shell `trap ''`
# is inherited across exec) — with no mount and no root. 4 blocks is 2 KiB under dash and
# 4 KiB under bash, both below the ~7.4 KB table and above every message the generator prints.
# `file_write_all` + `<= 0` reads the short count as success and leaves a truncated table,
# which the gate would then misreport as STALE (measured: the pre-6.6.6 write path).
A4=0
G="$W/gen"
( cd "$T" && ./build/cyrius build programs/gen_syscall_xlat.cyr "$G" ) > "$W/genbuild.out" 2>&1
if [ ! -x "$G" ] || [ ! -s "$G" ]; then
    echo "FAIL: axis 4: programs/gen_syscall_xlat.cyr does not build:"; tail -3 "$W/genbuild.out" | sed 's/^/      /'
    FAIL=1; A4=1
else
    mkdir -p "$W/g_ok" "$W/g_fsz"
    rc=0; ( cd "$T" && "$G" "$W/g_ok/out.cyr" ) > "$W/g0.out" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$W/g_ok/out.cyr" "$ROOT/src/common/syscall_xlat.cyr"; then
        echo "FAIL: axis 4: unconstrained, the generator does not write the committed table to OUT (rc=$rc) — the size-limit rows below would test nothing"
        FAIL=1; A4=1
    fi
    printf 'SENTINEL -- must survive a failed regeneration\n' > "$W/g_fsz/keep.cyr"
    cp "$W/g_fsz/keep.cyr" "$W/keep.orig"
    rc1=0; ( cd "$T" && trap '' XFSZ && ulimit -f 4 && exec "$G" "$W/g_fsz/new.cyr" ) > "$W/g1.out" 2>&1 || rc1=$?
    rc2=0; ( cd "$T" && trap '' XFSZ && ulimit -f 4 && exec "$G" "$W/g_fsz/keep.cyr" ) > "$W/g2.out" 2>&1 || rc2=$?
    left=$(cd "$W/g_fsz" && ls -A | LC_ALL=C sort | tr '\n' ' ')
    if [ "$rc1" -eq 0 ] || [ -e "$W/g_fsz/new.cyr" ]; then
        echo "FAIL: axis 4: a SHORT write was reported as success (rc=$rc1, OUT $( [ -e "$W/g_fsz/new.cyr" ] && wc -c < "$W/g_fsz/new.cyr" | tr -d ' ' || echo absent) bytes)"
        FAIL=1; A4=1
    elif [ "$rc2" -eq 0 ] || ! cmp -s "$W/g_fsz/keep.cyr" "$W/keep.orig"; then
        echo "FAIL: axis 4: a failed regeneration changed the EXISTING OUT (rc=$rc2) — a truncated table replaced it"
        FAIL=1; A4=1
    elif [ "$left" != "keep.cyr " ]; then
        echo "FAIL: axis 4: a failed write left files behind in OUT's dir: $left"
        FAIL=1; A4=1
    elif ! grep -q 'write failed' "$W/g1.out"; then
        echo "FAIL: axis 4: the generator failed without saying why:"; sed 's/^/      /' "$W/g1.out" | head -3
        FAIL=1; A4=1
    fi
    if [ "$ro_real" = 1 ]; then
        rc3=0; ( cd "$T" && "$G" "$W/ro/out.cyr" ) > "$W/g3.out" 2>&1 || rc3=$?
        if [ "$rc3" -eq 0 ] || [ -e "$W/ro/out.cyr" ]; then
            echo "FAIL: axis 4: OUT in an unwritable dir was reported as success (rc=$rc3)"; FAIL=1; A4=1
        fi
    fi
    # End to end: the scratch tree's build/cyrius becomes a wrapper that builds with the real
    # CLI and then runs the BUILT program under the same limit, so syscall_xlat_generated.sh's
    # own generator cannot write — while its temp dir is fine.
    mv "$T/build/cyrius" "$W/cyrius.real"
    cat > "$T/build/cyrius" <<EOF
#!/bin/sh
"$W/cyrius.real" "\$@" || exit \$?
for a; do out=\$a; done
[ "\$1" = build ] && [ -x "\$out" ] || exit 0
mv "\$out" "\$out.real" || exit 1
printf '#!/bin/sh\ntrap "" XFSZ\nulimit -f 4\nexec "%s.real" "\$@"\n' "\$out" > "\$out" && chmod +x "\$out"
EOF
    chmod +x "$T/build/cyrius"
    touch -t 200001010000 "$T/build/cyrius" "$T/build"
    _manifest > "$W/m0"
    rc=0; ( cd "$T" && TMPDIR="$W/tmpok" timeout 300 sh tests/gates/platform/syscall_xlat_generated.sh ) > "$W/out" 2>&1 || rc=$?
    _manifest > "$W/m1"
    if [ "$rc" -eq 0 ] || ! grep -q 'could not write its output' "$W/out" || grep -q 'is STALE' "$W/out"; then
        echo "FAIL: axis 4: syscall_xlat_generated.sh with a generator that cannot write did not say so (rc=$rc):"
        grep 'axis 1' "$W/out" | head -2 | sed 's/^/      /'
        FAIL=1; A4=1
    elif [ -n "$(find "$T" -newer "$W/stamp")" ] || ! cmp -s "$W/m0" "$W/m1"; then
        echo "FAIL: axis 4: syscall_xlat_generated.sh WROTE THE TREE when its generator could not write"; FAIL=1; A4=1
    fi
    mv -f "$W/cyrius.real" "$T/build/cyrius"
    [ "$A4" = 0 ] && echo "  ok: axis 4: a short write (RLIMIT_FSIZE) or an unwritable dir$([ "$ro_real" = 0 ] && echo ' [not enforced: root]') fails the generator with no OUT, an existing OUT kept, no temp left; the gate reports 'could not write', never STALE, tree untouched"
fi

# ── axis 5: STATIC — every temp dir is a CHECKED mktemp, and no gate uses a FIXED /tmp name ──
# v6.6.6. Two shapes, one root cause (a gate's scratch space that is not provably its own):
#   (a) an UNCHECKED `mktemp`. A failed mktemp prints nothing, so D="" and every "$D/x" became
#       ROOT-ABSOLUTE ("/x.bin"): folds_agnos_parity then PASSED "0/12 checked", and
#       install_atomic_over_running_binary ran a box-wide `pkill -f /bin/victim`. Every
#       `$(mktemp …)` must be the canonical `V=$(mktemp …) && [ -d|-f "$V" ] || { …; exit N; }`,
#       and a hand-built `"${TMPDIR:-/tmp}/name.$$"` + `mkdir -p` (no exclusivity, no check)
#       is refused too — a mktemp TEMPLATE argument is the one legitimate `${TMPDIR:-/tmp}/`.
#   (b) a FIXED name under /tmp, shared by every concurrent check.sh (two worktrees, a CI matrix
#       on one runner). Measured this release: ecb's /tmp/cyr_macho_peep, written by the check
#       driver, was replaced mid-T3 by another run's binary and T3 failed rc=126. Refused in the
#       shell gates, and as a string literal "/tmp/<name>" in the check driver
#       (programs/checks/*.cyr — remote names come from _remote_name, local ones from _run_tmp).
#       Exempt, read-only observations of OTHER tools' fixed namespaces: /tmp/cyrius-* (the CLI's
#       own temp, /tmp/cyrius-<pid> by design, CVE-35/36) and /tmp/.wine-* (wineserver's socket).
# Self-tested on each shape and on clean look-alikes first.
_mktemp_bad() {  # prints "<line>: <text>" for every non-canonical mktemp / hand-built temp dir
    # A script that assigns its OWN `TMPDIR` from a CHECKED `mktemp -d` (scripts/install.sh,
    # bench-history.sh) then legitimately spells every path "$TMPDIR/x": that is the private
    # directory, not the shared one. The hand-built-path rule below is about
    # "${TMPDIR:-/tmp}/name.$$" — an unchecked path in whatever TMPDIR happens to be — so it is
    # skipped for those files. CHANGELOG [6.6.6]
    _mb_own=0
    grep -qE '^[ \t]*TMPDIR=\$\(mktemp -d\) && \[ -d "\$TMPDIR" \] \|\| \{' "$1" && _mb_own=1
    awk -v own="$_mb_own" '
    /^[ \t]*#/ { next }
    {
        line = $0
        # every mktemp COMMAND is spelled `$(mktemp` — a backtick, `$( mktemp`, a path or a
        # `command` prefix would slip past the count below (quoted strings are messages)
        q = line; gsub(/"[^"]*"/, "S", q); gsub(/\047[^\047]*\047/, "S", q)
        u = q
        while (match(u, /(^|[^A-Za-z0-9_])mktemp([^A-Za-z0-9_]|$)/)) {
            s0 = (substr(u, RSTART, 1) == "m") ? RSTART : RSTART + 1   # where "mktemp" starts
            if (s0 < 3 || substr(u, s0 - 2, 2) != "$(") { print NR ": " line; next }
            u = substr(u, s0 + 6)
        }
        # one mktemp per line, and that line is the canonical checked assignment whose failure
        # branch EXITS NON-ZERO (a `{ echo SKIP; exit 0; }` is a vacuous pass, not a check)
        n = 0; tmp = line
        while ((i = index(tmp, "$(mktemp")) > 0) { n++; tmp = substr(tmp, i + 8) }
        if (n > 0) {
            ok = 0
            c = line; gsub(/\$\{[^}]*\}/, "X", c)
            if (n == 1 && match(c, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=\$\(mktemp[^)]*\) && \[ -[df] "\$[A-Za-z_][A-Za-z0-9_]*" \] \|\| \{[^}]*\}/)) {
                seg = substr(c, RSTART, RLENGTH)
                v = seg; sub(/^[ \t]*/, "", v); sub(/=.*/, "", v)
                w = ""
                if (match(seg, /\[ -[df] "\$[A-Za-z_][A-Za-z0-9_]*"/)) { w = substr(seg, RSTART + 7, RLENGTH - 8) }
                blk = seg; sub(/^.*\|\| \{/, "", blk)
                if (v == w && blk ~ /(^|[^A-Za-z0-9_])exit[ \t]+[1-9]/ && blk !~ /(^|[^A-Za-z0-9_])exit[ \t]+0/) ok = 1
            }
            if (!ok) { print NR ": " line; next }
        }
        # a temp PATH built from TMPDIR by hand, however spelled (${TMPDIR:-/tmp}/, "${TMPDIR:-/tmp}"/,
        # $TMPDIR/, ${TMPDIR}/) — a mktemp TEMPLATE argument is the one legitimate use
        t = line; gsub(/mktemp[^)]*/, "M", t)
        if (own) next
        if (t ~ /\$TMPDIR"?\// || t ~ /\$\{TMPDIR(:-[^}]*)?\}"?\//) print NR ": " line
    }' "$1"
}
_fixed_tmp_sh() {  # a /tmp/<name> in code (not a comment), bar the two observed namespaces
    awk '/^[ \t]*#/ { next } { t = $0; gsub(/\/tmp\/cyrius-|\/tmp\/\.wine-/, "", t); if (t ~ /\/tmp\/[A-Za-z0-9_.]/) print NR ": " $0 }' "$1"
}
_fixed_tmp_cyr() {  # a "/tmp/<name>" string literal in the check driver
    awk '/^[ \t]*#/ { next } { if ($0 ~ /"\/tmp\/[A-Za-z0-9_.@]/) print NR ": " $0 }' "$1"
}
mkdir -p "$W/fx5"
printf 'D=$(mktemp -d)\n' > "$W/fx5/bare.sh"
printf 'T=$(mktemp); trap '"'"'rm -f "$T"'"'"' EXIT\n' > "$W/fx5/trap.sh"
printf 'A=$(mktemp -d) && [ -d "$B" ] || { echo no; exit 1; }\n' > "$W/fx5/wrongvar.sh"
printf 'A=$(mktemp -d) && [ -d "$A" ] || echo "FAIL: soft"\n' > "$W/fx5/noexit.sh"
printf 'TMP="${TMPDIR:-/tmp}/x.$$"\nmkdir -p "$TMP"\n' > "$W/fx5/handmade.sh"
printf 'D=$(mktemp -d) && [ -d "$D" ] || { echo SKIP; exit 0; }\n' > "$W/fx5/skip0.sh"
printf 'D="${TMPDIR:-/tmp}"/cyr_fixed\n' > "$W/fx5/quoted_tmpdir.sh"
printf 'D=$TMPDIR/cyr_fixed\n' > "$W/fx5/bare_tmpdir.sh"
printf 'D="${TMPDIR}/cyr_fixed"\n' > "$W/fx5/braced_tmpdir.sh"
printf 'D=`mktemp -d` && [ -d "$D" ] || { echo no; exit 1; }\n' > "$W/fx5/backtick.sh"
printf 'D=$( mktemp -d ) && [ -d "$D" ] || { echo no; exit 1; }\n' > "$W/fx5/spaced.sh"
printf 'D=$(/usr/bin/mktemp -d) && [ -d "$D" ] || { echo no; exit 1; }\n' > "$W/fx5/pathed.sh"
printf 'echo x > /tmp/cyx_probe\n' > "$W/fx5/fixed.sh"
printf '    var p = "/tmp/cyr_macho_peep";\n' > "$W/fx5/fixed.cyr"
{ printf 'D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: g: mktemp -d failed"; exit 1; }\n'
  printf 'O=$(mktemp --suffix=.cyr) && [ -f "$O" ] || { echo "FAIL: g"; exit 1; }; trap '"'"'rm -f "$O"'"'"' EXIT\n'
  printf 'H=$(mktemp -d "${TMPDIR:-/tmp}/cyrius-check-home.XXXXXX") && [ -d "$H" ] || { printf x; exit 1; }\n'
  printf 'E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: g: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }\n'
  printf 'rc=0; TMPDIR="$W/tmpok" sh "$g" || rc=$?\nprintf "%%s: mktemp failed\\n" "${TMPDIR:-/tmp}" >&2\n'
  printf '# a comment may say D=$(mktemp -d) or /tmp/foo freely\n'
  printf 'ls -d /tmp/cyrius-* 2>/dev/null\nSOCK="/tmp/.wine-$(id -u)/server"\nsys_chdir("/tmp");\n'; } > "$W/fx5/clean.sh"
printf '    var base = "/tmp";\n    str_builder_add_cstr(sb, "/tmp/");\n    var r = _remote_name("/tmp/", "cyr_x", "");\n' > "$W/fx5/clean.cyr"
st5=0
for f in bare trap wrongvar noexit handmade skip0 quoted_tmpdir bare_tmpdir braced_tmpdir backtick spaced pathed; do
    [ -n "$(_mktemp_bad "$W/fx5/$f.sh")" ] || { echo "FAIL: axis 5 self-test: an unchecked temp dir ('$f') was not flagged"; st5=1; }
done
[ -n "$(_fixed_tmp_sh "$W/fx5/fixed.sh")" ] || { echo "FAIL: axis 5 self-test: a fixed /tmp name in a gate was not flagged"; st5=1; }
[ -n "$(_fixed_tmp_cyr "$W/fx5/fixed.cyr")" ] || { echo "FAIL: axis 5 self-test: a fixed \"/tmp/<name>\" literal in the driver was not flagged"; st5=1; }
[ -z "$(_mktemp_bad "$W/fx5/clean.sh")$(_fixed_tmp_sh "$W/fx5/clean.sh")$(_fixed_tmp_cyr "$W/fx5/clean.cyr")" ] \
    || { echo "FAIL: axis 5 self-test: a canonical form or an exempt read was flagged: $(_mktemp_bad "$W/fx5/clean.sh")$(_fixed_tmp_sh "$W/fx5/clean.sh")$(_fixed_tmp_cyr "$W/fx5/clean.cyr")"; st5=1; }
[ "$st5" = 0 ] || FAIL=1
n5=0; nmk=0; bad5=0
# + every scripts/*-gate.sh that check.sh runs (derived from check.sh itself)
for g in $(find tests/gates -name '*.sh' | LC_ALL=C sort) scripts/check.sh \
         $(grep -oE 'scripts/[A-Za-z0-9_-]+-gate\.sh' scripts/check.sh | LC_ALL=C sort -u); do
    [ "$g" = "$SELF" ] && continue
    n5=$((n5 + 1))
    nmk=$((nmk + $(grep -c 'mktemp' "$g" || true)))
    h=$(_mktemp_bad "$g")
    [ -n "$h" ] && { echo "$h" | sed "s|^|FAIL: axis 5: $g: an UNCHECKED temp dir (use V=\$(mktemp -d) \&\& [ -d \"\$V\" ] \|\| { echo FAIL…; exit 1; }) at line |"; bad5=1; }
    h=$(_fixed_tmp_sh "$g")
    [ -n "$h" ] && { echo "$h" | sed "s|^|FAIL: axis 5: $g: a FIXED /tmp name (shared by concurrent runs) at line |"; bad5=1; }
done
ncyr=0
for c in programs/checks/*.cyr; do
    ncyr=$((ncyr + 1))
    h=$(_fixed_tmp_cyr "$c")
    [ -n "$h" ] && { echo "$h" | sed "s|^|FAIL: axis 5: $c: a FIXED \"/tmp/<name>\" (use _tmp_path / _remote_name) at line |"; bad5=1; }
done
# (this file's own temp dir is canonical too — it is excluded above only for its fixtures)
if [ "$n5" -lt 150 ] || [ "$nmk" -lt 120 ] || [ "$ncyr" -lt 10 ]; then
    echo "FAIL: axis 5: scanned $n5 scripts / $nmk mktemp lines / $ncyr driver files (floors 150 / 120 / 10) — the scan read nothing"; FAIL=1
elif [ "$bad5" != 0 ]; then
    FAIL=1
elif [ "$st5" = 0 ]; then
    echo "  ok: axis 5: $n5 gate scripts ($nmk mktemp lines) take every temp dir from a checked mktemp and name no fixed /tmp path; $ncyr check-driver files carry no \"/tmp/<name>\" (self-tested on 14 shapes + 2 clean files)"
fi

# ── axis 8: STATIC — a test does not CREATE a fixed cwd-relative fixture ────────────────
# v6.6.6 bite 17h. Axes 5-7 are about /tmp. This one is about the OTHER shared directory: the
# check driver's own cwd, which is the REPO ROOT (and `~/_cyaud` on ecb/ach/cass/pi).
# tests/tcyr/crossos/{atomic_write,syscalls_meta,uid_identity}.tcyr created
# `cyrius_atomic_test.txt`, `cyrius_rename_{src,dst}.txt`, `cyrius_intact_test.txt`,
# `cyrius_excl_test.txt`, `_vr01_mdir`, `_vr01_meta.bin` and `_uid_identity_probe.bin` at FIXED
# relative names, so two check.sh runs in one checkout raced over the same files (measured: 2 of
# 4 concurrent atomic_write runs failed `rename returns 0` with -2, ENOENT — the other run had
# already moved the source) and a killed run left them in the tree.
#
# ⚠ THE PATHS ARE CWD-RELATIVE ON PURPOSE and must stay so: /tmp does not exist on Windows,
# where the cross-OS leg runs in C:\cyrius-tests. And the runner cannot simply chdir the
# children, because other tests in the same corpus read TREE-relative paths. So the fix is in
# the NAME: `test_scratch(base)` (lib/assert.cyr) returns "<base>.<pid>", unique per process on
# every target, still relative, still no "/". This axis refuses the bare literal.
# ⚠ ONE TARGET USED TO BE EXEMPT AND IS NOT ANY MORE. Until 6.6.6, `xrmdir` returned -1 on
# PE (no RemoveDirectoryW reroute was wired), so syscalls_meta.tcyr's directory survived every
# Windows run and a per-pid name there would have turned one reused leftover into one per run.
# That branch kept the fixed name under `#ifdef CYRIUS_TARGET_WIN`, allowlisted under a
# `win_guarded` rule. 6.6.6 wired the reroute (`syscall(0xF03A)`), the test uses `test_scratch`
# on every target, and the rule went with the exemption — an allowlist rule whose reason has
# been fixed is the shape this gate exists to refuse.
_cwd_create() {   # prints "<line>: <text>" for every fixed cwd-relative fixture a test creates
    awk '
    /^[ \t]*#/ { next }
    # pass 1 is folded in: a var assigned a bare relative literal is as good as the literal
    match($0, /^[ \t]*var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*"[^"\/]*"[ \t]*;/) {
        v = $0; sub(/^[ \t]*var[ \t]+/, "", v); sub(/[ \t]*=.*/, "", v)
        lit = $0; sub(/^[^"]*"/, "", lit); sub(/".*/, "", lit)
        if (lit != "") barevar[v] = lit
    }
    {
        line = $0
        # the creating calls. sys_open/file_open/xopen only count with a create bit.
        creates = 0
        if (line ~ /(file_write_atomic|file_replace_atomic|file_write_all|file_write_all_r|file_append_locked|file_create_exclusive|sys_mkdir|mkdir_p)\(/) creates = 1
        if (line ~ /(sys_open|file_open|xopen)\(/) {
            if (line ~ /O_CREAT/) creates = 1
            else if (match(line, /,[ \t]*[0-9]+[ \t]*[,)]/)) {
                f = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", f)
                if (f != "" && int(f) % 128 >= 64) creates = 1
            }
        }
        if (!creates) next
        # first argument
        a = line
        sub(/^.*(file_write_atomic|file_replace_atomic|file_write_all_r|file_write_all|file_append_locked|file_create_exclusive|sys_mkdir|mkdir_p|sys_open|file_open|xopen)\(/, "", a)
        sub(/[,)].*/, "", a)
        gsub(/^[ \t]+|[ \t]+$/, "", a)
        if (a ~ /^"[^\/]*"$/) { print NR ": " line; next }
        if (a in barevar) print NR ": " line
    }' "$1"
}
mkdir -p "$W/fx8"
printf 'var p = "cyrius_atomic_test.txt";
var rc = file_write_atomic(p, "x", 1);
' > "$W/fx8/varlit.tcyr"
printf 'sys_mkdir("_vr01_mdir", 493);
' > "$W/fx8/direct.tcyr"
printf 'var fd = sys_open("_uid_probe.bin", 577, 384);
' > "$W/fx8/openflags.tcyr"
printf 'var fd2 = file_open("probe.bin", O_WRONLY | O_CREAT | O_TRUNC, 420);
' > "$W/fx8/opencreat.tcyr"
{ printf 'var p = test_scratch("cyrius_atomic_test.txt");
var rc = file_write_atomic(p, "x", 1);
'
  printf 'var q = test_scratch("_vr01_mdir");
sys_mkdir(q, 493);
'
  printf 'var r2 = file_read_all("tests/data/ucd/x.txt", b, 63);
'
  printf 'var fd3 = sys_open("tests/data/fixed.bin", 0, 0);
'
  printf '# sys_mkdir("_commented", 493) is not a call
'; } > "$W/fx8/clean.tcyr"
st8=0
for f in varlit direct openflags opencreat; do
    [ -n "$(_cwd_create "$W/fx8/$f.tcyr")" ] || { echo "FAIL: axis 8 self-test: a fixed cwd-relative fixture ('$f') was not flagged"; st8=1; }
done
[ -z "$(_cwd_create "$W/fx8/clean.tcyr")" ] || { echo "FAIL: axis 8 self-test: a test_scratch name, a tree-relative READ or a comment was flagged: $(_cwd_create "$W/fx8/clean.tcyr")"; st8=1; }
[ "$st8" = 0 ] || FAIL=1
# Two ways to be safe other than `test_scratch`, each an allowlist RULE that the gate re-checks
# rather than takes on trust — `<file>|<rule>|<reason>`:
#   chdir       the test chdirs into a per-process directory FIRST, so the fixed names inside it
#               are its own. Honoured only while the file still calls sys_chdir.
# (A second rule, `win_guarded`, stood here from 6.6.6 bite 17h to bite 9h: it allowed a fixed
# name inside a `#ifdef CYRIUS_TARGET_WIN` block, because on PE `xrmdir` returned -1 and a
# per-pid directory could never be removed. Wiring the RemoveDirectoryW reroute removed the
# reason, so the rule and its one entry were deleted rather than left as a standing permission
# for a defect that no longer exists.)
ALLOW8='tests/tcyr/platform/fs.tcyr|chdir|it creates a pid-named private dir and sys_chdirs INTO it before any fixture, so the fixed names are inside it — and they must stay literal, because the bare-literal coercion is what this test is testing'
n8=0; bad8=0; nallow8=0
for t in $(find tests/tcyr tests/fixtures -type f \( -name '*.tcyr' -o -name '*.cyr' \) | LC_ALL=C sort); do
    n8=$((n8 + 1))
    h=$(_cwd_create "$t")
    [ -z "$h" ] && continue
    rule8=$(printf '%s\n' "$ALLOW8" | grep -F "$t|" | cut -d'|' -f2)
    case "$rule8" in
        chdir)
            nallow8=$((nallow8 + 1))
            grep -qE 'sys_chdir\(' "$t" || { echo "FAIL: axis 8: $t is allowlisted for chdir-ing into its own private directory, but no longer calls sys_chdir — the allowlist is now hiding a real fixed cwd fixture"; bad8=1; }
            ;;
        *) echo "$h" | sed "s|^|FAIL: axis 8: $t: CREATES a fixed cwd-relative fixture — the check driver's cwd is the REPO ROOT, so concurrent runs race and a killed run leaks (use test_scratch) at line |"; bad8=1 ;;
    esac
done
# an allowlist entry that no longer matches a finding is dead weight
printf '%s\n' "$ALLOW8" | grep . | cut -d'|' -f1 | while read -r af; do
    [ -n "$(_cwd_create "$af")" ] || echo "FAIL: axis 8: allowlist entry '$af' matches no live finding — remove it"
done > "$W/stale8"
[ -s "$W/stale8" ] && { cat "$W/stale8"; bad8=1; }
if [ "$n8" -lt 400 ]; then
    echo "FAIL: axis 8: only $n8 test files scanned (floor 400) — the scan read nothing"; FAIL=1
elif [ "$bad8" != 0 ]; then
    FAIL=1
elif [ "$st8" = 0 ]; then
    echo "  ok: axis 8: $n8 tests/tcyr + tests/fixtures files create no fixed cwd-relative fixture ($nallow8 allowlisted, re-checked against its rule — chdir-into-its-own-dir; self-tested on 4 shapes + 1 clean file)"
fi

# ── axis 7: STATIC — every scripts/*.sh, not just the gates ─────────────────────────────
# v6.6.6 bite 17f. Axis 5 covers tests/gates/**, scripts/check.sh and the `*-gate.sh` scripts
# check.sh calls. The REST of scripts/ had exactly the same defect and nothing looking at it:
# the CI installer staged a release tarball AND the three inputs to its signature check at six
# fixed /tmp names (CVE-44, bite 17e); install.sh compiled a COMPILER to /tmp/cc5_verify, made
# it executable and RAN it; bench-history.sh built and ran every benchmark under a hand-made
# "/tmp/cyr_bench_$$"; cass-install-gate.sh staged a Windows tarball at /tmp/_co_windist;
# version-bump.sh read the seed-derive verdict that decides whether a release is tagged out of
# /tmp/_vb_seed.out. Two shapes, both already detected by axis 5's functions, which is why this
# axis reuses them verbatim rather than writing a second pair that could drift.
#
# ⚠ AND IT SWEEPS BY SHAPE, NOT BY DIRECTORY LEVEL (bite 17 review). The first cut was
# `find scripts -maxdepth 1`, so the two scripts that live one level down kept the very defect
# this axis exists to catch — and both are INSTALLED into `~/.cyrius/versions/<v>/bin`:
#   * scripts/shims/cyrius-repl.sh COMPILED each entered expression to "/tmp/cyrius_repl_$$",
#     chmod'd it +x and RAN it. That is install.sh's /tmp/cc5_verify shape exactly, and the
#     CVE-44 neighbour class: pre-create the name (the redirect follows a symlink) or swap the
#     binary between the chmod and the exec and the REPL runs your code as the user.
#   * scripts/lib/audit-walk.sh staged the formatter's output at "/tmp/aw_fmt_$$" (it needs no
#     temp at all — cyrfmt writes to stdout and diff reads "-").
# benches/ is swept for the same reason: bench_capacity_overhead.sh wrote its timings to
# "/tmp/bench_cap_$$_*" and then `rm -f`'d that glob. A directory-level sweep catches a defect
# where it was last seen; a shape-level one catches it where it is.
#
# ⚠ ALLOWLIST, and why it is short. A fixed /tmp name is allowed only where the path is a
# CONTRACT with something outside this repo, and each entry names it. An entry that matches no
# live line FAILS, so the list cannot rot into a blanket pass.
ALLOW7='scripts/cross-os-selfhost.sh|the /tmp/_co_* staging names the cross-OS self-host leg scps to ecb/ach/cass/pi. NOT fixed here: verifying a change needs all four SSH hosts, which this lane cannot reach, and a silently-wrong path there breaks the release gate (CLAUDE.md already warns to run it ONE host at a time for exactly this reason). Tracked for the next release.'
n7=0; bad7=0; nhit7=0
: > "$W/allow7.live"
for g in $(find scripts benches -name '*.sh' | LC_ALL=C sort); do
    n7=$((n7 + 1))
    allowed=0
    case "$ALLOW7" in *"$g|"*) allowed=1 ;; esac
    h=$(_mktemp_bad "$g")
    if [ -n "$h" ]; then
        nhit7=$((nhit7 + 1))
        [ "$allowed" = 1 ] && printf '%s\n' "$g" >> "$W/allow7.live" \
            || { echo "$h" | sed "s|^|FAIL: axis 7: $g: an UNCHECKED temp dir (use V=\$(mktemp -d) \&\& [ -d \"\$V\" ] \|\| { echo …; exit 1; }) at line |"; bad7=1; }
    fi
    h=$(_fixed_tmp_sh "$g")
    if [ -n "$h" ]; then
        nhit7=$((nhit7 + 1))
        [ "$allowed" = 1 ] && printf '%s\n' "$g" >> "$W/allow7.live" \
            || { echo "$h" | sed "s|^|FAIL: axis 7: $g: a FIXED /tmp name — shared with every other user on the box and with every concurrent run — at line |"; bad7=1; }
    fi
done
# every allowlist entry must still name a live offender
printf '%s\n' "$ALLOW7" | grep . | cut -d'|' -f1 | while read -r af; do
    grep -qxF "$af" "$W/allow7.live" || { echo "FAIL: axis 7: allowlist entry '$af' matches no live fixed-/tmp or unchecked-mktemp line — remove it, it is hiding nothing and could hide the next one"; }
done > "$W/stale7"
[ -s "$W/stale7" ] && { cat "$W/stale7"; bad7=1; }
if [ "$n7" -lt 28 ]; then
    echo "FAIL: axis 7: scanned $n7 scripts/**.sh + benches/**.sh (floor 28) — the scan read nothing"; FAIL=1
elif [ "$bad7" != 0 ]; then
    FAIL=1
else
    nallow7=$(printf '%s\n' "$ALLOW7" | grep -c .)
    echo "  ok: axis 7: all $n7 shell scripts under scripts/ and benches/ (at any depth) take every temp from a checked mktemp and name no fixed /tmp path ($nallow7 allowlisted, each still live; detectors shared with axis 5)"
fi

# ── axis 6: STATIC — the TESTS check.sh runs share no fixed name either ─────────────────
# v6.6.6 bite 13 review. Axis 5 covered the gates and the driver, but every check.sh also RUNS
# the whole tests/tcyr/** corpus and the tests/fixtures/** programs, and those still named fixed
# resources — so two check.sh at once still clobbered each other, on timing luck:
#   (a) "/tmp/<name>" literals: 17 .tcyr files. Measured with the 6.6.5 files, N concurrent
#       copies of one test: fs.tcyr 9/16 failed, io.tcyr 10/16 (one SIGSEGV), syscall_shm_fd_
#       passing 12/12, syscall_wrappers 7/12. Each name is now per-process (/tmp/<name>.<pid>).
#   (b) fixed TCP/UDP ports: the async_connect / async_sendrecv / async_dns fixtures the driver
#       runs on every check.sh bound 47653 / 47663 / 47671 — 24 concurrent runs: 1-2 hung to the
#       timeout or exited 1, each. They bind port 0 and read the port back now.
# A literal that is NOT a path the test opens (a flag-parser argv string) is allowlisted below
# with its reason; an allowlist entry that matches no live literal fails, so the list cannot rot.
# ⚠ Static, so it sees literals only: a cwd-RELATIVE name used after sys_chdir("/tmp") is a
# fixed /tmp name it cannot see (syscall_wrappers.tcyr's access probe was one — found by running
# the file as 16 concurrent copies, not by this scan).
_fixed_tmp_lits() {  # "<file>|<literal>" for every "/tmp/<name>…" string literal in code
    awk '/^[ \t]*#/ { next } {
        t = $0
        while (match(t, /"\/tmp\/[A-Za-z0-9_.@-][^"]*"/)) {
            print FILENAME "|" substr(t, RSTART + 1, RLENGTH - 2)
            t = substr(t, RSTART + RLENGTH)
        }
    }' "$1"
}
# A port a test BINDS that is not 0: sock_bind(fd, addr, P) with P a non-zero literal or a
# name assigned one, and a raw bind (sys_bind / syscall(SYS_BIND|49, …)) whose sockaddr gets
# non-zero port bytes (store8 at +2/+3, store16 at +2) or comes from sockaddr_in[6](a, P).
cat > "$W/ports.awk" <<'AWK'
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
function isnz(x) { return (x ~ /^(0[xX][0-9A-Fa-f]+|[0-9]+)$/) && (x !~ /^(0[xX]0+|0+)$/) }
function nzname(x) { return isnz(x) || (x in NZ) }
function splitargs(s, pos,    depth, i, c, cur, instr) {   # top-level args of the call at pos
    depth = 0; NA = 0; cur = ""; instr = 0
    for (i = pos; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (instr) { cur = cur c; if (c == "\"") instr = 0; continue }
        if (c == "\"") { instr = 1; cur = cur c; continue }
        if (c == "(") depth++
        else if (c == ")") { if (depth == 0) { AR[++NA] = trim(cur); return NA } depth-- }
        else if (c == "," && depth == 0) { AR[++NA] = trim(cur); cur = ""; continue }
        cur = cur c
    }
    NA = 0; return 0
}
function saname(x) { x = trim(x); sub(/^&/, "", x); return trim(x) }
{
    L[NR] = ($0 ~ /^[ \t]*#/) ? "" : $0
    if (match(L[NR], /(^|[^A-Za-z0-9_.])(var[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(0[xX][0-9A-Fa-f]+|[0-9]+)[ \t]*;/)) {
        seg = substr(L[NR], RSTART, RLENGTH); sub(/^[^A-Za-z_]*/, "", seg); sub(/^var[ \t]+/, "", seg)
        id = seg; sub(/[ \t]*=.*/, "", id); v = seg; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t]*;.*/, "", v)
        if (isnz(v)) NZ[id] = 1
    }
}
END {
    for (i = 1; i <= NR; i++) {
        t = L[i]
        while ((k = index(t, "sock_bind(")) > 0) {
            if (splitargs(t, k + 10) == 3 && nzname(AR[3])) print i ": sock_bind(…, " AR[3] ") binds a FIXED port"
            t = substr(t, k + 10)
        }
        t = L[i]
        while ((k = index(t, "sys_bind(")) > 0) { if (splitargs(t, k + 9) >= 2) SA[saname(AR[2])] = 1; t = substr(t, k + 9) }
        t = L[i]
        while ((k = index(t, "syscall(")) > 0) {
            if (splitargs(t, k + 8) >= 3 && (AR[1] == "SYS_BIND" || AR[1] == "49")) SA[saname(AR[3])] = 1
            t = substr(t, k + 8)
        }
    }
    for (i = 1; i <= NR; i++) {
        t = L[i]
        while ((k = index(t, "store8(")) > 0) {
            if (splitargs(t, k + 7) == 2 && isnz(AR[2])) { a = AR[1]; sub(/^&/, "", a); gsub(/[ \t]/, "", a)
                for (s in SA) if (a == s "+2" || a == s "+3") print i ": port byte " AR[2] " stored into the bound sockaddr " s }
            t = substr(t, k + 7)
        }
        t = L[i]
        while ((k = index(t, "store16(")) > 0) {
            if (splitargs(t, k + 8) == 2 && isnz(AR[2])) { a = AR[1]; sub(/^&/, "", a); gsub(/[ \t]/, "", a)
                for (s in SA) if (a == s "+2") print i ": port " AR[2] " stored into the bound sockaddr " s }
            t = substr(t, k + 8)
        }
        if (match(L[i], /[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*sockaddr_in6?\(/)) {
            id = substr(L[i], RSTART, RLENGTH); sub(/[ \t]*=.*/, "", id)
            if ((id in SA) && splitargs(L[i], RSTART + RLENGTH) == 2 && nzname(AR[2])) print i ": the bound sockaddr " id " is built with port " AR[2]
        }
    }
}
AWK
_fixed_port() { awk -f "$W/ports.awk" "$1"; }
# file|literal|reason — literals that are not paths the test opens
TMPLIT_ALLOW='tests/tcyr/crossos/flags.tcyr|/tmp/out.s|argv string for the flag parser; never opened
tests/fixtures/aarch64_cluster/syscalls_combined.cyr|/tmp/out|argv string for the flag parser; never opened'
mkdir -p "$W/fx6"
printf 'var testpath = "/tmp/cyrius_fs_test";\n' > "$W/fx6/tmp_lit.tcyr"
printf '    xsymlink("/tmp/cyr_xlat_f", "/tmp/cyr_xlat_lnk");\n' > "$W/fx6/tmp_two.tcyr"
printf 'fn main(): i64 {\n    var port = 47663;\n    sock_bind(lfd, 0, port);\n}\n' > "$W/fx6/port_var.cyr"
printf '    sock_bind(srv, localhost, 47671);\n' > "$W/fx6/port_lit.cyr"
{ printf '    var sa23[16];\n    store8(&sa23 + 2, 0xAD); store8(&sa23 + 3, 0x23);   # port 44323 (BE)\n'
  printf '    assert_eq(sys_bind(lfd, &sa23, 16), 0, "bind 127.0.0.1:44323");\n'; } > "$W/fx6/port_raw.tcyr"
printf 'var l4sa = sockaddr_in(INADDR_LOOPBACK(), 8080);\nsyscall(SYS_BIND, l4, l4sa, 16);\n' > "$W/fx6/port_sockaddr.tcyr"
{ printf '# a comment may say "/tmp/foo" and sock_bind(fd, 0, 8080)\n'
  printf 'var p = _scratch("cyr_x", "/a");\nmemcpy(p, "/tmp/", 5);\nis_dir(str_from("/tmp"));\n'
  printf 'sock_bind(lfd, 0, 0);\nvar port = _bound_port(lfd);\nsock_connect(fd, ip, 443);\n'
  printf 'var lsa = sockaddr_in6(loop6, 0);\nsyscall(SYS_BIND, lfd, lsa, 28);\nstore8(&r + 2, 0x81);\n'
  printf 'store8(sa + 4, 127);\nsys_bind(lfd, sa, 16);\nsock_bind(fd, INADDR_LOOPBACK(), 0);\n'; } > "$W/fx6/clean.tcyr"
st6=0
for f in tmp_lit.tcyr tmp_two.tcyr; do
    [ -n "$(_fixed_tmp_lits "$W/fx6/$f")" ] || { echo "FAIL: axis 6 self-test: a \"/tmp/<name>\" literal in a test ('$f') was not flagged"; st6=1; }
done
[ "$(_fixed_tmp_lits "$W/fx6/tmp_two.tcyr" | wc -l)" -eq 2 ] || { echo "FAIL: axis 6 self-test: two literals on one line were not both reported"; st6=1; }
for f in port_var.cyr port_lit.cyr port_raw.tcyr port_sockaddr.tcyr; do
    [ -n "$(_fixed_port "$W/fx6/$f")" ] || { echo "FAIL: axis 6 self-test: a fixed port ('$f') was not flagged"; st6=1; }
done
[ -z "$(_fixed_tmp_lits "$W/fx6/clean.tcyr")$(_fixed_port "$W/fx6/clean.tcyr")" ] \
    || { echo "FAIL: axis 6 self-test: a per-process name, an ephemeral bind or a connect was flagged: $(_fixed_tmp_lits "$W/fx6/clean.tcyr") $(_fixed_port "$W/fx6/clean.tcyr")"; st6=1; }
[ "$st6" = 0 ] || FAIL=1
n6=0; bad6=0
: > "$W/lits6"
for t in $(find tests/tcyr tests/fixtures -type f \( -name '*.tcyr' -o -name '*.cyr' \) | LC_ALL=C sort); do
    n6=$((n6 + 1))
    _fixed_tmp_lits "$t" >> "$W/lits6"
    h=$(_fixed_port "$t")
    [ -n "$h" ] && { echo "$h" | sed "s|^|FAIL: axis 6: $t: a FIXED port (bind port 0 and read it back with getsockname) at line |"; bad6=1; }
done
nallow=0
while IFS='|' read -r af al ar; do
    [ -n "$af" ] || continue
    nallow=$((nallow + 1))
    grep -qxF "$af|$al" "$W/lits6" || { echo "FAIL: axis 6: allowlist entry '$af|$al' matches no live literal — remove it"; bad6=1; }
done <<EOF
$TMPLIT_ALLOW
EOF
printf '%s\n' "$TMPLIT_ALLOW" | cut -d'|' -f1,2 | LC_ALL=C sort -u > "$W/allow6"
LC_ALL=C sort -u "$W/lits6" | LC_ALL=C comm -23 - "$W/allow6" > "$W/badlits6"
if [ -s "$W/badlits6" ]; then
    sed 's/^\([^|]*\)|/FAIL: axis 6: \1: a FIXED \/tmp name, shared by every concurrent run (use a per-process name, e.g. \/tmp\/<name>.<pid>): /' "$W/badlits6"
    bad6=1
fi
# Floor: 323 .tcyr + 112 fixture .cyr at 6.6.6 (derive: find tests/tcyr tests/fixtures -name '*.tcyr' -o -name '*.cyr' | wc -l).
if [ "$n6" -lt 400 ]; then
    echo "FAIL: axis 6: only $n6 test files scanned (floor 400) — the scan read nothing"; FAIL=1
elif [ "$bad6" != 0 ]; then
    FAIL=1
elif [ "$st6" = 0 ]; then
    echo "  ok: axis 6: $n6 tests/tcyr + tests/fixtures files name no fixed /tmp path ($nallow allowlisted non-path literals) and bind no fixed port (self-tested on 6 shapes + 1 clean file)"
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: gates_never_write_tree"; exit 1; fi
echo "PASS gates_never_write_tree (static: no gate or check.sh writes a path under \$ROOT but gitignored build/ outputs, edits one in place, or backs one up and restores it; every temp dir is a checked mktemp and no gate or check-driver path is a fixed /tmp name; no test check.sh runs names a fixed /tmp path or binds a fixed port; dynamic: the 4 gates that did leave a stamped scratch tree untouched under 4 TMPDIR faults; the generator fails a short write)"
