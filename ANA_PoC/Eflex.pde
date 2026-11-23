// Eflex.pde — ANA eFLEX vault. The "no wallet": not a balance, just the growing pile of sealed
// proofs a lesson has minted. A proof = a captured-moment body, FLEX-signed, hashed. This is the
// shared Foundation every lesson plugs into: mintProof() seals + records; this screen shows the pile.
// (The "+ Mint a test proof" button is a dev stand-in that proves the pipeline; real lessons call
//  mintProof() themselves once they verify an event.)

// ---- vault store (persisted via pref: one record per line "lesson|timestamp|hash|amount").
// Cached in the sketch so drawing never hits the bridge every frame — on iOS every js.* call is a
// synchronous window.prompt, and reading the vault 60x/second froze the slower phones. We read the
// pref once (lazily) and keep the pile in memory; eflexAdd keeps the cache and the pref in step.
String[] eflexCache = null;        // vault rows; null = not loaded from pref yet
String rtPendCache = null;         // pending round-trip hash; null = not loaded, "" = none out
int    eflexPollAt = 0;            // next frame we're allowed to poll roundTripInbox

String[] eflexRows() {
  if (eflexCache == null) {
    String cur = (js != null) ? js.pref("eflexVault") : "";
    eflexCache = (cur == null || cur.length() == 0) ? new String[0] : split(cur, '\n');
  }
  return eflexCache;
}
void eflexAdd(String rec) {
  String[] old = eflexRows();
  String[] nv = new String[old.length + 1];
  for (int i = 0; i < old.length; i++) nv[i] = old[i];
  nv[old.length] = rec;
  eflexCache = nv;
  if (js != null) {
    String s = "";
    for (int i = 0; i < nv.length; i++) s += (i > 0 ? "\n" : "") + nv[i];
    js.setPref("eflexVault", s);
  }
}
float eflexTotal() {
  String[] r = eflexRows(); float t = 0;
  for (int i = 0; i < r.length; i++) { String[] f = split(r[i], '|'); if (f.length >= 4) t += float(f[3]); }
  return t;
}

// ---- the mint pipeline: seal a verified moment as a signed proof and record it. Returns the hash.
String mintProof(String lesson, String body, float amt) {
  if (js == null) return "";
  String sig = js.flexSign(body);                 // FLEX signs the captured-moment body
  String full = body + "\nsig: " + sig;
  String hash = js.flexHash(full);                // sha256 anchor
  String ts = nf(year(), 4) + "-" + nf(month(), 2) + "-" + nf(day(), 2) + " " + nf(hour(), 2) + ":" + nf(minute(), 2);
  eflexAdd(lesson + "|" + ts + "|" + hash + "|" + nf(amt, 1, 2));
  return hash;
}

