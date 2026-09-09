# Ecosystem migration worklist — the v6.6.0 value-form flip

> **Status:** OPEN — the sweep runs *after* v6.6.2 ships. Tick the boxes as repos land; this file
> is the review artifact for the campaign, so leave the unticked ones visible rather than deleting
> them.
>
> **Created 2026-09-09**, from a full census of all 143 directories under `~/Repos` (140 git repos,
> 127 carrying first-party cyrius source, 4,912 files scanned). Every figure here was derived from
> live code, not carried from a doc. Re-derive before acting on any of them — this file will rot
> like every other, and the whole reason it exists is that a number nobody re-derived shipped a
> deletion against a live consumer.

---

## Why this file exists

v6.6.0 flipped `Result` / `Option` / `Either` to the value form and deleted `payload()` and
`tagged_new()`. The justification, written into `lib/tagged.cyr` and restated in seven other
places, was:

> Nothing in the ecosystem called it (verified across all 12 sibling stdlibs at the v6.6.0 cut)

**The survey was real and its result was correct — for the twelve stdlibs it covered.** The claim
that got written down was ecosystem-wide. `agnostik` (a domain library) calls `tagged_new` 19
times; `agnova` 9 more. Domain libraries were never in scope, and the membership list of "the 12"
appears nowhere in the tree.

The durable rule that came out of it is in `CLAUDE.md` → Working Agreements. This file is the
remediation.

---

## The numbers

Derivation: comment- and string-stripped grep over first-party trees only (`src/ tests/ programs/
benches/ examples/ cbt/ fuzz/ tools/ kernel/ ai/ bootstrap/ scripts/` + repo-root `*.cyr`),
excluding vendored `lib/`, generated `dist/`, `build/`, `vendor/`, `node_modules/`.

| | |
|---|---|
| Repos with ≥1 first-party call site | **49** (of 127 with cyrius source) |
| First-party call sites | **4,392** across 422 files |
| Repos that hard-fail on bump | **40** |
| Repos already migrated | **9** |

### Break buckets

| bucket | sites | repos | loud? |
|---|---|---|---|
| deleted symbol (`payload` 517 + `tagged_new` 28) | 545 | 30 | LOUD |
| arity changed (`result_unwrap` 412, `err_code_of` 40, `unwrap` 3, `result_unwrap_or` 1) | 456 | 20 | LOUD |
| single-var bind `var r = <pair-returning call>;` | ~743 | 38 | LOUD — **never mentioned in the 6.6.0 release notes** |
| `tag()` / `is_tag()` on a raw box | 34 | 2 | 🔴 **SILENT** |
| old-form sites in **vendored** `lib/` trees | 5,961 | 71 | detonates on next `cyrius deps` |

⚠ The single-var bind bucket is **larger than both deletions combined** and governs 38 of the 40
failing repos. A repo needs no accessor call at all to be hit — 157 stdlib functions became
pair-returning, so `var fd = tcp_socket();` is enough.

### Vendored `lib/tagged.cyr` state (all 143 dirs)

`OLD` (has `tagged_new`) **89** · `NEW` (no `tagged_new`) **18** · absent **36**

`NEW` list: agnostik\*, ai-hwaccel, bayan, chakshu, crab, cyrius, ganita, hisab, mabda, mihi,
patra, samvada, sandhi, sigil, vani, vidya\*, yantra, yukti — **\* = pinned below 6.6.x, therefore
already skewed**.

---

## ⛔ Ordering — read before touching anything

1. **Toolchain first.** See below.
2. **cyrius 6.6.2 ships** (the boxed-primitive restore + the pin-honouring vendor guard).
3. **Publishers regenerate `dist/`** — in dependency order.
4. **Consumers re-vendor.**

⛔ **Do not run `cyrius deps` in any pre-flip repo before 6.6.2 is installed.** Until the bite-2
guard lands, `cbt/deps.cyr` falls back to the *installed* snapshot when the pinned one is absent,
so it vendors 6.6.1's stdlib **regardless of the pin**. That is exactly how agnostik was poisoned
at 09:40 on 2026-09-09. 89 repos still hold a pre-flip `lib/tagged.cyr` and build fine today;
one careless `deps` breaks any of them.

