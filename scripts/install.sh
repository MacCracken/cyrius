#!/bin/sh
# Cyrius installer
# Usage: curl -sSf https://install.cyrius.dev | sh
#    or: curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh
#
# Installs the Cyrius toolchain to ~/.cyrius/
# Structure:
#   ~/.cyrius/
#     bin/              symlinks to active version (on PATH)
#     versions/0.9.0/   version-specific binaries
#     current           active version file
#
# Environment:
#   CYRIUS_VERSION   install specific version (default: latest)
#   CYRIUS_HOME      install directory (default: ~/.cyrius)

set -e

CYRIUS_HOME="${CYRIUS_HOME:-$HOME/.cyrius}"
REPO="MacCracken/cyrius"
VERSION="${CYRIUS_VERSION:-}"
ARCH=$(uname -m)

# v5.4.18: --refresh-only mode. Skips tarball fetch / source bootstrap
# and only re-copies lib/ + bin/ from the CURRENT REPO state into
# ~/.cyrius/versions/$VERSION/. Called by version-bump.sh post-bump so
# the install snapshot never lags the repo after a dep or tool bump.
# Only makes sense when run from within a cyrius repo checkout.
REFRESH_ONLY=0
if [ "${1:-}" = "--refresh-only" ]; then
    REFRESH_ONLY=1
    VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null)"
    if [ -z "$VERSION" ]; then
        echo "error: --refresh-only must run from a cyrius repo (VERSION file not found)" >&2
        exit 1
    fi
fi

# Parse a single array from cyrius.cyml's [release] table. Outputs
# space-separated entries. Returns empty if key/section missing.
_parse_release_array() {
    local cyml="${CYRIUS_CYML:-cyrius.cyml}"
    [ -f "$cyml" ] || return 0
    awk -v k="$1" '
        /^\[release\]/ { in_r = 1; next }
        in_r && /^\[/ { exit }
        in_r && $1 == k {
            sub(/^[^=]+= \[/, ""); sub(/\].*$/, "")
            gsub(/[",]/, " "); gsub(/ +/, " ")
            sub(/^ +/, ""); sub(/ +$/, ""); print; exit
        }' "$cyml"
}

# Colors (if terminal)
if [ -t 1 ]; then
    BOLD="\033[1m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
    DIM="\033[2m"
    RESET="\033[0m"
else
    BOLD="" GREEN="" YELLOW="" RED="" DIM="" RESET=""
fi

info() { printf "  ${GREEN}>${RESET} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
err()  { printf "  ${RED}x${RESET} %s\n" "$1" >&2; exit 1; }

# ── Detect platform ──

case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) err "unsupported architecture: $ARCH" ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
# Map the host OS to the release tarball suffix. The release pipeline
# publishes per-OS artifacts: <arch>-linux, <arch>-macos, <arch>-windows.
case "$OS" in
    linux)                        OS_SUFFIX="linux" ;;
    darwin)                       OS_SUFFIX="macos" ;;
    mingw*|msys*|cygwin*|windows*) OS_SUFFIX="windows" ;;
    *) err "unsupported OS: $OS (Cyrius targets Linux, macOS, and Windows)" ;;
esac

