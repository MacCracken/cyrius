# `cyrius package` with a missing `[build] entry` prints "package ready: build/<out>" and exits 0 with no artifact; its help row promises an `.ark` it never writes — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`,
`build/cycc` 2,057,744 B), with the CLI built from `cbt/cyrius.cyr` by that `build/cycc` and a throwaway `HOME` /
`CYRIUS_HOME`. A manifest whose `[build] entry` names a file that does not exist: `cyrius package` prints
`package ready: build/pk`, exits 0, and leaves an empty `build/` and no file; `cyrius build` in the same directory
fails by name (`error: no such file: src/nope.cyr`, rc 1). With no manifest and no `src/main.cyr`:
`version: unknown`, `package ready: build/main`, rc 0, an empty `build/`. `cyrius --help` lists
`package — create .ark distributable`; no `.ark` writer exists anywhere in the tree (`programs/ark.cyr` has no
create / pack verb; `docs/architecture/package-format.md` § *`cyrius package`* says so).
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *6.7.12*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (reported in its tools findings; the sweep rewrote
`docs/architecture/package-format.md` to what `package` does — "no `.ark` writer exists"); re-verified and filed by
the 6.7.10 planning lane.
**Severity:** Medium — a green placeholder: "package ready" and exit 0 for a package that was never built, the
shape v6.5.19 closed for a failed compile but not for a missing entry. The help row misdescribes the verb.
**Affects:** the `cyrius` CLI on every host; the missing-entry path since `package` existed, the `[build] entry`
read since 6.6.17.

## Summary

`cmd_package` compiles the entry only `if (file_exists(entry) == 1)`. When the entry is absent it skips the compile
and falls through to the success line. v6.5.19 made a FAILED compile fail (`package: entry does not compile`), but
the "nothing to compile" branch still reports ready. The `sys_mkdir("build")` runs first, so the run also leaves an
empty `build/` behind. Separately, the help row says the verb creates an `.ark` distributable; it compiles
`[build] entry` to `[build] output` and prints the project version — nothing more.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/bin" "$W/p" "$W/q" "$W/h" "$W/ch"
build/cycc < cbt/cyrius.cyr > "$W/bin/cyrius" 2>/dev/null && chmod +x "$W/bin/cyrius"; cp build/cycc "$W/bin/"
export HOME="$W/h" CYRIUS_HOME="$W/ch"
printf '[package]\nname = "pk"\nversion = "0.1.0"\n\n[build]\nentry = "src/nope.cyr"\noutput = "build/pk"\n' > "$W/p/cyrius.cyml"
( cd "$W/p" && "$W/bin/cyrius" package </dev/null; echo "rc=$?"; find . -type f -o -type d | sort )
( cd "$W/p" && "$W/bin/cyrius" build </dev/null >/dev/null 2>&1; echo "build rc=$?" )
( cd "$W/q" && "$W/bin/cyrius" package </dev/null; echo "rc=$?"; find . | sort )   # no manifest, no src/main.cyr
"$W/bin/cyrius" --help | grep -n 'package'
cd /; rm -rf "$W"
```

```
actual:   === cyrius package ===
            version: 0.1.0
            package ready: build/pk
          rc=0          (. ./build ./cyrius.cyml — no build/pk)
          build rc=1
          === cyrius package === / version: unknown / package ready: build/main / rc=0   (. ./build)
          56:  package    create .ark distributable
expected: rc 1 naming the missing entry ("error: package: no such entry: src/nope.cyr"), no build/ created;
          a help row that says what the verb does
```

## Root cause

- `cbt/deps.cyr:4373-4417` `cmd_package`: `sys_mkdir("build", …)` (`:4398`) before anything is known; the compile is
  guarded by `if (file_exists(entry) == 1)` (`:4401`) with no else; `package ready:` (`:4413-4415`) and `return 0`
  run whether or not anything was compiled.
- `cbt/cyrius.cyr:172` `_help_row("package", "create .ark distributable")`.

## Proposed fix

In `cmd_package`: refuse a missing entry by name and return 1 (the `compile()` "no such file" wording, so `build` and
`package` say the same thing), and create `build/` only on the compile path, after the entry is known to exist. Rewrite
the help row to what the verb does, from `docs/architecture/package-format.md` ("compile [build] entry to [build]
output and print the project version"). Gate rows (`tests/gates/toolchain/`): the missing-entry manifest rc 1 with the
named error and no `build/`; the no-manifest, no-`src/main.cyr` directory rc 1; a real entry still compiles to
`[build] output` (byte-identical to `cyrius build`) with `package ready:`; the help row text. Mutation: restore the
fall-through → the first two rows go RED.

Question for the user (one line, not decided here): does `cyrius package` stay a build-plus-version verb with an
honest help row, or is it retired (or given an `.ark` writer) — the fix above holds under either answer.

## Consumer-side workaround

Use `cyrius build` (which fails by name on a missing entry) and check the output file exists.
