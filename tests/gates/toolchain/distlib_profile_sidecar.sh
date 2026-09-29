#!/bin/sh
# v6.5.29 — `cyrius distlib <profile>` must EMIT a sidecar, scoped to that profile's own needs.
#
# TWO consumer filings, ONE defect. ranga (M5) reported header-only `.deps` for its
# `[lib.spectral]`/`[lib.hwaccel]` profiles; sit (v1.4.0) reported that `dist/sit-read.deps`
# never appeared at all and blamed `out_path`. Measured: `out_path` is innocent — the path
# derivation was always correct. The leaf SET was empty, so the `vec_len(req_leaves) > 0`
# guard wrote nothing, and the base sidecar sitting on disk from an earlier run is what the
# reporter then read as "overwritten with 38 leaves".
#
# ⛔ THE ROOT CAUSE IS TWO REASONABLE RULES THAT COMPOSE INTO A GUARANTEED-EMPTY FILE:
#   1. v6.5.10 unioned the declared `[deps] stdlib` into the sidecar — BASE ONLY, on the
#      grounds that a profile is a subset and unioning the whole declaration over-reports.
#   2. The toolchain's own guide says "includes are auto-prepended — source files only need
#      project includes", so a conforming project has NO stdlib include lines to scan.
# Rule 1 leaves profiles on include-scan inference; rule 2 guarantees that inference finds
# nothing. Anyone following the documented convention gets an empty profile sidecar.
#
# The fix keeps rule 1's INTENT and inverts its mechanism: union for profiles too, then PRUNE
# the union down to what the profile bundle actually references. Over-reporting is prevented
# by a positive filter instead of by withholding the leaves entirely.
#
# 6.6.10 (bite 15) — EVERY DECLARATION SPELLING, AT THE PRUNE AND AT THE VERIFY (axes 11-16).
# The prune and the verify loop's symbol attribution each matched column-0 `fn ` / `var `
# lines, so a leaf whose symbols are `#inline fn` or indented was invisible to BOTH: the
# profile sidecar came out with 0 leaves at rc 0 (measured), because the verify loop read the
# still-undefined symbol as "not stdlib" and moved on. A `pub fn` leaf was dropped by the
# prune and only rescued by the loop ("re-added 1 leaf(s)"). Both now use cbt/srcscan.cyr's
# `_src_decls`. Axes 11-15: each leaf is kept BY THE PRUNE (no "re-added" line). Axis 16: a
# stdlib file whose braces do not balance (so the depth-0 reader cannot see past the skew)
# and that declares the missing symbol is a HARD ERROR naming the file, not a short sidecar.
# MUTATIONS (6.6.10, run by hand): the prune back on column-0 `fn `/`var ` → 11, 12, 13, 14,
# 15 FAIL; the attribution back on it → 11, 12 FAIL (0 leaves, rc 0); the unbalanced-file
# check removed (`raw == 0` → continue) → 16 FAIL.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CLI="$ROOT/build/cyrius"
[ -x "$CLI" ] || CLI="$HOME/.cyrius/bin/cyrius"
[ -x "$CLI" ] || { echo "SKIP: cyrius CLI missing"; exit 0; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: distlib_profile_sidecar: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/src" "$W/pkg/lib" "$W/pkg/dist" "$W/home/bin"
# A hermetic CYRIUS_HOME needs BOTH bin/cycc and a real lib/: `_auto_deps()` resolves the
# manifest's [deps].stdlib out of CYRIUS_HOME/lib, and a home with only bin/ dies with
# `cannot find cyrius stdlib` — which would make every axis below pass vacuously on a
# package that never built. (Same trap test_runner_bounded.sh documents at its axis 4.)
cp "$ROOT/build/cycc" "$W/home/bin/cycc"; chmod +x "$W/home/bin/cycc"
cp -R "$ROOT/lib" "$W/home/lib"
CYRIUS_HOME="$W/home"; export CYRIUS_HOME
cd "$W/pkg"

# Two leaves with DIFFERENT shapes:
#   dispatch.cyr  — a DISPATCHER: defines almost nothing itself, delegates to a name-prefixed
#                   private peer. This is `lib/syscalls.cyr`'s shape (8 KB, TWO top-level
#                   definitions, every `sys_*` wrapper in a per-arch peer).
#   plainleaf.cyr — an ordinary leaf that defines its own symbols.
cat > lib/dispatch_impl.cyr <<'EOF'
fn dispatch_do(x): i64 { return x + 1; }
EOF
cat > lib/dispatch.cyr <<'EOF'
include "lib/dispatch_impl.cyr"
include "lib/plainleaf.cyr"
var _dispatch_marker = 0;
EOF
cat > lib/plainleaf.cyr <<'EOF'
fn plainleaf_do(x): i64 { return x + 2; }
EOF
# heavy.cyr is the `tls_native` SHAPE: it includes a COMMON, non-prefixed leaf
# (`plainleaf`) alongside its own symbols. The profile bundle references plainleaf's symbol
# but never heavy's. This is the shape that made an unguarded peer recursion keep
# `tls_native` in sit's read profile — the leaf the profile exists to drop.
cat > lib/heavy.cyr <<'EOF'
include "lib/plainleaf.cyr"
fn heavy_do(x): i64 { return x + 9; }
EOF

cat > src/a.cyr <<'EOF'
fn a_one(): i64 { return dispatch_do(1) + plainleaf_do(2); }
EOF
cat > src/b.cyr <<'EOF'
fn b_two(): i64 { return heavy_do(2); }
EOF
# c.cyr references NO leaf at all — its profile's pruned set is legitimately EMPTY, which is
# the only shape that exercises the always-write rule.
cat > src/c.cyr <<'EOF'
fn c_three(): i64 { return 3; }
EOF
# 6.6.9 (vani filing) — ONLY CODE IS A REFERENCE. Each of these names `heavy_do` (or its leaf)
# in a different way, and only two of them are code:
#   d.cyr  — `heavy_do` in a `#` comment AND in a string literal: NOT a reference;
#   e.cyr  — a char literal '"' BEFORE a real call: a blanker that took strings before chars
#            would read '"' as a string opening and blank the call after it — so the call must
#            still keep `heavy` (anti-vacuous for d.cyr: blanking everything passes it);
#   f.cyr  — an `include "lib/heavy.cyr"` line and no call: the bundle KEEPS that line, so a
#            consumer's build must resolve it — a reference even though the path is a string.
cat > src/d.cyr <<'EOF'
# Wraps heavy_do() — safe to call heavy_do twice.
fn d_four(): i64 {
    var msg = "heavy_do";
    return 4;
}
EOF
cat > src/e.cyr <<'EOF'
fn e_five(c): i64 {
    if (c == '"') { return heavy_do(5); }
    return 5;
}
EOF
cat > src/f.cyr <<'EOF'
include "lib/heavy.cyr"
fn f_six(): i64 { return 6; }
EOF
# 6.6.10 — one leaf per declaration spelling (axes 11-15), and an unbalanced one (axis 16).
cat > lib/attrleaf.cyr <<'EOF'
#inline fn attrleaf_do(x): i64 { return x + 11; }
EOF
cat > lib/indleaf.cyr <<'EOF'
    fn indleaf_do(x): i64 { return x + 12; }
EOF
cat > lib/publeaf.cyr <<'EOF'
pub fn publeaf_do(x): i64 { return x + 13; }
EOF
printf 'fn\ttableaf_do(x): i64 { return x + 14; }\n' > lib/tableaf.cyr
cat > lib/enumleaf.cyr <<'EOF'
enum EnumLeafK { ENUMLEAF_A = 15; ENUMLEAF_B; }
EOF
cat > lib/skewleaf.cyr <<'EOF'
#ifdef CYRIUS_TARGET_NO_SUCH_TARGET
fn skewleaf_head(x): i64 {
#endif
#ifndef CYRIUS_TARGET_NO_SUCH_TARGET
fn skewleaf_head(x): i64 {
#endif
    return x;
}
fn skewleaf_do(x): i64 { return x + 16; }
EOF
printf 'fn g_attr(): i64 { return attrleaf_do(1); }\n' > src/g_attr.cyr
printf 'fn g_ind(): i64 { return indleaf_do(1); }\n' > src/g_ind.cyr
printf 'fn g_pub(): i64 { return publeaf_do(1); }\n' > src/g_pub.cyr
printf 'fn g_tab(): i64 { return tableaf_do(1); }\n' > src/g_tab.cyr
printf 'fn g_enm(): i64 { return ENUMLEAF_A; }\n' > src/g_enm.cyr
printf 'fn g_skew(): i64 { return skewleaf_do(1); }\n' > src/g_skew.cyr
cat > src/lib.cyr <<'EOF'
include "src/a.cyr"
include "src/b.cyr"
include "src/c.cyr"
EOF
cat > cyrius.cyml <<'EOF'
[package]
name = "pf"
version = "0.1.0"

[deps]
stdlib = ["dispatch", "plainleaf", "heavy", "attrleaf", "indleaf", "publeaf", "tableaf", "enumleaf", "skewleaf"]

[lib]
modules = ["src/a.cyr", "src/b.cyr", "src/c.cyr"]

[lib.small]
modules = ["src/a.cyr"]

[lib.bare]
modules = ["src/c.cyr"]

[lib.words]
modules = ["src/d.cyr"]

[lib.chr]
modules = ["src/e.cyr"]

[lib.inc]
modules = ["src/f.cyr"]

[lib.attr]
modules = ["src/g_attr.cyr"]

[lib.ind]
modules = ["src/g_ind.cyr"]

[lib.pubp]
modules = ["src/g_pub.cyr"]

[lib.tab]
modules = ["src/g_tab.cyr"]

[lib.enm]
modules = ["src/g_enm.cyr"]

[lib.skew]
modules = ["src/g_skew.cyr"]
EOF

# The fake leaves must live where [deps].stdlib resolves them (CYRIUS_HOME/lib) AND where
# the prune's own scan looks first (the package's ./lib).
cp lib/dispatch.cyr lib/dispatch_impl.cyr lib/plainleaf.cyr lib/heavy.cyr "$W/home/lib/"
cp lib/attrleaf.cyr lib/indleaf.cyr lib/publeaf.cyr lib/tableaf.cyr lib/enumleaf.cyr lib/skewleaf.cyr "$W/home/lib/"

"$CLI" distlib      > "$W/base.log"  2>&1 || true
"$CLI" distlib small > "$W/prof.log" 2>&1 || true
"$CLI" distlib bare  > "$W/bare.log" 2>&1 || true
"$CLI" distlib words > "$W/words.log" 2>&1 || true
"$CLI" distlib chr   > "$W/chr.log" 2>&1 || true
"$CLI" distlib inc   > "$W/inc.log" 2>&1 || true
for pr in attr ind pubp tab enm; do "$CLI" distlib "$pr" > "$W/$pr.log" 2>&1 || true; done
SKEW_RC=0; "$CLI" distlib skew > "$W/skew.log" 2>&1 || SKEW_RC=$?

# PREMISE ROW — if the bundles did not build, every axis below is vacuous.
if [ ! -f dist/pf.cyr ] || [ ! -f dist/pf-small.cyr ]; then
    echo "  FAIL premise: distlib produced no bundle — the axes below would pass vacuously"
    sed -n '1,6p' "$W/base.log" | sed 's/^/    /'
    echo "FAIL: distlib-profile-sidecar"; exit 1
fi
echo "  ok premise: both bundles built (base + profile)"

fail=0
leaves() { grep -v '^#' "$1" 2>/dev/null | grep -v '^$' | sort | tr '\n' ' '; }

# --- axis 1: THE HEADLINE — the profile sidecar must EXIST ---
if [ ! -f dist/pf-small.deps ]; then
    echo "  FAIL axis 1: dist/pf-small.deps was never created (the filed symptom)"; fail=1
else
    echo "  ok axis 1: dist/pf-small.deps exists"
fi

# --- axis 2: it must not simply copy the base (no over-report) ---
B=$(leaves dist/pf.deps); S=$(leaves dist/pf-small.deps)
if [ "$B" = "$S" ]; then
    echo "  FAIL axis 2: profile sidecar equals the base's [$B] — the prune did not narrow it"; fail=1
else
    echo "  ok axis 2: profile [$S] is narrower than base [$B]"
fi

# --- axis 3 (ANTI-VACUOUS for axis 1): it must CONTAIN the leaf the profile really needs ---
# Without this, "always write the file" passes axis 1 with an empty file — which is the ranga
# symptom exactly, and would be a regression dressed as a fix.
case " $S " in
    *" dispatch "*) echo "  ok axis 3: the referenced leaf 'dispatch' is present" ;;
    *) echo "  FAIL axis 3 (anti-vacuous): 'dispatch' missing from [$S] — the small profile calls dispatch_do(), so the sidecar UNDER-reports and a consumer following it cannot build"; fail=1 ;;
