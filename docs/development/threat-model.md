# Cyrius Threat Model

> **Scope**: Cyrius is a systems language compiler and toolchain.
> It generates native binaries (ELF / Mach-O / PE) from source code.
> Zero external **language** dependencies. Zero unsafe code in
> compiler/stdlib by construction (assembly up). Stdlib **may**
> bridge to system libraries (libssl, libc) via the v5.6.37
> fdlopen-bootstrapped helper — see Trust Boundaries below.
>
> **Last reviewed**: 2026-07-01 (v6.3.21 — security-audit tail; RM-02 refresh + CVE-09/11 closed).
> Seed boundary: `seed → cybs → cycc` is byte-identical-derivable (CVE-20 resolved 2026-06-20),
> enforced every release via `scripts/release-gate.sh` (step 2). Current facts: native TLS is the
> *default* backend (since v6.1.21, not opt-in), PIE/ASLR ships (since v6.1.6), the input buffer is
> 1 MB **and the output buffer 16 MB** (both raised v6.1.27), and the binary-release trust root is
> the committed `build/cycc` (CVE-20). **CVE-09** (x86 jump-target overflow) now HARD-ERRORS past
> 1023 targets/fn instead of silently mis-eliminating (v6.3.21); **CVE-11** (stack canaries) is
> accepted-with-rationale (see Known Limitations); **CVE-10** (tmp-file race) fixed v4.10.0.

## Trust Boundaries

| Boundary | Trust Level |
|----------|-------------|
| 29KB seed binary (bootstrap/asm) | **Source-level** root of trust — auditable, committed, byte-exact. **(CVE-20, RESOLVED 2026-06-20)** the seed assembles `cybs`, which compiles `src/main.cyr` to a `cycc` that self-hosts byte-identical to the committed `build/cycc` — so `build/cycc` is now **machine-derivable from the 29 KB seed** (no bridge). Enforced every release by `seed-derive-cycc.sh` (= `release-gate.sh` step 2). NOTE: the cycc self-host fixpoint does NOT cover this chain — cybs is far more limited (v6.3.0 seed break). |
| Source code (src/, lib/, programs/) | Trusted — developer-controlled |
| User input (compiled programs) | Untrusted — may contain arbitrary code |
| Syscall interface (Linux kernel) | Trusted — OS provides memory isolation |
| Generated binaries | Untrusted until verified — self-hosting proves compiler correctness |
| `~/.cyrius/dlopen-helper` (v5.6.37+) | Trusted **for non-setuid callers only** — built by `install.sh` from cyrius source; used by `fdlopen.cyr` to bootstrap real glibc for libssl bridge. Missing helper = TLS / libssl features disabled at runtime, not a security risk. **⚠ NOT trusted for setuid-root callers:** the path resolves inside the *invoking user's* `$HOME`, which a non-root caller of a setuid binary owns and can replace — `fdlopen` would then `execve` it **as root** (arbitrary root code execution). Setuid consumers (e.g. shakti) MUST use `fdlopen_init_trusted()` (v6.1.29), which resolves the root-owned `/usr/lib/cyrius/dlopen-helper`, `lstat`-verifies it (regular file, uid 0, not symlink, not group/other-writable), never consults `$HOME`, and fails closed (`FDL_ERR_UNTRUSTED` = -9). |
| Linked `libssl.so.3` / `libcrypto.so.3` (**opt-in** legacy backend, `-D CYRIUS_TLS_LIBSSL`) | System-trusted — the host's OpenSSL. **Default builds use the in-tree native stack** (`lib/tls_native.cyr` + sigil crypto/x509) and have NO libssl dependency, so OpenSSL CVEs do not apply. They apply transitively only when the bridge is explicitly opted into with `-D CYRIUS_TLS_LIBSSL` (default polarity inverted at v6.1.21). |

## Attack Surface

