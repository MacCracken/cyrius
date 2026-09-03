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
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL macho_clock_buffer_contract: $1" >&2; exit 1; }

# Confirm the premise still holds before enforcing it — if EMACHO_CLOCK_X86 ever stops
# dereferencing arg 3, this gate should be revisited rather than silently kept.
grep -A20 'fn EMACHO_CLOCK_X86' "$ROOT/src/backend/x86/emit.cyr" | grep -q '0x8B); EB(S, 0x07)' \
  || fail "EMACHO_CLOCK_X86 no longer looks like it dereferences arg 3 (mov rax,[rdi]) — re-derive this gate's premise instead of trusting it"

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
echo "PASS macho_clock_buffer_contract: every reachable syscall(228) passes a real buffer"
