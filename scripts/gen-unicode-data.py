#!/usr/bin/env python3
# scripts/gen-unicode-data.py — build-time codegen for lib/unicode/* data tables.
#
# This is a one-shot generator that runs offline to refresh the Unicode tables
# baked into lib/unicode/. Its output (lib/unicode/_categories_data.cyr) is
# committed to the repo — users do NOT need to run this script. Re-run only
# when bumping to a new Unicode revision (current target: 17.0.0, released
# 2025-09-09).
#
# Why Python: this is a one-shot codegen tool, not part of the cyrius runtime
# or self-hosting chain. The cyrius project ethos ("own the toolchain") applies
# to the runtime + compiler — UCD parsing is offline build-machinery, the same
# category as the bash scripts in scripts/. A native cyrius UCD parser is not
# blocked by this script and could land in a later cycle if desired.
#
# Usage:
#   python3 scripts/gen-unicode-data.py
#
# Outputs:
#   lib/unicode/_categories_data.cyr — packed hex-pair encoded GeneralCategory
#   range table + range count + category-name table.
#
# Encoding format (per range, 14 ASCII hex chars):
#   bytes 0..2  start codepoint  (u24, big-endian — high byte first)
#   bytes 3..5  end   codepoint  (u24, big-endian, INCLUSIVE)
#   byte  6     general-category index (see GC_* enum in categories.cyr)
#
# Hex-pair encoding chosen because cyrius has no precedent for binary string
# literals (embedded NUL / high bytes); printable ASCII is lexer-safe and
# round-trips through `cyrius fmt` cleanly. Each byte costs 2 chars, so the
# blob is ~2x raw. For Unicode 17.0 GeneralCategory (~3500 ranges merged) the
# expanded form is ~50KB — comfortably below cc5's 8 MiB tok_values cap.

import re
import sys
import urllib.request

URL = "https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt"
URL_CASEFOLDING = "https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt"
URL_UNICODEDATA = "https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt"
URL_COMPEXCL = "https://www.unicode.org/Public/17.0.0/ucd/CompositionExclusions.txt"

# Order matches GeneralCategory enum in lib/unicode/categories.cyr.
# Index = enum value. 30 categories total per Unicode standard.
CAT_ORDER = [
    "Lu", "Ll", "Lt", "Lm", "Lo",        # Letter
    "Mn", "Mc", "Me",                    # Mark
    "Nd", "Nl", "No",                    # Number
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",   # Punctuation
    "Sm", "Sc", "Sk", "So",              # Symbol
    "Zs", "Zl", "Zp",                    # Separator
    "Cc", "Cf", "Cs", "Co", "Cn",        # Other
]
CAT_IDX = {c: i for i, c in enumerate(CAT_ORDER)}


def fetch():
    print(f"fetching {URL}", file=sys.stderr)
    with urllib.request.urlopen(URL, timeout=30) as resp:
        return resp.read().decode("utf-8")


def parse(text):
    """Parse DerivedGeneralCategory.txt lines.

    Format examples:
        0030..0039    ; Nd # Nd  [10] DIGIT ZERO..DIGIT NINE
        0041..005A    ; Lu # L&  [26] LATIN CAPITAL LETTER A..LATIN CAPITAL LETTER Z
        00B5          ; Ll # L&       MICRO SIGN

    Skips aggregate categories (L, M, N, P, S, Z, C) — we want only the leaf
    2-char categories that map to enum entries.
    """
    rng = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        m = re.match(
            r"^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\s*;\s*(\w+)\s*$", line
        )
        if not m:
            continue
        start = int(m.group(1), 16)
        end = int(m.group(2), 16) if m.group(2) else start
        cat = m.group(3)
        if cat not in CAT_IDX:
            continue  # aggregate (L, M, N, P, S, Z, C)
        rng.append((start, end, CAT_IDX[cat]))
    rng.sort()
    # Merge adjacent ranges sharing a category.
    merged = []
    for s, e, c in rng:
        if merged and merged[-1][1] + 1 == s and merged[-1][2] == c:
            merged[-1] = (merged[-1][0], e, c)
        else:
            merged.append([s, e, c])
    return merged


