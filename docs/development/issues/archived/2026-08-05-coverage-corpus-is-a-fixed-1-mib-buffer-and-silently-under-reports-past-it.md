# `cyrius coverage` reads the test corpus into a fixed 1 MiB buffer and silently under-reports once the corpus exceeds it

**Status:** ✅ **SHIPPED — archived 2026-08-07 at v6.5.10.** shipped v6.5.8. The fixed `alloc(1048576)` is gone from cbt/quality.cyr, replaced by grow-and-retry; three further defects were found and fixed in the same pass (an off-by-one at the corpus end, `pub fn` being invisible to the scanner, and fail-open on an empty measurement). It was mis-measuring THIS repo by 33 functions. Gate: tests/coverage_corpus_and_failopen.sh.
**Originally filed as:** shipped in 6.5.8; cyrius-side re-verified against live code on **6.5.10**
(2026-08-07): the fixed `alloc(1048576)` quoted below is gone from `cbt/quality.cyr`, replaced by a
**grow-and-retry** loop whose in-place comment names this filing and records why the filing's own
suggestion 2 ("sum the file sizes first") was not taken. Also re-verified on 6.5.9 from agnosai
2026-08-07 by this file's own repro. agnosai's corpus is 1,125,915 bytes today,
77 KB past the old cap, and padded to **1,765,916** — well beyond the 1,376,773
that used to report 85% and 64/75 files — `cyrius coverage --min 80` still reads
**75/75 files, 1099/1099 functions, 100%**. The consumer-side workaround
(`scripts/check-coverage.sh` and a corpus-size gate) is removed.
**Filed as:** filed 2026-08-05 from agnosai, whose `.tcyr` corpus crossed the buffer that day. Root cause read directly from `cbt/quality.cyr`; the size effect measured across seven corpus sizes on live 6.5.7.
**Placement:** unpinned — 6.x-line backlog (tooling behaviour, no language surface).
**Discovered:** 2026-08-05, adding ~9 KB of allocation-measurement assertions to agnosai's `tests/server_serve.tcyr`.
**Severity:** **Medium-high.** It is the fail-open direction on a **gate**: coverage under-reports, the number goes *down* silently, and `--min` still exits 0 as long as the degraded number clears the floor. A project can lose a tenth of its measured coverage to an unrelated file growing and get no signal at all.
**Affects:** cycc 6.5.7 and earlier.

## Summary

`cyrius coverage` answers "is this symbol's name referenced anywhere in the
`tests/` corpus" by concatenating every `.tcyr` into one buffer and substring-
searching it. The buffer is a **fixed 1,048,576-byte `alloc`**, and files are
read into whatever space is left. Once the corpus reaches that size, the
remaining files are truncated or dropped entirely — **with no warning, no
diagnostic, and exit 0.**

Every symbol whose only reference lived in the discarded tail then reads as
unreferenced. The reported percentage falls, but nothing distinguishes that fall
from real coverage loss, so the natural reading is "someone deleted a test".

`cbt/quality.cyr:59-73`:

```cyrius
var corpus = alloc(1048576);
var corpus_len = 0;
if (is_dir(str_from("tests")) == 1) {
    var tests = vec_new();
    dir_walk(str_from("tests"), tests);
    var ti = 0;
    while (ti < vec_len(tests)) {
        var tf = vec_get(tests, ti);
        if (str_ends_with(tf, ".tcyr") == 1) {
            var n = file_read_all(str_data(tf), corpus + corpus_len, 1048576 - corpus_len - 1);
            if (n > 0) { corpus_len = corpus_len + n; }   # <-- short read and failure are the same here
        }
        ti = ti + 1;
    }
}
```

The cap is enforced correctly — nothing overflows — but the `if (n > 0)` treats
a truncated read and a refused read identically, and neither is reported. That
is the whole defect: the **bound is right, the silence is wrong.**

## Measured

agnosai, 66 `.tcyr` files. Padding one *unrelated* suite (`tests/order.tcyr`)
with comment lines, and re-running `cyrius coverage --min 80` at each size:

