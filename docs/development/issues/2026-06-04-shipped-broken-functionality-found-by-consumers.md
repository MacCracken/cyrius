# Genuinely-broken shipped functionality, untracked — found by consumers, not our gates

- **Filed**: 2026-06-04
- **Why this exists**: no gate ever ran the real consumer flow (`cyrius init` → `lib sync` → `build`
  → run; or actually exercising a shipped public API). So functional holes shipped green and were
  discovered downstream. This is the "found by ports" failure CLAUDE.md explicitly forbids
  ("NO EXCUSE THAT SHIT BEING FOUND BY PORTS"). Registering them per the rule (track deferred/broken
  work; never bury it in comments).

## A. Broken PUBLIC API shipped returning errors silently

### `lib/tls_native.cyr` — "shipped TLS 1.3" has unimplemented public functions
The 1.3 client+server core IS real (slots .15–.28, OpenSSL interop CONNECTED). But:
- **Stale header lie** (L7): still declares *"v6.0.10 SCAFFOLD — every fn returns NOT_IMPLEMENTED."*
  False — the stack works. Reconciled to the truth in this same change.
- Three **public** API fns genuinely `return TLS_ERR_NOT_IMPLEMENTED`, untracked — a consumer calling
  them gets a silent error code:
  - `tls_native_set_alpn` (L2918) — no ALPN ⇒ no protocol negotiation (HTTP/2, etc.).
  - `tls_native_set_version_range` (L3159) — can't pin/restrict the TLS version; security-config hole.
  - `tls_native_close` (L3372) — **no clean shutdown (close_notify)**; a consumer can't close a TLS
    connection through the API, just abandon the socket.
- **Action**: implement them, or if deliberately deferred, keep the error but track it here and point
  the comment at this issue. (Distinct from the *unstarted* TLS 1.2 backport + consumer-wiring arc —
  Mini-arcs D/E — which ARE pinned in roadmap at .68–x; the source just never pointed there.)

