# Process Notes — Historical (Phases 3-6, April 2026)

> **Historical artifact** — dated journal entries from the
> pre-v5.0.0 bootstrap phases. References `cc2` / `cc3` /
> `cyrc` / `Stage1f` binary names that were retired at the
> `cc3` → `cc5` rename (v5.0.0); the current toolchain
> binary is `cc5` (will be `cyc` post-v6.0.0 per the
> permanent-binary-name rule in CLAUDE.md).
>
> **For current process discipline**: [`CLAUDE.md`](../../CLAUDE.md)
> "Doing tasks" / "P(-1)" / "Closeout Pass" sections +
> [`cycle-discipline.md`](cycle-discipline.md) (evergreen
> operating principles: slot acceptance, bottom-to-top
> priority, premise-check, cross-host smoke, cycle-close
> shape).
>
> **For current state**: [`state.md`](state.md) — volatile
> per-release status. **For shipped work**:
> [`../CHANGELOG.md`](../../CHANGELOG.md) — canonical source
> of truth.

Development observations across the pre-v5.0.0 phases.

---

## Date: 2026-04-04 — Phase 4 Complete + Phase 5 In Progress

### Language Extensions Shipped
- Structs (definition, init, field access, field assignment)
- Multi-width memory (load/store 16/32/64)
- Pointers (*deref, *store)
- >6 function parameters (stack-passed)
- Include directive (file I/O preprocessing)
- Inline assembly (raw byte emission)
- Progressive type annotations (var x: i64, fn f(a: i64))
- Elif keyword (eliminates brace-counting bug class)
- Duplicate var detection at compile time
- Error messages with token position

### Real Programs Built
15 Linux programs: true, false, echo, cat, head, tee, yes, nl, wc, rev, seq, tr, uniq, sum, grep. All under 10KB. Cyrius wc is 2.4x FASTER than GNU wc on 1MB.

### Key Bugs Found and Fixed
1. **VCNT restore erasing function-scope globals** — arrays inside functions were lost after function parsing. Fix: don't restore VCNT.
2. **Duplicate var names** (hit 5 times!) — finally added compile-time detection.
3. **Hex literal underscores** — cyrc doesn't support `_` in numbers.
4. **Function table overflow** — 136 fns in 128-slot table. Bumped to 256.

### Development Loop
Research → vidya → plan → build → test → audit → vidya. Vidya front-loads thinking. Pointers took 15 lines because vidya had the patterns. Structs took hours because vidya didn't. The reference library IS the velocity.

### Metrics
- 137 tests, 0 failures (80 cc + 11 asm + 46 programs)
- cc2: ~2572 lines, 181 functions, 7 modules, self-hosting (cc2==cc3)
- 100+ vidya entries across compiler_bootstrapping, code_generation, kernel_codegen
- Bootstrap: 40ms. Self-compile: 8ms. 38 programs.
- Token arrays: 32768. Codebuf: 196KB. Input buffer: 128KB.
- build/cc2 committed to git. cc.cyr updated: elif, codebuf, input buffer.
- Phase 6 COMPLETE. Phase 7 STARTED: boot_serial prints "AGNOS" on QEMU.

---

## Date: 2026-04-04 — Phase 3 Complete: Rust Independence

### What We Did

1. Built stage1e (bitwise ops: % & | ^ ~ << >>, hex literals, comments, uppercase idents — 63 tests)
2. Built cyrc (token scaling: 4096→16384 slots — mechanical offset change)
3. Wrote asm.cyr (self-hosting assembler: 1128 lines, 43 mnemonics, two-pass, heap-based state)
4. Achieved bootstrap closure: seed→cyrc→asm→cyrc_v2 byte-identical
5. Committed bootstrap binary (bootstrap/asm, 29KB) + bootstrap.sh
6. Archived Rust seed (archive/seed/), deinited upstream submodule (saved 13GB)
7. Cyrius now bootstraps with: `sh bootstrap/bootstrap.sh` — no Rust, no LLVM, no Python

