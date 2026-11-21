// Reader.pde — tap a notification (Pulse's Recent Notifications, Timeline): read it in full.
//
// A glass card over the screen: the app, where it came from (the iPhone over Bluetooth, or this phone), the
// time, the sender, the whole message (not cut to one line), then
//   COPY               the text, to the clipboard
//   SELECT             mark it for EXPORT (.pngmesh), as in Archive
//   CLEAR ON iPHONE    an iPhone notification: dismiss it on the iPhone (while it's still there and linked)
//   OPEN               a notification from this phone: open its app
// and under it "More from ...": the other notifications from the same app and sender, newest first.
// Tap one of those to read it; tap outside the card or X to close.

Entry readerE = null;
int readerAt = 0;

void openReader(Entry e) {
  readerE = e;
  readerAt = millis();
}

void closeReader() { readerE = null; }

float rdX() { return FX(30); }
float rdY() { return FY(250); }
float rdW() { return 792 * fk; }
float rdB() { return barY - 20 * u; }        // the card's bottom
float rdMsgH() { return 300 * fk; }
float rdBtnY() { return rdY() + 200 * fk + rdMsgH() + 24 * fk; }
float rdBtnH() { return 58 * fk; }
float rdListY() { return rdBtnY() + rdBtnH() + 70 * fk; }
float rdRowH() { return 66 * fk; }

boolean rdIphone(Entry e) { return e.src.equals("IPHONE"); }

String rdName(Entry e) {
  if (e.src.equals("MANUAL")) return "Manual entry";
  if (e.src.equals("REMIND")) return "Reminder";
  return appFor(e.pkg).label;
}

String[] rdButtons(Entry e) {
  String[] b = { "COPY", e.selected ? "SELECTED" : "SELECT", rdIphone(e) ? "CLEAR ON iPHONE" : e.src.equals("MANUAL") || e.src.equals("REMIND") ? "" : "OPEN" };
  return b;
}

float[] rdBtnRect(int i) {
  float g = 16 * fk, bw = (rdW() - 56 * fk - 2 * g) / 3;
  float[] r = { rdX() + 28 * fk + i * (bw + g), rdBtnY(), bw, rdBtnH() };
  return r;
}

// the other notifications from the same app and sender, newest first
ArrayList rdMore(Entry e, int max) {
  ArrayList out = new ArrayList();
  boolean bySender = e.isSms() && e.title.length() > 0;   // SMS: same sender; an app push: the same app
  for (int k = 0; k < entries.size(); k++) {
    Entry o = (Entry) entries.get(k);
    if (o == e || !o.pkg.equals(e.pkg) || o.src.equals("SYS")) continue;
    if (bySender && !o.title.equals(e.title)) continue;
    int at = out.size();
    for (int j = 0; j < out.size(); j++) {
      Entry p = (Entry) out.get(j);
      if (whenCmp(o.ymd + " " + o.time, p.ymd + " " + p.time) > 0) { at = j; break; }
    }
    out.add(at, o);
    if (out.size() > max) out.remove(out.size() - 1);
  }
  return out;
}

int rdRows() { return max(0, min(6, floor((rdB() - rdListY() - 20 * fk) / rdRowH()))); }

