#!/bin/sh
# Cross-OS self-host gate — run cycc's REAL self-host on real hardware for
# ONE target host and exit 0 iff it self-hosts BYTE-IDENTICAL. FAIL-LOUD:
# a compile failure or a non-identical fixpoint exits 1; a host that is
# genuinely unreachable exits 3 (UNREACHABLE — distinct so the gate can say
# "couldn't verify" vs "verified broken"; BOTH block a release — "not
# available" is never an excuse, that placebo IS the rot). There is NO skip.
#
# Invoked per host by `cyrius audit` (_cross_os_selfhost, cbt/commands.cyr)
# via _co_run_sh so ssh/scp inherit the real environment (HOME +
# SSH_AUTH_SOCK). Also runnable standalone: `sh scripts/cross-os-selfhost.sh <host>`.
#
# ROBUSTNESS: `.local` (mDNS) lookups transiently fail (EAI_AGAIN) under load
# — e.g. after the long ecb operations, the later hosts' lookups failed and
# produced a FALSE "broken" verdict in the v6.0.45 bring-up. So we resolve the
# alias's HostName to an IP ONCE (with retries) and PIN every ssh/scp to that
# IP via -o HostName, so one flaky lookup mid-run cannot flip the verdict.
#
# Hosts (wired in ~/.ssh/config):
#   ecb          macOS arm64 (Apple Silicon)  — self-hosts; ad-hoc codesign REQUIRED (AMFI)
#   ach          macOS x86_64 (Intel)         — self-hosts; NO codesign (Intel runs
#                                                unsigned; `codesign -s -` rejects this
#                                                Mach-O AND mutates it with an
#                                                LC_CODE_SIGNATURE load command — which is
#                                                what produced the false v6.0.44
#                                                "x86-macOS doesn't self-host" retraction)
#   pi           Linux aarch64 (real ARM)      — NATIVE self-host (NOT the cross-compiler;
#                                                release.yml's "QEMU-only codegen diff"
#                                                excuse hid a real bug on real silicon)
#   cass         Windows x86_64 (PE32+)        — self-host via cmd.exe (the default ssh
#                                                shell is PowerShell, which lacks `<`)
#   ecb-install  macOS arm64 packaging gate    — real install.sh -> cyrius build -> exit 42
# See CHANGELOG [6.0.45].
set -e

HOST="${1:?usage: cross-os-selfhost.sh <ecb|ach|pi|cass|ecb-install> [tcyr-glob]}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

# Cross-OS LIB-TEST fallback (v6.0.75) — INTERIM mechanism, the trigger is
# opt-in so normal self-host runs stay lean. Arg 2 (or $CYRIUS_CROSS_OS_LIBTEST)
# is a glob; when set, AFTER the cycc self-host passes on this host, the
# slot's matching `tests/tcyr/<glob>*.tcyr` are compiled by the freshly-built
# NATIVE host cycc and run on real hardware — catching stdlib breakage (a
# syscall the target doesn't translate, an ABI/byte-order bug) BEFORE CI/ports.
# It bundles from THIS repo + scp's, so it does NOT depend on the host having a
# current checkout. FALLBACK, not the gate: CI still runs the full matrix; this
# is "catch before CI if possible" (user 2026-06-06). A better mechanism (per-
# platform test manifests, a PE-safe subset for cass since fork/socketpair are
# POSIX-only) is TODO. Fail-loud: a lib-test failure exits 1.
LIBTEST="${2:-${CYRIUS_CROSS_OS_LIBTEST:-}}"

# The ssh-config alias for this job (ecb-install reuses the ecb host).
ALIAS="$HOST"
case "$HOST" in ecb-install) ALIAS=ecb ;; esac

# Resolve ALIAS's HostName -> IP, retrying transient mDNS failures. Exit 3
# (UNREACHABLE) if it never resolves. Then pin all ssh/scp to that IP.
HN=$(ssh -G "$ALIAS" 2>/dev/null | awk '/^hostname /{print $2; exit}')
[ -n "$HN" ] || HN="$ALIAS"
IP=""
i=0
while [ "$i" -lt 6 ]; do
  # Prefer IPv4: mDNS returns IPv6 (incl. the UNUSABLE fe80:: link-local,
  # which fails plain ssh with "Invalid argument") in nondeterministic order
  # via `getent hosts` — that flaked the cass leg of the v6.0.47 run. Fall
  # back to `getent hosts` only if the host has no IPv4.
  IP=$(getent ahostsv4 "$HN" 2>/dev/null | awk '{print $1; exit}')
  [ -n "$IP" ] || IP=$(getent hosts "$HN" 2>/dev/null | awk '{print $1; exit}')
  [ -n "$IP" ] && break
  i=$((i + 1)); sleep 2
