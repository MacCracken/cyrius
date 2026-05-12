# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.

## Version

**5.11.32** (shipped 2026-05-12 — **`EMITELF_USER` x86_64
user-binary ELF section-header cleanup**). Mirrors the .29
(x86 kernel) / .30 (aarch64 kernel) / .31 (cyrld) section-header
arc into the in-compiler x86_64 user-binary emit path. Every
Cyrius x86_64 ET_EXEC `cc5` produces now carries a 5-entry
section header table (SHT_NULL + `.text` + `.rodata` + `.bss` +
`.shstrtab`) — `objdump -d`, `gdb`, `ltrace`, `readelf -S`, IDE
symbol indexers all see real section info on user binaries (not
just kernel + linker output). Same ELF64 5-section template as
.30 adapted to user-binary base `0x400000` and 4 KB `p_align`;
section table + shstrtab sit past `PT_LOAD` as non-loaded
metadata (overhead 352 B per emit). Three previously-zero header
fields now carry real values: `e_shoff`, `e_shnum = 5`,
`e_shstrndx = 4`. Two-step self-host byte-identical at
**818,344 B** (+8,320 from .31's 810,024 — emit code growth +
352 B section overhead in cc5 itself); check.sh 67/67; cyrius
test 149/149. Small user binary verification (`var x: i64 = 42;
return x;`) compiles + executes (`exit=42`) under the new
emitter; `objdump -d` now shows `Disassembly of section .text:`
where pre-.32 user binaries disassembled as opaque blobs.
**Companion** (next): v5.11.33 = `EMITELF` aarch64 user-binary
(`src/backend/aarch64/fixup.cyr:323`) to close the in-compiler
user-emitter arc.

**5.11.31** (shipped 2026-05-12 — **`cyrld` ELF64 linker
section-header fix**). Closes the third of three identical
`e_shoff = 0` sites identified in the 2026-05-12 GRUB-rejection
postmortem; `programs/cyrld.cyr::emit_executable` now appends a
5-entry section header table + 30-byte `.shstrtab` past the
loaded segment. Section layout uses `.data` (vs `.bss` in the
kernel emitters) because cyrld merges initialized data from
input modules. Same ELF64, 64-byte `Elf64_Shdr`, 8-byte aligned
shdr-table pattern as .30. `readelf -S` on cyrld output lists
all 5 sections cleanly; linked binary executes identically
(`rc=44` from `tests/fixtures/linker/` 4-module inc_counter
chain); output grows 352 B per linked binary regardless of input
module count. **Bug caught in patch development**: first pass
wrote `store64(sh + 0, …)` for shdr field stores forgetting
that `sh` is a file offset not a base pointer — correct form is
`store64(O + sh + 0, …)` (file-buffer base `O` must prefix every
store target). Worth noting because the same trap would catch
anyone mirroring this pattern into a future linker pass.

**5.11.30** (shipped 2026-05-12 — **aarch64 kernel ELF64
section-header fix**). Same fix as .29 for `EMITELF_KERNEL` in
`src/backend/aarch64/fixup.cyr`, adapted to ELF64 (`Elf64_Shdr`
64 bytes, 8-byte aligned shdr table, `e_shentsize=64`). MVP is
x86-only but the aarch64 kernel binary now ships with proper
section metadata so future ARM-host bringup (Pi 4, Apple Silicon
dev) won't trip the symmetric counterpart to GRUB's
`grub_elf32_get_shnum`. `.text` deliberately covers the 16-byte
SP-setup preamble (entry-point `base + 120` is the start of
`.text`). `readelf -S build/agnos-aarch64` lists 5 sections;
kernel grows 93,288 → 93,640 B (+352 / +0.38%). aarch64 QEMU
boot deferred to CI (no `qemu-system-aarch64` locally).

**5.11.29** (shipped 2026-05-12 — **Kernel ELF section-header
fix for GRUB multiboot compatibility**). Before this patch
`EMITELF_KERNEL` in `src/backend/x86/fixup.cyr` emitted ELF32
binaries with `e_shoff=0`, `e_shnum=0`, `e_shentsize=0` — valid
ELF (Linux `execve` only consumes program headers) but GRUB's
`grub_elf32_get_shnum` (kern/elfxx.c:227) rejects outright with
`invalid section header table offset in e_shoff`, so the
multiboot loader never reaches the kernel. **Symptom on hardware
(AGNOS USB boot 2026-05-12)**: `error: kern/elfxx.c:grub_elf32_get_shnum:227:
invalid section header table offset in e_shoff. error:
loader/multiboot.c:grub_cmd_module:387: you need to load the
kernel`. **Fix**: appends a 5-entry section header table after
the kernel's loaded segment (SHT_NULL + `.text` (incl multiboot1
hdr) + `.rodata` + `.bss` (NOBITS) + `.shstrtab`); ~232-byte
overhead per kernel binary. `grub-file --is-x86-multiboot
build/agnos` → exit 0 (was rejected); AGNOS kernel boots to
scheduler under `qemu-system-x86_64 -kernel` with no behavioral
regression (full init: GDT/IDT/PIC/APIC/timer, page tables,
PMM/VMM, ACPI, PCI, VFS, SYSCALL/SYSRET, syscall test, scheduler
tick test, initrd read — all pass); kernel grows 250,704 →
250,936 B (+232 / +0.09%). **Downstream**: `agnos/cyrius.cyml`
bumps 5.10.44 → 5.11.29 to consume the fix — required to
unblock USB boot of the AGNOS MVP on iron (closed beta target
early June 2026). Split across three patch releases (.29/.30/.31)
per AGNOS founder direction so each platform's change is
bisectable and 5.11.x patch-number runway is used rather than
bundling.

**5.11.28** (shipped 2026-05-12 — **bote parser quirk slot
closed: no-repro confirmed + diagnostic improvement +
regression test**). Premise-check at slot entry per pin:
reverted bote's `cap0/cap1` var-stage workaround to
recreate the filing's inline `assert(streq(vec_get(caps_v,
N), "lit") == 1, "msg")` shape, compiled at both v5.11.27
(current) AND v5.10.34 (filing version, intact at
`~/.cyrius/versions/5.10.34/bin/cc5`) — clean parse both
times. Synthetic fuzz 0/28 across 9 preceding-line counts ×
both versions and 10 ident-counts at filing version
(spanning the filing's ~8700 boundary speculation). Likely
closed silently by v5.11.18's identifier buffer doubling
(`f3e98a3e`, 131072 → 262144 bytes) — fits the filing's
Speculation 2 hash-collision / scan-window boundary
hypothesis. **Ships:**
(1) `tests/tcyr/parse_nested_call_assert.tcyr` (13 asserts)
locks the nested-call shape — bote's exact trigger, 3-deep
nested variant, and the same shape preceded by a 7-assert
SSRF-URL + JSON literal stress block.
(2) `src/common/util.cyr:425-432` adds a hint to `ERR_EXPECT`
when `expected ')'` or `','` AND got-token is string: the
exact symptom signature gets a `hint: a string literal where
')' is expected often means a nested call inside a fn
argument confused the parser; stage the inner call into a
\`var\` first.` line between the diagnostic and capacity
dump. Saves consumers the misleading-fix rabbit hole.
Issue file `git mv`'d to `archived/`. cc5 byte-identical at
**810,024 B** (+496 B from 5.11.27's 809,528 — diagnostic
strings + 4 syscall branches in `ERR_EXPECT`); check.sh
67/67; cyrius test 149/149 (was 148; +1 regression test).

**5.11.27** (shipped 2026-05-12 — **aarch64-native build
repair; 2 stale-fork bugs latent since v5.5.16**). Pre-empted
the v5.11.27=bote-parser-quirk slot mid-flight after `ssh pi to
verify aarch64 native` premise-check on a freshly built
`/tmp/cc5-native-aarch64` SIGILL'd at first `alloc()` call.
(1) `src/main_aarch64_native.cyr` was missing the
`CYRIUS_TARGET_LINUX`/`CYRIUS_TARGET_MACOS` predefine block
that `main_aarch64.cyr:148-159` shipped at v5.5.16 — so every
`#ifdef CYRIUS_TARGET_LINUX` in `lib/` was dead and
`alloc`/`vec_*` undefined under native-aarch64 build.
(2) `_init_cyrius_lib` + `_check_shadow_lib` (lex.cyr:221, :325,
:356) used bare `syscall(2, path, …)`; aarch64's xlat changed
2→56 but didn't reshuffle args, so path landed in dfd slot →
EFAULT → `_cyrius_lib_len` stayed 0 → version-pinned-lib fallback
dead → any include not in cwd `lib/` failed. Roadmap re-pinned
mid-slot: parser quirk slipped to v5.11.28; 4-slot OPEN buffer
remains (.32-.35). Pi e2e: compiled+ran an
alloc+vec_push+vec_get+assert program from cwd-without-lib
(version-pinned-lib fallback now fires), `exit=0`,
`1 passed, 0 failed`. cc5 byte-identical at **809,528 B**
(+288 B from 5.11.26's 809,240 — the new predefine block
+ 3 syscall-branch sites); check.sh 67/67; cyrius test
148/148. Latency 6 minors, ~150 patches — same kind of
gate-gap as v5.11.23's Win64 RSP alignment; v5.11.37
(cc5_aarch64_native cross-bin ship) will add the pi-side
CI smoke that closes the gap.

