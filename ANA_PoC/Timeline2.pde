// Timeline2.pde — Timeline, the flat screen (concept image 2): a calendar card (month pill, two weeks,
// the chosen day in a pink capsule, a dot under days that have notifications), then that day's
// notifications on a coloured vertical line, hour by hour. Swipe the calendar sideways for other weeks;
// tap the month to come back to today; tap a notification to open its app.

float tlSwipe = 0;           // sideways drag on the calendar

// "2026-11-12" -> days since 1970-01-01 (civil calendar), and back
int dayNum(String ymd) {
  int yy = int(ymd.substring(0, 4)), mm = int(ymd.substring(5, 7)), dd = int(ymd.substring(8, 10));
  yy -= mm <= 2 ? 1 : 0;
  int era = floor(yy / 400.0);
  int yoe = yy - era * 400;
  int doy = floor((153 * (mm + (mm > 2 ? -3 : 9)) + 2) / 5.0) + dd - 1;
  int doe = yoe * 365 + floor(yoe / 4.0) - floor(yoe / 100.0) + doy;
  return era * 146097 + doe - 719468;
}

String ymdOf(int z) {
  z += 719468;
  int era = floor(z / 146097.0);
  int doe = z - era * 146097;
  int yoe = floor((doe - floor(doe / 1460.0) + floor(doe / 36524.0) - floor(doe / 146096.0)) / 365.0);
  int yy = yoe + era * 400;
  int doy = doe - (365 * yoe + floor(yoe / 4.0) - floor(yoe / 100.0));
  int mp = floor((5 * doy + 2) / 153.0);
  int dd = doy - floor((153 * mp + 2) / 5.0) + 1;
  int mm = mp + (mp < 10 ? 3 : -9);
  if (mm <= 2) yy++;
  return nf(yy, 4) + "-" + nf(mm, 2) + "-" + nf(dd, 2);
}

int weekday(int z) {             // 0 = Sunday
  return ((z + 4) % 7 + 7) % 7;
}

