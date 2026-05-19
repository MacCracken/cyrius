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
- **Size**: The entire toolchain (250KB compiler + 29KB seed) is smaller than most profile photos

## Consequences

- Bootstrap chain is longer (seed → cybs → cycc; bridge intermediate retired v5.11.66, cc3 → cycc at v5.0.0)
- No access to libc functions — must implement everything from syscalls
- Every new feature must work without external libraries
- Self-hosting verification is mandatory after every compiler change
