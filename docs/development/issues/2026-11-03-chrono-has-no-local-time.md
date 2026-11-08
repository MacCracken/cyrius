# `lib/chrono.cyr` has no local time (no tzfile, no `TZ`), so kriya's `date`, `ls -l`, `stat` and `touch -t` are UTC-only — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-03 against cyrius 6.7.18. `lib/chrono.cyr` has no `TZif`, tzfile,
`TZ` or localtime code (grep count 0). Its only 6.7.10–6.7.18 change is a cx sleep.
**Placement:** unpinned — 6.x-line backlog. A stdlib addition: `lib/chrono.cyr`, or a sibling `lib/chrono_tz.cyr`.
**Discovered:** kriya ADR 0007 (2026-05-18) named this dependency at kriya 0.7.0: "gated on an upstream
Cyrius stdlib `chrono_tz.cyr` … we prefer the upstream contribution." It was recorded only in kriya's roadmap
(§ Gated, Upstream chrono) and never filed until 2026-11-03.
⚠ The one chrono proposal upstream, `proposals/archived/2026-07-18-chrono-datetime-duration-format.md`
(samay), lists "Local time / timezone offset … explicitly out of scope". So nobody upstream had a consumer
asking for it until now.
**Severity:** Medium. POSIX `date` defaults to local time, and kriya `date` cannot. This is kriya's one
documented POSIX-default deviation. It also leaves every time kriya prints or parses in UTC.
**Affects:** every cyrius; the gap is a missing API, not a defect in an existing one.

## Summary

POSIX `date` (and GNU `ls -l`, `stat`, `touch -t`) reads time in the local zone. That zone comes from `TZ`,
or else from `/etc/localtime`. chrono offers only UTC (`epoch_to_date`, `iso8601`, `dt_*`), so kriya prints
UTC with a literal `+0000`:

```sh
# Ubuntu 26.04, tzdata installed, TZ=America/New_York, a file with mtime @1751328000:
$ stat -c %y f            # GNU coreutils 9.7
2025-06-30 20:00:00.000000000 -0400
$ kriya stat -c %y f
2025-07-01 00:00:00.000000000 +0000
$ date '+%H:%M %z %Z'      # GNU
04:39 -0500 EST
$ kriya date '+%H:%M %z %Z'
09:39 +0000 UTC
```

## What a consumer needs

All four of kriya's call sites need these:

1. **Zone resolution, in POSIX's order**: `TZ` unset → `/etc/localtime`; `TZ=:path` or `TZ=Area/City` → a
   file under `$TZDIR`, default `/usr/share/zoneinfo`; `TZ=` empty → UTC; anything else → a POSIX TZ string.
2. **A TZif reader**: v1 (32-bit) and v2/v3 (64-bit transitions plus the footer TZ string that covers
   instants past the last transition). That means the header, the transition times, the type indices, the
   `ttinfo` records (offset, isdst, abbreviation index) and the abbreviation table. Leap-second records can
   be skipped.
3. **A POSIX TZ string parser** (XBD 8.3), e.g. `EST5EDT,M3.2.0/2,M11.1.0/2`, used both for a bare `TZ`
   value and for the TZif footer. That means `std offset [dst [offset] [,rule,rule]]` with the `Mm.w.d`,
   `Jn` and `n` rule forms and `/time`.
4. **epoch → local**: `(utc_offset_seconds, is_dst, abbreviation)` for an instant. With that, an
   `epoch_to_date`-style local breakdown is one addition. It is what `date`, `ls -l` and `stat` need, and it
   gives `%z` / `%Z`.
5. **local → epoch** (`mktime`): for `touch -t [[CC]YY]MMDDhhmm[.ss]`, which POSIX defines in local time.
   It needs the spring-forward gap and fall-back overlap rules: the earlier offset for an overlap, a
   documented choice for a gap.

Suggested surface, for illustration only:

- `tz_load()` resolves the zone once and returns a handle, or 0 for UTC.
- `tz_offset_at(tz, epoch, out)` writes `{offset, isdst, abbr_ptr}`.
- `tz_epoch_from_local(tz, y, mo, d, h, mi, s, out_epoch)` returns 0, or an error for an invalid time.

On a target with no tzdata (agnos today) everything resolves to UTC, which is kriya's current behaviour.
So consumers need no `#ifdef`.

## Proposed fix

Add the reader and parser to `lib/chrono.cyr`, or a new `lib/chrono_tz.cyr` so programs that don't need
zones don't pay for them. It is about 400 lines, per kriya ADR 0007's estimate. The IANA format is RFC 8536.

## Consumer-side workaround

None that is right. kriya prints UTC with an explicit `+0000` and documents it, rather than a local offset
it cannot compute (ADR 0007, `--help`). It parses `touch -t` in UTC so that it agrees with what it prints.
When this lands, kriya flips `date`'s default to local time (with a CHANGELOG **Breaking** note) and gives
`-u` its meaning. kriya's roadmap § Gated (Upstream chrono) now points here.
