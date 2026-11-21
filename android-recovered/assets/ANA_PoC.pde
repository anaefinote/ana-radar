// ANA_PoC — Notification Compiler proof of concept
// Access Novera Analytics · v0.6 (ball UI)
//
// Runs in TWO places from the SAME source:
//   1. Processing 1.5.1 desktop  -> simulation mode (no phone needed)
//   2. Android APK               -> Processing.js inside a WebView, fed by the
//                                   native notification listener (see Bridge.pde)
//
// The screen: the control ball on top (Ball.pde), the list for the tab under it,
// and the bar at the bottom (Bar.pde) with Pulse, Archive, Timeline and Settings.
//   Pulse     today's notifications. Ball: SCAN, MANUAL, ARM / OFF
//   Archive   everything. Tap cards to select. Ball: EXPORT, IMPORT, PICKED / ALL, SELECT ALL, CLEAR
//   Timeline  one day at a time. Ball: OLDER, NEWER, TODAY
//   Settings  the apps to show (tap to pick). Ball: ACCESS, LOG, LID, SKIN
//   APPify    the apps the notifications come from, as icons on a glass ball: tap one to open it (Appify.pde)
// Drag the ball up or down to roll it: the list under it scrolls with it. Drag it sideways to turn it.
// It eases back to face you. It nods when something works and shakes when there's nothing to do,
// and spins once when a notification arrives.
//
// Desktop keys:  1-5 = tabs (Pulse, Archive, APPify, Timeline, Settings)   S = SCAN   L = LIVE push   T = LIVE SMS   M = MANUAL
//                O = LIVE from another app   A = ARM / disarm   + / - = deeper / up in the Archive maze
//
// Keep this sketch Processing.js-safe: no rounded rect, no clip(),
// no int/int division, ArrayList with casts, colours as #RRGGBB.

ArrayList entries = new ArrayList();

String status = "DESKTOP SIM";
boolean armed = false;
int armedAt = 0;
String armedHit = "";
int flashAt = -10000;

int nLive = 0, nScan = 0, nManual = 0, nDup = 0, nImport = 0;

boolean filterOn = true;      // show only the picked apps (MANUAL, IMPORT and SYS always show)
ArrayList watch = new ArrayList();   // picked keys: a package name, or "sms:<sender>" for SMS
boolean prefsLoaded = false;
ArrayList pickRows = new ArrayList();
ArrayList shown = new ArrayList();   // the cards on screen this frame, for tapping
int nextLine = -1;            // log line number of the next onNotif (set by the Android side)
String tlDay = "";            // the Timeline's day, yyyy-mm-dd

float u = 1;                  // UI scale: 1.0 at 480 px wide
int lastW = -1, lastH = -1;
float listTop, listBottom, stripY;

// scrolling: one position per tab; the ball rolls with it
float[] tabScroll = new float[5];
float listVel = 0;
float seenScroll = 0;
int seenTab = -1;

// touch
final int D_NONE = 0, D_LIST = 1, D_BALL = 2, D_SLIDER = 3;
int dragMode = D_NONE;
float pressX = 0, pressY = 0, lastMY = 0, lastMX = 0, lastDY = 0;
boolean moved = false;
Ctl pressedCtl = null;

void setup() {
  size(480, 900);         // desktop size; the APK resizes to 100% device pixels
  smooth();
  // ballSetup() waits until the control ball is turned on (it's off by default): ensureBall()
  tlDay = today();
}

void layout() {
  lastW = width;
  lastH = height;
  u = min(width / 480.0, height / 900.0);
  barLayout();
  float r = min(150 * u, width * 0.5 - 20 * u);
  ballLayout(r, width * 0.5, 14 * u + r);
  stripY = ballCY + r + 16 * u;
  listTop = stripY + 30 * u;
  listBottom = barY - 10 * u;
  appifyLayout();
  flatLayout();
}

boolean ballReady = false;
void ensureBall() {
  if (ballReady) return;
  ballReady = true;
  ballSetup();
}

