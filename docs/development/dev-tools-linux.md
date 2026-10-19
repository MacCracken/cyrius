# Development Tools — Linux (x86_64 dev / verification host)

> One file **per environment** so moving env→env we install the proper tools
> up front instead of discovering a gap mid-debug. This is the **x86_64 Linux
> dev box** — the primary build + cross-emit + cross-host-verify machine.
> Siblings (to be added): `dev-tools-macos.md`, `dev-tools-windows.md`.
>
> Reference distro: **Arch Linux** (`pacman`). `apt` equivalents are listed for
> Ubuntu-based hosts (e.g. the `pi` aarch64 target host, the GitHub CI's Linux runners, which
> run `ubuntu-26.04`).

## Why this matters (the v6.0.45 lesson)

The cross-OS self-host gate cross-builds cycc for **every** target on this one
Linux box, then verifies. Two capabilities make platform bugs cheap to fix:

- **Run target binaries locally** — `qemu-user` runs the aarch64 ELF cycc and
  `wine` runs the Windows PE `cycc.exe` **here**, so a self-host miscompile
  (e.g. the shared `_TARGET_MACHO`-undefined bug) is reproduced + bisected in a
  ~30 s local loop instead of round-tripping to `pi`/`cass` every iteration.
- **Disassemble any target** — `llvm-objdump` reads x86-64 / aarch64 / PE /
  Mach-O, so a codegen bug can be read straight out of the emitted binary.

When these were missing, platform debugging stalled — install them first.

## One-shot install (Arch / pacman)

```sh
sudo pacman -S --needed \
  qemu-user qemu-system-x86 wine llvm binutils gcc clang gdb lldb openssh python python-yaml \
  tinyxxd file coreutils diffutils cpio parted mtools edk2-ovmf openssl curl git tar gzip
```

Arch has no `xxd` package: `xxd` comes from `tinyxxd` (above) or from `vim`.

Ubuntu/Debian (`pi`, CI images):

```sh
sudo apt-get install -y \
  qemu-user qemu-system-x86 wine llvm binutils gcc clang gdb lldb openssh-client python3 \
  python3-yaml xxd file coreutils diffutils cpio parted mtools ovmf openssl curl git tar gzip
```

The gates read nothing beyond these packages and the cyrius checkout: since 6.7.16 no other
project's checkout, built or not (`release-gate.sh` step 4 also needs the four verification
hosts over `ssh`). The table under *What the gates need* is the measurement behind both lines.

On Ubuntu 26.04 `qemu-user` ships the static binaries (named `qemu-aarch64`) and there is no
`qemu-user-static` package. On an older Ubuntu / Debian `qemu-user` still provides `qemu-aarch64`;
its `qemu-user-static` package names the binary `qemu-aarch64-static`, which this file's commands
do not call.

## Tools

