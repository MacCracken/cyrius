#!/bin/sh
# install_paths_ship_init_templates.sh — 6.7.7. EVERY install path puts the cyrius-init scaffolding
# templates where the installed cyrius-init binary resolves them: <root>/programs/cyrius-init-templates,
# root = versions/<v> (the binary's own bin/ parent).
#
# ⛔ THE DEFECT. scripts/install.sh has three ways to fill versions/<v>: `--refresh-only` (from a
# checkout — what version-bump.sh and `cyrius pulsar` run), the TARBALL path (`cyriusly install`,
# `curl | sh`), and the SOURCE-BOOTSTRAP path (no tarball for the tag: clone it, bootstrap from the
# seed, build the tools). The first two copied programs/cyrius-init-templates into the slot; the
# source-bootstrap path copied bin/ and lib/ only. After a source install `cyrius init` /
# `cyrius port` ran a binary that could not find a single template.
#
# AXES — install.sh runs under `env -i` with a throwaway HOME, CYRIUS_HOME, TMPDIR and
# XDG_CONFIG_HOME; a stub curl answers 22 to every URL and a stub git "clones" a mini source
# tree, so nothing reaches the network and nothing touches the live store:
#   1  the TARBALL path (CYRIUS_INSTALL_TARBALL, a release-shaped tarball whose
#      programs/cyrius-init-templates is the tree's): the slot's templates equal the tree's
#   2  the REFRESH-ONLY path, from a mini checkout (bins = [], untagged) holding the tree's
#      templates: the slot's templates equal the tree's
#   3  the SOURCE-BOOTSTRAP path (Linux only — install.sh refuses it elsewhere): no tarball, the
#      stub git copies a mini source tree whose bootstrap.sh builds a stub build/cycc; the run must
#      say "bootstrapped from source" (anti-vacuous: it took THAT path) and the slot's templates
#      equal the tree's
#   4  install.ps1 (static — no PowerShell on a check host): it copies <stage>\programs into
#      versions\<v>\programs AND <home>\programs (bin\ is a copy at both levels on Windows)
# "Equal" is `diff -r` against programs/cyrius-init-templates, whose file count is floored so an
# empty tree cannot read green.
#
# MUTATION LEDGER (6.7.7, measured in this worktree): the source-bootstrap copy removed from
# install.sh (the 6.7.6 shape) -> axis 3 RED ("templates MISSING"), axes 1, 2, 4 green; the
# refresh-only copy removed -> axis 2 RED ("MISSING"); the tarball path's `cp -R` removed -> axis 1
# RED (an empty directory: "differ"); install.ps1's `Copy-Item "$Stage\programs\*"` line removed
# -> axis 4 RED. Each mutant reddens its own axis alone.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=install_paths_ship_init_templates
TPL="$ROOT/programs/cyrius-init-templates"

for t in tar gzip diff; do
    command -v "$t" > /dev/null 2>&1 || { echo "SKIP: $NAME — no $t on this host"; exit 77; }
done
NT=$(find "$TPL" -type f 2>/dev/null | grep -c . || true)
[ "$NT" -ge 20 ] || { echo "FAIL: $NAME — only $NT file(s) under programs/cyrius-init-templates; the comparison would be blind"; exit 1; }

W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0
bad() { echo "  FAIL $1"; sed 's/\x1b\[[0-9;]*m//g' "$W/out" 2>/dev/null | tail -4 | LC_ALL=C tr -c '[:print:]\n' '?' | sed 's/^/    /'; fail=1; }

ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH=x86_64 ;; aarch64|arm64) ARCH=aarch64 ;; *) ARCH="" ;; esac
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in linux) OSS=linux ;; darwin) OSS=macos ;; *) OSS="" ;; esac
[ -n "$ARCH" ] && [ -n "$OSS" ] || { echo "SKIP: $NAME — install.sh installs on Linux / macOS x86_64 / aarch64 only"; exit 77; }

# stub curl: nothing is published (so the source path is taken when no local tarball is given, and
# the trailing cyriusly fetch fails quietly). stub git: `git clone … <dest>` copies $W/src.
mkdir -p "$W/fakebin" "$W/gitbin"
printf '#!/bin/sh\nexit 22\n' > "$W/fakebin/curl"
cat > "$W/gitbin/git" <<EOF
#!/bin/sh
[ "\$1" = clone ] || exit 1
for _a in "\$@"; do _d=\$_a; done
mkdir -p "\$_d" && cp -R "$W/src/." "\$_d/"
EOF
chmod +x "$W/fakebin/curl" "$W/gitbin/git"

# inst <cwd> <home> <args...> — install.sh into <home>/store (never <home>/.cyrius: that is the
# user's store by definition, which the refresh-only released-slot guard treats as live). The stub
# git is on PATH only when XPATH names it (axis 3); refresh-only runs the real git.
inst() {
    _d=$1; _h=$2; shift 2
    mkdir -p "$_h/tmp"
    RC=0
    ( cd "$_d" && env -i HOME="$_h" CYRIUS_HOME="$_h/store" PATH="$W/fakebin:${XPATH:+$XPATH:}/usr/bin:/bin" TMPDIR="$_h/tmp" \
        XDG_CONFIG_HOME="$_h/.config" "$@" ) > "$W/out" 2>&1 || RC=$?
}
# shipped <label> <home> — the slot's templates are the tree's, byte for byte
shipped() {
    _st="$2/store/versions/9.9.9/programs/cyrius-init-templates"
    if [ "$RC" -ne 0 ]; then bad "$1: install.sh exit $RC"; return 1; fi
    if [ ! -d "$_st" ]; then bad "$1: templates MISSING — versions/9.9.9/programs/cyrius-init-templates was not installed"; return 1; fi
    if ! diff -r "$TPL" "$_st" > "$W/diff" 2>&1; then
        bad "$1: the installed templates differ from programs/cyrius-init-templates"
        head -3 "$W/diff" | sed 's/^/    /'
        return 1
    fi
    return 0
}

