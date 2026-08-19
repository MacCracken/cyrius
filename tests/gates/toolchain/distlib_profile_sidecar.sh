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
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CLI="$ROOT/build/cyrius"
[ -x "$CLI" ] || CLI="$HOME/.cyrius/bin/cyrius"
[ -x "$CLI" ] || { echo "SKIP: cyrius CLI missing"; exit 0; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
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
stdlib = ["dispatch", "plainleaf", "heavy"]

[lib]
modules = ["src/a.cyr", "src/b.cyr", "src/c.cyr"]

[lib.small]
modules = ["src/a.cyr"]

[lib.bare]
modules = ["src/c.cyr"]
EOF

# The fake leaves must live where [deps].stdlib resolves them (CYRIUS_HOME/lib) AND where
# the prune's own scan looks first (the package's ./lib).
cp lib/dispatch.cyr lib/dispatch_impl.cyr lib/plainleaf.cyr lib/heavy.cyr "$W/home/lib/"

"$CLI" distlib      > "$W/base.log"  2>&1 || true
"$CLI" distlib small > "$W/prof.log" 2>&1 || true
"$CLI" distlib bare  > "$W/bare.log" 2>&1 || true

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

[ "$fail" -eq 0 ] || { echo "FAIL: distlib-profile-sidecar"; exit 1; }
echo "PASS: distlib-profile-sidecar — profiles emit a sidecar scoped to their own references"