⛔ **A clean `git status` is not evidence about `lib/`.** 55–68 sibling repos gitignore their
vendored stdlib (`sigil/.gitignore:29` is `/lib/`; `agnostik/.gitignore:5` is `lib/*.cyr`).
Check content and mtime.

---

## Phase 0 — toolchain

- [ ] Restore whichever wiped versions you actually want back. All 25 publish
      `cyrius-<v>-x86_64-linux.tar.gz` + `.sha256` on GitHub Releases (checked HTTP 200 for every
      one), and `signed-since=6.6.1` permits them. Drive it by **absolute path**, never the
      `cyriusly` on `PATH` — `install.sh` activates what it installs and replaces the running
      `cyriusly` mid-loop:

      CL=~/.cyrius/versions/6.6.1/bin/cyriusly
      for v in <versions>; do "$CL" install "$v"; done
      cyriusly use 6.6.1

      ⚠ 103 of the 104 bricked repos pin **below 6.5.44**, and sibling-`cycc` resolution only
      works from 6.5.44 onward (`CHANGELOG.md:2714`). So restoring gives them their old *wrapper*
      while they still compile with the *current* cycc. Restoring is therefore a convenience for
      `--version` / `lint` / `fmt` and honest error messages, **not** a way to pin old codegen.
- [ ] `6.5.70` specifically is worth having — the last release before the SIMD operand-slot
      Critical, so it is the escape hatch for anyone blocked on that.

---

## Phase 1 — the two boxed-union consumers

These are the repos the deleted primitive actually served. **Construction sites need no edit** —
`tagged_new` returns in `lib/boxed.cyr` as a construction alias, because its meaning never changed.
Only the *reads* move, to `boxed_tag` / `boxed_payload`.

### agnostik — pin 6.5.35 · ⛔ BROKEN ON DISK (10 errors) · `.gitignore:5` = `lib/*.cyr`

Post-flip libs vendored under a pre-flip pin. 9 × "returns two values" + undefined `payload` +
undefined `tagged_new`.

- [ ] **Construction — no change.** 19 `tagged_new` sites stay as written
      (`src/llm.cyr` ×13, `src/telemetry.cyr` ×3, `src/security.cyr` ×2, `src/agent.cyr` ×1).
- [ ] **Boxed reads → `boxed_tag` / `boxed_payload`:** `src/agent.cyr:38,39` ·
      `src/telemetry.cyr:568,569` · `src/llm.cyr:139,140` ·
      `tests/tcyr/test_coverage_1.tcyr:398,400,402,404`
- [ ] **Result-class migration — must land in the same sweep or it still will not build:**
      - `src/error.cyr:131-136` — `fn result_print_agnostik_err(res)` becomes `(t, e)`;
        `is_ok(res)` → `is_ok(t)`; `payload(res)` → `e`; update callers.
      - `src/agent.cyr:210` — `if (is_ok(parsed) == 1) { store64(info, payload(parsed)); }`
      - `src/main.cyr:39,53,60,115,120,320`
      - Tests: `test_v140_enum_parse.tcyr` (204 lines), `agnostik.tcyr` (6),
        `test_v137_hardening.tcyr` (3), `test_v130_slice_safety.tcyr` (2),
        `test_v150_capability_numbers.tcyr` (2), `test_audit_2026_04_26.tcyr` (1),
        `tests/bcyr/agnostik.bcyr` (1)
- [ ] `cyrius.cyml:8` → `6.6.2`, then `cyrius deps`, then **`cyrius distlib`** to regenerate
      `dist/agnostik.cyr`. Never hand-edit the bundle.
- [ ] Note honestly in the CHANGELOG: `src/security.cyr`'s `seccomp_errno` / `seccomp_trace` boxes
      have **no reader anywhere in agnostik**, so no security impact is demonstrated for those two.

