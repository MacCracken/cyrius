# Cyrius Threat Model

> **Scope**: Cyrius is a systems language compiler and toolchain.
> It generates native binaries (ELF / Mach-O / PE) from source code.
> Zero external **language** dependencies. Zero unsafe code in
> compiler/stdlib by construction (assembly up). Stdlib **may**
> bridge to system libraries (libssl, libc) via the v5.6.37
> fdlopen-bootstrapped helper — see Trust Boundaries below.
>
> **Last reviewed**: 2026-06-06 (v6.0.83) — adds the sovereign native TLS backend.

## Trust Boundaries

| Boundary | Trust Level |
|----------|-------------|
| 29KB seed binary (bootstrap/asm) | Root of trust — auditable, committed, byte-exact |
| Source code (src/, lib/, programs/) | Trusted — developer-controlled |
| User input (compiled programs) | Untrusted — may contain arbitrary code |
| Syscall interface (Linux kernel) | Trusted — OS provides memory isolation |
| Generated binaries | Untrusted until verified — self-hosting proves compiler correctness |
| `~/.cyrius/dlopen-helper` (v5.6.37+) | Trusted — built by `install.sh` from cyrius source; used by `fdlopen.cyr` to bootstrap real glibc for libssl bridge. Missing helper = TLS / libssl features disabled at runtime, not a security risk. |
| Linked `libssl.so.3` / `libcrypto.so.3` (default backend, when `tls_available() == 1`) | System-trusted — the host's OpenSSL. Stdlib `lib/tls.cyr` is a thin bridge; OpenSSL CVEs apply transitively when used. **Built with `-D CYRIUS_TLS_NATIVE` there is NO libssl dependency** — TLS runs on the in-tree native stack (`lib/tls_native.cyr` + sigil crypto/x509), so OpenSSL CVEs do not apply. |

## Attack Surface

| Area | Risk | Mitigation |
|------|------|------------|
| **Buffer overflow in compiler** | Malicious input overflows tok_names, codebuf, or fixup table | Bounds checks on ADDTOK (65536), LEXID (65000), fixup (1024) |
| **Heap layout corruption** | Adjacent buffers overflow silently | Guard checks, documented HEAP MAP, P-1 hardening |
| **Preprocessor path traversal** | `include "../../../etc/passwd"` reads arbitrary files | `READFILE` in `lib/lex.cyr` rejects `..` path components by default; `CYRIUS_ALLOW_PARENT_INCLUDES=1` env override exists for sibling-dep projects (bote pattern) and is auto-set by `cyrius build` when resolving relative-path deps. CVE-02 hardening, shipped v5.x. |
| **Integer overflow in alloc** | Large allocation wraps to small size | brk return value checked; returns 0 on failure |
| **Code injection via inline asm** | `asm { ... }` emits arbitrary bytes | By design — asm is a power tool, not a vulnerability |
| **Denial of service** | Extremely large source files | Input buffer capped at 131KB; token array at 65536 |
| **Supply chain** | Compromised compiler binary | **Narrow-scope self-hosting verification**: the compiler must produce byte-identical output when recompiling its own source (3-step fixpoint `cc_a → cc_b → cc_c; b == c`; pre-v5 this was `cc3 == cc3`, now `cycc → cycc_b → cycc_c`). This invariant is check.sh-enforced on every commit across all active targets. **Note on scope**: this mitigates trusting-trust attacks against the compiler's own codegen only. It does NOT address platform-loader tolerance of the emitted binary (a separate "broad-scope" property — see `docs/architecture/cyrius.md` §"Self-hosting: two scopes of byte-identity"). |
| **Bootstrap trust** | Trusting the committed 29KB seed | Diverse double compilation possible; seed is auditable |

## Known Limitations

