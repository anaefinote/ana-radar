// Gst.pde — GST, Group Spend Technology (Phase 1), the fourth pill in Settings: ANA | EFINOTE | WATCH | GST.
// Everything is opt-in, and GST never holds money: it only keeps track of what people choose to say.
//   Personal pools   split what you watch into pools (car, mortgage, gas) and top them up in rotation
//   Groups           a group's combined balance, from what each member chooses to share (a number, never an address)
//   Spend alerts     "I'm about to spend 50 BBD on gas", to the whole group
//   Turns and buys   whose turn it is (sou-sou / meeting-turn), and group buys with pledges
// Packs travel as a sealed .pngmesh + .sha256 (class 21), sent however you like (WhatsApp, email...) and opened
// with ANA (IMPORT). Bluetooth, Wi-Fi and a small server come later, also opt-in.
// The same file runs in ANA LITE, ANA ORBIT and ANA : STATIA. State is saved with js.setPref("gst", ...).

final color GGREEN = #3DDC97;
final int R_GPOOLS = 40, R_GGROUPS = 41, R_GALERTS = 42, R_GTURNS = 43, R_GNAME = 44, R_GPADD = 45, R_GPNEXT = 46,
          R_GNEW = 47, R_GIMPORT = 48, R_GBACK = 49, R_GINVITE = 50, R_GSHARE = 51, R_GALERT = 52, R_GTURN = 53,
          R_GBUYNEW = 54, R_GLEAVE = 55, R_GPOOL = 3000, R_GGROUP = 4000, R_GBUY = 5000;

boolean gLoaded = false;
boolean gfPools, gfGroups, gfAlerts, gfTurns;     // the four opt-ins (all off until turned on)
String gMyId = "", gMyName = "Me";
ArrayList gPools = new ArrayList();
int gNext = 0;                                     // the pool next in the top-up rotation
ArrayList gGroups = new ArrayList();
ArrayList gFeed = new ArrayList();                 // String[] { group id, when, text }, newest last
HashMap gSeen = new HashMap();                     // pack ids already taken in
ArrayList gSeenOrder = new ArrayList();
String gOpen = "";                                 // the group open on screen ("" = the GST page)
int gSeq = 0;
float gAll = 0, gFront = 0;                        // watched totals (every wallet / the front face)
int gTotalsAt = -100000, gInboxAt = -100000;
String gAskId = "", gAskKind = "", gAskCtx = "";
int gAskN = 0;

class GPool {
  String id, name;
  float target, have;
  GPool(String id, String name, float target, float have) { this.id = id; this.name = name; this.target = target; this.have = have; }
}

class GMember {
  String id, name, when, key = "";      // key: the member's phone signing key (FLEX), first one seen is kept
  float amt;
  boolean shared;
  GMember(String id, String name) { this.id = id; this.name = name; this.when = ""; }
}

class GBuy {
  String id, title;
  float target;
  ArrayList pledges = new ArrayList();             // GMember: who pledged how much
  GBuy(String id, String title, float target) { this.id = id; this.title = title; this.target = target; }
}

class GGroup {
  String id, name, owner;
  ArrayList members = new ArrayList();
  ArrayList buys = new ArrayList();
  String[] order = new String[0];                  // turn order (member ids)
  int turn = 0;
  ArrayList ledger = new ArrayList();              // FLEX: the group's signed, hash-chained ledger (Flex.pde)
  HashMap acks = new HashMap();                    // member id -> "n|h": the ledger they hold
  String conflict = "";
  GGroup(String id, String name, String owner) { this.id = id; this.name = name; this.owner = owner; }
}

// ---------------------------------------------------------------- small helpers
String gClean(String s) {
  if (s == null) return "";
  return trim(join(split(join(split(s, "\t"), " "), "\n"), " "));
}

float gNum(String s, float d) {
  if (s == null) return d;
  s = trim(s);
  if (s.length() == 0) return d;
  float v = float(s);
  if (v != v) return d;                           // NaN
  return v;
}

String gMoney(float v) {
  int c = round(abs(v) * 100);
  int whole = floor(c / 100.0);
  return (v < 0 ? "-$" : "$") + (whole == 0 ? "0" : nfc(whole)) + "." + nf(c - whole * 100, 2);
}

String gNow() {
  return year() + "-" + nf(month(), 2) + "-" + nf(day(), 2) + " " + nf(hour(), 2) + ":" + nf(minute(), 2);
}

String gShortWhen(String w) {
  return w.length() > 5 ? w.substring(5) : w;
}

String gNewId(String p) {
  gSeq++;
  return p + gMyId + "-" + gSeq + "-" + int(random(100000));
}

GGroup gFind(String gid) {
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    if (g.id.equals(gid)) return g;
  }
  return null;
}

GMember gMember(ArrayList list, String id, String name) {
  for (int i = 0; i < list.size(); i++) {
    GMember m = (GMember) list.get(i);
    if (m.id.equals(id)) { if (name != null && name.length() > 0) m.name = name; return m; }
  }
  GMember m = new GMember(id, name == null || name.length() == 0 ? "Member" : name);
  list.add(m);
  return m;
}

String gNameOf(GGroup g, String id) {
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    if (m.id.equals(id)) return m.name;
  }
  return "someone";
}

float gCombined(GGroup g) {
  float t = 0;
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    if (m.shared) t += m.amt;
  }
  return t;
}

float gPledged(GBuy b) {
  float t = 0;
  for (int i = 0; i < b.pledges.size(); i++) {
    GMember m = (GMember) b.pledges.get(i);
    t += m.amt;
  }
  return t;
}

