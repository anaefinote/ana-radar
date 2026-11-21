// Bar.pde — the bottom bar: "ANA." + subtitle, the RECORDING badge, and the four tabs.
// Rounded corners are drawn with ellipses and arcs (rect() with a radius isn't in 1.5.1).

// APPify sits in the centre and is the home screen; after the first run ANA opens on the last tab used
final int T_PULSE = 0, T_ARCHIVE = 1, T_APPIFY = 2, T_TIMELINE = 3, T_SETTINGS = 4, T_RADAR = 5;
String[] tabName = { "Pulse", "Archive", "APPify", "Timeline", "Settings", "Radar" };
final int NTABS = 6;

// the tabs shown in the bar (iOS: no APPify)
int[] barTabs() {
  int[] t = { T_PULSE, T_ARCHIVE, T_APPIFY, T_TIMELINE, T_RADAR, T_SETTINGS };
  return t;
}
int tab = T_APPIFY;

float barX, barY, barW, barH;

void barLayout() {
  barH = 156 * u;
  barX = 12 * u;
  barW = width - 24 * u;
  barY = height - barH - 12 * u;
}

// filled rounded rectangle, as ONE shape: pieces that overlap would show darker seams where see-through
void rrect(float x, float y, float w, float h, float r) {
  r = min(r, min(w, h) * 0.5);
  int seg = max(4, min(16, round(r / 3)));
  noStroke();
  beginShape();
  rrCorner(x + w - r, y + r, r, -HALF_PI, seg);
  rrCorner(x + w - r, y + h - r, r, 0, seg);
  rrCorner(x + r, y + h - r, r, HALF_PI, seg);
  rrCorner(x + r, y + r, r, PI, seg);
  endShape(CLOSE);
}

void rrCorner(float cx, float cy, float r, float a0, int seg) {
  for (int i = 0; i <= seg; i++) {
    float a = a0 + HALF_PI * i / seg;
    vertex(cx + cos(a) * r, cy + sin(a) * r);
  }
}

// rounded outline, as one closed path (separate arcs and lines overlap at the joins: beads when see-through)
void rrectLine(float x, float y, float w, float h, float r) {
  r = min(r, min(w, h) * 0.5);
  int seg = max(4, min(16, round(r / 3)));
  noFill();
  beginShape();
  rrCorner(x + w - r, y + r, r, -HALF_PI, seg);
  rrCorner(x + w - r, y + h - r, r, 0, seg);
  rrCorner(x + r, y + h - r, r, HALF_PI, seg);
  rrCorner(x + r, y + r, r, PI, seg);
  endShape(CLOSE);
}

// slightly heavier text: drawn twice, a fraction of a pixel apart
void boldText(String s, float x, float y) {
  text(s, x, y);
  text(s, x + 0.7 * u, y);
}