**5.11.26** (shipped 2026-05-12 — **Per-repo isolation Part 3:
`cyriusly use --global` flag + per-repo default; closes 3-part
arc**). `cyriusly use 5.11.X` (no flag) now writes `cyrius.cyml`'s
`[package].cyrius` field instead of `~/.cyrius/current`.
`--global` keeps the legacy global-pointer write. `cyriusly use`
(no args) prints resolved version + source. New helpers:
`_write_cyml_cyrius_pin` (TOML line-level rewrite — in-place
value replace or insertion at top of [package]),
`_print_resolved_version`. Hard error when no cyml + no
`--global` (instructs cd to project or pass --global). Also
fixed v5.11.25 cosmetic gotcha: `cyrius version` now reports
the binary's `_VERSION_TOOLCHAIN` (compile-time embed) instead
of `~/.cyrius/current` (the global pointer) — so re-exec'd
older binaries report their actual version. 8-case test matrix
verified all branches. **Per-repo isolation arc complete**:
v5.11.17 (deps stdlib_dir) → v5.11.25 (CLI dispatcher) →
v5.11.26 (cyriusly use --global). Sibling agents flipping the
global pointer no longer affect other repos. cc5 byte-identical
at **809,240 B** (cyriusly/cbt only); check.sh 67/67; cyrius
test 148/148.

**5.11.25** (shipped 2026-05-11 — **Per-repo isolation Part 2:
`cyrius` CLI version-resolved dispatcher**). Picks up where
v5.11.17's deps stdlib_dir fix (Part 1) left off. Every
`cyrius <cmd>` now does a version-resolution walk: reads
`cyrius.cyml`'s `[package].cyrius` field, compares with the
binary's compile-time-embedded `_VERSION_TOOLCHAIN`, and if
they differ → `sys_execve` re-exec to `~/.cyrius/versions/<pin>/
bin/cyrius` with `CYRIUS_RESOLVED=1` env loop guard. Loop guard
detected on re-entry by `find_tools()` → sets `_cyrius_resolved`
→ skips the redirect (no infinite loop). Hard error (NEVER
silent slide to `latest`) when pinned binary isn't installed —
matches v5.11.17 deps policy. Skipped for cyrius source repo
(`src/main.cyr` present). **NEW** `_VERSION_TOOLCHAIN` literal
in `src/version_str.cyr` (version-bump.sh regen block writes it
going forward). 5-case test matrix verified: same-version /
no-cyml / source-repo → no re-exec; uninstalled pin → exit=1
with clear message; installed-different-pin → re-exec confirmed;
CYRIUS_RESOLVED=1 → loop guard skips. cc5 byte-identical at
**809,240 B**; check.sh 67/67; cyrius test 148/148. Part 3
(`cyriusly use --global`) stays pinned at v5.11.26 to close
the arc.

**5.11.24** (shipped 2026-05-11 — **`#derive(accessors)` >16-field
silent miscompile fix**). agnos 1.28.3 `struct Process` (22
fields) hit a no-bounds-check overflow in `src/frontend/lex_pp.cyr`
per-struct field tables — silently clobbered field_types,
produced wrong accessor offsets, manifested as `CR3=0x2`
page-fault on first kernel context switch. **Fix**: relocate
per-struct field tables from 0x197060 (1152 B / 16-field cap)
to 0x194600 (within the 10.5 KB free band at 0x194600-0x197000),
raise cap **16 → 32**, add hard-cap diagnostic past 32. New
`tests/tcyr/derive_accessors_large.tcyr` exercises the 17-field
case directly. 80 hex-literal updates + 9 LOC for the
diagnostic (all in lex_pp.cyr; no cross-file callers). cc5
byte-identical at 809,200 B; check.sh 67/67; cyrius test
**148/148** (+1 new tcyr). 33-field test verified the
diagnostic fires loud (exit=1 with clear error) — no more
silent miscompile. agnos's `Process` `#derive(accessors)` port
now unblocked.

**5.11.23** (shipped 2026-05-11 — **PE32+ kernel32 path-API
alignment fix**). Closes the pre-existing bug v5.11.22 surfaced:
EOPEN_PE / ECREATEDIR_PE / EDELETEF_PE used frame size 0x250
which left RSP misaligned by 8 at the kernel32 CALL (Win64 ABI
requires 16-aligned RSP). Wine 11.8 tolerated; Win11 26200's
ntdll detects via TEB/SEH-frame validation at `+0x41912` and
access-violates. **Single-byte fix**: 0x250 → 0x258 (frame mod
16 = 0 → 8, cancels cyrius's +8 entry-state). Real call bodies
shipped for ECREATEDIR_PE + EDELETEF_PE (replacing v5.11.22
-ENOSYS placeholders). NEW `_pe_path_apis_gate` in
programs/check.cyr exercises CreateFileW + mkdir + unlink on
cass with filesystem-effect verification — **the FIRST PE
path-API smoke that's been green on real Windows in cyrius's
history**. check.sh count 66 → **67**. The bug had been silent
for 6+ minors because `_pe_exit_gate` only tested exit42 +
hello-world; never any kernel32 path API. Audit-driven
discovery via ai-hwaccel's filing (v5.11.22 debunk →
unrouted-syscall finding → routes → alignment fault → bisect →
fix). cc5 byte-identical at **809,032 B** (+2,928 from real
bodies replacing placeholders); check.sh 67/67; cyrius test
147/147.

**5.11.22** (shipped 2026-05-11 — **ai-hwaccel cc5_win debunk +
mkdir/unlink PE plumbing**). Per user direction "review the
ai-hwaccel repo and usage" — empirical audit on cass found the
minimal `syscall(60, 42)` PE binary EXIT-CODE filing is a
**second premise-debunk** (works on cass with correct wrappers;
follows v5.10.49's pattern but with the right test shape this
time). Real ai-hwaccel.exe crash is `STATUS_ILLEGAL_INSTRUCTION`
(0xC000001D) from 3 unrouted syscalls in cache.cyr +
detect/platform.cyr (mkdir 83, unlink 87, readlink 89).
**Shipped**: PE auto-imports for CreateDirectoryW + DeleteFileW
(`_pe_ensure_createdir` / `_pe_ensure_deletef` in pe/emit.cyr);
parser dispatch for syscall(83) + syscall(87) routing to
ECREATEDIR_PE / EDELETEF_PE; placeholder emit bodies that pop
args and return -ENOSYS (-38) — consumers' `if (rc < 0)` path
fires cleanly. Updated warning text to mention STATUS_ILLEGAL_INSTRUCTION
(0xC000001D) and the full set of routed numbers. **Pre-existing
PE bug surfaced**: EOPEN_PE (CreateFileW, existing route)
faults at `ntdll!+0x41912` on Win11 26200 same as new
ECREATEDIR_PE would — shared UTF-16 widening pattern bug,
masked because `_pe_exit_gate` only tests exit42 + hello-world,
never kernel32 path APIs. Held back real call bodies; pinned
v5.11.23 = full widening fix + IAT layout + cass-gate. ai-hwaccel
issue archived with debunk evidence. cc5 byte-identical at
806,104 B (+1,648 from emit/dispatch); check.sh 66/66;
cyrius test 147/147.

