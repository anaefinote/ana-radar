// Flex.pde — FLEX points: the fifth pill in Settings (ANA | EFINOTE | WATCH | GST | FLEX 500), showing your eFLEX.
//   eFLEX   earned: the ideal is 1 eFLEX for every $10 held, per day, averaged from what ANA watches (counted at
//           midnight). A proven wallet (OWNERSHIP PROOF) counts in full; a wallet only watched counts F_WATCHED of it
//   gifted  eFLEX other people sent you: shown apart, so your earned score stays honest
//   FlexP   FLEX points bought: kept apart from eFLEX, never mixed (purchases open November 30)
// Gifts move through a GST group's LEDGER, and everyone in the group must hold the same ledger:
//   * every entry is signed by the sender's phone (its own P-256 key, kept on the phone)
//   * every entry carries the sha256 of the one before it, so the entries form a chain
//   * a ledger that splits (the same entry number with two different contents) is a conflict: the group's
//     transfers freeze, and it shows
//   * a gift is pending until every member's ANA confirms (ACK, signed) the same ledger, then it's final
// Ledgers, acks and keys ride along in every GST file sent to the group (.pngmesh + .sha256, Gst.pde).

final color FGOLD = #F5B942, FVIOLET = #B48CFF, FBLUE = #6FA2FF;
boolean fLoaded = false, fOpen = false, fHide = false, fShared = false;
boolean fShowShared = false;           // show eFLEX while the screen is shared (a demo, a Zoom); off: •••• while shared
int fEarned = 0;                       // eFLEX earned, all days counted so far
float fSumP = 0, fAllP = 0;            // the proven part of what ANA watches (OWNERSHIP PROOF), summed and now
final float F_WATCHED = 0.25;          // a wallet only watched (not proven yours) counts for this much of a proven one
                                       // (copy-pasting someone else's address mustn't earn like holding your own);
                                       // the weights move to a signed flex lesson later
String fDay = "";                      // today (yyyy-mm-dd) and its samples of the watched total
float fSum = 0;
int fCount = 0;
ArrayList fHist = new ArrayList();     // String[] { day, points }
float fAll = 0;
int fTotAt = -100000, fSampleAt = -100000, fStartAt = -1;
String fMyKey = "";
final int F_GIFT = 56, F_PROOF = 57, F_HIDE = 58, F_SHOWSHARE = 59;   // rows on the FLEX page; icons: gstIcon (Gst.pde)
final int F_BILLS = 60;                // BILLS: paying bills earns eFLEX (native: Bills / BillCore)
int fBills = 0, fBillsOpen = 0, fBillsAll = 0;   // eFLEX earned from bills, bills still open, all bills
int fGoal = -1;                        // the 30-day settlement goal, % (-1: no bills yet)

// eFLEX earned: holding (counted at midnight) + bills paid, reported and helped with
int flexEarned() { return fEarned + fBills; }

class LEntry {
  int i, amt;
  String from, to, kind, when, prev, h, sig;
  LEntry(int i, String from, String to, String kind, int amt, String when, String prev, String h, String sig) {
    this.i = i; this.from = from; this.to = to; this.kind = kind; this.amt = amt; this.when = when;
    this.prev = prev; this.h = h; this.sig = sig;
  }
}

// ---------------------------------------------------------------- keys and hashes (native: Flex.java / Flex.swift)
String flexMyKey() {
  if (fMyKey.length() == 0 && js != null) { fMyKey = js.flexKey(); if (fMyKey == null) fMyKey = ""; }
  return fMyKey;
}

String lCanon(String gid, LEntry e) {
  return gid + "|" + e.i + "|" + e.from + "|" + e.to + "|" + e.kind + "|" + e.amt + "|" + e.when + "|" + e.prev;
}

String lHeadH(GGroup g) {
  if (g.ledger.size() == 0) return "0";
  LEntry last = (LEntry) g.ledger.get(g.ledger.size() - 1);
  return last.h;
}

String memberKey(GGroup g, String id) {
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    if (m.id.equals(id)) return m.key;
  }
  return "";
}

// a member's key: the first one seen is kept; a different one later is refused
void pinKey(GGroup g, String id, String name, String key, String when) {
  if (key == null || key.length() == 0) return;
  GMember m = gMember(g.members, id, name);
  if (m.key.length() == 0) m.key = key;
  else if (!m.key.equals(key)) gFeedAdd(g.id, when, "Refused a new key for " + m.name + ": not the phone this group knows");
}

