# Cyrius Security Audit — 2026-07-27

> **Routine full audit** on the CLAUDE.md "Security Audit Process" cadence
> (*full audit every 2-3 minors*), run as compliance item 9 of the **v6.4.x
> closeout**. It supersedes [`2026-06-10-deep-dive-review.md`](2026-06-10-deep-dive-review.md)
> (cycc 6.1.31), whose last identifier is CVE-31.
>
> **This document is a RECORD, not a work list.** Every finding below was
> already fixed and shipped in **v6.4.81** before this file was written — an
> audit's output is fixes, not a longer backlog. It exists so the next auditor
> can see what the scan found, what it got *wrong*, and which gates were lying.

**Reviewer:** Claude (Opus 5), closeout workflow
**Version:** cycc 6.4.82 (1,108,368 B) — findings fixed at **6.4.81**
**Scope:** the untrusted-input surface of the compiler front end
(`src/frontend/`), the CLI's temp-file and dependency-integrity surface
(`cbt/`), and the gates that are supposed to be watching both
(`tests/heapmap.sh`, `programs/checks/`, `scripts/*-gate.sh`).
**Methodology:** targeted re-scan of the CLAUDE.md item-2 patterns
(`sys_system`/`sys_execve` on user-controlled args, `READFILE`/`sys_open` on
unvalidated paths, `store8`/`store64` near region boundaries, predictable temp
paths) → adversarial verification of every candidate against live source →
**empirical repro on the host for each retained finding** (not a reading of the
code alone) → fix → re-run. Seven candidates entered verification; **five were
confirmed and fixed, two were refuted and are recorded below so they are not
re-filed.**

CVE IDs continue the 2026-06-10 sequence. There are no `DD-NN`-class
(non-security) rows this pass — this was a security re-scan, not a project-wide
deep dive.

---

## Headline

The prior review's through-line was *"loud failure silently turned into silent
failure."* This one's is narrower and worse: **the map and the gate described
something other than what the code did.**

1. **cycc smashes its own heap on a long `include` path** — no flag, no opt-in,
   from ordinary source text. `include "zzz/<31490 A's>.cyr"` → **SIGSEGV, exit
   139**. Compiling untrusted source is the compiler's entire job, so this is
   the wrong side of the only trust boundary the tool has (**CVE-32**).
2. **The heap map hid it for three minors.** `src/main.cyr` documented that
   scratch at `0x190500 [256]` — an address **no code has ever written** (every
   use is `0x190400`, unbounded). `tests/heapmap.sh` validated the comment,
   found no overlap, and reported PASS across every closeout since.
3. **The security control was the subvertible part.** `cyrius deps --verify`
   read its SHA-256 digests, and the force-pushed-tag refusal read its git HEAD,
   out of fixed, world-writable, no-`O_EXCL` `/tmp` names (**CVE-35**).

All five confirmed findings were small. None needed a heap-layout change; all
shipped in one release with the gate GREEN.

---

## Security findings (CVE-32 …)

| CVE | Sev | Title | Files | Fixed |
|---|---|---|---|---|
| **CVE-32** | **High** | Three unbounded include/`#ref` filename capture loops overrun the `S+0x190400` scratch — **SIGSEGV from source text**; silent PP-state corruption below the threshold | `src/frontend/lex_pp.cyr:1997,2370,2497` | v6.4.81 |
| **CVE-33** | **High** | `READFILE`'s `CYRIUS_HOME/lib/` fallback composes an unbounded path into a **512-byte** local — both copy loops unbounded | `src/frontend/lex.cyr:610,612,614` | v6.4.81 |
| **CVE-34** | Medium | Long `$HOME` overruns `_cyrius_lib` — a *bare top-level* `[256]` array is 2048 B, and the copy was bounded only by `elen` (≤4096) with ~32 B appended after | `src/frontend/lex.cyr:208,275` | v6.4.81 |
| **CVE-35** | Medium | Dependency-integrity controls read their results from predictable shared `/tmp` (no `O_EXCL`, no `O_NOFOLLOW`) — lockfile digests and the force-pushed-tag refusal | `cbt/deps.cyr:2025,2066` | v6.4.81 |
| **CVE-36** | Medium | `cyrius run/test/fuzz/bench/soak` compile to a predictable `/tmp` name and then **execve** it | `cbt/commands.cyr:150,164,250,291,1518` | v6.4.81 |

