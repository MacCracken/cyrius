# `cyrius distlib`'s self-check rejects any bundle containing a slice subscript

**Status:** 🔴 OPEN — filed from a consumer (kavach), not fixed here.
**Discovered:** 2026-08-10, v6.5.16, bumping kavach's pin 6.5.10 → 6.5.16.
**Severity:** High for the affected consumers — `cyrius distlib` exits 1 and refuses to
publish a bundle that is **correct** and that compiles cleanly for a real consumer. It is
a hard CI failure with no supported workaround that preserves the consumer's code.

## The failure

```
$ cd ~/Repos/kavach && cyrius distlib
dist/kavach.deps: 36 stdlib leaf requirements
error:kavach.cyr:198:21: slice subscript requires include "lib/slice.cyr"
                         (provides _slice_idx_get_W helpers) : undef
            var c = sl[i];
                        ^
...
error: distlib: the generated bundle does not compile: dist/kavach.cyr
      (undefined fns are already downgraded — this is a REAL defect
       in the bundle, not the consumer's missing stdlib).
```

**The parenthetical is wrong, and that is the bug.** It *is* the missing stdlib.

## Isolation

Clean room — a scratch directory with no `cyrius.cyml`, so nothing is auto-prepended,
holding only `lib/`, `dist/kavach.cyr` and `dist/kavach.deps`:

| entry file | result |
|---|---|
| `include "kavach.cyr"` alone | **fails**, exactly the error above |
| the 36 leaves from `kavach.deps`, then `include "kavach.cyr"` | **OK** |

`slice` is line 35 of the 36 in `dist/kavach.deps` — the sidecar `distlib` had just
written. So the bundle is correct, the sidecar is correct and complete, and the
self-check compiles the bundle **without the leaves it just declared**.

## Why the downgrade does not cover it

The self-check's premise is that undefined *functions* are expected — a bundle names
consumer-provided stdlib symbols — so it downgrades them and treats anything left as a
real defect. That holds for every ordinary reference. In the same log:

```
warning: undefined function 'slice_set'      <- a plain fn: downgraded, fine
error: ... var c = sl[i];                    <- a SUBSCRIPT: hard error
```

`slice_set` and `sl[i]` come from the same stdlib module and the same line of consumer
code. The difference is that a subscript is **lowered by the compiler into
`_slice_idx_get_W` calls during lowering**, and that requirement is checked before the
undefined-fn downgrade can apply. So the one construct the downgrade cannot reach is the
one that is not spelled as a call.

Any bundle using `sl[i]` therefore fails the self-check, no matter how correctly it
declares `slice`.

## Why the consumer cannot work around it

kavach's two subscript sites are in `is_safe_text` / `is_safe_argument`
(`src/util.cyr:241` and `:263`), which validate **untrusted, attacker-influenced** input.
The bounds-checked read is the point, and the source says so:

> Reads the untrusted input through a bounds-checked slice (`sl[i]` lowers to the stdlib
> `_slice_idx_get_1`, which traps on out-of-range): on this security-relevant validation
> path a future off-by-one becomes a clean abort rather than an out-of-bounds read of
> attacker-influenced memory.

Rewriting those two lines as an unchecked read would turn CI green by removing a
deliberate memory-safety guard on a security boundary. That is not a workaround, it is a
regression, and it is the only consumer-side option available.

The alternatives are equally bad: pinning kavach back to 6.5.10 (abandoning the
toolchain bump), or disabling the self-check (hiding a check that does catch real bundle
defects).

## Expected

The self-check should compile the generated bundle **with the stdlib leaves it wrote to
the `.deps` sidecar**, which is exactly the environment `cyrius deps` reconstructs for a
real consumer. That is the shape the second row of the isolation table proves works.

Failing that, the slice-helper requirement should be downgradeable alongside undefined
fns, since it is the same class of thing: a symbol the consumer supplies.

## Repro

```sh
cd ~/Repos/kavach && cyrius distlib; echo "exit=$?"
```

Or from any bundle: add `var s: [u8] = 0; slice_set(&s, buf, n); var c = s[0];` to a
`[lib].modules` file and re-run `distlib`.

## Blast radius

Only bundles that use a subscript. sankoch 2.7.7's `dist/sankoch.cyr` has none and
`distlib` exits 0 there, which is why this did not surface until kavach was bumped.
Every project whose `[lib]` surface reads untrusted bytes through a bounds-checked slice
— the pattern the stdlib's own docs encourage for exactly that case — is affected.

## Notes for the fix

Worth checking the same lowering-vs-downgrade boundary for the other constructs that
lower into stdlib helper calls rather than appearing as plain calls in the source, since
they will have the identical hole: anything with a `_*_idx_*`-style helper contract.
