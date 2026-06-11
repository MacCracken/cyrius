# Cyrius Development Roadmap — v6.1.x (active minor)

**Scope** — the **current active minor only** (v6.1.x), opened at the
v6.0.x → v6.1.0 clean cut (2026-06-08). This is the slot-pinning
working artifact. The rest of the v6.x cycle (framing, budgeting,
minors v6.2.x → v6.5.x, and the now-closed v6.0.x summary) lives in
[roadmap_6.md](roadmap_6.md); items beyond the cycle (v7.0+
aspirations, unpinned language refinements, speculative work) live in
[roadmap-future.md](roadmap-future.md).

> **Reading order**: this file (active minor) →
> [roadmap_6.md](roadmap_6.md) (rest of the v6.x cycle) →
> [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, v6.2.x → v6.5.x, the closed v6.0.x
  summary).
- [roadmap-future.md](roadmap-future.md) — long-term watching list,
  including the **v6.1.x carry-in** candidates surfaced by the v6.0.91
  closeout judgment passes.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.1.x — Backend Codegen Multi-Arc

**Theme**: position-independent codegen + dynamic-link migration +
v6.0.x back-compat retirement, plus the v6.0.x → v6.1.x carry-ins
(stdlib carve, closeout judgment-pass cleanups). Multi-arc minor.

Per user direction 2026-05-19: "defer larger items for multi-arc
in 6.1.x".

**Minor window**: stated at arc open and open to change
([[feedback_minor_window_at_arc_open]]) — see the slot estimate below.
Premise-check each arc at slot entry ([[feedback_premise_check_at_slot_entry]]);
cross-arch propagation is mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS
self-host verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]).

---

## Pinned slot sequence

