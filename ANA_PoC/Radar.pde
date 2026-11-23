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
  int fHue = 0, fMembers = 0, fRole = 0;      // role 0 member / 1 host / 2 knocking
  if (fenced) {
    String[] fi = split(fInfo, '\t');
    if (fi.length >= 5) { myFid = fi[0]; fName = fi[1]; fHue = int(fi[2]); fRole = int(fi[3]); fMembers = int(fi[4]); }
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
  if (fRole == 2)   text("waiting to be let in", cx, cy + 56 * fk);
  else if (fenced)  text(fMembers + (fMembers == 1 ? " in fence" : " in the fence"), cx, cy + 56 * fk);
  else              text(n == 1 ? "ANA device near" : "ANA devices near", cx, cy + 56 * fk);

  drawReachable(cx, cy, R);                         // PRESENCE MESH: ANAs reachable over Wi-Fi (ghosted outer arc)
  drawTailnet(cx, cy, R);                            // PRESENCE MESH: tailnet peers reachable over Tailscale (violet list)
  // ---- ANA FENCE controls, between the scope and the list
  drawFenceStrip(fenced, fRole, fName, fHue, fMembers);
  coSignPoll();                                     // catch an incoming co-sign request/reply
  flashDraw();

  // ---- host gate takes the list's place while someone's knocking; otherwise the device list
  String knockers = (fenced && fRole == 1 && js != null) ? js.fenceKnockers() : "";
  if (knockers.length() > 0) {
    drawHostGate(knockers, fHue);
  } else {
    float top = FY(995), rowH = 92 * fk;
    int shown = min(rows.length, 4);
    glassCard(FX(45), top, 762 * fk, max(1, shown) * rowH + 22 * fk, 34 * fk, color(40, 120, 110));
    if (n == 0 || rows.length == 0) {
      fill(#9FD9CE);
      textAlign(CENTER, CENTER);
      textSizeQ(23 * fk);
      text("Listening… no ANA devices in range yet", FX(426), top + rowH * 0.5 + 10 * fk);
    } else {
      for (int i = 0; i < shown; i++) {
        String[] f = split(rows[i], ',');
        if (f.length < 3) continue;
        float y = top + 22 * fk + i * rowH;
        if (i > 0) { stroke(30, 70, 64, 160); strokeWeight(1.2 * fk); line(FX(70), y, FX(782), y); noStroke(); }
        String rfid = (f.length > 4) ? trim(f[4]) : "-";
        int tier = fenceTier(rfid, myFid, fenced);          // 0 stranger, 1 member, 2 knocker
        color dot = tier == 1 ? fenceCol(fHue) : (tier == 2 ? color(#C9922E) : color(#4DE2C4));
        fill(dot);
        ellipse(FX(92), y + 40 * fk, 22 * fk, 22 * fk);
        fill(#EAFBF6);
        textAlign(LEFT, BASELINE);
        textSizeQ(27 * fk);
        String nm = (f.length > 3 && trim(f[3]).length() > 0) ? trim(f[3]) : "";
        boldTextF(nm.length() > 0 ? ("ANA · " + f[0] + " · " + nm) : ("ANA · " + f[0]), FX(132), y + 36 * fk);
        fill(#9FD9CE);
        textSizeQ(21 * fk);
        int age = int(f[2]);
        String tag = tier == 1 ? "  ·  in fence" : (tier == 2 ? "  ·  knocking" : "");
        text(f[1] + " dBm  ·  " + (age <= 1 ? "now" : age + "s ago") + tag, FX(132), y + 66 * fk);
        int bars = (int) constrain(map(int(f[1]), -95, -45, 1, 4), 1, 4);
        for (int b = 0; b < 4; b++) {
          fill(b < bars ? dot : color(40, 70, 64));
          float bh = (10 + b * 7) * fk;
          rrect(FX(716) + b * 20 * fk, y + 54 * fk - bh, 13 * fk, bh, 3 * fk);
        }
      }
    }
  }
}

// which tier a peer's fence tag puts it in, from my own fence's perspective
int fenceTier(String rfid, String myFid, boolean fenced) {
  if (!fenced || myFid.equals("-")) return 0;
  if (rfid.equals(myFid)) return 1;            // broadcasting my fence -> member
  if (rfid.equals("?" + myFid)) return 2;      // knocking on my fence
  return 0;                                    // stranger / other fence
}

// host gate: up to two accept/decline cards where the device list would be
void drawHostGate(String knockers, int fHue) {
  String[] ks = split(knockers, ';');
  float top = FY(995);
  int shown = min(ks.length, 2);
  for (int i = 0; i < shown; i++) {
    String[] k = split(ks[i], ',');
    if (k.length < 1 || trim(k[0]).length() == 0) continue;
    float y = top + i * (128 * fk);
    glassCard(FX(45), y, 762 * fk, 110 * fk, 28 * fk, color(150, 110, 40));
    fill(#C9922E); ellipse(FX(88), y + 36 * fk, 22 * fk, 22 * fk);
    fill(#F0D79A); textAlign(LEFT, BASELINE); textSizeQ(26 * fk);
    String nm = (k.length > 2 && trim(k[2]).length() > 0) ? trim(k[2]) : "Guest";
    boldTextF(nm + " · " + k[0] + "  wants in", FX(120), y + 44 * fk);
    fill(18, 58, 44); rrect(FX(70), y + 58 * fk, 330 * fk, 42 * fk, 12 * fk);
    fill(#7CE0BB); textAlign(CENTER, CENTER); textSizeQ(23 * fk); boldTextF("Accept", FX(70) + 165 * fk, y + 80 * fk);
    fill(52, 28, 32); rrect(FX(432), y + 58 * fk, 330 * fk, 42 * fk, 12 * fk);
    fill(#FF9BA6); boldTextF("Decline", FX(432) + 165 * fk, y + 80 * fk);
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

// ANA FENCE strip. States: not fenced -> Create + Request pills; knocking (role 2) -> waiting +
// Cancel; member/host (role 0/1) -> banner + Leave. Tap handling in radarTap mirrors these rects.
void drawFenceStrip(boolean fenced, int fRole, String fName, int fHue, int fMembers) {
  float y = FY(905), h = 64 * fk;
  noStroke();
  if (fenced && fRole == 2) {                  // knocking — waiting to be let in
    color c = fenceCol(fHue);
    fill(red(c), green(c), blue(c), 40);
    rrect(FX(45), y, 520 * fk, h, 20 * fk);
    fill(#F0D79A); textAlign(LEFT, CENTER); textSizeQ(24 * fk);
    boldTextF("Requested  ·  waiting for host", FX(72), y + h / 2);
    fill(60, 30, 36); rrect(FX(590), y, 218 * fk, h, 20 * fk);
    fill(#FF9BA6); textAlign(CENTER, CENTER); textSizeQ(24 * fk);
    boldTextF("Cancel", FX(590) + 109 * fk, y + h / 2);
  } else if (fenced) {                         // member or host — banner + Leave (+ Seal for host)
    color c = fenceCol(fHue);
    float bw = (fRole == 1) ? 360 * fk : 520 * fk;   // host leaves room for a Seal button
    fill(red(c), green(c), blue(c), 40);
    rrect(FX(45), y, bw, h, 20 * fk);
    fill(c); ellipse(FX(80), y + h / 2, 26 * fk, 26 * fk);
    fill(#EAFBF6); textAlign(LEFT, CENTER); textSizeQ(fRole == 1 ? 21 * fk : 24 * fk);
    String tag = fRole == 1 ? "  ·  host" : "";
    boldTextF((fName.length() > 0 ? fName : "Fence") + "  ·  " + fMembers + tag, FX(108), y + h / 2);
    if (fRole == 1) {                          // Seal: sign the roster + export as pngmesh
      fill(18, 70, 58); rrect(FX(420), y, 150 * fk, h, 20 * fk);
      fill(#7CE0BB); textAlign(CENTER, CENTER); textSizeQ(23 * fk);
      boldTextF("Seal", FX(420) + 75 * fk, y + h / 2);
    }
    fill(60, 30, 36); rrect(FX(590), y, 218 * fk, h, 20 * fk);
    fill(#FF9BA6); textAlign(CENTER, CENTER); textSizeQ(24 * fk);
    boldTextF("Leave fence", FX(590) + 109 * fk, y + h / 2);
  } else {                                     // no fence — Create + Request pills
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
        boldTextF("Knock · " + cnt, x + 48 * fk, y + h / 2);
        x += 222 * fk;
      }
    }
  }
  noStroke();
}

// ---- PRESENCE MESH (slice 1): ANAs reachable over Wi-Fi, shown as ghosted dots on an OUTER arc above
// the scope. They are "reachable", not "near" — no RSSI, no distance claim. Discovery is Bonjour/NSD
// (the same the CHATNOTE listener announces). v1: show only; no dedupe-with-Bluetooth yet.
String lanCache = "";
int lanAt = 0;
void drawReachable(float cx, float cy, float R) {
  if (js == null) return;
  if (frameCount >= lanAt) { lanAt = frameCount + 20; lanCache = js.lanPeers(); }   // ~3x/sec
  if (lanCache == null || lanCache.length() == 0) return;
  String[] ps = split(lanCache, ';');
  int n = ps.length;
  float rr = R * 1.16;
  textAlign(CENTER, CENTER);
  for (int i = 0; i < n; i++) {
    String[] tn = split(ps[i], '~');
    String nm = (tn.length > 1 && tn[1].length() > 0) ? tn[1] : ps[i];
    float a = (n == 1) ? -HALF_PI : map(i, 0, n - 1, PI + 0.55, TWO_PI - 0.55);
    float x = cx + cos(a) * rr, y = cy + sin(a) * rr;
    noFill();
    stroke(127, 176, 255, 150);
    strokeWeight(2 * fk);
    ellipse(x, y, 26 * fk, 26 * fk);
    noStroke();
    fill(127, 176, 255, 55);
    ellipse(x, y, 26 * fk, 26 * fk);
    fill(127, 176, 255, 220);
    textSizeQ(16 * fk);
    text(nm, x, y - 26 * fk);
  }
  fill(127, 176, 255, 170);
  textSizeQ(15 * fk);
  text("· reachable on Wi-Fi ·", cx, cy - rr - 36 * fk);
}

// ---- PRESENCE MESH (slice 2): tailnet (Tailscale) peers — the longest carry layer. The tailnet is the
// directory (added by address, no WAN auto-discovery), so these are a small list off the scope, violet,
// live/stale by a reachability ping. Reachable via Tailscale — never "near". A "+" adds one by address.
String tailCache = "";
int tailAt = 0;
float tailAddX, tailAddY, tailAddW, tailAddH;      // the "+ Tailscale peer" chip rect, for the tap test
void drawTailnet(float cx, float cy, float R) {
  if (js == null) return;
  if (frameCount >= tailAt) { tailAt = frameCount + 25; tailCache = js.tailPeers(); }
  tailAddX = FX(557); tailAddY = FY(150); tailAddW = 250 * fk; tailAddH = 52 * fk;   // top-right, flush to the content margin — off the ANA header text
  fill(20, 24, 40, 230);
  rrect(tailAddX, tailAddY, tailAddW, tailAddH, 14 * fk);
  fill(#B9A7FF);
  textAlign(CENTER, CENTER);
  textSizeQ(19 * fk);
  text("+ Tailscale peer", tailAddX + tailAddW / 2, tailAddY + tailAddH / 2);
  if (tailCache == null || tailCache.length() == 0) return;
  String[] ps = split(tailCache, ';');
  for (int i = 0; i < ps.length; i++) {
    String[] f = split(ps[i], '~');
    String nm = (f.length > 1 && f[1].length() > 0) ? f[1] : ps[i];
    boolean live = f.length > 2 && f[2].equals("1");
    float y = tailAddY + 64 * fk + i * 46 * fk;
    fill(live ? color(90, 200, 150) : color(90, 90, 104));
    ellipse(FX(60), y, 15 * fk, 15 * fk);
    fill(live ? color(185, 167, 255, 235) : color(150, 150, 170, 170));
    textAlign(LEFT, CENTER);
    textSizeQ(18 * fk);
    text(nm + (live ? "" : "  (offline)"), FX(80), y);
  }
  fill(185, 167, 255, 150);
  textAlign(LEFT, CENTER);
  textSizeQ(14 * fk);
  text("via Tailscale", FX(50), tailAddY + 64 * fk + ps.length * 46 * fk + 6 * fk);
}

// Seal the fence: write a signed record of who was inside, over the window, as a pngmesh + sha256.
// The signed roster IS the seal (v0.3) — host signs it with its FLEX key; anyone can verify later.
void fenceSeal() {
  if (js == null) return;
  String fInfo = js.fenceInfo();
  if (fInfo.length() == 0) return;
  String[] fi = split(fInfo, '\t');
  if (fi.length < 2) return;
  String fid = fi[0], name = fi[1];
  String data = js.radarPeers();
  String ps = rdrField(data, 1);
  String[] rows = ps.length() == 0 ? new String[0] : split(ps, ';');

  // Plain String, not StringBuilder: Processing.js (the sketch's runtime in the WebView) has no
  // java.lang.StringBuilder, so new StringBuilder() threw here and the whole seal silently died.
  String b = "ANASEAL1\n";
  b += "fence: " + fid + "  " + name + "\n";
  b += "sealed: " + nf(year(), 4) + "-" + nf(month(), 2) + "-" + nf(day(), 2) +
       " " + nf(hour(), 2) + ":" + nf(minute(), 2) + "\n";
  b += "host_key: " + js.flexKey() + "\n";
  b += "member: host  " + gMyName + "\n";
  for (int i = 0; i < rows.length; i++) {
    String[] f = split(rows[i], ',');
    if (f.length < 5) continue;
    if (trim(f[4]).equals(fid)) {
      String nm = (f.length > 3 && trim(f[3]).length() > 0) ? trim(f[3]) : "";
      b += "member: " + f[0] + "  " + nm + "\n";
    }
  }
  String sig = js.flexSign(b);                     // host signs the whole roster
  b += "sig: " + sig + "\n";
  b += "sha256: " + js.flexHash(b) + "\n";
  js.sealExport(b);                                // seal the payload itself -> .pngmesh + .sha256, shareable
}

void radarTap(float mx, float my) {
  poke();
  // "+ Tailscale peer" chip (presence mesh): add a tailnet peer by address
  if (js != null && mx >= tailAddX && mx <= tailAddX + tailAddW && my >= tailAddY && my <= tailAddY + tailAddH) {
    js.tailAdd();
    return;
  }
  String fInfo = (js != null) ? js.fenceInfo() : "";
  boolean fenced = fInfo.length() > 0;
  int fRole = 0; String myFid = "-";
  if (fenced) { String[] fi = split(fInfo, '\t'); if (fi.length >= 5) { myFid = fi[0]; fRole = int(fi[3]); } }

  // ---- fence strip row
  float fy = FY(905), fh = 64 * fk;
  if (my >= fy && my <= fy + fh) {
    if (fenced && fRole == 2) {                          // waiting: Cancel
      if (mx >= FX(590) && mx <= FX(590) + 218 * fk) { if (js != null) js.fenceLeave(); return; }
    } else if (fenced) {                                 // member/host: Seal (host) + Leave
      if (fRole == 1 && mx >= FX(420) && mx <= FX(420) + 150 * fk) { fenceSeal(); return; }
      if (mx >= FX(590) && mx <= FX(590) + 218 * fk) { if (js != null) js.fenceLeave(); return; }
    } else {                                             // Create + knock pills
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
          if (mx >= x && mx <= x + 210 * fk) { if (js != null) js.fenceRequest(o[0]); return; }
          x += 222 * fk;
        }
      }
    }
  }

  // ---- host gate: Accept / Decline on knocker cards (same rects as drawHostGate)
  String knockers = (fenced && fRole == 1 && js != null) ? js.fenceKnockers() : "";
  if (knockers.length() > 0) {
    String[] ks = split(knockers, ';');
    float top = FY(995);
    for (int i = 0; i < ks.length && i < 2; i++) {
      String[] k = split(ks[i], ',');
      if (k.length < 1 || trim(k[0]).length() == 0) continue;
      float y = top + i * (128 * fk);
      float by = y + 58 * fk, bh = 42 * fk;
      if (my >= by && my <= by + bh) {
        if (mx >= FX(70) && mx <= FX(70) + 330 * fk) { if (js != null) js.fenceAccept(k[0]); return; }
        if (mx >= FX(432) && mx <= FX(432) + 330 * fk) { if (js != null) js.fenceDecline(k[0]); return; }
      }
    }
    return;                                              // gate is showing; no list to tap
  }

  // ---- tap a device in the list -> open CHATNOTE
  int n = (js != null) ? js.radarCount() : 0;
  if (n <= 0) return;
  int shown = min(n, 4);
  float top = FY(995), rowH = 92 * fk;
  if (mx >= FX(45) && mx <= FX(45) + 762 * fk && my >= top && my <= top + shown * rowH + 22 * fk) {
    chatOpen();
  }
}