| Area | Risk | Mitigation |
|------|------|------------|
| **Buffer overflow in compiler** | Malicious input overflows tok_names, codebuf, or fixup table | Bounds checks on ADDTOK (1,048,576), LEXID dedup (16,384), and the **growable** fixup table (×2 grow, 64 MiB ceiling, v6.2.0) |
| **Heap layout corruption** | Adjacent buffers overflow silently | Guard checks, documented HEAP MAP, P-1 hardening |
| **Preprocessor path traversal** | `include "../../../etc/passwd"` reads arbitrary files | `READFILE` in `lib/lex.cyr` rejects `..` path components by default; `CYRIUS_ALLOW_PARENT_INCLUDES=1` env override exists for sibling-dep projects (bote pattern) and is auto-set by `cyrius build` when resolving relative-path deps. CVE-02 hardening, shipped v5.x. |
| **Integer overflow in alloc** | Large allocation wraps to small size | brk return value checked; returns 0 on failure |
| **Code injection via inline asm** | `asm { ... }` emits arbitrary bytes | By design — asm is a power tool, not a vulnerability |
| **Denial of service** | Extremely large source files | Input buffer capped at 1 MB (raised 512 KB → 1 MB, v6.1.27); output buffer capped at 16 MB (raised 2 MB → 16 MB, v6.1.27); preprocess-out 8 MB (v5.11.33); token array at 1,048,576 (v5.8.46); x86 jump-target table capped at 1023/fn — **hard-error past it** (CVE-09, v6.3.21) rather than silent LASE mis-elimination |
| **Supply chain** | Compromised compiler binary | **Narrow-scope self-hosting verification**: the compiler must produce byte-identical output when recompiling its own source (3-step fixpoint `cc_a → cc_b → cc_c; b == c`; pre-v5 this was `cc3 == cc3`, now `cycc → cycc_b → cycc_c`). This invariant is check.sh-enforced on every commit across all active targets. **Note on scope**: this mitigates trusting-trust attacks against the compiler's own codegen only. It does NOT address platform-loader tolerance of the emitted binary (a separate "broad-scope" property — see `docs/architecture/cyrius.md` §"Self-hosting: two scopes of byte-identity"). |
| **Bootstrap trust** | Trusting the committed 29KB seed | Diverse double compilation possible; seed is auditable |

## Known Limitations

| Limitation | Impact | Planned Fix |
|-----------|--------|-------------|
| No memory safety | Buffer overflows in user programs possible | Ownership/borrow checker (v1.0+) |
| No stack canaries (**accepted — CVE-11, v6.3.21**) | Stack smashing on a thread stack is caught, not silent | **Accept-with-rationale:** canaries are not emitted. A `PROT_NONE` guard page below every thread stack (**CVE-29, v6.2.44**) turns a stack overflow into a loud SIGSEGV — the same detect-and-crash outcome a canary gives. **W^X** code/data separation (v6.3.12) makes injected stack data non-executable (blocks ROP/JOP payloads), and opt-in **PIE/ASLR** (v6.1.6) removes address predictability. For a bare-metal-first sovereign systems language, this multi-layer defense is preferred to per-call canary overhead. Revisit if a consumer profiles a real canary-shaped gap (e.g. a non-thread stack without a guard page). |
| PIE/ASLR is opt-in | Non-PIE binaries have a predictable layout | **PIE codegen shipped v6.1.6** — `--pie` / `CYRIUS_PIE=1` emits `ET_DYN` so the loader applies ASLR (x86_64 + aarch64 userland). Default output is still non-PIE `ET_EXEC`; pass `--pie` for ASLR. |
| No sandboxing | Generated binaries have full syscall access | Sandbox-aware borrow checker (post-v1.0) |
| Fixed-size arrays | Compiler crashes on capacity overflow | Dynamic allocation or larger fixed sizes |

## Security Scanning

`cyrius vet` scans for dangerous patterns (a `cyaudit` pass dispatched by the `cyrius` CLI — not the `cybs` bootstrap compiler, which has no vet/deny mode; the `cybs vet` wording was a mis-wire fixed v6.1.25):
- Raw `syscall(59, ...)` (execve) outside process.cyr/agnosys
- Unbounded loops without break conditions
- Missing null checks on pointer arguments

`cyrius deny` enforces policy:
- No shell execution in library code
- No network syscalls in core libraries
- Trusted path validation for include directives

## Reporting

Security issues: security@agnos.dev
Response SLA: 48 hours
Disclosure: 90-day coordinated

## Stdlib TLS surface (v5.7.0+; native backend v6.0.74–.83)

`lib/tls.cyr` has two backends behind one verb contract. **Default (since
v6.1.21, no flag):** the sovereign native stack `lib/tls_native.cyr` — TLS 1.2 +
1.3, auth via ECDSA P-256/P-384 + RSA (PSS / PKCS#1 v1.5) + Ed25519,
AES-128/256-GCM + ChaCha20-Poly1305, EMS, ALPN, OS trust-store +
intermediate-chain + SNI-hostname verification, server-flight reassembly — no
OpenSSL, crypto/x509 in-tree (sigil). Backend-agnostic peer-introspection verbs
`tls_get_alpn_selected` / `tls_get_peer_spki_der` (v6.0.82). Live-Cloudflare- +
OpenSSL-interop-proven. **Opt-in (`-D CYRIUS_TLS_LIBSSL`):** the legacy
libssl-bridge surface (below):

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