void drawEflex() {
  eflexPoll();                                  // catch any round-trip proof that came back
  coSignPoll();                                 // catch an incoming co-sign request/reply
  image(flatBgImg, 0, 0);
  flatHeader("eFLEX", "proofs you've earned", false);

  String[] rows = eflexRows();
  float total = eflexTotal();

  // ---- the running total (it's a count of sealed truths, not a balance)
  fill(#FFD147);
  textAlign(CENTER, BASELINE);
  textSizeQ(96 * fk);
  text(nf(total, 1, total == int(total) ? 0 : 2), FX(426), FY(360));
  fill(#9FD9CE);
  textSizeQ(27 * fk);
  text("eFLEX  ·  " + rows.length + (rows.length == 1 ? " proof" : " proofs"), FX(426), FY(408));

  // ---- actions: Test proof, the Round-Trip lesson, and the Co-Sign lesson. All platforms.
  textAlign(CENTER, CENTER);
  float bw = 240 * fk, bh = 70 * fk, by = FY(466);
  // test proof (left)
  fill(20, 60, 54);
  rrect(FX(45), by, bw, bh, 18 * fk);
  fill(#4DE2C4);
  textSizeQ(22 * fk);
  boldTextF("+  Test", FX(45) + 120 * fk, by + 35 * fk);
  // round-trip (middle)
  boolean waiting = rtPendingHash().length() > 0;
  fill(waiting ? color(58, 46, 18) : color(44, 36, 16));
  rrect(FX(300), by, bw, bh, 18 * fk);
  fill(#FFD147);
  textSizeQ(waiting ? 18 * fk : 22 * fk);
  boldTextF(waiting ? "Round-trip…" : "Round-trip", FX(300) + 120 * fk, by + 35 * fk);
  // co-sign (right)
  boolean csw = coSignWaiting();
  fill(csw ? color(26, 42, 64) : color(18, 30, 48));
  rrect(FX(555), by, bw, bh, 18 * fk);
  fill(#7FB0FF);
  textSizeQ(csw ? 18 * fk : 22 * fk);
  boldTextF(csw ? "Co-sign…" : "Co-sign", FX(555) + 120 * fk, by + 35 * fk);

  // ---- the pile, newest first
  float top = FY(600), rowH = 108 * fk;
  int shown = min(rows.length, 4);
  if (rows.length == 0) {
    fill(#9FD9CE);
    textAlign(CENTER, CENTER);
    textSizeQ(23 * fk);
    text("No proofs yet — complete a lesson to earn eFLEX", FX(426), FY(690));
  } else {
    glassCard(FX(45), top, 762 * fk, shown * rowH + 22 * fk, 34 * fk, color(40, 120, 110));
    for (int i = 0; i < shown; i++) {
      String[] f = split(rows[rows.length - 1 - i], '|');
      if (f.length < 4) continue;
      float y = top + 22 * fk + i * rowH;
      if (i > 0) { stroke(30, 70, 64, 160); strokeWeight(1.2 * fk); line(FX(70), y, FX(782), y); noStroke(); }
      fill(#FFD147);
      ellipse(FX(92), y + 46 * fk, 22 * fk, 22 * fk);
      fill(#EAFBF6);
      textAlign(LEFT, BASELINE);
      textSizeQ(27 * fk);
      boldTextF(f[0] + "   ·   +" + f[3] + " eFLEX", FX(132), y + 40 * fk);
      fill(#9FD9CE);
      textSizeQ(20 * fk);
      text(f[1], FX(132), y + 70 * fk);
      fill(#5F8C80);
      textSizeQ(18 * fk);
      text("sealed #" + f[2].substring(0, min(16, f[2].length())), FX(132), y + 96 * fk);
    }
  }
  flashDraw();
}

void eflexTap(float mx, float my) {
  poke();
  boolean onRow = my >= FY(466) && my <= FY(466) + 70 * fk;
  if (!onRow) return;
  float bw = 240 * fk;
  if (mx >= FX(45) && mx <= FX(45) + bw) {                             // test proof
    mintProof("TEST", eflexBody("TEST"), 1.0);
  } else if (mx >= FX(300) && mx <= FX(300) + bw) {                    // start / re-send round-trip
    roundTripStart();
  } else if (mx >= FX(555) && mx <= FX(555) + bw) {                    // co-sign the nearest phone
    coSignStart();
  }
}

// A fresh, nonce-unique captured-moment body. The nonce makes every proof one-of-a-kind (replay is dead).
String eflexBody(String lesson) {
  String moment = (js != null) ? js.radarPeers() : "";                // whatever reality is in range
  String nonce = hex((int) random(0x10000), 4) + hex((int) random(0x10000), 4);
  return "ANAEFLEX1\nlesson: " + lesson + "\nmoment: " + moment + "\nnonce: " + nonce +
         "\nkey: " + ((js != null) ? js.flexKey() : "");
}

// ---- ROUND-TRIP (L2): mint a fresh proof, share it out, remember its hash; mint for real when it returns.
String rtPendingHash() {                                              // cached: no per-frame bridge call
  if (rtPendCache == null) {
    String h = (js != null) ? js.pref("rtPendingHash") : "";
    rtPendCache = (h == null) ? "" : h;
  }
  return rtPendCache;
}
void roundTripStart() {
  if (js == null) return;
  String body = eflexBody("ROUNDTRIP");
  String h = js.roundTripShare(body);                                 // native builds the file, pops the share sheet
  if (h != null && h.length() > 0) {
    js.setPref("rtPendingHash", h);
    js.setPref("rtPendingBody", body);
    rtPendCache = h;
    eflexPollAt = frameCount;                                         // start watching for the return now
  }
}
void eflexPoll() {
  if (js == null) return;
  if (rtPendingHash().length() == 0) return;                          // nothing out — no bridge call at all
  if (frameCount < eflexPollAt) return;                               // throttle: a few checks a second, not 60
  eflexPollAt = frameCount + 20;
  String got = js.roundTripInbox();                                   // sha256 of any round-trip files imported back
  if (got == null || got.length() == 0) return;
  String pend = rtPendingHash();
  String[] hs = split(got, '\n');
  for (int i = 0; i < hs.length; i++) {
    if (hs[i].equals(pend)) {                                         // the exact bytes I sent came back — proof carried
      String body = js.pref("rtPendingBody");
      mintProof("ROUNDTRIP", (body != null && body.length() > 0) ? body : ("roundtrip\nhash: " + pend), 2.0);
      js.setPref("rtPendingHash", "");
      js.setPref("rtPendingBody", "");
      rtPendCache = "";
    }
  }
}
