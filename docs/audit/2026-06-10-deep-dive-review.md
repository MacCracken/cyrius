# Cyrius Deep-Dive Review — 2026-06-10

> **Project-wide review** (not a routine security scan): state, all three
> roadmap tiers, and hardening / security / optimization opportunities
> against the language's goals (sovereignty, AGNOS-kernel authorship,
> ~v7 public release). This is the **next full audit** that supersedes the
> archived [`2026-04-13-security-audit.md`](archived/2026-04-13-security-audit.md)
> per CLAUDE.md "Security Audit Process" (it was ~13 minors overdue — last
> ran against `cc3 4.2.1`/312 KB; cycc is now 1.05 MB with a network-facing
> TLS server, dep resolver, PIE, and TS frontend added since).

**Reviewer:** Claude (Fable 5), multi-agent workflow
**Version:** cycc 6.1.31 (1,045,896 B at .30)
**Scope:** compiler (front + 6 backends), stdlib (88 modules), bootstrap +
build/install/release infra, tests/fuzz/bench, the fixed heap map, and the
roadmap tiers.
**Methodology:** 9 parallel subsystem mappers → 7 dimension analysts
(memory-safety, crypto/TLS, supply-chain, architecture, performance,
verification, roadmap-vs-goals) → triage/dedup → **40 findings adversarially
verified against source (0 refuted)** → completeness critic. Every claim
below carries a `file:line` cite confirmed by a second agent.

CVE IDs continue the archived audit's sequence (last was CVE-13). Non-security
findings are catalogued by dimension with `DD-NN` ids. Each finding points to
the issue file that tracks its fix.

---

## Headline

The compiler is in strong shape — self-hosting across 5 targets, 0 git deps,
sovereign TLS shipped and default. The review's through-line is a recurring
**"loud failure silently turned into silent failure"** pattern, concentrated
in exactly the surfaces the goals lean on: the dep resolver, the default TLS
stack, the cross-target stdlib, and the measurement harnesses. The three
highest-leverage items:

1. **`cyrius deps --verify`/`--lock` is a shell-injection sink** of the same
   class as CVE-01 — and `--lock` auto-runs on every build (**CVE-14**,
   arguably P0).
2. **`roadmap_6.md` still plans the already-shipped native-TLS arc as v6.2.x
   future work** (~12–15 phantom slots; the "TLS > RISC-V" priority call is on
   a dead workload) — the multi-roadmap drift (**RM-01**).
3. **The runtime benchmark suite has been blind since 2026-04-16** — an
   integer-µs truncation floor flat-lines 37/42 micro-benches; the v6.4.x/v6.5.x
   perf arcs cannot measure their own wins (**PF-01**).

None of the 40 are tracked anywhere today; all three above are cheap.

---

## Security findings (CVE-14 …)

