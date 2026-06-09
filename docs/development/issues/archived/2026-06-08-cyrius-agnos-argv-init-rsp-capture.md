# cyrius (agnos target): `argc()`/`argv()` return 0/null in non-trivial programs — init-rsp capture grabs a shifted rsp

> **RESOLVED — cycc 6.1.14 (2026-06-08).**
> **Bug 1 (FIXED):** the `call _agnos_capture_rsp` emission was moved out of the
> entry *epilogue* (after `PARSE_PROG`) up to immediately after `EMIT_GVAR_INITS`
> / before `PARSE_PROG` in `src/main.cyr` — the same placement the x86-macOS
> `_macho_capture_args` capture already uses, so rsp still equals the kernel init
> stack at capture time, ahead of any top-level statement that shifts it. The
> capture fn (`lib/args_agnos.cyr`, `rbp+16` read) was correct and is unchanged —
> only the call-site timing was wrong. Emit-level A/B verified on real `--agnos`
> output: in a program with loose top-level statements the capture call moves
> from *after* the top-level `call`s (old) to *before* them (new), with no
> rsp movement between entry and the capture. x86 cycc self-hosts byte-identical;
> ecb/cass cross-OS self-host green; check.sh 87/87.
> **Bug 2 (CLOSED — not a cyrius defect):** `syscall(60, …)` lowers *correctly*
> (`rax=60`, `rdi=137`, `syscall` — verified in disassembly). It's a no-op because
> **agnos has no syscall 60** (table is 0–33; `exit` = syscall **0**). It "works"
> at top level only because cycc's auto-`EEXIT` (which translates to agnos exit 0)
> follows. agnos is a source-level syscall-numbering target — code must use
> `SYS_EXIT` (= 0), never a hardcoded `60`. bannermanor fixes its call sites.
> See CHANGELOG [6.1.14].

> **FILE INTO:** `cyrius/docs/development/issues/2026-06-08-...md` — written here (agnos) only because the discovering session is hands-off on the cyrius repo. Two distinct agnos-target codegen bugs, both QEMU-reproduced against a real agnos 1.43.7 kernel. No iron needed to reproduce.

- **Severity:** HIGH (Bug 1 — blocks the entire argv-reading agnos userland: `bnrmr`, `cmdrs`, and any tool that reads command-line arguments). MEDIUM/latent (Bug 2).
- **Target:** `--agnos`, x86_64. Other targets unaffected.
- **Toolchain reproduced on:** cycc **6.1.13** (also present on 6.0.56-era vendored libs; the capture *placement* is cycc-side, so the lib version is irrelevant). Kernel: agnos **1.43.7**. Boot: gnoboot + OVMF q35 + NVMe (QEMU).
- **NOT related to:** the 6.1.13 `fnptr.cyr` fncall fix (different bug; `argc`/`argv` use no fncall and no vtable). Bug 1 persists after rebuilding on 6.1.13.

---

## Bug 1 — `argc()` returns 0 (init-rsp capture is wrong) in real-world programs

### Symptom

A cyrius `--agnos` program that calls `argc()`/`argv()` gets the **correct** answer when the program is small, and **`argc()==0` / `argv(n)==null`** when the program is non-trivial. The downstream effect in `bannermanor`: `bnrmr agnos` sees `argc()==0`, hits `if (ac <= 1) { print_usage(); return 0; }`, and prints help instead of rendering the banner — even though the kernel staged `argv` correctly and a sibling program reads it fine.

### How `args_agnos` is supposed to work

`lib/args_agnos.cyr` captures the init stack pointer via a cycc-emitted `call _agnos_capture_rsp` placed *"at the epilogue, just before `call main`, while rsp still = the init rsp"*, relying on the stated assumption:

> *"On the agnos executable path (km==0) nothing moves rsp between e_entry and the auto-call to main."*

`_agnos_capture_rsp` computes `rbp+16` (its own return-addr + saved-rbp) = the rsp at the **call site**, and stores it to the module global `_agnos_init_rsp`. `argc()` returns `load64(_agnos_init_rsp)`; `argv(n)` reads `load64(_agnos_init_rsp + 8 + n*8)`.

**The assumption is false for non-trivial programs.** Top-level / module-init code that runs between `e_entry` and the `call main` site *does* move rsp, so the capture records a pointer into the entry frame (which happens to hold 0) instead of the kernel's init stack.

### Reproducers (all run via `execwait #37` from agnsh on a real 1.43.7 kernel, QEMU)

Each program is built `cyrius build --agnos`, seeded onto an ext2 rootfs as `/bin/<name>`, and launched from agnsh. Exit code is read from agnsh's `run: exit N`.