void draw() {
  if (width != lastW || height != lastH) layout();
  if (js != null && !prefsLoaded) loadPrefs();
  flexTick();                                     // FLEX: GST mail, dialogs and the daily eFLEX samples (Flex.pde)
  if (frameCount % 30 == 1) {
    String s = (js != null) ? js.status() : "DESKTOP SIM";
    if (!s.equals(status)) {
      status = s;
      if (tab == T_PULSE) guiDirty = true;
    }
  }
  skinPoll();
  if (ballOn) ensureBall();
  if (!frameWanted()) return;                     // nothing can look different: keep the last frame
  lastDrawAt = millis();
  iconBudget = 2;
  if (chatOn) { drawChat(); return; }          // CHATNOTE (Chat.pde) takes the whole screen while open

  if (!(tab == T_ARCHIVE && flatTab())) mazeLeave();   // the maze's GPU layer only shows on Archive
  if (tab == T_APPIFY) {               // APPify has its own screen (Appify.pde) above the bar
    drawAppify();
    drawBar();
    drawFlexChip();                    // FLEX: the pill right above APPify, and the wallet when open (Flex.pde)
    drawFlexPanel();
    return;
  }
  if (flatTab()) {                     // the flat screens (control ball off, and Settings always)
    if (tab == T_PULSE) {
      boolean part = pulsePartial() && !fOpen;     // FLEX: the open wallet covers the whole screen
      drawPulse2(part);
      if (part) { drawFlexChip(); return; }   // only the top moved: the rest of the screen stays as it was
    }
    else if (tab == T_ARCHIVE) drawMaze();
    else if (tab == T_TIMELINE) drawTimeline2();
    else drawSettings2();
    drawReader();                      // a notification being read (Reader.pde), over the screen
    drawFlexChip();                    // FLEX: the chip at the top, and the wallet when it's open (Flex.pde)
    drawFlexPanel();
    drawToast();
    drawBar();
    return;
  }
  physics();

  background(#05070C);
  drawList();
  noStroke();
  fill(#05070C);
  rect(0, 0, width, listTop);                 // the list scrolls under the ball area (no clip in 1.5.1)
  rect(0, listBottom, width, height - listBottom);
  drawBall();
  drawStrip();
  drawBar();

  if (millis() - flashAt < 600) {
    noFill();
    stroke(#3DDC97);
    strokeWeight(8 * u);
    rect(0, 0, width, height);
    noStroke();
  }
}

// ---------------------------------------------------------------- motion
void physics() {
  // fling
  if (dragMode == D_NONE && abs(listVel) > 0.3) {
    tabScroll[tab] -= listVel;
    listVel *= 0.93;
  }
  else if (dragMode == D_NONE) listVel = 0;

  // the ball rolls with the list, like a ball rolling along it
  if (seenTab != tab) {
    seenTab = tab;
    seenScroll = tabScroll[tab];
  }
  float d = tabScroll[tab] - seenScroll;
  seenScroll = tabScroll[tab];
  rollOff += d / sr;

  // when nothing holds it, it eases back to face you (to the nearest whole turn)
  int now = millis();
  float dt = constrain(now - lastTick, 0, 200);
  lastTick = now;
  if (dragMode != D_BALL && abs(listVel) < 2) {
    float rt = round(rollOff / TWO_PI) * TWO_PI;
    float yt = round(yawOff / TWO_PI) * TWO_PI;
    float f = 1 - pow(0.84, dt / 16.7);          // same ease at any frame rate
    rollOff += (rt - rollOff) * f;
    yawOff += (yt - yawOff) * f;
    if (abs(rt - rollOff) < 0.0005) rollOff = rt;
    if (abs(yt - yawOff) < 0.0005) yawOff = yt;
  }
}

// ---------------------------------------------------------------- input
// Called by the Android listener (via JavaScript) or by the desktop sim. when = "yyyy-mm-dd hh:mm:ss".
void onNotif(String src, String when, String pkg, String title, String body, String key, String lag, String ev) {
  poke();
  Entry e = new Entry(src, when, pkg, title, body, key, lag);
  e.ev = ev == null ? "" : ev;
  e.logLine = nextLine;
  nextLine = -1;

  if (key.length() > 0) {
    for (int i = 0; i < entries.size(); i++) {
      Entry o = (Entry) entries.get(i);
      if (o.nkey.equals(key) && o.body.equals(body)) {
        e.dup = true;
        break;
      }
    }
  }

  if (src.equals("LIVE")) {
    nLive++;
    if (e.dup) nDup++;
    if (armed && armedHit.length() == 0) {
      armedHit = "caught after " + nf((millis() - armedAt) / 1000.0, 1, 1) + "s";
    }
    flashAt = millis();
    spin();
    bellAt = millis();
  }
  else if (src.equals("SCAN")) nScan++;
  else if (src.equals("MANUAL")) nManual++;
  else if (src.equals("IMPORT")) nImport++;

  entries.add(0, e);
  if (entries.size() > 500) entries.remove(entries.size() - 1);
  if (tab == T_TIMELINE) guiDirty = true;     // the day's count is on the ball
}

// The Android side calls this just before onNotif() with the entry's line number in ana_log.txt,
// so EXPORT can hand the exact log lines to the .pngmesh writer.
void setNextLine(int n) {
  nextLine = n;
}

void act(int id) {
  if (id == C_SCAN) {
    if (js != null) js.scan();
    else simScan();
    nod();
  }
  else if (id == C_MANUAL) {
    if (js != null) js.manualEntry();
    else simManual();
    nod();
  }
  else if (id == C_ARMON) {
    armed = true;
    armedAt = millis();
    armedHit = "";
    nod();
  }
  else if (id == C_ARMOFF) {
    if (armed) nod();
    else shake();
    armed = false;
  }
  else if (id == C_EXPORT) {
    if (selectedCount() > 0) {                     // selected cards -> .pngmesh + .sha256
      if (js != null) js.exportPngmesh(selectedLines());
      else dumpSelected();
      clearSelection();
      nod();
    }
    else shake();                                  // nothing selected (the text log is under Settings > LOG)
  }
  else if (id == C_IMPORT) {
    if (js != null) js.importFiles();
    else println("IMPORT: phone only (opens the file picker for .pngmesh files)");
    nod();
  }
  else if (id == C_PICKED || id == C_ALL) {
    filterOn = (id == C_PICKED);
    tabScroll[tab] = 0;
    seenScroll = 0;
    nod();
  }
  else if (id == C_SELALL) {
    if (shown.size() == 0) shake();
    else {
      selectAllShown();
      nod();
    }
  }
  else if (id == C_CLEAR) {
    if (selectedCount() == 0) shake();
    else {
      clearSelection();
      nod();
    }
  }
  else if (id == C_PREV || id == C_NEXT) {
    String[] days = dayList();
    int at = -1;
    for (int i = 0; i < days.length; i++) if (days[i].equals(tlDay)) at = i;
    // days run newest first: OLDER = further down the list
    int to;
    if (at < 0) {
      to = -1;
      if (id == C_PREV) { for (int i = 0; i < days.length && to < 0; i++) if (dayNum(days[i]) < dayNum(tlDay)) to = i; }
      else { for (int i = days.length - 1; i >= 0 && to < 0; i--) if (dayNum(days[i]) > dayNum(tlDay)) to = i; }
    }
    else to = (id == C_PREV) ? at + 1 : at - 1;
    if (to < 0 || to >= days.length) shake();
    else {
      tlDay = days[to];
      tabScroll[tab] = 0;
      seenScroll = 0;
      nod();
    }
  }
  else if (id == C_TODAY) {
    tlDay = today();
    tabScroll[tab] = 0;
    seenScroll = 0;
    nod();
  }
  else if (id == C_ACCESS) {
    if (js != null) js.openAccess();
    else println("ACCESS: phone only (opens Notification access settings)");
    nod();
  }
  else if (id == C_LOG) {
    if (js != null) js.exportLog();
    else dumpEntries();
    nod();
  }
  else if (id == C_SKINPREV || id == C_SKINNEXT) {
    setSkin(skin + (id == C_SKINNEXT ? 1 : -1));
    savePref("skin", "" + skin);
    spin();
  }
  guiDirty = true;
}

void mousePressed() {
  poke();
  if (chatOn) { chatPress(mouseX, mouseY); return; }
  pressX = mouseX;
  pressY = mouseY;
  lastMX = mouseX;
  lastMY = mouseY;
  lastDY = 0;
  moved = false;
  listVel = 0;
  pressedCtl = null;
  wPressAt = millis();       // SUB-WATCH: the hold on Check Now
  wHeld = false;

  if (onBar(mouseX, mouseY)) {
    int t = tabAt(mouseX, mouseY);
    if (t >= 0 && t != tab) setTab(t);
    else if (t == T_APPIFY && tab == T_APPIFY) appifyHome();   // APPify again: back to the default view
    dragMode = D_NONE;
    return;
  }
  if (tab == T_APPIFY) {
    if (!fOpen && !flexChipHit(mouseX, mouseY)) appifyPressed(mouseX, mouseY);   // FLEX: its pill and wallet first
    dragMode = D_NONE;
    return;
  }
  if (flatTab()) {
    dragMode = D_LIST;
    return;
  }
  if (onBall(mouseX, mouseY)) {
    pressedCtl = ctlAt(mouseX, mouseY);
    if (pressedCtl != null && pressedCtl.id == C_LID) {
      dragMode = D_SLIDER;
      setLid(mouseX, mouseY);
    }
    else dragMode = D_BALL;
    pressCtl = (pressedCtl != null) ? pressedCtl.id : 0;
    return;
  }
  if (mouseY >= listTop && mouseY <= listBottom) dragMode = D_LIST;
  else dragMode = D_NONE;
}

void mouseDragged() {
  if (chatOn) { poke(); chatDrag(mouseX, mouseY); return; }
  if (fOpen) return;                             // FLEX: the wallet doesn't scroll the screen under it
  poke();
  if (tab == T_APPIFY) {
    appifyDragged(mouseX, mouseY);
    return;
  }
  if (flatTab() && dragMode == D_LIST && readerE != null) {   // nothing under the reader moves
    if (abs(mouseX - pressX) > 12 * u || abs(mouseY - pressY) > 12 * u) moved = true;
    return;
  }
  if (flatTab() && dragMode == D_LIST) {
    float fdx = mouseX - lastMX, fdy = mouseY - lastMY;
    lastMX = mouseX;
    lastMY = mouseY;
    if (abs(mouseX - pressX) > 12 * u || abs(mouseY - pressY) > 12 * u) moved = true;
    if (!moved) return;
    if (tab == T_ARCHIVE) mazeDrag(fdx, fdy);
    else if (tab == T_TIMELINE && onCalendar(pressX, pressY)) tlSwipe = mouseX - pressX;
    else tabScroll[tab] -= fdy;
    return;
  }
  float dx = mouseX - lastMX, dy = mouseY - lastMY;
  lastMX = mouseX;
  lastMY = mouseY;
  if (abs(mouseX - pressX) > 12 * u || abs(mouseY - pressY) > 12 * u) moved = true;

  if (dragMode == D_SLIDER) {
    setLid(mouseX, mouseY);
    return;
  }
  if (dragMode == D_BALL) {
    if (moved) {
      pressedCtl = null;
      pressCtl = 0;
    }
    tabScroll[tab] -= dy * 1.5;            // roll the ball: the list follows the finger
    yawOff += dx / sr;
    lastDY = dy * 1.5;
  }
  else if (dragMode == D_LIST) {
    tabScroll[tab] -= dy;
    lastDY = dy;
  }
}

void mouseReleased() {
  poke();
  if (chatOn) { chatRelease(mouseX, mouseY); return; }
  if (tab == T_APPIFY) {
    if (fOpen) { flexPanelTap(mouseX, mouseY); return; }                       // FLEX: the wallet takes every tap
    if (flexChipHit(pressX, pressY) && flexChipHit(mouseX, mouseY)) { fOpen = true; return; }
    appifyReleased(mouseX, mouseY);
    return;
  }
  if (tab == T_ARCHIVE) mazeRelease();
  if (flatTab() && dragMode == D_LIST) {
    dragMode = D_NONE;
    if (fOpen) {                                 // FLEX: the wallet takes every tap while it's open
      if (!moved) flexPanelTap(mouseX, mouseY);
      return;
    }
    if (!moved && readerE == null && flexChipHit(pressX, pressY)) { fOpen = true; return; }
    if (readerE != null) {                       // the reader takes every tap while it's open
      if (!moved) readerTap(mouseX, mouseY);
      return;
    }
    if (!moved) {
      if (tab == T_PULSE) pulseTap(mouseX, mouseY);
      else if (tab == T_ARCHIVE) mazeTap(mouseX, mouseY);
      else if (tab == T_TIMELINE) timelineTap(mouseX, mouseY);
      else settingsTap(mouseX, mouseY);
    }
    else if (tab == T_TIMELINE && onCalendar(pressX, pressY)) timelineSwipe(mouseX - pressX);
    tlSwipe = 0;
    return;
  }
  if (dragMode == D_NONE && onBar(mouseX, mouseY)) return;
  if (dragMode == D_BALL && !moved && pressedCtl != null) act(pressedCtl.id);
  else if (dragMode == D_SLIDER) {
    savePref("lid", "" + brtVal);
    guiDirty = true;
  }
  else if (dragMode == D_LIST && !moved) tapList(mouseX, mouseY);
  else if ((dragMode == D_LIST || dragMode == D_BALL) && moved) listVel = lastDY;
  dragMode = D_NONE;
  pressedCtl = null;
  pressCtl = 0;
}

// the flat screens: Settings always; Pulse / Archive / Timeline when the control ball is off
boolean flatTab() {
  return tab == T_SETTINGS || (!ballOn && tab != T_APPIFY);
}

void setTab(int t) {
  poke();
  readerE = null;
  if (tab == T_PULSE) pulseSeen = countToday();
  if (t == T_SETTINGS) setPicking = false;
  tab = t;
  guiDirty = true;
  spin();
  savePref("tab", "" + t);
}

void setLid(float mx, float my) {
  float[] t = texAt(mx, my);
  if (t == null) return;
  brtVal = sliderVal(t[0]);
  guiDirty = true;
}

void tapList(float mx, float my) {
  if (tab == T_SETTINGS) {
    PickRow r = pickAt(mx, my);
    if (r != null) toggleWatch(r.key);
    return;
  }
  if (tab != T_ARCHIVE) return;            // cards are selected in the Archive
  Entry e = cardAt(mx, my);
  if (e != null) {
    e.selected = !e.selected;
    guiDirty = true;                       // "n selected" is on the ball
  }
}

void keyPressed() {
  poke();
  int t = -1;
  if (key == '1') t = T_PULSE;
  if (key == '2') t = T_ARCHIVE;
  if (key == '3') t = T_APPIFY;
  if (key == '4') t = T_TIMELINE;
  if (key == '5') t = T_SETTINGS;
  if (t >= 0 && t != tab) setTab(t);
  if (tab == T_ARCHIVE && (key == '+' || key == '=')) mazeDive(1);      // desktop: deeper (pinch out on the phone)
  if (tab == T_ARCHIVE && key == '-') mazeDive(-1);                      // up toward the surface
  if (key == 's' || key == 'S') act(C_SCAN);
  if (key == 'l' || key == 'L') simLive();
  if (key == 't' || key == 'T') simSms();
  if (key == 'm' || key == 'M') act(C_MANUAL);
  if (key == 'o' || key == 'O') simOther();
  if (key == 'r' || key == 'R') simReminder();
  if (tab == T_APPIFY && (key == 'c' || key == 'C') && apps.size() > 0) {    // desktop: touch the next app (its panel)
    int i = selApp == null ? 0 : (apps.indexOf(selApp) + 1) % apps.size();
    chooseApp((AppIcon) apps.get(i));
  }
  if (key == 'a' || key == 'A') act(armed ? C_ARMOFF : C_ARMON);
}

// ---------------------------------------------------------------- lists
boolean passes(Entry e) {
  return !filterOn || e.alwaysShown() || isWatched(e.watchKey());
}

void collectShown() {
  shown.clear();
  String td = today();
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!passes(e)) continue;
    if (tab == T_PULSE && !e.ymd.equals(td)) continue;
    if (tab == T_TIMELINE && !e.ymd.equals(tlDay)) continue;
    shown.add(e);
  }
}

void drawList() {
  float ch = 120 * u;
  int count;
  if (tab == T_SETTINGS) {
    buildPickRows();
    count = pickRows.size();
    ch = 70 * u;
  }
  else {
    collectShown();
    count = shown.size();
  }

  float maxScroll = max(0, count * ch - (listBottom - listTop));
  float s = tabScroll[tab];
  if (s < 0 || s > maxScroll) {
    tabScroll[tab] = constrain(s, 0, maxScroll);
    listVel = 0;
  }
  float scrollY = tabScroll[tab];

  if (count == 0) {
    fill(#7A8BA0);
    textAlign(CENTER, TOP);
    textSizeQ(15 * u);
    text(emptyText(), width / 2.0, listTop + 30 * u);
    return;
  }

  for (int i = 0; i < count; i++) {
    float y = listTop + i * ch - scrollY;
    if (y > listBottom) break;
    if (y + ch < listTop) continue;
    if (tab == T_SETTINGS) drawPickRow((PickRow) pickRows.get(i), y, ch);
    else ((Entry) shown.get(i)).drawCard(12 * u, y, width - 24 * u, ch - 8 * u);
  }
}

String emptyText() {
  if (tab == T_SETTINGS) return "No notifications caught yet.\nTap SCAN on Pulse, or wait for one to arrive,\nthen pick its app here.";
  if (entries.size() == 0) return "No notifications yet.\nSettings > ACCESS once, then SCAN on Pulse.";
  if (filterOn && watch.size() == 0) return "No apps picked yet.\nPick the apps to show in Settings,\nor tap ALL on the Archive ball.";
  if (tab == T_PULSE) return "Nothing from the picked apps today.";
  if (tab == T_TIMELINE) return "Nothing from the picked apps on this day.";
  return "Nothing from the picked apps yet.";
}

// the line between the ball and the list
void drawStrip() {
  String s;
  color c = #8FA3B8;
  if (tab == T_PULSE) {
    if (armed) {
      c = #3DDC97;
      if (armedHit.length() > 0) s = "ARMED  ·  " + armedHit;
      else s = "ARMED  ·  waiting " + nf((millis() - armedAt) / 1000.0, 1, 1) + "s";
    }
    else s = "Today " + shown.size() + "     live " + nLive + "  scan " + nScan + "  dup " + nDup + "  manual " + nManual;
  }
  else if (tab == T_ARCHIVE) {
    int nSel = selectedCount();
    if (nSel > 0) {
      c = #F5B942;
      s = nSel + " selected  ·  EXPORT on the ball makes a .pngmesh";
    }
    else s = shown.size() + " entries" + (filterOn ? "  ·  " + watch.size() + " picked apps" : "  ·  all apps") + "  ·  tap to select";
  }
  else if (tab == T_TIMELINE) s = tlDay + "  ·  " + shown.size() + " entries";
  else s = "Tap the apps to show  ·  " + watch.size() + " picked";
  fill(c);
  textAlign(LEFT, CENTER);
  textSizeQ(13 * u);
  text(s, 16 * u, stripY + 10 * u);
}

Entry cardAt(float mx, float my) {
  float ch = 120 * u;
  if (my < listTop || my > listBottom) return null;
  int i = floor((my - listTop + tabScroll[tab]) / ch);
  if (i < 0 || i >= shown.size()) return null;
  if (my - listTop + tabScroll[tab] - i * ch > ch - 8 * u) return null;      // the gap between cards
  return (Entry) shown.get(i);
}

int selectedCount() {
  int n = 0;
  for (int i = 0; i < entries.size(); i++) if (((Entry) entries.get(i)).selected) n++;
  return n;
}

void clearSelection() {
  for (int i = 0; i < entries.size(); i++) ((Entry) entries.get(i)).selected = false;
}

// SELECT ALL selects every card in the Archive list (so it follows PICKED / ALL)
boolean allShownSelected() {
  if (tab != T_ARCHIVE) return false;
  collectShown();
  if (shown.size() == 0) return false;
  for (int i = 0; i < shown.size(); i++) if (!((Entry) shown.get(i)).selected) return false;
  return true;
}

void selectAllShown() {
  collectShown();
  for (int i = 0; i < shown.size(); i++) ((Entry) shown.get(i)).selected = true;
}

// "12,15,20": the log lines of the selected cards, oldest first
String selectedLines() {
  String out = "";
  for (int i = entries.size() - 1; i >= 0; i--) {
    Entry e = (Entry) entries.get(i);
    if (e.selected && e.logLine >= 0) out += (out.length() > 0 ? "," : "") + e.logLine;
  }
  return out;
}

// ---------------------------------------------------------------- days
String today() {
  return nf(year(), 4) + "-" + nf(month(), 2) + "-" + nf(day(), 2);
}

// the days that have entries (picked apps), newest first
String[] dayList() {
  ArrayList ds = new ArrayList();
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!passes(e)) continue;
    boolean have = false;
    for (int j = 0; j < ds.size(); j++) {
      String d = (String) ds.get(j);
      if (d.equals(e.ymd)) have = true;
    }
    if (!have) ds.add(e.ymd);
  }
  String[] out = new String[ds.size()];
  for (int i = 0; i < out.length; i++) out[i] = (String) ds.get(i);
  out = sort(out);
  return reverse(out);
}