**5.11.21** (shipped 2026-05-11 — **0-call public stdlib fn downstream
survey**). 10 PUBLIC stdlib fns flagged 0-callers-within-cyrius
audited across all 50 sibling repos. **Net: 0 removals, 0
deprecations**. Audit revealed 5/10 have downstream consumers
(daimon → async_new; cyim → niyama_bre_compile; libro → sig_alg_name;
sandhi-internal → sandhi_err_kind_name; sakshi-internal →
sakshi_clock_recalibrate), 3/10 are NSS cache-invalidation
trio (grp/pwd/shadow_invalidate_cache — coherent surface,
agnos/kavach intended consumer), 2/10 speculative/init verbs
(callback::for_each, log_init — kept with v6.0.0 dead-code
sweep revisit pointer). Validates
`feedback_dead_code_audit_scope` — 0-callers-in-grep is NOT
safe-to-remove. Docstrings updated in 8 native lib files (folded
distfiles sakshi/sandhi left byte-identical with upstream).
**NEW** `docs/audit/2026-05-11-zero-call-stdlib.md` carries the
full per-fn decision tree. cc5 byte-identical at 804,456 B
(comment-only edits); check.sh 66/66; cyrius test 147/147.

**5.11.20** (shipped 2026-05-11 — **syscall-wrapper DRY consolidation**).
~46 body-identical wrappers extracted from `lib/syscalls_x86_64_linux.cyr`
+ `lib/syscalls_aarch64_linux.cyr` into a NEW `lib/syscalls_linux_common.cyr`
that both peers `include` after their own SysNr enum is defined.
Audit found **4× more duplication** than the v5.11.7 close-out
estimate (10-12 fns → 46 actual). Groups extracted: file I/O,
process lifecycle, wait-status macros, 9 credentials, kavach
sandbox trio, mount/fs, signal, epoll, timer, getdents64/random,
Landlock trio, 7 sockets. Kept in peers: at-family dispatch
(sys_open/stat/mkdir/etc.), arch-divergent (sys_fork → clone+SIGCHLD,
sys_pipe → pipe2, sys_pause → ppoll-NULL, sys_epoll_wait →
epoll_pwait, sys_inotify_*). **Gotcha caught at slot entry**:
`#io` annotation in common file broke aarch64 cross-build —
`error:913: unexpected enum` because `src/main_aarch64.cyr`'s
pass-1 scanner lacks the v5.8.21 `#io` token-126 handler that
`src/main.cyr` has. Dropped `#io` from common file; main_aarch64.cyr
fix is follow-up. **Line savings**: 1542 → 1354 LOC (-188, ~12%
of original). cc5 byte-identical at 804,456 B (no change — wrappers
were already body-identical). check.sh 66/66; cyrius test 147/147.
api-surface 3050 → 3000 (-50 from the dedup; net consumer-visible
count unchanged).

**5.11.19** (shipped 2026-05-11 — **kybernet Part A.ii: fn_table
4096 → 8192 heap-map refactor**). Highest-risk slot of v5.11.x —
self-hosting compiler heap layout shift. **5-phase byte-identical
execution**: (1) relocated 7 scattered fn_* tables (fn_deprecated_msg
0x104000→0x100000, fn_name_hash 0x10C000→0x110000, fn_start_hash
0x110000→0x114000, fn_regalloc 0x1C8000→0x14A000, fn_ret_sid
0x1EC000→0x15A000, fn_variadic 0x1F4000→0x16A000, fn_flags
0x1FC000→0x17A000) into the 0x100000-0x118000 + 0x14A000-0x18A000
gaps; (2) shifted IR + fixup regions forward by 0x80000 to free
0x12CA000-0x134A000; (3) moved primary fn_* block 0x128A000 →
0x12CA000 + doubled stride 0x8000→0x10000; (4) doubled extended
fn_* block stride 0x8000→0x10000 (reverse-order sed to avoid
collision); (5) REGFN cap check 4096 → 8192 + warning thresholds.
Hash tables kept at 8192 slots × 2B (mask 8191 preserved) — the
0.5 load factor degrades to 1.0 at extreme caps but kybernet's
3779-fn worst case stays at 0.46. `CYRIUS_STATS=1` on cc5
self-compile now shows `fn_table: 660 / 8192`. ~85 hex-literal
edits across 15 src/ files. **cc5 self-host byte-identical at
804,456 B** (was 804,464; -8 from string-literal length deltas).
Phase 1 had an initial misplacement at 0xA0000-0xF0000 inside
input_buf — first compile worked but resulting binary hung on
self-compile; caught at fixpoint check, no ship damage. Redo at
real-gap offsets clean. check.sh 66/66; cyrius test 147/147; api-
surface 3050 exact match. kybernet 1.1.0 (3779 fns) now reads as
46% — well below 85% warn threshold; combined with v5.11.18
identifier buffer raise, kybernet 1.1.0 should compile clean.
kybernet-fn-table issue archived.

**5.11.18** (shipped 2026-05-11 — **kybernet Part A.i + Part B:
identifier buffer 2× + socket-syscall wrappers**). Identifier
buffer 131072 → **262144 bytes** (grows 0x60000-0xA0000 into
existing gap; lex.cyr NPOS_GUARD/LEXID threshold + main*.cyr
warnings + util.cyr parse-failure dump). Part B: 7 socket-family
wrappers added to `lib/syscalls_x86_64_linux.cyr` + `lib/
syscalls_aarch64_linux.cyr` (sys_socket/bind/connect/listen/
recvfrom/recvmsg/accept4 — 14 fns total). Closes silent aarch64
misroute footgun (x86 41→pipe2 etc.). New test
`tests/tcyr/socket_syscalls.tcyr` runtime-exercises sys_socket
AF_UNIX/SOCK_DGRAM. **Audit-driven scope shrink**: reporter's
"single source-line edit" framing for fn_table 4096→8192 was
wrong — 15+ fn_* tables across scattered locations need
relocate-and-shift; split off to v5.11.19 as standalone heavy
slot. All subsequent pinned slots shifted forward by 1.
api-surface 3036 → **3050** (+14). cc5 byte-identical at
804,464 B; check.sh 66/66; cyrius test 147/147 (+1).
kybernet-socket-syscall-wrappers issue archived; fn_table
caps issue remains active until v5.11.19.

**5.11.17** (shipped 2026-05-11 — **per-repo isolation Part 1: deps
stdlib_dir fix**). `cbt/deps.cyr::_dep_find_stdlib_dir()` rewritten:
new priority is `./lib` if in cyrius source repo (signaled by
`src/main.cyr`) → `~/.cyrius/versions/<cyml-cyrius-field>/lib/` if
the consumer's `cyrius.cyml` pins `[package].cyrius` → legacy
`~/.cyrius/lib` fallback. Pinned-but-not-installed = HARD ERROR
(never silent slide). New helper `_dep_read_cyml_cyrius_field()`
parses the field from cyml's `[package]` section. Closes the
snapshot-ping-pong wipe wedge (hit v5.11.3 + v5.11.13). Regression
test: in-tree `lib/syscalls.cyr` edit + `cyrius deps` run → hash
unchanged. Original v5.11.17 5-item acceptance bar split into 3
slots at v5.11.16 close per user direction; Parts 2-3 pinned at
v5.11.23 (`cyrius` CLI version-resolved dispatcher) and v5.11.24
(`cyriusly use --global` flag + per-repo default). cc5 byte-
identical at 804,472 B (deps.cyr is dispatcher-only); check.sh
66/66; cyrius test 146/146.

**5.11.16** (shipped 2026-05-11 — **bote WS handshake key validation
+ slot map consolidation**). RFC 6455 §4.1 enforcement in
`lib/ws_server.cyr`: `Sec-WebSocket-Key` must be exactly 24 chars
(base64 of 16 bytes); reject any other length before the SHA-1
Accept derivation. Single conditional, fail-closed (returns 0;
caller responds 400). **Plus** consolidation of the v5.11.x slot
map per user direction *"close up open gap, so we have additional
runway later"*: pinned slots .18-.23 shifted back 2 (closing the
.16-17 OPEN gap freed by v5.11.15's bote streaming arc collapse).
**New emergent pin**: `#derive(accessors)` >16-field silent
miscompile (agnos 1.28.3, filed 2026-05-11) at v5.11.22 — root
cause in `src/frontend/lex_pp.cyr` per-struct metadata tables
hard-sized at 16; 17th+ field clobbers adjacent regions. cc5
byte-identical at 804,472 B; check.sh 66/66; cyrius test 146/146.
Issue archived.