esac

# --- axis 4 (the DISPATCHER axis): a leaf that defines nothing itself must survive ---
# `lib/dispatch.cyr` has ONE top-level definition (`_dispatch_marker`) which the bundle never
# names; `dispatch_do` lives in its private peer. Judging the leaf only by what it literally
# spells drops it — and drops exactly the leaf the consumer cannot compile without.
if [ "$fail" -eq 0 ]; then echo "  ok axis 4: the dispatcher leaf survived on its private peer's symbol"; fi

# --- axis 5 (ANTI-VACUOUS for axis 4): recursion must NOT follow non-private includes ---
# `lib/dispatch.cyr` also includes `lib/plainleaf.cyr`, which is NOT name-prefixed and is a
# leaf in its own right. The small profile never calls `plainleaf_do`. If the peer recursion
# is unguarded, `plainleaf` is kept merely because `dispatch` includes it — which is how a
# real `tls_native` (it includes alloc/string/io/sigil) stayed in sit's read profile while
# none of its 27 symbols appeared in the bundle.
case " $S " in
    *" heavy "*) echo "  FAIL axis 5 (anti-vacuous): 'heavy' kept in [$S] though the small profile never calls heavy_do — the peer recursion is following NON-private includes, so heavy rode in on plainleaf. This is exactly how tls_native survived sit's read profile."; fail=1 ;;
    *) echo "  ok axis 5: a non-prefixed include is not pulled in transitively" ;;
