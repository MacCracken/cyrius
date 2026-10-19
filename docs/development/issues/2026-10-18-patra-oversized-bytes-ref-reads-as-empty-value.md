# patra: a BYTES / TEXT row ref whose length exceeds the file reads back as an empty value, `PATRA_OK` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 libfix lane (unit L2, the patra 1.16.5 fold patch for
issues/2026-10-18-patra-fuzz-bytes-plants-corruption-at-a-heap-address.md), on patra `bfd1674` (1.16.5 with that
unit's two read-path fixes) and on the 1.16.5 release commit `e36f202` alike, built by the libfix lane tree's
`build/cycc` with its `lib/`.
**Placement:** 6.7.15 — repair 5 (libfix lane, wave 3, unit L5; placed at the wave-2 integration, 2026-10-18: a fold defect is always fixed; folded into the untagged patra 1.16.5) — never 7.x. A fold defect: the fix
**Decision (user, 2026-10-18, at the 6.7.15 wave-2 integration):** `patra_result_get_bytes_len` answers -1 for such a cell (no valid length) and `patra_result_read_bytes` answers PATRA_ERR_PAGE, as a malformed chain's read does since 1.16.5.
is a patra patch (fix the source repo, then re-vendor).
**Severity:** Low — a malformed (crafted or corrupted) `.patra` file: one cell's value is answered as empty instead of
as an error. No memory-safety impact (the length is clamped before any allocation). Not a security issue (no boundary
crossed: the developer's own database file).
**Found:** in passing, while fixing the malformed-chain read path (the unit's second patra commit, `4426fb7`); outside
that issue's filed surface (its five mutations corrupt the chain's head page, not the row's ref), so filed, not fixed.

## Reproduction

A one-row table `t (hash STR, content BYTES)` holding a 5,000-byte blob (5 pages in the file); the row's on-disk
bytes-ref length (`BR_LEN`, column 1 of the data page's only row) rewritten from 5000 to 1,000,000,000, its page left
as is; reopen and read:

```
var rs = patra_query(db, "SELECT * FROM t");
patra_result_get_bytes_len(rs, 0, 1);            # 0
patra_result_read_bytes(db, rs, 0, 1, out);      # 0 (PATRA_OK), nothing written
```

Measured (x86_64 Linux): `rs_nonzero=1 len=0 read_bytes=0` on both `bfd1674` and `e36f202`. The probe, compiled from
a patra checkout's root (`cat overlen.cyr | cycc > overlen`, `lib/` = the stdlib):

```
# a row whose BYTES ref names a length past every page of the file
include "src/lib.cyr"
include "tests/scratch_path.cyr"
alloc_init();
fl_init();
patra_init();
var fpath = _scr("/tmp/patra_l2_overlen.patra");
xunlink(fpath);
var db = patra_open(fpath);
patra_exec(db, "CREATE TABLE t (hash STR, content BYTES)");
var pl = fl_alloc(5000);
memset(pl, 65, 5000);
var a = fl_alloc(96);
memset(a, 0, 96);
store64(a + 0, COL_STR); store64(a + 8, COL_BYTES);
store64(a + 32, "h"); store64(a + 48, 1);
store64(a + 72, pl); store64(a + 88, 5000);
patra_insert_row(db, "t", 1, 2, a, a + 16, a + 32, a + 48, a + 64, a + 80);
patra_close(db);
# the row's BR_LEN: 5000 -> 1,000,000,000 (the file holds 5 pages)
var fd = _pt_file_open(fpath);
var hdr = pg_alloc();
var buf = pg_alloc();
patra_hdr_read(fd, hdr);
var root = load64(_tbl_entry(hdr, 0) + TBL_ROOT);
page_read_checked(fd, hdr, root, buf);
row_write_bytes_ref(buf + DP_DATA, COL_STR_SZ, row_read_bytes_page(buf + DP_DATA, COL_STR_SZ), 1000000000);
page_write(fd, root, buf);
sys_close(fd);
db = patra_open(fpath);
var rs = patra_query(db, "SELECT * FROM t");
eprint("rs_nonzero=", 11); efmt_int(rs != 0);
eprint(" len=", 5); efmt_int(patra_result_get_bytes_len(rs, 0, 1));
var out = fl_alloc(16);
eprint(" read_bytes=", 12); efmt_int(patra_result_read_bytes(db, rs, 0, 1, out));
eprint("\n", 1);
patra_result_free(rs);
patra_close(db);
xunlink(fpath);
sys_exit(0);
```

## Root cause

`_rs_materialize` (patra src/lib.cyr, the 1.14.0 clamp): a ref whose `len` exceeds
`HDR_PGCOUNT * BY_DATA_MAX` — more than every page of the file could hold — has BOTH halves zeroed
(`BR_LEN = 0`, then `BR_PAGE = 0` on the empty path); its comment says "patra_result_read_bytes copies BR_LEN bytes
from" a null pointer, but both reads have checked `payload == 0` after `blen > 0` (answering `PATRA_ERR_PAGE`) since
1.12.8 — so the zeroed length is what makes the cell read as an empty value with `PATRA_OK` — the
shape 1.16.5 (`4426fb7`) fixed for a malformed CHAIN (that cell now keeps its length and reads `PATRA_ERR_PAGE`; the
reads' doc comments say `PATRA_ERR_PAGE` on a malformed chain). A ref longer than the file is malformed the same way.

## Fix direction

Not decided here (the answer is the user's call): the cell must not read as a valid empty value. Keeping the
huge `BR_LEN` beside `BR_PAGE = 0` makes the read `PATRA_ERR_PAGE`, but `patra_result_get_bytes_len` then hands a
caller sizing its buffer from it a length the file cannot hold; a distinct marker (e.g. a
negative length, or failing the query) avoids that. Row: the reproduction above, in `tests/tcyr/patra.tcyr` beside
`test_malformed_chain_read_refused`.
