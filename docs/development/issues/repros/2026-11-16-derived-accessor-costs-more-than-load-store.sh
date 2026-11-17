#!/usr/bin/env bash
# cyrius 6.7.18: a `#derive(accessors)` accessor is inlined but costs more than the load64 / store64 it stands for.
# Per call, a setter retires 6 instructions more than `store64(p + OFF, v)` and a getter 2 more than
# `load64(p + OFF)`, and each keeps one branch (a jump, not a call: a call would add two). svara 3.8.4 found it
# in its formant bank's per-sample loop, 130 instructions a sample, and wrote the record as const offsets.
# Counts retired user instructions and branches with perf_event_open from python3 (perf_event_paranoid <= 2;
# no perf binary needed). Run:
#   bash docs/development/issues/repros/2026-11-16-derived-accessor-costs-more-than-load-store.sh; echo $?
# Exits 1 while either accessor loop retires more instructions than its load64 / store64 twin.
set -u
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cd "$d" || exit 2
cat > cyrius.cyml <<'EOF'
[package]
name = "acc"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "acc.cyr"
output = "acc"

[deps]
stdlib = ["syscalls", "string", "alloc", "str", "fmt", "args"]
EOF
cat > acc.cyr <<'EOF'
#derive(accessors)
struct Rec { a; b; c; }

const REC_A = 0;
const REC_B = 8;

fn by_setter(r, n) {
    var i = 0;
    while (i < n) { Rec_set_a(r, i); Rec_set_b(r, i); i = i + 1; }
    return 0;
}
fn by_store(r, n) {
    var i = 0;
    while (i < n) { store64(r + REC_A, i); store64(r + REC_B, i); i = i + 1; }
    return 0;
}
fn by_getter(r, n) {
    var s = 0;
    var i = 0;
    while (i < n) { s = s + Rec_a(r) + Rec_b(r); i = i + 1; }
    return s;
}
fn by_load(r, n) {
    var s = 0;
    var i = 0;
    while (i < n) { s = s + load64(r + REC_A) + load64(r + REC_B); i = i + 1; }
    return s;
}
fn main() {
    alloc_init(); args_init();
    var mode = atoi(argv(1));
    var r = alloc(sizeof(Rec));
    store64(r, 1); store64(r + 8, 2);
    var n = 1000000;
    if (mode == 1) { by_setter(r, n); }
    if (mode == 2) { by_store(r, n); }
    if (mode == 3) { return by_getter(r, n) & 1; }
    if (mode == 4) { return by_load(r, n) & 1; }
    return 0;
}
EOF
cyrius build acc.cyr acc > build.log 2>&1 || { cat build.log; exit 2; }
python3 - ./acc <<'EOF'
import ctypes, os, struct, sys
libc = ctypes.CDLL(None, use_errno=True)
FLAGS = (1 << 0) | (1 << 5) | (1 << 6) | (1 << 12)   # disabled, no kernel, no hv, enable on exec
def count(argv):
    attr = lambda cfg: ctypes.create_string_buffer(struct.pack("IIQQQQQ", 0, 128, cfg, 0, 0, 0, FLAGS).ljust(128, b"\0"), 128)
    go_r, go_w = os.pipe(); ready_r, ready_w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(go_w); os.close(ready_r); os.write(ready_w, b"x"); os.read(go_r, 1)
        os.execv(argv[0], argv)
    os.close(go_r); os.close(ready_w); os.read(ready_r, 1)
    fds = []
    for cfg in (1, 4):   # instructions, branch instructions
        fd = libc.syscall(298, attr(cfg), pid, -1, -1, 0)
        if fd < 0:
            sys.exit(f"perf_event_open: errno {ctypes.get_errno()} (perf_event_paranoid must be <= 2)")
        fds.append(fd)
    os.write(go_w, b"x"); os.waitpid(pid, 0)
    return [struct.unpack("Q", os.read(fd, 8))[0] for fd in fds]
b = sys.argv[1]
best = lambda m: [min(x) for x in zip(*[count([b, str(m)]) for _ in range(3)])]
base = best(0)
per = {}
for m, name in [(1, "Rec_set_a + Rec_set_b"), (2, "store64 x2"), (3, "Rec_a + Rec_b"), (4, "load64 x2")]:
    v = best(m)
    per[m] = (v[0] - base[0]) / 1e6
    print(f"{name:24s} {per[m]:6.2f} instructions, {(v[1] - base[1]) / 1e6:4.2f} branches per iteration")
sys.exit(1 if per[1] > per[2] or per[3] > per[4] else 0)
EOF
