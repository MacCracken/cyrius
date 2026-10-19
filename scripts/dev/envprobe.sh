#!/bin/sh
# scripts/dev/envprobe.sh — a Linux dev machine's inventory: what a new box has, and lacks, next to
# the one the toolchain is developed on.
#
# Usage:  sh scripts/dev/envprobe.sh            (run it on each box and diff the two outputs)
#
# Input:  the running machine only (/proc, /etc, ulimit, locale, the network); it reads no repo file.
# Output: one `key: value` / `key=value` line per item on stdout — CPU and core count, memory, kernel,
#         the sysctls the toolchain's gates and tools touch (ASLR, mmap_min_addr, ptrace scope, user
#         namespaces, perf, inotify, overcommit, pid_max, max_map_count), ulimits, locale, timezone,
#         /tmp's mount options and size, binfmt_misc (qemu-user's registrations), HTTPS reachability
#         of 1.1.1.1 and api.github.com (8 s each), systemd-binfmt, TMPDIR / WINEPREFIX / CYRIUS_HOME,
#         and the installed package count where pacman exists. An unreadable item prints n/a (or
#         the tool's own error on stderr); the exit status is 0.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md

echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')  nproc=$(nproc)"
echo "mem: $(free -g | awk '/Mem:/{print $2"G"}')"
echo "kernel: $(uname -r)"
for s in kernel.randomize_va_space vm.mmap_min_addr kernel.yama.ptrace_scope kernel.unprivileged_userns_clone \
         user.max_user_namespaces kernel.perf_event_paranoid fs.inotify.max_user_watches vm.overcommit_memory \
         kernel.pid_max vm.max_map_count; do
    printf "%s=%s\n" "$s" "$(cat "/proc/sys/$(echo "$s" | tr . /)" 2>/dev/null || echo n/a)"
done
# ulimit's options other than -f are not POSIX: a shell without one prints n/a for it
echo "ulimit -n=$(ulimit -n 2>/dev/null || echo n/a) -s=$(ulimit -s 2>/dev/null || echo n/a) -u=$(ulimit -u 2>/dev/null || echo n/a) -v=$(ulimit -v 2>/dev/null || echo n/a) -c=$(ulimit -c 2>/dev/null || echo n/a)"
echo "locale: LANG=${LANG:-unset} LC_ALL=${LC_ALL:-unset}; $(locale 2>/dev/null | grep -E '^LC_CTYPE')"
echo "localectl-conf: $(cat /etc/locale.conf 2>/dev/null)"
echo "tz: $(readlink /etc/localtime)"
echo "tmp: $(findmnt -no OPTIONS /tmp)"
echo "tmp-size: $(df -h /tmp | awk 'NR==2{print $2}')"
echo "binfmt: $(cat /proc/sys/fs/binfmt_misc/status) entries=$(ls /proc/sys/fs/binfmt_misc | grep -vE '^(register|status)$' | tr '\n' ' ')"
echo "net-1.1.1.1:443: $(timeout 8 curl -s -o /dev/null -w '%{http_code}' https://1.1.1.1/ 2>&1 || echo FAIL)"
echo "net-github: $(timeout 8 curl -s -o /dev/null -w '%{http_code}' https://api.github.com/ 2>&1 || echo FAIL)"
echo "systemd-binfmt: $(systemctl is-active systemd-binfmt 2>&1)"
echo "TMPDIR=${TMPDIR:-unset} WINEPREFIX=${WINEPREFIX:-unset} CYRIUS_HOME=${CYRIUS_HOME:-unset}"
if command -v pacman > /dev/null 2>&1; then
    echo "pacman pkgs: $(pacman -Q | wc -l)"
else
    echo "pacman pkgs: n/a (no pacman)"
fi
