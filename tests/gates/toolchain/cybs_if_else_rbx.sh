#!/bin/sh
# v6.5.33 — cybs must not stray-write into the code stream from `parse_if_else`.
#
# ⛔ THE DEFECT. `parse_if_else` (bootstrap/cybs.cyr) emits an `E9` + a 4-byte hole for the
# skip-over-else jump, records the hole's offset in **rbx**, recursively parses the else body
# with `call parse_program`, and only then patches. Something inside that recursive parse
# CLOBBERS rbx, so the deferred `patch_rel32` fired with a stale value and wrote a 4-byte
# rel32 into an arbitrary place in the code stream.
#
# ⭐ IT CORRUPTED EVERY BUILD, not just failing ones. Instrumented tracing of `gen1` showed
# exactly ONE orphan patch (a PATCH with no matching SET) in the ordinary build too — it just
# happened to land inside a `movabs` immediate, where a wrong constant in that particular spot
# was survivable. Shift the layout by ~80 bytes (adding any branching fn to
# `src/common/util.cyr` did it) and the same stray write lands on an INSTRUCTION BOUNDARY:
# `gen1` then links fine and dies with SIGILL/SIGSEGV compiling `src/main.cyr`.
#
# That is why it read as "util.cyr cannot take a branching function" for a release — a
# position-dependent symptom of a register-discipline bug three layers down. `build/cycc`
# compiles every variant correctly, so ONLY the seed chain ever saw it.
#
# ⚠ The `(x >> 62)` probe that also broke the chain was NOT a second bug — same stray write,
# different landing site. Verified after the fix: both probes derive clean.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
[ -x bootstrap/asm ] || { echo "SKIP: bootstrap/asm missing"; exit 0; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
fail=0

# --- axis 1 (STRUCTURAL): rbx must be saved across the recursive else-body parse ---
# Cheap, and it is what stops the fix being "tidied" away. Checks that a push/pop brackets the
# `call parse_program` inside parse_if_else.
if awk '/^parse_if_else:/{inblk=1} inblk && /push rbx/{p=1} inblk && /call parse_program/{if(!p) bad=1} inblk && /^parse_if_done:/{inblk=0} END{exit bad?1:0}' bootstrap/cybs.cyr; then
    echo "  ok axis 1: parse_if_else saves rbx across the recursive parse"
else
    echo "  FAIL axis 1 (structural): parse_if_else calls parse_program without saving rbx — the deferred patch offset can be clobbered again"
    fail=1
fi

# --- axis 2: the seed still assembles cybs, and cybs still reproduces the seed ---
# Any edit to cybs.cyr must keep the closure. Fast (~1s).
cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
if [ ! -s "$D/cybs" ]; then
    echo "  FAIL axis 2: the seed could not assemble bootstrap/cybs.cyr"
    fail=1
else
    cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
    if cmp -s "$D/asm2" bootstrap/asm; then
        echo "  ok axis 2: seed->cybs->seed closure holds"
    else
        echo "  FAIL axis 2: cybs no longer reproduces the seed — the bootstrap root is broken"
        fail=1
    fi
fi

# --- axis 3 (BEHAVIOURAL, the one that actually caught this): a branching fn in util.cyr ---
# ⭐ THIS IS THE REGRESSION TEST. Inject a branching fn into src/common/util.cyr, have cybs
# build gen1, and require gen1 to WORK. Before the fix gen1 built and then died with SIGILL on
# its first real compile — which is precisely why nothing but the seed chain ever noticed.
# Bounded: one cybs run plus one small compile, not a full seed-derive.
if [ -s "$D/cybs" ]; then
    cp src/common/util.cyr "$D/util.bak"
    python3 - <<'PY'
p='src/common/util.cyr'; s=open(p).read()
a='var _vecv_base = 0;    # 0x1D8000 enum_const_val'
assert s.count(a)==1, "anchor moved — update this gate"
open(p,'w').write(s.replace(a, a+'\nfn _cy_gate_probe(x): i64 { if (x != 0) { return x; } return 0; }', 1))
PY
    cat src/main.cyr | "$D/cybs" > "$D/gen1" 2>/dev/null || true
    cp "$D/util.bak" src/common/util.cyr
    chmod +x "$D/gen1" 2>/dev/null || true
    if [ ! -s "$D/gen1" ]; then
        echo "  FAIL axis 3: cybs produced no gen1 with a branching fn in util.cyr"
        fail=1
    else
        # ⚠ gen1 must compile `src/main.cyr`, NOT a toy program. A first draft of this axis
        # used a three-line probe and SURVIVED the mutation: the stray patch lands in one
        # specific region of the emitted compiler, and a toy input never executes it. The
        # whole point of the bug is that gen1 LINKS and looks fine until it does real work.
        rc=0
        cat src/main.cyr | "$D/gen1" > "$D/gen2" 2>/dev/null || rc=$?
        if [ "$rc" -ne 0 ] || [ ! -s "$D/gen2" ]; then
            echo "  FAIL axis 3: gen1 built from a util.cyr containing a branching fn CRASHED compiling src/main.cyr (rc=$rc) — the stray patch is back"
            fail=1
        else
            echo "  ok axis 3: a branching fn in util.cyr still yields a gen1 that compiles the compiler"
        fi
    fi
fi

# --- premise: util.cyr really is clean afterwards (the gate must not leave its probe behind) ---
if grep -q "_cy_gate_probe" src/common/util.cyr; then
    echo "  FAIL premise: the gate left its probe in src/common/util.cyr"
    fail=1
else
    echo "  ok premise: util.cyr restored"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: cybs-if-else-rbx"; exit 1; }
echo "PASS: cybs-if-else-rbx — no stray patch from parse_if_else; a branching fn in util.cyr is fine"