**5.11.15** (shipped 2026-05-11 — **bote P2: streaming dispatch
primitives, 3-slot arc collapsed to 1**). Premise check found cyrius
already shipped the heavy primitives — `chan_new` / `chan_send` /
`chan_recv` / `chan_close` (v5.5.31, MPSC futex-backed) + `atomic_*`
(v5.5.31). Slot work was 4 thin shims: `chan_try_recv` (non-blocking),
`cancel_token_new` / `cancel_token_signal` / `cancel_token_check`.
Plus doc block at top of `lib/async.cyr` showing the bote
transport ↔ worker integration pattern. api-surface 3032 →
**3036** (+4). cc5 byte-identical at 804,472 B; check.sh 66/66;
cyrius test 146/146. **Roadmap**: v5.11.16-17 freed from the
3-slot scope — now OPEN for emergent items.

**5.11.14** (shipped 2026-05-11 — **bote P2: arena_free lifecycle
terminator + per-frame reuse pattern docs**). New `fn arena_free(a)`
in `lib/alloc.cyr` invalidates the arena handle. Audit clarified
that `arena_reset` (the load-bearing per-frame reuse primitive bote
needed) already shipped at v5.5.x; the issue's "fl_free" title was a
misframe of the existing surface + missing lifecycle terminator.
Docstring refreshed with the bote WS / SSE per-frame reuse pattern.
api-surface 3031 → **3032**. cc5 byte-identical at 804,472 B;
check.sh 66/66; cyrius test 146/146. Issue archived.

**5.11.13** (shipped 2026-05-11 — **bote P2 Part A: sock_set_recv_timeout**).
New `fn sock_set_recv_timeout(fd, secs, usecs): i64` in `lib/net.cyr`
sets `SO_RCVTIMEO` via setsockopt — Slowloris defense. Closes bote
1.9.5 audit H5. Functional test: 1-second timeout fires in 1.056s,
recv returns -EAGAIN. api-surface 3030 → **3031**. Part B
(getaddrinfo equivalent) pinned forward — larger DNS-resolver
surface, multi-slot scope. cc5 byte-identical at 804,472 B;
check.sh 66/66; cyrius test 146/146. Issue archived to
`issues/archived/`.

**5.11.12** (shipped 2026-05-11 — **daimon P2: lib/async.cyr aarch64
portability fix**). Three bare `syscall(SYS_X, ...)` calls in async.cyr
replaced with arch-dispatching wrappers: `sys_epoll_wait` (lines 117 +
145), `sys_pipe` (line 126), `sys_fork` (line 129). daimon's filing
flagged SYS_EPOLL_WAIT; aarch64 cross-build surfaced the other two.
Cross-host smoke: pi runtime exit=0 ✓. cc5 byte-identical at 804,472 B;
check.sh 66/66; cyrius test 146/146. Closes
[`docs/development/issues/2026-05-10-daimon-async-aarch64-sys-epoll-wait.md`](issues/2026-05-10-daimon-async-aarch64-sys-epoll-wait.md).

**5.11.11** (shipped 2026-05-11 — **TS test harness program**). New
`programs/ts_test_runner.cyr` — standalone CLI harness walking
.ts/.tsx fixtures via `cc5 --parse-ts` / `--lex-ts`. Added to
`[release].bins` (80,248 B). Real-corpus smoke against secureyeoman:
**2053/2053 .ts + 435/435 .tsx passed** at `--mode=parse`. cc5
byte-identical at 804,472 B; check.sh 66/66; cyrius test 146/146.
install.sh ships 19 bins (was 18).

**5.11.10** (shipped 2026-05-11 — **Cyriusly cmdtools port closeout**).
All 11 cyriusly verbs handled by `programs/cyriusly.cyr` (cyrius
binary 89,616 B). Native impls: `version` / `list` / `ls` / `which` /
`home` / `help` / `use`. Shell-out via `exec_cmd`: `uninstall` /
`install` / `update` / `setup` / `cmdtools`. `cyriusly` added to
`[release].bins`; removed from `[release].scripts` (binary replaces
shell script in install). scripts/cyriusly stays in tree as the
backend for the `setup` / `cmdtools` shell-out paths. install.sh
ships 18 bins (was 17). cc5 byte-identical at 804,472 B; check.sh
66/66; cyrius test 146/146.

**5.11.9** (shipped 2026-05-11 — **Cyriusly cmdtools port — scaffold +
light verbs**). New `programs/cyriusly.cyr` ports the lighter
sub-commands (`version` / `list` / `which` / `home` / `help`).
Heavier verbs (`setup` / `install` / `update` / `uninstall` / `use` /
`cmdtools`) defer to `scripts/cyriusly` until v5.11.10 closes the
arc. Binary committed at `programs/`; NOT in `[release].bins` yet
(scripts/cyriusly still load-bearing for unported verbs). cc5
byte-identical at 804,472 B. check.sh 66/66; cyrius test 146/146.
`tests/regression-*.sh` arc audit confirmed COMPLETE at v5.9.41 —
zero remaining scripts to port (the .9 pin half resolved as no-op,
pivoted to start the cyriusly port early).

**5.11.8** (shipped 2026-05-11 — **`cyrius deps` symlink → file-copy**).
`cbt/deps.cyr:603` no longer emits `syscall(88, ...)` symlink; always
calls `_dep_copy_file`. Eliminates the install.sh `cp -L` same-file
collision + snapshot-ping-pong silent-wipe trigger (which bit us at
v5.11.3 mid-Phase 3). Pairs with v5.11.19 per-repo version isolation.
Plus post-v5.11.7 lib comment condensation (8 native files,
~80 lines history → CHANGELOG pointers; memory pin
`feedback_comments_primary_info_plus_changelog_pointer`). cc5
byte-identical (deps.cyr not in main.cyr chain); build/cyrius CLI
rebuilt to 175,240 B; check.sh 66/66; cyrius test 146/146.

**5.11.7** (shipped 2026-05-11 — **Phase 7: compiler-side internals
+ ARC CLOSE**). 44 fns annotated across `src/common/ir.cyr` (44→64)
and `src/frontend/parse_types.cyr` (0→24). parse_decl + parse_fn
were already at 100%. cc5 byte-identical at 804,472 B; check.sh
66/66; cyrius test 146/146; api-surface unchanged at 3030 (compiler
internals don't expose publicly).

**Annotation arc TOTAL** (v5.11.1 → v5.11.7): **~1,306 in-tree
fns annotated across 7 slots**. Phase 5 mabda (747 fns) handled
out-of-band on mabda v3 branch awaiting 3.0.0 GA. stdlib +
compiler-internals coverage at effective 100% on in-tree modules.
api-surface delta across arc: 2,876 → **3,030** (+154 public fns).

**Arc CLOSED**. v5.11.8 picks up `cyrius deps` symlink→file-copy fix.

**5.11.6** (shipped 2026-05-11 — **Cross-binary ship: cc5_win
(PLATFORM BLOCKER unblock)**). Added `cc5_win` to
`cyrius.cyml [release].cross_bins` — Linux x86_64 ELF cross-compiler
emitting Win64 PE32+. Unblocks ai-hwaccel agent's DXGI work
(re-flagged at v5.10.37 / v5.11.5 ship). install.sh generic rebuild
rule picks up automatically; release snapshot now ships 18
bins/scripts (was 17). Cross-host smoke: cc5_win runs on cass,
emits valid PE. Three deferred cross-targets pinned to back of
buffer band per user direction:
**cc5_aarch64_macho → v5.11.36** (host-runtime mmap fix needed),
**cc5_aarch64_native → v5.11.37** (build + pi smoke),
**cc5_cx → v5.11.38** (VM smoke target). Buffer band tightens
from 18 to 15 slots (v5.11.21-35 OPEN).

**5.11.5** (shipped 2026-05-11 — **Stdlib annotation arc Phase 6:
partial-coverage closeouts** + **mabda annotation out-of-band on v3
branch**). 13 modules topped to 100%: vani, patra, agnosys, sandhi
(703 fns — refold reset), pwd, grp, shadow, cyml, fdlopen, flags,
net, u128, ws_server. ~761 fns added in-tree. Plus 747 mabda fns
on v3 branch (not committed; awaiting 3.0.0 GA release). Arc total
in-tree: 501 → **~1262**. cc5 byte-identical 804,472 B.
**check.sh 66/66**; **cyrius test 146/146**. Mabda is **release-
blocked until 3.0.0 GA** per user; annotation prep done so the
mabda agent's rc.3 work is purely soak testing.

**Roadmap shift**: Phase 6 promoted v5.11.6 → v5.11.5 (mabda
removed from cyrius slot list). **v5.11.6 inserted as PLATFORM
BLOCKER** — ship `cc5_win` + `cc5_aarch64_macho` (+ aarch64_native /
cx as bandwidth allows) in `[release].cross_bins`. Pinned 2026-05-11
after ai-hwaccel agent re-flagged the v5.10.37 cc5_win gap. Phase 7
compiler-internals cascades to v5.11.7 — **arc CLOSES at v5.11.7**.

**9-sibling fold-in (byte-identical)**: dist files from vani 0.9.3,
patra 1.9.4, agnosys 1.2.6, sandhi 1.3.4, sakshi 2.2.4, sigil 3.1.1,
yukti 2.2.3, sankoch 2.2.5, niyama 1.0.2 all folded into
`cyrius/lib/<name>.cyr` per v5.8.65 sandhi pattern. cc5 byte-identical
at 804,472 B. **api-surface 2876 → 3030 (+154 fns)**.

**v5.11.20 pin expanded 2026-05-11** to bundle kybernet's second
filing (socket-syscall wrappers — `sys_socket` / `sys_bind` /
`sys_recvfrom` / `sys_listen` / `sys_accept4` / `sys_connect` +
`sys_recvmsg`, mirrored across x86_64 + aarch64 peers). Same
release as the existing cap-raise; both kybernet P2 stdlib asks.
Filing:
[`docs/development/issues/2026-05-11-kybernet-socket-syscall-wrappers.md`](issues/2026-05-11-kybernet-socket-syscall-wrappers.md).

**5.11.4** (shipped 2026-05-11 — **Stdlib annotation arc Phase 4:
collection libraries**). 127 public fns across 2 modules
(hashmap 41, json 86) — heavier than the roadmap's ~89 estimate.
All `: i64` (map ptrs / counts / tagged json values). cc5
byte-identical at 804,472 B. **check.sh 66/66**;
**cyrius test 146/146**. Arc total: 374 → **501** annotated
(~50 % — halfway). **v5.11.20 pinned**: kybernet
`fn_table`+`identifier buffer` cap raise (filed 2026-05-11; lands
first slot in buffer band after annotation arc).

**5.11.3** (shipped 2026-05-11 — **Stdlib annotation arc Phase 3:
string/format completion**). 85 public fns added across 5 modules
(string +7, str +16, bigint +24, chrono +19, bench +19) closing
the string-handling band. cc5 byte-identical at 804,472 B.
**check.sh 66/66**; **cyrius test 146/146**.

**Phase 3 modules + counts**: string 16/16, str 70/70, bigint 24/24,
chrono 19/19, bench 19/19. **Coverage delta**: 289 → **374**
annotated; stdlib gap → **~743** unannotated (~37 % arc progress).

**Mid-slot recovery**: snapshot-ping-pong wipe triggered when
`cyrius test` ran against a stale `~/.cyrius/lib` symlink (agnosys
agent had switched to v5.10.44 for its tests). v5.11.2 snapshot
intact; restored + re-applied Phase 3. **Pinned v5.11.19**: per-repo
version isolation via `cyrius.cyml`'s `cyrius` field (resolve from
project instead of global `~/.cyrius/current`; error if version
not installed). User direction.

