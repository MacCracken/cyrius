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
>
> **Live census — re-derived 2026-09-10** (126 dirs under `~/Repos` carrying a `cyrius.cyml`):
> **26 on 6.6.2** · 20 on 6.6.0/6.6.1 · 72 on 6.5.x · 8 older. On 6.6.2:
> aethersafha · agnodrm · agnostik · agnova · anuenue · ark · bote · chitra ·
> cyrius-yeomans-descent · drishti · hisab · hoosh · kavach · kybernet · majra ·
> mela · nein · nous · samay · samvada · sankhya · sit · stiva · szal · t-ron · thoth.
>
> ✅ **Released this pass:** t-ron 2.1.10 · majra 2.7.2 · nein 1.6.11 · drishti 0.7.130 ·
> thoth 0.44.6 · stiva 3.0.20.  ⏳ **Awaiting a tag:** bote 3.3.8.
>
> ⛔ **A LOCAL GATE RUN IS NOT A CI RUN.** t-ron 2.1.10 was cut locally-green and CI
> could not produce a binary. `path = "../sibling"` makes `git`/`tag` inert and
> resolves from the WORKTREE; CI has no siblings and clones the tag. t-ron's
> `path = "../bote"` chained into bote's own `path = "../majra"` and reached an
> unreleased majra, while CI cloned bote 3.3.7 → **majra 2.7.0**. **31 repos carry
> such overrides across 99 dep entries.** Tell: `cyrius deps` printing `N deps locked`
> *without* a `M commit-pinned` suffix. Verify by staging the tracked tree OUTSIDE
> `~/Repos` and running the workflow's own `run:` blocks under `bash -e`
> (`memory/ci-faithful.py`). Second half of the same incident: t-ron's Build step was
> `cyrius build … | tee`, which takes **tee's** exit status under GitHub Actions'
> `bash -e`, so a failed compile read GREEN and surfaced two steps later as a missing
> file. ~20 consumer workflows still have unguarded `| tee` pipelines.
>
> ✅ **bote 3.3.8 closes the landmine at the source.** Both breaks are fixed where they
> live rather than worked around downstream: majra re-pinned 2.7.0 → **2.7.2** (the
> `_sub_new/1` vs `_sub_new/2` collision became a hard error at **6.5.37**, and bote
> pinned 6.5.35 — one release below it, which is why it sat latent here while every
> consumer inherited it), and `src/transport_unix.cyr:144`'s bare `payload(` migrated,
> so `dist/bote.cyr` now scans **payload=0**. t-ron's and nein's explicit
> `[deps.majra]` overrides are now redundant and can be retired against 3.3.8.
> **Next, and unblocked by it:** phylax 1.2.6 · agnosai 2.0.7 (both `bote-core`,
> pin 6.5.35) · daimon 2.1.2 · itihas 2.5.0 (both full `dist/bote.cyr`, pin 6.5.36;
> daimon also has 3 bare `payload(` of its own).
>
> ⚠ **A missing gate rots silently.** bote's CI had **no fuzz step**, and all four
> `fuzz/*.fcyr` harnesses had stopped compiling at cyrius **6.1.25 (2026-06-10)** when
> `lib/json.cyr` was carved into `lib/bayan.cyr` — four minors invisible. Two of them
> also carried **18 undefined functions** and "passed" only because every call site was
> unreachable, so an exit-code-only gate would have missed that half. bote 3.3.8 adds a
> Fuzz step asserting BOTH a zero failure count and zero `undefined function` lines.
> Worth checking wherever a repo ships `fuzz/` or `benches/` without a CI step for it.
>
> 🧊 **Held back deliberately** for a coordinated **6.6.3** pass, per the user: the
> twelve folded stdlibs — sandhi · vani · sakshi · patra · sigil · yukti · sankoch ·
> niyama · mabda · bayan · ganita · yantra. drishti's committed `lib/` carries stale
> copies of *exactly* that set; left alone so they move once, together.

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

⚠ **CORRECTED — the original version of this warning was WRONG, and it is left visible rather
than deleted because it shaped the plan.** It said `cbt/deps.cyr` "falls back to the installed
snapshot when the pinned one is absent, so it vendors 6.6.1's stdlib regardless of the pin".
**It does not.** Measured: a repo pinned to an uninstalled version **hard-errors and vendors
nothing** (`_dep_find_stdlib_dir` exits 1 rather than sliding to latest), and `cmd_lib_sync`
behaves the same way. The pin genuinely shields.

