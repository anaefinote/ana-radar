"""Makes the test files in ../vectors and vectors.json, then checks them with anarule.py.

Every key here is a TEST key derived from a fixed text. Never the real Novvera root or spare.
Run:  python3 -I make_vectors.py ../vectors
"""
import base64, hashlib, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anarule as A

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "vectors")
os.makedirs(out, exist_ok=True)

ROOT = A.priv_from_seed("ANA TEST ROOT key, never the real one")
SPARE = A.priv_from_seed("ANA TEST SPARE key, never the real one")
ACME = A.priv_from_seed("ANA TEST licensee ACME")
STRANGER = A.priv_from_seed("ANA TEST stranger")
TRUSTED = [A.raw_pub(ROOT), A.raw_pub(SPARE)]
kid = lambda p: A.key_id(A.raw_pub(p))

BUILDS = {
    "ORBIT": {"reader": 1, "tier": "ana", "hives": A.HIVES_ALL},
    "STATIA": {"reader": 1, "tier": "statia", "hives": A.HIVES_ALL},
    "NO_WATCH": {"reader": 1, "tier": "ana", "hives": ["efinote"]},     # a test-only build, to reach WRONG_HIVE
}

# ------------------------------------------------------------------ addresses for the tests (valid by construction)
def b58enc(b):
    n = int.from_bytes(b, "big"); s = ""
    while n:
        n, r = divmod(n, 58); s = A.B58[r] + s
    return "1" * (len(b) - len(b.lstrip(b"\x00"))) + s

def b58check(ver, payload):
    d = bytes([ver]) + payload
    return b58enc(d + hashlib.sha256(hashlib.sha256(d).digest()).digest()[:4])

def bech32_addr(hrp, witver, prog):
    acc = bits = 0; data = []
    for x in prog:
        acc = (acc << 8) | x; bits += 8
        while bits >= 5:
            bits -= 5; data.append((acc >> bits) & 31)
    if bits:
        data.append((acc << (5 - bits)) & 31)
    data = [witver] + data
    vals = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp] + data
    pm = A._polymod(vals + [0] * 6) ^ 1
    return hrp + "1" + "".join(A.B32[d] for d in data + [(pm >> 5 * (5 - i)) & 31 for i in range(6)])

h20 = hashlib.sha256(b"ANA test address").digest()[:20]
LTC_L = b58check(48, h20)
LTC_BAD = LTC_L[:-1] + ("2" if LTC_L[-1] != "2" else "3")
LTC_BECH = bech32_addr("ltc", 0, h20)
assert A.b58check_ok(LTC_L, "48,50") and not A.b58check_ok(LTC_BAD, "48,50") and A.bech32_ok(LTC_BECH, "ltc")

# ------------------------------------------------------------------ lessons
def cardano(version=1, **over):
    rows = [
        ("lesson", "id", "cardano"), ("lesson", "version", str(version)), ("lesson", "needs_reader", "1"),
        ("lesson", "hive", "watch"), ("lesson", "tier", "ana"),
        ("coin", "name", "Cardano"), ("coin", "ticker", "ADA"), ("coin", "decimals", "6"),
        ("coin", "display_decimals", "4"), ("coin", "price_id", "cardano"),
        ("address", "form1.kind", "bech32"), ("address", "form1.hrp", "addr"),
        ("address", "form1.pattern", "^addr1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{50,120}$"),
        ("reader", "name", "json"),
        ("server", "1", "https://api.koios.rest/api/v1/address_info"),
        ("param", "method", "POST"), ("param", "body", '{"_addresses":["{address}"]}'),
        ("param", "balance_path", "0.balance"), ("param", "balance_type", "text_integer"),
        ("test", "good.1", "addr1q8df6egcnzgak7prje3lnpt42e3h7j2y9tjpjzr89lq5uxc3ulas65tpunlmdm93a4jtwag4575ymr4dyuukhany6qaqka4v3c"),
        ("test", "bad.1", "addr1q8df6egcnzgak7prje3lnpt42e3h7j2y9tjpjzr89lq5uxc3ulas65tpunlmdm93a4jtwag4575ymr4dyuukhany6qaqka4v3q"),
    ]
    return patch(rows, over)