| Limitation | Impact | Planned Fix |
|-----------|--------|-------------|
| No memory safety | Buffer overflows in user programs possible | Ownership/borrow checker (v1.0+) |
| No stack canaries | Stack smashing undetected | Compiler-inserted canaries (future) |
| No ASLR | Predictable memory layout | Polymorphic codegen (post-v1.0) |
| No sandboxing | Generated binaries have full syscall access | Sandbox-aware borrow checker (post-v1.0) |
| Fixed-size arrays | Compiler crashes on capacity overflow | Dynamic allocation or larger fixed sizes |

## Security Scanning

`cybs vet` scans for dangerous patterns:
- Raw `syscall(59, ...)` (execve) outside process.cyr/agnosys
- Unbounded loops without break conditions
- Missing null checks on pointer arguments

`cybs deny` enforces policy:
- No shell execution in library code
- No network syscalls in core libraries
- Trusted path validation for include directives

## Reporting

Security issues: security@agnos.dev
Response SLA: 48 hours
Disclosure: 90-day coordinated

## Stdlib TLS surface (v5.7.0+; native backend v6.0.74–.83)

`lib/tls.cyr` has two backends behind one verb contract. **Default:** brokers
TLS 1.2/1.3 via OpenSSL's `libssl.so.3` (below). **Opt-in (`-D CYRIUS_TLS_NATIVE`):**
the sovereign native stack `lib/tls_native.cyr` — TLS 1.2 + 1.3, auth via ECDSA
P-256/P-384 + RSA (PSS / PKCS#1 v1.5) + Ed25519, AES-128/256-GCM + ChaCha20-Poly1305,
EMS, ALPN, OS trust-store + intermediate-chain + SNI-hostname verification, server-flight
reassembly — no OpenSSL, crypto/x509 in-tree (sigil). Backend-agnostic peer-introspection
verbs `tls_get_alpn_selected` / `tls_get_peer_spki_der` (v6.0.82). Live-Cloudflare- +
OpenSSL-interop-proven. The libssl-bridge surface (legacy):

`lib/tls.cyr` brokers TLS 1.2/1.3 via OpenSSL's `libssl.so.3`,
bootstrapped through fdlopen for correct pthread TCB layout
(pre-v5.6.37 in-tree dynlib_open caused `SSL_CTX_new` to
deadlock on its first futex). Capabilities surfaced through
`tls_supports_*()` probes; consumers (sandhi 1.x) fall back
to a non-TLS path on unsupported hosts.

| Wave | Slot | Surface |
|------|------|---------|
| Core | v5.6.37 / v5.6.40 | `tls_connect` / `tls_connect_with_ctx_hook` / `tls_set_alpn` / `tls_set_verify` |
| Session resumption + 0-RTT primitives | v5.10.21 | `tls_get_session` / `tls_set_session` / `tls_session_free` / 3 session-cache callbacks / `tls_ctx_set_max_early_data` / `tls_write_early_data` / `tls_read_early_data` |
| Client-side staged connect | v5.10.27 | `tls_connect_alloc` + `tls_connect_complete` (closes the timing-window gap for session-resumption) |
| Client-side 0-RTT acceptance + eligibility | v5.10.34 | `tls_get_early_data_status` + `tls_session_get_max_early_data` (sandhi 1.3.2 unblock per `sandhi/docs/issues/2026-05-10-stdlib-tls-early-data-status.md`) |

**Security caveats for TLS users**:
- Replay-attack mitigation for 0-RTT is the **consumer's**
  responsibility (sandhi's session-cache impl bounds early-data
  budget per cache entry). Stdlib enforces no replay window.
- `tls_set_verify(handle, mode, callback)` — passing a permissive
  callback (always returns 1) disables peer verification.
  Consumers are expected to call default-path setup
  (`SSL_CTX_set_default_verify_paths` via `tls_connect`'s
  internals) and only override the callback for mTLS / pinning.

## Design Principles

- Zero external language dependencies — no crates.io supply chain
- Self-hosting verification after every compiler change
- Byte-exact reproducibility — same source always produces same binary
- Fixed heap layout is documented and auditable
- P-1 hardening before every feature release
- `cyrius audit` must pass before every commit