float gInPools() {
  float t = 0;
  for (int i = 0; i < gPools.size(); i++) {
    GPool p = (GPool) gPools.get(i);
    t += p.have;
  }
  return t;
}

void gFeedAdd(String gid, String when, String text) {
  gFeed.add(new String[] { gid, when, text });
  while (gFeed.size() > 80) gFeed.remove(0);
}

// ---------------------------------------------------------------- saving (one line per thing, tab-separated)
void gstLoad() {
  if (gLoaded) return;
  gLoaded = true;
  String s = js != null ? js.pref("gst") : "";
  if (s == null) s = "";
  String[] lines = split(s, "\n");
  for (int i = 0; i < lines.length; i++) {
    String[] f = split(lines[i], "\t");
    if (f.length < 2) continue;
    String k = f[0];
    if (k.equals("C")) {
      gfPools = f[1].equals("1"); gfGroups = f.length > 2 && f[2].equals("1");
      gfAlerts = f.length > 3 && f[3].equals("1"); gfTurns = f.length > 4 && f[4].equals("1");
    } else if (k.equals("M") && f.length > 2) { gMyId = f[1]; gMyName = f[2]; }
    else if (k.equals("N")) { gNext = int(gNum(f[1], 0)); gSeq = f.length > 2 ? int(gNum(f[2], 0)) : 0; }
    else if (k.equals("P") && f.length > 4) gPools.add(new GPool(f[1], f[2], gNum(f[3], 0), gNum(f[4], 0)));
    else if (k.equals("G") && f.length > 3) {
      GGroup g = new GGroup(f[1], f[2], f[3]);
      if (f.length > 5 && f[4].length() > 0) { g.order = split(f[4], ","); g.turn = int(gNum(f[5], 0)); }
      gGroups.add(g);
    } else if (k.equals("U") && f.length > 6) {
      GGroup g = gFind(f[1]);
      if (g == null) continue;
      GMember m = gMember(g.members, f[2], f[3]);
      m.amt = gNum(f[4], 0); m.when = f[5]; m.shared = f[6].equals("1");
      if (f.length > 7) m.key = f[7];
    } else if (k.equals("B") && f.length > 4) {
      GGroup g = gFind(f[1]);
      if (g != null) g.buys.add(new GBuy(f[2], f[3], gNum(f[4], 0)));
    } else if (k.equals("Q") && f.length > 5) {
      GGroup g = gFind(f[1]);
      if (g == null) continue;
      for (int b = 0; b < g.buys.size(); b++) {
        GBuy by = (GBuy) g.buys.get(b);
        if (by.id.equals(f[2])) gMember(by.pledges, f[3], f[4]).amt = gNum(f[5], 0);
      }
    } else if (k.equals("L") && f.length > 10) {
      GGroup g = gFind(f[1]);
      if (g != null) g.ledger.add(new LEntry(int(gNum(f[2], 0)), f[3], f[4], f[5], int(gNum(f[6], 0)), f[7], f[8], f[9], f[10]));
    } else if (k.equals("A") && f.length > 3) {
      GGroup g = gFind(f[1]);
      if (g != null) g.acks.put(f[2], f[3]);
    } else if (k.equals("X") && f.length > 2) {
      GGroup g = gFind(f[1]);
      if (g != null) g.conflict = f[2];
    } else if (k.equals("F") && f.length > 3) gFeed.add(new String[] { f[1], f[2], f[3] });
    else if (k.equals("S")) { gSeen.put(f[1], "1"); gSeenOrder.add(f[1]); }
  }
  if (gMyId.length() == 0) gMyId = "m" + hex(int(random(2147483647)));
}

void gstSave() {
  String sb = "";
  sb += ("C\t" + (gfPools ? "1" : "0") + "\t" + (gfGroups ? "1" : "0") + "\t" + (gfAlerts ? "1" : "0") + "\t" + (gfTurns ? "1" : "0") + "\n");
  sb += ("M\t" + gMyId + "\t" + gClean(gMyName) + "\n");
  sb += ("N\t" + gNext + "\t" + gSeq + "\n");
  for (int i = 0; i < gPools.size(); i++) {
    GPool p = (GPool) gPools.get(i);
    sb += ("P\t" + p.id + "\t" + gClean(p.name) + "\t" + p.target + "\t" + p.have + "\n");
  }
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    sb += ("G\t" + g.id + "\t" + gClean(g.name) + "\t" + g.owner + "\t" + join(g.order, ",") + "\t" + g.turn + "\n");
    for (int k = 0; k < g.members.size(); k++) {
      GMember m = (GMember) g.members.get(k);
      sb += ("U\t" + g.id + "\t" + m.id + "\t" + gClean(m.name) + "\t" + m.amt + "\t" + m.when + "\t" + (m.shared ? "1" : "0") + "\t" + m.key + "\n");
    }
    for (int k = 0; k < g.ledger.size(); k++) {
      LEntry e = (LEntry) g.ledger.get(k);
      sb += "L\t" + g.id + "\t" + e.i + "\t" + e.from + "\t" + e.to + "\t" + e.kind + "\t" + e.amt + "\t" + e.when + "\t" + e.prev + "\t" + e.h + "\t" + e.sig + "\n";
    }
    for (int k = 0; k < g.members.size(); k++) {
      GMember m = (GMember) g.members.get(k);
      String a = (String) g.acks.get(m.id);
      if (a != null) sb += "A\t" + g.id + "\t" + m.id + "\t" + a + "\n";
    }
    if (g.conflict.length() > 0) sb += "X\t" + g.id + "\t" + gClean(g.conflict) + "\n";
    for (int b = 0; b < g.buys.size(); b++) {
      GBuy by = (GBuy) g.buys.get(b);
      sb += ("B\t" + g.id + "\t" + by.id + "\t" + gClean(by.title) + "\t" + by.target + "\n");
      for (int q = 0; q < by.pledges.size(); q++) {
        GMember m = (GMember) by.pledges.get(q);
        sb += ("Q\t" + g.id + "\t" + by.id + "\t" + m.id + "\t" + gClean(m.name) + "\t" + m.amt + "\n");
      }
    }
  }
  for (int i = 0; i < gFeed.size(); i++) {
    String[] f = (String[]) gFeed.get(i);
    sb += ("F\t" + f[0] + "\t" + f[1] + "\t" + gClean(f[2]) + "\n");
  }
  int from = max(0, gSeenOrder.size() - 400);
  for (int i = from; i < gSeenOrder.size(); i++) sb += ("S\t" + gSeenOrder.get(i) + "\n");
  if (js != null) js.setPref("gst", sb);
}

