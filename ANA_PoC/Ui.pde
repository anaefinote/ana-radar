// Ui.pde — the flat screens' shared look (Pulse, Archive / EFINOTE, Timeline, Settings).
// Positions on those screens are in the concept images' pixels (852 px wide), scaled by fk to this
// screen and drawn at 100% device pixels: FX(x), FY(y), fk * size.

String VERSION = "0.11-ios-orbit";

// ANA : STATIA (ANA's big sister) shares this sketch; the page says which one is running
String editionName = null;
boolean statia() {
  if (editionName == null && js != null) { editionName = js.edition(); if (editionName == null) editionName = ""; }
  return "statia".equals(editionName);
}
String appTitle() { return statia() ? "ANA : STATIA" : "ANA"; }

boolean ballOn = false;          // the control ball (Settings > ANA > Control ball): off by default
float fk = 1, fX0 = 0, fY0 = 0;
PGraphics flatBg;
PImage flatBgImg;                 // flatBg as a plain image: drawing a PGraphics copies all its pixels every frame
// text sizes rounded to whole pixels: Processing.js measures a font's pixels the first time each size is
// used, so fractional sizes (20 * fk, or a size that follows the zoom) kept it measuring, frame after frame
void textSizeQ(float s) { textSize(max(1, round(s))); }

