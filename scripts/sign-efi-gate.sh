#!/bin/sh
# scripts/sign-efi-gate.sh — end-to-end UEFI Authenticode signing gate.
#
# Signs a synthetic PE32+ EFI with `cyrius sign-efi` (→ cyrsign-efi → sigil's
# authenticode_pe_sign) and verifies, INDEPENDENTLY, that the produced signature
# is what a real UEFI firmware checks: (1) the embedded Authenticode PE hash
# equals a from-scratch recompute over the signed image (skipping checksum +
# security data-dir + the cert table), and (2) the RSA signature over the
# SpcIndirectData verifies against the signer cert's public key.
#
# This is the round-trip the component KATs (sigil authenticode.tcyr) can't cover.
# openssl is used ONLY as an independent oracle (not by the signer). CHANGELOG [6.4.47].
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v openssl >/dev/null 2>&1 || { echo "  SKIP sign-efi-gate: openssl not available"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- build the signer if missing ---
if [ ! -x build/cyrsign-efi ]; then
    cyrius build programs/cyrsign-efi.cyr build/cyrsign-efi >/dev/null 2>&1 \
        || { echo "  FAIL sign-efi-gate: cyrsign-efi build failed"; exit 1; }
fi

# --- test key + cert (RSA-2048, self-signed) ---
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days 2 -nodes \
    -subj "/CN=Cyrius sign-efi gate" >/dev/null 2>&1
openssl rsa  -in "$TMP/k.pem" -outform DER -out "$TMP/key.der"  >/dev/null 2>&1
openssl x509 -in "$TMP/c.pem" -outform DER -out "$TMP/cert.der" >/dev/null 2>&1

# --- sign with the REPO-BUILT helper ---
# v6.5.4: this used to prefer `build/cyrius sign-efi`, but that verb execve's
# the helper out of `_tools_dir` (the INSTALLED ~/.cyrius/bin/cyrsign-efi) —
# so the gate graded whatever was last installed and ignored the
# build/cyrsign-efi it had just built two lines up. That made it blind in both
# directions: green on a stale-but-good install over a broken tree, and red on
# a stale-bad install over a fixed tree (which is how it surfaced — the sigil
# 3.12.2 fold fixed the signer while the installed helper still had 3.12.1).
# Gate the repo build; the CLI verb's own dispatch is covered separately.
SIGNER="build/cyrsign-efi"

# One end-to-end case at a given image size. Run for an 8-ALIGNED and an
# UNALIGNED image: Authenticode hashes the image up to the START OF THE CERT
# TABLE, which is `(pe_len + 7) & ~7` — so for any pe_len not a multiple of 8
# the hash MUST cover the alignment pad the signer writes. sigil <= 3.12.1
# hashed only pe[0, pe_len), producing a structurally valid signature over a
# byte range no spec verifier checks (firmware would reject the image).
# Until 6.5.4 this gate used a single 512-byte fixture — 8-aligned, so the pad
# was empty and the gate was VACUOUS against exactly that defect. See sigil
# CHANGELOG [3.12.2] + CHANGELOG [6.5.4].
run_case() {
    SIZE=$1
    LABEL=$2

    # --- synthetic PE32+ EFI fixture (mirrors sigil authenticode.tcyr's shape) ---
    python3 - "$TMP/test.efi" "$SIZE" <<'PY'
import sys, struct
pe = bytearray(i & 0xFF for i in range(int(sys.argv[2])))
pe[0x3c:0x40] = struct.pack("<I", 0x40)        # e_lfanew
pe[0x40:0x44] = b"PE\x00\x00"
pe[0x58:0x5a] = struct.pack("<H", 0x20b)        # PE32+ magic (opt = lfanew+24 = 0x58)
pe[0xE8:0xF0] = b"\x00"*8                        # Security data-dir entry (secdir = opt+144) = 0
open(sys.argv[1], "wb").write(pe)
PY

    $SIGNER "$TMP/test.efi" "$TMP/key.der" "$TMP/cert.der" "$TMP/signed.efi" >/dev/null 2>&1 \
        || { echo "  FAIL sign-efi-gate[$LABEL]: signing failed"; exit 1; }

    # --- independent verification: PE-hash arithmetic + RSA signature ---
    python3 - "$TMP/signed.efi" "$TMP/cert.der" "$TMP" "$LABEL" <<'PY'
import sys, struct, hashlib, subprocess
sig, certd, tmp, label = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = open(sig, "rb").read()
lfanew = struct.unpack("<I", d[0x3c:0x40])[0]; opt = lfanew + 24
magic = struct.unpack("<H", d[opt:opt+2])[0]; cksum = opt + 64
ddir = opt + (96 if magic == 0x10b else 112); secdir = ddir + 4*8
off, size = struct.unpack("<II", d[secdir:secdir+8])
if off == 0 or size == 0:
    print(f"  FAIL sign-efi-gate[{label}]: Security data-dir not set"); sys.exit(1)
# (1) recompute Authenticode PE hash over the signed image
h = hashlib.sha256(); h.update(d[0:cksum]); h.update(d[cksum+4:secdir]); h.update(d[secdir+8:off])
recomputed = h.hexdigest()
dwlen = struct.unpack("<I", d[off:off+4])[0]
pkcs7 = d[off+8:off+dwlen]; open(f"{tmp}/p7.der", "wb").write(pkcs7)
# the recomputed hash must appear verbatim in the signature (the embedded DigestInfo)
if bytes.fromhex(recomputed) not in pkcs7:
    print(f"  FAIL sign-efi-gate[{label}]: recomputed PE hash {recomputed} not embedded in the signature"); sys.exit(1)
# extract the SpcIndirectData (content signed) via asn1parse: SEQUENCE after the SPC OID
ap = subprocess.run(["openssl", "asn1parse", "-inform", "DER", "-in", f"{tmp}/p7.der"], capture_output=True, text=True).stdout
lines = [l for l in ap.splitlines() if l.strip()]
spc = None
for n, l in enumerate(lines):
    if "1.3.6.1.4.1.311.2.1.4" in l:
        for m2 in range(n+1, len(lines)):
            if "cons:" in lines[m2] and "SEQUENCE" in lines[m2]:
                soff = int(lines[m2].split(":")[0].strip())
                spc = pkcs7[soff:soff+2+pkcs7[soff+1]]; break
        break
if spc is None:
    print(f"  FAIL sign-efi-gate[{label}]: SpcIndirectData not found"); sys.exit(1)
# (2) RSA signature: verifyrecover the 256-byte encryptedDigest, compare to SHA-256(SpcIndirectData)
k = pkcs7.find(bytes([0x04, 0x82, 0x01, 0x00]))
if k < 0: print(f"  FAIL sign-efi-gate[{label}]: encryptedDigest not found"); sys.exit(1)
open(f"{tmp}/sig.bin", "wb").write(pkcs7[k+4:k+4+256])
subprocess.run(["openssl", "x509", "-inform", "DER", "-in", certd, "-out", f"{tmp}/c.pem"], check=True)
rec = subprocess.run(["openssl", "pkeyutl", "-verifyrecover", "-certin", "-inkey", f"{tmp}/c.pem",
                      "-in", f"{tmp}/sig.bin"], capture_output=True).stdout
di = subprocess.run(["openssl", "asn1parse", "-inform", "DER"], input=rec, capture_output=True).stdout.decode("utf-8", "replace")
import re
m = re.findall(r"[0-9A-F]{64}", di)
spc_h = hashlib.sha256(spc).hexdigest().upper()
if not m or m[-1] != spc_h:
    print(f"  FAIL sign-efi-gate[{label}]: RSA signature invalid ({m[-1:]!r} vs {spc_h})"); sys.exit(1)
print(f"  PASS sign-efi-gate[{label}]: Authenticode PE-hash + RSA signature verify (a real UEFI would accept)")
PY
}

# 512 = 8-aligned (empty pad). 509 = unaligned: cert table lands at 512, so the
# signed hash MUST cover the 3 pad bytes. 509 is the case that turns red against
# a pre-3.12.2 signer; 512 alone cannot.
run_case 512 aligned
run_case 509 unaligned
