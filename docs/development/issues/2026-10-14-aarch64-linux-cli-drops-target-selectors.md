# On an aarch64 Linux host, `cyrius build --agnos` writes an aarch64 Linux ELF, and `--target=x86_64-bare-metal-elf` writes an aarch64 image while printing an x86_64 multiboot2 entry line, both at rc 0 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on pi (aarch64 Linux hardware) with the CLI and the native compiler
cross-built from the 6.7.11 tools lane (l6711-tools @ a3d9837d), throwaway `HOME` / `CYRIUS_HOME`.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D6 — refuse by name.
**Discovered:** 2026-10-14 by the 6.7.11 tools lane's review (issues/archived/2026-10-10-windows-cli-drops-target-selectors.md,
which refuses the selectors on Windows and macOS). The aarch64 Linux CLI is outside that filing's surface.
**Severity:** High — a dropped target selector: the requested artifact (an agnos ring-3 binary, an x86_64 kernel
image) is not written, the host format is, and the CLI says OK at rc 0 — for the bare-metal target it also prints an
x86_64 multiboot2 entry line for an image that is aarch64. The same defect class as the Windows filing (the 6.6.5
one-argument rule: a dropped flag that changes the artifact).
**Affects:** `cyrius build` / `cyrius run` with `--agnos` or `--target=x86_64-bare-metal-elf` on an aarch64 Linux host
(cbt/cli_args.cyr `_cli_host_emits_only`, cbt/core.cyr `current_cc`, src/main_aarch64.cyr /
src/main_aarch64_native.cyr).

## Reproduction

`hello.cyr`:

```cyrius
syscall(60, 7);
```

Built on an x86_64 box from the tree, then run on pi (aarch64 Linux):

```sh
cat src/main_aarch64.cyr | ./build/cycc > cycc_aarch64.x && chmod +x cycc_aarch64.x
cat cbt/cyrius.cyr | ./cycc_aarch64.x > cyrius                    # the aarch64 Linux CLI
cat src/main_aarch64_native.cyr | ./cycc_aarch64.x > cycc         # the native compiler, beside it
# on pi, in a scratch dir with HOME / CYRIUS_HOME pointed into it:
./cyrius build --agnos hello.cyr o.out; echo "rc=$?"; head -c 20 o.out | od -An -tx1; ./o.out; echo "exit=$?"
./cyrius build hello.cyr plain.out; ls -l o.out plain.out
./cyrius build --target=x86_64-bare-metal-elf hello.cyr k.out; echo "rc=$?"; head -c 20 k.out | od -An -tx1
```

```
actual:
compile hello.cyr -> o.out [x86_64] OK (65888 bytes)
rc=0
 7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
 02 00 b7 00                                     <- e_machine 0xb7: aarch64
exit=7                                           <- runs as a Linux program
65888 o.out
65888 plain.out                                  <- byte count identical to a plain build
compile hello.cyr -> k.out [x86_64] OK (536 bytes)
  kernel: entry 0x1000a8, load base 0x100000 (x86_64 ELF64 multiboot2)
rc=0
 7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
 02 00 b7 00                                     <- an aarch64 image, not the x86_64 kernel the line names
```

The review measured the same on pi with the CLI at l6711-tools@fb5278a4 (65,896 B / 632 B, e_machine 0xb7, exit 7).

```
expected: the decided treatment of a selector the host's compiler cannot emit — either the x86_64 image is built
          (the CLI reaching an x86_64-emitting compiler on an aarch64 host), or the flag is refused by name,
          rc 1, nothing written, as the Windows / macOS CLIs do since 6.7.11 — never an aarch64 binary at rc 0.
```

## Root cause

- `_cli_host_emits_only()` (cbt/cli_args.cyr) answers 0 on every Linux host, so `_cli_foreign_target` lets the
  selector through.
- compile() uses `current_cc()` (cbt/core.cyr), which on an aarch64 Linux host is an aarch64 compiler; only
  src/main.cyr reads `CYRIUS_TARGET_AGNOS` / `CYRIUS_ELF64_KERNEL` (`grep -l 'CYRIUS_TARGET_AGNOS\|CYRIUS_ELF64_KERNEL'
  src/*.cyr` matches src/main.cyr, plus a mention in main_cx.cyr); main_aarch64.cyr and main_aarch64_native.cyr read
  `CYRIUS_KERNEL` alone, so the environment entries the CLI injects are ignored and an aarch64 Linux binary (or an
  aarch64 kernel image) comes out.
- The progress line says `[x86_64]` because `_arch` defaults to X86 there, and the kernel line is printed from the
  requested target, not from the written image.

## Proposed fix

The user's decision, one of: (a) refuse `--agnos` and `--target=x86_64-bare-metal-elf` by name on an aarch64 Linux
host (extend `_cli_host_emits_only` with an aarch64-Linux answer, `--target=aarch64-bare-metal-elf` kept: the aarch64
forks honour `CYRIUS_KERNEL`); or (b) have the aarch64 Linux CLI build those targets with an x86_64-emitting compiler
(none ships for aarch64 hosts today). Rows in tests/gates/toolchain/win_cli_refuses_foreign_targets.sh (an aarch64
Linux CLI under qemu-aarch64, an S row for its refusal text) and a pi measurement; the guide's § Targeting AGNOS ⚠
(added 6.7.11) updated to the outcome.