| Tool | Arch pkg | apt pkg | Why it's needed | Verify |
|------|----------|---------|-----------------|--------|
| `qemu-aarch64` | `qemu-user` | `qemu-user` | Run the **aarch64 ELF** cycc locally — reproduce/bisect the native-aarch64 self-host without SSHing to `pi` | `qemu-aarch64 --version` |
| `qemu-system-x86_64` | `qemu-system-x86` | `qemu-system-x86` | **`check.sh` gate** — `scripts/qemu-boot-gate.sh` really BOOTS the `kernel;` build and asserts it writes `AGNOS` to serial. **Absent → the gate exits 77, a SKIP: check.sh still exits 0** (`GREEN, with N gate(s) SKIPPED`), while `release-gate.sh` step 3 fails on it; CI sets `CYRIUS_REQUIRE_BOOT=1` to make it a hard FAIL | `qemu-system-x86_64 --version` |
| `wine` | `wine` | `wine` | Run the **Windows PE** `cycc.exe` locally — reproduce/bisect the Windows self-host without SSHing to `cass` | `wine --version` |
| `llvm-objdump` | `llvm` | `llvm` | Disassemble **x86-64 / aarch64 / PE / Mach-O** — read codegen out of any emitted target binary | `llvm-objdump --version` |
| `objdump` / `nm` | `binutils` | `binutils` | x86-64 ELF disasm (several check.sh gates read `objdump -d`) / quick header and symbol dumps | `objdump --version` |
| `gdb` | `gdb` | `gdb` | Debug the x86-64 Linux cycc + emitted ELF | `gdb --version` |
| `lldb` | `lldb` | `lldb` | Debug under wine / inspect Mach-O-shaped output | `lldb --version` |
| `ssh` / `scp` | `openssh` | `openssh-client` | **Authoritative** cross-host self-host verification on real hardware (`ecb`/`ach`/`pi`/`cass`) — see `scripts/cross-os-selfhost.sh` | `ssh -V` |
| `python` + `pyyaml` | `python` `python-yaml` | `python3` `python3-yaml` | Validate `.github/workflows/*.yml` locally; CI parses PE headers with python, and some check.sh gates (`scripts/sign-efi-gate.sh` among them) run python helpers | `python3 -c "import yaml"` |
| `xxd` | `tinyxxd` (or `vim`) | `xxd` | Inspect Mach-O/PE magic; the macOS tarball builders read magic with it (`macos_tarball_ships_release_scripts.sh` axis 5 SKIPs without it) | `xxd -v` |
| `file` | `file` | `file` | Confirm emitted binary format (`Mach-O … arm64`, `PE32+`, `ELF … aarch64`) | `file --version` |
| `sha256sum` | `coreutils` | `coreutils` | Byte-identical self-host proof + release checksums | `sha256sum --version` |
| `tar` | `tar`* | `tar` | Bundle `src/ lib/ VERSION` for shipping to verification hosts | `tar --version` |
| `openssl` | `openssl` | `openssl` | **`check.sh` gate** — `scripts/sign-efi-gate.sh` uses it as the *independent oracle* (it is not used by the signer) that `cyrius sign-efi`'s Authenticode signature is one real UEFI firmware would accept. **Absent → `SKIP sign-efi-gate: openssl not available`, exit 77** (a SKIP, as above) | `openssl version` |
| `curl` | `curl` | `curl` | Release + install paths (`scripts/ci.sh`, `install.sh`, `release-lib.sh`) and **the only sanctioned way to reach the GitHub API** — `gh` is banned per CLAUDE.md | `curl --version` |

\* `tar`, `getent`, `cmp`, `printf` ship in the base system.

> ⚠ **A gate whose tool is missing SKIPs** (exit 77) — the two above, and the rows marked SKIP in
> *What the gates need* below. check.sh still exits 0, its summary `GREEN, with N gate(s) SKIPPED`
> listing them. That is the same green-checkmark-over-nothing shape the cross-OS principle exists
> to stop, and `release-gate.sh` refuses it: step 3 fails on any SKIP not named in
> `RG_SKIP_ALLOW`, which is EMPTY since 6.7.16. On a box that gates releases, every package in
> the install lines above is required, not optional.

## What the gates need (measured 6.7.16)

Measured over every file check.sh and the release gate run — `tests/gates/**/*.sh`,
`programs/checks/*.cyr`, `scripts/check.sh`, `scripts/release-gate.sh` and the `scripts/*.sh`
gates and legs they call (`qemu-boot-gate.sh`, `sign-efi-gate.sh`, `agnos-crossbuild-gate.sh`,
`cross-os-selfhost.sh`, …): each `command -v` probe, each hard-coded tool path and each tool
invoked in a non-comment line. Packages are Arch / apt; "base" ships in a minimal install.

