#!/bin/sh
# Gate: an `object;` build does not export libc-reserved names as preemptible symbols.
#
# ⛔ THE INCIDENT (samvada, 2026-09-09). `object;` mode exported every public fn as a GLOBAL
# symbol with DEFAULT visibility. Linked against a C library, the C library's OWN calls bound to
# cyrius's implementation — and the contracts are inverted in both directions:
#
#     C:      void *memchr(const void *s, int c, size_t n)   -> pointer, or NULL
#     cyrius: fn memchr(s, c, n) -> i64                      -> OFFSET, or -1
#
# "Not found" hands C a non-NULL 0xFFFFFFFFFFFFFFFF so it proceeds as if it found something;
# "found at offset 0" hands C a NULL so it concludes not-found. samvada's process HUNG inside
# `sd_bus_call_method`; `objcopy -L memchr` alone fixed it.
#
# ⚠ WHY IT WAS EASY TO MISS. The link SUCCEEDS — libc's copy is weak or in a not-yet-loaded .so,
# so there is no duplicate-symbol error. The failure surfaces inside a C function the cyrius
# author never called. And it is conditional on REACHABILITY: if nothing pulls `memchr` into the
# object it is eliminated and there is no bug, so a project links cleanly for months and then
# breaks because unrelated code made the symbol reachable.
#
# ⚠ THE OBVIOUS DERIVATION POINTS AT THE WRONG SYMBOL. Comparing the object's globals against
# libc's DYNAMIC exports returns only `getenv`, because glibc's memchr/memcpy/strlen are IFUNCs
# and do not match a naive type filter. Localizing `getenv` changes nothing; `memchr` is the one.
#
# ⭐ STV_HIDDEN, NOT STB_LOCAL. ELF requires all LOCAL symbols to precede all GLOBAL ones, with
# sh_info naming the first global — flipping the binding of an arbitrary subset would break that
# invariant and require reordering the whole table. HIDDEN keeps the binding GLOBAL (ordering
# untouched) and `ld` makes it local at link time, which is the property actually wanted.
#
# ⭐ AXIS 2 IS THE ANTI-VACUOUS ONE. Hiding EVERY symbol would pass axis 1 and silently break
# every consumer that links a cyrius object for its own entry points — including mabda, whose C
# launcher calls `_cyrius_init` and `mabda_main()` directly.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYCC=${CYCC_BIN:-"$ROOT/build/cycc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: object_hides_libc_names: $1"; exit 1; }
[ -x "$CYCC" ] || fail "no cycc at $CYCC"
command -v readelf >/dev/null 2>&1 || { echo "SKIP: object_hides_libc_names (no readelf)"; exit 0; }
cd "$ROOT"

# Reach every one of the 11 reserved names so none is eliminated as unreachable — the bug only
# bites when the symbol is actually emitted, so a probe that does not reach them proves nothing.
cat > "$WORK/o.cyr" <<'EOF'
object;
include "lib/string.cyr"
include "lib/io.cyr"
fn app_touch_all(a, b) {
    var t = 0;
    t = t + memchr(a, 65, 8);
    t = t + strchr(a, 65);
    t = t + strstr(a, b);
    t = t + strlen(a);
    t = t + atoi(a);
    memcpy(a, b, 4);
    memset(a, 0, 4);
    t = t + getpid();
    t = t + getppid();
    t = t + gettid();
    t = t + getenv(b);
    return t;
}
fn app_public_entry(x) { return x + 1; }
EOF
"$CYCC" < "$WORK/o.cyr" > "$WORK/o.o" 2>"$WORK/o.err" || fail "probe object did not compile: $(head -3 "$WORK/o.err")"
readelf -sW "$WORK/o.o" > "$WORK/syms.txt" 2>/dev/null || fail "readelf failed on the object"

_vis() { awk -v n="$1" '$8==n {print $6; exit}' "$WORK/syms.txt"; }

