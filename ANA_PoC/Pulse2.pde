// Pulse2.pde — Pulse, the flat screen (concept image 1): the bell in a glass ball with its orbit,
// today's count, Apps / Categories / Last Received, the Activity Timeline bars (-> Timeline),
// and the Recent Notifications (View All -> Archive). The round button top right is SCAN.

int pulseSeen = 0;           // notifications today when Pulse was last looked at (the red dot = new since)
int bellAt = -10000;         // the bell swings when one arrives

PImage pulseBallImg = null;   // the glass ball round the bell never changes: drawn once into an image
float pulseBallFk = -1;
PImage flatBgTopImg = null;   // the background behind the top half (the part that moves)
int pulseFullAt = -10000, pulseSig = -1;

void makePulseBall(float R) {
  int s = ceil(R * 3.2);
  PGraphics g = createGraphics(s, s, JAVA2D);
  g.beginDraw();
  g.smooth();
  g.noStroke();
  float cx = s * 0.5, cy = s * 0.5;
  for (int i = 14; i >= 1; i--) {                         // glow round the ball
    float t = i / 14.0;
    g.fill(40, 90, 200, 7);
    g.ellipse(cx, cy, 2 * R * (1 + 0.5 * t), 2 * R * (1 + 0.5 * t));
  }
  g.fill(8, 12, 26);
  g.ellipse(cx, cy, 2 * R, 2 * R);
  for (int i = 10; i >= 1; i--) {                         // body: dark centre, lit edge
    float t = i / 10.0;
    g.fill(30, 50, 100, 10);
    g.ellipse(cx + R * 0.12 * (1 - t), cy + R * 0.12 * (1 - t), 2 * R * t, 2 * R * t);
  }
  // rim: blue upper left, warm lower right
  g.noFill();
  for (int i0 = 0; i0 < 72; i0 += 6) {
    float am = TWO_PI * (i0 + 3) / 72;
    float k = (cos(am - 0.8) + 1) * 0.5;
    color c = lerpColor(color(70, 140, 255), color(255, 170, 80), k);
    g.stroke(red(c), green(c), blue(c), 60 + 140 * max(k, 1 - k));
    g.strokeWeight(2.2 * fk);
    g.beginShape();
    for (int i = i0; i <= i0 + 6; i++) g.vertex(cx + cos(TWO_PI * i / 72) * R, cy + sin(TWO_PI * i / 72) * R);
    g.endShape();
  }
  g.noStroke();
  for (int i = 0; i < 8; i++) {                           // window reflection
    g.fill(255, 255, 255, 8);
    g.ellipse(cx - R * 0.35, cy - R * 0.52, R * (0.7 - i * 0.05), R * (0.3 - i * 0.02));
  }
  g.endDraw();
  pulseBallImg = g.get();
  pulseBallFk = fk;
}

// Pulse's top (the bell, its orbit and comets, the count) moves all the time; the rest only when something
// changes. Between those changes only the top is redrawn (and the bar under it is left as it is).
boolean pulsePartial() {
  int sig = entries.size() * 7 + pulseSeen * 13 + floor(millis() / 1000.0);
  if (readerE != null || sig != pulseSig || millis() - lastInputAt < 1500 || millis() - appMsgAt < 2600 || armed || mousePressed) {
    pulseSig = sig;
    return false;
  }
  return true;
}

void drawPulse2() {
  drawPulse2(false);
}

