# Security audit — 2026-09-03 (cycc 6.5.45)

**Scope:** the untrusted-source-input surface. Previous full audit:
`docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36) at cycc 6.4.82.
**Next free identifier after this document: CVE-68.** (CVE-41 is fixed at 6.5.47; see its entry.) (CVE-37 and CVE-38 in the previous
document are **withdrawn** but still consume their ids.) CVE-43 was consumed at 6.6.5,
**CVE-44 and CVE-45 at 6.6.6** — the release installer's fixed `/tmp` staging, and a forged `#@file` from an included file —
**CVE-46, CVE-47 and CVE-48 at 6.6.7** (a `secret var` inside a closure was never zeroised; a `secret var` in a
fn whose `return f(..)` was compiled as a tail call was never zeroised; on agnos a server bound to 127.0.0.1
listened on the network), and **CVE-49 and CVE-50 at 6.6.9** (`cyrius self` staged and executed compilers at
predictable shared `/tmp` names; `lib/http.cyr` wrote a long URL past its 2048-byte request buffer), and
**CVE-51, CVE-52 and CVE-53 at 6.6.10** (on Intel-Mac, reading the clock wrote mach time through a stale
`rdx`; the lexer silently dropped any `@` that did not spell `@unsafe`; `lib/ws.cyr`'s `ws_recv_frame` let a
remote peer choose its allocation size and read frames it had not received), and **CVE-54 and CVE-55 at 6.6.11**
(on Windows, `net_resolve_ipv4` read a drive-relative `C:\etc\hosts` that any local user can plant; a multi-line
string literal shifted file attribution, so a call to another file's `private` fn compiled); **CVE-56 at 6.6.12** (`lib/log.cyr`'s `log_info_kv` / `log_info_int` built a log line past a 512-byte stack buffer); **CVE-57 at 6.6.12** (on Windows, the folded sandhi resolver read a drive-relative `C:\etc\resolv.conf` any local user can plant); **CVE-58 at 6.6.12** (cxvm let guest bytecode read and write the interpreter's own host memory); **CVE-59 at 6.6.13** (the libssl TLS backend never bound the server's certificate to the host, so any chain-valid certificate verified any host); **CVE-60 at 6.6.13** (the libssl backend's `tls_read` / `tls_write` (and `tls_get_peer_spki_der`) returned a C `int` zero-extended, so a tampered record read as ~4 GiB read); **CVE-61 at 6.6.13** (the native TLS stack skipped plaintext ChangeCipherSpec records without limit and had no deadline, so anyone on the path held a thread for ever); **CVE-62 at 6.6.13** (a `[deps.NAME]` header holding `..` made `cyrius deps` create directories and git-clone outside the dep cache — a CVE-32 residual); **CVE-63 at 6.6.13** (the native TLS client verified an IP-literal host against dNSName SAN entries, wildcards included); **CVE-64 at 6.6.14** (a native TLS server that required client certificates authenticated nobody: a TLS 1.2 client connected with none, a TLS 1.3 client with any leaf, and `tls_set_verify` dropped FAIL_IF_NO_PEER_CERT); **CVE-65 at 6.6.14** (on Windows, the native TLS client read its trust roots from a drive-relative `C:\etc\ssl\cert.pem` any local user can plant); **CVE-66 at 6.6.14** (a TLS write to a peer that had reset the connection raised SIGPIPE, so any peer could kill a native- or libssl-backed TLS client or server process); **CVE-67 at 6.6.14** (the native TLS client took any `*.` dNSName as a wildcard, so a certificate for `*.com` verified every `.com` host); all twenty-five are appended below.
⚠ **This line read "next free: CVE-42" while CLAUDE.md read "the next CVE number is 43" and this document ran 39-41.**
Two authorities, two answers, and nothing reconciled them. CLAUDE.md is the one every closeout reads, so **42 is
retired unused** and CVE-43 is the entry appended below. Anything below 64 now collides.

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

## CVE-44 — the release installer staged the tarball AND its signature inputs at fixed `/tmp` names

*Appended 2026-09-19 (cyrius 6.6.6), found by the bite-13 review's sweep of tool and script
write safety. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger
and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **High** — local privilege/supply-chain: another user on the box can redirect the installer's writes, and can swap the inputs to the signature check that authorises the install |
| **Affected** | `scripts/ci.sh` (the CI installer), since the .sha256 check landed at v6.2.30 / CVE-21 and the Ed25519 check at v6.2.31 / CVE-13, through cyrius 6.6.5 |
| **Fixed** | 6.6.6 |

**Vector.** Six fixed, predictable paths in a world-writable directory:

```
/tmp/$TARBALL            /tmp/${TARBALL}.sha256   /tmp/SHA256SUMS
/tmp/SHA256SUMS.sig      /tmp/cyrius-release.pub  /tmp/cyrius_tsum
```

That is the tarball being installed *and all three inputs to the signature check that is
supposed to authorise installing it*. `/tmp`'s sticky bit stops another user **deleting** your
file; it does not stop them **creating** a name that does not exist yet. Two consequences, and
the first is not a race:

1. **Deterministic — arbitrary file overwrite as the installing user.** `curl -o <path>` and
   `printf … > <path>` both follow a symlink. A local user who creates `/tmp/$TARBALL` (or
   `/tmp/cyrius-release.pub`) as a symlink to any file the installing user can write has that
   file overwritten the next time CI installs. **Measured** against the 6.6.5 script in the
   hermetic harness of `release_verify_private_temp.sh`: `/tmp/$TARBALL` planted as a symlink
   out of `/tmp`, and the link's target came back **clobbered with the downloaded tarball**. The
   `cyrius-release.pub` half is **reasoned, not measured** — `printf … > /tmp/cyrius-release.pub`
   follows a symlink by exactly the same mechanism — and the gate deliberately does not plant it:
   that name has no version in it, so planting it would collide with any concurrent run on the
   same box (the gate says so at the planting step). On a CI runner the installing user is very
   often the one whose `~/.ssh/authorized_keys`, shell profile or job script matters.
2. **A race — the signature check answers to the attacker.** The attacker owns the six files, so
   they can rewrite any of them at any moment, including between `printf … > /tmp/cyrius-release.pub`
   and `cyrsign verify … /tmp/cyrius-release.pub`, and between the verify and `tar xzf
   /tmp/$TARBALL`. Win either window and an arbitrary tarball installs with "signature verified
   (Ed25519)" printed above it. **A verification whose inputs another local user can swap is not
   a verification** — which makes this a hole in CVE-13's fix, not a separate inconvenience.

**Fix.** One `mktemp -d`, `chmod 700`, everything staged inside it, removed by an `EXIT` trap.
Deliberately *not* a check: "is this still the file I wrote?" is itself a TOCTOU. An unguessable
0700 directory leaves nothing to pre-create and nothing to swap. A `mktemp` that cannot produce a
directory **aborts the install** — it never falls back to a shared one. (⚠ The naive fallback
`TD=/tmp` is worse than the bug: the script's own `trap 'rm -rf "$TD"' EXIT` then runs
`rm -rf /tmp`. Measured once while mutation-testing the gate, and it took every other process's
scratch with it.)

**Verified.** `tests/gates/toolchain/release_verify_private_temp.sh` — 4 axes, run hermetically
with `curl`, `cyrsign` and the checksum tools stubbed on `PATH` over a fake release, so no
network is touched and "which public key reached the verifier" is directly observable. Axis 2 is
the exploit: the two version-specific names pre-created, the tarball as a **symlink out of
`/tmp`**; the link target must come back byte-for-byte, the planted files must be neither written
nor removed, and the genuine payload must install. (The four version-INDEPENDENT names —
`SHA256SUMS`, `.sig`, `cyrius-release.pub`, `cyrius_tsum` — are deliberately not planted: they are
shared with every other process on the box, so planting them would make the gate collide with a
concurrent run. Same defect, same mechanism, same fix; the static axis is what pins that the
fixed installer touches none of them.) Axis 1 is anti-vacuous (a well-formed
release installs and verifies against the pinned key), axis 3 pins the abort-never-fall-back
rule, axis 4 is static over `scripts/ci.sh`. Mutation-measured: the 6.6.5 script verbatim reddens
axes 2, 3 and 4. The tree-wide version of the static axis — no fixed `/tmp` name, and every
`mktemp` checked, across **all** of `scripts/*.sh` — is axis 7 of
`tests/gates/toolchain/gates_never_write_tree.sh`.

**Other scripts with the same shape, fixed in the same release (6.6.6, bites 17f and 17j):**
`scripts/install.sh` (`/tmp/cc5_verify`, `/tmp/cc5_verify2`, `/tmp/dlopen_err_$$`, and four
unchecked `mktemp`s), `scripts/cass-install-gate.sh`, `scripts/mac-diagnose.sh`,
`scripts/bench-history.sh`, and — found by the bite-17 review, because the first sweep was
`find scripts -maxdepth 1` — **`scripts/shims/cyrius-repl.sh`**, `scripts/lib/audit-walk.sh` and
`benches/bench_capacity_overhead.sh`. The REPL shim is the sharpest of them and is **installed
into `~/.cyrius/versions/<v>/bin`**: it compiled every expression you type to
`/tmp/cyrius_repl_$$`, `chmod +x`'d it and ran it, so a local user who pre-creates that name
(the redirect follows a symlink) or replaces the file between the `chmod` and the `exec` gets
their code executed as you — `install.sh`'s `/tmp/cc5_verify` shape, in a shipped tool. None of
these stage a signature input, so they are the overwrite / local-code-execution half of this
finding rather than the verification-bypass half — but they are the same defect and the same
fix, and the sweep that pins them is now by SHAPE (`scripts/**`, `benches/**`), not by directory
level.

## CVE-45 — an INCLUDED file could forge `#@file` and defeat `private` visibility

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

---

## CVE-46 — a `secret var` (and any `defer`) inside a closure body was registered on the ENCLOSING fn: the closure's key material was never zeroised

*Appended 2026-09-27 (cyrius 6.6.7, bite 1). Not part of the 2026-09-03 sweep: recorded here
because this is the live ledger and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — `secret` is the language's only guarantee that key material does not outlive its scope, and consumers (sigil, sakshi) rely on it for exactly that. Not attacker-triggered: the defect is in code the program's own author wrote, and what it breaks is the guarantee, silently |
| **Affected** | `src/frontend/parse_expr.cyr` (the closure emitter) and `src/frontend/parse_fn.cyr` (`_instantiate_generic_fn`, `_async_emit_constructor`, PARSE_FN_DEF's epilogue). Every target (x86/PE/Mach-O, aarch64, cx). From v6.3.7 (closures) through 6.6.6 |
| **Vector** | `secret var buf[N];` or `defer { … }` written inside a closure literal (`\|x\| { secret var key[32]; … }`); any fn that registers a `defer`/`secret` and then makes its first explicit `f<T>(..)` call |
| **Fixed in** | 6.6.7 |

### What it is

`secret var` is implemented as a synthetic `defer` whose block zeroes the buffer, run by the
function epilogue's defer walker. The per-fn defer table was reset only by PARSE_FN_DEF and walked
only at its epilogue. A closure body is a function emitted INSIDE another function's body, and
the closure emitter neither isolated nor walked that table, so a closure's `secret`/`defer`
entry was appended to the ENCLOSING fn's table:

- the closure's own return never zeroised the buffer;
- the enclosing fn's epilogue tested the entry's reached-flag at the closure's slot index in
  the ENCLOSING frame (a different variable), so it usually skipped the block — and when that
  slot happened to be non-zero it ran the closure's block in the wrong frame;
- the flag's `= 0` initialisation, emitted by the enclosing trampoline, wrote 0 into that
  enclosing slot: `fn outer(a, b, c, d)` holding a closure with a `defer` returned 1204 for 1234,
  because parameter `c` was zeroed.

Measured on 6.6.6 (`build/cycc` at the 6.6.7 open), x86_64 Linux:

```
fn caller(): i64 {
    var f = |x| { secret var key2[32]; store64(&key2, x); return &key2; };
    return fncall1(f, 77);
}
# after caller() has RETURNED, load64(result) is still 77 — the key was never cleared
```

A generic instantiation went the other way: `_instantiate_generic_fn` re-enters PARSE_FN_DEF,
which zeroed the table, so every `defer`/`secret` the enclosing fn had registered before its
first `f<T>(..)` call was DROPPED — never run on any return path.

### Fix

The three nested-fn emitters (closure, generic instance, async constructor) now go through one
per-fn state snapshot (`_fnst_save` / `_fnst_restore`, `src/frontend/parse.cyr`). The nested fn
owns only the defer entries and return patches it appends — `_defer_base` / `_rp_base` mark where
they start — and PARSE_FN_DEF and the closure path share one epilogue authority
(`_defer_emit_init`, `_rp_patch_here`, `_defer_emit_walk`), so a closure now zeroes its own flags
at entry, lands its own returns, and runs its own `secret`/`defer` blocks before it returns. The
same snapshot fixed the rest of the drifted per-fn state (the return patches lost by an early
`return` before a closure — CHANGELOG [6.6.7]).

### Verified

`tests/tcyr/crossos/defer_every_return_path.tcyr` — the `secret var in a closure is zeroised at
the closure's return` row reads the (static-fallback) buffer after the closure returned and wants
0 (on the pre-fix compiler the file never reaches that row — an earlier row SIGSEGVs — so the
defect itself was measured with the standalone probe above: 77 still readable after `caller()`
returned, 0 after the fix). Mutation: dropping the closure's
`_defer_emit_walk` call turns that row and both closure-defer rows RED. Green on x86_64 Linux,
aarch64 (qemu and real pi), Mach-O arm64 (ecb), Mach-O x86_64 (ach), PE (wine) and cx (cxvm);
cass (real Windows) was down at the time and is left to the release gate. Self-host fixpoint and
`seed-derive-cycc.sh` green.

## CVE-47 — a `secret var` was never zeroised when its fn returned through a tail call (`return f(..);`)

*Appended 2026-09-27 (cyrius 6.6.7, bite 2). Not part of the 2026-09-03 sweep: recorded here
because this is the live ledger and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — the same guarantee as CVE-46 (key material does not outlive its scope), broken on the most common return spelling there is. Not attacker-triggered; silent |
| **Affected** | `src/frontend/parse_fn.cyr` (PARSE_RETURN's tail-call arm), every target (x86/PE/Mach-O, aarch64, cx). Present at least since 5.11.69 (`build/cc5` reproduces it) through 6.6.6 |
| **Vector** | any fn holding a `secret var` whose `return IDENT(args);` is compiled as a tail call — `return helper(x);`, `return Ok(v);` / `return Err(e);` (Ok/Err are ctor fns) — when nothing else in the fn forces the normal call path |
| **Fixed in** | 6.6.7 |

### What it is

`secret var` registers its zeroise as a synthetic `defer`, run by the function epilogue's defer
walker. PARSE_RETURN lowers `return IDENT(args);` to epilogue + `jmp` (ETAILJMP; a call plus an
inline epilogue on cx), which never reaches the walker, and none of the tail arm's diverts asked
whether the fn had a `defer`/`secret`. The one incidental shield — a fn that has taken a local's
address (`_fn_local_addr`) is not tail-called — is lexical: it covers only returns parsed AFTER
the first `&key`, and a static-storage secret (an array over the frame budget) never sets it.

Measured on the 6.6.7 bite-1 compiler, x86_64 Linux (aarch64 under qemu: 65 bytes, same static
result):

```
fn leak_tail(x): i64 {
    secret var key[64];
    var i = 0;
    while (i < 3) {
        if (i == 2) { return _value(); }   # parsed before the first &key: tail-called
        memset(&key, 90, 64);
        i = i + 1;
    }
    return 0;
}
# a 4 KB uninitialised local in the next call finds 66 bytes of 0x5A on the dead stack
fn stat_tail(): i64 { secret var big[200000]; store64(&big, 0x5A5A5A5A); gbig = &big; return _value(); }
# load64(gbig) after the return: 1515870810 (the pattern) — never cleared
```

The same skip dropped every ordinary `defer` on those returns (a lock never released, an fd never
closed — `return Ok(fd);` is the shape agnodrm hit), and the walker, when it did run, preserved
only the first return register, so any call in a defer or zeroise body could destroy an `Ok`
payload or the second half of a pair (CHANGELOG [6.6.7]).

### Fix

A fn whose body contains `defer` or `secret` ANYWHERE (a whole-body prescan at its `{`,
`_body_has_defer`, kept per-fn through the nested-fn snapshot) never tail-calls: its `return
f(..);` takes the normal call path and reaches the walker. The tail arm's diverts are one
predicate now (`_tc_must_divert`). The walker saves the whole return convention
(`EDEFER_SAVE`/`EDEFER_RESTORE`, per backend), and a fn with a `defer`/`secret` is never
inline-replayed into a caller.

### Verified

`tests/tcyr/crossos/defer_every_return_path.tcyr`: `stack secret zeroised on a tail return that
precedes &key` (a dead-stack scan with an anti-vacuous twin — the same shape without `secret` must
be found) and `static-storage secret zeroised on a tail return`. Mutation: disabling the prescan
divert turns both RED (along with 13 defer rows). Green on x86_64 Linux, aarch64 (qemu and real
pi), Mach-O arm64 (ecb), Mach-O x86_64 (ach), PE (wine) and cx (cxvm); cass (real Windows) was
down and is left to the release gate. Self-host fixpoint and `seed-derive-cycc.sh` green.
## CVE-48 — on agnos, a server bound to 127.0.0.1 listened on the network

*Appended 2026-09-27 (cyrius 6.6.7, bite 4), found by the 6.6.7 batch audit of the agnos peer.
Not part of the 2026-09-03 sweep: recorded here because this is the live ledger and the id has
to come from one place. Drafted as CVE-47 and renumbered before release: 6.6.7 bite 2 spent
CVE-47 first.*

| | |
|---|---|
| **Severity** | **High** — remote exposure of services that chose loopback as their access control; silent (no diagnostic, and the host build of the same program is correct) |
| **Affected** | `lib/net.cyr` `sock_bind` (agnos arm) + `lib/syscalls_x86_64_agnos.cyr` `_agnos_listen_start`, since the agnos server adapter landed at v6.2.22, through cyrius 6.6.6 |
| **Fixed** | 6.6.7 |

**Vector.** agnos has no BSD `bind()`: `sock_listen`#56 merges bind and listen and takes a port.
The v6.2.22 adapter therefore made `sock_bind(fd, addr, port)` stash the port and **drop the
address** — its comment said so ("addr is ignored"). A server written the portable way,
`sock_bind(fd, INADDR_LOOPBACK(), port)`, meaning *local clients only*, got a listener on the
NIC: before agnos 1.57.7 the kernel had no address classes at all, and from 1.57.7 the class-0
form it was sent is ANY (the NIC address **and** 127/8). Nothing reported the widening, and a
Linux build of the same source binds loopback correctly, so no host test could see it. The
consumer that matters is daimon, whose default control API is unauthenticated and bound to
127.0.0.1 — daimon's own `src/server.cyr` notes that on agnos "sock_bind ignores the address",
and it had fixed exactly this widening on the host side in 2.3.0.

**Fix.** agnos 1.57.7 added the class the adapter needed: `#56` a1 = `port | class << 32`,
class 1 = LOOPBACK (admits only SYNs addressed to 127/8, which the wire drops, so they can only
originate on this host). `sock_bind` now derives the class from the address
(`_agnos_listen_class`): 127/8 → `SOCK_LISTEN_LOOPBACK`; 0.0.0.0 or this host's `net_ip` →
class 0; **any other address → `Err(99)` (EADDRNOTAVAIL), never widened**. The port is range-
checked (1..65535, else `Err(22)`) because it shares the register with the class bits. The class
and bind address live in per-slot tables that `sys_close` clears with the port, so a recycled
slot inherits neither; `getsockname` reports the real bind address.

**Fails closed, with no probe.** A kernel older than 1.57.7 refuses any `#56` value above 65535
(`if (arg1 > 65535) return -1`, verified in `git show 1.57.6:kernel/core/syscall.cyr` and
`v1.46.8`), so a loopback `sock_listen` there returns `Err` and the server **does not start**.
⚠ Consumer-visible: **daimon's default 127.0.0.1 serve now refuses to start on agnos < 1.57.7**
instead of exposing its API. A probe was rejected on purpose — the filing suggested
`spawn_limits#107(0, 0)`, which would also disarm a pending spawn-limits arm.

**Verified.** `tests/gates/platform/agnos_peer_fake_kernel.sh` axis 4 runs `net.cyr` on a
PTRACE_SYSEMU fake kernel and reads `#56`'s register: 127.0.0.1 → `8080 | 0x100000000`,
0.0.0.0 and `net_ip` → class 0, a foreign address and port 70000 refused, `getsockname` =
127.0.0.1:8080, and — with the kernel scripted as pre-1.57.7 — the loopback `sock_listen`
fails. Mutation: restoring the address-dropping `sock_bind` turns five assertions red.
`syscall_wrapper_pass.sh` axis 5 pins the `sys_close` clear. **On a real agnos 1.57.10 kernel
in QEMU** (`-smp 1` and `-smp 4`): a 127.0.0.1:9000 bind + listen succeeds, `getsockname` reports
127.0.0.1:9000, a forked client's dial to 127.0.0.1 is accepted and `getpeername` reads 127.x,
**a dial to the host's own `net_ip` on that port is refused**, and a bind to an address the host
lacks is `Err(99)`. The `net_ip` dial is only evidence with its controls, so the probe carries
both: it dials `_agnos_bswap32(net_ip)` (`sys_net_ip()` is the ip4() form and `sock_connect`
byte-swaps its address — the first probe dialled the raw value, i.e. a foreign address, and its
"refused" proved nothing; caught in review), a 0.0.0.0 (class 0) listener on the same guest
ACCEPTS that same dial, and the same probe built against the pre-fix `net.cyr` has the 127.0.0.1
listener accept it too — the vulnerability reproduced on the real kernel, then closed. The pre-1.57.7 fail-closed arm is proven on the fake kernel only (no older
kernel was booted).

## CVE-50 — `lib/http.cyr` wrote a long URL past its 2048-byte request buffer

*Appended 2026-09-28 (cyrius 6.6.9, bite 12), found by the 6.6.8 bite 3 review of `lib/http.cyr`.
Not part of the 2026-09-03 sweep: recorded here because this is the live ledger and the id has to
come from one place. 6.6.9 bite 10 spends CVE-49.*

| | |
|---|---|
| **Severity** | **High (P1)** — an out-of-bounds heap write whose length and bytes are the caller's URL; silent (no diagnostic, and the call then fails or succeeds normally) |
| **Affected** | `lib/http.cyr` `_http_build_request`, reached by `http_get`, `http_get_r` and `http_get_a`, since the module's first version, through cyrius 6.6.8 |
| **Fixed** | 6.6.9 |

**Vector.** `_http_build_request(method, host, path)` did `alloc(2048)` and then `memcpy`d the
method, the whole path, the fixed ` HTTP/1.0\r\nHost: ` text, the host and the
`Connection: close` trailer into it with no length check. `path` and `host` come straight from
the URL (`_http_parse_url` points `path` into the caller's string and copies the host), and the
URL is exactly what callers take from outside — phylax's `rules fetch <url>` passes its argument,
abaco builds one from configuration. `_http_parse_url` rejects CR, LF, TAB and space, so the
overflow carries any other byte. It runs **before** any socket is opened, so it was reachable even
though the same release's connect defect (the host string passed as the address) meant no request
was ever sent.

**Impact.** The write lands past the buffer in the global allocator's chunk. Measured on this tree
(the review's probe, now a test row): after building a request for a 4000-byte path, the NEXT
`alloc(64)` comes back already full of the path's bytes — memory the allocator hands out as
fresh, which cyrius code routinely treats as zeroed. Reasoned from `lib/alloc.cyr`, not
demonstrated: `alloc` is shared by every thread under one lock, so another thread's LIVE
allocation made just after the request buffer is overwritten; and a buffer near the end of a
chunk writes past the chunk's mapping — a SIGSEGV, or corruption of whatever mapping follows.

**Fix.** The builder computes the request's length first — method + 1 + path + 17 + host + 23 +
the NUL — and returns 0 when it exceeds `_HTTP_REQ_CAP` (2048, the old buffer's size, so no
request that used to fit is refused); otherwise it allocates exactly that length. All three
callers go through `_http_prepare`, which builds the request first and returns before any lookup
or socket when the builder refuses it: `http_get` / `http_get_a` return status `HTTP_ERROR`,
`http_get_r` returns `Err(HttpBadUrl)`. (The first cut resolved the host before checking, in two
of the three callers, so an over-long URL still read `/etc/hosts` + `/etc/resolv.conf` and sent a
DNS datagram for its host; the review caught it under `qemu-x86_64 -strace`.)

**Verified.** `tests/tcyr/crossos/http_connect_by_name.tcyr`, group *CVE-50*: a 4000-byte path
is refused **and the next allocation holds none of its bytes**; an over-long Host is refused; a
request of exactly 2048 bytes with its NUL builds (2047 long) and one byte more is refused; all
three `http_get*` return their error for a long URL whose host only DNS could answer, and
`_http_prepare` leaves its address slot untouched on the refusal (no lookup ran). Mutation: restoring the unchecked builder
turns five rows red, including the next-allocation row. Green on x86_64 Linux, the agnosticos
CI container, aarch64 (qemu and real pi), Mach-O arm64 (ecb), Mach-O x86_64 (ach) and PE (wine
and real cass).
---

## CVE-53 — `lib/ws.cyr`'s `ws_recv_frame` let a remote peer choose its allocation size and read frames it had not received

*Appended 2026-09-28 (cyrius 6.6.10, bite 14), found by the 6.6.8 review of the agnos userland
(the unchecked-read shape of `async_timeout`, grepped across the stdlib). Not part of the
2026-09-03 sweep: recorded here because this is the live ledger. The id was pre-assigned by the
6.6.10 plan; the counter lines above are reconciled at integration, not by this bite.*

| | |
|---|---|
| **Severity** | **High (P1)** — a remote WebSocket peer controls the size of an allocation and, when it fails, a write through the failed pointer; silent (frames are reported complete when they are not) |
| **Affected** | `lib/ws.cyr` `ws_recv_frame` (and `ws_recv`, which calls it) since the module's first version, through cyrius 6.6.9; the same reader shape in `lib/ws_server.cyr` `ws_server_recv_frame` (fail-closed, not memory-unsafe — see below); every consumer that vendors either file |
| **Fixed** | 6.6.10 |

**Vector.** The client reads a frame the server sends, so the bytes are the remote peer's.
`ws_recv_frame` took the 16-bit and 64-bit extended length, the mask and the payload each with
ONE unchecked `sys_read`. (1) A short read — routine for any frame larger than one TCP segment —
left stale stack bytes as the length or the mask, and a short payload read was reported as the
whole payload with the declared `plen`. (2) The 64-bit length kept only its low 32 bits, so
`0x80000000_00000005` read as 5. (3) `alloc(plen + 1)` took the peer's length with no bound and
no check, and then `sys_read(fd, payload, plen)` and `store8(payload + plen, 0)` ran through
the result.

**Impact.** A peer declaring a ~4 GiB payload makes the client attempt a 4 GiB allocation; when
`alloc` returns 0 the NUL store lands at address `plen` — a SIGSEGV for any peer that wants the
process gone, i.e. a remote crash of any cyrius WebSocket client (yantra's CDP driver reads
Chromium's frames through it). A peer that simply sends
a large frame in several segments gets its message silently truncated and padded with stale
bytes — data corruption with no error. Measured on this tree (the test rows below, against the
6.6.9 reader): a 300-byte frame truncated to 10 bytes came back as a 300-byte payload; a frame
whose declared length has its top bit set came back as a 5-byte payload; a frame delivered in
nine pieces was dropped at its 1-byte first read.

**Also in the same file (no separate id).** `_ws_handshake_request` `memcpy`d the path and host
into a fixed `alloc(512)` with no length check — the CVE-50 shape: after building a request for
a 2048-byte path the NEXT `alloc(64)` came back full of the path's bytes. `ws_connect` compared
bytes 9-11 of a response it may have read fewer than 12 bytes of. `ws_new` and the frame sender's
masking buffer used `alloc` unchecked.

**`lib/ws_server.cyr`.** `ws_server_recv_frame` bounded the length (`len > max`,
`WS_MAX_PAYLOAD`) and read the payload in a loop, but the header, extended-length and mask reads
treated a short read as a dead connection (a healthy client whose frame was split was dropped),
and a 64-bit length with its MSB set composed to a NEGATIVE `len` that passed both bounds and was
returned as the "length" (`ws_server_recv` treats any negative as a close, so it was not
memory-unsafe there).

**Fix.** Every frame part goes through a read-exactly loop (`_ws_recv_exact` /
`_wss_recv_exact`; EINTR retried, EOF or an error is a failure). A 64-bit length with any of its
top 32 bits set is refused (RFC 6455 §5.2 requires the MSB to be 0, and nothing that large fits
a cap), as is any length above `WS_RECV_MAX_PAYLOAD` (16 MiB, a public var the caller may set)
— before any allocation. The allocation is checked. A refused or short frame returns 0 with
`len_out` 0 and marks the connection CLOSED (the stream position is unknown after it). The
handshake request is sized from its inputs; a response shorter than 12 bytes is not OPEN; the
server reader refuses the negative length by name.

**Sibling copies.** `majra`'s `majra_ws_recv_frame` (src/ws.cyr) was already correct — its
2.6.9 repair reads exactly, bounds the length and rejects the top 32 bits — so it needs no fix.
yantra has no reader of its own: its CDP driver calls this `ws_recv`, and the 52 sibling repos that
vendor `lib/ws.cyr` / `lib/ws_server.cyr` pick the fix up at their next stdlib re-vendor on 6.6.10.

**Verified.** `tests/tcyr/stdlib/ws_recv_frame_short_reads.tcyr` (30 rows): complete frames
still read; a truncated payload, extended length, mask and header each return 0 and CLOSE; the
top-bit, >4 GiB and cap+1 lengths are refused; a lowered cap refuses a 5-byte frame; a 2048-byte
path builds a complete request and the next allocation holds none of its bytes; a frame a forked
child writes in nine pieces arrives whole. `tests/tcyr/stdlib/ws_server_recv_frame_exact.tcyr`
covers the server reader (top-bit length is -1, a split frame is received). Mutation: the 6.6.9
`lib/ws.cyr` turns 17 of the 30 rows red (every truncation, bound and next-allocation row); the
6.6.9 `lib/ws_server.cyr` turns 3 of 7 red.

---

## Hardening, 6.6.9 bite 9 (no CVE): the CLI's temp base honours `$TMPDIR`, and a temp dir it cannot write is never read as a verdict

Not a CVE: every site below already FAILED CLOSED — nothing untrusted was accepted — but each
read "my capture came back empty" as an answer, so the refusal named the wrong cause.

- **`_git_run` / `_sha256sum_file`** opened their stdout capture in the CHILD and, when that open
  failed (EDQUOT, ENOSPC, no inodes), ran git / sha256sum with the parent's stdout. Under a full
  `/tmp` the CVE-43 cache check then refused every healthy git dep as **tampered** with `rm -rf`
  advice (reasons 1, 2, 3, 8 all reachable), and the hasher read as "sha256sum missing?". The
  capture is now opened by the PARENT before the fork; a refusal reached while a capture could
  not be written — or while the private temp dir refuses a fresh file as big as git's write
  (64 KB, or the dep's own index size), asked BEFORE the verify removes its own temps — is
  **reason 10** (still a refusal), which names the temp dir and errno and prints no restore
  recipe. (Review round: probing AFTER the cleanup, and reading a failed `update-index
  --refresh` through `diff-files`, still called a NEARLY full temp dir — 4-8 KB or 5 inodes
  left — tampered; both closed.) The hasher asks the same question when it prints no digest, so
  a capture that opened but could not be written no longer blames the dependency file.
- **`cyrius lint`'s syntax pre-pass** FAILED OPEN on the same condition — a file that does not
  parse linted `0 warnings`, rc 0. It now refuses by name.
- **`_cbt_tmpbase`** returned the literal `/tmp` on every POSIX target, so a user could not route
  the CLI off a full `/tmp`. An **absolute** `$TMPDIR` is now the base (trailing slashes dropped;
  a relative value is ignored, since it would resolve against whatever directory a verb runs in).
  The private-directory discipline of CVE-35/CVE-36 is unchanged: an EXCLUSIVE 0700 `mkdir`, 16
  candidates, fail closed, never a shared name — except that a failure other than EEXIST (a
  `TMPDIR` that is gone or unwritable) now stops at once and names the base and errno instead of
  burning the 16 candidates and blaming stale directories. On macOS this moves every CLI temp from `/tmp`
  to the per-user `/var/folders/…/T` — a 0700 per-user directory, which narrows the shared
  namespace further. The leak gates that counted `/tmp/cyrius-*` derive the same base, so a set
  `TMPDIR` cannot make them read green over directories they never looked at.

Gate: `tests/gates/toolchain/deps_cache_capture_failure_named.sh` (the filing's `unshare` +
`nr_inodes` recipe swept 2-8, a 64 KB tmpfs at 0-12 KB free, a 1500-file dep at 0-320 KB free,
TMPDIR routing and a missing/unwritable TMPDIR, the hasher out of inodes and full, lint, a
failing `update-index`, and static checks that the capture is opened before the fork and the
verdict judged before the cleanup), mutation-proven per mechanism.

---

## CVE-49 — `cyrius self` staged and EXECUTED compilers at predictable shared `/tmp` names

*Appended 2026-09-28 (cyrius 6.6.9, bite 10), found by the 6.6.6 review of the self-host verbs
(the adjacency of `cmd_soak`'s move onto `_self_host_step`). Not part of the 2026-09-03 sweep:
recorded here because this is the live ledger and the id has to come from one place.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — local; another user on the same host can make `cyrius self` run their code as the invoking user, or clobber a file the invoking user can write. Silent |
| **Affected** | `cbt/commands.cyr` `cmd_self`, POSIX arm (Linux, macOS arm64/x86, aarch64 Linux), from before the v6.4.81 private temp dir through cyrius 6.6.8. The PE arm (`_win_cmd_self`, 6.6.6) was never affected |
| **Fixed** | 6.6.9 |
| **Class** | CVE-35/CVE-36 (predictable shared-`/tmp` names for staged-and-executed binaries — the reason the private temp dir exists); cf. CVE-44 (the installer's fixed `/tmp` staging of signature inputs, a different threat) |

**Vector.** `cmd_self` forked `/bin/sh -c` over a script that began
`cycc=/tmp/cyr_cc5_$$;ccr=/tmp/cyr_ccr_$$;cc4=/tmp/cyr_cc4_$$`, wrote step 1's compiler with
`>$cycc`, copied it with `cp $cycc $ccr`, and then **executed `$ccr`** (`cat $F|$ccr>$cc4`).
`$$` is the shell's PID, which is predictable, and none of the three writes is exclusive. So a
local user who creates those names first decides what happens: a symlink at `/tmp/cyr_cc5_<pid>`
makes the redirect overwrite any file the victim can write with a compiler binary; a regular
file they own at `/tmp/cyr_ccr_<pid>` (mode 0666) is truncated and written by `cp` but stays
THEIRS, so they can rewrite it between the copy and the exec and the victim runs their program.
v6.4.81 (CVE-35/CVE-36) had moved every other cbt temp into `_cbt_tmpdir()`'s 0700
exclusive-mkdir directory; this verb predated it and was never migrated. On Linux the
`fs.protected_symlinks=1` / `fs.protected_regular=1` defaults blunt both halves; **macOS has no
equivalent** — and `/tmp` there is shared by every local user — which is where the verb is most
often run (ecb, ach). `grep` over cbt/ confirmed it was the only fixed `/tmp/<name>` left in a
cbt string.

**Also found while fixing it (same script, no separate id).** The script scored a **0-byte
compiler as a PASS**, rc 0: `/bin/sh` runs an empty executable as an empty SCRIPT (exit 0, no
output), so both steps "succeeded" and `cmp` of two empty files is equal. Measured with the
6.6.8 CLI on x86-64 Linux, pi, ach and ecb — a green self-host verdict for no compiler at all.

**Fix.** The POSIX arm is native: `_self_host_step(_cc, src, t1)`, `_self_host_step(t1, src,
t2)`, `_self_host_same(t1, t2)` — the helpers `cmd_soak` already used — over `_cbt_tmpexe` /
`_cbt_tmpfile` names inside the private directory, removing what it staged on every path. The
step runs the compiler RAW (no `compile()` prepend), signs a COPY on macOS, and refuses an
empty output; `_self_host_same` has a non-empty floor, so a 0-byte compiler is now
`error: self-host step 1 (./build/cycc, compiling src/main.cyr) exited 127` on Linux and
`could not stage a signable copy` on macOS. A failed step is named — the step, the compiler by
path, the source, and what it actually did (`exited N`, `was killed by signal S`, `exited 0 but
wrote no output`; never a status the compiler did not return) — instead of folding into
`FAIL: cycc!=cycc`. Packed with the same bite's temp-hygiene fix to the helper it now
shares: `_copy_binary` removes its dst when it fails, and `_self_host_step_macos` removes its
staged copy on every return — before, a failed stage (a 0-byte or unreadable `cc`, ENOSPC
mid-copy) left `selfhost_signed` behind and, because the exit sweep is rmdir-only, the whole
`cyrius-<pid>` directory with it (reproduced on ecb and ach with the 6.6.8 CLI; gone with the
fix).

**Verified.** `tests/gates/toolchain/cbt_no_shared_tmp_paths.sh`: no string literal in any
cbt/*.cyr names a `/tmp/` path (a lexer-faithful scanner — comments and char literals skipped —
with a self-test and a 2000-literal floor); `cyrius self` over a stub compiler that writes
itself PASSes with step 2 run from under `$TMPDIR/cyrius-<pid>/`, and each failure shape
(step 1, step 2, differing outputs, a 0-byte compiler) is named, non-zero, and leaves `$TMPDIR`
empty; the real `_copy_binary`, extracted and run, leaves no dst for an empty or unreadable
source. The 6.6.8 `cmd_self` fails axes 1-5 and 3b. **On real hardware** with this tree's CLI
and a compiler built from this tree: `cyrius self` PASSes on ecb (macOS arm64), ach (Intel
macOS) and pi (aarch64 Linux) with nothing left under the temp base, and the 0-byte compiler is
refused on all three where the 6.6.8 CLI printed PASS (rc 0). On ecb, ach and pi stub
compilers that exit 42, die of SIGSEGV and exit 0 with no output are each reported as such; on
cass the PE arm names a failing step by compiler path and still PASSes the real self-host.

---

## CVE-51 — on Intel-Mac, reading the clock wrote mach time through a stale register (and its stale-register out-pointer siblings)

*Appended 2026-09-28 (cyrius 6.6.10, bite 1), found by the 6.6.10 group-D triage while chasing
"an unconfirmed garbled assert message on ach" that had stood in the roadmap since 6.6.8. Not part
of the 2026-09-03 sweep: recorded here because this is the live ledger and the id has to come from
one place. 6.6.10 bite 9 spends CVE-52 and bite 14 CVE-53.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — an 8-byte write of emitted-code-chosen data (mach time) to a stale address in an rwx image; neither the value nor the address is attacker-chosen. Silent: no diagnostic, rc unchanged, and a non-writable address is swallowed as EFAULT |
| **Affected** | x86_64-macOS (`CYRIUS_MACHO=1`): every `syscall(228, id, &ts)` — so every `clock_now_ns` / `clock_now_ms` / `bench_*` / sakshi timestamp — from v6.5.16 through cyrius 6.6.9. Siblings below |
| **Fixed** | 6.6.10 |

**Vector.** Darwin has no `clock_gettime`, so `EMACHO_CLOCK_X86` (src/backend/x86/emit.cyr)
composes `syscall(228)` from BSD `gettimeofday(struct timeval *tp, struct timezone *tzp,
uint64_t *mach_absolute_time)`. The THIRD parameter is an out-pointer: xnu copies mach time out
through it when it is non-NULL. The emitter set `rdi = &tv` and `esi = 0` and never wrote `rdx`,
so the kernel wrote 8 bytes to whatever address the previous code left there — normally the
previous call's third argument. `lib/sys.cyr`'s own `_macos_gettimeofday` has documented exactly
this hazard, and passed an explicit 0, since v6.5.16; the emitter never got the same treatment.

**Impact.** The x86 Mach-O image is a single `__TEXT` segment with maxprot/initprot rwx
(`llvm-objdump --macho --private-headers`), so code, string literals and globals are all
writable targets. Measured on ach: `take3(0, 0, &buf); clock_now_ms();` overwrote the sentinel in
3 of 3 runs with `0x0012ADE8A2EA59E2` ns ≈ 60.9 days — ach's uptime; the same probe on ecb
(arm64 binds `_clock_gettime_nsec_np` through `__got`) left it intact. It was the "garbled
assert": `regression_terminate_children.tcyr` against the 6.6.8-lane `lib/regression.cyr`
printed `FAIL: \xAD (got 0, expected 1)` twice on ach — an assert label's bytes overwritten
mid-test — and prints the full message with the fix. When `rdx` held no writable address,
copyout failed with EFAULT, which the reroute ignores, so the defect is "whenever the previous
code left a live pointer in rdx", not literally every call.

**The same class — a Darwin call whose extra or unsupplied argument is an OUT-pointer, filled
from a register the Linux-shaped caller never wrote:**
- **x86-macOS `syscall(22)` at argc 1** (pipe with no fds pointer). `EMACHO_PROC_FIXUP` stores
  Darwin's rax:rdx fds through `rdi`, which the call never wrote: with `rdi` primed by
  `syscall(21, &sentinel, 0)`, `syscall(22)` overwrote the sentinel (ach). arm64's twin stored
  through `x0 = 59` (SIGSEGV), and arm64 `syscall(35)` dereferenced `x0 = 35` in the nanosleep
  emulation. **Fixed here:** both backends now emit those emulations only at their arity
  (ESCPOPS records argc; `_msx_short`, `_esx_short`, and `EMACHO_NANOSLEEP_ARM` at argc 3), so a
  too-short call is SIGSYS (or -ENOSYS with SIGSYS ignored), and parse_expr warns at compile time.
- **x86-macOS `EMACHO_PROC_FIXUP`'s error guard.** Found while testing the row above: its `js`
  had no `test rax, rax` in front of it and read the sign of the preceding `cmp r11, 22`, which is
  zero on that path — so a FAILED pipe stored `-errno` and a stale `rdx` over the caller's fds and
  returned 0 (measured on ach: a -ENOSYS pipe came back 0 with `0x…FFFFFFB2` written). **Fixed
  here** (`test rax, rax`; the arm64 twin's `cmp x0, #0; b.lt` was already right).
- **`sys_getdents64` on both Macs.** Darwin's `getdirentries64` takes a fourth parameter, `off_t
  *basep`, and the shared 3-argument Linux wrapper left `r10` / `x3` stale: with it primed to
  `&sentinel`, a directory read zeroed the sentinel on ach AND ecb (and returned Darwin records
  under the `linux_dirent64` contract). **Fixed in 6.6.10 bite 3** (lane D): the wrapper declines
  with -78 on macOS.

**Fix.** `xor edx, edx` before the `syscall` in `EMACHO_CLOCK_X86` (+2 B per x86-macOS clock
site): mach time out-pointer = NULL. Fixpoint and `seed → cybs → cycc` hold. Using gettimeofday's
third argument as a MONOTONIC source for Intel-Mac (it is the only syscall-reachable mach time) is
a separate change and is not made here.

**Verified.** `tests/tcyr/crossos/darwin_clock_no_stray_write.tcyr` primes the third argument
register with `&sentinel` through a cyrius call, then reads the clock through `clock_now_ns()` and
through a raw `syscall(228, 4, &ts)` in the same function: 3 rows RED on ach with the 6.6.9
compiler (the sentinel reads back as mach time), green with the fix, and green on every other
target. `tests/tcyr/crossos/darwin_short_arity_sigsys.tcyr` covers the siblings fixed here:
the too-short calls die with SIGSYS 12 on ach and ecb (6.6.9: SIGSEGV 11 on ecb and on ach's
pipe), and with SIGSYS ignored return -78 and leave the rdi sentinel intact (6.6.9: the fds
stored over it). `tests/gates/platform/macho_clock_buffer_contract.sh` fails on the Linux host
if `EMACHO_CLOCK_X86` stops zeroing rdx before its syscall (mutation-proven), and
`darwin_syscall_literals_routed.sh`'s controls pin the compile-time warnings for 35 at argc 2 and
a pipe with no fds pointer on both Macs.

## CVE-52 — the lexer silently dropped any `@` that did not spell `@unsafe` (a CVE-31 residual)

*Appended 2026-09-28 (cyrius 6.6.10, bite 9), found by the 6.6.10 group-H triage. Not part of the
2026-09-03 sweep: recorded here because this is the live ledger. 6.6.10 bite 14 spends CVE-53.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — a narrow residual of P1 CVE-31 (`docs/audit/2026-06-10-deep-dive-review.md`): source bytes that change a program's meaning with no diagnostic, rc 0. Not a memory-safety defect in the compiler; the hazard is review-evasion — code that reads as one expression and compiles as another |
| **Affected** | every target: `src/frontend/lex.cyr`'s `@` arm, from v5.6.3 (when `@unsafe` landed) through cyrius 6.6.9 |
| **Fixed** | 6.6.10 |

**Vector.** The v5.6.3 `@unsafe` arm matched the seven bytes `@unsafe` and, for any other `@`,
ran `p = p + 1` — the byte vanished before tokenisation. CVE-31 (v6.1.35) made every OTHER
unmatched ASCII byte, and every non-ASCII byte, a hard error at the bottom of the lexer's
dispatch, but the `@` arm returned before control reached it.

**Impact.** Measured on 6.6.9: `return @@@;` and `return @;` compiled at rc 0 and returned 0;
`var y = 5 @- 3` was 2; `var z = @y` was 7; `var b = a @* 2` was 6; `@@unsafe {}` was accepted.
`$` in the same position was refused (`error:2: unexpected character (0x24)`). Because cycc
exited 0, everything that trusts its rc inherited the gap: `cyrius lint` printed `0 warnings`
over `return @@@;`, and two gates had gone vacuous on it —
`tests/gates/toolchain/cli_temp_dir_no_leak.sh` axis 3 ("a COMPILE ERROR is reported") passed
on a build that printed `OK (4448 bytes)`, and `tests/gates/diagnostics/dx_multi_error.sh`
case 2's "garbage must terminate" fixture only reached the parser because its `@@@` was eaten.
An ecosystem scan (24,717 `.cyr`/`.tcyr`/`.bcyr`/`.fcyr`/`.scyr`/`.smcyr` files under `~/Repos`,
strings and comments stripped) found **0** stray `@`, so nothing valid depended on the skip.

**Fix.** One shared reject, `_lex_stray(S, p, c)`, now serves all three routes — the `@` arm,
the non-ASCII arm and the CVE-31 stray-ASCII arm — so `@` cannot be the one byte that skips it
again. It prints `error:<file>:<line>:<col>: unexpected character (0x40)` and exits 1. The same
release moves every lexer error site onto one location head (`_lex_err_head`): they printed the
raw EXPANDED line with no file and no column. `@unsafe` is unchanged. Fixpoint and
`seed → cybs → cycc` hold.

**Verified.** `tests/gates/frontend/lexer_errors_name_file_line.sh` axis 1 refuses `@@@`, `@`,
`@-`, `@y`, `@*`, `@@unsafe` and a trailing `@` by file:line:col (all compile at rc 0 on 6.6.9);
axis 2 keeps `@unsafe` compiling and running. `lint_reports_unparseable.sh` axis 4 gains two
stray-`@` shapes (6.6.9: `0 warnings`, rc 0). The two vacuous gates are repaired:
`cli_temp_dir_no_leak.sh` axis 3 now requires rc != 0 and the compiler's own diagnostic (RED on
6.6.9), and `dx_multi_error.sh` case 2 drops `@@@` and proves its diagnostic comes from the
parser, not the lexer.

## CVE-54 — on Windows, `net_resolve_ipv4` read a DRIVE-RELATIVE `/etc/hosts` any local user can plant

*Appended 2026-09-29 (cyrius 6.6.11, bite B07 item I5), found by the 6.6.9 review finds (group I).
Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.11 also spends
CVE-55.*

| | |
|---|---|
| **Severity** | **High (P1)** — a local, unprivileged user redirects every other user's name lookups on the same Windows machine; with 6.6.11's working sockets it also chooses their nameserver |
| **Affected** | PE (Windows) programs that call `net_resolve_ipv4` or `_net_dns_id` (`lib/net.cyr`) — the hosts step worked on PE through `file_open` in released cyrius through 6.6.10 (confirmed on cass) |
| **Fixed** | 6.6.11 |

**Vector.** `net_resolve_ipv4` read `"/etc/hosts"` and `"/etc/resolv.conf"` on every target. On
Windows a rooted path is DRIVE-RELATIVE, so `"/etc/hosts"` is `C:\etc\hosts` — and any
authenticated user may create a folder at the root of the system drive. With no resolv.conf the
lookup fell back to `127.0.0.1:53`, and port 53 is not privileged on Windows, so once sockets work
(6.6.11 item I4) the nameserver was whoever bound it first. `_net_dns_id`'s `/dev/urandom` fallback
for the DNS transaction id had the same shape (`C:\dev\urandom`).

**Impact.** One local user plants `C:\etc\hosts` and every other user's cyrius program on that
machine resolves the planted names to the planter's addresses. Confirmed on cass (real Windows)
against released 6.6.10: a PE program's `net_resolve_ipv4` honoured a planted `C:\etc\hosts`.

**Fix.** After the literal and `*.localhost` steps the Windows arm is `_net_resolve_win` —
`getaddrinfo`, the system resolver (the real `%SystemRoot%\System32\drivers\etc\hosts` and the
adapters' DNS), walking `AF_INET` results and freeing them. Refused before any lookup: a byte that
is not printable ASCII (`getaddrinfo` reads an ANSI code-page string), and a name the resolver
would read as an ADDRESS although `net_parse_ipv4` refused it (`010.0.0.1`, `127.1`,
`0x7f000001` — probed with `AI_NUMERICHOST`). The POSIX steps and the `/dev/urandom` fallback are
compiled out on Windows.

**Verified.** `tests/tcyr/crossos/net_resolve_pe.tcyr` plants `C:\etc\hosts` and asserts it is
ignored. Wine maps a rooted path to the unix root, so only real Windows shows the plant; there
(wine is told apart by ntdll's `wine_get_version` export) the plant itself is asserted, so a
pre-existing file or a failed write fails a named row instead of passing vacuously. Mutation,
measured on cass: with the POSIX steps restored the planted `10.9.8.7` came back.

## CVE-55 — a multi-line string literal shifted file attribution, so a call to another file's `private` fn COMPILED

*Appended 2026-09-29 (cyrius 6.6.11, bite B05 item N1), found by the 6.6.10 review finds (group N).
Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. The same impact
as CVE-45 (a forged `#@file` defeating `private`) through a different vector.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — a compile-time visibility bypass, not a memory-safety defect: code that the language says cannot call a `private` fn compiles and calls it |
| **Affected** | every target: `src/frontend/lex.cyr`'s string loop, from the v6.5.0 visibility work (`private` enforced through the file map) through cyrius 6.6.10 |
| **Fixed** | 6.6.11 |

**Vector.** LEX's string loop stored a raw LF (and a `\<LF>`) without bumping the line counter, so
after any multi-line string every later token was lexed one line HIGH per newline. `FM_FILEID`
maps a token to its file by that line, so the tokens after a multi-line string near an `include`
boundary were attributed to the WRONG FILE — and `private` is enforced through the file map.

**Impact.** A file that included another file's `private` fn could call it once a multi-line
string sat ahead of the call: the call was attributed to the defining file, and it compiled. The
same miscount put every later diagnostic on the wrong line (an undefined name on line 5 reported
line 3), and line 1 of the next `include` landed on its `#@file` marker line and printed a bare
`error:4:12:` with no file name. The "diagnostics in `backend/x86/fixup.cyr` are one line high"
report (N3) was this defect.

**Fix.** Both the raw-LF and the `\<LF>` paths bump the line counter; the string token keeps its
opening line, matching the column its diagnostic head prints. The `#@file` bookkeeping was correct
and is untouched. Fixpoint and `seed → cybs → cycc` hold.

**Verified.** `tests/gates/frontend/lexer_errors_name_file_line.sh` axis 6 pins, after a
multi-line string, the diagnostic's line, the include's file name, and the `private` refusal of a
cross-file call (which compiled on 6.6.10). Axis 4 pins the escape rules that landed with it.

## CVE-56 — `lib/log.cyr`'s `log_info_kv` / `log_info_int` built a log line past a 512-byte stack buffer

*Appended 2026-09-30 (cyrius 6.6.12, bite B10 item S-B2), found in passing by the 6.6.11 lanes and
promoted from the backlog by the user. Not part of the 2026-09-03 sweep: recorded here because this is
the live ledger. 6.6.12 also spends CVE-57 and CVE-58.*

| | |
|---|---|
| **Severity** | **High (P1)** — a stack buffer overflow reachable from any string a program logs; the same class as CVE-50 |
| **Affected** | every target: `lib/log.cyr` `log_info_kv(msg, key, val)` and `log_info_int(msg, key, val)` from their introduction (v3.4.9, 2026-04-11) through cyrius 6.6.11, and every consumer that includes `lib/log.cyr` (vendored copies too) until it re-vendors 6.6.12 |
| **Fixed** | 6.6.12 |

**Vector.** Both functions assemble the line `msg key=val` in a `var buf[512]` stack buffer by
copying `strlen(msg) + strlen(key) + strlen(val)` bytes with no bound. A program that logs a string
an attacker influences — a request header, a path, a query value — through either function (as
`val`, `key` or `msg`; `log_info_int` as `msg` or `key`) overruns the buffer as soon as the fields
together exceed 511 bytes.

**Impact.** The copy overwrites the function's own locals and its return address. A 4 KB value
crashes the process with SIGSEGV (rc 139) before the sink is reached — a remote denial of service at
minimum, and with attacker-chosen bytes a potential control-flow hijack.

**Fix.** Every copy goes through one bounded helper, `_log_cat(buf, off, s, lim)`, with `lim = 511`;
a line that is cut ends in `...`. `log_info_int` reserves 22 bytes for `=`, the sign and 19 digits,
so the number itself is never cut.

**Verified.** `tests/tcyr/stdlib/log_kv_bounded.tcyr`: a 4 KB value, msg and key each return rc 0
with the sink seeing exactly 511 bytes, the head intact and the `...` mark; the 511/512 boundary;
and `i64::MIN` surviving a 4 KB msg. It passes on x86_64 and qemu-aarch64 and exits 139 against the
6.6.11 `lib/log.cyr`.

## CVE-57 — on Windows, the folded sandhi resolver read a DRIVE-RELATIVE `/etc/resolv.conf` any local user can plant

*Appended 2026-09-30 (cyrius 6.6.12, bite B15 item SA11). This is the CVE-54 class, reached
through a fold instead of `lib/net.cyr`: the vulnerable code is sandhi's own resolver, shipped in
cyrius as `lib/sandhi.cyr`.*

| | |
|---|---|
| **Severity** | **High (P1)**. A local, unprivileged user chooses the DNS server for every other user's sandhi lookups on the same Windows machine, including `sandhi_http_get` by hostname. |
| **Affected** | PE (Windows) programs that resolve through the folded sandhi: `sandhi_resolve_ipv4[_a]` / `sandhi_resolve_ipv6[_a]`, and every `sandhi_http_*` / discovery / rpc call given a hostname with no `sandhi_client_set_resolver` hook installed. `lib/sandhi.cyr` has built for PE since 6.6.7 (sandhi 1.10.1), and the file read ran there from then on. The query reached the planted server once 6.6.11 gave PE working Winsock UDP. **Exploitable in released cyrius 6.6.11** (fold sandhi 1.10.3), confirmed on cass. |
| **Fixed** | 6.6.12 (sandhi 1.10.4, commit `88115b3`, re-vendored byte-identical) |

**Vector.** `_sandhi_resolve_read_resolv_conf_a` (sandhi `src/net/resolve.cyr`) opened
`"/etc/resolv.conf"` on every target, and both lookups (`_sandhi_resolve_ipv4_query_a` /
`_sandhi_resolve_ipv6_query_a`) fell back to 8.8.8.8 without one. On Windows a rooted path is
drive-relative, so the reader opened `C:\etc\resolv.conf`, and any authenticated user may create a
folder at the root of the system drive. `net_resolve_ipv4`'s own fix at 6.6.11 (CVE-54) did not
cover this: sandhi has its own resolver and does not call `net_resolve_ipv4`.

**Impact.** One local user plants `C:\etc\resolv.conf` with `nameserver <their address>`, and every
other user's sandhi-based program on that machine sends its DNS queries there and trusts the
answers (a matching TXID is all it checks). That redirects `sandhi_http_*` traffic by hostname.
When no file exists, the 8.8.8.8 fallback bypasses the machine's configured resolver and its hosts
file. Confirmed on cass (real Windows) against the 6.6.11 fold (sandhi 1.10.3), with a planted
`nameserver 127.0.9.7`:
- the reader returned the planted address (118030463 = 127.0.9.7);
- the lookups of the machine's own name and of `localhost` were sent to the planted server, which
  answered nothing, so both failed (5 of 15 rows of the new test fail).

**Fix (at the source, sandhi 1.10.4).** On `CYRIUS_TARGET_WIN`:
- the A lookup is `net_resolve_ipv4(host)`, i.e. getaddrinfo, which reads the real
  `%SystemRoot%\System32\drivers\etc\hosts` and the adapters' DNS;
- the AAAA lookup answers 0, so the client stays on v4, the only family the PE socket surface can dial;
- the reader returns -1 without opening anything;
- 8.8.8.8 is never used.

The consumer resolve hook still runs first. The v6 connect paths keep declining on PE, with a
corrected comment: dialling v6 needs a public AF_INET6 socket in `lib/net.cyr`, which is a feature.
sandhi's CI gained a structural row that keeps every `"/etc/"` literal and 8.8.8.8 fallback in
`src/` inside `#ifndef CYRIUS_TARGET_WIN`. It names all three 1.10.3 sites.

**Verified.** `tests/tcyr/crossos/sandhi_pe_resolver_no_etc_path.tcyr` runs on cass in the release
gate's cross-OS leg. On real Windows it plants `C:\etc\resolv.conf` and asserts the plant, so a
pre-existing file or a failed write fails a named row. It then asserts:
- the reader returns -1;
- the machine's own name resolves through the system resolver, to the address `net_resolve_ipv4` gives;
- the AAAA lookup answers 0, and `localhost` and a `.invalid` name behave.

Measured results:
- **cass:** 15/15 with the 1.10.4 fold, and 5 of 15 fail with the 1.10.3 fold. The plant was removed
  and `C:\etc` does not exist afterwards.
- **wine:** 13/13 with the fix. The 1.10.3 fold fails 3 of 13, because its reader returned the
  Linux host's 127.0.0.53: wine maps a rooted path to the unix root, so only real Windows shows
  the plant.
- **Other targets:** the every-target rows pass on x86_64, aarch64 (qemu), ecb, ach and the
  agnosticos container.

## CVE-58 — cxvm let guest bytecode read and write the interpreter's own host memory

*Appended 2026-09-30 (cyrius 6.6.12, bite B06 item Q6). Not part of the 2026-09-03 sweep: recorded
here because this is the live ledger.*

| | |
|---|---|
| **Severity** | **High (P1)** — guest bytecode corrupts the interpreter process that runs it. cxvm is documented as *not a sandbox* for syscalls, but ordinary buggy programs (a deep recursion, a stray pointer, a `read()` into a too-short buffer) silently corrupted cxvm's own heap and exited with garbage codes |
| **Affected** | `programs/cxvm.cyr`, every version through cyrius 6.6.11, on every host cxvm runs on (x86_64 and aarch64 Linux, macOS arm64 and x86_64, Windows) |
| **Fixed** | 6.6.12 |

**Vector.** A `.cyx` whose guest code:
- loads or stores at an address at or past the 1 MB guest memory (less the access width), or at a
  negative address;
- stores to guest addresses 0–7, which silently succeeded because guest 0 is the bytecode copy;
- nests more than 512 calls, which overran the 1024-entry call stack into the next host allocation
  (the loaded code), or pushes more than 1024 data-stack entries;
- passes `read` / `write` / `getrandom` / `clock_gettime` a buffer that ends past 1 MB, so the HOST
  kernel wrote cxvm's heap through the translated pointer;
- jumps to a negative pc, so host memory was decoded as code.
An unknown opcode was also a silent no-op, so an older cxvm ran a newer compiler's opcodes as identity.

**Impact.** Silent corruption of cxvm's register file, stacks, loaded code and heap, and wrong exit
codes: before the fix a non-tail recursion of depth 1000 exited 231 and depth 5000 exited 135, and
`store64(0, 5)` exited 9 where the same program SIGSEGVs natively.

**Fix.** Every load and store is bounds-checked at its full width against `[8, 1 MB)`; translated
syscall buffers are range-checked and answer `-EFAULT`; the data and call stacks trap on overflow and
underflow and grow to 65536 entries, so the guest's own 1 MB is the binding limit; `sub sp` traps
before the guest stack reaches the loaded image (without it a runaway recursion overwrote the
program's globals and heap before any other trap fired); a negative pc and an unknown opcode trap.
Each trap prints `cxvm: <what> <value> at pc <N>` and exits 1. There is no `.cyx` format bump. The
same bite gives cx real tail calls (`mov sp, fp; popc fp; jmp f`), so a 2,000,000-deep tail
recursion runs in constant stack. The pass-through of every other syscall number is unchanged:
cxvm is still not a sandbox (`docs/platform-status.md`, "cyrius-x guest contract").

**Verified.** `tests/gates/codegen/cx_tailcall_and_vm_traps.sh` (24 rows, every trap
mutation-proven); its 23 cxvm cases run 23/23 on real pi, ecb, ach and cass (a cxvm cross-built per
host) and under qemu-aarch64 and wine.

## CVE-59 — the libssl TLS backend never bound the server's certificate to the host: any chain-valid certificate verified any host

*Appended 2026-10-01 (cyrius 6.6.13, bite I1). Found by: abaco 2.4.9 TLS study (2026-09-30); issue `docs/development/issues/archived/2026-09-30-tls-libssl-backend-no-hostname-verification.md`. The CN-only / partial-wildcard / IP / NULL-host widening was found by the 6.6.13 I1 premise check. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.13 spends CVE-59 … CVE-63.*

| | |
|---|---|
| **Severity** | P1 (High) — man-in-the-middle, silent (the handshake reports success). Anyone holding a certificate that chains to a trusted root — any public-CA certificate for any domain they control — impersonates every server a libssl-backed client talks to. The libssl twin of CVE-18 (native, v6.1.36). |
| **Class** | Identity verification (RFC 9525 §6.3 / RFC 6125 §6): chain checked, reference identity never compared. |
| **Affected** | The libssl client path of `tls_connect`, `tls_connect_with_ctx_hook` and `tls_connect_alloc`/`tls_connect_complete`, in every `-D CYRIUS_TLS_LIBSSL` build (hoosh's remote HTTPS uses one) and in a default build after `tls_set_backend(TLS_BACKEND_LIBSSL)`; from the libssl wrapper's introduction (4.9.3, 2026-04-15) through 6.6.12. The native backend is not affected (CVE-18). |
| **Files** | `lib/tls.cyr` — `tls_connect_alloc` (set `SSL_VERIFY_PEER` + SNI only), `_tls_init` (resolved no binding symbol); fixed by the new `_tls_libssl_bind_host` and the shared classifier `lib/tls_hostid.cyr` |
| **Fixed** | 6.6.13 |

**Vector.** A server (or on-path attacker) presents a leaf that chains to a root the client trusts but names a different host: `DNS:localhost` verified `www.example.com`, `127.0.0.1` and `host == 0`; a CN-only leaf (no SAN) and a partial wildcard (`DNS:f*.example.com` for `foo.example.com`) verified too, as did an IP host against a dNSName-only leaf. Measured against OpenSSL 3.6.5 `s_server`.

**Impact.** Full impersonation of any TLS server to a libssl-backed cyrius client: confidentiality and integrity of the session lost.

**Fix.** `tls_connect_alloc` calls `_tls_libssl_bind_host(ssl, host)` after the hook and `SSL_new`. The host is classified by the native stack's own code (`_tn_parse_ip_literal`, moved unchanged from `lib/tls_native_conn.cyr` into `lib/tls_hostid.cyr`, included by both `lib/tls.cyr` and `lib/tls_native.cyr`). An IP literal → `X509_VERIFY_PARAM_set1_ip_asc` (iPAddress SANs only), no SNI. A DNS name → hostflags `X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS | X509_CHECK_FLAG_NEVER_CHECK_SUBJECT`, `X509_VERIFY_PARAM_set1_host` (dNSName SANs only), SNI. Host 0 / `""` / a `:`-bearing non-literal → `tls_connect_alloc` returns 0 under `SSL_VERIFY_PEER`; after a hook's `tls_set_verify(h, 0, 0)` nothing is bound (parity with native's `TLS_VERIFY_NONE`). `SSL_set1_host` deliberately not used (OpenSSL ≥ 3.0 re-parses the name as an IP with its own parser — the libssl version would decide the classification). The five symbols (`SSL_get0_param`, `SSL_get_verify_mode`, `X509_VERIFY_PARAM_set1_host`, `X509_VERIFY_PARAM_set_hostflags`, `X509_VERIFY_PARAM_set1_ip_asc`) are REQUIRED in `_tls_init`'s bail list: one missing → `tls_available()` 0 and every libssl connect returns 0 (fail closed). `docs/development/lib-tls-contract.md` gains a "Server identity" section. No public API change.

**Behaviour change.** libssl only: `host == 0` under `SSL_VERIFY_PEER` now fails (it always did on native); CN-only and partial-wildcard certificates are refused; no SNI for an IP-literal host. Ecosystem survey (hoosh, sandhi, abaco, chakshu): no caller passes `host == 0` or relies on a CN fallback.

**Verified.** Filed repro `docs/development/issues/repros/2026-09-30-tls-libssl-no-hostname-verification.sh` exits 0 under both builds (2 on 6.6.12; re-measured 2 → 0 with the pre-fix and fixed lib in one harness). `tests/gates/platform/tls_libssl_hostname_binding.sh` (registered in `programs/checks/main.cyr`): 24 rows × native / libssl-via-`tls_set_backend` / `CYRIUS_TLS_LIBSSL` build against OpenSSL `s_server`, 5 SNI rows (`-servername_fatal`), 4 hook-pin rows × 2 builds (a name / IP a hook pinned on the `SSL_CTX` param is replaced by `host` when of the same kind, kept when of the other kind — documented in the contract), 5 bogus-symbol fail-closed legs; 95 rows pass, 42 RED against the pre-fix lib; mutation-proven five ways (bind call deleted, hostflags dropped, a bail line removed, SSL_set1_host-style routing, SNI for every host).

**Not covered.** The native client still sends an IP literal as SNI (backlog (d)). Native accepts a wildcard directly over a single label (`*.com` for `a.com`) where libssl refuses — a remaining divergence, reported for the backlog. The libssl backend cannot be exercised off x86_64 Linux (no libssl.so.3 on macOS/Windows, no dlopen-helper on pi).

## CVE-60 — the libssl TLS backend's `tls_read` / `tls_write` returned a C `int` zero-extended: a tampered record read as ~4 GiB read, and a fatal alert or a truncated stream read as a clean end of stream

*Appended 2026-10-01 (cyrius 6.6.13, bite I2c). Found by: The 6.6.13 I2 (c) premise check (measuring how libssl reports alerts for issue `2026-09-30-tls-client-memory-and-alert-gaps` (c)). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.13 spends CVE-59 … CVE-63.*

| | |
|---|---|
| **Severity** | P1 (High) — an on-path attacker with no key turns a libssl-backed client's read into a reported 4,294,967,295-byte success. A consumer that does `total = total + n` (abaco `ai.cyr:1976`, whirl `transport.cyr:69`, sandhi `conn.cyr:935`) then indexes and parses past its buffer: an out-of-bounds read or write. The 0 half (alert / truncation read as EOF) is a truncation-acceptance vector for any length-less body. |
| **Class** | Integer sign / width (CWE-194, unexpected sign extension — here its absence) feeding an out-of-bounds access; error-as-EOF (CWE-754). |
| **Affected** | Every `-D CYRIUS_TLS_LIBSSL` build and every default build after `tls_set_backend(TLS_BACKEND_LIBSSL)`, on `tls_read` and `tls_write`, from the libssl wrapper's introduction (4.9.3) through 6.6.12. x86_64 Linux only in practice (the fdlopen bridge). The native backend is not affected by the sign defect. |
| **Files** | `lib/tls.cyr` — `tls_read` and `tls_write`, libssl branch (`return fncall3(_fn_SSL_read / _fn_SSL_write, …)`); fixed by the new `_tls_ssl_io_ret`, `ERR_peek_last_error` / `ERR_clear_error` (optional symbols in `_tls_init`) and a `#ifdef CYRIUS_TLS_LIBSSL` `TLS_ERR_*` block |
| **Fixed** | 6.6.13 |

**Vector.** (1) Flip one bit of any application-data record on the wire: `SSL_read` returns -1, which `fncall3` hands back with its high 32 bits clear — `tls_read` returned **+4294967295** (measured, OpenSSL 3.6.5; also for a non-blocking read with nothing pending, and for `tls_write` to a closed peer or after a fatal alert). (2) Send a sealed fatal alert, or cut the stream mid-record and FIN: `SSL_read` returns 0, which `tls_read` passed through as a clean end of stream.

**Impact.** (1) Memory corruption / out-of-bounds read in the consumer, from an unauthenticated network position. (2) A truncated or attacked response accepted as complete.

**Fix.** `_tls_ssl_io_ret(ssl, r)` masks the return to its 32 bits and sign-extends it (no `>>`: logical in cyrius), returns `r > 0` unchanged, and otherwise maps `SSL_get_error`: `ZERO_RETURN` with `r == 0` → 0 (close_notify); `ZERO_RETURN` with `r < 0` → `TLS_ERR_PROTOCOL`; `WANT_READ` / `WANT_WRITE` → `TLS_ERR_WOULD_BLOCK`; `SYSCALL` → `TLS_ERR_IO`; `SSL_ERROR_SSL` → `TLS_ERR_ALERT` when the last queued error is lib SSL with reason 1000..1255 (a received alert), `TLS_ERR_IO` for reason 294 (unexpected EOF), else `TLS_ERR_PROTOCOL`; anything else, or no `SSL_get_error`, → `TLS_ERR_IO` (never 0). `ERR_clear_error` runs before every `SSL_read` / `SSL_write` so a stale queued error cannot decide the answer. `tls_write` returns 0 for a 0-byte write without calling libssl and never returns 0 for a failed one. In a libssl-only build `lib/tls.cyr` defines the four `TLS_ERR_*` it returns (same values as `lib/tls_native.cyr`). No public API change; return values change (see below). The introspection sibling `tls_get_peer_spki_der` read `i2d_PUBKEY`'s C `int` the same way (a failed second call returned 4294967295 as the SPKI length); both of its calls are sign-extended too, and a written length is bounded by `bufmax`.

**Behaviour change.** libssl `tls_read` / `tls_write`: negatives are `TLS_ERR_*` (`-9` / `-12` / `-17` / `-19`) instead of a raw or zero-extended int; a received fatal alert is `TLS_ERR_ALERT` instead of 0; EOF without close_notify is `TLS_ERR_IO` instead of 0. Every surveyed consumer already treats `< 0` as an error and 0 as EOF (sandhi `conn.cyr:935`, `server/mod.cyr:2448`; whirl `transport.cyr:69`; abaco `ai.cyr:1976`); none compares `== -1` (grep of ~/Repos).

**Verified.** `tests/tcyr/crypto/tls_libssl_read_errors.tcyr` (40 assertions; a libssl client against a forked native server, TLS 1.3 and 1.2; named SKIP without libssl.so.3 / the dlopen-helper): WOULD_BLOCK on a non-blocking empty read (was 4294967295), a sealed fatal alert → `TLS_ERR_ALERT` (was 0), close_notify → 0 and still 0 with a record behind it, a bit-flipped record → `TLS_ERR_PROTOCOL` and never > maxlen (was 4294967295), a record cut short + FIN → `TLS_ERR_IO` (was 0), FIN alone → `TLS_ERR_IO` (was 0), `tls_write` after a fatal alert → `TLS_ERR_PROTOCOL` and to a closed peer → `TLS_ERR_IO` (both were 4294967295); a stale libcrypto error that reads as a received alert is planted before the reads and writes (anti-vacuous). 18 of the 40 fail against the pre-fix lib. Mutants, each RED: no sign extension, the raw read, the raw write, no `ERR_clear_error` before the read / before the write, the alert-reason row, the unexpected-EOF row, `WANT_READ` → IO, `SYSCALL` → PROTOCOL, and `ZERO_RETURN` always 0 together with the `tls_write` 0-guard. The 32-bit mask is ABI hygiene (the upper half of an `int` return is unspecified) and cannot be exercised on x86_64 / aarch64, where 32-bit writes zero-extend. `tests/tcyr/crypto/tls_libssl_spki_int_return.tcyr` stubs the introspection entry points: a -1 from `i2d_PUBKEY` returns 0 (4294967295 before the fix), on x86_64 and qemu-aarch64.

**Not covered.** After a fatal alert, a SECOND libssl `tls_read` returns 0: OpenSSL reports `SSL_ERROR_ZERO_RETURN` once `SSL_RECEIVED_SHUTDOWN` is set, because `warn_alert` stays 0 (= close_notify) for a fatal alert. The first read reports `TLS_ERR_ALERT` and the record behind the alert is never delivered; native re-reads stay `TLS_ERR_ALERT`. Making libssl sticky needs a shim slot (I8 plans +24 of the libssl shim for its deadline) — reported for the backlog. libssl's SIGPIPE exposure on a write to a closed peer is backlog (f); the test ignores SIGPIPE.

## CVE-61 — the native TLS stack skipped plaintext ChangeCipherSpec records without limit and had no deadline: anyone on the path held a client (or server) thread for ever, with no key

*Appended 2026-10-01 (cyrius 6.6.13, bite I8). Found by: The abaco 2.4.12 HTTPS review (2026-10-01). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.13 spends CVE-59 … CVE-63.*

| | |
|---|---|
| **Severity** | P2 (Medium) — availability. An on-path attacker with no key and no certificate pins a native-TLS thread indefinitely: one plaintext CCS record more often than the read timeout, during the handshake or inside an already-verified session; or, from the peer, one byte at a time just inside the timeout inside a single record. Same class as CVE-30 (the unbounded post-handshake record drain). It also broke RFC 8446 §5's MUST (a CCS outside the window ends the connection with `unexpected_message`). |
| **Class** | Uncontrolled resource consumption / missing timeout (CWE-400, CWE-1088); improper protocol-state enforcement (CWE-841). |
| **Affected** | Every native-TLS client and server (the default `lib/tls.cyr` backend since 6.1.21, and every direct `tls_native_*` user — abaco, sit and whirl in the ecosystem survey), on every target, from the native stack's CCS skip (6.0.23, OpenSSL middlebox interop) through 6.6.12. The libssl backend never skipped CCS but likewise had no caller deadline (blocking `SSL_*` on the caller's socket). Windows: native TLS does not run over Winsock sockets at all (backlog j), so it was not reachable there. |
| **Files** | `lib/tls_native_conn.cyr` — `_tn_sock_read_record_skip_ccs` (deleted), `_tn_sock_read_full` / `_tn_sock_write_all` (now ctx == 0 forms of `_tn_io_read_full` / `_tn_io_write_all`), `tls_native_connect`, `tls_native_accept`, `tls_native_read`, `tls_native_write`, `tls_native_close`; `lib/tls_native_hs12.cyr` (`tls_native_connect_12`, `_tn_12_server_drive`, `tls_native_accept_12`); `lib/tls_native_hs13.cyr` (`tls_native_client_recv_flight`, `_tn_send_key_update`); `lib/tls.cyr` (the libssl shim's `SSL_*` calls); `lib/tls_native_ctx.cyr`, `lib/tls_native.cyr` (new fields / codes) |
| **Fixed** | 6.6.13 |

**Vector.** (1) Inject a 6-byte CCS record (`14 03 03 00 01 01`) into the stream more often than the client's read timeout — before the ServerHello, or at any time after the handshake: every read dropped it and read again (measured with the filed repro: both clients still blocked at 10 s under a 2 s `SO_RCVTIMEO`). (2) As the peer, announce a record of up to 16,640 bytes and send one byte just inside the read timeout: `_tn_sock_read_full` looped with no clock (a 16 KB record at one byte per 9 s: ~40 h). (3) The caller had no way to bound either: the transport vtable is process-global.

**Impact.** Denial of service: a client or server thread held for ever; for a per-request worker pool, exhaustion. No confidentiality or integrity impact (CCS carries no data; the record layer stays authenticated).

**Fix.** **(a)** `_tn_read_rec(ctx, fd, buf, cap, policy)` replaces the skip at all 13 record-read sites, each with an explicit policy — `_TN_CCS_MAY` (TLS 1.3: one CCS per connection, before the peer's Finished, dropped; ctx `TLS_CTX_OFF_CCS_STATE` bit 0), `_TN_CCS_MUST` (TLS 1.2: exactly one, directly before the peer's Finished), `_TN_CCS_REFUSE` (before a ClientHello, the 1.2 server flight / ClientKeyExchange, and every read after the handshake). A CCS must be exactly the byte 1. A violation fails the ctx with `TLS_ERR_PROTOCOL` after a best-effort fatal `unexpected_message` alert (plaintext while our writes are; else sealed under our current write keys — in TLS 1.3 the application keys, or before them our handshake-traffic keys (the client from its ServerHello to its own Finished); in TLS 1.2 our keys after our own CCS, bit 1). **(b)** a per-connection deadline: `tls_native_set_deadline(ctx, abs_ns)` / `tls_set_deadline(ctx, abs_ns)` (`clock_now_ns()` scale, 0 = none; `TLS_ERR_TIMEOUT` = -20). Linux/macOS: `fd_wait_ready` with the time left before each read (every byte costs a clock check); writes non-blocking for the call with an EAGAIN (11 / Darwin 35) wait, flags restored on every exit. agnos: `_agnos_sock_recv_block` / `_agnos_sock_send_dl(rearm 0)` with the time left. Custom transport / Windows: checked between calls. libssl: the shim keeps the deadline (+24, 24 → 32 B) and drives the `SSL_*` calls non-blocking from `SSL_get_error` WANT_READ / WANT_WRITE. No deadline set = no change, no clock read. **(c)** the reader passes `TLS_ERR_IO` / `TLS_ERR_TIMEOUT` through and answers a header past the ciphertext ceiling with `TLS_ERR_BAD_RECORD`; write sites pass their code through.

**Behaviour change.** A TLS 1.3 peer sending two CCS, or a 1.2 peer omitting its CCS before Finished, now fails (`TLS_ERR_PROTOCOL`) where it used to pass; RFC-conformant stacks send exactly one (verified against OpenSSL `s_server -tls1_3` / `-tls1_2` and `s_client`). After `TLS_ERR_TIMEOUT` the native ctx is failed (a record may be half read). A plaintext alert in place of the 1.2 peer's CCS reads as `TLS_ERR_ALERT` (was `TLS_ERR_BAD_RECORD`). New public API: `tls_native_set_deadline`, `tls_set_deadline`, `TLS_ERR_TIMEOUT`.

**Verified.** `tests/tcyr/crossos/tls_native_deadline_ccs.tcyr` (39 assertions, single-threaded, preloaded loopback pairs; x86_64, qemu-aarch64, pi, ecb, ach 39/39; cass 8/8 with the socket rows SKIPped by name, backlog j). `tests/tcyr/crypto/tls_native_ccs_deadline.tcyr` (108 assertions, socketpair + fork with transport write hooks; the filed repro's two cases by code, every read site's policy, 1.3 and 1.2 both directions, mTLS sites, drips under `SO_RCVTIMEO`, write deadline, both shim backends, OpenSSL `s_server` 1.3 / 1.2; 45 of 108 fail on the pre-fix lib). `tests/gates/platform/agnos_tls_deadline.sh` (fake-kernel agnos read / write paths). 34 + 5 mutants, each RED. The filed repro `docs/development/issues/repros/2026-10-01-tls-native-no-deadline.sh` exits 0 unmodified (was 2): case 1's client returns 4 (handshake refused at the second CCS), case 2's returns 5 (`tls_read` → `TLS_ERR_PROTOCOL`), each well inside 10 s.

**Not covered.** Windows: native TLS over `net.cyr` sockets (the transport leaves are `ReadFile` / `WriteFile`, which return 0 on Winsock) — backlog j; the deadline there is checked between calls. A custom transport is bounded only between its calls (documented on `tls_native_set_transport`). On agnos a write can overshoot the deadline by one `sock_send#48` stall (~8 s). Writing the fatal alert to a peer that already reset the connection can raise SIGPIPE in a process that does not ignore it — the same exposure every native TLS write (`tls_native_write`, `tls_native_close`'s close_notify, the handshake's own writes) already has.

## CVE-62 — a `[deps.NAME]` header was used as a path unchecked: `cyrius deps` created directories and git-cloned outside the dep cache (a CVE-32 residual)

*Appended 2026-10-01 (cyrius 6.6.13, bite I10d). Found by: the 6.6.13 I10 premise check (in passing, measuring the modules-less default that derives `dist/<name>.cyr` from the same name). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.13 spends CVE-59 … CVE-63.*

| | |
|---|---|
| **Severity** | P1 (High) — arbitrary-path directory creation + `git clone` driven by any manifest in the dep graph, including a transitive dependency's. Not P0: the write is a git checkout of a URL the same manifest names (no arbitrary bytes into an arbitrary existing file), and the `lib/` copy guard (CVE-04) still refuses the vendoring step. |
| **Class** | Path traversal (a CVE-32 residual — the v6.2.51 dep-resolver traversal hardening, `_dep_reject_unsafe_name`, covered sub-module / index-leaf / package names but not the `[deps.NAME]` header) |
| **Affected** | every cyrius with named git deps up to and including 6.6.12 |
| **Files** | `cbt/deps.cyr` — `_process_named_deps` (name extraction, then the clone-dir build `<home>/deps/<name>/<tag>` + `sys_mkdir` + `git clone`) |
| **Fixed** | 6.6.13 |

**Vector.** A `cyrius.cyml` — the consumer's own, or the manifest of ANY transitive dependency, which `cyrius deps` / `cyrius build` (auto-deps) read in the Phase 3 BFS — declaring `[deps.../../<anything>]` with `git`, `tag` and `modules`.

**Impact.** `cyrius deps` runs `mkdir <home>/deps/../../<anything>` and `git clone <url> <home>/deps/../../<anything>/<tag>`, i.e. creates directories and writes a full checkout at an attacker-chosen location relative to `$CYRIUS_HOME` (default `~/.cyrius`, so `../../x` lands in the user's home directory's parent tree) with the user's privileges. Measured on 6.6.12: `[deps.../../esc/x]` cloned into `<home>/../esc/x/2.0.0`; only the subsequent `lib/../../esc/x_foo.cyr` destination guard ("path traversal in dep destination") stopped the copy — after the clone had been written. With no `$CYRIUS_HOME` the same name escapes the per-run temp dir.

**Fix.** `_dep_reject_unsafe_name(dep_name)` runs immediately after the header name is read, before the closest-wins lookup, the clone, or any path derivation; a refused section prints `error: [deps.<name>] is not a usable dep name …`, counts as an error (exit 1, no lock write) and is skipped. Applies to the root manifest and every transitive manifest (same function).

**Verified.** `tests/gates/toolchain/deps_modules_default_or_warned.sh` axis D8: root `[deps.../x]` and a TRANSITIVE dep whose manifest declares `[deps.../../esc/x]` — both refused by name, exit 1, nothing created outside `$CYRIUS_HOME/deps` (filesystem check of the escape target).

## CVE-63 — the native TLS client verified an IP-literal host against dNSName SAN entries, wildcards included

*Appended 2026-10-01 (cyrius 6.6.13, bite I7). Found by: abaco 2.4.12 HTTPS review (2026-10-01); issue `docs/development/issues/archived/2026-10-01-tls-ip-literal-dnsname.md`. The IPv6 parser defects were found by the 6.6.13 I7 premise check. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.13 spends CVE-59 … CVE-63.*

| | |
|---|---|
| **Severity** | P3 (Low) — certificate identity-verification flaw. Exploitation needs a CA the client trusts to issue a dNSName that spells an IP address (or a wildcard over one), which the CA/Browser Forum Baseline Requirements forbid public CAs to do; private / enterprise CAs and custom bundles are the realistic exposure. It breaks the documented CVE-18 rule (RFC 9525 §6.3). |
| **Class** | Identity verification (RFC 9525 §6.3 / RFC 6125 §6.2.1: an IP-ID is compared with iPAddress SANs only; DNS-ID and wildcard rules apply to DNS names only). A CVE-18 residual. |
| **Affected** | the native TLS client (`tls_connect*` under the native backend, `tls_native_connect`, `tls_native_client_verify_hostname`) from 6.0.30 (SAN matching; every dNSName tried for every host) through 6.6.12; the lax IPv6 literal parse from 6.1.36 (CVE-18's iPAddress matching) through 6.6.12. The libssl backend is a separate defect (I1). |
| **Files** | `lib/tls_native_conn.cyr` — `_tn_cert_san_match` (the GeneralName loop), `_tn_parse_ipv4`, `_tn_ipv6_groups`, `_tn_parse_ipv6`, `_tn_parse_ip_literal` |
| **Fixed** | 6.6.13 |

**Vector.** A server presents a chain-valid leaf whose SAN holds `DNS:<the IP the client dialled>` (e.g. `DNS:127.0.0.1`), or a wildcard over it (`DNS:*.0.0.1`), or — for IPv6 / malformed hosts — a dNSName spelling the host verbatim (`DNS:::1`, `DNS:[::1]`, `DNS:fe80::1%eth0`) or an iPAddress entry a malformed host lax-parses to (host `1:2:3:4:5:6:7:8:` / `1:2:3:4::5:6:7:8` vs `IP:1:2:3:4:5:6:7:8`; `00001::` vs `IP:1::`; `::1:` vs `IP:::1`).

**Impact.** The client accepts that certificate for the IP-literal host: a man-in-the-middle holding any such certificate from a trusted (private) CA impersonates the server. Also: `_tn_parse_ipv4` read a leading-zero host (`010.0.0.1`) as an address while the resolver (`net_parse_ipv4`) sends it to DNS as a name, so the verifier and the resolver disagreed on what the host was.

**Fix.** `_tn_cert_san_match` classifies the host ONCE, before the walk — `_tn_parse_ip_literal` returns 4/16 (IP literal: compared with 0x87 entries only, octet for octet), 0 (DNS name: compared with 0x82 entries only) or -1 (a `:`-bearing host that is no well-formed IPv6 literal: matches nothing). `_tn_parse_ipv4` refuses a leading zero, mirroring `net_parse_ipv4`. `_tn_ipv6_groups` / `_tn_parse_ipv6` follow RFC 4291 §2.2: 1-4 hex digits per group, no empty group or trailing `:`, `::` stands for >= 1 group (the two sides hold <= 14 bytes), and an optional dotted-quad tail (`::ffff:1.2.3.4`) parsed by the strict IPv4 parser. No public API change.

**Behaviour change.** A client connecting by IP to a server whose certificate spells that IP only as a dNSName now fails with `TLS_ERR_CERT_HOSTNAME_MISMATCH` (reissue with an `IP:` SAN). Bracketed hosts and hosts with a zone id verify against nothing.

**Verified.** Filed repro `docs/development/issues/repros/2026-10-01-tls-ip-literal-dnsname.sh` exits 0 (2 on 6.6.12). `tests/tcyr/crypto/tls_native_scaffold.tcyr` group "RFC 9525 IP-ID vs DNS-ID (6.6.13)": 83 assertions over six self-signed P-256 leaves, the literal classifier and `_tn_parse_ipv4` vs `net_parse_ipv4` agreement; 41 fail against the 6.6.12 lib; 532/532 on x86_64 and aarch64 (qemu).

**Not covered.** The native client still sends an IP literal as SNI (RFC 6066 §3) — backlogged (6.6.13 roadmap backlog item d).

## CVE-64 — a native TLS server that required client certificates authenticated nobody: a TLS 1.2 client connected with none, a TLS 1.3 client on possession of any leaf, and `tls_set_verify` dropped FAIL_IF_NO_PEER_CERT

*Appended 2026-10-02 (cyrius 6.6.14, lane auth: A1 + A2 + A3). Found by: the 6.6.13 TLS review — the "v6.2.8 SCOPE LIMITATION" note on `tls_native_server_recv_client_certificate`, the 1.2 server's missing CertificateRequest and the `tls_set_verify` mapping, recorded as 6.6.14 candidates (roadmap, 2026-10-02); each reproduced by the 6.6.14 premise check before the fix. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.14 spends CVE-64 … CVE-67.*

| | |
|---|---|
| **Severity** | P1 (High) — authentication bypass. A native server configured to REQUIRE client certificates (mutual TLS) admits an unauthenticated client (offer only TLS 1.2, or present nothing through a `tls_set_verify` FAIL mode) or a client of the attacker's choosing (present any self-signed leaf — the server checked only that the client held its key). No key, no CA cooperation, nothing on-path needed: a network client does it alone. Exposure is bounded by deployment: no surveyed consumer turns client authentication on for a native server. |
| **Class** | Improper certificate validation (CWE-295); improper authentication / authentication bypass by downgrade (CWE-287, CWE-757); incorrect mapping of a security setting (CWE-1220-like: a stricter mode silently weakened). |
| **Affected** | Every native-TLS server with a verify mode other than `TLS_VERIFY_NONE` — `tls_native_set_verify` on a server ctx, or `tls_set_verify(handle, mode != 0, …)` in a `tls_accept_alloc[_in]` hook (the default backend since 6.1.21): the 1.3 possession-only check from 6.2.8 (server-side client auth) through 6.6.13; the 1.2 server's missing CertificateRequest from 6.0.74 (the 1.2 server) through 6.6.13, a bypass once a 1.3 server could ask (6.2.8); `tls_set_verify`'s mapping from 6.0.80 (native dispatch) through 6.6.13. The libssl backend is not affected (OpenSSL validates the chain and requests the certificate in both versions). The 1.2 CLIENT's inability to answer a CertificateRequest (an interop defect, not a vulnerability) was fixed with it. |
| **Files** | `lib/tls_native_hs12.cyr` — `tls_native_client_verify_chain` / `_tn_verify_chain` / `_tn_leaf_purpose_ok` / `_tn_cert_eku_client_auth`, `tls_native_12_build_server_flight`, `_tn_12_server_drive`, `_tn_12_build_cert_request`, `_tn_12_srv_next_msg`, `_tn_12_srv_client_cert`, `_tn_12_srv_client_cv`, `_tn_12_client_consume_flight`, `_tn_12_parse_cert_request`, `tls_native_connect_12`, `tls_native_12_build_client_hello`; `lib/tls_native_hs13.cyr` — `tls_native_server_recv_client_certificate`, `tls_native_server_recv_client_certverify`, `_tn_server_take_client_chain`, `_tn_verify_client_sig`, `_tn_sign`; `lib/tls_native_conn.cyr` — `tls_native_accept`, `_tn_client_auth_alert`, `tls_native_get_peer_cert_der` / `_spki_der` (`_tn_peer_leaf`); `lib/tls.cyr` — `tls_set_verify`; `lib/tls_native_ctx.cyr` — `tls_native_server_transition`, `_tn_server_connected` (+560 `TLS_CTX_OFF_CLIENT_SIG_SCHEME`, +568 `TLS_CTX_OFF_HS_DONE`) |
| **Fixed** | 6.6.14 |

**Vector.** (1) **Downgrade:** against a native server that requires client certificates (`TLS_VERIFY_FAIL_IF_NO_PEER_CERT`, or any verify mode), offer only TLS 1.2 (`openssl s_client -tls1_2`, or a native client pinned with `tls_native_set_version_range(c, 1.2, 1.2)`). The server's default range is 1.2–1.3, `tls_native_accept` routes a 1.2 ClientHello to `_tn_12_server_drive`, which sends no CertificateRequest and never reads the verify mode: the handshake completes with no client certificate (measured on 6.6.13: accept `TLS_OK` with FAIL_IF_NO_PEER_CERT and with PEER + an untrusted self-signed client certificate). (2) **Any identity, TLS 1.3:** present a self-signed leaf (or an expired one, or one from a CA the server does not trust) and sign the CertificateVerify with its key: `tls_native_server_recv_client_certificate` parsed the leaf and verified no chain, so the server accepted it — and a server with no trust roots at all accepted every client (measured: accept `TLS_OK`). (3) **Through the wrapper:** a hook calling `tls_set_verify(handle, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, 0)` got `TLS_VERIFY_PEER` (`lib/tls.cyr` mapped every non-zero mode to PEER), so a client presenting nothing was accepted in TLS 1.3 too.

**Impact.** Any network client is admitted to a service that relies on mTLS to decide who may connect, unauthenticated (1, 3) or as a self-chosen identity (2). A server that authorizes by the client's certificate had, in addition, no way to read it: the native peer getters read the client-side slot and answered 0 on a server.

**Fix.** One role-neutral chain verifier, `_tn_verify_chain(ctx, leaf, inters, now, purpose)` — the client's RFC 5280 path building, moved out of `tls_native_client_verify_chain` (now its server-identity wrapper, unchanged) — with the leaf checked for its purpose: a TLS client's keyUsage must allow digitalSignature or keyAgreement and its extendedKeyUsage list clientAuth or anyExtendedKeyUsage (read from the DER: sigil records serverAuth only). A server verifies the client's whole certificate_list (`_tn_server_take_client_chain`, leaf + up to 16 more) to its OWN trust roots at `_tn_now_unix()`; no roots → refused (fail closed); no hostname. TLS 1.3: an empty request context, a list that fills the message, an exact CertificateVerify length. TLS 1.2: a CertificateRequest whenever the verify mode is not NONE (ecdsa_sign; ecdsa_secp256r1_sha256 / ecdsa_secp384r1_sha384 / ed25519 — the 1.3 offer; no CA names); the client's flight read message by message across records; the chain verified; a presented certificate's CertificateVerify verified over every handshake message before it (the scheme naming the hash, the key the curve — RFC 5246 §7.4.1.4.1); an empty Certificate refused under FAIL_IF_NO_PEER_CERT; an unrequested message refused, a missing CertificateVerify refused (the CCS in its place). A refused client is told why with a fatal alert. `tls_set_verify`: bit 2 set → `TLS_VERIFY_FAIL_IF_NO_PEER_CERT` (with or without PEER — never looser than asked), other non-zero → PEER. The peer getters answer the client's verified leaf on a server ctx once the handshake COMPLETED (`TLS_CTX_OFF_HS_DONE`, latched where the server's handshake completes, never cleared): nothing for a handshake that failed after the certificate verified, and the identity kept through a later connection error, as libssl keeps it. The native 1.2 client answers a CertificateRequest (its certificate + CertificateVerify, or an empty Certificate) and, holding a P-256 / P-384 certificate, lists that curve in supported_groups after x25519 (OpenSSL refuses an ECDSA client certificate on a curve the client did not list).

**Behaviour change.** A native mTLS server refuses a client certificate that does not chain to its own roots (a self-signed one not itself installed as a root; every certificate when the server has no roots), an expired one, and one whose keyUsage / extendedKeyUsage forbid client authentication; a TLS 1.2 client now gets a CertificateRequest; `tls_set_verify(h, 2 | 3, …)` now requires a certificate; RSA client certificates are not offered natively (they never were in 1.3); `tls_get_peer_spki_der` on a server returns the client's key once the handshake completed. ⚠ A native client limited to TLS 1.2 that HOLDS a P-256 / P-384 client certificate now fails (`TLS_ERR_HANDSHAKE_FAILED`) against a 1.2 server that ranks that curve above X25519 for the key exchange by its own preference, whether or not it asks for a certificate — 6.6.13 connected there (its ECDHE is x25519 only; see *Not covered*). No surveyed consumer is affected: sandhi's and sit's servers set no verify mode, abaco and whirl are clients, no caller passes a verify callback; sandhi's mTLS client now completes against a TLS 1.2 server that asks.

**Verified.** `tests/tcyr/crossos/tls_native_client_auth.tcyr` (236 assertions; native client ↔ native server through `tls_accept_alloc_in` + a `tls_set_verify` hook, in-memory transport, seeded entropy, pinned clock, replayed to a fixed point, single-threaded): TLS 1.3 and 1.2 × no certificate (PEER / FAIL), trusted P-256 / Ed25519 / P-384 leaves (the server's getters naming the client, and still naming it after a later read error), untrusted, foreign-CA, expired, serverAuth-only, keyEncipherment-only, wrong-key, no-roots, CertificateVerify removed, unrequested CertificateVerify, server not asking, and the `tls_set_verify` mode table; 55 of 236 fail on the 6.6.13 lib; 13 mutants RED. 236/236 on x86_64 and pi (aarch64, 35.5 s), and the crossos leg (165/165, self-host OK) green on pi, ecb, ach and cass at the final code. `tests/gates/platform/tls_native_client_auth_openssl.sh` (27 rows against OpenSSL `s_client` / `s_server` — 3.6.5 on x86_64, 3.0.13 on pi — both directions, both versions, an intermediate chain, P-384 signing SHA-256 in 1.2, a keyEncipherment-only leaf, and the supported_groups trade-off at its boundary); 22 of 27 RED on the 6.6.13 lib (one the trade-off row); 9 mutants RED. `tests/tcyr/crypto/tls_native_scaffold.tcyr` (558: the chain rules on direct calls, the getter before completion and after failure, and the framing — request context, list and signature lengths, the 1.2 CertificateRequest — each check RED when dropped), `tls_native_mtls_client.tcyr`, `tls_native_alert_mapping.tcyr`, `tls_native_ccs_deadline.tcyr` updated (their mTLS servers now trust the client's root).

**Not covered.** RSA client certificates (native signs and offers ECDSA / Ed25519 only). The native client presents its leaf alone, never an intermediate chain (`tls_native_set_client_cert` keeps one certificate). The certificate_authorities list is empty, so a client holding several certificates cannot pick by issuer. The TLS 1.3 server still reads each client message from one record (a client Certificate of at most 8 KiB, never split or coalesced across records); the 1.2 server reassembles up to 16 KiB. The native TLS 1.2 client does ECDHE on x25519 only. Listing a P-256 / P-384 client certificate's curve (which OpenSSL requires of a 1.2 client certificate) therefore trades one interop case for another: a 1.2 server that ranks that curve above X25519 by its own preference fails the handshake (documented in `lib-tls-contract.md`, "The client side", and pinned by the gate's `-groups P-256:X25519 -serverpref` row); and OpenSSL 1.2 servers with an ECDSA SERVER certificate on P-256 / P-384 still refuse a native client with no such client certificate ("no shared cipher"). The remedy for both is ECDHE on P-256 / P-384 in the 1.2 client — a new key-exchange capability that wants a constant-time ECDH primitive from sigil (its P-256 / P-384 scalar multiplications are public-scalar, non-CT), so it is not part of this fix. No verify callback natively: a caller pinning through an OpenSSL callback must check `tls_get_peer_spki_der` after the handshake.

## CVE-65 — on Windows, the native TLS client read its system trust roots from a DRIVE-RELATIVE `/etc/ssl/cert.pem` any local user can plant (and had no real system store)

*Appended 2026-10-02 (cyrius 6.6.14, lane wintrust, items W1–W3). Found by: the 6.6.13 premise check and lane reviews (roadmap "6.6.14 — candidates: the TLS follow-ups"). This is the CVE-54 / CVE-57 class (a rooted POSIX path is drive-relative on Windows), reached through the TLS trust store. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.14 spends CVE-64 … CVE-67.*

| | |
|---|---|
| **Severity** | **Medium (P2)**. A local, unprivileged user chooses the trust anchors of every other user's native TLS client on the same Windows machine, and so can impersonate any server to them from a network position. Reachability in 6.6.13 was narrow — native TLS did not run over `lib/net.cyr`'s Winsock sockets (backlog j) — but it was live through a custom transport, through `tls_init_main()` / `tls_ctx_set_verify_paths` / `tls_native_set_ca_system` followed by `tls_native_client_verify_chain`. 6.6.14 also lands the Winsock transport, which would have made it live for every Windows `tls_connect`; the fix ships in the same release, so that combination never shipped. |
| **Class** | Trust chain / path planting (CWE-427-like: an untrusted search path for a security-critical file). CVE-54 and CVE-57 residual. |
| **Affected** | PE (Windows) programs that include `lib/tls.cyr` / `lib/tls_native.cyr` and load the system roots: `tls_native_set_ca_system`, `tls_ctx_set_verify_paths`, `tls_init_main`, and every native `tls_connect*` (`_tls_native_alloc_in` installs the system set on every connect). The four candidate paths arrived at 6.0.78 (the multi-root system store) and were read on every target from then on; `file_open` (6.2.23) passes a rooted path straight to `CreateFileW`, which resolves it against the current drive. Confirmed on cass against the 6.6.13 lib. |
| **Files** | `lib/tls_native_hs12.cyr` — `_tn_ca_read` (the four `file_open` calls), and the new `_tn_ca_read_win`, `_tn_w_export`, `_tn_w_policy`, `_tn_w_dated`, `_tn_w_prop`, `_tn_w_eku_server` + the other `_tn_w_*` helpers |
| **Fixed** | 6.6.14 |

**Vector.** `_tn_ca_read` opened `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt` and `/etc/ssl/ca-bundle.pem` on every target. On Windows a rooted path is drive-relative, so the reader opened `C:\etc\ssl\cert.pem` (on the current drive), and any authenticated user may create a folder at the root of the system drive. Windows had no other source of system roots: with no such file, `tls_native_set_ca_system` returned `TLS_ERR_IO` and installed nothing.

**Impact.** One local user creates `C:\etc\ssl\cert.pem` holding a CA they control; every other user's native TLS client on that machine then loads it as its ONLY system trust root (once per process, cached), and accepts any chain that CA signs for any host name. Measured on cass (real Windows) against the 6.6.13 lib: with no file, `tls_native_set_ca_system` returned -12 (`TLS_ERR_IO`) and 0 roots; with a planted `cert.pem` (a self-signed P-256 CA) it returned 0 (`TLS_OK`) with exactly 1 root — the planted one — and a certificate that root signs verified.

**Fix.** Two parts, one release:
- **W1 — the POSIX paths are not compiled for Windows.** `_tn_ca_read` dispatches to `_tn_ca_read_win` under `CYRIUS_TARGET_WIN`; the four `file_open` calls sit under `#ifndef CYRIUS_TARGET_WIN`.
- **W2 — a real Windows system store.** `_tn_ca_read_win` exports the TLS roots of the **CurrentUser `ROOT`** store (read-only, `CERT_SYSTEM_STORE_CURRENT_USER | READONLY | OPEN_EXISTING`) as the PEM bundle, under the existing once-per-process 0 → 1 → 2 publish (`_tn_ca_load`). CurrentUser `ROOT` is the store the current-user chain engine — the one SChannel / WinHTTP use for a client in a user's process — anchors to, and it is a logical store holding LocalMachine `ROOT`, the AuthRoot (third-party) roots and the Group Policy / Enterprise roots (cass: CurrentUser `ROOT` 59 ⊇ LocalMachine `ROOT` 59 ⊇ AuthRoot 47). The walk (`_tn_w_export`, which takes the two store handles) applies the root program's per-certificate properties; the policy only ever REMOVES roots, and anything it cannot judge is refused:
  - a root whose purposes (`CERT_ENHKEY_USAGE_PROP_ID`, 9) leave out serverAuth is not exported (cass: 6 — Thawte Timestamping CA, Symantec Enterprise Mobile Root, Microsoft Authenticode, UTN-USERFirst-Object and two time-stamping roots);
  - Microsoft distrusts by DATE two ways, each scoped by a purpose list (absent = every purpose): a **Disable** date (`CERT_DISALLOWED_FILETIME_PROP_ID` 104, scope `CERT_DISALLOWED_ENHKEY_USAGE_PROP_ID` 122), after which the root is not trusted at all, and a **NotBefore** date (`CERT_NOT_BEFORE_FILETIME_PROP_ID` 126, scope `CERT_NOT_BEFORE_ENHKEY_USAGE_PROP_ID` 127), after which certificates it issues are not. A root with either covering serverAuth or anyExtendedKeyUsage is **refused whole** — the verifier has neither a clock-dependent root set nor a per-root issuance bound, so it fails closed — and counted in `tls_native_ca_skipped` (new `_tn_ca_sys_refused`). cass: 12 — by Disable StartCom, DST Root CA X3, AddTrust External, QuoVadis Root CA, Baltimore CyberTrust, VeriSign Class 3 G5; by NotBefore Entrust Root CA, Entrust Root CA - G2, Entrust.net (2048), SecureTrust CA, Certum CA, Class 3 Public Primary CA;
  - a root carrying root-program name constraints (`CERT_ROOT_PROGRAM_NAME_CONSTRAINTS_PROP_ID`, 84) is refused and counted the same way (the verifier has no per-root name constraint; none on cass today);
  - a property is size-queried and read whole (into the bundle buffer's free tail); a value that cannot be read, or a purpose list that is not one well-formed `SEQUENCE OF OID` filling the value exactly, cannot be judged — the root is refused and counted, and a malformed distrust scope counts as covering TLS;
  - a certificate also in the `Disallowed` store is never a root; a `Disallowed` store that cannot be opened makes the whole store unusable rather than unfiltered.
  crypt32 is loaded at first use with `LoadLibraryExA("crypt32.dll", 0, LOAD_LIBRARY_SEARCH_SYSTEM32)`, resolved through the existing GetModuleHandleA / GetProcAddress reroutes (0xF013 / 0xF014) and called through `callptr`. It is deliberately not an IAT import: crypt32 is not a KnownDLL, so an imported crypt32.dll would be searched for in the application directory first, and one planted beside any TLS program would run at its load — the same planting class again. No compiler change.

**Behaviour change (Windows only).** `tls_native_set_ca_system` returns `TLS_OK` with the store's TLS roots instead of `TLS_ERR_IO` (cass: 41 exported, 40 installed, 13 skipped = 1 sigil cannot parse (the md5-signed Microsoft Root Authority) + 12 refused); `tls_ctx_set_verify_paths` returns 1; a verifying native connect has roots. A bundle placed at `C:\etc\ssl\cert.pem` is no longer read — install a private bundle with `tls_ctx_load_verify_locations`. A process that loads the system roots maps crypt32.dll (from System32) at that first load; the load costs ~26 ms once per process on cass.

**Verified.** `tests/tcyr/crossos/tls_system_trust_store.tcyr` (new; the release gate's cross-OS leg runs it):
- on Windows it plants `C:\etc\ssl\cert.pem` itself (asserting the plant), loads the system roots, and asserts the planted root anchors nothing and is not in the cached bundle, then removes only what it created; `C:\etc` does not exist afterwards;
- on every target the system set loads, installed + skipped == PEM blocks + refused, a second ctx shares the set at 0 B, and a real chain (www.microsoft.com → Microsoft TLS G2 RSA CA OCSP 04 → Microsoft TLS RSA Root G2 → **DigiCert Global Root G2**) verifies offline at a fixed time against the system roots — with three controls (a set of only the fixture root, a time past the leaf's notAfter, the cross-signed root left out) that each fail;
- on Windows the exported bundle is re-derived from the `ROOT` store certificate by certificate, with the test's own reading of the properties (its own property reads, well-formedness walker, PEM encoder and `Disallowed` copy), and no root whose NotBefore distrust covers TLS may be in it;
- on Windows the policy is then run rule by rule on stores the test builds in MEMORY (`CERT_STORE_PROV_MEMORY`; the fixture root with exactly the properties each row names; no admin rights, no machine trust state touched) — 42 rows: `Disallowed` (the fixture, or a different certificate), the purposes allow-list (including six malformed and two 694-byte lists), name constraints, every Disable / NotBefore shape (absent, empty, `[serverAuth]`, `[codeSigning, serverAuth]`, anyEKU, `[codeSigning]` only, malformed, 694-byte), and a block or property that does not fit the buffer.

Measured results:
- **cass:** 82/82. The W1 rows alone against the 6.6.13 lib: 7/9, 2 FAIL (the planted root anchored the planted certificate and sat in the cached bundle). Mutants of the final fix, each RED on cass: the W1 hunk removed (5 FAIL), `Disallowed` check removed (2), NotBefore (126/127) not applied (13 — the real-store rows among them: 6 such roots in the bundle), a malformed distrust scope read as sparing TLS (4), a malformed purpose list read as "not a TLS root" (6), a fixed 512-byte property read (3), an unreadable purpose list not counted (1), name constraints not applied (2), the refused count not added to skipped (1). Each review fix was also run against the lib before it: 10, 10, 3 and 2 FAIL.
- **cass, through the OS store itself (one-off, cleaned up, before the memory rows existed):** a throwaway self-signed root (its key discarded) added with `certutil -addstore Root` was installed and its certificate verified; added to `Disallowed` as well it was excluded and no longer verified; both store entries were then deleted and the count checked back to 0.
- **Other targets:** 17/17 on x86_64 (Arch, 121 blocks); the whole `crossos/` leg with SELFHOST_OK on pi, ecb, ach and cass (`cross-os-selfhost.sh <host> crossos`).

**Not covered.**
- Windows' automatic root update: its chain engine downloads a root it does not hold yet (from the Microsoft root program list) the first time it meets one; the native client sees only the roots already in the store, so a server chaining to a not-yet-fetched root fails `TLS_ERR_CERT_INVALID` where SChannel would succeed. `tls_ctx_load_verify_locations` with a bundle is the workaround.
- A root with a dated distrust covering TLS is refused entirely. For a NotBefore date that means a leaf issued BEFORE the date — still accepted by SChannel — fails here; on cass that is a live loss only for SecureTrust CA (NotBefore 2026-09-15, so its leaves issued before then stay valid into 2027) — the Entrust roots' date (2025-04-16) is past the 398-day leaf limit already. For a Disable date in the future it means the root is refused before Windows stops trusting it (none on cass). The verifier gaining a per-root issuance bound would lift this.
- Not Windows parity in the other direction either: the chain engine also consults the auto-updated disallowed CTL (`HKLM\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate\DisallowedCertEncodedCtl` — on cass 6092 B, ~97 hashes, while the `Disallowed` STORE holds 0 certificates), which is not read; none of its hashes matches a cass `ROOT` certificate today. And `Disallowed` is applied to roots only — an intermediate or leaf Windows has distrusted is not refused when a server sends it.
- The native verifier does not check a CA certificate's own extendedKeyUsage extension (only the leaf's), on any target; Windows' chain engine and OpenSSL do. Independent of the store.

## CVE-66 — a TLS write to a peer that had reset the connection raised SIGPIPE: any peer could kill a TLS client or server process that had not ignored the signal (native and libssl backends)

*Appended 2026-10-02 (cyrius 6.6.14; native half lane io item I2, libssl half lane client item C2). Found by: CVE-61's and CVE-60's *Not covered* (the 6.6.13 I8 and I2 (c) work), roadmap backlog (f). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.14 spends CVE-64 … CVE-67.*

| | |
|---|---|
| **Severity** | P1 (High) — availability, remote and unauthenticated. Any peer — before or after the handshake, with no key and no certificate — ends the WHOLE process (every connection of a server, not one): a client by closing before the victim's next write, a server's client by connecting and hanging up before the server's flight goes out. Not P0: no code execution or data exposure, and a process that ignores SIGPIPE itself (`signal_ignore(SIGPIPE)`; sandhi since 1.6.6) was never exposed. The libssl half alone would be P2 (an opt-in backend); the native half is the default backend on every POSIX target. |
| **Class** | Uncaught exception / improper handling of an exceptional condition (CWE-248, CWE-755): a process-fatal signal raised by a library on peer-controlled input (CWE-400 class). |
| **Affected** | **Native:** Every native-TLS client and server on Linux (x86_64, aarch64) and macOS (arm64, x86_64) — the default `lib/tls.cyr` backend since 6.1.21 and every direct `tls_native_*` user — that had not ignored SIGPIPE, through 6.6.13: `tls_native_write` / `tls_write`, the handshake's own writes (ClientHello, ServerHello and flight, Finished, the TLS 1.2 CCS), the close_notify `tls_native_close` / `tls_close` sends, and the fatal alerts the stack sends on a protocol violation (6.6.13's CCS policy). Windows and agnos raise no such signal (agnos: `sock_send#48` answers -1 for a dead connection; its kernel documents "EPIPE — there is no SIGPIPE"). A custom transport (`tls_native_set_transport`) writes through its own `write_fn` and is the transport's to protect. **libssl:** Every libssl-backend client and server — every `-D CYRIUS_TLS_LIBSSL` build and every default build after `tls_set_backend(TLS_BACKEND_LIBSSL)` — on Linux x86_64 (the only libssl target), from the libssl wrapper's introduction (4.9.3) through 6.6.13, in any process that leaves SIGPIPE at its default disposition. Reached by `tls_write`, `tls_read` (an alert or a KeyUpdate answer libssl writes), `tls_connect_complete` / `tls_accept_complete` (the handshake's writes), `tls_close` (`SSL_shutdown`'s close_notify) and the 0-RTT pair. |
| **Files** | **Native:** `lib/tls_native_conn.cyr` — `_tn_io_write_all` (the one choke point every native record write passes through), `_tn_nb_write_all` (its deadline form), the new `_tn_os_write` / `_tn_nosigpipe`; `lib/tls_native_ctx.cyr` — `TLS_CTX_OFF_NOSIGPIPE` (+576), `TLS_CTX_LEN` 576 → 584. **libssl:** `lib/tls.cyr` — every `SSL_connect` / `SSL_accept` / `SSL_read` / `SSL_write` / `SSL_shutdown` / `SSL_write_early_data` / `SSL_read_early_data` call (they now all go through `_tls_ssl_call`; new `_tls_sigpipe_hold` / `_tls_sigpipe_release`) |
| **Fixed** | 6.6.14 |

**Vector.** **Native.** The peer closes its socket (a FIN). The victim's next record write reaches a closed socket, whose kernel answers with an RST; the write after that — or, on macOS, the first write once the RST has arrived — fails with EPIPE, and a flagless `write(2)` on a socket raises SIGPIPE with it. On Linux the RST arriving in CLOSE_WAIT sets `sk_err = EPIPE` and `sk_stream_error` sends the signal unless the send carries `MSG_NOSIGNAL`; on macOS `sosend` answers EPIPE for `SS_CANTSENDMORE` and `soo_write` signals unless the socket has `SO_NOSIGPIPE`. A client that merely disconnects while a server is writing a response is enough, and so is a server that drops a client mid-stream. The 6.6.13 fatal alert made one more such write (answering a CCS the peer sent after the handshake, then closed).

**libssl.** libssl's socket BIO writes with `write(2)`, not `send(…, MSG_NOSIGNAL)`, and Linux has no per-socket `SO_NOSIGPIPE`. Close the connection under a libssl peer, then let it write: the kernel raises SIGPIPE on the writing thread. Measured on 6.6.13 (OpenSSL 3.6.5, socketpair, SIGPIPE at `SIG_DFL`): the first `tls_write` after the peer closed — exit 141 (killed by SIGPIPE); likewise `tls_close` after the peer closed (close_notify), a `tls_read` that must answer a KeyUpdate(update_requested) to a gone peer, a libssl server's `tls_write` after its client closed, and a libssl server's `tls_accept_complete` answering a ClientHello whose sender had already closed — each killed by signal 13.

**Impact.** **Native.** Denial of service: the process dies (`128 + 13 = 141`), taking every connection and every thread with it. Measured against the 6.6.13 lib on x86_64 Linux, pi (aarch64), ecb (macOS arm64) and ach (Intel Mac): all five SIGPIPE rows of `tests/tcyr/crossos/tls_native_socket_transport.tcyr` kill the writer with SIGPIPE (exit 141) on every host (39 of the file's 44 assertions pass, these five fail) — a TLS 1.3 client's record write, a TLS 1.2 server's record write under a deadline, a TLS 1.3 client's close_notify, a TLS 1.2 server's fatal alert, and a TLS 1.3 client's ClientHello — the handshake's own first write — on a socket already shut down both ways (the state an RST leaves).

**libssl.** Denial of service: the whole process — every other connection and thread with it — is terminated by any peer, from an unauthenticated network position; for a server, by any client that connects and hangs up at the right moment.

**Fix.** **Native.** The default transport's write leaf protects every native record write without touching the process-wide signal disposition:
- **Linux** (x86_64 and aarch64): `_tn_os_write` sends with `send(fd, buf, n, MSG_NOSIGNAL)` — `sys_sendto(fd, buf, n, 0x4000, 0, 0)`, `SYS_SENDTO` 44 on x86_64 and the native 206 on aarch64 (no ESYSXLAT row involved) — so a reset is EPIPE, never SIGPIPE; an fd that is not a socket (`ENOTSOCK`, 88) falls back to `write(2)`, so a pipe or a file still works.
- **macOS** (no `MSG_NOSIGNAL` in the documented API): `_tn_nosigpipe` sets `SO_NOSIGPIPE` (`SOL_SOCKET` 0xFFFF, 0x1022, through `sys_setsockopt`, which both Mach-O backends route to BSD 105) on the socket before the connection's first write; the ctx remembers the fd it covered (`TLS_CTX_OFF_NOSIGPIPE` = fd + 1, a ctx-less write sets it each time). `ENOTSOCK` (38) means a pipe or a file and the write proceeds; ANY other refusal fails the write closed with `TLS_ERR_IO` instead of writing unprotected — xnu answers `EINVAL` for a socket already shut down both ways, which is exactly what an RST leaves.
- Both write loops use the leaf: the plain one and the deadline's non-blocking one (`_tn_nb_write_all`), so a deadline does not reopen the hole.
A write into a reset connection is `TLS_ERR_IO` and fails the ctx, as any other socket failure does.

**libssl.** Every libssl call that can write goes through `_tls_ssl_call(op, …)`, which holds SIGPIPE off in the CALLING THREAD for that one call — libpq's `pq_block_sigpipe` / `pq_reset_sigpipe` pattern: `rt_sigprocmask(SIG_BLOCK, {SIGPIPE})` saving the caller's mask; if SIGPIPE was already blocked, `rt_sigpending` notes whether one was already pending (that one is the caller's); after the call, if none was pending before and one is pending now, a zero-timeout `rt_sigtimedwait` consumes it — the SIGPIPE this call raised; then `rt_sigprocmask(SIG_SETMASK)` restores the caller's mask exactly. The failed write itself surfaces as libssl's `SSL_ERROR_SYSCALL`, i.e. `TLS_ERR_IO` from `tls_read` / `tls_write` and 0 from the `*_complete` verbs. The process-wide disposition is never touched (no `SIG_IGN`), so a consumer's own SIGPIPE handling and every other thread are as they were. Linux x86_64 only (`#ifdef CYRIUS_TARGET_LINUX` + `CYRIUS_ARCH_X86`; raw `rt_sigpending` 127 / `rt_sigtimedwait` 128 — the libssl backend runs nowhere else). Cost: three syscalls per libssl call (measured ~1.1 µs on the release box, kernel mitigations on). No public API change.

**Behaviour change.** **Native.** A native TLS process that has not ignored SIGPIPE now survives a peer reset: `tls_native_write` / `tls_write` return `TLS_ERR_IO`, `tls_native_close` returns `TLS_OK` (its close_notify is best effort). On macOS a socket that refuses `SO_NOSIGPIPE` fails the connection's first record write with `TLS_ERR_IO` (it is already dead). The native ctx grows 576 → 584 bytes (internal, not contract). No public API change. ⚠ The default transport now makes different syscalls: on Linux every record write to a socket is `sendto(2)` (44 on x86_64, 206 on aarch64) instead of `write(2)` (`write(2)` remains only for an fd that is not a socket), and on macOS each connection adds one `setsockopt(2)`. A seccomp allowlist around a native TLS writer must permit them: one that permits `write` but not `sendto` now kills the process (SIGSYS) on its first record write — kavach's `basic` profile (`security_create_basic_seccomp_filter`, `RET_KILL_PROCESS` on a miss) is one, read from its source (`src/security.cyr` `_seccomp_allow_list`), not traced. The deadline path's `fcntl` / `poll` are unchanged from 6.6.13.

**libssl.** A libssl-backend program whose peer closes now reads `TLS_ERR_IO` (writes) or a 0 from `*_complete` instead of dying of SIGPIPE. A program that had installed its own SIGPIPE handler no longer sees it invoked for libssl's own writes (the signal is held and consumed); a SIGPIPE it already had pending is left pending.

**Verified.** **Native.** `tests/tcyr/crossos/tls_native_socket_transport.tcyr` (new, in the release gate's cross-OS set; 44 assertions; the test spawns itself — fork + execve on POSIX, CreateProcessW on Windows — so both ends run at once where threads run inline): five rows run the writer in a child that resets SIGPIPE to SIG_DFL first, so an inherited ignore cannot pass a row vacuously — a TLS 1.3 client's record writes with no deadline, a TLS 1.2 server's under a deadline (the non-blocking writer), a TLS 1.3 client's close_notify into the reset connection, a TLS 1.2 server's fatal alert answering a late CCS, and a socket shut down both ways before the connection's first write. 44/44 on x86_64 Linux, pi, ecb, ach and cass. Against the 6.6.13 lib all five rows read 141 (SIGPIPE) on x86_64, pi, ecb and ach — `39 passed, 5 failed (44 total)` on each, the fifth being the shut-down-first row, whose ClientHello write is the one killed (re-run in the fix pass with the final test on all four hosts). Mutants, each RED: the Linux leaf back to `write(2)` (5 rows → 141, x86_64 and pi); `_tn_nb_write_all` back to `write(2)` (the 3 deadline rows → 141, the 2 others still pass — the two write loops are covered separately); `_tn_nosigpipe` a no-op (5 rows → 141 on ecb and ach); a refused `SO_NOSIGPIPE` ignored instead of failed closed (the shut-down-first row → 141 on ecb and ach); the `ENOTSOCK` fallback removed (the file rows fail on x86_64).

**libssl.** `tests/tcyr/crypto/tls_libssl_sigpipe.tcyr` (56 assertions). Live — Linux x86_64 with libssl.so.3 and the dlopen-helper, a named SKIP elsewhere: seven forked cases at SIGPIPE's DEFAULT disposition — client `tls_write` after the peer closed (`TLS_ERR_IO`), client `tls_close` after the peer closed, client `tls_read` answering a KeyUpdate to a gone peer (an error), server `tls_write` after the client closed (`TLS_ERR_IO`), server handshake answering a ClientHello whose sender left (0), a client `tls_write` under a deadline after the peer closed (`TLS_ERR_IO`, through the `_tls_ssl_io` loop), and a client handshake whose server end closed before the ClientHello (0) — each child also asserting the disposition is still `SIG_DFL`, its mask unchanged and nothing pending; and a case where the caller has SIGPIPE blocked with one already pending, which must stay pending with the mask kept. Structural — no libssl needed, so it also runs in check.sh's environment (no dlopen-helper there): spies replace `SSL_connect`, `SSL_accept`, `SSL_read`, `SSL_write`, `SSL_shutdown`, `SSL_write_early_data` and `SSL_read_early_data` behind a fake shim, and for each of 12 call sites (the four handshake / I/O calls with and without a deadline, `SSL_shutdown` twice, the 0-RTT pair) the test asserts the spy ran exactly once and that SIGPIPE was blocked in the calling thread WHILE it ran, then that the mask, pending set and disposition are the caller's afterwards. Mutants, each RED: no hold — the 6.6.13 shape — 19 (all seven live cases killed by signal 13, every structural row unheld); the deadline loop calling libssl around the hold 5; the client handshake 2; the server handshake 3; the 0-RTT pair 2; `SSL_shutdown` outside the wrapper 3; no consume 7 (the restored mask delivers it); consume a pre-pending one 1; process-wide `SIG_IGN` instead 23. The existing libssl suite (`tls_libssl_read_errors`, `tls_client_alloc_in`, `tls_native_ccs_deadline`, `tls_early_data_status`, `tls_libssl_spki_int_return`) stays green.

**Not covered.** **Native.** A pipe or a file used as the native transport keeps `write(2)`'s SIGPIPE: neither Linux nor macOS has a per-call flag for one, and the process-wide disposition is the application's (`signal_ignore(SIGPIPE)`). A custom transport's `write_fn` is its own.

**libssl.** The 0-RTT pair and the server handshake under a deadline are pinned structurally only (the spies above): no live case drives a real `SSL_write_early_data` / `SSL_read_early_data` to a closed peer (it needs a resumable session and a 0-RTT-accepting server), or a deadline-bounded `SSL_accept` against a client that hung up. The SIGPIPE hold costs three syscalls per libssl call; a process that already ignores SIGPIPE pays it too (the disposition is not cached: it can change at any time). The libssl backend is still MAIN-THREAD ONLY (it now fails closed off it — 6.6.14 C1); a worker cannot reach these calls.

## CVE-67 — the native TLS client took any `*.` dNSName as a wildcard: a certificate for `*.com` verified every `.com` host, and the backends disagreed on what a certificate binds

*Appended 2026-10-02 (cyrius 6.6.14, lane client, item C6). Found by: the 6.6.13 I1 review (CVE-59's register entry, *Not covered*: "Native accepts a wildcard directly over a single label (`*.com` for `a.com`) where libssl refuses"); widened by the 6.6.14 premise check, which ported OpenSSL's `valid_star` / `wildcard_match` and ran one SAN / host table through both backends. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. CVE-67 was reserved for this item (P3) when 6.6.14 was planned; 6.6.14 spends CVE-64 … CVE-67.*

| | |
|---|---|
| **Severity** | P3 (Low) — certificate identity-verification flaw. Exploitation needs a CA the client trusts to issue a wildcard over a public suffix (`*.com`) or one of the other patterns below, which the CA/Browser Forum Baseline Requirements forbid public CAs to do and Certificate Transparency would expose; private / enterprise CAs and custom trust bundles (`tls_ctx_load_verify_locations`) are the realistic exposure. With such a certificate the native client accepts it for every host it covers, where OpenSSL — and so the libssl backend since CVE-59 — refuses. |
| **Class** | Identity verification (RFC 9525 §6.3 / RFC 6125 §6.4.3: the wildcard must be the complete left-most label of a name that is not itself a public suffix); a backend divergence (the same certificate and host verified on native and refused on libssl). |
| **Affected** | The native TLS client — `tls_connect*` under the native backend (the default), `tls_native_connect`, `tls_native_client_verify_hostname` — from 6.0.30 (SAN matching) through 6.6.13, on every target. The libssl backend's half (a host starting with `.` bound as "any subdomain") from 6.6.13 (CVE-59's binder) through 6.6.13. |
| **Files** | `lib/tls_native_conn.cyr` — `_tn_host_match` (new `_tn_wildcard_ok`, `_tn_ldh_alnum`); `lib/tls_hostid.cyr` — `_tn_parse_ip_literal` (a leading-`.` host is no identity); `lib/tls.cyr` — `_tls_libssl_bind_host` (comment) |
| **Fixed** | 6.6.14 |

**Vector.** A server presents a chain-valid leaf whose SAN holds a dNSName that native read as a wildcard and OpenSSL does not: `DNS:*.com` (verified `a.com`, `example.com`, every single-label-under-`.com` host), `DNS:*.` (verified `a.`), `DNS:*.example.com.` (a trailing dot: verified `a.example.com.`), `DNS:*.*.example.com` (verified `a.*.example.com`), `DNS:*.a_b.com`, `DNS:*.-a.com`, `DNS:*.a-.com`, `DNS:*..com` (non-LDH, hyphen-edged or empty labels after the star); or a legitimate `DNS:*.example.com` and a host whose first label is not LDH (`a_b.example.com`: OpenSSL lets the star stand for `[A-Za-z0-9-]` only). Separately, on the libssl backend: a host starting with `.` (`.example.com`), which `X509_check_host` reads as a subdomain pattern and matches against `a.example.com` or `*.example.com`. Measured: the pre-fix native matcher accepted 10 of the table's 47 rows that OpenSSL 3.6.5 refuses; raw `X509_check_host` accepts `.example.com` for both leaves.

**Impact.** A man-in-the-middle holding such a certificate from a CA the client trusts impersonates every host the pattern covers to a native-TLS client (for `*.com`: every `<label>.com`). No effect on chain validation, expiry or key usage, which are separate checks.

**Fix.** `_tn_wildcard_ok(dns, len)` is OpenSSL's `valid_star` under `X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS` (the flags `_TLS_LIBSSL_HOSTFLAGS` sets on the libssl binding): a pattern is a wildcard only as `*.` followed by two or more labels, each 1+ of `[A-Za-z0-9-]`, not starting or ending in `-`, with no second `*`, no empty label and no trailing dot. `_tn_host_match` then follows `wildcard_match`: the star stands for one non-empty label of the host made only of `[A-Za-z0-9-]` (never a `.`), or for a literal `*`; the remaining labels compare case-insensitively. A dNSName that is not a wildcard is compared literally (so `*.com` matches only the host `*.com`, as in OpenSSL), and one holding a NUL byte never matches. The shared classifier `_tn_parse_ip_literal` returns -1 (no reference identity) for a host that starts with `.`, so neither backend binds one: native matched nothing for it already, and the libssl binder now refuses it under `SSL_VERIFY_PEER` before OpenSSL can read it as a subdomain pattern. No public API change.

**Behaviour change.** Native: a certificate whose only matching name is one of the patterns above is now refused (`TLS_ERR_CERT_HOSTNAME_MISMATCH`), exactly as the libssl backend refuses it. Both backends: a host starting with `.` verifies against nothing (it is no DNS name). Not changed, on either backend: `*.co.uk` still matches `a.co.uk` — OpenSSL applies no public-suffix list, and neither does native; the table pins that agreement.

**Verified.** `tests/tcyr/crossos/tls_hostname_verdicts.tcyr` (99 assertions): 47 SAN / host rows — the wildcard rows above, literals, iPAddress rows, hosts with no identity — each checked against the table's verdict on the NATIVE matcher everywhere, and, where libssl is reachable (Linux x86_64 with libssl.so.3 and the dlopen-helper), asked of OpenSSL live (`d2i_X509` of the same DER, then `X509_check_host` with `_TLS_LIBSSL_HOSTFLAGS` or `X509_check_ip_asc`, routed exactly as `_tls_libssl_bind_host` routes) — so the column is OpenSSL's answer, not a transcription, and a future divergence fails one side; plus three rows showing raw `X509_check_host`'s subdomain reading of `.example.com`. 13 fail against the pre-fix matcher and classifier (10 native rows, 3 libssl leading-dot rows). x86_64 (libssl live), and natively on pi, ecb, ach and cass (native table). `tests/gates/platform/tls_libssl_hostname_binding.sh`: a `DNS:*.com` leaf (`a.com`, `example.com`) and `a_b.example.com` against `DNS:*.example.com`, end to end against OpenSSL `s_server` on native, libssl via `tls_set_backend` and a libssl-only build — refused by all three; the pre-fix matcher accepts the 3 native rows.

**Not covered.** Neither backend consults a public-suffix list, so a wildcard over a two-label public suffix (`*.co.uk` for `a.co.uk`) still verifies on both, as on OpenSSL — the table pins that agreement; the policy is unchanged. Neither backend maps IDNA U-labels: both compare A-labels byte-wise.
