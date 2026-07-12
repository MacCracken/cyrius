# parse_fn.cyr: return-type-error ERR_MSG passes len=93 for an 88-byte string (5-byte over-read)

**Filed:** 2026-07-11 (found during v6.4.55 while adding scalar f64 to the return-type allow-list).
**Severity:** P3 (cosmetic — a garbage-tail in one error message; no memory-safety impact beyond
reading a few bytes of adjacent read-only string data).
**Component:** `src/frontend/parse_fn.cyr` (the return-type allow-list ERR_MSG).

## Bug

The `ERR_MSG(S, "fn return type must be struct or i8/i16/i32/i64/Result/Option/Tagged/cstring/f64v2/f64v4", 93)`
call passes length **93** but the string literal is **88 bytes**, so the message printer over-reads
~5 bytes of whatever read-only data follows the literal. Visible as a garbage tail:

```
$ echo 'fn g(): SomeUnknownType { return 0; }' | cyrius build ...
error:<source>:1: fn return type must be struct or i8/i16/i32/i64/Result/Option/Tagged/cstring/f64v2/f64v4 ra:
                                                                                                          ^^^^ garbage over-read
```

(Observed as the trailing ` ra: ` in the rejection message.)

## Why it wasn't fixed inline in v6.4.55

The v6.4.55 scalar-f64-return work makes `_classify_return_type` recognize `f64` (→ -9), so `: f64`
no longer reaches this ERR_MSG at all — the message only fires now for genuinely unknown return
types. Editing the string to add `/f64` (as one design draft proposed) WITHOUT correcting `len`
would have widened the over-read; the correct fix is a standalone one: **set `len` to the true byte
length of the string** (and optionally add `/f64` to the message for accuracy, recomputing `len`).
Kept separate per one-bug-one-fix.

## Fix

Count the literal's true length and pass it (or use a strlen if one is available at that site).
If updating the message to mention `f64`, recompute the length. A quick audit of other `ERR_MSG`
call sites for hardcoded-length/string mismatches is worthwhile while here.

## Acceptance

- The return-type rejection message prints with no garbage tail.
- No over-read (length == string bytes).
