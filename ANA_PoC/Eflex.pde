// Eflex.pde — ANA eFLEX vault. The "no wallet": not a balance, just the growing pile of sealed
// proofs a lesson has minted. A proof = a captured-moment body, FLEX-signed, hashed. This is the
// shared Foundation every lesson plugs into: mintProof() seals + records; this screen shows the pile.
// (The "+ Mint a test proof" button is a dev stand-in that proves the pipeline; real lessons call
//  mintProof() themselves once they verify an event.)

// ---- vault store (persisted via pref: one record per line "lesson|timestamp|hash|amount")
String[] eflexRows() {
  String cur = (js != null) ? js.pref("eflexVault") : "";
  if (cur == null || cur.length() == 0) return new String[0];
  return split(cur, '\n');
}
void eflexAdd(String rec) {
  String cur = (js != null) ? js.pref("eflexVault") : "";
  if (cur == null) cur = "";
  String nv = cur.length() > 0 ? cur + "\n" + rec : rec;
  if (js != null) js.setPref("eflexVault", nv);
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

  // ---- actions. iOS gets the real Round-Trip lesson beside the dev test button; Android gets the test only.
  textAlign(CENTER, CENTER);
  if (onIOS) {
    // test proof (left)
    fill(20, 60, 54);
    rrect(FX(45), FY(466), 370 * fk, 70 * fk, 20 * fk);
    fill(#4DE2C4);
    textSizeQ(24 * fk);
    boldTextF("+  Test proof", FX(45) + 185 * fk, FY(466) + 35 * fk);
    // round-trip (right) — label reflects whether one is out and waiting
    boolean waiting = rtPendingHash().length() > 0;
    fill(waiting ? color(58, 46, 18) : color(44, 36, 16));
    rrect(FX(437), FY(466), 370 * fk, 70 * fk, 20 * fk);
    fill(#FFD147);
    textSizeQ(waiting ? 22 * fk : 24 * fk);
    boldTextF(waiting ? "Round-trip · waiting…" : "Start round-trip", FX(437) + 185 * fk, FY(466) + 35 * fk);
  } else {
    fill(20, 60, 54);
    rrect(FX(246), FY(466), 360 * fk, 70 * fk, 20 * fk);
    fill(#4DE2C4);
    textSizeQ(26 * fk);
    boldTextF("+  Mint a test proof", FX(246) + 180 * fk, FY(466) + 35 * fk);
  }

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
}

void eflexTap(float mx, float my) {
  poke();
  boolean onRow = my >= FY(466) && my <= FY(466) + 70 * fk;
  if (!onRow) return;
  if (onIOS) {
    if (mx >= FX(45) && mx <= FX(45) + 370 * fk) {                     // test proof (left)
      mintProof("TEST", eflexBody("TEST"), 1.0);
    } else if (mx >= FX(437) && mx <= FX(437) + 370 * fk) {            // start / re-send round-trip (right)
      roundTripStart();
    }
  } else if (mx >= FX(246) && mx <= FX(246) + 360 * fk) {              // Android: test only
    mintProof("TEST", eflexBody("TEST"), 1.0);
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
String rtPendingHash() {
  if (js == null) return "";
  String h = js.pref("rtPendingHash");
  return (h == null) ? "" : h;
}
void roundTripStart() {
  if (js == null) return;
  String body = eflexBody("ROUNDTRIP");
  String h = js.roundTripShare(body);                                 // native builds the file, pops the share sheet
  if (h != null && h.length() > 0) {
    js.setPref("rtPendingHash", h);
    js.setPref("rtPendingBody", body);
  }
}
void eflexPoll() {
  if (!onIOS || js == null) return;
  String got = js.roundTripInbox();                                   // sha256 of any round-trip files imported back
  if (got == null || got.length() == 0) return;
  String pend = rtPendingHash();
  if (pend.length() == 0) return;
  String[] hs = split(got, '\n');
  for (int i = 0; i < hs.length; i++) {
    if (hs[i].equals(pend)) {                                         // the exact bytes I sent came back — proof carried
      String body = js.pref("rtPendingBody");
      mintProof("ROUNDTRIP", (body != null && body.length() > 0) ? body : ("roundtrip\nhash: " + pend), 2.0);
      js.setPref("rtPendingHash", "");
      js.setPref("rtPendingBody", "");
    }
  }
}
