# Cyrius Threat Model

> **Scope**: Cyrius is a systems language compiler and toolchain.
> It generates native binaries (ELF / Mach-O / PE, plus cx bytecode) from source code.
> Zero external **language** dependencies. Zero unsafe code in
> compiler/stdlib by construction (assembly up). Stdlib **may**
> bridge to system libraries (libssl, libc) via the v5.6.37
> fdlopen-bootstrapped helper — see Trust Boundaries below.
>
> **Last reviewed**: 2026-10-12 (6.7.9 doc sweep — stale facts corrected against the tree; the
> attack surface was not re-audited — the last full security audit is named in the Security
> ledger row of `docs/development/state.md`).
> Seed boundary: `seed → cybs → cycc` is byte-identical-derivable, enforced every release by
> `scripts/release-gate.sh` (step 2). Native TLS is the *default* backend (since v6.1.21), PIE/ASLR
> is opt-in (`--pie`, since v6.1.6), stack canaries are accepted-with-rationale (see Known
> Limitations), and the binary-release trust root is the committed `build/cycc`. Vulnerabilities
> carry project ids `CYRIUS-YYYY-NNNN`, recorded in `docs/audit/2026-10-08-security-ledger.md`.

## Trust Boundaries

| Boundary | Trust Level |
|----------|-------------|
| 29KB seed binary (bootstrap/asm) | **Source-level** root of trust — auditable, committed, byte-exact. The seed assembles `cybs`, which compiles `src/main.cyr` to a `cycc` that self-hosts byte-identical to the committed `build/cycc` — so `build/cycc` is **machine-derivable from the 29 KB seed** (no bridge). Enforced every release by `scripts/seed-derive-cycc.sh` (= `release-gate.sh` step 2). NOTE: the cycc self-host fixpoint does NOT cover this chain — cybs is far more limited (v6.3.0 seed break). The seed itself is re-derived out of band from the archived Rust seed by `bootstrap/verify.sh` (needs rustc / cargo; see SECURITY.md). |
| Source code (src/, lib/, programs/) | Trusted — developer-controlled |
| User input (compiled programs) | Untrusted — may contain arbitrary code |
| Syscall interface (Linux kernel) | Trusted — OS provides memory isolation |
| Generated binaries | Untrusted until verified — self-hosting proves compiler correctness |
| `~/.cyrius/dlopen-helper` (v5.6.37+) | Trusted **for non-setuid callers only** — built by `install.sh` from `programs/dlopen-helper.c` with the host C compiler (`cc` / `gcc`); used by `fdlopen.cyr` to bootstrap real glibc for libssl bridge. Missing helper = TLS / libssl features disabled at runtime, not a security risk. **⚠ NOT trusted for setuid-root callers:** the path resolves inside the *invoking user's* `$HOME`, which a non-root caller of a setuid binary owns and can replace — `fdlopen` would then `execve` it **as root** (arbitrary root code execution). Setuid consumers (e.g. shakti) MUST use `fdlopen_init_trusted()` (v6.1.29), which resolves the root-owned `/usr/lib/cyrius/dlopen-helper`, `lstat`-verifies it (regular file, uid 0, not symlink, not group/other-writable), never consults `$HOME`, and fails closed (`FDL_ERR_UNTRUSTED` = -9). |
| Linked `libssl.so.3` / `libcrypto.so.3` (**opt-in** legacy backend) | System-trusted — the host's OpenSSL. **Default builds use the in-tree native stack** (`lib/tls_native.cyr` + sigil crypto/x509) and load no libssl, so OpenSSL CVEs do not apply. They apply transitively only to a program that loads it: one built with `-D CYRIUS_TLS_LIBSSL` (a libssl-only build), a default build that selects it at run time with `tls_set_backend(TLS_BACKEND_LIBSSL)`, or one that calls `tls_dlsym` (which loads libssl whatever the backend). |

## Attack Surface

