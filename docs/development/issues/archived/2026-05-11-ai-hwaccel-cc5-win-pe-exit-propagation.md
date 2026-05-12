# Cyrius: cc5_win 5.11.5 PE emit — exit code crashes with `0x40001000`, stdout never reaches WriteFile

**Filed:** 2026-05-11
**Reporter:** ai-hwaccel (v2.2.2)
**Cyrius version at time of report:** 5.11.8 install bundle (cc5_win binary reports 5.11.5)
**Affected stage:** PE backend, `cc5_win`
**Severity:** **High** — the Win64 PE backend can load a binary but
the binary can't propagate exit codes or write to stdout. Every
downstream consumer attempting Win64 ship targets is blocked at
cross-host smoke validation. Functionally the PE target is broken
end-to-end despite the loader-side surface looking healthy.
**Status:** open. **Expected target:** **5.11.x — this minor.**
Per ai-hwaccel maintainer guidance: 5.11.x is the optimization +
bug-fix window, may be the last minor for a while where such a
fix has a natural home; landing here matters.

## Summary

A minimal `syscall(60, 42);` source built with `cc5_win` produces a
PE binary that **loads and starts** on Windows but **crashes before
reaching `ExitProcess(42)`**. Windows reports exit code
`0x40001000` (1,073,745,920) instead of `42`. The same source
built with `cc5` (Linux ELF) runs fine and exits with code 42.

The companion hello-world (`syscall(1, 1, "hello\n", 6);
syscall(60, 42);`) has the same crash status; the `hello\n` text
never reaches stdout — `WriteFile` is reached too late or not at
all.

## Reproduction (Linux x86_64 → Win64 PE → ssh cass)

```sh
# Source: minimal exit42
$ cat > /tmp/exit42.cyr <<'EOF'
syscall(60, 42);
EOF

# Build (any of these — output is byte-identical)
$ cc5_win /tmp/exit42.cyr > /tmp/exit42.exe                        # install bundle, v5.11.5
$ /home/macro/Repos/cyrius/build/cc5_win_cross /tmp/exit42.cyr \
    > /tmp/exit42_v2.exe                                            # source build, v5.10.37
$ cmp /tmp/exit42.exe /tmp/exit42_v2.exe && echo "byte-identical"
byte-identical

$ file /tmp/exit42.exe
/tmp/exit42.exe: PE32+ executable (console) x86-64, for MS Windows
$ wc -c /tmp/exit42.exe
1536 /tmp/exit42.exe

# Deploy to cass (Win11 Pro 26200, OpenSSH server, PowerShell shell)
$ scp /tmp/exit42.exe cass:exit42.exe

# Run with delayed-expansion wrapper (5.11.6's fix path)
$ ssh cass 'cmd /v /c ".\exit42.exe & echo exit=!errorlevel!"'
exit=1073745920          # ← 0x40001000, NOT 42

# Same with .bat indirection (canonical cyrius test wrapper)
$ cat > /tmp/exit42.bat <<'EOF'
@echo off
exit42.exe
echo exit=%ERRORLEVEL%
EOF
$ scp /tmp/exit42.bat cass:exit42.bat
$ ssh cass 'cmd /c exit42.bat'
exit=1073745920          # same

# Sanity: known-good `cmd /c "exit 42"` does propagate cleanly
$ ssh cass 'cmd /c "exit 42"; "ps_exit=$LASTEXITCODE"'
ps_exit=42               # PowerShell propagation works
```

The `0x40001000` status is consistent across:

| Build path                               | cc5_win version | Wrapper             | Exit code   |
|------------------------------------------|-----------------|---------------------|-------------|
| `cc5_win` (`~/.cyrius/bin/cc5_win`)      | 5.11.5          | `cmd /v /c "…!…!"`  | 0x40001000  |
| `cc5_win_cross` (cyrius source build)    | 5.10.37         | `cmd /v /c "…!…!"`  | 0x40001000  |
| Same binary, .bat indirection            | 5.11.5          | `cmd /c bat`        | 0x40001000  |
| Hello-world with WriteFile + ExitProcess | 5.11.5          | `cmd /v /c "…!…!"`  | 0x40001000  |

