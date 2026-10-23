#!/bin/sh
# deps_plaintext_url_refused.sh — `cyrius deps` REFUSES a dependency whose git URL is a plaintext
# transport (git://, http://, ftp://), by name, before anything is fetched (6.7.18; the 2026-10-22
# audit's Finding 26; the user's decision at the audit: "cyrius deps refuses plaintext git:// /
# http:// dependency URLs by name"; https://, ssh://, git@host: and local paths stay).
#
# THE DEFECT. `_dep_git_remote` accepted any `scheme://`, and the clone argv was
# `git clone --depth 1 -q -b <tag> -- <url> <dir>` with no transport check and no protocol.allow:
# a `[deps.foo] git = "git://…"` resolved over the clear, and on a FIRST resolve (no lock pin yet,
# or `cyrius update` of an untagged dep) an on-path attacker substituted the dependency — vendored
# into lib/ and compiled — and cyrius.lock then commit-pinned the attacker's commit, turning later
# honest fetches into "commit-pin mismatch" refusals. Measured at 6.7.17 (the audit's repro, a
# local `git daemon`): "1 deps resolved", "1 commit-pinned (1 re-verified)", rc 0, no warning.
#
# THE FIX (cbt/deps/local.cyr). `_dep_pick` refuses a git source whose scheme is git / http / ftp
# (`<scheme>://`, a remote helper NAMED git / http / ftp, or a helper whose URL is one of those —
# `https::http://…` — any case) with the dep, the owner and the URL named;
# `_dep_report_newer_tags` never lists one; and every fetching git argv carries
# `-c protocol.{git,http,ftp,ext}.allow=never` (`_git_no_plaintext`), so a URL the scheme check
# misreads — or an https redirect to http — still cannot fetch in the clear.
#
# AXES (Linux / macOS; git required, `git daemon` optional — A1 SKIPS by name without it):
#   A1  git://127.0.0.1:<port>/foo.git served by a live `git daemon`: rc != 0, the refusal names
#       the dep and the URL, the daemon saw NO upload-pack request, lib/foo.cyr not vendored, no
#       commit pin written
#   A2  http://127.0.0.1:<port>/foo.git, HTTP://…, Git://…, ftp://… and the remote-helper spellings
#       http::http://…, http::host/…, git::git://…, https::http://…, HTTPS::HTTP://…,
#       https::ftp://… and persistent-https::http://… (nothing listening): each refused by name, no
#       "git clone failed" (nothing was attempted)
#   A2c controls: https::https://… and ext::true are NOT refused as plaintext — the clone is
#       attempted (ext:: is a command the developer chose; the protocol.ext.allow=never belt has it)
#   A3  a dependency's OWN manifest naming git:// (resolved from a file:// origin): refused, the
#       owner named
#   A4  control: the same repository over file:// resolves (rc 0, lib/foo.cyr vendored)
#   A5  STATIC: the clone argv and `_dep_wt_run` (ls-remote) carry `_git_no_plaintext`, which
#       names git, http, ftp and ext
#
# MUTATION LEDGER (6.7.18, each a copy of the tree's cbt/):
#   the parent (b873a1eca's cbt/)                    -> A1 A2 A3 A5 RED (A1: resolved over git://)
#   `_dep_pick` without the plaintext refusal        -> A1 A2 A3 RED (A1 still fetches nothing: the
#                                                       protocol.git.allow=never belt makes git
#                                                       refuse — the refusal is git's, not named)
# ⚠ The belt yields to an inherited GIT_ALLOW_PROTOCOL — git's design: that variable overrides
#   every protocol.<p>.allow — so a user who lists git or http there has opted in at the git
#   level; the named refusal in `_dep_pick` still stands. This gate unsets it.
#   `_git_no_plaintext` dropped from the clone argv  -> A5 RED
#   (6.7.18, the cleanup lane) `_dep_git_plaintext` as the audit fix left it — the leading name
#   only, at most 8 characters: https::http://, HTTPS::HTTP://, https::ftp:// and
#   persistent-https::http:// fetched (git's belt then answered `Protocol "http" is disabled`,
#   not the named refusal)                         -> those four A2 rows RED
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_plaintext_url_refused
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
DPID=""
trap '[ -n "$DPID" ] && kill "$DPID" 2>/dev/null; chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"; true' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V/bin" "$H/deps" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
# git's own default policy (git, http, https, ssh "always"; file "user"), so the defect — a CLI
# that fetches — is visible in A1. An inherited GIT_ALLOW_PROTOCOL is dropped: by git's design it
# OVERRIDES every `-c protocol.<p>.allow`, so a CI that sets it would hide or fake A1.
unset GIT_ALLOW_PROTOCOL
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# The origin: foo, tag 1.0.0, shipping dist/foo.cyr; a bare copy the daemon serves.
O="$W/srv/foo"; mkdir -p "$O/dist"
printf 'fn foo_answer(): i64 { return 42; }\n' > "$O/dist/foo.cyr"
( cd "$O" && git init -q . && git add -A && git commit -qm v1 && git tag 1.0.0 ) || { echo "FAIL: $G: cannot build the origin"; exit 1; }
git clone -q --bare "$O" "$W/srv/foo.git" && touch "$W/srv/foo.git/git-daemon-export-ok" || { echo "FAIL: $G: cannot make the bare origin"; exit 1; }
# An origin whose OWN manifest names a git:// dependency (A3).
B="$W/srv/outer"; mkdir -p "$B/dist"
printf 'fn outer_f(): i64 { return 1; }\n' > "$B/dist/outer.cyr"
printf '[package]\nname = "outer"\nversion = "1.0.0"\nlanguage = "cyrius"\n\n[deps.inner]\ngit = "git://127.0.0.1:9/inner.git"\ntag = "1.0.0"\nmodules = ["dist/inner.cyr"]\n' > "$B/cyrius.cyml"
( cd "$B" && git init -q . && git add -A && git commit -qm v1 && git tag 1.0.0 ) || { echo "FAIL: $G: cannot build the outer origin"; exit 1; }

