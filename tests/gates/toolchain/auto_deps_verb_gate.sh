#!/bin/sh
# tests/gates/toolchain/auto_deps_verb_gate.sh — v6.5.19
#
# EVERY CLI verb that reaches compile() is in the _auto_deps() gate list.
#
# THE BUG CLASS, FIVE TIMES. `cbt/cyrius.cyr` resolves the manifest's [deps] and
# fills `_dep_includes` only for verbs named in one `streq(cmd, ...)` chain. A verb
# that compiles but is missing from that chain gets an EMPTY `_dep_includes`, so
# `_materialize_source` (cbt/build.cyr:378) prepends nothing and every stdlib symbol
# comes back `undefined function` / `undefined variable`:
#
#   v5.7.21  fuzz              — downstream harnesses had to hand-declare the stdlib
#   v5.7.38  soak, smoke       — same parity fix, two more verbs
#   v6.4.73  audit, capacity   — stiva: `audit` 0 passed/5 failed vs `test` 202/0
#   v6.5.17  distlib           — hisab: 44 of 69 [lib] repos called "defective bundle"
#   v6.5.19  doctest           — agnosai: cyrius' OWN lib/hashmap.cyr doctest failed
#
# WHY A DOCTEST-ONLY GATE WOULD BE THE SIXTH PATCH, NOT THE LAST ONE. Auditing the
# whole verb set for the doctest filing found TWO more already live — `publish` and
# `package` — and `publish` was created BY the v6.5.17 patch: `cmd_publish` calls
# `cmd_distlib()` one call frame away, so adding the `distlib` STRING left the identical
# defect reachable through a different verb, printing the identical misleading "the
# generated bundle does not compile" and then git-tagging the release anyway.
# **The requirement is a property of the CALL GRAPH, not of the verb string.**
#
# WHAT THIS GATE DOES. It enumerates every verb `main()` dispatches, computes which
# functions transitively reach `compile()` / `_materialize_source()` across all of
# `cbt/*.cyr`, and FAILS if any dispatched verb that reaches them is absent from the
# list between the AUTO_DEPS_VERBS markers. Exemptions are allow-listed below, one
# reason each, and a stale exemption fails too (axis 3) so the allow-list cannot rot
# into the same silence it exists to prevent.
#
# ⚠ ANTI-VACUOUS. A static analyser that quietly parses nothing reports nothing
# missing and PASSES. Axis 0 puts a floor under every derived quantity, and axis 4
# asserts known-true / known-false rows (`build` compiles, `which` does not) so an
# analyser that has degenerated to "everything" or "nothing" is caught.
#
# ⚠ AN ALLOW-LIST ROW IS A CLAIM, AND AXIS 6f WEIGHS IT. `lsp` was ADDED to
# AUTO_DEPS_VERBS earlier in this same release, on the reasoning that one more verb in
# the list is harmless. It is not: `cyrius lsp` INSTALLS what it builds, and
# programs/cyrius-lsp.cyr already self-declares all 11 of its includes, so gating it
# unioned the whole [deps].stdlib into the installed binary — 119,584 B -> 507,144 B,
# 4.24x, 516 unreachable fns. Same condition as `pulsar`. Axis 6f now RUNS the verb
# into a hermetic CYRIUS_HOME and `cmp`s the installed binary against a no-prepend
# build, so the exemption is measured on every run instead of asserted in a comment.
#
# MUTATION PROOF: delete any one of doctest / publish / package from the
# AUTO_DEPS_VERBS line in cbt/cyrius.cyr — each goes RED on its own (axis 2).
# ADD `lsp` back to that line -> axis 6f RED (installed binary no longer matches the
# no-prepend build), every other axis green — which is exactly how this shipped.
# Delete the `pulsar` allow-list row and axis 2 goes RED for pulsar; delete `pulsar`'s
# `cmd_pulsar` call and axis 3 goes RED for the now-stale exemption.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CLI="cbt/cyrius.cyr"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

if [ ! -f "$ROOT/$CLI" ]; then
    echo "FAIL: auto-deps-verb-gate — $CLI not found"
    exit 1
fi