### agnova — pin 6.4.43 · builds today · detonates on next `deps` · no `dist/`

- [ ] **Construction — no change.** 9 sites in `src/types.cyr:204,222,238,252,270,282,294,310,327`.
      Update the layout comment at `:168` to the `boxed_*` spelling.
- [ ] **Boxed reads → `boxed_tag` / `boxed_payload`:** `src/types.cyr:349,350` ·
      `src/executor.cyr:230,231,260,281,282` · `src/cli.cyr:203,226,227` ·
      `src/disk_backend.cyr:99,139,140,141,171,172,173,210,221,231` ·
      `tests/agnova.tcyr` — 23 `tag(` lines
      (`63,79,95,111,129,140,153,169,181,925,1053,1083,1094,1368,1396,1403,1408,1413,1417,1424,1734,1738,1744`)
      and the `SystemOp` subset of its 63 `payload(` lines.
      ⚠ `src/executor.cyr` decides **what to run on a disk** from `tag(op)`.
- [ ] **Result-class:** `src/cli.cyr:324` `var v = validate_config(cfg);` → `var vt, vv = …`;
      `:325` guard → `is_ok(vt)`; `:327,329,405,408,457` → `vv`.
      `src/validation.cyr:9` — the comment "Caller checks tag(result) == OK; on Ok, payload is a
      vec ptr" is now wrong twice over.
- [ ] `cyrius.cyml:7` → `6.6.2`, `cyrius deps`.

### The five agnostik-`dist` vendors — re-vendor **after** agnostik regenerates

Each carries `lib/agnostik.cyr` with 19 `tagged_new(` + 5 `payload(` and no definition.

- [ ] aethersafha  - [ ] anuenue  - [ ] ark  - [ ] kybernet
- [ ] mela — ⚠ its copy is from 2026-06-18 and 40 KB behind; separately stale.

---

## Phase 2 — repos broken on disk right now

### sigil — pin 6.6.0 · listed **"Done"** on `docs/ecosystem.md:10` · 91 errors

Vendored tree is internally incoherent: post-flip `lib/tagged.cyr` (Sep 6) beside pre-flip
`lib/sandhi.cyr` (Sep 4, 33 `payload(`), `lib/mabda.cyr` (26), `lib/yukti.cyr` (16),
`lib/sigil.cyr` (13). Size skew visible directly: `lib/sandhi.cyr` 679,136 B vs sandhi's
`dist/` 678,880 B; `lib/sigil.cyr` 1,079,160 B (Aug 14) vs 1,106,823 B (Sep 6).

- [ ] `cyrius lib sync --full`, or delete `lib/` and re-vendor, **after** 6.6.2.
- [ ] Its build already prints the skew as a *warning*. Treat that warning as a failure.
- [ ] Correct the "Done" status on `docs/ecosystem.md:10` — it was verified in the one direction
      that cannot fail (`cyrius/lib/<r>.cyr == <r>/dist/<r>.cyr`).

### vidya — pin 6.5.35 · post-flip lib under a pre-flip pin

⚠ This is the corpus `CLAUDE.md`'s Development Loop step 1 tells the next session to consult, and
it currently **teaches the deleted API as live**.

- [ ] `content/error_handling/cyrius.cyr` — `:18-19` documents `tagged_new`/`payload` as
      "legacy, still works"; `:34` `result_unwrap(r1)` @1; `:38` `result_unwrap_or(r2, 99)` @2;
      `:47` `unwrap(s)` @1; `:48` `unwrap_or(n, 99)` @2
- [ ] `content/pattern_matching/cyrius.cyr` — `:49` `result_unwrap(r)` @1; `:54` `payload(e)`;
      `:62,63` `unwrap_or(…)` @2
- [ ] `content/design_patterns/cyrius.cyr:71,73` — `result_unwrap(…)` @1
- [ ] `content/input_output/cyrius.cyr:48-52,67,70` — recipes teaching `result_unwrap(tcp_socket())`
- [ ] Closeout-mandated refresh of `content/cyrius/` for the two-class statement, the new
      `lib/boxed.cyr` module, and the corrected structural facts. Pin → 6.6.2, re-vendor.

