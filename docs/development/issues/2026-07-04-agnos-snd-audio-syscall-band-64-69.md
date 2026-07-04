# Add the agnos `sys_snd_*` audio peer band (#64–#69)

> **Filed 2026-07-04 by the agnos audio arc (1.52.x Gate 2), not yet scheduled.**
> Two-sided ABI request, same shape as the `sys_symlink#63` and the net band
> (`sys_sock_connect#47`…). agnos owns the six kernel handlers; cyrius owns the
> matching ring-3 wrappers. The numbers below are **FROZEN** on the agnos side
> (design + 2-pass adversarial verify complete; signatures did not move) — safe
> to mirror without drift. Land on any release line that touches
> `lib/syscalls_x86_64_agnos.cyr`.

**Filed:** 2026-07-04 · **Status:** ✅ RESOLVED v6.4.2 (2026-07-04) · **Severity:** P2 (unblocks agnos audio for vani + cyrius-doom)

> **RESOLVED v6.4.2** — the six `SYS_SND_*` constants (#64–#69) + seven wrappers
> (`sys_snd_open`/`_config`/`_write`/`_write_nb`/`_close`/`_drain`/`_avail`) landed in
> `lib/syscalls_x86_64_agnos.cyr`, verbatim to the frozen ABI. `sys_snd_write_nb` uses the
> 5-arg `syscall(N, slot, buf, frames, 1)` form (a4=r10 bit0 = O_NONBLOCK), same as
> `sys_symlink`'s a4 path — the compiler passes it via push→`pop %r10`, so no drift. Purely
> additive, agnos-gated (`#ifdef CYRIUS_TARGET_AGNOS`) → cycc **byte-identical** on
> Linux/macOS/Windows/aarch64; the agnos build compiles all seven (a probe calling each →
> valid agnos ELF, emits `syscall` with eax=0x40–0x45) and the standing
> `agnos-crossbuild-gate.sh` stays green. Runtime (HDA → ALC897) validates on the agnos
> side in QEMU. See CHANGELOG [6.4.2].

## What

Add six `sys_snd_*` wrappers + their `SYS_SND_*` constants to
`lib/syscalls_x86_64_agnos.cyr`, mirroring the frozen agnos audio syscall band
`#64–#69`. This is the ring-3 half of the two-sided freeze — the agnos kernel
handlers are landing in parallel (agnos 1.52.x Gate 2), and vani's agnos backend
+ cyrius-doom bind to these wrappers to reach the HDA output. Until the wrappers
exist, no ring-3 code can call the band (the `sys_symlink` lesson: the kernel arm
alone is a no-op to userland until the peer exposes the numbers).

Purely additive — the same mechanical change as when `sys_symlink#63` and the
`#45–#61` net band were added. No behavior change to existing wrappers.

## The frozen ABI (agnos `syscall.cyr` #64–#69)

The output stream is **hard-armed at 48000 Hz / 16-bit / stereo** (4 bytes/frame);
the kernel does **no** format conversion (a dumb byte-mover) — any resample is the
producer's job (cyrius-doom already owns its mixer). All calls take an `snd_id`
slot `0..3`; `#65–#69` reject a slot that isn't allocated-and-owned by the caller
(returns `-1`), like `flock`.

| # | signature | returns | notes |
|---|-----------|---------|-------|
| 64 | `snd_open()` | slot `0..3`, or `-1` | no args; grabs the single output stream, `-1` if busy / no device / table full. Auto-released on proc-exit. |
| 65 | `snd_config(slot, rate, fmt)` | `0` / `-1` | **`rate` MUST be `48000`**; **`fmt = (bits<<8)|ch` MUST be `0x1002`** (16-bit, 2ch). Rejects anything else, and rejects reconfig once audio is queued. |
| 66 | `snd_write(slot, buf, frames)` | frames written (`>=0`), or `-1` | **blocking** by default (feeds PCM, blocks until the DMA frees ring space, bounded deadline); **`a4` bit0 = `O_NONBLOCK`** → single pass, may return `0` = WOULD_BLOCK. `buf` = S16 stereo interleaved, `frames*4` bytes, range-checked. |
| 67 | `snd_close(slot)` | `0` / `-1` | release the slot. |
| 68 | `snd_drain(slot)` | `0` | block until the queued audio plays out (bounded ~1s deadline — the DMA loops forever, so it can never hang). |
| 69 | `snd_avail(slot)` | free frames (`>=0`), or `-1` | non-blocking. |

## The peer to add (matches the `sys_symlink` / net one-liner style)

Constants block (next to `SYS_SYMLINK = 63`):

```
    SYS_SND_OPEN   = 64;   # snd_open() -> slot 0..3 / -1
    SYS_SND_CONFIG = 65;   # snd_config(slot, rate, fmt) -> 0 / -1  (rate=48000, fmt=(bits<<8)|ch=0x1002)
    SYS_SND_WRITE  = 66;   # snd_write(slot, buf, frames) -> frames / -1;  a4=r10 bit0 = O_NONBLOCK
    SYS_SND_CLOSE  = 67;   # snd_close(slot) -> 0 / -1
    SYS_SND_DRAIN  = 68;   # snd_drain(slot) -> 0  (blocks until play-out / ~1s cap)
    SYS_SND_AVAIL  = 69;   # snd_avail(slot) -> free frames / -1
```

Wrappers (next to `sys_symlink` / `sys_sock_*`):

```
fn sys_snd_open(): i64 { return syscall(SYS_SND_OPEN); }
fn sys_snd_config(slot, rate, fmt): i64 { return syscall(SYS_SND_CONFIG, slot, rate, fmt); }
fn sys_snd_write(slot, buf, frames): i64 { return syscall(SYS_SND_WRITE, slot, buf, frames); }
fn sys_snd_write_nb(slot, buf, frames): i64 { return syscall(SYS_SND_WRITE, slot, buf, frames, 1); }  # a4=r10 bit0 = NONBLOCK
fn sys_snd_close(slot): i64 { return syscall(SYS_SND_CLOSE, slot); }
fn sys_snd_drain(slot): i64 { return syscall(SYS_SND_DRAIN, slot); }
fn sys_snd_avail(slot): i64 { return syscall(SYS_SND_AVAIL, slot); }
```

The only non-obvious one is `snd_write`'s **`a4`/r10 NONBLOCK** bit — the same
`syscall(N, a1, a2, a3, a4)` 5-arg form `sys_symlink` uses for its 4th arg. The
blocking `sys_snd_write` uses the 3-arg form (a4 defaults 0); `sys_snd_write_nb`
passes `1`.

## Why / two-sided context

This is the Gate-2 half of the 1.52.x audio arc (first sound landed on real ALC897
hardware at 1.52.5; the streamed-PCM double-buffer ring landed 1.52.6). The
critical path to cyrius-doom sound is: **cyrius-doom `audio.cyr` → vani agnos
backend → these `sys_snd_*` wrappers → agnos `#64–#69` → the HDA ring → ALC897.**
The `sys_snd_*` wrappers are the one piece that must live in cyrius (hands-off for
the agnos side to edit — hence this issue rather than a direct commit).

**No format negotiation to co-design:** the band is deliberately single-format
(48k/16/stereo), so the wrappers are a straight passthrough — the producer
(cyrius-doom's existing 11025→48000 upsample) does all conversion. That keeps the
freeze clean.

## Status of the agnos side

Landing in parallel as agnos 1.52.x Gate 2 (kernel handlers + a ring-3 selftest,
QEMU-validated via WAV capture — audio validates in QEMU, not an iron burn). If any
signature shifts during implementation (not expected — the numbers are frozen), the
agnos side will update this issue to keep the two halves in lockstep. Consumers:
vani (needs an agnos backend written against these) + cyrius-doom (retarget
`audio_write` onto `sys_snd_*` + a 48000 fractional-upsample tweak, its own repo).