# ── EXEMPTIONS. A verb belongs here ONLY when auto-prepending the manifest's deps
# would be WRONG for it — not when it is merely inconvenient. One line, one reason.
# Axis 3 re-derives each row against live code, so a row that stops being true fails.
EXEMPT_pulsar='auto-prepend builds a ~434 KB LARGER cycc that is not the self-host fixpoint binary, and pulsar INSTALLS what it builds (measured at 6.5.18: gated 1,576,376 B / 563 unreachable fns vs --no-deps 1,142,016 B, byte-identical to build/cycc; re-measure the two numbers, not the conclusion, if you need them exact)'
EXEMPT_lint='the syntax pre-pass runs under _skip_deps = 1 on purpose — `cyrius lint <file>` must keep working on a single file with no manifest and no lib/ (see docs/development/issues/archived/2026-08-10-cyrlint-never-parses-so-syntax-errors-are-invisible.md)'
EXEMPT_lsp='programs/cyrius-lsp.cyr self-declares all 11 of its includes and only exists inside this repo (cmd_lsp hard-codes the path), so it never had the missing-prepend bug — and like pulsar it INSTALLS what it builds into CYRIUS_HOME/bin. Gating it unioned the whole [deps].stdlib into a binary that already had everything it needed: 119,584 B -> 507,144 B, 4.24x, 516 unreachable fns (measured at 6.5.19; re-measure the numbers, not the conclusion). Axis 5 pins the size so this cannot silently regress again.'
EXEMPT_LIST="pulsar lint lsp"

