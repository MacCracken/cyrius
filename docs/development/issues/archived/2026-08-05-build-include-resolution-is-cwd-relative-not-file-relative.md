# `cyrius build` resolves every `include` against the process CWD, so a source file in a subfolder cannot include its own sibling

**Status:** ✅ **SHIPPED v6.5.7** — implemented as designed below, with one correction to the
CVE analysis (see the ⛔ banner in *CVE posture*, which was wrong in the filing and is the
single most important thing on this page). Gate: `tests/include_dir_resolution.sh`, 12 axes,
three mutation-proven.
**Placement:** v6.5.7 (W1). Compiler change → seed-derive gated; cybs compiles the new scanner
and `gen2 == build/cycc` verified green.
**Discovered:** 2026-08-05. Maintainer ruling: a subfolder callout was **always** intended to work.
**Severity:** Medium — no data loss, but it forces the flagship consumer (agnos) into a shell workaround that costs it dependency resolution.
**Affects:** cycc 6.5.6 and every earlier release. Long-standing, at least several minors.

## Summary

`include "P"` is opened as the literal path `P`, relative to the **process working
directory** — never relative to the file doing the including. `READFILE(fname, …)` at
`src/frontend/lex_pp.cyr:2158` (PP_PASS) and `:2536` (PP_IFDEF_PASS) takes the include
text verbatim. There is no search path and no notion of "the including file's directory".

**This is NOT a limit on subfolders.** Nested source trees work fine as long as every
include is written relative to the project root — this repo is the proof at scale: **2,503
include directives across 414 files** spanning `src/frontend/`, `src/backend/x86/`, `lib/`,
all resolving. A three-way nested probe (`src/core/math/`, `src/net/http/`, `src/util/`)
builds and runs correctly.

The defect is narrower and entirely about **path style**: a file cannot include a sibling
by its bare name.

```
src/deep/main.cyr   contains   include "helper.cyr"
src/deep/helper.cyr exists
$ cyrius build src/deep/main.cyr build/deep
error: cannot open include file: helper.cyr        # FAIL
```

`include "src/deep/helper.cyr"` works. Only the file-relative spelling fails.

## The consumer cost — agnos pays it in shell

`agnos/cyrius.cyml:16` declares `entry = "kernel/agnos.cyr"`, and `kernel/agnos.cyr`
carries ~90 includes written relative to **its own directory**:

```
kernel/agnos.cyr:8   include "arch/x86_64/boot_data.cyr"   → kernel/arch/x86_64/boot_data.cyr
```

Building from the repo root fails on every one of them. So `agnos/scripts/build.sh:570`:

```sh
(cd "$ROOT/kernel" && "$CYRB" build --no-deps "$PREPPED" "$ROOT/build/agnos")
```

with the reason recorded at `scripts/build.sh:562-563` — *"`cyrius build` looks for
cyrius.cyml at cwd and we cd into kernel/ for relative include"*.

**That `cd` is the whole cost.** Moving CWD into `kernel/` makes the includes resolve, but
`cyrius build` then looks for `cyrius.cyml` there, doesn't find it, and dependency
resolution is lost — hence `--no-deps` plus a hand-rolled kashi font-data prepend. You
cannot have `[build] entry` pointing into a subfolder **and** file-relative includes.

## Root cause — and why the obvious fixes do not work

**cycc never learns the source path.** `cbt/build.cyr:516` does:

```cyr
var sfd = sys_open(actual_source, O_RDONLY, 0);
sys_dup2(sfd, 0);            # ← the compiler reads the source from STDIN
```

so the compiler structurally cannot derive the entry directory on its own. That kills the
two obvious channels:

| channel | why it fails |
|---|---|
| **`chdir` into the source dir in `cbt`** (mechanising agnos's workaround) | `_materialize_source` (`cbt/build.cyr:298`) **emits `include "lib/…"` LINES** for dep prepends — only `[build] modules` and the entry source are stream-inlined. Those emitted includes are root-relative, so moving CWD breaks the stdlib prepend instead. |
| **An env var (`CYRIUS_SOURCE_DIR`) read via `_read_env`** | `_read_env` has **no Windows branch** — `src/backend/common/runtime.cyr` falls through to `return 0` (its own header still says the Win lookup is queued), and `src/backend/cx/emit.cyr:1380` is a hard `return 0` stub whose fork does not even include `runtime.cyr`. The channel is inert on **cass (PE)** and **cx**, both first-class gates. |

## Proposed fix — an in-band marker, CWD-first

Use the channel that already crosses this exact boundary: the preprocessor's `#@file`
marker stream, which `cbt` writes into the materialized temp and which **cybs already
parses**.

1. `_materialize_source` emits the entry file's directory once, at the top of the temp
   (e.g. `#@incdir "kernel"`). Derived in `cbt`, which knows the real path.
2. `lex_pp` records it in a file-scope buffer beside the existing `_pp_curfile[512]`
   (`src/frontend/lex_pp.cyr:305`).
3. At both `READFILE` include sites, **try the bare path first, exactly as today**; only
   if that fails, retry as `<incdir>/<name>`.

**Resolution order is CWD-first, deliberately.** It is strictly additive: every include
that resolves today resolves identically, so none of the 2,503 in this tree — nor any
consumer's — can change meaning. The fallback can only convert a hard error into a
success. Sibling-first was considered and rejected: it changes which file wins when a name
exists in both places.

For the IFDEF pass, `_pp_curfile` (already maintained there, `:322`) gives the true
including file, so that site can use the *including file's* directory. In `PP_PASS` the
enclosing file is always the main source, so the entry `incdir` is exactly right.

⚠ **Deviation, shipped deliberately:** one global `incdir` (the top-level source's directory)
rather than a per-including-file one. Putting the retry inside `READFILE` covers both PP sites
and the `#ref` reader from a single place, which is what makes the CWD-first ordering provable
rather than a property to re-check per call site. True per-file resolution — where a file two
levels down includes relative to *itself* — is a strictly larger change and is not what the
filing asked for. The filed repro and the agnos case are both entry-relative.

## CVE posture — unchanged by construction

**No guard is bypassed, weakened, or duplicated.** The fallback path is fed to the same
`READFILE`, so both existing guards apply to it verbatim:

- **CVE-02** (`src/frontend/lex.cyr:642-660`) — rejects any path with a `..` component
  unless `CYRIUS_ALLOW_PARENT_INCLUDES=1`, and returns `-1` so the PP's `nr < 0` guard
  fails the build rather than treating it as an empty include.
- **CVE-16** (`src/frontend/lex.cyr:663+`) — rejects absolute include paths unless
  `CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1`.

Consequences, stated explicitly so nothing is assumed:

- **A `..` include behaves exactly as it does today.** Joining `incdir` to a name
  containing `..` yields a path that still contains `..`, so CVE-02 still rejects it.
  Consumers relying on `..` includes (`~/Repos/chakshu/ai/main.cyr:16-21` has six
  `../src/*.cyr`; `~/Repos/agnos/tests/gpu/moderaster.cyr:35-36` has `../../kernel/…`)
  keep needing `CYRIUS_ALLOW_PARENT_INCLUDES=1` — **no regression, and no new permission.**
- **Do NOT implement the retry as a bare `open`/`close` probe** *outside* the guards. The
  shipped retry lives INSIDE `READFILE`, after every existing resolution step, so the
  include name has already cleared CVE-02 and CVE-16 before the prefix is joined to it.
  (Re-entering `READFILE` recursively was considered and rejected: it would re-run guards
  both halves have already passed, and recurse.)

### ⛔ The filing was WRONG about the trust model — this is the correction

> ~~`incdir` is derived by `cbt` from a path the user passed on the command line, not from
> file content, so it is not itself an untrusted-input channel.~~

**It is exactly an untrusted-input channel, and reasoning otherwise would have reopened
CVE-16 through the front door.** The marker is *in-band* — that is the whole reason it was
chosen over env/chdir — so the thing that writes it is whatever text arrives on stdin, and a
hostile `.cyr` can write its own. `#@incdir /home/u/.ssh` + `include "id_rsa"` reconstructs
precisely the read-anything primitive CVE-16 was filed to remove. The claim above confused
"the CLI is the *intended* writer" with "the CLI is the *only possible* writer".

Two rules restore the property the filing assumed it already had:

1. **Relative and `..`-free, or refused.** Composed with an include name that has itself
   passed CVE-02/CVE-16, a relative `..`-free prefix yields a path confined to the CWD
   subtree — provably not one file more than a plain relative include could already reach.
2. **Byte 0 only.** `cyrius build` writes the marker as the first bytes of the materialised
   temp, ahead of the dep prepend, so the CLI's value is the one cycc reads; a marker
   further down — the shape a hostile include would use — stays an ordinary comment.

**Cost of rule 1, stated plainly:** `cyrius build /abs/dir/x.cyr` gets no marker, so its
includes still resolve against CWD exactly as they do today. Relativising an absolute source
against CWD would need a `getcwd` wrapper that does not exist on the PE/Mach-O targets
`cbt/cyrius.cyr` cross-compiles to. That is a real limit, and it is the right trade: no reach
was bought with a hole.

Both guards are mutation-proven. Deleting the absolute check, or the mid-path `..` check,
each turns `tests/include_dir_resolution.sh` red with the escape file's sentinel value.

⚠ **The escape axes cost this gate a round, and the lesson generalises.** They first pointed
at `/etc/hostname`, and *passed against a compiler with the guard removed* — a hostname is
not parseable cyrius, so the escape succeeded, the file was read, and the compile then failed
for an unrelated reason that looked identical to a refusal. A security test whose failure mode
aliases its success mode proves nothing. The target must be valid cyrius, so a breach is
visible as a distinct exit code rather than as the same red as a block.

## What shipped

| | |
|---|---|
| `src/common/util.cyr` | `_pp_incdir[512]` / `_pp_incdir_len` — declared here (the `_had_error` precedent) so every fork sees them. Bounded at 480: a top-level `var x[N]` is N*8 bytes under cycc but N **bytes** under cybs, and this file is on the seed path. |
| `src/frontend/lex_pp.cyr` | `PP_SCAN_INCDIR(S)`, called first in `PREPROCESS` — one site, all seven forks. Reads the marker at byte 0 and applies the guard; rejects are silent, so a bad value costs exactly what no value costs. |
| `src/frontend/lex.cyr` | the retry inside `READFILE`, placed **after** every existing resolution step. |
| `cbt/build.cyr` | `_source_incdir(source)` + the marker write, ahead of the dep prepend. A directory component now forces `need_tmp = 1` on its own. |

`#` opens a comment in cyrius, so the marker needed no tolerance work anywhere: older cycc,
cybs, and the cx/JS forks all skip the line untaught.

## Acceptance — all met at v6.5.7

- ✅ `src/sub/app.cyr` with `include "helper.cyr"` **and** `include "deeper/more.cyr"` builds
  from the project root and runs (gate axis 1). Verified end-to-end through `cyrius build`,
  not just through cycc.
- ⏳ agnos builds from its **repo root** with `entry = "kernel/agnos.cyr"`, no `cd`, and
  **without** `--no-deps` — the workaround at `scripts/build.sh:570` is deletable. Deletable
  as of this release; the deletion itself is agnos-side and is theirs to make.
- ✅ All in-tree includes unchanged — `check.sh` **156 / 0**. `seed → cybs → cycc` green,
  `gen2 == build/cycc`, and the cycc fixpoint holds at 1,141,696 B.
- ✅ A `..` include still errors identically without `CYRIUS_ALLOW_PARENT_INCLUDES=1`, **and
  still errors with a valid marker set** (gate axis 7 — the marker must not become a way to
  smuggle a hostile name past a guard that already exists).
- ✅ CWD-first proven, not asserted: with the same basename present in both places, the CWD
  copy wins (axis 3), and making the fallback unconditional turns that axis red.

## Adjacent, same command, smaller

`cyrius build src/x.cyr build/nested/deeper/out` prints a bare `FAIL` with **no `error:`
line** and emits nothing when the output directory does not exist. It should either
`mkdir -p` the parent or say which directory is missing. Independent of the include work.

## Not a defect (verified, recorded so it is not "fixed" by mistake)

Multiple and deeply nested subfolders are fully supported today when includes are written
root-relative. The fix adds a second accepted spelling; it does not add subfolder support,
which already exists.
