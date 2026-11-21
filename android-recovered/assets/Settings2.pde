// Settings2.pde — Settings (concept image 5), with a pill: ANA | EFINOTE | WATCH.
// It opens on whichever half was used last (ANA the first time).
//   ANA      capture (Notification access, Usage access, SCAN, MANUAL, ARM), display (the control ball,
//            its skin and brightness), apps (the apps to show, picked / all), data (text log), about
//   EFINOTE  Notification Capture (pause saving), Retention Period (applied when ANA next starts), About
//   WATCH    wallets ANA keeps an eye on, read-only: an ether.fi Safe on Optimism (ready to spend +
//            earning), Solana and TRON wallets, with their activity in plain words. The phone reads them (Wallets.java on Android, Wallets.swift on iPhone).
// Only settings that work are here.

String lessonsTxt = "";          // LESSONS: one line per coin a lesson taught ANA
int setPill = 0;                 // 0 ANA, 1 EFINOTE, 2 WATCH, 3 GST (Gst.pde), 4 FLEX (Flex.pde)
boolean setPicking = false;      // the "Apps to show" page
boolean efAbout = false;         // About efinote opened
boolean usageOn = false;
int usageCheckAt = -100000;
boolean captureOn = true;
int retention = 0;               // days, 0 = forever
int[] retentionDays = { 0, 365, 90, 30 };
float[] brtSteps = { 0.25, 0.35, 0.45, 0.6, 0.75 };

// rows are laid out as the screen draws them; taps look them up here
ArrayList setRows = new ArrayList();
class SetRow {
  int id;
  float y0, y1;
  SetRow(int id, float y0, float y1) { this.id = id; this.y0 = y0; this.y1 = y1; }
}

final int R_ACCESS = 1, R_USAGE = 2, R_SCAN = 3, R_MANUAL = 4, R_ARM = 5, R_BALL = 6, R_SKIN = 7, R_BRT = 8,
          R_PICK = 9, R_ONLYPICKED = 10, R_LOG = 11, R_CAPTURE = 12, R_RETENTION = 13, R_EFABOUT = 14,
          R_FEVENT = 15, R_FTEXT = 16, R_FREMIND = 17, R_ADDREM = 18, R_EFSTART = 19, R_EFFULL = 20, R_RESTRICT = 21, R_IPHONE = 22,
          R_WADD = 23, R_WREFRESH = 24, R_WCLOSE = 25, R_LESSONS = 26, R_CHAT = 27, R_TILEPLACE = 29, R_WALLET = 1000;   // R_WALLET + n: the n-th wallet card
boolean iphoneOn = false;          // the iPhone <-> Android Bluetooth link (pref "iphone")
String iphoneSaid = "";
int sdkInt = -1;                 // Android's version (API level); -1 until asked
String[] efStartName = { "Present", "Past", "Future" };

// WATCH: what the phone last read (Wallets pageText), asked for once a second
String wText = "";
int wTextAt = -100000;
boolean wBack, wHeld;                  // SUB-WATCH: open; Check Now was held (so the release isn't a tap)
int wBackAt = -100000, wPressAt;       // last time we asked if it's open; when the finger went down
final color WVIOLET = #B48CFF;
String[] wIds = new String[40];
color WGOLD = #F5B942;