def emit_packed_hex(ranges):
    """Emit one big string: 14 hex chars per range, all concatenated.

    Returns (hex_blob, count).
    """
    chunks = []
    for s, e, c in ranges:
        if s > 0xFFFFFF or e > 0xFFFFFF:
            raise ValueError(f"codepoint > 24 bits: {s:x}..{e:x}")
        if c < 0 or c > 0xFF:
            raise ValueError(f"category index out of byte range: {c}")
        chunks.append(f"{s:06x}{e:06x}{c:02x}")
    return "".join(chunks), len(ranges)


def emit_cyrius_source(blob, count, category_text_count, source_url):
    """Emit lib/unicode/_categories_data.cyr."""
    # Chunk on a clean range boundary (each range is 14 hex chars) so the
    # cyrius-side dispatch can compute (piece_idx, offset_in_piece) from a
    # flat range index without crossing piece edges. 500 ranges per piece =
    # 7000 hex chars; safely under cc5's per-literal limits.
    RANGES_PER_PIECE = 500
    CHARS_PER_RANGE = 14
    CHUNK = RANGES_PER_PIECE * CHARS_PER_RANGE
    pieces = [blob[i : i + CHUNK] for i in range(0, len(blob), CHUNK)]

    out = []
    out.append("# lib/unicode/_categories_data.cyr — AUTO-GENERATED by")
    out.append("# `scripts/gen-unicode-data.py`. Do NOT edit by hand; the next")
    out.append("# regeneration will overwrite. Source of truth:")
    out.append(f"#   {source_url}")
    out.append(f"# Unicode 17.0.0 ({count} merged ranges; {category_text_count}")
    out.append("# total leaf categories). Encoding: 14 hex chars per range —")
    out.append("# 6 chars u24 start + 6 chars u24 end (inclusive) + 2 chars cat")
    out.append("# index. The category index aligns with the GeneralCategory")
    out.append("# enum in lib/unicode/categories.cyr (Lu=0, Ll=1, ..., Cn=29).")
    out.append("# Public surface lives in categories.cyr; this file is data.")
    out.append("")
    out.append(f"var _UNICODE_CAT_RANGE_COUNT = {count};")
    out.append(f"var _UNICODE_CAT_PIECE_COUNT = {len(pieces)};")
    out.append(f"var _UNICODE_CAT_RANGES_PER_PIECE = 500;")
    out.append("")
    for i, piece in enumerate(pieces):
        out.append(f'var _UNICODE_CAT_PIECE_{i} = "{piece}";')
    return "\n".join(out) + "\n"


# ── Case folding (v5.8.50) ────────────────────────────────────────────

def fetch_url(url):
    print(f"fetching {url}", file=sys.stderr)
    with urllib.request.urlopen(url, timeout=30) as resp:
        return resp.read().decode("utf-8")


def parse_simple_case(text):
    """Parse UnicodeData.txt → (uppercase_map, lowercase_map, titlecase_map).

    Each map is dict[cp, cp] for codepoints with a defined simple mapping.
    Codepoints whose mapping is empty (themselves) are NOT in the map —
    consumer-side `unicode_to_lower(cp)` returns cp unchanged on lookup
    miss.

    UnicodeData.txt fields (semicolon-separated, 0-indexed):
        0  codepoint
        12 simple uppercase mapping
        13 simple lowercase mapping
        14 simple titlecase mapping
    """
    upper = {}
    lower = {}
    title = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split(";")
        if len(f) < 15:
            continue
        try:
            cp = int(f[0], 16)
        except ValueError:
            continue
        if f[12]:
            upper[cp] = int(f[12], 16)
        if f[13]:
            lower[cp] = int(f[13], 16)
        if f[14]:
            title[cp] = int(f[14], 16)
    return upper, lower, title


