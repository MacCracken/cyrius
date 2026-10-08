#!/bin/sh
# macho_clock_buffer_contract.sh — v6.5.43
#
# syscall(228) is rerouted on three targets, and they DISAGREE about the third argument:
#   arm64-macOS  EMACHO_CLOCK_ARM   → __got[6] _clock_gettime_nsec_np(id); arg 3 IGNORED
#   x86_64-macOS EMACHO_CLOCK_X86   → gettimeofday composition; arg 3 is DEREFERENCED
#                                     (`pop rdi` … `mov rax,[rdi]` … `mov ecx,[rdi+8]`)
#   Windows PE   EGETTICKS_PE       → GetTickCount64(); arg 3 IGNORED
#
# ⛔ WHY THIS IS A GATE AND NOT A COMMENT. ONE `#ifdef CYRIUS_TARGET_MACOS` covers BOTH Mach-O
# backends, so a call written against the arm64 contract compiles unchanged for x86-macOS and
# dereferences whatever was passed. `_prof_clock_ns()` in src/backend/common/runtime.cyr did
# exactly that — `return syscall(228, 4, 0);` — a NULL dereference on Intel-Mac that was fine
# on ecb. It was latent only because CYRIUS_PROF is wired in src/main.cyr alone and the macOS
# forks never call it; wiring profiling into a macOS fork, or calling _prof_clock_ns from
# anywhere else, would have turned it into a SIGSEGV with no warning of any kind.
# Demonstrated on real ach at v6.5.43: `syscall(228, 4, 0)` exits 139, `syscall(228, 4, &ts)`
# returns a live nanosecond count.
#
# PROPERTY: no syscall(228, _, 0) may be reachable on a macOS build. A literal 0 third
# argument is allowed ONLY inside a CYRIUS_TARGET_WIN guard, where the route ignores it.
#
# SECOND PROPERTY (6.6.10, the Intel-Mac clock stale-register bug): EMACHO_CLOCK_X86 zeroes rdx before its gettimeofday. Darwin's
# gettimeofday takes a THIRD argument, `uint64_t *mach_absolute_time`, an OUT-pointer xnu writes
# 8 bytes through; the emitter never wrote rdx, so every Intel-Mac clock read stored mach time at
# whatever address the previous call left in rdx (measured on ach, in an rwx image). The runtime
# half is tests/tcyr/crossos/darwin_clock_no_stray_write.tcyr, which only ach can run; this
# source check fails on the Linux build host the moment the `xor edx, edx` is dropped.
# MUTATION: delete `EB(S, 0x31); EB(S, 0xD2);` from EMACHO_CLOCK_X86 → FAIL (measured).
# 6.6.12 (Q4): the property is now "rdx points at the emitter's OWN 8-byte stack slot", not
# "rdx is NULL" — the monotonic clock ids read the mach time xnu copies out through it, and a
# slot the emitter just pushed is exactly as safe as NULL. The slot is pushed as 0 (`push 0`,
# so a failed copyout reads 0), then `mov rdx, rsp`, both before the syscall.
# MUTATION: delete `EB(S, 0x48); EB(S, 0x89); EB(S, 0xE2);` → FAIL (measured).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL macho_clock_buffer_contract: $1" >&2; exit 1; }

# Confirm the premise still holds before enforcing it — if EMACHO_CLOCK_X86 ever stops
# dereferencing arg 3, this gate should be revisited rather than silently kept.
grep -A20 'fn EMACHO_CLOCK_X86' "$ROOT/src/backend/x86/emit.cyr" | grep -q '0x8B); EB(S, 0x07)' \
  || fail "EMACHO_CLOCK_X86 no longer looks like it dereferences arg 3 (mov rax,[rdi]) — re-derive this gate's premise instead of trusting it"

# The body of EMACHO_CLOCK_X86 alone (up to its closing brace) — NOT a fixed -A window, which
# would also see EMACHO_NANOSLEEP_X86's own `xor edx, edx` (for its div) if the fns ever moved
# closer together.
CLOCK_BODY=$(awk '/^fn EMACHO_CLOCK_X86\(S\)/{s=1} s{print} s&&/^\}/{exit}' "$ROOT/src/backend/x86/emit.cyr")
[ -n "$CLOCK_BODY" ] || fail "fn EMACHO_CLOCK_X86 not found in src/backend/x86/emit.cyr"
echo "$CLOCK_BODY" | grep -q 'EB(S, 0x48); EB(S, 0x89); EB(S, 0xE2);' \
  || fail "EMACHO_CLOCK_X86 no longer points rdx at its own stack slot (mov rdx, rsp) before gettimeofday — xnu writes mach_absolute_time through the third argument register, so a stale rdx is an 8-byte write to an arbitrary address (the Intel-Mac clock stale-register bug)"
# ...the slot is pushed (as 0) first, and both precede the syscall, not follow it.
echo "$CLOCK_BODY" | awk '/EB\(S, 0x6A\); EB\(S, 0x00\);/{if(!p)p=NR} /EB\(S, 0x48\); EB\(S, 0x89\); EB\(S, 0xE2\);/{if(!x)x=NR} /EB\(S, 0x0F\); EB\(S, 0x05\);/{if(!sc)sc=NR} END{exit !(p && x && sc && p < x && x < sc)}' \
  || fail "EMACHO_CLOCK_X86's push 0 / mov rdx, rsp are not both before its syscall"

BAD=$(find "$ROOT/src" "$ROOT/lib" -name '*.cyr' -print0 2>/dev/null | xargs -0 awk '
  /^[[:space:]]*#ifdef CYRIUS_TARGET_WIN/ { win = 1 }
  /^[[:space:]]*#endif/                   { if (win) win = 0 }
  # a literal 0 as the THIRD argument of syscall(228, ...)
  /syscall\(228,[^,]*,[[:space:]]*0[[:space:]]*\)/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line !~ /^#/ && win == 0) printf "%s:%d: %s\n", FILENAME, FNR, line
  }
')
if [ -n "$BAD" ]; then
  echo "$BAD" | sed 's/^/  /' >&2
  fail "syscall(228, _, 0) outside a CYRIUS_TARGET_WIN guard — NULL is dereferenced by EMACHO_CLOCK_X86 on Intel-Mac. Pass a real 16-byte buffer; both other routes ignore it."
fi
echo "PASS macho_clock_buffer_contract: every reachable syscall(228) passes a real buffer, and the x86 reroute passes its own stack slot for mach time"