Detail follows. Every claim below was re-verified against live source while
writing this file.

---

### CVE-32 (High) — heap smash from an `include` path

`PREPROCESS` captures the filename of `include`, of a post-macro-expansion
`include`, and of `#ref` into one shared scratch at `S+0x190400`. **All three
loops were `store8(fname + fi, fc); fi = fi + 1;` with no bound at all.**

The scratch's neighbour is the include-count cell at `S+0x197F00`, i.e. exactly
`0x7B00` = **31,488 bytes** away. That number is the finding:

| filename length | observed |
|---|---|
| 31,480 chars | clean `cannot open include file` error, exit 1 |
| **31,490 chars** | **SIGSEGV, exit 139** |

The boundary is exact, which is what makes it a *heap* bug rather than a length
bug: at 31,488 the write starts landing in the include-count cell, and that
count is then used as an unbounded scan limit by `PP_ALREADY_INCLUDED`
(`while (i < cnt)` over `S + 0x1C0000 + i * 128`, `lex_pp.cyr:249`). Below the
threshold nothing crashed — it silently corrupted whatever preprocessor state
sat between.

**Vector.** Ordinary `.cyr` source. No flag, no environment, no privileged
position. `include` paths are attacker-controlled the moment you compile code
you did not write, which is the compiler's normal mode of operation.

**Impact.** Denial of service at minimum; below the crash threshold, controlled
overwrite of adjacent preprocessor state with attacker-chosen bytes.

**Fix (v6.4.81).** Bounded at 4096 B — the scratch runs to `0x191400`, clear of
the `#ref` read buffer at `0x191800` — through one shared
`PP_FNAME_TOO_LONG()` helper (`lex_pp.cyr:287`) called from all three sites.
Split into its own fn rather than inlined **because `PREPROCESS` is already near
cybs's per-fn literal/global ceiling**; three inlined error strings is exactly
the shape that passes the cycc fixpoint and then fails `seed-derive` silently.

**Why it lived three minors: the map documented a fiction.** `src/main.cyr:90`
recorded this region as `0x190500  include_fname [256]` — one page high and 16×
too small. No code has ever written `0x190500`. `tests/heapmap.sh` therefore
validated a region that exists only in a comment, found no overlap, and reported
PASS at every closeout. The map is corrected in all five forks to
`0x190400  include_fname [4096]`.

---

### CVE-33 (High) — unbounded composition into a 512-byte local

When an `include "lib/…"` fails to open, `READFILE` retries under
`$HOME/.cyrius/versions/<VER>/lib/`. It built that path into `var fbuf[512]`
with **neither** copy loop bounded: the first copies `_cyrius_lib_len` bytes
(which can reach ~2 KB — see CVE-34), the second copies the caller-supplied
`path` until NUL.

**Vector.** Same as CVE-32 — source text, via the include path, combined with an
environment the user does not necessarily control on a shared box.

**Impact.** Stack-frame overrun with attacker-influenced bytes.

**Fix (v6.4.81).** `var fbuf[4096]` (matching the CVE-32 bound), both loops stop
at 4095, and a truncated path simply fails to open and falls into the existing
`-1` / "cannot open include file" path — `lex.cyr:610-615`.

*Note for future readers:* `var x[N]` as a **local** is N **bytes**, so the old
`[512]` really was 512 B. The same syntax at top level is N×8. That asymmetry is
load-bearing in the next finding.

---

### CVE-34 (Medium) — `_cyrius_lib` overflow from a long `$HOME`

