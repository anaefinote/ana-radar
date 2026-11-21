// One captured notification (or manual entry).
// Raw capture only, no parsing.

class Entry {
  String src, ymd, time, pkg, title, body, nkey, lag;
  String ev = "";              // the time the notification points to (from the app), "" if none
  String fut = "";             // the future time worked out from ev / the text / a reminder (Future.pde)
  int futAt = -1;
  boolean dup = false;
  boolean selected = false;
  int logLine = -1;          // line in ana_log.txt (Android), -1 on the desktop

  // when = "yyyy-mm-dd hh:mm:ss" (just "hh:mm:ss" from older callers: then it's today)
  Entry(String src, String when, String pkg, String title, String body, String key, String lag) {
    this.src = src;
    if (when.length() >= 19) {
      ymd = when.substring(0, 10);
      time = when.substring(11);
    }
    else {
      ymd = today();
      time = when;
    }
    this.pkg = pkg;
    this.title = title;
    this.body = body;
    this.nkey = key;
    this.lag = lag;
  }

  // What PICK APPS watches: the app's package for push notifications, the sender for SMS.
  // No wording is matched, so a change in how an app words its notifications doesn't matter.
  String watchKey() {
    if (isSms()) return "sms:" + title.toLowerCase().trim();
    return pkg;
  }

  // shown even when the filter is on
  boolean alwaysShown() {
    return src.equals("MANUAL") || src.equals("IMPORT") || src.equals("SYS") || src.equals("REMIND") || src.equals("IPHONE");   // the iPhone's: never hidden by PICKED
  }

  // SMS arrives as a notification from the phone's messaging app.
  // Everything else is an app push notification.
  boolean isSms() {
    return pkg.equals("com.google.android.apps.messaging")
        || pkg.equals("com.samsung.android.messaging")
        || pkg.equals("com.android.mms")
        || pkg.equals("com.android.messaging")
        || pkg.equals("sim.sms");
  }

  String channel() {
    if (src.equals("MANUAL") || src.equals("SYS")) return "";
    return isSms() ? "   SMS" : "   PUSH";
  }

  color tagColor() {
    if (src.equals("LIVE")) return #3DDC97;
    if (src.equals("SCAN")) return #4DA3FF;
    if (src.equals("MANUAL")) return #F5B942;
    if (src.equals("IMPORT")) return #B48CFF;
    return #7A8BA0;
  }

  String tagText() {
    if (!dup) return src;
    if (src.equals("LIVE")) return src + " DUP";
    return src + " SEEN";
  }

  String lagText() {
    if (src.equals("LIVE") && lag.length() > 0) return "   +" + lag + " ms";
    return "";
  }

  void drawCard(float x, float y, float w, float h) {
    noStroke();
    boolean picked = isWatched(watchKey());
    fill(picked ? #16324A : #18212D);
    rect(x, y, w, h);
    if (selected) {
      noFill();
      stroke(#F5B942);
      strokeWeight(3 * u);
      rect(x + 1.5 * u, y + 1.5 * u, w - 3 * u, h - 3 * u);
      noStroke();
      fill(#F5B942);
      rect(x + w - 30 * u, y + 10 * u, 18 * u, 18 * u);
      fill(#0E1621);
      textAlign(CENTER, CENTER);
      textSizeQ(13 * u);
      text("x", x + w - 21 * u, y + 18 * u);
    }
    fill(tagColor());
    rect(x, y, 6 * u, h);

    textAlign(LEFT, TOP);
    textSizeQ(13 * u);
    fill(tagColor());
    text(tagText() + channel(), x + 16 * u, y + 8 * u);
    fill(#8FA3B8);
    text((tab == T_ARCHIVE ? ymd.substring(5) + "  " : "") + time + lagText(), x + 170 * u, y + 8 * u);

    fill(#5F7388);
    textSizeQ(12 * u);
    text(pkg + (picked ? "   ·   PICKED" : ""), x + 16 * u, y + 28 * u, w - 60 * u, 18 * u);

    fill(#E8EEF5);
    textSizeQ(15 * u);
    text(title, x + 16 * u, y + 46 * u, w - 24 * u, 22 * u);

    fill(#B9C7D6);
    textSizeQ(13 * u);
    text(body, x + 16 * u, y + 70 * u, w - 24 * u, h - 74 * u);
  }
}