// the blue "iPhone" tag on an entry that came from the iPhone over Bluetooth: a phone, then the word.
// x = its left edge, cy = its centre line, h = its height. Returns its width.
float iphoneTag(float x, float cy, float h) {
  textSizeQ(h * 0.56);
  float w = h * 0.85 + textWidth("iPhone") + h * 0.45;
  noStroke();
  fill(#13243A);
  rrect(x, cy - h * 0.5, w, h, h * 0.5);
  float gx = x + h * 0.48, gw = h * 0.32, gh = h * 0.58;
  stroke(#4DA3FF);
  strokeWeight(max(1, h * 0.07));
  rrectLine(gx - gw * 0.5, cy - gh * 0.5, gw, gh, gw * 0.28);
  noStroke();
  fill(#4DA3FF);
  ellipse(gx, cy + gh * 0.3, h * 0.07, h * 0.07);
  fill(#9CCBFF);
  textAlign(LEFT, CENTER);
  text("iPhone", x + h * 0.85, cy - h * 0.05);
  textAlign(LEFT, BASELINE);
  return w;
}

int iconBudget = 2;
int iconWaitAt = -10000;

// ---- the frame governor: a frame is only drawn when it can look different.
// While you touch the screen, something animates or something arrives: every frame. A still screen is
// redrawn once a second (for "52s ago" and the clocks). Skipping draw() keeps the last picture on screen.
int lastInputAt = 0, lastDrawAt = -10000, frameSig = 0;

void poke() { lastInputAt = millis(); }

boolean frameWanted() {
  int now = millis();
  int sig = entries.size() * 31 + tab * 7 + watch.size() * 131 + (filterOn ? 1 : 0) + status.length() * 1009 + skin * 3;
  if (sig != frameSig) { frameSig = sig; poke(); }
  if (mousePressed || now - lastInputAt < 1500 || now - appMsgAt < 2600 || now - iconWaitAt < 3000 || chatOn) return true;
  return now - lastDrawAt >= idleInterval();
}

// how often a screen that nobody is touching is redrawn (0 = every frame)
int idleInterval() {
  if (tab == T_APPIFY) return showList ? 1000 : 33;          // the icon ball turns slowly on its own: 30 fps
  if (!flatTab()) return 0;                                   // the control-ball screens: as before
  if (tab == T_PULSE) return 33;                              // the comet round the bell: 30 fps
  if (tab == T_ARCHIVE) return mazeBusy() ? 0 : mzSel != null ? 50 : 1000;
  if (tab == T_SETTINGS && armed) return 100;                 // the arm test's timer
  return 1000;
}              // app icons asked for per frame (each is a call to the phone)

float FX(float x) { return fX0 + x * fk; }
float FY(float y) { return fY0 + y * fk; }

void flatLayout() {
  fk = min(width / 852.0, (barY - 8 * u) / 1580.0);
  fX0 = (width - 852 * fk) * 0.5;
  fY0 = -70 * fk;
  flatBg = createGraphics(width, height, JAVA2D);
  flatBg.beginDraw();
  flatBg.smooth();
  flatBg.background(#05070C);
  flatBg.noStroke();
  for (int i = 30; i >= 1; i--) {                        // soft blue haze top right, violet low left
    float t = i / 30.0;
    flatBg.fill(30, 70, 190, 4);
    flatBg.ellipse(width * 0.78, height * 0.12, width * 1.1 * t, width * 0.9 * t);
    flatBg.fill(90, 50, 170, 3);
    flatBg.ellipse(width * 0.1, height * 0.62, width * 0.9 * t, width * 0.9 * t);
  }
  randomSeed(7);
  for (int i = 0; i < 70; i++) {                          // a few stars
    flatBg.fill(150, 180, 255, random(25, 110));
    float s = random(1, 2.6) * fk;
    flatBg.ellipse(random(width), random(height), s, s);
  }
  flatBg.endDraw();
  flatBgImg = flatBg.get();
  flatBgTopImg = null;
  pulseBallImg = null;
}

// app icon (or a lettered tile until it arrives), x y = top left
void drawAppIconAt(AppIcon a, float x, float y, float s) {
  appInfo(a);
  if (!a.ready) iconWaitAt = millis();          // an icon still coming: keep drawing until it shows
  if (!a.asked && iconBudget > 0) {
    iconBudget--;
    a.asked = true;
    if (js != null) {
      String d = js.appIcon(a.pkg);
      if (d.length() > 0) a.img = loadImage(d);
    }
  }
  if (!a.ready && a.img != null && a.img.width > 0) {
    a.ready = true;
    a.glow = averageColour(a.img);
  }
  if (a.ready) image(a.img, x, y, s, s);
  else {
    fill(pkgColour(a.pkg));
    rrect(x, y, s, s, s * 0.24);
    fill(255);
    textAlign(CENTER, CENTER);
    textSizeQ(s * 0.46);
    text(a.label.length() > 0 ? a.label.substring(0, 1).toUpperCase() : "?", x + s * 0.5, y + s * 0.46);
  }
}

// glass card: dark body, faint top sheen, coloured edge
void glassCard(float x, float y, float w, float h, float r, color edge) {
  noStroke();
  fill(10, 14, 28, 235);
  rrect(x, y, w, h, r);
  fill(255, 255, 255, 7);
  rrect(x + 2 * fk, y + 2 * fk, w - 4 * fk, h * 0.45, r);
  stroke(red(edge), green(edge), blue(edge), 120);
  strokeWeight(1.5 * fk);
  rrectLine(x, y, w, h, r);
  noStroke();
}

void boldTextF(String s, float x, float y) {
  text(s, x, y);
  text(s, x + 0.9 * fk, y);
}

// the logo line at the top of a flat screen
void flatHeader(String logo, String sub, boolean infinity) {
  textAlign(LEFT, BASELINE);
  float x = FX(58);
  if (infinity) {
    drawInfinity(FX(100), FY(128), 40 * fk, 2.2);
    x = FX(158);
  }
  fill(70, 140, 255, 70);
  textSizeQ(58 * fk);
  text(logo, x - 1.5 * fk, FY(150) + 1.5 * fk);
  fill(#F4F7FF);
  boldTextF(logo, x, FY(150));
  fill(#9AA6C0);
  textSizeQ(28 * fk);
  text(sub, FX(60), FY(190));
}

// efinote's mark: an infinity loop, blue on the left, orange on the right
void drawInfinity(float cx, float cy, float s, float w) {
  noFill();
  int N = 64;
  for (int pass = 0; pass < 2; pass++) {
    for (int i0 = 0; i0 < N; i0 += 8) {
      float tm = TWO_PI * (i0 + 4) / N;
      float k = (sin(tm) + 1) * 0.5;                      // left loop blue, right loop orange
      color c = lerpColor(color(60, 140, 255), color(255, 160, 60), k);
      if (pass == 0) { stroke(red(c), green(c), blue(c), 60); strokeWeight(w * 4 * fk); }
      else { stroke(c); strokeWeight(w * fk); }
      beginShape();
      for (int i = i0; i <= i0 + 8; i++) {
        float t = TWO_PI * i / N;
        float d = 1 + cos(t) * cos(t);
        vertex(cx + s * sin(t) / d * 1.1, cy + s * sin(t) * cos(t) / d * 1.1);
      }
      endShape();
    }
  }
  noStroke();
}

// toggle switch, x y = left / centre line
void drawToggle(float x, float cy, boolean on) {
  float w = 92 * fk, h = 50 * fk;
  noStroke();
  if (on) {
    for (int i = 4; i >= 1; i--) {
      fill(30, 110, 255, 18);
      rrect(x - i * 3 * fk, cy - h * 0.5 - i * 3 * fk, w + i * 6 * fk, h + i * 6 * fk, h * 0.5 + i * 3 * fk);
    }
    fill(#1E6BFF);
  }
  else fill(#232B3D);
  rrect(x, cy - h * 0.5, w, h, h * 0.5);
  fill(on ? #FFFFFF : #8A93A6);
  float kx = on ? x + w - h * 0.5 : x + h * 0.5;
  ellipse(kx, cy, h - 10 * fk, h - 10 * fk);
}

void chevronRight(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  line(cx - s * 0.25, cy - s * 0.5, cx + s * 0.25, cy);
  line(cx + s * 0.25, cy, cx - s * 0.25, cy + s * 0.5);
  noStroke();
}

void chevronDown(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  line(cx - s * 0.5, cy - s * 0.25, cx, cy + s * 0.25);
  line(cx, cy + s * 0.25, cx + s * 0.5, cy - s * 0.25);
  noStroke();
}

// ---- line icons (cx, cy = centre, s = half size, c = colour)
void icoBell(float cx, float cy, float s, color c) {
  noStroke();
  fill(c);
  beginShape();
  vertex(cx - s * 0.75, cy + s * 0.5);
  bezierVertex(cx - s * 0.62, cy + s * 0.2, cx - s * 0.62, cy - s * 0.05, cx - s * 0.6, cy - s * 0.25);
  bezierVertex(cx - s * 0.55, cy - s * 0.75, cx + s * 0.55, cy - s * 0.75, cx + s * 0.6, cy - s * 0.25);
  bezierVertex(cx + s * 0.62, cy - s * 0.05, cx + s * 0.62, cy + s * 0.2, cx + s * 0.75, cy + s * 0.5);
  endShape(CLOSE);
  rrect(cx - s * 0.85, cy + s * 0.42, s * 1.7, s * 0.2, s * 0.1);
  ellipse(cx, cy + s * 0.78, s * 0.42, s * 0.36);
  ellipse(cx, cy - s * 0.78, s * 0.2, s * 0.2);
}

void icoGrid(float cx, float cy, float s, color c) {
  noStroke();
  fill(c);
  float g = s * 0.12, q = s - g;
  rrect(cx - s, cy - s, q, q, q * 0.25);
  rrect(cx + g, cy - s, q, q, q * 0.25);
  rrect(cx - s, cy + g, q, q, q * 0.25);
  rrect(cx + g, cy + g, q, q, q * 0.25);
}

void icoFolder(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  beginShape();
  vertex(cx - s, cy - s * 0.7);
  vertex(cx - s * 0.25, cy - s * 0.7);
  vertex(cx - s * 0.05, cy - s * 0.45);
  vertex(cx + s, cy - s * 0.45);
  vertex(cx + s, cy + s * 0.75);
  vertex(cx - s, cy + s * 0.75);
  endShape(CLOSE);
  noStroke();
}

void icoClock(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, 2 * s, 2 * s);
  line(cx, cy, cx, cy - s * 0.55);
  line(cx, cy, cx + s * 0.45, cy + s * 0.15);
  noStroke();
}

void icoWave(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  beginShape();
  vertex(cx - s, cy);
  vertex(cx - s * 0.45, cy);
  vertex(cx - s * 0.2, cy - s * 0.7);
  vertex(cx + s * 0.1, cy + s * 0.75);
  vertex(cx + s * 0.35, cy - s * 0.3);
  vertex(cx + s * 0.55, cy);
  vertex(cx + s, cy);
  endShape();
  noStroke();
}

void icoRefresh(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3.4 * fk);
  arcPath(cx, cy, s * 0.8, -2.6, 1.9);
  noStroke();
  fill(c);
  float ax = cx + cos(1.9) * s * 0.8, ay = cy + sin(1.9) * s * 0.8;
  triangle(ax - s * 0.38, ay - s * 0.05, ax + s * 0.12, ay - s * 0.35, ax + s * 0.12, ay + s * 0.3);
}

void icoBars(float cx, float cy, float s, color c) {
  noStroke();
  fill(c);
  rrect(cx - s * 0.75, cy - s * 0.1, s * 0.34, s * 0.9, s * 0.17);
  rrect(cx - s * 0.17, cy - s * 0.8, s * 0.34, s * 1.6, s * 0.17);
  rrect(cx + s * 0.41, cy - s * 0.45, s * 0.34, s * 1.25, s * 0.17);
}

void icoCal(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(2.4 * fk);
  noFill();
  rrectLine(cx - s, cy - s * 0.8, 2 * s, s * 1.8, s * 0.25);
  line(cx - s, cy - s * 0.25, cx + s, cy - s * 0.25);
  line(cx - s * 0.45, cy - s * 1.05, cx - s * 0.45, cy - s * 0.6);
  line(cx + s * 0.45, cy - s * 1.05, cx + s * 0.45, cy - s * 0.6);
  noStroke();
}

void icoInfo(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, 2 * s, 2 * s);
  line(cx, cy - s * 0.1, cx, cy + s * 0.5);
  noStroke();
  fill(c);
  ellipse(cx, cy - s * 0.45, s * 0.24, s * 0.24);
}

void icoDown(float cx, float cy, float s, color c) {         // export / save
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  line(cx, cy - s, cx, cy + s * 0.35);
  line(cx - s * 0.45, cy - s * 0.1, cx, cy + s * 0.35);
  line(cx + s * 0.45, cy - s * 0.1, cx, cy + s * 0.35);
  line(cx - s, cy + s * 0.85, cx + s, cy + s * 0.85);
  noStroke();
}

void icoPencil(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  beginShape();
  vertex(cx - s * 0.8, cy + s * 0.8);
  vertex(cx - s * 0.65, cy + s * 0.25);
  vertex(cx + s * 0.45, cy - s * 0.85);
  vertex(cx + s * 0.85, cy - s * 0.45);
  vertex(cx - s * 0.25, cy + s * 0.65);
  endShape(CLOSE);
  noStroke();
}

void icoTarget(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, 2 * s, 2 * s);
  ellipse(cx, cy, s, s);
  noStroke();
  fill(c);
  ellipse(cx, cy, s * 0.3, s * 0.3);
}

void icoBall(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, 2 * s, 2 * s);
  ellipse(cx, cy, 2 * s, s * 0.7);
  noStroke();
  fill(255, 255, 255, 160);
  ellipse(cx - s * 0.35, cy - s * 0.45, s * 0.35, s * 0.22);
}

void icoSun(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, s, s);
  for (int i = 0; i < 8; i++) {
    float a = TWO_PI * i / 8;
    line(cx + cos(a) * s * 0.75, cy + sin(a) * s * 0.75, cx + cos(a) * s, cy + sin(a) * s);
  }
  noStroke();
}

void icoEye(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  beginShape();
  vertex(cx - s, cy);
  bezierVertex(cx - s * 0.5, cy - s * 0.75, cx + s * 0.5, cy - s * 0.75, cx + s, cy);
  bezierVertex(cx + s * 0.5, cy + s * 0.75, cx - s * 0.5, cy + s * 0.75, cx - s, cy);
  endShape();
  ellipse(cx, cy, s * 0.6, s * 0.6);
  noStroke();
}

void icoHistory(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  arcPath(cx, cy, s, -2.4, 2.9);
  line(cx, cy, cx, cy - s * 0.5);
  line(cx, cy, cx + s * 0.4, cy + s * 0.2);
  noStroke();
  fill(c);
  float ax = cx + cos(-2.4) * s, ay = cy + sin(-2.4) * s;
  triangle(ax - s * 0.35, ay + s * 0.05, ax + s * 0.2, ay - s * 0.2, ax + s * 0.15, ay + s * 0.35);
}

void icoPalette(float cx, float cy, float s, color c) {
  stroke(c);
  strokeWeight(3 * fk);
  noFill();
  ellipse(cx, cy, 2 * s, 2 * s);
  noStroke();
  fill(#FF6B6B); ellipse(cx - s * 0.4, cy - s * 0.25, s * 0.38, s * 0.38);
  fill(#F5B942); ellipse(cx + s * 0.1, cy - s * 0.5, s * 0.38, s * 0.38);
  fill(#3DDC97); ellipse(cx + s * 0.5, cy - s * 0.05, s * 0.38, s * 0.38);
  fill(#4DA3FF); ellipse(cx + s * 0.2, cy + s * 0.45, s * 0.38, s * 0.38);
}

// a colour per app, from the timeline's set
color appHue(String pkg) {
  color[] set = { #F5B061, #8B7CF6, #2BB59A, #F25AB8, #4DA3FF, #FF7A5C };
  return set[pkgHash(pkg) % set.length];
}

// a small hash of a package name, the same in 1.5.1 and Processing.js
int pkgHash(String s) {
  String al = "abcdefghijklmnopqrstuvwxyz0123456789._-";
  int h = 7;
  for (int i = 0; i < s.length(); i++) h = (h * 31 + al.indexOf(s.substring(i, i + 1).toLowerCase()) + 2) % 65521;
  return h;
}

String monthName(int m) {
  String[] n = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
  return n[constrain(m - 1, 0, 11)];
}

// "08:15 AM" from "08:15:32"
String ampm(String t) {
  if (t.length() < 5) return t;
  int h = int(t.substring(0, 2));
  String m = t.substring(3, 5);
  String ap = h < 12 ? "AM" : "PM";
  int h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return nf(h12, 2) + ":" + m + " " + ap;
}

// "November 12, 2026" from "2026-11-12"
String longDate(String ymd) {
  if (ymd.length() < 10) return ymd;
  return monthName(int(ymd.substring(5, 7))) + " " + int(ymd.substring(8, 10)) + ", " + ymd.substring(0, 4);
}

// a short message above the bar (taps that need explaining)
void drawToast() {
  int t = millis() - appMsgAt;
  if (t > 2600 || appMsg.length() == 0) return;
  float a = t < 2200 ? 1 : (2600 - t) / 400.0;
  textSizeQ(21 * fk);
  float w = textWidth(appMsg) + 48 * fk, h = 50 * fk;
  float x = width * 0.5 - w * 0.5, y = barY - h - 18 * u;
  fill(20, 26, 44, 240 * a);
  rrect(x, y, w, h, h * 0.5);
  stroke(245, 185, 66, 200 * a);
  strokeWeight(1.4 * fk);
  rrectLine(x, y, w, h, h * 0.5);
  noStroke();
  fill(255, 230, 180, 255 * a);
  textAlign(CENTER, CENTER);
  text(appMsg, width * 0.5, y + h * 0.5 - 1 * fk);
}