# ── --refresh-only fast path (v5.4.18) ──
# Skips the Installer banner, version resolve, tarball fetch, and source
# bootstrap. Just re-copies the current repo's build/ + lib/ + scripts
# named in cyrius.cyml [release] into ~/.cyrius/versions/$VERSION/.
# Purpose: version-bump.sh calls this after bumping so the install
# snapshot never rots behind dep/tool bumps.
if [ "$REFRESH_ONLY" -eq 1 ]; then
    printf "\n${BOLD}Refreshing install snapshot for %s${RESET}\n" "$VERSION"
    mkdir -p "$CYRIUS_HOME/versions/$VERSION/bin"
    mkdir -p "$CYRIUS_HOME/versions/$VERSION/lib"

    _R_BINS=$(_parse_release_array bins)
    _R_CROSS=$(_parse_release_array cross_bins)
    _R_SCRIPTS=$(_parse_release_array scripts)

    # v5.8.53: rebuild stale build/<bin> from source before copying.
    # Pre-fix, --refresh-only only `cp`'d existing build/<bin> into the
    # snapshot — so a stale binary (gitignored, dev-local) propagated
    # forever. Symptom: cycc_aarch64 froze at 438896 B from v5.8.46
    # through v5.8.52 because `build/cycc_aarch64` was last rebuilt
    # before the v5.8.46 token-cap raise; sit v0.7.2 release flow hit
    # the old 262144 cap on aarch64 cross-build six version-bumps
    # later. The version-bump.sh post-hook calls --refresh-only on
    # every patch; if rebuild is the contract, the contract has to
    # actually rebuild.
    #
    # Source-mapping rules:
    #   - bins entry "cycc"     → seed-bootstrapped, NOT rebuilt here.
    #   - bins entry "cyrius"  → cbt/cyrius.cyr
    #   - bins entry <other>   → programs/<name>.cyr (cyrlint, cyrfmt, ark, …)
    #   - cross_bins "cycc_aarch64" → src/main_aarch64.cyr
    #   - cross_bins <other>      → src/main_<arch>.cyr (future-proof)
    #
    # Staleness rule: rebuild if binary is missing OR source mtime is
    # newer than binary mtime (`-nt`). Errors are surfaced (no
    # `2>/dev/null` swallow) — if cycc emits warnings we want them
    # visible so the next stale-binary trap doesn't take six bumps
    # to discover.
    _rebuild_stale() {
        local target="$1"
        local source="$2"
        [ -f "$source" ] || return 0
        if [ -x "build/$target" ] && [ "build/$target" -nt "$source" ]; then
            return 0
        fi
        if [ ! -x "build/cycc" ]; then
            warn "build/cycc missing — cannot rebuild $target from $source; falling back to existing binary"
            return 1
        fi
        local err_log
        err_log=$(mktemp)
        if cat "$source" | ./build/cycc > "build/$target" 2>"$err_log"; then
            chmod +x "build/$target"
            info "rebuilt $target from $source"
            if [ -s "$err_log" ]; then
                # cycc emitted warnings/notes. Don't fail — these are
                # commonly the "note: N unreachable fns" diagnostic and
                # cross-arch latent-fn warnings (see v5.8.54 EFLADDR/PE
                # parity slot). Surface them so they don't rot silently.
                sed 's/^/    /' "$err_log" >&2
            fi
            rm -f "$err_log"
            return 0
        else
            warn "rebuild of $target from $source failed:"
            sed 's/^/    /' "$err_log" >&2
            rm -f "$err_log"
            rm -f "build/$target"
            return 1
        fi
    }

    for bin in $_R_BINS; do
        case "$bin" in
            cycc)    : ;;  # seed-bootstrapped, never rebuilt by --refresh-only
            cyrius) _rebuild_stale "cyrius" "cbt/cyrius.cyr" ;;
            *)      _rebuild_stale "$bin"    "programs/${bin}.cyr" ;;
        esac
    done
    for cbin in $_R_CROSS; do
        case "$cbin" in
            cycc_aarch64) _rebuild_stale "cycc_aarch64" "src/main_aarch64.cyr" ;;
            cycc-native-aarch64)
                # v6.0.7 — native aarch64 self-host. Built by piping
                # src/main_aarch64_native.cyr through build/cycc_aarch64
                # (the x86-host cross-compiler that emits aarch64).
                # _rebuild_stale's build path uses build/cycc (x86),
                # which would produce an x86 binary — so we skip
                # _rebuild_stale and let `cyrius pulsar` handle the
                # native build chain. The binary stays committed
                # (.gitignore whitelist) so a stale x86-host install
                # still has a usable native binary in lockstep.
                : ;;
            cycc_win)
                # v6.0.50: unfreeze the PE compiler. Build cycc_win from
                # src/main_win.cyr with CYRIUS_TARGET_WIN=1 (the x86 cycc
                # emits a PE32+ cycc that runs on Windows) instead of copying
                # the frozen cc5_win 5.11.69 binary forward. The 5.11.69 freeze
                # blocked consumers (ai-hwaccel) whose 6.0.x stdlib WIN closure
                # the old frontend couldn't resolve (`undefined PROT_READ`).
                # _rebuild_stale can't set the env var, so the build is inlined;
                # rebuilt unconditionally (no -nt skip) so the unfreeze can't be
                # skipped by the frozen binary's mtime. See issue
                # 2026-06-03-windows-pe-syscall-surface-blocks-detection.md.
                if [ -f src/main_win.cyr ] && [ -x build/cycc ]; then
                    _cw_err=$(mktemp)
                    if cat src/main_win.cyr | CYRIUS_TARGET_WIN=1 ./build/cycc > build/cycc_win 2>"$_cw_err"; then
                        chmod +x build/cycc_win
                        info "rebuilt cycc_win from src/main_win.cyr (CYRIUS_TARGET_WIN=1 → PE32+)"
                        [ -s "$_cw_err" ] && sed 's/^/    /' "$_cw_err" >&2
                    else
                        warn "rebuild of cycc_win failed:"; sed 's/^/    /' "$_cw_err" >&2; rm -f build/cycc_win
                    fi
                    rm -f "$_cw_err"
                fi
                ;;
            *) warn "unknown cross_bins entry '$cbin' — no rebuild rule, will copy existing build/$cbin if present" ;;
        esac
    done

    _refreshed=0
    for bin in $_R_BINS $_R_CROSS; do
        if [ -x "build/$bin" ]; then
            cp "build/$bin" "$CYRIUS_HOME/versions/$VERSION/bin/"
            _refreshed=$((_refreshed + 1))
        fi
    done
    [ -f bootstrap/asm ] && cp bootstrap/asm "$CYRIUS_HOME/versions/$VERSION/bin/"

    # v6.1.0: the v6.0.x back-compat install symlinks (cc5 → cycc,
    # cyrc → cybs, + cross-arch variants) were DROPPED here per the
    # v6.0.0 closeout plan. The rename grace period is over; consumers
    # still pinned to 5.11.x must re-pin to a 6.x tag. cycc / cybs are
    # the only names installed.

    # v5.8.53: also rebuild dlopen-helper from C source. Pre-fix, the
    # full-install path (lines below) compiled the helper but
    # --refresh-only skipped it entirely — so a host libc upgrade
    # between two version-bump.sh invocations would leave the snapshot
    # with a stale helper. Same shape as the cross-compiler trap.
    if [ -f "programs/dlopen-helper.c" ]; then
        if command -v cc > /dev/null 2>&1; then _CC=cc
        elif command -v gcc > /dev/null 2>&1; then _CC=gcc
        else _CC=""
        fi
        if [ -n "$_CC" ]; then
            if "$_CC" -O2 -fPIE -pie -o "$CYRIUS_HOME/dlopen-helper" \
                programs/dlopen-helper.c -ldl 2>/tmp/dlopen_err_$$; then
                info "dlopen-helper rebuilt"
            else
                warn "dlopen-helper rebuild failed:"
                sed 's/^/    /' /tmp/dlopen_err_$$ >&2
            fi
            rm -f /tmp/dlopen_err_$$
            cp programs/dlopen-helper.c "$CYRIUS_HOME/versions/$VERSION/bin/dlopen-helper.c"
        fi
    fi

    for script in $_R_SCRIPTS; do
        # v5.11.69: shim scripts (cyrius-init/port/repl) moved to
        # scripts/shims/. Look there first; fall through to flat
        # scripts/ for the genuinely user-facing scripts that stayed.
        if [ -f "scripts/shims/$script" ]; then
            cp "scripts/shims/$script" "$CYRIUS_HOME/versions/$VERSION/bin/"
            chmod +x "$CYRIUS_HOME/versions/$VERSION/bin/$script"
            _refreshed=$((_refreshed + 1))
        elif [ -f "scripts/$script" ]; then
            cp "scripts/$script" "$CYRIUS_HOME/versions/$VERSION/bin/"
            chmod +x "$CYRIUS_HOME/versions/$VERSION/bin/$script"
            _refreshed=$((_refreshed + 1))
        fi
    done

    # Stdlib refresh (follow symlinks so dep content gets dereferenced).
    # v5.8.49: walk subdirs recursively so nested stdlib (e.g.
    # `lib/unicode/*.cyr`) reaches the snapshot. Pre-fix, the flat
    # `for f in lib/*.cyr` glob silently dropped subdir files —
    # surfaced when v5.8.49 added the first lib/ subdirectory and
    # consumers couldn't find lib/unicode/categories.cyr through
    # `cyrius deps`. -L on `find` follows symlinks during traversal;
    # `cp -L` deferences any symlinked files when copying.
    _lib_count=0
    while IFS= read -r f; do
        [ -e "$f" ] || continue
        # Compute the destination path preserving the lib/-relative
        # structure: strip leading "lib/", join with snapshot lib dir.
        rel="${f#lib/}"
        dst="$CYRIUS_HOME/versions/$VERSION/lib/$rel"
        mkdir -p "$(dirname "$dst")"
        cp -L "$f" "$dst"
        _lib_count=$((_lib_count + 1))
    done <<EOF_LIB
