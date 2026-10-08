# Security audit — 2026-09-03 (cycc 6.5.45)

**Scope:** the untrusted-source-input surface. Previous full audit:
`docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36) at cycc 6.4.82.
**Next free identifier after this document: CVE-104.** (CVE-41 is fixed at 6.5.47; see its entry.) (CVE-37 and CVE-38 in the previous
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
string literal shifted file attribution, so a call to another file's `private` fn compiled); **CVE-56 at 6.6.12** (`lib/log.cyr`'s `log_info_kv` / `log_info_int` built a log line past a 512-byte stack buffer); **CVE-57 at 6.6.12** (on Windows, the folded sandhi resolver read a drive-relative `C:\etc\resolv.conf` any local user can plant); **CVE-58 at 6.6.12** (cxvm let guest bytecode read and write the interpreter's own host memory); **CVE-59 at 6.6.13** (the libssl TLS backend never bound the server's certificate to the host, so any chain-valid certificate verified any host); **CVE-60 at 6.6.13** (the libssl backend's `tls_read` / `tls_write` (and `tls_get_peer_spki_der`) returned a C `int` zero-extended, so a tampered record read as ~4 GiB read); **CVE-61 at 6.6.13** (the native TLS stack skipped plaintext ChangeCipherSpec records without limit and had no deadline, so anyone on the path held a thread for ever); **CVE-62 at 6.6.13** (a `[deps.NAME]` header holding `..` made `cyrius deps` create directories and git-clone outside the dep cache — a CVE-32 residual); **CVE-63 at 6.6.13** (the native TLS client verified an IP-literal host against dNSName SAN entries, wildcards included); **CVE-64 at 6.6.14** (a native TLS server that required client certificates authenticated nobody: a TLS 1.2 client connected with none, a TLS 1.3 client with any leaf, and `tls_set_verify` dropped FAIL_IF_NO_PEER_CERT); **CVE-65 at 6.6.14** (on Windows, the native TLS client read its trust roots from a drive-relative `C:\etc\ssl\cert.pem` any local user can plant); **CVE-66 at 6.6.14** (a TLS write to a peer that had reset the connection raised SIGPIPE, so any peer could kill a native- or libssl-backed TLS client or server process); **CVE-67 at 6.6.14** (the native TLS client took any `*.` dNSName as a wildcard, so a certificate for `*.com` verified every `.com` host); **CVE-68 at 6.6.15** (folded sigil's ECDSA P-256 / P-384 signing leaked its secret nonce and key through timing, and left the nonce in dead stack and a vector register); **CVE-69 at 6.6.15** (a `secret var` fn's epilogue wrote its return registers into dead stack after its own wipe); **CVE-70 at 6.6.15** (the native TLS stack never zeroed its ephemeral ECDHE private keys or shared secrets); **CVE-71 at 6.6.15** (native TLS 1.3 accepted an all-zero x25519 shared secret); **CVE-72 at 6.6.15** (a `secret var` or `defer` in a `#naked` fn compiled clean and never ran); **CVE-73 at 6.6.15** (on Windows, folded sigil's trust helpers probed drive-relative rooted POSIX paths any local user can plant); **CVE-74 at 6.6.16** (a plain-socket write to a peer that had reset the connection raised SIGPIPE, so any peer could kill a `lib/net.cyr` client or server process that had not ignored the signal — the plain-socket half of CVE-66's class); **CVE-75 at 6.6.16** (the native TLS chain verifier ignored a CA's extendedKeyUsage, so a CA confined to another purpose could issue a TLS server identity to a native client, or a TLS client identity to a native mTLS server); **CVE-76 at 6.6.16** (a `[deps.X] tag` holding `..` made `cyrius deps` create directories outside the dep cache and print `rm -rf` advice for a directory outside it — a CVE-62 residual); **CVE-77 at 6.6.17** (on Windows, an mTLS server verifying client chains against the system store anchored them at roots the store trusts for server authentication only — the trust-store half of CVE-75); **CVE-78 at 6.6.18** (`lib/fmt.cyr`'s `fmt_int_buf` wrote 24 bytes at `buf` whatever the number's length, so `fmt_float`'s own stack buffer and any `buf + pos` heap caller overran); **CVE-79 … CVE-96 at 6.6.20** (CVE-79: a `[package] cyrius` pin was path-traversed into an `execve` — code execution from a cloned repository; CVE-80: on an inherited SIGCHLD = SIG_IGN, `lib/pam.cyr` read an unwritten wait status as exit 0, so a wrong password authenticated; CVE-81: the 65th `use` alias overwrote the alias table and live compiler state, silently re-binding a call; CVE-82: `PP_EXPAND` copied macro parameter names and arguments into 512-byte stack buffers unbounded, and never checked the argument count; CVE-83: a resolve that skipped a tagged git dep dropped its CVE-21 commit pin from `cyrius.lock`, so the next resolve accepted a repointed tag; CVE-84: Windows had no munmap route, so every large `fl_free` / `cyr_munmap` leaked its mapping — unbounded growth driven by input through argon2; CVE-85: `#if`-family nesting past 64 levels wrote state bytes through live compiler state; CVE-86: an attribute line holding a multi-line string desynced the preprocessor from the lexer, so a forged `#@file` defeated `private` — a CVE-45 / CVE-55 residual; CVE-87: `[deps.]` / `[deps..]` / control-byte header names passed the CVE-62 guard; CVE-88: a `[deps.X] modules` entry with `..`, or a dep file committed as a symlink, vendored any readable file into `lib/`; CVE-89: on a CRLF `cyrius.lock` the moved-tag check failed open and `deps --verify` failed every file; CVE-90: aarch64 frame displacements past 64 KiB were emitted as a 16-bit `movz`, so loads and stores landed 64 KiB off; CVE-91: `scripts/funcgate-stage.sh`'s live-home guard compared a physical path with raw ones, so a symlinked `$HOME` walked past it to `rm -rf`; CVE-92: `cyrius publish` joined the version unquoted into a `sys_system` `git tag` line; CVE-93: `cyrius distlib`'s RETIRED-name blast door scanned a 256 KB capture, so warning volume skipped it; CVE-94: `cyriusly uninstall ../versions` deleted the whole store, the active version included, and `install` spliced its operand into `sh -c`; CVE-95: manifest strings reached the terminal raw, and `[package] name` injected a live line into a distlib bundle; CVE-96: native TLS's Ed25519 signer left a copy of the long-term private seed in an allocator buffer on every signature); **CVE-97 … CVE-102 at 6.6.20**, from the closeout security re-scan the fix lanes had not carried (CVE-97: a manifest `[build] output` reached a shell on macOS and Windows and wrote outside the checkout; CVE-98: the CLI wrote a checkout's own files through committed symlinks to any path; CVE-99: `${file:PATH}` read any file into the binary and compiled a multi-line value as source; CVE-100: the crash-safe writers' predictable temp followed a planted link; CVE-101: a stripped signature installed whenever a verifier was present; CVE-102: Windows started cmd.exe / certutil.exe by a bare name the project directory could supply); and **CVE-103 at 6.7.3** (the compiled `cyriusly cmdtools` ran whatever `scripts/cyriusly` the CURRENT directory held — CVE-94's filed remainder); all sixty-one are appended below.
⚠ **This line read "next free: CVE-42" while CLAUDE.md read "the next CVE number is 43" and this document ran 39-41.**
Two authorities, two answers, and nothing reconciled them. CLAUDE.md is the one every closeout reads, so **42 is
retired unused** and CVE-43 is the entry appended below. Anything below 104 now collides.

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

**Update (6.6.14).** Both closed: the native client sends no SNI for an IP literal (C5, the backends now agree), and a single-label wildcard such as `*.com` — with the rest of OpenSSL's wildcard refusals — is refused natively (**CVE-67**), pinned by a differential host-verdict test across both backends.

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

**Update (6.6.14).** Both closed: a failed libssl read or write is now sticky — every later `tls_read` returns the stored error (writes `TLS_ERR_PROTOCOL`, the native rule) without touching SSL, the error kept at libssl shim `+32`; and libssl's SIGPIPE on a write to a closed peer is **CVE-66** (held and consumed per call, never `SIG_IGN`).

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

**Update (6.6.14).** Windows: native TLS runs over `net.cyr`'s Winsock sockets and the deadline bounds each read and write for real there (`WSAPoll`, `FIONBIO`; backlog j). SIGPIPE on a write to a reset peer is **CVE-66** (Linux `MSG_NOSIGNAL`, macOS `SO_NOSIGPIPE`). Still open: the agnos write overshoot by one `sock_send#48` stall — it needs agnos's #48 to honour a time bound (its `tcp_send_ex` already takes one as a parameter); recorded in the roadmap.

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

**Update (6.6.14).** Closed: neither ClientHello builder sends `server_name` for an IPv4 / IPv6 literal (`_tn_sni_len`, the shared classifier); the host still binds the certificate's iPAddress entries.

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

## CVE-68 — ECDSA P-256 / P-384 signing (sigil, folded as `lib/sigil.cyr`) leaked its secret nonce and key: through timing, and in dead stack and a vector register after signing

*Appended 2026-10-03 (cyrius 6.6.15, sigil 3.13.8 + 3.13.9 refold). Found by: the sigil 3.13.8 premise check for
constant-time ECDH (could the signing ladder serve as the ECDH primitive?). Part B by the review of the first sigil 3.13.8 draft. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | P1 (High) — timing side channel on secret data. Signing time depends on the per-signature nonce k and on the private key d through data-dependent branches in the field and scalar arithmetic. A fixed-vs-random-scalar Welch t-test on the 3.13.7 signing entry separates k = 1 from random k at \|t\| = 6.3 with 400 samples (dudect threshold 4.5). The class is Minerva / TPM-Fail / LadderLeak: partial nonce information over many timed signatures recovers d by lattice reduction. The per-call difference is small (~0.4%), so exploitation needs many signatures and a quiet timing source; a native TLS server signs one CertificateVerify per handshake for any client that connects. |
| **Class** | Observable timing discrepancy (CWE-208); use of a non-constant-time algorithm on secret data (CWE-385, covert timing channel). |
| **Affected** | `ecdsa_p256_sign` / `ecdsa_p384_sign` and every caller — `ecdsa_p256_sign_der` / `ecdsa_p384_sign_der`, the Authenticode ECDSA signer, and cyrius's native TLS CertificateVerify (`_tn_sign`, ECDSA P-256 / P-384 server and client certificates) — in every sigil release with signing (3.5.9 through 3.13.7), i.e. every cyrius `lib/sigil.cyr` that carried it, through cyrius 6.6.14. Ed25519, RSA, X25519 and all verification are not affected. |
| **Files** | sigil `src/ecdsa_p256.cyr` (`fp_p256_add` / `_sub`, `_p256_sol_red1`, `_pt_ladder`, `pt_add`, `pt_double`, `fp_p256_inv`, `n_reduce`, `fn_p256_mul`, `fn_p256_inv`), `src/ecdsa_p384.cyr` (the `u384_*` / `fp_p384_*` / `n384_reduce` twins), `src/bigint_ext.cyr` (`u256_mul_full`, `_u256k_mul128` carry fix-ups), `src/mul64.cyr` (`_nmul64_hi_sw`, aarch64), `src/ecdsa_sign.cyr` (`_ecs_addmod_n_*`, the RFC 6979 candidate compare) |
| **Fixed** | sigil 3.13.8 (cyrius 6.6.15 refold) |