# mkproj <dir> <dep name> <git url>: a project with one [deps] entry at tag 1.0.0
mkproj() {
    mkdir -p "$1"
    printf '[package]\nname = "pp"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[deps.%s]\ngit = "%s"\ntag = "1.0.0"\nmodules = ["dist/%s.cyr"]\n' "$V" "$2" "$3" "$2" > "$1/cyrius.cyml"
}
# deps_in <dir>: `cyrius deps` there with the throwaway home; output in <dir>/out.txt, rc echoed
deps_in() {   # each run starts from an empty dep cache: one axis's clone is never another's
    rm -rf "$H/deps" && mkdir -p "$H/deps"
    _rc=0
    ( cd "$1" && HOME="$W/uhome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 timeout 120 "$CY" deps ) > "$1/out.txt" 2>&1 || _rc=$?
    echo "$_rc"
}
mkdir -p "$W/uhome"

# ── A1: git:// against a live daemon ──
if git daemon --help > /dev/null 2>&1 || git help -a 2>/dev/null | grep -q '^ *daemon'; then
    PORT=$(( 20000 + $$ % 20000 ))
    git daemon --export-all --base-path="$W/srv" --port="$PORT" --listen=127.0.0.1 --reuseaddr --verbose \
        > "$W/daemon.log" 2>&1 &
    DPID=$!
    up=0; i=0
    while [ $i -lt 50 ]; do
        git ls-remote "git://127.0.0.1:$PORT/foo.git" > /dev/null 2>&1 && { up=1; break; }
        sleep 0.1; i=$((i + 1))
    done
    if [ "$up" = 1 ]; then
        : > "$W/daemon.log.mark"; before=$(grep -c 'upload-pack' "$W/daemon.log" 2>/dev/null || true)
        P1="$W/p1"; mkproj "$P1" foo "git://127.0.0.1:$PORT/foo.git"
        rc=$(deps_in "$P1")
        after=$(grep -c 'upload-pack' "$W/daemon.log" 2>/dev/null || true)
        if [ "$rc" != 0 ] && grep -q "\[deps.foo\] git = \"git://127.0.0.1:$PORT/foo.git\", a plaintext git URL" "$P1/out.txt" \
           && [ "$before" = "$after" ] && [ ! -f "$P1/lib/foo.cyr" ] && ! grep -q '^commit' "$P1/cyrius.lock" 2>/dev/null; then
            ok "A1: git:// against a live daemon is refused by name (rc $rc), nothing fetched, nothing vendored or pinned"
        else
            bad "A1: git:// (rc $rc, daemon upload-packs $before -> $after, vendored: $([ -f "$P1/lib/foo.cyr" ] && echo yes || echo no)): $(grep -m2 -E 'error|resolved|locked' "$P1/out.txt" | tr '\n' ' ')"
        fi
    else
        echo "  SKIP: A1 — git daemon did not come up on 127.0.0.1:$PORT (A2-A5 still run)"
    fi
    kill "$DPID" 2>/dev/null || true
    wait "$DPID" 2>/dev/null || true   # 143: it was killed (and `set -e` callers must live)
    DPID=""
else
    echo "  SKIP: A1 — this git has no daemon (A2-A5 still run)"
fi

# ── A2: http:// and spellings, nothing listening ──
n=0
for url in "http://127.0.0.1:9/foo.git" "HTTP://127.0.0.1:9/foo.git" "Git://127.0.0.1:9/foo.git" "http::http://127.0.0.1:9/foo.git" "ftp://127.0.0.1:9/foo.git" \
           "http::127.0.0.1:9/foo.git" "git::git://127.0.0.1:9/foo.git" "https::http://127.0.0.1:9/foo.git" \
           "HTTPS::HTTP://127.0.0.1:9/foo.git" "https::ftp://127.0.0.1:9/foo.git" "persistent-https::http://127.0.0.1:9/foo.git"; do
    n=$((n + 1)); P2="$W/p2_$n"; mkproj "$P2" foo "$url"
    rc=$(deps_in "$P2")
    if [ "$rc" != 0 ] && grep -qF "[deps.foo] git = \"$url\", a plaintext" "$P2/out.txt" && ! grep -q 'git clone failed' "$P2/out.txt"; then
        ok "A2: $url refused by name before any fetch (rc $rc)"
    else
        bad "A2: $url (rc $rc): $(grep -m2 -E 'error|resolved' "$P2/out.txt" | tr '\n' ' ')"
    fi
done

# ── A2c: controls — a helper whose URL is not plaintext, and ext:: (a command the developer
#    chose, refused by the belt, not by this check), are not refused AS plaintext: the clone is
#    attempted (and fails: nothing listens on port 9, and protocol.ext.allow=never) ──
n=0
for url in "https::https://127.0.0.1:9/foo.git" "ext::true"; do
    n=$((n + 1)); P2="$W/p2c_$n"; mkproj "$P2" foo "$url"
    rc=$(deps_in "$P2")
    if [ "$rc" != 0 ] && ! grep -q 'a plaintext' "$P2/out.txt" && grep -q 'git clone failed' "$P2/out.txt"; then
        ok "A2c: control — $url is not refused as plaintext; the clone is attempted (rc $rc)"
    else
        bad "A2c: control $url (rc $rc): $(grep -m2 -E 'error|resolved|failed' "$P2/out.txt" | tr '\n' ' ')"
    fi
done

# ── A3: a dependency's own manifest naming git:// ──
P3="$W/p3"; mkproj "$P3" outer "file://$B"
rc=$(deps_in "$P3")
if [ "$rc" != 0 ] && grep -q "outer's manifest names \[deps.inner\] git = \"git://127.0.0.1:9/inner.git\", a plaintext git URL" "$P3/out.txt"; then
    ok "A3: a dependency's own git:// entry is refused, its owner named (rc $rc)"
else
    bad "A3: a dependency's git:// entry (rc $rc): $(grep -m2 -E 'error|resolved' "$P3/out.txt" | tr '\n' ' ')"
fi

# ── A4: control — file:// resolves ──
P4="$W/p4"; mkproj "$P4" foo "file://$W/srv/foo.git"
rc=$(deps_in "$P4")
if [ "$rc" = 0 ] && grep -q 'foo_answer' "$P4/lib/foo.cyr" 2>/dev/null; then
    ok "A4: control — the same repository over file:// resolves and vendors lib/foo.cyr"
else
    bad "A4: file:// (rc $rc): $(grep -m2 -E 'error|resolved' "$P4/out.txt" | tr '\n' ' ')"
fi

# ── A5: STATIC — git itself refuses the plaintext transports on every fetching argv ──
a5=0
for p in git http ftp ext; do
    grep -q "\"protocol\.$p\.allow=never\"" cbt/deps/git_cache.cyr || { bad "A5: _git_no_plaintext does not name protocol.$p.allow=never"; a5=1; }
done
grep -q '_git_no_plaintext(&gargv, gai)' cbt/deps/named.cyr || { bad "A5: the clone argv does not carry _git_no_plaintext"; a5=1; }
awk '/^fn _dep_wt_run\(/ { f = 1 } f && /_git_no_plaintext\(&argv, i\)/ { hit = 1 } /^}/ { f = 0 } END { exit hit ? 0 : 1 }' cbt/deps/local.cyr \
  || { bad "A5: _dep_wt_run (ls-remote) does not carry _git_no_plaintext"; a5=1; }
[ "$a5" = 0 ] && ok "A5: the clone and ls-remote argvs carry -c protocol.{git,http,ftp,ext}.allow=never"

echo ""
if [ "$fail" -gt 0 ]; then echo "FAIL: $G ($pass ok, $fail failed)"; exit 1; fi
echo "PASS: $G ($pass rows: a plaintext git://, http:// or ftp:// dependency is refused by name before any fetch; file:// still resolves)"