def litecoin(**over):
    rows = [
        ("lesson", "id", "litecoin"), ("lesson", "version", "1"), ("lesson", "needs_reader", "1"),
        ("lesson", "hive", "watch"), ("lesson", "tier", "statia"),
        ("coin", "name", "Litecoin"), ("coin", "ticker", "LTC"), ("coin", "decimals", "8"),
        ("coin", "display_decimals", "4"), ("coin", "price_id", "litecoin"),
        ("address", "form1.kind", "base58check"), ("address", "form1.versions", "48,50"),
        ("address", "form1.pattern", "^[LM][1-9A-HJ-NP-Za-km-z]{26,33}$"),
        ("address", "form2.kind", "bech32"), ("address", "form2.hrp", "ltc"),
        ("address", "form2.pattern", "^ltc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{20,90}$"),
        ("reader", "name", "esplora"), ("server", "1", "https://litecoinspace.org/api/"),
        ("test", "good.1", LTC_L), ("test", "good.2", LTC_BECH), ("test", "bad.1", LTC_BAD),
    ]
    return patch(rows, over)

def patch(rows, over):
    """over: {"section|key": value}; value None removes the row."""
    rows = list(rows)
    for k, v in over.items():
        s, key = k.split("|", 1)
        idx = [i for i, r in enumerate(rows) if r[0] == s and r[1] == key]
        if v is None:
            rows = [r for i, r in enumerate(rows) if i not in idx]
        elif idx:
            rows[idx[0]] = (s, key, v)
        else:
            rows.append((s, key, v))
    order = {s: i for i, s in enumerate(A.SECTIONS)}
    return sorted(rows, key=lambda r: order.get(r[0], 99))    # stable: keeps each section's own order

def chain_rows(seq, prev, extra):
    return [("chain", "seq", str(seq)), ("chain", "prev", prev)] + extra

def permit(seq, prev, key_priv, tiers="ana", hives="watch", tickers="ADA", until=99, name="ACME Ltd (TEST)", signer=None):
    rows = chain_rows(seq, prev, [("permit", "name", name), ("permit", "key", A.raw_pub(key_priv).hex()),
                                  ("permit", "tiers", tiers), ("permit", "hives", hives),
                                  ("permit", "tickers", tickers), ("permit", "until_seq", str(until))])
    return A.build(A.CLASS_PERMIT, rows, signer or ROOT)

def revoke(seq, prev, keys, signer=None, reason="TEST revoke"):
    return A.build(A.CLASS_REVOKE, chain_rows(seq, prev, [("revoke", "keys", ",".join(keys)), ("revoke", "reason", reason)]), signer or ROOT)

def body_hash(f):
    return hashlib.sha256(A.parse(f)[2]).hexdigest()

def with_permit(rows, pfile):
    return rows + [("permit", "file", base64.b64encode(pfile).decode())]

# ------------------------------------------------------------------ files
files = {}
def put(name, data, sc=None):
    files[name] = (data, A.sidecar(data, name) if sc is None else sc)
    return name

good = A.build(30, cardano(), ROOT)
put("lesson_good.pngmesh", good)
put("lesson_good_v2.pngmesh", A.build(30, cardano(2), ROOT))
put("lesson_v2_other_body.pngmesh", A.build(30, cardano(2, **{"coin|display_decimals": "3"}), ROOT))
put("lesson_by_spare.pngmesh", A.build(30, cardano(3), SPARE))
flip = bytearray(good); i = len(good) - 8 - 40; flip[i] ^= 1                     # a byte inside the trailer body
put("lesson_tampered.pngmesh", bytes(flip))                                        # fresh sidecar: only the signature can catch it
put("lesson_bad_sidecar.pngmesh", good, A.sidecar(good[:-1] + b"x"))
put("lesson_no_sidecar.pngmesh", good, b"")
put("lesson_truncated.pngmesh", good[:-20])
put("lesson_stranger.pngmesh", A.build(30, cardano(), STRANGER))
put("lesson_high_s.pngmesh", A.build(30, cardano(), ROOT, high_s=True))
put("lesson_newer_reader.pngmesh", A.build(30, cardano(**{"lesson|needs_reader": "2"}), ROOT))
put("lesson_hive_efinote.pngmesh", A.build(30, cardano(**{"lesson|hive": "efinote"}), ROOT))
put("lesson_litecoin_statia.pngmesh", A.build(30, litecoin(), ROOT))
put("lesson_http_server.pngmesh", A.build(30, cardano(**{"server|1": "http://api.koios.rest/api/v1/address_info"}), ROOT))
put("lesson_secret_url.pngmesh", A.build(30, cardano(**{"server|1": "https://api.koios.rest/api/v1/address_info?api_key=abc123"}), ROOT))
put("lesson_bad_test_address.pngmesh", A.build(30, cardano(**{"test|bad.1": cardano()[-2][2]}), ROOT))