| Area | Risk | Mitigation |
|------|------|------------|
| **Buffer overflow in compiler** | Malicious input overflows tok_names, codebuf, or fixup table | The compiler's tables check their caps and exit with a named error past them: the token arrays (`ADDTOK`), the identifier dedup table (`LEXID`), and the fn / var / fixup tables and code buffer, which grow on demand (the fixup table doubles since v6.2.0) up to a hard ceiling |
| **Heap layout corruption** | Adjacent buffers overflow silently | Guard checks, documented HEAP MAP (`src/main.cyr`), the check suite's heap audit, P-1 hardening |
| **Preprocessor path traversal** | `include "../../../etc/passwd"` reads arbitrary files | `READFILE` (`src/frontend/lex.cyr`) rejects an include path with a `..` component or an absolute path and FAILS the build (v6.1.41), unless `CYRIUS_ALLOW_PARENT_INCLUDES=1` / `CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1` is set — the caller's switch: `cyrius build` sets neither (an `include` resolves relative to the entry file through its `#@incdir` marker, and deps are vendored into `lib/` by `cyrius deps`). `cyrius deny` reports both shapes. |
| **Integer overflow in alloc** | Large allocation wraps to small size | `alloc` refuses a size ≤ 0 or above `ALLOC_MAX` before rounding it, and returns 0 when the kernel refuses a chunk (the Linux heap is mmap'd chunks since v6.1.19, not brk) |
| **Code injection via inline asm** | `asm { ... }` emits arbitrary bytes | By design — asm is a power tool, not a vulnerability |
| **Denial of service** | Extremely large source files | The source and preprocess buffers, the token arrays and every growable table are capped, and a program past a cap fails to compile with a named error (sizes: the HEAP MAP in `src/main.cyr`; usage: `CYRIUS_STATS=1` or `cyrius capacity`). The x86 jump-target table **hard-errors** past its per-fn cap (v6.3.21) rather than silently mis-eliminating code |
| **Supply chain** | Compromised compiler binary | **Narrow-scope self-hosting verification**: the compiler must produce byte-identical output when recompiling its own source — `release-gate.sh` step 1 (`build/cycc` reproduces itself and equals cycc(src)) before every release, step 2 re-deriving it from the seed, and step 4 self-hosting on real macOS (arm64, x86_64), Windows and aarch64 hardware. **Note on scope**: this mitigates trusting-trust attacks against the compiler's own codegen only. It does NOT address platform-loader tolerance of the emitted binary (a separate "broad-scope" property — see `docs/architecture/cyrius.md` §"Self-hosting: two scopes of byte-identity"). |
| **Bootstrap trust** | Trusting the committed 29KB seed | Diverse double compilation: `bootstrap/verify.sh` rebuilds the seed from the archived Rust seed (out of band); the seed is auditable |

## Known Limitations

| Limitation | Impact | Planned Fix |
|-----------|--------|-------------|
| No memory safety | Buffer overflows in user programs possible | Partial, opt-in: the **bounds-checked mode** (6.7.8 — `--bounds`, `CYRIUS_BOUNDS=1`, `[build] bounds = true` or a `#bounds` line) checks typed-array subscripts against their N, slice reads and writes, and a negative `*T` subscript, exiting 134 on a violation; raw `load*` / `store*` and `*p` stay unchecked, and `@unsafe { }` turns the checks off. A slice index is checked in every build (`slice bounds violation`, exit 134). No ownership / borrow checker is on the roadmap. |
| No stack canaries (**accepted — the no-stack-canary hardening item, v6.3.21**) | Stack smashing on a thread stack is caught, not silent | **Accept-with-rationale:** canaries are not emitted. A `PROT_NONE` guard page below every thread stack (**the thread guard-page hardening item, v6.2.44**) turns a stack overflow into a loud SIGSEGV — the same detect-and-crash outcome a canary gives. **W^X** code/data separation (v6.3.12) makes injected stack data non-executable (blocks ROP/JOP payloads), and opt-in **PIE/ASLR** (v6.1.6) removes address predictability. For a bare-metal-first sovereign systems language, this multi-layer defense is preferred to per-call canary overhead. Revisit if a consumer profiles a real canary-shaped gap (e.g. a non-thread stack without a guard page). |
| PIE/ASLR is opt-in | Non-PIE binaries have a predictable layout | **PIE codegen shipped v6.1.6** — `--pie` / `CYRIUS_PIE=1` emits `ET_DYN` so the loader applies ASLR (x86_64 + aarch64 userland). Default output is still non-PIE `ET_EXEC`; pass `--pie` for ASLR. |
| No sandboxing | Generated binaries have full syscall access | None scheduled (not on the roadmap) |
| Compiler table caps | A program past a table's cap does not compile | Each cap exits with a named error; the fn / var / fixup tables and the code buffer grow on demand up to a hard ceiling; `cyrius capacity` reports usage and `--check` gates it in CI |

## Security Scanning

`cyrius vet` and `cyrius deny` are the two passes of the `cyaudit` tool (`programs/cyaudit.cyr`),
dispatched by the `cyrius` CLI. Both read only the named file's own `include` lines (not
recursively) — neither scans code for patterns.

