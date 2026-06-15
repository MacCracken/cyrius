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
| **Version** | **6.2.10** (v6.2.x cycle — **Platform Expansion**; Darwin IPv6 socket surface for `lib/net.cyr` + the pre-existing aarch64-Linux INET ESYSXLAT gap it surfaced + sandhi 1.6.1 fold. See [roadmap_6.md](roadmap_6.md)) |
| **cycc** (x86_64 ELF) | 1,063,792 B (+8 B @ 6.2.10 — `6.2.10` version string only, x86 codegen unchanged; −16 B @ 6.2.9 dead debug bytes) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | 616,496 B (+1,192 B @ 6.2.10 — aarch64-Linux ESYSXLAT socket/fcntl/poll renumbers + version string; +~20 KB @ 6.2.2 annotation-token consume) |
| **cycc-native-aarch64** (aarch64-native, tracked) | 787,248 B (refreshed @ 6.1.8 — PIE-enabled; **NOTE: predates the 6.2.10 aarch64 emit fix — refresh via `cyrius pulsar` when next on ARM hw; not a gate, the pi self-host rebuilds from source**) |
| **cycc_win** (PE32+ cross) | 836,096 B (rebuilt @ 6.2.10; size flat — PE 512 B file-alignment absorbs the +8 version-string bytes) |
| **cyrius-lsp** (language server) | 531,688 B |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | 12,344 B |
| **seed** (`bootstrap/asm`, root of trust) | 29,016 B |
| check.sh gates | 89/89 (+1 @ 6.1.36 — `_vendored_dist_selfcontained_gate`) |
| sigil fold | 3.7.13 (@6.2.2 ecosystem fold-in: json dropped + bigint→bayan + 6 attestation cert-arrays → `i64[4]`) |
| stdlib fold | agnosys 1.4.2 · **sandhi 1.6.1** · sankoch 2.3.1 · niyama 1.0.5 · bayan 1.0.1 · ganita 1.0.1 · patra 1.11.2 · yukti 2.2.5 · vani 0.9.5 · sigil 3.7.13 · mabda 3.1.1 · sakshi 2.3.0 (sandhi refold @.10 — v4 nb-connect + per-op timeout now compose stdlib; v6/listen adoption is its follow-on) |
| tests | 178 `.tcyr` (+`net_v6_connect` @.10 — Darwin v6 layout + nb-connect, runs on x86/ecb/pi) · 15 `.bcyr` · 5 `.fcyr` |
| stdlib | 97 `lib/*.cyr` · 79 programs · api-surface 4346 fns (+5 @.10 — `net::sockaddr_in6`/`net_connect_nb6`/`net_connect_sa_nb`/`sock_set_nonblocking`/`sock_clear_nonblocking`, additions-only) |
| heap | `output_buf` 16 MB @ `S+0x4D9D000` (relocated heap-top, 2MB→16MB @ .27); `file_map` relocated to freed `0x71A000` band @ .35; 4 per-fn local tables relocated to heap-top `0x5D9D000`+ (4×128 KB, 16384 slots) @ .40 (CVE-24); brk-final `0x5E1D000` (~94.1 MB virtual, +512 KB @ .40) |
| bench (every-release gate) | self_compile ~505 ms (flat @ 6.2.10 — lib + aarch64-emit changes don't touch the x86 compiler; cycc 1,063,792 B, +8 version string, self-host byte-identical) |

> **Handoff (2026-06-15):** **v6.2.10 CUT — Darwin IPv6 socket surface for
> `lib/net.cyr` + the aarch64-Linux INET path it surfaced.** Fulfils sandhi's filed
> consumer request (`2026-06-15-cyrius-net-v6-darwin.md`): stdlib now exposes a
> Darwin-correct IPv6 + non-blocking surface — per-target `AF_INET6` (Darwin 30 /
> Linux 10), `sockaddr_in6` (28 B, BSD `sin6_len`), `net_connect_nb6` +
> `net_connect_sa_nb` (the extracted generic core of `net_connect_nb`, v4
> unchanged), `sock_set/clear_nonblocking`. **Folded-in fix (the user's call to do
> it now, not defer):** verifying the new test on the **real pi** exposed a
> pre-existing (v6.0.59-era) bug — net.cyr issues x86 socket syscall NUMBERS and
> relied on `ESYSXLAT` to renumber them, but those renumbers existed ONLY in the
> `_TARGET_MACHO==2` branch, never aarch64-Linux, so the entire INET path
> (tcp_socket / connect / the v6 surface) AND `chrono.cyr sleep_ms` were silently
> broken on native ARM (socket 41→pivot_root, fcntl 72→pselect6, poll 7→fsetxattr).
> `src/backend/aarch64/emit.cyr` now mirrors the socket family into the
> aarch64-Linux ESYSXLAT branch (socket/connect/accept/shutdown/bind/listen/
> getsockname/setsockopt/getsockopt/fcntl pure renumbers + a `poll 7→ppoll 73`
> timespec arg-shift; encodings assembled with `aarch64-linux-gnu-as`). Dep refold
> **sandhi 1.6.0→1.6.1** (v4 nb-connect + per-op timeout now compose stdlib; v6 +
> listen-socket adoption is sandhi's follow-on slot). **VERIFIED:** check.sh
> **89/89**; x86 self-host byte-identical (aarch64 backend not in the x86 build);
> aarch64-Linux self-host byte-identical; cross-OS **SELFHOST_OK ecb/pi/cass** on
> the shipped 6.2.10 binaries; `net_v6_connect.tcyr` 17/17 on x86 + **ecb (real
> macOS, Darwin constants executed)** + **pi (real aarch64, was failing pre-fix)**;
> `poll→ppoll` validated (1500 ms→~1.5 s, 0 ms→immediate). 17-agent adversarial
> review: surface correct, sandhi fold clean byte-identical, v6 deferral a
> legitimately-scoped consumer follow-on (not a half-fix). api-surface 4341→4346
> (additions only). bench self_compile ~505 ms. **NEXT:** the remaining v6.2.x
> pins — bare-metal target formalization + RISC-V rv64. **user pushes/tags after
> CI.** (Stale tracked `build/cycc-native-aarch64` predates this emit fix — refresh
> via `cyrius pulsar` when next on ARM; not a gate.)
>
> ---
>
> **Prior (2026-06-15):** **v6.2.9 CUT — sandhi 1.6.0 / mabda 3.1.1 fold +
> diagnostic byte-length audit closed.** Maintenance release. **sandhi 1.6.0** is
> the consumer half of the 6.2.8 mTLS work: it retired its `tls_dlsym("SSL_CTX_*")`
> callers onto the typed `tls_ctx_*` wrappers (7 call sites now; its 5 removed
> symbols are the `_sandhi_apply_*_fp` dlsym caches — all `_`-prefixed internals,
> not public). **mabda 3.1.1** patch fold. **Byte-length audit**
> (`2026-06-12-diagnostic-syscall-byte-length-audit.md`) resolved: its 27 sites
> were already fixed in a prior release (stale-open); a UTF-8/DOTALL re-derivation
> across all 425 `syscall(SYS_WRITE,…,LEN)` sites found one more the original
> single-line audit missed — `main.cyr:825`, a multi-line `"\n        "` debug
> literal with `LEN=1` (cleaned to `"\n"`; runtime unchanged). Audit now provably
> clean (425 sites, 0 miscounts) → archived. cycc 1,063,800→1,063,784 B (−16).
> **VERIFIED:** check.sh 89/89; self-host byte-identical; cross-OS **SELFHOST_OK
> ecb/pi/cass**; bench ~506 ms; api-surface 4340→4341 (additions only). Also filed
> sandhi's macOS non-blocking-connect gap sandhi-side
> (`sandhi/docs/issues/2026-06-06-macos-nonblocking-connect.md` — was only tracked
> cyrius-side; sandhi-side fix is the consumer's follow-up). **NEXT:** the
> remaining v6.2.x pins — bare-metal target formalization + RISC-V rv64. **user
> pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-15):** **v6.2.8 CUT — native TLS trust-store + mTLS
> client-auth.** Closes the residual of sandhi's `2026-05-22-cyrius-native-tls-in-6.0.x.md`
> (the last open native-TLS item): typed native `SSL_CTX_*` equivalents so native
> trust-store / mTLS **enforce**. **Trust-store half:** `lib/tls.cyr` gained
> `tls_ctx_load_verify_locations` / `tls_ctx_set_verify_paths` /
> `tls_ctx_use_certificate_file` / `tls_ctx_use_private_key_file` — backend-agnostic
> (native via `tls_native_set_ca_bundle`/`set_ca_system`; libssl via dlsym), return
> 1=success (sandhi's `!= 1` contract). **mTLS half (net-new):** a `tls_native`
> CLIENT now presents its own cert (TLS 1.3 client `Certificate` + `CertificateVerify`
> in `tls_native_client_finish`; new `tls_native_set_client_cert`/`set_client_key`;
> parameterized `_tn_build_cert_verify` for the client label), and the server side is
> wired into `tls_native_accept` to read+verify it. ECDSA-P256/P384 + Ed25519. New
> ctx slot `CERT_REQUESTED` (LEN 472→480). **VERIFIED:** `tls_native_mtls_client.tcyr`
> 9/9 (client↔server loopback, positive + strict-`FAIL_IF_NO_PEER_CERT`-rejects);
> existing TLS suites byte-identical (no-mTLS path unchanged); check.sh **89/89**;
> compiles Linux/libssl-variant/Mach-O/agnos; agnos gate 4/4; api-surface 4306→4340
> (additions only); bench ~513 ms flat / cycc 1,063,800 B byte-identical; cross-OS
> **SELFHOST_OK ecb/pi/cass**. 7-agent adversarial security review: no auth-bypass /
> nonce-reuse / overflow; P-384 client-CV verify added + the server-CV-signature-only
> (not client-chain-trust) limitation documented + tracked. Deps refold sandhi
> 1.5.3→1.5.5, mabda 3.0.4→3.1.0. sandhi retiring its `tls_dlsym` callers onto the
> typed wrappers is its follow-up slot. **NEXT:** the remaining v6.2.x pins —
> bare-metal target formalization + RISC-V rv64. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-15):** **v6.2.7 CUT — sandhi-driven stdlib AGNOS-completeness
> pass + IPv4 multicast + dep refresh.** sandhi filed two issues at its 1.5.3
> close: (1) `thread-agnos-clone-dispatch` — `lib/async.cyr`'s `SYS_EPOLL_CREATE1`
> is the next `--agnos` blocker after `thread.cyr`, and asked for a *systematic
> agnos-completeness pass*; (2) `mdns-multicast-primitives` — `lib/net.cyr` lacks
> IPv4 multicast. An adversarial audit walked the whole sandhi-from-source
> `--agnos` bundle and found the full cascade. **FIX:** `async.cyr` peer-split →
> `async_agnos.cyr` (serial; agnos has no epoll_create1/fcntl/fork/wait4);
> `net.cyr` gained IPv4 multicast helpers (`net_join_multicast` + `sock_reuseport`
> + per-target `IpOpt`, Darwin consts live-checked on ecb) **and** AGNOS guards on
> `sock_reuse`/`sock_set_recv_timeout`/`sock_shutdown` (raw #54/#48 silently
> mis-dispatched to udp_unbind/sock_send); `regression.cyr` peer-split →
> `regression_agnos.cyr` (fork+exec fail-closed) + portable `regression_network_probe`
> (raw `syscall(41)` was `SYS_SLEEP_MS` on agnos); `ws.cyr` raw `syscall(0/1)` →
> `sys_read`/`sys_write` (agnos `syscall(0)`=`SYS_EXIT` — read was a process-kill
> landmine). **Refold:** sandhi 1.4.11→1.5.3 (its C1/C2 guards the 20 SYS_FCNTL
> sites), mabda 3.0.2→3.0.4, patra 1.11.1→1.11.2 — zero breaking removals.
> **VERIFIED:** full sandhi-bundle `--agnos` probe has **zero agnos-specific
> undefined symbols** (residual `fdlopen_*`/`sakshi_span_*` warnings are identical
> on Linux = probe-include completeness); check.sh **89/89**; api-surface 4260→4306
> (additions only); agnos gate 4/4 (new probe 1c); compiles on Linux/Mach-O/agnos;
> bench ~509 ms flat / cycc 1,063,800 B byte-identical; cross-OS **SELFHOST_OK
> ecb/pi/cass**. AGNOS kernel-gaps filed upstream
> (`agnos/docs/development/issues/2026-06-15-cyrius-stdlib-missing-syscalls.md`).
> Remaining agnos-completeness (host-side test modules beyond the sandhi consumer
> bundle) tracked there. **NEXT:** the remaining v6.2.x pins — bare-metal target
> formalization + RISC-V rv64. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-14):** **v6.2.6 CUT — chrono AGNOS monotonic-clock + sleep
> bound to the real kernel syscalls.** `lib/chrono.cyr`'s AGNOS branches for
> monotonic time + sleep were fixed-0 / no-op stubs (the obsolete "no monotonic/
> sleep syscall in the frozen 0-33 surface" assumption) — but AGNOS has had
> `uptime_ms`#40 + `sleep_ms`#41 since kernel 1.43.x. Result: monotonic time read
> 0 and `sleep_ms` busy-spun on AGNOS, forcing the v6.2.5 `dig`/`yo` net-tool
> backends to re-roll a direct-syscall workaround. **FIX:** added `sys_uptime_ms`
> (#40) + `sys_sleep_ms` (#41) wrappers (new `SysNrAgnosTimer` enum, the 1.43.x
> timing band) to `lib/syscalls_x86_64_agnos.cyr`; chrono `clock_now_ns()` →
> `sys_uptime_ms()*1e6`, `sleep_ms()` AGNOS branch → `sys_sleep_ms(ms)` (guards
> `ms<=0`). Wall-clock (#46) was already correct @6.2.3 — this is the monotonic+
> sleep counterpart. **VERIFIED:** agnos emit inspected (`mov eax,40/41; syscall`
> at wrapper sites); `agnos-crossbuild-gate.sh` extended with a chrono monotonic/
> sleep probe (anti-re-stub guard) — 3/3 PASS; x86 self-host byte-identical
> (cycc 1,063,800 B — chrono not in cycc); check.sh 89/89 (api-surface
> re-baselined 4260, +2 non-breaking); cross-OS byte-identical ecb/pi/cass
> (`SELFHOST_OK`); bench ~510 ms flat. `dig`/`yo` AGNOS backend migration to the
> portable chrono API is the consumer-repo (AGNOS-side) agent's follow-up.
> Issue `2026-06-14-chrono-agnos-monotonic-sleep-stale-stubs.md` resolved.
> **NEXT:** the remaining v6.2.x pins — bare-metal target formalization +
> RISC-V rv64. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-14):** **v6.2.5 CUT — `tls_native.cyr` module split.** The
> 5,857-line monolith → a 302-line include-hub (deps + shared enums/consts) + 6
> focused modules: `_lowlevel` (299, wire/record/transcript), `_keysched` (588,
> 1.3 key schedule + ciphersuite registries), `_ctx` (237, ctx + new_client/
> server), `_hs13` (1,930, full TLS 1.3), `_hs12` (1,712, full TLS 1.2), `_conn`
> (806, verify + the 6.2.4 transport vtable + connect/accept + I/O + getters).
> **STRICTLY logic-preserving via ORDER-PRESERVING block moves:** each module is
> a contiguous slice included at its original position, so the preprocessed text
> is unchanged. **PROVEN byte-identical:** concatenating the 6 slices reproduces
> the pre-split file exactly (`cmp` clean) → the compiler sees identical code by
> construction. **VERIFIED:** scaffold 448/448 + realpeer + tls12_* + vtable +
> live round-trip all green; x86 self-host byte-identical (cycc 1,063,800 B —
> tls not in cycc); check.sh 89/89; compiles x86+agnos+aarch64; cross-OS
> byte-identical pi/ecb/cass; **downstream `cyrius deps` pulls all 6 new files
> via the transitive include-scan (verified end-to-end with a simulated
> consumer build)**; api-surface 113 tls fns relocated, name+arity UNCHANGED
> (bare-fn-set diff empty), re-baselined. Documented 2 public fns the per-file
> cyrdoc surfaced (`tls_native_client_recv_flight`, `tls_native_seal_app`).
> bench ~512 ms flat. **v6.2.x TLS arc (vtable→split) COMPLETE.** **NEXT:** the
> remaining v6.2.x pins — bare-metal target formalization (consumes the 6.2.4
> transport vtable for kernel-freestanding TLS) + RISC-V rv64. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-14):** **v6.2.4 CUT — TLS transport-vtable refactor
> (Option C), the kernel-freestanding-TLS enabler.** Decoupled `tls_native` from
> raw `sys_read`/`sys_write`/`_tn_now_unix` so the AGNOS bare-metal kernel can
> plug its own TCP send/recv + RTC. **MODULE-GLOBAL vtable** (3 fn-ptr globals
> `_tn_tx_read`/`_write`/`_now`, 0=default → `&sys_read`/`&sys_write`/the
> per-target `_tn_now_unix` body) routed in the 2 leaf helpers
> (`_tn_sock_read_full`/`_tn_sock_write_all`) + `_tn_now_unix`; public
> `tls_native_set_transport(read,write,now)`; per-conn handle still flows via
> `TLS_CTX_OFF_SOCK_FD`. **Chose global over per-ctx deliberately:** the
> transport impl is process-wide, so global = **ZERO change to the 25 `_tn_sock_*`
> call sites** → a missed site (the untyped-cyrius silent-miscompile risk that
> bit 6.2.3 `sock_connect`) is impossible by construction; the 1.2 driver +
> app-data I/O + KeyUpdate ride the same leaf helpers, covered for free. CA-bundle
> FILE I/O correctly NOT routed. **STRICTLY logic-preserving** — default path
> behaviorally byte-identical. **VERIFIED:** all TLS gates green
> (`tls_native_scaffold` 1.3 handshake, `tls_native_realpeer` live 1.1.1.1,
> `tls12_*` driver, `tls_wrapper_native`, new `tls_native_transport_vtable`
> 12/12); x86 self-host byte-identical (cycc 1,063,800 B, tls not in cycc);
> check.sh 89/89; tls_native still cross-builds agnos; **4-agent adversarial
> review = no real bugs** (confirmed 6.2.3 agnos tagged-fd routing preserved
> through the default; global-model footguns are fn-ptr-config contract items,
> documented in the setter); cross-OS byte-identical pi/ecb/cass, ach DNS-down
> (CI covers); bench ~511 ms flat; api-surface +1 (4258, non-breaking).
> **NEXT (v6.2.5):** full `tls_native.cyr` module split + cleanup (5,786-line
> monolith → focused modules, strictly logic-preserving). **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-14):** **v6.2.3 CUT — AGNOS net/entropy/clock syscall peer
> (#45–#55), the TLS + net-tools-on-agnos enabler.** Mirrored the eleven ring-3
> syscalls AGNOS 1.45.0–1.45.4 froze into `lib/syscalls_x86_64_agnos.cyr`
> (`sys_time_unix`#46, `sock_*`#47–50, `udp_*`#51–54, `icmp_echo`#55; **un-fail-
> closed `sys_getrandom`→#45**). **No codegen change** — the 4-arg `a4=r10`
> convention (`sys_rename`/`link` already use it) lowers #52/#53; emit-verified
> (`pop r10`). **Option A** (per user; Option C transport-vtable refactor pinned
> for **v6.2.4**): a tagged-fd↔conn_id 8-slot table routes the BSD-shaped
> `net`/`tls_native`/`http` (all bottom out at `sys_read`/`write`/`close`) onto
> AGNOS's conn_id socket model, keeping consumers **source-identical**; the agnos
> `sys_read` blocking-polls AGNOS's inverted recv sense (0=WOULD_BLOCK,−1=EOF)
> back to Linux read semantics. `chrono.clock_epoch_secs`→#46; `tls_native
> ._tn_now_unix`→#46. **Discovered prereq (committed through):** `tls_native`→
> `sigil`→`thread.cyr` and agnos has no clone/futex, so added
> `lib/thread_agnos.cyr` — single-threaded serial fallback (inline `thread_create`,
> no-op mutex, FIFO chan) mirroring `thread_win`/macOS, **with TLS save/zero/
> restore around the inline body** (emulates a real `CLONE_SETTLS` worker's fresh
> block so a worker's `thread_local` write can't leak past join and corrupt
> sigil's main-thread crypto bank). `net.cyr` BSD UDP/server shims fail-loud on
> agnos (UDP→raw `sys_udp_*`; inbound TCP = Phase B). **VERIFIED:** x86 self-host
> byte-identical (cycc 1,063,800 B, pure stdlib); check.sh 89/89; agnos
> cross-build gate PASS (probe + **new net/TLS peer probe** + agnoshi); emit
> #45–#55 + #47-not-#42 + zero Linux socket syscalls on agnos path; **13-agent
> adversarial review caught 2 real bugs (missing `sock_connect` agnos branch +
> `thread_create` TLS-leak) — both fixed + re-verified**; cross-OS self-host
> byte-identical **pi/ecb/cass** (`SELFHOST_OK`), **ach unreachable this cut**
> (CI covers macOS-x86; cycc byte-identical on the other 3 incl ecb macOS-arm64);
> bench self_compile ~511 ms (flat). Proposal
> `2026-06-14-agnos-net-entropy-clock-syscalls.md` resolved; filed
> `2026-06-14-sandhi-nonblocking-connect-not-agnos-ported.md` (vendored, off the
> 6.2.3 path). **NEXT (v6.2.4):** Option C TLS transport-vtable refactor (also
> unblocks the bare-metal kernel-freestanding-TLS slot). **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** **v6.2.2 CUT — aarch64/macOS annotation-token codegen
> fix + ecosystem stdlib fold-in.** **Fixed** the pass-1/pass-2 annotation-token
> desync (same class as the v5.8.21 `#io` fix that only landed x86-side): the three
> non-x86 compiler entry points (`main_aarch64.cyr`, `main_aarch64_macho.cyr`,
> `main_x86_macho.cyr`) never consumed the fn-attribute tokens 109/122/124/125/126/127,
> so an annotated fn (bayan's `#pure fn bayan_u128_eq`) terminated each scan loop
> early and the next `enum` (bayan's `TomlError`) tripped `error: unexpected enum` —
> blocking `bayan` (and any annotated stdlib) on aarch64+macOS. Ported the consume
> into all three forks, both passes; aarch64/macOS gate the opts off so they
> consume-and-ignore (no `_*_pending`). x86 `main.cyr` untouched → x86 cycc
> byte-identical. **Changed** — re-folded all 12 vendored `lib/*.cyr` to their
> released 6.2.1-pinned versions (agnosys 1.4.2, sandhi 1.4.11, sankoch 2.3.1,
> niyama 1.0.5, bayan 1.0.1, ganita 1.0.1, patra 1.11.1, yukti 2.2.5, vani 0.9.5,
> sigil 3.7.13, mabda 3.0.2, sakshi 2.3.0); api-surface re-snapshotted (4236 fns,
> +26/−1). **VERIFIED:** issue repro + bayan-via-deps build clean on aarch64
> (qemu exit-0); x86 self-host byte-identical; check.sh 89/89; cross-OS self-host
> byte-identical 4/4 (pi/ecb/ach/cass `SELFHOST_OK`); bench self_compile 498 ms /
> cycc 1,063,800 B (flat). Issue `2026-06-12-main-aarch64-pass1-missing-annotation
> -tokens-unexpected-enum.md` resolved. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** **v6.2.1 CUT — element-typed arrays `var a: T[N]` +
> daimon-class slot-array sweep.** Resolves the address-taken-local byte-vs-slot
> footgun (daimon route-404). **Added** `var a: T[N]` = N elements of T, sized
> `N*sizeof(T)` identically in fn + top-level scope — `i64[N]` is the unambiguous
> SLOT spelling (fixes the `store64(&a+i*8)` idiom), `u8[N]` an explicit byte
> buffer; widths i8..i64/u8..u64/u128. Pure frontend: element width → `0x12A000`
> var-size table → every backend inherits it (zero backend edits). **Fixed** 10
> cyrius-owned daimon-class sites a fan-out audit confirmed (17 total): 5 in cycc
> itself (`PARSE_SWITCH`/`PARSE_MATCH` `ends`×3+`seen_vcnt` capped at 32 not 256
> slots; `_fc_simd_table` OOB past arg 0) + 5 native stdlib (`regex`
> splits/splits2, `pwd`/`grp` field_starts, `net` sa sockaddr) → `i64[N]`.
> Migrating cycc's own arrays needed the **two-step bootstrap** (stage_b==stage_c).
> **Held for release:** 8 ecosystem-stdlib sites patched in *source* (sigil ×6
> attestation cert-chains — the source check caught one the fold-audit missed;
> sakshi `ts` timespec hot-path; agnosys `bc_buf` fmt) → re-fold after each lib
> releases ([`issues/2026-06-12-ecosystem-lib-daimon-class-refold.md`](issues/2026-06-12-ecosystem-lib-daimon-class-refold.md)).
> **VERIFIED:** self-host byte-identical (1-step x86 + 2-step internal); check.sh
> 89/89; cross-OS 4/4 (pi/ecb/ach/cass `SELFHOST_OK`); differential 252/252; tcyr
> 175/175 (+`element_typed_array`, +40-case switch); cross-arch aarch64(qemu)+PE(wine)
> exit-42; bench self_compile 509 ms / cycc 1,063,800 B. Issue archived.
> **NEXT:** ecosystem-lib re-fold (above) once sigil/sakshi/agnosys release;
> remaining v6.2.x — bare-metal + RISC-V rv64. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** **v6.2.0 CUT — Platform Expansion opens with Phase 0 COMPLETE.**
> Four bites: (1) **`fixup_tbl` → growable** (`_fixup_base`/grow, 64M-entry ceiling); (2)
> **`cyrius init` CI/release** aligned to the patra/sigil toolchain workflow (canonical
> `install.sh` one-liner replacing the hand-rolled curl+tar+cp; release publishes a
> `git archive` source tarball + `SHA256SUMS` so scaffolds are dep-consumable; `VERSION`
> file as single source of truth + `version = "${file:VERSION}"`); (3) **fn-tables →
> growable** (16 parallel tables + 2 cap-sized hashes + the `live[]` DCE bitmap → `_fnt_*`/
> single `_fnt_cap`, grow+rehash, 32768 ceiling — cycc was at **79 %** of the 8192 cap);
> (4) **codebuf → growable** (`_codebuf_base`/grow, 64 MiB ceiling, 64 B guard-band for the
> disp32 RMW; cx's separate 0x54A000 stays fixed). **Phase-0 growable-region foundation
> COMPLETE** — ends the cap-raise treadmill + AR-03 split-brain; the v6.3.x generics arc
> opens onto already-growable tables. cycc 1,055,784 B (+5,176 B growth-tax). Each migration
> verified 6 ways: byte-identical self-host + differential corpus + forced-grow on x86 AND
> real-ARM (pi) + check.sh 89/89 (aarch64-EB-cap gate updated to the growable invariant) +
> cross-OS 4/4 (pi/ecb/ach/cass `SELFHOST_OK`). bench self_compile ~497 ms (flat). Remaining
> v6.2.x: bare-metal target formalization + RISC-V rv64 (inherits the growable pattern).
> **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** v6.1.41 cut — **pre-v6.2.0 closeout hardening** (3-dimension
> closeout audit caught 3 residuals the per-slot reviews missed). **(P1) Mach-O
> output-cap parity** — CVE-23 (v6.1.35) missed both `EMITMACHO_*` writers (capped
> code only, not `var buf[N]` globals/strings/__LINKEDIT); a large-globals macOS
> program overran output_buf into the .40 local tables at `0x5D9D000` → silent heap
> corruption. Both now use `_check_output_cap` on the true on-disk size. **(P2)
> security-reject return code** — path-traversal/absolute include rejects `return 0`
> → PP treated as empty include → `include "/etc/passwd"` exited **0**; now `-1`
> (fatal). New reject-gate case (4/4). **(P1·latent) IR counters** relocated out of
> fixup_tbl (`0x174A0xx`→`ir_state 0xF3A0xx`; collided at ≥446k fixups+CYRIUS_IR).
> Cleanup: byte-length over-count `fixup.cyr:1992` the .39 single-line regex missed
> (multi-line scan now clean); dead `GFVA` removed (63→62, −256 B); stale heap-map
> comments. **VERIFIED:** fixpoint converged (1,050,608 B); macho cross-compilers
> build; check.sh 89/89; ecb/ach/pi/cass `SELFHOST_OK` (Slot 1 on macOS); bench
> ~497 ms. **NEXT (v6.1.42 = closeout doc-sync pass):** vidya/doc currency refresh
> (version-bump.sh doesn't touch vidya — the two GONE-file stdlib entries base64/csv→
> bayan are FIXED; version refs .27→.41 pending), downstream cyrius.cyml pin check
> (informational only — deps adjust downstream, not a cyrius issue), doc-health
> ledger, bootstrap-closure verify. **The daimon "static under-reservation" was
> RE-DIAGNOSED 2026-06-12** (disasm: `var parts[4]` = 8 bytes = the documented N-bytes
> *local* convention, NOT a `(N-1)*8` off-by-one; daimon's `store64(&local+i*8)` uses
> the *global* N-slots idiom on a local) → working-as-documented MEDIUM DX footgun,
> moved to **v6.2.x Language Refinements**, NOT a v6.1.42 codegen fix —
> [`issues/2026-06-11-addr-taken-local-array-static-underreserve.md`](issues/2026-06-11-addr-taken-local-array-static-underreserve.md).
> **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** v6.1.40 cut — **CVE-24: per-fn local-table overflow (grow + cap).**
> Closes the 6th/final F3 item (deferred from .38 after the audit premise proved
> wrong). `SFLC`/`local_cnt` counts stack-frame SLOTS not vars (a `stack var buf[N]`
> registers N/8 fillers), so the 4 slot-indexed tables (fn_local_names/depths 256,
> types/slice 576) silently overran on any frame >~2 KB. Fix: **relocate** all 4 to
> the heap top (`0x5D9D000`/`0x5DBD000`/`0x5DDD000`/`0x5DFD000`, appended above
> output_buf) + **grow to 16384 slots (128 KB frames)** each; S-region size bumped
> `0x5D9D000`→`0x5E1D000` (+512 KB) in all 7 driver heap-init sites (main_win already
> `0x5F00000`); `SFLC` caps at 16384 (loud error vs silent overflow). ~46
> fn_local_names + 6 accessor refs relocated; the `lex_pp` 16 KB file-scratch sharing
> `0x191800` is untouched. **VERIFIED:** self-host byte-identical (+160 B);
> ecb/ach/pi/cass `SELFHOST_OK` (per-target heap bumps on real hardware — a missed
> bump → unmapped table → instant self-host crash); `stack_var.tcyr` 4/4 (16 KB
> big_frame round-trips, was a silent overflow); new reject-gate case (3/3) caps a
> 200 KB stack var; check.sh 89/89; bench ~497 ms. Heap-map docs synced; issue
> archived. **F3 PACK COMPLETE (6/6); the 2026-06-10 deep-dive urgent set is done.**
> **NEXT:** dep-fold cycle-close → v6.2.0; bug bandwidth as filed. (Follow-up noted:
> a permanent check.sh gate for syscall-write byte-lengths, from the .39 audit.)
> **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** v6.1.39 cut — **diagnostic `syscall` byte-length audit.**
> Swept all 539 `syscall(SYS_WRITE,…,"…",LEN)` strings in src/+lib/; fixed **27**
> with a wrong `LEN` (16 em-dash undercounts — UTF-8 `—`=3 B counted as 1 →
> truncated message; 11 off-by-one incl. a few over-counts → `write` over-reads
> adjacent `.rodata`). Each `LEN` now the exact byte count. Data-only (length
> immediates) → cycc byte-identical, **size unchanged** 1,050,704 B. **VERIFIED:**
> re-audit 0 mismatches; self-host byte-identical; check.sh 89/89; ecb/ach/pi/cass
> `SELFHOST_OK` (fixes touch aarch64/macho/win emit paths); bench ~510 ms (flat).
> Issue [`2026-06-12-diagnostic-syscall-byte-length-audit.md`](issues/2026-06-12-diagnostic-syscall-byte-length-audit.md)
> notes a permanent recurrence-prevention check.sh gate (follow-up).
> **NEXT (queued, v6.1.40):** CVE-24 grow-and-cap — premise-check showed it's a
> fragile **75+-ref heap relocation** (the 4 slot-indexed local tables must move to
> a fresh 256 KB block; macro tables block in-place growth; direct slot reads +
> `lex_pp` file-scratch alias are special cases). Its own slot, not a fold-in.
> [`2026-06-12-locals-table-slot-indexed-overflow.md`](issues/2026-06-12-locals-table-slot-indexed-overflow.md).
> **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-12):** v6.1.38 cut — **Phase F pack F3: memory-safety parity,
> CVE-25/26/27/28 + AR-03** (2026-06-10 deep-dive; **5 of 6 — CVE-24 deferred**).
> **CVE-26** agnos `alloc()` pre-lock size guards (neg `size`→backward bump→overlap)
> + local `ALLOC_MAX`. **CVE-25** `_sb_grow` propagates OOM rc; 5 str-builders abort
> via `_sb_die()`. **CVE-28** aarch64 atomics had NO barrier (bare `ldxr`/`stxr`; the
> `dmb ish` docs claimed was never emitted) → `ldaxr`/`stlxr` acquire/release (1-bit
> opcode change `0x7C`→`0xFC`, branch offsets intact) + `default_alloc` vtable-publish
> fence. **CVE-27** PE import-registry count+name-buffer bounds (arrays already
> 256/4096 — global `var x[N]`=N i64 slots; the "32 slots" comments were wrong,
> corrected). **AR-03** fixup cap 4× under its 16 MiB region since v5.7.7 — unified 10
> checks 262144→1048576 (+GFCNT diagnostics, main_win even staler at 16384);
> `jump_target_tbl` off-by-one fixed in ALL 4 accessors (EJMP/EPATCH writers `<1023`,
> IS_JUMP_TARGET+compaction readers clamp the 1024 sentinel).
> **CVE-24 DEFERRED** — the audit premise was wrong: `SFLC`/`local_cnt` counts
> stack-frame *slots* not variables (a `stack var buf[N]` registers N/8 fillers), so a
> count cap breaks sanctioned large frames (`stack_var.tcyr::big_frame` 16 KB). The
> naive guard was implemented then reverted; real fix re-scoped to
> [`issues/2026-06-12-locals-table-slot-indexed-overflow.md`](issues/2026-06-12-locals-table-slot-indexed-overflow.md).
> **VERIFIED:** self-host byte-identical x86+aarch64(qemu)+PE(wine); ecb/ach/pi/cass
> `SELFHOST_OK`; CVE-28 on REAL pi (atomics.tcyr 4-thread, `ldaxr`/`stlxr`
> disasm-confirmed `c85ffc04`/`c805fc02`); check.sh 89/89; 4-dim
> adversarial-review-the-diff caught the jump fix touching only 1 of 4 accessors
> (self-host-invisible @ 1023+ targets; v6.1.35 CVE-23 class) + the post-bump
> `big_frame` regression that surfaced the CVE-24 mis-scope. cycc +736 B → 1,050,704 B;
> bench self_compile ~496 ms. **user pushes/tags after CI.**
>
> ---
>
> **Prior (2026-06-11):** v6.1.37 cut — **const chained-multiply miscompile**
> (cyrius-doom). `A*B*C` with const A,B folded to `B*C` (first operand dropped,
> `320*200*4`→800). Premise-check: NOT agnos-only — all targets. Shared
> `parse_expr.cyr` left `_cfo` set after PARSE_FACTOR re-armed const-fold on a const
> RHS, so the next `*` folded off the stale RHS + rewound, discarding the runtime
> EIMUL; fix clears `_cfo` after the EIMUL in the 3 `_cfo==1` sub-branches. Self-host
> byte-identical; 89/89; ecb/ach/pi/cass SELFHOST_OK; regression
> `const_chained_multiply_fold.tcyr` 8/8.
>
> **Phase F COMPLETE (F1+F2+F3 shipped):** next is the dep-fold cycle-close → v6.2.0.
> See [roadmap.md](roadmap.md) Phase F. Open downstream (Low, not a slot):
> [`issues/2026-06-11-thoth-lib-sync-ignores-deps-stdlib.md`](issues/2026-06-11-thoth-lib-sync-ignores-deps-stdlib.md);
> follow-on filed: [`issues/2026-06-11-windows-entropy-primitive.md`](issues/2026-06-11-windows-entropy-primitive.md) (Win/AGNOS real CSPRNG).
>
> **Carry-forward (.32 agnos fix):** run-on-agnos `argc=4` was NOT verified locally —
> `cyrius build --agnos` on this box sets the `#ifdef` but not the runtime `_TARGET_AGNOS`
> env (direct `env CYRIUS_TARGET_AGNOS=1 cycc` works; pre-existing, suppressed the OLD
> capture too). Confirm on a real attn11/agnoshi build + investigate the wrapper
> env-propagation gap separately.
>
> **Still OPEN — x86-macOS-usable arc (.30 shipped phase 1 = argv prologue; follow-up slots,
> ach-gated):** (1) env (`_read_env`/`_macho_fill_environ` → HOME/uname); (2) wrapper's
> aarch64 arch-default on macOS (`cbt/cyrius.cyr set_arch` — detect x86 on Intel); (3)
> cycc-finding; (4) **issue-1** native miscompile (broken 323 KB wrapper vs 610 KB
> cross-built — ship cross-built until fixed); (5) packaging.
> **Follow-on (.28, still open):** agnosys can drop `src/syscall.cyr` for `lib/sys.cyr`.
> Phase E (bayan .25 + ganita .26) stays DONE. **Still deferred to v6.1.x closeout (heap-map
> audit §4):** re-sort the `output_buf` comment line + reclaim the 2 MB gap at `0x71A000` (.27).
> **NOT fixed (separate, still OPEN):** sandhi's own Darwin non-blocking-connect
> constants (`issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md`) —
> needs an upstream sandhi fix + re-fold.
> **Deferred polish:** relocate the 64 KB `_ts_cst` scratch to the ts_base heap.
>
> **Kernel-PIE boot-test readiness** (the v6.1.7 wrapper — still pending an AGNOS
> `--pie` harness): build an x86 PIE kernel with `cat <kernel.cyr with 'kernel;'> |
> CYRIUS_PIE=1 build/cycc > k.elf` → **ET_DYN, p_vaddr=0, e_entry=0xA8**, RIP-
> relative `.text`. The boot shim (AGNOS gnoboot) must handle ET_DYN: pick a base,
> slide the single PT_LOAD, jump to `base + 0xA8`. gnoboot-boot validation +
> aarch64 kernel-PIE remain the consumer-gated follow-ons.

## v6.1.x — CLOSED (Backend Codegen Multi-Arc)

> **v6.1.x closed at .41; v6.2.x is the active cycle** — see *Current state* +
> the handoff above. The per-release detail below is retained for convenience
> but is canonical in [CHANGELOG.md](../../CHANGELOG.md) +
> [completed-phases.md](completed-phases.md); still-open carry-ins live in
> [roadmap.md](roadmap.md). (This block is a candidate to trim to a pointer at
> the next state consolidation.)

Whole-v6.x cycle: [roadmap_6.md](roadmap_6.md).

**Shipped (all 2026-06-08):**
- **v6.1.0** — clean cycle cut: roadmap split into 3 tiers (roadmap.md active /
  roadmap_6.md cycle / roadmap-future.md beyond) + full docs sweep + `build/`
  prior-major slot corrected `cc3 → cc5` + **benchmark-every-release gate**
  (CLAUDE.md Release rule #6).
- **v6.1.1** — Phase A: back-compat symlink drop (install `cc5`/`cyrc`
  symlinks + `cbt/core.cyr` cc5 fallback + repl shim). cycc untouched.
- **v6.1.2** — Phase A: aarch64 `EADDRA_IMM` >4095 fix (12-bit-mask → low+hi
  adds + movz/movk guard). Latent pre-existing; verified on pi + ecb.
- **v6.1.3** — Phase A: POSIX `*at()` family + bare-name peers (`sys_link`/
  `lstat`/`rename`) — **and the aarch64 ESYSXLAT collision fix it forced**:
  native `newfstatat`(79)/`utimensat`(88) collided with x86 `getcwd`/`symlink`
  → stdlib emits x86 262/280, ESYSXLAT renumbers. **Repaired `sys_stat`
  silently broken on native aarch64 since v6.0.41** (found-by-ports).
- **v6.1.4** — Phase B: hoist `_TARGET_*` + `_emit_fmt` to
  `src/backend/common/runtime.cyr` (logic-preserving). `_entry_base` stays
  per-arch (premise-check: arch-specific VAs, not a dup).
- **v6.1.5** — Phase B (final): DCE mark-and-sweep probe consolidation —
  `_dce_hash_lookup` + `_dce_host_fn` hoisted to `common/runtime.cyr`, collapsing
  4 hash-probe blocks → 1 and 4 host-fn scans → 1 across the two `fixup.cyr`
  backends. Logic-preserving (−51 LOC, cycc −752 B). Verified byte-identical via
  338-input old-vs-new corpus + DCE-torture (report + `CYRIUS_DCE=1` NOP-fill,
  both arches) + a 4-reviewer adversarial workflow + pi/ecb/cass self-host.
- **v6.1.6** — Phase C (PIE): `--pie` / `CYRIUS_PIE=1` position-independent codegen
  x86_64. Ships **working userland PIE executables** (ET_DYN, RIP-relative) —
  validated by running the full 169-test `.tcyr` corpus as ASLR'd PIE binaries +
  a new check.sh gate. **Premise correction**: PIE was ~80% pre-built via
  `shared`/object `_IS_OBJ` (proven), so this widened the gate + fixed the one
  ungated site (`EVADDR_X1`) rather than greenfield; the fn-ptr/vtable "awkward
  case" was a non-issue. Non-PIE byte-identical (338-input differential). Kernel-PIE
  ELF (AGNOS KASLR) is a follow-on (needs the AGNOS `--pie` boot harness; no live
  pull). See CHANGELOG [6.1.6].
- **v6.1.7** — packed (user-directed): (1) **Windows COM/DXGI `.rdata` corruption
  fix** (ai-hwaccel consumer bug) — function-local arrays are `.rdata` globals and
  the m128 array padding was computed against the ELF base in `FIXUP` but the
  unpadded sum in `_pe_layout`, so `&desc` (GetDesc1's out-param) drifted +8 into
  the string region and its write smashed `"true"`. Fixed by padding against the PE
  gvar VA base in both. Diagnosed debugger-free via exit-code probes on real-GPU
  cass; GPU-confirmed (60→42). PE-only → ELF/aarch64 byte-identical. (2) **Kernel-PIE
  ELF wrapper** — `EMITELF64_KERNEL` emits ET_DYN+p_vaddr=0+`e_entry=0xA8` under
  `--pie` (the deferred v6.1.6 pickup); structurally validated, gnoboot-boot pending
  the AGNOS harness. See CHANGELOG [6.1.7].
- **v6.1.8** — Phase C (PIE, Sub-arc B): **aarch64 PIE** — `--pie`/`CYRIUS_PIE=1`
  reuses the proven Mach-O `adrp`/`add` PIC path for ELF (6 address-emit sites + 3
  fixup branches gated on `_TARGET_MACHO==2` now also fire for `_pie_mode`; ELF
  emitter → ET_DYN+p_vaddr=0; `FIXUP_ADRP_ADD` uses `_entry_base`, Mach-O
  byte-identical). **Completes the PIE arc on both arches.** Validated: full tcyr
  corpus as aarch64 PIE on **pi (real ARM)** — exit-code parity with non-PIE, zero
  PIE-only failures; 338-input non-PIE byte-identical; pi/ecb/cass self-host; x86
  cycc untouched. See CHANGELOG [6.1.8].
- **v6.1.9** — Phase C tail (Sub-arc C): **`.gnu.hash` migration** — `EMITELF_SHARED`
  (x86 `fixup.cyr`) emits a single-bucket `.gnu.hash` + `DT_GNU_HASH` instead of
  SysV `.hash`/`DT_HASH`. The native loader (`lib/dynlib.cyr`) was **already**
  gnu-hash-only — it never read `DT_HASH`, so cyrius `.so`s were resolving via the
  linear `.dynsym` fallback over a dead SysV table; this flips them onto the O(1)
  Bloom path. x86-only (aarch64 has no `.so` path). cycc byte-identical self-host;
  dlopen gate resolves *through* gnu.hash (exit 99); cass/pi/ecb cross-OS green.
  The v5.6.38 pin, closed. See CHANGELOG [6.1.9].
- **v6.1.10** — Phase D **prereq** (mini-arc): **TS children-list allocator fix**.
  Premise-check found the TS parser builds a CORRUPT AST for every nested list
  (`TS_AST_CHILDREN_RESERVE` didn't advance the pool cursor → sibling lists
  overlapped); `--parse-ts` passed only because nothing read lists back. Fixed via
  deferred construction (`TS_CST_PUSH`/`FLUSH`) across all value builders + the
  `<T,>` trailing-comma generic-param parse fix. New `cycc --emit-js` walks the AST
  to a stable kind-S-expr and **self-validates** (exits non-zero on overlap —
  proven to catch a re-broken allocator); check.sh gate 87. TS frontend is
  x86-Linux-only. cycc +79 KB / self_compile +61 ms (new module; documented
  growth-tax). x86 self-host byte-identical; cass/pi/ecb green. See CHANGELOG [6.1.10].
- **v6.1.11** — Phase D proper: **TS/TSX → JS emitter** (`cycc --emit-js` emits real
  browser JS). AST-driven (`src/backend/js/emit.cyr`): type-strips interfaces/
  aliases/annotations/`as`/`!`/generics/`?`; lowers JSX → `h(tag, props, ...kids)`
  (pragma configurable via `CYRIUS_JSX_PRAGMA`, default `h`, + a standalone `h`
  runtime prelude); ESM passthrough with type-only export pruning; verbatim
  string/template literals. The consumer's **app.tsx emits valid runnable JS**
  (node --check + `--parse-ts` round-trip + stub-DOM run all pass). `_ts_walk_gate`
  upgraded to emit→round-trip. x86-Linux-only; cycc +24.7 KB. Closes the SY
  `yeo-cy-test` ask. **Phase D mini-arc COMPLETE.** See CHANGELOG [6.1.11].
- **v6.1.12** — agnos `getenv` HIGH-sev fix + Phase D edges. (1) `lib/io.cyr`
  `getenv()` guards its 8 KB `/proc/self/environ` reader behind
  `#ifndef CYRIUS_TARGET_AGNOS` — the buffer was compiled past the agnos early
  return (agnoshi #PF). **Verified it's `.bss` static, not a stack frame** as the
  issue assumed (agnos `.bss` −8,208 B, `.text` −928 B). (2) `cyrius build
  --target=js` CLI wrapper over `cycc --emit-js`. (3) Indented JS output (AST-
  driven structural newlines). (4) **Fixed a pre-existing bug: every for /
  for-of / for-in header emitted invalid JS** (`;;` / `; of ` / `; in ` — the
  loop binding kept its statement `;`); shipped silent in 6.1.10/.11 (consumer
  had no loops); `_ts_walk_gate` now scans for it + fixture coverage. See
  CHANGELOG [6.1.12].
- **v6.1.13** — agnos `fnptr` HIGH-sev fix (agnoshi): `lib/fnptr.cyr` `fncall0..8`
  had no `CYRIUS_TARGET_AGNOS` asm branch → indirect calls returned 0 → null
  allocator vtable #PF. Added the agnos+x86 SysV branch in-place. cycc flat
  (stdlib-only); ecb/cass green. See CHANGELOG [6.1.13].
- **v6.1.14** — agnos `argc()`/`argv()` HIGH-sev fix (bannermanor): the init-rsp
  capture sat in the entry epilogue (after `PARSE_PROG`) and recorded a stale
  pointer; moved before `PARSE_PROG`. cycc flat (`_TARGET_AGNOS`-gated); ecb/cass
  green. See CHANGELOG [6.1.14].
- **v6.1.15** — TS/TSX→JS `async`-on-wrong-node fix (yeo-cy-test): the single
  pending-async slot was stolen by the first nested arrow → bare `await`; added
  `TS_PS_TAKE_ASYNC` capture-at-entry/apply-after-push. cycc +512 B; ecb/cass green.
  See CHANGELOG [6.1.15].
- **v6.1.16** — Windows-correctness pack (3 items): `cycc_win` missing from the
  x86_64 release tarball since v6.0.50 (`release.yml` fix); PE `syscall(<var>,…)`
  silent miscompile → `EPE_SYSCALL_DYNAMIC` runtime dispatch; `lib/sync.cyr`
  portable mutex (futex/SRWLOCK/spinlock). cycc +2,552 B; ecb+cass `SELFHOST_OK`.
  See CHANGELOG [6.1.16].
- **v6.1.17** — sakshi 2.2.8 fold + PE `nanosleep(35)` routing (`ENANOSLEEP_PE`,
  completing the 6.1.16 PE dispatch) + **unblocked the PE release tarball** (6.1.16
  made an unroutable-arity var-syscall a hard error → arity-5 getdents64 broke the
  wrapper build; softened to -38+warning). cycc +1,736 B; ecb+cass green;
  `nanosleep_pe` + `var_syscall_arity_pe` → exit 42 on real Windows;
  `build-windows-tarball.sh` succeeds. See CHANGELOG [6.1.17].
- **v6.1.18** — Windows directory-listing port (`dir_list`/`is_dir`/`dir_walk` now
  work on Windows via FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW —
  `lib/fs_win.cyr` + four `0xF016-0xF019` reroutes) + **sakshi 2.2.10 fold** (2.2.9
  timespec fix + 2.2.10 busy-spin drop). cycc +2,248 B; ecb+cass green;
  `tests/win/dir_list_pe.cyr` → exit 42 on real Windows. See CHANGELOG [6.1.18].

- **v6.1.19–.31** (summary — full detail in [roadmap.md](roadmap.md) + CHANGELOG;
  this file's per-release bullets above stop at .18): TLS/alloc/LSP band (brk→mmap
  chunked alloc, cert path-build, **native-default flip @ .21**, async arena-leak
  fix, LSP hover) · **bayan .25 / ganita .26** distfile carve (Phase E — stdlib
  primitives-only) · output cap 2 MB→16 MB (.27) · `lib/sys.cyr` + dir-family
  dep-resolution fix (.28) · `fdlopen_init_trusted` (.29) · x86-macOS argv prologue
  (.30) · Ed25519 server certs (.31). roadmap.md is the authoritative slot list.

**Phase F — security hardening tail (SHIPPED v6.1.32–.41)**, from the **2026-06-10
deep-dive review** (`docs/audit/2026-06-10-deep-dive-review.md` — 40 verified
findings, 13 issues). Packed releases: F1 silent-failure + dep-injection, F2
TLS-authn, F3 memory-safety parity — then the dep-fold cycle-close that opened
v6.2.0. The kernel-PIE gnoboot-boot validation remains consumer-gated on the
AGNOS `--pie` harness (filed upstream).

**Open / filed (v6.1.x):**
- **2026-06-10 deep-dive issues** (`docs/development/issues/2026-06-10-*`, 13
  trackers; CVE-14…31 + LEGAL-01). Phase F absorbs the urgent set (F1–F3); the rest
  spread to v6.2.x+/bug-bandwidth. Audit: `docs/audit/2026-06-10-deep-dive-review.md`.
- `stdlib-reference.md` covers ~65/95 lib modules — human-led rewrite, flagged since
  v6.1.0 (~30 modules still undocumented).
- x86-macho cycc self-compile (HELD, Intel EOL) + the broader x86-macOS
  usable-toolchain arc tail (env/arch-detect/cycc-finding/issue-1/packaging) —
  bug-bandwidth.
- macho-arm `*at()`/stat ESYSXLAT — ✅ **fixed v6.1.20 + archived** (was listed here
  as open; corrected 2026-06-10).

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
bootstrap/asm (29 KB committed binary — root of trust)
  → cybs (bootstrap compiler; formerly cyrc, renamed v6.0.0)
    → cycc (modular compiler + IR; formerly cc5, renamed v6.0.0)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win (Windows PE32+ cross-compiler)

(bridge.cyr — the old intermediate stage — was retired at v5.11.66.)
No Rust. No LLVM. No Python. Just sh + Linux x86_64.
Build: sh bootstrap/bootstrap.sh
```
