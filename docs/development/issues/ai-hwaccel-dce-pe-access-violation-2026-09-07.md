# `CYRIUS_DCE=1` + `--win` emits a PE that dies at startup with `0xC0000005` — OPEN

**Status:** 🟡 **OPEN** — reported from a consumer release; not yet triaged upstream.
**Placement:** unpinned — 6.6.x line. Suggest treating as a 6.6.1 blocker: it is a
shipped-artifact crash on a supported target.
**Discovered:** 2026-09-07 during the ai-hwaccel `6.5.36 → 6.6.0` toolchain bump
(ai-hwaccel 2.3.21), when the `windows-smoke` CI gate began failing with exit 139.
**Severity:** High
**Affects:** cycc **6.5.72 → 6.6.0** (bisected). Last known good: **6.5.71**.
PE / `--win` target only.

> Severity note: by the letter of the rubric this is Medium — a workaround exists
> (drop the flag on `--win`). Filed High because the failure mode is a *shipped*
> artifact — a Python wheel whose bundled `.exe` crashes on launch for end users —
> and a consumer whose CI does not actually execute the PE will not notice.
> Re-triage down if you disagree.

## Summary

Building the PE target with `CYRIUS_DCE=1` produces an executable that raises
`STATUS_ACCESS_VIOLATION` (`0xC0000005`) before emitting any output. The same
source and toolchain without the flag runs correctly. It is PE-specific: x86_64
ELF, ELF-aarch64 and Mach-O arm64 all run correctly with the flag.

The tell is that **the flag does not change the output size on PE**. `cycc`
reports "N bytes of dead code eliminated" and the file is byte-for-byte the same
length as the non-DCE build — so something is being removed from or rewritten in
the image without the layout shrinking, and the entry path pays for it.

## Reproduction

Repro source: [`repros/2026-09-07-dce-pe-access-violation.cyr`](./repros/2026-09-07-dce-pe-access-violation.cyr)

```cyrius
fn main() {
    syscall(1, 1, "ok\n", 3);   # write(stdout) — PE-rerouted to WriteFile
    return 0;
}
```

Must be built **inside a project whose manifest declares `[deps] stdlib`** — a
bare file with no manifest links nothing, yields a ~2.5 KB PE, and does **not**
reproduce. The defect needs the (unreachable) stdlib set present. The manifest
used is inlined in the repro's header comment.

```
cyrius lib sync
cyrius build --win src/main.cyr ok.exe                 # 143,872 B
CYRIUS_DCE=1 cyrius build --win src/main.cyr bad.exe   # 143,872 B  + "…bytes of dead code eliminated"
```

Run on Windows 11 (10.0.26200, x86_64):

```
.\ok.exe    -> exit 0            stdout: "ok"
.\bad.exe   -> exit -1073741819  (0xC0000005)   stdout: <empty>
```

Under Git Bash — which is what GitHub Actions gives a `windows-latest` job with
`defaults.run.shell: bash` — the same crash surfaces as **exit code 139**.

### Version bisect (same source, same host, same manifest)

| cycc | reports "eliminated" | `--win` + `CYRIUS_DCE=1` | `--win` no DCE |
|---|---|---|---|
| 6.5.36 | no  | exit 0 | exit 0 |
| 6.5.71 | no  | exit 0 | exit 0 |
| **6.5.72** | **yes** | **0xC0000005** | exit 0 |
| 6.6.0  | yes | **0xC0000005** | exit 0 |

### Target matrix (cycc 6.6.0, `CYRIUS_DCE=1`, same source)

| target | how run | result |
|---|---|---|
| x86_64 ELF | native Linux | exit 0 — and genuinely reclaims (419 360 → 214 504 B on the real consumer) |
| ELF-aarch64 | `qemu-aarch64` | exit 0, output identical to no-DCE, size unchanged |
| Mach-O arm64 | native, Apple Silicon | exit 0, output identical to no-DCE, size unchanged |
| **x86_64 PE** | native Windows 11 | **0xC0000005 at startup** |

x86_64 ELF is the only backend where the size actually drops. aarch64 and Mach-O
report elimination and do not shrink either — they simply do not crash.

## Root cause (speculation — not verified against cycc internals)

6.5.72 is the release that turned `CYRIUS_DCE=1` from NOP-padding into real
elimination, and it is exactly the first bad version, so the PE emitter's handling
of the new elimination path is the obvious place to look. Given the size is
unchanged, the suspicion is that entries are being removed or zeroed without the
PE section headers / relocations / import thunks being updated to match — i.e.
something the loader or the entry stub still reaches is now gone, while
`SizeOfImage` and the section table still describe the old layout. Purely
inferential; I have not read the emitter.

## Proposed fix

None offered — I do not know the PE backend well enough. Bisecting 6.5.71 → 6.5.72
against the PE emitter, with the "reports eliminated but file size unchanged"
discrepancy as the signal, is the concrete starting point.

## Consumer-side workaround

ai-hwaccel 2.3.21 drops `CYRIUS_DCE=1` from the PE cross-build only
(`bindings/python/scripts/stage_win_cross.sh`); it is retained everywhere else,
where it is correct and, on x86_64 ELF, worth −48.8%. The workaround costs nothing
on PE — that binary is 497,152 bytes with or without the flag.

Any consumer cross-building a PE with `CYRIUS_DCE=1` on cycc ≥ 6.5.72 should
assume their binary is broken and check it by *running* it, not by checking that
the build succeeded — the build is clean and the `MZ` magic is intact.