esac

# --- axis 7 (ANTI-VACUOUS for the always-write rule): an EMPTY profile still gets a file ---
# `src/c.cyr` references no leaf, so `bare`'s pruned set is legitimately empty. Under the old
# `vec_len(req_leaves) > 0` guard that wrote NO file — and a consumer following the sidecar
# then silently fell back to the BASE sidecar, the superset the profile exists to avoid.
# Axes 1-3 cannot see this: their profile has a non-empty set, so the guard never fires.
if [ ! -f dist/pf-bare.deps ]; then
    echo "  FAIL axis 7 (anti-vacuous): dist/pf-bare.deps absent — an empty profile writes no sidecar, so a consumer inherits the base's [$B]"; fail=1
else
    BARE=$(leaves dist/pf-bare.deps)
    if [ -n "$BARE" ]; then
        echo "  FAIL axis 7: pf-bare.deps should be empty but carries [$BARE]"; fail=1
    else
        echo "  ok axis 7: an empty profile still emits its sidecar (0 leaves, file present)"
    fi
fi

# --- axis 6: the BASE sidecar is unchanged by all of this ---
case " $B " in
    *" dispatch "*) case " $B " in
        *" plainleaf "*) echo "  ok axis 6: base sidecar still carries both leaves" ;;
        *) echo "  FAIL axis 6: base sidecar lost 'plainleaf' [$B]"; fail=1 ;;
    esac ;;
    *) echo "  FAIL axis 6: base sidecar lost 'dispatch' [$B]"; fail=1 ;;