done
[ -n "$IP" ] || { echo "UNREACHABLE: $ALIAS ($HN did not resolve after retries)"; exit 3; }
# Connect to the pinned IP but verify the host key under the configured
# hostname (known_hosts is keyed by $HN, not the IP) — without HostKeyAlias
# the IP-pin fails BatchMode with "Host key verification failed".
# RemoteCommand=none + RequestTTY=no override any per-host `RemoteCommand`/
# `RequestTTY force` directive in ~/.ssh/config (e.g. an ecb test setup that
# cd's into a working dir + execs a login shell) — those conflict with the
# gate passing its own command and fail with "Cannot execute command-line
# and remote command" (exit 255). The gate cd's to its own _cyaud dir anyway.
SSHO="-o ConnectTimeout=20 -o BatchMode=yes -o HostName=$IP -o HostKeyAlias=$HN -o RemoteCommand=none -o RequestTTY=no"

# Linux-side seed + source bundle (shared by the self-host cases; harmless for
# ecb-install, which builds its own tarball). Built from clean source so what
# we verify is what we ship.
cat src/main.cyr | ./build/cycc > /tmp/_co_l && chmod +x /tmp/_co_l
# cx Release C (v6.4.20): a portable-.cyx fixture, built once with the LOCAL
# cx bytecode compiler (cycc_cx), shipped to every host. Each self-host leg
# rebuilds cxvm with the just-self-hosted NATIVE cycc and runs this .cyx —
# proving cxvm's per-host guest-syscall translation actually works (exit 42 IFF
# the guest write() returned its byte count, i.e. the 0x70 syscall path fired).
# A green cxvm-that-halts is the placebo CLAUDE.md warns about, so the fixture
# EXERCISES real work, not just a halt. programs/cxvm.cyr rides the bundle
# (its includes lib/string.cyr + lib/alloc.cyr are already in `lib`).
# v6.4.32: upgraded to also exercise the cx SIMD path — local-array frame
# addressing (ELOAD_LOCAL_ADDR + the EFLLOAD/EFLSTORE regalloc unification),
# f64v_add (per-lane fadd), and f64v_sqrt (the new cxvm fsqrt opcode 0x68).
# A green leg now means the cx SIMD emitters + frame fix run on that host's
# native cxvm, not just that a write halts. (Text output length 10, not 9.)
cat src/main_cx.cyr | ./build/cycc > /tmp/_co_ccx && chmod +x /tmp/_co_ccx
printf 'fn main(): i64 { var A[24]; var B[16]; var R[16]; store64(&A + 0, f64_from(10)); store64(&A + 8, f64_from(20)); store64(&B + 0, f64_from(3)); store64(&B + 8, f64_from(4)); f64v_add(&R, &A, &B, 2); if (f64_to(load64(&R + 0)) != 13) { return 1; } if (f64_to(load64(&R + 8)) != 24) { return 2; } store64(&A + 0, f64_from(9)); store64(&A + 8, f64_from(16)); f64v_sqrt(&R, &A, 2); if (f64_to(load64(&R + 0)) != 3) { return 3; } if (f64_to(load64(&R + 8)) != 4) { return 4; } var w = syscall(1, 1, "cx-simd-ok\\n", 10); if (w == 10) { return 42; } return 5; }\nvar e = main();\nsyscall(60, e);\n' > /tmp/_co_cx.cyr
cat /tmp/_co_cx.cyr | /tmp/_co_ccx > /tmp/_co_cx.cyx
# tests/win: v6.0.71 callptr→real-Win64 regression (cass leg). tests/tcyr +
# lib/assert.cyr only ride along when the lib-test fallback is triggered.
if [ -n "$LIBTEST" ]; then
  tar czf /tmp/_co.tgz src lib tests/win tests/tcyr VERSION programs/cxvm.cyr
else
  tar czf /tmp/_co.tgz src lib tests/win VERSION programs/cxvm.cyr
fi

