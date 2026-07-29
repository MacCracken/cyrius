# Function/Var Visibility (public / private) — **v6.5.0 OPENER**

**Status:** ✅ **SHIPPED in v6.5.0.** Design committed by the user 2026-07-22; delivered on the
`privatefns` branch. Two corrections this doc made that the implementation disproved: (a) `fn_flags`
is no longer at `0x17A000` — that band was FREED at v6.4.75 and the table is now `_fnflg_base`,
lazy-alloc'd; (b) the "linchpin gap" was smaller than described — the preprocessor's `#@file` markers
and `FM_BUILD` already existed for CVE-31 diagnostics, so the arc needed an index-returning sibling of
`FM_LOOKUP`, not new preprocessor infrastructure. What the doc did NOT anticipate: that map was
silently wrong (no resume marker on leaving an include), and enforcement needed 13 resolution paths,
not 2. Original status: **DESIGN COMMITTED (user, 2026-07-22). Scheduled as the v6.5.0 OPENER** — no longer
the last 6.4.x arc. 6.4.x stays open for agnos work + bugs and closes out on its own; this arc does
not gate that closeout.

## Committed design — file-scoped opt-in, default public

1. **A top-level `private` declaration in a source file flips that FILE to private-by-default** —
   every `fn` (and `var`) in it becomes private to the file.
2. **Inside such a file, a `public` moniker in front of an individual `fn`/`var` re-exposes it.**
3. **No declaration = today's behaviour: everything public** — unless an item is individually
   declared private.
4. **The `_`-prefix convention is explicitly LATER** — it may come back as a convenience for
   declaring additional items, but it is *not* part of this arc.

**Why this is materially better than the model this doc originally forced.** The earlier framing
(hybrid `_`-default + keyword override) was blocked by its own prerequisite: the `_`-audit found
**165 `_`-prefixed fns are called cross-file**, so derive-from-`_` was never zero-churn and every
violation would have needed an escape hatch or a rename. This design **sidesteps that entirely** —
nothing is derived from names, so the audit result stops being a blocker. It is also **opt-in per
file**, which means the whole ecosystem keeps compiling unchanged on day one and adoption is a
per-file decision rather than a migration.

**Scope note:** visibility covers **`fn` *and* `var`** (the user specified "function/var") — the
original doc was fn-only.

**Open implementation detail (not a design question):** the exact spelling of the file-level
declaration — cyrius already has a directive vocabulary (`#ifdef`, `#derive`, `#regalloc`,
`#pe_import`), so a `#private`-style directive fits the language; the keyword form is equally
workable. Pick at implementation. Note `pub` is already lexer token 73 but **dead**
(consumed-and-ignored at `parse_fn.cyr:1570`), and so is `shared` — decide whether `public`
reuses/renames that token.

**Prior art:** this arc would execute **"Phase 2 — `pub` enforcement"** already sketched in
[`module-manifest-design.md`](../module-manifest-design.md) (Phase 1 = the v6.2.x manifest/deps,
shipped). Phases 3 (qualified `use`) and 4 (separate compilation) remain later/aspirational.

---

## Why — the bug classes a visibility boundary would close

Cyrius has **one flat global namespace**: after `include` (textual concatenation) every top-level
`fn` is globally callable. Documented consequences:

- **The recurring `dynlib_*` dead-code corruption** (CLAUDE.md, v5.5.30–.33): a downstream repo's
  dead-code pass deleted `dynlib_bootstrap_environ` / `_read_auxv` / `_auxv_get` **four times**
  because, from that repo's view, an internal helper *looked* unused. File-private helpers are
  invisible to an external pass — it cannot see, misjudge, or delete them.
- **Enum-shadow (`[6.3.24]`)** and **thread-local slot-collision (`[6.3.25]`)**: no encapsulation →
  any name/symbol can clash or be reached across "modules"; both surfaced only at runtime.
- **The api-surface snapshot is a *convention*, not enforcement**: `docs/api-surface.snapshot`
  (~4,500 fns, keyed `module::fn/arity`, "public" = any fn **not** prefixed `_`) is a review gate;
  a consumer can still call any `_internal` helper. The language does not enforce the API surface
  it already tracks.

## Substrate — what exists today (grounded; the arc builds on this)