**5.11.2** (shipped 2026-05-11 — **Stdlib annotation arc Phase 2:
I/O surface**). 182 public fns across 5 modules (io / fs / process
+ syscalls_x86_64_linux + syscalls_aarch64_linux). Mix of `: i64`
(raw syscall returns), `: Result` (10 fns — io `_r` family + process
run/run_capture/spawn/wait_pid), with three fs.cyr path fns kept
`: i64` (Str-shape downgrade — fs.cyr's consumers don't all
include str.cyr first; Phase 6 closeout will add the include and
re-promote). cc5 byte-identical at 804,472 B. **check.sh 66/66**;
**cyrius test 146/146** — parser_cosmetics now passes (v5.11.1
snapshot refresh fixed the include chain).

**5.11.1** (shipped 2026-05-11 — **Stdlib annotation arc Phase 1:
foundational core**). 107 public fns across 8 modules
(alloc / vec / fmt / freelist / fnptr / result / tagged / assert)
now carry `: i64` return-type annotations. Same shape as v5.10.24's
`cstring` annotation pass on `string.cyr` / `io.cyr` — parse-only,
zero codegen impact. cc5 self-host **804,472 B at v5.11.1 — byte-
identical to v5.11.0** (annotations don't change emit). check.sh
66/66; cyrius test 144/146 (1 pre-existing parser_cosmetics fail
absorbed into v5.11.2's snapshot refresh).

**v5.11.0** (shipped 2026-05-11 — **v5.11.x cycle OPEN — kavach P1
sandbox syscall wrappers + roadmap restructure**). v5.10.x closed
at .50; v5.11.0 opens the next minor with the highest-priority
pending work landed (kavach P1 — the only P1 in the consumer-
filed issue backlog) plus roadmap restructure mapping the v5.11.x
arc. cc5 self-host **804,472 B at v5.11.0 — byte-identical to
v5.10.50** (stdlib-only change; cc5 doesn't include
`lib/syscalls_*_linux.cyr`). api-surface 2,876 → **2,888**
(+12 fns).

**Six new wrappers (x86_64 + aarch64 mirrored)**: `sys_fchmod`,
`sys_setresuid`, `sys_setresgid`, `sys_prctl`, `sys_seccomp`,
`sys_execveat`. All async-signal-safe (no heap, no mutex, no
logging) for post-fork / pre-execve sandbox transition windows.
Closes `docs/development/issues/2026-05-10-kavach-sandbox-syscall-
wrappers.md`. 7 sub-asserts in new
`tests/tcyr/sandbox_syscalls.tcyr` (safe wrappers runtime-
exercised; dangerous wrappers compile-time-referenced via `&fn`).

**v5.11.x mandate**:
1. **Stdlib annotation arc** (7-phase, pinned v5.10.32):
   1,010 unannotated public fns across 75 % stdlib coverage.
2. **7 consumer-filed issues** from 2026-05-10 wave (bote /
   daimon / kavach) — 1 P1, 4 P2, 2 Low.
3. **Held-forward from v5.10.x** — Class B FFI/wgpu, cyim
   regex, float.cyr peephole.
4. **Infrastructure** — `cyrius deps` symlink → copy fix
   (v5.10.37 pin), regression.sh → cyrius port +
   Cyriusly cmdtools port (v5.10.36 pin paired), TS test
   harness program (v5.7.37 → v5.10.20).

Slot ordering at slot entry per
`feedback_priority_bottom_to_top` + `feedback_premise_check_at_slot_entry`:
P1 first → annotation foundations (v5.11.1) → cross-arch
fixes → consumer-blocking P2 → infrastructure rotation →
annotation completion → TS test harness → defensive sweep
+ closeout.

See [`docs/development/roadmap.md`](roadmap.md) `## v5.11.x —
Cleanup / annotation-completion minor` section for the full
arc map.

Premise debunk: chat-side cross-host smoke wrappers used `cmd /c
"prog.exe & echo %errorlevel%"` which expands at parse time →
false-negative `exit=0`. Correct shapes (memory pin
`feedback_windows_errorlevel_test_wrapper` saved this slot):
`cmd /v /c "... !errorlevel!"` or `.bat` indirection
(`programs/check.cyr`'s `_pe_exit_gate` always used the correct
shape; chat-side wrappers diverged). Phantom claim propagated
through CHANGELOG entries [5.10.33] / .34 / .39 / .40 / .41 /
.44 / .47; this entry is the durable correction.

**Retroactive Phase 3 status update**: v5.10.47 struct-byval
Phase 3 cass runtime is **actually green** (Point repro
`syscall(60, run())` → cass exit=42 verified with `cmd /v`).
The arc was 4/4 across x86/pi/ecb/cass, not 3/4 as the .47
entry noted under bad-wrapper assumption. Per
`feedback_doc_canonical_no_redundancy`: .47 entry stays as
shipped; this .49 entry is the corrected record.

**Arc COMPLETE** (planned at v5.10.45 entry; see CHANGELOG [5.10.45]
"Arc shape" for the empirical premise-check that drove the
re-scoping):
- Phase 1 (v5.10.45, **shipped**) — x86 SysV via rax+rdx pair.
- Phase 2 (v5.10.46, **shipped**) — aarch64 AAPCS64 via X0+X1
  pair (Linux + Mach-O share ABI). pi runtime exit=42 ✓.
- Phase 3 (v5.10.47, **shipped — arc CLOSED**) — Cross-host
  matrix: local x86 + pi + ecb runtime green; cass compile-clean
  (runtime exit-code gated on pre-existing v5.10.49 PE gap).

Acceptance bar: `struct Point {x: i64; y: i64;}` + `fn make():
Point` + `var got: Point = make();` returns got.y correctly
(not lost to scalar-rax). Pre-v5.10.45 the high half was silently
dropped across ALL backends for value-typed 16B struct returns;
v5.10.28's f64v2 fix didn't generalize (f64v2 uses SSE-class
XMM0, int-class structs use rax+rdx). Str's 16B handle-shape is
preserved unchanged via `_STR_SID(S)` special-case carve-out.
Phase 1 x86 acceptance MET; aarch64 + PE staged for Phase 2/3.

Three new public verbs (`exec_vec_str` / `exec_capture_str` /
`exec_env_str`) parallel the cstr-shape `exec_vec` / `exec_capture`
/ `exec_env`. Each `_str` sibling extracts `str_data` on the way
into execve's argv (and envp for the env variant), so callers
using the natural cyrius idiom (`vec_push(args, str_from("/bin/
foo"))`) get a working verb. Runtime byte/Str dispatch was rejected
at slot entry — both shapes are pointers in cyrius's heap layout,
and the `load64(P)`-looks-like-a-pointer heuristic fails for 8+-
char cstrs (`"/usr/bin"` loads as 7.97e18). Argonaut-blocking
issue closed; consumers migrate via one-line patch
(`exec_vec(cstr)` → `exec_vec_str(Str)`). 6 sub-asserts in new
`tests/tcyr/process_exec_str.tcyr` all pass.

api-surface bumped 2873 → **2876** (+3 fns for the `_str` family).

**Headline numbers** (CYRIUS_PROF=1, `cc5 < src/main.cyr`,
best-of-5 median, end-to-end v5.10.x perf-arc gain pre-.40 → .41):
- lex phase: **603 ms → 62 ms (−90 %, ~9.7×)** [.40]
- fixup phase: **213 ms → 76 ms (−64 %, ~2.8×)** [.41]
- total compile: **1037 ms → 387 ms (−63 %, ~2.7×)** [.40+.41 combined]

v5.10.40 approach: length-bucketed linked-list dedup at heap region
`0x4E8C000..0x4EAD000` (132 KB brk extension; PE mmap had slack).
Per-length head into a 16384-entry chain table.

v5.10.41 approach: `fn_start_hash` open-addressing table at
`0x110000` (8192 slots × 2 B = 16 KB) reusing the 232 KB free gap
between `fn_name_hash` and `struct_ftypes` — no brk extension. Knuth
golden-ratio multiplicative hash; replaces two O(N²) DCE byte-scan
linear scans with ~2-probe lookups. aarch64 fixup has no DCE pass,
so x86-specific change (cross-arch propagation verified by reading
aarch64 fixup.cyr).

Cross-host verified at v5.10.40: pi (aarch64 Linux) native
self-host fixpoint b == c byte-identical at 567,672 B; ecb (macOS
Mach-O arm64) compile+run exit=42; cass (Windows PE) compile
exit=0. v5.10.41 smoke on cass green; pi/ecb byte-identical to
v5.10.40 (no aarch64 backend change).

**Slots .33 - .50 one-liner sweep**:
- **v5.10.33** — `lib/simd.cyr` typed wrappers around f64v_*
  intrinsics; first downstream consumption of typed-simd ABI
  Phase 5 (XMM0 return).
- **v5.10.34** — `lib/tls.cyr` early-data status accessors
  (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + 2 fns); sandhi
  1.1.0 → 1.3.3 fold (+1,194 lines); doc-health.md ledger
  introduced at this slot.
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness codegen fix
  via new `_SIMD_STASH` helper; covers ptyp 93-130 (8 intrinsics).
  Same bug-class hit again at v5.10.39 for ptyp 89-91 (separate
  dispatch path).
- **v5.10.36** — aarch64 V0 NEON register-class return for
  f64v2 (replaced v5.10.30 X0+X1 GPR pair); LDUR Q0 / STUR Q0
  for single-register transfer.
- **v5.10.37** — `f64v4` (32-byte packed-double) value type;
  parser + var-decl + extensions; pair-quad return ABI across
  x86 SSE, aarch64 NEON imm12-scaled deep-frame fallback, cx
  4-register r0..r3.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9
  + Phase 10); 0x1282000 fn_param_simd_mask heap region;
  cyrius-internal SysV split-counter (SIMD ordinal independent
  of int ordinal); per-backend ESTOREPARM_F64V*/ELOAD_F64V*_TO_XMM
  emission.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `f64v2_add_ptr`; `f64v2_add(x, y)` calls value-form
  base) + lib/simd.cyr full rewrite (50 public fns, value-form
  gated by CYRIUS_HAS_VAL_SIMD_PARAMS for non-PE targets).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table with per-length head chains; first-occurrence-
  wins canonical offset. lex 603→59 ms (10.2×), total 1037→510 ms
  (2×). Cross-host verified on pi/ecb/cass.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio hash) reusing
  free 232 KB gap. Replaces two O(N²) DCE byte-scan inner linear
  scans (seed + propagate). fixup 213→76 ms (2.8×), total 510→
  387 ms (1.32×). aarch64 fixup has no DCE — x86-specific.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises
  the verb inventory + lifecycle invariants + failure / partial-
  state contract across 24 public verbs. `lib/tls.cyr` header
  points to the doc. cc5 byte-identical (doc-only). No vidya
  entry (API surface, not gotcha). Snapshot-ping-pong guard
  applied via `~/.cyrius/lib/` mirror.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix. Runtime dispatch on `sep < 256` (byte path) vs `>= 256` (Str
  fat-pointer path); multi-byte Str sep supported. Closes the
  long-standing
  `2026-05-03-str-split-sep-treated-as-pointer.md` issue (live the
  entire v5.x cycle). `lib/process.cyr:224` cstr-sep bug fixed in
  same slot. cc5 byte-identical (lib-only; no compiler include).
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix.
  Parallel `_str` family (`exec_vec_str` / `exec_capture_str` /
  `exec_env_str`) — each extracts `str_data` on the way into
  execve's argv. Runtime dispatch rejected at slot entry (cstr 8+-
  char literals fail the pointer heuristic). Closes the argonaut-
  blocking
  `2026-05-10-process-exec-str-cstr-ambiguity.md`. api-surface
  2873 → 2876 (+3). cc5 byte-identical (lib-only).
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. New `_cur_fn_ret_pair` global,
  `EFLLOAD/STORE_STRUCT_INT_PAIR` x86 emit helpers (rax+rdx),
  caller-side `asv_pair` path mirroring asv_try. `_STR_SID(S)`
  carve-out preserves Str's 16B handle-shape unchanged. cc5
  +4,176 B. 14 sub-asserts in new `tests/tcyr/struct_byval_return.tcyr`.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs in
  `src/backend/aarch64/emit.cyr` replaced with LDUR/STUR X0,X1
  fast path + LDR/STR via X9 deep-frame fallback. Single change
  covers both Linux aarch64 + macOS arm64 (shared AAPCS64). pi
  runtime: minimal `struct Point` repro → exit=42 ✓ (was 7).
  cc5 byte-identical to v5.10.45 at 803,088 B (aarch64-only
  change). Phase 3 (.47 cross-host smoke + PE retptr verify)
  pinned next.

