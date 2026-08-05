# `cyrius bench` accepts an argument it cannot use — a directory, or a path that does not exist — and reports success

**Status:** 🟡 **OPEN** — filed 2026-08-05. Behaviour verified against live 6.5.6 the same day across all nine argument forms in the table below, exit code of each recorded.
**Placement:** unpinned — 6.x-line backlog, never 7.x (CLI/runtime behaviour). **Triage with [`2026-08-03-agnosai-build-of-a-missing-source-file-reports-OK.md`](./2026-08-03-agnosai-build-of-a-missing-source-file-reports-OK.md) — they share a root cause and the `build` fix closes most of this one.**
**Discovered:** 2026-08-05, running agnosai's benchmarks after the M7 sandbox audit remediation.
**Severity:** Low-to-medium — ergonomic, but it is the fail-open direction, and it is the second observed symptom of one underlying defect rather than an independent papercut.
**Affects:** cycc 6.5.6 and earlier.

## Summary

Of the nine argument forms below, **four run nothing at all, print no
diagnostic, and exit 0**:

| invocation | benchmarks run | summary line | exit |
|---|---|---|---|
| `cyrius bench` | 72 | `=== 6 passed, 0 failed ===` | 0 |
| `cyrius bench benches/core.bcyr` | 10 | *(none)* | 0 |
| `cyrius bench zz-fails.bcyr` (harness exits 3) | 0 | *(none)* | **3** |
| `cyrius bench tests/sandbox_policy.tcyr` | 0 | — ran the **test suite**, `102 passed` | 0 |
| `cyrius bench src/units.cyr` | 0 | *(none)* | 0 |
| `cyrius bench benches` (a directory) | **0** | *(none)* | **0** |
| `cyrius bench benches/` | **0** | *(none)* | **0** |
| `cyrius bench no-such-dir` | **0** | *(none)* | **0** |
| `cyrius bench no-such-file.bcyr` | **0** | *(none)* | **0** |

The bottom four are the problem. A directory argument, a misspelled directory
and a misspelled filename are all **indistinguishable from a successful run** —
nothing on stdout, nothing on stderr, exit 0.

The exit code is not meaningless in general: row 3 shows a file argument
propagating the harness's own status. It is only uninformative about whether the
argument was usable at all, which is the one thing a caller cannot otherwise
find out.

**Rows 4 and 5 are what explain the rest**, and they were the surprise. A file
argument is not matched against a benchmark registry at all — it is **built and
run as a program**, and "benchmarks" are simply whatever that program reported
via `bench_report`. Hand `bench` a `.tcyr` and it runs the *test suite* and
prints `102 passed, 0 failed`; hand it an ordinary `.cyr` and it runs that. So
`bench` is `build` + run with a benchmark-shaped expectation, and the four
silent rows are the case where the thing built contains nothing — see *Root
cause* below, which is not speculation once this is granted.

## Why this is worth fixing: `bench` is the only one that does it

Every sibling command refuses a bad argument loudly. Measured on the same
tree, same version:

```
$ cyrius tests tests/sandbox_policy.tcyr     # a file, where a directory is wanted
cyrius tests: not a directory: tests/sandbox_policy.tcyr
exit 1

$ cyrius tests no-such-dir
cyrius tests: not a directory: no-such-dir
exit 1

$ cyrius fmt
Usage: cyrius fmt <file.cyr> [--check]
exit 1

$ cyrius lint
Usage: cyrius lint [--strict] <file.cyr>
exit 1

$ cyrius lint no-such.cyr
=== cyrlint: no-such.cyr ===
cyrlint: cannot read file
exit 1

$ cyrius bench benches
exit 0                                        # ← nothing printed, nothing run
```

Note also that `tests` and `bench` have **inverted argument contracts** —
`tests` takes a directory and refuses a file, `bench` takes a file and ignores a
directory — which is a reasonable thing to get wrong from memory. Getting
`tests` wrong tells you so; getting `bench` wrong does not.

## The consumer failure this actually causes

A benchmark gate written the natural way is silently vacuous:

```sh
# Looks like it runs the project's benchmarks. Runs none. Exits 0.
cyrius bench benches || { echo "benchmarks failed"; exit 1; }
```

This is the same shape as the `fmt`/`lint`/`doc` "takes a FILE, not a
directory" trap that agnosai already documents as a standing hazard — except
those exit 1, so a gate that ignores the exit code passes over zero files while
one that checks it fails loudly and gets fixed. With `bench`, **both** spellings
report success.

agnosai's own `scripts/bench-history.sh` happens to be correct (it calls the
bare form), and the mistake was caught only because the run printed no rows to
compare against a recorded baseline. Nothing about the command said so.

## Reproduction

Deterministic in any project with at least one `.bcyr` under `benches/`.

```sh
cd <project-root>

# Works.
cyrius bench                       ; echo "exit=$?"   # runs everything, prints a summary
cyrius bench benches/core.bcyr     ; echo "exit=$?"   # runs one file, prints NO summary

# Runs the file as a program, whatever it is — this one runs the test suite.
cyrius bench tests/<any>.tcyr      ; echo "exit=$?"

# Silently runs nothing, exit 0, no diagnostic.
cyrius bench benches               ; echo "exit=$?"
cyrius bench benches/              ; echo "exit=$?"
cyrius bench no-such-dir           ; echo "exit=$?"
cyrius bench no-such-file.bcyr     ; echo "exit=$?"
```

