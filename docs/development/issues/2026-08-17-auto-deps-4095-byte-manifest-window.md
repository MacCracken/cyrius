# `_auto_deps` reads only the first 4095 bytes of `cyrius.cyml`, so a `[deps]` past that is invisible

**Status:** 🟡 **OPEN** — filed from kavach 3.11.14, where it cost a bisect; worked around by moving commentary below the `[deps]` array and adding a repo-side CI gate. Verified against live code 2026-08-17: `cbt/deps.cyr:1983-1984` still allocates 4096 and reads 4095, and the repro below still reproduces on 6.5.27.
**Placement:** unpinned — 6.x-line backlog. Resolver/toolchain item — never 7.x.
**Discovered:** 2026-08-17 while documenting a *different* dep bug in kavach's `cyrius.cyml`. The comment explaining that bug pushed `[deps]` from byte 3676 to 5288 and broke the build.
**Severity:** Medium — hard build failure with a workaround, but the diagnostic is actively misleading and the trigger is *writing a comment*. See the amplifier note below.
**Affects:** cycc **6.0.43 through 6.5.27** — every version tested. Not a regression; a long-standing latent limit.

## Summary

`cyrius build` does not call the dep resolver directly. It goes through `_auto_deps`
(`cbt/deps.cyr:1979`), which reads the manifest into a **4096-byte** buffer and scans **only that
prefix** for `[deps]` / `[deps.`:

```cyrius
var buf = alloc(4096);
var n = file_read_all(_ad_manifest, buf, 4095);
```

If the marker starts past byte 4095 it is never seen, `_auto_deps` returns 0, `cmd_deps()` never
runs, and **nothing is prepended into the compilation unit**. The build then fails on undefined
stdlib symbols in the consumer's *own* source files.

⛔ **Three things make this expensive out of proportion to the bug:**

1. **No diagnostic mentions the manifest.** Not the file, not `[deps]`, not a byte count. The
   output is `undefined variable 'IoNotFound'` at `src/util.cyr:305` — kilobytes away from the
   cause, in a file the author did not touch.
2. **A populated `lib/` does not save you.** `cmd_deps` reads **32767** bytes
   (`cbt/deps.cyr:1808`), so an explicit `cyrius deps` sees the section fine and vendors every
   module. They sit on disk, correct and complete, while the build behaves as if none were
   declared. Running `cyrius deps` — the obvious thing to try — changes nothing and reinforces the
   wrong hypothesis.
3. **The trigger is writing a comment.** The natural place to document a dependency list is
   directly above it. On this manifest that is *the* edit that breaks the build.

⚠ **The two readers of the same file disagree by 8×** (4095 vs 32767). Either bound is defensible;
having both, silently, is what produces a manifest that `cyrius deps` accepts and `cyrius build`
ignores.

## Reproduction

`docs/development/issues/repros/2026-08-17-auto-deps-4095-byte-manifest-window.sh`
(self-contained; builds its own fixture in a temp dir, takes the cycc version as `$1`).

Two builds, **identical manifest content** — the only difference is the length of a comment above
`[deps]`, which moves the marker across byte 4095:

```
$ ./2026-08-17-auto-deps-4095-byte-manifest-window.sh 6.5.27
=== cycc 6.5.27 ===
CASE A — [deps] at ~4000 bytes (inside the window)
    '[deps]' starts at byte : 4000
    lib/ populated by build : 14 module(s)
    any mention of the manifest in output: 0
    binary emitted          : YES

CASE B — [deps] at ~4200 bytes (past the window)
    '[deps]' starts at byte : 4200
    lib/ populated by build : 0 module(s)
    any mention of the manifest in output: 0
    binary emitted          : NO
```

The program under test only needs `vec`:

```cyrius
fn main(): i64 {
    var v = vec_new();
    vec_push(v, 1);
    return vec_len(v) - 1;
}
var r = main();
syscall(60, 0);
```

The boundary is exact. Padding kavach's real manifest so `stdlib = [` lands at a chosen offset:

| `stdlib = [` at byte | build errors |
|---|---|
| 3900 | 0 |
| 4050 | 0 |
| 4090 | 0 |
| **4095** | **0** |
| **4100** | **7** |
| 4200 | 7 |

### Version range

Same CASE B fixture, one version per minor — **every** one fails:

