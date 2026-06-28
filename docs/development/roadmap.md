# Cyrius Development Roadmap — v6.2.x (active minor)

**Scope** — the **current active minor only** (v6.2.x — Platform
Expansion), opened at the v6.1.x → v6.2.0 cut (2026-06-12). This is the
slot-pinning working artifact. The rest of the v6.x cycle (framing,
budgeting, minors v6.2.x → v6.5.x, and the closed v6.0.x/v6.1.x
summaries) lives in [roadmap_6.md](roadmap_6.md); items beyond the cycle
(v7.0+ aspirations, unpinned language refinements, speculative work) live
in [roadmap-future.md](roadmap-future.md).

> **v6.1.x is CLOSED.** Its Backend-Codegen multi-arc shipped to .41 (PIE
> x86/aarch64, `.gnu.hash`, TS/TSX→JS emit, agnos-target HIGH-sev fixes,
> Windows pillar, TLS/alloc/LSP, bayan/ganita carve, Phase-F security
> hardening). Per-patch detail is the [`CHANGELOG.md`](../../CHANGELOG.md)
> source of truth; the arc summary is in [roadmap_6.md](roadmap_6.md). The
> v6.1.x items that did **not** land are carried forward below under
> [Carry-in from v6.1.x](#carry-in-from-v61x-unpinned).

> **Reading order**: this file (active minor) →
> [roadmap_6.md](roadmap_6.md) (rest of the v6.x cycle) →
> [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, v6.2.x → v6.5.x, the closed v6.0.x +
  v6.1.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.2.x — Platform Expansion

**Theme**: bare-metal target codification + the **dependency-model
foundation** (modules + module groupings, lever 1 of 2), opened onto a
growable-region compiler foundation. RISC-V rv64 — originally this
minor's second platform arc — was **re-homed to v6.6.x** (user
2026-06-27: *"don't want to worry about another platform until some of
the other items in the minors get ironed out"*). So v6.2.x's remaining
committed work is the dependency-model arc, with the **bare-metal/kernel
reactive window staying open after it** (the `.39`–`.45` mode — incidental
kernel/agnos kickbacks). The *structured* bare-metal deliverable tail (the
three open design deliverables, below) is **pinned to v6.3.x for
revisit/fix** (user 2026-06-27). Substantial new-code minor.

**Realized shape (through v6.2.45):** the minor flexed long into a broad
**platform / stdlib / security / verification** line. Shipped: AGNOS syscall
completeness + portability, native-float math (`f64` type + operators), TLS
hardening (server wrapper, ALPN, per-connection arena), Darwin/Windows surface,
stdlib folds, aarch64 imm12-mask codegen, CLI tooling (.0–.25); **bare-metal
target formalization (.27 frontend + .28 runtime/boot)**; CVE-20/21 trust-chain
+ sovereign signing + the seed→cybs→cycc derivation (.30–.31); the
silent-correctness + stdlib-refold arc (.41 call-arity check + IEEE-754 NaN fix,
.42 sigil certpin, .43 agnos-clock + ERR_* namespacing + agnos landmine gates);
CVE-29 thread-stack guard page + cross-arch `_PE`/Mach-O stub completeness (.44);
kernel-PIE landmine + structural-gate hardening + 3-lib refold (.45).
See the shipped-summary row below + [CHANGELOG.md](../../CHANGELOG.md). **The one
remaining committed arc *here in v6.2.x* is the dependency-model foundation
(lever 1)** — see the pinned row below. The bare-metal target's core shipped
(.27 frontend / .28 runtime), but **three of the seven design deliverables remain
open and are pinned to v6.3.x for revisit/fix** (user 2026-06-27; numbered per
the [roadmap_6.md](roadmap_6.md) seven-deliverable design list — NOT the .27/.28
shipped-slot D-labels, which reused D5–D7 for entropy/load-base/boot-gate):
**#5** the `[sections]` linker-script / section-placement block; **#6** inline-asm
primitive completion (`cli`/`sti`/`hlt`, port I/O, memory barriers, `cpuid` —
beyond the `asm{}`/`iretq`/`eret` that shipped;
`2026-06-19-naked-fn-safety-and-inline-asm.md`); **#7** the kernel-freestanding
TLS link + in-kernel handshake smoke (cyrius-side link + smoke schedulable; the
live in-kernel boot stays AGNOS-consumer-gated). The kernel load-base settability
tail (`2026-06-19-kernel-load-base-settable.md`) and the kernel-PIE live boot
(gnoboot-gated) ride alongside. Meanwhile v6.2.x keeps the **open bare-metal/kernel
reactive window** for incidental kickbacks (the `.39`–`.45` mode); the structured
deliverable work is the pinned v6.3.x set. **RISC-V rv64 is re-homed to v6.6.x**
([roadmap_6.md](roadmap_6.md)).

Per cycle discipline: premise-check each arc at slot entry
([[feedback_premise_check_at_slot_entry]]); cross-arch propagation is
mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS
self-host verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]); benchmark every release
([[feedback_benchmark_every_release]]). Window open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long (v6.0.x ran
to 91; "no worries about patch size, just hardening and adding
features", user 2026-06-10).

---

## Pinned slot sequence

| Slot | Item | Phase |
|---|---|---|
| **v6.2.0** ✅ | **Phase 0 — growable-region foundation** (ends the cap-raise treadmill + AR-03 split-brain): `fixup_tbl` → `_fixup_base`/grow (64M ceiling), fn-tables (16 parallel tables + 2 hashes + `live[]` → `_fnt_*`/`_fnt_cap`, grow+rehash, 32768 ceiling; was at 79 % of 8192), codebuf → `_codebuf_base`/grow (64 MiB). **+ `cyrius init` CI/release alignment** (canonical `install.sh` one-liner, `git archive` source tarball + `SHA256SUMS`, `VERSION` as single source of truth). Each migration byte-identical + forced-grow on x86 **and** real-ARM (pi) + check.sh 89/89 + cross-OS 4/4. | 0 — substrate |
| **v6.2.1** ✅ | **Element-typed fixed arrays `var a: T[N]`** — resolves the address-taken-local byte-vs-slot footgun (daimon route-404). `i64[N]` is the unambiguous SLOT spelling (fixes the `store64(&a+i*8)` idiom), `u8[N]` an explicit byte buffer; widths i8..i64/u8..u64/u128. Pure frontend (element width → var-size table → every backend inherits it). + daimon-class slot-array sweep: 10 cyrius-owned sites (5 in cycc itself via two-step bootstrap, 5 native stdlib). | 0 — language/safety |
| **v6.2.2** ✅ | **aarch64/macOS annotation-token codegen fix + ecosystem stdlib fold-in.** The fn-attribute tokens (109/122/124/125/126/127 — `#regalloc`/`#must_use`/`#deprecated`/`#pure`/`#io`/`#alloc`) were only consumed in `main.cyr`; the 3 non-x86 forks dropped an annotated fn into their catchall, leaving the next `enum` unregistered → `error: unexpected enum` (blocked `bayan` on aarch64+macOS). Ported the consume into **both** pass-1 + pass-2 of `main_aarch64.cyr` / `main_aarch64_macho.cyr` / `main_x86_macho.cyr` (consume-and-ignore; opts gated off per CO-03). x86 cycc byte-identical. **+** re-folded all 12 vendored `lib/*.cyr` to released 6.2.1-pinned versions; api-surface re-snapshotted (4236 fns, +26/−1). qemu exit-0 + cross-OS 4/4 + check.sh 89/89. | 0 — frontend/fold |
| **v6.2.3** ✅ | **AGNOS net/entropy/clock syscall peer (#45–#55) — the TLS + net-tools enabler.** Mirrors the eleven ring-3 syscalls AGNOS 1.45.0–1.45.4 froze into the `CYRIUS_TARGET_AGNOS` stdlib peer (`sys_time_unix`/`sock_*`/`udp_*`/`icmp_echo`; `sys_getrandom` un-fail-closed → #45). **Option A** (surgical adapter): tagged fd↔conn_id table routes the BSD-shaped `net`/`tls_native`/`http` (which bottom out at `sys_read`/`write`/`close`) onto the conn_id model, source-identical. **+ discovered prereq:** `lib/thread_agnos.cyr` single-threaded threading serial-fallback (tls→sigil→thread.cyr; agnos has no clone/futex) with TLS save/zero/restore around inline workers. Pure stdlib + agnos-`#ifdef`-gated → x86 cycc byte-identical. http/net/dig/yo + tls_native now build for agnos. 13-agent adversarial review caught 2 real bugs pre-cut. | agnos-target |
| **v6.2.4** ✅ | **TLS transport-vtable refactor (Option C).** Decoupled `tls_native` from raw `sys_read`/`sys_write`/`_tn_now_unix` via a **module-global** transport vtable (3 fn-ptr globals, 0=default; `tls_native_set_transport` setter) routed in the 2 leaf I/O helpers + `_tn_now_unix`; per-conn handle still flows via `TLS_CTX_OFF_SOCK_FD`. **Global over per-ctx deliberately** → ZERO change to the 25 `_tn_sock_*` call sites (a missed site is impossible by construction; the 6.2.3 `sock_connect` near-miss class), and the 1.2 driver + app-data I/O ride the same leaf helpers (covered free). Strictly logic-preserving (all TLS gates green; default byte-identical; cycc byte-identical). Hermetic `tls_native_transport_vtable.tcyr` proves the dispatch. Unblocks the bare-metal kernel-freestanding-TLS slot (the kernel plugs its TCP send/recv). 4-agent review: no real bugs. | agnos-target / refactor |
| **v6.2.5** ✅ | **`tls_native.cyr` module split** (user-directed). The 5,857-line monolith → a 302-line include-hub (deps + shared enums/consts) + 6 focused modules: `_lowlevel` (wire/record/transcript), `_keysched` (1.3 key schedule + ciphersuite registries), `_ctx`, `_hs13` (full TLS 1.3), `_hs12` (full TLS 1.2), `_conn` (verify + 6.2.4 transport vtable + connect/accept + I/O). **ORDER-PRESERVING block moves** (each module a contiguous slice included at its original position → preprocessed text unchanged). **PROVEN byte-identical** (concatenating the slices reproduces the pre-split file, `cmp` clean). All TLS gates green (scaffold 448/448, realpeer, tls12, vtable, live); self-host byte-identical; check.sh 89/89; x86+agnos+aarch64 compile; cross-OS pi/ecb/cass; downstream `cyrius deps` pulls the new files via the transitive include-scan (verified). 113 tls fns relocated, name+arity unchanged. **Closes the v6.2.x TLS arc** (vtable → split). | refactor / lib-streamlining |
| **v6.2.6–.25** ✅ | **Shipped — the realized middle of the minor** (per-slot detail canonical in [CHANGELOG.md](../../CHANGELOG.md); recent handoffs in [state.md](state.md)). The two pinned platform arcs below have not yet landed; what shipped instead: **AGNOS syscall completeness** (net/entropy/clock peer .3/.6/.7, server-socket #56/#57 + ALPN .22, fs/sysinfo .23), **native-float math** (f32 conversions .18, named `f64` type + operators .19), **native-TLS hardening** (trust-store/mTLS .8, `tls_accept` server wrapper + SYS_* dedup .24, per-connection arena/flat-RSS + sigil 3.9.1 .25), **Darwin/Windows platform** (IPv6 .10, clock .13, file-output .17, CSPRNG .12), **stdlib folds** (sandhi/mabda/sankoch/sigil across .9/.11/.12/.22/.24/.25), **aarch64 imm12-mask codegen** (.21), **CLI tooling** (cyrfmt/cyrlint silent-truncation .20, `cyrius audit` project sweep .25). cycc 1,069,688 B · check.sh 89/89 · api-surface 4939 · cross-OS pi/ecb/cass green throughout. | platform/stdlib/TLS |
| **v6.2.26** ✅ | **agnos-fs ABI substrate — SHIPPED** + mabda 3.3.0 + **yantra 1.0.0 (new fold)**. Portable `xopen`/`xstat`/`xunlink`/`xgetdents` in `lib/io.cyr` (per-target `#ifdef` ABI bridge) + cyrlint getdents rule + a new agnos x* emit-inspect gate (`_agnos_xsys_gate`, no-Linux-217). **Premise-check finding:** the "~58 sites" were mostly vendored (upstream) / Linux-only / already-fixed (fs.cyr @.23), so this shipped as the **preventative cure** (substrate + lint rule), NOT a migration — no cyrius-native crash site remained. Adversarial review: substrate ABI/guards clean; 2 cyrlint rule bugs fixed. Also folded **mabda 3.3.0** (asset/png + native/wgpu) and **yantra 1.0.0** (UI/E2E testing — WebDriver/Appium/CDP — vendored, opt-in). cycc byte-identical; check.sh 89→90; api-surface 4939→5034. Feeds the .27 kernel-freestanding-TLS arc. (user-pinned 2026-06-19) | bottom — agnos/stdlib |
| **v6.2.27** ✅ | **Bare-metal target formalization — FRONTEND HALF — SHIPPED.** **D1** `--target=<arch>-bare-metal-elf` triple (x86_64 + aarch64; forces kmode via a new `CYRIUS_KERNEL=1` env read, `_skip_deps` freestanding, byte-identical to source `kernel;`). **D2/D4** clean no-libc ELF (single PT_LOAD, no PT_INTERP/DYNAMIC). **D3 `#naked`** attribute (token **133**; frameless emit, x86 −48 B / aarch64 −24 B; 6-fork mirror). **Adversarial review (19 agents) — 3 P1s fixed:** token-128/f64v_dot collision → 133; DCE-stub `_naked_pending`-leak SIGSEGV → reset; aarch64-triple silent-x86-build → `set_arch`+hard-error. **`#naked` shipped as the prologue-skip ATTRIBUTE (building block)** — full ISRs need inline-asm (cyrius has none yet) + the param/return guards don't fire on DCE-stubbed fns → both filed (`2026-06-19-naked-fn-safety-and-inline-asm.md`) + pinned to .28. cycc 1,069,688→**1,071,904 B** (+2,216, in-compiler); check.sh 90/90; cross-OS pi/ecb/cass. | bare-metal frontend |
| **v6.2.28** ✅ | **Bare-metal target formalization — RUNTIME HALF — SHIPPED** (closes the .27+.28 arc). **D5** kernel-freestanding TLS entropy: `_tn_tx_rand` slot + `tls_native_set_entropy` + `_tn_rand_bytes` leaf over all **11** getrandom sites (roadmap's "12"/hs13×9 was stale → 8+3). **D6** entry/load-base VA exposed via the triple build (gate-asserted both arches); full base-settability deferred (`2026-06-19-kernel-load-base-settable.md`). **D7** a REAL QEMU kernel boot gate (`scripts/qemu-boot-gate.sh` → "AGNOS" on serial; ELF64 shape both arches) wired into check.sh + a `bare-metal-boot` CI job. **`#naked` completion** (premise-check found inline asm always existed — `asm{}`+`iretq`; only aarch64 `eret` was missing): DCE-force so ISRs aren't stubbed-and-bypassed, the silent `strlen`-segfault in the param/return guards fixed, the 1-line `eret` mnemonic — real ISRs now writable. **Adversarial review (18 agents) — 6 folded, P1: the boot gate wasn't wired into CI** (the placebo it exists to kill). cycc 1,071,904→**1,071,888 B** (−16); check.sh 90/90 + boot gate; cross-OS pi/ecb/cass. | bare-metal runtime |
| **v6.2.29** ✅ | **VR-01/VR-02 verification fold — SHIPPED** (no `src/` change; tests/gates/CI). **VR-02** `cyrius fuzz` → check.sh gate + ci.yml step. **CLI cross-compile gate** (cbt/cyrius.cyr → PE/Mach-O/aarch64, magic-verified) — the .25-class hole. **VR-01** the full `.tcyr` corpus now runs on REAL arm64 (aarch64-native CI job) — it surfaced that the language was effectively broken on ARM, and **the whole batch was fixed IN-SLOT** (the gate's first red run tied it to .29): the root cause `main_aarch64_native.cyr` stale-fork (124 lines behind, zero annotation handling) + **9 backend bugs** (x86-leak class: unguarded x86 asm in `.text`, missing ESYSXLAT renumbers pipe/flock/faccessat, `clock_gettime`, 2 x86-exact test bugs) + **`fdlopen`** via `#naked` setjmp/longjmp (which earned `#naked` register-param support). bayan u128 fix source-first → **bayan 1.0.2** re-folded. Gate now HARD + GREEN: **189 pass / 0 fail / 0 xfail / 1 skip** on pi. cycc 1,071,888→**1,071,936 B** (+48, the `#naked` param-store gate). check.sh **92/92**. The validation lesson: validate with the NATIVE compiler ARM users run, not the cross. | verification/CI |
| **v6.2.30** ✅ | **CVE-21 trust-chain integrity — PART 1: integrity + pinning** (was .29) — fail-closed release path + immutable pins. (a) `install.sh:373` warn→err (abort on checksum mismatch) + require the `.sha256` on the network-download path; (b) `.sha256` verify added to `ci.sh` + `install.ps1` (both had none); (c) installer fetched from `/refs/tags/<v>/` not `main`, tag-clone failure fatal (no silent HEAD fallback); (d) `cbt/deps.cyr` records the resolved **commit SHA** per dep in `cyrius.lock` + verifies the cached/cloned HEAD on re-resolve (force-push / cache-poison detection); (e) all GitHub Actions pinned to full commit SHAs. **+ CVE-20 doc reframe** (shipped trust root is `build/cycc`, not the seed; reframe CVE-12). **+ RM-02** threat-model.md factual fix (native-TLS default / PIE shipped / 1 MB cap) + owed doc-health stamp refresh. **+ mabda 3.3.0→3.4.2 fold** (array textures + cubemaps, BC tiled arrays, `F64_*`→`MABDA_F64_*` math-collision fix, render-target 64 KiB VA-map align + per-context RT VA bump). Signing + reconstruction CI split to .31 (pre-planned, user 2026-06-19). From `2026-06-10-release-trust-chain-integrity`. **SHIPPED:** cycc byte-identical 1,071,936 B · check.sh 92/92 · self_compile 508 ms · cross-OS pi/ecb/cass `SELFHOST_OK` · api-surface 5035→5055 (mabda 3.4.2) · 25-agent adversarial review (8 fixed: P1 scaffolded-CI-template hole, dep-verify 8 KB→64 KB window, worktree-tamper guard). | security |
| **v6.2.31** ✅ | **CVE-20/21 trust-chain integrity — PART 2: sovereign signing + reproducibility attestation** (user 2026-06-19/20). (a) **Sovereign** detached signing — `cyrsign` (a standalone tool over sigil's in-tree ed25519: keypair/sign/verify) signs `SHA256SUMS`; pubkey committed in-repo + SECURITY.md; `install.sh`/`ci.sh`/`install.ps1` verify with the cyrius verifier on the upgrade/CI path (no external `minisign` — sovereignty). Closes CVE-13. (b) **Self-host-fixpoint attestation CI** (NOT the literal seed→cycc — see the bridge arc below): a `trust-root-attest` job (`build-cycc-verify.sh`) asserts the committed `cycc` compiles its own source → fixpoint → equals the committed binary. **Interim** CVE-20 mitigation: catches accidental artifact **drift** + non-self-reproducing tampers — it does NOT defeat a self-reproducing (trusting-trust) tamper (the committed binary is its own root → a self-perpetuating backdoor is a stable fixpoint), and is NOT diverse double compilation. Real anti-tamper / machine-*derivability* is the bridge arc. **SHIPPED:** cyrsign sovereign Ed25519 (sigil 3.9.2 fold) builds+signs+verifies on all 4 targets; release CI signs+self-verifies fail-closed; 3 installers verify on upgrade/CI; cyrsign in all 5 tarballs; CVE-13 closed. cycc byte-identical 1,071,936 B · check.sh 92/92 · cross-OS pi/ecb/cass `SELFHOST_OK` · 2-round adversarial review (33 agents, 10 fixed; anti-downgrade floor filed). | security |
| **v6.2.x** ✅ | **Seed→cycc derivation — the REAL CVE-20 fix — SHIPPED 2026-06-20** (user-prioritized 2026-06-20). **Achieved with NO bridge rung** — rather than restoring `src/bridge.cyr`, `cybs` (`bootstrap/cybs.cyr`, the asm-source bootstrap compiler) was grown brick-by-brick to compile ALL of modern `src/main.cyr` directly: recursive `include` + `#ifdef` preprocessor, 3-pass driver, fn↔global resolution, compound assignment, comparisons-as-values, bare-truthy conditions, fn-pointers (`&fn` + indirect call), find-or-reuse locals, and the completing fix — a missing string-NUL-terminator in cybs's lexer (had broken the preprocessor macro-hash → dropped the Linux `#ifdef` block → undefined `alloc` → `ud2` trap). Chain, no bridge: seed assembles cybs → cybs compiles `src/main.cyr`→gen1 → gen1 compiles `src/main.cyr`→gen2 == `build/cycc` (self-host fixpoint, gen2==gen3). Enforced by `scripts/seed-derive-cycc.sh` + the `trust-root-attest` CI job; supersedes the .31 attestation interim. **Fewer rungs than "the way we did it before"** — the sovereignty win. seed 29,016→29,024 B (NUL fix), cybs 12,344→21,066 B, Rust-seed-verified via `bootstrap/verify.sh`, `bootstrap/SHA256SUMS` updated. | security / bootstrap |
| **post-v6.2.33** ✅ | **Deleted `bootstrap/scaffold/bridge.cyr`** (2026-06-20, after the v6.2.33 tag). The readable-cyrius proof-of-concept that de-risked the seed→cybs→cycc derivation had served its purpose — cybs now stands alone. Recovery point preserved: `git checkout v6.2.33 -- bootstrap/scaffold/bridge.cyr` restores it if the chain ever regresses. Removal verified byte-identical (nothing included it; cycc self-hosts unchanged). | cleanup / bootstrap |
| **v6.2.x** ⏳ | **Dependency model — modules + module groupings (the granularity foundation; LEVER 1 of 2)** — **ACTIVE next arc** (window opened 2026-06-27; the bare-metal/kernel reactive work continues *after* it, still in v6.2.x). (user-added 2026-06-19; plan-of-attack grounded + sequenced 2026-06-21 — full framing + verified facts + the two-lever rationale in [roadmap_6.md § "Dependency model: modules + module groupings"](roadmap_6.md)). Dissolve the flat `[deps] stdlib = [list]` into module-granular **standard deps** + named **module groupings**, so a consumer pulls exactly the modules it needs instead of `include`-ing a vendored monolith whole + hand-ordering its chain. **Why lever 1 first (user 2026-06-21, "right over fast"):** granularity shrinks *what* each project pulls, profile-scoping (lever 2, v6.3.x) restricts *which contexts* pull it — they compound, so a smaller cyrius/sigil/mabda makes every downstream consumer smaller+faster recursively. **Sequenced (pre-planned 1–2 release arc):** **Phase A** transitive auto-resolve + topological include ordering (lead — cheap, CLI-only, kills descent's live "omit one → runtime SIGILL" hand-ordered-chain pain; the 8 MB cap means bloat is latent not live, so the ordering fix is the urgent half); **Phase B** named `[groups]` (the addressable sub-units lever 2 will gate); **Phase C** distlib per-module emit + index → true sub-module extraction (heavier producer-rework — folds are flat non-sub-includable concats today; may be its own release); **Phase D** dissolve "stdlib" + migrate descent as the proof. Self-host byte-identical (cycc has no folds); pre-existing manifests byte-identical. Profiles/optional/features = **v6.3.x lever 2**, built on this. **Folds in:** the **undefined-fn reachable-call hard-error** ([`issues/2026-06-25-undefined-fn-reachable-call-hard-error.md`](issues/2026-06-25-undefined-fn-reachable-call-hard-error.md)) — designed + verified in a v6.2.44 spike but deferred here because a *default* hard-error needs cross-module refs resolved/declared-optional first (else loosely-coupled consumer builds break). Once transitive resolution lands (Phase A), the hard-error becomes safe to default-on. | deps/packaging |

> **RISC-V rv64 moved to v6.6.x** (user 2026-06-27) — the 4th platform
> peer (`backend/riscv/{emit,jump,fixup}.cyr` + syscalls peer +
> real-hardware self-host gate) is parked at a new tail minor so v6.2.x
> doesn't take on a second platform while the v6.3.x–v6.5.x items iron
> out. Hardware is in-hand; it's a deferral of *worry*, not of intent.
> Full scope lives in [roadmap_6.md § v6.6.x](roadmap_6.md).

> **Indicative sizes** (roadmap_6.md, not a budget cap): dependency-model
> lever 1 ~6–10; bare-metal reactive window as surfaced (the structured
> #5/#6/#7 deliverable tail is pinned to v6.3.x); cross-arch harness/CI
> ~3–4. RISC-V (~12–14) moved to v6.6.x. Deep-dive hardening rides
> bug-bandwidth as surfaced.

---

## Next items — frontend / DX hardening (pull into a v6.2.x later line)

Not yet pinned to a slot; land on a bug-bandwidth line or fold into an
adjacent compiler change.

- **SHIPPED v6.2.41 — call-site arity check** (`2026-06-23-call-arity-no-check.md`,
  RESOLVED+archived). Non-fatal warning via a shared `_CHECK_ARITY` helper across all
  three call-emit paths (normal `PARSE_FNCALL`, the `return f(args);` tail-call path,
  and the inline-replay path — broader than the originally-pinned PARSE_FNCALL-only
  scope, which alone would have missed the inline `ESUBRSP` and every `return f(args)`).
  Carve-outs as planned: backward-refs-only (`_fnt_offsets >= 0`; inline path skips the
  gate since `pc` is reliable there), variadics (new `GFVA` getter), syscall/`fncallN`
  structurally exempt; variant ctors register their real arity instead of being exempted.
  Surfaced+fixed in-slot: the `ESUBRSP` latent bug (cycc self-compiles arity-clean) +
  the `cyml.tcyr`/`v5104_inference.tcyr` test bugs. The sigil `run_capture` finding was
  a deeper signature mismatch → filed as
  `2026-06-24-sigil-certpin-run-capture-signature-mismatch.md` (follow-up). Still-open
  hard-error/`--strict-arity` escalation (+ the struct-return / `return (a,b)` paths)
  is the documented later scope. See [[project_call_arity_check_warning_first]].
- **DRY the four pass-1/pass-2 top-level scanners** (`main.cyr`,
  `main_aarch64.cyr`, `main_aarch64_macho.cyr`, `main_x86_macho.cyr`). The
  v6.2.2 `unexpected enum` fix was the **3rd instance** of an annotation
  token (or any new top-level token) landing on only one fork's scanner
  (v5.8.20 `#io`, now v6.2.2 `#pure`). Each fork hand-maintains a parallel
  pass-1 pre-scan + pass-2 parse loop; a 7th annotation token, or any new
  top-level construct, will desync again. Extract the token-dispatch into a
  shared `common/`-hosted helper (mirror the v6.1.4/.5 `_emit_fmt`/DCE
  hoist pattern) so the cases live in one place. Logic-preserving →
  byte-identical self-host on all 4 hosts is the gate. MEDIUM (DX /
  recurring-bug-class). See [[project_v622_annotation_fork_desync]].
- **Undefined-function call should hard-error, not emit `ud2`** — **DEFERRED
  to the dependency-model arc** (v6.2.44 spike, 2026-06-25). Designed +
  implemented + verified working (hard-error default + `--allow-undef`), then
  pulled back out of the cut: making it the *default* breaks 21/192 tcyr **and
  loosely-coupled consumer builds** (e.g. mabda-without-samvada) because the
  stdlib's cross-module refs aren't always resolved — exactly what the
  dependency model (the pinned slot above) fixes. Its byproduct — 3 genuine
  cross-arch stub gaps it surfaced — **shipped in v6.2.44**. Full design +
  blast-radius writeup:
  [`issues/2026-06-25-undefined-fn-reachable-call-hard-error.md`](issues/2026-06-25-undefined-fn-reachable-call-hard-error.md).
  Pick up *with* the dependency-model arc.
- **Local-array byte-vs-slot convention decision.** Largely resolved by the
  v6.2.1 `var a: T[N]` slot spelling, but the *bare* `var a[N]` convention
  (local = N bytes, global = N slots) remains a latent footgun. Decide:
  lint the address-taken-per-slot idiom on a bare local array, or audit
  stdlib/consumers for remaining bare-array slot writes. MEDIUM (DX).
  [`issues/2026-06-11-addr-taken-local-array-static-underreserve.md`](issues/2026-06-11-addr-taken-local-array-static-underreserve.md).
- **Permanent syscall-write byte-length gate** — the `.39` audit missed a
  multi-line syscall (single-line regex); make the byte-length check a
  standing gate using DOTALL. (Carried from v6.2.0-open.)

---

## Carry-in from v6.1.x (unpinned)

v6.1.x items that did **not** land — they ride the bug-bandwidth budget,
landing on consumer pressure or explicit user direction
([[feedback_no_unilateral_scope_decisions]]), not as pinned releases.

- **Kernel-PIE ELF boot-test for AGNOS KASLR.** The RIP-relative codegen +
  `ET_DYN` `EMITELF64_KERNEL` wrapper **shipped v6.1.7** (structurally
  validated, never boot-tested). **Consumer-gated** on an AGNOS `--pie`
  boot harness (won't ship blind); the harness ask is filed
  (`agnos/.../2026-06-10-cyrius-pie-boot-harness-ask.md`). AGNOS isn't
  pulling yet (data-only KASLR @ v1.28.0). [[project_v616_bugband_then_full_pie]].
  **Update (v6.2.45):** a ground-truth review added a structural CI gate
  (`_kernel_pie_struct_gate` — `kernel; --pie` → ET_DYN + `p_vaddr=0`) and a
  latent `_entry_base` fix. It also surfaced the one concrete cyrius-side item
  the live boot will force: the `--pie` `.text` is fully PIC but the emitted
  boot metadata still targets the link base (`p_paddr=0` + an **absolute**
  multiboot2 `ENTRY_ADDRESS_EFI64` tag; no `ADDRESS` tag, no relocations) — so
  a slide needs gnoboot to bias manually OR cyrius to emit slide-aware metadata.
  **RESOLVED 2026-06-27 — full-binary KASLR shipped + validated end-to-end.**
  gnoboot took Option 1 (biases manually: reads the relocation-free ET_DYN,
  picks an RDRAND-slid 2 MB-aligned base in [32 MB, 254 MB), jumps to
  `base + e_entry`) — **no cyrius metadata change needed**; the relocation-free
  PIE `.text` + ET_DYN/`p_vaddr=0` wrapper was necessary AND sufficient. Issue
  archived. This carry-in (open since v6.1.7) is **complete** — migrate to
  completed-phases.md at the next closeout.
- **x86-macOS usable-toolchain arc tail.** Phase 1 (argv prologue) shipped
  v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), the
  wrapper's macOS arch-default (detect x86 on Intel), cycc-finding, the
  layer-6 native self-compile miscompile (tools ship cross-built until
  fixed), packaging. **`ach` is the supported macOS-x86 verify host**; the
  v6.2.2 `main_x86_macho.cyr` annotation fix is verified there
  (`SELFHOST_OK`).
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md),
  [`issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md`](issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated; lands when cyim
  updates + re-tests against v6.x.

---

## Deep-dive hardening spread (rides v6.2.x+ bug-bandwidth)

From the 2026-06-10 deep-dive review
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)).
The urgent set landed in the v6.1.x Phase-F tail (CVE-14/15/16/17/18/19/22/
23/24/25/26/27/28/30/31, CO-02/03, AR-03 — all shipped v6.1.33–.41). The
remainder spreads here and to later minors per "urgent now, rest spread":

- **Release / trust-chain integrity** (CVE-20/21) — v6.2.x bug-bandwidth +
  the v7 trust-story.
- **Thread-stack guards** (CVE-29) — v6.2.x.
- **Verification coverage** (VR-01…04) — VR-03 differential corpus gates
  v6.4.x; the rest as surfaced.
- **Monomorphization substrate** (AR-01 / CO-01) — v6.3.x Phase-0 (AR-02
  growable tables already landed at v6.2.0).
- **v7 readiness gates** (LEGAL-01 licensing, diagnostics) — tracked for
  the v7 cut.

Audit cadence + the CVE-09…13 re-file tail:
[overdue-security-audit-cve-tail](issues/2026-06-10-overdue-security-audit-cve-tail.md)
— this deep-dive IS the overdue full audit.
