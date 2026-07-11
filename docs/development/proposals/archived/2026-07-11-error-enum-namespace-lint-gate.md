# Error-enum namespace lint gate — base-owned bare `ERR_*`, leaves must prefix

**Status:** **FILED for review (2026-07-11). No decisions committed.** A grounded
design exploration of an *enforcement* mechanism; the levers in "Open decisions"
are chosen at review, not here. cyrius already **detects** the underlying
collision (see Substrate) — this is about turning detection into an enforceable,
attributable gate.

**User lean (2026-07-11 — a lean, NOT a commitment):** sakshi, as the ecosystem's
**base logger** (the foundation include every AGNOS Cyrius project pulls in), owns
the canonical *unprefixed* `ERR_*` error-code set; **every other lib must prefix
its error enum** (`<LIB>_ERR_*`). A lint gate keeps that honest so bare `ERR_*`
stays sakshi-only. Mechanism is open.

**Origin / prior art:** sakshi
`docs/development/issues/2026-06-23-err-timeout-enum-collision-namespace.md`
(**Option B**), parked for sakshi **3.0.0**. Same "convention needs enforcement,
not hope" theme as the api-surface snapshot in
[`2026-07-02-function-visibility-pub-private.md`](2026-07-02-function-visibility-pub-private.md)
(public = non-`_`, a review gate the language does not enforce).

---

## Why — the collision class this closes