| cycc | 6.0.43 | 6.2.11 | 6.3.40 | 6.4.62 | 6.5.21 | 6.5.27 |
|---|---|---|---|---|---|---|
| CASE B binary | NO | NO | NO | NO | NO | NO |

So this is not a regression and nothing recent exposed it — it has simply never been hit, because
manifests rarely carry 4 KB of preamble. kavach's did once it started documenting a resolver
gotcha (see
[`2026-08-17-stdlib-transitive-pull-drops-top-level-include.md`](./2026-08-17-stdlib-transitive-pull-drops-top-level-include.md),
filed the same day — that filing is *why* the comment existed).

## Root cause

`cbt/deps.cyr:1983-1984`, in `_auto_deps`:

```cyrius
var buf = alloc(4096);
var n = file_read_all(_ad_manifest, buf, 4095);
if (n <= 0) { return 0; }
store8(buf + n, 0);
# Check if [deps] section exists
var has_deps = 0;
...
if (has_deps == 0) { return 0; }        # <-- silent
var dr = cmd_deps();
```

`cmd_deps()` itself (`cbt/deps.cyr:1808`) uses `alloc(32768)` / `file_read_all(..., 32767)`, so the
two paths that read this one file use different bounds.

⚠ The same 4095-byte buffer also backs the `[build] modules` scan a few lines below, so that key
has the identical cliff.

## Proposed fix

**Preferred — read the same amount `cmd_deps` does.** Make `_auto_deps` use `alloc(32768)` /
`file_read_all(..., 32767)`. It is a two-line change, it makes the two readers agree, and 32 KB is
already the number the project treats as "a manifest". No new failure mode: a manifest larger than
32 KB was already truncated for `cmd_deps`.

**Better still — size the buffer from the file.** `_file_size` is already available in this module
and is what removes the cliff rather than moving it.

**Independently, and worth doing even if the bound stays: make the miss loud.** The failure is
cheap to diagnose *if named* and near-impossible if not. When the manifest was read but no `[deps]`
marker was found in the scanned prefix, and the file is longer than the prefix, say so:

```
note: cyrius.cyml is 9869 bytes but only the first 4095 were scanned for [deps];
      no [deps] section found in that range — no dependencies were prepended
```

⭐ That single line would have turned this filing into a ten-second fix. It is the same lesson as
`.24`/`.25`'s work on `_dep_pull_leaves`' message: **a silent early-return in a resolver surfaces
as a nonsense error somewhere else entirely.**

⚠ A truncated read that silently means "no dependencies" is the shape worth removing regardless of
the byte count, because the wrong answer is indistinguishable from the correct one for a project
that genuinely has no `[deps]`.

## Consumer-side workaround (if any)

Shipped in **kavach 3.11.14**, two parts.

**1. Keep the marker inside the window.** Long commentary moved *below* the `[deps]` array, with
only a short pointer above it:

```toml
#
# ⛔ 2 SILENT HAZARDS — read "MANIFEST HAZARDS" below the array before
#    editing ANY comment above it. (1) `[deps]` must start inside the
#    first 4095 bytes. (2) Declaring a module here != it gets included.
[deps]
stdlib = [ ... ]

# ── MANIFEST HAZARDS (read before editing anything above) ────────
# ...full explanation lives here, where its length is free...
```

**2. Gate it in CI**, because a comment edit is an easy way to walk back into it and the symptom
does not point here. `.github/workflows/ci.yml` fails the build when the marker crosses 4095 and
warns under 300 bytes of headroom:

```sh
off=$(python3 -c "
b=open('cyrius.cyml','rb').read()
c=[x for x in (b.find(b'[deps]'), b.find(b'[deps.')) if x>=0]
print(min(c) if c else -1)")
[ "$off" -ge 4095 ] && { echo "FAIL: [deps] at byte $off, past the 4095-byte window"; exit 1; }
```

⚠ **Note for other consumers:** the exposure is any manifest with a large preamble above `[deps]` —
a long `[lib] modules` list with per-module comments, an ASCII-art header, or a documented `[deps]`
rationale will all do it. kavach was at **3676 / 4095** before this release with no idea the
ceiling existed. The symptom to recognise is *undefined stdlib symbols in your own `src/` while
`cyrius deps` reports success and `lib/` is fully populated*; check the byte offset of `[deps]`
first, before anything else.
