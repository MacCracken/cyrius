# Windows: no `getpeername`/`getsockname` reroute — peer address unavailable on PE

**Status:** 🟡 **OPEN** — capability gap, safe degradation. **Filed:** 2026-07-14 at the v6.4.64 close.
**Severity:** Low-Medium (no wrong answers; a real feature is simply unavailable on one target).

## The gap

v6.4.64 fixed `getpeername`(52)/`getsockname`(51) reaching the *wrong syscall* on aarch64-Linux and
Darwin (they were missing from the ESYSXLAT / EMACHO_SYSXLAT tables — see
`archived/…` and the CHANGELOG). **Windows was never broken in that dangerous way** and is
therefore not part of that fix: `src/backend/x86/emit.cyr` (the PE syscall router) emits
`-38 (-ENOSYS)` for any number it cannot route and **never** emits a raw `0F 05`, plus a
compile-time warning. So on PE:

- `sandhi_server_peer_sockaddr(fd, out16)` gets `-38` → returns `0`
- `sandhi_server_peer_ip/port` → `0` = "unknown"

which **honors sandhi's documented contract** (*"0 means unknown; callers must fail open or fall
back, never treat it as a real peer"*). Nothing is corrupted. But the capability is absent.

## Why it matters

sandhi 1.9.0's peer API exists for **per-IP rate limiting** — filed by `yeo-cy-test`, whose
`/api/login` runs Argon2id at ~244 ms CPU/attempt (a request-amplification lever). A Windows
deployment of that server gets `0` for every peer, so it cannot build the rate-limit key at all:
either every request collapses onto one bucket, or the limiter has to fail open. The security
control the API was added for is unavailable on PE — quietly, since "unknown" is a legal answer.

## Fix

Add ws2_32 reroutes, mirroring the existing socket band (`0xF01E` WSAStartup, `0xF01F-0xF021` IOCP,
`0xF033` listen, …):

- `getpeername(s, name, namelen)` → ws2_32!getpeername
- `getsockname(s, name, namelen)` → ws2_32!getsockname

Both are 3-arg and map 1:1 onto the Winsock signatures; the sockaddr_in layout already matches what
`sandhi_server_peer_ip` parses (family@0, port@2 BE, addr@4). Note the fd→SOCKET handle mapping the
PE net path already performs (`_pe_fd_to_handle_rcx`, `emit.cyr`) applies here too.

## Acceptance criteria

- `tests/tcyr/vr01_getpeername_xlat.tcyr` — drop its `#ifndef CYRIUS_TARGET_WIN` guard; the
  Windows arm should then assert `WSAENOTCONN (10057)` on an unconnected socket (Winsock does not
  use the POSIX errno space — the test's Linux 107 / Darwin 57 split needs a third arm).
- Green on real **cass** via the release gate's `vr01_` glob.
- cycc self-host + **seed-derive** (this is a `src/` change; `x86/emit.cyr` is in 6 of 7 forks'
  closure, and adding call refs to that function is the documented cybs silent-failure class).

## Notes

- Do **not** "fix" this in `lib/sandhi.cyr` — fix the router. The vendored fold evaporates at the
  next re-vendor, and the syscall tables are cyrius's, not sandhi's. (Cf.
  `feedback_dont_encode_codegen_bugs_as_language_rules` — this whole family surfaced from treating a
  compiler-side gap as the consumer's problem.)
- Related upstream hardening for sandhi (**not** cyrius's to make): `sandhi_server_peer_sockaddr`
  declares `var sa[16]` and reads it after a failed call on some paths — zeroing it upstream would
  contain the class rather than rely on every target routing correctly.
