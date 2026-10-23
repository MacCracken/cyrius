# Security audit — 2026-10-22 (cyrius 6.7.17 → 6.7.18)

The full audit the 2–3-minor rule owed (the last: `2026-09-03-security-audit.md` at 6.5.45), run at the 6.7.18 open on the
6.7.17 tree. **Method:** eight read-only scanners, one per attack surface of CLAUDE.md § *Security Audit Process* —
the native TLS stack; net / http / ws / DNS and the libssl path; the folds sandhi, sigil and bayan (read at their
upstream sources); local users and the filesystem; the release and download channel; auth helpers and secrets — each
finding then re-checked once by an independent verifier who rebuilt the repro from scratch. **28 findings:** 27 confirmed,
1 uncertain. **13 vulnerabilities** take ids `CYRIUS-2026-0038` – `0050` (two findings are one: the X.509
nameConstraints gap seen from sigil's parser and from the native TLS verifier, `0042`); the rest are bugs and
hardening (no id). Every finding is fixed in 6.7.18 unless its row says otherwise; each section's **Status** names the
fix when it lands. The probes are in `~/.cache/l6718/audit/` (scanners) and `~/.cache/l6718/audit/verify-*/` (verifiers).

User decisions at the audit (2026-10-22): bayan refuses invalid base64, malformed / out-of-range JSON numbers and
duplicate JSON keys by name; `cyrius deps` refuses plaintext `git://` / `http://` URLs; `lib/pam.cyr` keeps `nullok`
for now (refusing empty passwords is planned: "keep nullok but plan it refuse empty as a part of 2.8.0 work"); the
`ach` self-hosted CI job stays (GitHub has no x86 macOS runner) behind the repository's fork-PR approval setting.

## Summary

| # | id | kind | sev | surface | finding | verifier |
|---|---|---|---|---|---|---|
| 1 | `CYRIUS-2026-0038` | vulnerability | P1 | net-http-ws-dns | async DNS label encoder overruns its 288-byte stack query buffer: an attacker-chosen hostname smashes the resolver task's stack | confirmed |
| 2 | `CYRIUS-2026-0039` | vulnerability | P2 | release-channel | Fork PRs can run code on the self-hosted 'ach' runner: the only guard is an `if:` inside the workflow file the PR itself controls | confirmed |
| 3 | `CYRIUS-2026-0040` | vulnerability | P2 | auth-secrets | sigil ChaCha20-Poly1305 accepts forged records (all-zero tag) when two threads share a crypto lane: the streaming Poly1305 state is a proces | confirmed |
| 4 | `CYRIUS-2026-0041` | vulnerability | P2 | auth-secrets | lib/tls.cyr's libssl backend runs the INVOKING user's $HOME/.cyrius/dlopen-helper in-process: fdlopen_init_full has no setuid / AT_SECURE ch | confirmed |
| 5 | `CYRIUS-2026-0042` | vulnerability | P2 | sigil | X.509 chain verifier ignores nameConstraints (RFC 5280 §6.1 path-validation gap; the CYRIUS-2026-0002 class) | confirmed |
| 6 | `CYRIUS-2026-0042` | vulnerability | P2 | tls-native | Native TLS chain verifier ignores a CA's X.509 nameConstraints: a non-critically name-constrained intermediate under a trusted root can impe | confirmed |
| 7 | `CYRIUS-2026-0043` | vulnerability | P2 | net-http-ws-dns | ws_server's receive buffer is a single process-global, so two concurrent WebSocket connections in a multi-threaded server read and echo each | confirmed |
| 8 | `CYRIUS-2026-0044` | vulnerability | P2 | sandhi | HPACK decoder accepts an unbounded Dynamic-Table-Size-Update: peer grows the client's decode table with no limit and amplifies a 16 KiB head | confirmed |
| 9 | `CYRIUS-2026-0045` | vulnerability | P2 | bayan | PDF Flate bomb guard bypassed: a failed decode is never cached or charged to the per-document budget, so every page reference re-inflates it | confirmed |
| 10 | `CYRIUS-2026-0046` | vulnerability | P3 | local-fs | compile() and its sibling emitters open the predictable '<output>.tmp.<pid>' temp with O_CREAT\|O_TRUNC, without O_EXCL or O_NOFOLLOW: this i | confirmed |
| 11 | `CYRIUS-2026-0047` | vulnerability | P3 | local-fs | file_write_atomic / _aw_open create the temp at 0644 & ~umask and only then fchmod it to the destination's mode: for a moment, the temp besi | confirmed |
| 12 | `CYRIUS-2026-0048` | vulnerability | P3 | local-fs | On Windows, the CLI's load_environ() opens the drive-relative rooted path '/proc/self/environ' (that is, <current drive>:\proc\self\environ, | confirmed |
| 13 | `CYRIUS-2026-0049` | vulnerability | P3 | net-http-ws-dns | http_get / http_get_r / http_get_a set no connect or read deadline and keep the socket private, so a malicious or slow server pins the fetch | confirmed |
| 14 | `CYRIUS-2026-0050` | vulnerability | P3 | auth-secrets | pam_unix_authenticate kills its own process with SIGPIPE when the password exceeds the pipe capacity (or the helper exits before reading): a | confirmed |
| 15 | — | bug | P2 | bayan | YAML parser is quadratic in mapping size: each key's duplicate check walks the whole object | confirmed |
| 16 | — | bug | P2 | bayan | Streaming JSON parser wraps out-of-range integers and accepts digitless numbers: the tree parser's 1.5.1 fixes were never applied to its sib | confirmed |
| 17 | — | bug | P3 | bayan | Flat TOML parser is quadratic in dotted-key tables: each new dotted key scans every section opened since the header | confirmed |
| 18 | — | bug | P3 | bayan | Base64 decoders accept invalid and non-canonical input: '=' anywhere decodes as zero bits, '====' gives one 0x00 byte, and base64url silentl | confirmed |
| 19 | — | bug | P3 | net-http-ws-dns | ws_connect discards any bytes received in the same TCP segment as the 101 handshake, silently dropping the server's first frame(s) | confirmed |
| 20 | — | bug | P3 | sigil | x509_parse_into: 1-byte out-of-bounds read on a crafted empty-TBS certificate | confirmed |
| 21 | — | bug | P3 | tls-native | Post-handshake KeyUpdate flood: unbounded KeyUpdate messages per record drive key-rotation allocations and response amplification with no ra | uncertain |
| 22 | — | hardening | P2 | release-channel | Any tag push yields a signed release, and the long-term Ed25519 signing key is handed to code built from the pushed tag (no environment, no  | confirmed |
| 23 | — | hardening | P3 | auth-secrets | pam_unix_authenticate hard-codes unix_chkpwd's "nullok": an account with an empty password field authenticates with an empty password, and a | confirmed |
| 24 | — | hardening | P3 | bayan | JSON accepts duplicate object keys and answers the FIRST, the opposite of most JSON readers; the flat and tree parsers also disagree on esca | confirmed |
| 25 | — | hardening | P3 | bayan | PDF text extraction work multiplies with repeated page references to one shared content stream | confirmed |
| 26 | — | hardening | P3 | release-channel | `cyrius deps` silently fetches git:// and http:// dependencies over plaintext and commit-pins whatever arrived | confirmed |
| 27 | — | hardening | P3 | release-channel | install.sh's header advertises `curl -sSf https://install.cyrius.dev \| sh`, a host that does not resolve, on a domain whose ownership is unv | confirmed |
| 28 | — | hardening | P3 | tls-native | Rotated-out and handshake-end TLS traffic secrets/keys are abandoned un-zeroized (defense-in-depth gap) | confirmed |

## `CYRIUS-2026-0038` — async DNS label encoder overruns its 288-byte stack query buffer: an attacker-chosen hostname smashes the resolver task's stack

**Severity:** P1 · **Kind:** vulnerability · **Surface:** net-http-ws-dns · **Where:** `lib/async.cyr` 634-662 (_async_dns_encode_labels); reached from _async_dns_build_query:664 and _async_resolve_task:748 (var qbuf[288])
**Attacker / boundary:** Whoever supplies a hostname a program resolves on the async reactor — e.g. the host of an attacker-influenced URL in an async HTTP client / crawler / proxy / webhook fetcher. The untrusted hostname string crosses into async_resolve -> _async_dns_build_query -> _async_dns_encode_labels, which writes it into a fixed 288-byte stack buffer with no total-length bound. Same boundary the ledger accepted for CYRIUS-2026-0010 (a long fetched URL overflowing http.cyr's request buffer).

**Impact.** Stack buffer overflow with attacker-controlled bytes (any byte except 0x00 and '.') and attacker-controlled length: the saved return address of _async_resolve_task is overwritten (measured: SIGSEGV with the stack return slot full of 0x41 and RIP sitting on a `ret`). Memory corruption / control-flow hijack primitive and a reliable crash (remote DoS) in a memory-unsafe language. async_resolve is Linux-only.

**Repro (scanner).** Build /home/macro/Repos/cyrius/build/cycc; probes at ~/.cache/l6718/audit/net-http-ws-dns/p1/. (1) Encoder in isolation: a 1000-byte all-'A' host into _async_dns_build_query over a zeroed 288+1024 buffer returns -1 but first writes 725 guard bytes past offset 288 (enc.cyr prints '-1 = build_query return; guard bytes past 288 written: 725'). (2) End to end: host=alloc(601); memset(host,0x41,600); store8(host+600,0); task_join(rt, async_resolve(rt,0x0100007F,53,host)) -> SIGSEGV (e2e: exit 139; gdb shows RIP on a `ret`, rsp bytes 0x4141414141414141). (3) 300 single-char dotted labels 'a.a.a...' (dots.cyr: dumped core, exit 139) — each label passes the per-label llen<=63 check, so the only guard `if (wi > 255)` at line 659 runs AFTER ~600 bytes are already written. Contrast lib/net.cyr:1398 _net_dns_build, which rejects hl>253 BEFORE writing and is safe.

**Verified (confirmed).** Code (lib/async.cyr:634-662): the encoder stores every host byte (store8(out + wi, c)) as it goes. Per-label llen<=63 is checked only at a '.' or at the end, and the total bound `if (wi > 255)` at line 659 runs only after the loop has written everything. The caller _async_resolve_task:748 passes `var qbuf[288]` (stack) via _async_dns_build_query (out+12). The encoder takes no out-size parameter. By contrast, net.cyr's _net_dns_build rejects hl>253 before writing.

Verifier repro 1, built from scratch with build/cycc (~/.cache/l6718/audit/verify-net-http-ws-dns/f1/enc.cyr): hosts of 'B' with no dots go into _async_dns_build_query over a zeroed 2048-byte block. Output:
- `n=253 ret=-1 highest nonzero offset>=288: 0`
- `n=300 ret=-1 highest nonzero offset>=288: 312`
- `n=600 ret=-1 highest nonzero offset>=288: 612`
- `n=1500 ret=-1 highest nonzero offset>=288: 1512`
The function returns -1 (rejected), but only after writing host length + 12 bytes, so the attacker controls the overrun length.

Verifier repro 2, end to end (f1/e2e.cyr): a dotted host of 60 labels 'CCCCCCCC' (539 bytes, every label valid per the 63 rule) is resolved with task_join(rt, async_resolve(rt, 0x0100007F, 53, host)). Output: `resolving 539-byte dotted host`, then `timeout: the monitored command dumped core`, exit=139. Under gdb: `SIGSEGV ... => 0x421a88: ret`, and `x/2gx $rsp` = `0x0843434343434343 0x4343434343434343`. The saved return address holds host bytes ('C', with an 8-byte label-length byte at its top).

The binary is a static non-PIE ELF at 0x400000 with no stack canary. The encoder ends with a single 0x00 terminator, so a partial low-byte overwrite into the binary's own code addresses is plausible. This is a real control-flow-hijack primitive, not just a crash.

Severity: the scanner said P2, but the project's own precedents for this exact class are P1. CYRIUS-2026-0010 (heap overflow, attacker bytes and length from the fetched URL) is 'High (P1)' in 2026-09-03-security-audit.md:628, and CYRIUS-2026-0013 (stack overflow in lib/log.cyr) is P1 at :1029. A stack overwrite of the return address is at least as severe, so P1.

Scope: Linux only. async_win.cyr uses getaddrinfo, and async_macos.cyr and async_agnos.cyr return 0. No in-tree lib/ caller passes untrusted input (callers are the test fixture and gates only), which matches 0004's 'library-level' framing.

The scanner's fix direction is right: reject strlen(host) > 253 before any store, as _net_dns_build does.

**Fix (planned).** Bound the host before writing, mirroring net.cyr's safe sibling: in _async_dns_encode_labels (or at async_resolve's entry) reject a host whose total length exceeds the wire limit up front (strlen(host) > 253 -> -1), and bound each byte-write so wi cannot exceed the caller's buffer capacity (the encoder takes no out-size parameter today — add one, or cap and check before every store8, not after the loop). The per-label and final wi>255 checks must become pre-write preconditions. Add a fuzz harness for _async_dns_encode_labels / _async_dns_parse_a.

**Status:** FIXED in 6.7.18 — `608b89369` (net): the encoder refuses an empty name or one over 253 bytes before writing and stores through a slice of exactly the encoded length; the answer parser through slices (`186e3eddb`, D1); row `tests/tcyr/stdlib/async_dns_query_bounded.tcyr`.

## `CYRIUS-2026-0039` — Fork PRs can run code on the self-hosted 'ach' runner: the only guard is an `if:` inside the workflow file the PR itself controls

**Severity:** P2 · **Kind:** vulnerability · **Surface:** release-channel · **Where:** `.github/workflows/ci.yml` 6-7 (pull_request trigger), 905-911 (macho-x86-native: `if:` guard + runs-on [self-hosted, macOS, X64]), 914 (checkout, persist-credentials default); .github/workflows/release.yml:7-8,14 (contents: write handed to ci.yml)
**Attacker / boundary:** Any GitHub account that opens a fork PR against main (subject only to the repo's fork-PR approval setting) -> code execution on the maintainer's physical Intel Mac 'ach' (self-hosted runner 'Achaemenid'), a release-verification host.

**Impact.** Runs arbitrary code as the runner user on ach, one of the four release-gate hosts, so it can falsify the ach leg of the cross-OS gate. The runner is persistent, and release.yml calls ci.yml with workflow-wide `permissions: contents: write`. ci.yml declares no `permissions:`, so on every tag push the ach job holds a contents:write GITHUB_TOKEN: it is passed to the job, and actions/checkout writes it into the workspace's .git/config for the job's lifetime. The repo has no branch or tag rulesets, so a stolen token can push to main. main's scripts/install.sh is the README's install command (README.md:12, `curl .../main/scripts/install.sh | sh`). The ci.yml comment says 'SECURITY: never run untrusted fork PRs on self-hosted hardware — gated to push / workflow_dispatch / same-repo PRs only', but that gate does not exist against a fork: for `pull_request` events GitHub runs the workflow definition from the PR's merge ref, so the PR can delete line 910 or add its own job with `runs-on: [self-hosted, macOS, X64]`.

**Repro (scanner).** Evidence only. I did NOT open a PR against real infrastructure.
1) grep -n -B3 'runs-on:.*self-hosted' .github/workflows/ci.yml  -> 910: if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository ; 911: runs-on: [self-hosted, macOS, X64]
2) grep -n permissions .github/workflows/ci.yml -> (none); release.yml:7-8 `permissions: contents: write`, :14 `uses: ./.github/workflows/ci.yml`
3) curl -s https://api.github.com/repos/MacCracken/cyrius | grep -E '"(private|visibility|allow_forking)"' -> "private": false, "allow_forking": true, "visibility": "public"
4) curl -s 'https://api.github.com/repos/MacCracken/cyrius/actions/runs/39907634674/jobs?per_page=100' -> "Mach-O x86 Native (ach, self-hosted)" success, runner_name "Achaemenid", labels ['self-hosted','macOS','X64'], runner_group "Default", completed 2026-10-23T05:47:52Z (the runner is live)
5) curl -s https://api.github.com/repos/MacCracken/cyrius/rulesets -> [] ; curl -s https://api.github.com/repos/MacCracken/cyrius/rules/branches/main -> []  (no branch or tag protection)
I could not read the fork-PR approval setting (GET /repos/MacCracken/cyrius/actions/permissions/fork-pr-contributor-approval needs admin). The maintainer should check Settings -> Actions -> General -> 'Approval for running fork pull request workflows'. Under 'first-time contributors who are new to GitHub', any established account runs without approval (P1). Under 'first-time contributors', one prior accepted contribution, or one 'Approve and run' click on a PR that edits ci.yml, is enough.

**Verified (confirmed).** I verified every precondition live; I did not open a PR against real infrastructure. (1) ci.yml:6-7 triggers `pull_request: branches: [main]`; :910 `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`; :911 `runs-on: [self-hosted, macOS, X64]`; :914 checkout with no `persist-credentials: false`; `grep permissions` finds only release.yml:7. (2) API repo: "private": false, "allow_forking": true, "visibility": "public". /rulesets -> [], /rules/branches/main -> [], /branches/main -> "protected": false. (3) Runner: CI run 39907634674 job "Mach-O x86 Native (ach, self-hosted)" ran on runner_name Achaemenid with labels ['self-hosted','macOS','X64'], group Default, runner_id 21. The SAME runner_id 21 ran "CI Gate / Mach-O x86 Native (ach, self-hosted)" in Release run 39886878816 (the 6.7.17 tag push, 2026-10-23T01:58) and in the 6.7.16 release run 39709749886 (2026-10-22T02:09). So the runner is persistent, not ephemeral, and the ach job runs inside the tag-push release workflow. release.yml sets workflow-level `permissions: contents: write`, and ci.yml declares none, so by GitHub's reusable-workflow rule (a callee can only downgrade) that job holds a write token. I could not read the job log's 'GITHUB_TOKEN Permissions' block: the logs endpoint returned 403 "Must have admin rights". (4) Platform semantics, from GitHub docs: pull_request runs with GITHUB_SHA = the merge commit, "in the context of the merge commit", so the PR's own workflow files govern and it can delete the `if:` or add a new workflow naming these labels. The self-hosted-runner docs warn verbatim: "forks of your public repository can potentially run dangerous code on your self-hosted runner machine by creating a pull request that executes the code in a workflow." (5) Approval: the docs say "By default, all first-time contributors require approval to run workflows." The repo has never had a PR (pulls?state=all -> 0; pull_request runs -> total 0), so every outside account is currently first-time. A run therefore needs one maintainer approval, or one benign merged contribution first; that is the PyTorch-style chain. This supports P2, not P1. I could not read the actual setting (admin-only). Corrections to the report: ci.yml has NO `workflow_dispatch` trigger, although the :905 comment says 'push / workflow_dispatch / same-repo PRs'. 'checkout writes the token into .git/config' may be imprecise for checkout v6+, which persists to a credentials file referenced from .git/config, but the token is on the runner for the job's lifetime either way. A GITHUB_TOKEN-pushed tag does not trigger release.yml, so this does not chain into the signing key. Classification note: CLAUDE.md lists 'the project's own dev / CI scripts' as bugs, but that exclusion covers the developer's own inputs. Here the attacker is an outside GitHub account who controls none of cyrius's code, build or dependencies, and the attacker and boundary can be named, so the ledger test is met.