⛔ **So how agnostik came to hold 6.6.x libs under a 6.5.35 pin is STILL UNEXPLAINED.** What is
known: 12 of its 29 `lib/*.cyr` were rewritten at **09:40:42 on 2026-09-09** and are byte-identical
to the 6.6.1 snapshot, and `_dep_copy_file` only rewrites files that DIFFER — which is why 12 of 29
moved rather than all 29. Recorded as open. Until the mechanism is known, treat a pre-flip repo's
vendored `lib/` as something to verify by content and mtime before and after any toolchain
operation, not something the pin is guaranteed to protect. 89 repos still hold a pre-flip
`lib/tagged.cyr` and build fine today.

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
      for v in <versions>; do CYRIUS_NO_ACTIVATE=1 "$CL" install "$v"; done

      ⭐ **`CYRIUS_NO_ACTIVATE=1` was added in v6.6.2 for exactly this loop.** Without it
      `install.sh` ACTIVATES whatever it installs — it repoints `~/.cyrius/bin`, `~/.cyrius/lib`
      and writes `current`. Since `~/.cyrius/lib` is the default stdlib source every
      `cyrius deps` reads, a naive restore loop leaves the machine's stdlib pointing at whichever
      version happened to be installed last: one such loop ended with the box on 6.2.6 and
      `~/.cyrius/lib` holding a 2026-era stdlib. With the flag a restore is a pure ADD.
      ⚠ Note `~/.cyrius/signed-since` is a TOFU downgrade floor (6.6.1 at time of writing);
      restoring anything below it may prompt or refuse, and that is a deliberate safety
      mechanism, not a bug to work around.

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

### agnostik — ✅ **DONE — v1.6.0, pin 6.6.2** (was 6.5.35, broken on disk)

> **Landed 2026-09-10.** `cyrius build` OK (675,824 B) · `cyrius test` **18 files, 788 assertions,
> 0 failures** · api-surface gate ok (916 fns, matches) · `dist/` regenerated (3,942 lines).
>
> ⭐ **All 19 `tagged_new` sites unchanged, exactly as designed** — it returned under its own name
> because its meaning never changed. Only the 6 reads moved to `boxed_tag`/`boxed_payload`. Zero
> bare `payload(`/`tag(` remain in `src/`, `tests/` or `dist/`.
>
> ⚠ **1.6.0, not 1.5.2.** `result_print_agnostik_err` went `/1` → `/2` — forced, since under the
> value form no one-argument fn can receive a Result and read its payload. Only public-surface
> delta of the 916. ⚖️ Six repos vendor the definition and **none call it**, so it breaks no
> consumer code — but the surface changed incompatibly, so it is a minor.
>
> ⚠ **Zero mixed-return warnings** — the 19-silent-defect shape from yukti's 6.6.0 migration did
> not occur; all six Result-returning parsers return a pair on every path.
>
> ⚠ Found in passing: `lib/hashmap_fast.cyr` is an ORPHAN — unreferenced, not in `[deps].stdlib`,
> so `cyrius deps` never refreshes it (dated 2026-08-23). Recorded, not deleted.

<details><summary>original worklist, kept for review</summary>


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

</details>

### agnova — ✅ **MIGRATED — pin 6.6.2** (was 6.4.43) · ⏸ version NOT bumped, deliberately

> **Landed 2026-09-10.** `cyrius build` OK (768,176 B) · `cyrius test` **344 assertions, 0
> failures** · no public API change (every touched fn keeps its arity).
>
> ⭐ All 10 `tagged_new` sites unchanged; 24 reads in `src/` + 68 in tests moved to `boxed_*`.
> ⚠ `src/executor.cyr:230,260,281` decides **what to run on a disk** from the tag — under 6.6.0's
> redefined `tag()` that dispatch would have silently received the POINTER. All six verified
> against their `tagged_new` producers.
>
> ⏸ **VERSION LEFT AT 0.7.0 ON PURPOSE.** agnova has substantial uncommitted in-flight work (the
> `--user is now optional` doctrine change across 5 files, with its own `[Unreleased]` entry).
> Cutting a release would ship that unfinished work as a side effect — the maintainer's call, not
> the migration's. The migration entry is written under `[Unreleased]` alongside it. In-flight diff
> patched to the session scratchpad as a safety net; verified untouched after migration.
>
> ⚠ **PRE-EXISTING, not from this migration: 35 vendored files differ from the pinned snapshot**
> and 11 folded sibling bundles are years behind (sigil 3.10.1 vs 3.12.16, sandhi 1.7.3 vs 1.9.16,
> yukti 2.2.9 vs 2.3.10, bayan 1.1.0 vs 1.5.5, …). Nine still call retired `payload()`/`tag()`
> (79 sites) but ALL are inert — undeclared in `[deps].stdlib`, so `cyrius deps` never refreshes
> them and nothing reaches them. `lib/sigil.cyr` IS included, but by `lib/tls_native.cyr`, itself
> undeclared: orphan including orphan. ⚠ agnova **tracks `lib/` in git**, so these are committed
> dead weight dated 2026-07-10. Refreshing 11 bundles across many versions of API change is its own
> piece of work and is deliberately NOT bundled here.