Per CLAUDE.md, slot-by-slot detail lives in `CHANGELOG.md` (source
of truth); closed cycles roll into `completed-phases.md` at each
minor close. The "Recent shipped" section below carries one-liners
for the current cycle.

## Compiler

- **cc5 (x86_64)**: **804,472 B** at v5.10.50 (unchanged
  from v5.10.48/.49; .50 is closeout — verify + docs +
  cleanup only). Full cycle delta: 753,768 B at v5.10.0 →
  804,472 B at v5.10.50 (+50,704 B / +6.7%); back-half delta
  (.39→.50): +7,008 B (.40/.41 perf miniarc +1,448 B;
  .42/.43/.44 flat; .45 +4,176 B; .46/.47 flat; .48
  +1,384 B; .49/.50 flat).
- **cc5_aarch64_native (cross-built)**: **587,048 B** at
  v5.10.47 (stable through Phase 2/3).
- **cyrius CLI**: ~170,900 B at v5.10.40 (flat across the
  cycle — `cyrius` doesn't run LEXID itself).
- **cc5_macho_arm (cross-built)**: **606,644 B** at
  v5.10.47. End-to-end run on ecb verified at Phase 3
  (exit=42).
- **cc5_win (cross)**: **701,440 B** at v5.10.47 (was
  ~696,832 B at v5.10.44; +4,608 B for the .45/.46
  emit helpers reaching the PE backend via x86 emit.cyr).
  (PE
  backend lives under x86, so the .45 emit helpers
  reach this binary — int-class pair-return ABI now
  available cross-compiled). PE retptr semantics for
  the same surface verify at Phase 3 (.47). PE mmap at
  0x5000000 has 1.5 MB slack past the v5.10.40 brk
  extension to `0x4EAD000`, no resize.
- **cc5_macho_arm (cross)**: ~590 KB at v5.10.40; mmap
  size bumped 0x4E8C000 → 0x4EAD000 to absorb the new
  LEXID region.
- **cc5_aarch64 native (Pi)**: **567,672 B** at v5.10.40
  (native self-host fixpoint b == c verified on pi
  2026-05-11). Cross-built variant from the x86 host is
  582,088 B; the cross/native byte delta is the standard
  "first-bootstrap differs from native rebuild" shape, b
  == c on the native side is the authoritative check.

> Per-slot byte-delta history is in `CHANGELOG.md` (source of truth)
> and `completed-phases.md` (closed cycles). This section tracks
> CURRENT sizes only; closeout passes consolidate per-slot detail
> into the cycle summary at `completed-phases.md`.

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

Current at v5.11.0 (v5.11.x cycle OPEN). Cross-host gates wire through `~/.ssh/config`
hosts: **pi = Linux aarch64**, **ecb = Apple Silicon Mach-O arm64**,
**cass = Windows 11 PE32+**.

- **check.sh**: ~66/66 PASS (typed-simd ABI arc added the
  `simd_overload_dispatch.tcyr` gate at v5.10.39; .38 added
  `f64v2_byval_param.tcyr`; .37 added `f64v4_byval_return.tcyr`;
  .34 added `tls_early_data_status.tcyr`).
- **`tests/tcyr/*.tcyr`**: ~135 files (v5.10.x added at least
  9 gates: tls_early_data_status, simd, simd_typed_wrappers,
  f64v2_byval_return, f64v4_byval_return, f64v2_byval_param,
  simd_overload_dispatch, plus REAL TYPE SYSTEM gates).
- **`tests/scyr/*.scyr`**: 1 soak harness (alloc_pressure).
- **`tests/smcyr/*.smcyr`**: 1 smoke harness (compile_minimal).
- **`fuzz/*.fcyr`**: 5 harnesses.
- **`benches/*.bcyr`**: 14 benchmarks.
- **Release toolchain**: 10 bins.
- **Stdlib**: 79 modules (v5.9.0 niyama 1.0.1 fold; v5.10.34
  sandhi 1.1.0 → 1.3.3 refresh fold +1,194 lines).
- **api-surface**: ~2873 entries (from `docs/api-surface.snapshot`
  generated artifact; was 2792 at v5.9.42 close).

Per-slot test-gate detail in `CHANGELOG.md`. Older suite-growth
narrative in `completed-phases.md`.

## In-flight

**v5.10.x cycle CLOSED at 50 slots (2026-05-11).** THREE
completed arcs (typed-simd ABI 11 phases, REAL TYPE SYSTEM 5
phases, struct-byval ABI 3 phases) plus a compile-time-perf
miniarc (.40+.41, 2.7× total compile speedup) plus the TLS
contract pin (.42) plus the roadmap-extension open-issues sweep
(.43/.44/.48 close all 4 v5.10.42-audit issues) plus the
v5.10.49 PE premise-debunk (15-slot phantom closed) plus the
v5.10.50 closeout pass anchor the cycle. **v5.11.0 opens next.**

1. **REAL TYPE SYSTEM** 5-phase arc (v5.10.1 - v5.10.26) — type
   annotations parsed + stored, call-site arg checking, overload
   dispatch on param-type fingerprint, return-type recording,
   sum-type rewriting. Unblock for the typed-simd value-form param ABI.

2. **Typed-simd value-type ABI** 11-phase arc (v5.10.28 - v5.10.39) —
   f64v2 + f64v4 as primitive value types with end-to-end XMM/V
   register-pair param + return ABI across x86 SysV / aarch64 NEON /
   cx bytecode / macho-arm64 / Win64 PE (retptr-style fallback).
   Closed with parser-side `&IDENT → _ptr` overload dispatch and
   the full `lib/simd.cyr` value-form/pointer-form surface (50 fns).

3. **v5.10.40 + v5.10.41 compile-time-perf miniarc** —
   length-bucketed LEXID dedup at v5.10.40 cut lex 603→59 ms
   (10.2×); fn_start_hash in fixup DCE at v5.10.41 cut fixup
   213→76 ms (2.8×). End-to-end gain: total compile-time
   **1037 → 387 ms (2.7×)** on cc5 self-compile. v5.10.0
   profile-guided "compile-time wins" held entry now realised
   across both phases.

4. **v5.10.42 TLS hook-surface contract** — new
   `docs/development/lib-tls-contract.md` pins the
   invariant layer for the `lib/tls.cyr` ↔ `lib/sandhi.cyr`
   surface that stabilised across .40/.13/.21/.27/.34.

5. **v5.10.43 + v5.10.44 open-issues sweep — stdlib
   Str/cstr disambiguation** — v5.10.42-ship roadmap-
   extension audit promoted 4 open issues into v5.10.x
   slots; .43 + .44 close the two Medium-severity bugs:
   - v5.10.43: `str_split` sep-treated-as-pointer (live
     entire v5.x cycle). Runtime dispatch on `sep < 256`
     preserves all 21+ stdlib byte-int callers byte-
     identical AND fixes Str-sep semantics.
   - v5.10.44: `exec_*` family was cstr-only with no
     docstring contract; argonaut-blocking on Str pushes.
     Parallel `_str` family added (`exec_vec_str` /
     `exec_capture_str` / `exec_env_str`); runtime
     dispatch rejected because both Str/cstr are
     pointers and 8+-char cstrs fail the heuristic.

6. **v5.10.45 + v5.10.46 + v5.10.47 struct-by-value ABI
   arc (CLOSED)** — pin re-scoped at v5.10.44 ship after
   empirical premise check showed the original "macOS arm64
   struct-byval" pin was mis-framed: the underlying bug
   (16B int-class struct returns lose the high half) was
   live across ALL backends, not just Mach-O. User authorized
   expansion into a 3-phase arc.
   - **.45**: x86 SysV via rax+rdx pair, `_STR_SID(S)`
     carve-out preserving Str's legacy handle-shape.
   - **.46**: aarch64 AAPCS64 X0+X1 pair (covers Linux
     + Mach-O via shared ABI). Verified on pi (exit=42).
   - **.47**: Cross-host smoke matrix established. Verified
     on pi (exit=42), ecb (exit=42 codesigned), local x86
     (tcyr 14/14). cass compile-clean; runtime exit-code
     gated on v5.10.49 PE exit-code propagation fix. Win64
     ABI deviation from strict MS x64 spec acknowledged
     (cyrius-internal-ABI uses rax+rdx pair; closed-system
     no-consumer-impact rationale documented).

Additional in-cycle work: TLS early-data surface completion at
v5.10.34 (TLS_EARLY_DATA_NOT_SENT/REJECTED/ACCEPTED + accessors);
sandhi 1.1.0 → 1.3.3 refresh fold at v5.10.34; doc-health.md
ledger scaffolded at v5.10.34; vidya wrap-up pass paired with
v5.10.39 (retro file + 3 gotcha entries + 3 feature entries).

**Cycle stats (final, v5.10.50 close)**:
- cc5: 753,768 B at v5.10.0 → **804,472 B at v5.10.50** (+50,704 B, +6.7%)
- cc5_aarch64_native: ~470 KB at v5.10.0 → **587,048 B at v5.10.47**
- cc5_macho_arm: ~510 KB at v5.10.0 → **606,644 B at v5.10.47**
- cc5_win: ~530 KB at v5.10.0 → **701,440 B at v5.10.47**
- api-surface: 2792 → **2876 entries** (+3 v5.10.44 `_str` fns)
- New `lib/simd.cyr` (50 public fns)
- New `docs/development/lib-tls-contract.md` (v5.10.42)
- New `tests/tcyr/str_split.tcyr` (v5.10.43, 35 sub-asserts)
- New `tests/tcyr/process_exec_str.tcyr` (v5.10.44, 6 sub-asserts)
- New `tests/tcyr/struct_byval_return.tcyr` (v5.10.45, 14 sub-asserts)
- **Compile time 1037 → 387 ms (2.7×) across .40 + .41 miniarc**
- 3 locname-staleness surfacings (v5.10.35 fixed ptyp 93-130; v5.10.39
  fixed the duplicate at ptyp 89-91 missed by .35); install.sh
  `cp -L` same-file collision discovered (workaround manual; fix
  pinned for v5.10.50 closeout)

**Closeout pinning**: roadmap has v5.10.45 - v5.10.50 slotted for
the remaining v5.10.x work. Full v5.10.x retro at
`../../../vidya/content/cyrius/field_notes/compiler/retros/v510x.cyml`.

## Recent shipped (one-liner per release)

v5.10.x cycle through 2026-05-11 (CLOSED at v5.10.50):

- **v5.10.50** — cycle closeout. 11-step CLAUDE.md closeout pass
  all green: mechanical (3-step + bootstrap + check.sh 66/66 +
  heapmap 96/0/0), judgment (heap-map clean, 34 dead-fn floor
  unchanged, no x86 leaks, refactor noted), compliance (security
  + downstream all pinned to released tags), doc sync (vidya
  retro back-half + 3 features.cyml entries). One cleanup
  finding: `bootstrap/verify.sh` `stage1/` path fixed. cc5
  byte-identical. v5.11.0 opens next.
- **v5.10.49** — Win64 PE `println` + exit-code premise-debunk
  (no code change). Empirical re-test shows both pinned pieces
  work today; the "broken" claims were a 15-slot chat-side
  test-wrapper bug (`cmd /c "& echo %errorlevel%"` parse-time
  expansion). Memory pin saved. v5.10.47 struct-byval Phase 3
  cass retroactively confirmed exit=42 (arc 4/4, not 3/4).
  cc5 byte-identical to v5.10.48.
- **v5.10.48** — Defensive sweep + parser cosmetic limits (7-item
  bundle). Bare `return;` synthesizes `return 0;`; enum-ident
  array sizes accepted in BOTH PARSE_ARRAY + PARSE_GVAR_ARR;
  parse_fn.cyr AARCH64 defensive guards; `run_script` file_exists
  guard. Premise-checked 3 items as already-resolved/out-of-
  scope. cc5 +1,384 B. 4 open issues from the v5.10.42 audit
  now all closed.
- **v5.10.47** — struct-by-value ABI arc Phase 3: cross-host smoke
  + PE retptr verify (arc CLOSED). 4-target matrix: x86 (tcyr
  14/14), pi (exit=42), ecb (exit=42 codesigned), cass (compile=0;
  runtime gated on .49). Win64 ABI deviation acknowledged. cc5
  byte-identical to v5.10.45/.46.
- **v5.10.46** — struct-by-value ABI arc Phase 2: aarch64 AAPCS64
  X0+X1 pair-return. v5.10.45 ERR_MSG stubs replaced with real
  LDUR/STUR X0,X1 encodings + LDR/STR X9 deep-frame fallback.
  Linux aarch64 + macOS arm64 covered (shared ABI). pi runtime
  verify: struct Point 7+35 repro → exit=42 ✓. cc5 byte-identical
  to v5.10.45 (aarch64-only change). cc5_aarch64_native +4,960 B.
- **v5.10.45** — struct-by-value ABI arc Phase 1: x86 SysV
  int-class pair-return. `_cur_fn_ret_pair` flag set by rough-scan
  when fn returns 9-16B non-Str struct; PARSE_RETURN emits
  `mov rax,[&v+0]; mov rdx,[&v+8]`; caller `asv_pair` path mirrors
  the layout. `_STR_SID(S)` carve-out preserves Str's handle-mode.
  14 sub-asserts. Phase 2 (.46 aarch64) + Phase 3 (.47 cross-host)
  pinned.
- **v5.10.44** — `lib/process.cyr` `exec_*` Str/cstr ambiguity fix
  (parallel `_str` family). Three new public verbs (`exec_vec_str`
  / `exec_capture_str` / `exec_env_str`); each extracts `str_data`
  on the way into execve's argv. Runtime dispatch rejected (cstr
  8+-char literals fail the pointer heuristic). Closes argonaut-
  blocking `2026-05-10-process-exec-str-cstr-ambiguity.md`. 6
  sub-asserts. api-surface 2873 → 2876.