esac

# --- axes 8-10 (6.6.9): comments and strings are not references; code and includes are ---
# Premise for all three: each profile bundle was built (with no bundle there is no sidecar,
# and "heavy absent" would then pass axis 8 vacuously).
for pr in words chr inc; do
    if [ ! -f "dist/pf-$pr.cyr" ] || [ ! -f "dist/pf-$pr.deps" ]; then
        echo "  FAIL premise: dist/pf-$pr.cyr/.deps not written"; sed -n '1,4p' "$W/$pr.log" | sed 's/^/    /'; fail=1
    fi
done
WD=$(leaves dist/pf-words.deps); CH=$(leaves dist/pf-chr.deps); IN=$(leaves dist/pf-inc.deps)
case " $WD " in
    *" heavy "*) echo "  FAIL axis 8: 'heavy' kept in [$WD] though pf-words names heavy_do only in a comment and a string — the prune is matching raw text (vani: a comment edit took dist/vani-core.deps from 3 leaves to 8)"; fail=1 ;;
    *) echo "  ok axis 8: a comment- or string-only mention keeps no leaf [$WD]" ;;
esac
# ⚠ The PRUNE must keep it, not the compile-verified loop: the loop re-adds a leaf whose symbol
# is undefined, so "heavy is in the sidecar" alone passes even when the blanker ate the call
# (measured: a blanker with no char-literal arm passed that weaker form). `re-added` in the log
# is the loop repairing the prune.
case " $CH " in
    *" heavy "*) if grep -q 're-added' "$W/chr.log"; then
            echo "  FAIL axis 9 (anti-vacuous for 8): 'heavy' was dropped by the prune and only re-added by the verify loop — a char literal was read as a string opening and blanked the call after it"; fail=1
        else echo "  ok axis 9: a real call after a char literal keeps 'heavy' at the prune"; fi ;;
    *) echo "  FAIL axis 9 (anti-vacuous for 8): 'heavy' missing from [$CH] — e_five() calls heavy_do"; fail=1 ;;
