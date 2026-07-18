# `lib/chrono.cyr`: `DateTime` type, Rust-style `Duration` API, and strftime `format()` — IMPLEMENTED v6.4.67

> **IMPLEMENTED in v6.4.67** (CHANGELOG [6.4.67]). Landed with the proposal's recommended
> answers to its own open questions: `DateTime` = a bare epoch-ns `i64` handle; canonical
> unit = ns; strftime numeric subset (names Tier-2, deferred); `iso8601()` kept as the fast
> fixed-form path. `dt_strptime` is stricter than `iso8601_parse` — it rejects non-digit
> numeric fields. Gated by `tests/tcyr/vr01_chrono_datetime.tcyr` (29 asserts).

**Filed:** 2026-07-18 during the **samay** Rust→Cyrius port (0.2.0 parity target — samay
is a cron / resource-aware task scheduler whose every timestamp is a `chrono::DateTime<Utc>`).
**Severity:** Stdlib gap — `lib/chrono.cyr` has the *primitives* (epoch clocks, a `{secs,nsecs}`
Duration, `epoch_to_date`, fixed ISO-8601 format/parse) but no ergonomic **`DateTime`** handle,
no Rust-`chrono`-style **`Duration` unit constructors / `num_*` accessors**, no **datetime±duration
arithmetic**, and no **strftime-style `format()`**. Every consumer that ports a `DateTime<Utc>`
surface re-derives hour/minute-of-day, duration-unit conversions, and field formatting by hand.
**Affects:** `lib/chrono.cyr` (proposed home — additive, beside the existing helpers). No compiler
change required: all of this composes from the existing `epoch_to_date` / `dur_new` / `_chrono_w*`
primitives and plain i64 math.
**Target slot:** any v6.x quality-of-life stdlib patch. Additive, back-compat, no removals. User direction.

## Current state (verified 2026-07-18, cyrius 6.4.66)

`lib/chrono.cyr` already ships, and this proposal builds on it — it does **not** start from zero:

- **Clocks:** `clock_now_ns()` / `clock_now_ms()` (monotonic), `clock_epoch_secs()` / `clock_epoch_ns()` (wall).
- **Duration** (`{secs:i64, nsecs:i64}`, 16 bytes): `dur_new(secs, nsecs)`, `dur_secs(d)`, `dur_nsecs(d)`,
  `dur_to_ms(d)`, `dur_to_ns(d)`, `dur_between(start_ns, end_ns)`.
- **Civil date:** `epoch_to_date(epoch)` → 48-byte `{year@0, month@8, day@16, hour@24, min@32, sec@40}`,
  `is_leap_year(y)`.
- **ISO-8601:** `iso8601(epoch)` / `iso8601_now()` / `iso8601_parse(s)`, plus the `_chrono_w2` / `_chrono_w4`
  zero-pad writers and `_chrono_init_mdays` month table.

What is **absent** (grep of `lib/*.cyr`, 2026-07-18: no `datetime`, `strftime`, `strptime`, `dur_hours/minutes/days`):
a named `DateTime` handle + field accessors, Rust-style `Duration` unit constructors and `num_*` accessors,
`DateTime ± Duration` arithmetic, and format-string (strftime) output/parse.

## Summary — what to add

All additive to `lib/chrono.cyr`, all i64 math, **UTC only** (matches `epoch_to_date`).

### 1. `DateTime` — a wall-clock instant

Canonical scalar: **epoch nanoseconds** (i64), consistent with `clock_epoch_ns()`. A `DateTime` is
that i64 (opaque handle — no wrapper alloc needed); accessors decode via the existing `epoch_to_date`.

```cyrius
fn dt_now(): i64          { return clock_epoch_ns(); }              # Utc::now()
fn dt_from_epoch_secs(s): i64 { return s * 1000000000; }
fn dt_from_epoch_ns(ns): i64  { return ns; }
fn dt_epoch_secs(dt): i64 { return dt / 1000000000; }
fn dt_epoch_ns(dt): i64   { return dt; }

# Field accessors (UTC) — decode once via epoch_to_date(dt / 1e9)
fn dt_year(dt): i64    { return load64(epoch_to_date(dt / 1000000000)); }       # +0
fn dt_month(dt): i64   { return load64(epoch_to_date(dt / 1000000000) + 8); }   # 1-12
fn dt_day(dt): i64     { return load64(epoch_to_date(dt / 1000000000) + 16); }  # 1-31
fn dt_hour(dt): i64    { return load64(epoch_to_date(dt / 1000000000) + 24); }  # 0-23
fn dt_minute(dt): i64  { return load64(epoch_to_date(dt / 1000000000) + 32); }  # 0-59
fn dt_second(dt): i64  { return load64(epoch_to_date(dt / 1000000000) + 40); }  # 0-59
```