<details><summary>original worklist, kept for review</summary>


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

</details>

### The five agnostik-`dist` vendors — re-vendor **after** agnostik regenerates

Each carries `lib/agnostik.cyr` with 19 `tagged_new(` + 5 `payload(` and no definition.

- [ ] aethersafha  - [ ] anuenue  - [ ] ark  - [ ] kybernet
- [x] **mela — ✅ DONE, v1.0.2, pin 6.2.21 → 6.6.2.** `cyrius test` **492 assertions, 0 failures**.
      `lib/agnostik.cyr` refreshed 120,192 → 160,515 B (agnostik 1.6.0). Zero first-party
      `payload`/`tagged_new` sites, so the flip needed no source change — but the bump surfaced
      **two real defects**:
      - ⛔ **A use-after-return, latent for years.** `FLUTTER_FORCE_SCALE_FACTOR` was built with
        `str_new(&scbuf, sclen)` on a STACK LOCAL. `str_new` ALIASES (lib/str.cyr:51) and
        `str_sub` "shares data with parent" (lib/str.cyr:199), so the `Str` in the env map pointed
        into a dead frame. It worked by luck until the 6.2.21 → 6.6.2 stack layout shifted:
        measured `str_len` = 4 (correct) with the bytes reading back as **four spaces**. Fixed with
        a load-bearing `str_clone`. Swept the shape — the only such site in `src/`.
      - **13 stale `json_v_parse_str` calls across 7 files.** bayan renamed its buf+len JSON entry
        `_str` → `_buf` in ITS OWN 6.6 migration (bayan `97bdc73`); mela was four minors behind so
        the test suite would not compile. ⚠ My first grep of these used `| head -3` and I treated
        the truncated list as complete — caught on the next build.

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

## Migration ledger — what has actually shipped

Recorded per repo as it completes, with **corrections to this file's own estimates** where the
measured surface differed. Each row was built, tested and gated locally before the version bump;
the user tags and pushes.

| repo | version | cyrius pin | first-party sites | state |
|---|---|---|---|---|
| agnostik | 1.6.0 → **1.6.1** | 6.5.35 → 6.6.2 | 19 `tagged_new` kept · 6 reads · 1 arity change | ⏳ **1.6.1 awaiting release** |
| agnova | **0.7.1** | 6.4.43 → 6.6.2 | 10 kept · 92 reads | ✅ released |
| mela | **1.0.3** | → 6.6.2 | 13 `json_v_parse_str` → `_buf` | ✅ released |
| nous | **1.4.0** | → 6.6.2 | 71 value-form sites | ✅ released |
| ark | **1.4.2** | → 6.6.2 | 1 `bayan_json_v_parse_str` | ✅ released |
| anuenue | **1.3.6** | 6.5.35 → 6.6.2 | **0** | ✅ ready to tag |
| kybernet | **1.6.20** | 6.5.36 → 6.6.2 | **65** | ✅ released |
| agnodrm | **1.6.0** | 6.5.35 → 6.6.2 | **27** | ✅ released |
| samay | **1.1.2** | 6.5.36 → 6.6.2 | **33** | ✅ released |
| kavach | **3.12.5** | 6.5.35 → 6.6.2 | **43** | ⏳ awaiting tag |
| aethersafha | **0.16.23** | 6.5.33 → 6.6.2 | **7** | ⏳ blocked on kavach 3.12.5 |

### ⚠ STATUS AS OF 2026-09-10 — THE SWEEP IS ~11% DONE, DO NOT ARCHIVE THIS FILE

Measured live, not read off the checkboxes above:

| cyrius pin | repos |
|---|---|
| **6.6.2** (the repair release) | **14** |
| 6.6.0 / 6.6.1 — post-flip, NOT on the repair release | **20** |
| 6.5.x or older | **92** |
| no manifest / no pin | 16 |

