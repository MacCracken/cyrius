#!/bin/sh
# released_slot_written_from_tag.sh — a RELEASED version's install slot is written from
# its tag, never from a drifted tree; the store can be audited against the tags.
#
# v6.6.4. `~/.cyrius/versions/<v>` is what a consumer pin MEANS. Four writers keyed a slot
# write on the working-tree VERSION (or `current`) with no notion of "released":
# `install.sh --refresh-only` (via version-bump's same-version path and the CLAUDE.md
# hand-copy recipe), `cyrius pulsar`, `cyrius lsp`. Between a tag and the next bump VERSION
# still names the released version, so every mid-slot refresh wrote the in-progress tree
# under the released name — hisab found the installed "6.6.2" stdlib was 6.6.3's byte for
# byte (12 files), "6.6.1" carried three 6.6.2 files, and the review found "6.6.3"'s
# cross-compilers built from the bump commit — the tag's direct PARENT, missing its fix.
#
# The guard (install.sh `_released_slot_guard`, mirrored for `cyrius lsp`): refuse when the
# tag exists AND the tree has moved past it AND the destination is LIVE (the slot exists, or
# the home is $HOME/.cyrius). Tree == tag proceeds; untagged proceeds; a throwaway home with
# no slot proceeds with no override; CYRIUS_REFRESH_RELEASED=1 forces it.
#
# Everything here runs in a mktemp mini-repo (its own git, its own tag) against a mktemp
# store — never the live ~/.cyrius. Expected-failure calls use `if cmd; then ...; else
# rc=$?; fi` (a bare `cmd; rc=$?` is killed by `set -e` — the CLAUDE.md CI shell-loop rule).
#
# Mutation ledger (MEASURED after the bite-4 review in a scratch ROOT — re-run, don't trust):
#   drop the `_released_slot_guard` call in install.sh        → axes 1 2 3 4 4c 4d 4f red
#   drop the slot-exists half of "live"                       → axes 1 4d 4f red
#   drop the `$HOME/.cyrius` half of "live"                    → axis 4c red
#   drop the untracked-lib conjunct of "drifted"               → axis 4d red
#   drop the SOURCE_COMMIT write                               → axes 2 4 4b 4e red
#   drop the `_released_slot_guard_current` call in cyrius.cyr → axes 5 5c red
#   revert pulsar's step 4 to its own copy loop (verbatim)     → axis 6 red
#   make verify-store never set `bad`                          → axis 7 red
#   make --restore skip the lib loop                           → axis 8 red
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: released_slot_written_from_tag: build/cycc missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: released_slot_written_from_tag: git not found"; exit 0; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: released_slot_written_from_tag: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

# ── a mini cyrius repo: VERSION 9.9.9 tagged, one lib file, a tracked build/cycc ─────────
R="$W/repo"; mkdir -p "$R/lib" "$R/build" "$R/scripts" "$R/programs" "$R/src"
cp "$ROOT/scripts/install.sh" "$R/scripts/install.sh"
cp "$ROOT/scripts/verify-store.sh" "$R/scripts/verify-store.sh"
printf '9.9.9\n' > "$R/VERSION"
printf 'fn probe_lib(): i64 { return 1; }\n' > "$R/lib/probe.cyr"
printf 'tracked-compiler-bytes-v1\n' > "$R/build/cycc"; chmod +x "$R/build/cycc"
# the manifest pins the WRAPPER'S OWN version so `_try_redirect_to_pinned` returns early and
# the tree-built cbt runs here (a foreign pin would demand an installed slot for it)
cat > "$R/cyrius.cyml" <<EOF
[package]
name = "mini"
version = "9.9.9"
language = "cyrius"
cyrius = "$(tr -d '[:space:]' < "$ROOT/VERSION")"

[release]
bins = []
cross_bins = []
scripts = []
EOF
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm "9.9.9" && git tag 9.9.9 )

