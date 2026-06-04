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

HOST="${1:?usage: cross-os-selfhost.sh <ecb|ach|pi|cass|ecb-install>}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }

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
tar czf /tmp/_co.tgz src lib VERSION

case "$HOST" in
  ecb)
    cat src/main_aarch64.cyr       | /tmp/_co_l                   > /tmp/_co_x  && chmod +x /tmp/_co_x
    cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 /tmp/_co_x > /tmp/_co_m
    ssh $SSHO ecb 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_m ecb:~/_cyaud/
    # Self-host twice + cmp, then the v6.0.37 exit-code-propagation guard
    # (fn main(){return 42;} must exit 42 — catches the rot-class where
    # main() is never called and the program exits with argc).
    ssh $SSHO ecb 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_m && codesign -s - -f _co_m \
      && cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 ./_co_m > r1 \
      && cp r1 r1r && chmod +x r1r && codesign -s - -f r1r \
      && cat src/main_aarch64_macho.cyr | CYRIUS_MACHO_ARM=1 ./r1r > r2 \
      && cmp r1 r2 \
      && printf "fn main() { return 42; }" > _ec.cyr \
      && cat _ec.cyr | CYRIUS_MACHO_ARM=1 ./r1r > _ec && chmod +x _ec && codesign -s - -f _ec \
      && (_rc=0; ./_ec || _rc=$?; [ $_rc -eq 42 ])'
    ;;
  ach)
    # x86 ELF cycc told to emit Mach-O builds the x86 Mach-O cycc (its driver
    # hardcodes _TARGET_MACHO=1, so no env flag is needed to RUN it).
    cat src/main_x86_macho.cyr | CYRIUS_MACHO=1 /tmp/_co_l > /tmp/_co_mx
    ssh $SSHO ach 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_mx ach:~/_cyaud/
    # NO codesign (see header). Self-host twice + cmp.
    ssh $SSHO ach 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_mx \
      && cat src/main_x86_macho.cyr | ./_co_mx > r1 && chmod +x r1 \
      && cat src/main_x86_macho.cyr | ./r1 > r2 \
      && cmp r1 r2'
    ;;
  pi)
    # x86 ELF -> aarch64-emitting cross-compiler -> NATIVE aarch64 cycc.
    cat src/main_aarch64.cyr | /tmp/_co_l  > /tmp/_co_x   && chmod +x /tmp/_co_x
    cat src/main_aarch64.cyr | /tmp/_co_x  > /tmp/_co_a64 && chmod +x /tmp/_co_a64
    ssh $SSHO pi 'rm -rf ~/_cyaud && mkdir ~/_cyaud'
    scp -q $SSHO /tmp/_co.tgz /tmp/_co_a64 pi:~/_cyaud/
    ssh $SSHO pi 'cd ~/_cyaud && tar xzf _co.tgz && chmod +x _co_a64 \
      && cat src/main_aarch64.cyr | ./_co_a64 > r1 && chmod +x r1 \
      && cat src/main_aarch64.cyr | ./r1 > r2 \
      && cmp r1 r2'
    ;;
  cass)
    # x86 ELF -> PE-emitting cross-compiler (cycc_win) -> native PE cycc.exe.
    cat src/main_win.cyr | /tmp/_co_l > /tmp/_co_w && chmod +x /tmp/_co_w
    cat src/main_win.cyr | /tmp/_co_w > /tmp/_co_exe
    printf 'fn main() { return 42; }' > /tmp/_co_ec.cyr
    ssh $SSHO cass 'cmd /c "rmdir /s /q %USERPROFILE%\_cyaud 2>nul & mkdir %USERPROFILE%\_cyaud"'
    scp -q $SSHO /tmp/_co.tgz cass:_cyaud/_co.tgz
    scp -q $SSHO /tmp/_co_exe cass:_cyaud/cycc.exe
    scp -q $SSHO /tmp/_co_ec.cyr cass:_cyaud/_ec.cyr
    # cmd.exe for `<` redirection. The &&-chain stops at the first failure and
    # cmd /c returns that command's exit code, which ssh propagates back, so a
    # broken cycc.exe (emits 0 code today) fails the gate for the right reason.
    # Then the v6.0.54 exit-code guard (the WIN analog of the ecb leg's v6.0.37
    # guard): a `fn main(){return 42;}` program compiled by the NATIVE cycc.exe
    # must exit 42. The byte-identity `fc /b` above does NOT catch the rot-class
    # where main_win.cyr's DCE stubs `fn main` / never auto-calls it (the bug
    # fixed in v6.0.54). `cmd /v` is REQUIRED — bare `%errorlevel%` expands at
    # parse time and falsely reads 0 (feedback_windows_errorlevel_test_wrapper).
    ssh $SSHO cass 'cmd /c "cd /d %USERPROFILE%\_cyaud && tar xzf _co.tgz && cycc.exe < src\main_win.cyr > c2.exe && c2.exe < src\main_win.cyr > c3.exe && fc /b c2.exe c3.exe"' \
      && ssh $SSHO cass 'cmd /v /c "cd /d %USERPROFILE%\_cyaud && c2.exe < _ec.cyr > _ec.exe && _ec.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"'
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
