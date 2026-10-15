# `args_init` returns a prefix of the command line, with no error, when it is longer than 2 MiB — OPEN

**Status:** 🔴 **OPEN** — filed by a consumer. Verified 2026-10-14 on Linux x86_64 against the stdlib
of 6.7.9 and 6.7.11; `args_init` is byte-identical in both.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D7 — a negative errno.
**Source:** cmdit (`/home/macro/Repos/cmdit`), found by its 1.3.2 audit
(`docs/audit/2026-10-14-audit.md`, SEC-7).
**Discovered:** 2026-10-14.
**Behaviour:** silent. `argc()` / `argv(n)` describe only the start of the command line, and nothing
signals that the rest is missing.
**Affects:** `lib/args.cyr`, Linux arm (`args_init`, line 138 in 6.7.11). Every program that reads its
command line through stdlib `args`, directly or through a parser built on it.

## Summary

`args_init` allocates a 2,097,152-byte buffer and reads `/proc/self/cmdline` with a single
`sys_read`. ARG_MAX on Linux is not fixed at 2 MiB: it follows the stack limit, which an
unprivileged user can raise (`ulimit -s unlimited` gives `getconf ARG_MAX` = 6,291,456 on the host
where this was found). When the command line is longer than the buffer, `_args_len` is 2,097,152.
`argc()` counts only the NUL-terminated strings inside that prefix, so every argument whose end lies
past the cut is absent, and the partly read one is dropped whole. Nothing in the return values
distinguishes this from a command line that really was that short.

A related observation in the same function: when `/proc/self/cmdline` cannot be opened, or the
buffer cannot be allocated, `args_init` returns 0 and leaves `argc()` at 0. A caller cannot
distinguish that from an empty command line either.

## Reproduction

```cyr
# args_repro.cyr — prints argc(), the bytes args_init read, and the start of the last argument
include "lib/args.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"

fn main(): i64 {
    args_init();
    var n = argc();
    syscall(1, 1, "argc=", 5); fmt_int(n);
    syscall(1, 1, " read=", 6); fmt_int(_args_len);
    var last = argv(n - 1);
    var len = strlen(last);
    if (len > 16) { len = 16; }
    syscall(1, 1, " last=", 6); syscall(1, 1, last, len);
    syscall(1, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(60, r);
```

```sh
cyrius build args_repro.cyr build/args_repro
bash -c '
  ulimit -s unlimited
  echo "ARG_MAX=$(getconf ARG_MAX)"
  big=$(head -c 100000 /dev/zero | tr "\0" a)
  args=(); for i in $(seq 1 30); do args+=("$big"); done
  ./build/args_repro "${args[@]}" LAST     # 31 arguments after argv[0]
  ./build/args_repro small LAST            # control
'
```

Observed:

```
ARG_MAX=6291456
argc=21 read=2097152 last=aaaaaaaaaaaaaaaa
argc=3 read=110 last=LAST
```

The first run passes 32 strings (argv[0] + 31). `argc()` reports 21, the read stops at exactly
2,097,152 bytes, and the final `LAST` is not visible. The control returns every argument.

## Impact seen by a consumer

cmdit builds its argv from `argc()` / `argv(n)`. Before cmdit 1.3.2, the parse of a truncated command
line succeeded and the tool ran on the prefix. A flag appended at the end of a long command line,
for example by a wrapper of the form `exec tool "$@" --read-only`, was not seen, with no error.
cmdit 1.3.2 now treats a 2,097,152-byte read, or `argc() == 0`, as "could not read the full command
line" and refuses to parse. That is a consumer-side check only, and it does not change what
`args_init` returns. Whether this warrants a ledger id is for cyrius to classify; the filer does not
assert one.