**39 repos still call the retired accessors** (`payload` / `tagged_new` / `is_tag`) in their own
`src/`. Every Phase 4 and Phase 5 site named above was re-checked against live code on this date
and is still present verbatim — `phylax/src/utils.cyr:187`, `agora/src/descent.cyr:378`,
`t-ron/src/llm_scan.cyr:300` and `cyrius-yeomans-descent/src/server.cyr:207` are all still
`var <one> = tcp_socket();`, and `agnosai/src/learning/optimizer.cyr:54` still seeds the intern
table at the reserved key `0`. (One drift: the `mabda/src/texture.cyr` line numbers have moved.)

⭐ The 20 repos on **6.6.0/6.6.1** are the least obvious bucket and the most likely to be mistaken
for done: they parse the value form, so they build, but they are not on the release that restored
`lib/boxed.cyr`, fixed the SIMD operand-slot Critical, or fixed the `map_u64` sentinel keys. Two
of them — `sigil` and `bayan` — are *publishers* whose bundles reach many consumers.

### Corrections to this file's estimates

⚠ Two of this document's own per-repo counts were **wrong in the same direction** — they counted
vendored `lib/`, which a re-vendor refreshes, as first-party work:

- **kybernet** was listed at *"38 sites in 10 files"*. Measured: **2** in first-party `src/` before
  the re-vendor; the other 43 were in vendored `lib/`. After re-vendoring to 6.6.2 the *real*
  first-party surface turned out to be **65** — larger than the estimate, and in different files.
  The estimate was wrong in both directions at once because it was measuring the wrong tree.
- **anuenue** was listed with *"1 payload site"*. Measured: **zero**. The one hit
  (`src/filter.cyr:41`) is the English word "payload" inside a comment.

⭐ **The lesson is this file's own lesson, applied to itself**: a count taken over the wrong tree
reads as a measurement. The only reliable enumeration is **the compiler after the re-vendor** —
a single-variable bind of a pair and a 1-argument `result_unwrap` are both hard errors at 6.6.2,
so the migration surface can be measured rather than estimated. Do that first for every remaining
repo, instead of trusting the tables above.

### Findings that were not migration work

- ⛔ **`health_check_new` mis-bound between agnostik and argonaut** — both exported the name at
  different arities for different types (agnostik 0-arg probe descriptor; argonaut 6-arg
  `HealthCheck`). "Last definition wins", so in a consumer vendoring both every call to the loser
  read garbage registers. **Live and silent since agnostik 1.3.5 (2026-08-24)**, through every
  release since; pre-6.6.2 cyrius treated a same-name different-arity duplicate as a *warning*.
  Fixed in **agnostik 1.6.1** (renamed its side to `agnostik_health_check_new` — one caller, no
  external consumers).
  ⚠ **kybernet is the only affected consumer.** An earlier draft of this line also named *stiva*,
  on a grep that found `health_check_new` in its sources. That was wrong and is corrected here:
  stiva depends on neither agnostik nor argonaut — it declares its **own** `health_check_new(command)`
  at arity 1 in `src/ansamblu.cyr:83`. Three independent definitions of the name exist in the
  ecosystem; only the two that get vendored together ever collided. ⭐ Same error shape as the
  survey this whole document exists because of: a name matched, and the match was reported as a
  relationship without checking whether the two things ever meet.
- ⛔ **agnostik's `scripts/version-bump.sh` printed `git tag v${NEW}`** while all 20+ of its tags
  are bare and every consumer pins `tag = "1.6.0"`. Following it would have published a tag no
  `[deps.agnostik]` entry could resolve. Fixed in 1.6.1.
- **anuenue carried an orphaned `lib/agnosys.cyr`** — a 335 KB `cyrius distlib` bundle of agnosys
  1.4.3 from 2026-06-19, with no `include` anywhere and no `[deps.agnosys]` to regenerate it. It
  held **32** retired-accessor calls and was the only file in the tree still calling them. Deleted,
  not migrated: an orphan bundle is exactly what a blanket `--allow-undef` waves through.
- **libro 2.10.0 pins patra 1.13.10** while the current release is 1.14.1, so every libro consumer
  gets `refusing to overwrite stdlib leaf 'patra'`. Benign (cyrius keeps the newer snapshot) but
  stale on libro's side.

### Language limitation surfaced by the migration

There is **no `t, v = f();` reassignment form** — only `var t, v = f();` binds a pair. Any loop
that re-polls a `Result` must bind a fresh pair per iteration and copy it into the carried one.
Written the obvious way (`rt = f();`) it compiles and **silently keeps only the tag**. Hit in
`kybernet/src/main.cyr:_remove_cgroup_settled`; it will recur in every repo with a retry loop.

---

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
