# `lib/chrono.cyr` writes and reads RFC 3339 in whole seconds only, and reads no offset other than `Z` — open

**Status:** 🟡 **OPEN** (feature request) — verified on 6.7.18 (x86_64), 2026-11-14.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-14, by selah's Rust → Cyrius port (M1, its history timestamps).
**Reporter:** selah 1.0.0 port (`selah/docs/development/selah-port-plan.md` §6, ledger row L5).
**Cyrius version at time of report:** 6.7.18
**Severity:** Low. Nothing is wrong in what chrono does; a port of a Rust program that stores `chrono` timestamps carries
its own RFC 3339 code meanwhile.

## Summary

`iso8601(epoch)` writes `YYYY-MM-DDTHH:MM:SSZ` and `iso8601_parse(s)` reads exactly that shape, both in whole seconds.
A Rust program that keeps `chrono::DateTime<Utc>` through serde writes and reads more than that:

- **Writing** (chrono's `Serialize`, `SecondsFormat::AutoSi`): the nanoseconds as the shortest of 0, 3, 6 or 9
  fraction digits — `2026-11-14T10:00:00.123Z`, `…00.000001Z`, `…00.000000001Z`.
- **Reading** (chrono's `DateTime<FixedOffset>::from_str`, `parse_rfc3339_relaxed`): a fraction of any length (the first
  nine digits count), an offset `±HH:MM` / `±HHMM` / `Z` / `z` / `UTC`, `T`, `t` or a space between date and time,
  whitespace around the fields, and a leap second (`:60`).

So a history file such a program wrote (`"timestamp":"2026-11-14T10:00:00.123456789Z"`) is refused by
`iso8601_parse`, and a timestamp written back through `iso8601` loses its fraction.

## What selah carries meanwhile

`selah/src/rfc3339.cyr` (about 300 lines): the AutoSi writer and an item-by-item transcription of chrono 0.4.45's
relaxed parser, pinned against chrono by 1,169 golden rows (`selah/tests/golden/rfc3339.tsv`, every row equal on
x86_64, aarch64 and x86_64 PE). It is there to be taken whole if it helps.

## Proposed shape

- `rfc3339_fmt(sb, secs, nanos)` — the AutoSi form above (and an explicit digit count, if wanted).
- `rfc3339_parse(p, n, secs_out, nanos_out)` — returns 1 / 0; strict RFC 3339 by default, with chrono's relaxed form
  behind a flag, since that is what a port of chrono-written data needs.
- Both on the proleptic Gregorian calendar for any year (see `2026-11-09-chrono-dates-before-1970-silently-wrong`).

## Consumer-side workaround

`selah/src/rfc3339.cyr`, under its `UPSTREAM(L5)` marker; it leaves when the stdlib has the two functions.
