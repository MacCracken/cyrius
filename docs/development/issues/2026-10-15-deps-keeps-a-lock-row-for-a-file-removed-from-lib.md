# `cyrius deps` keeps a `cyrius.lock` row for a file removed from `lib/`, and `--locked` tells you to run the `deps` that does not drop it — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools @ 6a14eeed, the CLI built from
`cbt/cyrius.cyr` by the tree's `build/cycc`, a throwaway `CYRIUS_HOME` holding this tree's `lib/` as the pinned
snapshot). Met while fixing 2026-10-12-deps-keeps-a-removed-stdlib-leaf-vendored-and-locked.md: its consumer
workaround (`rm -rf lib/ && cyrius deps`) and the triage's proposed notice text (`rm lib/vec.cyr && cyrius deps`)
both leave the row, so the shipped notice names `rm <file> && cyrius deps --lock` instead.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — fail-closed (`deps --verify` and `--locked` both fail), but `--locked`'s remedy is false: the CI
check stays red after doing exactly what it says, and `--verify` says "the hasher could not read it" about a file
that is not there.
**Affects:** a stdlib-only project (or any resolve with no named dep: `copied == 0`) since the lock became
conditional on `_must` / `_dep_lock_new_leaf` (6.6.4 / 6.6.9). A project with a named dep re-writes the lock on every
resolve and drops the row.

## Reproduction

```sh
mkdir p && cd p
cat > cyrius.cyml <<'EOF'
[package]
name = "lockprune"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.12"

[build]
entry = "main.cyr"
output = "build/main"

[deps]
stdlib = ["syscalls", "alloc", "vec"]
EOF
printf 'syscall(SYS_EXIT, 0);\n' > main.cyr
cyrius deps
sed -i 's/, "vec"\]/]/' cyrius.cyml
rm lib/vec.cyr
cyrius deps; echo "deps rc=$?"
grep -c 'lib/vec.cyr' cyrius.lock
cyrius deps --verify; echo "verify rc=$?"
cyrius deps --locked; echo "locked rc=$?"
cyrius deps; grep -c 'lib/vec.cyr' cyrius.lock
```

Output:

```
cyrius.lock: 16 deps locked
deps rc=0
1
  FAIL: lib/vec.cyr (cannot hash: the hasher could not read it (exit 1))
15 verified, 1 failed
verify rc=1
  differs: cyrius.lock lists lib/vec.cyr, which neither lib/ nor the tags hold
error: --locked: 1 difference(s) between what the tags resolve and the committed lib/ + cyrius.lock (named above); nothing was written — run `cyrius deps` and commit the result
locked rc=1
1
```

`rm -rf lib/ && cyrius deps` gives the same: every leaf is re-vendored, none is new to the lock, so the lock is not
written and the vec row stays. `cyrius deps --lock` (or `--relock`) drops it.

## Root cause

`_deps_finish` (`cbt/deps.cyr`) writes the lock only when `copied > 0 || _dep_relock == 1 || _stamp_legacy == 1`
(`_must`) or `_dep_lock_new_leaf == 1` (a vendored leaf the lock has no line for). Nothing triggers a write for the
opposite case — a lock line for a file that is no longer in `lib/` — so the stale row survives every stdlib-only
resolve. `_deps_locked_compare`'s model of a default resolve ("a lock line for a file that exists nowhere: a default
resolve drops them", and its closing "run `cyrius deps` and commit the result") assumes a write that does not happen.
`cmd_deps_verify` hashes the missing path and reports the hasher's failure rather than "missing from lib/".

## Proposed fix

A lock row whose path is in neither `lib/` nor this resolve's closure makes the resolve write the lock (the sibling
of the 6.6.9 new-leaf rule), so `rm <file> && cyrius deps` drops it and `--locked`'s remedy is true; `--verify`
names a missing file as missing. Gate: `deps_lock_new_leaf_locked.sh` (or `deps_out_of_closure_named.sh` R1b) gains
the `rm lib/vec.cyr && cyrius deps` row.