| CVE | Sev | Title | Files | Issue |
|---|---|---|---|---|
| **CVE-14** | **P0/P1** | `deps --verify`/`--lock` lockfile path → `/bin/sh -c` (shell injection; `--lock` auto-runs on every build) | `cbt/deps.cyr:1313,1474,1032` | [deps-resolver-injection-class](../development/issues/2026-06-10-deps-resolver-injection-class.md) |
| **CVE-15** | P1 | CVE-01 residual: git/tag denylist misses space + leading `-` → `git -c …ext::sh` arg-injection RCE | `cbt/deps.cyr:692,703,716` | [deps-resolver-injection-class](../development/issues/2026-06-10-deps-resolver-injection-class.md) |
| **CVE-16** | P2 | CVE-02 half-fixed: rejects `..` but not absolute `/` includes → read `~/.ssh/id_rsa` | `src/frontend/lex.cyr:622` | [deps-resolver-injection-class](../development/issues/2026-06-10-deps-resolver-injection-class.md) |
| **CVE-17** | P1 | TLS chain verify ignores pathLenConstraint, EKU(serverAuth), keyUsage; no revocation | `lib/tls_native.cyr:4829`, `lib/sigil.cyr:9942,9948` | [tls-chain-verification-gaps](../development/issues/2026-06-10-tls-chain-verification-gaps.md) |
| **CVE-18** | P1 | `tls_native_connect` returns OK unverified; wrapper skips hostname when `host==0` | `lib/tls_native.cyr:5058`, `lib/tls.cyr:308` | [tls-chain-verification-gaps](../development/issues/2026-06-10-tls-chain-verification-gaps.md) |
| **CVE-19** | P1 | Entropy fail-weak: ws uninit mask on RNG fail; raw `/dev/urandom` bypass of getrandom; AGNOS has no getrandom syscall at all | `lib/ws.cyr:55,70`, `lib/sandhi.cyr:3444`, `lib/syscalls_x86_64_agnos.cyr`, `lib/random.cyr:34` | [entropy-failweak-paths](../development/issues/2026-06-10-entropy-failweak-paths.md) |
| **CVE-20** | P2 | Shipped `cycc` is the de-facto trust root, disjoint from the seed chain `bootstrap.sh` verifies (extends CVE-12) | `bootstrap/bootstrap.sh:29`, `.github/workflows/release.yml:38` | [release-trust-chain-integrity](../development/issues/2026-06-10-release-trust-chain-integrity.md) |
| **CVE-21** | P2 | Release integrity: unsigned tarballs, mutable git-tag deps (no SHA pin), checksum non-blocking ("continuing anyway"), installer pulled from `main`, unpinned GH Actions w/ `contents:write` (extends CVE-13) | `scripts/install.sh:373`, `cbt/deps.cyr:717`, `scripts/cyriusly:57`, `.github/workflows/release.yml:7,380` | [release-trust-chain-integrity](../development/issues/2026-06-10-release-trust-chain-integrity.md) |
| **CVE-22** | P1 | `_vec_die`/`_hm_die` infinitely self-recurse → OOB/OOM SIGSEGVs instead of `exit(1)` on all non-AGNOS targets (regression v6.0.56) | `lib/vec.cyr:69`, `lib/hashmap.cyr:224` | [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md) |
| **CVE-23** | P2 | 16 MB `output_buf` cap unenforced in aarch64-ELF, PE, x86-kernel emitters → silent heap-top overrun (kernel images are the unguarded path) | `aarch64/fixup.cyr:597,758`, `pe/emit.cyr:1069`, `x86/fixup.cyr:703,900` | [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md) |
| **CVE-24** | P2 | Locals registration has no cap; 257th local overruns `fn_local_names` (256) into `local_depths` | `parse_decl.cyr:967`, `util.cyr:127` | [memory-safety-parity-gaps](../development/issues/2026-06-10-memory-safety-parity-gaps.md) |
| **CVE-25** | P2 | `_sb_grow` discards grow-OOM rc → builders memcpy past old buffer (silent heap corruption) | `lib/str.cyr:469,486` | [memory-safety-parity-gaps](../development/issues/2026-06-10-memory-safety-parity-gaps.md) |
| **CVE-26** | P2 | `alloc_agnos` alloc() lacks `size<=0`/`>ALLOC_MAX` guard → negative size rewinds bump pointer | `lib/alloc_agnos.cyr:61` | [memory-safety-parity-gaps](../development/issues/2026-06-10-memory-safety-parity-gaps.md) |
| **CVE-27** | P2 | PE import registries fixed 32-slot/512-B, no bounds check; 34 auto-import helpers already saturate them | `src/backend/pe/emit.cyr:127,231,735` | [memory-safety-parity-gaps](../development/issues/2026-06-10-memory-safety-parity-gaps.md) |
| **CVE-28** | P2 | aarch64 `atomic_cas`/`fetch_add` are bare `ldxr/stxr` — NOT barriers despite the documented contract; `default_alloc()` CAS-publishes an unfenced vtable (Pi races) | `lib/atomic.cyr:19`, `lib/alloc.cyr:622` | [unreviewed-dimensions](../development/issues/2026-06-10-unreviewed-dimensions.md) |
| **CVE-29** | P3 | Thread stacks mapped RW with no PROT_NONE guard page; overflow silently writes adjacent mappings; stack probe PE-only | `lib/thread.cyr:50`, `x86/emit.cyr:2037` | [unreviewed-dimensions](../development/issues/2026-06-10-unreviewed-dimensions.md) |
| **CVE-30** | P1 | TLS post-handshake records (NewSessionTicket/KeyUpdate) collapse to `read()==0` = false EOF / truncation; KeyUpdate silently dropped → later records fail. Default backend. | `lib/tls_native.cyr:2091,5266`, `lib/tls.cyr:76` | [tls-post-handshake-false-eof](../development/issues/2026-06-10-tls-post-handshake-false-eof.md) |
| **CVE-31** | P1 | Compiler silently accepts broken input: missing include = 0 bytes, unknown ASCII dropped, `file_map>128` misattributes file:line | `lex.cyr:657,1647,28`, `lex_pp.cyr:1612` | [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md) |