int countDay(String d) {
  int n = 0;
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (passes(e) && e.ymd.equals(d)) n++;
  }
  return n;
}

// ---------------------------------------------------------------- picked apps
boolean isWatched(String k) {
  for (int i = 0; i < watch.size(); i++) {
    String w = (String) watch.get(i);
    if (w.equals(k)) return true;
  }
  return false;
}

void toggleWatch(String k) {
  for (int i = 0; i < watch.size(); i++) {
    String w = (String) watch.get(i);
    if (w.equals(k)) {
      watch.remove(i);
      saveWatch();
      return;
    }
  }
  watch.add(k);
  saveWatch();
}

// kept on the phone; the desktop sim keeps them in memory only
void loadPrefs() {
  prefsLoaded = true;
  watch.clear();
  String[] ks = split(js.watchList(), "\n");
  for (int i = 0; i < ks.length; i++) if (trim(ks[i]).length() > 0) watch.add(trim(ks[i]));
  String sk = js.pref("skin");
  if (sk.length() > 0) setSkin(int(sk));
  String tb = js.pref("tab");
  if (tb.length() > 0) tab = constrain(int(tb), 0, NTABS - 1);
  ballOn = js.pref("ball").equals("1");                  // the control ball: off unless turned on
  String sp = js.pref("setpill");
  if (sp.length() > 0) setPill = constrain(int(sp), 0, 4);   // 2 = WATCH, 3 = GST, 4 = FLEX
  captureOn = !js.pref("capture").equals("0");
  String rt = js.pref("retention");
  if (rt.length() > 0) retention = int(rt);
  futEvent = !js.pref("fut_event").equals("0");
  futText = !js.pref("fut_text").equals("0");
  futRemind = !js.pref("fut_remind").equals("0");
  String es = js.pref("efstart");
  if (es.length() > 0) efStart = constrain(int(es), 0, 2);
  efFull = js.pref("effull").equals("1");
  iphoneOn = js.pref("iphone").equals("1");
  if (js.pref("tileplace").length() > 0) tilePlace = constrain(int(js.pref("tileplace")), 0, 5);
  mzLock = !js.pref("eflock").equals("0");
  String am = js.pref("appmode");
  if (am.length() > 0) appMode = constrain(int(am), 0, 3);
  String lid = js.pref("lid");
  if (lid.length() > 0) brtVal = constrain(float(lid), 0, 1);
  guiDirty = true;
}