case "$HOST" in
  ecb)
    cat src/main_aarch64.cyr       | /tmp/_co_l                   > /tmp/_co_x  && chmod +x /tmp/_co_x
    cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 /tmp/_co_x > /tmp/_co_m
    ssh $SSHO ecb 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_m /tmp/_co_cx.cyx /tmp/_co_cx.cyr ecb:~/_cyaud/
    # Self-host twice + cmp, then the v6.0.37 exit-code-propagation guard
    # (fn main(){return 42;} must exit 42 — catches the rot-class where
    # main() is never called and the program exits with argc). Then cx C:
    # build a NATIVE Mach-O cxvm with the just-self-hosted r1r and run the
    # portable .cyx I/O fixture — proves EMACHO_SYSXLAT translates the guest's
    # runtime syscall number (must exit 42; guest write() must return 9).
    ssh $SSHO ecb 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_m && codesign -s - -f _co_m \
      && cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 ./_co_m > r1 \
      && cp r1 r1r && chmod +x r1r && codesign -s - -f r1r \
      && cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 ./r1r > r2 \
      && cmp r1 r2 \
      && printf "fn main() { return 42; }" > _ec.cyr \
      && cat _ec.cyr | CYRIUS_MACHO_ARM=1 ./r1r > _ec && chmod +x _ec && codesign -s - -f _ec \
      && (_rc=0; ./_ec || _rc=$?; [ $_rc -eq 42 ]) \
      && cat programs/cxvm.cyr | CYRIUS_MACHO_ARM=1 ./r1r > cxvm && chmod +x cxvm && codesign -s - -f cxvm \
      && (_cxrc=0; ./cxvm < _co_cx.cyx > /dev/null || _cxrc=$?; [ $_cxrc -eq 42 ]) \
      && cat src/main_cx.cyr | ./r1r > cycc_cx && chmod +x cycc_cx && codesign -s - -f cycc_cx \
      && cat _co_cx.cyr | ./cycc_cx > _nat.cyx \
      && (_nrc=0; ./cxvm < _nat.cyx > /dev/null || _nrc=$?; [ $_nrc -eq 42 ])'
    # v6.4.22 cx: the NATIVE macho cycc_cx (r1r, which hardcodes CYRIUS_TARGET_MACOS)
    # compiles a .cyr → .cyx that the native cxvm runs to exit 42. Guards the
    # main_cx.cyr per-target arena (mmap on macho, not brk — the fault this fixed).
    ;;
  ach)
    # x86 ELF cycc told to emit Mach-O builds the x86 Mach-O cycc (its driver
    # hardcodes _TARGET_MACHO=1, so no env flag is needed to RUN it).
    cat src/main_x86_macho.cyr | CYRIUS_MACHO=1 /tmp/_co_l > /tmp/_co_mx
    ssh $SSHO ach 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_mx ach:~/_cyaud/
    # NO codesign (see header — unsigned x86_64 Mach-O runs on Intel 13.7.8).
    # Self-host twice + cmp, then the v6.0.37 exit-code-propagation guard
    # (fn main(){return 42;} must exit 42 — catches the rot-class where main()
    # is never called and the program exits with argc), mirroring the ecb leg.
    # Without the guard a byte-identical-but-broken cycc could self-host green.
    ssh $SSHO ach 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_mx \
      && cat src/main_x86_macho.cyr | ./_co_mx > r1 && chmod +x r1 \
      && cat src/main_x86_macho.cyr | ./r1 > r2 \
      && cmp r1 r2 \
      && printf "fn main() { return 42; }" > _ec.cyr \
      && cat _ec.cyr | ./r1 > _ec && chmod +x _ec \
      && (_rc=0; ./_ec || _rc=$?; [ $_rc -eq 42 ])'
    ;;
  pi)
    # x86 ELF -> aarch64-emitting cross-compiler -> NATIVE aarch64 cycc.
    cat src/main_aarch64.cyr | /tmp/_co_l  > /tmp/_co_x   && chmod +x /tmp/_co_x
    cat src/main_aarch64.cyr | /tmp/_co_x  > /tmp/_co_a64 && chmod +x /tmp/_co_a64
    ssh $SSHO pi 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_a64 /tmp/_co_cx.cyx /tmp/_co_cx.cyr pi:~/_cyaud/
    # Self-host twice + cmp, then cx C: build a NATIVE aarch64 cxvm with r1 and
    # run the portable .cyx I/O fixture — proves ESYSXLAT translates the guest's
    # runtime syscall number (incl. open→openat AT_FDCWD shift). Must exit 42.
    ssh $SSHO pi 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_a64 \
      && cat src/main_aarch64.cyr | ./_co_a64 > r1 && chmod +x r1 \
      && cat src/main_aarch64.cyr | ./r1 > r2 \
      && cmp r1 r2 \
      && cat programs/cxvm.cyr | ./r1 > cxvm && chmod +x cxvm \
      && (_cxrc=0; ./cxvm < _co_cx.cyx > /dev/null || _cxrc=$?; [ $_cxrc -eq 42 ]) \
      && cat src/main_cx.cyr | ./r1 > cycc_cx && chmod +x cycc_cx \
      && cat _co_cx.cyr | ./cycc_cx > _nat.cyx \
      && (_nrc=0; ./cxvm < _nat.cyx > /dev/null || _nrc=$?; [ $_nrc -eq 42 ])'
    # v6.4.22 cx: native aarch64-Linux cycc_cx (brk arena — aarch64-Linux has brk)
    # compiles a .cyr → .cyx the native cxvm runs to 42. (macho/PE were the broken
    # arenas; pi confirms the per-target #ifdef keeps the Linux path working.)
    ;;
  cass)
    # x86 ELF -> PE-emitting cross-compiler (cycc_win) -> native PE cycc.exe.
    cat src/main_win.cyr | /tmp/_co_l > /tmp/_co_w && chmod +x /tmp/_co_w
    cat src/main_win.cyr | /tmp/_co_w > /tmp/_co_exe
    printf 'fn main() { return 42; }' > /tmp/_co_ec.cyr
    # v6.4.14 — run under C:\cyrius-tests, the dir cass has a standing Windows
    # Defender exclusion for. The old %USERPROFILE%\_cyaud was NOT excluded, so
    # Defender's ML classifier (Bearfoos.A!ml) could QUARANTINE a freshly-built
    # cycc.exe mid-run → 0-byte output → a FALSE self-host FAIL on a perfectly
    # good compiler. Writing to the excluded root makes the verdict trustworthy.
    # ⛔ REAP ORPHANS FIRST — this leg must be re-runnable without a human. A test that
    # hangs on Windows is killed by the per-test `timeout`, but that only kills the LOCAL
    # ssh: the remote `_lt.exe` keeps running and holds a file lock, so the NEXT run's
    # `rmdir` fails, `mkdir` then errors "already exists", and `set -e` aborts setup before
    # a single test runs. Measured: one orphaned `_lt.exe` (PID 3336) blocked the whole leg
    # until it was killed by hand. `taskkill` is allowed to fail — usually there is nothing
    # to reap — so it is explicitly not part of the `set -e` chain.
    ssh $SSHO cass 'taskkill /F /IM _lt.exe' >/dev/null 2>&1 || true
    ssh $SSHO cass 'cmd /c "rmdir /s /q C:\cyrius-tests\_cyaud 2>nul & mkdir C:\cyrius-tests\_cyaud"'
    scp -q $SSHO /tmp/_co.tgz cass:/cyrius-tests/_cyaud/_co.tgz
    scp -q $SSHO /tmp/_co_exe cass:/cyrius-tests/_cyaud/cycc.exe
    scp -q $SSHO /tmp/_co_ec.cyr cass:/cyrius-tests/_cyaud/_ec.cyr
    scp -q $SSHO /tmp/_co_cx.cyx cass:/cyrius-tests/_cyaud/_co_cx.cyx
    scp -q $SSHO /tmp/_co_cx.cyr cass:/cyrius-tests/_cyaud/_co_cx.cyr
    # cmd.exe for `<` redirection. The &&-chain stops at the first failure and
    # cmd /c returns that command's exit code, which ssh propagates back, so a
    # broken cycc.exe (emits 0 code today) fails the gate for the right reason.
    # Then the v6.0.54 exit-code guard (the WIN analog of the ecb leg's v6.0.37
    # guard): a `fn main(){return 42;}` program compiled by the NATIVE cycc.exe
    # must exit 42. The byte-identity `fc /b` above does NOT catch the rot-class
    # where main_win.cyr's DCE stubs `fn main` / never auto-calls it (the bug
    # fixed in v6.0.54). `cmd /v` is REQUIRED — bare `%errorlevel%` expands at
    # parse time and falsely reads 0 (feedback_windows_errorlevel_test_wrapper).
    # v6.4.14 — the cass leg is the ONE host that splits its checks across
    # MULTIPLE ssh invocations joined by LOCAL `&&`. That is a set -e FALSE-PASS
    # trap: POSIX `set -e` IGNORES a failure of any command in an AND-OR list
    # OTHER THAN THE LAST. So if the FIRST ssh (the self-host `fc /b c2.exe
    # c3.exe`) FAILS, the chain short-circuits, set -e does NOT fire, and the
    # script falls straight through to `echo SELFHOST_OK` below — reporting a
    # GREEN verdict on a BROKEN Windows self-host. (ecb/ach/pi are safe: each is
    # a SINGLE ssh whose remote `&&`-chain exit ssh propagates, so a nonzero ssh
    # is a standalone command that set -e catches.) A broken cass PE self-host
    # slipped past as SELFHOST_OK exactly this way. Wrap the whole chain in an
    # explicit `if` so ANY leg's failure is a hard, visible exit 1 — never masked.
    if ssh $SSHO cass 'cmd /c "cd /d C:\cyrius-tests\_cyaud && tar xzf _co.tgz && cycc.exe < src\main_win.cyr > c2.exe && c2.exe < src\main_win.cyr > c3.exe && fc /b c2.exe c3.exe"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < _ec.cyr > _ec.exe && _ec.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < tests\win\callptr_real_win64.cyr > cpr.exe && cpr.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < tests\win\nanosleep_pe.cyr > nsp.exe && nsp.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < tests\win\var_syscall_arity_pe.cyr > vsa.exe && vsa.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < tests\win\dir_list_pe.cyr > dlp.exe && dlp.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < tests\win\async_iocp_pe.cyr > aip.exe && aip.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < programs\cxvm.cyr > cxvm.exe && cxvm.exe < _co_cx.cyx > nul & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d C:\cyrius-tests\_cyaud && c2.exe < src\main_cx.cyr > cycc_cx.exe && cycc_cx.exe < _co_cx.cyr > nat.cyx && cxvm.exe < nat.cyx > nul & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"'; then
      :   # all cass legs passed (self-host fixpoint + the 5 exit-42 guards + cx-C portable-.cyx I/O + v6.4.22 native cycc_cx compile→run round-trip)
    else
      echo "SELFHOST_FAIL: cass — Windows self-host fixpoint (fc /b c2.exe c3.exe) or an exit-code guard FAILED (rc=$?). NOT SELFHOST_OK."
      exit 1
    fi
    # v6.0.71 callptr→real-Win64-callee regression: the NATIVE cycc.exe compiles
    # a program that callptr's real kernel32 entries (lstrlenA/GetModuleHandleA/
    # MulDiv — real SSE-prologue Win64 callees) and must exit 42. Pre-fix this
    # returned a corrupted 5 / AV'd. Guards the ECALLPTR_PE force-align. (The
    # full DXGI/COM demonstrator + AddRef/Release residual is tracked separately
    # — needs windbg on cass; see 2026-06-05-windows-com-vtable issue.)
    # v6.1.17 PE nanosleep(35) routing: the NATIVE cycc.exe compiles a program
    # that calls syscall(35,&ts,0) both literally and via a var-number, and
    # measures elapsed wall time with GetTickCount64 (228) to prove the Sleep
    # actually fired (must exit 42). Guards the ENANOSLEEP_PE emitter +
    # EPE_SYSCALL_DYNAMIC argc==3 candidate (the v6.1.16 dispatch's nanosleep gap).
    # v6.1.17 var-syscall-arity regression: a var-number syscall of an
    # UNROUTABLE arity (arity-5 getdents64) must emit a stack-balanced -38, NOT
    # hard-error the build (the 6.1.16 PE-tarball blocker) — must exit 42.
    # v6.1.18 dir-listing regression: dir_list/is_dir now route to
    # FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW (lib/fs_win.cyr);
    # dir_list_pe.cyr enumerates tests\win + checks is_dir on a dir/file/missing
    # path on real Windows — must exit 42.
    # v6.4.44 IOCP async: the NATIVE cycc.exe compiles async_iocp_pe.cyr and drives
    # the Windows IOCP reactor end-to-end — async_interval + async_with_timeout +
    # async_spawn_process/run_process + async_join_all/async_select — folding to
    # exit 42. First permanent Windows async coverage (R1/R2 were ad-hoc); also
    # guards the v6.4.44 PE reroute 16-align fix (CloseHandle in the process resume
    # faulted 0xC0000005 on a misaligned stack; WINE could not reproduce it).
    # v6.4.20 cx Release C: the NATIVE cycc.exe builds a PE cxvm from
    # programs\cxvm.cyr and runs the portable .cyx I/O fixture (a guest write()).
    # Before C, cxvm issued the guest syscall with a FIXED argc-6 shape that hit
    # NO EPE_SYSCALL_DYNAMIC arity bucket → every guest write/read/open/exit
    # returned -ENOSYS (cass exit=-38, no output). The arity-correct dispatch
    # (write/read/open/lseek→argc4, close/exit→argc2) makes the PE buckets route
    # to EWRITE_PE/etc. Must exit 42 (guest write must return its 9-byte count).
    ;;
  ecb-install)
    # Packaging-rot guard (v6.0.38): build the real tarball via the same
    # script the release uses, run the REAL install.sh on ecb under a
    # sandboxed CYRIUS_HOME, then `cyrius build` fn-main-42 and assert exit 42.
    sh scripts/build-macos-arm64-tarball.sh /tmp/_co_dist >/dev/null 2>&1
    V=$(tr -d '[:space:]' < VERSION)
    printf 'fn main() { return 42; }' > /tmp/_co_t.cyr
    ssh $SSHO ecb 'rm -rf ~/_coih ~/_co_t.out ~/_cofg'
    scp -q $SSHO scripts/install.sh scripts/funcgate-posix.sh /tmp/_co_t.cyr "/tmp/_co_dist/cyrius-$V-aarch64-macos.tar.gz" ecb:~/
    ssh $SSHO ecb "CYRIUS_VERSION=$V CYRIUS_HOME=\$HOME/_coih CYRIUS_INSTALL_TARBALL=\$HOME/cyrius-$V-aarch64-macos.tar.gz sh \$HOME/install.sh >/dev/null 2>&1 && CYRIUS_HOME=\$HOME/_coih \$HOME/_coih/bin/cyrius build \$HOME/_co_t.cyr \$HOME/_co_t.out >/dev/null 2>&1 && (r=0; \$HOME/_co_t.out || r=\$?; [ \$r -eq 42 ])"
    # v6.0.63 FUNCTIONAL gate — the REAL consumer flow (init -> lib sync -> deps
    # -> build a vec-grown fib that allocates -> run/assert -> hash). Self-host +
    # the single-file build above BOTH pass while is_dir/dir_list are broken
    # (neither walks a directory) — the blind spot that let arm64-macOS lib sync
    # rot green for 10+ releases (known + papered-over since v6.0.40, deps.cyr's
    # own comment). This step FAILS RED on the broken state — that's the truth.
    # Honest known-broken bypass: FUNCGATE_ALLOW_KNOWN_BROKEN=1 downgrades a
    # tracked-broken host to exit 4 (visible RED, not blocking Linux, NEVER green).
    # Issue: 2026-06-04-shipped-broken-functionality-found-by-consumers.md.
    _frc=0
    ssh $SSHO ecb "sh \$HOME/funcgate-posix.sh \$HOME/_coih/bin/cyrius \$HOME/_cofg \$HOME/_coih" || _frc=$?
    if [ "$_frc" -ne 0 ]; then
      echo "FUNCGATE_FAIL: ecb arm64 macOS real-flow broken (rc=$_frc) — see 2026-06-04-shipped-broken-functionality-found-by-consumers.md"
      if [ "${FUNCGATE_ALLOW_KNOWN_BROKEN:-0}" = "1" ]; then
        echo "FUNCGATE_KNOWN_BROKEN: ecb (tracked) — NOT blocking, NOT claiming green"; exit 4
      fi
      exit 1
    fi
    ;;
  *)
    echo "ERROR: unknown host '$HOST' (expected ecb|ach|pi|cass|ecb-install)"; exit 2
    ;;