**Status of the prior audit's open tail** (verified): CVE-09 (jump-table
overflow) still silent; CVE-10 (tmp-file race) vector fixed v4.10.0 but never
ticked; CVE-11 (canaries) open; **CVE-12** (bootstrap attestation) + **CVE-13**
(release signing) open and now sharpened by CVE-20/21. The archived audit's
banner claims this tail "is tracked as roadmap items" — it appears on **zero**
roadmap tiers. See [overdue-security-audit-cve-tail](../development/issues/2026-06-10-overdue-security-audit-cve-tail.md).

---

## Compliance findings

| ID | Sev | Title | Files | Issue |
|---|---|---|---|---|
| **LEGAL-01** | High (v7 blocker) | GPL-3.0-only stdlib is *source-included* into every consumer binary with no Runtime-Library-Exception → arguably forces GPL on all downstream binaries. `sigil.cyr:533` also elects the GPLv2-only leg of dual BSD/GPLv2 SHA-NI code (GPLv2-only is GPL-3-incompatible). | `LICENSE`, `lib/sigil.cyr:533` | [unreviewed-dimensions](../development/issues/2026-06-10-unreviewed-dimensions.md) |

---

## Correctness / integrity findings (non-CVE)

| ID | Sev | Title | Issue |
|---|---|---|---|
| **CO-01** | P1 | Forward calls get zero ABI metadata (Str/SIMD masks, struct-ret) — include/definition order is load-bearing, silently miscompiles, no diagnostic. Hard prereq for v6.3.x generics; a C-programmer trap for v7. `parse_fn.cyr:730,949,2036` | [monomorphization-substrate-prereqs](../development/issues/2026-06-10-monomorphization-substrate-prereqs.md) |
| **CO-02** | P1 | `check.sh` tcyr gate masks crashes: exit status discarded, PASS from stdout grep. The v6.0.83 lesson was fixed only in CI; `check.sh` is the pre-version-bump gate. `lib/regression.cyr:297`, `programs/checks/selfhost.cyr:695` | [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md) |
| **CO-03** | P2 | x86 byte-pattern opt passes (DSE/LASE/regalloc picker) run unguarded on aarch64/cx codebufs — A64/cx words matching the x86 opcode windows get silently NOP-corrupted. `parse_fn.cyr:2310,1408` | [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md) |

---

## Roadmap & process findings

