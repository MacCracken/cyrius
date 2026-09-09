# Repro — stdlib libc-name collision (2026-09-09)

    ./run.sh              # -> sd_bus_default_system -> -107 (FAIL)
    ./run.sh localize     # -> sd_bus_default_system -> 0 (ok)

The only difference is `objcopy -L memchr app.o`.

Cyrius's `memchr` (lib/string.cyr:76) returns an OFFSET or -1; C's returns a POINTER or NULL.
libsystemd calls the Cyrius one because `object;` mode exports it as a global `T` symbol.

Localizing any single OTHER symbol (memcpy, memset, strlen, strchr, strstr, atoi) instead makes
the binary HANG rather than fail fast — a partial fix looks like a different bug.