`var _cyrius_lib[256]` (`lex.cyr:208`) is a **bare top-level array**, so it is
256 × 8 = **2048 B** under the v6.4.10 contract — not 256. `_init_cyrius_lib`
scans `/proc/self/environ` for `HOME=` and copied its value bounded only by
`elen` (≤ 4096, the read size), then appended `/.cyrius/versions/<VER>/lib/`
(~32 more bytes) **unconditionally**.

**Vector.** A `HOME` longer than ~2 KB. Local, and requires influence over the
environment cycc runs under — hence Medium, not High.

**Impact.** Overwrite of whatever follows `_cyrius_lib` in the globals region
with environment-controlled bytes, before any source has been read.

**Fix (v6.4.81).** The copy now reserves the suffix (`if (wi >= 1984) { return 0; }`,
`lex.cyr:278`) and **degrades to "no fallback"** rather than smashing — the same
`return 0` the `efd < 0` path already used. The `CYRIUS_HOME` lib path is
best-effort by design, so giving it up is the correct failure mode.

---

### CVE-35 (Medium) — dependency-integrity controls read from predictable shared `/tmp`

Two of them, and they are precisely the controls that exist to detect tampering:

- `_sha256sum_file` (`cbt/deps.cyr:1986`) — produces the digests written into
  `cyrius.lock` and checked by `cyrius deps --verify`. It forks, `dup2`s stdout
  to a file, and `execve`s `sha256sum`. The capture file was the fixed
  `/tmp/cyrius_sha_out`, opened `O_WRONLY|O_CREAT|O_TRUNC` — **no `O_EXCL`, no
  `O_NOFOLLOW`.**
- `_git_head_sha` (`cbt/deps.cyr:2065`) — gates the force-pushed-tag refusal,
  same pattern through `/tmp/cyrius_githead_out`.

**Vector.** Any local user on a shared or multi-user box (or a shared CI runner)
who wins the name. Note the argv hardening from CVE-14 is intact and unrelated —
`path` is a distinct argv element here, never concatenated into `/bin/sh -c`.
This is the *output* channel, not the input one.

**Impact.** An attacker who holds the name supplies the digest, so
`cyrius deps --verify` passes on a tampered dependency, and `cyrius.lock`
records the attacker's hash as ground truth. The dependency-integrity mechanism
returns a verdict the attacker wrote. Same for the force-pushed-tag refusal.

---

### CVE-36 (Medium) — compile-to-fixed-`/tmp`-then-execve

`cyrius run` / `test` / `fuzz` / `bench` / `soak` each compiled to a fixed
`/tmp` name and then executed the result (`cbt/commands.cyr:150,164,250,291,1518`).

**Be precise about the residual — the naive attack does not work.** `compile()`
writes `<out>.tmp.<pid>` and then `rename(2)`s it into place, and `rename`
**replaces** a planted symlink rather than following it. So a pre-planted
symlink at the final name does not redirect the write. What remains is real but
narrower: the final name is predictable, and there is a window between the
rename and the `execve` in which another local user can replace the file that is
about to be run.

**Fix for CVE-35 and CVE-36 (v6.4.81).** All **23** fixed `/tmp` literals in
`cbt/` now route through a single private per-invocation directory —
`_cbt_tmpdir()` / `_cbt_tmpfile()` at `cbt/build.cyr:413,446`. `/tmp/cyrius-<pid>`,
created with `sys_mkdir(d, 448)` = mode **0700**. Two properties matter:

- **`mkdir` is exclusive, so it fails closed.** If the directory cannot be
  created, the CLI prints why and `sys_exit(1)` — it never quietly falls back to
  a shared name. A fallback would have reintroduced the whole finding under
  contention, which is the usual way this class comes back.
- The 16-attempt suffix loop exists **only** so our own leftovers (PID reuse on a
  long-lived box) self-heal. It is not a retry against an adversary — every
  attempt is still an exclusive create.