| Package (Arch / apt) | Tools | What runs them | Missing → |
|---|---|---|---|
| `qemu-user` | `qemu-aarch64` | ~110 gates (aarch64 builds run locally) | per gate: SKIP or a named SKIP leg |
| `qemu-system-x86` | `qemu-system-x86_64` | `scripts/qemu-boot-gate.sh`, `tests/gates/codegen/dce_kernel_compaction_boots.sh`, the driver's EFI rows (`programs/checks/platform_efi.cyr`); the opt-in row 4 of `tests/gates/memory/alloc_first_chunk_small_board.sh` | SKIP (the two shell gates FAIL under `CYRIUS_REQUIRE_BOOT=1`) |
| `wine` | `wine`, `winepath`, `wineserver` | ~100 gates (PE builds run locally) | per gate: SKIP or a named SKIP leg |
| `llvm` | `llvm-objdump` | 9 gates (e.g. `ir_nop_harvest.sh`, `lazy_init_release_fence.sh`) | FAIL or SKIP, per gate |
| `binutils` | `objdump`, `readelf`, `ld` | `objdump` in 25 gate files (disassembly checks, `agnos-crossbuild-gate.sh` among them), `readelf` in 11 (`object_hides_libc_names.sh`, `dyn_checked.sh`, …), `ld` in `dyn_checked.sh` | per gate: SKIP, a named SKIP leg, or a disassembly check not run |
| `gcc` | `gcc`, `cc` | `call_site_stack_alignment.sh`, `ffi_stack_protected_extern_c.sh` (gcc), `default_named_args_checked.sh`, `header_spellings_and_size.sh` (cc); `scripts/install.sh` builds the dlopen helper the driver's libssl `.tcyr` groups use | SKIP |
| `clang` | `clang` | `header_spellings_and_size.sh` (the aarch64 / Darwin / Win64 header rows) | those three rows are not run (no SKIP is reported) |
| `parted`, `mtools`, `edk2-ovmf` / `ovmf` | `parted`, `mformat` / `mcopy` / `mmd`, `OVMF_CODE.4m.fd` + `OVMF_VARS.4m.fd` | the driver's EFI rows: boot an EFI image under qemu + OVMF | SKIP. ⚠ The rows read OVMF at Arch's path, `/usr/share/edk2-ovmf/x64/`; Ubuntu's `ovmf` installs elsewhere, so there they SKIP |
| `cpio` | `cpio` | `alloc_first_chunk_small_board.sh`'s OPT-IN row 4 (`CYRIUS_ALLOC_VM=1`: packs the initramfs it boots); the default run does not need it | FAIL when the row is asked for |
| `diffutils` (base on Ubuntu) | `diff`, `cmp` | ~330 byte-identity lines across the gates (the tarball gates probe for them and SKIP) | FAIL, or SKIP where probed |
| `python` / `python3` | `python3` | `sign-efi-gate.sh`, `simd_direct_form.sh`, `cycc_parser_fuzz.sh`, `recursion_depth_bounded.sh`, `deps_git_cache_verified.sh`, … | FAIL or SKIP, per gate |
| `openssl` | `openssl` | `sign-efi-gate.sh` (the independent Authenticode oracle), the TLS gates' `s_server` peers (`tls_first_use_thread_race.sh`, `tls_libssl_hostname_binding.sh`, …) | SKIP |
| `tinyxxd` or `vim` / `xxd` | `xxd` | `macos_tarball_ships_release_scripts.sh` (the macOS tarball builders read Mach-O magic with it) | a named SKIP leg |
| `file` | `file` | `aarch64_tarball_ships_release_bins.sh` | SKIP |
| `git` | `git` | ~40 gates (deps / lock / local-mode rows, `cyriusly_setup_bootstrap_and_env.sh`), `removed_symbol_census.sh` (the last release tag) | FAIL or SKIP, per gate |
| `tar`, `gzip` | `tar`, `gzip` | the release-tarball gates (`ci_installs_the_release_tarball.sh`, `install_paths_ship_init_templates.sh`, `aarch64_tarball_ships_release_bins.sh`) | SKIP |
| `openssh` / `openssh-client` | `ssh`, `scp` | `release-gate.sh` step 4 (`scripts/cross-os-selfhost.sh`: ecb, ach, cass, pi) | step 4 RED |
| base (`coreutils`, `util-linux`, `findutils`, `procps`, `gawk`/`mawk`, `sed`, `grep`, `bash`) | `timeout`, `sha256sum`, `od`, `dd`, `truncate`, `mkfifo`, `stat`; `setsid`, `setarch`, `unshare`, `mount`; `find`, `xargs`; `ps`; `awk`; `sed`; `grep`; `bash` | everywhere (`bash` also runs the pipefail checks, `gates_verdict_under_pipefail.sh`) | FAIL |

No gate reads another project's checkout (6.7.16 — `tests/gates/toolchain/gates_read_only_the_tree.sh`
refuses one), so nothing beyond these packages and the cyrius checkout is needed.

The cyrius compiler itself is **bootstrapped**, not packaged: `sh bootstrap/bootstrap.sh` (seed asm → `cybs` → `cycc`). No crates.io, no toolchain package — that's the point.

## What each capability unlocks

