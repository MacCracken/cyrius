#!/bin/sh
# cx_compiler_reads_env.sh — 6.6.10. The cx compiler (cycc_cx, src/main_cx.cyr) must read its
# own environment, like every other compiler fork.
#
# THE BUG. main_cx.cyr does not include src/backend/common/runtime.cyr (it keeps its own RECFIX),
# and until 6.6.10 it compiled against `fn _read_env(name): i64 { return 0; }` in
# src/backend/cx/emit.cyr. Every CYRIUS_* knob reachable from the cx driver was dead — ten call
# sites: CYRIUS_ASYNC, CYRIUS_STACK_ARRAYS (parse.cyr), CYRIUS_DCE, CYRIUS_STATS (util.cyr),
# CYRIUS_POISON, CYRIUS_MONOMORPH (main_cx.cyr), CYRIUS_ALLOW_PARENT_INCLUDES,
# CYRIUS_ALLOW_ABSOLUTE_INCLUDES (lex.cyr), CYRIUS_TYPE_CHECK, CYRIUS_FILEID_DUMP (parse_fn.cyr).
# Derive the list, do not trust this one:
#   grep -ho '_read_env("[A-Z_]*")' <every file main_cx.cyr includes> | sort -u
# And the refusals that NAME a knob were unactionable: `CYRIUS_ASYNC=1 cycc_cx` still said
# "async fn requires CYRIUS_ASYNC=1", and `CYRIUS_ALLOW_PARENT_INCLUDES=1 cycc_cx` still said
# "path traversal rejected ... (set CYRIUS_ALLOW_PARENT_INCLUDES=1 to permit)".
# THE FIX. _env_scratch + _read_env moved into src/backend/common/env.cyr, included from
# runtime.cyr and from main_cx.cyr; the stub is gone. CHANGELOG [6.6.10]
#
# THE ROWS — three knobs read in THREE different source files, each with its unset twin, so a
# compiler that always (or never) honoured a knob fails the pair:
#   lex.cyr       CYRIUS_ALLOW_PARENT_INCLUDES  unset: rc 1 + the traversal refusal; set: rc 0 and
#                                               the .cyx runs under cxvm to the included fn's value
#   parse.cyr     CYRIUS_ASYNC                  unset: rc 1 + the gate message; set: a plain async
#                                               fn compiles and `await` yields its value under cxvm;
#                                               a coroutine reaches the cx refusal by name (dead before)
#   main_cx.cyr   CYRIUS_POISON                 predefines the CYRIUS_POISON macro: set, an #ifdef
#                                               arm is taken (exit 11); unset, it is not (exit 22)
# plus a source pin: no `fn _read_env` in the cx backend, and main_cx.cyr includes env.cyr.
#
# MUTATION (6.6.10, built and run): restore the stub in cx/emit.cyr and drop the env.cyr include
# from main_cx.cyr → every "set" row fails (parent include rc 1, async rc 1, the coroutine row
# reports the gate message instead of its refusal, POISON exit 22) and
# the source pin fails. The unset rows stay green, which is the point of pairing them.
#
# HARDWARE. cycc_cx is a HOST binary: its env read is the host arm of _read_env
# (/proc/self/environ, the macOS arm64 x28 / x86 r15 envp walk, GetEnvironmentVariableA). This
# gate runs the Linux arm; the four hosts were measured by hand at 6.6.10 (CHANGELOG).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL cx_compiler_reads_env: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL cx_compiler_reads_env: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0

