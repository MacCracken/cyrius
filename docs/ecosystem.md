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

Sibling repos vendored byte-identical into `cyrius/lib/` at a
patched tag. Removed from `[deps]` once folded. As of the mabda
3.0.1 fold (v6.0.45) there are no remaining explicit `[deps.*]`
git entries (see Live deps below).

| Lib | Folded at | Source tag | Domain |
|-----|-----------|------------|--------|
| `lib/sandhi.cyr` | v5.7.0 (refold v6.5.6) | sandhi 1.9.9 | HTTP/2 + JSON-RPC + service discovery + TLS policy (ALPN/SPKI on typed native verbs) |
| `lib/vani.cyr` | v5.8.0 (refold v6.5.6) | vani 1.1.3 | Audio (ALSA PCM + ring buffer + mixer) |
| `lib/sakshi.cyr` | v5.8.65 (refold v6.5.16) | sakshi 2.4.10 | Tracing (`_sk_fmt_int` half of the `i64::MIN` formatter class, fixed upstream @2.4.8) |
| `lib/patra.cyr` | v5.8.65 (refold v6.4.65) | patra 1.12.12 | Storage (thread-local slots allocator-managed @1.12.12) |
| `lib/sigil.cyr` | v5.8.65 (refold v6.5.14) | sigil 3.12.6 | Security (x509 + Ed25519 sign/verify — powers native TLS + cyrsign release signing; UEFI Secure Boot signing (authenticode_pe_sign) + enrollment (efi_signature_list/efi_auth); crypto-bank slot allocator-managed @3.12.1; Authenticode VERIFY + unaligned-image hash fix @3.12.2; **RSA verify authentication-bypass closed across 3.12.3-3.12.6** — v1.5 @3.12.3, bignum scratch @3.12.4/.5, the whole PSS workspace @3.12.6, which needed cyrius 6.5.14's tail-call fix to be expressible) |
| `lib/yukti.cyr` | v5.8.65 (refold v6.5.4) | yukti 2.3.2 | Hardware enumeration |
| `lib/sankoch.cyr` | v5.8.65 (refold v6.4.79) | sankoch 2.7.7 | Compression |
| `lib/niyama.cyr` | **v5.9.0** (refold v6.4.65) | niyama 1.0.6 | Regex (5 engines: bre / re2 / pcre / fuzzy / vim; 6,689 lines vendored) |
| `lib/mabda.cyr` | **v6.0.45** (refold v6.5.4) | mabda 4.0.8 | GPU/compute (AMD-native GA; array textures + cubemaps + BC arrays; samvada/chitra calls `#ifdef`-gated) |
| `lib/bayan.cyr` | **v6.1.25** (refold v6.5.8) | bayan 1.4.1 | Data formats + big-int (json / toml / cyml / csv / base64 / **yaml** / bigint `u256` / u128; per-format sublibs @1.2.0; `bayan_json_v_obj_get_by_str` + the cstring/`Str` key contract spelled out @1.4.1). **Carve** out of stdlib: public fns renamed `bayan_*` + legacy aliases. Consumers of `ws`/`sigil`/`patra`/`tls` (which call carved fns) must `include "lib/bayan.cyr"`. |
| `lib/ganita.cyr` | **v6.1.26** (refold v6.4.70) | ganita 1.0.4 | Linear algebra + advanced math (matrix / linalg / transcendental + fibonacci/binomial). **Carve** out of stdlib (closes Phase E): renamed `ganita_*` + legacy aliases. Keep stdlib `math` in scope (f64-exp/ln polyfills + F64 constants). |
| `lib/yantra.cyr` | **v6.2.26** (refold v6.5.1) | yantra 1.0.2 | UI/E2E testing (WebDriver + Appium + Chromium-CDP RPC). Requires its dep chain in order: net / ws / bayan / sandhi / tls / sakshi / sigil. |

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
