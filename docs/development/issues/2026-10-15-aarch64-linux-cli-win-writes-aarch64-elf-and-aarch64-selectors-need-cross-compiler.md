# On an aarch64 Linux host, `cyrius build --win` writes an aarch64 ELF named `.exe` at rc 0, and `--aarch64` / `--target=aarch64-bare-metal-elf` fail looking for the x86_64-hosted `cycc_aarch64` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on pi (aarch64 Linux hardware) with the CLI and the native compiler
cross-built from the 6.7.12 tools lane (l6712-tools, before and after the fix of
issues/2026-10-14-aarch64-linux-cli-drops-target-selectors.md, D6 — identical for these three selectors), throwaway
`HOME` / `CYRIUS_HOME`. Met while fixing that issue: D6 refuses `--agnos` and `--target=x86_64-bare-metal-elf` on the
aarch64 Linux CLI; its triage noted "Not checked: `--win` from an aarch64 Linux host". The combined-target-flags issue
(D20, 6.7.12) refuses two selectors at once; a single `--win` on this host is outside both.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; filed from the 6.7.12 tools lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** High for `--win` (a dropped target selector: the requested PE is not written, an aarch64 ELF named
`w.exe` is, and the CLI says OK at rc 0 — the 6.6.5 one-argument rule's defect, the class D6 and 6.7.11 refused by name);
Medium for `--aarch64` / `--target=aarch64-bare-metal-elf` (a named rc 1, never a wrong artifact, but the host's own cycc
emits aarch64 and honours CYRIUS_KERNEL, so the remedy it prints — build `cycc_aarch64` via `cyrius pulsar` — is an
x86_64 binary that cannot run there).
**Affects:** the aarch64 Linux CLI (`cat cbt/cyrius.cyr | cycc_aarch64`): `_cli_host_emits_only` / `_cli_host_emits_no_x86`
(cbt/cli_args.cyr) answer nothing for `--win`; `current_cc()` (cbt/core.cyr) returns `_cc_arm` — `<tools>/cycc_aarch64`,
the x86_64-hosted cross compiler — whenever `_arch` is ARCH_AARCH64 (`--aarch64`, and `--target=aarch64-bare-metal-elf`
through `_baremetal_aa`, cbt/build.cyr compile()), where the aarch64 host's compiler is `_cc` itself.

## Reproduction

```sh
# on an x86_64 box, from the tree:
cat src/main_aarch64.cyr | ./build/cycc > cycc_aarch64.x && chmod +x cycc_aarch64.x
cat cbt/cyrius.cyr | ./cycc_aarch64.x > cyrius                    # the aarch64 Linux CLI
cat src/main_aarch64_native.cyr | ./cycc_aarch64.x > cycc         # the native compiler, beside it
printf 'syscall(60, 7);\n' > hello.cyr
# on pi, in a scratch dir holding the three, with HOME / CYRIUS_HOME pointed into it:
./cyrius build --win hello.cyr w.exe; echo "rc=$?"; head -c 20 w.exe | od -An -tx1
./cyrius build --target=aarch64-bare-metal-elf hello.cyr kk.out; echo "rc=$?"
./cyrius build --aarch64 hello.cyr a.out; echo "rc=$?"
```

```
compile hello.cyr -> w.exe [aarch64] OK (65888 bytes)        (6.7.11's label: [x86_64])
rc=0
 7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
 02 00 b7 00                                                 <- an aarch64 Linux ELF, not a PE
compile hello.cyr -> kk.out [aarch64]
FAILED
error: aarch64-bare-metal-elf requested but cycc_aarch64 not found; build it via `cyrius pulsar` (or CI/install): ./cycc_aarch64
rc=1
compile hello.cyr -> a.out [aarch64]
FAILED
error: compiler not found: ./cycc_aarch64
rc=1
```

## Root cause

- `--win`: compile() injects CYRIUS_TARGET_WIN=1 for the host compiler; src/main_aarch64_native.cyr reads no
  CYRIUS_TARGET_WIN (there is no PE emitter for an aarch64-hosted compiler), so it writes its own format; no early block
  refuses it on this host.
- `--aarch64` / aarch64 bare metal: `current_cc()` and compile()'s `_baremetal_aa` arm pick `_cc_arm` by `_arch`, a
  choice made for the x86_64 host (where the aarch64 emitter is the separate cross compiler).

## Proposed fix

- `--win` from the aarch64 Linux CLI: refused by name, as D6 refuses `--agnos` (the user's 2026-10-13 rule — a target
  the host's compiler cannot emit is refused by name); or, a decision, built by shipping a PE-emitting compiler for
  aarch64 hosts (distribution work).
- `--aarch64` and `--target=aarch64-bare-metal-elf` on an aarch64 host: run the host's own cycc (`_cc`), which emits
  aarch64 and honours CYRIUS_KERNEL — `--aarch64` a no-op there, the bare-metal target the aarch64 kernel image.
- Rows: tests/gates/toolchain/win_cli_refuses_foreign_targets.sh's A axis (qemu-aarch64; the `--win` refusal before any
  exec), and pi for the two builds (they exec the native compiler).