# ── axis 1: the tarball path ──
S1="$W/t1/stage/cyrius-9.9.9-$ARCH-$OSS"
mkdir -p "$S1/bin" "$S1/lib" "$S1/programs" "$W/t1/cwd"
printf '#!/bin/sh\necho stub-cycc\n' > "$S1/bin/cycc"
chmod +x "$S1/bin/cycc"
printf 'fn x(): i64 { return 0; }\n' > "$S1/lib/x.cyr"
cp -R "$TPL" "$S1/programs/"
( cd "$W/t1/stage" && tar czf "$W/t1/tb.tar.gz" "cyrius-9.9.9-$ARCH-$OSS" ) || { echo "FAIL: $NAME — cannot build the axis-1 tarball"; exit 1; }
inst "$W/t1/cwd" "$W/h1" CYRIUS_VERSION=9.9.9 CYRIUS_INSTALL_TARBALL="$W/t1/tb.tar.gz" sh "$ROOT/scripts/install.sh"
shipped "axis 1 (tarball path)" "$W/h1" && echo "  ok axis 1: the tarball path ships the templates ($NT files) to versions/<v>/programs"

# ── axis 2: the refresh-only path, from a mini checkout ──
M="$W/m2"
mkdir -p "$M/lib" "$M/scripts" "$M/programs"
cp "$ROOT/scripts/install.sh" "$M/scripts/install.sh"
printf '9.9.9\n' > "$M/VERSION"
printf 'fn x(): i64 { return 0; }\n' > "$M/lib/x.cyr"
printf '[package]\nname = "m"\nversion = "9.9.9"\n\n[release]\nbins = []\ncross_bins = []\nscripts = []\n' > "$M/cyrius.cyml"
cp -R "$TPL" "$M/programs/"
if command -v git > /dev/null 2>&1; then
    ( cd "$M" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm m ) > /dev/null 2>&1
fi
inst "$M" "$W/h2" sh scripts/install.sh --refresh-only
shipped "axis 2 (refresh-only path)" "$W/h2" && echo "  ok axis 2: the refresh-only path ships the templates to versions/<v>/programs"

# ── axis 3: the source-bootstrap path ──
if [ "$OSS" = linux ]; then
    # The mini source tree the stub git "clones". bootstrap.sh builds a build/cycc that copies
    # stdin to stdout, and src/main.cyr is a script that does the same, so install.sh's self-host
    # check (cycc(src) run on src, cmp) holds without a real compiler.
    mkdir -p "$W/src/bootstrap" "$W/src/src" "$W/src/lib" "$W/src/programs" "$W/c3"
    printf 'mkdir -p build && printf "#!/bin/sh\\ncat\\n" > build/cycc && chmod +x build/cycc\n' > "$W/src/bootstrap/bootstrap.sh"
    printf '#!/bin/sh\ncat\n' > "$W/src/src/main.cyr"
    printf 'fn x(): i64 { return 0; }\n' > "$W/src/lib/x.cyr"
    printf '[package]\nname = "cyrius"\nversion = "9.9.9"\n\n[release]\nbins = ["cycc"]\ncross_bins = []\nscripts = []\n' > "$W/src/cyrius.cyml"
    cp -R "$TPL" "$W/src/programs/"
    XPATH="$W/gitbin" inst "$W/c3" "$W/h3" CYRIUS_VERSION=9.9.9 sh "$ROOT/scripts/install.sh"
    if ! grep -q "bootstrapped from source" "$W/out"; then
        bad "axis 3 (source-bootstrap path): the run never reached the source bootstrap (exit $RC)"
    else
        shipped "axis 3 (source-bootstrap path)" "$W/h3" && echo "  ok axis 3: the source-bootstrap path ships the templates to versions/<v>/programs"
    fi
else
    echo "  skip axis 3: install.sh's source bootstrap is Linux-only (it refuses on $OSS)"
fi

# ── axis 4: install.ps1 (static) ──
PS="$ROOT/scripts/install.ps1"
a4=0
: > "$W/out"
grep -qF 'Copy-Item "$Stage\programs\*" "$VerDir\programs\" -Force -Recurse' "$PS" || { bad "axis 4: install.ps1 no longer copies <stage>\\programs into versions\\<v>\\programs"; a4=1; }
grep -qF 'Copy-Item "$VerDir\programs\*" "$CyriusHome\programs\" -Force -Recurse' "$PS" || { bad "axis 4: install.ps1 no longer copies the templates beside <home>\\bin"; a4=1; }
[ "$a4" -eq 0 ] && echo "  ok axis 4: install.ps1 copies the templates into versions\\<v>\\programs and <home>\\programs"

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (the tarball, refresh-only and source-bootstrap paths of install.sh, and install.ps1, ship programs/cyrius-init-templates)"
