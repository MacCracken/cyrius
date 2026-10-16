# `lib/ws.cyr` and `lib/ws_server.cyr` both declare the nine `WS_*` constants, so `cyrius distlib` refuses a bundle that uses one with neither leaf in its unit — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-1, `e114fa8f`: `lib/ws_server.cyr` includes `lib/ws.cyr` and no longer declares its own nine `WS_*` vars — the opcodes and states are ws.cyr's enum constants, one home per name (D11, the user 2026-10-15). The filed reproduction is rc 0 with `dist/orp.deps` = `ws` (it was rc 1, "more than one stdlib leaf could own it (ws, ws_server)"); yantra 1.0.11's distlib on this lib/ converges — rc 0, 12 leaves, `dist/yantra.cyr` byte-identical to `lib/yantra.cyr`; `distlib_owner_rule_shared.sh`'s ALLOW list is empty. With ws_server alone a write to or `&` of one of the nine stops compiling, and the include now brings ws.cyr's fns, `WS_CONNECTING` and `WS_RECV_MAX_PAYLOAD`. Rows: `distlib_owner_rule_shared.sh` row C (ALLOW empty) and row W (the repro verbatim, sidecar exactly `ws`), `tests/tcyr/stdlib/ws_server_constants_from_ws.tcyr` (14/14), `ws_and_ws_server_constants_agree.tcyr` (6/6). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-13 on the 6.7.11 tools lane (l6711-tools, after the distlib owner-rule
commit): `lib/ws.cyr` declares `WS_OP_CONTINUATION` / `WS_OP_TEXT` / `WS_OP_BINARY` / `WS_OP_CLOSE` / `WS_OP_PING` /
`WS_OP_PONG` (enum `WsOpcode`) and `WS_OPEN` / `WS_CLOSING` / `WS_CLOSED` (enum `WsState`); `lib/ws_server.cyr`
declares the same nine as top-level `var`s with the same values. Neither file includes the other and neither is a
peer of a dispatcher, so for `cyrius distlib`'s sidecar verify the two leaves TIE for every one of the nine names.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D11 — ws_server.cyr includes lib/ws.cyr and drops its nine copies.
**Discovered:** 2026-10-13, the 6.7.11 tools lane's census of every-target owner ties
(`tests/gates/toolchain/distlib_owner_rule_shared.sh` row C — the only ties in lib/; they are its ALLOW list).
**Severity:** Medium — the folded stdlib yantra's own `cyrius distlib` stops at its next release: measured on a
scratch `git archive` of yantra 1.0.11 (@737f539, `cyrius.lock` removed, the snapshot = this tree's lib/), the 6.7.10
CLI records `ws` for `WS_OPEN` and writes the sidecar; the 6.7.11 CLI refuses (rc 1, no sidecar).
**Affects:** cbt 6.7.11 (the owner rule that refuses a tie on every target, user decision 2026-10-13); the duplicate
declarations predate it (6.7.10 settled the tie by file name: `ws`, and 6.7.6 by directory order: `ws_server` — the
14th leaf yantra 1.0.10 dropped).

## Reproduction

```sh
# a hermetic CYRIUS_HOME whose snapshot is the tree's lib/, and a producer that reads WS_OPEN with nothing declared
mkdir -p h/versions/6.7.11 p/src && cp -R lib h/versions/6.7.11/lib
printf '[package]\nname = "orp"\nversion = "0.1.0"\ncyrius = "6.7.11"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' > p/cyrius.cyml
printf 'fn orp_a(): i64 { return WS_OPEN; }\n' > p/src/lib.cyr
cd p && CYRIUS_HOME=$PWD/../h CYRIUS_RESOLVED=1 cyrius distlib; echo rc=$?
```

6.7.11:

```
error: distlib: sidecar verify: 'WS_OPEN' is undefined on every target, and more than one stdlib leaf could own it (ws, ws_server) — include the right leaf from a bundled module. Sidecar NOT written
rc=1
```

6.7.10 (byte order): rc 0, `dist/orp.deps` = `ws`. yantra 1.0.11 (its sources include no `lib/` file; its bundle
reads `WS_OPEN`): 6.7.10 — `sidecar verify round 1: ws recorded for 'WS_OPEN' (every target)`, 12 leaves, rc 0;
6.7.11 — the refusal above, rc 1.

A program that includes both files compiles today (`include "lib/ws.cyr"` + `include "lib/ws_server.cyr"`, then
`return WS_OPEN;`: rc 0) — the values agree, so nothing miscomputes; the cost is the ambiguity.

## Root cause

ws_server.cyr ("Companion to lib/ws.cyr (client-side)") carries its own copy of the protocol constants instead of
taking them from ws.cyr. One home per name ends the tie: ws_server.cyr includes `lib/ws.cyr` and drops its copies, or
the shared constants move to one leaf both include. Either changes what `include "lib/ws_server.cyr"` brings into a
program (ws.cyr's fns and its two enums), so it is not a drive-by fix. Until then a producer that uses a `WS_*` name
must `include "lib/ws.cyr"` (or `lib/ws_server.cyr`) from a bundled module so the verify sees the leaf in its unit.

## Acceptance

- `WS_*` has one declaring leaf in lib/ (or the two are dispatcher peers); the reproduction records it, rc 0.
- `distlib_owner_rule_shared.sh`'s ALLOW list is empty (its row C then fails until the entries are removed).
- yantra's distlib at its next release converges (an `include "lib/ws.cyr"` in yantra's own module also does that, on
  yantra's side).
