# Crash Localization with CYRIUS_SYMS

Since v4.3.1, the cyrius compiler can dump a symbol table during compilation.
Combined with systemd-coredump and a little ELF arithmetic, this turns an
opaque SIGSEGV into a concrete `function + offset` trace — even without gdb
installed. Every backend writes the dump except cx (x86_64 ELF since v4.3.1;
aarch64 ELF, Mach-O and PE since v6.3.23 — `_emit_sym_dump` in
`src/backend/common/runtime.cyr`).

## Usage

```sh
# Compile with symbols written to a side-file (the variable is read by the compiler,
# so it goes on the compiler's side of a pipe; `cyrius build` passes it through)
CYRIUS_SYMS=/tmp/myproj-syms.txt cyrius build

# File format: one function per line, `VA name`
#   000000000040007d strlen
#   0000000000400106 streq
#   00000000004001a8 memeq
#   ...
```

Zero cost when the env var is unset — the feature is purely opt-in.

The addresses are where the function sits in the image. A default (non-PIE)
Linux ELF loads at `0x400000` (a PE at its ImageBase), so they match the
absolute addresses in a stack trace; with `--pie` the image base is 0, so
match a frame's `+ 0x…` offset from the binary instead.

Under `CYRIUS_DCE=1` an x86_64 ELF build (a kernel image and `CYRIUS_WX=0`
included) removes its unreachable functions and moves the code down, and the
file is written after that: a removed function is absent and every other one
is at its moved address. (Until 6.7.14 the file held the pre-compaction
addresses — a removed function at a live one's address, and everything after
it too high.) A dead function the compiler keeps — one holding an instruction
the length decoder cannot size, or one whose range holds a live generic
instance — stays listed where it now sits.

## Mapping a crash to a function

```sh
# 1. Run the failing binary; coredumpctl captures the core
./build/myproj

# 2. Grab the stack trace (no gdb needed)
coredumpctl info | grep "Stack trace" -A 10
#   #0  0x0000000000400219 n/a (/tmp/myproj + 0x219)
#   #1  0x000000000045284d n/a (/tmp/myproj + 0x5284d)

# 3. Resolve each frame against the symbol file
python3 -c '
import sys
syms = sorted((int(l.split()[0],16), l.split()[1]) for l in open(sys.argv[1]))
for addr in [int(a,16) for a in sys.argv[2:]]:
    prev = None
    for off, name in syms:
        if off > addr: break
        prev = (off, name)
    print(f"0x{addr:x} -> {prev[1]} + 0x{addr-prev[0]:x}")
' /tmp/myproj-syms.txt 0x400219 0x45284d
# 0x400219 -> memeq + 0x71
# 0x45284d -> test_patrastore_append_load + 0x235
```

## Reading the offset

`memeq + 0x71` means the crash instruction is 113 bytes into `memeq`. Count
instructions in the .cyr source or dump the binary bytes to find the exact
statement. Tail calls (Cyrius emits `mov rsp,rbp; pop rbp; jmp target`)
don't appear in the stack — the callee's caller is the next frame up.

## When you need more

- **Register state at crash**: install `gdb`, run `coredumpctl gdb <pid>`,
  then `info registers`.
- **Data memory dump**: same gdb workflow; use `x/64gx <addr>` to peek.
- **Live tracing**: install `strace` — syscall-level tracing shows which
  fd/path/size combo preceded the fault.

## Open bugs

Open bugs, including crashes this tool localized, live in
[`docs/development/issues/`](issues/).