"$CC" < src/main_cx.cyr > "$T/cycc_cx" 2> "$T/eb" || { echo "FAIL cx_compiler_reads_env: could not build src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
"$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/eb" || { echo "FAIL cx_compiler_reads_env: could not build programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/cycc_cx" "$T/cxvm"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# run <env-assignment|-> <dir> <fixture> — compile with cycc_cx from <dir>; sets rc, leaves .cyx in $T/o.cyx
run() {
  if [ "$1" = - ]; then (cd "$2" && env -u CYRIUS_ALLOW_PARENT_INCLUDES -u CYRIUS_ASYNC -u CYRIUS_POISON "$T/cycc_cx" < "$3" > "$T/o.cyx" 2> "$T/e"); rc=$?
  else (cd "$2" && env "$1" "$T/cycc_cx" < "$3" > "$T/o.cyx" 2> "$T/e"); rc=$?; fi
}
vm() { "$T/cxvm" < "$T/o.cyx" > /dev/null 2>&1; vrc=$?; }

# ── lex.cyr: CYRIUS_ALLOW_PARENT_INCLUDES ──────────────────────────────────────────────────
mkdir -p "$T/inc/sub"
printf 'fn from_parent(): i64 { return 7; }\n' > "$T/inc/x.cyr"
printf 'include "../x.cyr"\nsyscall(60, from_parent());\n' > "$T/inc/sub/m.cyr"
run - "$T/inc/sub" m.cyr
if [ "$rc" -ne 1 ] || ! grep -q 'path traversal rejected' "$T/e"; then _bad "parent include, knob unset: rc $rc, expected 1 with the traversal refusal"; else pass=$((pass + 1)); fi
run CYRIUS_ALLOW_PARENT_INCLUDES=1 "$T/inc/sub" m.cyr
if [ "$rc" -ne 0 ]; then _bad "parent include, CYRIUS_ALLOW_PARENT_INCLUDES=1: rc $rc — cycc_cx cannot see the knob its own refusal names"; grep '^error' "$T/e" | head -2 | sed 's/^/      /'
else vm; if [ "$vrc" -ne 7 ]; then _bad "parent include: the .cyx exits $vrc under cxvm, expected 7"; else pass=$((pass + 1)); fi; fi

# ── parse.cyr: CYRIUS_ASYNC ────────────────────────────────────────────────────────────────
cat > "$T/as.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn five(): i64 { return 5; }
fn main(): i64 { alloc_init(); var f = five(); var v = await f; return v + 30; }
syscall(60, main());
EOF
run - "$ROOT" "$T/as.cyr"
if [ "$rc" -ne 1 ] || ! grep -q 'async fn requires CYRIUS_ASYNC=1' "$T/e"; then _bad "async, knob unset: rc $rc, expected 1 with the gate message"; else pass=$((pass + 1)); fi
run CYRIUS_ASYNC=1 "$ROOT" "$T/as.cyr"
if [ "$rc" -ne 0 ]; then _bad "async, CYRIUS_ASYNC=1: rc $rc — cycc_cx cannot see the knob its own refusal names"; grep '^error' "$T/e" | head -2 | sed 's/^/      /'
else vm; if [ "$vrc" -ne 35 ]; then _bad "async: the .cyx exits $vrc under cxvm, expected 35 (await five() + 30)"; else pass=$((pass + 1)); fi; fi

# With the gate open, the cx coroutine refusal (parse_fn.cyr) is reachable for the first time:
# a mid-body suspend must be refused BY NAME on cx, not compiled.
cat > "$T/co.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn one(): i64 { return 1; }
async fn co(): i64 { var a = await one(); var b = await one(); return a + b; }
fn main(): i64 { alloc_init(); var f = co(); return await f; }
syscall(60, main());
EOF
run CYRIUS_ASYNC=1 "$ROOT" "$T/co.cyr"
if [ "$rc" -ne 1 ] || ! grep -q 'mid-body suspend is x86-only' "$T/e"; then _bad "coroutine, CYRIUS_ASYNC=1: rc $rc — expected 1 with the cx coroutine refusal"; grep '^error' "$T/e" | head -2 | sed 's/^/      /'; else pass=$((pass + 1)); fi

# ── main_cx.cyr: CYRIUS_POISON (a predefine, so the program can see it) ────────────────────
cat > "$T/po.cyr" <<'EOF'
#ifdef CYRIUS_POISON
syscall(60, 11);
#endif
syscall(60, 22);
EOF
run - "$ROOT" "$T/po.cyr"
vm
if [ "$rc" -ne 0 ] || [ "$vrc" -ne 22 ]; then _bad "POISON unset: rc $rc, cxvm exit $vrc — expected 0 / 22"; else pass=$((pass + 1)); fi
run CYRIUS_POISON=1 "$ROOT" "$T/po.cyr"
vm
if [ "$rc" -ne 0 ] || [ "$vrc" -ne 11 ]; then _bad "CYRIUS_POISON=1: rc $rc, cxvm exit $vrc — expected 0 / 11 (the knob predefines CYRIUS_POISON)"; else pass=$((pass + 1)); fi

# ── source pin ─────────────────────────────────────────────────────────────────────────────
if grep -q '^fn _read_env' src/backend/cx/emit.cyr; then _bad "src/backend/cx/emit.cyr defines _read_env again (the stub)"; else pass=$((pass + 1)); fi
if grep -q '^include "src/backend/common/env.cyr"' src/main_cx.cyr; then pass=$((pass + 1)); else _bad "src/main_cx.cyr no longer includes src/backend/common/env.cyr"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL cx_compiler_reads_env: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS cx_compiler_reads_env: $pass rows — CYRIUS_ALLOW_PARENT_INCLUDES (lex), CYRIUS_ASYNC (parse), CYRIUS_POISON (main_cx) each honoured by cycc_cx and inert when unset; no stub"
exit 0