String lSerialize(GGroup g) {
  String s = "";
  for (int k = 0; k < g.ledger.size(); k++) {
    LEntry e = (LEntry) g.ledger.get(k);
    if (k > 0) s += ";";
    s += e.i + "," + e.from + "," + e.to + "," + e.kind + "," + e.amt + "," + e.when + "," + e.prev + "," + e.h + "," + e.sig;
  }
  return s;
}

ArrayList lParse(String s) {
  ArrayList out = new ArrayList();
  if (s == null || s.length() == 0) return out;
  String[] es = split(s, ";");
  for (int k = 0; k < es.length; k++) {
    String[] f = split(es[k], ",");
    if (f.length < 9) continue;
    out.add(new LEntry(int(gNum(f[0], -1)), f[1], f[2], f[3], int(gNum(f[4], 0)), f[5], f[6], f[7], f[8]));
  }
  return out;
}

// the first entry that fails (wrong number, broken chain, bad hash, bad or unknown signature), or -1
int lCheck(GGroup g, ArrayList list) {
  for (int k = 0; k < list.size(); k++) {
    LEntry e = (LEntry) list.get(k);
    String prev = "0";
    if (k > 0) { LEntry pe = (LEntry) list.get(k - 1); prev = pe.h; }
    if (e.i != k || !e.prev.equals(prev) || e.amt <= 0) return k;
    String key = memberKey(g, e.from);
    String canon = lCanon(g.id, e);
    if (key.length() == 0 || !js.flexVerify(key, canon, e.sig)) return k;
    if (!e.h.equals(js.flexHash(canon + "|" + e.sig))) return k;
  }
  return -1;
}

// a ledger that came in: checked, then taken if it only adds to ours; two versions = a conflict
void lMerge(GGroup g, String ser, String who, String when) {
  if (js == null) return;
  ArrayList inc = lParse(ser);
  int bad = lCheck(g, inc);
  if (bad >= 0) { gFeedAdd(g.id, when, "Refused " + who + "'s ledger: entry " + (bad + 1) + " failed its check"); return; }
  int common = min(inc.size(), g.ledger.size());
  for (int k = 0; k < common; k++) {
    LEntry ea = (LEntry) inc.get(k), eb = (LEntry) g.ledger.get(k);
    if (!ea.h.equals(eb.h)) {
      if (g.conflict.length() == 0) gFeedAdd(g.id, when, "Two different ledgers from entry " + (k + 1) + ": transfers are frozen until the group agrees");
      g.conflict = "Two versions from entry " + (k + 1);
      return;
    }
  }
  if (inc.size() <= g.ledger.size()) return;
  for (int k = g.ledger.size(); k < inc.size(); k++) {
    LEntry e = (LEntry) inc.get(k);
    gFeedAdd(g.id, e.when, gNameOf(g, e.from) + " gifted " + gNameOf(g, e.to) + " " + fN(e.amt) + " eFLEX");
  }
  g.ledger = inc;
}

// a member says which ledger they hold (signed by their phone)
void lAck(GGroup g, String from, String n, String h, String sig) {
  String key = memberKey(g, from);
  if (js == null || key.length() == 0) return;
  if (!js.flexVerify(key, "ACK|" + g.id + "|" + from + "|" + n + "|" + h, sig)) return;
  g.acks.put(from, n + "|" + h);
}

// final once every member's ANA holds a ledger with this entry in it, the same as ours
boolean lFinal(GGroup g, int idx) {
  if (g.conflict.length() > 0) return false;
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    String a = (String) g.acks.get(m.id);
    if (a == null) return false;
    String[] p = split(a, "|");
    int n = int(gNum(p[0], 0));
    if (n < idx + 1) return false;
    if (n <= g.ledger.size()) {
      LEntry en = (LEntry) g.ledger.get(n - 1);
      if (!en.h.equals(p[1])) return false;
    }
  }
  return true;
}

String lWaiting(GGroup g) {
  if (g.ledger.size() == 0) return "";
  String w = "";
  for (int i = 0; i < g.members.size(); i++) {
    GMember m = (GMember) g.members.get(i);
    String a = (String) g.acks.get(m.id);
    boolean ok = false;
    if (a != null) {
      String[] p = split(a, "|");
      ok = int(gNum(p[0], 0)) >= g.ledger.size() && p.length > 1 && p[1].equals(lHeadH(g));
    }
    if (!ok) w += (w.length() > 0 ? ", " : "") + m.name;
  }
  return w;
}