**Fix (planned).** Take the self-hosted runner out of reach of pull_request workflows. Best: move the ach job to a separate workflow triggered only by `push` to main / `workflow_dispatch`, with a dedicated label the pull_request workflow never names. Then set the repo's fork-PR approval to 'Require approval for all external contributors'. A user-owned repo cannot use runner groups, so if any PR-triggered workflow can name the runner's labels, the runner stays exposed. Also run the runner ephemeral (--ephemeral, re-registered per job) under a dedicated low-privilege macOS user with no SSH keys or access to the dev box. Give ci.yml an explicit top-level `permissions: contents: read`, so the release-time call does not hand the self-hosted job a write token. Add a main-branch ruleset (no direct pushes from GITHUB_TOKEN, no force-push).

**Status:** MITIGATED in 6.7.18 — no code change: the `ach` self-hosted CI job stays (the user, 2026-10-22: GitHub has no x86 macOS runner), and the control is the repository's fork-PR approval setting (approval required for outside contributors), which the user sets in GitHub. Beside it, release.yml's top-level `contents: read` (`392197ca7`, local; Finding 22) means the CI gate a tag push calls, the ach job among them, no longer holds a `contents: write` token.

## `CYRIUS-2026-0040` — sigil ChaCha20-Poly1305 accepts forged records (all-zero tag) when two threads share a crypto lane: the streaming Poly1305 state is a process-global lane that another thread's finalize wipes to an all-zero key