Cyrius enum members are **global constants** — an `enum` does not namespace them
(`parse_types.cyr:265`; fold table `enum_const_val` @ `0x1D8000`, bit 63 = "is
enum const"). Domain-agnostic error enums therefore collide **by name** across
libs that a consumer pairs:

| Library | Enum | `ERR_TIMEOUT` |
|---|---|---|
| **sakshi** (base logger) | `ErrCode` | **5** |
| yukti | `YuktiErrorKind` | 9 |
| ai-hwaccel | `DetectionError` | 3 |
| sandhi (already prefixes) | — | `SANDHI_ERR_TIMEOUT = 4` |

Textual `include` + last-definition-wins → a consumer pulling sakshi **and**
yukti/ai-hwaccel gets one global `ERR_TIMEOUT`, whichever is last. sakshi's
`sakshi_err_new` packs the low-16 `code` literal into its `[63:32 ctx][31:16
cat][15:0 code]` i64, so a foreign winner (`ERR_TIMEOUT = 3`) silently repacks
`3` where sakshi documents `5` — a **value-dependent miscompile**, not just noise.
Note the *enum names* are already distinct (`ErrCode` vs `YuktiErrorKind`); only
the **members** are bare.

## Substrate — what exists today (grounded)

| Piece | Location | State |
|---|---|---|
| **Enum → global const** | `src/frontend/parse_types.cyr:265`; fold table `0x1D8000` (1024 × 8 B, bit 63 = is-enum-const) | members registered as flat globals — the root of the collision |
| **Conflicting-value redefinition detection** | `parse_decl.cyr` `CHKDUPVAL` (v6.2.11, issue `2026-06-14`) for `var` globals; **mirrored at the enum-member site** in `parse_types.cyr` | **already fires a warning** on a conflicting int-literal redefinition — this is the "last-wins **with a warning**" today |
| **Enum-shadow hard-error** | `CHK_ENUM_SHADOW`, `parse_types.cyr` (v6.3.24) | a *non-int* (string/expr/struct) shadow of an enum const is already a **hard error** (the dangerous silent-miscompile case) — precedent that enum-const collisions can be promoted past "warning" |
| **Linter** | `programs/cyrlint.cyr` — `lint_*(buf, total)` textual rules, driver at `:819-820`, `#skip-lint` exemption | where a new proactive per-file rule slots in; run per-file as `cyrius lint <f>` |
| **CI lint gate** | `programs/checks/lint_fmt.cyr` (cyrfmt + cyrlint + parse-drift + doc-coverage) | the ecosystem-facing gate a new rule would join |
| **Convention-not-enforcement precedent** | `docs/api-surface.snapshot` (public = non-`_`) | exactly the pattern here: a tracked convention the language doesn't enforce |

## The gap

The collision is **detected** (the conflicting-value enum-const warning) but not
**enforced**, and detection has two blind spots:

1. **Reactive only.** The warning fires solely when *both* libs land in one
   compilation. A leaf lib defining a bare `ERR_TIMEOUT` in isolation sees
   nothing until some downstream consumer pairs it with sakshi.
2. **No ownership attribution.** The warning says "these two collide," not "the
   base logger owns `ERR_*`; **you** (a leaf) must prefix." Nothing tells an
   author the rule, so the warning gets tolerated and the debt compounds.

## Design space + recommended (NOT committed) shape

Two complementary mechanisms; the "lint gate" ask is (1).

**(1) A proactive cyrlint per-file rule — `lint_error_enum_namespace` [primary].**
A new rule in `programs/cyrlint.cyr` that flags an `enum` defining bare,
ecosystem-shared error members (`ERR_*`) in a **non-owner** file — caught at the
*leaf lib's own* CI, independent of include context, before any consumer pairs
them. The open sub-question is how the rule knows sakshi owns `ERR_` **without
hardcoding "sakshi":**

- **(1a) Positive ownership pragma [lean].** The owning file declares the prefix
  it claims, e.g. `#lint-owns-prefix ERR_` in sakshi's `error.cyr`. cyrlint flags
  a bare `ERR_*` enum member in any file that does **not** carry the matching
  claim. Single source of truth, no allowlist, and it generalizes to other
  shared prefixes later.
- **(1b) Config allowlist.** A short cyrlint config maps `ERR_ → sakshi/error.cyr`
  (owner). Simpler to ship; a second place to keep in sync.
- **(1c) Universal-prefix rule.** Require *every* error-enum member to be
  module-prefixed and let sakshi opt out via `#skip-lint` on its enum. Simplest
  rule, but frames sakshi's canonical set as "exempted" rather than "owned."

**(2) Compiler-side collision elevation [complementary backstop].** Promote the
existing conflicting-value enum-const redefinition from a warning to a
**gate-able** diagnostic — a `--strict-enum-collision` build flag or a structured,
cyrlint-reportable diagnostic — so a *real* cross-module `ERR_` collision becomes
a hard failure in any build that pairs the libs. Definitive, but reactive (fires
only when both compile together). `CHK_ENUM_SHADOW` (v6.3.24) is the precedent
that an enum-const collision can legitimately be a hard error.

**Recommended combination:** (1a) as the proactive per-lib gate the ecosystem CI
runs, backed by (2) as the definitive integration-time backstop.

## Open decisions

- **Prefix scope:** only `ERR_`, or a general shared-namespace-prefix registry
  (`ERR_` today, room for future base-owned prefixes)?
- **Ownership mechanism:** pragma (1a) vs config (1b) vs universal-prefix (1c).
- **Severity + gating:** cyrlint `warn` vs `error`; does it join
  `programs/checks/lint_fmt.cyr` immediately or after a migration window?
- **Compiler elevation (2):** ship as opt-in `--strict-enum-collision`, or
  default-on at an arc?
- **Migration:** the leaves (`yukti` `YuktiErrorKind`, `ai-hwaccel`
  `DetectionError`, `sigil`/`bote`) already prefix their enum **names** but carry
  bare `ERR_*` **members** — they rename members to `<LIB>_ERR_*`. Coordinated
  window across those repos.

## Downstream effect (the point)

Once (1) lands and the leaves prefix their error-enum **members**, sakshi is the
**only** lib with bare `ERR_*` — its canonical base set — and the collision is
retired ecosystem-wide **with zero change to sakshi's own surface**. That is
exactly sakshi Option B: the fix owner moves off sakshi and onto the colliding
consumers, enforced by this gate instead of by hope.

## Cross-references

- sakshi `docs/development/issues/2026-06-23-err-timeout-enum-collision-namespace.md` (Option B; sakshi 3.0.0).
- cyrius issue `2026-06-14` (`CHKDUPVAL` conflicting-value redefinition); `CHK_ENUM_SHADOW` (`[6.3.24]`).
- cyrius proposal `2026-07-02-function-visibility-pub-private.md` (the "convention vs enforcement" parallel; api-surface snapshot).
