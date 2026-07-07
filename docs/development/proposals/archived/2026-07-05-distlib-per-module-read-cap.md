# Raise the `cyrius distlib` per-module read cap 256 KB → 1024 KB

- **Filed**: 2026-07-05 (surfaced by a shabdakosh consumer premise-check during its
  v3.0.0 Rust→CYRIUS port, at the distlib/release-prep step)
- **Status**: ✅ **IMPLEMENTED in v6.4.10** (2026-07-05). Both call sites in `cbt/commands.cyr`
  (flat + `--modular`) bumped 256KB → 1MB (`alloc(1048576)` / `1048575` read / `1048575` guard /
  "1024KB read cap" message), matching cycc's `input_buf[1048576]`. Verified: the rebuilt `cyrius`
  CLI bundles a 405KB module the old CLI rejected. cbt-only change → cycc self-host unaffected. The
  dynamic `_file_size`-based buffer remains the eventual fix if a module nears 1MB.
- **Priority**: not a release-blocker (consumers can shard their large modules today),
  but it removes a real, recurring workaround tax on generated-data crates.

## The finding (one line)

`cyrius distlib` reads each bundled module into a **fixed 256 KB buffer** and fails loud
above it — but **cycc itself compiles single source modules up to 1 MB** (`input_buf
[1048576]`), so a module the compiler happily accepts cannot be put into a distlib bundle.

## Evidence (verified 2026-07-05)

- **The cap is a hardcoded 256 KB (`262144`) read buffer in two places** in
  `cbt/commands.cyr`:
  - **flat path** (~L1864): `var fbuf = alloc(262144); var flen = file_read_all(mod_path,
    fbuf, 262143);` then a fail-loud guard (v6.2.51) `if (flen >= 262143 &&
    _file_size(mod_path) > 262143) { _err_ctx("distlib: module exceeds 256KB read cap
    (truncated)", mod_path); ... return 1; }`.
  - **`--modular` path** (~L1559): the same `alloc(262144)` / `262143` read + guard,
    message `"distlib --modular: module exceeds 256KB read cap (truncated)"`.
- **The compiler's own per-source limit is already 1 MB**: `input_buf [1048576]` — "1MB raw
  stdin input (v3.6.7, was 256KB)" (`src/main_win.cyr:16`), and the cx/native forks error
  with `"input exceeds 1MB buffer"` (`src/main_cx.cyr:99`, `src/main_aarch64_native.cyr:234`).
  So **cycc compiles a 900 KB module fine, but `distlib` refuses to bundle it.** The bundler
  is the tighter, inconsistent limit.
- **The code already anticipated this revisit.** The flat-path comment (v5.7.36, which raised
  the cap 64 KB → 256 KB after the **mabda** crate hit the 64 KB wall) says verbatim: *"256KB
  is the next breathing room without committing to a dynamic vec — **revisit if a module ever
  crosses 192KB**."* A module has now crossed it (below), so this is that revisit.

## What surfaced it (the concrete consumer)

shabdakosh (pronunciation dictionary) ships its base CMUdict as a **generated `.cyr` data
module** (the CYRIUS replacement for a Rust `build.rs` — same pattern as varna / cyrius-unicode).
That generated file is **283 KB**. `cyrius distlib` failed:

```
error: distlib: module exceeds 256KB read cap (truncated): src/dictionary/_cmudict_data.cyr
```

The only fix available to the consumer was to **shard the generated data** into
`_cmudict_data_0.cyr` (172 KB) + `_cmudict_data_1.cyr` (110 KB), and then thread that split
through the generator, **16 includers** (`src/main.cyr` + every `tests/*.tcyr`), and
`[lib].modules`. That works, and CYRIUS's flat link resolves the cross-shard piece globals —
but it is pure boilerplate tax imposed by a bundler read buffer, and it recurs for every
generated-data crate whose table crosses 256 KB (dictionaries, unicode tables, embedded
assets — exactly the crates that use the generated-`.cyr` idiom the ecosystem encourages).

## The change (minimal)

Raise the per-module read cap to **1 MB (`1048576`)**, matching cycc's `input_buf`. In
`cbt/commands.cyr`, at **both** call sites (flat ~L1864 and `--modular` ~L1559):

- `alloc(262144)` → `alloc(1048576)`
- `file_read_all(mod_path, fbuf, 262143)` → `file_read_all(mod_path, fbuf, 1048575)`
- guard `flen >= 262143 && _file_size(mod_path) > 262143` → `... >= 1048575 && ... > 1048575`
- error text `"... exceeds 256KB read cap ..."` → `"... exceeds 1024KB read cap ..."`
- refresh the v5.7.36 rationale comment (note the new 1 MB ceiling + the cycc `input_buf`
  alignment; drop the stale "revisit if a module crosses 192KB").

**Cost/risk:** the two buffers are one-shot `alloc`s in the `cbt` build tool (only one runs
per invocation); +768 KB of bump-allocated scratch in a short-lived CLI process. Zero effect
on compiled-program size or runtime. The fail-loud guard is preserved (now at 1 MB), so a
genuinely oversized module still errors rather than silently truncating. Low risk, localized.

## Alternative considered (and why not now)

**Size the buffer dynamically** from `_file_size(mod_path)` (`alloc(size + 1)` + a single
`file_read_all`), removing any fixed ceiling. This is the "proper" fix and the code comment
gestures at it ("without committing to a dynamic vec"). It's a larger change (both paths,
plus deciding a sane upper sanity-bound to avoid a pathological alloc), and the authors
already deferred it once. A 1 MB constant bump is the low-effort, low-risk step that unblocks
today's real consumer and re-aligns distlib with the compiler's own 1 MB per-source limit;
the dynamic approach can follow if/when a module approaches 1 MB.

## Open questions

- Is **1 MB the right number**, or should distlib go straight to a dynamic (`_file_size`-based)
  buffer to retire the ceiling permanently? (This proposal recommends 1 MB now for parity with
  `input_buf`; dynamic later.)
- Should the **generated-`.cyr` idiom** grow a first-class "sharded data module" helper so
  crates don't hand-roll the split — or does raising this cap make that unnecessary for the
  foreseeable table sizes? (Raising to 1 MB covers shabdakosh's 283 KB with 3.6× headroom.)

**Bottom line:** a one-constant, two-site bump (256 KB → 1 MB) that makes `distlib` stop
rejecting modules `cycc` already compiles, and removes the sharding workaround tax on
generated-data crates. This is the "revisit" the v5.7.36 comment scheduled.