### Key Bugs Found

1. **Duplicate var names create separate stack slots** — declaring `var val` in two branches of the same function creates two separate local slots. The compiler allocates ALL var declarations during parsing regardless of control flow. Fix: split into separate functions (SHEX/SDEC for hex/decimal parsing).
2. **fn-before-var ordering** — cyrc's parser requires all fn definitions before var declarations. Functions can't reference globals. Fix: heap-based state (S pointer + fixed offsets), passed as first param to every function.
3. **Return value 0 vs -1 for try-parse** — DO_ALU2 returned 0 on success (reg,reg handled), but 0 is rax's register code. Caller treated 0 as "unhandled, try immediate." Fix: return -1 for "handled," positive register code for "unhandled."
4. **Input buffer overflow** — stage1d.cyr (73KB) didn't fit in 64KB input buffer. Silent truncation, labels past the cutoff couldn't be found. Fix: increased to 128KB.

### Architecture Decisions

- **Heap state pattern**: All assembler state lives at fixed offsets from a heap base pointer (S). Every function takes S as its first parameter. This mirrors cyrc's own r15+offset pattern but at the high-level language layer.
- **Packed word comparison**: Mnemonics dispatched by packing identifier bytes into a 64-bit value and comparing against precomputed constants — same technique cyrc's lexer uses for keywords.
- **Incremental testing**: Each mnemonic addition verified by byte-exact comparison with seed output. Caught encoding errors immediately rather than at integration time.

### What Worked Well

- Bite-sized approach: V1 (8 mnemonics) → V2a (memory operands) → V2b (everything else). Each step tested independently.
- Byte-exact comparison as gold standard — caught every encoding bug.
- vidya reference material (instruction_encoding, compiler_bootstrapping) prevented several encoding mistakes.

---

## Date: 2026-04-03

### What We Did

1. Added rust-lang/rust as a shallow submodule at `upstream/`
2. Discovered cargo is a nested submodule — had to `git submodule update --init --depth 1 src/tools/cargo` separately
3. Installed `ninja` (missing build dep)
4. Created `bootstrap.toml` with `profile = "compiler"` and `change-id = "ignore"`
5. Ran `python3 x.py build` — completed in 5:19
6. Result: `rustc 1.96.0-dev` (stage 1)

### Problems Observed

#### 1. Nested Submodules
- rust-lang/rust contains 12+ submodules (cargo, LLVM, gcc, book, reference, etc.)
- Each must be initialized separately or with `--recursive` (which pulls everything)
- Shallow clones help but add complexity
- **Cyrius fix**: single repo. No submodules. The compiler, stdlib, and package manager live in one tree.

#### 2. Python Bootstrap
- The entire build orchestration runs through `x.py`, a Python script
- Python 3 is a hard requirement to build Rust
- `x.py` downloads a pre-built beta `rustc` from Rust CI to compile the real compiler
- "Building from source" is actually "building from source + a binary you downloaded"
- **Cyrius fix**: self-hosting bootstrap. The Cyrius compiler builds the Cyrius compiler. A minimal seed binary is the only external dependency, and that's a one-time cost.

#### 3. External Build Dependencies
- cmake and ninja required for LLVM (unless using CI-built LLVM)
- CI-built LLVM is the default — saves time but means you're trusting a binary from someone else's CI
- **Cyrius fix**: own the entire toolchain. No cmake, no ninja, no external LLVM binaries in the final state.

#### 4. Bootstrap Config Complexity
- `bootstrap.example.toml` is hundreds of lines
- Profiles (`compiler`, `library`, `tools`, etc.) help but the surface area is enormous
- `change-id` tracking for config schema changes is clever but adds friction
- **Cyrius fix**: minimal, opinionated defaults. One build command, no config file for the common case.

### What Worked Well

- CI-built LLVM made the build fast (5 min vs. 60+ min)
- `profile = "compiler"` gave sane defaults
- The stage 1 compiler works immediately
- 16 cores utilized well during compilation