| ID | Sev | Title | Issue |
|---|---|---|---|
| **RM-01** | P1 | `roadmap_6.md` v6.2.x still plans the shipped native-TLS arc (~12–15 phantom slots; budget inflated to "~47–50, largest minor"; "TLS > RISC-V" priority on a dead workload). `roadmap_6.md:199-278` | [roadmap-drift-and-stale-docs](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md) |
| **RM-02** | P2 | `threat-model.md` wrong on security facts (libssl-as-default inverted v6.1.21, "No ASLR" vs PIE, "131 KB input" vs 1 MB), and omits no-revocation/no-EKU. `threat-model.md:23,33,43,65` | [roadmap-drift-and-stale-docs](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md) |
| **RM-03** | P2 | The AGNOS-kernel flagship goal + in-kernel-TLS acceptance have no tracking home on any active tier (live only inside the stale TLS section slated for deletion). | [roadmap-drift-and-stale-docs](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md) |
| **RM-04** | P2 | RISC-V acceptance gate #4 needs real rv64 hardware absent from the fleet (pi/ecb/ach/cass); procurement unbudgeted, has lead time. | [roadmap-drift-and-stale-docs](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md) |
| **RM-05** | P2 | cc3 contradiction across tiers (tier-2/3 "stays through v6.x, drops at v7.0.0" vs CLAUDE.md "dropped at v6.1.0"); state.md stale ("Next: Phase E bayan .19" after both shipped). | [roadmap-drift-and-stale-docs](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md) |
| **RM-06** | P1 | Full security audit ~13 minors overdue; CVE-09…13 tail on no tier despite the banner. This doc closes the audit; the tail needs re-filing. | [overdue-security-audit-cve-tail](../development/issues/2026-06-10-overdue-security-audit-cve-tail.md) |

---

## Architecture debt (must precede v6.3.x / v7)

| ID | Sev | Title | Issue |
|---|---|---|---|
| **AR-01** | P1 | Monomorphization has no working substrate — inline token-replay (`SFBS/SFBE`) is **disabled on both arches** (`_INLINE_OK=0`); the ~7 v6.3.x generic slots assume one exists. `parse_fn.cyr:1191,2226`, `emit.cyr:166` | [monomorphization-substrate-prereqs](../development/issues/2026-06-10-monomorphization-substrate-prereqs.md) |
| **AR-02** | P2 | Fixed-heap model: the growable-table path is proven in-tree (`rp_vec`, byte-identical self-host) but unscheduled; monomorphization is the forcing function. Migrate fn-tables/fixup_tbl/codebuf to vec-backed before v6.3.x. `main.cyr:442` | [monomorphization-substrate-prereqs](../development/issues/2026-06-10-monomorphization-substrate-prereqs.md) |
| **AR-03** | P2 | Heap-registry rot: fixup-cap split-brain (262144 vs 1048576 — 12 MB unreachable), stale fn-table labels, undocumented region w/ off-by-one overlap; cap-drift gate covers 3 of 99 regions. `runtime.cyr:247`, `main.cyr:328` | [memory-safety-parity-gaps](../development/issues/2026-06-10-memory-safety-parity-gaps.md) |
| **AR-04** | P3 | v6.4.x cross-BB regalloc is scoped onto byte-archaeology (post-body x86 byte-scan, x86-only, 5 regs no spilling); needs an explicit substrate decision at arc entry. `parse_fn.cyr:2352` | [monomorphization-substrate-prereqs](../development/issues/2026-06-10-monomorphization-substrate-prereqs.md) |

---

## Performance findings

| ID | Sev | Title | Issue |
|---|---|---|---|
| **PF-01** | P1 | Runtime bench suite blind: integer-µs floor flat-lines 37/42 tier1/2 benches at 1000 ns since 2026-04-16; tool-compile loop dead; 8/15 `.bcyr` orphaned. Blocks the v6.4.x bench-delta slot. `lib/bench.cyr:235`, `scripts/bench-history.sh:80,171` | [runtime-bench-suite-blind](../development/issues/2026-06-10-runtime-bench-suite-blind.md) |
| **PF-02** | P2 | `alloc()` throughput regressed 3–6× (v6.0.64 unconditional spinlock + 2 fences even single-threaded); shipped invisibly in the v6.0.x bench gap. Add a `_threads_active` fast path. `lib/alloc.cyr:197` | [runtime-bench-suite-blind](../development/issues/2026-06-10-runtime-bench-suite-blind.md) |
| **PF-03** | P2 | Per-release bench gate records no phase attribution though `CYRIUS_PROF` ships since v5.10.0; the v6.5.x "first-step audit" wants exactly this. Capture one PROF run in tier3. `main.cyr:896`, `bench-history.sh:161` | [runtime-bench-suite-blind](../development/issues/2026-06-10-runtime-bench-suite-blind.md) |