---

## Phase 3 — the SIMD operand-slot Critical (compiler-side; consumers just re-vendor)

`lib/hisab.cyr:975-978` is the `m4_mul_vec4` block, miscompiled today on every target
(`f64v_scale(r, m + 0, HVec4_x(v), 4)` — `HVec4_x` is a `#derive(accessors)` getter, so it
inlines). hisab's own `src/mat4.cyr:131-134` is already hoisted for v2.11.3, so **the workaround
did not travel with the fold**.

⛔ **Do not file 13 downstream issues. The compiler is the defect.**

- [ ] After the bite-8 fix ships: re-vendor each, then remove the load-bearing hoist and its
      comment from hisab.
- [ ] attn11 - [ ] dhvani - [ ] garjan - [ ] ghurni - [ ] goonj - [ ] naad - [ ] nidhi
- [ ] prakash - [ ] prani - [ ] ranga - [ ] shabda - [ ] shabdakosh - [ ] svara

---

## Phase 4 — hashmap sentinel consumers

The library fix makes reads honest; it does **not** make key 0 storable.

- [ ] **agnosai** — `src/learning/optimizer.cyr:54` `store64(it + AGN_INTERN_NEXT_ID, 0);` → `1`.
      `_agnosai_q_key(0, 0) == 0` is the `MAP_U64_EMPTY` sentinel and is the most-visited cell of
      a fresh Q-learner. The `-1` "never interned" sentinel at `:63` stays unambiguous.
- [ ] **mabda** — two of four u64 caches bypass `_cache_safe_key`: `src/texture.cyr:207-223` and
      `src/shader_cache.cyr:46-52` (`map_u64_get(cache, _shader_hash(wgsl_source))`, an FNV-1a
      hash of shader source — the consumer the u64 surface was built for). Route both through
      `_cache_safe_key` until the library fix propagates.
      Also `mabda/cyrius.cyml:21` restates the deletion in a manifest comment.

---

## Phase 5 — single-var-bind repos (the largest bucket)

These have **no** accessor call — they bind a pair-returning stdlib function into one variable.
All are hard errors at 6.6.x.

- [ ] **phylax** (pin 6.5.35 — *wrongly listed as already-migrated*) — `src/utils.cyr:187`
      `var fd = tcp_socket();` · `:189` `var r = sock_connect(…)` · `:204` `var n = sock_recv(…)`
- [ ] **agora** — `src/descent.cyr:378`
- [ ] **agnosticos** — `scripts/dhcp-probe/src/dhcp_probe.cyr:299,316`
- [ ] **cyrius-yeomans-descent** — `src/server.cyr:207,211,213,1564`
- [ ] **t-ron** (pin 6.5.35, absent from both halves of the original survey) — `src/llm_scan.cyr:300,322`
      are hard binds. ⛔ **`:302` `if (sock_connect(fd, addr, port) < 0)` and `:317`
      `if (sock_send(fd, req, off) < 0)` are SILENT** — Err's tag is `1`, so those checks can never
      fire. Fixing the two loud sites leaves the two silent ones shipping.

Compiler-verified simulation (repo sources copied to `/tmp`, only `lib/tagged.cyr` +
`lib/result.cyr` swapped for 6.6.1, manifest `[build] entry` compiled):

| repo | before → after | breakdown |
|---|---|---|
| szal | 0 → **87** | 63 stackbind, 24 arity |
| nein | 15 → 64 | 44 stackbind, 5 arity |
| kavach | 8 → 37 | 23 stackbind, 6 arity |
| hapi | 2 → 28 | 26 stackbind |
| libro | 63 → 69 | 6 |
| agnodrm | 0 → 6 | |
| aegis | 33 → 36 | 3 |
| majra | 0 → 2 | |
| agnoshi | 0 → 2 | |
| yukti · mabda · sigil · bayan | clean both ways | already migrated |

