# `lib/net.cyr` hardcodes seven x86-only socket syscall numbers with zero arch guards

**Filed:** 2026-07-30
**Reporter:** sandhi 1.9.7 (via bote 3.2.1)
**Cyrius version at time of report:** 6.5.3
**Affected stdlib:** `lib/net.cyr` (lines 10–16, 350), `src/backend/aarch64/emit.cyr` (`ESYSXLAT`, the v6.2.10 socket block)
**Severity:** Medium — nothing is broken *today*, but the mechanism keeping it working is the one the stdlib has twice documented as the wrong answer, and it has now armed a collision against planned work (roadmap W1). See Severity rationale.
**Status:** open

## 1. Summary

`lib/net.cyr` declares its socket syscall numbers as bare, unguarded globals — the **x86_64**
numbers — and the file contains **zero** `CYRIUS_ARCH` conditionals:

```
lib/net.cyr:10   var NSYS_SOCKET = 41;
lib/net.cyr:11   var NSYS_CONNECT = 42;
lib/net.cyr:12   var SYS_ACCEPT = 43;
lib/net.cyr:13   var NSYS_BIND = 49;
lib/net.cyr:14   var NSYS_LISTEN = 50;
lib/net.cyr:15   var NSYS_SETSOCKOPT = 54;
lib/net.cyr:16   var SYS_SHUTDOWN = 48;
```

On aarch64-Linux every one of those is the wrong number (41 is `pivot_root`, 43 is `statfs`,
49 is `chdir`, …). They work only because the aarch64 backend emits a runtime renumber chain
ahead of every `svc` — the v6.2.10 block in `ESYSXLAT`:

```
src/backend/aarch64/emit.cyr:  socket 41→198 · connect 42→203 · accept 43→202
                               shutdown 48→210 · bind 49→200 · listen 50→201
                               getsockname 51→204 · setsockopt 54→208 · getsockopt 55→209
```

This is the exact pattern the stdlib has already ruled against, in its own words, at
`lib/syscalls_linux_common.cyr:429`:

> Each peer supplies the number for ITS OWN arch […] which is what this file's per-arch split
> is for. **Do NOT "solve" this with an ESYSXLAT entry for x86-52**: it collides with the
> aarch64 peer's `SYS_FCHMOD = 52` and remaps fchmod to getpeername (CI caught precisely that
> — sandbox_syscalls RED on pi).

`net.cyr` is the last significant holdout still relying on the renumber chain, and the
collision the `getpeername` note warns about has already recurred here — see §3.

`SYS_ACCEPT` is the sharpest case: it is defined in **neither** syscall peer. Its only
definition anywhere in `lib/` is that one bare `var SYS_ACCEPT = 43`. Meanwhile `SYS_ACCEPT4`
*is* per-arch native (x86_64 288 · aarch64 242) with a portable wrapper already shipped
(`sys_accept4`, `lib/syscalls_linux_common.cyr:479`), and neither number needs a renumber entry
because neither is ambiguous.

## 2. Reproduction

This is a latent-hazard filing, not a live crash — on aarch64-Linux the renumber chain
currently produces the right call. The reproduction is of the *mechanism*, not a failure:

```bash
# The x86 numbers, unguarded, with no arch conditional in the file:
sed -n '10,16p' lib/net.cyr
grep -c CYRIUS_ARCH lib/net.cyr          # → 0

# The only thing making them correct on aarch64:
grep -n "41→198\|43→202\|49→200" src/backend/aarch64/emit.cyr

# The armed collision (see §3):
grep -n "SYS_CHDIR" lib/syscalls_aarch64_linux.cyr   # → 95:    SYS_CHDIR = 49;
grep -rn "sys_chdir" lib/regression.cyr              # → 658:        sys_chdir(work_dir);
grep -rn "fn sys_chdir" lib/ src/                    # → nothing: the wrapper does not exist yet
```

## 3. Root cause — and the collision this has already armed

A runtime renumber chain is **arch-blind to source origin**. `ESYSXLAT` emits `cmp x8,#N /
b.ne / movz x8,#M` ahead of every `svc`, so it rewrites *any* code path that lands N in x8, not
just the `net.cyr` ones it was added for. Every x86 number mapped there is therefore burned:
no aarch64-peer code may ever legitimately issue it.

Nine numbers are currently burned that way (41, 42, 43, 48, 49, 50, 51, 54, 55). **One of them
is already claimed by the aarch64 peer:**

| Symbol | Where | aarch64 value | ESYSXLAT rewrites it to |
|--------|-------|--------------:|-------------------------|
| `SYS_CHDIR` | `lib/syscalls_aarch64_linux.cyr:95` | **49** | `bind(2)` (49→200) |

Nothing calls it *yet*, because `fn sys_chdir` does not exist anywhere in `lib/` or `src/` —
the dangling call at `lib/regression.cyr:658` is a known gap, tracked as roadmap **W1** and in
[`2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md`](2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md).
That is the whole problem: **the day W1 lands the obvious one-line wrapper**

```
fn sys_chdir(path): i64 { return syscall(SYS_CHDIR, path); }
```

**every aarch64-Linux caller of `sys_chdir` silently calls `bind(2)` instead**, with a directory
path in the sockaddr slot. Same failure shape as the fchmod/getpeername incident: a wrong
syscall that does not fail loudly. Whoever closes W1 will not be looking at `net.cyr`.

## 4. Proposed shape

Move `net.cyr` onto the per-arch peers, which already carry every wrapper it needs:

| `net.cyr` today | Compose instead | Peer wrapper |
|-----------------|-----------------|--------------|
| `syscall(NSYS_SOCKET, …)` | `sys_socket(domain, type, proto)` | `syscalls_linux_common.cyr:407` |
| `syscall(NSYS_CONNECT, …)` | `sys_connect(fd, sa, len)` | `:452` |
| `syscall(NSYS_BIND, …)` | `sys_bind(fd, sa, len)` | `:468` |
| `syscall(NSYS_LISTEN, …)` | `sys_listen(fd, backlog)` | `:473` |
| `syscall(NSYS_SETSOCKOPT, …)` | `sys_setsockopt(fd, lvl, opt, val, len)` | `:447` |
| `syscall(SYS_ACCEPT, fd, 0, 0)` | **`sys_accept4(fd, 0, 0, 0)`** | `:479` |
| `syscall(SYS_SHUTDOWN, …)` | *(no wrapper yet — add `sys_shutdown`)* | — |

`accept4(fd, NULL, NULL, 0)` is defined to be exactly `accept(fd, NULL, NULL)`, so the accept
swap is behaviour-preserving. Keep `flags` at 0 rather than reaching for `SOCK_CLOEXEC` — that
would be a behaviour change and belongs in its own bite.

Then **retire the nine now-dead `ESYSXLAT` x86 socket entries** (41/42/43/48/49/50/51/54/55),
which is what actually disarms the `SYS_CHDIR` collision and unburns the slots. The aarch64
rows in the same block (198/200/201/203/204/205/208) stay — those are the real per-arch numbers.
Keep the *macho* branch's x86 rows: Darwin translation is a separate axis and `net.cyr`'s
Darwin support rides `EMACHO_SYSXLAT`/`ESYSXLAT` by design.

The `getpeername` gate (`tests/tcyr/vr01_getpeername_xlat.tcyr`) is the model for the
regression test: prove on real aarch64 hardware that `sys_chdir`-shaped and `bind`-shaped calls
are not swapped.

## 5. Consumer-side workaround

**bote 3.2.1 shipped one and it is instructive.** Its Unix-socket transport needed `accept(2)`
and deliberately did **not** route through `sock_accept()`, precisely because `net.cyr`'s
non-agnos branch issues the same bare 43 — going through the stdlib would have relocated the
dependence, not removed it. It calls `sys_accept4(sfd, 0, 0, 0)` directly
(`bote/src/transport_unix.cyr`), and bote's CI now bans a bare `syscall(SYS_` in `src/`
outright.

So the swap proposed in §4 is already proven in a shipping consumer; this issue is asking the
stdlib to make it unnecessary for the next consumer to rediscover.

sandhi is **not** shipping a workaround: it composes `sock_accept()` from five serve loops and
routing around the stdlib there would be worse than the hazard.

## 6. Severity rationale

**Medium, not High** — nothing is miscompiled today. Every path `net.cyr` exercises gets the
right syscall on every supported target.

**Not Low, for three reasons:**

1. The `SYS_CHDIR = 49` collision is *armed against planned work*. W1 is on the roadmap; the
   trap fires on a one-line wrapper that will look obviously correct in review.
2. This failure class does not fail loudly. Both prior instances — sandhi's raw `syscall(52)`
   getpeername becoming `fchmod`, and the x86-52 ESYSXLAT entry remapping `fchmod` to
   `getpeername` — **succeeded** and returned garbage. One needed real pi hardware to find.
3. `net.cyr` is the last significant holdout on the renumber chain, so this is a
   finite, closeable cleanup rather than an open-ended one.

**Bump to High if** W1 lands a `sys_chdir` wrapper before this is fixed, or if any new
aarch64-peer constant takes a value in {41, 42, 43, 48, 50, 51, 54, 55}.

## 7. Related issues

- [`2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md`](2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md)
  — same family; documents that `fn sys_chdir` exists nowhere. **Cross-blocking: closing that
  one first fires the collision in §3.**
- [`archived/2026-07-14-sandhi-peer-api-use-stdlib-getpeername.md`](archived/2026-07-14-sandhi-peer-api-use-stdlib-getpeername.md)
  — the precedent. Resolved by adding per-arch wrappers and explicitly *rejecting* an ESYSXLAT
  entry.
- [`archived/2026-06-04-macos-net-socket-syscalls-unported.md`](archived/2026-06-04-macos-net-socket-syscalls-unported.md)
  — added the macho socket renumbers; the Darwin axis stays.
- Roadmap **W1** (*Missing syscall wrappers — one pass*).

## 8. Pointers

- `lib/net.cyr:10-16` — the seven unguarded constants; `:350` — `syscall(SYS_ACCEPT, fd, 0, 0)`
- `lib/syscalls_linux_common.cyr:407-480` — every replacement wrapper except `sys_shutdown`
- `lib/syscalls_linux_common.cyr:423-432` — the `getpeername` note; the argument this filing rests on
- `lib/syscalls_x86_64_linux.cyr:109` / `lib/syscalls_aarch64_linux.cyr:184` — `SYS_ACCEPT4` 288 / 242
- `lib/syscalls_aarch64_linux.cyr:95` — `SYS_CHDIR = 49`, the armed collision
- `src/backend/aarch64/emit.cyr` — `ESYSXLAT`, v6.2.10 socket block (Linux) and v6.0.59 block (macho)
- Consumer precedent: `bote/src/transport_unix.cyr` (bote 3.2.1, `sys_accept4` swap + rationale)
- Reported alongside sandhi's accept-loop hardening — sandhi CHANGELOG `[Unreleased]`,
  `sandhi/docs/development/issues/2026-07-30-accept-loop-unguarded-spin.md`