def parse_full_fold(text):
    """Parse CaseFolding.txt → dict[cp, list[cp]].

    Includes 'C' (common, 1:1) and 'F' (full, 1:n) status entries; skips
    'S' (simple alt, redundant when F is present) and 'T' (Turkish-locale
    only — not applicable to general fold). All resulting lists have
    1, 2, or 3 codepoints.
    """
    fold = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        # Strip trailing comment
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        f = [x.strip() for x in line.split(";")]
        if len(f) < 3:
            continue
        cp_str, status, mapping = f[0], f[1], f[2]
        if status not in ("C", "F"):
            continue
        try:
            cp = int(cp_str, 16)
        except ValueError:
            continue
        cps = [int(x, 16) for x in mapping.split()]
        fold[cp] = cps
    return fold


def emit_simple_table(mapping, label):
    """Encode a simple 1:1 case map as 12 hex chars per record:
    src(u24 BE, 6 chars) + dst(u24 BE, 6 chars). Sorted by src.

    Returns (hex_blob, count).
    """
    parts = []
    for src in sorted(mapping):
        dst = mapping[src]
        if src > 0xFFFFFF or dst > 0xFFFFFF:
            raise ValueError(f"{label}: cp > 24 bits {src:x}→{dst:x}")
        parts.append(f"{src:06x}{dst:06x}")
    return "".join(parts), len(mapping)


def emit_full_fold_table(fold):
    """Encode the full case fold as 26 hex chars per record:
    src(u24 BE, 6) + count(u8, 2) + cp1(u24 BE, 6) + cp2(u24 BE, 6) +
    cp3(u24 BE, 6). cp2 / cp3 are 0 when count < 3 / 2. Sorted by src.

    Returns (hex_blob, count).
    """
    parts = []
    for src in sorted(fold):
        cps = fold[src]
        n = len(cps)
        if n < 1 or n > 3:
            raise ValueError(f"full fold expansion not in [1,3]: {src:x} → {cps}")
        c1 = cps[0]
        c2 = cps[1] if n >= 2 else 0
        c3 = cps[2] if n >= 3 else 0
        for v in (src, c1, c2, c3):
            if v > 0xFFFFFF:
                raise ValueError(f"cp > 24 bits in full fold: {v:x}")
        parts.append(f"{src:06x}{n:02x}{c1:06x}{c2:06x}{c3:06x}")
    return "".join(parts), len(fold)