---

## Phase 6 — the pre-flip cohort

~490 first-party `payload`/`tagged_new` sites. All hold a pre-flip `lib/tagged.cyr` and **build
today**. They break on their next `cyrius deps`, not before.

- [ ] cyrius-yeomans-descent 92 - [ ] nous 79 - [ ] agnodrm 37 - [ ] argonaut 36 - [ ] nein 31
- [ ] kavach 17 - [ ] sit 16 - [ ] takumi 14 - [ ] hoosh 13 - [ ] ark 12 - [ ] abaco 12
- [ ] majra 6 - [ ] dhvani 6 - [ ] daimon 5 - [ ] aegis 5 - [ ] rosnet 4 - [ ] ranga 4
- [ ] hadara 3 - [ ] puka 2 - [ ] kybernet 2 - [ ] bote 2

---

## Phase 7 — publisher `dist/` bundles carrying deleted-symbol calls

Regenerate in dependency order **before** any consumer re-vendors.

- [ ] agnostik (5 `payload` + 19 `tagged_new`) - [ ] agnodrm (14; core 5) - [ ] nein-mcp (9), nein (4)
- [ ] kavach (8 + 8 one-arg; kavach-confine 1 + 5) - [ ] nous (8) - [ ] sit (7) - [ ] abaco (4)
- [ ] dhvani (3) - [ ] agnosai (3 one-arg) - [ ] mishran (3 one-arg) - [ ] sankhya (11 one-arg)
- [ ] ranga-gpu (2) - [ ] rosnet-gpu (2) - [ ] bote (1) - [ ] samay (1) - [ ] stiva (1)
- [ ] majra-backends (1+1)

**Already clean** (comments only): mabda, bayan, sandhi, sigil, yukti, vani, yantra.

---

## Phase 8 — unrelated damage found in passing

- [ ] **Six repos with uncommitted stdlib overwrites from 2026-09-03** — `anuenue`, `bannermanor`,
      `commandress`, `cyim`, `iam`, `kii`, each with a modified `lib/io.cyr` + four
      `lib/syscalls_*.cyr` matching cyrius **6.5.36** against pins of 6.5.35/6.5.27. **Predates
      this campaign.** Remedy: `git checkout -- lib/` in each.
- [ ] **Four nested vendoring sites** a repo-root `cyrius deps` will not reach:
      `chakshu/ai/lib`, `tarang/cyr/lib`, `secureyeoman/yeo-cy-test/lib`,
      `agnos/build/vani-tone-smoke/consumer/lib`.
- [ ] **`agnosys` is a phantom.** `docs/ecosystem.md:10` lists it as Done; no `~/Repos/agnosys`
      exists, while **14 repos vendor a `lib/agnosys.cyr` containing 32 `payload(` calls.**
      Surfaced rather than skipped, per the cross-repo-smoke rule — needs a maintainer answer on
      where that bundle comes from.

**Verified clean, no action:** all four `CLAUDE.md` symlink-audit commands return zero hits. The
v6.5.37 file-shaped variant has not reappeared; the current vendoring skew has a different cause
(snapshot fallback, not symlinks).

---

## Stated limits of this census

Flagged rather than asserted, so a later reader does not treat these as measured:

- The 5,961 vendored-site figure and the 46 one-parameter Result helpers rest on a **single pass**.
- The 40-repo fail list was **compile-verified for 9 repos**, not end to end; the rest is a
  scope-aware heuristic.
- `grep` in this environment is a ugrep shim that silently under-matches
  `(^|[^_a-zA-Z0-9])name\(` and honours `.gitignore`. **Use `command grep` for every count** —
  multiple investigation passes lost real call sites to it.

---

## Related

- `CHANGELOG.md` [6.6.2] — the repair release
- `CLAUDE.md` → Working Agreements → Execution integrity — the durable rule
- `tests/gates/toolchain/removed_symbol_census.sh` — the gate that forces this census in future
- `docs/ecosystem.md` — fold table (single source of truth for vendored versions)
