#!/bin/sh
# Gate: the CLI rewrites a PROJECT's own files through a symlink ONLY to a file inside the
# project (6.6.20, CVE-TBD — SEC-03 of the v6.6.x closeout security re-scan).
#
# THE DEFECT. 6.6.6 made the writers of a user's file keep a symlink and write the file it
# names (lib/io.cyr file_replace_atomic, cbt's _aw_open_replace) — wherever it pointed. A
# checkout is untrusted input and git commits symlinks, so a COMMITTED link wrote outside the
# project. Measured before the fix, each one exit 0:
#   * a dangling `cyrius.cyml -> ~/.ssh/authorized_keys` beside a cyrius.toml holding an ssh key
#     line: `cyrius update` CREATED authorized_keys from the toml (file_exists() is 0 for a
#     dangling link, so the toml -> cyml migration ran and wrote through it);
#   * `.cyrius-toolchain -> ~/.profile`: `cyrius update` replaced it with the version string;
#   * `cyrius.lock -> ~/.profile`: `cyrius deps --lock`, AND a plain `cyrius build` (its
#     auto-deps relock), replaced it with the lock;
#   * `cyrius.cyml -> ../other/cyrius.cyml`: `cyriusly use` rewrote ANOTHER project's pin;
#   * `src/x.cyr -> ../../victim.cyr`: `cyrius fmt src/x.cyr` reformatted the file it names;
#   * `.gitignore -> ../victim`: `cyrius port` appended its lines to it (O_APPEND follows).
# THE RULE (lib/io.cyr _io_replace_target_in, the one helper every writer above now goes
# through): a link is followed only while every hop's target is RELATIVE, never climbs above
# the root with `..`, and never passes through a directory that is itself a link. The last is
# not pedantry: the kernel resolves `dirlink/..` against the link's TARGET, so with
# `dl2 -> ../victim/sub` the target `dl2/../x` READS as `x` (inside) and LANDS in victim/ —
# axis 4b is that trap. Anything else is refused BY NAME, and nothing is written.
#
# AXES
#   1   cyrius update, dangling ABSOLUTE cyrius.cyml link: refused, nothing created, toml kept
#   2   cyrius update, .cyrius-toolchain -> ../victim/profile (climbs out): refused, unchanged
#   3   cyrius deps --lock, cyrius.lock -> an absolute path: refused, unchanged
#   4a  deps --lock through a DIRECTORY link (dl/x.lock, dl -> ../victim): refused
#   4b  deps --lock via `dl2/../lock2` (dl2 -> ../victim/sub): refused, victim/lock2 not created
#   4c  deps --lock via a two-hop chain whose SECOND hop climbs out: refused, the hop named
#   5   plain `cyrius build` (auto-deps relock) with cyrius.lock -> an absolute path: rc != 0
#   6   cyriusly use, cyrius.cyml -> ../other6/cyrius.cyml: refused, the other manifest unchanged
#   7   cyrius fmt src/evil.cyr (-> ../../victim/fmt.cyr): refused, unformatted
#   7b  cyrius port, .gitignore -> ../victim/gi: refused, nothing appended
#   8   ANTI-OVER-CORRECTION — an in-tree link is still written THROUGH, link kept (the 6.6.6
#       semantics the fix must not undo): deps --lock via locks/real.lock, update's migration via
#       real/../real/m.cyml, cyrius fmt via ../shared/a.cyr from src/, cyrfmt --write on an
#       ABSOLUTE path from another cwd, cyriusly use via in/m.cyml, port via sub/gi
#   9   a hostile target is printed ESCAPED (\x1b), never as a raw ESC byte
#   10  cyrius update, dangling cyrius.cyml -> .git/commondir (a real repo): refused, no commondir,
#       toml kept. `.git` is INSIDE the project, so containment alone let it through — measured:
#       toml `../evil` + a checkout dir `evil\n---/` with core.fsmonitor = a command, and the next
#       `git status` RAN it (the migration writes the toml plus `---\n`; git strips the newline)
#   11  cyrius.lock -> .git/config: deps --lock AND a plain build's relock refused, config unchanged
#   12  .GIT/config (case-folded on APFS/NTFS), sub/../.git/config (normalised), `.git` itself (a
#       worktree / submodule gitfile) and a chain whose 2nd hop lands in .git: each refused
#   13  the cx tools JIT-built into build/ (cxvm by `cyrius run x.cyx`, cycc_cx by
#       `cyrius build --target=cx`) REPLACE a committed build/cxvm / build/cycc_cx link — the
#       O_TRUNC open they used planted the binary, mode 0755, where the link pointed
#   14  cyrius distlib's self-check entry `.distchk<pid>.cyr` (project root): a committed link at
#       that name is removed and the entry created fresh, never written through
#
# MUTATION LEDGER (6.6.20; each run against a copy of the fixed tree; real tree GREEN, the
# pre-fix tree RED on every refusal axis with axis 8 GREEN):
#   M1 cbt _aw_open_replace back on _io_replace_target                 -> 3 4a 4b 4c 5 9 RED
#   M2 cmd_update's two writes back on file_replace_atomic              -> 1 2 RED
#   M3 cyriusly back on file_replace_atomic                             -> 6 RED
#   M4 cyrfmt --write back on file_replace_atomic                       -> 7 RED
#   M5 cyrius port appends to the NAMED .gitignore again                -> 7b RED
#   M6 _io_replace_target_in: no link check before a `..` pop           -> 4b RED (only it)
#   M7 _io_replace_target_in: no directory-prefix link walk             -> 4a RED (only it)
#   M8 over-correction: every link refused                              -> 8 RED (and the reason
#      text of 1 3 4a-c)
#   M9 _io_ew_shown prints bytes raw                                    -> 9 RED
#   M10 _io_replace_target_in: no .git check on a hop (_io_path_meta_why) -> 10 11 12 RED
#   M11 _io_path_meta_why compares case-SENSITIVELY                     -> 12 (.GIT) RED (only it)
#   M12 cbt _cx_jit_build opens `out` O_TRUNC again (the pre-fix open)    -> 13 RED (only it)
#   M13 distlib opens .distchk<pid>.cyr O_TRUNC again (the pre-fix open)  -> 14 RED (only it)
#   (the alias families — HFS-ignorable code points, `:stream`, trailing dots/spaces, GIT~1 and
#   other 8.3 names — are pinned row by row in tests/tcyr/crossos/replace_in_tree_link_rules.tcyr,
#   each one's mutation RED there)
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: project_writes_stay_in_tree: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: project_writes_stay_in_tree: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: project_writes_stay_in_tree: build/cycc missing"; exit 1; }
VER=$(tr -d '[:space:]' < VERSION)

