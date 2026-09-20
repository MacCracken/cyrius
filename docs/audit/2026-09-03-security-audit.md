# Security audit — 2026-09-03 (cycc 6.5.45)

**Scope:** the untrusted-source-input surface. Previous full audit:
`docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36) at cycc 6.4.82.
**Next free identifier after this document: CVE-45.** (CVE-41 is fixed at 6.5.47; see its entry.) (CVE-37 and CVE-38 in the previous
document are **withdrawn** but still consume their ids.) CVE-43 was consumed at 6.6.5 and
**CVE-44 at 6.6.6**; both are appended below.
⚠ **This line read "next free: CVE-42" while CLAUDE.md read "the next CVE number is 43" and this document ran 39-41.**
Two authorities, two answers, and nothing reconciled them. CLAUDE.md is the one every closeout reads, so **42 is
retired unused** and CVE-43 is the entry appended below. Anything below 44 now collides.

Run as part of the band K closeout, as nine parallel audit dimensions over the v6.5.x minor with
an adversarial verification pass over the highest-severity findings. Everything recorded here was
reproduced against a compiler built for the purpose; where a claim is inherited rather than
re-measured, it says so.

---

## CVE-39 — an include path's LENGTH silently changes which `#ifdef` branch compiles

| | |
|---|---|
| **Severity** | **High** — silent wrong-code generation, exit 0, no diagnostic |
| **Affected** | `src/frontend/lex_pp.cyr` (3 capture loops), through cycc 6.5.44 |
| **Fixed** | 6.5.45 |

**Vector.** The three include/`#ref` filename capture loops wrote into the scratch region at
`S+0x190400`, bounded at 4095 because the heap map declared that region `[4096]`. Two live
things sit inside that declared span:

| offset | bytes in | what |
|---|---|---|
| `S+0x190700` | 768 | `PP_EXPAND`'s output-write-cursor return slot (`lex_pp.cyr:2334` store / `:3166` load) |
| `S+0x190800` | 1024 | the `#ifdef` **feature-flag table** — name hashes, 16 slots (`:2368`, `:2379`) |

**Impact.** A path of ≥768 characters corrupts the preprocessor's own output cursor, so expanded
macro text lands at the wrong offset. At ≥1024 it overwrites the hashes of `CYRIUS_ARCH_X86`,
`CYRIUS_TARGET_MACOS` and their siblings — after which `#ifdef` selects the **wrong branches**
and the compiler emits a binary shaped for a different target.

**Measured**, against a compiler built with the pre-fix guards:

```
include path 1210 chars → probe returns 7, where 42 is correct.  compile rc=0, no diagnostic.
                          post-fix: "error: include/#ref filename exceeds 767 bytes", rc=1.
```

⚠ **A long path is not exotic.** Deep vendored dependency trees under a long `$HOME` reach four
figures, and the input is attacker-influenced wherever source is compiled on someone's behalf.

**Fix.** All three loops bounded at 767; the map corrected to `[768]` and both live neighbours
declared. ⚠ **The first cut of this fix used 1024** — reasoning from the flag table alone and
missing the cursor slot 256 bytes below it. That is why
`tests/gates/frontend/preprocessor_scratch_bounds.sh` **derives** the bound from live writes
rather than trusting the map or any comment.

---

## CVE-40 — an unbounded `#define` body copy walks out of the macro text pool

| | |
|---|---|
| **Severity** | **High** — silent memory corruption of live compiler state from ordinary source |
| **Affected** | `src/frontend/lex_pp.cyr:2704-2721`, through cycc 6.5.44 |
| **Fixed** | 6.5.45 |

**Vector.** The macro body copy ran to end-of-line with no check on the copied length **or** on
the accumulating write position `_pp_macro_text_pos`, writing into the pool at `S+0x193000`. Free
headroom there runs to `S+0x197000` — 16 KB shared across all 16 macros — so a single long body,
or enough ordinary ones in sequence, walks into live compiler state. The audit dimension that
found it measured a SIGSEGV from a 20500-character function-like macro body (that specific crash
is inherited from the audit, not re-measured here).

**Fix.** Bounded at 16384 with an honest hard error (`PP_MACRO_TEXT_FULL`). ⚠ The guard tests the
**accumulating position**, not this macro's length — bounding the length alone still overruns on
the sixteenth `#define`. Verified: a 20500-character body is refused with a diagnostic, and an
ordinary `#define` is unaffected.

---

## Not fixed here, and why

