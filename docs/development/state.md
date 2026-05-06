# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.

## Version

**5.9.7** (shipped 2026-05-06 — **v5.9.x SLOT 7 — sovereignty
pass batch 3a/3 (9 conversions: TS acceptance cluster + 3
cyrlint regressions)**. The TS acceptance cluster pinned in
v5.9.4 lands as one 6-script batch sharing a single helper
template (`_parse_ts_dir_gate`) — six `tests/regression-ts-*.sh`
scripts, each with 5-7 inline TS heredocs, extracted to 38 .ts
fixture files in `tests/fixtures/ts_*/` and run through
`cc5 --parse-ts` per fixture. Plus three bespoke cyrlint-
output gates: ts-lex (single 130-line `--lex-ts` fixture),
lint-init-order (4 sub-cases asserting cyrlint's
forward-ref-warning behavior), cyrlint-large-file (7008-line
synthesized fixture asserting zero file-size false-positives).
cc5 unchanged at **741,048 B** — `programs/` +
`tests/fixtures/` work; the compiler binary is not touched.

**Premise-check at slot entry**: v5.9.4 roadmap pinned the TS
acceptance cluster at 9 scripts; empirical at slot entry only
6 fit the uniform "compile each TS heredoc with `cc5
--parse-ts`, all must exit 0" shape. ts-lex uses a different
mode flag (single-fixture `--lex-ts`) and was a one-off port
this slot. ts-parse + ts-parse-tsx walk an external SY corpus
with a pass-count threshold (deferred to v5.9.8 — the corpus
walker is its own helper-design step). Honest scope shrink:
9 conversions instead of an originally-projected ~12.

**What also shipped**: helpers `_count_substr_buf`,
`_cyrlint_count_marker`, `_exec_with_arg_capture_both`
(stdout+stderr variant of v5.9.6's `_exec_with_arg_capture`),
plus the parameterized `_ts_mode_run(fixture, mode_flag)` so
`_parse_ts_dir_gate` and `_ts_lex_gate` share one fork+exec
implementation. 11 new fixture sub-directories under
`tests/fixtures/`. 60 → 50 → 38 → 37 → 28 .sh remaining
across v5.9.2 + v5.9.3 + v5.9.6 + v5.9.7.

**Verification**: 66/66 check.sh green pre- and post-deletion;
cc5 self-host byte-identical (no compiler-source change);
38 TS fixtures smoke under `--parse-ts`; ts-lex 130-line
fixture smoke under `--lex-ts`; cyrlint regressions
(forward_refs → 3 warnings, string_literal_safe / lib/math /
lib/string → 0 warnings, 7008-line synthetic → 0 file-size
false-positives).

**Next**: v5.9.8 — sovereignty pass batch 3b/3. Earned
categories remaining: ts-parse + ts-parse-tsx (external SY
corpus walker + threshold check), shared-library cyrius-side
test (lib/dynlib.cyr / lib/fdlopen.cyr consumer), cross-host
SSH gates (8 scripts: aarch64-syscalls,
aarch64-native-selfhost, macho-exit, pe-exit, sit-status,
tls-live, aarch64-f64, aarch64-f64-polyfill — needs
`_ssh_skip_check(target)` helper + cyrius-side scp/ssh
fork-exec wrappers), plus ~17 remaining bespoke. v5.9.9+
inherits from the v5.9.6 roadmap.)

**5.9.6** (shipped 2026-05-06 — **v5.9.x SLOT 6 — testsuite-
gate fix chain + args regression harness + 1 conversion**. The
v5.9.5-pinned `_testsuite_gate "0 files"` audit unraveled into
three stacked bugs in `lib/fs.cyr` + `programs/check.cyr`,
each masking the next: (1) `dir_list` pushed borrowed
filename pointers into a getdents64 batch buffer that
overwrote on the next outer-loop iteration → all post-first-
batch entries silently corrupted; (2) `path_has_ext(path,
ext)` delegated to `str_ends_with(Str, Str)` but check.cyr
called it with a cstring literal `.tcyr` — `str_ends_with`
read junk past the literal as the suffix length, making every
comparison silently false; (3) once #1 and #2 were fixed and
the gate actually iterated, `_tcyr_compile_and_run` (sibling
code-path to the v5.9.2 `_tcyr_relay_gate` fix) tripped the
same orphan-setuid pipe deadlock on `shadow_pam.tcyr`. All
three landed this slot. cc5 unchanged at **741,048 B** —
`lib/` + `programs/` work; the compiler binary is not touched.

**Premise-check at slot entry**: the "0 files" report looked
like a one-line printf bug. It was actually a chain of three
real bugs hiding behind it. The fix-cascade was discovered by
applying #1, re-running, finding #2, applying #2, re-running,
finding #3 (which the gate had been masking from v5.9.2
onward — the testsuite-gate path missed the v5.9.2 capture
migration because it never iterated to the deadlock site).

**What also shipped**: (a) `_exec_with_arg_capture(bin, arg,
buf, buflen)` helper for argv-shape regression gates; (b)
`_args_init_4kb_gate()` for cyim BUG-001 (fixed v5.9.5) —
8 KB synthetic arg → `argc() == 2` post-fix; pre-fix returned 1.
Audit total 65 → 66. (c) `tests/fixtures/argc_print.cyr`
minimal fixture. (d) `_struct_cap_gate()` + helper
`_gen_struct_decls_source(path, n)` — converted
`regression-struct-cap.sh` (v5.7.17 kybernet-class fix).
3/3 sub-cases (80-struct compile+run+exit-0, 200-struct
compile clean, 257-struct overflow with diagnostic substring
matches). 60 → 50 → 38 → 37 .sh remaining across v5.9.2 +
v5.9.3 + v5.9.6.

**Verification**: 66/66 check.sh green; testsuite-gate now
actually iterates 128 .tcyr files (all PASS); cc5 self-host
byte-identical; args_init regression smoke (8 KB arg →
argc=2, was 1 pre-v5.9.5).

**Roadmap pin (NOT fixed this slot)**: tcyr-relay gates from
v5.9.2 (shadow_pam / fdlopen / thread_local / atomics /
thread_safety / flags + json_pretty / json_stream /
json_pointer / test_lib expected-output gates) now run twice
per audit — once as named relay gates, once via the
now-actually-walking testsuite-gate. Relay gates have richer
output ("N assertions") so removing them costs UX
granularity; cleanup decision deferred to v5.9.x closeout.

**Next**: v5.9.7 — sovereignty pass batch 3/3 (cross-host SSH
gates + TS acceptance cluster + shared-library cyrius-side
test) continues from where v5.9.3 left off; remaining 36
`tests/regression-*.sh` queued.)

**5.9.5** (shipped 2026-05-06 — **v5.9.x SLOT 5 — two consumer-
filed bug fixes**. Both surfaced 2026-05-06 with detailed
reproducers + suggested fixes from downstream repos.

(1) cyim BUG-001: `lib/args.cyr` `args_init()` read
`/proc/self/cmdline` into a 4096-byte stack buffer; argv > 4063
bytes truncated silently and `argc()` undercounted. Linux
ARG_MAX is 2 MB — the cap rejected ~99.8% of valid argv. Fixed
by switching to `alloc(2097152)` heap-backed buffer. Verified
locally: 8192-byte arg → `argc() == 2` post-fix (vs `argc() == 1`
pre-fix).

(2) agnosys 1.1.0 blocker: `src/frontend/lex_pp.cyr`'s derive
emitter shared one 4 KB heap region for both per-struct tables
([32] cap) AND shared parse-state buffers, with overlapping
extents — struct_names[31] reached past the op slot at 0x197400,
and the 33rd struct's size store at 0x197008 + 32*8 = 0x197108
overwrote struct_names[0]'s first 8 bytes. Two surface modes:
clean truncation (33rd struct's accessors silently fail to
register; binary SIGILLs at runtime when the missing accessor is
reached) and prefix corruption (struct[0]'s name first 8 chars
overwritten, e.g., `update_state_X` emitted as `tate_X`). Fixed
by reshuffling the 0x197XXX layout: per-struct tables move to
the high half (0x197500..0x197F00) entirely separate from
shared parse-state in the low half (0x197008..0x1974E0). Cap
raised 32 → 64. All ~109 offset references in lex_pp.cyr
updated via two-step token swap; external callers
(src/main.cyr, src/main_win.cyr, src/common/util.cyr) only
touch 0x197000 and 0x197F00, both unchanged. Verified against
the agnosys reproducer at `/tmp/cyrius-derive-truncation/`:
threshold probe N=28..36 reports 0 undefined-fn warnings
post-fix (pre-fix: 0,0,0,0,0,1,1,2,2); the 37-struct
minimal_repro builds clean and runs to exit 0 (pre-fix: 12+
undefined-fn warnings, SIGILL exit 132). Added
`tests/tcyr/derive_cap.tcyr` (36 derive structs across the
pre-v5.9.5 cap, 9 assertions) as the regression floor.

cc5: **741,048 B unchanged** — heap-layout reshuffle, no
code-size change. Two-step self-host byte-identical.

**Premise-check at slot entry**: both bugs filed with full
reproducers + suggested fixes, so the slot's ambiguity was
bounded — investigate, confirm, implement, regression-test,
ship. The derive bug analysis revealed the root cause was BOTH
a fixed [32] cap AND a heap-region overlap (struct_names[23+]
overlapping with op at 0x197400), so the fix had to address
both in the same reshuffle. Cap-only-bump would still leave
struct_names[39+] overlapping op in the new range, so clean
separation was the right call.

**Verification**: check.sh 65/65 green; cyrius test 104/104
including new derive_cap.tcyr (9 assertions); cc5 self-host
byte-identical; both consumer reproducers re-checked locally
post-fix.

**Roadmap pins (NOT fixed this slot)**: (a) args_init >4 KB
arg regression test earned its own slot — needs a CLI-arg-
passing harness; deferred alongside batch 3/3. (b) check.sh
`_testsuite_gate` reports "0 files" (pre-existing; predates
v5.9.5); cyrius test discovers them fine, so test coverage
isn't lost — but the dispatcher's duplicate walk earns a
separate fix slot.

**Next**: v5.9.6 — sovereignty pass batch 3/3 (cross-host SSH
gates + TS acceptance cluster + shared-library cyrius-side
test) + args_init regression harness. v5.9.7+ inherits from
the v5.9.4 roadmap.)

**5.9.4** (shipped 2026-05-06 — **v5.9.x SLOT 4 — CI hotfix +
`cyrius audit` review pin**. Post-v5.9.3 push surfaced a CI
failure: `.github/workflows/ci.yml`'s `Test (ubuntu)` job
invoked `sh tests/regression-object-init.sh` and
`sh tests/regression-linker.sh` directly — both retired in
v5.9.3 into `programs/check.cyr` dispatcher fns, breaking the
direct-invocation steps. cc5 unchanged at **741,048 B** — slot
is `.github/` + docs only. **Premise-check at slot entry**:
`grep -rn "regression-" .github/workflows/` returned 4
direct invocations in `Test (ubuntu)`; 2 were retired in
v5.9.3 (object-init, linker) → BROKEN; 2 still ship as
standalone .sh (shared, capacity) → still work. Same lesson as
the v5.8.31 docs-deletion incident (memory pin
`feedback_archive_dont_delete_docs`): grep `.github/workflows/`
before deleting any file the dispatcher consolidated.
Memory-pin extended this slot to cover test scripts, not just
docs. **What shipped**: ci.yml's two broken steps replaced
with inline equivalents — `_cyrius_init STB_GLOBAL` step uses
inline heredoc + `readelf -s` + awk Bind extraction;
`cyrld multi-module link` step uses the v5.9.3
`tests/fixtures/linker/{a,c,d,m}.cyr` fixtures directly,
compiles via cc5, links via cyrld, runs both binaries, checks
exit codes 43 / 44. No dependency on retired .sh files. Both
verified locally via mirror-of-CI-step shell execution.
**Roadmap pin (NOT fixed this slot)**: `cyrius audit` broken
outside the cyrius repo — `cbt/commands.cyr:415` `cmd_audit()`
invokes `~/.cyrius/bin/check.sh` which doesn't exist (check.sh
not in `[release].scripts`); `run_tool` validates only
`/bin/sh`, never the script arg. Two open design questions
waiting on user direction; earmarked for v5.9.8+ once the
design call lands. v5.9.5 inherits batch 3/3 of the
regression-*.sh conversion arc (shifted from v5.9.4 to
accommodate this hotfix slot). **Next**: v5.9.5 — sovereignty
pass batch 3/3 (cross-host SSH + TS acceptance + shared-library
cyrius-side test).)

**5.9.3** (shipped 2026-05-06 — **v5.9.x SLOT 3 — sovereignty
pass: tests/regression-*.sh batch 2/3 (12 conversions, 50 → 38
scripts)**. Second batch of the 60-script `tests/regression-*.sh`
conversion arc. cc5 unchanged at **741,048 B** — slot is
`programs/` + `tests/` work; the compiler binary is not touched.
**Premise-check finding at slot entry**: the remaining 50 scripts
clustered into uneven shapes — only 1 cluster (3 stderr-diagnostic
gates) earned a helper template; everything else needed a one-off
dispatcher fn. Pragmatic ceiling 12 conversions before
per-script porting cost outpaced aggregate value. Cross-host
SSH gates (8 scripts), TS corpus / acceptance cluster (9
scripts), and the C-harness shared-library test (1 script)
deferred to v5.9.4. **What shipped**: 1 helper template
(`_stderr_match_subcase` + `_compile_capture_stderr`); 7 generic
helpers (`_exec_run_clean`, `_compile_run_get_exit`,
`_link_objects_invoke`, `_file_contains_substr`,
`_find_bytes`, `_doc_parse_undocumented`, plus dispatcher's
`CYRDOC_PATH` resolver); 12 bespoke gate fns each replacing one
.sh script (aarch64-codebuf-cap source-grep, macho-cross-build
ELF-magic, object-init native ELF symbol-table parse, truthy-after-
fncall 2-sub-case, input-1mb synth-source, fn-collision /
reserved-kw-diag / string-escapes stderr-grep clusters, stdlib-
doc-coverage cyrdoc-walk, linker cyrld-multi-module, cyrfmt-
comment-braces idempotency, kmode-emit-order byte-offset
search); 11 fixture files in 3 new `tests/fixtures/` sub-dirs
(truthy, linker, cyrfmt_braces). Acceptance: 65/65 check.sh both
pre- and post-deletion; cc5 self-host byte-identical. **Surfaced
but NOT fixed this slot**: `cyrius audit` from outside the
cyrius repo prints a raw sh "no such file or directory" and
exits 127 because check.sh isn't in `[release].scripts` (so
`~/.cyrius/bin/check.sh` doesn't exist) and `run_tool`
validates only `/bin/sh` not the script arg. Two open
design questions surfaced to user; earmarked for a follow-up
slot. **Next**: v5.9.4 continues with the SSH cross-host gates
+ TS acceptance cluster + shared-library cyrius-side test.)

**5.9.2** (shipped 2026-05-06 — **v5.9.x SLOT 2 — sovereignty
pass: tests/regression-*.sh batch 1/3 (10 conversions, 60 → 50
scripts)**. First batch of the 60-script `tests/regression-*.sh`
conversion arc pinned in v5.9.1's roadmap. cc5 unchanged at
**741,048 B** — slot is `programs/` + `tests/` work; the compiler
binary is not touched. **Premise-check finding at slot entry**:
the v5.9.1 commit 69603ae shipped one helper (`_tcyr_relay_gate`)
plus 6 `_gate()` conversions but never ran the result end-to-end
— two prereq bugs surfaced when this slot first ran the dispatcher
through the converted gates: (a) `_tcyr_relay_gate` used
`exec_capture` (pipe-based) and the `shadow_pam.tcyr` test binary
forks `unix_chkpwd` (setuid root, reparented to init as an orphan)
which kept the pipe write-end open after the test binary exited,
deadlocking read-to-EOF; (b) `_tcyr_parse_failed` had a
control-flow bug in its digit-walkback loop that infinite-looped
on every PASS path (the byte before " failed" being a digit, e.g.
`0 failed`). Both fixed in this slot's commit-through. **What
shipped**: `_tcyr_relay_gate` + `_expected_output_gate` helpers
in `programs/check.cyr` + new `_exec_capture_clean(bin, buf, cap)`
private capture helper (file-based, stdin/stderr to /dev/null,
waits only on the direct child so orphan grandchildren can't
deadlock the read); 4 fixture pairs in new `tests/fixtures/`
directory (json_pretty, json_stream, json_pointer, test_lib —
each `.cyr` source + `.expected` cmp target); 10 `_gate()` calls
converted (6 tcyr-relay + 4 expected-output); 10
`tests/regression-*.sh` files retired
(60 → 50 remaining); **`scripts/release-lib.sh` packaging fix**
(walk lib/ recursively so lib/unicode/*.cyr lands in the release
tarball — surfaced by cyim against the v5.9.1 tarball; mirrors
the v5.8.49 fix in install.sh's --refresh-only path). Acceptance:
65/65 check.sh both pre- and post-deletion; cc5 self-host
byte-identical; release-lib.sh smoke stages all 7
`lib/unicode/*.cyr` at `<dest>/unicode/`. **Next**: v5.9.3
continues with regression-*.sh batch 2/3 (next ~15-20 conversions).)

**5.9.1** (shipped 2026-05-06 — **v5.9.x SLOT 1 — sovereignty
pass kickoff: scripts/check.sh → cyrius**. First slot of the
v5.9.x bash-toolchain → cyrius conversion arc. cc5 unchanged at
**741,048 B** — slot is `programs/` + `lib/` work; the compiler
binary is not touched. **Premise-check finding at slot entry**:
roadmap pin estimated check.sh at 200 LOC + audit-walk.sh at 80
LOC; empirical was **743 LOC for check.sh** (3.7× pin) and
audit-walk.sh has a second consumer (bash `scripts/cyrius`
dispatcher, queued for v5.9.5). Slot scope-corrected to check.sh
only; audit-walk.sh stays bash and pairs with `scripts/cyrius`
in v5.9.5. The fmt/lint walk logic was simultaneously ported into
a new cyrius stdlib module (`lib/audit_walk.cyr`) so
`programs/check.cyr` doesn't reach back into bash. **What
shipped**: `programs/check.cyr` (~700 LOC cyrius port of the
audit dispatcher; replicates self-host two-step, heap-map, .tcyr
loop, ~50 regression gates, format/lint walks; sovereign
fork+execve+wait via lib/process.cyr; environ passthrough via
`/proc/self/environ` — load-bearing because regression scripts
need HOME/PATH set), `lib/audit_walk.cyr` (cyrius stdlib walker
with self-contained getdents64 d_type extraction; 77 → 78
stdlib modules), `scripts/check.sh` collapsed to a ~30-line
shim that builds `build/cyrius_check` on demand and exec's it.
api-surface snapshot regenerated 2,760 → 2,763 public fns (+3
from `lib/audit_walk.cyr`; non-breaking). Acceptance: 65/65
check.sh; cc5 self-host two-step byte-identical; idempotent
rebuild from a clean `build/cyrius_check` deletion. **Next**:
v5.9.2 begins the regression-*.sh batch conversion (60 scripts /
6,679 LOC across .2–.4).)

**5.9.0** (shipped 2026-05-06 — **v5.9.x cycle opener — niyama
fold-in (sandhi-pattern)**. Eighth sibling distfile vendored
byte-identical into `lib/`. cc5 unchanged at **741,048 B** —
foldin is `lib/` content only; the compiler binary doesn't
include niyama. niyama 1.0.1 `dist/niyama.cyr` (6,664 lines,
sha256 `4f6bf9fd...4fe06a`) → `lib/niyama.cyr`; inlines all 7
niyama modules (posix_classes, unicode_props, bre, re2, pcre,
fuzzy, vim) covering the full regex-engine surface area cyim
threads through `--regex=<flavor>`. niyama ADR 0011 status:
**Triggered: 2026-05-06 via cyrius v5.9.0** — multi-consumer
gate met by cyim (#1) + queued AGNOS bare-metal kernel (#2,
v5.10.0). niyama 1.0.0 → 1.0.1 patch corrected a v1.0.0 dist
defect: the originally-shipped `dist/niyama.cyr` was a 108-line
`include`-manifest scaffold with unresolved `include
"src/*.cyr"` paths; v1.0.1 wired `[lib] modules = [...]` in
`niyama/cyrius.cyml` and regenerated via `cyrius distlib`
(canonical bundling tool). api-surface snapshot regenerated:
**2,725 → 2,760** public fns (+35 from niyama; all non-breaking).
Acceptance: 65/65 check.sh; cc5 self-host two-step byte-
identical; niyama smoke (`niyama_re2_compile + niyama_re2_search`)
links and runs from the vendored stdlib path. v5.9.x cycle
theme proceeds with sovereignty pass (bash → cyrius) per
roadmap pin.)

**5.8.65** (shipped 2026-05-05 — **v5.8.x SLOT 65 — stdlib foldin
(sandhi-pattern)**. Twenty-seventh slot of Phase 3. cc5 unchanged at
**741,048 B** — foldin is dep-resolution + manifest work only.
Six sibling distfiles vendored byte-identical into `lib/` from their
patched tags (sakshi 2.2.3, patra 1.9.3, sigil 3.0.1, vani 0.9.2,
yukti 2.2.2, sankoch 2.2.4 — out-of-band patched against cyrius
5.8.64 in topological order). `[deps.X]` sections removed from
cyrius.cyml for all 6; `[deps.mabda]` retained per user direction
("sans mabda" — 3.0.0-rc.2 not GA, Class B FFI work deferred to
v5.9.x). Decision NOT to add the 6 to `[deps].stdlib` auto-prepend
list — all cyrius tcyrs that reference dep symbols already use
explicit `include "lib/<dep>.cyr"`; auto-prepending ~28 KLOC of
folded code to every consumer's preprocess_out would risk the
v5.8.60-tested 2 MB cap. Sandhi precedent (v5.7.0) followed —
explicit-include only. **Mid-slot fix-up**: first push committed
the 7 folded files (sakshi/patra/sigil/vani/yukti/sankoch/agnosys)
as absolute-path symlinks into the user's local cyrius-deps cache
(`/home/macro/.cyrius/...`); on Ubuntu CI those symlinks dangled
(home is `/home/runner/...`), tcyr loop hit `sakshi.tcyr`, cc5
preprocessor file-not-found, `bash -e` killed the shell silently.
Diagnosed from CI raw log; same-slot fix re-pushed: (1) symlink →
regular-file conversion for the 7 vendored deps (matching the
v5.7.0 sandhi precedent — `lib/sandhi.cyr` is mode 100644, never a
symlink); (2) `scripts/lib/audit-walk.sh` `_aw_is_distlib_bundle`
extended to recognize sakshi's `# Bundled distribution of` header
in addition to the `# Generated by: cyrius distlib` cyrius-distlib
marker. mabda stays a symlink (still in `[deps]`; `cyrius deps`
regenerates it on every machine). Acceptance: 65/65 check.sh; 127
tcyr files PASS (320,874 unicode asserts unchanged); cross-host
pi/cass/ecb green; `audit_fmt_walk` skipped 9 dep files (was 8;
+sakshi via the new marker).)

**5.8.64** (shipped 2026-05-05 — **v5.8.x SLOT 64 — cycle closeout
pass** per CLAUDE.md 11-step protocol. Twenty-sixth slot of Phase 3.
cc5 unchanged at **741,048 B** — closeout is audit + docs only, no
source code change. **§1-3 Mechanical**: self-host byte-identical,
bootstrap closure clean, check.sh 65/65 + cross-host pi/cass/ecb
green. **§4 Heap**: 84 regions, 0 overlaps, monotonic; 8.4 MB of
closeable gaps pinned for pre-v6.0 hardening. **§5 Dead-code**: 32
fns / 22,571 B floor stable since v5.8.56; all retained per
mode-flag-reachable rule. **§6-8**: refactor consolidations
absorbed in cycle (.55-.57, .61-.63); 1 TODO retained (cx
ESTORESTACKPARM, held); no orphans. **§9 Security**: quick scan
clean; full audit pinned for v5.9.x. **§10 Downstream**: 6 fold-
target deps (sakshi/patra/sigil/vani/yukti/sankoch) inventoried at
5.7.48 pin — work-list captured for out-of-band patch round before
.65; mabda excluded per user direction. **§11 Docs**: CHANGELOG/
roadmap/state.md/completed-phases.md synced; v5.8.0-.63 migrated to
completed-phases.md (94 lines, sub-arc grouped); vidya refresh
tracked as out-of-band. **Cycle summary**: 64 patches across 5 days
(2026-05-01 → 2026-05-05); cc5 720,928 → 741,048 B (+20,120 B /
+2.79%); check.sh 64 → 65 gates; tcyr 108 → 127 files; unicode
asserts 0 → 320,874 covering NFC/NFD/NFKC/NFKD. **Next**: out-of-
band sibling-dep version-patch round, then v5.8.65 stdlib foldin,
then v5.8.66 release-valve. Backstop hard at .66.)

**5.8.63** (shipped 2026-05-05 — **v5.8.x SLOT 63 — refactor pass B:
main_*.cyr boilerplate extraction**. Twenty-fifth slot of Phase 3.
Two-step bootstrap slot. cc5: 741,128 B → **741,048 B (-80 B)** —
inlined heap-zero sequence (~30 S64 calls) in each main_*.cyr
collapses to a single `call _HEAP_INIT_SCRATCH` instruction.
cc5_aarch64: 439,880 B → **440,008 B (+128 B)** — helper body
lives once in .text. Net source: **-162 LOC** (removed 237 lines
of init-block duplication across 6 main_*.cyr; added 75 lines for
the helper + header in src/common/util.cyr). New helper
`_HEAP_INIT_SCRATCH(S)` writes the SUPERSET of all init blocks
(compiler state + IR state + global-var-init + module-system
slots), with two sentinel-value exceptions preserved
(0x18FCB0 = -1 last_var sentinel, 0x18FCB8 = 1 cur_line). Cmdline
parser extraction deferred — exists only in main.cyr + main_win.cyr
(4 of 6 mains skip cmdline parsing entirely), variant differences
(--lex-ts/--parse-ts flags + #ifdef CYRIUS_TARGET_LINUX guard)
make clean shared helper awkward. 65/65 check.sh; 127 tcyr files
PASS; cross-host pi/cass/ecb green via existing SSH wiring;
heapmap unchanged at 84 regions monotonic.)

**5.8.62** (shipped 2026-05-05 — **v5.8.x SLOT 62 — refactor pass A:
lib/ structural cleanups + stale-comment sweep**. Twenty-fourth slot
of Phase 3. cc5 unchanged at **741,128 B** — no byte-identity risk
(lib/ moves don't reach cc5; src/ edits this slot are all comments).
Per user direction at v5.8.61 ship: "lets push final closeout to
.63; .62 is focused on refactors ... lets look at src and lib to see
where we could improve the structure". Closeout cascaded forward
once more at .62 entry per "main_ boilerplate extraction should be
.63 with .64 closeout". Delivered: (1) `lib/vidya.cyr` →
`programs/vidya.cyr` (helper-program, not stdlib; 24 `vidya::`
symbols removed from `docs/api-surface.snapshot`; 3 tcyrs rewired);
(2) stale-comment sweep in src/main_*.cyr (~50 LOC of v5.8.46/.59/
.60/.61 brk-extension narratives trimmed across 6 files; the
`(was str_data, ...)` 4-line annotation collapsed to a single line);
(3) main.cyr heap-map block header refreshed (last-audit ref bumped
to v5.8.61, section-grouping-vs-offset-order note added upfront,
str_data section trimmed 22→14 lines); (4) audits — `str.cyr` /
`string.cyr` / `ws.cyr` / `ws_server.cyr` already self-document the
split intent, no action; `lib/hashmap_fast.cyr` annotated
experimental + zero-consumers, pinned for pre-v6.0 hardening sweep
re-evaluation. Out of scope: syscalls_*.cyr / alloc_*.cyr per-arch
splits stay split (intentional per their headers; merging would
re-introduce the v5.4.10 yukti aarch64 portability regression);
main_*.cyr boilerplate extraction (`_HEAP_INIT_SCRATCH(S)` +
`_PARSE_VERSION_FLAGS()`) deferred to v5.8.63 (changes cc5 byte
size; needs its own two-step bootstrap audit). 65/65 check.sh; 127
tcyr files PASS; cross-host pi/cass/ecb green via existing SSH
wiring; install snapshot now 83 stdlib files (was 84 — vidya
removed); api-surface snapshot 2726 public fns (was 2750).)

**5.8.61** (shipped 2026-05-05 — **v5.8.x SLOT 61 — heap-map
monotonic reorganization**. Twenty-third slot of Phase 3.
Two-step bootstrap slot. cc5 unchanged at **741,128 B** — pure
offset relocation; same hex literal widths. **Layout is now
monotonic from input_buf at `0x00000` through brk-final at
`0x4E8C000`.** str_data folded from the v5.8.59 high-block
(`0x4E8C000`) back into the var_enum_id..preprocess_out gap at
`0x21A000..0x41A000`; brk shrinks `0x508C000` → `0x4E8C000`
(-2 MB mmap reservation); Windows MMAP shrinks `0x5100000` →
`0x5000000`. Picked minimum-blast-radius reorg (~80 edits)
over full reorg (~800 edits) per user direction "minimum blast
is probably the safer bet to allow for some potential bumps in
the future without a full restructure ... should be something
we consider as a last minor effort before 6.0". Remaining 8.4
MB of closeable gaps (output_buf-to-struct_ftypes 6 MB +
struct gaps) pinned forward to a pre-v6.0 hardening slot.
65/65 check.sh; 127 tcyr files PASS including 320,547
unicode_normconf asserts; `tests/heapmap.sh` 84 regions clean
0 overlaps 0 warnings; cross-host pi/cass/ecb green via existing
SSH wiring.)

**5.8.60** (shipped 2026-05-05 — **v5.8.x SLOT 60 — Unicode 17.0.0
NFKC + NFKD compatibility normalization**. Twenty-second slot of
Phase 3. cc5 unchanged at **741,128 B** — pure stdlib + data work,
no compiler change. K-forms originally pinned with v5.8.51 deferred
per the str_data cap; v5.8.59 raised the cap, this slot fills the
room. Mid-slot pivot from fixed-width 116-char compat encoding (445
KB) to 2-table split (sorted IDX + variable-width DATA blob, ~87 KB
total) when fixed-width hit the **preprocess_out 2 MB cap** —
histogram shows 70% of compat decomps are 1-cp so fixed-width
padded ~100 chars of zeros per record. `lib/unicode/normalize.cyr`
gets `NFKC=2` / `NFKD=3` enum variants + new public fn
`unicode_compat_decomp` + new private fn
`_uc_decompose_cp_recursive_compat`; `str_normalize` dispatch
selects compat vs canonical decomp by form, reuses canonical
composition pass for both NFC + NFKC per UAX #15 §1.3. Test surface
expanded: `unicode_normalize.tcyr` 83 → 99 asserts (+16 K-form
unit tests covering ligatures, full-width, super/subscript, Roman
numerals, NBSP→SPACE, U+FDFA 18-cp ligature); `unicode_normconf.tcyr`
auto-discovers cols 4-5 of NormalizationTest.txt — 6 asserts/row →
**16 asserts/row**, **320,547 conformance asserts PASS** (was
120,207). 65/65 check.sh; cross-host pi/cass/ecb green.)

**5.8.59** (shipped 2026-05-05 — **v5.8.x SLOT 59 — `str_data`
heap-region bump for Unicode compat-only decomposition**.
Twenty-first slot of Phase 3. Two-step bootstrap slot per CLAUDE.md
"Two-step bootstrap for heap changes". cc5: 741,120 B → **741,128
B** (+8 B for wider cap-value digits). `str_data` 256 KB → 2 MB
(8x, proportional to v3.6.9's 32KB→256KB jump); cap was the
v5.8.51 NFKC/NFKD blocker. Layout option B chosen — relocate
str_data to high block at `0x4E8C000` (above tok_lines), brk →
`0x508C000` (~80.5 MB), Windows MMAP → `0x5100000`. ~50 edits
across 13 files. Heap-map refactor pinned forward to a pre-closeout
slot to reorganize the gap left by the high-block relocation.
Two-step verify: cc5 (old layout) → cc5b (new) → cc5b' = cc5b
byte-identical at 741,128 B. 65/65 check.sh gates green; 127 tcyr
files PASS including 120,518 unicode asserts; cross-host gates
pi/cass/ecb green via existing SSH wiring.)

**5.8.58** (shipped 2026-05-04 — **v5.8.x SLOT 58 — deps cleanup
+ release-valve**. Twentieth slot of Phase 3. cc5 unchanged at
**741,120 B** — no compiler change. All 8 `[deps.*]` pins audited
at latest GA (zero bumps needed). Release-valve absorbed
sovereignty audit (~10,800 LOC bash; pinned forward as v5.9.0
cycle theme — "Sovereignty pass — bash-toolchain conversion to
cyrius"). state.md refresh shipped after 10-slot silent rot since
v5.8.47.)

**5.8.57** (shipped 2026-05-04 — **v5.8.x SLOT 57 — sovereign UCD
generator**. Nineteenth slot of Phase 3. Last of three audit/
refactor slots (.55 codec dedup → .56 dead-code → **.57 sovereignty
fix**). cc5 unchanged at **741,120 B** — stdlib-tooling work, no
compiler delta. Native `programs/gen_unicode_data.cyr` (~640 lines)
replaced retired `scripts/gen-unicode-data.py` (~640 lines of
Python carried since v5.8.49 across the Unicode arc); UCD source
files committed at `tests/data/ucd/*.txt` for hermetic regen; all
3 generated `lib/unicode/_*_data.cyr` files byte-identical to
Python output (data portions). Project zero non-cyrius general-
logic code now (only sovereign-allowed: bash bootstrap glue,
ABI-shim `programs/dlopen-helper.c`, IDE integrations
`editors/*.lua` + `editors/*.js`). 120,518 unicode asserts hold
at the regression floor v5.8.52 set.)

**Cycle CLOSED at v5.8.65** (2026-05-05). The held-open v5.8.66
release-valve retired unused — foldin fallout (Ubuntu CI symlink-
dangling + audit-walk distlib-bundle marker missing sakshi's
bundle.sh header) was absorbed in v5.8.65 itself via mid-slot
fix-ups (three pushes: initial foldin, audit-walk + symlink-revert,
ci.yml inline-marker fan-out). With foldin clean at .65, the valve
had nothing to absorb. Mirror of the v5.7.50 P(-1) unblock pattern
except the unblock happened in-slot rather than needing its own
patch. **65 patches across 5 days (2026-05-01 → 2026-05-05)** —
the longest minor in cyrius history by patch count, more
compressed than v5.7.x's 51-patch / 36-day cycle. Next: v5.9.x —
bare-metal arc + RISC-V port + sovereignty pass.
Backstop history: was .55 pre-Unicode-pin → .57 to absorb
v5.8.51-deferred heap bump + K-forms → .59 for cross-arch
propagation slots → .61 to absorb the audit/dedup/refactor trio
→ .62 to absorb the heap-map reorg as its own dedicated slot →
**.64** at v5.8.62 entry 2026-05-05 per user direction "main_
boilerplate extraction should be .63 with .64 closeout ... clean
separation of tasks in this instance since its a cleaning up
refactor".

**v5.9.0 cycle theme pinned forward** (from v5.8.58 audit
2026-05-04): **Sovereignty pass — bash-toolchain conversion to
cyrius**. v5.8.x retired Python in one shot at .57; the remaining
sovereignty debt is ~10,800 LOC of bash across `scripts/` (3,885
LOC), `tests/regression-*.sh` (60 scripts, 6,679 LOC),
`benches/` (75 LOC), `tests/heapmap.sh`. Bootstrap (`bootstrap/
bootstrap.sh` + `verify.sh`, 133 LOC) and the dispatch shim
(`scripts/cyrius`, 30 LOC) stay bash by intrinsic necessity (run
before cyrius exists / before cyrius is on PATH). v5.9.0 ports
the convertible bulk; v5.9.x continues with bare-metal arc +
RISC-V port as originally pinned.

### Historical Version narratives (pre-v5.8.48)

**5.8.47** (shipped 2026-05-03 — **v5.8.x SLOT 47 — starship +
p10k prompt color split AND vidya cyrius-language audit**. Ninth
slot of Phase 3. cc5 unchanged at **741,040 B** — no compiler
change; Part A is shell-script edits, Part B is vidya `.cyml`
content + one new local issue file. **Part A** (starship/p10k
color refresh): edited `scripts/cyriusly`'s `_CYRIUS_STARSHIP`
+ `_CYRIUS_P10K` heredocs to differentiate the package side
(ॐ Om → forestgreen `#228B22` TEXT) from the toolchain side
(🌀 cyclone → light blue `#87CEEB` TEXT). Pre-fix both shared
`bg:teal` / `fg:base` and visually collapsed; the slot's
first-pass attempt (mid-session) put color on the bg with
contrasting white/black text — corrected after user feedback
("not the background the text"). p10k uses 256-color foreground
codes (-f 28 / -f 117) for the same split. Divider `" | "`
retained between segments since there's no bg fill to act as a
visual separator. Acceptance gate run: `scripts/cyriusly cmdtools install
starship` re-installed cleanly via the existing purge-then-write
path; `cyrius-prompt-info pkg` returns `5.8.46 (cyrius)` and
`cyrius-prompt-info tool` returns `5.8.46`, both rendering in
the new colored segments. **Part B** (vidya audit of ~20K lines
across 33 cyml files; 35 entries in field_notes/language/
alone): **3 entries flipped to ✅ FIXED** with status paragraph
at body top + PRE-FIX text preserved for pre-v5.8.x toolchain
users — `global_init_order_silent_zero` (FIXED v5.7.32 cyrlint
warning + v5.7.36 string-lit awareness; description was stale
even though body said "Shipped at v5.7.32"),
`no_var_redecl_same_scope` (empirically FIXED in v5.8.x;
sibling if/elif `var buf` redecl now compiles), and
`multi_line_struct_enum_bodies_dont_parse` (empirically FIXED
in v5.8.x, likely as side-effect of v5.8.21+ sum-type cluster).
**3 entries refreshed** for stale cap/version refs —
`the_gvar_wall` (cap moved 256 → 1024 entries),
`the_256kb_ceiling` (output_buf moved 256 KB → 2 MiB at
v5.6.43), `the_preprocessed_line_number_problem` (still active
at v5.8.46; partial mitigation infra exists but errors still
emit preprocessed-stream line numbers). **1 new local issue
filed** at
`docs/development/issues/2026-05-03-parser-cosmetic-limits-bare-return-and-var-bracket.md`
covering the two confirmed-still-active parser cosmetic limits
(`bare_return_in_if_block_rejected` + `var_bracket_size_must_be_literal`),
both vidya entries cross-referenced. **Stale-pin streak now 4
of 6 in v5.8.x cycle** — v5.8.45 (4-of-5 sweep stale),
v5.8.46-Part-A (18-of-18 op shapes already passing), v5.8.47
(3-of-6 vidya entries already FIXED by side-effect). Same root
pattern: parser/expression-grammar work between v5.8.20 and
v5.8.40 closed three separate vidya-tracked items without
anyone noticing until the audit. Pinned for v5.8.48: parser-
grammar widening slots should grep vidya field_notes/language/
for FIXED-by-side-effect entries. Verification: scripts/check.sh
65/65 PASS; cc5 self-host two-step byte-identical at 741,040 B
(no compiler delta this slot). v5.8.x cycle progress: **47 of
55 pinned slots shipped (85.5%)**; 8 slots remaining. Phase 3
remaining: refactoring + heap-map cleanups (v5.8.48 — also
absorbs v5.8.46-Part-B's heap-map sweep that surfaced the
tok_types/output_buf overlap), full closeout pass (v5.8.49),
deps cleanup (v5.8.50), release-valve (v5.8.51), Unicode 17.0.0
categories+normalization (v5.8.52-54), Unicode regression suite
+ final closeout (v5.8.55).)

**5.8.46** (shipped 2026-05-03 — **v5.8.x SLOT 46 — arithmetic-
in-fn-args regression-floor lock + token-array cap raised
262144 → 1048576 (sit v0.7.2 unblocked)**. Eighth slot of Phase
3. Two coherent deliverables landed in the same slot. **Part A**
closes the v5.8.34-filed arithmetic-in-fn-args pin (vidya
`audio_dsp` 11-lang port:
`biquad_set(a_q15, 0, 0, a_q15 - ONE, 0)` originally rejected
with generic `expected identifier, got unknown`) as a
regression-floor lock — the parser fix landed earlier in the
cycle as a side-effect of expression-grammar work
(`lib/assert.cyr:11` already comment-noted "Now that comparisons
work in function arguments, assert(x == 42, 'name') works"), but
neither the issue file nor the vidya field-note
`no_comparisons_in_fn_args` was refreshed; this part ships the
30-assertion `tests/tcyr/expr_in_fn_args.tcyr` test + vidya
audio_dsp port restoration (workaround removed; missing
`lib/syscalls.cyr` / `lib/vec.cyr` includes added; port had been
silently broken at compile time independent of the arithmetic
bug) + vidya field-note ✅ FIXED flip + issue file archived.
**Part B** closes the 2026-04-25-filed sit cap-overflow issue
(`docs/development/issues/archived/2026-04-25-cyrius-fixup-table-cap.md`,
sit-side; was conflated with the fixup-table cap that v5.7.7
already cleared — actual binding limit at sit's scale was
`src/frontend/lex.cyr:95` ADDTOK's separate token-array cap
that hadn't moved since pre-v5.7.1) — surfaced mid-slot when
the user named the sit issue file
("`@../sit/docs/development/issues/2026-04-25-cyrius-fixup-table-cap.md`
- sit cannot"). Two sub-deliverables per the issue's preferred
path: (B.1) ADDTOK diagnostic upgraded `error: token limit
exceeded (262144)` → `error: token limit exceeded: needed M,
cap is N` so future raises target empirical M (sit's
threshold-abort gave M >= 262145); (B.2) cap raised 4× to
1048576 + token arrays relocated from the
0x94A000/0xD4A000/0xF4A000 trio (each 2 MiB; tok_types
overlapped output_buf at 0x94A000 — undocumented v3.6.2
recycling) to fresh post-TS-region high block at
0x368C000/0x3E8C000/0x468C000 (each 8 MiB). Heap brk extended
in every main_*.cyr (main.cyr: 0x368C000 → 0x4E8C000;
main_aarch64/macho/native/cx: 0x290B000 → 0x4E8C000;
main_win.cyr MMAP: 0x2000000 → 0x5000000). Bridge.cyr NOT
touched (uses different bootstrap-chain offsets and its own
smaller cap; bridge only compiles cc5, well under 262K
tokens). cc5: 740,528 → **741,040 B** (+512 from v5.8.45's
`_TOK_IS_KERNEL(S)` inheritance + Part B's PRNUM call sequence;
Part A added zero compiler bytes). Self-host two-step
byte-identical. **Premise-check lesson** (folded into existing
memory pin `feedback_premise_check_at_slot_entry`): when a bug
points to a consumer workaround in a sibling repo, the right
test is **revert the workaround in the source repo and
recompile** — not synthesize a minimal program. Surfaced first
in Part A (vidya audio_dsp; user push-back: "won't look at the
repo that reported it... I forgot it was YOU IN THE REPO") and
applied immediately in Part B (sit) — same lesson, two
consecutive applications in one slot. **Slot-scope note**: Part
B was added to v5.8.46 (rather than cut as a fresh v5.8.47)
because v5.8.46 hadn't shipped yet — same fold-in pattern as
v5.8.45's `kernel_ident.tcyr` correction. The originally-pinned
v5.8.47 starship/vidya-audit slot stays at v5.8.47 (not yet
shipped, not displaced). Verification: 30/30 expr_in_fn_args
assertions pass; CI-shape `bash -eo pipefail` loop on 123 tcyr
= 123 passed; `scripts/check.sh` 65/65 PASS; vidya audio_dsp
port = 17/17 + zero warnings against the post-v5.8.46 cyrius
lib; **sit v0.7.2 builds (1,283,232-byte binary; was parked at
v0.7.1's ~709 KB) and sit `cyrius test` reports 127/127 PASS**
— the canonical end-to-end gate for Part B. v5.8.x cycle
progress: **46 of 55 pinned slots shipped (83.6%)**; 9 slots
remaining. Phase 3 remaining: combined starship/p10k color
refresh + vidya audit (v5.8.47), refactoring + heap-map
cleanups (v5.8.48 — note: v5.8.48's heap-map audit will absorb
the v5.8.46 Part B sweep that surfaced the
tok_types/output_buf overlap; pinned for v5.8.50 closeout to
add SOURCE FILE + LINE to cap-overflow diagnostics so future
cap-site drift is unambiguous), full closeout pass (v5.8.49),
deps cleanup (v5.8.50), release-valve (v5.8.51), Unicode 17.0.0
categories+normalization (v5.8.52-54), Unicode regression suite
+ final closeout (v5.8.55).)

**5.8.45** (shipped 2026-05-03 — **v5.8.x SLOT 45 — `kernel`
demoted from reserved token to plain ident**. Seventh slot of
Phase 3. Surfaced from vidya audio_dsp 11-language port at v5.8.34
(`fn fir_step(kernel, history, n_taps, x_new)` failed; `kernel`
was reserved as token 56 for AGNOS top-level mode-switch
`kernel;`). cc5 740,528 → **740,976 B** (+448 from new
`_TOK_IS_KERNEL(S)` helper). **Premise-check rejected the issue
file's "lexer-context-sensitive" framing**: bisection focused on
the underscore-in-fn-name axis turned out to be DCE-related, not
a real parser asymmetry. Non-underscored fns with no callers get
DCE-stub'd via `xor eax,eax;ret` without parsing the body, so
`fn ff(kernel)` "worked" only because the parser was skipped.
**Pin-bisection-sweep was 4-of-5 stale**: candidates `weights /
bias / tensor / layer` ALL parse cleanly — only `kernel` (the
real AGNOS keyword) was reserved. Same pattern as v5.7.44/45/46
(memory pin `feedback_premise_check_at_slot_entry`). **Fix per
preferred path** (issue + slot pin both said "allow as normal
identifier — common DSP/graphics/AI name"): demoted `kernel`
from token 56 to plain ident in lex.cyr; AGNOS top-level
`kernel;` now detected via new `_TOK_IS_KERNEL(S)` helper that
byte-compares the current ident's bytes (no L64 mask, so partial
prefixes like `kernels`/`kernel32` don't match). 12 dispatch
sites updated across 6 main.* files (2 per file: pass-1 mode-
switch + pass-2 skip). New tcyr `kernel_ident.tcyr` (4 assertions)
locks the regression floor — fn-param / underscored-fn-param /
single-arg / local-var. **Test rework caught pre-ship**:
initial draft wrapped logic in `fn main()` which cyrius
doesn't auto-invoke — binary exited 0 with no output and
local `check.sh` scored PASS while the assertions never ran.
CI surfaced it under `bash -eo pipefail` (the empty-output
grep for "N failed" returned nothing → pipeline exit 1 →
loop terminated after the prior test's `PASS:` line with no
diagnostic). Reworked to top-level form (`alloc_init();` →
`assert_eq` calls → `assert_summary()` → `syscall(60, ec)`)
matching `regalloc.tcyr` / `shadowing.tcyr`; now prints
`4 passed, 0 failed (4 total)` and genuinely locks the floor.
Pinned for v5.8.49 closeout: tighten `check.sh` to mirror
CI's pipefail so this divergence class can't reship. **AGNOS bootstrap re-verified**: agnos
kernel/agnos.cyr compiles cleanly through the new cc5; full agnos
build via cbt = byte-identical 249,080-byte kernel (cbt itself
unchanged, just consumes new cc5). **cbt-vs-cc5 install confusion
worth flagging**: I overwrote `~/.cyrius/bin/cyrius` (cbt
frontend) with `/tmp/cc5_new` (raw cc5) mid-verification and
agnos's `cyrius build` subcommand started failing — looked like
the demotion broke AGNOS but was just front-end confusion.
Restoring the original cyrius binary + compiling the agnos-prep
file directly with the new cc5 cleared it. To verify a downstream
that uses `cyrius build`, rebuild cbt with the new cc5 first —
don't replace the front-end with raw cc5. cc5 self-host
two-step byte-identical at 740,976 B; check.sh 65/65 PASS.
v5.8.x cycle progress: **45 of 51 originally-pinned slots shipped**
but cycle backstop **extended v5.8.51 → v5.8.55** to absorb
**Unicode 17.0.0 support** (https://www.unicode.org/versions/Unicode17.0.0/).
v5.8.x will be the longest minor in cyrius history — and that's
fine, the work fits the cycle better than starting v5.9.0 with
half-built Unicode infrastructure. Phase 3 remaining (10 slots):
arithmetic in fn args (v5.8.46), combined starship/p10k color
refresh + vidya audit (v5.8.47), refactoring + heap-map cleanups
(v5.8.48), full closeout pass (v5.8.49), deps cleanup (v5.8.50),
release-valve (v5.8.51), Unicode 17.0.0 categories+normalization
(v5.8.52-54), Unicode regression suite + final closeout
(v5.8.55).)

**5.8.44** (shipped 2026-05-03 — **v5.8.x SLOT 44 — api-surface refresh
+ auto-build wiring + null-byte-in-shell-substitution fix**.
Sixth slot of Phase 3. Three-part deliverable per the original
roadmap pin: (1) check.sh now build-on-demands cyrius_api_surface
if missing — pre-fix the gate had silently skipped since v5.7.50;
(2) off-by-one length literal in programs/api_surface.cyr (lines
337 + 350: "BREAKING: ...:\n" is 65 bytes; syscall length was 66
including the cstring's trailing \0; null byte in output triggered
shell warnings on command substitution); (3) snapshot regen via
`cyrius_api_surface --update` — 2563 → **2750 entries (+187)**
reflecting v5.7.x → v5.8.x stdlib growth (slice helpers + Result
+ Allocator `_a` variants + sandhi v1.1.0 fold + 10 typed-error
enums + alloc_via et al). cc5 unchanged at **740,528 B** (zero
compiler delta — fixes in tool source + check.sh wiring + snapshot
regen, none touch the cc5 binary). Gate now runs as a real PASS
not silent skip; 0 null-byte warnings; all 3 test cases green.
**Off-by-one byte counts in literals are a recurring foot-gun**:
cyrius's lack of compile-time `sizeof("string literal")` means
every `syscall(SYS_WRITE, 2, "literal", N)` site has a hand-
counted N. Pinned for future cleanup (a `strlen_const("...")`
compile-time helper would eliminate this entire bug class —
surface during v5.8.49 closeout refactor pass if it bites again).
**Lesson reinforced**: gates that "skip clean" can hide regressions
for many minors (api-surface gate orphaned since v5.7.50; same
pattern v5.8.41 caught for cyrlint large-file). Build-on-demand
fallbacks (now applied here + cyrfmt/cyrlint pattern from v5.7.36)
are the structural fix. Verification: self-host two-step
byte-identical, check.sh 65/65 (gate count unchanged — was
counted as PASS while silent-skipping, now actually validates).
v5.8.x cycle progress: **44 of 51 pinned slots shipped (86.3%)**.
Phase 3 remaining (7 slots): kernel reserved-word (v5.8.45),
arithmetic in fn args (v5.8.46), combined starship/p10k color
refresh + vidya audit (v5.8.47), refactoring + heap-map cleanups
(v5.8.48), full closeout pass (v5.8.49), deps cleanup +
post-release propagation (v5.8.50), release-valve (v5.8.51).
Cycle backstop hard at v5.8.51.)

**5.8.43** (shipped 2026-05-03 — **v5.8.x SLOT 43 — Phase 3 polish
absorber: stdlib Allocator migration pass 3 (peripheral cleanup)**.
Fifth slot of Phase 3. Absorbs the deferred-from-v5.8.35 + v5.8.36
peripheral _a variants — completes the v5.8.x Allocator-as-parameter
migration to ~100% stdlib coverage. Unblocks sandhi v1.1.0
dup-elimination work parked at sandhi-side.) **lib/str.cyr (9 new
fns)**: str_sub_a, str_trim_a, str_split_a, str_builder_new_a,
_sb_grow_a internal, str_builder_add_a, str_builder_add_cstr_a,
str_builder_add_int_a, str_builder_build_a. **lib/hashmap.cyr (3
new fns)**: _map_u64_grow_a internal, map_u64_new_a, map_u64_set_a.
**Migration status post-v5.8.43**: ~100% stdlib coverage —
45 `_a` variants + 10 typed-error enums across 11 stdlib modules
(io/json/toml/cyml/http/dynlib/pwd/grp/shadow/pam errors;
vec/str/hashmap/json/toml/cyml/http/sandhi `_a` variants). New tcyr
`alloc_stdlib_pass3.tcyr` — 33 assertions across 11 groups
(str_sub_a/str_trim_a/str_split_a bump+arena; full str_builder
lifecycle in arena: new→add→build→reset; str_builder OOM at first
grow; map_u64_new_a + map_u64_set_a bump+arena; map_u64_set_a
OOM at 12th-set grow trigger; back-compat unchanged). **Surfaced
bug filed**: `docs/development/issues/2026-05-03-str-split-sep-
treated-as-pointer.md` — pre-existing str_split bug where sep
parameter is treated as Str/cstr at API level but compared as
byte at impl level (load8 == sep never matches; always returns
1 part). Affects lib/process.cyr:214 cmdline parsing. v5.8.43
str_split_a preserves the existing broken behavior end-to-end
(out of scope for absorber); test assertions adjusted to reflect
actual state so the floor catches the fix when it lands. **Sandhi
unblock**: sandhi v1.1.0's `_sandhi_client_host_header_a` /
`_sandhi_wd_session_url_a` / `sandhi_json_build_a` use global
bump + dup pattern because v5.8.36 stdlib lacked str_builder_*_a.
v5.8.43 ships those variants; sandhi can drop the dup pattern in
v1.1.x or v1.2.0 (sandhi-side follow-up). cc5 unchanged at
**740,528 B** (zero compiler delta — pure stdlib addition).
**Process notes**: (1) doc-coverage gate caught 2 undocumented
fns (str_sub + str_builder_new lost leading comments when _a
variants were inserted between comment and fn body) — same v5.8.35
hashmap-fix pattern; lesson: when inserting variants between an
existing fn and its leading comment, MOVE the comment. (2)
map_u64 test originally started keys from 0 (MAP_U64_EMPTY
sentinel) → got 29/30 entries; adjusted to start from 1. Pre-
existing map_u64 contract. (3) Honest scope-shrink — str_split
bug NOT fixed in absorber; filed as new issue for future slot.
Per CLAUDE.md "ONE change at a time" + feedback_premise_check.
Verification: self-host two-step byte-identical, check.sh 65/65,
alloc_stdlib_pass3 33/33, all Phase 2 + Phase 3 prior tcyrs
regression-floored. v5.8.x cycle progress: **43 of 51 pinned
slots shipped (84.3%)**. Phase 3 remaining (8 slots): api-surface
refresh (v5.8.44), kernel reserved-word (v5.8.45), arithmetic in
fn args (v5.8.46), combined starship/p10k color refresh + vidya
audit (v5.8.47), refactoring + heap-map cleanups (v5.8.48), full
closeout pass (v5.8.49), deps cleanup + post-release propagation
(v5.8.50), release-valve (v5.8.51). Cycle backstop hard at v5.8.51.)

**5.8.42** (shipped 2026-05-03 — **v5.8.x SLOT 42 — paired UX/diagnostic
polish** (mabda A2 + mabda C1, combined per pin). Fourth slot of
Phase 3.) **Half (a) cyrius fmt --check exit code**: cbt's
cmd_fmt invoked `cyrfmt <file> --check` but cyrfmt parses --check
only at argv(1); with file at argv(1), _check_mode stayed 0,
cyrfmt fell through to format-to-stdout, exit 0 regardless of
drift. Drift detection silently broken via cbt wrapper; mabda's
CI gate never fired. Fix: swap run_tool args to put --check
FIRST (`run_tool(cyrfmt, "--check", file, 0)`). Now matches
Rust/Go: silent on no-drift, exit non-zero on drift. cbt-only
edit, zero compiler delta. **Half (b) var X; bare-decl diag**:
two ERR_EXPECT(S, 4) sites in parse_decl.cyr (line 953
PARSE_VAR; line 594 EMIT_GVAR_INITS) emitted generic "expected
'=', got ';'" for the bare-decl shape. Devs porting from C/Go
expected `var X;` to declare a zero-init slot and got the cryptic
generic message. Fix: special-case the `;` token at both sites
— if actual token is `;`, emit specific "uninitialized variable
not allowed; use `var X = 0;` or initial value". Other missing-=
cases (e.g. `var x 42;`) keep generic ERR_EXPECT path so the
diagnostic still names the real offending token. cc5 **740,312
→ 740,528 B (+216 B)** — entirely from half (b)'s diagnostic
improvement. Verification: self-host two-step byte-identical,
check.sh 65/65, manual smoke clean (cyrfmt drift/no-drift/
unrelated-syntax-error all correct; var X; in-fn + top-level
both produce new message; var x 42; keeps generic). v5.8.x
cycle progress: **42 of 51 pinned slots shipped (82.4%)**.
Phase 3 remaining (9 slots): Phase 3 polish absorber (v5.8.43),
api-surface refresh (v5.8.44), kernel reserved-word (v5.8.45),
arithmetic in fn args (v5.8.46), combined starship/p10k color
refresh + vidya cyrius-language audit (v5.8.47), refactoring
+ heap-map cleanups (v5.8.48), full closeout pass (v5.8.49),
deps cleanup + post-release propagation (v5.8.50), release-valve
(v5.8.51). Cycle backstop hard at v5.8.51.)

**5.8.41** (shipped 2026-05-03 — **v5.8.x SLOT 41 — cyrlint large-file
false-positive verification slot**. Third slot of Phase 3. Closes
the mabda-filed `cyrius lint reports phantom "unclosed braces at
end of file" on large test files` issue (mabda/docs/development/
issues/2026-04-28-cyrlint-multi-line-assert.md) which a premise
check at slot entry found NOT REPRODUCING at v5.8.40 across 4
synthetic repros — likely fixed by intermediate cyrlint work
between v5.7.23 filing and v5.8.40.) **Premise check (4 repros
all clean)**: 3504-line plain-vars (`var x_N = N;` × 3500), mabda's
actual mabda.tcyr at 2743 lines, doubled mabda content at 5486
lines, 9007-line synthetic with 600 fns + multi-line assert_eq +
comments — all returned 0 warnings. Cyrius git log shows multiple
"fixing linter" commits between v5.7.23 filing and v5.8.40;
probable resolution candidates: v5.7.36 string-literal awareness
fix, later brace-tracker refactor, v5.8.40's preprocessor
string-literal awareness as secondary protection. **Per user
direction at slot entry**: ship as verification slot; if mabda
hits a new variant they file a new issue with fresh repro +
repo location. **New regression-floor gate**:
tests/regression-cyrlint-large-file.sh generates a 7010-line
synthetic matching mabda's repro shape (700 fns each with
test_group + multi-line assert_eq + brace-block body + comments),
runs cyrlint, asserts 0 "unclosed braces" / 0 "trailing
whitespace" warnings. Wired into check.sh as section 4an2
alongside the existing v5.7.32 cyrlint global-init-order gate.
**Mabda issue annotated** as ✅ RESOLVED in cyrius v5.8.41 with
premise-check methodology + 4-repro evidence + regression-floor
pointer + explicit "if NEW variant, file NEW issue, don't reopen"
note. cc5 unchanged at **740,312 B** (zero compiler delta — gate
is shell + uses pre-existing cyrlint). **Gate count 64 → 65**
(check.sh +1). **Process notes**: (1) two layers of premise
check beat acting on the original pin text — pin said "multi-line
assert false-positive", mabda's bisection revised to "file-size
threshold", v5.8.41's premise check revised again to "already
fixed". Per feedback_premise_check_at_slot_entry.md. (2) Verification
slots are legitimate slot deliveries — convert "we think it's
fixed" into "CI proves it's fixed and will catch any regression".
(3) Per feedback_flag_missing_repos_dont_skip.md applied here:
mabda repo IS at /home/macro/Repos/mabda/; annotation went into
the right place; no silent "n/a" lazy skip. v5.8.x cycle progress:
**41 of 51 pinned slots shipped (80.4%)**. Phase 3 remaining (10
slots): paired UX polish (v5.8.42), Phase 3 polish absorber
(v5.8.43), api-surface refresh (v5.8.44), kernel reserved-word
(v5.8.45), arithmetic in fn args (v5.8.46), starship + vidya
audit combined (v5.8.47), refactoring + heap-map cleanups
(v5.8.48), full closeout pass (v5.8.49), deps cleanup +
post-release propagation (v5.8.50), release-valve (v5.8.51).
Cycle backstop hard at v5.8.51.)

**5.8.40** (shipped 2026-05-03 — **v5.8.x SLOT 40 — preprocessor
string-literal awareness**. Second slot of Phase 3 (cascaded from
v5.8.39 by sandhi re-slot). Closes the long-standing PP bug where
source containing string literals with the byte sequence `include "`
at beginning-of-line was processed as a real include directive,
silently corrupting source.) Filed at v5.7.49 vidya audit
(`docs/development/issues/2026-05-01-preprocessor-include-pattern-
in-string-literals.md`); pinned to v5.8.x bug-fix cycle. **PP_PASS
+ PP_IFDEF_PASS** in src/frontend/lex_pp.cyr now track `"`-bounded
string-literal state via in_string + escape_next flags; the
`if (bol == 1)` directive-detection block is gated on
`&& in_string == 0`. Mirrors the v5.7.36 cyrlint string-literal
awareness fix shape. State transitions in default-copy branch:
escape_next clears + skips toggle; outside-string `"` enters string;
inside-string `\` sets escape_next; inside-string `"` exits.
**Vidya annotated** at content/cyrius/ecosystem.cyml:685-720 —
status flipped from "pinned for v5.8.x" to "✅ FIXED in v5.8.40";
workaround text kept for pre-v5.8.40 toolchain users; cross-ref
to canonical issue file maintained per v5.7.49 audit policy.
New tcyr `preprocessor_string_literal.tcyr` — 12 assertions across
5 groups (string with include pattern preserved byte-by-byte,
back-compat byte-store workaround still produces same bytes, real
include directives at col 0 still work as regression floor, escape
sequences inside strings, '#define' prefix inside string isn't a
directive). cc5 **739,672 B → 740,312 B (+640 B)** — 320 B per
pass for the state machine. Verification: self-host two-step
byte-identical, check.sh 64/64, preprocessor_string_literal 12/12,
all Phase 2 sub-suite tcyrs regression-floored. **Process note**:
lex_pp.cyr is in src/ not lib/, so ping-pong path doesn't apply
(no snapshot refresh needed). v5.8.x cycle progress: **40 of 44
pinned slots shipped (90.9%)**. Phase 3 remaining (4 slots):
cyrlint multi-line assert false-positive (v5.8.41), vidya cyrius-
language audit (v5.8.42), paired UX polish (v5.8.43), cycle
backstop (v5.8.44). Cycle backstop v5.8.49.)

**5.8.39** (shipped 2026-05-03 — **v5.8.x SLOT 39 — fold sandhi v1.1.0
dist into stdlib**. First slot of Phase 3. Closes the v5.8.36
deferral of sandhi from Allocator stdlib pass 2 by vendoring the
just-released sandhi v1.1.0 dist/sandhi.cyr into
cyrius/lib/sandhi.cyr.) **Re-slotted from preprocessor item** —
v5.8.39 was originally pinned for "Preprocessor include-pattern in
string literals (vidya audit)"; user reslotted because sandhi
v1.1.0 became available between v5.8.38 ship and Phase 3 start.
Displaced preprocessor item cascades to v5.8.40; rest of Phase 3
shifts right by 1; backstop unchanged (v5.8.49) with 5 slots of
headroom. **Sandhi v1.1.0 delivered**: 6 batches bottom-up (URL/
headers/discovery leaves → TLS+h2 leaves → discovery+RPC → HTTP
response/request foundation → connection layer → client/streaming/
SSE/retry/server); ~150 new public `_a` verbs across 27 files
threading Allocator as first arg per cyrius v5.8.35-36 pattern;
back-compat wrappers preserve pre-migration API via default_alloc().
**Singletons pinned to default_alloc** (ALPN wire, HPACK static
table, Huffman decode tree, server per-process req buf — they
outlive any per-request arena, corrupting them on reset would
break in-flight requests). **Daimon ctx grew 16→24 B**; local mDNS
gained 8B ctx (resolver-fn-pointer callbacks carry the allocator
on the ctx struct since `(ctx, name)` shape can't take extra arg).
**Pool struct grew 40→48 B** (Allocator on slot +40 routes pool
churn through the same arena). **143 new alloc tcyrs** in sandhi
(tests/alloc.tcyr separate program per fixup-table cap arch ADR);
total sandhi 792 assertions green (482 sandhi + 167 h2 + 143
alloc; +143 over v1.0.0). **Headline win** — per-request-arena
pattern: HTTP server handlers can `arena_allocator(64KB)` at top
of request, build URL/headers/response/body all into one arena,
reset_via(a) between requests; zero leakage; deterministic memory
ceiling; failing-allocator coverage of every handler path via
fail_after_n_allocs. **Fold-in mechanics**: cp sandhi/dist/
sandhi.cyr → cyrius/lib/sandhi.cyr (376,037 B → 411,361 B;
+35,324 / +9.4%); snapshot refresh to ~/.cyrius/lib/ + ~/.cyrius/
versions/5.8.38/lib/ per ping-pong protection. **Cyrius-side
consumers** — none broken. grep -rln '^include "lib/sandhi.cyr"'
across cyrius src/lib/tests/programs returned zero; only ref is
a historical-bug comment in src/backend/x86/emit.cyr:1122. sandhi
is pure-vendored — downstream consumers (vidya, samvada, etc.)
pull it via cyrius deps, so fold-in propagates v1.1.0 stdlib to
every sandhi-using repo on next deps resolution. **Sandhi-side
toolchain pin** bumped 5.6.41 → 5.8.36 in sandhi's cyrius.cyml.
**Sandhi-side scope-shrink ledger** (captured in cyrius CHANGELOG):
str_builder_* lacks _a variants in v5.8.36 stdlib pin sandhi
worked against — sandhi's _a paths use global bump for builder
scratch + dup final cstr into a; future cyrius slot adding
str_builder_new_a will let these dups drop. cc5 unchanged at
**739,672 B** (zero compiler delta — pure stdlib re-vendor).
Verification: self-host two-step byte-identical, check.sh 64/64,
all sub-suite tcyrs regression-floored. v5.8.x cycle progress:
**39 of 44 pinned slots shipped (88.6%)**. Phase 3 remaining (5
slots, +1 cascade): preprocessor include-pattern (v5.8.40 — was
v5.8.39), cyrlint multi-line assert false-positive (v5.8.41 — was
v5.8.40), vidya cyrius-language audit (v5.8.42 — was v5.8.41),
paired UX polish (v5.8.43 — was v5.8.42), cycle backstop (v5.8.44
— was v5.8.43). Cycle backstop v5.8.49.)

**5.8.38** (shipped 2026-05-03 — **v5.8.x SLOT 38 — Allocators sub-suite
closeout. Sub-suite COMPLETE (v5.8.33–v5.8.38, 6 slots, +0 B
compiler delta, 156 new tcyr assertions across 4 new tcyrs).**
Smoke + retrospective slot — no compiler change. **Phase 2 COMPLETE**
(both sub-suites done: Result+? at +1,784 B, Allocators at +0 B).)
**Sub-suite delivered**: Allocator vtable (40B, 5 i64 slots) + 3
impls (bump/arena/test) + 4 dispatch helpers (alloc_via /
realloc_via / free_via / reset_via) + failing-allocator harness
(fail_after_n_allocs in lib/assert.cyr) + default_alloc() lazy-init
singleton + 30 `_a` variants across vec/str/hashmap/json/toml/cyml/
http + alloc_init() lazy-init in alloc() across Linux/macOS/Windows.
**Cross-repo smoke** (all 4 pinned consumers reached): sigil 3.0.0
✅ (compile OK; runtime exit 4 matches v5.7.48 baseline — sigil's
smoke is non-zero by design); mabda ✅ (compile OK); yukti ✅
(compile OK); ark 0.8.0 ✅ (5.1.10 → 5.8.37 → 5.1.10; compile OK;
runtime exit 0 matches baseline — ark's pin was 7 minors old,
validating back-compat from a long-stale caller).
**Static audit pre-dynamic**: 0 collisions across all 3 reachable
repos for every v5.8.33-37 symbol (bump/arena/test_allocator,
alloc_via et al, default_alloc, fail_after_n_allocs, all *_a
variants). **Allocator-API adoption**: 0 of 47 alloc_init() call
sites across sigil (27) / mabda (16) / yukti (3) / ark (1)
migrated yet — per migration policy opt-in during v5.8.x;
lazy-init in v5.8.37 means existing alloc_init() top-level calls
keep working unchanged.
**Acceptance-gate audit**: byte-identical self-host every patch ✅;
oom_vec_push.tcyr Err(OutOfMemory) gate ⚠ partial (vec_push_a
returns -1, not Err — back-compat shape preserved; v6.0.0 closeout
removes legacy wrapper and ships full Result-typed OOM); compiler-
internal explicit Allocator ⚠ partial (cc5's src/ uses global
bump; pinned for v6.0.0 sweep). **Honest scope-shrink ledger**:
sandhi deferred (handed off to parallel agent for v1.1.0); str
peripheral fns (str_split/str_trim/str_builder_new) and map_u64_*
not migrated (transitive arena routing via default_alloc works);
http_get_a partial migration (URL parsing on default); alloc_init()
retirement is requirement-only; compiler-internal explicit Allocator
deferred to v6.0.0. **Process notes**: (1) sigil smoke baseline check before claiming
regression — first v5.8.37 sigil smoke returned exit 4; restoring
to v5.7.48 baseline reproduced exit 4 (sigil's smoke is non-zero
by design). Lesson: baseline FIRST when smoking against a
downstream pinned baseline. (2) Missing-repo lazy-skip pattern
caught + corrected — first-draft closeout marked ark as ⚠
"deferred / not present" (same as v5.8.32); user pushback caught
it; ark IS available locally; smoke ran clean. Memory saved as
feedback_flag_missing_repos_dont_skip.md: when a closeout pin
names a repo that isn't at the expected path, STOP and ASK before
silently marking n/a. **Phase 2 COMPLETE**:
both sub-suites done in 11 slots total (Result+? 5 + Allocators 6).
cc5 unchanged at **739,672 B**. Verification: self-host two-step
byte-identical, check.sh 64/64 (first run flickered to 63/64
intermittent gate, second run clean), all sub-suite tcyrs
regression-floored. v5.8.x cycle progress: **38 of 44 pinned slots
shipped (86.4%)**. Phase 3 next: v5.8.39-v5.8.44 (6 closeout slots);
cycle backstop v5.8.49.)

**5.8.37** (shipped 2026-05-03 — **v5.8.x SLOT 37 — `alloc_init()`
becomes optional via lazy-init**. Fifth slot of the Phase 2
Allocators sub-suite (v5.8.33–v5.8.38). Pin wording was "Retire
alloc_init() global singleton"; honest interpretation — alloc_init()
stays callable but the REQUIREMENT to call it pre-alloc is retired
via lazy-init in alloc().) **Lazy-init guard added** to
lib/alloc.cyr (Linux) + lib/alloc_macos.cyr + lib/alloc_windows.cyr:
`if (_heap_base == 0) { alloc_init(); }` at top of alloc().
Pre-v5.8.37 every consumer had to alloc_init() before any alloc;
new code can omit. **Header doc updated** to reflect the
optional-init shape; alloc_init() doc clarified it's now an
explicit-init shim. New tcyr `alloc_no_init.tcyr` — 17 assertions
across 8 groups deliberately omitting top-level alloc_init() call
(direct alloc, multiple back-to-back distinct ptrs, alloc_via via
default_alloc, arena_new, explicit alloc_init post-lazy-init still
callable, vec/str/hashmap all work). **Honest pin interpretation**
— migration policy (roadmap line 965-968) resolves the apparent
conflict: v5.8.37 retires the REQUIREMENT (lazy-init); v6.0.0
sweeps explicit calls out of consumers; only then can the fn
itself retire. **Sandhi-side proposal handed off** —
sandhi/docs/proposals/2026-05-03-allocator-migration.md filed for
parallel agent work targeting sandhi v1.1.0; 6-batch bottom-up
migration of 27 files / ~135 alloc sites; per-batch acceptance
gates; process notes from v5.8.33-36 lessons captured.
cc5 unchanged at **739,672 B** (zero compiler delta — pure stdlib
addition). Verification: self-host two-step byte-identical,
check.sh 64/64, alloc_no_init 17/17, alloc_iface 43/43,
oom_handling 33/33, alloc_stdlib 33/33, alloc_stdlib_pass2 30/30,
all Result+? tcyrs regression-floored. v5.8.x cycle progress:
**37 of 44 pinned slots shipped (84.1%)**. Allocators sub-suite
remaining: closeout (v5.8.38). Phase 3 closeout v5.8.39–v5.8.44;
cycle backstop v5.8.49.)

**5.8.36** (shipped 2026-05-03 — **v5.8.x SLOT 36 — stdlib Allocator
migration pass 2**. Fourth slot of the Phase 2 Allocators sub-suite
(v5.8.33–v5.8.38). Threads Allocator as first arg across the
peripheral modules: lib/json.cyr (12 new `_a` variants),
lib/toml.cyr (2), lib/cyml.cyr (2), lib/http.cyr (1 partial +
1 internal). lib/sandhi.cyr is auto-generated from sandhi distrepo
via `cyrius distlib` — migration requires upstream sandhi changes,
deferred to next distlib refresh.) **json**: _jv_alloc_a +
json_v_{null,bool_new,int_new,float_new,str_new,arr_new,obj_new}_a
+ _jv_pair_new_a + json_v_arr_push_a + json_pair_new_a.
json_v_arr_new_a / json_v_obj_new_a use vec_new_a internally so
inner vec also lives in arena. **toml**: toml_section_new_a +
toml_pair_new_a. **cyml**: cyml_entry_new_a + cyml_doc_new_a.
**http**: _http_parse_response_a internal helper +
http_get_a(a, url) — partial migration routing the 64KB recv
buffer + 32B response struct through the supplied allocator;
URL parsing + request-build buffers stay on default_alloc (smaller,
bounded, shared between requests in the typical per-request-arena
pattern). New tcyr `alloc_stdlib_pass2.tcyr` — 30 assertions
across 10 groups (json back-compat, _a tree-building inside arena,
arena reset clears everything, OOM via fail_after_n_allocs at the
3-alloc arr_new_a threshold, json_pair cstr-deref, toml/cyml
constructor round-trips, http_get_a bad-URL alloc routing).
**Lint gate caught 2 long-line warnings** in http.cyr after the
edit (one-liner if-blocks exceeded 120 cols); reformatted to
multi-line. **Tcyr ergonomics lesson**: first draft of
json_pair_new_a value check used `load64(pair + 8)` expecting the
'v' byte, but pair[+8] is the cstr POINTER — fixed via
`load8(load64(pair + 8))`. Cyrius's i64-everything model lets
this type confusion compile silently. cc5 unchanged at **739,672
B** (zero compiler delta — pure stdlib addition). Verification:
self-host two-step byte-identical, check.sh 64/64,
alloc_stdlib_pass2 30/30, alloc_stdlib 33/33, alloc_iface 43/43,
oom_handling 33/33, all Result+? tcyrs regression-floored.
v5.8.x cycle progress: **36 of 44 pinned slots shipped (81.8%)**.
Allocators sub-suite remaining: retire alloc_init() (v5.8.37),
sub-suite closeout (v5.8.38). Phase 3 closeout v5.8.39–v5.8.44;
cycle backstop v5.8.49.)

**5.8.35** (shipped 2026-05-03 — **v5.8.x SLOT 35 — stdlib Allocator
migration pass 1**. Third slot of the Phase 2 Allocators sub-suite
(v5.8.33–v5.8.38). Threads Allocator as first arg of every alloc-
touching public fn in lib/vec.cyr / lib/str.cyr / lib/hashmap.cyr;
existing call sites stay callable via back-compat wrappers that
pass default_alloc() = lazy-init bump_allocator() singleton.)
**lib/alloc.cyr**: new default_alloc() — _default_allocator global
+ lazy-init bump_allocator on first call. **lib/vec.cyr**:
vec_new_a(a) returns 0 on OOM; vec_push_a(a, v, val) returns -1
on grow OOM (vs. back-compat vec_push which aborts). **lib/str.cyr**:
str_from_a / str_new_a / str_cat_a / str_clone_a / str_from_int_a
all return 0 on OOM (Str-typed sentinel). **lib/hashmap.cyr**:
map_new_a / map_new_str_a / _map_grow_a / map_set_a — map_set_a
returns -1 on grow OOM. (map_u64_new / map_u64_set / str_split /
str_trim deferred to v5.8.36 along with json/toml/cyml/http/sandhi.)
New tcyr `alloc_stdlib.tcyr` — 33 assertions across 14 groups
(back-compat wrappers, _a variants with bump_allocator,
_a variants with arena_allocator(8KB), OOM via
fail_after_n_allocs — vec_push_a/map_set_a return -1, str_cat_a/
str_clone_a return 0, default_alloc singleton consistency).
**Doc-coverage gate caught 1 undocumented fn** (map_new_str lost
its leading comment when _a variant was inserted); fixed inline.
**OOM-threshold tuning lesson**: when testing grow-path OOM,
count the exact alloc sequence — first draft used fail_after=4
but the test loop exhausted before grow #2 fired; re-tuned to
fail_after=2 so the first grow trips OOM. cc5 unchanged at
**739,672 B** (zero compiler delta — pure stdlib addition).
Verification: self-host two-step byte-identical, check.sh 64/64,
alloc_stdlib 33/33, alloc_iface 43/43, oom_handling 33/33, all
Result+? tcyrs regression-floored. v5.8.x cycle progress: **35
of 44 pinned slots shipped (79.5%)**. Allocators sub-suite
remaining: stdlib pass 2 json/toml/cyml/http/sandhi (v5.8.36),
retire alloc_init() (v5.8.37), sub-suite closeout (v5.8.38).
Phase 3 closeout v5.8.39–v5.8.44; cycle backstop v5.8.49.)

**5.8.34** (shipped 2026-05-03 — **v5.8.x SLOT 34 — failing-allocator
test harness**. Second slot of the Phase 2 Allocators sub-suite
(v5.8.33–v5.8.38). Adds `fail_after_n_allocs(n)` helper to
lib/assert.cyr — a thin wrapper over v5.8.33's test_allocator() +
test_allocator_fail_after(). Foundation for the OOM-handling
coverage v5.8.35-37 stdlib migration will land.) lib/assert.cyr
gains `include "lib/alloc.cyr"` near the top so test consumers
get assertion + OOM-driving stack from a single include. New
`fn fail_after_n_allocs(n)` returns an Allocator configured to
fail after n successful alloc_via calls — n=0 fails every alloc,
n=-1 never fails. New tcyr `oom_handling.tcyr` — 33 assertions
across 9 groups (n=0 / n=1 / n=3 thresholds, alloc_count tracks
failures, bytes_total accumulation, reset_via clears counters but
preserves threshold, consumer-pattern fallback with primary-OK +
backup-OOM distinction, vtable sanity). cc5 unchanged at
**739,672 B** (zero compiler delta — pure stdlib addition).
Verification: self-host two-step byte-identical, check.sh 64/64,
oom_handling 33/33, alloc_iface 43/43, all Result+? tcyrs
regression-floored. Doc-coverage gate clean on first run (12/12 —
v5.8.33 lesson stuck). v5.8.x cycle progress: **34 of 44 pinned
slots shipped (77.3%)**. Allocators sub-suite remaining: stdlib
pass 1 vec/str/hashmap (v5.8.35), stdlib pass 2 json/toml/cyml/
http/sandhi (v5.8.36), retire alloc_init() (v5.8.37), sub-suite
closeout (v5.8.38). Phase 3 closeout v5.8.39–v5.8.44; cycle
backstop v5.8.49.)

**5.8.33** (shipped 2026-05-03 — **v5.8.x SLOT 33 — Allocator vtable
interface**. First slot of the Phase 2 Allocators sub-suite
(v5.8.33–v5.8.38). Foundational: adds Allocator vtable shape + 3
default impls to lib/alloc.cyr without touching the existing
global-singleton callers.) **Allocator layout** (40 bytes, 5 i64
slots): alloc_fn / realloc_fn / free_fn / reset_fn / state. **3
impls**: `bump_allocator()` wraps the global bump (state=0,
free=no-op, reset=alloc_reset GLOBAL); `arena_allocator(cap)`
wraps a fresh arena (state=arena ptr, reset clears only this
arena); `test_allocator()` tracks alloc_count + bytes_total +
fail_after threshold for the v5.8.34 OOM harness (state=24-byte
struct with counter+threshold+totals). **Dispatch helpers**:
`alloc_via(a, size)`, `realloc_via(a, p, oldsz, newsz)`,
`free_via(a, p)`, `reset_via(a)` — call through the vtable via
fncall1/fncall2/fncall4 from lib/fnptr.cyr. **Vtable accessors**:
allocator_alloc_fn / realloc_fn / free_fn / reset_fn / state.
**test_allocator extras**: test_allocator_fail_after(a, n) —
configure threshold (-1 = never); test_allocator_alloc_count(a) /
test_allocator_bytes_total(a) — read counters. New tcyr
`alloc_iface.tcyr` — 43 assertions across 12 groups (vtable
layout, bump alloc+free+realloc-grow, arena alloc+cap-overflow+
reset-returns-to-base, test alloc_count+fail_after+
-1-disables+reset-clears, cross-impl uniformity). **Doc-coverage
gate caught 8 undocumented public fns** (5 accessors + 3
constructors) on first check.sh run; fixed inline before bump
per `cyrdoc --check` convention. cc5 unchanged at **739,672 B**
(zero compiler delta — pure stdlib addition). Verification:
self-host two-step byte-identical, check.sh 64/64, alloc_iface
43/43, all Result+? tcyrs regression-floored. v5.8.x cycle
progress: **33 of 44 pinned slots shipped (75.0%)**. Allocators
sub-suite remaining: failing-allocator harness (v5.8.34), stdlib
pass 1 vec/str/hashmap (v5.8.35), stdlib pass 2 json/toml/cyml/
http/sandhi (v5.8.36), retire alloc_init() (v5.8.37), sub-suite
closeout (v5.8.38). Phase 3 closeout v5.8.39–v5.8.44; cycle
backstop v5.8.49.)

**5.8.32** (shipped 2026-05-03 — **v5.8.x SLOT 32 — Result+? sub-suite
closeout. Sub-suite COMPLETE (v5.8.28–v5.8.32, 5 slots, +1,784 B
compiler delta from 737,888 → 739,672 B, 106 new tcyr assertions
across 4 new tcyrs).** Smoke + retrospective slot — no compiler
change.) Cross-repo downstream smoke executed via temporary-pin-bump
methodology: backup cyrius.cyml + lib/, bump pin to 5.8.31, copy
v5.8.31/lib/*.cyr over snapshot (preserve symlinks; add new
lib/result.cyr that v5.8.28 introduced), `cyrius build` smoke
target + run, restore. **Results**: sigil 3.0.0 ✅ (compile + runtime
exit 0); mabda ✅ (compile OK); yukti ✅ (compile OK); ark ⚠ (repo not
present at /home/macro/Repos/ark/, flagged for next downstream cycle).
**Static audit pre-dynamic**: 0 enum-variant name collisions across
all 3 reachable repos (each defines its own module-prefixed enums —
SigilError, WGPUBlendOp, DeviceClass etc. — none clash with the
v5.8.30/.31 Io*/Json*/Toml*/Cyml*/Http*/Dynlib*/Pwd*/Grp*/Shadow*/Pam*
variants); all sub-suite changes additive (legacy file_open /
json_parse_file / tcp_socket / pwd_getpwuid all preserved verbatim).
**Honest scope-shrink ledger**: lib/net.cyr was pre-migrated (Err(errno)
form from a pre-cycle migration; refactor to NetError would have broken
ws_server/sandhi consumers); strict "?-outside-Result-returning-fn type
error" enforcement deferred (needs fn return-type tracking). **Bonus
fix**: doc-audit deletion of docs/benchmarks.md (commit 62eec00) caught
afterwards as breaking ci.yml's required-docs check; restored as a stub
at the canonical path pointing readers to size-comparisons.md +
development/benchmarks.md, with original v3.4.15 content preserved as
docs/development/archive/2026-04-11-benchmarks.md. CLAUDE.md memory
updated with the lesson (feedback_archive_dont_delete_docs.md).
**Methodology pinned for future closeouts**: `cyrius deps` does NOT
refresh cyrius-side stdlib snapshots in downstream repos — it only
resolves `[deps.*]`-declared packages — so cross-version smoke needs
the manual lib/ overlay step. cc5 unchanged at **739,672 B**.
Verification: self-host two-step byte-identical, check.sh 64/64,
result 24/24, result_propagation 29/29, result_stdlib 29/29,
result_stdlib_pass2 24/24. v5.8.x cycle progress: **32 of 44 pinned
slots shipped (72.7%)**. Remaining: allocators (v5.8.33–v5.8.38, 6
slots), Phase 3 closeout (v5.8.39–v5.8.44, 6 slots). Cycle backstop
v5.8.49.)

**5.8.31** (shipped 2026-05-03 — **v5.8.x SLOT 31 — stdlib `Result`
migration pass 2 + http_get bug fix + PARSE_STMT `?`-statement gap
close**. Fourth slot of the Phase 2 Result+? sub-suite (v5.8.28–
v5.8.32). Adds `*_r` variants across 6 modules (http / dynlib /
pwd / grp / shadow / pam) with module-prefixed error enums.)
**Premise-check finding:** `lib/net.cyr` was already Result-
returning (Err(errno) form) from a pre-cycle migration; refactor
to NetError enum would break payload-comparing consumers
(ws_server / sandhi). Skipped per honest scope-shrink — only
gap was sock_close/sock_shutdown returning bare ints (essentially
infallible). **Fixed:** lib/http.cyr's http_get treated
tcp_socket()/sock_connect()/sock_send()/sock_recv() Result heap
ptrs as raw ints — guard `if (fd < 0)` never fired since heap
ptrs are positive; subsequent syscalls passed the Result ptr as
a kernel fd and silently failed. Replaced with is_err_result/
payload guards in the lib/sandhi.cyr shape. Bug predates v5.8.x.
**Fixed:** v5.8.29's `?` hook lived only in PARSE_TERM, but
PARSE_STMT's IDENT+LPAREN dispatch bypasses PARSE_TERM, so bare
`expr?;` statements hit "expected ';', got unknown" (token 124
has no TOKNAME entry). Added matching desugar inline in
PARSE_STMT after PARSE_FNCALL. **New error enums:** HttpError
(HttpBadUrl, HttpNetErr, HttpNon2xx, HttpOther); DynlibError
(DynlibNotFound, DynlibBadElf, DynlibSymMissing, DynlibOther);
PwdError (PwdNotFound, PwdLoadFailed, PwdBufTooSmall, PwdOther);
GrpError (same shape); ShadowError (same shape); PamError
(PamAuthFail, PamHelperMissing, PamPipeFailed, PamForkFailed,
PamExecFailed, PamOther). New tcyr `result_stdlib_pass2.tcyr` —
24 assertions across 12 groups (dynlib NotFound/BadElf,
pwd_getpwuid_r self-uid Ok + bogus Err, grp gid-0 Ok + bogus
Err, shadow load-failed-or-not-found Err, pam auth-fail-or-
helper-missing Err, ?-propagation chain on pwd_getpwuid_r +
pwd_uid). cc5 **738,856 → 739,672 B (+816 B)** — entirely from
the PARSE_STMT `?` hook; the 6 stdlib modules ship zero compiler
delta. Verification: self-host two-step byte-identical, check.sh
64/64, result_stdlib_pass2 24/24, result_stdlib 29/29,
result_propagation 29/29, result 24/24, tagged 14/14, aarch64
SSH gate PASS. v5.8.x cycle progress: **31 of 44 pinned slots
shipped (70.5%)**. Phase 2 remaining: Result sub-suite closeout
(v5.8.32), allocators (v5.8.33–v5.8.38). Phase 3 closeout
v5.8.39–v5.8.44; cycle backstop v5.8.49.)

**5.8.30** (shipped 2026-05-03 — **v5.8.x SLOT 30 — stdlib `Result`
migration pass 1**. Third slot of the Phase 2 Result+? sub-suite
(v5.8.28–v5.8.32). Adds `Result`-returning `*_r` variants of the
file-loading paths across four stdlib modules. Zero compiler
delta — pure stdlib reorganization.) Per-module error enums:
`IoError {IoNotFound, IoAccessDenied, IoBadFd, IoFailed, IoOther}`,
`JsonError {JsonIoErr, JsonParseErr, JsonOther}`,
`TomlError {TomlIoErr, TomlParseErr, TomlOther}`,
`CymlError {CymlIoErr, CymlOther}`. Module-prefixed variant
names avoid global-namespace collisions; verified by the
result_stdlib tcyr including all four modules simultaneously.
**lib/io.cyr** adds `file_open_r`, `file_close_r`, `file_read_r`,
`file_write_r`, `file_read_all_r`, `file_write_all_r` — all
return `Result<T, IoError>` mapping the negated kernel errno
through `_io_errno_to_iorr`. **lib/json.cyr** + **lib/toml.cyr**
add `*_parse_file_r` variants surfacing underlying file-read
failures as `Err(IoErr)` instead of the back-compat silent-empty-
vec behavior. **lib/cyml.cyr** adds the brand-new
`cyml_parse_file_r` (cyml had no prior file-loading helper).
Legacy int-returning fns stay callable per migration policy
(roadmap line 922) — back-compat through v5.8.x; v6.0.0
closeout removes. New `tests/tcyr/result_stdlib.tcyr` —
29 assertions across 14 groups (Ok/Err for each *_r,
round-trip write+read, `?` propagation chain over
open+read+close, json/toml/cyml synthetic-file Ok cases).
**Cross-compiler refresh** required mid-slot — stale
`build/cc5_aarch64` (May 2 build) choked on the v5.8.21
`enum Result<T, E>` generic syntax newly transitively included
via `lib/io.cyr`; rebuilt from `src/main_aarch64.cyr` via host
cc5, aarch64 SSH gate cleared. cc5 unchanged at **738,856 B**.
Verification: self-host two-step byte-identical, check.sh 64/64,
result_stdlib 29/29, result_propagation 29/29, result 24/24,
tagged 14/14. v5.8.x cycle progress: **30 of 44 pinned slots
shipped (68.2%)**. Phase 2 remaining: stdlib migration pass 2
(v5.8.31), Result sub-suite closeout (v5.8.32), allocators
(v5.8.33–v5.8.38). Phase 3 closeout v5.8.39–v5.8.44; cycle
backstop at v5.8.49.)

**5.8.29** (shipped 2026-05-03 — **v5.8.x SLOT 29 — postfix `?`
propagation operator on `Result<T, E>`. Second slot of the Phase 2
Result+? sub-suite (v5.8.28–v5.8.32). Compiler addition: lex token
124 + parse hook + emit desugar.**) — `expr?` desugars at the call
site to `tag = load64(expr); if (tag != Ok) return expr; rax =
load64(expr + 8)`. Highest precedence — binds tighter than `*`/`/`
so `foo()? * bar` is `(foo()?) * bar`. Early-return path uses the
existing fn-epilogue jump table (`0x18DA20` / `GRPC` / `EJMP0`).
Lex: standalone `?` token 124, distinct from the existing TS-regex
compounds `+?`/`-?`/`*?` (115/118/121). Parse + emit: hook in
`PARSE_TERM` immediately after the first `PARSE_FACTOR` call;
hidden temp var (same idiom as `PARSE_MATCH`'s `midx`); existing
emit primitives only (no new x86 hex literals). Outside-fn-body
`?` is a parse-time hard error (verified via `/tmp/probe_q_outside.
cyr`). Stricter "outside Result-returning fn is type error"
enforcement deferred — needs fn return-type tracking that doesn't
exist yet; honest scope-shrink documented per CLAUDE.md pattern.
New `tests/tcyr/result_propagation.tcyr` — 29 assertions across
11 groups (Ok unwrap, Err short-circuit at first/second `?`,
`return expr?;` shape, `?` in binary-op context, `?` as first
fn-body statement, `?` inside `if` body, payload roundtrip
negatives + zero). cc5 **737,888 B → 738,856 B (+968 B)**.
Verification: self-host two-step byte-identical, check.sh 64/64,
result_propagation 29/29, result 24/24, tagged 14/14. v5.8.x
cycle progress: **29 of 44 pinned slots shipped (65.9%)**. Phase 2
remaining: stdlib migrations (v5.8.30/.31), Result sub-suite
closeout (v5.8.32), allocators (v5.8.33–v5.8.38). Phase 3 closeout
v5.8.39–v5.8.44; cycle backstop at v5.8.49.)

**5.8.28** (shipped 2026-05-03 — **v5.8.x SLOT 28 — `Result<T, E>`
carve-out into `lib/result.cyr`. First slot of the Phase 2
Result+? sub-suite (v5.8.28–v5.8.32). Stdlib-only / zero compiler
change**) — `enum Result<T, E> { Ok(v); Err(e); }` (typed shape
using v5.8.21 generic-parameter syntax) and all six Result
helpers (`is_ok`, `is_err_result`, `result_unwrap`,
`result_unwrap_or`, `err_code_of`, `result_print`) moved out of
`lib/tagged.cyr` into the dedicated `lib/result.cyr` module.
Helpers inline `load64()` for tag/payload access so the new
module has no circular dep on tagged.cyr. `lib/tagged.cyr` adds
`include "lib/result.cyr"` near the top so existing consumers
(`lib/net.cyr`, `lib/ws_server.cyr`, `lib/sandhi.cyr`,
`tests/tcyr/tagged.tcyr`) keep working transitively. New
`tests/tcyr/result.tcyr` — 24 assertions across 9 groups
covering constructor layout, all six helpers, payload roundtrip,
`match load64(res)` pattern-match consumer, realistic
`_safe_div(n, d)` Result-returning fn shape. cc5 unchanged at
**737,888 B** (zero compiler delta — pure stdlib reorganization).
Verification: self-host two-step byte-identical, check.sh 64/64,
result tcyr 24/24, tagged tcyr 14/14. Snapshot-ping-pong
mitigation fired during first check.sh run (caught the
documented loop, recovered per CLAUDE.md recipe). v5.8.x cycle
progress: **28 of 44 pinned slots shipped (63.6%)**. Phase 2
continuing: `?` operator (v5.8.29), stdlib migrations
(v5.8.30/.31), Result sub-suite closeout (v5.8.32),
allocators (v5.8.33–v5.8.38), Phase 3 closeout v5.8.39–v5.8.44;
cycle backstop at v5.8.49.)

**5.8.27** (shipped 2026-05-03 — **v5.8.x SLOT 27 — tagged-
unions sub-suite closeout. Sub-suite COMPLETE (v5.8.21–v5.8.27,
7 slots, +5,568 B compiler delta from 732,320 → 737,888 B,
51 new tcyr assertions across 3 new tcyrs + 14 preexisting
exercising migrated lib/tagged.cyr).** Doc-only / verification
slot — no compiler or stdlib code change. Sub-suite delivered
the language-feature foundation that v5.8.28–v5.8.32 (Result+?)
builds on directly. **What shipped across the sub-suite**:
sum-type syntax + generic params + multi-arg constructors
(v5.8.21); exhaustive `match` coverage + diagnostic (v5.8.22);
lib/tagged.cyr migration to compiler-generated sum types
(v5.8.23) — Option/Result/Either replace 6 hand-rolled
constructor fns; enum table cap bump 256→1024 (v5.8.24); arm-
tag dedup (v5.8.25); ecosystem hardening — sakshi directory-
symlink fix + CLAUDE.md snapshot-ping-pong protection doc +
hashmap key_type migration (v5.8.23/v5.8.26). **Compiler-
internal infrastructure**: 4 new heap regions (var_enum_id /
enum_count / enum_variant_count / enum_name) + 8 accessor fns
in util.cyr. **Codegen unchanged across the sub-suite for
match** — coverage check is metadata-only; runtime cmp/jcc-
skip cascade still picks first matching arm. **Downstream pin
audit**: 10 consumers all pinned at pre-v5.8.21 cyrius
(mabda/sigil/yukti/phylax/sakshi/vani/patra/cyrius-doom @
5.7.48; vidya @ 5.8.19; yantra @ 5.6.17 stale). Pin bumps are
downstream-repo operations (separate git cycles); audit
identifies the work, doesn't execute it. **Honest scope-
shrunk items cascaded forward**: bare-name auto-tagging in
mixed enums (paren-consistent migration sufficient);
cyrius-vet 80%-cap pre-warn (fail-fast diagnostic adequate).
cc5 unchanged at **737,888 B**. Verification: self-host two-
step byte-identical, check.sh 64/64, all sub-suite tcyrs
green (enum_generics 31/31, exhaustive_match 10/10,
match_dedup 10/10, tagged 14/14, enums 10/10), 0 false-
positive coverage/dedup warnings, 0 directory-level lib/
symlinks across ~/Repos. v5.8.x cycle progress: **27 of 44
pinned slots shipped (61.4%)**. **Last release in this work
session — handoff to un-versioned doc/vidya pass next** per
user direction 2026-05-03 ("we will do a doc and vidya pass
after not attached to a release. As handoff/wrapup"). Phase 2
continuing post-handoff: Result<T,E>+? (v5.8.28–v5.8.32),
allocators (v5.8.33–v5.8.38). Phase 3 closeout v5.8.39–v5.8.44;
cycle backstop at v5.8.49.)

**Tagged-unions sub-suite (v5.8.21–v5.8.27) — COMPLETE
2026-05-03**:

| Slot      | Theme                                              | Δ cc5  |
|-----------|----------------------------------------------------|--------|
| v5.8.21   | Sum-type syntax + constructor parsing              | +2,272 |
| v5.8.22   | Exhaustive pattern match in `match`                | +2,568 |
| v5.8.23   | Stdlib pass 1: lib/tagged.cyr migration            | -48    |
| v5.8.24   | Cap bump 256 → 1024                                | 0      |
| v5.8.25   | Arm-tag dedup                                      | +776   |
| v5.8.26   | Stdlib pass 2 + ecosystem hardening                | 0      |
| v5.8.27   | Sub-suite closeout                                 | 0      |
| **Total** |                                                    | **+5,568** |

**5.8.26** (shipped 2026-05-03 — **v5.8.x SLOT 26 — stdlib
adoption pass 2 + ecosystem hardening**. Phase 2 language-
vocabulary slot, sixth of the tagged-unions sub-suite
(v5.8.21–v5.8.27). Ships the cascaded items from v5.8.23.
**Bite #1 (CLAUDE.md)**: extended "Downstream repo setup
(ecosystem rule)" section with directory-level `lib/`
symlink finder + new "Snapshot-ping-pong protection" subsection
documenting the repo→snapshot→repo loop discovered v5.8.23
mid-bite-2 (root cause: `install.sh --refresh-only` copies
lib/*.cyr into ~/.cyrius/versions/<v>/lib/ which then ping-
pongs back via `cyrius deps`). Mitigation: 3-step recipe
(edit → manually refresh snapshot → check.sh). **Bite #2
(lib/hashmap.cyr)**: hashmap key_type migration — replaced
raw 0/1/2 int literals at map header offset 24 with named
symbolic constants `enum KeyType { KeyTypeCstr; KeyTypeStr;
KeyTypeU64; }`. Auto-incremented tag values match prior raw-int
exactly so pre-migration call shapes keep working. 6 sites
updated across the file (3 store + 3 load/comparison; pin
estimated 12, empirically 6). Pure ergonomic — no API or
runtime behavior change. **Bite #3**: symlink audit
re-verification — 0 directory-level `lib/` symlinks remain
(sakshi's v5.8.23 fix holds; all other downstream repos have
only single-file dep symlinks, which are the legitimate
`cyrius deps` output). cc5 unchanged at **737,888 B**
(compiler not touched; only stdlib + CLAUDE.md changed).
Verification: self-host two-step byte-identical, check.sh
64/64, hashmap migration survives `version-bump.sh 5.8.26`
snapshot refresh (protection-doc workflow followed without
incident — edit → snapshot refresh → check.sh, no
ping-pong reversion this time). All v5.8.25 + v5.8.24 +
v5.8.23 + v5.8.22 + v5.8.21 regressions intact. v5.8.x cycle
progress: **26 of 44 pinned slots shipped (59.1%)**. Phase 2
continuing: tagged-unions sub-suite closeout (v5.8.27),
Result<T,E>+? (v5.8.28–v5.8.32), allocators (v5.8.33–v5.8.38).
Phase 3 closeout v5.8.39–v5.8.44; cycle backstop at v5.8.49.)

**5.8.25** (shipped 2026-05-03 — **v5.8.x SLOT 25 — exhaustive-
match arm-tag dedup**. Phase 2 language-vocabulary slot, fifth
of the tagged-unions sub-suite (v5.8.21–v5.8.27). Cascaded from
v5.8.22 follow-ups. Single-bite slot. Fixes the false-clean
coverage math: pre-bite, `match s { A => ..., A => ... }` over
a 3-variant enum counted as 2-of-3 covered (false-clean —
adding any third arm made it 3-of-3 silently); now emits BOTH
`duplicate match arm 'A'` warning + `non-exhaustive ... covers
1 of 3` (accurate — only unique arms contribute). **Bite
(parse.cyr)**: PARSE_MATCH stack-allocates `seen_vcnt[256]` per
match; per arm, O(N²) linear scan for prior occurrence of
arm's vcnt. Duplicate emits diagnostic + skips coverage bump;
new arm appends + bumps as before. **Dedup keyed by `vcnt`**
(variant-var-index, unique program-wide) instead of tag value —
avoids the v5.5.2 `enum_const_val` fold table's 1024-vcnt cap.
**Codegen unchanged** — runtime `cmp/jcc-skip` cascade still
picks first matching arm. cc5 grew **737,112 → 737,888 B
(+776 B)** for the scan loop + diagnostic. New
`tests/tcyr/match_dedup.tcyr` 10/10 locks runtime first-match-
wins behavior on dup-first / dup-middle / triple-dup. 0
false-positive duplicate warnings during self-host or stdlib
compile (no existing match has dups). Verification: self-host
two-step byte-identical, check.sh 64/64, all v5.8.24 + v5.8.23
+ v5.8.22 + v5.8.21 regressions intact, standalone smoke probe
confirms both warnings emit on the dup-non-exhaustive case.
v5.8.x cycle progress: **25 of 44 pinned slots shipped (56.8%)**.
Phase 2 continuing: stdlib adoption pass 2 (v5.8.26 — absorbs
hashmap key_type migration + downstream symlink audit/cleanup +
snapshot-ping-pong protection doc), tagged-unions closeout
(v5.8.27), Result<T,E>+? (v5.8.28–v5.8.32), allocators (v5.8.33–
v5.8.38). Phase 3 closeout v5.8.39–v5.8.44; cycle backstop at
v5.8.49.)

**5.8.24** (shipped 2026-05-03 — **v5.8.x SLOT 24 — exhaustive-
match table cap bump 256 → 1024**. Phase 2 language-vocabulary
slot, fourth of the tagged-unions sub-suite (v5.8.21–v5.8.27).
Cascaded from v5.8.22 follow-ups. Single-bite slot. Audit at
slot entry: cyrius stdlib has 299 enum decls (cc5 self-host
doesn't trip prior cap because include chain pulls only
math/slice/syscalls_macos); downstream pressure is real — vani
120, yukti 91, sigil 69, patra 46, mabda 42 — composed multi-dep
programs were 1-2 releases from tripping. Empirical fail-fast
confirmed pre-bump: 300-enum probe correctly errored. **Cap
bump**: `SENUMC` check `>= 256` → `>= 1024`; diagnostic text
updated 52→53 bytes (same encoding length); `enum_variant_count[]`
grew 2KB → 8KB at 0x214008; `enum_name[]` grew 2KB → 8KB and
moved 0x214808 → **0x216008** to accommodate. Six accessor
fns from v5.8.22 updated. Heap-map comment in src/main.cyr
updated. `var_enum_id[8192]` at 0x204000 unchanged (variant
cap is a separate bucket — no realistic consumer near 8192
variants). Total metadata-band growth +12 KB; heap brk reaches
0x368C000. **Honest scope-shrink**: pin's `cyrius vet` 80%-cap
warning deferred — would need new vet-tool instrumentation hook;
fail-fast diagnostic already gives clear error before silent
overflow. cc5 unchanged at **737,112 B** (constants encode at
same instruction length whether literal is 256 or 1024).
Verification: self-host two-step byte-identical, check.sh 64/64,
pre-bump 300-enum probe now passes, post-bump 1100-enum probe
correctly fails with new diagnostic, all v5.8.23 + v5.8.22 +
v5.8.21 regressions intact. v5.8.x cycle progress: **24 of 44
pinned slots shipped (54.5%)**. Phase 2 continuing: arm-tag dedup
(v5.8.25), stdlib adoption pass 2 (v5.8.26 — absorbs hashmap
key_type migration + downstream symlink audit/cleanup + snapshot-
ping-pong protection doc), tagged-unions closeout (v5.8.27),
Result<T,E>+? (v5.8.28–v5.8.32), allocators (v5.8.33–v5.8.38).
Phase 3 closeout v5.8.39–v5.8.44; cycle backstop at v5.8.49.)

**5.8.23** (shipped 2026-05-03 — **v5.8.x SLOT 23 — stdlib
adoption pass 1: `lib/tagged.cyr` migration to compiler-
generated sum types**. Phase 2 language-vocabulary slot, third
of the tagged-unions sub-suite (v5.8.21–v5.8.27). First real
consumer of v5.8.21 sum-type syntax + v5.8.22 exhaustive-match
machinery. **Bite #1 (parse_types.cyr)**: empty-parens nullary
tagged variant — pre-v5.8.23 `Foo()` collapsed to arity-1
(16-byte alloc with garbage payload from unconsumed rdi); now
`alloc(8)`, tag at +0, no payload, no params. Removed v5.8.21's
`if (ctor_arity == 0) { ctor_arity = 1; }` collapse; codegen
falls through naturally to arity-0 with `EMOVI(8 + 0*8) =
EMOVI(8)`, frame size `(0 + 1) * 16 = 16`. **Bite #2
(lib/tagged.cyr)**: replaced 3 hand-rolled tagged-union types
with compiler-generated sum types — `enum Option { None();
Some(v); }`, `enum Result { Ok(v); Err(e); }`, `enum Either
{ Left(v); Right(v); }`. Tag values match prior NONE=0/SOME=1
etc. convention; helper bodies (`is_none`/`is_some`/`unwrap`/
`unwrap_or`/`result_unwrap`/`err_code_of`/`is_left`/`is_right`)
updated to reference lowercase variant names which fold via
`enum_const_val` to identical tag values. `tagged_new`/`tag`/
`payload`/`is_tag` primitives + `option_print`/`result_print`
unchanged. **Shape change**: `None()` is now 8 bytes (tag-only)
vs prior 16 bytes (tag + zero payload); `payload(None())`
direct-call would now read OOB but no helper does this (all
check `is_none` first). 3 downstream tcyrs intact: `tagged.tcyr`
14/14, `stdlib.tcyr`, `enum_generics.tcyr` 31/31.
**Symlink corruption discovery**: mid-bite-2, `lib/tagged.cyr`
edits reverted between Edit calls — the CLAUDE.md-documented
ecosystem corruption pattern. Root cause: `version-bump.sh`'s
`install.sh --refresh-only` hook + `cyrius deps` re-resolution
in `check.sh` ping-pong files between repo `lib/` and
`~/.cyrius/versions/<v>/lib/`. Mitigated by manual snapshot
update mid-bite. Surfaced: `/home/macro/Repos/sakshi/lib`
is a symlink to `~/.cyrius/lib` — exactly the pattern
CLAUDE.md warns against. **Audit + cleanup queued for v5.8.26
stdlib pass 2.** **Honest scope-shrink**: pin's hashmap
`key_type` migration + dynlib error codes + json/toml parse
state premise-checked — empirically `lib/json.cyr` /
`lib/toml.cyr` had **0 ad-hoc tag dispatch hits** (parsers
use direct char-matching, not tag+union state machines);
`lib/fdlopen.cyr` 2 hits (marginal); `lib/hashmap.cyr` 12 hits
(real but pure ergonomic — internal int-const → enum const
rename, not API change). Symlink-corruption ceremony per `lib/`
edit makes per-file migrations costly; **hashmap key_type
migration deferred to v5.8.26** alongside symlink audit. cc5
**737,160 → 737,112 B (-48 B)** — slight shrink from collapse
removal + EMOVI constant-fold on arity-0 path. Verification:
self-host two-step byte-identical, check.sh 64/64, all v5.8.22
+ v5.8.21 + v5.8.20 regressions intact, standalone migration
probe confirms None/Some/Ok/Err/Left/Right shapes + helpers.
v5.8.x cycle progress: **23 of 44 pinned slots shipped (52.3%
— past halfway)**. Phase 2 continuing: cap-bump (v5.8.24),
arm-tag dedup (v5.8.25), stdlib adoption pass 2 (v5.8.26 —
absorbs hashmap key_type migration + downstream symlink
audit/cleanup), tagged-unions closeout (v5.8.27), Result<T,E>+?
(v5.8.28–v5.8.32), allocators (v5.8.33–v5.8.38). Phase 3
closeout v5.8.39–v5.8.44; cycle backstop at v5.8.49.)

**5.8.22** (shipped 2026-05-03 — **v5.8.x SLOT 22 — exhaustive
pattern match in `match`**. Phase 2 language-vocabulary slot, second
of the tagged-unions sub-suite (extended v5.8.21–v5.8.25 →
v5.8.21–v5.8.27 via this slot's cap-bump + dedup cascade).
Compiler-emitted warning when a `match` over an enum value
misses one or more variants and has no `_ =>` opt-out — same
warn-not-error policy as v5.6.x #must_use / #deprecated and
v5.8.20 #pure→#io. **Bite #1 (infrastructure)**: per-variant →
parent-enum bookkeeping. New heap regions extending the
metadata band past `fn_flags`: `var_enum_id[8192]` at 0x204000
(64 KB, 1-based; 0 = not a variant), `enum_count[8]` at 0x214000
(cap 256), `enum_variant_count[256]` at 0x214008 (2 KB),
`enum_name[256]` at 0x214808 (2 KB). PARSE_ENUM_DEF in pass 1
bumps eid + writes all four. Six new accessor fns in
util.cyr (GVENUMID/SVENUMID, GENUMC/SENUMC, GENUMVCNT/SENUMVCNT,
GENUMNM/SENUMNM). +1,016 B. **Bite #2 (consumer + diagnostic)**:
PARSE_MATCH peeks each arm's first ident pre-PCMPE; if it
resolves to a variant of an enum, records the parent eid.
First variant arm sets primary `match_eid`; subsequent variant
arms must share that eid (mismatch → "match arms span multiple
enums" diagnostic, exhaustive-coverage check skipped). After
arms close: if eid set AND `_ =>` not present AND covered <
total → "non-exhaustive match over enum 'X' — covers N of M
variants; add `_ =>` to opt out" warning. +1,552 B.
**Codegen unchanged** — metadata-only check. Self-host stays
byte-identical. **§22 SCOPE NOTE**: ships coverage check +
diagnostic only — known follow-ups cascaded as new pinned slots
**v5.8.24 (cap bump)** + **v5.8.25 (arm-tag dedup)** so they
ship after v5.8.23's stdlib migration validates real-world
consumer pressure. cc5 grew **734,592 → 737,160 B (+2,568 B)**.
Verification: self-host two-step byte-identical, check.sh
64/64, pre-existing `enums.tcyr` 10/10 + `tagged.tcyr` 14/14
intact (no regressions in match runtime correctness), new
`tests/tcyr/exhaustive_match.tcyr` 10/10 across 3 groups
(exhaustive match runtime correctness, non-exhaustive with
`_ =>` runtime correctness, literal-int match no-fire).
Standalone smoke probe confirms warning text on three paths
(missing variants, mixed enums, exhaustive). **0 false
positives** during self-host or stdlib compile. All v5.8.21
regressions intact (`enum_generics.tcyr` 31/31), v5.8.20
regressions intact (`effect_annotations.tcyr` 7/7, slices 159/159).
v5.8.x cycle progress: **22 of 44 pinned slots shipped (50% —
exactly halfway after the +2 cascade)**. Phase 2 continuing:
stdlib adoption pass 1 (v5.8.23 — `lib/tagged.cyr` migration +
bare-variant consistency precondition), cap-bump (v5.8.24),
arm-tag dedup (v5.8.25), stdlib adoption pass 2 (v5.8.26),
tagged-unions closeout (v5.8.27), Result<T,E>+? (v5.8.28–
v5.8.32), allocators (v5.8.33–v5.8.38). Phase 3 closeout
v5.8.39–v5.8.44 (api-surface refresh at v5.8.44); cycle
backstop holds at v5.8.49 (5-slot headroom v5.8.45–v5.8.49).)

**Slot-map cascade +2 at v5.8.22 ship**: 42 → 44 pinned slots,
backstop holds at v5.8.49. Per-user 2026-05-03 "lets cascade
the remaining items - cap bump then dedup after previous .23
work" — known follow-up bites moved into discrete pinned slots
v5.8.24 + v5.8.25 instead of being absorbed into v5.8.22's
ship. Tagged-unions sub-suite extends from v5.8.21-v5.8.25 to
v5.8.21-v5.8.27. Downstream phases shift +2: Result<T,E>+?
v5.8.28-v5.8.32, allocators v5.8.33-v5.8.38, Phase 3 closeout
v5.8.39-v5.8.44 (api-surface refresh at v5.8.44).

**5.8.21** (shipped 2026-05-03 — **v5.8.x SLOT 21 — sum-type
syntax + constructor parsing**. Phase 2 language-vocabulary
slot. Generalizes the existing single-arg `enum Foo { A; B(v); }`
constructor capability into the full pinned canonical shape
`enum Result<T, E> { Ok(T), Err(E) }` — generic-parameter syntax,
comma variant separators, and multi-arg variant constructors
`Foo(a, b, c)`. Reuses existing enum/struct infrastructure:
REGFN registration, alloc helper call, tag-then-payload heap
layout — extends parse loops + scales codegen by arity, no new
heap regions. **Generics**: `SKIP_GENERICS(S)` after the enum
name in `PARSE_ENUM_DEF`, mirroring `PARSE_STRUCT_DEF` /
`PARSE_UNION_DEF`. Type params are syntactically accepted but not
yet bound semantically (mono-only, erasure semantics — full
binding lands when monomorphization arrives post-v5.8.x).
**Comma separator**: separator check `PEEKT(S) == 5` →
`PEEKT(S) == 5 || PEEKT(S) == 31` (token 31 = `,`). Mixed `,`/`;`
in same decl tolerated. **Multi-arg variants**: ident-loop
parses `Foo(a, b, c)`; codegen scales — `8 + 8*arity` byte
alloc, params stored to slots `0..arity-1`, alloc-ptr to slot
`arity`, tag at +0, payload[i] at +8 + 8*i; frame size
`(arity + 1) * 16`. **Byte-identity preserved** for arity-1
case (matches the v5.5.2 single-arg corpus exactly). **Cascaded
into this slot** from v5.8.20: directive-token tolerance
(Pass 1 + Pass 2 top-level scanner) for tokens 122 (#must_use),
124 (#deprecated), 125 (#pure), 126 (#io), 127 (#alloc) —
fix for v5.8.20's annotation ramp landing where an annotated
fn at the top of a stdlib file silently truncated Pass 1's
pre-scan; plus the demo annotation ramp itself
(`sys_open/close/read/write` `#io`, `u128_eq/u128_is_zero`
`#pure`). **§21 SCOPE NOTE**: ships syntax + codegen capability
only — `lib/tagged.cyr` stdlib migration to compiler-generated
sum types is **v5.8.23 stdlib adoption pass 1**; bare-variant
payload-shape consistency (so `Nothing` unifies with
`Just(v)` shape) is the precondition for that migration and
pinned to v5.8.23 alongside; arity validation at call sites
+ exhaustive `switch` match are separate slots (v5.8.22 next).
cc5 grew **732,320 → 734,592 B (+2,272 B)** across four
in-flight bites: directive-tolerance (+1,792) + generic-skip
(+16) + comma-separator (+80) + multi-arg-variants (+384).
Verification: self-host two-step byte-identical, check.sh
64/64, pre-existing `enums.tcyr` 10/10 + `tagged.tcyr` 14/14
intact (no regressions in library-level tagged-union API),
new `tests/tcyr/enum_generics.tcyr` 31/31 across 9 test groups
(non-generic regression floor, `<T>`, `<T, E>`, payload
roundtrip, comma separator, mixed separators, `Triple(a,b,c)`,
`Pair(x,y)` with auto-increment tag, multi-arg payload
roundtrip with zero/negative). All v5.8.20 regressions intact
(`effect_annotations.tcyr` 7/7, 9 slices regressions 159/159).
v5.8.x cycle progress: **21 of 42 pinned slots shipped (50%
— exactly halfway)**. Phase 2 continuing: exhaustive `switch`
match (v5.8.22), then stdlib adoption (v5.8.23–v5.8.24,
absorbing the `lib/tagged.cyr` migration deferred from this
slot + bare-variant unification precondition), Result<T,E>+?
(v5.8.26–v5.8.30), allocators (v5.8.31–v5.8.36). Phase 3
closeout v5.8.37–v5.8.42 (api-surface refresh at v5.8.42);
cycle backstop v5.8.49.)

**5.8.20** (shipped 2026-05-02 — **v5.8.x SLOT 20 — per-fn
effect/purity annotations (`#pure` / `#io` / `#alloc`)**.
Phase 2 effects slot — first slot after the slices true-
completion sub-arc closeout. Three new fn-attribute decorators
that the parser tags into `fn_flags[fi]` (bits 3 / 4 / 5).
PARSE_FNCALL + PARSE_RETURN tail-call path enforce: when the
current fn body is `#pure` AND the callee has bit 4 (#io) or
bit 5 (#alloc) set, emit a `warning:<file>:<line>: #pure fn
calls #io|#alloc fn '<name>'` line. Same shape as #must_use /
#deprecated diagnostics — easy downstream incremental adoption.
**Lexer**: 3 new byte-pattern recognizers + token IDs (125 =
HASH_PURE, 126 = HASH_IO, 127 = HASH_ALLOC). **Parser**: 3 new
pending-flag globals + `_cur_fn_is_pure` mirror set in
PARSE_FN_DEF and reset at fn-end alongside `_cur_fn_regalloc`.
**Enforcement**: both call paths covered — PARSE_FNCALL for
normal calls, PARSE_RETURN's tail-call branch for `return
helper(args);` (which historically bypasses PARSE_FNCALL —
v5.8.16 §8's tail-call escape skip work surfaced this code
path). **Warnings, not errors** — same trade-off as
#must_use / #deprecated; downstream consumers annotate
incrementally; `cyrius lint --strict` escalation reserved as
follow-up. **§20 SCOPE NOTE**: ships the directive
infrastructure only — annotation ramp across stdlib (mark
keccak/sha1/u128 leaves `#pure`, mark sys_write/alloc/
vec_push `#io`/`#alloc`) is opt-in per consumer; mass-touch
isn't in scope this slot. cc5 grew **727,960 → 732,320 B
(+4,360 B)** for the lex patterns + dispatch + flag transfer
+ enforcement. Verification: self-host two-step byte-
identical, check.sh 64/64, all 9 slices regressions intact
(159 assertions), new `tests/tcyr/effect_annotations.tcyr`
7/7 across 3 groups (#pure body produces correct values,
#pure roundtrips identical to unannotated, #pure composes
through arithmetic), standalone smoke probe confirms warning
text on both PARSE_FNCALL + tail-call paths. v5.8.x cycle
progress: 20 of 42 pinned slots shipped (47.6% — past
halfway). Phase 2 continuing: tagged unions next
(v5.8.21–v5.8.25), then Result<T,E>+? + allocators.
Phase 3 closeout v5.8.37–v5.8.42; cycle backstop v5.8.49.)

**5.8.19** (shipped 2026-05-02 — **v5.8.x SLOT 19 — slices §11:
TRUE sub-arc closeout. Slices true-completion sub-arc COMPLETE
(§6-§11, v5.8.14-v5.8.19, 6 slots, 159 slice assertions across
9 tcyrs, +6,024 B compiler size delta).** Doc-only / verification
slot — no compiler or stdlib code change. Sub-arc retrospective:
§6 element-type tracking (parser branches + GSLICE_W/SSLICE_W +
parallel-array stash at 0x193400); §7 bounds-aware `s[i]` (10
helpers in lib/slice.cyr + PARSE_FACTOR slice-subscript branch +
pre-existing 16-byte fn-local SFLC bump fix); §8 dot-syntax
`.ptr` / `.len` (load + store) + 16-byte fn-local layout-flip +
tail-call escape skip for `&local` args; §9 pointer-to-struct
dot-syntax capability (auto-detect via sentinel-name check) +
Str fn-param SLTYPE tagging; §10 three slice-typed wrapper
helpers (sys_read_slice / slice_copy_bytes / slice_eq_bytes,
additive); §11 closeout retrospective. **Honest scope-shrunk
during sub-arc**: §9/§10 pivoted from mass migration to
capability-only on twice-reverted lib/fs.cyr pilot signal —
mass call-site sweep stays opt-in per file as consumers earn
the change. Var-side subscript syntax + dot-syntax also opt-in
follow-up (fn-local scope today; ~99% of subscripting happens
inside fns anyway). **Honest scope-EXPAND during sub-arc**:
§7 absorbed the layout-collision fix (precondition for correct
indexing); §8 absorbed both layout-flip and tail-call escape
skip (regalloc/TCO interactions with the new layout couldn't
be deferred). cc5 unchanged at **727,960 B** (closeout slot
has no code change). Verification: self-host two-step
byte-identical, check.sh 64/64, all 9 slices regressions green
(9+26+15+12+24+21+23+14+15 = 159 total). v5.8.x cycle progress:
19 of 42 pinned slots shipped (45% — past halfway). Phase 2
next: v5.8.20 effects, then tagged unions (5), Result<T,E>+?
(5), allocators (6); Phase 3 closeout at v5.8.37-v5.8.42
(api-surface refresh pinned at v5.8.42); cycle backstop at
v5.8.49 (7-slot headroom v5.8.43-v5.8.49 reserved for
surface-during-cycle items + final closeout). **Premise-check
discipline payoff**: three of six sub-arc slots had pin
premises empirically wrong; 5-line probe at slot entry caught
each in time to honestly expand or shrink scope without
silently dropping work. v5.6.x deferment-rate disaster
explicitly avoided.)

**5.8.18** (shipped 2026-05-02 — **v5.8.x SLOT 18 — slices §10:
slice-typed wrapper helpers (`sys_read_slice`, `slice_copy_bytes`,
`slice_eq_bytes`)**. Fifth slot of the slices true-completion
sub-arc. Premise-check at slot entry flipped the deliverable —
the original pin called for a 454-site sweep (sys_read 53 +
memcpy 332 + memeq 69) plus the §9-deferred ~80-site
str_data/str_len migration. Empirical counts came in smaller
(sys_read 8 + memcpy 110 + memeq 96 + str helpers 81 ≈ 295
sites) and a pilot migration of `lib/fs.cyr` was reverted twice
in-flight — clear signal that mass call-site churn isn't wanted
this slot. §10 ships the API capability; mechanical sweep
moves to a future slot once a downstream consumer earns the
change. Three new helpers in lib/slice.cyr, additive: takes
slice POINTERS like the rest of the slice API; `sys_read_slice`
unpacks (ptr, len) and forwards to sys_read; `slice_copy_bytes`
truncates against the shorter slice (avoids the memcpy(n)
foot-gun); `slice_eq_bytes` treats length-mismatch as unequal
by definition. The 454-site re-port pain the cycle-compression
argument was meant to prevent doesn't materialize from the
helper-fn API existing — downstream code calling memcpy(dst,
src, n) keeps working; the new helpers exist for code that
wants the slice shape, not as a forced replacement. cc5
unchanged at **727,960 B** — wrappers are stdlib for user
programs, not used by the compiler. Verification: self-host
two-step byte-identical, check.sh 64/64, all 7 prior slices
regressions intact (121 assertions: 9+26+15+12+24+21+14), new
`tests/tcyr/slice_byte_helpers.tcyr` 15/15 across 7 test groups
(equal-length copy, dst-shorter truncation, src-shorter
truncation, equality on equal contents, equality on differing
contents, length-mismatch is unequal, copy/eq round-trip).
sys_read_slice smoke-tested via stdlib's existing syscall
probes (real-fd machinery doesn't fit cleanly in tcyr). §11
next: TRUE sub-arc closeout — downstream consumers rebuild
against the new helper surface area; acceptance gates
extended; sub-arc retrospective + lessons learned from the
§9 / §10 honest scope-shrink calls.

**Slot-map cascade +1 at v5.8.18 ship**: 41 → 42 pinned slots,
soft backstop ~.44 → ~.49 (mirroring v5.7.49's end-of-cycle
backstop role; per-user 2026-05-02 "include api surface work
in the 5.8.x workflow; we can backstop with 5.8.49 again").
New v5.8.42 slot pinned for `cyrius_api_surface` refresh +
auto-build wiring + null-byte-in-shell-substitution fix —
the gate has been silently skipping since v5.7.50 because the
binary stopped getting auto-built and the Apr-29 snapshot is
2 minor releases stale. v5.8.43-v5.8.49 reserved as headroom
for surface-during-cycle items + final closeout backstop.)

**5.8.17** (shipped 2026-05-02 — **v5.8.x SLOT 17 — slices §9:
pointer-to-struct dot-syntax capability + Str fn-param SLTYPE
tagging**. Fourth slot of the slices true-completion sub-arc.
Premise-check at slot entry flipped the scope: original pin
assumed `s.data` / `s.len` already worked on Str-typed locals
and §9 was just a stdlib migration; empirically dot-syntax
returned 0 because PARSE_FIELD_LOAD's local-struct branch
treated every struct-typed local as inline (v5.5.36 path), but
`var s: Str = str_from(...)` actually stores a heap pointer in
a single slot. PARSE_FIELD_LOAD/STORE extended to auto-detect
pointer-vs-inline by checking if slot lli-1 has the sentinel
name -1 (indicates v5.5.36 inline-struct filler); if yes, use
`EFLADDR_X1` (lea — slot IS the struct's bytes); otherwise use
`EFLLOAD + EMOVCA` (mov — slot HOLDS the struct's pointer).
PARSE_FN_DEF's param-decl loop now calls FINDSTRUCT on every
`: Type` annotation and tags the slot with SLTYPE = -sid when
the type resolves to a struct, so `param.field` on a `: Str`
parameter routes through the struct-typed-local branch instead
of compile-erroring. Backward-compatible with the existing
string-literal auto-coerce. **Honest scope shift**: pinned scope
was 30-site stdlib migration; empirical scope was 81 sites + a
`: Str` annotation per site (most stdlib fns take untyped
params). A demo migration of lib/fs.cyr was prepared and
reverted in-flight per user signal — capability ships now,
mass migration moves to v5.8.18 §10 which was already pinned
for the bigger 454-site sys_read/memcpy/memeq sweep. Folding
the str_data/str_len migration into §10 keeps capability +
migration cleanly separated and gives §10 a worked example to
scale up from. cc5 grew **727,368 → 727,960 B (+592 B)** for
the pointer-vs-inline dispatch and param-decl SLTYPE tagging.
**§9 SCOPE NOTE**: dot-syntax fires only when the local or
param has the `: Str` (or other struct) annotation; untyped
locals storing Str pointers fall through to the existing error
path. Verification: self-host two-step byte-identical, check.sh
64/64, all 6 prior slices regressions intact (107 assertions),
new `tests/tcyr/str_dot_syntax.tcyr` 14/14 across 5 test groups
(Str local declarations, fn parameters, str_new buffers,
arithmetic composition, direct heap mutation visibility). §10
next: stdlib migration of str_data/str_len + the original 454-
site sweep.)

**5.8.16** (shipped 2026-05-02 — **v5.8.x SLOT 16 — slices §8:
dot-syntax field access `s.ptr` / `s.len` + 16-byte fn-local
layout-flip + tail-call escape skip for `&local` args**. Third
slot of the slices true-completion sub-arc; three intertwined
deliverables that ship together because the regalloc / tail-call
interactions only surface when all three are in place.
PARSE_FIELD_LOAD/STORE local-ident branch grew a slice short-
circuit: when GSLICE_W(lli) > 0 AND field name parses as `ptr` or
`len`, lower the dot access to address-based memory I/O via the
canonical-slot address (`EFLADDR_X1` + optional `EADDIMM_X1(8)` +
`ELODC` / `ESTOC`). Both fields go through this pattern even
though `.ptr` could have used direct `EFLLOAD` against the slot
— necessary for symmetry and avoids a regalloc-pinning landmine
on `.len` (the picker would have allocated rbx for the high half
and patched `mov [rbp+disp], rax` to `mov rbx, rax`, leaving the
actual stack slot uninitialized). **Pre-existing 16-byte fn-local
layout bug fixed**: pre-fix the canonical slot was at the higher
address and `&slice + 8` overflowed past the local frame into
saved-rbp territory; `slice_set` clobbered saved rbp, `slice_len`
read it back. Round-tripped within a fn so §7 indexing worked by
luck. `slices_typing.tcyr`'s `return slice_len(&x);` form passed
because main's rbp = 0 from C runtime. Fix flips the allocation:
high-half slot allocated FIRST (slot li, higher address),
canonical slot SECOND (slot li+1, lower address). Name + meta on
li+1 so FINDLOCAL returns the canonical, EFLADDR(li+1) yields the
lower address, EFLADDR(li+1) + 8 lands on the high half. Init the
high half via address-based memory store rather than EFLSTORE so
the regalloc picker doesn't pin rbx to it. **Tail-call escape
skip**: PARSE_RETURN's TCO detector now scans args for the `&`
token; if any arg passes `&local`, skip TCO and emit a normal
call. Required because the tail-call epilogue deallocates the
current frame BEFORE jumping to the callee, leaving any `&local`
the callee reads pointing at dead stack. Pre-§8 masked for
slices because the high half was on saved rbp; the §8 layout-
flip moves it into a real slot whose post-epilogue value is
arbitrary. Conservative — disables TCO for any `&` in args
(false-positive on `&global`, but rare and only loses the
optimization). cc5 grew **725,704 → 727,368 B (+1,664 B)** for
PARSE_FIELD_LOAD/STORE branches + layout-flip + tail-call scan.
**§8 SCOPE NOTE**: same as §7 — dot-syntax fires only inside the
local-ident branch; top-level slice vars still need slice_ptr /
slice_len helpers. Var-side support reserved as the same follow-
up slot. Verification: self-host two-step byte-identical, check.sh
64/64, all 6 prior slices regressions intact (9+26+15+12+24+21 =
107 assertions), new `tests/tcyr/slices_field_access.tcyr` 23/23
across 6 test groups (dot-syntax matches helper API, .len = N
truncates view, .ptr = expr rewrites view start, composition with
§7 subscript, both [T] and slice<T> ident forms, width-aware .len
is element count, zero-init both-halves contract). §9 next: Str
API migration.)

**5.8.15** (shipped 2026-05-02 — **v5.8.x SLOT 15 — slices §7:
bounds-aware indexing `s[i]` + fix to a long-latent fn-local
16-byte slot-collision bug**. Second slot of the slices true-
completion sub-arc. Surfaces §6's element-width data into a real
syntactic deliverable: `s[i]` on a slice-typed fn-local lowers
to `_slice_idx_get_W(&s, i)` via the width-specific helper.
PARSE_FACTOR's local-ident branch reads `GSLICE_W(S, li)`; if
non-zero AND next token is `[`, emits `EFLADDR/EPUSHR/PCMPE/
EPUSHR/ECALLPOPS/ECALLFIX` — the helper (`_slice_idx_get_{1,2,
4,8,16}` looked up via `_FINDFN_CSTR`) bounds-checks then loads
via the right-width `load{8,16,32,64}`. Width-16 returns a
POINTER to the u128 slot (cyrius's i64-only ABI). 10 new helpers
in `lib/slice.cyr`: `_slice_bounds_trap` + 5 bounds-checked
`_slice_idx_get_W` + 5 unchecked `slice_unchecked_get_W` for
perf hot paths. **Pre-existing slot-collision bug fixed**: two
adjacent fn-local 16-byte vars (slices, u128) shared a stack
slot because PARSE_VAR only bumped local count by +1; fix bumps
by +2 for `scalar_type==16` AND clears the high slot's name/
depth/type/slice-w to prevent stale state surfacing as
spurious "duplicate variable" errors. Bug had been silent since
v5.5 because no tcyr exercised adjacent fn-local 16-byte vars
(slices_codegen tested only top-level vars, which use
`var_sizes` and DO get full 16 bytes). **§7 SCOPE NOTE**:
subscript syntax works on fn-local slices; top-level vars
still need helper-fn API directly — var-side support reserved
as follow-up if a consumer asks (in practice ~99% of subscripts
happen inside fns). Editor integration folded in: new
`.lsp.json` at repo root pointing `cyrius-lsp` at all
`.cyr`-family extensions, new `docs/editor-integration.md`,
README.md "Editor Integration" section. cc5 grew **724,432 →
725,704 B (+1,272 B)**. Verification: self-host two-step
byte-identical, check.sh 64/64, all 5 prior slices regressions
intact (9+26+15+12+24 = 86/86), new
`tests/tcyr/slices_indexing.tcyr` 21/21 PASS across 8 test
groups (widths 1/2/4/8/16, both `[T]` / `slice<T>` ident forms,
arithmetic composition, variable index loop, u128 pointer-
return shape), OOB/negative bounds-trap behavior verified via
smoke probes (exit 134 + stderr msg), u128 collision fix
verified independently. §8 next: dot-syntax field access
`s.ptr` / `s.len`.)

**5.8.14** (shipped 2026-05-02 — **v5.8.x SLOT 14 — slices §6:
TYPE_SLICE element-type tracking infrastructure**. First slot of
the **slices true-completion sub-arc** (v5.8.14-v5.8.19) absorbing
the deferred work the v5.8.9-v5.8.13 foundation sub-arc shipped
without — per user direction "complete the task as assigned, the
cycle's backstop was sized for full delivery, not half-shipped
features". Added per-local element-width tracking via
parallel-array stash at heap offset 0x193400 (576 entries × 8B,
matching local_types extent). New helpers `GSLICE_W`/`SSLICE_W`
in `src/common/util.cyr`. PARSE_VAR's `[T]` and `slice<T>`
branches restructured to extract T's element-type identifier and
decode byte width (1/2/4/8/16 + STRUCTSZ for struct elements).
Local-emission path adds `SSLICE_W(S, li, slice_elt_w)` after
SLTYPE so element width is recorded per local slot. Why parallel
array vs packed encoding: packed conflicted with existing `lt > 0`
/ `lt < 0` consumer checks; parallel array exploits 19KB free
space between local_types end (0x193400) and gvar_toks start
(0x198000) — no heap reshuffle. §6 is pure infrastructure (data
has NO consumer until §7 reads it for sized indexing); semantic
verification deferred to §7. cc5 grew **721,936 → 724,432 B
(+2,496 B)** for parser branches + helpers + SSLICE_W call site.
Verification: self-host two-step byte-identical, check.sh 64/64,
all 4 prior slices regressions intact (9/9 + 26/26 + 15/15 +
12/12 = 62/62), new `tests/tcyr/slices_typing.tcyr` 24/24 PASS
across 7 test groups covering all 22 element-type variants.
**Slot-map cascade +6 at this ship**: cycle total 35 → 41
pinned slots, 9-slot → 3-slot headroom against ~.44 backstop.
§7 next: bounds-aware indexing `s[i]` using §6 element widths.)

**5.8.13** (shipped 2026-05-02 — **v5.8.x SLOT 13 — slices §5
closeout: sub-arc retrospective + acceptance gates + downstream
audit**. Fifth and final slot of the 5-patch slices sub-arc.
Doc-only patch — no code change. **Slices sub-arc COMPLETE
(v5.8.9-v5.8.13)**: shipped 62 slice assertions across 4 tcyrs
(slices_parse 9, slices_codegen 26, slices_str_interop 15,
slices_vec_interop 12), 11 helpers in lib/slice.cyr (slice_set/
of/ptr/len/zero/copy/eq/is_empty/is_null + slice_from_cstr/
slice_from_buf + vec_as_slice), 3 doc-blocks (str.cyr, vec.cyr,
slice.cyr), ~190 LOC, +552 B cc5. Auto-discovered by check.sh's
`tests/tcyr/*.tcyr` walker — no new gate wiring. Honest scope-
shrunk during sub-arc: TYPE_SLICE AST kind (no AST tree in main
parser), bounds-aware indexing (no element-type tracking), dot-
syntax field access (struct-path unification), Str-API migration
(Str ALREADY a slice<u8> structurally), hashmap slice getters
(32-byte header isn't contiguous-element shape), 454-site
read/memcpy/memeq migration (multi-slot scope) — all pin
candidates held until consumer pain surfaces. Downstream audit
2026-05-02: **5 of 7 deps cross-build clean** for aarch64
(sigil 3.0.0, mabda 2.5.0, sankoch 2.2.3, sakshi 2.2.2, patra
1.9.2); 2 failures (yukti 2.2.1, vani 0.9.1) hit pre-existing
patra/aarch64 SYS_OPEN class noted at v5.8.4 audit — NOT a
slices regression. cc5 unchanged at **721,936 B**. Verification:
self-host two-step byte-identical, check.sh 64/64, all 4 slices
tcyrs 62/62 PASS. Phase 2 progress: ✅ slices (5 slots),
v5.8.20 next = per-fn effect annotations.)

**5.8.12** (shipped 2026-05-02 — **v5.8.x SLOT 12 — slices §4:
vec ↔ slice<T> structural-prefix equivalence + scope-shrink
doc**. Fourth of the 5-patch slices sub-arc. Honest scope-shrink
during slot: original description was "vec/hashmap slice getters
+ read/memcpy migration"; reality at slot entry — vec fits
(first 16 bytes byte-identical to slice prefix), hashmap doesn't
(32-byte header `(entries_ptr, capacity, count, key_type)` is
not a contiguous-element shape), migration of sys_read/memcpy/
memeq is 454 call sites = multi-slot scope. Documented vec's
structural equivalence in both `lib/vec.cyr` and `lib/slice.cyr`
headers; vec values pass directly to slice_ptr / slice_len /
slice_is_empty / slice_is_null / slice_eq (all read offsets 0
and 8 only). Added `vec_as_slice(dst, v)` to lib/slice.cyr —
copies vec's slice-prefix into a 16-byte stack slot; documented
as snapshot semantics (dst's ptr may invalidate if vec_push
reallocs the backing). Migration of 454 call sites deferred —
opt-in once helpers exist; held until a consumer surfaces
measurable pain. cc5 unchanged at **721,936 B** — stdlib-only
patch. Verification: self-host byte-identical, check.sh 64/64,
new `tests/tcyr/slices_vec_interop.tcyr` 12/12 PASS, all prior
slices tcyrs intact (9/9 + 26/26 + 15/15). §5 next: sub-arc
closeout — acceptance gates, downstream audit.)

**5.8.11** (shipped 2026-05-02 — **v5.8.x SLOT 11 — slices §3:
Str ↔ slice<u8> structural equivalence + stack-slice builders**.
Third of the 5-patch slices sub-arc. Honest scope-shrink during
slot: original description was "Str → slice<u8> wrapper (API
stays byte-compatible)", but Str's internal layout investigation
surfaced that Str is ALREADY a slice<u8> structurally — `str_new`
does `alloc(16); store64(s, data); store64(s + 8, len)` — byte-
identical to a 16-byte stack slice. Documented the structural
equivalence in both libs' headers; a Str-typed value passes
DIRECTLY to any slice helper (slice_ptr / slice_len /
slice_is_empty / etc.) without conversion. Only difference:
lifetime (heap vs stack). Added 2 stack-slice builders to
lib/slice.cyr — `slice_from_cstr` (analog of str_from) and
`slice_from_buf` (analog of str_new) — for cases where heap
allocation is undesirable. No migration of Str's API: would
break every existing consumer's call sites across stdlib + 8
deps + downstream; structural equivalence makes that migration
unnecessary. cc5 unchanged at **721,936 B** — stdlib-only patch.
Verification: self-host byte-identical, check.sh 64/64, new
`tests/tcyr/slices_str_interop.tcyr` 15/15 PASS, §1+§2
regressions intact (9/9 + 26/26). §4 next: vec/hashmap slice
getters + read/memcpy migration.)

**5.8.10** (shipped 2026-05-02 — **v5.8.x SLOT 10 — slices §2
codegen: 16-byte alloc + field-access helpers**. Second of the
5-patch slices sub-arc. Parser change in `parse_decl.cyr`'s
PARSE_VAR: `[T]` branch now sets `scalar_type = 16` after
consuming the syntax (reuses u128's existing 16-byte stack-slot
path); `slice<T>` ident form gets the same treatment via 5-byte
"slice" name-match (0x6563696C73 little-endian) in the scalar-
type fallthrough. Both forms now allocate identical 16-byte
slots. New `lib/slice.cyr` ships 9 helpers: slice_set / slice_of /
slice_ptr / slice_len / slice_zero / slice_copy / slice_eq /
slice_is_empty / slice_is_null — all take a slice POINTER (&s)
mirroring u128/struct-by-pointer convention. Dot-syntax field
access (s.ptr / s.len) not wired (would require unifying
struct-field path with scalar_type=16 — separate scope); bounds-
aware indexing deferred (needs element-type tracking the parser
doesn't have). Both pin candidates for §X follow-ups if
consumers ask. cc5 grew **721,848 → 721,936 B (+88 B)**.
Verification: self-host two-step byte-identical, check.sh 64/64,
new `tests/tcyr/slices_codegen.tcyr` 26/26 PASS across 8 test
groups (16-byte alloc, helper roundtrips, copy/eq/empty/null
semantics, both forms produce identical slices), §1 regression
intact (9/9). §3 next: Str → slice<u8>.)

**5.8.9** (shipped 2026-05-02 — **v5.8.x SLOT 9 — Phase 2 opens;
slices §1 parse-acceptance + slot-map cascade +4**. First
substantive Phase 2 slot. Slot-map re-pin: slices originally
single-slot; honest scope-check at slot entry (premise-check
pattern) surfaced this needs the same 5-patch sub-arc shape as
Tagged unions / Result / Allocators. Re-pinned as v5.8.9-v5.8.13;
cascading effect annotations / tagged unions / Result / allocators
/ Phase 3 by +4 each. Cycle total 31 → **35 pinned slots**, 9-slot
headroom against ~.44 backstop. Slices §1 implementation: type-
position parse-acceptance for `slice<T>` (Rust-like generic) and
`[T]` (Go-like bracket) forms. Pure parser change in
`parse_decl.cyr`'s PARSE_VAR type-annotation block — added LBRACKET
branch alongside existing pointer / scalar / struct branches;
`slice<T>` already parse-accepted via existing ident +
SKIP_GENERICS path. No codegen, no type-tracking, no AST tree —
cyrius's main parser doesn't have type AST kinds (only TS
frontend does); §1 makes the syntax LEGAL, §2 lands the (ptr, len)
struct lowering + field access. cc5 grew **721,384 → 721,848 B
(+464 B)** for the new branch. Verification: self-host two-step
byte-identical, check.sh 64/64, new `tests/tcyr/slices_parse.tcyr`
9/9 PASS across `[u8]` / `[i32]` / `[i64]` / `[*i64]` / `[u128]` /
`slice<u8>` / `slice<i64>` / `slice<*i64>` + §1 contract
assertion (both forms produce byte-identical untyped emit).
Sub-arc plan: §2 codegen, §3 Str → slice<u8>, §4 vec/hashmap
slice getters + memcpy migration, §5 closeout.)

**5.8.8** (shipped 2026-05-02 — **v5.8.x SLOT 8 — phylax #4
NI-class duplicate-fn investigation: STALE PIN, closed by
upstream churn**. Last slot of Phase 1. Premise-check at slot
entry surfaced that the issue doesn't reproduce at v5.8.7 +
sigil 3.0.0 — closed by sigil's own 3.0.0 release (specifically
the `[lib].modules` section-header fix that landed in sigil 2.9.5
and merged into 3.0.0). Cyrius's pin to sigil 3.0.0 at v5.7.49
deps refresh transitively closed phylax-reported residue.
Verified clean across three reproduction paths (sigil src/lib.cyr
aarch64 cross, programs/smoke.cyr aarch64 cross, sigil tcyr suite
96/96). Doc-only patch — cc5 unchanged at **721,384 B**, check.sh
64/64. No new regression gate (cross-repo coupling not justified
for sigil-manifest-shape-specific issue; sigil's own CI catches
manifest regressions). Future polish slot could add cross-repo
gates if recurrence justifies. **Phase 1 complete (v5.8.1-v5.8.8);
Phylax #1/#2/#3/#4 all closed; sakshi cross-arch noise closed;
mabda Class A1 closed.** Pattern reaffirmed: project memory's
"premise-check at slot entry" — v5.7.x had 4-of-5 stale advanced-
TS items; v5.8.x had 1-of-31 here. Phase 2 (language vocabulary,
slots 9-26) opens at v5.8.9.)

**5.8.7** (shipped 2026-05-02 — **v5.8.x SLOT 7 — `_SC_ARITY`
cross-arch false-positive gate (phylax #3 + sakshi)**. Closes 11
spurious `syscall arity mismatch` warnings on `cyrius build
--aarch64` of any stdlib-including program. Root cause: the
`_SC_ARITY(n)` table at `src/frontend/parse_expr.cyr:10-53` maps
**x86_64** syscall numbers to expected arg counts; on aarch64 the
same numerical values denote DIFFERENT syscalls (e.g. aarch64
`SYS_NEWFSTATAT=79` == x86 `getcwd`, aarch64 `SYS_FSTAT=80` == x86
`chdir`, aarch64 `SYS_PIPE2=59` == x86 `execve`). aarch64's
at-family wrappers call e.g. `syscall(SYS_NEWFSTATAT, AT_FDCWD,
path, buf, 0)` legitimately with 4 user args; parser checked
against x86's getcwd arity (2) and warned. Single-line fix in
`parse_expr.cyr:589`: gate the arity check to `_AARCH64_BACKEND
== 0`. Hand-written aarch64 syscalls with wrong arity now get
runtime errors instead of compile warnings — acceptable tradeoff
(warning was best-effort, not load-bearing). Why not v5.7.8-shape
table-pin per entry: those corrections would break x86's reading
of the same numbers; arches need separate tables. Future polish
slot could add `_SC_ARITY_AARCH64(n)` to restore arity warnings
on aarch64 numbers — held until a consumer surfaces an aarch64
arity bug. cc5 grew **721,352 → 721,384 B (+32 B)** for the gate;
cc5_aarch64 grew matching. Verification: pre-fix `cyrius build
--aarch64` 4-line probe = 11 arity warnings; post-fix = 0;
check.sh 64/64; bench 15/15; x86 arity warnings still fire on
deliberate-mismatch x86 probe (gate's conditional preserves x86
behavior). Phylax #3 + sakshi cross-arch noise items both close
when consumers pin v5.8.7+.)

**5.8.6** (shipped 2026-05-01 — **v5.8.x SLOT 6 — `sys_stat` /
`sys_fstat` x86_64 wrapper backfill (phylax #2)**. Cross-arch
stdlib surface symmetry. Pre-v5.8.6, `lib/syscalls_x86_64_linux.cyr`
exposed the `SYS_STAT`/`SYS_FSTAT` enum slots but lacked wrapper
fns; aarch64's stdlib (`lib/syscalls_aarch64_linux.cyr:346-353`)
had both. Consumers calling `sys_stat(path, buf)` portably hit
`undefined function` warnings on x86. Phylax + agnosys's
`src/fuse.cyr` carried local backfills; v5.8.6 lets them drop
those. Fix: 4 LOC of fn definitions in
`lib/syscalls_x86_64_linux.cyr` (sys_stat → direct SYS_STAT
syscall; sys_fstat → direct SYS_FSTAT) plus a one-line doc
comment to satisfy the per-fn doc-coverage gate. Block comment
header documents the cross-arch shape (x86 has direct stat/fstat;
aarch64 routes through newfstatat with AT_FDCWD because the
direct stat was dropped in favor of the at-family). cc5
unchanged at **721,352 B** — stdlib-only change. Verification:
self-host two-step byte-identical, check.sh 64/64, x86 smoke
(`sys_stat("/etc/hostname", &buf)` → rc=0, st_size in sanity
bounds), cyrdoc 60 documented / 0 undocumented. Phylax + agnosys
can drop their local backfills on next pin bump. Out-of-scope
finding: api-surface snapshot has drift (null-byte parse abort
in the tool's distfile scan); pre-existing; pinned for v5.8.37
closeout doc-sync.)

**5.8.5** (shipped 2026-05-01 — **v5.8.x SLOT 5 — aarch64 SSH-gate
extension for `f64_log2` (phylax #1 hardware verification)**.
v5.8.4 closed the parser-side phylax-blocker (replaced hard-reject
with stdlib polyfill dispatch); this slot extends the v5.7.31
SSH-gate (`tests/regression-aarch64-f64-polyfill.sh`) with 4 new
log2 assertions and confirms bit-accuracy on real aarch64
(pi). Carved out from v5.8.4 per user direction after pi-live
status surfaced post-`79eeae4` commit; rather than amend a
published commit, the SSH gate ships as its own slot. cc5
unchanged at **721,352 B**; `build/cc5_aarch64` cross-compiler
rebuilt at 421,072 B (+424 B matching cc5's v5.8.4 dispatch
growth) so the regression script's raw cross-build picks up the
new f64_log2 parser branch. Verification: SSH gate PASS on pi
(`PASS: aarch64 f64_exp / f64_ln / f64_log2 polyfills bit-
accurate within ulp budget on pi (v5.7.31 + v5.8.4)`); check.sh
64/64; gate description updated to v5.7.31+v5.8.4. **Phylax #1
now FULLY closed** — parser dispatch (v5.8.4) + hardware-verified
polyfill (v5.8.5). Slot map cascades all originally-pinned v5.8.5–
v5.8.36 by +1 (sys_stat backfill → v5.8.6, _SC_ARITY → v5.8.7,
NI-class → v5.8.8, slices → v5.8.9, etc.); 31 pinned slots total
v5.8.1–v5.8.37 with 13-slot headroom against ~.44 backstop.)

**5.8.4** (shipped 2026-05-01 — **v5.8.x SLOT 4 — `f64_log2`
aarch64 polyfill (phylax #1 unblock)**. First substantive stdlib
slot of v5.8.x. Pre-v5.8.4: `cyrius build --aarch64` hard-rejected
`f64_log2` with `is x86-only for v5.6.0`; phylax CI ran
`continue-on-error: true` on the aarch64 lane because Shannon
entropy is load-bearing across the YARA / strings / analyze
pipeline. Fix mirrors v5.7.30/31 f64_exp/f64_ln shape: new
`_f64_log2_polyfill` in `lib/math.cyr` (one-liner via change-of-
base `log2(x) = ln(x) * F64_LOG2E`, leveraging the v5.7.31
`_f64_ln_polyfill` underneath); `parse_expr.cyr:1162` hard-reject
replaced with aarch64 dispatch block (~22 LOC mirroring the
v5.7.31 ln branch). New `F64_LOG2E` global hoisted from
`_f64_exp_polyfill`'s local for cross-polyfill reuse. cc5 grew
**720,928 → 721,352 B (+424 B)** for the new dispatch code.
Verification: self-host two-step byte-identical, check.sh 64/64,
bench 15/15, x86 smoke (`f64_log2(8) → exit 3`), math.tcyr
extended +9 assertions for log2 native + polyfill + ulp-tolerance
comparison (45/45 PASS). Aarch64 hardware SSH gate
(`tests/regression-aarch64-f64-polyfill.sh` on Pi) extended with
4 new log2 cases — all bit-accurate within budget on real
hardware; check.sh gate text updated to v5.7.31+v5.8.4. cc5_aarch64
cross-compiler rebuilt at 421,072 B (+424 B from new dispatch).
Script bypasses `cyrius build`'s auto-prepend so the separate
patra/aarch64 `SYS_OPEN`-not-defined blocker (which v5.8.5+
addresses) doesn't trip this gate.)

**5.8.3** (shipped 2026-05-01 — **v5.8.x SLOT 3 —
`src/frontend/ts/parse.cyr` fmt sweep follow-up**. Closes the
v5.8.0 fmt-sweep deferral that was blocked by the 128 KiB
cyrlint/cyrfmt cap (mabda A1) — v5.8.1 raised the cap to
524 KiB, this slot applied fmt to the file. Pre-sweep: 4532
lines / 195,483 B. Post-sweep: 4532 lines / 195,173 B (-310 B
canonical whitespace normalization; line-count preserved per
the v5.8.0 mabda-A1-aware fmt-loop pattern). cc5 unchanged at
**720,928 B** — parser-source whitespace doesn't reach lexed
TOK_LITERAL surface so emit is unaffected. Verification:
self-host two-step byte-identical, check.sh 64/64, bench 15/15.
All 25 v5.8.0-era first-party drift files now canonical;
remaining un-swept files are vendored distlib artifacts —
`lib/sandhi.cyr` (sandhi v1.0.0 fold), and 8 symlinked dep
distfiles — owned upstream and intentionally not swept.)

**5.8.2** (shipped 2026-05-01 — **v5.8.x SLOT 2 — `cc5_aarch64`
release-tarball placement fix + `build/cyrc_check` orphan delete**.
Paired build-tree hygiene; release.yml + working-tree changes
only, zero compiler impact. Pre-v5.8.2: `release.yml:101`
staged `build/cc5_aarch64` to `$STAGE/` (tarball top-level) while
local `install.sh:100` always placed it under `bin/` — release
tarball was the outlier, breaking every downstream consumer
(sakshi/yukti/patra/mabda) that copies `bin/*` to
`~/.cyrius/bin/` (cc5_aarch64 silently dropped → aarch64 cross-
build fails with `compiler not found`). Fix: one-line `$STAGE/`
→ `$STAGE/bin/` in release.yml, plus inline-comment correction
of the prior "dev tool" rationale. Plus `rm build/cyrc_check`
(12,344-byte orphan with zero refs, surfaced in 2026-05-01 P(-1)
audit §4). cc5 unchanged at **720,928 B**. Verification: self-host
two-step byte-identical, check.sh 64/64, bench 15/15. Downstream
consumers can drop their workaround lines once pinned to v5.8.2+;
cyrius's side is unblocked.)

**5.8.1** (shipped 2026-05-01 — **v5.8.x SLOT 1 — `cyrlint` /
`cyrfmt` 128 KiB buffer cap raise + `cyrius-prompt-info`
redundancy fix**. First patch of the v5.8.x 30-slot cycle.
Tooling-side bump only — `programs/cyrlint.cyr` +
`programs/cyrfmt.cyr` raised 131,072 B → 524,288 B (4× distlib
v5.7.36 precedent shape, 4× scaling for fmt output-growth
headroom; 6 occurrences total: 2 in cyrlint, 4 in cyrfmt
covering input read + `--check` _out_buf + `--write` _out_buf).
Closes mabda Class A1 (mabda `backend_native.cyr` at 137 KiB
was hitting the truncation), unblocks v5.8.3 ts/parse.cyr fmt
sweep (195 KiB; verified post-bump fmt round-trips cleanly at
4532/4532 lines). Plus `scripts/cyrius-prompt-info` pkg-mode
output cleanup: drop `name` when `name == repo` so segments
read `ॐ 5.8.0 (cyrius)` instead of redundant `ॐ cyrius 5.8.0
(cyrius)`. cc5 unchanged at **720,928 B** — compiler untouched,
self-host two-step byte-identical. Verification: check.sh 64/64,
bench 15/15, smoke-tested cyrius/vidya/sigil prompt segments.)

**5.8.0** (shipped 2026-05-01 — **v5.8.x CYCLE OPENS —
optimization + bug-fix theme + vani fold-in + cyriusly icon rework**.
Triple-anchor cut: P(-1) fmt-sweep finish (24 first-party files
canonicalized; ts/parse.cyr at 195 KB skipped pending the v5.8.x
lint/fmt 128 KB cap-raise slot) + vani audio distlib fold-in (vani
0.9.1 added as `[deps.vani]`; `lib/audio.cyr` 236 LOC retired;
3 preprocessor-cap test fixtures migrated to `lib/vani.cyr`) +
cyriusly starship.toml two-segment rework (🌀 cyclone for toolchain
+ ॐ Om for packages, format `<pkg-icon> name version (repo) | 🌀 ver`,
backed by new `scripts/cyrius-prompt-info` helper). cc5 unchanged at
**720,928 B** — fmt sweep added +8 B (whitespace into TOK_LITERAL),
5.8.0 version-string shortening (5 vs 6 chars × 3 arch literals + pad)
reclaimed exactly 8 B; coincidence-clean. Verification: self-host
two-step byte-identical; check.sh 64/64; `cyrius bench` 15/15 PASS
(baseline for v5.8.x optimization arc captured); 8 deps resolve
clean (was 7 at v5.7.50; vani added). v5.7.x final tally stays at
51 patches; v5.8.x soft backstop ~.44.)

**5.7.50** (shipped 2026-05-01 — **PRE-v5.8.0 P(-1) UNBLOCK —
v5.7.x cycle ends for real at 51 patches across 36 days**. Single-
issue config-only patch closing the BLOCKER surfaced in the pre-
v5.8.0 P(-1) audit (`docs/audit/2026-05-01-pre-5.8.0-audit.md`):
`cyrius bench` and `cyrius test` were both failing at compile
time with `error:lib/patra.cyr:101: undefined variable 'SYS_LSEEK'`
because cyrius's own `cyrius.cyml` was missing the `[deps].stdlib`
auto-prepend block that every other consumer (yukti / patra /
sigil / sankoch / sakshi / mabda) has had since their respective
folds. Latent at v5.7.48 too — patra 1.9.0 had identical SYS_LSEEK
refs at the same lines; v5.7.x's `scripts/check.sh`-based closeout
never went through the auto-prepend chain so the gap stayed
invisible until P(-1) ran `cyrius bench` end-to-end. Fix: 19-module
`[deps].stdlib` block added to cyrius.cyml (union of every dep's
own stdlib needs at v5.7.49 pin time). cc5 unchanged at **720,928 B**
(compiler unchanged — config + `src/version_str.cyr` regen only).
Verification: `cyrius bench` 15/15 PASS (was 2/13); `cyrius test`
unblocked; check.sh 64/64; self-host two-step byte-identical. **The
.50 headroom was held open from v5.7.42 closeout planning for
exactly this kind of late-cycle P(-1) finding — used once.** v5.8.x
slot list now opens with a clean `cyrius bench` baseline. **Cycle
final**: v5.7.0 ship 2026-03-26 → v5.7.50 ship 2026-05-01 = 51
patches across 36 days, longest minor in cyrius history by a
comfortable margin over v5.6.x's 45-patch prior record.)

**5.7.49** (shipped 2026-05-01 — **ECOSYSTEM DEPS REFRESH —
v5.7.x cycle ends at 50 patches across 36 days**. Final patch
of the v5.7.x minor; lands the downstream-check §10 work
deferred from v5.7.48 closeout per user direction. Five of
six pinned deps bumped to their latest released tags: sakshi
2.0.0 → **2.2.2** (minor×2 + patches), patra 1.9.0 → **1.9.2**
(2 patches), sigil 2.9.3 → **3.0.0** (major — audited safe
against cyrius), yukti 2.1.1 → **2.2.1** (minor + patch),
sankoch 2.1.0 → **2.2.3** (minor + patches). Plus transitive
agnosys refreshed to **1.0.4**. **Mabda held at 2.5.0** —
v3.0.0-rc.2 is on `main` awaiting rc.3 + soak window; cyrius
doesn't consume mabda's API (`lib/mabda.cyr` is a preprocessor-
cap test fixture, same role as sigil/sakshi/etc.), so the hold
is cost-free. **Sigil 3.0.0 audit**: zero impact on cyrius —
none of the breaking-change names (`TRUST_COMMUNITY`,
`alog_append_to_file`/`_load_from_file`, `SIGIL_BATCH_PARALLEL`)
match anywhere in `src/`/`lib/`/`programs/`/`tests/`/`benches/`
/`fuzz/`; sigil's "consumers" list (daimon, kavach, ark[ext],
aegis, phylax, mela, stiva, argonaut, takumi) are all
downstream of sigil, not part of cyrius itself; sigil 3.0.0's
declared min cyrius pin is 5.7.48 (the one we just closed).
**Hard cap respected**: cc5 byte-identical at **720,928 B** —
patch is dep symlinks + `src/version_str.cyr` regen only, no
compiler source change. **Verification**: self-host two-step
byte-identical; check.sh **64/64 PASS** (same gate count as
v5.7.48); `cyrius deps` resolves 7 deps clean; `build/cc5
--version` reports `cc5 5.7.49`. **Slot cascade**: v5.8.0
(bare-metal AGNOS kernel + RISC-V rv64 + Vani audio fold-in)
ahead. **Cycle final**: v5.7.0 ship 2026-03-26 → v5.7.49 ship
2026-05-01 = **50 patches across 36 days**, still the longest
minor in cyrius history.)

**5.7.48** (shipped 2026-04-30 — **TRUE CLOSEOUT BACKSTOP —
v5.7.x cycle complete**. Final patch of the v5.7.x minor —
**the longest minor in cyrius history at 49 patches across 35
days** (v5.7.0 ship 2026-03-26 → v5.7.48 ship 2026-04-30).
CLAUDE.md 11-step closeout-pass protocol run end-to-end. cc5
unchanged at **720,928 B** — closeout is verification + doc
sync, no compiler change. **Mechanical (§1-3) all PASS**:
self-host two-step byte-identical, bootstrap closure clean
(seed → cyrc → cc5), check.sh 64/64. **Judgment passes
(§4-8) all clean**: heap map 80 regions/0 overlaps; dead-code
floor stable at 36 (no v5.7.x additions); refactor pass already
done at v5.7.47 (-106 LOC); code review found no ABI leaks /
byte-order typos / silent errors; cleanup sweep clean (one
flag: `build/cc3` tracked but CLAUDE.md says only cc5 tracked
— pinned for separate user call). **Compliance (§9-10)**:
security re-scan clean, no new dangerous patterns; downstream
check pinned for v5.7.49 deps-only slot. **Docs (§11)**:
vidya `language.cyml` overview entry + `ecosystem.cyml`
refreshed to v5.7.48; new `field_notes/compiler.cyml` entry
for the v5.7.46 `fn`-as-param-name reserved-keyword gotcha.
**Cycle highlights**: sandhi fold at v5.7.0 (clean-break
consolidation, 469 fns into stdlib); cyrius-ts P-series
reaching 100% SY corpus (2053 + 435); advanced TS feature
suite (asserts/mapped/decorators/variadic-tuples/const-type-
params/audit-pass — 8/8 advanced-TS pin RETIRED at v5.7.46);
lib/json.cyr depth triple (pretty/streaming/JSON Pointer);
lib/test.cyr v1 (testing-framework split anchor); v5.7.47
refactor pass. **Compiler size delta**: 531 KB → **720,928 B**
(+~190 KB across 49 patches). **check.sh growth**: 26 → **64
gates** (+38). **Testing**: 97 tcyr files, **~3400 total
assertions** across TS + JSON + misc. **Stdlib**: 60 → **68
modules**. **Slot cascade**: v5.7.49 (deps refresh — no
compiler change; downstream §10 lands there) → v5.8.0
(bare-metal AGNOS kernel + Vani audio fold-in).
**Out of scope**: full security audit (due, pin v5.8.0
pre-cut); `build/cc3` tracking decision (flagged, pending
user call).)

**5.7.47** (shipped 2026-04-30 — **REFACTOR PASS — testing +
codebase**. Standalone slot per CLAUDE.md closeout-pass §6
("Refactor pass") carved out for audit-trail clarity rather
than bundling into v5.7.48 closeout. **Hard cap respected**:
cc5 stays byte-identical at **720,928 B** (unchanged from
v5.7.45). **Discovery (3-pronged)**: tcyr migration (1 win:
ts_parse_p56), arch-branch consolidation (nothing earned),
heap region audit (nothing earned). **Refactored**: (1)
`ts_parse_p56` (v5.7.45 const type params) — 13 parallel-
shape parse-rc cases collapsed from ~70 lines of inline
assertions to a single `test_each` call over (source, label)
pairs. tcyr now includes `lib/test.cyr` (transitively pulls
assert + fnptr — same one-include pattern as v5.7.42's
`lib/json.cyr` → `lib/fnptr.cyr` fix). (2) `lib/json.cyr`
`_jb_walk` + `_jb_walk_pretty` consolidation — two near-
identical ~50-line walkers (compact + pretty) merged into a
single `_jb_walk(sb, v, indent, level)` with `indent` param
driving the mode. `indent=0` = compact, `indent>0` = pretty.
`if (n > 0)` guard handles both modes for empty
containers correctly. **Skipped (deliberate)**:
`json_stream` scalar-inputs (heterogeneous post-conditions),
`ts_parse_p55` / `p57` (heterogeneous shapes). Per the v5.7.43
json_pointer §5 migration discipline — only homogeneous shapes
migrate; heterogeneous stay inline. **Verification**: cc5
unchanged at 720,928 B; all 4 JSON tcyrs PASS post-
consolidation (190 assertions); all 3 JSON regression gates
exact-byte cmp PASS; 4 TS group runners PASS post-p56-
migration (1181 assertions, same total — structure
consolidated); SY corpus 2053/2053 + 435/435 unchanged;
check.sh **64/64 PASS** (no new gate — refactor introduces
no new functionality). **LOC delta**: -106 net lines (lib/
json.cyr -54, tcyr -52) preserving 100% of assertion coverage.
**Slot cascade**: v5.7.48 (TRUE CLOSEOUT BACKSTOP) ahead. User-
authorized headroom v5.7.49-50 unused; planned finish at
v5.7.48 holds.)

**5.7.46** (shipped 2026-04-30 — **v5.7.x ADVANCED-TS PIN
AUDIT — 4 stale-pin items closed**. Third and final slot of
the v5.7.44-46 advanced TS feature suite. Reframed during
v5.7.45 ship from "feature implementation" to "audit-pass"
after empirical bisection found 4 of 5 remaining pin items
already parse rc=0. v5.7.46 locks the empirical findings via
formal regression gates + tcyr fixtures and **retires the
v5.7.x advanced-TS pin entirely**. **Zero compiler change** —
cc5 unchanged at **720,928 B**. **What landed**: (1) tcyr group
`ts_parse_p57` adds **25 new assertions** in 7 sub-groups
covering `as const` (4 sub-shapes), `satisfies` postfix (7
sub-shapes incl. TS 5.0 `as const satisfies` idiom),
`never`/`unknown` primitives (9 sub-shapes), conditional types
(basic / nested / `infer T` / distributive — 14 sub-shapes
incl. standard util types `Unwrap`/`ElementOf`/`ArgsOf`/
`ReturnT`/`Head`/`Tail`/`Filter`); (2) single combined gate
`tests/regression-ts-advanced-pin-audit.sh` (4ba) with 4
numbered sub-sections embedding real-world shapes pulled from
zod / react / redux / TS 5.0 routes-table patterns.
**Verification**: cc5 unchanged at 720,928 B; 4 TS group
runners clean (core 257 + decls 157 + advanced 197 (+25 from
172) + lex 570 = **1181 total TS assertions**); SY corpus
unchanged (2053/2053 .ts, 435/435 .tsx); check.sh **64/64
PASS** (was 63; +gate 4ba). **Pin list RETIRED**: all 8 items
✅ (mapped 5.7.25 / asserts 5.7.24 / decorators 5.7.26 /
variadic tuples 5.7.44 / const type params 5.7.45 / as const
+ satisfies + never/unknown + conditional types — all 5.7.46
audit). v5.7.x advanced-TS pin replaced in roadmap.md with
superseded note. **Slot cascade**: v5.7.47 (refactor pass) +
v5.7.48 (true closeout backstop) ahead. **Authorized
headroom v5.7.49-50 unused** — audit-pass surfaced no
additional gaps; planned finish at v5.7.48 holds. **Out of
scope (future polish)**: typed AST for conditional types
(`TS_AST_TYPE_CONDITIONAL` + `_INFER`); `as const` AST
tagging — both pinned behind future typechecker / tooling
consumer.)

**5.7.45** (shipped 2026-04-30 — **TS 5.0 CONST TYPE PARAMETERS
— `<const T>` parse acceptance**. Second slot of the v5.7.44-46
advanced TS feature suite. Picked from pin list per "highest-
friction at slot-claim time" + v5.7.44 premise-check pattern:
empirically test each remaining pin item before scoping.
**Premise-check findings**: of the 5 remaining advanced-TS pin
items, **4 already parsed rc=0** against current cc5 (`as
const`, `satisfies` postfix, `never`/`unknown` primitives,
conditional types in basic / nested / `infer` / distributive
forms); only `<const T>` had a real gap, failing with `code=3
tok=102` (TS_TOK_KW_CONST) at the type-parameter position.
The 4 already-passing items move to v5.7.46 audit-pass.
**Honest scope-shrink call**: third premise-check in a row
showing pinned items work — v5.7.44 was magnum→medium, v5.7.45
is medium→small. Called out to user; user authorized small fix
+ headroom up to v5.7.50 if more work surfaces. **What landed**:
~5 LOC in `TS_PARSE_TYPE_PARAMS` consuming optional
`TS_TOK_KW_CONST` before the IDENT expect. Per "parse loosely,
type strictly" — typechecker enforces const-only-in-type-param-
position, parser stays permissive. **Not added** (deliberate):
no AST emission for type params. Existing parser counts type
params but doesn't push `TS_AST_DECL_TYPE_PARAM` nodes; adding
emission only for `const`-modified params would be inconsistent.
AST emission pinned for a future slot if a typechecker consumer
surfaces. **Verification**: cc5 self-host two-step byte-
identical at **720,928 B** (was 720,864 at v5.7.44; +64 B);
`tests/tcyr/ts_parse_advanced.tcyr` group `ts_parse_p56` **13
new assertions** in 12 groups (plain on function/class/iface/
alias/method/arrow, with extends constraint, with default,
mixed `<T, const U, V>`, multiple const params, complex combo,
plain regression); 4 TS group runners clean (core 257 + decls
157 + advanced 172 + lex 570 = **1156 total TS assertions**);
`tests/regression-ts-const-type-params.sh` gate 4az 6 real-
world groups; check.sh **63/63 PASS** (was 62; +gate 4az).
**Pin list status** (8-item v5.7.x advanced-TS pin): **5 of 8
shipped** (mapped + asserts + decorators + variadic tuples +
const type params); 4 remaining all parse rc=0 today (`as
const`, `satisfies` postfix, `never`/`unknown` audit,
conditional types corpus) — v5.7.46 = audit-pass marking them
✅ with empirical proof. **Backstop**: user authorized headroom
to v5.7.50 if needed; planned finish stays at v5.7.48.
**Out of scope**: type-param AST emission (pin behind future
typechecker consumer); const-position enforcement (typechecker
concern).)

**5.7.44** (shipped 2026-04-30 — **TS VARIADIC TUPLE TYPES —
AST representation (`TS_AST_TYPE_REST`)**. First slot of the
v5.7.44-46 advanced TS feature suite. Picked from the pin list
at `roadmap.md §v5.7.x — patch slate` per the selection rule
"highest-friction at slot-claim time." **Honest premise check
at slot entry**: pin claimed multi-spread / leading-spread /
mixed forms "don't" work; empirical test of all 7 variadic
shapes returned rc=0 — the pin was stale at the parse-
acceptance layer. **Real gap was AST representation**: pre-
v5.7.44 `TS_PARSE_TYPE_TUPLE` consumed `...` silently. Scope
shrank from "magnum" to "medium" — called out honestly before
proceeding. **What landed**: (1) `TS_AST_TYPE_REST = 316` AST
kind (next free after `TS_AST_DECORATOR = 315`); payload[0] =
inner element type. (2) `TS_PARSE_TYPE_TUPLE` `is_rest` flag
tracks `...` presence; wraps element in REST after type +
optional wrapping. **Verification**: cc5 self-host two-step
byte-identical at **720,864 B** (was 720,640 at v5.7.43; +224
B); `tests/tcyr/ts_parse_advanced.tcyr` group `ts_parse_p55`
**18 new assertions** in 8 groups (single rest, trailing,
leading, multi-spread, mixed, labeled, optional+spread, plain-
tuple no-false-REST regression); 4 TS group runners clean
(core 257 + decls 157 + advanced 159 + lex 570 = **1143 total
TS assertions**); `tests/regression-ts-variadic-tuples.sh` gate
4ay 7 real-world-shape groups; check.sh **62/62 PASS** (was
61; +gate 4ay). **Pin list status** (8-item v5.7.x advanced-TS
pin): mapped / asserts / decorators ✅ (v5.7.25/24/26),
variadic tuples ✅ (v5.7.44); 5 remaining (`as const`, const
type params, `satisfies` postfix verify, `never`/`unknown`
audit, conditional types exhaustive corpus) distribute across
v5.7.45-46. **Out of scope (future polish)**: typechecker
emission on REST spread (future typechecker phase);
spread-position validation (`[...A, ...B]` typechecker
rejection — parser accepts per "parse loosely, type strictly"
precedent).)

**5.7.43** (shipped 2026-04-30 — **`lib/test.cyr` v1 — TABLE-
DRIVEN TESTING (`test_each`)**. First slot of the testing-
framework split decided 2026-04-30 after v5.7.42 ship. Surfaced
by in-tree pain: v5.7.40-v5.7.42 tcyr files had 3+ parallel-
shape assertion runs (json_pointer's RFC 6901 §5 corpus = 8
cases, json_stream scalars = 6, TS group runners' parallel
blocks). **What landed**: (1) new `lib/test.cyr` stdlib module
that transitively `include`s `lib/assert.cyr` + `lib/fnptr.cyr`
(one-include consumer pattern, same shape as v5.7.42's `lib/
json.cyr` → `lib/fnptr.cyr` fix); (2) `test_each(cases_vec, fp)`
dispatch — applies `fp` to every element via `fncall1`; null
inputs are silently no-ops; returns 0; failures account via
`lib/assert.cyr` globals; (3) Demo migration: json_pointer.tcyr
§5 block's 8 homogeneous (path → int) assertions converted to
a single `test_each` call (3 outliers stay inline — different
shapes); behavior preserved 36 → 36 PASS. **Slot cascade**:
backstop bumped v5.7.47 → v5.7.48 to absorb the v5.7.43
+ v5.7.47 split. Option-E test-harness pin (formerly v5.7.46
floating) retired unclaimed. **Verification**: zero compiler
change (lib-only); cc5 self-host two-step byte-identical at
**720,640 B**; `tests/tcyr/test_lib.tcyr` **12 assertions** in
4 groups (ordering, empty vec, null safety, single-element)
all PASS; `tests/regression-test-lib.sh` gate 4ax end-to-end
trace `0.1.2.3.4.\nend\n`; check.sh **61/61 PASS** (was 60;
+gate 4ax). **Deferred (v2, behind further consumer pressure)**:
`test_property` (quickcheck-style on top of `lib/random.cyr`),
fixture register/teardown helpers.)

**5.7.42** (shipped 2026-04-30 — **`lib/json.cyr` JSON POINTER
(RFC 6901)**. Third and final slot of the v5.7.20-pinned JSON
depth follow-up series. Closes the triple: pretty-print (5.7.40)
+ streaming (5.7.41) + pointer-walk (this slot) on the existing
tagged tree. **What landed**: (1) `json_v_pointer(v, ptr)` Str
entry — empty pointer returns root, non-empty must start with
`/`; (2) `json_v_pointer_cstr(v, ptr, plen)` explicit-len entry;
(3) `_jp_obj_lookup` length-explicit key match (handles
interior-NUL keys correctly); (4) `_jp_parse_idx` strict RFC 6901
§4 index parser (`0` or `[1-9][0-9]*`; `-` next-element token,
leading zeros, and non-digits all rejected → -1); (5)
`_jp_token_unescape` single-pass `~1`→`/` / `~0`→`~` with any
other `~X` rejected; equivalent to the spec's two-pass order
because only `~0`/`~1` are valid (no chained-rewrite possibility).
**Hygiene fix**: `lib/json.cyr` now `include`s `lib/fnptr.cyr` at
the top, closing the v5.7.41 incomplete-dep regression where
streaming-code references to `fncall1/2/3` tripped three
"undefined function" warnings on every consumer of lib/json.cyr.
Self-contained dep declaration matches the existing pattern in
17 other stdlib files. **Verification**: zero compiler change
(lib-only); cc5 self-host two-step byte-identical at **720,640
B**; `tests/tcyr/json_pointer.tcyr` **36 assertions** in 7
groups (empty pointer = root, obj key lookup with miss = 0, array
index with OOB / leading-zero / `-` / non-numeric all rejected,
deep nested mixed, RFC 6901 §5 corpus incl. `/a~1b` `/m~0n` `/`
`/k\"l` `/ `, error paths, trailing-slash empty-token descent)
all PASS; `tests/regression-json-pointer.sh` gate 4aw end-to-end
8-case exact-byte fixture; **all four JSON tcyrs clean** post-
fnptr-include (engine 71 + pretty 18 + stream 65 + pointer 36 =
190 assertions); check.sh **60/60 PASS** (was 59; +gate 4aw).
**JSON depth triple complete** — slot v5.7.20's three pinned
items all shipped, pin retired. **Slot cascade**: backstop
unchanged at v5.7.47. **Out of scope (future polish)**: JSON
Pointer mutation (`json_v_pointer_set`) — implicit ownership
questions, pending real consumer; relative JSON Pointer (draft
spec, mostly schema-engine-relevant).)

**5.7.41** (shipped 2026-04-30 — **`lib/json.cyr` STREAMING PARSER**.
Second slot of the v5.7.20-pinned JSON depth follow-up series.
Adds an event-driven push parser for multi-MB JSON inputs that
don't fit the tagged-tree memory model. **What landed**: (1) 11
event constants `JS_EV_OBJECT_START`..`JS_EV_ERROR` + `JS_EV_COUNT`
sentinel; (2) 96-byte handler struct (ctx + 11 fnptr slots); (3)
`json_stream_handler_new(ctx)` / `json_stream_on(h, event_id, fp)`
/ `json_stream_parse(buf, len, h)` / `json_stream_parse_str(src,
h)` public API; (4) Driver shares lex state with the tree parser
(`_jp_buf` / `_jp_len` / `_jp_pos` + `_json_err_msg` /
`_json_err_pos`) and reuses `_jp_skip_ws` / `_jp_parse_string` /
`_jp_atoi` / `_jp_atof` unchanged — kept the streaming surface to
~210 LOC instead of ~400. Callbacks fire via `fncall1` / `fncall2`
/ `fncall3` from `lib/fnptr.cyr`. **Verification**: zero compiler
change (lib-only); cc5 self-host two-step byte-identical at
**720,640 B**; `tests/tcyr/json_stream.tcyr` **65 assertions** in
9 groups (handler alloc + slot wiring incl. invalid event_id
rejection, 6 scalar shapes, empty containers, flat object 4 mixed
types, nested exact-byte event-order trace `{k[ii]k{ks}}`, array
of 3 objects, 4 error paths, selective-callback no-op, convenience
entries) all PASS; `tests/regression-json-stream.sh` gate 4av —
end-to-end fixture trace `{kskik[bn]k{ks}}` (16 events) + `OK`
rc=0; check.sh **59/59 PASS** (was 58; +gate 4av). **Slot
cascade**: backstop unchanged at v5.7.47. **Out of scope (future
polish)**: abort-on-callback (non-zero return as early-exit
signal) — pending consumer ask; streaming-from-fd with partial-
token buffering — likely belongs in sandhi RPC layer; combined
`on_value` super-event — trivial to layer when asked.)

**5.7.40** (shipped 2026-04-30 — **`lib/json.cyr` PRETTY-PRINTING**.
First slot of the v5.7.20-pinned JSON depth follow-up series. Adds
`json_v_build_pretty(v, indent)` on top of the existing tagged-
value tree. **What landed**: (1) `json_v_build_pretty(v, indent)`
public entry — `indent` is spaces-per-level; `indent <= 0` short-
circuits to compact `json_v_build(v)`; (2) `_jb_walk_pretty` walker
mirroring the existing `_jb_walk` shape with `": "` key separator
and parent-level indent before close brackets; (3) `_jb_emit_indent`
helper (LF + N spaces); (4) Empty `{}` and `[]` short-circuit to
bracket-pair with no internal whitespace, matching
`JSON.stringify(v, null, n)`. **Verification**: zero compiler
change (lib/json.cyr is not in cc5's include chain; src/main.cyr
only pulls src/); cc5 self-host two-step byte-identical at
**720,640 B**; `tests/tcyr/json_pretty.tcyr` **18 assertions** in
10 groups (indent fallback, scalars unchanged, empty containers
compact, array indent=2, object indent=2, nested mix, empty arr
inside obj, indent=4 step, two parse→pretty→parse→compact round-
trips on 51-char and 25-char fixtures, embedded `\n` re-escape
through pretty path) all PASS; `tests/regression-json-pretty.sh`
gate 4au — end-to-end fixture against canonical 8-line shape,
negative-case verified by deliberately reverting `": "` to `":"`;
check.sh **58/58 PASS** (was 57; +gate 4au). **Slot cascade**:
backstop unchanged at v5.7.47. **Out of scope (future polish)**:
configurable separator string (consumer-ask), sort-keys flag for
stable diffs (consumer-ask).)

**5.7.39** (shipped 2026-04-30 — **LSP CROSS-FILE GO-TO-
DEFINITION + DOCUMENT OUTLINE**. Extends `programs/
cyrius-lsp.cyr` from diagnostics-only to a navigation-capable
language server. Slot title was "LSP semantic-tokens polish";
honest sizing at slot entry split the framing — go-to-def is
the headline consumer-visible feature, semanticTokens is
internal polish that earns its own slot when a consumer asks.
**What landed**: (1) Symbol indexer with parallel-array table
(cap 4096), recursive include walker (project-relative then
file-relative fallback), idempotent via 256-entry indexed-path
set; (2) `textDocument/definition` handler — looks up IDENT
under cursor, returns Location across file boundaries; (3)
`textDocument/documentSymbol` flat `SymbolInformation[]` form
mapping cyrius kinds (fn/var/enum/struct/enum-member) to LSP
SymbolKind (12/13/10/23/22); (4) Capabilities advertise
`definitionProvider:true` + `documentSymbolProvider:true`; (5)
`cyrius-lsp` promoted from install-on-demand to default
release binary (`cyrius.cyml [release].bins`); VSCode
extension's `~/.cyrius/bin/cyrius-lsp` candidate now resolves
on a fresh install. **Verification**: cc5 self-host two-step
byte-identical at **720,640 B** (no compiler change);
cyrius-lsp: 22 KB → 65,456 B (+43 KB for ~430 LOC of
indexer + handlers + capability changes); check.sh **57/57
PASS** (was 56; +gate 4at `regression-lsp-definition.sh`
covering 5 sub-tests including cross-file
includer→included resolution); install snapshot 14 → 15
bins/scripts (cyrius-lsp joined). **Pinned long-term**: LSP
`textDocument/semanticTokens/full` (~150 LOC; deferred from
this slot's "polish" framing) + LSP `textDocument/references`
(~80 LOC; easy add on top of v5.7.39's symbol-table
infrastructure when a consumer asks). **Slot cascade**:
backstop unchanged at v5.7.47 — this slot landed inside the
v5.7.46 floating allocation.)

**5.7.38** (shipped 2026-04-30 — **`.scyr` (soak) + `.smcyr`
(smoke) FILE TYPES**. Two new test-discovery shapes mirroring
the existing `*.tcyr` / `*.bcyr` / `*.fcyr` walkers. Closes
the `cyrius soak` / `cyrius smoke` gap (only soak shape was
the hardcoded self-host loop; no smoke verb existed) and kills
the last Python3 dependency in the test surface
(`tests/regression-capacity.sh`'s 3500-fn synthesis →
POSIX shell loop). Originally bundled with LSP polish as the
v5.7.38 duo; honest sizing at slot entry flagged LSP as
substantially larger, user authorized splitting (LSP moved to
v5.7.39 own slot, backstop bumped v5.7.46 → v5.7.47). **What
landed**: (1) `cyrius smoke` subcommand — fail-fast walker
over `tests/smcyr/*.smcyr` + `smoke/*.smcyr`; (2) `cyrius
soak` extended to walk `tests/scyr/*.scyr` + `soak/*.scyr`
after the built-in self-host loop, with `_skip_deps`
save/restore guarding the built-in loop from manifest-dep
auto-prepend that would blow the 2MB expanded-source cap;
(3) Both verbs added to the auto-deps gate for harness-side
parity with `.tcyr`/`.bcyr`/`.fcyr`; (4)
`tests/regression-capacity.sh` Python3→shell-loop migration
(byte-identical output); (5) Example harnesses
`tests/smcyr/compile_minimal.smcyr` (minimal "fn returns
literal" smoke) + `tests/scyr/alloc_pressure.scyr` (10,000×
`alloc(4KB)` + sentinel readback, 40 MB total). **Verification**:
cc5 self-host two-step byte-identical at **720,640 B** (no
compiler change); check.sh **56/56 PASS** (was 55; +gate 4as
`regression-smoke-discovery.sh`); `cyrius soak 1` end-to-end
clean (self-host iter PASS + alloc_pressure.scyr PASS).
**Small pinned method**: `_skip_deps` save/restore is the
right pattern for any `cmd_*` that calls `compile()` against
sources near the 2MB cap; don't add commands to the
auto-deps gate without checking whether their `compile()`
calls would inflate.)

**5.7.37** (shipped 2026-04-30 — **TS TEST-ORG REWORK —
GROUP-LEVEL CONSOLIDATION**. Closes the load-bearing
prerequisite for the v5.7.42-v5.7.44 advanced-TS suite by
collapsing 24 individual `tests/tcyr/ts_*.tcyr` files into 4
topic-grouped runners (`ts_lex_combined`, `ts_parse_core`,
`ts_parse_decls`, `ts_parse_advanced`). Each runner includes
the TS frontend (~6,615 LOC of `lex.cyr` + `parse.cyr`)
ONCE per group instead of once per file. Initial agent
proposal was a single megafile runner; user pushback ("do you
GENUINELY think that one test runner is the optimum?")
surfaced the real trade-off — megafile trades 6× speedup for
blast-radius-of-the-whole-suite on any segfault and zero
scaling headroom. Group-level consolidation gets ~5× of the
speedup with isolation per topic. **Verification**:
`tests/regression-ts-*.sh` SY-corpus gates unchanged; cc5
self-host two-step byte-identical at **720,640 B** (no
compiler change); assertion-count parity 1117 = 1117 (verified
pre-deletion); TS suite compile time **4774ms → 926ms =
5.15× speedup**; check.sh **55/55 PASS**. **Long-term pin
(option E)**: TS test harness program — a single
`programs/ts_test_runner.cyr` consuming both internal-symbol
fn dispatch and TS fixture files. Claims a v5.7.x slot when
a downstream consumer surfaces a test pattern that doesn't
fit either current shape; until then group-level
consolidation is sufficient. **Slot cascade** (continuing the
v5.7.36 +1 cascade; user-authorized at this ship): backstop
bumped v5.7.45 → v5.7.46 to absorb option E pin. v5.7.45 is
floating slot for option E if pulled.)

**5.7.36** (shipped 2026-04-30 — **FRESH-INSTALL HARDENING +
DISTLIB CAP RAISE**. Bundled five tooling-quality items
surfaced by re-setting up the toolchain on a fresh Arch
install plus a mabda-surfaced distlib truncation, authorized
mid-execution by user direction "want to fix tests before
adding additional testing verbs." **What shipped**: (1)
`scripts/check.sh:329` syntax-error noise — backticks around
`if (r)` triggered command substitution every audit run;
switched to single quotes (closes warning-sweep finding #5).
(2) `scripts/check.sh` PATH fallback for `cyrfmt`/`cyrlint`
+ loud-FAIL when neither in `build/` nor on PATH — pre-
v5.7.36 a fresh checkout reported "skip: cyrfmt/cyrlint not
built" and counted nothing toward pass/fail, producing a
green "52/52 PASS" report on un-exercised gates. (3)
`cyrius distlib` per-module cap 64KB → 256KB
(`cbt/commands.cyr:894-895`) — mabda surfaced silent
truncation when modules grew past `alloc(65536)` /
`file_read_all(..., 65535)`. (4) `cyrlint` string-literal
awareness in `lint_globals_init_order` Pass-2 (pulled
forward from the v5.7.37 trio) — Pass-2 scan loop now skips
IDENTs inside `"..."` and `'...'` literals with `\\` / `\"`
/ `\'` escapes. (5) `cyriusly setup` verb — installs from
the current repo checkout (validates VERSION + cyrius.cyml
+ scripts/install.sh, bootstraps `build/cc5` if missing,
builds tools listed in `cyrius.cyml [release]`, delegates
to `install.sh --refresh-only`). End-to-end first-time
setup: `git clone && sh scripts/cyriusly setup`. Zero
compiler change; cc5 byte-identical at **720,640 B**.
check.sh **55/55 PASS** (was 52/52 going in; +2 from fmt/
lint gates now actually running via PATH fallback; +1 from
new gate 4ar `regression-distlib-large-module.sh`). New
test fixtures: `tests/regression-distlib-large-module.sh`
(synthesises a ~78KB module + sentinel, asserts bundle
contains the sentinel) and Test 4 in `regression-lint-
global-init-order.sh` (string-literal fixture with
forward-declared var named inside a `"..."`). Slot cascade
(user-authorized; relative order preserved): v5.7.37 ←
v5.7.36 was = TS test-org rework; v5.7.38 ← v5.7.37 was =
trio reduced to LSP polish + `.scyr`/`.smcyr` (string-lit
moved forward); v5.7.39-v5.7.41 ← v5.7.38-v5.7.40 were =
JSON depth series; v5.7.42-v5.7.44 ← v5.7.41-v5.7.43 were
= advanced TS suite; v5.7.45 ← v5.7.44 was = TRUE CLOSEOUT
BACKSTOP. Pinned method update: fresh-install rehearsal
once per minor (last: never; first: v5.7.36) — silent-skip
and per-module truncation modes are invisible to a developer
running from an active repo. Same audit-honesty failure
shape as v5.7.29's `set -e` / `tail` masking; same fix
shape (loud-FAIL when the test would otherwise skip).)

**5.7.35** (shipped 2026-04-28 — **STDLIB SYSCALL SURFACE GAPS
— agnosys-surfaced (drm/luks/security)**. Closes three coherent
stdlib additions that share the same shape: Linux syscalls
valid on both x86_64 and aarch64 but not exposed by
`lib/syscalls_*.cyr`. Filed by agnosys aarch64 portability work
as `docs/development/issues/stdlib-syscalls-aarch64-gaps-from-
agnosys.md`. Stdlib-only patch; zero compiler change. **What
landed**: (1) Five SysNr enum members in BOTH arch peers —
`SYS_GETDENTS64` (217 x86 / 61 arm), `SYS_GETRANDOM` (318 / 278),
`SYS_LANDLOCK_CREATE_RULESET` / `_ADD_RULE` / `_RESTRICT_SELF`
(444/445/446, same on both arches). (2) Five portable wrappers
in BOTH peers (`sys_getdents64` / `sys_getrandom` /
`sys_landlock_create_ruleset` / `_add_rule` / `_restrict_self`)
— trivial `syscall(SYS_X, args...)` shape; doc-comment per fn
to satisfy v5.7.20 cyrdoc-coverage gate. (3) New
`lib/random.cyr` with `GrndFlag` enum + `random_bytes(buf, len)`
loop wrapper that handles short reads (getrandom returns short
for >256 bytes). (4) New `lib/security.cyr` with
`LandlockAccessFs` (13 flag constants — EXECUTE / WRITE_FILE /
READ_FILE / READ_DIR / REMOVE_* / MAKE_*) + `LandlockRuleType`
(PATH_BENEATH). Deliberately constants-only, no struct —
`landlock_ruleset_attr` drifts upstream (`handled_access_net`
6.7, `scoped` 6.10), consumers should declare their own. **The
"stdlib is the platform abstraction" principle preserved**:
consumers should not need to know which arch they're running on
to make a syscall that exists on both. cyrius stdlib already
does this for the common surface (`sys_open`, `sys_read`, ...);
this slot extends it to 2014-2021-era kernel additions.
Verification: cc5 self-host two-step byte-identical at
**720,640 B** (no compiler change). check.sh **54/54 PASS**
(+gate 4aq). `docs/api-surface.snapshot` regenerated: **2552 →
2563** entries (+11: `random::random_bytes/2` + 5 wrappers ×
2 arches). **Post-ship CI fix (3 iterations)**: initial gate
form was `tests/tcyr/syscall_surface_v5735.tcyr` picked up by
the CI tcyr loop. Failed in CI (both ubuntu-latest and the
agnos container) — symptom: no FAIL line, no PASS line, the
loop just dies between iterations with `Error: Process
completed with exit code 1`. Two narrowing iterations didn't
help (relaxing landlock return-value assertions, then moving
landlock calls into a dead `if (0 != 0)` branch); root cause
likely GitHub Actions container seccomp policy gating
landlock syscalls (444-446, added 2021) with `SCMP_ACT_KILL`
rather than `SCMP_ACT_ERRNO`, killing the test in a way the
surrounding bash subshell captured inconsistently. **Final
shape**: deleted `tests/tcyr/syscall_surface_v5735.tcyr`,
moved the test source inline as a `cat <<EOF` heredoc inside
`tests/regression-syscall-surface-v5735.sh`. The `.sh` gate
runs in `check.sh` (and any CI that invokes check.sh) where
the surrounding context lets us isolate failures by exit code
rather than relying on the generic tcyr loop. **Lesson**:
syscall-coverage tests that exercise capability-gated kernel
APIs (landlock, anything < 10 years old) belong as standalone
shell gates with surrounding context, not in the generic
tcyr loop. The tcyr loop is for in-process unit tests; the
shell-gate harness is for "the kernel might do something
unexpected here." **Pinned method**: when the next consumer
surfaces a missing syscall, diff `lib/syscalls_*.cyr`'s SysNr
enum against kernel `include/uapi/asm-generic/unistd.h`
(aarch64) or `arch/x86/entry/syscalls/syscall_64.tbl` (x86).
Don't expand to full BPF / pidfd / openat2 sweep without
consumer ask — minimal bundle is the precedent.)

**5.7.34** (shipped 2026-04-28 — **AARCH64 CODEBUF CAP RAISE
(524288 → 3145728) — phylax-surfaced**. Closes the v5.7.27
ship omission. v5.7.27 grew the codebuf heap region 1 MB → 3 MB
on x86 (`src/backend/x86/emit.cyr:68`) and reshuffled 19
downstream regions to make room, but the matching cap on the
aarch64 backend's `EB()` emit-byte function in
`src/backend/aarch64/emit.cyr:99` was not bumped. Result: any
program that exceeded ~512 KB of emitted machine code on the
aarch64 cross-compiler aborted with `error: codebuf overflow
(.../524288)` while the same source built fine on x86. Phylax
surfaced this when a downstream cross-build of a phylax-shape
program tripped the old cap; the heap region itself had room
(3 MB allocated since v5.7.27), only the function-local cap
check still rejected. **Fix**: trivial constant bump 524288 →
3145728 in `EB()`, plus the matching `/3145728 bytes — program
too large for single compilation` error message (mirroring the
x86 wording so the message is identical from the user's POV).
Comment block flags this as the v5.7.27 follow-up so the next
"grow the codebuf" cycle audits BOTH backend EBs. **Pinned
method** for next codebuf-region grow:
`grep -rn "^\s*if (cp >= [0-9]" src/backend/` enumerates every
EB-class cap in one place before shipping the resize. cc5
self-host two-step byte-identical at **720,640 B** (no compiler
change for x86; aarch64 EB lives in a file `src/main.cyr` does
NOT include — only `src/main_aarch64.cyr` does). **check.sh
53/53 PASS** (was 52/52; +gate 4ap source-checks the cap
constant — fast, no binary build, catches accidental revert
either direction). **Bundled second issue NOT closed**: phylax-
agent surfaced duplicate-fn warnings (`aes_ni_available`,
`_aes_ni_cpuid_probe`, `aes256_encrypt_block_ni`) when building
sigil under cyrius's aarch64 include pipeline. Could not
reproduce locally with phylax/sigil at current pins; cyrius's
include-once table (`PP_ALREADY_INCLUDED` at S+0x1C0000) and
the v5.7.14 closest-wins BFS dedup both look correct on
inspection. Investigation moves to the agnosys side where the
phylax-agent can capture the actual include sequence triggering
the warning. May land at v5.7.35 or v5.7.36 if reproduced
before backstop.)

**5.7.33** (shipped 2026-04-28 — **`cyrius api-surface` —
SNAPSHOT-BASED PUBLIC API DIFF**. New toolchain-quality slot
from the `v5.x — Toolchain Quality` section. Pattern adapted
from `agnosys/scripts/check-api-surface.sh`; cyrius-native
pure-cyrius implementation per the sovereign-toolchain stance.
Catches breaking removals / signature changes before ship;
allows additions (non-breaking). **Why now**: without an
API-surface gate, downstream consumers (mabda / sandhi / sit
/ phylax) can break silently when stdlib renames or removes
a public fn. Agnosys ships a bash-based check; cyrius needed
its own. **Coverage**: top-level `fn NAME(args)` defs in
`src/` + `lib/`, underscore-prefixed names excluded by
convention. Out of scope: top-level vars (covered by
v5.7.32 cyrlint init-order rule), enum/struct types
(future slot if surfaced), local fns (not API surface).
**Implementation**: `programs/api_surface.cyr` (~450 lines)
walks both dirs, extracts public fns + arity, formats as
`module::name/arity`, insertion-sorts byte-wise (deterministic
regardless of host locale — agnosys hard-learned lesson),
diffs against `docs/api-surface.snapshot`. Two modes:
`cyrius api-surface` (diff vs snapshot, rc=1 on breakage)
and `cyrius api-surface --update` (regenerate snapshot).
Wired into cbt at `cbt/commands.cyr` (`cmd_api_surface`) +
`cbt/cyrius.cyr` (dispatch between `deny` and `audit`). Tool
binary added to `cyrius.cyml [release].bins` so install
snapshot ships it. Initial snapshot of cyrius's public API:
**2552 entries** spanning the full stdlib + bundled deps.
cc5 self-host two-step byte-identical at **720,640 B** (no
compiler change — cbt + new program only). New gate
`tests/regression-api-surface.sh` (4ao): three cases —
committed snapshot matches current (no drift), synthetic
extra `_TEST_REMOVED` entry → BREAKING rc=1, deleted entry →
non-breaking addition rc=0. **check.sh 52/52 PASS** (was
51/51; +gate 4ao). LSP semantic-tokens polish (other
toolchain-quality item) not bundled — separate slot when
claimed.)

**5.7.32** (shipped 2026-04-28 — **CYRLINT GLOBAL-INIT-ORDER
FORWARD-REF WARNING (mabda-surfaced)**. Closes silent
miscompile class that cost mabda 30+ minutes hardware-iter
misdiagnosis. **Promoted before RISC-V** at user direction
"rather be 'bug' free before RISCV work." Cyrlint-only patch;
zero compiler change; cc5 byte-identical at 720,640 B.
**What was broken**: cyrius initializes top-level
`var X = expr;` in source declaration order; if `expr`
references a constant declared LATER, the ref resolves to 0
(default zero-init) at the time X is evaluated. No warning,
no error. Mabda hit this in `_NATIVE_PERM_FULL =
AMDGPU_VM_PAGE_READABLE | _WRITEABLE | _EXECUTABLE` at line
117 with the AMDGPU_VM_PAGE_* constants at line 391+; result:
all BOs mapped with `perms=0`; every dispatch TDR'd at the
AMDGPU 10-second timeout looking like a wedged GPU.
**Fixed**: new rule `lint_globals_init_order` in
`programs/cyrlint.cyr` walks file twice. Pass 1 collects
every TOP-LEVEL `var IDENT = ...;` and records (name, line)
in parallel arrays (cap 256). Pass 2 walks every var
initializer, scans expr tokens for IDENT references, emits
warning if def_line > current_line. Mirrors mabda's option
(1) in the filing. Helpers added: `_is_id_start`,
`_is_id_cont`, `_find_eol`, `_find_var_decl_ident`,
`_scan_id_end`, `_eq_substr`. Scope deliberately narrow:
only var→var references (fns/enums/structs are forward-
ref-safe). Per `feedback_grow_compiler_to_fit_language.md`:
language behavior stays unchanged; lint surfaces the
foot-gun without breaking existing stdlib shapes that rely
on declaration order. **Verification**: new gate
`tests/regression-lint-global-init-order.sh` (4an): 3 test
cases — known-bad fixture (3 forward refs → ≥3 warnings),
lib/math.cyr (0 false-positives), lib/string.cyr (0
false-positives). All PASS. cc5 self-host two-step
byte-identical at **720,640 B** (no compiler change).
**check.sh 51/51 PASS** (was 50/50; +gate 4an). Out of
scope (future polish): IDENTs inside string literals (no
suppression yet — no observed false positives but
literal-aware scanner is a future polish).)

**5.7.31** (shipped 2026-04-28 — **AARCH64 f64_exp / f64_ln
POLYFILLS — phylax UNBLOCK**. Originally-named v5.7.30 ask;
split off when v5.7.30 premise verification surfaced the
broader basic-op miscompile (closed by v5.7.30). With v5.7.30's
basic ops working, polyfills are pure-cyrius implementations
in `lib/math.cyr` using FADD/FSUB/FMUL/FDIV/FRINTN/FCVTZS/SCVTF.
**Polyfills**: (1) `_f64_exp_polyfill(x)` — range-reduce
`x = n*ln(2) + r` with `|r| ≤ ln(2)/2`; 11-term Taylor for
`exp(r)`; `2^n` via integer-exponent bit-pack. (2)
`_f64_ln_polyfill(x)` — mantissa/exponent split via bit
masks; remap mantissa to `[√(1/2), √2)`; 8-term inverse-tanh
series `2u·(1 + u²/3 + u⁴/5 + … + u¹⁴/15)`. Both target
~few-ulp accuracy — sufficient for phylax-class statistical
work. **Helper added**: `_FINDFN_CSTR(S, str_ptr, str_len)`
in `parse_fn.cyr` for fn-by-c-string lookup (vs FINDFN's
noff-based lookup). Used by parser polyfill dispatch.
**Dispatch**: `parse_expr.cyr` aarch64 ERR_MSG paths for
`f64_exp` (ptyp 85) and `f64_ln` (ptyp 86) replaced with
fncall emission via `EPUSHR` + `ECALLPOPS(1)` + `ECALLFIX`
to the polyfill fnidx (resolved via `_FINDFN_CSTR`). If
polyfill isn't registered, clear error points at required
`include "lib/math.cyr"`. **Inverse-trig section** in
`lib/math.cyr` (`f64_asin`/`f64_acos`/`f64_atan2`) wrapped in
`#ifdef CYRIUS_ARCH_X86` — uses `f64_atan` builtin (x87
fpatan) with no aarch64 equivalent; not polyfilled in
v5.7.31 (phylax doesn't need it). cc5 self-host two-step
byte-identical at **720,640 B** (was 719,280 at v5.7.30;
+1,360 B for polyfill bodies + helper + dispatch). New gate
`tests/regression-aarch64-f64-polyfill.sh` (4am): cross-
builds smoke test on aarch64, scp's to `$SSH_TARGET`
(default `pi`), runs on real Pi 4 hardware, asserts
bit-accurate within ulp budget for 6 cases (`exp(0)=1.0`
exact, `exp(1)≈e`, `ln(1)=0`, `ln(e)≈1`, `exp(ln(2))≈2`
round-trip, `exp(-1)≈1/e`). All 6 PASS on Pi 4.
**check.sh 50/50 PASS** (was 49/49; +gate 4am).
**Trio v5.7.30 + v5.7.31** closes the v5.4.x-era silent f64
miscompile + the v5.7.0-era hard-reject in one coherent
split. Structural CI gates at both levels (4al basic ops, 4am
polyfill correctness) catch future drift before ship.
**phylax UNBLOCK** — chi-squared p-values + entropy paths
compile + run correctly on aarch64; the "green CI but broken
local aarch64" gap is closed; cc5_aarch64 bundles with
phylax produce a working aarch64 release. Out of scope
(future polyfill slots if surfaced):
`f64_sin/f64_cos/f64_log2/f64_exp2/f64_atan` — same shape,
none phylax-blocking.)

**5.7.30** (shipped 2026-04-28 — **AARCH64 f64 BASIC-OP
IMPLEMENTATION**. Closes a silent miscompile that affected
every aarch64 build using f64 ops. Pre-v5.7.30 every basic
f64 op on aarch64 was a stub (`return 0;` in
`src/backend/aarch64/emit.cyr`) — `f64_add(1.0, 2.0)` returned
2.0 (the second arg, because the parser left it in x0 and
EMIT_F64_BINOP emitted nothing), with stack leak from the
unpopped first arg. Probably broken since v5.4.x when aarch64
cross-build first shipped. Surfaced via phylax's f64_exp
hard-reject; original v5.7.30 ask was "f64_exp polyfill" but
premise verification (per `feedback_verify_slot_premise_first.md`)
turned up that the f64_exp hard-reject was masking
f64_add/sub/mul/div/sqrt/floor/ceil/round/neg + int↔f64 ALL
silently broken on aarch64. Per user direction "you can split
into the two logical pieces": v5.7.30 = basic-op
implementation, v5.7.31 = f64_exp/f64_ln polyfills using these
ops. **Fixed**: 7 stub fns replaced with single-instruction
emits (encodings verified via aarch64-linux-gnu-as) —
EMIT_F64_BINOP (FADD/FSUB/FMUL/FDIV depending on fop), EF64SQRT
(FSQRT), EF64FLOOR (FRINTM), EF64CEIL (FRINTP), EF64ROUND
(FRINTN — round-to-nearest, ties-to-even, IEEE 754 default),
EI2F (SCVTF), EF2I (FCVTZS). Plus `f64_neg` parser ERR_MSG
replaced with FNEG d0,d0 emit (parse_expr.cyr:1104). Each
op: 3 instructions (fmov-d-x bit-cast, op, fmov-x-d extract;
12 bytes total per op). x86-named EMOVQ_*/EUCOMISD/EXORPD_X1/
EMOVAPD_01/EX87PUSH/EX87POP stubs preserved — they're
parser-shared codepath helpers the aarch64 path doesn't need
(fmov ops inlined directly into EMIT_F64_BINOP). cc5
self-host two-step byte-identical at **719,280 B** (was
719,000 at v5.7.29; +280 B for emit code). New gate
`tests/regression-aarch64-f64.sh` (4al): cross-builds 11-case
f64 op smoke test, scp's to `$SSH_TARGET` (default `pi`),
runs on real Pi 4 hardware, asserts bit-exact expected
results against IEEE 754 reference values (each assertion
exits with unique code 1-11 on failure; success = 99).
**check.sh 49/49 PASS** (was 48/48; +gate 4al). Gate
verified: ALL 11 ops bit-exact on Pi 4. Phylax STILL
blocked at v5.7.30 (f64_exp/f64_ln still hard-reject;
v5.7.31 closes that with polyfills using these basic ops).
Out of scope: f64_sin/cos/log2/exp2 (not phylax-blocking;
future slot).)

**5.7.29** (shipped 2026-04-28 — **CX GATE `set -e` REPAIR +
check.sh HYGIENE**. Closes the v5.7.27 fallout chain. v5.7.28
fixed the COMPILER regression (cc5_cx restored); v5.7.29 fixes
the GATE-INFRASTRUCTURE so check.sh can correctly report it.
~50 lines, zero compiler change. **What was broken**: three
`regression-cx-{build,roundtrip,syscall-literal}.sh` gates had
`set -e + pipeline` interaction — cc5_cx returns exit 1 on
parse-error inputs (correct; emits diagnostic + exits non-zero)
but `set -e` aborted the gate before `EXIT=$?` capture, making
the "only flag SIGSEGV ≥128" gate logic unreachable. check.sh
itself had `set -e` at line 4 — when any gate returned
non-zero, the script aborted before `_result=$?` captured, so
the entire audit died at the first failing gate (~25 of 47+).
The verification idiom `sh check.sh 2>&1 | tail -3` returned 0
from `tail` (unset pipefail), masking the abort behind a "47/47
PASS"-shape line that was actually partial-output's last 3
lines. Every "47/47 PASS" report I logged across v5.7.24-v5.7.27
ship was false reassurance. **Fixed**: (1) three cx gates wrap
cc5_cx invocations in `set +e` / `set -e` toggles (matching the
existing pattern around cxvm calls). Plus repaired latent bug
in roundtrip Test 4: `cmd || true; EXIT=$?` was clobbering
EXIT to 0 (`$?` after `|| true` reflects `true`'s exit), making
SIGSEGV-detection unreachable. Replaced with proper capture
pattern. (2) check.sh `set -e` removed at line 4 with block
comment explaining why. The script uses explicit
`_result=$?` + `check "..." "$_result"` reporting throughout;
`set -e` was never load-bearing, just counterproductive. (3)
~25 lines of explanatory comments encode the v5.7.27-era ship
damage so future contributors don't re-add `set -e`.
**Verification**: `sh scripts/check.sh` rc=0, **48/48 PASS**
(was aborting at gate ~25/47 silently); with `pipefail` set,
still rc=0 — verification idiom no longer pipe-masked.
v5.7.28's parity gate (4ak) now reachable; pre-v5.7.29 the
cx-build gate failure aborted check.sh before 4ak ran. cc5
self-host two-step byte-identical at **719,000 B** (no
compiler change). All TS gates PASS, SY corpus unchanged. The
trio (v5.7.27 cap raise + v5.7.28 cx re-sync + v5.7.29 gate
hygiene) closes the v5.7.27 ship-damage chain entirely.)

**5.7.28** (shipped 2026-04-28 — **CX BACKEND TOKEN-OFFSET FIX
(v5.7.27 SHIP REGRESSION) + STRUCTURAL PARITY GATE**.
Mechanical 2-line shift in `src/backend/cx/emit.cyr` to track
v5.7.27's heap reshuffle, plus a new CI gate that catches
lex-write / backend-read offset drift at the source level.
**v5.7.27 silently regressed cc5_cx** — its heap reshuffle
shifted lex's token writes (`tok_types` 0x74A000 → 0x94A000;
`tok_values` 0xB4A000 → 0xD4A000) but the v5.7.27 shift loop
deliberately skipped `src/backend/cx/emit.cyr` (cx has its own
codebuf at 0x54A000 + per-fn at 0x150B000, both unchanged).
The skip OVER-applied — cx backend's `TOKTYP` / `TOKVAL`
definitions read the SAME shared frontend tokens at the SAME
offsets the main backends use. Post-v5.7.27 cx read tok_types
from inside the new codebuf region (garbage) and tok_values
from where tok_types now lives. cc5_cx returned exit 1 with
`error:2: unexpected unknown` on every input. Bug stayed
masked at v5.7.27 ship by (1) the queued v5.7.29 cx-gate
`set -e + pipeline` issue that aborts gates before failure
reporting and (2) the `sh check.sh 2>&1 | tail -3` pipe-mask
that hid check.sh's actual exit code. cc5_cx is byte-identical
when built with v5.7.26 vs v5.7.27 cc5 (both 371,848 B); both
fail today on all inputs. **At v5.7.26 ship cc5_cx worked**;
at v5.7.27 ship silently broken; at v5.7.28 ship restored.
Fix: 2 lines in cx/emit.cyr — TOKTYP 0x74A000 → 0x94A000,
TOKVAL 0xB4A000 → 0xD4A000. Verified end-to-end:
`echo 'syscall(60, V);' | cc5_cx | cxvm` exits with V across
V ∈ {0, 7, 42, 99, 200}. cc5 self-host two-step byte-
identical at **719,000 B** (size unchanged; the cx-emit
constant change doesn't affect cc5 output). New gate
`tests/regression-cx-token-offsets.sh` (4ak) — greps each
backend's `TOKTYP` / `TOKVAL` definitions and the shared lex's
write sites, extracts the hex offsets, asserts they all
agree. Catches drift at the source level in 0.1s with no
compiler build. Validated by deliberately reverting cx
TOKTYP back (gate FAILs with explicit drift message), then
restoring (gate PASSes). **Third instance in v5.7.x of
forked-helper offset drift**: v5.7.23 cx TOKVAL typo
(memory `feedback_audit_forked_helper_offsets.md`), v5.7.27
heap-shift skipped cx, v5.7.28 re-synced + structural gate.
The new gate directly addresses the audit pattern from the
v5.7.23 memory — check.sh now does the diff automatically.
**check.sh still v5.7.27-broken at the cx-build gate**
(`set -e` aborts before the new 4ak gate runs); v5.7.29
fixes the gate-infrastructure so check.sh can complete and
the parity gate actually reaches its check. v5.7.28 ships
the COMPILER fix; v5.7.29 ships the GATE-INFRA fix —
logically distinct per user direction at v5.7.28 start
"you can split into the two logical pieces.")

**5.7.27** (shipped 2026-04-28 — **CODEBUF CAP 1 MB → 3 MB +
19-REGION HEAP RESHUFFLE**. Mechanical cap raise to absorb
cyrius-ts test-compile pressure. User-pinned at v5.7.26 ship:
"might need code-buf to 3MB in the next release... but also
begs the question on test organization." `cyrius test
ts_parse_p52-54.tcyr` was hitting 94% of the 1 MB code-buf cap
(988-989 KB) across the v5.7.24-v5.7.26 advanced-TS trio.
v5.7.27 is the cap raise; the test-organization rework is
SEPARATE per user direction "no retiring my file set... they
would need to grow to be better that SHELLOUTS" (`tcyr` =
real in-process unit tests, shell gates = smoke; new feedback
memory `feedback_no_retire_tcyr_for_shell_gates.md` pinned).
**261 offset references shifted across 21 source files** —
every region from `output_buf` (was 0x74A000, now 0x94A000)
through `brk-with-ts-frontend` (was 0x348C000, now 0x368C000)
moved +0x200000. cx backend (`src/backend/cx/emit.cyr`) is
untouched — it uses its own layout (codebuf at 0x54A000,
per-fn at 0x150B000 inherited from the legacy retired-fixup
gap); main_cx.cyr's brk extension shifted with the rest.
**codebuf cap value 1048576 → 3145728** in 9 sites: main.cyr
+ main_win.cyr cap-warning blocks (3 each) + heap-map
comments, backend/x86/emit.cyr overflow check + error message,
main_aarch64* heap-map comments. aarch64 emit's internal
524288 cap left alone (separate scope; smaller cc5_aarch64
binary doesn't hit it). cc5 self-host two-step byte-identical
at **719,000 B** (size unchanged from v5.7.26 — heap reshuffle
doesn't change emitted code sequence; only data layout. cc5
bytes do differ from v5.7.26 starting at byte 3380 — string-
literal table shifted by the new cap-warning text). Heap-map
audit `sh tests/heapmap.sh` PASS (80 regions, 0 overlaps);
`cyrius test ts_parse_p54.tcyr` 20/20 PASS with code-buf at
**32%** (989528/3145728) — well below the 85% warning
threshold. TS gates all green (asserts / mapped / decorators);
SY corpus unchanged (2053/2053 .ts + 435/435 .tsx).
**Pre-existing bug surfaced (queued v5.7.28)**: cx regression
gates (`regression-cx-{build,roundtrip,syscall-literal}.sh`)
have a `set -e + pipeline` interaction — `cc5_cx` returns
exit 1 on parse-error inputs (correct) which under `set -e`
aborts the script before `EXIT=$?` capture. `check.sh` (also
`set -e`) then aborts at the cx-build gate, never reaching
the new TS gates or summary. **v5.7.24-v5.7.26 ship "47/47
PASS" reports were false reassurance** — `sh check.sh 2>&1
| tail -3` masked check.sh's exit code via the unset-pipefail
pipe. v5.7.26 cc5 reproduces identically (verified directly),
so the bug is at minimum v5.7.26-era; v5.7.27 didn't
introduce it. v5.7.28 fix is ~30 lines: `set +e` / `EXIT=0;
cmd || EXIT=$?` toggles in each cx gate + check.sh hygiene
pass.)

**5.7.26** (shipped 2026-04-28 — **CYRIUS-TS — TS 5.0 STAGE-3
DECORATORS**. Third and final of the v5.7.24-v5.7.26 TS-depth
patches (smallest → highest order: asserts predicate sigs at
v5.7.24, mapped types at v5.7.25, decorators here). Closes the
"advanced TS features beyond SY corpus" pin. Pre-v5.7.26 the
`@` token (`TS_TOK_AT = 35`) was unhandled at every valid
decorator position — class statements, class members, function
parameters — and parses rejected with `code=6 tok=35`
(unexpected statement-leading token) or `code=3 tok=35`
(unexpected token at expected position). The SY corpus didn't
surface this gap (no SY .ts file uses decorators), so parse
acceptance ran 100% without coverage. v5.7.26 adds:
(1) `TS_AST_DECORATOR = 315` AST kind allocated (parse-
acceptance only — AST attachment to following declaration is
a future polish slot for the typechecker phase, same pattern
as v5.7.24 asserts and v5.7.25 mapped types);
(2) `TS_PARSE_DECORATOR_LIST` helper — loops while
`peek == TS_TOK_AT`, consumes `@`, dispatches to existing
`TS_PARSE_CALL_MEMBER` for the expression. The call-member
parser already covers full TS 5.0 grammar: `@foo`, `@foo()`,
`@foo.bar`, `@foo.bar.baz<T>(args)`, `@(<expr>)`,
`@foo({obj})`. No new lex tokens; no new expression parser
primitives. (3) Wire-in at four sites: `TS_PARSE_STMT` (top —
`@foo class X {}`, `@foo abstract class Y {}`),
`TS_PARSE_CLASS_MEMBER` (top, before `SKIP_MODIFIERS` —
`class X { @foo method() {} @bar prop }`),
`TS_PARSE_ARROW_PARAMS` (per-iteration, before
`SKIP_MODIFIERS` — `class X { method(@foo x: T,
@bar.dec() y: U) {} }`), `TS_PARSE_EXPORT` (top + default
branch — `export @foo class X {}` and `export default @foo
class {}`). cc5 self-host two-step byte-identical at
**719,000 B** (was 718,200 B at v5.7.25; +800 B for the
helper + four wire-in sites + the AST kind). New gate
`tests/regression-ts-decorators.sh` (4aj, 5 shape categories):
class decl decorators (incl. multi-chain, qualified, factory
with object/array args, generic `@foo<T>()`, abstract class);
class member decorators (incl. method, property, factory +
modifier, multi-decorator async, get/set accessors); parameter
decorators (incl. multi-param mixed, decorator + ctor-prop
modifier); export/export-default decorators; pre-v5.7.26
regression forms. New tcyr `tests/tcyr/ts_parse_p54.tcyr` —
**20 byte-level assertions** in 5 groups, mirroring the gate.
SY corpus regressions unchanged: `regression-ts-parse.sh`
2053/2053, `regression-ts-parse-tsx.sh` 435/435,
`regression-ts-asserts.sh` PASS, `regression-ts-mapped.sh`
PASS. **check.sh 47/47 PASS** (was 46/46; +gate 4aj).
**Side-task pin (cap-raise + test organization, user-direction
2026-04-28)**: `cyrius test ts_parse_p54.tcyr` reports
`code buffer at 94% (989528/1048576 bytes)` —
basically unchanged from v5.7.25's 988456 B (+1,072 B for
decorator helper + enum slot). User-pinned for v5.7.27:
"might need code-buf to 3MB in the next release... but also
begs the question on test organization." Bundle the
1 MB → 3 MB cap raise with TS test-organization rework.
Not blocking v5.7.26.)

**5.7.25** (shipped 2026-04-28 — **CYRIUS-TS — MAPPED TYPES +
`as`-CLAUSE + `+/-` MODIFIERS (TS 2.1 / 2.8 / 4.5)**. Second of
the v5.7.24-v5.7.26 TS-depth patches (smallest → highest:
asserts predicate sigs at v5.7.24, mapped types here, decorators
at v5.7.26). Pre-v5.7.25 the parser handled `[k: K]: V` index
signatures inside object types but treated the entire mapped-
type construct (`[K in T]: V`) as a syntax error — `KW_IN` was
unexpected after the bracket-key IDENT consume. The SY corpus
didn't surface this gap (no SY .ts file uses mapped types in
real code), so parse acceptance ran 100% without coverage.
v5.7.25 adds: (1) `TS_AST_TYPE_MAPPED = 314` AST kind (payload
`[0]` iter type, `[1]` remap type or 0, `[2]` value type);
(2) mapped-type fork in `TS_PARSE_TYPE_OBJECT` dispatched by
`peek == LBRACKET && peek_ahead(1) is name-like &&
peek_ahead(2) == KW_IN` — index sigs (`peek_ahead(2) == COLON`)
fall through unchanged; (3) full body parse `[K in <iter>]`
plus optional `as <remap>` (TS 4.5+ key remapping; reuses
existing `KW_AS = 137` keyword), optional `?` / `+?` / `-?`
modifier, `:`, value type; (4) `+/-readonly` modifier prefix
in the member-start consume block (TS 2.8+ explicit add/remove)
alongside the bare `readonly` already shipped — detection:
`peek == PLUS|MINUS && peek_ahead(1) == KW_READONLY`. cc5
self-host two-step byte-identical at **718,200 B** (was
716,728 B at v5.7.24; +1,472 B for the AST slot + TYPE_OBJECT
fork + `+/-readonly` modifier extension). New gate
`tests/regression-ts-mapped.sh` (4ai, 7 shape categories):
bare mapped, `as`-clause remap (incl. template literal +
conditional types), `readonly`/`+readonly`/`-readonly`, bare
`?` / `+?` / `-?`, combined (full `-readonly + as + -?`),
pre-v5.7.25 index-sig regression, readonly property
regression. New tcyr `tests/tcyr/ts_parse_p53.tcyr` —
**17 byte-level assertions** in 6 groups, mirroring the gate.
SY corpus regressions unchanged: `regression-ts-parse.sh`
2053/2053, `regression-ts-parse-tsx.sh` 435/435,
`regression-ts-asserts.sh` PASS. **check.sh 46/46 PASS** (was
45/45; +gate 4ai). **Side-task pin (cap-raise candidate)**:
`cyrius test` on `ts_parse_p53.tcyr` reports `code buffer at
94% (988456/1048576 bytes)` — TS frontend test compiles
approach the 1 MB code-buf cap; queue a heap-map reshuffle
slot in v5.7.31-v5.7.33 range or bundle with v5.7.26
decorators (which broaden the parser further). Not blocking.)

**5.7.24** (shipped 2026-04-28 — **CYRIUS-TS — `asserts`
PREDICATE SIGNATURES (TS 3.7+)**. First of three v5.7.x
patches working through TS features beyond the SY corpus
(smallest first per direction; mapped types `as`-clause v5.7.25,
decorators v5.7.26). Pre-v5.7.24 the parser had a comment-only
stub at `TS_PARSE_TYPE` that *intended* to tolerate `asserts
<id> [is <T>]` in return-type position; the implementation only
handled the `<lhs> is <T>` suffix and misparsed any input
starting with `asserts` (consumed `asserts` as the type-ref,
then `<id> is <T>` ate the subject, leaving the actual T
unconsumed). v5.7.24 adds (1) `TS_TOK_KW_ASSERTS = 219`
contextual keyword in `src/frontend/ts/lex.cyr` len-7 block
alongside `declare`; (2) real prefix consumer in
`TS_PARSE_TYPE` — when `peek == KW_ASSERTS && ahead is
name-like (IDENT / KW / KW_THIS)`, consume `asserts` and let
the existing `<lhs> is <T>` predicate suffix logic handle the
rest; (3) polymorphic `this`-type branch in
`TS_PARSE_TYPE_PRIMARY` emitting `TYPE_REF` — needed for
`asserts this is C` method predicates and class-builder
return-type `this` patterns (incidental coverage:
`interface Builder { build(): this }`,
`class B { chain(): this {...} }`,
`class P { is(): this is P {...} }`); (4) `KW_ASSERTS` added to
expr-PRIMARY ident-eligible OR-chain (alongside `KW_SATISFIES` /
`KW_INFER`) and `TYPE_PRIMARY` type-ref OR-chain (alongside
`KW_FROM` / `KW_AS` / `KW_TYPE`) so `var asserts = 1;`,
`let x: asserts;`, `type T = asserts;`, `obj.asserts`,
`{ asserts: 42 }` all stay green — same pattern as `satisfies`
shipped in v5.7.4. cc5 self-host two-step byte-identical at
**716,728 B** (was 716,080 B at v5.7.23; +648 B for the new
branches and token). New gate
`tests/regression-ts-asserts.sh` (4ah, 6 shape categories):
typed predicate `asserts <id> is <T>` (incl. unions and
generic params), bare `asserts <id>`, method `asserts this is
<T>`, polymorphic `this`-type, `asserts` ident-eligibility
(var / type-ref / type alias / property / member access),
pre-v5.7.24 regression `<id> is <T>` predicate. New tcyr
`tests/tcyr/ts_parse_p52.tcyr` — **15 byte-level assertions**
in 6 groups, mirroring the gate. SY corpus regressions
unchanged: `regression-ts-parse.sh` 2053/2053, `regression-
ts-parse-tsx.sh` 435/435, `regression-ts-lex.sh` PASS.
**check.sh 45/45 PASS** (was 44/44; +gate 4ah). Out of
v5.7.24 scope (same behavior as `satisfies` today, future
patches if surfaced): `function asserts() {}` and
`class asserts {}` — pre-existing parser limitation that
contextual keywords aren't accepted as fn/class declaration
names; `function satisfies() {}` rejects identically.)

**5.7.23** (shipped 2026-04-27 — **CX CODEGEN — LITERAL ARG
PROPAGATION**. Single-character typo fix in
`src/backend/cx/emit.cyr:443` — `TOKVAL` helper read tokens
from `S + 0x94A000 + i*8` (a zero-initialized gap region
between `tok_types` and `tok_values`) instead of the canonical
`S + 0xB4A000 + i*8` write site in `src/frontend/lex.cyr:99`.
PEEKV always returned 0 in cc5_cx, so any user-supplied literal
arg in `syscall(N, V)` (and any other typ==1 NUM token) emitted
`MOVI r0, 0` regardless of the source value. The implicit-exit
syscall's `60` propagated correctly because main_cx synthesizes
that token via a hard-coded path, not via lex. Fix: 0x94A000 →
0xB4A000. Closes the issue pinned in v5.7.12's
`regression-cx-roundtrip.sh` "What this gate does NOT check"
note. cc5 self-host two-step byte-identical at **716,080 B**
(cx-backend-only edit; main x86 cc5 unchanged). New gate
`tests/regression-cx-syscall-literal.sh` (4ag, 7 sub-checks):
bytecode for `syscall(60, 42);` contains `MOVI r0, 60`
(`01 00 3c 00`) and `MOVI r0, 42` (`01 00 2a 00`); no spurious
"syscall arity mismatch" on stderr; cxvm round-trip exits 42;
literals 0/7/99/200 each exit with their own code (catches
hypothetical TOKVAL-reads-a-constant regression). **check.sh
44/44 PASS** (was 43/43; +gate 4ag). Pattern caught:
forked-helper drift — when a backend module forks shared
frontend helpers, every offset literal is a typo candidate.
Audit pattern: `grep -rn "0x[0-9A-F]\{6\}A000" src/backend/`
and diff each region's reads/writes against canonical write
sites in `src/frontend/lex.cyr`.)

**5.7.22** (shipped 2026-04-27 — **HYGIENE PASS** — three
bundled tooling fixes. (1) `programs/cyrfmt.cyr` no longer
tracks `{`/`}` inside `#` comments or `"..."` string literals
— closes agnos
[2026-04-27-cyrius-fmt-tracks-braces-in-comments](https://github.com/MacCracken/agnos/blob/main/docs/development/issue/2026-04-27-cyrius-fmt-tracks-braces-in-comments.md)
issue. (2) `scripts/install.sh --refresh-only` now re-links
`~/.cyrius/bin` → `versions/$VERSION/bin` after refreshing
the snapshot — closes the H3 local-dev footgun where
`version-bump.sh` left the PATH-resolved cyrius binary
pointing at a stale version. (3) `scripts/cyriusly`'s
`link_version` uses `rm -rf` instead of `rm -f` so a
stale-directory state at `~/.cyrius/bin` (from older
copy-based installs) gets cleaned out. Bonus: seven stdlib
files (`bench.cyr`, `cyml.cyr`, `dynlib.cyr`, `flags.cyr`,
`hashmap.cyr`, `json.cyr`, `net.cyr`) were re-formatted with
the fixed cyrfmt — semantically a no-op (cyrius lex strips
leading whitespace) but the source matches the formatter
output again. cc5 self-host two-step byte-identical at
**716,080 B** (programs/scripts edits only; compiler
unchanged). New gates: `tests/regression-cyrfmt-comment-braces.sh`
(gate 4ae, 4 cases — agnos repro + string-literal-with-
braces + ordinary code + mixed) and
`tests/regression-install-shim-symlink.sh` (gate 4af —
isolated CYRIUS_HOME, fake old-version snapshot, runs
--refresh-only, asserts symlink re-pointed). **check.sh
43/43 PASS** (was 41/41; +2 gates).)

**5.7.21** (shipped 2026-04-27 — **`cyrius fuzz` MANIFEST-DEPS
AUTO-PREPEND PARITY**. One-line cmd-gate fix in
`cbt/cyrius.cyr`: added `streq(cmd, "fuzz") == 1` to the
`_auto_deps` whitelist that previously contained only
`build / run / test / bench / check`. Pre-v5.7.21 fuzz
harnesses had to hand-include every stdlib module they
used (sibling `.tcyr` / `.bcyr` got auto-prepend from day
one). cmd_fuzz was already calling `compile()` which reads
`_dep_includes`; the gate just wasn't populating it for the
fuzz path. cc5 self-host two-step byte-identical at
**716,080 B** (cbt-only edit; compiler unchanged). New gate
`tests/regression-fuzz-deps-prepend.sh` (gate 4ad): 2 cases
— manifest-with-stdlib (`fuzz/X.fcyr` references `strlen`,
auto-prepend resolves) and no-manifest (self-contained
`.fcyr` still runs cleanly). **check.sh 41/41 PASS** (was
40/40; +gate 4ad). Side-task progress: warning sweep —
manifest-listed stdlib fns referenced from fuzz harnesses
no longer trigger `undefined function` warnings.)

**5.7.20** (shipped 2026-04-27 — **`lib/json.cyr` DEPTH**.
Stdlib baseline JSON engine; RPC-grade scope still owned by
sandhi (`lib/sandhi.cyr`). New `json_v_*` API (~700 LOC of
engine) alongside the existing flat key-value API at the top
of `lib/json.cyr`. Tagged 24-byte heap value with 7 tags
(NULL / BOOL / INT / FLOAT / STR / ARR / OBJ). Recursive-
descent parser handles all 6 value types, arbitrary nesting,
full JSON string escape decoding (`\"` `\\` `\/` `\b` `\f`
`\n` `\r` `\t` `\uXXXX` including surrogate-pair handling
for 4-byte UTF-8), numbers (INT if no `.` `e` `E`; else
FLOAT via custom f64 parser using cyrius's f64 builtins).
Error reporting via `json_last_error` / `json_last_error_pos`.
Compact serializer `json_v_build` re-escapes strings per
JSON spec. Backward compat preserved: `json_parse`,
`json_get`, `json_get_int`, `json_pair_new`, `json_key`,
`json_value`, `json_build`, `json_parse_file` untouched —
existing kybernet (boot-config), argonaut (test_serde),
libro (canonical-json-hash) callers stay green. New gate
`tests/tcyr/json_engine.tcyr`: **71 byte-level assertions**
in 11 groups including primitives, escapes (with surrogate
pair `😀`), arrays, objects (order preserved + missing-key
returns 0), 3-level nesting, floats (decimal + scientific),
build round-trip, error positions, type coercion, flat-API
regression. cc5 self-host two-step byte-identical at
**716,080 B** (lib-only addition). **check.sh 39/39 PASS**
(tcyr 109 → 110; gate count unchanged because tcyr files are
auto-discovered). Two cleanups during build: decorative
box-drawing unicode (`# ── X ──`) tripped `cyrius lint` 120-
byte threshold (U+2500 is 3 bytes UTF-8) — switched to ASCII
separators (`# === X ===`); long `if (...&& load8 == X &&
load8 == Y...)` keyword-parse chains for true/false/null
shortened with `memeq`. Out of scope (deferred): pretty-
printing, streaming parser, JSON Pointer.)

**5.7.19** (shipped 2026-04-27 — **KERNEL-MODE EMIT ORDER FIX**.
Under `kernel;` (kmode == 1), top-level asm (the multiboot
32→64 long-mode boot shim) now emits BEFORE 64-bit gvar-init
code in `src/main.cyr`. Restores the cc3-era ordering
invariant — every agnos kernel release relied on it;
silently dropped at cyrius v5.0.0 (cc4→cc5 IR overhaul).
Path A1 from the [agnos boot-shim regression proposal](https://github.com/MacCracken/agnos/blob/main/docs/development/proposals/2026-04-27-cc5-kernel-boot-shim-regression.md):
agnos 1.23.0 (on cyrius 5.7.12) compiled clean + passed all
in-tree tests but did not boot — multiboot1 hands control in
32-bit protected mode, but cc5 emitted `mov rcx, imm64; mov
[rcx], rax` (REX.W; 64-bit) gvar inits BEFORE the boot shim,
so the CPU triple-faulted on the very first instruction.
Implementation: kmode-conditional split of `EMIT_GVAR_INITS`
and `PARSE_PROG` calls in `src/main.cyr` ~line 982. Non-kmode
path unchanged (executable / object / shared modes still
emit gvar inits before main parse). The undefined-fn warning
loop sits between the two branches, so non-kmode order stays
exactly `EMIT_GVAR_INITS → STI → warnings → PARSE_PROG`.
cc5 self-host two-step byte-identical at **716,080 B** (was
715,920 B; +160 B for the kmode branch). New gate
`tests/regression-kmode-emit-order.sh` (gate 4ab): compiles
a minimal kernel; source with a 4-byte top-level asm marker
(4× HLT) and a single gvar init; asserts the `f4 f4 f4 f4`
marker file offset is LESS than the first `48 b9` (REX.W mov
rcx, imm64) gvar-init signature. **check.sh 39/39 PASS** (was
38/38; +gate 4ab). Reviewing the proposal at v5.7.18 ship
confirmed kmode IS the agnos team's request — v5.7.20
placeholder reclaimed; net cascade since v5.7.18 is +0.
Out of scope: Path A2 (skip `EMIT_GVAR_INITS` entirely under
kmode and emit constants into `.data`) — cleaner long-term
but bigger change; future patch if a kmode consumer earns it.
Downstream: agnos 1.24.0 bumps `cyrius.cyml` toolchain pin
to v5.7.19, removes `continue-on-error: true` from the QEMU
Boot Test job, asserts boot output via `grep -q "AGNOS
kernel v"`.)

**5.7.18** (shipped 2026-04-27 — **FULL REGEX ENGINE** —
Thompson NFA + Pike's matcher in `lib/regex.cyr`. Linear-time
matching, no backtracking. Supports literals + escapes + `.`
+ anchors `^` `$` + character classes (`[abc]` `[^abc]`
`[a-z]`) + predefined classes (`\d \D \w \W \s \S`) +
quantifiers (`* + ? {n} {n,} {n,m}` greedy AND lazy) +
alternation `|` + grouping `(...)` capturing + `(?:...)`
non-capturing + word boundaries `\b \B`. API: `regex_compile`,
`regex_match` (anchored), `regex_search` (find-first),
`regex_search_at`, `regex_group_start`, `regex_group_end`.
~830 LOC engine on top of the existing glob/find_all/
str_replace helpers (backward-compat preserved; existing
`tests/tcyr/regex.tcyr` still green). New gate
`tests/tcyr/regex_engine.tcyr` — **89 byte-level assertions**
in 13 groups: literals, anchors, classes, predefined,
quantifiers (greedy + lazy + brace), alternation (incl.
3-way), grouping, captures, boundaries, common patterns.
Two engine bugs caught + fixed: gen-counter timing
(bumped after step instead of before, blocked first-step
loop adds), and half-open shift target bound (3-way alt's
JMP-to-end-of-fragment missed by `[lo, hi)` bound). cc5
unchanged at **715,920 B** (lib-only addition; compiler
untouched). **check.sh 38/38 PASS** (tcyr 108 → 109; gate
count unchanged). Out of scope (deferred): backreferences,
lookaround, Unicode property classes, multiline flag.
v5.7.19 = kernel-mode emit-order fix
(THE agnos team request — proposal confirmed kmode swap is
the entire ask; reclaimed v5.7.20 placeholder). +1 cascade
absorbed by v5.7.34 backstop (was v5.7.33; bumped at v5.7.20 ship to queue lib/json.cyr follow-ups — pretty-print, streaming, JSON Pointer — pinned in the v5.7.x patch slate).)

**5.7.17** (shipped 2026-04-27 — **STRUCT CAP 64 → 256 +
DUMP-ON-OVERFLOW DIAGNOSTIC**. kybernet 2026-04-27 surfaced
the cc3-era 64-struct ceiling: pulling 3 dep dist bundles
(libro 29 + agnosys 10 + agnostik 9 + argonaut 27) into one
TU exceeded the cap, and the diagnostic blamed the first
user-code struct line even though that file defined exactly
1 struct. v5.7.17 raises the cap to 256 (kybernet's
recommendation), relocates `struct_fcounts` 0x18E830 →
0x18EE30 to make room for the expanded `struct_names` region,
grows `struct_ftypes` and `struct_fnames` from 16 KB to 64 KB
each (in place; ~496 KB free heap above each), and adds a
`DUMP_STRUCTS(S)` helper that prints every registered struct
name to stderr before the cap-overflow ERR_MSG fires —
mirroring the `note: N unreachable fns` pattern. cc5 byte-
identical at **715,920 B** (was 715,312 B; +608 B for
DUMP_STRUCTS + the new error message). New gate
`tests/regression-struct-cap.sh` (gate 4aa): 80-struct
compile clean (would fail at #65 pre-v5.7.17); 200-struct
compile clean (kybernet-class workload); 257-struct overflow
dumps the full `#0..#255` registered name list followed by
the `max 256` error line. **check.sh 38/38 PASS** (was 37/37;
+gate 4aa). **v5.7.x backstop bumped v5.7.28 → v5.7.33** at
this ship — 5-slot extension absorbs the +1 cascade and
restores RISC-V's full 3-5 sub-patch range without forcing
the low end. Out-of-scope per kybernet directions 2 and 3:
struct-level DCE and module-level visibility (bigger
redesigns; revisit if 256 starts feeling tight). Per-file
struct attribution also out-of-scope (current name-only
attribution is enough; revisit if users still struggle).)

**5.7.16** (shipped 2026-04-27 — **`cyrius init` / `cyrius port`
FIRST-PARTY-DOCUMENTATION DOC-TREE**. Closes the v5.7.14-as-
bundle 3-patch split: v5.7.14 transitive deps + v5.7.15 lib-vs-
bin + v5.7.16 doc-tree all shipped 2026-04-27. Both `cyrius
init` and `cyrius port` now scaffold the standard `docs/adr/`
(README + template), `docs/architecture/` (README),
`docs/guides/` (getting-started, shape-aware), `docs/examples/`
(.gitkeep), `docs/development/` (state + roadmap stubs), plus
a default root CLAUDE.md following durable-vs-volatile split
(no inlined state — Current State block points at
docs/development/state.md). Legacy `--agent` flag is now a
deprecated no-op; the v5.7.16 default template subsumes the
three legacy presets (generic/agnos/claude). cc5 unchanged at
**715,312 B** (scripts-only edits — both `cyrius-init.sh` and
`cyrius-port.sh`; compiler untouched). New gate
`tests/regression-init-doctree.sh` (gate 4z): 5 cases —
`--lib` emits 8 doc-tree files; `--bin` emits same;
bare defaults to `--bin` and emits same; `cyrius port`
mirrors; durable-vs-volatile invariant checked
(state.md carries the toolchain pin AND CLAUDE.md must NOT).
**check.sh 37/37 PASS** (was 36/36; +gate 4z).)

**5.7.15** (shipped 2026-04-27 — **`cyrius init --lib`/`--bin`
LIBRARY SCAFFOLD**. `scripts/cyrius-init.sh` grew a `SHAPE`
variable + `--lib`/`--bin` flag parsing. Lib shape emits
`[build] entry = "programs/smoke.cyr" output =
"build/<name>-smoke"` + `[lib] modules = ["src/main.cyr"]`,
header-only `src/main.cyr`, and a `programs/smoke.cyr`
proof program (mabda/sigil/sankoch convention). Bin shape
keeps the existing binary scaffold. Bare `cyrius init <name>`
defaults to `--bin` for backward-compat. README, CI/release
workflows, dry-run listing, and final next-steps all
shape-aware. cc5 unchanged at **715,312 B** (scripts-only
edit; compiler untouched). New gate
`tests/regression-init-lib-bin.sh` (gate 4y): 4 cases —
`--lib` smoke build clean, `--bin` keeps binary, bare =
`--bin`, lib CI targets programs/smoke.cyr. **check.sh 36/36
PASS** (was 35/35; +gate 4y). Second of three patches
splitting the v5.7.14-as-bundle plan from 2026-04-23.
v5.7.16 = doc-tree alignment (last of trio). Agent CLAUDE.md
heredocs in cyrius-init.sh still hardcode binary build hint —
will be folded into v5.7.16 doc-tree work.)

**5.7.14** (shipped 2026-04-27 — **`cyrius deps` TRANSITIVE
RESOLUTION** — `cbt/deps.cyr` grew a BFS recursive walker that
processes each resolved dep's own `cyrius.cyml`. `_dep_visited`
(closest-wins de-dup) + `_dep_queue` (resolved manifest dirs to
walk) + `_process_named_deps(buf, n, manifest_dir)` extracted
from cmd_deps's Phase 2 body. Phase 3 drains the queue. Cycles
break naturally (re-encountered names hit visited). Diamonds
collapse to single-symlink. Relative `path = "..."` resolves
against the transitive manifest's directory, not the consumer's
cwd. cc5 unchanged at **715,312 B** (cbt-only edit; compiler
untouched). build/cyrius now **152,320 B**. New gate
`tests/regression-deps-transitive.sh` (gate 4x): 4 cases —
3-level chain, diamond, cycle, relative-path. **check.sh 35/35
PASS** (was 34/34; +gate 4x). First of three patches splitting
the v5.7.14-as-bundle plan from 2026-04-23: v5.7.15 = init
lib-vs-bin, v5.7.16 = doc-tree alignment. Per user direction
+2 cascade through closeout; v5.7.28 hard cap now requires
RISC-V to land at the 3-sub-patch low end. Three known
limitations deferred (stdlib transitive expansion, self-package
detection, version-conflict warnings).)

**5.7.13** (shipped 2026-04-27 — **STRING-LITERAL ESCAPE
SEQUENCES** — `\x##`, `\u####`, `\u{...}`, plus the previously-
missing C-family escapes `\a` `\b` `\f` `\v` `\'`. cyim-
unblocking: `"\x1b[?1049h"` and family now decode to actual
escape bytes; pre-v5.7.13 lex stripped the `\` and emitted the
next byte verbatim, so cyim's interactive surface rendered
literal `x1b[?1049h` text and was unusable. cc5 710,312 →
**715,312 B** (+5,000 B for the new decoders + helpers + error
messages). New `_LEX_HEX_VAL` (ASCII hex digit -> [0..15] / -1)
and `_LEX_EMIT_UTF8` (codepoint -> 1-4 byte UTF-8) helpers in
`src/frontend/lex.cyr`. Surrogate codepoints (D800-DFFF) and
codepoints > U+10FFFF are lex errors; bad-hex / wrong-arity /
empty `\u{}` / 7+ digit `\u{}` / missing close-brace all
produce explicit lex errors with `error:LINE: ...` shape.
TS lex left untouched (records source spans without decoding).
Acceptance: `tests/tcyr/string_escapes.tcyr` (77 byte-level
assertions covering all classic + new forms across UTF-8
boundaries U+007F / U+0080 / U+07FF / U+0800 / U+FFFF /
U+10000 / U+10FFFF + the canonical cyim alt-screen sequence)
and `tests/regression-string-escapes.sh` (gate 4w; 11 reject
cases). cc5 self-host byte-identical fixpoint at 715,312 B.
**check.sh 34/34 PASS** (was 33/33; +gate 4w). RISC-V remains
slid to v5.7.22-v5.7.26; closeout target unchanged at
v5.7.28.)

**5.7.12** (shipped 2026-04-27 — **CYRIUS-X BYTECODE PATH B**.
Stops `parse_*.cyr` from emitting raw x86 instruction bytes
into the CYX bytecode stream. cc5 709,776 → **710,312 B**
(+536 B for the `_TARGET_CX` flag + 7 path-B guards). cc5_cx
output is now clean CYX bytecode — pre-v5.7.12 had
`4889 5df8 4c89 65f0 ...` (x86 callee-save chains) leaked
through from regalloc save/restore. Inventory: 67 raw
direct-emit hits in `parse_*.cyr` collapsed to ~10 logical
sites; 7 guarded with `_TARGET_CX == 0`, 3 already
arch-conditional. Path A (named-op refactor across 3
backends) **pinned long-term** in roadmap — trigger when
RISC-V or 2+ new direct-emit sites make path B unwieldy. cx
output `CYX\0` magic + valid CYX opcodes only, zero x86
bytes. New `tests/regression-cx-roundtrip.sh` (gate 4v)
verifies path B holds: greps cc5_cx output for known x86
instruction-byte signatures (`4889 5df8`, `4c8b 65f0`); fails
if any leak. **check.sh 33/33 PASS**, x86 fixpoint clean.
Two pre-existing limitations documented for follow-up: (a)
syscall arg literal-propagation bug — cc5_cx's EMOVI on
syscall args emits `movi r0, 0` instead of `movi r0, N` for
literal N (pin v5.7.x patch slot); (b) f64 ops on cx still
emit raw x87/SSE bytes (none in v5.7.12 acceptance gates,
pin if consumer surfaces). **v5.7.13 (string-literal escape
sequences `\x##` / `\u####` — cyim-unblocking) is now next;
RISC-V slid to v5.7.22-v5.7.26 to clear the bug/UX patch slate
first.**)

**5.7.11** (shipped 2026-04-27 — **`main_cx.cyr` DRIFT FIX +
CI GATE**. Smaller-slot scope per user 2026-04-27
("correctness over new features always"). v5.7.10's cross-arch
verify surfaced `error: undefined variable 'IR_RAW_EMIT'` on
the cyrius-x bytecode entry. Investigation showed accumulated
silent drift: 4 missing pieces, 2 dead colliding stubs, an
undersized brk. **No CI gate ever built cx**, so each frontend
addition silently broke it. Fixes: `include "src/common/ir.cyr"`
added (was added to main.cyr at v5.6.12, never propagated);
`var _AARCH64_BACKEND = 0` + `_TARGET_MACHO = 0` +
`_TARGET_PE = 0` + `_flags_reflect_rax = 0` + 4 peephole-
tracker globals (`_last_push_cp`, `_last_emovca_cp`,
`_last_movca_popr_cp`, `_INLINE_OK`, `_LOOPVAR_OK`) added to
`backend/cx/emit.cyr`; 2 dead `PF64BIN`/`PF64CMP` cx stubs
deleted (v5.7.9 duplicate-fn warning surfaced — collided with
parse_expr.cyr authoritative versions); brk bumped 5.5 MB →
39 MB to reach tok_types at `S+0x74A000`. **CI gate (the
durable fix):** `tests/regression-cx-build.sh` (gate 4u in
check.sh) runs 3 checks: cc5 builds main_cx.cyr cleanly, cc5_cx
exits clean on empty input, cc5_cx exits clean on trivial
input. cc5 unchanged at 709,776 B (cx-only edits); cc5_cx now
builds at 365,696 B. **check.sh 32/32 PASS**, x86 fixpoint
clean. **Bytecode SEMANTIC correctness explicitly cascaded to
v5.7.12** — parse_*.cyr emits raw x86 via `E3(S, 0xC18948)`-
style calls in shared codepaths; cx interpreter sees x86 noise
interleaved with valid CYX opcodes. Multi-session
parser-to-emit re-architecture work, not a wedge. RISC-V
cascaded v5.7.12 → v5.7.13.)

**5.7.10** (shipped 2026-04-26 — **`input_buf` 512 KB → 1 MB
HEAP-MAP RESHUFFLE** — load-bearing unblock; hisab was at 96 %
of cap and censoring upstream, every consumer of hisab via
`cyrius deps` auto-prepend inherited 505 KB before its own
source could land. cc5 unchanged at **709,776 B** (heap-only
change; instruction encoding bytes unaffected). Cap value
(524288 → 1048576) bumped at 3 sites/file × 6 main_*.cyr files
+ 1 PP IFDEF copy-back site in `lex_pp.cyr`. **Heap shift +
0x100000** on 95 distinct region addresses originally in
0x80000..0xFFFFF — they land in 0x180000..0x1FFFFF, clearing
the existing 6-digit squatters at 0x104000-0x14A000 (which had
to stay put). +0x100000 not +0x80000 because the +0x80000
naive shift would collide with 3 existing addresses
(0x10C000 / 0x11A000 / 0x122000); +0x100000 lifts cleanly into
the empty 0x180000..0x1FFFFF range. Bare-hex comment refs
shifted in the same sweep (96 occurrences); 4 boundary
comments over-shifted by the sweep (where 0x80000 was the
input_buf END, not a region address) hand-corrected back to
0x100000 (new input_buf end) or 0x80000 (tok_names overlay
end). **brk unchanged** at 0x348C000 (52.5 MB) — the +0x100000
shift packs into already-allocated heap; no `SYS_BRK` size
change. Error message `"input exceeds 512KB buffer..."` (68 B)
→ `"input exceeds 1MB buffer..."` (66 B); write length operand
updated. New regression `tests/regression-input-1mb.sh` (gate
4t in check.sh) compiles a 639 KB comment-padded source
through cc5; pre-v5.7.10 would have errored. **check.sh
31/31 PASS**, 3-step fixpoint clean, 5/5 main_*.cyr cross-arch
builds pass (x86 ELF, aarch64 ELF, aarch64-native,
aarch64-mach-o, Win64 PE). main_cx.cyr cyrius-x entry is
*pre-existingly broken* on `IR_RAW_EMIT undefined` (same shape
as v5.6.32 native-aarch64 missing-include); out of v5.7.10
scope, deserves its own slot. v5.7.11 RISC-V is now next.)

**5.7.9** (shipped 2026-04-26 — **SILENT FN-NAME COLLISION
INVESTIGATION**. cc5 709,688 → **709,776 B** (+88 B net —
warning emit code +312 B; dead `EADDIMM_X1` imm8-form removal
−224 B). Lifted from v5.7.10 → v5.7.9 same day when the
v5.7.10 input_buf reshuffle audit showed it deserves its own
slot. **Audit:** `docs/audit/2026-04-26-stdlib-fn-collisions.md`
— 66 names appear duplicated across `lib/*.cyr`, **only
`json_build` is genuine cross-module** (rest are arch-
conditional, one variant per build via `#ifdef`). **Resolution
rule:** option (b) warn + last-wins (arity-aware overload
resolution is a separate language addition, no slot pinned).
**cc5 change:** `parse_fn.cyr:601` checks `FINDFN` result; if
slot already has non-`-1` body offset, emit `warning:
<file>:<line>: duplicate fn '<name>' (last definition wins)`.
Forward decls (offset stays `-1` until body lands) do NOT
trigger. **Internal collision surfaced + fixed:** dead
imm8-form `EADDIMM_X1` deleted from `src/backend/x86/emit.cyr`
(imm32-form had been winning silently for unknown number of
versions; bytes unchanged at call sites because imm32 handles
all small values). **First ecosystem collision resolved at
source:** patra v1.8.3 → **v1.9.0** rename `fn json_build/6` →
`fn patra_json_build/6`; `cyrius.cyml` `[deps.patra]` pin
bumped 1.8.3 → 1.9.0. **Regression:** new
`tests/regression-fn-collision.sh` (3 cases: same-arity dup,
diff-arity dup, forward-decl no-false-positive) wired as
check.sh gate 4s; check.sh **30/30 PASS**. RISC-V rv64
remains at v5.7.11; v5.7.10 = `input_buf` 512KB → 1MB heap
reshuffle (load-bearing — hisab at 96% of cap) follows.)

**5.7.8** (shipped 2026-04-26 — **`cyrius check` REPAIR +
`cyrius deps` ERGONOMICS + SYSCALL ARITY WARNING FIX**. cc5
709,544 → **709,688 B** (+144 B). Bundle of silent-failure /
UX fixes surfaced during cyrius-bb wiring:
**(1)** `cyrius check`: `/dev/null.tmp.<pid>` open-fail bug
fixed by switching to PID-suffixed `/tmp` path; default-on
`--skip-deps` (parse standalone, not against manifest deps);
new `--with-deps` opt-in for legacy auto-prepend; "is a
module" tautology removed; `lex.cyr:95` token-cap message
length off-by-one (37 written as 36) fixed.
**(2)** Syscall arity: `_SC_ARITY(112)` SYS_SETSID 1 → 0
(closes `lib/syscalls_x86_64_linux.cyr:358` warning);
structural skip for `sc_num=2 && got=4` cross-arch openat
sentinel pattern (closes `lex.cyr:227+240+<source>:7`
warnings). cc5 self-build emits ZERO arity warnings.
**(3)** `cyrius deps` P1-P5: P1 silent dangling symlinks
now hard-error (`error: [deps.X] modules entry "..." not
found at tag in ...`); P2 `--help` branches added; P3
`deps`/`update` listed in top-level `cyrius help`; P4
`copied` counts distinct deps (one per `[deps.NAME]` block
that succeeded), not per-module operations — cold/warm
match; P5 `cyrius.lock` written by default after every
successful resolve, `--no-lock` opt-out; lockfile flag
family documented.
**(4)** `cyrius build --no-deps` flag added (closes the
v5.7.7 carry-forward pin). `_had_error` exit-code
infrastructure added but no error path writes to it yet
(deliberate: undefined-fn-with-call-site reverted because
tests rely on the historical "warn, don't abort, partial
includes are common in test files" semantics).
3-step fixpoint clean. check.sh 29/29.
RISC-V rv64 (was v5.7.8) cascaded → v5.7.11; v5.7.9 =
`input_buf` 512 KB → 1 MB; v5.7.10 = silent fn-name collision
investigation.)

**5.7.7** (shipped — fixup-cap 1MB+ + tool-issue bundle.
cc5 704,976 → **709,544 B**. Fixup table 262K → 1M; lint
UFCS Pascal-prefix exemption; `cyrius build` atomic-output.)

**5.7.6** (shipped — **CYRIUS-TS JSX INNER-EXPR TOKENIZATION
(P4.3d)**. Closes v5.7.5's empty `JSX_EXPR_CONTAINER` deferral.
Lex now tokenizes `{...}` JSX expression bodies via mode-stack
dispatch (modes 4=JSX_TAG, 5=JSX_TEXT, 8=JSX_EXPR on the
existing template stack); main TS_LEX loop dispatches to per-
mode helpers `TS_LEX_JSX_TAG` / `TS_LEX_JSX_TEXT`. Parser
consumes real expressions inside `JSX_EXPR_CONTAINER` /
`JSX_ATTRIBUTE` / `JSX_SPREAD_ATTR`. v5.7.3 post-`>` `(`
generic-arrow disambig REMOVED — the pre-flight `BYTE_SKIP`
check correctly rejects generic arrows while accepting
paren-prefixed JSX text (`<span>(optional)</span>`).
`TS_LOOKAHEAD_IS_ARROW` COLON-branch extended with JSX
scope-terminator tokens (was the root cause of the v5.7.5
P4.3d-2 attempt's 57-file regression that triggered rollback).
`IS_PRIMARY_CONTEXT` whitelist extended for JSX_CLOSE_END /
JSX_SELF_CLOSE / JSX_FRAGMENT_CLOSE. `.tsx`: 429 → **430/435 =
98.85%**. Threshold 429 → 430. `.ts`: held at
2033/2053 = 99.03%. cc5 697,840 → **704,976 B** (+7,136 B);
3-step self-host fixpoint clean.
`regression-ts-parse-tsx.sh` threshold 429 → 430.)
**5.7.5** (shipped — **CYRIUS-TS REAL JSX AST**. Closes the v5.7.0–
v5.7.5 cyrius-ts arc by replacing v5.7.3's `TOK_INT` placeholder
with structured JSX tokens + AST nodes. Lex emits 13 JSX token
kinds in block 300-312 (`OPEN_START`/`TAG_NAME`/`ATTR_NAME`/
`ATTR_VALUE_STRING`/`OPEN_END`/`CLOSE_START`/`CLOSE_END`/
`SELF_CLOSE`/`TEXT`/`EXPR_OPEN`/`EXPR_CLOSE`/`FRAGMENT_OPEN`/
`FRAGMENT_CLOSE`); parser builds 9 JSX AST kinds in block 700-708
(`JSX_ELEMENT`/`JSX_FRAGMENT`/`JSX_OPENING`/`JSX_CLOSING`/
`JSX_ATTRIBUTE`/`JSX_SPREAD_ATTR`/`JSX_EXPR_CONTAINER`/`JSX_TEXT`/
`JSX_NAME`) via `TS_PARSE_JSX_ELEMENT` invoked from `PRIMARY`.
`TS_LEX_JSX_SKIP` and `TS_LEX_JSX_SKIP_INNER` deleted (256 LOC).
New `TS_LEX_JSX_BYTE_SKIP` (catches generic types like
`Foo<HTMLParagraphElement>` mis-firing as JSX via stray-`}` bail);
`TS_LEX_JSX_SKIP_WS` extended to skip `//` + `/* */` comments
inside JSX tags. `.tsx` parse acceptance 428 → **429/435 = 98.6%**;
`.ts` held at 2033/2053 = 99.03%. cc5 687,088 B → **697,840 B**
(+10,752 B); 3-step self-host fixpoint clean. New tcyrs:
`ts_lex_p43.tcyr` (49 assertions, 12 groups) + `ts_parse_p43.tcyr`
(11 groups). `regression-ts-parse-tsx.sh` threshold 425 → 429.
check.sh 29/29. Inner-expr tokenization deferred to v5.7.6 — empty
`JSX_EXPR_CONTAINER` in this iteration; mode-stack-driven prototype
reverted at end of v5.7.5 work for clean cut. 6 sticky `.tsx`
failures remain (non-JSX TS feature gaps: generic method types,
`!:`, multi-arg generics, computed-key destructure, multi-line
JSX block comment, one cumulative shape) — each its own slot.)

**5.7.4** (shipped — **CYRIUS-TS CLEANUP PASS**. .ts parse acceptance
crossed 99% (2020 → **2033/2053 = 99.03%**). .tsx held at
**428/435 = 98.4%** (the 7 sticky JSX edges cascade to v5.7.5's real
JSX AST work). Async modifier now recorded as bit 48 of SPAN on
DECL_FUNCTION / EXPR_ARROW / DECL_METHOD nodes via the new
`TS_AST_CONSUME_ASYNC` / `TS_AST_IS_ASYNC` helpers + the
`TS_PS_PENDING_ASYNC` parser-state slot — wired into 9 AST_PUSH sites
+ 8 async-consume sites. P4.1: `typeof import("...")` composite type,
template-interp brace tracking fix (object literals inside `${...}`
now balance correctly; P1.4 test updated 7-tok → 8-tok), broader
PRIMARY ident-equivalent list (KW_OVERRIDE/DECLARE/NAMESPACE/READONLY
/INFER/SATISFIES/PUBLIC/PRIVATE/PROTECTED/STATIC/ABSTRACT/IMPLEMENTS
accepted as variable names). P4.5: `async <T>(x) => ...` generic
arrow now parses. New `tests/tcyr/ts_parse_p44.tcyr` (25 assertions).
Thresholds: `regression-ts-parse.sh` 2000 → 2030;
`regression-ts-parse-tsx.sh` 420 → 425. cc5 687,088 B (+3,280 from
v5.7.3); self-host byte-identical. check.sh 29/29.). .ts parse acceptance
crossed 99% (2020 → **2033/2053 = 99.03%**). .tsx held at
**428/435 = 98.4%** (the 7 sticky JSX edges cascade to v5.7.5's real
JSX AST work). Async modifier now recorded as bit 48 of SPAN on
DECL_FUNCTION / EXPR_ARROW / DECL_METHOD nodes via the new
`TS_AST_CONSUME_ASYNC` / `TS_AST_IS_ASYNC` helpers + the
`TS_PS_PENDING_ASYNC` parser-state slot — wired into 9 AST_PUSH sites
+ 8 async-consume sites. P4.1: `typeof import("...")` composite type,
template-interp brace tracking fix (object literals inside `${...}`
now balance correctly; P1.4 test updated 7-tok → 8-tok), broader
PRIMARY ident-equivalent list (KW_OVERRIDE/DECLARE/NAMESPACE/READONLY
/INFER/SATISFIES/PUBLIC/PRIVATE/PROTECTED/STATIC/ABSTRACT/IMPLEMENTS
accepted as variable names). P4.5: `async <T>(x) => ...` generic
arrow now parses. New `tests/tcyr/ts_parse_p44.tcyr` (25 assertions).
Thresholds: `regression-ts-parse.sh` 2000 → 2030;
`regression-ts-parse-tsx.sh` 420 → 425. cc5 687,088 B (+3,280 from
v5.7.3); self-host byte-identical. check.sh 29/29.)

**5.7.3** (shipped — **CYRIUS-TS COMPLETION + JSX**. Continues the
v5.7.2 cyrius-ts arc: 80% → **98.4%** SY .ts parse acceptance via
16 iterative fix batches against the diag harness, plus a new
JSX-aware lex skip that lifts SY .tsx parse acceptance from 0.5%
(2/435) to **98.2%** (427/435). check.sh active gates 28 → 29
(new `regression-ts-parse-tsx.sh`). P3.1: async object-method
modifier, nested-generic call consume, broadened param-name
acceptance, `import("./mod").T` types, `for await` loops,
generator `*` markers (function/method/object), `yield`/`yield*`
in UNARY, broadened binding-pattern names, computed property
names, array destructure holes, FLOAT lex (frac + exponent —
`1e-7` no longer lexes as 4 tokens), TYPE_OBJECT method sigs,
function-overload bodies optional, `declare global { ... }`,
`new () => T` constructor types, `value is T` predicates,
`override`/`declare` modifiers, import attributes
`with { type: 'json' }`. P3.3: `TS_LEX_JSX_SKIP` byte-level scanner
recognizes `<IDENT`/`<>` in expression context (via
`TS_IS_PRIMARY_CONTEXT` walk-back), walks balanced JSX tags +
fragments + `{...}` exprs (with template-literal awareness) +
nested JSX, emits one `TOK_INT` placeholder per JSX expression.
Generic-arrow disambiguation (`<T extends U>(args) => body`)
recognized as not-JSX via post-`>` `(` lookahead. cc5 683,808 B
(+17,600 from v5.7.2); self-host byte-identical. Remaining
~8 .tsx + ~33 .ts edge cases slated for v5.7.4 (final cyrius-ts
cleanup).)

**5.7.2** (shipped — **CYRIUS-TS FOUNDATIONAL**. TypeScript
frontend for the Cyrius compiler shipped as 7 phases (P1.1–P1.7
lex + P2.1–P2.7 parse). 462 lex assertions + 367 parse assertions
all green; 100% SY .ts lex acceptance; 1642/2053 (80%) SY .ts
parse acceptance via new `regression-ts-parse.sh` gate (≥ 1600
threshold). Iterative triage on the SY corpus delivered 196 → 1642
PASS through ~15 fix batches: trailing commas, broadened
keyword-as-name acceptance, async/import.meta/dynamic-import,
`as`/`satisfies` postfix, generic-call lookahead with
depth-aware nested paren/brace/bracket disambiguation, top-level
enum/namespace/declare decls, conditional types, `infer T`,
`value is T` predicates, abstract methods, computed member names,
object method shorthand, constructor parameter properties,
destructure rename + default. Children-array sentinel pattern
(children[0] = -1) lets payload-stored "0" unambiguously mean
"no list". Heap-relative offsets via `ts_base` decouple TS
frontend from main.cyr's heap layout. Diagnostic `--parse-ts`
emits `code=N line=L tok=T cur_idx=X err_idx=Y`. cc5 666,208 B
(+34,624 from v5.7.1); self-host byte-identical. check.sh 27 → 28
active gates. Remaining ~411 SY edge cases (mapped types,
`asserts` predicates, JSX in .tsx, complex destructure) slated
for v5.7.3.)

**5.7.1** (shipped — **fixup-table cap bump 32,768 → 262,144**.
sit-blocking ecosystem unblock per sit's proposal. All 8 named
sandhi consumers (vidya/yantra/hoosh/ifran/daimon/mela/ark/sit)
now able to actually pin sandhi in `[deps].stdlib` without
overflowing the fixup table. Wedged into v5.7.1 via git rewind +
fixup-cap commit + cherry-pick of cyrius-ts P1.1+P1.2 work back
on top (preserved on `wip/cyrius-ts-p1` branch during the dance).
16 cap-check sites updated across 5 backend files; brk extended
+3.5 MB across 4 main entry files; capacity-meter output and
heap-layout comments updated. cc5 self-host fixpoint clean at
531,880 B (8 B smaller than v5.7.0; cc5 itself never approaches
32K fixups so cap bump doesn't change its behavior). check.sh
26/26 PASS.)

**5.7.0** (shipped — **THE SANDHI FOLD**. Clean-break consolidation
per [sandhi ADR 0002](https://github.com/MacCracken/sandhi/blob/main/docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).
`lib/sandhi.cyr` adds (vendored byte-identical from `sandhi/dist/sandhi.cyr`
at the v1.0.0 tag, 376,037 B / 9,649 lines, 469 fns); `lib/http_server.cyr`
deletes (no alias, no passthrough); `tests/tcyr/http_server.tcyr` deletes
with it. All 17 deprecated `http_*` public fns have 1:1 `sandhi_server_*`
replacements (audit-confirmed pre-fold, full table in CHANGELOG).
`scripts/lib/audit-walk.sh` extended to skip `cyrius distlib`-generated
files in fmt+lint walks (marker-based, complements existing symlink-based
skip for `cyrius deps`-managed deps; dep files skipped 6 → 7).
Acceptance gates 1, 2, 5, 6 ✅ on cyrius side; gates 3 + 4 (downstream
sweep across yantra/hoosh/ifran/daimon/mela/vidya/sit-remote/ark-remote)
are separate work, organized by user. Sandhi repo enters maintenance
mode — subsequent surface patches land via Cyrius release cycle.
Zero compiler change → cc5 byte-identical at 531,888 B; check.sh
26/26 PASS.)

**5.6.45** (shipped — VS Code TextMate grammar refresh.
Extended `editors/vscode/syntaxes/cyrius.tmLanguage.json` to
cover the v5.6.x syntax wave: 4 new keywords (`secret`, `match`,
`in`, `shared`) + 10 new directives (`#deprecated`, `#pe_import`,
`#must_use`, `#regalloc`, `#endplat`, `#include`, `#ifplat`,
`#elif`, `#else`, `#ifndef`). All grep-confirmed as live cyrius
syntax before adding. Directives ordered longest-prefix-first
to avoid Oniguruma alternation false-matches. JSON valid. Pairs
with v5.6.44: now the `#deprecated("use lib/sandhi.cyr instead")`
attributes on `lib/http_server.cyr` render as preprocessor
directives in VS Code, making the deprecation banner unmissable.
Zero compiler change → cc5 byte-identical at 531,888 B; check.sh
26/26 PASS.)

**5.6.44** (shipped — v5.7.0 prep patch. `lib/http_server.cyr`
deprecation-notice cycle: all 17 public fns marked
`#deprecated("use lib/sandhi.cyr instead -- removed at v5.7.0")`
via the v5.6.4 fn-attribute mechanism + file-header deprecation
block. Per-call-site warning fires at every consumer call site
(stronger notice than one-shot include-time print). Satisfies
roadmap line 718 prerequisite. Zero compiler change → cc5
byte-identical at 531,888 B; check.sh 26/26 PASS;
http_server.tcyr 31/31 with 31 deprecation warnings fired.
v5.7.0 fold blocks on sandhi M5 → v1.0.0 tag + downstream
consumer-side dual-build branches + `cyrius distlib`
verification.)

**5.6.43** (shipped — LAST polish patch of v5.6.x. Closeout finish
(CLAUDE.md "Closeout Pass" steps 9-11) + sigil 2.9.0 → 2.9.3 +
sankoch 2.0.3 → 2.1.0 dep bumps + output_buf 1MB → 2MB heap
reshuffle (16-region shift
+1MB; brk 22.5MB → 23.5MB) + heap-map fix-through across the 4
main_*.cyr files (stale fixup_tbl docs corrected; 0xA0000
documented as v5.6.27 codebuf-compaction tables not fixup_tbl)
+ vidya per-minor refresh (language/dependencies/ecosystem).
Sigil 2.9.3 brings AES-NI + SHA-NI compress (~80x SHA-NI
throughput win on hosts with hw support).)

## Compiler

- **cc5 (x86_64)**: **741,120 B** at v5.8.57 (unchanged since
  v5.8.54). Aggregate growth across v5.8.x cycle: 720,928 B at
  cycle entry (v5.8.0 / inherited from v5.7.48) → 741,040 B at
  v5.8.46 (token-array cap raise 262144→1048576 + tok_types/
  values/lines relocation, +20.1 KB) → 741,040 B held steady
  through .47-.53 (no compiler change in those slots) → 741,120
  B at v5.8.54 (+80 B for aarch64 EFLADDR + EFLADDR_X1 + 5 PE
  shim stubs + parse_expr.cyr syscall-arity skip extension) →
  741,120 B held .54-.57. Total v5.8.x growth: +20.2 KB across
  47 patches (.0-.57); the .46 token-cap raise + .54 cross-arch
  propagation are the only compiler-side bumps. `cc5 --version`
  reports `cc5 5.8.57`.
- **cc5_win (cross)**: 526,856 B (unchanged from v5.6.42 — same reason)
- **cc5_aarch64 native (Pi)**: 463,768 B (was: did not build — v5.6.32 added
  the missing `include "src/common/ir.cyr"` to `main_aarch64_native.cyr` that
  had been orphaned since v5.6.12 O3a shipped the IR instrumentation
  references to `IR_RAW_EMIT`)
- **cc5_aarch64 (cross)**: 439,904 B at v5.8.57 (was 411,136 at
  v5.6.39 → 411,520 B v5.7.x → 438,896 B v5.8.46 token-cap raise
  → 438,896 B silently frozen across v5.8.46-52 from the v5.8.53
  install-pipeline rebuild miss → 438,960 B v5.8.53 fresh build
  + new error format → 439,904 B v5.8.54 EFLADDR + EFLADDR_X1 +
  5 PE shim stubs + relevant byte deltas).
- **cc5_win (cross)**: 526,552 B (was 526,376 at v5.6.39)
- **cc5 native aarch64** (Pi 4 output): 503,328 B at v5.6.27 (+6,320 B vs
  v5.6.25's 497,008; the x86-only compaction code is dead-emitted on aarch64
  builds — `#ifdef CYRIUS_ARCH_X86` strip pinned as future cleanup)
- **Self-host fixpoint**: 3-step (cc5_a → cc5_b → cc5_c, b == c) clean at both
  `IR_ENABLED == 0` and `IR_ENABLED == 3` (since v5.6.16).
- **IR=3 NOP-fill on cc5 self-compile** (v5.6.18 baseline carries forward;
  v5.6.19 adds infrastructure only, no codegen change): 135 folds + 678 DCE +
  15 DSE + 567 LASE = 1,395 candidates / **6,099 B**. v5.6.27 compaction
  sweeps picker NOPs at IR=0 only; IR=3 NOP harvest (DSE/LASE/const-fold)
  pinned for a future slot — needs same-shape tracking added to those passes.
- **Regalloc** (v5.6.20–v5.6.24): per-fn live-interval tables (v5.6.19) +
  Poletto-Sarkar picker (v5.6.20) + asm-skip lookahead (v5.6.23) +
  fixed SysV stack-arg shuttle (v5.6.24). **Default-on as of v5.6.24**
  (`CYRIUS_REGALLOC_AUTO_CAP=0` to disable; previously opt-in via
  `#regalloc` only). Picker pins up to 5 locals to rbx/r12-r15.
  v5.6.24 fixed the SysV ECALLPOPS r12-r14 clobber that surfaced as
  the "live-across-calls" bug (sandhi-reported / flags-test
  test_str_short→test_defaults bisection). `CYRIUS_REGALLOC_DUMP=1`
  prints intervals; `CYRIUS_REGALLOC_PICKER_CAP=N` caps assignments
  for bisection.

## Suites

- **check.sh**: **65/65 PASS** at v5.8.57 (Linux x86_64 daily-
  driver + cross-platform regressions via SSH wiring to pi/cass/
  ecb). v5.8.x growth: 64 → 65 across 57 patches (the new gate
  was ts_advanced_pin_audit at v5.7.46-49; v5.8.x added zero
  named gates — Unicode arc + cross-arch propagation work all
  rode the existing auto-discovered tcyr suite gate). Cross-host
  gates: aarch64 native self-host + aarch64 syscalls + Mach-O
  cross-build runtime + PE Win64 runtime all go via the SSH
  config'd hosts (pi=Linux aarch64, ecb=Apple Silicon Darwin,
  cass=Windows PowerShell — empirically confirmed at v5.8.52
  cross-arch propagation slot).
- **`tests/tcyr/*.tcyr`**: **127 files** at v5.8.57 (Unicode arc
  added 4 — unicode_categories .49, unicode_casefold .50,
  unicode_normalize .51, unicode_normconf .52 — totaling 120,518
  asserts; cross-arch propagation work added zero new tcyrs but
  the .53 install-pipeline fix surfaced sit v0.7.2 as an
  end-to-end gate). v5.8.43 added `alloc_stdlib_pass3.tcyr` — 33 assertions across 11 groups covering str/map_u64 peripheral _a variants. v5.8.40 added `preprocessor_string_literal.tcyr` — 12 assertions across 5 groups for the PP string-literal awareness fix. v5.8.37 added `alloc_no_init.tcyr` — 17 assertions across 8 groups verifying alloc/alloc_via/arena_new/vec/str/hashmap all work without explicit alloc_init() (lazy-init proves out). v5.8.36 added `alloc_stdlib_pass2.tcyr` — 30 assertions across 10 groups covering json/toml/cyml/http _a variants, per-request-arena pattern, OOM behavior. v5.8.35 added `alloc_stdlib.tcyr` — 33 assertions across 14 groups covering vec/str/hashmap _a variants, bump/arena/test allocator dispatch, OOM via fail_after_n_allocs, default_alloc singleton consistency. v5.8.34 added `oom_handling.tcyr` — 33 assertions across 9 groups covering fail_after_n_allocs thresholds 0/1/3, alloc_count + bytes_total tracking, reset_via behavior, consumer-pattern fallback, vtable sanity. v5.8.33 added `alloc_iface.tcyr` — 43 assertions across 12 groups covering Allocator vtable layout, 3 default impls (bump/arena/test), dispatch helpers, fail_after threshold, cross-impl uniformity. v5.8.31 added `result_stdlib_pass2.tcyr` — 24 assertions across 12 groups covering the *_r variants of http/dynlib/pwd/grp/shadow/pam + ? propagation chain on pwd_getpwuid_r. v5.8.30 added `result_stdlib.tcyr` — 29 assertions across 14 groups covering the *_r variants of the io/json/toml/cyml modules, `?` propagation chain over open+read+close, round-trip write+read, json/toml/cyml synthetic-file Ok cases. v5.8.29 added `result_propagation.tcyr` — 29 assertions across 11 groups covering Ok unwrap, Err short-circuit at first/second `?`, `return expr?;` shape, `?` in binary-op context, `?` as first fn-body statement, `?` inside `if` body, payload roundtrip negatives + zero. v5.8.28 added `result.tcyr` — 24 assertions across 9 groups covering typed `Result<T, E>` + 6 helpers + match consumer + Result-returning fn shape. Plus v5.8.x sub-suite tcyrs: enum_generics 31/31, exhaustive_match 10/10, match_dedup 10/10, tagged 14/14, enums 10/10. ~3400 total assertions across the cyrius surface)
- **`tests/scyr/*.scyr`**: 1 file (v5.7.38 added `tests/scyr/alloc_pressure.scyr` — 10,000× alloc(4KB) + sentinel readback; runs via `cyrius soak`)
- **`tests/smcyr/*.smcyr`**: 1 file (v5.7.38 added `tests/smcyr/compile_minimal.smcyr` — minimal "fn returns literal" smoke; runs via `cyrius smoke`)
- **Release toolchain**: 10 bins (v5.7.39 promoted `cyrius-lsp` to `[release].bins` so fresh installs ship the navigation-capable language server; pre-v5.7.39 was install-on-demand via `cyrius lsp` subcommand)
- **`fuzz/*.fcyr`**: 5 harnesses
- **`benches/*.bcyr`**: 14 benchmarks
- **Stdlib**: 62 modules (55 first-party + 7 vendored/deps: 6 via `cyrius deps`
  symlinks — sakshi, patra, sigil, yukti, mabda, sankoch — plus
  `lib/sandhi.cyr` vendored from `cyrius distlib` at sandhi v1.0.0;
  v5.7.43 added `lib/test.cyr` table-driven testing helper;
  v5.8.28 added `lib/result.cyr` — `Result<T, E>` + 6 helpers
  carved out of `lib/tagged.cyr`, transitively re-included from
  tagged.cyr for backward compat)

## In-flight

**v5.8.47 ✅ shipped — starship + p10k prompt color split AND vidya cyrius-language audit. cc5 unchanged at 741,040 B (no compiler change). Part A (starship/p10k): ॐ Om → forestgreen `#228B22` TEXT, 🌀 cyclone → light blue `#87CEEB` TEXT (color on the text, not the background — first-pass attempt put it on bg, corrected after user feedback "not the background the text"); pre-fix both shared bg:teal/fg:base and visually collapsed. p10k uses 256-color fg codes -f 28/-f 117 for the same split. Part B (vidya audit, ~20K lines, 33 cyml files): 3 entries flipped to ✅ FIXED (`global_init_order_silent_zero` v5.7.32, `no_var_redecl_same_scope` v5.8.x, `multi_line_struct_enum_bodies_dont_parse` v5.8.x); 3 entries refreshed for stale cap/version refs (`the_gvar_wall` 256→1024, `the_256kb_ceiling` 256K→2M, `the_preprocessed_line_number_problem` still-active confirmation); 1 new local issue file for confirmed-still-active parser cosmetic limits (`bare_return_in_if_block_rejected` + `var_bracket_size_must_be_literal`). **Stale-pin streak now 4 of 6 in v5.8.x cycle**: parser/expression-grammar work between v5.8.20 and v5.8.40 closed three separate vidya-tracked items without anyone noticing until the audit. Pinned for v5.8.48 — parser-grammar slots should grep vidya field_notes/language/ for FIXED-by-side-effect entries. Verification: scripts/check.sh 65/65 PASS; cc5 self-host two-step byte-identical at 741,040 B; starship install acceptance gate green (cyrius-prompt-info renders in distinct colored segments). 47 of 55 pinned slots shipped (85.5%); 8 slots remaining. Phase 3 remaining: refactoring + heap-map cleanups (v5.8.48), full closeout pass (v5.8.49), deps cleanup (v5.8.50), release-valve (v5.8.51), Unicode 17.0.0 categories+normalization (v5.8.52-54), Unicode regression suite + final closeout (v5.8.55).**

**v5.8.46 ✅ shipped — arithmetic-in-fn-args regression-floor lock + token-array cap raised 262144 → 1048576 (sit v0.7.2 unblocked). cc5 740,528 → 741,040 B (+512 from v5.8.45's `_TOK_IS_KERNEL(S)` inheritance + Part B's PRNUM call sequence + relocated-offset literals; Part A added zero compiler bytes). Two coherent deliverables landed in the same slot. Part A closes the v5.8.34-filed arithmetic-in-fn-args pin (vidya `audio_dsp` 11-lang port, originally rejected `biquad_set(a_q15, 0, 0, a_q15 - ONE, 0)`) as a regression-floor lock — the parser fix landed earlier in the cycle as a side-effect of expression-grammar work, this part ships the test + vidya cleanup that should have followed; deliverables: new `tests/tcyr/expr_in_fn_args.tcyr` (30 assertions × all 18 operator shapes × operand-source mix × arg-position variation + biquad inline repro), vidya `audio_dsp/cyrius.cyr` workaround removed + missing `lib/syscalls.cyr` / `lib/vec.cyr` includes added, vidya field-note `no_comparisons_in_fn_args` flipped to ✅ FIXED, issue file archived. Part B closes the 2026-04-25-filed sit cap-overflow issue (sit-side, mirrored to cyrius archived/) — surfaced mid-slot when the user named the sit issue file ("`@../sit/docs/development/issues/2026-04-25-cyrius-fixup-table-cap.md` - sit cannot"); originally framed as "fixup-table" overflow but v5.8.45 retest's `error: token limit exceeded (262144)` came from a separate cap site — `lex.cyr:95` ADDTOK, not the fixup table (fixup caps had moved 32K → 262K → 1M in v5.7.x but ADDTOK hadn't moved since pre-v5.7.1). Part B sub-deliverables per the issue's preferred path: (B.1) ADDTOK diagnostic upgraded to print `needed M, cap is N`; (B.2) cap raised 4× to 1048576 + token arrays relocated from the 0x94A000/0xD4A000/0xF4A000 trio (each 2 MiB; tok_types overlapped output_buf at 0x94A000 — undocumented v3.6.2 recycling) to fresh post-TS-region high block at 0x368C000/0x3E8C000/0x468C000 (each 8 MiB). Brk extended in every main_*.cyr (main.cyr: 0x368C000 → 0x4E8C000; main_aarch64/macho/native/cx: 0x290B000 → 0x4E8C000); main_win.cyr MMAP raised 0x2000000 → 0x5000000. Bridge.cyr NOT touched (different bootstrap-chain offsets and its own smaller cap; bridge only compiles cc5 itself, well under 262K tokens). **Premise-check method memo** (folded into existing memory pin `feedback_premise_check_at_slot_entry`): revert the consumer workaround in the filing repo, recompile against unmodified cyrius — synthetic minimal programs miss shape-dependent bugs. Surfaced first in Part A (vidya audio_dsp; user push-back: "won't look at the repo that reported it... I forgot it was YOU IN THE REPO") and applied immediately in Part B (sit) — same lesson, two consecutive applications in one slot. **Slot-scope note**: Part B was added to v5.8.46 (rather than cut as a fresh v5.8.47) because v5.8.46 hadn't shipped yet — same fold-in pattern as v5.8.45's `kernel_ident.tcyr` correction. The originally-pinned v5.8.47 starship/vidya-audit slot stays at v5.8.47 (not yet shipped, not displaced). **Stale-pin streak**: 2 consecutive (v5.8.45 + v5.8.46-Part-A) + 3 total in v5.8.x cycle, but Part B ships actual consumer-unblocking work in the same slot, freeing vidya, yantra, hoosh, ifran, daimon, mela, ark, sit. Verification: 30/30 expr_in_fn_args assertions pass; CI-shape pipefail loop on 123 tcyr = 123 passed; cyrius `scripts/check.sh` 65/65 PASS; vidya audio_dsp port = 17/17 + zero warnings against the post-v5.8.46 cyrius lib; **sit v0.7.2 builds (1,283,232-byte binary; was parked at v0.7.1's ~709 KB) + sit `cyrius test` 127/127 PASS** — the canonical end-to-end gate for Part B. Self-host two-step byte-identical at 741,040 B. Pin candidates queued: cap-overflow diagnostics should include source file + line so future cap-site drift is unambiguous (v5.8.50 closeout); heap-map comments should be re-validated against actual code at every minor closeout — the tok_types-vs-output_buf overlap was a v3.6.2-era recycling pattern the comments never caught up to. Phase 3 remaining (9 slots): combined starship/p10k + vidya audit (v5.8.47), refactoring + heap-map cleanups (v5.8.48), full closeout pass (v5.8.49), deps cleanup (v5.8.50), release-valve (v5.8.51), Unicode 17.0.0 categories+normalization (v5.8.52-54), Unicode regression suite + final closeout (v5.8.55). 46 of 55 pinned slots shipped (83.6%); 9 slots remaining.**

**v5.8.45 ✅ shipped — `kernel` demoted from reserved token to plain ident. Premise-check rejected stale "lexer-context-sensitive" framing; bisection-sweep 4-of-5 stale; fix per preferred path with new `_TOK_IS_KERNEL(S)` byte-compare helper at 12 dispatch sites across 6 main.* files. AGNOS bootstrap byte-identical. **Cycle backstop EXTENDED v5.8.51 → v5.8.55** to absorb **Unicode 17.0.0 support** (https://www.unicode.org/versions/Unicode17.0.0/). v5.8.x will be the longest minor in cyrius history — that's fine, work fits the cycle better than starting v5.9.0 with half-built Unicode infrastructure.**
v5.8.0 cut the cycle open with the triple-anchor (fmt sweep +
vani fold-in + cyriusly starship.toml). 2026-05-01 strategic
re-theming compressed the originally-separate v5.10.x / v5.11.x /
v5.12.x language-feature minors INTO v5.8.x — slices, effect
annotations, tagged unions, `Result<T,E>` + `?`, allocators-as-
parameter all ship in this cycle so hisab + downstream consumers
do ONE port pass instead of 4-5. **30 firm pinned slots**, full
slot map at `docs/development/roadmap.md` §"v5.8.x — pinned slot
map". Bare-metal arc + RISC-V stay at v5.9.x.

**3-phase pinning** (firm 2026-05-01 at v5.8.0 ship; cascaded +1
2026-05-01 at v5.8.5 ship to absorb the SSH-gate carve-out):

Phase 1 — Quick-win unblockers (slots 1-8):
- **v5.8.1** ✅ `lint`/`fmt` 128 KiB cap raise (mabda A1) +
  `cyrius-prompt-info` redundancy fix
- **v5.8.2** ✅ `cc5_aarch64` packaging + `build/cyrc_check` orphan
- **v5.8.3** ✅ ts/parse.cyr fmt sweep follow-up (unblocked by .1)
- **v5.8.4** ✅ `f64_log2` aarch64 polyfill — parser dispatch (phylax #1)
- **v5.8.5** ✅ aarch64 SSH-gate extension for f64_log2 — hardware verification
- **v5.8.6** ✅ `sys_stat`/`sys_fstat` x86_64 wrapper backfill (phylax #2)
- **v5.8.7** ✅ `_SC_ARITY` cross-arch gate (phylax #3 + sakshi)
- **v5.8.8** ✅ phylax #4 NI-class investigation (stale pin; closed by sigil 3.0.0)

Phase 2 — Language vocabulary (slots 9-30; cascaded +4 at v5.8.9
ship to absorb slices re-scope from single-slot to 5-patch sub-arc):
- **v5.8.9** ✅ slices §1 — type-position parse-acceptance for `slice<T>` + `[T]`
- **v5.8.10** ✅ slices §2 — 16-byte alloc + lib/slice.cyr helper API (slice_set/of/ptr/len/zero/copy/eq/is_empty/is_null)
- **v5.8.11** ✅ slices §3 — Str ↔ slice<u8> structural equivalence (Str IS a slice; documented in both libs) + slice_from_cstr / slice_from_buf builders
- **v5.8.12** ✅ slices §4 — vec ↔ slice<T> structural-prefix equivalence (vec's first 16 bytes ARE a slice; documented in both libs) + vec_as_slice helper; hashmap excluded (no fit), 454-site migration deferred
- **v5.8.13** ✅ slices §5 — sub-arc FOUNDATION shipped (62 assertions across 4 tcyrs, auto-discovered by check.sh; downstream audit 5/7 deps clean). True-completion deferred work re-pinned as **v5.8.14–v5.8.19** (TYPE_SLICE typing + bounds-indexing + dot-field-access + Str migration + 454-site migration + true closeout) per user-direction "complete the task as assigned, it was there for a reason".
- **v5.8.14** ✅ slices §6 — TYPE_SLICE element-type tracking (parallel-array stash at 0x193400; GSLICE_W/SSLICE_W helpers; PARSE_VAR captures element width from `[T]` and `slice<T>` for all 22 variants)
- **v5.8.15** — slices §7 — Bounds-aware indexing `s[i]` (uses §6 element width; constant-index compile-time guard, runtime guard for vars)
- **v5.8.16** — slices §8 — Dot-syntax field access `s.ptr` / `s.len` (PARSE_FIELD_LOAD/STORE extension, struct-path unification)
- **v5.8.17** — slices §9 — Str API migration (str_data/str_len → .data/.len with backward-compat aliases; ~30 stdlib + cyrius src/ call sites)
- **v5.8.18** — slices §10 — Stdlib 454-site migration (sys_read 53 + memcpy 332 + memeq 69 → slice-typed signatures with `_slice` variants)
- **v5.8.19** — slices §11 — TRUE sub-arc closeout (downstream rebuild against migrated APIs, gates extended)
- **v5.8.20** ✅ Per-fn effect annotations (`#pure` / `#io` / `#alloc`)
- **v5.8.21–v5.8.27** ✅ Tagged unions + exhaustive match (sub-suite COMPLETE 2026-05-03; +5,568 B compiler delta; cascaded +2 at v5.8.22 ship)
- **v5.8.28** ✅ `Result<T,E>` carve-out into `lib/result.cyr` (typed shape, 24-assertion tcyr; zero compiler delta)
- **v5.8.29** ✅ `?` propagation operator (postfix on Result-typed exprs; lex token 124 + PARSE_TERM hook + tag-check / early-return / unwrap desugar; +968 B; 29-assertion tcyr; outside-fn-body parse error enforced)
- **v5.8.30** ✅ Stdlib migration pass 1: 4 modules (lib/io.cyr + lib/json.cyr + lib/toml.cyr + lib/cyml.cyr) gain Result-returning `*_r` variants with module-prefixed error enums; zero compiler delta; 29-assertion tcyr; required mid-slot cc5_aarch64 cross-compiler refresh
- **v5.8.31** ✅ Stdlib migration pass 2: 6 modules (http/dynlib/pwd/grp/shadow/pam) gain *_r variants + error enums; net.cyr skipped (pre-migrated); http_get bug fix (Result-as-fd); PARSE_STMT `?`-statement gap close (+816 B); 24-assertion tcyr
- **v5.8.32** ✅ Result+? sub-suite COMPLETE — closeout slot. Cross-repo smoke against sigil/mabda/yukti via temp-pin-bump methodology (all ✅); ark not present (flagged); 0 enum-name collisions; bonus benchmarks.md restore-as-stub fix for ci.yml required-docs gate
- **v5.8.33** ✅ Allocator vtable interface — 5-slot vtable + bump/arena/test impls + dispatch helpers (alloc_via/realloc_via/free_via/reset_via) + 43-assertion tcyr; zero compiler delta; foundation for v5.8.34-38 stdlib migration
- **v5.8.34** ✅ Failing-allocator test harness — `fail_after_n_allocs(n)` in lib/assert.cyr (thin wrapper over v5.8.33 test_allocator) + 33-assertion oom_handling tcyr; zero compiler delta
- **v5.8.35** ✅ Stdlib Allocator migration pass 1 — `_a` variants for vec/str/hashmap (vec_new_a / vec_push_a / str_from_a / str_new_a / str_cat_a / str_clone_a / str_from_int_a / map_new_a / map_new_str_a / map_set_a); back-compat wrappers via default_alloc() singleton; 33-assertion alloc_stdlib tcyr; zero compiler delta
- **v5.8.36** ✅ Stdlib Allocator migration pass 2 — 17 `_a` variants across json (12) / toml (2) / cyml (2) / http (1 partial + 1 internal); sandhi.cyr deferred (auto-generated bundle); 30-assertion alloc_stdlib_pass2 tcyr; zero compiler delta. Sandhi-side proposal handed off to parallel agent for v1.1.0
- **v5.8.37** ✅ alloc_init() lazy-init — `if (_heap_base == 0) { alloc_init(); }` guard in alloc() across Linux/macOS/Windows; alloc_init() now OPTIONAL; 17-assertion alloc_no_init tcyr; zero compiler delta
- **v5.8.38** ✅ Allocators sub-suite COMPLETE — closeout slot. Cross-repo smoke against sigil/mabda/yukti/ark via temp-pin-bump methodology (4-of-4 ✅; ark validated back-compat from a 7-minor-old pin 5.1.10 → 5.8.37); 0 enum/symbol collisions; 0/47 downstream alloc_init() sites migrated yet (opt-in); acceptance-gate audit captured (oom_vec_push Err shape + compiler-internal explicit Allocator partial — both pinned for v6.0.0); sandhi handed off to parallel agent for v1.1.0; **Phase 2 COMPLETE** (Result+? + Allocators sub-suites done in 11 slots total)
- **v5.8.39** ✅ sandhi v1.1.0 fold-in (re-slotted from preprocessor item by user direction at v5.8.38 ship). lib/sandhi.cyr 376,037 → 411,361 B (+35,324 / +9.4%); ~150 new public _a verbs in sandhi src; per-request-arena pattern realized end-to-end; 143 new sandhi alloc tcyrs (792 total assertions green). cyrius-side: zero compiler delta; no internal consumers broken (grep clean); downstream propagation via cyrius deps
- **v5.8.40** ✅ Preprocessor string-literal awareness (cascaded from v5.8.39). PP_PASS + PP_IFDEF_PASS gain in_string + escape_next state machines; `include "..."` inside string literals no longer mistaken for directives. cc5 +640 B (320 per pass). 12-assertion tcyr. Vidya entry flipped to ✅ FIXED.
- **v5.8.41** ✅ cyrlint large-file false-positive verification slot. Premise check (4 repros, all clean) found mabda-filed bug already resolved by intermediate cyrlint work between v5.7.23 and v5.8.40. New regression-floor gate (tests/regression-cyrlint-large-file.sh, 7010-line synthetic) wired into check.sh (gate count 64→65). mabda issue annotated as ✅ RESOLVED. Zero compiler delta.
- **v5.8.42** ✅ Paired UX polish (mabda A2 + C1). Half (a) `cyrius fmt --check` cbt arg-order fix (drift detection silently broken pre-fix; now matches Rust/Go silent-on-no-drift / exit-1-on-drift). Half (b) `var X;` bare-decl diag improvement (special-case ; token in PARSE_VAR + EMIT_GVAR_INITS, emit "uninitialized variable not allowed; use `var X = 0;`"). cc5 +216 B (entirely from half b).
- **v5.8.43** ✅ Phase 3 polish absorber — stdlib Allocator migration pass 3 (peripheral cleanup). 9 new str _a variants (str_sub_a / str_trim_a / str_split_a / 5 str_builder_*_a) + 3 new map_u64 _a variants (map_u64_new_a / map_u64_set_a / _map_u64_grow_a internal). Migration now at ~100% stdlib coverage (45 _a variants + 10 typed-error enums across 11 modules). Unblocks sandhi v1.1.0 dup-elimination. Surfaced str_split pre-existing bug (sep treated as ptr) → filed as new issue for future slot. cc5 +0 B; 33-assertion tcyr.
- **v5.8.44** ✅ api-surface refresh + auto-build wiring + null-byte fix. 3-part deliverable: check.sh now build-on-demands cyrius_api_surface (was silently skipping since v5.7.50); off-by-one 66→65 length literal in programs/api_surface.cyr (BREAKING-report header was including cstring's trailing \0 in syscall length, triggering shell command-sub null-byte warnings); snapshot regen 2563 → 2750 (+187) reflecting v5.7.x→v5.8.x stdlib growth. Gate now real PASS not silent skip; 0 null-byte warnings; cc5 unchanged.
- **v5.8.45** ✅ `kernel` demoted from reserved token to plain ident. Surfaced from vidya audio_dsp 11-lang port. Premise-check rejected issue file's "lexer-context-sensitive" framing — actual mechanic was DCE-as-error-shield (non-underscored uncalled fns skip parse). Pin-bisection-sweep `weights/bias/tensor/layer` all parse cleanly — only `kernel` was reserved. Fix per preferred path: lex.cyr keyword check removed; new `_TOK_IS_KERNEL(S)` helper detects AGNOS top-level `kernel;` via byte-compare. 12 dispatch sites across 6 main.* files. AGNOS bootstrap re-verified byte-identical. cc5 +448 B (740,976).

Phase 3 — Polish + cycle closeout (slots 39-44):
- **v5.8.39** — Preprocessor include-pattern in string literals (vidya audit)
- **v5.8.40** — `cyrlint` multi-line assert false-positive (mabda C5)
- **v5.8.41** — Vidya cyrius-language audit (annotation pass)
- **v5.8.42** — Paired UX polish: `cyrius fmt --check` exit-code (mabda A2)
  + `var X;` bare-decl error message (mabda C1)
- **v5.8.43** — v5.8.x closeout backstop

**Held items** (surfacing-ask only; not pinned, no slot consumed):
- `cyim` regex pattern (mabda C6) — pin when cyim consumer hits it
- `ESTORESTACKPARM` cx >6 args (audit §4) — pin when cx consumer surfaces 7+ args
- `float.cyr:41` peephole pattern — pin when measured to matter

**Deferred to v5.9.x or later**:
- Class B FFI/wgpu fncall6 ABI (mabda B1/B2)

Slot policy: single-issue patches (v5.4.x / v5.5.x discipline);
**soft backstop ~.44** with **14-slot headroom** for surface-during-
cycle items. Below v5.7.x's 51-patch record.

**v5.7.x slot map (firm as of 2026-04-30, hard upper bound
v5.7.48 — backstop bumped +1 to absorb the v5.7.43 = lib/test.cyr
v1 + v5.7.47 = refactor pass split decided 2026-04-30 after
v5.7.42 ship):**

Shipped:
- **v5.7.13** ✅ string-literal escapes (cyim-unblocking)
- **v5.7.14** ✅ `cyrius deps` transitive resolution (BFS walker)
- **v5.7.15** ✅ `cyrius init --lib`/`--bin` library scaffold
- **v5.7.16** ✅ `cyrius init`/`cyrius port` first-party-doc tree
- **v5.7.17** ✅ struct cap 64→256 + dump-on-overflow (kybernet)
- **v5.7.18** ✅ regex engine (Thompson NFA + Pike matcher)
- **v5.7.19** ✅ kernel-mode emit-order fix (agnos boot-shim)
- **v5.7.20** ✅ `lib/json.cyr` depth — tagged-value tree
- **v5.7.21** ✅ `cyrius fuzz` manifest-deps auto-prepend parity
- **v5.7.22** ✅ hygiene pass — cyrfmt comment-brace + install-shim re-link + cyriusly rm-rf
- **v5.7.23** ✅ cx codegen literal-arg propagation (TOKVAL offset typo)
- **v5.7.24** ✅ TS `asserts` predicate signatures (KW_ASSERTS + prefix consumer + this-type)
- **v5.7.25** ✅ TS mapped types + `as`-clause + `+/-readonly` / `+/-?` modifiers (TYPE_MAPPED AST kind + TYPE_OBJECT fork)
- **v5.7.26** ✅ TS 5.0 stage-3 decorators (TS_AST_DECORATOR + DECORATOR_LIST helper + 4 wire-in sites — closes the v5.7.24-v5.7.26 advanced-TS trio)
- **v5.7.27** ✅ codebuf cap 1 MB → 3 MB + 19-region heap reshuffle (261 offset refs shifted across 21 files; cx backend untouched — turned out to be wrong, see v5.7.28)
- **v5.7.28** ✅ cx backend TOKTYP/TOKVAL offset re-sync + structural parity gate (closes the v5.7.27 ship regression where cc5_cx silently broke)
- **v5.7.29** ✅ cx gate `set -e` repair + check.sh hygiene (closes the v5.7.27 fallout chain — check.sh now runs through to 48/48 PASS)
- **v5.7.30** ✅ aarch64 f64 basic-op implementation (FADD/FSUB/FMUL/FDIV/FSQRT/FNEG/FRINT*/FCVTZS/SCVTF — closes silent miscompile that probably dated to v5.4.x)
- **v5.7.31** ✅ aarch64 f64_exp / f64_ln polyfills (closes phylax-block — chi-squared + entropy paths now correct on aarch64)
- **v5.7.32** ✅ cyrlint global-init-order forward-ref warning (closes mabda surfacing — the silent miscompile class)
- **v5.7.33** ✅ cyrius api-surface tooling (snapshot-based public API diff; cyrius-native pure-cyrius impl; 2552-entry initial snapshot)
- **v5.7.34** ✅ aarch64 codebuf cap raise 524288→3145728 (closes the v5.7.27 ship omission — phylax-surfaced; trivial constant bump in `src/backend/aarch64/emit.cyr` `EB()`; bundled dup-fn investigation moved to agnosys side where phylax-agent has the repro context)
- **v5.7.35** ✅ stdlib syscall surface gaps (getdents64 + getrandom + landlock × 2 arches; agnosys drm/luks/security-surfaced; new lib/random.cyr + lib/security.cyr; +11 api-surface entries)
- **v5.7.36** ✅ fresh-install hardening + distlib cap raise (5-item bundle: check.sh:329 syntax-noise fix + check.sh PATH fallback for fmt/lint with loud-FAIL on missing binaries + cyrius distlib per-module cap 64KB→256KB mabda-surfaced + cyrlint string-literal awareness pulled forward from the v5.7.37 trio + new `cyriusly setup` verb for fresh-checkout install. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 55/55 PASS.)
- **v5.7.37** ✅ TS test-org rework — group-level consolidation (24 ts_*.tcyr → 4 topic-grouped runners; frontend included once per group instead of per file; assertion-count parity 1117=1117; TS suite compile time 4774ms → 926ms = 5.15× speedup; user-pushback rejected the initial megafile proposal in favour of group-level isolation; option E test-harness pinned long-term in §v5.x — Toolchain Quality. Zero compiler change.)
- **v5.7.38** ✅ `.scyr` (soak) + `.smcyr` (smoke) file types (cyrius smoke + cyrius soak walkers mirror the .tcyr/.bcyr/.fcyr discovery shape; tests/regression-capacity.sh Python3 dependency removed via shell-loop migration; example harnesses tests/smcyr/compile_minimal.smcyr + tests/scyr/alloc_pressure.scyr; _skip_deps save/restore guards cmd_soak's built-in self-host loop from auto-prepend size blowout; LSP polish split from this slot to v5.7.39. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 56/56 PASS.)
- **v5.7.39** ✅ LSP cross-file go-to-def + documentSymbol (programs/cyrius-lsp.cyr extended from diagnostics-only to navigation-capable; ~430 LOC of indexer + 2 new method handlers; cyrius-lsp 22 KB → 65,456 B; promoted to [release].bins so fresh installs ship it; semanticTokens deferred to long-term pin. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 57/57 PASS.)
- **v5.7.40** ✅ `lib/json.cyr` pretty-printer (`json_v_build_pretty(v, indent)` + `_jb_walk_pretty` + `_jb_emit_indent`; indent<=0 falls back to compact `json_v_build`; empty `{}`/`[]` short-circuit to bracket-pair with no internal whitespace per `JSON.stringify(v, null, n)` convention; `": "` key separator; tcyr 18 assertions in 10 groups + regression-json-pretty.sh gate 4au with negative-case verification. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 58/58 PASS.)
- **v5.7.41** ✅ `lib/json.cyr` streaming parser (11 event constants `JS_EV_OBJECT_START`..`JS_EV_ERROR` + 96B handler struct + `json_stream_handler_new` / `json_stream_on` / `json_stream_parse` / `json_stream_parse_str` public API; driver reuses tree parser's lex state and `_jp_*` helpers unchanged so streaming surface stays at ~210 LOC; callbacks fire via `fncall1`/`fncall2`/`fncall3` from `lib/fnptr.cyr`; tcyr 65 assertions in 9 groups + regression-json-stream.sh gate 4av exact-byte trace verification. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 59/59 PASS.)
- **v5.7.42** ✅ `lib/json.cyr` JSON Pointer (RFC 6901) (`json_v_pointer(v, ptr)` + `_cstr` variant + `_jp_obj_lookup` length-explicit key match + `_jp_parse_idx` strict §4 index parser + `_jp_token_unescape` single-pass `~1`→`/` / `~0`→`~`. Plus hygiene fix: `lib/json.cyr` now `include`s `lib/fnptr.cyr` to close the v5.7.41 incomplete-dep regression; tcyr 36 assertions in 7 groups + regression-json-pointer.sh gate 4aw 8-case exact-byte fixture; all four JSON tcyrs run clean post-fix (190 total assertions across the JSON surface). Zero compiler change; cc5 unchanged at 720,640 B; check.sh 60/60 PASS. **Closes the v5.7.20-pinned JSON depth triple.**)
- **v5.7.43** ✅ `lib/test.cyr` v1 — table-driven testing (new stdlib module; `test_each(cases_vec, fp)` via `fncall1` dispatch; transitively `include`s `lib/assert.cyr` + `lib/fnptr.cyr` so consumers write one include and get the unit-test stack — same one-include pattern as v5.7.42's `lib/json.cyr`→`lib/fnptr.cyr` fix; demo migration of json_pointer.tcyr §5 corpus 8 homogeneous assertions → single test_each call, behavior preserved 36→36 PASS; tcyr 12 assertions + regression-test-lib.sh gate 4ax end-to-end trace; first slot of the 2026-04-30 testing-framework split decision; option-E test-harness pin retired unclaimed; backstop bumped v5.7.47→v5.7.48 to absorb v5.7.43 + v5.7.47 split. Zero compiler change; cc5 unchanged at 720,640 B; check.sh 61/61 PASS.)
- **v5.7.44** ✅ TS variadic tuple types — AST representation (new `TS_AST_TYPE_REST = 316` AST kind wraps tuple elements preceded by `...`; `TS_PARSE_TYPE_TUPLE` `is_rest` flag tracks `...` and emits REST wrapper after element type + optional wrapping; honest premise check at slot entry caught stale pin claim — all 7 variadic forms already parsed rc=0; real gap was AST loss of spread distinction; first slot of the v5.7.44-46 advanced-TS suite, `ts_parse_p55` group adds 18 assertions in 8 sub-groups; cc5 720,640 → 720,864 B (+224 B); 4 TS group runners clean (1143 total TS assertions); regression-ts-variadic-tuples.sh gate 4ay 7 real-world-shape groups; check.sh 62/62 PASS.)
- **v5.7.45** ✅ TS 5.0 const type parameters `<const T>` — parse acceptance (~5 LOC `TS_TOK_KW_CONST` consume in `TS_PARSE_TYPE_PARAMS` before IDENT expect; per "parse loosely, type strictly" — no AST emission since existing parser doesn't push `TS_AST_DECL_TYPE_PARAM` for any param yet; premise-check at slot entry surfaced 4 of 5 remaining pin items already parse rc=0 — only `<const T>` had real gap with `code=3 tok=102`; honest scope-shrink medium→small called out to user; cc5 720,864 → 720,928 B (+64 B); `ts_parse_p56` group 13 new assertions in 12 sub-groups (function/class/iface/alias/method/arrow + extends + default + mixed + multiple + complex combo + plain regression); 4 TS group runners clean (1156 total TS assertions); regression-ts-const-type-params.sh gate 4az 6 real-world groups; check.sh 63/63 PASS.)
- **v5.7.46** ✅ v5.7.x advanced-TS pin audit — 4 stale-pin items closed (zero compiler change; cc5 unchanged at 720,928 B; reframed to audit-pass after v5.7.45 bisection found 4/5 remaining pin items already parse rc=0; tcyr `ts_parse_p57` group adds 25 new assertions in 7 sub-groups covering `as const` 4-shape, `satisfies` postfix 7-shape incl. TS 5.0 `as const satisfies` idiom, `never`/`unknown` 9-shape, conditional types 14-shape across basic/nested/infer/distributive incl. `Unwrap`/`ElementOf`/`ArgsOf`/`ReturnT`/`Head`/`Tail`/`Filter` standard utils; single combined regression-ts-advanced-pin-audit.sh gate 4ba with 4 sub-sections embedding zod/react/redux/TS-5.0 patterns; 4 TS group runners clean (1181 total TS assertions); SY corpus unchanged 2053+435; check.sh 64/64 PASS. **v5.7.x advanced-TS pin RETIRED — all 8 items ✅**.)
- **v5.7.47** ✅ refactor pass — testing + codebase (zero compiler change; cc5 unchanged at 720,928 B; 2 consolidations: (1) `ts_parse_p56` 13 parallel-shape parse-rc cases → `test_each` over (source, label) pairs; tcyr now includes `lib/test.cyr` for transitive assert + fnptr access; (2) `lib/json.cyr` `_jb_walk` + `_jb_walk_pretty` merged into unified `_jb_walk(sb, v, indent, level)` walker with `indent` param driving compact (=0) / pretty (>0) mode; behavior preserved end-to-end across all 4 JSON tcyrs (190 assertions) + 3 regression gates exact-byte cmp + 4 TS group runners (1181 assertions); skipped: `json_stream` scalars + `ts_parse_p55`/`p57` (heterogeneous shapes per v5.7.43 discipline); LOC delta -106 lines net while preserving 100% assertion coverage; check.sh 64/64 PASS.)
- **v5.7.48** ✅ TRUE CLOSEOUT BACKSTOP — v5.7.x cycle complete (longest minor in cyrius history; 49 patches across 35 days, v5.7.0 ship 2026-03-26 → v5.7.48 ship 2026-04-30). CLAUDE.md 11-step closeout-pass protocol run end-to-end: §1-3 mechanical (self-host two-step + bootstrap closure + check.sh 64/64 all PASS); §4-8 judgment passes (heap map 80 regions/0 overlaps, dead-code floor stable at 36, refactor pass already done at v5.7.47, code review clean, cleanup sweep clean — flagged build/cc3 tracking-vs-CLAUDE.md inconsistency for separate user call); §9-10 compliance (security re-scan clean — full audit due but v5.8.x phase; downstream check pinned for v5.7.49); §11 docs sync — vidya `language.cyml` overview + `ecosystem.cyml` refreshed to v5.7.48, new `field_notes/compiler.cyml` entry for the v5.7.46 `fn`-as-param-name reserved-keyword gotcha. cc5 unchanged at 720,928 B. **v5.7.x cycle stats**: compiler 531 KB → 720,928 B (+~190 KB across 49 patches); check.sh 26 → 64 gates; testing surface ~3400 total assertions (1181 TS + 190 JSON + ~2000 misc); stdlib 60 → 68 modules; cyrius-ts hit 100% SY corpus (2053+435); 8/8 advanced-TS pin RETIRED.)

Queue (firm assignments as of 2026-04-30 at v5.7.48 ship —
v5.7.x **CYCLE COMPLETE** at 49 patches; longest minor in
cyrius history. v5.7.44 ✅ variadic tuple AST; v5.7.45 ✅ const
type params; v5.7.46 ✅ advanced-TS pin audit (8/8 RETIRED);
v5.7.47 ✅ refactor pass; v5.7.48 ✅ TRUE CLOSEOUT BACKSTOP —
11-step protocol clean. **User-authorized headroom v5.7.49-50
partially used** for the deps refresh):

- **v5.7.49** — **deps refresh** (per user direction at v5.7.48
  ship: "no code updates but possible bringing in updated dists/
  deps"). Bump `cyrius/cyrius.cyml` `[deps.*]` tags; re-resolve
  via `cyrius deps`; re-bundle stdlib distfiles via `cyrius
  distlib` if any dep cut a new release; downstream check (§10)
  — confirm ecosystem `cyrius.cyml` `cyrius` fields point to
  v5.7.48+. Hard cap: cc5 stays byte-identical at 720,928 B.

- **v5.7.50** — **headroom (unclaimed)** — only used if the
  v5.7.49 deps refresh surfaces a follow-up bug or a downstream
  consumer files a parse failure. Otherwise unused; v5.7.49
  becomes the final v5.7.x patch and v5.8.0 cuts next.

- **v5.8.0** — bare-metal AGNOS kernel target + Vani audio
  distlib fold-in (per `roadmap.md §v5.8.x`).

**Side-task throughout v5.7.39-v5.7.48**: warning-sweep
continuing — goal still "zero `warning:` lines from cc5
self-build". Item #5 (check.sh:329 syntax noise) closed at
v5.7.36; remaining items are the 3 syscall-arity warnings in
lex.cyr + the 36 unreachable-fn floor. Cleared opportunistically
each closeout, no dedicated slot.

**Floating items** that may displace the v5.7.39-v5.7.48 plan
if surfaced before backstop:
- **Duplicate-fn warning investigation** — parked at v5.7.34
  ship; phylax-agent has the agnosys-side repro context. If
  reproduced and a fix is required, claims a slot and
  cascades the downstream items by +1 each (TS suite would
  pinch first since it's the tail).
- **Wildcard correctness items** (consumer-surfaced) per
  `feedback_correctness_over_features.md` — preempt feature
  parity. If one surfaces, the v5.7.38-v5.7.45 plan slips by
  one slot; v5.7.47 backstop would re-bound at that point.

Moved out of v5.7.x:
- **RISC-V rv64** → v5.8.x (paired with bare-metal AGNOS kernel).

**Side-task across v5.7.13–v5.7.26 closeouts**: warning sweep
(3 syscall-arity + 36 unreachable-fn floor + check.sh shell-syntax
warning + cbt/programs/bootstrap shellcheck pass). Cleared
opportunistically each closeout, no dedicated patch slot. Goal:
zero `warning:` lines from cc5 self-build by v5.7.28 (RISC-V
opens after the cap-raise/test-org slot at v5.7.27).

**v5.7.0 (sandhi fold) — cyrius side ✅ shipped.** Cyrius-side
acceptance gates 1, 2, 3, 5, 6 closed (CHANGELOG enumerates the
deleted/added symbol delta + downstream audit). Open work
(separate, user-organized):

- ⏳ Downstream consumer sweep — gate 4 of v5.7.0. Only **vidya**
  actually `include`s `lib/http_server.cyr` (in `src/main.cyr`).
  yantra and sit have orphan pre-fold copies of
  `lib/http_server.cyr` (regular files, not `cyrius deps`
  symlinks — likely manual copies from early sandhi M0 era) that
  need deletion for cleanliness. hoosh / ifran / daimon / mela /
  ark have no v5.7.0 work.
- ⏳ Vyakarana grammar refresh for sandhi syntax (469 fns now in
  stdlib).
- ⏳ Vidya per-minor refresh (language.toml / dependencies.toml /
  ecosystem.toml updates for the v5.7.0 stdlib reshape).

Sandhi repo enters maintenance mode per ADR 0002.

**Long-term considerations (no version pin)**: copy propagation +
cross-BB extended dead-store elimination — both recon-evaluated at
v5.6.18/v5.6.19-attempt, both bail (zero direct savings on stack-
machine IR; cross-BB versions need regalloc liveness data first).
Path A parser-to-emit named-op refactor pinned long-term post-
v5.7.12; trigger is RISC-V (4th backend) or 2+ new direct-emit
sites slipping past the gate. See `roadmap.md §Long-term
considerations` for full recon data + revisit criteria.

## Recent shipped (one-liner per release)

- **v5.7.6** — **CYRIUS-TS JSX INNER-EXPR TOKENIZATION (P4.3d)**.
  Closes v5.7.5's empty `JSX_EXPR_CONTAINER` deferral. Mode-stack-
  driven lex (modes 4=TAG, 5=TEXT, 8=EXPR on existing template stack)
  dispatched from main TS_LEX loop; `TS_LEX_JSX_TAG`/`TS_LEX_JSX_TEXT`
  helpers; parser consumes real exprs inside `JSX_EXPR_CONTAINER` /
  `JSX_ATTRIBUTE` / `JSX_SPREAD_ATTR`. v5.7.3 generic-arrow disambig
  REMOVED (false-positived on `<span>(optional)</span>`); pre-flight
  `BYTE_SKIP` handles both cases. `TS_LOOKAHEAD_IS_ARROW` COLON-branch
  extended with JSX scope terminators (was root cause of v5.7.5 P4.3d-2
  rollback). `.tsx` 429 → 430/435 (98.85%); threshold raised 429 → 430.
  cc5 697,840 → 704,976 B. Inner-expr tokenization shipped — empty
  JSX_EXPR_CONTAINER no longer needed.
- **v5.7.5** — **CYRIUS-TS REAL JSX AST**. v5.7.3's `TOK_INT` JSX
  placeholder replaced with 13 structured JSX token kinds (block
  300-312) + 9 JSX AST kinds (block 700-708) built by
  `TS_PARSE_JSX_ELEMENT` from PRIMARY. `TS_LEX_JSX_SKIP` +
  `TS_LEX_JSX_SKIP_INNER` deleted (256 LOC). New `BYTE_SKIP`
  bails on stray `}` to catch generic types
  (`Foo<HTMLParagraphElement>`) mis-firing as JSX. JSX tag
  whitespace skip extended to handle `//` + `/* */` comments
  between attrs (eslint-disable pragmas). `.tsx` 428 → 429/435
  (98.6%); `.ts` held at 2033/2053 (99.03%); threshold raised
  425 → 429. New tcyrs: ts_lex_p43 (49 assertions, 12 groups) +
  ts_parse_p43 (11 groups). cc5 687,088 → 697,840 B (+10,752 B).
  3-step fixpoint clean. Inner-expr tokenization deferred to
  v5.7.6 — empty `JSX_EXPR_CONTAINER` in this iteration; the
  mode-stack-driven prototype reverted at end of v5.7.5 work for
  clean cut. 6 sticky `.tsx` failures triaged as non-JSX TS
  feature gaps.
- **v5.7.4** — **CYRIUS-TS CLEANUP PASS**. `.ts` 99.03%, async
  modifier tracked as bit 48 of SPAN on DECL_FUNCTION/EXPR_ARROW/
  DECL_METHOD. P4.1 `typeof import()` types + template-interp
  brace fix + broader PRIMARY ident-equivalent list; P4.5
  `async <T>(x) =>` generic arrow. `tests/tcyr/ts_parse_p44.tcyr`
  added. Thresholds 2000→2030 / 420→425. cc5 +3,280 B.
- **v5.7.1** — **FIXUP-TABLE CAP BUMP** 32,768 → 262,144 (8×).
  sit-blocking ecosystem unblock per [sit's proposal](https://github.com/MacCracken/sit/blob/main/docs/development/proposals/cyrius-fixup-table-cap-bump.md);
  unblocks all 8 named sandhi consumers (vidya/yantra/hoosh/ifran/
  daimon/mela/ark/sit) from `[deps].stdlib "sandhi"` overflow.
  Wedged into v5.7.1 via git rewind to v5.7.0 + fixup-cap commit +
  cherry-pick of cyrius-ts P1.1+P1.2 work (preserved on
  `wip/cyrius-ts-p1`). 16 cap-check sites updated across 5 backend
  files (proposal originally listed 5 sites; x86 backend was missing
  + aarch64 had a variant string format we caught). Brk extended
  +3.5 MB across 4 main entry files. main.cyr capacity-meter
  output + heap-layout comments updated; pre-existing off-by-2x
  percentage math bug at line 1073 (stale `/ 16384` divisor)
  fixed in passing. cx backend's cap bumped uniformly but its
  smaller heap layout left untouched (cx never approaches 32K
  fixups). cc5 self-host fixpoint clean at 531,880 B (8 B
  smaller than v5.7.0 from the constant-change byte-shift; cc5
  itself unchanged semantically). check.sh 26/26 PASS. Resumes
  cyrius-ts work as v5.7.2.
- **v5.7.0** — **THE SANDHI FOLD**. Clean-break consolidation per
  sandhi ADR 0002: `lib/sandhi.cyr` adds (vendored byte-identical
  from `sandhi/dist/sandhi.cyr` at v1.0.0 tag — 376,037 B / 9,649
  lines / 469 fns covering M0–M5: HTTP client + server + HTTP/2 +
  streaming + JSON-RPC + service discovery + TLS policy);
  `lib/http_server.cyr` deletes (no alias, no passthrough); 17
  deprecated `http_*` fns confirmed 1:1-mapped to `sandhi_server_*`
  pre-fold. `tests/tcyr/http_server.tcyr` deletes with the lib
  (suite 68 → 67 files). `scripts/lib/audit-walk.sh` extended to
  skip `cyrius distlib`-generated files (marker-based, complements
  symlink-based skip for `cyrius deps` deps; dep skip count 6 → 7).
  Acceptance gates 1, 2, 5, 6 ✅; gates 3 + 4 (downstream sweep
  across yantra/hoosh/ifran/daimon/mela/vidya/sit-remote/ark-remote)
  are separate user-organized work. Sandhi repo enters maintenance
  mode. Zero compiler change → cc5 byte-identical at 531,888 B
  (cc5 doesn't include either lib); cc5 --version → 5.7.0;
  check.sh 26/26 PASS.
- **v5.6.45** — VS Code TextMate grammar refresh
  (`editors/vscode/syntaxes/cyrius.tmLanguage.json`). Extended
  to cover the v5.6.x syntax wave: 4 new keywords (`secret`,
  `match`, `in`, `shared`) + 10 new directives (`#deprecated`,
  `#pe_import`, `#must_use`, `#regalloc`, `#endplat`, `#include`,
  `#ifplat`, `#elif`, `#else`, `#ifndef`). All grep-confirmed
  as live cyrius syntax. Directive pattern ordered
  longest-prefix-first to avoid Oniguruma alternation
  false-matches; trailing `\b`. Pairs with v5.6.44: the
  `#deprecated("use lib/sandhi.cyr instead")` attributes on
  `lib/http_server.cyr` now render as preprocessor directives in
  VS Code (and through Claude Code's IDE integration via
  `mcp__ide__getDiagnostics`), making the v5.7.0 cutover
  signal unmissable. Out-of-scope (deliberately not bundled):
  CLI fence-tag convention (no Claude Code plugin/config surface
  for custom-language grammar registration — researched via
  claude-code-guide; working through OWL routing instead via
  `~/.claude/settings.json` permission rule); vyakarana grammar
  resync (separate repo, separate audit); CYIM (cyrius-aware
  editor binary, pinned for after owl + sit stable). cc5
  byte-identical at 531,888 B (grammar-only edit). check.sh
  26/26 PASS.
- **v5.6.44** — `lib/http_server.cyr` deprecation-notice cycle
  for v5.7.0 prep. All 17 public fns marked
  `#deprecated("use lib/sandhi.cyr instead -- removed at v5.7.0")`
  via the v5.6.4 fn-attribute mechanism + file-header deprecation
  block. Per-call-site warning fires at every consumer call site
  (parse_fn.cyr:352) — stronger notice than one-shot include-time
  print. Satisfies roadmap line 718 prereq for the v5.7.0 sandhi
  fold (which deletes the file). Design choice: reuse existing
  `#deprecated` infra rather than build a new `#warning`
  directive — zero compiler change → zero self-host risk; matches
  "compiler grows to fit language, never the other way around."
  cc5 byte-identical at 531,888 B (cc5 doesn't include the lib).
  http_server.tcyr 31/31 (31 deprecation warnings fire at compile;
  test exits 0). check.sh 26/26 PASS. Notice cycle now runs in
  parallel with sandhi's M5 → v1.0.0 work; v5.7.0 fold lands
  when sandhi tags v1.0.0 + downstream branches ready.
- **v5.6.43** — closeout finish + sigil 2.9.0 → 2.9.3 + sankoch
  2.0.3 → 2.1.0 + output_buf 1MB → 2MB heap reshuffle. CLAUDE.md "Closeout Pass" steps 9-11
  ran clean: security re-scan (no new sys_system / unchecked
  READFILE / new execve paths; full audit due v5.7.x — last v5.0.1),
  downstream pin matrix snapshotted across 16 ecosystem repos
  (older-minor pins enumerated as v5.7.0 sandhi-fold worklist),
  vidya refreshed (language.toml / dependencies.toml /
  ecosystem.toml — version refs, patra 1.6.0 → 1.8.3 details,
  sigil 2.9.0 → 2.9.3 details, ALPN hook surface mention).
  Sigil 2.9.3 = AES-NI dispatch + SHA-NI compress (drop-in
  software-SHA-256 replacement, ~80x throughput win on x86_64
  SHA-NI hosts; surfaced by sit v0.6.4 perf review). Bump
  required adding `lib/fdlopen.cyr` / `lib/ct.cyr` /
  `lib/sha1.cyr` / `lib/keccak.cyr` includes to the 3
  "include-everything" test fixtures (transitive deps from
  sigil's new symbols). Resulting compiled-fixture size crossed
  the 1MB output_buf cap → reshuffle: output_buf 1MB → 2MB,
  16 regions shifted +1MB (tok_types/values/lines, struct
  ftypes/fnames, fn_names band, ir_nodes/blocks/state/edges/cp,
  fixup_tbl), brk 22.5MB → 23.5MB. Cap-check sites at 4
  EMITELF/macho overflow points updated 1048576 → 2097152.
  Heap-map fix-through caught stale `0xA0000 fixup_tbl` docs in
  4 main_*.cyr files (region was repurposed at v5.6.27 to
  jump_src_tbl for codebuf compaction; docs were 16 patches
  stale). cc5 byte-identical at 531,888 B (heap shifts are
  immediates, no byte-count change). check.sh **26/26 PASS**
  with the previously-failing 3 fixtures (large_input,
  large_source, preprocessor_past_cap) now compiling to
  ~1.08MB ELF and running cleanly. **v5.6.x closes here**;
  v5.7.0 (sandhi fold + lib/ cleanup) is next. Pinned for
  v5.7.x: `cyrius deps` transitive resolution, full security
  audit, downstream pin sweep before fold opens.
- **v5.6.42** — compiler-side closeout (CLAUDE.md "Closeout Pass"
  steps 1-8) + bundled PP_DEFINE/PP_DEFINED/PP_GETVAL/PP_EVAL_IF/
  PP_HASH `src_base` hardening (latent v5.6.30 same-class bug
  closed for the rest of the helper family). Mechanical: cc5
  3-step fixpoint clean at 531,888 B (+112 B); bootstrap closure
  clean; check.sh **26/26 PASS** (new gates: `preprocessor_past_cap.tcyr`
  + `regression-macho-cross-build.sh`). Judgment: heap-map clean,
  24-fn dead floor preserved (each is a real scaffold per its own
  inline docstring — multi-target Mach-O, ESHRIMM/ELVR* unfinished
  optimizations, IR scaffolds for deferred O3 work), refactor pass
  found cross-backend duplication intentional (alternates per build),
  code-review surfaced the PP_DEFINE bug fixed in this slot, cleanup
  sweep updated stale brk heap-map comments to 0x168B000 / 22.5 MB
  across main_aarch64*.cyr + main_win.cyr. v5.6.43 = closeout finish
  (compliance + downstream dep-pointer check + sigil 2.9.3 fold-in
  + final doc sync). LAST patch of v5.6.x.
- **v5.6.41** — SysV 16-byte stack alignment fix for odd-stack-arg
  callers (sandhi-blocking, M2 HTTPS-live unblock). Sandhi-filed
  2026-04-25: any cyrius fn with 7/9/11 formal params calling
  `tls_connect` (or any libssl/libc fn with SSE in its prologue)
  SIGSEGV'd at the resolved external symbol's first instruction.
  Root cause: `ECALLPOPS`'s SysV path emitted `add rsp, 48`
  unconditionally; for odd `nextra = N - 6` this left rsp 8-aligned
  at the CALL site, violating SysV's `rsp+8 16-aligned at entry`
  rule. Win64 path already aligned (line 1067). Fix: shift step-2
  writes down 8 bytes (write to `[rsp+(5+i)*8]` not `[rsp+(6+i)*8]`)
  and `add rsp, 40` not `add rsp, 48` for odd nextra; even nextra
  unchanged. `ECALLCLEAN` adds 8 extra back to release the alignment
  padding. New regression gate `tests/tcyr/sysv_odd_stack_args.tcyr`
  (5 assertions, callers 7/8/9/10/11 → SSE-using leaf). cc5
  531,584 → 531,776 B (+192 B). check.sh **25/25 PASS**. 3-step
  fixpoint clean. Sandhi's `_min_repro_7arg_tls.cyr` now returns
  valid TLS contexts for both 6-arg and 7-arg paths. Closeout
  cascaded: v5.6.42 = compiler-side closeout, v5.6.43 = finish.
- **v5.6.40** — `lib/tls.cyr` ALPN/mTLS/custom-verify hook
  surface (sandhi-pinned) **+ bundled patra 1.6.0 → 1.8.3
  dep bump + 1 MB → 2 MB preprocessor expanded-source cap
  raise (12-region heap reshuffle, brk 21.5 MB → 22.5 MB)**.
  ALPN: sandhi 0.8.1 had wire-format encoding ready since
  2026-04-24 but couldn't fire `SSL_CTX_set_alpn_protos`
  because stdlib `tls_connect` built its `SSL_CTX` privately
  with no customisation point. New `tls_dlsym(name)` +
  `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)`;
  `tls_connect` collapses to a 1-line wrapper. End-to-end
  verified at Cloudflare 1.1.1.1:443 → server picks h2.
  Patra: 1.7.0 INSERT OR IGNORE + 1.7.1 STR-keyed B+ tree
  indexes + 1.8.2 page-slab allocator + word-at-a-time
  `_memeq256` + prepared statements (`patra_prepare` /
  `patra_exec_prepared` / `patra_query_prepared` /
  `patra_finalize`) + 1.8.3 fmt/lint/doc cleanup. Cap raise:
  `large_input.tcyr` + `large_source.tcyr` crossed the 1 MB
  cap by ~280 B once patra 1.8.3 (~14 KB larger than 1.6.0)
  joined the include set; both tests' actual goal is
  >256 KB, so they were already 768 KB above their stated
  bar. Right answer: grow the cap, not trim the language.
  Reshuffle hit `preprocess_out → 2 MB` and shifted every
  region forward 1 MB across `src/main*.cyr`, every
  `parse_*.cyr`, `lex.cyr`, `lex_pp.cyr`, `ir.cyr`, every
  `backend/*/{emit,fixup,jump}.cyr`. Subtle bugs surfaced:
  (1) 9 `var O = S + 0x64A000` EMITELF sites were OLD
  output_buf base, not new codebuf — moved to 0x74A000;
  (2) `var pfx = S + 0x64A000 + 131072` scratch in
  `backend/x86/fixup.cyr` was OLD output_buf tail — moved
  to 0x74A000; (3) `0x150B000` ambiguous between OLD
  fixup_tbl (16-byte stride) and NEW ir_cp (4-byte stride)
  — disambiguated via stride; (4) `0x13CA000` ambiguous
  between OLD ir_state and NEW ir_blocks — ir_state shifted
  to 0x14CA000 with offset family `+8/+10/+18/+20`;
  (5) `0xECA000` ambiguous between OLD ir_nodes and NEW
  struct_fnames — ir.cyr shifted to 0xFCA000.
  3-step fixpoint clean (`b == c == d` byte-identical at
  531,584 B). check.sh **25/25 PASS** (was 24/25 with
  large_input/large_source failing the 1 MB cap; now well
  under 2 MB). Closeout cascaded v5.6.40 → v5.6.41.
- **v5.6.39** — `cc5 --version` drift repair + hardcoded-
  literal removal. Caught via Starship prompt observation:
  cyrius repo bumped to v5.6.38, but `cc5 --version` still
  said `5.6.29-1`. Root cause: `version-bump.sh`'s regex
  `[0-9]+\.[0-9]+\.[0-9]+\\n` didn't accept the `-N` hotfix
  suffix; once `5.6.29-1\n` baked in, the sed gate's grep
  failed silently for 9 consecutive releases (5.6.30→5.6.38).
  Fixed by **removing the hardcoded-literal class entirely**:
  new auto-generated `src/version_str.cyr` holds the version
  vars; `main.cyr` and `main_win.cyr` `include` it and
  reference the vars in the syscall. version-bump.sh writes
  the file via heredoc — no regex hunting, no per-file
  sweeping, no `-N` suffix vulnerability. Same-version
  invocation also regenerates (documented "regenerate without
  bumping" path now works). cc5 rebuilt: 531,360 → 531,584 B
  (+224 B for include + var refs); 3-step self-host
  byte-identical; `cc5 --version` correctly reports v5.6.39.
  Closeout cascaded v5.6.39 → v5.6.40.
- **v5.6.38** — shared-object emission slot ran the
  verify-premise check first (per v5.6.33/v5.6.36 lessons).
  Result: `.so` emission has been complete and shipping since
  v5.5.x. `tests/regression-shared.sh` (in check.sh as gate
  4a) covers all four PIC surfaces (fn calls + string literal
  refs + mutable globals + DT_INIT) and continues to PASS.
  The roadmap's "SYSV_HASH is unreachable, hash chain not
  wired" framing was misleading — the SysV ELF spec + glibc
  `dl-lookup.c` show chain walks do pure strcmp, never hash
  comparison, so `nbucket=1` makes the hash function
  genuinely irrelevant. Slot deliverable: removed dead
  `SYSV_HASH` (14 LOC) + the misleading comment + added a
  pointer to `.gnu.hash` as a long-term consideration (no
  consumer needs it). cc5 −320 B (531,680 → 531,360);
  unreachable-fn count 25 → 24. 3-step self-host
  byte-identical. check.sh 25/25.
- **v5.6.37** — `SSL_connect` deadlock fixed by routing libssl
  through `fdlopen`. Sandhi M2's HTTPS probe hung forever on
  `futex(FUTEX_WAIT_PRIVATE, 2, NULL)` at TCB+0x118 after TCP
  connect succeeded — libssl's `OPENSSL_init_ssl` uses a
  pthread recursive mutex inside the TCB, and cyrius's
  `dynlib_bootstrap_tls` stub zeroed that TCB so the mutex's
  `__kind` field reads 0 (= non-recursive). Same-thread
  re-entry deadlocked (CAS 0→1, CAS 1→2, futex(WAIT, 2)).
  Fix: `lib/tls.cyr::_tls_init` now calls `fdlopen_init_full`
  which invokes `ld-linux.so` to run a shim through real
  `__libc_start_main` + `__libc_pthread_init`; subsequent
  `dlopen("libssl.so.3")` loads against a fully-initialised
  glibc TCB and all pthread primitives work correctly.
  Verified end-to-end: `https://1.1.1.1/` handshake + HTTP
  GET + response read round-trips cleanly ("HTTP/1.1 301
  Moved Permanently"). New gate
  `tests/regression-tls-live.sh` wired into check.sh (4q''),
  skips if `~/.cyrius/dlopen-helper` missing or network
  unreachable. Zero compiler change; cc5 byte-identical at
  531,680 B.
- **v5.6.36** — `tests/regression-pe-exit.sh` rewritten. Same
  exact misdiagnosis pattern as v5.6.33's Mach-O slot — the
  PE gate's `fn main() { syscall(60, 42); return 0; }` fixture
  never entered `main()` (cyrius has no auto-call); entry
  prologue branched over the dead body to `EEXIT_PE` which
  called `kernel32!ExitProcess(arg)` with whatever was in the
  arg-slot register on Win11 24H2 (= `0x40010080`, the roadmap's
  reported "regression"). PowerShell reported
  `ApplicationFailedException` because the high nibble is an
  NTSTATUS-shape informational code. **None of this was a
  Win11 24H2 issue.** Verified by patching the PE's
  `DllCharacteristics` from `0x0000` → `0x0160` and observing
  byte-identical exit behavior; both forms exit 42 with correct
  top-level syntax. Gate rewritten: top-level
  `syscall(60, 42)` (proves IAT + ExitProcess) + write+exit
  (kernel32!WriteFile reroute) + user-fn arithmetic (v5.6.10
  peephole on PE codegen). `CYRIUS_V5634_SHIPPED` guard
  dropped; `CC_PE` retargeted from `build/cc5_win` (PE binary
  that can't run on Linux) to `build/cc5_win_cross` (Linux ELF
  emitting PE; auto-builds from `cc5 < src/main_win.cyr`).
  CR-strip added for cmd.exe CRLF output. Zero compiler change;
  cc5 byte-identical at 531,680 B. check.sh 24/24 with PE gate
  ACTIVE. End-to-end on cass (Win11 24H2 build 26200,
  Microsoft Windows 10.0.26200.8246): all three tests exit 42.
- **v5.6.35** — sit symptom 2 of 2 closed via sankoch dep bump
  2.0.1 → 2.0.3. Triage on the same 100-commit fixture pinned
  the layer to sankoch's `zlib_compress` producing
  non-decompressible DEFLATE on sit-tree-shaped inputs
  (1600+ patra roundtrips clean, 1600+ sankoch synthetic
  roundtrips clean, in-process zlib_decompress fails 50/300
  in same lock window — bug upstream of patra, deterministic
  on input). sankoch 2.0.2 fixed 51/53; 2.0.3 fixed remaining
  2 (~1.5 KB and ~2 KB inputs with a distinct mid-stream
  zero-run). Cyrius v5.6.35 = `cyrius.cyml` `[deps.sankoch]`
  pin 2.0.1 → 2.0.3 + new `tests/regression-sit-status.sh`
  active gate. Zero compiler change; cc5 byte-identical at
  531,680 B. check.sh 24/24. End-to-end sit `fsck` reports
  `checked 300 objects, 0 bad`.
- **v5.6.34** — stdlib `alloc` grow-undersize SIGSEGV fixed
  (`lib/alloc.cyr` Linux brk + `lib/alloc_macos.cyr` mmap).
  Both paths grew by a fixed `0x100000` step every time
  `_heap_ptr` crossed `_heap_end` — any single
  `alloc(size > 1 MB)` near the boundary returned a pointer
  past the new end, SIGSEGV on first tail-write. Filed by sit
  2026-04-24 during S-33 triage of `sit status` SIGSEGV on
  100-commit repo (16 MiB zlib retry buffer in
  `object_db.cyr:read_object`). Verified across v5.6.25 → v5.6.33.
  Fix: Linux rounds the new end up to the next 1 MB grain;
  macOS loops 1 MB mmaps to preserve the per-step contiguity
  guard. New gate `tests/tcyr/alloc_grow.tcyr` (10 assertions
  covering 4 MB / 16 MB / 1000×64 B / 128 MB shapes). Windows
  path separable — `lib/alloc_windows.cyr` doesn't grow, fails
  cleanly. cc5 byte-identical at 531,680 B (uses raw `brk`,
  not `lib/alloc.cyr`). check.sh 23/23.
- **v5.6.33** — `tests/regression-macho-exit.sh` rewritten.
  Slot's premise was wrong: the `fn main() { syscall(60, 42); }`
  fixture never actually entered `main()` — cyrius has no
  auto-invoked `main`; top-level stmts are the entry point. The
  argv prologue's branch-over-fn-bodies landed on the `EEXIT`
  tail with `x0 = argc = 1` still resident, hence rc=1 on ecb.
  Top-level `syscall(60, 42);` exits 42 cleanly under macOS
  26.4.1 on unchanged v5.6.33 cross-compiler. Gate expanded to
  three tests: `__got[0]=_exit` + `__got[1]=_write` (bytes
  verified) + v5.6.11 peephole round-trip. `CYRIUS_V5633_SHIPPED`
  guard dropped; gate runs whenever `build/cc5_aarch64` exists
  and `ssh ecb` is reachable. No compiler code changed. cc5
  byte-identical at 531,680 B. check.sh 23/23.
- **v5.6.32** — native aarch64 self-host on Pi 4 repaired.
  `src/main_aarch64_native.cyr` was missing
  `include "src/common/ir.cyr"` that `main_aarch64.cyr` received
  when v5.6.12 O3a shipped the `IR_RAW_EMIT` instrumentation
  markers (shared `parse_*.cyr` references the opcode enum
  unconditionally). 1-line fix. Native-on-Pi fixpoint now
  byte-identical: cc5_b == cc5_c at 463,768 B.
  `regression-aarch64-native-selfhost.sh` flipped from a
  wrong-shape skip-stub (md5-against-cross-build) to the correct
  2-step native fixpoint and wired into `check.sh`. The earlier
  roadmap framing cited `_TARGET_MACHO` undef — stale symptom
  shape from a pre-v5.6.12 source tree; same root cause class
  (include missing from the native variant), same 1-line fix.
- **v5.6.29** — sandhi-surfaced `lib/tls.cyr` HTTPS infinite-loop
  fix. `_tls_init` now runs the documented libc-consumer bootstrap
  (`dynlib_bootstrap_cpu_features` + `_tls` + `_stack_end`) before
  `dynlib_open("libcrypto.so.3")` / `libssl.so.3`. Without it,
  IFUNC-resolved cipher selection in libcrypto + `%fs:N` accesses
  in libssl session setup faulted; `_tls_init` returned 0
  (looked-success) but `SSL_connect` entered a tight retry loop —
  the http-probe "GET ... GET ... GET ..." flood symptom in the
  sandhi M2 design report. fdlopen half (symptom §1-2) split to
  v5.6.29-1 hotfix-style slot; the investigation may or may not
  yield in one sitting and the suffix lets it ship-or-defer
  cleanly. tls.tcyr 22/22, check.sh 23/23, cc5 byte-identical.
- **v5.6.28** — `cyrius init` scaffold gaps (owl-surfaced, 5 fixes)
  + audit-pass cleanup. (1) Write the advertised `src/test.cyr` stub
  (was ENOENT on `cyrius test`). (2) Global `cyrius.toml` →
  `cyrius.cyml` in agent CLAUDE.md presets + src/main.cyr +
  tests/* headers. (3) Dry-run output rebuilt to mirror the real
  writer set 1:1 (was advertising CONTRIBUTING.md / SECURITY.md /
  CODE_OF_CONDUCT.md / docs-content that no writer ever produces).
  (4) `--description=<str>` flag with `<name> — TODO` placeholder
  default (was always empty). (5) "already exists" hint now points
  at `cd $NAME && cyrius init --language=none .` (was the same
  command that failed). Audit extras: bare `cyrius test` in CI
  workflow + README, dropped dead `lib/agnosys/` and `scripts/`
  empty mkdirs, consolidated tests/ mkdir into the structure block.
  No compiler change. check.sh 23/23, cc5 byte-identical.
- **v5.6.27** — Phase O6 codebuf compaction (NOP harvest with jump+fixup
  repair). Per-fn pass after picker; sweeps the 4-byte `0F 1F 40 00`
  NOP-fills via explicit tracking at every NOP-emit + disp32-emit
  site (no byte-scan — that false-positives on data bytes). New heap
  regions at 0xA0000 (jump-source) + 0xA2010 (NOP runs) + 0xA6010
  (fn-start fixup baseline). Hooks in EJCC/EJMP/EJMP0/ECALLTO + the
  picker's load/store rewrites. Compaction sorts NOPs by CP, walks
  the jump-source table to recompute disp32s, shifts fixup-table CPs
  + jump-target CPs, then compacts bytes. Gates: x86 only, kmode≤1,
  IR=0, no table overflow. **cc5 542,928 → 531,392 B (−11,536 B /
  −2.13%)**, cross-compilers see similar gains. check.sh 23/23, both
  fixpoints clean. IR=3 NOP harvest (DSE/LASE/const-fold passes)
  pinned for a future slot.
- **v5.6.26** — peephole refinement + v5.6.25 doc/CHANGELOG completion
  (the EPOPARG `n == 0` adjacency-cancel block landed cleanly, plus
  full CHANGELOG/roadmap/state.md entry for v5.6.25's 13-LOC fix).
  Phase O5 maximal-munch slot dropped from the optimization arc:
  recon found 0 fused-op candidates (cyrius's stack-machine IR keeps
  a push between sub-expression results and consumers); push-imm
  rewrite has rax-side-effect + forward-jump-target issues. Pinned
  long-term, no slot — needs an IR-level push-elision pass first.
- **v5.6.25** — aarch64 push/pop cancel completion (scope retargeted
  from "aarch64 fused ops" after bytescan found 0 `mul+add` / 0
  `lsr+and` matches). v5.6.9's push/pop cancel had a latent gap:
  `EPOPARG(S, n)` bypassed the adjacency check for every `n`, so
  1-arg call sites (`EPUSHR; EPOPARG(S, 0)`) emitted a redundant
  8-byte push+pop pair. Pre-fix cc5_native_arm carried **2,569**
  such pairs. 13-LOC fix in `src/backend/aarch64/emit.cyr::EPOPARG`.
  Native aarch64 cc5 **517,376 → 497,008 B (−20,368 B / −3.94%)** —
  larger than v5.6.11's aarch64 combine-shuttle shrinkage. x86
  cc5 unchanged at 542,928 B. check.sh 23/23. Pi exit42 OK.
- **v5.6.24** — **Default-on regalloc**, two-bug fix. (1) SysV
  ECALLPOPS for n>6 args used r12-r14 as scratch. Under v5.6.20+
  regalloc the picker pinned caller's locals to those callee-saved
  regs → silent corruption (sandhi-reported "live-across-calls"
  boxing workaround / flags-test test_str_short→test_defaults
  bisection at AUTO_CAP=118). Rewrote shuttle to use only r10
  (caller-saved) via direct `[rsp+offset]` addressing. (2) Flipped
  `_ra_auto_cap` default from -1 (disabled) to "uncapped" — every
  eligible fn gets auto-regalloc'd unless it has inline asm.
  cc5 522,624 → 542,928 B (+20,304 B for save/restore overhead;
  perf gain visible only in downstream consumers). check.sh 23/23,
  all 84 .tcyr PASS, both fixpoints clean. v5.6.25 sandhi
  pre-existing fdlopen + TLS bugs pinned for future investigation.
  Cascade -1 (v5.6.25 picker-bug consolidated into v5.6.24);
  closeout v5.6.36 → v5.6.35.
- **v5.6.23** — Misdiagnosis correction: the v5.6.22 "alignment
  regression" was actually inline-asm + regalloc stack-frame layout
  collision. Asm hardcodes `[rbp-N]` disps; regalloc's callee-save
  block shifts every local slot by `_cur_fn_regalloc * 8`. Fix:
  body-scan lookahead in `parse_fn.cyr` for token 48 (`asm`); auto-
  enable silently skips, opt-in `#regalloc` warns and skips. Default-
  on flip surfaced a SECOND picker bug — fixed at v5.6.24.
  Cascade +2: closeout v5.6.34 → v5.6.36.
- **v5.6.22** — Phase O4c (partial): picker correctness fix (loop-back
  time-share extend) + auto-enable infrastructure shipped DISABLED
  by default. `CYRIUS_REGALLOC_AUTO_CAP=N` opts in (per-fn count cap).
  Default-on auto-enable surfaced what was framed as a v5.5.21
  array-alignment regression — v5.6.23 traced it to inline-asm
  layout, not alignment. Patra 1.6.0 verified folding cleanly.
- **v5.6.21** — Codegen bug fix: bare-truthy `if (r)` after fn-call.
  Root cause: v5.6.8 `_flags_reflect_rax` not reset by EFLLOAD,
  ECALLFIX, ECALLTO, ESYSCALL. 4-line fix. Patra 1.6.0 unblocked.
  New regression gate 4r (check.sh 22 → 23). Repro
  `/tmp/cyrius_5.6_codegen_bug.cyr` now exits 99 (was -1).
- **v5.6.20** — Phase O4b: Poletto-Sarkar linear-scan picker (replaces
  greedy use-count) + time-sliced rewrite. Opt-in `#regalloc` only.
  Picker proven correct on 8-local spill-pressure test (5 assigned, 3
  spilled). cc5 self-build observable change = none (no `#regalloc`
  in cyrius source); v5.6.21 auto-enable surfaces the win. Patra dep
  bumped 1.5.5 → 1.6.0 (blob support for `sit` consumer).
- **v5.6.19** — Phase O4a: per-fn live-interval infrastructure. Foundation
  for v5.6.20 Poletto-Sarkar picker. Pre-existing `ra_counts[256]` sizing
  bug fixed (256 bytes → 256 i64 slots). `CYRIUS_REGALLOC_DUMP=1` env knob
  for inspection. No codegen change yet.
- **v5.6.18** — Phase O3c: dead-store elimination + fixed-point driver.
  Recon-driven scope split: copy-prop deferred to v5.6.19 (zero direct
  savings on stack-machine IR — cascade-only value). **15 DSE / 6,099 B
  NOP-fill at IR=3 in 3 fixpoint iterations** (cascade caught 3 more folds).
- **v5.6.17** — Phase O3b-fix: bitmap liveness + DCE (the v5.6.16-deferred
  half). Bug fixed via `CYRIUS_DCE_CAP` bisection — `IR_RAX_CLOBBER` reads
  RCX, not writes it. **678 DCE kills / 2,010 B NOP-fill** at IR=3.
- **v5.6.16** — Phase O3b part 1/2: IR const-fold (130 folds, 774 B NOP-fill
  at IR=3); DCE deferred to v5.6.17 per quality-before-ops; v5.6.22
  re-pinned to codebuf compaction (real shrinkage).
- **v5.6.15** — IR-emit-order audit fix: 5-LOC `ESETCC` reorder; SETCC→CMP
  IR adjacency 3,665 → 0; bytes unchanged at IR=0.
- **v5.6.14** — Phase O3a-fix: LASE correctness (`parse_ctrl.cyr` loop_top
  IR_NOP landing pads) + `IR_RAX_CLOBBER` for EMULH/EIDIV/ELODC.
- **v5.6.13** — `lib/sha1.cyr` extraction (quick-win, promoted from
  `_wss_sha1`).

(Older releases: see `completed-phases.md`.)

## Consumers

AGNOS kernel, agnostik (58 tests), agnosys (20 modules), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests).

All AGNOS ecosystem projects depend on the compiler and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

## Bootstrap chain

```
bootstrap/asm (29 KB committed binary — root of trust)
  → cyrc (12 KB compiler)
    → bridge.cyr (bridge compiler)
      → cc5 (modular compiler + IR, 9 modules)
        → cc5_aarch64 (cross-compiler)
        → cc5_win (cross-compiler)

No Rust. No LLVM. No Python. Just sh + Linux x86_64.
Build: sh bootstrap/bootstrap.sh
```
