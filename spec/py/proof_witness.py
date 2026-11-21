"""
proof_witness.py  -  the signed witness of an ownership proof (choice A, Thu 19 Nov 2026).

When a wallet goes Proven, the phone writes one class 22 pngmesh (Mesh Rule chains) holding the proof,
signed with the phone's own P-256 key the Spec's way (section 1 and 4):

    proof | version     | 1
    proof | coin        | BTC
    proof | address     | bc1qqm49...
    proof | direction   | in            (in = Received, out = Sent)
    proof | units       | 8683          (satoshis / litoshis, exact)
    proof | amount      | 0.00008683    (as the notification wrote it)
    proof | txid        | 8122dd2c...
    proof | block_time  | 1795075134    (seconds since 1970)
    proof | notified_ms | 1795075682000
    proof | app         | com.sixdays.trust
    proof | via         | iphone-relay | android | iphone-relay-on-android
    proof | party       | bc1qhp...5fjj (the From / To fingerprint, "" if none)
    proof | note        | the plain-words line the card shows
    phone | key         | <130 hex: 04 || X || Y, the signing phone's public key>
    sig   | key_id      | <64 hex: sha256 of that key>
    sig   | value       | <128 hex: r || s, low-S, over "ANA-PMSH1|22|" || sha256(body)>

A witness is self-signed: it shows WHICH phone saw the proof and that nothing in it changed since. It is
not a Novvera-trusted file (that would be a lesson or a permission). Mesh Rule v2 takes it over later.

    python3 proof_witness.py <file.pngmesh>     checks a witness from a phone (and its .sha256 sidecar)
    python3 proof_witness.py                    self-test
"""
import hashlib
import os
import sys

import anarule as A

FIELDS = ["version", "coin", "address", "direction", "units", "amount", "txid", "block_time",
          "notified_ms", "app", "via", "party", "note"]


def check(f, sidecar_text=None):
    """-> (ok, message, fields)"""
    if sidecar_text is not None:
        first = sidecar_text.split("\n", 1)[0].strip().lower()
        if first != hashlib.sha256(f).hexdigest():
            return False, "BAD_SIDECAR", {}
    try:
        cls, rows, body = A.parse(f)
    except A.Bad as e:
        return False, "BAD_FORMAT: %s" % e, {}
    if cls != 22:
        return False, "BAD_FORMAT: class %d, not 22" % cls, {}
    kv = {}
    for s, k, v in rows:
        kv[(s, k)] = v
    if len(rows) < 3 or rows[-1][:2] != ("sig", "value") or rows[-2][:2] != ("sig", "key_id"):
        return False, "BAD_FORMAT: sig rows", {}
    raw_hex = kv.get(("phone", "key"), "")
    try:
        raw = bytes.fromhex(raw_hex)
        sig = bytes.fromhex(rows[-1][2])
    except ValueError:
        return False, "BAD_FORMAT: hex", {}
    if len(raw) != 65 or raw[0] != 4 or len(sig) != 64:
        return False, "BAD_FORMAT: key or signature size", {}
    if A.key_id(raw) != rows[-2][2]:
        return False, "BAD_SIGNATURE: key_id is not this phone's key", {}
    if int.from_bytes(sig[32:], "big") > A.N // 2:
        return False, "HIGH_S", {}
    if not A.verify_raw(raw, A.signed_message(22, body), sig):
        return False, "BAD_SIGNATURE", {}
    fields = {k: kv.get(("proof", k), "") for k in FIELDS}
    if fields["version"] != "1" or not fields["units"].isdigit():
        return False, "BAD_FORMAT: proof rows", {}
    return True, "OK: signed by phone " + rows[-2][2][:16], fields


def _selftest():
    phone = A.priv_from_seed("ANA TEST PHONE key, never a real one")
    raw = A.raw_pub(phone)
    rows = [("proof", "version", "1"), ("proof", "coin", "BTC"),
            ("proof", "address", "bc1qqm49tpkgjfyv65valfmvt4x79ert90255mderk"),
            ("proof", "direction", "in"), ("proof", "units", "8683"), ("proof", "amount", "0.00008683"),
            ("proof", "txid", "8122dd2c9ea2979e5d16b7e137efd71c6d88cc192458fffb4163e5c6997cd645"),
            ("proof", "block_time", "1795075134"), ("proof", "notified_ms", "1795075682000"),
            ("proof", "app", "com.sixdays.trust"), ("proof", "via", "iphone-relay"),
            ("proof", "party", "bc1qhp...5fjj"), ("proof", "note", "Proven: +0.00008683 BTC"),
            ("phone", "key", raw.hex())]
    f = A.build(22, rows, phone)
    sc = A.sidecar(f).decode()
    ok, msg, fields = check(f, sc)
    assert ok and fields["units"] == "8683", msg
    # one changed byte in the amount -> refused
    bad = f.replace(b"8683", b"8684", 1)
    assert not check(bad)[0]
    assert check(bad, sc)[1] == "BAD_SIDECAR"
    # a different phone's key swapped in -> refused
    other = A.raw_pub(A.priv_from_seed("another phone")).hex()
    swapped = A.build(22, rows[:-1] + [("phone", "key", other)], phone)
    assert check(swapped)[1].startswith("BAD_SIGNATURE")
    # high-S -> refused
    assert check(A.build(22, rows, phone, high_s=True))[1] == "HIGH_S"
    with open(os.path.join(os.path.dirname(__file__), "..", "vectors", "proof_witness_ok.pngmesh"), "wb") as o:
        o.write(f)
    print("proof_witness: all checks pass")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        data = open(sys.argv[1], "rb").read()
        side = sys.argv[1] + ".sha256" if os.path.exists(sys.argv[1] + ".sha256") else os.path.splitext(sys.argv[1])[0] + ".sha256"
        st = open(side).read() if os.path.exists(side) else None
        ok, msg, fields = check(data, st)
        print(msg)
        for k in FIELDS:
            if fields.get(k):
                print("  %-12s %s" % (k, fields[k]))
        sys.exit(0 if ok else 1)
    _selftest()
