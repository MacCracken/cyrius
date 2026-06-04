# Security Policy

## Reporting Vulnerabilities

Report security issues to: security@agnosticos.org

Do **not** open public issues for security vulnerabilities.

## Scope

Cyrius is a systems language compiler. Security-relevant areas:

- **Compiler correctness**: codegen bugs that produce wrong behavior
- **Bootstrap chain integrity**: the 29KB seed binary is the root of trust
- **Kernel code**: AGNOS kernel memory safety, interrupt handling, syscall validation
- **Build tool (cyrius)**: fork/exec security, path handling
- **Package manager (ark)**: package verification, database integrity

## Supported Versions

Cyrius releases follow semver. Security fixes land on the latest minor and
the prior minor; older lines are best-effort. Per CLAUDE.md, **v5.0.0+ is
the recommended minimum** (cycc IR + cyrius.cyml manifest). v5.0.1+ adds
alloc/vec overflow guards. v5.1.0+ adds macOS Mach-O.

| Version | Supported |
|---------|-----------|
| 6.0.x | Yes (current) |
| 5.x.x (5.0.0+) | Best-effort |
| < 5.0.0 | No |

## Response

We aim to respond to security reports within 48 hours and provide fixes within 7 days for critical issues.
