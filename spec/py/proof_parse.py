"""
proof_parse.py  -  reads a wallet notification and pulls out a proof candidate.

Only "Received:" / "Sent:" lines with an amount and a ticker count.
Price alerts and everything else return None.

The amount is kept as an exact integer in the coin's smallest unit
(satoshis / litoshis), never as a float.
"""
import re

# smallest-unit decimals per ticker (UTXO coins first; more added as we see them)
DECIMALS = {"BTC": 8, "LTC": 8, "DOGE": 8, "BCH": 8}

# leading emoji / symbols are ignored; "Received: 0.00008683 BTC"
HEAD = re.compile(r"(Received|Sent)\s*:?\s*([0-9]+(?:\.[0-9]+)?)\s+([A-Z]{2,10})\b")
# "From bc1qhp...5fjj"  /  "To LYN2To...rsZ"   (prefix ... suffix, either dot style)
PARTY = re.compile(r"\b(From|To)\s+([A-Za-z0-9]+)(?:\.{3}|…)([A-Za-z0-9]+)")


def to_units(amount, ticker):
    d = DECIMALS.get(ticker)
    if d is None:
        return None
    whole, _, frac = amount.partition(".")
    if len(frac) > d:
        return None                      # more decimals than the coin has: not trustworthy
    return int(whole) * 10 ** d + int((frac + "0" * d)[:d])


def parse(title, body=""):
    text = (title or "") + "\n" + (body or "")
    m = HEAD.search(text)
    if not m:
        return None
    direction = "in" if m.group(1) == "Received" else "out"
    ticker = m.group(3)
    units = to_units(m.group(2), ticker)
    if units is None:
        return None
    c = {"direction": direction, "ticker": ticker, "units": units,
         "amount": m.group(2), "exact": len(m.group(2).partition(".")[2]) == DECIMALS[ticker]}
    p = PARTY.search(text)
    if p:
        c["party_role"] = "sender" if p.group(1) == "From" else "receiver"
        c["party_prefix"], c["party_suffix"] = p.group(2), p.group(3)
    return c


def party_matches(c, address):
    """the truncated address in the notification fits a full on-chain address"""
    if "party_prefix" not in c:
        return True                      # nothing to check
    return address.startswith(c["party_prefix"]) and address.endswith(c["party_suffix"])


if __name__ == "__main__":
    # the real one from Thu 19 Nov (Trust Wallet, Nov 17 12:08:02 PM, relayed iPhone -> Android)
    real = parse("\U0001F4B0 Received: 0.00008683 BTC", "From bc1qhp...5fjj")
    assert real["direction"] == "in" and real["ticker"] == "BTC"
    assert real["units"] == 8683 and real["exact"]
    assert real["party_role"] == "sender"
    assert party_matches(real, "bc1qhpXXXXXXXXXXXXXXXXXXXXXXXXXXXX5fjj")
    assert not party_matches(real, "bc1qzzXXXXXXXXXXXXXXXXXXXXXXXXXXXX5fjj")

    # price alerts are ignored
    assert parse("\U0001F4C8 BTC price alert: BTC just passed $60,000") is None
    assert parse("\U0001F4C8 SOL Price Update: SOL is up 5.10%") is None

    # a guessed Sent shape (to confirm against the real LTC screenshot)
    s = parse("Sent: 0.5 LTC", "To LYN2To...rsZ")
    assert s["direction"] == "out" and s["units"] == 50000000 and not s["exact"]
    assert party_matches(s, "LYN2To4qkWLYWCgbpS7hRTmCp528EGYrsZ")

    # too many decimals is refused, unknown ticker is refused
    assert parse("Received: 0.000000001 BTC") is None
    assert parse("Received: 5 XYZ") is None
    print("proof_parse: all checks pass")