void drawSettings2() {
  image(flatBgImg, 0, 0);
  if (frameCount % 60 == 1 || millis() - usageCheckAt > 3000) {
    usageCheckAt = millis();
    usageOn = js != null && js.usageOk();
  }
  setRows.clear();
  float s0 = tabScroll[tab];
  float y = FY(0) - s0;

  if (setPicking) { drawPickPage(); return; }

  // header (scrolls with the page) + the infinity light top right
  boolean ef = setPill == 1, wt = setPill == 2, gs = setPill == 3, fx = setPill == 4;
  pushMatrix();
  translate(0, -s0);
  if (ef) drawInfinity(FX(640), FY(150), 150 * fk, 3.2);
  else if (wt) {                                  // WATCH's mark: a gold coin in an orbit
    pulseRing(FX(660), FY(150), 150 * fk, 46 * fk, -0.35, false, 3, 0.9);
    noStroke();
    fill(48, 34, 8);
    ellipse(FX(660), FY(150), 70 * fk, 70 * fk);
    noFill();
    stroke(245, 185, 66, 230);
    strokeWeight(3 * fk);
    ellipse(FX(660), FY(150), 70 * fk, 70 * fk);
    noStroke();
    fill(WGOLD);
    textAlign(CENTER, CENTER);
    textSizeQ(34 * fk);
    boldTextF("$", FX(660), FY(147));
    pulseRing(FX(660), FY(150), 150 * fk, 46 * fk, -0.35, true, 3, 0.9);
  }
  else {                                          // ANA's mark: a small orbit
    pulseRing(FX(660), FY(150), 150 * fk, 46 * fk, -0.35, false, 3, 0.9);
    noStroke();
    fill(8, 12, 28);
    ellipse(FX(660), FY(150), 70 * fk, 70 * fk);
    noFill();
    if (gs) stroke(61, 220, 151, 220); else if (fx) stroke(245, 185, 66, 220); else stroke(110, 170, 255, 200);
    strokeWeight(2 * fk);
    ellipse(FX(660), FY(150), 70 * fk, 70 * fk);
    noStroke();
    pulseRing(FX(660), FY(150), 150 * fk, 46 * fk, -0.35, true, 3, 0.9);
  }
  flatHeader(ef ? "efinote" : wt ? (wBack ? "Sub-watch" : "Watch") : gs ? "GST" : fx ? "FLEX" : "ANA : STATIA", ef ? "Your Digital Memory" : wt ? (wBack ? "Only you see this" : "Your wallets, read-only") : gs ? "Group Spend Technology" : fx ? "Earned and bought never mix" : "Notification Compiler", ef);
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(54 * fk);
  boldTextF("Settings", FX(48), FY(300));
  fill(#9AA6C0);
  textSizeQ(25 * fk);
  text(ef ? "Personalise your efinote experience" : wt ? "The wallets ANA keeps an eye on" : gs ? "Pool, share and spend together" : fx ? "Earn your FLEX" : "Personalise your ANA experience", FX(48), FY(342));
  popMatrix();

  // the pill
  int np = 5;
  float py = FY(372) - s0, pw = 800 * fk, ph = 60 * fk, px = FX(426) - pw * 0.5, sw = pw / np;
  fill(12, 16, 30, 240);
  rrect(px, py, pw, ph, ph * 0.5);
  stroke(60, 80, 140, 140);
  strokeWeight(1.4 * fk);
  rrectLine(px, py, pw, ph, ph * 0.5);
  noStroke();
  float hx = px + 5 * fk + setPill * sw, hw = sw - 10 * fk;
  color pc = ef ? color(255, 150, 60) : wt ? color(245, 185, 66) : gs ? color(61, 220, 151) : fx ? color(180, 140, 255) : color(40, 120, 255);
  for (int i = 3; i >= 1; i--) {
    fill(red(pc), green(pc), blue(pc), 26);
    rrect(hx - i * 3 * fk, py + 5 * fk - i * 3 * fk, hw + i * 6 * fk, ph - 10 * fk + i * 6 * fk, (ph - 10 * fk) * 0.5 + i * 3 * fk);
  }
  fill(red(pc) * 0.55, green(pc) * 0.55, blue(pc) * 0.55);
  rrect(hx, py + 5 * fk, hw, ph - 10 * fk, (ph - 10 * fk) * 0.5);
  textAlign(CENTER, CENTER);
  textSizeQ((np > 4 ? 19 : 22) * fk);
  String[] pillName = { "ANA", "EFINOTE", "WATCH", "GST", flexPillLabel() };   // FLEX shows your eFLEX
  for (int i = 0; i < np; i++) {
    fill(setPill == i ? #FFFFFF : #8A93A6);
    boldTextF(pillName[i], px + sw * (i + 0.5), py + ph * 0.5 - 1 * fk);
  }

  if (fx) {
    y = drawFlexPage(FY(460) - s0);
    float contentF = y + s0 - FY(0);
    tabScroll[tab] = constrain(tabScroll[tab], 0, max(0, contentF - (barY - 10 * u)));
    return;
  }
  if (gs) {
    y = drawGst(FY(460) - s0);
    float contentG = y + s0 - FY(0);
    tabScroll[tab] = constrain(tabScroll[tab], 0, max(0, contentG - (barY - 10 * u)));
    return;
  }
  if (wt) {
    y = drawWatch(FY(460) - s0);
    float contentW = y + s0 - FY(0);
    tabScroll[tab] = constrain(tabScroll[tab], 0, max(0, contentW - (barY - 10 * u)));
    return;
  }

  // product card
  y = FY(460) - s0;
  glassCard(FX(38), y, 776 * fk, 160 * fk, 46 * fk, ef ? color(150, 110, 255) : color(70, 130, 255));
  float oc = FX(136), ocy = y + 80 * fk;
  for (int i = 8; i >= 1; i--) {
    fill(ef ? color(120, 80, 255, 14) : color(40, 110, 255, 14));
    ellipse(oc, ocy, (110 + i * 6) * fk, (110 + i * 6) * fk);
  }
  fill(8, 12, 28);
  ellipse(oc, ocy, 112 * fk, 112 * fk);
  if (ef) drawInfinity(oc, ocy, 28 * fk, 2.4);
  else {
    fill(#F4F7FF);
    textAlign(CENTER, CENTER);
    textSizeQ(34 * fk);
    boldTextF("A", oc - 0.5 * fk, ocy - 3 * fk);
  }
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(30 * fk);
  boldTextF(ef ? "efinote" : "ANA : STATIA", FX(244), y + 64 * fk);
  fill(#9AA6C0);
  textSizeQ(23 * fk);
  text("Version " + VERSION, FX(244), y + 100 * fk);
  text(ef ? "The archive of every notification" : "Access Novera Analytics", FX(244), y + 132 * fk);

  y += 200 * fk;
  if (!ef) y = drawPromises(y);          // ANA's promises, under the version card
  if (ef) {
    y = setSection("Capture", y, #4DA3FF);
    y = setGroup(y, 2);
    setRowToggle(R_CAPTURE, y, 0, "Notification Capture", "Save and organise your notifications", captureOn, color(60, 150, 255));
    String rv = retention == 0 ? "Forever" : retention == 365 ? "1 year" : retention + " days";
    setRowValue(R_RETENTION, y, 1, "Retention Period", "How long to keep your history", rv, true, color(255, 180, 60));
    y += 2 * 100 * fk + 30 * fk;
    y = setSection("Future", y, #C9D3E6);
    y = setGroup(y, 4);
    setRowToggle(R_FEVENT, y, 0, "Event times", "When an app says a notification is for later", futEvent, color(200, 215, 240));
    setRowToggle(R_FTEXT, y, 1, "Dates in the text", "\"tomorrow at 7pm\", \"Nov 20\", \"in 2 hours\"", futText, color(160, 190, 255));
    setRowToggle(R_FREMIND, y, 2, "My reminders", "Reminders you make in ANA", futRemind, color(120, 170, 255));
    setRowValue(R_ADDREM, y, 3, "Add a reminder", "A note with a date and time", "", true, color(61, 220, 151));
    y += 4 * 100 * fk + 30 * fk;
    y = setSection("Archive", y, #3DDC97);
    y = setGroup(y, 2);
    setRowValue(R_EFSTART, y, 0, "Ball in front", "The ball Archive opens on", efStartName[efStart], false, color(61, 220, 151));
    setRowToggle(R_EFFULL, y, 1, "Full screen (experimental)", "Tap a ball and it fills the screen", efFull, color(201, 211, 230));
    y += 2 * 100 * fk + 30 * fk;
    y = setSection("About", y, #8B6CFF);
    y = setGroup(y, 1);
    setRowValue(R_EFABOUT, y, 0, "About efinote", "Learn more about the archive", "", false, color(60, 170, 255));
    y += 100 * fk + 20 * fk;
    if (efAbout) {
      String t = "efinote is ANA's archive: a dive into the sea of notifications you usually throw away and never look back at. "
               + "E for electronic, FIN from infinite, NOT from notifications, and E from archive. "
               + "In Archive, the maze keeps every notification by age: today is the core, older days lie further out. "
               + "Three balls: the past (gooey agate, one shell per day: zoom in to dive older), the present (emerald, today) and the future (mercury: reminders and notifications about times ahead). "
               + "Touch a bead to see the notification, open its app, or find out if the app is active, dormant, archived or uninstalled.";
      textSizeQ(21 * fk);
      float th = textBoxHeight(t, 700 * fk, 21 * fk);
      glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, color(150, 110, 255));
      fill(#C9D3E6);
      textAlign(LEFT, TOP);
      text(t, FX(70), y + 24 * fk, 712 * fk, th + 10 * fk);
      y += th + 80 * fk;
    }
  }
  else {
    y = setSection("Capture", y, #4DA3FF);
    if (sdkInt < 0) sdkInt = js != null ? js.sdkInt() : 0;
    boolean restricted = sdkInt >= 33;              // Android 13+: sideloaded apps need "Allow restricted settings"
    int nCap = restricted ? 6 : 5;
    y = setGroup(y, nCap);
    boolean acc = status.equals("CONNECTED");
    setRowValue(R_ACCESS, y, 0, "Notification access", acc ? "On: ANA is recording" : "Off: tap to turn it on", acc ? "On" : "Off", true, color(60, 150, 255));
    setRowValue(R_USAGE, y, 1, "Usage access", "For APPify ACTIVE and app states", usageOn ? "On" : "Off", true, color(150, 110, 255));
    setRowValue(R_SCAN, y, 2, "Scan now", "Read what's in the notification shade", "", true, color(60, 220, 150));
    setRowValue(R_MANUAL, y, 3, "Manual entry", "Add an entry by hand", "", true, color(245, 185, 66));
    setRowToggle(R_ARM, y, 4, "Arm test", armed ? (armedHit.length() > 0 ? armedHit : "Waiting for a notification") : "Time how fast a notification arrives", armed, color(61, 220, 151));
    if (restricted) setRowValue(R_RESTRICT, y, 5, "Allow restricted settings", acc ? "Done: access is on" : "If Android blocks access: tap, then its menu", "", true, color(255, 140, 80));
    y += nCap * 100 * fk + 30 * fk;

    // iPhone notifications over Bluetooth: Android ANA is the iPhone's "watch"; ANA on the iPhone connects to it
    y = setSection("iPhone", y, #4DA3FF);
    y = setGroup(y, 2);
    String ist = js != null ? js.iphoneState() : "Off";
    if (iphoneOn && !ist.equals(iphoneSaid)) { iphoneSaid = ist; appMsg = ist; appMsgAt = millis(); }   // the whole message, as a toast
    String itm = iphoneOn && js != null && ist.startsWith("Receiving") ? js.iphoneTimes() : "";   // LINK TIME
    setRowToggle(R_IPHONE, y, 0, "iPhone notifications", iphoneOn ? (itm.length() > 0 ? itm : ist) : "Over Bluetooth: this device acts as the iPhone's watch", iphoneOn, color(77, 163, 255));
    setRowValue(R_CHAT, y, 1, "CHATNOTE (experimental)", "Say hello: Bluetooth, Wi-Fi, Internet, Light", "", true, color(245, 185, 66));
    y += 2 * 100 * fk + 30 * fk;

    y = setSection("Display", y, #8B6CFF);
    y = setGroup(y, 4);
    setRowToggle(R_BALL, y, 0, "Control ball", "The 3D ball on Pulse, Archive and Timeline", ballOn, color(120, 160, 255));
    setRowValue(R_SKIN, y, 1, "Ball skin", "Tap to change", skinName[skin], false, color(255, 120, 160));
    setRowValue(R_BRT, y, 2, "Ball brightness", "Tap to change", round(brtVal * 100) + "%", false, color(255, 200, 80));
    setRowValue(R_TILEPLACE, y, 3, "New tiles go", "FIND and CHATNOTE: tap to change", tilePlaceName[tilePlace], false, color(245, 185, 66));
    y += 4 * 100 * fk + 30 * fk;

    y = setSection("Apps", y, #3DDC97);
    y = setGroup(y, 2);
    setRowValue(R_PICK, y, 0, "Apps to show", "Pick the apps whose notifications you see", watch.size() + " picked", true, color(61, 220, 151));
    setRowToggle(R_ONLYPICKED, y, 1, "Only picked apps", filterOn ? "Showing the picked apps" : "Showing every app", filterOn, color(77, 163, 255));
    y += 2 * 100 * fk + 30 * fk;

    y = setSection("Data", y, #F5B942);
    y = setGroup(y, 1);
    setRowValue(R_LOG, y, 0, "Export the text log", "Every notification, tab-separated", "", true, color(245, 185, 66));
    y += 100 * fk + 30 * fk;
  }
  float contentH = y + s0 - FY(0);
  tabScroll[tab] = constrain(tabScroll[tab], 0, max(0, contentH - (barY - 10 * u)));
}

float setSection(String t, float y, color c) {
  fill(c);
  rect(FX(40), y + 8 * fk, 5 * fk, 32 * fk);
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(27 * fk);
  text(t, FX(64), y + 34 * fk);
  return y + 56 * fk;
}

float setGroup(float y, int n) {
  glassCard(FX(38), y, 776 * fk, n * 100 * fk, 40 * fk, color(60, 90, 180));
  for (int i = 1; i < n; i++) {
    stroke(40, 50, 78, 170);
    strokeWeight(1.2 * fk);
    line(FX(170), y + i * 100 * fk, FX(794), y + i * 100 * fk);
    noStroke();
  }
  return y;
}

void setRowIcon(int id, float cx, float cy, color c) {
  for (int i = 5; i >= 1; i--) {
    fill(red(c), green(c), blue(c), 12);
    ellipse(cx, cy, (44 + i * 8) * fk, (44 + i * 8) * fk);
  }
  float s = 18 * fk;
  if (id == R_ACCESS || id == R_CAPTURE) icoBell(cx, cy, s, c);
  else if (id == R_USAGE) icoBars(cx, cy, s, c);
  else if (id == R_SCAN || id == R_WREFRESH) icoRefresh(cx, cy, s, c);
  else if (id == R_WADD || id == R_LESSONS) icoPencil(cx, cy, s, c);
  else if (id == R_WCLOSE) icoHistory(cx, cy, s, c);
  else if (id == R_MANUAL || id == R_CHAT) icoPencil(cx, cy, s, c);
  else if (id == R_ARM) icoTarget(cx, cy, s, c);
  else if (id == R_RESTRICT) icoEye(cx, cy, s, c);
  else if (id == R_IPHONE) icoBell(cx, cy, s, c);
  else if (id == R_BALL || id == R_TILEPLACE) icoBall(cx, cy, s, c);
  else if (id == R_SKIN) icoPalette(cx, cy, s, c);
  else if (id == R_BRT) icoSun(cx, cy, s, c);
  else if (id == R_PICK) icoGrid(cx, cy, s * 0.9, c);
  else if (id == R_ONLYPICKED) icoEye(cx, cy, s, c);
  else if (id == R_LOG) icoDown(cx, cy, s, c);
  else if (id == R_RETENTION) icoHistory(cx, cy, s, c);
  else if (id == R_FEVENT || id == R_FREMIND || id == R_ADDREM) icoClock(cx, cy, s, c);
  else if (id == R_FTEXT) icoCal(cx, cy, s, c);
  else if (id == R_EFSTART || id == R_EFFULL) icoBall(cx, cy, s, c);
  else if (id == F_BILLS) icoCal(cx, cy, s, c);
  else if (id >= R_GPOOLS && id <= 58) gstIcon(id, cx, cy, s, c);
  else icoInfo(cx, cy, s, c);
}

void setRowText(float y, String t, String sub) {
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(26 * fk);
  text(fitText(t, 440 * fk), FX(190), y + 44 * fk);
  fill(#9AA6C0);
  textSizeQ(20 * fk);
  text(fitText(sub, 440 * fk), FX(190), y + 74 * fk);
}

void setRowToggle(int id, float gy, int i, String t, String sub, boolean on, color c) {
  float y = gy + i * 100 * fk;
  setRows.add(new SetRow(id, y, y + 100 * fk));
  setRowIcon(id, FX(108), y + 50 * fk, c);
  setRowText(y, t, sub);
  drawToggle(FX(700), y + 50 * fk, on);
}

void setRowValue(int id, float gy, int i, String t, String sub, String v, boolean chev, color c) {
  float y = gy + i * 100 * fk;
  setRows.add(new SetRow(id, y, y + 100 * fk));
  setRowIcon(id, FX(108), y + 50 * fk, c);
  setRowText(y, t, sub);
  fill(#C9D3E6);
  textAlign(RIGHT, CENTER);
  textSizeQ(23 * fk);
  float rx = chev ? FX(752) : FX(784);
  text(v, rx, y + 48 * fk);
  if (chev) chevronRight(FX(774), y + 50 * fk, 20 * fk, #9AA6C0);
}

float textBoxHeight(String t, float w, float sz) {
  textSizeQ(sz);
  String[] words = split(t, " ");
  float lines = 1, lw = 0, sp = textWidth(" ");
  for (int i = 0; i < words.length; i++) {
    float ww = textWidth(words[i]);
    if (lw + ww > w) { lines++; lw = ww + sp; }
    else lw += ww + sp;
  }
  return lines * sz * 1.35;
}

// "Apps to show": every app / SMS sender caught, tap to pick
void drawPickPage() {
  float s0 = tabScroll[tab];
  fill(30, 36, 52);
  ellipse(FX(80), FY(140), 64 * fk, 64 * fk);
  stroke(#C9D3E6);
  strokeWeight(3 * fk);
  line(FX(88), FY(124), FX(72), FY(140));
  line(FX(72), FY(140), FX(88), FY(156));
  noStroke();
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(44 * fk);
  boldTextF("Apps to show", FX(130), FY(156));
  fill(#9AA6C0);
  textSizeQ(22 * fk);
  text("Push notifications match by app, SMS by sender. " + watch.size() + " picked.", FX(48), FY(210));
  buildPickRows();
  float top = FY(240), rh = 96 * fk, bottom = barY - 10 * u;
  tabScroll[tab] = constrain(tabScroll[tab], 0, max(0, pickRows.size() * rh - (bottom - top)));
  s0 = tabScroll[tab];
  if (pickRows.size() == 0) {
    fill(#7A8BA0);
    textAlign(CENTER, TOP);
    textSizeQ(23 * fk);
    text("No notifications caught yet: SCAN, or wait for one", FX(426), top + 40 * fk);
  }
  for (int i = 0; i < pickRows.size(); i++) {
    float y = top + i * rh - s0;
    if (y < top - 2 || y + rh > bottom + 2) continue;
    PickRow r = (PickRow) pickRows.get(i);
    boolean on = isWatched(r.key);
    glassCard(FX(38), y + 6 * fk, 776 * fk, rh - 12 * fk, 30 * fk, on ? color(61, 220, 151) : color(50, 70, 120));
    String pkg = r.key.startsWith("sms:") ? "" : r.key;
    if (pkg.length() > 0) drawAppIconAt(appFor(pkg), FX(62), y + 22 * fk, 52 * fk);
    else {
      fill(#2BB59A);
      rrect(FX(62), y + 22 * fk, 52 * fk, 52 * fk, 14 * fk);
      fill(255);
      textAlign(CENTER, CENTER);
      textSizeQ(18 * fk);
      text("SMS", FX(88), y + 47 * fk);
    }
    String name = pkg.length() > 0 ? appFor(pkg).label : r.label;
    fill(#F4F7FF);
    textAlign(LEFT, BASELINE);
    textSizeQ(25 * fk);
    text(fitText(name, 420 * fk), FX(136), y + 46 * fk);
    fill(#9AA6C0);
    textSizeQ(19 * fk);
    text(fitText((pkg.length() > 0 ? pkg : r.sub) + "  ·  " + r.n, 420 * fk), FX(136), y + 74 * fk);
    drawToggle(FX(700), y + rh * 0.5, on);
  }
}

// taps on Settings
void settingsTap(float mx, float my) {
  if (wHeld) { wHeld = false; return; }          // the finger lifting after the hold that opened sub-watch
  if (setPicking) {
    if (dist(mx, my, FX(80), FY(140)) < 50 * fk) { setPicking = false; tabScroll[tab] = 0; return; }
    float top = FY(240), rh = 96 * fk;
    if (my > top) {
      int i = floor((my - top + tabScroll[tab]) / rh);
      buildPickRows();
      if (i >= 0 && i < pickRows.size()) {
        PickRow pr = (PickRow) pickRows.get(i);
        toggleWatch(pr.key);
      }
    }
    return;
  }
  int np = 5;
  float py = FY(372) - tabScroll[tab], pw = 800 * fk, px = FX(426) - pw * 0.5;
  if (my > py - 8 * fk && my < py + 68 * fk && mx > px && mx < px + pw) {
    setPill = constrain(floor((mx - px) / (pw / np)), 0, np - 1);
    if (setPill != 2 && wBack && js != null) { js.walletFront(); wBack = false; }
    savePref("setpill", "" + setPill);
    tabScroll[tab] = 0;
    if (setPill == 2 && js != null) { js.walletRefresh(); wTextAt = -100000; }
    if (setPill == 3) { gTotalsAt = -100000; gOpen = ""; }
    return;
  }
  for (int i = 0; i < setRows.size(); i++) {
    SetRow r = (SetRow) setRows.get(i);
    if (my >= r.y0 && my <= r.y1 && mx > FX(38) && mx < FX(814)) { settingsAct(r.id); return; }
  }
}

void settingsAct(int id) {
  if (flexAct(id)) return;                      // FLEX page rows (Flex.pde)
  if (gstAct(id)) return;                       // GST rows (Gst.pde)
  if (id >= R_WALLET) {                         // a wallet card: rename, copy, check, stop watching
    int n = id - R_WALLET;
    if (js != null && n < wIds.length && wIds[n] != null) js.walletEdit(wIds[n]);
    wTextAt = -100000;
    return;
  }
  if (id == R_WADD) { if (js != null) js.walletAdd(); wTextAt = -100000; return; }
  if (id == R_LESSONS) { if (js != null) js.lessonsOpen(); return; }
  if (id == R_WCLOSE) {
    if (js != null) js.walletFront();
    wBack = false;
    tabScroll[tab] = 0;
    wTextAt = -100000;
    return;
  }
  if (id == R_WREFRESH) {
    if (wHeld) { wHeld = false; return; }       // that was the hold that opens sub-watch, not a tap
    if (js != null) js.walletRefresh();
    appMsg = "Checking your wallets";
    appMsgAt = millis();
    wTextAt = -100000;
    return;
  }
  if (id == R_ACCESS) act(C_ACCESS);
  else if (id == R_USAGE) { if (js != null) js.openUsageAccess(); }
  else if (id == R_SCAN) act(C_SCAN);
  else if (id == R_MANUAL) act(C_MANUAL);
  else if (id == R_CHAT) chatOpen();
  else if (id == R_TILEPLACE) { tilePlace = (tilePlace + 1) % 6; savePref("tileplace", "" + tilePlace); appSig = ""; }
  else if (id == R_ARM) act(armed ? C_ARMOFF : C_ARMON);
  else if (id == R_IPHONE) {
    iphoneOn = !iphoneOn;
    iphoneSaid = "";
    if (js != null) js.iphoneLink(iphoneOn);
    else { appMsg = "iPhone link: on the phone"; appMsgAt = millis(); }
  }
  else if (id == R_RESTRICT) {
    // Android 13+ blocks Notification access for apps not from the Play Store until it's allowed on the
    // app's own App info page (the menu at the top right). The app can open the page, not flip the switch.
    if (js != null) js.openOwnInfo();
    appMsg = "Tap the menu (top right), then Allow restricted settings";
    appMsgAt = millis();
  }
  else if (id == R_BALL) { ballOn = !ballOn; savePref("ball", ballOn ? "1" : "0"); guiDirty = true; }
  else if (id == R_SKIN) { setSkin(skin + 1); savePref("skin", "" + skin); }
  else if (id == R_BRT) {
    int at = 0;
    for (int i = 0; i < brtSteps.length; i++) if (abs(brtSteps[i] - brtVal) < 0.06) at = i;
    brtVal = brtSteps[(at + 1) % brtSteps.length];
    savePref("lid", "" + brtVal);
    guiDirty = true;
  }
  else if (id == R_PICK) { setPicking = true; tabScroll[tab] = 0; }
  else if (id == R_ONLYPICKED) filterOn = !filterOn;
  else if (id == R_LOG) act(C_LOG);
  else if (id == R_CAPTURE) { captureOn = !captureOn; savePref("capture", captureOn ? "1" : "0"); }
  else if (id == R_RETENTION) {
    int at = 0;
    for (int i = 0; i < retentionDays.length; i++) if (retentionDays[i] == retention) at = i;
    retention = retentionDays[(at + 1) % retentionDays.length];
    savePref("retention", "" + retention);
    appMsg = retention == 0 ? "Keeping everything" : "Older than " + (retention == 365 ? "1 year" : retention + " days") + " is cleared when ANA next starts";
    appMsgAt = millis();
  }
  else if (id == R_EFABOUT) efAbout = !efAbout;
  else if (id == R_FEVENT) { futEvent = !futEvent; savePref("fut_event", futEvent ? "1" : "0"); futSig++; mzSig = -1; }
  else if (id == R_FTEXT) { futText = !futText; savePref("fut_text", futText ? "1" : "0"); futSig++; mzSig = -1; }
  else if (id == R_FREMIND) { futRemind = !futRemind; savePref("fut_remind", futRemind ? "1" : "0"); futSig++; mzSig = -1; }
  else if (id == R_ADDREM) { if (js != null) js.addReminder(); else simReminder(); }
  else if (id == R_EFSTART) { efStart = (efStart + 1) % 3; savePref("efstart", "" + efStart); mzStarted = false; }
  else if (id == R_EFFULL) { efFull = !efFull; savePref("effull", efFull ? "1" : "0"); if (!efFull) mzFullOpen = false; }
}

// ---------------------------------------------------------------- SUB-WATCH: behind the front face
// Every wallet, with where it is: on the front, hidden for a while, or hidden until you bring it back.
// Tap one to hide it, bring it back, hide it while the screen is shared, rename it or stop watching it.
float drawSubWatch(float y, String[] lines) {
  String t = "Only you see this page. Hidden wallets aren't on the front face: no card, no activity, no alerts. "
           + "They're still checked quietly, and a hide timer brings them back by itself. Tap a wallet for its options.";
  textSizeQ(20 * fk);
  float th = textBoxHeight(t, 700 * fk, 20 * fk);
  glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, WVIOLET);
  fill(#C9D3E6);
  textAlign(LEFT, TOP);
  text(t, FX(70), y + 24 * fk, 712 * fk, th + 10 * fk);
  y += th + 80 * fk;

  y = setSection("All your wallets", y, WVIOLET);
  int nW = 0;
  for (int i = 0; i < lines.length; i++) {
    String[] f = split(lines[i], "\t");
    if (f.length < 7 || !f[0].equals("S")) continue;
    boolean hid = f[6].equals("1"), share = f.length > 7 && f[7].length() > 0;
    float ch = (share ? 186 : 150) * fk;
    if (nW < wIds.length) wIds[nW] = f[1];
    setRows.add(new SetRow(R_WALLET + nW, y, y + ch));
    glassCard(FX(38), y, 776 * fk, ch, 40 * fk, hid ? WVIOLET : WGOLD);
    fill(hid ? #C9D3E6 : #F4F7FF);
    textAlign(LEFT, BASELINE);
    textSizeQ(27 * fk);
    boldTextF(fitText(f[2], 430 * fk), FX(70), y + 50 * fk);
    fill(#9AA6C0);
    textSizeQ(19 * fk);
    text(fitText(f[3], 500 * fk), FX(70), y + 82 * fk);
    fill(hid ? #C9D3E6 : #FFFFFF);
    textAlign(RIGHT, BASELINE);
    textSizeQ(32 * fk);
    boldTextF(f[4], FX(780), y + 56 * fk);
    color sc = hid ? WVIOLET : color(61, 220, 151);
    fill(sc);
    ellipse(FX(78), y + 115 * fk, 12 * fk, 12 * fk);
    textAlign(LEFT, BASELINE);
    textSizeQ(21 * fk);
    text(fitText(f[5], 680 * fk), FX(96), y + 122 * fk);
    if (share) {
      fill(#7A8BA0);
      textSizeQ(18 * fk);
      text(fitText(f[7], 680 * fk), FX(96), y + 158 * fk);
    }
    y += ch + 20 * fk;
    nW++;
  }
  if (nW == 0) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    textSizeQ(21 * fk);
    text("No wallets yet", FX(70), y + 30 * fk);
    y += 70 * fk;
  }

  y = setGroup(y, 2);
  setRowValue(R_WADD, y, 0, "Add to sub-watch", "Hidden from the front until you bring it out", "", true, WVIOLET);
  setRowValue(R_WCLOSE, y, 1, "Close sub-watch", "Back to the front face", "", true, WGOLD);
  return y + 2 * 100 * fk + 60 * fk;
}

// ---------------------------------------------------------------- WATCH: wallets, read-only
// One card per wallet (tap it: rename, copy the address, check now, stop watching), then "Add an address" and
// "Check now", then the latest activity across the wallets, in plain words.
float drawWatch(float y) {
  if (js == null) {                                // desktop: WATCH runs on the iPhone
    String t = "Watch runs in the app on your phone: it reads your ether.fi Safe on Optimism and your Solana, TRON, Litecoin and Bitcoin wallets straight from public blockchain data.";
    textSizeQ(22 * fk);
    float th = textBoxHeight(t, 700 * fk, 22 * fk);
    glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, WGOLD);
    fill(#C9D3E6);
    textAlign(LEFT, TOP);
    text(t, FX(70), y + 24 * fk, 712 * fk, th + 10 * fk);
    return y + th + 80 * fk;
  }
  if (millis() - wBackAt > 250) {                 // opened after Face ID / fingerprint, closed when ANA leaves
    boolean b = js.walletBack();
    if (b != wBack) { wBack = b; wTextAt = -100000; tabScroll[tab] = 0; }
    wBackAt = millis();
  }
  if (millis() - wTextAt > 1000) {
    wText = js.walletText();
    if (wText == null) wText = "";
    lessonsTxt = js.lessonsText();       // LESSONS, refreshed with the wallets
    if (lessonsTxt == null) lessonsTxt = "";
    wTextAt = millis();
  }
  String[] lines = wText.length() > 0 ? split(wText, "\n") : new String[0];
  if (wBack) return drawSubWatch(y, lines);

  y = setSection("Wallets", y, WGOLD);
  int nW = 0, nA = 0;
  for (int i = 0; i < lines.length; i++) {
    String[] f = split(lines[i], "\t");
    if (f.length >= 11 && f[0].equals("W")) {
      int nr = f.length >= 13 ? 3 : 2;            // a third row: ether.fi's "Available to borrow"
      float ch = (236 + (nr - 2) * 38) * fk;
      if (nW < wIds.length) wIds[nW] = f[1];
      setRows.add(new SetRow(R_WALLET + nW, y, y + ch));
      glassCard(FX(38), y, 776 * fk, ch, 40 * fk, WGOLD);
      fill(#F4F7FF);
      textAlign(LEFT, BASELINE);
      textSizeQ(29 * fk);
      boldTextF(fitText(f[2], 430 * fk), FX(70), y + 54 * fk);
      fill(#9AA6C0);
      textSizeQ(19 * fk);
      text(fitText(f[3], 500 * fk), FX(70), y + 86 * fk);
      fill(#FFFFFF);
      textAlign(RIGHT, BASELINE);
      textSizeQ(40 * fk);
      boldTextF(f[4], FX(780), y + 62 * fk);
      stroke(60, 70, 100, 150);
      strokeWeight(1.2 * fk);
      line(FX(70), y + 106 * fk, FX(780), y + 106 * fk);
      noStroke();
      for (int r = 0; r < nr; r++) {
        float ry = y + (142 + r * 38) * fk;
        String lab = r < 2 ? f[5 + r * 2] : f[11], val = r < 2 ? f[6 + r * 2] : f[12];
        fill(#C9D3E6);
        textAlign(LEFT, BASELINE);
        textSizeQ(23 * fk);
        text(lab, FX(70), ry);
        fill(r == 0 ? #F4F7FF : r == 1 ? WGOLD : #8FB8FF);
        textAlign(RIGHT, BASELINE);
        boldTextF(val, FX(780), ry);
      }
      boolean bad = f[10].startsWith("Couldn");
      fill(bad ? #FF9A5C : #7A8BA0);
      textAlign(LEFT, BASELINE);
      textSizeQ(18 * fk);
      text(fitText(f[10].length() > 0 ? f[10] : f[9], 700 * fk), FX(70), y + ch - 16 * fk);
      y += ch + 20 * fk;
      nW++;
    }
    else if (f.length >= 6 && f[0].equals("A")) nA++;
  }
  if (nW == 0) {
    String t = "No addresses yet. Add your ether.fi Safe (the 0x... address, on Optimism), a Solana wallet such as Jupiter, a TRON wallet (T...), or a Litecoin or Bitcoin wallet you hold yourself (ltc1... / bc1..., e.g. Trust Wallet). Public addresses only: ANA never needs keys or recovery words.";
    textSizeQ(21 * fk);
    float th = textBoxHeight(t, 700 * fk, 21 * fk);
    glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, WGOLD);
    fill(#C9D3E6);
    textAlign(LEFT, TOP);
    text(t, FX(70), y + 24 * fk, 712 * fk, th + 10 * fk);
    y += th + 70 * fk;
  }

  y = setGroup(y, 3);
  setRowValue(R_WADD, y, 0, "Add an address", "ether.fi, Solana, TRON, Litecoin or Bitcoin", "", true, WGOLD);
  setRowValue(R_WREFRESH, y, 1, "Check now", "Balances and activity (also every 2 minutes)", "", true, color(61, 220, 151));
  // SUB-WATCH: hold Check Now (about 2 seconds, without sliding) and the phone asks for Face ID / fingerprint
  float hy = y + 100 * fk;
  if (mousePressed && !wHeld && !moved && tab == T_SETTINGS && pressY > hy && pressY < hy + 100 * fk
      && pressX > FX(38) && pressX < FX(814) && abs(mouseY - pressY) < 24 * fk && millis() - wPressAt > 1800) {
    wHeld = true;
    js.walletReveal();
  }
  // LESSONS: the coins signed lesson files taught ANA
  String lt = lessonsTxt;
  int nl = lt == null || lt.length() == 0 ? 0 : split(lt.trim(), "\n").length;
  setRowValue(R_LESSONS, y, 2, "Lessons", "Teach WATCH a new coin with a signed lesson file", nl == 0 ? "None yet" : nl + (nl == 1 ? " coin" : " coins"), true, WGOLD);
  y += 3 * 100 * fk + 30 * fk;

  y = setSection("Activity", y, #4DA3FF);
  if (nA == 0) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    textSizeQ(21 * fk);
    text("Nothing yet", FX(70), y + 30 * fk);
    y += 70 * fk;
  }
  else {
    float rh = 92 * fk;
    glassCard(FX(38), y, 776 * fk, nA * rh, 40 * fk, color(60, 90, 180));
    int k = 0;
    for (int i = 0; i < lines.length; i++) {
      String[] f = split(lines[i], "\t");
      if (f.length < 6 || !f[0].equals("A")) continue;
      float ry = y + k * rh;
      if (k > 0) {
        stroke(40, 50, 78, 170);
        strokeWeight(1.2 * fk);
        line(FX(140), ry, FX(794), ry);
        noStroke();
      }
      color sc = f[3].equals("+") ? color(61, 220, 151) : f[3].equals("-") ? color(255, 170, 80) : color(110, 170, 255);
      for (int g = 4; g >= 1; g--) {
        fill(red(sc), green(sc), blue(sc), 14);
        ellipse(FX(96), ry + rh * 0.5, (40 + g * 7) * fk, (40 + g * 7) * fk);
      }
      fill(red(sc) * 0.3, green(sc) * 0.3, blue(sc) * 0.3);
      ellipse(FX(96), ry + rh * 0.5, 44 * fk, 44 * fk);
      fill(sc);
      textAlign(CENTER, CENTER);
      textSizeQ(28 * fk);
      boldTextF(f[3].equals("~") ? "~" : f[3].equals("-") ? "-" : "+", FX(96), ry + rh * 0.5 - 2 * fk);
      fill(#F4F7FF);
      textAlign(LEFT, BASELINE);
      textSizeQ(23 * fk);
      text(fitText(f[5], 440 * fk), FX(140), ry + 40 * fk);
      fill(#9AA6C0);
      textSizeQ(18 * fk);
      text(fitText(f[1] + "  ·  " + f[2], 440 * fk), FX(140), ry + 68 * fk);
      fill(sc);
      textAlign(RIGHT, BASELINE);
      textSizeQ(25 * fk);
      boldTextF((f[3].equals("~") ? "" : f[3]) + f[4], FX(780), ry + 52 * fk);
      k++;
    }
    y += nA * rh + 30 * fk;
  }

  String t = "Watch only reads public blockchain data, on this phone: no keys, no login, no signing. "
           + "ether.fi Cash: Ready to spend is the USDC in your Safe on Optimism; Earning is what ether.fi has lent out for you "
           + "(read from ether.fi's lending gateway, interest included). TRON wallets show USDT and TRX; Litecoin and Bitcoin show the coins you hold and their value at today's price. "
           + "Anything new also appears on Pulse as a Watch entry.";
  textSizeQ(20 * fk);
  float th = textBoxHeight(t, 700 * fk, 20 * fk);
  glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, color(150, 110, 255));
  fill(#9AA6C0);
  textAlign(LEFT, TOP);
  text(t, FX(70), y + 24 * fk, 712 * fk, th + 10 * fk);
  return y + th + 80 * fk;
}


// ---------------------------------------------------------------- ANA's promises (the ZF rule and the money rule)
// Shown on the ANA settings page, always: nobody should ever be unsure.
final String[] PROMISES = {
  "Zero friction: keep doing what you already do. ANA fits around you.",
  "Your notifications are your business. They stay on your phone.",
  "Novvera never touches money. Not yours, not your group's, not ever.",
  "No ads, ever. Your data is never sold."
};

float drawPromises(float y) {
  float h = 70 * fk + PROMISES.length * 44 * fk;
  glassCard(FX(38), y, 776 * fk, h, 34 * fk, color(61, 220, 151));
  textAlign(LEFT, BASELINE);
  fill(#3DDC97);
  textSizeQ(19 * fk);
  boldTextF("ANA'S PROMISES", FX(70), y + 42 * fk);
  textSizeQ(20 * fk);
  for (int i = 0; i < PROMISES.length; i++) {
    fill(i == 2 ? #FFFFFF : #C9D3E6);
    text(fitText((i + 1) + "   " + PROMISES[i], 712 * fk), FX(70), y + 84 * fk + i * 44 * fk);
  }
  return y + h + 30 * fk;
}