# root chain
p1 = permit(1, "0" * 64, ACME)
put("chain1_permit_acme.pngmesh", p1)
r2 = revoke(2, body_hash(p1), [kid(ACME)])
put("chain2_revoke_acme.pngmesh", r2)
put("chain2_fork.pngmesh", revoke(2, body_hash(p1), [kid(STRANGER)], reason="TEST a different file 2"))
put("chain3_after_fork.pngmesh", revoke(3, body_hash(r2), [kid(STRANGER)]))
put("chain_permit_by_licensee.pngmesh", permit(1, "0" * 64, ACME, signer=ACME))
put("chain1_bad_prev.pngmesh", permit(1, "1" * 64, ACME))
p1short = permit(1, "0" * 64, ACME, until=2)
put("chainB1_permit_until2.pngmesh", p1short)
put("chainB2_revoke_stranger.pngmesh", revoke(2, body_hash(p1short), [kid(STRANGER)]))
put("chainC1_spare_revokes_root.pngmesh", revoke(1, "0" * 64, [kid(ROOT)], signer=SPARE))

# licensee lessons (signed by ACME, carrying their permission)
acme_rows = cardano(**{"lesson|id": "acme-cardano"})
put("lesson_acme_no_permit.pngmesh", A.build(30, acme_rows, ACME))
put("lesson_acme.pngmesh", A.build(30, with_permit(acme_rows, p1), ACME))
put("lesson_acme_wrong_ticker.pngmesh", A.build(30, with_permit(litecoin(**{"lesson|id": "acme-ltc", "lesson|tier": "ana"}), p1), ACME))
put("lesson_acme_statia.pngmesh", A.build(30, with_permit(cardano(**{"lesson|id": "acme-ada-s", "lesson|tier": "statia"}), p1), ACME))
put("lesson_acme_until2.pngmesh", A.build(30, with_permit(cardano(**{"lesson|id": "acme-ada-2"}), p1short), ACME))
put("lesson_acme_until2_b.pngmesh", A.build(30, with_permit(cardano(**{"lesson|id": "acme-ada-3"}), p1short), ACME))

# ------------------------------------------------------------------ scenarios: a fresh phone each, steps in order
S = []
def scen(name, build, steps):
    S.append({"name": name, "build": build, "steps": [{"file": f, "expect": e} for f, e in steps]})

scen("versions", "ORBIT", [("lesson_good.pngmesh", "ACCEPT"), ("lesson_good.pngmesh", "DUPLICATE"),
     ("lesson_good_v2.pngmesh", "ACCEPT"), ("lesson_good.pngmesh", "OLDER"),
     ("lesson_v2_other_body.pngmesh", "FORK"), ("lesson_by_spare.pngmesh", "ACCEPT")])
scen("damage", "ORBIT", [("lesson_tampered.pngmesh", "BAD_SIGNATURE"), ("lesson_bad_sidecar.pngmesh", "BAD_SIDECAR"),
     ("lesson_no_sidecar.pngmesh", "BAD_SIDECAR"), ("lesson_truncated.pngmesh", "BAD_FORMAT"),
     ("lesson_high_s.pngmesh", "HIGH_S"), ("lesson_stranger.pngmesh", "UNKNOWN_KEY")])
