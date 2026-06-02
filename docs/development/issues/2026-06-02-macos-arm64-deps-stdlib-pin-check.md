# 2026-06-02 — arm64-macOS: `[deps] stdlib` resolution false-negatives the install check (valid snapshot rejected)

**Discovered:** 2026-06-02 during the ai-hwaccel v2.3.6 macOS-arm64 wheel
build (consumer: **ai-hwaccel**, pin bumped 6.0.30 → 6.0.38).
**Severity:** High — hard failure on a shipping consumer's build, **no
workaround available** (every stopgap tried is a dead end, see below).
**Affects:** cycc/cyrius **6.0.38** arm64 Mach-O (the build that *first*
shipped a working Darwin compiler). Verified on `ecb` (Apple-silicon,
Darwin arm64, SSH-wired). Linux x86_64 with the identical manifest is
unaffected.

## Summary

On arm64 macOS, `cyrius build` aborts with a **false** "version not
installed" error whenever the manifest has BOTH a `cyrius = "<pin>"`
line AND a `[deps] stdlib = [...]` block — even though the pinned
snapshot lib is present and complete:

```
error: cyrius.cyml pins version 6.0.38 but it is not installed at
  /Users/macro/.cyrius/versions/6.0.38/lib
  run: cyrius install 6.0.38
```

The path it names *exists* and holds the full 82-file stdlib snapshot
(`ls -d ~/.cyrius/versions/6.0.38/lib` → Directory; `ls .../lib/*.cyr |
wc -l` → 82). The same toolchain compiles trivial and `[lib]`-only
projects fine, so the Mach-O codegen/runtime is healthy — the bug is
isolated to the **`[deps] stdlib` dependency-resolution path's
install-verification**, which is the only path that mis-detects the
snapshot on Darwin. This is the v6.0.38 follow-on to the arm64 packaging
fix: the compiler now ships and runs, but consumers that declare stdlib
deps (the normal case) can't build against a pinned manifest.

## Reproduction

On `ecb` (Darwin arm64), with a clean `install.sh` install of 6.0.38
(reproduced in a throwaway `CYRIUS_HOME` too — not specific to one
install):

```sh
mkdir -p /tmp/minrepro && cd /tmp/minrepro
printf 'fn main() { return 42; }\n' > main.cyr

# Snapshot is present and complete:
ls -d ~/.cyrius/versions/6.0.38/lib            # -> .../lib  (Directory)
ls ~/.cyrius/versions/6.0.38/lib/*.cyr | wc -l # -> 82
cyrius --version                               # -> cyrius 6.0.38

# --- matrix (only the [deps] stdlib + pin combo fails) ---

# T1  no manifest                          -> OK, exit 42
cyrius build main.cyr out1 && ./out1; echo $?

# T3  manifest: [package] cyrius="6.0.38"  -> OK, exit 42
# T6  + [lib] modules=["main.cyr"]         -> OK, exit 42

# T4  + [deps] stdlib=["io"]   (THE BUG)   -> error "not installed at .../lib"
cat > cyrius.cyml <<'EOF'
[package]
name = "m"
version = "0.1.0"
language = "cyrius"
cyrius = "6.0.38"
[build]
entry = "main.cyr"
output = "out4"
[deps]
stdlib = ["io"]
EOF
cyrius build main.cyr out4    # <-- false "version not installed"
```

Expected: T4 builds (snapshot is installed). Actual: T4 aborts with the
"not installed" error above. T1/T3/T6 all succeed on the *same* host, so
the snapshot is reachable — only the `[deps] stdlib` resolver rejects it.

**Platform contrast:** ai-hwaccel's real manifest (`cyrius = "6.0.38"` +
`[deps] stdlib = [string, alloc, vec, ...]`) builds cleanly on Linux
x86_64 with the same 6.0.38 toolchain and an identical 82-file snapshot.
Only Darwin arm64 false-negatives.

## UPDATE 2026-06-02 — RESOLVED on ecb; THREE distinct Darwin-ABI defects

Dug + checkpoint-bisected on ecb. There was **no single common root** (the
first pass guessed "getdents64 everywhere" — only bug 1 was that). Three
separate Darwin-ABI defects stacked, each masking the next:

- **Bug 1 — install-probe `is_dir` false-negative (FIXED, v6.0.40).**
  `_dep_find_stdlib_dir` used `is_dir(pinned_lib)`, which probes via
  `getdents64` → fails on Darwin → "not installed" on a present snapshot.
  Fixed: the probe now checks `file_exists(<lib>/syscalls.cyr)` (open-based,
  Darwin-safe). Verified on ecb: the false "not installed" error is gone,
  the requested module (`io.cyr`) resolves into `./lib`.

