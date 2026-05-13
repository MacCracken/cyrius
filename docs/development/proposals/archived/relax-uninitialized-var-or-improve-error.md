# Relax `var X;` (uninitialized) — or improve the error message

**Filed:** 2026-04-25 during `cyim` M5 fuzz-harness work
**Severity:** Low — ergonomic papercut; valid workaround exists
**Affects:** Cyrius parser, `cc5` 5.7.x

## Summary

Cyrius rejects uninitialized `var X;` declarations at function scope
with a parse error that points at the `;` token rather than at the
missing initializer:

```
error:<source>:21: expected '=', got ';'
```

The error is *correct* — Cyrius requires every `var` to carry an
initializer — but the message blames the `;` and gives no hint that
the declaration itself is the problem. Users with C / Rust / Go
muscle memory write `var X;` reflexively, and a one-line fix
(`var X = 0;`) restores compilation.

This proposal asks for one of:

1. **Relax the parser** to accept `var X;` and treat it as
   `var X = 0;` (implicit zero, matching the existing default
   i64 initializer behavior).
2. **Improve the error message** to point at the missing
   initializer rather than the `;` and to suggest the
   `var X = 0;` form.
3. Or both.

Either fix removes the surprise without changing what cyim's
codebase has to do today (it can keep writing `var X = 0;`).

## Reproduction

In a function:

```cyr
fn f() {
    var key;                  # ← parse error here
    if (cond) { key = 1; }
    else      { key = 2; }
    return key;
}
```

Compiling under `cc5 5.7.1`:

```
$ cyrius bench fuzz/driver.fcyr
warning:lib/syscalls_x86_64_linux.cyr:358: syscall arity mismatch
error:<source>:21: expected '=', got ';'
  at fail: fn=571/4096 ident=13658/131072 var=309/8192 fixup=870/32768
FAIL: compile error
```

The line number (`21`) was the include line in the consumer file,
not the actual offending `var X;` line — debugging required reading
through the included file by hand to find a single missing `= 0`.

## Why this matters

The trip-cost is small but the *frequency* is high. Any non-trivial
fuzz harness or refactor that introduces a "fill in this var across
a few branches" pattern hits it. Examples from cyim:

```cyr
# fuzz/driver.fcyr — bias-controlled keystroke choice
var key;                         # ← rejected
if ((rng_pos() & 7) < 5) {
    key = 32 + (rng_pos() % 95);
} else {
    key = rng_pos() & 0x7F;
}
```

Workaround:

```cyr
var key = 0;
```

Trivial — but only after you find the offending line, which the
current error doesn't help with.

## Recommendation

### Option A: Implicit zero (preferred)

Allow `var X;` at function scope; treat as `var X = 0;`. This
matches Cyrius's default i64 type and zero-initializes per existing
semantics. Also matches the *behavior* of `var buf[N];` (which is
already accepted at top level for fixed-size byte buffers — those
are zero-initialized by the BSS layout).

**Concerns:** none I can think of. Cyrius is i64-by-default; zero is
the natural default value.

### Option B: Better diagnostic

If A is rejected on style grounds (explicit-init is a feature, not
a bug), improve the parse error to:

```
error:<source>:21: var declaration requires an initializer
  cyim/fuzz/driver.fcyr:50: var key;
                                   ^
  hint: write `var key = 0;` if you'll assign to it later
```

The fix here is a parser-side check: when the next token after `var
<ident>` is `;`, emit a dedicated diagnostic instead of letting the
generic "expected '=', got X" message fall through.

### Option C: Both

Accept implicit-zero AND emit a stylistic warning (`-Wstyle-
uninitialized` or similar) so projects can opt into "explicit init
is mandatory" via `--strict` or a `.cyimrc`-style flag.

## Severity rationale

LOW — the workaround (`var X = 0;`) is one character. The cost is
debugging time when the error message doesn't point at the actual
problem. cyim's M5 work hit this twice in one fuzz harness; both
times took ~5 minutes to isolate from the misleading line number.

## What we're doing in cyim

cyim is keeping the `var X = 0;` form everywhere. No conditional
compilation against the future fix. When this lands in 5.7.x or
later, cyim can drop the explicit `= 0` in fuzz harnesses if the
project decides explicit-init isn't load-bearing for them — but
that's a stylistic call, not a correctness one.