$(find -L lib -type f -name '*.cyr')
EOF_LIB

    # v6.0.60: cyrius-init scaffolding templates → versions/<v>/programs/ so the
    # cyrius-init binary (F_GETPATH-resolved <root>/programs/cyrius-init-templates)
    # finds them on installs (finishes the v5.9.29 install template path; was
    # dev-mode/repo-only, so installs fell through to the bash shim).
    if [ -d programs/cyrius-init-templates ]; then
        mkdir -p "$CYRIUS_HOME/versions/$VERSION/programs"
        rm -rf "$CYRIUS_HOME/versions/$VERSION/programs/cyrius-init-templates"
        cp -r programs/cyrius-init-templates "$CYRIUS_HOME/versions/$VERSION/programs/"
    fi

    echo "$VERSION" > "$CYRIUS_HOME/current"
    echo "$VERSION" > "$CYRIUS_HOME/versions/$VERSION/VERSION"

    # v5.7.22: re-link ~/.cyrius/bin → versions/$VERSION/bin so the
    # PATH-resolved cyrius/cycc/cyrfmt/cyrlint binaries match the
    # version we just refreshed. Pre-v5.7.22, --refresh-only updated
    # the snapshot but left the bin/ symlink pointing at whatever
    # version was previously active. Local devs running version-bump.sh
    # back-to-back saw `cyrius --version` reporting a stale binary
    # while ~/.cyrius/current already advanced (footgun, not breakage).
    # Use rm -rf (not rm -f) so a stale-directory state from an older
    # install also gets cleaned out.
    rm -rf "$CYRIUS_HOME/bin" "$CYRIUS_HOME/lib"
    ln -sf "$CYRIUS_HOME/versions/$VERSION/bin" "$CYRIUS_HOME/bin"
    ln -sf "$CYRIUS_HOME/versions/$VERSION/lib" "$CYRIUS_HOME/lib"

    # v6.0.36: install the build-artifact pre-commit hook when refreshing
    # from inside the git repo, so a fresh clone (or any version-bump) is
    # protected from committing a contaminated build/cycc. See
    # docs/development/issues/archived/2026-05-13-build-artifact-precommit-hook.md.
    if [ -d .git ] && [ -f scripts/hooks/pre-commit ]; then
        cp scripts/hooks/pre-commit .git/hooks/pre-commit && \
            chmod +x .git/hooks/pre-commit && \
            info "installed build-artifact pre-commit hook (.git/hooks/pre-commit)"
    fi

    info "refreshed $_refreshed bins/scripts + $_lib_count stdlib files"
    exit 0