void drawTimeline2() {
  image(flatBgImg, 0, 0);
  int sel = dayNum(tlDay);

  // title + PICKED / ALL
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(54 * fk);
  boldTextF("Timeline", FX(58), FY(150));
  fill(#9AA6C0);
  textSizeQ(26 * fk);
  text("Your notifications, hour by hour", FX(60), FY(190));
  String fl = filterOn ? "PICKED" : "ALL";
  textSizeQ(20 * fk);
  float fw = textWidth(fl) + 70 * fk;
  float fx = FX(800) - fw, fy = FY(106);
  fill(14, 20, 38, 240);
  rrect(fx, fy, fw, 52 * fk, 26 * fk);
  stroke(60, 90, 150, 140);
  strokeWeight(1.4 * fk);
  rrectLine(fx, fy, fw, 52 * fk, 26 * fk);
  noStroke();
  // sliders icon
  stroke(#9AA6C0);
  strokeWeight(2.4 * fk);
  float sx = fx + 26 * fk, sy = fy + 26 * fk;
  line(sx - 10 * fk, sy - 6 * fk, sx + 10 * fk, sy - 6 * fk);
  line(sx - 10 * fk, sy + 6 * fk, sx + 10 * fk, sy + 6 * fk);
  noStroke();
  fill(#9AA6C0);
  ellipse(sx + 4 * fk, sy - 6 * fk, 8 * fk, 8 * fk);
  ellipse(sx - 4 * fk, sy + 6 * fk, 8 * fk, 8 * fk);
  fill(#E8EEF5);
  textAlign(LEFT, CENTER);
  text(fl, fx + 46 * fk, fy + 25 * fk);

  // calendar card
  float cx0 = FX(40), cy0 = FY(222), cw = 772 * fk, ch = 330 * fk;
  noStroke();
  fill(20, 24, 40, 245);
  rrect(cx0, cy0, cw, ch, 40 * fk);
  fill(#8A93C6);
  textAlign(LEFT, BASELINE);
  textSizeQ(26 * fk);
  text("Notification date", FX(80), FY(290));
  String mon = monthName(int(tlDay.substring(5, 7)));
  textSizeQ(28 * fk);
  float mw = textWidth(mon) + 84 * fk;
  float mx0 = FX(772) - mw, my0 = FY(254);
  stroke(70, 130, 255, 200);
  strokeWeight(1.8 * fk);
  rrectLine(mx0, my0, mw, 56 * fk, 28 * fk);
  noStroke();
  fill(#5EA2FF);
  textAlign(LEFT, CENTER);
  text(mon, mx0 + 22 * fk, my0 + 26 * fk);
  chevronDown(mx0 + mw - 30 * fk, my0 + 28 * fk, 16 * fk, #5EA2FF);

  // which days have notifications
  String days = "|";
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (passes(e) && days.indexOf("|" + e.ymd + "|") < 0) days += e.ymd + "|";
  }
  int start = sel - weekday(sel);                // Sunday of the chosen week = row 1
  String[] dn = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
  float off = constrain(tlSwipe, -200 * fk, 200 * fk);
  int todayN = dayNum(today());
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 7; c++) {
      int z = start + r * 7 + c;
      float x = FX(118 + c * 103) + off;
      float yN = FY(r == 0 ? 410 : 488);
      boolean isSel = (z == sel);
      if (isSel) {
        for (int i = 4; i >= 1; i--) {
          fill(255, 80, 180, 18);
          rrect(x - 38 * fk - i * 4 * fk, FY(330) - i * 4 * fk + (r == 1 ? 120 * fk : 0), 76 * fk + i * 8 * fk, (r == 0 ? 136 : 62) * fk + i * 8 * fk, 38 * fk + i * 4 * fk);
        }
        fill(#FF4FAE);
        if (r == 0) rrect(x - 38 * fk, FY(330), 76 * fk, 136 * fk, 38 * fk);
        else rrect(x - 38 * fk, FY(450), 76 * fk, 62 * fk, 31 * fk);
      }
      if (r == 0) {
        fill(isSel ? #FFFFFF : #8B7CF6);
        textAlign(CENTER, BASELINE);
        textSizeQ(23 * fk);
        text(dn[c], x, FY(362));
      }
      String ymd = ymdOf(z);
      fill(isSel ? #FFFFFF : z > todayN ? #4A5070 : #B7BDDA);
      textAlign(CENTER, BASELINE);
      textSizeQ(30 * fk);
      text("" + int(ymd.substring(8, 10)), x, yN + 12 * fk);
      if (days.indexOf("|" + ymd + "|") >= 0) {
        fill(isSel ? #FFFFFF : #4DA3FF);
        ellipse(x, yN + 28 * fk, 7 * fk, 7 * fk);
      }
    }
  }

  // the day's notifications, oldest first, on a vertical line
  ArrayList list = dayList();
  float top = FY(600), bottom = barY - 10 * u, ih = 190 * fk;
  float maxS = max(0, list.size() * ih + 60 * fk - (bottom - top));
  tabScroll[tab] = constrain(tabScroll[tab], 0, maxS);
  float scroll = tabScroll[tab];
  if (list.size() == 0) {
    fill(#7A8BA0);
    textAlign(CENTER, TOP);
    textSizeQ(24 * fk);
    text(tlDay.equals(today()) ? "Nothing yet today" : "Nothing on " + longDate(tlDay), FX(426), top + 40 * fk);
  }
  for (int i = 0; i < list.size(); i++) {
    float y = top + i * ih - scroll;
    if (y > bottom || y + ih < top) continue;
    Entry e = (Entry) list.get(i);
    AppIcon a = appFor(e.pkg);
    appInfo(a);
    color c = appHue(e.pkg);
    if (y < top - 10 * fk) continue;                         // whole items only (no clip in 1.5.1)
    if (y + ih * 0.8 > bottom) continue;
    fill(#8A93C6);
    textAlign(LEFT, BASELINE);
    textSizeQ(23 * fk);
    boldTextF(ampm(e.time), FX(66), y + 30 * fk);
    if (i < list.size() - 1) {
      stroke(c);
      strokeWeight(3 * fk);
      line(FX(245), y + 46 * fk, FX(245), y + ih - 6 * fk);
      noStroke();
    }
    noFill();
    stroke(c);
    strokeWeight(2.4 * fk);
    ellipse(FX(245), y + 22 * fk, 44 * fk, 44 * fk);
    noStroke();
    fill(c);
    ellipse(FX(245), y + 22 * fk, 20 * fk, 20 * fk);
    String name = e.src.equals("MANUAL") ? "Manual entry" : a.label;
    textSizeQ(30 * fk);
    boolean ip = e.src.equals("IPHONE");
    boldTextF(fitText(name, ip ? 340 * fk : 470 * fk), FX(330), y + 34 * fk);
    if (ip) iphoneTag(FX(330) + min(textWidthAt(name, 30 * fk), 340 * fk) + 14 * fk, y + 23 * fk, 32 * fk);
    float lx = FX(340);
    drawAppIconAt(a, lx - 12 * fk, y + 58 * fk, 26 * fk);
    textAlign(LEFT, BASELINE);                 // the icon's letter (no icon) leaves the text centred
    fill(#9AA6C8);
    textSizeQ(22 * fk);
    String body = e.title.length() > 0 && !e.title.equals(name) ? e.title + ": " + e.body : e.body;
    text(fitText(body, 400 * fk), lx + 34 * fk, y + 80 * fk);
    icoCal(lx + 1 * fk, y + 112 * fk, 11 * fk, #8A93C6);
    text(longDate(e.ymd), lx + 34 * fk, y + 120 * fk);
    icoClock(lx + 1 * fk, y + 150 * fk, 11 * fk, #8A93C6);
    text(e.time + (e.src.equals("LIVE") ? "" : "  ·  " + e.src.toLowerCase()), lx + 34 * fk, y + 158 * fk);
  }
  // now, on today: a dot and a line after the last item; the band below is still to come
  if (tlDay.equals(today()) && list.size() > 0) {
    float y = top + list.size() * ih - scroll + 10 * fk;
    if (y < bottom - 20 * fk) {
      fill(110, 70, 200, 60);
      rect(FX(40), y, 772 * fk, bottom - y);
      stroke(140, 110, 255, 200);
      strokeWeight(1.6 * fk);
      line(FX(40), y, FX(812), y);
      noStroke();
      fill(#8B6CFF);
      ellipse(FX(40), y, 30 * fk, 30 * fk);
      fill(#C9C2FF);
      textAlign(LEFT, BASELINE);
      textSizeQ(20 * fk);
      text("Now  ·  " + ampm(nf(hour(), 2) + ":" + nf(minute(), 2)), FX(80), y + 34 * fk);
    }
  }
}

// taps on Timeline (a sideways swipe on the calendar is handled on release)
void timelineTap(float mx, float my) {
  String fl = filterOn ? "PICKED" : "ALL";
  textSizeQ(20 * fk);
  float fw = textWidth(fl) + 70 * fk;
  if (my > FY(96) && my < FY(168) && mx > FX(800) - fw) {
    filterOn = !filterOn;
    tabScroll[tab] = 0;
    return;
  }
  if (my > FY(244) && my < FY(320) && mx > FX(560)) {         // month pill: back to today
    tlDay = today();
    tabScroll[tab] = 0;
    return;
  }
  if (my > FY(320) && my < FY(520)) {                         // a day
    int c = constrain(floor((mx - FX(118 - 51.5)) / (103 * fk)), 0, 6);
    int r = my < FY(436) ? 0 : 1;
    int sel = dayNum(tlDay);
    int z = sel - weekday(sel) + r * 7 + c;
    tlDay = ymdOf(z);
    tabScroll[tab] = 0;
    return;
  }
  // a notification: open its app
  float top = FY(600), ih = 190 * fk;
  if (my > top) {
    int i = floor((my - top + tabScroll[tab]) / ih);
    ArrayList list = dayList();
    if (i >= 0 && i < list.size()) openReader((Entry) list.get(i));   // read it in full (Reader.pde)
  }
}

// The Timeline's day, oldest first by the time each notification was posted. Entries arrive in the
// order they reach the phone, and a relayed backlog (an iPhone app linking to Android ANA) arrives out
// of order, so the day is sorted by time, not by arrival. Drawing and tapping both use this list.
ArrayList dayList() {
  ArrayList list = new ArrayList();
  for (int i = entries.size() - 1; i >= 0; i--) {
    Entry e = (Entry) entries.get(i);
    if (!(e.ymd.equals(tlDay) && passes(e) && !e.src.equals("SYS"))) continue;
    String k = e.ymd + " " + e.time;
    int at = list.size();
    while (at > 0) {
      Entry p = (Entry) list.get(at - 1);
      String pk = p.ymd + " " + p.time;
      if (k.length() < 19 || pk.length() < 19 || whenCmp(pk, k) <= 0) break;   // no full time: keep arrival order
      at--;
    }
    list.add(at, e);
  }
  return list;
}

boolean onCalendar(float mx, float my) {
  return my > FY(222) && my < FY(552);
}

// a sideways swipe on the calendar: a week back or forward
void timelineSwipe(float dx) {
  if (abs(dx) < 60 * fk) return;
  tlDay = ymdOf(dayNum(tlDay) + (dx > 0 ? -7 : 7));
  tabScroll[tab] = 0;
}
