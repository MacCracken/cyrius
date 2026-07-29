#!/bin/sh
# scripts/check.sh — thin shim around programs/checks/main.cyr.
#
# v5.9.1 (2026-05-06) — first slot of the v5.9.x sovereignty pass
# (bash-toolchain → cyrius). The dispatcher logic that used to live
# here (~743 LOC of bash) moved into cyrius. At v6.0.90 the monolithic
# programs/check.cyr (10.2K LoC) was split into programs/checks/
# (slim dispatcher main.cyr + per-suite files). This shim:
#   1. cd's to the repo root so child gates see the expected CWD,
#   2. builds build/cyrius_check on demand (mirrors the v5.8.44
#      auto-build pattern for build/cyrius_api_surface),
#   3. exec's the binary, propagating its exit code.
#
# scripts/lib/audit-walk.sh stays bash for the v5.9.x window — it
# is still consumed by the bash scripts/cyrius dispatcher, queued
# for cyrius conversion at v5.9.5 alongside that dispatcher. The
# fmt/lint walk logic was simultaneously ported into
# lib/audit_walk.cyr (cyrius stdlib module) for the check program's
# use; once scripts/cyrius converts, both audit-walk.sh and this
# bridge can retire together.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECK_BIN="$ROOT/build/cyrius_check"
# v6.0.90: programs/check.cyr split into programs/checks/ (slim dispatcher
# main.cyr + per-suite files). CHECK_SRC is the dispatcher; the rebuild
# trigger watches EVERY suite file (a single-file -nt test would miss a
# stale binary after a suite edit — masking a regression).
CHECK_SRC="$ROOT/programs/checks/main.cyr"
CC="$ROOT/build/cycc"

NEWEST_SRC="$(ls -t "$ROOT"/programs/checks/*.cyr 2>/dev/null | head -1)"
# Rebuild if: no binary, the glob matched nothing (force a rebuild so the
# build fails loudly rather than running a stale binary), or any suite file
# is newer than the binary.
if [ ! -x "$CHECK_BIN" ] || [ -z "$NEWEST_SRC" ] || [ "$NEWEST_SRC" -nt "$CHECK_BIN" ]; then
    if [ ! -x "$CC" ]; then
        printf "error: build/cycc missing — run 'sh bootstrap/bootstrap.sh' first.\n" >&2
        exit 1
    fi
    cat "$CHECK_SRC" | "$CC" > "$CHECK_BIN" 2>/dev/null
    chmod +x "$CHECK_BIN"
fi

# Run the cyrius gate suite. On a targeted run (a suite name was passed),
# exec it directly — the bare-metal boot gate is a full-run-only capstone.
if [ $# -gt 0 ]; then
    exec "$CHECK_BIN" "$@"
fi
"$CHECK_BIN"

# v6.2.28 D7: the bare-metal kernel BOOT gate — a real QEMU execution of the
# kernel built via the formalized triple. This anti-rots the v6.2.27 kernel
# codegen the way the macho port never was (a green checkmark is not
# verification; the kernel actually running IS). Visibly skips when qemu is
# absent rather than masquerading as green.
sh "$ROOT/scripts/qemu-boot-gate.sh"

# v6.4.47 (arc #3): UEFI Authenticode signing end-to-end gate — `cyrius sign-efi`
# signs a synthetic PE and an independent oracle (openssl + from-scratch PE-hash)
# confirms the signature is one a real UEFI firmware would accept. Skips if openssl
# is absent. The sign path is lib/CLI-only (cycc byte-identical), so this is the
# behavioral gate for the signer.
sh "$ROOT/scripts/sign-efi-gate.sh"

# v6.4.81: value-form SIMD must exist on every EMIT path, not just the native
# forks. main.cyr's PE/Mach-O CROSS arms were missing CYRIUS_HAS_VAL_SIMD_PARAMS
# since v6.4.31, so the same source built differently depending on WHERE it was
# built. Host-side by necessity: a tcyr runs natively on each host and therefore
# exercises main_win.cyr (always correct), never the cross path.
sh "$ROOT/tests/valform_simd_crosstarget.sh"

# v6.5.0 Phase 1 (public/private visibility): every fn must be attributed to the
# source file its `fn` keyword is in. Phase 2 turns that partition into a visibility
# boundary, so a wrong stamp means `private` silently mis-scopes. Gated here at
# Phase 1 — while the table is still recorded-not-enforced — so the substrate is
# never write-only and never unverified.
sh "$ROOT/tests/fileid_substrate.sh"

# v6.5.0 Phase 2: file-scoped `private` / per-item `public`, WARN mode. Asserts
# per-RESOLUTION-PATH (ordinary / tail / operator), because enforcement that covers
# only the obvious path is the v6.4.81 `_cfo` shape repeating — that class was
# declared fixed three times before the fourth occurrence turned up in a path nobody
# had enumerated.
sh "$ROOT/tests/visibility_private.sh"

# v6.5.1: overload-suffix dispatch must be ARITY-AWARE and POSITION-CONSISTENT.
# Asserts across assign / return-tail / nested-arg because the two defects it covers
# were *position-specific* — the redirect ignored the target's arity on the assign and
# nested paths, and PARSE_RETURN's tail path skipped the dispatch entirely, so the same
# call spelled two ways ran two different functions. The 253-file corpus changes 0 bytes
# under the arity fix, i.e. it had ZERO coverage of the shape, which is why this must be
# a gate and not a .tcyr.
sh "$ROOT/tests/overload_arity_dispatch.sh"

# v6.5.1: the agnos O_RDWR flag-map gate (v6.4.27) was CI-ONLY — `ci.yml` ran it and
# nothing local did, so `release-gate.sh` could report GREEN while CI went RED. It did
# exactly that this release: the arity escalation above turned the gate's `sys_unlink(path)`
# into a hard error (agnos's wrapper is length-carrying and takes 2 args), and the local
# gate never noticed. A gate CI runs but the release gate does not is the same blind spot
# as grading check.sh by its stdout instead of its exit status — fixed the same way, by
# making the local gate actually run it. `tests/heapmap.sh` is the only other CI-only
# script and it is genuinely redundant: `_heapmap_gate()` in the check binary covers it.
sh "$ROOT/tests/io_rdwr_agnos.sh"

# v6.5.2: every folded stdlib that builds for Linux must also build for agnos.
# `lib/yukti.cyr` shipped SIX agnos ABI errors for months — including `sys_mount` called
# with 5 args against agnos's 0-parameter no-op stub, so yukti returned Ok() for a mount
# that never happened — because NO gate had ever compiled a folded stdlib for a non-Linux
# target. Parity (Linux-OK-but-agnos-broken) rather than "must build", since the distlib
# bundles deliberately do not carry their own stdlib deps. Reports its own coverage: 11/12
# today, niyama skipped and named.
sh "$ROOT/tests/folds_agnos_parity.sh"