# ── every writer, built from the tree ──
mkdir -p "$D/bin" "$D/iroot/bin"
for t in cyrius:cbt/cyrius.cyr cyrfmt:programs/cyrfmt.cyr cyriusly:programs/cyriusly.cyr; do
    n=${t%%:*}; s=${t#*:}
    if ! "$CC" < "$s" > "$D/bin/$n" 2> "$D/$n.err" || [ ! -s "$D/bin/$n" ]; then
        echo "FAIL: project_writes_stay_in_tree: $s does not build:"; tail -3 "$D/$n.err"; exit 1
    fi
done
# cyrius-init finds its templates at <bin>/../programs/cyrius-init-templates.
if ! "$CC" < programs/cyrius-init.cyr > "$D/iroot/bin/cyrius-init" 2> "$D/init.err" || [ ! -s "$D/iroot/bin/cyrius-init" ]; then
    echo "FAIL: project_writes_stay_in_tree: programs/cyrius-init.cyr does not build:"; tail -3 "$D/init.err"; exit 1
fi
ln -s "$ROOT/programs" "$D/iroot/programs" && ln -s "$ROOT/lib" "$D/iroot/lib" \
  && cp "$CC" "$D/bin/cycc" && chmod +x "$D/bin/cyrius" "$D/bin/cyrfmt" "$D/bin/cyriusly" "$D/bin/cycc" "$D/iroot/bin/cyrius-init" \
  || { echo "FAIL: project_writes_stay_in_tree: cannot stage the binaries"; exit 1; }
# A throwaway home whose stdlib slot is the tree's lib/ (read here, never written: every write
# below lands in a project under $D or is refused).
H="$D/home/.cyrius"
mkdir -p "$H/versions/$VER" && ln -s "$ROOT/lib" "$H/versions/$VER/lib" && printf '%s' "$VER" > "$H/current" \
  || { echo "FAIL: project_writes_stay_in_tree: cannot stage the throwaway home"; exit 1; }
# run <dir> <out> <cmd...> — in <dir>, with the throwaway home; sets $rc
run() { _d=$1; _o=$2; shift 2; rc=0; ( cd "$_d" && HOME="$D/home" CYRIUS_HOME="$H" CYRIUS_VER="$VER" exec "$@" ) > "$_o" 2>&1 || rc=$?; }
V="$D/victim"
mkdir -p "$V/.ssh" "$V/sub"
# same <a> <b>: byte-identical
same() { cmp -s "$1" "$2"; }

# ── axis 1: update's toml->cyml migration through a dangling ABSOLUTE link ──
P="$D/p1"; mkdir -p "$P"
printf '[package]\nname = "p1"\n# ssh-ed25519 AAAAPLANTEDKEY attacker@evil\n' > "$P/cyrius.toml"
ln -s "$V/.ssh/authorized_keys" "$P/cyrius.cyml"
run "$P" "$D/a1.out" "$D/bin/cyrius" update
a=0
[ "$rc" -ne 0 ] || { fail "axis 1: cyrius update exited 0 over a cyrius.cyml link to an absolute path"; a=1; }
[ -e "$V/.ssh/authorized_keys" ] && { fail "axis 1: cyrius update CREATED the file the dangling cyrius.cyml link names: $(cat "$V/.ssh/authorized_keys")"; a=1; }
grep -qF "refusing to write cyrius.cyml: it is a symlink to $V/.ssh/authorized_keys, an ABSOLUTE path" "$D/a1.out" \
  || { fail "axis 1: the refusal does not name the link and its target:"; sed 's/^/      /' "$D/a1.out" | head -4; a=1; }
[ -f "$P/cyrius.toml" ] || { fail "axis 1: cyrius.toml was deleted although the migration was refused"; a=1; }
[ -L "$P/cyrius.cyml" ] || { fail "axis 1: the cyrius.cyml link was replaced"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 1: cyrius update refuses to migrate cyrius.toml through a dangling absolute cyrius.cyml link, by name; nothing created, the toml kept"

# ── axis 2: update's toolchain pin through a link that climbs out ──
P="$D/p2"; mkdir -p "$P"
printf '[package]\nname = "p2"\n' > "$P/cyrius.cyml"
echo "VICTIM-PROFILE" > "$V/profile"; cp "$V/profile" "$D/profile.orig"
ln -s ../victim/profile "$P/.cyrius-toolchain"
run "$P" "$D/a2.out" "$D/bin/cyrius" update
a=0
[ "$rc" -ne 0 ] || { fail "axis 2: cyrius update exited 0 over .cyrius-toolchain -> ../victim/profile"; a=1; }
same "$V/profile" "$D/profile.orig" || { fail "axis 2: cyrius update wrote THROUGH .cyrius-toolchain into ../victim/profile: $(cat "$V/profile")"; a=1; }
grep -qF "refusing to write .cyrius-toolchain: it is a symlink to ../victim/profile, which climbs out with .." "$D/a2.out" \
  || { fail "axis 2: the refusal does not name the link:"; sed 's/^/      /' "$D/a2.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 2: cyrius update refuses .cyrius-toolchain -> ../victim/profile by name; the file it names is byte-identical"

# ── axes 3-4: deps --lock ──
# mklock <dir> — a project with one lib file and no deps (the lock is written unconditionally)
mklock() { mkdir -p "$1/lib" && printf '[package]\nname = "pl"\nversion = "0.1.0"\n' > "$1/cyrius.cyml" && echo 'fn y(): i64 { return 2; }' > "$1/lib/y.cyr"; }
echo "VICTIM-LOCK" > "$V/lock"; cp "$V/lock" "$D/lock.orig"
P="$D/p3"; mklock "$P"; ln -s "$V/lock" "$P/cyrius.lock"
run "$P" "$D/a3.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 3: cyrius deps --lock exited 0 over cyrius.lock -> an absolute path"; a=1; }
same "$V/lock" "$D/lock.orig" || { fail "axis 3: cyrius deps --lock replaced the file cyrius.lock links to: $(head -1 "$V/lock")"; a=1; }
grep -qF "refusing to write cyrius.lock: it is a symlink to $V/lock, an ABSOLUTE path" "$D/a3.out" \
  || { fail "axis 3: the refusal does not name the link:"; sed 's/^/      /' "$D/a3.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 3: cyrius deps --lock refuses cyrius.lock -> an absolute path by name; the file it names is byte-identical"

P="$D/p4a"; mklock "$P"; ln -s ../victim "$P/dl"; ln -s dl/x.lock "$P/cyrius.lock"
run "$P" "$D/a4a.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 4a: deps --lock exited 0 writing through the directory link dl"; a=1; }
[ -e "$V/x.lock" ] && { fail "axis 4a: deps --lock CREATED victim/x.lock through the directory link dl"; a=1; }
grep -qF "refusing to write cyrius.lock: it is a symlink to dl/x.lock, reached through the directory link dl" "$D/a4a.out" \
  || { fail "axis 4a: the refusal does not name the directory link:"; sed 's/^/      /' "$D/a4a.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 4a: a target under a DIRECTORY link (dl/x.lock, dl -> ../victim) is refused, naming dl"

P="$D/p4b"; mklock "$P"; ln -s ../victim/sub "$P/dl2"; ln -s dl2/../lock2 "$P/cyrius.lock"
run "$P" "$D/a4b.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 4b: deps --lock exited 0 over dl2/../lock2 (dl2 a directory link)"; a=1; }
[ -e "$V/lock2" ] && { fail "axis 4b: deps --lock CREATED victim/lock2: dl2/../lock2 read as the in-tree lock2 and landed beside dl2's target"; a=1; }
[ -e "$P/lock2" ] && { fail "axis 4b: deps --lock wrote the project's lock2, a path the kernel would never have resolved the link to"; a=1; }
grep -qF "reached through the directory link dl2" "$D/a4b.out" \
  || { fail "axis 4b: the refusal does not name dl2:"; sed 's/^/      /' "$D/a4b.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 4b: dl2/../lock2 with dl2 a directory link is refused (lexically in-tree, physically outside)"

P="$D/p4c"; mklock "$P"; mkdir -p "$P/locks"; ln -s ../../victim/lock "$P/locks/l2"; ln -s locks/l2 "$P/cyrius.lock"
run "$P" "$D/a4c.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 4c: deps --lock exited 0 over a chain whose second hop climbs out"; a=1; }
same "$V/lock" "$D/lock.orig" || { fail "axis 4c: deps --lock replaced victim/lock through the two-hop chain"; a=1; }
grep -qF "refusing to write cyrius.lock: the link locks/l2 on its way is a symlink to ../../victim/lock, which climbs out with .." "$D/a4c.out" \
  || { fail "axis 4c: the refusal does not name the hop:"; sed 's/^/      /' "$D/a4c.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 4c: a two-hop chain (cyrius.lock -> locks/l2 -> ../../victim/lock) is refused at the hop that climbs out, named"

# ── axis 5: a plain `cyrius build` relocks through its auto-deps resolve ──
P="$D/p5"; mkdir -p "$P/src"
printf '[package]\nname = "p5"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["string"]\n' "$VER" > "$P/cyrius.cyml"
printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$P/src/main.cyr"
ln -s "$V/lock" "$P/cyrius.lock"
run "$P" "$D/a5.out" "$D/bin/cyrius" build src/main.cyr build/p5
a=0
[ "$rc" -ne 0 ] || { fail "axis 5: cyrius build exited 0 over cyrius.lock -> an absolute path"; a=1; }
same "$V/lock" "$D/lock.orig" || { fail "axis 5: a plain cyrius build replaced the file cyrius.lock links to (auto-deps relock)"; a=1; }
grep -qF "refusing to write cyrius.lock" "$D/a5.out" || { fail "axis 5: the build's refusal does not name cyrius.lock:"; sed 's/^/      /' "$D/a5.out" | head -4; a=1; }
[ -d "$P/lib" ] || { fail "axis 5: the auto-deps resolve did not run (no lib/) — this axis did not reach the relock"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 5: a plain cyrius build (auto-deps relock) refuses cyrius.lock -> an absolute path; the build fails, the file it names is byte-identical"

# ── axis 6: cyriusly use ──
mkdir -p "$D/other6" "$D/p6"
printf '[package]\nname = "other6"\ncyrius = "6.6.1"\n' > "$D/other6/cyrius.cyml"; cp "$D/other6/cyrius.cyml" "$D/other6.orig"
ln -s ../other6/cyrius.cyml "$D/p6/cyrius.cyml"
run "$D/p6" "$D/a6.out" "$D/bin/cyriusly" use "$VER"
a=0
[ "$rc" -ne 0 ] || { fail "axis 6: cyriusly use exited 0 over cyrius.cyml -> ../other6/cyrius.cyml"; a=1; }
same "$D/other6/cyrius.cyml" "$D/other6.orig" || { fail "axis 6: cyriusly use rewrote ANOTHER project's pin: $(grep cyrius "$D/other6/cyrius.cyml" | tail -1)"; a=1; }
grep -qF "refusing to write cyrius.cyml: it is a symlink to ../other6/cyrius.cyml" "$D/a6.out" \
  || { fail "axis 6: the refusal does not name the link:"; sed 's/^/      /' "$D/a6.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 6: cyriusly use refuses cyrius.cyml -> ../other6/cyrius.cyml by name; the other project's manifest is byte-identical"

# ── axis 7: cyrius fmt (cyrfmt --write) ──
UNF='fn f(): i64 {\nreturn 1;\n}\n'
printf "$UNF" > "$V/fmt.cyr"; cp "$V/fmt.cyr" "$D/fmt.orig"
P="$D/p7"; mkdir -p "$P/src"; ln -s ../../victim/fmt.cyr "$P/src/evil.cyr"
run "$P" "$D/a7.out" "$D/bin/cyrius" fmt src/evil.cyr
a=0
[ "$rc" -ne 0 ] || { fail "axis 7: cyrius fmt exited 0 over src/evil.cyr -> ../../victim/fmt.cyr"; a=1; }
same "$V/fmt.cyr" "$D/fmt.orig" || { fail "axis 7: cyrius fmt reformatted the file outside the project"; a=1; }
grep -qF "cyrfmt: refusing to write src/evil.cyr: it is a symlink to ../../victim/fmt.cyr, which climbs out with .." "$D/a7.out" \
  || { fail "axis 7: the refusal does not name the link:"; sed 's/^/      /' "$D/a7.out" | head -4; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 7: cyrius fmt refuses src/evil.cyr -> ../../victim/fmt.cyr by name; unformatted"

# ── axis 7b: cyrius port's .gitignore append ──
echo "VICTIM-GI" > "$V/gi"; cp "$V/gi" "$D/gi.orig"
mkdir -p "$D/port/proj/src"
printf '[package]\nname = "proj"\n' > "$D/port/proj/Cargo.toml"; echo 'fn main() {}' > "$D/port/proj/src/main.rs"
ln -s ../../victim/gi "$D/port/proj/.gitignore"
run "$D/port" "$D/a7b.out" "$D/iroot/bin/cyrius-init" --__mode=port proj
a=0
[ "$rc" -ne 0 ] || { fail "axis 7b: cyrius port exited 0 over .gitignore -> ../../victim/gi"; a=1; }
same "$V/gi" "$D/gi.orig" || { fail "axis 7b: cyrius port appended to the file outside the project: $(tail -2 "$V/gi" | tr '\n' ' ')"; a=1; }
grep -qF "refusing to write proj/.gitignore: it is a symlink to ../../victim/gi, which climbs out with .." "$D/a7b.out" \
  || { fail "axis 7b: the refusal does not name the link:"; sed 's/^/      /' "$D/a7b.out" | head -6; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 7b: cyrius port refuses to append through .gitignore -> ../../victim/gi, by name"

# ── axis 8: ANTI-OVER-CORRECTION — an in-tree link is still written THROUGH ──
a=0
P="$D/p8l"; mklock "$P"; mkdir -p "$P/locks"; echo "old" > "$P/locks/real.lock"; ln -s locks/real.lock "$P/cyrius.lock"
run "$P" "$D/a8l.out" "$D/bin/cyrius" deps --lock
{ [ "$rc" -eq 0 ] && [ -L "$P/cyrius.lock" ] && grep -q '  lib/y.cyr$' "$P/locks/real.lock"; } \
  || { fail "axis 8: deps --lock no longer writes THROUGH an in-tree link (rc=$rc):"; sed 's/^/      /' "$D/a8l.out" | head -3; a=1; }
P="$D/p8m"; mkdir -p "$P/real"; printf '[package]\nname = "p8m"\n' > "$P/cyrius.toml"; ln -s real/../real/m.cyml "$P/cyrius.cyml"
run "$P" "$D/a8m.out" "$D/bin/cyrius" update
{ [ "$rc" -eq 0 ] && [ -L "$P/cyrius.cyml" ] && grep -q 'name = "p8m"' "$P/real/m.cyml" && [ ! -e "$P/cyrius.toml" ]; } \
  || { fail "axis 8: update's migration no longer writes THROUGH real/../real/m.cyml (rc=$rc):"; sed 's/^/      /' "$D/a8m.out" | head -3; a=1; }
P="$D/p8f"; mkdir -p "$P/src" "$P/shared" "$P/real"
printf "$UNF" > "$P/shared/a.cyr"; ln -s ../shared/a.cyr "$P/src/a.cyr"
run "$P" "$D/a8f.out" "$D/bin/cyrius" fmt src/a.cyr
{ [ "$rc" -eq 0 ] && [ -L "$P/src/a.cyr" ] && grep -q '^    return 1;$' "$P/shared/a.cyr"; } \
  || { fail "axis 8: cyrius fmt no longer writes THROUGH src/a.cyr -> ../shared/a.cyr (rc=$rc):"; sed 's/^/      /' "$D/a8f.out" | head -3; a=1; }
printf "$UNF" > "$P/real/src.cyr"; ln -s real/src.cyr "$P/link.cyr"
run "$D" "$D/a8g.out" "$D/bin/cyrfmt" --write "$P/link.cyr"
{ [ "$rc" -eq 0 ] && [ -L "$P/link.cyr" ] && grep -q '^    return 1;$' "$P/real/src.cyr"; } \
  || { fail "axis 8: cyrfmt --write <absolute path> no longer writes THROUGH link.cyr -> real/src.cyr (rc=$rc):"; sed 's/^/      /' "$D/a8g.out" | head -3; a=1; }
P="$D/p8y"; mkdir -p "$P/in"; printf '[package]\nname = "in"\ncyrius = "6.6.1"\n' > "$P/in/m.cyml"; ln -s in/m.cyml "$P/cyrius.cyml"
run "$P" "$D/a8y.out" "$D/bin/cyriusly" use "$VER"
{ [ "$rc" -eq 0 ] && [ -L "$P/cyrius.cyml" ] && grep -qF "cyrius = \"$VER\"" "$P/in/m.cyml"; } \
  || { fail "axis 8: cyriusly use no longer writes THROUGH cyrius.cyml -> in/m.cyml (rc=$rc):"; sed 's/^/      /' "$D/a8y.out" | head -3; a=1; }
mkdir -p "$D/port8/proj/src" "$D/port8/proj/sub"
printf '[package]\nname = "proj"\n' > "$D/port8/proj/Cargo.toml"; echo 'fn main() {}' > "$D/port8/proj/src/main.rs"
echo "/keep/" > "$D/port8/proj/sub/gi"; ln -s sub/gi "$D/port8/proj/.gitignore"
run "$D/port8" "$D/a8p.out" "$D/iroot/bin/cyrius-init" --__mode=port proj
{ [ "$rc" -eq 0 ] && [ -L "$D/port8/proj/.gitignore" ] && grep -q '^/rust-old/target/$' "$D/port8/proj/sub/gi"; } \
  || { fail "axis 8: cyrius port no longer appends THROUGH .gitignore -> sub/gi (rc=$rc):"; sed 's/^/      /' "$D/a8p.out" | tail -3; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 8: in-tree links are still written THROUGH, the link kept — deps --lock (locks/real.lock), update's migration (real/../real/m.cyml), cyrius fmt (../shared/a.cyr from src/), cyrfmt --write on an absolute path from another cwd, cyriusly use (in/m.cyml), port (sub/gi)"

# ── axis 9: the refusal prints a hostile target escaped ──
P="$D/p9"; mklock "$P"; ln -s "../$(printf '\033')]0;owned$(printf '\007')x" "$P/cyrius.lock"
run "$P" "$D/a9.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 9: deps --lock exited 0 over a link that climbs out"; a=1; }
grep -qF 'it is a symlink to ../\x1b]0;owned\x07x, which climbs out' "$D/a9.out" \
  || { fail "axis 9: the hostile target is not shown escaped:"; sed 's/^/      /' "$D/a9.out" | head -2 | od -c | head -4; a=1; }
if LC_ALL=C grep -q "$(printf '\033')" "$D/a9.out"; then fail "axis 9: a raw ESC byte reached the terminal"; a=1; fi
[ "$a" = 0 ] && echo "  ok: axis 9: a link target holding ESC/BEL is shown as \\x1b / \\x07, never raw"

# ── axes 10-12: .git is INSIDE the project, and a write there is code execution ──
# Each fixture is a real `git init` repo, so .git/ is the metadata git itself reads.
command -v git >/dev/null 2>&1 || { echo "FAIL: project_writes_stay_in_tree: git not found (axes 10-12 need a real repository)"; exit 1; }
# grepo <dir> — a git repo at <dir> (no commit needed: .git/config is what git reads)
grepo() { mkdir -p "$1" && git -c init.defaultBranch=main init -q "$1" && git -C "$1" config user.name gate; }

# axis 10: update's migration through a dangling cyrius.cyml -> .git/commondir. Before the fix
# the toml was written verbatim to .git/commondir, so with toml = `../evil` and a checkout
# directory `evil\n---/` holding a config with core.fsmonitor, the next `git status` ran it.
P="$D/g10"; grepo "$P"
printf '../evil' > "$P/cyrius.toml"; ln -s .git/commondir "$P/cyrius.cyml"
run "$P" "$D/g10.out" "$D/bin/cyrius" update
a=0
[ "$rc" -ne 0 ] || { fail "axis 10: cyrius update exited 0 over cyrius.cyml -> .git/commondir"; a=1; }
[ -e "$P/.git/commondir" ] && { fail "axis 10: cyrius update CREATED .git/commondir (the repo's common dir is now: $(od -c "$P/.git/commondir" | head -1))"; a=1; }
grep -qF "refusing to write cyrius.cyml: it is a symlink to .git/commondir, which reaches into .git, the repository's own metadata" "$D/g10.out" \
  || { fail "axis 10: the refusal does not name the link and .git:"; sed 's/^/      /' "$D/g10.out" | head -4; a=1; }
[ -f "$P/cyrius.toml" ] || { fail "axis 10: cyrius.toml was deleted although the migration was refused"; a=1; }
git -C "$P" status --porcelain > /dev/null 2>&1 || { fail "axis 10: the repository no longer reads after cyrius update"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 10: cyrius update refuses to migrate through a dangling cyrius.cyml -> .git/commondir, by name; no commondir created, the toml kept, the repo intact"

# axis 11: cyrius.lock -> .git/config — deps --lock AND a plain build's relock. Before the fix
# both replaced the config with the lock (`git remote -v`: "fatal: bad config line 1").
P="$D/g11"; grepo "$P"; mklock "$P"; git -C "$P" remote add origin https://example.invalid/r.git
cp "$P/.git/config" "$D/g11.cfg"; ln -s .git/config "$P/cyrius.lock"
run "$P" "$D/g11.out" "$D/bin/cyrius" deps --lock
a=0
[ "$rc" -ne 0 ] || { fail "axis 11: cyrius deps --lock exited 0 over cyrius.lock -> .git/config"; a=1; }
same "$P/.git/config" "$D/g11.cfg" || { fail "axis 11: cyrius deps --lock replaced .git/config: $(head -1 "$P/.git/config")"; a=1; }
grep -qF "refusing to write cyrius.lock: it is a symlink to .git/config, which reaches into .git" "$D/g11.out" \
  || { fail "axis 11: deps --lock's refusal does not name the link and .git:"; sed 's/^/      /' "$D/g11.out" | head -4; a=1; }
P="$D/g11b"; grepo "$P"; mkdir -p "$P/src"; git -C "$P" remote add origin https://example.invalid/r.git
printf '[package]\nname = "g11b"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["string"]\n' "$VER" > "$P/cyrius.cyml"
printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$P/src/main.cyr"
cp "$P/.git/config" "$D/g11b.cfg"; ln -s .git/config "$P/cyrius.lock"
run "$P" "$D/g11b.out" "$D/bin/cyrius" build src/main.cyr build/g11b
[ "$rc" -ne 0 ] || { fail "axis 11: a plain cyrius build exited 0 over cyrius.lock -> .git/config"; a=1; }
same "$P/.git/config" "$D/g11b.cfg" || { fail "axis 11: a plain cyrius build (auto-deps relock) replaced .git/config: $(head -1 "$P/.git/config")"; a=1; }
grep -qF "refusing to write cyrius.lock: it is a symlink to .git/config, which reaches into .git" "$D/g11b.out" \
  || { fail "axis 11: the build's refusal does not name the link and .git:"; sed 's/^/      /' "$D/g11b.out" | head -4; a=1; }
[ -d "$P/lib" ] || { fail "axis 11: the auto-deps resolve did not run (no lib/) — the build did not reach the relock"; a=1; }
git -C "$P" remote -v 2>/dev/null | grep -q example.invalid || { fail "axis 11: git no longer reads the repository's remotes"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 11: cyrius.lock -> .git/config is refused by deps --lock and by a plain build's relock, by name; .git/config byte-identical"

# axis 12: other spellings that reach .git — case-folded (APFS / NTFS fold `.GIT` onto `.git`; on
# this case-sensitive fixture it is a separate directory, so only the refusal can make it RED),
# normalised through `..`, a worktree/submodule gitfile (`.git` itself), a chain hiding the hop.
a=0
for spec in "u:.GIT/config:.GIT" "p:sub/../.git/config:" "f:.git:" "c:locks/c2:"; do
    k=${spec%%:*}; rest=${spec#*:}; tgt=${rest%%:*}; mk=${rest#*:}
    P="$D/g12$k"; grepo "$P"; mklock "$P"; mkdir -p "$P/sub" "$P/locks"
    [ -n "$mk" ] && mkdir -p "$P/$mk"
    cp "$P/.git/config" "$D/g12$k.cfg"
    case $k in
        f) rm -rf "$P/.git" && printf 'gitdir: %s\n' "$D/g12f.real" > "$P/.git" && cp "$P/.git" "$D/g12f.gitfile" ;;
        c) ln -s ../.git/config "$P/locks/c2" ;;
    esac
    ln -s "$tgt" "$P/cyrius.lock"
    run "$P" "$D/g12$k.out" "$D/bin/cyrius" deps --lock
    [ "$rc" -ne 0 ] || { fail "axis 12 ($tgt): deps --lock exited 0"; a=1; }
    grep -qF "which reaches into .git" "$D/g12$k.out" \
      || { fail "axis 12 ($tgt): the refusal does not name .git:"; sed 's/^/      /' "$D/g12$k.out" | head -3; a=1; }
    case $k in
        u) [ -e "$P/.GIT/config" ] && { fail "axis 12 (.GIT/config): written — on APFS/NTFS that is .git/config"; a=1; } ;;
        f) same "$P/.git" "$D/g12f.gitfile" || { fail "axis 12 (.git gitfile): the gitfile was replaced: $(head -1 "$P/.git")"; a=1; } ;;
        *) same "$P/.git/config" "$D/g12$k.cfg" || { fail "axis 12 ($tgt): .git/config was replaced"; a=1; } ;;
    esac
done
grep -qF "the link locks/c2 on its way is a symlink to ../.git/config" "$D/g12c.out" \
  || { fail "axis 12 (chain): the hop into .git is not the one named:"; sed 's/^/      /' "$D/g12c.out" | head -2; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 12: .GIT/config (case-folded), sub/../.git/config (normalised), .git itself (a gitfile) and a chain whose second hop lands in .git are each refused, naming .git; nothing written"

# ── axis 13: the cx tools the CLI JIT-builds into the project's build/ ──
# With no cxvm / cycc_cx installed (this home has neither), `cyrius run x.cyx` builds
# programs/cxvm.cyr into ./build/cxvm and `cyrius build --target=cx` builds src/main_cx.cyr into
# ./build/cycc_cx. Both opened that name O_TRUNC, which follows a committed dangling link: the
# compiled binary was planted, mode 0755, wherever the link pointed. They now build a fresh temp
# and rename it over the name, REPLACING the link. (That the checkout's own cxvm.cyr is then RUN
# is binary planting — handoff 3 — and is why this asserts only where the bytes land.)
a=0
P="$D/p13"; mkdir -p "$P/programs" "$P/src" "$P/build"
printf '[package]\nname = "p13"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
echo 'syscall(60, 7);' > "$P/programs/cxvm.cyr"; printf 'var x = 1;\n' > "$P/x.cyx"
ln -s "$V/planted_vm" "$P/build/cxvm"
run "$P" "$D/a13v.out" "$D/bin/cyrius" run x.cyx
[ -e "$V/planted_vm" ] && { fail "axis 13: cyrius run x.cyx wrote the JIT-built cxvm THROUGH build/cxvm into $V/planted_vm"; a=1; }
{ [ -f "$P/build/cxvm" ] && [ ! -L "$P/build/cxvm" ]; } || { fail "axis 13: build/cxvm is not the freshly built file (rc=$rc):"; sed 's/^/      /' "$D/a13v.out" | head -3; a=1; }
printf 'fn main(): i64 { return 0; }\n' > "$P/src/a.cyr"
echo 'syscall(60, 0);' > "$P/src/main_cx.cyr"
ln -s "$V/planted_cc" "$P/build/cycc_cx"
run "$P" "$D/a13c.out" "$D/bin/cyrius" build --target=cx src/a.cyr build/a.cyx
[ -e "$V/planted_cc" ] && { fail "axis 13: cyrius build --target=cx wrote the JIT-built cycc_cx THROUGH build/cycc_cx into $V/planted_cc"; a=1; }
{ [ -f "$P/build/cycc_cx" ] && [ ! -L "$P/build/cycc_cx" ]; } || { fail "axis 13: build/cycc_cx is not the freshly built file (rc=$rc):"; sed 's/^/      /' "$D/a13c.out" | head -3; a=1; }
ls "$P/build" | grep -q '\.tmp\.' && { fail "axis 13: a JIT-build temp was left in build/: $(ls "$P/build" | tr '\n' ' ')"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 13: the JIT-built cxvm and cycc_cx REPLACE a committed build/cxvm / build/cycc_cx link (temp + rename); nothing written where it pointed"

# ── axis 14: distlib's self-check entry, `.distchk<pid>.cyr` in the project root ──
# It was written with file_write_all (O_TRUNC), which follows a committed link; a checkout can
# plant one per pid for a range (a CI container's pids are small and steady). Deterministic here:
# the shell plants `.distchk$$.cyr` and EXECs the CLI, which keeps that pid. The sidecar verify
# needs an aarch64 compiler beside the CLI before it reaches the self-check, so one is built.
a=0
if ! "$CC" < src/main_aarch64.cyr > "$D/bin/cycc_aarch64" 2> "$D/cca64.err" || [ ! -s "$D/bin/cycc_aarch64" ]; then
    echo "FAIL: project_writes_stay_in_tree: src/main_aarch64.cyr does not build:"; tail -3 "$D/cca64.err"; exit 1
fi
chmod +x "$D/bin/cycc_aarch64"
P="$D/p14"; mkdir -p "$P/src"
printf '[package]\nname = "dlp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$VER" > "$P/cyrius.cyml"
echo 'fn dlp_one(): i64 { return 1; }' > "$P/src/lib.cyr"
run "$P" "$D/a14.out" sh -c 'ln -s "$1" ".distchk$$.cyr" && echo $$ > .planted && exec "$2" distlib' _ "$V/planted_dl" "$D/bin/cyrius"
[ -e "$V/planted_dl" ] && { fail "axis 14: cyrius distlib wrote its self-check entry THROUGH .distchk<pid>.cyr into $V/planted_dl: $(head -1 "$V/planted_dl")"; a=1; }
[ "$rc" -eq 0 ] || { fail "axis 14: cyrius distlib failed (rc=$rc):"; sed 's/^/      /' "$D/a14.out" | head -3; a=1; }
[ -f "$P/.planted" ] && [ ! -e "$P/.distchk$(cat "$P/.planted").cyr" ] && [ ! -L "$P/.distchk$(cat "$P/.planted").cyr" ] \
  || { fail "axis 14: the planted .distchk<pid>.cyr is still there — the self-check never reached it (pid not kept?)"; a=1; }
[ "$a" = 0 ] && echo "  ok: axis 14: cyrius distlib removes a committed .distchk<pid>.cyr link and creates its self-check entry fresh; nothing written where it pointed"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: project_writes_stay_in_tree (cyrius update, deps --lock, build's relock, cyriusly use, cyrius fmt and cyrius port write through a link only to a file inside the project and outside its .git, refuse every other link by name and write nothing; in-tree links still written through)"