- **Bug 2 — `cyrius build`/`deps` SIGSYS (FIXED — pinned by checkpoint
  bisection on ecb; was TWO distinct Darwin-ABI defects, NOT dir_list).**

  > **CORRECTION of the earlier "dir_list/getdents64" claim:** that was
  > wrong. The `[deps] stdlib` resolver copies modules BY NAME — it never
  > enumerates a directory. Checkpoint-bisecting `cyrius deps` on ecb
  > pinned the real causes, both stat/getcwd-ABI, not dir listing:

  - **2a — getcwd SIGSYS (the hard crash).** After copying the stdlib by
    name, `cmd_deps` calls `_abs_path(".")` to get the consumer dir, which
    issued `syscall(79)` = x86 getcwd. The arm64-macho `ESYSXLAT` mapped
    `79 → 326` claiming "__getcwd 326" — but **Darwin has no getcwd syscall
    and slot 326 is unused** (`/* 326 */` in the SDK), so it ran an
    unimplemented syscall → SIGSYS (exit 140). The macho self-host never
    calls getcwd (cycc reads stdin), so the bogus map shipped green for 6
    minors — only the wrapper's `[deps]` path hit it.
    **Fix:** `_abs_path` now derives cwd on Darwin via
    `open(".") → fcntl(fd, F_GETPATH=50, buf) → close` (`#ifdef
    CYRIUS_TARGET_MACOS`); ESYSXLAT gains `fcntl 72→92` and drops the
    fraudulent `79→326`. Also added `getcwd 79→17` to the aarch64-**Linux**
    ESYSXLAT (there `syscall(79)` was silently `fstatat`, so `_abs_path`
    returned a relative path — latent, non-crashing).

  - **2b — transitive stdlib dropped (silent, would bite real consumers).**
    With 2a fixed, `cyrius build` succeeded and a trivial `return 42`
    binary ran — but **only `io.cyr` itself was copied; its `include`
    chain (result, syscalls, platform files) was silently dropped**, so any
    consumer actually *calling* stdlib fns would fail. Cause: the
    include-scan sizes its read with `_file_size`, which read the **Linux**
    `st_size` offset (byte 48). The raw Darwin `stat` syscall (188) fills
    the **legacy 32-bit-inode** struct where st_size is at **byte 72** (not
    48, and not the SDK INODE64 layout's 96 — verified by dumping the
    struct on ecb: `@72=8781` for an 8781-byte file). Wrong offset →
    garbage/0 size → truncated read → no `include` lines matched.
    **Fix:** `_file_size` reads byte 72 on Darwin (`#ifdef`).

  **VERIFIED on ecb (real Apple silicon), end-to-end:** `[deps]
  stdlib=["io"]` resolves all **8 transitive files**, `cyrius build`
  succeeds, and the resolved stdlib **executes** (`io.print` outputs, exit
  code correct). x86 self-host byte-identical; Linux deps unaffected (8
  files, `#else` paths). **ai-hwaccel UNBLOCKED.**

  **Separate, still-open (NOT a blocker for [deps]):** the directory-
  listing surface (`is_dir`/`dir_list` → `getdents64` = Linux 217 /
  aarch64 61) remains unported on Darwin. It does **not** affect `[deps]
  stdlib` resolution (copy-by-name) — confirmed the dep lock is not written
  for stdlib-only manifests on *any* platform. It would affect `cyrius
  update` and named/git-dep locks on macOS. A raw `getdirentries` probe
  (344/196) returned EFAULT earlier; port deferred — file/track separately.

## Root cause (speculation — flag for verification)

The `[deps] stdlib` resolver does its own "is the pinned version
installed" probe of `~/.cyrius/versions/<ver>/lib/` that is distinct from
the one the `[lib]`/no-deps path uses (T6 passes, T4 fails on the same
manifest minus `[deps]`). That probe appears to be a directory-existence
/ `readdir` / `stat` test that is miscompiled or Linux-ABI-only on the
Darwin build — it returns "absent" for a directory that demonstrably
exists. Note the binary's strings advertise two accepted layouts
(`~/.cyrius/versions/<ver>/lib/` **or** `../cyrius/lib/`); the
versions-path branch fails before the dev-layout fallback is reached (a
`../cyrius/lib` symlink does not rescue it). Likely siblings of the same
Darwin syscall-translation surface that the arm64 BSD-ABI arc
(v6.0.32–.34) and the x86 `ESYSXLAT` gap
([`2026-06-02-macos-x86-release-no-compiler.md`](./2026-06-02-macos-x86-release-no-compiler.md))
touch — here it bites the *toolchain's own* fs probe rather than emitted
code.

Pointer to start: the stdlib-deps resolution entry in `cyrius`'s build
driver (the code that prints `pins version X but it is not installed at
<path>` / `snapshot lib not found at <path>`), and whatever `is_dir`/
`readdir` helper it calls on Darwin.

## Proposed fix

Make the `[deps] stdlib` install-probe use the same snapshot-detection
the `[lib]`/no-deps path uses (which works on Darwin, per T6), or fix the
underlying Darwin directory check. Add the matrix above to the macOS
real-install gate (`cyrius audit` ecb arm) so a manifest *with `[deps]
stdlib`* — not just `fn main(){return 42;}` — is exercised; the current
trivial-build smoke test passes straight through this bug.

## Consumer-side workaround (if any)

**None found.** All stopgaps are dead ends on 6.0.38 arm64:

- **Strip the `cyrius =` pin** → `error: cannot find cyrius stdlib`
  (the pin is what points the resolver at the version's lib).
- **Strip `[deps] stdlib`** → not viable; the project needs the stdlib.
- **`../cyrius/lib` dev-layout symlink** (the binary's advertised
  fallback) → still hits the versions-path error first.
- **`CYRIUS_HOME` / `CYRIUS_RESOLVED=1`** env → no effect.
- **Clean `install.sh` into a fresh `CYRIUS_HOME`** → same failure
  (rules out a corrupt install).

Consumer impact: ai-hwaccel's macOS arm64 wheel (roadmap 2.3.6) stays
**blocked** and its CI `wheels.yml` `macos` job stays gated off — the
`macos-14` runner would hit this same error, so the gate cannot flip
until a 6.0.x fix lands. **Recommended floor for the ai-hwaccel macOS
wheel to deploy: the first 6.0.x that builds the T4 repro on `ecb`.**