// rows that ride along in every GST file to this group: the whole ledger, and our signed ack of it
String[] flexRows(GGroup g) {
  if (g.ledger.size() == 0 || js == null) return new String[0];
  String n = "" + g.ledger.size(), h = lHeadH(g);
  String sig = js.flexSign("ACK|" + g.id + "|" + gMyId + "|" + n + "|" + h);
  return new String[] { gRow("LEDGER", g.id, lSerialize(g), n, h, ""), gRow("ACK", g.id, n, h, sig, "") };
}

// LEDGER / ACK / PROOF packs (called from gApply)
boolean flexApply(GGroup g, String[] f, boolean mine) {
  String kind = f[1], from = f[3], who = f[4], when = f[5];
  if (kind.equals("LEDGER")) { if (!mine) lMerge(g, f[6], who, when); return true; }
  if (kind.equals("ACK")) { lAck(g, from, f[6], f[7], f[8]); return true; }
  if (kind.equals("PROOF")) {
    String key = memberKey(g, from);
    boolean ok = js != null && key.length() > 0 && js.flexVerify(key, "PROOF|" + g.id + "|" + from + "|" + f[6] + "|" + f[7] + "|" + when, f[8]);
    gFeedAdd(g.id, when, (mine ? "You show " : who + " shows ") + fN(int(gNum(f[6], 0))) + " eFLEX earned over " + f[7] + " days"
             + (ok ? " (signed by their phone)" : " (signature not checked)"));
    return true;
  }
  return false;
}

// ---------------------------------------------------------------- balances
int flexGiven() {
  int t = 0;
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    for (int k = 0; k < g.ledger.size(); k++) {
      LEntry e = (LEntry) g.ledger.get(k);
      if (e.from.equals(gMyId) && e.kind.equals("EFLEX")) t += e.amt;
    }
  }
  return t;
}

int flexGifted(boolean finalOnly) {
  int t = 0;
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    for (int k = 0; k < g.ledger.size(); k++) {
      LEntry e = (LEntry) g.ledger.get(k);
      if (e.to.equals(gMyId) && e.kind.equals("EFLEX") && (lFinal(g, k) == finalOnly)) t += e.amt;
    }
  }
  return t;
}

// whole numbers with commas (nfc prints 0 as "" in Processing.js)
String fN(int v) { return v == 0 ? "0" : (v < 0 ? "-" + nfc(-v) : nfc(v)); }

int flexToday() { return fCount > 0 ? floor(fSum / fCount / 10.0) : 0; }

// ---------------------------------------------------------------- earning: samples of what ANA watches
void flexLoad() {
  if (fLoaded || js == null) return;
  fLoaded = true;
  String s = js.pref("flex");
  if (s == null) s = "";
  String[] lines = split(s, "\n");
  for (int i = 0; i < lines.length; i++) {
    String[] f = split(lines[i], "\t");
    if (f.length < 2) continue;
    if (f[0].equals("E")) fEarned = int(gNum(f[1], 0));
    else if (f[0].equals("D") && f.length > 3) { fDay = f[1]; fSum = gNum(f[2], 0); fCount = int(gNum(f[3], 0)); fSumP = f.length > 4 ? gNum(f[4], 0) : fSum; }
    else if (f[0].equals("Y") && f.length > 2) fHist.add(new String[] { f[1], f[2] });
    else if (f[0].equals("O")) fHide = f[1].equals("1");
    else if (f[0].equals("S")) fShowShared = f[1].equals("1");
  }
}

void flexSave() {
  if (js == null) return;
  String s = "E\t" + fEarned + "\nD\t" + fDay + "\t" + fSum + "\t" + fCount + "\t" + fSumP + "\nO\t" + (fHide ? "1" : "0") + "\nS\t" + (fShowShared ? "1" : "0") + "\n";
  for (int i = max(0, fHist.size() - 120); i < fHist.size(); i++) {
    String[] h = (String[]) fHist.get(i);
    s += "Y\t" + h[0] + "\t" + h[1] + "\n";
  }
  js.setPref("flex", s);
}