### 2. `Duration` — Rust-`chrono`-style constructors + `num_*` accessors

Reuse the existing `{secs,nsecs}` `dur_new` layout so old and new code interoperate.

```cyrius
fn dur_seconds(n): i64 { return dur_new(n, 0); }                 # Duration::seconds(n)
fn dur_minutes(n): i64 { return dur_new(n * 60, 0); }           # Duration::minutes(n)
fn dur_hours(n): i64   { return dur_new(n * 3600, 0); }         # Duration::hours(n)
fn dur_days(n): i64    { return dur_new(n * 86400, 0); }        # Duration::days(n)
fn dur_weeks(n): i64   { return dur_new(n * 604800, 0); }
fn dur_millis(n): i64  { return dur_new(n / 1000, (n % 1000) * 1000000); }
fn dur_nanos(n): i64   { return dur_new(n / 1000000000, n % 1000000000); }

# num_* accessors (Rust's Duration::num_seconds / num_milliseconds / ...)
fn dur_num_seconds(d): i64 { return dur_secs(d); }
fn dur_num_minutes(d): i64 { return dur_secs(d) / 60; }
fn dur_num_hours(d): i64   { return dur_secs(d) / 3600; }
fn dur_num_days(d): i64    { return dur_secs(d) / 86400; }
fn dur_num_millis(d): i64  { return dur_to_ms(d); }   # existing dur_to_ms kept as-is
fn dur_num_nanos(d): i64   { return dur_to_ns(d); }   # existing dur_to_ns kept as-is

fn dur_add(a, b): i64 { return dur_nanos(dur_to_ns(a) + dur_to_ns(b)); }
fn dur_sub(a, b): i64 { return dur_nanos(dur_to_ns(a) - dur_to_ns(b)); }
```

### 3. `DateTime ± Duration` arithmetic

```cyrius
fn dt_add(dt, dur): i64  { return dt + dur_to_ns(dur); }     # dt + Duration
fn dt_sub(dt, dur): i64  { return dt - dur_to_ns(dur); }     # dt - Duration
fn dt_diff(a, b): i64    { return dur_nanos(a - b); }        # (a - b) -> Duration
```

`dt_diff` generalizes the existing `dur_between(start_ns, end_ns)` to the `DateTime` handle;
`dur_between` stays for callers that already hold raw ns timestamps.

### 4. strftime-style `format()` (and parse)

`dt_format(dt, fmt)` walks a format string, emitting an alloc'd null-terminated `Str`. Reuses
`epoch_to_date` + the `_chrono_w2` / `_chrono_w4` writers. Proposed specifier subset (extendable):

| Spec | Meaning            | Spec | Meaning                 |
|------|--------------------|------|-------------------------|
| `%Y` | 4-digit year       | `%H` | hour 00-23              |
| `%m` | month 01-12        | `%M` | minute 00-59            |
| `%d` | day 01-31          | `%S` | second 00-59            |
| `%y` | 2-digit year       | `%j` | day-of-year 001-366     |
| `%e` | day, space-padded  | `%%` | literal `%`             |

```cyrius
fn dt_format(dt, fmt): i64 { ... }              # -> Str  (generalizes iso8601())
fn dt_strptime(s, fmt): i64 { ... }             # -> epoch ns, or -1 (mirrors iso8601_parse)
```

Weekday/month *names* (`%A %a %B %b`) and `%p` are a natural Tier-2 extension; the table above is
the minimal set the current consumers need. `iso8601(epoch)` becomes expressible as
`dt_format(dt, "%Y-%m-%dT%H:%M:%SZ")` but is kept as a fast fixed-form path.

## Why this is more than cosmetic

1. **`DateTime<Utc>` is the single most common serde/time surface in the fleet.** samay alone carries
   6 `DateTime<Utc>` fields per task plus cron time-of-day matching; anything scheduler-, log-, or
   cert-shaped hits the same wall. Without a `DateTime` handle + accessors, every port re-implements
   hour/minute-of-day extraction from raw epoch math inline.