void saveWatch() {
  if (js == null) return;
  String out = "";
  for (int i = 0; i < watch.size(); i++) out += (i > 0 ? "\n" : "") + (String) watch.get(i);
  js.saveWatch(out);
}

void savePref(String k, String v) {
  if (js != null) js.setPref(k, v);
}

// one row per app / SMS sender seen, newest first, plus picked ones not seen this session
void buildPickRows() {
  pickRows.clear();
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (e.alwaysShown()) continue;
    String k = e.watchKey();
    PickRow r = null;
    for (int j = 0; j < pickRows.size(); j++) {
      PickRow o = (PickRow) pickRows.get(j);
      if (o.key.equals(k)) { r = o; break; }
    }
    if (r == null) {
      r = new PickRow();
      r.key = k;
      if (e.isSms()) {
        r.label = "SMS from " + e.title;
        r.sub = "text message  ·  " + e.pkg;
      }
      else {
        r.label = e.pkg;
        r.sub = "last: " + e.title;
      }
      pickRows.add(r);
    }
    r.n++;
  }
  for (int i = 0; i < watch.size(); i++) {
    String k = (String) watch.get(i);
    boolean seen = false;
    for (int j = 0; j < pickRows.size(); j++) {
      PickRow o = (PickRow) pickRows.get(j);
      if (o.key.equals(k)) seen = true;
    }
    if (!seen) {
      PickRow r = new PickRow();
      r.key = k;
      r.label = k.startsWith("sms:") ? "SMS from " + k.substring(4) : k;
      r.sub = "picked  ·  nothing from it yet";
      pickRows.add(r);
    }
  }
}

