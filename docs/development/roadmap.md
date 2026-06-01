# Cyrius Development Roadmap — v6.x

**Scope** — the v6.x cycle (post-v6.0.0 cycle-open 2026-05-19).
Items outside the current minor — v7.0+ aspirations, unpinned
language refinements, speculative work — live in
[roadmap-future.md](roadmap-future.md). v5.x history is canonical
in [`CHANGELOG.md`](../../CHANGELOG.md) per-patch and in
[completed-phases.md](completed-phases.md) for arc retrospective.

## See also

- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check,
  cross-host smoke, cycle-close shape). Evergreen; not cycle-specific.
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [roadmap-future.md](roadmap-future.md) — long-term watching list
  (unpinned items, speculative type-system work, v7.0+ aspirations).
- [completed-phases.md](completed-phases.md) — pre-v5.11.x historical
  arc retrospective (Phase 0–11 foundation summary post-trim).
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

## v6.x framing

v5.x froze "what the language IS." **v6.x is what the language
gains** — new platforms, position-independent codegen, language
features (closures, generics, async syntax), Class B FFI fix,
cross-BB regalloc + the deferred optimization passes that gate on
it. Plus a dedicated middle-late perf-refactor minor to absorb the
accumulated growth-tax from v5.x feature work + early-v6.x platform
additions.

## v6.x cycle budgeting

**Per-minor target**: ~30-slot budget = 20 planned + 10 bug
bandwidth (per user direction 2026-05-19). Can flex to 40-50 like
late v5.x cycles when a minor's substantive new-code surface
warrants it (notably v6.2.x platform expansion + v6.4.x ABI+Perf
arcs).

Reference points: v5.11.x = 70 slots (longest in history),
v5.7.x = 49. v6.x cycles target a middle-ground — most minors
in the 30-40 range, with the substantive-new-code minors flexing
higher.

---

## v6.0.x — Language Cleanup + Stdlib + Native TLS arc

**Theme**: absorb leftover v5.x runway-carryover items + small
language QoL improvements + holdovers + (per user direction
2026-05-28) the **native TLS arc** (`lib/tls_native.cyr`) pulled
forward from v6.2.x. Stdlib clean-slate (mabda fold + bayan/ganita
carve) still pending mabda 3.0 GA; folds in this minor or the next
once GA cuts. The original ~30-slot target for this minor was
revised 2026-05-28 to a **35-60 patch window**, matching v5.7.x /
v5.11.x precedent. (Window stated at arc open and open to change —
see [[feedback_minor_window_at_arc_open]].)

**Shipped**:
- **v6.0.0** — two-binary rename ceremony: `cyrc → cybs` (Cyrius
  Bootstrap) + `cc5 → cycc` (Cyrius Computer Compiler). Bootstrap
  chain `seed (asm) → cybs → cycc`. ~2,100 occurrences renamed
  across ~157 files; historical narrative preserved.
- **v6.0.1** — two stdlib-resolution hotfixes filed same-day as the
  v6.0.0 cycle-open. (1) Rename-skip off-by-one in
  `src/frontend/lex.cyr` (`vp = 4` / `_pd_self_start = 4` should
  have been 5 for `"cycc "`) corrupted the version-pinned stdlib
  fallback path to `$HOME/.cyrius/versions/ <v>/lib/` (leading
  space), causing `include "lib/X.cyr"` to silently fail-resolve
  for consumers without a vendored `./lib/` — gnoboot 0.2.0
  shipped a PE32+ with `ud2/ud2/nop` sentinels at every UEFI
  service call. Same bug fired the pin-drift warning when versions
  matched. (2) Pre-existing `cmd_deps` mkdir-before-find regression
  (v5.11.17 vintage) — `sys_mkdir("lib", 0x1ED)` before
  `_dep_find_stdlib_dir` tripped priority (a) for ANY downstream
  repo with `src/main.cyr` + non-empty stdlib pin. Surfaced when
  gnoboot adopted `stdlib = ["fnptr"]`. Two regression smoke gates
  added (check.sh 78/78 now).
- **v6.0.2** — `cyrius deps` correct-lock fix (`cyrius.lock` empty
  ecosystem-wide since v5.11.8: `cmd_deps_lock` filtered by the stale
  symlink proxy) + stdlib pins verified at 6.0.1. check.sh 79.
- **v6.0.3** — `str_from` overload-dispatch misroute codegen P1
  (nous 0001): the `_int` auto-route now gates on the base fn's return
  type, so data-producing bases (`str_from: Str`) no longer stringify
  cstr pointers as decimals.
- **v6.0.4** — kybernet aarch64 codegen-hang fix: the aarch64 DCE
  reachability pass used `GFCNT` (fixup count) where `GFNC` (fn count)
  was needed, overflowing the 8192-slot fn-start hash into an uncapped
  probe loop → infinite spin on units with >8192 fixups (a **v5.11.59**
  regression, not the 6.0.0 rename the filing blamed). + DCE `live[]`
  4096→8192 cap (both arches), `CYRIUS_DEBUG_PHASES` markers,
  `_dce_fn_count_gate` (check.sh 80), `check.cyr` S64→store64 SIGILL
  fix, audit-walker `-- bundled distribution` recognition, and the
  stdlib refresh sigil 3.1.1→3.5.5 + patra 1.9.4→1.10.3.
- **v6.0.5** — TS scripting papercut bundle from yeo-cy-test
  (2026-05-27 filing). Bug 1: four v6.0.0 rename-drift length args in
  `programs/ts_test_runner.cyr` (memcpy 16→17, store8 +16→+17, error
  text 24→25, two help-text lines 51→52 + 39→40) — out-of-the-box
  runner couldn't find `cycc`. Bug 3: `src/main.cyr`'s cmdline parser
  ignored the path arg after `--parse-ts` / `--lex-ts`; cycc now opens
  the named file instead of reading stdin (backward-compatible with all
  `dup2(fd, 0)` callers). Bug 2 (`cyrius build` exit-0 on failure) did
  not reproduce — `cmd_build` returns `compile()`'s nonzero result and
  has since 2026-04-16; locked in as `_build_exit_nonzero_gate`.
  `_ts_path_arg_gate` covers the bug 3 invariant (piping garbage to
  stdin while passing a valid path; exit 0 only if cycc reads the
  path). check.sh 80 → 82.
- **v6.0.6** — alloc + vec pull-in (mini-arc step 1/2). Folded
  `lib/alloc.cyr` + transitive `lib/fnptr.cyr` (~1.4k LoC active) and
  `lib/vec.cyr` into `src/main.cyr` + `src/main_aarch64.cyr`. Explicit
  `alloc_init()` + pre-allocated `rp_vec = vec_new()` at parser init.
  Zero behavior change — fixed 256-slot array still active. +9,816 B
  x86, +9,840 B aarch64 cross.
- **v6.0.7** — return-patch buffer → vec conversion (mini-arc
  step 2/2) + `cycc-native-aarch64` resurrection. 12 push sites + 3
  read-backs + closure save/restore + inline save/restore + per-fn
  reset migrated to `rp_vec`; `GRPC`/`SRPC` deleted; cap diagnostic
  retired (new ceiling = alloc heap, ~131k returns per fn). Option A
  reuse via `vec_truncate(rp_vec, 0)` keeps memory bounded at
  high-water-mark of largest fn (DoS protection under bump
  allocator). `lib/vec.cyr::vec_truncate` added.
  `tests/tcyr/return_cap_removed.tcyr` (260 returns) joins the suite.
  Cross-arch propagation: all 6 `src/main_*.cyr` variants wired. Net
  -1,576 B per binary from push-site collapse. `build/cycc-native-
  aarch64` resurrected from doc/policy ghost — added to `cyrius.cyml
  [release].cross_bins`, `cbt/pulsar.cyr` builds via the cross,
  binary committed (683,936 B ARM aarch64 ELF).
- **v6.0.8** — backend module collapse. Established
  `src/backend/common/`; moved 4 token-stream accessors
  (`TOKTYP`/`TOKVAL`/`PEEKT`/`PEEKV`) shared across x86 + aarch64 +
  cx into `common/tokens.cyr`, and 4 runtime helpers
  (`_env_scratch`/`_read_env`/`_prof_clock_ns`/`RECFIX`) shared
  across x86 + aarch64 into `common/runtime.cyr`. cx kept its own
  `RECFIX` (different cap/region) and `_read_env` stub. The audit
  confirmed that the ~133 `Exxx` instruction emitters appearing in
  both x86 and aarch64 emit.cyr files are deliberate cross-arch API
  surface — same names, arch-specific bodies — and are NOT
  consolidation candidates. `_cx_token_offsets_gate` rewired to
  check `common/tokens.cyr` once instead of per-backend. cycc x86
  +168 B (honest growth-tax from unified `_prof_clock_ns`'s extra
  `#ifdef` branches); cycc_aarch64 cross -16 B; native binary
  byte-identical.

### v6.0.9 — aarch64 wrapper argv + distlib blank-line residue

User direction 2026-05-28: pull two small open bugs forward into .9
ahead of the TLS arc.