// ---------------------------------------------------------------- packs (rows: id kind group from fromName when a b c d)
String gRow(String kind, String gid, String a, String b, String c, String d) {
  return gNewId("p") + "\t" + kind + "\t" + gid + "\t" + gMyId + "\t" + gClean(gMyName) + "\t" + gNow()
       + "\t" + gClean(a) + "\t" + gClean(b) + "\t" + gClean(c) + "\t" + gClean(d);
}

// takes in a pack (received or our own); returns false if it was already in, or for an unknown group
boolean gApply(String[] f) {
  if (f.length < 10) return false;
  String id = f[0], kind = f[1], gid = f[2], from = f[3], who = f[4], when = f[5];
  boolean again = kind.equals("LEDGER") || kind.equals("ACK");   // checked every time: a refused copy can't block the real one
  if (!again && gSeen.containsKey(id)) return false;
  if (!again) { gSeen.put(id, "1"); gSeenOrder.add(id); }
  boolean mine = from.equals(gMyId);
  GGroup g = gFind(gid);
  if (kind.equals("INVITE")) {
    boolean fresh = g == null;
    if (fresh) { g = new GGroup(gid, f[6], from); gGroups.add(g); }
    String[] ms = split(f[7], ";");                 // id:name:amount:shared:key
    for (int i = 0; i < ms.length; i++) {
      String[] p = split(ms[i], ":");
      if (p.length < 4 || p[0].equals(gMyId)) continue;
      GMember m = gMember(g.members, p[0], p[1]);
      if (p[3].equals("1")) { m.amt = gNum(p[2], 0); m.shared = true; m.when = when; }
      if (p.length > 4) pinKey(g, p[0], p[1], p[4], when);
    }
    gMember(g.members, gMyId, gMyName).key = flexMyKey();
    if (f[8].length() > 0 && g.order.length == 0) { g.order = split(f[8], ","); g.turn = int(gNum(f[9], 0)); }
    if (fresh && !mine) {
      gFeedAdd(gid, when, "You joined " + g.name + ", invited by " + who);
      appMsg = "GST: you joined " + g.name;
      appMsgAt = millis();
    }
    return true;
  }
  if (g == null) return false;
  if (flexApply(g, f, mine)) return true;          // FLEX: LEDGER, ACK, PROOF (Flex.pde)
  if (kind.equals("SHARE")) {
    GMember m = gMember(g.members, from, who);
    m.amt = gNum(f[6], 0); m.shared = true; m.when = when;
    pinKey(g, from, who, f[9], when);
    gFeedAdd(gid, when, (mine ? "You" : who) + " shared " + gMoney(m.amt));
  } else if (kind.equals("ALERT")) {
    gMember(g.members, from, who);
    gFeedAdd(gid, when, (mine ? "You are" : who + " is") + " about to spend " + f[6] + " " + f[7] + (f[8].length() > 0 ? " on " + f[8] : ""));
  } else if (kind.equals("TURN")) {
    gMember(g.members, from, who);
    if (f[7].length() > 0) g.order = split(f[7], ",");
    g.turn = int(gNum(f[6], 0));
    if (g.order.length > 0) gFeedAdd(gid, when, "Turn: " + gNameOf(g, g.order[g.turn % g.order.length]) + (mine ? "" : " (set by " + who + ")"));
  } else if (kind.equals("BUY")) {
    gMember(g.members, from, who);
    boolean have = false;
    for (int i = 0; i < g.buys.size(); i++) {
      GBuy by = (GBuy) g.buys.get(i);
      if (by.id.equals(f[6])) have = true;
    }
    if (!have) g.buys.add(new GBuy(f[6], f[7], gNum(f[8], 0)));
    gFeedAdd(gid, when, (mine ? "You" : who) + " started a group buy: " + f[7] + ", " + gMoney(gNum(f[8], 0)));
  } else if (kind.equals("PLEDGE")) {
    gMember(g.members, from, who);
    for (int i = 0; i < g.buys.size(); i++) {
      GBuy b = (GBuy) g.buys.get(i);
      if (b.id.equals(f[6])) {
        gMember(b.pledges, from, who).amt = gNum(f[7], 0);
        gFeedAdd(gid, when, (mine ? "You" : who) + " pledged " + gMoney(gNum(f[7], 0)) + " to " + b.title);
      }
    }
  }
  return true;
}

// our own packs: take them in here, then share them as a .pngmesh + .sha256
void gSend(GGroup g, String head, String[] rows0, String[] pics) {
  String[] extra = flexRows(g);                   // FLEX: the whole ledger and our signed ack ride along
  String[] rows = new String[rows0.length + extra.length];
  for (int i = 0; i < rows0.length; i++) rows[i] = rows0[i];
  for (int i = 0; i < extra.length; i++) rows[rows0.length + i] = extra[i];
  for (int i = 0; i < rows.length; i++) gApply(split(rows[i], "\t"));
  gstSave();
  if (js != null) js.gstSend(g.name, head, join(rows, "\n"), join(pics, "\n"));
}

