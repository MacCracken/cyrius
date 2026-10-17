# cx: a conditional jump (`jz` / `jnz`) over more than 128 KiB of bytecode wraps its 16-bit offset silently — the compile exits 0 and cxvm jumps to the wrong place — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib, after the cx code-region
growth); the defect is older than the growth (6.6.x's 512 KiB region already held a fn this size).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — a silent miscompile on the cx target: `cycc_cx` exits 0 and writes a `.cyx` whose branch lands
at a wrapped offset. Here cxvm caught it (a negative pc traps since 6.6.12); a wrap that lands inside the code runs
the wrong instructions with no diagnostic. 6.7.12's 4 MiB code region makes fns this large more reachable.
**Discovered:** 2026-10-15, the 6.7.12 stdlib lane (unit L2), while growing cx's code region
(`issues/archived/2026-10-12-cx-codebuf-512k-overflows-yukti-crossos-test.md`): checking which offsets the bigger region can
exceed.

## Reproduction

A fn whose `if` body is ~150 KB of cx bytecode (1500 statements, ~100 B each), generated:

```sh
cd /home/macro/.cache/c6/wt6712/stdlib     # any tree at or after 6.7.12's cx bite
awk 'BEGIN { print "var g = 1;"; print "fn f(a): i64 {\n    var x = a;\n    if (a == 5) {";
  for (i = 0; i < 1500; i++) print "        x = x + g * 3 - 1;";
  print "    }\n    return x;\n}"; print "syscall(60, f(1) % 251);" }' > jz.cyr
cat src/main_cx.cyr | build/cycc > cycc_cx; cat programs/cxvm.cyr | build/cycc > cxvm; chmod +x cycc_cx cxvm
./cycc_cx < jz.cyr > jz.cyx; echo "compile rc=$?"
./cxvm < jz.cyx; echo "cx=$?"
build/cycc < jz.cyr > jz.x && chmod +x jz.x && ./jz.x; echo "native=$?"
```

```text
compile rc=0
cxvm: jump to a negative code offset: -112020 at pc 120
cx=1
native=1
```

## Root cause

`src/backend/cx/emit.cyr` `EPATCH`: for `jz` (0x51) / `jnz` (0x52) the relative offset, in 4-byte instruction units,
is stored in bytes 2-3 only (byte 1 is the register) — a signed 16-bit field, ±32768 instructions = ±128 KiB.
`rel = (cp - off) / 4` is written with `& 0xFF` / `>> 8 & 0xFF` and no range check, so a body longer than 128 KiB
wraps (here +37,5xx instructions read back as a negative offset). `jmp` / `call` carry 24 bits (±32 MB) and are not
affected. cxvm's decoder (programs/cxvm.cyr, `off > 0x7FFF` sign-extension) is consistent with the 16-bit encoding;
the emitter is what never checks.

## Fix (sketch — the user's call where it changes the format)

Either refuse by name in EPATCH when `rel` leaves [-32768, 32767] ("a conditional branch spans more than 128 KiB of
cx bytecode in fn <name>"), or lower a far conditional to `jz/jnz` over an unconditional 24-bit `jmp` (an inverted
short branch around a long jump), which needs no `.cyx` format change. A row: the repro above exits 1 natively and
on cxvm (or is refused by name).