def emit_casefold_source(
    upper_blob, upper_count,
    lower_blob, lower_count,
    title_blob, title_count,
    fold_blob, fold_count,
    sources,
):
    """Emit lib/unicode/_casefold_data.cyr.

    Three simple tables (upper / lower / title) — 12 hex chars per record,
    chunked at 500 records (6000 chars/piece). One full-fold table —
    26 hex chars per record, chunked at 250 records (6500 chars/piece).
    """
    SIMPLE_PER_PIECE = 500
    SIMPLE_CHARS_PER_REC = 12
    FULL_PER_PIECE = 250
    FULL_CHARS_PER_REC = 26

    def chunk(blob, chars_per_rec, rec_per_piece):
        chunk_size = chars_per_rec * rec_per_piece
        return [blob[i : i + chunk_size] for i in range(0, len(blob), chunk_size)]

    upper_pieces = chunk(upper_blob, SIMPLE_CHARS_PER_REC, SIMPLE_PER_PIECE)
    lower_pieces = chunk(lower_blob, SIMPLE_CHARS_PER_REC, SIMPLE_PER_PIECE)
    title_pieces = chunk(title_blob, SIMPLE_CHARS_PER_REC, SIMPLE_PER_PIECE)
    fold_pieces = chunk(fold_blob, FULL_CHARS_PER_REC, FULL_PER_PIECE)

    out = []
    out.append("# lib/unicode/_casefold_data.cyr — AUTO-GENERATED by")
    out.append("# `scripts/gen-unicode-data.py`. Do NOT edit by hand; the next")
    out.append("# regeneration will overwrite. Sources of truth:")
    for s in sources:
        out.append(f"#   {s}")
    out.append("# Unicode 17.0.0. Four tables:")
    out.append("#   simple uppercase: 12 hex chars/rec (src u24 + dst u24)")
    out.append("#   simple lowercase: same")
    out.append("#   simple titlecase: same")
    out.append("#   full case fold:   26 hex chars/rec (src u24 + count u8 +")
    out.append("#                                       cp1/cp2/cp3 each u24)")
    out.append("# All tables sorted by src cp; consumer-side does binary search.")
    out.append("# Public surface lives in casefold.cyr; this file is data.")
    out.append("")
    out.append(f"var _UNICODE_UPPER_RECORD_COUNT = {upper_count};")
    out.append(f"var _UNICODE_UPPER_PIECE_COUNT = {len(upper_pieces)};")
    out.append(f"var _UNICODE_UPPER_RECORDS_PER_PIECE = {SIMPLE_PER_PIECE};")
    out.append("")
    for i, piece in enumerate(upper_pieces):
        out.append(f'var _UNICODE_UPPER_PIECE_{i} = "{piece}";')
    out.append("")
    out.append(f"var _UNICODE_LOWER_RECORD_COUNT = {lower_count};")
    out.append(f"var _UNICODE_LOWER_PIECE_COUNT = {len(lower_pieces)};")
    out.append(f"var _UNICODE_LOWER_RECORDS_PER_PIECE = {SIMPLE_PER_PIECE};")
    out.append("")
    for i, piece in enumerate(lower_pieces):
        out.append(f'var _UNICODE_LOWER_PIECE_{i} = "{piece}";')
    out.append("")
    out.append(f"var _UNICODE_TITLE_RECORD_COUNT = {title_count};")
    out.append(f"var _UNICODE_TITLE_PIECE_COUNT = {len(title_pieces)};")
    out.append(f"var _UNICODE_TITLE_RECORDS_PER_PIECE = {SIMPLE_PER_PIECE};")
    out.append("")
    for i, piece in enumerate(title_pieces):
        out.append(f'var _UNICODE_TITLE_PIECE_{i} = "{piece}";')
    out.append("")
    out.append(f"var _UNICODE_FOLD_RECORD_COUNT = {fold_count};")
    out.append(f"var _UNICODE_FOLD_PIECE_COUNT = {len(fold_pieces)};")
    out.append(f"var _UNICODE_FOLD_RECORDS_PER_PIECE = {FULL_PER_PIECE};")
    out.append("")
    for i, piece in enumerate(fold_pieces):
        out.append(f'var _UNICODE_FOLD_PIECE_{i} = "{piece}";')
    return "\n".join(out) + "\n"


# ── Normalization (v5.8.51) ───────────────────────────────────────────