# ── The analysis. One awk pass over cbt/*.cyr:
#   * strip `#` comments outside double-quoted strings (cbt/deps.cyr:1737 mentions
#     compile() in prose and is a false positive without this),
#   * build caller→callee edges keyed on the enclosing `^fn NAME(`,
#   * reverse-BFS from compile / _materialize_source to the transitive reach set,
#   * split main()'s dispatch chain into per-verb regions (one `streq(cmd, "X")`
#     site to the next) and ask whether that region calls anything in the reach set.
ANALYSIS=$(awk '
function strip(s,   i, c, out, inq, prev) {
    out = ""; inq = 0; prev = "";
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1);
        if (inq == 0 && c == "#") break;
        if (c == "\"" && prev != "\\") inq = 1 - inq;
        out = out c;
        if (c == "\\" && prev == "\\") prev = ""; else prev = c;
    }
    return out;
}
BEGIN { mb = 0; me = 0; ncli = 0 }
FNR == 1 { curfn = "" }
{
    raw = $0; line = strip(raw);
    iscli = (FILENAME ~ /cbt\/cyrius\.cyr$/);
    if (iscli) {
        ncli = FNR;
        if (raw ~ /AUTO_DEPS_VERBS BEGIN/) mb = FNR;
        if (raw ~ /AUTO_DEPS_VERBS END/)   me = FNR;
    }
    if (match(line, /^fn [A-Za-z_][A-Za-z0-9_]*\(/)) {
        curfn = substr(line, 4, RLENGTH - 4);
        nfn++;
        if (iscli && curfn == "main") main_start = FNR;
    }
    # The closing brace of main() bounds the dispatch chain. Without it the LAST
    # verb region runs to EOF and swallows the top-level `var exit_code = main();`
    # — and main reaches compile, so -h was reported as a compiling verb.
    if (iscli && main_start > 0 && main_end == 0 && FNR > main_start && line ~ /^}/) main_end = FNR;
    t = line;
    while (match(t, /[A-Za-z_][A-Za-z0-9_]*[ ]*\(/)) {
        nm = substr(t, RSTART, RLENGTH);
        sub(/[ ]*\($/, "", nm);
        if (curfn != "") edge[curfn SUBSEP nm] = 1;
        if (iscli) lcall[FNR] = lcall[FNR] " " nm;
        t = substr(t, RSTART + RLENGTH);
    }
    if (iscli) cli[FNR] = line;
}
END {
    # reach set: functions that transitively call compile / _materialize_source
    R["compile"] = 1; R["_materialize_source"] = 1;
    changed = 1;
    while (changed) {
        changed = 0;
        for (e in edge) {
            split(e, p, SUBSEP);
            if ((p[2] in R) && !(p[1] in R)) { R[p[1]] = 1; changed = 1 }
        }
    }
    nreach = 0; for (f in R) nreach++;

    # gate list = verbs between the markers
    ngate = 0;
    if (mb > 0 && me > mb) {
        for (i = mb; i <= me; i++) {
            t = cli[i];
            while (match(t, /streq\(cmd, "[^"]*"\)/)) {
                v = substr(t, RSTART, RLENGTH);
                sub(/^streq\(cmd, "/, "", v); sub(/"\)$/, "", v);
                if (!(v in GATE)) { GATE[v] = 1; ngate++ }
                t = substr(t, RSTART + RLENGTH);
            }
        }
    }

    # dispatch sites = every OTHER streq(cmd, "X"), inside main() only
    if (main_end == 0) main_end = ncli;
    nd = 0;
    for (i = main_start; i <= main_end; i++) {
        if (mb > 0 && i >= mb && i <= me) continue;
        t = cli[i];
        while (match(t, /streq\(cmd, "[^"]*"\)/)) {
            v = substr(t, RSTART, RLENGTH);
            sub(/^streq\(cmd, "/, "", v); sub(/"\)$/, "", v);
            nd++; dline[nd] = i; dverb[nd] = v;
            if (!(v in VERB)) { VERB[v] = 1; nverb++ }
            t = substr(t, RSTART + RLENGTH);
        }
    }

    # per-verb region: this dispatch site up to the line before the next one
    for (k = 1; k <= nd; k++) {
        lo = dline[k];
        hi = (k < nd) ? dline[k + 1] - 1 : main_end - 1;
        if (hi < lo) hi = lo;
        for (i = lo; i <= hi; i++) {
            n = split(lcall[i], cs, " ");
            for (j = 1; j <= n; j++) if (cs[j] in R) COMPILES[dverb[k]] = 1;
        }
    }

    for (v in VERB)     print "VERB " v;
    for (v in GATE)     print "GATE " v;
    for (v in COMPILES) print "COMPILES " v;
    print "STAT fns " nfn;
    print "STAT reach " nreach;
    print "STAT verbs " nverb;
    print "STAT gate " ngate;
    print "STAT markers " ((mb > 0 && me > mb) ? 1 : 0);
    print "STAT mainspan " (main_end - main_start);
}
' cbt/*.cyr)

get()      { printf '%s\n' "$ANALYSIS" | awk -v k="$1" '$1==k {print $2}' | sort; }
stat()     { printf '%s\n' "$ANALYSIS" | awk -v k="$1" '$1=="STAT" && $2==k {print $3}'; }
has()      { printf '%s\n' "$ANALYSIS" | awk -v k="$1" -v v="$2" '$1==k && $2==v {n++} END{print n+0}'; }

VERBS=$(get VERB)
GATED=$(get GATE)
COMPILING=$(get COMPILES)

# ── AXIS 0 — the analyser actually analysed something. Without this, an awk that
# parsed nothing reports nothing missing and the gate passes vacuously.
echo "axis 0 — ANTI-VACUOUS floors on every derived quantity:"
check "AUTO_DEPS_VERBS markers found" 1 "$(stat markers)"
check "cbt/ fns indexed >= 140" yes "$([ "$(stat fns)" -ge 140 ] && echo yes || echo no)"
check "compile-reaching fns >= 12" yes "$([ "$(stat reach)" -ge 12 ] && echo yes || echo no)"
check "dispatched verbs >= 35" yes "$([ "$(printf '%s\n' "$VERBS" | grep -c . )" -ge 35 ] && echo yes || echo no)"
check "compile-reaching verbs >= 14" yes "$([ "$(printf '%s\n' "$COMPILING" | grep -c . )" -ge 14 ] && echo yes || echo no)"
check "gate-list verbs >= 12" yes "$([ "$(stat gate)" -ge 12 ] && echo yes || echo no)"
check "main() body spans >= 600 lines" yes "$([ "$(stat mainspan)" -ge 600 ] && echo yes || echo no)"

# ── AXIS 1 — the gate list names only real verbs (a typo'd entry is dead weight
# that reads as coverage).
echo "axis 1 — every AUTO_DEPS_VERBS entry is a verb main() actually dispatches:"
n_ghost=0
for v in $GATED; do
    if [ "$(has VERB "$v")" = 0 ]; then
        echo "  FAIL: gate list names '$v', which main() never dispatches"
        n_ghost=$((n_ghost + 1))
    fi
done
check "ghost entries in the gate list" 0 "$n_ghost"

# ── AXIS 2 — THE INVARIANT. Every verb that reaches compile() is gated or exempt.
echo "axis 2 — ⭐ every compile()-reaching verb is in the gate list (or allow-listed):"
n_missing=0
for v in $COMPILING; do
    if [ "$(has GATE "$v")" != 0 ]; then continue; fi
    case " $EXEMPT_LIST " in *" $v "*) continue ;; esac
    echo "  FAIL: '$v' reaches compile() but is NOT in AUTO_DEPS_VERBS"
    echo "        → it will compile with an EMPTY _dep_includes and every stdlib"
    echo "          symbol will come back undefined. Add it to the list in"
    echo "          cbt/cyrius.cyr, or allow-list it here WITH A REASON."
    n_missing=$((n_missing + 1))
done
check "compile()-reaching verbs missing from the gate" 0 "$n_missing"

# ── AXIS 3 — the allow-list cannot rot. An exemption for a verb that no longer
# exists, or no longer compiles, is silence pretending to be a decision.
echo "axis 3 — every exemption is still live AND still carries a reason:"
for v in $EXEMPT_LIST; do
    check "'$v' is still a dispatched verb" 1 "$(has VERB "$v")"
    check "'$v' still reaches compile() (else the exemption is stale)" 1 "$(has COMPILES "$v")"
    eval "reason=\${EXEMPT_$v:-}"
    check "'$v' exemption carries a reason" yes "$([ -n "$reason" ] && echo yes || echo no)"
    check "'$v' is exempt OR gated, never both" 0 "$(has GATE "$v")"
done

# ── AXIS 4 — the analyser is not degenerate. Known-true and known-false rows: an
# analyser that answered "yes" for everything would satisfy axis 2 by accident.
echo "axis 4 — known-true / known-false rows (catches an analyser stuck at all-yes or all-no):"
for v in build run test tests bench fuzz check audit capacity distlib doctest publish package lsp pulsar; do
    check "'$v' reaches compile()" 1 "$(has COMPILES "$v")"
done
for v in which help version clean deps init update port header fmt doc vet deny coverage repl self hooks install; do
    check "'$v' does NOT reach compile()" 0 "$(has COMPILES "$v")"
done

# ── AXIS 5 — the five historical instances stay fixed. Named explicitly so a
# regression on any one of them is reported by name rather than as a count.
echo "axis 5 — the five shipped instances are still in the list:"
for v in fuzz soak smoke audit capacity distlib doctest; do
    check "'$v' gated" 1 "$(has GATE "$v")"
done

# ── AXIS 6 — ⭐ RUNTIME. The static analysis proves the LIST is complete; it cannot
# prove the entry WORKS. `_materialize_source` (cbt/build.cyr:378) needs BOTH
# `_skip_deps == 0` and a populated `_dep_includes`, and the first attempt at the
# v6.5.17 fix set the flag alone and changed nothing. So: run the verbs.
echo "axis 6 — ⭐ RUNTIME: the gated verbs really do get the manifest prepend:"
if [ ! -x "$ROOT/build/cyrius" ] || [ ! -x "$ROOT/build/cycc" ]; then
    echo "  SKIP: build/cyrius or build/cycc not built — static axes above still ran"
else
    T=$(mktemp -d)
    # Hermetic home: this tree's compiler + this tree's lib/, so the axis cannot pass
    # or fail on whatever happens to be installed.
    mkdir -p "$T/home/bin"
    cp "$ROOT/build/cycc" "$T/home/bin/cycc"
    chmod +x "$T/home/bin/cycc"
    cp -r "$ROOT/lib" "$T/home/lib"
    CY="$ROOT/build/cyrius"
    # `cyrius publish` shells out to `git tag`. mktemp -d lands under /tmp today, but
    # a TMPDIR inside a repo would let that tag land in a REAL repository — so fence
    # git in, and give the one case that reaches the tag step its own throwaway repo.
    GIT_CEILING_DIRECTORIES="$T"
    export GIT_CEILING_DIRECTORIES

    # 6a — doctest: the filed repro. An example that calls a [deps] stdlib fn must PASS
    # with no hand-written `include` line anywhere in the file.
    mkdir -p "$T/dt/src"
    printf '[package]\nname = "dtg"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["syscalls","alloc","string","result","fmt","io","str","vec"]\n' > "$T/dt/cyrius.cyml"
    printf '# >>> fn main() { return str_len(str_from("xy")) - 2; }\n# >>> var r = main(); syscall(60, r);\n# === 0\nfn _dtg(): i64 { return 0; }\n' > "$T/dt/src/mod.cyr"
    rc=0
    ( cd "$T/dt" && CYRIUS_HOME="$T/home" timeout 300 "$CY" doctest src/mod.cyr > "$T/dt.out" 2> "$T/dt.err" ) || rc=$?
    check "doctest: a stdlib-using example passes with no hand-written include" 0 "$rc"
    check "doctest: 1 passed" 1 "$(grep -c '^1 passed, 0 failed' "$T/dt.out" || true)"
    check "doctest: no 'undefined function'" 0 "$(grep -c 'undefined function' "$T/dt.err" || true)"

    # 6b — package: dropping compile()'s return value made this print
    # "package ready in build/" and exit 0 with no artifact on disk.
    mkdir -p "$T/pk/src" "$T/pg/src"
    printf '[package]\nname = "pk"\nversion = "0.1.0"\n' > "$T/pk/cyrius.cyml"
    printf 'fn main() { return undefined_thing_xyz(); }\nvar r = main();\n' > "$T/pk/src/main.cyr"
    rc=0
    ( cd "$T/pk" && CYRIUS_HOME="$T/home" timeout 300 "$CY" package > "$T/pk.out" 2> "$T/pk.err" ) || rc=$?
    check "package: a non-compiling entry exits non-zero" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "package: does not claim 'package ready'" 0 "$(grep -c 'package ready' "$T/pk.out" || true)"
    check "package: no artifact left behind" "no" "$([ -f "$T/pk/build/main" ] && echo yes || echo no)"
    printf '[package]\nname = "pg"\nversion = "0.1.0"\n' > "$T/pg/cyrius.cyml"
    printf 'fn main() { return 0; }\nvar r = main();\n' > "$T/pg/src/main.cyr"
    rc=0
    ( cd "$T/pg" && CYRIUS_HOME="$T/home" timeout 300 "$CY" package > "$T/pg.out" 2> "$T/pg.err" ) || rc=$?
    check "package: ANTI-VACUOUS — a good entry still succeeds" 0 "$rc"
    check "package: and writes the artifact" "yes" "$([ -f "$T/pg/build/main" ] && echo yes || echo no)"

    # 6c — publish: it called cmd_distlib() and discarded the verdict, so it printed
    # "the generated bundle does not compile" and then git-tagged the release anyway.
    mkdir -p "$T/pb/src"
    printf '[package]\nname = "pb"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["syscalls","string","alloc","io"]\n\n[lib]\nmodules = ["src/mod.cyr"]\n' > "$T/pb/cyrius.cyml"
    printf 'fn pb_bad(): i64 {\n    var x = ;\n    return 0;\n}\n' > "$T/pb/src/mod.cyr"
    printf '0.1.0\n' > "$T/pb/VERSION"
    rc=0
    ( cd "$T/pb" && CYRIUS_HOME="$T/home" timeout 300 "$CY" publish > "$T/pb.out" 2> "$T/pb.err" ) || rc=$?
    check "publish: a defective bundle exits non-zero" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "publish: never reaches the git-tag step" 0 "$(grep -c 'tag: v' "$T/pb.out" || true)"
    check "publish: says why" 1 "$(grep -c 'not tagging' "$T/pb.err" || true)"

    # 6d — publish on a bundle that reads a stdlib GLOBAL: the v6.5.17 shape, one call
    # frame down. Must NOT report the bundle as defective.
    mkdir -p "$T/pv/src"
    printf '[package]\nname = "pv"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["syscalls","string","alloc","io"]\n\n[lib]\nmodules = ["src/mod.cyr"]\n' > "$T/pv/cyrius.cyml"
    printf 'fn pv_probe(): i64 {\n    sys_write(STDOUT_FD, "x", 1);\n    return 0;\n}\n' > "$T/pv/src/mod.cyr"
    printf '0.1.0\n' > "$T/pv/VERSION"
    ( cd "$T/pv" && git init -q . >/dev/null 2>&1 ) || true
    ( cd "$T/pv" && CYRIUS_HOME="$T/home" timeout 300 "$CY" publish > "$T/pv.out" 2> "$T/pv.err" ) || true
    check "publish: a GOOD bundle is not called defective" 0 "$(grep -c 'does not compile' "$T/pv.err" || true)"

    # 6e — cmd_doctest's `code` buffer. Both memcpys into it were unbounded, so a doc
    # example longer than 8 KB wrote past the end of the heap region and the failure
    # then presented as a bare "compile error". Noticed while fixing the prepend in the
    # same function; the honest report is a named overflow, not a mystery.
    mkdir -p "$T/ov"
    {
        printf '# >>> fn main() {\n'
        i=0
        while [ "$i" -lt 400 ]; do
            printf '# >>>     var pad_%s = 1234567890; var pad2_%s = 9876543210; var pad3_%s = 1111111;\n' "$i" "$i" "$i"
            i=$((i + 1))
        done
        printf '# >>>     return 0;\n# >>> }\n# >>> var r = main(); syscall(60, r);\n# === 0\nfn _ov(): i64 { return 0; }\n'
    } > "$T/ov/big.cyr"
    rc=0
    ( cd "$T/ov" && CYRIUS_HOME="$T/home" timeout 300 "$CY" doctest big.cyr > "$T/ov.out" 2> "$T/ov.err" ) || rc=$?
    check "doctest: an oversized example is refused, not copied past the buffer" "yes" "$([ "$rc" != 0 ] && echo yes || echo no)"
    check "doctest: and NAMES the overflow" 1 "$(grep -c 'exceeds the 8192-byte example buffer' "$T/ov.err" || true)"

    # 6f — ⭐ THE EXEMPTIONS ARE MEASURED, NOT ASSERTED. An allow-list row is a claim
    # ("gating this verb would be WRONG"); axis 3 only checks the row is still live.
    # `lsp` was added to AUTO_DEPS_VERBS earlier in this same release on the reasoning
    # that one more name is harmless — and `cyrius lsp` INSTALLS what it builds, so
    # the installed binary silently grew 4.24x. So run the verb and weigh the result:
    # programs/cyrius-lsp.cyr self-declares every include it needs, therefore what
    # `cyrius lsp` installs must be EXACTLY what the compiler produces from that file
    # with no prepend at all. `cmp`, not a size band — same compiler, same bytes in.
    "$ROOT/build/cycc" < "$ROOT/programs/cyrius-lsp.cyr" > "$T/lsp_raw" 2> /dev/null
    chmod +x "$T/lsp_raw" 2> /dev/null
    check "lsp: the no-prepend build is non-trivial (floor, so cmp cannot pass on two empties)" \
        "yes" "$([ "$(wc -c < "$T/lsp_raw")" -ge 50000 ] && echo yes || echo no)"
    rc=0
    ( cd "$ROOT" && CYRIUS_HOME="$T/home" timeout 600 "$CY" lsp > "$T/lsp.out" 2> "$T/lsp.err" ) || rc=$?
    check "lsp: the verb succeeds" 0 "$rc"
    check "lsp: it installs into CYRIUS_HOME/bin" "yes" \
        "$([ -f "$T/home/bin/cyrius-lsp" ] && echo yes || echo no)"
    if [ -f "$T/home/bin/cyrius-lsp" ]; then
        lsp_inst=$(wc -c < "$T/home/bin/cyrius-lsp")
        lsp_raw=$(wc -c < "$T/lsp_raw")
        check "lsp: installed binary is byte-identical to the no-prepend build" "yes" \
            "$(cmp -s "$T/home/bin/cyrius-lsp" "$T/lsp_raw" && echo yes || echo no)"
        if ! cmp -s "$T/home/bin/cyrius-lsp" "$T/lsp_raw"; then
            echo "        installed $lsp_inst B vs no-prepend $lsp_raw B — 'lsp' is being"
            echo "        auto-prepended again. Take it OUT of AUTO_DEPS_VERBS in"
            echo "        cbt/cyrius.cyr; it is EXEMPT_lsp here, with the reason."
        fi
    fi
    rm -rf "$T"
fi

echo ""
echo "  verbs dispatched: $(printf '%s\n' "$VERBS" | grep -c .)   reaching compile(): $(printf '%s\n' "$COMPILING" | grep -c .)   gated: $(stat gate)   exempt: $(printf '%s\n' $EXEMPT_LIST | grep -c .)"
if [ "$fails" = "0" ]; then
    echo "PASS: auto-deps-verb-gate — no compile()-invoking verb is missing the manifest prepend"
    exit 0
fi
echo "FAIL: auto-deps-verb-gate — $fails assertion(s) failed"
exit 1