scen("content", "ORBIT", [("lesson_newer_reader.pngmesh", "UPDATE_FIRST"), ("lesson_hive_efinote.pngmesh", "UPDATE_FIRST"),
     ("lesson_litecoin_statia.pngmesh", "WRONG_TIER"), ("lesson_http_server.pngmesh", "BAD_RULES"),
     ("lesson_secret_url.pngmesh", "BAD_RULES"), ("lesson_bad_test_address.pngmesh", "BAD_RULES")])
scen("statia", "STATIA", [("lesson_litecoin_statia.pngmesh", "ACCEPT"), ("lesson_good.pngmesh", "ACCEPT")])
scen("wrong_hive", "NO_WATCH", [("lesson_good.pngmesh", "WRONG_HIVE")])
scen("licensee", "STATIA", [("lesson_acme_no_permit.pngmesh", "UNKNOWN_KEY"), ("chain1_permit_acme.pngmesh", "ACCEPT"),
     ("lesson_acme.pngmesh", "ACCEPT"), ("lesson_acme_wrong_ticker.pngmesh", "NOT_PERMITTED"),
     ("lesson_acme_statia.pngmesh", "NOT_PERMITTED"), ("chain2_revoke_acme.pngmesh", "ACCEPT"),
     ("lesson_acme.pngmesh", "REVOKED")])
scen("expiry", "ORBIT", [("chainB1_permit_until2.pngmesh", "ACCEPT"), ("lesson_acme_until2.pngmesh", "ACCEPT"),
     ("chainB2_revoke_stranger.pngmesh", "ACCEPT"), ("lesson_acme_until2_b.pngmesh", "EXPIRED")])
scen("root_chain", "ORBIT", [("chain2_revoke_acme.pngmesh", "HOLE"), ("chain_permit_by_licensee.pngmesh", "UNKNOWN_KEY"),
     ("chain1_bad_prev.pngmesh", "FORK")])
scen("root_chain_order", "ORBIT", [("chain2_revoke_acme.pngmesh", "HOLE"), ("chain1_permit_acme.pngmesh", "ACCEPT"),
     ("chain2_revoke_acme.pngmesh", "ACCEPT"), ("chain2_revoke_acme.pngmesh", "DUPLICATE"),
     ("chain2_fork.pngmesh", "FORK"), ("chain3_after_fork.pngmesh", "FROZEN")])
scen("spare_revokes_root", "ORBIT", [("lesson_good.pngmesh", "ACCEPT"), ("chainC1_spare_revokes_root.pngmesh", "ACCEPT"),
     ("lesson_good_v2.pngmesh", "REVOKED"), ("lesson_by_spare.pngmesh", "ACCEPT")])
scen("revoked_root_behind_permit", "ORBIT", [("chainC1_spare_revokes_root.pngmesh", "ACCEPT"), ("lesson_acme.pngmesh", "REVOKED")])

# ------------------------------------------------------------------ write and self-check
for name, (data, sc) in files.items():
    open(os.path.join(out, name), "wb").write(data)
    open(os.path.join(out, name + ".sha256"), "wb").write(sc)
doc = {"rule": "ANA Rule v1 (spec/SPEC.md)", "note": "TEST keys only. Never the real Novvera root or spare.",
       "trusted_raw": [r.hex() for r in TRUSTED], "builds": BUILDS, "scenarios": S}
json.dump(doc, open(os.path.join(out, "vectors.json"), "w"), indent=1)

fails = total = 0
seen = set()
for sc in S:
    ph = A.Phone(BUILDS[sc["build"]], TRUSTED)
    for st in sc["steps"]:
        data, side = files[st["file"]]
        v, why = ph.check(data, side)
        total += 1; seen.add(st["expect"])
        ok = v == st["expect"]
        fails += not ok
        print("%-4s %-18s %-36s %-14s %s" % ("ok" if ok else "FAIL", sc["name"], st["file"], v, why if not ok else ""))
print("python: %d/%d verdicts as expected; %d files; verdicts covered: %s" % (total - fails, total, len(files), " ".join(sorted(seen))))
sys.exit(1 if fails else 0)
