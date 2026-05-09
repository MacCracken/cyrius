# Raise the per-function return-statement cap from 64 → 128

**Filed:** 2026-05-08 during `vyakarana` 2.1.0 grammar-batch work
**Severity:** Low — workaround exists (refactor into helpers); cost
of the limit is shown to bite at moderate function sizes
**Affects:** Cyrius parser, `cc5` 5.10.x

## Summary

Cyrius rejects functions with more than 64 `return` statements:

```
error:<source>:131: too many return statements in function (max 64)
```

The cap is implemented as a fixed-size 512-byte array of return-
patch offsets in the parser state (`S + 0x18DA20`, 64 × 8 bytes).
Eight call sites in `src/frontend/parse.cyr`, `parse_fn.cyr`, and
`parse_expr.cyr` enforce the limit when growing the array.

vyakarana hit this in 2.1.0 when adding the `.ps1` / `.psm1` /
`.psd1` extensions to `detect_language` — a flat dispatcher
matching file extensions and returning the grammar name. The
function had ~85 `return "<name>";` statements in a natural
extension-table style, just past the cap.

This proposal asks to **raise the cap to 128** (doubling the
fixed-array size to 1 KB per function being parsed). 128 covers
the realistic cases we know about; the memory cost is negligible
on modern systems; no language-level redesign is required.

## Reproduction

```cyr
fn lookup(s) {
    if (memeq(s, "a", 1) == 1) { return "a"; }
    if (memeq(s, "b", 1) == 1) { return "b"; }
    # ... 65 more if-returns ...
    if (memeq(s, "z", 1) == 1) { return "z"; }
    return 0;
}
```

Compile:

```
$ cyrius build src/main.cyr build/foo
error:src/foo.cyr:131: too many return statements in function (max 64)
FAIL
```

The actual workaround vyakarana applied (split the function into
length-bucket helpers, see vyakarana CHANGELOG 2.1.0):

```cyr
fn _detect_short(path, n) { /* 18 returns */ }
fn _detect_4byte(path, n) { /* 26 returns */ }
fn _detect_5plus(path, n) { /* 17 returns */ }
fn _detect_basename(path, n) { /* 5 returns */ }
fn detect_language(path) {
    var n = strlen(path);
    var r = _detect_short(path, n);
    if (r != 0) { return r; }
    r = _detect_4byte(path, n);
    if (r != 0) { return r; }
    /* ... 4 returns total here ... */
}
```

The split is mechanical and doesn't hurt readability — but it's
the cost of a hard cap that no other mainstream language enforces.

## What other languages cap at

Surveyed the mainstream landscape; **none of these has a hard
language-level cap on `return` statements per function:**

| Language | Cap | Notes |
|----------|-----|-------|
| C (GCC, Clang) | none | Compiler IR is flexible; no fixed table |
| C++ (Clang, MSVC) | none | Same — IR-based |
| Java | effectively bounded by JVM constant-pool (65535) and method bytecode size (~64KB), but no return-specific limit |
| Rust | none | rustc uses MIR / LLVM IR with flexible structures |
| Go | none |
| Python | none |
| C# | none | Roslyn IR; no fixed limit |
| Swift | none |
| Cyrius (5.10.x) | **64** | The only language we found with a hard cap |

**Style-guide / static-analysis recommendations** (not language
limits): SonarQube's `S1142` defaults to "no more than 3 returns
per method" as a maintainability rule, configurable. PMD,
Checkstyle, and similar tools have analogous rules. These cap
much *lower* than Cyrius's 64 — but they're warnings, not errors,
and they're framed as "consider refactoring," not "compilation
fails." **No language imposes a hard error here.**

The takeaway: Cyrius is unusual in having any cap. The cap exists
because the parser uses a fixed-size patch-list array; the cap
itself is an implementation detail leaking into the language
surface.

## Real-world incidence (the vyakarana cases)

vyakarana is a tokenizer with 41 bundled grammars. The
`detect_language(path)` function dispatches by file extension:

- 1.x: ~50 returns (under cap)
- 1.6.0 – 1.9.0: language batches added, climbed to ~70-80
- 1.13.0: hit 80, no overage yet (some duplicates collapsed)
- **2.1.0 (this trigger):** PowerShell adds `.ps1` / `.psm1` /
  `.psd1` → 83 returns. Bumped over 64. Refactor mandated.

The refactor split into four length-bucket helpers totalling 70
returns spread across 4 functions (max 26 in a single helper).
That's well under 128 even with significant future growth.

vyakarana plans to add Vue / Svelte / Nix / Terraform / HCL in
2.1.1 – 2.1.3 (4 more extensions). Eight beyond that are queued
post-2.1.x. The dispatcher would be at ~95 returns if it had
stayed flat.

**128 buys all of vyakarana's foreseeable grammar growth** — and
matches a generous "Conway's-law-friendly" headroom. We're not
asking for unlimited; we're asking for 2× more.

## Cost analysis

The cap is a **fixed-size array** at `S + 0x18DA20` in the parser
state struct, indexed `S64(S + 0x18DA20 + rpc * 8, rp)`. Doubling
to 128 entries:

- **Memory:** +512 bytes per parser-state instance (1 KB total
  vs 512 bytes today). The parser state is allocated once per
  function being compiled, then released. Negligible on any
  modern host.
- **Code:** 8 sites flag `if (rpc >= 64) { ERR_MSG... }` —
  bump each to `>= 128`. One commit, mechanical.
- **Risk of collision:** the next field after the patch array
  starts at `0x18DA20 + 512 = 0x18DC20`. Bumping to 128 entries
  needs 1024 bytes, ending at `0x18DE20`. Anyone consulting the
  parser-state layout map (or the Cyrius compiler-internals doc)
  needs to verify nothing else lives in that range. From outside
  the compiler I can't confirm; the maintainer can.
- **Backward compatibility:** zero. Cap raises are strictly
  additive — code that compiled against 64 still compiles against
  128.

## Recommendation

### Option A: Raise to 128 (preferred)

Bump the cap. One mechanical patch. Covers all real-world cases
the cyim / vyakarana / yukti / owl projects have surfaced or are
likely to surface in the next 12 months.

### Option B: Raise to 256

Same shape, more headroom. 256 × 8 = 2 KB per parser state.
Argument: "do it once, never come back." Argument against: still
a magic number; if 128 covers everything we know, why double
again? Pick A unless someone has a real workload that hits 100+.

### Option C: Make it dynamic

Replace the fixed array with a growable buffer (e.g., the same
shape as `vec_*`). Removes the cap entirely. Cost: a `realloc`-
shaped path inside the parser, which is more invasive than a
literal-bump. Nice-to-have eventually; not necessary today.

### Option D: Keep at 64 but improve the diagnostic

If the project values the cap as a "you should refactor" signal,
keep 64 but make the error message say so:

```
error:<source>:131: function has 65 returns; max 64
  hint: long extension dispatchers split well into length-
  bucket helpers — see vyakarana 2.1.0 detect_language
  refactor as a worked example
```

Not preferred from outside the compiler — the cap shouldn't
exist as a hard limit when no other mainstream language has
one — but it's a viable middle ground.

## Severity rationale

LOW — the workaround (split into helpers) is mechanical and the
result is arguably more readable. But the cap surfaces at
moderate function sizes (vyakarana hit it at ~85 returns, only
moderately above the cap), it's the only language we've found
with a hard cap here, and the fix is a one-character change to
8 sites. Cost-benefit strongly favours raising it.

## What we're doing in vyakarana

vyakarana 2.1.0 shipped the helper-split workaround because the
cut needed to land for the user. The split is documented in the
2.1.0 CHANGELOG under `### Changed`:

> `detect_language` refactored into length-bucket helpers.
> Cyrius caps return statements per function at 64; the growing
> extension list pushed past that. Split into `_detect_short` /
> `_detect_4byte` / `_detect_5plus` / `_detect_basename`
> helpers, each well under the cap.

If this proposal lands and the cap goes to 128 (or higher),
vyakarana can collapse the helpers back into a single function
in a future cut for marginal readability — but that's a
stylistic choice, not a correctness one.