### `lib/process_agnos.cyr` — `sys_dup` stub ⇒ spawned process stdout can't be redirected (L15)
Surfaced by agnsh (`run <prog>` output goes to the terminal, can't be captured). Tracked at
`2026-06-03-agnos-followup-after-boot.md` for the kernel-ABI side; cross-linked here as a
consumer-discoverable hole.

## B. Platform: arm64 macOS dir-walk — FIXED in .63 (root cause was NOT codegen)

`is_dir` / `dir_list` / `cyrius lib sync` returned EBADF on **arm64 macOS**, so `lib sync` reported
"snapshot lib not found" on a dir that exists ⇒ couldn't build ⇒ **arm64 macOS broken in fact**
(found by **yantra CI**). The earlier "arg-corruption codegen bug" characterization was **wrong** —
proven by bisection on ecb (2026-06-04):

- A standalone probe calling `dir_list`/`is_dir` on the same path **worked** (91 files, correct names),
  but the cyrius WRAPPER's `lib sync` failed. Same `is_dir` source, opposite result.
- Instrumenting `is_dir` in the wrapper showed `fd=3` (open OK) but `getdirentries n=-9` (EBADF), and
  crucially **`SYS_GETDENTS64` loaded as 61, not 217**.
- **Root cause:** `SYS_GETDENTS64` is multiply-defined — 217 (x86/macos) in `fs.cyr`/`syscalls_macos`,
  but **61** (the aarch64-Linux number) in `syscalls_aarch64_linux.cyr`. The wrapper includes
  `fs.cyr` (217) *then* `syscalls.cyr` (→ aarch64 → 61), so **61 wins** ("last definition wins"). The
  probe's include order bound 217, masking it. The .60 macho `ESYSXLAT` translated only the x86 `217→344`
  and **missed the aarch64 `61→344`** — yet the wrapper/tools pull the aarch64 stdlib (61). Untranslated
  61 ran with a stale x16 → EBADF.
- **Fix (`src/backend/aarch64/emit.cyr` ESYSXLAT, macho block):** add `cmp x8,#61; b.ne; movz x16,#344`
  (`0xF100F51F / 0x54000041 / 0xD2802B10`, llvm-mc-verified), next to the existing 217→344 and the other
  aarch64→BSD renumbers. Makes both 61 and 217 translate, robust to include order.
- **Verified on ecb (real arm64 macOS):** `lib sync` copies 89 files; the FULL funcgate (init→lib sync→
  deps→build→run→reproducible→hashmap) is **GREEN**. Self-host byte-identical on x86_64 + aarch64-linux
  (qemu) + macho-arm. `macho-arm64-funcgate` promoted to a **HARD** CI gate.
- **Gate bug also fixed:** the funcgate's reproducible-build compared two *different* output names
  (fib vs fib2); Mach-O embeds the output basename (signing identifier) so they always differed by those
  bytes (one byte: `1`↔`2`). Now rebuilds the SAME name and hashes the **unsigned** output (codesign is
  non-deterministic — the .44 lesson). Linux/ELF didn't embed the name so it passed there, hiding it.

## C. Root cause of the whole class — the verification never tested the real thing

`scripts/cross-os-selfhost.sh` checks that `cycc` reproduces `cycc` byte-identical. That **passes right
now**, while the toolchain can't list a directory — because self-host reads source by path and never
walks a dir. The flow a consumer actually depends on (`init` → `lib sync` → `build` → run) was never
run on any host, local or CI; the macOS/Windows CI jobs run hello-world smoke. Self-host is a fancier
placebo for "does the toolchain work."

**Fix (the thing that ends consumer-discovery):** a **fail-loud real-flow gate** — on each SSH host
(ecb/ach/pi/cass) run `init` → `lib sync` → `build` → run, and go **RED** when any step fails, every
release. It must turn the *current* macOS state red the first time it runs; that's the tell it's real
and not lipstick. Replaces / augments the self-host-only check.

## D. Platform findings the new functional gate surfaced (the gate working as intended)

Built `scripts/funcgate-posix.sh` (Linux/macOS) + `scripts/funcgate-win.ps1` (Windows) +
`scripts/funcgate-stage.sh`, wired into CI (`test` hard, `test-agnos`/`aarch64-native` tracking,
`macho-arm64-funcgate`/`windows-native`) AND verified on real hardware (pi/ecb/cass) before claiming
anything. Flow: init → lib sync (dir-walk) → deps → build+run a vec-grown fib AND a u64-hashmap →
reproducible-build. Per-platform truth, **hardware-verified 2026-06-04**:

| Platform | Result | Where |
|---|---|---|
| x86_64 Linux | **GREEN** — full flow | local + `test` job |
| aarch64 Linux | **GREEN** — full flow (fixed .68) | pi |
| arm64 macOS | **`lib sync` REDS** (getdirentries) | ecb |
| Windows PE | codegen **GREEN**; wrapper-flow N/A | cass |

### D1. `cyrius deps` silently fails on aarch64 Linux — ✅ FIXED in .68
On pi (`ubuntu-24.04-arm` equiv), `cyrius lib sync` **works** (dir-walk + 89/90 files copied — so the
arm64 codegen is fine and the macOS bug is Darwin-specific, NOT arm64-generic). But `cyrius deps`
returns `0 deps resolved, 9 errors` / **rc=9**, prints **nothing to stderr**, and is **destructive** —
it leaves `lib/` short (`vec.cyr` goes missing after). Traced to `_dep_copy_stdlib_recursive`
(`cbt/deps.cyr:902`) returning 1 for every stdlib module while the IO-error prints
(`_dep_copy_file:119/127`) never fire — i.e. it fails *before/around* the copy without the diagnostic,
OR the `STDERR_FD` write itself is misrouted on aarch64. Same `sys_open`/read path that `lib sync` uses
*works*, so it is specific to the deps stdlib-copy recursion. A real aarch64 consumer is blocked at
`cyrius deps`. **Surfaced by the gate, not a consumer.** Pin: user to slot (NOT folded into .63 — that
is gate-fix + macOS getdirentries + sigil 3.7.3).

**✅ Resolution (.68).** Root cause was NOT the recursion returning 1 / a misrouted STDERR (the original
guess above). It was the aarch64-Linux **ESYSXLAT missing `stat 4`**: `cbt`'s `_file_size` issues a
literal `syscall(4)`, which on aarch64-Linux is `io_getevents` (4 wasn't in the non-macho ESYSXLAT) →
`_file_size` returned -1 → the transitive-include SCAN's `if (sz<=0) return 0` short-circuited → the
recursion copied each top module but NEVER followed its `include` chain (so `syscalls.cyr` arrived
without `syscalls_aarch64_linux.cyr`/`alloc_*`/`atomic`; on the current build rc=0 with peers missing,
not rc=9 — the original rc=9/vec-missing was an earlier manifestation). Fixed by adding `stat 4→fstatat
79` to the ESYSXLAT, plus the same-class `rename 82→renameat 38` (`cyrius build`'s output-rename ran as
`fsync` → never produced a binary) and `symlink 88→symlinkat 36` (`cyrius pulsar`). Fixing deps then
unmasked TWO more: the SHIPPED native cycc (`main_aarch64_native.cyr`) never got the v5.9.37
auto-call-`main` port (bare-`fn main()` builds exited 0), and the CI `aarch64-native` gate built/tested
`cycc_a64` from the CROSS source (`main_aarch64.cyr`) instead of the shipped native binary — a placebo.
All three fixed; `aarch64-native` now builds/self-hosts/funcgates the shipped `cycc_native_a64` **HARD**.
`cyrius deps` resolves all 14 transitive files on pi (matching x86); full funcgate GREEN on pi (init→
sync→deps→build→run=42→reproducible→hashmap=43); 4-host self-host green. See CHANGELOG [6.0.68].

### D2. The cyrius CLI wrapper is not ported to Windows — NEW, untracked
Compiling `cbt/cyrius.cyr` for PE (`CYRIUS_TARGET_WIN=1`) emits **undefined**:
`sys_fork`, `sys_execve`, `sys_waitpid`, `sys_dup2`, `sys_mkdir`, `sys_unlink`, `sys_chmod`,
`WIFEXITED/WEXITSTATUS/WIFSIGNALED/WTERMSIG`; and most `syscall(n)` values trap with
`STATUS_ILLEGAL_INSTRUCTION`. So the wrapper can't spawn processes or mutate the filesystem on Windows
— `cyrius init` (spawns `sh cyrius-init.sh`), `cyrius build` (spawns `cycc`), `cyrius lib sync`
(`getdents`, which Windows lacks) all fail there. The wrapper-driven funcgate is therefore **not
portable to Windows** and the Windows gate instead exercises what IS native: **`cycc.exe` compiling +
running allocating programs** (vec fib → 42, u64 hashmap → 43, reproducible) — **verified GREEN on cass**.
The old Windows CI only ran no-alloc exit-code programs, so a Windows heap/hashmap codegen bug would
have shipped green; the new gate closes that. Porting the wrapper (Win32 process + `FindFirstFile`
dir-walk + `CreateDirectory`) is a separate, larger arc — pin: user to slot.

### D3. Gate-harness bug the hardware caught (fixed in this change)
`funcgate-posix.sh` first ran GREEN locally because the ambient `~/.cyrius` masked it; on a clean host
(pi) `cyrius init` failed `no toolchain detected`. `cyrius-init.sh` checks `~/.cyrius/current` + a
symlink-sensitive `$CYRIUS/VERSION`, neither honoring a scratch `CYRIUS_HOME`. **Consequence:** the
macOS gate would have RED at `init(10)` — a cosmetic detection miss — not the real `lib-sync(11)`
dir-walk bug, i.e. the right color for the wrong reason. Fixed by exporting the documented `CYRIUS_VER`
override in the gate; re-verified on ecb that it now reaches and reds at `lib sync(11)`.

### D4. arm64 macOS: `nanosleep` (syscall 35) not in ESYSXLAT — NEW, untracked (next macho slot)
Surfaced by yantra **once .63's dir-walk fix let `lib sync` succeed and the e2e finally reached
runtime**: a program calling `syscall(35, ts, 0)` (nanosleep) faults on arm64 macOS (exit 127) because
the macho `ESYSXLAT` doesn't translate `35` — same class as the getdents `61` gap and the socket
surface, an x86/Linux number a consumer uses that ESYSXLAT never renumbers to a Darwin BSD number.
**Caveat:** XNU has no plain `nanosleep` BSD syscall (libsystem layers it over `__semwait_signal`/
`clock_nanosleep`), so it is NOT a one-line renumber like sockets — options are a reroute-with-arg-shuffle,
a `__got` libSystem reroute (mirror `clock_gettime_nsec_np`), or — cleaner long-term — a portable
`sleep_ms` in the stdlib (`lib/time.cyr`/`process.cyr`) so consumers stop hardcoding `syscall(35)`.
**Secondary finding:** the compile-time warning whitelist in `parse_expr.cyr` (~L419,
`{0,1,2,3,9,10,11,60,228}`) is stale — it no longer matches what ESYSXLAT actually translates, so it
fires for dozens of already-rerouted syscalls and **drowns the one (35) that genuinely isn't**. Sync
that whitelist to the ESYSXLAT-covered set so the warning means something. A real-flow funcgate that
exercises sleep would have caught this (à la the .63 dir-walk gate). Full issue:
`docs/development/issues/2026-06-04-macos-nanosleep-syscall-35-not-in-esysxlat.md`. **Pinned to the next
macho/platform slot** (roadmap partials block) — NOT a .63 follow-up.

## Process note

This whole register only exists because deferred/broken work was left in source comments
(50 `SCAFFOLD`, 14 `NOT_IMPLEMENTED`, 28 "for now" across `lib`/`src`/`cbt`) instead of tracked
issues, in violation of CLAUDE.md's tracking rules. Sigil's markers were audited and are largely
legitimate perf-deferral notes with tracking refs — not part of this register.
