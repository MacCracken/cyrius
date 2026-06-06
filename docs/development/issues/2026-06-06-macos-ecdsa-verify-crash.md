# sigil `ecdsa_p256_sign` corrupts heap/global memory on macOS (Mach-O) — the last layer blocking the TLS stack on macOS

- **Filed**: 2026-06-06 (v6.0.75); **root cause refined 2026-06-06 (.76 investigation)**
- **Reporter**: the .75 cross-OS lib-test (`scripts/cross-os-selfhost.sh ecb tls12`) on real ecb (Apple Silicon)
- **Affects**: `lib/sigil.cyr` **`ecdsa_p256_sign`** (`src/ecdsa_p256.cyr` in the sigil repo) on **macOS** (Mach-O; arm64 confirmed on ecb; x86-macOS/ach almost certainly the same — it's sigil-level, not arch-specific). **Linux unaffected** (full TLS suite green on x86_64 + aarch64, where the SKE sign→verify round-trip passes).
- **Severity**: blocks the native TLS handshake on macOS — the server signs the ServerKeyExchange with `ecdsa_p256_sign_der`, which corrupts memory so the *next* allocation/hash crashes (in practice the client's signature-verify, or any subsequent crypto). No real TLS handshake completes on macOS.

## ROOT CAUSE (refined): it is **sign**, not verify

The original symptom was "`ecdsa_p256_verify_der` SIGSEGVs," but a full bisect on ecb relocated it:
**`ecdsa_p256_sign` (the SKE/CertVerify signer) corrupts heap/global memory on macOS** — it completes
and returns a valid-length signature, but a buffer overflow / out-of-bounds write clobbers critical
memory (benign on Linux's heap/global layout, fatal on Darwin's), so the **next** `sha256` /
`fl_alloc` SIGSEGVs. The handshake test happened to crash in the verify-side `sha256` *because verify
runs right after sign*, which is why it first looked like a verify bug.

### Bisect evidence (ecb, native macho-arm64 cycc, post-.75 CSPRNG+freelist fixes)

- `ecdsa_p256_verify` **alone** (no preceding sign, crafted in-range sig) → **runs fine** (returns 0/1, no crash).
- `ecdsa_p256_sign_der` **alone** → returns a valid sig (`sl > 0`).
- `sign` **then** a plain `sha256` (no verify at all) → **SIGSEGV** in the sha256. ⟸ the decisive test: sign corrupts state that any later `sha256`/alloc trips over.
- The corruption **persists after sign returns** → it is a **heap or global** OOB write, not a reclaimed stack-local.
- Verify reaches `pt_is_on_curve`/`pt_from_affine` fine; it dies at the `sha256(msg,len,_ecv_digest)` call — i.e. at the first post-sign allocation, not in EC arithmetic.

### Localized to `_rfc6979_k_p256` (RFC 6979 deterministic nonce) — but a SUBTLE combination bug

Further bisection narrowed the corruptor inside sign to **`_rfc6979_k_p256`** (`lib/sigil.cyr` ~8258):
`sign-then-_rfc6979-then-sha256` SIGSEGVs, and isolating `_rfc6979_k_p256` + a following `sha256`
reproduces it directly. But **every individual ingredient works in isolation on ecb** — so it is a
subtle combination/interleaving bug, not an obvious oversized buffer:

| Tested in isolation on ecb | Result |
|---|---|
| `sha256` (standalone) | ✅ OK |
| `fl_alloc` small/arena + large + `fl_free`/reuse | ✅ OK |
| `secret var sc[416]` (1 block) + a following `sha256` | ✅ OK |
| 7 `secret var`s (mirroring `_rfc6979`'s V/K/Kt/Vt/data/d1/kint) + `sha256` | ✅ OK |
| 1 `hmac_sha256(key32, msg97)` + `sha256` | ✅ OK |
| 10× `hmac_sha256` in a loop + `sha256` | ✅ OK |
| EC verify arithmetic (`pt_scalarmul`/`pt_add`/`pt_to_affine`/`fn_p256_inv/mul`) — verify-alone | ✅ OK |
| **`_rfc6979_k_p256` then `sha256`** | 🔴 **SIGSEGV** |

So the shared EC arithmetic + the freelist + `secret` codegen + `hmac_sha256` are all exonerated. The
corruption emerges only from `_rfc6979_k_p256`'s specific mix: **interleaved `fl_alloc`/`fl_free` of
different sizes (`hmac_sha256`'s internal sha256 ctx vs any `u256` bignum scratch) over its 7 live
secret-scratch buffers**, which appears to corrupt a freelist class-list (heap metadata) on Darwin's
layout — benign on Linux's. The exact OOB is the remaining work.

### Update (.76): sigil 3.7.3 re-fold does NOT fix it; localized to the reject loop; printf-bisection exhausted

- **Re-folded sigil 3.6.4 → 3.7.3** (non-breaking: +13 public fns incl. AES-128-GCM, RSA-PSS, TEE quote-verify; no removals; Linux `check.sh` 85/85). The `_rfc6979_k_p256` source is **byte-identical** in 3.7.3 and **still crashes** on ecb (`rfc6979-then-sha256 = 139`). So this is not a stale-vendored-copy bug.
- **Narrowed to the RFC 6979 reject loop:** an instrumented early-return *before* `while (tries < 256)` is **clean** (`81`); the loop body is the corruptor.
- **But every loop ingredient is clean in isolation** (all on ecb, with `_p256_init()`): `hmac_sha256` at msg_len 32/33/56/64/97, the `u256_load_be/is_zero/cmp/store_be` sequence (×5), 7 live `secret var`s + hmac, `sha256`, `fl_alloc`/`fl_free`/reuse. **A `u256` test first looked guilty (139) but was a false positive — it had skipped `_p256_init()`, so `_p256_n` was a null global.** With init it is clean (`82`).
- **Conclusion:** the corruption only manifests from `_rfc6979_k_p256`'s *full* interleaving (hmac's internal `fl_alloc`/`fl_free` of the 144-byte sha256 ctx ↔ the surrounding `u256`/`memcpy` over 7 live secret-scratch buffers), leaving a freelist free-list head / heap-metadata corrupted so the *next* `fl_alloc` faults. printf-bisection can't isolate it further — every part is individually fine.

### lldb on ecb — DEFINITIVE: a cyrius freelist near-null deref (NOT a sigil bug)

Ran the crashing binary under lldb on ecb (needs `codesign -s - --entitlements get-task-allow.plist`,
and `lldb -b -o run -k "<post-crash cmds>"` since batch mode can't go interactive on the crash):

```
stop reason = EXC_BAD_ACCESS (code=1, address=0x18)
->  ldr x0, [x0]        ; x0 = 0x18  → fault
    ...
    ldur x0, [x29,#-0x18]   ; x0 = cls = 3
    lsl  x0, x0, #3         ; x0 = cls*8 = 0x18
    ldr  x1, [sp], #0x10    ; x1 = base = 0x0   ← the BASE is null
    add  x0, x0, x1         ; x0 = 0x18 + 0 = 0x18
->  ldr  x0, [x0]           ; load64(0x18) → EXC_BAD_ACCESS
regs: x0=0x18 x1=0x0 x2=0x20 x8=0x9 x16=0xC5(=197 mmap)
```

This is the freelist's **`load64(&_fl_heads + cls*8)`** (`lib/freelist.cyr`; `var _fl_heads[72]`) with the
**base `&_fl_heads` resolved to 0** (cls=3). The *first* `&_fl_heads` access in the same instruction
stream is VALID; a *second* one is 0 — and the same access works fine during `_rfc6979`'s own
`hmac`→`fl_free` calls, so it is **context-dependent, not a static address bug**. `x16=197` shows a
freelist arena mmap happened recently, but forcing an arena grow (700×`fl_alloc(144)` > 64 KB) then a
hash is **clean** — so arena-grow itself is exonerated; the null base is a codegen/register-or-stack
issue around the freelist access after `_rfc6979`'s specific activity.

**Conclusion: this is a CYRIUS Mach-O codegen bug in the freelist `&_fl_heads` global-address access,
NOT a sigil bug.** The fix is cyrius-side (`src/backend/` and/or `lib/freelist.cyr`), no sigil change /
fold needed. Next: find why the `&_fl_heads` base computes 0 in this path — disassemble the full
`fl_free`/`fl_alloc` on ecb (it is a 2-arg-shaped frame: arg0→fp-0x8 valid, arg1→fp-0x10 = 0), check
how cyrius emits `&<module-level array global>` on Mach-O when it appears twice in a function, and
whether a preceding `svc` (the freelist mmap) clobbers the cached base. A targeted reproducer + a
backend codegen fix; the cross-OS lib-test gate will confirm `tls12_*` green on ecb.

### Earlier suggested step — lldb (now done, see above)

Run the crashing binary under `lldb` on ecb: catch the SIGSEGV (it will be in `sha256_init`→`fl_alloc` dereferencing a bad free-list `next`), then set a **watchpoint** on that freed block / the `_fl_heads[cls]` slot and re-run to catch the *write* that corrupts it inside `_rfc6979_k_p256`. That pins whether it is a sigil OOB or a cyrius freelist-linkage / macho-codegen bug. Strong suspicion now leans toward a **cyrius freelist free-list** edge (the `.75` fix covered only the arena `MAP_ANON`, not the free/reuse linkage under interleaved different-size alloc/free) OR a macho codegen issue — i.e. possibly a **cyrius** fix, not sigil.

### Original suggested next step (superseded by the lldb plan above)

Instrument `_rfc6979_k_p256` on ecb with an inline `sha256`-canary after each portion (the first 4
HMAC blocks vs the accept/reject loop) to pin which interleaving corrupts; then check `u256_*`'s
scratch allocation vs `hmac_sha256`'s for a free-list class mismatch. **Fix lands in the sigil repo
(`~/Repos/sigil/src/`, currently 3.7.3 vs vendored 3.6.4) + a re-fold into `lib/sigil.cyr`** — a stdlib
dep bump (needs the leader's signal). Re-folding sigil 3.7.3 first (it's ahead) is worth trying — it may
already differ in this path.

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