2. **The `num_*` / unit-constructor gap is a footgun, not just boilerplate.** Hand-rolled
   `(now - last) / 1_000_000_000` "seconds" and `secs * 3600` "hours" scatter magic constants across
   consumers and invite unit mixups (ms vs ns vs s). Rust's `Duration::hours(1)` /
   `.num_milliseconds()` exist precisely to name the unit at the call site.
3. **`format("%H")` has no equivalent.** samay's cron matcher does `now.format("%H").parse::<u8>()`
   / `.format("%M")` to fire entries at a specific hour/minute. Today that forces a consumer to reach
   into `epoch_to_date`'s magic offsets (`load64(epoch_to_date(x) + 24)`) — leaking an internal struct
   layout into user code. A `dt_hour(dt)` / `dt_format(dt, "%H")` keeps the layout private.
4. **It restores parity tests.** Like the serde-derive gap, a missing `format`/parse pair means ported
   crates quietly drop their time round-trip assertions. A `dt_format` ⇄ `dt_strptime` pair lets them
   keep the invariant.

## Design notes / semantics

- **UTC only.** Matches `epoch_to_date` (already UTC) and the ports' `DateTime<Utc>`. Local time /
  timezone offset are explicitly out of scope (no locale/tz DB — consistent with chrono's minimalism).
- **Canonical unit = epoch nanoseconds (i64).** Seconds/ms helpers convert. i64 ns overflows ≈ year
  2262 (Rust `chrono` has the same 2262 `timestamp_nanos` ceiling); second-granular helpers are safe
  far beyond. On agnos the low 9 digits are zero (RTC granularity — see the existing `clock_epoch_ns`
  note); `dt_second` precision degrades gracefully, sub-second stays 0.
- **`0` is not special-cased** the way `clock_epoch_secs()` treats `0` as "unknown" — a `DateTime`
  handle is a plain instant. Consumers modeling Rust's `Option<DateTime>` use `0`/sentinel + a
  presence flag (samay uses `Option`, mapped to an i64 sentinel).
- **All integer math**, no f64. No new allocations except `dt_format`'s result Str (and the existing
  per-call `epoch_to_date` alloc — a components-cache variant `dt_parts(dt)` returning the 48-byte
  struct once is an easy optimization if accessor call-sites cluster).

## samay call sites (the trigger)

Rust `src/lib.rs` (pre-port) uses, and the port will bind to the new API as:

- `Utc::now()` → `dt_now()` — `ScheduledTask::new`, `transition`, `cancel_task`, `schedule_pending`.
- `Utc::now() + Duration::seconds(max)` → `dt_add(dt_now(), dur_seconds(max))` — `TrainingJobTemplate::to_scheduled_task`.
- `Utc::now() + Duration::hours(1)` → `dt_add(dt_now(), dur_hours(1))` — deadline tests.
- `(completed - started).num_milliseconds()` → `dur_num_millis(dt_diff(completed, started))` — `stats()`.
- `(now - last).num_seconds()` → `dur_num_seconds(dt_diff(now, last))` — cron `check_due`.
- `now.format("%H").parse::<u8>()`, `now.format("%M")` → `dt_hour(now)` / `dt_minute(now)` (or
  `dt_format(now, "%H")`) — cron `specific_hour` / `specific_minute` matching.

## Workaround until landed

samay's 0.2.0 port implements these as private helpers over the existing primitives (`clock_epoch_ns`
for `dt_now`, `epoch_to_date` for hour/minute, i64 subtraction + `dur_new` for durations/deadlines),
each cross-referencing this proposal. They collapse to the `dt_*` / `dur_*` calls above once the stdlib
versions land — a mechanical find/replace, no logic change.

## Open questions

- **`DateTime` as a bare i64 epoch-ns handle** (proposed — lightest, i64-idiomatic) **vs a named
  `struct DateTime { epoch_ns; }`** wrapper (clearer types, enables `#derive(Serialize)` to name it,
  but adds an alloc)? The port would prefer whichever the maintainer blesses as canonical.
- **Canonical unit** — ns (2262 ceiling) as proposed, or seconds (unbounded, but loses sub-second) as
  the primary, with ns as an explicit opt-in?
- **strftime subset** — is the numeric table above enough, or should Tier-1 include weekday/month
  names (`%A %a %B %b`) and `%p` up front?
- Should `iso8601()` be re-expressed over `dt_format` (one code path) or kept as the fast fixed path
  (current behavior)?
