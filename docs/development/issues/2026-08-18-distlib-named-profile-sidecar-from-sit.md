# `cyrius distlib <profile>` writes the BASE profile's sidecar path, with the BASE profile's leaf set

**Status:** 🟡 **OPEN** — reproduced against live **cycc 6.5.26** (wrapper), filed by **sit**
(v1.4.0) which ships two `distlib` profiles.

**Severity:** **Low** — packaging correctness, not a build break. A superset sidecar always
resolves, and the last writer wins with identical bytes, so nothing miscompiles today. It
defeats the *purpose* of a lean profile rather than breaking it.

## Symptom

A package with a named profile (`[lib.read]`) emits its bundle to the profile path correctly
but its **sidecar to the base path**, carrying the **base profile's leaves**:

```console
$ rm -f dist/*.deps
$ cyrius distlib          # base profile -> dist/sit.cyr
$ ls dist/*.deps
dist/sit.deps
$ cyrius distlib read     # read profile -> dist/sit-read.cyr   (bundle path IS correct)
$ ls dist/*.deps
dist/sit.deps             # <-- no dist/sit-read.deps; base sidecar OVERWRITTEN
```

Two distinct symptoms, both observed in that one run:

1. **Path** — no `dist/sit-read.deps` is ever created. The profile run rewrites
   `dist/sit.deps`.
2. **Contents** — the rewritten sidecar carries **all 38** of the package's declared leaves,
   including the six the `read` profile exists to exclude (`net`, `tls`, `tls_native`, `ws`,
   `http`, `sandhi`). The v6.4.48 per-profile `.deps` pruning (`cbt/commands.cyr:2673`) does
   not appear to take effect for a named profile.

## Why it matters to the consumer

sit's `[lib.read]` profile exists **specifically** so a read-only consumer (thoth's status
bar, owl's gutter markers) can compile the bundle without the network stack. The bundle
delivers that. The sidecar then tells `cyrius deps` to pull the whole network stdlib back in
— so a consumer that follows the sidecar, which is exactly what the sidecar is for, undoes
the profile.

## Code pointer (hypothesis — not verified by the reporter)

The sidecar emit at **`cbt/commands.cyr:3168–3186`** derives its path from `out_path`:

```cyrius
var opl = strlen(out_path);
if (opl > 4 && memeq(out_path + opl - 4, ".cyr", 4) == 1) { ... stem ... }
str_builder_add_cstr(dep_sb, ".deps");
```

That *looks* correct — for `dist/sit-read.cyr` it should yield `dist/sit-read.deps`. Since the
bundle lands at the right path but the sidecar does not, `out_path` at this point evidently
still holds the **base** bundle path when a named profile is selected, or the emit runs before
the profile output name is applied.

⚠ **Stated as a hypothesis on purpose.** The reporter verified the *behaviour* (above,
reproducible) but did not confirm the mechanism, and this repo's own re-triage rule is that a
wrong tree fact is worse than no tree fact. The two symptoms may or may not share a cause —
the pruning miss (2) could be independent of the path miss (1).

## Wanted

`dist/<name>-<profile>.deps`, scoped to the leaves that profile's own module set requires.
Base profile keeps `dist/<name>.deps` unchanged.

## Reproducer

Any package with a `[lib.X]` profile. sit is one:

```console
$ cd sit && rm -f dist/*.deps && cyrius distlib && cyrius distlib read && ls dist/*.deps
```

Expected: `dist/sit.deps` and `dist/sit-read.deps`, the latter without the network leaves.
Actual: `dist/sit.deps` only, 38 leaves.
