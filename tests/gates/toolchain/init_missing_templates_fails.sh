#!/bin/sh
# Gate: `cyrius init` / `cyrius port` with missing templates FAIL, name the directory they looked
# in, and never print the success lines. CHANGELOG [6.7.9]
#
# ⛔ THE DEFECT (filed 2026-10-08, cyrius-init <= 6.7.8). `_rw_wia` — the writer behind EVERY
# file of an `init` scaffold — called _render_template / _write_file itself and returned their
# -1 to call sites that never look. `_rw` (port's writer) counts each failure in `_rw_fails`,
# which `_rw_report` turns into exit 1; `_rw_wia` counted nothing. So with the template
# directory absent (a source install before 6.7.7, a hand-built bin/, any partial tree)
# `cyrius-init demo` printed 21 "missing template" lines, then `Created demo/`, the next steps,
# and exited 0 — a broken install reported success, and the user found the empty project later.
#
# AXES — the scaffolder is built from the tree into <root>/bin/, so its own templates resolution
# (<root>/programs/cyrius-init-templates) lands inside the scratch dir, which each axis shapes:
#   1  an EMPTY template dir, greenfield: exit 1, no "Created demo/", the report counts the
#      missing templates (equal to the "missing template" lines printed) and NAMES the dir
#   2  NO template dir, greenfield: exit 1, the dir named, and NOTHING created (a retry after a
#      reinstall must not meet "directory 'demo' already exists")
#   3  a PARTIAL tree (one template removed): exit 1, that template named, "1 template(s)
#      missing", no "Created", and the files it could render were written
#   4  an EMPTY template dir, in-place (`init .` in an empty dir): exit 1, no "Initialized"
#   5  a WRITE failure in in-place mode (docs/adr is a FILE, so docs/adr/README.md cannot be
#      written — ENOTDIR, which holds as root too): exit 1, "cannot write docs/adr/README.md",
#      and no "template(s) missing" line (the templates were all there)
#   6  in-place on a COMPLETE project with no template dir: exit 0 — every file is skipped and
#      none needs a template, so the greenfield-only refusal of axis 2 must not reach it
#   7  the full template tree, greenfield: exit 0 and "Created demo/" (anti-vacuous: the fix
#      did not just make init fail)
#   8  `port` with NO template dir: exit 1, the dir named, and the source tree NOT moved aside
#      (port moves it into rust-old/ before it renders anything)
#   9  `port` with a PARTIAL tree (main-cyr-port, ci.yml removed): exit 1, no "Created
#      src/main.cyr" / "Created .github/workflows/ci.yml" for the files it did not write, no
#      "ready for porting", while "Created cyrius.cyml" (written) still prints
#
# MUTATION LEDGER (6.7.9 quick 13, measured in the lane worktree; each mutant applied alone to the
# fixed source, the real tree 0 RED):
#   * the pre-fix programs/cyrius-init.cyr                      -> 26 RED (axes 1-5, 8, 9)
#   * _rw_wia's old body (render / write itself, uncounted)     -> 15 RED (axes 1, 3, 4, 5)
#   * the greenfield `_require_templates` call removed          ->  2 RED (axis 2: dir unnamed, demo/ made)
#   * init's `if (_rw_fails != 0) return _rw_report()` removed  ->  5 RED (axes 1, 3, 4, 5: success lines)
#   * _rw_report's "missing from <dir>" dropped                 ->  4 RED (axes 1, 3, 4, 9)
#   * port's `_require_templates` call removed                  ->  3 RED (axis 8: the source moved aside)
#   * port's two Created lines made unconditional again         ->  2 RED (axis 9)
#   * port's early `_rw_report` return removed                  ->  1 RED (axis 9: "ready for porting")
#   * the template-dir refusal made unconditional (in-place too)->  3 RED (axis 6)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: init_missing_templates_fails: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$D" 2>/dev/null; rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CC" ] || { echo "FAIL: init_missing_templates_fails: $CC missing"; exit 1; }
SRC_TPL="$ROOT/programs/cyrius-init-templates"
[ -d "$SRC_TPL" ] || { echo "FAIL: init_missing_templates_fails: $SRC_TPL missing"; exit 1; }
NTPL=$(find "$SRC_TPL" -maxdepth 1 -type f | grep -c . || true)
[ "$NTPL" -ge 20 ] || { echo "FAIL: init_missing_templates_fails: only $NTPL templates in the tree (floor 20)"; exit 1; }

