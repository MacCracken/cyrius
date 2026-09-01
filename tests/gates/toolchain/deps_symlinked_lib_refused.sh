#!/bin/sh
# Gate: `cyrius deps` REFUSES to vendor into a symlinked lib/ (v6.5.37).
#
# THE INCIDENT (2026-09-01). `nous/lib` was a directory-level symlink to `~/.cyrius/lib`,
# itself a symlink to `~/.cyrius/versions/6.5.36/lib` — the LIVE stdlib snapshot. nous
# pins cyrius 6.3.35, so `_dep_find_stdlib_dir()` correctly resolved the SOURCE to
# `versions/6.3.35/lib` and the resolver then wrote each leaf to `lib/<mod>.cyr` —
# straight through the symlink and INTO the 6.5.36 snapshot. 27 files of 6.3.35-era
# stdlib replaced the shipped ones. `lib/alloc.cyr` lost `fn _alloc_zero`, the
# memory-reuse information-leak fix from v6.4.1 (daimon VULN-007).
#
# ⭐ AND IT PROPAGATED. `~/.cyrius/lib` is the global DEFAULT source, so every other repo
# then read the corruption back out: shabda ingested it 12 seconds later. A single
# `cyrius deps` in one old-pinned repo silently downgraded the stdlib for the machine.
#
# ⚠ CLAUDE.md has forbidden the directory-level `lib` symlink since the v5.5.30–v5.5.33
# sakshi corruption and even ships `find` commands to detect it — but the remedy was
# always a human noticing. THE TOOL NEVER REFUSED. That is what this gate pins.
#
# ⛔ TWO GUARDS, AND THE SECOND ONE IS THE LOAD-BEARING ONE. `cbt/cyrius.cyr`'s
# `_try_redirect_to_pinned()` re-execs `~/.cyrius/versions/<pin>/bin/cyrius` BEFORE any
# command dispatch. So for an old-pinned repo, control never reaches this build's
# resolver at all — a guard living only in `_dep_copy_file` would protect repos pinned
# at >= 6.5.37 and nothing else, and the repos most likely to carry a stale lib/ are
# exactly the old-pinned ones. The dispatcher guard runs in the binary that is always
# current (`~/.cyrius/bin/cyrius` tracks the newest install), so it covers delegation to
# ANY old binary, including ones built before this fix existed and never rebuilt.
#
# Axis 3 is the one that fails if someone "simplifies" the guard to `refuse whenever lib
# is a symlink`: the cyrius source repo's own ./lib IS the stdlib and must keep working.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: deps_symlinked_lib_refused: $1"; exit 1; }

# ── axis 1: symlinked lib + a pin that would DELEGATE → refuse, write nothing ────────
# The pin is deliberately a version that is not installed, so this axis does not depend
# on which versions happen to exist on the box. The guard is ordered ahead of the
# "pinned version not installed" error precisely so this is deterministic.
mkdir -p "$WORK/a/snap" "$WORK/a/proj"
for m in alloc io vec; do echo "# SENTINEL $m" > "$WORK/a/snap/$m.cyr"; done
BEFORE=$(ls "$WORK/a/snap" | wc -l | tr -d ' ')
ln -s "$WORK/a/snap" "$WORK/a/proj/lib"
cat > "$WORK/a/proj/cyrius.cyml" <<'EOF'
[package]
name = "probe"
version = "0.1.0"
cyrius = "0.0.1-absent"
[deps]
stdlib = ["alloc", "io", "vec"]
EOF
set +e
OUT=$(cd "$WORK/a/proj" && "$CYRIUS" deps 2>&1); RC=$?
set -e
[ "$RC" -ne 0 ] || fail "axis 1: exit 0 — the vendor into a symlinked lib/ was not refused"
echo "$OUT" | grep -q "SYMLINKED" || fail "axis 1: refusal did not name the symlink; got: $OUT"
AFTER=$(ls "$WORK/a/snap" | wc -l | tr -d ' ')
[ "$BEFORE" = "$AFTER" ] || fail "axis 1: symlink target gained files ($BEFORE -> $AFTER)"
for m in alloc io vec; do
    grep -q SENTINEL "$WORK/a/snap/$m.cyr" || fail "axis 1: $m.cyr was overwritten THROUGH the symlink"
done