- **CVE-41** — unbounded name captures in the `#derive` path. **Deferred from this release and
  FIXED at 6.5.47.**

  ⛔ **The stated reason for deferring it was WRONG, and the correction belongs here rather than
  quietly in the next changelog.** This document said CVE-41 "needs a heap/brk layout change
  (relocating the `#derive` name scratch out from under `S+0x197020`), which makes it a
  two-step-bootstrap change". Premise-checked at 6.5.47 against live code: nothing is written
  between `S+0x197020` and the next live address `S+0x197400`, so **no relocation was needed at
  all**. The fix is two bounds checks in place.

  ⛔ **And the count was wrong.** It said *three* unbounded captures. There are **two** — the
  struct name and the field name. The third, the type-name loop, has been **bounded at 31 all
  along**, and is the template the other two should have followed. Three name captures sit in one
  construct; one was written with a guard and two without, and nothing compared them. That
  asymmetry inside a single function is the actual finding.

  ⚠ **The real ceiling is 31, not the 64 the scratch declares**, because both names are copied at
  a **32-byte stride** (`_pp_derive_names + dsi * 32`, `S+0x1FC000 + fc * 32`) — the smaller of
  the two limits governs, and reading only the scratch declaration is how 64 looked safe.

  ⚠ **The overflow is SILENT**, not a crash: 71 bytes into a 32-byte stride renames the
  *neighbouring* field. That is why this needed a static finding — a pre-fix compiler runs the
  probe to completion and exits 0.

The remaining band K audit findings are correctness rather than security and are pinned to the
band's second phase; see `docs/development/roadmap.md`.

---

## Still holding from the previous audit

`CVE-32`/`33`/`34` fixes intact. The `cbt/` temp-file hardening (`CVE-35`/`36`) still holds —
`_cbt_tmpdir()` / `_cbt_tmpfile()` remain the only `/tmp` path producers.

---

## CVE-43 — the dep-cache tamper check trusted the cache's own index, and failed OPEN around it

*Appended 2026-09-18 (cyrius 6.6.5), from the mabda 4.1.3 filing. Not part of the 2026-09-03
sweep: recorded here because this is the live ledger and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **High** — a modified dependency is vendored into the consumer's `lib/` at exit 0, with no diagnostic |
| **Affected** | `cbt/deps.cyr` (`_git_worktree_clean`, and the `if (_head != 0)` call site), CVE-21's check since v6.2.30, through cyrius 6.6.4 |
| **Fixed** | 6.6.5 |

**Vector.** The check was `git -C <cache> diff-index --quiet HEAD`. That command answers from
the SHARED cache's own `.git/index` and config — cached stat data, the `assume-unchanged` and
`skip-worktree` bits, `core.fileMode` / `core.trustctime` / `core.checkStat` / `core.fsmonitor`,
and `refs/replace` — every one of which is writable by anything that can write the cache. Measured
end-to-end against 6.6.4, each of these resolved at exit 0 and vendored the tampered bytes:

1. an in-place edit with the mtime restored (no config change needed once the index has been
   rewritten a second later, which any porcelain command in a warm cache does);
2. `git update-index --assume-unchanged` plus an edit;
3. `git update-index --skip-worktree` plus an edit (sparse checkout sets this bit);
4. a local commit with no `cyrius.lock` — first resolve is TOFU and HEAD was never compared with
   `refs/tags/<tag>`, so the local commit was pinned as the tag's;
5. a cache with `.git` removed — `if (_head != 0)` had no `else`, so all three CVE-21 checks were
   skipped and the commit pin was dropped (1 → 0);
6. `git replace` over HEAD's commit (no `--no-replace-objects`);
7. a `core.fsmonitor` hook reporting no changes — and git **executes** that program, so the
   untrusted cache also chose a binary for the resolver to run (measured: 2 executions per check).

Untracked files are invisible to `diff-index`, so a module planted at a declared-but-absent
`modules` path, or at the `lib/<basename>` fallback, was vendored as `lib/<dep>_<base>.cyr`.
Files planted inside a gitlink directory are invisible to `diff-index`, `status` **and**
`ls-files -o` alike.

Two amplifiers. With `CYRIUS_HOME` inside a git repository (a CI workspace, a dotfiles `$HOME`),
a `.git`-less cache made `git -C` discovery climb into the **enclosing** repo, so the check
passed and `cyrius.lock` pinned that repo's HEAD as the dependency's commit. And because
`_envp` forwarded the repository-location variables, a `cyrius deps` run from a git **hook**
(git exports an absolute `GIT_INDEX_FILE`, plus `GIT_DIR` in a linked worktree) made the
cold-cache `git clone` rewrite the user's in-progress commit index — their `git commit` failed
with `invalid object … Error building trees` and the cache was left indexless.