mkdir -p "$D/root/bin" "$D/root/programs" "$D/home"
BIN="$D/root/bin/cyrius-init"
if ! "$CC" < "$ROOT/programs/cyrius-init.cyr" > "$BIN" 2> "$D/build.err"; then
    echo "FAIL: init_missing_templates_fails: programs/cyrius-init.cyr did not compile"
    sed 's/^/    /' "$D/build.err"
    exit 1
fi
chmod +x "$BIN"
SZ=$(wc -c < "$BIN")
[ "$SZ" -ge 4096 ] || { echo "FAIL: init_missing_templates_fails: cyrius-init compiled to $SZ bytes"; exit 1; }
echo "built cyrius-init: $SZ bytes"
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")
TPL="$D/root/programs/cyrius-init-templates"

# run_init <workdir> <args...> — rc in $RC, combined output in $D/out. CYRIUS_HOME points at an
# empty dir so the stdlib vendor step finds nothing of the live store.
run_init() {
    w=$1; shift
    ( cd "$w" && HOME="$D/home" CYRIUS_HOME="$D/home/.cyrius" XDG_CONFIG_HOME="$D/home/.config" \
        CYRIUS_VER="$VER" "$BIN" "$@" ) > "$D/out" 2>&1 && RC=0 || RC=$?
}
has() { grep -cF -- "$1" "$D/out" || true; }
tpl_empty()   { rm -rf "$TPL"; mkdir -p "$TPL"; }
tpl_absent()  { rm -rf "$TPL"; }
tpl_full()    { rm -rf "$TPL"; cp -r "$SRC_TPL" "$TPL"; }
fresh() { rm -rf "$D/w"; mkdir -p "$D/w"; }

echo "axis 1 — an EMPTY template dir, greenfield:"
tpl_empty; fresh
run_init "$D/w" demo
check "init exits 1" 1 "$RC"
check "no 'Created demo/' line" 0 "$(has 'Created demo/')"
check "no next-steps block" 0 "$(has 'Next steps:')"
check "the INCOMPLETE report" 1 "$(has 'error: scaffold INCOMPLETE')"
NMISS=$(grep -c "^error: missing template '" "$D/out" || true)
check "missing-template lines printed (floor 20)" yes "$([ "$NMISS" -ge 20 ] && echo yes || echo no)"
check "the report counts them and names the dir" 1 "$(has "  $NMISS template(s) missing from $TPL")"

echo "axis 2 — NO template dir, greenfield:"
tpl_absent; fresh
run_init "$D/w" demo
check "init exits 1" 1 "$RC"
check "the dir is named" 1 "$(has "no directory $TPL")"
check "no 'Created demo/' line" 0 "$(has 'Created demo/')"
check "nothing was created" no "$([ -e "$D/w/demo" ] && echo yes || echo no)"

echo "axis 3 — a PARTIAL template tree (license removed), greenfield:"
tpl_full; rm -f "$TPL/license"; fresh
run_init "$D/w" demo
check "init exits 1" 1 "$RC"
check "the missing template is named" 1 "$(has "error: missing template 'license'")"
check "the report: 1 template missing from the dir" 1 "$(has "  1 template(s) missing from $TPL")"
check "no 'Created demo/' line" 0 "$(has 'Created demo/')"
check "the templates it had were rendered (VERSION written)" yes "$([ -s "$D/w/demo/VERSION" ] && echo yes || echo no)"
check "LICENSE not written" no "$([ -e "$D/w/demo/LICENSE" ] && echo yes || echo no)"