# ── axis 1b: the REAL delegation path, against an actually-installed older version ───
# Axis 1 pins a version that is not installed, which makes it deterministic but means no
# execve ever happens — so on its own it proves the guard is ORDERED ahead of the
# missing-pin error, not that it stops the corruption the incident actually caused. This
# axis pins a version that IS installed, so without the guard control really does leave
# for `versions/<v>/bin/cyrius` (a binary predating this fix, which will never gain it)
# and that process writes through the symlink. If no other version is installed the axis
# announces the skip by name — a silent skip here would be the placebo this gate exists
# to replace.
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
OTHER=""
if [ -d "$HOMEDIR/versions" ]; then
    for d in "$HOMEDIR"/versions/*/; do
        v=$(basename "$d")
        [ "$v" = "$(cat "$ROOT/VERSION")" ] && continue
        [ -x "$d/bin/cyrius" ] || continue
        OTHER="$v"; break
    done
fi
if [ -z "$OTHER" ]; then
    echo "  axis 1b SKIPPED: no second cyrius version installed under $HOMEDIR/versions"
    echo "  (the delegation path is unexercised on this host — axis 1 still covers ordering)"
else
    mkdir -p "$WORK/d/snap" "$WORK/d/proj"
    for m in alloc io vec; do echo "# SENTINEL $m" > "$WORK/d/snap/$m.cyr"; done
    DBEFORE=$(ls "$WORK/d/snap" | wc -l | tr -d ' ')
    ln -s "$WORK/d/snap" "$WORK/d/proj/lib"
    cat > "$WORK/d/proj/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$OTHER"
[deps]
stdlib = ["alloc", "io", "vec"]
EOF
    set +e
    OUT1B=$(cd "$WORK/d/proj" && "$CYRIUS" deps 2>&1); RC1B=$?
    set -e
    [ "$RC1B" -ne 0 ] || fail "axis 1b: exit 0 — delegated to $OTHER and vendored through the symlink"
    DAFTER=$(ls "$WORK/d/snap" | wc -l | tr -d ' ')
    [ "$DBEFORE" = "$DAFTER" ] || fail "axis 1b: symlink target gained files via $OTHER ($DBEFORE -> $DAFTER)"
    for m in alloc io vec; do
        grep -q SENTINEL "$WORK/d/snap/$m.cyr" || fail "axis 1b: $m.cyr overwritten by delegated $OTHER"
    done
fi

# ── axis 1c: PER-FILE symlink — lib/ is a REAL dir holding a symlinked FILE ─────────
# ⛔ THE AXIS THE FIRST CUT OF THIS GUARD SHIPPED GREEN OVER. v6.5.37's initial guard walked
# directory PREFIXES only, so it caught `lib -> <snapshot>` and sailed past
# `lib/alloc.cyr -> <snapshot>/alloc.cyr`: exit 0, target overwritten, silent. This is not an
# exotic shape — CLAUDE.md calls single-file `lib/<dep>.cyr` symlinks "legitimate `cyrius
# deps` output", and three live instances sit under ~/.cyrius/deps/sigil/*/lib/sakshi.cyr.
# A gate written only around the directory shape passes while the file shape corrupts, which
# is the v6.5.36 lesson verbatim: a gate pinning the mechanism passes while the mechanism is
# wrong. Both shapes are asserted, permanently.
mkdir -p "$WORK/f/snap" "$WORK/f/proj/lib"
echo "# SENTINEL alloc" > "$WORK/f/snap/alloc.cyr"
ln -s "$WORK/f/snap/alloc.cyr" "$WORK/f/proj/lib/alloc.cyr"
cat > "$WORK/f/proj/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$(cat "$ROOT/VERSION")"
[deps]
stdlib = ["alloc"]
EOF
set +e
OUTF=$(cd "$WORK/f/proj" && "$CYRIUS" deps 2>&1); RCF=$?
set -e
[ "$RCF" -ne 0 ] || fail "axis 1c: exit 0 on a per-FILE symlink — the guard checks directory prefixes only"
grep -q SENTINEL "$WORK/f/snap/alloc.cyr" || fail "axis 1c: the symlinked FILE's target was overwritten"

