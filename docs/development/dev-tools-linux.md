# Development Tools — Linux (x86_64 dev / verification host)

> One file **per environment** so moving env→env we install the proper tools
> up front instead of discovering a gap mid-debug. This is the **x86_64 Linux
> dev box** — the primary build + cross-emit + cross-host-verify machine.
> Siblings (to be added): `dev-tools-macos.md`, `dev-tools-windows.md`.
>
> Reference distro: **Arch Linux** (`pacman`). `apt` equivalents are listed for
> Ubuntu-based hosts (e.g. the `pi` aarch64 target host, GitHub CI runners).

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
  qemu-user qemu-system-x86 wine llvm binutils gdb lldb openssh python-yaml xxd file \
  coreutils python openssl curl
```

Ubuntu/Debian (`pi`, CI images):

```sh
sudo apt-get install -y \
  qemu-user-static qemu-system-x86 wine llvm binutils gdb lldb openssh-client python3-yaml \
  xxd file coreutils python3 openssl curl
```

## Tools

| Tool | Arch pkg | apt pkg | Why it's needed | Verify |
|------|----------|---------|-----------------|--------|
| `qemu-aarch64` | `qemu-user` | `qemu-user-static` | Run the **aarch64 ELF** cycc locally — reproduce/bisect the native-aarch64 self-host without SSHing to `pi` | `qemu-aarch64 --version` |
| `qemu-system-x86_64` | `qemu-system-x86` | `qemu-system-x86` | **`check.sh` gate** — `scripts/qemu-boot-gate.sh` really BOOTS the `kernel;` build and asserts it writes `AGNOS` to serial. **Absent → the gate prints `SKIP` and check.sh still reads green** (CI sets `CYRIUS_REQUIRE_BOOT=1` to make that a hard FAIL) | `qemu-system-x86_64 --version` |
| `wine` | `wine` | `wine` | Run the **Windows PE** `cycc.exe` locally — reproduce/bisect the Windows self-host without SSHing to `cass` | `wine --version` |
| `llvm-objdump` | `llvm` | `llvm` | Disassemble **x86-64 / aarch64 / PE / Mach-O** — read codegen out of any emitted target binary | `llvm-objdump --version` |
| `objdump` / `nm` | `binutils` | `binutils` | x86-64 ELF disasm / quick header dumps; `nm` backs the agnos cross-build gate's symbol check | `objdump --version` |
| `gdb` | `gdb` | `gdb` | Debug the x86-64 Linux cycc + emitted ELF | `gdb --version` |
| `lldb` | `lldb` | `lldb` | Debug under wine / inspect Mach-O-shaped output | `lldb --version` |
| `ssh` / `scp` | `openssh` | `openssh-client` | **Authoritative** cross-host self-host verification on real hardware (`ecb`/`ach`/`pi`/`cass`) — see `scripts/cross-os-selfhost.sh` | `ssh -V` |
| `python` + `pyyaml` | `python` `python-yaml` | `python3` `python3-yaml` | Validate `.github/workflows/*.yml` locally; CI parses PE headers with python | `python3 -c "import yaml"` |
| `xxd` | `xxd` | `xxd` | Inspect Mach-O/PE magic + byte-level header gates | `xxd -v` |
| `file` | `file` | `file` | Confirm emitted binary format (`Mach-O … arm64`, `PE32+`, `ELF … aarch64`) | `file --version` |
| `sha256sum` | `coreutils` | `coreutils` | Byte-identical self-host proof + release checksums | `sha256sum --version` |
| `tar` | `tar`* | `tar` | Bundle `src/ lib/ VERSION` for shipping to verification hosts | `tar --version` |
| `openssl` | `openssl` | `openssl` | **`check.sh` gate** — `scripts/sign-efi-gate.sh` uses it as the *independent oracle* (it is not used by the signer) that `cyrius sign-efi`'s Authenticode signature is one real UEFI firmware would accept. **Absent → `SKIP …: openssl not available`, exit 0** | `openssl version` |
| `curl` | `curl` | `curl` | Release + install paths (`scripts/ci.sh`, `install.sh`, `release-lib.sh`) and **the only sanctioned way to reach the GitHub API** — `gh` is banned per CLAUDE.md | `curl --version` |

\* `tar`, `getent`, `cmp`, `printf` ship in the base system.

> ⚠ **The two `check.sh` gates above SKIP silently when their tool is missing** — the run
> still prints `N passed, 0 failed`. That is the same green-checkmark-over-nothing shape the
> cross-OS principle exists to stop, so on a box that gates releases, treat `qemu-system-x86`
> and `openssl` as required, not optional.

The cyrius compiler itself is **bootstrapped**, not packaged: `sh bootstrap/bootstrap.sh` (seed asm → `cybs` → `cycc`). No crates.io, no toolchain package — that's the point.

## What each capability unlocks

- **Cross-emit all targets here** — each target has its OWN source fork, so the driver file
  changes with the target, not just the env var (`scripts/build-macos-*-tarball.sh` and
  `scripts/cross-os-selfhost.sh` are the authority on which pairs are correct):

  - aarch64 ELF — `cat src/main_aarch64.cyr | build/cycc`
  - x86 Mach-O — `cat src/main_x86_macho.cyr | CYRIUS_MACHO=1 build/cycc`
  - arm64 Mach-O — `cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 build/cycc`
  - Windows PE — `cat src/main_win.cyr | build/cycc > cycc_win`, then `cat src/main_win.cyr | ./cycc_win`
  - cx bytecode — `cat src/main_cx.cyr | build/cycc`

  All from the x86 seed.
- **Local self-host repro:** `qemu-aarch64 ./cycc_a64 < src/main_aarch64.cyr` and `wine ./cycc.exe < src/main_win.cyr` reproduce the real-hardware self-host result locally.
- **Authoritative verify:** `sh scripts/cross-os-selfhost.sh <ecb|ach|pi|cass> [tcyr-glob]` self-hosts on the real host (qemu/wine are for fast iteration; **real hardware is the gate** — see CLAUDE.md "Cross-OS self-host is non-negotiable, on REAL hardware"). The release gate passes `vr01_` as the glob for all four hosts; `CYRIUS_CROSS_OS_FULL=1` runs the whole `tests/tcyr` corpus instead. Run **one host at a time** — the fixed `/tmp` and remote paths clobber under concurrency.

## Verify your env

```sh
for t in qemu-aarch64 qemu-system-x86_64 wine llvm-objdump objdump nm gdb lldb ssh scp \
         tar xxd file sha256sum python3 openssl curl; do
  command -v "$t" >/dev/null 2>&1 && echo "✅ $t" || echo "❌ $t  (install per table above)"
done
python3 -c "import yaml" 2>/dev/null && echo "✅ pyyaml" || echo "❌ pyyaml"
```

A `❌` on `qemu-aarch64` or `wine` means platform self-host bugs can only be
reproduced by SSHing to `pi`/`cass` — install them before any cross-target
codegen work. A `❌` on `qemu-system-x86_64` or `openssl` is worse in kind: those
two gates do not fail, they **SKIP**, so check.sh comes back green over untested
kernel boot and untested EFI signing.