def parse_normalize(ud_text, ce_text):
    """Parse UnicodeData.txt + CompositionExclusions.txt → normalization tables.

    Returns (ccc, canonical_decomp, compat_only_decomp, composition):
      ccc: dict[cp, ccc_byte]   — non-zero CCC only (most are 0; lookup
                                  miss returns 0).
      canonical_decomp: dict[cp, list[cp]] (length ≤ 2) — canonical
                                  decomposition only (no compat tag).
                                  Used by NFD/NFC.
      compat_only_decomp: dict[cp, list[cp]] (length 1..18) —
                                  decompositions with a compat tag
                                  (<font>, <wide>, <super>, etc.).
                                  Disjoint from canonical_decomp. Used
                                  by NFKD/NFKC IN ADDITION to canonical.
      composition: dict[(cp1, cp2), cp] — reverse of canonical_decomp,
                                  filtered by composition exclusions
                                  + non-starter constraints. NFC/NFKC
                                  use this to recombine after decomp +
                                  reorder.

    Hangul (S = LV / LVT) is handled algorithmically in normalize.cyr;
    UnicodeData.txt does not list its decomposition (would be redundant).

    UnicodeData.txt fields (semicolon-separated):
        0  codepoint
        3  canonical combining class
        5  decomposition: empty | "<tag> CPS" | "CPS"
    """
    ccc = {}
    canon = {}
    compat_only = {}
    for line in ud_text.splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split(";")
        if len(f) < 6:
            continue
        try:
            cp = int(f[0], 16)
        except ValueError:
            continue
        # CCC (field 3)
        try:
            c = int(f[3])
        except ValueError:
            c = 0
        if c != 0:
            ccc[cp] = c
        # Decomposition (field 5)
        d = f[5].strip()
        if not d:
            continue
        parts = d.split()
        if parts[0].startswith("<"):
            # Compat decomp — strip tag, parse remaining cps
            tag = parts[0]
            cps = [int(x, 16) for x in parts[1:]]
            compat_only[cp] = cps
        else:
            cps = [int(x, 16) for x in parts]
            if len(cps) > 2:
                raise ValueError(f"canonical decomp > 2 cps at {cp:x}: {cps}")
            canon[cp] = cps

    # Composition exclusions: codepoints whose canonical decomp must NOT
    # be re-composed during NFC. Read from CompositionExclusions.txt.
    excl = set()
    for line in ce_text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        # Lines are single codepoints in hex (the file lists single cps,
        # not ranges).
        try:
            excl.add(int(line, 16))
        except ValueError:
            continue

    # Build composition table: (cp1, cp2) → cp from canonical decomps
    # of length 2, filtered by:
    #   1. cp not in CompositionExclusions
    #   2. cp1's CCC is 0 (cp1 is a starter)
    # Single-cp canonical decomps (rare — singleton decompositions like
    # 0x2126 OHM SIGN → 0x03A9 GREEK CAPITAL OMEGA) cannot recompose.
    composition = {}
    for cp, cps in canon.items():
        if cp in excl:
            continue
        if len(cps) != 2:
            continue
        cp1, cp2 = cps
        if ccc.get(cp1, 0) != 0:
            continue   # cp1 is a non-starter; can't act as composition base
        composition[(cp1, cp2)] = cp

    return ccc, canon, compat_only, composition


def emit_ccc_table(ccc):
    """Encode CCC: each record 8 hex chars = cp(u24, 6) + ccc(u8, 2).
    Sorted by cp.
    """
    parts = []
    for cp in sorted(ccc):
        c = ccc[cp]
        if cp > 0xFFFFFF or c > 0xFF:
            raise ValueError(f"CCC out-of-range: {cp:x} → {c}")
        parts.append(f"{cp:06x}{c:02x}")
    return "".join(parts), len(ccc)


def emit_canonical_decomp(canon):
    """Encode canonical decomp: each record 20 hex chars =
    cp(u24, 6) + count(u8, 2) + cp1(u24, 6) + cp2(u24, 6).
    cp2 = 0 when count = 1. Sorted by cp.
    """
    parts = []
    for cp in sorted(canon):
        cps = canon[cp]
        n = len(cps)
        c1 = cps[0]
        c2 = cps[1] if n >= 2 else 0
        for v in (cp, c1, c2):
            if v > 0xFFFFFF:
                raise ValueError(f"canon decomp cp > 24 bits: {v:x}")
        parts.append(f"{cp:06x}{n:02x}{c1:06x}{c2:06x}")
    return "".join(parts), len(canon)


