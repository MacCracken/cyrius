# Standard Library Reference

## Core Libraries

### string.cyr

Memory and string operations on null-terminated C strings.

| Function | Signature | Description |
|----------|-----------|-------------|
| `strlen` | `strlen(s) → len` | Length of null-terminated string |
| `streq` | `streq(a, b) → 0/1` | Compare two strings for equality |
| `memeq` | `memeq(a, b, n) → 0/1` | Compare n bytes |
| `memcpy` | `memcpy(dst, src, n)` | Copy n bytes |
| `memset` | `memset(dst, val, n)` | Fill n bytes with val |
| `memchr` | `memchr(s, c, n) → idx/-1` | Find byte in buffer |
| `strchr` | `strchr(s, c) → idx/-1` | Find byte in string |
| `print_num` | `print_num(n)` | Print decimal integer to stdout |
| `println` | `println(s)` | Print string + newline to stdout |

### alloc.cyr

Bump allocator over anonymous-mmap chunks (v6.1.19; was `brk`-backed — switched so glibc's `brk` arena can't collide with the fdlopen/libssl bridge). `alloc_init()` is idempotent (v6.1.23). Call it before any allocation.

| Function | Signature | Description |
|----------|-----------|-------------|
| `alloc_init` | `alloc_init() → base` | Initialize heap (must call first) |
| `alloc` | `alloc(size) → ptr` | Allocate size bytes (8-byte aligned) |
| `alloc_reset` | `alloc_reset()` | Free all allocations (batch reset) |
| `alloc_used` | `alloc_used() → bytes` | Current allocation total |
| `default_alloc` | `default_alloc() → Allocator` | Process-wide default `Allocator` (static storage since v6.5.7 — see the reset warning) |