void gstPollInbox() {
  if (js == null || millis() - gInboxAt < 700) return;
  gInboxAt = millis();
  String s = js.gstInbox();
  if (s == null || s.length() == 0) return;
  String[] lines = split(s, "\n");
  int got = 0, unknown = 0;
  for (int i = 0; i < lines.length; i++) {
    String[] f = split(lines[i], "\t");
    if (f.length < 10) continue;
    if (gApply(f)) got++;
    else if (gFind(f[2]) == null && !f[1].equals("INVITE")) unknown++;
  }
  if (unknown > 0) { appMsg = "GST: " + unknown + " update" + (unknown == 1 ? " is" : "s are") + " for a group you haven't joined"; appMsgAt = millis(); }
  if (got > 0 || unknown > 0) gstSave();
}

// ---------------------------------------------------------------- dialogs (native; answers come back by polling)
void gAsk(String kind, String ctx, String title, String msg, String spec) {
  if (js == null) return;
  gAskN++;
  gAskId = "g" + gAskN;
  gAskKind = kind;
  gAskCtx = ctx;
  js.gstAsk(gAskId, title, msg, spec);
}

void gPick(String kind, String ctx, String title, String items) {
  if (js == null) return;
  gAskN++;
  gAskId = "g" + gAskN;
  gAskKind = kind;
  gAskCtx = ctx;
  js.gstPick(gAskId, title, items);
}

void gstPollAnswer() {
  if (js == null || gAskId.length() == 0) return;
  String a = js.gstAnswer(gAskId);
  if (a == null || a.length() == 0) return;
  String kind = gAskKind, ctx = gAskCtx;
  gAskId = "";
  if (!a.startsWith("O")) return;
  String[] v = split(a, "\t");
  gAnswered(kind, ctx, v);
}

GPool gPool(String pid) {
  for (int i = 0; i < gPools.size(); i++) {
    GPool p = (GPool) gPools.get(i);
    if (p.id.equals(pid)) return p;
  }
  return null;
}

void gAnswered(String kind, String ctx, String[] v) {
  if (flexAnswered(kind, ctx, v)) { gstSave(); return; }   // FLEX dialogs (Flex.pde)
  String v1 = v.length > 1 ? v[1] : "", v2 = v.length > 2 ? v[2] : "", v3 = v.length > 3 ? v[3] : "";
  if (kind.equals("name")) { if (trim(v1).length() > 0) gMyName = trim(v1); }
  else if (kind.equals("padd")) {
    if (trim(v1).length() == 0) return;
    gPools.add(new GPool(gNewId("pool"), trim(v1), max(0, gNum(v2, 0)), 0));
  } else if (kind.equals("pnext")) {
    if (gPools.size() == 0) return;
    GPool p = (GPool) gPools.get(gNext % gPools.size());
    p.have += max(0, gNum(v1, 0));
    gNext = (gNext + 1) % gPools.size();
    appMsg = "Topped up " + p.name + ". Next: " + ((GPool) gPools.get(gNext)).name;
    appMsgAt = millis();
  } else if (kind.equals("pool")) {
    GPool p = gPool(ctx);
    if (p == null) return;
    int c = int(gNum(v1, -1));
    if (c == 0) gAsk("ptop", ctx, "Top up " + p.name, "", "Amount (USD)||number");
    else if (c == 1) gAsk("ptake", ctx, "Take out of " + p.name, "", "Amount (USD)||number");
    else if (c == 2) gAsk("ptarget", ctx, "Target for " + p.name, "", "Target (USD)|" + nf(p.target, 0, 2) + "|number");
    else if (c == 3) gAsk("pname", ctx, "Rename " + p.name, "", "Name|" + p.name + "|text");
    else if (c == 4) { gPools.remove(gPools.indexOf(p)); if (gPools.size() > 0) gNext = gNext % gPools.size(); else gNext = 0; }
  } else if (kind.equals("ptop")) { GPool p = gPool(ctx); if (p != null) p.have += max(0, gNum(v1, 0)); }
  else if (kind.equals("ptake")) { GPool p = gPool(ctx); if (p != null) p.have = max(0, p.have - max(0, gNum(v1, 0))); }
  else if (kind.equals("ptarget")) { GPool p = gPool(ctx); if (p != null) p.target = max(0, gNum(v1, p.target)); }
  else if (kind.equals("pname")) { GPool p = gPool(ctx); if (p != null && trim(v1).length() > 0) p.name = trim(v1); }
  else if (kind.equals("gnew")) {
    if (trim(v1).length() == 0) return;
    if (trim(v2).length() > 0) gMyName = trim(v2);
    GGroup g = new GGroup(gNewId("g"), trim(v1), gMyId);
    gMember(g.members, gMyId, gMyName).key = flexMyKey();
    gGroups.add(g);
    gFeedAdd(g.id, gNow(), "You started " + g.name + ". Send the invite to bring people in.");
    gOpen = g.id;
    tabScroll[tab] = 0;
  } else if (kind.equals("gshare")) {
    GGroup g = gFind(ctx);
    if (g == null) return;
    float amt = max(0, gNum(v1, 0));
    gSend(g, "Balance shared in " + g.name, new String[] { gRow("SHARE", g.id, "" + amt, "", "", flexMyKey()) },
          new String[] { gMyName + " shared a balance\t" + gMoney(amt) + " with " + g.name });
    return;
  } else if (kind.equals("galert")) {
    GGroup g = gFind(ctx);
    if (g == null) return;
    String amt = trim(v1), cur = trim(v2).length() > 0 ? trim(v2).toUpperCase() : "USD", what = trim(v3);
    if (amt.length() == 0) return;
    gSend(g, "Spend alert in " + g.name, new String[] { gRow("ALERT", g.id, amt, cur, what, "") },
          new String[] { "Spend alert from " + gMyName + "\tAbout to spend " + amt + " " + cur + (what.length() > 0 ? " on " + what : "") });
    return;
  } else if (kind.equals("gturn")) {
    GGroup g = gFind(ctx);
    if (g == null) return;
    int c = int(gNum(v1, -1));
    String[] order = g.order;
    int t = g.turn;
    if (c == 1 || order.length == 0) {                  // the order: members as listed, starting from the first
      order = new String[g.members.size()];
      for (int i = 0; i < order.length; i++) { GMember om = (GMember) g.members.get(i); order[i] = om.id; }
      t = 0;
    } else if (c == 0) t = (g.turn + 1) % order.length;
    else return;
    if (order.length == 0) return;
    gSend(g, "Turn in " + g.name, new String[] { gRow("TURN", g.id, "" + t, join(order, ","), "", "") },
          new String[] { "Turn in " + g.name + "\tIt's " + gNameOf(g, order[t]) + "'s turn" });
    return;
  } else if (kind.equals("gbuy")) {
    GGroup g = gFind(ctx);
    if (g == null || trim(v1).length() == 0) return;
    float target = max(0, gNum(v2, 0));
    gSend(g, "Group buy in " + g.name, new String[] { gRow("BUY", g.id, gNewId("b"), trim(v1), "" + target, "") },
          new String[] { "Group buy: " + trim(v1) + "\tTarget " + gMoney(target) + " in " + g.name });
    return;
  } else if (kind.equals("gpledge")) {
    String[] c = split(ctx, "|");
    GGroup g = gFind(c[0]);
    if (g == null || c.length < 2) return;
    float amt = max(0, gNum(v1, 0));
    String title = "";
    for (int i = 0; i < g.buys.size(); i++) {
      GBuy by = (GBuy) g.buys.get(i);
      if (by.id.equals(c[1])) title = by.title;
    }
    gSend(g, "Pledge in " + g.name, new String[] { gRow("PLEDGE", g.id, c[1], "" + amt, "", "") },
          new String[] { gMyName + " pledged\t" + gMoney(amt) + " to " + title });
    return;
  } else if (kind.equals("gleave")) {
    if (int(gNum(v1, -1)) != 0) return;
    GGroup g = gFind(ctx);
    if (g != null) gGroups.remove(gGroups.indexOf(g));
    gOpen = "";
  }
  gstSave();
}

