# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.

## Session close — 2026-06-07 (.86 ship — Windows DXGI GPU enum: callptr callee-spill aliased a &-local)

Closing **v6.0.86**. check.sh **85/85**; self-host byte-identical on ecb + ach + pi + cass; tcyr 0/167.
**The last Windows item — `lib/dxgi.cyr` `dxgi_vram_bytes()` (ai-hwaccel's native GPU detection) — is
GPU-VERIFIED on cass** (Intel UHD 600 → 128 MB DedicatedVideoMemory, full COM chain clean).

Root cause (cdb on cass — `C:\dbg\cdb.exe`, tools were there): **the `callptr` callee-spill frame slot
could alias a `&`-taken local.** v6.0.70 spilled the indirect-call target to a `GFLC` frame slot; in a
frame passing a `&local` out-param to a COM method, that slot landed on the SAME offset as the local
(`&pAdapter` for EnumAdapters1 == the callee-spill at rbp-0x50) → out-param/spill collision → frame +
regalloc corruption → the GetDesc1 dispatch loaded avtbl from a stale r12=0 → `mov rax,[0x50]` → AV.
Frame-dependent, real-Win64-callee-only, invisible to self-host (cycc has no callptr). **Fix:** emit the
PE callptr callee on the STACK + `call rax` (no frame slot → no alias); non-PE path unchanged
(byte-identical Linux/macOS/aarch64). The v6.0.71 ECALLPTR_PE force-align was a separate, real fix.

**Process note (user correction, pinned [[feedback_check_hardware_directly_not_verdicts]]):** I'd
twice deferred DXGI as "operator-gated (no debugger / integrated GPU)" — both wrong. cdb WAS on cass
(`C:\dbg\`; my Program-Files-only + minimal-PATH `where` searches missed it), and the integrated GPU is
plenty (it's a codegen bug, not VRAM-size). User: *"TOOLS ARE THERE MAN"* / *"IF YOU CANNOT SOLVE FOR
INTEGRATED..."*. **The Windows arc is now fully closed.**

**Next (leader sequence):** .87 AGNOS (cross-build gate + envp/getenv — gated on agnos landing
envp-at-exec first) → .88 cleanup/refactor → .89 closeout + docs sweep → v6.1.0.

## Session close — 2026-06-07 (.85 ship — Windows install pillar: `cyrius build` works on Windows)

Closing **v6.0.85**. check.sh **85/85**; self-host byte-identical; cross-OS self-host green on ecb + ach
+ pi; **cass install pillar gate green** (real `install.ps1` → `cyrius build` → exit 42). **Windows is
now a verified-supported platform at the macOS-`.38` bar** — a real install yields a toolchain you can
`cyrius build` with.

Windows had a green cross-OS *self-host* gate but had **never been installed-and-used end-to-end**. I
put hands directly on cass (after the user's correction — don't take gate verdicts/pins/probes as
gospel, [[feedback_check_hardware_directly_not_verdicts]]) and each layer surfaced by testing:

1. **No Windows env-reading in the toolchain** → new **`GetEnvironmentVariableA` PE reroute (`0xF015`)**
   (pe/x86/aarch64 emit + parse_expr; 3-arg aligned caller).
2. **Wrapper couldn't find cycc** → `cbt/core.cyr` reads `CYRIUS_HOME`/`USERPROFILE` via the reroute +
   resolves `bin/cycc.exe` (was `bin/cycc`, `_home` defaulted to `/root`).
3. **Wrapper couldn't invoke cycc** (POSIX fork/execve) → `compile()` spawns `cycc < src > out` via
   cmd.exe + `CreateProcessW` (`lib/process_win.cyr` `_win_compile_spawn`).
4. **No native installer / tarball had no wrapper** → `scripts/install.ps1` + `build-windows-tarball.sh`
   (SSOT, now ships `cyrius.exe` + the installer); release.yml rewired to it.
5. **No hardware install gate** → `cass-install-gate.{sh,ps1}` wired into `cyrius audit`.
6. **`cyrius deps --lock`** → certutil hash on Windows (`cbt/deps.cyr`).

**Premise-check win:** the Windows `cycc`-runtime "bug 2" pin was STALE — `cycc.exe` already compiles +
self-hosts on cass (re-verified hands-on: fns+loop+args → runnable PE). Issue corrected + archived;
only the install Pillar remained, delivered here.

**Still deferred (operator-gated, NOT this slot):** the Windows **DXGI demonstrator** — cass has no
windbg/cdb and only an integrated Intel UHD 600 GPU, so the 1-arg-COM AV can't be single-stepped and
`DedicatedVideoMemory` is ~0 there. Needs the operator to provision a debugger + a discrete GPU.
**Latent (from .84):** macho-arm socket *family* (socket/connect/accept) still mapped with x86 nums.

**Next (leader order):** the remaining Windows DXGI residual (operator-gated) + `cyrius deps --lock`
Windows-portable end-to-end + AGNOS-target install → cleanup/refactor cluster → cycle closeout → v6.1.0.

## Session close — 2026-06-07 (.84 ship — macOS native-TLS: thread_local TPIDR + socketpair, both fixed)

Closing **v6.0.84**. check.sh **85/85**; self-host byte-identical; cross-OS green on ecb + pi + cass.
**The full TLS 1.2 e2e suite now runs on Apple Silicon** — `tls12_*` 5/5 on ecb incl. the
fork+socketpair handshake that was crashing.

The roadmap item was *"macOS `&_fl_heads` freelist codegen bug."* That diagnosis (from the issue's
earlier lldb) was **WRONG** — the `&global` adrp+add path is provably correct. An lldb repro on real
ecb surfaced two genuinely distinct stacked bugs:

1. **`thread_local` can't own `TPIDR_EL0` on macOS** (the crypto crash). `lib/thread_local.cyr` used
   `msr/mrs TPIDR_EL0` for the TLS base. Darwin owns that register and **restores it across
   preemption** — proven with a 2-billion-iter pure-compute loop (zero syscalls) that reset it from a
   valid block to a Darwin thread value (`~0x2010`). sigil's `cbank()` lazy-inits once, so the first
   preemption during crypto (ECDSA sign) made every later `thread_local_get` fault. Fix: macOS
   process-global slot array (no TPIDR) — cyrius threads don't run on macOS (`thread.cyr` is
   clone-only), so single-threaded is correct. Lib-only → self-host byte-identical.
2. **`socketpair` untranslated on Darwin** (unmasked once crypto worked). arm-macho pulls
   `syscalls_aarch64_linux.cyr` → socketpair is **199**, not the x86/macos **53** (which is *fchmodat*
   on that enum — a 53 entry collides). Fix: `199→135` (aarch64-macho) + `53→135` (x86-macho) ESYSXLAT
   + whitelist sync. Encodings assembler-verified on ecb.

**Cross-OS:** ecb (arm64) self-host + 5/5 tls12; pi (aarch64-Linux) self-host + 5/5; cass (Windows)
self-host byte-identical. **ach (x86-macho)** self-hosts but `tls_native` tests can't compile — the
pre-existing **held** x86-macho cycc layer-6 miscompile (`error: unexpected enum`, a frontend parse
error; issue `2026-06-02-macos-x86-release-no-compiler.md`, Intel/EOL). The x86-macho fixes are present
+ correct in the self-hosted cycc, runtime-unverifiable there until that held issue clears.

**Latent finding (NOT fixed — surfaced, out of scope):** the macho-arm socket *family*
(socket/connect/accept/bind/listen) is mapped with x86 numbers (41-50) in the aarch64-macho ESYSXLAT,
but arm-macho uses aarch64-Linux numbers (198/203/202/200/201) → **real-network sockets are likely
broken on arm-macho** (the .81 live-Cloudflare proof was on Linux). Doesn't affect the socketpair e2e
or the tls12 suite. Related to `2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md`. Candidate
for a follow-up slot.

**Next (leader order):** the Windows remaining repair cluster (DXGI demonstrator / PE cycc-runtime
bug 2+ / deps-lock hash / `.ps1` installer / AGNOS-target install) → cleanup/refactor cluster → cycle
closeout → v6.1.0.

## Session close — 2026-06-06 (.83 ship — AES-128 + RSA-auth + P-384 ciphersuite enablement; sandhi 1.4.2 fold)

Closing **v6.0.83**. check.sh **85/85**; self-host byte-identical; cross-OS green on ecb + cass. The
native TLS client now speaks the rest of the mainstream web's crypto: **AES-128-GCM**, **RSA** server
certs (RSA-PSS over 1.3, PKCS#1 v1.5 / PSS over 1.2), and **ECDSA P-384**, on top of the ECDSA-P-256 it
already did. The .74 ciphersuite stubs are retired.

**Shipped:** AES-128-GCM (0x1301 in 1.3 + the 1.2 AES-128 suites; sigil `aes_128_gcm_*`, nr=10 — NOT
`aes_gcm_*` which is nr=14/AES-256). RSA server auth via a shared `_tn_rsa_verify_scheme` (n/e from
sigil's cert+248 side block, fail-closed on non-RSA). ECDSA P-384 (sigil `ecdsa_p384_verify` over a
DER→raw r‖s parse). TLS 1.2 server-flight reassembly (the .81 1.3 fix's sibling — `_tn_flight_complete`
gained a terminator-type param). Both sig-verify sites unified into `_tn_verify_sig_scheme`. Folded
**sandhi 1.4.2** (byte-identical). All helpers internal — api-surface unchanged.

**Method note — adversarial review caught 3 real bugs, all fixed in-slot:** (P1) the new 1.2
reassembly loop spun forever on zero-length handshake records (no timeout) → now `BAD_RECORD`; (P2) the
1.3 CertVerify accepted `rsa_pkcs1_*` schemes RFC 8446 §4.2.3 forbids in 1.3 → now rejected (1.2 SKE
still allows them); (P2) P-384 was advertised-but-unhandled → wired. The review correctly DISMISSED a
flagged `alloc(128)` server-RSA-sign overflow as unreachable (that sign path returns KEY_UNSUPPORTED
first). Verified vs OpenSSL `s_server`: RSA-1.3+AES-128 / RSA-1.2 / P-384 all handshake OK; live
Cloudflare regression green. scaffold 412.

**Latent (tracked, not reached):** `_tn_12_sign_kex_params` allocs sig[128] — too small for a 256-byte
RSA-2048 signature IF cyrius-as-SERVER ever signs with RSA; currently unreachable (no server RSA-sign
path). Fix when/if server-side RSA certs land.

**Next (leader order):** repair slots — macOS `&_fl_heads` freelist codegen bug; Windows cluster (cdb
on cass) — then cycle closeout → **v6.1.0**.

## Session close — 2026-06-06 (.82 ship — backend-agnostic TLS peer-introspection verbs; sandhi-rewire enablement)

Closing **v6.0.82**. check.sh **85/85**; self-host byte-identical; cross-OS green on ecb + cass. The
cyrius half of the Mini-arc E sandhi rewire — the typed verbs sandhi needs to drop its raw-SSL-ptr +
tls_dlsym bindings.

**Added:** `tls_native_get_peer_spki_der` (extracts the leaf SubjectPublicKeyInfo DER via sigil's
der_walk — SHA-256 matches openssl's pin EXACTLY, hermetic + live-verified), `tls_native_get_peer_cert_der`
(was a stub → returns leaf DER), and the backend-agnostic wrappers `tls_get_alpn_selected` /
`tls_get_peer_spki_der` in lib/tls.cyr (native → the sovereign verbs; libssl → the FFI moved out of
sandhi). Live-validated vs Cloudflare: ALPN `h2` + SPKI both via the wrapper verbs on native. +3 public
fns, non-breaking. Scaffold 400.

**Next — the sandhi EDIT (gated on .82 release):** sandhi vendors lib/tls.cyr via `cyrius deps`, so it
re-syncs the released .82 first, then I rewire `src/http/conn.cyr` (_sandhi_alpn_read_selected →
`tls_get_alpn_selected`) + `src/tls_policy/apply.cyr` (_sandhi_check_spki → `tls_get_peer_spki_der` +
SHA-256) and drop all its tls_dlsym/raw-SSL* sites. That CLOSES Mini-arc E. Then (leader order):
AES-128 + RSA-auth ciphersuite enablement → repair slots (macOS `&_fl_heads` freelist codegen; Windows
cluster, cdb on cass) → cycle closeout → **v6.1.0**.

## Session close — 2026-06-06 (.81 ship — SOVEREIGN HTTPS: server-flight reassembly + live Cloudflare smoke)

Closing **v6.0.81**. check.sh **85/85**; self-host byte-identical; cross-OS self-host green on ecb +
cass. **Milestone: the native TLS stack does real-world HTTPS, no libssl.** Mini-arc E Release B's
load-bearing technical piece.

**Headline:** **server-flight reassembly** — the last blocker for live EXTERNAL HTTPS.
`tls_native_client_recv_flight` previously read ONE record for the server flight (EE/Cert/CertVerify/
Finished) — fine for a tiny self-signed cert, but real servers fragment a large Certificate (chain +
SCTs) across records (RFC 8446 §5.1), so the client got a partial flight and hung. Now: decrypt the
first record, then loop-read+decrypt handshake records into one plaintext buffer until the flight is
complete (`_tn_flight_complete` walks messages, stops at Finished; bounded 64 KB). **Proven LIVE: a
real TLS 1.3 handshake with Cloudflare 1.1.1.1:443 — reassembly + cert-chain verification through the
OS trust store (rooted at the SSL.com root, parseable since sigil 3.7.4) + SNI — then an HTTP GET
returns `HTTP/1.1`.** Committed as a guarded smoke (`tls_native_realpeer.tcyr`; skips offline, 10 s
socket timeouts, robust to leaf rotation).

**Next — Mini-arc E Release B remaining:** **sandhi rewire** (cross-repo, leader-authorized in-arc:
ALPN-read onto `tls_native_get_alpn_selected`, SPKI-pin onto `tls_native_get_peer_cert_der` + sigil
hash, drop the `tls_dlsym`/raw-SSL-ptr sites) → closes Mini-arc E. **Then** (leader order): AES-128 +
RSA-auth ciphersuite enablement (unblocked by sigil 3.7.x) → repair slots (macOS `&_fl_heads` freelist
codegen bug; Windows cluster, cdb now on cass) → **cycle closeout → v6.1.0.**

## Session close — 2026-06-06 (.80 ship — Mini-arc E Release A complete: sigil 3.7.4 fold + native TLS wrapper)

Closing **v6.0.80**. check.sh **85/85**; self-host byte-identical; cross-OS self-host green on ecb +
cass. **Mini-arc E Release A complete** — the sovereign native-TLS client path is wired end-to-end into
the stdlib wrapper, and real-server cert verification works.

**Two substantive pieces:** (1) **Folded sigil 3.7.4** — its `x509_parse` `ec_fw` fix (retry r,s width
at 48 on overflow) lets real-world ECDSA roots parse (SSL.com Root ECC = P-384 key + ecdsa-with-SHA256,
+ ~12 OS roots that were silently dropped). With `.78`'s trust store, **the live Cloudflare → SSL.com
chain validates through the real OS trust store in cyrius** (dev-check = VERIFIED). The `.78`
"x509_parse SIGSEGV" report was a test-harness bug (wrong hex_decode length) — corrected + archived.
(2) **Bite 4 — `lib/tls.cyr` re-backed onto native** behind `CYRIUS_TLS_NATIVE` (keep-both: libssl is
the default; the flag pulls tls_native.cyr + defaults to native; `tls_set_backend` switches at runtime).
The full client path (connect/write-fragmenting/read/close + typed set_alpn/set_verify, hook on the
opaque native ctx, chain+SNI verification on complete) routes to `tls_native_*`. Committed e2e:
wrapper-client (native) ↔ cyrius-native server (`tls_wrapper_native.tcyr`). +2 public fns, non-breaking.

**The sigil saga (premise correction):** the "sigil x509_parse crashes on real certs" `.78` claim was
WRONG (my hex_decode test bug). The real bug was a parse REJECTION (ec_fw hash-derived, not curve-aware)
of P-384-key-with-SHA256 roots. Fixed in sigil 3.7.4 (retry-on-overflow — the first attempt, forcing
ec_fw by the cert's own curve, broke the SEV-SNP VCEK; corrected). Off-diagonal ECDSA *verify*
(hash≠curve chain LINKS) is P1 on sigil's roadmap + an issue — not needed for cloudflare-class chains.

**Next — Mini-arc E Release B:** server-flight reassembly (the last blocker for live EXTERNAL HTTPS),
sandhi rewire (ALPN-read + SPKI-pin onto typed native verbs, drop tls_dlsym — leader authorized in-arc),
the live one.one.one.one:443 real-peer smoke (now that cert verification works), + closeout. Then
cycle closeout → v6.1.0. Also queued: macOS &_fl_heads freelist codegen bug, Windows repair cluster
(cdb now provisioned on cass), AES-128/RSA-auth ciphersuite enablement.

## Session close — 2026-06-06 (.79 ship — SECURITY: cyml_parse OOB stack-write fix)

Closing **v6.0.79**. check.sh **85/85**; self-host byte-identical (cyml not in cycc). A HIGH-sev
stdlib memory-safety patch, slotted between TLS arc work per leader order.

**Fix:** `lib/cyml.cyr` `cyml_parse` — `var entry_starts[256]` (256 *bytes* = 32 slots, function-local)
was written at 8-byte stride up to 256 entries → **1792-byte OOB stack write from untrusted CYML**
(return-address hijack at worst; reachable in ring-3 tools commandress/bannermanor). Sized to true
capacity: `var entry_starts[2048]` (256×8 B) + a byte-unit comment guarding the `var X[N]`-is-N-bytes
footgun. Found by the agnos 1.42.14 audit. Regression: a 50-entry CYML now parses
(`tests/tcyr/cyml.tcyr`). Verified Linux + real macOS (ecb); issue archived.

**Windows note:** running cyml.tcyr cross-OS surfaced a *pre-existing* Windows gap — an unrouted
`syscall(n)` in cyml's alloc/fmt deps → STATUS_ILLEGAL_INSTRUCTION. `cyml_parse` uses neither, so the
lib + fix are correct on Windows; only the test harness is blocked → **Windows repair cluster**. Fixed
one of two gaps en route (explicit `include "lib/vec.cyr"` so fmt's `vec_get` resolves on PE).

**Next (leader-set order):** **`.80`** = fix sigil `x509_parse` real-cert crash (in ~/Repos/sigil, then
re-fold — issue 2026-06-06-sigil-x509-parse-…) **+ bite 4** (the `lib/tls.cyr` wrapper rebuild onto
native, keep libssl fallback). Unblocks Mini-arc E Release B (sandhi rewire + real-peer smoke +
closeout), which also needs server-flight reassembly. cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.78 ship — sovereign native-TLS client features: close_notify + ALPN + trust store)

Closing **v6.0.78**. check.sh **85/85**; self-host byte-identical; cross-OS self-host green on ecb +
cass. **Mini-arc E Release A, part 1** — the native client-side features the stdlib `lib/tls.cyr`
wrapper will need, landed + hermetically tested. The wrapper rebuild (bite 4) was deferred mid-arc
behind a sigil blocker (below).

**Headline (3 bites):** (1) **`tls_native_close`** — encrypted close_notify send + receive (read→0 on
clean EOF), 1.2 + 1.3, e2e-proven. (2) **client ALPN** (RFC 7301) — CH offer (1.2+1.3), selection
parse from EE/SH, `get_alpn_selected`; hermetic. (3) **real trust store** — multi-root `set_ca_bundle`,
`set_ca_system` (OS bundle, >150 anchors), intermediate capture, `verify_chain` reverse+loop (sigil
already owned the chain walk; bite 3 was plumbing, no split). `TLS_CTX_LEN` 448→456; +2 public fns
(`set_ca_system`, non-breaking).

**Blocker found (reshaped the arc):** a dev-check against a live Cloudflare chain showed **sigil's
`x509_parse` SIGSEGVs on a real CT-SCT leaf cert** (+ fails on a real intermediate) — HIGH-sev (crash
on untrusted server cert) and the blocker for Release B's real-peer smoke + sandhi.
[issue: 2026-06-06-sigil-x509-parse-crashes-real-world-certs.md]

**Next (leader-set order):** **`.79`** = the cyml_parse OOB stack-write security fix
(`var entry_starts[256]`→`[2048]`; issue 2026-06-06-cyml-parse-…). **`.80`** = fix sigil `x509_parse`
(in ~/Repos/sigil, then re-fold) + bite 4 (the `lib/tls.cyr` wrapper rebuild onto native, keep libssl
fallback). Then Release B (sandhi rewire + real-peer smoke + closeout), which also needs server-flight
reassembly. cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.77 ship — TLS 1.2 Extended Master Secret (RFC 7627) + OpenSSL interop)

Closing **v6.0.77**. check.sh **85/85**; self-host byte-identical; cross-OS self-host green on ecb +
cass. Closes **Mini-arc D's real-peer validation** — the deferred OpenSSL 1.2 interop, shipped together
with EMS as one negotiated feature.

**Headline:** TLS 1.2 **Extended Master Secret** (RFC 7627) end-to-end — `master = PRF(pm, "extended
master secret", session_hash)` where session_hash = Hash(CH..CKE). New `tls_native_12_master_secret_ems`
(+1 public fn, non-breaking), `TLS_EXT_EXTENDED_MASTER_SECRET`/`TLS_CTX_OFF_USE_EMS`, full negotiation
(client offers + validates echo with legacy fallback; server parses the CH ext block — which it
previously skipped — and echoes iff offered), the EMS-vs-legacy branch in derive_keys, and the
load-bearing client reorder in connect_12 (feed CKE before derive; server already correct). Real-peer
proof: our server interops with **OpenSSL 3.6.2 s_client** (ECDHE-ECDSA, AES-256-GCM + ChaCha20),
EMS negotiated on the wire. Tests: scaffold 387 (incl. the live OpenSSL interop), handshake_msgs 73
(+7 EMS units), handshake e2e 20 (+EMS both sides). 4 bites, tested after each.

**Side-benefit available:** the `.76` sigil 3.7.3 fold added AES-128-GCM + RSA-PSS → the `.74`-stubbed
TLS ciphersuites (AES-128 + RSA-auth suites) are now enable-able in a future slot.

**Next:** Mini-arc E (consumer wiring) is the remaining TLS-arc step. Queued as own slots: the macOS
`&_fl_heads` freelist codegen bug (the lldb-pinned `.76` issue — unblocks TLS-on-macOS), the Windows
repair cluster, and the AES-128/RSA-auth ciphersuite enablement. cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.76 ship — sigil 3.7.3 re-fold + macOS TLS crash pinned to a cyrius codegen bug)

Closing **v6.0.76**. check.sh **85/85**; self-host byte-identical. A stdlib re-fold + a deep diagnosis
slot (no TLS feature). Continues the `.75` macOS thread (the cross-OS lib-test gate that revealed the
native TLS stack had never run on macOS).

**Headline:** (1) **Re-folded sigil 3.6.4 → 3.7.3** (dist fold, non-breaking: +13 public fns / 0
removals — AES-128-GCM + RSA-PSS + TEE quote-verify; api-surface +13). Side benefit: AES-128-GCM +
RSA-PSS now exist in sigil → unblocks the `.74`-stubbed TLS ciphersuites (AES-128 + RSA-auth) for a
future slot. (2) **Root-caused the remaining macOS TLS blocker** (the `.75` `tls12_handshake_msgs`/
`tls12_handshake` SIGSEGV) via exhaustive bisect + **lldb on ecb**: "`ecdsa_p256_verify` crashes" →
`ecdsa_p256_sign`'s `_rfc6979_k_p256` corrupts the heap → the freelist's `load64(&_fl_heads + cls*8)`
faults with the **global-array base resolving to 0** (`ldr x0,[x0]`, x0=0x18). It is a **cyrius Mach-O
codegen / global-address bug, NOT sigil** — 3.7.3 is byte-identical in this path and doesn't fix it; the
fix is cyrius-side. Arena-grow exonerated (700×fl_alloc>64 KB then hash = clean). Logged in full:
`docs/development/issues/2026-06-06-macos-ecdsa-verify-crash.md`.

**Next (leader: bank .76, move on):** the deferred TLS-arc work — **OpenSSL 1.2 interop + EMS** (Mini-arc
D real-peer validation; spec workflow output cached on disk) — then Mini-arc E (consumer wiring). The
macOS freelist `&_fl_heads` codegen bug + the Windows repair cluster are queued as their own slots
(both surfaced/kept-visible by the cross-OS gate). cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.75 ship — macOS CSPRNG + freelist repair + cross-OS lib-test gate)

Closing **v6.0.75**. check.sh **85/85**; self-host byte-identical (x86_64 + aarch64); macho-arm64
self-hosts on ecb. A compiler-backend + stdlib slot, NOT a TLS-feature slot — it makes the native
TLS/crypto stack actually *run* on macOS (it never had — only cycc-self-host ran on ecb, never the
`.tcyr` tests).

**Headline — three stacked macOS "found by ports" bugs, surfaced by a new cross-OS lib-test gate.**
The native TLS stack had never executed on real macOS. A new opt-in **lib-test fallback**
(`scripts/cross-os-selfhost.sh <host> [tcyr-glob]` — runs the slot's `tests/tcyr/<glob>*.tcyr` on the
real host with its native cycc after the self-host check) ran the TLS suite on ecb for the first time
and peeled back: (1) **CSPRNG broken** — `sys_getrandom` issued Linux syscall 318 on Mach-O → garbage
random → whole TLS stack dead. **Fixed**: ESYSXLAT 318/278 → Darwin getentropy 500 on BOTH backends
(aarch64 + x86; x86 needed an imm32 `_msx32` since 318 > 255) + stdlib 0→len normalize. (2) **Freelist
mmap broken** — `fl_alloc` used Linux `MAP_ANON=0x20`; Darwin's is `0x1000` → MAP_FAILED → SIGSEGV →
crashed ALL sigil crypto (the bump alloc worked via `alloc_macos.cyr`). **Fixed**: `_fl_map_flags()`
target-conditional. (3) **sigil ECDSA-P256 verify SIGSEGVs** — the last layer; characterized + logged
(`docs/development/issues/2026-06-06-macos-ecdsa-verify-crash.md`), deferred per leader.

**Verified on ecb (post-fix):** getrandom fills the buffer; `fl_alloc`/`sha256`/`x25519` ECDH/
`hex_decode`/X.509 parse/`ecdsa_p256_sign_der` all work; `tls12_ciphersuites` passes (28/28). Still
crashing: the EC **verify** path (sign works, verify doesn't) → `tls12_handshake_msgs`/`tls12_handshake`
don't pass on macOS yet. **Cross-OS posture (the .75 lesson, now a pinned rule):** the four-host gate
only ever ran cycc-self-host, which is lib-independent — exactly why stdlib bugs shipped green for the
whole TLS arc. The lib-test fallback closes that; it's interim (per-platform manifests + a PE-safe cass
subset are TODO — fork/socketpair are POSIX-only).

**Next:** the macOS ECDSA-verify crash (its own slot, finishes TLS-on-macOS), then the deferred
**OpenSSL 1.2 interop + EMS** (Mini-arc D real-peer validation; spec workflow output cached on disk),
then Mini-arc E (consumer wiring), the Windows repair cluster, and cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.74 ship — TLS 1.2 handshake message flow; Mini-arc D COMPLETE)

Closing **v6.0.74** (Mini-arc D step 3 — the 1.2 backport is now COMPLETE). check.sh **85/85**;
self-host byte-identical (x86_64) at 6.0.74; `tls_native_scaffold` 375/375 (TLS 1.3 path unaffected).

**Headline — the full TLS 1.2 (ECDHE) handshake.** `lib/tls_native.cyr` gains the complete 1.2
client+server handshake over the `.72` AEAD record layer + `.73` PRF/key-schedule: the ciphersuite
registry (the 6 wire suites ↔ the internal `0x130x` AEAD identity the crypto layer keys off; supported =
`0xC02C`+`0xCCA9`), every handshake message (CH/SH/Cert/ServerKeyExchange-sign+verify/SHD/ClientKeyExchange/
CCS/Finished), the ECDHE key-schedule glue (ephemeral-pub-only, x25519 premaster with the mandatory
all-zero reject, derive_keys into the reused 1.3 app-key ctx slots), and the `tls_native_connect_12` /
`tls_native_accept_12` drivers. `tls_native_connect`/`accept` now version-dispatch (client by `max_ver`,
server by a ClientHello `key_share`/`supported_versions` sniff); `seal_app`/`open_app` route 1.2 app data
to the `.72` record layer; `set_version_range` is implemented. New ctx offset `OFF_MASTER12=416`.

**Verification depth (ultracode):** a 21-agent byte-exact spec workflow drove the wire formats correct up
front; a **16-agent adversarial review found 8 real defects — all fixed + regression-tested in this same
release** (one-bug-one-complete-fix): a **P0 remote OOB heap read** (`_tn_12_client_consume_flight` fed an
unbounded 24-bit handshake length into `sha*_update` — now length-bounded), a downgrade-sentinel
false-reject of conformant 1.3-capable servers, a ClientKeyExchange transcript desync, RFC 5746 secure
renegotiation (signal + echo-validate), and `_tn_ctx_fail` wrapping. **e2e on x86_64 AND aarch64** (the
socketpair our-client↔our-server handshake + bidirectional app data, plus all unit suites:
`tls12_ciphersuites` 28/28, `tls12_handshake_msgs` 66/66, `tls12_handshake` 19/19 — identical on both
arches, aarch64 via a native cross-compile under qemu → byte-order/ABI clean). api-surface +22; stdlib-only.

**Cross-OS posture:** stdlib-only change — `cycc` does NOT include `lib/tls_native.cyr`, so its bytes
change only by the arch-independent `--version` string; the four-host `cycc` self-host is structurally
unaffected. Real-hardware **ecb/cass** runtime of the 1.2 `.tcyr` suite was NOT run this session (the 1.3
path interops with OpenSSL since `.23`; the 1.2 e2e is our↔our only). Aarch64 IS covered (qemu).

**Next:** **Mini-arc E** — consumer wiring + TLS arc closeout (sandhi onto `tls_native`, libssl-wrapper
disposition, consumer smoke). Real-peer OpenSSL 1.2 interop + **EMS (RFC 7627)** must be addressed before
that (the 1.2 path uses the legacy master derivation; EMS negotiation → different keys). Carve-outs:
client-auth, resumption, RSA-auth suites + P-384 SKE-verify (sigil gaps). Then the near-end Windows repair
cluster, last cleanup/refactor + sigil fold, cycle closeout → v6.1.0.

## Session close — 2026-06-06 (.73 ship — TLS 1.2 PRF + key derivation)

Closing **v6.0.73** (Mini-arc D step 2). check.sh **85/85**; self-host byte-identical on **all four
cross-OS hosts** (`pi` aarch64-Linux, `cass` Windows-PE, `ach` x86-macOS, `ecb` arm64-macOS) at 6.0.73.

**Headline — TLS 1.2 PRF + key derivation.** `tls_native_12_prf` (dispatch to sigil's P_hash by
ciphersuite hash) + `tls_native_12_master_secret` (PRF over `client_random‖server_random`, RFC 5246 §8.1)
+ `tls_native_12_key_block` (PRF over `server_random‖client_random` — the **reversed** order, §6.3) +
`tls_native_12_partition_keys` (AEAD: `cw_key‖sw_key‖cw_iv‖sw_iv`, no MAC keys) + `tls_native_12_key_block_len`
+ `tls_native_cipher_iv_len_12` (GCM 4-byte salt vs ChaCha 12-byte IV) + `tls_native_12_verify_data`
(Finished MAC, §7.4.9). All `lib/tls_native.cyr`, stateless — the handshake slot wires them to the ctx.
The PRF wrapper propagates sigil's seed-cap failure (no silent TLS_OK on an over-cap transcript hash).

**Verification depth (ultracode):** `tests/tcyr/tls12_keysched.tcyr` (26 asserts) is a **known-answer test**
cross-checked against an independent RFC 5246 §5 P_hash reference (HMAC expansion) for BOTH hashes
(AES-256-GCM-SHA384 + ChaCha20-Poly1305-SHA256) — master secret, key block (proving the reversed random
order), partition offsets, verify_data — plus a `.72` record round-trip with the **derived** keys. KAT also
proven on **aarch64** (native cycc under qemu → 26/26). 7-agent adversarial review (3 lenses, each finding
refuted) → **0 confirmed**; the lone shared nit (PRF wrapper discarding sigil's return) was unreachable for
the fixed-size internal seeds but hardened anyway. api-surface +7; stdlib-only (compiler changes only by
`--version`). sigil 3.7.3 already vendors `tls12_prf` + RSA sigs — no crypto blocker.

**Next:** **.74 — TLS 1.2 handshake message flow** (ClientHello/ServerHello version semantics, key
exchange, certificate + signature wiring) → Finished (consuming `.73`'s `verify_data`) → 1.2 ciphersuite
registration → 1.2 e2e; then Mini-arc E (consumer wiring + closeout), the near-end Windows repair cluster,
cycle closeout.

## Session close — 2026-06-06 (.72 ship — native TLS arc resumes: TLS 1.2 AEAD record layer; Windows back-burned)

Closing **v6.0.72**. check.sh **85/85**; self-host byte-identical on **all four cross-OS hosts** —
`pi` (aarch64-Linux), `cass` (Windows PE), `ach` (x86-macOS), `ecb` (arm64-macOS), each via
`scripts/cross-os-selfhost.sh` after the bump.

**Slate re-order (leader direction 2026-06-06):** *"back burn the windows items posted from .72 until later
after tls … windows remaining repair goes to near end of 6.0.x line of work."* The `.71`-deferred
windbg/DXGI demonstrator residual + the standalone Windows-repair slot are consolidated into ONE near-end
Windows repair cluster that runs **after** the TLS arc. `.72` onward = native TLS (Mini-arc D then E),
then the Windows repair cluster, then the LAST cleanup/refactor + sigil 3.7.3 fold, then closeout → v6.1.0.
roadmap.md back-end shape updated to match.

**Headline — TLS 1.2 AEAD record layer (Mini-arc D, step 1).** `tls_native_record_seal_12` /
`tls_native_record_open_12` + `tls_native_aead_nonce_12_gcm` + `tls_native_record_aad_12` + the
`_tn_cipher_is_gcm` predicate (all `lib/tls_native.cyr`). The three 1.2-vs-1.3 differences: real content
type in the **outer** header (no inner-type/padding); **13-byte AAD** (`seq‖type‖version‖length`, plaintext
length, RFC 5246 §6.2.3.3); **GCM 8-byte explicit nonce on the wire** (`salt(4)‖explicit(8)`, RFC 5288 §3)
vs **ChaCha20-Poly1305 implicit nonce** (`iv XOR seq`, RFC 7905). Legacy CBC intentionally skipped. The
RFC 5246 §6.2.1 2¹⁴ plaintext cap is enforced on seal AND open. `tests/tcyr/tls12_record.tcyr` (17 asserts:
both AEADs round-trip + wire format + tag-tamper → DECRYPT + over-cap → RECORD_OVERFLOW).

**Verification depth (ultracode):** an 18-agent adversarial spec-conformance review (4 lenses, each finding
independently refuted) cleared 13 of 14 findings — the one confirmed P3 (missing 2¹⁴ plaintext cap) was
fixed before cut. The new record code was additionally proven on **aarch64**: a native aarch64 `cycc`
(x86→cross→native) compiled the test and ran it under qemu → **17/17**, matching x86. sigil 3.7.3 already
vendors every 1.2 primitive (`tls12_prf_sha256/384`, RSA PKCS1/PSS) — no crypto blocker. api-surface
snapshot +4 public `tls_native::*` fns; compiler binary changes only by the `--version` string.

**Next:** **.73 — TLS 1.2 handshake + PRF key derivation** (produces the 4-byte GCM salt / 12-byte ChaCha
IV this record layer takes as input), then cert + Finished, the 1.2 ciphersuite set, and 1.2 e2e; then
Mini-arc E (consumer wiring + closeout), the near-end Windows repair cluster, and cycle closeout.

## Session close — 2026-06-05 (.71 ship — callptr→real-Win64-callee frame fix (ECALLPTR_PE) + COM vtable dispatch works on real cass)

Closing **v6.0.71** — the v6.0.70 §0 follow-up. check.sh **85/85**; self-host byte-identical on
**x86_64 + aarch64-Linux (pi) + macho-arm (ecb) + macho-x86 (ach) + Windows (cass)** — all 4 cross-OS
hosts green; cass leg now also runs the callptr→real-Win64 regression → 42.

**Headline — `callptr` to a REAL Win64 callee no longer corrupts the caller; calling a COM vtable method
from cyrius works.** v6.0.70's `callptr` was verified only against trivial cyrius callees; the DXGI
demonstrator surfaced that `callptr` to a real Win64 callee (COM method, kernel32 entry) AV'd/corrupted
(issue 2026-06-05-windows-com-vtable-real-callee-frame-corruption.md).

**Root cause:** cyrius's PE call chain runs at a CONSTANT body alignment landing every callee at entry
rsp ≡ 0, NOT the Win64-ABI ≡ 8 (Windows enters the EXE at ≡ 8, cyrius never re-aligns). Harmless for
cyrius's own SSE-free code; the kernel32 IAT reroutes mask it with `and rsp,-16`; but `callptr` invokes
real Win64 callees whose aligned `movaps` SSE spill #GP-faults when misaligned. Found via local
**wine + winedbg** (wine self-hosts the PE compiler byte-identically — isolated the bug deterministically
WITHOUT the GPU) + cass exit-code bisect.

**Fix — `ECALLPTR_PE` (`src/backend/x86/emit.cyr`):** force-16-align the callptr call site with the same
rbx-anchored `and rsp,-16` the reroutes use → callee entered ABI-correct regardless of caller alignment.
Local to callptr (a whole-program entry-seed was tried + **rejected** — it destabilised the top-level-only
`cycc` compiler itself). Plus `GetModuleHandleA`/`GetProcAddress` PE imports (0xF013/0xF014) for resolving
real callee pointers, `tests/win/callptr_real_win64.cyr` (wired into the cass leg), and `lib/dxgi.cyr`.

**Verified on real cass:** regression (callptr → kernel32 `lstrlenA`/`GetModuleHandleA`/`MulDiv`) → 42;
COM `EnumAdapters1` (slot 12) → S_OK; `GetDesc1` (slot 10) → reads `DXGI_ADAPTER_DESC1` (VendorId ≠ 0).
The §0 capability (call a COM vtable from cyrius) WORKS.

**Deferred to next slot (leader-approved split):** on the REAL GPU, `Release`/`AddRef` (1-arg COM) + the
full `dxgi_vram_bytes()` chain still AV. The callptr EMIT for the failing 1-arg-COM case is byte-identical
to the working 1-arg-kernel32 case, and the pre-fix symptom was the INVERSE — a SECOND subtler interaction
the alignment fix doesn't cover, reproducible ONLY on real DXGI hardware (wine has no GPU). **Next: install
windbg/cdb on cass, pin it, finish the VRAM demonstrator.** Issue re-filed with full v6.0.71 status.

**Next:** **.72 — windbg-on-cass: finish the DXGI demonstrator** (the deferred residual), then the
remaining Windows partials (D2 wrapper port / deps-lock / .ps1 installer), then **TLS** Mini-arcs D/E.

## Session close — 2026-06-05 (.70 ship — compiler-emitted indirect calls (callptr/IR_CALL_INDIRECT) = the COM-vtable-call capability §0)

Closing **v6.0.70** — second half of the Windows FFI arc. check.sh **85/85**; self-host byte-identical on
**x86_64 + aarch64-Linux (pi native+cross) + macho-arm (ecb) + macho-x86 (ach) + Windows (cass)**.

**Headline — cyrius can call through a computed function pointer in ordinary source.** `callptr(callee,
args…)` → `IR_CALL_INDIRECT` (x86 `call [rbp-disp]`, aarch64 `ldr x6;blr x6`), NOT lib/fnptr.cyr asm. The
callee is spilled to a FRESH frame slot before the args, so it survives ECALLPOPS (Win64 carves a 32 B
shadow that would bury a stack-pushed callee); the slot is re-entrant (nested callptr → distinct slots)
and handles any arg count. The genuinely hard part was the cross-ABI callee-survival — the design
workflow's "pop callee after ECALLPOPS" was wrong for Win64 (shadow burial), so the frame-slot spill is
the correct general mechanism (leader chose "full"). Paired with the `dxgi.dll!CreateDXGIFactory1` import
(3rd PE DLL via the .69 multi-DLL foundation), .70 delivers BOTH §0 capabilities the COM/DXGI issue named
(non-kernel32 imports + COM vtable dispatch).

**Mechanism:** IR_CALL_INDIRECT=66 (+ the 3 DCE/LASE predicates + CIND opname); x86 ECALLIND `FF /2
call [rbp+disp]`; aarch64 ECALLIND loads the slot into **x6** (x0-x5 are arg regs, x9 is the >6-arg
shuffle scratch) then `blr x6`; cx = loud compile error (no indirect-call op). The callptr builtin (lex
token 111 + PARSE_FACTOR) allocates a fresh frame local per call-site (GFLC/EFLSTORE) — so it needs a fn
frame; **top-level use is a loud compile error** (top-level vars are globals, no rbp frame), not a crash.

**Proof:** callptr.tcyr 7/7 on x86 + pi (0–7 args incl. >6-arg shuffle, callee-from-var, nested
re-entrancy); a callptr exerciser → 42 on cass (Win64) + ecb (macho-arm); loaded-callee (2/3-arg) → 42 on
cass; CreateDXGIFactory1 → S_OK + non-null IDXGIFactory1 on cass (3-DLL PE loads); self-host
byte-identical (cycc uses no callptr); 4-host cross-OS green; check.sh 85/85.

**Deferred to .71 (filed):** the DXGI GPU-enum demonstrator `lib/dxgi.cyr`. callptr to a *real Win64 COM
callee* (EnumAdapters/GetDesc) corrupts the cyrius caller frame on cass — NOT a callptr bug (loaded-callee
+ 3-arg verified; slots + frame-slot allocation ruled out), a subtle real-Win64-callee interaction needing
a Windows debugger to pin. Issue: 2026-06-05-windows-com-vtable-real-callee-frame-corruption.md. The §0
CAPABILITY is shipped + verified; only the DXGI consumer is blocked. Leader: ship .70, demonstrator → .71.

**Next:** **.71 — DXGI demonstrator + the Win64-COM-callee fix** (windbg on cass → fix the callptr call
frame for real Win64 callees → lib/dxgi.cyr `dxgi_vram_bytes()`), then the remaining Windows partials
(D2 wrapper port / deps-lock / .ps1 installer), then **.72+ TLS** Mini-arcs D/E.

## Session close — 2026-06-05 (.69 ship — Windows multi-DLL FFI foundation + full §3 CommandLineToArgvW)

Closing **v6.0.69** — first half of the Windows FFI arc (**.69 = foundation + §3; .70 = indirect-call
codegen + §0 DXGI**, leader-blessed split). check.sh **85/85**; self-host byte-identical on **x86_64 +
aarch64-Linux (pi native+cross) + macho-arm (ecb) + macho-x86 (ach) + Windows (cass)**.

**Headline — the PE backend can import from any DLL now, and Windows argv is full-fidelity.** Two bites:

**Bite 1 — multi-DLL IAT foundation** (`src/backend/pe/emit.cyr`). The PE import machinery was hardcoded
to a single kernel32 descriptor (`imp_dir_size = 20*2`, literal "kernel32.dll", flat IAT where
imp_idx == slot). Generalized to **N DLLs**: each import is tagged with a DLL id; `_pe_layout` groups
imports by DLL into per-descriptor IAT/ILT runs (kernel32=0 first so ExitProcess stays at physical slot 0),
sizes `imp_dir_size = (dll_count+1)*20`, and builds an `imp_idx → physical slot` remap (`_pe_iat_pos` /
`_pe_iat_slot()`) that the ftype=4 fixup (`src/backend/x86/fixup.cyr`) now uses. **Byte-identical to the
old path at one DLL** — proven before adding a second: same compiler, same Windows program → identical
2560-byte PE. This is the foundation both §3 (shell32) and .70's §0 (dxgi) named as their blocker.

**Bite 2 — full §3 `CommandLineToArgvW`.** The first non-kernel32 import: `shell32!CommandLineToArgvW`
(+ `kernel32!LocalFree`), `0xF010`/`0xF011` reroutes → cyrius's **first 2-DLL PE**. `lib/args_win.cyr`
`args_init` now splits the command line with the real shell32 call (correct `\\"`-quote rules) and converts
each wide arg to UTF-8 via the new host-testable `_args_w2u8` (`lib/args.cyr`, surrogate-aware), then frees
the `LPWSTR*` with `LocalFree`. Replaces the v6.0.54 ASCII-only `_args_tokenize_utf16` that dropped each
wide char's high byte (a Unicode install path corrupted silently). New `tests/tcyr/args_win_utf8.tcyr`
(21 assertions) replaces `args_win_tokenize.tcyr`.

**Cross-arch:** `ECMDTOARGV_PE`/`ELOCALFREE_PE` got no-op stubs in `src/backend/aarch64/emit.cyr` (dead
under aarch64/macho, FATAL under `--strict` without them — same cohort as the existing PE-reroute stubs);
cx parity confirmed (identical to ESLEEP_PE).

**Proof:** 2-DLL args program on cass — `argtest a b c`→65 (argc 4), `argtest "hello world"`→43 (argc 2,
quoted arg kept whole, len 11), no-args→16; PE carries both `kernel32.dll`+`shell32.dll`; `_args_w2u8`
21/21 on Linux; check.sh 85/85; 4-host cross-OS self-host green (pi+ecb+ach+cass).

**Next:** **.70 — §0 COM/DXGI** (the second half): new `IR_CALL_INDIRECT` opcode (x86 `FF /2` + aarch64
`blr`, cross-arch same slot) + a call-through-pointer primitive, then `dxgi.dll` import +
`CreateDXGIFactory1 → EnumAdapters1 → GetDesc1 → DedicatedVideoMemory` (64-bit VRAM) — DXGI GPU
enumeration as ordinary cyrius. Then **.71+** Windows wrapper port (D2) / deps-lock / .ps1 installer, then
TLS Mini-arcs D/E.

## Session close — 2026-06-05 (.68 ship — aarch64-Linux native toolchain completion: §D1 deps + native auto-call-main + honest HARD funcgate)

Closing **v6.0.68**. check.sh **85/85**; self-host byte-identical on **x86_64 + aarch64-Linux (pi
native+cross) + macho-arm (ecb) + macho-x86 (ach) + Windows (cass)**; full aarch64 funcgate green.

**Headline — three latent aarch64-Linux bugs killed; the aarch64-native funcgate is now an HONEST HARD
gate.** Registered §D1 (`cyrius deps` silently fails on aarch64-Linux) was the aarch64-Linux ESYSXLAT
missing a CLASS of x86→aarch64 syscall translations the `cbt` wrapper issues as literals:
- **`stat 4 → fstatat 79`** (the §D1 root cause). aarch64 syscall 4 is `io_getevents`; `_file_size`
  (`cbt/deps.cyr`) returned -1 → the deps include-scan short-circuited (`if (sz<=0) return 0`) →
  transitive stdlib peers (`syscalls_aarch64_linux.cyr`, `alloc_*`, `atomic`, …) silently dropped →
  consumers got a broken `lib/`. Ordered AFTER `getcwd 79→17` so the `x8=79` it sets isn't re-caught.
- **`rename 82 → renameat 38`** + **`symlink 88 → symlinkat 36`** (same class, AT_FDCWD arg-shifts).
  `rename` 82 = `fsync` on aarch64 → `cyrius build` never renamed `.tmp.<pid>` to the final binary;
  `symlink` 88 broke `cyrius pulsar`'s install symlinks. Every instruction's hex assembler-verified on pi.

**Two more, unmasked by fixing §D1:**
- **Native auto-call-`main` missing.** The SHIPPED native cycc (`cycc-native-aarch64`, from
  `main_aarch64_native.cyr`) never got the v5.9.37 auto-call-`main` port the cross / macho (v6.0.37) /
  win (v6.0.54) all have → every `cyrius build` on aarch64 using the bare-`fn main()` convention
  silently exited 0 (the funcgate's fib exited 0, not 42). Latent since v6.0.7, masked by §D1's deps
  failure + the soft funcgate. Ported; native self-hosts byte-identical either way (compiler
  `sys_exit`s explicitly, so its own binary is unchanged).
- **The gate was a placebo.** CI `aarch64-native` built/self-hosted/funcgated `cycc_a64` from
  `main_aarch64.cyr` (the CROSS source, which HAD auto-call-main), NOT the shipped
  `main_aarch64_native.cyr` binary → it stayed green while the shipped toolchain was broken (the exact
  "found by ports" pattern). Reworked to build/self-host/funcgate the shipped `cycc_native_a64` and
  made HARD (`continue-on-error` dropped).

**Proof:** full aarch64 funcgate green on pi (init → lib sync → deps [14 transitive files, matching
x86] → build → run=42 → reproducible → hashmap=43); native self-host byte-identical (3-gen, pi); 4-host
cross-OS self-host green (pi + ecb + ach + cass); check.sh 85/85; x86 unaffected (`main.cyr` doesn't
include the aarch64 backend).

**Scope note:** registered as "§D1 deps" but the investigation surfaced the whole shape — deps + build +
pulsar syscalls, the native codegen gap, AND the placebo gate — all blockers to the same goal (an
honest HARD aarch64-native funcgate). Leader confirmed packing all three + the gate fix into .68 (the
"see the whole shape, pack intentionally" discipline).

**Next:** **.69+ partials block** (Windows §3 `CommandLineToArgvW` + §0 COM/DXGI GPU-enum), then
**.70+ TLS** (Mini-arc D backport + E consumer wiring).

## Session close — 2026-06-05 (.67 ship — asm-block param_load(reg, idx) pseudo-op + atomic/thread migration)

Closing **v6.0.67** (the asm-block global-symbol pseudo, split from .66). check.sh **85/85**; self-host
byte-identical on **x86_64 + aarch64 (pi native+cross) + macho-arm (ecb) + macho-x86 (ach) + Windows
(cass)**.

**Headline — `param_load(reg, idx)` decouples inline asm from prologue layout.** Inline asm loads a
parameter from its ACTUAL prologue slot (disp = -(idx+1+_cur_fn_regalloc)*8) instead of hardcoding
`[rbp-N]`/`[x29,#-N]` byte literals that silently break on prologue drift (the recurring sigil AES-NI /
cyrius atomic.cyr coupling bug; issue 2026-05-21). x86 → `mov reg,[rbp+disp]`, aarch64 → `ldur
reg,[x29,#disp]`. Implemented Option 2 (user-chosen); Option 1 `sym32(name)` left as a future general
enhancement. `_asm_{x86,aarch64}_reg` name→encoding maps + ASM_PARAM_LOAD emit in each backend.

**Proof — BYTE-IDENTICAL.** Migrating `lib/atomic.cyr` (atomic_cas/atomic_fetch_add) + `lib/thread.cyr`
(clone arg-marshal) to param_load produced a byte-identical cycc (atomic.cyr is in cycc via the .64
alloc lock) → param_load emits exactly the hand-rolled bytes (and confirms regalloc=0 for those fns).
atomics/threads/thread_safety/thread_local green on x86 + pi; new `param_load.tcyr` 5/5 both arches.

**Bootstrap finding (taken to the leader, who chose to keep the migration):** atomic.cyr/thread.cyr are
bootstrap-critical (in cycc), so migrating them COUPLES them to param_load — a pre-6.0.67 cycc can't
compile them (the smoke gate caught a stale installed cycc). The leader accepted this: consumers get
lib+cycc together via `cyrius deps`, the bootstrap propagates param_load from the current backend (cybs
does NOT compile main.cyr directly — `cat main.cyr | cybs` fails pre-existing, so cybs is not the
main.cyr compiler), and pulsar's self-host chain carries param_load forward. Smoke passes once .67 is
installed. (Feature-only — atomic/thread hand-rolled — was also verified 85/85 as the fallback.)

**Next:** **.68+ partials block** (Windows follow-up nuances §3/§0; aarch64 `cyrius deps` §D1), then
**.69+ TLS**. Consumer follow-up: sigil migrates aes_ni/sha_ni off `[rbp-N]` to param_load (its filing).

## Session close — 2026-06-05 (.66 ship — cbt: `cyrius test` works on Apple Silicon; 2 stacked bugs fixed)

Closing **v6.0.66**. **Leader split (2026-06-05):** the in-flight work was turned into two slots — the
current cbt fixes ship as **.66**; the asm-block `param_load` pseudo slips to **.67**; everything after
slips one (partials → .68+, TLS → .69+). Wrapper-only release (cycc UNCHANGED → self-host carries; the
version-string bump is the only cycc delta).

**Headline — `cyrius test` (and run/bench/fuzz/doctest) now work on arm64 macOS.** Two stacked cbt bugs,
surfaced by the **yantra extensions CI** (macos-15-arm64), each masked the next:
- **Bug 1 (exit 127) — qemu mis-route.** `find_tools()` forces `_arch=AARCH64` on arm64-macOS, so
  `run_binary` took the qemu-aarch64 cross-run branch — but a native Apple-Silicon host has no
  `/usr/bin/qemu-aarch64` → execve-fail → exit 127, zero test output. (ecb had qemu installed, masking it;
  the hosted runner doesn't.) Fix: gate the qemu branch `#ifndef CYRIUS_TARGET_MACOS` → macho execs directly.
- **Bug 2 (exit 137) — unsigned AMFI SIGKILL.** Only `cmd_build` ad-hoc-codesigned (6.0.38);
  test/run/bench/fuzz/doctest compiled to /tmp + ran via `run_binary` unsigned → AMFI SIGKILL. Fix:
  hoisted the codesign into a shared `_macho_codesign()` called inside `run_binary` (cmd_build DRY'd to it).

**Proof:** `cyrius test smoke.tcyr` on ecb → `1 passed, 0 failed` (the 132/SIGILL during diagnosis was a
test-setup artifact — `lib/` includes not resolving in /tmp; the binary RAN, proving past 127/137).

**Process note:** the deeper root-cause (Bug 1, the qemu mis-route = the literal 127) came from the user's
own investigation in the yantra issue — my first pass found only Bug 2 (the codesign asymmetry). Both fixed.

**Next:** **.67 = asm-block `param_load` pseudo** (Option 2; design + exact byte encodings already settled
— x86 disp8 `mov`, aarch64 `ldur`, disp = -(idx+1+_cur_fn_regalloc)*8; byte-identical atomic.cyr migration
as the proof). Then .68+ partials, .69+ TLS.

## Session close — 2026-06-05 (.65 ship — partials/repairs: portable sleep_ms + single-source macho whitelist + ach CI gate)

Closing **v6.0.65** (partials/repairs slate). check.sh **85/85**; self-host byte-identical on **x86_64 +
aarch64-linux (pi native+cross) + macho-arm (ecb) + macho-x86 (ach) + Windows (cass)**.

**Headline — `lib/chrono.cyr` `sleep_ms` is portable.** It called raw `syscall(35)` (Linux nanosleep),
which faults off Linux: Darwin has no plain `nanosleep` BSD syscall (35 there collides with aarch64
`unlinkat`) and PE never routed it. Now: `poll(NULL,0,ms)` on Linux+macOS (poll 7→230 already routed on
both Mach-O backends) + a new kernel32 `Sleep` reroute (0xF00F) on Windows; agnos/cx no-op. Measured
`sleep_ms(500)` ≈ 501/500/503/558 ms on Linux/ecb/ach/cass. **Unblocks yantra's macOS-arm64 iOS CI** —
yantra moves `_yantra_sleep_ms` off raw `syscall(35)`. `lib/regression.cyr` moved off 35 too.

**Single-source Mach-O whitelist (user-chosen over a parallel-list sync).** The parse-time
"syscall-not-routed-on-Mach-O" warning hardcoded `{0,1,2,3,9,10,11,60,228}` while ESYSXLAT routes ~40 —
firing for routed syscalls and hiding the genuinely-unrouted. Replaced with `_macho_arm_routes()`
adjacent to ESYSXLAT (src/backend/aarch64/emit.cyr), queried by parse_expr.cyr — no drift. Warning now
fires only for genuinely-unrouted syscalls. (The naive partial sync was reverted as a half-measure.)

**ach (Achaemenid) x86-macOS CI gate restored** (`ci.yml` `macho-x86-native`) — on the self-hosted
Intel-Mac runner, replacing the scarce/quarantine-flaky GitHub `macos-13` job; fork PRs gated out.
**First CI run finding:** self-host step is GREEN + HARD (authoritative, rot-proof); the consumer
funcgate step is **SOFT on x86-macho** — its first step `cyrius init` no-ops there (the HELD x86-macho
argv/init gap; `cd proj` → No such file or directory), Apple-Intel EOL so it's backlog under higher
priorities. codesign/dlopen-helper warnings on the runner are non-fatal env quirks. dir-walk/consumer
coverage stays HARD on arm64 (ecb). Flip funcgate to HARD once x86-macho argv/init is unheld.

**Process note:** two premise-check findings surfaced + were taken to the user mid-slot: (1) the
whitelist sync was harder than the issue implied (dual number-convention + hex-encoded ESYSXLAT) → user
chose the single-source refactor; (2) the asm-block global-symbol pseudo is a cross-arch FEATURE (the
issue itself suggests a dedicated cycle), not a "small squeeze-in" → **deferred to v6.0.66** (its own slot).

**Issues archived:** `2026-06-04-macos-nanosleep-syscall-35-not-in-esysxlat.md` (resolved) +
`2026-06-03-agnos-followup-after-boot.md` (cyrius-side complete .56). `macos-install-lib-snapshot` held
(its own "await yantra runner confirmation" gate); `ach-selfhosted-runner` stays active until the first
green CI run on the registered runner.

**Next:** v6.0.66 = asm-block global-symbol pseudo (`sym32`/`param_load`, cross-arch + fixup, full
design); then the slate continues (TLS, remaining Windows/macho follow-ups).

## Session close — 2026-06-05 (.64 ship — thread-safe global allocator + 2 latent aarch64 bugs fixed)

Closing **v6.0.64**. check.sh **85/85**; self-host byte-identical on **x86_64 + aarch64-linux
(pi native+cross) + macho-arm (ecb) + Windows (cass)**; self_compile perf neutral (449 vs 451 ms).
The slated **global allocator thread-safety** fix — and two latent aarch64 bugs it exposed.

**The headline — concurrent `alloc()` no longer corrupts the heap.** A consumer's multi-threaded
accept loop was blocked: the bump allocator's `_heap_ptr` read-modify-write + grow were unsynchronized,
so `CLONE_VM`/`CreateThread` threads sharing one heap overlap-allocated (~5000 corruptions / 4 threads).
Fix = recommended option (b): a process-wide CAS spinlock (`_alloc_lock`) serializing
`alloc()`/`alloc_reset()` across **all four** allocator peers + a CAS-publish for the `default_alloc()`
singleton — closing the bump-pointer, grow, and lazy-init races. Spinlock not futex/SRWLOCK because
Darwin + agnos expose no futex. New `alloc_thread_safe.tcyr` **proves it**: fails 5/5 with the lock
removed, passes with it; verified by a 4-thread contended run on **real aarch64 hardware** (pi).

**Two latent aarch64 bugs surfaced + fixed in the same release (one-bug-one-complete-fix):**
- **Missing acquire barrier** (`lib/alloc.cyr`) — `_alloc_lock_acquire` lacked the post-CAS
  `atomic_fence()` that `thread.cyr` `mutex_lock` carries. aarch64's CAS is plain `ldxr/stxr` (no
  ordering), so the critical-section `_heap_ptr` read could hoist before the lock → stale bump pointer.
- **Globals only 4-byte aligned** (`src/backend/aarch64/fixup.cyr`, user-chosen root-cause fix) — the
  aarch64 ELF var-area base inherited the code size's 4-alignment (x86 rounds code to 8; aarch64 to 4).
  `atomic_cas` on a *global* uses `ldxr/stxr`, which **SIGBUS on a non-8-aligned address**, so
  atomic-on-a-global faulted (caught by the native-pi self-host gate). One-line fix: round code size to
  8 — now **atomic-on-any-global works on aarch64**, matching x86. `build/cycc_aarch64` +
  `cycc-native-aarch64` regenerated with the fix (`cyrius pulsar`).

**Process note:** the adversarial review caught the acquire-barrier bug; check.sh's pi gates caught the
SIGBUS — both before ship. "Run it on the hardware, never trust a checkmark" held again (x86 was green
throughout; only real aarch64 exposed both).

**Issues archived:** `2026-06-04-cyrius-global-allocator-not-thread-safe.md` (resolved) +
`2026-06-03-windows-pe-syscall-surface-blocks-detection.md` (core resolved .50–.52, downstream done).

**Next:** the slate resumes (partials, then TLS); macho/platform syscall-coverage cluster (the tracked
§D4 nanosleep + aarch64 `cyrius deps` §D1) at the next macho/platform slot.

## Session close — 2026-06-04 (.63 ship — real-flow functional gate + arm64 macOS dir-walk fix)

Closing **v6.0.63**. check.sh **85/85**; self-host byte-identical on **x86_64 + aarch64-linux (qemu) +
macho-arm (ecb)** (906,528 B x86). The slate was redirected (user): .63 became the functional-gate arc
+ the macOS dir-walk fix (global-allocator thread-safety + partials slide).

**The headline — arm64 macOS dir-walk repaired (`src/backend/aarch64/emit.cyr`).** The prior
"arm64 arg-corruption codegen bug" diagnosis was WRONG (disproved by bisection on ecb). Root cause:
`SYS_GETDENTS64` is multiply-defined — `217` (x86/macos) but **`61`** (`syscalls_aarch64_linux.cyr`) —
and the wrapper binds `61` by include order (`fs.cyr` then `syscalls.cyr`, last wins). The .60 macho
ESYSXLAT translated only the x86 `217→344` and **missed the aarch64 `61→344`**, so untranslated `61`
ran with a stale `x16` → EBADF and `lib sync` reported "snapshot lib not found" on a dir that exists.
Fix: one entry, `cmp x8,#61; b.ne; movz x16,#344` (llvm-mc-verified). A standalone probe bound `217`
and worked, masking it — **the wrapper, not a probe, is the test.** Full consumer flow GREEN on ecb.

**Shipped:**
- **Real consumer-flow functional gate** — `scripts/funcgate-posix.sh` (Linux/macOS) + `funcgate-win.ps1`
  (Windows codegen) + `funcgate-stage.sh`. init → lib sync (dir-walk) → deps → build+run a vec-fib AND a
  u64-hashmap → reproducible. Wired into CI: `test` **HARD**, `test-agnos` + `aarch64-native` tracking,
  `windows-native` **HARD**, folded into `macho-arm64-native` **HARD**. Hardware-verified pi/ecb/cass.
  Closes the self-host "found-by-ports" blind spot (self-host never walks a dir).
- **Funcgate reproducibility fix** — was comparing two different output names; Mach-O embeds the output
  basename, so they always differed. Now rebuilds the SAME name + hashes unsigned (codesign non-det).
- **`cyrlint --strict-deferrals`** — flags deferred/broken-work markers not cross-referenced by a
  CHANGELOG/issue/roadmap pointer (185-item backlog reported, non-failing by default).
- `lib/tls_native.cyr` header reconciled to truth; findings register
  (`2026-06-04-shipped-broken-functionality-found-by-consumers.md`).

**Tracked / still-open (gate did its job):** §D1 **`cyrius deps` silently fails on aarch64 Linux**
(rc=9, empty stderr, wipes `lib/`) — blocks `aarch64-native` from HARD until fixed. §D2 **cyrius wrapper
not ported to Windows** (fork/execve/mkdir/… undefined for PE) — bigger arc. §D4 **arm64 macOS
`nanosleep` (35) not in ESYSXLAT** (`2026-06-04-macos-nanosleep-syscall-35-not-in-esysxlat.md`; surfaced
once .63's lib-sync fix let yantra's e2e reach runtime) + the stale `parse_expr.cyr` warning-whitelist —
pinned to the next macho/platform slot (roadmap partials block).

**Next:** fix §D1 (aarch64 deps) so `aarch64-native` can join macho+Windows as a HARD gate; then the
slate resumes (global-allocator thread-safety, partials, TLS).

## Session close — 2026-06-04 (.62 ship — QoL/language smalls + macOS install hotfix)

Closing **v6.0.62** — the first .62-slate slot (QoL/language smalls), with an urgent macOS install
hotfix folded in. check.sh **85/85**; self-host byte-identical (906,528 B); **cross-OS `SELFHOST_OK`
on ALL FOUR** (cass + pi + ecb + ach).

**Shipped (4 items — premise-checked at slot entry):**
- **Octal literals `0o755`** (`lex.cyr` LEXOCT, base-8, underscores) — self-host-critical bite, landed
  last + isolated; byte-identical self-host (octal inert for compiler sources); `octal_literals.tcyr`
  10/10; cross-OS green.
- **`cyrius tests [dir]`** plural recursive suite runner (cbt) — `cyrius test` single/auto-discover
  unchanged; verified finds nested `.tcyr`.
- **TOML `[section]` single-bracket** (`lib/toml.cyr`) — unblocks commandress; `toml.tcyr` 31/31.
- **macOS install hotfix** (`scripts/install.sh`) — the download-path stdlib copy used the whole-dir
  `cp -r` form, which returns 0 but leaves `versions/<v>/lib` MISSING on the GitHub `macos-15-arm64`
  runner (yantra CI red on 6.0.59+; `lib sync` → "snapshot lib not found"). NOT reproducible on ecb
  (runner-image cp quirk); the **bin** copy worked because it used the contents form. Fixed to
  contents-into-premade-dir (`mkdir -p` + `cp -R src/lib/.`) + **fail-loud assert** + `else err` for a
  no-lib tarball; same for templates. Regression-safe on ecb. Issue
  2026-06-04-macos-install-lib-snapshot-missing-breaks-lib-sync.md — FIXED cyrius-side, pending
  runner confirmation on 6.0.62 (yantra's backfill keeps CI green meanwhile; not archived yet).

**Dropped/deferred:** `cyrius hooks` already shipped @ v6.0.36 (premise-check caught it). POSIX `*at()`
pulled to its own slot (not a "small"). **Deferred to a post-cut doc pass (user direction):** vidya
octal `language` entry + roadmap reconciliation (.62 shipped / hooks-done / `*at` pulled).

**Next (slate [[project_v6_0_x_remaining_slot_plan]]):** .63 = global allocator thread-safety
(2026-06-04-cyrius-global-allocator-not-thread-safe). Then .64-66 partials, .67-x TLS, .x windows
fixes, cleanup-refactor cluster, closeout → v6.1.0.

## Session close — 2026-06-04 (.61 ship — real Windows threading + thread-local storage)

Closing **v6.0.61** — third of the pinned macOS/Windows hardening slate (the Windows nuances item).
check.sh **85/85**; self-host byte-identical (905,856 B); **cross-OS `SELFHOST_OK` on ALL FOUR**
(cass + pi + ecb + ach). Replaces the v6.0.53 serial fallback with real preemptive threads, SRWLOCK
mutexes, and real per-thread TLS — 8 new kernel32 reroutes (0xF007-0xF00E).

**Shipped (2 stages):**
- **Stage 1 — real threads + SRWLOCK mutexes (`lib/thread_win.cyr`).** thread_create → CreateThread
  (0xF007); thread_join → WaitForSingleObject (0xF001) + CloseHandle (3). The cyrius body fn is a
  valid MS-x64 ThreadProc directly (PE arg0==RCX==lpParameter) — NO trampoline; 6 params via struct
  ptr (ECREATEPROC_PE pattern). mutex_* → InitializeSRWLock/Acquire/ReleaseSRWLockExclusive
  (0xF008-0xF00A). Channels became SRWLOCK-protected rings. **cass-verified:** 4 threads × 100000
  under a mutex → exactly 400000; the same workload WITHOUT the mutex → lost updates (<400000),
  proving real parallelism (not the serial fallback).
- **Stage 2 — real per-thread TLS + gettid (`lib/thread_local.cyr`).** thread_local_init/get/set key
  off one TlsAlloc'd (0xF00C) TEB index; each thread installs its own 128-byte block via TlsSetValue
  (0xF00E) / TlsGetValue (0xF00D). gettid → GetCurrentThreadId (0xF00B). **cass-verified:** 4 threads
  each read back their own slot-0 value after interleaving + report nonzero, distinct-from-main tids.

**The bug found on hardware:** SRWLOCK's CONTENDED path builds a stack wait-block needing 16-aligned
ops → the bare `sub rsp,0x28` reroute faulted (0xC0000005) only when ≥2 real threads contended
(single-thread + 1-worker ran fine; 4 contending crashed). Fix = the rbx-anchored 16-align (the
ECREATEPROC_PE/CreateProcessW SSE pattern), applied to all 3 SRWLOCK + 4 TLS reroutes. The "run it on
the hardware, never trust a checkmark" principle again — a Linux build is blind to this.

x86-macho UNTOUCHED this slot. The bump allocator stays non-thread-safe (thread bodies pass
pre-alloc'd buffers via the arg); a blocking chan_recv (condvar) is future.

**Next (slate [[project_macos_windows_platform_hardening_first]]):** remaining Windows nuances — full
CommandLineToArgvW (2026-06-03-windows-followup-nuances.md) + COM/DXGI GPU-enum
(2026-06-03-windows-pe-com-vtable-dxgi-for-gpu-enum.md, the heavier deferred item). macOS cluster is
essentially clear (x86-macho argv reserved-reg remains, HELD — Intel EOL).

## Session close — 2026-06-04 (.60 ship — macOS getdirentries port + cyrius init sovereign-binary scaffolding)

Closing **v6.0.60** — second of the pinned macOS hardening slate. check.sh **85/85**; self-host
byte-identical (897,960 B); **cross-OS `SELFHOST_OK` on ALL FOUR** (ecb + ach + pi + cass).

**Fixed:**
- **`lib/fs.cyr` dir enumeration → Darwin getdirentries64.** getdents64 (217) → getdirentries64 (344)
  in both Mach-O backends (ESYSXLAT arm64 + EMACHO x86); fs.cyr passes the 4th `basep` out-param
  (Linux ignores it — the prior EFAULT was the missing basep). Darwin dirent layout dumped
  empirically on ecb: d_type@20 / name@21 (vs Linux 18/19), reclen@16 same. is_dir buffer 32→4096
  (32 too small for Darwin getdirentries64 → misreported dirs as non-dirs). Fixes `lib sync` /
  `cyrius update` / any dir-walk on macOS. Verified on ecb (dir_list enumerates, is_dir dir=1/file=0).
- **`cyrius init` scaffolds via the BINARY on installs** (finished the dev-mode-only v5.9.29 path).
  cyrius-init resolves its real path on macOS via `open(argv0)+fcntl(F_GETPATH)` (argv0 = unresolved
  `~/.cyrius/bin` symlink → root `~/.cyrius` w/o templates; F_GETPATH → `versions/<v>/bin` → versioned
  root w/ templates+VERSION). macOS tarballs bundle `programs/cyrius-init-templates/`; install.sh
  (tarball + refresh-only) lands them at `versions/<v>/programs/`. Verified on ecb: `cyrius init
  <name>` scaffolds a full project (cyrius.cyml + src/main.cyr + docs/tests/...) via the program.

x86-macho parity in (getdents64 EMACHO + cyrius-init F_GETPATH) but unverified — x86 held (Intel EOL).
Issues archived: getdirentries; wrapper-commands (init/port/repl/lib-sync all resolved; the x86 argv
item → the x86-release issue, held).

**Next (slate [[project_macos_windows_platform_hardening_first]]):** .61 = Windows nuances (threading
→ thread_local TLS → CommandLineToArgvW → COM/DXGI). Then the macOS cluster is essentially clear
(x86-macho argv reserved-reg remains, held).

## Session close — 2026-06-04 (.59 ship — lib/net.cyr Darwin socket port: unblocks yantra + sandhi HTTP on Apple Silicon)

Closing **v6.0.59** — first of the pinned macOS hardening slate. check.sh **85/85**; self-host
byte-identical (897,928 B); **cross-OS `SELFHOST_OK` on ALL FOUR** (ecb + ach + pi + cass).

**Fixed — `lib/net.cyr` ported to Darwin BSD socket ABI.** Was Linux-hardcoded (socket nums +
sockaddr + sockopt), so ALL TCP/UDP failed on macOS: `socket()` returned a garbage fd, `connect()`
→ EBADF. Surfaced by yantra M4 on ecb.
- Socket syscall nums → BSD via BOTH Mach-O backends: ESYSXLAT (arm64) + EMACHO_SYSXLAT (x86) —
  socket 41→97, connect 42→98, accept 43→30, bind 49→104, listen 50→106, setsockopt 54→105,
  getsockopt 55→118, shutdown 48→134, poll 7→230 (aarch64 cmp/b.ne/movz encodings llvm-mc-verified).
- BSD `sockaddr_in` (sin_len/sin_family byte pair); Darwin `SO_*`/`SOL_SOCKET=0xFFFF`/`O_NONBLOCK`/
  `EINPROGRESS` constants (SOL_SOCKET=0xFFFF was NOT in the issue's hardware deltas — caught +
  confirmed on ecb via setsockopt); 32-bit `timeval` for SO_RCVTIMEO.
- **Verified on ecb (arm64):** client (socket+setsockopt+connect) AND server (socket/bind/listen/
  accept/connect/fork/send/recv) both round-trip exit 42. Issue archived.

x86-macho parity (EMACHO socket entries) added for cross-arch consistency but unverified — x86 HELD
(Apple Intel EOL).

**Next (pinned slate [[project_macos_windows_platform_hardening_first]]):** .60 = getdirentries +
`cyrius init` scaffolding; .61 = Windows nuances. x86-macho argv reserved-reg HELD.

## Session close — 2026-06-04 (.58 ship — macOS fixes & repairs: x86-macho self-host completion + wrapper-command packaging)

Closing **v6.0.58** — macOS-focused fixes and repairs from on-hardware use (ecb arm64 / ach Intel).
check.sh **85/85**; self-host byte-identical (897,672 B); **cross-OS `SELFHOST_OK` on ALL FOUR —
ecb (arm64-macho) + ach (x86-macho) + pi (aarch64-Linux) + cass (Windows)**.

**Fixed:**
- **x86-macho stdlib syscall peer (`syscalls_macos.cyr`) completed** — was numbers-only (tools/wrapper
  compiled to `ud2`); rewritten as a real peer (Linux nums + EMACHO_SYSXLAT + shared common wrappers +
  x86 peer wrappers + Darwin O_*/mmap/stat@72). cycc + file-I/O + stat + heap-alloc verified on ach.
- **macOS fork/pipe multi-return ABI fixup (x86)** — EMACHO_SYSXLAT fork 57→2 / dup2 33→90 / pipe
  22→42 + new EMACHO_PROC_FIXUP (fork: child rax←0 when rdx==1; pipe: fd0:fd1→`*fds`), the x86 analog
  of the aarch64 .34 x1-fixup. fork/dup2/execve/wait4 verified on ach (WEXITSTATUS=7).
- **macOS `cyrius port`/`repl` "script not found"** — tarballs never bundled the cyrius-init binary +
  the cyrius-{init,port,repl}.sh shims; both builders now ship them. Verified on ecb.
- **macOS wrapper env/arch (`cbt/core.cyr`)** — `find_tools` forced `_arch=AARCH64` on all macOS → x86
  picked the absent cycc_aarch64; now gated on CYRIUS_ARCH_AARCH64. `_macho_fill_environ` x86 reads
  envp off the LC_UNIXTHREAD init stack (was x28-only → 0 on x86).

**Added:** `scripts/build-macos-x86-tarball.sh` (the x86 tarball single-source-of-truth); x86-macho
argv/env capture foundation (`args_macos.cyr` `_macho_capture_args`, stack model — works for simple
programs).

**Tracked (Darwin-surface gaps — filed, NOT fixed this slot):** `cyrius init` scaffolding
(`/proc/self/exe` + templates unbundled + VERSION), `lib sync` + dir-listing (getdirentries), `lib/net.cyr`
sockets (Linux nums unported — surfaced by yantra M4 on ecb), x86-macho full tools/wrapper argv (where
`var r = main()` runs main inside EMIT_GVAR_INITS — needs a reserved register like arm64 x28).

**Next:** the tracked macOS Darwin-surface ports (getdirentries, net sockets, x86 argv reserved-reg,
init scaffolding) — then agnos follow-ups → TLS → Windows nuances ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.57 ship — bug line: >16-arg ECALLPOPS param scramble fixed x86+aarch64 + macOS arena dedup)

Closing **v6.0.57** — first bug-line slot of the re-pivoted order (bug line → agnos → TLS → Windows).
A 6-agent premise-check of the open bug issues found ONE live correctness bug; the rest were already
fixed incidentally (archived). check.sh **85/85**; self-host byte-identical (896,480 B); **cross-OS
cass + pi + ecb `SELFHOST_OK`**.

**Fixed — the cc5-18-arg `ECALLPOPS` >16-arg param scramble (silent miscompile), TWO root causes,
cross-arch:**
- **x86 (1) disp8 overflow:** the reg-arg loads + extras shuttle emitted a signed-disp8 stack
  displacement; at 17 args `(n-1)*8=128>127` wrapped negative → garbage. New `_emov_rsp_disp` helper
  auto-selects disp32 (byte-identical for ≤16-arg, so small calls unchanged). **(2) shuttle
  read-after-write:** step-2 wrote `[rsp+48+si*8]` which iteration `si+6` re-read → middle args
  (7-12) scrambled at n>12. Now descending.
- **aarch64 parallel bug:** ECALLPOPS was hardcoded to ≤4 extras (≤10 args) via x9-x12 pop/push.
  Rewritten to the same memory-shuffle (ELDR_SP/ESTR_SP + add sp) — matches old behavior for ≤4
  extras, extends to any count. **cx FLAGGED** (bytecode arg-reg count — niche, nothing blocked).
- **Verified:** 18-arg per-arg verifier all-correct on x86 (native) + aarch64 (qemu-aarch64); self-host
  byte-identical; cross-OS green.
- **macОS `alloc_macos.cyr` arena_* duplicate-fn dedup** — 5 dups of alloc.cyr's un-gated arena_*
  removed (5 warnings/macOS build → 0 on ecb). api-surface non-breaking (the 5 `alloc_macos::arena_*`
  drop, all still under `alloc::`; 3880).

**Archived (premise-check found stale/resolved):** bote nested-call leak (v5.11.18), derive-cap
(v6.0.53), + the 2 fixed-this-slot. **asm-block `sym32`/`param_load` → roadmap** (feature, nothing
blocked).

**Bug line continues:** macОS platform gaps (deps-pin / getdirentries / x86-release — real Darwin
BSD-ABI port work, bigger) + ach-selfhosted-runner (CI) + yeo TS→JS (feature). Then agnos follow-ups →
TLS → Windows nuances ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.56 ship — the REST of the agnos follow-up: exec arc + W* + chrono + syscall(60); + deferred-work tracking)

Closing **v6.0.56** — everything carved out of .55, done in one slot (user: stop hitting agnos walls
release-after-release; "don't hide the deferred"). check.sh **85/85**; self-host byte-identical
(896,592 B); **cross-OS cass + ecb + pi `SELFHOST_OK`**. All lib-only except version_str → cycc
unchanged-behavior.

**Shipped:**
- **agnos process `exec` (`lib/process_agnos.cyr`)** — agnos has no fork/exec/dup2; spawns an in-memory
  ELF: read ELF → `sys_spawn(elf,size)` → `sys_waitpid`→exit_code DIRECTLY. Full process surface (run/
  run_capture/spawn/wait_pid/exec_vec/exec_capture/exec_env + _str family + exec_cmd/getpid/getppid)
  over that model; process.cyr dispatches under `#ifdef AGNOS` + excludes the POSIX block (nested
  `#ifndef`). Unblocks agnsh's `run`. **2 agnos ABI limits (flag-back, not cyrius gaps):** sys_spawn
  takes no argv (args not passed), sys_dup is a stub (no capture redirect → output to terminal).
- **agnos `W*` wait macros** (peer) — trivial (waitpid returns the code directly).
- **chrono agnos branches** — fixed-zero epoch (228/35 are out of 0-33) + no-op sleep.
- **`syscall(60)` normalization** — vec/hashmap/tagged abort paths used Linux exit_group (invalid on
  agnos → no-op that lets a fatal path keep running); now a per-file target-aware `_die()` (agnos
  syscall(0,1)). Kept raw (these stay syscalls.cyr-free). Behavior-identical off agnos.
- **sandhi 1.3.4 → 1.4.1** fold (byte-identical; non-breaking). api-surface +25 → 3885 (process_agnos
  exec surface + W* + sandhi), 0 removals.

**Process correction this slot (user, justified annoyance):** I'd been carving out work into report
prose ("separate arc / future work") without a tracked home — "agnos follow up work went where?" Fixed:
the agnos remainder → **2026-06-03-agnos-followup-after-boot.md** (sys_spawn argv + stdout-redirect =
agnos kernel-ABI additions), the resolved args+io issue archived. Same for Windows →
**2026-06-03-windows-followup-nuances.md** (real threads, thread_local TLS, full CommandLineToArgvW,
and the user's flagged COM/DXGI GPU-enum wrinkle = 2026-06-03-windows-pe-com-vtable-dxgi-for-gpu-enum.md,
AFTER the heavier items); resolved windows-args issue archived. Pinned
[[feedback_file_deferred_work_dont_hide_in_prose]].

**The on-hardware proof (consumer step):** agnsh `run`-on-agnos via agnoshi `cyrius update` + OVMF/ext2.
cyrius side ready.

**Next — slate RE-PIVOTED (user 2026-06-03 at .56 ship): bug line → agnos follow-ups → TLS → Windows
nuances, in that order.** (1) **Bug line** = the open correctness bugs in docs/development/issues/
(cc5-18-arg param scramble, bote nested-call state leak, asm-block global-symbol, macos-alloc-arena
duplicate-fns, …) — premise-check each at entry (these pins are old, may be stale). (2) **agnos
follow-ups** = 2026-06-03-agnos-followup-after-boot.md remainder (sys_stat consumer guard + any new
walls; the kernel-ABI items are agnos-side). (3) **TLS** resumes ([[project_native_tls_arc_v6_2_x]]).
(4) **Windows nuances** = 2026-06-03-windows-followup-nuances.md (threading → thread_local TLS → full
CommandLineToArgvW → COM/DXGI GPU-enum). TS→JS (yeo) folds into the bug line or QoL as it fits.

## Session close — 2026-06-03 (.55 ship — agnos boot-to-prompt: CYRIUS_TARGET_AGNOS stdlib args + io gap closed)

Closing **v6.0.55** — the cyrius side of the agnos boot-to-prompt milestone. `agnsh` built with
`cyrius build --agnos` was `#UD`-ing at `args_init()` on startup (no agnos branch → cycc's `ud2`
sentinel); now it gets its command line + correct-ABI file ops. check.sh **85/85**; self-host
byte-identical (896,592 B); **cross-OS self-host byte-identical on cass + ecb + pi** (the bite-1 emit
change is in the self-host driver); the init-stack capture verified on a real SysV stack (agnos's
format == Linux's: an `--agnos` test ran on Linux → argc/argv correct).

**Shipped (5 bites, exec carved out):**
- **agnos command-line args** — two parts. (1) **emit-side init-`rsp` capture (`src/main.cyr`):** on
  the km==0 agnos path nothing moves rsp between e_entry and the auto-call to main, so the epilogue
  emits `call _agnos_capture_rsp` (mirroring the EFI efi_main forward-call) while rsp = the kernel's
  init rsp; gated `_TARGET_AGNOS` → emits nothing elsewhere (self-host byte-identical). (2)
  **`lib/args_agnos.cyr`:** `_agnos_capture_rsp` records init rsp (= rbp+16) into `_agnos_init_rsp`;
  `argc`/`argv` read argc/argv from there (the agnos kernel builds a SysV init stack: [rsp]=argc,
  [rsp+8+i*8]=argv[i]). Same shape as args_macos.cyr's x28 read. Decisive design point: x86 `#regalloc`
  uses r14/r15, so a callee-saved reg (the macOS-x28 trick) is unsafe → a reserved global is required.
- **`sys_chmod` no-op** (syscalls_x86_64_agnos.cyr) — agnos has no chmod in the frozen 0-33 surface.
- **`lib/io.cyr` AO_* bridge (silent miscompile fix)** — agnos `sys_open` is `(name, namelen, ao_flags)`
  with different `AO_*` bits, so the Linux `(path, O_flags, mode)` shape silently miscompiled (no
  `ud2`). `file_open` now computes namelen + maps O_*→AO_*; the `_r` opens funnel through it. `getenv`
  degrades to 0 (no /proc) for free.
- **api-surface +4 non-breaking** (`args_agnos::{argc,args_init,argv}` + `sys_chmod`, 0 removals → 3860).

**Left as a SEPARATE arc (not boot-to-prompt):** agnos process `exec` — `sys_fork`/`sys_execve`/
`sys_dup2` + the `W*` wait macros (the `sys_spawn(elf,size)` model). agnsh's `run <external>` stays its
own future work; after .55 those are agnsh's only remaining `--agnos` undefineds, so it boots to a
prompt. Carve-outs still open: chrono fixed-epoch, sys_stat sudo-path (consumer-side guard), raw
`syscall(60)` aborts.

**The on-hardware proof (consumer step, like .54's wheel):** agnsh boots to a prompt on agnos — needs
agnoshi to `cyrius update` (re-vendor the .55 lib; cyrius did NOT touch agnoshi/lib) + the agnos
OVMF/ext2 boot smoke. The cyrius side is ready.

**Next = v6.0.56 (stdlib `*at`-family + fsync/fdatasync)** per the slate; then .57 cc5-18-arg + QoL,
.58 TS→JS, **TLS resumes at .59** ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.54 ship — Windows command-line args: GetCommandLineW + args_win.cyr + WIN thread_local + cycc_win main-rooting fix; LAST windows arc item)

Closing **v6.0.54** — the last of the Windows arc (command-line argument support), fully unblocking
ai-hwaccel's win_amd64 wheel. check.sh **85/85**; self-host byte-identical (896,288 B); **cross-OS
self-host byte-identical on cass + ecb + pi (real hardware)**; real-cass runtime verified
(`argc a b c`→4, thread_local slots 0/15/7→0, `cycc_win --version`→6.0.54, `fn main(){return 42}`→42).

**Shipped (5 bites + sigil fold):**
- **GetCommandLineW `0xF006` reroute** (EGETCMDLINE_PE x86-emit + `_pe_ensure_getcmdline` scaffold +
  parse_expr dispatch + aarch64 stub) + **`lib/args_win.cyr`** — `args_init`/`argc`/`argv` via
  GetCommandLineW; the shared pure `_args_tokenize_utf16` (UTF-16→NUL-joined blob, quote-aware, ASCII)
  is unit-tested 22/22 on Linux, so argc/argv reuse the Linux logic verbatim. Last undefined fns in
  ai-hwaccel's WIN closure.
- **`lib/thread_local.cyr` WIN branch** — the arch-asm body had NO OS guard (→ `arch_prctl(158)`/`fs:[]`
  → SIGILL on WIN); wrapped `#ifndef WIN` + a global 16-slot array (serial thread_win →
  thread-local≡global; upgrade caveat tied to the windows-threading issue). Unblocks sigil 3.6.x's
  crypto-bank on Windows.
- **cycc's own Windows `--version`/`--strict`** (main_win.cyr GetCommandLineW token walk — the
  v5.5.x-queued replacement).
- **PACKED: the .23 aarch64 PE-stub debt** (ECREATEDIR_PE/EDELETEF_PE — aarch64 cross now fully
  `--strict`-clean, symmetric with x86 at 15 `_PE` defs) **+ the cycc_win main-rooting fix** — FOUND on
  real cass: native cycc_win lacked main.cyr's v5.9.37 exempt-`main`-from-DCE + auto-call-main, so
  `fn main(){...}` programs were DCE-stubbed (`xor eax,eax;ret`) → wrong exit (`0x40001040`, not 42).
  Ported both to main_win.cyr + added a **cass `fn main(){return 42}` exit-code regression gate** to
  cross-os-selfhost.sh (the byte-identity `fc /b` never caught it). Pre-existing (~.45); ai-hwaccel
  unaffected (its wheel cross-builds via main.cyr, which is correct).
- **sigil 3.6.0 → 3.6.4 fold** (byte-identical to sigil/dist; +26 public `bn_*` constant-time bignum +
  TLS 1.2 PRF fns, **0 removals**; api-surface 3830 → 3856). sigil's `# Requires: lib/thread_local.cyr`
  now satisfied on WIN; sigil README got a mabda-style opt-in note.

**Verification depth:** an adversarial review (20 agents — 5 dimensions + a refute pass) returned "safe
to ship" and surfaced 4 P2 + 2 P3, all folded (empty-quoted-arg preserved, non-ASCII NUL-injection
guard, driver `--version` walk double-NUL termination, blob cap 32768→65536, two comment fixes). It
also corrected a mental-model error now pinned: a **GLOBAL `var x[N]` reserves N i64 slots (N*8 bytes)
— the byte-sizing gotcha is LOCAL-only** ([[feedback_var_array_byte_sized]]). **Gate hardening:**
`cross-os-selfhost.sh` SSHO now sets `RemoteCommand=none`/`RequestTTY=no` (robust against a host's
`~/.ssh/config` RemoteCommand directive — ecb's test setup had broken the gate with exit 255).

**ai-hwaccel:** pin bump + its Windows patch work = USER-handled in parallel (the cyrius side is ready).

**Next = v6.0.55 (the agnos CYRIUS_TARGET_AGNOS stdlib args+io gap)** per the slate; then .56 *at+fsync,
.57 cc5-18-arg + QoL, .58 TS→JS, **TLS resumes at .59** ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.53 ship — Windows threading (serial) + #derive cap 64→512, PACKED)

Closing **v6.0.53** — two packed items (user "pack windows thread and cap together as .53").
check.sh **85/85**; self-host byte-identical on Linux + ecb + cass + pi (895,240 B; cycc changed via
the lex_pp.cyr cap relocation → cross-OS re-verified). **Windows threading runs on cass: THREAD-OK.**

**Shipped:**
- **lib/thread_win.cyr — Windows threading/mutex (serial-fallback).** thread.cyr's Linux body
  (SYS_CLONE/CLONE_*/futex hand-asm) can't parse under CYRIUS_TARGET_WIN → guarded `#ifndef WIN`,
  thread_win.cyr included `#ifdef WIN` (process.cyr→process_win.cyr pattern). thread_create runs the
  fn inline via fncall1 (serial), mutexes are single-threaded no-ops; full public surface matched.
  cass-verified: thread_create+mutex+join → THREAD-OK (fncall1 calls a cyrius fn ptr under MS-x64,
  per the EFI/gnoboot precedent). Real CreateThread/SRWLOCK = future upgrade.
- **#derive cap 64 → 512** (heap surgery). The 64-#derive cap — NOT the 256→1024 type-table cap a
  prior agent MISDIAGNOSED + "fixed" — was libro's real -D LIBRO_TPM blocker (66 derives: 27 libro +
  39 agnosys). sizes[]/names[] were butted against the 0x197F00 metadata → relocated into the free
  tok_types scratch band (sizes[512]@0x198000, names[512*32]@0x199000; 512 chosen generously, won't
  revisit). Boundary verified 512 ok / 513 fails. ADR-003 updated (the scratch regions were
  undocumented). libro can drop its hand-written-accessor workaround.

**ai-hwaccel:** cross-builds for Windows past the threading wall; **the LAST remaining gap is
args.cyr's CYRIUS_TARGET_WIN branch** (GetCommandLineW) — slotted separately
(docs/development/issues/2026-06-03-windows-args-stdlib-gap.md, user "slot args separately"). Wheel
stays gated until then; ai-hwaccel pin unchanged.

**Also folded into .53 before the tag (user-directed):** sakshi 2.2.4→2.2.6 + sigil 3.5.9→3.6.0
(byte-identical to dists; check.sh sakshi/sigil green; sigil purely additive — no removals). The
sigil fold (610 KB dist) surfaced + fixed a latent api-surface bug: the per-file read buffer was
256 KB → truncated sigil mid-file → false "9 removed"; hoisted out of the scan loop + raised to 2 MB,
and the snapshot corrected 2789 → 3824 publics (the tool had silently hidden ~1035 fns across the
>256 KB libs). cycc UNCHANGED by the folds/tool-fix → self-host + cross-OS carry over; check.sh 85/85.

**Next = v6.0.54 (the LAST Windows-arc items: lib/args.cyr CYRIUS_TARGET_WIN branch [GetCommandLineW
→ argv] + WIN thread_local for sigil 3.6.0)** per the reordered slate (user 2026-06-03: ".54 the last
of the windows arc items then .55 can be agnos"); fully unblocks ai-hwaccel's win_amd64 wheel. Then
.55 agnos CYRIUS_TARGET_AGNOS args+io gap, .56 *at+fsync, .57 cc5-18-arg + QoL, .58 TS→JS, **TLS
resumes at .59** ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.52 ship — `cyrius build --win` + PROT_READ cross-target fix)

Closing **v6.0.52**. Scoped as the ai-hwaccel wheel smoke (carry from .51); GREW into a cyrius
release when the smoke surfaced real gaps. check.sh **85/85**; self-host byte-identical on Linux +
ecb + cass + pi (cycc UNCHANGED this release — cbt + lib/thread + lib/freelist only; version_str is
the sole src/ delta, so the bump's cycc is a clean fixpoint; 895,240 B).

**Shipped:**
- **`cyrius build --win`** — Linux→Windows cross-build flag (cbt/{core,cyrius,build}.cyr; injects
  CYRIUS_TARGET_WIN into cycc's envp, mirrors --agnos). Fills the cross-build gap — cycc_win runs
  only ON Windows, wheels.yml's win job built native-only. Verified: `cyrius build --win` → PE32+.
- **PROT_READ cross-target fix** — lib/thread.cyr + lib/freelist.cyr free-rode on alloc.cyr's Linux
  closure transitively pulling mmap.cyr; now they `include "lib/mmap.cyr"` explicitly. Broke every
  Windows cross-build that pulled thread/freelist. **.50's green win gate MASKED it** (win_emit_probe
  pulls only syscalls+alloc — the too-small-probe placebo, macOS-rot class).

**ai-hwaccel:** compiles clean native against 6.0.51 (0 warn); spawn path (exec_capture →
CreateProcessW) proven on cass (.51); **pin UNCHANGED at 6.0.47 — the win_amd64 wheel is NOT fully
unblocked** (the next blocker below).

**The remaining blocker, SLOTTED SEPARATELY (user "ship .52 now, slot threading separately"):**
lib/thread.cyr is Linux-only (SYS_CLONE/CLONE_*/futex); ai-hwaccel uses threads (async_detect) +
mutexes (lazy/cache, every run) → needs a Windows threading/mutex stdlib (guard thread.cyr +
thread_win.cyr, like process.cyr→.51; real CreateThread/SRWLOCK or serial-fallback). Issue
docs/development/issues/2026-06-03-windows-threading-stdlib-gap.md. **USER POSITIONS this in the slate.**

**Next = v6.0.53 — PACKED: Windows threading/mutex stdlib arc (thread_win.cyr) + the 64→512
`#derive`-cap raise (heap surgery)** (user 2026-06-03 "pack windows thread and cap together as .53";
512 cap = generous, won't revisit). Issues: 2026-06-03-windows-threading-stdlib-gap.md +
2026-06-03-derive-struct-cap-64-is-real-tpm-blocker.md. Then .54 agnos args+io gap, .55 *at+fsync,
.56 cc5-18-arg + QoL, .57 TS→JS, **TLS resumes at .58** ([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.51 ship — Windows process creation: CreateProcessW spawn arc)

Closing **v6.0.51** — the RUNTIME half of the Windows PE issue (ai-hwaccel,
issue 2026-06-03-windows-pe-syscall-surface-blocks-detection.md). Win32 process
creation now routes through CreateProcessW. check.sh **85/85**; self-host
byte-identical (895,240 B) on Linux + **ecb (macOS) + cass (Windows) + pi
(aarch64)**; **cass RUNTIME verified** — `exec_capture(["cmd.exe","/c","echo
cyrius-spawn-ok"])` spawns a real process and captures `cyrius-spawn-ok`.

**Shipped:**
- **lib/process_win.cyr** — full POSIX process surface (run / run_capture / spawn /
  wait_pid / exec_vec / exec_capture / exec_env + the `_str` family + exec_cmd) over
  CreateProcessW + an anonymous inheritable pipe. Included by lib/process.cyr under
  `#ifdef CYRIUS_TARGET_WIN`; POSIX defs guarded by `#ifndef` (covers Linux/macOS/
  agnos — exactly one target predefined). UTF-16LE cmdline/env builders +
  STARTUPINFOW/PROCESS_INFORMATION layouts.
- **Five PE-internal kernel32 reroutes** (src/backend/x86/emit.cyr, syscalls
  0xF001-0xF005): WaitForSingleObject / GetExitCodeProcess / SetHandleInformation /
  CreatePipe / CreateProcessW — bespoke MS-x64 IAT-call emit fns (CreateProcessW's 10
  args via a packed struct ptr → ECREATEPROC_PE). Pipe reads reuse EREAD_PE's
  raw-handle path (v6.0.45); close reuses ECLOSE_PE. aarch64 dead stubs for
  parse_expr symbol resolution.
- **_win_process_gate** (check.sh 84 → 85) + win_process_probe.cyr — structural
  CreateProcessW-import assertion.
- **FOUND ON HARDWARE:** ECREATEPROC_PE force-aligns rsp — the 10-arg CreateProcessW
  faults on a misalign the ≤4-arg reroutes tolerate (CreatePipe ran, CreateProcessW
  SIGSEGV'd on cass; invisible to objdump). The "run it on the hardware, never trust
  a checkmark" principle in action.

**Next = v6.0.52 (carries the ai-hwaccel downstream wheel smoke).** The cass
spawn-runtime gate originally scoped for .52 landed in .51; .52 = pin ai-hwaccel to
6.0.51 + verify the win_amd64 wheel builds/spawns (downstream, now unblocked).
**Then v6.0.53 = the cyrius CYRIUS_TARGET_AGNOS stdlib args+io gap** (user "after .52"
2026-06-03; agnos-side issue 2026-06-03-cyrius-agnos-stdlib-args-io-gap.md) — lib/args.cyr
+ lib/io.cyr have no CYRIUS_TARGET_AGNOS branch so agnsh #UDs at startup (args_init → ud2);
blocks the agnsh-on-agnos boot. After that .54 = stdlib `*at`+fsync, .55 = cc5-18-arg +
QoL, .56 = TS→JS, **TLS resumes at .57** ([[project_native_tls_arc_v6_2_x]] PRE-TLS SLATE).

## Session close — 2026-06-03 (.50 ship — Windows PE foundation: cycc_win unfrozen + stdlib-build gate)

Closing **v6.0.50** — the FOUNDATION half of the Windows PE issue (ai-hwaccel,
issue 2026-06-03-windows-pe-syscall-surface-blocks-detection.md). check.sh **84/84**;
self-host byte-identical (888,016 B); cycc src UNCHANGED (.50 = install.sh +
check.cyr + probes + the cycc_win artifact) → cross-OS carries over from .49.

**Premise-check reshaped the issue (filed at 6.0.47):** the 6.0.x EMIT path
(`CYRIUS_TARGET_WIN=1 cycc`) already resolves the WIN stdlib closure (0
`PROT_READ`) — the break was the FROZEN `cc5_win` 5.11.69 frontend, which
install.sh copied forward because it had NO `cycc_win` rebuild rule.

**Shipped (foundation):**
- **cycc_win unfrozen 5.11.69 → 6.0.x** — both install.sh paths now build it from
  `src/main_win.cyr` with `CYRIUS_TARGET_WIN=1` (rebuilt unconditionally so a
  stale mtime can't skip the unfreeze). Verified: the version-bump install rule
  fires; snapshot cycc_win 686632 B (5.11.69) → 749568 B (6.0.x PE32+).
- **Windows stdlib-cross-build gate** (`win_emit_probe.cyr` + `_win_build_gate`):
  compiles a stdlib program under CYRIUS_TARGET_WIN=1, asserts MZ + PE32+ +
  Subsystem 3. Guards the `PROT_READ` closure regression + PE emit. 83 → 84.
- The 5.11.5 ExitProcess/WriteFile hazard is gone on 6.x (the cass cross-OS
  self-host writes via WriteFile + exits via ExitProcess every release).

**Next = v6.0.51 (the process-creation arc — the actual ai-hwaccel runtime
blocker):** route Win32 process creation — a `CreateProcess`-based `run`/
`run_capture` under `#ifdef CYRIUS_TARGET_WIN` (the fork/execve+pipe+wait+dup2
pattern lib/process.cyr emits has no 1:1 Win32 mapping) + the kernel32 imports
(CreateProcessW/CreatePipe/WaitForSingleObject/GetExitCodeProcess) + a cass
spawn-build gate. fork(57)/execve(59) are currently unrouted → ai-hwaccel's
probe spawns fault with STATUS_ILLEGAL_INSTRUCTION. **Then return to the TLS arc**
([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.49 ship — AGNOS Phase 3+4: heap + emit gate + CLI; cyrius-side arc COMPLETE)

Closing **v6.0.49**. AGNOS target arc Phase 3+4 — the **cyrius side of the AGNOS
userspace target arc is COMPLETE** (target + peer in .48; heap + gate + CLI in .49).
check.sh **83/83**; self-host byte-identical (888,016 B). **cycc source UNCHANGED
from .48** (Phase 3+4 = lib/programs/cbt only) → cross-OS (pi/ecb/ach/cass) carries
over from .48's 4-host green (no compiler change, like the .46 precedent).

**Shipped:**
- **lib/alloc_agnos.cyr** — agnos heap: chunk-based bump over agnos mmap(27)
  (2 MB-granular, hint-less → discontiguous chunks; no brk). Unblocks agnoshi.
- **`cyrius build --agnos`** — CLI injects CYRIUS_TARGET_AGNOS=1 into cycc's envp
  (cbt _envp is empty, so explicit, like --strict-pin). cbt/{core,cyrius,build}.cyr.
- **_agnos_emit_gate** (programs/check.cyr + agnos_emit_probe.cyr) — static gate:
  compiles a probe under CYRIUS_TARGET_AGNOS=1, asserts valid ELF64 + entry ≥
  0x200000 + NO Linux-60 (agnos exit = syscall(0)). 82 → 83.

**Live run-on-agnos = the one remaining proof, GATED on an agnos-side hook.** agnos
runs a userspace binary interactively (kybernet `run /prog`) or via a kernel
EXEC_SELFTEST that hand-builds its OWN ELF; running an arbitrary cyrius binary
automatically needs an agnos-side hook to load it from ext2 at boot — NO cyrius-side
cross-repo edit (coordination item for the agnos side). The static gate + objdump
proofs (exit=syscall(0), write=syscall(1), mmap(27) heap, valid ELF64) lock the
cyrius-side codegen meanwhile.

**Next (pinned sequence, user 2026-06-03):** **.50 = the new Windows PE syscall-
surface issue** (docs/development/issues/2026-06-03-windows-pe-syscall-surface-blocks-detection.md,
found by the ai-hwaccel client) → **then return to the TLS arc**
([[project_native_tls_arc_v6_2_x]]).

## Session close — 2026-06-03 (.48 ship — AGNOS userspace target: cycc emits agnos ring-3 binaries)

Closing **v6.0.48**. **cycc can now emit AGNOS ring-3 userspace binaries**
(`CYRIUS_TARGET_AGNOS=1`) — the first two phases of the AGNOS target arc.
check.sh 82/82; self-host byte-identical (888,016 B); **cross-OS self-host
byte-identical on pi/ecb/ach/cass** (the changes are agnos-gated/inert for
every other target, but verified on real hardware per the non-negotiable gate).

**What shipped:**
- **`CYRIUS_TARGET_AGNOS` emit target** — env-driven like `CYRIUS_MACHO_ARM`
  (cycc on host emits an x86_64 ELF64 agnos binary; NOT a self-host platform —
  it's a cross-compile target). No new driver. Only codegen divergence: `EEXIT`
  emits agnos `exit` = `syscall(0)` (code in rdi), not Linux `60`. `_TARGET_AGNOS`
  global + `CYRIUS_TARGET_AGNOS` predefine in main.cyr; always-zero shim in the
  aarch64/cx backends (shared frontend resolves on cross-builds — cross-arch
  propagation was mandatory: the first attempt broke 7 cross-arch gates because
  the shim was x86-only).
- **`lib/syscalls_x86_64_agnos.cyr`** — agnos syscall-ABI peer: numbers 0-33,
  `AO_*` flags, `a4`=r10 4-arg (rename/link), agnos `stat`(48B)/`getdents` layouts.
  Standalone (NOT the Linux common wrappers — agnos has its own numbers +
  explicit-length signatures). Wired into lib/syscalls.cyr's #ifdef dispatcher.
- **Fixed** the syscall arity-warning false-positive for agnos (Linux arity
  table vs agnos's colliding numbers) — skipped for CYRIUS_TARGET_AGNOS.
- Verified by objdump: exit-code + write-string agnos binaries use `syscall(0)`
  exit (zero Linux `0x3c`), `syscall(1)` write, agnos numbers, valid ELF64.

**Agnos ABI ground truth (agnos 1.41.1, frozen):** rax=num, rdi/rsi/rdx/r10=a1-4,
ret -1 on error (not -errno), user ptrs ≥0x200000, exit=syscall(0), mmap=27
(2MB-granular)/munmap=28, getdents=29/unlink=30/rename=31(a4)/link=32(a4)/stat=33.
New FS *types* land as mount backends behind vfs_resolve_mount — they do NOT
change the syscall ABI the peer mirrors (re-freeze only on number/sig/layout change, §5).

**Next (AGNOS arc continues):** Phase 3 = `lib/alloc.cyr` agnos heap via `mmap`(27)
→ unblocks **agnoshi** (it allocs). Phase 4 = run-on-agnos verification (QEMU ELF
loader / spawn=3) + an agnos-emit regression gate (objdump no-Linux-60) +
`cyrius build --target agnos` CLI wiring.

## Session close — 2026-06-03 (.47 ship — compiler table-cap raises via packed field pool; AGNOS path clear)

Closing **v6.0.47**. The cap-raise bundle that gates the AGNOS arc is done:
**struct fields 32→256, struct/type table 256→1024, `secret`/`defer` 8→64.**
check.sh 82/82; x86 self-host **887,272 B**; **cross-OS self-host byte-identical
on real hardware: pi (aarch64), ecb (macOS arm64), ach (macOS x86), cass (Windows).**

**How (no S extension, no driver mmap changes):** the heap was at zero headroom,
so instead of the naive 1024×256×8 fixed grid (~4 MB of mostly-zero table), the
per-struct field tables (`struct_ftypes` 0x91A000 / `struct_fnames` 0x92A000)
became a flat **packed pool** addressed `(field_base[si]+fc)*8` — sized by the
SUM of fields (≤8192 entries), reusing the existing 64 KB regions in place.
`REGSTRUCT` records each struct's pool base; `ADDFIELD` fills sequentially
(verified: no per-struct interleave). New index tables (`field_base[1024]`,
`pooltop`) + relocated `struct_names`/`fcounts` + the `secret`/`defer` table went
into the grep-verified-free **0x1A6018-0x1B0000** band; the 256-field `#derive`
parse scratch into **0x1FC000-0x204000**. Heap map (src/main.cyr) updated; driver
heap-map comments defer to main.cyr (cosmetically stale — refresh at closeout).

**Silent-overflow fixes (issue 2026-05-28 "worse half"):** packed pool emits
`"struct field pool exhausted (8192 max)"`; `#derive` metadata table (cap 64)
now errors instead of clobbering. **Gate hardening:** `cross-os-selfhost.sh`
prefers IPv4 (mDNS `fe80::` link-local flaked the cass leg).

**Surgery method (future reference):** one cap at a time, self-host byte-identical
+ targeted test after EACH phase (A secret/defer → B field scratch reloc → C1
struct-table reloc → C2/D pool+caps → E #derive diag), then check.sh + 4-host
cross-OS. Tests: 10-secret fn (42), 40-field #derive accessors (85), 1000 structs
clean, 300-structs-then-40-field (80, proves base[] correct at scale).

**Next: AGNOS userspace target arc** (CYRIUS_TARGET_AGNOS) — the cap blockers are
now clear. Gated on agnos FS-ABI re-freeze; verify upstream before committing.

## Session close — 2026-06-03 (.46 ship — argv/envp byte-sizing class closed repo-wide + UEFI ud2 regression guard)

Closing **v6.0.46**. check.sh **82/82**; x86 self-host **886,656 B**, byte-
identical to .45 (no compiler source changed — only the version string
`6.0.45`→`6.0.46`, same byte length → identical binary behavior, so the .45
cross-OS self-host status carries over unchanged).

**The bug that surfaced:** 8 TypeScript `check.sh` gates were silently failing.
Root cause = the cyrius buffer contract (`var x[N]` = N **bytes**, not N
slots): the `--lex-ts`/`--parse-ts` gate runner used `var argv[3]; … var
envp[1];`, so `envp[0]` aliased `argv[1]` and `store64(&envp, 0)` zeroed the
mode flag → cycc ran cyrius-mode + rejected the TS fixtures' em-dash. Pre-
existing (the .44 cycc reproduces it); latent until a check-binary rebuild
shifted the stack layout. Tell-tale: fork-only nondeterminism (same `cycc
--lex-ts < fixture` exits 0 from a shell, 1 when fork+execve'd).

**Shipped (packed):**
- **`argv`/`envp` byte-sizing class closed REPO-WIDE** (exhaustive sweep, not
  just the failing gate): `programs/check.cyr` (16 sites), `lib/regression.cyr`
  (SSH/scp/exec helpers + the ssh-alive probe writing 8 ptrs into `argv[8]`),
  `lib/pam.cyr`, `cbt/{build,commands,deps,pulsar}.cyr` (the cyrius CLI execs),
  `programs/ts_test_runner.cyr` (same `envp`-aliases-`argv[1]` bug zeroing
  `mode_flag`), `programs/cyrius-lsp.cyr`. Compiler `src/` verified clean — 0
  sites. + the `tar` member-loop in the cross-OS gate got `argv[304]` + the
  missing `idx < 37` 32-member bound guard.
- **UEFI `fncallN` ud2 regression guard** — `programs/efi_fncall_probe.cyr` +
  `_efi_emit_gate` byte-scan for `0F 0B 0F 0B`; issue archived. (The bug was
  already fixed in v6.0.x; this locks it in.)
- **Premise-check:** `preprocess_out` is already 8 MB (v5.11.33) — that cap-
  raise needs no code; the `lex.cyr` 2 MB checks guard a different buffer
  (`str_data`). Noted on the issue.

**Next: v6.0.47 = the cap-raise heap-map surgery** (deferred from .46 by user
direction — "cut and do the surgery next release"). Struct-field 32→256 +
type-table 256→1024 (+ the silent-overflow diagnostic) via a **packed-pool
decoupled layout** (per-struct base offset into a flat pool sized by SUM of
fields, not `structs×maxfields` — avoids ~4 MB of zero-padding), `secret`/
`defer` 8→64. Every raise needs relocation (S is a tightly-packed ~78 MB
mmap). Then AGNOS userspace target arc.

## Session close — 2026-06-03 (.45 ship — cross-OS gate REAL; aarch64 + Windows self-host FIXED on real hardware)

Closing **v6.0.45**. The cross-OS self-host gate is now REAL and
publish-blocking, and it caught + drove the fix of the two platforms that
shipped "green" while broken. **All four hosts self-host byte-identical on
REAL hardware:** ecb (macOS arm64), ach (macOS x86_64), pi (Linux aarch64),
cass (Windows). check.sh 82/82; x86 self-host **886,656 B**.

**Corrected ground truth (verified on hardware, not a checkmark):**
- **x86-macOS (ach) self-hosts** — the .44 "doesn't self-host" retraction was
  a codesign-comparison artifact (`codesign -s -` mutates the Mach-O with an
  LC_CODE_SIGNATURE load command). Run UNSIGNED → byte-identical fixpoint. The
  .39–.44 x86-macOS "runtime arc" chased a testing artifact, not a bug.
- **aarch64-Linux (pi) FIXED** — `ESYSXLAT` translated open(2)→openat(56) by
  NUMBER only, never inserting AT_FDCWD → path landed in the dirfd register →
  EFAULT → READFILE returned 0 → zero includes → `undefined variable
  '_TARGET_MACHO'`. Now does the open→openat arg-shift. release.yml's "subtle
  QEMU codegen difference" excuse hid a real bug on real silicon.
- **Windows (cass) FIXED** — `EREAD_PE` ran GetStdHandle on EVERY fd (correct
  only for std fds); a real CreateFileW handle (52) → GetStdHandle(-62) →
  garbage → ReadFile returned 0. Now: GetStdHandle for std fds {0,1,2},
  real handles used directly. First time cycc compiles *through itself* on Windows.

**Shipped this release (packed):**
- **Real publish-blocking gate:** `scripts/cross-os-selfhost.sh` (4 hosts,
  fail-loud, IP-pinned + HostKeyAlias) + `cyrius audit` 4-host arms + `ci.yml`
  native jobs that build+self-host cycc (macos-14 / new macos-13 Intel /
  windows-latest / new ubuntu-24.04-arm) and block `release.yml` publish.
- **mabda folded at 3.0.1** (AMD-native GA) — vendored opt-in, `[deps.mabda]`
  removed; needs mmap/dynlib/sakshi (consumer-included; documented in mabda
  README). `docs/api-surface.snapshot` regenerated 2,846 → **2,727** fns.
- **`docs/development/dev-tools-linux.md`** (per-env dev toolchain) + README /
  CLAUDE.md links.

**Queue:** the macOS/Windows/aarch64 cross-OS self-host SAGA is CLOSED — all
four hosts green on real hardware. Remaining: preprocess-cap raise (2 MB →
6/8 MB, `2026-06-03-preprocess-cap-raise.md`, cap-sweep) · UEFI `fncallN`
ud2 · cap-raise bundle (struct 256 / type-table 1024 / secret 64) · then AGNOS.

## Session close — 2026-06-02 (.44 ship — DCE driver-parity fix + .43 retraction)

Closing **v6.0.44**. ELF self-host byte-identical; check.sh green. x86-macOS
does **NOT** self-host — correcting the .43 record.

**RETRACTION:** the .43 "x86-macOS self-hosts byte-identical" claim was
false — a codesigned-vs-unsigned `cmp` (LC_CODE_SIGNATURE changes ncmds/size)
+ a stale file. `cycc(cycc) != cycc` on `ach`. The cross-built cycc runs and
compiles real programs (42, 88, strings, gvars, enums, includes verified) —
it is NOT a self-hosting compiler. The carry-negate fix itself is real.

**Real fix this slot:** `main_x86_macho.cyr` was missing `main.cyr`'s
always-on DCE stub pass (unreferenced top-level fns → 3-byte `xor eax,eax;
ret`). The hand-written dedicated driver dropped it → cross-builder stubbed,
native didn't → guaranteed `cycc != cycc(cycc)` on every uncalled fn. Ported
the pre-scan bitmap + stub decision verbatim; verified correct under trusted
Linux execution (`note: 6 unreachable fns (0 bytes)`).

**Blocker (the real root):** layout-sensitive Darwin **global-variable
access** heisenbug. m1-built cycc_macho == trusted-built one (emission is
byte-perfect), but on the Mac it mis-accesses one of its own top-level
globals at its exact gvar layout — right DCE decision in isolation, wrong in
place. ANY added global shifts the layout and fixes it → every probe masks
it. Ruled out: heap >4GB, segment vmsize/totvar, DCE bitmap (popcount equal
both hosts), gvar-array 16-align (FIXUP uses real dbase), non-determinism.
Next avenue: byte-level disasm of cycc_macho's gvar map (reconstruct from
EMIT_GVAR_INITS prologue) OR a debugger that attaches to ad-hoc Mach-O.

**Queue:** x86-macOS gvar heisenbug (self-host blocker) · then full pillar
(argv→pkg→install→gate) · Windows `cycc` bug 2+ (`cass`) · UEFI ud2 · CI
cross-OS gate · cap-raise bundle (struct 256/type-table 1024/secret 64) ·
then AGNOS.

## Session close — 2026-06-02 (.43 ship — x86-macOS carry-negate keystone)

> **RETRACTED in .44** — the self-host claim below did not hold
> (codesigned-vs-unsigned cmp + stale file). x86-macOS does not self-host.
> The carry-negate fix is real; only the self-host conclusion is withdrawn.

Closing **v6.0.43**. ELF self-host byte-identical 886,432 B; check.sh green.

**★ The x86_64 Mach-O cycc self-hosts on real Intel hardware (`ach`).** The
keystone fix (5 bytes): `ESYSCALL` now emits `jnc +3; neg rax` after every
Mach-O syscall — Darwin signals errors via the CARRY flag + POSITIVE errno,
not Linux's negative return, so every `if (result < 0)` check silently
passed on failure (e.g. `PP_IFDEF_PASS`'s fallback mmap → SIGSEGV in
PREPROCESS). arm64 had `csneg`; x86 had nothing. Gated `_TARGET_MACHO==1`.

**Verified on `ach` (Intel, Darwin 13.7.8):** cycc runs (was SIGSYS at
instruction 1) → trivial exits 42 → fib (recursion+loop) exits 88 →
**self-hosts byte-identical** (cross→c2 741376 B→c3, cmp clean). x86 ELF +
arm64 macho self-host byte-identical; check.sh 82/82. No regressions
(macho-gated).

**x86-macOS COMPILER pillar layers 1-5 DONE.** Remaining for the FULL pillar
(PILLAR RULE — install.sh→working cyrius on HW), next release:
1. **argv entry prologue** — wrapper + tools (fmt/lint/doc) need argv (cycc
   reads stdin, needs none). Emit `push rsi/rdi; mov r13,sp` into outputs;
   `_macho_x28`/`_macho_argv_base` read r13. --version/--strict ride this.
2. **`scripts/build-macos-x86-tarball.sh`** (mirror arm64) + install.sh x86
   path + release.yml `build-macos`.
3. **Real-install gate on `ach`** — install.sh → `cyrius build fn-main-42`
   → exit 42. Pillar NOT closed until this passes on hardware.

**Queue:** x86-macOS full pillar (argv→pkg→install→gate) · Windows `cycc`
bug 2+ (`cass`) · UEFI ud2 · CI cross-OS gate · cap-raise bundle (struct
256/type-table 1024/secret 64) · then AGNOS.

## Session close — 2026-06-02 (.42 ship — x86-macOS dedicated driver; layers 3-4)

Closing **v6.0.42**. self-host byte-identical 886,272 B; check.sh green.

**x86-macOS runtime arc (Intel cycc, `ach`) — dedicated driver + layers
3-4. Still non-functional; gated/macho-only, x86 ELF self-host byte-id.**
- **NEW `src/main_x86_macho.cyr`** — dedicated x86 Mach-O driver (peer of
  `main_aarch64_macho.cyr`; chosen over `#ifdef`-ing main.cyr because the
  entry-prologue argv parking hits a bootstrap chicken-and-egg). Hardcodes
  target+arch, mmaps heap, skips /proc. Includes pe/emit.cyr for the
  `_pe_text_rva` symbols x86/fixup references.
- **Layer 3** — skip `/proc/self/cmdline` on macho (main.cyr; no /proc +
  Darwin errno-in-carry made a failed open look like success → off-stack
  walk).
- **Layer 4** — `_macho_x28`/`_macho_argv_base` x86-safe (return 0 on
  `#ifdef CYRIUS_ARCH_X86`; were arm64 asm → garbage on x86).
- cycc now reaches **PREPROCESS** (layers 1-4 cleared). **Layer 5 OPEN:
  SIGSEGV inside PREPROCESS — leading hypothesis Darwin LC_MAIN entry stack
  alignment (`rsp%16==8` vs ELF `0`) faulting SSE-aligned ops; fix belongs
  in shared macho entry emit (backend/macho/emit.cyr x86 path).** Heap
  fully accessible (probe verified). Issue
  `2026-06-02-macos-x86-release-no-compiler.md` has the full layer ledger.

**Cap-raise bundle (after platform repairs) — TARGETS user-set:** struct
fields 32→256, type table 256→1024 (+ silent-FAIL diagnostic), secret/defer
8→64. type-table issue filed (`2026-05-28-type-table-256-cap.md`).

**Queue:** x86-macOS layer 5 (entry alignment, `ach`) → argv prologue →
x86 release packaging + real-install gate · Windows `cycc` bug 2+ (`cass`)
· UEFI ud2 · CI cross-OS gate · cap-raise bundle · then AGNOS.

## Session close — 2026-06-02 (.41 ship — arm64-macOS [deps] FIXED; x86-macOS arc opened)

Closing **v6.0.41**. self-host byte-identical 886,272 B (x86 + arm64).

**Fixed — arm64-macOS `[deps] stdlib` build SIGSYS (ai-hwaccel UNBLOCKED).**
The v6.0.40 bug-1 follow-on, pinned by checkpoint-bisection on `ecb`. NOT
`dir_list`/`getdents64` (the .40 guess was wrong — the resolver copies by
name, never lists a dir). TWO Darwin-ABI defects:
- **getcwd SIGSYS:** `_abs_path`'s `syscall(79)` mapped `79→326` ("__getcwd")
  in arm64 `ESYSXLAT` — but **Darwin has no getcwd syscall; slot 326 is
  unused** → SIGSYS. cycc self-host never calls getcwd → shipped green 6
  minors. Now `open(".")→fcntl(F_GETPATH)→close`; `ESYSXLAT` gains
  `fcntl 72→92`, drops `79→326`. Also `getcwd 79→17` added to aarch64-Linux
  ESYSXLAT (was `fstatat` → relative-path degradation, latent).
- **transitive stdlib dropped:** `_file_size` read Linux `st_size` offset
  48; raw Darwin `stat` fills the legacy struct with size at **byte 72**
  (verified by struct dump). Wrong size → truncated include-scan → `io`
  copied without its chain. Fixed (`#ifdef`, offset 72).
Verified end-to-end on `ecb`: 8 transitive files, build OK, stdlib executes.

**Added — x86-macOS runtime arc, first 2 of N layers (Intel cycc still
non-functional; gated to macho, inert on ELF, x86 ELF self-host byte-id).**
Diagnosed on `ach`, exit walked 140→139: (1) mmap heap bootstrap in
`main.cyr` (`brk` was first syscall → SIGSYS); (2) `EMACHO_SYSXLAT`
(`backend/x86/emit.cyr`) — x86 analog of arm64 `ESYSXLAT`, rewrites Linux
syscall nums → `0x2000000|BSD`. **Layer 3 (`/proc/self/cmdline` arg parse:
no `/proc` + Darwin errno-in-carry → walks off stack → SIGSEGV) and layer 4
(envp stack reading) remain.** Architecture call pending (dedicated
`main_x86_macho.cyr` vs continued `#ifdef`). Issue
`2026-06-02-macos-x86-release-no-compiler.md`.

**Filed:** `2026-06-02-macos-getdirentries-dir-listing-port.md` (separate
Darwin dir-enum gap; NOT a `[deps]` blocker — affects `cyrius update` /
git-dep locks). **Queue intake requested:** struct-field cap (32) raise +
related cap items from proposals/issues → next-version queue.

**Queue (user-confirmed 2026-06-02):** x86_64-macOS runtime layers 3-4
(`ach`: `/proc/self/cmdline`→stack-argv + Darwin errno convention, then
envp) · Windows `cycc` runtime bug 2+ (`SBL`/`GBL`, `cass`) · UEFI ud2 ·
CI cross-OS gate · **compiler table-cap raises bundle** (AFTER platform
repairs — TARGETS user-set 2026-06-02: struct fields 32→256 [avatara
2.5.0 blocked], type table 256→1024 + silent-FAIL diagnostic, secret/defer
per-fn 8→64; all three are
compile-state tables, ship as one packed release; issues:
`2026-06-02-struct-field-cap-raise.md`,
`2026-05-28-type-table-256-cap.md`, `2026-05-27-secret-defer-block-per-fn-cap.md`)
· then AGNOS. See [[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.40 ship — stdlib QoL + arm64-macOS [deps] probe fix)

Closing **v6.0.40**. check.sh 82/82; self-host byte-identical 885,040 B.

**Added:** `lib/math.cyr` `f64_le`/`f64_ge` (avatara proposal 2026-06-02;
NaN-correct; +6 math.tcyr asserts; api-surface 2844→2846). avatara drops
its `src/types.cyr` copies once shipped. Proposal archived.

**Fixed:** arm64-macOS `[deps] stdlib` install-probe false-negative —
`_dep_find_stdlib_dir` used `is_dir` (getdents64, Linux syscall 217, not
ported to Darwin) → false "version not installed" on a present snapshot,
blocking every pinned consumer manifest with stdlib deps (ai-hwaccel
2.3.6). Probe now uses `file_exists(<lib>/syscalls.cyr)` (open-based).
Verified on ecb: false error gone, `io.cyr` resolves.

**Open (consumer still blocked):** arm64-macOS `cyrius build` with
`[deps] stdlib` now **SIGSYS's (exit 140)** — the resolver's `dir_list`
also calls `getdents64`. **Common root: the directory-listing surface
(`is_dir`/`dir_list`/`getdents64`) was NEVER ported to Darwin.** Bug 2 =
add `getdents64`→`getdirentries` (Darwin syscall 196) to arm64 ESYSXLAT
+ Darwin `dirent` parsing in `lib/fs.cyr` (a .32–.34-shaped BSD-ABI piece
for fs-enumeration). Issue `2026-06-02-macos-arm64-deps-stdlib-pin-check.md`.

**Platform-repair queue (all PILLAR, real-install-verified on hardware):**
arm64-macOS getdents/dir-listing (unblocks ai-hwaccel) · x86_64-macOS
runtime arc (SIGSYS, `ach`) · Windows `cycc` runtime bug 2+ (`SBL`/`GBL`,
`cass`) · UEFI ud2 · CI cross-OS gate · then AGNOS. See
[[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.39 ship — Windows `cycc` runtime bug 1 fixed; arc opened)

Closing **v6.0.39**. Dug into Windows on real `cass` and found **`cycc`
has NEVER run as a compiler on Windows** — crashed on startup, hidden
~30 minors because CI only ran EMITTED PE programs, never compiled one
THROUGH `cycc` (the macOS placebo, one platform over).

**Bug 1 FIXED (verified on cass):** `lib/alloc_windows.cyr:alloc_init`
called `syscall(12)` (BRK) assuming a "PE reroutes brk → VirtualAlloc"
that was **never implemented** (PE dispatch handles 0/1/2/3/8/9/60/228,
not 12) → raw SYSCALL → STATUS_ACCESS_VIOLATION on the first `alloc()`
in `vec_new()` at startup. Fixed to `syscall(9)` (mmap → VirtualAlloc,
the main-heap reroute). cycc now runs + reads stdin on cass (12/12).
Also fixed `pe/emit.cyr` accidental HIGH_ENTROPY_VA (0x0160→0x0140,
hygiene per its own comment). x86 self-host byte-identical 885,040 B;
Linux smoke 42; macOS/Linux unaffected (`#ifdef`-gated).

**Bug 2 OPEN (Windows still doesn't compile):** post-fix `cycc` reads
input but generates 0 code (`GCP=0`) — `BL` is lost before parse
(`GBL`=0 right after `SBL(S, bl=12)`; `SBL`'s store isn't landing where
`GBL` reads on Windows). Distinct bug; likely more beneath. **Windows =
a multi-slot RUNTIME ARC.** Issue `2026-06-02-windows-cycc-runtime-multibug.md`.

**Order (user 2026-06-02): cut .39 → NEXT = x86_64-macОS runtime arc
(x86 Mach-O cycc SIGSYS's on real compiles; verifiable on `ach`, Intel
Mac) → then RETURN to grinding Windows bug 2+ → UEFI → CI gate → AGNOS.**
PILLAR rule holds for every platform: real installer compiles+runs on
hardware. See [[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.38 ship — macОS arm64 INSTALL actually ships a compiler)

Closing **v6.0.38**. **The thing the user actually runs — `install.sh`
on a Mac — now produces a working toolchain.** Verified end-to-end on
real Apple Silicon (ecb) via the REAL installer, not an SSH cross-build.

**THE FAILURE THIS FIXES:** the `build-macos-arm64` release job shipped
only a `smoke.macho` toy — **every Apple Silicon install was EMPTY**
(no `cycc`/`cyrius`). Flagged in the `.32` notes as problem #1, then I
**punted it for 5 releases** while "verifying macОS" by hand-cross-
building binaries on Linux and scp'ing them to ecb — never the real
install. The user installed 6.0.37 on a Mac and got nothing: the exact
"found by ports" failure, committed one level up from the CI rot that
started this arc. **Pillar lesson pinned: a platform isn't supported
until the REAL installer yields a working toolchain on real hardware —
SSH self-host is necessary but CANNOT catch a packaging hole.**

**Fixed (all verified via the real `install.sh` on ecb):**
- release `build-macos-arm64` ships the full arm64 Mach-O toolchain in
  `bin/` (cycc + cycc_aarch64 + cyrius + cyrfmt/cyrlint/cyrdoc +
  cyriusly), via `scripts/build-macos-arm64-tarball.sh` (single source
  of truth — release AND the audit gate both call it).
- `install.sh` ad-hoc codesigns each Mach-O binary on macОS + hard-fails
  on a no-`bin/` tarball + `CYRIUS_INSTALL_TARBALL` local override.
- `cyrius build` ad-hoc-signs its output on macОS (`#ifdef
  CYRIUS_TARGET_MACOS`) — unsigned arm64 = AMFI SIGKILL.
- **`cyrius audit` real-install gate**: build tarball → install.sh →
  `cyrius build fn-main`→42. PASSES. The check that catches an empty/
  broken install. `check.sh` 82/82; cycc unchanged 885,040 B.

**x86_64-macОS (`ach`, Intel) — NOT done, surfaced not punted:** the x86
Mach-O `cycc` **SIGSYS's (rc 140) on real compiles** — only partial
Darwin BSD-ABI syscall translation (arm64 got the full `ESYSXLAT` in
.34; x86 never did). A runtime ARC, not a packaging patch. Issue
`2026-06-02-macos-x86-release-no-compiler.md`. `ach` is SSH-wired for
verification.

**Platform window order (user 2026-06-02): Windows install+self-host
(cass) → x86-macОS runtime arc → UEFI `fncallN` ud2 → CI cross-OS gate →
AGNOS. PILLAR RULE: each platform's REAL installer must produce a
working toolchain (verified on hardware) — "we don't support a platform
if the installer doesn't work."** See [[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.37 ship — macОS `fn main()` return→exit FIXED)

Closing **v6.0.37**. macОS `fn main(){return N;}` now exits N (was 1).
Verified end-to-end via the real `cyrius audit` gate on `ecb`.

**Root cause (`src/main_aarch64_macho.cyr`):** the native Mach-O driver
is a stale fork that never received `main_aarch64.cyr`'s **v5.9.37
auto-call-`main` fix** (same rot class as the v6.0.33 entry-prologue
gap). The emitted entry stub fell straight through to the exit syscall
**without `bl main`** → `main()` never ran → exit with `argc` (1).
Disassembly (native vs cross) confirmed the missing `bl`. Ported the
fix: walk fn table for `"main\0"` → `ECALLTO` before `EEXIT`.
**Native-compiler-only** — the cross-emitter (`main_aarch64.cyr`+env)
already had it, so `.35`/.36 cross-built smokes passed while the
on-device toolchain didn't. Tools unaffected (explicit `sys_exit`).

**Gate hardening (`cbt/commands.cyr`):** the `cyrius audit` macОS gate
now asserts `fn main(){return 42;}`→42 (a `var x=42;` smoke would sail
past this exact rot). Gate line: "self-host byte-identical + exit-code
propagation".

**Gates:** `cyrius audit` PASS — ecb self-host **byte-identical 639,412
B** + exit-code assertion. x86 self-host **byte-identical 885,040 B** (no
`src/main.cyr` change); `check.sh` **82/82**. Compiler source defines no
firing `fn main` → macОS self-host stays byte-identical.

**Next (user order): Windows install + self-host (cass) → UEFI `fncallN`
ud2 regression → CI cross-OS gate → AGNOS userspace arc.** See
[[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.36 ship — open-issue LHF cleanup batch)

Closing **v6.0.36**, the open-issue low-hanging-fruit cleanup batch
(platform-cleanup window, before the AGNOS binary). **No compiler
(`src/`) change** — `cycc` self-host byte-identical **885,040 B**;
`check.sh` **82/82**. Open issues **16 → 7**.

**7 bited fixes:**
- `lib/bigint.cyr` `u256_addmod` honors the 2²⁵⁶ carry-out (was wrong for
  moduli near 2²⁵⁶, e.g. P-256 order; Curve25519 callers unaffected) +
  regression test (fails pre-fix).
- `cyrlint` exit code conventional (0/1/2; `--strict`, opt-in
  `--exit-with-count`); `cyrius lint --strict` passthrough. Gates parse
  stdout → unaffected.
- `cyrius build` rejects unknown `-…` flags + refuses `.cyr` output
  (source-clobber data-loss guard).
- `cbt` `modules` TOML key: all 3 readers boundary/comment-aware +
  indented-key capable.
- `cyriusly` starship install/remove symlink-safe (preserves dotfile
  links) + `.bak` backup.
- Build-artifact **pre-commit hook** (`scripts/hooks/pre-commit`) +
  `cyrius hooks install` verb + `install.sh --refresh-only` auto-install
  (fired live during this bump). check.cyr gate stays as backstop.

**2 verified-resolved + archived:** `type-table-256-cap` (diagnostic
ships), `distlib-blank-lines` (fixed v6.0.9). **1 won't-fix:** `for(;;)`
empty clauses (documented in cyrius-guide.md).

**Remaining open (7):** `cc5-18-arg-scramble`, `uefi-fncall-ud2`,
`yeo-tsx-emit`, `bote` (cold), `asm-block` (P3), `secret/defer cap` (own
release), **`macho-main-return-exit` (NEXT)**.

**Next (user order 2026-06-02): macОS `fn main()` return→exit
propagation → Windows/cass install+self-host → UEFI `fncallN` ud2
regression → CI cross-OS gate → AGNOS userspace arc.** See
[[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.35 ship — `cyrius build` macОS SIGBUS FIXED; `&` shadowing)

Closing **v6.0.35**. The `.34`-deferred `cyrius build` Mach-O SIGBUS is
**fixed** — single-line root cause, verified end-to-end on `ecb` (real
Apple Silicon). The `.34` "non-ftype-0 / missed-fixup / large-binary"
hypothesis was wrong: it was a **name-shadowing / W^X** bug.

**Root cause (`src/frontend/parse_expr.cyr`):** the `&IDENT` operator
checked `FINDFN` **before** `FINDLOCAL`/`FINDVAR`, so a local or global
whose name collided with a function resolved to the **function's
`__TEXT` code address**. The wrapper's `sys_system` has `var argv[4]`
while `lib/args.cyr` defines `fn argv(n)` → `&argv` became `&(fn argv)`
(a code pointer @ `0x10000F288`); `store64(&argv, "/bin/sh")` then wrote
into `__TEXT`. **Why macОS-only:** cyrius x86 ELF uses a single **RWE**
load segment, so the bogus write into code silently succeeded and the
load-back round-tripped — invisible on Linux; macОS enforces **W^X** →
hard SIGBUS. Not size-related (a 3-line repro triggers it); cycc itself
was unaffected (no local/global collides with a function name).

**Fix:** resolve `&IDENT` in **local → global → function** order
(correct lexical scoping). `&fn_name` still works when nothing shadows
(e.g. allocator vtable `&_arena_alloc`).

**Gates:** x86 self-host **byte-identical 885,040 B**; `check.sh`
**82/82**; conflict-probe over cycc's own source = **0** changed `&`
resolutions (reorder is a no-op for the compiler). `ecb`: cycc self-host
**byte-identical 639,412 B** + **`cyrius build` runs (exit 0, valid
Mach-O)** — SIGBUS gone.

**Found during the fix → filed, queued for the platform window (NOT
.35):** macОS `fn main(){return N;}` exits **1**, not N — the Mach-O
entry/exit epilogue doesn't propagate `main`'s return to the BSD exit
syscall. **Pre-existing** (installed `.34` cycc identical), unrelated to
this fix; tools are unaffected (they `sys_exit` explicitly). Issue:
`docs/development/issues/2026-06-02-macho-main-return-exit-propagation.md`.

**Arc (user 2026-06-02 — finish PLATFORM cleanup before the AGNOS
binary):** the v6.0.x platform-cleanup window absorbs `.36` Windows
install + self-host (cass), `.37` CI cross-OS self-host gate, **and the
macОS main-return→exit bug above**, all **before** the AGNOS userspace
target arc (`~.38+`). See [[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.34 ship — macOS TOOLS work; cyrius build wrapper deferred to .35)

Closing **v6.0.34**. **cyrfmt / cyrlint / cyrdoc run real files on Apple
Silicon (ecb)** — formats, lints, generates docs. Broad macho-arm BSD-ABI
expansion. User cut at working tools; the `cyrius build` wrapper SIGBUS is
a deep macho fixup bug, precisely localized, deferred to **.35**.

**Landed (all `#ifdef`/`_TARGET_MACHO`-gated → Linux byte-identical):**
- `src/backend/aarch64/emit.cyr` — ESYSXLAT expanded to the full BSD
  syscall surface (read/write/close/lseek/mmap/mprotect/munmap/exit +
  openat→open arg-shift + execve/dup3→dup2/wait4/clone→fork/mkdirat/
  unlinkat/fchmodat arg-shifts + raw x86 stat/getpid/rename/symlink) +
  **fork x1-fixup** in ESYSCALL (macOS raw fork child/parent x0 quirk).
- `lib/syscalls_aarch64_linux.cyr` — macOS `OpenFlag` values (O_* differ).
- `lib/alloc_macos.cyr` — 256 MB up-front heap reserve (macOS won't honor
  mmap hints → growth SIGBUS'd; bump allocator needs contiguity).
- `cbt/cyrius.cyr` + `cbt/core.cyr` — wrapper defaults arch=aarch64 +
  reads HOME/env from the entry-stack envp (no /proc on macOS).

**Gates:** Linux self-host **byte-identical 885,024 B**; `check.sh`
**82/82**. ecb: tools verified by output.

**THE .35 BUG (precisely localized):** `cyrius build` forks+execs cycc;
the child SIGBUSes — `(Data Abort) byte write Translation fault`. crash
report + lldb: a global assignment's macho `adrp/add` resolves to
`0x10000F288` (**inside read-only __TEXT**, page-3 base) instead of
`__DATA` (page 17, `0x44000`). The normal ftype-0 var path is CORRECT
(verified `acp=219496` → `mfp=15` → page 17); this specific access uses a
page-3 (`mfp=1`) base via a non-ftype-0 / missed-fixup path. macho-only
(`cyrius build` works on Linux), large-binary-only (cycc self-hosts fine
— it keeps state in its 78MB heap, not big static globals; the wrapper
has 339KB static data). **.35 = trace which fixup record/emit path
produces that page-3 address.**

**Arc:** .35 = cyrius-build wrapper macho-fixup bug; .36 = Windows
install + self-host (cass; wire the audit gate's cass arm); .37 = CI
cross-OS self-host gate — MANDATORY before AGNOS (~.38+). See
[[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-02 (.33 ship — macOS self-host FIXED + cyrius audit cross-OS gate)

Closing **v6.0.33**. **The macOS compiler self-host is fixed and proven
byte-identical on Apple Silicon (ecb)** — the core of the ~9-minor rot.

**Self-host fix (`src/`):** `main_aarch64_macho.cyr` was a stale fork
missing the v5.5.17 entry prologue (`stp x0,x1`/`mov x28,sp`) + the
`CYRIUS_TARGET_MACOS` predefine → cycc built from it emitted prologue-less,
dispatch-less, Linux-shaped programs that SIGILL'd on Darwin. Added both.
`runtime.cyr` `_read_env` gained a macOS branch (argc/argv/envp via x28).
**Proven on ecb: cycc self-host round1==round2 byte-identical (639,412 B);
output runs (`tiny`→42).** Linux unchanged: 885,024 B, check.sh 82/82.

**`cyrius audit` cross-OS gate (`cbt/`):** after check.sh, `cyrius audit`
now cross-builds the Mach-O cycc, ships to ecb, codesigns, self-hosts
twice + `cmp` — **FAIL-LOUD** (unreachable = FAILURE, no "not available"
skip). Verified: `cyrius audit` prints "PASS: ecb (macOS arm64) cycc
self-host byte-identical". `_co_build_envp` reconstructs real env (from
/proc/self/environ) so ssh/scp have HOME+agent. cass/Windows arm = .35.

**Why this matters / how it rotted:** the macOS path was unverified since
v5.3.13 because the native CI jobs (`macho-arm64-native` macos-14,
`windows-native` windows-latest) only ran hello-world/exit-code smoke,
never built or self-hosted cycc. ecb/cass were one `ssh` away, unused.
Hardening: CLAUDE.md Key Principle "Cross-OS self-host is non-negotiable
on REAL hardware" + Closeout 3b + the audit gate + memories.

**KNOWN-INCOMPLETE (→ .34, scoped up front):** macOS **tool/wrapper**
file I/O (cyrfmt/cyrlint/cyrdoc/cyrius-wrapper) still broken — the macho
ESYSXLAT whitelists only 9 syscalls + auto-prepend forces aarch64
numbers. Full BSD-ABI tool port (ESYSXLAT whitelist + reroutes +
openat/stat + enum-collision) is `.34`. `cycc` itself unaffected.

**Arc plan:** .34 = macOS tool/wrapper BSD-ABI port; .35 = Windows
install + self-host (cass; wire the audit gate's cass arm); .36 = CI
cross-OS self-host gate (extend macos-14/windows-latest jobs) — MANDATORY
before AGNOS arc (~.37+). See [[project_macos_install_arm64_fix_v6_0_32]],
[[feedback_macos_windows_ci_gate_mandatory]].

## Session close — 2026-06-01 (.32 ship — macOS install repair arc START + the CI-gate-gap reckoning)

Closing **v6.0.32**, first slot of the macOS install-repair arc
(interrupt before the AGNOS binary work). `lib/`-only code + process
hardening.

**Code (verified on Linux byte-identical + on ecb):**
- `lib/syscalls.cyr` — added the `CYRIUS_TARGET_MACOS` dispatch branch
  (was missing; neither WIN nor LINUX fired for a Mach-O build →
  `undefined STDERR_FD`). x86_64 → `syscalls_macos.cyr`; arm64 → Linux
  aarch64 numbers + ESYSXLAT (same as the compiler).
- `lib/syscalls_macos.cyr` — added `STDIN_FD`/`STDOUT_FD`/`STDERR_FD`.
- Result: `cyrius` wrapper builds as arm64 Mach-O (262,580 B) on ecb;
  `cycc` from `src/main_aarch64_macho.cyr` (mmap heap) runs + compiles
  `tiny`→exit 42 on ecb once ad-hoc codesigned.

**Gates:** cycc x86 self-host **byte-identical 885,024 B**; `check.sh`
**82/82** (plumbing is emit-neutral on Linux).

**THE RECKONING (why this arc exists):** the macOS compiler self-host
rotted silently from **v5.3.13 → v6.0.32** — ~9 minor lines, 400+
patches — behind a green CI job named "Mach-O ARM64 Native". That job
(and `windows-native`) only ran hello-world / exit-code smoke programs;
neither ever built or self-hosted `cycc`. The rot surfaced only when the
user installed on a Mac and got only `cyriusly`. ecb/cass were wired in
`~/.ssh/config` the whole time, one `ssh` away, unused by any gate and
by me across the whole TLS arc. Root causes mapped on ecb: unsigned →
AMFI SIGKILL (fix: install-time `codesign -s -`); brk heap in main.cyr
(the correct `main_aarch64_macho.cyr` mmap source exists); native
self-host SIGILL (→ .33); tool/wrapper file-I/O broken (→ .33).

**Hardening landed this slot:** CLAUDE.md Key Principle "Cross-OS
self-host is non-negotiable, on REAL hardware" + Closeout Pass item 3b
(no minor closes with macOS/Windows self-host unverified/red). Memories:
[[feedback_macos_windows_ci_gate_mandatory]], reinforced
[[reference_verification_hosts_ssh]] + [[feedback_cross_arch_propagation_mandatory]].

**Arc plan:** .33 = aarch64/Mach-O **self-host codegen bug** (cycc
reproduces itself byte-identical on ecb) + tool file-I/O; .34 = Windows
install (verify on cass); **.35 = CI cross-OS self-host GATE** (extend
the macos-14/windows-latest jobs to self-host cycc — MANDATORY before
AGNOS arc). See [[project_macos_install_arm64_fix_v6_0_32]].

## Session close — 2026-06-01 (.31 ship — TLS Mini-arc B.8 connect() + e2e; **Mini-arc B COMPLETE**)

Closing **v6.0.31**, the eighth/final slot of TLS Mini-arc B (client).
**The TLS 1.3 stack — client + server — is complete.** `lib/`-only.

`tls_native_connect(ctx, sock_fd)` — client socket handshake driver
(mirror of `accept()`): send ClientHello plaintext record → read SH
(CCS-skipping) → `client_parse_server_hello` → read encrypted flight →
`client_recv_flight` → verify server Finished + send client Finished
(`client_finish`) → `install_app_keys`. `tls_native_write`/`read` —
socket-level app I/O (`seal_app`/`open_app` over the stored fd, CONNECTED
required). `accept()` now stores the fd + derives master/installs app
keys so the server does app data too.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot **2,844 fns** (connect/write/read were stubs in
  the surface; now live, same signatures).
- `tls_native_scaffold.tcyr` 369 → **375 asserts** (+6): `socketpair`+
  `fork` e2e — **our client (`connect`) ↔ our server (`accept`)**, full
  TLS 1.3 handshake + bidirectional app data over a real socket.

Memory pin: [[project_native_tls_arc_v6_2_x]] — **Mini-arc B COMPLETE
(8/8)**; the full 1.3 stack (A primitives + C server + B client) ships.

**Next: `.32` — macOS install + arm64 Mach-O runtime fix** (slotted
BEFORE the AGNOS binary arc, per user 2026-06-01). Bug surfaced this
session: macOS install ships **only `cyriusly`**, no compiler. Root
cause on Apple Silicon (`ecb`, Darwin arm64): (1) the `aarch64-macos`
release tarball carries no `bin/` (stale "arm64 pulls brk/flock outside
BSD whitelist" claim in `release.yml` build-macos-arm64); (2) `cycc`
*does* build clean as an arm64 Mach-O (639 KB, valid magic/PIE) but
**SIGKILLs (rc=137) on any real compile** on ecb — even `var x=42;`.
Data heap is `prot=3` RW (not a W^X kill); leading suspect is the
`alloc_macos.cyr` contiguity guard (hinted 1MB `mmap`s that macOS won't
place at `_heap_end`). Also `syscalls_macos.cyr` defines no `STD*_FD`, so
the `cyrius` wrapper fails to build for macOS (`cbt/core.cyr:60
undefined STDERR_FD`). x86_64-macos build-macos job also omits cycc but
there's no x86_64-macOS host to verify against (ecb is arm64). `.32`
scope = make the macOS install ship a working compiler + fix the arm64
runtime; verify end-to-end on ecb via SSH.

## Session close — 2026-06-01 (.30 ship — TLS Mini-arc B.7 hostname / SAN verification)

Closing **v6.0.30**, the seventh slot of TLS Mini-arc B (client).
`lib/`-only.

`tls_native_client_verify_hostname(ctx)`: walks the server cert DER to
its SubjectAltName (OID 2.5.29.17 — sigil doesn't surface SAN) + matches
the SNI host per RFC 6125 (case-insensitive exact; leftmost wildcard,
single-label). Private helpers `_tn_der_hdr` (TLV reader),
`_tn_cert_san_match`, `_tn_host_match`, `_tn_ci_eq`. Returns TLS_OK /
CERT_HOSTNAME_MISMATCH.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,843 → **2,844 fns** (+client_verify_hostname).
- `tls_native_scaffold.tcyr` 360 → **369 asserts** (+9): SAN cert
  (localhost + *.example.com) — exact, wildcard, multi-label reject,
  bare-domain reject, case-insensitive, no-SAN → mismatch.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 7 of 8.
Next: **.31 — localhost client↔server socket e2e** (lands
`tls_native_connect()` client socket driver + socket-level
`tls_native_write`/`read`; runs full client↔server handshake + app data
over a socketpair). Closes Mini-arc B → cyrius has a complete native
TLS 1.3 client + server.

## Session close — 2026-06-01 (.29 ship — TLS Mini-arc B.6 X.509 chain verification)

Closing **v6.0.29**, the sixth slot of TLS Mini-arc B (client).
`lib/`-only.

`tls_native_set_ca_bundle` now live (parse trust anchor — DER via
x509_parse, PEM via pem_decode_certs first cert; store CA_ROOT).
`tls_native_client_verify_chain(ctx, now_unix)`: sigil x509_verify_chain
over server leaf + root (sig links, DN match, validity, CA bits) →
TLS_OK / CERT_INVALID. now_unix caller-supplied (no stdlib clock).
Intermediate chains a follow-on. New ctx field CA_ROOT.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,842 → **2,843 fns** (+client_verify_chain).
- `tls_native_scaffold.tcyr` 352 → **360 asserts** (+8): self-signed →
  trusted root TLS_OK; untrusted root → CERT_INVALID; expired → CERT_INVALID.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 6 of
~8. Next: **.30 — hostname / SAN verification** (RFC 6125: parse cert
SAN via sigil der_walk/der_skip, match SNI host + wildcards), then
**.31 — localhost client↔server socket e2e** (+ connect() + socket-level
write/read; runs full client↔server handshake + app data over a socket).

## Session close — 2026-06-01 (.28 ship — client app data + multi-OS installer)

Closing **v6.0.28**, two deliverables (user direction): TLS 1.3 app
data + the installer multi-OS fix.

**Installer**: `scripts/install.sh` now OS-aware (linux / darwin→-macos
/ windows→-windows tarball mapping; macOS install works now — -macos
artifacts already shipped; source-bootstrap guarded Linux-only).
`.github/workflows/release.yml` + `build-windows` job (PE32+ via
`cycc_win` cross-emitter, verified locally → `cycc.exe` PE32+). Targets
Linux+Windows+Darwin (AGNOS eventual). Followups end-of-6.0.x:
install.sh polish, native Windows .ps1 installer, AGNOS-target install
(roadmap back-end candidates).

**TLS app data**: `tls_native_install_app_keys` (server+client app
key/IV + seqs), `tls_native_seal_app`/`open_app` (role-aware: write own
key, read peer's; open surfaces alert/post-handshake), and
`tls_native_key_update_secret` (§7.2 traffic-upd rotation). New ctx
app-key fields.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,838 → **2,842 fns** (+4 app-data publics).
- `tls_native_scaffold.tcyr` 341 → **352 asserts** (+11): full mutual
  handshake → **app data both directions** under app keys; tamper →
  DECRYPT; KeyUpdate secret rotation. (Traps: `secret` reserved-keyword
  param → `sec`; 4-space continuation indent up front, no fmt nit.)

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 5 of
~8; TLS 1.3 app data flowing. Next: **.29 — X.509 chain verification**
(wire sigil x509_verify_chain + trust store), then .30 hostname/SAN,
.31 localhost client↔server socket e2e (+ connect() + socket-level
write/read).

## Session close — 2026-06-01 (.27 ship — TLS Mini-arc B.4 client Finished; handshake complete)

Closing **v6.0.27**, the fourth slot of TLS Mini-arc B (client). The
TLS 1.3 handshake is now **complete on both sides**. `lib/`-only.

`tls_native_client_seal_handshake` (seal with client hs key + CLI_SEQ).
`tls_native_client_finish`: verify the server Finished (HMAC over
CH..CertVerify, server hs finished key) → transcript → derive master +
app-traffic secrets (over CH..serverFin, §7.1) → compute+seal client
Finished (HMAC over CH..serverFin, client hs finished key) → transcript
→ CONNECTED.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (fmt gate caught the continuation-indent
  nit again — now pinned [[feedback_cyrfmt_continuation_indent]]).
- api-surface snapshot 2,836 → **2,838 fns** (+client_seal_handshake,
  +client_finish).
- `tls_native_scaffold.tcyr` 334 → **341 asserts** (+7): **full
  in-memory mutual handshake** — our client + our server both reach
  CONNECTED + agree on server_application_traffic secret; bad server
  Finished → client AUTHN. (Fixed a test bug: server derive_master must
  be over CH..serverFin, not CH..clientFin.)

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 4 of
~8; **TLS 1.3 handshake complete client+server**. Next: **.28 — app
data send/recv + KeyUpdate** (install app-traffic keys; tls_native_write
/read over app records), then .29 X.509 chain verify, .30 hostname/SAN,
.31 localhost client↔server e2e loop.

## Session close — 2026-06-01 (.26 ship — TLS Mini-arc B.3 client recv flight + CertVerify)

Closing **v6.0.26**, the third slot of TLS Mini-arc B (client).
`lib/`-only.

`tls_native_client_open_handshake` (open with server hs key + SRV_SEQ).
`tls_native_client_recv_flight`: decrypt the server flight, transcript
EE + Cert + CertVerify, parse+store server leaf cert, **verify the
server CertificateVerify sig** ("TLS 1.3, server CertificateVerify"
content vs cert pubkey — ECDSA-P256/Ed25519; P-384+RSA gap →
KEY_UNSUPPORTED), stash the server Finished for .27. New ctx field
SERVER_CERT.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (fmt gate caught a continuation-indent
  nit; cyrfmt-corrected).
- api-surface snapshot 2,834 → **2,836 fns** (+client_open_handshake,
  +client_recv_flight).
- `tls_native_scaffold.tcyr` 326 → **334 asserts** (+8): matching
  ECDSA-P256 cert/key → client verifies real server flight → TLS_OK;
  mismatched → client AUTHN. Positively closes .19's CertVerify crypto
  from the client side.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 3 of
~8. Next: **.27 — Finished + handshake-complete**: client verifies the
**server** Finished (stashed; MAC over CH..CertVerify with server_hs
finished key), computes+sends its **own** Finished (client_hs key),
derives master/app secrets, → CONNECTED. Completes the client
handshake; sets up the .31 localhost client↔server loop.

## Session close — 2026-06-01 (.25 ship — TLS Mini-arc B.2 ServerHello parse + client keys)

Closing **v6.0.25**, the second slot of TLS Mini-arc B (client).
`lib/`-only.

`tls_native_client_parse_server_hello(ctx, sh, sh_len)`: downgrade
protection (HRR sentinel + §4.1.3 DOWNGRD markers + supported_versions
0x0304), validate cipher, extract server x25519 key_share, retroactive
transcript init (buffered CH → SH), client ECDHE (x25519), derive
handshake secret, install traffic keys → client ready to decrypt the
server flight. HRR retry not yet handled (→ HANDSHAKE_FAILED).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,833 → **2,834 fns** (+client_parse_server_hello).
- `tls_native_scaffold.tcyr` 317 → **326 asserts** (+9): client↔server
  hello exchange → **client+server agree on ECDHE shared secret AND
  server_hs_traffic secret**; negatives.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 2 of
~8. Next: **.26 — EncryptedExtensions + Certificate + CertificateVerify**
(client reads + decrypts the server flight via a client-open record
wrapper; verifies the server's signature against its cert — ECDSA/
Ed25519; RSA waits on sigil 3.5.10). Also exercises .19's positive
CertVerify crypto from the client side.

## Session close — 2026-06-01 (.24 ship — TLS Mini-arc B.1 ClientHello construction)

Closing **v6.0.24**, the first slot of TLS Mini-arc B (TLS 1.3 client).
`lib/`-only.

`tls_native_new_client(host, host_len)` now live (alloc client ctx,
role CLIENT, verify PEER, copy host for SNI). `tls_native_client_build_hello`:
x25519 ephemeral keypair + random → serialize ClientHello (SNI,
supported_versions 1.3, supported_groups x25519, signature_algorithms
ECDSA/Ed25519, key_share x25519); buffers the CH (ctx CH_BUF/CH_LEN)
for retroactive transcript init at .25 (hash unknown until SH reveals
the cipher).

**Mini-arc B arc-open cross-walk** (sigil 3.5.9, against the repo):
no new sigil filing — the 2026-05-28 audit covers the client surface.
RSA cert verify → sigil 3.5.10 (audit-pinned; client does ECDSA/Ed25519
certs only until then); x25519 key_share only (no P-256 ECDH); SAN/
hostname (.30) is cyrius-side via sigil der_walk/der_skip.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,832 → **2,833 fns** (+client_build_hello).
- `tls_native_scaffold.tcyr` 307 → **317 asserts** (+10): CH builds +
  buffered; interop cross-check (our server parses our CH → SH,
  AES-256-GCM + x25519, no HRR).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc B step 1 of
~8. Next: **.25 — ServerHello parsing** (downgrade protection, key-
share extraction, ciphersuite acceptance) + retroactive transcript
init (CH then SH) + client ECDHE → handshake secret. Premise-check at
entry: x25519 client→server shared-secret derivation already proven in
the .22 loopback client; .25 packages the SH-parse + key derivation as
library fns.

## Session close — 2026-06-01 (.23 ship — OpenSSL interop; **Mini-arc C COMPLETE**)

Closing **v6.0.23** — the cyrius native TLS 1.3 **server** completes a
full handshake against **OpenSSL 3.6.2** `s_client`. **Mini-arc C done
(9 slots, .15–.23).** `lib/`-only + a cross-arch syscall.

`_tn_sock_read_record_skip_ccs` skips ChangeCipherSpec records (TLS 1.3
middlebox-compat; openssl sends one) — wired into both accept() reads
(loopback .22 unaffected). Added `sys_setsockopt` cross-arch
(SYS_SETSOCKOPT x86=54/aarch64=208) for SO_REUSEADDR.

Interop test (guarded on openssl presence): matching openssl-gen
ECDSA-P256 cert+key (DER) → real TCP listen → fork `openssl s_client
-tls1_3` → accept → **handshake TLS_OK + CONNECTED** (cipher
AES-256-GCM-SHA384; openssl's only gripe is the expected self-signed
verify warning).

**Mini-arc C (TLS 1.3 server) — the full stack**: state machine →
cert/key → ServerHello/x25519 → signed flight → client-auth →
resumption → record-layer AEAD → accept() socket loop + loopback →
OpenSSL interop. Crypto in sigil 3.5.9; sovereign protocol layer.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (OpenSSL interop runs in-suite).
- api-surface snapshot 2,831 → **2,832 fns** (+sys_setsockopt).
- `tls_native_scaffold.tcyr` 301 → **307 asserts** (+6: openssl cert/key
  load + the real-peer handshake → CONNECTED).

Memory pin: [[project_native_tls_arc_v6_2_x]] — **Mini-arc C COMPLETE
(9/9)**. Next: **Mini-arc B — TLS 1.3 client** (~.24+), which completes
the 1.3 stack and exercises the .19/.20 deferred items (positive
client-auth crypto + resumption acceptance) once we have our own client
+ a localhost client↔server loop. Then Mini-arc D (1.2), AGNOS target
arc (gated on agnos ABI re-freeze), Mini-arc E (consumer + closeout).

## Session close — 2026-06-01 (.22 ship — TLS Mini-arc C.8 accept() + loopback e2e)

Closing **v6.0.22** — the **first full TLS 1.3 handshake over a socket
in cyrius**. The e2e capstone split: .22 = socket handshake driver +
cyrius-native loopback; .23 = OpenSSL `s_client` real interop.

`tls_native_accept(ctx, sock_fd)`: read CH record → plaintext SH →
derive+install handshake keys → encrypted flight → read+verify
encrypted client Finished → CONNECTED. Socket framing helpers
`_tn_sock_read_full`/`_read_record`/`_write_all`. Added `sys_socketpair`
cross-arch (SYS_SOCKETPAIR x86=53/aarch64=199 + common wrapper).

Loopback test: socketpair + fork — parent server accept(), child a
minimal TLS 1.3 client (CH, SH parse, x25519 ECDHE, matching key
derivation, flight decrypt, Finished) from existing primitives →
asserts accept()→TLS_OK + CONNECTED over the socket.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (lint gate caught a >120-char line in
  the driver; wrapped).
- api-surface snapshot 2,830 → **2,831 fns** (+sys_socketpair).
- `tls_native_scaffold.tcyr` 298 → **301 asserts** (+3: socketpair,
  accept→TLS_OK, CONNECTED).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 8 of
9 done (e2e split widened C to 9). Next: **.23 — OpenSSL `s_client`
real interop** (real TCP listen/accept + fork openssl; PEM-cert support
+ matching ECDSA-P256 cert/key gen + ChangeCipherSpec middlebox compat)
closes Mini-arc C against a real peer. Premise-check at entry: openssl
s_client flags for a raw TLS 1.3 handshake + how to generate a DER cert
+ key pair via openssl from the harness.

## Session close — 2026-06-01 (.21 ship — TLS Mini-arc C.7 record-layer protection)

Closing **v6.0.21**, the seventh slot of TLS Mini-arc C (server) — the
record-layer AEAD encryption + traffic-key install (the prerequisite
for a real handshake). `lib/`-only. The e2e capstone split: .21 =
record layer, .22 = accept() socket loop + OpenSSL e2e.

`tls_native_record_seal` / `_open` (TLSInnerPlaintext content‖type;
nonce = static_iv XOR seq; AAD = 5-byte header; padding strip on open;
DECRYPT on bad tag). `tls_native_server_install_handshake_keys`
(derive+install server/client hs key/IV via derive_key/derive_iv;
reset seqs). `server_seal_handshake` / `_open_handshake` ctx wrappers.
New ctx fields (per-direction key/IV ptrs + inline 8-byte seqs);
TLS_CTX_LEN 320→448 (room for app keys).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (fmt gate caught a continuation-indent
  nit in the new multi-line calls; fixed via cyrfmt — paren-aligned →
  4-space continuation).
- api-surface snapshot 2,825 → **2,830 fns** (+5 publics).
- `tls_native_scaffold.tcyr` 286 → **298 asserts** (+12): seal/open
  round-trip, seq-mismatch + tampered → DECRYPT, ctx-installed-key
  server-seal round-trip.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 7 of
8 done (e2e split widened C to 8). Next: **.22 — accept() socket loop
+ OpenSSL `s_client` e2e** closes Mini-arc C; validates the full
plaintext+encrypted handshake flow + .19's positive client-auth crypto
+ x509-pubkey wiring against a real peer. Premise-check: sys_accept /
sys_read / sys_write availability + how to spawn `openssl s_client`
from a .tcyr (or a shell-driven smoke harness).

## Session close — 2026-05-31 (.20 ship — TLS Mini-arc C.6 session-ticket / PSK resumption)

Closing **v6.0.20**, the sixth slot of TLS Mini-arc C (server) — the
server-side issuance + crypto primitives for TLS 1.3 resumption.
`lib/`-only.

`tls_native_server_derive_master` (→ master + resumption_master over
CH..clientFin). `tls_native_server_new_session_ticket`: PSK =
HKDF-Expand-Label(resumption_master, "resumption", nonce); sealed into
a self-encrypted ticket (AES-256-GCM under a per-ctx STEK); serialized
as NewSessionTicket (§4.6.1). `tls_native_server_open_ticket` (AEAD
open). `tls_native_psk_binder` (§4.2.11.2: early→binder_key→
finished_key→HMAC). Private `_tn_ticket_seal`/`_tn_ctx_stek`; new ctx
field STEK. Ticket blob = IV(12)‖tag(16)‖ct.

**Scope**: issuance + primitives. Resumption *acceptance* (parse a
resuming CH pre_shared_key + verify binder + derive from PSK) rides
the client mini-arc / e2e (needs a real resuming client).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,821 → **2,825 fns** (+4 publics).
- `tls_native_scaffold.tcyr` 276 → **286 asserts** (+10): NewSessionTicket
  issue+parse; ticket **opens to a PSK == independently-derived PSK**;
  binder deterministic + non-trivial; tampered ticket → AEAD fail.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 6 of
7 done. Next: **.21 — server e2e vs OpenSSL `s_client`** closes
Mini-arc C and validates the full handshake (plus .19's positive
client-auth crypto + the x509-pubkey wiring) against a real peer.

## Session close — 2026-05-31 (.19 ship — TLS Mini-arc C.5 optional client auth)

Closing **v6.0.19**, the fifth slot of TLS Mini-arc C (server). The
old combined .19 (client-auth + resumption) was **split** at slot
entry (user direction, roadmap-sanctioned): client-auth here, session/
PSK resumption → .20, server e2e → .21. `lib/`-only.

CertificateRequest emission (verify-mode gated, in build_flight after
EE; signature_algorithms ext). `tls_native_server_recv_client_certificate`
(parse + store leaf), `_recv_client_certverify` (verify CV sig over
"TLS 1.3, client CertificateVerify" content vs client cert pubkey —
ECDSA-P256 via verify_der + Ed25519; P-384 → KEY_UNSUPPORTED, no sigil
verify_der peer), `_recv_client_finished` (HMAC(client_hs finished_key,
transcript) constant-time compare via `_tn_ct_eq` → CONNECTED; serves
both no-auth + auth paths). New ctx field CLIENT_CERT.

**Honest scope**: the *positive* client-CertVerify crypto isn't
unit-tested — no cert + matching private-key fixture / cert-gen to
synthesize a valid client sig. Covered at .21 e2e (OpenSSL
`s_client -cert`), which also validates the x509-pubkey-format wiring.
The negative path + client-Finished positive + everything else is
tested now.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,818 → **2,821 fns** (+3 recv_client_* publics).
- `tls_native_scaffold.tcyr` 262 → **276 asserts** (+14): CertReq by
  verify mode, client-cert parse, **client Finished → CONNECTED**
  positive + wrong-Finished AUTHN, garbage client-CV → AUTHN+ERROR.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 5 of
7 done (split widened C to 7). Next: **.20 — session-ticket / PSK
resumption** (resumption_master via keysched_derive_master,
NewSessionTicket issuance, PSK binder), then **.21 server e2e** (vs
OpenSSL s_client) closes Mini-arc C.

## Session close — 2026-05-31 (.18 ship — TLS Mini-arc C.4 server flight 2)

Closing **v6.0.18**, the fourth slot of TLS Mini-arc C (server). The
server derives the handshake secret from .17's ECDHE shared secret +
the CH‖SH transcript, then emits its authenticated flight:
EncryptedExtensions ‖ Certificate ‖ CertificateVerify ‖ Finished.
`lib/`-only; messages are plaintext (record-layer AEAD wrapping under
the handshake key is the accept() I/O layer, later).

`tls_native_server_derive_handshake` (keysched_new +
keysched_derive_handshake) → `tls_native_server_build_flight` builds
the four messages, advancing the transcript after each. CertificateVerify
signs `0x20*64 ‖ "TLS 1.3, server CertificateVerify" ‖ 0x00 ‖
Transcript-Hash(CH..Cert)` via sigil ECDSA-P256/P384 (DER) or Ed25519
(seed expanded to 64-byte sk via ed25519_keypair). RSA → KEY_UNSUPPORTED
(RSA-PSS sign still awaits a sigil tag). Finished verify_data =
HMAC(HKDF-Expand-Label(server_hs,"finished"), Transcript-Hash(..CV)).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,816 → **2,818 fns** (+2 publics).
- `tls_native_scaffold.tcyr` 245 → **262 asserts** (+17): full flight
  off a real CH→SH exchange; the **CertificateVerify Ed25519 signature
  verifies** against an independently-replayed transcript, and the
  **Finished verify_data matches** an independent finished-key + HMAC
  recompute.

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 4 of
6 done. Next: **.19 — optional client auth (CertificateRequest +
client-cert validation) + session-ticket / PSK resumption** (RFC 8446
§4.6.1 + §2.2), the last build-out before .20 server e2e. Full Mini-arc
C scope keeps both (user chose full over minimal); split into sub-slots
if either grows.

## Session close — 2026-05-31 (.17 ship — TLS Mini-arc C.3 ServerHello + key_share)

Closing **v6.0.17**, the third slot of TLS Mini-arc C (server). The
server consumes a ClientHello and produces its ServerHello (or HRR),
establishing the x25519 ECDHE shared secret. `lib/`-only.

`tls_native_server_respond_hello(ctx, ch_msg, ch_len, out, out_max)`:
bounds-checked ClientHello parse (`_tn_parse_client_hello` +
`_tn_find_ext` / `_tn_find_x25519_share` / `_tn_supports_x25519`) →
cipher negotiation (AES-256-GCM ▸ ChaCha20 server pref) + x25519
group → ephemeral keypair via `sys_getrandom` + `x25519_base`/`x25519`
ECDHE → ServerHello serialize + transcript(CH,SH). HelloRetryRequest
when the client offered no x25519 share but lists it in
supported_groups (SHA-256("HelloRetryRequest") sentinel random).
Added `get_group` / `server_sent_hrr` diagnostics + ctx fields.

**Scope**: x25519 only (P-256 ECDHE awaits a sigil ECDH-P256
primitive; HRR is the fallback). HRR §4.4.1 transcript substitution +
retry loop deferred to the accept() driver.

**Reserved-keyword traps**: `pub` and `shared` are reserved (like
`secret`) — renamed to ppub/epub and dhe. Compiler flagged them
precisely (unlike `secret`'s useless location). Pinned to
[[feedback_secret_reserved_keyword]].

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,813 → **2,816 fns** (+3 publics).
- `tls_native_scaffold.tcyr` 233 → **245 asserts** (+12; live CH →
  SH with end-to-end ECDHE agreement, HRR sentinel, negatives).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 3 of
6 done. Next: **.18 — EncryptedExtensions + Certificate +
CertificateVerify + Finished** (derive the handshake secret from
.17's ECDHE shared secret via keysched_derive_handshake, then the
server's signed flight; CertificateVerify uses sigil ECDSA/Ed25519
sign — RSA-PSS still awaits a sigil tag).

## Session close — 2026-05-31 (.16 ship — TLS Mini-arc C.2 server cert + key loading)

Closing **v6.0.16**, the second slot of TLS Mini-arc C (server).
Parses the cert chain + private key (stored as opaque refs by .15's
new_server) into usable form, with key-format detection. `lib/`-only.

**Premise-check correction (pinned)**: at slot entry I grepped
cyrius's *vendored* `lib/sigil.cyr` (pin 3.5.6) and wrongly declared
the private-key parsers "missing." Sigil was at **3.5.9** with all of
it shipped — I checked the fold, not the repo. User was (rightly)
furious; 3rd occurrence of this class. Pinned
[[feedback_premise_check_upstream_repo_not_vendored]]: premise-check
the UPSTREAM repo (`~/Repos/<dep>/VERSION` + `src/` + `dist/`), not the
vendored copy; if the repo's ahead, RE-FOLD, don't block.

**sigil fold 3.5.6 → 3.5.9**: re-folded `lib/sigil.cyr` byte-identical
from sigil's dist (v5.8.65 fold model). Brings `src/privkey.cyr`
(pem_decode_privkey + ed25519/p256/p384 `_privkey_from_der` + PKCS#8
algo detect) and `src/ecdsa_sign.cyr` (ecdsa_p256/p384_sign + _der).
RSA parse + RSA-PSS sign still a future sigil tag.

**Cred loading**: `tls_native_server_load_creds(ctx)` →
`_tn_load_privkey` (PEM 0x2D → pem_decode_privkey auto-detect; DER →
try each typed parser) + `_tn_load_cert` (x509_parse leaf). Stores
algo/material/leaf-cert in ctx; failure → ERROR + last_err. Added
`tls_native_get_key_algo`, `TLS_ERR_KEY_UNSUPPORTED` (−21), and the
parsed-cred ctx fields. RSA key → KEY_UNSUPPORTED. PEM-cert + full
chain walk deferred to .18/.26.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82** (sigil 3.5.9 fold passes the suite).
- api-surface snapshot 2,808 → **2,813 fns** (+2 tls publics + sigil
  3.5.9's new parser/sign publics).
- `tls_native_scaffold.tcyr` 219 → **233 asserts** (+14; real key +
  cert vectors from sigil's test suite).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 2 of
6 done. Next: **.17 — ServerHello + key_share response** (x25519
ECDHE — confirmed present in the 3.5.9 fold; `x25519` + `x25519_base`).
HelloRetryRequest if the client key_share is insufficient.

## Session close — 2026-05-31 (.15 ship — TLS Mini-arc C.1 server handshake state machine)

Closing **v6.0.15**, the first slot of TLS Mini-arc C (server),
pulled ahead of the client per the 2026-05-31 re-order. Lays the
**connection context** that all of Mini-arc C + B build on, plus the
**server-side state-machine transitions**. `lib/`-only — no compiler
change.

**Connection ctx**: the opaque handle is now a real `alloc()`'d
struct, 256-byte documented layout (`TLS_CTX_OFF_*` — role / state /
version / cipher / verify / version-range / transcript + keysched
handles / cert+key refs / host / sock fd / last-err). +136..255
reserved for the read/write keys, seq nums, and I/O buffers B–D add.
`_tn_ctx_new(role)` zero-inits + applies defaults (INIT, verify NONE,
1.2..1.3); `_tn_ctx_fail` records err + drives state to ERROR.

**Server state machine**: `tls_native_server_transition(ctx, event)`
drives `INIT →START→ WAIT_CH →RECV_CH→ {WAIT_FINISHED |
WAIT_CLIENT_FLIGHT2} →RECV_FINISHED→ CONNECTED`, verify-mode steering
the client-auth branch. Illegal transitions → ERROR + TLS_ERR_PROTOCOL.
Events `TLS_EV_*` added. The message build/parse firing each event is
.16–.19; this slot proves the transitions in isolation.

**Live now (were stubs)**: `new_server` (alloc + stores cert/key as
opaque refs — DER parse is .16), `set_verify`, `get_state` /
`get_cipher` / `get_version` (read live ctx), new `get_last_error`
diagnostic. `new_client` / `connect` / `accept` / `set_version_range`
/ … stay stubbed for later slots.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit change).
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,806 → **2,808 fns** (+2 publics:
  `tls_native_server_transition`, `tls_native_get_last_error`).
- `tls_native_scaffold.tcyr` 191 → **219 asserts** (+28 for ctx +
  server state machine: happy path, client-auth path, illegal
  transitions, null guards).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc C step 1 of
6 done. Next: **.16 — cert + key loading** (PEM/DER decode via sigil;
RSA / ECDSA / Ed25519 format detection). Premise-check sigil's
server-side surface (private-key parsers + RSA/ECDSA sign) at .16
entry — these are in the 2026-05-28 comprehensive audit but become
load-bearing now; hold affected sub-slots if unshipped (.13 precedent).

## 2026-05-31 — TLS arc RE-ORDERED + AGNOS userspace-target arc inserted (planning note, no bump)

User direction 2026-05-31 (two passes): with TLS Mini-arc A complete,
**all of TLS 1.3 first kept contiguous** (server then client — "no
gaps"), then a new **AGNOS userspace-target arc**, then the **TLS 1.2
backport**, then consumer/closeout. The "v6.0.x going forward" list
under the .14 close below is **superseded** by this order (roadmap.md
is the canonical plan). New execution order from .15:

- **.15–.20 — Mini-arc C, TLS 1.3 server** (pulled forward, FULL
  scope — user chose full over a minimal subset). Forcing function for
  sigil's server-side gaps (RSA sign PKCS#1v1.5+PSS, ECDSA P-256/384
  sign, RSA/ECDSA/Ed25519 private-key parsers) — all already in the
  2026-05-28 comprehensive sigil audit; premise-check sigil's tag at
  .15 entry, hold affected sub-slots if unshipped (.13 precedent).
- **.21–.28 — Mini-arc B, TLS 1.3 client** — completes the 1.3 stack;
  .28 client e2e closes the localhost client↔server loop. Kept
  adjacent to C so 1.3 has no gap (user: "after 1.3 work so there is
  no gaps").
- **.29–.33 — AGNOS userspace target `CYRIUS_TARGET_AGNOS`** (new).
  Cyrius-side gating prerequisite for AGNOS's 1.41.x shell-separation
  arc: a ring-3 agnos syscall-ABI compile target so the OS-agnostic
  **agnoshi** shell (`MacCracken/agnoshi`) rebuilds for agnos instead
  of Linux. **Userspace only** (not the v6.2.0 kernel bare-metal
  triple). **ABI contract now FILED**:
  `agnos/docs/development/agnos-userland-abi.md` (canonical source
  `agnos/kernel/core/syscall.cyr`). Table **0–28 🔒 FROZEN** (mirror
  now); FS surface **29 getdents/30 unlink/31 rename/32 link/33 stat
  + `a4=r10` + `AO_*` flags + blocking `read(fd 0)` is 🧪 PROPOSED**,
  re-freezing as agnos 1.41.1 (stdin) + 1.41.2 (FS) land. **Hard gate
  = FS surface re-freeze** (agnoshi build needs it). Peer gotchas:
  agnos `exit`=0 not Linux 60; error `-1` not `-errno`; user ptr ≥
  0x200000; agnos-native `stat`/`getdents` layouts. .29 plumbing +
  `_start`/exit shim → .30 syscall peer (x86_64 + aarch64) → .31
  stdlib subset gating + hello probe → .32 agnoshi cross-build gate
  (flags if absent) → .33 closeout. agnoshi source stays in its own
  repo; no cross-repo edit from cyrius.
- **.34–.39 — Mini-arc D, TLS 1.2 backport** (user: "backport is fine
  to be done after agnos bin works").
- **.40–.42 — Mini-arc E, consumer wiring + TLS arc closeout**.
- **~.43–.49 — back-end window; ~.50 — cycle closeout.**

Slot numbers nominal; the arc may open additional slots (user: "don't
care the additional slots it may open"). Memory pins updated:
[[project_native_tls_arc_v6_2_x]], [[project_agnos_userspace_target_arc]].
No version bump — cyrius stays at v6.0.14.

## Session close — 2026-05-28 (.14 ship — TLS Mini-arc A.5 ciphersuite negotiation; **A COMPLETE**)

Closing **v6.0.14**, the fifth and final slot of TLS Mini-arc A.
**`tls_native_available()` flipped 0→1.** The protocol layer is
usable end-to-end for 2 of 3 TLS 1.3 ciphersuites
(`TLS_AES_256_GCM_SHA384` + `TLS_CHACHA20_POLY1305_SHA256`).

**Ciphersuite registry** — 5 lookup fns (hash algo / key length / IV
length / tag length / supported gate) over the three IANA-defined
TLS 1.3 ciphersuite IDs. All three TLS 1.3 ciphersuites have entries
in the registry; `_supported()` returns 0 for AES-128-GCM-SHA256
until sigil ships AES-128 (see audit issue below).

**Ciphersuite selection** — server-side picker walks the server's
preference list and picks the first that's `_supported()` and in
the client's offer list. Returns 0 on no overlap. Inputs use the
exact TLS-wire-format uint16-BE arrays from ClientHello.cipher_suites.

**AEAD dispatch** — `tls_native_aead_encrypt` and `_decrypt` route
each call to sigil's `aes_gcm_*` or `chacha20poly1305_*` based on
the cipher ID. Tag verification: sigil's decrypt fns return non-zero
on bad tag; we translate to `TLS_ERR_DECRYPT`. Verified by tamper
test (flip last tag byte → DECRYPT err).

**Sigil gap — AES-128 missing**: sigil 3.5.6's `aes_gcm_encrypt`
uses `aes256_key_expand` internally — it's hardcoded for AES-256.
So we ship 2 of 3 TLS 1.3 ciphersuites. The mandatory minimum suite
per RFC 8446 §9.1 (`TLS_AES_128_GCM_SHA256`) is registered but
returns `TLS_ERR_CIPHER_NOT_SUPPORTED` until sigil ships the
AES-128 path.

**Sigil-side asks filed as ONE comprehensive audit** (user direction
this session, frustrated with the piecemeal pattern of filing
each gap at its forcing slot): `sigil/docs/development/issues/2026-05-28-cyrius-tls-arc-full-audit.md`
covers ALL remaining sigil gaps for the FULL TLS arc through .37:
- AES-128 (3 fns: key_expand + gcm_encrypt + gcm_decrypt)
- RSA signature surface (8 fns: PKCS#1 v1.5 + PSS, sign + verify,
  SHA-256 + SHA-384)
- ECDSA P-256 + P-384 sign (4 fns: raw + DER for each curve)
- Private-key parsers for RSA, ECDSA, Ed25519 (5 fns: 4 DER +
  1 PEM auto-detect)
- Optional: TLS 1.2 PRF (cyrius can build inline)

Sigil ships these in whichever order/grouping fits its cycle.
Each line item lifts a specific cyrius hold; net impact-without-
shipping is 70% TLS surface coverage with 30% of the load-bearing
interop gap (AES-128 + RSA).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (stdlib-only).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,800 → 2,806 fns (+6 publics).
- `tls_native_scaffold.tcyr` 161 → 191 asserts (+30 for registry +
  selection + AEAD round-trip + tamper detection).

Memory pin: [[project_native_tls_arc_v6_2_x]] — **Mini-arc A
COMPLETE**. v6.0.x going forward:
  - .15–.22: Mini-arc B — TLS 1.3 client (ClientHello → ServerHello
    → EncryptedExtensions → Certificate → CertificateVerify →
    Finished → application data → X.509 chain → hostname → e2e).
    Some slots will surface server-side dependencies (private key
    parsers, RSA/ECDSA sign) but the bulk is client-side flow.
  - .23–.28: Mini-arc C — TLS 1.3 server
  - .29–.34: Mini-arc D — TLS 1.2 backport
  - .35–.37: Mini-arc E — consumer + closeout
  - .38–.39: cyrius tests + TOML
  - .40–.44: back-end remaining
  - .45: closeout

## Session close — 2026-05-28 (.13 ship — TLS Mini-arc A.4 key schedule)

Closing **v6.0.13**, the fourth slot of the native TLS arc (A.4 of
A's 5 sub-slots). Adds the full TLS 1.3 key schedule per RFC 8446
§7.1 + §7.3: three-phase HKDF tree, four traffic secrets, exporter +
resumption master, per-secret key/IV derivation.

**Held earlier in the session pending sigil HKDF-SHA384** — see the
hold note below. **Resolved by sigil 3.5.6** (same day, 2026-05-28)
shipping `hmac_sha384` + `hkdf_extract_sha384` + `hkdf_expand_sha384`
+ `hkdf_sha384` exactly as requested. Bumped the sigil pin in
cyrius.cyml + refreshed lib/sigil.cyr from sigil's dist bundle. Full
TLS 1.3 ciphersuite set (AES-128/256-GCM-SHA256/384,
ChaCha20-Poly1305-SHA256) now backable by the protocol layer.

**Test vectors**:
- RFC 8448 §3 SHA-256 `early_secret` matched byte-for-byte
  (`33ad0a1c…f170f92a`).
- Python-computed SHA-384 `early_secret` matched
  (`7ee8206f…ec4ea9b5`).
- Derive-Secret("derived") matched for both algorithms.
- derive_key + derive_iv matched against Python reference
  (`dbfaa693…258d01` + `5bd3c71b…73265f`).
- State machine: pre-derivation `get_secret` returns
  TLS_ERR_PROTOCOL; bad algo rejected; bad state transition rejected.

**Cyrius gotchas surfaced (BOTH pinned to memory)**:

1. **`secret` is a reserved keyword** — it's the zeroise-on-return
   attribute (`secret var prk[32];` pattern in sigil). Using `secret`
   as a fn param name fails the parser with
   `error:src/aes_ni.cyr:<huge_line>: expected identifier, got
   unknown` — error location is bogus (the cumulative post-
   preprocessor source position, not the actual offending code).
   Cost ~30 minutes to bisect. Renamed all my params from `secret`
   to `sec`. Memory pin: [[feedback_secret_reserved_keyword]].

2. **9-arg fn called incorrectly = SIGILL** — I drafted comments
   for `_tn_hkdf_spec_set` + `_tn_hkdf_spec_set_ctx` helpers but
   didn't implement them; test code calling those non-existent fns
   compiled to ud2 sentinels → SIGILL with no debug info.
   Refresher on [[feedback_end_to_end_verify_helpers_before_commit]]:
   if you reference a fn in test code, actually implement it. Fixed
   by removing the spec-helper test path; the 9-arg fn works fine
   in practice (verified across 17 new vector asserts).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (stdlib-only).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,797 → 2,800 fns (+3 publics this slot,
  plus sigil 3.5.6's 4 new fns picked up via dist refresh).
- `tls_native_scaffold.tcyr` 122 → 161 asserts (+39 for key
  schedule with RFC 8448 §3 + Python-verified vectors).

Memory pin: [[project_native_tls_arc_v6_2_x]] — Mini-arc A step 4
of 5 done. v6.0.x going forward:
  - .14: Mini-arc A.5 — ciphersuite negotiation; `tls_native_available()`
    flips from 0 to 1 (FIRST CIPHERSUITE END-TO-END wired through
    encrypt/decrypt with the key schedule from this slot)
  - .15–.22: Mini-arc B — TLS 1.3 client
  - .23–.28: Mini-arc C — TLS 1.3 server
  - .29–.34: Mini-arc D — TLS 1.2 backport
  - .35–.37: Mini-arc E — consumer + closeout
  - .38–.39: cyrius tests + TOML
  - .40–.44: back-end remaining
  - .45: closeout

---

## 2026-05-28 — v6.0.13 HELD pending sigil HKDF-SHA384 (RESOLVED same session)

v6.0.13 (Mini-arc A.4 — TLS 1.3 key schedule) **held at slot
entry**. Premise-check found sigil 3.5.5 ships HMAC-SHA256 +
HKDF-Extract-SHA256 + HKDF-Expand-SHA256 only — no SHA-384 variants.
The TLS 1.3 ciphersuite `TLS_AES_256_GCM_SHA384` (0x1302) uses
HKDF-SHA384; without it, .13's key schedule can support
`TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256` only.

**User direction 2026-05-28**: hold .13 until sigil ships HKDF-SHA384.
Rejected the alternative of inlining HMAC-SHA384 + HKDF-SHA384 in
`lib/tls_native.cyr` — would violate the arc's charter that
"crypto stays in sigil; tls_native is a protocol layer". Rejected
also "ship SHA-256-only and patch later" — would have .14's
`tls_native_available()` flip with an incomplete ciphersuite set.

**Sigil-side issue filed (user-authorized cross-repo write)**:
`~/Repos/sigil/docs/development/issues/2026-05-28-cyrius-tls-native-needs-hkdf-sha384.md`.
The issue requests:
- `hmac_sha384(key, key_len, msg, msg_len, out48): i64`
- `hkdf_extract_sha384(salt, salt_len, ikm, ikm_len, prk_out48): i64`
- `hkdf_expand_sha384(prk, prk_len, info, info_len, out, out_len): i64`
- Optional: `hkdf_sha384(salt, salt_len, ikm, ikm_len, info, info_len, out, out_len): i64`

Includes the SHA-384 block-size gotcha (128 bytes, not 64 — common
copy-from-sha256 trap), implementation outline, RFC 4231 §4 test
vectors for HMAC-SHA384, and pointer to RFC 8448 §4's full TLS 1.3
handshake using AES-256-GCM-SHA384 (every intermediate secret
published byte-for-byte; cyrius will verify against this once sigil
ships).

**Resume condition**: sigil 3.5.x patch tag exposing the three (or
four) fns. Cyrius will bump the sigil pin in `cyrius.cyml` and
resume Mini-arc A.4 from .13 entry. Mini-arcs B–E (.14–.37) and the
back-end + closeout (.38–.45) all queue behind this — the whole TLS
arc serialises here.

**No version bump this turn** (nothing shipped). cyrius stays at
v6.0.12. The held .13 slot doesn't consume the slot number — when
work resumes, it still lands as .13.

Memory pin: [`project_native_tls_arc_v6_2_x`] — updated 2026-05-28
with the HELD status + sigil-side ask shape. Cyrius agent on resume
should check sigil's tag for the new fns, bump pin, then start
A.4 implementation from scratch (this session committed nothing).

## Session close — 2026-05-28 (.12 ship — TLS Mini-arc A.3 handshake framing + transcript hash)

Closing **v6.0.12**, the third slot of the native TLS arc
(A.3 of A's 5 sub-slots). Adds the 4-byte handshake message header
(`HandshakeType` + 24-bit length) and the transcript-hash
accumulator (sha256 or sha384 per ciphersuite). With A.3 done, the
only remaining A piece is .13 — the TLS 1.3 key schedule HKDF tree.

**Transcript hash snapshot semantics** (RFC 8446 §4.4.1): the
transcript-hash is sampled multiple times during a handshake
(Finished MAC, CertificateVerify signature input, key schedule
binding). sigil's `sha256_finalize` / `sha384_finalize` mutate
the ctx (padding + length-block append), so `tls_native_transcript_digest`
clones the ctx, finalizes the clone, and discards it — the original
running ctx stays valid for further updates.

**Transitive-include fix**: lib/tls_native.cyr was pre-.12
including only syscalls + alloc + sigil. sigil needs a heavier
dep set (freelist for fl_alloc, string for memcpy, vec, hashmap,
io, fs, bigint, ct, keccak). Without those, `sha256_init` → `fl_alloc`
hit the `ud2` undefined-fn sentinel → SIGILL. Added the full
transitive set so consumers only need to `include "lib/tls_native.cyr"`
([[feedback_stdlib_self_sufficient_constants]]). The pre-existing
libssl wrapper `lib/tls.cyr` documents deps via comment (`Requires:
alloc.cyr, syscalls.cyr, ...`) but tls_native goes the
self-sufficient route.

**Cited test vectors wrong from memory**: drafted `sha256("abcdef")[31]
= 0xFA` and `sha384("abc")[23] = 0x31`. Sigil computed the correct
0x21 and 0x63 (verified via `echo -n "..." | sha256sum / sha384sum`).
Note for future slots: verify reference values against a tool, not
recall.

**Mechanical gates green**:
- cycc x86 **byte-identical at 885,024 B** (stdlib-only).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,791 → 2,797 fns (+6 publics).
- `tls_native_scaffold.tcyr` 78 → 122 asserts (+44 for handshake
  framing + transcript hash with snapshot semantics + FIPS 180-4
  vectors).

Memory pin: [`project_native_tls_arc_v6_2_x`] — Mini-arc A step 3
of 5 done. Next:
  - .13: Mini-arc A.4 — TLS 1.3 key schedule (HKDF tree:
    early/handshake/master secrets, per-direction keys)
  - .14: Mini-arc A.5 — ciphersuite negotiation; tls_native_available()
    flips from 0 to 1
  - .15–.22: Mini-arc B — TLS 1.3 client
  - .23–.28: Mini-arc C — TLS 1.3 server
  - .29–.34: Mini-arc D — TLS 1.2 backport
  - .35–.37: Mini-arc E — consumer + closeout
  - .38–.39: cyrius tests + TOML
  - .40–.44: back-end remaining
  - .45: closeout

## Session close — 2026-05-28 (.11 ship — TLS Mini-arc A.2 record layer)

Closing **v6.0.11**, the second slot of the native TLS arc (A.2 of
A's 5 sub-slots). Built the record-layer building blocks:
big-endian wire helpers, 5-byte header encode/decode, fragmentation
count, per-direction sequence numbers with overflow refusal,
RFC 8446 §5.3 AEAD nonce derivation, and RFC 8446 §5.2 AAD
construction.

**No existing stdlib peer** covered big-endian I/O — TLS is BE
end-to-end. Inlined `_tn_be16/24/32/64_w/r` in tls_native.cyr;
will promote to `lib/be.cyr` if a second consumer (QUIC, HTTP/2
binary frames) materialises.

**Sequence-number invariant per §5.3**: implementations MUST NOT
wrap. `tls_native_seq_increment` returns `TLS_ERR_PROTOCOL` if
asked to bump from the all-ones state. KeyUpdate (slot .19's
client + .25's server) will rekey long before the counter
approaches 2^64.

**AEAD nonce derivation** (§5.3): XOR the direction's 12-byte
static IV with the 8-byte sequence number, left-padded with 4
zero bytes. Identical construction for AES-GCM and
ChaCha20-Poly1305. Hand-vector verified in the .tcyr.

**Bug caught by the .tcyr regression**: cyrius `var x[N]`
allocates N **BYTES** (rounded to 8-byte alignment), not N i64
slots. A 12-byte IV declared `var _iv[2]` was 8 bytes, and writes
to bytes 8-11 clobbered the NEXT local (`_seq2`). aead_nonce
returned phantom zeros for nonce[10] and nonce[11]. Cyrius
source proof in `src/frontend/parse_decl.cyr` (`aligned = (asz +
7) & ~7`). Pinned new memory `feedback_var_array_byte_sized` so
this doesn't bite again in .12+. Note: `cbt/build.cyr`'s
`var argv[4]` + `store64(&argv + 8, ...)` pattern is the same
bug class but works only because `argv` is the last referenced
local. Don't copy the pattern.

**Mechanical gates green**:
- cycc x86 **byte-identical at 885,024 B** (stdlib-only change).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- `scripts/check.sh` **82/82**.
- api-surface snapshot 2,784 → 2,791 fns (+7 publics: 3 record
  fns + 2 seq fns + 2 nonce/AAD fns; `_tn_be*_*` private).
- `tls_native_scaffold.tcyr` 34 → 78 asserts (44 new for record
  layer + BE + seq + nonce + AAD).

Memory pin: [`project_native_tls_arc_v6_2_x`] — Mini-arc A step 2
of 5 done. v6.0.x going forward:
  - .12: handshake message framing (HandshakeType wire,
    reader/writer, transcript hash accumulator)
  - .13: TLS 1.3 key schedule (HKDF tree)
  - .14: ciphersuite negotiation
  - .15–.22: Mini-arc B (TLS 1.3 client)
  - .23–.28: Mini-arc C (TLS 1.3 server)
  - .29–.34: Mini-arc D (TLS 1.2 backport)
  - .35–.37: Mini-arc E (consumer wiring + closeout)
  - .38–.39: cyrius tests + TOML
  - .40–.44: back-end remaining
  - .45: cycle closeout

## Session close — 2026-05-28 (.10 ship — TLS Mini-arc A.1 scaffold)

Closing **v6.0.10**, the first slot of the native TLS arc
(Mini-arc A.1 / A of 5). Pure structure slot — public API surface,
types, error codes, state-machine states. No protocol logic yet;
that's .11 (record layer) → .14 (ciphersuite negotiation) → .15+
(1.3 client/server).

**Premise-check findings at slot entry**:
- Real ecosystem TLS usage is only 5 fns (`tls_available`,
  `tls_connect`, `tls_write`, `tls_read`, `tls_close`) per
  ecosystem-wide grep. Plus sandhi's `tls_policy/` submodules wrap
  the surface for cert pinning. The scaffold's 16 fns superset that
  + add accept (server), CA bundle setter, version-range setter,
  diagnostic getters.
- Sigil 3.5.5 confirmed to ship every primitive the protocol layer
  needs (`x25519`, `chacha20poly1305_*`, `aes_gcm_*`, `hkdf_*`,
  `sha256`, `ecdsa_p256/p384`, `ed25519`, `x509`). Zero crypto
  blockers.

**Cyrius-enum quirk discovered**: enum initializers don't accept
arithmetic (`= 0 - 1`). Worked around by moving the negative-valued
error codes (`TLS_ERR_*`) to top-level `var` constants; positive-
valued enums (ContentType, HandshakeType, etc.) stay as `enum`.
Filed as a v6.x language polish candidate (not pinned).

**`cyrfmt` re-indented continuation comments** inside the enum
body (lines 84-86 of the file got flush-left after fmt). Cosmetic
only; doesn't affect parsing.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no compiler
  change this slot — pure stdlib addition).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- `scripts/check.sh` **82/82**, including the new
  `tls_native_scaffold` tcyr (34 asserts).
- api-surface snapshot refreshed (2,767 → 2,784 fns).

Memory pin: [`project_native_tls_arc_v6_2_x`] — Mini-arc A step 1
of 5 done. v6.0.x shape going forward:
  - .11–.14: Mini-arc A remainder (record/framing/key/cipher)
  - .15–.22: Mini-arc B (TLS 1.3 client)
  - .23–.28: Mini-arc C (TLS 1.3 server)
  - .29–.34: Mini-arc D (TLS 1.2 backport)
  - .35–.37: Mini-arc E (consumer wiring + closeout)
  - .38–.39: cyrius tests + TOML [section]
  - .40–.44: back-end remaining
  - .45: cycle closeout

## Session close — 2026-05-28 (.9 ship — aarch64 wrapper argv + distlib blank-lines)

Closing **v6.0.9**, two open bugs pulled forward into the slot
ahead of the TLS arc (which shifts +1 to .10–.37). Per user
direction 2026-05-28: bump TLS Mini-arc A back one and slot
these two unrelated cleanups in .9.

**Bug A — aarch64 cyrius wrapper argv dispatch (TWO bugs in one
path)**: `lib/args.cyr` used raw x86 syscall numbers (`syscall(2,
...)` for open, etc.). On aarch64, syscall 2 = `io_destroy` and
syscall 0 = `io_setup`, so `args_init()` was calling
`io_destroy("/proc/self/cmdline")` and getting garbage —
`_args_len = 0` → `argc() == 0` → every wrapper dispatch fell
through to "Usage". Fix: switch to the arch-dispatched `sys_open`
/ `sys_read` / `sys_close` wrappers; add `include
"lib/syscalls.cyr"` to args.cyr so it's self-sufficient
([[feedback_stdlib_self_sufficient_constants]]). SECOND bug
surfaced after the first fix: `cbt/cyrius.cyr:732`'s
`syscall(60, exit_code)` was x86's `sys_exit`; aarch64 needs 93.
Switched to `syscall(SYS_EXIT, exit_code)`. Pi smoke confirms
both: dispatch lands, exit code propagates.

**Bug B — distlib blank-line residue**: `cmd_distlib` in
`cbt/commands.cyr` wrote an explicit `\n` after the header AND
the per-module loop's opener started with `\n# --- ...`, so two
blanks ended up before the first module marker. Separately, the
`include`-strip step removed include lines but not their
surrounding blanks, leaving adjacent blanks at section-comment
boundaries (e.g. `# ── Stdlib ──` + blank + 6 stripped includes
+ blank + `# ── Modules ──` collapsed to a double-blank).
Fix: track `prev_blank` across writes; collapse blank-after-blank
to a single blank. Verified on patra 1.10.3: bundle 5130 → 5128
lines; `cyrlint dist/patra.cyr` clean (0 warnings).

**Scope discipline**: the bug A class (raw `syscall(N, ...)` with
x86 number) exists in many other places under `cbt/*.cyr` and
`programs/*.cyr`. Out of scope for .9 per the v6.0.2 finding's
specific complaint (argv dispatch). Will surface command-by-command
as those commands get run on aarch64; filing as a follow-up rather
than widening the slot ([[feedback_no_unilateral_scope_decisions]]).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (no emit
  change — all fixes are in lib/args, cbt/cyrius wrapper, and
  cbt/commands).
- cycc_aarch64 cross **byte-identical at 574,664 B**.
- cycc-native-aarch64 **byte-identical at 683,936 B**.
- build/cyrius wrapper grew (distlib + args + SYS_EXIT logic).
- `scripts/check.sh` **82/82**.
- Pi smoke: aarch64 cyrius wrapper dispatches all commands
  correctly + propagates exit codes.

Memory pin: [`project_v6_0_2_cross_host_smoke_findings`] (item 1
of the v6.0.2 cross-host smoke now closed; items 2 + 3 still
open — Mach-O cross-emitter mmap-fail on Linux, Windows
lock-hash gap).

v6.0.x shape going forward (post-.9):
  - .10–.14: Mini-arc A (TLS scaffold/record/framing/key/cipher)
  - .15–.22: Mini-arc B (TLS 1.3 client)
  - .23–.28: Mini-arc C (TLS 1.3 server)
  - .29–.34: Mini-arc D (TLS 1.2 backport)
  - .35–.37: Mini-arc E (consumer wiring + arc closeout)
  - .38: cyrius tests plural verb
  - .39: TOML [section] single-bracket
  - .40–.44: back-end remaining (5 slots, user picks)
  - .45: cycle closeout

## Session close — 2026-05-28 (.8 ship — backend module collapse)

Closing **v6.0.8**, the v6.0-runway "backend module collapse where
viable" item. Established `src/backend/common/` as the home for
truly-shared backend helpers; moved ~80 LoC of genuinely duplicated
code out of per-backend files.

**Honest scope finding**: the audit at slot entry showed that the
parallel `src/backend/x86/` and `src/backend/aarch64/` directories
share ~133 fn NAMES (`ECMPR`, `EJCC`, `EMOVRA_RDX`, …) but those are
the deliberate cross-arch API surface — same names, arch-specific
bodies. The genuinely collapsible code was much narrower than the
roadmap's "where viable" wording suggested. User picked "all 5
candidates" — the conservative cut would have been even smaller
(~40 LoC of byte-identical bodies).

**Two new files in src/backend/common/**:

1. `tokens.cyr` — `TOKTYP`, `TOKVAL`, `PEEKT`, `PEEKV` (4 token-stream
   accessors that were byte-identical in x86 + aarch64 + cx).
   3 copies → 1.
2. `runtime.cyr` — `_env_scratch`, `_read_env`, `_prof_clock_ns`,
   `RECFIX`. Previously 2 copies (x86 + aarch64) that diverged in
   small ways. Unified:
   - `_prof_clock_ns`: `#ifdef CYRIUS_ARCH_X86 / AARCH64` selects
     syscall 228 (x86_64) vs 113 (aarch64) inside the existing
     `#ifdef CYRIUS_TARGET_LINUX` block.
   - `_read_env`: shim form `if (SYS_OPEN == 2) {direct open} else
     {openat AT_FDCWD}` works for both archs (x86 path stays fast).
   - `RECFIX`: aarch64's better-error-message variant (uses `PRNUM`
     to show actual count, not just the cap) is the canonical one.
   - cx kept its own `RECFIX` (cap 1048576 / region 0x150B000) and
     `_read_env` stub — only token helpers shared.

**Include-order discipline**: shared common files MUST precede the
arch-specific emit/fixup includes in each `main_*.cyr` because the
backend files call `_read_env`, `RECFIX`, and `PEEKT/V` internally
during their top-level execution. Established the pattern in all 6
variants this slot.

**Gate rewire**: `_cx_token_offsets_gate` (v5.7.28) previously read
three per-backend `emit.cyr` files and ran a case for each, asserting
their TOKTYP/TOKVAL hex offsets matched the lex.cyr writes.
Post-collapse, one canonical source — read `common/tokens.cyr` once.
Same invariant, less surface.

**Mechanical gates green**:
- cycc x86 self-host **byte-identical at 885,024 B** (+168 B over
  v6.0.7's 884,856 — counted as honest growth-tax for the unified
  `_prof_clock_ns`'s extra `#ifdef` branches; aarch64 added a
  CYRIUS_ARCH_AARCH64 case the x86 file didn't have).
- cycc_aarch64 cross **byte-identical at 574,664 B** (-16 B).
- cycc-native-aarch64 **byte-identical at 683,936 B** (no change —
  the unified runtime helpers only affect the cross-compiler's
  INTERNAL codepaths, not the aarch64 instructions it emits).
- `scripts/check.sh` **82/82**.

**v6.0.x cycle pause point reached**: the original pinned sequence
.2 → .8 is complete (stdlib pin refresh, two codegen P1s, the TS
scripting papercut bundle, the alloc/vec mini-arc, the backend
collapse). Per user direction 2026-05-28, the next slot **re-evaluates
the cycle** + decides on placement of the native TLS arc (pulled
forward from v6.2.x; lands once sandhi + projects-waiting-on-TLS
prereqs are met — see [[project_native_tls_arc_v6_2_x]]).

Memory pin: [`project_v6_0_2_3_4_slot_sequence`] (.8 = backend
module collapse done; v6.0.x .2-.8 mini-arc complete).

## Session close — 2026-05-28 (.7 ship — return-patch vec conversion + native binary resurrection)

Closing **v6.0.7**, the second half of the return-patch mini-arc and
the resurrection of `build/cycc-native-aarch64` from doc-only ghost
to actually-committed binary.

**Conversion (primary)**: 12 push sites + 3 read-backs + closure
save/restore + inline save/restore + per-fn-start reset migrated from
the fixed 256-slot array at `S + 0x18DA20` to `rp_vec`
(`lib/vec.cyr`). `GRPC`/`SRPC` accessors deleted from `util.cyr:128`.
The "too many return statements (max 256)" diagnostic is gone; the
new ceiling is alloc heap (~131k returns per fn at 8 B each). Option
A reuse via `vec_truncate(rp_vec, 0)` at each fn-start keeps memory
bounded at the high-water mark of the largest fn — not the cumulative
product — which matters under the bump allocator (DoS surface
otherwise on malicious input).

**`lib/vec.cyr::vec_truncate(v, new_len)`** added as the bounded-
reset primitive. Preserves capacity so subsequent pushes reuse the
data buffer.

**Cross-arch**: all 6 `src/main_*.cyr` variants wired with the same
shape (alloc/vec includes BEFORE parse.cyr; `var rp_vec = 0;` forward
declaration; `alloc_init()` + `rp_vec = vec_new()` post-
HEAP_INIT_SCRATCH). Newly wired this slot: `main_aarch64_macho.cyr`,
`main_aarch64_native.cyr`, `main_cx.cyr`, `main_win.cyr`. The
main.cyr + main_aarch64.cyr (v6.0.6) wirings re-ordered to put alloc/
vec BEFORE parse.cyr include — necessary so converted vec_push/get/
len/truncate call sites resolve at parse time.

**Forward-decl gotcha**: `var rp_vec = vec_new();` at the
post-HEAP_INIT_SCRATCH point failed at parse with
`undefined variable 'rp_vec'` from parse_expr.cyr fn bodies. Cyrius
pre-scan registers globals BEFORE the parse pass, but the include of
parse.cyr happens AT include-time, which is BEFORE the
post-HEAP_INIT_SCRATCH var declaration. Split to forward decl
(`var rp_vec = 0;` BEFORE parse.cyr include) + runtime assignment
(`rp_vec = vec_new();` AFTER alloc_init) — same pattern other
forward-referenced globals use implicitly when their type is integer.

**Native binary resurrection**: `build/cycc-native-aarch64` was a
doc/policy ghost — CLAUDE.md DO NOT list said "needed for self-hosting
on ARM hardware (generated by `cyrius pulsar`)", `.gitignore`
whitelisted the path, but the binary was never committed in git
history and `cyrius pulsar`'s build chain didn't produce it. Source
`src/main_aarch64_native.cyr` was active throughout. This slot wires
it: `cyrius.cyml [release].cross_bins` adds the name; `cbt/pulsar.cyr`
Step 2 builds it via `set_arch(ARCH_AARCH64); compile(...)` using the
just-rebuilt `cycc_aarch64` cross; `scripts/install.sh` skips
`_rebuild_stale` since that uses x86 cycc. Binary committed at
**683,936 B** (`file` reports `ELF 64-bit LSB executable, ARM
aarch64`).

**Mechanical gates green**:
- cycc x86 self-host **byte-identical 884,856 B** (-1,576 B over .6 —
  push-site collapse). Negative growth-tax this slot, despite adding
  alloc/vec call surface to 4 more main variants.
- cycc_aarch64 cross **byte-identical 574,680 B** (-1,576 B).
- cycc-native-aarch64 **683,936 B** (newly committed; ARM aarch64).
- `scripts/check.sh` **82/82** — `return_cap_removed.tcyr` (260
  returns) joins the Test Suite walk; api-surface snapshot refreshed
  to 2,767 fns (vec_truncate added).

**Heap-map dead region**: `[0x18DA20..0x18E220)` (2 KB ret_patches
array) + the counter slot at `0x18E220` remain in the layout but are
unwritten. Flagged for v6.x closeout heap-map sweep per user
direction 2026-05-20 ("if needed collapse it otherwise closeouts
should focus on those kind of cleanups").

Memory pins: [`project_v6_0_2_3_4_slot_sequence`] (mini-arc step 2/2
done; .8 = backend module collapse next).

## Session close — 2026-05-28 (.6 ship — alloc + vec pull-in, mini-arc step 1/2)

Closing **v6.0.6**, the first half of the return-patch-buffer → vec
mini-arc. Folded `lib/alloc.cyr` (+ transitive `lib/fnptr.cyr`,
~1.4k LoC active) and `lib/vec.cyr` into both `src/main.cyr` and
`src/main_aarch64.cyr`; added explicit `alloc_init()` + `var rp_vec =
vec_new()` at parser init right after `_HEAP_INIT_SCRATCH(S)`. Zero
behavior change — the fixed 256-slot `ret_patches` array at `S +
0x18DA20` is still the active storage. **Mini-arc step 2 (the
conversion itself) lands at v6.0.7.**

**Preprocessor mechanics**: cycc's own preprocessor already
`PP_PREDEFINE`s `CYRIUS_TARGET_LINUX` + `CYRIUS_ARCH_X86` at top-level
(`src/main.cyr:674,738`), so alloc.cyr's Linux brk branch and fnptr.cyr's
x86 SysV branch resolve naturally during the self-build. The aarch64
cross-compiler binary is x86-hosted so the same defines fire. No manual
`#define` lines needed in the entry files.

**Heap layering**: cycc's existing fixed-heap region runs `[S,
S+0x4D9D000)` (~78 MB) for compiler scratch + token tables + fn tables.
`alloc_init()` runs syscall(12, 0) which returns the post-extension
brk, sets `_heap_base` to that, and extends another 1 MB on top. The
alloc heap therefore lives at `[S+0x4D9D000, S+0x4E9D000)`, fully
disjoint from the fixed-heap layout.

**Mechanical gates green:**
- cycc self-host **byte-identical 886,432 B** on x86 (+9,816 B over .5's
  876,616). Growth-tax bookkept per
  [[feedback_perf_deltas_growth_tax_default]] — ~1.4k LoC of new code,
  not a regression to bisect.
- cycc_aarch64 cross-compile **byte-identical 576,256 B** (+9,840 B).
- `scripts/check.sh` **82/82**, no new gates this slot. The behavior
  change + its regression gate land in .7.

**DCE bookkeeping**: x86 reports 71 unreachable fns (27,777 B), aarch64
113 — both are the freshly-included alloc/vec/fnptr surface that v6.0.6
doesn't yet call. They become reachable when v6.0.7 swaps in
`vec_push(rp_vec, ...)` at the 9 enforcement sites.

Memory pin: [`project_v6_0_2_3_4_slot_sequence`] (.6 shipped — mini-arc
step 1 of 2 done; .7 = the conversion).

## Session close — 2026-05-28 (.5 ship — TS scripting papercut bundle)

Closing **v6.0.5**, the three near-term TS scripting papercuts filed by
secureyeoman's `yeo-cy-test` port viability probe
(`docs/development/issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`).
Bugs 1 + 3 reproduced + fixed; bug 2 didn't reproduce on v6.0.4 — wiring
was correct since 2026-04-16; gated as an invariant.

**Bug 1 — `ts_test_runner` truncates `cycc` → `cyc`:** four v6.0.0
rename-drift length args in `programs/ts_test_runner.cyr` (the `cc5` → `cycc`
rename added 1 byte but `memcpy` / `syscall` len args weren't bumped):
the `cc_path` memcpy (16→17), the `store8` NUL offset (+16→+17), the
"not found at " error line (24→25), and two help-text lines (51→52 and
39→40). Same off-by-one class as the v6.0.1 lex skip-prefix bug. Out-of-
the-box `ts_test_runner` couldn't find the compiler on a fresh v6.0.0+
install. Exit-code wiring was already correct (`syscall(60, rc)` at
line 254); the filing's "exits 0" claim didn't reproduce locally.

**Bug 3 — `cycc --parse-ts <file>` blocks on stdin:** `src/main.cyr`'s
cmdline parser saw `--parse-ts` / `--lex-ts` but discarded the path arg
that followed; the compiler then read stdin unconditionally and hung in
no-tty contexts (yeo-cy-test reported a 17-min orphan holding a lock).
Fix: track `_ts_expect_path` after a TS mode flag, capture the next
non-flag arg as `_ts_input_path` (pointer into the file-scope `_vbuf`),
and open that file instead of stdin in the read loop. Backward-compatible
with all `dup2(fd, 0)` callers (no path arg → stays on stdin).

**Bug 2 — `cyrius build` exit-0 on compile failure (gated, not fixed):**
empirical premise-check across `cmd_build`, `--strict`, `-q`,
stdout-suppressed, and bare invocation all exit 1 on v6.0.4. `cmd_build`
returns `compile()`'s nonzero result directly (unchanged since
2026-04-16), `main()` propagates, `syscall(60, exit_code)` does the right
thing. The filer's environment likely wrapped the call in a shell that
masked the exit code. Locked in via `_build_exit_nonzero_gate` —
a future refactor that silently drops the nonzero status will go red.

**Gates added (check.sh 80 → 82):**
- `_build_exit_nonzero_gate` — `cyrius build` on a broken source exits ≠ 0.
- `_ts_path_arg_gate` — `cycc --parse-ts <valid-file>` with **invalid TS
  piped to stdin** exits 0 (proves the path arg path is taken, not stdin).

**Mechanical gates green:** cycc self-host **byte-identical 876,616 B**
(+1032 B over v6.0.4 — the bug 3 cmdline-parser + open-file wiring);
check.sh **82/82**.

Memory pin: this slot fulfils the "TS front-end scripting papercuts"
near-term entry from `docs/development/roadmap.md` v6.0.x Planned list.

## Session close — 2026-05-27 (.4 ship — kybernet aarch64 codegen-hang fixed + stdlib refresh)

Closing **v6.0.4**, the kybernet aarch64 codegen-hang + DCE correctness
audit, plus the v6.0.x stdlib refresh (sigil 3.5.5, patra 1.10.3).

**Root cause (corrected vs filing):** the aarch64 DCE reachability pass
(`src/backend/aarch64/fixup.cyr`, added **v5.11.59** — NOT the 6.0.0 rename
the filing blamed) used `GFCNT(S)` (fixup count, 9903 for kybernet) where
it needed `GFNC(S)` (fn count, 3372). The 8192-slot fn-start hash
overflowed → the uncapped probe loop spun forever (99.9% CPU, no output).
**aarch64-only** (x86 used GFNC), **size-dependent** (>8192 fixups), and
also **corrupted reachability** on smaller units (cycc-self-aarch64: 1701
unreachable vs x86's 37). `cycc_aarch64` is an **x86-hosted cross-compiler**,
so the hang reproduced + was fixed entirely on x86 — no Pi/qemu needed.

**Fix:** one accessor, `var fnc = GFNC(S)`. kybernet aarch64 cross-build now
~1-2s, valid ELF; unreachable counts match x86.

**Also shipped:**
- DCE `live[]` bitmap 4096 → 8192-fn cap (both arches; latent OOB >4096 fns).
- `CYRIUS_DEBUG_PHASES=1` DCE-pass markers (cross-arch, env-gated → byte-identical).
- `_dce_fn_count_gate` regression gate (check.sh 79 → 80).
- `programs/check.cyr` S64→store64 — pre-existing undefined-fn `ud2` that
  SIGILL'd the doc-size gate on a fresh check-binary build.
- `lib/audit_walk.cyr`: recognize `-- bundled distribution` marker so
  upstream-self-generated dists (sigil) skip fmt/lint like distlib bundles.
- sigil 3.1.1 → 3.5.5 (+ChaCha20-Poly1305 + X25519; +275 fns, no public removals);
  patra 1.9.4 → 1.10.3 (+8 fns); `docs/api-surface.snapshot` regen (2766 fns).

**Mechanical gates green:** cycc self-host **byte-identical 875,584 B**;
check.sh **80/80**; kybernet aarch64 cross-build completes with a valid ELF.

**Post-bump CI fmt fix (in the released tag, commit `41a3beea`):** the
release CI's fmt gate went red on `lib/sigil.cyr` — sigil's dist tracks
its own continuation-indent baseline, and the fmt/lint *skip*-detection
recognized only `# Generated by: cyrius distlib` / `# Bundled distribution
of `, missing sigil's `# <name>.cyr -- bundled distribution` marker. The
.4 `lib/audit_walk.cyr` change fixed check.sh but didn't propagate to the
two CI mirrors. Added `-- bundled distribution` to all three —
`lib/audit_walk.cyr`, `scripts/lib/audit-walk.sh`, and the inline greps in
`.github/workflows/ci.yml` (fmt + lint + doc). 10 bundles skip, 71
cyrius-authored checked. CI green.

**RELEASED** — v6.0.4 tagged 2026-05-27 (tag on `41a3beea`, incl. the CI fix).

**Deferred (non-blocking, combine opportunistically — user direction
2026-05-27):** `cyrius distlib` leaves double-blank lines at the
header→first-module seam + include-strip residue → cosmetic cyrlint
warnings on generated bundles (filed
`docs/development/issues/2026-05-27-cyrius-distlib-blank-lines.md`).
**CI-unaffected** (bundles are skipped). Fix = blank-collapse in
`cmd_distlib` (`cbt/commands.cyr`); fold it into adjacent code work that
already touches distlib rather than a dedicated slot
([[feedback_combine_nonblocking_fixes_opportunistically]]). Separate
still-open item: the aarch64 `cyrius` **wrapper** argv dispatch (v6.0.2
cross-host finding).

Memory pin: [`project_v6_0_2_3_4_slot_sequence`] (.4 released — sequence at .5 next).

## Session close — 2026-05-27 (.3 ship — str_from overload-misroute codegen P1 fixed)

Closing **v6.0.3**, the nous-0001 codegen P1 — root-caused to a different
cause than the filing claimed.

**Root cause (corrected):** the v5.10.25 overload dispatcher
(`src/frontend/parse_fn.cyr`, `PARSE_FNCALL` ~803) auto-routed
`str_from(<i64-returning-call>)` → `str_from_int`. Since cyrius is
i64-everywhere (ADR-002), an i64 from `vec_get(): i64` is a cstr POINTER,
so `str_from(vec_get(..))` stringified the pointer's decimal instead of
wrapping the cstr → corrupted cstr map keys → DFS cycle detection read
acyclic → silently-wrong "no cycle". **NOT** typed-vec_get codegen: premise-
check disproved both the filing's bisection (stripping `: i64` doesn't help
— i64 is the default return) and its fix (local-cache doesn't help). Also
ruled out inlining (disabled) + regalloc (bug persists with it off).

**Fix (Option A, user-chosen):** gate the `_int` auto-route on the base fn's
return type — route only for output-style bases (i64 return, e.g. println);
not for data-producing bases (non-i64 return, e.g. `str_from: Str`) where a
wrong conversion corrupts data. `str_from` is the only such stdlib base;
`GFRS(S, fi) == -8` gate is surgical. Also corrected latent misroutes in
`lib/yukti.cyr` (GPT/MBR `*_to_str(): i64`) + `check.cyr` doc-path gates.

**Mechanical gates green:** self-host **byte-identical at 874,280 B**
(+48 B over v6.0.2's 874,232 — the gate code; cycc's own source doesn't use
the misroute pattern so step-1 fixpoint held). `scripts/check.sh` **79/79**
incl. new regression `tests/tcyr/str_from_ptr_overload.tcyr` (5 asserts).
0 downstream consumer sites affected; nous can revert their 0001 de-nest
workaround on bumping to v6.0.3.

Memory pin: [`project_nous_typed_vec_get_nested_miscompile`] (corrected
root cause + resolution).

## Session close — 2026-05-27 (.2 ship — cyrius deps correct-lock fix + stdlib pins verified)

Closing **v6.0.2**, the dual-item slot.

**Item 1 — stdlib pin refresh (verify-only).** The parallel
stdlib-walk-to-6.0.1 sweep already landed: sigil / sakshi / patra /
sankoch / niyama / vani / yukti / agnosys all pin `cyrius = "6.0.1"`.
mabda holds at `6.0.0` per the rc.4 exception. cyrius's own
`cyrius.cyml` has only `[deps.mabda]` (held) — no manifest edit needed.

**Item 2 — `cyrius deps` correct-lock fix.** `cyrius.lock` had been
empty ecosystem-wide since **v5.11.8** (cyrius/kybernet/argonaut all
0 bytes): `cmd_deps_lock` filtered by symlink (`readlink`), but v5.11.8
switched resolution symlink→file-copy, so every resolved dep was
skipped. Fix (`cbt/deps.cyr`): `cmd_deps_lock` now hashes every `.cyr`
under `lib/` recursively (new `_deps_lock_dir`, drops the symlink
filter); new `_dep_is_cyrius_source_repo()` (matches `[package] name =
"cyrius"`) skips the self-referential lock in cyrius's own repo to
avoid churning the tracked `cyrius.lock`. New `_deps_lock_gate`
regression gate (`programs/check.cyr`) — the bug survived ~60 patches
because nothing tested it.

**Mechanical gates green:** `scripts/check.sh` **79/79** (was 78; +1
for the new gate). cycc self-host unaffected by the bump only (lock fix
is wrapper-side, not cycc). `cyrius.lock` stays 0 bytes in this repo
(source-repo skip; no churn through check.sh). Verified the fix in a
downstream sandbox: non-empty lock incl. `unicode/` subdir, `--verify`
round-trips.

**Cross-host smoke — blocked by toolchain, findings captured.** A live
cross-host lock smoke couldn't run: neither pi (aarch64) nor ecb (macOS)
has a usable native `cycc`, and the lock fix is host-agnostic logic
anyway (verified-by-construction; `sha256sum` + `/bin/sh` confirmed on
both). Three findings routed forward
([`project_v6_0_2_cross_host_smoke_findings`]): (1) the aarch64 `cyrius`
**wrapper** argv dispatch is broken (all commands → usage; suspect
`lib/args.cyr` aarch64 path) → **v6.0.4** evidence the aarch64 problem
is broader than the kybernet hang; (2) the Mach-O cross-emitter dies
`mmap heap init failed` on Linux; (3) Windows `deps --lock` can't hash
(no `sha256sum`/`/bin/sh`) → deps-portability holdover.

Memory pins: [`project_v6_0_2_3_4_slot_sequence`] (.2 of the .2–.7
sequence), [`project_v6_0_2_cross_host_smoke_findings`].

## Session close — 2026-05-19 (.1 ship — stdlib-resolution hotfix bundle)

Closing **v6.0.1** as same-day hotfix for two stdlib-resolution
path bugs surfaced by today's v6.0.0 cycle-open:

**Filed by**: agnosticos (gnoboot 0.2.0 UEFI #UD on first
firmware-call site; `objdump` showed `ud2 ud2 nop` sentinels
where `call rel32` should have been). Issue file moved into
`docs/development/issues/2026-05-19-cycc-6.0.0-uefi-fncall-ud2-emit.md`.

**Root cause 1** (compiler, src/frontend/lex.cyr):
`var vp = 4` (`_init_cyrius_lib`) + `var _pd_self_start = 4`
(`_check_cyml_pin_drift`) skipped the first 4 chars of
`_VERSION_STR_CYCC`. Correct for `"cc5 "` (4 chars), off-by-one
for `"cycc "` (5 chars). Effects:

- Version-pinned stdlib fallback path corrupted to
  `$HOME/.cyrius/versions/ <v>/lib/` (leading space). Consumers
  without a vendored `./lib/` couldn't resolve `include "lib/X.cyr"`.
  Cycc emitted `ud2 ud2 nop` placeholders + exit 0.
- Pin-drift warning fired even when cyml pin matched cycc
  version (length-mismatch short-circuit).

**Root cause 2** (wrapper, cbt/deps.cyr): `sys_mkdir("lib", 0x1ED)`
unconditional at cmd_deps entry tripped `_dep_find_stdlib_dir`
priority (a) for ANY downstream repo with `src/main.cyr` + non-
empty stdlib pin. Pre-existing since v5.11.17; latent because no
such consumer had been tested through `cyrius deps` until gnoboot
adopted `stdlib = ["fnptr"]` at this slot.

**Fixes**:
- `src/frontend/lex.cyr` — both 4→5; comment text updated;
  pin-drift warning syscall length 12→13 to preserve spacing.
- `cbt/deps.cyr` — removed upfront `sys_mkdir("lib", ...)`;
  `_dep_copy_file` prefix-walk already mkdir's lazily.
- `programs/check.cyr` — two new regression gates:
  `_efi_stdlib_fallback_gate` + `_deps_downstream_src_main_gate`.

**Coordinated**: `gnoboot/cyrius.cyml` now declares
`stdlib = ["fnptr"]` (belt-and-suspenders alongside the cycc-side
fallback fix).

**Mechanical gates**:
- cycc self-host **byte-identical at 874,232 B** (same as v6.0.0).
- `scripts/check.sh` **78/78** (was 76/76 at v6.0.0; +2 for the
  new regression gates).
- gnoboot `BOOTX64.EFI` 33,792 B PE32+ with **0 `0F 0B 0F 0B 90`
  sentinels** (was 32 across 16 paired sites at v6.0.0).

Memory pin: [`project_v6_0_1_skip_prefix_fix`].

## Session close — 2026-05-19 (v6.0.0 OPEN — two-binary rename ceremony)

Opening **v6.0.0** with the two-binary rename ceremony per
user direction post-v5.11.69 ship: ".69 is out; lets 6.0.0
this baby thinking I want to name it cycc - so its seed →
cyrc → cycc (cyrius computer compiler)" — then expanded to
rename the bootstrap binary too: "seed (asm) → cybs (Cyrius
Bootstrap) → cycc (Cyrius Computer Compiler)".

**Rename**:
- `cyrc` → **`cybs`** (Cyrius Bootstrap)
- `cc5`  → **`cycc`** (Cyrius Computer Compiler)

Bootstrap chain is now `seed (asm) → cybs → cycc`.

**Surface**: ~2,100 occurrences across ~157 files. Categorized
sed preserved historical narrative — v5.x CHANGELOG entries,
archives, completed-phases, vidya retros stay as historical
anchor text. Current-state code + canonical-current docs flipped.

**Byte-length math**: `src/version_str.cyr` had its
`_VERSION_LEN_CC5*` byte counts calculated assuming "cc5 "
(4 chars + \n = 5). After sed-renaming the strings to "cycc "
(5 chars + \n = 6), the lengths needed +1 each. Caught
because sed-only update would have truncated `cycc --version`
output. Fix: rename vars `_VERSION_STR_CC5*` →
`_VERSION_STR_CYCC*` + update length calcs in
`scripts/version-bump.sh` template (`LEN_CYCC = ${#NEW} + 6`
etc.). All 3 consumers (main.cyr, main_win.cyr, lex.cyr)
updated to match new var names.

**Back-compat (v6.0.x window only)**:
- `scripts/install.sh` ships `cc5 → cycc`, `cyrc → cybs`,
  `cc5_aarch64 → cycc_aarch64`, `cc5_win → cycc_win`
  symlinks in `~/.cyrius/versions/<v>/bin/`.
- `cbt/core.cyr` compiler-lookup tries `cycc` first, falls
  back to `cc5` (same for `cybs`/`cyrc`).
- Both drop at v6.1.0.

**Surprise during smoke**: `cyrius capacity` failed against
v5.11.69 install snapshot — new cyrius binary couldn't find
`cycc` because `~/.cyrius/bin/cycc` doesn't exist yet (snapshot
has `cc5`). Added back-compat fallback in `cbt/core.cyr` so the
new cyrius works against pre-rename and post-rename snapshots.

**Mechanical gates**:
- cycc self-host **byte-identical at 874,240 B** (was cc5
  874,232 B at v5.11.69; +8 B for longer binary-name strings
  baked into version_str.cyr).
- `scripts/build-cycc-verify.sh` (renamed from
  build-cc5-verify.sh): VERIFY OK end-to-end.
- 3-step bootstrap: /tmp/cc5_v5_11_69_PRESERVED (saved
  pre-rename binary) → cycc_a → cycc_b == cycc_a.
- `check.sh` **76/76**; `cyrius test` **152/152**.

**v6.0.x roadmap remaining** (carry-forward from v5.x close
band — 5 accompanying-refactor items pulled forward into
subsequent v6.0.x slots per "Big Heavy One Thing"):
- Dead-code careful sweep
- `_TARGET_*` flag consolidation
- Backend module collapse
- Byte-array literal peephole
- Return-patch buffer dynamic conversion

Memory pins:
- [`project_v6_0_0_cycc_cybs_rename`] — rename ceremony shape.
- [`project_v5_11_x_closeout_at_40`] — v5.x retired.

## Session close — 2026-05-19 (.69 ship — v5.x CYCLE CLOSED)

Closing **v5.11.69** as the **FINAL v5.x patch**. v5.11.x
ran 70 slots across 2026-05-09 → 2026-05-19 — the longest
minor in Cyrius history (prior record v5.7.x at 49 slots).

Closeout bundle:
- **`scripts/shims/`** for the 3 CLI-implementation-detail
  bash scripts (cyrius-init/port/repl, 1,775 LOC). They're
  invoked by `cyrius <verb>`, not by users. Moving them
  out of top-level `scripts/` corrects the mis-signal.
  User pushed back on initial "leave as-is" audit
  recommendation: "you sure about scripts cause... most
  of those command got folded into cyrius proper." Re-
  audit surfaced this.
- **`docs/guides/`** subdirectory with 4 guide-shape
  files (tutorial, editor-integration, faq, cyrius-guide).
  Cross-refs updated across README + CLAUDE.md + roadmap
  + check.cyr + architecture docs + 2 archive docs.
- **Doc sweep**: doc-health.md last-refresh header
  rewritten for cycle-close framing; roadmap-old.md
  v6.0.0 accompanying-refactor list — 5 items struck
  through as done in v5.x close band.
- **Vidya refresh** per CLAUDE.md Closeout Pass §11:
  language/index.cyml header (verified-on 5.11.59 →
  5.11.69, cycle-close framing); v511x.cyml new
  cycle-close retro entry covering .50-.69 with process
  patterns; gotchas.cyml + 2 entries (gvar-init-order
  kmode + CVE-05 mangle-path magic-budget).

**Mabda 3.0 fold DROPPED** from v5.11.x at user direction
post-.67 ship. Mabda stays as git [deps.*] resolution
through v6.x or until re-pinned. Class B FFI / wgpu
fncall6 ABI work continues to track in v6.4.x.

**v6.0-runway scoreboard (cycle CLOSE)**: 5 v6.0.0
accompanying-refactor items absorbed into v5.x close —
CVE-05 (.65), bridge retirement (.66), build-cc5-verify.sh
skeleton (.67), cc3-era residue load-bearing portion (.67),
heap-map full reorganization (.68). 5 items carry forward
into v6.0.x (dead-code sweep, _TARGET_* consolidation,
backend module collapse, byte-array literal peephole,
return-patch-to-vec).

**Mechanical gates green**: cc5 byte-identical at **874,232 B**
(no compile-path changes in .69). check.sh 76/76; cyrius
test 152/152. cyrius init/port/repl smoke-tested via the
new scripts/shims/ path. build-cc5-verify.sh reports
VERIFY OK end-to-end.

**v5.11.x cycle stats**:
- 70 slots over 11 days
- cc5: 804,472 → 874,232 B (+69,760 B / +8.7%)
- check.sh: 65 → 76 gates (+11)
- cyrius test: 149 → 152 tcyr (+3)

Next: v6.0.0 cycle opens. First slot is the `cc5 → cyc`
rename (the v6.0.0 line item). Roadmap.md gets the v6.x
pull-forward from roadmap-old.md during cycle-open
doc-pass.

Memory pins:
- [`project_v5_11_x_closeout_at_40`] — v5.11.x retired.
- [`project_v5_11_69_closeout_bundle`] — .69 slot shape.

## Session close — 2026-05-19 (.68 ship — heap-map full reorg, the true v5.x closeout engineering)

Closing **v5.11.68** with the heap-map full reorganization
pinned at v5.8.61 ship as the "last-minor-before-v6.0
effort." Four documented closeable gaps closed; brk shrunk
**0x56AD000 → 0x4D9D000** (-9.06 MB / 86.6 MB → 77.6 MB
total heap). 13.3 MB TS frontend reservation preserved.

- **Closed gaps**: A (2.24 MB str_data→codebuf) + B (6.00
  MB output_buf→struct_ftypes) + C (448 KB struct_ftypes
  →struct_fnames) + D (448 KB struct_fnames→fn_param_cstring
  _mask) = 9.06 MB reclaimed.
- **Cascade shifts**: Group 1 (codebuf + output_buf, -2.24
  MB) → Group 2 (struct_ftypes, -8.19 MB) → Group 3
  (struct_fnames, -8.62 MB) → Group 4 (25+ regions through
  preprocess_out, -9.06 MB). Each region shifts by the sum
  of upstream gap sizes.
- **Edits**: ~32 distinct hex constants replace_all'd across
  20 files in src/; heap-map comment blocks in 6 main_*.cyr
  refreshed; Windows MMAP shrunk 0x5800000 → 0x4F00000
  (-9.06 MB tracking brk reduction); src/common/util.cyr
  historical comments updated for post-.68 layout.
- **Two-step bootstrap**: old cc5 (.67 layout) → cc5_a (.68
  layout) → cc5_b == cc5_a byte-identical at **874,232 B**
  (unchanged — pure offset relocation, hex widths identical).
  cc5_aarch64 564,456 B + cc5_win 686,632 B also unchanged.
- **Mechanical gates green**: heapmap.sh 99 regions / 0
  overlaps / 0 warnings, layout monotonic 0x00000 → 0x4D9D000
  with single 13.3 MB TS reservation preserved. `check.sh`
  **76/76**; `cyrius test` **152/152**; `scripts/build-cc5-
  verify.sh` reports VERIFY OK on first invocation post-reorg.

**v6.0-runway scoreboard (post-.68)**: five v6.0.0 items
absorbed — CVE-05 (.65), bridge retirement (.66), build-
cc5-verify.sh skeleton (.67), cc3-era residue load-bearing
portion (.67), heap-map full reorg (.68). One slot remains:
**.69 = another pre-6.0 item** (candidate TBD at slot entry).

Memory pins:
- [`project_v5_11_x_closeout_at_40`] — updated 2026-05-19
  to reflect mabda fold dropped + .69 absorbing another
  pre-6.0 item.

## Session close — 2026-05-19 (.67 ship — v6.0-runway triple-pull → double-pull after premise-check)

Closing **v5.11.67** with a v6.0-runway double-pull bundle:
`scripts/build-cc5-verify.sh` (formalizes the cc5 byte-
identical fixpoint verifier) + cc3-era residue cleanup
(ADR-005 substantive rewrite + doc-health + roadmap-old
self-references). Byte-array literal peephole moved out
to v6.0.x per user direction "put the pinned byte-array
into 6.0.x line of work now."

- **Premise-check at slot entry caught a no-op**: the
  third item in the originally-pitched triple-pull —
  `cyrius build --strict` wrapper plumbing — already
  shipped at v5.11.63 (cbt/build.cyr:130-142 +
  CHANGELOG [5.11.63]). Slot reshaped to double-pull;
  noted explicitly in CHANGELOG so future audits can
  cross-check.
- **build-cc5-verify.sh** (~100 LoC bash) — three
  invariants with distinct exit codes (1=stage_a compile
  failed, 2=fixpoint diverged, 3=stale build artifact).
  Renames to `scripts/build-cyc.sh` at v6.0.0 cut.
- **ADR-005 substantive rewrite** — was using `cc3`
  throughout an active ADR (predated v5.0.0 cc3 → cc5
  rename); rewritten with stage_a/stage_b convention so
  steps are unambiguous regardless of current binary
  name. Adds Tooling section pointing at the new
  verifier script.
- **README refreshed** — 823 KB → 874 KB compiler;
  79 → 81 stdlib modules; 149 → 152 tcyr; 72 → 76 gates;
  Compiler Architecture listing + Bootstrap Chain ASCII
  art updated post-bridge-retirement; "Bridge compiler
  (cyrc)" label corrected to "Bootstrap compiler (cyrc)"
  — cyrc has always been the bootstrap compiler, the
  "bridge" framing conflated it with the just-retired
  `src/bridge.cyr`.
- **Byte-array peephole moved to v6.0.x** — full scope
  + cross-arch plan preserved verbatim in
  roadmap-old.md's v6.0.0 accompanying-refactor section.
- **Mechanical gates green**: cc5 **byte-identical at
  874,232 B** (no compile-path changes — only docs +
  new standalone script). 3-step bootstrap converges.
  `check.sh` **76/76**; `cyrius test` **152/152**.
  `scripts/build-cc5-verify.sh` reports VERIFY OK
  end-to-end on first invocation.

**v6.0-runway scoreboard** (post-.67): three v6.0.0
accompanying-refactor items absorbed into v5.x close —
bridge retirement (.66), build-cyc.sh skeleton (.67),
cc3-era residue load-bearing portion (.67). Plus CVE-05
(.65). v6.0.0's surface shrinks by four line items.

**Remaining slots** to v5.x close: .68 (heap-map full
reorganization — the true closeout engineering work) +
.69 (conditional mabda 3.0 GA fold).

Memory pins:
- [`project_v5_11_67_triple_pull`] — double-pull after
  premise-check.
- [`project_byte_array_peephole_v6_0_x`] — peephole
  moved out.
- [`project_v5_11_67_return_patch_vec`] — pushed back
  to v6.0.x.

## Session close — 2026-05-19 (.66 ship — bridge-compiler retired; v6.0 march continues)

Closing **v5.11.66** with the deletion of `src/bridge.cyr`
(2,005 LoC). Second slot in the v6.0-runway band; absorbs
one of v6.0.0's pinned accompanying-refactor line items.

- **Audit-at-slot-entry**: bridge was never in the active
  bootstrap chain. `bootstrap/bootstrap.sh` produces
  `seed → cyrc → asm` directly; cc5 is built standalone.
  The Key Principle "seed → cyrc → bridge → cc5" was
  historical / aspirational wording, not actual.
- **Only active reference**: `scripts/bench-history.sh:162`
  treated `bridge.cyr` as a cc5 INPUT (compile-time bench
  target), not as a compiler. Deleted in the same slot.
- **API surface**: 150 `bridge::*` public-fn entries
  cleanly removed from `docs/api-surface.snapshot` via
  `cyrius api-surface --update` regeneration. Total fns
  drops 3,000 → 2,850.
- **Ecosystem cleanup**: `CLAUDE.md` project-structure
  listing + "Bootstrap chain integrity" Key Principle
  wording updated; `src/common/util.cyr:580` comment
  cleanup (drops "bridge.cyr has its own layout"
  parenthetical); `docs/adr/001-assembly-cornerstone.md:20`
  historical chain annotated; `docs/development/
  roadmap-old.md` v6.0.0 cleanup item struck and dated.
- **Mechanical gates green**: cc5 **byte-identical at
  874,232 B** (no change from .65 — bridge wasn't in any
  compile path). 3-step bootstrap converges. `check.sh`
  **76/76**; `cyrius test` **152/152**; `cyrius
  api-surface` gate passes on regenerated snapshot.

Bootstrap chain is now `seed → cyrc → cc5` cleanly — one
canonical compiler line (cc5), no historical intermediate.
v6.0.0's "accompanying refactor / cleanup" list shrinks
by one item.

Memory pins:
- [`project_v5_11_66_bridge_retirement`] — slot shape
  + audit findings (bridge never actually in active
  build path).

## Session close — 2026-05-19 (.65 ship — CVE-05 split forward; v6.0 march starts)

Closing **v5.11.65** with the CVE-05 tok_names mangle-
path write-boundary guard — first v6.0-runway slot;
split forward from .68 so the closeout slot stays a
pure heap-map layout reorg per "Big Heavy One Thing."

- **Audit-at-slot-entry premise check**: confirmed the
  bulk of CVE-05's surface was already covered by
  earlier work (CVE-06 for `str_data`, `EB()` on both
  arches for `codebuf` append, `LEXID`+`NPOS_GUARD` for
  the `tok_names` lex hot path). The actual remaining
  gap was the **mangle-path byte-copy loops** at 11
  sites using `NPOS_GUARD(S, 256)` as a magic-pessimistic
  budget that an over-long source identifier could
  silently exceed.
- **Larger pre-existing gap than expected**: the 4 non-
  x86 `main_*.cyr` variants (aarch64, aarch64_macho,
  aarch64_native, cx) had **no prior tok_names guard at
  all** on the use-alias path — the parallel x86
  `main.cyr` had the magic-256 NPOS_GUARD that the cross-
  arch variants never gained. Cross-arch propagation
  per [`feedback_cross_arch_propagation_mandatory`] —
  all 6 main_*.cyr variants treated in same slot.
- **Fix shape** (single uniform pattern, no new helper):
  pre-walk source identifier strlen(s); pass actual sum
  to `NPOS_GUARD` which already has the region cap
  check (`np + need >= 261872`). 11 sites updated:
  parse_decl.cyr `BUILD_METHOD_NAME`, parse_expr.cyr
  `BUILD_OP_NAME`, parse_fn.cyr `PARSE_FN_DEF`,
  parse_types.cyr variant-ctor × 2, 6× main_*.cyr
  use-alias.
- **Structural gate** `_cve05_guard_gate` (programs/
  check.cyr) scans the 10 affected source files for
  `NPOS_GUARD(S, 256)`, fails fast on any reappearance.
  Negative-tested at bring-up. check.sh **75 → 76**.
- **Mechanical gates green**: cc5 self-host byte-
  identical at **874,232 B** (+1,264 B vs .64 = the
  11 strlen-walks + NPOS_GUARD inserts). 3-step
  bootstrap converges. Cross-arch builds proportional:
  cc5_aarch64 **564,456 B** (+1,312 B), cc5_win
  **686,632 B** (+1,280 B); cc5_aarch64_macho /
  cc5_aarch64_native / cc5_cx build clean.
  `check.sh` **76/76**; `cyrius test` **152/152**.

Audit + roadmap updates: CVE-05 unpinned from .68 in
`docs/audit/2026-04-13-security-audit.md`, marked
shipped .65 with corrected scope. .68 roadmap entry
drops the CVE-05 batching language — closeout stays
a pure heap-map layout reorg.

Memory pins:
- [`project_v5_11_65_cve_05_split`] — v6.0-runway slot
  shape; CVE-05 split forward so .68 stays clean.
- [`feedback_cross_arch_propagation_mandatory`] — 4
  unguarded main_*.cyr variants were the bigger gap
  than the magic-256 x86 sites; all fixed in same slot.
- [`feedback_release_needs_code_not_just_docs`] —
  v6.0-runway slot ships real security code, not just
  doc reorg.

## Session close — 2026-05-18 (.64 ship — agnos gvar-init-order bug closed)

Closing **v5.11.64** with the static-init fix for top-
level `var X = INT_LITERAL ;` declarations. First slot
of the post-papercut absorber band; opened the same day
the agnos issue filing (`docs/development/issues/
2026-05-18-gvar-init-order-zero-reads.md`) landed.

- **Root cause**: in kmode==1, cyrius emits `[boot-shim
  asm] → [rest of PARSE_PROG] → [EMIT_GVAR_INITS]` at
  the entry. agnos kernel main body lives in PARSE_PROG
  and never returns; the gvar init stores after it never
  execute, so any fn called from main reads the BSS-zero
  default instead of the declared literal. Two load-
  bearing agnos cases (`XHCI_CMD_TIMEOUT_SPINS = 1e7`,
  `XHCI_EVT_RING_SEGMENT_SIZE = 256`) ate 10+ iron-burn
  attempts before the compiler-side root cause surfaced.
- **Fix shape (Option 1 from the issue, "the cleanest")**:
  PARSE_GVAR_REG detects `= INT_LITERAL ;` shape with
  positive non-zero RHS, records value in new
  `gvar_initval` table (0x1EC000), skips gvar_toks
  registration so EMIT_GVAR_INITS doesn't replay the
  runtime store. FIXUP populates per-var byte offsets
  in stable `gvar_byte_off` mirror (0x1B0000). Each
  EMIT_* path adds `_EMIT_GVAR_STATIC_INITS(S, O, bss_o)`
  after its var-area zero-fill to S64 literal bytes at
  the right offsets. Result: value is in the file image
  at first read; no runtime store needed.
- **Cross-arch coverage**: x86 EMITELF_KERNEL +
  EMITELF64_KERNEL + EMITELF_USER + EMITELF_SHARED +
  EMITELF_OBJ; aarch64 EMITELF + EMITELF_KERNEL; MachO
  x86 + ARM64; PE (EXE + EFI Application). cx
  bytecode opts out via `_TARGET_CX != 1` guard.
- **Shadow-declaration opt-out**: when `FINDVAR` finds
  an existing match for the new var name (shadow redecl),
  fall through to runtime-store. Caught during bring-up
  by the math_constants tcyr — mabda's `var F64_TWO = 0`
  shadowed by math's `var F64_TWO = 0x4000_0000_0000_
  0000` hit `EMIT_GVAR_INITS`'s FINDVAR-last-match
  semantics: mabda's runtime-store-of-zero targeted
  math's address, clobbering the new static-init bytes.
- **Verbatim repro green**: `kernel;` source with
  `var XHCI_CMD_TIMEOUT_SPINS = 10000000;` + helper fn
  reading it; binary inspection shows literal bytes
  `80 96 98 00` at file offset 0x140. Helper read
  returns 10000000.
- **Mechanical gates green**: cc5 self-host byte-
  identical at **872,952 B** (was 875,336 B; -2,384 B
  from eliminating runtime stores for cc5's own TS_TOK_*
  / TS_AST_* literal gvars in `src/frontend/ts/`).
  Three-step bootstrap converges at pass2 / pass3 byte-
  identical. `check.sh` **75/75**; `cyrius test` **152/150**
  (new `tests/tcyr/gvar_static_init.tcyr` with 11 sub-
  asserts).
- **Test update**: `_kmode_emit_order_gate`'s fixture
  changed from `var marker_var = 0xDEADBEEF;` (bare INT
  literal — now static-init, no `48 b9` byte sequence
  the gate looks for) to `var marker_var = 0xDEADBEE0 |
  0xF;` (arithmetic RHS — preserves runtime-store
  emit). Same value (0xDEADBEEF); v5.7.19 invariant
  continues to be enforced for cases where it still
  applies.
- **Cross-builds**: cc5_aarch64 **563,144 B**
  (+5,128 B), cc5_win **685,352 B** (+2,592 B); growth
  from new parser logic + helper fn + EMIT_* call sites.
  cc5_aarch64_macho / cc5_aarch64_native / cc5_cx all
  build clean.

Filing archived to
`docs/development/issues/archived/2026-05-18-gvar-init-
order-zero-reads.md` post-ship.

Heap layout addition (v5.11.68 closeout will consolidate
the band):

- `0x1B0000  gvar_byte_off [65536]` — 8192 × 8B prefix-
  sum mirror, FIXUP-time written / EMIT_*-time read.
  Lives in the free band between `fn_start_fcnt` end
  (0x1A6018) and `include_fnames` / `fn_names` start
  (0x1C0000) — clean in both main.cyr and main_aarch64
  heap maps.
- `0x1EC000  gvar_initval  [65536]` — 8192 × 8B per-gvar
  static-init literal. Uses v5.11.19's freed `fn_ret_sid`
  slot (relocated to 0x15A000 at .19 doubling).

Memory pins:
- [feedback_cross_arch_propagation_mandatory] — all
  arch paths handled in the same slot, no follow-up
  half-fix.
- [feedback_premise_check_at_slot_entry] — confirmed
  agnos repro on cc5 .63 before scoping (synthetic
  kmode source: `var X = N;` + fn reading X + top-
  level asm; pre-fix reads X as 0, post-fix as N).

## Session close — 2026-05-18 (.60 + .61 + .62 + .63 ship — commandress papercut band CLOSED 4/4)

Closing the session at **v5.11.63** after shipping the
full .60-.63 commandress absorber band in one session:

- **`lib/process.cyr` bug-fix pair (commandress Items 6
  + 7) shipped**. Item 6 (Medium): `_exec3`'s
  `var argv[4]` reserved 4 BYTES (not 4 entries) of
  stack and silently corrupted whatever sat after argv
  on every call — `run_capture("/bin/echo", "hello",
  0, ...)` returned 1 byte instead of 6, reproduced
  pre-fix on cc5 .59. Fixed to `var argv[40]` + `var
  envp[16]` per the byte-not-entry buffer contract; in-
  source comment block pins the contract above the fn.
  Item 7 (Low): four vec-based execs (`exec_capture`,
  `exec_env`, `exec_capture_str`, `exec_env_str`) were
  missing the stderr→/dev/null dup2 stanza that
  `run_capture` ships. All four now mirror
  `run_capture` (deliberate scope per user direction
  2026-05-18 — breaks cstr-family parity where `run`
  doesn't suppress, but matches the filing's explicit
  4-fn enumeration).
- **Premise check at slot entry**: confirmed Item 6
  reproducer manifests on cc5 5.11.59 before scoping.
  `/bin/echo hello` returned 1 byte (lone `\n`); post-
  fix returns 6 bytes (`hello\n`). Item 7 confirmed by
  code inspection (dup2 block visibly missing in all
  four target fns).
- **Scope clarification asked + answered**: cstr family
  asymmetry (`run` no-suppress vs `run_capture`
  suppress) made the "exec_capture family" pin
  ambiguous between 2 and 4 fns. User picked all 4 per
  the filing's enumeration. Noted in CHANGELOG +
  in-source comments.
- **Regression test**:
  `tests/tcyr/process_run_capture_args.tcyr` (new, 6
  sub-asserts) — single-arg / two-arg `run_capture`
  byte counts + `run` two-arg no-capture exit code.
  Skips cleanly when `/bin/echo` or `/bin/true` is
  missing. `cyrius test` now 151/150.
- **Mechanical gates green**: cc5 self-host byte-
  identical at **875,336 B** (unchanged from .59 —
  lib/process.cyr is not included by cc5);
  `check.sh` **75/75**; cross-compilers unchanged
  (cc5_aarch64 558,016 B; cc5_win 682,760 B).
- **Snapshot ping-pong avoided**: edits copied to
  `~/.cyrius/versions/5.11.59/lib/process.cyr` +
  `~/.cyrius/lib/process.cyr` before check.sh per
  CLAUDE.md mitigation; `install.sh --refresh-only`
  during version-bump replaced both with the .60
  snapshot.

**.61 ship details** —
`lib/toml.cyr::toml_parse_file` heap-alloc rewrite
(commandress Item 2). Pre-fix the fn declared a
256 KB on-fn-scope buffer (`var buf[262144]`) that
landed in every consumer's bss regardless of whether
the fn was ever called (DCE drops the body but the
static survives). Fix mirrors `toml_parse_file_r`
(v5.8.30) exactly — `var buf = alloc(262144)` + drop
the `&buf` address-of on subsequent uses. ~10 LoC
delta + a 6-line comment block above the fn pointing
to CHANGELOG [5.11.61].

**Measured impact** — verified via two paths:
- Synthetic repro in cyrius repo (include lib/toml.cyr,
  don't call toml_parse_file): bss = **2,600 B** post-
  fix. Confirms static is gone when fn is DCE-killed.
- commandress consumer rebuild (transient swap of
  `commandress/lib/toml.cyr`, repo restored to pre-
  test state after — no persisted edits): pre-fix bss
  **298,064 B** with `large static data` warning →
  post-fix bss **35,920 B**, warning suppressed.
  Delta **−262,144 B** = exactly the buffer size.

commandress downstream gets the drop when they bump
their `cyrius.cyml` pin to .61 + run `cyrius lib sync`
to refresh their local `lib/` from the .61 snapshot.

**.62 ship details** — Compiler/tooling pair
(commandress Items 5 + 1). Item 5 was **reframed at
slot entry** after a premise-check finding: the roadmap
pin's "filter the warning by `live[]` under CYRIUS_DCE=1"
fix was empirically wrong. CYRIUS_DCE=1 NOPs `.text` only;
bss reservations for dead-fn-local statics survive both
modes (commandress measured at 298,064 B identical bss
under both modes). User picked the reframe — keep the
warning honest about disk bytes, add diagnostic
attribution. Item 1 (scaffold rewrite) shipped alongside.

**Item 5 implementation**: new 64 KB heap region at
`0x1C8000` (reused slot vacated v5.11.19 by fn_regalloc
relocation) tracks per-fn array bytes. Parser
(`_cur_fn_ix` global + PARSE_FN_DEF entry/exit hooks +
parse_decl.cyr array path) accumulates `var foo[N]`
aligned sizes into the fn's slot. FIXUP's DCE pass walks
fn_table after building `live[]` and sums dead-fn
contributions; stash into post-data_size scratch at
`0x18FCD8/E0` for EMITELF_USER's warning to read. New
output:
```
warning: large static data (298056 bytes) — consider alloc() for buffers >4KB
  hint: 275360 bytes inside 250 unreachable fn(s) — DCE NOPs code but keeps .bss;
        restructure with alloc() or move the static into a reachable consumer
```
275,360 / 298,056 = **92% of commandress's bss attributable
to unreachable fns**. Drive-by fix: pre-existing 44-vs-46
byte-count bug in the warning's main line (em-dash is 3
UTF-8 bytes; trailing `B\n` was truncated). Cross-arch
parser tracking shared; warning x86-only by existing design.

**Item 1 implementation**: rewrote both scaffold sources
(`programs/cyrius-init-templates/proj-bcyr` for the
binary path + `scripts/cyrius-init.sh` heredoc for the
shell fallback) to use real `bench_new` +
`bench_batch_start/stop` + `bench_report` API. Added
`"bench"` to `[deps.stdlib]` in both cyml templates +
the shell fallback's two embedded lists (otherwise
`cyrius deps` skips `lib/bench.cyr` and the scaffold
still fails on `bench_new` undefined). Verified end-to-
end: `cyrius init mytest && cd mytest && cyrius deps &&
cyrius bench tests/mytest.bcyr` → `noop: 2ns avg`.

**.63 ship details** — aarch64 `_strict_mode` parity
with the v5.11.59 DCE-aware reachability filter follow-up.
Three aarch64 build variants
(`main_aarch64.cyr` / `main_aarch64_macho.cyr` /
`main_aarch64_native.cyr`) gained the same `_strict_mode`
global + `/proc/self/cmdline` parse block via a
`SYS_OPEN == 2` branch (covers x86_64 host AND aarch64
native host with the right openat signature).
`src/backend/aarch64/fixup.cyr` strict-exit mirrors
x86's lines 729-738. **Drive-by**: wrapper `--strict`
plumbing extended to BOTH archs (was absent in the
wrapper for both pre-.63 even though cc5 supported
`--strict` via direct invocation since v5.4.19), so
`cyrius build --strict` and `cyrius build --aarch64
--strict` are now symmetric.

End-to-end verified:
- `cyrius build --aarch64 --strict <reachable-undef>` →
  warning + error + FAIL + exit 1.
- `cyrius build --strict <reachable-undef>` → same (x86
  parity).
- `cyrius build --aarch64 --strict <clean>` → OK + exit 0.

**.60-.63 band CLOSED**. All four slots shipped clean
without slipping. Commandress papercut filing
(`2026-05-17-commandress-stdlib-papercuts.md`) moved to
`archived/`. In-scope items: Items 1 + 2 + 5 + 6 + 7 ✅
closed. Items 3 + 4 + 8 deferred to v6.x as own
filings / arcs.

**Handoff note**: next agent kicks off on **.64**
(explicit open bandwidth per the roadmap). Per user
direction 2026-05-17, .64 + .65 stay as the absorber
runway for inbound consumer filings or split-overflow
before the pinned .66/.67 byte-array literal peephole
pair. If no fresh filings surface, both slots cycle into
the closeout window approaching .68 (heap-map full
reorg + CVE-05 + ADR-002 i64-tenet+SIMD-exception
reframing).

**Cycle tail status**: .64/.65 open bandwidth; .66/.67
byte-array literal peephole (5× emit compression);
.68 heap-map full reorg + CVE-05 + ADR-002 update per
[[project_adr_002_i64_core_tenet_simd_exception]];
.69 conditional mabda 3.0 fold.

Slot pins (per roadmap.md `### v5.11.60 → v5.11.63`):

- **.60** — ✅ **SHIPPED 2026-05-18**. `lib/process.cyr`
  bug-fix pair (commandress Items 6 + 7).
- **.61** — ✅ **SHIPPED 2026-05-18**.
  `lib/toml.cyr::toml_parse_file` heap-alloc rewrite
  (commandress Item 2). −256 KB bss in any consumer
  that includes `lib/toml.cyr`.
- **.62** — ✅ **SHIPPED 2026-05-18**. Compiler/tooling
  pair (commandress Items 5 + 1). Item 5 reframed at
  slot entry (CYRIUS_DCE=1 doesn't shrink bss); ships
  dead-fn `.bss` attribution hint instead. Item 1
  ships the real bench API scaffold + `bench` added to
  default stdlib deps.
- **.63** — ✅ **SHIPPED 2026-05-18**. aarch64
  `_strict_mode` parity (.59 retro follow-up) +
  wrapper `--strict` plumbing for both archs.

**Post-ship doc-health sweep — 2026-05-18 (non-release-bearing)**:
Dedicated read-through of the 8 🟠 carryovers + bench-
infrastructure verification + roadmap restructure. Sweep
retired 7 of 8 🟠 docs (the 8th, `migration-strategy.md`,
deferred to v6.0.0 doc-pass per user direction). Three
classes of finding:
- **Naming refresh** (4 docs): `process-notes` /
  `crash-localization` / `architecture/cyrius` /
  `architecture/package-format` had pre-v5.0.0 `cc3` and
  pre-v5.5.x `cyrius.toml` references. Frontmatter notes +
  in-context renames applied.
- **Mechanical schema refresh** (1 doc):
  `module-manifest-design` got `cyrius.toml` → `cyrius.cyml`
  sed across 11 occurrences.
- **Bench infrastructure orphan finding** (2 docs +
  `BENCHMARKS.md` re-run): `scripts/bench-history.sh` 3-tier
  suite + `BENCHMARKS.md` auto-gen + `bench-history.csv`
  history all already existed since v5.7.x but the doc
  pointers in `docs/benchmarks.md` and
  `docs/development/benchmarks.md` were sending readers at
  the frozen v5.6.x narrative. Pointers updated to canonical-
  current `/BENCHMARKS.md`; historical-frontmatter added to
  the dev-side doc. Fresh `bench-history.sh` run caught a
  **+65.2 % self_compile regression vs 2026-04-18 baseline**
  (244 ms → 404 ms). To investigate as its own slot — see
  follow-up candidate below.
- **Verified accurate** (1 doc): `ffi/struct-packing` —
  `fncallN` ABI unchanged since v5.4.13 landing. Promoted
  🟠 → ✅.

Also collapsed v5.11.47-.63 shipped slot detail in
`roadmap.md` into a single "Shipped this cycle" one-liner
section per `feedback_doc_canonical_no_redundancy` (CHANGELOG
is canonical; roadmap was duplicating ~315 lines of detail).
Roadmap dropped from ~648 to ~330 lines while preserving all
forward-looking content (.66/.67/.68/.69 detail intact).

**Outstanding follow-up candidates** (not in pinned band):
- **Self-compile growth tax** (surfaced 2026-05-18 bench
  refresh): self_compile **244 ms → 404 ms (+160 ms)** across
  the v5.10.50 → v5.11.63 window (~30+ patches of real feature
  work: stdlib annotation arc, named-op refactor, byte-array
  literal, UEFI Application emit, full aarch64 DCE pass at
  .59, per-fn array-bytes parser tracking at .62, aarch64
  strict-mode parity at .63, etc). Averages ~+5 ms/patch which
  isn't surprising for the work shipped. **Not pressing for
  v5.11.x — reframed as a growth-tax audit for v6.x review
  queue** (see `roadmap.md` "v6.x review queue"). Decision
  shape at review: accept-as-cost-of-capability vs schedule a
  perf miniarc (v5.10.40/.41 precedent: 2.7× total compile-
  time win in 2 slots). cc5 binary grew only +1,072 B over
  the same window — cost is parse/codegen overhead, not bloat.
- `migration-strategy.md` — deferred to v6.0.0 doc-pass per
  2026-05-18 user direction.
- Open issues (carryover): bote nested-call state-leak cold
  case (Low); build-artifact pre-commit hook (Medium). Both
  stayed open across the .50-.59 arc. build-artifact earns a
  v5.11.x slot only if a fresh trigger surfaces during
  .64/.65, otherwise v6.x.
- Open issues (carryover NEW 2026-05-17 → closed 2026-05-18):
  commandress papercuts — Items 6+7 ✅ closed at v5.11.60;
  Item 2 ✅ closed at v5.11.61; Items 1+5 ✅ closed at
  v5.11.62 (Item 5 reframed mid-slot after
  CYRIUS_DCE=1-doesn't-shrink-bss premise check); aarch64
  `_strict_mode` parity ✅ closed at v5.11.63. Issue file
  archived. Items 3 (toml `[name]`), 4 (LSP transitive-
  include), 8 (PATH lookup) deferred to v6.x as own
  filings / arcs.
- Open proposals: pie-support (v6.1.x pin),
  cyrius-lsp-argv0-self-resolution (unpinned; v6.x LSP arc
  candidate alongside commandress Item 4),
  octal-literal-syntax + syscalls-`*at()`-family + toml-
  single-bracket-sections (all v6.x per
  [[project_kriya_low_level_v6x_syscall_arc]] /
  [[project_v5_11_x_closeout_at_40]]).

## Version

**6.0.4** (shipped 2026-05-27 — **kybernet aarch64 codegen-hang fix
(`GFCNT`→`GFNC` in the aarch64 DCE pass) + DCE `live[]` 8192-fn cap + stdlib
refresh sigil 3.5.5 / patra 1.10.3**). The aarch64 DCE reachability pass
sized its fn-table loops with the fixup count, overflowing an 8192-slot
hash into an infinite probe loop on large units (kybernet). self-host
byte-identical **875,584 B**; check.sh **80/80** (+`_dce_fn_count_gate`).
See CHANGELOG [6.0.4] + the .4 session-close above.

**6.0.3** (shipped 2026-05-27 — **`str_from` overload-misroute codegen P1
(nous 0001)**). The overload dispatcher routed `str_from(<i64-returning-call>)`
→ `str_from_int`, stringifying cstr pointers as decimal (silently-wrong data).
Fixed by gating the `_int` auto-route to output-style (i64-return) bases only;
data-producing bases (`str_from: Str`) no longer auto-route. Self-host
byte-identical **874,280 B**; check.sh **79/79** + regression
`str_from_ptr_overload.tcyr`. See CHANGELOG [6.0.3] + the .3 session-close above.

**6.0.2** (shipped 2026-05-27 — **`cyrius deps` correct-lock fix
(empty ecosystem-wide since v5.11.8) + stdlib pins verified at 6.0.1**).
`cbt/deps.cyr::cmd_deps_lock` now hashes `lib/*.cyr` recursively
instead of filtering by the stale symlink proxy; cyrius source repo
skips the self-referential lock. New `_deps_lock_gate` → check.sh
**79/79**. See CHANGELOG [6.0.2] + the .2 session-close above.

<!-- Historical per-patch blocks below predate the v6.0.x cycle and
are retained as narrative; the maintained current-state record is the
session-close entries at the top of this file. -->

**5.11.63** (shipped 2026-05-18 — **aarch64 `_strict_mode`
parity (.59 retro follow-up) + wrapper `--strict` plumbing
for both archs**). Final slot of the .60-.63 commandress
papercut absorber band — band CLOSED.

Closes the parity gap the v5.11.59 slot explicitly deferred
("aarch64 doesn't declare `_strict_mode`; filter emits
warning but no hard-exit. Adding aarch64 strict is its own
follow-up slot"). aarch64 now exits with code 1 on
reachable undef-fn refs when `--strict` is set, matching x86
since v5.4.19.

**Compiler-side** — three aarch64 build variants
(`main_aarch64.cyr` / `main_aarch64_macho.cyr` /
`main_aarch64_native.cyr`) gained the same `_strict_mode`
global + `/proc/self/cmdline` parse block. Block uses
`if (SYS_OPEN == 2) ...` branching so the same source lands
cleanly on x86_64 hosts (cross-compile path) AND aarch64
hosts (native self-host path with openat + AT_FDCWD).
`src/backend/aarch64/fixup.cyr` strict-exit mirrors x86's
lines 729-738 verbatim. `undef_count` only bumps on
REACHABLE refs (v5.11.59 DCE filter preserved) — strict
fires only on real bugs, not dead-host refs.

**Drive-by** — wrapper `--strict` plumbing landed for BOTH
archs (was absent in the wrapper for both pre-.63; cc5
supported `--strict` via direct invocation only). New
`_strict` global in `cbt/core.cyr`; flag parsing in
`cbt/cyrius.cyr` build dispatch; argv pass-through in
`cbt/build.cyr compile()` (covers both default and
`--strict-pin` envp branches). Symmetric across archs to
avoid the `--aarch64 --strict works` / `--strict
silently-no-ops` shape.

**End-to-end verified**:
```
$ cyrius build --aarch64 --strict <reachable-undef-ref>
warning: undefined function '...' (call site may be unreachable)
error: --strict: refusing to emit binary with 1 undefined function(s)
FAIL ; exit 1

$ cyrius build --strict <same>                  # x86 parity
error: --strict: refusing to emit binary with 1 undefined function(s) ; exit 1

$ cyrius build --aarch64 --strict <clean>       # no undef refs
OK ; exit 0
```

Self-host byte-identical at **876,408 B** (unchanged —
main.cyr untouched). `check.sh` **75/75**. `cyrius test`
**151/150** (no new tcyr; aarch64 strict is a runtime
gate). Cross-compilers: cc5_aarch64 **561,848 B**
(+3,560 B for parser tracking from .62 propagation + new
cmdline parse + strict-exit); cc5_win **683,832 B**
(unchanged — PE shares x86 fixup which already had
`_strict_mode`).

**Snapshot-ping-pong guarded**: this slot is parser /
fixup / wrapper / templates — no `lib/*.cyr` edits.
`install.sh --refresh-only` ran via `version-bump.sh`.

**.60-.63 band CLOSED**. Commandress papercut filing
moved to `archived/`. Next: **.64** (open bandwidth).

**5.11.62** (shipped 2026-05-18 — **Compiler/tooling pair —
dead-fn `.bss` attribution in `large static data` warning +
`cyrius init` bench-scaffold rewrite**). Third slot of the
.60-.63 commandress papercut absorber band; closes Items 1
+ 5 of `docs/development/issues/archived/2026-05-17-commandress-stdlib-papercuts.md`.

**Item 5 was reframed at slot entry** after a premise check
(per `feedback_premise_check_at_slot_entry`) found the
roadmap pin was empirically wrong. Pre-fix the pin said
"filter the warning by `live[]` under CYRIUS_DCE=1", on
the assumption that CYRIUS_DCE=1 frees the bss reservations
for dead-fn-local statics. Reality: CYRIUS_DCE=1 NOPs
`.text` only; bss survives. commandress reported 298,064 B
bss IDENTICAL in both modes. Filtering would have produced
a misleadingly LOWER number that doesn't match disk.

User picked the reframe path — keep the warning honest about
disk bytes, add diagnostic attribution. Implementation:

- **New 64 KB heap region** at `0x1C8000` (reused slot
  vacated v5.11.19 by `fn_regalloc` relocation to
  `0x14A000`) — `fn_var_bytes [8192]`.
- **Parser** (`parse.cyr` + `parse_fn.cyr` + `parse_decl.cyr`):
  new `_cur_fn_ix` global, set in PARSE_FN_DEF entry +
  zeroed slot, reset to -1 in PARSE_FN_DEF exit. Array
  registration path in parse_decl accumulates the aligned
  size into the current fn's slot when `_cur_fn_ix >= 0`.
- **FIXUP tally** (`src/backend/x86/fixup.cyr`): after the
  DCE pass populates `live[]`, walk fn_table and sum
  `fn_var_bytes[fi]` for each unreachable fn. Stash totals
  into post-data_size scratch at `0x18FCD8` (dead bytes) +
  `0x18FCE0` (dead count) so EMITELF_USER (a separate fn)
  reads them at warning time without re-running the bitmap.
- **Warning emission** (same file): append
  `hint: M bytes inside N unreachable fn(s) — DCE NOPs code
  but keeps .bss; restructure with alloc() or move the
  static into a reachable consumer` when M > 0.
- **Drive-by**: fixed pre-existing 44-vs-46 byte-count bug
  in the warning's main line (em-dash is 3 UTF-8 bytes;
  trailing `B\n` was being truncated, producing the visible
  `>4K` followed by whatever came next).

**Measured impact** (commandress, direct via .62 cc5):
```
warning: large static data (298056 bytes) — consider alloc() for buffers >4KB
  hint: 275360 bytes inside 250 unreachable fn(s) — DCE NOPs code but keeps .bss;
        restructure with alloc() or move the static into a reachable consumer
```
275,360 / 298,056 = **92% of commandress's bss attributable
to unreachable fns** — exactly the actionable signal Item
5 was supposed to surface.

**Item 1**: rewrote both scaffold sources
(`programs/cyrius-init-templates/proj-bcyr` + the heredoc
in `scripts/cyrius-init.sh`) to use real `bench_new` +
`bench_batch_start/stop` + `bench_report` API. Added
`"bench"` to `[deps.stdlib]` in both cyml templates +
the shell fallback's two embedded lists. Verified end-to-
end: `cyrius init mytest && cd mytest && cyrius deps &&
cyrius bench tests/mytest.bcyr` → `noop: 2ns avg`.

**Cross-arch**: parser tracking is shared (single-source
parse_*.cyr); cc5_aarch64 silently builds `fn_var_bytes`
but doesn't emit the warning (aarch64 fixup has no
`large static data` warning today — x86-only by existing
design, not by this slot's choice). cc5_win shares
x86/fixup.cyr so the warning + attribution land there too.

Self-host byte-identical at **876,408 B** (+1,072 B from
.61 for new parser tracking + DCE tally + warning emit).
`check.sh` **75/75**. `cyrius test` **151/150** (no new
tcyr; existing suites cover the parser change).
Cross-compilers: cc5_aarch64 **558,288 B** (+272 B, parser
only); cc5_win **683,832 B** (+1,072 B, full warning).

**Snapshot-ping-pong guarded**: lib/* untouched this slot
(parser + fixup + scaffold templates only). `install.sh
--refresh-only` ran twice — once via `version-bump.sh`,
once after the post-bump scaffold-template edits.

**Next**: .63 — aarch64 `_strict_mode` parity (.59 retro
follow-up). Closes the .60-.63 band.

**5.11.61** (shipped 2026-05-18 — **`lib/toml.cyr::toml_parse_file`
heap-alloc rewrite — −256 KB bss in every consumer that
includes `lib/toml.cyr`**). Second slot of the .60-.63
commandress papercut absorber band; closes Item 2 of
`docs/development/issues/archived/2026-05-17-commandress-stdlib-papercuts.md`.

Pre-fix the fn body declared a 256 KB on-fn-scope buffer
(`var buf[262144]`) that lived in `.bss` regardless of
whether the fn was ever called — DCE drops the body but
the static survives. Fix: `var buf = alloc(262144)` +
drop the `&buf` address-of on subsequent uses (alloc
already returns a payload pointer). Mirrors
`toml_parse_file_r` (v5.8.30) exactly, which already
heap-allocs. ~10 LoC delta + a 6-line comment block above
the fn pointing to CHANGELOG [5.11.61] and naming
`toml_parse_file_r` as the precedent.

**Verification** — two paths:
1. Synthetic repro (cyrius repo, local lib/, fn
   DCE-killed): bss = **2,600 B**.
2. commandress consumer rebuild (transient
   `commandress/lib/toml.cyr` swap, restored after):
   pre-fix **298,064 B** + `large static data (298064
   bytes) — consider alloc() for buffers >4K` warning →
   post-fix **35,920 B**, warning suppressed. **−262,144 B**
   = exactly the buffer size.

Self-host byte-identical at **875,336 B** (unchanged —
lib/toml.cyr not included by cc5). `check.sh` **75/75**.
`cyrius test` **151/150** (existing `toml.tcyr` +
`toml_multiline.tcyr` cover the surface; no new tcyr).
Cross-compilers unchanged (cc5_aarch64 558,016 B;
cc5_win 682,760 B).

**Snapshot-ping-pong guarded**: edit copied to
`~/.cyrius/versions/5.11.60/lib/` + `~/.cyrius/lib/`
before check.sh; `install.sh --refresh-only` during .61
bump replaced both with the .61 snapshot.

**Next**: .62 — commandress Items 5 + 1 (DCE-aware
`large static data` warning gate + `cyrius init` bench-
scaffold rewrite).

**5.11.60** (shipped 2026-05-18 — **`lib/process.cyr`
bug-fix pair — `_exec3` argv/envp byte-contract fix +
stderr→/dev/null dup2 across four vec-based execs**).
First slot of the commandress papercut .60-.63 absorber
band; closes Items 6 (Medium) + 7 (Low) of
`docs/development/issues/archived/2026-05-17-commandress-stdlib-papercuts.md`.

**Item 6** (`_exec3` byte-contract): `var argv[4]`
and `var envp[1]` reserved **4 BYTES and 1 BYTE** of
stack respectively. Body wrote up to 4×8 B + NUL into
argv and 8 B into envp — silent stack corruption on
every call. Pre-fix `run_capture("/bin/echo", "hello",
0, ...)` returned 1 byte (lone `\n`); post-fix returns
6 (`hello\n`). Fix: `var argv[40]` (5×8 B — cmd + 2
args + NUL + slot headroom) + `var envp[16]` (2×8 B).
Comment block above the fn documents the byte-vs-entry
contract for the next reader. `_str` family
(`exec_capture_str` etc.) was never affected — they
heap-alloc argv via `alloc((argc+1)*8)`.

**Item 7** (stderr leak): `exec_capture`, `exec_env`,
`exec_capture_str`, `exec_env_str` were missing the
`sys_open("/dev/null", 1, 0) + sys_dup2(devnull, 2)`
stanza that `run_capture` ships (since v5.10.18). All
four now mirror `run_capture`'s child-side dup2 block.
Scope was 2-vs-4 ambiguous (cstr family is asymmetric:
`run` no-suppress, `run_capture` suppress); user picked
all 4 per filing's explicit enumeration — deliberately
breaks cstr-family parity. Consumers needing stderr to
surface from `exec_env` / `exec_env_str` now inline
their own fork+pipe+execve.

**Regression test** (new):
`tests/tcyr/process_run_capture_args.tcyr` — 6 sub-
asserts. Single-arg + two-arg `run_capture` byte counts
+ `run` two-arg no-capture exit code. Skips when
`/bin/echo` or `/bin/true` is missing.

Self-host byte-identical at **875,336 B** (unchanged —
lib/process.cyr is not included by cc5). `check.sh`
**75/75**. `cyrius test` **151/150** (+1 tcyr).
Cross-compilers unchanged (cc5_aarch64 558,016 B,
cc5_win 682,760 B). Snapshot-ping-pong guarded
(`~/.cyrius/versions/5.11.59/lib/` + `~/.cyrius/lib/`
refreshed pre-check.sh; .60 bump replaced both via
`install.sh --refresh-only`).

**Next**: .61 — `lib/toml.cyr::toml_parse_file` heap-
alloc rewrite (commandress Item 2; 256 KB on-fn-scope
buffer → `alloc()`, mirrors `toml_parse_file_r`
v5.8.30).

**5.11.59** (shipped 2026-05-17 — **DCE-aware undefined-fn
reachability filter (cross-arch engineering slot)**).
Completes the deferred work from the .56 papercut split.
Cross-arch parity in same slot per
`feedback_cross_arch_propagation_mandatory`.

**x86_64** (`src/backend/x86/fixup.cyr`) — moved the
undef-fn check from BEFORE the fixup patch loop to AFTER
the DCE pass; added host-fn reachability filter via the
existing `live[]` bitmap. Strict-mode hard-fail preserved
but now only counts reachable refs (no more false-positive
strict failures on dead-host undef refs).

**aarch64** (`src/backend/aarch64/fixup.cyr`) — added a
NEW DCE pass (~200 LoC) mirroring x86's seed + propagate +
sweep with aarch64 BL/B encodings (4-byte fixed instruction
width, byte-3 mask `& 0xFC == 0x94` for BL / `== 0x14` for
B, rel26 sign-extend + shift-left-2). NOP-fill uses
`0xD503201F`, safety check via preceding RET
(`0xD65F03C0`) OR body-ending RET. Reuses x86's hash table
region at `0x114000` (verified unused on aarch64). aarch64
now produces `note: N unreachable fns (M bytes ...)` for
the first time — previously had no DCE visibility.

**Validation**:
- `agnosticos/scripts/src/read-boot-log.cyr` x86 + aarch64:
  fixup-time `vec_get (call site may be unreachable)`
  warning GONE on both archs (dead `vec_find` host); only
  the parse-time main.cyr:1344 warning still fires on x86
  (different check, out of scope).
- `cc5_aarch64` cross-build of itself: emits `note: 79
  unreachable fns ...` (first aarch64 DCE output).
- `CYRIUS_DCE=1` aarch64 cross-build of read-boot-log:
  `note: 415 unreachable fns (15892 bytes NOPed)` — sweep
  engaged, file size unchanged (in-place NOP fill).

**Strict-mode parity gap**: aarch64 doesn't declare
`_strict_mode` (only x86 + main_win); filter emits warning
but no hard-exit. Adding aarch64 strict is its own follow-
up slot (would need `_strict_mode` decl in
`main_aarch64.cyr` + flag plumbing in the wrapper's
aarch64 dispatch).

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**875,336 B**, +672 B from v5.11.58 for u59 filter block);
`check.sh` **75/75**; `cyrius test` **150/150**;
cross-compilers rebuilt (cc5_aarch64 558,016 B / +8,192 B
for full DCE pass; cc5_win 682,760 B / +672 B for filter
only).

**Next absorber band**: .60-.65 open buffer. Pinned: .66/
.67 (byte-array literal peephole), .68 (heap-map full
reorg + CVE-05), .69 (conditional mabda fold). Open
follow-up candidate: aarch64 `_strict_mode` parity (small
slot).

**5.11.58** (shipped 2026-05-17 — **Wrapper polish —
version-bump rebuild fix + `cyrius lib sync` + wrapper
`--strict-pin` + `--version` manifest-pin line**). Closes
the wrapper-side surface of iron-boot papercut filing
Items 1 + 4; cc5-side detection shipped at v5.11.57.
Filing **fully closed** across .56 + .57 + .58 — issue
file archived.

**Wrapper rebuild bug** (the .57 premise-check finding):
`scripts/install.sh::_rebuild_stale` checks `build/$target
-nt $source` against direct source only, misses transitive
includes. Every `.cyr` file that includes
`src/version_str.cyr` (auto-regenerated at every bump) was
therefore invisible to staleness detection. Wrapper at
`~/.cyrius/bin/cyrius` froze at the May-12 build embedding
`5.11.25` and propagated forward into every snapshot. Fix
in `scripts/version-bump.sh`: after regenerating
version_str.cyr, `touch` every consumer source (main.cyr,
main_aarch64.cyr, main_win.cyr, main_cx.cyr,
main_aarch64_native.cyr, main_aarch64_macho.cyr,
cbt/cyrius.cyr) so install.sh's `-nt` check fires; ALSO
rebuild `build/cc5` explicitly because install.sh skips
cc5 by contract (line 158, "seed-bootstrapped"). Existing
stale snapshots at `~/.cyrius/versions/X.Y.Z/` remain
historical debt — consumers can `cyrius install X.Y.Z` to
refresh a specific version. From .58 onward, every bump
produces correct binaries.

**`cyrius lib sync`** — new dispatch + `cmd_lib_sync` in
cbt/commands.cyr. Copies `~/.cyrius/versions/<X>/lib/*.cyr`
into cwd `./lib/`, where `<X>` is cyml pin or wrapper
version. Third remediation for the shadow-lib warning (was:
delete ./lib/ or set CYRIUS_NO_WARN_SHADOW_LIB=1).
`--dry-run` supported. Verified end-to-end: 81 stdlib `.cyr`
files synced from .57 snapshot into a fresh test dir.

**`cyrius build --strict-pin`** — wrapper-side CLI flag
that augments cc5 child's envp with `CYRIUS_STRICT_PIN=1`,
which v5.11.57's `_check_cyml_pin_drift` reads to upgrade
the pin-drift warning to a hard exit. CI gating path for
pin-faithful builds. New `_strict_pin` global in core.cyr;
flag parsing in `build` dispatch; envp augmentation in
`compile()` (cbt/build.cyr). Verified: `cyrius build
--strict-pin` from agnos (pin .55, cc5 .56) emits
`error: ... (CYRIUS_STRICT_PIN)` + exit 1.

**`cyrius --version` manifest-pin line** — when run inside
a project tree (cwd has cyrius.cyml with [package].cyrius),
appends a second line:
```
cyrius 5.11.57
manifest-pin: 5.11.55 (drift — wrapper is 5.11.57)
```
The `(drift — ...)` suffix only appears on mismatch. Spot
the drift the moment you check what wrapper you're running.

**Drive-by**: `cmd_clean` em-dash byte count (60 → 62) —
same class as the .57 retro gotcha, would've chopped `"d "`
off the cleaned-files message rendering `removeN` instead of
`removed N`. Fixed under .57 hygiene pin.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**874,664 B**, unchanged from v5.11.57 — .58 only touches
the wrapper layer + build scripts); `check.sh` **75/75**;
`cyrius test` **150/150**; wrapper rebuilt at 184,232 B
(+3,376 B over .57).

**Next absorber band**: .59 (DCE-aware reachability filter,
cross-arch engineering, ~300 LoC) → .60-.65 open buffer.
Pinned: .66/.67 (byte-array literal peephole), .68 (heap-
map full reorg + CVE-05), .69 (conditional mabda fold).

**5.11.57** (shipped 2026-05-17 — **cc5-side pin-drift +
shadow-content detection (papercut Items 1 + 4, cc5 surface)**).
Slot-entry premise check revealed Item 1's root cause is
deeper than the filing captured: `scripts/install.sh::
_rebuild_stale` misses `src/version_str.cyr` as a transitive
dependency of `cbt/cyrius.cyr`, so the wrapper at
`~/.cyrius/bin/cyrius` has been embedding `5.11.25` since
2026-05-12. Every bump since copies the stale May-12 binary
forward into each snapshot. cc5 is rebuilt every bump for
self-host so cc5 IS authoritative-current; detection from
cc5 surfaces drift regardless of wrapper-rebuild state.
Wrapper-side polish (rebuild fix + `cyrius lib sync` +
`--strict-pin` + `--version` manifest-pin line) earns .58.
Reachability filter (was pinned .58) re-pinned to .59 per
`feedback_deferral_requires_roadmap_pinnage`.

**Item 1 (cc5 side)** — new `_check_cyml_pin_drift()` in
`src/frontend/lex.cyr`, hooked into `_init_cyrius_lib`
alongside `_check_shadow_lib`. Reads cwd's `cyrius.cyml`
`[package].cyrius = "X.Y.Z"`, compares to cc5's compile-time
`_VERSION_STR_CC5`. On mismatch emits `warning: cyrius.cyml
pins X.Y.Z but cc5 is X.Y.W — toolchain drift (snapshot may
be stale; set CYRIUS_NO_WARN_PIN_DRIFT=1 to silence)`. Opt-
out via `CYRIUS_NO_WARN_PIN_DRIFT=1`; strict mode via
`CYRIUS_STRICT_PIN=1` → `error:` + exit 1.

**Item 4 (cc5 side)** — `_check_shadow_lib` content-compare
filter. Pre-fix the shadow note fired any time cwd had a
`lib/` directory (empty-dir agnosticos/scripts case from the
filing). New shape: probes `./lib/alloc.cyr` as canonical
sentinel; if absent, local lib isn't shadowing stdlib. If
present, byte-size-compare against snapshot's `alloc.cyr`
via new `_file_size()` helper; only emits note when sizes
differ (real drift). Sentinel-file approach trades full
directory enumeration (`getdents64`) for ~30 LoC; corner
case where `alloc.cyr` matches but other files differ is
rare enough to accept (full enumeration can land later).

**Helpers added** — `_file_size(path)` (SYS_OPEN + SYS_LSEEK
SEEK_END), `_env_var_is_1(name, name_len)` (scans
`/proc/self/environ` for `<name>=1\0`). Existing
`_check_shadow_lib` inline `CYRIUS_NO_WARN_SHADOW_LIB` check
predates `_env_var_is_1` and stays inline for byte-identity
stability; future cleanup can converge.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**874,664 B**, +47,384 B / +5.7% from v5.11.56 — new fns +
cyml parser + shadow-compare rewrite); `check.sh` **75/75**;
`cyrius test` **150/150**; cross-compilers rebuilt
(cc5_aarch64 549,824 B, cc5_win 682,088 B).

**Validation**: agnosticos/scripts (cyml pins .55, cc5 .57)
emits the pin-drift warning; shadow note CORRECTLY absent
(empty lib/, sentinel absent). Cyrius repo (alloc.cyr ==
snapshot) emits NO shadow note (was always spuriously
emitted pre-fix); forcing a size diff re-engages the note,
confirming compare logic works.

**Bringup gotcha**: em dash is 3 bytes in UTF-8 — first pass
on the warning string used visible-char count and chopped the
trailing `)\n`, running warnings together on stderr.
Existing `_check_shadow_lib` strings already use the 3-byte
convention (112-byte string with `"—"`); future syscall-
length args should be cross-checked against that pattern.

**Next absorber band**: .58 (wrapper polish, Items 1+4
wrapper surface) → .59 (DCE-aware reachability filter,
cross-arch engineering) → .60-.65 open buffer. Pinned: .66/
.67 (byte-array literal peephole), .68 (heap-map full reorg
+ CVE-05), .69 (conditional mabda fold).

**5.11.56** (shipped 2026-05-17 — **Build-diagnostic polish
(papercut Items 2 + 3) — LSP forks `cyrius` wrapper + undef-fn
"will crash" wording downgrade**). Closes 2 of 4 items in the
2026-05-16 iron-boot session papercut filing. .57 closes
Items 1 + 4 (wrapper/lib-resolution infra). .58 earns the
deferred precise DCE-aware reachability filter as its own
cross-arch engineering slot.

**Item 2 (LSP → wrapper)**: `programs/cyrius-lsp.cyr`
`compile_and_capture()` previously forked **raw cc5** with
NULL envp and the LSP's cwd; cc5 had no visibility into
project `cyrius.cyml` `[deps.*]` declarations. New shape:
`find_cyrius()` mirrors `find_cc5()` lookup chain;
`find_project_root(filepath)` walks up looking for
`cyrius.cyml`; `_build_envp_from_proc()` reads `/proc/self/
environ` and forwards the LSP's env to the child (raw-cc5
NULL envp resolved `HOME` to `/root/...` and surfaced bogus
pin-mismatch diagnostics); `_compile_via_wrapper()` forks
the wrapper with `chdir(project_root)` + `cyrius check
--with-deps <filepath>`. Falls back to raw cc5 for files
outside any project tree or when wrapper isn't installed.
- Smoke: agnos xhci.cyr went from ~10 false-positive
  diagnostics to 1 (genuine include-submodule cross-file ref;
  separate scoping class, not the [deps.*] class).
  read-boot-log.cyr went from 8 stdlib-fn false positives to
  0; the genuine `vec_get` diagnostic remains with the new
  wording from Item 3.

**Item 3 (undef-fn wording downgrade)**: `src/backend/x86/
fixup.cyr` + `src/backend/aarch64/fixup.cyr` fixup-time
undef-fn check — `error: undefined function 'X' (will crash
at runtime)` → `warning: undefined function 'X' (call site
may be unreachable)`. Drops the `error:` + `OK` contradiction
the filing flagged. `--strict` mode hard-fail path preserved
unchanged (CI gating). Cross-arch in same slot per
`feedback_cross_arch_propagation_mandatory`. cc5_aarch64
(502,424 B) + cc5_win (634,704 B) rebuilt to propagate.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**827,280 B**, −16 B from v5.11.55); `check.sh` **75/75**;
`cyrius test` **150/150**; `cyrius-lsp` now 101,120 B
(+4,704 B over v5.11.55 — new helpers + env forwarder).

**Next absorber band**: .57 (wrapper/lib infra, Items 1 +
4) → .58 (DCE-aware reachability filter, cross-arch
engineering, ~300 LoC) → .59-.65 open buffer. Pinned: .66/
.67 (byte-array literal peephole), .68 (heap-map full reorg
+ CVE-05), .69 (conditional mabda fold).

**5.11.55** (shipped 2026-05-13 — **Refactor sweep — cap-drift gate
`_verify_*` helpers + `_efi_compile_to_buf` consolidation (items
#2 + #4)**). Pure housekeeping; no new gates, no behavior change.

**#2 cap-drift gate helpers**: v5.11.50's 3 hardcoded 20-LoC cap
blocks replaced with two ≤6-arg helpers (`_verify_heap_map`,
`_verify_inline`). Each cap-check is now 2 short lines.

**#4 EFI gate compile boilerplate**: `_efi_compile_to_buf(src_path,
buf, cap, fail_label)` consolidates `_self_host_pipe_efi` +
unlink-on-fail + file_read_all + unlink-bin from `_efi_emit_gate`
and `_efi_trampoline_rex_gate`. Both gates' prologues shrunk
~20→5 LoC.

**Bringup gotcha (pinned)**: first refactor attempt used a 13-arg
single helper. Args 7+ (cstr literals) appeared as 0 in body —
cyrius's stack-arg ABI has alignment/value-corruption issues
beyond the 6-register convention. Restructured to two ≤6-arg
helpers, worked first try. New memory pin
`feedback_fn_arg_count_6`: keep cyrius helper fns ≤6 args.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**827,296 B** — unchanged from v5.11.54, refactors only touched
`programs/check.cyr`); `check.sh` **75/75**; `cyrius test`
**150/150**.

**Next absorber band**: .56 → .67 open buffer. Pinned: .68
(heap-map full reorg) + .69 (conditional mabda fold). Refactor
items #5 (byte-array peephole 5× compression) + #6 (ELF
section-header DRY at .68) remain.

**5.11.54** (shipped 2026-05-13 — **LSP papercut close + refactor
sweep (REX named ops + `_find_fn_by_name` helper)**). Closes
`2026-05-13-gnoboot-lsp-byte-array-literal.md` + 2 refactor items
from the .53-end survey (items #1 + #3).

**LSP fix**: `programs/cyrius-lsp.cyr::find_cc5()` — added a new
FIRST fallback that reads `HOME=` from `/proc/self/environ` and
tries `$HOME/.cyrius/bin/cc5` (the symlink → current installed
version, i.e. the LATEST parser). Falls back to the v5.11.44
co-installed lookup if `$HOME` is absent (minimal-env LSP
launchers). When a consumer pins an older `cyrius.cyml` (gnoboot
at 5.11.49 editing 5.11.51+ syntax), LSP diagnostics now use the
LATEST parser's view — `cyrius build` still respects the pin for
actual binary output. Filer's mental model ("the LSP has its own
parser, rebuild it") was wrong — cyrius-lsp forks cc5.

**Refactor #1 — REX named ops** (`src/backend/x86/emit.cyr`):
six new named ops cover the EFI trampoline encoding:
`EMOV_R14_RCX` (49 89 CE) / `EMOV_R15_RDX` (49 89 D7) /
`EMOV_RCX_R14` (4C 89 F1) / `EMOV_RDX_R15` (4C 89 FA) /
`ESUB_RSP_IMM8(n)` / `EADD_RSP_IMM8(n)`. Op names spell the intent;
REX bit locked in code. v5.11.52's silent encoding bug (raw
`EB(S, 0x4C)` decoded as `mov rsi, r9` not `mov r14, rcx`) is
structurally prevented — wrong op name surfaces at compile-time
review. 8 raw-byte calls in `src/main.cyr` collapse to named-op
calls; emitted bytes identical (encoding-gate verified).

**Refactor #3 — `_find_fn_by_name` helper** (`src/common/util.cyr`):
two open-coded nested-if byte comparisons (main at main.cyr:1338,
efi_main at :1369; 5-deep + 9-deep respectively) collapsed to one
helper + 2 short call sites. Suffix-NUL guard prevents
`"main"`-matching-`"mainframe"`-style false positives. Used at
pass-2 emit for fn auto-call dispatch.

**Net cc5 size**: 827,976 → **827,296 B** (**−680 B**) — first
v5.11.x slot where cc5 SHRUNK. The efi_main lookup alone went
from 9 nested ifs to 5 instruction-body lines.

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-lsp-byte-array-literal.md`
→ `archived/`.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**827,296 B**); `check.sh` **75/75**; `cyrius test` **150/150**;
EFI trampoline REX gate green (named-op emits produce same bytes
as the v5.11.53 raw-byte fix).

**Next (.55)**: user pre-authorized "anything else we can wrap"
except closeout items. Candidates from the survey: #2 (cap-drift
gate table refactor ~20 LoC), #4 (EFI gate compile helper ~30 LoC),
#5 (byte-array literal peephole 5× compression ~80 LoC + cross-
arch). #6 (ELF section-header DRY) reserved for .68 closeout per
CLAUDE.md item #6.

**5.11.53** (shipped 2026-05-13 — **Hotfix: efi_main trampoline
entry-save REX prefix `0x4C → 0x49`**). P1 filing from gnoboot
agent caught hours after v5.11.52 ship. 2-byte literal change in
`src/main.cyr:1273` save emit; restore stays correct as-is.

**The bug**: MR-form `mov r/m64, r64` (opcode `89 /r`) puts dst
in r/m field, src in reg field. To extend dst to r14/r15 needs
REX.B; v5.11.52 set REX.R instead.
- Wrong: `4C 89 CE` decodes as `mov rsi, r9` (not `mov r14, rcx`)
- Wrong: `4C 89 D7` decodes as `mov rdi, r10` (not `mov r15, rdx`)
- Right: `49 89 CE` / `49 89 D7`

Restore at trampoline tail (`4C 89 F1` etc.) was correct *by
accident* — r14/r15 as source (reg field) genuinely needs REX.R.
Save and restore use the same `0x4C` only when the symmetry
holds; for save direction it doesn't.

**Why slot-bringup smoke missed it**: v5.11.52 used a bare
`fn efi_main(h,s): i64 { return 0; }` test. With no body code
that dereferences `handle` or `st`, the bug never manifested —
efi_main just returned 0 and firmware unwound. **Trampoline
control-flow worked; register-content bug stayed latent.** The
gnoboot agent's rebuild against `cyrius = "5.11.52"` used a real
test (`var con_out = load64(st + 0x40);`) which dereferences
SystemTable → NULL deref → CR2=0 → caught.

**Encoding regression gate** (new): `_efi_trampoline_rex_gate()`
in `programs/check.cyr` compiles a minimal efi_main source, asserts
the save pattern `49 89 CE 49 89 D7` is present AND the wrong-REX
pattern `4C 89 CE 4C 89 D7` is absent AND the restore pattern
`4C 89 F1 4C 89 FA` is present. Negative-tested: v5.11.52 cc5
swap → gate FAILs with exact byte signatures from the filing
(offset 621). check.sh **74 → 75**.

**OVMF re-smoke** with the filing's exact repro (`fn efi_print`
walks SystemTable→ConOut→OutputString and `fncall2`s it):
- v5.11.52 cc5: `#PF`, `CR2=0x0` (NULL deref).
- v5.11.53 cc5: `hi` prints on serial; firmware unwinds to
  BootManagerMenu. **Trampoline now works end-to-end through
  user code dereferencing the captured args.**

**Process pin (mid-cycle)**: future inline-asm emit work must
verify captured state via test sources that *use* the captured
values, not just structural control-flow harnesses. Bare
`return 0;` tests pass control-flow audits but can't catch
register-content bugs.

**Issue archive**:
`docs/development/issues/2026-05-13-efi-main-trampoline-save-rex-wrong.md`
→ `archived/`.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**827,976 B** — same as v5.11.52, only byte values changed in
the trampoline emit; no instruction-count delta); `check.sh`
**74 → 75**; `cyrius test` **150/150**.

**Next**: cycle returns to absorber buffer (.53 → .67) with
pinned .68 (heap-map full reorg) and .69 (conditional mabda fold).

**5.11.52** (shipped 2026-05-13 — **`fn efi_main(handle, st)`
entry convention + `CYRIUS_TARGET_EFI` predefine — gnoboot
ergonomic fix #2 of 2**). Closes the second gnoboot-agent
enhancement filing; companion byte-array literal landed at
v5.11.51. Ergonomic, not a bug; both gnoboot ergonomic filings
now closed in two slots same-day as user-pinned split.

**Convention**:
```cyrius
kernel;
fn efi_main(handle, st): i64 {
    # RCX = ImageHandle, RDX = SystemTable
    return 0;   # EFI_SUCCESS
}
```

When `CYRIUS_TARGET_EFI=1` AND fn `efi_main` is registered,
cyrius emits an entry trampoline: save R14/R15 ← RCX/RDX right
after entry jmp; let EMIT_GVAR_INITS + PARSE_PROG run (they
clobber RAX/RCX/RDX, R14/R15 callee-saved); restore RCX/RDX
← R14/R15 before efi_main call; allocate 0x28 stack (MS x64
shadow + align); ECALLTO efi_main; restore stack; EEXIT under
EFI emits `ret` → firmware reads RAX as EFI_STATUS.

**Implementation** (3 sites in `src/main.cyr`):
1. **Env-var read** (`src/main.cyr:625`): `CYRIUS_TARGET_EFI=1`
   sets both `_is_pe_build=1` AND `_is_efi_build=1`.
2. **PP_PREDEFINE** (`src/main.cyr:670`): EFI build predefines
   BOTH `CYRIUS_TARGET_WIN` (so `lib/fnptr.cyr`'s MS-x64 fncallN
   branches fire) AND `CYRIUS_TARGET_EFI` (consumer
   discriminator). Mirror in `src/main_win.cyr:303`.
3. **Entry save + trampoline emit** (`src/main.cyr:1266` save,
   `:1346` trampoline). Save: `4C 89 CE` (mov r14, rcx) + `4C 89
   D7` (mov r15, rdx). Trampoline: fn-table scan for `efi_main\0`
   (same shape as existing main auto-call); on found, emit
   restore + sub rsp + ECALLTO + add rsp. EEXIT below emits ret.

**`lib/fnptr.cyr` doc refresh** — header doc-comment now
enumerates 3 ABIs explicitly: SysV (LINUX/MACOS), MS x64
(WIN/EFI), AAPCS64 subset (aarch64). No code change — the
existing TARGET_WIN branches (shipped v5.5.7) fire under EFI
builds via the new predefine.

**OVMF smoke** at slot work: bare `kernel; fn efi_main(handle,
st): i64 { return 0; }` boots cleanly under qemu+OVMF; firmware
reads `rax=0` (EFI_SUCCESS) and unwinds to BootManagerMenu.
Confirms entry save / restore / ECALLTO rel32 / EEXIT ret /
firmware rax-readback all working end-to-end.

**Out-of-scope (acknowledged)**:
- gnoboot rebuild verify deferred to gnoboot-agent task (consumer
  cleanup of ~50 lines → `fn efi_main` body).
- Manual smoke surfaced a GP fault when efi_main's body uses
  `var con_out = load64(st + 0x40);` — likely a cyrius emit
  pattern issue with chained loads through MS-x64-passed RDX, NOT
  the trampoline. Trampoline-only (bare `return 0;`) is clean.
  Separate concern, separate slot.

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-efi-main-convention.md`
→ `archived/`.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**827,976 B** / +2,216 from v5.11.51); `check.sh` **74/74**;
`cyrius test` **150/150**. Default-off path (no
`CYRIUS_TARGET_EFI`) byte-identical to v5.11.51.

**Next**: cycle returns to absorber buffer (.52 → .67) with
pinned .68 (heap-map full reorg) and .69 (conditional mabda fold).

**5.11.51** (shipped 2026-05-13 — **Byte-array literal
`var foo[N] = { 0x.., 0x.., ... };` — gnoboot ergonomic fix #1
of 2**). Closes `2026-05-13-gnoboot-byte-array-literal.md`.
Companion `fn efi_main` convention lands at .52.

**Syntax/semantics**:
- `[N]` allocates `N*8` bytes (existing cyrius semantic; arrays
  are 8-byte slots).
- Brace-list bytes initialise the first `k+1` bytes (zero rest);
  each must be NUM in `[0, 255]`. Hex/decimal/trailing-comma all OK.
- Capacity check `k+1 > N*8` is a hard parse error.
- Bytes are initialised by emitted `store8(&var + i, B)` sequences
  at top-level entry — same shape the consumer would write by
  hand; ~21 bytes of `.text` per byte. Future v6.x peephole/`.rdata`
  compaction possible.

**Implementation** (3-part):
1. **`EADDRA_IMM(S, n)`** named op per backend (`src/backend/{x86,
   aarch64,cx}/emit.cyr`) — `rax += imm`. x86: `48 05 imm32` (6 B);
   aarch64: `ADD x0,x0,#imm12` (`0x91000000 | (imm<<10)`, 4 B);
   cx: composed via `CX_MOVI` to scratch + add-reg.
2. **`PARSE_GVAR_ARR`** (`src/frontend/parse_decl.cyr:533`) — extended
   to accept `sti` param + optional `= { byte-list };` tail.
   Validates inline (parse-time errors on bad bytes / capacity)
   but **defers codegen** — saves `sti` to `gvar_toks` so pass-2
   replay can emit. Pass-1 emits land in dead code (skipped by
   entry-jmp patch).
3. **`EMIT_GVAR_INITS`** (`src/frontend/parse_decl.cyr:735`) — at
   replay, detects array-decl shape (`[` after IDENT) and emits
   per-byte: `EVADDR + EADDRA_IMM + EPUSHR + EMOVI + EPOPC +
   ESTORE8 + EXORAA`.

**Token-ID gotcha** (caught at slot bringup): `{` is token **13**,
`{` is **NOT** token 19 (which is `<`). Initial mis-map produced
`error: expected '<', got '{'` — the kind of confused-diagnostic
that consumers would file. Comment now names token IDs explicitly.

**Test coverage**: `tests/tcyr/byte_array_literal.tcyr` — 26
sub-asserts across 5 categories (ordering / zero-fill /
UTF-16LE interleave / boundary u8 / mixed-hex-decimal +
trailing-comma).

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-byte-array-literal.md`
→ `archived/`.

**Cross-arch**: all 3 backends ship `EADDRA_IMM` in this slot.
Deferred-emit is parser-side (backend-agnostic via named ops).
Not a half-fix.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**825,760 B** / +2,648 from v5.11.50); `check.sh` **74/74**;
`cyrius test` **150/150** (+1 new tcyr).

**Next**: v5.11.52 — `fn efi_main(handle, st)` convention +
`lib/fnptr.cyr` MS-x64 branch. The other gnoboot ergonomic
filing.

**5.11.50** (shipped 2026-05-13 — **Cap-drift detector + doc-size
currency gates + fresh-tier doc refresh**). Two new programmatic
gates in `programs/check.cyr` close recurring drift surfaces.
Plus immediate fix-forward of the stale cc5-size claims in
size-comparisons.md / platform-status.md / faq.md. Resolves the
v5.11.49-filed `2026-05-13-cap-drift-detector-gate.md` issue
same-day.

**Cap-drift gate** — `_cap_drift_gate()` cross-checks heap-map
comments at `src/main.cyr:24+` against inline literal caps in
`src/frontend/lex.cyr`. Three known surfaces verified:
`input_buf` (1 MB / 1048576), `tok_names` (256 KB / 262144 with
261872 inline guard accounting for 272 B LEXID slack), `str_data`
(2 MB / 2097152). Anchored on `0xADDR region_name` combos to
skip cross-reference NOTEs.

**Doc-size gate** — `_doc_size_currency_gate()` scans
size-comparisons.md / platform-status.md / faq.md / README.md
for `cc5 ~NNN KB` claims, verifies within ±50 KB of actual
build/cc5 (decimal KB). Lines with `(v5.X.Y)` historical tag
are exempt.

**Fresh-tier doc refresh** — size-comparisons.md cc5 739,672 B
(v5.8.31) → 823,112 B (v5.11.50); platform-status.md cc5 ~741 KB
(v5.8.65) → ~823 KB (v5.11.50); faq.md self-compile time 280 ms
→ 387 ms (post v5.10.40-.41 perf miniarc), cc5 size bumped to
~823 KB. Cross-compiler sizes refreshed (cc5_aarch64 506,216 B;
cc5_win 630,272 B). doc-health.md ledger header bumped.

**Helper fn** `_find_str_from(buf, n, from, needle, nlen)` —
bounded substring search returning absolute offset on hit or −1
on miss. Used by both new gates.

**Issue archive** —
`docs/development/issues/2026-05-13-cap-drift-detector-gate.md`
→ `archived/`. Filed during the v5.11.49 vidya cleanup; resolved
at .50 ship.

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**823,112 B** — unchanged from v5.11.49; gates are tooling, no
compiler change); `check.sh` **72 → 74**; `cyrius test`
**149/149**.

**Next**: two new gnoboot ergonomic-improvement issues filed
2026-05-13 by gnoboot agent (byte-array literal + efi_main
calling convention). User-pinned for .51/.52 (or .51 bundle
if scope fits).

**5.11.49** (shipped 2026-05-13 — **OVMF runtime smoke + arc
closeout; gnoboot MVP unblocker GA, arc KO**). Third and final
slot of the 3-slot UEFI Application emit arc. cyrius-compiled
`programs/efi_probe.cyr` boots end-to-end under qemu+OVMF and
prints `"hello, uefi"` to firmware's ConOut serial.

**Runtime bringup discovery**. Manual OVMF boot of v5.11.48
output produced `BdsDxe: failed to load ... Not Found`. Walk-
through: DOS+PE+Subsystem+DllChar+DataDirs all correct; **COFF
Characteristics = 0x0023 includes RELOCS_STRIPPED (0x0001)**.
UEFI firmware treats RELOCS_STRIPPED as "load me at exactly
ImageBase=0x140000000 or fail" — and OVMF's runtime services
occupy nearby pages so allocation fails silently → "Not Found".
Standard UEFI Application binaries (rEFInd, systemd-boot,
GRUB-EFI) NEVER set RELOCS_STRIPPED for exactly this reason.

**Fix**. `src/backend/pe/emit.cyr:714` COFF Characteristics
branch:
```cyrius
var _chars = 0x0023;
if (_pe_reloc_vsize != 0) { _chars = 0x0022; }
if (_TARGET_EFI_APPLICATION == 1) { _chars = 0x0022; }
```
EFI mode now clears RELOCS_STRIPPED unconditionally — firmware
can place at any free address; probe doesn't care (all addressing
is runtime register-indirect, no imm64 references); gnoboot will
care correctly once it has globals (covered by `.reloc`).

**Post-fix boot trace**:
```
BdsDxe: starting Boot0002 "UEFI QEMU HARDDISK QM00001 " ...
hello, uefi
BdsDxe: loading Boot0000 "BootManagerMenuApp" ...
```
Firmware loaded BOOTX64.EFI, jumped to AddressOfEntryPoint, our
inline-asm executed `SystemTable→ConOut→OutputString(L"hello,
uefi\r\n")`, returned EFI_SUCCESS, firmware unwound back to boot
manager menu. **End-to-end working.**

**_efi_ovmf_smoke_gate()** (new). `programs/check.cyr` registers
the runtime-floor gate right after `_efi_emit_gate`. Compiles
`efi_probe.cyr` via `_self_host_pipe_efi`; orchestrates a GPT-
disk-with-ESP build (parted + mtools + mcopy); runs the disk
under qemu+OVMF with `-serial stdio` capture; greps for
`"hello, uefi"`. Orchestration is a `/bin/sh -c '<one-liner>'
-- $efi_path` shell-out (test glue, not a separate
scripts/ovmf-smoke.sh deliverable). Graceful SKIP path if
qemu/parted/mtools/OVMF firmware missing — gate is opt-in via
test-environment presence. Negative-test verified: v5.11.48 cc5
(RELOCS_STRIPPED set) → gate FAILs `(sh rc=1)`; post-fix → PASS.

**Issue archive**:
`docs/development/issues/2026-05-13-gnoboot-uefi-application-emit.md`
→ `docs/development/issues/archived/`.

**gnoboot consumer status**: AGNOS Path C / gnoboot can pin
`cyrius = "5.11.49"` and start writing the sovereign UEFI
bootloader. Path A (ELF64 multiboot2 via GRUB) dead-on-iron;
Path C is the live MVP boot path.

**Arc summary (v5.11.47 → v5.11.49)**:
- cc5: 821,984 → **823,112 B** (+1,128 B total across 3 slots)
- check.sh: 70 → **72** (+2 gates: structural + runtime)
- 1 new cyrius source program: `programs/efi_probe.cyr` (64 LoC,
  inline-asm-only — no fixups, no globals)
- 1 filing closed (gnoboot UEFI emit issue, archived)
- Compile→runtime turnaround: same-day (filing in the morning →
  arc shipped + runtime-verified in the afternoon)

Self-host byte-identical (3-step cc5 → stage2 == stage3 at
**823,112 B**); `check.sh` **72/72**; `cyrius test` **149/149**.
Default-off path byte-identical to v5.11.48.

**Next**: gnoboot consumer agent picks up the unblocked toolchain.
Cyrius cycle returns to v5.11.x absorber buffer (.50 → .67 open;
.68 = heap-map full reorg, .69 = conditional mabda fold).

### Prior v5.11.x ships (one-liner per release; detail in CHANGELOG.md)

- **v5.11.54** — LSP papercut close + REX named ops + `_find_fn_by_name` helper. cyrius-lsp now prefers `$HOME/.cyrius/bin/cc5` for diagnostics so latest parser is used regardless of `cyrius.cyml` pin. 6 new MS-x64 named ops lock the REX bit in code. 5-deep+9-deep fn-lookup nested-ifs collapse to single helper. cc5 SHRANK 827,976 → 827,296 B (−680 B; first shrink in v5.11.x).
- **v5.11.53** — Hotfix: efi_main trampoline entry-save REX prefix `0x4C → 0x49` (was MR-form REX.R when r14/r15-as-dst needs REX.B). gnoboot caught within hours of .52 ship. New `_efi_trampoline_rex_gate` locks the encoding. check.sh 74→75.
- **v5.11.52** — `fn efi_main(handle, st)` entry convention + `CYRIUS_TARGET_EFI` predefine — gnoboot ergonomic fix #2 of 2. Closes second gnoboot-agent filing. Both filings closed same-day. (v5.11.53 hotfix landed for the REX prefix bug shipped with this slot.)
- **v5.11.51** — Byte-array literal `var foo[N] = { 0x.., 0x.., ... };` — gnoboot ergonomic fix #1 of 2 (the other lands at .52). New `EADDRA_IMM` named op on 3 backends; PARSE_GVAR_ARR extension + EMIT_GVAR_INITS replay path. Token-ID gotcha caught at bringup (`{` is 13, not 19). 26-assert tcyr.
- **v5.11.50** — Cap-drift detector + doc-size currency gates + fresh-tier doc refresh: `_cap_drift_gate()` cross-checks heap-map comments vs inline literal caps; `_doc_size_currency_gate()` scans fresh-tier docs for cc5 size refs (decimal KB ±50 KB tolerance); 4 docs refreshed v5.8.x → v5.11.50. check.sh 72→74.
- **v5.11.49** — OVMF runtime smoke + gnoboot arc closeout: RELOCS_STRIPPED cleared in EFI mode (UEFI firmware needs latitude to place anywhere); new `_efi_ovmf_smoke_gate()` boots efi_probe.efi under qemu+OVMF and asserts "hello, uefi" on serial. Arc filing → ship same-day. check.sh 71→72.
- **v5.11.48** — EFI Application probe + structural gate (gnoboot arc P2): `programs/efi_probe.cyr` (64 LoC, inline-asm-only); `_efi_emit_gate()` structural check (Subsystem=0xA, NX_COMPAT, Data Dirs zeroed, .text has ret); DllCharacteristics NX_COMPAT forced in EFI mode even without `.reloc`. check.sh 70→71.
- **v5.11.47** — UEFI Application PE emit mode + `_pe_ensure_*` refactor (gnoboot arc P1): `_TARGET_EFI_APPLICATION` flag, Subsystem byte 3→10 branch, EEXIT EFI variant (single `ret`), ExitProcess import skip + kernel32 fail-fast guard, Data Dirs [1]/[12] zeroed. 9 `_pe_ensure_<X>(S)` fns consolidated to single `_pe_register_kernel32` helper.
- **v5.11.46** — ELF64 kernel entry-arithmetic agreement (FIXUP ↔ EMITELF64_KERNEL) — agnos UEFI x86_64 boot regression fix; `_elf64_kernel_entry_gate()` added (check.sh 69→70).
- **v5.11.45** — P(-1) hardening sweep (4-item bundle): state.md compression 1451→583, `build/cc5` contamination gate, `cyrius vet` restored, dead-fn report behind `CYRIUS_DCE_VERBOSE=1`. check.sh 68→69.
- **v5.11.44** — `build/cc5` mabda-contamination restoration + cyrius-lsp `argv[0]` self-resolution + doc-cleanup bundle.
- **v5.11.43** — ELF64 kernel emit + multiboot2 + EFI64-entry tag — Path A for AGNOS UEFI x86_64 boot.
- **v5.11.42** — LSP `textDocument/semanticTokens/full` legend extension — locals + parameters colored. Roadmap doc-cleanup: -1258 lines (-51%).
- **v5.11.41** — CVE-08 security hardening (`cld` before `rep movsb`) + doc-cleanup: `completed-phases.md` phase-out trim + roadmap held-items reconciliation.
- **v5.11.40** — `f64_abs(x)` peephole — long-pinned optimization landed.
- **v5.11.39** — `ESWITCH_DISPATCH_*` named ops; drift gate extends to all 6 parse_*.cyr files.
- **v5.11.38** — Parser-to-emit named-op refactor — Class B missed-site + drift-prevention gate; ARC CLOSED.
- **v5.11.37** — Parser-to-emit named-op refactor — Class C (f64 unary ops).
- **v5.11.36** — Parser-to-emit named-op refactor — Class B (PIC-vs-direct address loads).
- **v5.11.35** — Parser-to-emit named-op refactor — Class D (v5.7.12 audit doc).
- **v5.11.34** — aarch64 user-binary ELF emitter section-header fix.
- **v5.11.33** — `PP_IFDEF_PASS` 2 MB cap raised to 8 MB; `preprocess_out` buffer relocated.
- **v5.11.32** — x86_64 user-binary ELF emitter section-header fix.
- **v5.11.31** — `cyrld` ELF64 user-binary linker section-header fix.
- **v5.11.30** — aarch64 kernel ELF emitter section-header fix.
- **v5.11.29** — Kernel ELF emitter: minimal section header table for GRUB multiboot compatibility.
- **v5.11.28** — bote parser quirk slot — closed as no-repro + diagnostic improvement + regression test.
- **v5.11.27** — aarch64-native build repair.
- **v5.11.26** — Per-repo isolation Part 3: `cyriusly use --global` flag + per-repo default.
- **v5.11.25** — Per-repo isolation Part 2: `cyrius` CLI version-resolved dispatcher.
- **v5.11.24** — `#derive(accessors)` >16-field silent miscompile fix.
- **v5.11.23** — PE32+ kernel32 path-API alignment fix.
- **v5.11.22** — ai-hwaccel `cc5_win` debunk + mkdir/unlink PE plumbing.
- **v5.11.21** — 0-call public stdlib fn downstream survey.
- **v5.11.20** — Syscall-wrapper DRY consolidation.
- **v5.11.19** — kybernet Part A.ii: `fn_table` 4096 → 8192 (heap-map refactor).
- **v5.11.18** — kybernet Part A.i + Part B: identifier buffer 2× + socket-syscall wrappers.
- **v5.11.17** — Per-repo isolation Part 1: `cyrius deps` stdlib_dir fix.
- **v5.11.16** — bote WS handshake key validation (RFC 6455 §4.1).
- **v5.11.15** — bote P2: streaming dispatch primitives.
- **v5.11.14** — bote P2: arena lifecycle terminator + per-frame reuse pattern.
- **v5.11.13** — bote P2 part A: `sock_set_recv_timeout` (Slowloris fix).
- **v5.11.12** — daimon P2: `lib/async.cyr` aarch64 portability fix.
- **v5.11.11** — TS test harness program.
- **v5.11.10** — Cyriusly cmdtools port closeout — full surface, cyriusly added to release bins, `scripts/cyriusly` retired from release.scripts.
- **v5.11.9** — Cyriusly cmdtools port — scaffold + light verbs.
- **v5.11.8** — `cyrius deps` symlink → file-copy.
- **v5.11.7** — Stdlib annotation arc — Phase 7: compiler-side internals + ARC CLOSE.
- **v5.11.6** — Cross-binary ship: `cc5_win` (PLATFORM BLOCKER unblock).
- **v5.11.5** — Stdlib annotation arc — Phase 6: partial-coverage closeouts + 9-sibling release fold-in.
- **v5.11.4** — Stdlib annotation arc — Phase 4: collection libraries.
- **v5.11.3** — Stdlib annotation arc — Phase 3: string/format completion.
- **v5.11.2** — Stdlib annotation arc — Phase 2: I/O surface.
- **v5.11.1** — Stdlib annotation arc — Phase 1: foundational core.
- **v5.11.0** — v5.11.x cycle OPEN — kavach P1 sandbox syscall wrappers + roadmap restructure.


Premise debunk: chat-side cross-host smoke wrappers used `cmd /c
"prog.exe & echo %errorlevel%"` which expands at parse time →
false-negative `exit=0`. Correct shapes (memory pin
`feedback_windows_errorlevel_test_wrapper` saved this slot):
`cmd /v /c "... !errorlevel!"` or `.bat` indirection
(`programs/check.cyr`'s `_pe_exit_gate` always used the correct
shape; chat-side wrappers diverged). Phantom claim propagated
through CHANGELOG entries [5.10.33] / .34 / .39 / .40 / .41 /
.44 / .47; this entry is the durable correction.

**Retroactive Phase 3 status update**: v5.10.47 struct-byval
Phase 3 cass runtime is **actually green** (Point repro
`syscall(60, run())` → cass exit=42 verified with `cmd /v`).
The arc was 4/4 across x86/pi/ecb/cass, not 3/4 as the .47
entry noted under bad-wrapper assumption. Per
`feedback_doc_canonical_no_redundancy`: .47 entry stays as
shipped; this .49 entry is the corrected record.

**Arc COMPLETE** (planned at v5.10.45 entry; see CHANGELOG [5.10.45]
"Arc shape" for the empirical premise-check that drove the
re-scoping):
- Phase 1 (v5.10.45, **shipped**) — x86 SysV via rax+rdx pair.
- Phase 2 (v5.10.46, **shipped**) — aarch64 AAPCS64 via X0+X1
  pair (Linux + Mach-O share ABI). pi runtime exit=42 ✓.
- Phase 3 (v5.10.47, **shipped — arc CLOSED**) — Cross-host
  matrix: local x86 + pi + ecb runtime green; cass compile-clean
  (runtime exit-code gated on pre-existing v5.10.49 PE gap).

Acceptance bar: `struct Point {x: i64; y: i64;}` + `fn make():
Point` + `var got: Point = make();` returns got.y correctly
(not lost to scalar-rax). Pre-v5.10.45 the high half was silently
dropped across ALL backends for value-typed 16B struct returns;
v5.10.28's f64v2 fix didn't generalize (f64v2 uses SSE-class
XMM0, int-class structs use rax+rdx). Str's 16B handle-shape is
preserved unchanged via `_STR_SID(S)` special-case carve-out.
Phase 1 x86 acceptance MET; aarch64 + PE staged for Phase 2/3.

Three new public verbs (`exec_vec_str` / `exec_capture_str` /
`exec_env_str`) parallel the cstr-shape `exec_vec` / `exec_capture`
/ `exec_env`. Each `_str` sibling extracts `str_data` on the way
into execve's argv (and envp for the env variant), so callers
using the natural cyrius idiom (`vec_push(args, str_from("/bin/
foo"))`) get a working verb. Runtime byte/Str dispatch was rejected
at slot entry — both shapes are pointers in cyrius's heap layout,
and the `load64(P)`-looks-like-a-pointer heuristic fails for 8+-
char cstrs (`"/usr/bin"` loads as 7.97e18). Argonaut-blocking
issue closed; consumers migrate via one-line patch
(`exec_vec(cstr)` → `exec_vec_str(Str)`). 6 sub-asserts in new
`tests/tcyr/process_exec_str.tcyr` all pass.

api-surface bumped 2873 → **2876** (+3 fns for the `_str` family).

**Headline numbers** (CYRIUS_PROF=1, `cc5 < src/main.cyr`,
best-of-5 median, end-to-end v5.10.x perf-arc gain pre-.40 → .41):
- lex phase: **603 ms → 62 ms (−90 %, ~9.7×)** [.40]
- fixup phase: **213 ms → 76 ms (−64 %, ~2.8×)** [.41]
- total compile: **1037 ms → 387 ms (−63 %, ~2.7×)** [.40+.41 combined]

v5.10.40 approach: length-bucketed linked-list dedup at heap region
`0x4E8C000..0x4EAD000` (132 KB brk extension; PE mmap had slack).
Per-length head into a 16384-entry chain table.

v5.10.41 approach: `fn_start_hash` open-addressing table at
`0x110000` (8192 slots × 2 B = 16 KB) reusing the 232 KB free gap
between `fn_name_hash` and `struct_ftypes` — no brk extension. Knuth
golden-ratio multiplicative hash; replaces two O(N²) DCE byte-scan
linear scans with ~2-probe lookups. aarch64 fixup has no DCE pass,
so x86-specific change (cross-arch propagation verified by reading
aarch64 fixup.cyr).

Cross-host verified at v5.10.40: pi (aarch64 Linux) native
self-host fixpoint b == c byte-identical at 567,672 B; ecb (macOS
Mach-O arm64) compile+run exit=42; cass (Windows PE) compile
exit=0. v5.10.41 smoke on cass green; pi/ecb byte-identical to
v5.10.40 (no aarch64 backend change).

**Slots .33 - .50 one-liner sweep**:
- **v5.10.33** — `lib/simd.cyr` typed wrappers around f64v_*
  intrinsics; first downstream consumption of typed-simd ABI
  Phase 5 (XMM0 return).
- **v5.10.34** — `lib/tls.cyr` early-data status accessors
  (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + 2 fns); sandhi
  1.1.0 → 1.3.3 fold (+1,194 lines); doc-health.md ledger
  introduced at this slot.
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness codegen fix
  via new `_SIMD_STASH` helper; covers ptyp 93-130 (8 intrinsics).
  Same bug-class hit again at v5.10.39 for ptyp 89-91 (separate
  dispatch path).
- **v5.10.36** — aarch64 V0 NEON register-class return for
  f64v2 (replaced v5.10.30 X0+X1 GPR pair); LDUR Q0 / STUR Q0
  for single-register transfer.
- **v5.10.37** — `f64v4` (32-byte packed-double) value type;
  parser + var-decl + extensions; pair-quad return ABI across
  x86 SSE, aarch64 NEON imm12-scaled deep-frame fallback, cx
  4-register r0..r3.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9
  + Phase 10); 0x1282000 fn_param_simd_mask heap region;
  cyrius-internal SysV split-counter (SIMD ordinal independent
  of int ordinal); per-backend ESTOREPARM_F64V*/ELOAD_F64V*_TO_XMM
  emission.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `f64v2_add_ptr`; `f64v2_add(x, y)` calls value-form
  base) + lib/simd.cyr full rewrite (50 public fns, value-form
  gated by CYRIUS_HAS_VAL_SIMD_PARAMS for non-PE targets).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table with per-length head chains; first-occurrence-
  wins canonical offset. lex 603→59 ms (10.2×), total 1037→510 ms
  (2×). Cross-host verified on pi/ecb/cass.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio hash) reusing
  free 232 KB gap. Replaces two O(N²) DCE byte-scan inner linear
  scans (seed + propagate). fixup 213→76 ms (2.8×), total 510→
  387 ms (1.32×). aarch64 fixup has no DCE — x86-specific.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises
  the verb inventory + lifecycle invariants + failure / partial-
  state contract across 24 public verbs. `lib/tls.cyr` header
  points to the doc. cc5 byte-identical (doc-only). No vidya
  entry (API surface, not gotcha). Snapshot-ping-pong guard
  applied via `~/.cyrius/lib/` mirror.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix. Runtime dispatch on `sep < 256` (byte path) vs `>= 256` (Str
  fat-pointer path); multi-byte Str sep supported. Closes the
  long-standing
  `2026-05-03-str-split-sep-treated-as-pointer.md` issue (live the
  entire v5.x cycle). `lib/process.cyr:224` cstr-sep bug fixed in
  same slot. cc5 byte-identical (lib-only; no compiler include).
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix.
  Parallel `_str` family (`exec_vec_str` / `exec_capture_str` /
  `exec_env_str`) — each extracts `str_data` on the way into
  execve's argv. Runtime dispatch rejected at slot entry (cstr 8+-
  char literals fail the pointer heuristic). Closes the argonaut-
  blocking
  `2026-05-10-process-exec-str-cstr-ambiguity.md`. api-surface
  2873 → 2876 (+3). cc5 byte-identical (lib-only).
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. New `_cur_fn_ret_pair` global,
  `EFLLOAD/STORE_STRUCT_INT_PAIR` x86 emit helpers (rax+rdx),
  caller-side `asv_pair` path mirroring asv_try. `_STR_SID(S)`
  carve-out preserves Str's 16B handle-shape unchanged. cc5
  +4,176 B. 14 sub-asserts in new `tests/tcyr/struct_byval_return.tcyr`.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs in
  `src/backend/aarch64/emit.cyr` replaced with LDUR/STUR X0,X1
  fast path + LDR/STR via X9 deep-frame fallback. Single change
  covers both Linux aarch64 + macOS arm64 (shared AAPCS64). pi
  runtime: minimal `struct Point` repro → exit=42 ✓ (was 7).
  cc5 byte-identical to v5.10.45 at 803,088 B (aarch64-only
  change). Phase 3 (.47 cross-host smoke + PE retptr verify)
  pinned next.

Per CLAUDE.md, slot-by-slot detail lives in `CHANGELOG.md` (source
of truth); closed cycles roll into `completed-phases.md` at each
minor close. The "Recent shipped" section below carries one-liners
for the current cycle.

## Compiler

- **cc5 (x86_64)**: **804,472 B** at v5.10.50 (unchanged
  from v5.10.48/.49; .50 is closeout — verify + docs +
  cleanup only). Full cycle delta: 753,768 B at v5.10.0 →
  804,472 B at v5.10.50 (+50,704 B / +6.7%); back-half delta
  (.39→.50): +7,008 B (.40/.41 perf miniarc +1,448 B;
  .42/.43/.44 flat; .45 +4,176 B; .46/.47 flat; .48
  +1,384 B; .49/.50 flat).
- **cc5_aarch64_native (cross-built)**: **587,048 B** at
  v5.10.47 (stable through Phase 2/3).
- **cyrius CLI**: ~170,900 B at v5.10.40 (flat across the
  cycle — `cyrius` doesn't run LEXID itself).
- **cc5_macho_arm (cross-built)**: **606,644 B** at
  v5.10.47. End-to-end run on ecb verified at Phase 3
  (exit=42).
- **cc5_win (cross)**: **701,440 B** at v5.10.47 (was
  ~696,832 B at v5.10.44; +4,608 B for the .45/.46
  emit helpers reaching the PE backend via x86 emit.cyr).
  (PE
  backend lives under x86, so the .45 emit helpers
  reach this binary — int-class pair-return ABI now
  available cross-compiled). PE retptr semantics for
  the same surface verify at Phase 3 (.47). PE mmap at
  0x5000000 has 1.5 MB slack past the v5.10.40 brk
  extension to `0x4EAD000`, no resize.
- **cc5_macho_arm (cross)**: ~590 KB at v5.10.40; mmap
  size bumped 0x4E8C000 → 0x4EAD000 to absorb the new
  LEXID region.
- **cc5_aarch64 native (Pi)**: **567,672 B** at v5.10.40
  (native self-host fixpoint b == c verified on pi
  2026-05-11). Cross-built variant from the x86 host is
  582,088 B; the cross/native byte delta is the standard
  "first-bootstrap differs from native rebuild" shape, b
  == c on the native side is the authoritative check.

> Per-slot byte-delta history is in `CHANGELOG.md` (source of truth)
> and `completed-phases.md` (closed cycles). This section tracks
> CURRENT sizes only; closeout passes consolidate per-slot detail
> into the cycle summary at `completed-phases.md`.

- **Self-host fixpoint**: 3-step (cc5_a → cc5_b → cc5_c, b == c) clean at both
  `IR_ENABLED == 0` and `IR_ENABLED == 3` (since v5.6.16).
- **IR=3 NOP-fill on cc5 self-compile** (v5.6.18 baseline carries forward;
  v5.6.19 adds infrastructure only, no codegen change): 135 folds + 678 DCE +
  15 DSE + 567 LASE = 1,395 candidates / **6,099 B**. v5.6.27 compaction
  sweeps picker NOPs at IR=0 only; IR=3 NOP harvest (DSE/LASE/const-fold)
  pinned for a future slot — needs same-shape tracking added to those passes.
- **Regalloc** (v5.6.20–v5.6.24): per-fn live-interval tables (v5.6.19) +
  Poletto-Sarkar picker (v5.6.20) + asm-skip lookahead (v5.6.23) +
  fixed SysV stack-arg shuttle (v5.6.24). **Default-on as of v5.6.24**
  (`CYRIUS_REGALLOC_AUTO_CAP=0` to disable; previously opt-in via
  `#regalloc` only). Picker pins up to 5 locals to rbx/r12-r15.
  v5.6.24 fixed the SysV ECALLPOPS r12-r14 clobber that surfaced as
  the "live-across-calls" bug (sandhi-reported / flags-test
  test_str_short→test_defaults bisection). `CYRIUS_REGALLOC_DUMP=1`
  prints intervals; `CYRIUS_REGALLOC_PICKER_CAP=N` caps assignments
  for bisection.

## Suites

Current at v5.11.0 (v5.11.x cycle OPEN). Cross-host gates wire through `~/.ssh/config`
hosts: **pi = Linux aarch64**, **ecb = Apple Silicon Mach-O arm64**,
**cass = Windows 11 PE32+**.

- **check.sh**: ~66/66 PASS (typed-simd ABI arc added the
  `simd_overload_dispatch.tcyr` gate at v5.10.39; .38 added
  `f64v2_byval_param.tcyr`; .37 added `f64v4_byval_return.tcyr`;
  .34 added `tls_early_data_status.tcyr`).
- **`tests/tcyr/*.tcyr`**: ~135 files (v5.10.x added at least
  9 gates: tls_early_data_status, simd, simd_typed_wrappers,
  f64v2_byval_return, f64v4_byval_return, f64v2_byval_param,
  simd_overload_dispatch, plus REAL TYPE SYSTEM gates).
- **`tests/scyr/*.scyr`**: 1 soak harness (alloc_pressure).
- **`tests/smcyr/*.smcyr`**: 1 smoke harness (compile_minimal).
- **`fuzz/*.fcyr`**: 5 harnesses.
- **`benches/*.bcyr`**: 14 benchmarks.
- **Release toolchain**: 10 bins.
- **Stdlib**: 79 modules (v5.9.0 niyama 1.0.1 fold; v5.10.34
  sandhi 1.1.0 → 1.3.3 refresh fold +1,194 lines).
- **api-surface**: ~2873 entries (from `docs/api-surface.snapshot`
  generated artifact; was 2792 at v5.9.42 close).

Per-slot test-gate detail in `CHANGELOG.md`. Older suite-growth
narrative in `completed-phases.md`.

## In-flight

**v5.10.x cycle CLOSED at 50 slots (2026-05-11).** THREE
completed arcs (typed-simd ABI 11 phases, REAL TYPE SYSTEM 5
phases, struct-byval ABI 3 phases) plus a compile-time-perf
miniarc (.40+.41, 2.7× total compile speedup) plus the TLS
contract pin (.42) plus the roadmap-extension open-issues sweep
(.43/.44/.48 close all 4 v5.10.42-audit issues) plus the
v5.10.49 PE premise-debunk (15-slot phantom closed) plus the
v5.10.50 closeout pass anchor the cycle. **v5.11.0 opens next.**

1. **REAL TYPE SYSTEM** 5-phase arc (v5.10.1 - v5.10.26) — type
   annotations parsed + stored, call-site arg checking, overload
   dispatch on param-type fingerprint, return-type recording,
   sum-type rewriting. Unblock for the typed-simd value-form param ABI.

2. **Typed-simd value-type ABI** 11-phase arc (v5.10.28 - v5.10.39) —
   f64v2 + f64v4 as primitive value types with end-to-end XMM/V
   register-pair param + return ABI across x86 SysV / aarch64 NEON /
   cx bytecode / macho-arm64 / Win64 PE (retptr-style fallback).
   Closed with parser-side `&IDENT → _ptr` overload dispatch and
   the full `lib/simd.cyr` value-form/pointer-form surface (50 fns).

3. **v5.10.40 + v5.10.41 compile-time-perf miniarc** —
   length-bucketed LEXID dedup at v5.10.40 cut lex 603→59 ms
   (10.2×); fn_start_hash in fixup DCE at v5.10.41 cut fixup
   213→76 ms (2.8×). End-to-end gain: total compile-time
   **1037 → 387 ms (2.7×)** on cc5 self-compile. v5.10.0
   profile-guided "compile-time wins" held entry now realised
   across both phases.

4. **v5.10.42 TLS hook-surface contract** — new
   `docs/development/lib-tls-contract.md` pins the
   invariant layer for the `lib/tls.cyr` ↔ `lib/sandhi.cyr`
   surface that stabilised across .40/.13/.21/.27/.34.

5. **v5.10.43 + v5.10.44 open-issues sweep — stdlib
   Str/cstr disambiguation** — v5.10.42-ship roadmap-
   extension audit promoted 4 open issues into v5.10.x
   slots; .43 + .44 close the two Medium-severity bugs:
   - v5.10.43: `str_split` sep-treated-as-pointer (live
     entire v5.x cycle). Runtime dispatch on `sep < 256`
     preserves all 21+ stdlib byte-int callers byte-
     identical AND fixes Str-sep semantics.
   - v5.10.44: `exec_*` family was cstr-only with no
     docstring contract; argonaut-blocking on Str pushes.
     Parallel `_str` family added (`exec_vec_str` /
     `exec_capture_str` / `exec_env_str`); runtime
     dispatch rejected because both Str/cstr are
     pointers and 8+-char cstrs fail the heuristic.

6. **v5.10.45 + v5.10.46 + v5.10.47 struct-by-value ABI
   arc (CLOSED)** — pin re-scoped at v5.10.44 ship after
   empirical premise check showed the original "macOS arm64
   struct-byval" pin was mis-framed: the underlying bug
   (16B int-class struct returns lose the high half) was
   live across ALL backends, not just Mach-O. User authorized
   expansion into a 3-phase arc.
   - **.45**: x86 SysV via rax+rdx pair, `_STR_SID(S)`
     carve-out preserving Str's legacy handle-shape.
   - **.46**: aarch64 AAPCS64 X0+X1 pair (covers Linux
     + Mach-O via shared ABI). Verified on pi (exit=42).
   - **.47**: Cross-host smoke matrix established. Verified
     on pi (exit=42), ecb (exit=42 codesigned), local x86
     (tcyr 14/14). cass compile-clean; runtime exit-code
     gated on v5.10.49 PE exit-code propagation fix. Win64
     ABI deviation from strict MS x64 spec acknowledged
     (cyrius-internal-ABI uses rax+rdx pair; closed-system
     no-consumer-impact rationale documented).

Additional in-cycle work: TLS early-data surface completion at
v5.10.34 (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + accessors);
sandhi 1.1.0 → 1.3.3 refresh fold at v5.10.34; doc-health.md
ledger scaffolded at v5.10.34; vidya wrap-up pass paired with
v5.10.39 (retro file + 3 gotcha entries + 3 feature entries).

**Cycle stats (final, v5.10.50 close)**:
- cc5: 753,768 B at v5.10.0 → **804,472 B at v5.10.50** (+50,704 B, +6.7%)
- cc5_aarch64_native: ~470 KB at v5.10.0 → **587,048 B at v5.10.47**
- cc5_macho_arm: ~510 KB at v5.10.0 → **606,644 B at v5.10.47**
- cc5_win: ~530 KB at v5.10.0 → **701,440 B at v5.10.47**
- api-surface: 2792 → **2876 entries** (+3 v5.10.44 `_str` fns)
- New `lib/simd.cyr` (50 public fns)
- New `docs/development/lib-tls-contract.md` (v5.10.42)
- New `tests/tcyr/str_split.tcyr` (v5.10.43, 35 sub-asserts)
- New `tests/tcyr/process_exec_str.tcyr` (v5.10.44, 6 sub-asserts)
- New `tests/tcyr/struct_byval_return.tcyr` (v5.10.45, 14 sub-asserts)
- **Compile time 1037 → 387 ms (2.7×) across .40 + .41 miniarc**
- 3 locname-staleness surfacings (v5.10.35 fixed ptyp 93-130; v5.10.39
  fixed the duplicate at ptyp 89-91 missed by .35); install.sh
  `cp -L` same-file collision discovered (workaround manual; fix
  pinned for v5.10.50 closeout)

**Closeout pinning**: roadmap has v5.10.45 - v5.10.50 slotted for
the remaining v5.10.x work. Full v5.10.x retro at
`../../../vidya/content/cyrius/field_notes/compiler/retros/v510x.cyml`.

## Recent shipped (one-liner per release)

v5.10.x cycle through 2026-05-11 (CLOSED at v5.10.50):

- **v5.10.50** — cycle closeout. 11-step CLAUDE.md closeout pass
  all green: mechanical (3-step + bootstrap + check.sh 66/66 +
  heapmap 96/0/0), judgment (heap-map clean, 34 dead-fn floor
  unchanged, no x86 leaks, refactor noted), compliance (security
  + downstream all pinned to released tags), doc sync (vidya
  retro back-half + 3 features.cyml entries). One cleanup
  finding: `bootstrap/verify.sh` `stage1/` path fixed. cc5
  byte-identical. v5.11.0 opens next.
- **v5.10.49** — Win64 PE `println` + exit-code premise-debunk
  (no code change). Empirical re-test shows both pinned pieces
  work today; the "broken" claims were a 15-slot chat-side
  test-wrapper bug (`cmd /c "& echo %errorlevel%"` parse-time
  expansion). Memory pin saved. v5.10.47 struct-byval Phase 3
  cass retroactively confirmed exit=42 (arc 4/4, not 3/4).
  cc5 byte-identical to v5.10.48.
- **v5.10.48** — Defensive sweep + parser cosmetic limits (7-item
  bundle). Bare `return;` synthesizes `return 0;`; enum-ident
  array sizes accepted in BOTH PARSE_ARRAY + PARSE_GVAR_ARR;
  parse_fn.cyr AARCH64 defensive guards; `run_script` file_exists
  guard. Premise-checked 3 items as already-resolved/out-of-
  scope. cc5 +1,384 B. 4 open issues from the v5.10.42 audit
  now all closed.
- **v5.10.47** — struct-by-value ABI arc Phase 3: cross-host smoke
  + PE retptr verify (arc CLOSED). 4-target matrix: x86 (tcyr
  14/14), pi (exit=42), ecb (exit=42 codesigned), cass (compile=0;
  runtime gated on .49). Win64 ABI deviation acknowledged. cc5
  byte-identical to v5.10.45/.46.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs replaced with real
  LDUR/STUR X0,X1 encodings + LDR/STR X9 deep-frame fallback.
  Linux aarch64 + macOS arm64 covered (shared ABI). pi runtime
  verify: struct Point 7+35 repro → exit=42 ✓. cc5 byte-identical
  to v5.10.45 (aarch64-only change). cc5_aarch64_native +4,960 B.
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. `_cur_fn_ret_pair` flag set by rough-scan
  when fn returns 9-16B non-Str struct; PARSE_RETURN emits
  `mov rax,[&v+0]; mov rdx,[&v+8]`; caller `asv_pair` path mirrors
  the layout. `_STR_SID(S)` carve-out preserves Str's handle-mode.
  14 sub-asserts. Phase 2 (.46 aarch64) + Phase 3 (.47 cross-host)
  pinned.
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix
  (parallel `_str` family). Three new public verbs (`exec_vec_str`
  / `exec_capture_str` / `exec_env_str`); each extracts `str_data`
  on the way into execve's argv. Runtime dispatch rejected (cstr
  8+-char literals fail the pointer heuristic). Closes argonaut-
  blocking `2026-05-10-process-exec-str-cstr-ambiguity.md`. 6
  sub-asserts. api-surface 2873 → 2876.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix (runtime byte/Str dispatch). Closes the long-standing issue
  filed at `docs/development/issues/2026-05-03-str-split-sep-
  treated-as-pointer.md`. `sep < 256` → byte path; `sep >= 256` →
  Str fat-pointer path with multi-byte sep support. cc5 byte-
  identical (lib-only). 12 test groups / 35 sub-asserts.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises 24
  public verbs (availability / connect-fused / connect-staged /
  I/O / hook-time config / session resumption / session cache cbs /
  0-RTT / soft-deprecated `tls_dlsym` escape hatch). cc5 byte-
  identical (doc-only); 3-step fixpoint clean.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio multiplicative
  hash) reusing free 232 KB gap; replaces two O(N²) DCE byte-scan
  linear scans. fixup 213→76 ms (2.8×), total 510→387 ms (1.32×).
  aarch64 fixup has no DCE — x86-specific (PE backend reached too).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table; first-occurrence-wins canonical offset. lex
  603→59 ms (10.2×), total 1037→510 ms (2.0×). Cross-host verified
  on pi (native fixpoint b == c at 567,672 B) / ecb / cass.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `_ptr` sibling) + `lib/simd.cyr` value-form/pointer-form
  surface (50 fns). Typed-simd ABI arc CLOSED at Phase 11.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9-10);
  0x1282000 fn_param_simd_mask; cyrius-internal SysV SIMD split-counter.
- **v5.10.37** — f64v4 (32-byte packed-double) value type; pair-quad
  return ABI across all backends.
- **v5.10.36** — aarch64 V0 NEON register-class return for f64v2
  (replaced X0+X1 GPR pair).
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness fix + `_SIMD_STASH`
  helper; threat-model + fncall-abi doc refresh.
- **v5.10.34** — `lib/tls.cyr` early-data status accessors; sandhi
  1.1.0 → 1.3.3 fold; doc-health.md ledger introduced.
- **v5.10.33** — `lib/simd.cyr` typed wrappers (first downstream
  consumption of typed-simd ABI Phase 5 XMM0 return).
- **v5.10.32** — typed-simd ABI Phase 5: x86 SysV XMM0 single-register
  return for f64v2 (replaced int-class rax/rdx pair).
- **v5.10.31** — typed-simd ABI Phase 4: Win64 PE retptr-style fallback.
- **v5.10.30** — typed-simd ABI Phase 3: aarch64 NEON V0 return.
- **v5.10.29** — typed-simd ABI Phase 2: x86 SysV f64v2 return path.
- **v5.10.28** — typed-simd ABI Phase 1: f64v2 as primitive value type.
- **v5.10.27** — REAL TYPE SYSTEM closeout consolidation.
- **v5.10.26** — Phase 5: sum-type rewriting + derive-friendly.
- **v5.10.25** — `_str` / `_int` / `_cstr` overload pattern.
- **v5.10.22-24** — overload dispatch refinement.
- **v5.10.21** — TLS surface filling.
- **v5.10.20** — P(-1) sweep.
- **v5.10.13-19** — TLS Phase + agnosys cascade close + `_init_cyrius_lib`
  hardening.
- **v5.10.1-12** — REAL TYPE SYSTEM Phases 1-4; agnosys 1.1.12 cascade;
  vyakarana cap unblock; net/tls Phase 1; `_check_shadow_lib`.
- **v5.10.0** — per-phase compile-time profiling (`CYRIUS_PROF=1`).

(Slot-by-slot detail in `CHANGELOG.md`. Earlier cycles in
`completed-phases.md`.)

## Consumers

AGNOS kernel, agnostik (58 tests), agnosys (20 modules), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests).

All AGNOS ecosystem projects depend on the compiler and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

## Bootstrap chain

```
bootstrap/asm (29 KB committed binary — root of trust)
  → cybs (bootstrap compiler; formerly cyrc, renamed v6.0.0)
    → cycc (modular compiler + IR; formerly cc5, renamed v6.0.0)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win (Windows PE32+ cross-compiler)

(bridge.cyr — the old intermediate stage — was retired at v5.11.66.)
No Rust. No LLVM. No Python. Just sh + Linux x86_64.
Build: sh bootstrap/bootstrap.sh
```