# ── axis 1: every libc-reserved name the object defines is HIDDEN ───────────────────────
# The list is a property of the LANGUAGE, not of the build host's libc — it was derived from the
# intersection of cyrius's stdlib public fns with a full libc symbol set, and is committed as a
# fixed list in src/backend/x86/fixup.cyr (_fx_libc_reserved).
MISSING=""
for n in memchr memcpy memset strchr strlen strstr atoi getenv getpid getppid gettid; do
    v=$(_vis "$n")
    [ -n "$v" ] || { MISSING="$MISSING $n(absent)"; continue; }
    [ "$v" = "HIDDEN" ] || MISSING="$MISSING $n($v)"
done
[ -z "$MISSING" ] || fail "axis 1: these libc-reserved names are not HIDDEN in the object:$MISSING"

# ⚠ ANTI-VACUOUS FLOOR: if the probe stopped reaching these names they would vanish from the
# object and axis 1 would pass by finding nothing to check.
NFOUND=$(awk '$8=="memchr"||$8=="strlen"||$8=="getenv"{c++} END{print c+0}' "$WORK/syms.txt")
[ "$NFOUND" -eq 3 ] || fail "axis 1 floor: expected memchr+strlen+getenv in the object, found $NFOUND — the probe is not reaching them"

# ── axis 2 (ANTI-VACUOUS): the object's OWN public entry points stay exported ────────────
# Hiding everything would satisfy axis 1 and break every consumer that links a cyrius object.
for n in app_touch_all app_public_entry; do
    v=$(_vis "$n")
    [ -n "$v" ] || fail "axis 2: the object no longer exports its own fn '$n' at all"
    [ "$v" = "DEFAULT" ] || fail "axis 2: the object's own fn '$n' has visibility $v, expected DEFAULT — the guard is too broad"
done

# ── axis 3: _cyrius_init must remain callable from C ────────────────────────────────────
# mabda's C launcher calls a cyrius object's `_cyrius_init` before its main. It was STB_LOCAL from
# v4.6.0-alpha2..v5.4.8 and that broke the link with `undefined reference`; v5.4.9 made it GLOBAL.
# This gate must not silently re-break it.
IV=$(_vis "_cyrius_init")
[ -n "$IV" ] || fail "axis 3: _cyrius_init is absent from the object"
[ "$IV" = "DEFAULT" ] || fail "axis 3: _cyrius_init visibility is $IV, expected DEFAULT (mabda's C launcher calls it)"
IB=$(awk '$8=="_cyrius_init"{print $5; exit}' "$WORK/syms.txt")
[ "$IB" = "GLOBAL" ] || fail "axis 3: _cyrius_init binding is $IB, expected GLOBAL"

# ── axis 4: a name that merely LOOKS libc-ish is not hidden ──────────────────────────────
# `memeq` is cyrius-only with no libc counterpart — mabda's hand-maintained objcopy list
# localizes it, which is a no-op there and would be a real regression here. The list must be the
# derived intersection, not a prefix match on mem*/str*.
cat > "$WORK/n.cyr" <<'EOF'
object;
include "lib/string.cyr"
fn app_uses_memeq(a, b) { return memeq(a, b, 4); }
EOF
"$CYCC" < "$WORK/n.cyr" > "$WORK/n.o" 2>/dev/null || fail "axis 4: probe did not compile"
readelf -sW "$WORK/n.o" > "$WORK/nsyms.txt" 2>/dev/null || fail "axis 4: readelf failed"
MV=$(awk '$8=="memeq"{print $6; exit}' "$WORK/nsyms.txt")
[ -n "$MV" ] || fail "axis 4: memeq absent — probe does not reach it"
[ "$MV" = "DEFAULT" ] || fail "axis 4: memeq is $MV — it has NO libc counterpart and must not be hidden (the guard is matching a prefix, not the derived list)"

echo "PASS: object_hides_libc_names (4 axes: 11-name coverage, own-exports-preserved, _cyrius_init-callable, no-prefix-overreach)"