*Note:* the 16 MB `output_buf` is virtual-only (no eager memset — verified);
the residual emitter cost is byte-at-a-time copy loops.

---

## Verification findings

| ID | Sev | Title | Issue |
|---|---|---|---|
| **VR-01** | P1 | Full tcyr suite runs on 2 of 5 targets; the 8 platform stdlib variants (`fs_win`/`alloc_macos`/`thread_win`/…) have **zero** on-platform test runs — validated only by funcgate side-effects. `ci.yml:185`, `cross-os-selfhost.sh:41` | [verification-coverage-gaps](../development/issues/2026-06-10-verification-coverage-gaps.md) |
| **VR-02** | P1 | Fuzzing vestigial: 5 deterministic loops, wired to no gate; zero fuzz of the cycc parser, the network-facing TLS server's record/handshake/DER parsers, or `x509_parse`. `fuzz/*`, `cbt/commands.cyr:170` | [verification-coverage-gaps](../development/issues/2026-06-10-verification-coverage-gaps.md) |
| **VR-03** | P2 | The 338-input differential corpus is hand-assembled muscle memory, not code — needed as a durable gate before the v6.4/v6.5 refactor minors. | [verification-coverage-gaps](../development/issues/2026-06-10-verification-coverage-gaps.md) |
| **VR-04** | P3 | No emitted-binary structural validation beyond `file` magic + one readelf check; the in-cyrius ELF-parse capability exists (`ci.yml:218`) and can extend to PE/Mach-O. | [verification-coverage-gaps](../development/issues/2026-06-10-verification-coverage-gaps.md) |

---

## Unreviewed dimensions (completeness critic)

Whole areas no analyst owned; several are v7-public blockers. Tracked in
[unreviewed-dimensions](../development/issues/2026-06-10-unreviewed-dimensions.md):
licensing (LEGAL-01), the debugging story (no DWARF on any target;
crash-localization x86-ELF-only), atomics memory model (CVE-28), thread-stack
safety (CVE-29), the AGNOS-target security model (no entropy/W^X/ASLR
assessment), and the LSP/editor tooling tier (the v7 onboarding surface,
unreviewed).

---

## Suggested sequencing (project leader's call — surfacing, not directing)

1. **One packed "stop-the-silent-failures" release** —
   [live-silent-failure-regressions](../development/issues/2026-06-10-live-silent-failure-regressions.md)
   (CVE-22/23/31, CO-02/03) + [deps-resolver-injection-class](../development/issues/2026-06-10-deps-resolver-injection-class.md)
   (CVE-14/15/16). All small, byte-identical for valid inputs, against your own shipped guards.
2. **At v6.1.x closeout doc-sync** — the
   [roadmap-drift](../development/issues/2026-06-10-roadmap-drift-and-stale-docs.md)
   cleanup (RM-01…05). De-risks v6.2.x planning before it opens.
3. **Before v6.2.0 opens** — re-file CVE-09…13 as real rows, settle rv64
   hardware, give hardening an absorber band using the budget freed by the
   phantom TLS arc. The TLS/entropy CVEs (17/18/19/30) are sovereignty +
   v7-public prerequisites.
4. **Before v6.3.x opens** — the AR-01/02 + CO-01 substrate work; these are
   prerequisites the plan assumes, not enhancements.