Verified on cycc 6.5.6, x86-64 Linux, 2026-08-05, against agnosai
(`benches/{core,learning,orch,order,tools}.bcyr` plus `tests/agnosai.bcyr` — 6
harnesses, 72 benchmarks). The `.tcyr` row printed
`102 passed, 0 failed (102 total)` from `tests/sandbox_policy.tcyr`.

## A pattern, not a papercut — this is the second instance

[`2026-08-03-agnosai-build-of-a-missing-source-file-reports-OK.md`](./2026-08-03-agnosai-build-of-a-missing-source-file-reports-OK.md)
is the same defect in `cyrius build`: a source path that does not exist prints
`OK`, exits 0, and emits a do-nothing binary. Two commands, both accepting a
path they never opened, both reporting success.

That filing's root cause **is** this one's, not merely a parallel — see *Root
cause* below. `bench` builds and runs the file it is given, so a `bench`
argument that matched nothing is a `build` argument that matched nothing, plus a
run of the do-nothing binary that results.

**Worth triaging as one item, and the `build` fix is the load-bearing half.**
Refusing a path the compiler never opened closes both symptoms; whatever is left
after that is `bench`-specific ergonomics (the directory form, and the missing
summary line). The wider question worth asking once: should any `cyrius`
subcommand be able to consume an argument, match zero inputs, and exit 0?
`tests`, `fmt` and `lint` already answer no.

## Secondary observation, same command

**Only the no-arg form prints `=== N passed, M failed ===`.** A single-file run
prints its benchmark lines and no summary, so a script that greps for the
summary — the obvious way to check a `bench` run programmatically — finds
nothing for a form that *did* work. Whatever is decided about the argument
handling, emitting the summary in both forms would make the command scriptable.

## What is NOT a defect here, recorded so it is not "fixed" by mistake

No-arg discovery scans `benches/` and `tests/` at their **top level only**, and
that is fine — but it is worth stating, because it is easy to misread as
recursion and then "fix". Probes confirm it:

- a `.bcyr` planted at `benches/zzsub/probe.bcyr` is **not** discovered — still
  `6 passed`, and its benchmark name is absent from the output;
- a `.bcyr` planted at the repo root is **not** discovered either.

Consumers document this as "do not put `.bcyr` files in subdirectories". The ask
in this filing is only that an argument the command cannot use be **refused**,
not that discovery change.

## Root cause — behavioural, not speculative

**`cyrius bench <file>` builds and runs that file as a program.** It does not
match the argument against a benchmark registry: `cyrius bench
tests/sandbox_policy.tcyr` runs the *test suite* and prints
`102 passed, 0 failed (102 total)`, and `cyrius bench src/units.cyr` builds and
runs that. "Benchmarks run" is just whatever the program reported through
`bench_report`.

Granting that, the four silent rows are **exactly the `cyrius build` missing-file
bug with a run appended.** That filing established the mechanism: the stdlib is
auto-prepended before the entry file is read, so a path that matched nothing
still yields a valid translation unit containing the entire stdlib and no
`main` — a program that legitimately compiles and legitimately does nothing.
`bench` then runs it, it exits 0, and it reports no benchmarks because it has
none.

The compiler output confirms it: `cyrius bench no-such-dir` still emits the
`unreachable fns` note and the `large static data` warning, i.e. it **compiled
something**. It compiled the stdlib.

So this is not a `bench` argument-parsing bug in isolation. Fixing
`cyrius build` to refuse a path it never opened would close both symptoms at
once, and the `bench`-specific parts left over would be the two ergonomic items
below (a directory argument, and the missing summary line).

## Proposed fix

In priority order, because the first one is most of the value:

1. **Fix the shared root cause — make the compiler refuse a path it never
   opened.** That is the `build` filing's ask, and it turns all four silent rows
   here into a diagnostic for free. Nothing `bench`-specific is required.
2. **Decide the directory form.** Either honour it (scan its top level, the way
   the no-arg form scans `benches/`) or refuse it with
   `cyrius bench: not a benchmark file: <arg>`, exit 1. Honouring it is
   friendlier and makes the contract symmetric with `cyrius tests`, which takes
   a directory and refuses a file; refusing is the smaller change. Either is
   better than the current silence.
3. **Print the summary for every form that runs.** `=== N passed, M failed ===`
   appears only for the no-arg form, so a script checking a single-file run
   programmatically has nothing to grep.
4. **Say when nothing ran.** `cyrius bench: no benchmarks found` on a run that
   registered none. "Ran nothing" and "ran everything successfully" should never
   look alike — and note this would also catch the `.cyr`/`.tcyr` rows, where
   the command did real work that was simply not benchmarking.

Left deliberately open: whether `bench` should accept a non-`.bcyr` file at all.
It currently runs one as a program, which is arguably a feature (a one-off
harness needs no special extension) and arguably a footgun (`bench` silently
running a test suite). Worth a decision either way rather than leaving it
undocumented.

## Consumer-side workaround

None is possible beyond "always use the bare form or an explicit file path, and
never a directory". agnosai records the measured behaviour in
`docs/development/state.md` under *Known issues in the current build*, because
there is no command that would have reported it.
