# Cyrius — Apple Silicon (arm64 Mach-O)

This tarball ships the full Apple Silicon toolchain as arm64 Mach-O:
the compiler (`cycc` / `cycc_aarch64`), the `cyrius` build-tool
wrapper, the quality tools (`cyrfmt`, `cyrlint`, `cyrdoc`), the
version manager (`cyriusly`), and the stdlib. The binaries are
cross-built on Linux and **unsigned**; `install.sh` ad-hoc codesigns
each at install time (an unsigned arm64 binary is AMFI-SIGKILL'd on
first exec), and `cyrius build` ad-hoc-signs its own output.

After install, `cyrius build foo.cyr foo && ./foo` works directly.

> **NOTE (v6.0.38):** before v6.0.38 this tarball shipped only a
> `smoke.macho` toy binary and **no compiler** — every macOS arm64
> install was empty. The release packaging plus a real-install
> verification gate (`cyrius audit --internal=platform-check`, run on real
> Apple Silicon; v6.2.12 moved the cross-OS/install gate behind that flag) were
> added in v6.0.38 so this can't regress unnoticed. See CHANGELOG.

## Status

The macOS aarch64 target reached functional parity with Linux
x86_64 / aarch64 and Windows PE32+ over the v5.5.11–v5.5.17 arc; the
v6.0.32–v6.0.38 arc fixed the on-device runtime (self-host, exit-code
propagation, `cyrius build`) **and the release/install packaging**
that had been shipping nothing.
Cross-compiled Cyrius binaries run through `libSystem` via
classic dyld binds, use an mmap-based heap, read command-line
args from the Darwin ABI entry registers, and call out to
`_exit` / `_write` / `_read` through a bound `__got`.

## How it works

### libSystem import layer (v5.5.11–14)

`EMITMACHO_ARM64` embeds a `__DATA_CONST` segment with a `__got`
section holding six slots — bound by dyld at load time to:

| slot | libSystem symbol   | use                                 |
|------|--------------------|-------------------------------------|
| 0    | `_exit`            | `syscall(60, code)` tail-call       |
| 1    | `_write`           | `syscall(1, fd, buf, len)` reroute  |
| 2    | `_read`            | `syscall(0, fd, buf, len)` reroute  |
| 3    | `_malloc`          | imports-only (reserved for C FFI)   |
| 4    | `_fopen`           | imports-only                        |
| 5    | `_pthread_create`  | imports-only                        |

Reroutes compile to `adrp x16, __got@PAGE; ldr x16, [x16, #slot*8]; br/blr x16`.
`FIXUP_ADRP_LDR` (v5.5.14) scales the LDR imm12 field by /8 for
non-zero slots.

### Per-OS stdlib dispatch (v5.5.16)

When `CYRIUS_MACHO_ARM=1` is set, `cycc_aarch64` predefines
`CYRIUS_TARGET_MACOS` (instead of `CYRIUS_TARGET_LINUX`). Stdlib
modules dispatch per-OS:

- `lib/alloc.cyr` → `lib/alloc_macos.cyr` (mmap-based, no brk).
- `lib/args.cyr` → `lib/args_macos.cyr` (see argv plumbing below).
- `lib/io.cyr` flock helpers are `#ifdef CYRIUS_TARGET_LINUX`-gated
  (Darwin BSD flock number doesn't match Linux's 73).

### argv plumbing (v5.5.17)

At LC_MAIN entry the Darwin ABI hands `argc` in x0, `argv` in x1,
`envp` in x2, and `apple[]` in x3. `main_aarch64.cyr` emits an
entry prologue BEFORE any other code runs:

    stp x0, x1, [sp, #-16]!    ; push argc/argv
    mov x28, sp                 ; x28 = base pointer

x28 is callee-saved per AAPCS64 and the cyrius aarch64 backend
doesn't touch it, so the pointer stays durable for the program's
lifetime. `lib/args_macos.cyr` reads x28 via inline asm to expose
`argc()` and `argv(n)` with the same API as the Linux peer — no
`/proc/self/cmdline` reach-around (XNU has no procfs).

## Cross-compiling

Install the Linux x86_64 tarball on a Linux host and run:

    CYRIUS_MACHO_ARM=1 build/cycc_aarch64 < my.cyr > my.macho
    chmod +x my.macho
    scp my.macho apple-silicon-host:/tmp/
    ssh apple-silicon-host 'codesign -s - /tmp/my.macho && /tmp/my.macho'

Tool binaries ship pre-built in this tarball:

    ./cyrfmt file.cyr               # format to stdout
    ./cyrfmt --check file.cyr       # exit 1 if formatting differs
    ./cyrlint file.cyr              # lint warnings
    ./cyrdoc file.cyr               # generate markdown API reference
    ./cybs vet file.cyr             # scan dependencies

## Known limitations

- `src/main.cyr`'s `--version` / `--strict` flag parsing still reads
  `/proc/self/cmdline`. Only relevant if `cycc` itself is ever
  built as a macOS binary (not today's flow — `cycc_aarch64` cross-
  compiles FROM Linux TO Mach-O).
- `envp` / `apple[]` are not exposed by `lib/args_macos.cyr`.
  Trivial follow-up: grow the entry prologue to push x2/x3 too.
- `_malloc` / `_fopen` / `_pthread_create` are bound at load but
  have no `syscall()`-shape reroute. Reserved for future C-FFI
  calls.