- **v5.10.43** — `lib/str.cyr` `str_split` separator-byte-comparison
  fix (runtime byte/Str dispatch). Closes the long-standing issue
  filed at `docs/development/issues/2026-05-03-str-split-sep-
  treated-as-pointer.md`. `sep < 256` → byte path; `sep >= 256` →
  Str fat-pointer path with multi-byte sep support. cc5 byte-
  identical (lib-only). 12 test groups / 35 sub-asserts.
- **v5.10.42** — `lib/tls.cyr` hook-surface contract audit. New
  `docs/development/lib-tls-contract.md` (~230 LOC) formalises 24
  public verbs (availability / connect-fused / connect-staged /
  I/O / hook-time config / session resumption / session cache cbs /
  0-RTT / soft-deprecated `tls_dlsym` escape hatch). cc5 byte-
  identical (doc-only); 3-step fixpoint clean.
- **v5.10.41** — Fixup phase optimization. `fn_start_hash` at
  `0x110000` (8192 slots × 2 B; Knuth golden-ratio multiplicative
  hash) reusing free 232 KB gap; replaces two O(N²) DCE byte-scan
  linear scans. fixup 213→76 ms (2.8×), total 510→387 ms (1.32×).
  aarch64 fixup has no DCE — x86-specific (PE backend reached too).