void drawPulse2(boolean partial) {
  if (partial) {
    if (flatBgTopImg == null || flatBgTopImg.width != width) flatBgTopImg = flatBgImg.get(0, 0, width, round(FY(745)));
    image(flatBgTopImg, 0, 0);
  }
  else image(flatBgImg, 0, 0);
  flatHeader(appTitle(), "Notification Compiler", false);

  // SCAN button (top right)
  float bx = FX(764), by = FY(137), br = 40 * fk;
  fill(14, 20, 38, 240);
  ellipse(bx, by, 2 * br, 2 * br);
  stroke(60, 90, 150, 140);
  strokeWeight(1.4 * fk);
  noFill();
  ellipse(bx, by, 2 * br, 2 * br);
  noStroke();
  if (onIOS) {                                   // iOS: + adds an entry by hand (there's nothing to scan)
    stroke(#4DB5FF);
    strokeWeight(3.2 * fk);
    line(bx - 15 * fk, by, bx + 15 * fk, by);
    line(bx, by - 15 * fk, bx, by + 15 * fk);
    noStroke();
  }
  else icoRefresh(bx, by, 17 * fk, #4DB5FF);

  // the bell ball with its orbit
  float cx = FX(430), cy = FY(400), R = 125 * fk;
  pulseOrbit(cx, cy, false);
  if (pulseBallImg == null || pulseBallFk != fk) makePulseBall(R);
  image(pulseBallImg, cx - pulseBallImg.width * 0.5, cy - pulseBallImg.height * 0.5);
  // the bell, swinging when something arrives
  float sw = 0;
  int since = millis() - bellAt;
  if (since < 1400) sw = sin(since / 70.0) * 0.32 * (1 - since / 1400.0);
  pushMatrix();
  translate(cx, cy - R * 0.38);
  rotate(sw);
  for (int i = 6; i >= 1; i--) {
    fill(200, 220, 255, 10);
    ellipse(0, R * 0.38, R * (0.9 + i * 0.12), R * (0.9 + i * 0.12));
  }
  icoBell(0, R * 0.38, R * 0.42, #E8EEFA);
  popMatrix();
  int nT = countToday();
  if (nT > pulseSeen) {                                   // new since you last looked
    for (int i = 5; i >= 1; i--) {
      fill(255, 60, 60, 26);
      ellipse(cx + R * 0.33, cy - R * 0.36, (26 + i * 7) * fk, (26 + i * 7) * fk);
    }
    fill(#FF3B3B);
    ellipse(cx + R * 0.33, cy - R * 0.36, 28 * fk, 28 * fk);
  }
  pulseOrbit(cx, cy, true);

  // count
  fill(#F4F7FF);
  textAlign(CENTER, BASELINE);
  textSizeQ(104 * fk);
  text("" + nT, FX(426) - 1.6 * fk, FY(672));
  text("" + nT, FX(426) + 1.6 * fk, FY(672));
  fill(#C9D3E6);
  textSizeQ(32 * fk);
  text("Notifications Today", FX(426), FY(718));
  if (partial) return;
  if (armed) {
    fill(#3DDC97);
    textSizeQ(20 * fk);
    text(armedHit.length() > 0 ? "ARMED  ·  " + armedHit : "ARMED  ·  waiting " + nf((millis() - armedAt) / 1000.0, 1, 1) + "s", FX(426), FY(752));
  }

  // Apps / Categories / Last Received
  glassCard(FX(45), FY(768), 762 * fk, 167 * fk, 44 * fk, color(70, 90, 200));
  String td = today();
  ArrayList pk = new ArrayList();
  String cats = "|";
  int nCat = 0;
  int secs = -1;
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!e.ymd.equals(td) || e.src.equals("SYS") || e.src.equals("MANUAL")) continue;
    if (secs < 0 && (e.src.equals("LIVE") || e.src.equals("SCAN"))) secs = secondsAgo(e);
    if (pk.indexOf(e.pkg) >= 0) continue;
    pk.add(e.pkg);
    AppIcon a = appFor(e.pkg);
    appInfo(a);
    if (a.cat.length() > 0 && cats.indexOf("|" + a.cat + "|") < 0) { cats += a.cat + "|"; nCat++; }
  }
  stroke(50, 60, 90, 120);
  strokeWeight(1.2 * fk);
  line(FX(297), FY(800), FX(297), FY(905));
  line(FX(558), FY(800), FX(558), FY(905));
  noStroke();
  icoGrid(FX(170), FY(810), 17 * fk, #3D8BFF);
  icoFolder(FX(427), FY(812), 17 * fk, #8B6CFF);
  icoClock(FX(687), FY(810), 16 * fk, #FFB23D);
  fill(#F4F7FF);
  textAlign(CENTER, BASELINE);
  textSizeQ(38 * fk);
  boldTextF("" + pk.size(), FX(170), FY(875));
  boldTextF("" + nCat, FX(427), FY(875));
  boldTextF(secs < 0 ? "-" : ago(secs), FX(687), FY(875));
  fill(#C9D3E6);
  textSizeQ(23 * fk);
  text("Apps", FX(170), FY(910));
  text("Categories", FX(427), FY(910));
  text("Last Received", FX(687), FY(910));

  // Activity Timeline
  glassCard(FX(45), FY(985), 762 * fk, 312 * fk, 44 * fk, color(110, 80, 220));
  icoWave(FX(112), FY(1055), 22 * fk, #B05CFF);
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(30 * fk);
  boldTextF("Activity Timeline", FX(180), FY(1053));
  fill(#9AA6C0);
  textSizeQ(22 * fk);
  text(nT == 0 ? "Quiet so far" : nT < 20 ? "A calm day so far" : nT < 80 ? "A steady day so far" : "A busy day so far", FX(180), FY(1088));
  fill(30, 36, 52);
  ellipse(FX(748), FY(1050), 58 * fk, 58 * fk);
  chevronRight(FX(750), FY(1050), 18 * fk, #C9D3E6);
  int[] bins = new int[24];
  int mx = 1;
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!e.ymd.equals(td) || e.src.equals("SYS") || e.time.length() < 2) continue;
    int h = int(e.time.substring(0, 2));
    if (h >= 0 && h < 24) { bins[h]++; mx = max(mx, bins[h]); }
  }
  int nowH = hour();
  for (int h = 0; h < 24; h++) {
    float x = FX(86 + h * 28.5), w = 16 * fk;
    float hh = bins[h] == 0 ? 22 : 22 + 88.0 * bins[h] / mx;
    float y0 = FY(1222);
    float f = h / 23.0;
    color c = f < 0.5 ? lerpColor(color(40, 110, 255), color(150, 90, 255), f * 2) : lerpColor(color(170, 90, 255), color(255, 175, 60), (f - 0.5) * 2);
    if (bins[h] == 0) c = h > nowH ? color(20, 26, 40) : color(22, 40, 80);
    else {
      for (int i = 3; i >= 1; i--) {
        fill(red(c), green(c), blue(c), 22);
        rrect(x - i * 3 * fk, y0 - hh * fk - i * 3 * fk, w + i * 6 * fk, hh * fk + i * 3 * fk, (w + i * 6 * fk) * 0.4);
      }
    }
    fill(c);
    rrect(x, y0 - hh * fk, w, hh * fk, w * 0.35);
    if (bins[h] > 0) {
      fill(255, 255, 255, 140);
      rrect(x + 3 * fk, y0 - hh * fk + 2 * fk, w - 6 * fk, 6 * fk, 3 * fk);
    }
  }
  fill(#9AA6C0);
  textAlign(CENTER, BASELINE);
  textSizeQ(21 * fk);
  text("12AM", FX(102), FY(1262));
  text("6AM", FX(264), FY(1262));
  text("12PM", FX(425), FY(1262));
  text("6PM", FX(587), FY(1262));
  text("12AM", FX(748), FY(1262));

  // Recent Notifications
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(31 * fk);
  boldTextF("Recent Notifications", FX(45), FY(1384));
  fill(#9AA6C0);
  textAlign(RIGHT, BASELINE);
  textSizeQ(24 * fk);
  text("View All", FX(770), FY(1382));
  chevronRight(FX(795), FY(1373), 18 * fk, #9AA6C0);

  ArrayList rec = new ArrayList();
  for (int i = 0; i < entries.size() && rec.size() < 8; i++) {
    Entry e = (Entry) entries.get(i);
    if (e.src.equals("SYS") || !passes(e)) continue;
    rec.add(e);
  }
  float rowH = 106 * fk, top = FY(1422);
  int rows = min(rec.size(), max(1, floor((barY - 10 * u - top) / rowH)));
  if (rec.size() == 0) {
    glassCard(FX(45), top, 762 * fk, rowH, 34 * fk, color(60, 80, 140));
    fill(#9AA6C0);
    textAlign(CENTER, CENTER);
    textSizeQ(23 * fk);
    text(entries.size() == 0 ? (onIOS ? "Nothing yet: tap + (top right) to add an entry" : "Nothing yet: Settings > Notification access, then SCAN") : "Nothing from the picked apps yet", FX(426), top + rowH * 0.5);
  }
  else {
    glassCard(FX(45), top, 762 * fk, rows * rowH, 34 * fk, color(60, 80, 140));
    for (int i = 0; i < rows; i++) {
      Entry e = (Entry) rec.get(i);
      float y = top + i * rowH;
      if (i > 0) {
        stroke(40, 50, 75, 160);
        strokeWeight(1.2 * fk);
        line(FX(45), y, FX(807), y);
        noStroke();
      }
      AppIcon a = appFor(e.pkg);
      drawAppIconAt(a, FX(82), y + 22 * fk, 62 * fk);
      fill(#F4F7FF);
      textAlign(LEFT, BASELINE);
      textSizeQ(28 * fk);
      String name = e.src.equals("MANUAL") ? "Manual entry" : a.label;
      boolean ip = e.src.equals("IPHONE");
      boldTextF(fitText(name, ip ? 300 * fk : 420 * fk), FX(175), y + 46 * fk);
      if (ip) iphoneTag(FX(175) + min(textWidthAt(name, 28 * fk), 300 * fk) + 14 * fk, y + 36 * fk, 30 * fk);
      fill(#C9D3E6);
      textSizeQ(23 * fk);
      String body = e.title.length() > 0 && !e.title.equals(name) ? e.title + ": " + e.body : e.body;
      text(fitText(body, 560 * fk), FX(175), y + 82 * fk);
      fill(#9AA6C0);
      textAlign(RIGHT, BASELINE);
      textSizeQ(22 * fk);
      text(ago(secondsAgo(e)) + " ago", FX(757), y + 46 * fk);
      fill(#2F8BFF);
      ellipse(FX(780), y + 38 * fk, 12 * fk, 12 * fk);
    }
  }
}

// the orbit round the bell ball: back half before the ball, front half after
void pulseOrbit(float cx, float cy, boolean front) {
  float tilt = -0.42;
  pulseRing(cx, cy, 300 * fk, 104 * fk, tilt, front, 4.6, 1.0);
  pulseRing(cx, cy + 10 * fk, 270 * fk, 120 * fk, tilt + 0.1, front, 1.6, 0.6);
  pulseRing(cx - 10 * fk, cy + 18 * fk, 330 * fk, 90 * fk, tilt - 0.06, front, 1.2, 0.4);
}

void pulseRing(float cx, float cy, float rx, float ry, float tilt, boolean front, float w, float bright) {
  int N = 120, RUN = 10;
  float ct = cos(tilt), st = sin(tilt);
  float comet = (millis() / 3000.0) % 1.0 * TWO_PI;
  noFill();
  for (int pass = 0; pass < 2; pass++) {
    for (int i0 = 0; i0 < N; i0 += RUN) {
      float tm = TWO_PI * (i0 + RUN * 0.5) / N;
      if ((sin(tm) > 0) != front) continue;
      float k = (cos(tm) + 1) * 0.5;                       // left blue, right gold (concept image 1)
      color c = k < 0.5 ? lerpColor(color(60, 150, 255), color(140, 90, 255), k * 2) : lerpColor(color(170, 100, 255), color(255, 170, 70), (k - 0.5) * 2);
      float d = abs(atan2(sin(tm - comet), cos(tm - comet)));
      float hot = max(0, 1 - d / 1.3);
      float al = (0.6 + 0.4 * hot) * bright * (front ? 1.0 : 0.55);
      if (pass == 0) { stroke(red(c), green(c), blue(c), 50 * al); strokeWeight((w * 5 + hot * 10) * fk); }
      else { stroke(min(255, red(c) + 60), min(255, green(c) + 60), min(255, blue(c) + 60), 255 * al); strokeWeight((w + hot * 1.5) * fk); }
      beginShape();
      for (int i = i0; i <= i0 + RUN; i++) {
        float t = TWO_PI * i / N;
        float ex = cos(t) * rx, ey = sin(t) * ry;
        vertex(cx + ex * ct - ey * st, cy + ex * st + ey * ct);
      }
      endShape();
    }
  }
  noStroke();
}

// taps on Pulse
void pulseTap(float mx, float my) {
  if (dist(mx, my, FX(764), FY(137)) < 50 * fk) { act(onIOS ? C_MANUAL : C_SCAN); bellAt = millis(); return; }
  if (dist(mx, my, FX(430), FY(400)) < 130 * fk) { pulseSeen = countToday(); bellAt = millis(); return; }
  if (my > FY(985) && my < FY(1297) && mx > FX(45) && mx < FX(807)) { setTab(T_TIMELINE); tlDay = today(); return; }
  if (my > FY(1340) && my < FY(1400) && mx > FX(600)) { setTab(T_ARCHIVE); return; }
  float rowH = 106 * fk, top = FY(1422);
  if (my > top) {
    int i = floor((my - top) / rowH);
    int n = 0;
    for (int k = 0; k < entries.size(); k++) {
      Entry e = (Entry) entries.get(k);
      if (e.src.equals("SYS") || !passes(e)) continue;
      if (n == i) {
        openReader(e);                        // read it in full (Reader.pde)
        return;
      }
      n++;
    }
  }
}