def emit_compat_decomp(compat):
    """Encode compat-only decomp: each record 116 hex chars =
    cp(u24, 6) + count(u8, 2) + 18 × cp(u24, 6).
    Trailing slots are 0 when count < 18. Sorted by cp.
    """
    parts = []
    for cp in sorted(compat):
        cps = compat[cp]
        n = len(cps)
        if n < 1 or n > 18:
            raise ValueError(f"compat decomp count out of [1,18]: {cp:x} → {cps}")
        # Pad to exactly 18 slots
        padded = cps + [0] * (18 - n)
        rec = f"{cp:06x}{n:02x}"
        for v in padded:
            if v > 0xFFFFFF:
                raise ValueError(f"compat decomp cp > 24 bits: {v:x}")
            rec += f"{v:06x}"
        parts.append(rec)
    return "".join(parts), len(compat)


def emit_composition_table(composition):
    """Encode composition: each record 18 hex chars =
    cp1(u24, 6) + cp2(u24, 6) + cp_composed(u24, 6).
    Sorted by (cp1, cp2) — composition lookup uses 2-key binary search
    treating cp1 as primary, cp2 as secondary.
    """
    parts = []
    for (cp1, cp2) in sorted(composition):
        cp = composition[(cp1, cp2)]
        for v in (cp1, cp2, cp):
            if v > 0xFFFFFF:
                raise ValueError(f"compose cp > 24 bits: {v:x}")
        parts.append(f"{cp1:06x}{cp2:06x}{cp:06x}")
    return "".join(parts), len(composition)


def emit_normalize_source(
    ccc_blob, ccc_count,
    canon_blob, canon_count,
    compose_blob, compose_count,
    sources,
):
    """Emit lib/unicode/_normalize_data.cyr.

    v5.8.51: NFC + NFD only. The compat-only decomposition table
    (~445 KB hex, used for NFKC/NFKD) is parsed by gen-unicode-data.py
    but NOT emitted here — it overflows cc5's 256 KB str_data heap
    region. Bumping that cap is a compiler change scoped to a later
    slot (two-step heap bootstrap per CLAUDE.md).
    """
    CCC_PER_PIECE = 800
    CANON_PER_PIECE = 350
    COMPOSE_PER_PIECE = 380

    def chunk(blob, chars_per_rec, rec_per_piece):
        chunk_size = chars_per_rec * rec_per_piece
        return [blob[i : i + chunk_size] for i in range(0, len(blob), chunk_size)]

    ccc_pieces = chunk(ccc_blob, 8, CCC_PER_PIECE)
    canon_pieces = chunk(canon_blob, 20, CANON_PER_PIECE)
    compose_pieces = chunk(compose_blob, 18, COMPOSE_PER_PIECE)

    out = []
    out.append("# lib/unicode/_normalize_data.cyr — AUTO-GENERATED by")
    out.append("# `scripts/gen-unicode-data.py`. Do NOT edit by hand; the next")
    out.append("# regeneration will overwrite. Sources of truth:")
    for s in sources:
        out.append(f"#   {s}")
    out.append("# Unicode 17.0.0. THREE tables for NFC + NFD normalization:")
    out.append("#   CCC (canonical combining class): 8 hex chars/rec")
    out.append("#                                    (cp u24 + ccc u8).")
    out.append("#   canonical decomp: 20 hex chars/rec (cp u24 + count u8 +")
    out.append("#                     cp1/cp2 each u24).")
    out.append("#   composition: 18 hex chars/rec (cp1 u24 + cp2 u24 +")
    out.append("#                cp_composed u24). Sorted by (cp1, cp2).")
    out.append("# Hangul L+V[+T] composition is algorithmic — no table.")
    out.append("# NFKC/NFKD compat-only decomp NOT shipped at v5.8.51")
    out.append("# (overflows cc5's 256 KB str_data cap; deferred until")
    out.append("# the cap is bumped in a later slot).")
    out.append("# Public surface lives in normalize.cyr; this file is data.")
    out.append("")

    def emit_table(label, pieces, count, per_piece):
        out.append(f"var _UNICODE_{label}_RECORD_COUNT = {count};")
        out.append(f"var _UNICODE_{label}_PIECE_COUNT = {len(pieces)};")
        out.append(f"var _UNICODE_{label}_RECORDS_PER_PIECE = {per_piece};")
        out.append("")
        for i, p in enumerate(pieces):
            out.append(f'var _UNICODE_{label}_PIECE_{i} = "{p}";')
        out.append("")

    emit_table("CCC", ccc_pieces, ccc_count, CCC_PER_PIECE)
    emit_table("CANON", canon_pieces, canon_count, CANON_PER_PIECE)
    emit_table("COMPOSE", compose_pieces, compose_count, COMPOSE_PER_PIECE)

    return "\n".join(out) + "\n"


