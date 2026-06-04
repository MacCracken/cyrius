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

## Process note

This whole register only exists because deferred/broken work was left in source comments
(50 `SCAFFOLD`, 14 `NOT_IMPLEMENTED`, 28 "for now" across `lib`/`src`/`cbt`) instead of tracked
issues, in violation of CLAUDE.md's tracking rules. Sigil's markers were audited and are largely
legitimate perf-deferral notes with tracking refs — not part of this register.