void drawReader() {
  Entry e = readerE;
  if (e == null) return;
  float fade = constrain((millis() - readerAt) / 180.0, 0, 1);
  noStroke();
  fill(3, 5, 10, 200 * fade);
  rect(0, 0, width, height);
  float x = rdX(), y = rdY() + (1 - fade) * 24 * fk, w = rdW(), h = rdB() - rdY();
  AppIcon a = appFor(e.pkg);
  color edge = rdIphone(e) ? color(77, 163, 255) : a.ready ? a.glow : pkgColour(e.pkg);
  glassCard(x, y, w, h, 36 * fk, edge);

  // the app, where from, when
  drawAppIconAt(a, x + 28 * fk, y + 28 * fk, 72 * fk);
  String name = rdName(e);
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(32 * fk);
  boldTextF(fitText(name, 380 * fk), x + 120 * fk, y + 62 * fk);
  if (rdIphone(e)) iphoneTag(x + 120 * fk + min(textWidthAt(name, 32 * fk), 380 * fk) + 14 * fk, y + 51 * fk, 32 * fk);
  fill(#9AA6C8);
  textAlign(LEFT, BASELINE);
  textSizeQ(21 * fk);
  String from = rdIphone(e) ? (onIOS ? "relayed by ANA on Android" : "from your iPhone") : e.src.equals("MANUAL") ? "added by hand" : e.src.equals("IMPORT") ? "imported" : e.src.equals("REMIND") ? "your reminder" : "on this phone";
  text((e.ymd.equals(today()) ? "Today" : longDate(e.ymd)) + "  ·  " + ampm(e.time) + "  ·  " + from, x + 120 * fk, y + 96 * fk);

  // close
  float cx = x + w - 46 * fk, cy = y + 46 * fk;
  fill(20, 28, 48, 230);
  ellipse(cx, cy, 52 * fk, 52 * fk);
  stroke(#C9D3E6);
  strokeWeight(2.6 * fk);
  line(cx - 9 * fk, cy - 9 * fk, cx + 9 * fk, cy + 9 * fk);
  line(cx - 9 * fk, cy + 9 * fk, cx + 9 * fk, cy - 9 * fk);
  noStroke();

  // the sender, then the whole message
  float ty = y + 150 * fk;
  if (e.title.length() > 0 && !e.title.equals(name)) {
    fill(#F4F7FF);
    textSizeQ(30 * fk);
    boldTextF(fitText(e.title, w - 56 * fk), x + 28 * fk, ty + 22 * fk);
    ty += 44 * fk;
  }
  fill(#DCE3F2);
  textAlign(LEFT, TOP);
  textSizeQ(27 * fk);
  String body = e.body.length() > 0 ? e.body : "(no text: the iPhone may be hiding previews; Settings > Notifications > Show Previews > Always)";
  if (e.body.length() == 0) fill(#7A8BA0);
  text(body, x + 28 * fk, ty, w - 56 * fk, rdY() + 200 * fk + rdMsgH() - ty);
  textAlign(LEFT, BASELINE);

  // COPY / SELECT / CLEAR ON iPHONE or OPEN
  String[] bl = rdButtons(e);
  for (int i = 0; i < 3; i++) {
    if (bl[i].length() == 0) continue;
    float[] r = rdBtnRect(i);
    color bc = i == 0 ? color(150, 165, 190) : i == 1 ? color(245, 185, 66) : rdIphone(e) ? color(77, 163, 255) : edge;
    if (i == 1 && e.selected) {
      fill(red(bc) * 0.55, green(bc) * 0.55, blue(bc) * 0.55, 240);
    }
    else fill(red(bc) * 0.22, green(bc) * 0.22, blue(bc) * 0.22, 240);
    rrect(r[0], r[1], r[2], r[3], r[3] * 0.5);
    stroke(red(bc), green(bc), blue(bc), 220);
    strokeWeight(1.6 * fk);
    rrectLine(r[0], r[1], r[2], r[3], r[3] * 0.5);
    noStroke();
    fill(#FFFFFF);
    textAlign(CENTER, CENTER);
    textSizeQ(19 * fk);
    boldTextF(bl[i], r[0] + r[2] * 0.5, r[1] + r[3] * 0.5 - 1.5 * fk);
  }

  // more from the same app and sender
  int n = rdRows();
  ArrayList more = rdMore(e, n);
  if (n > 0) {
    fill(#8FA3B8);
    textAlign(LEFT, BASELINE);
    textSizeQ(20 * fk);
    String who = e.isSms() && e.title.length() > 0 ? e.title : name;   // SMS: the sender; an app: its name
    text(more.size() == 0 ? "Nothing else from " + fitText(who, 400 * fk) : "More from " + fitText(who, 500 * fk), x + 28 * fk, rdListY() - 18 * fk);
    for (int i = 0; i < more.size(); i++) {
      Entry o = (Entry) more.get(i);
      float ry = rdListY() + i * rdRowH();
      stroke(40, 50, 75, 160);
      strokeWeight(1.2 * fk);
      line(x + 28 * fk, ry, x + w - 28 * fk, ry);
      noStroke();
      fill(#9AA6C8);
      textSizeQ(19 * fk);
      String when = (o.ymd.equals(today()) ? "" : o.ymd.substring(5).replace('-', '/') + " ") + ampm(o.time);
      text(when, x + 28 * fk, ry + 42 * fk);
      fill(#DCE3F2);
      textSizeQ(22 * fk);
      text(fitText(o.body.length() > 0 ? o.body : o.title, w - 260 * fk), x + 200 * fk, ry + 42 * fk);
    }
  }
}

// a tap while the reader is open
void readerTap(float mx, float my) {
  Entry e = readerE;
  if (e == null) return;
  float x = rdX(), y = rdY(), w = rdW();
  if (mx < x || mx > x + w || my < y || my > rdB()) { closeReader(); return; }       // outside the card
  if (dist(mx, my, x + w - 46 * fk, y + 46 * fk) < 34 * fk) { closeReader(); return; }
  String[] bl = rdButtons(e);
  for (int i = 0; i < 3; i++) {
    float[] r = rdBtnRect(i);
    if (bl[i].length() == 0 || !(mx >= r[0] && mx <= r[0] + r[2] && my >= r[1] - 8 * fk && my <= r[1] + r[3] + 8 * fk)) continue;
    if (i == 0) {
      String t = e.title.length() > 0 && !e.title.equals(rdName(e)) ? e.title + ": " + e.body : e.body;
      if (js != null) js.copyText(t);
      else println("COPY: " + t);
      appMsg = "Copied";
    }
    else if (i == 1) {
      e.selected = !e.selected;
      appMsg = e.selected ? "Selected for EXPORT (Archive)" : "Not selected";
    }
    else if (rdIphone(e)) {
      boolean ok = js != null && js.iphoneDismiss(e.nkey);
      appMsg = ok ? "Cleared on the iPhone" : "Not on the iPhone any more (or the link is off)";
    }
    else {
      openApp(appFor(e.pkg));
      return;
    }
    appMsgAt = millis();
    return;
  }
  // a row of "More from"
  if (my >= rdListY()) {
    int i = floor((my - rdListY()) / rdRowH());
    ArrayList more = rdMore(e, rdRows());
    if (i >= 0 && i < more.size()) openReader((Entry) more.get(i));
  }
}
