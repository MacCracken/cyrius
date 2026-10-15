# cx: the pointer-taking wrappers outside D13's four still hand the host a guest address — and since the 8 MiB guest segment a guest address can be cxvm's own Linux image (`cyr_munmap(0x400000, …)` unmaps cxvm's code) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib, after the cx code-region
growth and D13's cx arms).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane; filed from the 6.7.12 stdlib lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — cxvm runs trusted bytecode and is documented as not a sandbox (docs/platform-status.md,
cyrius-x guest contract); no attacker crosses a boundary (no ledger id). But an honest guest program can now corrupt
or kill its own VM by accident where it used to get -EFAULT.
**Discovered:** 2026-10-15, the 6.7.12 stdlib lane (unit L2), landing D13
(`issues/2026-10-14-cx-main-running-tcyr-fail-at-guest-contract-limits.md`: honest cx arms in `cyr_mmap` /
`sys_pipe` / `sys_fstat` / `sys_unlink`) right after D12 grew cxvm's guest memory 1 MB → 8 MiB.

## Reproduction

```sh
cd /home/macro/.cache/c6/wt6712/stdlib     # any tree at or after 6.7.12's cx bites
printf 'include "lib/syscalls.cyr"\ninclude "lib/mmap.cyr"\nvar r = cyr_munmap(4194304, 65536);\nsyscall(1, 1, "after munmap\\n", 13);\nsyscall(60, 0 - r);\n' > mu.cyr
cat src/main_cx.cyr | build/cycc > cycc_cx; cat programs/cxvm.cyr | build/cycc > cxvm; chmod +x cycc_cx cxvm
./cycc_cx < mu.cyr > mu.cyx; ./cxvm < mu.cyx; echo "cx=$?"
readelf -l cxvm | grep -A1 LOAD
```

```text
cx=139
  LOAD  0x0000000000000000 0x0000000000400000 0x0000000000400000  ... R E
  LOAD  0x0000000000011000 0x0000000000600000 0x0000000000600000  ... RW
```

Guest address 0x400000 (4 MiB) is an ordinary address in the 8 MiB guest segment, but cxvm forwards munmap(11) to the
host with the raw value, so the HOST unmaps cxvm's own text and cxvm dies with SIGSEGV. (Natively the same source also
kills itself — it unmaps its own text — so this repro shows the reach, not a divergence; the divergence is a guest
BUFFER: a guest address in [0x600000, 0x601c08] handed to an untranslated read-type syscall — `sys_stat`, `sys_statfs`,
`pread64`, `recvfrom`, … — is written by the host kernel into cxvm's own globals instead of answering -EFAULT:
`var r = syscall(5, 1, 6291712); syscall(60, 100 + r);` exits 100 under cxvm — fstat(2) SUCCEEDED, writing a 144-byte
`struct stat` over cxvm's data segment at 0x600100 — while the same call at guest 0x700000 answers -14.)

## Root cause

D13 (the user, 2026-10-15) gave honest cx arms to the four wrappers the filing enumerated. Every other pointer-taking
wrapper — `cyr_munmap`, `cyr_mprotect`, `sys_statfs` (the yukti crossos file's statfs answers -EFAULT on cx, which its
6.7.12 cx arm asserts as an Err), `sys_stat` / `sys_lstat` / `sys_fstatat`, `sys_nanosleep`, the socket family, … —
still reaches the host with a guest address (programs/cxvm.cyr op 0x70: only read / write / open / getrandom /
clock_gettime are translated). Until 6.7.12 a guest address was below 1 MiB, which a static Linux cxvm never maps, so
such a call failed with -EFAULT; the 8 MiB segment now overlaps cxvm's link addresses (text 0x400000, data 0x600000)
on Linux hosts (the macOS and Windows images sit far above 8 MiB).

## Fix (the user's call)

Extend D13's honest arms to the remaining pointer-taking wrappers (-38 / -1 on cx), or have cxvm refuse (or
translate) every untranslated number whose arguments include a pointer, or link cxvm above the guest range. The
platform-status guest contract should name the overlap either way. A row: the repro above exits with a refusal, not
139.
