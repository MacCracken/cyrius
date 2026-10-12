# `cyrius tests` still says it "goes in the next release" three releases after the one it named — when the deprecated alias is removed — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (when `cyrius tests` is removed, or whether it stays). Verified
2026-10-12 on Linux x86_64 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744 B), with the CLI
built from `cbt/cyrius.cyr` by that `build/cycc` and a throwaway `HOME` / `CYRIUS_HOME`: `cyrius tests` in a project
with one passing `tests/a.tcyr` prints ``warn: `cyrius tests` is deprecated and goes in the next release; use
`cyrius test tests` ``, runs it, exits 0. CHANGELOG [6.7.6] made `tests` "a deprecated alias for this release";
`docs/development/ecosystem-migration.md:293` says "a deprecated alias for 6.7.6 only"; 6.7.7, 6.7.8 and 6.7.9
shipped it unchanged, and `docs/guides/cyrius-guide.md:3512` says "to be removed" with no release. No roadmap slot
names the removal.
**Placement:** 6.7.12 — repair 2, the CLI lane (roadmap.md § *6.7.12*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (its tools findings: the three notice sites); re-verified and filed
by the 6.7.10 planning lane.
**Severity:** Low — the alias works; its notice states a removal date that has passed, and three documents disagree
on when it goes.
**Affects:** the `cyrius` CLI 6.7.6 – 6.7.10 (every host).

## Summary

6.7.6 folded the directory walk into `cyrius test <file|dir>...` and kept `cyrius tests [dir]` as a one-release
deprecated alias with a one-line notice naming the exact replacement. The removal was never scheduled, so the notice,
the help row and the verb's `--help` text keep saying "the next release". Whether and when to remove a CLI verb is
the user's call; any answer also fixes the stale wording.

## The decision

- **(a) Remove it at 6.7.12 (this lane):** `cyrius tests` becomes an unknown command (rc 1, the existing
  unknown-command refusal, optionally naming `cyrius test <dir>`); the verb leaves the dispatch, the spec tables, the
  help and `_tests_verb_deprecated`; `ecosystem-migration.md` and the guide say so.
- **(b) Keep it for a stated window:** the notice, the help row and `tests --help` name the release that removes it
  (e.g. "goes in 6.8.0"), and that release carries the removal as a roadmap line.
- **(c) Keep it as a permanent alias:** drop the word "deprecated" and the removal claim from the notice, the help and
  the docs; it stays a documented spelling of `cyrius test <dir>`.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
W=$(mktemp -d); mkdir -p "$W/bin" "$W/p/tests" "$W/h" "$W/ch"
build/cycc < cbt/cyrius.cyr > "$W/bin/cyrius" 2>/dev/null && chmod +x "$W/bin/cyrius"; cp build/cycc "$W/bin/"
printf 'syscall(60, 0);\n' > "$W/p/tests/a.tcyr"
cd "$W/p"; export HOME="$W/h" CYRIUS_HOME="$W/ch"
"$W/bin/cyrius" --version
"$W/bin/cyrius" tests </dev/null; echo "rc=$?"
"$W/bin/cyrius" --help | grep -n 'tests \['
"$W/bin/cyrius" tests --help | tail -1
cd /; rm -rf "$W"
grep -n 'deprecated alias' /home/macro/Repos/cyrius/docs/development/ecosystem-migration.md
```

```
actual:   cyrius 6.7.10
          warn: `cyrius tests` is deprecated and goes in the next release; use `cyrius test tests`
          1 passed, 0 failed
          rc=0
          21:  tests [dir]      DEPRECATED: use `test <dir>` (goes in the next release)
            Deprecated: `cyrius test <dir>` is the same recursive walk; `tests` goes in the next release.
          293:- … `cyrius tests` is a deprecated alias for 6.7.6 only.
```

## Root cause

The removal was planned as "one release, then it goes (roadmap, Break 1)" (`cbt/commands.cyr:747-749`) and never
placed. The notice text lives in three places: `cbt/cyrius.cyr:134` (help row), `cbt/cli_args.cyr:340-343` (`tests
--help`), `cbt/commands.cyr:750-757` (`_tests_verb_deprecated`). The verb is also listed in `cbt/cli_args.cyr:93`,
`:118`, `:162`, `:214`, `:663`, `cbt/cyrius.cyr:713` / `:908-915`, and `cbt/manifest.cyr:1928`, `:1939`, `:2507`.

## Proposed fix

Per the option chosen. (a): remove every site above in one bite; `tests/gates/toolchain/test_absorbs_tests.sh` rows
7 / 7b (the notice) become rows asserting the refusal; the two other gates that invoke `cyrius tests`
(`build_config_precedence.sh:232`, `operands_checked_before_resolve.sh:82-84`) move to `cyrius test <dir>` or assert
the refusal; CHANGELOG + `ecosystem-migration.md` line. (b) / (c): the three text sites and the guide /
migration lines reworded, with the gate's notice row updated to the new wording. Mutation for (a): restore the
dispatch arm → the refusal row goes RED.

## Consumer-side workaround

Use `cyrius test <dir>` (bare `cyrius tests` is `cyrius test tests`), which works under every option.