void gInvite(GGroup g) {
  String ms = "";
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    if (ms.length() > 0) ms += ";";
    ms += (m.id + ":" + join(split(gClean(m.name), ":"), " ") + ":" + m.amt + ":" + (m.shared ? "1" : "0") + ":" + m.key);
  }
  gSend(g, "Invite to " + g.name,
        new String[] { gRow("INVITE", g.id, g.name, ms, join(g.order, ","), "" + g.turn) },
        new String[] { "Invite to " + g.name + "\tFrom " + gMyName + " · " + g.members.size() + " member" + (g.members.size() == 1 ? "" : "s") + " · open with ANA to join" });
}

// ---------------------------------------------------------------- taps
boolean gstAct(int id) {
  if (id < R_GPOOLS || (id > R_GLEAVE && id < R_GPOOL) || id >= R_GBUY + 1000) return false;
  if (id == R_GPOOLS) gfPools = !gfPools;
  else if (id == R_GGROUPS) gfGroups = !gfGroups;
  else if (id == R_GALERTS) gfAlerts = !gfAlerts;
  else if (id == R_GTURNS) gfTurns = !gfTurns;
  else if (id == R_GNAME) { gAsk("name", "", "Your name in groups", "What your groups see next to what you share.", "Name|" + gMyName + "|text"); return true; }
  else if (id == R_GPADD) { gAsk("padd", "", "Add a pool", "A pool is money you set aside in your head, inside what you already hold. Nothing moves.", "Name (car, mortgage, gas...)||text\nTarget (USD)||number"); return true; }
  else if (id == R_GPNEXT) {
    if (gPools.size() == 0) { gAsk("padd", "", "Add a pool", "", "Name (car, mortgage, gas...)||text\nTarget (USD)||number"); return true; }
    GPool p = (GPool) gPools.get(gNext % gPools.size());
    gAsk("pnext", "", "Top up " + p.name, "Next in your rotation. The one after it is next.", "Amount (USD)||number");
    return true;
  }
  else if (id == R_GNEW) { gAsk("gnew", "", "Create a group", "Then send the invite (.pngmesh + .sha256) to the people you want in it.", "Group name||text\nYour name in the group|" + gMyName + "|text"); return true; }
  else if (id == R_GIMPORT) { if (js != null) js.importFiles(); return true; }
  else if (id == R_GBACK) { gOpen = ""; tabScroll[tab] = 0; return true; }
  else if (id >= R_GPOOL && id < R_GPOOL + 1000) {
    int n = id - R_GPOOL;
    if (n < gPools.size()) {
      GPool p = (GPool) gPools.get(n);
      gPick("pool", p.id, p.name + ": " + gMoney(p.have) + (p.target > 0 ? " of " + gMoney(p.target) : ""), "Top up\nTake out\nChange the target\nRename\nRemove");
    }
    return true;
  }
  else if (id >= R_GGROUP && id < R_GGROUP + 1000) {
    int n = id - R_GGROUP;
    if (n < gGroups.size()) { GGroup og = (GGroup) gGroups.get(n); gOpen = og.id; tabScroll[tab] = 0; }
    return true;
  }
  else {
    GGroup g = gFind(gOpen);
    if (g == null) { gOpen = ""; return true; }
    if (id == R_GINVITE) gInvite(g);
    else if (id == R_GSHARE) {
      gAsk("gshare", g.id, "Share a balance with " + g.name,
           "Only this number goes out: no addresses, no keys. It starts at what your front face shows (" + gMoney(gFront) + "); change it to share less.",
           "Amount (USD)|" + nf(gFront, 0, 2) + "|number");
    } else if (id == R_GALERT) gAsk("galert", g.id, "Spend alert to " + g.name, "Tell the group you're about to spend, so someone can spend at the same time.", "Amount|25|number\nCurrency (USD, BBD...)|USD|text\nOn what (gas, groceries...)||text");
    else if (id == R_GTURN) {
      String next = g.order.length > 0 ? gNameOf(g, g.order[(g.turn + 1) % g.order.length]) : "";
      gPick("gturn", g.id, "Turns in " + g.name, (g.order.length > 0 ? "Pass the turn to " + next : "Start turns with the first member") + "\nSet the order: members as listed");
    }
    else if (id == R_GBUYNEW) gAsk("gbuy", g.id, "Start a group buy", "Bulk groceries, early tickets, a big order: everyone pledges toward the target.", "What||text\nTarget (USD)||number");
    else if (id == R_GLEAVE) gPick("gleave", g.id, "Leave " + g.name + "? (only on this phone)", "Leave the group\nStay");
    else if (id >= R_GBUY && id < R_GBUY + 1000) {
      int n = id - R_GBUY;
      if (n < g.buys.size()) {
        GBuy b = (GBuy) g.buys.get(n);
        gAsk("gpledge", g.id + "|" + b.id, "Pledge to " + b.title, gMoney(gPledged(b)) + " of " + gMoney(b.target) + " pledged so far.", "Your pledge (USD)||number");
      }
    }
    return true;
  }
  gstSave();
  return true;
}

