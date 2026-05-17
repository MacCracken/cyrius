# Iron-boot session papercuts — wrapper/lib version drift + LSP cross-file scope noise

**Filed:** 2026-05-16 (during AGNOS iron-boot Attempts 37-38 + Repair (R10) staging session on `archaemenid` Beelink SER AMD)
**Severity:** Low across the board — ergonomic papercuts, none blocked the iron-boot work; kernel + `read-boot-log` both built `OK` with valid multiboot2 ELF64.
**Affects:** `cyrius` wrapper at 5.11.25; lib snapshot 5.11.54 in install tree; LSP diagnostics layer.
**Consumer:** `agnos` (kernel) + `agnosticos` (boot pipeline scripts, including `read-boot-log`), both pinned to 5.11.55 in their `cyrius.cyml`.

## Summary

Four small surface-quality issues surfaced during a single iron-boot-debug session. None blocked the work — the agnos kernel rebuilt cleanly (342,584 → 343,320 B, multiboot2 OK, entry `0x1000a8` unchanged) and `read-boot-log` rebuilt cleanly (43,600 → 48,888 B, working binary). But each one cost a small amount of session friction or trained a "noise to ignore" reflex. Bundling them as one file since they're all the same magnitude.

## Item 1 — Wrapper / manifest pin version drift

### Symptom

```sh
$ cyrius --version
cyrius 5.11.25

$ grep -E "^cyrius\s*=" /home/macro/Repos/agnos/cyrius.cyml /home/macro/Repos/agnosticos/scripts/cyrius.cyml
agnos/cyrius.cyml:cyrius = "5.11.55"
agnosticos/scripts/cyrius.cyml:cyrius = "5.11.55"

$ cd /home/macro/Repos/agnosticos/scripts && cyrius build src/read-boot-log.cyr build/read-boot-log
compile src/read-boot-log.cyr -> build/read-boot-log [x86_64] note: cwd ./lib/ shadows version-pinned /home/macro/.cyrius/versions/5.11.54/lib/ ...
```

The wrapper at `~/.cyrius/bin/cyrius` reports **5.11.25**. The project's `cyrius.cyml` pins **5.11.55**. The build resolved against the **5.11.54** lib snapshot (per the shadow-lib note). Three different versions in play; no diagnostic surfaces the mismatch.

### Why it's a papercut, not blocking

The artifacts built clean (multiboot2 ELF64 OK, entry unchanged), so 5.11.54-vs-5.11.55 is a one-patch lag that didn't break anything in this case. But:

1. If a v5.11.26→.55 patch had touched the x86 emitter / ELF surface, the iron burn could surface a regression that disappears after a toolchain refresh — and the consumer wouldn't know to refresh because no diagnostic fired.
2. The wrapper version (5.11.25) vs install snapshot (5.11.54) gap is even larger and equally silent.

### Proposed surface

`cyrius build` in a project with a `cyrius.cyml` `cyrius = "X.Y.Z"` pin should, when the resolved lib version != pin:

- **Warn loudly** (one-liner, not buried in a `note:`): `warning: cyrius.cyml pins 5.11.55 but build resolved against lib snapshot 5.11.54 — run 'cyrius update' or 'curl ... | sh' to refresh`
- **Optionally error** under a `cyrius build --strict-pin` flag (or `[build] strict_pin = true` in cyrius.cyml), for CI.

Similarly, `cyrius --version` could include a "manifest-pin: 5.11.55 (project at $PWD)" line when run inside a project tree.

### Consumer workaround

Manual `cyrius --version` check at session start + `~/.cyrius/versions/` ls to confirm the pinned version is actually installed. Folded into agnosticos `feedback_read_state_at_session_start.md` as a session-start ritual, but a wrapper-side warn would let consumers stop doing this manually.

---

## Item 2 — LSP per-file scope checks miss cross-file globals (noisy diagnostics)

### Symptom

Every `Edit` made to AGNOS source during this session surfaced LSP diagnostics for cross-file references that actually resolve correctly at build time. Sample diagnostics from this session, none of which corresponded to real bugs:

```
xhci_port.cyr:
  ✘ [Line 71:1] undefined variable 'xhci_max_ports' (missing include or enum?) (cyrius)

xhci.cyr:
  ✘ [Line 75:1] undefined variable 'XHCI_PCI_CLASS' (missing include or enum?) (cyrius)

read-boot-log.cyr:
  ✘ [Line 1:1] undefined function 'strlen' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'fmt_byte' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'print_num' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'println' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'args_init' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'argc' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'argv' (will crash at runtime) (cyrius)
  ✘ [Line 1:1] undefined function 'streq' (will crash at runtime) (cyrius)
```

All of these resolve at build time:
- `xhci_max_ports` is defined in `xhci.cyr:42` and consumed across the `usb/` directory
- `XHCI_PCI_CLASS` is defined in `xhci_regs.cyr` and consumed in `xhci.cyr`
- `strlen` / `fmt_byte` / `print_num` / `println` / `args_init` / `argc` / `argv` / `streq` are stdlib functions resolved via `cyrius.cyml` `[deps.*]` declarations

The fixed `[Line 1:1]` location on the stdlib diagnostics is the tell — the LSP isn't tracking which function call surfaced the warning, just stamping line 1.

### Why it's a papercut, not blocking

The build is the truth channel — kernel + read-boot-log both compiled and linked successfully. But the noise has a real cost:

1. **Trains a "diagnostics are noise" reflex.** When *every* edit produces a wall of `✘`s for valid code, the signal-to-noise ratio drops to zero. A real `undefined variable` ends up looking identical to the false positives. The Cyrius wrapper's `Line 1:1 ... will crash at runtime` wording is especially load-bearing — it makes "this is a real bug" indistinguishable from "the LSP doesn't see your includes."
2. **Discourages incremental edits.** Every edit produces ~10 spurious diagnostics; the consumer learns to batch edits before checking the warning panel, which is the opposite of the LSP's purpose.

### Proposed surface

Two paths, ranked by likely effort × impact:

- **Quick win — diagnostic-wording fix:** for stdlib functions resolved via `[deps.*]`, downgrade `✘ error: undefined function 'X' (will crash at runtime)` to `⚠ warning: 'X' resolved at build time via [deps.X]` or just suppress entirely when the function name matches a known stdlib export. The current wording promises a runtime crash that doesn't actually happen.
- **Real fix — follow includes in LSP scope:** the `cyrius build` resolver already knows how to follow `#include` directives and `[deps.*]` declarations. The LSP could share that resolution layer. Probably non-trivial because the LSP runs per-file without project context — but a single-shot project-scan-on-LSP-init that produces a "known symbols" map could close most of the noise without going full incremental.

### Consumer workaround

"Ignore LSP, trust the build." Already established as the working pattern in agnos/agnosticos sessions, but it negates most of the value of having an LSP in the first place.

---

## Item 3 — `vec_get` "will crash at runtime" false positive on `read-boot-log` build

### Symptom

```sh
$ cyrius build src/read-boot-log.cyr build/read-boot-log
compile src/read-boot-log.cyr -> build/read-boot-log [x86_64] note: cwd ./lib/ shadows ...
warning: undefined function 'vec_get'
error: undefined function 'vec_get' (will crash at runtime)
note: 56 unreachable fns (7212 bytes ...)
OK
```

The build emits `error: undefined function 'vec_get' (will crash at runtime)` immediately followed by `OK` and produces a working binary. `read-boot-log` has been used across many iron-boot burns (Attempts 23 → 38, ~15 burns) without a runtime crash. The diagnostic is acknowledged in `agnosticos/docs/development/state.md` as "pre-existing vec_get runtime warning unchanged — cyrius-side surface."

### Why it's a papercut, not blocking

The binary runs fine. But:

1. An `error:` line that the build treats as non-fatal (continues to emit `OK`) trains the consumer to ignore future `error:` lines.
2. If `vec_get` ever IS a real undefined-at-runtime path on a different codepath, the existing noise hides it.

### Proposed surface

Either:

- **Make it correct:** if `vec_get` is reachable from `read-boot-log` at runtime and *does* resolve to a working impl (which the binary's track record suggests), the diagnostic is wrong — fix the resolver to find it.
- **Make it fatal:** if `vec_get` is genuinely undefined and only happens to work because it's DCE'd out of reachable codepaths, `error:` should fail the build, and the DCE pass should run *before* the undefined-fn check.

Either resolution closes the "`error:` + `OK`" contradiction.

### Consumer workaround

Treat the line as decorative; trust the binary's iron-boot track record. (state.md already notes it as pre-existing noise.)

---

## Item 4 — Shadow-lib warning is informational but always fires

### Symptom

Every build of `read-boot-log` from `agnosticos/scripts/` emits:

```
note: cwd ./lib/ shadows version-pinned /home/macro/.cyrius/versions/5.11.54/lib/ — delete ./lib/ to use the version-matched snapshot, or set CYRIUS_NO_WARN_SHADOW_LIB=1 to silence this note
```

The note is correct — there's a local `lib/` under `agnosticos/scripts/` from an older era of the project layout. But it fires on every build, even when the local `lib/` is empty or matches the snapshot.

### Why it's a papercut, not blocking

Build noise; consumer-side fixable. But:

1. The two suggested remediations are asymmetric: "delete ./lib/" is destructive (might break the project if anything still depends on it), "set CYRIUS_NO_WARN_SHADOW_LIB=1" silences the warning without fixing the underlying drift.
2. There's no "is the local lib *actually different from* the snapshot?" check — if the local lib is identical, the shadow is harmless.

### Proposed surface

Compare local `./lib/` content hash against snapshot content hash. Only warn when they differ. Add a third remediation: `cyrius lib sync` (or similar) that overwrites the local copy with the snapshot when the consumer wants pin-faithful behavior.

### Consumer workaround

Set `CYRIUS_NO_WARN_SHADOW_LIB=1` in the agnosticos session env, or `rm -rf scripts/lib/` and rebuild. Neither lands in this session per `cyrius-hands-off`.

---

## Triage suggestion

All four are **Low** severity — closing them as a polish bundle in a v5.11.x patch (or as part of the v5.11.x → v6.x boundary cleanup per `project_cyrius_5x_6x_boundary`) seems appropriate. None block consumer work today.

If only one ships: **Item 1 (wrapper/manifest pin drift warning)** has the highest leverage. The other three are LSP / diagnostic-wording polish that consumers route around. Item 1 has a real risk profile — a silent version skew that hides emitter regressions until iron-burn time, which on the AGNOS bring-up costs hours per surfaced regression (re-cabling + reboot cycles per `feedback_dont_re_request_completed_experiments`).

## Related

- `agnosticos/docs/development/state.md` — toolchain-pin drift surfaced under Attempt 39 prep build-deltas block
- `agnosticos/docs/development/iron-nuc-zen-log.md` § *Attempt 39 prep* — build-under-test table notes the wrapper/manifest mismatch
- `agnosticos` memory file `feedback_read_state_at_session_start.md` — session-start ritual where this drift typically surfaces
- `agnosticos` memory file `feedback_cyrius_hands_off.md` — why these items are filed here rather than fixed in-session
