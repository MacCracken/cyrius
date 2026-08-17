#!/bin/sh
# v6.5.24 — bare-metal forbidden-module check (bare-metal arc deliverable #4).
#
# THE ARC'S OWN ACCEPTANCE, unbuilt for ~2 months and briefly lost: "forbidden-module
# check errors clearly when bare-metal code pulls host-OS modules", plus for #7 "a kernel
# object links tls_native freestanding AND passes the forbidden-module check". The v6.3.4
# premise-check found no such check existed; the issue was then bulk-renamed into
# `issues/archived/` on 2026-07-10 with NO resolution banner, for work that was never
# built, and sat in the resolved graveyard while the roadmap still listed it as live.
# Restored 2026-08-11, built here. `issues/README.md` states the principle it violated:
# archiving is how we assert something is DONE.
#
# HOW IT WORKS. A host-OS-only module marks itself with a first-column `#host_only` line;
# the preprocessor records the first such module pulled, and the check fires at the end of
# PARSE_PROG. An ANNOTATION rather than a central deny-list because the fact then lives in
# the module it describes and moves with the file — a central list is the self-drifting
# value shape that bit three separate places this cycle. Unannotated modules stay allowed,
# so the default is unchanged rather than breaking every kernel build.
#
# ⚠ WHY THE CHECK IS NOT AT THE INCLUDE SITE. `PREPROCESS(S)` runs at main.cyr:1189 and
# the CYRIUS_KERNEL env is not read until :1217, so kernel_mode is still 0 while includes
# expand. The first cut checked it there and the gate silently never fired — the same
# always-green shape this file exists to prevent. End-of-PARSE_PROG also catches the
# source `kernel;` directive (axis 3), which is not known until every top-level statement
# is parsed.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
T=$(mktemp --suffix=.cyr); E=$(mktemp); O=$(mktemp)
trap 'rm -f "$T" "$E" "$O"' EXIT
fail=0

pull_fs() {
    printf 'include "lib/syscalls.cyr"\ninclude "lib/fs.cyr"\nfn main(): i64 { return 0; }\nvar ec = main();\nsyscall(60, ec);\n' > "$T"
}
no_fs() {
    printf 'include "lib/syscalls.cyr"\nfn main(): i64 { return 0; }\nvar ec = main();\nsyscall(60, ec);\n' > "$T"
}
hit() { grep -c "host-only module" "$E" 2>/dev/null || true; }

# --- axis 1: a HOST build pulling lib/fs.cyr must be completely unaffected ---
# The single most important negative: every ordinary consumer build includes host modules.
pull_fs
"$CC" < "$T" > "$O" 2>"$E" || true
if [ "$(hit)" != "0" ]; then echo "  FAIL axis 1: a HOST build pulling lib/fs.cyr was rejected — the check leaked outside kernel mode"; fail=1
else echo "  ok axis 1: host build pulling lib/fs.cyr is unaffected"; fi

# --- axis 2: a KERNEL build (the --target=...-bare-metal-elf env path) must ERROR ---
pull_fs
CYRIUS_KERNEL=1 "$CC" < "$T" > "$O" 2>"$E" || true
if [ "$(hit)" = "0" ]; then echo "  FAIL axis 2: CYRIUS_KERNEL=1 build pulling #host_only lib/fs.cyr did NOT error"; fail=1
else
    # The message must NAME the module, or it is not the "errors clearly" the arc asked for.
    if grep -q "lib/fs.cyr" "$E"; then echo "  ok axis 2: kernel build pulling lib/fs.cyr errors and names the module"
    else echo "  FAIL axis 2: errored but did not NAME the offending module"; fail=1; fi
fi

# --- axis 3: the source `kernel;` directive path must error too (no env set) ---
printf 'kernel;\ninclude "lib/syscalls.cyr"\ninclude "lib/fs.cyr"\nfn main(): i64 { return 0; }\n' > "$T"
"$CC" < "$T" > "$O" 2>"$E" || true
if [ "$(hit)" = "0" ]; then echo "  FAIL axis 3: source \`kernel;\` build pulling #host_only lib/fs.cyr did NOT error (env-only check?)"; fail=1
else echo "  ok axis 3: source \`kernel;\` declaration is caught as well"; fi

# --- axis 4 (POSITIVE, anti-vacuous): a kernel build pulling NO host-only module builds ---
# Axes 2-3 assert failures, so a check that rejected EVERY kernel build would pass them.
no_fs
CYRIUS_KERNEL=1 "$CC" < "$T" > "$O" 2>"$E" || true
if [ "$(hit)" != "0" ]; then echo "  FAIL axis 4: a clean kernel build was rejected — the check fires on modules that are not #host_only"; fail=1
else echo "  ok axis 4: clean kernel build still compiles (check is not blanket)"; fi

# --- axis 5: the arc's own #7 fixture must PASS the check (its stated acceptance) ---
if [ -f tests/fixtures/freestanding_tls/kernel_link.cyr ]; then
    CYRIUS_KERNEL=1 "$CC" < tests/fixtures/freestanding_tls/kernel_link.cyr > "$O" 2>"$E" || true
    if [ "$(hit)" != "0" ]; then echo "  FAIL axis 5: the freestanding_tls #7 fixture now FAILS the forbidden-module check"; fail=1
    else echo "  ok axis 5: freestanding_tls #7 fixture passes the check (arc acceptance)"; fi
else
    echo "  note axis 5: tests/fixtures/freestanding_tls/kernel_link.cyr absent — skipped"
fi

# --- axis 6: a cbt MANIFEST-supplied host-only module must NOT fail a kernel build ---
# ⛔ THE FALSE POSITIVE THIS GATE MISSED FIRST TIME. cbt prepends one `include` per
# `[deps].stdlib` module to EVERY build regardless of target, so this repo's own
# `programs/boot_serial.cyr` — a kernel with NO includes of its own — inherited `lib/fs.cyr`
# from the manifest and the first cut FAILED it. Only check.sh's qemu-boot gate caught it
# ("FAIL: plain kernel build"); left in, every kernel build in every repo whose manifest
# lists a host-only module would break, which makes the feature unusable rather than useful.
# `#@srcline` separates cbt's prepends from the user's file, so attribution is now exact.
# Axes 2-3 above prove the USER-include case still errors, so this is not a silent disarm.
if [ -f programs/boot_serial.cyr ] && [ -x build/cyrius ]; then
    if build/cyrius build programs/boot_serial.cyr "$O" 2>&1 | grep -q "host-only module"; then
        echo "  FAIL axis 6: a manifest-supplied host-only module failed a kernel build — cbt's prepends are being blamed on the kernel author"
        fail=1
    else
        echo "  ok axis 6: manifest-supplied (cbt-prepended) host-only module does not fail a kernel build"
    fi
else
    echo "  note axis 6: programs/boot_serial.cyr or build/cyrius absent — skipped"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: bare-metal-forbidden-module"; exit 1; }
echo "PASS: bare-metal-forbidden-module — #host_only modules rejected under CYRIUS_KERNEL and \`kernel;\`, host builds and clean kernel builds unaffected"
