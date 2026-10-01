# Ecosystem

Downstream consumer repos that depend on the Cyrius toolchain.
**Refresh target**: every closeout pass (CLAUDE.md step 11),
plus whenever a port lands or a new repo joins.

## Status board

| Status | Repos |
|--------|-------|
| **Done** | agnostik, agnosys, argonaut, kybernet, nous, ark |
| **Done** | sakshi, majra, bsp, cyrius-doom, mabda, hadara |
| **Done** | sigil, patra, libro, shravan, tarang, yukti |
| **Done** | avatara, ai-hwaccel, hoosh, itihas, sankoch |
| **Done** | hisab |
| **In progress** | bhava |
| **In progress** | **bote** — MCP core service (JSON-RPC 2.0, tool registry, schema validation). Active port; unblocks vidya MCP. |
| **Blocked** | vidya MCP (needs bote) |

## Folded-in distlibs (sandhi-pattern)

> ⭐ **v6.6.0 refolded EIGHT of these in one pass** — sigil, sandhi, yukti, mabda, bayan, vani,
> yantra and sankoch — because `Result`/`Option`/`Either` became the value form and that changed
> the ARITY of every value they carry. Each was migrated **at source**, pin-bumped to cyrius
> 6.6.0, released as a patch version, and re-vendored. ⚠ The list was derived from actual
> `payload(` / `result_unwrap(` usage, not copied: an earlier survey named six and **missed
> yantra and sankoch**.
>
> ⛔ **AND THAT WAS THE SMALL VERSION OF THE SAME MISTAKE, MADE TWICE IN ONE RELEASE.** The note
> above records a survey that missed two repos and was corrected. One level up, the same release
> deleted `tagged_new()`/`payload()` on a survey **scoped to these twelve stdlibs** and wrote the
> result down as "nothing in the ecosystem". ~130 repos live under `~/Repos`; **agnostik calls
> `tagged_new` 19 times and agnova 9**, and both are DOMAIN libraries — a class this fold table
> never covered and was never meant to.
>
> ⭐ **THE SCOPE OF THIS TABLE, STATED SO IT CANNOT BE BORROWED AGAIN:** it covers the
> **fold-table stdlibs only**. It is evidence about *these repos* and about nothing else. Any
> claim about "the ecosystem" needs `tests/gates/toolchain/removed_symbol_census.sh`, which walks
> every sibling checkout including vendored `lib/` and `dist/`, and the per-repo worklist in
> [`docs/development/ecosystem-migration-6.6.2.md`](development/ecosystem-migration-6.6.2.md).
> Tracked domain consumers of the boxed primitives: **agnostik**, **agnova**, plus the five repos
> that vendor `agnostik/dist` (aethersafha, anuenue, ark, kybernet, mela).

Sibling repos vendored byte-identical into `cyrius/lib/` at a
patched tag. Removed from `[deps]` once folded. As of the mabda
3.0.1 fold (v6.0.45) there are no remaining explicit `[deps.*]`
git entries (see Live deps below).