# ── axis 1: tagged + drifted + LIVE destination (slot exists) → refused, nothing written ──
H1="$W/home1"; mkdir -p "$H1/versions/9.9.9/lib"; printf 'released bytes\n' > "$H1/versions/9.9.9/lib/probe.cyr"
printf 'fn probe_lib(): i64 { return 2; }\n' > "$R/lib/probe.cyr"     # the drift
rc=0; if ( cd "$R" && CYRIUS_HOME="$H1" sh scripts/install.sh --refresh-only > "$W/a1.out" 2> "$W/a1.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q "CUT RELEASE" "$W/a1.err" && grep -q "git tag -f 9.9.9 HEAD" "$W/a1.err" \
   && [ "$(cat "$H1/versions/9.9.9/lib/probe.cyr")" = "released bytes" ] && [ ! -f "$H1/versions/9.9.9/SOURCE_COMMIT" ]; then
    ok "tagged+drifted into a live slot: refused (rc=$rc), names the re-cut path, slot untouched"
else bad "axis 1 (rc=$rc): $(head -2 "$W/a1.err")"; fi

# ── axis 2: throwaway home (no slot) + drifted → proceeds with NO override, stamped dirty/no ──
H2="$W/home2"; mkdir -p "$H2"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H2" sh scripts/install.sh --refresh-only > "$W/a2.out" 2> "$W/a2.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 2' "$H2/versions/9.9.9/lib/probe.cyr" \
   && grep -q '^tree-matches-tag: no' "$H2/versions/9.9.9/SOURCE_COMMIT" && grep -q ' dirty$' "$H2/versions/9.9.9/SOURCE_COMMIT"; then
    ok "throwaway home: proceeds without an override; SOURCE_COMMIT says dirty + tree-matches-tag: no"
else bad "axis 2 (rc=$rc): $(head -2 "$W/a2.err") / $(cat "$H2/versions/9.9.9/SOURCE_COMMIT" 2>/dev/null)"; fi

# ── axis 3: the override writes the live slot (throwaways only — but it must work) ──────
rc=0; if ( cd "$R" && CYRIUS_HOME="$H1" CYRIUS_REFRESH_RELEASED=1 sh scripts/install.sh --refresh-only > "$W/a3.out" 2> "$W/a3.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 2' "$H1/versions/9.9.9/lib/probe.cyr" && grep -q 'CYRIUS_REFRESH_RELEASED=1' "$W/a3.out" "$W/a3.err"; then
    ok "CYRIUS_REFRESH_RELEASED=1: forces the write and says so"
else bad "axis 3 (rc=$rc)"; fi

# ── axis 4: tree == tag → the released slot is re-populated (idempotent, e.g. post-tag) ──
( cd "$R" && git checkout -q -- lib/probe.cyr )
H4="$W/home4"; mkdir -p "$H4/versions/9.9.9/lib"; printf 'stale\n' > "$H4/versions/9.9.9/lib/probe.cyr"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H4" sh scripts/install.sh --refresh-only > "$W/a4.out" 2> "$W/a4.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 1' "$H4/versions/9.9.9/lib/probe.cyr" && grep -q '^tree-matches-tag: yes' "$H4/versions/9.9.9/SOURCE_COMMIT"; then
    ok "tree == tag: proceeds into the live slot (reconcile after tagging), stamp says matches"
else bad "axis 4 (rc=$rc): $(head -2 "$W/a4.err")"; fi

# ── axis 4b: untagged VERSION (the in-flight bump) + drifted + live → proceeds ───────────
printf '9.9.10\n' > "$R/VERSION"; printf 'fn probe_lib(): i64 { return 3; }\n' > "$R/lib/probe.cyr"
H4b="$W/home4b"; mkdir -p "$H4b/versions/9.9.10/lib"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H4b" sh scripts/install.sh --refresh-only > "$W/a4b.out" 2> "$W/a4b.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 3' "$H4b/versions/9.9.10/lib/probe.cyr" && grep -q '^tree-matches-tag: untagged' "$H4b/versions/9.9.10/SOURCE_COMMIT"; then
    ok "untagged VERSION: proceeds (that is the bump path), stamp says untagged"
else bad "axis 4b (rc=$rc): $(head -2 "$W/a4b.err")"; fi
( cd "$R" && git checkout -q -- lib/probe.cyr VERSION )

# ── axis 4c: the home IS the user's store (no slot yet, spelled with a trailing slash and a
#    symlinked $HOME) + tagged + drifted → refused: "live" is not only "slot exists" ─────────
FH="$W/fakehome"; mkdir -p "$FH/.cyrius/versions"; ln -s "$FH" "$W/fakehome-link"
printf 'fn probe_lib(): i64 { return 2; }\n' > "$R/lib/probe.cyr"
rc=0; if ( cd "$R" && HOME="$W/fakehome-link" CYRIUS_HOME="$FH/.cyrius/" sh scripts/install.sh --refresh-only > "$W/a4c.out" 2> "$W/a4c.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q "CUT RELEASE" "$W/a4c.err" && [ ! -d "$FH/.cyrius/versions/9.9.9" ]; then
    ok "the user's own store (trailing slash, symlinked HOME) is live even with no slot: refused"
else bad "axis 4c (rc=$rc): $(head -1 "$W/a4c.err")"; fi
( cd "$R" && git checkout -q -- lib/probe.cyr )

# ── axis 4d: tree == tag EXCEPT an untracked lib file → that is drift (the copy loop is find) ──
printf 'fn stray(): i64 { return 0; }\n' > "$R/lib/stray.cyr"
H4d="$W/home4d"; mkdir -p "$H4d/versions/9.9.9/lib"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H4d" sh scripts/install.sh --refresh-only > "$W/a4d.out" 2> "$W/a4d.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q "CUT RELEASE" "$W/a4d.err" && [ ! -f "$H4d/versions/9.9.9/lib/stray.cyr" ]; then
    ok "an untracked lib file counts as drift: refused into a live slot"
else bad "axis 4d (rc=$rc): $(head -1 "$W/a4d.err")"; fi
rm -f "$R/lib/stray.cyr"

# ── axis 4e: a REUSED throwaway (its stamp says the inputs had drifted) is refreshed again ──
printf 'fn probe_lib(): i64 { return 5; }\n' > "$R/lib/probe.cyr"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H2" sh scripts/install.sh --refresh-only > "$W/a4e.out" 2> "$W/a4e.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 5' "$H2/versions/9.9.9/lib/probe.cyr"; then
    ok "a throwaway refreshed twice: the second refresh proceeds (its stamp marks it a dev slot)"
else bad "axis 4e (rc=$rc): $(head -1 "$W/a4e.err")"; fi
( cd "$R" && git checkout -q -- lib/probe.cyr )

# ── axis 4f: a clone with NO tags cannot tell "not cut" from "not fetched" → refuses a live slot ──
RN="$W/repo-notags"; git clone -q --no-tags "$R" "$RN" 2>/dev/null
printf 'fn probe_lib(): i64 { return 6; }\n' > "$RN/lib/probe.cyr"
H4f="$W/home4f"; mkdir -p "$H4f/versions/9.9.9/lib"; printf 'released bytes\n' > "$H4f/versions/9.9.9/lib/probe.cyr"
rc=0; if ( cd "$RN" && CYRIUS_HOME="$H4f" sh scripts/install.sh --refresh-only > "$W/a4f.out" 2> "$W/a4f.err" ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q "NO tags" "$W/a4f.err" && [ "$(cat "$H4f/versions/9.9.9/lib/probe.cyr")" = "released bytes" ]; then
    ok "a --no-tags clone refuses a live slot (fetch tags first) instead of failing open"
else bad "axis 4f (rc=$rc): $(head -1 "$W/a4f.err")"; fi
rc=0; if ( cd "$RN" && CYRIUS_HOME="$H4f" sh scripts/verify-store.sh > "$W/a4f2.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 3 ] && grep -q 'NOTHING was judged' "$W/a4f2.out"; then
    ok "verify-store in a --no-tags clone says nothing was judged (exit 3), not a vacuous green"
else bad "axis 4f2 (rc=$rc): $(tail -2 "$W/a4f2.out")"; fi

# ── axis 5: `cyrius lsp` refuses to write bin/ of a live released slot — DETERMINISTIC: the
#    guard runs BEFORE the compile and reads git from the CWD, so the mini-repo (tag 9.9.9,
#    drifted tree, current = 9.9.9, slot exists) exercises it whatever this tree's state ────
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) || { bad "could not build cbt/cyrius.cyr"; }
chmod +x "$W/cyrius" 2>/dev/null || true
if [ -x "$W/cyrius" ]; then
    printf 'fn probe_lib(): i64 { return 7; }\n' > "$R/lib/probe.cyr"
    H5="$W/home5"; mkdir -p "$H5/versions/9.9.9/bin"; printf '9.9.9\n' > "$H5/current"
    rc=0; if ( cd "$R" && CYRIUS_HOME="$H5" "$W/cyrius" lsp > "$W/a5.out" 2> "$W/a5.err" ); then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && grep -q "CUT RELEASE" "$W/a5.err" && ! grep -q "Building" "$W/a5.out" \
       && [ ! -f "$H5/versions/9.9.9/bin/cyrius-lsp" ] && [ ! -f "$H5/bin/cyrius-lsp" ]; then
        ok "cyrius lsp: refused for the live released slot before compiling, nothing written"
    else bad "axis 5 (rc=$rc): $(grep -m1 -v '^note' "$W/a5.err")"; fi
    # no `current` at all, but bin/ is a symlink INTO the released slot → still refused
    H5c="$W/home5c"; mkdir -p "$H5c/versions/9.9.9/bin"; ln -s "$H5c/versions/9.9.9/bin" "$H5c/bin"
    rc=0; if ( cd "$R" && CYRIUS_HOME="$H5c" "$W/cyrius" lsp > "$W/a5c.out" 2> "$W/a5c.err" ); then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && grep -q "CUT RELEASE" "$W/a5c.err" && [ ! -f "$H5c/versions/9.9.9/bin/cyrius-lsp" ]; then
        ok "cyrius lsp: no \`current\` but bin/ links into the released slot: refused"
    else bad "axis 5c (rc=$rc): $(grep -m1 -v '^note' "$W/a5c.err")"; fi
    ( cd "$R" && git checkout -q -- lib/probe.cyr )
    # a throwaway home (no slot, current untagged) proceeds — run from THIS repo so the
    # compile has a real programs/cyrius-lsp.cyr + lib/ to work with
    H5b="$W/home5b"; mkdir -p "$H5b/bin"; printf '0.0.0-throwaway\n' > "$H5b/current"
    rc=0; if ( cd "$ROOT" && CYRIUS_HOME="$H5b" "$W/cyrius" lsp > "$W/a5b.out" 2> "$W/a5b.err" ); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && [ -x "$H5b/bin/cyrius-lsp" ]; then ok "cyrius lsp: a throwaway home proceeds and installs"; else bad "axis 5b (rc=$rc): $(grep -m1 -v '^note' "$W/a5b.err")"; fi
fi

# ── axis 6: pulsar has ONE writer — it delegates to install.sh and carries no copy loop.
#    Checked in the COMPILED wrapper (a comment cannot satisfy it) plus the absence of the
#    old store-writer idioms in the source (`"/versions/"` path building, `syscall(88` symlinks,
#    `dir_list(str_from("lib"))` — the top-level-only lib copy), and the byte-exact fixpoint. ──
if [ -x "$W/cyrius" ] && grep -a -q 'sh scripts/install.sh --refresh-only' "$W/cyrius" \
   && ! grep -q '"/versions/"' "$ROOT/cbt/pulsar.cyr" \
   && ! grep -q 'syscall(88' "$ROOT/cbt/pulsar.cyr" \
   && ! grep -q 'dir_list(str_from("lib"))' "$ROOT/cbt/pulsar.cyr" \
   && grep -q '_files_identical(cc5_a, cc5_b)' "$ROOT/cbt/pulsar.cyr" \
   && grep -q '_pulsar_raw_compile(cc5_a, "src/main.cyr", cc5_b)' "$ROOT/cbt/pulsar.cyr"; then
    ok "cyrius pulsar: installs through install.sh (in the binary), no store-writer idioms, raw byte-exact fixpoint"
else bad "axis 6: pulsar still carries a store writer, a size-only fixpoint test, or a compile()-built stage 1"; fi

# ── axis 7/8: verify-store reports a slot that drifted from its tag, --restore repairs it ──
H7="$W/home7"; mkdir -p "$H7/versions/9.9.9/lib" "$H7/versions/9.9.9/bin"
printf 'fn probe_lib(): i64 { return 99; }\n' > "$H7/versions/9.9.9/lib/probe.cyr"     # mutated lib
printf 'fn extra(): i64 { return 0; }\n' > "$H7/versions/9.9.9/lib/extra.cyr"         # not at the tag
printf 'other-bytes\n' > "$H7/versions/9.9.9/bin/cycc"                                 # tracked bin drifted
printf 'deadbeef dirty\ntree-matches-tag: no\n' > "$H7/versions/9.9.9/SOURCE_COMMIT"
rc=0; if ( cd "$R" && CYRIUS_HOME="$H7" sh scripts/verify-store.sh > "$W/a7.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && grep -q 'DIFFERS   lib/probe.cyr' "$W/a7.out" && grep -q 'NOT-AT-TAG lib/extra.cyr' "$W/a7.out" \
   && grep -q 'DIFFERS   bin/cycc' "$W/a7.out" && grep -q 'inputs DRIFTED' "$W/a7.out" && grep -q '1 BAD' "$W/a7.out"; then
    ok "verify-store: names the drifted lib, the file not at the tag, the drifted tracked bin, the foreign stamp; exits non-zero"
else bad "axis 7 (rc=$rc): $(cat "$W/a7.out")"; fi
rc=0; if ( cd "$R" && CYRIUS_HOME="$H7" sh scripts/verify-store.sh --restore 9.9.9 > "$W/a8.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q 'return 1' "$H7/versions/9.9.9/lib/probe.cyr" && [ ! -f "$H7/versions/9.9.9/lib/extra.cyr" ] \
   && [ "$(cat "$H7/versions/9.9.9/bin/cycc")" = "tracked-compiler-bytes-v1" ] \
   && [ "$(head -1 "$H7/versions/9.9.9/SOURCE_COMMIT")" = "$(git -C "$R" rev-list -n1 9.9.9)" ] \
   && ( cd "$R" && CYRIUS_HOME="$H7" sh scripts/verify-store.sh > "$W/a8b.out" 2>&1 ) && grep -q '0 BAD' "$W/a8b.out"; then
    ok "verify-store --restore: lib + tracked bin back to the tag, stray file removed, stamp = tag commit, report now clean"
else bad "axis 8 (rc=$rc): $(tail -4 "$W/a8.out")"; fi

# ── axis 9: a clean slot verifies OK (anti-vacuous — the report must not red everything) ──
rc=0; if ( cd "$R" && CYRIUS_HOME="$H4" sh scripts/verify-store.sh > "$W/a9.out" 2>&1 ); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && grep -q '9.9.9    OK' "$W/a9.out"; then ok "verify-store: a slot written at the tag verifies OK"; else bad "axis 9 (rc=$rc): $(cat "$W/a9.out")"; fi

echo "released_slot_written_from_tag: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