Organized 2026-06-08 (user direction): **primary expected items first**,
in the order *quick housekeeping → backend-refactor prep → PIE codegen →
stdlib carve*, packed **one sub-arc per release** (user: "per-sub-arc
releases"). Slot numbers are nominal — premise-check each at slot entry;
the HELD / open-arc items (below the primary block) are **not pinned** and
land only on consumer pressure or explicit user direction.

| Slot | Item | Phase |
|---|---|---|
| **v6.1.0** ✅ | Clean cut — roadmap split (`roadmap.md`/`roadmap_6.md`) + full docs sweep + `build/` cleanup (prior-major slot `cc3 → cc5`) + benchmark-every-release gate | shipped |
| **v6.1.1** ✅ | Back-compat symlink drop (install symlinks + `cbt/core.cyr` cc5 fallback + repl shim) | A — housekeeping |
| **v6.1.2** ✅ | `aarch64 EADDRA_IMM` >4095 fix (low+hi adds + movz/movk guard; pi+ecb verified) | A — housekeeping |
| **v6.1.3** ✅ | POSIX `*at()` family + bare-name peers + aarch64 ESYSXLAT collision fix (repaired pre-existing native-aarch64 `sys_stat`) | A — housekeeping |
| **v6.1.4** ✅ | Backend prep — `_TARGET_*` decl move + `_emit_fmt` hoist to common/runtime.cyr (`_entry_base` stays per-arch — not a dup) | B — backend prep |
| **v6.1.5** ✅ | DCE mark-and-sweep consolidation (`_dce_hash_lookup` + `_dce_host_fn` hoist to `common/runtime.cyr`; 4 probe-blocks → 1, 4 host-scans → 1; −51 LOC, cycc −752 B; logic-preserving) | B — backend prep |
| **v6.1.6** ✅ | PIE codegen x86_64 — `--pie`/`CYRIUS_PIE=1` ships working **userland** PIE executables (ET_DYN, RIP-relative; 169/169 tcyr run as ASLR'd PIE + new gate). Reused the ~80%-prebuilt `shared`/object `_IS_OBJ` machinery (premise correction) + fixed `EVADDR_X1`. Kernel-PIE ELF = follow-on (needs AGNOS `--pie` boot harness). | C — PIE |
| **v6.1.7** ✅ | **Packed (user-directed)**: Windows COM/DXGI `.rdata` corruption fix (ai-hwaccel consumer bug — m128 array-padding base mismatch between `FIXUP` + `_pe_layout`; GPU-confirmed 60→42) **+** kernel-PIE ELF wrapper (`EMITELF64_KERNEL` ET_DYN+p_vaddr=0, the deferred v6.1.6 pickup) | bug-bandwidth + C |
| **v6.1.8** ✅ | PIE codegen aarch64 (Sub-arc B — `adrp`/`add` via the proven Mach-O PIC path; ET_DYN; full tcyr corpus exit-parity on pi). **Completes the PIE arc on both arches.** | C — PIE |
| **v6.1.9** ✅ | `.gnu.hash` migration + drop SysV `.hash` (Sub-arc C) — `EMITELF_SHARED` emits single-bucket `.gnu.hash` + `DT_GNU_HASH` matching `lib/dynlib.cyr::_gnu_hash_lookup` (loader was already gnu-hash-only; the SysV table was dead weight). x86-only; cycc byte-identical; cass/pi/ecb self-host | C — PIE / dynlink |
| **v6.1.10** ✅ | **TS AST children-list allocator fix** (Phase D prereq) — the parser built a corrupt AST for nested lists (`RESERVE` didn't advance `used` → call-args/block/object/JSX sub-lists stomped each other; verified empirically). Restructured all value builders to deferred collect-then-contiguous-write (`TS_CST_PUSH`/`FLUSH`) + the `<T,>` trailing-comma parse fix + `cycc --emit-js` self-validating AST-walk (kind-S-expr; check.sh gate 87, proven to catch a re-broken allocator). x86-Linux-only; cycc +79 KB; cass/pi/ecb green. | D — frontend emit (prereq) |
| **v6.1.11** ✅ | TS/TSX → JS emit (`cycc --emit-js`) — AST-driven emitter on the corrected AST: type-strip + JSX→`h(...)` (pragma `CYRIUS_JSX_PRAGMA`, default `h`, + standalone prelude) + ESM passthrough with type-only export pruning. Consumer `app.tsx` emits valid runnable JS (node --check + parse-ts round-trip + stub-DOM run); gate does emit→round-trip. x86-only; cycc +24.7 KB. **Phase D mini-arc complete.** | D — frontend emit |
| **v6.1.12** ✅ | **agnos `getenv` HIGH-sev fix, packed with Phase D edges** (user "hotfix + small pack"): `lib/io.cyr` `getenv()` guards its 8 KB `/proc/self/environ` reader behind `#ifndef CYRIUS_TARGET_AGNOS` (it was compiled past the agnos early return → agnoshi #PF; verified it's `.bss` static, not a stack frame — `.bss` −8,208 B). **+** `cyrius build --target=js` CLI wrapper over `cycc --emit-js`. **+** indented JS output. **+** fixed a pre-existing bug: every `for`/`for-of`/`for-in` header emitted invalid JS (`;;`/`; of `/`; in `; silent since .10/.11) + gate guard + fixture coverage. pi/ach/ecb byte-identical; cass deferred (Defender quarantine-lock, box reset pending). | agnos fix + D edges |
| **v6.1.13** ✅ | **agnos `fnptr` HIGH-sev fix (agnoshi)** — `lib/fnptr.cyr` `fncall0..8` had no `CYRIUS_TARGET_AGNOS` asm branch → every indirect call returned 0 on agnos → null allocator vtable → agnsh #PF after its banner. Added the agnos+x86 SysV branch in-place to each `fncallN` (the REAL root cause that .12's getenv fix was a layer off from). Emit A/B-verified (0→1 `call rax`); cycc flat (stdlib-only); ecb/cass green. | bug bandwidth |
| **v6.1.14** ✅ | **agnos `argc()`/`argv()` HIGH-sev fix (bannermanor)** — the init-rsp capture (`call _agnos_capture_rsp`) sat in the entry epilogue, after `PARSE_PROG`, so any top-level statement that shifted rsp made it record a stale (zeroed) pointer. Moved the emission up to after `EMIT_GVAR_INITS` / before `PARSE_PROG` (mirrors the x86-macOS `_macho_capture_args` placement). Emit A/B-verified; cycc flat (`_TARGET_AGNOS`-gated); ecb/cass green. The issue's "Bug 2" (nested `syscall(60)` no-op) closed as consumer-side (agnos exit=0, not 60; use `SYS_EXIT`). | bug bandwidth |
| **v6.1.15** ✅ | **TS/TSX→JS emitter `async`-on-wrong-node fix (secureyeoman/yeo-cy-test)** — an `async` function/method/arrow enclosing a nested arrow emitted `async` on the inner arrow + dropped it from the owner → bare `await` → invalid JS. Single ambient pending-async slot was consumed after body parse; the first nested arrow stole it. Added `TS_PS_TAKE_ASYNC`/`TS_AST_SET_ASYNC` (capture-at-entry, apply-after-push) across all 5 body-before-consume sites + emit-js regression scanner. cycc +512 B (TS frontend); ecb/cass green. | bug bandwidth |
| **v6.1.16** ✅ | **Windows-correctness pack (ai-hwaccel / sakshi / patra), 3 items.** (1) **`cycc_win` missing from x86_64 release tarball** since v6.0.50 — `release.yml` shipped cycc_aarch64 but never cycc_win → pinned-release `cyrius build --win` failed (sakshi CI blocker); added the WIN cross-build + bin/ copy + PE32+ verify (mirrors v5.8.2 cycc_aarch64 fix). (2) **PE `syscall(<var>,…)` silently miscompiled** (HIGH) — literal-only reroute let a var-number syscall emit Linux `0F 05` (silent no-op on Windows → all sakshi logging dropped); added `EPE_SYSCALL_DYNAMIC` runtime `cmp`/`jne` dispatch by arity → the literal `E*_PE` path, unknown→`-38`, unroutable-arity→hard error; aarch64/cx stub; T1–T4 verified on cass. (3) **`lib/sync.cyr`** portable mutex (futex/SRWLOCK/spinlock) decoupled from thread.cyr; `sync.tcyr` green on all 4 targets. cycc +2,552 B; ecb+cass `SELFHOST_OK`. | consumer pack |
| **v6.1.17** ✅ | **sakshi 2.2.8 fold + PE `nanosleep(35)` routing (user-directed)** — `ENANOSLEEP_PE` (`src/backend/x86/emit.cyr`) completes the 6.1.16 PE var-syscall dispatch (nanosleep was the one routable-arity gap → returned `-38`, forcing sakshi's Windows clock-calibration busy-spin); reads the `timespec` (sec@+0/nsec@+8) → `Sleep(ms)`, wired into both the literal `sc_num==35` case + the `EPE_SYSCALL_DYNAMIC` argc==3 candidate + aarch64 `--strict` stub. Folded sakshi 2.2.8 (compile-time `SAKSHI_LEVEL` threshold). PE-only — x86 cycc==cycc unchanged; ecb+cass `SELFHOST_OK`; new `tests/win/nanosleep_pe.cyr` → exit 42 on real Windows. **Also unblocked the PE release tarball** (a 6.1.16 regression, never released): 6.1.16's `EPE_SYSCALL_DYNAMIC` made a var-number syscall of an *unroutable arity* a HARD COMPILE ERROR, and `lib/fs.cyr`'s `syscall(SYS_GETDENTS64, …)` (arity 5) made the wrapper refuse to compile → `build-windows-tarball.sh` failed. Softened to an honest stack-balanced `-38`/`-ENOSYS` + warning (the treatment unknown *numbers* already get); `tests/win/var_syscall_arity_pe.cyr` guards it. cycc +1,736 B total. | consumer fold + bugs |
| **v6.1.18** ✅ | **Windows directory-listing port + sakshi 2.2.10 fold.** `dir_list`/`is_dir`/`dir_walk` now work on Windows (were empty/`-38` stubs since .17): four kernel32 reroutes `0xF016-0xF019` (FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW) driven from a new self-contained `lib/fs_win.cyr` (`#ifdef CYRIUS_TARGET_WIN`; getdents64 path `#ifndef`'d out). EXPLICIT approach (not transparent getdents64 routing — fd is not a path, would overload the fd slot). PE-only — x86 cycc==cycc unchanged, aarch64 `--strict` stubs added; new `tests/win/dir_list_pe.cyr` → exit 42 on real cass; ecb+cass `SELFHOST_OK`. Folded **sakshi 2.2.10** (2.2.9 timespec P3 fix + 2.2.10 single-path rdtsc, busy-spin dropped). Closes `issues/2026-06-09-windows-dir-listing-findfirstfile-port.md`. cycc +2,248 B. | bug bandwidth (Windows pillar) + fold |
| **v6.1.19–.24** ✅ | TLS native-default arc (brk→mmap chunked alloc, cert path-build, macho `*at()`, native default flip, async arena-leak fix, `alloc_init` idempotency) + LSP hover/keyword dive. _(See CHANGELOG; bayan pushed back behind this band.)_ | TLS/alloc/LSP |
| **v6.1.25** ✅ | **bayan distfile carve** — json/toml/cyml/csv/base64/bigint/u128 → bayan 1.0.0, folded `lib/bayan.cyr` (`bayan_*` + aliases); `#derive` deserialize emits `bayan_json_*`; tls_native `bigint`→`bayan`. **+ `cyrius vet`/`deny` ELF-emission fix** (mis-wired to `cybs`→`cyaudit`). | E — stdlib carve |
| **v6.1.26** ✅ | **ganita distfile carve** — matrix + linalg (`mat_*`) + the 13 advanced math fns SPLIT from `lib/math.cyr` (transcendental + fibonacci/binomial) → ganita 1.0.0, folded `lib/ganita.cyr` (`ganita_*` + aliases). stdlib `math` keeps primitives (constants/basic-ops/gcd/lcm/parse/polyfills). cycc unchanged. **Closes Phase E** — stdlib is primitives-only. | E — stdlib carve |
| **v6.1.27** ✅ | **binary output cap 2 MB → 16 MB** (phylax hit it pulling bayan). `output_buf` relocated heap-top (`S+0x4D9D000`) + resized; heap → `0x5D9D000`; cap checks → 16777216. Virtual-only cost (no memset). Two-step self-host + ecb/cass green; a 2.06 MB binary compiles (old cap would error). | bug bandwidth (infra) |
| **v6.1.28** ✅ | **`lib/sys.cyr`** system-introspection (uname/sysinfo/is_root + `system_*`) carved off agnosys's `src/syscall.cyr`; +`SYS_SYSINFO` floor const. **+ bare directory-family dep-resolution fix** — `"unicode"` now resolves `lib/unicode/*.cyr` (fixes downstream niyama consumers / chakshu). cycc unchanged; ecb/cass green. | lib + dep-resolver |
| **v6.1.29** ✅ | **`fdlopen_init_trusted`** — setuid-safe foreign-dlopen (HIGH-sev; closes the shakti proposal). Resolves root-owned `/usr/lib/cyrius/dlopen-helper`, `lstat`-verifies (uid 0 / not symlink / not world-writable), never `$HOME`, fails closed `-9`. install.sh root-system-helper + threat-model trust row. Unblocks shakti 0.6.3. cycc unchanged; ecb/cass green. | security (consumer-blocking) |
| **v6.1.30** ✅ | **x86-macOS argv prologue** — reserve r15 (regalloc cap 5→4) + park `mov r15,rsp` at the output landing + `args_macos` reads r15, all gated `_TARGET_MACHO==1`. The Intel-Mac tools now read argv (verified on `ach`). Phase 1 of the x86-macOS-usable arc; env/arch-detect/cycc-finding/issue-1/packaging remain. ecb/cass/ach SELFHOST_OK. | x86-macOS pillar (ach) |
| **v6.1.31** ✅ | **Ed25519 server certs for native TLS** — fold sigil 3.7.9 (Ed25519 X.509 leaf-cert parse: sig-algid/SPKI/`_x509_verify_link`, RFC 8410). Root cause was sigil's ECDSA/RSA-only `x509_parse`, not the TLS layer. Closes the sit-filed issue; verified native loopback + OpenSSL `s_client` interop. cycc unchanged; ecb/cass green. | consumer bug (sit → sigil fold) |
| **v6.1.31** ✅ | **Ed25519 server certs for native TLS** (sigil 3.7.9 fold) — root cause was sigil's `x509_parse` (ECDSA/RSA-only), NOT the TLS layer; sigil 3.7.9 adds Ed25519 X.509 leaf-cert parse (RFC 8410, PureEd25519). Loopback + OpenSSL `s_client` interop verified. cycc unchanged. | TLS (sit-filed) |
| **v6.1.32+** ⏳ | **Phase F — security hardening tail** (the 2026-06-10 deep-dive review). Packed releases absorbing the urgent findings before cycle-close — see the Phase F detail + slot estimate below. | F — hardening |
| *(bug bandwidth)* | **kernel-PIE ELF (AGNOS KASLR — consumer-gated; `--pie` boot harness filed upstream)**, x86-macho self-compile (HELD), cyim regex unblock, x86-macOS arc tail (env / arch-detect / cycc-finding / issue-1 / packaging). (macho-arm `*at()`/stat ESYSXLAT ✅ fixed v6.1.20 + archived; Windows deps `--lock` hash ✅ done v6.0.85) | absorbed into bug bandwidth |

**Why this order** (user lead choice = housekeeping → backend-prep → PIE):
the housekeeping items (Phase A) are small, ready, and have concrete
pressure (a filed `EADDRA_IMM` bug, kriya's `*at()` ask, the overdue
rename-symlink retirement). The backend-refactor carry-ins (Phase B) are
**prep for PIE** — the `_emit_fmt` hoist needs the `_TARGET_*` decls moved
first, and PIE adds new fixup modes to the same `emit.cyr`/`fixup.cyr`
files, so consolidating them before PIE keeps the codegen clean. PIE
(Phase C) is the pinned theme; it lands on the cleaned backend, x86 first
to validate the fixup-table shape, then aarch64, then the `.gnu.hash`
dynamic-link cleanup. **TS/TSX → JS emit (Phase D)** is pulled up ahead of
the carve (user 2026-06-08) — it has active consumer pressure
(SecureYeoman `yeo-cy-test`) and the expensive part (the parser) already
exists, so it earns a primary slot before the carve. The bayan/ganita
carve (Phase E) is the last primary block — concrete (standing pin) but
independent of the backend work, so it tails the codegen + emit arcs.

---

## Slot detail

### Phase A — quick housekeeping (v6.1.1 → v6.1.3)

#### v6.1.1 — Back-compat symlink drop

The v6.0.0 rename grace period ends at the first v6.1 working patch.

- Drop `~/.cyrius/bin/cc5 → cycc` + `~/.cyrius/bin/cyrc → cybs`
  symlinks from `scripts/install.sh` release path.
- Drop `cbt/core.cyr` lookup fallback (compiler-binary search
  tries cycc only; no fallback to cc5).
- Same shape for cross-arch symlinks (`cc5_aarch64 → cycc_aarch64`,
  `cc5_win → cycc_win`).

#### v6.1.2 — aarch64 `EADDRA_IMM` 12-bit mask (>4095) fix

Latent, pre-existing (filed at the .91 closeout, **not** a .88–.90
regression). `add x0,x0,#imm12` masks the operand to 12 bits, so a
byte-array literal `> 4096` elements silently corrupts (at offset 4096,
`4096 & 0xFFF == 0` → no-op add → byte lands at `&var+0`). Reached only
via the peephole's correct `disp >= 4096` legacy fallback; doesn't bite
in-tree today (no brace-literal byte array > 4096). Fix: a `> 4095` path
(chunked add-imm12 or movz/movk + add-reg). Changes aarch64 codegen →
cross-OS self-host reverify (pi/ecb). Issue:
[`issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md`](issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md).

#### v6.1.3 — POSIX `*at()` family

`openat`, `mkdirat`, `unlinkat`, `fstatat`, `linkat`, `renameat`,
`fchmodat`, `utimensat` + `AT_FDCWD` / `AT_SYMLINK_NOFOLLOW` /
`AT_REMOVEDIR` / `AT_SYMLINK_FOLLOW` consts + bare-name peers
(`sys_lstat`, `sys_link`, `sys_rename`). Pulled out of v6.0.62 as its
own slot (2-arch parity + cross-arch tests — not a "small"). kriya M2
surfaced the gap; agnos likely co-consumer. Proposal:
[`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).

### Phase B — backend-refactor prep (v6.1.4 → v6.1.5)

The .91 closeout judgment-pass carry-ins, sequenced **before PIE** because
they clean the backend PIE then extends. Detail in
[roadmap-future.md](roadmap-future.md) "v6.1.x carry-in".

#### v6.1.4 — `_TARGET_*` decl move + `_emit_fmt`/`_entry_base` hoist

The v6.0.89 first-bite left `_emit_fmt`/`_entry_base` byte-identical-
duplicated in `x86/fixup.cyr` + `aarch64/fixup.cyr`. The hoist to a shared
home is blocked by the single-pass parser + include order (`_emit_fmt`
reads `_TARGET_MACHO`/`_PE`/`_ELF64_KERNEL` as bare-identifier globals
declared only in `emit.cyr` → a hoist there is a hard "undefined variable"
exit). **Prereq (this slot)**: move the `_TARGET_*` declarations into
`runtime.cyr`/`tokens.cyr` first (verified feasible at closeout — no early
reader; all assignments happen after every include), then hoist. Structural
multi-backend change → ecb/cass/pi self-host reverify. Also reclaim the
FREED scalar holes (the v6.0.88 `ret_patches` ~2 KB hole + the v6.0.47
holes) for any new compiler-state scalar rather than growing the band.

#### v6.1.5 — DCE mark-and-sweep consolidation

The hash build/seed/propagate/sweep/undef-fn pass is duplicated across the
two `fixup.cyr` backends, and within each the open-addressing hash-probe +
the linear host-fn scan are each written twice. A shared `_dce_hash_lookup`
+ `_dce_host_fn` collapse 4 probe-blocks → 1 and 4 host-scans → 1 (arch
delta is only `E8/E9`+`DECODE_LEN` vs `BL/B` 4-byte stride). Changes
emitted helper code → cross-OS self-host reverify.

### Phase C — PIE codegen (v6.1.6 → v6.1.8)

The pinned theme — position-independent codegen, landing on the cleaned
backend. **Consumer note**: PIE's first consumer is AGNOS full-binary
KASLR (Option A in agnos's `2026-05-11-kaslr-scope.md`); AGNOS v1.28.0
ships data-only KASLR that doesn't need PIE, so this arc may land ahead of
live consumer pressure. Premise-check AGNOS pull at slot entry.

#### v6.1.6 ✅ — PIE codegen x86_64 (Sub-arc A)

**Shipped.** `--pie` / `CYRIUS_PIE=1` emits a working **userland** position-
independent executable (ET_DYN, `lea [rip+disp32]` throughout), validated by
running all 169 `.tcyr` as ASLR'd PIE + a new `_pie_exec_gate` (check.sh 86).
**Premise correction**: PIE was ~80% pre-built and dlopen-proven via the
`shared`/object `_IS_OBJ` path — so this widened the gate + fixed the one ungated
site (`EVADDR_X1`) rather than greenfield, and the fn-ptr/vtable "awkward case"
was a non-issue. Non-PIE byte-identical. Full implementation findings appended to
[`proposals/2026-05-11-pie-support.md`](proposals/2026-05-11-pie-support.md).

**Backlog (deferred from v6.1.6, still v6.1.x):**

- **Kernel-PIE ELF for AGNOS KASLR** (the original Option-A motivation). The
  codegen is done + proven via userland PIE; only the ELF *wrapper* remains — an
  `ET_DYN` + multiboot2 variant of `EMITELF64_KERNEL` with a real `_start` +
  `p_vaddr=0` (the kernel path is `ET_EXEC` at fixed `0x100000` today). **Gated on
  an AGNOS `--pie` boot harness** (two-boot QEMU+OVMF base-diff exists in agnos CI,
  wireable to `--pie`) — NOT shipped blind per "never trust a checkmark over running
  it on hardware." AGNOS (v1.43.5) isn't pulling (data-only KASLR shipped v1.28.0;
  full-binary PIE-KASLR deferred/unscheduled there). Lands on the harness or explicit
  user direction; rides the bug-bandwidth/consumer-gated tail until then.

#### v6.1.7 — PIE codegen aarch64 (Sub-arc B)

`adrp` + `add` on aarch64 replacing the 4-chunk `movz`/`movk` absolute-address
sequence. The x86 sub-arc (v6.1.6) validated the fixup-table + `_IS_OBJ` gate
shape; aarch64 `_IS_OBJ` (`src/backend/aarch64/emit.cyr`) covers only object mode
(`kmode==3`) today — this slot adds the shared/PIE `adrp`/`add` conversions. (The
`EADDRA_IMM` fix shipped @ v6.1.2, so the `add`-imm path is already >4095-safe.)
The kernel-PIE ELF wrapper (above) may land alongside this slot if the AGNOS
harness is ready.

#### v6.1.8 — `.gnu.hash` migration + dynamic-link cleanup (Sub-arc C)

The long-term `.gnu.hash` pin deferred at v5.6.38 (no consumer pressure)
earns its slot here — modern dynamic loaders prefer `.gnu.hash`'s Bloom
filter pre-check over the SysV `.hash` chain walk, and PIE binaries going
through `dlopen` / symbol resolution see the measurable difference. Drop
SysV `.hash` once `.gnu.hash` is in place.

### Phase D — TS/TSX → JS emit (v6.1.10 → v6.1.11) ✅

Pulled into the primary block ahead of the carve (user 2026-06-08). The
Cyrius TS/TSX front-end **parses** real-world TS/TSX cleanly today
(interfaces, generics + default type params, `?.`/`??`, async/await, enums,
JSX, a full React component) but has **no emit** — `--lex-ts` / `--parse-ts`
validate only. The ask: a `cycc --emit-js <file.tsx>` (or `cyrius build
--target=js`) codegen stage walking the existing AST — strip type
annotations / interfaces / type aliases, lower JSX → `createElement`-style
calls (configurable pragma), pass ESM through. **Single-file emit only; a
bundler is out of scope.** The expensive part (the full-fidelity TS/TSX
parser) already exists — this is codegen on top. Active consumer pressure
(SecureYeoman `yeo-cy-test`, which hand-maintains a parallel `web/app.js`
stopgap today). ✅ **SHIPPED** (v6.1.10/.11; `cyrius build --target=js` v6.1.12;
`async` fix v6.1.15). Issue (resolved, archived):
[`issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md);
full write-up in [roadmap-future.md](roadmap-future.md).

> **Framing note**: this is a *non-machine-code output target* for an
> assembly-up compiler. Premise-check the scope at slot entry — if it
> proves larger than one slot, ASK for the shape rather than re-slotting
> ([[feedback_no_unilateral_scope_decisions]]).

### Phase E — stdlib carve (v6.1.25 → v6.1.26) ✅

The bayan/ganita distfile carve — the second half of the stdlib
clean-slate (the mabda fold shipped @ v6.0.45). After the carve, stdlib
stays primitives-only so bare-metal consumers (v6.2.x RISC-V / firmware)
don't drag the data offshoots into kernel objects. Math primitives + regex
stay stdlib. [[project_bayan_ganita_carve_arc]]. **Shipped .25/.26** —
pushed back from the original .19/.20 by the user-directed sakshi/PE pack
(.17/.18) and the TLS/alloc/LSP band (.19–.24).

#### v6.1.25 — bayan distfile carve ✅

Extract `json` / `toml` / `cyml` / `csv` / `base64` / `bigint` / `u128`
from stdlib into the **bayan** sibling repo + folded `lib/bayan.cyr`
(`bayan_<module>_*` + back-compat aliases).

#### v6.1.26 — ganita distfile carve ✅

Extract `matrix` / `linalg` / advanced math from stdlib into the
**ganita** sibling repo + folded `lib/ganita.cyr` (`ganita_<module>_*`).
Closes Phase E — stdlib is primitives-only.

---

## Phase F — security hardening tail (v6.1.32+)

The 2026-06-10 deep-dive review
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)
— 40 adversarially-verified findings, 0 refuted, across 13 issues) surfaced a
cluster of "loud failure silently turned into silent failure" bugs plus authn
gaps in the now-default native TLS stack. Per user direction 2026-06-10, the
**urgent set lands in the v6.1.x tail as packed releases before cycle-close**
("bigger hardening chunk first"); the lower-severity / prerequisite items spread
to v6.2.x bug-bandwidth and the later minors where they gate work ("urgent now,
rest spread"). Patch count is not a constraint (v6.0.x ran to 91). Nominal
packing — premise-check at slot entry, pack per
[[feedback_one_bug_one_complete_fix]]:

| Pack | Items | Issues |
|---|---|---|
| **F1 — silent-failure + dep-injection** | `_vec_die`/`_hm_die` recursion (CVE-22), `output_buf` cap unenforced on aarch64/PE/kernel (CVE-23), silent-bad-input (CVE-31), `check.sh` exit-masking (CO-02), x86-opt passes unguarded on aarch64/cx (CO-03) · `deps --verify`/`--lock` shell injection (CVE-14 — auto-runs every build), git arg-injection (CVE-15), absolute-path include (CVE-16) | [live-silent-failure-regressions](issues/2026-06-10-live-silent-failure-regressions.md) · [deps-resolver-injection-class](issues/2026-06-10-deps-resolver-injection-class.md) |
| **F2 — TLS authn hardening** | chain-verify gaps: pathLen/EKU/keyUsage/revocation (CVE-17), connected-but-unverified default + `host==0` hostname skip (CVE-18), post-handshake NST/KeyUpdate false-EOF (CVE-30); entropy fail-weak cyrius-side: ws uninit mask + raw-`/dev/urandom`→`getrandom` routing (CVE-19 — the AGNOS getrandom syscall is filed upstream) | [tls-chain-verification-gaps](issues/2026-06-10-tls-chain-verification-gaps.md) · [tls-post-handshake-false-eof](issues/2026-06-10-tls-post-handshake-false-eof.md) · [entropy-failweak-paths](issues/2026-06-10-entropy-failweak-paths.md) |
| **F3 — memory-safety parity** | locals 256-cap (CVE-24), `_sb_grow` OOM (CVE-25), `alloc_agnos` size guard (CVE-26), PE import-registry caps (CVE-27); aarch64 atomics barriers + unfenced vtable publish (CVE-28) | [memory-safety-parity-gaps](issues/2026-06-10-memory-safety-parity-gaps.md) · [unreviewed-dimensions](issues/2026-06-10-unreviewed-dimensions.md) |

**Spread to v6.2.x+ / later minors** (NOT the v6.1.x tail, per "rest spread"):
release/trust-chain integrity (CVE-20/21 — v6.2.x bug-bandwidth + v7 trust-story),
verification coverage (VR-01…04 — VR-03 differential corpus gates v6.4.x), the
blind bench harness (PF-01 — gates v6.4.x/v6.5.x, see
[roadmap_6.md](roadmap_6.md)), the monomorphization substrate (AR-01/CO-01/AR-02 —
v6.3.x phase-0), thread-stack guards (CVE-29 — v6.2.x), and the v7 readiness gates
(LEGAL-01 licensing, diagnostics). The audit cadence + CVE-09…13 re-file is tracked
at [overdue-security-audit-cve-tail](issues/2026-06-10-overdue-security-audit-cve-tail.md)
— **this deep-dive IS the overdue full audit**.

**Cycle-close after Phase F**: per [cycle-discipline.md](cycle-discipline.md), the
final patch folds any deps that GA'd during the window (sandhi/sigil/etc.), then
v6.2.0 opens.

---

## Bug-bandwidth items (not pinned)

Real v6.1.x candidates that ride the **bug-bandwidth** budget rather than
the planned arc (user 2026-06-08: "keep tail as bug bandwidth") — each
lands in an open bug-bandwidth slot on consumer pressure or explicit user
direction ([[feedback_no_unilateral_scope_decisions]]), not as a pinned
planned release.

- **Kernel-PIE ELF for AGNOS KASLR** (deferred from v6.1.6 — see Phase C). The
  RIP-relative codegen is done + proven via userland PIE, and the `ET_DYN`
  `EMITELF64_KERNEL` wrapper (`p_vaddr=0`, `e_entry=0xA8`) **shipped v6.1.7** —
  structurally validated but never boot-tested. **Consumer-gated** on an AGNOS
  `--pie` boot harness to validate (won't ship blind). The harness ask is now
  **filed upstream**:
  `agnos/docs/development/issue/2026-06-10-cyrius-pie-boot-harness-ask.md` (the
  kaslr-scope Option-A "once cyrius ships PIE" blocker is now met). AGNOS isn't
  pulling yet (data-only KASLR @ v1.28.0). [[project_v616_bugband_then_full_pie]].
- **x86-macho cycc self-compile** (layer-6 miscompile) — **HELD** (Apple
  Intel EOL); arm64-macOS is the supported macOS target. Revisited as a
  working item, not a blocker.
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md),
  [`issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md`](issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md).
- **x86-macOS usable-toolchain arc tail** (Phase 1 = argv prologue shipped
  v6.1.30) — remaining `ach`-gated layers: env reading (`HOME`/uname),
  the wrapper's aarch64 arch-default on macOS (detect x86 on Intel),
  cycc-finding, issue-1 native miscompile (tools ship cross-built until fixed),
  packaging. [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md).
- **macho-arm `*at()`/stat ESYSXLAT mappings** — ✅ **fixed v6.1.20 + archived**
  (`newfstatat 262→fstatat64 470`, `linkat 37→471`, `renameat 38→465`, Darwin
  `stat64` struct; `utimensat`→ENOSYS since Darwin has no such syscall). Repaired
  `sys_stat` (broken on arm64-macOS since v6.0.41). Kept here only to mark it
  resolved — issue archived, no longer a candidate.
- **Cyim regex unblock** (mabda C6) — consumer-gated; land when cyim
  updates + re-tests against v6.x.
- **`cyrius deps --lock` Windows-portable hash** — ✅ **DONE @ v6.0.85**
  (`_sha256sum_file` uses `certutil -hashfile` behind the Windows path in
  `cbt/deps.cyr`); kept here only to mark it resolved — no longer a candidate.

---

## Actual shape (v6.1.x)

The original ~11-planned / ~21-budget estimate is **long past** — v6.1.x has
shipped 31 releases and counting, which is expected, not a breach: minors flex
long (**v6.0.x ran to 91**) and per user direction 2026-06-10 *"no worries about
patch size, just hardening and adding features."*

| Phase | Releases |
|---|---|
| A — housekeeping | v6.1.1–.3 |
| B — backend-refactor prep | v6.1.4–.5 |
| C — PIE codegen + `.gnu.hash` | v6.1.6–.9 |
| D — TS/TSX → JS emit | v6.1.10–.12, .15 |
| agnos-target HIGH-sev fixes | v6.1.12–.14 |
| Windows pillar | v6.1.16–.18 |
| TLS/alloc/LSP | v6.1.19–.24 |
| E — stdlib carve (bayan, ganita) | v6.1.25–.26 |
| infra / security | v6.1.27–.31 |
| **F — security hardening tail** (deep-dive) | **v6.1.32+** |
| Bug bandwidth (x86-macOS arc tail · kernel-PIE · cyim · HELD) | ongoing |

Phase F closes the minor (urgent deep-dive findings packed in, then the dep-fold
cycle-close → v6.2.0). Window open to change
([[feedback_minor_window_at_arc_open]]).