**Impact.** Anything that can write `~/.cyrius/deps/<name>/<tag>` — another process on the box,
a restored backup, a shared build agent, a hook — can change what a dependency compiles into
every consumer that resolves it, without moving HEAD and without a diagnostic. The check existed
precisely to stop that (CVE-21, "catches an in-place edit of a cached checkout").

**Fix.** The verification runs in a per-process throwaway index built from HEAD (so no stat
cache and no index bits participate, and nothing inside the shared cache is written): `.git` must
be a real directory, `HEAD == refs/tags/<tag>^{commit}`, a FULL `git fsck`, then `read-tree HEAD`
+ `update-index --refresh` + `diff-files` + `ls-files -o` (no `--exclude-standard`) + a
populated-gitlink check. Every git call strips the 13 location variables, passes
`--no-replace-objects`, SETS `GIT_WORK_TREE`, overrides the cache's config
(`core.fsmonitor=false`, `core.hooksPath=/dev/null`, `core.symlinks=true`,
`core.untrackedCache=false`, `core.attributesFile=/dev/null`, and `core.fileMode` at the value a
filesystem probe establishes) and is fenced by `GIT_CEILING_DIRECTORIES` rather than an explicit
`--git-dir`, which would skip git's own `safe.directory` ownership check. An unreadable cache
refuses instead of skipping; untagged deps are verified too; the clone's exit status is checked.

**The config knobs `-c` CANNOT override are refused, not overridden.** Review of the first cut
found eight more shapes that it still accepted at exit 0 with the tampered bytes vendored, all of
them inside `.git` where `ls-files -o` cannot look: `core.worktree` pointing every content
command at a pristine copy; a `filter.<name>.clean` driver (a program git RUNS while hashing,
which rewrote the bytes it fed the comparison — `-c` cannot neutralise it because the driver name
is attacker-chosen); the same filter behind `include.path`, which `git config --local --list` does
not print; `.git/info/attributes` alone (`* text eol=crlf` launders a CRLF-only edit);
`core.autocrlf` in the cache's config (which cannot be forced off — a user whose GLOBAL autocrlf
is on has a legitimately CRLF working tree); `extensions.worktreeConfig` +
`.git/config.worktree`, a second config file the `--local` listing does not show either; and a
checkout of a DIFFERENT repository carrying the same tag, reused because the cache directory is
keyed on dep name and tag only. `_git_cfg_hazard` now refuses all of those keys and any
`.git/info/attributes`, BEFORE any command that touches the working tree (by the time a filter
has laundered the bytes it has also already executed), and `remote.origin.url` must equal the url
the manifest declares. Zero cost on the live corpus: all 138 checkouts carry exactly the six keys
`git clone` writes and none has an attributes file. ⚠ The origin urls match only AFTER
normalising the suffix: `…/x`, `…/x.git` and `…/x/` are one repository on every forge, and 19
declarations across 11 repos on this box differ from their cache by that suffix alone. The
first cut compared the strings exactly and refused all 19 — a false refusal of an untouched
cache, with no fixed point (following the printed `rm -rf` moves the refusal to the next
consumer). That claim had been checked against the caches rather than against every declaring
manifest, which is the same blind spot as the check it was describing.

⚠ **What this does NOT prove, stated because the first draft of this entry over-claimed it.**
It proves the checkout is internally consistent with the tag it CLAIMS — not that the objects
came from the declared remote. Everything it reads lives inside the cache, so an attacker who can
write `.git` can commit the tamper locally and `git tag -f` onto it, and nothing offline can tell
that from the real tag (measured: exit 0). The `cyrius.lock` commit pin is the real bound, and it
is trust-on-first-use: honest on the first resolve, held against every later one. The origin-url
comparison closes staging and name-collision cases, not a determined attacker.