| Program | What it does | Result |
|---|---|---|
| hand-built `/bin/argv Z` (kernel selftest, reads `[rsp]` in raw asm) | reads argv[1][0] | **exit 90** ('Z') — kernel staging is correct |
| `cargv` (minimal cyrius: `args_init(); return load8(argv(1))`) | reads argv[1][0] via `args_agnos` | **exit 90** — `args_agnos` works in a small program |
| `cargv3` (replicates bnrmr's full 8-flag `flags_new/add/parse` setup) | returns `strlen(positional[0])` | **exit 5** ('agnos') — argc=2, flags+positional all correct |
| `cargvg` (cargv + two module-global *expression* gvars `var G = 0 - 1;`) | reads argc | **argc=2 correct** — expression-gvars are NOT the trigger |
| **`bnrmr agnos`** (real tool: `flags` + `darshana` + `fmt` + embedded font tables) | reads argc | **`argc()==0`** ← the bug |

Minimal failing-vs-passing pair: `cargv` (passes) vs `bnrmr` (fails). The trigger correlates with the amount/shape of top-level init code the program pulls in (bnrmr uses `darshana`/`fmt`/font tables on top of `flags`); `flags` alone (`cargv3`) and expression-gvars alone (`cargvg`) do **not** trigger it.

### Root cause (disassembly)

Both `cargv_agnos` (works) and `bnrmr_agnos` (fails) **contain and call** `_agnos_capture_rsp` right before `call main`:

```
cargv  entry:  ... 41491b: call 0x40d257 (_agnos_capture_rsp);  414920: call 0x41422b (main)
bnrmr  entry:  ... 421fa8: call 0x40d6e9 (_agnos_capture_rsp);  421fad: call 0x420cbe (main)
```

Both capture bodies are byte-identical and store `rbp+16` (= call-site rsp) to their `_agnos_init_rsp` global:

```asm
push   %rbp ; mov %rsp,%rbp ; sub $0x10,%rsp
xor    %eax,%eax ; mov %rax,-0x8(%rbp)
lea    0x10(%rbp),%rax          ; rax = call-site rsp
mov    %rax,-0x8(%rbp)
mov    -0x8(%rbp),%rax
movabs $<&_agnos_init_rsp>,%rcx ; cargv: 0x414c08   bnrmr: 0x422298
mov    %rax,(%rcx)              ; _agnos_init_rsp = call-site rsp
```

So the capture **runs** for bnrmr too — but `argc()` still reads 0. That means `rbp+16` at bnrmr's capture-call site **≠ the kernel's init rsp**: bnrmr's larger entry/module-init sequence shifts rsp before the capture, so it records a stale entry-frame address (whose qword is 0). cargv's minimal entry doesn't shift rsp, so its capture records the true init rsp and `argc()==2`.

(Note for anyone reproducing: referencing `_agnos_init_rsp` directly from consumer `src/` binds to a *phantom* implicit global, not the lib's — the LSP flags "undefined variable". Measure `argc()` via its public accessor, not the raw global.)

### Proposed fix

Capture the init rsp at the **absolute first instruction of `e_entry`**, where `rsp == kernel init rsp`, *before* any module-init / top-level initializer code runs — not "just before `call main`". Options:

1. Emit an inline `mov [_agnos_init_rsp], rsp` (or `lea`/store) as the very first thing at the entry, ahead of gvar-init emission (`EMIT_GVAR_INITS`) and the top-level body. Then `_agnos_capture_rsp`'s `rbp+16` heuristic is unnecessary.
2. Equivalently: have the entry preserve the init rsp in a callee-saved reg reserved across the whole entry, and spill it to `_agnos_init_rsp` before `call main`.

The defect is purely the **timing/placement** of the capture relative to top-level init code; the `args_agnos` read side is correct.

### Consumer-side asm workaround (if cyrius fix lags)

From `main()` the true init rsp is recoverable by walking the saved-rbp chain to the entry frame (cycc calls `main` directly from the entry, so `main`'s caller frame *is* the entry frame; the kernel sets rbp=0 at exec, so the top of the chain is identifiable), then adding the fixed entry-prologue offset. This is implementable in a small committed `asm { }` helper without touching cyrius or the vendored lib. (Being prototyped on the bannermanor side as the immediate unblock.)

---

## Bug 2 — `syscall(SYS_EXIT, …)` from a non-top-level function is a no-op

### Symptom

`syscall(60, x)` (the exit syscall) works at **top level** (cargv exits with the right code) but is a **silent no-op when called from inside a nested function** — execution falls through instead of terminating.

### Reproducer

```cyrius
fn helper(): i64 { syscall(60, 137); return 0; }
fn main(): i64 { helper(); return 5; }
var r = main();
syscall(60, r);
```

Built `--agnos`, run via agnsh → **`run: exit 5`** (expected 137). `helper`'s `syscall(60,137)` did not trap; control returned, `main` returned 5, and only the top-level `syscall(60, r)` exited. Confirmed independently: a `println("MARK"); syscall(60,137);` as the first two lines of a function prints `MARK` and then keeps running past the exit.

### Impact

Latent — most programs exit via `return` up to the top-level exit syscall, so they're unaffected. But any code that calls `exit()`/`syscall(SYS_EXIT,…)` (or any raw syscall?) from a helper mid-execution has it silently dropped. (Open question: is this specific to the exit syscall, or do all `syscall()` builtins mis-emit in nested-function context on agnos? `println`'s internal write-syscall works mid-function, so it is not *all* syscalls — needs narrowing.)

### Suggested investigation

Why the `syscall()` builtin in a nested function body on `--agnos` doesn't emit a trapping `syscall` with `rax=60` — candidate areas: DCE marking post-syscall code unreachable and dropping the call, inlining/tail-call handling, or the builtin's lowering differing between the top-level entry context and a regular function frame.

---

## Test harness (for reproduction)

- Build tool: `cyrius build --agnos src/<x>.cyr build/<x>_agnos` (static ELF64).
- Seed onto ext2: `mkfs.ext2 -d <seed-with-/bin/<x>>` on a GPT image with an ESP carrying gnoboot + the agnos kernel.
- Boot: `qemu-system-x86_64 -machine q35 -cpu max -device nvme,... -device qemu-xhci -device usb-kbd ...`, OVMF pflash.
- Drive: agnsh (PID-1-exec'd) types `<name> <arg>` via HMP `sendkey`; read `run: exit N` from the serial log. Encode the value under test in the program's exit code.
