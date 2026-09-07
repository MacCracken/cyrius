> ## ✅ RESOLVED — v6.5.7 + v6.5.11. Archived 2026-08-08.
>
> Closed on evidence, and NOT by implementing §4 — which premise-checking showed to be the
> wrong direction:
>
> - **§3 (the armed collision)** — disarmed at **v6.5.7** by the ≥1000 private-alias band,
>   a different mechanism than §4 proposed.
> - **§4 (per-arch peer wrappers)** — **deliberately NOT implemented.** The seven x86
>   numbers are already renumbered for aarch64-Linux by the `ESYSXLAT` block at
>   `src/backend/aarch64/emit.cyr:865-873`, which sits in the **aarch64-Linux** arm (added
>   v6.2.10), not the Mach-O one. Verified by running the project's own net tests on **real
>   pi**: `net_v6_connect` and `socket_syscalls` both `rc=0`. Replacing that with per-arch
>   NATIVE numbers would move `net.cyr` OFF the pattern CLAUDE.md mandates ("use the x86
>   number + an ESYSXLAT entry") and INTO the hazard that rule exists to prevent — to fix
>   nothing observable.
> - **The real defect** was that the coupling was SILENT: delete a row and the whole INET
>   surface dies with no signal until someone runs sockets on that hardware. Closed at
>   **v6.5.11** by `tests/gates/platform/net_esysxlat_coupling.sh` (11 assertions,
>   registered in `programs/checks/main.cyr`), mutation-proven by reproducing the v6.2.10
>   defect: deleting the aarch64-Linux socket-41 row turns 2 axes red. It asserts **2** rows
>   per number, not ≥1 — the v6.2.10 bug WAS "1 row, macho only", which a ≥1 assertion would
>   have called healthy.
>
> ⚠ **Carried forward, NOT closed here:** §9's AF_UNIX surface is a separate yes/no for the
> maintainer and is unaffected by any of the above. It belongs in the roadmap backlog rather
> than an issue file (per the "consolidate the someday tail into roadmap entries" rule).

# `lib/net.cyr` hardcodes seven x86-only socket syscall numbers with zero arch guards

**Filed:** 2026-07-30
**Reporter:** sandhi 1.9.7 (via bote 3.2.1)
**Cyrius version at time of report:** 6.5.3
**Affected stdlib:** `lib/net.cyr` (lines 10–16, 350), `src/backend/aarch64/emit.cyr` (`ESYSXLAT`, the v6.2.10 socket block)
> ## ⛔ v6.5.11 premise-check: §4 IS THE WRONG DIRECTION — do not implement it
>
> Picked up for the v6.5.11 catch-up batch, premise-checked **on real hardware**, and the
> conclusion is that the proposed fix must NOT be written. Two findings:
>
> **1. There is no live bug on any gated target.** The seven x86 numbers are renumbered for
> aarch64-Linux by the `ESYSXLAT` block at `src/backend/aarch64/emit.cyr:865-873` — which lives in
> the **aarch64-Linux** arm, not the `_TARGET_MACHO == 2` arm (it was added at v6.2.10 for exactly
> this reason; read the comment at `:854-864`). Verified by running the project's own net tests on
> **real pi (Linux aarch64)** at v6.5.11:
>
> ```
> net_v6_connect.tcyr  -> rc=0
> socket_syscalls.tcyr -> rc=0
> ```
>
> macOS is covered by the `_TARGET_MACHO == 2` arm, and x86 is native. So "zero arch guards" is
> true as written and yet costs nothing: the guard is the compiler's translation table, by design.
>
> **2. §4 would move `net.cyr` OFF the sanctioned pattern and INTO a documented hazard.** CLAUDE.md
> states the convention outright: *"aarch64 stdlib syscall numbers that collide with an x86 number
> in ESYSXLAT get silently mis-remapped — use the x86 number + an ESYSXLAT entry."* `net.cyr`
> already does precisely that. Replacing it with per-arch peer wrappers carrying **native** numbers
> is the shape that rule exists to prevent, and it would do so to fix nothing observable.
>
> **What is genuinely real here** is the *silence* of the coupling, not the numbers: `net.cyr` has
> no way to state that it depends on those nine rows, so deleting a row or adding a target breaks
> the socket surface with no signal until someone runs net on that hardware. That is a **missing
> gate**, not a missing abstraction — and the fix for a missing gate is to add the gate.
>
> **Recommended disposition:** re-scope this issue to "assert the net.cyr ⇄ ESYSXLAT coupling
> structurally" and drop §4. §9 (the AF_UNIX surface) is unaffected and remains a separate yes/no
> for the maintainer.

**Status:** 🟡 **OPEN — but the §3 collision was DISARMED at v6.5.7 by a different mechanism than
§4 proposed.** Re-verified against live code on cycc **6.5.10**, 2026-08-07:

- **Still true (the filing's core):** `lib/net.cyr:10-16` carries the same seven bare x86 numbers,
  `grep -c CYRIUS_ARCH lib/net.cyr` → **0**, and the nine `ESYSXLAT` x86-compat socket rows are
  still live (`src/backend/aarch64/emit.cyr:865-873`, `41→198 · 42→203 · 43→202 · 49→200 ·
  50→201 …`). No `net.cyr` call was moved onto a per-arch peer wrapper. §4 is unshipped.
- **No longer true (§3's armed collision):** `fn sys_chdir` now exists
  (`lib/syscalls_linux_common.cyr:191`) — W1 landed it at **v6.5.7** — and it does **not** call
  `bind`. The escape was a **new ≥1000 cyrius-private alias band**: `SYS_CHDIR = 1049` on the
  aarch64 peer (`lib/syscalls_aarch64_linux.cyr:122`), renumbered by ESYSXLAT to native 49 on
  aarch64 and to 12 on Darwin. So the trap this file predicted **fired for real** — CHANGELOG
  [6.5.7] records `chdir` returning `-EBADF` on ecb/pi when `vr01_syscall_wrappers.tcyr` first ran
  it — and was closed by making the x86-compat shim unreachable from source instead of by
  retiring it. The remaining nine x86 numbers stay burned for any future aarch64-peer constant.
- **Severity accordingly: still Medium, no longer escalating.** The "bump to High if W1 lands a
  `sys_chdir` wrapper before this is fixed" trigger in §6 **did** fire; it was neutralised at the
  same release, so do not re-read §6 as an open escalation. The residual risk is the one the alias
  band now formalises: nine numbers permanently unavailable to the aarch64 peer.

⭐ **Two items added 2026-08-07 (see §5a and §9), from setu 0.8.4:** (1) the ESYSXLAT socket block is
**easy to audit wrongly** — it is split across a macho branch and a Linux branch a hundred lines apart,
and a consumer read the wrong one and shipped a confident wrong claim; the block also covers only nine
numbers, so adjacent calls (`recvfrom` 45, `unlink` 87) get **no** rescue and mis-dispatch silently.
(2) `net.cyr` has **no AF_UNIX support at all**, which is the root reason both known consumers left the
stdlib rather than a preference for raw syscalls.

**Placement:** unpinned — 6.x-line stdlib backlog, never 7.x. No dedicated slot in `roadmap.md` at
6.5.10. It is a finite cleanup that rides an adjacent net/stdlib release; the ≥1000 alias band has
removed the deadline pressure that §6 rested on.
**Severity:** Medium — nothing is broken *today*, but the mechanism keeping it working is the one the stdlib has twice documented as the wrong answer, and it has now armed a collision against planned work (roadmap W1). See Severity rationale.

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

# The armed collision (see §3) — AS FILED, 2026-07-30:
grep -n "SYS_CHDIR" lib/syscalls_aarch64_linux.cyr   # → 95:    SYS_CHDIR = 49;
grep -rn "sys_chdir" lib/regression.cyr              # → 658:        sys_chdir(work_dir);
grep -rn "fn sys_chdir" lib/ src/                    # → nothing: the wrapper does not exist yet
```

⚠ **Those last two lines no longer reproduce** — re-run 2026-08-07 on 6.5.10 they give
`lib/syscalls_aarch64_linux.cyr:122:    SYS_CHDIR = 1049;` (the private alias) and
`lib/syscalls_linux_common.cyr:191:fn sys_chdir(path): i64 {`. The first two lines — the seven
bare x86 constants and `grep -c CYRIUS_ARCH lib/net.cyr` → 0 — still reproduce exactly.

## 3. Root cause — and the collision this has already armed

> ⚠ **The prediction in this section came true and has since been closed — read it as history.**
> W1 landed `fn sys_chdir` at **v6.5.7**, `vr01_syscall_wrappers.tcyr` turned RED on ecb and pi,
> and the diagnosis was exactly the one below: native 49 eaten by the `bind(49→200)` shim,
> `chdir` returning `-EBADF`. The fix was **not** §4's retirement of the shim (51 ecosystem repos
> emit raw `syscall(54, …)` and the rows are load-bearing) but a new **≥1000 cyrius-private alias
> band**: `SYS_CHDIR = 1049` on the aarch64 peer, ESYSXLAT-renumbered to 49. The x86 number 80 was
> no escape either — that is the aarch64 peer's own `SYS_FSTAT`. Live at
> `lib/syscalls_aarch64_linux.cyr:122`. The table below is therefore **no longer an open hazard**;
> the burned-number analysis around it still is.


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

### 5a. Second consumer, 2026-08-07 — setu 0.8.4, and it went WRONG first

setu (the AGNOS display-protocol contract lib) moved its Linux transport off TCP onto
**AF_UNIX / SOCK_SEQPACKET** and hit §9 immediately: there is no AF_UNIX support in `net.cyr` to
call. It reached for raw `syscall(41, …)` — **the exact shape this filing is about** — and did so
after reading `net.cyr` and finding nothing, *without checking the syscall peers*, where
`sys_socket` / `sys_connect` / `sys_bind` / `sys_listen` / `sys_accept4` / `sys_recvfrom` /
`sys_unlinkat` all already exist and are per-arch correct.

⛔ **THE INSTRUCTIVE PART IS THE MIS-DIAGNOSIS, AND IT IS A HAZARD THIS FILING SHOULD NAME.** The
setu author checked whether `ESYSXLAT` would rescue the raw numbers on aarch64, read the **macho**
block (`emit.cyr:760-773`), found no socket rows there, and concluded *"ESYSXLAT contains no socket
numbers at all"* — then wrote that into a shipped CHANGELOG. The Linux x86-compat socket block is a
hundred lines further down at `:865-873` and contains exactly those rows. **The renumber chain is
hard to audit from the outside**: it lives in the backend, it is split across two target branches,
and a consumer checking "am I safe on aarch64?" can read the wrong half and reach a confident wrong
answer in either direction.

⭐ **And the half-truth is the dangerous shape.** Of the seven numbers setu hardcoded, five (41 socket,
42 connect, 43 accept, 49 bind, 50 listen) **are** in the block and would have worked. Two are not:

| x86 number | call | in the ESYSXLAT socket block? | aarch64 outcome |
|---|---|---|---|
| 45 | `recvfrom` | ⛔ **no** | not renumbered — silent mis-dispatch |
| 87 | `unlink` | ⛔ **no** | aarch64 Linux has no `unlink(2)` at all; needs `unlinkat(AT_FDCWD, path, 0)` — a different ARITY, which no renumber chain can express |

So a consumer that copies `net.cyr`'s pattern gets a **partially** working result: the socket calls
survive, the adjacent ones do not, and nothing fails at build time. That is worse than a uniformly
broken one, because the working majority reads as evidence the pattern is sound.

⚠ **Arity is the hard limit on the whole mechanism.** `ESYSXLAT` renumbers `x8`; it cannot add an
argument. Any x86 syscall whose aarch64 replacement takes different arguments — `unlink`→`unlinkat`,
`open`→`openat`, `stat`→`fstatat` — is permanently outside what the renumber chain can fix, no matter
how many rows are added. That is an argument for §4 independent of the burned-number analysis.

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

> ⚠ **The first trigger fired and was handled — see the Status block.** W1 landed `sys_chdir` at
> v6.5.7 and the collision was closed the same release via the ≥1000 private-alias band, so this
> is **not** an open escalation. The second trigger stands: the eight remaining burned values are
> still unavailable to the aarch64 peer, and the alias band is now the documented escape from
> them (`SYS_FCHOWNAT = 1054`, `SYS_CHDIR = 1049`).

## 9. NEW (2026-08-07) — `net.cyr` has no AF_UNIX at all, which is why consumers keep leaving it

Separate from the arch-guard defect, and surfaced by the same setu work: **the stdlib has no
Unix-domain socket support whatsoever.**

```bash
grep -rn "AF_UNIX\|sockaddr_un\|SOCK_SEQPACKET" lib/     # → nothing
sed -n '30,34p' lib/net.cyr
#   enum SockDomain { AF_INET = 2; AF_INET6 = 10; }
#   enum SockType   { SOCK_STREAM = 1; SOCK_DGRAM = 2; }
```

`SockDomain` has no `AF_UNIX = 1`; `SockType` has no `SOCK_SEQPACKET = 5`; there is no `sockaddr_un`
builder anywhere. So a consumer wanting a **local** socket has no stdlib path at all and must
hand-roll the address structure and reach past `net.cyr` — which is precisely how both known
consumer workarounds (§5, §5a) came about.

⭐ **This is not a niche ask.** It is the correct primitive for local IPC, and it is what the two
in-tree consumers actually need: bote's transport is Unix-socket; setu's host transport is now
AF_UNIX/SOCK_SEQPACKET because TCP-on-loopback was ruled the wrong primitive for local display IPC.
`socketpair(SOCK_SEQPACKET)` is also what agnos's own channel-band semantic proof is written against,
so the semantics are already load-bearing in the ecosystem — just not expressible through the stdlib.

**Proposed shape** (small, and independent of §4):

```
enum SockDomain { AF_INET = 2; AF_INET6 = 10; AF_UNIX = 1; }
enum SockType   { SOCK_STREAM = 1; SOCK_DGRAM = 2; SOCK_SEQPACKET = 5; }

fn sockaddr_un(path, sa): i64          # build sockaddr_un, return addrlen (2 + len + 1)
fn unix_socket(type): Result           # AF_UNIX socket, SOCK_STREAM or SOCK_SEQPACKET
fn unix_connect(fd, path): Result
fn unix_bind(fd, path): Result         # unlinks the stale node first — see below
fn unix_listen(fd, backlog): Result
```

⚠ **`unix_bind` must unlink before binding.** An AF_UNIX node is a filesystem entry that OUTLIVES its
process, so a server killed without a clean shutdown leaves it and every later bind fails
`EADDRINUSE`. Leaving that to each consumer reproduces, per-consumer, the "second run hosts nothing
and otherwise looks completely healthy" failure — setu hit exactly that shape with a leaked TCP
listener and now unlinks at bind time, because a shutdown path is skipped by a crash.

⚠ **Missing peer wrappers this also needs:** `sys_shutdown` (§4 already notes it) and nothing else —
`sys_socket`/`sys_connect`/`sys_bind`/`sys_listen`/`sys_accept4`/`sys_recvfrom`/`sys_unlinkat` are all
present and per-arch already, which is the point: the wrappers exist, `net.cyr` just doesn't use them
and doesn't expose AF_UNIX on top of them.

## 7. Related issues

- [`archived/2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md`](2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number.md)
  — same family; documented that `fn sys_chdir` existed nowhere. **RESOLVED and archived at
  v6.5.7.** Its landing did fire the §3 collision as predicted, and the same release neutralised
  it with the ≥1000 alias band.
- [`archived/2026-07-14-sandhi-peer-api-use-stdlib-getpeername.md`](2026-07-14-sandhi-peer-api-use-stdlib-getpeername.md)
  — the precedent. Resolved by adding per-arch wrappers and explicitly *rejecting* an ESYSXLAT
  entry.
- [`archived/2026-06-04-macos-net-socket-syscalls-unported.md`](2026-06-04-macos-net-socket-syscalls-unported.md)
  — added the macho socket renumbers; the Darwin axis stays.
- Roadmap **W1** (*Missing syscall wrappers — one pass*).

## 8. Pointers

*(Line numbers re-derived live 2026-08-07 on 6.5.10; the as-filed numbers had drifted.)*

- `lib/net.cyr:10-16` — the seven unguarded constants; `:350` — `syscall(SYS_ACCEPT, fd, 0, 0)` *(both unchanged)*
- `lib/syscalls_linux_common.cyr:456` `sys_socket` · `:496` `sys_setsockopt` · `:501` `sys_connect` ·
  `:517` `sys_bind` · `:522` `sys_listen` · `:528` `sys_accept4` — every replacement wrapper except `sys_shutdown`
- `lib/syscalls_linux_common.cyr` — the `getpeername` note ("do NOT solve this with an ESYSXLAT
  entry for x86-52"); the argument this filing rests on
- `lib/syscalls_x86_64_linux.cyr:109` / `lib/syscalls_aarch64_linux.cyr:211` — `SYS_ACCEPT4` 288 / 242
- `lib/syscalls_aarch64_linux.cyr:122` — `SYS_CHDIR = 1049` (**was** `= 49` when filed; the v6.5.7
  private-alias band, which is what disarmed §3)
- `src/backend/aarch64/emit.cyr:865-873` — `ESYSXLAT`, v6.2.10 x86-compat socket block (Linux);
  `:760-773` — the v6.0.59 macho block
- Consumer precedent: `bote/src/transport_unix.cyr` (bote 3.2.1, `sys_accept4` swap + rationale)
- Reported alongside sandhi's accept-loop hardening — sandhi CHANGELOG `[Unreleased]`,
  `sandhi/docs/development/issues/2026-07-30-accept-loop-unguarded-spin.md`