**Severity:** P2 · **Kind:** vulnerability · **Surface:** auth-secrets · **Where:** `lib/sigil.cyr (upstream ~/Repos/sigil/src/poly1305.cyr:247,437 and src/chacha20poly1305.cyr; sigil 3.13.13)` 8757 (top-level `var _p1305_state[10752]`), 8760 (`_p1305_lane` = &_p1305_state + cbank()*168), 8947 (poly1305_finalize ends `memset(st, 0, 168)` on the shared lane), 9205-9222 (`_cp_tag` streams init/update/finalize through that lane), 9277 (chacha20poly1305_decrypt's tag compare); lane wrap in cbank() at 5394; the false 'fail-closed noise rather than a forged acceptance' claim at 5424
**Attacker / boundary:** An on-path network attacker with no key, against a ChaCha20-Poly1305 session (native TLS 1.3/1.2 record layer via tls_native_keysched.cyr:623, or any direct chacha20poly1305_decrypt consumer) served by a process whose crypto lanes alias. That happens after 63 lifetime crypto-touching threads, because cbank() never releases a lane, so for example sandhi_server_run_pooled_tls with max_conns >= 64 (agnosai's filed deployment ran 100 workers). On arm64 macOS it also happens with more than 64 live threads: lib/thread_local.cyr:132-150 `_tls_bind` falls back to the main thread's shared slot array, which I read in the code but did not run on ecb. The attacker crosses the network into the AEAD integrity check.

**Impact.** Integrity bypass of the AEAD. When thread B's poly1305_finalize wipes the shared lane after thread A's poly1305_init, A's remaining absorbs run with r = 0 and pad = 0, and A's finalize outputs a tag of 0^16. ct_eq_bytes(expected, tag) then passes for a record carrying an all-zero tag, and the forged ciphertext is decrypted and returned as authentic. ChaCha20 is malleable, so an attacker who flips chosen ciphertext bits of an in-flight record and zeroes its tag gets chosen plaintext bit-flips accepted. Each failed try aborts that connection. The same aliasing also makes valid records fail (a DoS), and it could put a Poly1305 tag computed under another session's one-time key on the wire; that last effect was not measured. This is the same class as sigil's RSA lane bypass fixed in 3.12.3 (888 of 400,000 forged signatures accepted). The ECDSA P-256/P-384 verify scratch (_ecv_* / _p256_* / _pta_*, lazily allocated per lane) is also process-global: on aliased lanes my probe accepted 0 of 100,000 forged signatures but rejected 99,403 of 99,403 valid ones. So sigil's roadmap claim that 'no signature path uses a lane' is wrong too, although that half fails closed.

**Repro (scanner).** Probe: ~/.cache/l6718/audit/auth-secrets/p1305_lane_alias.cyr. Thread A (the first worker, lane 1) loops chacha20poly1305_decrypt(keyA, nonce, no AAD, a random 64-byte ct, tag = 16 zero bytes). Next, 62 short-lived threads each call cbank() and exit. Thread B (the 64th worker, which wraps back to lane 1) loops decrypting a genuine record under an unrelated keyB.
  cd /home/macro/Repos/cyrius
  cat ~/.cache/l6718/audit/auth-secrets/p1305_lane_alias.cyr | build/cycc > ~/.cache/l6718/audit/auth-secrets/p1305_alias && chmod +x ~/.cache/l6718/audit/auth-secrets/p1305_alias
  ~/.cache/l6718/audit/auth-secrets/p1305_alias
    bank_a=1 bank_b=1 exhausted=1
    forged accepted by A: 1189 / 200000
    valid rejected by B: 163388 / 184871
  A second run gave 318 / 200000 forged accepted.
Control run (no burn threads, so B gets lane 2), ~/.cache/l6718/audit/auth-secrets/p1305_lane_control.cyr compiled the same way:
    bank_a=1 bank_b=2 exhausted=0
    forged accepted by A: 0 / 200000
    valid rejected by B: 0 / 113558
ECDSA twin (ecdsa_lane_alias100k.cyr: garbage signature under key A, valid signature under key B, aliased lanes): forged accepted 0 / 100000, valid rejected 99403 / 99403.

**Verified (confirmed).** I wrote my own probe instead of reusing the scanner's: ~/.cache/l6718/audit/verify-auth-secrets/v_p1305.cyr, with its control v_p1305_ctl.cyr. Thread A holds a GENUINE record under keyA, flips bit 5 of ciphertext byte 0 (an attacker's chosen flip) and zeroes the tag. Thread B ENCRYPTS rather than decrypts under keyB. 62 threads call cbank() and are joined (retired) in between. Built with `cat … | build/cycc`. Alias run 1: `lane_a=1 lane_b=1 claimed=64 exhausted=1 / forged accepted:14991 / 300000 (with the chosen flip in plaintext: 14991) / B encrypts run:182226`. Run 2: `forged accepted:10171 / 300000 (… chosen flip … 10171)`. Control: `lane_a=1 lane_b=2 claimed=2 exhausted=0 / forged accepted:0 / 300000`. So the forged record is accepted, and the plaintext returned carries exactly the attacker's bit flip. The aliasing partner only has to be running any Poly1305 (encrypt is enough). The code matches the claim. lib/sigil.cyr:8757 has `var _p1305_state[10752]`; 8760 is `_p1305_lane` = &_p1305_state + cbank()*168; poly1305_init (8813) stores r/s/pad into the lane; 8947 is `memset(st, 0, 168)` in finalize; 9205-9222 is _cp_tag streaming init/update/finalize through the lane; chacha20poly1305_decrypt compares with ct_eq_bytes. Once B's finalize zeroes the lane, A's absorbs run with r=0 and pad=0, so A's tag is 0^16. cbank() (5374-5400) uses `(n % 63) + 1` and `_crypto_next_bank` is never decremented (grep: only the atomic_fetch_add), so lanes are held for each thread's lifetime. Upstream ~/Repos/sigil (tag 3.13.13) has the same code at src/poly1305.cyr:247/250/437, and the wrong 'fail-closed noise' comment is at src/crypto_scratch.cyr:305 (lib/sigil.cyr:5424). Reach: tls_native_keysched.cyr:623 calls chacha20poly1305_decrypt for TLS_CHACHA20_POLY1305_SHA256. sandhi_server_run_pooled_tls spawns max_conns workers, and SANDHI_SERVER_DEFAULT_MAX_CONNS = 128 (lib/sandhi.cyr:14934), so the DEFAULT pooled TLS server aliases lanes from startup. One narrowing the scanner did not state: the native TLS 1.3 server prefers AES-256-GCM over ChaCha20 (tls_native_hs13.cyr:2231-2235), and the native client offers AES-256-GCM first. A forgery therefore needs a victim session that negotiated ChaCha20, plus a ChaCha20/Poly1305 partner busy on the aliased lane; the attacker can supply that partner with its own chacha-only connections. That narrowing is why P2 rather than P1 fits. I also rebuilt and ran the ECDSA sub-claim with 20k iterations (v_ecdsa_alias / v_ecdsa_ctl). Aliased: `forged accepted by A: 0 / 20000, valid rejected by B: 20055 / 20055`. Control: `0 / 20000, 0 / 20398`. That half fails closed (a DoS), as stated. I did not run the macOS >64-live-thread _tls_bind fallback (no SSH allowed); in the code (lib/thread_local.cyr:132-150, _TLS_REG_MAX = 64) a full registry returns -1 to the shared slot array.

**Fix (planned).** Make the streaming Poly1305 state caller-owned, the same move sigil 3.12.3 made for RSA and 3.13.12 for hash_file_into. Add poly1305_init_into(st, key) / poly1305_update_into(st, p, n) / poly1305_finalize_into(st, out) over a 168-byte context, have _cp_tag declare `var st[168]` on its own frame (wiped at return), and keep the old poly1305_init/update/finalize as wrappers over a per-call context, or retire them. Localise the ECDSA P-256/P-384 verify scratch (the _ecv*/_ecv384* sets and the lazily allocated _p256_*/_p384_*/_pt*_aff_* lanes) onto the verify frame in the same patch. The security half should not wait for the 3.14.0 'retire cbank()' minor. Correct the crypto_banks_exhausted comment, which says aliasing is fail-closed noise. Fix it in the sigil source repo, cut 3.13.14, regenerate dist/ and re-vendor lib/sigil.cyr byte-identical. Turn the probe above into a regression .tcyr (forged acceptance must be 0 on aliased lanes) in sigil's suite and cyrius's crypto bucket.

**Status:** FIXED in 6.7.18 — sigil 3.13.14 `ee7c75d` (the AEAD's Poly1305 state on its own frame) and `6d95d4c` (crypto lanes a pool held only while used) / 3.13.15, vendored byte-identical by the refold (`4ec5b2414`, `1c9bede70`); the arm64-macOS alias path, tls-slots `ea9bda1e1` / `97d9be17d`. The audit's v_p1305: 0 / 300,000 forged accepted; v_ecdsa_alias: 0 forged, 0 valid rejected.

## `CYRIUS-2026-0041` — lib/tls.cyr's libssl backend runs the INVOKING user's $HOME/.cyrius/dlopen-helper in-process: fdlopen_init_full has no setuid / AT_SECURE check, so a setuid program using the libssl backend runs a local user's code as root

**Severity:** P2 · **Kind:** vulnerability · **Surface:** auth-secrets · **Where:** `lib/tls.cyr (caller); lib/fdlopen.cyr (resolver)` lib/tls.cyr:366-368 (`fdlopen_helper_available()` then `fdlopen_init_full(&_tls_fdl_state)`, the untrusted entry, with no way for a caller to select fdlopen_init_trusted); lib/fdlopen.cyr:346-421 (`_fdlopen_helper_path` reads HOME from /proc/self/environ unless `_fdl_trusted_mode`), :877 (`fdlopen_init_full`, no uid/euid/AT_SECURE test), :739 (synthesised auxv hard-codes AT_SECURE=0)
**Attacker / boundary:** A local unprivileged user who runs a setuid-root program built with cyrius that uses lib/tls.cyr's libssl backend (`-D CYRIUS_TLS_LIBSSL`, or `tls_set_backend(TLS_BACKEND_LIBSSL)`). Crosses user -> root. HOME is attacker-chosen and a setuid-root process can read its own /proc/self/environ. docs/development/threat-model.md:28 says setuid consumers MUST use fdlopen_init_trusted, but the stdlib's own TLS calls fdlopen_init_full and offers no way to comply.

**Impact.** Arbitrary code execution as root on the first TLS use (tls_available / connect) in such a program: the planted ELF is mmapped and entered through ld.so inside the privileged process. Exposure is low: the libssl backend is opt-in (native is the default), and no known setuid consumer enables it today (shakti parked TLS pending exactly this proposal, docs/development/proposals/archived/2026-06-02-fdlopen-helper-trust-for-setuid-consumers.md). That proposal's option 1, ignoring the $HOME copy whenever geteuid() != getuid(), was never implemented.

**Repro (scanner).** D=~/.cache/l6718/audit/auth-secrets
  cc -O1 -DMARKER="\"$D/evil_marker.txt\"" -o $D/evilhome/.cyrius/dlopen-helper $D/evil_helper.c    # stand-in planted helper: writes a marker, _exit(77)
  cd /home/macro/Repos/cyrius && cat $D/tls_libssl_home.cyr | build/cycc > $D/tls_libssl_home && chmod +x $D/tls_libssl_home    # tls_set_backend(TLS_BACKEND_LIBSSL); tls_available();
  rm -f $D/evil_marker.txt; HOME=$D/evilhome $D/tls_libssl_home; echo exit=$?
    exit=77            (the planted helper's _exit, from inside the cyrius process)
  cat $D/evil_marker.txt
    planted helper ran: uid=1000 euid=1000 pid=1806062
Separately, $D/fdl_home with HOME=$D/fakehome prints `helper path: .../fakehome/.cyrius/dlopen-helper ... helper_available=1`. `grep -n 'geteuid\|getuid\|AT_SECURE' lib/fdlopen.cyr` finds only the hard-coded `AT_SECURE=0` comment lines (710, 739). This was not run setuid-root (that needs root): the root half follows from the code, because nothing distinguishes a setuid caller.

**Verified (confirmed).** Independent repro in ~/.cache/l6718/audit/verify-auth-secrets/. I wrote my own planted helper (plant_helper.c, built with cc to plant/.cyrius/dlopen-helper, which records uid/pid and _exit(91)) and my own probe (v_tls_home.cyr: print pid; tls_set_backend(TLS_BACKEND_LIBSSL); tls_available()). `HOME=$D/plant $D/v_tls_home` printed `pid=1950519` and then exited 91, never reaching its 'returned' line. The helper wrote `VERIFIER planted helper executed: uid=1000 euid=1000 ppid=1950051 pid=1950519 argc=3`. That is the same pid, so the planted ELF ran inside the cyrius process, with the synthesised 3-arg stack. Control `HOME=$D/emptyhome` printed `returned; tls_available=0`, exit 0, and no marker. Code: lib/tls.cyr:366-368 is `fdlopen_helper_available()` then `fdlopen_init_full(&_tls_fdl_state)`, with no trusted variant selectable. _fdlopen_helper_path (lib/fdlopen.cyr:346-421) reads HOME from /proc/self/environ unless `_fdl_trusted_mode == 1`, and that flag is set only inside fdlopen_init_trusted and cleared again on return (954/956), so a setuid consumer cannot make lib/tls take the trusted path. grep finds no getuid/geteuid; AT_SECURE appears only as the hard-coded `store64(p, 0)` at 739. I could not run the root half (it needs root), but nothing in the path depends on uid. A setuid exec keeps the invoker's envp, and a process can always read its own /proc/self/environ, so the same branch runs as root. threat-model.md:28 says setuid consumers MUST use fdlopen_init_trusted; lib/tls offers no way to. One nuance: the archived proposal's header claims option 1 shipped, but only its system-path half did. Its 'ignore $HOME when geteuid() != getuid()' clause was not implemented, as the scanner says. Exposure is limited: an opt-in, non-default backend, and no known setuid user of it. The impact is root code execution, so P2 stands.

**Fix (planned).** Close it in fdlopen itself, so lib/tls.cyr and every other caller are covered. In fdlopen_init_full and fdlopen_helper_available, detect secure execution from the real auxv (AT_SECURE, tag 23, via dynlib_auxv_get on /proc/self/auxv), with getuid()!=geteuid() || getgid()!=getegid() as the fallback. When secure, never consult $HOME: resolve only /usr/lib/cyrius/dlopen-helper through _fdlopen_verify_trusted and return FDL_ERR_UNTRUSTED (-9) otherwise, so lib/tls.cyr reports tls_available()==0 and fails closed. Open the helper once and verify ownership and mode with fstat on that fd rather than lstat-then-reopen-by-name, and forward the real AT_SECURE into the synthesised auxv instead of 0. Add a regression test with an injected 'secure' flag that asserts a planted $HOME helper is never opened, and update threat-model.md.

**Status:** FIXED in 6.7.18 — `fa7d68639`, `fa111fc34` (local): in a secure exec (AT_SECURE, a real / effective uid or gid mismatch, an unreadable auxv) every fdlopen entry takes only the root-owned, verified `/usr/lib/cyrius/dlopen-helper`, verified on the fd it is mapped from; `fdlopen_trusted_only(1)` asks for it anywhere (api-surface `34c5211f7`); row `fdlopen_trusted.tcyr`.

## `CYRIUS-2026-0042` — X.509 chain verifier ignores nameConstraints (RFC 5280 §6.1 path-validation gap; the CYRIUS-2026-0002 class)

**Severity:** P2 · **Kind:** vulnerability · **Surface:** sigil · **Where:** `/home/macro/Repos/sigil/src/x509.cyr (x509_verify_chain / _x509_verify_link / _xp_parse_extensions); vendored /home/macro/Repos/cyrius/lib/sigil.cyr:19536; and /home/macro/Repos/cyrius/lib/tls_native_hs12.cyr:3824 (_tn_verify_chain)` sigil/src/x509.cyr:773 (_xp_parse_extensions reads only basicConstraints/keyUsage/EKU); 1272 (x509_verify_chain); cyrius/lib/tls_native_hs12.cyr:3824
**Attacker / boundary:** An attacker holding the private key of an intermediate CA that is name-constrained (permitted/excluded subtrees) and chains to a root the victim trusts. They should only be able to issue certificates for names inside their permitted subtree; the boundary crossed is name-space authorization — they can mint a leaf for ANY host (e.g. a bank or vendor domain) and a cyrius TLS client / Authenticode / TEE chain verifier accepts it, enabling server impersonation / MITM.

**Impact.** RFC 5280 name-constraint enforcement is absent at every level: _xp_parse_extensions never parses the nameConstraints extension (2.5.29.30) and the chain walkers (_x509_verify_link, x509_verify_chain, and cyrius's _tn_verify_chain) never apply permitted/excluded subtrees. OpenSSL rejects such a chain (verify error 47, 'permitted subtree violation'); cyrius accepts it. IMPORTANT MITIGATING FACT: a CONFORMANT constrained CA marks nameConstraints critical (RFC 5280 §4.2.1.10 'MUST'; CA/B Forum requires it), and sigil's parser fail-closes on any critical unrecognised extension (_xp_parse_extensions returns -1 -> x509_parse returns 0 -> the cert does not parse -> chain cannot build), so a conformant constrained CA is simply unusable rather than over-trusted. The bypass only bites a NON-conformant intermediate that marked nameConstraints non-critical. This is also a DOCUMENTED known gap (sigil/src/x509.cyr:10 'no name constraints'; cyrius docs/audit/2026-09-03-security-audit.md 'Not covered'), so it is reported as hardening, not a fresh find — but it is the same validation-bypass class that was assigned CYRIUS-2026-0002 for pathLen/keyUsage/EKU, so the user may wish to decide whether it warrants an id.

**Repro (scanner).** In ~/.cache/l6718/audit/sigil/nc: generated a P-256 root; an intermediate with basicConstraints CA:TRUE + 'nameConstraints=permitted;DNS:allowed.test' (NON-critical); a leaf CN/SAN=victim.example signed by that intermediate. openssl: `openssl verify -CAfile root.pem -untrusted int.pem -purpose sslserver leaf.pem` -> 'error 47 ... permitted subtree violation / verification failed'. cyrius probe (nc_probe.cyr, built with build/cycc) loading root.der as the trust bundle, leaf.der as SERVER_CERT and int.der as the one intermediate: `tls_native_client_verify_chain(ctx, 1798761600)` returned 0 (TLS_OK) and `tls_native_client_verify_hostname` returned 0 (TLS_OK) — the name-constrained intermediate successfully vouched for victim.example, outside its allowed.test subtree. (The critical-nameConstraints variant int_crit.der: x509_parse returned 0 — fail-closed, confirming the mitigation above.)

**Verified (confirmed).** Reproduced from scratch in ~/.cache/l6718/audit/verify-sigil/nc. I used fresh P-256 keys to build a root, an intermediate `int` (CA:TRUE pathlen:0, keyCertSign, nameConstraints=permitted;DNS:allowed.test, NON-critical), a second intermediate `intc` with the same constraint marked critical, and a leaf with CN/SAN DNS:victim.example and EKU serverAuth, signed by `int`.

OpenSSL 3.6.5 is the reference. `openssl verify -CAfile root.pem -untrusted int.pem -purpose sslserver leaf.pem` gives 'error 47 at 0 depth lookup: permitted subtree violation / verification failed' (rc=2). The in-subtree control leaf (SAN www.allowed.test) gives 'OK'.

The cyrius probe (probe.cyr, includes lib/tls.cyr, built with the tree's build/cycc) printed: set_ca_bundle(root.der)=0; x509_parse(leaf)=1; x509_parse(int.der, NON-critical NC)=1; tls_native_client_verify_chain=0 (TLS_OK); tls_native_client_verify_hostname victim.example=0 (TLS_OK); sigil x509_verify_chain(leaf,[int],root)=1. The negative controls fail as they should: no intermediate gives -6, host other.example gives -7. The critical-NC intermediate gives x509_parse(intc.der)=0, which confirms the fail-closed mitigation for the critical form.

Code: _xp_parse_extensions (sigil/src/x509.cyr:773, the same in lib/sigil.cyr) reads only basicConstraints, keyUsage and EKU, and drops an unknown NON-critical extension. _x509_verify_link (:1171), x509_verify_chain (:1272) and cyrius _tn_verify_chain (lib/tls_native_hs12.cyr:3824) never apply subtrees. No nameConstraints handling exists anywhere in lib/. The only name-constraint logic is the Windows store reader, which REFUSES roots that carry root-program name constraints because 'the native verifier cannot apply' them (hs12.cyr:2181, 2450). The project fails closed there but open on a cert-embedded non-critical constraint.

Two corrections to the scanner's classification:
(1) The mitigating claim that 'CA/B Forum requires it [critical]' is inaccurate. The Baseline Requirements explicitly permitted non-critical nameConstraints (Ballot 75 / BR 1.1 exception, because Apple clients rejected critical ones), and later only said 'SHOULD be critical' (see the cabforum servercert-wg 2019-10 'Removing the exception to allow non-critical name constraints' thread). Non-critical constrained subCAs are therefore a sanctioned real-world shape, not merely 'non-conformant'. Such technically constrained subCAs are held by organisations precisely because the constraint is the boundary.
(2) The 'documented known gap' (sigil x509.cyr:10; the 2026-09-03 audit 'Not covered') is not an issue file and is not a reason to withhold an id. The identical class (a constrained CA exceeding its pathLen / keyUsage / EKU constraint) received CYRIUS-2026-0002 (P1).

I set the severity to P2 rather than 0002's P1 because the attacker needs a key to a subCA whose constraint is non-critical, plus an on-path position. No root in /etc/ssl/cert.pem (118 roots scanned) carries nameConstraints, so exposure is via intermediates only. The scanner's interim fix is sound: refuse any present-but-unenforced nameConstraints, mirroring the Windows root refusal. It belongs upstream in sigil and then a re-vendor.

**Fix (planned).** Parse nameConstraints in _xp_parse_extensions (store permitted/excluded GeneralSubtrees) and apply them during path building in _x509_verify_link's callers / x509_verify_chain / _tn_verify_chain: for each CA in the path carrying constraints, every subordinate certificate's subject DN and subjectAltName dNSName/iPAddress/rfc822/directoryName must fall within the permitted set and outside the excluded set, per RFC 5280 §6.1.4(g)/§4.2.1.10, else refuse the chain. A minimal interim hardening that costs almost nothing: since the conformant (critical) case already fail-closes, the only exposure is non-critical nameConstraints — treating a PRESENT-but-ignored nameConstraints extension (critical or not) as a refusal would close the bypass fail-closed until full subtree matching is implemented. Decision for the user: whether this is tracked as the CYRIUS-2026-0002 validation-bypass class (id) or a documented hardening backlog item.

**Status:** FIXED in 6.7.18 — sigil 3.13.14 `1910602`, `0637b14` / 3.13.15 `3c47656` (sigil): nameConstraints parsed critical or not and enforced by `x509_verify_chain` and `_x509_verify_link`, an intermediate checked as a CA (`x509_name_constraints_check_ca`); vendored byte-identical by the refold (`4ec5b2414`, `1c9bede70`). Row: sigil `tests/tcyr/x509_name_constraints.tcyr`.

## `CYRIUS-2026-0042` — Native TLS chain verifier ignores a CA's X.509 nameConstraints: a non-critically name-constrained intermediate under a trusted root can impersonate any host

**Severity:** P2 · **Kind:** vulnerability · **Surface:** tls-native · **Where:** `lib/tls_native_hs12.cyr` 3824
**Attacker / boundary:** An on-path / active network attacker who holds a name-constrained subordinate CA (constraint marked NON-critical) that chains to a root the cyrius client trusts; the boundary crossed is server-identity authentication (impersonation of a host outside the sub-CA's permitted name subtree).

**Impact.** RFC 5280 §4.2.1.10 nameConstraints is the mechanism a root/issuer uses to delegate a subordinate CA while limiting the names it may vouch for. _tn_verify_chain checks window, keyUsage/pathLen, EKU and the policy deny-lists but NEVER evaluates nameConstraints, and sigil's x509 parser (_xp_parse_extensions) does not parse the extension. A sub-CA constrained to e.g. DNS:good.test is accepted as the issuer of a leaf for victim-bank.test. The holder of such a constrained intermediate can mint a trusted-looking certificate for any host and MITM a cyrius native-TLS client, losing session confidentiality and integrity. Scope note: when the intermediate marks nameConstraints critical (the RFC-conformant case) sigil rejects it at parse as an unhandled critical extension, so verify fails CLOSED; the exploitable window is a non-critically-constrained intermediate. Pre-documented as a known limitation in docs/audit/2026-09-03-security-audit.md 'Not covered' and lib-tls-contract.md, but not a filed issue and the impersonation path is concrete.

**Repro (scanner).** Scratch PKI in ~/.cache/l6718/audit/tls-native/pki: root 'Test Root'(CA); intermediate 'Constrained Sub-CA good.test' signed by root with nameConstraints=permitted;DNS:good.test (NON-critical); leaf SAN DNS:victim-bank.test signed by the intermediate. OpenSSL refuses: `openssl verify -CAfile root.pem -untrusted inter.pem -verify_hostname victim-bank.test leaf.pem` -> error 47 permitted subtree violation. cyrius accepts, two ways: (1) ~/.cache/l6718/audit/tls-native/nc_probe loads root.pem as the only anchor, parses leaf+intermediate into SERVER_CERT/SERVER_INTERS, prints `tls_native_client_verify_chain -> 0` and `tls_native_client_verify_hostname(victim-bank.test) -> 0`; (2) end-to-end ~/.cache/l6718/audit/tls-native/nc_e2e vs `openssl s_server -cert leaf.pem -key leaf.key -cert_chain inter.pem -tls1_3` prints `tls_native_connect -> 0`, version 772, reads `HTTP/1.0 200 ok`. The same s_server makes `openssl s_client -CAfile root.pem -verify_hostname victim-bank.test -verify_return_error` fail num=47 permitted subtree violation.

**Verified (confirmed).** Code: _tn_verify_chain (lib/tls_native_hs12.cyr:3824-3891) checks the window, purpose, keyUsage/pathLen/EKU (_tn_ca_signer_ok) and the policy deny-lists. It never evaluates nameConstraints. sigil's _xp_parse_extensions (lib/sigil.cyr:19037-19178) matches only basicConstraints, keyUsage and EKU. Any other extension is dropped when non-critical and rejected when critical.

Independent repro (my own PKI and probes in ~/.cache/l6718/audit/verify-tls-native/): P-256 root 'Verifier Root' -> 'NC Sub-CA' with nameConstraints=permitted;DNS:allowed.example (non-critical) -> leaf with SAN DNS:other-host.example. OpenSSL refuses it: `error 47 at 0 depth lookup: permitted subtree violation`.

API-level probe vprobe:
- `A noncrit-NC ... parse_inter=1 verify_chain=0 verify_hostname=0`: accepted.
- Same chain, nameConstraints critical: `B ... parse_inter=0 verify_chain=-6`. Fails closed, but only by accident.
- Controls: hostname mismatch `C ... verify_hostname=-7`; intermediate withheld `D ... verify_chain=-6`.

End to end, ve2e against `openssl s_server -cert leaf.pem -cert_chain inter.pem -tls1_3 -www`:
- `E1 noncrit NC, host other-host.example: connect=0 version=772`, then reads `HTTP/1.0 200 ok`.
- `E2 ... wrong.example: connect=-7`
- `E3 crit NC ...: connect=-6`
openssl s_client against the same server reports `verify error:num=47:permitted subtree violation`.

Severity: I raise it from P3 to P2. It is the same class and attacker shape as ledger entry CYRIUS-2026-0026 (P2, 'Native TLS chain verifier ignored a CA's EKU', attacker 'holder of an EKU-constrained CA under a trusted root') and CYRIUS-2026-0002 (pathLen). The finding calls the non-critical precondition 'non-conforming issuance'. That understates it: the Baseline Requirements permitted non-critical nameConstraints on technically constrained sub-CAs, so publicly trusted examples exist. The gap is listed under 'Not covered' in docs/audit/2026-09-03-security-audit.md:1757, but no issue was filed and no id assigned. A documented limitation does not exempt it from the ledger rule.

**Fix (planned).** Parse nameConstraints (OID 2.5.29.30) in sigil's x509 parser (store permitted/excluded dNSName and iPAddress subtrees rather than rejecting it as unhandled-critical), and in _tn_verify_chain enforce, at each CA selected on the path and the anchor, that the leaf's dNSName/iPAddress SANs fall within every ancestor CA's permitted subtrees and outside its excluded subtrees (RFC 5280 §6.1.4). Until then the critical-rejection is only accidental fail-closed coverage. Whether to spend a ledger id vs. track as a capability gap is the maintainer's call given the non-conforming (non-critical) issuance precondition.

**Status:** FIXED in 6.7.18 — `8b244685d`, `e91b099c1` (refold), with sigil 3.13.15: `_tn_verify_chain` requires every CA on the selected path, the trust anchor included, to allow every certificate below it (the leaf always, a self-issued intermediate exempt, an intermediate checked as a CA); the TLS 1.2 client keeps the intermediates (`b6c4bc5ba`). The audit's nc_probe: `tls_native_client_verify_chain` 0 → -6. Rows: `tests/tcyr/crossos/tls_native_name_constraints.tcyr`, `tests/gates/platform/tls_native_name_constraints_openssl.sh`.

## `CYRIUS-2026-0043` — ws_server's receive buffer is a single process-global, so two concurrent WebSocket connections in a multi-threaded server read and echo each other's payloads

**Severity:** P2 · **Kind:** vulnerability · **Surface:** net-http-ws-dns · **Where:** `lib/ws_server.cyr` 260 (var _wss_recv_buf = 0); used unsynchronized at 266,271,281,286,289 in ws_server_recv
**Attacker / boundary:** Any WebSocket client of a server that handles connections on more than one thread (e.g. a WS handler wired into sandhi_server_run_pooled / sandhi_server_run_async, both multi-threaded). _wss_recv_buf is a module-level global shared by every ws_server_recv call on every thread, so connection isolation is broken: client A's in-flight frame payload lands in client B's buffer and vice versa.

**Impact.** Cross-connection data disclosure and corruption between unrelated clients: one client reads another client's message bytes, and a PING auto-response echoes a different client's payload on the wrong socket. Confidentiality break across client sessions plus frame-stream corruption. Reachability requires the server to serve WS on multiple threads concurrently (the module's documented integration is sandhi's single-threaded http_server, which is why this is P2, not P1).

**Repro (scanner).** ~/.cache/l6718/audit/net-http-ws-dns/p3/wssbuf.cyr: two socketpairs, two ws_server handles; thread A blocks in ws_server_recv part-way through an 8-byte PING (7 bytes delivered); main thread then calls ws_server_recv on connection B and receives a TEXT frame 'B-SECRET'; A's last PING byte is then delivered. Output: `B's handler got: B-SECRET` then `PONG payload sent to A: B-SECREa` — connection B's secret leaked into the PONG A sends to its own peer, proving the two connections share one buffer (built with build/cycc; exit 0).

**Verified (confirmed).** Code: lib/ws_server.cyr:260 `var _wss_recv_buf = 0;` is one per-process buffer. ws_server_recv (265-296) lazily allocates it and passes it to ws_server_recv_frame. That function reads the payload incrementally with _wss_recv_exact (139-148, reading into buf+got), then unmasks in place. The PING branch echoes _wss_recv_buf back via ws_server_send_pong. There is no lock and no per-handle buffer, and no thread-safety restriction is documented anywhere (grep of lib/ and docs/).

Reachability: sandhi.cyr:16253-16262 says run_pooled is a worker-thread pool whose handler shape is 'identical to run / run_async ... existing handlers drop straight in', with alloc thread-safe (CAS lock). ws_server.cyr's documented integration is exactly such an HTTP handler that calls ws_server_handshake and then loops. A WS handler moved into run_pooled therefore runs ws_server_recv concurrently on N threads.

One correction to the scanner: sandhi_server_run_async is NOT multi-threaded. sandhi.cyr:16250-16252 calls it 'cooperative/run-to-completion', so only the pooled loop reaches this.

Verifier repro, written from scratch (~/.cache/l6718/audit/verify-net-http-ws-dns/f2/wss2.cyr):
- Two socketpairs and two ws_server_new handles.
- Attacker A sends a MASKED PING (len 16, non-zero mask 5A5A5A5A) and holds back the last payload byte. Its thread blocks inside ws_server_recv.
- Victim B sends a masked TEXT 'B-SECRET-TOKEN-1' (mask 01020304), and the main thread runs ws_server_recv on B.
- A then releases its last byte, and A's peer XORs the PONG with its OWN mask key.
Output (exit 0):
- `B's handler got: B-SECRET-TOKEN-1`
- `A's peer got PONG opcode byte 0x138 len 16; payload XOR A's own mask: B-SECRET-TOKEN-;`
(138 is decimal for 0x8A, the PONG opcode.)

So B's plaintext reaches attacker A even through masking, because A chose its own mask key. The frame length is checked only against WS_MAX_PAYLOAD (1 MiB), not the RFC's 125-byte control-frame cap. A can therefore declare a PING of up to 1 MiB, send all but one byte, and leak up to 1 MiB of whatever other connections receive in that window. Attacker bytes can also land in B's returned message (cross-session injection).

P2 is consistent with CYRIUS-2026-0004 (a library-level flaw that needs a particular server configuration). The fix is a per-handle buffer allocated in ws_server_new or ws_server_handshake.

**Fix (planned).** Give each connection (or each worker thread) its own receive buffer instead of a process-global. Either allocate the recv buffer inside the ws handle struct at ws_server_new / ws_server_handshake (sized WS_MAX_PAYLOAD+1), or make _wss_recv_buf thread-local via thread_local_alloc/thread_local_set the way sandhi's pooled loop already threads per-worker arenas. Add a regression driving two ws_server handles concurrently that asserts payload isolation.

**Status:** FIXED in 6.7.18 — `5afff204d`, `ae53f9d3c` (net): each frame has its own buffer — a data frame its own allocation, a control frame (≤ 125 bytes) the call's stack; row `tests/tcyr/crossos/ws_server_connections_isolated.tcyr`.

## `CYRIUS-2026-0044` — HPACK decoder accepts an unbounded Dynamic-Table-Size-Update: peer grows the client's decode table with no limit and amplifies a 16 KiB header block

**Severity:** P2 · **Kind:** vulnerability · **Surface:** sandhi · **Where:** `lib/sandhi.cyr:7593 (upstream src/http/h2/hpack.cyr:677, decode-field §6.3 branch) + lib/sandhi.cyr:7268 (upstream :352 sandhi_hpack_table_set_max_size)` 7593
**Attacker / boundary:** A malicious/compromised HTTP/2 server (or an on-path attacker on cleartext h2c) that a sandhi client reaches through the sandhi_http_*_auto / h2 client APIs; the boundary is HPACK decoding of the server's response HEADERS/CONTINUATION block in sandhi_h2_response_recv_a -> _h2_decode_response_headers_a -> sandhi_hpack_decode_field_a.

**Impact.** Remote memory-exhaustion DoS driven by a network peer. sandhi's decode table is created with max 4096 (sandhi_h2_conn_new -> sandhi_hpack_table_new_a(a,0)) and sandhi advertises no SETTINGS_HEADER_TABLE_SIZE, so RFC 7541 §6.3 / RFC 7540 §6.5.2 make 4096 the ceiling. The §6.3 Dynamic-Table-Size-Update branch calls sandhi_hpack_table_set_max_size(t, value) with the peer's integer-decoded value and NO upper-bound check, so a server can set the client's per-connection decode table to an arbitrary size (measured: 256 MiB accepted). With eviction thus disabled, literal-with-incremental-indexing fields accumulate in the table without bound across the connection's lifetime, and a HEADERS block of indexed references to large table entries decompresses into a header list far larger than the <=16 KiB wire block (each name/value copied into the per-request arena by sandhi_headers_add_a). _h2_decode_response_headers_a also applies no MAX_HEADER_LIST_SIZE bound on the decoded list. Mitigated by: h2 is opt-in (the _auto path); the per-response decode arena is reset after each response, bounding the transient decoded-headers spike per response; the input header block is capped at 16 KiB/response. The table's own fl_alloc storage persists per-connection and grows cumulatively over requests the client initiates.

**Repro (scanner).** Compiled a probe that drives the decoder exactly as the h2 response reader does, feeding the field decoder a real §6.3 size-update then adding entries, and measured the table. cd /home/macro/Repos/cyrius && ./build/cycc < ~/.cache/l6718/audit/sandhi/hpack_tbl.cyr > /tmp/p && chmod +x /tmp/p && /tmp/p. Output: initial max_size=4096; after sandhi_hpack_decode_field(t, <5-byte size-update for 0x10000000>) rc=1 (TBL_UPDATE) and max_size=268435456 ('decoder accepted a dynamic-table-size-update of 256 MiB'); then 2000 literal adds of ~632 B each left table cur_size=1260000 with 2000 entries and no eviction ('dynamic table grew past 4096'). Probe at ~/.cache/l6718/audit/sandhi/hpack_tbl.cyr.

**Verified (confirmed).** Code (lib/sandhi.cyr matches upstream ~/Repos/sandhi/src/http/h2/hpack.cyr:670-680 and :352): the §6.3 branch of sandhi_hpack_decode_field_a (lib/sandhi.cyr:7586-7597) calls sandhi_hpack_table_set_max_size(t, load64(sz_cell)) with the peer's integer and does not check it against the 4096 that sandhi_h2_conn_new_a gives the decode table (:8036-8038). sandhi never sends SETTINGS_HEADER_TABLE_SIZE, so RFC 7541 §4.2's 'MUST treat as a decoding error' applies. _h2_decode_response_headers_a (:8928-8953) puts every decoded field through sandhi_headers_add_a with no MAX_HEADER_LIST_SIZE bound. Each indexed reference is copied twice: once by _hpack_own_a and once by the name/value dups in sandhi_headers_add_a.

I wrote my own end-to-end repro, ~/.cache/l6718/audit/verify-sandhi/h2_hpack_e2e.cyr (built as e2e_m0/1/2). A forked fake h2 server on loopback TCP writes raw HEADERS frames, and the client runs the real sandhi_conn_open, sandhi_h2_conn_new and sandhi_h2_response_recv_a(default_alloc(), ...).

MODE 0 (baseline, no size update; resp1 = :status 200 + a literal-with-indexing entry of exactly 4096; resp2 = a 16,384-byte block of 0x88 + 16,383 x 0xBE): dec max_size/cur_size/count = 4096/4096/1; resp2 err 0, status 200, 'decoded header count = 16383', 'client heap bytes allocated by resp2 (wire block 16384 B) = 135159896'.

MODE 1 (resp1 starts with a size update to 2^28, then a 16,000-byte entry): 'dec max_size / cur_size / count after resp1 = 268435456 / 16035 / 1'; resp2 err 0, status 200, 16383 headers, '526517000' bytes allocated.

MODE 2 (the size update, then 30 more responses each adding a 16,000-byte entry): 'after 30 more responses: dec cur_size / count = 497085 / 31', so nothing was evicted.

Three corrections to the report:
(a) The amplification does not need the size update. Missing the header-list bound alone gives about 8,250x (135 MB from 16 KiB) with a compliant 4096 table. The unchecked size update raises that about 3.9x (526 MB) and lets the persistent table grow. That growth is only linear in wire bytes: 497 KB after 31 responses.
(b) The 'per-response arena reset' mitigation does not hold for the bare public verbs. sandhi_http_get_auto / request_auto pass default_alloc(), the global bump allocator, which is never reset (lib/sandhi.cyr:9760, :9774). The 135-526 MB per response is therefore retained for the life of the process, and a few responses OOM the client.
(c) The cleartext h2c on-path vector does not apply to the _auto path. _sandhi_http_try_h2_promote_a promotes only over TLS with ALPN h2 (opens use_tls=1, needs a pool). It applies only to a program that drives sandhi_h2_* by hand over a plaintext conn it opened itself.

Severity: P2 rather than the reported P3. By ledger precedent, CYRIUS-2026-0037 was P3 for about 24 ms of CPU per 16 KB hello, and 0031 was a vulnerability for remote-driven retained growth of 19-64 MiB per attempt. This is 135-526 MB retained per 16 KiB response on the default verbs.

Fix: the decoded header-list bound in _h2_decode_response_headers_a is the primary half, not 'additional'. Also reject a §6.3 value above the advertised 4096 in the decoder branch with _SANDHI_HPACK_ERR_MALFORMED, leaving the table primitive uncapped for the encoder. Both changes go upstream in sandhi first, then re-vendor.

**Fix (planned).** In the §6.3 Dynamic-Table-Size-Update branch of sandhi_hpack_decode_field_a, reject (return _SANDHI_HPACK_ERR_MALFORMED) any value greater than the size sandhi advertised for its decoder — the default SANDHI_HPACK_DEFAULT_TABLE_SIZE (4096), or whatever it sends in SETTINGS_HEADER_TABLE_SIZE if that is ever added — before calling sandhi_hpack_table_set_max_size on the decode table, per RFC 7541 §6.3. Keep the primitive sandhi_hpack_table_set_max_size uncapped (the encoder legitimately follows the peer's larger SETTINGS value). Additionally bound the decoded header list in _h2_decode_response_headers_a against a MAX_HEADER_LIST_SIZE so references cannot amplify a 16 KiB block without limit. Add an .fcyr harness over sandhi_hpack_decode_field_a as the already-filed parser-fuzzing issue calls for.

**Status:** FIXED in 6.7.18 — sandhi 1.13.7 `a683fb7`, `d69944b` (sandhi), vendored byte-identical by the refold (`a5aa7c3dd`): a size update above the advertised 4096 is a decoding error, an h2 response's decoded header list is bounded at 65,536 octets; the audit's `hpack_tbl.cyr` prints `ok: capped`.

## `CYRIUS-2026-0045` — PDF Flate bomb guard bypassed: a failed decode is never cached or charged to the per-document budget, so every page reference re-inflates it into fresh, never-freed buffers

**Severity:** P2 · **Kind:** vulnerability · **Surface:** bayan · **Where:** `lib/bayan.cyr (bayan 1.11.0; upstream /home/macro/Repos/bayan/src/pdf.cyr)` lib/bayan.cyr:15697-15698 (bayan_pdf_stream_data_a: `var d = _pdfp_decode_chain_a(...)`, `if (d == 0) return empty`, so only a success is memoized); 11542-11613 (_pdfz_inflate_a: every retry does `alloc_via(a, cap + 1)` at 11580 and doubles cap up to 64 MiB, and _pdfz_budget is called only on success, at 11598); 9500 (_PDF_MAX_INFTOT, '512 MiB per document (bomb guard)'). Upstream: pdf.cyr:6351-6352, 2197-2270, 2083-2092, 154
**Attacker / boundary:** A remote party uploads a PDF to a service that extracts its text with bayan_pdf_extract_text / page_extract_text, with an inflate hook installed as bayan documents for 'a consumer parsing untrusted PDFs'. The boundary is the service's file-upload input; the result is memory exhaustion and an OOM kill (DoS).

**Impact.** A tiny file drives unbounded allocation, and the documented 512 MiB per-document bomb guard never fires because failures are not charged. All four runs are on the default allocator.
- Bare &zlib_decompress hook: a 25 KB file reached alloc_used 1.91 GB and RSS 1.78 GB in 6 s, at about 40 MB per page.
- The recommended ratio-capped hook (zlib_decompress_with_ratio_cap, ratio 100): a 66 KB, 400-page file reached alloc_used 1.96 GB and RSS 1.92 GB.
- The same with one page object repeated in /Kids: a 22 KB file reached RSS 1.92 GB.
Growth is linear in page references, and _PDF_MAX_WALK allows about 1M of them at roughly 6 bytes each. A 50-100 KB file therefore drives tens of GB.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
# gen_bomb.py writes N pages that all use object 3: a /FlateDecode stream of 20,000,000 spaces (19 KB compressed).
# zlib_decompress's 16 MiB ceiling makes every inflate fail.
python3 -I gen_bomb.py bomb_fail_48.pdf 48 20000000   # 25299 bytes
# p_bomb.cyr: bayan_pdf_set_inflate(&zlib_decompress); doc = bayan_pdf_parse(src); bayan_pdf_extract_text(doc); print alloc_used()
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_bomb.cyr > ~/.cache/l6718/audit/bayan/p_bomb); chmod +x p_bomb
./p_bomb bomb_fail_4.pdf    # pages=4  alloc_used=161293680
./p_bomb bomb_fail_16.pdf   # pages=16 alloc_used=638480864  (RSS 605 MB from 21.6 KB)
./p_bomb bomb_fail_48.pdf   # pages=48 alloc_used=1910981568 (RSS 1.78 GB, 5.98 s)
# Recommended hook, wrapper returning zlib_decompress_with_ratio_cap(src,n,dst,cap,100):
./p_bomb_rc bomb_fail_400.pdf        # 66390 bytes -> alloc_used=1963982424, RSS 1.92 GB
python3 -I gen_bomb_rep.py bomb_rep_fail_400.pdf 400 20000000   # one page object, /Kids repeats '4 0 R' 400 times: 22297 bytes
./p_bomb_rc bomb_rep_fail_400.pdf    # alloc_used=1963435112, RSS 1.92 GB
# Control: the same stream at 15,000,000 bytes (it succeeds, so it is cached). alloc_used stays at 62 MB for 8 to 128 pages.

**Verified (confirmed).** I rebuilt this independently with my own generator (~/.cache/l6718/audit/verify-bayan/gen/mkpdf.py writes a well-formed PDF with an xref) and my own harness (src/vpdf.cyr, built with build/cycc).

With the bare &zlib_decompress hook and pages sharing one 20,000,000-byte FlateDecode stream (sankoch's 16 MiB ceiling makes every inflate fail):
- fail_d_4 (20,323 B): alloc_used_after_extract=162,359,664, VmHWM 152,732 kB, err_count=4.
- fail_d_16 (21,906 B): alloc_used 639,914,936, VmHWM 601,244 kB.
- fail_d_48 (26,130 B): alloc_used 1,913,397,208, VmHWM 1,813,660 kB, err_count=48, err='FlateDecode failed (the inflate hook reported an error)'.
- fail_r_48 (20,216 B; one page object repeated 48 times in /Kids): alloc_used 1,913,347,576, VmHWM 1,811,612 kB.

With the recommended hook (zlib_decompress_with_ratio_cap, ratio 100):
- fail_d_400 (73,205 B): alloc_used 1,966,311,736, VmHWM 1,928,348 kB, 5.9 s.
- fail_r_400 (22,329 B): alloc_used 1,965,890,392, VmHWM 1,928,348 kB.

Control: the same stream at 15,000,000 bytes decodes successfully and is memoized. alloc_used is 62,997,976 at 16 pages and 63,092,664 at 64 pages, with VmHWM about 50 MB in both.

Code reading confirms the mechanism:
- lib/bayan.cyr:15697-15698 memoizes only a non-zero decode.
- _pdfz_inflate_a (11542-11613) does alloc_via(a, cap+1) on every doubling and never frees.
- _pdfz_budget is reached only on success (11598), so _PDF_MAX_INFTOT (9500) never sees a failure.
- default_alloc is the bump allocator, where free is a no-op.
- Upstream /home/macro/Repos/bayan/src/pdf.cyr:6351 and 2252 are identical.

On classification: the documented untrusted-PDF use, the explicit bomb guard it defeats, and the CYRIUS-2026-0031 ('remote-driven unbounded growth is DoS') and 0010/0004 (library API in its normal untrusted use) precedents make this a vulnerability. P2 is consistent with 0004 (a library-level flaw with no in-tree network caller).

**Fix (planned).** Make a failed decode as sticky as a successful one: bayan_pdf_stream_data_a should record a failure on the stream cell (a sentinel in the cache slot) and return the empty Str at once on later calls. In _pdfz_inflate_a, charge the budget for what each attempt costs: before calling the hook, charge `cap` (the buffer about to be allocated) against _PDF_MAX_INFTOT, or clamp cap to the remaining budget and fail when it is exhausted. Do not wait for a successful final n. Reuse one buffer across retries (realloc_via) rather than allocating a fresh one per doubling. Also stop trusting /DL beyond the remaining budget. Add a regression row with a page tree whose pages share one failing Flate stream, asserting that alloc_used stays bounded as pages grow.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `1672fbc`, `d301d58` (bayan), vendored byte-identical by the refold (`48fc2a219`): a failed decode is memoised, each inflate attempt charged before its buffer exists, rejected buffers freed; the audit's files: 42 MB / 7.9 MB.

## `CYRIUS-2026-0046` — compile() and its sibling emitters open the predictable '<output>.tmp.<pid>' temp with O_CREAT|O_TRUNC, without O_EXCL or O_NOFOLLOW: this is the CYRIUS-2026-0034 class, left unfixed in the CLI's own build path

**Severity:** P3 · **Kind:** vulnerability · **Surface:** local-fs · **Where:** `cbt/build.cyr` 1821-1837 (unchecked sys_unlink, then a probe open with O_WRONLY|O_CREAT|O_TRUNC), 1882 (the child reopens the same way), 1925 (rename); the same shape at 105-112 (_emit_js), 306 (the cx emit tmp_out) and cbt/pulsar.cyr:60 ('<out>.pulsar.new')
**Attacker / boundary:** Another local unprivileged user, across a shared sticky directory such as /tmp or /private/tmp, when the developer points `cyrius build`'s output into it (for example `cyrius build x.cyr /tmp/x`). Without this temp, the sticky bit already keeps the attacker away from the final name.

**Impact.** The temp name is predictable (it is the output path plus the CLI's pid). In a sticky directory, the victim cannot unlink a link someone else planted there, and the unlink's result is ignored. The next open(O_CREAT|O_TRUNC) then follows the planted symlink, so a file the victim can write gets truncated and overwritten with the build output. The later rename of a source the victim does not own fails with EPERM, so the result is an integrity / DoS clobber, not code execution. On Linux, the default fs.protected_symlinks=1 blocks this in a world-writable sticky directory. It is not blocked in a group-writable sticky directory, or on macOS, which has no such sysctl. Exposure depends on the developer choosing a shared output directory, so the same 'conditional' judgement as 0034 applies; the classification is the ledger owner's call.

**Repro (scanner).** Static evidence only. strace is not installed, and a demonstration across users would need an attack harness, which I chose not to build. Run `sed -n 1821,1837p cbt/build.cyr; sed -n 1880,1884p cbt/build.cyr`: it shows `sys_unlink(tmp_out);` with its result discarded, then `sys_open(tmp_out, O_WRONLY | O_CREAT | O_TRUNC, 0x1ED)` both in the parent probe and in the child. Compare lib/io.cyr:964-975 `_io_tmp_open`, the 6.6.20 fix for this exact class (O_EXCL|O_NOFOLLOW, a taken name skipped). That fix was applied to file_write_atomic / _aw_open, but compile() was never migrated. The 2026-07-27 audit (docs/audit/2026-07-27-security-audit.md:195-201) said 'rename replaces a planted symlink rather than following it'. That is true of the rename, but the open before it does follow the link.

**Verified (confirmed).** Code: cbt/build.cyr:1821 discards the result of `sys_unlink(tmp_out);`. Then 1836 (the parent probe) and 1882 (the child) both run `sys_open(tmp_out, O_WRONLY | O_CREAT | O_TRUNC, 0x1ED)`, without O_EXCL or O_NOFOLLOW. _emit_js (build.cyr:105-112), the cx emit (build.cyr:306) and pulsar.cyr:60 have the same shape. cbt/ and lib/ have not changed since the 6.7.17 tag (`git diff --stat 6.7.17 HEAD -- cbt lib src` is empty), and the installed CLI equals the 6.7.17 slot.

Test 1, single user. I made the output directory non-writable so that the unlink fails, the same way a sticky directory makes it fail for another user's link (~/.cache/l6718/audit/verify-local-fs/f1). Command: `sh -c 'ln -s $PWD/victim.txt D/x.tmp.$$; chmod 555 D; exec cyrius build hello.cyr D/x'`. Output: `error: could not rename the temp output onto: D/x` / `FAILED`. victim.txt (0600) went from 24 bytes of text to `-rw------- 4456 ... ELF 64-bit LSB executable`.

Test 2, real cross-user, in a user namespace (f1x.sh). The victim was ns-uid 0 with all capabilities dropped, so the sticky bit binds it. The attacker, uid 1001, planted `x.tmp.<victim pid>` -> victim file. (a) Directory mode 1777: `error: cannot write output`, victim file intact (16 bytes, 'VICT'). protected_symlinks=1 blocked the open, so the finding's Linux caveat is correct. (b) Directory mode 1770, a group-writable sticky directory: `error: could not rename the temp output onto` and the victim's 0600 file became 4456 bytes starting `177 E L F`. The attacker's link survived, the rename failed with EPERM as predicted, and there was no code execution.

The 2026-07-27 audit text (lines 193-199) covers only the rename, not the open before it. Severity and kind agree with the precedents: CYRIUS-2026-0034 (same class, conditional, got an id) and 0036 (pid-predictable O_CREAT|O_TRUNC, got an id). macOS was not measured (no SSH); that part is inferred from it having no protected_symlinks.

**Fix (planned).** Create the output temp exclusively, the way lib/io.cyr already does. In the parent, replace the probe open with `_io_tmp_open(output, &fd)`, or with an open using O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW over '<output>.tmp.<pid>[.N]' that skips a taken name up to a bound and then refuses by name. Keep that fd and hand it to the child: open it before the fork and dup2 it to fd 1 in the child, instead of reopening by name. Apply the same change to _emit_js (build.cyr:105-112), the cx emit (build.cyr:306) and _pulsar_raw_compile (pulsar.cyr:60). Add a row to tests/gates/toolchain/atomic_temp_exclusive.sh that plants a link at the output's '.tmp.<pid>' name and checks that the target is untouched.

**Status:** FIXED in 6.7.18 — `5e72dfb10` (local): the output temp is `<out>.tmp.<n>` (62 bits of the OS CSPRNG), created O_EXCL|O_NOFOLLOW in the parent and handed to the child; row `atomic_temp_exclusive.sh` axes 6–8.

## `CYRIUS-2026-0047` — file_write_atomic / _aw_open create the temp at 0644 & ~umask and only then fchmod it to the destination's mode: for a moment, the temp beside a 0600 file is world-readable

**Severity:** P3 · **Kind:** vulnerability · **Surface:** local-fs · **Where:** `lib/io.cyr` 969 (_io_tmp_open creates the temp with mode 0x1A4), 1001-1011 (_io_keep_mode fchmods it afterwards), 1071; cbt/core.cyr:355
**Attacker / boundary:** No shipped attack path I can show. It would take another local user who can traverse the destination's directory and who opens the empty temp in the gap between its creation and the fchmod. File permissions are checked only at open, so an fd opened in that gap could later read the bytes written. No shipped caller writes a secret through file_write_atomic: sigil writes its trust store with public keys and signatures, cyrsign writes .sig, and cyrsign keygen prints to stdout.

**Impact.** The doc comment promises that a 0600 file stays 0600 when it is replaced, but the inode that carries the new bytes is 0644 & ~umask until the fchmod. A consumer that rewrites a secret with this primitive (a token or credential file) in a directory others can traverse has a window in which it can be disclosed.

**Repro (scanner).** I ran ~/.cache/l6718/audit/local-fs/modewin.cyr (built with `cyrius build modewin.cyr modewin`, umask 022). It calls the stdlib's own `_io_tmp_open` and `_io_keep_mode` on a 0600 file and stats the temp between the two calls. Actual output: `dest mode (decimal, 384=0600): 384` / `temp mode right after _io_tmp_open: 420` / `temp mode after _io_keep_mode: 384`.

**Verified (confirmed).** Code: lib/io.cyr:969 `file_open(tmp, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0x1A4)`, then file_write_atomic:1071 / cbt/core.cyr:355 call `_io_keep_mode` (xstat + fchmod) and only then write.

Test 1, deterministic (my own ~/.cache/l6718/audit/verify-local-fs/f2/modecheck.cyr, umask 022). Output: `destination mode (octal 600 = 384): 384` / `temp mode right after _io_tmp_open ...: 420` / `temp mode after _io_keep_mode: 384`.

Test 2, real cross-user race (f2race.sh, user namespace). The victim, ns-uid 0 with capabilities dropped, replaces a 0600 secret.txt 3000 times via file_write_atomic. The attacker, uid 1001, watches the directory with inotify and opens each new .cyrtmp. temp. The attacker's direct read fails: `cat: secret.txt: Permission denied`. Unpinned run: `temps seen=3000 opened=15 denied(after fchmod)=2984`, and each held fd reads `b'TOPSECRET-0600-ONLY\n'`. Same-CPU run: `opened=1204` of 3000. The finder's mode observation is right, but the window is practically winnable, not merely theoretical.

Classification: the finder said hardening because no shipped caller writes a secret, which I confirmed. The callers are sigil's trust store, cyrsign .sig, ark db, cyrius.lock, vendored lib, distlib, and cyrius-init; cyrsign keygen prints to stdout. However, the ledger's CYRIUS-2026-0034 gave an id to this same primitive with exposure conditional on a caller ('no shipped caller writes into a shared directory'). The doc comment promises 'a 0600 file stays 0600', and the disclosure is measured, so by that precedent this is a conditional P3 vulnerability. If the owner reads 0034 differently, it falls back to hardening.

Fix caveat: creating the temp at 0600 and only widening changes what a NEW file gets (today 0644 & ~umask), because _io_keep_mode returns early when the destination does not exist. The fix must therefore widen a fresh file to 0644 & ~umask explicitly.

**Fix (planned).** Create the temp with the narrowest mode and widen it afterwards, never the reverse. In `_io_tmp_open`, pass 0600 (0x180), or the destination's current mode masked with 0777 when it can be stat'ed before the create, as the create mode. After that, `_io_keep_mode` only ever widens, for example to 0644 or 0755 for a non-secret file. The fd is held from the create onward, so no other user can open the inode while it is narrow. Add a row to tests/tcyr/crossos/atomic_write_temp_exclusive.tcyr that asserts the temp's mode right after `_io_tmp_open` is never wider than the destination's.

**Status:** FIXED in 6.7.18 — `7c71c6075` (local): the temp is created at the destination's mode and only ever widened; row `atomic_write_temp_exclusive.tcyr`.

## `CYRIUS-2026-0048` — On Windows, the CLI's load_environ() opens the drive-relative rooted path '/proc/self/environ' (that is, <current drive>:\proc\self\environ, which any local user can create) and reads it to EOF with unchecked doubling allocations

**Severity:** P3 · **Kind:** vulnerability · **Surface:** local-fs · **Where:** `cbt/core.cyr` 595-611 (load_environ: only macOS is guarded, so the Windows build falls through to file_open("/proc/self/environ"); the growth `alloc(cap * 2)` at ~607 is unchecked before its memcpy); called unconditionally from cbt/cyrius.cyr:594
**Attacker / boundary:** Another local user on Windows who plants C:\proc\self\environ: the CYRIUS-2026-0012 / 0014 / 0020 drive-relative class. I found no value-level impact. On Windows, nothing reads `_envp` entries: the POSIX child-env builders are not on the Windows path, the pinned re-exec at cyrius.cyr:432-434 exits on WIN before using it, and pulsar refuses non-x86-Linux hosts. So no attacker-chosen environment reaches a decision.

**Impact.** Every cyrius.exe run whose current drive holds a planted file reads that file whole into memory. The doubling allocations are never freed and the growth alloc is unchecked, so a large planted file could cost other users' CLI runs time and memory, or crash them. I measured none of this; it is inferred from the code. lib/io.cyr already knows the hazard: its env_block comment at lib/io.cyr:1767-1773 (6.7.16) refuses this exact path on Windows for this reason, but the CLI's own reader was not given the same guard.

**Repro (scanner).** Static: `sed -n 595,603p cbt/core.cyr` shows `#ifdef CYRIUS_TARGET_MACOS ... #endif` followed by an unguarded `var fd = file_open("/proc/self/environ", 0, 0);`. Compare `sed -n 1767,1782p lib/io.cyr` (env_block returns 0 under CYRIUS_TARGET_WIN, with the drive-relative rationale) and cbt/core.cyr:1043-1049 (find_tools wraps its own _cbt_environ call in #ifndef CYRIUS_TARGET_WIN). I did not run it under wine or on cass.

**Verified (confirmed).** Code: cbt/core.cyr:595-611. Only CYRIUS_TARGET_MACOS returns early, so the PE build runs `file_open("/proc/self/environ", 0, 0)`. Its growth `var nb = alloc(cap * 2); memcpy(nb, buf, n);` is unchecked. The call is unconditional from main (cbt/cyrius.cyr:594). Windows sys_open passes the path to CreateFileW without translating it. alloc_windows.cyr returns 0 when size > ALLOC_MAX (0x80000000).

Test 1: I cross-built the PE CLI from the tree (`src/main_win.cyr | cycc > cc_win; cbt/cyrius.cyr | cc_win > cyrius.exe`) and ran `cyrius.exe --version` under wine with WINEDEBUG=+file, in a throwaway prefix. The trace shows `CreateFileW L"/proc/self/environ" GENERIC_READ ...` followed by `ReadFile ... 16383` and `ReadFile ... 12928` to EOF, which is load_environ's 16384-byte buffer.

Wine routes a rooted '/...' path to the Unix filesystem (`\\??\\unix\\proc\\self\\environ`), so a plant at C:\proc does not show under wine. Wine diverges from real Windows here, which is probably why wine-based testing never saw this.

Test 2 (bigenv.sh): I put a tmpfs over /proc in a user+mount namespace so that the path the PE CLI opens is a file I control. With no file: `cyrius.exe exit=0`, `cyrius 6.7.17`. With a 2,306,867,200-byte sparse file: `exit=5 elapsed=7s`, `wine: Unhandled page fault on write access to 0000000000000000 at address 000000014000149B`, r8=0x7fffffff (n = cap-1), and 0x80000000 (cap) on the stack. That is the memcpy into the failed alloc(2^32).

I did not run the C:\proc resolution on cass (no SSH). It rests on Windows' rooted-path semantics, which the cass-confirmed 0012/0014/0020 established and lib/io.cyr:1767-1773 (env_block) already acts on.

The finder's 'no value-level impact' holds. Windows sys_execve is a stub returning -1 (lib/syscalls_windows.cyr:588). _cfg_env uses _win_getenv_alloc. The pinned re-exec exits via _win_redirect_to_pinned before it reads _envp. _cbt_environ's only caller (core.cyr:1049) is under #ifndef CYRIUS_TARGET_WIN.

I reclassify the finding from hardening to vulnerability. The DoS the finder only inferred is now measured, and the rule counts a DoS from an unprivileged local position, with the drive-relative planted path on the CLAUDE.md attack-surface map. Fix as proposed: return an empty envp under CYRIUS_TARGET_WIN before any file_open, and check the growth alloc.

**Fix (planned).** Under CYRIUS_TARGET_WIN, have load_environ() set `_envp` to an empty NULL-terminated vector and return before any file_open, because Windows spawns inherit the process environment and never use `_envp`. As defence in depth, check the growth `alloc` (fail closed with an empty envp). Extend the static axis of tests/gates/toolchain/regression_capture_exclusive.sh (the one that refuses rooted literals in lib/) to cover cbt/, so that a rooted POSIX path reachable in the PE build is refused unless it sits under #ifndef CYRIUS_TARGET_WIN.

**Status:** FIXED in 6.7.18 — `10f77cb09`, `811e7d9a9` (local): the PE CLI opens no `/proc/self/environ`, refuses a missing home by name, and fails closed on a refused allocation; row `regression_capture_exclusive.sh` axis 5.

## `CYRIUS-2026-0049` — http_get / http_get_r / http_get_a set no connect or read deadline and keep the socket private, so a malicious or slow server pins the fetching thread forever with no caller remedy

**Severity:** P3 · **Kind:** vulnerability · **Surface:** net-http-ws-dns · **Where:** `lib/http.cyr` http_get (~280), http_get_r (~360), http_get_a (~410): tcp_socket()+sock_connect()+sock_recv loop with no sock_set_recv_timeout/sock_set_send_timeout and no exposed fd
**Attacker / boundary:** The remote server a program fetches from — directly, or via an attacker-supplied URL (crawler, webhook deliverer, link preview). A server that accepts the connection then never sends (or dribbles bytes) holds the client's thread in a blocking recv indefinitely; the caller cannot inject a timeout because http_get owns the socket internally and never returns the fd.

**Impact.** Availability: unbounded thread/worker stall driven by an untrusted peer — the slowloris-against-client analogue of CYRIUS-2026-0017 (rated P2 for the TLS no-deadline case). A pool of fetch workers can be exhausted by servers that merely accept and stay silent. Not memory corruption.

**Repro (scanner).** ~/.cache/l6718/audit/net-http-ws-dns/p2/hhang.cyr: bind+listen a socket, do NOT accept-and-reply, then call http_get on its URL. The kernel completes the TCP handshake from the listen backlog, so http_get connects and blocks in recv forever: `timeout 8 ./hhang` -> exit 124 (prints 'GET http://127.0.0.1:PORT/ (server never answers)' and never 'http_get returned'). net.cyr already provides sock_set_recv_timeout, but http.cyr never calls it.

**Verified (confirmed).** Code: lib/http.cyr contains no sock_set_*, setsockopt, SO_RCVTIMEO or net_connect_nb (grep count 0). http_get (251-332), http_get_r (~338-390) and http_get_a (~392-457) each run tcp_socket, then a blocking sock_connect (294/354/425), then a sock_recv loop (320/363/446) that only stops on error, EOF or 64 KiB. tcp_socket (net.cyr) sets no default timeout either. The fd is local and never returned, so the caller cannot add one; the only external remedy would be a process-wide SIGALRM to force EINTR, since sock_recv turns n<0 into Err.

Verifier repro, from scratch (~/.cache/l6718/audit/verify-net-http-ws-dns/f3/hang.cyr): bind 127.0.0.1:0, listen, never accept or reply, then call http_get on it. Output: `http://127.0.0.1:49113/x -> calling http_get`, then nothing. `timeout 8 ./hang` gave exit=124, and 'http_get returned' was never printed.

Classification: this is the weakest of the three. Mainstream HTTP clients without a default timeout are usually treated as hardening, but they all let the caller set one, and this API has no remedy at all. It differs from CYRIUS-2026-0017, where the attacker defeated a timeout the caller had set. It meets the ledger's letter (remote position, availability) only if the user accepts the 0010 'whoever supplies a URL the program fetches' boundary for availability as well as memory corruption. If the user rules that a fetched endpoint stalling its own response is caller policy, this becomes a hardening issue (P3, no id). The behaviour itself is confirmed.

**Fix (planned).** Apply a default SO_RCVTIMEO (and SO_SNDTIMEO) to the socket in _http_prepare/http_get before the connect+recv loop, and/or add a timeout parameter to the http_get family so a caller fetching untrusted URLs can bound the exchange; net_connect_nb would also cap the connect phase. Document the default. Mirror the deadline discipline CYRIUS-2026-0017 added to the TLS stack.

**Status:** FIXED in 6.7.18 — `83eca3cd0` (net): every wait bounded by `HTTP_IDLE_TIMEOUT_MS` (5 s) and the exchange by `HTTP_TIMEOUT_MS` (30 s); row `tests/tcyr/crossos/http_get_deadlines.tcyr`.

## `CYRIUS-2026-0050` — pam_unix_authenticate kills its own process with SIGPIPE when the password exceeds the pipe capacity (or the helper exits before reading): a remote client can crash a password-checking daemon pre-auth

**Severity:** P3 · **Kind:** vulnerability · **Surface:** auth-secrets · **Where:** `lib/pam.cyr` 126-130 (`sys_write(wfd, password, plen)`: one unchecked write to a pipe, no SIGPIPE protection, no length cap)
**Attacker / boundary:** A remote unauthenticated client of a network service that verifies its submitted password with pam_unix_authenticate. The module documents this use: shadow.cyr says 'e.g. an unprivileged daemon ... needs to verify a password'. The client crosses the network to terminate the whole server process. The same SIGPIPE-from-a-stdlib-write class was ledgered as CYRIUS-2026-0021/0025. In the setuid-consumer case the password's author kills only their own invocation, which is a bug, not a vulnerability.

**Impact.** Pre-auth remote denial of service. A password longer than 65,536 bytes leaves the parent blocked in write. unix_chkpwd reads a bounded prefix and exits, the write takes EPIPE, and SIGPIPE at default disposition terminates the caller, so pam_unix_authenticate never returns. The same root cause turns the exec-failure path (child exits 127 before the write) into a SIGPIPE death instead of PAM_AUTH_EXEC_FAILED. It only reaches consumers that accept passwords over 64 KiB, and many protocols cap them lower.

**Repro (scanner).** cd /home/macro/Repos/cyrius
  for n in 1000 65536 65537; do cat ~/.cache/l6718/audit/auth-secrets/pam_pw_$n.cyr | build/cycc > ~/.cache/l6718/audit/auth-secrets/pam_pw_$n; chmod +x ~/.cache/l6718/audit/auth-secrets/pam_pw_$n; ~/.cache/l6718/audit/auth-secrets/pam_pw_$n </dev/null; echo n=$n exit=$?; done
    calling pam_unix_authenticate (password 1000 bytes)  / returned rc=1 / n=1000 exit=0
    calling pam_unix_authenticate (password 65536 bytes) / returned rc=1 / n=65536 exit=0
    calling pam_unix_authenticate (password 65537 bytes) / n=65537 exit=141   (128+SIGPIPE; never returned)
The probe calls pam_unix_authenticate("cyraudit_no_such_user", <n x 'A'>) against the host's real /usr/sbin/unix_chkpwd (Linux-PAM 1.7.3), so no real account was tried.

**Verified (confirmed).** My own probe, ~/.cache/l6718/audit/verify-auth-secrets/v_pam.cyr, takes the password length from argv and calls pam_unix_authenticate("cyrverify_absent_user", <n x 'z'>) against the host's setuid /usr/sbin/unix_chkpwd (pam 1.7.3-1). Results: n=0 `after rc=1` exit=0; n=512 rc=1 exit=0; n=1000 rc=1 exit=0; n=65536 rc=1 exit=0. For n=65537, 70000 and 1048576 it printed `before n=…` and then exited 141 (128+SIGPIPE) without ever printing `after`. Code: lib/pam.cyr:126-130 is a single `sys_write(wfd, password, plen)` with no length cap, no short-write loop, no SIGPIPE guard and no MSG_NOSIGNAL path, so default SIGPIPE terminates the whole process. The exec-failure half (child exits 127 before the write) is a race, not deterministic: with a short password the parent's write usually finishes before the child's failed execve exits. I did not reproduce it; the code reading supports it only as a race. lib/shadow.cyr:12 documents the unprivileged-daemon use. The precedent is CYRIUS-2026-0021/0025 (stdlib SIGPIPE killing servers). Reach needs a consumer that accepts passwords over 64 KiB with SIGPIPE at its default disposition. That is plausible for HTTP basic auth or JSON login bodies, and P3 fits. The setuid-consumer case, where the password's author kills only their own run, is a bug, as the scanner says.

**Fix (planned).** (1) Refuse a password longer than PAM_MAX_RESP_SIZE (512 bytes, the most unix_chkpwd reads) up front with PAM_AUTH_FAIL, before forking. That bounds the write well under any pipe capacity and matches what the helper could ever check. (2) Make the write unable to raise SIGPIPE. Give the helper its stdin through socketpair(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC) and write with send(..., MSG_NOSIGNAL), or block SIGPIPE on the calling thread around the write and consume any pending one with sigtimedwait. Loop over short writes. (3) Treat EPIPE as 'the helper did not take the bytes' and still waitpid for the verdict, failing closed unless it exits 0, so the exec-failure path reports PAM_AUTH_EXEC_FAILED. Add a crossos/linux .tcyr with a 65,537-byte password that must return PAM_AUTH_FAIL, not die.

**Status:** FIXED in 6.7.18 — `f347bdbc9` (local): a password over 512 bytes is PAM_AUTH_FAIL before anything runs, and the parent holds the pipe's read end through its write; with `bf8e1ed52` (the password sent NUL-terminated) and `e90c9ff84` (libs: the bound a const); row `pam_fail_closed.tcyr`.

## Finding 15 (bug) — YAML parser is quadratic in mapping size: each key's duplicate check walks the whole object

**Severity:** P2 · **Kind:** bug · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/yaml.cyr)` lib/bayan.cyr:7875 (`if (bayan_json_v_obj_get_by_str(obj, dupk) != 0)` inside _yp_parse_mapping, 7784); upstream yaml.cyr:850
**Attacker / boundary:** No cyrius-shipped component parses untrusted YAML, so this is a bug. It becomes a remote CPU DoS in any service that runs bayan_yaml_parse or frontmatter_split on submitted documents (mneme frontmatter, agnosai definitions): the attacker is the submitter, and the boundary is that service's input.

**Impact.** Parse time is O(n^2) in the number of keys at one level: 5,000 keys / 60 KB take 0.24 s, 10,000 / 120 KB take 0.94 s, 20,000 / 240 KB take 3.65 s, and 40,000 / 480 KB take 14.4 s. That extrapolates to about 1 min for 1 MB and about 4 min for 2 MB. The JSON tree parser appends in O(1), and the TOML tree parser indexes keys with a hash for exactly this reason (toml_tree.cyr:46, 'not O(n^2)').

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
# p_yaml_dup.cyr builds 'k1000000: 1\n' ... n lines and calls bayan_yaml_parse_buf
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_yaml_dup.cyr > ~/.cache/l6718/audit/bayan/p_yaml_dup); chmod +x p_yaml_dup
for n in 5000 10000 20000 40000; do time ./p_yaml_dup $n; done
# bytes=60000 keys=5000 0.24s | bytes=120000 keys=10000 0.94s | bytes=240000 keys=20000 3.65s | bytes=480000 keys=40000 14.36s

**Verified (confirmed).** My probe (~/.cache/l6718/audit/verify-bayan/src/vquad.cyr, mode y) builds 'k1000000: 1\n'... and calls bayan_yaml_parse_buf. Timings (top_len equals keys in every run):

| keys | bytes | time |
|---|---|---|
| 5,000 | 60,000 | 263 ms |
| 10,000 | 120,000 | 1,044 ms |
| 20,000 | 240,000 | 4,056 ms |
| 40,000 | 480,000 | 16,030 ms |

That is about 4x per doubling, so quadratic. The same key count through the JSON tree parser (mode j) takes 3, 4, 7 and 13 ms. The cause is the linear bayan_json_v_obj_get_by_str -> _jp_obj_lookup walk at lib/bayan.cyr:7875 (upstream yaml.cyr:850) on every insert.

**Fix (planned).** Keep duplicate-key refusal, which is the right semantics (yaml.cyr:840-847), but answer it with a per-parse hash index keyed on (object, key bytes), as toml_tree.cyr's _tv_index / _tv_find do, instead of a linear bayan_json_v_obj_get_by_str per insert. The index can live in a small context next to ps. A regression row should parse 40k keys within a time bound, or assert linear scaling.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `2d0240b` (bayan; the key set's hash seeded, `32de3de`): 40,000 keys 14.4 s → 0.04 s; row `tests/parse_scaling.cyr`.

## Finding 16 (bug) — Streaming JSON parser wraps out-of-range integers and accepts digitless numbers: the tree parser's 1.5.1 fixes were never applied to its sibling

**Severity:** P2 · **Kind:** bug · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/json.cyr)` lib/bayan.cyr:6670-6719 (_js_parse_number). The only validity test is `pos == start` at 6707; there is no _jp_int_fits before `_jp_atoi` at 6714, and no per-part digit counts. Upstream json.cyr:1980-2029. Compare with the tree parser at lib/bayan.cyr:6034-6037 (upstream 1288-1347).
**Attacker / boundary:** No security boundary crossed, so this is a bug. A JSON peer controls the integers that a bayan_json_stream_parse consumer receives: 18446744073709551616 is delivered as 0, and 18446744073709551615 as -1. That is silent value substitution in a network parser, but an attack needs an application decision built on the value.

**Impact.** The streaming parser (named in the filed issue's JSON family) hands callbacks a different number from the one in the document, and reports success. For `[18446744073709551616]` on_int receives 0; for `[18446744073709551615]`, -1; for `[9223372036854775808]`, INT64_MIN. `[-]`, `[-,-]`, `[1.]`, `[1e]`, `[-e5]` and `[-.5]` are all accepted. The tree parser refuses every one of these ('integer is out of range for i64' / 'expected number' / 'expected digits ...'), so the two parsers in one file disagree on the same bytes. Both also accept leading zeros (`[01]` gives 1), which RFC 8259 forbids.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_stream.cyr > ~/.cache/l6718/audit/bayan/p_stream); chmod +x p_stream; ./p_stream
# int 0 / rc 0 / tree: refused: integer is out of range for i64      <- [18446744073709551616]
# int -1 / rc 0 / tree: refused: integer is out of range for i64     <- [18446744073709551615]
# int -9223372036854775808 / rc 0 / tree: refused ...                <- [9223372036854775808]
# int 0 / rc 0 / tree: refused: expected number                      <- [-]
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_stream2.cyr > ~/.cache/l6718/audit/bayan/p_stream2); chmod +x p_stream2; ./p_stream2
# [1.] stream: ... accepted | tree: refused (expected digits after the decimal point)
# [-e5] stream: float-bits 0 accepted | tree: refused (expected number)
# [01] stream: int 1 accepted | tree: accepted [1]

**Verified (confirmed).** My probe (~/.cache/l6718/audit/verify-bayan/src/vstream.cyr) runs each input through bayan_json_stream_parse and then bayan_json_v_parse_buf:
- [18446744073709551616]: stream int=0 rc=0; tree refused: integer is out of range for i64.
- [18446744073709551615]: stream int=-1 rc=0; tree refused.
- [9223372036854775808]: stream int=-9223372036854775808 rc=0; tree refused.
- [-]: stream int=0 rc=0; tree refused: expected number.
- [-,-]: stream int=0 int=0 rc=0.
- [1.]: stream fbits=4607182418800017408 rc=0; tree refused: expected digits after the decimal point.
- [1e]: stream accepted; tree refused: expected digits in the exponent.
- [-e5]: stream fbits=0 rc=0; tree refused.
- [-.5]: stream accepted; tree refused.
- [01]: stream int=1; tree accepted [1].

Code at lib/bayan.cyr:6670-6719 matches the claim: the only check is `pos == start`, and there is no _jp_int_fits before _jp_atoi. Upstream json.cyr:1980 is the same code.

**Fix (planned).** Give both descents one number scanner. Factor the lex half of _jp_parse_number_a (sign; at least one integer digit; a fraction needs a digit; an exponent needs a digit) into a helper that returns the end position and an is_float flag, or -1. Have _js_parse_number use it and refuse through _js_emit_error. On the integer path, call _jp_int_fits(buf+start, int_end-start) before _jp_atoi and emit 'integer is out of range for i64', exactly as the tree parser does. While in that scanner, decide whether to refuse a leading zero followed by a digit (RFC 8259 section 6) in both parsers. That is a behaviour change, so it is bayan's call. Add regression rows for each of the inputs above to both parsers.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `93b98d0` (bayan; the user's decision): one RFC 8259 number scanner for tree and stream, malformed and out-of-range numbers refused by name.

## Finding 17 (bug) — Flat TOML parser is quadratic in dotted-key tables: each new dotted key scans every section opened since the header

**Severity:** P3 · **Kind:** bug · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/toml.cyr)` lib/bayan.cyr:2942 (`target = _toml_section_find(sections, scope, full)`), with _toml_section_find at 2800 (a linear str_eq walk); upstream toml.cyr:1219 and 1077
**Attacker / boundary:** No boundary is crossed: bayan_toml_parse reads configuration the developer chose (cyrius's own manifests among it), so this is a bug. It would be a CPU DoS only for a consumer that runs the flat parser on submitted TOML.

**Impact.** Parse time is O(n^2) in distinct dotted-key prefixes under one header: 5,000 keys / 75 KB take 0.27 s, 10,000 / 150 KB take 1.01 s, and 20,000 / 300 KB take 4.02 s. The strict tree parser (bayan_toml_v_parse) handles the same 300 KB document in 0.03 s.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
# p_toml_dot.cyr builds 'k1000000.x = 1\n' ... n lines; arg2 0 = bayan_toml_parse, 1 = bayan_toml_v_parse
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_toml_dot.cyr > ~/.cache/l6718/audit/bayan/p_toml_dot); chmod +x p_toml_dot
for n in 5000 10000 20000; do time ./p_toml_dot $n 0; done   # 0.27s 1.01s 4.02s
time ./p_toml_dot 20000 1                                       # 0.03s (tree parser)

**Verified (confirmed).** My probe (vquad.cyr, mode t) builds 'k1000000.x = 1\n'... and calls bayan_toml_parse:

| keys | bytes | time |
|---|---|---|
| 5,000 | 75,000 | 314 ms |
| 10,000 | 150,000 | 1,258 ms |
| 20,000 | 300,000 | 4,731 ms |

The strict tree parser (mode v, bayan_toml_v_parse_buf) takes 37 ms on the same 20,000-key document and 79 ms on 40,000 keys. The cause is _toml_section_find (lib/bayan.cyr:2800), a linear str_eq walk from `scope`, called per dotted key at 2942 (upstream toml.cyr:1077 and 1219).

**Fix (planned).** Index the sections opened since `scope` by name, so a dotted key's table lookup is O(1). A small open-addressing table keyed on the joined name, reset when a header moves `scope`, is enough, and toml_tree.cyr's _tv_hash / _tv_find shape can be reused. The O(n^2) str_eq walk then remains only for the rare duplicate-name check. A regression row should time 20k dotted keys.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `6585949`, `a733bbe`, `c2b9404`, `d1f68b2` (bayan): dotted-key tables indexed by name, the index zeroed, freed and seeded; 20,000 keys 4.0 s → 0.02 s.

## Finding 18 (bug) — Base64 decoders accept invalid and non-canonical input: '=' anywhere decodes as zero bits, '====' gives one 0x00 byte, and base64url silently drops a dangling character

**Severity:** P3 · **Kind:** bug · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/base64.cyr)` lib/bayan.cyr:72-80 (_b64_dec_at: `if (ch == 61) { return 0; }` at any position); bayan_base64_decode's out_len looks only at the last two bytes; lib/bayan.cyr:191-245 (bayan_base64url_decode: rem == 1 is neither decoded nor refused, at 206; unbounded '=' stripping; trailing bits are not checked; `alloc` results at the dtbl and out allocations are unchecked). Upstream base64.cyr:44-53, 56-117, 164-217
**Attacker / boundary:** No boundary is crossed in cyrius's own code, so this is a bug. sigil's PEM path (lib/sigil.cyr:1184) hashes the decoded DER, so encoding malleability does not change its pin. A consumer that compares, deduplicates or revokes by encoded string (JWT signatures through base64url, for example) gets multiple accepted spellings of the same bytes.

**Impact.** Strings that are not base64 decode to plausible bytes instead of being refused: `QQ==QUFB` gives 41 00 00 41 41 41, `=AAA` gives 00 00 00, `A===` and `====` give 00, and `Q=Q=` gives 40 04. The non-canonical `QR==` gives 41 (as QQ== does). base64url `Q` gives an empty buffer, `QUFBQ` gives 41 41 41 with the dangling Q dropped, and `QQ=====` gives 41. The source comment claims '=' 'is only legal in the last group, which the length rules above already constrain'. Those rules constrain only the last two bytes.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_b64.cyr > ~/.cache/l6718/audit/bayan/p_b64); chmod +x p_b64; ./p_b64
# std  QQ==QUFB   -> 41 00 00 41 41 41 (len 6)
# std  =AAA       -> 00 00 00 (len 3)
# std  ====       -> 00 (len 1)
# std  Q=Q=       -> 40 04 (len 2)
# url  QUFBQ      -> 41 41 41 (len 3)
# url  Q          -> (len 0)

**Verified (confirmed).** My probe (~/.cache/l6718/audit/verify-bayan/src/vb64.cyr) gives:

Standard base64:
- QQ==QUFB -> 41 00 00 41 41 41 (len 6)
- =AAA -> 00 00 00
- A=== -> 00
- ==== -> 00
- Q=Q= -> 40 04
- QR== -> 41 (non-canonical, same as QQ==)
- !!!! -> REFUSED (alphabet check works)

base64url:
- Q -> len 0
- QUFBQ -> 41 41 41 (dangling Q dropped)
- QQ===== -> 41
- QR -> 41

Code reading confirms the cause. _b64_dec_at (lib/bayan.cyr:72-80) returns 0 for '=' at any position, and out_len looks only at the last two bytes. bayan_base64url_decode strips every trailing '=', ignores rem==1, and leaves its two alloc results unchecked. A refused out alloc can only fault, because it writes at address 0 and up, so that part is a crash rather than corruption.

**Fix (planned).** Refuse in bayan_base64_decode any '=' outside the final group, and in the final group a '=' at position 0 or 1 or a non-'=' after an '='. In bayan_base64url_decode, refuse an unpadded length with remainder 1 and more than two '=' of padding. In both, refuse non-zero trailing bits in the last sextet (RFC 4648 section 3.5 canonical encoding), at least behind a strict flag if lenient decoding is a kept contract. Check the two unchecked `alloc` results in the url decoder. Add rows for each of the inputs above.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `cd55398`, `eb5b084` (bayan; the user's decision): the decoders refuse non-canonical input by name (`bayan_base64_last_error()`), every allocation checked.

## Finding 19 (bug) — ws_connect discards any bytes received in the same TCP segment as the 101 handshake, silently dropping the server's first frame(s)

**Severity:** P3 · **Kind:** bug · **Surface:** net-http-ws-dns · **Where:** `lib/ws.cyr` 131-146 (ws_connect: var resp[512]; one _net_os_recv of 511 bytes, headers checked, remainder dropped)
**Attacker / boundary:** No attacker boundary — the peer is the server the client deliberately connected to and the effect is data loss, not corruption or a cross-trust crossing. Reported as a robustness bug, not a vulnerability.

**Impact.** If a server sends its 101 response and its first WebSocket data frame coalesced into one TCP segment (common for a server that pushes immediately on upgrade), ws_connect reads both into resp[512], validates only the '101', and discards everything after the status bytes. The dropped frame is unrecoverable — the next ws_recv blocks for a frame already delivered and discarded. A protocol/interop defect.

**Repro (scanner).** ~/.cache/l6718/audit/net-http-ws-dns/p2/wshs.cyr: a socketpair where the 'server' writes the 101 response immediately followed by a text frame 0x81 02 'hi' in one write, then shuts down. ws_connect reports WS_OPEN but the subsequent ws_recv returns 0 ('first ws_recv: 0 (the hi frame was consumed by the handshake read)'; exit 0) — the 'hi' frame was swallowed by the handshake read and the shutdown then yields EOF.

**Verified (confirmed).** Code: lib/ws.cyr:131-146 does one `_net_os_recv(sock, &resp, 511)` into `var resp[512]` and checks only bytes 9-11 for '101'. Everything after the header block is discarded, and nothing is carried over to ws_recv_frame or _ws_recv_exact.

Verifier repro, from scratch (~/.cache/l6718/audit/verify-net-http-ws-dns/f4/wsco.cyr): over a socketpair the 'server' writes the 101 response plus frame 0x81 02 'hi' in one write. ws_connect runs, then a second frame 'yo' is written, then ws_recv. Output: `state after ws_connect: 1 (WS_OPEN=1)` then `first ws_recv: yo` (exit 0). The 'hi' frame was swallowed.

Same root, other direction (f4/wslong.cyr): a 101 whose header block is longer than 511 bytes (a 600-byte X-Pad header) followed by 'yo'. ws_recv returns `(null)`: the unread header tail ('zzz...' = 0x7A, parsed as a PONG-opcode frame) is read as frames, desynchronising the stream, and 'yo' is lost.

One fix covers both: read exactly to \r\n\r\n, or keep the leftover bytes in the handle and have the frame reader drain them first. In passing, ws_connect also never checks Sec-WebSocket-Accept; that is not a security issue.

**Fix (planned).** After ws_connect confirms the 101, carry any bytes of resp beyond the end of the header block (the \r\n\r\n boundary) into the frame reader as a pending buffer, or restructure the handshake read to stop exactly at the end of headers so no frame bytes are consumed. Alternatively buffer the leftover in the ws handle and have _ws_recv_exact drain it first.

**Status:** FIXED in 6.7.18 — `aeecfd70e` (net): ws_connect reads the 101's header block to CRLF CRLF (≤ 8 KiB) and keeps the rest for the frame reader; row `tests/tcyr/crossos/ws_client_handshake_leftover.tcyr`.

## Finding 20 (bug) — x509_parse_into: 1-byte out-of-bounds read on a crafted empty-TBS certificate

**Severity:** P3 · **Kind:** bug · **Surface:** sigil · **Where:** `/home/macro/Repos/sigil/src/x509.cyr:949 (vendored /home/macro/Repos/cyrius/lib/sigil.cyr:19213)` sigil/src/x509.cyr:948-949 — `var cur = tbs_cp; if ((load8(der + cur) & 0xFF) != DER_TAG_CONTEXT_0_EXP)`
**Attacker / boundary:** A malformed DER certificate reaches x509_parse_into on the TLS handshake path (a peer's Certificate message) and the Authenticode/TEE paths. The raw read is unguarded against cur == der_len. In principle a peer supplies the bytes; in practice no attacker-reachable crash or disclosure was demonstrated on the real call sites (see impact), so this is classed as a bug / defence-in-depth, not a vulnerability.

**Impact.** After der_walk validates the outer Certificate SEQUENCE and the TBSCertificate SEQUENCE, the code reads `load8(der + cur)` with cur = tbs_cp (the first byte of TBS content) WITHOUT re-checking cur < der_len. When the TBS is empty (inner length 0) and the certificate ends exactly at the TBS, cur == der_len and the load reads one byte past the end of the DER buffer. Every real call site passes a cert that is embedded in a larger allocation (the TLS record/flight buffer in tls_native_hs13/hs12; the PE image buffer in authenticode; a 16 MB over-allocated file buffer in cyrsign), so the extra byte lands in mapped memory and the result is only compared to a tag constant — no crash and no disclosure to the attacker. It is a genuine parser OOB-read defect that would fault only if a cert buffer were sized exactly to its DER length at a page boundary.

**Repro (scanner).** In ~/.cache/l6718/audit/sigil: overread.cyr mmaps two pages, makes the second PROT_NONE, writes the 4-byte certificate `30 02 30 00` (Certificate SEQUENCE len2 { TBS SEQUENCE len0 }) ending at the guard page, and calls x509_parse(p, 4, c). Built with build/cycc. Running it SIGSEGVs (exit 139) at the unguarded load. The control run (same 4 bytes placed one byte earlier so the over-read stays in page one) returns cleanly with x509_parse = 0 (exit 0), confirming the fault is the 1-byte over-read at the version-tag load, not any later logic.

**Verified (confirmed).** Code: sigil/src/x509.cyr:949, byte-identical in vendored lib/sigil.cyr:19213 (the x509_parse_into bodies match, sigil 3.13.13). It runs `if ((load8(der + cur) & 0xFF) != DER_TAG_CONTEXT_0_EXP)` with cur = tbs_cp, without re-checking cur < der_len. der_walk (x509.cyr:145-156) guards `pos >= buf_len` and `content_pos + len > buf_len`, so an empty inner TBS (`30 02 30 00`) passes and gives tbs_cp = 4 = der_len.

Repro, rebuilt from scratch in ~/.cache/l6718/audit/verify-sigil/overread: mmap_anon(8192), cyr_mprotect(base+4096, 4096, PROT_NONE), write `30 02 30 00` so that it ends at the guard page, then x509_parse(p, 4, c); built with build/cycc.
- Guard run: exit=139 (SIGSEGV). Under gdb the fault address is $_siginfo si_addr = 0x7ffff7ff6000. That is page-aligned: exactly der+4 = der+der_len. The faulting instruction is `movzbq (%rax),%rax` followed by `mov $0xff`, which is the load8 & 0xFF shape.
- Control run (the same 4 bytes one byte earlier, so the over-read stays mapped): exit=10, i.e. x509_parse returned 0 cleanly.

The call sites match the scanner's description. tls_native_hs13.cyr:887/909 and hs12.cyr:648 parse a peer cert inside the handshake body buffer, which is bounds-checked against clist_end / blen but embedded in a larger allocation, so the extra byte is mapped. Classification as bug P3 with no id is correct. The fix is to add `if (cur >= tbs_end) { return 0; }` before the load, upstream in sigil, then re-vendor byte-identical. It packs trivially, so per CLAUDE.md it should be repaired in this release rather than filed.

**Fix (planned).** Guard the version-tag read against the TBS/buffer bound before dereferencing: add `if (cur >= tbs_end) { return 0; }` (equivalently `cur >= der_len`) immediately before the `load8(der + cur)` at sig/src/x509.cyr:949, mirroring the guarded `if (cur < tbs_end)` the extensions step already uses. Fix upstream in sigil/src/x509.cyr, release the fold, regenerate dist and re-vendor byte-identical; add a regression cert (`30 02 30 00`) to tests/tcyr/ed25519_strict.tcyr's sibling x509 harness or sigil's x509 test.

**Status:** FIXED in 6.7.18 — sigil 3.13.14 `7dbd6c2` (sigil): an empty TBS refused before the version-tag read; row sigil `tests/tcyr/x509_guard_page.tcyr`.

## Finding 21 (bug) — Post-handshake KeyUpdate flood: unbounded KeyUpdate messages per record drive key-rotation allocations and response amplification with no rate limit

**Severity:** P3 · **Kind:** bug · **Surface:** tls-native · **Where:** `lib/tls_native_hs13.cyr` 1350
**Attacker / boundary:** A remote peer that has completed a native-TLS 1.3 handshake (any client of a public native-TLS server, or a server talking to a native client) over the established encrypted channel; the boundary is the server's CPU/memory availability (denial of service).

**Impact.** _tn_handle_post_handshake loops over EVERY handshake message packed into one decrypted record with no cap, and tls_native_read (lib/tls_native_conn.cyr:1455) drains up to TLS_POST_HANDSHAKE_DRAIN_MAX=32 such records per call. A ~16 KiB record can carry ~3276 KeyUpdate messages (5 bytes each); each calls _tn_rotate_recv_keys, which runs HKDF-Expand-Label and allocates a fresh secret+key+IV (~90 B) from the ctx allocator that is NEVER freed, and for update_requested=1 also sends a response record via _tn_send_key_update. One read() call processes up to ~32x3276 ~= 100k KeyUpdates: ~100k HKDF derivations and ~9-16 MB of allocations before the call fails the connection with TLS_ERR_PROTOCOL. On the DEFAULT server path (tls_accept -> global no-free heap) that memory leaks permanently; across many connections it is unbounded growth. RFC 8446 §4.6.3 expects KeyUpdate rate-limiting; cyrius has none. Same availability class as the fixed CYRIUS-2026-0017, but post-handshake.

**Repro (scanner).** Reasoned from source (no live flood run). _tn_handle_post_handshake (lib/tls_native_hs13.cyr:1350) `while (pos + 4 <= msg_len)` has no message-count cap; for TLS_HS_KEY_UPDATE it calls _tn_rotate_recv_keys (-> _tn_rotate_app_keys:1309 which _tn_allocs newsec/nk/niv and abandons the old) and, when body==1, _tn_send_key_update (:1332). tls_native_read (lib/tls_native_conn.cyr:1455-1500) calls it per record under only the 32-record drain bound. A completed-handshake peer sending application records whose decrypted inner type is handshake(22) and whose content is many `18 00 00 01 00` KeyUpdate messages triggers one rotation+allocation each; grep shows no rate/limit/max guard on KeyUpdate count in the stack.

**Verified (uncertain).** Not reproduced live. A live flood run is outside what I could do in this pass, so I did not build or run a flooding peer. The code reading supports the mechanism:
- _tn_handle_post_handshake (lib/tls_native_hs13.cyr:1350-1373) loops `while (pos + 4 <= msg_len)` over every handshake message in one decrypted record, with no message-count cap.
- It does not refuse several KeyUpdates coalesced in one record (RFC 8446 §5.1 requires KeyUpdate to be record-aligned).
- It does not validate that the body is exactly one byte of 0 or 1.
- Each KeyUpdate calls _tn_rotate_recv_keys -> _tn_rotate_app_keys (:1309). That runs HKDF-Expand-Label plus key and IV derivation and makes three fresh _tn_alloc's (secret _TLS_MAX_DIGEST_LEN, key, IV), abandoning the old ones.
- With update_requested=1, _tn_send_key_update (:1332) also allocates a 64-byte record, writes a response record and rotates the send keys.

One correction to the finding's bound: tls_native_read (lib/tls_native_conn.cyr:1455) applies TLS_POST_HANDSHAKE_DRAIN_MAX=32 per call, and returns as soon as a non-empty application-data record arrives. A peer that interleaves one data record every 31 handshake records therefore resets the guard, so the per-connection total is unbounded while the application keeps reading. It is not capped at ~100k as the finding says.

Memory: on the global-heap path (tls_native_new_server / tls_accept) the abandoned buffers are never reclaimed. On the arena path (tls_accept_alloc_in) the arena's cap bounds growth: _tn_alloc returns 0 -> TLS_ERR_OOM fails the connection.

The finding's own repro is 'reasoned from source (no live flood run)'. Its cost figures (100k HKDF derivations, 9-16 MB) are unmeasured estimates. Under the default-to-refuted rule I mark it uncertain, not confirmed: the code reading supports a real per-byte CPU and memory amplification, but no measurement exists. The ledger precedent CYRIUS-2026-0037 got its P3 id only on measured CPU cost. An id is not warranted until the cost is measured.

**Fix (planned).** Bound post-handshake handshake-message processing per connection (cap the number of KeyUpdate / total post-handshake messages, as OpenSSL/BoringSSL do), and/or reject a record coalescing more than a couple of post-handshake messages (RFC 8446 §5.1). Validate the KeyUpdate body is exactly one byte of value 0/1. Reuse the rotated-out secret/key/IV buffers in place instead of allocating fresh so a bounded flood cannot leak on the no-free heap.

**Status:** FIXED in 6.7.18 — `3b043ec6b` (tls): a KeyUpdate's body exactly one byte 0 / 1, one per record, at most 32 in a row without application data, the keys rotated in place; row `tests/tcyr/crypto/tls_native_key_update.tcyr`.

## Finding 22 (hardening) — Any tag push yields a signed release, and the long-term Ed25519 signing key is handed to code built from the pushed tag (no environment, no tag protection)

**Severity:** P2 · **Kind:** hardening · **Surface:** release-channel · **Where:** `.github/workflows/release.yml` 3-8 (on: push: tags: ['*']; permissions: contents: write), 388-410 (sign step: CYRIUS_RELEASE_SK passed to a cyrsign built from the tag's programs/cyrsign.cyr)
**Attacker / boundary:** Anyone holding a credential with contents:write on MacCracken/cyrius, such as a leaked PAT or a stolen session/SSH key. That is control of cyrius itself, so this is not a ledger vulnerability: it is a missing separation between push access and signing.

**Impact.** Confirmed facts: release.yml runs on a push of ANY tag. Its workflow file and build come from that tag's commit. The repo has zero environments (API total_count 0) and zero rulesets ([]), so no reviewer gate stands between a tag push and secrets.CYRIUS_RELEASE_SK. The secret reaches `$CYRSIGN sign`, a binary compiled in build-x86 from the tag's own programs/cyrsign.cyr (and the tag can also rewrite the sign step). So a single push credential gives a signed, installer-accepted release AND the raw 32-byte seed. Exfiltration bypasses log masking with any encoding. A stolen seed keeps signing offline after the GitHub credential is rotated, until a key rotation ships a new CYRIUS_RELEASE_PUBKEY in install.sh / ci.sh / install.ps1 and raises the installer floor. Today the Ed25519 signature adds protection only against parties who can alter release assets without push access. The same root cause covers `cyriusly install`, which runs install.sh fetched from a mutable (unprotected) tag, and the README's main-branch installer. Third-party actions are fine: checkout 3d3c42e5…, upload-artifact cf430e03…, download-artifact 9000827c… and softprops/action-gh-release efb35369… all match their upstream tag commits (verified via the GitHub refs API). No secret reaches pull_request or fork builds: ci.yml uses none, and release.yml's `uses: ./.github/workflows/ci.yml` passes no `secrets:`.

**Repro (scanner).** sed -n 1,8p .github/workflows/release.yml   -> on: push: tags: ['*'] / permissions: contents: write
sed -n 388,410p .github/workflows/release.yml -> env CYRIUS_RELEASE_SK: ${{ secrets.CYRIUS_RELEASE_SK }}; LX=$(ls dist/cyrius-*-x86_64-linux.tar.gz); tar xzf "$LX" -C /tmp; CYRSIGN=$(find /tmp -type f -name cyrsign | head -1); "$CYRSIGN" sign dist/SHA256SUMS
curl -s https://api.github.com/repos/MacCracken/cyrius/environments -> {"total_count": 0, "environments": []}
curl -s https://api.github.com/repos/MacCracken/cyrius/rulesets -> []
Action pins: for each pin, curl -s https://api.github.com/repos/<owner>/<action>/git/refs/tags/<tag> (dereferencing softprops' annotated tag e598afbe… -> commit efb35369…): all four SHAs match.

**Verified (confirmed).** release.yml:3-8 is `on: push: tags: ['*']` with `permissions: contents: write`. :388-410: the sign step has env `CYRIUS_RELEASE_SK: ${{ secrets.CYRIUS_RELEASE_SK }}`, extracts the just-built linux tarball, then runs `CYRSIGN=$(find /tmp -type f -name cyrsign | head -1)` and `"$CYRSIGN" sign dist/SHA256SUMS`. :45-60 ('Build tools') builds each tool with `cat programs/${tool}.cyr | ./build/cycc`, and that cycc was bootstrapped from the tag's own tree, so the key goes to a binary compiled from the pushed tag's source, and the tag can also rewrite the step itself. API: /environments -> {"total_count": 0}, /rulesets -> [], /branches/main protected:false. Secrets appear only at release.yml:391. ci.yml uses none, and `uses: ./.github/workflows/ci.yml` passes no `secrets:` (no `secrets: inherit`), so PR and fork builds never see the key, as the report says. One action pin spot-checked: actions/checkout refs/tags/v7.0.1 -> 3d3c42e5aac5ba805825da76410c181273ba90b1, a match. install.sh:38 hard-codes CYRIUS_RELEASE_PUBKEY, so a leaked seed stays usable until a key rotation ships. Classification as hardening is correct under the ledger rule.

**Fix (planned).** Put the sign step in a job with `environment: release` and a required reviewer (the maintainer), and move CYRIUS_RELEASE_SK from a repository secret to that environment's secret. Restrict the environment's deployment tags to the release pattern. Add a tag ruleset limiting creation, update and deletion of `*.*.*` tags to the maintainer, so a tag cannot be repointed under `cyriusly install`. Sign with a verifier whose code does not come from the tag being released, e.g. the previous release's pinned cyrsign. Strongest: keep the key out of CI entirely: CI publishes SHA256SUMS, and the maintainer signs it offline and uploads the .sig. Narrow top-level permissions to `contents: read` and grant `contents: write` only to the final release job.

**Status:** FIXED in 6.7.18 (the repository half) — `392197ca7` (local): release.yml is `contents: read` and the one job that holds CYRIUS_RELEASE_SK runs in `environment: release` with `contents: write`. The required-reviewer rule on that environment and the key in its secrets are the user's GitHub settings; until they exist the environment gates nothing.

## Finding 23 (hardening) — pam_unix_authenticate hard-codes unix_chkpwd's "nullok": an account with an empty password field authenticates with an empty password, and a consumer cannot ask for "nonull"

**Severity:** P3 · **Kind:** hardening · **Surface:** auth-secrets · **Where:** `lib/pam.cyr` 114 (`store64(&argv + 16, "nullok")`), 127 (plen == 0 sends nothing, so the helper sees a blank password)
**Attacker / boundary:** No attack path in cyrius alone: it needs an account the administrator left with an empty shadow hash. Then any remote client of a daemon using this helper logs into that account with an empty password, which Linux-PAM's own pam_unix default (no nullok) and sshd's PermitEmptyPasswords=no refuse.

**Impact.** Defence-in-depth: the library's policy is looser than the pam_unix default and cannot be tightened by the consumer.

**Repro (scanner).** grep -n 'nullok' /home/macro/Repos/cyrius/lib/pam.cyr shows line 114, the only mode ever passed, with no parameter or option to change it. Not exercised end to end, because that needs a root-created empty-password account.

**Verified (confirmed).** lib/pam.cyr:114 `store64(&argv + 16, "nullok");` is the only mode passed; there is no parameter or option. At line 127, `if (plen > 0)` skips the write, so an empty password reaches the helper as EOF. The host helper accepts both modes (`strings /usr/sbin/unix_chkpwd` shows nullok and nonull). Two context points the scanner left out. First, lib/pam.cyr:11-12 documents nullok as a deliberate choice ("accept empty passwords — typical for interactive auth"). Second, 'looser than the pam_unix default' is true of the module's built-in default but not of every distro: this Arch host's /etc/pam.d/system-auth:7 passes `pam_unix.so try_first_pass nullok` itself. I did not exercise it end to end, because that needs a root-created empty-password account. The classification holds: the exposure needs an administrator-created empty-hash account, so there is no attacker-crossed boundary from cyrius alone. That makes it hardening, with no id. Switching the default to nonull changes what existing callers get, so it is the user's call.

**Fix (planned).** Default to "nonull" and refuse plen == 0 before forking. Add an explicit opt-in (e.g. pam_unix_authenticate_opts(user, password, PAM_ALLOW_EMPTY)) for the console-login case that wants nullok. Document the change in the CHANGELOG / ecosystem-migration, because it changes what an existing caller gets for an empty-password account.

**Status:** KEPT (the user, 2026-10-22) — `nullok` stays; refusing empty passwords is placed at 6.8.0 (`docs/development/issues/2026-10-22-pam-nullok-empty-password-authenticates.md`). Since `bf8e1ed52` (local) the password is sent NUL-terminated, so an account with an empty hash accepts the empty password only, no longer ANY password.

## Finding 24 (hardening) — JSON accepts duplicate object keys and answers the FIRST, the opposite of most JSON readers; the flat and tree parsers also disagree on escaped keys

**Severity:** P3 · **Kind:** hardening · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/json.cyr)` lib/bayan.cyr:6210-6246 (_jp_parse_object_a appends every pair through bayan_json_v_obj_set_a at 5480; lookups return the first match); the flat parser bayan_json_parse_a returns raw, undecoded keys. Upstream json.cyr:1520-1556, 790-796, 286-364
**Attacker / boundary:** No attack path in cyrius's own code. In a mixed deployment where a bayan component validates or authorizes a JSON body and a last-wins reader (JavaScript, Python, Go encoding/json) acts on it, the client controlling the body can show each side a different value.

**Impact.** `{"role":"user","role":"admin"}` reads as role=user through bayan_json_v_obj_get_by_cstr, bayan_json_v_pointer and the flat bayan_json_get_by_cstr. bayan_json_v_build re-emits both pairs, and every downstream last-wins reader then sees admin. YAML and TOML in this same fold refuse duplicates precisely because 'two components reading the same document disagreeing about a role is exactly the shape a policy file must not have' (yaml.cyr:840-847). Separately, for `{"admin":true}` the flat parser answers admin=absent while the tree parser answers present.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
(cd /home/macro/Repos/cyrius && build/cycc < ~/.cache/l6718/audit/bayan/p_dup.cyr > ~/.cache/l6718/audit/bayan/p_dup); chmod +x p_dup; ./p_dup
# tree lookup role = user
# tree pointer /role = user
# tree re-serialized = {"role":"user","role":"admin"}
# flat lookup role = user
# flat lookup admin in {"admin":true} = absent
# tree lookup admin = present
# yaml same doc: duplicate mapping key
# toml tree same doc: duplicate key

**Verified (confirmed).** My probe (~/.cache/l6718/audit/verify-bayan/src/vdup.cyr) on {"role":"user","role":"admin"}:
- The tree parse is accepted.
- bayan_json_v_obj_get_by_cstr role = user.
- bayan_json_v_pointer_cstr /role = user.
- bayan_json_v_build re-serializes to {"role":"user","role":"admin"}.
- The flat bayan_json_get_by_cstr role = user.

On {"admin":true}, the flat get_by_cstr for admin answers absent while the tree answers present.

The same duplicate document in YAML gives 'duplicate mapping key', and in TOML tree 'duplicate key'. _jp_obj_lookup (lib/bayan.cyr:6908) returns the first match. Whether JSON should refuse duplicates changes what parses, so that is the user's call.

**Fix (planned).** Pick one rule for the fold. The consistent choice is to refuse duplicate keys in bayan_json_v_parse* ('duplicate key', as YAML and TOML do), using a per-parse hash index so it stays O(n); that also covers the YAML quadratic finding's index. If refusal breaks a contract, offer it as a strict flag on the _ctx entry. Document that the flat API compares raw, undecoded keys, which already holds for values, and must not be used for allowlist or denylist checks. Whether to change JSON's default is the maintainer's call, because it changes what parses.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `91440f4`, `32de3de` (bayan; the user's decision): a duplicate key refuses the document in the tree, flat and stream parsers, keys compared decoded.

## Finding 25 (hardening) — PDF text extraction work multiplies with repeated page references to one shared content stream

**Severity:** P3 · **Kind:** hardening · **Surface:** bayan · **Where:** `lib/bayan.cyr (upstream /home/macro/Repos/bayan/src/pdf.cyr)` lib/bayan.cyr:18041-18055 (bayan_pdf_extract_text_a extracts every walked page). The page-tree walk accepts one page object repeated in /Kids, up to _PDF_MAX_WALK = 1,048,576 visits (upstream pdf.cyr:155, 8695-8708).
**Attacker / boundary:** A remote party submits a PDF to a service that extracts its text with bayan. Each extra page costs the attacker about 6 bytes ('4 0 R ') and the service one full scan of the decoded content. This is inherent PDF sharing, so it is filed as hardening rather than as a defect.

**Impact.** A 15.8 KB file with /Kids repeating one page 128 times, whose /Contents is a cached 15 MB stream, takes 11.6 s of CPU (about 90 ms per reference); memory stays flat because the decode is cached. At the 1M-visit walk cap (a file of about 6 MB) that extrapolates to about a day of CPU. Distinct page objects (about 90 bytes each) scale the same way: 32, 64 and 128 pages take 2.96 s, 5.78 s and 11.39 s.

**Repro (scanner).** cd ~/.cache/l6718/audit/bayan
python3 -I gen_bomb_rep.py bomb_rep_128.pdf 128 15000000   # 15807 bytes
time ./p_bomb bomb_rep_128.pdf   # pages=128 alloc_used=62054248 err=   11.57s, 50 MB RSS

**Verified (confirmed).** My generator's 'rep' mode makes one page object repeated N times in /Kids, with /Contents a 15,000,000-byte FlateDecode stream that decodes successfully and is cached:
- ok_r_32 (15,263 B): 3,491 ms.
- ok_r_128 (15,840 B): 12,519 ms, about 98 ms per reference.
- In both, alloc_used is about 63 MB and VmHWM about 50 MB (flat).

The page walk accepted all 128 repeats; err_count=0. The cost is linear in page references, and _PDF_MAX_WALK = 1,048,576 (lib/bayan.cyr:9501) is the only cap. bayan_pdf_extract_text_a (18041-18055) extracts every walked page, and the decoded-bytes budget does not charge scanning.

**Fix (planned).** Charge decoded-content bytes scanned by text extraction against a per-document budget, alongside _PDF_MAX_INFTOT, and stop or refuse once it is exhausted. Alternatively, have the page walk refuse a /Kids that references an already-visited page object: a page with two parents is malformed, and PDF 32000-1 section 7.7.3 requires each page object to have exactly one /Parent. Either change bounds work by file size rather than by reference count.

**Status:** FIXED in 6.7.18 — bayan 1.11.1 `1128283` (bayan): page content handed out is charged to a 512 MiB per-document budget, refused by name.

## Finding 26 (hardening) — `cyrius deps` silently fetches git:// and http:// dependencies over plaintext and commit-pins whatever arrived

**Severity:** P3 · **Kind:** hardening · **Surface:** release-channel · **Where:** `cbt/deps.cyr` 3365-3380 (clone argv: `git clone --depth 1 -q -b <tag> -- <dep_git> <dir>`, no transport check), 2237-2252 (_dep_git_remote recognises any scheme://), 3482-3533 (first resolve: no pin -> TOFU pin written)
**Attacker / boundary:** On-path network attacker (shared Wi-Fi, a compromised router, a CI network) vs. a resolve whose dep graph names a git:// or http:// URL. The URL is written in a manifest the developer or a chosen dependency controls, so under the ledger's manifest rule this is defence-in-depth, not an id.

**Impact.** On the first resolve (no lock pin yet), or after `cyrius update` of an untagged dep, the attacker substitutes the dependency's content. It is vendored into lib/ and compiled into the build, so it runs at test or run time. The lock then pins the attacker's commit, which turns later honest fetches into 'commit-pin mismatch' refusals. Once a pin exists, a later plaintext fetch is caught, because the commit id binds the content.

**Repro (scanner).** S=~/.cache/l6718/audit/release-channel/plain   (already built: a dep repo src/foo with tag 1.0.0 shipping dist/foo.cyr, bare clone $S/foo.git, a throwaway CYRIUS_HOME $S/home/.cyrius with a copy of the 6.7.17 lib/)
git daemon --export-all --base-path=$S --port=19418 --listen=127.0.0.1 --reuseaddr --verbose > $S/daemon.log 2>&1 &
$S/proj/cyrius.cyml:  [deps.foo] git = "git://127.0.0.1:19418/foo.git"  tag = "1.0.0"  modules = ["dist/foo.cyr"]
cd $S/proj && HOME=$S/home CYRIUS_HOME=$S/home/.cyrius $S/home/.cyrius/bin/cyrius deps
Actual: "1 deps resolved" / "cyrius.lock: 1 deps locked, 1 commit-pinned (1 re-verified)", rc=0, lib/foo.cyr vendored, cyrius.lock row `commit 3bb2e4c32f11eb1eb75fa257aed2912ec6196723 foo git://127.0.0.1:19418/foo.git 1.0.0`, daemon log "Request upload-pack for '/foo.git'". No warning about the unauthenticated transport.

**Verified (confirmed).** Code: cbt/deps.cyr:2237-2252 _dep_git_remote accepts any `scheme://`. :3366-3380 clone argv is `env -u GIT_DIR … git -c advice.detachedHead=false clone --depth 1 -q -b <tag> -- <dep_git> <dir>`. Neither _git_env_argv (:5625-5641) nor anything in cbt/ or lib/ sets protocol.allow or GIT_ALLOW_PROTOCOL (grep finds nothing). My repro, from scratch in ~/.cache/l6718/audit/verify-release-channel/plain (throwaway HOME, a copy of the 6.7.17 slot as CYRIUS_HOME, git 2.56.0): `git daemon --port=19518 --listen=127.0.0.1`, then `git ls-remote git://127.0.0.1:19518/foo.git` -> refs/tags/1.0.0 c3010539…. A manifest `[deps.foo] git = "git://127.0.0.1:19518/foo.git" tag = "1.0.0" modules = ["dist/foo.cyr"]` and `cyrius deps` gave "1 deps resolved" / "cyrius.lock: 1 deps locked, 1 commit-pinned (1 re-verified)", rc=0, with no transport warning. The lock row was `commit c3010539008fe606e44a1bd3d9d173a6b8d71994 foo git://127.0.0.1:19518/foo.git 1.0.0`. Next I substituted the served content: same URL, tag 1.0.0 repointed to 41cdb302…, foo_answer returning 7. With the pin present, it was caught: "error: commit-pin mismatch for dep 'foo' tag '1.0.0': cyrius.lock pins c3010539… but the tag now resolves to 41cdb302… — refusing.", rc=1. On a first resolve (lock deleted) it was accepted silently: rc=0, lib/foo.cyr = `fn foo_answer() { return 7; }  # substituted`, and the lock now pins 41cdb302…. This matches the report: TOFU over plaintext, caught only after a pin exists. The server-side swap stands in for a MITM; the plaintext transport itself is shown by the git:// daemon fetch.

**Fix (planned).** Before the clone, refuse remote URLs whose scheme is git:// or http://, naming the dep and URL; allow https://, ssh:// and scp-like `host:path`, plus local paths and file://. Belt and braces: pass `-c protocol.git.allow=never -c protocol.http.allow=never -c protocol.ext.allow=never` on the clone argv, so a URL the scheme check misreads still cannot go plaintext. Whether to offer an explicit opt-in key for a plaintext mirror is the user's call; this changes what manifests resolve, so ask first per the language-change rule.

**Status:** FIXED in 6.7.18 — `1ea3e6530` (local; the user's decision) and `ef2300041` (cleanup): `git://`, `http://`, `ftp://` and every plaintext remote-helper spelling (`http::`, `https::http://…`) refused by name before any fetch; fetching argvs carry `protocol.*.allow=never`; row `deps_plaintext_url_refused.sh`.

## Finding 27 (hardening) — install.sh's header advertises `curl -sSf https://install.cyrius.dev | sh`, a host that does not resolve, on a domain whose ownership is unverified

**Severity:** P3 · **Kind:** hardening · **Surface:** release-channel · **Where:** `scripts/install.sh` 3
**Attacker / boundary:** Whoever controls cyrius.dev's DNS. If that is not the maintainer, a stranger can serve a script to anyone who copies the documented command. The boundary is the release/download channel's advertised entry point.

**Impact.** The usage line, added 2026-04-05 (549732f05), ships inside every tarball's install.sh and in the raw installer people read before piping it to sh. install.cyrius.dev has no DNS record today, so the command currently just fails. cyrius.dev itself is registered (RDAP: OVH sas, created 2025-08-06, expires 2027-08-06, NS dns10/ns10.ovh.net) and serves an OVH 'Site not installed' page. Adding one DNS record makes the line a live curl|sh to arbitrary code. The README uses the raw.githubusercontent URL instead, so exposure is limited to people who follow the script's own comment.

**Repro (scanner).** grep -rn 'install.cyrius.dev' /home/macro/Repos/cyrius  -> scripts/install.sh:3 only
getent hosts install.cyrius.dev -> (nothing)
getent hosts cyrius.dev -> 2001:41d0:301::100
curl -s https://pubapi.registry.google/rdap/domain/cyrius.dev -> registrar OVH sas, registration 2025-08-06T11:07:40Z, status client delete/transfer prohibited
curl -s http://cyrius.dev/ -> <title>Site not installed - OVHcloud</title>

**Verified (confirmed).** scripts/install.sh:3 reads `# Usage: curl -sSf https://install.cyrius.dev | sh`. It is the only cyrius.dev reference in the repo. It was added by 549732f05 (2026-04-05), and release.yml copies scripts/install.sh into dist/. README.md uses the raw.githubusercontent URL instead. DNS: `getent hosts install.cyrius.dev` rc=2 (no record). `getent hosts cyrius.dev` -> 2001:41d0:301::100. RDAP (pubapi.registry.google): registrar OVH sas, registration 2025-08-06T11:07:40Z, expiration 2027-08-06, last changed 2026-08-06, NS dns10.ovh.net / ns10.ovh.net, status client delete/transfer prohibited, registrant redacted. `curl http://cyrius.dev/` -> <title>Site not installed - OVHcloud</title>. The domain was registered ~8 months before this repo's first commit (09a568b28, 2026-04-03), which weakly suggests it may not be the maintainer's, but ownership cannot be established. The facts as reported are all reproduced. It is correctly classified as hardening (a one-line comment fix), with low confidence about who owns the domain.

**Fix (planned).** If the maintainer owns cyrius.dev: keep it but point install.cyrius.dev at the tag-pinned raw URL, or delete the line until it exists. If not owned: replace line 3 with the README's raw.githubusercontent.com URL, preferably tag-pinned. Either way it is a one-line comment edit.

**Status:** FIXED in 6.7.18 — `a41d88eda` (local): the header advertises the README's raw.githubusercontent.com URL; row `install_signature_required.sh` axis 9.

## Finding 28 (hardening) — Rotated-out and handshake-end TLS traffic secrets/keys are abandoned un-zeroized (defense-in-depth gap)

**Severity:** P3 · **Kind:** hardening · **Surface:** tls-native · **Where:** `lib/tls_native_hs13.cyr` 1309
**Attacker / boundary:** No demonstrated attack path — hardening only. Would matter only if process memory later reaches an attacker (core dump, swap, memory-reuse into an attacker-readable buffer); no such channel was found.

**Impact.** On a KeyUpdate, _tn_rotate_app_keys allocates a new secret/key/IV and leaves the previous application-traffic secret/key/IV in the allocator un-zeroized (comment: 'the old key/IV/secret are abandoned to the bump arena'). The retained app-traffic secrets (TLS_CTX_OFF_{SRV,CLI}_APP_SECRET, kept for KeyUpdate) and derived keys/IVs are also never wiped at tls_native_close. This diverges from the stack's own ephemeral-secret discipline (_tn_wipe_ephemeral zeroizes the ECDHE private key and shared secret; the Ed25519 expanded key is a secret var per 6.6.20). Dead copies of live-session traffic keys persist in the process heap/arena. Per the ledger rule this is hardening, not a vulnerability, absent a channel carrying the bytes to an attacker.

**Repro (scanner).** Read lib/tls_native_hs13.cyr:1309 (_tn_rotate_app_keys): old secret/key/IV at secoff/keyoff/ivoff are overwritten with new pointers, no memset of the old buffers; tls_native_close (lib/tls_native_conn.cyr:1537) frees/zeros nothing by design. Contrast _tn_wipe_ephemeral (lib/tls_native_hs13.cyr:2095) which memsets EPH_PRIV and SHARED.

**Verified (confirmed).** Code reading, confirmed:
- _tn_rotate_app_keys (lib/tls_native_hs13.cyr:1309-1328) store64's new secret, key and IV pointers over the old ones without memset; its own comment says 'the old key/IV/secret are abandoned to the bump arena'.
- tls_native_close (lib/tls_native_conn.cyr:1537-1555) seals close_notify on the stack, sets STATE_CLOSED and wipes nothing. Its header documents 'nothing is freed here'.
- No memset or wipe of any *_APP_SECRET / *_APP_KEY / *_APP_IV appears in lib/tls_native_conn.cyr.
- By contrast, _tn_wipe_ephemeral (lib/tls_native_hs13.cyr:2095-2100) runs _tn_wipe_priv and memsets TLS_CTX_OFF_SHARED, and tls_native_accept calls it after the handshake.

The classification as hardening is correct: dead copies of traffic keys persist in the process heap, and nothing shows them reaching an attacker.

**Fix (planned).** memset the previous secret/key/IV buffers in _tn_rotate_app_keys before replacing the pointers (or rotate in place), and zeroize the app-traffic secrets/keys/IVs in tls_native_close, matching the ephemeral-secret wipe discipline already used for ECDHE and Ed25519 key material.

**Status:** FIXED in 6.7.18 — `3b043ec6b`, `3ad239fe6`, `6b6d7ef05` (tls): rotation in place, `tls_native_close` zeroises every secret the ctx holds, the handshake's working copies are `secret var`s; row `tests/tcyr/crypto/tls_native_close_wipe.tcyr`.
