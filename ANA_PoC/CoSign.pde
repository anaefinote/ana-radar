// ---- CO-SIGN (L1): two phones in BLE range both sign ONE shared moment, so neither could have made
// the proof alone. 2-hop (commit -> complete), carried on the round-trip pipe. v1 uses the strongest
// BLE peer (2-phone friendly) and single-sample RSSI reciprocity. Protocol proven in diag/cosign2.js.
//
//   A: build commitment {nonce, rssi(A->B), tick, key}, sign it (sigA), share classCoSign to B.
//   B: verify sigA, check |rssiA - rssiB| < GAP (real co-presence), form the full moment (adds nB,
//      rssiB, bkey), sign it (sigB), share classCoSignReply back, and mint {moment, sigA, sigB}.
//   A: verify sigB over the moment, confirm it answers our nonce, re-check reciprocity, mint the same.

int COSIGN_GAP = 15;               // dB: single-sample reciprocity tolerance (looser than the series mean)
int coSignAt = 0;                  // next frame allowed to poll the co-sign inbox

// a tiny transient status line (co-sign is a multi-step flow; silence here would be confusing)
String flashMsg = "";
int flashAt = -99999;
void flash(String m) { flashMsg = m; flashAt = millis(); }
void flashDraw() {
  if (millis() - flashAt > 3200) return;
  fill(#FFD147);
  textAlign(CENTER, CENTER);
  textSizeQ(20 * fk);
  text(flashMsg, FX(426), FY(876));
}

// pull a "key: value" field out of a body (first match)
String csField(String body, String key) {
  String[] ls = split(body, '\n');
  for (int i = 0; i < ls.length; i++) {
    if (ls[i].startsWith(key + ": ")) return ls[i].substring(key.length() + 2);
  }
  return "";
}

// strongest BLE peer's RSSI (hop 0, real radio). Returns 1 (impossible for real RSSI) if none in range.
int csBestRssi() {
  if (js == null) return 1;
  String ps = rdrField(js.radarPeers(), 1);
  if (ps.length() == 0) return 1;
  String[] rows = split(ps, ';');
  int best = -999;
  for (int i = 0; i < rows.length; i++) {
    String[] f = split(rows[i], ',');
    if (f.length >= 2) { int r = int(f[1]); if (r > best) best = r; }
  }
  return best == -999 ? 1 : best;
}

boolean coSignWaiting() {
  if (js == null) return false;
  String p = js.pref("coSignNonce");
  return p != null && p.length() > 0;
}

// A initiates: commit to our half, sign it, share to B, remember our nonce.
void coSignStart() {
  if (js == null) return;
  int rssiA = csBestRssi();
  if (rssiA > 0) { flash("Co-sign needs another phone in Bluetooth range"); return; }
  String nA = hex((int) random(0x10000), 4) + hex((int) random(0x10000), 4);
  String tick = nf(year(), 4) + "-" + nf(month(), 2) + "-" + nf(day(), 2) + "T" + nf(hour(), 2) + ":" + nf(minute(), 2);
  String canon = "ANACOSIGN1\nnonce: " + nA + "\nrssi: " + rssiA + "\ntick: " + tick + "\nkey: " + js.flexKey();
  String sigA = js.flexSign(canon);
  js.coSignRequest(canon + "\nsig: " + sigA);     // native: write classCoSign pngmesh, pop the share sheet
  js.setPref("coSignNonce", nA);
}

// poll the inbox: a request makes us B; a reply means we were A.
void coSignPoll() {
  if (js == null) return;
  if (frameCount < coSignAt) return;
  coSignAt = frameCount + 15;                       // ~4x/second, not every frame
  String got = js.coSignInbox();
  if (got == null || got.length() == 0) return;
  String[] items = split(got, "\n@@@\n");           // native separates items with this marker
  for (int i = 0; i < items.length; i++) {
    int tab = items[i].indexOf('\t');
    if (tab < 0) continue;
    String kind = items[i].substring(0, tab), body = items[i].substring(tab + 1);
    if (kind.equals("REQ")) coSignHandleReq(body);
    else if (kind.equals("REPLY")) coSignHandleReply(body);
  }
}

// B: verify A's half, check reciprocity, sign the full moment, reply, mint.
void coSignHandleReq(String body) {
  int si = body.lastIndexOf("\nsig: ");
  if (si < 0) return;
  String canonA = body.substring(0, si);
  String sigA = body.substring(si + 6);
  String aKey = csField(canonA, "key");
  if (aKey.length() == 0 || !js.flexVerify(aKey, canonA, sigA)) { flash("Co-sign: couldn't verify the request"); return; }
  int rssiA = int(csField(canonA, "rssi"));
  int rssiB = csBestRssi();
  if (rssiB > 0) { flash("Co-sign: the other phone isn't in range here"); return; }
  if (abs(rssiA - rssiB) >= COSIGN_GAP) { flash("Co-sign: radio link doesn't match (not co-present)"); return; }
  String nB = hex((int) random(0x10000), 4) + hex((int) random(0x10000), 4);
  String moment = canonA + "\nbnonce: " + nB + "\nbrssi: " + rssiB + "\nbkey: " + js.flexKey();
  String sigB = js.flexSign(moment);
  js.coSignReply(moment + "\nasig: " + sigA + "\nbsig: " + sigB);   // native: write classCoSignReply, pop share sheet
  mintProof("COSIGN", moment, 3.0);                 // B holds {moment, sigA (from the request), sigB}
  flash("Co-signed ✓ proof minted");
}

// A: verify B's signature, confirm it answers our nonce, re-check reciprocity, mint.
void coSignHandleReply(String body) {
  int ai = body.lastIndexOf("\nasig: ");
  if (ai < 0) return;
  String moment = body.substring(0, ai);
  String sigB = csField(body, "bsig");
  String bKey = csField(moment, "bkey");
  if (bKey.length() == 0 || !js.flexVerify(bKey, moment, sigB)) { flash("Co-sign: couldn't verify the reply"); return; }
  String pend = js.pref("coSignNonce");
  if (pend == null || pend.length() == 0 || !pend.equals(csField(moment, "nonce"))) return;   // not our request
  int rssiA = int(csField(moment, "rssi")), rssiB = int(csField(moment, "brssi"));
  if (abs(rssiA - rssiB) >= COSIGN_GAP) { flash("Co-sign: link mismatch on reply"); return; }
  mintProof("COSIGN", moment, 3.0);
  js.setPref("coSignNonce", "");
  flash("Co-signed ✓ proof minted");
}
