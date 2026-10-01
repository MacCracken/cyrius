# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the 6.6.13 repair release, the tooling proposals that round out the minor, and the
unscheduled 6.x backlog. Whole-cycle framing, the v6.7.x language arc and v6.8.x/v6.9.x RISC-V live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slots) → [roadmap_6.md](roadmap_6.md)
> (v6.7.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

> ⚠ **This file was rewritten 2026-09-08 at v6.6.1.** It had been 1,043 lines still titled
> *"v6.5.x (active minor)"* — a closed minor — of which **~480 lines were a slot list where every
> entry read ✅ SHIPPED**. CLAUDE.md's rule is that closed-minor detail lives in the CHANGELOG and
> [completed-phases.md](completed-phases.md) and that this file carries **only what is still
> ahead**; that rule had been violated for a whole minor, which is the same drift the 2026-07-29
> re-scope removed from `roadmap_6.md`. The v6.5.x narrative was not deleted — it is in the
> CHANGELOG per-patch and summarised in `completed-phases.md`'s v6.5.x band. **Do not re-add
> shipped slots here.**

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: the v6.7.x language arc
  (real traits, the missing common features, and the language list this minor used to carry),
  v6.8.x/v6.9.x RISC-V rv64, cycle budgeting, and the shape of what follows v6.x.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger**.
- [state.md](state.md) — volatile current state. Refreshed **by hand** every release —
  `version-bump.sh` never touches it (its closing summary names the rows to update).
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.6.12** (2026-09-30) — cycc **1,470,944 B** (`.text` **1,297,064**) ·
seed-derive **GREEN** · cross-OS **GREEN** on ecb/ach/cass/pi · self_compile **839 ms** ·
**410** `.tcyr` (**153** in `crossos/`) · **104** `lib/*.cyr` · **316** shell gates under
`tests/gates/<bucket>/` · **11 open issues**, all placed in 6.6.13 · **6 open proposals**.

> ⚠ **Every figure above was DERIVED on the day, not carried** (re-derived 2026-09-27 at the 6.6.7 open).
> `version-bump.sh` rewrites the version token, replaces the `(…)` after it with the bump date, and
> nothing else — **the numbers beside it are yours to re-derive.** Keep the stamp at the start of its
> line and its parenthetical free of nested `(`/`)`, or the bump refuses to rewrite it (and
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red the day it is written). Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.0 opened this minor** with its one breaking change: `Result` / `Option` / `Either` are the **value
form** (construction allocates zero bytes), shipped WITH the ecosystem. **v6.6.1–v6.6.6** were the repair
window: 6.6.1 closed the issue queue, 6.6.2/6.6.3 repaired what the ecosystem sweep found, 6.6.4 fixed the
59-release native-aarch64 `cyrius run/test` defect, 6.6.5 the nine issues open at 2026-09-17, and 6.6.6 its
27-bite follow-on (five lanes; see CHANGELOG). **The repair window is CLOSED.** Per-release detail is in the
CHANGELOG; do not re-add shipped slots here.

**v6.6.7–v6.6.12 were the repair batch** (2026-09-27 → 2026-09-30, CLOSED): the 30 issues filed after
6.6.6, split by the user across three releases, then each release's own review finds, which the user
placed into 6.6.10–6.6.12 — and 6.6.12 also took the backlog's repair items and every sibling follow-up.
It spent **CVE-46 … CVE-58** (the next free id is 59) and shipped each release together with the sibling
patch releases it needed. Per-release detail is in the CHANGELOG; the process rules it settled are in
*Standing notes* below.

**Re-planned 2026-10-01 (user).** 6.6.13 is a repair release — the three silent memory-corruption finds
that led the backlog, and the open issues (I1–I11). After it the minor finishes on **tooling** (the proposals).
The language list that was Phase 3 moved to **v6.7.x**, which RISC-V vacates for v6.8.x/v6.9.x. See
*The shape of v6.6.x*.

---

## The shape of v6.6.x

| Phase | Slots | What goes here |
|---|---|---|
| **1 — Repair window** | `.2` – `.6` | ✅ **CLOSED at 6.6.6.** |
| **1b — the repair batch** | `.7` – `.12` | ✅ **CLOSED at 6.6.12** (summary in *Where we are*). |
| **1c — memory + reported-issue repair** | `.13` | The three silent memory-corruption finds, the open issues I1–I11, and the ganita / bayan / sigil folds. ✅ ganita 1.2.11, bayan 1.5.10 and sigil 3.13.6 are tagged (2026-10-01): the release is open. See *6.6.13* below. |
| **2 — Tooling round-out** | after `.13`, to the minor's close | The tooling proposals P1, P2, P4, P5, P6, alongside the DCE compaction arc and, last, macOS concurrency ordering (*Open questions* 3). Then the closeout pass. |
| ~~**3 — Committed ergonomics**~~ | — | **Moved to v6.7.x** with P3 `const fn` (user, 2026-10-01) — see [roadmap_6.md](roadmap_6.md). |

---

## 6.6.13 — memory fixes + reported-issue repair (planned 2026-10-01, OPEN)

**Set by the user 2026-10-01**: the three silent memory-corruption finds that led the backlog, and every
open issue in [`issues/`](issues/). ⛔ **No `src/` or `lib/` work starts until ganita and bayan have
released**: this release folds their repaired stdlibs.

**Before it opens: three sibling releases.** Each repo fixes its own source, and cyrius refolds
byte-identical from the tag (CLAUDE.md: fix the SOURCE repo, not the fold).

| Sibling | Folded in cyrius now | Open in that repo at planning time |
|---|---|---|
| **ganita** | 1.2.9 (1.2.10 is tagged) | six issues filed 2026-09-30 / 10-01: `f64_tan` missing; `atan2` with infinite arguments; `atan2` signed zero and NaN; the hyperbolic + `asin` cancellation band; the `sinh` / `cosh` overflow band; `binomial` refusing representable values |
| **bayan** | 1.5.9 | `json_parse_flat` mis-associates values; u64 `mulmod` always takes the wide path on aarch64; the agnosai `json_obj_get` cstring / `Str` key mismatch; and the open sibling follow-up below (`_toml_unescape_span_a`) |
| **sigil** ⚠ *found while planning; the 2026-10-01 instruction named only ganita and bayan* | 3.13.5 | I3's lazy initialisers and main-thread TLS block, and I2 (e)'s rejected roots, are **sigil source** (`lib/sigil.cyr` is its fold) — see I2 and I3 |

**Bites.** Premise-checked 2026-10-01 against the 6.6.12 tree; re-run at the open rather than trust this.

*Memory corruption (compiler; the `src` lane):*

- **M1 — a zero-initialised narrow global clobbers the next one.** `var a: u8 = 0; var b: u8 = 7;
  syscall(60, b);` exits **0** (want 7). The 6.6.12 lanes saw it on x86, aarch64 and PE. Site: the
  narrow-global INIT path in `parse_decl.cyr` (6.6.12 B01 fixed only the `for`-step and compound paths).
  Acceptance: a `crossos/` test over every narrow width, zero and non-zero initialisers, adjacent pairs
  in both orders.
- **M2 — arrays of a float or struct element are under-sized.** Measured: inside a fn, `var a: f64[4]`
  and `var a: Pt[2]` reserve **8 bytes** (`&x - &a` = 8, where `var a: i64[4]` gets 32). PARSE_VAR passes
  `scalar_type = 0` for those elements, so PARSE_ARRAY sizes them like a bare `var a[N]`. At top level
  `f64[4]` is right (32), but **`Pt[2]` gets 16** (N × 8, not N × sizeof). Size by element everywhere.
  ⚠ The first probe missed it: the neighbouring local was held in a register (regalloc), so the
  acceptance test must check through an address-taken neighbour.
- **M3 — a captured struct copied into a field inside a closure stores its address.**
  `var g = || { var b: Box; b.v = p; return b.v.x * 10 + b.v.y; };` with a captured `Pt p` = (3, 4)
  returns **80** (want 34). Cause: `_fsc_name_src` does not resolve captures (since 6.6.10's field-store
  copy).

*The open issues (I1–I5 at planning; I6–I11 added 2026-10-01):*

- **I1 — 🔴 the libssl backend never verifies the server hostname**
  ([issue](issues/2026-09-30-tls-libssl-backend-no-hostname-verification.md)). A man-in-the-middle: any
  chain-valid certificate for any name is accepted, on every `-D CYRIUS_TLS_LIBSSL` build and after
  `tls_set_backend(TLS_BACKEND_LIBSSL)`. Fix as the issue proposes:
  - resolve `SSL_set1_host` / `X509_VERIFY_PARAM_set1_ip_asc` as REQUIRED (if missing, `tls_available()` is 0 and connects fail closed);
  - refuse `host == 0`;
  - put the repro in the TLS suite under both backends;
  - state the hostname binding in the contract.

  CVE-class, as CVE-18 was for the native backend: it takes the next id (59 at planning time), spent in
  the commit that records it.
- **I2 — the native client's memory and alert gaps**
  ([issue](issues/2026-09-30-tls-client-memory-and-alert-gaps.md)), all five parts:
  - (a) `tls_ctx_load_verify_locations` retains 1 MiB per call.
  - (b) There is no allocator-aware client connect. Add `tls_connect_alloc_in` / `tls_native_new_client_in`, and parse the system store once into a shared, immutable root set.
  - (c) Every alert reads as EOF; a fatal alert must return `TLS_ERR_ALERT`.
  - (d) Re-pin `lib-tls-contract.md`, and drop `tls_native.cyr`'s stale KNOWN-HOLES block.
  - (e) **Diagnosed while planning**: the 8 roots skipped out of `/etc/ssl/cert.pem`'s 121 are:
    - three self-signed with sha1WithRSA;
    - four self-signed with sha512WithRSA — Certum ×2 and **D-TRUST BR / EV Root CA 2 2023**, current roots;
    - one ECDSA P-521 (Microsec).

    sigil's `x509_parse` refuses each on the root's OWN signature algorithm or curve. A trust anchor's self-signature is never verified (RFC 5280 §6.1), so the seven RSA roots should install. The parser fix is sigil's; cyrius exposes the skipped count (`tls_native_ca_skipped(ctx)`). P-521 stays counted and skipped until sigil has the curve — adding a curve is a feature for sigil's roadmap, not this repair.
- **I3 — first TLS use from two threads poisons the process; worker-then-main SIGSEGVs**
  ([issue](issues/2026-09-30-tls-first-use-thread-race.md)). Split by owner:
  - **sigil**: convert every check-then-set lazy init to the 0 → 1 → 2 atomic publish its AES / SHA-512 / Ed25519 inits already use; stop `crypto_tls_main_init` giving bank 0 to whichever thread arrives first.
  - **cyrius**: publish `tls_native_set_ca_system`'s bundle cache the same way; add the idempotent `tls_init_main()` warm verb to `lib/tls.cyr`; write the thread-safety contract.

  The repro's A / B / C checks can pass only once the sigil fold is in.
- **I4 — `f64_parse` is not correctly rounded**
  ([issue](issues/2026-09-30-f64-parse-not-correctly-rounded.md)). Default: port **bayan 1.5.7's parser**
  into `lib/math.cyr`, rather than the issue's Clinger + double-double sketch (99.74 %). bayan's parser
  is `bayan_f64_parse` in `bayan/src/dtoa.cyr`: a Clinger fast path, cached 64-bit powers of ten and an
  exact tier for near-halfway inputs — correctly rounded for EVERY input. That leaves one correctly-rounded
  algorithm in the ecosystem; bayan delegating to the stdlib afterwards is a bayan follow-up.
  `f64_parse_ok` shares the parser. Acceptance: the repro exits 0, and bayan's parse corpus is bit-exact.
- **I5 — `f64_le`, `f64_ge` and `f64_trunc` are calls**
  ([issue](issues/2026-09-30-f64-le-ge-trunc-are-calls.md)). Make them builtins like `f64_lt` /
  `f64_floor`, with NaN semantics unchanged (`f64_le` is false when either side is NaN). `f64_trunc`
  lowers to `roundsd $3` on x86 — `f64_floor` already uses `roundsd`, so SSE4.1 is not a new baseline —
  `frintz` on aarch64, and a cx form. ⚠ A builtin name becomes RESERVED: survey the ecosystem for local
  definitions of the three names before switching (the 6.6.0 `tagged_new` lesson). `lib/math.cyr`'s
  wrappers retire in the same bite.
- **I6 — arm64 macOS: a thread created in a `fork()` child kills the child**
  ([issue](issues/2026-10-01-macos-arm64-thread-create-in-fork-child-sigsegv.md); added 2026-10-01 at the
  user's request, found while preparing sigil 3.13.6). SIGSEGV inside `thread_create`, before it returns;
  fork itself works, and Linux is unaffected. The likely cause: `sys_fork` there is the aarch64 peer's
  `clone`, translated to Darwin's raw BSD `fork`, so libSystem's child-side fork handling never runs before
  `pthread_create`. Default fix: route the arm64-macOS `sys_fork` through libSystem's `fork()` via `__got`, a
  Mach-O writer change. Acceptance:
  - the repro exits 0 on ecb;
  - a new `tests/tcyr/crossos/` fork-then-thread test runs on the ecb leg.

- **I7 — the native TLS client matches an IP-literal host against dNSName SAN entries, wildcards included**
  ([issue](issues/2026-10-01-tls-ip-literal-dnsname.md); placed by the user 2026-10-01). A certificate
  whose only SAN is `DNS:127.0.0.1` or `DNS:*.0.0.1` is accepted for `https://127.0.0.1`. RFC 9525 §6.3,
  the rule CVE-18 cites, matches an IP literal against iPAddress entries only. Fix:
  - `_tn_cert_san_match` (`lib/tls_native_conn.cyr:214`) parses the host once, and for an IP literal
    compares `0x87` entries only;
  - `_tn_parse_ipv4` (`:89`) refuses leading zeros, as `net_parse_ipv4` (`lib/net.cyr:1114`) does — or the
    two share one parser.

  Severity Low: exploiting it needs a trusted CA to issue such a dNSName. Acceptance: the repro exits 0.
- **I8 — the native TLS client has no deadline, and skips plaintext ChangeCipherSpec records without limit**
  ([issue](issues/2026-10-01-tls-native-no-deadline.md); placed by the user 2026-10-01). Any on-path box can
  hold a client thread forever by injecting a CCS record more often than the read timeout; a 1-byte drip does
  the same inside one record. All three parts:
  - (a) accept at most one CCS, and only before the peer's Finished (RFC 8446 §5; one per direction in TLS
    1.2), anything else failing with `TLS_ERR_PROTOCOL` and an `unexpected_message` alert;
  - (b) a per-connection deadline — `tls_native_set_deadline(ctx, abs_ns)` plus a `tls_set_deadline` on the
    shim, honoured by `_tn_sock_read_full` / `_tn_sock_write_all` by polling with the time left, and failing
    with a distinct `TLS_ERR_TIMEOUT`;
  - (c) pass the record-read error through instead of collapsing it to `TLS_ERR_IO`.

  (b) is new public API. ⚠ It shares `tls_native_read` with I2 (c), where alerts read as EOF: take the two in
  sequence, with one error-mapping table. Acceptance: the repro exits 0 (both cases fail fast instead of
  blocking).
- **I9 — a typed-array global leaves every later global misaligned; an atomic on one SIGBUSes on aarch64**
  ([issue](issues/2026-10-01-typed-array-globals-not-padded-aarch64-atomics-sigbus.md); filed by agnostic
  0.1.7, placed 2026-10-01). `var a: u8[N]` reserves exactly `N` bytes and the next global lands at
  `&a + N`, so for `N % 8 != 0` every later 64-bit global is misaligned until some other odd size shifts
  it back. x86 tolerates it; the Pi 4's `ldaxr`/`ldar` fault. The folded sankoch's three `u8` arrays
  (630 B) misalign 1,101 of agnostic's 1,962 globals, among them a dozen of sigil's atomic init flags.
  A memory-layout fix, so it rides with M1–M3. Fix: pad after an odd-sized typed array so every global
  starts 8-aligned, on every backend (a `u8[N]` keeps its `N` usable bytes). Acceptance:
  - the repro exits 0 natively on pi;
  - a new `crossos/` row asserts `&g % 8 == 0` for a 64-bit global declared after `u8[3]`, `u8[363]`,
    `i16[3]` and `i32[3]` globals, and runs `atomic_cas` on it.
- **I10 — a `[deps.X]` with `git` + `tag` but no `modules` is silently ignored**
  ([issue](issues/2026-10-01-git-dep-without-modules-silently-inert.md); filed by agnostic 0.1.7, placed
  2026-10-01). `cbt/deps.cyr` clones a named dep only when it lists `modules`, so the block is never
  cloned, vendored or locked. It is not reported either, and a transitive declaration of the same name
  resolves in its place. Default fix: take both of the issue's options. A missing `modules` means
  `["dist/<name>.cyr"]` when the tag ships that file; otherwise `cyrius deps` warns and counts the dep in
  its summary. Acceptance: the repro `.cyml` vendors and locks the dep, and a gate pins the warning.
- **I11 — the Str → `: cstring` diagnostic types only a named local, and its `str_data` hint is wrong**
  ([issue](issues/2026-10-01-str-cstring-diagnostic-misses-call-results.md); filed by bayan 1.5.10, which
  had put it in the backlog — placed in 6.6.13 with the other open issues, 2026-10-01). The check sees
  only an argument whose first token is a `Str` local or param. It is silent for a call result, a global,
  a `: Str` field, a tail call and a method call (W2–W9). It reports `s.data` as the `Str` itself, and its
  hint recommends `str_data(x)`, which turns a warned bug into a silent one (F2). Fix as the issue
  proposes:
  - one helper, called from all three argument loops (PARSE_FNCALL, `_call_arg_one` and the tail loop);
  - type single primaries only (`IDENT`, `IDENT (…)` via `GFRS`, `IDENT . field`);
  - give a declared global's positive struct id, and an inferred global's initializer `GFRS`;
  - hints that never suggest `str_data`.

  Warning text only: every binary stays byte-identical. Acceptance: the repro warns on W1–W9, F1 and F2,
  and no others. The issue's *Related* `#deprecated` gaps are a separate defect, and go to the backlog
  below.

**Once the siblings have tagged:**
1. Fold ganita, bayan and sigil byte-identical from their tags.
2. Open the lanes, minding the two shared files:
   - `lib/tls.cyr` and the `lib/tls_native_*.cyr` files are touched by I1, I2, I3, I7 and I8: one TLS lane,
     with its bites in sequence (I2 (c) and I8 back to back).
   - `lib/math.cyr` is touched by I4 and I5. I5's compiler half sits in the `src` lane, and its `lib/math.cyr` hunk goes to the math lane as a named hand-off.
3. One `src` lane commits `build/cycc`: M1–M3, I9's global padding, I5's builtins, I11's diagnostic
   and I6's Mach-O `__got` entry. I6's `lib/syscalls_aarch64_linux.cyr` arm rides with it; verify it on
   ecb, and verify I9 natively on pi.
   - I10 is `cbt/deps.cyr` only, so it goes in a tooling lane.
4. Gate as always: `release-gate.sh` GREEN on the merged tree, cross-OS on ecb / ach / cass / pi, bench recorded.

**Not promoted** (still in the backlog): the nearest to this release's theme are `var v = g<i32>(..)?;`
exiting 139 and cyrius-lsp's silent 1 MB document buffer.

---

## Open arc — DCE cannot compact on PE, x86 Mach-O or aarch64 (the rip-relative repair)

**Arrived from v6.6.1.** `CYRIUS_DCE=1` now declines the whole-program compaction on PE and x86
Mach-O, exactly as it already declines under `_pie_mode`, because both reach a live import/stub
table through a **rip-relative disp32 that the compaction pass does not repair**, and both
compute file geometry *before* elimination runs. Declining was the correct release fix — those
targets emitted a binary that faulted `0xC0000005` before `main` (PE) or SIGSEGV'd on real
Intel-Mac hardware (Mach-O) — but it leaves them on NOP-fill: **correct, and not shrinking.**
ELF still eliminates for real (measured 123,048 → 16,552 B, −86.5%).

**The repair is two things that must land together**, which is why it is scoped at two slots:

1. **Repair the rip-relative shape in `wp_compact`** — when a body is removed, every `disp32`
   whose target is *not* code that moved by the same delta needs re-patching. This is the same
   repair `_pie_mode` needs, so doing it unblocks PIE compaction too; do not build a PE-only
   version of it.
2. **Re-run `_pe_layout(S)` after compaction** (and the Mach-O equivalent) so section geometry,
   RVAs and `PointerToRawData` describe the code that was actually emitted — with the ftype=4
   IAT-reference fixups patched **after** that re-layout, since their displacement is computed
   from `_pe_idata_rva`.

⚠ **Order matters and the current code proves it**: the IAT displacement in the broken build
resolved to RVA `0x39DD` for an IAT the header put at `0x23000` — it had been patched against the
old geometry and then the instruction moved. Fixing geometry without fixing displacements, or the
reverse, produces a binary that looks fine and faults later. That is exactly the shape that cost
three attempts at the v6.5.72 compaction work.

**Acceptance**: `tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh` is **inverted** —
its axes 1-2 currently assert the payload does *not* move, and on success they must assert PE and
Mach-O shrink *and still run*. Verify by RUNNING on `cass` and `ach`, not by size alone; the
whole defect class is "smaller and broken". Keep axis 3 (ELF still eliminates) unchanged.


**Placement (default taken 2026-09-27): the anchor `src` lane of the release after 6.6.9** — it does not fit
6.6.7–6.6.9 without a third compiler lane. Premise re-checked at the 6.6.7 open: the decline is live at
`src/backend/x86/fixup.cyr:875-876`; `_pe_layout(S)` runs at `fixup.cyr:146` (the comment at `:859` and the
gate header still say "line 123"); the ftype=4 IAT disp32 is baked at `:295-300`, before compaction runs at
`:877-878`. ⚠ **Wider than the slot said**: `wp_compact` also returns 0 for EVERY aarch64 target
(`src/common/ir.cyr:1634`), so arm64 Mach-O and aarch64 ELF never compact either — the same arc, taken
together. Until it lands, the declined-path note should say it declined and why.

**Re-placed 2026-10-01**: 6.6.10–6.6.12 did not take it. It stays in v6.6.x and runs in the tail beside the
tooling proposals (Phase 2). It is backend work, not language work, so it did not move to v6.7.x.

---

## Phase 2 — the tooling round-out (after 6.6.13, to the minor's close)

**Set 2026-10-01 (user): v6.6.x finishes on tooling.** Five of the six open proposals are tooling and
stay here, sequenced by their own stated prerequisites rather than by size. P3 `const fn` is language,
so it moved to v6.7.x with the rest of the language list. The DCE compaction arc (above) and macOS
concurrency ordering (*Open questions* 3) are the minor's other open items.

### P1 — `cyrius.cyml` as the build tool's actual configuration
[`proposals/2026-09-04-build-tool-manifest-integration.md`](proposals/2026-09-04-build-tool-manifest-integration.md)

Filed 2026-09-04, 🟡 OPEN. **Sequence it first, and adjacent to `.2`** — both are about the CLI
honouring its own manifest, and `.2`'s guard needs to read the declared `src`/`entry` key, which
is precisely the surface this proposal is about.

⭐ **The lesson it already records is the reason it ranks first**: the v6.5.49 slice shipped
**inert**. Its `[build]` path fallback read `src`, the key *this* repo happens to use — but of
125 `cyrius.cyml` files across `~/Repos`, **120 declare `entry` and 5 declare `src`**, one of the
five being cyrius itself. So the feature presented as *"does not exist"* to 96% of the ecosystem,
and **its gate passed the whole time because the gate's fixture manifest was written with the
same key the implementation read.** Any work here must gate against a fixture that does *not*
share the implementation's assumptions.

### P2 — Embed data files as source strings (`[embed]` / assets manifest)
[`proposals/2026-08-10-embed-data-files-as-source-strings.md`](proposals/2026-08-10-embed-data-files-as-source-strings.md)

Ergonomics, not capability — the generated-`.cyr` idiom already works and is fleet-wide, and
agnosai ships its own generator, so nothing is blocked. **Its prerequisite has cleared**:
`2026-06-25-source-level-version-constant` shipped at v6.5.21, and `PP_EMIT_PKGVER`
(`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm.

⚠ **Hard constraint learned at `.21`**: an injected directive must emit **ZERO newlines** (merge
onto the following source line) or it shifts every `<source>` diagnostic by one — a 1-for-1 line
replacement is **not** line-neutral.

### ~~P3 — Compile-time evaluation (`const fn`)~~ → moved to v6.7.x (2026-10-01)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

It is language, not tooling, so it moved with the rest of the language list. Its spec — the rung
chosen 2026-07-07 and the `ir_const_fold` ordering constraint — is now [roadmap_6.md](roadmap_6.md)
§ v6.7.x, item C1.

### P4 — test-only stdlib leaves, instead of hiding them from the umbrella scan
[`proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md`](proposals/2026-09-16-declare-test-only-stdlib-leaves-instead-of-hiding-them-from-the-umbrella-scan.md)

Filed 2026-09-16 by **rekha 0.4.4**, 🟡 OPEN. Nothing is blocked — rekha shipped the workaround —
so rank it by appetite, though it is **adjacent to P1**: it is the same complaint, that a
manifest does not say what the tool actually reads.

`dist/<pkg>.deps` unions the include scan of **`src/lib.cyr`** (path hardcoded at
`cbt/commands.cyr:3903`) with `[deps] stdlib`, so a harness-only leaf has nowhere to live that
is not published. rekha carried **nine** leaves for a bundle that calls `strlen` + `memcpy`;
consumers vendored eight leaves of nothing for four releases. The fix — move the harness
includes into `programs/prelude.cyr`, a file the scan does not read — cut the sidecar to
`string alloc` with **byte-identical** bundles, and is the discomfort being reported: *which
file an include sits in* decides what every downstream consumer must vendor.

⭐ **`_distlib_verify_leaves` is the part that works** and the proposal explicitly does not touch
it — it derived `alloc` unaided, because `lib/string.cyr` calls `alloc()` and declares no include
for it. Option 3 in the filing is to trust it as the *sole* authority and delete the two
over-reporting channels, which would have produced rekha's correct answer with no declaration
discipline at all.

⚠ **Two measured notes from the filing that outlive whatever shape this takes.** (a) Auto-prepend
puts every resolved leaf in scope, so a package's own tree **cannot** check its own sidecar — a
program with no includes at all compiles while calling `alloc`/`strlen`/`vec_new`, and a
"compile it the way a consumer does" suite therefore passes a sidecar that omits a needed leaf.
Only `_skip_deps = 1` catches it. (b) `_distlib_verify_leaves`' header reasons that
over-reporting is the safe direction; that holds for a *misspelled* leaf (hard resolver error)
but not for a *real* leaf that is merely unnecessary, which is silent. Over-reporting is
quieter, not safer.

### P5 — `cyrius coverage` over RUN programs, not only `.tcyr` suites
[`proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md`](proposals/2026-09-20-coverage-should-accept-run-programs-as-a-corpus.md)

Filed 2026-09-20 by **rekha 0.4.12** (25 self-checking `programs/*_test.cyr`, ~13,000 lines of assertions,
coverage reported as ~0 %). ⚠ **Its prerequisite ships first**: 6.6.8 bite 9 fixes how coverage COUNTS
(substring and comment matches, a denominator that drops public fns), and extending the corpus before that
would widen a number that is already wrong. The open scope question — a text-reference corpus versus
execution/branch coverage — is the proposal's, and gets asked when this slot opens. Size: M on top of 6.6.8.

### P6 — `cyrius fuzz --poison` through a custom allocator seam
[`proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md`](proposals/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md)

Filed 2026-09-20 by **rekha 0.4.12**, which parses untrusted font bytes through sadish's `sd_alloc` seam and
hand-built a 2,100-line substitute because `--poison` only redzones the freelist. The overlapping piece —
freelist poison comments that no longer describe the code, and a `--poison … ACTIVE` message that claims
coverage it does not have — ships in 6.6.7 bite 8. The design fork (a redzone/fill seam versus guard-page
faulting) is the proposal's. Size: M.

---

## ~~Phase 3 — the committed ergonomics list~~ → v6.7.x (moved 2026-10-01)

The user moved the language list out of this minor on 2026-10-01: `const fn`, the opt-in
bounds-checked mode and trait-bounded generics now open v6.7.x, together with a real-traits arc and the
missing common features. The spec lives in [roadmap_6.md](roadmap_6.md) § v6.7.x — one authority per
minor, so it is not repeated here. Of this list, item 1 (the value-form `Result` / `Option` / `Either`)
shipped at v6.6.0, and `defer` and per-block scoping had long since shipped when they were struck on
2026-07-29.

---

## Sibling follow-ups — open (each is that repo's next patch release)

Found at the 6.6.12 releases. A sibling's fix ships as that repo's own patch release, pinned to a released
cyrius; a folded stdlib is then re-vendored into `lib/` byte-identical from its tag.

- ⚠ kriya `k_isatty` does TCGETS into a 16-byte `var tio[16]` (termios is 36 B): a stack overrun on
  every tty probe, a crash on aarch64 (`cp -i`, `mv -i`, `ls` on a terminal) — recorded for kriya 1.7.4,
  which also adopts 6.6.12's aarch64 wrappers after the cyrius tag.
- bayan `_toml_unescape_span_a` answers a refused allocation with `str_from("")` from the DEFAULT
  allocator, so its value arms report an empty string as success.
- mabda still names `_sk_info_cstr` in sakshi's `_sk_` namespace (no collision today).
- sakshi's "Run under qemu" step calls `qemu-aarch64-static`, which exists only after its apt step.
- bote still commits live `path = "../libro"` / `"../majra"` lines (the dhvani/libro shape 6.6.12 removed).
- aethersafha: 21 files not `cyrius fmt`-clean on 6.6.11 (its CI has no fmt step); duplicate-fn warnings
  between sigil and the agnostik / agnodrm bundles (`_hex_nibble`, `result_print_err`, …).
- sankhya's README / CLAUDE.md name varna 2.1.0 / itihas 2.4.0 / avatara 2.9.0; its 3.0.2 lock pins
  2.4.1 / 2.5.0 / 2.14.8.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **`#deprecated` gaps (measured by bayan 1.5.10 on the 6.6.12 release, recorded in I11's issue as a
  *Related* separate defect; backlog, not placed).**
  - Silent: a call through `&f` (`fncall1(&old_f, 1)`), a method-dot call `o.m()` whose `T_m` is
    `#deprecated`, and a call parsed before the deprecated definition.
  - Mislocated on a tail call: PARSE_RETURN warns (`_DEPRECATED_WARN`, `parse_fn.cyr:790`) after the `)`
    and `;` are consumed, so `return old_f(x);` is reported at the NEXT token's line.
- **Found by the 6.6.12 premise check and lanes (2026-09-30; backlog, not placed — only the user promotes).**
  Met in passing, not swept for. Its three ⚠ silent-memory-corruption items were promoted to **6.6.13**
  (M1–M3) on 2026-10-01.
  - `var v = g<i32>(..)?;` exits 139 on a generic returning a `Result` pair: the expression-side
    `_callee_returns_pair` recognises only `name (`, not `name<T>(`. The statement form (6.6.12 R2) is right.
  - A named >8 B struct argument aliases the caller (`take(q)` passes the address; the guide documents it),
    while 6.6.12 made a FIELD argument copy — decide whether the named form copies too.
  - Windows `sys_symlink` (CreateSymbolicLinkW) widens with `_win_widen` at 519 units, no `\\?\` — a link
    at a path over 260 units fails -1 (honest).
  - cyrius-lsp `lsp_read_file` reads the open document through a fixed 1 MB buffer, silently.
  - The agnos stdlib peer has no `sys_setsockopt` (not even a declining stub), so anything reaching it
    fails to build for agnos (yantra 1.0.7 carries an agnos arm).
  - `async_await_readable_ms` is defined only in `lib/async.cyr`'s Linux branch (sandhi's cooperative
    server loop on macOS is unexercised).
  - x86-macOS `clock_now_ns` assumes the Intel 1:1 mach timebase; unverified under Rosetta (no host).
  - `cyrius lib sync --full` does not re-lock `cyrius.lock`, so rows for files a repo does not vendor keep
    stale hashes until a lock is regenerated from empty (kriya and yantra both hit it).
  - `tests/gates/codegen/cx_forward_read_constant_global.sh` builds relative to the cwd (green only from
    the repo root, where check.sh runs it).
  - The guide's zero-allocation Result example defines `fn use()`, a reserved word — the block does not
    compile (guide_examples_compile.sh skips blocks with no `include`).
  - Inside an aarch64 region (6.6.12 B05's `#@a+` markers) a raw literal that HAS an ESYSXLAT x86-compat
    row is still translated with no warning: `syscall(9, ..)` meant as native lgetxattr runs mmap (also 5 →
    fstat, 55 → getsockopt). Unchanged from 6.6.11 (the raw-literal warning only covers untranslated
    numbers); the native spelling is the 1000+N alias (6.6.12 B09). A region-aware warning for translated
    rows is open.
  - Coverage lost to a CORRECT emulator: with mirshi 1.11.3 filling `sysinfo`'s full tier and emulating
    `uptime_us` (#95), `agnos_sysinfo_tail_parity`'s runtime axis and `agnos_monotonic_clock_rdtsc`'s axis 5
    SKIP by name — the pre-1.57.9 `sched_kicks` pre-fill and the refused-calibration fallback in the stdlib
    no longer run on this box. They need an older-kernel mode (e.g. a mirshi switch) to be exercised again.
- **ESYSXLAT emits its whole translation chain INLINE at every aarch64 syscall site** — measured at the 6.6.8
  merge: `build/cycc-native-aarch64` `.text` 1,495,592 → 1,578,544 B (+82,952 over 605 `svc` sites, ~137 B
  per site) because 6.6.8 bite 3 added nine rows and every row is copied into every site. Every aarch64
  program pays it, and each new row makes it worse. A shared translation stub (one call per site) would
  cut it to a few bytes a site. Correct today; a size tax, so it is placed here rather than in a release.
- **`lib/net.cyr` §4 — per-arch socket syscall peers.** The issue is ARCHIVED (`✅ RESOLVED
  v6.5.7 + v6.5.11`) and was closed deliberately without its §4, so the sharp edge is gone but
  the work is unshipped: `lib/net.cyr` still carries bare x86 numbers with `grep -c CYRIUS_ARCH`
  → **0**, working because nine `ESYSXLAT` x86-compat rows remap them. That remap is
  **load-bearing for 51 ecosystem repos** — this is a migration, not a deletion.
- **`lib/net.cyr` AF_UNIX surface** — a yes/no design call, not a defect: whether `net.cyr` grows
  a Unix-domain socket surface alongside INET. Nothing blocks on it.
- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks with
  no shared pass-1 dispatch helper. A recurring-bug class, not cosmetics: `#io` v5.8.20, `#pure`
  v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute needed return-0 stubs in aarch64 + cx
  and only `cass`'s `cycc_cx` caught the miss. Logic-preserving ⇒ gate is byte-identical
  self-host on all four hosts + seed-derive. Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; slot it when a real debugger story is
  needed. Distinct from the DX diagnostics arc, which was only the error-reporting layer.
- **Incremental compilation** — unpin condition: reconsider when cycc self-host crosses ~2 s. It
  is **731–734 ms at 6.6.1** after 150+ releases, so the whole-program model is nowhere near the
  threshold. ⚠ Read the trend with care: the same binary has measured a 52 ms spread across three
  consecutive runs — **wider than most release-over-release deltas** — so a single number carries
  no signal. Every release's mandatory bench run IS the report.
- **`ir_dce` / `ir_dead_store` uncapped wrappers and `CLASSIFY_CF` / `CF_TARGET`** — decide
  wire-or-delete. Leaving a third option open is how they survived two closeouts.
- **Bare `var a[N]` byte-vs-slot convention** — a design decision, not an arc. The typed spelling
  `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is whether to
  lint the address-taken bare-local per-slot idiom.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot). Policy: the
  next new compiler-state scalar goes into a hole rather than growing the band. **Cite the live
  count** (`grep -n FREED src/main.cyr`) and the heap map; do not maintain an enumerated list that
  goes stale every minor.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term".

- **Fold bundles that are raw-includable** — found at the 6.6.7 triage: `log`, `ws` and `ws_server` cannot be
  included alone because the fold bundles they depend on strip their own includes, so the stdlib
  self-sufficiency sweep (6.6.9 bite 7) carries them as a named PENDING tier. The real fix is a distlib
  change released in cyrius first, then ten sibling regenerations + releases, then a re-vendor — an XL
  cross-repo campaign, so it is not packed into 6.6.7–6.6.9.
- **Nine syscall families consumers still hand-roll, unnamed by the stdlib** — the widened
  surface v6.6.5 measured and deliberately did NOT ship. Per-family reasons, consumers and
  collision analysis live in the table of
  [`issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md`](issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md)
  ("Not fixed, deliberately — (b)"). **Pinned here, not left in an archived file**, because a
  deferral is real only when it is pinned somewhere still open. ⛔ **They are in the exact silent
  class thoth filed**: `_SYSX_MEANT` only carries numbers named in BOTH peers, so a NAMELESS
  number produces **no warning at all** (measured: raw 160 on the aarch64 fork warns nothing).
  Two tiers:
  - ⭐ **Tier 1 SHIPPED at 6.6.8 bite 3** — kavach filed for `unshare`/`chroot`
    ([`issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md`](issues/archived/2026-09-25-kavach-unshare-chroot-unnamed-aarch64-chroot-unreachable.md)),
    and shakti is broken on aarch64 today, so `capget`/`capset` and `process_vm_*` ride with it.
  - **No technical blocker, held only as API surface nobody filed for** — `capget`/`capset`
    (125/126 → 90/91, consumers kybernet + shakti), `chroot` (161 → 51, kavach — the row must sit
    BELOW `51 → 204`), `unshare` (272 → 97, kavach), `process_vm_readv`/`writev` (310/311 →
    270/271, mirshi). Each needs a Darwin route-or-decline, and this release's open concern is
    that three Darwin numbers were derived from neighbouring rows rather than an SDK read — so
    take these on a slot that has an ecb/ach leg, not as a tail-end addition.
  - **Concrete blockers** — `ptrace` (101 is the PRODUCT of this release's `35 → 101`),
    `sched_getaffinity` (204 is the product of `51 → 204`), `pread64`/`pwrite64` (17 is the
    product of `79 → 17` and aarch64-native getcwd → needs the ≥1000 alias band), and the
    `rlimit` family (aarch64 has only `prlimit64`, with a different arg list → an arg-shifting
    row, real hand-assembly).
  - **Acceptance**: every family named in `lib/syscalls_linux_common.cyr` (or the peer that owns
    it) with a Darwin arm, a row whose placement `esysxlat_row_order.sh` passes, and a runtime
    assertion in `tests/tcyr/crossos/` that fails when the number is wrong — the three tests
    v6.6.5 itself had to add.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

---

## Open questions — standing defaults, not a queue

⛔ **This section was once titled "owed to the maintainer" and that framing is banned here. There
is nobody to owe: the maintainer is the person reading this.** A question parked as "owed" is a
deferral to nobody, and it is how several of these sat for months. The rule: **each item carries
a stated default and the work starts under it**; where a genuine fork remains it gets ASKED, in
one line, that turn — not recorded here and left.

The proof is on the record: `darshana-aarch64-syscall-shadow` sat as *"needs a call on where a
~350-row table lives"* until the call was simply taken (**generate it from the stdlib peers**),
whereupon it became 43 derived rows and shipped at `.51`. Assume the same of anything below.

1. **The self_compile budget — ANSWERED (user, 2026-07-29): the later performance track owns it.**
   The budget gets set as part of that track rather than pinned up front. Input for whoever opens
   it: **731–734 ms · 1,247,608 B at 6.6.1**. A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering.** Real platform work with a genuinely broken verb on a gate
   host, so it cannot be dropped — but it has **no consumer waiting**, it mirrors an
   already-shipped split (`thread_win`), and the crossos guards mean it cannot rot silently.
   **Default: keep it last in the minor**; pull it forward if a consumer appears.

*(Former item 3 — per-item `private` — was never a question. It is a live defect and is now
slot `.3` above. Former item 2, the bare-metal forbidden-module check, SHIPPED at v6.5.24 after
this section had carried it as "never built" for thirty releases.)*

---

## Standing notes — traps this minor must not re-learn

- **How a batched release runs (settled across 6.6.5–6.6.12).** Releases are strictly sequential;
  parallelism happens only INSIDE one, in git-worktree lanes where each file has exactly one owning lane
  and every cross-lane hunk travels as a named hand-off patch that lands at a named merge step. At most
  two `src/` lanes, and only one commits `build/cycc`; the binary is rebuilt once on the merged tree
  (fixpoint + seed-derive), `build/cycc-native-aarch64` once with `cyrius pulsar`. Ratchet and census
  final passes (`CORPUS_FLOOR`, `CYCC_CEIL`, the alloc census, the cross-compile allowlist, the
  self-sufficiency floors) are integration steps — a lane working in parallel cannot see the lanes it
  measures. **A per-lane green is not a merged green**: the full gate runs on the merged tree.
- **Fixing bugs is not hunting bugs** (user, 2026-09-29). One implementer + one reviewer per bite,
  reviewing THE BITE; an out-of-scope find goes to the *Potential backlog*, never automatically into a
  later release — only the user promotes. A severe find met in passing (security, silent corruption) is
  reported in one line, not swept for.
- **A CVE id is spent in the commit that records it**, and that commit moves BOTH counters (the
  September audit file's header and `CLAUDE.md`). 6.6.5's did not, and three reviewers had to report it.
- **Text handed into a cyrius string literal obeys the 6.6.11 lexer.** A driver `_gate("…")`
  description carrying a bare `"` or an unknown escape (`\<LF>`, `\q`) stops `programs/checks` compiling —
  it happened at the 6.6.11 merge. Hand-off text for descriptions must avoid both.
- **A sibling's CI runs isolated, never by hand-extracted steps.** Use a clean `git archive` copy with
  `path` deps commented out, a throwaway `CYRIUS_HOME` (a copy of the pinned slot, an EMPTY dep cache) and
  a throwaway `HOME`. At 6.6.12 a reviewer cut the wrong block out of bote's workflow and ran its
  "Install Cyrius toolchain" step against the live `~/.cyrius` (the active version flipped to 6.6.10 for a
  minute). Run the steps with GitHub's shell semantics: `bash -e` unless the workflow says `shell: bash`.
- **The `PARSE_RETURN` tail path has skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each fixed with the same narrow divert — the `_cfo`
  escalation shape, *"declared fixed, fourth occurrence in a path nobody enumerated"*. **Any new
  `PARSE_FNCALL`-resident transformation must be grepped against the tail path before it ships**
  — grep the SHAPE, not the operator.
  **FIFTH occurrence (6.6.7 bite 2): `defer`.** The tail path skipped the EPILOGUE's obligation,
  not PARSE_FNCALL's — every `return f(..);` in a fn with a `defer`/`secret var` jumped past the
  defer walker (CVE-47). By then the arm carried fifteen bolted-on diverts, not four; they are one
  predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a new line THERE. And
  the walker the divert lands on must keep the whole return convention:
  **`EDEFER_SAVE`/`EDEFER_RESTORE` must preserve every return register of every return
  convention on x86, aarch64 AND cx** (x86: rax, rdx, r8, xmm0, xmm1; aarch64: x0-x3, q0, q1;
  cx: r0-r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** The
  v6.6.1 DCE issue said *"PE / `--win` target only"*; x86 Mach-O shared the code path and was
  crashing on real Intel-Mac hardware, unreported, because the reporter does not build that
  platform. **Reproduce on every host that shares the path before scoping the fix.**
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases measured 0 diffs on real wrong-answer fixes.
  When a fix measures 0 diffs, add the shape to the corpus in the same release.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9 minors
  behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. Run the compiler on the
  hardware.
- **A "found by ports" test is worth more than the gate that says the code compiles.** v6.5.7's
  compile-only wrapper gate proved the wrappers *compile* on five targets — most of the risk, none
  of the bugs. The one `.tcyr` that RAN them found **seven** defects, five of which were half-fixes
  that stopped at the first symptom. Whenever a slot adds a platform-facing verb, the
  `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have.
- **A gate fixture in the wrong order is a vacuous gate**, and a gate whose fixture shares the
  implementation's assumption proves nothing at all (the v6.5.49 `entry`/`src` case). Mutation-prove
  the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.** The
  retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got cited to
  file against *sigil*. This is the language repo: when the compiler cannot compile valid cyrius,
  fix the compiler. Premise-check **rules**, not just pins.
- **Re-derive every count in this file at slot entry.** The head line above was version-stamped
  correctly and wrong in five metrics simultaneously; the previous edition carried a gate count
  seven higher than the tree. A number in a roadmap has nothing checking it.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

- **Atomic commits, packed releases.** One logical change per commit; a release bundles many.
- **A bug ships complete** — no granularity by gnarliness, no slicing the hard half into the next
  patch.
- **Only the user pivots focus.** Surface findings; never unilaterally redirect or defer.
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on ecb/ach/cass/pi (REAL hardware) · bench. Never tag with the gate RED.
- **Benchmark every release**, recording self_compile + cycc size in the CHANGELOG entry.
- **An audit's output is fixes, not a backlog.** File only when the fix genuinely cannot pack —
  and name the reason.
