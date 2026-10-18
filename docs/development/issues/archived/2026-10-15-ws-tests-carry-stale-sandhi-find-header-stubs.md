# Five ws tests still define a `sandhi_server_find_header` (and one a `base64_encode`) stand-in that `lib/ws_server.cyr`'s own includes made a duplicate — every compile warns, and in one the stub binds last — RESOLVED

> ✅ **RESOLVED in v6.7.14** (LIB-3, `a6e1779bd`. No decision was needed; the change is tests only. The `sandhi_server_find_header` / `base64_encode` stand-ins and their stale comments are deleted from all five files. Each compiles with 0 `duplicate fn` warnings on the x86_64, aarch64, PE, x86 Mach-O and arm64 Mach-O builds (1 / 1 / 1 / 2 / 1 before). `sock_send_all_short_write.tcyr`'s handshake group now runs sandhi's real `sandhi_server_find_header`. `ws_server_handshake.tcyr`'s header is rewritten: a stale `http_find_header` call is still a reachable-undefined hard error. Pass counts are unchanged on x86_64, qemu-aarch64, pi, ecb and ach (4 / 7 / 14 / 17 / 21), and on wine and cass (4 / 3 / 14 / 7 / 2, the POSIX groups fenced). Row: `tests/gates/toolchain/ws_tests_no_duplicate_fn.sh` (no warning, no stand-in definition, a staged stub still warns, all five present). Mutations: each 6.7.13 file restored → RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib @ c667293d), x86_64 Linux.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — test hygiene, no lib/ defect. Every listed test passes. But each compile prints a duplicate-fn
warning that a real one can scroll past, and the tests' own comments describe a mechanism that no longer holds.
**Discovered:** 2026-10-15, the 6.7.12 stdlib lane (unit L1), while checking that `lib/ws_server.cyr`'s new
`include "lib/ws.cyr"` (D11) added no warning to the ws tests: these warnings are the same before and after that change.

## Reproduction

From the repo root:

```
$ cat tests/tcyr/formats/ws_server_handshake.tcyr | ./build/cycc > /dev/null
warning:lib/sandhi.cyr:13284:1: duplicate fn 'sandhi_server_find_header' (last definition wins; first defined in <source>)
$ cat tests/tcyr/stdlib/ws_server_recv_frame_exact.tcyr | ./build/cycc > /dev/null
warning:lib/sandhi.cyr:13284:1: duplicate fn 'sandhi_server_find_header' (last definition wins; first defined in <source>)
$ cat tests/tcyr/crossos/ws_server_socket_reads.tcyr | ./build/cycc > /dev/null
warning:lib/sandhi.cyr:13284:1: duplicate fn 'sandhi_server_find_header' (last definition wins; first defined in <source>)
$ cat tests/tcyr/crossos/net_plain_write_peer_reset.tcyr | ./build/cycc > /dev/null
warning:lib/bayan.cyr:17040:1: duplicate fn 'base64_encode' (last definition wins; first defined in <source>)
warning:lib/sandhi.cyr:13284:1: duplicate fn 'sandhi_server_find_header' (last definition wins; first defined in <source>)
$ cat tests/tcyr/crossos/sock_send_all_short_write.tcyr | ./build/cycc > /dev/null
warning:<source>:37:1: duplicate fn 'sandhi_server_find_header' (last definition wins; first defined in lib/sandhi.cyr)
```

## Root cause

Since 6.6.19 R2 `lib/ws_server.cyr` includes `lib/sandhi.cyr` (and `lib/bayan.cyr`) itself. Before that the tests
supplied their own `sandhi_server_find_header` so ws_server's handshake had a definition without sandhi's TLS stack.
The stand-ins stayed:

- four files define the stub BEFORE `include "lib/ws_server.cyr"`, so sandhi's real fn (defined later) wins and the
  stub is dead code. `ws_server_handshake.tcyr`'s header still says the local definition is what "locks" the rename
  (a stale `http_find_header` call would find no definition) — sandhi's real fn now satisfies the call either way.
- `sock_send_all_short_write.tcyr` defines it AFTER the include, so its stub binds last and ws_server's handshake in
  that test runs the stand-in, not sandhi's.
- `net_plain_write_peer_reset.tcyr` also defines `base64_encode` ahead of bayan's.

## Fix

Delete the stand-ins (and the stale comments), so each test runs the real sandhi / bayan fns its includes already
bring, and check that each file compiles warning-free and still passes on its targets (the crossos three on
ecb / ach / cass / pi). Changing which definition `sock_send_all_short_write.tcyr`'s handshake runs is the one
behaviour change: confirm its handshake group still passes on the real `sandhi_server_find_header`.
