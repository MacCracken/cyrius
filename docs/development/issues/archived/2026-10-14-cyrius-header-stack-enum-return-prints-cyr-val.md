# `cyrius header` prints `cyr_val f(..)` for a fn returning a `: stack` enum (`: Result` / `: Option`, the stdlib's value form), which cycc returns as a (tag, payload) pair in rax:rdx — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-22: `: Result` / `: Option` / `: Tagged` (and a file's own `enum E: stack`) returns print `cyr_val2 f(..);   /* returns Result: the tag in w0, the payload in w1 */` under `#if defined(__x86_64__) && !defined(_WIN64)`, a named comment elsewhere — the repro's `parse` and lib/process.cyr's `run`, `run_capture`, `spawn`, `wait_pid`, rc 0; a linked C caller reads `0 42|1 5`. ⚠ The issue's x0:x1 on aarch64 is wrong: cycc returns the pair in x0:x2 (measured on qemu, pi and ecb), so the guard is x86_64 SysV only. A public fn whose signature says a word (none, or `: i64`) but whose body returns the pair — a payload constructor, or a pair fn of the same file, to a fixpoint — is refused by name, rc 1. The user's decision D23, 2026-10-15 (refuse by name, annotated pairs modelled; applied to `: i64` signatures as well as unannotated ones — lib/result.cyr and five folds' sources now exit 1). Rows: `header_spellings_and_size.sh` H12 (22 fns with cycc's single-bind refusal as the oracle); mutations RED. Filed beside it (6.7.13): a fn pair-returning only through `?` still prints `cyr_val`. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 tools lane (l6711-tools @ a3d9837d) with its
`build/cyrius` and `build/cycc` (throwaway `HOME` / `CYRIUS_HOME`).
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D23 — refuse by name (annotated pair returns modelled).
**Discovered:** 2026-10-14 by the 6.7.11 tools lane's review of the header struct-return bite
(issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md). That filing names structs and `dyn`; a stack enum is
outside its surface. Same class as the staged vector-return issue
(issues/archived/2026-10-14-cyrius-header-vector-return-prints-cyr-val.md).
**Severity:** Medium — a generated C header that is wrong for every public fn returning a stack enum: the C caller
reads rax (the TAG) and never sees the payload in rdx. lib/process.cyr's public `run`, `run_capture`, `spawn` and
`wait_pid` (`: Result`) are printed this way. No memory corruption (a 16-byte register return).
**Affects:** the `cyrius header` verb (cbt/quality.cyr `_hdr_ret_class`), every version that has it.

## Reproduction

`se.cyr`:

```cyrius
include "lib/result.cyr"
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
```

```sh
T=$(mktemp -d); HOME=$T CYRIUS_HOME=$T/.cyrius build/cyrius header se.cyr | grep parse; echo "rc=$?"; rm -rf "$T"
{ echo 'object;'; cat se.cyr; } | build/cycc > se.o && llvm-objdump -d --no-show-raw-insn se.o | awk '/<Ok>:/,/^$/'
```

```
actual:   cyr_val parse(cyr_val x);            (rc 0)

          <Ok>:  pushq %rbp; movq %rsp,%rbp; subq $0x10,%rsp
                 movq %rdi,-0x8(%rbp); movq -0x8(%rbp),%rax
                 movq %rax,%rdx                 <- the payload in rdx
                 xorl %eax,%eax                 <- the tag (Ok = 0) in rax
                 leave; retq
          (parse tail-jumps to Ok / Err, so its return is that pair)

          build/cyrius header lib/process.cyr:
          cyr_val run(cyr_val cmd, cyr_val arg1, cyr_val arg2);
          cyr_val run_capture(cyr_val cmd, cyr_val arg1, cyr_val arg2, cyr_val buf, cyr_val buflen);
          cyr_val spawn(cyr_val cmd, cyr_val arg1, cyr_val arg2);
          cyr_val wait_pid(cyr_val pid);

expected: the pair modelled as the 9-16 B struct return is (`cyr_val2` — tag w0, payload w1 — under the target
          guard where cycc's pair lands where C reads a 16-byte struct, a named comment elsewhere), or the fn refused
          by name on stderr, rc 1, as the header refuses what it cannot express — never `cyr_val`.
```

## Root cause

`_hdr_ret_class` (cbt/quality.cyr) answers "a word" for `Result` / `Option` / `Tagged` through `_hdr_name_w` (their
FIELD width, an 8-byte handle), and for a file's own `enum` through `if (load64(r + 16) == 3) { return 0; }`
without asking whether the enum is declared `: stack`. A `: stack` enum's constructor returns the (tag, payload) pair
in rax:rdx (x0:x1 on aarch64). A fn with NO annotation whose body returns a stack-enum constructor is pair-returning
by propagation (GFLG 256) and cannot be seen from the signature at all.

## Proposed fix

Class a `: stack` enum return (the stdlib's `Result` / `Option` / `Tagged` and a file's own `enum E: stack`) as the
pair, on each target as cycc returns it (verify aarch64 / Win64 / macOS on hardware as the parent bite did); an
unannotated fn that returns a stack-enum constructor is either refused by name or found by the same propagation the
compiler runs — the user's call. Rows in tests/gates/toolchain/header_spellings_and_size.sh (a C caller reading both
words, as H11 does for the struct pair).