| Lib | Folded at | Source tag | Domain |
|-----|-----------|------------|--------|
| `lib/sandhi.cyr` | v5.7.0 (refold v6.6.12, sandhi commit `88115b3`) | sandhi 1.10.4 | HTTP/2 + JSON-RPC + service discovery + TLS policy. @1.10.4 Windows never reads a drive-relative, plantable `C:\etc\resolv.conf` (CVE-57): on PE the A lookup is the stdlib's `net_resolve_ipv4` (getaddrinfo), the AAAA lookup answers 0, and 8.8.8.8 is never used (tested on cass by `tests/tcyr/crossos/sandhi_pe_resolver_no_etc_path.tcyr`). A stop-enabled server parked in `accept` now wakes on macOS, where XNU's accept ignores `SO_RCVTIMEO` (the serve loops poll a non-blocking listener there, and hand accepted fds out blocking). The four suites now run on macOS in sandhi's CI; pin 6.6.11. @1.10.3 the DNS TXID fails CLOSED when getrandom fails (CVE-19): the clock-ns fallback, fixed only in this fold on 2026-06-11 and lost at the next re-vendor, is now fixed at the source — both resolvers refuse the lookup before touching resolv.conf or a socket. @1.10.1 makes `_SANDHI_EAGAIN` and the accept errno table per target (Darwin's EAGAIN is 35 — a macOS read deadline had read as a broken connection) and declines the IPv6 open paths on Windows instead of borrowing yukti's `SYS_SOCKET`/`SYS_CONNECT`; cut during the 6.6.7 fold. @1.10.0 is a toolchain move (pin 6.6.6); its `.deps` sidecar lists `sys` because the folded sigil calls `sys_uname`. @1.9.14 adds `sandhi_client_set_resolver` — a consumer resolve hook, filed by bote 3.3.7, which had a tested SSRF classifier it could only apply to IP-literal hosts because `sandhi_http_get` resolves internally. Purely additive: no signature changes, no behaviour change without a hook installed. |
| `lib/vani.cyr` | v5.8.0 (refold v6.6.12, vani commit `4ab53a7`) | vani 1.2.8 | Audio (ALSA PCM + ring buffer + mixer). @1.2.6 `audio_open_playback` / `audio_open_capture` no longer HANG on a busy PCM (one PipeWire holds): they open `O_NONBLOCK`, so a busy device returns the null handle at once, then clear it before the first PREPARE. @1.2.7 every ALSA ioctl goes through a private `_audio_ioctl` that returns -ENOSYS on agnos, so the agnos build no longer borrows yukti's old placeholder `SYS_IOCTL = 9001` (which yukti 2.3.12 deleted); a `CYRIUS_TARGET_WIN` arm refuses the open (-1, the null handle) instead of naming `SYS_FCNTL`, which the Windows peer does not define. ⛔ Never fold 1.2.6: it does not compile for PE. @1.2.8 `vani_drain` / `vani_drop` / `vani_state` return a Result on EVERY path (the live path returned the raw `audio_*` integer, which a two-value bind read as the TAG — a device in state SETUP read as `Err`): `Ok(d)` or `Err(VANI_ERR_DRAIN / VANI_ERR_DROP)` (new codes 23 / 24), and `Ok(raw state)`; and its private `_sk_emit_err` is `_vani_sk_emit_err`, so it no longer collides with mabda's (last definition won program-wide). |
| `lib/sakshi.cyr` | v5.8.65 (refold v6.6.12, sakshi commit `9218130`) | sakshi 2.5.6 | Tracing (`_sk_fmt_int` half of the `i64::MIN` formatter class, fixed upstream @2.4.8). @2.5.4 anchors timestamps to the reference clock (MONOTONIC_RAW on Linux, QPC on Windows) at calibration, so absolute timestamps **jump once** and become comparable across processes; PE timestamps no longer run ~1.6× fast. @2.5.5 rejects a stall-stretched calibration window instead of installing a wrapped rate. @2.5.6 comment-only: the agnos clock comments name `#95` first (`#40` the fallback) and the ACPI PM timer as `#95`'s calibration reference. |
| `lib/patra.cyr` | v5.8.65 (refold v6.6.10, patra commit `589d226`) | patra 1.15.1 | Storage (@1.15.1 the CSPRNG-failure salt/db-id fallback has ns resolution — two processes falling back in one second no longer collide; thread-local slots allocator-managed @1.12.12; @1.13.0 dropped its `[deps.sakshi]` 2.4.2 pin — a folded module pinning a sakshi 8 patches behind the one this snapshot ships, silently downgrading `lib/sakshi.cyr` for every transitive consumer). @1.15.0 issues no raw syscalls and declares no OS constant of its own; its `[deps] stdlib` gains **`chrono` and `random`** (a hand-written include list must add both before `lib/patra.cyr`; DCE-off binaries grow ~16 KB). Fixed: macOS database create / WAL truncate (x86 open-flag numbers) and CSPRNG salts; Windows transactions no longer fail with `PATRA_ERR_IO` on the first write — their fdatasync goes through `xfsync` (a real flush only where xfsync's PE arm issues the `FlushFileBuffers` route). Still no crash atomicity on Windows: no `flock`, so recovery never runs on open and a crashed transaction's writes stay applied. |
| `lib/sigil.cyr` | v5.8.65 (refold v6.6.13, sigil commit `6a586c4`) | sigil 3.13.6 | Security (x509 + Ed25519 sign/verify — powers native TLS + cyrsign release signing; UEFI Secure Boot signing + enrollment; @3.13.6 (folded v6.6.13) first use is thread-safe: all 31 flag-guarded lazy initialisers claim and publish through one 0 → 1 → 2 atomic, the 15 lazily allocated scratch buffers are CAS-published, and `crypto_tls_main_init` installs a thread-local block only on a thread that has none (it no longer hands bank 0 to whichever thread arrives first); X.509 parses and verifies sha512WithRSA, parses sha1WithRSA but never verifies with it, and still refuses P-521 — so a self-signed trust anchor on either RSA algorithm installs (RFC 5280 §6.1); pin stays 6.6.9; **RSA verify authentication-bypass closed across 3.12.3-3.12.6**, the last of which needed cyrius 6.5.14's tail-call fix to be expressible). ⛔ **3.12.14 was written during this fold** — 3.12.13's subprocess work broke agnos AND Windows: `agnosys_run_capture_timeout` was guarded for agnos only (Windows has no `SYS_FCNTL` either), and `agnosys_run_checked_timeout` — added by 3.12.13 itself — had no guard at all. sigil is in every fold's preamble, so that one line broke **11 of 12** folds on agnos and the Windows builds of mabda and yukti. Fixed at SOURCE, not in the fold. ⛔ **3.12.15 was likewise written during a cyrius release** (v6.5.48): cyrius's new `write_literal_lengths` gate found `sigil_perror` declaring 25 bytes for a 26-byte literal, so `"kernel module not loaded: "` printed without its trailing space. Fixed in sigil's `src/sys_error.cyr`, all 14 bundles regenerated, then folded — never patched in the fold. sigil's pin also moved **6.5.35 → 6.5.47**, off the band carrying the v6.5.36 enum Critical. @3.13.x (folded v6.6.7) is a security release: the 8 `defer` cleanups that never ran on a value-form Result return are gone (the LUKS keyfile was left in /tmp), `sv_verify_boot_chain` and `keyring_validate_chain` fail CLOSED, GHASH / software AES are constant-time, and verification is STRICTER — `ed25519_verify` refuses small-order public keys and `ed25519_sign` returns -1 on a mismatched sk, ECDSA and Authenticode take only canonical DER, SGX/TDX quotes need exact lengths, `sv_load_trust_store` refuses group/world-writable files, `hash_file*` returns 0 on a read error. `uname_release` is no longer defined by sigil (it is lib/sys.cyr's, so the `duplicate fn` warning is gone), and @3.13.3 the bundle carries `include "lib/sys.cyr"` itself — a hand-written list no longer needs to add it. @3.13.3 `EAGAIN` is the PLATFORM's on Linux and macOS: sigil's own `EAGAIN = 11` used to replace Darwin's 35 program-wide (it stays 11 on PE and agnos, whose peers declare none). @3.13.5 (folded v6.6.12) the eight errno names whose Darwin values differ — `ENOSYS`, `ENOTEMPTY`, `ENODATA`, `EOVERFLOW`, `EOPNOTSUPP`, `EADDRINUSE`, `ECONNREFUSED`, `ETIMEDOUT` — carry the BSD values on macOS (they were Linux values program-wide there: ENOSYS 38 is Darwin's `ENOTSOCK`, ENODATA 61 Darwin's `ECONNREFUSED`), and `agnosys_run_capture_timeout` / `agnosys_run_checked_timeout` check their argv/envp allocs, so a refusal is an ENOMEM Err, not a SIGSEGV. |
| `lib/yukti.cyr` | v5.8.65 (refold v6.6.8) | yukti 2.3.14 | Hardware enumeration. @2.3.14 (`bcc8cb0`, folded byte-identical from that commit) `_yk_ppoll` declines on macOS with -ENOSYS: Darwin has no ppoll and neither Mach-O backend routes 271 / 1073, so every Mach-O build including yukti warned `not routed` and a reached call was a SIGSYS on Intel (a silent re-run of the previous syscall on Apple Silicon before 6.6.8); toolchain pin 6.6.7. @2.3.12 every raw syscall goes through a stdlib wrapper — `filesystem_usage` issued accept(2) on aarch64 (its own `SYS_STATFS = 43`, rewritten 43 -> 202) and overran its 120-byte buffer on Darwin (statfs64 is 2168 B; SIGSEGV on ach), both fixed; `enum YkSyscalls` and the agnos placeholder band (`SYS_IOCTL = 9001` …) are gone. @2.3.13 eight stdlib names it redeclared program-wide are private `_YK_*` (`O_RDONLY`, `O_NONBLOCK`, `MS_RDONLY/NOSUID/NODEV/NOEXEC`, `SOCK_DGRAM`, `SOL_SOCKET`): on Darwin its `O_NONBLOCK = 2048` had turned every `O_NONBLOCK` in the program into `O_EXCL`. ⚠ A consumer that got `SYS_IOCTL` on agnos, or `O_NONBLOCK` / `MS_*` on PE or agnos, from yukti no longer does. A PE build that reaches its socket / ioctl / mount / lstat paths links against the -ENOSYS peers in `lib/syscalls_windows.cyr` (6.6.7). |
| `lib/sankoch.cyr` | v5.8.65 (refold v6.6.5) | sankoch 2.8.0 | Compression. @2.7.9 exposes a DEFLATE **sync flush** for RFC 7692 (filed by bote; the machinery existed, only the exposure was missing) and — because measuring the newly-exposed path showed it **+64 % over reference zlib** — changes how the level >= 4 encoder picks a block type. @2.7.10 survives a caller's `alloc_reset()`. Both halves reference-verified against Python `zlib` in each direction. |
| `lib/niyama.cyr` | **v5.9.0** (refold v6.6.7) | niyama 1.0.12 | Regex (5 engines: bre / re2 / pcre / fuzzy / vim; 6,689 lines vendored). @1.0.12 is a toolchain move (pin 6.6.6) — the bundle differs from 1.0.11 only in its `# Version:` header. |
| `lib/mabda.cyr` | **v6.0.45** (refold v6.6.12, mabda commit `97679dc`) | mabda 4.1.6 | GPU/compute (AMD-native GA; array textures + cubemaps + BC arrays; samvada/chitra calls `#ifdef`-gated). @4.1.5 every ioctl goes through a private fail-closed `_mabda_ioctl` (-ENOSYS on agnos), so the agnos build no longer compiles only by borrowing yukti's old placeholder `SYS_IOCTL = 9001`; the profiler clock is `clock_now_ns()` instead of a raw `syscall(228, …)`. ⚠ **4.1.5 adds the `chrono` leaf**: a hand-written include list must add `include "lib/chrono.cyr"` before `lib/mabda.cyr`, or `clock_now_ns` is an undefined function (a trap stub) and the profiler faults at its first read. @4.1.6 two cross-fold collisions are gone: its AMD GPU vendor id is `WGPU_VENDOR_ID_AMD` (0x1002; was `PCI_VENDOR_AMD`, which yukti's `PciVendor` enum defines as 0x1022, so whichever fold came first compared against the other's value), and its private `_sk_emit_err` is `_mabda_sk_emit_err` (collided with vani's). A consumer that named mabda's `PCI_VENDOR_AMD` uses `WGPU_VENDOR_ID_AMD`. |
| `lib/bayan.cyr` | **v6.1.25** (refold v6.6.13, bayan commit `f880e35`) | bayan 1.5.10 | Data formats (@1.5.10 ⚠ `bayan_json_parse` changes what it returns for VALID input: a nested object or array is one value, its raw source span, so its members are no longer top-level pairs; TAB/CR end a bare value; malformed input stops the parse; a refused allocation returns 0, never a partial vec. `bayan_u64_mulmod` is one asm block on aarch64 (~600× faster) and correct on cx; `bayan_u64_powmod` handles exponents ≥ 2^63; a null key no longer crashes an object lookup. New `bayan_json_v_obj_get_by_cstr` and `bayan_json_parse_a`; `bayan_json_v_obj_get` / `json_v_obj_get` are `#deprecated` (they still answer the same); pin 6.6.12; @1.5.9 a refused alloc returns 0: `bayan_base64_encode` stored through it (SIGSEGV), and `bayan_toml_array_parse_a` loaded through a refused vec or handed back a short one; pin 6.6.11, coverage floor 100; @1.5.8 comment-only: the stale "callptr is a hard compile error" FlateDecode note) + big-int (json / toml / cyml / csv / base64 / **yaml** / bigint `u256` / u128; @1.5.7 the f64 parser is **correctly rounded** (an exact third tier decides near-halfway inputs), so some decoded doubles move by 1 ULP, `[2^-1075, 2^-1074)` now rounds to the smallest subnormal (was 0) and the exact overflow tie goes to +Inf (was DBL_MAX) — folded from the TAG, whose `dist/` differs from the post-tag worktree in eight comment lines; per-format sublibs @1.2.0; `bayan_json_v_obj_get_by_str` + the cstring/`Str` key contract spelled out @1.4.1; the `_toml_parse_*` family now RETURNS `Str` rather than an `i64` carrying one @1.4.2, which adds a hard `lib/str.cyr` requirement — declared in its sidecar, so a sidecar-resolved consumer is unaffected, but a hand-rolled include list that omitted `str` will now fail to parse rather than fail to link). **Carve** out of stdlib: public fns renamed `bayan_*` + legacy aliases. Consumers of `ws`/`sigil`/`patra`/`tls` (which call carved fns) must `include "lib/bayan.cyr"`. |
| `lib/ganita.cyr` | **v6.1.26** (refold v6.6.13, ganita commit `6788e28`) | ganita 1.2.11 | Linear algebra + advanced math (matrix / linalg / transcendental + fibonacci/binomial). @1.2.11 new `ganita_f64_tan`, `ganita_f32_tan` and the alias `f64_tan` (they need stdlib `math` from cyrius 6.6.9 or later); `ganita_binomial` returns −1 exactly when C(n, k) > i64_MAX (it refused representable values); `atan2` gets signed zeros, NaN at ±0 and the four infinities right; sinh / tanh / atanh / asinh / acosh / asin no longer cancel just above their small-argument cutoffs (worst errors from ~10^7 ulp to ≤ 2.18); sinh / cosh were up to 496 ulp off for 709 < \|x\| ≤ 710.48; pin 6.6.12. @1.2.10 toolchain 6.6.11 and a 100 % coverage floor. @1.2.9 `ganita_f32_sin`/`_cos` are correct past 2^63 (the NaN guard written against the pre-6.6.9 `f64_sin` is gone) and the headers no longer name the retired `lib/matrix.cyr` / `lib/linalg.cyr`. **Carve** out of stdlib (closes Phase E): renamed `ganita_*` + legacy aliases. Keep stdlib `math` in scope (f64-exp/ln polyfills + F64 constants). |
| `lib/yantra.cyr` | **v6.2.26** (refold v6.6.12, yantra commit `1095e5e`) | yantra 1.0.7 | UI/E2E testing (WebDriver + Appium + Chromium-CDP RPC). @1.0.7 `_cdp_set_nodelay` calls the stdlib `sys_setsockopt` with a stack cell: no raw `syscall(54)`, which on agnos was `SYS_UDP_UNBIND` (it now declines there), and no leaked `alloc(4)` per connect. The pin moves to 6.6.11, so yantra's standalone build uses the CVE-53-fixed `lib/ws.cyr` reader, which this fold has had since 6.6.10. yantra's `dist/` is untracked, and this fold is `cyrius distlib` at that commit (reproducible). @1.0.6 the CDP discovery request is sent whole (`sock_send_all`) or refused. Requires its dep chain in order: net / ws / bayan / sandhi / tls / sakshi / sigil. |

## Live deps (explicit `[deps.*]`)

None. As of the mabda 3.0.1 fold (v6.0.45), `cyrius.cyml` has no
explicit `[deps.*]` git entries — every former dep is now a folded
distlib (see table above). `[deps].stdlib` is the auto-prepend list
only, not git resolution.

- **mabda** — folded byte-identical into `lib/mabda.cyr` (carved at 3.0.1
  / v6.0.45; **now 4.0.8, refolded at v6.5.4**) — removed from `[deps]`; opt-in via
  `include "lib/mabda.cyr"`.
- **agnosys** — was transitive via mabda's git resolution; with mabda
  vendored it is no longer pulled (re-add `[deps.agnosys]` if a
  consumer needs it).

## Downstream server-stack arc

10-layer hardened-server stack is consumer of the Cyrius
toolchain. Current status: **kavach is the last port blocking
completion** (memory: `project_server_stack.md`). Once kavach
lands, the server OS stack is feature-complete at the consumer
layer. No direct Cyrius-compiler release targets this — progress
is tracked in consumer repos. Listed here so it's not forgotten
across account switches.

## Deferred consumer projects

- **CYIM** — postponed until the server base OS is wrapped
  (memory: `project_cyim_deferred.md`). No Cyrius release target;
  resumes when the server-stack arc above closes.
- **sandhi repo extraction** — completed at v5.7.0 fold (see
  table above). Original "before v5.6.x closeout" target was
  revised to v5.7.0 clean-break per [sandhi ADR
  0002](https://github.com/MacCracken/sandhi/blob/main/docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).

## Closeout audit checklist

Run during CLAUDE.md step 11 (vidya / docs sync) at every minor:

- [ ] Verify each **Done** repo still builds against the latest
      cyrius (their `cyrius.cyml` `cyrius` field points at the
      released tag — CLAUDE.md downstream-check, step 10).
- [ ] Move any **In progress** repo whose port landed to **Done**.
- [ ] Update fold-in lineage table when a new sibling distlib
      is vendored (e.g., niyama at v5.9.0).
- [ ] **Verify the `Source tag` column MECHANICALLY — it rots silently.**
      At the v6.4.77 fold, 5 of 11 rows were stale (sandhi 1.8.2→1.9.3,
      sankoch 2.5.5→**2.7.5**, two minors behind; vani, bayan, ganita each one
      patch). A refold that updates `lib/` but not this table leaves no trace.
      Note there are **three** header formats, so a single-pattern grep
      under-reports (it silently skips sakshi). The table is **12** rows —
      `yantra` was missing from the loop below (and from the table itself
      until v6.4.77), which is the same under-count in a different place:
      ```sh
      for f in lib/{sandhi,vani,patra,sigil,yukti,sankoch,niyama,mabda,bayan,ganita,yantra}.cyr; do
        printf '%-22s %s\n' "$f" "$(head -40 "$f" | grep -m1 -oE '# Version: *[0-9][0-9.]*')"
      done
      head -12 lib/sakshi.cyr | grep -oE 'distribution of sakshi v[0-9.]+'   # 3rd format
      ```
      Cheapest full sweep — every `lib/*.cyr` that carries any version header,
      so a new fold can't hide by not being on a hand-written list:
      ```sh
      for f in lib/*.cyr; do
        v=$(head -20 "$f" | grep -m1 -iE '^# (Version:|Bundled distribution of)')
        [ -n "$v" ] && printf '%-22s %s\n' "$f" "$v"
      done
      ```
      The `Folded at` column is NOT mechanically verifiable and may still be
      stale on rows whose `Source tag` was corrected without a matching refold
      entry — trust the CHANGELOG over that column.
- [ ] Refresh live-deps table when a `[deps.*]` entry bumps tag
      or the dep folds out of `[deps]`.
- [ ] Audit for symlink-corruption antipattern — see CLAUDE.md
      "Downstream repo setup (ecosystem rule)" for the
      `find` commands.
