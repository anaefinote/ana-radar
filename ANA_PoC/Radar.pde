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

  // ---- blips: stronger signal sits nearer the centre; a stable angle per device from its id
  for (int i = 0; i < rows.length; i++) {
    String[] f = split(rows[i], ',');
    if (f.length < 3) continue;
    int rssi = int(f[1]), age = int(f[2]);
    float rr = constrain(map(rssi, -40, -100, 0.12, 0.95), 0.12, 0.98) * R;
    float ang = (rdrHash(f[0]) % 1000) / 1000.0 * TWO_PI;
    float bx = cx + cos(ang) * rr, by = cy + sin(ang) * rr;
    float fade = constrain(1 - age / 15.0, 0.2, 1.0);
    for (int g = 4; g >= 1; g--) {
      fill(77, 226, 196, 30 * fade);
      ellipse(bx, by, (14 + g * 7) * fk, (14 + g * 7) * fk);
    }
    fill(150, 255, 232, 235 * fade);
    ellipse(bx, by, 15 * fk, 15 * fk);
  }

  // ---- the live count in the middle
  fill(#EAFBF6);
  textAlign(CENTER, BASELINE);
  textSizeQ(96 * fk);
  text("" + n, cx, cy + 10 * fk);
  fill(#9FD9CE);
  textSizeQ(27 * fk);
  text(n == 1 ? "ANA device near" : "ANA devices near", cx, cy + 56 * fk);

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
      fill(#4DE2C4);
      ellipse(FX(92), y + 40 * fk, 22 * fk, 22 * fk);
      fill(#EAFBF6);
      textAlign(LEFT, BASELINE);
      textSizeQ(27 * fk);
      boldTextF("ANA · " + f[0], FX(132), y + 36 * fk);
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

// field i of a "count\tpeers" line (only two fields, so indexOf beats split on a tab)
String rdrField(String s, int i) {
  int t = s.indexOf('\t');
  if (i == 0) return t < 0 ? s : s.substring(0, t);
  return t < 0 ? "" : trim(s.substring(t + 1));
}

// a device's blip sits at a fixed angle, from a hash of its short id
int rdrHash(String s) {
  int h = 5381;
  for (int i = 0; i < s.length(); i++) h = (h * 33 + s.charAt(i)) & 0x7FFFFFFF;
  return h;
}

void radarTap(float mx, float my) {
  poke();                                 // keep the scope awake; room for per-device actions later
}
