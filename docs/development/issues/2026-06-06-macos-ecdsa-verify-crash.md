# sigil ECDSA-P256 **verify** path SIGSEGVs on macOS (Mach-O) — the last layer blocking the TLS stack on macOS

- **Filed**: 2026-06-06 (v6.0.75)
- **Reporter**: the .75 cross-OS lib-test (`scripts/cross-os-selfhost.sh ecb tls12`) on real ecb (Apple Silicon)
- **Affects**: `lib/sigil.cyr` EC public-key verify (`ecdsa_p256_verify_der` / `ecdsa_p256_verify`, and/or `x509_cert_pubkey`) on **macOS** (Mach-O, arm64 confirmed on ecb; x86-macOS/ach almost certainly the same — it's a sigil-level issue, not arch-specific). **Linux unaffected** (full TLS suite is green on x86_64 + aarch64).
- **Severity**: blocks the native TLS handshake on macOS — the client verifies the server's ServerKeyExchange / certificate signature via this path. With it crashing, no real TLS handshake completes on macOS.

## Context — this is the LAST of three stacked "found by ports" macOS bugs

The native TLS/crypto stack had **never actually run on macOS** — only cycc-self-host had ever run on ecb, never the `.tcyr` tests. The new `.75` cross-OS lib-test mechanism ran the TLS suite on real macOS for the first time and peeled back three stacked bugs:

1. **macOS CSPRNG broken** (`sys_getrandom` used Linux syscall 318 → garbage random). **FIXED in .75** (ESYSXLAT 318/278 → Darwin getentropy 500 on both backends + stdlib 0→len normalization).
2. **Freelist allocator mmap broken** (`fl_alloc` used Linux `MAP_ANONYMOUS=0x20`; Darwin `MAP_ANON` is `0x1000` → mmap returned MAP_FAILED → first store SIGSEGV'd → crashed ALL sigil crypto). **FIXED in .75** (`_fl_map_flags()` target-conditional; `CYRIUS_TARGET_MACOS` → `0x1000`).
3. **ECDSA-P256 verify SIGSEGVs** — *this issue*, the remaining layer (deferred per leader 2026-06-06: ".75 = the freelist repair; log any remaining issues for later").

## What works on macOS now (verified on ecb, post-fixes #1 + #2)

Every one of these returns success on real ecb with the freshly-built native macho-arm64 `cycc`:

- `sys_getrandom` (fills the buffer, returns the byte count) — `build_client_hello`, `new_client` work.
- `fl_alloc` (small/arena + large/mmap paths), `sha256`, `x25519_base` + `x25519` (ECDH agreement).
- `hex_decode` (including the full 770/276-char test cert/key strings).
- `tls_native_new_server` + `tls_native_server_load_creds` (X.509 cert parse + private-key parse).
- **`ecdsa_p256_sign_der`** (the SKE signer) — works.
- Large stack frames (2 KB – 16 KB) — work.
- `tls12_ciphersuites.tcyr` — **passes on ecb** (28/28).

## What crashes (SIGSEGV / exit 139)

A probe that does `load_creds` → `ecdsa_p256_sign_der` (OK) → `x509_cert_alloc` + `x509_parse(cert)` (a *second*, direct parse) → `x509_cert_pubkey` → `ecdsa_p256_verify_der` **SIGSEGVs**. Sign alone returns 100 (OK); the crash is in the **verify half** — either the direct `x509_parse`/`x509_cert_pubkey` (note: `x509_parse` *inside* `load_creds` works, so suspect a 2nd-allocation or pubkey-extraction path) or `ecdsa_p256_verify_der` (the EC public-key scalar-mult path, distinct from the private-key sign path that works).

`tls12_handshake_msgs.tcyr` and `tls12_handshake.tcyr` (the e2e) crash here — they exercise the SKE sign→verify round-trip and X.509 chain verify.

## Reproduce

```sh
# from the cyrius repo (ecb has the bundle in ~/_cyaud after a cross-OS run):
sh scripts/cross-os-selfhost.sh ecb tls12     # tls12_ciphersuites PASS, tls12_handshake_msgs LIBTEST_FAIL
# minimal repro on ecb with the native cycc (r1r in ~/_cyaud):
#   load_creds(cert23,key23) → ecdsa_p256_sign_der (OK) → x509_parse+pubkey → ecdsa_p256_verify_der → SIGSEGV
```

## Suspected root cause (to investigate)

Sign works but verify crashes → the divergence is the EC **public-key** path. Candidates, in order:
1. `ecdsa_p256_verify_der` / `ecdsa_p256_verify` uses a code path (point ops, a different scratch buffer, a static table, or a fnptr/indirect call) the sign path doesn't — and that path is macho-fragile.
2. `x509_cert_pubkey` / a second `x509_cert_alloc`+`x509_parse` (the in-`load_creds` parse works; a direct second one may hit a different allocation path).
3. Another cross-target constant like the freelist `MAP_ANON` (already fixed) lurking in a verify-only path.

Next step: bisect the verify path on ecb with the `.75` mechanism (`scripts/cross-os-selfhost.sh ecb <glob>`) — add return-coded probes between `x509_cert_alloc`, `x509_parse`, `x509_cert_pubkey`, and `ecdsa_p256_verify_der` to pin the exact faulting call, then disassemble it on ecb.

## Definition of done

`tls12_handshake_msgs.tcyr` + `tls12_handshake.tcyr` pass on ecb (and ach) via `sh scripts/cross-os-selfhost.sh ecb tls12` / `ach tls12`. That proves the full native TLS 1.2 stack runs on macOS.
