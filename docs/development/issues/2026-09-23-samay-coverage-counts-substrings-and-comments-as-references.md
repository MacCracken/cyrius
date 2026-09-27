# `cyrius coverage` counts a name inside another identifier, or in a comment, as a reference, so `--min 100` passes for functions no test references — OPEN

**Status:** 🟡 **OPEN** — Verified 2026-09-23 against the 6.6.6 release binary and at HEAD
`52fabac5`: the match loop at `cbt/quality.cyr:180-181` is identical in both, and the
reproduction below passes `--min 100` with one of three functions referenced.
**Placement:** **6.6.8 bite 9** — cyrius coverage and header tell the truth: whole-identifier match over a non-code-blanked corpus, every public spelling, the file-private rule, no nested lib/ prune, whole-file reads. Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-23 during samay 1.1.5, while auditing whether samay's `rust-old/`
could be deleted.
**Severity:** Medium — a CI gate reports green for functions that no test references. A
consumer workaround exists (below).
**Affects:** the reference scan has matched raw substrings since 5.1.7; it has been a CI gate
since `--min` shipped in 6.4.72. Verified on 6.6.6, and unchanged at HEAD `52fabac5`.

## Summary

`cyrius coverage` counts a public function as referenced when its name occurs anywhere in
the concatenated `tests/**/*.tcyr` text. The match is a raw substring, so two things count
that are not references:

1. **The name inside a longer identifier.** `check_due` is "referenced" by every call to
   `check_due_at`.
2. **The name inside a comment.**

The design since 6.4.72 is that "a referenced symbol is a watched symbol" whether the test
calls the function or re-implements it (the linked-vs-mirror note in
[`archived/2026-07-23-hoosh-coverage-reports-stdlib-not-local-repo.md`](archived/2026-07-23-hoosh-coverage-reports-stdlib-not-local-repo.md)).
Neither case above fits that design: `check_due_at` does not watch `check_due`, and a comment
watches nothing. So `--min 100` reports "gate OK" for code that no test references, and the
report cannot show which functions it counted.

## Reproduction

```sh
d=$(mktemp -d) && cd "$d" && mkdir src tests
cat > src/sched.cyr <<'EOF'
fn check_due(x) { return x; }
fn check_due_at(x) { return x; }
fn str_lt(a, b) { return 0; }
EOF
cat > tests/sched.tcyr <<'EOF'
# str_lt() is only ever named in this comment.
fn main() { return check_due_at(1); }
EOF
cyrius coverage --min 100; echo "exit: $?"
```

**Expected:** 1/3 (33%), `coverage gate FAILED`, exit 1. Only `check_due_at` is referenced.

**Actual** (6.6.6):

```
  sched.cyr                         3/3 fns

-- Summary --
  Files referenced:   1/1
  Functions referenced: 3/3 (100%)  [reference coverage — a floor, not a correctness proof]
  gate OK: 100% >= --min 100%
exit: 0
```

`cyrius coverage -v` prints the same report. Nothing in the output names the functions that
were counted, or the ones that were not.

### In a real project

samay 1.1.4 (79 public functions, one suite at `tests/samay.tcyr`): the tool reported
59/79. Two of the 59 had no reference at all:

- `cron_scheduler_check_due`, which was counted through `cron_scheduler_check_due_at(`;
- `samay_str_lt`, which is named only in two comments.

The true figure was 57/79. Both gaps were found only by re-implementing the scan, because
the report gives per-file counts and never names a function. samay 1.1.5 now has a test
calling each of the 79.

## Root cause

`cbt/quality.cyr:180-181`, identical at the 6.6.6 tag and at HEAD:

```cyr
while (ci <= corpus_len - fname_len) {
    if (memeq(corpus + ci, lbuf + ns, fname_len) == 1) { found = 1; break; }
```

Nothing checks that the match begins and ends at an identifier boundary. The corpus, built at
`:81-116`, is the raw text of every `.tcyr`, comments included.

## Proposed fix

Keep reference semantics; the linked-vs-mirror decision stands. A mirror suite's
re-implementation, such as `fn foo(` in the test, still counts. Only what counts as a
reference changes:

1. **Match whole identifiers only.** After `memeq` succeeds, require that the byte before
   the match (if there is one) and the byte after it are not `[A-Za-z0-9_]`. That is two
   `load8` checks in the existing loop.
2. **Do not count comments.** When building the corpus, skip from `#` to the end of the
   line, outside string literals.
3. **Name the misses.** List the unreferenced functions under `-v`, and whenever `--min`
   fails. That list is the actionable part of a failed gate.

Each rule was simulated with GNU grep over the same corpora:

| Corpus | Today | With rule 1 | With rules 1 and 2 |
|---|---|---|---|
| The reproduction above | 3/3 | 2/3 | 1/3 |
| samay 1.1.4 | 59/79 | 58/79 | 57/79 |
| samay 1.1.5 | 79/79 | 79/79 | 79/79 |

Rule 1 can lower a project's figure only by removing a match that was never a reference.
Rule 2 lowers it wherever comments were carrying the count. That is the intended effect, but
a consumer that pins `--min` may see its figure drop on upgrade, so it is worth a ⚠ line in
the CHANGELOG. The reproduction above would make a regression case in
`tests/gates/toolchain/coverage_corpus_and_failopen.sh`, asserting 1/3 and exit 1.

## Consumer-side workaround

samay 1.1.5's CI step "Every public function is called by a test" runs the tool at 100%,
then a stricter pass. Every public function in `[lib].modules` must appear as `name(`, with
no identifier character before it, outside a comment:

```sh
cyrius coverage --min 100
calls="$(mktemp)"
sed 's/#.*$//' tests/*.tcyr > "$calls"
fail=0
for f in $(sed -n '/^\[lib\]/,/^\]/p' cyrius.cyml | grep -oE 'src/[a-z_]+\.cyr'); do
  for fn in $(grep -oE '^(pub )?fn [A-Za-z][A-Za-z0-9_]*' "$f" | awk '{print $NF}'); do
    if ! grep -qE "(^|[^A-Za-z0-9_])$fn\(" "$calls"; then
      echo "::error file=$f::public fn '$fn' is never called by a test"; fail=1
    fi
  done
done
exit $fail
```

It is stricter than the proposed fix. It requires a call, which a mirror suite's `fn foo(`
also satisfies, but a function-pointer reference `&foo` does not. Three notes for anyone
copying it:

- It strips from `#` to the end of the line, so a `#` inside a string literal truncates
  that line. That is harmless for this purpose.
- It writes the corpus to a file rather than piping `printf` into `grep -q`. Under
  `pipefail`, that pipeline reports `printf`'s SIGPIPE as "not found".
- It needs GNU grep. The `(^|…)` alternation did not match under a `grep` shell function
  from an interactive zsh profile, so run it with `bash`, as CI does.

Verified under `bash -eo pipefail` with the exact block from samay's `ci.yml`. It fails on
the samay 1.1.4 tests, on a planted untested function, and on a function mentioned only in
a test comment, where the tool alone reports `gate OK: 100%`.