> ⚠ **`alloc_reset()` invalidates every pointer the allocator has ever handed
> out**, including ones the stdlib itself is holding — any `Str`, `vec`,
> hashmap, arena or struct built before the reset is dangling afterwards, and
> the reused span is zeroed *and* re-issuable, so a stale read returns zeros
> until something else is allocated over it. Reset only when nothing from the
> previous epoch will be read again. (v6.5.7 moved the default-`Allocator`
> vtable to static storage so the stdlib's own memo survives; consumer-held
> pointers remain the caller's problem.)

**Arenas** — independent bump pools. Freeing or resetting one arena doesn't
touch other arenas or the global allocator. The backing chunks come from the
global bump.

| Function | Signature | Description |
|----------|-----------|-------------|
| `arena_new` | `arena_new(capacity) → arena` | Fixed-size arena; `arena_alloc` returns 0 once exhausted |
| `arena_new_growable` | `arena_new_growable(initial) → arena` | v6.5.9 — chains another `initial`-sized chunk instead of failing |
| `arena_set_on_full` | `arena_set_on_full(a, policy) → 0/-1` | v6.5.9 — set the exhaustion policy (`ARENA_FULL_*`) |
| `arena_on_full` | `arena_on_full(a) → policy/-1` | v6.5.9 — read the policy back (-1 on a null handle) |
| `arena_alloc` | `arena_alloc(a, size) → ptr` | Allocate from the arena (8-byte aligned); on exhaustion follows the policy |
| `arena_reset` | `arena_reset(a) → 0` | Rewind. For a GROW arena this rewinds to the FIRST chunk and **keeps** the chain, so a request loop converges on its high-water mark |
| `arena_capacity_total` | `arena_capacity_total(a) → bytes` | v6.5.9 — bytes across **every** chunk (what `arena_used`/`arena_remaining`, which see only the current chunk, cannot show once grown) |
| `arena_used` | `arena_used(a) → bytes` | Bytes used in the current chunk |
| `arena_remaining` | `arena_remaining(a) → bytes` | Bytes left in the current chunk |
| `arena_free` | `arena_free(a) → 0` | Invalidate the handle — zeroes bounds, policy **and** the chunk chain so later `arena_alloc` fails. Backing memory stays in the global bump until `alloc_reset` / exit |

Exhaustion policy constants (v6.5.9). Default is `ARENA_FULL_NULL`, so every
pre-existing arena behaves exactly as before:

| Constant | Value | Behaviour when the current chunk can't serve the request |
|----------|-------|---------------------------------------------------------|
| `ARENA_FULL_NULL` | `0` | Return 0 (the historical behaviour, still the default) |
| `ARENA_FULL_GROW` | `1` | Chain another chunk |
| `ARENA_FULL_SPILL` | `2` | Serve from the global allocator — spilled bytes are **never** reclaimed by `arena_reset` |
| `ARENA_FULL_ABORT` | `3` | Write a diagnostic to stderr and exit at the allocation site |

**Allocator interface** (v5.8.33) — a 40-byte vtable `{alloc_fn, realloc_fn,
free_fn, reset_fn, state}` threaded as a parameter (the `_a` convention).

| Function | Signature | Description |
|----------|-----------|-------------|
| `allocator_new` | `allocator_new(alloc_fn, realloc_fn, free_fn, reset_fn, state) → Allocator` | Build one from 4 fn pointers + state |
| `alloc_via` | `alloc_via(a, size) → ptr` | Allocate through the vtable |
| `realloc_via` | `realloc_via(a, old_ptr, old_size, new_size) → ptr` | Reallocate through the vtable |
| `free_via` | `free_via(a, ptr) → 0` | Free through the vtable (bump + arena impls treat as a no-op) |
| `reset_via` | `reset_via(a) → 0` | Reset through the vtable |
| `allocator_alloc_fn` / `allocator_realloc_fn` / `allocator_free_fn` / `allocator_reset_fn` / `allocator_state` | `(a) → slot` | Vtable slot accessors (+0/+8/+16/+24/+32) |
| `bump_allocator` | `bump_allocator() → Allocator` | Wraps the global bump — `reset_via` clears **every** global allocation |
| `arena_allocator` | `arena_allocator(capacity) → Allocator` | Wraps a fresh fixed arena |
| `arena_allocator_growable` | `arena_allocator_growable(initial) → Allocator` | v6.5.9 — wraps a fresh growable arena |
| `arena_allocator_set_on_full` | `arena_allocator_set_on_full(al, policy) → 0/-1` | v6.5.9 — set the policy through the allocator handle |
| `test_allocator` | `test_allocator() → Allocator` | Counting allocator for failing-allocator tests |
| `test_allocator_fail_after` | `test_allocator_fail_after(a, n) → 0` | Fail every alloc after the nth (-1 disables) |
| `test_allocator_alloc_count` / `test_allocator_bytes_total` | `(a) → n` | Read the counters |

v6.5.10 inlined the two accessor loads inside `alloc_via` / `realloc_via` /
`free_via` / `reset_via` (cyrius does not inline, so each accessor was a real
call): `alloc_via` went 15.1 ns → 11 ns. The accessors remain public API.

### str.cyr

Fat string type: `{data: ptr, len: i64}`. Requires alloc.cyr + string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `str_from` | `str_from(cstr) → Str` | Wrap C string as Str |
| `str_new` | `str_new(data, len) → Str` | Create from buffer + length |
| `str_len` | `str_len(s) → len` | Get length (also available as `s.len` on `: Str` typed locals — v5.8.17) |
| `str_data` | `str_data(s) → ptr` | Get raw data pointer (also available as `s.data` on `: Str` typed locals — v5.8.17) |
| `str_print` | `str_print(s)` | Print to stdout |
| `str_println` | `str_println(s)` | Print + newline |
| `str_eq` | `str_eq(a, b) → 0/1` | Compare two Str |
| `str_cat` | `str_cat(a, b) → Str` | Concatenate (allocates new) |
| `str_sub` | `str_sub(s, start, len) → Str` | Substring (shares data) |
| `str_clone` | `str_clone(s) → Str` | Deep copy |
| `str_contains` | `str_contains(s, needle) → 0/1` | Substring search |
| `str_starts_with` | `str_starts_with(s, prefix) → 0/1` | Prefix check |
| `str_ends_with` | `str_ends_with(s, suffix) → 0/1` | Suffix check |
| `str_index_of` | `str_index_of(s, byte) → idx/-1` | Find byte |
| `str_from_int` | `str_from_int(n) → Str` | Integer to string |
| `str_to_int` | `str_to_int(s) → n` | Parse string to integer |
| `str_trim` | `str_trim(s) → Str` | Strip whitespace |
| `str_split` | `str_split(s, sep) → vec` | Split by byte separator |
| `str_join` | `str_join(parts, sep) → Str` | Join vec of Str |
| `str_builder_new` | `str_builder_new() → sb` | Create string builder |
| `str_builder_add` | `str_builder_add(sb, str)` | Append Str |
| `str_builder_add_cstr` | `str_builder_add_cstr(sb, cstr)` | Append C string |
| `str_builder_add_int` | `str_builder_add_int(sb, n)` | Append integer |
| `str_builder_build` | `str_builder_build(sb) → Str` | Finalize to Str |

### slice.cyr

Stack-allocated 16-byte fat pointer (`{ptr@0, len@8}`). The `slice<T>`
/ `[T]` type annotation reserves the slot at PARSE_VAR time; the
helper API populates / inspects it. Byte-identical layout to the
first 16 bytes of `Str` and `vec` (zero-cost interop).

Subscript (`s[i]`, v5.8.15) and dot-syntax (`s.ptr` / `s.len`,
v5.8.16) work on **fn-local** slices only. Top-level vars use the
helper API.

| Function | Signature | Description |
|----------|-----------|-------------|
| `slice_set` | `slice_set(&s, ptr, len) → 0` | Initialize in-place |
| `slice_of` | `slice_of(&s, ptr, len) → 0` | Builder alias for `slice_set` |
| `slice_ptr` | `slice_ptr(&s) → ptr` | Read .ptr field |
| `slice_len` | `slice_len(&s) → len` | Read .len field |
| `slice_zero` | `slice_zero(&s) → 0` | Set both fields to 0 |
| `slice_copy` | `slice_copy(&dst, &src) → 0` | Copy ptr+len fields |
| `slice_eq` | `slice_eq(&a, &b) → 0/1` | Pointer-equality (NOT content) |
| `slice_is_empty` | `slice_is_empty(&s) → 0/1` | True iff `.len == 0` |
| `slice_is_null` | `slice_is_null(&s) → 0/1` | True iff `.ptr == 0` |
| `slice_from_cstr` | `slice_from_cstr(&dst, cstr) → 0` | Init from null-terminated string |
| `slice_from_buf` | `slice_from_buf(&dst, buf, len) → 0` | Init from `(buf, len)` pair |
| `vec_as_slice` | `vec_as_slice(&dst, v) → 0` | Snapshot vec's first 16 bytes |
| `_slice_idx_get_W(&s, i)` | width 1/2/4/8/16 | Bounds-checked sized load (used by `s[i]` lowering) |
| `slice_unchecked_get_W(&s, i)` | width 1/2/4/8/16 | Same as above, no bounds check |
| `sys_read_slice` | `sys_read_slice(fd, &s) → n` | `sys_read` taking a slice (v5.8.18) |
| `slice_copy_bytes` | `slice_copy_bytes(&dst, &src) → n` | `memcpy` with min-length cap (v5.8.18) |
| `slice_eq_bytes` | `slice_eq_bytes(&a, &b) → 0/1` | Content equality, length-mismatch is unequal (v5.8.18) |

### vec.cyr

Dynamic array. Elements are i64. Requires alloc.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `vec_new` | `vec_new() → vec` | Create empty vec (cap=16) |
| `vec_len` | `vec_len(v) → len` | Current length |
| `vec_cap` | `vec_cap(v) → cap` | Current capacity |
| `vec_push` | `vec_push(v, val)` | Append (auto-grows) |
| `vec_pop` | `vec_pop(v) → val` | Remove + return last |
| `vec_get` | `vec_get(v, idx) → val` | Read at index (bounds-checked) |
| `vec_set` | `vec_set(v, idx, val)` | Write at index (bounds-checked) |
| `vec_find` | `vec_find(v, val) → idx/-1` | Linear search |
| `vec_remove` | `vec_remove(v, idx)` | Remove + shift left |
| `vec_truncate` | `vec_truncate(v, new_len) → 0` | Shrink to `new_len` (no-op if already shorter); keeps capacity + buffer, so it's the bounded-memory save/restore primitive under a bump allocator |
| `vec_sort_by` | `vec_sort_by(v, cmp) → 0` | In-place sort by comparator. **Not** named `vec_sort` — that name is occupied in cyrius's flat namespace and last-definition-wins would displace it. O(n) pre-scan returns immediately on already-ordered input |
| `vec_select_nth` | `vec_select_nth(v, k, cmp) → val` | Element that would sit at index `k` if sorted, partitioning in place (Hoare quickselect, median-of-3; O(n) expected). Aborts on out-of-range `k` |
| `vec_new_a` / `vec_push_a` | `vec_new_a(a)` / `vec_push_a(a, v, val)` | Allocator-threaded variants (v5.8.35). `vec_push_a` returns -1 on grow OOM where `vec_push` aborts the process |

### io.cyr

File I/O wrappers around Linux syscalls.

| Function | Signature | Description |
|----------|-----------|-------------|
| `file_open` | `file_open(path, flags, mode) → fd` | Open file (legacy int-return) |
| `file_close` | `file_close(fd)` | Close file |
| `file_read` | `file_read(fd, buf, len) → n` | Read bytes |
| `file_write` | `file_write(fd, buf, len) → n` | Write bytes |
| `file_read_all` | `file_read_all(path, buf, max) → n` | Read entire file |
| `file_write_all` | `file_write_all(path, buf, len) → n` | Write entire file |
| `file_exists` | `file_exists(path) → 0/1` | Check if file exists |
| `getenv` | `getenv(name) → cstr/0` | Look up an environment variable |
| `print` | `print(msg, len)` | Write to stdout |
| `eprint` | `eprint(msg, len)` | Write to stderr |

**Portable syscall bridges — the `x*` family.** These exist because the raw
`sys_*` wrappers do **not** share one signature across targets: agnos's are
length-carrying (`sys_mkdir(path, pathlen)`, no mode) where POSIX takes
`(path, mode)`, so a consumer calling `sys_*` directly is correct on Linux and
silently wrong on agnos, with the surplus argument binding to garbage. Call
these instead of the raw wrappers — the cyrlint `xsys` rule nudges raw sites
here. All take/return raw cstrings + POSIX-shaped `0` / negative-errno.

| Function | Signature | Description |
|----------|-----------|-------------|
| `xopen` | `xopen(path, flags) → fd` | Open a regular file (namelen-bridged; 0644 default create mode) |
| `xunlink` | `xunlink(path) → 0/-errno` | Unlink. Windows routes to `DeleteFileW` (v6.4.58) |
| `xrmdir` | `xrmdir(path) → 0/-errno` | Remove an empty directory. **-1 on Windows** (no `RemoveDirectoryW` reroute wired) |
| `xmkdir` | `xmkdir(path, mode) → 0/-errno` | v6.5.7 — create a directory. Windows **does** route here |
| `xmkdir_p` | `xmkdir_p(path, mode) → 0/-1` | v6.5.7 — `mkdir -p`. Existing directory is success; tries the full path first, walks parents only on failure; paths >1023 bytes return -1 rather than truncating |
| `xsymlink` | `xsymlink(target, linkpath) → 0/-errno` | v6.5.7 — symlink. **-1 on Windows** |
| `xreadlink` | `xreadlink(path, buf, bufsize) → n/-errno` | v6.5.7 — read a symlink target. **NOT NUL-terminated** (readlink(2)'s contract). **-1 on Windows** |
| `xlink` | `xlink(oldpath, newpath) → 0/-errno` | v6.5.7 — hard link. **-1 on Windows** |
| `file_rename` | `file_rename(oldpath, newpath) → 0/-errno` | Rename/replace. Windows routes to `MoveFileExW(REPLACE_EXISTING)` |
| `xfsync` | `xfsync(fd) → 0/-errno` | Flush to stable storage. agnos has no per-fd fsync → whole-fs `sync` (documented residual); Windows is a no-op |
| `xstat` | `xstat(path, buf) → 0/-errno` | stat into `buf`. **-1 on Windows.** Read fields via `STAT_MODE` etc. — the offsets differ per arch (st_mode @24 x86-Linux, @16 aarch64, @4 macOS-arm64) |
| `xgetdents` | `xgetdents(fd, buf, n) → n/-errno` | Raw directory entries (caller parses the per-target record). **-1 on Windows** — use `dir_list` |
| `xlseek` | `xlseek(fd, off, whence) → off/-errno` | Reposition (whence 0=SET / 1=CUR / 2=END) |
| `xflock` | `xflock(fd, op) → 0/-errno` | Advisory whole-file lock (LOCK_SH=1 / LOCK_EX=2 / LOCK_UN=8, +LOCK_NB=4). **-1 on Windows** |

**Crash-safe write + locking helpers (v6.4.57–.58):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `file_write_atomic` | `file_write_atomic(path, buf, len) → 0/-errno` | Write a unique sibling temp → fsync → close → rename over `path`. On any failure the temp is unlinked and `path` is left intact |
| `file_create_exclusive` | `file_create_exclusive(path, mode) → fd/-17` | No-clobber create. Kernel-atomic on Linux/macOS (`O_CREAT\|O_EXCL`) and Windows (`CREATE_NEW`); **agnos degrades to a non-atomic `file_exists` pre-check** |
| `file_lock` / `file_unlock` | `(fd) → 0/-errno` | Exclusive lock / release (blocking on Linux+macOS; agnos flock is **non-blocking** — a contended `LOCK_EX` returns -1) |
| `file_trylock` | `file_trylock(fd) → 0/-1` | Non-blocking exclusive lock |
| `file_lock_shared` | `file_lock_shared(fd) → 0/-errno` | Shared (read) lock |
| `file_append_locked` | `file_append_locked(path, buf, len) → n/-errno` | Append under an exclusive lock (kernel `O_APPEND` off agnos; explicit SEEK_END under the lock on agnos) |

**Result-returning variants (v5.8.30):** Each `*_r` returns
`Result<T, IoError>`. The `IoError` enum has variants
`IoNotFound` (ENOENT), `IoAccessDenied` (EACCES), `IoBadFd`
(EBADF), `IoFailed` (EIO), `IoOther` (catch-all).

| Function | Signature |
|----------|-----------|
| `file_open_r` | `file_open_r(path, flags, mode) → Result<fd, IoError>` |
| `file_close_r` | `file_close_r(fd) → Result<0, IoError>` |
| `file_read_r` | `file_read_r(fd, buf, len) → Result<n, IoError>` |
| `file_write_r` | `file_write_r(fd, buf, len) → Result<n, IoError>` |
| `file_read_all_r` | `file_read_all_r(path, buf, max) → Result<n, IoError>` |
| `file_write_all_r` | `file_write_all_r(path, buf, len) → Result<n, IoError>` |

Pair the `_r` variants with the `?` operator (v5.8.29) for clean
chaining: `var fd = file_open_r(path, 0, 0)?; ...`. The legacy
int-returning fns (`file_open`, `file_close`, `file_read`,
`file_write`, `file_read_all`) remain callable as of v6.0.x.

### fmt.cyr

Formatting and printing utilities. Requires string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `fmt_int` | `fmt_int(n)` | Print decimal to stdout |
| `fmt_hex` | `fmt_hex(n)` | Print hex (no prefix) |
| `fmt_hex0x` | `fmt_hex0x(n)` | Print hex with 0x prefix |
| `fmt_bool` | `fmt_bool(b)` | Print "true" or "false" |
| `fmt_pad` | `fmt_pad(n)` | Print n spaces |
| `fmt_byte` | `fmt_byte(b)` | Print byte as 2-digit hex |
| `fmt_int_buf` | `fmt_int_buf(n, buf) → len` | Integer to buffer |
| `fmt_hex_buf` | `fmt_hex_buf(n, buf) → len` | Hex to buffer |
| `fmt_sprintf` | `fmt_sprintf(buf, fmt, args) → len` | Printf-like (%d %x %s %%) |
| `fmt_printf` | `fmt_printf(fmt, args) → len` | Format + print to stdout |

### args.cyr

CLI argument parsing via /proc/self/cmdline. Requires string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `args_init` | `args_init()` | Parse cmdline (call once) |
| `argc` | `argc() → count` | Number of arguments |
| `argv` | `argv(n) → cstr` | Get argument n (0-based) |

### fnptr.cyr

Indirect function calls via inline assembly.

| Function | Signature | Description |
|----------|-----------|-------------|
| `fncall0` … `fncall8` | `fncallN(fp, a1, …, aN) → ret` | Call a function pointer with N arguments, **N = 0 through 8** |

---

## Extended Libraries

### tagged.cyr

Tagged-union primitives + `Option` / `Either` (`Result` carved out
into its own module — see `result.cyr` below). Requires alloc.cyr,
fmt.cyr (for `option_print`). Transitively `include`s
`lib/result.cyr` so legacy callers that include only `tagged.cyr`
keep getting `Result` symbols.

| Function | Signature | Description |
|----------|-----------|-------------|
| `tagged_new` | `tagged_new(tag, value) → ptr` | Create tagged value |
| `tag` | `tag(t) → tag` | Get discriminant |
| `payload` | `payload(t) → value` | Get payload |
| `is_tag` | `is_tag(t, expected) → 0/1` | Tag-equals check |
| `None` | `None() → Option` | Create None (compiler-generated since v5.8.23) |
| `Some` | `Some(val) → Option` | Create Some(val) |
| `is_none` | `is_none(opt) → 0/1` | Check if None |
| `is_some` | `is_some(opt) → 0/1` | Check if Some |
| `unwrap` | `unwrap(opt) → val` | Get value or abort |
| `unwrap_or` | `unwrap_or(opt, fallback) → val` | Get value or fallback |
| `Left` | `Left(val) → Either` | Create Left variant |
| `Right` | `Right(val) → Either` | Create Right variant |
| `is_left` | `is_left(e) → 0/1` | Check if Left |
| `is_right` | `is_right(e) → 0/1` | Check if Right |
| `option_print` | `option_print(opt)` | Print "Some(N)" or "None" |

### result.cyr (v5.8.28)

`Result<T, E>` typed sum type plus the Result-specific helpers,
carved out of `lib/tagged.cyr` so consumers that only need
`Result` can include just this module. Tag layout matches the
v5.8.23 compiler-generated form (tag at +0, payload at +8;
`Ok = 0`, `Err = 1`). Requires alloc.cyr, fmt.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `Ok` | `Ok(val) → Result` | Create Ok(val) (compiler-generated) |
| `Err` | `Err(code) → Result` | Create Err(code) (compiler-generated) |
| `is_ok` | `is_ok(res) → 0/1` | Check if Ok |
| `is_err_result` | `is_err_result(res) → 0/1` | Check if Err |
| `result_unwrap` | `result_unwrap(res) → val` | Get value or abort with stderr message |
| `result_unwrap_or` | `result_unwrap_or(res, fb) → val` | Get value or fallback |
| `err_code_of` | `err_code_of(res) → code` | 0 if Ok, payload if Err |
| `result_print` | `result_print(res)` | Print "Ok(N)" or "Err(N)" |

The `?` propagation operator (v5.8.29 / v5.8.31) is the language-
level companion: `expr?` short-circuits the enclosing fn on `Err`
and unwraps `Ok` to the payload value. See `cyrius-guide.md` for
the operator's parse + emit shape.

### hashmap.cyr

Hash table with string keys and i64 values. FNV-1a hash, open addressing. Requires alloc.cyr + string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `map_new` | `map_new() → map` | Create empty map (cap=16) |
| `map_set` | `map_set(m, key, val)` | Set key=value (overwrites) |
| `map_get` | `map_get(m, key) → val` | Get value (0 if missing) |
| `map_has` | `map_has(m, key) → 0/1` | Check if key exists |
| `map_delete` | `map_delete(m, key) → 0/1` | Remove key |
| `map_count` | `map_count(m) → n` | Number of entries |
| `map_keys` | `map_keys(m) → vec` | All keys as vec |
| `map_print` | `map_print(m)` | Print {key: val, ...} |

### assert.cyr

Test assertions. Requires string.cyr + fmt.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `assert` | `assert(cond, name)` | Pass if cond == 1 |
| `assert_eq` | `assert_eq(a, b, name)` | Pass if a == b (shows got/expected) |
| `assert_neq` | `assert_neq(a, b, name)` | Pass if a != b |
| `assert_gt` | `assert_gt(a, b, name)` | Pass if a > b |
| `assert_summary` | `assert_summary() → fails` | Print results, return fail count |

### callback.cyr

Functional patterns via function pointers. Requires fnptr.cyr + vec.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `for_each` | `for_each(vec, &fn)` | Apply fn(item) to each |
| `vec_filter` | `vec_filter(vec, &fn) → vec` | Keep items where fn(item)==1 |
| `vec_map` | `vec_map(vec, &fn) → vec` | Transform each with fn(item) |
| `vec_fold` | `vec_fold(vec, init, &fn) → val` | Accumulate with fn(acc, item) |
| `vec_any` | `vec_any(vec, &fn) → 0/1` | True if any fn(item)==1 |
| `vec_all` | `vec_all(vec, &fn) → 0/1` | True if all fn(item)==1 |
| `vec_find_by` | `vec_find_by(vec, &fn) → item` | First match (0 if none) |
| `fork_with_pre_exec` | `fork_with_pre_exec(cmd, argv, envp, &cb, data) → pid` | Fork + callback + exec |

### bench.cyr

Benchmarking with nanosecond precision. Requires fnptr.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `bench_new` | `bench_new(name) → bench` | Create benchmark |
| `bench_start` | `bench_start(b)` | Start timer |
| `bench_stop` | `bench_stop(b) → ns` | Stop timer, return elapsed |
| `bench_run` | `bench_run(b, &fn, n)` | Run fn n times |
| `bench_avg_ns` | `bench_avg_ns(b) → ns` | Average nanoseconds |
| `bench_min_ns` | `bench_min_ns(b) → ns` | Minimum |
| `bench_max_ns` | `bench_max_ns(b) → ns` | Maximum |
| `bench_report` | `bench_report(b)` | Print formatted report |
| `bench_report_all` | `bench_report_all(vec)` | Print all benchmarks |

### bounds.cyr

Opt-in runtime bounds checking. Aborts with error message on violation.

| Function | Signature | Description |
|----------|-----------|-------------|
| `checked_load64` | `checked_load64(buf, len, idx) → val` | Bounds-checked 64-bit read |
| `checked_store64` | `checked_store64(buf, len, idx, val)` | Bounds-checked 64-bit write |
| `checked_load8` | `checked_load8(buf, len, idx) → val` | Bounds-checked byte read |
| `checked_store8` | `checked_store8(buf, len, idx, val)` | Bounds-checked byte write |
| `checked_memcpy` | `checked_memcpy(dst, dlen, src, slen, n)` | Bounds-checked copy |

### trait.cyr

Vtable-based trait objects for polymorphic dispatch. Requires fnptr.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `trait_obj_new` | `trait_obj_new(vtable, data) → obj` | Create trait object |
| `trait_call0` | `trait_call0(obj, slot) → ret` | Call method (0 extra args) |
| `trait_call1` | `trait_call1(obj, slot, arg) → ret` | Call method (1 extra arg) |
| `display` | `display(obj)` | Print via Display trait |
| `to_string` | `to_string(obj) → Str` | String via Display trait |
| `int_as_display` | `int_as_display(n) → obj` | Wrap int as Display |
| `str_as_display` | `str_as_display(s) → obj` | Wrap Str as Display |

### json.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** JSON / TOML /
> CYML / CSV / base64 / bigint / u128 now live in the `bayan` fold
> (canonical `bayan_*` names; the names below are kept as legacy
> aliases). No longer stdlib — `include "lib/bayan.cyr"`.

Minimal JSON parser and builder.

| Function | Signature | Description |
|----------|-----------|-------------|
| `json_parse` | `json_parse(str) → vec` | Parse JSON object |
| `json_get` | `json_get(pairs, key) → Str/0` | Find value by key |
| `json_get_int` | `json_get_int(pairs, key) → int` | Get as integer |
| `json_build` | `json_build(pairs) → Str` | Build JSON string |
| `json_parse_file` | `json_parse_file(path) → vec` | Parse JSON file (legacy: returns empty vec on file error) |
| `json_parse_file_r` | `json_parse_file_r(path) → Result<vec, JsonError>` | Result variant — file errors surface as `Err(JsonIoErr)` (v5.8.30) |

`enum JsonError { JsonIoErr; JsonParseErr; JsonOther; }` —
file-read failures land as `JsonIoErr`; `JsonParseErr` is reserved
for a future slot when the parser tracks structural errors.
The streaming + tagged-tree + JSON Pointer surfaces (v5.7.20–v5.7.42)
remain best-effort and don't have `_r` variants yet.

### toml.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

Minimal TOML parser for vidya-style content files.

| Function | Signature | Description |
|----------|-----------|-------------|
| `toml_parse` | `toml_parse(str) → vec` | Parse TOML string |
| `toml_parse_file` | `toml_parse_file(path) → vec` | Parse TOML file (legacy) |
| `toml_parse_file_r` | `toml_parse_file_r(path) → Result<vec, TomlError>` | Result variant (v5.8.30) |
| `toml_get` | `toml_get(pairs, key) → Str/0` | Find value by key |
| `toml_get_sections` | `toml_get_sections(secs, name) → vec` | Filter `[[section]]` by name |

`enum TomlError { TomlIoErr; TomlParseErr; TomlOther; }`.

### cyml.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

CYML parser (TOML header + markdown body) used by vidya for
content files.

| Function | Signature | Description |
|----------|-----------|-------------|
| `cyml_parse` | `cyml_parse(data, len) → CymlDoc` | Parse buffer (always returns a doc; entry_count >= 0) |
| `cyml_parse_file_r` | `cyml_parse_file_r(path) → Result<CymlDoc, CymlError>` | Open + read + parse; file errors → `Err(CymlIoErr)` (v5.8.30) |

`enum CymlError { CymlIoErr; CymlOther; }`. There's no
`cyml_parse_file` legacy fn — cyml previously required consumers
to open + read manually; v5.8.30 added the file-loading helper
in Result-returning form only.

### process.cyr

Process management with Result returns.

| Function | Signature | Description |
|----------|-----------|-------------|
| `run` | `run(cmd, a1, a2) → Result(exit)` | Run + wait |
| `run_capture` | `run_capture(cmd, a1, a2, buf, len) → Result(n)` | Capture stdout |
| `spawn` | `spawn(cmd, a1, a2) → Result(pid)` | Background run |
| `wait_pid` | `wait_pid(pid) → Result(exit)` | Wait for pid |

### fs.cyr

Filesystem: paths, directories, tree walking.

| Function | Signature | Description |
|----------|-----------|-------------|
| `path_join` | `path_join(dir, name) → Str` | Join paths |
| `path_basename` | `path_basename(path) → Str` | Last component |
| `path_dirname` | `path_dirname(path) → Str` | Directory part |
| `dir_list` | `dir_list(path) → vec` | List directory |
| `dir_walk` | `dir_walk(path, results)` | Recursive walk |
| `find_files` | `find_files(path, ext) → vec` | Find by extension |
| `is_dir` | `is_dir(path) → 0/1` | Check if directory |

### net.cyr

TCP/UDP sockets. **Already Result-returning** from a pre-cycle
migration — Err payload is the negated kernel errno (positive
int). The v5.8.30/.31 module-prefixed enum convention was NOT
applied here per honest scope-shrink at v5.8.31 entry: refactoring
would break payload-comparing consumers (lib/ws_server.cyr,
lib/sandhi.cyr).

| Function | Signature | Description |
|----------|-----------|-------------|
| `tcp_socket` / `udp_socket` | `→ Result<fd, errno>` | Create socket |
| `sock_bind` | `sock_bind(fd, addr, port) → Result<0, errno>` | Bind |
| `sock_listen` | `sock_listen(fd, backlog) → Result<0, errno>` | Listen |
| `sock_accept` | `sock_accept(fd) → Result<client_fd, errno>` | Accept |
| `sock_connect` | `sock_connect(fd, addr, port) → Result<0, errno>` | Connect |
| `sock_send` / `sock_recv` | `(fd, buf, len) → Result<n, errno>` | Send/receive |
| `sock_close` / `sock_shutdown` | `(fd, [how]) → int` | Bare int — no Err variant since failure on a valid fd is essentially impossible |

### http.cyr

Minimal HTTP/1.0 client.

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `http_get(url) → resp_ptr` | GET request — back-compat shape; failure → resp with `status == HTTP_ERROR` (-1) |
| `http_get_r` | `http_get_r(url) → Result<resp_ptr, HttpError>` | Result variant (v5.8.31). Bad URL → `Err(HttpBadUrl)`; net failure → `Err(HttpNetErr)`; 200-299 → `Ok(resp)`; non-2xx → `Err(HttpNon2xx)` |
| `http_status` / `http_body` / `http_body_len` | `(resp) → field` | Response accessors |

`enum HttpError { HttpBadUrl; HttpNetErr; HttpNon2xx; HttpOther; }`.

Note: `http_get` shipped with a long-standing latent bug
(treated net.cyr Result heap pointers as raw int fds) that was
fixed alongside the `http_get_r` addition at v5.8.31.

### dynlib.cyr

Pure-cyrius ELF shared-object loader (no libc, no dlopen).

| Function | Signature | Description |
|----------|-----------|-------------|
| `dynlib_open` | `dynlib_open(path) → handle/0` | Open + parse + relocate |
| `dynlib_open_r` | `dynlib_open_r(path) → Result<handle, DynlibError>` | Result variant (v5.8.31) — distinguishes `DynlibNotFound` (open failed) from `DynlibBadElf` (open ok, parse failed) |
| `dynlib_sym` | `dynlib_sym(handle, name) → addr/0` | Symbol lookup (GNU hash if available, else linear scan) |
| `dynlib_sym_r` | `dynlib_sym_r(handle, name) → Result<addr, DynlibError>` | Result variant; null handle → `Err(DynlibNotFound)`, missing symbol → `Err(DynlibSymMissing)` |
| `dynlib_close` | `dynlib_close(handle) → 0` | Unmap |

`enum DynlibError { DynlibNotFound; DynlibBadElf; DynlibSymMissing; DynlibOther; }`.

### regex.cyr

Glob matching, string search/replace, **and** a Thompson-NFA / Pike regex
engine (v5.7.18). `private`-by-default since v6.5.0: 41 of its 52 fns are
`_re_*` implementation detail and calling one from outside the file is now a
diagnostic. The 11 `public` fns below are the whole API surface.
(`lib/niyama.cyr` is the separate 5-engine regex fold — see
[ecosystem.md](ecosystem.md); this module is the stdlib primitive.)

**Glob + search/replace:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `glob_match` | `glob_match(pattern, text) → 0/1` | Glob (`*` and `?`) against a C string |
| `str_glob` | `str_glob(s, pattern) → 0/1` | Same, taking a `Str` |
| `find_all` | `find_all(haystack, needle) → vec` | All occurrences |
| `str_replace` | `str_replace(s, old, new) → Str` | Replace first |
| `str_replace_all` | `str_replace_all(s, old, new) → Str` | Replace all |

**Regex engine:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `regex_compile` | `regex_compile(pat) → nfa/0` | Compile a null-terminated pattern to an opaque heap NFA; 0 on syntax error |
| `regex_match` | `regex_match(nfa, s) → 0/1` | Anchored at position 0 |
| `regex_search` | `regex_search(nfa, s) → start/-1` | First match anywhere |
| `regex_search_at` | `regex_search_at(nfa, s, len, from) → start/-1` | As `regex_search`, starting at `from` |
| `regex_group_start` | `regex_group_start(nfa, n) → off/-1` | Capture-group `n` start (group 0 = whole match; `n` 0–9) |
| `regex_group_end` | `regex_group_end(nfa, n) → off/-1` | Capture-group `n` end |

---

## System Libraries

### syscalls.cyr

The single public include point for syscalls; it delegates to a per-target peer
(`syscalls_x86_64_linux` / `syscalls_aarch64_linux` / `syscalls_macos` /
`syscalls_windows` / `syscalls_x86_64_agnos`, the last two **standalone**) plus
the shared `syscalls_linux_common`. Never include a peer directly. On x86_64
Linux that resolves to **96 `SYS_*` number constants + 84 `sys_*` wrappers**
(23 in the x86_64 peer, 61 in linux_common).

See [agnosys documentation](guides/cyrius-guide.md#agnos-system-libraries) for full API.

Key functions: `sys_open`, `sys_close`, `sys_read`, `sys_write`, `sys_fork`, `sys_execve`, `sys_pipe`, `sys_waitpid`, `sys_kill`, `sys_mount`, `sys_mkdir`, `sys_rmdir`, `sys_chdir` (v6.5.7), `sys_sigprocmask`, `sys_signalfd`, `sys_epoll_create`, `sys_epoll_ctl`, `sys_epoll_wait`, `sys_timerfd_create`, `sys_fchownat`.

Helper functions: `sigset_new`, `sigset_add`, `sigset_has`, `epoll_event_new`, `timerspec_new`, `WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED`, `WTERMSIG`, `is_err`, `err_code`.

Signal disposition (defined in `syscalls.cyr` itself, per-target routed inside
one fn so the `#ifdef`-blind static checker sees a single definition):

| Function | Signature | Description |
|----------|-----------|-------------|
| `signal_ignore` | `signal_ignore(signum) → 0/-errno` | Set the disposition to `SIG_IGN` |
| `signal_default` | `signal_default(signum) → 0/-errno` | v6.5.7 — set it back to `SIG_DFL`. **Not optional alongside `signal_ignore`**: `SIG_IGN` is *inherited across `execve`* (a handler is reset, an ignore is not), so a process that ignores a signal then fork+execve's a child hands that child a disposition its own code never chose. Call it in the child between fork and execve |

**agnos-only additions (`lib/syscalls_x86_64_agnos.cyr`, v6.5.9)** — the agnos
peer is standalone, so these exist on no other target:

| Function | Signature | Description |
|----------|-----------|-------------|
| `sys_chan_endow` | `sys_chan_endow(fd) → child_fd / -CH_E_*` | Arm a channel endpoint for placement into the next `sys_spawn_path*` child. ⚠ The return is an **fd**, not a status — the parent must announce it to the child itself (canonically `AGNOS_CHAN=<fd>` in the env blob) |
| `sys_spawn_path_env` | `sys_spawn_path_env(path, len, env, envlen) → pid` | `sys_spawn_path` (non-blocking from-disk spawn, returns the pid immediately) with a per-process env blob (packed `KEY=VALUE\0…`, ≤1024 B, ≤16 entries). ⛔ The kernel treats a mis-shaped `env`/`envlen` as *fall back to the default environment*, **never** as an error — a bad call degrades silently, which is why this is a named wrapper rather than a raw 4-arg `syscall()` |

## Identity & Authentication

Pure-cyrius parsers for `/etc/passwd`, `/etc/group`, `/etc/shadow` that bypass glibc NSS entirely — same architectural stance musl libc takes. Added in v5.5.26 (pwd/grp) and v5.5.27 (shadow/pam) as the landing for the NSS-dispatch work that the v5.5.23-25 arc proved was not tractable through glibc's dlopen surface. See `docs/development/issues/archived/dynlib-nss-bootstrap.md` for the full why.

### pwd.cyr (v5.5.26)

`/etc/passwd` reader. Caller protocol: 56 B `pwrec` (uid, gid, name ptr, passwd ptr, gecos ptr, dir ptr, shell ptr) + a `strbuf` scratch for the string fields.

| Function | Signature | Description |
|----------|-----------|-------------|
| `pwd_getpwuid` | `(uid, pwrec, strbuf, strbufsz) → 1/0/-1/-2` | Look up by uid (legacy int-return) |
| `pwd_getpwnam` | `(name, pwrec, strbuf, strbufsz) → 1/0/-1/-2` | Look up by name (legacy) |
| `pwd_getpwuid_r` | `(uid, pwrec, strbuf, strbufsz) → Result<0, PwdError>` | Result variant (v5.8.31) |
| `pwd_getpwnam_r` | `(name, pwrec, strbuf, strbufsz) → Result<0, PwdError>` | Result variant (v5.8.31) |
| `pwd_invalidate_cache` | `() → 0` | Force re-read on next call |
| `pwd_uid` / `pwd_gid` / `pwd_name` / `pwd_passwd` / `pwd_gecos` / `pwd_dir` / `pwd_shell` | `(pwrec) → value` | Accessors |

Legacy returns: `1` = found, `0` = not found, `-1` = `/etc/passwd`
unreadable, `-2` = strbuf too small.

`enum PwdError { PwdNotFound; PwdLoadFailed; PwdBufTooSmall; PwdOther; }`.
`_r` variants map `1`→`Ok(0)`, `0`→`Err(PwdNotFound)`,
`-1`→`Err(PwdLoadFailed)`, `-2`→`Err(PwdBufTooSmall)`.

### grp.cyr (v5.5.26)

`/etc/group` reader with `getgrouplist` semantics matching glibc (primary gid prepended, supplementary gids appended for every group that lists `user` as a member).

| Function | Signature | Description |
|----------|-----------|-------------|
| `grp_getgrgid` | `(gid, grrec, strbuf, strbufsz) → 1/0/-1/-2` | Look up by gid (legacy) |
| `grp_getgrnam` | `(name, grrec, strbuf, strbufsz) → 1/0/-1/-2` | Look up by name (legacy) |
| `grp_getgrouplist` | `(user, primary_gid, gid_buf, max) → count / -1 / -2` | All gids for user (legacy) |
| `grp_getgrgid_r` / `grp_getgrnam_r` | `(...) → Result<0, GrpError>` | Result variants (v5.8.31) |
| `grp_getgrouplist_r` | `(user, primary_gid, gid_buf, max) → Result<count, GrpError>` | Result variant (v5.8.31) |
| `grp_invalidate_cache` | `() → 0` | Force re-read on next call |
| `grp_gid` / `grp_name` / `grp_passwd` | `(grrec) → value` | Accessors |

24 B `grrec`.
`enum GrpError { GrpNotFound; GrpLoadFailed; GrpBufTooSmall; GrpOther; }`.
`grp_getgrouplist_r` collapses the legacy `-(n+2)` overflow encoding
to `Err(GrpBufTooSmall)`; callers needing the would-have-been count
fall back to the int-returning fn.

### shadow.cyr (v5.5.27)

`/etc/shadow` reader. On a normal Linux system the file is mode `0600 root:root`; non-root callers get `rc=-1` (EACCES). For non-root authentication, use `lib/pam.cyr` below — same path `pam_unix.so` itself takes from unprivileged processes.

| Function | Signature | Description |
|----------|-----------|-------------|
| `shadow_getspnam` | `(name, sprec, strbuf, strbufsz) → 1/0/-1/-2` | Look up by username (legacy) |
| `shadow_getspnam_r` | `(name, sprec, strbuf, strbufsz) → Result<0, ShadowError>` | Result variant (v5.8.31) |
| `shadow_invalidate_cache` | `() → 0` | Force re-read on next call |
| `shadow_name` / `shadow_hash` / `shadow_last_change` | `(sprec) → value` | Accessors |

24 B `sprec` (name, hash, last_change). The hash is the full crypt(3)
encoding (`$6$salt$hash` / `$5$salt$hash` / `*` / `!`).
`enum ShadowError { ShadowNotFound; ShadowLoadFailed; ShadowBufTooSmall; ShadowOther; }`.
`ShadowLoadFailed` typically signals "no read access to /etc/shadow"
(caller is non-root); use `pam_unix_authenticate` (below) for the
non-root authentication path.

### pam.cyr (v5.5.27)

Non-root password verification via the setuid-root `unix_chkpwd` helper that Linux-PAM ships for exactly this purpose. Forks the helper, pipes the password to its stdin, returns based on its exit code. Works against any NSS backend the system is configured for (`files`, LDAP, SSSD, …) — `unix_chkpwd` does a normal glibc lookup inside its setuid environment.

| Function | Signature | Description |
|----------|-----------|-------------|
| `pam_unix_available` | `() → 0/1` | `1` if `/usr/sbin/unix_chkpwd` or `/usr/bin/unix_chkpwd` is present |
| `pam_unix_authenticate` | `(user, password) → PAM_AUTH_*` | Verify `password` for `user` (legacy int-return) |
| `pam_unix_authenticate_r` | `(user, password) → Result<0, PamError>` | Result variant (v5.8.31) |

Legacy return constants:

| Constant | Value | Meaning |
|----------|-------|---------|
| `PAM_AUTH_OK` | `0` | Password verified |
| `PAM_AUTH_FAIL` | `1` | Rejected (wrong password, locked, disabled) |
| `PAM_AUTH_HELPER_MISSING` | `-2` | `unix_chkpwd` not on system |
| `PAM_AUTH_PIPE_FAILED` | `-3` | `sys_pipe` errored |
| `PAM_AUTH_FORK_FAILED` | `-4` | `sys_fork` errored |
| `PAM_AUTH_EXEC_FAILED` | `-5` | Helper present but couldn't run |

`enum PamError { PamAuthFail; PamHelperMissing; PamPipeFailed; PamForkFailed; PamExecFailed; PamOther; }`.
`pam_unix_authenticate_r` maps `PAM_AUTH_OK`→`Ok(0)` and every
non-zero code to its corresponding variant. `pam_unix_available`
stays bool-returning — no Err semantics needed.

An inline cyrius SHA-512-crypt implementation (for root consumers that want to skip the subprocess fork) was considered for v5.5.27 but deferred — Drepper's algorithm is ~120 LoC of error-prone interleaved hashing, and `unix_chkpwd` is ~1 ms and covers every crypt type the system supports automatically. Can land as a future patch if a zero-fork consumer needs it.

### random.cyr (v5.7.35)

Kernel-entropy source via `getrandom(2)`. Linux 3.17+, available on
both x86_64 (syscall 318) and aarch64 (syscall 278). agnosys-surfaced
when its drm/luks/security work needed a libc-free entropy path.

| Function | Signature | Description |
|----------|-----------|-------------|
| `random_bytes` | `random_bytes(buf, len) → bytes_written` | Fill `buf` with `len` bytes; loops on short reads (getrandom returns short for >256-byte requests) |

Plus the `GrndFlag` enum:

| Constant | Value | Meaning |
|----------|-------|---------|
| `GRND_NONBLOCK` | `0x0001` | Non-blocking; `EAGAIN` if pool not yet initialized |
| `GRND_RANDOM` | `0x0002` | Use `/dev/random` pool (vs the default `/dev/urandom` semantics) |
| `GRND_INSECURE` | `0x0004` | Allow uninitialized pool — only for non-cryptographic uses (Linux 5.6+) |

### security.cyr (v5.7.35)

Landlock policy constants. Stdlib exposes constants only — the
`landlock_ruleset_attr` struct drifts upstream (handled_access_net
added 6.7, scoped added 6.10), so consumers declare their own
struct shape and call `sys_landlock_create_ruleset` /
`sys_landlock_add_rule` / `sys_landlock_restrict_self` directly
from `lib/syscalls.cyr`.

`LandlockAccessFs` (13 flags from the 5.13 surface):

| Flag | Bit | Use |
|------|-----|-----|
| `LANDLOCK_ACCESS_FS_EXECUTE` | `1<<0` | Execute file |
| `LANDLOCK_ACCESS_FS_WRITE_FILE` | `1<<1` | Open for write |
| `LANDLOCK_ACCESS_FS_READ_FILE` | `1<<2` | Open for read |
| `LANDLOCK_ACCESS_FS_READ_DIR` | `1<<3` | Open dir |
| `LANDLOCK_ACCESS_FS_REMOVE_DIR` | `1<<4` | rmdir |
| `LANDLOCK_ACCESS_FS_REMOVE_FILE` | `1<<5` | unlink |
| `LANDLOCK_ACCESS_FS_MAKE_*` | `1<<6` … `1<<12` | mknod char/dir/reg/sock/fifo/block/sym |

`LandlockRuleType.PATH_BENEATH = 1` for path-tree rules (the
sole rule type in 5.13).

---

## Concurrency

OS threads, atomics, async runtime, and portable locks.

### thread.cyr

OS thread creation and synchronization using clone/futex on Linux (v6.0.53: Windows threads are routed to lib/thread_win.cyr). Each thread gets its own stack via mmap and 4KB TLS block installed by the kernel at clone time.

| Function | Signature | Description |
|----------|-----------|-------------|
| `thread_create` | `thread_create(fp, arg) → ptr` | Create and spawn a thread running `fn(arg)`; returns thread struct pointer or 0 on failure |
| `thread_create_detached` | `thread_create_detached(fp, arg) → 1/0` | v6.5.8 — spawn a thread nobody joins; the child releases its own stack + TLS on exit. **Returns a boolean, not a handle, deliberately** — a handle would invite `thread_join`, whose `munmap_stack` would double-unmap a range the child already released. Fixes the leak that degraded a thread-per-request server to `thread_create` returning 0 after ~65 K spawns (`vm.max_map_count`) |
| `thread_join` | `thread_join(t) → 0/-1` | Block until thread completes; frees its stack |
| `thread_is_done` | `thread_is_done(t) → 1/0/-1` | v6.5.8 — non-blocking "has it finished?" on a `thread_create` handle (-1 if null). Enables the reaper shape — poll while running, join once it returns 1. ⛔ **Valid only BEFORE `thread_join`**: join consumes the handle (on Windows it `CloseHandle`s it), so a post-join query inspects a closed handle and reports "not done". A detached thread has no handle by design |
| `gettid` | `gettid() → i64` | Get current thread ID |
| `mmap_stack` | `mmap_stack(size) → ptr` | Allocate thread stack via mmap (returns base or MAP_FAILED) |
| `munmap_stack` | `munmap_stack(addr, size) → 0/-errno` | Free thread stack via munmap |
| `mutex_new` | `mutex_new() → ptr` | Create a futex-based mutex (0=unlocked) |
| `mutex_lock` | `mutex_lock(m) → 0` | Acquire mutex; blocks via futex when contended (acquire barrier) |
| `mutex_unlock` | `mutex_unlock(m) → 0` | Release mutex; wakes one waiter (release barrier) |
| `chan_new` | `chan_new(cap) → ptr` | Create bounded MPSC channel with capacity cap |
| `chan_send` | `chan_send(ch, val) → 0/-1` | Send value to channel (blocks if full; returns -1 if closed) |
| `chan_recv` | `chan_recv(ch) → val` | Receive from channel (blocks if empty; returns 0 if closed) |
| `chan_try_recv` | `chan_try_recv(ch) → val/0` | Non-blocking receive (returns 0 if empty or closed) |
| `chan_close` | `chan_close(ch) → 0` | Close channel; wakes all blocked receivers |

⚠ `chan_*` here is the **in-process MPSC thread channel**. agnos's kernel
channel syscalls (`#97 chan_op`, minted v6.5.8) are deliberately named
`sys_chan_*` — reusing `chan_send`/`chan_recv`/`chan_close` would have let
last-definition-wins silently replace the MPSC channel on agnos only.

### thread_local.cyr (v6.0.61)

Per-thread slot storage (TLS) via CPU thread-pointer register (`%fs` on x86_64, `TPIDR_EL0` on aarch64). Provides 16 slots × 8 bytes per thread. On Windows uses Win32 TlsAlloc/TlsGetValue/TlsSetValue; on macOS uses process-global array (threads not supported); on Linux/aarch64 uses CPU register.

| Function | Signature | Description |
|----------|-----------|-------------|
| `thread_local_init` | `thread_local_init() → 1/0` | Install per-thread TLS block (worker threads installed automatically by kernel); returns 1 on success |
| `thread_local_get` | `thread_local_get(slot) → i64` | Read value from slot (0 on fresh slots) |
| `thread_local_set` | `thread_local_set(slot, val) → 0` | Write value to slot |

### atomic.cyr

Atomic memory primitives for concurrent code. Provides race-safe 8-byte load-modify-write and memory-ordering operations. Uses `lock cmpxchg`/`lock xadd`/`mfence` on x86_64; LL-SC loops + `dmb ish` on aarch64.

| Function | Signature | Description |
|----------|-----------|-------------|
| `atomic_load` | `atomic_load(ptr) → i64` | Atomic 8-byte load (aligned i64 loads are atomic on both arches) |
| `atomic_store` | `atomic_store(ptr, val) → 0` | Atomic 8-byte store |
| `atomic_cas` | `atomic_cas(ptr, expected, new) → 1/0` | Compare-and-swap; returns 1 if swapped, 0 if not (full memory barrier) |
| `atomic_fetch_add` | `atomic_fetch_add(ptr, delta) → old` | Atomic increment; returns old value (pre-add; full memory barrier) |
| `atomic_fence` | `atomic_fence() → 0` | Full memory barrier (`mfence` on x86; `dmb ish` on aarch64) |

### sync.cyr (v6.1.16)

Portable process-internal mutex with acquire/release memory ordering. Linux
x86_64/aarch64 use a **three-state** futex lock (v6.5.9 — Drepper "Futexes Are
Tricky", Mutex Take 3: `0` free / `1` held-no-waiters / `2` held-waiters-may-be-parked);
Windows uses SRWLOCK; macOS uses an atomic_cas spinlock (no routed blocking
futex / `__ulock` primitive, so it **spins** — correct for short, low-contention
sections). Requires atomic.cyr + alloc.cyr. No `trylock`: SRWLOCK has no routed
TryAcquire, so the surface stays to what every backend supports.

| Function | Signature | Description |
|----------|-----------|-------------|
| `mutex_new` | `mutex_new() → ptr` | Create mutex (8-byte cell = `MUTEX_SIZE`, 0=unlocked) |
| `mutex_lock` | `mutex_lock(m) → 0` | Acquire (blocking; acquire barrier). Uncontended = one CAS, no syscall |
| `mutex_unlock` | `mutex_unlock(m) → 0` | Release (release barrier). Syscalls **only** when the cell says a waiter may be parked |

The third state is what removes the syscall from the uncontended release path:
an uncontended lock/unlock pair went **392 ns → 48 ns** (against ~7 ns for a bare
`atomic_cas`), and that tax compounded through every lock-guarded structure in
the stdlib.

### async.cyr

Cooperative async runtime with epoll event loop. Tasks are function pointers scheduled to run to completion or yield; supports timers (via timerfd) and I/O readiness (via epoll). Includes cancellation tokens (v5.11.15) for cooperative cancellation via atomic load/store.

| Function | Signature | Description |
|----------|-----------|-------------|
| `async_new` | `async_new() → rt` | Create new async runtime (epoll-based) |
| `async_spawn` | `async_spawn(rt, fp, arg) → task` | Schedule task on runtime (function pointer + argument) |
| `async_run` | `async_run(rt) → 0` | Run all spawned tasks to completion; blocks until done |
| `async_sleep_ms` | `async_sleep_ms(ms) → 0/-1` | Sleep for ms milliseconds (via timerfd + epoll) |
| `async_read` | `async_read(fd, buf, len) → n` | Non-blocking read via fcntl O_NONBLOCK |
| `async_await_readable` | `async_await_readable(fd) → 0` | Block until fd readable via epoll |
| `async_timeout` | `async_timeout(fp, arg, ms) → result/-1` | Run function with timeout (ms); uses fork/pipe/epoll |
| `cancel_token_new` | `cancel_token_new() → tok` | Create cancellation token (0 = live) |
| `cancel_token_signal` | `cancel_token_signal(tok) → 0/-1` | Signal cancellation (atomic_store) |
| `cancel_token_check` | `cancel_token_check(tok) → 1/0` | Check if cancelled (atomic_load; 1 = cancelled) |

### freelist.cyr (v6.0.75)

Segregated free-list allocator with individual free (v6.0.52: explicit mmap.cyr include). Allocations rounded to size classes (16, 32, 64, 128, 256, 512, 1024, 2048, 4096 bytes); each class has a singly-linked free list. Large allocations (>4096) go directly to mmap/munmap. 16-byte header per block (next_free, size_class); returned pointer skips header.

| Function | Signature | Description |
|----------|-----------|-------------|
| `fl_init` | `fl_init() → 0` | Initialize freelist allocator (idempotent) |
| `fl_alloc` | `fl_alloc(size) → ptr` | Allocate size bytes (rounded to class or mmap'd if >4096) |
| `fl_free` | `fl_free(ptr) → 0` | Free pointer returned by fl_alloc (chains onto class free list) |
| `fl_calloc` | `fl_calloc(size) → ptr` | Allocate and zero-fill size bytes |


## Math & SIMD

Scalar f64 math, SIMD vector types, matrices/linear algebra, and big numbers.

### math.cyr

Scalar f64 primitives that stayed in the stdlib after the v6.1.26 **ganita
carve**: the `F64_*` bit-pattern constants, comparison / rounding / clamping
ops, integer gcd+lcm, the private `f64`-builtin polyfills (exp / ln / log2 /
exp2 / sin / cos / atan cores), and f64 parsing. All values are f64 **bit
patterns** carried in i64.

| Function | Signature | Description |
|----------|-----------|-------------|
| `f64_clamp` | `f64_clamp(x, lo, hi) → i64` | Clamp x to [lo, hi] |
| `f64_min` | `f64_min(a, b) → i64` | Minimum of two f64 values |
| `f64_max` | `f64_max(a, b) → i64` | Maximum of two f64 values |
| `f64_le` | `f64_le(a, b) → i64` | Less-than-or-equal (NaN-safe) |
| `f64_ge` | `f64_ge(a, b) → i64` | Greater-than-or-equal (NaN-safe) |
| `f64_lerp` | `f64_lerp(a, b, t) → i64` | Linear interpolation |
| `f64_sign` | `f64_sign(x) → i64` | Sign: -1.0, 0.0, or 1.0 |
| `f64_trunc` | `f64_trunc(x) → i64` | Truncate toward zero |
| `f64_fract` | `f64_fract(x) → i64` | Fractional part |
| `gcd` | `gcd(a, b) → i64` | Greatest common divisor |
| `lcm` | `lcm(a, b) → i64` | Least common multiple |
| `f64_parse` | `f64_parse(s) → i64` | Parse null-terminated string to f64 |
| `f64_parse_ok` | `f64_parse_ok(s, out) → i64` | Parse with success flag |

Constants include `F64_ONE` / `F64_TWO` / `F64_HALF` / `F64_PI` (+ `PI_2`,
`PI_4`, `PI_6`, `2_PI`) / `F64_TAU` / `F64_E` / `F64_LN2` / `F64_LN10` /
`F64_LOG2E` / `F64_SQRT2` / `F64_FRAC_1_SQRT2`, plus the Dekker
double-double reduction constants used by the large-argument trig path.

> ⛔ **Carved out — no longer in `lib/math.cyr`.** The transcendental,
> hyperbolic, power and combinatorial fns moved into `lib/ganita.cyr` at
> ganita 1.0.0 / **v6.1.26** and are reachable only via
> `include "lib/ganita.cyr"` (canonical `ganita_*`, with the legacy names
> below retained as aliases):
> `f64_sinh`, `f64_cosh`, `f64_tanh`, `f64_asinh`, `f64_acosh`, `f64_atanh`,
> `f64_asin`, `f64_acos`, `f64_atan2`, `f64_pow`, `f64_hypot`, `fibonacci`,
> `binomial`.
> This section listed all thirteen as `math.cyr` surface for four minors after
> the carve; they were verified out of `lib/math.cyr` and into `lib/ganita.cyr`
> on 2026-08-07.

### simd.cyr

Typed SIMD wrappers over the compiler's packed-vector builtins. **SIMD Phase 5 is complete (v6.4.32): every verb runs on all four backends** — x86 (SSE + AVX2), aarch64 NEON, Windows PE (value-form params + returns, v6.4.31), and cx bytecode (per-lane scalar loops, v6.4.32). Each operation has a value-form (non-PE targets, plus PE since v6.4.31) and a pointer-form (universal) variant; the parser auto-routes `&x` calls to the `_ptr` siblings.

The surface spans four vector families plus flat-array packed verbs:

- **f64v2 (2-lane) / f64v4 (4-lane)** — the double-precision vectors detailed in the table below.
- **f32v4 (4-lane) / f32v8 (8-lane, 256-bit AVX2 on x86)** — single-precision `make`/`splat`/`lane`/`add`/`sub`/`mul`/`fmadd`/`dot`. On aarch64, f32v8 routes through native f32v4 NEON (native 256-bit is x86-AVX2-only).
- **integer vectors** — `i8v16`/`i16v8`/`i32v4`/`i64v2` (+ unsigned) with `iv_add`/`iv_sub`/`iv_mul` (mul is i16/i32 only) and `iv_dp8` (u8·i8→i32 widening int8 dot, the BitNet inner loop).
- **flat-array packed verbs** — `f32v_*`/`f64v_*`/`iv_*` over `(&dst, &a, &b, n)` pointer+count arguments: `add`/`sub`/`mul`/`div`/`sqrt`/`abs`/`fmadd`/`dot`/`scale`/`axpy`. These are the portable form that runs identically on every backend (the cx bytecode oracle lowers them to per-lane scalar loops).

| Function | Signature | Description |
|----------|-----------|-------------|
| `f64v2_make` | `f64v2_make(lo, hi) → f64v2` | Create f64v2 from two i64 bit patterns |
| `f64v2_lo` | `f64v2_lo(v) → i64` | Extract low lane |
| `f64v2_lo_ptr` | `f64v2_lo_ptr(p) → i64` | Extract low lane (pointer form) |
| `f64v2_hi` | `f64v2_hi(v) → i64` | Extract high lane |
| `f64v2_hi_ptr` | `f64v2_hi_ptr(p) → i64` | Extract high lane (pointer form) |
| `f64v2_add` | `f64v2_add(a, b) → f64v2` | Packed-double addition |
| `f64v2_add_ptr` | `f64v2_add_ptr(a, b) → f64v2` | Packed-double add (pointer form) |
| `f64v2_sub` | `f64v2_sub(a, b) → f64v2` | Packed-double subtraction |
| `f64v2_sub_ptr` | `f64v2_sub_ptr(a, b) → f64v2` | Packed-double subtract (pointer form) |
| `f64v2_mul` | `f64v2_mul(a, b) → f64v2` | Packed-double multiply |
| `f64v2_mul_ptr` | `f64v2_mul_ptr(a, b) → f64v2` | Packed-double multiply (pointer form) |
| `f64v2_div` | `f64v2_div(a, b) → f64v2` | Packed-double divide |
| `f64v2_div_ptr` | `f64v2_div_ptr(a, b) → f64v2` | Packed-double divide (pointer form) |
| `f64v2_fmadd` | `f64v2_fmadd(a, b, c) → f64v2` | Fused multiply-add (a*b+c) |
| `f64v2_fmadd_ptr` | `f64v2_fmadd_ptr(a, b, c) → f64v2` | Fused multiply-add (pointer form) |
| `f64v2_dot` | `f64v2_dot(a, b) → i64` | Dot product |
| `f64v2_dot_ptr` | `f64v2_dot_ptr(a, b) → i64` | Dot product (pointer form) |
| `f64v2_scale` | `f64v2_scale(a, s) → f64v2` | Scalar multiply |
| `f64v2_scale_ptr` | `f64v2_scale_ptr(a, s) → f64v2` | Scalar multiply (pointer form) |
| `f64v2_abs` | `f64v2_abs(a) → f64v2` | Absolute value per lane |
| `f64v2_abs_ptr` | `f64v2_abs_ptr(a) → f64v2` | Absolute value (pointer form) |
| `f64v2_sqrt` | `f64v2_sqrt(a) → f64v2` | Square root per lane |
| `f64v2_sqrt_ptr` | `f64v2_sqrt_ptr(a) → f64v2` | Square root (pointer form) |
| `f64v4_make` | `f64v4_make(b0, b1, b2, b3) → f64v4` | Create f64v4 from four i64 bit patterns |
| `f64v4_lane0` | `f64v4_lane0(v) → i64` | Extract lane 0 |
| `f64v4_lane0_ptr` | `f64v4_lane0_ptr(p) → i64` | Extract lane 0 (pointer form) |
| `f64v4_lane1` | `f64v4_lane1(v) → i64` | Extract lane 1 |
| `f64v4_lane1_ptr` | `f64v4_lane1_ptr(p) → i64` | Extract lane 1 (pointer form) |
| `f64v4_lane2` | `f64v4_lane2(v) → i64` | Extract lane 2 |
| `f64v4_lane2_ptr` | `f64v4_lane2_ptr(p) → i64` | Extract lane 2 (pointer form) |
| `f64v4_lane3` | `f64v4_lane3(v) → i64` | Extract lane 3 |
| `f64v4_lane3_ptr` | `f64v4_lane3_ptr(p) → i64` | Extract lane 3 (pointer form) |
| `f64v4_add` | `f64v4_add(a, b) → f64v4` | 4-lane packed-double add |
| `f64v4_add_ptr` | `f64v4_add_ptr(a, b) → f64v4` | 4-lane add (pointer form) |
| `f64v4_sub` | `f64v4_sub(a, b) → f64v4` | 4-lane packed-double subtract |
| `f64v4_sub_ptr` | `f64v4_sub_ptr(a, b) → f64v4` | 4-lane subtract (pointer form) |
| `f64v4_mul` | `f64v4_mul(a, b) → f64v4` | 4-lane packed-double multiply |
| `f64v4_mul_ptr` | `f64v4_mul_ptr(a, b) → f64v4` | 4-lane multiply (pointer form) |
| `f64v4_div` | `f64v4_div(a, b) → f64v4` | 4-lane packed-double divide |
| `f64v4_div_ptr` | `f64v4_div_ptr(a, b) → f64v4` | 4-lane divide (pointer form) |
| `f64v4_fmadd` | `f64v4_fmadd(a, b, c) → f64v4` | 4-lane fused multiply-add |
| `f64v4_fmadd_ptr` | `f64v4_fmadd_ptr(a, b, c) → f64v4` | 4-lane FMA (pointer form) |
| `f64v4_dot` | `f64v4_dot(a, b) → i64` | 4-lane dot product |
| `f64v4_dot_ptr` | `f64v4_dot_ptr(a, b) → i64` | 4-lane dot product (pointer form) |
| `f64v4_scale` | `f64v4_scale(a, s) → f64v4` | 4-lane scalar multiply |
| `f64v4_scale_ptr` | `f64v4_scale_ptr(a, s) → f64v4` | 4-lane scalar multiply (pointer form) |
| `f64v4_abs` | `f64v4_abs(a) → f64v4` | 4-lane absolute value |
| `f64v4_abs_ptr` | `f64v4_abs_ptr(a) → f64v4` | 4-lane absolute value (pointer form) |
| `f64v4_sqrt` | `f64v4_sqrt(a) → f64v4` | 4-lane square root |
| `f64v4_sqrt_ptr` | `f64v4_sqrt_ptr(a) → f64v4` | 4-lane square root (pointer form) |

### matrix.cyr

> **Carved into `lib/ganita.cyr` (ganita 1.0.0, v6.1.26).** Matrix +
> linear-algebra now live in the `ganita` fold (canonical `ganita_*`
> names; the `mat_*` names below are kept as legacy aliases). No longer
> stdlib — `include "lib/ganita.cyr"`.

Row-major dense matrix operations on f64 values (stored as i64 bit patterns). Requires alloc.cyr, fmt.cyr, string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `mat_new` | `mat_new(rows, cols) → i64` | Create zero-filled rows×cols matrix |
| `mat_rows` | `mat_rows(m) → i64` | Get number of rows |
| `mat_cols` | `mat_cols(m) → i64` | Get number of columns |
| `mat_get` | `mat_get(m, r, c) → i64` | Get element at (row, col) |
| `mat_set` | `mat_set(m, r, c, val)` | Set element at (row, col) |
| `mat_identity` | `mat_identity(n) → i64` | Create n×n identity matrix |
| `mat_from` | `mat_from(rows, cols, data) → i64` | Create matrix from flat array |
| `mat_add` | `mat_add(a, b) → i64` | Matrix addition (returns new) |
| `mat_sub` | `mat_sub(a, b) → i64` | Matrix subtraction (returns new) |
| `mat_scale` | `mat_scale(a, scalar) → i64` | Scalar multiply (returns new) |
| `mat_mul` | `mat_mul(a, b) → i64` | Matrix multiply (a is m×k, b is k×n) |
| `mat_transpose` | `mat_transpose(a) → i64` | Transpose matrix |
| `mat_dot` | `mat_dot(a, b, n) → i64` | Dot product of two n-element arrays |
| `mat_print` | `mat_print(m)` | Print matrix to stdout |

### linalg.cyr

> **Carved into `lib/ganita.cyr` (ganita 1.0.0, v6.1.26)** alongside
> `matrix.cyr`. No longer stdlib — `include "lib/ganita.cyr"` (legacy
> `mat_*` aliases retained).

Dense linear algebra on f64 matrices. Decompositions (LU, Cholesky, QR, SVD, eigendecomposition), solvers, and factorization utilities. Requires alloc.cyr, math.cyr, matrix.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `mat_copy` | `mat_copy(m) → i64` | Deep copy matrix |
| `mat_neg` | `mat_neg(m) → i64` | Negate all elements |
| `mat_row` | `mat_row(m, r) → i64` | Extract row as flat array |
| `mat_col` | `mat_col(m, c) → i64` | Extract column as flat array |
| `mat_set_row` | `mat_set_row(m, r, data)` | Overwrite row from array |
| `mat_set_col` | `mat_set_col(m, c, data)` | Overwrite column from array |
| `mat_submatrix` | `mat_submatrix(m, r0, c0, r1, c1) → i64` | Extract submatrix [r0..r1, c0..c1) |
| `mat_frobenius` | `mat_frobenius(m) → i64` | Frobenius norm |
| `mat_max_norm` | `mat_max_norm(m) → i64` | Infinity norm (max abs row sum) |
| `mat_is_symmetric` | `mat_is_symmetric(m, tol) → 0/1` | Symmetry check within tolerance |
| `mat_eq` | `mat_eq(a, b, tol) → 0/1` | Element-wise equality within tolerance |
| `mat_trace` | `mat_trace(m) → i64` | Trace (sum of diagonal) |
| `mat_lu` | `mat_lu(m, out_lu, out_piv) → i64` | LU decomposition with partial pivoting |
| `mat_lu_solve` | `mat_lu_solve(lu, piv, b, out_x)` | Solve Ax=b from LU factors |
| `mat_det` | `mat_det(m) → i64` | Determinant via LU |
| `mat_inv` | `mat_inv(m) → i64` | Matrix inverse via LU (0 if singular) |
| `mat_cholesky` | `mat_cholesky(m, out_l) → 0/1` | Cholesky factorization (SPD matrices) |
| `mat_cholesky_solve` | `mat_cholesky_solve(l, b, out_x)` | Solve Ax=b from Cholesky factor |
| `mat_qr` | `mat_qr(m, out_q, out_r)` | QR decomposition via Householder |
| `mat_gaussian_elim` | `mat_gaussian_elim(aug) → 0/1` | Gaussian elimination on augmented matrix |
| `mat_least_squares` | `mat_least_squares(a, b, out_x)` | Least-squares solve via QR |
| `mat_eigen_sym` | `mat_eigen_sym(m, out_vals, out_vecs) → i64` | Eigendecomposition (symmetric) via Jacobi |
| `mat_svd` | `mat_svd(m, out_u, out_sigma, out_vt)` | SVD via eigendecomposition |
| `mat_pseudo_inv` | `mat_pseudo_inv(m) → i64` | Moore-Penrose pseudoinverse |
| `mat_rank` | `mat_rank(m, tol) → i64` | Numerical rank (SVD-based) |
| `mat_condition` | `mat_condition(m) → i64` | Condition number σ_max/σ_min (-1 if singular) |

### bigint.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

256-bit unsigned integer arithmetic (4×64-bit limbs, little-endian). Core operations: add, subtract, multiply, modular reduction, shift, compare, and hex conversion. Designed for elliptic-curve arithmetic (Ed25519, secp256k1). Requires alloc.cyr, string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `u256_zero` | `u256_zero() → i64` | Create zero u256 |
| `u256_from` | `u256_from(val) → i64` | Create u256 from u64 |
| `u256_copy` | `u256_copy(dst, src)` | Copy u256 |
| `u256_clone` | `u256_clone(a) → i64` | Clone u256 (allocates new) |
| `u256_limb` | `u256_limb(a, i) → i64` | Get limb i |
| `u256_set_limb` | `u256_set_limb(a, i, v)` | Set limb i |
| `u256_is_zero` | `u256_is_zero(a) → 0/1` | Check if zero |
| `u256_cmp` | `u256_cmp(a, b) → 1/0/-1` | Compare (1 if a>b, -1 if a<b, 0 if equal) |
| `u256_eq` | `u256_eq(a, b) → 0/1` | Equality check |
| `u256_add` | `u256_add(r, a, b) → i64` | Add (returns carry) |
| `u256_sub` | `u256_sub(r, a, b) → i64` | Subtract (returns borrow) |
| `u256_mul` | `u256_mul(r, a, b)` | Multiply (truncates to 256 bits) |
| `u256_shl1` | `u256_shl1(r, a) → i64` | Left shift by 1 bit |
| `u256_shr1` | `u256_shr1(r, a)` | Right shift by 1 bit |
| `u256_mod` | `u256_mod(r, a, p)` | Modular reduction r = a mod p |
| `u256_addmod` | `u256_addmod(r, a, b, p)` | Modular add (a+b) mod p |
| `u256_submod` | `u256_submod(r, a, b, p)` | Modular subtract (a-b) mod p |
| `u256_mulmod` | `u256_mulmod(r, a, b, p)` | Modular multiply (a*b) mod p |
| `u256_to_hex` | `u256_to_hex(a) → i64` | Format as 64-char hex string |
| `u256_from_hex` | `u256_from_hex(s) → i64` | Parse hex string to u256 |

### u128.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

128-bit unsigned integer helpers: construction, arithmetic (add, subtract, multiply), bitwise ops, shifts, comparisons, and division with modulo. Hardware fast-path for 64-bit divisors. Provides u64 modular arithmetic (mulmod, powmod) for cryptographic operations.

| Function | Signature | Description |
|----------|-----------|-------------|
| `u128_set` | `u128_set(dst, lo, hi)` | Set both limbs |
| `u128_from_u64` | `u128_from_u64(dst, lo)` | Zero-extend u64 to u128 |
| `u128_copy` | `u128_copy(dst, src)` | Copy 16 bytes |
| `u128_lo` | `u128_lo(ptr) → i64` | Low 64-bit limb |
| `u128_hi` | `u128_hi(ptr) → i64` | High 64-bit limb |
| `u128_eq` | `u128_eq(a, b) → 0/1` | Byte-identical equality |
| `u128_is_zero` | `u128_is_zero(ptr) → 0/1` | Zero test |
| `u128_add` | `u128_add(dst, a, b)` | Addition (wraps at 2^128) |
| `u128_sub` | `u128_sub(dst, a, b)` | Subtraction (wraps at 2^128) |
| `u128_addeq` | `u128_addeq(dst, src)` | In-place add |
| `u128_subeq` | `u128_subeq(dst, src)` | In-place subtract |
| `u128_mul` | `u128_mul(dst, a, b)` | Multiply (wraps at 2^128) |
| `u128_muleq` | `u128_muleq(dst, src)` | In-place multiply |
| `u128_shl` | `u128_shl(dst, src, n)` | Left shift by n bits |
| `u128_shr` | `u128_shr(dst, src, n)` | Logical right shift by n bits |
| `u128_shleq` | `u128_shleq(dst, n)` | In-place left shift |
| `u128_shreq` | `u128_shreq(dst, n)` | In-place right shift |
| `u128_and` | `u128_and(dst, a, b)` | Bitwise AND |
| `u128_or` | `u128_or(dst, a, b)` | Bitwise OR |
| `u128_xor` | `u128_xor(dst, a, b)` | Bitwise XOR |
| `u128_not` | `u128_not(dst, src)` | Bitwise NOT |
| `u128_andeq` | `u128_andeq(dst, src)` | In-place AND |
| `u128_oreq` | `u128_oreq(dst, src)` | In-place OR |
| `u128_xoreq` | `u128_xoreq(dst, src)` | In-place XOR |
| `u128_ugt` | `u128_ugt(a, b) → 0/1` | Unsigned greater-than |
| `u128_uge` | `u128_uge(a, b) → 0/1` | Unsigned greater-or-equal |
| `u128_ult` | `u128_ult(a, b) → 0/1` | Unsigned less-than |
| `u128_ule` | `u128_ule(a, b) → 0/1` | Unsigned less-or-equal |
| `u128_divmod` | `u128_divmod(qdst, rdst, a, b)` | Division with remainder (exits on division by zero) |
| `u128_div` | `u128_div(dst, a, b)` | Quotient only |
| `u128_mod` | `u128_mod(dst, a, b)` | Remainder only |
| `u128_diveq` | `u128_diveq(dst, src)` | In-place divide |
| `u128_modeq` | `u128_modeq(dst, src)` | In-place modulo |
| `u64_mulmod` | `u64_mulmod(a, b, m) → i64` | (a*b) mod m (u64, hardware fast-path) |
| `u64_powmod` | `u64_powmod(base, exp, m) → i64` | base^exp mod m (u64, square-and-multiply) |


## Crypto

Hashes and constant-time primitives. (x509/RSA/ECDSA live in the folded `sigil` dep; AEAD/key-schedule in `tls_native`.)

### sha1.cyr (v5.6.13)

SHA-1 message digest (FIPS 180-4). WARNING: SHA-1 is NOT collision-resistant (practical attacks since 2017). Use only for legacy interop (git object IDs, WebSocket handshake per RFC 6455, TLS 1.2 cipher names). For new code, prefer `lib/sigil.cyr` (SHA-256 / SHA-512) or `lib/keccak.cyr` (SHAKE-128 / SHAKE-256).

| Function | Signature | Description |
|----------|-----------|-------------|
| `sha1` | `sha1(data, len, digest_out) → 0` | Hash data[0..len) with FIPS 180-4 SHA-1, write 20-byte big-endian digest to digest_out (caller-allocated) |

### keccak.cyr (v5.4.15)

Keccak-f[1600] permutation and SHAKE-128 / SHAKE-256 extendable-output functions (FIPS 202). Pure reference implementation (64-bit lanes, no platform variants). Requires `lib/alloc.cyr` and `lib/string.cyr`.

| Function | Signature | Description |
|----------|-----------|-------------|
| `shake128` | `shake128(msg, msglen, out, outlen) → 0` | XOF with rate 168 bytes; writes outlen bytes to out |
| `shake256` | `shake256(msg, msglen, out, outlen) → 0` | XOF with rate 136 bytes; writes outlen bytes to out |

### ct.cyr (v5.9.18)

Constant-time primitives for cryptographic code. All comparisons and selections use mask-xor arithmetic with no data-dependent branches. Requires `lib/alloc.cyr` for `ct_eq_bytes_lens`.

| Function | Signature | Description |
|----------|-----------|-------------|
| `ct_select` | `ct_select(cond, a, b) → i64` | Branchless select: return a if cond==0, b if cond==1 |
| `ct_eq_bytes` | `ct_eq_bytes(a, b, n) → 0/1` | Branchless equality of a[0..n) and b[0..n); both buffers must be exactly n bytes |
| `ct_eq_bytes_lens` | `ct_eq_bytes_lens(a, a_len, b, b_len) → 0/1` | Branchless equality with length checks; returns 0 immediately on length mismatch (length is NOT secret) |


## Data & Encoding

Encoding, parsing, time, flags, and logging.

### base64.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

RFC 4648 Base64 encoding/decoding (standard + URL-safe). Requires alloc.cyr, string.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `base64_encode` | `base64_encode(buf, len) → ptr` | Encode buffer to base64 string (null-terminated) |
| `base64_decode` | `base64_decode(encoded, enc_len) → ptr` | Decode base64 to {data_ptr, length} pair |
| `base64url_encode` | `base64url_encode(buf, len) → ptr` | Encode buffer to base64url (no padding, null-terminated) |
| `base64url_decode` | `base64url_decode(encoded, enc_len) → ptr` | Decode base64url with optional padding, returns {data_ptr, length} pair |

### csv.cyr

> **Carved into `lib/bayan.cyr` (bayan 1.0.0, v6.1.25).** No longer
> stdlib — `include "lib/bayan.cyr"` (legacy aliases retained).

RFC 4180 CSV parser and writer. Requires alloc.cyr, string.cyr, vec.cyr, str.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `csv_parse_line` | `csv_parse_line(line) → vec` | Parse CSV line into vec of field strings (handles quoted fields and escapes) |
| `csv_escape` | `csv_escape(field) → ptr` | Escape field for CSV output (quotes if needed) |
| `csv_write_line` | `csv_write_line(fields) → ptr` | Write vec of fields as CSV line (null-terminated string with trailing newline) |

### chrono.cyr

Time and duration utilities for wall-clock and monotonic clocks. Requires syscalls.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `clock_now_ns` | `clock_now_ns() → i64` | Current monotonic time in nanoseconds |
| `clock_now_ms` | `clock_now_ms() → i64` | Current monotonic time in milliseconds |
| `clock_epoch_secs` | `clock_epoch_secs() → i64` | Current wall-clock epoch seconds |
| `clock_epoch_ns` | `clock_epoch_ns() → i64` | Current wall-clock epoch nanoseconds |
| `sleep_ms` | `sleep_ms(ms)` | Sleep for ms milliseconds (portable across Linux/macOS/Windows) |
| `dur_new` | `dur_new(secs, nsecs) → ptr` | Create duration struct {secs, nsecs} |
| `dur_secs` | `dur_secs(d) → i64` | Get seconds component |
| `dur_nsecs` | `dur_nsecs(d) → i64` | Get nanoseconds component |
| `dur_to_ms` | `dur_to_ms(d) → i64` | Convert duration to total milliseconds |
| `dur_to_ns` | `dur_to_ns(d) → i64` | Convert duration to total nanoseconds |
| `dur_between` | `dur_between(start_ns, end_ns) → ptr` | Measure elapsed time as duration struct |
| `is_leap_year` | `is_leap_year(y) → 0/1` | Check if year is leap |
| `epoch_to_date` | `epoch_to_date(epoch) → ptr` | Convert epoch seconds to date struct {year, month, day, hour, min, sec} |
| `iso8601` | `iso8601(epoch) → ptr` | Format epoch seconds as ISO-8601 string (null-terminated) |
| `iso8601_now` | `iso8601_now() → ptr` | Format current time as ISO-8601 string |
| `iso8601_parse` | `iso8601_parse(s) → i64` | Parse ISO-8601 string to epoch seconds, returns -1 on error |

### flags.cyr

getopt-long-shaped CLI flag parser with bool/int/string flag types. Requires alloc.cyr, string.cyr, fmt.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `flags_new` | `flags_new() → handle` | Allocate fresh flags context |
| `flags_add_bool` | `flags_add_bool(h, short_ch, long_name, default_val, help) → idx` | Register bool flag, returns index |
| `flags_add_int` | `flags_add_int(h, short_ch, long_name, default_val, help) → idx` | Register int flag, returns index |
| `flags_add_str` | `flags_add_str(h, short_ch, long_name, default_val, help) → idx` | Register string flag, returns index |
| `flags_parse` | `flags_parse(h, argc, argv) → 0/-1` | Parse argv[1..], returns 0 on success or -1 on error |
| `flags_get_bool` | `flags_get_bool(h, idx) → 0/1` | Read bool flag value |
| `flags_get_int` | `flags_get_int(h, idx) → i64` | Read int flag value |
| `flags_get_str` | `flags_get_str(h, idx) → ptr` | Read string flag value (cstr) |
| `flags_positional_count` | `flags_positional_count(h) → count` | Number of positional arguments captured |
| `flags_positional` | `flags_positional(h, idx) → ptr` | Get positional arg at index (cstr), returns 0 if out of range |
| `flags_error` | `flags_error(h) → code` | Last parse error code (FlagErr enum) |
| `flags_print_help` | `flags_print_help(h)` | Print usage to stderr |

### log.cyr

Structured logging wrapper with level filtering (TRACE/DEBUG/INFO/WARN/ERROR/FATAL). Requires sakshi.cyr, string.cyr, fmt.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `log_init` | `log_init(level)` | Initialize logging with minimum level |
| `log_level` | `log_level() → i64` | Get current log level |
| `log_set_level` | `log_set_level(level)` | Set log level at runtime |
| `log_enabled` | `log_enabled(level) → 0/1` | Check if level would be logged |
| `log_trace` | `log_trace(msg)` | Log at TRACE level |
| `log_debug` | `log_debug(msg)` | Log at DEBUG level |
| `log_info` | `log_info(msg)` | Log at INFO level |
| `log_warn` | `log_warn(msg)` | Log at WARN level |
| `log_error` | `log_error(msg)` | Log at ERROR level |
| `log_fatal` | `log_fatal(msg)` | Log at FATAL level (does not exit) |
| `log_info_kv` | `log_info_kv(msg, key, val)` | Log with key=value context at INFO level |
| `log_info_int` | `log_info_int(msg, key, val)` | Log with integer key=value at INFO level |


## Collections (additional)

### hashmap_fast.cyr

SIMD-accelerated hash table with Swiss-table-inspired design (metadata + separate key/value arrays). Requires alloc.cyr, string.cyr, fnptr.cyr. **Status (v5.8.62): experimental, no production consumers — not in the `[deps].stdlib` auto-prepend list, and the only in-repo caller is `tests/tcyr/hashmap_ext.tcyr`. Use hashmap.cyr for production.**

| Function | Signature | Description |
|----------|-----------|-------------|
| `fhm_new` | `fhm_new() → handle` | Create new fast hashmap (initial capacity 16) |
| `fhm_cap` | `fhm_cap(m) → i64` | Current capacity |
| `fhm_count` | `fhm_count(m) → i64` | Number of occupied entries |
| `fhm_size` | `fhm_size(m) → i64` | Alias for fhm_count |
| `fhm_get` | `fhm_get(m, key) → i64` | Get value by key, returns 0 if not found |
| `fhm_get_or` | `fhm_get_or(m, key, default_val) → i64` | Get value with default fallback |
| `fhm_has` | `fhm_has(m, key) → 0/1` | Check if key exists |
| `fhm_set` | `fhm_set(m, key, val)` | Set key-value pair (grows at 87.5% load) |
| `fhm_delete` | `fhm_delete(m, key) → 0/1` | Delete key, returns 1 if found |
| `fhm_keys` | `fhm_keys(m) → vec` | Get all keys as vec |
| `fhm_values` | `fhm_values(m) → vec` | Get all values as vec |
| `fhm_clear` | `fhm_clear(m)` | Clear all entries |


## Networking — TLS & WebSockets

Layered on `net.cyr`/`http.cyr` (above). TLS has a libssl façade + a sovereign native stack.

### tls.cyr

TLS client façade. Default backend wraps `libssl.so.3` (loaded via `fdlopen`-bootstrapped glibc `dlopen`); `tls_set_backend(TLS_BACKEND_NATIVE)` flips to the sovereign stack in `tls_native.cyr` (no OpenSSL). Requires fdlopen.cyr, net.cyr, mmap.cyr, dynlib.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_available` | `tls_available() → 1/0` | Is the active backend usable (native always; libssl checks dlopen) |
| `tls_set_backend` | `tls_set_backend(backend) → 0/-1` | Select `TLS_BACKEND_LIBSSL` or `TLS_BACKEND_NATIVE` |
| `tls_get_backend` | `tls_get_backend() → backend` | Active backend |
| `tls_connect` | `tls_connect(sock, host) → ctx/0` | Wrap a connected socket in a TLS session (SNI = host) |
| `tls_connect_with_ctx_hook` | `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx) → ctx/0` | Connect with a pre-handshake hook (ALPN / verify customization) |
| `tls_write` | `tls_write(ctx, buf, len) → n/-1` | Write plaintext through TLS |
| `tls_read` | `tls_read(ctx, buf, maxlen) → n/-1` | Read plaintext from TLS |
| `tls_close` | `tls_close(ctx) → 0` | Shut down and free the session |
| `tls_set_alpn` | `tls_set_alpn(handle, protos, len) → 0/-1` | Set ALPN advertise list (OpenSSL wire format; call in the hook) |
| `tls_set_verify` | `tls_set_verify(handle, mode, cb) → 0/-1` | Override peer-verification mode |
| `tls_get_alpn_selected` | `tls_get_alpn_selected(ctx, buf, max) → len` | Negotiated ALPN protocol |
| `tls_get_peer_spki_der` | `tls_get_peer_spki_der(ctx, buf, max) → len` | Peer SubjectPublicKeyInfo DER (HPKP pin target) |

The façade also exposes **session resumption** (`tls_connect_alloc`/`tls_connect_complete`, `tls_get_session`/`tls_set_session`/`tls_session_free`, `tls_ctx_set_session_*_cb`, `tls_ctx_set_session_cache_mode`) and **TLS 1.3 0-RTT** (`tls_write_early_data`/`tls_read_early_data`/`tls_get_early_data_status`/`tls_ctx_set_max_early_data`, gated by `tls_supports_early_data`) — see the source for the full surface.

### tls_native.cyr

Sovereign TLS 1.2 + 1.3 stack — no OpenSSL. ECDSA (P-256/P-384) / RSA (PSS, PKCS#1) / Ed25519 signatures; AES-128/256-GCM + ChaCha20-Poly1305; ALPN, SNI, Extended Master Secret, OS trust-store verification; server-flight reassembly; client + server. Live-interop-proven against Cloudflare + OpenSSL. Requires syscalls.cyr, alloc.cyr, sigil.cyr, thread.cyr, thread_local.cyr.

**Connection lifecycle:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_available` | `tls_native_available() → 1` | Capability check (compile-time available) |
| `tls_native_new_client` | `tls_native_new_client(host, host_len) → ctx` | Client context (SNI + hostname verification) |
| `tls_native_new_server` | `tls_native_new_server(cert_chain, cert_len, key, key_len) → ctx` | Server context (cert chain + private key) |
| `tls_native_connect` | `tls_native_connect(ctx, fd) → TLS_OK/err` | TLS 1.3 client handshake |
| `tls_native_connect_12` | `tls_native_connect_12(ctx, fd) → TLS_OK/err` | TLS 1.2 client handshake |
| `tls_native_accept` | `tls_native_accept(ctx, fd) → TLS_OK/err` | TLS 1.3 server handshake |
| `tls_native_accept_12` | `tls_native_accept_12(ctx, fd) → TLS_OK/err` | TLS 1.2 server handshake |
| `tls_native_write` | `tls_native_write(ctx, buf, len) → n/err` | Send application data (plaintext → AEAD record) |
| `tls_native_read` | `tls_native_read(ctx, buf, max) → n/err` | Receive application data (AEAD record → plaintext) |
| `tls_native_close` | `tls_native_close(ctx) → TLS_OK/err` | Clean close handshake (sends close_notify alert) |

**Configuration (pre-handshake):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_set_alpn` | `tls_native_set_alpn(ctx, protos, len) → TLS_OK/err` | ALPN advertise list (OpenSSL wire format) |
| `tls_native_set_verify` | `tls_native_set_verify(ctx, mode) → TLS_OK/err` | Peer-verification mode (`TLS_VERIFY_NONE`/`PEER`) |
| `tls_native_set_ca_bundle` | `tls_native_set_ca_bundle(ctx, pem, len, is_der) → TLS_OK/err` | Install a custom CA bundle (PEM or DER) |
| `tls_native_set_ca_system` | `tls_native_set_ca_system(ctx) → TLS_OK/err` | Load the system CA trust store |
| `tls_native_set_version_range` | `tls_native_set_version_range(ctx, min, max) → TLS_OK/err` | Constrain negotiated version to [min, max] |

**Introspection (post-handshake):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_get_state` | `tls_native_get_state(ctx) → state` | Connection state (`TLS_STATE_*`) |
| `tls_native_get_cipher` | `tls_native_get_cipher(ctx) → suite` | Negotiated ciphersuite |
| `tls_native_get_version` | `tls_native_get_version(ctx) → ver` | Negotiated version (`TLS_VERSION_1_2`/`1_3`) |
| `tls_native_get_alpn_selected` | `tls_native_get_alpn_selected(ctx, buf, max) → len` | Negotiated ALPN |
| `tls_native_get_peer_cert_der` | `tls_native_get_peer_cert_der(ctx, buf, max) → len` | Peer leaf certificate DER |
| `tls_native_get_peer_spki_der` | `tls_native_get_peer_spki_der(ctx, buf, max) → len` | Peer SubjectPublicKeyInfo DER |
| `tls_native_get_last_error` | `tls_native_get_last_error(ctx) → code` | Last error (`TLS_ERR_*`) |
| `tls_native_get_key_algo` | `tls_native_get_key_algo(ctx) → algo` | Peer's signature algorithm (ECDSA/RSA/Ed25519) |
| `tls_native_get_group` | `tls_native_get_group(ctx) → group` | Selected ECDH group |

**Record layer:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_record_write_header` | `tls_native_record_write_header(buf, ct, version, length) → 5` | Write 5-byte TLSPlaintext/TLSCiphertext header |
| `tls_native_record_read_header` | `tls_native_record_read_header(buf, buflen, ct_out, version_out, length_out) → 5/err` | Parse record header; extract type, version, length |
| `tls_native_record_fragment_count` | `tls_native_record_fragment_count(plaintext_len) → count` | Number of fragments needed (max 16KB plaintext per fragment) |
| `tls_native_record_aad` | `tls_native_record_aad(ct, version, length, aad_out5) → 5` | Generate 5-byte TLS 1.3 AAD from header fields |
| `tls_native_record_aad_12` | `tls_native_record_aad_12(seq8, ct, version, length, aad_out13) → 13` | Generate 13-byte TLS 1.2 AAD (sequence ‖ type ‖ version ‖ length) |
| `tls_native_record_seal` | `tls_native_record_seal(cipher, key, static_iv, seq8, inner_ct, inner, inner_len, out, out_max) → n/err` | Encrypt + authenticate plaintext into record (TLS 1.3) |
| `tls_native_record_seal_12` | `tls_native_record_seal_12(cipher, key, iv, seq8, ct, plain, plain_len, out, out_max) → n/err` | Encrypt + authenticate plaintext into record (TLS 1.2 AEAD) |
| `tls_native_record_open` | `tls_native_record_open(cipher, key, static_iv, seq8, record, record_len, out, out_max, out_ct) → n/err` | Decrypt + verify ciphertext record, extract content type (TLS 1.3) |
| `tls_native_record_open_12` | `tls_native_record_open_12(cipher, key, iv, seq8, record, record_len, out, out_max, out_ct) → n/err` | Decrypt + verify ciphertext record, extract content type (TLS 1.2) |

**AEAD & ciphersuite selection:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_aead_nonce` | `tls_native_aead_nonce(static_iv12, seq8, nonce_out12) → 12` | Compute 12-byte TLS 1.3 nonce: XOR(seq ‖ 0x00, static_iv) |
| `tls_native_aead_nonce_12_gcm` | `tls_native_aead_nonce_12_gcm(salt4, explicit8, nonce_out12) → 12` | Compute 12-byte TLS 1.2 GCM nonce: salt ‖ explicit |
| `tls_native_cipher_hash_algo` | `tls_native_cipher_hash_algo(cipher) → algo` | Hash algo for ciphersuite (TLS_HASH_SHA256/384) |
| `tls_native_cipher_key_len` | `tls_native_cipher_key_len(cipher) → bytes` | AEAD key length (16 for AES-128, 32 for AES-256 or ChaCha20) |
| `tls_native_cipher_iv_len` | `tls_native_cipher_iv_len(cipher) → 12` | Static IV length for TLS 1.3 AEAD (always 12) |
| `tls_native_cipher_iv_len_12` | `tls_native_cipher_iv_len_12(cipher) → bytes` | IV/salt length for TLS 1.2 (4 for AES-GCM, 12 for ChaCha20) |
| `tls_native_cipher_tag_len` | `tls_native_cipher_tag_len(cipher) → 16` | AEAD authentication tag length (always 16) |
| `tls_native_cipher_supported` | `tls_native_cipher_supported(cipher) → 0/1` | Capability check (1 = supported by this build) |
| `tls_native_cipher_select` | `tls_native_cipher_select(client_offers, n_offers, server_prefs, n_prefs) → cipher` | Select ciphersuite from client list using server preference order |
| `tls_native_aead_to_wire_12` | `tls_native_aead_to_wire_12(aead_id, auth) → wire_id` | Map internal AEAD identity + auth algo to TLS 1.2 wire ciphersuite ID |

**Key schedule (TLS 1.3):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_keysched_new` | `tls_native_keysched_new(hash_algo) → handle` | Create key schedule for hash algo (TLS_HASH_SHA256/384) |
| `tls_native_keysched_set_psk` | `tls_native_keysched_set_psk(ks, psk, psk_len) → TLS_OK/err` | Override PSK and recompute early secret (hash_len bytes) |
| `tls_native_keysched_derive_handshake` | `tls_native_keysched_derive_handshake(ks, dhe, dhe_len, transcript) → TLS_OK/err` | Derive handshake + c/s hs-traffic secrets from DHE + transcript |
| `tls_native_keysched_derive_master` | `tls_native_keysched_derive_master(ks, transcript) → TLS_OK/err` | Derive app-traffic + exporter + resumption secrets from transcript |
| `tls_native_keysched_get_secret` | `tls_native_keysched_get_secret(ks, which, out) → len/err` | Read derived secret (early/hs/c-hs/s-hs/app/exporter/resumption) |
| `tls_native_keysched_phase` | `tls_native_keysched_phase(ks) → phase` | Current phase (TLS_KSP_NONE/EARLY/HANDSHAKE/MASTER) |
| `tls_native_key_update_secret` | `tls_native_key_update_secret(cipher, secret, secret_len, hash_algo, out) → len/err` | Derive next-gen secret for KeyUpdate post-handshake |

**Transcript hashing:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_transcript_init` | `tls_native_transcript_init(hash_algo) → handle/0` | Create transcript state (SHA-256 or SHA-384) |
| `tls_native_transcript_update` | `tls_native_transcript_update(state, data, len) → TLS_OK/err` | Hash serialized handshake message into transcript |
| `tls_native_transcript_digest` | `tls_native_transcript_digest(state, digest_out) → len/err` | Finalize and return digest (32 for SHA-256, 48 for SHA-384) |
| `tls_native_transcript_digest_len` | `tls_native_transcript_digest_len(state) → len/-1` | Get digest length without computing (32 or 48) |

**Derive labels (HKDF-Expand-Label):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_derive_key` | `tls_native_derive_key(sec, secret_len, hash_algo, key_out, key_len) → len/err` | Derive per-direction write key from secret |
| `tls_native_derive_iv` | `tls_native_derive_iv(sec, secret_len, hash_algo, iv_out, iv_len) → len/err` | Derive per-direction write IV from secret (12 bytes for AEADs) |

**TLS 1.2 PRF & key derivation:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_12_prf` | `tls_native_12_prf(cipher, sec, secret_len, label, label_len, seed, seed_len, out, out_len) → len/err` | PRF-SHA256/384 for key expansion, master secret, verify data |
| `tls_native_12_master_secret` | `tls_native_12_master_secret(cipher, pre_master, pm_len, client_random, server_random, out48) → 48/err` | Derive master secret from pre-master + randoms |
| `tls_native_12_master_secret_ems` | `tls_native_12_master_secret_ems(cipher, pre_master, pm_len, session_hash, sh_len, out48) → 48/err` | Derive master secret using Extended Master Secret (transcript hash) |
| `tls_native_12_key_block_len` | `tls_native_12_key_block_len(cipher) → bytes/-1` | Bytes of key block needed (2*key_len + 2*iv_len for AEAD) |
| `tls_native_12_key_block` | `tls_native_12_key_block(cipher, master48, client_random, server_random, out, out_len) → len/err` | Generate key block for record encryption keys + IVs |
| `tls_native_12_partition_keys` | `tls_native_12_partition_keys(cipher, key_block, cw_key, sw_key, cw_iv, sw_iv) → TLS_OK/err` | Split key block into client/server write keys + IVs |
| `tls_native_12_cipher_aead_identity` | `tls_native_12_cipher_aead_identity(wire_id) → aead` | Map TLS 1.2 wire ciphersuite ID to internal AEAD identity |
| `tls_native_12_cipher_hash` | `tls_native_12_cipher_hash(wire_id) → algo` | Hash algo for TLS 1.2 ciphersuite (TLS_HASH_SHA256/384) |
| `tls_native_12_cipher_auth` | `tls_native_12_cipher_auth(wire_id) → auth` | Auth algo (TLS12_AUTH_ECDSA/RSA) |
| `tls_native_12_cipher_supported` | `tls_native_12_cipher_supported(wire_id) → 0/1` | Capability check for TLS 1.2 ciphersuite |

**TLS 1.2 handshake messages:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_12_build_client_hello` | `tls_native_12_build_client_hello(ctx, out, out_max) → len/err` | Build ClientHello with extensions + ciphersuites |
| `tls_native_12_verify_data` | `tls_native_12_verify_data(cipher, master48, label, label_len, handshake_hash, hh_len, out12) → 12/err` | Compute 12-byte verify_data for Finished message |
| `tls_native_12_build_finished` | `tls_native_12_build_finished(ctx, label, out, out_max) → len/err` | Build Finished message with master secret + transcript hash |
| `tls_native_12_verify_finished` | `tls_native_12_verify_finished(ctx, msg, msg_len, label) → TLS_OK/err` | Verify peer Finished message constant-time |
| `tls_native_12_build_server_hello_done` | `tls_native_12_build_server_hello_done(out, out_max) → len/err` | Build ServerHelloDone (0-byte body handshake message) |
| `tls_native_12_parse_server_hello_done` | `tls_native_12_parse_server_hello_done(msg, msg_len) → TLS_OK/err` | Parse ServerHelloDone (validates empty body) |
| `tls_native_12_build_client_key_exchange` | `tls_native_12_build_client_key_exchange(client_eph_pub, out, out_max) → len/err` | Build ClientKeyExchange (ECDHE public key) |
| `tls_native_12_parse_client_key_exchange` | `tls_native_12_parse_client_key_exchange(msg, msg_len, peer_pub_out32) → 32/err` | Parse ClientKeyExchange, extract peer's ECDHE public key |
| `tls_native_12_compute_premaster` | `tls_native_12_compute_premaster(ctx, peer_eph_pub32, out32) → 32/err` | Derive pre-master secret (ECDHE shared secret) |
| `tls_native_12_derive_keys` | `tls_native_12_derive_keys(ctx, premaster, pm_len) → TLS_OK/err` | Derive master secret, key block, and install keys |
| `tls_native_12_seal` | `tls_native_12_seal(ctx, ct, plain, plain_len, out, out_max) → len/err` | Encrypt + MAC plaintext into TLS 1.2 record |
| `tls_native_12_open` | `tls_native_12_open(ctx, record, record_len, out, out_max, out_ct) → len/err` | Decrypt + verify TLS 1.2 record, extract plaintext + type |
| `tls_native_12_build_server_flight` | `tls_native_12_build_server_flight(ctx, out, out_max) → len/err` | Build server flight (ServerHello + Certificate + done) |

**Handshake (client side — TLS 1.3):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_client_build_hello` | `tls_native_client_build_hello(ctx, out, out_max) → len/err` | Build ClientHello with x25519 + ECDSA/Ed25519 sig algs |
| `tls_native_client_parse_server_hello` | `tls_native_client_parse_server_hello(ctx, sh, sh_len) → TLS_OK/err` | Parse ServerHello, derive handshake secrets (no HelloRetryRequest yet) |
| `tls_native_client_open_handshake` | `tls_native_client_open_handshake(ctx, record, record_len, out, out_max, out_ct) → len/err` | Decrypt server handshake flight with handshake key |
| `tls_native_client_recv_flight` | `tls_native_client_recv_flight(ctx, record, record_len) → TLS_OK/err` | Process server flight record (accumulate for reassembly) |
| `tls_native_client_seal_handshake` | `tls_native_client_seal_handshake(ctx, inner, inner_len, out, out_max) → len/err` | Encrypt client handshake message with handshake key |
| `tls_native_client_finish` | `tls_native_client_finish(ctx, out, out_max) → len/err` | Build + encrypt Finished message, transition to CONNECTED |
| `tls_native_client_verify_chain` | `tls_native_client_verify_chain(ctx, now_unix) → TLS_OK/err` | Verify peer certificate chain against trust store |
| `tls_native_client_verify_hostname` | `tls_native_client_verify_hostname(ctx) → TLS_OK/err` | Verify SNI host against server cert SubjectAltName |
| `tls_native_client_parse_server_hello_12` | `tls_native_client_parse_server_hello_12(ctx, sh, sh_len) → TLS_OK/err` | Parse TLS 1.2 ServerHello + derive handshake secrets |

**Handshake (server side — TLS 1.3):**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_server_load_creds` | `tls_native_server_load_creds(ctx) → TLS_OK/err` | Validate certificate chain + private key before accepting |
| `tls_native_server_respond_hello` | `tls_native_server_respond_hello(ctx, ch_msg, ch_len, out, out_max) → len/err` | Build ServerHello (or HelloRetryRequest) in response to ClientHello |
| `tls_native_server_sent_hrr` | `tls_native_server_sent_hrr(ctx) → 0/1` | Check if last respond_hello was HelloRetryRequest (vs ServerHello) |
| `tls_native_server_derive_handshake` | `tls_native_server_derive_handshake(ctx) → TLS_OK/err` | Derive handshake secrets from ECDHE + CH..SH transcript |
| `tls_native_server_build_flight` | `tls_native_server_build_flight(ctx, out, out_max) → len/err` | Build server flight (EncryptedExtensions + Certificate + Finished) |
| `tls_native_server_recv_client_certificate` | `tls_native_server_recv_client_certificate(ctx, msg, msg_len) → TLS_OK/err` | Process Certificate message, advance transcript + state |
| `tls_native_server_recv_client_certverify` | `tls_native_server_recv_client_certverify(ctx, msg, msg_len) → TLS_OK/err` | Verify CertificateVerify signature (ECDSA-P256/Ed25519) |
| `tls_native_server_recv_client_finished` | `tls_native_server_recv_client_finished(ctx, msg, msg_len) → TLS_OK/err` | Verify client Finished constant-time, transition to CONNECTED |
| `tls_native_server_derive_master` | `tls_native_server_derive_master(ctx) → TLS_OK/err` | Derive application-traffic + exporter secrets post-Finished |
| `tls_native_server_install_handshake_keys` | `tls_native_server_install_handshake_keys(ctx) → TLS_OK/err` | Install derived server/client hs-traffic keys (TLS 1.2) |
| `tls_native_server_seal_handshake` | `tls_native_server_seal_handshake(ctx, inner, inner_len, out, out_max) → len/err` | Encrypt server handshake message with handshake key |
| `tls_native_server_open_handshake` | `tls_native_server_open_handshake(ctx, record, record_len, out, out_max, out_ct) → len/err` | Decrypt client handshake flight with handshake key |
| `tls_native_server_open_ticket` | `tls_native_server_open_ticket(ctx, blob, blob_len, out) → len/-1` | Decrypt session ticket, recover resumption secret |
| `tls_native_server_new_session_ticket` | `tls_native_server_new_session_ticket(ctx, out, out_max) → len/err` | Build NewSessionTicket message (sealed resumption secret) |

**Application data & record encryption:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_open_app` | `tls_native_open_app(cipher, key, static_iv, seq8, record, record_len, out, out_max) → len/err` | Decrypt application record (post-handshake) |
| `tls_native_seal_app` | `tls_native_seal_app(cipher, key, static_iv, seq8, plain, plain_len, out, out_max) → len/err` | Encrypt application record (post-handshake) |
| `tls_native_install_app_keys` | `tls_native_install_app_keys(ctx) → TLS_OK/err` | Install derived app-traffic keys into context |

**Sequence & state tracking:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `tls_native_seq_init` | `tls_native_seq_init(seq8) → 0` | Initialize sequence number to 0 |
| `tls_native_seq_increment` | `tls_native_seq_increment(seq8) → 0` | Post-increment 8-byte sequence number (big-endian) |
| `tls_native_handshake_write_header` | `tls_native_handshake_write_header(buf, type, length) → 4` | Write 4-byte handshake message header |
| `tls_native_handshake_read_header` | `tls_native_handshake_read_header(buf, buflen, type_out, length_out) → 4/err` | Parse handshake header, extract type + body length |
| `tls_native_ccs_record_write` | `tls_native_ccs_record_write(buf) → len` | Write ChangeCipherSpec record (legacy 1.2, middlebox compat in 1.3) |
| `tls_native_psk_binder` | `tls_native_psk_binder(cipher, psk, psk_len, transcript, transcript_len, binder_out) → len/err` | Compute PSK binder for 0-RTT resumption |

### ws.cyr

WebSocket client (RFC 6455): handshake upgrade, frame masking/unmasking, automatic ping→pong, and the close handshake. Requires net.cyr, base64.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `ws_new` | `ws_new(fd) → ws` | WebSocket handle from a connected socket |
| `ws_connect` | `ws_connect(sock, path, host) → ws` | Perform the upgrade handshake |
| `ws_fd` | `ws_fd(ws) → fd` | Underlying socket fd |
| `ws_state` | `ws_state(ws) → state` | `WS_CONNECTING`/`OPEN`/`CLOSING`/`CLOSED` |
| `ws_send_text` | `ws_send_text(ws, msg) → n` | Send a masked text message |
| `ws_send_binary` | `ws_send_binary(ws, data, len) → n` | Send a masked binary message |
| `ws_ping` | `ws_ping(ws) → n` | Send a ping frame |
| `ws_recv_frame` | `ws_recv_frame(ws, opcode_out, len_out) → payload` | Receive a frame (auto-responds to ping) |
| `ws_recv` | `ws_recv(ws) → payload` | Receive a text/binary message (0 on close) |
| `ws_close` | `ws_close(ws) → 0` | Send close frame + shut down |

### ws_server.cyr

WebSocket server (RFC 6455). Integrates with http_server.cyr for upgrade handshake; after upgrade, handles frame I/O, masking, and control frames. Requires: alloc.cyr, string.cyr, fmt.cyr, str.cyr, syscalls.cyr, base64.cyr, sha1.cyr, net.cyr, tagged.cyr, http_server.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `ws_server_new` | `ws_server_new(fd) → ws` | Create handle for upgraded socket |
| `ws_server_fd` | `ws_server_fd(ws) → fd` | Extract socket file descriptor |
| `ws_server_state` | `ws_server_state(ws) → state` | Get connection state |
| `ws_server_handshake` | `ws_server_handshake(cfd, req_buf, req_len) → ws/0` | Perform upgrade; reply 101 or 0 on failure |
| `ws_server_recv_frame` | `ws_server_recv_frame(ws, payload_buf, max, opcode_out) → len/-1` | Receive frame and unmask |
| `ws_server_recv` | `ws_server_recv(ws) → data/0` | Receive text/binary, handle ping/close |
| `ws_server_send_text` | `ws_server_send_text(ws, msg)` | Send text message |
| `ws_server_send_binary` | `ws_server_send_binary(ws, data, len)` | Send binary message |
| `ws_server_send_ping` | `ws_server_send_ping(ws)` | Send ping frame |
| `ws_server_send_pong` | `ws_server_send_pong(ws, data, len)` | Send pong (echo client ping payload) |
| `ws_server_send_close` | `ws_server_send_close(ws, code, reason)` | Send close frame with code + reason |
| `ws_server_send_frame` | `ws_server_send_frame(ws, opcode, data, len)` | Send raw frame |
| `ws_server_close` | `ws_server_close(ws)` | Close handshake and free handle |


## Systems & FFI (additional)

Memory mapping, dynamic loading, C FFI, and Windows GPU enumeration. (`dynlib.cyr` is documented above.)

### mmap.cyr

Memory-mapped I/O via direct syscalls. Requires syscalls.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `cyr_mmap` | `cyr_mmap(addr, length, prot, flags, fd, offset) → addr/-1` | Map region; prot: PROT_READ=1, PROT_WRITE=2, PROT_EXEC=4; flags: MAP_PRIVATE=2, MAP_SHARED=1, MAP_ANONYMOUS=32, MAP_FIXED=16 |
| `cyr_munmap` | `cyr_munmap(addr, length) → 0` | Unmap region |
| `cyr_mprotect` | `cyr_mprotect(addr, length, prot) → 0` | Change page protection |
| `mmap_file_ro` | `mmap_file_ro(fd, length) → addr/0` | Map file read-only (MAP_PRIVATE) |
| `mmap_file_rw` | `mmap_file_rw(fd, length) → addr/0` | Map file read-write (MAP_PRIVATE copy) |
| `mmap_anon` | `mmap_anon(length) → addr/0` | Anonymous mapping (page-aligned malloc) |

### fdlopen.cyr

Foreign-dlopen: glibc function access from static cyrius binaries via ld.so bootstrap (x86_64 Linux only). Requires string.cyr, syscalls.cyr, mmap.cyr, dynlib.cyr, fnptr.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `fdlopen_state_size` | `fdlopen_state_size() → 256` | Bytes to allocate for state buffer |
| `fdlopen_init` | `fdlopen_init(state) → -1/-6/-8` | Probe helper; use fdlopen_init_full for full orchestration |
| `fdlopen_init_full` | `fdlopen_init_full(state) → 0 or negative` | Complete ld.so-entry dance; populates fn pointers on success |
| `fdlopen_helper_available` | `fdlopen_helper_available() → 0/1` | Check if ~/.cyrius/dlopen-helper exists |
| `dl_setjmp` | `dl_setjmp(buf) → 0/nonzero` | Capture x86_64 callee-saved state (128-byte jmp_buf) |
| `dl_longjmp` | `dl_longjmp(buf, val)` | Restore state and jump (does not return) |
| `fdlopen_slot` | `fdlopen_slot(state, offset) → fn*` | Get fn pointer at offset in state (0 if uninit) |
| `fdlopen_dlopen` | `fdlopen_dlopen(state) → fn*` | Get real glibc dlopen |
| `fdlopen_dlsym` | `fdlopen_dlsym(state) → fn*` | Get real glibc dlsym |
| `fdlopen_dlclose` | `fdlopen_dlclose(state) → fn*` | Get real glibc dlclose |
| `fdlopen_dlerror` | `fdlopen_dlerror(state) → fn*` | Get real glibc dlerror |
| `fdlopen_getaddrinfo` | `fdlopen_getaddrinfo(state) → fn*` | Get real glibc getaddrinfo |
| `fdlopen_freeaddrinfo` | `fdlopen_freeaddrinfo(state) → fn*` | Get real glibc freeaddrinfo |
| `fdlopen_gai_strerror` | `fdlopen_gai_strerror(state) → fn*` | Get real glibc gai_strerror |
| `fdlopen_strerror` | `fdlopen_strerror(state) → fn*` | Get real glibc strerror |
| `fdlopen_setlocale` | `fdlopen_setlocale(state) → fn*` | Get real glibc setlocale |
| `fdlopen_setenv` | `fdlopen_setenv(state) → fn*` | Get real glibc setenv |
| `fdlopen_unsetenv` | `fdlopen_unsetenv(state) → fn*` | Get real glibc unsetenv |
| `fdlopen_status` | `fdlopen_status(state) → 0/1/negative` | Query init status (1 = success, negative = error code) |

### cffi.cyr

C struct layout helpers for foreign struct interop (field offsets with C alignment/padding rules). Requires alloc.cyr.

| Function | Signature | Description |
|----------|-----------|-------------|
| `cffi_struct_new` | `cffi_struct_new() → layout` | Create new struct layout (supports ≤32 fields) |
| `cffi_field` | `cffi_field(layout, typ) → offset` | Add field, return byte offset |
| `cffi_field_struct` | `cffi_field_struct(layout, size, align) → offset` | Add nested struct field |
| `cffi_field_array` | `cffi_field_array(layout, elem_type, count) → offset` | Add array field (count × elem_type) |
| `cffi_field_count` | `cffi_field_count(layout) → n` | Get number of fields |
| `cffi_offset` | `cffi_offset(layout, n) → offset/-1` | Get byte offset of field N |
| `cffi_sizeof` | `cffi_sizeof(layout) → bytes` | Get total struct size (with tail padding) |
| `cffi_max_align` | `cffi_max_align(layout) → bytes` | Get maximum field alignment |
| `cffi_type_size` | `cffi_type_size(typ) → bytes` | Extract size from CFFI type constant |
| `cffi_type_align` | `cffi_type_align(typ) → bytes` | Extract alignment from CFFI type constant |
| `cffi_get8` | `cffi_get8(buf, layout, field) → u8` | Read u8 at field's offset |
| `cffi_get16` | `cffi_get16(buf, layout, field) → u16` | Read u16 at field's offset |
| `cffi_get32` | `cffi_get32(buf, layout, field) → u32` | Read u32 at field's offset |
| `cffi_get64` | `cffi_get64(buf, layout, field) → u64` | Read u64 at field's offset |
| `cffi_set8` | `cffi_set8(buf, layout, field, val)` | Write u8 at field's offset |
| `cffi_set16` | `cffi_set16(buf, layout, field, val)` | Write u16 at field's offset |
| `cffi_set32` | `cffi_set32(buf, layout, field, val)` | Write u32 at field's offset |
| `cffi_set64` | `cffi_set64(buf, layout, field, val)` | Write u64 at field's offset |

### dxgi.cyr

DXGI GPU enumeration on Windows (PE/x86_64); dispatches COM vtable methods via callptr. Windows-only (CYRIUS_TARGET_WIN).

| Function | Signature | Description |
|----------|-----------|-------------|
| `dxgi_vram_bytes` | `dxgi_vram_bytes() → bytes` | Dedicated VRAM of primary GPU (index 0) via CreateDXGIFactory1 → EnumAdapters1 → GetDesc1 |
| `dxgi_adapter_vram_bytes` | `dxgi_adapter_vram_bytes(index) → bytes` | Dedicated VRAM of adapter at index via DXGI COM dispatch |


## Testing & Internal Tooling

Test-framework helpers and internal audit/regression scaffolding.

### test.cyr

Table-driven test framework helpers. Include once to pull in lib/assert.cyr + lib/fnptr.cyr (the full unit-test stack).

| Function | Signature | Description |
|----------|-----------|-------------|
| `test_each` | `test_each(cases_vec, fp)` | Iterate through test cases (vec of pointers); call fp(case) for each |

### audit_walk.cyr

Internal tooling: shared format/lint walkers for cyrius audit + check. Skips symlinks and distlib bundles when traversing .cyr files.

| Function | Signature | Description |
|----------|-----------|-------------|
| `audit_fmt_walk` | `audit_fmt_walk(cyrfmt_path, dirs_vec)` | Run cyrfmt on every .cyr file; sets AW_FMT_FAIL, AW_FMT_SKIPPED, AW_FMT_FAIL_FILES |
| `audit_lint_walk` | `audit_lint_walk(cyrlint_path, dirs_vec)` | Run cyrlint on every .cyr file; sums warnings into AW_LINT_TOTAL, AW_LINT_SKIPPED |
| `str_starts_with_buf` | `str_starts_with_buf(buf, n, prefix) → 0/1` | Check if first n bytes of buf start with cstring prefix |

### regression.cyr

Testing-stdlib primitives: display formatting, buffer scanning, process execution, network probing, SSH cluster helpers. ~22 reusable verbs carved from programs/checks/.

| Function | Signature | Description |
|----------|-----------|-------------|
| `regression_print` | `regression_print(s)` | Write to stdout (no newline) |
| `regression_section` | `regression_section(name)` | Print section header "── name ──\n" |
| `regression_check` | `regression_check(name, exit_code) → exit_code` | Print PASS/FAIL line (0=PASS); returns exit_code |
| `regression_buf_eq` | `regression_buf_eq(p, s, n) → 0/1` | Byte-level prefix compare |
| `regression_count_substr` | `regression_count_substr(buf, n, needle) → count` | Count non-overlapping occurrences of cstring in buffer |
| `regression_file_contains_substr` | `regression_file_contains_substr(path, substr) → 0/1` | Read file and check for substring |
| `regression_pipe_to_bin_capture` | `regression_pipe_to_bin_capture(bin_path, src_path, out_path, envp) → exit` | Pipe src to binary stdin; capture stdout to file; return exit code |
| `regression_pipe_to_bin` | `regression_pipe_to_bin(bin_path, src_path, envp) → exit` | Thin wrapper: pipe to binary with /dev/null output |
| `regression_run_with_timeout` | `regression_run_with_timeout(bin_path, timeout_ms, envp) → exit` | Fork+exec with wall-clock timeout (100ms poll); returns -2 on timeout |
| `regression_exec_capture` | `regression_exec_capture(bin_path, buf, buflen, envp) → bytes` | Run binary, capture stdout; returns bytes read |
| `regression_exec_run` | `regression_exec_run(bin_path, envp) → exit` | Run binary (no args), discard I/O; return exit code |
| `regression_exec_with_arg_capture` | `regression_exec_with_arg_capture(bin_path, arg, buf, buflen, envp) → bytes` | Run binary with one arg, capture stdout |
| `regression_exec_with_arg_capture_both` | `regression_exec_with_arg_capture_both(bin_path, arg, buf, buflen, envp) → bytes` | Run binary with arg, capture stdout+stderr |
| `regression_network_probe` | `regression_network_probe(addr_ipv4, port, timeout_ms) → 0/1` | TCP reachability probe (non-blocking connect + poll) |
| `regression_ssh_target` | `regression_ssh_target(env_name, default_name) → name` | Resolve SSH target (env override or default) |
| `regression_ssh_skip_check` | `regression_ssh_skip_check(target) → 0/1` | Test SSH reachability via ssh -o BatchMode |
| `regression_scp_to` | `regression_scp_to(target, local_path, remote_path, envp) → exit` | SCP local file to remote host |
| `regression_ssh_remote_exit` | `regression_ssh_remote_exit(target, command, envp) → exit` | SSH remote command, discard I/O; return exit code |
| `regression_ssh_remote_exec_capture` | `regression_ssh_remote_exec_capture(target, command, out_path, envp) → exit` | SSH remote command, capture stdout to file |
| `regression_codesign_remote` | `regression_codesign_remote(target, remote_path, envp) → exit` | SSH remote: chmod +x && codesign -s - (macOS adhoc signing) |
| `regression_exec_in_dir3` | `regression_exec_in_dir3(work_dir, bin_path, arg1, arg2, arg3, out_path, envp) → exit` | Run binary with up to 3 args in cwd; capture stdout; trailing 0 args skipped |
| `regression_exec_in_dir3_env` | `regression_exec_in_dir3_env(work_dir, bin_path, arg1, arg2, arg3, env_extras_vec, out_path, envp) → exit` | Variant of regression_exec_in_dir3 with extra environment variables |


## Folded sibling distfiles

These modules are byte-identical folds of sibling-repo distfiles (the
sandhi pattern), vendored into `lib/<name>.cyr`. They are **opt-in** —
`include "lib/<name>.cyr"` explicitly (not auto-prepended). Each has its
own canonical API reference in its own repo; this table is a pointer. See
[ecosystem.md](ecosystem.md) for fold versions/lineage.

| Module | Folded dep | Domain |
|--------|-----------|--------|
| `lib/sandhi.cyr` | sandhi 1.9.9 | HTTP/2 + JSON-RPC + service discovery + TLS policy |
| `lib/sigil.cyr` | sigil 3.12.2 | Security / x509 / Ed25519 — powers native TLS + release/UEFI signing |
| `lib/sakshi.cyr` | sakshi 2.4.8 | Tracing / structured logging |
| `lib/patra.cyr` | patra 1.12.12 | Storage |
| `lib/sankoch.cyr` | sankoch 2.7.6 | Compression |
| `lib/yukti.cyr` | yukti 2.3.2 | Hardware enumeration |
| `lib/vani.cyr` | vani 1.1.3 | Audio (ALSA PCM + ring buffer + mixer) |
| `lib/niyama.cyr` | niyama 1.0.6 | Regex (5 engines: bre / re2 / pcre / fuzzy / vim) |
| `lib/mabda.cyr` | mabda 4.0.8 | GPU / compute (AMD-native) |
| `lib/bayan.cyr` | bayan 1.4.1 | Data formats + big-int (json / toml / cyml / csv / base64 / yaml / bigint `u256` / u128) — carved v6.1.25, `bayan_*` + legacy aliases |
| `lib/ganita.cyr` | ganita 1.0.4 | Linear algebra + advanced math (matrix / linalg / transcendental + fibonacci/binomial) — carved v6.1.26, `ganita_*` + legacy aliases |
| `lib/yantra.cyr` | yantra 1.0.2 | UI / end-to-end testing (WebDriver + Appium + Chromium-CDP RPC) |

## Platform sub-modules

Several modules dispatch to per-OS / per-arch sub-includes that are **not
documented separately** — their public surface is the parent module's (above):

- `args.cyr` → `args_win` / `args_macos` / `args_agnos`
- `process.cyr` → `process_win` / `process_agnos`
- `fs.cyr` → `fs_win` (Windows `dir_list`/`is_dir`/`dir_walk`, v6.1.18)
- `sync.cyr` → `sync_windows` / `sync_macos`
- `thread.cyr` → `thread_win` / `thread_agnos`
- `async.cyr` → `async_win` / `async_agnos`
- `regression.cyr` → `regression_agnos`
- `alloc.cyr` → `alloc_windows` / `alloc_macos` / `alloc_agnos`
- `syscalls.cyr` → `syscalls_{x86_64,aarch64}_linux` / `syscalls_windows` / `syscalls_macos` / `syscalls_x86_64_agnos` / `syscalls_linux_common`

---

> **Coverage note**: this reference documents the **core, concurrency,
> math/SIMD, crypto, data/encoding, networking (TLS + WebSocket), systems/FFI,
> and testing** surfaces — **56 of the 99 `lib/*.cyr` modules** have their own
> section here. (There are 65 `### <name>.cyr` headings, but nine of them —
> `json` / `toml` / `cyml` / `base64` / `csv` / `bigint` / `u128` / `matrix` /
> `linalg` — describe modules that were **carved out** into the `bayan` and
> `ganita` folds and no longer ship as `lib/*.cyr`. Counting headings instead
> of modules is what made this line read "roughly 65".)
>
> Of the 43 without a section, most are so by design:
> - **Folded sibling distfiles** — all **12** (`sandhi` / `sigil` / `sakshi` /
>   `patra` / `sankoch` / `yukti` / `vani` / `niyama` / `mabda` / `bayan` /
>   `ganita` / `yantra`, listed above) — the canonical API for each lives in
>   its own repo.
> - **Platform sub-modules** (`*_win` / `*_macos` / `*_agnos` / `syscalls_*`) —
>   their public surface is the parent module's.
> - The six `tls_native_*` split modules — their public surface is
>   `tls_native.cyr`'s (above).
>
> Genuinely not yet written up here, and NOT by design: `overflow.cyr`,
> `protobuf.cyr`, `sys.cyr`.
>
> **The per-module tables are curated, not exhaustive** — do not read a table as
> a module's full public surface. Measured 2026-08-07, the largest gaps are
> `simd` (75 public fns not tabulated — the f32v4/f32v8/integer-vector families
> and the flat-array packed verbs are described in prose above but not row by
> row), `str` (44, mostly the `_a` allocator-threaded variants), `chrono` (31,
> the `dt_*` datetime surface), `hashmap` (24), `async` (23), `net` (18) and
> `tls` (14, session-resumption + server-side).
>
> For any fn not listed, the source files are the canonical signature reference
> — `cyrdoc <file.cyr>` emits markdown from the doc-comment header on every
> public fn.