esac

echo "SELFHOST_OK: $HOST"

# ---- LIB-TEST fallback phase (v6.0.75; opt-in) -------------------------------
# After self-host, compile + run the slot's matching tests/tcyr/<glob>*.tcyr
# with the NATIVE host cycc just built (ecb=r1r codesigned / ach,pi=r1 /
# cass=c2.exe), on real hardware. Glob is expanded LOCALLY (avoids host-side
# globbing, esp. cmd.exe). Fail-loud. ecb-install has no native cycc → skipped.
if [ -n "$LIBTEST" ]; then
  case "$HOST" in
    ecb|ach|pi|cass) ;;
    *) echo "  lib-test: $HOST is not a lib-test host — skipped"; LIBTEST="" ;;
  esac
fi
if [ -n "$LIBTEST" ]; then
  # v6.5.11: RECURSIVE — the corpus lives in topical subfolders under tests/tcyr.
  CORPUS_TOTAL=$(find tests/tcyr -name '*.tcyr' | wc -l | tr -d ' ')
  # v6.5.8: CYRIUS_CROSS_OS_FULL=1 runs the WHOLE tcyr corpus instead of the subset.
  # Opt-in, not the default, and the reason is measured rather than assumed: a full run on
  # ecb takes 75 s (affordable only because the ssh loop is now batched — it was ~1.8 s of
  # handshake PER TEST before) and reports 235 pass / 23 fail. Those 23 are pre-existing
  # platform gaps, most of them downstream of the open macOS-threading issue, not
  # regressions from this release — so defaulting to full would wedge every release behind
  # a separate arc. Filed with the measured list; flip the default when it reaches zero.
  if [ "${CYRIUS_CROSS_OS_FULL:-0}" = "1" ]; then LIBTEST=""; fi
  # v6.5.11: LIBTEST is a SUBDIRECTORY under tests/tcyr (it was the filename prefix
  # "vr01_"). A missing directory is a hard error here; a prefix that matches nothing
  # is indistinguishable from a prefix that matched a shrinking set, which is how a
  # partial move would have reported "12 of 12 (0 NOT run)" — a self-consistent lie.
  if [ -n "$LIBTEST" ]; then
    [ -d "tests/tcyr/$LIBTEST" ] || { echo "LIBTEST_FAIL: no such directory tests/tcyr/$LIBTEST"; exit 1; }
    TESTS=$(find "tests/tcyr/$LIBTEST" -name '*.tcyr' | sort)
  else
    TESTS=$(find tests/tcyr -name '*.tcyr' | sort)
  fi
  [ -n "$TESTS" ] || { echo "LIBTEST_FAIL: no tests/tcyr matched '${LIBTEST}'"; exit 1; }
  SEL_N=$(echo "$TESTS" | wc -l | tr -d ' ')
  echo "── lib-test on $HOST (native cycc, real hardware) ──"
  # ⛔ v6.5.8: SAY WHAT IS AND IS NOT COVERED. This used to print a bare "LIBTEST_OK:
  # <host>" with no numerator, denominator or the word "subset", so a gate running 32 of
  # 255 tcyr read as authoritative — and 6.5.7 proved the blind region holds real,
  # multi-release-shipped defects (xrmdir was broken on macOS-arm64 for five releases).
  # No silent caps: if the selection narrows the corpus, the number dropped is printed.
  if [ -z "$LIBTEST" ]; then
    echo "  corpus: ALL $SEL_N of $CORPUS_TOTAL tcyr (CYRIUS_CROSS_OS_FULL=1)"
  else
    echo "  corpus: $SEL_N of $CORPUS_TOTAL tcyr selected by subdir 'tests/tcyr/${LIBTEST}' ($((CORPUS_TOTAL - SEL_N)) NOT run on $HOST — set CYRIUS_CROSS_OS_FULL=1 for the whole corpus)"
  fi

  case "$HOST" in
    ecb) LT_CC='CYRIUS_MACHO_ARM=1 ./r1r'; LT_SIGN=1 ;;
    ach) LT_CC='./r1';                     LT_SIGN=0 ;;
    pi)  LT_CC='./r1';                     LT_SIGN=0 ;;
    *)   LT_CC='';                         LT_SIGN=0 ;;
  esac

  if [ -n "$LT_CC" ]; then
    # ── ONE ssh for the whole corpus (v6.5.8). The loop it replaces opened a fresh
    # connection PER TEST: ~1.8 s of handshake on cass, ~0.9 s on pi, with zero test
    # value. Batching is what pays for widening the corpus — the tests were never the
    # cost driver, the connections were. The runner is scp'd rather than inlined because
    # nesting a remote for-loop inside ssh quoting is exactly the class of bug the cass
    # notes in CLAUDE.md warn about.
    scp -q $SSHO scripts/cross-os-libtest-runner.sh "$HOST:~/_cyaud/_lt_run.sh" || {
      echo "LIBTEST_FAIL: could not ship the runner to $HOST"; exit 1; }
    LT_OUT=$(ssh $SSHO "$HOST" "cd ~/_cyaud && sh _lt_run.sh '$LT_CC' '$LT_SIGN' '$LIBTEST'" 2>&1) || true
    ssh $SSHO "$HOST" 'rm -f ~/_cyaud/_lt_run.sh' >/dev/null 2>&1 || true
    LT_SUM=$(printf '%s\n' "$LT_OUT" | grep '__LIBTEST_SUMMARY__' | tail -1)
    if [ -z "$LT_SUM" ]; then
      printf '%s\n' "$LT_OUT" | tail -8
      echo "LIBTEST_FAIL: $HOST produced no summary (runner did not complete)"
      exit 1
    fi
    LT_PASS=$(echo "$LT_SUM" | awk '{print $2}')
    LT_FAIL=$(echo "$LT_SUM" | awk '{print $3}')
    echo "  ran $LT_PASS passed, $LT_FAIL failed on $HOST"
    # ⛔ v6.5.11: THE REMOTE MUST HAVE RUN WHAT WE SELECTED. Nothing used to compare the
    # locally-computed SEL_N against the remote's pass+fail, so a corpus of 260 and a
    # corpus of 0 were indistinguishable to this gate: the runner re-globs on the far
    # side, an unmatched glob yields "__LIBTEST_SUMMARY__ 0 0", LT_FAIL=0 skips the
    # failure branch, and the next line printed "LIBTEST_OK: <host> (0 tests)" — GREEN,
    # having run nothing. That is precisely the macOS-rot shape this whole gate exists
    # to prevent, and it was reachable before any file moved.
    LT_RAN=$((LT_PASS + LT_FAIL))
    if [ "$LT_RAN" -ne "$SEL_N" ]; then
      printf '%s\n' "$LT_OUT" | tail -8
      echo "  LIBTEST_FAIL: $HOST ran $LT_RAN test(s) but $SEL_N were selected — the remote saw a different corpus (stale checkout, or a selector that matches here and not there)"
      exit 1
    fi
    if [ "$LT_FAIL" != "0" ]; then
      printf '%s\n' "$LT_OUT" | grep '__LIBTEST_FAILED__' | sed 's/__LIBTEST_FAILED__/  failing:/'
      echo "  LIBTEST_FAIL: $LT_FAIL test(s) on $HOST"
      exit 1
    fi
    echo "LIBTEST_OK: $HOST ($LT_PASS tests of $CORPUS_TOTAL corpus)"
  else
    # cass keeps the per-test loop DELIBERATELY. Its remote shell is cmd.exe, where
    # `prog & echo %errorlevel%` reports 0 at parse time and a redirect inside a
    # backgrounded compound corrupts the output — the quoting rules that make a batched
    # remote loop safe on POSIX do not transfer, and this leg is the one that most needs
    # to stay trustworthy. See the cass notes in CLAUDE.md.
    # v6.5.10: ACCUMULATE like the POSIX hosts instead of exiting on the first failure.
    # ⚠ This leg was the only one that stopped at failure #1, so a full-corpus run on cass
    # could never produce a count — it reported "5 passed" and quit, which is not a
    # measurement. The per-test ssh stays (the cmd.exe quoting is the hazard, not the loop);
    # only the bookkeeping changed.
    # ⛔ EVERY REMOTE CALL IS TIMEOUT-WRAPPED. `ConnectTimeout` covers only connection
    # SETUP, not how long the remote command runs — so a test that blocks on Windows hung
    # this leg FOREVER. Measured: `tls_native_freestanding.tcyr` held one ssh for 33
    # minutes with no output before it was killed by hand. It stayed invisible because the
    # old loop was fail-fast and quit at an earlier failure without ever reaching it.
    # A timeout also has to COUNT as a failure, not abort the sweep — a hang is a result.
    cass_p=0; cass_f=0; cass_t=0; cass_bad=""; cass_n=0
    for t in $TESTS; do
      base=$(basename "$t")
      wt=$(echo "$t" | tr '/' '\\')
      cass_n=$((cass_n + 1))
      rc=0
      timeout 90 ssh $SSHO cass "cmd /v /c \"cd /d C:\\cyrius-tests\\_cyaud && c2.exe < $wt > _lt.exe && _lt.exe & if !errorlevel! NEQ 0 (exit 1) else (exit 0)\"" >/dev/null 2>&1 || rc=$?
      if [ "$rc" = "0" ]; then
        cass_p=$((cass_p + 1))
      elif [ "$rc" = "124" ]; then
        cass_t=$((cass_t + 1)); cass_f=$((cass_f + 1)); cass_bad="$cass_bad ${base}(HANG)"
      else
        cass_f=$((cass_f + 1)); cass_bad="$cass_bad $base"
      fi
      # Progress: 260 sequential SSH round-trips is minutes of silence otherwise, and
      # silence is exactly what made the hang look like normal slowness.
      if [ $((cass_n % 25)) = "0" ]; then
        echo "  ... $cass_n/$SEL_N (pass $cass_p, fail $cass_f)"
      fi
    done
    [ "$cass_t" != "0" ] && echo "  ⚠ $cass_t test(s) TIMED OUT at 90s (counted as failures)"
    echo "  ran $cass_p passed, $cass_f failed on cass"
    if [ "$cass_f" != "0" ]; then
      echo "  failing:$cass_bad"
      echo "  LIBTEST_FAIL: $cass_f test(s) on cass (PE-incompatible? fork/socketpair are POSIX-only)"
      exit 1
    fi
    echo "LIBTEST_OK: cass ($cass_p tests)"
  fi
fi