void drawBar() {
  fill(#05070C);                             // the base colour: no grey panel, just a faint outline
  rrect(barX, barY, barW, barH, 24 * u);
  stroke(#151922);
  strokeWeight(1.2 * u);
  rrectLine(barX, barY, barW, barH, 24 * u);
  noStroke();

  float px = barX + 22 * u;
  textAlign(LEFT, TOP);
  fill(#F2F4F8);
  textSizeQ(27 * u);
  boldText(statia() ? "ANA : STATIA." : "ANA ORBIT.", px, barY + 14 * u);
  fill(#8A93A6);
  textSizeQ(15 * u);
  text("NOTIFICATION COMPILER", px, barY + 48 * u);

  // badge
  String st = recLabel();
  textSizeQ(15 * u);
  float bw = textWidth(st) + 24 * u, bh = 30 * u;
  float bx = barX + barW - 22 * u - bw, by = barY + 22 * u;
  fill(recBack());
  rrect(bx, by, bw, bh, bh * 0.5);
  fill(recColor());
  textAlign(CENTER, CENTER);
  boldText(st, bx + bw * 0.5 - 0.35 * u, by + bh * 0.5 - 1 * u);

  stroke(#151922);
  strokeWeight(1 * u);
  line(barX + 22 * u, barY + 80 * u, barX + barW - 22 * u, barY + 80 * u);
  noStroke();

  int[] bt = barTabs();
  float cw = (barW - 44 * u) / bt.length;
  for (int k = 0; k < bt.length; k++) {
    int i = bt[k];
    float cx = barX + 22 * u + cw * (k + 0.5);
    boolean on = (i == tab);
    drawTabIcon(i, cx, barY + 104 * u, on);
    fill(on ? #FFFFFF : #8A93A6);
    textAlign(CENTER, CENTER);
    textSizeQ(16 * u);
    if (on) boldText(tabName[i], cx - 0.35 * u, barY + 134 * u);
    else text(tabName[i], cx, barY + 134 * u);
  }
}

String recLabel() {
  if (status.equals("IOS")) return "iPHONE";
  if (status.equals("CONNECTED")) return "RECORDING";
  if (status.equals("DESKTOP SIM")) return "SIMULATION";
  if (status.startsWith("ENABLED")) return "STARTING";
  return "NOT RECORDING";
}

color recColor() {
  if (status.equals("IOS")) return #4DA3FF;
  if (status.equals("CONNECTED")) return #3FB950;
  if (status.equals("DESKTOP SIM")) return #4DA3FF;
  if (status.startsWith("ENABLED")) return #F5B942;
  return #FF6B6B;
}

color recBack() {
  if (status.equals("IOS")) return #13243A;
  if (status.equals("CONNECTED")) return #15281C;
  if (status.equals("DESKTOP SIM")) return #13243A;
  if (status.startsWith("ENABLED")) return #2E2614;
  return #33181A;
}

void drawTabIcon(int i, float cx, float cy, boolean on) {
  float s = 12 * u;                          // half size of the icon
  strokeWeight(2.2 * u);
  noFill();
  if (i == T_PULSE) {                        // square with a pulse line
    stroke(on ? #6CC4FF : #4A90C0);
    rrectLine(cx - s, cy - s, 2 * s, 2 * s, 4 * u);
    line(cx - s * 0.65, cy + s * 0.15, cx - s * 0.25, cy - s * 0.35);
    line(cx - s * 0.25, cy - s * 0.35, cx + s * 0.1, cy + s * 0.3);
    line(cx + s * 0.1, cy + s * 0.3, cx + s * 0.6, cy - s * 0.4);
  }
  else if (i == T_ARCHIVE) {                 // stack
    stroke(on ? #B49CFF : #8370C8);
    line(cx - s, cy + s * 0.25, cx + s, cy + s * 0.25);
    line(cx - s, cy + s * 0.75, cx + s, cy + s * 0.75);
    line(cx - s * 0.75, cy - s * 0.65, cx + s * 0.75, cy - s * 0.65);
    line(cx - s * 0.75, cy - s * 0.65, cx - s, cy - s * 0.2);
    line(cx + s * 0.75, cy - s * 0.65, cx + s, cy - s * 0.2);
    line(cx - s, cy - s * 0.2, cx + s, cy - s * 0.2);
  }
  else if (i == T_TIMELINE) {                // calendar
    stroke(on ? #F7B866 : #C08E50);
    rrectLine(cx - s, cy - s * 0.8, 2 * s, s * 1.85, 4 * u);
    line(cx - s, cy - s * 0.3, cx + s, cy - s * 0.3);
    line(cx - s * 0.45, cy - s * 1.1, cx - s * 0.45, cy - s * 0.6);
    line(cx + s * 0.45, cy - s * 1.1, cx + s * 0.45, cy - s * 0.6);
    noStroke();
    fill(on ? #F7B866 : #C08E50);
    for (int r = 0; r < 2; r++) for (int c = 0; c < 3; c++) ellipse(cx - s * 0.45 + c * s * 0.45, cy + s * 0.15 + r * s * 0.4, 2.6 * u, 2.6 * u);
  }
  else if (i == T_APPIFY) {
    drawAppifyIcon(cx, cy, s, on);
  }
  else if (i == T_RADAR) {                   // radar: concentric arcs + a blip
    stroke(on ? #4DE2C4 : #3A9E8C);
    arc(cx, cy, s * 1.1, s * 1.1, -0.9, 0.9);
    arc(cx, cy, s * 1.9, s * 1.9, -0.9, 0.9);
    noStroke();
    fill(on ? #4DE2C4 : #3A9E8C);
    ellipse(cx, cy, 3.4 * u, 3.4 * u);
    ellipse(cx + s * 0.55, cy - s * 0.35, 3 * u, 3 * u);
  }
  else {                                     // sliders
    stroke(on ? #C3C8D2 : #8D929C);
    line(cx - s, cy - s * 0.45, cx + s, cy - s * 0.45);
    line(cx - s, cy + s * 0.45, cx + s, cy + s * 0.45);
    fill(#05070C);
    ellipse(cx + s * 0.3, cy - s * 0.45, s * 0.75, s * 0.75);
    ellipse(cx - s * 0.3, cy + s * 0.45, s * 0.75, s * 0.75);
  }
  noStroke();
  strokeWeight(1);
}

int tabAt(float mx, float my) {
  if (my < barY + 82 * u || my > barY + barH || mx < barX || mx > barX + barW) return -1;
  int[] bt = barTabs();
  float cw = (barW - 44 * u) / bt.length;
  int i = floor((mx - barX - 22 * u) / cw);
  return bt[constrain(i, 0, bt.length - 1)];
}

boolean onBar(float mx, float my) {
  return my >= barY && mx >= barX && mx <= barX + barW;
}
