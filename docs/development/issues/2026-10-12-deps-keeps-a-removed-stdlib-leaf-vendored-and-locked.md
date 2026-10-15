# `cyrius deps` keeps a stdlib leaf removed from `[deps].stdlib` vendored and locked, and nothing reports it — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (the run below): after a leaf is dropped from `[deps].stdlib`, `lib/<leaf>.cyr` and its lock row survive `cyrius deps`, and `deps --verify` passes.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-12, darshana 1.1.3: dropping its `vec` and `args` leaves at the 6.6.20 bump left both files vendored and locked until `rm -rf lib/ && cyrius deps`.
**Severity:** Low — no wrong build: auto-prepend follows `[deps].stdlib`, not `lib/`. But the vendored tree and its lock overstate the footprint, and a reviewer reading `lib/` or `cyrius.lock` to learn a project's footprint is misled.
**Affects:** 6.6.9 (first lock of a stdlib-only project) through 6.7.9.

## Summary

`cyrius deps` copies the declared closure into `lib/` and, by design, re-hashes **all** of `lib/` into
`cyrius.lock` (see [`2026-10-08-deps-before-lib-sync-stamps-new-pin.md`](2026-10-08-deps-before-lib-sync-stamps-new-pin.md)
for the other consequence of that). Nothing ever removes a file. So when a leaf leaves `[deps].stdlib`, its file stays
in `lib/`, its row stays in the lock, `--verify` agrees with both, and nothing tells the user. The only way back to
the declared footprint is `rm -rf lib/ && cyrius deps`, which is documented in no `cyrius deps` output.

Pruning cannot be unconditional: a `lib sync --full` project deliberately vendors files outside its closure. But
`deps` knows the closure it resolved and could at least name what is outside it.

## Reproduction

```sh
mkdir p && cd p
cat > cyrius.cyml <<'EOF'
[package]
name = "lockprune"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.9"

[build]
entry = "main.cyr"
output = "build/main"

[deps]
stdlib = ["syscalls", "alloc", "vec"]
EOF
printf 'syscall(SYS_EXIT, 0);\n' > main.cyr
cyrius deps                                   # "cyrius.lock: 16 deps locked"
sed -i 's/, "vec"\]/]/' cyrius.cyml           # drop the leaf
cyrius deps
grep -c 'lib/vec.cyr' cyrius.lock             # 1  — still locked
ls lib/vec.cyr                                # still vendored
cyrius deps --verify                          # "16 verified, 0 failed"
```

The same manifest resolved into an empty directory locks **15** files and vendors no `vec.cyr`: the only
difference from the run above is `lib/vec.cyr`.

## Proposed fix

Either, or both:

1. `cyrius deps` prints a notice naming each `lib/` file outside the closure it just resolved (stdlib leaves, their
   transitive includes, named deps' modules): *"lib/vec.cyr is not in the declared footprint — `rm -rf lib/ &&
   cyrius deps` to drop it"*. Silent when the project was `lib sync --full`-vendored, if that is recorded.
2. A `cyrius deps --prune` that removes those files and their lock rows.

## Consumer-side workaround

`rm -rf lib/ && cyrius deps` after any `[deps].stdlib` removal.
