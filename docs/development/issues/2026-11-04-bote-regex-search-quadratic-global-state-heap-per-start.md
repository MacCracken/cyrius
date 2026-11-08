# `lib/regex.cyr`'s search is quadratic, allocates on the heap at each start, keeps its state in globals and matches bytes — OPEN

**Filed:** 2026-11-04
**Reporter:** bote v3.8.11
**Cyrius version at time of report:** 6.7.18
**Affected stdlib:** `lib/regex.cyr`
**Severity:** Medium. A consumer that searches a client's string with `regex_search` gives that client quadratic time and an unbounded heap. Any consumer with threads cannot use the module at all. It would be High if a stdlib consumer exposed it today; bote, which needed a regex engine for JSON Schema's `pattern`, wrote its own (below).
**Status:** open.

## Summary

`regex_search` / `regex_search_at` look for a match by running the whole Pike machine once from every start offset (`lib/regex.cyr:1189`, `_re_pike_run(nfa, s, len, i)` for `i` from `from` to `len`). So an unanchored search of an `n`-byte string costs O(n²) in the worst case, not O(n). Each of those runs also allocates two 160-byte save arrays with `alloc` (`_re_pike_run`, `saves_scratch` and `match_saves`) that are never given back. Measured on cyrius 6.7.18 (x86_64):
- `regex_search(regex_compile("a*z"), <20,000 a's>)` takes **44.9 s** and keeps 7.8 MB.
- `regex_search(regex_compile("z"), <60,000 a's>)` takes 12 ms and keeps **20.6 MB** of heap for good.

Three more properties stop the module serving a library that runs on threads or reads text:
- Compile state (`_re_pat`, `_re_pos`, `_re_nfa`, `_re_instr_n`, `_re_err` …) and match state (`_re_m_cur`, `_re_m_next`, `_re_m_lastgen`, `_re_m_gen`) are module globals. Two threads compiling or matching at once corrupt each other.
- A match writes its result into the compiled program (`REGEX_OFF_MATCH_START`, the saves at +56). A program shared between threads therefore races even when compiling is done once.
- It matches bytes: a class is a 256-bit bitmap (`_re_class_set` ignores `c > 255`) and the machine steps `load8(input + pos)`. Measured: `regex_match(regex_compile("^.{3}$"), "été")` is 0 (5 bytes), where `^...$` takes "abc". `^[é-ü]$` compiles and refuses "ö".

## Reproduction

```cyrius
include "lib/regex.cyr"
fn main() {
    alloc_init();
    var nfa = regex_compile("z");
    var sb = str_builder_new();
    var i = 0;
    while (i < 60000) { str_builder_add_cstr(sb, "a"); i = i + 1; }
    var s = str_data(str_builder_build(sb));
    var h0 = alloc_used();
    regex_search(nfa, s);          # 60,001 Pike runs, each allocating
    println_int(alloc_used() - h0); # 20609360 measured; with "a*z" over 20,000 a's: 44.9 s
    return 0;
}
```

## Root cause

Search is written as a loop over start positions around an anchored match, rather than as one pass. The machine's buffers are lazily allocated globals sized to `REGEX_MAX_INSTRS`, and each run's save arrays come from `alloc`.

## Proposed shape / fix

- **One pass.** Add a thread at program counter 0 at every position inside a single run, as Thompson's construction does, so search is O(n × program).
- **No state outside the call.** Put the match arrays on an allocator the caller passes (`regex_search_a(a, nfa, s, len)`), or on the stack for small programs. Return the match position instead of storing it in the NFA. Take the compiler's state in a struct.
- **Code points** as an option (`REGEX_UNICODE`): decode UTF-8, and store classes as ranges.

## Consumer-side workaround

bote 3.8.11 ships `src/regex.cyr`: an ECMA-262 `u`-flag parser and a one-pass Thompson machine over code points. The machine's arrays come from the caller's arena and are given back, and each step is charged to a budget. bote does not include `lib/regex.cyr`, and its names (`bote_rx_*`, `_brx_*`) do not collide with the module's `_re_*`.

## Severity rationale

Medium today: the defect is real, and no in-tree consumer is known to search untrusted text with it. Raise it if one does, or if the module is advertised for server use.

## Related issues

None filed against `lib/regex.cyr` before this.

## Pointers

- `lib/regex.cyr:1040` (`_re_pike_run`), `:1189` (`regex_search_at`), `:218` (the match globals), `:207` (the compile globals).
- bote `src/regex.cyr` (3.8.11), and its differential against JavaScript, `scripts/regex-diff.sh`.