esac
case " $IN " in
    *" heavy "*) echo "  ok axis 10: an explicit include of lib/heavy.cyr keeps 'heavy'" ;;
    *) echo "  FAIL axis 10: 'heavy' missing from [$IN] — the bundle keeps its include of lib/heavy.cyr, so a consumer following this sidecar cannot resolve it"; fail=1 ;;
esac

# --- axes 11-15 (6.6.10): every declaration spelling keeps its leaf AT THE PRUNE ---
spelled() {   # $1 profile, $2 leaf, $3 axis, $4 spelling
    if [ ! -f "dist/pf-$1.deps" ]; then
        echo "  FAIL axis $3: dist/pf-$1.deps not written"; sed -n '1,4p' "$W/$1.log" | sed 's/^/    /'; fail=1; return
    fi
    L=$(leaves "dist/pf-$1.deps")
    case " $L " in
        *" $2 "*) if grep -q 're-added' "$W/$1.log"; then
                echo "  FAIL axis $3: '$2' ($4) was dropped by the prune and only re-added by the verify loop"; fail=1
            else echo "  ok axis $3: a $4 leaf is kept by the prune itself [$L]"; fi ;;
        *) echo "  FAIL axis $3: '$2' missing from [$L] — its only symbol is spelled '$4', and the sidecar was written without it"; fail=1 ;;
    esac
}
spelled attr attrleaf 11 "#inline fn"
spelled ind  indleaf  12 "indented top-level fn"
spelled pubp publeaf  13 "pub fn"
spelled tab  tableaf  14 "fn<TAB>"
spelled enm  enumleaf 15 "enum member"

# --- axis 16 (6.6.10): a declaration the reader cannot see is a HARD ERROR, not a short file ---
# skewleaf.cyr opens a brace in each of two #ifdef arms and closes one, so the depth-0 reader
# is still at depth 1 when `skewleaf_do` is declared. The verify loop used to read the
# still-undefined symbol as "not stdlib" (`raw == 0 → continue`) and write the sidecar
# without the leaf, at rc 0.
if [ "$SKEW_RC" -eq 0 ]; then
    echo "  FAIL axis 16: distlib skew exited 0 — the leaf it needs is declared where the reader cannot see it, and it wrote the sidecar anyway [$(leaves dist/pf-skew.deps 2>/dev/null)]"; fail=1
elif ! grep -q "skewleaf_do" "$W/skew.log" || ! grep -q "skewleaf.cyr" "$W/skew.log"; then
    echo "  FAIL axis 16: distlib skew failed (rc $SKEW_RC) without naming the symbol and the file"; sed -n '1,6p' "$W/skew.log" | sed 's/^/    /'; fail=1
elif [ -f dist/pf-skew.deps ]; then
    echo "  FAIL axis 16: distlib skew failed but still left dist/pf-skew.deps behind"; fail=1
else
    echo "  ok axis 16: an unreadable declaration is a hard error naming skewleaf_do and skewleaf.cyr (rc $SKEW_RC)"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: distlib-profile-sidecar"; exit 1; }
echo "PASS: distlib-profile-sidecar — profiles emit a sidecar scoped to their own references"
