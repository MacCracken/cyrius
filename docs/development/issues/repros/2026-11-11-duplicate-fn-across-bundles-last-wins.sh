#!/usr/bin/env bash
# cyrius 6.7.18: two included bundles that define the same non-private fn with the same signature compile with a
# warning, and every call — the first bundle's own calls included — goes to the LAST definition (guide: "duplicate
# fn … last definition wins"). Cyrius has one global namespace, so this is how two independent libraries collide in a
# program that uses both (ushma 2.0.0 port, M0 probe 6: ushma 1.4.0 and kimiya's bundle share 10 public names, and
# kiran uses both). Exits 1 while the program builds and bundle A's own caller silently gets B's function.
set -u
d=$(mktemp -d)
cd "$d" || exit 2
mkdir -p src
cat > cyrius.cyml <<'EOF'
[package]
name = "dupfn"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/dupfn"

[deps]
stdlib = ["syscalls", "string", "alloc", "fmt", "io"]
EOF
cat > src/a.cyr <<'EOF'
# Bundle A: pressure in Pa, and its own caller.
fn ideal_gas_pressure(n: f64, t: f64, v: f64): f64 {
    var p: f64 = (n * 8.31446261815324 * t) / v;
    return p;
}

# Bundle A's caller: expects A's ideal_gas_pressure.
fn a_pressure_kpa(n: f64, t: f64, v: f64): f64 {
    var p: f64 = ideal_gas_pressure(n, t, v);
    var k: f64 = p / 1000.0;
    return k;
}
EOF
cat > src/b.cyr <<'EOF'
# Bundle B: the same name and signature, a different meaning (here: in kPa).
fn ideal_gas_pressure(n: f64, t: f64, v: f64): f64 {
    var p: f64 = (n * 8.31446261815324 * t) / (v * 1000.0);
    return p;
}
EOF
cat > src/main.cyr <<'EOF'
include "src/a.cyr"
include "src/b.cyr"

# Prints bundle A's result for 1 mol, 300 K, 1 m^3 (2.494 kPa expected).
fn main(): i64 {
    alloc_init();
    var k: f64 = a_pressure_kpa(1.0, 300.0, 1.0);
    var milli: f64 = k * 1000.0;
    var m = f64_to(milli);
    print("a_pressure_kpa x 1000 = ", 24);
    println_int(m);
    if (m == 2494) { return 0; }
    return 1;
}

var r = main();
sys_exit_group(r);
EOF
cyrius deps > /dev/null 2>&1
cyrius build src/main.cyr build/dupfn 2>&1 | grep -E 'duplicate|error|OK' | head -3
[ -x build/dupfn ] || { echo "build refused (the fix)"; exit 0; }
./build/dupfn
rc=$?
[ $rc -eq 0 ] && { echo "A's caller got A's function"; exit 0; }
echo "A's caller got B's function (2 instead of 2494)"
exit 1
