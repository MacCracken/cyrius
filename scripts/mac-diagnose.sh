#!/bin/sh
# mac-diagnose.sh — dump everything needed to debug a SIGILL in cycc_macho.
# Run on the Mac. Paste the whole output back. Should take <5 seconds.
set +e  # keep going past failing commands

CC5=${1:-./cycc_macho}

echo "=== System ==="
uname -m
sw_vers 2>/dev/null
echo

echo "=== Binary ==="
ls -la "$CC5"
file "$CC5"
echo
otool -h "$CC5" 2>&1 | head -10
echo

echo "=== Codesign ==="
codesign -dvvv "$CC5" 2>&1 | head -10
codesign --verify --verbose "$CC5" 2>&1
echo

echo "=== Direct run ==="
# v6.6.6: a CHECKED private temp, not /tmp/cc5_stdout + /tmp/cc5_stderr — fixed names in a
# world-writable directory, and the redirect follows a symlink another user planted there.
# CHANGELOG [6.6.6]
_md=$(mktemp -d) && [ -d "$_md" ] || { echo "ERROR: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$_md"' EXIT
"$CC5" < /dev/null > "$_md/cc5_stdout" 2> "$_md/cc5_stderr"
ec=$?
echo "exit=$ec  (132=SIGILL, 137=SIGKILL, 139=SIGSEGV, 0=clean)"
echo "stdout bytes: $(wc -c < "$_md/cc5_stdout")"
echo "stderr:"
head -5 "$_md/cc5_stderr"
echo

echo "=== Crash dump (if one landed) ==="
ls -lt ~/Library/Logs/DiagnosticReports 2>/dev/null | head -3
latest=$(ls -t ~/Library/Logs/DiagnosticReports/cycc_macho* 2>/dev/null | head -1)
if [ -n "$latest" ]; then
    echo "--- $latest ---"
    head -60 "$latest"
fi
echo

echo "=== Done ==="
