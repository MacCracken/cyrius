#!/bin/sh
# private_per_item_rejected.sh — v6.5.56. `private fn h()` must be REJECTED, not silently
# reinterpreted as a file-level declaration.
#
# THE DEFECT, twelve releases live. `private` flips the FILE it sits in (`_TL_VIS`,
# src/frontend/parse.cyr) — deliberately, because a running per-item flag would leak into every
# file included after it. But the per-item spelling `private fn h(): i64 { ... }` parsed with
# **no diagnostic** and privatised the ENTIRE FILE, `main` included. It reads exactly like the
# per-item visibility other languages have, so it is the spelling a user reaches for first.
#
# ⭐ THE DISCRIMINATOR IS THE LINE, not the next token. `private` alone on its own line followed
# by `fn h()` on the NEXT line is the legitimate file-level form and must keep working — so a
# naive "reject if the next token is `fn`" test would break every correct use. Axes 2 and 3 are
# what stop that fix from being written.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL private_per_item_rejected: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL private_per_item_rejected: stage1 build failed"; exit 1; }
chmod +x "$T/cc"
fail=0

# axis 1 — the per-item form must HARD ERROR and say why.
printf 'include "lib/syscalls.cyr"\nprivate fn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a1.cyr"
if "$T/cc" < "$T/a1.cyr" > /dev/null 2>"$T/a1.err"; then
  echo "FAIL private_per_item_rejected axis1: 'private fn h()' COMPILED — it silently privatises the whole file including main"
  fail=1
else
  grep -q "per-item" "$T/a1.err" || { echo "FAIL private_per_item_rejected axis1: rejected without the explaining message"; sed -n 1,2p "$T/a1.err"; fail=1; }
fi

# axis 2 — the file-level form (own line) must STILL WORK. This is what stops the axis-1 fix
# from being written as "reject if followed by fn".
printf 'include "lib/syscalls.cyr"\nprivate\nfn helper(): i64 { return 7; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a2.cyr"
"$T/cc" < "$T/a2.cyr" > "$T/a2" 2>/dev/null && chmod +x "$T/a2" && "$T/a2"
[ $? -eq 7 ] || { echo "FAIL private_per_item_rejected axis2: file-level 'private' on its own line no longer works"; fail=1; }

# axis 3 — the `private;` form must still work too (the trailing semicolon closes the statement,
# so a following `fn` on the SAME line is legal there).
printf 'include "lib/syscalls.cyr"\nprivate; fn helper(): i64 { return 9; }\nfn main(): i64 { syscall(60, helper(), 0, 0, 0, 0); return 0; }\n' > "$T/a3.cyr"
"$T/cc" < "$T/a3.cyr" > "$T/a3" 2>/dev/null && chmod +x "$T/a3" && "$T/a3"
[ $? -eq 9 ] || { echo "FAIL private_per_item_rejected axis3: 'private;' form regressed"; fail=1; }

[ $fail -eq 0 ] || exit 1
echo "PASS private_per_item_rejected: per-item form errors; own-line and 'private;' forms still work"
exit 0