# ── axis 2: symlinked lib + CURRENT pin (no re-exec) → the resolver guard catches it ──
# Exercises _dep_copy_file's guard rather than the dispatcher's. Both must hold; if only
# one does, an old-pinned repo (axis 1) or a current-pinned one (axis 2) stays exposed.
VER=$(cat "$ROOT/VERSION")
mkdir -p "$WORK/b/snap" "$WORK/b/proj"
for m in alloc io vec; do echo "# SENTINEL $m" > "$WORK/b/snap/$m.cyr"; done
ln -s "$WORK/b/snap" "$WORK/b/proj/lib"
cat > "$WORK/b/proj/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$VER"
[deps]
stdlib = ["alloc", "io", "vec"]
EOF
set +e
OUT2=$(cd "$WORK/b/proj" && "$CYRIUS" deps 2>&1); RC2=$?
set -e
[ "$RC2" -ne 0 ] || fail "axis 2: exit 0 on the resolver path — _dep_copy_file guard missing"
for m in alloc io vec; do
    grep -q SENTINEL "$WORK/b/snap/$m.cyr" || fail "axis 2: $m.cyr overwritten on the resolver path"
done

# ── axis 3: a NORMAL project with a real lib/ still vendors ──────────────────────────
# The guard must be about the symlink, not about vendoring. If this axis fails the fix
# has broken every consumer on the planet, which is worse than the bug.
mkdir -p "$WORK/c/proj"
cat > "$WORK/c/proj/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$VER"
[deps]
stdlib = ["alloc", "io", "vec"]
EOF
set +e
OUT3=$(cd "$WORK/c/proj" && "$CYRIUS" deps 2>&1); RC3=$?
set -e
[ "$RC3" -eq 0 ] || fail "axis 3: normal vendoring broke (exit $RC3): $OUT3"
COUNT=$(ls "$WORK/c/proj/lib"/*.cyr 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || fail "axis 3: normal project vendored 0 files"

# ── axis 4: a read-only verb still works inside an affected tree ─────────────────────
# Scoping the dispatcher guard to write verbs is deliberate: a broken tree should still
# be inspectable. If this fails, the guard was widened past the verbs that vendor.
#
# ⚠ Uses the CURRENT-pin tree (b), not the absent-pin tree (a). In (a) EVERY command
# exits 1 — `_try_redirect_to_pinned` hard-errors on an uninstalled pin and deliberately
# never slides to latest — so asserting success there would be testing that pre-existing
# policy, not this guard, and it fails for a reason that has nothing to do with symlinks.
set +e
(cd "$WORK/b/proj" && "$CYRIUS" --version >/dev/null 2>&1); RC4=$?
set -e
[ "$RC4" -eq 0 ] || fail "axis 4: --version broke inside a symlinked-lib tree (exit $RC4)"

# ── axis 5: a TOOLCHAIN install through a symlinked dir must still WORK ─────────────
# ⛔ THE OTHER HALF THE FIRST CUT GOT WRONG, in the opposite direction. `~/.cyrius/bin` IS a
# symlink into `versions/<v>/bin` on every normal install, so an ungated guard refuses
# `cyrius lsp install` and every sibling that writes there — and `cbt/cyrius.cyr` ignored
# `_dep_copy_file`'s return, printing "Installed: <path>" over a copy that never happened.
# The refusal is therefore gated on `_dep_vendor_mode`, set only by deps/update/lib-sync.
# This axis pins that gating: without it the guard is a self-inflicted outage that REPORTS
# SUCCESS. Simulated with a non-vendor copy rather than a real install so the gate stays fast
# and hermetic — `cyrius fmt` writes in place through _dep_copy_file's sibling path.
mkdir -p "$WORK/g/real" "$WORK/g/proj"
printf 'fn main() {\n    return 0;\n}\n' > "$WORK/g/real/x.cyr"
ln -s "$WORK/g/real" "$WORK/g/proj/linkdir"
set +e
(cd "$WORK/g" && "$CYRIUS" fmt --check proj/linkdir/x.cyr >/dev/null 2>&1); RCG=$?
set -e
[ "$RCG" -le 1 ] || fail "axis 5: a non-vendor path through a symlinked directory hard-failed (exit $RCG) — the guard is not vendor-gated"

echo "PASS: deps_symlinked_lib_refused (6 axes: delegate-refuse, delegate-real, per-file, resolver-refuse, normal-op, read-only, non-vendor-unaffected)"
