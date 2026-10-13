# `cyrius distlib` records a named dep's transitive stdlib leaf as the bundle's own: a pure module's sidecar gets `boxed` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (the run below). Found by anuenue's 1.4.0 release, whose committed `dist/anuenue.deps` reads `boxed`.
**Placement:** Unplaced — filed from darshana 1.3.0's consumer releases (2026-10-12). Only the user places it.
**Discovered:** 2026-10-12, regenerating anuenue's `dist/` under 6.7.9.
**Severity:** Low — an extra leaf in a sidecar costs a consumer one unneeded `lib/boxed.cyr`, and nothing fails. But the sidecar is meant to be exactly what compile-verify proves the bundle itself needs, and this one names a leaf the bundle never uses.
**Affects:** 6.7.9 (verified). Earlier releases were not checked.

## Summary

The sidecar verify credits a symbol to a named dep when the symbol comes from one of the leaves that dep's own
sidecar lists. Every symbol below is credited that way: `alloc in scope (a named dep's) for 'alloc'`, likewise
`result`, `str`, `string`, `fmt` and `hashmap`. agnostik also calls `tagged_new`, which is defined in
`lib/boxed.cyr`. agnostik's sidecar lists `tagged`, not `boxed`; `boxed` reaches it through `tagged.cyr`'s own
include. The verify does not follow that include, so it records `boxed` as a requirement of the bundle being built.

## Reproduction

```sh
mkdir -p p/src && cd p
cat > cyrius.cyml <<'EOF'
[package]
name = "dla"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.9"

[build]
entry = "main.cyr"
output = "build/m"

[lib]
modules = ["src/a.cyr"]

[deps]
stdlib = ["syscalls"]

[deps.agnostik]
git = "https://github.com/MacCracken/agnostik.git"
tag = "1.6.0"
modules = ["dist/agnostik.cyr"]
EOF
printf '# pure\nfn pure_add(a, b): i64 { return a + b; }\n' > src/a.cyr
printf 'include "src/a.cyr"\nsyscall(SYS_EXIT, pure_add(0, 0));\n' > main.cyr
cyrius deps
cyrius distlib -v 2>&1 | grep -E "named dep's|recorded"
grep -v '^#' dist/dla.deps
```

Actual (6.7.9):

```
  sidecar verify round 1: alloc in scope (a named dep's) for 'alloc' (every target)
  sidecar verify round 1: result in scope (a named dep's) for 'Err' (every target)
  ...
  sidecar verify round 1: boxed recorded for 'tagged_new' (every target)
boxed
```

`src/a.cyr` calls nothing. Expected sidecar: empty.

## Root cause (speculation)

The "in scope (a named dep's)" check matches against the dep's sidecar leaf list. It should match against that list's
transitive include closure: the same closure `cyrius deps` Phase 3 vendors for those leaves.

## Proposed fix

Credit a symbol to a named dep when its defining file is in the include closure of the dep's sidecar leaves, not only
when it is in one of the listed leaf files.

## Consumer-side workaround

None needed for correctness. anuenue ships the extra `boxed` line.