WriteFile output ("hello\n") never reaches stdout in the
hello-world shape — the program crashes before the `syscall(1, 1, ...)`
reroute fires.

## What the status code means

`0x40001000` = `1073745920`. The high byte `0x40` is *informational*
in NTSTATUS terms (not an error severity), but the specific code
doesn't match any well-known `STATUS_*` constant we found. It's
*not* `STATUS_BREAKPOINT` (`0x80000003`), `DBG_CONTROL_C`
(`0x40010005`), `DBG_PRINTEXCEPTION_C` (`0x40010006`), or
`STATUS_ACCESS_VIOLATION` (`0xC0000005`).

Hypothesis: minimal PE produced by cc5_win has a malformed entry-
point or IAT setup where the loader runs the image, the user code
never executes, and Windows synthesizes some default informational
exit. The PE *header* looks structurally fine on `xxd` inspection
(MZ + PE at +0x40, machine type 0x8664, valid SizeOfHeaders, IAT
references `kernel32.dll` + `ExitProcess`).

## What this blocks

- ai-hwaccel 2.2.x's `tests/regression-pe-exit.sh`-style cross-host
  validation. The 2.2.2 release ships a `src/detect/windows.cyr`
  skeleton but defers CI cross-build until this is resolved.
- Any consumer following cyrius's documented cross-host smoke
  pattern (the `cmd /v /c "exe & echo exit=!errorlevel!"` shape
  the 5.10.49 entry calls "the correct wrapper").

## What this does NOT block

- Linux-hosted parser tests against synthesized fixtures
  (`tests/fixtures/windows/dxdiag.txt`). The DXGI parsing logic
  for ai-hwaccel 2.2.3 can ship on Linux and ride along once
  cc5_win is patched.
- Cyrius's own check.sh suite — `programs/check.cyr`'s
  `_pe_exit_gate` uses .bat indirection, and presumably builds its
  test fixtures with `cc5_win_cross` from the same source. If those
  tests are currently passing, the regression may be new in
  5.11.5+ vs whatever cc5_win the .47/.48/.49 cycle used. Worth
  bisecting against the cyrius CHANGELOG to find the first version
  that emits the broken shape.

## Bisect candidates (per cyrius CHANGELOG)

- 5.10.47 — first PE+struct-byval Phase 3 test on cass passing.
- 5.10.49 — premise-debunk slot, "cass: exit=42 ✓" claimed.
- 5.11.5 — `cc5_win` added to release tree.
- 5.11.6 — install.sh refresh: 18 bins (was 17 at v5.11.5; +1
  for cc5_win). Cross-host smoke claims "binary loads, --version
  doesn't error-out … minimal source compile attempted (CRLF quirk
  surfaced — separate item)."

The 5.11.6 entry's "CRLF quirk … separate item" phrasing suggests
the issue here may BE that separate item, never opened as a
trackable ticket. This file fills that gap.

### Notes on a quick repro from any cyrius checkout

```sh
echo 'syscall(60, 42);' > /tmp/exit42.cyr
cc5_win /tmp/exit42.cyr > /tmp/exit42.exe        # 1536 bytes
file /tmp/exit42.exe                              # PE32+ x86-64
scp /tmp/exit42.exe cass:exit42.exe
ssh cass 'cmd /v /c ".\exit42.exe & echo exit=!errorlevel!"'
# expected: exit=42
# actual:   exit=1073745920
```

Two-tick test in any cyrius dev environment with `cass` in
`~/.ssh/config`.

## Workaround (consumer-side, until patched)

For ai-hwaccel 2.2.x: skip the CI cross-build step, ship the
source-side skeleton + Linux-hosted fixture tests only. End-to-end
Win64 validation gates on a cc5_win patch.

For any consumer that needs PE validation NOW: stdout-content match
won't work either (WriteFile output doesn't escape). The only
demonstrably-working path is `cmd /c "exit N"` (no PE involved).

## Memory pin

ai-hwaccel side: `memory/feedback_cc5_win_exit_propagation.md`
records the consumer-side handling rule (Linux fixture tests
proceed; Win64 cross-build gates on upstream fix).
