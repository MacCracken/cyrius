# `lib/chrono.cyr` gets every date before 1970-01-01 wrong, with no error — open

**Status:** 🟡 **OPEN** — verified on 6.7.18 (x86_64), 2026-11-09.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-09, by tanmatra's chrono bridge (2.0.1), whose TAI epoch is 1958-01-01
**Reporter:** tanmatra 2.0.1
**Cyrius version at time of report:** 6.7.18
**Severity:** **Medium.** No crash, but a wrong date or epoch that looks valid. Nothing in `docs/stdlib-reference.md`
or the header says the calendar starts at 1970, and `iso8601_parse` documents −1 as its only failure.

## Summary

Each calendar routine counts forward from 1970 and has no backward path:
- **`iso8601_parse` and `_chrono_ymd_to_epoch_secs`** run `while (y < yr)` from `y = 1970`. For a year before 1970
  the loop never runs, so the date is read as if it were in 1970.
  - `1958-01-01T00:00:00Z` gives **0**, which is 1970-01-01; the right value is −378,691,200.
  - `1969-12-31T23:59:59Z` gives **31,535,999**, which is 1970-12-31T23:59:59.
- **`_epoch_to_date_into`**, which backs `epoch_to_date`, `dt_year`, `dt_month`, `dt_day` and the rest, does
  `days = secs / 86400` and `rem = secs % 86400` with truncating division. Then `while (days >= yd)` never runs for
  negative days.
  - Epoch −1 decodes as **1970-01-01**, hour 0. `rem` is −1, so the hour, minute and second are 0, 0 and −1. The right
    answer is 1969-12-31T23:59:59.
  - Epoch −378,691,200 decodes as **1970-01, day −4,382**.
- **`dt_strptime`** shares `_chrono_ymd_to_epoch_secs`, and so has the same parse error. Its own validation doesn't
  catch it, because it only refuses negative fields.

The control, 1972-01-01, is right: 63,072,000.

## Reproduction

[`repros/2026-11-09-chrono-dates-before-1970-silently-wrong.cyr`](repros/2026-11-09-chrono-dates-before-1970-silently-wrong.cyr):

```sh
cyrius build docs/development/issues/repros/2026-11-09-chrono-dates-before-1970-silently-wrong.cyr /tmp/cpre
/tmp/cpre; echo "exit=$?"      # five lines marked WRONG, exit=5 on 6.7.18
```

## Proposed fix

Either of these closes it.
1. **Support dates before 1970.** In the parser, subtract the days of each year from `yr` up to 1969 when `yr < 1970`.
   In the decoder, use floor division and modulo (`days = floor(secs / 86400)`, `rem` in [0, 86400)), then walk
   years back from 1970 while `days < 0`. A days-from-civil formula (Hinnant's `days_from_civil`) replaces both loops
   and handles any year.
   - ⚠ `iso8601_parse`'s −1 sentinel is then ambiguous: −1 is 1969-12-31T23:59:59. It needs another error channel, a
     `Result` or an `err_out` word, at least for a new entry point.
2. **Declare a 1970 floor.** Document it in the header and in `docs/stdlib-reference.md`. Make `iso8601_parse` and
   `dt_strptime` return −1 for a year before 1970, and the decoder refuse a negative epoch. `dt_year` and the other
   accessors already answer −1 for an allocation failure, which is distinguishable from a year, so they could reuse it.

Either way, `tests/tcyr/stdlib/chrono.tcyr` needs cases before the epoch: −1 s, −86,400 s, 1969-12-31T23:59:59 and
1958-01-01. It has none today.

## Consumer-side workaround

tanmatra's chrono bridge (`src/bridge.cyr`) takes plain year, month and seconds values, as the Rust bridge does. It
never calls `lib/chrono.cyr`. Its header documents the `lib/chrono.cyr` recipe (year = `dt_year(dt)`,
month = `dt_month(dt)`, seconds since 1958 = `dt_epoch_secs(dt)` + 378,691,200) as holding from 1970 on only.
Before 1972 the bridge's ΔAT is 0 anyway. tanmatra's tests check the recipe from 1972 to 2035, and check the
1958 → 1970 shift through modified Julian dates instead of through `lib/chrono.cyr`.