// every frame (cheap): GST mail and dialogs, the watched total, and a sample a minute
void flexTick() {
  if (js == null) return;
  if (fStartAt < 0) fStartAt = millis();
  gstLoad();
  flexLoad();
  gstPollInbox();
  gstPollAnswer();
  if (millis() - fTotAt > 2000) {
    fTotAt = millis();
    String[] t = split(js.walletTotals(), "\t");
    if (t.length > 1) { fAll = gNum(t[0], 0); gAll = fAll; gFront = gNum(t[1], 0); }
    fShared = t.length > 2 && t[2].equals("1");
    fAllP = t.length > 3 ? min(fAll, gNum(t[3], 0)) : 0;
    String[] b = split(js.billsText(), "\t");     // BILLS: open, eFLEX, all
    if (b.length > 2) { fBillsOpen = int(gNum(b[0], 0)); fBills = int(gNum(b[1], 0)); fBillsAll = int(gNum(b[2], 0)); }
    fGoal = b.length > 3 ? int(gNum(b[3], -1)) : -1;
  }
  if (millis() - fStartAt < 20000 || millis() - fSampleAt < 60000) return;   // let the wallets load first
  fSampleAt = millis();
  String day = gNow().substring(0, 10);
  if (!day.equals(fDay)) {
    if (fDay.length() > 0 && fCount > 0) {                // a day ended: it counts now
      float avgP = fSumP / fCount, avgW = max(0, fSum - fSumP) / fCount;   // proven, and only watched
      int pts = floor((avgP + F_WATCHED * avgW) / 10.0);
      fEarned += pts;
      fHist.add(new String[] { fDay, "" + pts });
    }
    fDay = day;
    fSum = 0;
    fSumP = 0;
    fCount = 0;
  }
  fSum += fAll;
  fSumP += fAllP;
  fCount++;
  flexSave();
}

// ---------------------------------------------------------------- the FLEX pill and page (Settings2.pde)
// The FLEX pill's label: your eFLEX, hidden (••••) when you ask or while the screen is shared
String flexPillLabel() {
  return "FLEX " + (fHide || fMasked() ? "••••" : fN(flexEarned()));
}

// (the floating pill is gone: FLEX lives in Settings now; these stay so older hooks do nothing)
boolean flexChipHit(float x, float y) { return false; }
void drawFlexChip() { }
void drawFlexPanel() { }
void flexPanelTap(float mx, float my) { }

float fCard(float y, float h, color c) {
  glassCard(FX(38), y, 776 * fk, h, 34 * fk, c);
  return y;
}