Verified: `cyrius run` → exit 42, the directory is `drwx------`, and the old
fixed names are gone.

**One self-inflicted regression worth recording.** The first cut of that helper
called `sys_rmdir`, which does not exist on the Windows peer, and broke the
`cbt/cyrius.cyr` PE cross-compile — exactly the CLAUDE.md rule about Linux-syscall
use in `cbt/`. The PE cross-compile gate caught it. A security fix is still a
compiler change and still owes the full gate.

---

## Refuted findings — recorded so they are not re-filed

Two candidates survived a first read and **failed adversarial verification.**
Both are written down because each is the kind of finding that looks right on a
second pass too, and re-filing them costs a future auditor a day.

### CVE-37 (withdrawn) — `file_write_atomic`'s temp file

**Claim.** `file_write_atomic` (`lib/io.cyr:355`) opens its temp with
`O_WRONLY|O_CREAT|O_TRUNC` and no `O_EXCL`, so a pre-planted symlink at the temp
name is followed and the caller's bytes are written through it.

**The code facts are correct.** `_io_tmp_name` (`lib/io.cyr:334`) builds
`<path>.cyrtmp.<pid>.<ctr>`, which is predictable, and `file_open` at `:357`
does not pass `O_EXCL`.

**The exploit path is not.** The temp is a **sibling of the destination**, not a
shared directory — it lands wherever `path` lands. An attacker who can plant a
file at `<path>.cyrtmp.<pid>.<ctr>` already has write access to that directory
and can therefore write `path` itself. No privilege boundary is crossed, so
there is nothing to escalate. Contrast CVE-35/36, where the shared `/tmp`
namespace *is* the boundary crossing — that is the distinction to hold onto.

*(Adding `O_EXCL` here would still be a defensible robustness change. It is not
a security finding, and it should not be filed as one.)*

### CVE-38 (withdrawn) — macOS `_macho_codesign` shell concatenation

**Claim.** `_macho_codesign` (`cbt/build.cyr:642`) concatenates a path into a
`sys_system` string —
`"codesign -s - -f " + path + " 2>/dev/null"` — and the path arrives from the
CLI's `-o` output flag, so a crafted `-o` value injects shell commands.

**The named input channel does not exist.** There is no `-o` flag anywhere in
`cbt/` (`grep '"-o"' cbt/*.cyr` → zero hits); `cyrius build` takes
`<source> <output>` as **positional** arguments (`cbt/cyrius.cyr:470`), and every
other caller passes an internally-generated path (`run_binary` → `_cbt_tmpfile("run")`).
A positional `<output>` is a string the invoking user typed into their own
shell — injecting into it buys the attacker nothing they did not already have.
The fn is additionally `#ifdef CYRIUS_TARGET_MACOS`-only.

**Residual, honestly stated:** it is still a `sys_system` sink with a
concatenated argument, so it is a live tripwire if a future caller ever passes a
path that is *not* user-supplied (a manifest field, a dep name, a downloaded
artifact). Worth converting to argv exec on general principle — but not as a
CVE, and not with a fabricated exploit attached to it.

---

## What this pass says about the gates

The five confirmed findings are ordinary bounds and temp-file bugs. What is not
ordinary is **how long three of them survived a repo with 150 green gates**, and
the answer is the same every time: *the gate described something other than what
the code did.*

