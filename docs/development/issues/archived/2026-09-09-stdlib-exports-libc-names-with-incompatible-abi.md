# 2026-09-09 — stdlib exports libc-reserved names (`memchr`, `strchr`, `strstr`, …) as globals with **incompatible return semantics**

**Filed by:** samvada (the AGNOS dbus client), during its 0.5.1 P(-1) audit.
**Status:** ✅ **FIXED in v6.6.2** — suggestion 1 adopted (the one that "fixes it for everyone").

> The 11 libc-reserved names cyrius's stdlib defines are now emitted **STV_HIDDEN** in both the
> `.o` symtab and the `.so` dynsym. Nothing outside the compilation unit can bind to them; the
> object's own public entry points and `_cyrius_init` are untouched.
>
> ⚠ **The symbol list was re-derived and the filing's was short by three.** Against the FULL libc
> symbol set (not just its dynamic exports, which is what hides the IFUNCs) the intersection with
> cyrius's stdlib public fns is **11**: the 8 listed plus **`getpid`, `getppid`, `gettid`**.
> Committed as a fixed list in `_fx_libc_reserved` — which names are reserved is a property of the
> language, not of the build host's libc, exactly as the filing argued.
>
> ⭐ **HIDDEN rather than LOCAL, and that is not a shortcut.** ELF requires every local symbol to
> precede every global one with `sh_info` naming the first global, so flipping the binding of an
> arbitrary subset would break that invariant and require reordering the whole symbol table.
> STV_HIDDEN keeps the binding GLOBAL and lets `ld` localize it at link time.
>
> **Verified on your repro**, not only at the symbol level: 6.6.1 times out; this build prints
> `sd_bus_default_system -> 1` / `GetSessionByPID -> 1` / `session = .../_32` with no `objcopy`.
>
> Suggestions 2-4 not taken, deliberately: (2) changing `memchr`/`strchr`/`strstr` to return
> pointers would break every in-language caller for no additional safety once the symbol cannot be
> bound externally; (3) a diagnostic is redundant once the export cannot happen; (4) the doc note
> is worth having anyway and is folded into the guide's FFI section.
>
> **Downstream:** mabda can drop the `objcopy -L` list from its Makefile once it vendors 6.6.2 —
> and should, since that list localizes `memeq` (a no-op) and omits `getenv`.

**Affects:** `lib/string.cyr` (`memchr`, `strchr`, `strstr`, `strlen`, `memcpy`, `memset`, `atoi`),
`lib/io.cyr` (`getenv`). Any `object;`-mode build that is linked against a C library.
**Checked against:** cyrius **6.6.1**, glibc 2.42, libsystemd 261, x86_64.

## What happens

A Cyrius translation unit compiled with `object;` exports these as **global `T` symbols**. When that
object is linked with a C library, the C library's calls to `memchr` bind to **Cyrius's**
implementation — and the two do not have the same contract:

| | C | Cyrius (`lib/string.cyr:76`) |
|---|---|---|
| signature | `void *memchr(const void *s, int c, size_t n)` | `fn memchr(s, c, n) -> i64` |
| found | pointer **to the byte** | **offset** from `s` |
| not found | **NULL** (`0`) | **`-1`** |

Confirmed by observation, not only by reading: localizing `memchr` and nothing else turns a hang
into a correct result (below).

Both directions are inverted:

- **Not found** — C expects `0`, gets `-1`. The caller sees a non-NULL "pointer" of
  `0xFFFFFFFFFFFFFFFF` and proceeds as if it found something.
- **Found at offset 0** — C expects `s`, gets `0`. The caller reads NULL and concludes "not found".

`strchr` (`:84`) and `strstr` (`:154`) have the identical offset-or-`-1` shape against C's
pointer-or-NULL. `strlen`, `memcpy`, `memset` and `atoi` happen to be compatible **today** by
coincidence of return value, not by design.

## How it surfaced

samvada links a Cyrius object against `libsystemd`. Without symbol localization the process
**hangs**; with `objcopy -L memchr` it works. The build is clean and the link succeeds either way,
and nothing in the failure mentions symbols.

Bisecting one symbol at a time against samvada's object:

```
  NO localization                    -> hang
  only -L memcpy                     -> hang
  only -L memset                     -> hang
  only -L memchr                     ->  0      <-- correct
  only -L strlen                     -> hang
  only -L strchr                     -> hang
  only -L strstr                     -> hang
  only -L atoi                       -> hang
```

Deterministic across repeats. **`memchr` is the symbol** — localizing it alone is sufficient, and
localizing any subset that omits it does not help.

**Two conditions are both required**, which is why this is easy to miss and was easy to
mis-diagnose:

1. **`memchr` must actually be exported by the object.** If nothing in the include chain reaches
   it, it is eliminated as unreachable, the symbol never lands in the `.o`, the C library binds to
   libc's, and there is no bug. Whether a given project trips this therefore depends on incidental
   reachability.
2. **The C library must take a call path that uses `memchr`.** `sd_bus_default_system()` alone does
   **not** reproduce — it returns cleanly with or without localization. A method call
   (`sd_bus_call_method` → `GetSessionByPID`) does.

Repro at `repros/2026-09-09-libc-name-collision/` — three files, no samvada dependency:

```
$ ./run.sh
(times out)

$ ./run.sh localize
sd_bus_default_system -> 1
GetSessionByPID -> 1
session = /org/freedesktop/login1/session/_32
```

The only difference between the two is `objcopy -L memchr app.o`.

### What was ruled out

Recorded because both are plausible and both are wrong, and the wrong ones cost time:

- **Not preemption of Cyrius's own calls.** A Cyrius object calling its own `memchr` gets the right
  answer (offset `1`) with and without localization; `objdump` shows a direct call, not a PLT
  indirection. Cyrius is not the victim here — the C library is.
- **Not `getenv`.** It is the one symbol that shows up as a straight duplicate against libc's
  dynamic exports (`comm -12` on the two symbol sets returns only `getenv`), which makes it the
  obvious suspect. Localizing `getenv` alone does not fix the hang; localizing `memchr` alone
  does.

## Why this is worse than a normal name clash

Three things make it sharp:

1. **The link succeeds.** No duplicate-symbol error, because the C library's copy is weak or in a
   not-yet-loaded shared object. The override is silent.
2. **The failure surfaces arbitrarily far away**, inside the C library, in a function the Cyrius
   author never called. A hang inside `sd_bus_call_method` gives no hint that `memchr` is involved.
3. **It is conditional on reachability**, so it appears and disappears as unrelated code is added or
   removed from the include chain. A project can link cleanly for months and then break because
   something new made `memchr` reachable.
4. **The symbol that looks guilty is not the guilty one.** `getenv` is the only straight duplicate
   against libc's dynamic exports, so the obvious derivation (below) points at it — and localizing
   it changes nothing.

This is not hypothetical: mabda already carries
`objcopy -L memcpy -L memset -L memchr -L strlen -L strchr -L strstr -L memeq -L atoi` in its
`Makefile` for its wgpu shim. That workaround has been hand-maintained, per-project, undocumented,
and its symbol list is partly wrong in both directions — it localizes `memeq` (Cyrius-only, no libc
counterpart, so a no-op) and omits `getenv` (`lib/io.cyr:889`, a real libc name).

## Suggestions, in order of preference

1. **Don't export libc-reserved names from `object;` builds.** Emit them as local symbols by
   default, or prefix them (`cyr_memchr` …) with the bare names as file-local aliases. Nothing
   outside the compilation unit should be able to bind to them.

2. **Or make the contracts match C where the name matches C.** Have `memchr` / `strchr` / `strstr`
   return a pointer (or `0`), and provide the offset-returning form under a distinct name
   (`memchr_off`, …). This is the more invasive change and would break in-language callers, but it
   removes a whole class of foot-gun rather than hiding it.

3. **At minimum, emit a diagnostic.** `object;` mode knows it is producing a relocatable; it could
   warn when a global export shadows a well-known libc symbol, and name the `objcopy -L` remedy.

4. **And document it.** Either the guide's FFI section or `object;`'s own docs should carry the
   symbol list and the `objcopy` incantation, so every consumer project does not rediscover it.

   Note that the obvious derivation is **not** sufficient — comparing the object's globals against
   libc's dynamic exports:

   ```sh
   comm -12 <(nm --defined-only app.o        | awk '$2=="T"{print $3}' | sort -u) \
            <(nm -D --defined-only libc.so.6 | awk '{print $3}' | sed 's/@.*//' | sort -u)
   ```

   returns only `getenv` on this system — because glibc's `memchr`/`memcpy`/`strlen` are IFUNCs and
   do not match a naive type filter. The list that actually matters is "every libc-reserved name the
   object exports", which is a property of the *language*, not of the local libc, and so belongs in
   the toolchain rather than in each consumer's build script.

## Note on scope

Suggestion 1 is the one that fixes it for everyone. 2–4 are fallbacks if the export behaviour has
to stay for compatibility. samvada is unblocked either way — it now documents the `objcopy` step in
`docs/guides/consumer-link.md` with the measurement above — so this is filed as a sharp edge worth
removing, not a blocker.