`cyrius vet <file>` audits include dependencies: it lists every include as `OK`, `UNTRUST` (outside
`lib/`, `src/`, `programs/`, `cbt/` and `kernel/`, or with a `..` component anywhere) or `MISSING`,
and exits 1 when any is untrusted or missing.

`cyrius deny <file>` enforces the include policy: each absolute include path and each include with
a `..` path component is a violation, and it exits with the violation count (capped at 255); a
file it cannot read is an error (exit 1).

## Reporting

- Security issues: report as [SECURITY.md](../../SECURITY.md) says (security@agnosticos.org; do
  not open a public issue)
- Response SLA: 48 hours
- Disclosure: 90-day coordinated

## Stdlib TLS surface

`lib/tls.cyr` has two backends behind one verb contract —
[`lib-tls-contract.md`](lib-tls-contract.md) is the full surface and its invariants.
**Default (since v6.1.21, no flag):** the sovereign native stack `lib/tls_native.cyr` — TLS 1.2 +
1.3, client and server, auth via ECDSA P-256/P-384 + RSA (PSS / PKCS#1 v1.5) + Ed25519,
AES-128/256-GCM + ChaCha20-Poly1305, EMS, ALPN, client certificates, OS trust-store +
intermediate-chain verification and the leaf bound to the host name — no OpenSSL, crypto/x509
in-tree (sigil). Live-Cloudflare- + OpenSSL-interop-proven. **Opt-in:** the legacy libssl
bridge (`-D CYRIUS_TLS_LIBSSL`, or `tls_set_backend(TLS_BACKEND_LIBSSL)` at run time) brokers
TLS 1.2/1.3 through OpenSSL's `libssl.so.3`, bootstrapped through fdlopen for a correct pthread
TCB layout (an in-tree `dynlib_open` deadlocked `SSL_CTX_new` on its first futex); it runs on
the main thread only and refuses a call from any other. Capabilities are surfaced through
`tls_available()` and the `tls_supports_*()` probes: sandhi (`lib/sandhi.cyr`) fails a TLS open
when `tls_available()` is 0 and sends no early data when `tls_supports_early_data()` is 0.

**Security caveats for TLS users**:
- 0-RTT exists on the libssl backend only, and replay-attack mitigation for it is the
  **consumer's** responsibility (sandhi sends early data only for replay-safe methods). Stdlib
  enforces no replay window.
- By default a client connect verifies the peer's chain against the OS trust store and binds its
  leaf to `host`, on both backends (the trust store and verify mode are set before a connect hook
  runs; the host binding is applied after it, from the hook's final verify mode).
  `tls_set_verify(handle, 0, 0)` in a hook turns both off, and the hook owns the consequence. On libssl a verify callback that accepts
  errors also accepts a wrong chain or name (OpenSSL reports both through it); the native backend
  runs no callback and fails closed. Override the defaults only for mTLS / pinning.

## Design Principles

- Zero external language dependencies — no crates.io supply chain
- Self-hosting verification after every compiler change
- Byte-exact reproducibility — same source always produces same binary
- Fixed heap layout is documented and auditable
- P-1 hardening before every feature release
- `cyrius audit` must pass before every commit
