#!/bin/sh
# scripts/check.sh — thin shim around programs/check.cyr.
#
# v5.9.1 (2026-05-06) — first slot of the v5.9.x sovereignty pass
# (bash-toolchain → cyrius). The dispatcher logic that used to live
# here (~743 LOC of bash) moved into programs/check.cyr (~700 LOC
# of cyrius). This shim:
#   1. cd's to the repo root so child gates see the expected CWD,
#   2. builds build/cyrius_check on demand (mirrors the v5.8.44
#      auto-build pattern for build/cyrius_api_surface),
#   3. exec's the binary, propagating its exit code.
#
# scripts/lib/audit-walk.sh stays bash for the v5.9.x window — it
# is still consumed by the bash scripts/cyrius dispatcher, queued
# for cyrius conversion at v5.9.5 alongside that dispatcher. The
# fmt/lint walk logic was simultaneously ported into
# lib/audit_walk.cyr (cyrius stdlib module) for programs/check.cyr's
# use; once scripts/cyrius converts, both audit-walk.sh and this
# bridge can retire together.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECK_BIN="$ROOT/build/cyrius_check"
CHECK_SRC="$ROOT/programs/check.cyr"
CC="$ROOT/build/cycc"

if [ ! -x "$CHECK_BIN" ] || [ "$CHECK_SRC" -nt "$CHECK_BIN" ]; then
    if [ ! -x "$CC" ]; then
        printf "error: build/cycc missing — run 'sh bootstrap/bootstrap.sh' first.\n" >&2
        exit 1
    fi
    cat "$CHECK_SRC" | "$CC" > "$CHECK_BIN" 2>/dev/null
    chmod +x "$CHECK_BIN"
fi

exec "$CHECK_BIN" "$@"