| total `.tcyr` bytes | functions referenced | gate |
|---|---|---|
| 1,053,976 (agnosai today) | 1073/1073 (100%) | OK, exit 0 |
| 1,057,644 | 1073/1073 (100%) | OK, exit 0 |
| **1,057,884** | **1072/1073 (99%)** | OK, exit 0 |
| 1,073,884 | 1071/1073 (99%) | OK, exit 0 |
| 1,113,884 | 1014/1073 (94%) | OK, exit 0 |
| 1,173,884 | 955/1073 (89%) | OK, exit 0 |
| 1,253,884 | 913/1073 (85%) | OK, exit 0 |
| 1,376,773 | 913/1073 (85%), **64/75 files** | OK, exit 0 |

**Padding `order.tcyr` is what makes the first casualty conclusive.** The
function that stops being counted at 1,057,884 belongs to
`src/server/routes/approval.cyr` — a file with no relationship to `order.tcyr`
at all. Bytes added to one suite silently delete another suite's evidence,
because they compete for one buffer in `dir_walk` order.

At 1,376,773 the report is 85% and *eleven source files* are counted as entirely
unreferenced. Every one of them still has a passing suite.

## The part that matters most: a project can already be over without knowing

agnosai's corpus is **1,053,976 bytes** — 5,401 bytes past the 1,048,575 the
buffer can hold. It still reports 100%.

That is not headroom, it is **luck**. Roughly five thousand bytes are already
being discarded from the tail of whatever file `dir_walk` returns last, and they
simply do not happen to contain the sole reference to any symbol yet. The next
line added anywhere in `tests/` can turn a 100% into a 99% that has nothing to
do with what changed.

So the reported number is not merely fragile past the cap — it is **already not
measuring what it says it measures**, for any project at or above it, and there
is no way to find that out from the output.

## Repro

Any project with a `tests/` directory of `.tcyr` files:

```sh
cyrius coverage --min 80                       # note the percentage
python3 -c "
import pathlib
p = pathlib.Path('tests/<any_suite>.tcyr')
p.write_text(p.read_text().rstrip() + '\n\n' + ('#'*79+'\n')*4000)
"
cyrius coverage --min 80                       # lower percentage, same tests, exit 0
```

Total `.tcyr` bytes:

```sh
find tests -name '*.tcyr' -printf '%s\n' | awk '{s+=$1} END {print s}'
```

## Suggested fix, in the order they are worth having

1. **Say something.** Even keeping the fixed buffer, a corpus that does not fit
   should print a diagnostic naming the first dropped file and the shortfall,
   and the gate should fail rather than report a number it knows is incomplete.
   This alone converts the defect from silent-wrong to loud-limited, and it is a
   few lines.

2. **Size the buffer to the corpus.** `dir_walk` already has the file list;
   summing `file_size` before allocating removes the constant entirely. The
   corpus is transient and freed after the scan, so there is no residency
   argument for capping it.

3. **Do not build a corpus at all.** The search is per-symbol substring
   matching; scanning each file in turn against the symbol set gives the same
   answer with bounded memory and no concatenation. This is the real fix if the
   tool is expected to scale, but 1 and 2 are what unblock a project today.

Related in kind, not in code: this is the same fail-open shape as
[`2026-08-05-cyrius-bench-accepts-an-unusable-argument-and-exits-0.md`](./archived/2026-08-05-cyrius-bench-accepts-an-unusable-argument-and-exits-0.md)
— a tool that cannot do the job it was asked to do, reporting success. That one
shipped in 6.5.7. Worth triaging together as a class: **tooling should not exit
0 on a run it knows was incomplete.**

## Workaround for consumers today

Track the corpus size as a gate of your own, since the tool will not:

```sh
BYTES=$(find tests -name '*.tcyr' -printf '%s\n' | awk '{s+=$1} END {print s}')
[ "$BYTES" -lt 1048575 ] || { echo "corpus $BYTES >= 1048575 — coverage is truncating"; exit 1; }
```

Splitting the corpus does **not** help — `dir_walk` is recursive, so
`tests/tcyr/*.tcyr` lands in the same buffer as `tests/*.tcyr`. The only
effective measures are keeping test text compact or running the bulk suites from
a sibling directory via `cyrius tests <dir>` while keeping `tests/` itself under
the cap.