| Piece | Location | State |
|---|---|---|
| **Storage** | `fn_flags` @ `0x17A000`, 8 B/fn — bits 0–5 used (`#must_use`/reserved/`#deprecated`/`#pure`/`#io`/`#alloc`), **bits 6–63 FREE** | a `private` bit = **bit 6**, next to the effect annotations |
| **Resolution** | `FINDFN` `src/frontend/parse_fn.cyr:236-263` — one global namespace, FNV-1a hash | enforcement point = **`PARSE_FNCALL` right after `FINDFN`**, + the tail-call path (`parse_fn.cyr:~381`) |
| **`pub` keyword** | lexer token **73**; `src/common/util.cyr:519-522` | **EXISTS BUT DEAD** — consumed-and-ignored ("skip in pass 1"); `GPUB`/`SPUB` accessors were *removed* as dead state; only the `0x18FED0` region stays reserved |
| **`GMOD`/`SMOD`** | `parse_fn.cyr:1978-2001` | **name MANGLING, not scoping** (`mod_fn` uniqueness) — NOT a usable visibility boundary |
| **Pass-1 prescan** | `_prescan_fn_sig` `parse_fn.cyr:1795-1820` | registers fn sigs before pass-2 → visibility is knowable at resolution time |
| **Undefined-fn hard-error** | `src/backend/x86/fixup.cyr:712-721` (v6.3.2) | **reusable verbatim** — a rejected private call becomes "call to undefined fn" |
| **DCE reachability** | `fixup.cyr:355-510` | file-private + no in-file caller = *definitively* dead → visibility sharpens DCE |
| **api-surface tool** | `programs/cyrius_api_surface.cyr`, `docs/api-surface.snapshot` | computes `module = filename`, `public = non-_`; this is the **migration data** + the unenforced convention |

### The linchpin gap — no per-function origin-file id

The compiler does **not** track which source file a `fn` came from (the api-surface tool derives
`module=filename` *externally*). **File-scoped `private` requires new preprocessor infrastructure:**
`lex_pp.cyr` must stamp a file-id per included source file, track the "current file id" through the
lex stream, and store `_fnt_fileid[fi]` per fn. **This is the real work of the arc** — the flag and
the enforcement check are small; the file-id substrate is the effort.

## Design space + recommended (NOT committed) shape

- **Boundary = file** — matches the api-surface `module::fn` convention and is the intuitive unit;
  `GMOD` isn't a usable boundary and a dep is coarser. (Cost: the file-id substrate above.)
- **Default = public** — byte-identical + additive; avoids the Rust-style "annotate 4,500 fns `pub`"
  breakage that default-private would force on the ecosystem.
- **Marker = derive from the `_`-prefix** (+ explicit `pub`/`private` override) — near-zero churn
  because it enforces the universal existing convention; `_helper` → file-private, `foo` → public.
  **[This is the user's lean — validate at arc-open with the audit below.]**
- **Enforcement = warn → flip to hard-error** — the proven **v6.3.2 undefined-fn-flip playbook**
  (measure blast radius in warn-mode, then flip default-on with zero `--allow-*` sprinkling).

## ~~Open decisions~~ — RESOLVED (user, 2026-07-22)

1. **Marker:** ✅ **explicit** — a file-level `private` declaration + a per-item `public` moniker.
   *Not* derive-from-`_`, and *not* the hybrid this doc previously forced.
2. **Boundary:** ✅ **FILE.** The declaration applies to the source file it appears in. (This still
   wants the Phase-1 file-id substrate below; that part of the plan stands.)
3. **Default:** ✅ **PUBLIC** — additive and non-breaking. The private default is **opt-in per file**,
   so nothing in the tree or the ecosystem changes behaviour until a file opts in.
4. **`_`-audit:** ✅ **moot for this design.** It was run and *disproved* zero-churn (165 `_`-prefixed
   fns are called cross-file), which is exactly why the committed design derives nothing from names.
   Keep the number on record for the possible later `_` convenience layer — if that ever lands, those
   165 sites are the migration surface it must answer for.

## Proposed phased arc (candidate structure — not pinned)

- **Phase 1 — file-id substrate** *(the real work):* preprocessor stamps a file-id per source file;
  store `_fnt_fileid[fi]`. **Recorded, not enforced → byte-identical.** Gate: file-id correct per fn.
- **Phase 2 — visibility flag + warn-mode enforce:** `fn_flags` bit 6; set from `_`-prefix (or the
  chosen marker); `PARSE_FNCALL` **warns** on a cross-file private call. **Run the `_`-audit here.**
  Gated proof; byte-identical default.
- **Phase 3 — flip to hard-error + adopt + sharpen DCE:** flip cross-file private → error (reuse
  v6.3.2); mark a flagship lib's internals private (e.g. `fdlopen.cyr` `dynlib_*`) to *prove* it
  blocks the corruption; feed visibility into DCE; make the api-surface snapshot visibility-derived.
  Cross-OS + measure→flip playbook.
- **Phase 4 — docs/vidya:** language guide + field notes; mark `module-manifest-design.md` Phase 2
  shipped.

## References

- `docs/development/module-manifest-design.md` — Phase 2 (`pub` enforcement) that this arc executes.
- `docs/api-surface.snapshot` + `programs/cyrius_api_surface.cyr` — the migration data / convention.
- `fn_flags`: `src/frontend/parse_fn.cyr:2153-2195`; heap map `src/main.cyr:181-192`.
- `FINDFN`: `src/frontend/parse_fn.cyr:236-263`; enforcement site: `PARSE_FNCALL` + tail-call `~381`.
- dead `pub` token: `src/common/util.cyr:519-522`, lexer token 73.
- undefined-fn hard-error (reuse): `src/backend/x86/fixup.cyr:712-721`.
- bug classes: CHANGELOG `[6.3.24]` (enum-shadow), `[6.3.25]` (slot-collision); CLAUDE.md `dynlib_*`.