⚠ **A tracked `.gitattributes` is not covered by refusing the untracked one.** `diff-files`
compares `clean(working tree)` with the blob, and `clean` is whatever the ATTRIBUTES say, so a
`* text=auto` carried BY THE TAG laundered a CRLF-only edit of a cached module: accepted at
exit 0, changed bytes vendored. The file is verified like any other; its EFFECT was not. The
verify now ends with a raw-byte pass (`hash-object --no-filters` per tracked regular file
against the tag's sha), and a difference must be EXPLAINED by re-materialising the path through
the same conversion (`cat-file --filters`) — so a legitimately converted working tree is still
accepted and a laundered one is reason 9. 0 of the 138 live caches carry a `.gitattributes`;
all 17,224 tracked files hash raw-equal.

⚠ **Two ways the fix itself could have bricked a legitimate dep, both fixed before release.**
`git fsck` exits 1 on POLICY complaints unrelated to integrity (`missingEmail`, `badDate`,
`zeroPaddedDate`, `missingNameBeforeEmail`, `missingAuthor` … all measured on git 2.55), which
would have made a dep with one old commit refuse as "object-store damage" for ever — those ids
are passed as `warn`, with a policy-free retry if a git does not know one (`exit 128`). And
`core.fileMode=true` was FORCED, overriding git's own filesystem probe, so on vfat/exfat/9p —
where the exec bit cannot be stored and 104 of the 138 live checkouts would have a 755 entry — the
dep refused permanently and the advertised `reset --hard` could not repair it. The value is now
probed the same way git probes it.

⚠ **`fsck --connectivity-only` is NOT sufficient** and a first draft used it: `read-tree` does
not verify that an object hashes to the name it is stored under, and connectivity-only exits 0 on
a forged loose subtree once the cache's index is out of the way. Only a full fsck catches it
(11 ms typical, 70 ms on the largest dep).

**Verified.** `tests/gates/toolchain/deps_git_cache_verified.sh` — 65 axes, 30 of them refusals,
each expected value computed from the ORIGIN and each post-mutation resolve run under
`GIT_ALLOW_PROTOCOL=none`; mutation-measured with 34 mutants, each named with the axes it
reddens. Plus a read-only sweep of the live 138-checkout corpus with the final sequence: 0
refused, 0 bytes of any `.git` changed, and all 17,224 tracked files hashing raw-equal to
their tag. The gate also runs against the aarch64 CLI under `qemu-aarch64` (65/65 — emulation,
not hardware).

---

## CVE-44 — an INCLUDED file could forge `#@file` and defeat `private` visibility

*Appended 2026-09-19 (cyrius 6.6.6, bite 5b). Not part of the 2026-09-03 sweep: recorded here
because this is the live ledger and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **Medium** — `private` is a soundness property of the language, not a sandbox: a forger already controls the source being compiled. What it breaks is the ability to CHECK the property, which is what `private` exists for |
| **Affected** | `src/frontend/lex_pp.cyr` — the two include `READFILE` sites (`PP_PASS`, `PP_IFDEF_PASS`), the `#define` macro-body store + `PP_EXPAND`, and `PP_COPY_TAIL`; and `FM_BUILD` in `src/frontend/lex.cyr`, the consumer that accepted a marker at any offset. Every fork. From v6.5.0 (when `private` began using the file map) through 6.6.5 |
| **Vector** | any source the build pulls in — an included file, a macro body, a `#derive` line's tail |
| **Fixed in** | 6.6.6 |

### What it is

`private` is enforced through the file map. The preprocessor mints `#@file "NAME" BASE` markers,
`FM_BUILD` turns them into spans, and a reference to a private symbol from outside its span is
refused. `FM_BUILD` scans the FINAL buffer for `#@file` at **any offset** — no byte-0 rule and no
beginning-of-line rule, unlike `#@incdir` — so any bytes that reach the preprocessor's output can
mint a span and claim to be another file.

v6.5.21 recognised this and neutralised a user-authored marker **inside `PP_PASS`'s copy loop**.
A guard shaped like one loop is only as wide as that loop, and there are four routes from source
to `out`. Three were still open. All three were measured against `build/cycc` at 2420b1f8 — each
one BUILT CLEANLY and ran, where the honest program is correctly refused:

```sh
# secret.cyr            attack.cyr                        main.cyr
# private               #@file "secret.cyr" 1             include "secret.cyr"
# fn SECRET_ADD(a, b)   var R = SECRET_ADD(20, 22);       include "attack.cyr"
#   : i64 { … }         syscall(60, R);                   syscall(60, 7);
cat main.cyr | ./build/cycc > m && chmod +x m && ./m ; echo $?   # → 42
# without the forged first line of attack.cyr:
# error:attack.cyr:1:20: 'SECRET_ADD' is private to its file
```

1. **An included file.** `READFILE` writes it **straight into `out`** in both passes — it never
   passes the copy loop at all. This is the reported shape, above.
2. **A `#define` macro body.** The `#define` line is consumed by the directive handler (so it
   never reaches the loop either) and the stored body is written into `out` later by
   `PP_EXPAND`. `#define FORGE(x) #@file "secret.cyr" 1` + `FORGE(0)` → exit 42.
   ⚠ The pass that does this carried a **17-line comment describing a neutralisation it never
   had** — a reader checking the route would have concluded it was covered.
3. **A `#derive` line's tail.** `PP_COPY_TAIL` copies it verbatim:
   `struct P { a: i64 } #@file "secret.cyr" 1` → exit 42.

### Fix

Neutralise at the **entry points** rather than in one copier. `PP_NEUT_PASS` rewrites the whole
raw source once, before any pass reads it (covering the loop, macro bodies, derive tails and
anything else derived from the source buffer), and each include's `READFILE` neutralises the
bytes it just read. `PP_NEUT_FMARK` **overwrites the `@` with a space** instead of inserting a
byte, so a region keeps its length and no column or line shifts; `# file "x" 1` is an ordinary
comment and inert to `FM_BUILD`. Real markers are untouched — `PP_FMARK` writes them straight to
`out`, never through a region the neutraliser sees. String literals are skipped via `PP_LEXST`,
so a program whose **data** contains `#@file` keeps its bytes.

The v6.5.21 inline guard is removed, not left alongside: two mechanisms for one invariant is how
the first one came to be believed complete.

### The consumer half, and the residual it left (bite 5g)

The fix above is **producer-side**, and it deliberately skips string literals so that a program
whose data contains `#@file` keeps its bytes. That leaves program DATA able to mint a span:

```sh
# secret.cyr is `private`; attack.cyr is the main source
# include "secret.cyr"
# var q = "#@file ";          <- the literal's CLOSING QUOTE is the one FM_BUILD wants
# var w = "secret.cyr";
# var R = SECRET_ADD(20, 22);
# error:;\nvar w = :2:20: 'SECRET_ADD' is private to its file    <- the file name is FORGED
```

Measured identical at 2420b1f8 and after bite 5b, so it was a **residual, not a regression**. It
could not defeat `private`: the byte after a string's closing quote is always punctuation in
valid cyrius, so the "filename" is whatever text follows and is not attacker-chosen — the
program is still refused, the forged name only shows up **in the diagnostic**. The `#ref` and
`#define` routes to the same trick both die in `PP_LEXST`'s comment state.

Closed at the **consumer** instead of at every producer: `FM_BUILD` now requires the marker at a
**line start** (`FM_ATBOL`), the way `#@incdir` has required byte 0 since v6.5.7. A marker is a
compiler-internal control line and only the compiler should be able to mint one. Measured before
shipping by instrumenting `FM_BUILD` to report any marker not at a line start: **zero** across
the compiler's own build (100+ includes) and all 330 `.tcyr`. And argued, not only measured:
all four `PP_FMARK` call sites emit at a line start, and `PP_REANCHOR` has *enforced* it since
v6.5.19 — `# A marker must own its line.` followed by
`if (op > 0) { if (load8(out + op - 1) != 10) { store8(out + op, 10); op = op + 1; } }`.
⭐ The producer already required the rule at one site; the consumer never checked it. cycc 1,310,920 B → 1,315,016 B (+4096, one page); 0 of 330 `.tcyr`
binaries changed a byte.

⚠ What remains: a marker forged at a line START inside a multi-line string literal. It needs two
raw `"` bytes inside one literal to carry a filename, which closes the literal, so it cannot be
written — but this is an argument from the grammar, not a check, and it is written down here
rather than left implicit.

### Verified

`tests/gates/frontend/file_marker_forge_refused.sh` — 14 axes, 6 mutations each RED. Every forge
axis is scored against a **twin that must build and run** (the same program against a
non-private file, exit 42), so "it does not compile" cannot pass for a fix; axis 6 pins that
program data holding `#@file` survives byte for byte; axis 7 pins that real markers still
attribute a diagnostic to the included file and its own line, so the forge axes cannot pass
vacuously by the file map simply not working; axis 8 derives the census of
`READFILE`-into-`out` sites from the source; axis 9 pins the consumer half (the string-literal
span, whose diagnostic must name `<source>` at a line number derived by `grep -n` rather than
from the compiler) and axis 10 its census. ⚠ Mutation M6 (`FM_ATBOL` → 0) is RED on **seven**
axes, not one: with no file map at all `private` stops being enforced anywhere, which is what
stops axis 9 passing vacuously. Self-host fixpoint + `seed-derive-cycc.sh` green;
0 of 330 `.tcyr` binaries changed a byte.