fi

printf "\n${BOLD}Cyrius Installer${RESET}\n\n"

# ── Resolve version ──

if [ -z "$VERSION" ]; then
    VERSION=$(curl -sSf "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || echo "")
    if [ -z "$VERSION" ]; then
        # API rate-limited or offline — fall back to the VERSION file on main
        VERSION=$(curl -sSf "https://raw.githubusercontent.com/${REPO}/main/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    if [ -z "$VERSION" ]; then
        err "could not resolve latest version (GitHub API + raw VERSION both unreachable). Set CYRIUS_VERSION=<tag> and retry."
    fi
fi

info "version:  ${VERSION}"
info "arch:     ${ARCH}"
info "home:     ${CYRIUS_HOME}"
echo ""

# ── Create directory structure ──

mkdir -p "$CYRIUS_HOME"
mkdir -p "$CYRIUS_HOME/versions/$VERSION/bin"

# ── Download tarball or bootstrap from source ──

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}"
TARBALL="cyrius-${VERSION}-${ARCH}-${OS_SUFFIX}.tar.gz"
TMPDIR=$(mktemp -d)
installed=0

# CYRIUS_INSTALL_TARBALL=/path/to/tarball installs from a local file
# instead of fetching from the release page — used to test the real
# install flow against a locally-built tarball (and for offline installs).
_got_tarball=0
if [ -n "${CYRIUS_INSTALL_TARBALL:-}" ] && [ -f "$CYRIUS_INSTALL_TARBALL" ]; then
    info "installing from local tarball: $CYRIUS_INSTALL_TARBALL"
    cp "$CYRIUS_INSTALL_TARBALL" "$TMPDIR/$TARBALL"
    _got_tarball=1
else
    info "downloading Cyrius ${VERSION}..."
    if curl -sSfL "${DOWNLOAD_URL}/${TARBALL}" -o "$TMPDIR/$TARBALL" 2>/dev/null; then
        # Verify checksum if available
        if curl -sSfL "${DOWNLOAD_URL}/${TARBALL}.sha256" -o "$TMPDIR/checksum" 2>/dev/null; then
            cd "$TMPDIR"
            if sha256sum -c checksum > /dev/null 2>&1; then
                info "checksum verified"
            else
                warn "checksum mismatch — continuing anyway"
            fi
            cd - > /dev/null
        fi
        _got_tarball=1
    fi
fi

if [ "$_got_tarball" -eq 1 ]; then
    # Untar into version directory
    tar xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
    EXTRACTED="$TMPDIR/cyrius-${VERSION}-${ARCH}-${OS_SUFFIX}"

    if [ -d "$EXTRACTED/bin" ]; then
        cp -r "$EXTRACTED/bin"/* "$CYRIUS_HOME/versions/$VERSION/bin/"
        chmod +x "$CYRIUS_HOME/versions/$VERSION/bin"/*
        # macOS ships unsigned cross-built Mach-O binaries; an unsigned
        # binary is AMFI-SIGKILL'd on first exec. Ad-hoc codesign each at
        # install time (shell scripts harmlessly fail and are skipped).
        if [ "$OS_SUFFIX" = "macos" ] && command -v codesign > /dev/null 2>&1; then
            for _b in "$CYRIUS_HOME/versions/$VERSION/bin"/*; do
                [ -f "$_b" ] || continue
                if head -c4 "$_b" | od -An -tx1 | tr -d ' \n' | grep -qiE "cffaedfe|cefaedfe|feedface|feedfacf"; then
                    codesign -s - -f "$_b" 2>/dev/null || warn "codesign failed for $(basename "$_b")"
                fi
            done
            info "codesigned macOS binaries (ad-hoc)"
        fi
        info "binaries installed"
    else
        err "release tarball for ${ARCH}-${OS_SUFFIX} has no bin/ — refusing to install a toolchain with no compiler. This is a release-packaging bug; please report it."
    fi

    if [ -d "$EXTRACTED/lib" ]; then
        # v6.0.62: copy the stdlib CONTENTS into a pre-created dir
        # (mkdir + cp -R src/.) rather than the whole-dir form
        # (cp -r src dest/). The whole-dir form returned 0 yet left
        # versions/<v>/lib MISSING on the GitHub macos-15-arm64 runner
        # (yantra CI, 6.0.59+): install printed "standard library installed"
        # and succeeded, but `cyrius lib sync` then failed with "snapshot lib
        # not found". Not reproducible on ecb — a runner-image cp quirk — but
        # the contents-into-premade-dir pattern is exactly what the downstream
        # backfill workaround proved works there, and it matches the bin copy
        # above. Assert non-empty + fail loud so a packaging regression can
        # never again masquerade as success (the macOS-rot lesson). See
        # 2026-06-04-macos-install-lib-snapshot-missing-breaks-lib-sync.md.
        rm -rf "$CYRIUS_HOME/versions/$VERSION/lib"
        mkdir -p "$CYRIUS_HOME/versions/$VERSION/lib"
        cp -R "$EXTRACTED/lib/." "$CYRIUS_HOME/versions/$VERSION/lib/"
        [ -n "$(ls -A "$CYRIUS_HOME/versions/$VERSION/lib" 2>/dev/null)" ] \
            || err "stdlib snapshot empty after copy from $EXTRACTED/lib — release-packaging/cp bug"
        info "standard library installed"
    else
        err "release tarball for ${ARCH}-${OS_SUFFIX} has no lib/ — refusing to install a toolchain with no stdlib. This is a release-packaging bug; please report it."
    fi

    # v6.0.60: cyrius-init scaffolding templates → versions/<v>/programs/ so the
    # cyrius-init binary finds them via its F_GETPATH-resolved root.
    if [ -d "$EXTRACTED/programs/cyrius-init-templates" ]; then
        # Same contents-into-premade-dir pattern as the stdlib copy above —
        # the whole-dir `cp -r dir dest/` form is unreliable on the macOS runner.
        rm -rf "$CYRIUS_HOME/versions/$VERSION/programs/cyrius-init-templates"
        mkdir -p "$CYRIUS_HOME/versions/$VERSION/programs/cyrius-init-templates"
        cp -R "$EXTRACTED/programs/cyrius-init-templates/." "$CYRIUS_HOME/versions/$VERSION/programs/cyrius-init-templates/"
        info "cyrius-init templates installed"
    fi

    installed=1
fi

if [ "$installed" -eq 0 ] && [ "$OS_SUFFIX" != "linux" ]; then
    # The source-bootstrap seed (bootstrap/asm) is a Linux ELF, so the
    # from-source path only works on Linux. On macOS/Windows we rely on
    # the published per-OS tarball; if it's missing, fail clearly rather
    # than running a Linux binary that can't execute here.
    err "no prebuilt Cyrius ${VERSION} for ${ARCH}-${OS_SUFFIX} (and source-bootstrap is Linux-only). Check the release assets for this tag, or build on a Linux host."
fi

if [ "$installed" -eq 0 ]; then
    # No tarball — bootstrap from source
    warn "no prebuilt release found, bootstrapping from source..."
    cd "$TMPDIR"
    git clone --depth 1 --branch "$VERSION" "https://github.com/${REPO}.git" cyrius 2>/dev/null || \
        git clone --depth 1 "https://github.com/${REPO}.git" cyrius
    cd cyrius

    sh bootstrap/bootstrap.sh
    chmod +x build/cycc

    # Verify self-hosting
    cat src/main.cyr | ./build/cycc > /tmp/cc5_verify
    chmod +x /tmp/cc5_verify
    cat src/main.cyr | /tmp/cc5_verify > /tmp/cc5_verify2
    if cmp -s /tmp/cc5_verify /tmp/cc5_verify2; then
        info "self-hosting verified"
    else
        warn "self-hosting check failed, using committed cycc"
    fi

    # Build tools from cyrius.cyml [release].bins + cross_bins
    # (single source of truth introduced at v5.4.18). cyrius itself is
    # special-cased below because its source lives in cbt/, not programs/.
    #
    # v5.8.53: stderr no longer suppressed via `2>/dev/null` and the
    # `|| true` shell trick is gone. Pre-fix, a build failure produced
    # no diagnostic and the downstream `cp` step silently dropped the
    # missing artifact — exactly the trap that froze cycc_aarch64 from
    # v5.8.46 → v5.8.52. Now: capture stderr to a tempfile, surface
    # warnings/notes (cycc emits a "note: N unreachable fns" diagnostic
    # that's normal), and warn loudly if the build itself fails.
    _build_tool() {
        local target="$1"
        local source="$2"
        local err_log
        err_log=$(mktemp)
        if cat "$source" | ./build/cycc > "./build/$target" 2>"$err_log"; then
            chmod +x "./build/$target"
            if [ -s "$err_log" ]; then sed 's/^/    /' "$err_log" >&2; fi
            rm -f "$err_log"
        else
            warn "failed to build $target from $source:"
            sed 's/^/    /' "$err_log" >&2
            rm -f "$err_log"
            rm -f "./build/$target"
        fi
    }

    _BINS=$(_parse_release_array bins)
    _CROSS_BINS=$(_parse_release_array cross_bins)
    for tool in $_BINS; do
        if [ "$tool" = "cycc" ] || [ "$tool" = "cyrius" ]; then continue; fi
        if [ -f "programs/${tool}.cyr" ]; then
            _build_tool "$tool" "programs/${tool}.cyr"
        fi
    done
    # cyrius build tool (lives in cbt/cyrius.cyr, not programs/)
    if [ -f cbt/cyrius.cyr ]; then
        _build_tool "cyrius" "cbt/cyrius.cyr"
    fi

    # Cross-compiler(s)
    if [ -f src/main_aarch64.cyr ]; then
        _build_tool "cycc_aarch64" "src/main_aarch64.cyr"
    fi
    # v6.0.50: PE compiler — build cycc_win from src/main_win.cyr with
    # CYRIUS_TARGET_WIN=1 (the x86 cycc emits a PE32+ cycc). Unfreezes it
    # from the frozen cc5_win 5.11.69 binary the copy-step shipped forward
    # (which couldn't resolve the 6.0.x stdlib WIN closure). _build_tool
    # can't set the env, so inline the build.
    if [ -f src/main_win.cyr ] && [ -x build/cycc ]; then
        info "building cycc_win from src/main_win.cyr (CYRIUS_TARGET_WIN=1 → PE32+)"
        if cat src/main_win.cyr | CYRIUS_TARGET_WIN=1 ./build/cycc > build/cycc_win 2>/dev/null; then
            chmod +x build/cycc_win
        else
            warn "cycc_win build failed — falling back to existing build/cycc_win if present"
        fi
    fi

    # Copy binaries
    for bin in $_BINS $_CROSS_BINS; do
        if [ -x "./build/$bin" ]; then
            cp "./build/$bin" "$CYRIUS_HOME/versions/$VERSION/bin/"
        fi
    done
    cp bootstrap/asm "$CYRIUS_HOME/versions/$VERSION/bin/"

    # Scripts from [release].scripts (includes cyriusly + cyrius-*.sh)
    # v5.11.69: shim scripts (cyrius-init/port/repl) live in
    # scripts/shims/ — look there first, fall through to flat scripts/.
    _SCRIPTS=$(_parse_release_array scripts)
    for script in $_SCRIPTS; do
        if [ -f "scripts/shims/$script" ]; then
            cp "scripts/shims/$script" "$CYRIUS_HOME/versions/$VERSION/bin/"
            chmod +x "$CYRIUS_HOME/versions/$VERSION/bin/$script"
        elif [ -f "scripts/$script" ]; then
            cp "scripts/$script" "$CYRIUS_HOME/versions/$VERSION/bin/"
            chmod +x "$CYRIUS_HOME/versions/$VERSION/bin/$script"
        fi
    done

    # Shared audit helpers (sourced by the cyrius dispatcher)
    if [ -d scripts/lib ]; then
        mkdir -p "$CYRIUS_HOME/versions/$VERSION/bin/lib"
        cp scripts/lib/*.sh "$CYRIUS_HOME/versions/$VERSION/bin/lib/" 2>/dev/null || true
    fi

    # Copy stdlib
    if [ -d lib ]; then
        cp -r lib "$CYRIUS_HOME/versions/$VERSION/"
    fi

    cd /
    rm -f /tmp/cc5_verify /tmp/cc5_verify2
    info "bootstrapped from source"
fi

rm -rf "$TMPDIR"

# ── Set active version ──

echo "$VERSION" > "$CYRIUS_HOME/current"
# Copy VERSION file so cyrius can read it from install directory
echo "$VERSION" > "$CYRIUS_HOME/versions/$VERSION/VERSION"

# ── Create symlinks (directory-level, version-agnostic) ──

info "linking directories..."
rm -rf "$CYRIUS_HOME/bin" "$CYRIUS_HOME/lib"
ln -sf "$CYRIUS_HOME/versions/$VERSION/bin" "$CYRIUS_HOME/bin"
ln -sf "$CYRIUS_HOME/versions/$VERSION/lib" "$CYRIUS_HOME/lib"

# ── Install version manager ──
# cyriusly lives in scripts/cyriusly (committed source of truth). The
# release tarball ships it under bin/, so the tarball path already has
# it. The source-bootstrap path also copies it from scripts/. This
# block is a safety net for stale tarballs (pre-5.4.12) that didn't
# include cyriusly — fetch it from the matching tag.
if [ ! -x "$CYRIUS_HOME/bin/cyriusly" ]; then
    if curl -sSfL "https://raw.githubusercontent.com/${REPO}/${VERSION}/scripts/cyriusly" \
        -o "$CYRIUS_HOME/bin/cyriusly" 2>/dev/null; then
        chmod +x "$CYRIUS_HOME/bin/cyriusly"
        info "version manager installed"
    else
        warn "cyriusly not found in tarball and fetch failed — run 'cyrius pulsar' from a repo to install it"
    fi
fi

# ── Build dlopen-helper (v5.5.28) ──
# lib/fdlopen.cyr (foreign-dlopen pattern for static-binary access to
# full glibc state) invokes a tiny C helper built against the host
# libc. Compile at install time; cache version-agnostically at
# $CYRIUS_HOME/dlopen-helper (helper is tied to host libc, not to
# the cyrius version). If cc is missing we silently skip — fdlopen
# is opt-in and consumers get a clear FDL_ERR_HELPER_MISSING code.
_DLOPEN_HELPER_SRC=""
if [ -f "programs/dlopen-helper.c" ]; then
    _DLOPEN_HELPER_SRC="programs/dlopen-helper.c"
elif [ -f "$CYRIUS_HOME/versions/$VERSION/bin/dlopen-helper.c" ]; then
    _DLOPEN_HELPER_SRC="$CYRIUS_HOME/versions/$VERSION/bin/dlopen-helper.c"
fi
if [ -n "$_DLOPEN_HELPER_SRC" ]; then
    if command -v cc > /dev/null 2>&1; then
        _CC=cc
    elif command -v gcc > /dev/null 2>&1; then
        _CC=gcc
    else
        _CC=""
    fi
    if [ -n "$_CC" ]; then
        if "$_CC" -O2 -fPIE -pie -o "$CYRIUS_HOME/dlopen-helper" \
            "$_DLOPEN_HELPER_SRC" -ldl 2>/dev/null; then
            info "dlopen-helper compiled (v5.5.28 foreign-dlopen)"
        else
            warn "dlopen-helper compile failed — fdlopen will report FDL_ERR_HELPER_MISSING"
        fi
    else
        warn "no C compiler found — fdlopen unavailable (install cc or gcc)"
    fi
    # Stash the source so the refresh-only path can rebuild after
    # a host libc upgrade without needing the original checkout.
    mkdir -p "$CYRIUS_HOME/versions/$VERSION/bin"
    cp "$_DLOPEN_HELPER_SRC" "$CYRIUS_HOME/versions/$VERSION/bin/dlopen-helper.c"
fi

# ── Setup PATH ──

add_to_path() {
    local profile="$1"
    if [ -f "$profile" ]; then
        if ! grep -q "\.cyrius/bin" "$profile" 2>/dev/null; then
            printf '\n# Cyrius\nexport PATH="$HOME/.cyrius/bin:$PATH"\n' >> "$profile"
            return 0
        fi
    fi
    return 1
}

path_added=0
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
    if [ -f "$rc" ]; then
        add_to_path "$rc" && path_added=1 && info "PATH added to $(basename $rc)"
    fi
done
if [ "$path_added" -eq 0 ]; then
    add_to_path "$HOME/.profile" && info "PATH added to .profile" || true
fi

# ── Starship prompt integration ──

STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
if [ -f "$STARSHIP_CONFIG" ] && command -v starship > /dev/null 2>&1; then
    if ! grep -q "custom.cyrius" "$STARSHIP_CONFIG" 2>/dev/null; then
        cat >> "$STARSHIP_CONFIG" << 'STARSHIP'

[custom.cyrius]
command = """if [ -f bootstrap/asm ]; then cat VERSION 2>/dev/null; else cycc --version 2>/dev/null | awk '{print $2}' || cat ~/.cyrius/current 2>/dev/null || echo '?'; fi"""
when = "test -f cyrius.cyml || test -f cyrius.toml"
symbol = "𝕮"
style = "bg:teal"
format = '[[ $symbol( $output) ](fg:base bg:teal)]($style)'
detect_files = ["cyrius.cyml", "cyrius.toml"]
STARSHIP
        info "Starship prompt configured (shows toolchain version in Cyrius projects)"
    fi
elif command -v starship > /dev/null 2>&1; then
    # Starship installed but no config — create minimal config with cyrius section
    mkdir -p "$(dirname "$STARSHIP_CONFIG")"
    cat > "$STARSHIP_CONFIG" << 'STARSHIP'
[custom.cyrius]
command = """if [ -f bootstrap/asm ]; then cat VERSION 2>/dev/null; else cycc --version 2>/dev/null | awk '{print $2}' || cat ~/.cyrius/current 2>/dev/null || echo '?'; fi"""
when = "test -f cyrius.cyml || test -f cyrius.toml"
symbol = "𝕮"
style = "bg:teal"
format = '[[ $symbol( $output) ](fg:base bg:teal)]($style)'
detect_files = ["cyrius.cyml", "cyrius.toml"]
STARSHIP
    info "Starship config created with Cyrius prompt"
fi

# ── Summary ──

printf "\n${BOLD}Cyrius ${VERSION} installed successfully!${RESET}\n\n"

# Show what was installed — bin list from [release] (single source of truth).
echo "  Toolchain:"
_SUMMARY_BINS=$(_parse_release_array bins)
for bin in $_SUMMARY_BINS; do
    if [ -x "$CYRIUS_HOME/bin/$bin" ]; then
        printf "    ${GREEN}+${RESET} %s\n" "$bin"
    fi
done
_SUMMARY_CROSS=$(_parse_release_array cross_bins)
for bin in $_SUMMARY_CROSS; do
    if [ -x "$CYRIUS_HOME/bin/$bin" ]; then
        printf "    ${GREEN}+${RESET} %s (cross-compiler)\n" "$bin"
    fi
done
echo ""
echo "  To get started:"
echo "    ${DIM}# restart your shell, or:${RESET}"
echo "    export PATH=\"\$HOME/.cyrius/bin:\$PATH\""
echo ""
echo "    ${DIM}# create a new project:${RESET}"
echo "    cyrius init myproject"
echo "    cd myproject"
echo "    cyrius build src/main.cyr -o build/main"
echo ""
echo "    ${DIM}# manage versions:${RESET}"
echo "    cyriusly list"
echo "    cyriusly update"
echo ""
