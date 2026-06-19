# tls_native_set_ca_system uses the Linux sys_open ABI — fails on agnos

> **RESOLVED (landed, targeting v6.2.23).** `tls_native_set_ca_system`
> (`lib/tls_native_hs12.cyr`) now opens the four CA-bundle candidate paths via
> io.cyr's per-target `file_open` bridge instead of raw `sys_open(path, 0, 0)`.
> On agnos `file_open` computes `strlen(path)` + maps `O_*→AO_*`; on Linux/macOS
> it passes `(path, O_RDONLY, mode)` straight through (byte-identical to the old
> behavior — cycc x86 self-host unchanged). The `_tls_native_alloc` ignored-return
> was deliberately NOT changed: the hook (`tls_connect_with_ctx_hook`) fires
> *after* set_ca_system, so whirl's verify-none-via-hook path depends on alloc
> surviving a CA-load failure; hard-failing would regress it. The ABI fix makes
> the load succeed on agnos, removing the confusing-failure scenario. Verified:
> agnos cross-build gate (tls_native compiles), check.sh 89/89, cross-OS pi/ecb/cass.

**Filed:** 2026-06-18
**Component:** `lib/tls_native_hs12.cyr` — `tls_native_set_ca_system`
**Severity:** breaks **all** verifying HTTPS clients on `CYRIUS_TARGET_AGNOS`
**Reported by:** whirl 0.6.1 agnos bring-up (iron-equivalent QEMU+KVM test)

## Symptom

On `CYRIUS_TARGET_AGNOS`, a verifying TLS client (the default `tls_connect`
path) fails the handshake with no roots loaded. `tls_native_set_ca_system`
returns **`TLS_ERR_IO` (-12)** even when the CA bundle is present and readable
on the agnos-fs.

Observed end-to-end in QEMU (agnos kernel + virtio-net + SLIRP, `/etc/ssl/cert.pem`
staged on the ext2 root, 185 KB / ~150 certs):

```
DIAG ca_system rc=-12          # tls_native_set_ca_system
DIAG handshake_noverify rc=0   # a TLS_VERIFY_NONE handshake completes fine
```

The verify-none handshake **succeeding** proves the transport + handshake state
machine are correct on agnos (this client wires `tls_native_set_transport` over a
sovereign socket). The only fault is the trust-root load.

## Root cause

`tls_native_set_ca_system` (lib/tls_native_hs12.cyr:1591) opens the bundle with:

```cyrius
var fd = sys_open("/etc/ssl/cert.pem", 0, 0);   # macOS, Arch
if (fd < 0) { fd = sys_open("/etc/ssl/certs/ca-certificates.crt", 0, 0); }
... (3 more, all the same shape) ...
```

This is the **Linux** `sys_open(path, flags, mode)` signature — the `0` in the
second slot is `O_RDONLY`. But on agnos, `sys_open` is
**`(name, namelen, flags)`** (lib/syscalls_x86_64_agnos.cyr:246 —
`fn sys_open(name, namelen, flags): i64`). So the `0` is read as **namelen=0** →
the kernel opens a zero-length filename → `fd < 0` for every candidate path →
the function returns `TLS_ERR_IO`.

`_tls_native_alloc` (lib/tls.cyr:296) calls `tls_native_set_ca_system` and
**ignores its return**, so the ctx is built with zero roots; the fail-closed
`tls_native_connect` then rejects the chain — surfacing to the app as a generic
connection failure.

## Fix

Branch the open ABI by target inside `tls_native_set_ca_system` (each `sys_open`
needs the byte length of its path on agnos), e.g.:

```cyrius
#ifdef CYRIUS_TARGET_AGNOS
    # agnos sys_open(name, namelen, flags) — explicit length, flags last.
    var fd = sys_open("/etc/ssl/cert.pem", 17, 0);
    # (... the other candidate paths likely absent on agnos; the first is the
    #  conventional stage path. A small helper that strlen()s each is cleaner.)
#endif
#ifndef CYRIUS_TARGET_AGNOS
    var fd = sys_open("/etc/ssl/cert.pem", 0, 0);   # Linux/macOS (path, flags, mode)
    ...
#endif
```

Same ABI mismatch affects any other `sys_open(literal, 0, 0)` in the TLS / sigil
trust paths — worth a sweep. (Mirrors the dig/taar/whirl per-target `sys_open`
discipline: agnos passes an explicit `namelen`.)

Secondary (defensive, separate): `_tls_native_alloc` silently ignoring the
`tls_native_set_ca_system` return is why a trust-store load failure degrades to a
confusing handshake failure rather than a clear "no roots" error — consider
surfacing it.

## Workaround in place (consumer side)

whirl 0.6.1 loads `/etc/ssl/cert.pem` itself with the correct agnos ABI and
installs it via `tls_native_set_ca_bundle` through a `tls_connect_with_ctx_hook`
hook (`_agnos_ca_hook` in `whirl/src/transport.cyr`). This is a stopgap; it
should be removed once `tls_native_set_ca_system` opens correctly on agnos.