| Gate | What it described | What the code did |
|---|---|---|
| `src/main.cyr:90` heap map | `include_fname` at `0x190500`, 256 B | `0x190400`, unbounded — **no code has ever written `0x190500`** |
| `tests/heapmap.sh:70` size parser | regions sized `[N]` | skipped every unit-suffixed entry — **blind to 20.02 MB of live heap**, incl. `ir_nodes [16 MB]`, and reported a phantom free gap that is fully occupied |
| `tests/heapmap.sh:70` (again) | the region's size | took the *last* bracketed number, so a trailing prose `issue [5]` parsed `fn_param_struct_mask` as **5 bytes** — off by 13,107× |
| `scripts/agnos-crossbuild-gate.sh:401` | "syscall #84 is emitted" | `0x52`–`0x55` are ASCII `R`–`U`, so a **string-literal byte store** matched `mov eax,0x54` — mutating #84 → 99 still reported PASS (fixed v6.4.70) |
| `programs/checks/platform_win_macho.cyr:471,693` | "the PE compiler works" | existence-only rebuild trigger on `build/cycc_win_cross`; nothing else in the repo refreshes it, so both PE gates ran a **`cycc 5.11.69`** binary for the whole v6.x line |
| the six native forks' `CYRIUS_HAS_VAL_SIMD_PARAMS` | "value-form SIMD is tested" | tcyr run **natively**, so they exercised `main_win.cyr` (always correct) and never `src/main.cyr`'s cross arms (silently dropped the feature) |

That is not six unrelated defects. It is one defect with six instances: **a gate
was written, was never made to fail, and its PASS was then read as evidence.**
The heap map is the sharpest case, because it is machine-read — prose on a map
line is parsed as the size, so an explanatory comment can *unset* a region's
audit.

**Standing rule this audit recommends, and the one to carry into v6.5.x:**

> **Mutation-prove every gate at the moment you write it.** Break the thing the
> gate claims to watch and confirm it goes RED; restore and confirm GREEN. A
> gate that has never been observed to fail is a placebo, and it is worse than
> no gate because it is *counted*.

v6.4.81 applied this to its own work — the heap-map parser was proven by
planting a probe region inside `ir_nodes` (RED where it previously passed), the
valform-SIMD gate by reverting the two predefines (fails exactly the `pe` and
`macho` legs), and the agnos band gate by renumbering `SYS_UPTIME_US` 95 → 77.
That is the bar; it is cheap, and it is the only thing that distinguishes a gate
from a comment.

Related, and unresolved by fixes alone: `tests/heapmap.sh` can only audit what
the map *has an entry for*. The v6.4.82 TS-arena finding — a 10,027,008-byte
overlap with `tok_types` — was structurally invisible to it because the arena
base was a **code literal**, not a map line. Sized regions that live as literals
are outside the audit by construction.

---

## Prior audit's tail — presence check

The 2026-06-10 review closed with CVE-14…CVE-31 open and tracked in `issues/`.
**Presence check performed this pass:** every identifier CVE-14 through CVE-31
now carries at least one in-tree `CVE-NN` fix marker across
`src/`, `lib/`, `cbt/`, `scripts/`, `tests/`, `.github/` — the v6.1.33–v6.1.41
hardening burst, plus CVE-20's `seed-derive-cycc.sh` trust-root closure
(2026-06-20) which is now a CI job and gate step 2.

**This is a marker census, not a re-audit.** This pass did not re-derive the
adequacy of each of those eighteen fixes; it confirmed each has a landed,
commented change rather than a note. A future full deep-dive should re-verify
the TLS/entropy group (CVE-17/18/19/30) in particular, since it is the largest
and the one whose correctness is least visible from a marker.

---

## Process note — the cadence line was wrong

CLAUDE.md's Closeout item 9 read **"Full audit every 2-3 minors (last: v5.0.1)"**
until v6.4.82. That was wrong: the last full audit was the
[2026-06-10 deep-dive](2026-06-10-deep-dive-review.md) at cycc 6.1.31, three
minors after v5.0.1. A stale "last:" stamp on a *cadence* rule is self-defeating
— it is the field the rule is measured against, so wrong-in-the-old-direction
makes the audit look more overdue than it is, and nobody trusts the trigger.
Corrected at v6.4.82 to name this file and the one before it.

Same class as the six gate rows above, and the reason `_doc_stamp_currency_gate`
(check.sh 149 → **150**, v6.4.81) exists: a checklist entry is not a gate.