- **Cross-emit all targets here** — each target has its OWN source fork, so the driver file
  changes with the target, not just the env var (`scripts/build-macos-*-tarball.sh` and
  `scripts/cross-os-selfhost.sh` are the authority on which pairs are correct):

  - aarch64 ELF — `cat src/main_aarch64.cyr | build/cycc > cc_a64 && chmod +x cc_a64` gives the
    x86-64 cross compiler that emits aarch64 ELF; `cat src/main_aarch64.cyr | ./cc_a64 > cycc_a64`
    gives the aarch64-hosted compiler
  - x86 Mach-O — `cat src/main_x86_macho.cyr | CYRIUS_MACHO=1 build/cycc`
  - arm64 Mach-O — **two steps**: `cc_a64` as above, then
    `cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 ./cc_a64`
  - Windows PE — `cat src/main_win.cyr | build/cycc > cycc_win`, then `cat src/main_win.cyr | ./cycc_win > cycc.exe`
  - cx bytecode — `cat src/main_cx.cyr | build/cycc`

  All from the x86 seed. ⚠ **arm64 Mach-O is the one that is NOT a one-liner**:
  `CYRIUS_MACHO_ARM=1 build/cycc` is refused by `src/backend/x86/fixup.cyr` (*"requires the
  aarch64 backend. Use ./build/cycc_aarch64"*) — it exits **1 after writing 0 bytes**, so a `>`
  redirect leaves a plausible-looking empty file. The env var selects the Mach-O *container*;
  the arm64 *instructions* come from the aarch64 backend, which on an x86 box only exists once
  `main_aarch64.cyr` has been cross-emitted.
- **Local self-host repro:** `qemu-aarch64 ./cycc_a64 < src/main_aarch64.cyr` and `wine ./cycc.exe < src/main_win.cyr` (run from the repo root, with `cycc_a64` / `cycc.exe` from the lines above) reproduce the real-hardware self-host result locally: each output equals its compiler byte for byte.
- **Authoritative verify:** `sh scripts/cross-os-selfhost.sh <ecb|ach|pi|cass> [tcyr-subdir]` self-hosts on the real host (qemu/wine are for fast iteration; **real hardware is the gate** — see CLAUDE.md "Cross-OS self-host is non-negotiable, on REAL hardware"). Arg 2 is a **subdirectory of `tests/tcyr`**, not a filename glob: the release gate passes `crossos` for all four hosts (`scripts/release-gate.sh` step 4), and a directory that does not exist is a hard `LIBTEST_FAIL` (`scripts/cross-os-selfhost.sh`, the `no such directory tests/tcyr/$LIBTEST` check) instead of a glob that matches nothing and passes. `CYRIUS_CROSS_OS_FULL=1` runs the whole `tests/tcyr` corpus instead (it alone also starts the lib-test, 6.7.12), and the hosts in the script's `CO_FULL_HOSTS` run it by default (6.7.12, D8 — ecb, ach and pi; cass since 6.7.14, when its full run reached zero; `CYRIUS_CROSS_OS_FULL=0` forces the subset). Safe to run concurrently (a private `mktemp -d` locally, a per-run `~/_cyaud_<id>` remotely, `C:\cyrius-tests\_cyaud_<id>` on cass): the release gate starts the four legs beside check.sh and waits for them at step 4 (`CYRIUS_GATE_SERIAL=1` walks them one at a time after it).

## Verify your env

```sh
for t in qemu-aarch64 qemu-system-x86_64 wine llvm-objdump objdump nm readelf gcc cc clang gdb lldb \
         ssh scp tar gzip xxd file sha256sum diff cmp cpio parted mformat python3 openssl curl git; do
  command -v "$t" >/dev/null 2>&1 && echo "✅ $t" || echo "❌ $t  (install per table above)"
done
python3 -c "import yaml" 2>/dev/null && echo "✅ pyyaml" || echo "❌ pyyaml"
[ -f /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd ] && echo "✅ OVMF (Arch path)" || echo "❌ OVMF at /usr/share/edk2-ovmf/x64/"
```

A `❌` on `qemu-aarch64` or `wine` means platform self-host bugs can only be
reproduced by SSHing to `pi`/`cass` — install them before any cross-target
codegen work. A `❌` on `qemu-system-x86_64` or `openssl` is worse in kind: those
two gates do not fail, they **SKIP**, so check.sh comes back `GREEN, with N gate(s)
SKIPPED` over untested kernel boot and untested EFI signing — and the release gate
then fails. The same holds for every row marked SKIP in *What the gates need*.
