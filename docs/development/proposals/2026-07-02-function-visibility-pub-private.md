# Function Visibility (pub / private) — v6.4.x arc candidate

**Status:** **FILED for full review at v6.4.x arc open** (2026-07-02). **No decisions committed.**
This is a grounded design *exploration* — the levers in "Open decisions" are chosen at arc-open,
not here.

**User lean (2026-07-02 — a lean, NOT a commitment):** the `_`-prefix as the private marker
appeals (it enforces the convention the ecosystem already follows). Everything else is open;
nothing is to be treated as decided until the arc-open review.

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

## Open decisions — resolve at the v6.4.x arc-open review

1. **Marker:** derive-from-`_` (zero churn; must audit) **vs** explicit `pub`/`private` keywords
   (the doc's model; needs a migration) **vs** hybrid (`_` default + keyword override).
2. **Boundary:** file (needs the file-id substrate) **vs** dep (coarser; would lean on the manifest).
3. **Default:** public (additive) **vs** private-across-files (clean, breaking).
4. **`_`-audit (do this FIRST at arc-open):** *how many `_`-prefixed fns are actually called
   cross-file today?* Grep the repo + ecosystem for calls to a `_`-prefixed fn from a different
   source file. **That number decides whether derive-from-`_` is truly zero-churn** — every
   convention violation needs a `pub` escape hatch or a rename. Do not commit to derive-from-`_`
   before this measurement.

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