void gstIcon(int id, float cx, float cy, float s, color c) {
  if (id == R_GPOOLS || id == R_GPADD || id == R_GPNEXT) icoTarget(cx, cy, s, c);
  else if (id == R_GGROUPS || id == R_GNEW || id == R_GINVITE) icoGrid(cx, cy, s * 0.9, c);
  else if (id == R_GALERTS || id == R_GALERT) icoBell(cx, cy, s, c);
  else if (id == R_GTURNS || id == R_GTURN) icoRefresh(cx, cy, s, c);
  else if (id == R_GNAME) icoPencil(cx, cy, s, c);
  else if (id == R_GIMPORT) icoDown(cx, cy, s, c);
  else if (id == R_GBACK || id == R_GLEAVE) icoHistory(cx, cy, s, c);
  else if (id == R_GSHARE) icoEye(cx, cy, s, c);
  else if (id == R_GBUYNEW) icoCal(cx, cy, s, c);
  else if (id == 56) icoTarget(cx, cy, s, c);          // FLEX: gift eFLEX
  else if (id == 57) icoInfo(cx, cy, s, c);            // FLEX: proof card
  else if (id == 58) icoEye(cx, cy, s, c);             // FLEX: hide the number
  else if (id == 59) icoEye(cx, cy, s, c);             // FLEX: show while sharing the screen
  else icoInfo(cx, cy, s, c);
}

// ---------------------------------------------------------------- drawing
float gText(String t, float y, float sz, color c) {
  textSizeQ(sz);
  float th = textBoxHeight(t, 712 * fk, sz);
  fill(c);
  textAlign(LEFT, TOP);
  text(t, FX(70), y, 712 * fk, th + 10 * fk);
  return y + th;
}

void gBar(float x, float y, float w, float frac, color c) {
  noStroke();
  fill(30, 40, 64);
  rect(x, y, w, 10 * fk);
  fill(c);
  rect(x, y, w * constrain(frac, 0, 1), 10 * fk);
}

float drawGst(float y) {
  gstLoad();
  gstPollInbox();
  gstPollAnswer();
  if (js != null && millis() - gTotalsAt > 2000) {
    gTotalsAt = millis();
    String[] t = split(js.walletTotals(), "\t");
    if (t.length > 1) { gAll = gNum(t[0], 0); gFront = gNum(t[1], 0); }
  }
  if (gOpen.length() > 0 && gFind(gOpen) != null) return drawGstGroup(y, gFind(gOpen));
  gOpen = "";

  // what GST is
  String t = "Group Spend Technology. Turn on only what you need. GST never holds money: groups share sealed "
           + ".pngmesh files (+ .sha256), sent however you like and opened with ANA.";
  textSizeQ(20 * fk);
  float th = textBoxHeight(t, 712 * fk, 20 * fk);
  glassCard(FX(38), y, 776 * fk, th + 50 * fk, 34 * fk, GGREEN);
  gText(t, y + 24 * fk, 20 * fk, #C9D3E6);
  y += th + 80 * fk;

  y = setSection("Opt in", y, GGREEN);
  y = setGroup(y, 5);
  setRowToggle(R_GPOOLS, y, 0, "Personal pools", "Car, mortgage, gas: top up in rotation", gfPools, GGREEN);
  setRowToggle(R_GGROUPS, y, 1, "Groups", "A combined balance; members share a number", gfGroups, GGREEN);
  setRowToggle(R_GALERTS, y, 2, "Spend alerts", gfGroups ? "\"About to spend\" to the group" : "Needs Groups", gfAlerts, GGREEN);
  setRowToggle(R_GTURNS, y, 3, "Turns and group buys", gfGroups ? "Sou-sou turns, pledges toward a buy" : "Needs Groups", gfTurns, GGREEN);
  setRowValue(R_GNAME, y, 4, "Your name in groups", "What your groups see", gMyName, true, GGREEN);
  y += 5 * 100 * fk + 40 * fk;

  if (gfPools) y = drawGstPools(y);
  if (gfGroups) y = drawGstGroups(y);
  if (!gfPools && !gfGroups) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    textSizeQ(21 * fk);
    text("Turn on Personal pools or Groups to start", FX(70), y + 20 * fk);
    y += 60 * fk;
  }
  return y + 40 * fk;
}

