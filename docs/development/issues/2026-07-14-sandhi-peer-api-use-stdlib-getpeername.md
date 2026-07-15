# sandhi: switch the peer API off raw `syscall(52)` onto the new `sys_getpeername` wrapper

**Status:** 🟡 **OPEN** — cross-repo ask (sandhi-side). **Filed:** 2026-07-14 at the v6.4.64 close.
**Severity:** **High until fixed** — sandhi 1.9.0's peer API **fabricates addresses on aarch64-Linux
and macOS-arm64**. **Consumer waiting:** `yeo-cy-test` (per-IP rate limiting on an Argon2id login).

## The problem, and whose it is

**This one is ours first.** cyrius had no `getpeername` wrapper, so sandhi 1.9.0 did the only thing
it could and hardcoded the x86_64-Linux number:

```cyrius
var _SANDHI_SYS_GETPEERNAME = 52;
var r = syscall(_SANDHI_SYS_GETPEERNAME, fd, out16, &alen);
```

Correct on x86_64-Linux (52 *is* getpeername). But cyrius's stdlib uses **per-arch** syscall numbers,
and an untranslated number does not error — it invokes a different syscall. On aarch64, **52 is
`fchmod(fd, mode)`**, and it **SUCCEEDS** (verified on real pi): `sandhi_server_peer_sockaddr` returns
1 ("got it") with `out16` **never written**, so `sandhi_server_peer_ip` hands back uninitialized
stack. A rate limiter keyed on garbage is not a rate limiter — and it fails *quietly*.

sandhi's own comment says the number is *"translated by the Mach-O backends the same way net.cyr's
socket band is."* It wasn't — getpeername was missing from every translation table. cyrius closed
that in v6.4.64.

## What cyrius now provides (v6.4.64)

Real per-arch wrappers, in `lib/syscalls_linux_common.cyr` (resolved via `lib/syscalls.cyr`):

```cyrius
fn sys_getpeername(fd, addr, addrlen): i64   # 0 / -errno; -ENOTCONN on an unconnected socket
fn sys_getsockname(fd, addr, addrlen): i64
```

Numbers per peer: x86-Linux 52/51 · aarch64-Linux **205/204** · macOS x86-numbered + EMACHO xlat →
BSD 31/32 · macOS-arm64 via the macho dual-map 205→31 / 204→32 · Windows **fail-closed `-ENOSYS`**
(no ws2_32 reroute yet — see `2026-07-14-windows-getpeername-reroute-missing.md`).

Gate: `tests/tcyr/vr01_getpeername_xlat.tcyr`, PASS on real pi + ecb + ach.

## The ask (sandhi 1.9.1)

1. Delete `_SANDHI_SYS_GETPEERNAME` and call **`sys_getpeername(fd, out16, &alen)`**. Nothing else
   changes — same args, same 0/-errno contract.
2. Keep the AGNOS `#ifdef` early-return (agnos has no BSD getpeername; the wrapper isn't defined
   there either).
3. Windows now returns `-ENOSYS` from the wrapper, which your `if (r < 0) { return 0; }` guard
   already turns into "unknown" — the documented contract holds unchanged.
4. **Defence-in-depth worth taking anyway:** `sandhi_server_peer_sockaddr` declares `var sa[16]` and
   the accessors read it after the call. Zero it first. The cyrius fix makes this moot on every
   supported target, but zeroing contains the *class* — a future unrouted target degrades to
   `0.0.0.0` instead of to stack contents.
5. Bump the cyrius pin to **6.4.64** (the wrapper does not exist before it) and re-vendor.

## Done when

sandhi 1.9.1 ships using the wrapper; cyrius re-vendors it; `sandhi_server_peer_ip` returns the real
client IP on x86-Linux, aarch64 (pi), Intel-Mac, and macOS-arm64, and `0` on Windows/agnos.

## Note for yeo-cy-test

Until 1.9.1 is vendored, **do not rely on `sandhi_server_peer_ip` for rate limiting on aarch64 or
Apple Silicon** — it returns garbage, not 0, so a `!= 0` check will not protect you. It is correct
today on x86_64-Linux and Intel-Mac, and returns 0 ("unknown") on Windows.