**Vector.** The signer computed R = k·G on a Montgomery ladder whose field operations branch on
their operands — conditional final subtracts in the modular add / subtract and the Solinas
reduction, carry fix-ups written as `if` in the 256-bit Karatsuba and 384-bit schoolbook
multiplies, early-exit compares, and on aarch64 two value-dependent branches in every 64×64
product — and then inverted the secret-derived Z, computed k^-1 mod n and r·d mod n on a
bit-serial long-division reduction with a conditional subtract per bit. sigil 3.13.0 (fixed-length
k_hat) and 3.13.1 (blinded ladder input) removed the coarse leaks, not these; sigil's 3.7.0 /
3.7.17 audits had recorded the arithmetic as an accepted INFO residual. An attacker who can time
signatures (a TLS client timing a native server's handshakes, or a co-located process) collects
signatures with timings and runs the standard hidden-number-problem lattice attack.

**Impact.** Recovery of an ECDSA P-256 / P-384 private key (a TLS server or client certificate
key, an Authenticode signing key) from enough timed signatures. Not demonstrated end to end; the
leak is measured, and the attack class is published and practical against comparable leaks.

**Fix.** sigil 3.13.8 runs every secret elliptic-curve operation on a new constant-time engine
(`src/ec_ct.cyr`): Montgomery field and scalar arithmetic with branch-free carries, borrows and
selects; complete Renes–Costello–Batina projective formulas for a = -3 (no special cases);
a fixed 4-bit window over every window of the scalar with a full-table masked lookup; Fermat
inversion with public exponents. `_nmul64_hi_sw` is branch-free. The RFC 6979 candidate test is
computed without a branch. Every conditional branch in the compiled engine (x86_64 and aarch64,
checked by disassembly with `CYRIUS_SYMS`) is a loop bound, a public exponent bit or a public
verdict. Signatures are byte-identical; signing got faster (P-256 13.3 → 2.7 ms, P-384
30.1 → 7.9 ms on the x86_64 dev host).

**Verified.** Welch t on the 3.13.8 entry: \|t\| = 0.7 at 1200 samples. sigil
`tests/tcyr/ecdsa_sign_timing.tcyr` (142: the engine against the reference ladder for edge and
random scalars, RFC 6979 KATs, interleaved-median timing of the scalar multiply and of the whole
signing core with (k, d) = (1, 1) vs (n - 1, n - 1)); `ecdsa_sign.tcyr` (90 at the final code: the
RFC 6979 KATs plus the residue groups of the second entry below); both on x86_64, the pi, ecb,
ach and cass. Every conditional branch of the compiled engine and of the signers (x86_64 and
aarch64) accounted for in sigil's audit §F2.

**Not covered.** Power / EM analysis of single traces (the engine does no coordinate or scalar
randomization). Operand-value-dependent timing through power and frequency (the Hertzbleed
class): no branch or address depends on a secret, but zero-heavy operands run measurably faster
in the fastest samples (a reviewer's dudect run on `ecdh_p256_shared`: \|t\| = 5.6 for d = 1 vs
random d with the fastest 20% kept, ≤ 1.3 uncropped; a fixed random-looking d stays ≤ 2.4), so
it follows operand values, not a code path; ephemeral ECDH scalars and RFC 6979 nonces are
uniform, so exposure is low. The RFC 6979 accept / reject branch (reveals only that a candidate
was discarded).

**Part B — the nonce survived signing (same refold).** P2 (Medium) — sensitive data left in memory (the per-signature nonce). Exploitation needs a second primitive that reads dead stack or registers (an uninitialised-memory disclosure, a core dump, swap); given one, a single signature and its k give the private key, d = r^-1(s·k − e). Pre-existing: sigil 3.13.7 leaves the same residue. The register-spill half was a cyrius defect, **CVE-69**; the rest (HMAC contexts, SHA-NI register state, the burn's size and order) was sigil's.

**Part B — Vector.** After a signature, the HMAC_DRBG's last HMAC context (whose final state is k) sat in
dead stack ~43 KB below the caller — HMAC never wiped its context — and xmm1 still held the
SHA-NI state of that round; the signer's own `secret var` epilogue, which ran after its 8 KB
stack burn, spilled xmm1 into the 64 bytes below its frame. A reviewer's probe found all eight
32-bit words of k at 42 664–42 720 bytes and words 0–3 at 212–224 bytes; sigil's new test finds
17 / 30 words of k and d (P-256 / P-384) on the 3.13.7 sources.

**Part B — Fix.** Both HMACs wipe their context and inner hash, and SHA-384's finalize its scratch; the
SHA-NI asm block clears xmm0–xmm7, its scratch and edx (the AES-NI block clears xmm0); each signer
is a plain wrapper around a callee holding the `secret var` block and burns 128 KB (P-256) /
160 KB (P-384) after the callee — epilogue included — has returned (`_ect_burn_stack` covers any
size with 8-byte stores, so signing time is unchanged; a short HMAC got faster).

**Part B — Verified.** sigil `tests/tcyr/ecdsa_sign.tcyr`: after each signer (and a `secret var` function
called right after it, so a register still holding k is spilled into the scanned region), no
32-bit word of k or d at any byte offset of 192 KB of dead stack, and nothing the signer wrote
survives past its burn; neither HMAC leaves its context, finalize scratch or inner hash. Red on
the first draft (21 / 24 words), on 3.13.7 (17 / 30), with only the SHA-NI clear removed (4), and
with an undersized burn. `tests/tcyr/ecdh.tcyr` scans 64 KB past ECDH's 8 KB burn the same way.
On x86_64, the pi, ecb, ach and cass.

**Part B — Not covered.** sigil's other `secret var` functions (Ed25519, X25519, HKDF, key parsers) until
the cyrius `EDEFER_RESTORE` fix lands; SHA compression frames below an HMAC / HKDF called
outside the signers (message schedule, working variables, a finalize temporary); the hashed key
of an HMAC-SHA256 / HMAC-SHA384 key longer than the block (64 / 128 bytes) in the one-shot
`sha256()` / `sha384()` dead frame.

## CVE-69 — a `secret var` fn's epilogue wrote its return registers into dead stack AFTER its own wipe: the defer walker's save area was released uncleared

*Appended 2026-10-03 (cyrius 6.6.15, lane src, item 1). Found by: the sigil 3.13.8 review — after `ecdsa_p256_sign` returned, words 0–3 of the RFC 6979 nonce k sat 212–224 bytes down in dead stack, directly above the signer's own 8 KB stack wipe (draft `cve-drafts/cyrius-secret-var-epilogue-spill.md`). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. CVE-68 is held by another 6.6.15 lane; this entry spends CVE-69. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | **Medium (P2)** — the CVE-46 / CVE-47 class: `secret var` is the language's guarantee that key material does not outlive its scope, and the mechanism that runs the wipe copied the return-convention registers below the stack pointer AFTER the wipe and left them there. Reading them needs a second primitive (an uninitialised stack read, a memory disclosure, a core dump), so not P1; but what it leaves is whatever those registers held at the return — in sigil 3.13.7, the ECDSA signing nonce, and k plus one signature (r, s) is the private key: d = r⁻¹(s·k − e). Not attacker-triggered; silent. |
| **Class** | Sensitive data left in released memory (CWE-226 / CWE-244): a compiler-generated spill that outlives a zeroisation. |
| **Affected** | Every fn holding a `secret var` or a `defer` (closures and generic instances included — they share the walker), on every native target: x86_64 ELF, PE, x86_64 Mach-O and the agnos kernel ELF (`src/backend/x86/float.cyr` — rdx, r8, xmm0, xmm1, the entry rsp, rax), aarch64 ELF and Mach-O (`src/backend/aarch64/emit.cyr` — x0–x3, q0, q1). From 6.6.7 (the bite-2 fix that widened the walker's save from rax alone — the value being returned — to the whole return convention, so a call in a defer body would not destroy the return value: CHANGELOG [6.6.7], "The defer walker kept only the FIRST return register") through 6.6.14. Before 6.6.7 the walker pushed rax / x0 only, which is the value the caller receives anyway. cx is not affected in the guest-visible sense: its save is six pushes onto cxvm's private data stack, which no guest address reaches (CVE-58). |
| **Files** | `src/backend/x86/float.cyr` `EDEFER_RESTORE`; `src/backend/aarch64/emit.cyr` `EDEFER_RESTORE` (called by `_defer_emit_walk`, `src/frontend/parse.cyr`) |
| **Fixed** | 6.6.15 |

**Vector.** Any fn with a `secret var` (or a `defer`) returns while a register in the saved set holds something secret-derived that is not the return value: a hash or cipher state in a vector register (SHA-NI / AES-NI leave theirs in xmm0/xmm1), the high half of a multiply in rdx, a key limb in r8 / x1–x3. The walker stored all of them in a 64-byte area below sp (`[rsp]` rax, `+8` rdx, `+16` r8, `+24` entry rsp, `+32` xmm0, `+48` xmm1 on x86_64; `stp x0,x1` / `x2,x3` / `q0,q1` on aarch64), ran the blocks — the `secret var` wipe among them — reloaded the registers and released the area by moving sp past it. Measured with the reproducer (a `secret var` fn whose last statement leaves a distinct marker in every saved register, then a sibling's uninitialised 4 KB window): 7 of 7 markers in dead stack on x86_64 (rax, rdx, r8, both halves of xmm0 and xmm1), 8 of 8 on aarch64 — the same fn without `secret` (no walker) leaves none. In sigil 3.13.7, xmm1 still held the SHA-NI state of the HMAC_DRBG's last round at `ecdsa_p256_sign`'s return — which is k — and the signer's `secret var` epilogue wrote it below its frame after its 8 KB stack wipe had run.

**Impact.** Secret material — whatever the return registers held — persists in released stack after the fn that was meant to destroy it returned, readable by any later uninitialised stack read or memory disclosure in the same process. For sigil 3.13.7 signing (and native-TLS CertificateVerify built on it): full recovery of the ECDSA private key from one signature plus the residue.

**Fix.** `EDEFER_RESTORE` clears the area after it reloads the registers and before it releases it. x86_64: reload xmm1, xmm0, r8, rdx, rax as before, `mov r11, [rsp+24]` (the entry rsp, out of its slot before the slot is cleared — r11 is already the walker's scratch), eight `mov qword [rsp+8i], 0` (immediate stores: no register of any return convention is touched), `mov rsp, r11`. aarch64: after the three `ldp`s, `stp xzr, xzr, [sp]`, `[sp, #16]`, `[sp, #32]`, `[sp, #48]`, then `add sp, sp, #64`. Unconditional — every fn with a walker, `defer` included (a `defer` body that wipes a key by hand has the same need) — and nothing else changes: fns without a `defer` / `secret var` are byte-identical. Cost: +74 bytes (x86_64) / +16 bytes (aarch64) per fn that has a walker, eight (four) stores per return of one. No other epilogue spill has this shape: a `secret var` fn never tail-calls (CVE-47's `_tc_frame_divert`), the regalloc restore and `leave; ret` only load, and a coroutine's completion (`_coro_mark_done`) pushes only the value being returned and the heap address it is stored at. A `#naked` fn has no epilogue at all, so its walker never ran — not this spill shape but the CVE-47 one (the wipe skipped); 6.6.15 refuses `secret var` / `defer` there (separate draft, `cyrius-naked-fn-defer-secret.md`).

**Behaviour change.** None observable: the area was dead after the release. Expression temporaries the fn's own body pushed below its frame are not the walker's and are not cleared — a `secret var` clears its array and, now, the walker's own copy of the return registers; it never promised to scrub every value the body computed.

**Verified.** `tests/tcyr/crossos/secret_epilogue_save_area.tcyr` (13 assertions): markers in every saved register via inline asm (x86 and aarch64 arms), a `secret var` fn that falls off its end right after loading them, a dead-stack window scan between rows that start from zeroed stack; anti-vacuous control (all eight markers left one frame down are visible to the window), a no-walker control (0), a plain-`defer` row (cleared too), and value rows (the return value, `(a, b)`, `(a, b, c)`, f64, f64v4 survive the clear). RED before the fix on x86_64 Linux (7 markers), qemu-aarch64 and real pi (8), ecb (8), ach (7), cass (3 rows), PE under wine; GREEN after on all of them. The sigil reproducer (`spill.cyr`): `secret var fn: xmm1*10+rdx hits = 11` → `0`. `tests/tcyr/crossos/defer_every_return_path.tcyr` (74/74, x86_64 / qemu-aarch64 / wine) and `tests/gates/codegen/defer_every_return_path.sh` (7 ok, including cx) still green. Self-host fixpoint, `seed-derive-cycc.sh`, every `src/main*.cyr` fork, `build/cycc-native-aarch64` regenerated; `cross-os-selfhost.sh <host> crossos` on pi, ecb, ach and cass: SELFHOST_OK and 171 / 171 crossos tests (the new one included) on each.

**Not covered.** cx: the walker's six pushes land on cxvm's data stack, which guest code cannot address (every guest address is bounded to `_cx_mem` since CVE-58) and which every cx expression spill shares; scrubbing it would be a VM decision (zero on pop), not this emitter's. Values the fn's own body spilled while computing on the secret (expression temporaries, the regalloc'd locals' frame slots) are outside what `secret var` covers, as before.

## CVE-70 — the native TLS stack never zeroed its ephemeral ECDHE private keys or shared secrets: every past connection's keys stayed in the process

*Appended 2026-10-03 (cyrius 6.6.15, lane ecdhe). Found by: the 6.6.15 ECDHE premise check (the TLS 1.2 client's new ECDHE zeroed its secrets; the paths it was compared with did not). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | P2 (Medium) — forward secrecy lost to any later memory read. Exploitation needs a second primitive (a heap over-read elsewhere, a core dump, swap, a debugger, a co-resident memory-disclosure bug); given one, every connection the process ever made or accepted is decryptable from a capture. |
| **Class** | Sensitive information in a resource not removed before reuse (CWE-226); improper clearing of heap memory before release (CWE-244). |
| **Affected** | Every native-TLS client and server (the default `lib/tls.cyr` backend and every direct `tls_native_*` user), TLS 1.3 both sides and the TLS 1.2 server, through 6.6.14. On the default global heap (`tls_connect_alloc` / `tls_accept_alloc` with `a == 0`, which never frees) for the life of the process; on an arena until it was reset AND the bytes reused. |
| **Files** | `lib/tls_native_hs13.cyr` (`tls_native_client_build_hello`, `tls_native_client_parse_server_hello`, `_tn_gen_ephemeral_x25519`, `tls_native_server_respond_hello`, `tls_native_server_derive_handshake`), `lib/tls_native_hs12.cyr` (`_tn_12_server_drive`), `lib/tls_native_conn.cyr` (`tls_native_connect`, `tls_native_accept`, `_tn_wipe_ephemeral`) |
| **Fixed** | 6.6.15 |

**Vector.** Every native handshake stored its ephemeral private key (`TLS_CTX_OFF_EPH_PRIV`) and its ECDHE shared secret / TLS 1.2 premaster (`TLS_CTX_OFF_SHARED`) in buffers from the ctx's allocator and never cleared them — not after use, not when the handshake finished, not when it failed. An attacker who can read the process's memory later reads them out.

**Impact.** With the peer's public share from a recorded capture, the private key gives the shared secret; with the shared secret and the transcript, every traffic key of that session — for every past session still in memory. Forward secrecy is exactly the property that the ephemeral secrets are gone once the handshake secret exists.

**Fix.** The step that uses each secret zeroes it at once — the private key once the shared secret exists (and a TLS 1.3 client's first share's key when a HelloRetryRequest replaces it), the shared secret once the handshake / master secret is derived — and `tls_native_connect`, `tls_native_accept` and `tls_native_accept_12` wipe both again on every exit (`_tn_wipe_ephemeral`). Every library-allocated buffer is 48 bytes, so one wipe fits every group.

**Verified.** `tests/tcyr/crossos/tls_native_ecdhe_groups.tcyr` asserts on every host that neither side holds a byte of either secret after every row (success, refusal, failed write) AND when its next flight goes out, so an inline wipe removed is RED rather than masked by the driver's wipe (mutants MG11–13, MW1–7 RED); `tests/tcyr/crypto/tls_native_scaffold.tcyr` pins the primitive-level wipes; `tests/tcyr/crossos/tls_native_client_auth.tcyr` covers the 1.2 client. Cross-OS: pi, ecb, ach and cass.

**Not covered.** The traffic and handshake secrets the key schedule derives live as long as the ctx (they are needed for the connection); a ctx on the global heap is never freed — reclaim with an arena (`tls_*_alloc_in` + `reset_via`). The libssl backend's secrets are libssl's.

## CVE-71 — native TLS 1.3 accepted an all-zero x25519 shared secret

*Appended 2026-10-03 (cyrius 6.6.15, lane ecdhe). Found by: the 6.6.15 ECDHE work (one shared ECDHE step for every side and version). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | P3 (Low) — an RFC 8446 MUST (contributory behaviour) not met; not a key-recovery path on its own, because TLS 1.3's authentication covers the substituted share in every configuration where the attacker gains anything. |
| **Class** | Improper validation of an input's specified property (CWE-1284 / CWE-325-adjacent: a missing required cryptographic step). |
| **Affected** | The native TLS 1.3 client and server (default backend), from the native 1.3 stack's introduction through 6.6.14. The TLS 1.2 path always checked (`tls_native_12_compute_premaster`). |
| **Files** | `lib/tls_native_hs13.cyr` (`tls_native_client_parse_server_hello`, `_tn_gen_ephemeral_x25519`), now one `_tn_ecdhe_shared` for every side and version |
| **Fixed** | 6.6.15 |

**Vector.** RFC 8446 §7.4.2: "For X25519 and X448, implementations MUST check whether the computed Diffie-Hellman shared secret is the all-zero value and abort if so." sigil's `x25519` does not signal a low-order input, and neither TLS 1.3 side checked its result. A peer — or, toward a server, anyone able to rewrite the ClientHello — that sends a low-order point (u = 0, u = 1, …) fixes the shared secret at zero, so the handshake secret becomes a public function of the transcript.

**Impact.** Limited: toward the client, the server's CertificateVerify covers the substituted share; toward a server without client authentication the attacker could simply connect itself; with client authentication, the client's CertificateVerify covers the real ClientHello.

**Fix.** `_tn_ecdhe_shared` serves both versions and both sides: x25519 with an all-zero result refused (illegal_parameter), the NIST curves through sigil's validating `ecdh_p*_shared` (SP 800-56A).

**Verified.** `tests/tcyr/crossos/tls_native_ecdhe_groups.tcyr`: an all-zero x25519 share is refused with illegal_parameter by the 1.3 client (ServerHello), the 1.3 server (ClientHello) and the 1.2 server (ClientKeyExchange); mutant MG10 RED on all three. Cross-OS: pi, ecb, ach and cass.

**Not covered.** X448 (not implemented).

## CVE-72 — a `secret var` (or `defer`) in a `#naked` fn compiled clean and never ran: a naked fn has no epilogue for the walker

*Appended 2026-10-03 (cyrius 6.6.15, lane src, fix pass). A CVE-47 residual: the same "the wipe is skipped" shape on a different return path. Found by: the 6.6.15 review of CVE-69's epilogue survey. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | **Low (P3)** — the CVE-46 / CVE-47 guarantee (key material does not outlive its scope) broken silently, but only on a construct no one in `~/Repos` writes: a `secret var` inside a `#naked` fn (a hand-written asm body, normally an ISR or setjmp). Not attacker-triggered |
| **Affected** | `src/frontend/parse.cyr` (`_PARSE_DEFER`, the `secret var` branch of the statement parser), every native target (x86_64 ELF / PE / both Mach-O, aarch64 ELF / Mach-O). Not cx: `#naked` is inert there (the fn is framed and its epilogue runs). Since `#naked` landed (6.2.27) through 6.6.14 |
| **Vector** | `#naked fn f() { secret var k[16]; ... asm { ... ret ... } }` — or a `defer { ... }` in the same position |
| **Fixed in** | 6.6.15 |

### What it is

A `#naked` fn gets no prologue, no frame and no epilogue: its body ends in its own asm return
(`ret` / `iretq` / `eret`). `PARSE_RETURN` already refused `return` there, because the epilogue a
`return` jumps to does not exist. But `secret var` and `defer` register blocks that ONLY the
epilogue's defer walker runs, and nothing refused them: the walker was emitted after the body,
unreachable, so the `secret var`'s zeroise never ran and a `defer` block never ran. Both
compiled with exit 0 and no diagnostic. A naked fn also has no frame, so the defer's reached-flag
and the secret array's slots were addressed through the CALLER's rbp.

Measured on 6.6.14 / the 6.6.15 base: `#naked fn f(): i64 { secret var k[16]; asm { 0xC3; } }`
compiles (rc 0, no diagnostic); `var _g = 0; #naked fn f() { defer { _g = 5; } asm { 0xC3; } }`
called from `main`, then `return _g;`, exits **0** (want 5).

### Fix

`_PARSE_DEFER` and the `secret var` branch refuse their statement when `_cur_fn_naked == 1`,
mirroring `PARSE_RETURN`: `defer is not allowed in a #naked fn (it has no epilogue to run the
block)` / `secret var is not allowed in a #naked fn (it has no epilogue to zeroise it)`, no
binary. A closure body inside a naked fn is its own framed fn (the nested-fn snapshot resets
`_cur_fn_naked`), so it is unaffected; on cx `#naked` is never armed, so a `defer` there still
runs (probe: exit 5). Survey: no `#naked` fn in `~/Repos` (57 files carry `#naked`) holds a
`defer` or `secret var`.

### Verified

`tests/gates/diagnostics/defer_misuse_refused.sh`: two refusal rows (the two probes above) and a
control (a `#naked` fn beside a fn whose `secret var` and `defer` still run, exit 5). Against the
pre-fix `parse.cyr`: 28 passed, 2 failed; after: 30 passed. Refused on the x86_64, aarch64
(cross and native, the latter under qemu-aarch64) and PE forks. Self-host fixpoint,
`seed-derive-cycc.sh` GREEN, `build/cycc-native-aarch64` regenerated, `cross-os-selfhost.sh
<host> crossos` on pi, ecb, ach and cass.

### Not covered

A plain `var` in a `#naked` fn is still accepted and, with no frame, stores through the caller's
rbp (`#naked fn f() { var q = 7; asm { 0xC3; } }` emits `mov [rbp-8], rax; ret` — a write into
the caller's frame). That is not a zeroisation defect and it is outside this finding; no `#naked`
fn in `~/Repos` declares a `var`, so refusing it would break nothing measured. Reported to the
integrator for the backlog, not changed here.

## CVE-73 — on Windows, folded sigil's trust helpers probed drive-relative rooted POSIX paths any local user can plant

*Appended 2026-10-03 (cyrius 6.6.15, sigil 3.13.9 refold). Found by: a cyrius review of sigil named the TPM helpers (6.6.14 lanes, in passing); sigil's pin-bump work then found the same class in every trust core (sigil audit `docs/audit/2026-10-03-3.13.9-pin-bump-windows-rooted-paths-audit.md` §F8). The class of CVE-54, CVE-57 and CVE-65, in a folded stdlib (CVE-57's precedent). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.15 spends CVE-68 … CVE-73.*

| | |
|---|---|
| **Severity** | P2 (Medium) — a local, unprivileged user on the same Windows machine chooses the answers other users' programs get to trust questions, and receives a LUKS key. Only against a program that calls these helpers on Windows (they serve Linux mechanisms), but they are public. |
| **Class** | Untrusted search path / externally controlled reference to a resource in another sphere (CWE-426, CWE-610). |
| **Affected** | sigil's TPM, Secure Boot, IMA, dm-verity and LUKS helpers in `lib/sigil.cyr` on Windows, from sigil 3.8.1 (the trust cores internalized; the same code came from agnosys before) through 3.13.8, i.e. every cyrius fold through 6.6.14. |
| **Files** | sigil `src/sys_util.cyr` (new `agnosys_rooted_paths_untrusted()`), `src/tpm_core.cyr`, `src/secureboot_core.cyr`, `src/ima_core.cyr`, `src/dmverity.cyr`, `src/luks.cyr` — folded as `lib/sigil.cyr` |
| **Fixed** | sigil 3.13.9 (cyrius 6.6.15 refold) |

**Vector.** On Windows a rooted path is drive-relative: `"/dev/tpmrm0"` opens `C:\dev\tpmrm0`, and any authenticated user may create folders at the root of the system drive. Measured on cass with each probed path planted at the root of a scratch drive: `tpm_detect` / `tpm_available` reported a TPM; `_sb_tool_in` resolved a planted `C:\usr\bin\mokutil` (spawning it was refused by the subprocess helpers); `ima_get_status` reported IMA active with the planted measurement count, `ima_read_measurements` returned the planted log and `ima_write_policy` wrote into the planted file; `dmverity_supported` said yes; `luks_write_keyfile` staged the LUKS key in a planted `C:\tmp` owned by the other user; `luks_close` answered Ok.

**Impact.** Attacker-chosen answers to "is there a TPM", "what did IMA measure", "is dm-verity available" for any program calling these helpers on Windows, and disclosure of a LUKS key staged into a directory the attacker owns.

**Fix.** `agnosys_rooted_paths_untrusted()` answers 1 on Windows; every trust-core probe of a fixed rooted path asks it first and fails closed (`tpm_detect` 0; the TPM operations, the Secure Boot variable list and sign-file fallback, `ima_read_measurements` / `ima_write_policy`, `luks_keyfile_path` / `luks_close` Err; `secureboot_detect_state` SB_NOT_SUPPORTED; `ima_get_status` inactive; `dmverity_supported` 0). Nothing changes off Windows.

**Verified.** sigil `tests/tcyr/rooted_paths.tcyr` and `scripts/cass-rooted-paths.sh` (every probed path planted on a `subst` scratch drive on cass: each helper fails closed at 3.13.9, each answered from the planted file at 3.13.8). cyrius: `lib/sigil.cyr` is 3.13.9's `dist/sigil.cyr` byte for byte; the cyrius suite and the cross-OS leg pass on the fold.

**Not covered.** Paths a CALLER supplies on Windows (`secureboot_read_efi_variable(path)`, `tpm_seal`'s `output_dir`, trust-store and keyring paths) are drive-relative too if rooted — the caller's to resolve (sigil audit §F8, *Not covered*).

## CVE-74 — a plain-socket write to a peer that had reset the connection raised SIGPIPE: any peer could kill a `lib/net.cyr` client or server process that had not ignored the signal (sock_send*, http, ws, ws_server, yantra, sandhi's client paths, the async writers)

*Appended 2026-10-05 (cyrius 6.6.16, lane net, bite net-1, item N1). Found by: CVE-66's own
vidya field note, which listed `lib/net.cyr`'s plain writers as "the open instance", and roadmap
backlog (the 6.6.14 sweep). Not part of the 2026-09-03 sweep: recorded here because this is the live
ledger. 6.6.16 spends CVE-74 … CVE-76.*

| | |
|---|---|
| **Severity** | P1 (High) — availability, remote and unauthenticated. Any peer ends the WHOLE process (every connection and thread of a server, not one) by closing its end before the victim's next write: a client that disconnects while a server writes its response, or a server that drops a client mid-request. Not P0: no code execution or data exposure, and a process that ignored SIGPIPE itself (`signal_ignore(SIGPIPE)`; sandhi's servers since 1.6.6) was never exposed. |
| **Class** | Uncaught exception / improper handling of an exceptional condition (CWE-248, CWE-755): a process-fatal signal raised by a library on peer-controlled input (CWE-400 class). The plain-socket instance of CVE-66's class. |
| **Affected** | Every program on Linux (x86_64, aarch64) or macOS (arm64, x86_64) that writes a TCP (or other stream) socket through the stdlib and had not ignored SIGPIPE, from the earliest `lib/net.cyr` through 6.6.15: `sock_send`, `sock_send_all`, `sock_send_a` — and so `lib/http.cyr` (requests), `lib/ws.cyr` (client frames), `lib/ws_server.cyr` (`ws_server_handshake`, `ws_server_send_frame` and every sender on it), `lib/yantra.cyr`, and the folded sandhi's CLIENT paths (its servers have ignored SIGPIPE since sandhi 1.6.6); the async backends' `async_send` (epoll task: a raw `SYS_WRITE`; kqueue task: `sys_write`) and `async_relay_once` (both backends). Windows (Winsock `send`, `async_win`'s `WSASend`) and agnos (`sock_send#48` answers -1 for a dead connection) raise no such signal. A pipe or a file written through these verbs keeps `write(2)`'s semantics, SIGPIPE included (no per-call flag exists for one). |
| **Files** | `lib/syscalls.cyr` — new private `_fd_write_nosigpipe`; `lib/net.cyr` — `_net_os_send` (the non-Windows arm, the one choke point under the three `sock_send*` verbs); `lib/async.cyr` — `_async_send_task`, `async_relay_once`; `lib/async_macos.cyr` — `_async_send_task`, `async_relay_once` |
| **Fixed** | 6.6.16 |

**Vector.** The peer closes its socket (a FIN). The victim's next write reaches a closed socket,
whose kernel answers with an RST; the write after that fails with EPIPE, and a flagless `write(2)` on
a socket raises SIGPIPE with it. On Linux the RST arriving in CLOSE_WAIT sets `sk_err = EPIPE` and
`sk_stream_error` sends the signal unless the send carries `MSG_NOSIGNAL` (a write that instead finds
`ECONNRESET` pending returns it without a signal, and the NEXT write is EPIPE with one); on macOS
`sosend` answers EPIPE for `SS_CANTSENDMORE` and signals unless the socket has `SO_NOSIGPIPE`. A
socket the writer shut down both ways itself (`sock_shutdown(fd, 2)`) is killed on its first write
the same way. Nothing in `lib/` ignored SIGPIPE for these callers: `lib/http.cyr`, `lib/ws.cyr` and
`lib/ws_server.cyr` never call `signal_ignore`.

**Impact.** Denial of service: the process dies (`128 + 13 = 141`), taking every connection and every
thread with it. Measured against the 6.6.15 lib with SIGPIPE at `SIG_DFL`, a loopback pair whose
accepted end was closed: the planning probe (`sock_send_all` in a loop) printed `11` and exited 141
on x86_64 Linux, qemu-aarch64, pi (aarch64, kernel 7.0.0-1020-raspi), ecb (macOS 27.0.1 arm64) and ach
(macOS 13.7.8 x86_64); and all seven reset rows of the new test — `sock_send_all`, `sock_send`,
`sock_send_a`, a socket shut down both ways before its first write, `ws_server_send_frame`,
`async_send` on the epoll / kqueue runtime, and `async_relay_once` from a pipe into the reset socket —
read child exit 141 on x86_64, qemu-aarch64, pi, ecb and ach (`10 passed, 7 failed (17 total)` on each).

**Fix.** ONE private leaf, `_fd_write_nosigpipe(fd, buf, n)` in `lib/syscalls.cyr`, under every
plain-socket writer, so `lib/net.cyr` and both async backends cannot drift (the TLS transport keeps
its own per-ctx-cached copy, `_tn_os_write` / `_tn_nosigpipe`, from CVE-66). The process-wide signal
disposition is never touched.
- **Linux** (x86_64 and aarch64): `sys_sendto(fd, buf, n, 0x4000 /*MSG_NOSIGNAL*/, 0, 0)` —
  `SYS_SENDTO` 44 on x86_64, the native 206 on aarch64, no ESYSXLAT row involved. With no destination
  it is `write(2)` on a connected socket, honouring O_NONBLOCK and SO_SNDTIMEO the same way (both are
  `tcp_sendmsg`), so `sock_send_all`'s short-write contract is unchanged. `ENOTSOCK` (-88) falls
  through to `write(2)`.
- **macOS** (arm64 and x86_64): `setsockopt(fd, SOL_SOCKET 0xFFFF, SO_NOSIGPIPE 0x1022, &1, 4)` on
  every call (both Mach-O backends route `sys_setsockopt` to BSD 105). Per call rather than at
  socket creation because sandhi creates IPv6 sockets with a raw `sys_socket` that never passes
  through `tcp_socket`. xnu answers `EINVAL` for a socket already shut down both ways — what an RST
  leaves — and that is answered `-EPIPE` with NOTHING written, the errno the write would have given,
  minus the signal (failing closed: writing after a refused `SO_NOSIGPIPE` is the hole itself).
  `ENOTSOCK` (-38: a pipe or a file) writes; any other refusal is returned. (Darwin does define
  `MSG_NOSIGNAL` — 0x80000, measured working on 13.7.8 — but it is not relied on.)
- Every target's tail is `write(2)`: the pipe / file fallback on POSIX; on agnos the peer's #48
  route; on PE / EFI / cx it is unused by net.cyr (the Winsock arm is unchanged) or harmless.
- `_net_os_send`'s non-Windows arm, `lib/async.cyr`'s `_async_send_task` (was a raw `SYS_WRITE`) and
  `async_relay_once`, and `lib/async_macos.cyr`'s `_async_send_task` and `async_relay_once` call it.

**Behaviour change.** A plain-socket writer that has not ignored SIGPIPE now survives a peer reset:
`sock_send_all` returns `-EPIPE` (or `-ECONNRESET`), `sock_send` / `sock_send_a` return
`Err(EPIPE)` / `Err(ECONNRESET)`, `ws_server_send_frame` and the http / ws senders return their
negative error, `async_send`'s task and `async_relay_once` a negative count. On macOS a socket shut
down both ways answers `-EPIPE` without a write being attempted (the errno the write itself would
give). No public API change. ⚠ **The syscall set changes:** on Linux every such socket write is
`sendto(2)` (44 x86_64 / 206 aarch64) instead of `write(2)` — `write(2)` remains only for an fd that
is not a socket — and on macOS each send adds one `setsockopt(2)`. A seccomp allowlist that admits
`write` but not `sendto` now SIGSYS-kills a self-confined plain-socket writer on its first send; a
fallback cannot help, because a seccomp kill is not an error return. kavach's `basic` filter is one
(read from its source and measured in a probe: `security_create_basic_seccomp_filter`, kill on a
miss); its sandboxed spawn paths use the exec deny-list filter and are not affected. Filed for
kavach as a consumer note.

**Verified.** `tests/tcyr/crossos/net_plain_write_peer_reset.tcyr` (new, in the release gate's
cross-OS set; 17 assertions on POSIX, 7 on Windows). Each reset row runs in a child — a `fork()` on
POSIX (no execve, so the file also runs under qemu-aarch64 without binfmt), the test spawning itself
on Windows — that sets SIGPIPE to `SIG_DFL` first, builds its own loopback pair, closes the accepted
end, writes through one path until a write fails and then three more times, and must exit 0: every
write after the reset `< 0`, the first errno in the accepted set (Linux {32, 104}, Darwin {32, 54};
never one exact value — which one a write sees depends on whether the peer's FIN or its RST was
processed first), and alive. A POSIX control child writing the same reset connection with a raw
`write(2)` must die 141, so a host that would not have killed the writer cannot pass the rows
vacuously. Pipe and file rows pin the ENOTSOCK fallback (every byte written and read back).
17/17 on x86_64 Linux, qemu-aarch64, pi, ecb and ach (10 consecutive runs each on pi, ecb and ach,
20 on x86_64, 16 concurrent copies on x86_64); 7/7 on cass (8 consecutive runs) (Windows rows 1-5, observed
`WSAECONNABORTED` 10053 and `WSAESHUTDOWN` 10058); the observed first errno on every POSIX host and
path was EPIPE (32). Against the 6.6.15 lib all seven reset rows read 141 on x86_64, qemu-aarch64,
pi, ecb and ach. Mutants, each RED: `_net_os_send` alone back to `write(2)` — rows 1-5 at 141 (x86_64);
the async writers alone back to `write(2)` — the `async_send` and relay rows at 141 (x86_64); the
ENOTSOCK fallback removed — the pipe and file rows read -88 (x86_64); the macOS EINVAL arm made to
write anyway (fail open) — the shut-down-first row at 141 on ecb and ach. The planning probe exits 7
with the write returning -32 (was 141) on x86_64, qemu-aarch64, pi, ecb and ach.
`sock_send_all_short_write`, `tls_native_socket_transport`, `http_connect_by_name`,
`async_macos_verbs`, `async_relay_once_no_deadlock` (and `http_short_send`, `net_loopback_tcp`,
`ws_client_short_write`, `ws_server_socket_reads`) green on pi, ecb, ach and cass; all 69 `.tcyr` that
include net / async / ws / http / tls exit 0 on x86_64. `tcyr_corpus_cross_compiles.sh` green (PE,
both Mach-O, agnos); the leaf also compiles and runs on cx (cxvm).

**Not covered.** A pipe or a file written through these verbs keeps `write(2)`'s SIGPIPE — neither OS
has a per-call flag for one, and the process-wide disposition is the application's
(`signal_ignore(SIGPIPE)`). A raw `sys_write` / `syscall(SYS_WRITE, ..)` a consumer issues on a
socket itself is the consumer's. UDP never raises SIGPIPE (`net_dns_query_ipv4`, `async_resolve`'s
connected UDP send are unaffected either way). Windows and agnos were never exposed.

## CVE-75 — the native TLS chain verifier ignored a CA's extendedKeyUsage: a CA confined to another purpose could issue a TLS server identity (client side) or a TLS client identity (mTLS server side)

*Appended 2026-10-05 (cyrius 6.6.16, lane tls, bite tls-2, item N3). Found by: the 6.6.16 planning premise checks (roadmap backlog: "the chain verifier checks only the LEAF's extendedKeyUsage, never a CA's own"), which built the chains with OpenSSL 3.6.5 and ran them through `_tn_verify_chain` and `openssl verify`. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. This is the verifier-too-lenient class of CVE-63 (an IP literal matched against dNSName) and CVE-67 (`*.com`). 6.6.16 spends CVE-74 … CVE-76.*

| | |
|---|---|
| **Severity** | P2 (Medium) — trust-policy bypass. Exploitation needs control of a CA the verifier trusts or chains through whose extendedKeyUsage confines it to another purpose: an S/MIME-, clientAuth- or codeSigning-only issuing CA under a root the client trusts, or a serverAuth-only CA in an mTLS server's trust set. With one, the native stack accepts an identity OpenSSL, the libssl backend and Windows' chain engine refuse. Public WebPKI roots carry no EKU (0 of the 122 in `/etc/ssl/cert.pem`, measured), so the realistic exposure is private and enterprise PKI and custom trust bundles (`tls_ctx_load_verify_locations`, `tls_native_set_ca_bundle`). Not P1: the attacker needs a constrained CA's signing key. |
| **Class** | Improper certificate validation (CWE-295) — an X.509 constraint on a CA not enforced during path validation (RFC 5280 §4.2.1.12; the CA/Browser Forum treats a CA's EKU as a technical constraint on what it issues). |
| **Affected** | The native TLS client's server-chain verification — `tls_connect*` under the native backend (the default), `tls_native_connect`, `tls_native_client_verify_chain` — from 6.0.29 (the native chain verifier) through 6.6.15; the native TLS server's client-certificate verification (`tls_accept*` / `tls_native_accept` with `tls_set_verify` PEER or FAIL_IF_NO_PEER_CERT), TLS 1.3 and 1.2, from 6.6.14 (CVE-64) through 6.6.15. Every target. The libssl backend was never affected (OpenSSL checks it). |
| **Files** | `lib/tls_native_hs12.cyr` — new `_tn_eku_purpose_ok`; `_tn_ca_signer_ok` (gains `purpose`); `_tn_leaf_purpose_ok` (delegates its EKU half); `_tn_verify_chain` (passes `purpose` at both CA checks); `docs/development/lib-tls-contract.md` (Verification and mTLS rows) |
| **Fixed** | 6.6.16 |

**Vector.** `_tn_verify_chain` applied the chain's purpose — `_TN_PURPOSE_SERVER` for the client verifying a server, `_TN_PURPOSE_CLIENT` for an mTLS server verifying a client — to the leaf alone (`_tn_leaf_purpose_ok`, CVE-17). For a CA, intermediate or trust root, it checked keyCertSign and pathLen (`_tn_ca_signer_ok`) and never its extendedKeyUsage. So (1) toward the native CLIENT: a leaf issued by an intermediate whose EKU is clientAuth-only, codeSigning-only or emailProtection-only — or anchored directly at a trusted root carrying such an EKU — verified as a TLS server identity; (2) toward a native mTLS SERVER: a client leaf issued by a serverAuth-only CA the server trusts (as a root or an intermediate) verified as a client identity. Measured on the 6.6.15 lib with openssl-generated P-256 chains: all 16 wrongly purposed rows of the verdict table (anchor at depth 0 and 1, intermediate; serverAuth / clientAuth / codeSigning CAs against the opposite purpose; a pair and a bundle with no rightly purposed candidate; the public verb) returned `TLS_OK`; `openssl verify -purpose sslserver | sslclient` refuses every one with error 26 (unsuitable certificate purpose) — and checks the trust anchor's EKU too (a plain PEM root carries no auxiliary trust). End to end, a native server trusting a serverAuth-only CA authenticated that CA's clientAuth leaf over TLS 1.3 and 1.2 (`tls_accept_complete` succeeded and `tls_get_peer_spki_der` named the client).

**Impact.** Toward the client: a man-in-the-middle holding a leaf from a CA whose EKU should have kept it out of TLS server authentication impersonates any host that leaf names to a native-TLS client trusting that CA's root. Toward an mTLS server: the holder of a client leaf from a CA the server trusts only for server certificates authenticates as that client. Hostname binding (CVE-18 / CVE-63 / CVE-67), validity, signatures, keyCertSign and pathLen were all still checked.

**Fix.** `_tn_eku_purpose_ok(cert, purpose)` is the one extendedKeyUsage rule, applied at every depth: an absent extension imposes no restriction; the server purpose needs serverAuth, the client purpose clientAuth (read from the DER, as sigil records the serverAuth bit only); anyExtendedKeyUsage satisfies either. `_tn_leaf_purpose_ok` keeps its keyUsage half and delegates the EKU half to it (the leaf's verdicts are unchanged), and `_tn_ca_signer_ok(ca, below, purpose)` applies it to every CA it vets — the anchoring root and every intermediate — inside the conjunction `_tn_verify_chain` uses to SELECT a candidate, so a wrongly purposed CA is skipped and path building continues to a rightly purposed one (a cross-signed or re-issued CA sharing its subject and key); it is never fatal on its own. The trust anchor is checked like any CA, as OpenSSL does for a root without auxiliary trust. No public API change, no new error value (`TLS_ERR_CERT_INVALID`, as for any chain that does not verify).

**Behaviour change.** Native chains through a CA or root whose extendedKeyUsage leaves out the chain's purpose are refused (`TLS_ERR_CERT_INVALID`; on an mTLS server the client is sent bad_certificate), as OpenSSL and the libssl backend already refused them. Two deliberate differences from OpenSSL 3.6.5 remain, both pinned by the test: anyExtendedKeyUsage satisfies the purpose at every depth (RFC 5280; OpenSSL honours it at none — an anyEKU-only leaf, intermediate or root fails there); and OpenSSL fails on the first issuer candidate it picks when that one is wrongly purposed, where the native verifier tries the next — so native accepts such a chain only when a fully valid, rightly purposed path exists.

**Verified.** `tests/tcyr/crypto/tls_native_ca_eku.tcyr` (82 assertions): openssl-generated P-256 families — five roots and five intermediates, each family one subject and one key, differing only in EKU (absent / serverAuth / clientAuth / codeSigning / anyEKU) — and two leaves fit for both purposes, valid 2025-2049 and read at a pinned 2030-01-01; the rule on each fixture; the verdict table for the trust anchor at depth 0 and depth 1 and for the intermediate, both purposes; path building over duplicate-subject intermediates and over multi-root PEM bundles in both orders; `tls_native_client_verify_chain`. The header records `openssl verify`'s verdict per row. The 6.6.15 lib fails exactly the 16 refusal rows. `tests/tcyr/crossos/tls_native_client_auth.tcyr` (+37 assertions, 297): a clientAuth leaf from a serverAuth-only CA is refused by a native server trusting that CA, TLS 1.3 and 1.2, and authenticated by one trusting the CA's EKU-less twin (same subject and key) — the 6.6.15 lib fails the 8 refusal assertions; it runs at the release gate on ecb, ach, cass and pi. Mutations measured RED: the CA EKU check removed (16 unit rows, the 8 crossos assertions); the anchor's / intermediate's check fed the server purpose whatever the chain's (5 / 3); a wrongly purposed intermediate / root made fatal instead of skipped (4 / 2); an absent EKU read as restricting (26); anyEKU dropped for the client purpose (5). The CVE-17 rows and every other client-auth row are unchanged. x86_64, and qemu-aarch64 locally.

**Not covered.** (1) anyExtendedKeyUsage stays honoured at every depth (above) — a policy choice, not a residual; flipping it is one line and also changes the leaf rule. (2) The native verifier has no policy-constraints / certificate-policies processing and no name constraints (unchanged; a root carrying Windows root-program name constraints is refused whole by the Windows store reader, CVE-65). (3) sigil's own `x509_verify_chain` primitive takes no purpose; nothing in the TLS stack calls it (the native stack uses only its `_x509_verify_link` signature check).

## CVE-76 — a `[deps.X] tag` was joined into the dep-cache path unchecked: `cyrius deps` created directories outside the cache, and printed `rm -rf` advice for a directory outside it (a CVE-62 residual)

*Appended 2026-10-05 (cyrius 6.6.16, lane tool, bite tool-3, item T1). Found by: the 6.6.13 lanes'
reviews (roadmap backlog, "`cyrius deps` joins the `tag` value into `<home>/deps/<name>/<tag>`
unchecked"); re-measured, and the `rm -rf` shape found, by the 6.6.16 T1 premise check. Not part of
the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.16 spends CVE-74 … CVE-76.*

| | |
|---|---|
| **Severity** | P2 (Medium) — directory creation outside the dep cache, driven by any manifest in the dep graph including a transitive dependency's, plus a destructive command PRINTED as advice for a path outside the cache (the user must run it; nothing deletes it on its own). Not P1 like CVE-62: git rejects the traversal ref before it writes a checkout, so only empty leading directories are created, and no bytes are written into an existing file. |
| **Class** | Path traversal (CWE-22) on a manifest field; a CVE-62 residual (CVE-62 added `_dep_reject_unsafe_name` for the `[deps.NAME]` header only), itself a CVE-32 residual. |
| **Affected** | every cyrius with named git deps through 6.6.15 — the tag has been joined into the clone dir since named git deps landed; the `rm -rf <cache path>` advice since 6.6.5, when the tampered-cache refusal (`_git_cache_refuse`, the CVE-43 release) began naming the cache path and a recovery. |
| **Files** | `cbt/deps.cyr` — `_process_named_deps` (the `tag` key, then the clone-dir build `<home>/deps/<name>/<tag>`, `sys_mkdir`, `is_dir`, `git clone`, and `_git_cache_refuse` on an existing dir with no readable `.git`) |
| **Fixed** | 6.6.16 |

**Vector.** A `cyrius.cyml` — the consumer's own, or the manifest of ANY transitive dependency,
which `cyrius deps` (and `cyrius build`'s auto-deps) read in the Phase 3 walk — declaring a
`[deps.<name>]` with `git`, a `tag` holding `..` components, and `modules` (or none: the
modules-less default clones too).

**Impact.** Measured on 6.6.15 (the tree with the new call removed, throwaway `CYRIUS_HOME` =
`<W>/home`, local `file://` origin):
- `tag = "../../../esc/sub"` (root manifest) and `tag = "../../../esc/t"` (a transitive dep's
  manifest): `git clone --depth 1 -q -b <tag> -- <url> <home>/deps/foo/../../../esc/sub` exits on
  `fatal: Remote branch ../../../esc/sub not found`, but has already created `<W>/esc`, OUTSIDE
  `$CYRIUS_HOME`; git removes only the last component it created. `cyrius deps` exits 1. With the
  default home (`~/.cyrius`), `../../../esc/sub` creates `$HOME/esc`: three `..` leave
  `CYRIUS_HOME`, and four leave `$HOME`.
- `tag = "../../.."`, which resolves to an EXISTING directory (`<home>/deps/foo/../../..` = `<W>`,
  the parent of `CYRIUS_HOME`): `is_dir` is true, so no clone is attempted; the dir has no readable
  `.git`, so the tampered-cache refusal prints
  `cache: <W>/home/deps/foo/../../..` and
  `or: rm -rf <W>/home/deps/foo/../../..   (re-clones from the remote on the next resolve).`
  Under the default `~/.cyrius` that path is `$HOME`. `..` names the whole dep cache and `../..`
  names `$CYRIUS_HOME` the same way. A user following the advice deletes their home directory.
- On PE (no fork) an existing outside dir would instead be vendored as-is through the
  no-git warning path (from reading the code; not run on cass).

**Fix.** `_dep_reject_unsafe_tag(tag)`, beside `_dep_reject_unsafe_name`, is called right after the
section's key loop — before the optional / target gates and before any mkdir, clone or `is_dir` —
and only when a `tag` key is present (`dep_tag != 0`; a tagless dep, the common shape, is never
checked). It refuses: an empty value (a literal `tag = ""`), `..` anywhere, a leading `/` or `-`,
any path component starting with `.`, a backslash (a Windows separator), and control bytes
(< 0x20, 0x7F). A `/` inside the tag stays legal: `release/1.0` is a valid git tag and the clone
dir stays under `<home>/deps/<name>/`. Git refnames can never contain `..`, a leading `-` or a
`.`-led component, so no real tag is lost. A refused section prints
`error: [deps.<name>] tag '<tag>' is not a usable tag (it would make the cache path leave <home>/deps/<name>) — section refused`
— the tag's non-printing bytes shown as `\xNN` so a hostile manifest cannot put a terminal escape
on the user's screen — with no derived path and no `rm -rf` advice; it counts an error (exit 1, no
`cyrius.lock` written) and the walk continues. With the name (CVE-62) and the tag both validated,
the clone dir is always inside `<home>/deps/<name>/`, so `_git_cache_refuse`'s advice needs no
change. Same function for the root and every transitive manifest.

**Not covered (backlog, roadmap "Found by the 6.6.16 planning premise checks").** The read side:
a `modules` entry with `../` or an absolute path, and a transitive manifest's `path`, can vendor
any local file into the consumer's `lib/` (information disclosure, no write outside `lib/`).

**Survey.** 75 repos in `~/Repos` carry `[deps.X]`; every tag is a plain `X.Y.Z`. Nothing is
newly refused.

**Verified.** `tests/gates/toolchain/deps_modules_default_or_warned.sh` axis D9 (throwaway `HOME` +
`CYRIUS_HOME`, local `file://` origins, git calls logged through a PATH shim):
- D9a root `../../../esc/sub` — refused by name, rc 1, git never invoked, a find snapshot outside
  `$CYRIUS_HOME/deps` unchanged, no lock;
- D9b `../../..` naming an existing dir — refused, rc 1, no `rm -rf` and no real path in the
  output, git never invoked;
- D9c the same class from a TRANSITIVE manifest — refused, the bad dep's origin never fetched,
  nothing outside the cache, no lock;
- D9d `1.0.0` and `rel/1.0` still clone, vendor the tag's bytes and pin the tag's commit;
- D9e a tagless `path = "../pathdep"` and a tagless git dep still resolve;
- D9f `""`, `-x`, `/abs`, `.hidden`, `a/.b`, `a\b` and a control byte each refused, the ESC shown
  as `\x1b`.
Mutants (each built from `cbt/`, run via `CYRIUS_GATE_CLI`): no call → D9a D9b D9c D9f red; no
`dep_tag != 0` guard → D4 D9e red (SIGSEGV on a tagless dep); `/` refused → D9d red; empty
allowed → D9f red; tag printed raw → D9f red.

## CVE-77 — on Windows, an mTLS server verifying client chains against the system store anchored them at roots the store trusts for server authentication only (the trust-store half of CVE-75)

*Appended 2026-10-05 (cyrius 6.6.17, lane lib, bite l1). Found by: the 6.6.16 lane reviews (roadmap "6.6.17 also takes" → TLS: "`tls_native_set_ca_system` takes a Windows root whose store purpose is serverAuth-only as a client-chain anchor"), measured on cass by the l1 premise check. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. CVE-75 enforced the extendedKeyUsage carried IN a CA certificate; this is the purpose Windows keeps for each root OUTSIDE the certificate. 6.6.17 spends CVE-77.*

| | |
|---|---|
| **Severity** | P3 (Low) — trust-policy bypass with zero measured exposure on a stock store. cass's CurrentUser `ROOT` store holds no root whose purposes name serverAuth without clientAuth, and no Disable / NotBefore distrust that refuses a root for clientAuth while sparing it for serverAuth: of the 41 server-purpose anchors, 0 are refused by the client policy (all 41 are client anchors too; the client set adds 4). Exploitation needs an mTLS server that verifies client certificates against the WHOLE Windows system store (unusual — mTLS servers normally install their own client CA), on a host whose store holds a root the root program trusts for server authentication only, plus a client certificate issued under that root. |
| **Class** | Improper certificate validation (CWE-295) — a trust anchor's purpose restriction (Windows `CERT_ENHKEY_USAGE_PROP_ID`, store property 9, and the purpose-scoped Disable / NotBefore dates) not enforced for the chain's purpose. |
| **Affected** | The native TLS server's client-certificate verification with the system trust set on a server ctx — `tls_native_set_ca_system` / `tls_ctx_set_verify_paths` with `tls_set_verify` PEER or FAIL_IF_NO_PEER_CERT — cyrius 6.6.14 (CVE-64 / CVE-65, the Windows store reader) through 6.6.16, Windows / PE only. A client ctx (verifying a server) was never affected; POSIX bundles carry no per-root purpose. |
| **Files** | `lib/tls_native_hs12.cyr` — `tls_native_set_ca_system`, `_tn_ca_load` / new `_tn_ca_load_into` and the `_tn_ca_cl_*` cells, `_tn_ca_read_win`, `_tn_w_export`, `_tn_w_policy`, `_tn_w_dated`, `_tn_w_eku_purpose` (each gains `purpose`); `lib/tls.cyr` — `tls_init_main` warms the client set on Windows; `docs/development/lib-tls-contract.md` (Trust store row) |
| **Fixed** | 6.6.17 |

**Vector.** `tls_native_set_ca_system` exported the CurrentUser `ROOT` store once, filtered for serverAuth, and installed that one set on every ctx. A SERVER ctx verifies CLIENT chains (`_TN_PURPOSE_CLIENT`), so a root whose root-program purposes (prop 9) are `[serverAuth]` — or whose purpose-scoped Disable / NotBefore distrust covers clientAuth — anchored a client identity.

**Impact.** An mTLS server on Windows authenticated a client whose identity was vouched for by a root Windows itself would not accept for client authentication (SChannel refuses the same chain).

**Fix.** The store policy takes the chain purpose. A server ctx loads a second, client-purpose set: prop 9 must name clientAuth (or anyExtendedKeyUsage, or be absent), and a dated distrust whose scope covers clientAuth refuses the root while one scoped to serverAuth alone does not. The set is read, parsed and published once per process exactly like the first (`_tn_ca_load_into`), and `tls_init_main` warms it too, so first use from worker threads stays race-free (follow-up 0910176f). No public API change, no new error value.

**Behaviour change (both directions, matching SChannel).** A Windows server ctx no longer takes a root whose purposes leave out clientAuth, and it now ALSO takes roots 6.6.16 refused for it — roots whose purposes name clientAuth but not serverAuth, and roots whose Disable / NotBefore distrust is scoped to serverAuth only. cass: 41 → 45 roots for a server ctx; a client ctx's set is unchanged.

**Verified.** `tests/tcyr/crossos/tls_system_trust_store.tcyr` (132/132 on cass): the client set re-derived from the real store (45 roots; server set 41); memory-store rows for the client purpose, row by row (a `[serverAuth]` root is not exported — 6.6.16 exported it); and one client chain end to end — a server ctx built from the export refuses `leaf_r` anchored at a `[serverAuth]` store root and verifies it at a `[clientAuth]` one. Because cass's stock store holds no serverAuth-only root, the defect is pinned on memory stores. `tests/tcyr/crossos/tls_first_use_threads.tcyr` gains the Windows rows for the warmed client set. The test runs at the release gate on all four hosts.

**Not covered.** POSIX trust bundles (`/etc/ssl/cert.pem` and the distro paths) are a flat serverAuth export with no per-root purpose, so both roles keep sharing one set there, as before — nothing to honour. Name constraints and certificate policies are unchanged (see CVE-75's *Not covered*).

## CVE-78 — `lib/fmt.cyr`'s `fmt_int_buf` wrote 24 bytes at `buf` whatever the number's length, so `fmt_float`'s own stack buffer and any `buf + pos` heap caller overran

*Appended 2026-10-06 (cyrius 6.6.18, lane poison, bite poison-1; follow-up d81e7f05). Found by: measuring the P6 poison prototype over the tcyr corpus — its check-previous-block hook reported a 2-byte heap overflow in `tls_native_ccs_deadline.tcyr`'s `alloc(32)+10`, confirmed with rc=3. Not a review sweep, and not part of the 2026-09-03 sweep: recorded here because this is the live ledger. Same class as CVE-50 (`lib/http.cyr`) and CVE-56 (`lib/log.cyr`), stdlib buffer overruns. 6.6.18 spends CVE-78.*

| | |
|---|---|
| **Severity** | P1 (High) — a stdlib stack and heap buffer overrun reachable from ordinary formatting calls; the bytes written are digits of the formatted number, which is attacker-influenced wherever that number is (a parsed length, a counter, a float from input). |
| **Class** | Out-of-bounds write (CWE-787) — a fixed-width scratch written into a caller's buffer regardless of the caller's room. |
| **Affected** | `fmt_int_buf` in every version with the in-place scratch, and through it `fmt_float_buf` / `fmt_float`; callers that format at `buf + pos` — `fmt_float`'s own `var buf[32]`, `patra.cyr:4789`, `bench.cyr:948`, `yantra.cyr:283`, and the `tls_native_ccs_deadline` test. All targets. |
| **Files** | `lib/fmt.cyr` — `fmt_int_buf`, `fmt_float_buf`, `fmt_float`; `tests/tcyr/text/fmt_int_buf_bounded.tcyr` (new) |
| **Fixed** | 6.6.18 |

**Vector.** `fmt_int_buf(n, buf)` built its digits in place from `buf+23` downward and then shifted them to `buf+0`, so every call wrote `buf+0 .. buf+23` — 24 bytes — even for a one-digit answer. Any caller passing `buf + pos` with fewer than 24 bytes left overran. `fmt_float_buf` formats the integer part at `buf + pos` and the fraction at `buf + pos'` (pos' up to 22), so `fmt_float`'s 32-byte STACK buffer was overrun for |val| ≳ 1e8 at 2 decimals (`1e15` wrote to `buf+40`). A second, independent half: even with an exact `fmt_int_buf`, 32 bytes was short of `fmt_float_buf`'s real worst case — a finite value past i64 range gives a 20-character integer field plus a 20-character fraction field (`-1e30` at 2 decimals touches 43 bytes), and any `decimals` past ~10 zero-pads past byte 32.

**Impact.** Adjacent heap blocks, or stack-frame bytes (locals, saved registers, the return address), overwritten with digit bytes.

**Fix.** `fmt_int_buf` builds in a local `var tmp[24]` (the `fmt_hex_buf` shape) and copies exactly `len + 1` bytes (≤ 21); output and return value unchanged. `fmt_float_buf` COMPUTES at most 18 fraction digits and writes any further digits as `'0'` padding — 10^19 overflows i64, so `fmt_float(3.5, 20)` printed wrong digits, and at 64 decimals `10^decimals` wrapped to 0 and the carry divided by zero (SIGFPE); its header documents the bound, `max(43, decimals + 24)` bytes. `fmt_float` formats at most 18 decimals into a 64-byte stack buffer (43 bytes worst case) and sends any wider field's padding in 32-byte pieces — no heap buffer, no leak, any `decimals`. Output for decimals ≤ 18 is unchanged.

**Verified.** `tests/tcyr/text/fmt_int_buf_bounded.tcyr` (21 assertions): 0xEE-filled 64-byte blocks; the bytes past each answer stay untouched for `47233`, `0`, `i64::MIN`, `buf+10`, `fmt_float_buf(1e15)` and `fmt_float_buf(-1e30)`; 3.5 at 20 decimals and 3 at 64 decimals format correctly; `fmt_float(-1e30, 2)`, `fmt_float(3, 50)`, `fmt_float(3.5, 20)` and `fmt_float(3, 64)` survive. Against the pre-fix code, 6 of the original 17 assertions fail; against ce750e8c (before the d81e7f05 follow-up) the wide-decimals rows fail and the run dies of SIGFPE (rc=136).

**Not covered.** No call site changed: the folded callers (`patra`, `yantra`) and `bench.cyr` are fixed by the `lib/fmt.cyr` change alone, so a consumer keeps the overrun until it bumps its pin to 6.6.18.

## CVE-79 — a `[package] cyrius` pin was joined unvalidated into a path the CLI EXECUTED: code execution from a cloned repository on every verb

*Appended 2026-10-07 (cyrius 6.6.20, lane c-pin, item CBT-01; commits 0df915c5, 38b56954, review 8572e96f and a6fb9c9f). Found by: the v6.6.x closeout audit (workflow `wf_ed01a9f8-8e1`, item CBT-01) and its security re-scan (SEC-01), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P0 (Critical) — code execution as the invoking user from a cloned repository, on verbs a user runs on an untrusted checkout precisely because they never run its code (`cyrius version`, `fmt`, `lint`, `build`, `deps`, a bare `cyrius`). |
| **Class** | Path traversal (CWE-22) into an executed path — execution of a binary the repository supplies (CWE-426, untrusted search path). The same unvalidated value also chose the stdlib directory and was echoed raw to the terminal (CWE-150). |
| **Affected** | The `cyrius` CLI from v5.11.25 for repositories without `src/main.cyr`, and for every consumer from v6.5.37, through 6.6.19 — Linux; macOS (a home-relative pin needs no `/proc`); Windows (a backslash spelling through `_win_redirect_to_pinned`, reproduced under wine). `cyriusly use` (no operand) through 6.6.19 for the raw echo. |
| **Files** | `cbt/deps.cyr` — `_dep_read_cyml_cyrius_field` (the one CLI reader) and new `_dep_pin_shape_ok`, which every site reaches through: `cbt/cyrius.cyr` `_try_redirect_to_pinned` / `_win_redirect_to_pinned`, `_dep_find_stdlib_dir`, `_dep_lock_pin_value` (the lock trailer), `_check_lib_freshness`, `cmd_lib_sync`, both distlib resolvers, the `manifest-pin:` print; `cbt/manifest.cyr` — `_cfg_resolve_build` (it read the pin with `_cfg_mf_str`); `programs/cyriusly.cyr` — `_print_resolved_version`, new `_cy_report_pin`, `_cy_shape_ok`, `_cy_err_shown` |
| **Fixed** | 6.6.20 |

**Vector.** A repository's `cyrius.cyml` declares `[package] cyrius = "<pin>"`. `_try_redirect_to_pinned` built `<home>/versions/<pin>/bin/cyrius` from the raw value and, when that file existed (`file_exists`, the only check), `execve`'d it before any verb ran (PE: spawned it). A repository that commits an executable `payload/bin/cyrius` and pins `cyrius = "../../(…)/proc/self/cwd/payload"` points the path back into itself; a home-relative traversal needs no `/proc`, and the path from `<home>/versions/` to a clone is predictable.

**Impact.** The repository's binary ran as the user on every verb. Under the documented `CYRIUS_RESOLVED=1`, which skips the redirect, the same value was joined into `<home>/versions/<pin>/…` at six more sites: `lib sync` copied from the traversed directory into `./lib`, `deps` vendored from it and wrote it into `cyrius.lock`, both distlib resolvers read it, the lib-freshness check read it, and `--version` / `build --print-config` printed it raw, terminal escapes included. A second reader, `cyriusly use` with no operand, parsed the pin with its own inline scan and wrote it straight to stdout (an OSC title-set and a clear-screen reached the terminal), and reported a traversal pin as valid while `cyrius` refused the same manifest.

**Fix.** The one CLI reader refuses — exit 1, by name, non-printing bytes shown as `\xNN` — a pin that is not a version's shape (a leading digit, then only `[0-9A-Za-z._-]`, no `..`; `/`, `\` and `:` are outside the set), and a present pin that is not a string; neither is ever read as "no pin". `build --print-config` routes the pin through it. cyriusly's reader applies the same rule (`_` allowed, so it never refuses a pin `cyrius` accepts), shows a refused pin as `\xNN`, exits 1, refuses an unquoted pin instead of reporting the global default, and reads a TOML literal-string pin (`'6.6.18'`) as the pin it is.

**Behaviour change.** A pin outside the shape is a named error. All 126 pins under `~/Repos` are plain `X.Y.Z`, so no consumer changes. A well-formed absent pin keeps the existing "not installed" error; an installed pin still redirects.

**Verified.** `tests/gates/toolchain/manifest_pin_shape_refused.sh` (new, registered in check.sh): the `/proc/self/cwd` payload on seven verbs; the home-relative and backslash spellings; the `CYRIUS_RESOLVED=1` siblings (nothing copied into `lib/`, no lock, nothing printed raw); the malformed shapes, including `6/x`, `6\x` and `6:x`, which only the charset refuses, each with a payload waiting where it would lead; controls (no pin, pin == VERSION, a well-formed absent pin, an installed pin still redirecting); and a wine leg for `cyrius.exe` (forward-slash and backslash traversal and `9\x` refused, a well-formed pin still redirecting). Reverting the reader turns it RED (the payload runs; exit 37 under wine), and so does a charset that also allows `/`, `\` or `:`. cyriusly's reader: `cyriusly_version_operand_refused.sh` axis 6 (an escape-bearing traversal pin, `../../x`, `6..6` and an unquoted pin refused; `6.6.19`, `6.6.20_rc` and `'6.6.18'` report) — RED against the base reader. Lane: `check.sh toolchain` 139 of 139.

**Not covered.** `cyriusly`'s own version-OPERAND handling is CVE-94.

## CVE-80 — `lib/pam.cyr` authenticated a WRONG password when its process had inherited SIGCHLD = SIG_IGN

*Appended 2026-10-07 (cyrius 6.6.20, lane l-plat, review round 1; commit c0bc1139). Found by: the skeptic verifier of audit item RLM-01 ("a SEVERE sibling met in passing", reproduced with a pam probe). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P1 (High) — local authentication bypass. Whoever starts the process chooses its inherited signal dispositions, and the consumer is shakti, a setuid-root sudo replacement. Not P0: it needs the inherited disposition (a local position) and a program that authenticates through this module. |
| **Class** | Unchecked return value (CWE-252) leading to use of an uninitialised variable (CWE-457) as an authentication verdict (CWE-287, improper authentication). The RLM-01 class (a wait status nobody wrote) on a security decision. |
| **Affected** | `pam_unix_authenticate` through 6.6.19 (the 6.6.19 `pam.cyr` returns `PAM_AUTH_OK` on both new test rows). |
| **Files** | `lib/pam.cyr` — `pam_unix_authenticate`; `tests/tcyr/platform/shadow_pam.tcyr` |
| **Fixed** | 6.6.20 |

**Vector.** `pam_unix_authenticate` forked `unix_chkpwd`, did a blocking `waitpid`, threw its result away and decoded the status buffer anyway. A process that inherits SIGCHLD = SIG_IGN — the disposition survives `execve` — has its children reaped by the kernel, so `waitpid` fails ECHILD and never writes the buffer.

**Impact.** The undecoded slot held whatever the stack held; a stale 0 read as exit 0, which is `PAM_AUTH_OK` — for a WRONG password, and for an unknown user.

**Fix.** The wait retries EINTR and returns `PAM_AUTH_FAIL` unless `waitpid` returned the helper's pid — the module's existing convention that anything but a clean exit 0 is a fail. shakti maps `PAM_AUTH_FAIL` to "rejected", not to its `su` fallback.

**Verified.** `tests/tcyr/platform/shadow_pam.tcyr` gains two SIG_IGN rows — a wrong root password and an unknown user — each run after a zeroed stack so the unwritten slot reads 0 deterministically. The 6.6.19 `pam.cyr` returns `PAM_AUTH_OK` (0) on both; fixed, 8 of 8.

**Not covered.** A consumer keeps the hole until it bumps its pin to 6.6.20. Filed in shakti (`docs/development/issues/2026-10-06-pam-wait-unobserved-sigchld-ign.md`, shakti `f04d26d`): bump the pin, and reset SIGCHLD to SIG_DFL at startup. The rest of the RLM-01 class (`lib/regression.cyr`, the check driver, `lib/async.cyr`, `lib/async_win.cyr`, the CLI's spawners) is fixed in 6.6.20 as ordinary bugs.

## CVE-81 — the 65th `use` alias overwrote the alias table and live compiler state: a call silently re-bound to another fn

*Appended 2026-10-07 (cyrius 6.6.20, lane s-decl, item HEAP-02; commit a5ebc0a0). Found by: the v6.6.x closeout audit's heap-map pass (item HEAP-02), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P1 (High) — memory corruption of compiler state reachable from source, whose first effect is a silent wrong call (rc 0, no diagnostic). The audit rated it P0 by its rubric; practical exposure is low (it takes 65 `use` aliases in one program). |
| **Class** | Out-of-bounds write (CWE-787) into a fixed heap region with no bound check (CWE-129); silent wrong-code generation. |
| **Affected** | Every target (all seven compiler forks share the code) through 6.6.19; the same unguarded stores were inline in 6.5.73. |
| **Files** | `src/frontend/parse_fn.cyr` — `_tl_use_alias`; `tests/gates/frontend/use_alias_table_cap.sh` (new); `scripts/check.sh` (registration) |
| **Fixed** | 6.6.20 |

**Vector.** `_tl_use_alias` stored alias #n at `use_from[n]` / `use_to[n]` unchecked. Both tables are 64 entries and abut — `use_from[64]` is `use_to[0]`, `use_to[64]` is the count.

**Impact.** With 65 aliases the call of the first alias's bare name resolved to whatever fn carried the 65th alias's bare name — rc 0, no diagnostic, a wrong call at run time. 66–120 aliases failed with a bogus "undefined function"; 199–5,062 compiled rc 0 and called the wrong fn; 5,063 and up crashed the compiler (SIGSEGV) after a bogus "uninitialized variable".

**Fix.** The 65th alias is refused — "too many `use` aliases (max 64)" — before the first store (`ERR_MSG` does not exit, so the refusal returns). Raising the cap in place would be a heap-layout change; the refusal is not.

**Verified.** `tests/gates/frontend/use_alias_table_cap.sh` (5 rows): 64 aliases resolve to the module fn; 65, 200 and 5,100 are refused rc 1 by name; a premise row. The base compiler is RED on 65 / 200 / 5,100; a cap at 63 is RED on the 64 row; dropping the `return` is RED on 5,100. Two-step self-host fixpoint and seed-derive OK; the refusal fires in the aarch64, PE and cx fork compilers too.

**Not covered.** None known.

## CVE-82 — `PP_EXPAND` copied a function-like macro's parameter names and arguments into 512-byte stack buffers unbounded, and never checked the argument count

*Appended 2026-10-07 (cyrius 6.6.20, lane s-ppcaps, item LEX-EXPR-01; commits 33c74a63, review ae60df8e). Found by: the v6.6.x closeout audit's lexer / preprocessor review (item LEX-EXPR-01), confirmed by the skeptic pass; the argument-count half was found while fixing it. A CVE-40 sibling. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P1 (High) — a compiler stack overflow and a silent miscompile reachable from source; the trigger is pathological (a macro argument or parameter list over ~512 bytes, or a mismatched argument count). |
| **Class** | Stack-based buffer overflow (CWE-121); improper validation of an argument count (CWE-628 class) leading to an out-of-bounds read of stale stack bytes (CWE-125). |
| **Affected** | Every target since 6.5.73 (CVE-40, at 6.5.45, bounded only the `#define` body copy). |
| **Files** | `src/frontend/lex_pp.cyr` — `PP_EXPAND`, new `PP_MACRO_REFUSE` and `PP_MACRO_ARGCHECK`; `tests/gates/frontend/pp_table_caps.sh` §D (new gate) |
| **Fixed** | 6.6.20 |

**Vector.** `PP_EXPAND` copies a macro's parameter names into `var pnames[512]` and an invocation's arguments into `var args[512]` — fn-local, so 512 BYTES each — and neither loop checked its index. It also never compared an invocation's argument count with the macro's parameter count.

**Impact.** A 516-byte argument expanded to nothing and compiled clean (`fn f(): i64 { return PICK("<516 a's>", 7); }` returned 0 where 7 is right); 518 bytes and up smashed the frame and cycc died of SIGSEGV; a ~600-byte parameter list did the same from the definition side; a parameter list with no `)` read past the stored definition (SIGSEGV). Count mismatches compiled silently: extra arguments were dropped (`#define PICK(a, b) b`, `PICK(5, 6, 7)` took 6); too few made the substitution walk past the last argument into stale bytes of `args` left by an EARLIER call (`PICK(3, 4)` then `PICK(9)` took 4 — and with no NUL in the stale bytes the walk is not bounded by the buffer); an invocation with no `)` was expanded from whatever had been copied by end of input.

**Fix.** Both copies refuse past 511 bytes of names / arguments and separators (no store past index 511), and the parameter scan stops at the stored definition's end. `PP_MACRO_ARGCHECK` refuses a count mismatch and an unclosed invocation. Each refusal is a hard error naming the macro: `error: function-like macro 'PICK': an invocation's arguments exceed 511 bytes` / `its parameter names exceed 511 bytes` / `its parameter list has no closing ')'` / `takes 2 arguments, given 1` / `an invocation has no closing ')'` (unlocated: the macro pass runs on the expanded stream). `Z()` / `Z( )` still invoke a zero-parameter macro and `F()` still passes one empty argument. The `up to 8 params, 64 bytes each` comment, which described a layout that never existed, is corrected.

**Behaviour change.** A mismatched invocation that used to compile silently is now an error. No ecosystem source defines a function-like macro.

**Verified.** `tests/gates/frontend/pp_table_caps.sh` §D, 17 rows: the pre-fix compiler is RED on all 6 buffer-refusal rows, the pre-count-check compiler on the 5 count refusals; mutants D1–D6 (each guard removed, the unclosed refusal deleted, the blank-argument exemption deleted) each RED. A 606-file differential corpus compiles byte-identical with identical stderr and exit codes; self-host fixpoint and seed-derive OK; six forks compile with identical diagnostics.

**Not covered.** A comma inside a string literal still splits a macro argument (the argument scan is not string-aware; making it so alone would desync `PP_ARGS_ON_LINE`, which bounds an invocation inside a `#` comment) — a known gap, named in the guide.

## CVE-83 — a resolve that skipped a tagged git dep dropped its CVE-21 commit pin from `cyrius.lock`, so the next resolve accepted a repointed tag

*Appended 2026-10-07 (cyrius 6.6.20, lane c-lock, item CBTB-01; commits aaeba872, 3006318a, e6c3fd1f, 97b1a726, 940ac734, 353a1e7b, b9f1970b, 3d2680dd, f7ee0144 across three review rounds). Found by: the v6.6.x closeout audit's CLI review (item CBTB-01), confirmed by the skeptic pass. A CVE-21 residual. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P1 (High) — supply-chain integrity: an attacker who can move a dependency's tag gets a silent swap on a fresh checkout (the CI case). That is the first-resolve trust-on-first-use floor CVE-21 exists to close, reached on a routine workflow. |
| **Class** | Download of code without an integrity check (CWE-494): a stored commit pin silently discarded, re-establishing trust on first use. |
| **Affected** | `cyrius deps` and every auto-deps verb (`build`, `run`, `test`, `bench`, `publish`, …) through 6.6.19 (measured on the 6.6.20 slot-open CLI), on every host; every pin on a host with no git (PE). |
| **Files** | `cbt/deps.cyr` — `cmd_deps_lock` (the commit-line block and its summary), `_lock_commit_lookup` (whole-file read), new `_lock_commit_field_at`, `_lock_commit_field_len`, `_lock_commit_same_key`, `_dep_commit_fresh_has`, `_lock_commit_name_same`, `_lock_cstr_cmp`, `_lock_commit_line_cmp`, `_dep_commit_fresh_count`; `tests/gates/toolchain/deps_commit_pins_kept.sh` (new) |
| **Fixed** | 6.6.20 |

**Vector.** `cmd_deps` resets its list of fresh pins on every run and pins only the tagged deps it cloned and verified in that run; `cmd_deps_lock` then wrote either those fresh lines or, for bare `--lock` (the 6.6.4 repair), the inherited ones — never both. Any dep a resolve skipped therefore lost its `commit` line while its `lib/` hash row stayed: an `optional = true` dep resolved without its feature (and `--no-default-features`), a `target =` dep resolved on another target, every transitive dep of a gated-out dep, a dep served by an existing `path =` override, and every pin on a host with no git — even when the build itself then failed.

**Impact.** Measured on the slot-open CLI: `deps --features gpu` reported 2 commit-pinned; plain `deps` then reported 1. With the optional dep's origin tag repointed and its cache cleared, `deps --features gpu` exited 0, vendored the new bytes and re-pinned to them.

**Fix.** `cmd_deps_lock` always merges and sorts: it writes the fresh lines plus every inherited `commit` line that no fresh line supersedes. Only a fresh line with the same (name, git, tag) supersedes — the key `_lock_commit_lookup` reads a pin by, with the url normalised the same way (`…/x` = `…/x.git`), so a respelled url replaces its line rather than duplicating it. (The first cut keyed on the name alone; review measured the hole: in a diamond, a gated root dep `x` at v2 and a required dep's own `x` at v1 share the name, and the feature-less resolve dropped the x@v2 pin, after which a repointed v2 was vendored at exit 0 — reachable with `target =` too.) The merge is not filtered to the names the manifest declares, because a gated-out dep's transitive deps are declared only in its own manifest. The block is sorted by (name, git, tag), then the whole line, so alternating gatings no longer flip it (the 6.6.3 churn class for consumers that run `git diff --exit-code -- cyrius.lock`). Because an old tag's line now stays, the block is no longer bounded by the dep count, and `_lock_commit_lookup`'s 64 KB window could put a live pin past the cut (~675 retained lines sorting before a dep's name) and answer "no pin": it sizes its buffer from the file, as `_dep_lock_load` and `cmd_deps_verify` have since 6.6.4 — the third fixed-window instance on `cyrius.lock`.

**Behaviour change.** An old tag's line stays after a tag bump (fail-closed, and what CVE-21 wants if the dep later moves back to a repointed old tag; deleting `cyrius.lock` re-pins, as before). An existing lock's commit block is re-ordered once, by the first resolve under 6.6.20, in the same change as the pin bump's `cyrius\t<pin>` trailer. The summary reads `cyrius.lock: N deps locked, M commit-pinned (K re-verified)`: M counts distinct dep names in the merged lock (a 6-dep project had printed "1006 commit-pinned"); K counts the deps this run checked against their origin — 0 for a pure-override resolve and for bare `--lock` — which keeps `ecosystem-migration-6.6.2.md`'s tell for a `path =` override that masked the tag (a dated note follows the doc's original line).

**Verified.** `tests/gates/toolchain/deps_commit_pins_kept.sh` (23 axes; 23/23 under `bash -eo pipefail`): K1–K9 — pins on an optional dep, its transitive dep, a target-gated dep and a path-override dep survive a feature-less `deps` and a feature-less `cyrius build`, and each kept pin then refuses its repointed tag by name with the lock and `lib/` untouched; K2 / K2l the summary (`(1 re-verified)`; bare `--lock` `(0 re-verified)`); K8 / K8r a tag bump; K12 the diamond; K13 three alternating resolves leave the lock byte-identical; K14 a respelled url; K15 1,000 retained lines put the live line past 64 KB and its repointed tag is still refused; K16 the summary on that lock; K17 a fork at the same tag; K18 libro's shape (two dep names on one repo at one tag, one optional). Mutants, one at a time against the final gate: the slot-open CLI (every axis but K1 RED); the name-keyed first cut; carrying every inherited line; a byte-for-byte git compare; a drop key ignoring git; a drop key ignoring the name; no sort; the 64 KB window restored; the summary counting lines; the summary without `(K re-verified)` or printing M as K — each RED on its named axes (ledger in the gate header). Lane: the `toolchain` bucket 137 of 137.

**Not covered.** The CRLF half is CVE-89. A consumer keeps the hole until it bumps its pin to 6.6.20.

## CVE-84 — Windows had no munmap route: every large `fl_free` / `cyr_munmap` leaked its whole mapping, so sigil's argon2 leaked its m_cost arena per call

*Appended 2026-10-07 (cyrius 6.6.20, lane s-pe, item REV-LIB-PLATFORM-01, commit d458108b; lane l-plat, RLM-07 d8e60dc8 and the comment half 2577d226). Found by: the v6.6.x closeout audit's platform-library review (item REV-LIB-PLATFORM-01, with RLM-07 its stdlib face), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P1 (High) — availability: unbounded committed-memory growth on Windows driven by untrusted input (a login attempt hashed with argon2). Not memory corruption. |
| **Class** | Missing release of memory after effective lifetime (CWE-401) leading to uncontrolled resource consumption (CWE-400); an unchecked return value hid it (CWE-252). |
| **Affected** | Every PE build through 6.6.19 that frees a block over 4 KiB through `fl_free`, or calls `cyr_munmap` / the Windows peer's `sys_munmap` / `syscall(11, …)` — sigil's argon2id / argon2i / argon2d among them; cycc.exe itself (its 24 MB preprocessor buffer stayed committed to exit). |
| **Files** | `src/backend/x86/emit.cyr` — new `EMUNMAP_PE`, `_PE_ROUTE_FLUSH` (the literal route), `EPE_SYSCALL_DYNAMIC` / new `_pe_dyn_arity3` (the var route); `src/backend/pe/emit.cyr` — `_pe_ensure_vfree` (the VirtualFree import); `src/backend/aarch64/emit.cyr`, `src/backend/cx/emit.cyr` — return-0 `EMUNMAP_PE` stubs; `lib/freelist.cyr` — new `_fl_unmap`, both large-block frees; `lib/syscalls_windows.cyr` — the `SysNr` / `sys_munmap` / `sys_brk` comments; tests below |
| **Fixed** | 6.6.20 |

**Vector.** The PE backend had no reroute for syscall 11, so `syscall(11, addr, len)` returned -38 there — with a warning on the literal path, and none on a var-held number (`var n = 11; syscall(n, …)`). `fl_free` unmaps every block over 4 KiB and ignored the result, so each large `fl_alloc` / `fl_free` pair kept its mapping alive. `lib/syscalls_windows.cyr`'s comments promised munmap and brk reroutes that did not exist.

**Impact.** Four 8 MiB `fl_alloc` / `fl_free` rounds under wine returned four distinct, growing addresses (+8 MiB + 64 KiB each) where Linux reuses one. sigil's argon2 variants `fl_alloc` their whole m_cost arena per call, so a Windows server hashing logins leaked m_cost KiB of committed memory per attempt — 19–64 MiB at OWASP settings — until memory ran out. `fl_free` returned 0 for every one of those frees, so nothing could tell.

**Fix.** Syscall 11 at arity 3 → `kernel32!VirtualFree(addr, 0, MEM_RELEASE)`: `EMUNMAP_PE` (rbx-anchored 16-byte align, like `EMMAP_PE`; `length` dropped because MEM_RELEASE requires a dwSize of 0; the BOOL, read from eax only, becomes 0 / -22 = -EINVAL, keeping munmap's 0 / -errno contract), routed on BOTH paths — the literal one through `_PE_ROUTE_FLUSH`, so `_PARSE_FACTOR_IMPL` gains no reference (cybs's silent per-function limit), and the var one through the arity-3 arm of `EPE_SYSCALL_DYNAMIC`, now `_pe_dyn_arity3`. Return-0 stubs on the aarch64 and cx backends; the routed-number note lists 11. Both large-block frees in `lib/freelist.cyr` (plain and poison mode) go through `_fl_unmap`, which returns the kernel's -errno when it refused (the mapping is still there) and 0 when it released; `docs/stdlib-reference.md` documents `fl_free → 0 / -errno`. The Windows comments now say what is routed (munmap from 6.6.20, `length` dropped; brk unrouted and unneeded — the PE heap is mmap → VirtualAlloc).

**Behaviour change.** A partial or offset munmap is not expressible on PE (MEM_RELEASE frees the whole reservation): a non-base address answers -EINVAL, and the base with a shorter length releases the whole reservation. No PE-reachable caller unmaps a sub-range.

**Verified.** `tests/tcyr/crossos/munmap_releases_mapping.tcyr` (new; 8 rounds of `fl_alloc(8 MiB)` / `fl_free` whose address spread must stay under 3 blocks, `cyr_munmap`, PE's `sys_munmap`, the var-held 11, the offset -EINVAL contract; runs on cass in the cross-OS leg). `tests/tcyr/crossos/mmap_anon_flag.tcyr` and `mmap_include_order.tcyr` lose a false `#ifndef CYRIUS_TARGET_WIN` guard that had hidden the -38 from the cross-OS gate. `tests/gates/platform/pe_unrouted_warning_names_site.sh` gains rows pinning that the note lists 11 and a literal munmap draws no warning. Mutation under wine 11.19: the pre-fix compiler turns 5 rows RED, the var arm alone 2. `tests/tcyr/crossos/freelist_unmap_failure_reported.tcyr` (new): a real 8 MiB block frees to 0 on every POSIX host; on Linux a forged page-aligned header with a 2^56 − 4096 length makes munmap refuse and `fl_free` returns -22 with the page still readable (the slot-open freelist returns 0). On cass at the lane: self-host identical, then 198/198 and (after REVBE-04) 199/199 crossos.

**Not covered.** sigil's `src/mldsa.cyr` comment ("cyrius routes no PE syscall 11 to VirtualFree …") goes stale with this fix — a sigil filing. `freelist_unmap_failure_reported.tcyr`'s real-block row was written guarded off PE while munmap was unrouted there; with the route in, it can run on PE too (an integration follow-up).

## CVE-85 — `#if` / `#ifdef` / `#ifndef` / `#ifplat` nesting past 64 levels wrote state bytes through live compiler state, and could silently miscompile

*Appended 2026-10-07 (cyrius 6.6.20, lane s-ppcaps, item HEAP-01; commit ca56c609). Found by: the v6.6.x closeout audit's heap-map pass (item HEAP-01), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — the audit rated it P0; the verifier P2: source-only input, the written bytes are 0–3 (conditional states), and the silent case needs ~344K nesting levels. Real code nests at most 5. |
| **Class** | Out-of-bounds write (CWE-787) into a fixed 64-byte heap region with no depth check; silent wrong-code generation. |
| **Affected** | Every target since v5.6.1. |
| **Files** | `src/frontend/lex_pp.cyr` — new `PP_PUSH_LEVEL` and the push sites in `PP_PASS` and `PP_IFDEF_PASS`; `tests/gates/frontend/pp_table_caps.sh` §A |
| **Fixed** | 6.6.20 |

**Vector.** The per-level state stack at `S+0x197F10` is 64 bytes, one per nesting level. None of its push sites checked the depth; the only depth tests were `pp_depth > 0` on `#else` / `#endif`.

**Impact.** Each deeper level wrote its state byte upward through freed space, then `gvar_cnt`, then the jump-target count (a loud `function exceeds 1023 jump targets` at ~24.8K levels), and at ~344K levels `gvar_initval`, which `_EMIT_GVAR_STATIC_INITS` bakes into the image: a clean compile whose uninitialised globals came out non-zero (exit 49 where 0 is right).

**Fix.** One helper, `PP_PUSH_LEVEL`, does the push at every site and refuses depth 65 with a located hard error — `error:<file>:<line>:<col>: #if/#ifdef/#ifndef/#ifplat nesting exceeds 64 levels` — in the main source and in an included file.

**Verified.** `tests/gates/frontend/pp_table_caps.sh` §A (15 rows): 64 levels compile and run for every arm in both passes; 65 are refused at the 65th directive; 9,000 are refused by the same message. The pre-fix compiler is RED on all 8 refusal rows. Self-host fixpoint and seed-derive OK; a 606-file differential corpus byte-identical.

**Not covered.** <!-- INTEGRATION: confirm before appending — 6.6.20's LEX-EXPR-03 (lane s-pplex) adds an `#ifplat` arm to PP_IFDEF_PASS, an eighth push site that must call PP_PUSH_LEVEL; in the trial tree it still stores raw (`store8(S + 0x197F10 + pp_depth, _s); pp_depth = pp_depth + 1;`). If it ships that way, an included file can still push past 64 through `#ifplat`, and this paragraph must say so. --> None known once every push site goes through `PP_PUSH_LEVEL`.

## CVE-86 — an attribute line holding a multi-line string desynced the preprocessor from the lexer: a forged `#@file` defeated `private`, a real `#ifdef` was skipped, and string data was executed as `#define` (a CVE-45 / CVE-55 residual)

*Appended 2026-10-07 (cyrius 6.6.20, lane s-pplex, item LEX-EXPR-02; commit 0d85cdcd). Found by: the v6.6.x closeout audit's lexer / preprocessor review (item LEX-EXPR-02), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — the CVE-45 / CVE-55 class: a compile-time visibility bypass (code the language says cannot call a `private` fn compiles and calls it), plus a silent wrong-arm compile; rc 0 and no diagnostic in every case. Not a memory-safety defect. |
| **Class** | Interpretation conflict between two passes over the same source (CWE-436): the preprocessor and the lexer disagreed about where a string literal ends. |
| **Affected** | Every target through 6.6.19 (measured on the 6.6.20 slot-open compiler for all ten attributes, from the main source and from an included file). |
| **Files** | `src/frontend/lex.cyr` — new `LEXATTRWORD` (the one attribute list; LEX dispatches on it); `src/frontend/lex_pp.cyr` — new `PP_LEXST_AT`, `PP_NEUT_BOLMARK`, and every walk that stepped the old `PP_LEXST`: `PP_PASS`, `PP_IFDEF_PASS`, `PP_MACRO_PASS`, `PP_REF_PASS`, `PP_IS_HOST_ONLY`, `PP_NEUT_FMARK`, `PP_A64_NATIVE_AT`, the `#derive` brace copy |
| **Fixed** | 6.6.20 |

**Vector.** The lexer lexes the rest of an ATTRIBUTE line (`#assert`, `#regalloc`, `#deprecated`, `#must_use`, `#pure`, `#io`, `#alloc`, `#naked`, `#inline`, `#pe_import`) as CODE, string literals included, and a cyrius literal may hold a raw LF. The preprocessor's state machine (`PP_LEXST`) read every `#` in code as a comment opener, so after `#assert 1 == 1, "x<LF>"` it took the literal's CLOSING quote for an opening one and believed the whole next line was string data while the lexer was in code.

**Impact.** Three consequences, each rc 0 with no diagnostic: a `#@file "secret.cyr" 1` line there was skipped by the forged-marker neutraliser (which leaves strings alone) and minted by FM_BUILD, so a `private` fn of `secret.cyr` was CALLED (built, exit 42; the same call without the forged line is refused); a real `#ifdef CYRIUS_TARGET_WIN` there was skipped by the preprocessor and read by the lexer as a comment, so the Windows-only arm compiled on Linux (exit 99, want 0); and a `#define Q 1` line INSIDE such a string was executed and cut out of the program's data (strlen 4 where the source spells 15).

**Fix.** At the root: the ten attribute words are ONE list, `LEXATTRWORD`, which LEX dispatches on (replacing ten hand-unrolled byte chains, ~250 lines) and which the preprocessor asks through `PP_LEXST_AT` — every preprocessor walk now steps through it, so a `#` the lexer reads as an attribute is code to the preprocessor too. 6.6.6 had declined this for fear two attribute lists would drift; with one list there is nothing to drift. Belt and braces: `PP_NEUT_BOLMARK` neutralises FM_BUILD's exact 8-byte key `#@file "` at any line start whatever the string state, since FM_BUILD mints a marker there with no idea of strings. That also closes the CVE-45 data-side residual (`"a<LF>#@file "` minted a junk-named file span, so later diagnostics named `;` + LF + … as their file). `"a<LF>#@filex"` and `"a<LF>#@file x"` keep every byte (the key is 8 bytes). `#@a+` / `#@a-` are not neutralised: their only consumer walks strings with the same `PP_LEXST_AT`.

**Behaviour change.** A macro invocation whose arguments wrap onto the next line on an attribute line (`#inline fn f(): i64 { return ADD(1,<LF>2); }`) expands again — from 6.6.6 to 6.6.19 it failed with `undefined function 'ADD'`. A string literal whose next line opens `#@file "` now holds `# file ` there — the one shape that was already mis-compiled.

**Verified.** `tests/gates/frontend/file_marker_forge_refused.sh` axes 11–26: 11 the reported included-file shape, 12–21 one per attribute, 22 the `#ifdef` miscompile, 23 the `#define`-in-data, 24 the belt and braces, 25 its over-correction guard, 26 a census (no bare-`PP_LEXST` walk, one shared list). The slot-open compiler fails 14 of them; mutations split the halves (`PP_LEXST_AT`'s attribute arm alone → 22, 23; `PP_NEUT_BOLMARK` alone → 24; both → 11–24). `macro_invocation_boundary.sh` axis 11 re-pinned to the hand-expanded twin; `lexer_attribute_word_boundary.sh` census B0 re-derived from `LEXATTRWORD`'s rows. Two-step self-host fixpoint, seed-derive OK, all seven forks byte-identical in output, the aarch64-native fixpoint under qemu.

**Not covered.** `cyaudit` and `cyrius_api_surface` carry their own copies of the old `PP_LEXST` and still read an attribute line as a comment (`cyaudit vet` reports "no dependencies" for an include that follows a multi-line `#assert` message) — filed as `docs/development/issues/tool-lexst-copies-miss-attribute-lines.md`. Those are reporting tools, not the compiler.

## CVE-87 — `[deps.]` / `[deps..]` / control-byte header names passed the CVE-62 guard: the clone dir aliased another dep's cache directory, and the name reached the terminal raw

*Appended 2026-10-07 (cyrius 6.6.20, lane c-deps, item CBTB-02; commit fd922a24). Found by: the v6.6.x closeout audit's CLI review (item CBTB-02) and its security re-scan (SEC-09), confirmed by the skeptic pass. A CVE-62 residual. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — name-level occupation of another dep's cache directory driven by any manifest in the dep graph, a destructive command PRINTED as advice for a foreign directory, and terminal escape injection through the name. No content poisoning: the CVE-43 origin check and the tree-vs-tag check held. |
| **Class** | Path traversal / equivalence (CWE-22, CWE-41) on a manifest field; improper neutralisation of escape sequences (CWE-150). A CVE-62 residual. |
| **Affected** | `cyrius deps` and the auto-deps verbs through 6.6.19, from the root manifest or any transitive one. |
| **Files** | `cbt/deps.cyr` — new `_dep_name_unsafe` (the silent rule), `_dep_refuse_name` (the one refusal line), the `_shown` / `_ew_shown` escaping printer; the CVE-76 tag refusal; `deps --dry-run` |
| **Fixed** | 6.6.20 |

**Vector.** `_dep_reject_unsafe_name` (the CVE-62 guard) refused a `[deps.NAME]` header only for `/` and `..`. An empty name (`[deps.]`), a `.`-led one (`[deps..]`, `[deps..x]`), a backslash and control bytes passed, and the header scan ran across newlines, so a header could span lines. The name becomes the clone dir `<home>/deps/<name>/<tag>`, so `[deps.]` / `[deps..]` turned it into `<home>/deps//<tag>` / `<home>/deps/./<tag>` — ANOTHER dep's NAME directory.

**Impact.** A foreign checkout could be cloned AS `<home>/deps/<tag>` (name-level cache occupation: symlinks committed in it then became that name's tag slots, and a later legitimate resolve verified a planted symlink into the user's own repo and printed `reset --hard` / `clean -qffdx` restore advice for it); the tamper refusal printed `rm -rf <home>/deps/./victim` (every cached tag of victim); and the name was echoed raw — a terminal escape sequence or a forged line out of a hostile manifest.

**Fix.** One silent name rule, `_dep_name_unsafe` — empty, `.`-led, `/`, `\`, `..` or a control byte (the tag rule's set less the `/` a tag may hold) — checked before any path is derived, root or transitive. The refusal is one line, `_dep_refuse_name`, with the name shown through the new `_shown` / `_ew_shown` printer (CVE-76's tag printer, generalised); the CVE-76 tag refusal escapes the name too. `cyrius deps --dry-run` lists `[deps.]` (it skipped it) and refuses it by the same line, exit 1, agreeing with the real run. (`cyrius build`'s auto-resolve, which had its own header rule, refuses the same manifest since 6.6.20's REFACTOR-02.)

**Verified.** `tests/gates/toolchain/deps_modules_default_or_warned.sh` D8b–D8f (floor 15 → 20): `[deps.]`, `[deps..]` aimed at a planted victim and `[deps..x]`; a transitive `[deps.]`; an ESC name and a backslash name (shown `\x1b`, no raw ESC); a header spanning lines; the dry run. RED on the slot-open CLI (5 rows); each mutation in the gate's ledger turns its rows red.

**Not covered.** The tag-slot squat itself is not unique to this gap (the cache key holds no URL). The name and tag rules refuse C0 and DEL but not UTF-8 C1 bytes (a CSI on terminals that honour C1) — low severity, backlog.

## CVE-88 — a `[deps.X] modules` entry with `..`, or a dep file committed as a symlink, vendored any readable file into the consumer's `lib/`

*Appended 2026-10-07 (cyrius 6.6.20, lane c-deps, item BACKLOG-04; commits 09e82ce4, review 70fab2c5 and 6f69e3f5). Found by: the roadmap backlog (the 6.6.16 premise checks, recorded under CVE-76's *Not covered*), re-verified by the v6.6.x closeout audit (item BACKLOG-04) and its security re-scan; the committed-symlink vector was found in the lane's review. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — information disclosure: any file the user can read is copied into the consumer's `lib/` (and so into a build, a commit, a published bundle), driven by any manifest in the dep graph; a linked `.deps` sidecar's contents were echoed on stderr (a public CI log). No write outside `lib/`. |
| **Class** | Path traversal (CWE-22) and link following (CWE-59) on the read side of dependency vendoring. |
| **Affected** | `cyrius deps` and the auto-deps verbs through 6.6.19 — git and path deps, root or transitive. |
| **Files** | `cbt/deps.cyr` — new `_dep_mod_path_unsafe`, `_dep_modules_refused`, `_dep_src_link`, `_dep_refuse_src_link`; the `modules` loop (primary path checked before its `lib/<base>` fallback), the default `dist/<name>.cyr` probe, the `.deps` sidecar read, the modular sub-module and `index.cyml` reads |
| **Fixed** | 6.6.20 |

**Vector.** Each `[deps.X] modules` entry was joined onto the dep's dir (`<dep>/<entry>`) and copied into `lib/` with no check: `modules = ["../secret"]` or `dist/../../secret` — from the root manifest or any TRANSITIVE one, where `../../../../secret` from `<home>/deps/foo/2.0.0` climbs out of the dep cache. The same class without any `..`: the copy opens the source with `sys_open`, which follows links, so a git dep whose tag COMMITS `dist/x.cyr -> /abs/secret` (absolute, or relative out of the cache, or `dist ->` a directory) vendored the target.

**Impact.** The secret landed in `lib/X_secret` (or `lib/x.cyr`) at exit 0 with a verified commit pin — root or transitive, with or without a `modules` key (the default `dist/<name>.cyr` too), and through a modular sub-module or its `index.cyml`. The CVE-43 cache verify passed: the link IS the tag's content. A linked `dist/<name>.deps` sidecar was read and its lines echoed back on stderr as refused leaf names. Path deps alike. (An absolute `modules` entry was never itself a vector — it joined as `<dep>//abs` and failed "not found".)

**Fix.** An entry with a `..` component (split on `/` and on `\`, Windows' separator) or a leading `/` / `\` is refused by name — `error: [deps.X] modules entry "…" is not a path inside the dep (absolute, or a `..` component) — section refused` — before any gate, clone or copy, root or transitive, like CVE-76's tag check; `./dist/x.cyr` and a `..` inside a name (`v..2/w.cyr`) stay legal. And every dep file is read only from inside the dep's tree: `_dep_src_link` checks each component below the dep root for a symlink (as `[embed]`'s `_embed_path_bad` does) before any read or unlink — a `modules` entry (its primary path first, then its `lib/<base>` fallback), the default probe (a link there, even dangling, is refused by name rather than called absent, so a dangling `dist/<name>.cyr` beside a regular `lib/<name>.cyr` is refused rather than resolved around — the first cut checked only the fallback, and that tag vendored `lib/<name>.cyr` with rc 0 and a lock), the `.deps` sidecar, a modular sub-module and its `index.cyml` — and `_dep_refuse_src_link` names the file and the link: `error: [deps.X] dist/x.cyr passes through a symlink (<path>) — a dependency's files are read only from inside its own tree; refused`, rc 1, nothing vendored, no lock. Only the dep ROOT may itself be a link.

**Behaviour change.** None for the ecosystem: no clone in the dep cache and no `dist/` or `src/` under `~/Repos` holds a symlink.

**Verified.** `tests/gates/toolchain/deps_modules_default_or_warned.sh` D10a–D10c (root `../secret`, `dist/../../secret`, an absolute path and `..\secret`; a transitive `../../../../secret`, its dep never cloned; anti-over-reach `./dist/sib.cyr` and `v..2/w.cyr`) and D11a–D11h (a tag committing `dist/lnk.cyr` as an absolute and a relative link, root and transitive, with and without `modules`; a `dist ->` directory link; a linked modular sub-module and `index.cyml`; a linked `.deps` sidecar whose target text must reach no stream; a linked path-dep file; a path dep whose ROOT is a link still vendors; a dangling `dist/lnk.cyr` beside a regular `lib/lnk.cyr`). Floor 15 → 31. D10a / D10b RED on the pre-fix CLI (the secret in `lib/`, rc 0); D11a–D11f RED on the first cut; D11h RED on the review-1 tip; each ledger mutation turns its rows red.

**Not covered.** A TRANSITIVE manifest's `path` still vendors any local file: a git dep whose tag ships `[deps.evil] path = "<abs dir>" modules = ["secret.cyr"]` gives the consumer `lib/evil_secret.cyr`, rc 0, with a lock (measured on the lane tip). Confining a transitive `path` to its own manifest's tree is a design item — there are 54 legitimate root `path = "../sibling"` uses — and stays open in roadmap.md's *Potential backlog*, with the re-scan's new sibling: a transitive `git = "<local path>"` clones any local repository into the cache and vendors its files.

## CVE-89 — on a CRLF checkout of `cyrius.lock` the moved-tag check failed open (a trust-on-first-use re-pin), and `deps --verify` failed every file

*Appended 2026-10-07 (cyrius 6.6.20, lane c-lock, item CBTB-05; commits 61c88ca3, review 126ee474). Found by: the v6.6.x closeout audit's CLI review (item CBTB-05), confirmed by the skeptic pass. A CVE-21 residual. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — the commit-pin half needs both an attacker who repoints a dependency's tag and a victim with a CRLF checkout; the `--verify` half alone (fail-closed, every failure false) is P3. |
| **Class** | Insufficient verification of data authenticity (CWE-345): a line-ending-dependent parse that answered "no pin" and so failed open. |
| **Affected** | `cyrius deps` and the auto-deps verbs (the commit-pin lookup) and `cyrius deps --verify` through 6.6.19, on any checkout whose `cyrius.lock` has CRLF line endings. |
| **Files** | `cbt/deps.cyr` — `_lock_commit_lookup` (field reads stop before a trailing `\r`), `cmd_deps_verify` (the path parse) |
| **Fixed** | 6.6.20 |

**Vector.** No hand-editing is needed: a plain `git -c core.autocrlf=true clone` of a consumer repository produces a CRLF `cyrius.lock`, and the 6.6.5 cache-verify work already treats a global-autocrlf tree as supported. 6.6.4 made `_dep_lock_load` and the hash lookup CRLF-tolerant (6.6.9 only factored the hash lookup into a buffer form for `--verify`); its review missed the other two readers.

**Impact.** `_lock_commit_lookup` kept the `\r` on the tag field, matched no line and returned "no pin", so on a CRLF checkout a repointed tag on a fresh cache was vendored and re-pinned at exit 0, skipping the CVE-21 refusal. `--verify` read each path up to the `\n` and reported every file `cannot hash` (`lib/x.cyr\r` does not exist) — closed, but every failure false.

**Fix.** Both readers strip one trailing `\r`: the lookup reads every field up to it (a truncated line still fails closed); `--verify` trims the path length and leaves its line cursor on the `\n`.

**Verified.** `tests/gates/toolchain/deps_commit_pins_kept.sh` K10 (with a CRLF lock, a repointed tag is refused by name, the lock and `lib/` untouched) and K11 (`--verify` on a CRLF lock reports N verified, 0 failed, and leaves the lock CRLF). Each strip's mutant turns its own axis RED.

**Not covered.** `deps --verify` on a CRLF checkout of a COMMITTED `lib/` (`core.autocrlf=true` is Git for Windows' default) reports a hash mismatch for every file: the lock's rows hash the LF bytes, and the bytes really differ. The lock file is CRLF-tolerant now; the files it hashes are not. Today's remedy is `lib/** -text` (and `cyrius.lock -text`) in `.gitattributes`; normalising versus documenting is a decision, filed in roadmap.md's backlog. The 6.6.4 CHANGELOG's note that `--verify` on a CRLF lock "already failed loud" no longer describes the tool.

## CVE-90 — aarch64 frame displacements past 64 KiB were emitted as a 16-bit `movz`: loads and stores landed 64 KiB off, so a local after a 64 KiB buffer aliased the buffer

*Appended 2026-10-07 (cyrius 6.6.20, lane s-a64args, item BACKLOG-02's review; commit 795cdabc). Found by: the s-a64args lane while fixing BACKLOG-02 (aarch64 calls of 262+ arguments, promoted into 6.6.20 by the user) — first as its "met in passing" frame miscompile, then raised by its review round 1 as a major and fixed in the same bite. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — memory corruption in generated aarch64 code, reachable from untrusted input wherever a large local buffer holds it (`programs/tail.cyr`: the input chooses the value of a local the program then indexes and writes through). Needs a frame past 64 KiB. |
| **Class** | Incorrect calculation (CWE-682) in code generation — a displacement truncated to 16 bits — producing out-of-bounds reads and writes (CWE-787) in the compiled program. |
| **Affected** | aarch64 ELF and arm64 Mach-O output through 6.6.19 (one emitter); the native aarch64 compiler too. x86, Win64 and x86 Mach-O use disp32 and were never affected. In the folded stdlibs, sigil's `ed25519_verify` (72 KiB of banked stack arrays) and mabda's `_native_shader_compile_spirv` (82 KiB) address locals past 64 KiB, so every TLS / sigil / mabda consumer built for aarch64 carried the truncated addressing. |
| **Files** | `src/backend/aarch64/emit.cyr` — `_EFP_ADDR_X9`, `EFLADDR_X8`'s large-frame arm, `ESTORESTACKPARM`'s destination arm, new `_EMOV_XN` (the old `_EMOV_X16` generalised to any register) |
| **Fixed** | 6.6.20 |

**Vector.** `_EFP_ADDR_X9` — the address of every local and parameter past `ldur` / `stur`'s 256-byte reach — `EFLADDR_X8`'s large-frame arm (the X8 struct-result pointer) and `ESTORESTACKPARM`'s destination arm each built the displacement with ONE `movz #(abs & 0xFFFF)`, on a comment's word that "|disp| fits in 16 bits — >= 8192 locals are implausible". It does not: one `var buf[65536]` puts every later local past it.

**Impact.** A local after a 64 KiB buffer aliased a byte INSIDE the buffer, so writing the buffer rewrote the local; a fn of 8,192+ parameters homed parameter 8,192 over the saved fp and 8,193 over parameter 1's slot (SIGSEGV at n = 8,200, measured). The shipped tree reached it: `programs/tail.cyr` declares `var buf[65536]` then `total`, `rgo`, … — measured under qemu on the old build, `total` aliased `buf + 65528`, `rgo` `buf + 65520`, `start` `buf + 65496`, so an input of 65,528 bytes or more wrote its own bytes into `total`, and the next `read(0, &buf + total, 65536 - total)` went wherever the input said (old build: SIGSEGV on a 108 KB input; the fixed build's output equals x86's). In `ed25519_verify` the only such local, `hctxb`, is dead before anything writes its alias — no wrong verdict found; mabda's was not analysed. Arrays past the ~120 KB frame budget are static and never reached the path.

**Fix.** One helper, `_EMOV_XN(rd, v)`, emits `movz` plus a `movk #hi, lsl #16` only when v needs it, and all three sites use it (as do BACKLOG-02's x16 arms). A frame is capped far below 4 GiB (SFLC's 16,384 slots, EPATCHFRAME's 16 MB), so two halves cover it.

**Behaviour change.** None where no displacement passes 64 KiB: the old and new aarch64 cross-compilers produce byte-identical output for 554 of 607 tests / benches / fuzz harnesses / programs; each of the 53 that differ includes sigil or mabda (checked through the include closure) or is `programs/tail.cyr` or the edited test.

**Verified.** `tests/gates/codegen/wide_call_stack_unwind.sh`: an n = 8,200 row (the x16 `movk` arm and the last parameter's home and read as derived words, then a qemu run) and a frame probe (a local, a store through `&local` and a received struct, each after a 70,000-byte buffer: the derived `movk` before `sub x9, x29, x9` and `sub x8, x29, x9`, a qemu run, the host as the oracle). Mutants M5 (`_EFP_ADDR_X9` lone movz), M6 (`EFLADDR_X8`), M7 (`ESTORESTACKPARM`) and M8 (`_EMOV_XN` never emitting `movk`) each turn the gate RED, and the hardware twin `tests/tcyr/crossos/wide_call_stack_unwind.tcyr` (8,200-argument direct and `callptr` rows plus four frame rows, the first gating the rest so a regression fails instead of hanging) RED under qemu `-cpu cortex-a72`. The twin passes 198 / 198 crossos on pi and ecb at the lane; x86 two-step self-host and seed-derive unaffected (aarch64-only change); the native aarch64 compiler is a fixpoint under qemu.

**Not covered.** aarch64's `ESTRUCT_BYVAL_COPY` loads its byte count with a lone `movz x11, #(aligned & 0xFFFF)`: a by-value struct result of 64 KiB or more would copy (size mod 64 KiB) bytes, or loop ~2^64 times at exactly 64 KiB — read from the code, not run; backlog. cx's analogous frame-size defect (a frame of 64 KiB or more lowered sp by its size mod 64 KiB, inside the VM) is fixed in the same bite and listed in the CHANGELOG, not here.

## CVE-91 — `scripts/funcgate-stage.sh`'s live-home / store guard compared a physical path with raw ones: a symlinked `$HOME`, a parent of HOME or the source tree walked past it to `rm -rf`

*Appended 2026-10-07 (cyrius 6.6.20, lane g-gates, item RS-01; commits 1d9519b1, review af785bd6). Found by: the v6.6.x closeout audit's scripts review (item RS-01), confirmed by the skeptic pass; the `..` half was found in the lane's review. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P2 (Medium) — a missing guard on a destructive operator path: deletion of the user's home directory, the live toolchain store or the source tree. Not reachable from untrusted input — the operand is the operator's. |
| **Class** | Improper link resolution before file access (CWE-59) and path equivalence (CWE-41) in a safety check guarding `rm -rf`. |
| **Affected** | `scripts/funcgate-stage.sh` through 6.6.19, on a host whose HOME is (or passes through) a symlink — Fedora Atomic and FreeBSD link `/home` — or spelled with a trailing slash; the parent-of-HOME and working-directory cases on any host. |
| **Files** | `scripts/funcgate-stage.sh` — the live-home / store guard and new `_fg_real` (a copy of install.sh's `_rs_real`); `tests/gates/toolchain/funcgate_refuses_live_home.sh` |
| **Fixed** | 6.6.20 |

**Vector.** The guard compared the target's PHYSICAL path (`cd && pwd -P`) with the RAW strings `$HOME` and `$HOME/.cyrius`. Any spelling of HOME that was not already physical walked past it; the equality test never saw a PARENT of HOME or the working directory; and a target holding a `..` after a directory that does not exist yet passed as an unresolved string.

**Impact.** On such a box `funcgate-stage.sh … "$HOME/"` deleted the whole home directory and `… "$HOME/.cyrius"` a one-version store (the two-or-more-versions heuristic was the only thing left). A parent of HOME, or the working directory (the source tree), was deleted with no symlink at all. `"$HOME/missing/../.cyrius"` passed the guard, `mkdir -p` made `missing/`, and the restage wrote into the live one-version store (its `current` rewritten, a version added, its bin and lib links replaced); `"$HOME/missing/.."` deleted `$HOME/bin`.

**Fix.** Every side resolves to a physical path (`_fg_real`, a copy of install.sh's `_rs_real` — no `realpath(1)`, so AGNOS still runs it), and the guard refuses `/`, HOME or any directory holding it, the store or any directory holding it, and the working directory or any directory holding it. Because the resolver can resolve only the part of a path that already exists, it also refuses a target with a `.` or `..` component before resolving.

**Verified.** `tests/gates/toolchain/funcgate_refuses_live_home.sh` grows from 4 axes to 12. Axis 1 now uses a ONE-version store, so it exercises the store compare itself (with two versions the count heuristic refused first, and a mutation deleting the compare stayed green). Axes 5–12 cover a symlinked HOME (targets `$HOME/` and `$HOME/.cyrius`), a symlinked parent, a trailing-slash HOME, a parent of HOME, the working directory, and a `..` after a missing directory (onto the store, and onto HOME); they run from a scratch repo root, so a regression wipes a copy, never the checkout. Each fails against the old script; 11–12 also against the first cut of the fix. Green under `sh`, `bash -eo pipefail`, from `/`, and through check.sh.

**Not covered.** `scripts/install.sh`'s `_rs_real`, which this guard copies, has the same tail behaviour — a `..` after a directory that does not exist yet is never resolved — so any guard comparing its output can be walked past the same way; install.sh was not changed for it in 6.6.20 (backlog).

## CVE-92 — `cyrius publish` joined the version unquoted into a `git tag` shell line: command injection from `./VERSION` or the manifest

*Appended 2026-10-07 (cyrius 6.6.20, lane c-cmd, review round 1 of REFACTOR-11; commit 269cbd80). Found by: the c-cmd lane's review, while moving `cmd_publish` to the manifest version — the base CLI ran a `./VERSION` of `1.0;touch PWNED` through `sys_system` (measured: `PWNED` created). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P3 (Low) — command injection from a project file: a contributor's one-line VERSION change executes on the maintainer's machine when the maintainer publishes. Needs the maintainer to run `cyrius publish` on a tree whose version file they did not read. |
| **Class** | OS command injection (CWE-78). |
| **Affected** | `cyrius publish` through 6.6.19, on every host with a shell. |
| **Files** | `cbt/commands.cyr` — `cmd_publish`, new `_publish_version`; `cbt/core.cyr` — `_project_version()` (the version source) |
| **Fixed** | 6.6.20 |

**Vector.** `cmd_publish` joined the version, unquoted, into `git tag -a v<ver> -m 'Release v<ver>'` and handed the line to `sys_system` (`/bin/sh -c`).

**Impact.** A `./VERSION` holding `1.0;touch PWNED` ran `touch` (measured against the 6.6.19 CLI); any command fits.

**Fix.** A version holding a byte outside a tag name's charset (`0-9 A-Z a-z . - + _`) is refused by name and never reaches a shell. The same check covers the manifest `[package] version` that publish now reads (`_project_version()`: the manifest's version, else `./VERSION`); publish also refuses — before distlib runs or anything is tagged — a manifest and `./VERSION` that both name a version and disagree, and a project with neither.

**Verified.** `tests/gates/toolchain/distlib_bundle_selfcheck.sh` axis 10, with a `git` recorder first on PATH: tag == the bundle's stamp for a manifest-only and a `${file:VERSION}` project; a disagreeing pair refused with nothing tagged or generated; `4.5.5;touch PWNED` refused, and the shell never runs it. Against the pre-change CLI: 9 FAIL.

**Not covered.** The security re-scan's SEC-02 (`[build] output` reaching `/bin/sh` and `cmd.exe` unquoted) is open, outside this release (CHANGELOG *Known*).

## CVE-93 — `cyrius distlib`'s RETIRED-name blast door scanned a 256 KB capture: warning volume skipped it, and a bundle calling a deleted stdlib name was published

*Appended 2026-10-07 (cyrius 6.6.20, lane c-cmd, item CBT-02; commit 871892ad, review f20bc3ea). Found by: the v6.6.x closeout audit's CLI review (item CBT-02), confirmed by the skeptic pass. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P3 (Low) — supply-chain integrity: a bundle that self-checks green and fails at the consumer. Needs a producer whose self-check compile emits more than 256 KB of warnings ahead of the retired call. |
| **Class** | Protection mechanism failure (CWE-693): a security check reading a bounded window of its evidence and treating the unread rest as clean. |
| **Affected** | `cyrius distlib`'s self-check from v6.6.2 (the RETIRED-name door) through 6.6.19. |
| **Files** | `cbt/commands.cyr` — new `_distlib_scan_retired_file` (replacing the fixed-buffer scan); `tests/gates/toolchain/distlib_bundle_selfcheck.sh` |
| **Fixed** | 6.6.20 |

**Vector.** The v6.6.2 check — a bundle calling a name the stdlib has RETIRED (`payload`, `tag`) must fail even under the self-check's `--allow-undef` — scanned the self-check's stderr capture through a fixed 256 KB buffer.

**Impact.** A bundle whose compile warned more than 256 KB before the retired call — measured: 1,400 long undefined hook names, a 326,629-byte capture, the `payload` warning at byte 326,490 — was written at rc 0: it would self-check green and detonate at the consumer, the class the door exists to stop.

**Fix.** The capture is read back WHOLE from disk (`_distlib_scan_retired_file`). It is created before the compile, so a capture that cannot be created, or cannot be read back whole, refuses the bundle by name instead of reading as "no retired name".

**Verified.** `distlib_bundle_selfcheck.sh` axis 7: the ~326 KB repro, with an anti-vacuous measurement that the capture really is over 256 KB and the `payload` warning really starts past byte 262,143. The old 256 KB read: 3 FAIL. That gate's RETIRED-name axes also sat inside the `if [ "$fails" = "0" ]` that prints PASS and exits 0, so they could never fail it — measured: with `payload` dropped from the retired list the old gate printed "FAIL: a bundle calling the deleted 'payload' self-checked CLEAN" and still exited 0 PASS. They count now. All 15 `distlib_*` gates green.

**Not covered.** `cyrius lint`'s syntax pre-pass reads its compiler capture through a fixed 64 KB buffer (the same shape on a non-security path) — backlog.

## CVE-94 — `cyriusly uninstall ../versions` deleted the whole toolchain store, the active version included; `install` and `cmdtools` spliced their operands into `sh -c`; the compiled `install` fetched install.sh from `main`

*Appended 2026-10-07 (cyrius 6.6.20, lane c-pin, item RS-04; commits 53715a2c, review 62a2a3f0, 4357f4b7, 06caaab7, 52459bcf, 2e976ba0). Found by: the v6.6.x closeout audit's scripts review (item RS-04) and its security re-scan (SEC-06), confirmed by the skeptic pass; the `cmdtools` splice and the `main` URL were raised in the lane's review. A CVE-21 residual (the `main` URL). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P3 (Low) — destruction of the toolchain store and command injection, but only through the operand the user types (or a script passes); the `main` fetch let a compromised or mistaken branch install where CVE-21 had pinned the tag. |
| **Class** | Path traversal (CWE-22) into `rm -rf`; OS command injection (CWE-78); download of code from a mutable reference (CWE-494). |
| **Affected** | The compiled `cyriusly` (`programs/cyriusly.cyr`, the Linux x86_64 tarball's `bin/cyriusly`) and the shell twin `scripts/cyriusly` (the aarch64 and macOS tarballs' `bin/cyriusly`, and install.sh's fallback) through 6.6.19: `uninstall`, `install`, `use`, `cmdtools`. |
| **Files** | `programs/cyriusly.cyr` — the operand rule, new `_cy_run_argv` (fork + execve with the environment forwarded; `exec_vec` on PE), `install` / `uninstall` / `cmdtools`; `scripts/cyriusly` — the operand rule in `use` and `uninstall` |
| **Fixed** | 6.6.20 |

**Vector.** `uninstall` built `rm -rf <home>/versions/<ver>` and ran it through `/bin/sh -c` with no check on `<ver>`, and the active-version guard is a string compare. `install` spliced its operand into `curl … | CYRIUS_VERSION=<ver> sh`; `cmdtools` spliced both operands into `sh scripts/cyriusly cmdtools <a> <t>`; `use ../x` wrote that pin into `cyrius.cyml`, or with `--global` re-pointed `~/.cyrius/bin` outside the store. The compiled `install` fetched install.sh from the mutable `main` branch — CVE-21 (v6.2.30) had moved only the shell twin to the immutable tag.

**Impact.** On 6.6.19: `cyriusly uninstall ../versions` printed "Uninstalled Cyrius ../versions", exit 0, every version gone; `uninstall 6.6.18/../6.6.19` deleted the ACTIVE 6.6.19 outright. `cyriusly install '6.6.19;cmd'` ran `cmd`, and `cyriusly cmdtools 'list;cmd'` ran `cmd`.

**Fix.** Both peers refuse, by name with exit 1, a version operand that is not a leading digit followed by `[0-9A-Za-z.-]` with no `..` (`scripts/version-bump.sh`'s charset plus a `..` ban), in `use`, `install` and `uninstall`, ahead of the active-version guard. The compiled `install`, `uninstall` and `cmdtools` run argv — a constant `/bin/sh -c` script with the version or directory as a positional parameter, or the twin with its operands as arguments — forwarding the environment as before, so no shell parses an operand. The compiled `install` fetches `…/cyrius/<version>/scripts/install.sh`, like the twin.

**Verified.** `tests/gates/toolchain/cyriusly_version_operand_refused.sh` (new, registered in check.sh): both peers against a throwaway store holding an active and an inactive version, with a fake `curl` on PATH — six uninstall operands (five path-shaped and `6..6`, which only the `..` ban refuses), three shell-shaped install operands, `use ../versions` and `use 6..6` (local and `--global`), controls (a real uninstall, an install on the TAG's installer, a switch; the active version still guarded), a static check that install / uninstall / cmdtools run no shell line, cmdtools injection rows, and a static PE build of the file. The 6.6.19 tree is RED (the store deleted, the injected command ran, install.sh fetched from `main`); mutants of the operand rule and of the `main` URL are each RED. The aarch64 build smoked under qemu.

**Not covered.** The compiled `cyriusly cmdtools` still finds the shell twin relative to the CURRENT directory, so inside a repository that ships `scripts/cyriusly` it runs that repository's script. The x86_64 store ships no copy of the twin, so "resolve it from the install" has nothing to resolve — filed as `docs/development/issues/2026-10-06-cyriusly-cmdtools-runs-the-cwd-script.md` (needs a packaging decision, a CVE id and a slot). → Fixed at 6.7.3 as **CVE-103** (below).

## CVE-95 — manifest strings reached the terminal raw (escape-sequence injection from any manifest in the dep graph), and `[package] name` injected a live line into a distlib bundle

*Appended 2026-10-07 (cyrius 6.6.20, lane c-deps, items REFACTOR-06 and CBTB-07; commits b43221a2, a9d9d523, review 6eb48bc0, 4360c717, c8aa16b6). Found by: the v6.6.x closeout audit's refactor pass (REFACTOR-06: the dep-name validator lacked the tag validator's control-byte rule) and CLI review (CBTB-07: the `[embed]` refusal), confirmed by the skeptic pass; the distlib echoes were found in the lane's reviews. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P3 (Low) — terminal escape injection (clear the screen, retitle the window via OSC, forge an earlier line of output) from a manifest the user may never have written, plus code injection into a published bundle from a producer's own `[package] name`. |
| **Class** | Improper neutralisation of escape, meta or control sequences (CWE-150) in output; improper neutralisation of a line delimiter (CWE-93) into generated source. |
| **Affected** | `cyrius deps` and the auto-deps verbs, `cyrius build`'s `[embed]` refusal (since 6.6.19; a TOML `\u001b` decodes to a raw ESC since 6.6.17), `cyrius distlib`, the pin echoes — through 6.6.19. |
| **Files** | `cbt/deps.cyr` — `_shown` / `_ew_shown` (the one escaping printer), `_dep_name_unsafe` (silent; `_dep_reject_unsafe_name` removed), every refusal and warning in the resolver, `_git_cache_refuse`'s declared URL; `cbt/manifest.cyr` — `_embed_refuse`, the symlink-component message, the pool-total listing; `cbt/commands.cyr` — distlib's `[lib] modules` / `[lib] embed` echoes and refused requires leaves, new `_distlib_bad_pkg_name`; `cbt/cyrius.cyr` — the wrapper's pin lines |
| **Fixed** | 6.6.20 |

**Vector.** The resolver echoed manifest strings raw into its errors and warnings — a dependency's `path`, its `git` URL (the declared one, and the cached origin in the CVE-43 origin refusal, whose declared URL a TRANSITIVE manifest controls and which the clone path's unsafe-character check never sees on a reused cache), a `modules` entry, sub-module names and the destination paths built from them. `_embed_refuse` printed the `[embed]` NAME and path verbatim — a path refused precisely for holding a control character. distlib echoed `[lib] modules` entries, a `[lib] embed` entry `[embed]` does not declare, and refused requires leaves raw; the wrapper, the resolver, the lock guard and `--version`'s `manifest-pin:` line echoed the `cyrius` pin raw. And `cyrius distlib` checked `[package] name` with the dep-name rule, which allowed a newline.

**Impact.** `[embed] X = "a\u001b]0;pwned\u0007b"` made `cyrius build`'s refusal carry a live OSC window-title sequence to the terminal (`od -c`: `033 ] 0 ; p w n e d \a`); a quoted NAME holding a raw ESC did the same; a dep `path` or `modules` entry holding ESC or an OSC sequence reached either stream raw. `name = "nm\nvar INJECTED = 7;\n#"` wrote `dist/nm?var INJECTED = 7;?#.cyr` with a LIVE `var INJECTED = 7;` line in the bundle header — code a consumer compiles.

**Fix.** The name rule is silent and every refusal is one line from the caller that knows what it refused (a modular sub-module now says `error: [deps.X] modular sub-module '…' is not a usable name …`). Every manifest string a `cyrius deps` error or warning echoes — dep name, tag, git URL, path, `modules` entry, module basename, sub-module, the `lib/` destination and dep-side source paths, the dep-tree file and submodule paths a cache refusal names — goes through `_ew_shown` (bytes below 32, 127 and above shown `\xNN`), as do distlib's echoes and every echo of the pin; `_embed_refuse` shows the NAME and path through `_shown`, so an invisible HFS+-ignorable code point (U+200C, U+FEFF) in a refused path is visible too. Recovery advice that names a clone dir (`rm -rf …`, the offline restore) stays raw so it can be pasted; the name and tag in it are refused for control bytes. distlib's `[package] name` takes the profile rule `[A-Za-z0-9_-]{1,32}` (`_distlib_bad_pkg_name`, refused by name, nothing written).

**Behaviour change.** A `[package] name` outside the profile rule is refused by distlib; every one of the ecosystem's 126 package names complies.

**Verified.** `tests/gates/toolchain/manifest_strings_shown_escaped.sh` (new): E1–E5 and E4b (a `path` and a `modules` entry holding ESC or an OSC sequence shown escaped with nothing raw on either stream; modular sub-modules `../x` and one holding ESC each get one named line; the newline package name and `name = "my lib"` refused with no bundle written; `my-lib_2` still bundles), E6 (a cached git dep re-declared with an OSC sequence in its URL), E7 (distlib and `distlib --modular` module-not-found with an OSC entry), E8 (an OSC pin: the wrapper's and the resolver's not-installed lines and `--version`'s manifest-pin line), E9 (`[lib] embed` holding an OSC sequence); floor 11 (10 without git). RED on the slot-open CLI and under each ledger mutant (each echo put back raw). `tests/gates/toolchain/embed_manifest_refusals.sh` axis 7 (a path holding ESC / BEL and a quoted NAME holding ESC refused and shown `\x1b` / `\x07`, nothing raw; the two HFS rows now expect `\xNN`), RED on the slot-open CLI and on the path-raw and NAME-raw mutants.

**Not covered.** The tag rule refuses C0 and DEL but not UTF-8 C1 bytes (`\xc2\x9b`, a CSI on terminals that honour C1), and a tag is echoed raw inside the clone-dir recovery advice so it can be pasted — reached only on a cache refusal; backlog.

## CVE-96 — native TLS's Ed25519 signer left a copy of the long-term private seed in an allocator buffer on every signature

*Appended 2026-10-07 (cyrius 6.6.20, lane l-net, item NET-05; commit bc08db51). Found by: the v6.6.x closeout audit's network-library review (item NET-05), confirmed by the skeptic pass. The CVE-70 class (key material not zeroised). Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.6.20 spends CVE-79 … CVE-96.*

| | |
|---|---|
| **Severity** | P3 (Low) — defence in depth: reading the copies needs a second primitive (a heap over-read, a core dump, swap, a debugger), and `KEY_MAT` itself already lives in the same allocator for the ctx's lifetime, so this multiplies an existing exposure rather than opening a new class. A long-running server accumulated one more copy of its long-term key per handshake. |
| **Class** | Sensitive information in a resource not removed before reuse (CWE-226); improper clearing of heap memory (CWE-244). |
| **Affected** | The native TLS stack's Ed25519 signing through 6.6.19: a server's TLS 1.3 CertificateVerify and TLS 1.2 ServerKeyExchange, and since 6.6.14 an mTLS client's TLS 1.2 / 1.3 CertificateVerify. Every target. |
| **Files** | `lib/tls_native_hs13.cyr` — `_tn_sign`'s Ed25519 arm |
| **Fixed** | 6.6.20 |

**Vector.** `_tn_sign`, the one signer of those messages, expanded an Ed25519 key with `ed25519_keypair(kmat, sk64, pk32)` into two `_tn_alloc` buffers and never wiped them; sigil writes `seed || pk` into `sk_out` and wipes only its own temporaries.

**Impact.** Every Ed25519 handshake signature left one more copy of the private seed in the no-free heap, or in the connection's arena until it was reset — on both exits. 6.6.15's CVE-70 wipe covered the ephemeral ECDHE secrets only.

**Fix.** The expanded key is a `secret var sk64[64]`, zeroised on every return; `pk32` is a plain stack array; the arm allocates nothing, so its `TLS_ERR_OOM` returns are gone (the doc comment names `TLS_ERR_BUFFER_FULL`, the arm's other error).

**Verified.** `tests/tcyr/crypto/tls_native_ed25519_sign_wipe.tcyr` (new, 9 rows; no socket — the signer is called on a server ctx built on an arena): the arena holds the seed exactly once after `load_creds` (the control that proves the scan sees `KEY_MAT`) and still once after three signatures (it was 4); the signatures are 64 bytes, scheme ed25519, and verify; a window over the released stack, read right after `_tn_sign` returns, finds no copy, while a plain local copy left at the same depth (the control) must be found. Mutants: the pre-fix `_tn_alloc` buffers fail the arena row (4 copies); a plain, non-`secret` `var sk64[64]` fails the stack row. Passes on x86_64, under qemu-aarch64 and under wine.

**Not covered.** `KEY_MAT` (the long-term key the ctx holds) is unchanged — it lives for the ctx's lifetime by design.

## CVE-97 — a manifest `[build] output` reached `/bin/sh -c` unquoted on macOS (the ad-hoc codesign) and was cmd.exe's quoted redirect target on Windows

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-shell SEC-02). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P1 |
| **Fixed** | 6.6.20 |

**Vector and impact.** A manifest `[build] output` reached `/bin/sh -c` unquoted on macOS (the ad-hoc codesign) and was cmd.exe's quoted redirect target on Windows — a `"` in it ran the rest of the line (measured under wine) — and on Linux it wrote the 0755 binary outside the checkout (`../`, absolute, through a committed directory link).

**Fix.** `cbt/manifest.cyr` `_cfg_output_refused` (new; the [embed] path rules `_proj_path_bad` applied to a manifest output — an output given as an argument stays the operator's), `cbt/build.cyr` `_macho_codesign` (execs `/usr/bin/codesign` by argv, no shell) and `_w_cmd_operand_ok` at every cmd.exe line builder, `lib/process_win.cyr` `_w_cmd_operand_bad` (a `"`, `%` or control byte is refused).

**Verified.** `tests/gates/toolchain/build_output_confined.sh` (mutation: the refusal off → 18 rows red).


## CVE-98 — `cyrius update`, `cyrius deps --lock` (and every auto-deps verb's relock), `cyriusly use`, `cyrius fmt --write` and `cyrius port` wrote a checkout's o

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-symlink SEC-03). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P1 |
| **Fixed** | 6.6.20 |

**Vector and impact.** `cyrius update`, `cyrius deps --lock` (and every auto-deps verb's relock), `cyriusly use`, `cyrius fmt --write` and `cyrius port` wrote a checkout's own files THROUGH a committed symlink to any path — a dangling `cyrius.cyml -> ~/.ssh/authorized_keys` beside a `cyrius.toml` holding a key line made `cyrius update` create the key file.

**Fix.** `lib/io.cyr` `_io_replace_target_in(root, rel)` / `_io_replace_atomic_in` / `_io_contain_refusal`: a link is followed only while every hop is relative, stays under the project root, passes no directory link, and never lands in or on `.git` (any spelling); every listed writer goes through it.

**Verified.** the sec-symlink gates registered in scripts/check.sh (containment rows per writer, `.git` rows, directory-link `..` rows).


## CVE-99 — `[package] version = "${file:PATH}"` read ANY file

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-shell SEC-04). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P2 |
| **Fixed** | 6.6.20 |

**Vector and impact.** `[package] version = "${file:PATH}"` read ANY file — absolute, `..`, `.git/config`, through a committed symlink, a FIFO (hang) — into the built binary (`#@pkgver`) and `--print-config`, and a multi-line value (or a literal with a `\n` escape) was compiled as SOURCE: the [embed] hardening's bypass; the ./VERSION fallback had the same reach.

**Fix.** `cbt/manifest.cyr` `_proj_path_bad` / `_proj_read` (one checker for every manifest key that names a project file, shared with [embed]); `cbt/deps.cyr` `_dep_expand_file_interp` and `_project_version` read through it and refuse a control byte.

**Verified.** `tests/gates/toolchain/pkgver_file_interp_confined.sh`.


## CVE-100 — `file_write_atomic` (lib/io.cyr) and the CLI's `_aw_open` opened their predictable temp `"<path>.cyrtmp.<pid>.<ctr>"` with O_WRONLY|O_CREAT|O_TRUNC, s

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-tmp SEC-05). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P2 |
| **Fixed** | 6.6.20 |

**Vector and impact.** `file_write_atomic` (lib/io.cyr) and the CLI's `_aw_open` opened their predictable temp `"<path>.cyrtmp.<pid>.<ctr>"` with O_WRONLY|O_CREAT|O_TRUNC, so a symlink planted at the next name redirected the write into the file it named and was then renamed over the path (cyrsign `.sig`, cyrfmt `--write`, cyrius-init, sigil trust-store writes, the CLI's lock/index writes).

**Fix.** `lib/io.cyr` `_io_tmp_open`: the temp is created O_EXCL|O_NOFOLLOW, a taken name is skipped (up to 64, then refused by name); `_aw_open` and `file_write_atomic` both use it.

**Verified.** `tests/gates/toolchain/atomic_temp_exclusive.sh`, `tests/tcyr/crossos/atomic_write_temp_exclusive.tcyr`.


## CVE-101 — with a trusted verifier present, a release whose signature had been STRIPPED installed

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-install SEC-07 (+ SEC-06's remainder)). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P2 |
| **Fixed** | 6.6.20 |

**Vector and impact.** With a trusted verifier present, a release whose signature had been STRIPPED installed — in all three installers (`scripts/install.sh` only required a signature at or above its local TOFU floor; `scripts/ci.sh` and `scripts/install.ps1` had no floor; install.ps1 also took the version from the download's own name); the compiled `cyriusly install` fetched `install.sh` from `main`, not the tag.

**Fix.** the first signed release (6.2.31) is a constant in all three installers: with a verifier present a release at or above it — or any malformed version — whose signature cannot be fetched is refused by name; an auto-resolved "latest" below it is refused; `CYRIUS_ALLOW_UNSIGNED=1` / `-AllowUnsigned` stays the explicit override; install.ps1 trusts no version the download names.

**Verified.** `tests/gates/toolchain/install_signature_required.sh` (install.sh / ci.sh / install.ps1 in step); install.ps1 measured on cass.


## CVE-102 — on Windows the CLI started `cmd` and `certutil` by a BARE name, and CreateProcessW searches the parent's current directory before System32: a `cmd.exe

*Appended 2026-10-07 (cyrius 6.6.20, lane sec-pe SEC-08). Found by: the v6.6.x closeout security re-scan (`~/.cache/cyrius-6620/audit/security.md`); its findings were missing from the audit's structured result and were carried by separate lanes at integration.*

| | |
|---|---|
| **Severity** | P2 |
| **Fixed** | 6.6.20 |

**Vector and impact.** On Windows the CLI started `cmd` and `certutil` by a BARE name, and CreateProcessW searches the parent's current directory before System32: a `cmd.exe` committed to a checkout ran on its first `cyrius build`, and a committed `certutil.exe` chose the hashes `cyrius deps --lock` recorded (measured on cass, Windows 11).

**Fix.** `lib/process_win.cyr` `_win_sys_exe` (GetSystemDirectoryW via GetProcAddress + callptr) gives the quoted absolute path for every cmd.exe / certutil.exe spawn in `cbt/build.cyr`, `cbt/deps.cyr` and `lib/process_win.cyr`; a caller refuses when the directory cannot be read and never falls back to the bare name.

**Verified.** `tests/gates/platform/pe_system_programs_absolute.sh` (wine, planting in the caller's own directory), `tests/tcyr/crossos/system_programs_not_from_cwd.tcyr`.


## CVE-103 — the compiled `cyriusly cmdtools` ran whatever `scripts/cyriusly` the CURRENT directory held

*Appended 2026-10-07 (cyrius 6.7.3, repair lane `cyriusly`). Found by: the 6.6.20 lane c-pin review (round 1, the RS-04 sibling), recorded as CVE-94's "Not covered" remainder and filed as `docs/development/issues/2026-10-06-cyriusly-cmdtools-runs-the-cwd-script.md`. Not part of the 2026-09-03 sweep: recorded here because this is the live ledger. 6.7.3 spends CVE-103.*

| | |
|---|---|
| **Severity** | P2 (Medium) — a toolchain verb executes repository-shipped code with the user's privileges (the CBT-01 class); the trigger is one rarely-run verb inside a hostile checkout, not every `cyrius` verb. |
| **Class** | Untrusted search path (CWE-426) — a helper resolved relative to the current directory. |
| **Affected** | The compiled `cyriusly` (`programs/cyriusly.cyr`, the Linux x86_64 tarball's `bin/cyriusly`) from v5.11.10, when the verb was ported, through 6.7.2: `cmdtools` with any action, `list` included. The shell twin `scripts/cyriusly` (the aarch64 and macOS tarballs' `bin/cyriusly`) carries the verb itself and was not affected. |
| **Files** | `programs/cyriusly.cyr` — new `_cy_twin_path`, `_cmd_cmdtools`; `scripts/install.sh` — new `_twin_required` / `_install_twin`, called from the refresh-only (with a pre-check before anything is written), tarball and source-bootstrap paths; `scripts/verify-store.sh` — judges and restores the twin; `.github/workflows/release.yml` (both Linux tarballs), `scripts/build-macos-arm64-tarball.sh`, `scripts/build-macos-x86-tarball.sh` — stage it at `scripts/cyriusly` |
| **Fixed** | 6.7.3 |

**Vector.** `_cmd_cmdtools` delegated to the shell twin as `/bin/sh scripts/cyriusly cmdtools <action> <tool>` — the literal `scripts/cyriusly`, a path relative to the current directory. Nothing else could have been meant: no store held a copy of the twin (the x86_64 slot's `bin/cyriusly` is the compiled binary itself, and `[release].scripts` does not list the twin), so the verb only ever worked inside a cyrius checkout.

**Impact.** Measured on 6.7.3 (both the tree's `build/cyriusly` and the installed one): in a directory holding a `scripts/cyriusly` that prints a marker, `cyriusly cmdtools list` printed "PWNED from the checkout: cmdtools list", exit 0, and `cmdtools install starship` ran it too. Any cloned repository shipping a `scripts/cyriusly` ran with the user's privileges the first time the user asked cyriusly about prompt integrations there. From an unrelated directory the verb failed (`/bin/sh: scripts/cyriusly: No such file or directory`, exit 127).

**Fix.** The twin is part of the store: every writer installs it at `<home>/versions/<v>/scripts/cyriusly` — `install.sh`'s refresh-only path (refusing, before anything is written, a tree whose `[release].bins` ship the compiled cyriusly without the twin), its tarball path (lenient: a tarball cut before 6.7.3 has no `scripts/`) and its source-bootstrap path; the release builders stage it in all four POSIX tarballs; `cyrius pulsar`, `version-bump.sh` and check.sh's staging reach the store through the refresh-only path. `cmdtools` runs `<home>/versions/<current>/scripts/cyriusly` only, refusing by name, exit 1, when `<home>` is not absolute (a relative `CYRIUS_HOME` is current-directory resolution again), when `current` is not a version's shape (`../evil` is a path), or when the active slot has no twin. There is no fallback, and the binary's own slot is deliberately not tried: a binary run from a shared directory would resolve a twin beside it that another user planted. `verify-store.sh` compares the twin with the tag's and reports a 6.7.3+ slot without it as MISSING; `--restore` rewrites it.

**Verified.** `tests/gates/toolchain/cyriusly_version_operand_refused.sh` axes 7 and 9: a hostile checkout's script never runs (`list` and `install starship` run the store twin), an unrelated directory lists, and no twin / `current = ../evil` / a relative home are each refused by name with nothing run; the tarball path (a fabricated 9.9.9 tarball whose `bin/cyriusly` is the binary built from the tree, installed hermetically) lands the twin byte-identical and the INSTALLED binary, run from the hostile checkout, runs the store twin; the refresh-only path lands it; a tree whose bins ship cyriusly without the twin is refused with nothing written; static rows pin the source-bootstrap call and the four builders' copies. The 6.7.2 `_cmd_cmdtools` turns 7a–7e and 9a RED, and each guard's mutant turns exactly its own row RED. `tests/gates/toolchain/released_slot_written_from_tag.sh` axes 7, 7b and 8: verify-store names a drifted twin DIFFERS and a missing one MISSING, and `--restore` writes the tag's bytes.
