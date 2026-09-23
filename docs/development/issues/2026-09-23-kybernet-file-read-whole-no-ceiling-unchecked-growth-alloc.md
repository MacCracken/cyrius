# `file_read_whole` has no size ceiling and does not check its growth `alloc()`: a file that does not end is a write through NULL — OPEN

**Status:** 🟡 **OPEN**: verified 2026-09-23 against the installed 6.6.6 snapshot
(`~/.cyrius/lib/io.cyr:573`): `nb = alloc(ncap + 1)` is followed by `memcpy(nb, buf, total)` with no
check, and the read loop ends only at EOF or a read error.
**Placement:** unpinned — 6.6.x-line backlog (never 7.x).
**Discovered:** 2026-09-23 during kybernet 1.7.8, which set out to adopt `file_read_whole` to retire
kybernet's fixed 16 KiB `config.json` read.
**Severity:** Medium: a crash with a known workaround. In kybernet the caller is PID 1, where a crash
is a kernel panic.
**Affects:** cycc 6.6.6 (checked). Earlier releases not checked.

## Summary

`file_read_whole(path, len_out)` doubles its buffer until the file ends. Three things follow:

1. **The growth allocation is unchecked.** When `alloc(ncap + 1)` returns 0, the next line copies the
   bytes read so far through it: SIGSEGV at address 0.
2. **There is no ceiling.** A file that does not end (`/dev/zero`, or anything a caller was pointed
   at by mistake or by a symlink) or a very large one grows the buffer until (1) fires. A caller has
   no way to say "no more than N bytes", so it cannot use the function on a path it does not fully
   trust.
3. **Every call allocates a new buffer of at least 65,537 bytes**, even for a 2-byte file. Under the
   bump allocator nothing is freed, so a long-running process that re-reads a file (kybernet
   re-reads its config on every SIGHUP) loses at least 64 KiB per read.

(1) and (2) together are the crash. (3) is a cost, and matters only for processes that live long
and read repeatedly.

## Reproduction

```cyrius
include "lib/thread_local.cyr"

fn main() {
    alloc_init();
    var n = 0;
    var b = file_read_whole("/dev/zero", &n);
    sys_write(1, "returned\n", 9);
    return 0;
}
```

Built in kybernet's tree (cycc 6.6.6), run under a 2 GB address-space limit:

```sh
(ulimit -v 2000000; ./probe; echo "exit=$?")        # exit=139, "returned" never printed
```

Under `qemu-x86_64 -strace` (read lines omitted), the buffer doubles to 512 MiB, the mapping for
the next doubling is refused, and the copy faults:

```
open("/dev/zero",O_RDONLY) = 3
mmap(NULL,536870912,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = 0x00007f22e4000000
mmap(NULL,805306368,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = 0x00007f22b4000000
mmap(NULL,1342177280,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = -1 errno=12 (Cannot allocate memory)
--- SIGSEGV {si_signo=SIGSEGV, si_code=1, si_addr=NULL} ---
```

The per-call cost, measured with `_heap_used` around two calls on a 2-byte file (`{}`):

```
file_read_whole tiny call 1 bytes allocated: 65544
file_read_whole tiny call 2 bytes allocated: 65544
```

## Root cause

`lib/io.cyr`, `file_read_whole` (`:573` in the 6.6.6 snapshot):

```cyrius
var cap = 65536;
var buf = alloc(cap + 1);
...
    if (total == cap) {
        var ncap = cap + cap;
        var nb = alloc(ncap + 1);
        memcpy(nb, buf, total);
```

`alloc` returns 0 when `_linux_new_chunk` cannot map a chunk (`alloc.cyr`, the `== 0` return in
`alloc`), and at `ALLOC_MAX` (2 GiB). Nothing between that and the `memcpy` looks at `nb`.

The first `alloc(cap + 1)` is unchecked as well. Speculation, not measured: with a NULL buffer the
first `read(2)` should fail with EFAULT, which the function already turns into "return 0", so that
one may be harmless by accident.

## Proposed fix

- **Check both allocations.** On 0: close the fd, `store64(len_out, 0)`, return 0, the same answer as
  an open or read failure.
- **Give callers a ceiling.** For example `file_read_whole_max(path, max, len_out)`, which stops at
  `max` bytes and reports "the file is larger than `max`" distinctly from a read error (a negative
  errno such as `-EFBIG`, or `len_out = max + 1`). The caller keeps the policy; the stdlib never reads
  without end. `file_read_whole` could become the unbounded wrapper over it.
- **Optional, for long-running processes:** a form that reads into a caller-owned, growable buffer,
  so a re-read reuses it instead of allocating a new 64 KiB one each time. kybernet's workaround
  below has that shape.

## Consumer-side workaround

kybernet 1.7.8, `src/lib/read_whole.cyr`: `read_whole_into(rb, path, first_cap, ceiling)`. The
caller keeps `rb` = `{ ptr, cap }` for the life of the process. The function opens before it
allocates, checks every allocation (returns `-ENOMEM`), grows by doubling up to `ceiling`, and at the
ceiling reads one more byte so a larger file comes back as `ceiling + 1` instead of a prefix. The
data is NUL-terminated. kybernet uses it for `/etc/kybernet/config.json` (256 KiB ceiling) and
`/proc/self/mounts` (1 MiB).

It is a stopgap. kybernet will move both call sites back onto `file_read_whole` once the function
has a ceiling and a checked growth path.