// the Flex wallet, as a Settings page (from FY(460), under the pills)
float drawFlexPage(float y) {
  int given = flexGiven(), avail = max(0, flexEarned() - given);
  fCard(y, 200 * fk, FGOLD);
  textAlign(LEFT, BASELINE);
  fill(FGOLD);
  textSizeQ(19 * fk);
  boldTextF("eFLEX EARNED", FX(70), y + 40 * fk);
  fill(#FFFFFF);
  textSizeQ(56 * fk);
  boldTextF(fMasked() ? "••••" : fN(flexEarned()), FX(70), y + 104 * fk);
  fill(#9AA6C0);
  textSizeQ(19 * fk);
  text("The ideal: 1 eFLEX per $10 a day. Proven wallets reach it." + (fBills > 0 && !fMasked() ? "  Bills: " + fN(fBills) : ""), FX(70), y + 140 * fk);
  text("+" + fN(flexToday()) + " building today (counts at midnight)  ·  " + fN(avail) + " to give", FX(70), y + 172 * fk);
  y += 220 * fk;

  fCard(y, 130 * fk, FVIOLET);
  fill(FVIOLET);
  textSizeQ(19 * fk);
  boldTextF("GIFTED eFLEX", FX(70), y + 40 * fk);
  fill(#FFFFFF);
  textSizeQ(40 * fk);
  int gf = flexGifted(true), gp = flexGifted(false);
  boldTextF(fMasked() ? "••••" : fN(gf), FX(70), y + 92 * fk);
  fill(#9AA6C0);
  textSizeQ(19 * fk);
  textAlign(RIGHT, BASELINE);
  text(gp > 0 ? "+" + fN(gp) + " waiting for the group" : "From people in your groups", FX(780), y + 90 * fk);
  textAlign(LEFT, BASELINE);
  y += 150 * fk;

  fCard(y, 130 * fk, FBLUE);
  fill(FBLUE);
  textSizeQ(19 * fk);
  boldTextF("FlexP", FX(70), y + 40 * fk);
  fill(#FFFFFF);
  textSizeQ(40 * fk);
  boldTextF("0", FX(70), y + 92 * fk);
  fill(#9AA6C0);
  textSizeQ(19 * fk);
  textAlign(RIGHT, BASELINE);
  text("FLEX points you buy · from November 30", FX(780), y + 90 * fk);
  textAlign(LEFT, BASELINE);
  y += 160 * fk;

  y = setGroup(y, 1);                    // BILLS
  setRowValue(F_BILLS, y, 0, "Bills", "Settle up, get 30 days ahead, help others", fGoal < 0 ? "Earn eFLEX" : fGoal >= 100 ? "30 days ahead" : fGoal + "% to 30 days", true, GGREEN);
  y += 100 * fk + 14 * fk;
  fill(#9AA6C0);                         // said plainly, every time bills show
  textAlign(LEFT, BASELINE);
  textSizeQ(18 * fk);
  text("Novvera never touches money. You pay your billers yourself.", FX(60), y + 22 * fk);
  y += 60 * fk;

  y = setGroup(y, 4);
  setRowValue(F_GIFT, y, 0, "Gift eFLEX", "Through a GST group's ledger", "", true, FGOLD);
  setRowValue(F_PROOF, y, 1, "Send a proof card", "Show your earned eFLEX to a group, signed", "", true, FGOLD);
  setRowToggle(F_HIDE, y, 2, "Hide the number", "The pill shows ••••", fHide, FGOLD);
  setRowToggle(F_SHOWSHARE, y, 3, "Show while sharing the screen", "For a demo or a Zoom. Off: •••• while shared", fShowShared, FGOLD);
  y += 4 * 100 * fk + 40 * fk;

  // every group's ledger: does everyone hold the same one?
  y = setSection("Group ledgers", y, FGOLD);
  textSizeQ(20 * fk);
  int shown = 0;
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    if (g.ledger.size() == 0 && g.conflict.length() == 0) continue;
    String w = lWaiting(g);
    String st = g.conflict.length() > 0 ? "Conflict: " + g.conflict + ". Transfers frozen."
              : w.length() == 0 ? "Everyone holds the same ledger" : "Waiting for " + w;
    fill(g.conflict.length() > 0 ? #FF9A5A : w.length() == 0 ? GGREEN : #C9D3E6);
    textAlign(LEFT, BASELINE);
    text(fitText(g.name + " · " + g.ledger.size() + " entr" + (g.ledger.size() == 1 ? "y" : "ies") + " · " + st, 740 * fk), FX(60), y + 20 * fk);
    y += 40 * fk;
    shown++;
  }
  if (shown == 0) {
    fill(#7A8BA0);
    textAlign(LEFT, BASELINE);
    text("No gifts yet. Gifts go through a GST group.", FX(60), y + 20 * fk);
    y += 40 * fk;
  }
  return y + 40 * fk;
}

// taps on the FLEX page's rows (from settingsAct)
boolean flexAct(int id) {
  if (id == F_HIDE) { fHide = !fHide; flexSave(); return true; }
  if (id == F_SHOWSHARE) { fShowShared = !fShowShared; flexSave(); return true; }
  if (id == F_GIFT) { flexStart("fgift"); return true; }
  if (id == F_BILLS) { if (js != null) js.billsOpen(); return true; }
  if (id == F_PROOF) { flexStart("fproof"); return true; }
  return false;
}

// groups you can gift through: a ledger with no conflict and someone else with a key
String flexGroups(boolean needOthers) {
  String ids = "";
  for (int i = 0; i < gGroups.size(); i++) {
    GGroup g = (GGroup) gGroups.get(i);
    if (g.conflict.length() > 0) continue;
    boolean ok = !needOthers;
    for (int k = 0; k < g.members.size(); k++) {
      GMember m = (GMember) g.members.get(k);
      if (!m.id.equals(gMyId) && m.key.length() > 0) ok = true;
    }
    if (ok) ids += (ids.length() > 0 ? "," : "") + g.id;
  }
  return ids;
}

void flexStart(String what) {
  String ids = flexGroups(what.equals("fgift"));
  if (ids.length() == 0) {
    appMsg = what.equals("fgift") ? "Gifts go through a GST group: members share a balance first" : "Proof cards go to a GST group: create or join one first";
    appMsgAt = millis();
    return;
  }
  String[] gs = split(ids, ",");
  if (gs.length == 1) { flexAfterGroup(what, gs[0]); return; }
  String names = "";
  for (int i = 0; i < gs.length; i++) names += (i > 0 ? "\n" : "") + gFind(gs[i]).name;
  gPick(what + "g", ids, what.equals("fgift") ? "Gift eFLEX through which group?" : "Send the proof card to which group?", names);
}

void flexAfterGroup(String what, String gid) {
  GGroup g = gFind(gid);
  if (g == null) return;
  if (what.equals("fproof")) {
    int days = fHist.size() + (fCount > 0 ? 1 : 0);
    String when = gNow();
    String sig = js.flexSign("PROOF|" + g.id + "|" + gMyId + "|" + flexEarned() + "|" + days + "|" + when);
    String row = gNewId("p") + "\tPROOF\t" + g.id + "\t" + gMyId + "\t" + gClean(gMyName) + "\t" + when + "\t" + flexEarned() + "\t" + days + "\t" + sig + "\t";
    gSend(g, "eFLEX proof card", new String[] { row }, new String[] { gMyName + "'s eFLEX\t" + fN(flexEarned()) + " earned over " + days + " days, signed by their phone" });
    return;
  }
  String ids = "", names = "";
  for (int k = 0; k < g.members.size(); k++) {
    GMember m = (GMember) g.members.get(k);
    if (m.id.equals(gMyId) || m.key.length() == 0) continue;
    ids += (ids.length() > 0 ? "," : "") + m.id;
    names += (names.length() > 0 ? "\n" : "") + m.name;
  }
  gPick("fmember", g.id + "|" + ids, "Gift eFLEX to", names);
}

boolean flexAnswered(String kind, String ctx, String[] v) {
  if (!kind.startsWith("f")) return false;
  String v1 = v.length > 1 ? v[1] : "";
  if (kind.equals("fgiftg") || kind.equals("fproofg")) {
    String[] gs = split(ctx, ",");
    int c = int(gNum(v1, -1));
    if (c >= 0 && c < gs.length) flexAfterGroup(kind.substring(0, kind.length() - 1), gs[c]);
  } else if (kind.equals("fmember")) {
    String[] c = split(ctx, "|");
    String[] ids = split(c[1], ",");
    int n = int(gNum(v1, -1));
    GGroup g = gFind(c[0]);
    if (g == null || n < 0 || n >= ids.length) return true;
    int avail = max(0, flexEarned() - flexGiven());
    gAsk("famount", g.id + "|" + ids[n], "Gift eFLEX to " + gNameOf(g, ids[n]),
         "You have " + fN(avail) + " eFLEX to give. It shows as gifted eFLEX for them; your earned score stays yours. Final once everyone in " + g.name + " holds the same ledger.",
         "Amount (eFLEX)||number");
  } else if (kind.equals("famount")) {
    String[] c = split(ctx, "|");
    GGroup g = gFind(c[0]);
    int amt = int(gNum(v1, 0));
    int avail = max(0, flexEarned() - flexGiven());
    if (g == null || amt <= 0) return true;
    if (amt > avail) { appMsg = "Only " + fN(avail) + " eFLEX to give"; appMsgAt = millis(); return true; }
    if (g.conflict.length() > 0) { appMsg = g.name + "'s ledger has a conflict: transfers are frozen"; appMsgAt = millis(); return true; }
    LEntry e = new LEntry(g.ledger.size(), gMyId, c[1], "EFLEX", amt, gNow(), lHeadH(g), "", "");
    String canon = lCanon(g.id, e);
    e.sig = js.flexSign(canon);
    if (e.sig == null || e.sig.length() == 0) { appMsg = "This phone couldn't sign the gift"; appMsgAt = millis(); return true; }
    e.h = js.flexHash(canon + "|" + e.sig);
    g.ledger.add(e);
    gFeedAdd(g.id, e.when, "You gifted " + gNameOf(g, c[1]) + " " + fN(amt) + " eFLEX (waiting for the group)");
    gSend(g, "eFLEX gift in " + g.name, new String[0],
          new String[] { gMyName + " gifted " + gNameOf(g, c[1]) + "\t" + fN(amt) + " eFLEX · signed · entry " + (e.i + 1) + " of " + g.name + "'s ledger" });
  }
  return true;
}

// eFLEX shows as •••• while the screen is shared, unless the owner chose to show it (a demo)
boolean fMasked() { return fShared && !fShowShared; }
