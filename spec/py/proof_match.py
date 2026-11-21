"""
proof_match.py  -  matches a parsed notification (proof_parse) to one on-chain transaction.

A transaction matches when ALL hold:
  - direction "in":  an output pays the watched address exactly c["units"]
    direction "out": an input spends from the watched address, and an output pays
                     exactly c["units"] to an address fitting the "To" fingerprint
                     (change goes back as its own output, so it never needs subtracting)
  - the "From"/"To" fingerprint (prefix...suffix) fits, when the notification gave one
  - the tx time is within the window before the notification (push comes after the block)
  - it is confirmed
Exactly one transaction must match; two or more is AMBIGUOUS, none is NO_MATCH.
"""
from proof_parse import parse, party_matches

WINDOW_BEFORE = 60 * 60      # tx up to 1 hour before the push
WINDOW_AFTER = 60 * 60       # wallets that push on broadcast: the block comes after the push


def fits(c, tx, watched, notified_at):
    if not tx["confirmed"]:
        return False
    if not (notified_at - WINDOW_BEFORE <= tx["time"] <= notified_at + WINDOW_AFTER):
        return False
    if c["direction"] == "in":
        if not any(o["address"] == watched and o["value"] == c["units"] for o in tx["vout"]):
            return False
        return "party_prefix" not in c or any(party_matches(c, i["address"]) for i in tx["vin"])
    if not any(i["address"] == watched for i in tx["vin"]):
        return False
    return any(o["value"] == c["units"] and o["address"] != watched and party_matches(c, o["address"])
               for o in tx["vout"])


def match(c, txs, watched, notified_at):
    hits = [t for t in txs if fits(c, t, watched, notified_at)]
    if len(hits) == 1:
        return "MATCH", hits[0]
    return ("AMBIGUOUS" if hits else "NO_MATCH"), None


if __name__ == "__main__":
    import datetime as dt
    ast = dt.timezone(dt.timedelta(hours=-4))
    ts = lambda s: int(dt.datetime.strptime(s, "%Y-%m-%d %H:%M:%S").replace(tzinfo=ast).timestamp())

    WATCH = "bc1qqm49tpkgjfyv65valfmvt4x79ert90255mderk"
    # the real tx, as shown on mempool.space (visible outputs; 7 more not shown)
    real_tx = {
        "txid": "8122dd2c9ea2979e5d16b7e137efd71c6d88cc192458fffb4163e5c6997cd645",
        "time": ts("2026-11-17 11:58:54"), "confirmed": True,
        "vin": [{"address": "bc1qhp7n555hk5mxlp3pz0347XXXXe7wp5fjj", "value": 2000000000}],
        "vout": [{"address": a, "value": v} for a, v in [
            ("bc1qqczwcz6ncff3zs25n80u98e8rkyaXXXXv45zryl5", 126882428),
            ("3GfyLHnouFeGrdnY81TFRg7eGhDMkcowoW", 622758313),
            (WATCH, 8683),
            ("bc1q8gfnmw2y53230hesuq28zj9p8XXXXf7cfg824", 771002)]]}
    c = parse("\U0001F4B0 Received: 0.00008683 BTC", "From bc1qhp...5fjj")
    pushed = ts("2026-11-17 12:08:02")

    verdict, tx = match(c, [real_tx], WATCH, pushed)
    assert verdict == "MATCH", verdict
    print("REAL Nov 17:", verdict, tx["txid"][:16], " push came", (pushed - tx["time"]) // 60, "min",
          (pushed - tx["time"]) % 60, "s after the block")

    # a fake: right amount, wrong sender  -> no match
    fake = dict(real_tx, vin=[{"address": "bc1qzz0000000000000000000000000005fjj", "value": 1}])
    assert match(c, [fake], WATCH, pushed)[0] == "NO_MATCH"
    # right tx, one sat off -> no match
    c2 = dict(c, units=8684)
    assert match(c2, [real_tx], WATCH, pushed)[0] == "NO_MATCH"
    # a push 3 hours later -> outside the window
    assert match(c, [real_tx], WATCH, pushed + 3 * 3600)[0] == "NO_MATCH"
    # same tx seen twice (two candidates) -> ambiguous
    assert match(c, [real_tx, dict(real_tx, txid="copy")], WATCH, pushed)[0] == "AMBIGUOUS"
    print("proof_match: all checks pass")