- **v5.10.40** — Lex dedup hot-path optimization. Length-bucketed
  linked-list at `0x4E8C000..0x4EAD000` (132 KB brk extension);
  16384-entry table; first-occurrence-wins canonical offset. lex
  603→59 ms (10.2×), total 1037→510 ms (2.0×). Cross-host verified
  on pi (native fixpoint b == c at 567,672 B) / ecb / cass.
- **v5.10.39** — typed-simd overload dispatch (`f64v2_add(&x, &y)`
  routes to `_ptr` sibling) + `lib/simd.cyr` value-form/pointer-form
  surface (50 fns). Typed-simd ABI arc CLOSED at Phase 11.
- **v5.10.38** — f64v2 + f64v4 value-form param ABI (Phase 9-10);
  0x1282000 fn_param_simd_mask; cyrius-internal SysV SIMD split-counter.
- **v5.10.37** — f64v4 (32-byte packed-double) value type; pair-quad
  return ABI across all backends.
- **v5.10.36** — aarch64 V0 NEON register-class return for f64v2
  (replaced X0+X1 GPR pair).
- **v5.10.35** — `PARSE_SIMD_EXT` locname-staleness fix + `_SIMD_STASH`
  helper; threat-model + fncall-abi doc refresh.
- **v5.10.34** — `lib/tls.cyr` early-data status accessors; sandhi
  1.1.0 → 1.3.3 fold; doc-health.md ledger introduced.
- **v5.10.33** — `lib/simd.cyr` typed wrappers (first downstream
  consumption of typed-simd ABI Phase 5 XMM0 return).
- **v5.10.32** — typed-simd ABI Phase 5: x86 SysV XMM0 single-register
  return for f64v2 (replaced int-class rax/rdx pair).
- **v5.10.31** — typed-simd ABI Phase 4: Win64 PE retptr-style fallback.
- **v5.10.30** — typed-simd ABI Phase 3: aarch64 NEON V0 return.
- **v5.10.29** — typed-simd ABI Phase 2: x86 SysV f64v2 return path.
- **v5.10.28** — typed-simd ABI Phase 1: f64v2 as primitive value type.
- **v5.10.27** — REAL TYPE SYSTEM closeout consolidation.
- **v5.10.26** — Phase 5: sum-type rewriting + derive-friendly.
- **v5.10.25** — `_str` / `_int` / `_cstr` overload pattern.
- **v5.10.22-24** — overload dispatch refinement.
- **v5.10.21** — TLS surface filling.
- **v5.10.20** — P(-1) sweep.
- **v5.10.13-19** — TLS Phase + agnosys cascade close + `_init_cyrius_lib`
  hardening.
- **v5.10.1-12** — REAL TYPE SYSTEM Phases 1-4; agnosys 1.1.12 cascade;
  vyakarana cap unblock; net/tls Phase 1; `_check_shadow_lib`.
- **v5.10.0** — per-phase compile-time profiling (`CYRIUS_PROF=1`).

(Slot-by-slot detail in `CHANGELOG.md`. Earlier cycles in
`completed-phases.md`.)

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
