# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.
>
> **Consolidated 2026-06-08 (v6.1.4):** the per-patch session-close log
> (104 entries, ~5,600 lines back to v5.x) + the stale v6.0.4-frozen
> structured sections were pruned — that detail is canonical in
> [`CHANGELOG.md`](../../CHANGELOG.md) (per-patch) and
> [`completed-phases.md`](completed-phases.md) (arc retrospective). This file
> now holds only the **active cycle** + current state.

## Current state

| | |
|---|---|
| **Version** | **6.2.33** (v6.2.x cycle — **Platform Expansion**; **AGNOS stdlib syscall-ABI pack** — closes `2026-06-18-stdlib-native-agnos-abi-fs`. The descent (MUD) agnos port re-surfaced the class: **patra 1.12.1→1.12.2** (flock #59 / lseek #58 from the peer, fdatasync→whole-FS sync #12, dropped hardcoded Linux `SYS_GETRANDOM=318`) + **sakshi 2.4.0→2.4.1** (precedence agnos branch — `CYRIUS_ARCH_X86` is predefined even on agnos so the Linux branch silently won → open#2/close#3/exit#60 corruption; `_sk_open` namelen+AO map; BSD socket/sendto guarded), both released + re-folded byte-identical. **`lib/io.cyr` xlseek/xflock** complete the portable x* wrapper set (xflock centralizes the per-target flock number; xlseek is peer-portable). sigil premise-checked OUT of scope. **Lib-only — `src/` untouched → cycc byte-identical.** See [roadmap_6.md](roadmap_6.md)) |
| **cycc** (x86_64 ELF) | **1,071,936 B** (FLAT @ 6.2.33 — lib-only slot, `src/` untouched, so cycc self-hosts byte-identical AND is seed-derivable from `bootstrap/asm`) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | **624,552 B** (rebuilt @ 6.2.30 version-bump — version-string stamp only; backend untouched; pi SELFHOST_OK) |
| **cycc-native-aarch64** (aarch64-native, tracked) | 787,248 B (refreshed @ 6.1.8 — PIE-enabled; **NOTE: predates the 6.2.10–.32 compiler changes (incl. the .29 aarch64 fixes) — refresh via `cyrius pulsar` when next on ARM hw; not a gate, the pi self-host rebuilds from source (✅ SELFHOST_OK @ .32)**) |
| **cycc_win** (PE32+ cross) | **845,824 B** (rebuilt @ 6.2.30 version-bump — version-string stamp only; PE backend untouched; cass SELFHOST_OK) |
| **cyrius-lsp** (language server) | 531,688 B |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | **21,066 B** (@2026-06-20 — grew from 12,344 B to compile ALL of `src/main.cyr`; **seed→cybs→cycc now reproduces build/cycc byte-identical** — the CVE-20 self-host restoration. cybs(main.cyr)=gen1, gen1(main.cyr)=gen2=build/cycc, fixpoint holds) |
| **seed** (`bootstrap/asm`, root of trust) | **29,024 B** (@2026-06-20 — +8 B from the cybs string-lexer NUL-terminator fix that completed the self-host; regenerated as cybs(asm.cyr), Rust-seed-verified via `bootstrap/verify.sh`, `bootstrap/SHA256SUMS` updated) |
| check.sh gates | **92/92 + the D7 boot gate** (+2 @.29 — `_cli_cross_compile_gate` (CLI cbt/cyrius.cyr → PE/Mach-O/aarch64, the .25-class gate) + `_fuzz_harness_gate` (cyrius fuzz → exit 0 + "0 failed"); both also per-PR ci.yml steps. + the D7 boot gate post-step @.28) |
| aarch64 native tcyr | **189 pass / 0 fail / 0 xfail / 1 skip** (@.29 VR-01 — the aarch64-native CI job runs the FULL tcyr corpus on real arm64. It surfaced a stale-native-fork + 9-bug debt; **all fixed in-slot** (`2026-06-19-aarch64-tcyr-failures.md` RESOLVED), gate HARD + GREEN. `math_pack_integration` skip = x86-only f64_sin; pi-verified) |
| sigil fold | **3.9.2** (@6.2.31 — luks raw `getrandom` syscall → `_sigil_random_fill` portable boundary so sigil/cyrsign cross-compile to PE; @6.2.25 — `sha384_init_into` alloc-free + `ecdsa_p256_verify_der` `raw_sig`→stack for the TLS arena/flat-RSS fix) |
| stdlib fold | agnosys 1.4.3 (**PINNED — upstream repo decomposed → agnodrm; no further bumps**) · **sandhi 1.6.8** · sankoch 2.4.4 · niyama 1.0.5 · **bayan 1.0.2** · ganita 1.0.1 · **patra 1.12.2** · yukti 2.2.6 · vani 0.9.5 · **sigil 3.9.2** · **mabda 3.4.2** · **sakshi 2.4.1** · **yantra 1.0.0** (**@.30 — mabda 3.3.0→3.4.2 (array textures + cubemaps, BC tiled arrays, F64_*→MABDA_F64_* math-collision fix, render-target 64 KiB VA-map align + per-context RT VA bump); @.26 — mabda 3.2.14→3.3.0 (asset/png + native/wgpu backends); + yantra 1.0.0 NEW fold — UI/E2E testing (WebDriver/Appium/CDP), OPT-IN, requires net/ws/bayan/sandhi/tls/sakshi/sigil dep chain**) |
| tests | **190** `.tcyr` (+`tls_native_entropy_vtable` @.28 — the D5 entropy-hook dispatch/short-fill/default; `naked_fn_attribute` updated @.28 to a real `asm{iretq}` ISR) · 15 `.bcyr` · 5 `.fcyr` |
| stdlib | **99** `lib/*.cyr` · 79 programs · api-surface **5059 fns** (+2 @.33 — `io::xlseek/3` + `io::xflock/2`, 0 removals; was 5057 @.32 +2 agnos syscall fns, 5055 @.30) |
| heap | `output_buf` 16 MB @ `S+0x4D9D000` (relocated heap-top, 2MB→16MB @ .27); `file_map` relocated to freed `0x71A000` band @ .35; 4 per-fn local tables relocated to heap-top `0x5D9D000`+ (4×128 KB, 16384 slots) @ .40 (CVE-24); brk-final `0x5E1D000` (~94.1 MB virtual, +512 KB @ .40) |
| agnos gate | **7/7** (+probe **x*** @.26 — io.cyr xopen/xstat/xunlink/xgetdents emit-inspect: valid agnos ELF + getdents #29, no Linux-217; +probe 1e @.23 — fs dir-listing getdents #29 + AO_DIRECTORY 0x800) |
| bench (every-release gate) | self_compile **512 ms** @ 6.2.33 (flat vs .30's 508 ms, within jitter; x86 cycc **1,071,936 B** unchanged — lib-only slot, no perf delta) |

> **Handoff (2026-06-20):** **v6.2.33 CUT — AGNOS stdlib syscall-ABI pack**
> (closes `2026-06-18-stdlib-native-agnos-abi-fs`). The descent (MUD) agnos port
> re-surfaced this class. Fixed at the source in two ecosystem libs + completed
> the `lib/io.cyr` x* wrapper family — **lib-only, `src/` untouched → cycc
> byte-identical 1,071,936 B.** **patra 1.12.2:** file.cyr agnos `#ifdef` (flock
> #59 / lseek #58 from the peer, no redefine; fdatasync→whole-FS sync #12);
> wal.cyr dropped hardcoded Linux `SYS_GETRANDOM=318` (collided w/ agnos peer #45,
> redundant on Linux → peer-provided everywhere). **sakshi 2.4.1:** root cause
> `CYRIUS_ARCH_X86` is predefined on EVERY x86 build incl. agnos, so agnos
> silently took the Linux branch (open#2/close#3/exit#60 → getpid/spawn/undefined
> log corruption); added a precedence `#ifdef CYRIUS_TARGET_AGNOS` branch
> (write#1/open#7/close#6/exit#0), `_sk_open` namelen+`O_*→AO_*` map, BSD
> socket/sendto guarded (UDP transport → -1, keeps stderr). Both **released +
> re-folded byte-identical**. **`xlseek`/`xflock`** added to `lib/io.cyr` (issue
> ask #1 — wrapper set now complete; `xflock` centralizes the per-target flock
> number, `xlseek` peer-portable); `agnos_xsys_probe` exercises both. cyrlint
> message updated — deliberately NOT flagging `SYS_LSEEK`/`SYS_FLOCK`/
> `SYS_GETRANDOM` (now peer/wrapper-portable → would false-positive on the fixed
> patra). **sigil premise-checked OUT of scope** (agnos build clean; only
> `sys_access` = Linux-disk LUKS). **VERIFIED:** check.sh **92/92** · cycc
> self-host byte-identical 1,071,936 B · cross-OS **pi/ecb/cass SELFHOST_OK** ·
> bench self_compile 512 ms · api-surface 5057→**5059**. User pushes/tags after CI.
>
> **Handoff (2026-06-20):** **v6.2.30 CUT — CVE-21 trust-chain integrity, part 1**
> (CVE-20/21 is a 2-release arc; part 2 = .31 detached signing + the seed→cybs→cycc
> reconstruction CI). Entirely CLI / scripts / docs / fold — `src/` untouched, **cycc
> byte-identical** (1,071,936 B). Shipped: installers fail-closed on the `.sha256`
> (`install.sh` warn→err + require sidecar, portable `_verify_checksum`; `ci.sh` +
> `install.ps1` gained verification; `cyriusly` fetches from `/refs/tags/<v>/`, not
> main; tag-clone-fatal); `cbt/deps.cyr` records the resolved **commit SHA** per
> tagged dep (written first in `cyrius.lock`) + refuses force-pushed tag / tampered
> cache (worktree≠HEAD) / corrupt pin line, gating the module copy; all GitHub
> Actions SHA-pinned; **the `cyrius port`/`init` scaffolded-CI templates hardened**
> (verify + pin — the review's lone P1, re-opened the hole one layer down). + CVE-20
> doc reframe (trust root = committed `build/cycc`) + RM-02 threat-model fix (closes
> the last RM item) + **mabda 3.3.0→3.4.2** fold (it moved 3.4.1→3.4.2 mid-slot via a
> sibling cut). `cmd_deps_verify` lock-read 8 KB→64 KB. **Adversarial review:
> 25 agents, 8 confirmed + all fixed, 13 dismissed.** VERIFIED: check.sh **92/92** +
> boot gate · cycc self-host byte-identical · CLI cross-compiles PE/Mach-O/aarch64 ·
> cross-OS **pi/ecb/cass all SELFHOST_OK** · self_compile 508 ms · api-surface
> 5035→5055. User cuts/tags after CI.
>
> **Handoff (2026-06-19g):** **v6.2.29 CUT — VR-01/VR-02 verification fold** (no
> `src/` change — tests/gates/CI; cycc FLAT). **VR-02:** `cyrius fuzz` → a check.sh
> gate (`_fuzz_harness_gate`) + a ci.yml step (was vestigial, in no gate).
> **CLI cross-compile gate** (`_cli_cross_compile_gate` + ci.yml step): pipes
> `cbt/cyrius.cyr` through PE/Mach-O/aarch64 + asserts magic — the EXACT .25-class
> hole (check.sh's cross-OS only self-hosted cycc, never the CLI). **VR-01:** the
> aarch64-native CI job now runs the FULL `.tcyr` corpus on REAL arm64 (first
> on-hardware tcyr coverage beyond self-host+funcgate). It measured a real
> aarch64 debt: the language was effectively broken on ARM. **The WHOLE batch was
> fixed IN-SLOT** (the gate's first red CI run tied it to .29): root cause was the
> stale `main_aarch64_native.cyr` fork (124 lines behind, zero annotation handling →
> bayan/derive "unexpected enum") — fixed by splicing the cross fork's pass-1/pass-2
> dispatch wholesale; + 9 backend bugs (x86-leak class: unguarded x86 asm in `.text`,
> missing ESYSXLAT pipe/flock/faccessat renumbers, `clock_gettime`, 2 x86-exact test
> bugs); + **`fdlopen`** via `#naked` setjmp/longjmp (earning `#naked` register-param
> support — `parse_fn.cyr` gates the param-store + relaxes the .28 no-params guard).
> bayan u128 fix source-first → **bayan 1.0.2** released + re-folded. **Validation
> lesson: I first validated with the CROSS compiler, which masked the native-fork
> bug — always run the NATIVE binary ARM users run.** Gate now HARD + GREEN: **189
> pass / 0 fail / 0 xfail / 1 skip** on pi; check.sh **92/92** + boot gate; cycc
> 1,071,888→**1,071,936 B** (+48, the `#naked` gate). **NEXT pinned: .30 CVE-21 →
> deps-modules → RISC-V.**
>
> **Handoff (2026-06-19f):** **v6.2.28 CUT — bare-metal target formalization,
> RUNTIME HALF** (closes the .27+.28 arc). A premise-check overturned the .27
> belief that `#naked` was a partial feature: cyrius has had inline asm (`asm{}` +
> the `iretq` mnemonic) all along — only the aarch64 `eret` mnemonic was missing.
> **`#naked` completion:** (1) a DCE force (`src/main.cyr`, `if (_naked_pending==1)
> { dce_reachable=1; }`) so an address-taken ISR is never DCE-stubbed-and-bypassed;
> (2) the param/return guards were aborting SILENTLY — `ERR_MSG(...,strlen(msg))`
> called `strlen` (in `lib/string.cyr`, NOT compiler-included) → undefined-fn
> segfault before the message; rewrote to literal+byte-count; (3) the 1-line aarch64
> `eret` mnemonic. Real ISRs now writable: `#naked fn isr() { asm { iretq } }` /
> `{ asm { eret } }`. **D5** kernel-freestanding TLS entropy: `_tn_tx_rand` +
> `tls_native_set_entropy` + `_tn_rand_bytes` leaf over all **11** getrandom sites
> (hs13×8/hs12×3 — roadmap's "12" was stale); new `tls_native_entropy_vtable.tcyr`.
> **D7** the capstone — `scripts/qemu-boot-gate.sh` REALLY BOOTS the kernel under
> QEMU (`boot_serial.cyr` → "AGNOS" on serial) + ELF64 shape-checks both arches;
> wired into check.sh AND a new `bare-metal-boot` CI job. **D6** entry/load-base VA
> exposed via the triple build (gate-asserted both arches); base-settability
> deferred (`issues/2026-06-19-kernel-load-base-settable.md`). **Adversarial review
> (18 agents, 6 confirmed, all folded):** the P1 was that the boot gate wasn't wired
> into ANY workflow + CI had `qemu-user-static` not `qemu-system-x86` — the exact
> placebo the gate exists to kill; fixed. **check.sh 90/90 + boot gate (real
> "AGNOS"); cross-OS pi/ecb/cass; cycc self-hosts byte-identical 1,071,888 B (−16);
> bench 520 ms; api-surface 5035 (+1).** `#naked` issue resolved (parts 1+2; only P3
> cosmetic residuals remain). The bare-metal arc (.27 frontend + .28 runtime) is
> COMPLETE. Next pinned: .29 verification fold → .30 CVE-21 → deps-modules → RISC-V.
>
> **Handoff (2026-06-19e):** **v6.2.27 CUT — bare-metal target formalization,
> FRONTEND HALF** (a 2-release arc, split contiguous after a premise-check; the
> runtime/boot half is .28). **D1** `--target=<arch>-bare-metal-elf` triple
> (x86_64 + aarch64): a named front-end over the ad-hoc `kernel;`/kmode — the CLI
> injects `CYRIUS_KERNEL=1` (a new env read in main.cyr/main_aarch64.cyr forcing
> `kernel_mode` at S+0x18FCA0, so no source `kernel;` is needed; default unset →
> byte-identical) + `CYRIUS_ELF64_KERNEL=1` + `_skip_deps` (freestanding: no
> userland-stdlib auto-prepend). Byte-identical to the source `kernel;` mechanism.
> **D2/D4** the output is a clean no-libc ELF (single PT_LOAD, no PT_INTERP/
> DYNAMIC, both arches). **D3** `#naked` fn-attribute (frameless ISR emit; token
> **133**) — skips prologue/epilogue/frame on x86 (−48 B) + aarch64 (−24 B),
> mirrored across all 6 main_* forks (annotation-fork-desync 4th instance).
> **Adversarial review (19 agents, 8 confirmed) — all 3 P1s fixed:** (1) token
> 128 **collided with the f64v_dot SIMD builtin** → renumbered #naked to 133; (2)
> a DCE-stubbed #naked fn leaked `_naked_pending` → the next fn emitted frameless
> + **SIGSEGV** → reset in the DCE-stub path; (3) `--target=aarch64-bare-metal-elf`
> **silently built an x86 kernel** when cycc_aarch64 absent → `set_arch` +
> hard-error. **`#naked` is the prologue-skip ATTRIBUTE, a building block — NOT a
> finished ISR feature**: cyrius has no inline asm (so a real ISR body ending in
> iretq/eret isn't writable yet) + the param/return guards don't fire on
> DCE-stubbed fns → both **FILED** (`2026-06-19-naked-fn-safety-and-inline-asm.md`)
> + **PINNED to .28** (where the boot gate + AGNOS IDT exercise real ISRs).
> **check.sh 90/90; cross-OS pi/ecb/cass; cycc self-hosts byte-identical
> 1,071,904 B (+2,216 feature growth); bench 518 ms.** Next: .28 (bare-metal
> runtime half). **Also added to the v6.2.x roadmap before RISC-V:** a
> deps-modules/groupings item (stdlib → standard deps).
>
> **Handoff (2026-06-19d):** **v6.2.26 CUT — agnos-fs ABI substrate + mabda
> 3.3.0 + yantra 1.0.0 (new stdlib fold).** Closes the cyrius-native half of
> `2026-06-18-stdlib-native-agnos-abi-fs`: agnos `sys_*` carry an explicit byte
> length + reorder flags, so a raw Linux-shaped `sys_open(path,O_RDONLY,0)` lands
> O_RDONLY in `namelen` → silent ABI miscompile off Linux. New portable
> **`xopen`/`xstat`/`xunlink`/`xgetdents`** in `lib/io.cyr` bridge the agnos ABI
> once (mirror `file_open`), `#ifdef`-gated per target (agnos namelen /
> Linux+macOS passthrough / Win guarded stub — the guard wraps the BLOCK, the
> v6.2.25 audit_walk lesson). cyrlint getdents rule (informational) + the new
> **`_agnos_xsys_gate`** emit-inspect (valid agnos ELF + getdents-#29, no
> Linux-217 leak; kept separate from the exit-60 gate since the io.cyr-pulling
> probe is big enough to coincidentally match a whole-binary exit-60 scan).
> **Premise-check:** the "~58 sites" are mostly vendored (upstream) / Linux-only
> / already-fixed (fs.cyr @.23) → preventative cure, not a migration. Adversarial
> review: substrate ABI + guards CLEAN; 2 cyrlint rule bugs (FSYS_ alias
> false-neg + message self-match) caught + fixed. **mabda 3.3.0** folded
> (asset/png + native/wgpu; deps unchanged). **yantra 1.0.0 NEW fold** — the
> UI/E2E testing lib (WebDriver/Appium/CDP), vendored byte-identical via `cyrius
> distlib` at the 1.0.0 tag, self-contained, OPT-IN (requires net/ws/bayan/
> sandhi/tls/sakshi/sigil dep chain — references sigil's SIG_ALG_ED25519
> constant); verified compiles+runs via `cyrius deps`; registered in cyrius.cyml.
> **check.sh 90/90 (+`_agnos_xsys_gate`); cross-OS pi/ecb/cass; cycc
> byte-identical 1,069,688 B; api-surface 4939→5034 (+95, 0 removals); bench
> 517 ms flat.** Next pinned: .27 bare-metal target formalization.
>
> **Handoff (2026-06-19c):** **v6.2.25 CUT — `tls_native` server-ctx
> arena/flat-RSS fix (full-depth) + sigil 3.9.1 + `cyrius audit` semantics fix.**
> A long-running native-TLS server leaked every accepted connection on the
> global bump (ctx + handshake/record buffers + keysched secrets + transcript
> hash + traffic keys + tickets) → unbounded RSS. Fixed: `TLS_CTX_OFF_ALLOC`
> stashes an `lib/alloc.cyr` Allocator (0=global) via `tls_native_new_server_in`,
> and `_tn_alloc`/`_tn_alloc_a`/`_tn_ks_alloc`/`_tn_arena` choke-points route
> ~95 per-connection allocs across conn/keysched/lowlevel/hs13/hs12 (+ the x509
> leaf via `x509_cert_alloc_into`); pure within-call scratch went stack-local
> (`record_seal`'s per-record 16 KB, HKDF info/th, transcript clone, p384 sig).
> `tls_accept_alloc_in(a, …)` exposes it → a server loop `arena_allocator(cap)`
> once + `reset_via(a)` per connection = flat RSS. `a==0` byte-identical (full
> TLS suite green). **Adversarial review (ultracode) caught 8 missed-routing
> leaks** the first conversion pass left (incl. the per-record `record_seal`) +
> 2 more found in sweep (x509, p384); **zero use-after-reset hazards.** Proven
> by hermetic `tls_native_server_arena_flat_rss.tcyr` (252 asserts: arena_used
> → base after every reset_via, constant per-connection footprint). sigil 3.9.1
> folded (`sha384_init_into` + ecdsa `raw_sig`→stack). **`cyrius audit` fixed**
> (was wired to the uninstalled `~/.cyrius/bin/check.sh` → `script not found`):
> default is now the **project sweep** (fmt/lint/docs/tests/bench, any repo);
> `--internal`=check.sh; `--internal=platform-check`=+cross-OS. New
> `audit_doc_walk` parses cyrdoc's stdout summary (per-fn markers → stderr).
> **check.sh 89/89; cross-OS self-host pi/ecb/cass green; cycc byte-identical
> 1,069,688 B; api-surface 4939 (+7).** Next slot: user's call.
>
> **Handoff (2026-06-19b):** **v6.2.24 CUT — TLS server-handshake contract
> (`tls_accept`) + cross-target SYS_* dedup + cyrlint agnos-ABI rule + mabda
> 3.2.14.** Follow-up to .23 (user: "more issues + deferred items"). **(1)
> `tls_accept` server wrapper** in lib/tls.cyr — backend-dispatched mirror of the
> client trio; native (40-byte shim sandhi hand-rolls) + libssl (in-memory DER via
> `*_ASN1`/`d2i_AutoPrivateKey`). An **adversarial review of the untestable libssl
> path caught 2 real bugs** (unguarded `SSL_CTX_use_PrivateKey` null-ptr + EVP_PKEY
> leak; `EVP_PKEY_free` wasn't resolved in `_tls_init`). **(2) SYS_* dedup** —
> net.cyr's 5 colliding socket nums → `NSYS_*` (x86-canonical kept for ESYSXLAT),
> fs.cyr `SYS_GETDENTS64`→`FSYS_`; `SYS_ACCEPT`/`SYS_SHUTDOWN` kept (peer-missing,
> never collided — over-renaming them broke `net_v6_connect.tcyr`, caught + fixed).
> Since consumers now resolve bare names to the peer's **aarch64** numbers, the
> **macho ESYSXLAT** gained the aarch64 socket family→Darwin (198→97 etc.) — the
> v6.2.x line's first aarch64-codegen change (+352 B cycc_aarch64; x86 cycc
> byte-identical). **(3) cyrlint rule** flags raw `sys_open(<path>,<literal>,…)` —
> comment-aware + an **informational note** (non-gate-failing: ~40 pre-existing
> host-only sites are legit). **(4) mabda 3.2.14** fold. **VERIFIED:** check.sh
> **89/89**; x86 self-host byte-identical; agnos gate 6/6; cross-OS pi/ecb/cass;
> api-surface 4909→4932 (0 removals); self_compile 522 ms. **NOTE:** the macho
> socket-xlat is encoding-verified + adversarially reviewed + compile/ecb-self-host
> green, but full **net-on-Darwin runtime** is sandhi's acceptance (check.sh's ecb
> gate doesn't exercise sockets). **POST-CUT FUNCGATE FIX (pi-verified):** the
> aarch64 funcgate caught that the fs.cyr `FSYS_GETDENTS64=217` dedup emitted an
> **untranslated 217 on aarch64-Linux** (the branch had socket+macho-getdents
> renumbers but never `217→61`), so `cyrius lib sync`'s dir-walk vendored nothing.
> Self-host-blind (cycc never dir-walks → check.sh's pi gate missed it). Fixed by
> adding `getdents64 217→61` to the aarch64-Linux ESYSXLAT; **verified on real pi**
> (dir-walk exit 99 fixed / 0 broken; two-step self-host s2==s3 byte-identical) +
> qemu-aarch64. LESSON: the dir-walk path needs a real aarch64 run (qemu or pi),
> NOT just the self-host gate. **PINNED → v6.2.25:** the tls_native server-ctx
> **arena/RSS-leak** (full-depth arena + sigil source patch + re-fold). **NEXT after
> .25:** the ecosystem-dedup arc (ERR_* namespacing + xopen wrappers + vendored
> SYS_* migrations). **user pushes/tags after CI.**
>
> ---
>
> **Handoff (2026-06-19):** **v6.2.23 CUT — agnos cross-target stdlib pack + 5-lib
> dependency fold.** Reviewed the latest filed issues; user picked the agnos-ABI
> cluster + sysinfo. Three stdlib fixes + the fold; all `#ifdef`-guarded or
> stdlib-only → **cycc x86 byte-identical (flat 1,069,688 B)**. **(1)**
> `tls_native_set_ca_system` opened CA bundles with raw `sys_open(path,0,0)` (Linux
> shape) → on agnos the `0`=namelen=0 → zero roots → **all verifying HTTPS dead on
> agnos**; routed through io.cyr `file_open` (Linux/macOS byte-identical). **(2)**
> `fs.cyr` `dir_list`/`is_dir` agnos branch: getdents **#29** (3-arg) + sovereign
> dirent §4.2. **A P0 was caught by the ultracode adversarial review** (read vs the
> agnos kernel source): the first cut opened dirs with `flags=0`, but the kernel's
> `ext2_open()` rejects dir inodes — only **`AO_DIRECTORY` (0x800)** routes to
> `ext2_open_dir()` → the getdents-capable fd. Without it dir_list was empty +
> is_dir always 0, invisible to self-host AND a compile-only gate. Fixed; gate
> probe **1e** now emit-inspects getdents 0x1d + the 0x800 flag. **(3)** sysinfo
> ask was **~90% pre-existing in `lib/sys.cyr` (v6.1.28)** — closed the gap (agnos
> `SYS_UNAME=34`/`SYS_SYSINFO=35` consts, `sys_geteuid`, portable `sys_gettid`).
> **Fold:** sandhi 1.6.8 · patra 1.12.0 · sigil 3.9.0 · mabda 3.2.12 · sakshi 2.4.0.
> mabda folded from the **3.2.12 TAG** (working dist was dirty v3.2.14-WIP). sigil
> 3.9.0's new `luks_write_keyfile` referenced `O_EXCL` (undefined on agnos) → added
> to io.cyr's agnos `O_*`. **agnosys PINNED 1.4.3** (repo decomposed → agnodrm).
> **VERIFIED:** check.sh **89/89**; x86 + pi self-host byte-identical; agnos gate
> **6/6**; cross-OS **ecb/cass/pi** green; api-surface 4567→**4909** (0 removals);
> self_compile 515 ms (flat). **STILL OPEN:** the `2026-06-18-stdlib-native-agnos-abi-fs`
> structural asks (`xopen` wrappers + cyrlint rule + ~58 raw-sys_open sites incl.
> sigil luks) — issue kept active. **user pushes/tags after CI.**

---

**Prior v6.2.x handoffs (.22 ← .6) trimmed 2026-06-19** — per-slot narrative is
canonical in [CHANGELOG.md](../../CHANGELOG.md); arc retrospectives in
[completed-phases.md](completed-phases.md). state.md keeps only the active head
(the 3 most recent slots above) per the canonical-source discipline.

## Open carry-ins

Tracked in [roadmap.md](roadmap.md) (active) / [roadmap-future.md](roadmap-future.md)
(watching) / `issues/`; surfaced here so the active head doesn't bury them:

- **x86-macOS usable-toolchain tail** — argv shipped (.30); env / arch-detect /
  cycc-finding / packaging remain; x86-macho cycc self-compile HELD (Intel EOL).
- **Kernel-PIE boot test** — the v6.1.7 ET_DYN wrapper needs an AGNOS `--pie` boot
  harness; aarch64 kernel-PIE is the consumer-gated follow-on.
- **var-syscall `ERR_*`/`SYS_*` namespace** — per-lib source cleanup (yukti/sakshi
  unrouted clock sites HELD / EOL-documented).
- **`2026-06-18-stdlib-native-agnos-abi-fs`** — `xopen` wrappers + cyrlint rule +
  ~58 raw `sys_open` sites (incl. sigil luks); issue active (from the .23 handoff).
- **`stdlib-reference.md`** — ~65/95 lib modules documented (human-led).
- **Windows/AGNOS real CSPRNG** — `issues/2026-06-11-windows-entropy-primitive.md`.

## v6.1.x — CLOSED (Backend Codegen Multi-Arc)

Closed at v6.1.41; v6.2.x is the active cycle (see *Current state* above).
Per-release detail is canonical in [CHANGELOG.md](../../CHANGELOG.md) +
[completed-phases.md](completed-phases.md); the whole-cycle frame is
[roadmap_6.md](roadmap_6.md). (The .0–.41 shipped list was trimmed to this
pointer 2026-06-19.)

## Consumers

AGNOS kernel, agnostik (58 tests), agnosys (20 modules), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests). All AGNOS ecosystem projects depend on the compiler
and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh ach` — Intel Mac (Mach-O x86_64 runtime, Apple EOL-track; self-hosts byte-identical)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

> **Note (2026-06-08):** ecb's repo checkout is stale (main @ v6.0.1, committed
> x86 `build/cycc` — only its installed `~/.cyrius/bin/cycc` runs there). Live
> ecb self-host needs that checkout updated; cross-emitted-binary runs verify it
> meanwhile. pi has no repo checkout (the self-host gate ships source over SSH).

## Bootstrap chain

```
bootstrap/asm (29,024 B committed binary — root of trust)
  → cybs (bootstrap compiler; formerly cyrc, renamed v6.0.0)
    → cycc (modular compiler + IR; formerly cc5, renamed v6.0.0)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win (Windows PE32+ cross-compiler)

(bridge.cyr — the old intermediate stage — was retired at v5.11.66.)
seed→cybs→cycc reproduces build/cycc BYTE-IDENTICAL (2026-06-20, CVE-20
resolved, no bridge rung). Enforced: scripts/seed-derive-cycc.sh.
No Rust* . No LLVM. No Python. Just sh + Linux x86_64.
  (* Rust seed in archive/seed/ rebuilds the asm seed itself — one-time
     deep verification via bootstrap/verify.sh; not on the build path.)
Build: sh bootstrap/bootstrap.sh
```
