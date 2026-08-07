# ADR-001: Assembly as the Cornerstone

**Status**: Accepted
**Date**: 2026-03-20
**Context**: Starting a sovereign language for AGNOS required choosing the bootstrap foundation.

## Decision

Build Cyrius from assembly up — no C compiler, no Rust, no LLVM, no libc in the bootstrap path. The 29KB seed binary is the root of trust.

## Rationale

- **Auditability**: A 29KB binary can be reviewed by a single person
- **Sovereignty**: No external toolchain governance can block the project
- **Reproducibility**: Byte-exact self-hosting from a committed binary
- **Size**: The entire toolchain (~1.14 MB compiler — cycc x86_64 is 1,141,792 B at v6.5.10 — + 29 KB seed) is smaller than most profile photos

## Consequences

- Bootstrap chain is longer (seed → cybs → cycc; bridge intermediate retired v5.11.66; the compiler binary renamed cc3 → cc5 (v5.0.0) → cycc (v6.0.0) — a name evolution, not separate compilers)
- No access to libc functions — must implement everything from syscalls
- Every new feature must work without external libraries
- Self-hosting verification is mandatory after every compiler change
