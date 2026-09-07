# Roadmap drift + stale governance docs — RM-01…05 — RESOLVED

> **RESOLVED** (archived at the v6.2.41 slot close; housekeeping). All five RM
> items were addressed by the 2026-06-19 internal doc-state sweep (see the
> UPDATE note below): phantom-TLS-arc deleted, threat-model.md corrected
> (v6.2.30), AGNOS-goal tracking home set, rv64-hardware note, cc3-drop
> contradiction fixed. No outstanding doc-drift items.

> **UPDATE 2026-06-19 (v6.2.25 internal doc-state sweep):** the recurring
> internal half is freshly addressed — **state.md trimmed 1,015 → ~185 lines**
> (handoff log + v6.1.x list → pointers; open carry-ins lifted), **roadmap.md**
> realized-shape + shipped v6.2.6–.25 summary row (it had read as if nothing past
> .5 shipped), **roadmap_6.md** stamp/mislabel/f64-band fixes, **doc-health.md**
> anchors → .25. **Still owed (the only open remainder):** the **user-facing**
> README / guides / vidya version+size+count stamps lag at the v6.2.22 full
> doc-staleness sweep — a .23–.25 user-facing refresh is the next (separate)
> doc-health pass. Keep open until that lands.

> **STATUS (2026-06-10): MOSTLY RESOLVED — roadmap rewrite landed.** The
> roadmap audit + rewrite addressed RM-01 (deleted the phantom v6.2.x TLS arc,
> re-homed the kernel-freestanding-TLS deliverable into bare-metal), RM-03
> (AGNOS-kernel goal now has a tracking home = bare-metal deliverable 7), RM-04
> (rv64 hardware is in hand per user 2026-06-10 — dissolved, real-hardware gate
> from the start), and RM-05 (cc3 contradiction fixed in roadmap_6.md +
> roadmap-future.md; state.md "Next/Open" sections refreshed). **RM-02 RESOLVED
> (v6.2.30):** `threat-model.md` corrected — native TLS is the default backend
> (since v6.1.21), PIE/ASLR ships (since v6.1.6), input buffer is 1 MB, the
> Known-Limitations "No ASLR" row replaced, the libssl trust-boundary row flipped
> to opt-in, and the CVE-20 binary-trust-root nuance added; last-reviewed →
> v6.2.30. The README user-facing version/size/count stamp lag was also refreshed
> this slot (→ v6.2.29 / 1,071,936 B / 99 modules / 190 tcyr / 92 gates). **All
> RM items now resolved — archive this issue.** (Remaining user-facing lag =
> guides + vidya stamps, tracked in doc-health.md, not an RM item.)

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../../audit/2026-06-10-deep-dive-review.md))
**Severity:** Medium (doc-correctness, but high-leverage — it distorts v6.2.x
planning before the minor opens)
**Affects:** `docs/development/roadmap_6.md`, `threat-model.md`, `state.md`,
roadmap-future.md, CLAUDE.md 6.1.31

## RM-01 — v6.2.x still plans the already-shipped native-TLS arc (P1)

`roadmap_6.md:199-251` plans a future "sovereign, pure-Cyrius TLS stack to
replace the current `lib/tls.cyr`, which is a libssl wrapper (client-only)". But
the **same file's** v6.0.x summary (`:66-72`) records full TLS 1.2 + 1.3,
client + server, shipped; and `roadmap.md:82` records the native-default flip at
v6.1.21. The slot table (`:253-264`) still counts "~12–15" TLS slots inside
"~37–40 planned / ~47–50 budget, largest minor of the cycle", and `:271-278`
ranks "native TLS > RISC-V" and names RISC-V the split-out candidate — all based
on a workload that no longer exists.

What actually survives: in-kernel **freestanding** TLS link (`:247`) is NOT
shipped (gated on the v6.2.0 bare-metal target) — ~1–2 slots, not 12–15. So real
v6.2.x ≈ 25 slots, which changes whether RISC-V even needs splitting.

**Fix:** before v6.2.x cycle-open, delete the TLS arc from v6.2.x, re-decide the
RISC-V split against the corrected budget, and consider pulling the
platform-conditional half of v6.3.x optional-deps (`:352-359` names bare-metal
/kernel objects as the immediate beneficiary) into the freed space. **Project
leader's call** — surfacing at the v6.1.x closeout doc-sync.