echo "axis 4 — an EMPTY template dir, in-place:"
tpl_empty; fresh; mkdir -p "$D/w/ip"
run_init "$D/w/ip" .
check "init . exits 1" 1 "$RC"
check "no 'Initialized' line" 0 "$(has 'Initialized ')"
check "the report names the dir" 1 "$(grep -cF "template(s) missing from $TPL" "$D/out" || true)"

echo "axis 5 — a WRITE failure, in-place (docs/adr is a file):"
tpl_full; fresh; mkdir -p "$D/w/wf/docs"; : > "$D/w/wf/docs/adr"
run_init "$D/w/wf" .
check "init . exits 1" 1 "$RC"
check "the unwritable file is named" 1 "$(has 'error: cannot write docs/adr/README.md')"
check "the INCOMPLETE report" 1 "$(has 'error: scaffold INCOMPLETE')"
check "no 'template(s) missing' line (they were all there)" 0 "$(has 'template(s) missing')"
check "no 'Initialized' line" 0 "$(has 'Initialized ')"

echo "axis 6 — in-place on a COMPLETE project, NO template dir:"
tpl_full; fresh
run_init "$D/w" demo
check "the complete project scaffolds (exit 0)" 0 "$RC"
tpl_absent
run_init "$D/w/demo" .
check "init . exits 0 (every file skipped, none needs a template)" 0 "$RC"
check "files reported as skipped (floor 20)" yes "$([ "$(has '(already exists)')" -ge 20 ] && echo yes || echo no)"
check "no missing-template line" 0 "$(has 'missing template')"
check "the 'Initialized' line" 1 "$(has 'Initialized ')"

echo "axis 7 — the full template tree, greenfield (anti-vacuous):"
tpl_full; fresh
run_init "$D/w" demo
check "init exits 0" 0 "$RC"
check "'Created demo/' printed" 1 "$(has 'Created demo/')"
check "no error line" 0 "$(grep -c '^error' "$D/out" || true)"
check "every template-backed file written (CLAUDE.md)" yes "$([ -s "$D/w/demo/CLAUDE.md" ] && echo yes || echo no)"

mkrs() { mkdir -p "$1/src"; printf '[package]\nname = "demo"\n' > "$1/Cargo.toml"; printf 'fn main() {}\n' > "$1/src/main.rs"; }

echo "axis 8 — port, NO template dir:"
tpl_absent; fresh; mkrs "$D/w/p1"
run_init "$D/w" --__mode=port p1
check "port exits 1" 1 "$RC"
check "the dir is named" 1 "$(has "no directory $TPL")"
check "the source was not moved aside (no rust-old/)" no "$([ -e "$D/w/p1/rust-old" ] && echo yes || echo no)"
check "src/main.rs still in place" yes "$([ -f "$D/w/p1/src/main.rs" ] && echo yes || echo no)"

echo "axis 9 — port, a PARTIAL template tree (main-cyr-port, ci.yml removed):"
tpl_full; rm -f "$TPL/main-cyr-port" "$TPL/ci.yml"; fresh; mkrs "$D/w/p2"
run_init "$D/w" --__mode=port p2
check "port exits 1" 1 "$RC"
check "no 'Created src/main.cyr' for the file it did not write" 0 "$(has 'Created src/main.cyr')"
check "no 'Created .github/workflows/ci.yml' either" 0 "$(has 'Created .github/workflows/ci.yml')"
check "'Created cyrius.cyml' for the file it did write" 1 "$(has 'Created cyrius.cyml')"
check "no 'ready for porting'" 0 "$(has 'ready for porting')"
check "the report: 2 templates missing from the dir" 1 "$(has "  2 template(s) missing from $TPL")"

echo ""
if [ "$fails" -eq 0 ]; then
    echo "PASS: init_missing_templates_fails — missing templates and failed writes fail init and port, naming the dir"
    exit 0
fi
echo "FAIL: init_missing_templates_fails — $fails check(s) failed"
exit 1
