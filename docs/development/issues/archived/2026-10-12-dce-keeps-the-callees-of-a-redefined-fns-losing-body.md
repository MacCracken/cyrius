# `CYRIUS_DCE=1` keeps the callees of a redefined function's losing body alive — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-6, `59b776f73`, with IN-6r `0142d3d54`, IN-6r2 `22ab30c80` and IN-7 `cce411c28` (no decision needed: 6.6.20's last-definition-wins rule, applied to reachability): `_fn_redirect` records each losing body's `[old, old_end)`, and both seed passes (x86 and aarch64 FIXUP) take a call inside one as no root; the redirect jump stays a root, so the winner is live; under `CYRIUS_IR=3` the seam's compaction moves the recorded ranges with the code (IN-6r — the lane's first version left them stale there, a regression that never shipped). The filed `a.cyr` (built as its manifest's `stdlib = ["syscalls"]` does) reports `dead: only_in_loser` once — as `b.cyr` does — where it reported it 0 times, and exits 1 (the winner ran), on x86 W^X, `CYRIUS_WX=0`, aarch64 and `CYRIUS_IR=3`; a program with no redefinition is byte-identical. chakshu's `shu-ai` was not rebuilt here (a consumer's tree). Found at the triage and fixed in its own commit (IN-7): `EFNREDIRECT`'s registry scan reads `_wpjs_base`, so a `#naked` redefinition past 49,152 jump sources, which died SIGILL under `CYRIUS_DCE=1`, exits 1. Rows: `dce_eliminates.sh` axis 8 (`a.cyr` / `b.cyr` verbatim on x86 W^X, `CYRIUS_WX=0`, aarch64 and `CYRIUS_IR=3`; 8b `fn_redefinition_last_wins.tcyr` under `CYRIUS_IR=3 CYRIUS_DCE=1` and a top-level call after a loser) and axis 9 (the naked shape past 49,152 sources); mutations: `_dce_in_loser` answering 0 RED, the `_wp_fnr_shift` call dropped RED, the scan back on `S + 0x60000` RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (the run below). Found by chakshu's 0.11.0 release: its four libssl refusals in `src/nolibc.cyr` redefine `lib/fdlopen.cyr`'s loaders (since 6.6.9 `lib/tls.cyr` includes `fdlopen.cyr` itself), and the loader code those losing bodies call stays in the DCE'd `shu-ai` binary.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-12, chakshu 0.11.0's `nolibc-check.sh` work.
**Severity:** Low — dead bytes, not wrong behaviour: every call binds to the last definition (6.6.20), and the losing body is never run. But DCE is how a consumer proves the shipped binary carries no libc-loader code. Here it keeps code no call can reach.
**Affects:** 6.7.9 (verified). Earlier releases were not checked.

## Summary

When a function is defined twice, the last definition wins (`duplicate fn 'f' (last definition wins …)`). The
losing body is unreachable, so everything only it calls is dead too. DCE does not treat it that way: a function
called only from the losing body is not reported dead, and its code stays in the binary.

## Reproduction

```sh
cat > a.cyr <<'EOF'
fn only_in_loser() { return 42; }
fn f() { return only_in_loser(); }
fn f() { return 1; }
var r = f();
syscall(SYS_EXIT, r);
EOF
cat > b.cyr <<'EOF'
fn only_in_loser() { return 42; }
fn g() { return 1; }
var r = g();
syscall(SYS_EXIT, r);
EOF
CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 cyrius build a.cyr build/a 2>&1 | grep -c 'dead: only_in_loser'   # 0
CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 cyrius build b.cyr build/b 2>&1 | grep -c 'dead: only_in_loser'   # 1
./build/a; echo $?                                                                                  # 1 — the winner ran
```

(Manifest: `cyrius = "6.7.9"`, `[deps] stdlib = ["syscalls"]`.)

Expected: `only_in_loser` is dead in both builds.

## Root cause (speculation)

The reachability walk seems to start from, or keep edges out of, every definition of a reachable name, rather than
only the definition the name binds to.

## Proposed fix

Treat a shadowed (losing) definition as unreachable and walk only the winning body's call edges.

## Consumer-side workaround

None that keeps the redefinition. chakshu documents the dead bytes, and its `nolibc-check.sh` checks the lean binary
(which has no `tls.cyr`) for loader strings instead of the AI binary.
