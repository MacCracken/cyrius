# agnos shm `#71-74` has no `sys_shm_*` peer — every shared-buffer consumer hardcodes raw syscall numbers

> **✅ RESOLVED cyrius-side (v6.4.34, 2026-07-09):** `SYS_SHM_CREATE/WRITE/READ/FREE` (71-74)
> + `sys_shm_create`/`_write`/`_read`/`_free` wrappers added to `lib/syscalls_x86_64_agnos.cyr`
> after `sys_readlink`#70. agnos-target compile verified; default cycc byte-identical;
> api-surface snapshot regenerated. **Downstream flip DONE (2026-07-09):** setu `buf.cyr`'s
> agnos branch now calls the native `sys_shm_*` wrappers (0 raw `syscall(71..74)` left); setu +
> aethersafha pins bumped →6.4.34 (aethersafha needed `cyrius lib sync --full`, not just
> `cyrius deps`). Re-proven both targets — `aethersafha-setu-smoke.sh` gate 4 green on agnos +
> the Linux file-backend PPM unchanged. **Nothing left — archive at v6.4.34 slot close.**

**Filed:** 2026-07-09 (setu `buf.cyr` — the sovereign shared-buffer PRESENT backend; agnos kernel
half shipped + QEMU-proven in agnos 1.53.9).
**Severity:** **P3 — ABI-completeness / stdlib surface.** A consumer stopgap is in place and
proven, so nothing is *blocked* — but without the named wrappers the syscall band is invisible
to every other program and to the ABI doc, so the primitive does not trickle out.
**Component:** `lib/syscalls_x86_64_agnos.cyr` — the agnos syscall wrapper bands. The file-op /
socket peers end at `SYS_READLINK = 70`; there is **no `sys_shm_*` band**. (Sibling to the pending
`sys_readlink`#70 peer.)

## The gap

agnos 1.53.9 added a COPY-based **kernel-owned shared-memory buffer** band so two ring-3 procs can
hand a pixel buffer across without streaming it over a socket (deadlocks on a single core: a
hundreds-of-KB payload can't drain through the 2 KB `TCP_RX_RING` while the sender holds preemption
in `sock_send`#48) or mapping a shared page (a page mapped into a proc's arena is freed by
`proc_free_address_space` on exit → a client that exits right after present frees a page the
compositor is still reading). It backs the setu shared-buffer present (dhancha/puka → aethersafha),
now composited end-to-end on agnos (`aethersafha-setu-smoke.sh` gate 4 green).

The setu backend (`setu/src/buf.cyr`) drives it today with **bare `syscall(71..74)` literals** in
its `#ifdef CYRIUS_TARGET_AGNOS` branch:

```cyrius
# setu/src/buf.cyr — the current stopgap (works, but hardcodes the numbers)
fn setu_buf_create(size): i64        { ... return syscall(71, size); ... }
fn setu_buf_write(buf_id, src, size): i64 { ... return syscall(72, buf_id, src, size); ... }
fn setu_buf_read(buf_id, dst, size): i64  { ... return syscall(73, buf_id, dst, size); ... }
fn setu_buf_close(buf_id): i64       { ... return syscall(74, buf_id); ... }
```

It compiles + runs, but the next consumer that wants a shared buffer has to re-derive `71..74` from
the kernel source. The named wrappers are where the numbers get documented + reused.

## The kernel ABI to wire against (verified from agnos `kernel/core/syscall.cyr`, QEMU-proven)

COPY-based, kernel-owned. 16-slot table over single 2 MB pmm pages; **ids are 1-based** (0 is the
setu "inline pixels" sentinel — a real buffer is never 0). The page's `pmm_kva_for_access` KVA is in
the kernel mirror, so `shm_write` (client CR3) and `shm_read` (compositor CR3) both reach it from
their own syscall context with a plain copy — no cross-proc mapping.

```
shm_create(size = a1)                 -> id (>= 1) / -1     # #71  size > 0, <= 2 MB (one page)
shm_write(id = a1, src = a2, len = a3) -> 0 / -1            # #72  copy user src -> buffer (is_user_range'd)
shm_read (id = a1, dst = a2, len = a3) -> 0 / -1            # #73  copy buffer -> user dst (is_user_range'd)
shm_free (id = a1)                    -> 0 / -1             # #74  release page + slot
```
`-1` on bad id / bad size / `len > the buffer's size` / bad user range / (create: pmm OOM or table full).
Numbers `#71-74` = the next free agnos band after `readlink`#70.

## The peers to add (mirror `sys_readlink`'s shape)

```cyrius
# in the agnos Sys enum, after SYS_READLINK = 70:
    SYS_SHM_CREATE = 71;   # shm_create(size) → id (>=1) / -1  — kernel-owned shared buffer
    SYS_SHM_WRITE  = 72;   # shm_write(id, user_src, size) → 0 / -1
    SYS_SHM_READ   = 73;   # shm_read(id, user_dst, size)  → 0 / -1
    SYS_SHM_FREE   = 74;   # shm_free(id) → 0 / -1

# The COPY-based shared-buffer band (agnos shm #71-74). A writer shm_write#72s a buffer, hands the id
# over its own IPC, a reader shm_read#73s it — no page mapping, no socket streaming. Backs the setu
# shared-buffer present (buf.cyr). ids are 1-based (0 = the setu "inline" sentinel).
fn sys_shm_create(size): i64         { return syscall(SYS_SHM_CREATE, size); }
fn sys_shm_write(id, src, size): i64 { return syscall(SYS_SHM_WRITE, id, src, size); }
fn sys_shm_read(id, dst, size): i64  { return syscall(SYS_SHM_READ, id, dst, size); }
fn sys_shm_free(id): i64             { return syscall(SYS_SHM_FREE, id); }
```

No Linux/Windows/mac twin is required — the band is agnos-kernel-only (no host equivalent). A
consumer that wants a portable "shared buffer" abstraction keeps its own per-target split (setu's
`buf.cyr` does: Linux = a `/dev/shm/setu-buf-<id>` file, agnos = this band); these wrappers are just
the agnos leg. `_agnos`-guarded like the rest of the file, so a Linux build never sees them.

## Done-criteria

`sys_shm_create` / `_write` / `_read` / `_free` are in `lib/syscalls_x86_64_agnos.cyr`, and setu
`buf.cyr`'s agnos branch calls the **native** wrappers (not the raw literals) after its next `lib/`
re-sync. On landing, flip `buf.cyr`'s four `syscall(71..74)` sites to `sys_shm_*(...)`.

## Cross-refs

- agnos-side mirror of this ticket: `agnos/docs/development/issues/2026-07-09-cyrius-agnos-shm-syscall-peers.md`
- agnos kernel: `kernel/core/syscall.cyr` (the `shm_*` helpers + `#71-74` dispatch), CHANGELOG `[1.53.9]`
- consumer: `setu/src/buf.cyr`; design: `agnosticos/docs/development/planning/shared-buffer-present.md`
- precedent: the pending `sys_readlink`#70 peer (same "kernel half shipped, wrapper missing" shape)