## RM-02 — threat-model.md is wrong on security facts (P2)

`threat-model.md` says libssl is the default backend and native is opt-in
`-D CYRIUS_TLS_NATIVE` (`:23,:65-68`) — **inverted at v6.1.21** (native is the
no-flag default; libssl is opt-out `-D CYRIUS_TLS_LIBSSL`). It lists "No ASLR" as
a Known Limitation (`:43`) despite PIE shipping v6.1.6/.8; says "input buffer
capped at 131 KB" (`:33`) vs the actual 1 MB; references `cybs vet/deny`
(`:49-57`) vs the cyaudit routing fixed at v6.1.25. It also omits no-revocation /
no-EKU / no-pathLen / no-post-handshake from Known Limitations (see
[tls-chain-verification-gaps](2026-06-10-tls-chain-verification-gaps.md)).

**Fix:** rewrite threat-model.md to current reality (native-as-default, PIE,
1 MB input) and add the TLS Known Limitations.

## RM-03 — the AGNOS-kernel flagship goal has no tracking home (P2)

"Cyrius writes the AGNOS kernel" is the headline goal, but: in-kernel TLS
acceptance ("kernel links tls_native freestanding") exists *only* inside the
stale v6.2.x TLS section slated for deletion (`roadmap_6.md:245-249`); bare-metal
v6.2.0 explicitly "does NOT gate AGNOS MVP" (`:166-170`); kernel-PIE is
consumer-gated indefinitely on an AGNOS `--pie` harness that doesn't exist
(`roadmap.md:279-285`). Nothing in the active tier advances the flagship.

**Fix:** when deleting the stale TLS arc, **re-home** the freestanding-link
acceptance as a named v6.2.0 bare-metal deliverable (kernel object links
tls_native + passes the forbidden-module check). The AGNOS `--pie` boot-harness
ask (the other half of the kernel-PIE follow-on) has been **filed upstream**:
`agnos/docs/development/issues/2026-06-10-cyrius-pie-boot-harness-ask.md`.

## RM-04 — RISC-V needs rv64 hardware absent from the fleet (P2)

Acceptance gate #4 (`roadmap_6.md:194-195`) requires "self-host byte-identical on
real rv64 hardware". The scope names "QEMU + HiFive Unmatched (or equivalent)"
(`:183-185`) and budgets 2 slots (`:261`), but the fleet is pi/ecb/ach/cass only
(`state.md:207-217`) and no tier carries a procurement decision. Hardware has lead
time.

**Fix:** settle the rv64 host **before v6.2.x opens** — a purchase decision, or an
explicit documented QEMU-interim-then-hardware policy with the hardware date
pinned. Add it as a named v6.2.x prerequisite row.

## RM-05 — cross-tier contradictions + stale state.md (P2)

- **cc3 contradiction:** `roadmap_6.md:526-535` + `roadmap-future.md:146-149` say
  "build/cc3 drops at v7.0.0 / stays through v6.x", but CLAUDE.md states cc3 was
  **dropped at v6.1.0**. A future agent could re-add or mis-retire the prior-major
  slot.
- **state.md stale:** "Next: Phase E bayan .19/ganita .20" (`:186-188`) after both
  shipped .25/.26; lists the macho-arm at-family issue as open (`:191-195`) though
  fixed v6.1.20 + archived; claims stdlib-reference ~33/90 (`:195-196`) though
  authored to ~65 modules; ecosystem.md fold-lineage pins stale (sandhi 1.4.2 /
  sigil 3.7.4 vs actual 1.4.10 / 3.7.8); doc-health.md self-contradicts on the
  stdlib-reference row and the fdlopen-trust proposal (shipped v6.1.29).

**Fix:** reconcile the cc3 statement to "dropped v6.1.0" across all tiers; refresh
state.md / ecosystem.md / doc-health.md at the v6.1.x closeout doc-sync.

## Status

Filed 2026-06-10. RM-01 is the item the project leader flagged ("there are
multiple roadmaps"). Re-scoping is the leader's call exclusively — this issue
catalogs the drift; it does not redirect.
