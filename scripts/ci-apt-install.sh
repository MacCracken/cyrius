#!/bin/sh
# scripts/ci-apt-install.sh <package>... — install Ubuntu packages on a GitHub-hosted runner over
# HTTPS mirrors only, bounded, so a mirror that does not answer fails the step in minutes.
#
# THE DEFECT (6.6.20's CI, ~10 minutes on "Install qemu-user"). The runner reads its Ubuntu archive
# through `mirror+file:/etc/apt/apt-mirrors.txt`, whose first entry is plain-http
# azure.archive.ubuntu.com. Our workaround for that mirror's flakiness sed'ed it to
# http://archive.ubuntu.com — and from GitHub's runners port 80 there times out, so every index
# file logged `Ign:` after a full timeout before apt fell back to the list's https entry, which
# answered at once (`Hit:2 https://archive.ubuntu.com/ubuntu noble InRelease`). Measured from a
# workstation 2026-10-07: https archive.ubuntu.com and mirrors.edge.kernel.org answer;
# https azure.archive.ubuntu.com does not.
#
# THE FIX. Write the mirror list ourselves, https only; rewrite any plain-http Ubuntu archive URI in
# the classic sources files the same way; give apt per-file timeouts and retries; skip the network
# entirely when every package is already installed. The step that calls this carries its own
# `timeout-minutes`, so a dead network is a red step, never a six-hour job.
set -eu
[ "$#" -ge 1 ] || { echo "usage: sh scripts/ci-apt-install.sh <package>..." >&2; exit 2; }

need=""
for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"
done
if [ -z "$need" ]; then
    echo "ci-apt-install: already installed:$(printf ' %s' "$@")"
    exit 0
fi

M=/etc/apt/apt-mirrors.txt
if [ -f "$M" ]; then
    printf 'https://archive.ubuntu.com/ubuntu/\tpriority:1\nhttps://mirrors.edge.kernel.org/ubuntu/\tpriority:2\n' \
        | sudo tee "$M" >/dev/null
fi
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    sudo sed -i -E 's#http://(azure\.)?(archive|security)\.ubuntu\.com#https://\2.ubuntu.com#g' "$f"
done

APTO="-o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20"
# shellcheck disable=SC2086
sudo apt-get $APTO update
# shellcheck disable=SC2086
sudo apt-get $APTO install -y $need
