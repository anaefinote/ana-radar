// Future.pde — what makes a notification "future" for EFINOTE's future ball. Three sources, each switched
// on or off in Settings > EFINOTE > Future:
//   Event times     the time an app gave its notification (calendars, reminders, bookings, deliveries)
//   Dates in text   "tomorrow at 3pm", "in 2 hours", "Friday", "Nov 20", "20 November 10:30" ...
//   My reminders    reminders made in ANA (Settings > EFINOTE > Add a reminder)
// A notification is future while that time is still ahead of now. Times are "yyyy-mm-dd hh:mm:ss".

boolean futEvent = true, futText = true, futRemind = true;
int futSig = 0;                  // changes when a switch changes, so cached answers are worked out again

String nowWhen() {
  return today() + " " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
}

// the time this notification points to ("" if none)
String futWhen(Entry e) {
  if (e.futAt == futSig) return e.fut;
  e.futAt = futSig;
  e.fut = "";
  String posted = e.ymd + " " + e.time;
  if (e.src.equals("REMIND")) {
    if (futRemind) e.fut = e.ev;
    return e.fut;
  }
  if (futEvent && e.ev.length() >= 19 && whenCmp(e.ev, posted) > 0) e.fut = e.ev;
  if (e.fut.length() == 0 && futText) e.fut = parseFuture(e.title + " " + e.body, posted);
  return e.fut;
}

boolean isFuture(Entry e) {
  String f = futWhen(e);
  return f.length() >= 19 && whenCmp(f, nowWhen()) > 0;
}

// ---------------------------------------------------------------- reading dates from text
String[] MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
String[] WEEKDAYS = { "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" };

// a time the text points to after `posted`, or ""
String parseFuture(String text, String posted) {
  String s = " " + text.toLowerCase() + " ";
  if (posted.length() < 19) return "";
  int base = dayNum(posted.substring(0, 10));
  int pSec = int(posted.substring(11, 13)) * 3600 + int(posted.substring(14, 16)) * 60 + int(posted.substring(17, 19));
  int dayOff = -999;            // days after the post date
  int sec = -1;                 // seconds into that day

  // "in 2 hours", "in 30 minutes", "in 3 days", "in 1 week"
  String[] m = match(s, "in (\\d+) (minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks)\\b");
  if (m != null) {
    int n = int(m[1]);
    String unit = m[2];
    int add = unit.startsWith("min") ? n * 60 : unit.startsWith("h") ? n * 3600 : unit.startsWith("d") ? n * 86400 : n * 604800;
    int t = pSec + add;
    int extra = floor(t / 86400.0);
    return ymdOf(base + extra) + " " + hms(t - extra * 86400);
  }
  if (match(s, "\\btomorrow\\b") != null) dayOff = 1;
  else if (match(s, "\\b(tonight|today|this evening|this afternoon)\\b") != null) dayOff = 0;
  else {
    for (int i = 0; i < 7 && dayOff < 0; i++) {
      if (match(s, "\\b" + WEEKDAYS[i] + "\\b") != null) {
        int d = (i - weekday(base) + 7) % 7;
        dayOff = d == 0 ? 7 : d;                         // "Friday" said on a Friday: next week's
      }
    }
  }
  // "Nov 20", "November 20th", "20 Nov", "20th of November"
  for (int i = 0; i < 12 && dayOff == -999; i++) {
    String[] a = match(s, "\\b" + MONTHS[i] + "[a-z]*\\.? (\\d{1,2})(st|nd|rd|th)?\\b");
    String[] b = match(s, "\\b(\\d{1,2})(st|nd|rd|th)? (of )?" + MONTHS[i] + "[a-z]*\\b");
    int dd = a != null ? int(a[1]) : b != null ? int(b[1]) : -1;
    if (dd >= 1 && dd <= 31) {
      int yy = int(posted.substring(0, 4));
      int z = dayNum(nf(yy, 4) + "-" + nf(i + 1, 2) + "-" + nf(dd, 2));
      if (z < base) z = dayNum(nf(yy + 1, 4) + "-" + nf(i + 1, 2) + "-" + nf(dd, 2));
      dayOff = z - base;
    }
  }
  // a time: "3pm", "3:30 pm", "15:00", "at 9"
  String[] t1 = match(s, "\\b(\\d{1,2})(:(\\d{2}))? ?(am|pm|a\\.m\\.|p\\.m\\.)");
  String[] t2 = match(s, "\\b([01]?\\d|2[0-3]):([0-5]\\d)\\b");
  String[] t3 = match(s, "\\bat (\\d{1,2})\\b");
  if (t1 != null) {
    int hh = int(t1[1]) % 12;
    if (t1[4].startsWith("p")) hh += 12;
    sec = hh * 3600 + (t1[3] != null && t1[3].length() > 0 ? int(t1[3]) * 60 : 0);
  }
  else if (t2 != null) sec = int(t2[1]) * 3600 + int(t2[2]) * 60;
  else if (t3 != null && dayOff != -999) {
    int hh = int(t3[1]);
    if (hh < 8) hh += 12;                                  // "at 3" usually means the afternoon
    sec = hh * 3600;
  }
  if (dayOff == -999 && sec < 0) return "";
  if (dayOff == -999) dayOff = 0;                           // a time on its own: today
  if (sec < 0) sec = 9 * 3600;                              // a day on its own: 9 in the morning
  String out = ymdOf(base + dayOff) + " " + hms(sec);
  return whenCmp(out, posted) > 0 ? out : "";
}

// compare two "yyyy-MM-dd HH:mm:ss" times: <0 a is earlier, 0 same, >0 later
// (no String.compareTo: Processing.js strings don't have it)
int whenCmp(String a, String b) {
  int da = dayNum(a.substring(0, 10)), db = dayNum(b.substring(0, 10));
  if (da != db) return da < db ? -1 : 1;
  int sa = int(a.substring(11, 13)) * 3600 + int(a.substring(14, 16)) * 60 + int(a.substring(17, 19));
  int sb = int(b.substring(11, 13)) * 3600 + int(b.substring(14, 16)) * 60 + int(b.substring(17, 19));
  return sa < sb ? -1 : sa > sb ? 1 : 0;
}

String hms(int t) {
  t = constrain(t, 0, 86399);
  int h = floor(t / 3600.0), mi = floor((t - h * 3600) / 60.0);
  return nf(h, 2) + ":" + nf(mi, 2) + ":" + nf(t - h * 3600 - mi * 60, 2);
}

// "in 2h", "in 3d" (for the future beads)
String inLabel(String when) {
  if (when.length() < 19) return "";
  int dd = dayNum(when.substring(0, 10)) - dayNum(today());
  int s = dd * 86400 + int(when.substring(11, 13)) * 3600 + int(when.substring(14, 16)) * 60
          - (hour() * 3600 + minute() * 60 + second());
  if (s < 3600) return "in " + max(1, floor(s / 60.0)) + "m";
  if (s < 86400) return "in " + floor(s / 3600.0) + "h";
  return "in " + floor(s / 86400.0) + "d";
}