float drawGstPools(float y) {
  y = setSection("Personal pools", y, GGREEN);
  float inPools = gInPools(), free = gAll - inPools;
  glassCard(FX(38), y, 776 * fk, 150 * fk, 40 * fk, GGREEN);
  textAlign(LEFT, BASELINE);
  fill(#9AA6C0);
  textSizeQ(20 * fk);
  text("You watch", FX(70), y + 44 * fk);
  text("In pools", FX(330), y + 44 * fk);
  text(free >= 0 ? "Not in a pool" : "Pools are over by", FX(560), y + 44 * fk);
  fill(#FFFFFF);
  textSizeQ(32 * fk);
  boldTextF(gMoney(gAll), FX(70), y + 90 * fk);
  boldTextF(gMoney(inPools), FX(330), y + 90 * fk);
  fill(free >= 0 ? GGREEN : #FF9A5A);
  boldTextF(gMoney(abs(free)), FX(560), y + 90 * fk);
  fill(#9AA6C0);
  textSizeQ(19 * fk);
  text(gPools.size() > 0 ? "Next top-up: " + ((GPool) gPools.get(gNext % gPools.size())).name : "Add your first pool below", FX(70), y + 128 * fk);
  y += 170 * fk;

  for (int i = 0; i < gPools.size(); i++) {
    GPool p = (GPool) gPools.get(i);
    float ch = 130 * fk;
    boolean next = i == gNext % gPools.size();
    setRows.add(new SetRow(R_GPOOL + i, y, y + ch));
    glassCard(FX(38), y, 776 * fk, ch, 36 * fk, next ? GGREEN : color(60, 90, 180));
    textAlign(LEFT, BASELINE);
    fill(#F4F7FF);
    textSizeQ(26 * fk);
    String pn = fitText(p.name, 400 * fk);
    boldTextF(pn, FX(70), y + 46 * fk);
    float pw = textWidth(pn);
    if (next) { fill(GGREEN); textSizeQ(18 * fk); text("NEXT", FX(70) + pw + 22 * fk, y + 44 * fk); }
    fill(#9AA6C0);
    textSizeQ(19 * fk);
    text(p.target > 0 ? gMoney(p.have) + " of " + gMoney(p.target) : gMoney(p.have) + " set aside", FX(70), y + 78 * fk);
    textAlign(RIGHT, BASELINE);
    fill(#FFFFFF);
    textSizeQ(28 * fk);
    boldTextF(p.target > 0 ? int(100 * min(1, p.have / p.target)) + "%" : gMoney(p.have), FX(780), y + 50 * fk);
    gBar(FX(70), y + 98 * fk, 710 * fk, p.target > 0 ? p.have / p.target : 0, GGREEN);
    y += ch + 18 * fk;
  }
  y = setGroup(y, 2);
  setRowValue(R_GPADD, y, 0, "Add a pool", "Money set aside in your head, nothing moves", "", true, GGREEN);
  setRowValue(R_GPNEXT, y, 1, "Top up the next pool", gPools.size() > 0 ? "In rotation: " + ((GPool) gPools.get(gNext % gPools.size())).name : "Add a pool first", "", true, GGREEN);
  return y + 2 * 100 * fk + 40 * fk;
}

float drawGstGroups(float y) {
  y = setSection("Groups", y, GGREEN);
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    float ch = (gfTurns && g.order.length > 0 ? 150 : 120) * fk;
    setRows.add(new SetRow(R_GGROUP + i, y, y + ch));
    glassCard(FX(38), y, 776 * fk, ch, 36 * fk, GGREEN);
    textAlign(LEFT, BASELINE);
    fill(#F4F7FF);
    textSizeQ(27 * fk);
    boldTextF(fitText(g.name, 430 * fk), FX(70), y + 48 * fk);
    fill(#9AA6C0);
    textSizeQ(19 * fk);
    text(g.members.size() + " member" + (g.members.size() == 1 ? "" : "s") + "  ·  combined, as shared", FX(70), y + 82 * fk);
    if (gfTurns && g.order.length > 0) {
      fill(GGREEN);
      text("Turn: " + gNameOf(g, g.order[g.turn % g.order.length]), FX(70), y + 116 * fk);
    }
    textAlign(RIGHT, BASELINE);
    fill(#FFFFFF);
    textSizeQ(32 * fk);
    boldTextF(gMoney(gCombined(g)), FX(780), y + 56 * fk);
    y += ch + 18 * fk;
  }
  if (gGroups.size() == 0) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    textSizeQ(21 * fk);
    text("No groups yet: create one, or IMPORT an invite", FX(70), y + 24 * fk);
    y += 60 * fk;
  }
  y = setGroup(y, 2);
  setRowValue(R_GNEW, y, 0, "Create a group", "Then send the invite file", "", true, GGREEN);
  setRowValue(R_GIMPORT, y, 1, "Open a GST file", "An invite or update (.pngmesh + .sha256)", "", true, GGREEN);
  return y + 2 * 100 * fk + 40 * fk;
}

float drawGstGroup(float y, GGroup g) {
  y = setGroup(y, 1);
  setRowValue(R_GBACK, y, 0, "All groups", "Back to GST", "", true, GGREEN);
  y += 100 * fk + 30 * fk;

  // the group: combined balance and who shared what
  int nm = g.members.size();
  float ch = (130 + nm * 46) * fk;
  glassCard(FX(38), y, 776 * fk, ch, 40 * fk, GGREEN);
  textAlign(LEFT, BASELINE);
  fill(#F4F7FF);
  textSizeQ(30 * fk);
  boldTextF(fitText(g.name, 430 * fk), FX(70), y + 52 * fk);
  fill(#9AA6C0);
  textSizeQ(19 * fk);
  text("Combined, as each member shared it", FX(70), y + 86 * fk);
  textAlign(RIGHT, BASELINE);
  fill(#FFFFFF);
  textSizeQ(36 * fk);
  boldTextF(gMoney(gCombined(g)), FX(780), y + 60 * fk);
  for (int i = 0; i < nm; i++) {
    GMember m = (GMember) g.members.get(i);
    float ry = y + (130 + i * 46) * fk;
    boolean turn = gfTurns && g.order.length > 0 && g.order[g.turn % g.order.length].equals(m.id);
    textAlign(LEFT, BASELINE);
    fill(turn ? GGREEN : #DCE3F0);
    textSizeQ(22 * fk);
    text(fitText(m.name + (m.id.equals(gMyId) ? " (you)" : "") + (turn ? "  · turn" : ""), 380 * fk), FX(70), ry);
    fill(#7A8BA0);
    textSizeQ(18 * fk);
    text(m.shared ? gShortWhen(m.when) : "not shared yet", FX(470), ry);
    textAlign(RIGHT, BASELINE);
    fill(m.shared ? #FFFFFF : #7A8BA0);
    textSizeQ(22 * fk);
    text(m.shared ? gMoney(m.amt) : "-", FX(780), ry);
  }
  y += ch + 30 * fk;

  // what you can do
  int n = 2 + (gfAlerts ? 1 : 0) + (gfTurns ? 2 : 0) + 1;
  y = setGroup(y, n);
  int r = 0;
  setRowValue(R_GINVITE, y, r++, "Send the invite", "Bring people in: .pngmesh + .sha256", "", true, GGREEN);
  setRowValue(R_GSHARE, y, r++, "Share a balance", "Only a number, never an address", "", true, GGREEN);
  if (gfAlerts) setRowValue(R_GALERT, y, r++, "Send a spend alert", "\"About to spend\" to the group", "", true, GGREEN);
  if (gfTurns) {
    setRowValue(R_GTURN, y, r++, "Turns", g.order.length > 0 ? "Now: " + gNameOf(g, g.order[g.turn % g.order.length]) : "Sou-sou / meeting-turn order", "", true, GGREEN);
    setRowValue(R_GBUYNEW, y, r++, "Start a group buy", "Everyone pledges toward a target", "", true, GGREEN);
  }
  setRowValue(R_GLEAVE, y, r++, "Leave the group", "Only on this phone", "", true, #9AA6C0);
  y += n * 100 * fk + 30 * fk;

  // group buys
  if (gfTurns && g.buys.size() > 0) {
    y = setSection("Group buys", y, GGREEN);
    for (int i = 0; i < g.buys.size(); i++) {
      GBuy b = (GBuy) g.buys.get(i);
      float bh = 120 * fk, got = gPledged(b);
      setRows.add(new SetRow(R_GBUY + i, y, y + bh));
      glassCard(FX(38), y, 776 * fk, bh, 36 * fk, GGREEN);
      textAlign(LEFT, BASELINE);
      fill(#F4F7FF);
      textSizeQ(25 * fk);
      boldTextF(fitText(b.title, 430 * fk), FX(70), y + 44 * fk);
      fill(#9AA6C0);
      textSizeQ(19 * fk);
      text(gMoney(got) + " of " + gMoney(b.target) + " pledged  ·  " + b.pledges.size() + " pledge" + (b.pledges.size() == 1 ? "" : "s") + "  ·  tap to pledge", FX(70), y + 76 * fk);
      gBar(FX(70), y + 92 * fk, 710 * fk, b.target > 0 ? got / b.target : 0, GGREEN);
      y += bh + 18 * fk;
    }
    y += 20 * fk;
  }

  // what happened
  y = setSection("Activity", y, GGREEN);
  int shown = 0;
  for (int i = gFeed.size() - 1; i >= 0 && shown < 10; i--) {
    String[] f = (String[]) gFeed.get(i);
    if (!f[0].equals(g.id)) continue;
    textSizeQ(20 * fk);
    float fh = textBoxHeight(f[2], 560 * fk, 20 * fk);
    fill(#DCE3F0);
    textAlign(LEFT, TOP);
    text(f[2], FX(70), y, 560 * fk, fh + 10 * fk);
    fill(#7A8BA0);
    textAlign(RIGHT, TOP);
    textSizeQ(17 * fk);
    text(gShortWhen(f[1]), FX(780), y + 2 * fk);
    y += fh + 22 * fk;
    shown++;
  }
  if (shown == 0) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    textSizeQ(20 * fk);
    text("Nothing yet", FX(70), y + 20 * fk);
    y += 50 * fk;
  }
  return y + 40 * fk;
}