void drawPickRow(PickRow r, float y, float rh) {
  boolean on = isWatched(r.key);
  noStroke();
  fill(on ? #16324A : #18212D);
  rect(12 * u, y, width - 24 * u, rh - 8 * u);
  fill(on ? #4DA3FF : #22303F);
  rect(24 * u, y + 19 * u, 24 * u, 24 * u);
  if (on) {
    fill(#0E1621);
    textAlign(CENTER, CENTER);
    textSizeQ(15 * u);
    text("x", 36 * u, y + 30 * u);
  }
  textAlign(LEFT, TOP);
  fill(#E8EEF5);
  textSizeQ(15 * u);
  text(r.label, 62 * u, y + 10 * u, width - 140 * u, 22 * u);
  fill(#7A8BA0);
  textSizeQ(12 * u);
  text(r.sub, 62 * u, y + 36 * u, width - 140 * u, 18 * u);
  fill(#8FA3B8);
  textAlign(RIGHT, TOP);
  textSizeQ(13 * u);
  if (r.n > 0) text("" + r.n, width - 24 * u, y + 10 * u);
}

PickRow pickAt(float mx, float my) {
  float rh = 70 * u;
  if (my < listTop || my > listBottom) return null;
  int i = floor((my - listTop + tabScroll[tab]) / rh);
  if (i < 0 || i >= pickRows.size()) return null;
  return (PickRow) pickRows.get(i);
}

class PickRow {
  String key = "", label = "", sub = "";
  int n = 0;
}

// ---------------------------------------------------------------- desktop simulation
// SIM text is a placeholder. The real ether.fi wording comes from test #2's log.
String clock() {
  return today() + " " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
}

void simScan() {
  onNotif("SCAN", clock(), "sim.etherfi", "ether.fi (SIM)", "SIM: Card payment USD 12.50 at Test Merchant", "sim-scan-1", "", "");
  onNotif("SCAN", clock(), "sim.sms", "ether.fi SMS (SIM)", "SIM: Card payment USD 12.50 at Test Merchant", "sim-scan-2", "", "");
}

void simLive() {
  onNotif("LIVE", clock(), "sim.etherfi", "ether.fi (SIM)", "SIM: Card payment USD 4.75 at Coffee Shop", "sim-live-" + millis(), "38", "");
}

void simSms() {
  onNotif("LIVE", clock(), "sim.sms", "ether.fi SMS (SIM)", "SIM: Card payment USD 4.75 at Coffee Shop", "sim-sms-" + millis(), "52", "");
}

void simOther() {
  onNotif("LIVE", clock(), "sim.chat", "Chat app (SIM)", "SIM: Your table is booked for tomorrow at 7pm", "sim-other-" + millis(), "41", "");
}

// desktop: a reminder of your own, two hours from now (the phone asks with a date + time dialog)
void simReminder() {
  onNotif("REMIND", clock(), "ana.reminder", "Reminder", "SIM: Call the bank", "remind-" + millis(), "", parseFuture("in 2 hours", nowWhen()));
}

void simManual() {
  onNotif("MANUAL", clock(), "manual", "Test Merchant", "Amount: 10.00", "manual-" + millis(), "", "");
}

void dumpSelected() {
  println("EXPORT (desktop): the phone writes these as one .pngmesh + .pngmesh.sha256");
  for (int i = entries.size() - 1; i >= 0; i--) {
    Entry e = (Entry) entries.get(i);
    if (e.selected) println(e.src + "\t" + e.ymd + " " + e.time + "\t" + e.pkg + "\t" + e.title + "\t" + e.body + "\t" + e.nkey + "\t" + e.lag);
  }
}

void dumpEntries() {
  for (int i = entries.size() - 1; i >= 0; i--) {
    Entry e = (Entry) entries.get(i);
    println(e.src + "\t" + e.ymd + " " + e.time + "\t" + e.pkg + "\t" + e.title + "\t" + e.body + "\t" + e.nkey + "\t" + e.lag);
  }
}
