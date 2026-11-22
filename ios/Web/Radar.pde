// Radar.pde — ANA : RADAR. Nearby ANA devices, found by scanning ANA's own BLE service UUID.
// No pairing, no connecting: the scope shows who's in the room right now, strongest signal nearest
// the centre, with a live count. The engine is native (Radar.swift); this screen only reads
// js.radarCount() / js.radarPeers(). Scanning is turned on in setTab() when this tab opens.

void drawRadar() {
  image(flatBgImg, 0, 0);
  flatHeader("Radar", "Nearby ANA devices", false);

  int n = (js != null) ? js.radarCount() : 0;
  String data = (js != null) ? js.radarPeers() : "0\t";
  String peerStr = rdrField(data, 1);
  String[] rows = peerStr.length() == 0 ? new String[0] : split(peerStr, ';');

  // ANA FENCE: am I in a fence? If so, the scope wears the fence's colour.
  String fInfo = (js != null) ? js.fenceInfo() : "";
  boolean fenced = fInfo.length() > 0;
  String myFid = "-", fName = "";
  int fHue = 0, fMembers = 0;
  if (fenced) {
    String[] fi = split(fInfo, '\t');
    if (fi.length >= 5) { myFid = fi[0]; fName = fi[1]; fHue = int(fi[2]); fMembers = int(fi[4]); }
    rdrTintHue = fHue;
  } else {
    rdrTintHue = -1;
  }

  // ---- the scope
  float cx = FX(426), cy = FY(620), R = 300 * fk;
  float sweep = (millis() / 2600.0) % 1.0 * TWO_PI;

  noStroke();
  for (int i = 10; i >= 1; i--) {                        // outer glow
    fill(30, 120, 110, 10);
    ellipse(cx, cy, 2 * R * (1 + 0.35 * i / 10.0), 2 * R * (1 + 0.35 * i / 10.0));
  }
  fill(6, 16, 18);
  ellipse(cx, cy, 2 * R, 2 * R);

  noFill();                                              // range rings + cross hairs
  stroke(40, 120, 110, 120);
  strokeWeight(1.4 * fk);
  for (int k = 1; k <= 3; k++) ellipse(cx, cy, 2 * R * k / 3.0, 2 * R * k / 3.0);
  stroke(40, 120, 110, 60);
  line(cx - R, cy, cx + R, cy);
  line(cx, cy - R, cx, cy + R);

  for (int i = 0; i < 40; i++) {                         // the sweep arm, with a fading trail
    float a = sweep - i * 0.03;
    stroke(77, 226, 196, 120 - i * 3);
    strokeWeight(2.2 * fk);
    line(cx, cy, cx + cos(a) * R, cy + sin(a) * R);
  }
  noStroke();

  // ---- real positions when peers have shared their distance rows (MDS constellation);
  //      otherwise the spoke fallback: real distance to each device, placeholder angle.
  String mtx = rdrField(data, 2);
  if (mtx.length() > 0) {
    drawConstellation(cx, cy, R, mtx);
  } else {
    for (int i = 0; i < rows.length; i++) {
      String[] f = split(rows[i], ',');
      if (f.length < 3) continue;
      int rssi = int(f[1]), age = int(f[2]);
      float rr = constrain(map(rssi, -40, -100, 0.12, 0.95), 0.12, 0.98) * R;
      float ang = (rdrHash(f[0]) % 1000) / 1000.0 * TWO_PI;
      float bx = cx + cos(ang) * rr, by = cy + sin(ang) * rr;
      float fade = constrain(1 - age / 15.0, 0.2, 1.0);
      stroke(77, 226, 196, 70 * fade);
      strokeWeight(2 * fk);
      line(cx, cy, bx, by);
      noStroke();
      for (int g = 4; g >= 1; g--) {
        fill(77, 226, 196, 30 * fade);
        ellipse(bx, by, (14 + g * 7) * fk, (14 + g * 7) * fk);
      }
      fill(150, 255, 232, 235 * fade);
      ellipse(bx, by, 15 * fk, 15 * fk);
    }
  }

  // ---- the live count in the middle (wears the fence colour when I'm in a fence)
  fill(fenced ? fenceCol(fHue) : color(#EAFBF6));
  textAlign(CENTER, BASELINE);
  textSizeQ(96 * fk);
  text("" + n, cx, cy + 10 * fk);
  fill(#9FD9CE);
  textSizeQ(27 * fk);
  if (fenced) text(fMembers + (fMembers == 1 ? " in fence" : " in the fence"), cx, cy + 56 * fk);
  else        text(n == 1 ? "ANA device near" : "ANA devices near", cx, cy + 56 * fk);

  // ---- ANA FENCE controls, between the scope and the list
  drawFenceStrip(fenced, fName, fHue, fMembers);

  // ---- the list under the scope
  float top = FY(995), rowH = 92 * fk;
  int shown = min(rows.length, 4);
  glassCard(FX(45), top, 762 * fk, max(1, shown) * rowH + 22 * fk, 34 * fk, color(40, 120, 110));
  if (n == 0 || rows.length == 0) {
    fill(#9FD9CE);
    textAlign(CENTER, CENTER);
    textSizeQ(23 * fk);
    text("Listening… no ANA devices in range yet", FX(426), top + rowH * 0.5 + 10 * fk);
  }
  else {
    for (int i = 0; i < shown; i++) {
      String[] f = split(rows[i], ',');
      if (f.length < 3) continue;
      float y = top + 22 * fk + i * rowH;
      if (i > 0) { stroke(30, 70, 64, 160); strokeWeight(1.2 * fk); line(FX(70), y, FX(782), y); noStroke(); }
      String rfid = (f.length > 4) ? trim(f[4]) : "-";                 // this peer's fence
      boolean mem = fenced && !myFid.equals("-") && rfid.equals(myFid); // in my fence?
      fill(mem ? fenceCol(fHue) : color(#4DE2C4));
      ellipse(FX(92), y + 40 * fk, 22 * fk, 22 * fk);
      fill(#EAFBF6);
      textAlign(LEFT, BASELINE);
      textSizeQ(27 * fk);
      String nm = (f.length > 3 && trim(f[3]).length() > 0) ? trim(f[3]) : "";
      boldTextF(nm.length() > 0 ? ("ANA · " + f[0] + " · " + nm) : ("ANA · " + f[0]), FX(132), y + 36 * fk);
      fill(#9FD9CE);
      textSizeQ(21 * fk);
      int age = int(f[2]);
      text(f[1] + " dBm  ·  " + (age <= 1 ? "now" : age + "s ago"), FX(132), y + 66 * fk);
      int bars = (int) constrain(map(int(f[1]), -95, -45, 1, 4), 1, 4);  // signal strength -> 1..4 bars
      for (int b = 0; b < 4; b++) {
        fill(b < bars ? #4DE2C4 : color(40, 70, 64));
        float bh = (10 + b * 7) * fk;
        rrect(FX(716) + b * 20 * fk, y + 54 * fk - bh, 13 * fk, bh, 3 * fk);
      }
    }
  }
}

// field i of a tab-separated snapshot "count\tpeers\tmatrix" — split on EVERY tab, so the peer
// list and the matrix stay cleanly separated (a single-tab split merged them, which spawned the
// stray rows at the bottom of the list).
String rdrField(String s, int i) {
  String[] f = split(s, '\t');
  return (i >= 0 && i < f.length) ? trim(f[i]) : "";
}

// a device's blip sits at a fixed angle, from a hash of its short id
int rdrHash(String s) {
  int h = 5381;
  for (int i = 0; i < s.length(); i++) h = (h * 33 + s.charAt(i)) & 0x7FFFFFFF;
  return h;
}

// ANA FENCE strip: when I'm in a fence, a coloured banner + Leave; otherwise Create, and Join
// pills for any fence seen nearby. Tap handling in radarTap mirrors these exact rects.
void drawFenceStrip(boolean fenced, String fName, int fHue, int fMembers) {
  float y = FY(905), h = 64 * fk;
  noStroke();
  if (fenced) {
    color c = fenceCol(fHue);
    fill(red(c), green(c), blue(c), 40);
    rrect(FX(45), y, 520 * fk, h, 20 * fk);
    fill(c); ellipse(FX(80), y + h / 2, 26 * fk, 26 * fk);
    fill(#EAFBF6); textAlign(LEFT, CENTER); textSizeQ(25 * fk);
    boldTextF((fName.length() > 0 ? fName : "Fence") + "  ·  " + fMembers + " in", FX(108), y + h / 2);
    fill(60, 30, 36); rrect(FX(590), y, 218 * fk, h, 20 * fk);
    fill(#FF9BA6); textAlign(CENTER, CENTER); textSizeQ(24 * fk);
    boldTextF("Leave fence", FX(590) + 109 * fk, y + h / 2);
  } else {
    fill(20, 60, 54); rrect(FX(45), y, 300 * fk, h, 20 * fk);
    fill(#4DE2C4); textAlign(CENTER, CENTER); textSizeQ(24 * fk);
    boldTextF("+  Create fence", FX(45) + 150 * fk, y + h / 2);
    String offers = (js != null) ? js.fenceOffers() : "";
    if (offers.length() > 0) {
      String[] ofs = split(offers, ';');
      float x = FX(370);
      for (int i = 0; i < ofs.length && i < 2; i++) {
        String[] o = split(ofs[i], ',');
        if (o.length < 2) continue;
        int hue = int(o[1]); int cnt = (o.length > 2) ? int(o[2]) : 1;
        color c = fenceCol(hue);
        fill(red(c), green(c), blue(c), 45); rrect(x, y, 210 * fk, h, 20 * fk);
        fill(c); ellipse(x + 26 * fk, y + h / 2, 24 * fk, 24 * fk);
        fill(#EAFBF6); textAlign(LEFT, CENTER); textSizeQ(22 * fk);
        boldTextF("Join · " + cnt, x + 48 * fk, y + h / 2);
        x += 222 * fk;
      }
    }
  }
  noStroke();
}

void radarTap(float mx, float my) {
  poke();
  // ANA FENCE controls first (same rects as drawFenceStrip)
  String fInfo = (js != null) ? js.fenceInfo() : "";
  boolean fenced = fInfo.length() > 0;
  float fy = FY(905), fh = 64 * fk;
  if (my >= fy && my <= fy + fh) {
    if (fenced) {
      if (mx >= FX(590) && mx <= FX(590) + 218 * fk) { if (js != null) js.fenceLeave(); return; }
    } else {
      if (mx >= FX(45) && mx <= FX(45) + 300 * fk) {
        if (js != null) js.fenceCreate("Fence " + nf(hour(), 2) + nf(minute(), 2), 25, 480);
        return;
      }
      String offers = (js != null) ? js.fenceOffers() : "";
      if (offers.length() > 0) {
        String[] ofs = split(offers, ';');
        float x = FX(370);
        for (int i = 0; i < ofs.length && i < 2; i++) {
          String[] o = split(ofs[i], ',');
          if (o.length < 2) continue;
          if (mx >= x && mx <= x + 210 * fk) { if (js != null) js.fenceJoin(o[0]); return; }
          x += 222 * fk;
        }
      }
    }
  }
  // tap a device in the list -> open CHATNOTE and talk to who's nearby (discovery -> conversation)
  int n = (js != null) ? js.radarCount() : 0;
  if (n <= 0) return;
  int shown = min(n, 4);
  float top = FY(995), rowH = 92 * fk;
  if (mx >= FX(45) && mx <= FX(45) + 762 * fk && my >= top && my <= top + shown * rowH + 22 * fk) {
    chatOpen();
  }
}
