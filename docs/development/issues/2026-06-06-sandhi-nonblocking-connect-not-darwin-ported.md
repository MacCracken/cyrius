# `sandhi` non-blocking connect (and SO_RCVTIMEO) use Linux-only constants → spurious `SANDHI_ERR_CONNECT` on macOS

- **Filed**: 2026-06-06
- **Reporter**: yantra (downstream consumer; iOS/XCUITest e2e on a GitHub Apple-Silicon runner, driving a local Appium server)
- **Affects**: `lib/sandhi.cyr` on **aarch64 macOS** (Mach-O). **Linux is unaffected.** Seen with the 6.0.66 stdlib snapshot.
- **Severity**: any `sandhi_http_*` call that sets `connect_ms > 0` cannot connect on macOS, even to a listening localhost server.

## Symptom

yantra's iOS Appium session-create (`POST http://127.0.0.1:4723/session` via
`sandhi_http_post_opts` with `connect_ms=15000`, `read_ms/total_ms=420000`)
fails on the macOS runner with sandhi error kind **`2` (`SANDHI_ERR_CONNECT`)**
— the *same* error you get with nothing listening — even though Appium is up and
a plain `curl` `POST /session` to the identical URL/caps returns **HTTP 200**.

yantra instrumented its own client to prove the request never leaves: it reports
`stage=2 errkind=2/CONNECT status=0` (i.e. `sandhi_http_err_kind != 0`, no HTTP
status ever received). The same `sandhi_http_post_opts` path drives the **Android**
Appium e2e on Linux and works 4/4 — so it is macOS-specific, at the connect step.

## Root cause

`sandhi_conn_open_*` chooses a connect path on `connect_ms`
(`lib/sandhi.cyr:1968`):

```
if (connect_ms > 0) {
    var nbr = _sandhi_conn_connect_sa_nb_a(a, fd, sa, 28, connect_ms);  // non-blocking
    ...
} else {
    var rc = syscall(SYS_CONNECT, fd, sa, 28);                          // blocking
    ...
}
```

The **non-blocking** path uses constants declared (and commented) as Linux-only
(`lib/sandhi.cyr:1514-1532`):

```
var _SANDHI_SYS_POLL       = 7;
var _SANDHI_SYS_GETSOCKOPT = 55;
var _SANDHI_F_GETFL        = 3;
var _SANDHI_F_SETFL        = 4;
var _SANDHI_O_NONBLOCK     = 2048;   # 0x800  — Linux
var _SANDHI_EINPROGRESS    = 115;    #          Linux
var _SANDHI_SO_ERROR       = 4;
```

On Darwin these differ:
- `O_NONBLOCK` is **`0x0004`**, not `0x800`. `fcntl(fd, F_SETFL, 0x800)` sets the
  wrong flag, so the socket may not actually be non-blocking (and `0x800` is
  `O_APPEND`-ish noise).
- A connect-in-progress sets `errno` **`EINPROGRESS = 36`** on Darwin, not `115`
  (`115` is Linux). sandhi checks for `115`, doesn't see it, and classifies the
  in-progress connect as a hard failure → `_SANDHI_CONN_NB_ERR` →
  `SANDHI_CONN_OPEN_CONNECT` → `SANDHI_ERR_CONNECT`.

The in-source comment already flags this (`:1514-1518`): *"Linux x86_64 syscall
numbers; aarch64 differs … when aarch64 support becomes a goal it needs a
cross-cutting pass … SYS_SETSOCKOPT=54 in net.cyr is already x86_64-only."*

### Latent second bug (same family): SO_RCVTIMEO

`_sandhi_conn_set_timeout_ms_a` (`:1568-`) sets read/write timeouts with Linux
constants too: `_SANDHI_SO_RCVTIMEO = 20` / `_SANDHI_SO_SNDTIMEO = 21` and a
Linux `struct timeval` layout, under (presumably) `SOL_SOCKET = 1`. On Darwin
`SO_RCVTIMEO = 0x1006`, `SO_SNDTIMEO = 0x1005`, `SOL_SOCKET = 0xFFFF`, and
`timeval` is `{ time_t sec (8), suseconds_t usec (4) }`. So `read_ms`/`write_ms`
are effectively **not applied** on macOS (the setsockopt fails with the wrong
level/optname). It didn't surface for yantra only because the connect failed
first; any macOS consumer relying on a recv/send timeout is affected.

(`net.cyr` was already Darwin-ported for the *option-constant* values in 6.0.59 —
e.g. `SockOpt { SOL_SOCKET=0xFFFF, SO_RCVTIMEO=0x1006, … }` under
`#ifdef CYRIUS_TARGET_MACOS` — but `sandhi.cyr` carries its **own** hardcoded
Linux copies that were not ported.)

## Repro

On an Apple-Silicon macOS host with any listening localhost HTTP server on
`:4723`:

```
# pseudo: sandhi_http_post_opts(url, headers, body, len, opts)
#   where opts has connect_ms = 15000
# -> returns err_kind = 2 (SANDHI_ERR_CONNECT), no HTTP status
# Set connect_ms = 0 on the same opts -> connects fine (blocking path).
```

A plain `curl -X POST http://127.0.0.1:4723/session …` against the same server
succeeds, isolating it to sandhi's non-blocking connect.

## Suggested fix (cyrius-side)

Darwin-port sandhi's socket constants + the timeval layout, mirroring what
`net.cyr` already does, and route the aarch64 syscall numbers:
- `#ifdef CYRIUS_TARGET_MACOS`: `O_NONBLOCK = 0x0004`, `EINPROGRESS = 36`,
  `SO_RCVTIMEO = 0x1006`, `SO_SNDTIMEO = 0x1005`, `SOL_SOCKET = 0xFFFF`, Darwin
  `timeval` ({sec:i64, usec:i32}).
- aarch64 syscall numbers for `poll`/`getsockopt`/`fcntl`/`setsockopt` (the
  Mach-O backend already reroutes several of these — `poll 7→230`,
  `setsockopt 54→105`, `getsockopt 55`, `fcntl 72` are in `_macho_arm_routes`).
- Consider sharing one Darwin-aware socket-constant module between `net.cyr` and
  `sandhi.cyr` so this can't drift again.

## Downstream workaround (in place, yantra 0.6.2)

yantra now sets `connect_ms = 0` in `wd_connect_timeout` (its Appium POST), which
takes sandhi's **blocking** connect path (`syscall(SYS_CONNECT)`, Darwin-routed)
— fine because Appium is always localhost. This unblocks the iOS e2e without the
non-blocking connect. The read side relies on the response arriving before any
(currently unenforced-on-macOS) recv timeout would matter; for the iOS session
that's a ~55s wait that a blocking recv handles. Remove the workaround once
sandhi's connect/timeout path is Darwin-ported and `connect_ms>0` works on macOS.
