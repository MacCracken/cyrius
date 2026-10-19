# patra: `patra_insert_row` accepts a NEGATIVE BYTES / TEXT length with `PATRA_OK` and stores it raw; since 1.16.5 that cell reads `PATRA_ERR_PAGE` while `patra_result_get_bytes_len` / `_get_text_len` answer the raw negative value (-5), not the -1 a ref longer than the file answers — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 libfix3 lane (unit L5, the patra 1.16.5 fold patch for
issues/archived/2026-10-18-patra-oversized-bytes-ref-reads-as-empty-value.md) on patra `5d2a9da` (before) and `9c67b33` (after:
L5's commits `306871e` + `9c67b33` in ~/Repos/patra), built by the libfix3 worktree's `build/cycc` with its `lib/`
(x86_64 Linux; the crafted-file route also on pi). The insert route was found by the lane's review and re-measured by
its fix step (BYTES and TEXT).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 libfix3 lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6 — a fold defect: its fold patch opens 6.7.16) — never 7.x. A fold defect: the
fix is a patra patch (fix the source repo, then re-vendor).
**Severity:** Low — reachable through patra's PUBLIC write API, not only a malformed file: `patra_insert_row` (and
`patra_insert_row_or_ignore`, the same impl) takes a negative `blens[i]` for a BYTES / TEXT column, answers `PATRA_OK`
and stores the negative length; a crafted or corrupted `.patra` file reaches the same cell. The cell's length getter
then answers an undocumented negative value, and since 1.16.5 its read answers `PATRA_ERR_PAGE` where it answered
`PATRA_OK` (an empty value) — so 1.16.5 changes the read of API-written data, which the 1.16.5 cyrius migration note
names. No memory-safety impact (nothing is allocated or copied for a negative length). Not a security issue (no
boundary crossed: the developer's own calls and database file).
**Found:** while fixing the oversized-ref issue: its user decision (6.7.15's, 2026-10-18) covers a stored length that
EXCEEDS what the file can hold (`len > HDR_PGCOUNT * BY_DATA_MAX`, 1.14.0's bound in `_rs_materialize`); a negative
stored length is below that bound, so it is outside the filed surface — filed, not fixed. The lane first framed it as
a crafted-file shape only; the review showed the public insert stores it too.

## Reproduction

### 1. Through the public API — no file editing

A one-row `t (hash STR, content BYTES)` inserted by `patra_insert_row` with `blens[1] = -5`, then `SELECT *`, the
getter and the read (compiled from a patra checkout's root, `cat neg_api.cyr | cycc > neg_api`, `lib/` = the stdlib):

```
# a BYTES cell inserted through the public API with a negative length
include "src/lib.cyr"
include "tests/scratch_path.cyr"
alloc_init();
fl_init();
patra_init();
var fpath = _scr("/tmp/patra_rev_negapi.patra");
xunlink(fpath);
var db = patra_open(fpath);
patra_exec(db, "CREATE TABLE t (hash STR, content BYTES)");
var pl = fl_alloc(16);
memset(pl, 65, 16);
var a = fl_alloc(96);
memset(a, 0, 96);
store64(a + 0, COL_STR); store64(a + 8, COL_BYTES);
store64(a + 32, "h"); store64(a + 48, 1);
store64(a + 72, pl); store64(a + 88, 0 - 5);
var ir = patra_insert_row(db, "t", 1, 2, a, a + 16, a + 32, a + 48, a + 64, a + 80);
var rs = patra_query(db, "SELECT * FROM t");
eprint("insert=", 7); efmt_int(ir);
eprint(" rs_nonzero=", 12); efmt_int(rs != 0);
eprint(" len=", 5); efmt_int(patra_result_get_bytes_len(rs, 0, 1));
var out = fl_alloc(16);
eprint(" read_bytes=", 12); efmt_int(patra_result_read_bytes(db, rs, 0, 1, out));
eprint("\n", 1);
patra_result_free(rs);
patra_close(db);
xunlink(fpath);
sys_exit(0);
```

Measured (x86_64 Linux):

| patra | BYTES (as above) | TEXT (`content TEXT`, `COL_TEXT`, `_get_text_len`, `_read_text`) |
|---|---|---|
| `5d2a9da` (before L5) | `insert=0 rs_nonzero=1 len=-5 read_bytes=0` | `insert=0 rs_nonzero=1 len=-5 read_text=0` |
| `9c67b33` (1.16.5 final) | `insert=0 rs_nonzero=1 len=-5 read_bytes=7` | `insert=0 rs_nonzero=1 len=-5 read_text=7` |

The insert answers `PATRA_OK` (0) on both; the read moves `PATRA_OK` → `PATRA_ERR_PAGE` (7); the getter answers the
raw -5 on both.

### 2. Through a crafted file

The oversized-ref issue's probe with the row's `BR_LEN` rewritten to -5 instead of 1,000,000,000 (compiled from a
patra checkout's root, `cat neglen.cyr | cycc > neglen`, `lib/` = the stdlib):

```
# a row whose BYTES ref names a negative length
include "src/lib.cyr"
include "tests/scratch_path.cyr"
alloc_init();
fl_init();
patra_init();
var fpath = _scr("/tmp/patra_l5_neglen.patra");
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
# the row's BR_LEN: 5000 -> -5
var fd = _pt_file_open(fpath);
var hdr = pg_alloc();
var buf = pg_alloc();
patra_hdr_read(fd, hdr);
var root = load64(_tbl_entry(hdr, 0) + TBL_ROOT);
page_read_checked(fd, hdr, root, buf);
row_write_bytes_ref(buf + DP_DATA, COL_STR_SZ, row_read_bytes_page(buf + DP_DATA, COL_STR_SZ), 0 - 5);
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

Measured (x86_64 Linux):

| patra | output |
|---|---|
| `5d2a9da` (1.16.5 before L5) | `rs_nonzero=1 len=-5 read_bytes=0` — the raw length, and the read `PATRA_OK` with nothing written |
| after L5 | `rs_nonzero=1 len=-5 read_bytes=7` — the read now `PATRA_ERR_PAGE` (below), the length still the raw -5 |

The same for a TEXT cell (`patra_result_get_text_len` -5; `patra_result_read_text` 0 before, 7 after), and for -1 (which
after L5 is indistinguishable from the decided answer: length -1, `PATRA_ERR_PAGE`).


## Root cause

Two halves, one class:

- **The write accepts it.** `_patra_insert_row_impl` (patra src/lib.cyr ~3966-3979, the BYTES / TEXT arm):
  `var bl = load64(blens + j * 8); var head = _bytes_write_chain(fd, hdr, bp, bl);` — `_bytes_write_chain` writes
  nothing and answers 0 for `len <= 0`, the `if (bl > 0) { if (head == 0) … PATRA_ERR_IO }` check is skipped for a
  negative `bl`, and `row_write_bytes_ref(row, off, head, bl)` stores the negative length. `patra_insert_row`'s doc
  comment names `blens[i]` "binary buffer + length; empty if 0" and its returns `PATRA_OK`, `PATRA_ERR_NOTFOUND`,
  `PATRA_ERR_COLCOUNT`, `PATRA_ERR_TYPE` — a negative length is undocumented. (The SQL INSERT path, ~927, takes a
  parsed TEXT literal's length, which is never negative.)
- **The read answers it raw.** `_rs_materialize` bounds a ref's length only from above (`len > maxlen`, 1.14.0); a
  negative `len` takes the empty path (`BR_PAGE = 0`) and keeps its `BR_LEN`, so the getters return the stored
  negative value — their doc comments name -1 (wrong column / outside the result set / since 1.16.5 a ref longer than
  the file), never another negative. The reads: L5 gave a malformed chain and a ref longer than the file one answer
  path (`blen == 0` is the only empty value; a cell with no snapshot answers `PATRA_ERR_PAGE`), and since a negative
  length has no snapshot either, its read moved from `PATRA_OK` to `PATRA_ERR_PAGE` with it — the -1 marker cannot be
  told apart from a stored -1, so the read answers every negative length alike.

## Fix direction

Not decided here (the class is the user's call), two questions:

1. Does `patra_insert_row` (and `_or_ignore`) refuse a negative BYTES / TEXT length — `PATRA_ERR_PARAM` (11, already
   patra's answer for a bad statement parameter), before any chain is written, the row not inserted — or keep
   storing it?
2. Does the read side answer -1 from the getters for EVERY negative stored length (bound `len < 0` beside
   `len > maxlen` in `_rs_materialize`, so a crafted / pre-1.16.5 negative cell reads like the decided oversized ref),
   or keep the raw negative (which a caller checking `< 0` already treats as no length)?

Rows: reproduction 1 (BYTES and TEXT; the insert's answer, then the getter and the read) and reproduction 2 beside
`test_oversized_ref_read_refused` in patra's `tests/tcyr/patra.tcyr`. patra's CHANGELOG [1.16.5] *Found* and roadmap
*Deferred* entries describe only the getter side; the fixing patch names the insert route there.
