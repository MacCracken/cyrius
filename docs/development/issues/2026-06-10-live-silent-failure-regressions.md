# Live silent-failure regressions (fix-now cluster) — CVE-22/23/31, CO-02/03

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** cycc / stdlib 6.1.31

## Summary

Five confirmed "a loud failure was silently turned into a silent failure"
bugs. None bite today only because no test exercises the path. All are
small and byte-identical for valid inputs — a single packed release.

## CVE-22 — `_vec_die`/`_hm_die` infinitely self-recurse (P1)

v6.0.56 (commit `4bc39019`) replaced a working `syscall(60,1)` with a target
dispatch whose `#ifndef CYRIUS_TARGET_AGNOS` branch **calls itself**
(`lib/vec.cyr:69`, `lib/hashmap.cyr:224`). On Linux/macOS/Windows every fatal
stdlib abort (vec_get/set OOB, capacity overflow, vec_push OOM, and
`hashmap.cyr:260,290,480,508`) unwinds into unbounded recursion = stack-overflow
SIGSEGV instead of `exit(1)`. The diagnostic write fires first, but the exit
mechanism is broken on the 3 primary targets. The same commit got
`tagged.cyr:82` *right* (`syscall(60,1)`) — proving the typo; CHANGELOG [6.0.56]
falsely claims "behavior-identical on non-agnos".

**Fix:** restore `syscall(60,1);` in the `#ifndef CYRIUS_TARGET_AGNOS` branch of
both fns (one line each). Add a tcyr that triggers a vec OOB and asserts the
exit code (per the per-file exit-code discipline). cycc has no lib includes →
self-host unaffected.

## CVE-23 — 16 MB `output_buf` cap unenforced on non-x86-user emitters (P2)

`grep 16777216`: the cap is checked only in `x86/fixup.cyr:1073/1392/1816`
(EMITELF user/shared/obj) + `macho/emit.cyr:94,298`. It is **absent** from
aarch64 EMITELF (`fixup.cyr:597`) + EMITELF_KERNEL (`:758`), PE EMITPE_EXEC
(`pe/emit.cyr:1069`; `_pe_image_file_size` is computed at `:947/1052` but never
checked), and x86 EMITELF_KERNEL/EMITELF64_KERNEL (`:703/:900`). A >16 MB binary
writes past `brk-final 0x5D9D000` (`main.cyr:386`). Kernel images — the AGNOS
authorship goal and v6.2.x bare-metal — are exactly the unguarded path.

**Fix:** hoist one shared filesz guard into `backend/common/runtime.cyr` (mirror
`x86/fixup.cyr:1073`'s top-3-largest-vars diagnostic) and call it from all 6
unguarded writers; check `_pe_image_file_size` at the end of `_pe_layout`.
Mechanical, byte-identical for under-cap output. **Land before v6.2.x** so
backend #7 (riscv64) inherits the guard rather than repeating the v6.1.27 gap.

## CVE-31 — compiler silently accepts broken input (P1)

`READFILE` returns 0 for unopenable paths (`lex.cyr:650-657`) and the PP
include site adds `nr=0` bytes + sets `had_include=1` with no check
(`lex_pp.cyr:1612-1613`) — a typo'd include surfaces only as downstream
undefined-fn warnings (non-fatal without `--strict`). The lexer's fallthrough
silently skips any unrecognized ASCII byte ≤127 (`lex.cyr:1647-1664`; only >127
errors) — a stray `$`/backtick changes program meaning with no diagnostic.
`file_map` drops files past 128 entries silently (`lex.cyr:28`) → wrong
file:line attribution on big multi-include consumer builds. CHANGELOG [5.10.8]
pinned "compiler should error on missing includes"; that pin was dropped and
never shipped.

**Fix:** hard-error on `READFILE` open-fail at the two PP include sites (print
the filename — distinguish open-fail from empty-file: return -1 on open-fail,
0 on empty); error on skipped unknown chars in LEX's final `else`; warn + raise
the `file_map` cap (needs a relocation — `512×24B` collides with
`file_map_str@0x19D000`; use a freed-band slot, and grow the 4 KB fname-str
region too). Loud-failure conversions, no codegen impact, byte-identical self-host.

## CO-02 — `check.sh` tcyr gate masks crashes (P1)

`regression_exec_capture` waits (`sys_waitpid`, `lib/regression.cyr:297`) but
never reads status — returns only captured bytes. `_tcyr_compile_and_run`
(`programs/checks/selfhost.cyr:695-720`) returns `_tcyr_parse_failed(stdout)`,
which is 0 when `' failed'` is absent (`:674-693`). So a tcyr that segfaults
before printing its summary, or exits nonzero after "0 failed", records **PASS
locally**. The v6.0.83 lesson (`feedback_run_ci_exit_check_before_green`) was
fixed **only in CI** (`ci.yml:193-196` checks `$ec` AND the count); `check.sh`
is the pre-version-bump release gate ("87/87"), so a false-green can be claimed
before CI ever runs.

**Fix:** propagate exit status from `regression_exec_capture` (the header at
`:64` already defines the convention; siblings at `:214/:325` use
`WEXITSTATUS`), fail `_tcyr_compile_and_run` on nonzero matching `ci.yml:196`.
Also cover `selfhost.cyr:35,117` + `codegen_regress.cyr:406,493`. ~20 lines.

## CO-03 — x86 byte-pattern opt passes run unguarded on aarch64/cx (P2)

`DSE_PASS` is called unconditionally (`parse_fn.cyr:2310`) and the LASE loop
(`:2315-2340`) scans codebuf for x86 opcodes `48 89 85`/`48 8B 85` and
overwrites 7-byte windows with `0x90` — **no** `_AARCH64_BACKEND`/`_TARGET_CX`
gate (the compaction pass *is* gated at `:2747`, making the omission visible).
`#regalloc` also sets SFRA without an arch check (`:1408`) while only the AUTO
path gates (`:1394`), so an annotated fn on aarch64 reaches the x86 byte-patching
picker (`:2352`). A64/cx instruction words matching those byte windows get
silently corrupted.

**Fix:** gate `DSE_PASS`, the LASE loop, and the picker entry on
`_AARCH64_BACKEND==0 && _TARGET_CX==0`, and arch-gate the `#regalloc` SFRA at
`:1408` — ~3 one-line guards. **Land before riscv64** (another 4-byte-word ISA
that doubles the false-match surface). Verify byte-identical x86 self-host.

## Status

Filed 2026-06-10. Recommended as one packed hardening release with
[deps-resolver-injection-class](2026-06-10-deps-resolver-injection-class.md).
