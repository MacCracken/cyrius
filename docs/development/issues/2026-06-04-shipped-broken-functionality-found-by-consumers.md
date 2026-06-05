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

## B. Platform: arm64 macOS dir-walk codegen bug — the active blocker

`is_dir` / `dir_list` / `cyrius lib sync` / any dir-walk return EFAULT/EBADF on **arm64 macOS**:
`getdirentries64` (syscall 217→344) gets corrupted args in real (runtime-linked) programs — an arm64
**codegen** bug, reproduced extensively on ecb. `lib sync` broken ⇒ can't build ⇒ **arm64 macOS is
broken in fact.** Found by **yantra CI**, not us. The `2026-06-04-macos-install-lib-snapshot-missing-
breaks-lib-sync.md` issue (+ the .62 install.sh change) was MIS-SCOPED at the install layer — the lib
snapshot was never the problem; re-scope it to this codegen cause. Pinned as **.63**.

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
| aarch64 Linux | lib sync OK, **`deps` REDS** | pi |
| arm64 macOS | **`lib sync` REDS** (getdirentries) | ecb |
| Windows PE | codegen **GREEN**; wrapper-flow N/A | cass |

### D1. `cyrius deps` silently fails on aarch64 Linux — NEW, untracked
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

## Process note

This whole register only exists because deferred/broken work was left in source comments
(50 `SCAFFOLD`, 14 `NOT_IMPLEMENTED`, 28 "for now" across `lib`/`src`/`cbt`) instead of tracked
issues, in violation of CLAUDE.md's tracking rules. Sigil's markers were audited and are largely
legitimate perf-deferral notes with tracking refs — not part of this register.
