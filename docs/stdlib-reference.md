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

Bump allocator using Linux brk syscall. Call `alloc_init()` before any allocation.

| Function | Signature | Description |
|----------|-----------|-------------|
| `alloc_init` | `alloc_init() → base` | Initialize heap (must call first) |
| `alloc` | `alloc(size) → ptr` | Allocate size bytes (8-byte aligned) |
| `alloc_reset` | `alloc_reset()` | Free all allocations (batch reset) |
| `alloc_used` | `alloc_used() → bytes` | Current allocation total |

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
| `print` | `print(msg, len)` | Write to stdout |
| `eprint` | `eprint(msg, len)` | Write to stderr |

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
| `fncall0` | `fncall0(fp) → ret` | Call function pointer (0 args) |
| `fncall1` | `fncall1(fp, a) → ret` | Call with 1 arg |
| `fncall2` | `fncall2(fp, a, b) → ret` | Call with 2 args |

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

Glob matching and string search/replace.

| Function | Signature | Description |
|----------|-----------|-------------|
| `glob_match` | `glob_match(pattern, text) → 0/1` | Glob (* and ?) |
| `find_all` | `find_all(haystack, needle) → vec` | All occurrences |
| `str_replace` | `str_replace(s, old, new) → Str` | Replace first |
| `str_replace_all` | `str_replace_all(s, old, new) → Str` | Replace all |

---

## System Libraries

### syscalls.cyr

Linux syscall bindings (arch-dispatched x86_64 / aarch64). 61 syscall numbers + 65 `sys_*` wrappers (x86_64).

See [agnosys documentation](cyrius-guide.md#agnos-system-libraries) for full API.

Key functions: `sys_open`, `sys_close`, `sys_read`, `sys_write`, `sys_fork`, `sys_execve`, `sys_pipe`, `sys_waitpid`, `sys_kill`, `sys_mount`, `sys_mkdir`, `sys_rmdir`, `sys_sigprocmask`, `sys_signalfd`, `sys_epoll_create`, `sys_epoll_ctl`, `sys_epoll_wait`, `sys_timerfd_create`.

Helper functions: `sigset_new`, `sigset_add`, `sigset_has`, `epoll_event_new`, `timerspec_new`, `WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED`, `WTERMSIG`, `is_err`, `err_code`.

## Identity & Authentication

Pure-cyrius parsers for `/etc/passwd`, `/etc/group`, `/etc/shadow` that bypass glibc NSS entirely — same architectural stance musl libc takes. Added in v5.5.26 (pwd/grp) and v5.5.27 (shadow/pam) as the landing for the NSS-dispatch work that the v5.5.23-25 arc proved was not tractable through glibc's dlopen surface. See `docs/development/issues/dynlib-nss-bootstrap.md` for the full why.

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

> **Coverage note**: this reference documents the most-used core
> surface — see `lib/*.cyr` for the full ~90 first-party modules
> (concurrency: thread, thread_local, atomic, async, freelist; data:
> base64, math, matrix, linalg, bigint, u128, csv, toml, cyml; crypto:
> sha1, keccak, ct, overflow; network: net, http, ws, tls, sandhi;
> systems: mmap, dynlib, fdlopen, cffi, audio, log, chrono; vidya).
> Doc additions tracked as their consumers stabilize — the source files
> themselves are the canonical signature reference (`cyrdoc <file.cyr>`
> emits markdown from the doc-comment header on every public fn).