**aarch64 `cyrius` wrapper argv dispatch broken** (open since v6.0.2
cross-host smoke, [[project_v6_0_2_cross_host_smoke_findings]]).
A cross-built aarch64 `cyrius` wrapper (`cat cbt/cyrius.cyr |
build/cycc_aarch64`) prints the usage banner for EVERY command — it
never reads `argv[1]`. Self-hosting confirms a native-on-pi build is
byte-identical, so it's real emitted-code behavior, not a cross
artifact. Prime suspect: `lib/args.cyr`'s aarch64 argv path. The
self-host gate doesn't exercise it (cycc reads stdin, not argv).

**`cyrius distlib` blank-line residue** (deferred from v6.0.4,
[`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md)).
Double-blank lines at the header→first-module seam + include-strip
residue → cosmetic cyrlint warnings on generated bundles. Fix =
blank-collapse in `cmd_distlib` (`cbt/commands.cyr`). CI-unaffected
(bundles are skipped); cosmetic only.

Acceptance: aarch64 cyrius wrapper dispatches `cyrius build foo bar`
correctly (not just `help`); `cyrius distlib <profile>` produces a
bundle with no double-blank lines that cyrlint flags; cycc x86 +
cycc_aarch64 cross both byte-identical; full `scripts/check.sh`.

### Native TLS arc + AGNOS userspace target — v6.0.x .10 → ~.50 (TLS mini-arcs A–E + AGNOS target arc; **re-ordered 2026-05-31**)

User direction 2026-05-28: pull the native TLS arc forward from its
original v6.2.x placement so sandhi + projects-waiting-on-TLS
unblock now. Sigil prereqs MET (ChaCha20-Poly1305 + X25519 shipped
in 3.5.1/.2/.3, cyrius pinned 3.5.6; full TLS 1.3 modern ciphersuite
+ classic suites available). See [[project_native_tls_arc_v6_2_x]]
for the full decision history.

**Re-ordered 2026-05-31 (user direction, two passes).** With Mini-arc
A complete (`tls_native_available()` flipped at .14), the order is:
**all of TLS 1.3 first, kept contiguous** — server (Mini-arc C) then
client (Mini-arc B), **no gap in the 1.3 work** — then the **AGNOS
userspace-target arc** (`CYRIUS_TARGET_AGNOS`), then the **TLS 1.2
backport** (Mini-arc D), then **consumer wiring + arc closeout**
(Mini-arc E). User: *"the native server side for tls 1.3; the Binary
Agnos work then back to the remaining tls items. don't care the
additional slots it may open in the arc"* → refined *"lets put the
agnos target after 1.3 work so there is no gaps … backport is fine to
be done after agnos bin works."* The kernel is mature enough to
warrant userland programs — **agnoshi the first out the gate** — so
cyrius builds the gating prerequisite (the agnos compile target) once
the full 1.3 stack is in. AGNOS kernel-mode code still waits for
v6.2.0's bare-metal target; the AGNOS arc here is **userspace only**
(ring-3 over the agnos syscall ABI).

**Execution order (post-.14):**

| Slots | Arc | Status |
|---|---|---|
| .10 → .14 | Mini-arc A — scaffold / record / framing / key-schedule / ciphersuite | ✅ COMPLETE |
| .15 → .23 | **Mini-arc C — TLS 1.3 server** (FULL scope; .19 auth / .20 resumption / .21 record / .22 loopback / .23 OpenSSL split out) | in progress (8/9) |
| ~.24 → ~.31 | **Mini-arc B — TLS 1.3 client** (completes the 1.3 stack) | |
| .29 → .33 | **AGNOS userspace target — `CYRIUS_TARGET_AGNOS`** (new) | gated on agnos FS-ABI re-freeze |
| .34 → .39 | Mini-arc D — TLS 1.2 backport | |
| .40 → .42 | Mini-arc E — consumer wiring + TLS arc closeout | |
| ~.43 → ~.49 | Back-end window (pinned + candidate items) | |
| ~.50 | v6.0.x cycle closeout | |

TLS 1.3 (server .15–.20 + client .21–.28) stays contiguous so the
client e2e at .28 closes the localhost client↔server loop directly,
then the AGNOS target lands on a complete 1.3 stack with no gap.

Slot numbers are nominal — per user direction the arc may open
additional slots ("don't care the additional slots"); ranges shift
accordingly. Window stated 35–60 ([[feedback_minor_window_at_arc_open]]).

**Goal**: replace `lib/tls.cyr` (current libssl/fdlopen wrapper,
client-only) with `lib/tls_native.cyr` — a sovereign, pure-Cyrius
TLS protocol-layer stack over sigil's crypto primitives. TLS 1.2 +
1.3, client + server. No external governance, no dlopen-of-libssl,
no ld.so dependency.

**Mini-arc A — tls_native scaffold + record layer (.10 → .14) — ✅ COMPLETE**
- **.10** — scaffold (public API, types, error codes, states). ✅
- **.11** — record layer (ContentType / version, fragmentation,
  sequence numbers, BE wire helpers, AEAD nonce + AAD). ✅
- **.12** — handshake message framing (HandshakeType, reader/writer,
  transcript-hash accumulator with snapshot semantics). ✅
- **.13** — TLS 1.3 key schedule (HKDF tree per RFC 8446 §7.1/§7.3).
  Held briefly pending sigil HKDF-SHA384; resolved by sigil 3.5.6. ✅
- **.14** — ciphersuite negotiation; `tls_native_available()` flipped
  0→1. 2 of 3 TLS 1.3 suites live (AES-256-GCM-SHA384 +
  ChaCha20-Poly1305-SHA256); AES-128-GCM-SHA256 registered but gated
  on sigil AES-128 (see the 2026-05-28 comprehensive sigil audit). ✅

**Mini-arc C — TLS 1.3 server (.15 → .23) — pulled forward, FULL scope**

> **Split 2026-05-31** (user direction, roadmap-sanctioned "split if
> grows"): the old combined .19 (client-auth + resumption) became
> **.19 client-auth** + **.20 resumption**; then the e2e capstone split
> into **.21 record-layer protection** (AEAD seal/open + traffic-key
> install — the encryption prerequisite) + **.22 accept() socket loop +
> OpenSSL `s_client` e2e**. Mini-arc C is now 8 slots (.15–.22).
> Downstream nominal ranges shift +2 from the original (B → ~.23,
> AGNOS → ~.31, D → ~.36, E → ~.42, back-end/closeout after) — numbers
> stay nominal per "don't care the additional slots."

User direction 2026-05-31: server-side TLS 1.3 goes first, **full
Mini-arc C as scoped** (not a minimal subset). **Forcing function for
sigil's server-side gaps** — RSA signature surface (PKCS#1 v1.5 + PSS,
sign + verify, SHA-256+384), ECDSA P-256/P-384 sign, and private-key
parsers (RSA / ECDSA / Ed25519 DER + PEM auto-detect) — all already in
the 2026-05-28 comprehensive sigil audit
(`sigil/docs/development/issues/2026-05-28-cyrius-tls-arc-full-audit.md`)
but **load-bearing now** rather than at the old .23. **Premise-check
sigil's tag at .15 entry** ([[feedback_premise_check_at_slot_entry]]);
if the sign / parser surface hasn't shipped, the affected sub-slots
hold (the .13 HKDF-SHA384 hold is the precedent).
- **.15** — server-side handshake state machine: WAIT_CH →
  WAIT_FLIGHT2 → WAIT_FINISHED → CONNECTED.
- **.16** — cert + key loading: PEM/DER decoding via sigil; key
  format detection (RSA / ECDSA / Ed25519).
- **.17** — ServerHello + key_share response. Server-side key
  generation; HelloRetryRequest if client key_share insufficient.
- **.18** — EncryptedExtensions + Certificate + CertificateVerify
  (server-auth signature via sigil RSA-PSS / ECDSA) + Finished.
- **.19** — optional client auth: CertificateRequest emission (in the
  server flight, verify-mode gated) + client Certificate +
  CertificateVerify validation + client Finished verification →
  CONNECTED. Content string "TLS 1.3, client CertificateVerify".
- **.20** — session-ticket / PSK resumption (RFC 8446 §4.6.1 + §2.2):
  resumption_master via keysched_derive_master, NewSessionTicket
  issuance, PSK binder.
- **.21** — record-layer protection: AEAD seal/open of TLS 1.3 records
  (inner content type + padding strip, nonce = static_iv XOR seq, AAD =
  record header) + derive/install the server & client handshake-traffic
  key/IV. The encryption prerequisite for a real handshake.
- **.22** — `accept()` socket loop (read CH record → plaintext SH →
  install keys → encrypted flight → read+verify client Finished →
  CONNECTED) + a **cyrius-native loopback e2e** over a `socketpair`
  (fork: parent server, child minimal client). First full TLS 1.3
  handshake over a socket; no external deps. Added `sys_socketpair`.
- **.23** — OpenSSL `s_client` real interop: real TCP listen/accept +
  fork `openssl s_client`; PEM-cert support + a matching ECDSA-P256
  cert/key generated via openssl + ChangeCipherSpec (middlebox compat).
  Validates the handshake — and .19's positive client-auth crypto
  (`s_client -cert`) + the x509-pubkey wiring — against a real peer.
  Closes Mini-arc C.

**Mini-arc B — TLS 1.3 client (.21 → .28) — completes the 1.3 stack**
- **.21** — ClientHello construction (key_share X25519 + secp256r1
  (P-256), supported_groups / supported_versions,
  signature_algorithms).
- **.22** — ServerHello parsing (downgrade protection, key-share
  extraction, ciphersuite acceptance).
- **.23** — EncryptedExtensions + Certificate + CertificateVerify
  (server-auth path; sigil ECDSA / RSA-PSS verify).
- **.24** — Finished + handshake-complete transition.
- **.25** — application data send/recv; KeyUpdate handling.
- **.26** — X.509 chain verification (sigil X.509 primitives; trust
  store — system bundle or caller-supplied).
- **.27** — hostname / SAN verification (RFC 6125 + wildcard).
- **.28** — client e2e + localhost client↔server loop using our own
  tls_native on both sides (closes Mini-arc C's .20 e2e gap too).

**AGNOS userspace target arc — `CYRIUS_TARGET_AGNOS` (.29 → .33) — new**

User direction 2026-05-31. The kernel is mature enough to warrant
userland programs; agnoshi is the first. Placed **after the full TLS
1.3 stack** (server .15–.20 + client .21–.28) so the 1.3 work stays
contiguous — no gap (user: "lets put the agnos target after 1.3 work
so there is no gaps"). agnos's `shell-separation-prior-art.md` §1a
specifies the **gating prerequisite** for AGNOS's 1.41.x shell-
separation arc: `agnsh` (agnoshi, `MacCracken/agnoshi`, ~5K LOC,
ring-3) is an OS-agnostic shell whose Linux build emits Linux syscall
numbers + struct layouts and **won't execute on AGNOS's sovereign
syscall ABI**. The fix is "Cyrius learns to emit agnos syscalls," not
"agnos answers Linux syscalls" — a new compile target, the same
multi-target story cyrius already has (Linux / Windows / macOS →
**+ agnos**).

**Userspace only** (user direction — target-basis fork): ring-3
programs over the agnos syscall ABI. NOT the kernel-mode bare-metal
triple — that stays v6.2.0; the kernel already builds via its ad-hoc
bare-metal mode.

**ABI contract FILED** (2026-05-31):
[`agnos/docs/development/agnos-userland-abi.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/agnos-userland-abi.md)
is the frozen interface both sides code against; canonical source is
`agnos/kernel/core/syscall.cyr` (`ksyscall` dispatch). The cyrius
`lib/syscalls_x86_64_agnos.cyr` peer **mirrors that doc** (kernel wins
on any disagreement). Key gotchas for the peer, distinct from Linux:
- **agnos `exit` = syscall 0** (NOT Linux `exit_group`/60) — the
  `CYRIUS_TARGET_AGNOS` `_start`/`exit` runtime shim must use agnos
  numbers, not the Linux epilogue.
- **Error return = `-1`** (`0 - 1`), NOT Linux `-errno`. Wrappers test
  `== -1`, no errno decoding.
- **User-pointer rule**: every buffer pointer must be **≥ `0x200000`**
  (kernel reserves 0–2 MB) or the call returns `-1`.
- **3-arg calling convention** (`rdi`/`rsi`/`rdx`) with a 🧪 PROPOSED
  **4th arg `a4 = r10`** for `rename`/`link` (§1a, lands 1.41.2 — adopt
  the register, not Linux's numbers).
- **`AO_*` open flags are agnos-native** (`AO_CREAT=0x100`,
  `AO_TRUNC=0x200`, …) — do NOT copy Linux `O_*`. `create` is
  `open` + `AO_CREAT`; no `chdir`/`getcwd` (CWD is userland-owned).
- **agnos-native struct layouts** — `stat` (48 B, 8-byte fields, §4.1)
  and `getdents` record (reclen-delimited, §4.2) are NOT Linux
  `struct stat`/`dirent64`; mirror the exact byte offsets.

**Gating premise-check ([[feedback_premise_check_at_slot_entry]])**:
table **0–28 is 🔒 FROZEN** (mirror now). The shell-critical FS surface
— **29 getdents · 30 unlink · 31 rename · 32 link · 33 stat**, the
`a4=r10` extension, the `AO_*` flags, and **blocking `read(fd 0)`** —
is **🧪 PROPOSED**, re-freezing as agnos **1.41.1** (stdin) and
**1.41.2** (FS) land. So the arc's hard gate is **the FS surface
re-freezing**: the peer can mirror 0–28 immediately, but the agnoshi
cross-build (.32) only passes once `getdents`/`unlink`/`stat` + open-
flags are 🔒. Open questions still live in the contract (O1 stdin RAW
vs COOKED, O2 `a4=r10`, O3 dir-fds, O4 FAT `stat`/`link`). **Re-freeze
on every change** (contract §5); coordination is agnos-side (user-
driven); **no cross-repo edit from cyrius**
([[feedback_no_unauthorized_cross_repo_edits]]).
- **.29** — target plumbing: `CYRIUS_TARGET_AGNOS` `PP_PREDEFINE`
  macro + target-triple / build-flag wiring (cbt + a
  `src/main_agnos.cyr` entry variant or flag path) + cyrius.cyml
  target selection + the agnos `_start`/`exit`(0) runtime shim. No
  syscall bodies yet — the target compiles a trivial probe.
- **.30** — `lib/syscalls_x86_64_agnos.cyr` peer: mirror the contract
  (numbers 0–28 + the re-frozen 29–33; `a4=r10`; `AO_*`; `stat` +
  `getdents` layouts; `-1` error; ptr ≥ 0x200000). Cross-arch:
  aarch64 peer in the same slot
  ([[feedback_cross_arch_propagation_mandatory]]).
- **.31** — stdlib subset gating for the agnos target: classify which
  `lib/` modules are agnos-ABI-safe (small syscall surface — no
  socket / clock yet; those are deferred kernel-side per prior-art
  §5). Forbidden-module / unavailable-syscall error when agnos-target
  code pulls a Linux-only path. exit-42 + `write`(1) hello probe
  against the agnos ABI (cyrius self-test; no agnos host needed).
- **.32** — agnoshi cross-build smoke gate (user direction —
  agnoshi-gate fork): a `scripts/check.sh` gate that compiles
  `MacCracken/agnoshi` source against `CYRIUS_TARGET_AGNOS` and
  asserts a valid AGNOS-ABI ELF. Adds a cross-repo dependency to
  check.sh — guard it to **flag** (not silently pass) if the agnoshi
  checkout is absent ([[feedback_flag_missing_repos_dont_skip]]).
  4-host smoke where target paths differ
  ([[reference_verification_hosts_ssh]]).
- **.33** — AGNOS-target closeout: lockstep-contract note in
  docs/guides + vidya (`language.toml` new target + `field_notes` for
  the ABI-mirror gotcha); api-surface snapshot; state.md + memory
  pins.

**Mini-arc D — TLS 1.2 backport (.34 → .39) — remaining**
- **.34** — TLS 1.2 record-layer differences (explicit IV, 1.2 seq;
  skip legacy CBC).
- **.35** — TLS 1.2 handshake (version-field semantics, RSA-PSS /
  PKCS1 cert sigs, downgrade-attack mitigations).
- **.36** — TLS 1.2 PRF (SHA-256 / SHA-384 per ciphersuite; RFC 5246
  §5+§8).
- **.37** — TLS 1.2 certificate + Finished (verify_data MAC).
- **.38** — TLS 1.2 ciphersuites (AES-GCM + ChaCha20-Poly1305 / RFC
  7905; skip legacy CBC — the minimum-needed modern-peer set).
- **.39** — TLS 1.2 e2e (localhost + at least one real 1.2-only peer).

**Mini-arc E — consumer wiring + TLS arc closeout (.40 → .42) — remaining**
- **.40** — sandhi rewires onto `lib/tls_native.cyr` + libssl wrapper
  disposition decision (deprecate / keep both / retire `lib/tls.cyr`
  — affects every downstream consumer on the wrapper today; ASK at
  slot entry).
- **.41** — consumer smoke + `cyrius deps` bump path: walk every TLS
  consumer in the ecosystem, verify the bump works, smoke each.
- **.42** — TLS arc closeout: CHANGELOG retrospective, vidya refresh
  (language.toml + field_notes/), state.md session-close, memory pins.

### v6.0.x back-end + closeout shape

Per user direction 2026-05-28 (slot numbers shifted by the 2026-05-31
re-order): after the TLS arc + AGNOS target arc close, run a back-end
window (~.43 → ~.49) absorbing pinned-or-deferred items, then a
closeout pass at ~.50. Closeout follows the CLAUDE.md "Closeout Pass"
§: mechanical fail-fast (self-host + bootstrap closure + check.sh),
then judgment-call passes (heap map / dead code / refactor / code
review / cleanup), then docs sync.

**Pinned back-end slots:**
- **`cyrius tests` plural verb** (folder/suite runner; deferred from
  v6.0.5). Add `cyrius tests [suite]` as the recursive folder runner
  (vs `cyrius test <file>` single-file). Wrapper-only change.
- **TOML `[section]` single-bracket** in `lib/toml.cyr` (commandress
  config-loader driver). ~10 LOC change in `toml_parse`'s dispatch.
  Proposal:
  [`proposals/2026-05-17-toml-single-bracket-sections.md`](proposals/2026-05-17-toml-single-bracket-sections.md).

**Remaining back-end candidates (user picks at slot entry):**
- POSIX `*at()` family (`openat`, `mkdirat`, `unlinkat`, `fstatat`,
  …). Proposal:
  [`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).
- Octal literal syntax (`0o755`). Proposal:
  [`proposals/2026-05-17-octal-literal-syntax.md`](proposals/2026-05-17-octal-literal-syntax.md).
- Build-artifact pre-commit hook (generalize the v5.11.45
  contamination gate from "catch after the fact" to "refuse the
  commit"). Issue:
  [`issues/2026-05-13-build-artifact-precommit-hook.md`](issues/2026-05-13-build-artifact-precommit-hook.md).
- Dead 2 KB ret_patches heap region from v6.0.7
  (`[0x18DA20..0x18E220)` + counter slot at `0x18E220`) —
  heap-map sweep candidate, may fold into closeout's heap-map
  judgment-call pass.
- Stdlib clean-slate (mabda 3.0 GA fold + bayan/ganita carve) —
  ONLY if mabda 3.0 GA cuts before this window; otherwise rolls
  into v6.1.x.
- `cyrius deps --lock` Windows-portable hash (low urgency;
  surfaced by v6.0.2 cross-host smoke).

**Premise-check at each mini-arc open** ([[feedback_premise_check_at_slot_entry]]):
re-verify the sigil API surface for whichever primitives that
mini-arc consumes; re-check sandhi state by Mini-arc E (current
shape may drift); confirm 4-host smoke
([[reference_verification_hosts_ssh]]) where TLS code paths exist.

**Cross-arch propagation** ([[feedback_cross_arch_propagation_mandatory]]):
tls_native is `lib/`-resident — it runs on whatever architecture
the consumer compiles for; no per-arch compiler-emit changes are
expected. If any do appear (e.g. inline-asm for constant-time
primitives — sigil owns that, not tls_native), x86 + aarch64 + cx
+ macho all propagate in the same slot.

### Pinned slot sequence

Per user direction 2026-05-20 (original .2/.3/.4) + 2026-05-27 (.2
dual-item; two codegen P1s — nous-0001 and the kybernet aarch64
hang + DCE — both inserted near-term ahead of the refactor work;
sequence shifted) + 2026-05-28 (yeo-cy-test TS scripting papercut
bundle pulled into .5; alloc/vec mini-arc shifts to .6/.7; backend
collapse shifts to .8). v6.0.2 lands at the user's convenience once
the in-flight stdlib walk completes; **v6.0.3 = the nous-0001
typed-`vec_get` codegen P1** and **v6.0.4 = the kybernet aarch64
codegen-hang + DCE correctness audit** (both silently-wrong /
hard-regression codegen, which outranks the refactor work — user
direction 2026-05-27 "prioritize near-term"); **v6.0.5 = yeo-cy-test
TS scripting papercut bundle** (SHIPPED 2026-05-28); v6.0.6 + v6.0.7
form the two-slot mini-arc closing out the v5.11.x deferred return-
patch-buffer → vec conversion (proposal Option C,
[`proposals/archived/2026-05-08-raise-return-cap.md`](proposals/archived/2026-05-08-raise-return-cap.md));
v6.0.8 = backend module collapse (pulled forward from the v6.0-runway
carry-forward list below). After v6.0.8 = re-evaluate; user direction
2026-05-28 to **pull native TLS arc forward** from its original v6.2.x
placement so sandhi + projects waiting on TLS unblock
([[project_native_tls_arc_v6_2_x]]).

- **v6.0.2 — stdlib pin refresh + `cyrius deps` correct-lock fix**
  (dual-item, per user direction 2026-05-27):
  1. **Stdlib pin refresh** — pull the latest of each stdlib dep
     into cyrius's own `cyrius.cyml` (sigil, sakshi, patra, sankoch,
     niyama, vani, yukti, agnosys, …) reflecting the parallel "walk
     the stdlibs and update to 6.0.1" sweep the user is running
     alongside kernel-arc work. **mabda holds at its current pin**
     until rc.4 validation closes — explicit exception.
  2. **`cyrius deps` correct-lock fix** — `cyrius.lock` has been
     **empty (0 bytes) ecosystem-wide since v5.11.8** (confirmed:
     cyrius, kybernet, argonaut all 0 bytes; tracked-but-empty in
     every commit). Root cause: v5.11.8 switched dep resolution from
     symlink to file-copy (`cbt/deps.cyr:707` `_dep_copy_file`), but
     `cmd_deps_lock` (`cbt/deps.cyr:1223-1226`) still filters for
     symlinks only (`readlink` syscall 89; non-symlinks `continue`d).
     Every resolved dep is now a real copied file → every entry
     skipped → empty lock → `cyrius deps --verify` has nothing to
     verify against. Fix shape (confirm at slot entry): identify
     resolved-dep files by the resolved manifest module list
     (`[deps.*]` + stdlib auto-prepend) rather than the stale
     symlink proxy; hash + record those. Gate cyrius's own repo
     (authored stdlib in `lib/` — self-referential lock is
     meaningless) vs downstream consumers (all `lib/*.cyr` are
     resolved deps).
  - Acceptance: every dep's `cyrius` field tracks v6.0.1; `cyrius
    deps` resolves clean and writes a **non-empty** `cyrius.lock`;
    `cyrius deps --verify` round-trips; `scripts/check.sh` green;
    smoke across all four SSH hosts
    ([[reference_verification_hosts_ssh]]).
- **v6.0.3 — nous-0001 typed-`vec_get` codegen fix** (codegen P1,
  inserted near-term per user direction 2026-05-27). Upstream report
  [`../../../nous/docs/development/issues/0001-cyrius-6.0.1-vec-get-recompute.md`]:
  under cycc 6.0.1, a typed stdlib accessor (`vec_get(v, i): i64`)
  returns a **wrong value** when used as a **nested argument** to
  another call (`str_from(vec_get(v, i))`, `map_get(m, vec_get(v, i))`)
  or **re-evaluated for the same index** within one scope while other
  typed calls + heap allocation intervene. Silently wrong (exit 0 in
  isolation; SIGSEGV downstream). **Clean bisection**: `lib/vec.cyr`
  byte-identical 5.7.29 ↔ 6.0.1 except the added `: i64` return-type
  annotations — overlaying only the typed `vec.cyr` reproduces,
  reverting only it fixes. So the defect is in **codegen for
  typed-return accessors consumed as nested call args**, not the body.
  Blast radius is ecosystem-wide (everything moved to typed sigs in
  the v5.11.x annotation arc). **Premise-check the self-contained
  minimal repro at slot entry** ([[feedback_premise_check_at_slot_entry]])
  before scoping the codegen fix. Cross-arch propagation mandatory
  ([[feedback_cross_arch_propagation_mandatory]]). Acceptance: repro
  prints `cycle detected (correct)`; cycc byte-identical;
  `tests/tcyr/` regression for the nested-accessor shape; full
  `scripts/check.sh`; 4-host smoke. (nous 0002 — `exec_capture`
  no-PATH-search — stays **nous-side, no cyrius slot** per user
  direction 2026-05-27: intentional execve-not-execvp stdlib behavior,
  fixed downstream.)
- **v6.0.4 — kybernet aarch64 codegen-hang + DCE correctness audit**
  (codegen P1, moved near-term per user direction 2026-05-27 — folds
  the originally-pinned aarch64 investigation together with the DCE
  review since they're one root-cause hunt). Filed issue:
  [`issues/2026-05-20-kybernet-cycc_aarch64-6.0.1-codegen-hang.md`](issues/2026-05-20-kybernet-cycc_aarch64-6.0.1-codegen-hang.md).
  **Symptom**: `cycc_aarch64` 6.0.1 parses kybernet's full dep-bundle
  in <1s then **hot-spins at 99.9% CPU indefinitely** (never emits a
  binary; killed at 4 min). `cc5_aarch64` 5.10.44 did the same work
  in ~5s. aarch64 cross-build **unusable** for kybernet; argonaut is
  the 2nd affected repo. x86_64 is clean. **Codegen-stage + size-
  dependent**: a one-line source in the same project errors fast and
  exits clean, so it's specific to kybernet's codegen workload
  (fn ≥ 3256). **DCE is the leading suspect**: the hang reproduces
  **with AND without `CYRIUS_DCE=1`**, and while the `.text` NOP-fill
  is flag-gated, the `live[]` reachability mark-and-sweep runs
  *unconditionally* (also feeds undef-fn warning suppression,
  `src/backend/x86/fixup.cyr:311` / `:157`) — a worse-than-linear
  mark-and-sweep would hang regardless of the flag. **Scope** (user
  direction 2026-05-27 "hang + correctness audit"): (1) localize +
  fix the termination/perf pathology so aarch64 terminates; (2) audit
  reachability *classification* across the v6.0.0 rename — verify no
  live fn is mis-marked dead (silently-wrong-output risk, nous-0001-
  adjacent). Note DCE is still opt-in (`CYRIUS_DCE=1`, `fixup.cyr:334`
  "until the pass is battle-tested"). Likely first step: land
  `CYRIUS_DEBUG_PHASES=1` phase markers (parse/typecheck/DCE/regalloc/
  instsel/emit) to localize the hang (the issue explicitly asks for
  it). Reproduce on the aarch64 SSH host (`pi`,
  [[reference_verification_hosts_ssh]]). Cross-arch propagation
  mandatory ([[feedback_cross_arch_propagation_mandatory]]).
  Outcome-conditional scope: if the fix is larger than a single slot,
  ASK for the shape rather than silently re-slotting
  ([[feedback_no_unilateral_scope_decisions]]). Acceptance: aarch64
  cross-build of kybernet HEAD terminates and emits a valid ELF; no
  reachability misclassification found (or fixed if found); cycc
  byte-identical on x86; 4-host smoke.
  - **New evidence from the v6.0.2 cross-host smoke (2026-05-27,
    [[project_v6_0_2_cross_host_smoke_findings]])**: the aarch64
    problem is **broader than the codegen hang**. A cross-built
    aarch64 `cyrius` *wrapper* (`cat cbt/cyrius.cyr | build/cycc_aarch64`)
    prints the usage banner for *every* command — it never reads
    `argv[1]`. By self-hosting, a native-on-pi build is byte-identical,
    so this is real emitted-code behavior, not a cross-build artifact.
    Prime suspect: **`lib/args.cyr`'s aarch64 argv path**, which the
    self-host gate never exercises (cycc reads stdin, not argv). Check
    this at .4 entry — it may be the same root cause as the hang, or a
    second aarch64 bug. Also relevant: a *live* cross-host smoke is
    blocked because the hosts lack a native `cycc` (pi has only stale
    5.10/5.11 + legacy `cc2`/`cyrb`; ecb is bare) and the Mach-O
    cross-emitter dies `mmap heap init failed` on Linux — so this slot
    may need to provision native toolchains (aarch64 bootstrap on pi)
    before it can verify on hardware.
- **v6.0.6 — alloc + vec pull-in (prep)** — fold `lib/alloc.cyr`
  (+ OS-variant `alloc_windows.cyr` / `alloc_macos.cyr` brought
  in by its internal `#ifdef` chain) and `lib/vec.cyr` into
  cycc's source tree. Add `include` lines to both `src/main.cyr`
  and `src/main_aarch64.cyr`; call `alloc_init()` explicitly at
  top-level (explicit > v5.8.37 lazy-init for compiler internals
  — narrower failure mode). Allocate the parser's
  return-patch vec once via `rp_vec = vec_new()` at parser-state
  init. **Zero behavior change**: the fixed 256-slot array at
  `S + 0x18DA20` is still the active storage; the parser still
  errors out at >256 returns. This slot just makes the surface
  available. Total pull-in surface: ~842 LoC (alloc 483 +
  alloc_windows 87 + alloc_macos 117 + vec 155). Cycc binary
  growth bookkept as honest growth-tax per
  [[feedback_perf_deltas_growth_tax_default]]. Acceptance: cycc
  byte-identical; full `scripts/check.sh`; 4-host smoke.
- **v6.0.7 — return-patch buffer → vec (conversion)** — replace
  the fixed-array storage at all 9 enforcement sites
  (`parse.cyr` ×1, `parse_expr.cyr` ×3, `parse_fn.cyr` ×5) with
  `vec_push(rp_vec, v)`; replace the read-back at
  `parse_expr.cyr:803-812` with `vec_get(rp_vec, clri)` and the
  iteration bound with `vec_len(rp_vec)`. Save/restore for
  closure-bodied nesting at `parse_expr.cyr:760-812` becomes
  `snap = vec_len(rp_vec); vec_truncate(rp_vec, 0)` on entry,
  `vec_truncate(rp_vec, snap)` on exit (may need to add
  `vec_truncate` to `lib/vec.cyr` if not already present —
  confirm at slot entry). Per-fn lifecycle: `vec_truncate(rp_vec,
  0)` at each fn-start — **Option A reuse pattern, chosen for
  security reasons**: cycc's allocator is a bump allocator
  (`lib/alloc.cyr` header line 17), so per-fn `vec_new`/free
  would leave stranded allocations and create a DoS surface on
  malicious input. Reset-per-fn keeps memory bounded at the
  high-water-mark of the largest fn. Delete `GRPC`/`SRPC` from
  `src/common/util.cyr:128-129` and sweep all callers; the dead
  2KB region `[0x18DA20..0x18E220)` and the now-unused counter
  slot at `0x18E220` stay in place — flagged for v6.x closeout
  heap-map sweep per user direction 2026-05-20 ("if needed
  collapse it otherwise closeouts should focus on those kind
  of cleanups"). The "too many return statements (max 256)"
  diagnostic is replaced by an OOM error at the single
  `vec_new()` site. Cross-arch propagation mandatory
  ([[feedback_cross_arch_propagation_mandatory]]): x86 +
  aarch64 + cx + macho in this same slot. Acceptance: cycc
  byte-identical post-conversion; new
  `tests/tcyr/return_cap_removed.tcyr` exercising a fn with
  >256 returns (currently rejected) compiling clean; full
  `scripts/check.sh`; 4-host smoke.
- **v6.0.8 — backend module collapse** (per user direction
  2026-05-27; pulled forward from the v6.0-runway carry-forward
  list below). Audit which helpers in `src/backend/x86/` and
  `src/backend/aarch64/` parallel `emit.cyr` / `jump.cyr` /
  `fixup.cyr` can move to `src/backend/common/` without entangling
  the arch-specific asm-byte tables. cycc byte-identical
  post-collapse; cross-arch builds proportional.

### Planned

#### Toolchain & tests

- **`programs/check.cyr` → `programs/checks/main.cyr` + per-suite
  split** — current monolithic ~9,300 LoC / ~80 gates file is
  hard to navigate and saturated. Break out into a slim dispatcher
  + per-suite files (self-host, EFI, deps, heap-map, etc. — exact
  breakdown ASK at slot entry). Self-host byte-identical post-
  split. User direction 2026-05-19.
- **`cyrius tests` suite/folder runner — split from single-file
  `cyrius test`** — today `cyrius test` does double duty: `cyrius
  test <file>` runs one `.tcyr`, while bare `cyrius test`
  shallow-walks only `tests/tcyr/` + `tests/` (top level), missing
  subdirs / any non-`tcyr/` layout, so an agent ends up
  hand-iterating files — "confusion city" (user, 2026-05-27).
  Sibling verbs make it worse: `soak` (`.scyr`), `smoke`
  (`.smcyr`), `fuzz` (`.fcyr`), `bench` (`.bcyr`) each own a
  separate verb+extension+discovery, so full coverage means
  running several commands. **Design (user direction 2026-05-27)**:
  keep `cyrius test <file>` as the single-file runner; add a new
  **plural `cyrius tests [suite]`** verb that either takes a
  suite/folder argument for explicit folder specification (`cyrius
  tests <dir>`) or, with no arg, searches the whole `tests/`
  folder. Removes the iterate-by-hand papercut. **Confirm at slot
  entry** ([[feedback_premise_check_at_slot_entry]]): (a) whether
  bare `cyrius test` (no file) keeps its legacy auto-discover for
  back-compat or redirects to `tests`; (b) whether the `tests`
  folder search is `.tcyr`-only or also sweeps sibling categories
  (`.scyr`/`.smcyr`/…). Wrapper-only change (`cbt/cyrius.cyr`
  dispatch + `cbt/commands.cyr` walkers) — cycc compile path
  untouched, so self-host is byte-identical trivially. Acceptance:
  `cyrius tests` runs every `.tcyr` under `tests/` recursively;
  `cyrius tests <suite>` scopes to one folder; `cyrius test <file>`
  unchanged; `scripts/check.sh` green; usage banner + `docs/guides`
  + vidya `language.toml` updated for the new verb.
  **Priority** (user direction 2026-05-27): long-standing
  papercut, **non-blocker** — not pinned to a slot yet, but
  wanted cleaned up *soon* within v6.0.x. Pull into an open
  bug-bandwidth slot ahead of the lower-pressure Planned items
  when there's room; ASK for a slot number when ready to pin
  ([[feedback_no_unilateral_scope_decisions]]).
- ~~**TS front-end scripting papercuts** (SecureYeoman `yeo-cy-test`
  port probe, 2026-05-27)~~ — **SHIPPED v6.0.5.** All three sub-bugs
  resolved: #1 (`cyc` truncation) and #3 (`--parse-ts` stdin block)
  fixed; #2 (`cyrius build` exit-0) didn't reproduce and is now gated
  as an invariant (`_build_exit_nonzero_gate`). See CHANGELOG [6.0.5]
  and the issue's *Status* section. The frontend's missing JS/JSX
  **emit** stage from the same filing is a larger arc, minor TBD —
  see [roadmap-future.md](roadmap-future.md).

### v6.0-runway carry-forward (5 items from v5.11.x close band)

The v5.11.x close absorbed 5 of 10 v6.0.0 accompanying-refactor
items into v5.x close (CVE-05, bridge retirement, build-cycc-
verify.sh skeleton, cc3-residue cleanup, heap-map full reorg).
The remaining 5 land in v6.0.x:

- **Byte-array literal peephole** — 5× emit compression for
  `var foo[N] = { 0x.., ... };` init via `mov byte [rcx+disp8],
  imm8` (x86) / STRB Wn, [Xn, imm12] (aarch64) / cx peer. Moved
  here from v5.11.66/.67 at user direction. Acceptance: cycc
  byte-identical; gnoboot binary shrinks visibly (~1300 B per
  UTF-16LE string, ~250 B per EFI GUID). Cross-arch propagation
  per `feedback_cross_arch_propagation_mandatory`.
- **Dead-code careful sweep** — walk cycc's reported unreachable
  fns. Per [`feedback_dead_code_audit_scope`]: scaffold (TS_*/
  ir_*/cross-arch helpers) stays alive by default; only
  confirmed-dead removable. Risk: 0-LoC outcome if all
  candidates classify as scaffold. **Distinct from the v6.0.4 DCE
  work** — that slot audits whether the reachability pass *classifies*
  correctly (and fixes the aarch64 hang); this item is about
  *removing* the fns the (now-trusted) pass reports as dead. Sequence
  this after v6.0.4 so removal runs on a verified-correct classifier.
- **Return-patch buffer → vec** — pinned as the v6.0.5 +
  v6.0.6 mini-arc (alloc/vec pull-in + conversion). See
  "Pinned slot sequence" above for full scope. Proposal
  Option C; allocator prereq surface confirmed at v5.11.67
  premise-check.
- **`_TARGET_*` flag consolidation** — `_TARGET_MACHO`,
  `_TARGET_PE`, `CYRIUS_TARGET_LINUX/WIN/MACOS`, `_AARCH64_BACKEND`,
  plus per-arch `EWRITE_PE` / `_pe_pending_imp_add` / `EDISP32`
  shim families. Consolidate into a single backend-dispatch
  table keyed on `(arch, format)`. Substantial multi-slot
  refactor; lands here per user direction "keep in v6.0.x
  bundle".
- **Backend module collapse where viable** — **pinned to v6.0.7**
  (see "Pinned slot sequence" above). `src/backend/x86/` and
  `src/backend/aarch64/` parallel `emit.cyr` / `jump.cyr` /
  `fixup.cyr`. Audit which helpers can move to
  `src/backend/common/` without entangling asm-byte tables.

### Stdlib QoL expansion

- **POSIX `*at()` family** — `openat`, `mkdirat`, `unlinkat`,
  `fstatat`, `linkat`, `renameat`, `fchmodat`, `utimensat` +
  `AT_FDCWD` / `AT_SYMLINK_NOFOLLOW` / `AT_REMOVEDIR` /
  `AT_SYMLINK_FOLLOW` consts + bare-name peers (`sys_lstat`,
  `sys_link`, `sys_rename`). kriya M2 surfaced this gap;
  agnos likely co-consumer. Proposal:
  [`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).
- **TOML `[section]` single-bracket** in `lib/toml.cyr` —
  spec-conformant single-table syntax alongside existing
  `[[name]]` array-of-tables. ~10 LOC change in `toml_parse`'s
  dispatch. commandress config-loader driver. Proposal:
  [`proposals/2026-05-17-toml-single-bracket-sections.md`](proposals/2026-05-17-toml-single-bracket-sections.md).
- **Octal literal syntax** (`0o755`) — lexer-only feature,
  ~30 LOC in `src/frontend/lex.cyr::LEXNUM` + new `LEXOCT`
  routine. kriya M2 surfaced this for POSIX file-mode constants.
  Proposal:
  [`proposals/2026-05-17-octal-literal-syntax.md`](proposals/2026-05-17-octal-literal-syntax.md).

### Holdovers

- **Build-artifact pre-commit hook** — generalize the v5.11.45
  `_cc5_contamination_gate` (now `_cycc_contamination_gate`)
  from "catch after the fact" to "refuse the commit". Adds a
  `cyrius hooks install` verb that installs `.git/hooks/pre-
  commit` checking for foreign-binary strings, size sanity, and
  ELF magic on `build/<bin>` commits. Issue:
  [`issues/2026-05-13-build-artifact-precommit-hook.md`](issues/2026-05-13-build-artifact-precommit-hook.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated holdover.
  Land when cyim repo updates + re-tests against v6.x. May not
  fire in v6.0.x window.
- **`cyrius deps --lock` Windows-portable hash** — surfaced by the
  v6.0.2 cross-host smoke ([[project_v6_0_2_cross_host_smoke_findings]]).
  `cbt/deps.cyr::_sha256sum_file` forks `/bin/sh` + runs `sha256sum`;
  Windows (cass) has neither (only `certutil -hashfile <f> SHA256`).
  So a correct lock on native Windows needs a `certutil`/built-in hash
  path behind a `_TARGET_PE` branch. **Pre-existing** (predates v6.0.2),
  not a regression; deps-portability follow-up. Low urgency — native
  Windows cyrius-deps consumers are rare. Lands when a Windows consumer
  surfaces pressure, else a quiet v6.0.x slot.

### Stdlib clean-slate — mabda 3.0 GA fold + bayan/ganita carve

**Status**: near-imminent. mabda 3.0.0-rc.3 passed its initial
soak window 2026-05-19; one 24-hour soak away from GA. Fold +
carve land together as the v6.0.x **primary stdlib arc** when
mabda 3.0 GA cuts.

Per user direction 2026-05-19: "stdlib stuff will wait until
mabda is 3.0 GA so we can clean slate and update all the items
together... most likely will happen in 6.0.x cycle".

**Three-part atomic update**:

1. **mabda 3.0 fold** into stdlib using the v5.7.0 sandhi pattern
   (sakshi/patra/sigil/vani/yukti/sankoch v5.8.x precedent; niyama
   v5.9.0). Sister fold: agnosys (transitive via mabda).

2. **bayan distfile carve** — extract `json` / `toml` / `cyml` /
   `csv` / `base64` / `bigint` / `u128` modules from stdlib into
   sibling repo + `[deps.bayan]` resolution. Naming convention
   `bayan_<module>_*`. Math primitives + regex stay in stdlib.

3. **ganita distfile carve** — extract `matrix` / `linalg` /
   advanced math from stdlib into sibling repo + `[deps.ganita]`
   resolution. Naming convention `ganita_<module>_*`.

After the carve, stdlib stays primitives-only — bare-metal
consumers in v6.2.x's RISC-V / firmware work won't drag the data
offshoots into kernel objects.

**Class B FFI / wgpu fncall6 ABI**: if mabda 3.0 GA shipped clean
(rc3 soak passing → GA is the test), the Class B FFI work doesn't
gate the fold. Class B FFI ABI fix proper lands in v6.4.x
regardless. If mabda 3.0 GA gates on the ABI fix in rare
unforeseen circumstance, fold + ABI move together to v6.4.x.

Memory pins: [`project_bayan_ganita_carve_arc`],
[`project_mabda_rc3_at_closeout`] (carried forward from v5.x).

### Slot estimate (v6.0.x)

| Cluster | Slots |
|---|---|
| Stdlib pin refresh + deps correct-lock fix (v6.0.2) | 1-2 |
| Codegen P1s — nous-0001 (.3) + kybernet aarch64 hang/DCE (.4) | ~2-4 |
| Runway carry-forward (return-patch mini-arc .5+.6, _TARGET_* consolidation, backend collapse .7, byte-array peephole, dead-code sweep) | ~14 |
| Stdlib QoL (POSIX *at + TOML + octal) | ~7 |
| Holdovers (pre-commit hook + cyim conditional) | ~2-3 |
| Stdlib clean-slate (mabda fold + bayan + ganita) | ~6-8 |
| **Total planned** | **~32-38** |
| Bug bandwidth | ~10 |
| **Budget** | **~42-48** |

The two codegen P1s (.3/.4) consume bug-bandwidth rather than adding
to the planned arc — both are filed regressions, not new scope. The
stdlib clean-slate flexes total slot count above the 30 target —
acceptable given the "clean slate, update all together" intent. If
mabda GA slips past v6.0.x window, the stdlib portion defers and
v6.0.x lands at ~25 planned slots.

### Deferred to v6.1.0 cut

- v6.0.x → v6.1.0 back-compat symlink drop (cc5 → cycc + cyrc →
  cybs in install snapshot + cbt/core.cyr lookup fallback). Per
  the v6.0.0 transition policy.

---

## v6.1.x — Backend Codegen Multi-Arc

**Theme**: position-independent codegen + dynamic-link migration
+ v6.0.x back-compat retirement. Multi-arc minor with 3 sub-arcs.

Per user direction 2026-05-19: "defer larger items for multi-arc
in 6.1.x".

### Sub-arc A — PIE codegen x86_64 (Option A: kernel-mode only)

`--pie` build flag emitting RIP-relative codegen: `lea rax,
[rip + rel32]` instead of `mov rax, imm64` for absolute-address
loads; fixup-table machinery learns whether each fixup is
absolute (old mode) or RIP-relative (new mode). Userland
binaries + stdlib distfiles continue to use non-PIE path
unchanged.

**AGNOS as first consumer**: full-binary KASLR (Option A in
agnos's `2026-05-11-kaslr-scope.md`). AGNOS v1.28.0 ships
data-only KASLR which doesn't need PIE; pressure here is "when
AGNOS wants full binary relocation" — uncertain timing but
likely materializes during v6.x.

Work surface: ~200-400 LOC across `src/backend/x86/emit.cyr` +
`fixup.cyr`, plus `parse_expr.cyr` fns handling `&fn_name` /
`&global_var` in PIE mode.

Reference proposal:
[`proposals/2026-05-11-pie-support.md`](proposals/2026-05-11-pie-support.md).

### Sub-arc B — PIE codegen aarch64

`adrp` + `add` on aarch64 replacing the 4-chunk `movz`/`movk`
absolute-address sequence. Lands after x86 sub-arc validates the
fixup-table changes are shape-correct cross-arch.

### Sub-arc C — `.gnu.hash` migration + dynamic-link cleanup

Long-term `.gnu.hash` pin deferred at v5.6.38 (no consumer
pressure) earns its slot here — modern dynamic loaders prefer
`.gnu.hash`'s Bloom filter pre-check over the SysV `.hash` chain
walk, and PIE binaries that go through `dlopen` / symbol
resolution see the measurable difference. Land as part of
v6.1.x dynamic-link work; drop SysV `.hash` once `.gnu.hash` is
in place.

### v6.1.0 — Back-compat symlink drop

- Drop `~/.cyrius/bin/cc5 → cycc` + `~/.cyrius/bin/cyrc → cybs`
  symlinks from `scripts/install.sh` release path.
- Drop `cbt/core.cyr` lookup fallback (compiler-binary search
  tries cycc only; no fallback to cc5).
- Same shape for cross-arch symlinks (`cc5_aarch64 → cycc_aarch64`,
  `cc5_win → cycc_win`).

### Slot estimate (v6.1.x)

| Sub-arc | Slots |
|---|---|
| PIE x86_64 (Option A — kernel-mode) | ~6 |
| PIE aarch64 | ~3 |
| `.gnu.hash` migration + drop SysV `.hash` | ~4 |
| Back-compat symlink drop (v6.1.0) | ~1 |
| AGNOS PIE smoke gate + cross-host verify | ~2 |
| **Total planned** | **~16** |
| Bug bandwidth | ~10 |
| **Budget** | **~26** |

---

## v6.2.x — Platform Expansion (Bare-metal + RISC-V rv64 + Native TLS)

**Theme**: 4th platform peer (RISC-V rv64) + bare-metal target
codification. Substantial new-code minor; substrate prerequisites
all landed in v5.11.x close (parser-to-emit named-op refactor,
heap-map full reorg) + v6.1.x backend codegen.

Per user direction 2026-05-19: "previous C items lets break up
logically into prioritized proposals into 6.2.x and 6.3.x" —
platform work (bottom-to-top priority) takes v6.2.x.

### v6.2.0 — Bare-metal target formalization

Codify the ad-hoc bare-metal mode that agnos has been using
since first boot into a first-class
`--target bare-metal-x86_64-elf` (and aarch64 peer) triple.
Six deliverables:

1. Formal target triple (`<arch>-bare-metal-elf`)
2. ELF no-libc output format (no PT_INTERP, no DT_NEEDED, no
   _start expecting libc init)
3. Interrupt-handler emit conventions (`naked_fn` attribute —
   no prologue/epilogue, manual register save/restore)
4. Kernel-mode stdlib subset (forbidden-module check errors
   when bare-metal code pulls host-OS modules)
5. Linker-script / section-placement control via `[sections]`
   block in `cyrius.cyml`
6. Inline assembly primitives for kernel work: `cli`/`sti`/`hlt`,
   port I/O (`in`/`out`), memory barriers (`mfence`/`lfence`/
   `sfence`), `cpuid`

**Acceptance**: rebuilding the agnos kernel with `--target
bare-metal-x86_64-elf` produces a byte-identical artifact to the
current ad-hoc build; forbidden-module check errors clearly when
bare-metal code pulls host-OS modules;
`examples/firmware-hello.cyr` demonstrates the target outside
of agnos.

**Important framing**: bare-metal is **formalization, not
enablement**. The agnos kernel already builds and boots without
this target; v6.2.0 is a QoL feature for future bare-metal
Cyrius consumers (firmware, alt-kernels, embedded). It does NOT
gate AGNOS MVP.

### v6.2.x — RISC-V rv64 backend

First-class RISC-V 64-bit target. The 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites already
landed: typed-simd ABI (v5.x), REAL TYPE SYSTEM (v5.10.x),
struct-byval ABI (v5.10.x), parser-to-emit named-op refactor
(v5.11.x close).

**Scope**:
- New backend: `src/backend/riscv64/{emit,jump,fixup}.cyr`
- New stdlib syscall peer: `lib/syscalls_riscv64_linux.cyr`
- New cross-entry: `src/main_riscv64.cyr`
- New test runner: QEMU + HiFive Unmatched (or equivalent rv64
  hardware) for self-host verify
- New CI matrix arm

**Acceptance gates**:
1. Cross-compiler `build/cycc_riscv64` emits valid rv64 ELF
   that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under
   `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on real rv64 hardware (hardware-
   gated like the aarch64 ssh-pi check).
5. `[release].cross_bins` in `cyrius.cyml` gets a
   `cycc_riscv64` entry.

### v6.2.x — Native TLS stack (`lib/tls_native.cyr`)

Per user direction 2026-05-27: build a **sovereign, pure-Cyrius TLS
stack** to replace the current `lib/tls.cyr`, which is a
**`libssl.so.3` / `libcrypto.so.3` wrapper via the fdlopen bridge**
(client-only; depends on a host OpenSSL + `ld.so`-bootstrapped glibc
TCB). Two consumers now justify the arc (the ≥2-consumer threshold,
[[project_testing_framework_split]]):

1. **The AGNOS kernel** — a freestanding/bare-metal kernel has **no
   `libssl.so.3` to dlopen and no `ld.so`** to bootstrap the glibc TCB
   the current wrapper requires, so the existing `tls.cyr` is
   *structurally unusable* in-kernel. This is the forcing function.
2. **sandhi** (`lib/sandhi.cyr`, folded at v5.7.0) — the larger
   service-boundary wrapper that composes the stdlib network
   primitives (`http`/`ws`/`tls`/`net`) into the full client+server
   surface. Re-points onto the native stack.

**Why v6.2.x**: the kernel consumer needs the **bare-metal target
(v6.2.0)** to compile freestanding crypto + protocol code at all, so
native TLS lands in the same minor, after the target formalizes.

**Scope** (per user direction 2026-05-27): **TLS 1.2 + 1.3, client +
server** — full parity with what the libssl wrapper exposes today,
including 1.2 for older-peer interop.

**Crypto base** — **stays in sigil**; the native TLS lib is a
*protocol layer* (handshake state machine + record layer + ciphersuite
negotiation + key schedule + X.509 chain-verify wiring) over sigil's
primitives. sigil 3.4.x already ships AES-GCM / ECDSA-P256+P384 /
X.509 / SHA-2 / HKDF / Ed25519 / RSA. The two genuine gaps for the
modern TLS 1.3 `ChaCha20-Poly1305 + X25519` suite — **ChaCha20** and
**X25519** — were added to **sigil's roadmap backlog 2026-05-27** with
this arc as the forcing function. The kernel folds sigil in
long-term the way it folds other select deps (per user analogy: a font
lib; agnoshi as primary shell vs tortuga as emergency shell in the
kernel codebase) — sigil is a kernel-folded crypto dep, not a
TLS-internal vendored copy.

**Sequencing within v6.2.x**: bare-metal target (v6.2.0) → sigil
ChaCha20 + X25519 land (separate sigil minor, gated on this slot
firming) → `lib/tls_native.cyr` record layer + handshake + cert verify
→ sandhi re-point → kernel integration smoke.

**Acceptance** (confirm shape at arc entry): native client handshakes
against a real TLS 1.3 + TLS 1.2 peer (OpenSSL `s_server`); native
server accepts a real client; X.509 chain verify via sigil; sandhi
suite green on the native stack; kernel links `tls_native` freestanding
(no `libssl`, no dlopen); `lib/tls.cyr` libssl path retained or retired
per a decision at arc entry. Cross-arch propagation mandatory
([[feedback_cross_arch_propagation_mandatory]]).

Memory pin: [[project_native_tls_arc_v6_2_x]].

### Slot estimate (v6.2.x)

| Cluster | Slots |
|---|---|
| Bare-metal target formalization (6 deliverables) | ~8 |
| RISC-V rv64 backend (new emit/jump/fixup + syscalls peer) | ~12 |
| Native TLS stack (`tls_native.cyr` — 1.2+1.3 client+server over sigil) | ~12-15 |
| Cross-arch test harness + CI matrix | ~3 |
| Hardware self-host gate (HiFive Unmatched or equivalent) | ~2 |
| **Total planned** | **~37-40** |
| Bug bandwidth | ~10 |
| **Budget** | **~47-50** |

Now the **largest minor of the v6.x cycle** — bare-metal + RISC-V +
native TLS is three substantial new-code arcs. Flexes well above the
30 target per user direction "larger patch bandwidth like the last few
minor cycles of 5.x."

**Priority within the minor** (user direction 2026-05-27): **native
TLS > RISC-V**. Native TLS is kernel-critical and sovereignty-bearing
(it removes the libssl external dependency and unblocks in-kernel TLS);
RISC-V is a 4th platform peer — valuable but not as load-bearing. So if
v6.2.x proves unwieldy at entry, **RISC-V is the flagged split-out
candidate** to defer into its own later minor (e.g. v6.2.x tail or a
dedicated platform minor) — TLS and bare-metal stay. Bare-metal stays
because it's the compile prerequisite for in-kernel native TLS.

---

## v6.3.x — Language Refinements

**Theme**: language-level closures + generics + async sugar.
Three syntactic/semantic additions the v5.x cycle held out
explicitly (per 2026-05-12 tight-close).

Per user direction 2026-05-19: language work (mid-priority,
above ABI/perf) takes v6.3.x.

### Closures with lexical capture

Today: function pointers + lambda-pattern workarounds (see
`lib/fnptr.cyr`). Gotcha #8 in v5.x Language Refinements table —
consumers feel the absence.

**Scope**: closure literals + lexical-capture analysis +
closure-environment lowering (allocate-on-construct, deallocate
when closure pointer goes out of scope; vtable-shaped indirect
call). Pairs with existing trait/vtable infrastructure
(`lib/trait.cyr`). v5.8.x ADTs (sum types + exhaustive match +
Result + ?) make captured-state encoding cleaner than it would
have been pre-v5.8.

### Real generic instantiation (monomorphization)

Today: generics parse (type params accepted at `SKIP_GENERICS`
in `src/frontend/parse_decl.cyr`) but erase at compile time —
no monomorphization, type-check semantics are weakest-applicable.
Test floor: `tests/tcyr/enum_generics.tcyr` (v5.8.21 syntax-
acceptance only).

**Scope**: type checker recognizes type parameters as
concrete-at-instantiation; emit-time substitution generates
per-monomorph code. Kavach was the original 1-vote consumer
(per v5.x Language Refinements table); re-verify pressure at
slot entry per [`feedback_premise_check_at_slot_entry`].

### Language-level async/await syntax

Today: callback-based async on epoll runtime (`lib/async.cyr`,
v5.11.15). Works but is verbose at consumer sites.

**Scope**: `async fn` / `await` syntax compiles to
CPS-transformed state machines over the existing epoll runtime.
Same runtime semantics, sugarier surface. Pairs with closures
(capture state across await points).

### Required vs Optional Dependencies

Today: `cyrius.cyml` has no required/optional distinction. Every
entry in `[deps].stdlib = [...]` auto-prepends; every `[deps.<name>]`
block resolves unconditionally via `cyrius deps`. No feature gating,
no target conditionals, no schema knob for "include this only when
needed." Consumers that want conditional code must wrap call sites
in `#ifdef` and hope the transitive resolver doesn't drag the dep
in anyway.

**Scope** (per user direction 2026-05-23 — combine feature +
platform axes):

1. **Feature-gated optional deps** (Cargo-style)
   - `optional = true` flag on `[deps.<name>]` blocks
   - `[features]` table declaring named feature sets +
     default-features
   - `cyrius build --features <list>` / `--no-default-features`
     CLI surface
   - Resolver only fetches+prepends deps whose feature gate is
     active for the current build
2. **Platform-conditional resolution**
   - `target = "<arch>"` / `target = "<os>"` keys on
     `[deps.<name>]` blocks (e.g. `target = "windows"`,
     `target = "aarch64"`, `target = "bare-metal"`)
   - Matches existing cross-arch story (`_TARGET_PE` / aarch64
     emit paths). Bare-metal target (v6.2.0) and RISC-V backend
     (v6.2.x) immediately benefit — kernel objects skip
     non-applicable userland deps without `#ifdef` gymnastics
3. **Axes combine** — a dep can be both feature-gated AND
   platform-conditional: `optional = true` + `target = "windows"`
   + listed under a feature

**Manifest schema delta** (illustrative):

```toml
[features]
default = ["std-io"]
std-io = []
gpu = ["wgpu"]
win-shell = ["mabda"]

[deps.wgpu]
git = "..."
tag = "..."
optional = true
target = "linux"            # AGNOS userland only

[deps.mabda]
git = "..."
tag = "..."
optional = true
target = "windows"          # win-shell feature gates further
```

**Touched surfaces**:
- `src/frontend/parse_decl.cyr` / cyml parser — schema additions
- `programs/cyrius_deps.cyr` — feature + target filtering before
  resolve
- `programs/cyrius_build.cyr` — `--features` / `--no-default-features`
  CLI surface, target detection passthrough
- Existing consumers (sakshi/patra/sigil/mabda/agnosys/etc.) —
  audit `[deps]` for entries that should become optional once the
  schema is available; consumer migration is opt-in (omitted
  `optional` defaults to required, preserving today's behavior)
- vidya — new `language.toml` entries for `[features]` block +
  optional/target keys; `field_notes/language.toml` for the
  "default = [...] vs --no-default-features" gotcha

**Acceptance bar**:
- Manifest parser round-trips a `[features]` block + optional/target
  keys byte-identical
- `cyrius build --features gpu` resolves wgpu, plain `cyrius build`
  does not
- `target = "windows"` deps skip resolution on aarch64-linux host
- Pre-existing consumer manifests (no `[features]`, no `optional`)
  build byte-identical to v6.2.x
- One vidya entry per axis (feature gate, target gate, combined)

**Out of scope for this slot**: feature unification across
transitive deps (Cargo's hardest semantic — defer to v6.4.x or
later if pressure surfaces); per-feature CHANGELOG/version
constraints; cross-package feature exports.

### Slot estimate (v6.3.x)

| Feature | Slots |
|---|---|
| Closures with lexical capture | ~7 |
| Real generic instantiation | ~7 |
| Language-level async/await syntax | ~5 |
| Required vs Optional Dependencies | ~5 |
| Cross-feature integration + tcyr suite | ~3 |
| **Total planned** | **~27** |
| Bug bandwidth | ~10 |
| **Budget** | **~37** |

---

## v6.4.x — ABI + Perf Arc

**Theme**: Class B FFI / wgpu fncall6 ABI fix + register
allocation upgrade + deferred peephole passes.

Held-forward through v5.9.x / v5.10.x / v5.11.x. The
*language-level* ABI work plus the regalloc-gated perf passes
that have been waiting for cross-BB liveness data.

### Class B FFI / wgpu fncall6 ABI fix

Fix Cyrius's `fncall6` vs SysV AMD64 calling convention bug that
mabda's wgpu integration needs. Lands here regardless of where
the mabda fold itself lands (likely already shipped in v6.0.x
clean-slate by this point per the mabda 3.0 GA timing).

### Cross-BB regalloc + liveness pass

Linear-scan register allocator with cross-BB liveness data.
Unlocks three deferred passes that all share the same gate:

- **Copy propagation** — deferred 2026-04-23 v5.6.18/.19. Stack-
  machine IR had no virtual registers for the classical wins;
  regalloc surfaces them. `ir_copyprop_recon` revival.
- **Extended cross-BB dead-store elimination** — deferred same
  date, same gate. Per-BB DSE shipped v5.6.18; cross-BB variant
  needs the liveness-out set per BB that regalloc builds.
  `ir_extdse_recon` revival.
- **Float peephole** (`float.cyr:41`, 5-instruction → 3-byte
  reduction) — worth landing here if bench delta justifies.

### Slot estimate (v6.4.x)

| Cluster | Slots |
|---|---|
| Class B FFI / wgpu fncall6 ABI fix | ~5 |
| Cross-BB regalloc + liveness pass | ~6 |
| Copy propagation revival | ~3 |
| Extended cross-BB DSE | ~3 |
| Float peephole | ~2 |
| Bench-delta evaluation + tcyr coverage | ~2 |
| **Total planned** | **~21** |
| Bug bandwidth | ~10 |
| **Budget** | **~31** |

---

## v6.5.x — Self-Compile Perf-Refactor

**Theme**: dedicated perf cleanup once accumulated growth
surfaces. Middle-late v6.x timing per user direction 2026-05-19:
"compile time can holdover until later in 6.x cycle probably
middle-late".

### Background

v5.11.x review queue (originally captured at v5.x cycle close,
referenced from CHANGELOG [5.11.69])
captured a perf-growth-tax finding: `bench-history.sh` tier-3
shows self_compile **244 ms → 404 ms (+160 ms / +65 %)** between
commits `a17a8de` (2026-04-18, post-v5.10.50) and `f60ec9b2`
(2026-05-18, post-v5.11.63). Growth-tax not regression — cycc
binary grew only +1,072 B over the same window, so the cost is
parse/codegen overhead from feature work (more parser tracking,
more dispatch checks, more cross-arch propagation), not output
bloat.

**v6.x adds its own growth-creating surfaces**: PIE codegen
(v6.1.x), bare-metal + RISC-V rv64 (v6.2.x), language
refinements (v6.3.x), Class B FFI + cross-BB regalloc (v6.4.x).
By v6.5.x the new baseline is established and a dedicated
perf-refactor minor can land without bumping capability work.

### First-step audit

Capture intermediate datapoints via on-quiet-box
`bench-history.sh` runs across the v6.x cycle so the trend has
more than 2 endpoints. Gradual-accretion vs one-patch-dominates
determines whether bisection is even productive (gradual is the
likelier shape given the work mix).

### Slot estimate (v6.5.x)

Open scope at v6.5.x slot entry — depends on the
accumulated-growth shape uncovered during the audit phase.
Target: ~20 planned + 10 bug bandwidth = ~30 budget. Could flex
to 40+ if the perf-refactor surface is wider than expected.

---

## What comes after v6.x

v7.x scope is open. Two known commitments per CLAUDE.md "Version
lives in `VERSION` + `--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
  Future major bumps run `version-bump.sh` and ship; no rename,
  no downstream sweep, no vidya `cc?` residue.
- **build/cc3 drops at v7.0.0** per the prior-major-seed
  retirement policy (cc3 stays through v6.x as the
  v5.0.0-era historical anchor; retires when v6.x → v7.x bump
  removes the legacy back-compat surface).

Beyond that, v7.x is open territory. Likely candidates: more
language refinements based on consumer pressure from v6.x ship;
toolchain improvements (LSP / formatter / linter evolution);
agnos v2.0 alignment if AGNOS's roadmap creates pull.