def main():
    # Categories (v5.8.49)
    cat_text = fetch()
    ranges = parse(cat_text)
    blob, count = emit_packed_hex(ranges)
    print(f"categories: merged {count} ranges; blob = {len(blob)} hex chars", file=sys.stderr)
    cat_path = "lib/unicode/_categories_data.cyr"
    cat_src = emit_cyrius_source(blob, count, len(CAT_ORDER), URL)
    with open(cat_path, "w") as f:
        f.write(cat_src)
    print(f"wrote {cat_path}", file=sys.stderr)

    # Case folding (v5.8.50)
    ud_text = fetch_url(URL_UNICODEDATA)
    cf_text = fetch_url(URL_CASEFOLDING)
    upper, lower, title = parse_simple_case(ud_text)
    fold = parse_full_fold(cf_text)
    upper_blob, upper_n = emit_simple_table(upper, "upper")
    lower_blob, lower_n = emit_simple_table(lower, "lower")
    title_blob, title_n = emit_simple_table(title, "title")
    fold_blob, fold_n = emit_full_fold_table(fold)
    print(
        f"casefold: upper={upper_n} lower={lower_n} title={title_n} fold={fold_n}",
        file=sys.stderr,
    )
    cf_path = "lib/unicode/_casefold_data.cyr"
    cf_src = emit_casefold_source(
        upper_blob, upper_n,
        lower_blob, lower_n,
        title_blob, title_n,
        fold_blob, fold_n,
        sources=[URL_UNICODEDATA, URL_CASEFOLDING],
    )
    with open(cf_path, "w") as f:
        f.write(cf_src)
    print(f"wrote {cf_path}", file=sys.stderr)

    # Normalization (v5.8.51) — re-uses ud_text from above.
    #
    # v5.8.51 ships NFC + NFD only. NFKC + NFKD compat-only decomp data
    # (~445 KB hex) overflows cc5's 256 KB str_data heap region; bumping
    # the cap is a compiler change requiring its own slot (two-step
    # heap-change bootstrap per CLAUDE.md). Compat-only table is
    # generated for parity with the parser but NOT emitted to the
    # cyrius source — the table dict is dropped on the floor.
    ce_text = fetch_url(URL_COMPEXCL)
    ccc_map, canon, compat_only, composition = parse_normalize(ud_text, ce_text)
    ccc_blob, ccc_n = emit_ccc_table(ccc_map)
    canon_blob, canon_n = emit_canonical_decomp(canon)
    compose_blob, compose_n = emit_composition_table(composition)
    print(
        f"normalize: ccc={ccc_n} canon={canon_n} compose={compose_n} "
        f"(compat_only={len(compat_only)} parsed but not emitted — v5.8.51 NFC/NFD only)",
        file=sys.stderr,
    )
    nz_path = "lib/unicode/_normalize_data.cyr"
    nz_src = emit_normalize_source(
        ccc_blob, ccc_n,
        canon_blob, canon_n,
        compose_blob, compose_n,
        sources=[URL_UNICODEDATA, URL_COMPEXCL],
    )
    with open(nz_path, "w") as f:
        f.write(nz_src)
    print(f"wrote {nz_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
