// CHATNOTE (experimental): the same messages, four ways. Orbit = APPify's own globe with people as the tiles
// (Appify.pde, peopleGlobe), River = one line of time, Notes = postmarked notes, Chat = contacts left, history
// right. People are their key colours: tap a colour chip to pick a person. Pinch to zoom River, Notes and Chat;
// tap a message to see it big. Typing and routes stay in the phone's own dialogs (js.chatWrite).

boolean chatOn = false;
float ck = 1;                        // CHATNOTE's own scale (APPify's fk is half that on an iPhone)
float chatZ = 1;                     // pinch zoom for River, Notes and Chat
int chatView = 0;                    // 0 Orbit, 1 River, 2 Notes, 3 Chat
String chatRaw = "";
ArrayList chatMsgs = new ArrayList(); // ChatMsg, oldest first
String chatWho = "";                 // the person picked (key id), "" = everyone
int chatPolled = -10000;
float chatScroll = 0, chatPX = 0, chatPY = 0, chatLX = 0, chatLY = 0;
boolean chatMoved = false, chatGlobeDrag = false;
ChatMsg chatBig = null;              // a message shown big
ArrayList chatHits = new ArrayList(); // float[]{x, y, w, h, kind, index}: kind 0 person, 1 message
ArrayList chatHitMsg = new ArrayList();

class ChatMsg {
  boolean mine; String name, key, route, text; int age;
}

color[] chatPal = { #4DA3FF, #F5B942, #9B7BFF, #3DDC97, #FF6B6B, #2EC4D6, #FF7FB0, #E8EEFA };

color chatCol(String key, int i) {
  if (key == null || key.length() < 12) return #8A93A6;
  String hx = "0123456789abcdef";
  int v = hx.indexOf(key.substring(i * 2, i * 2 + 1)) * 16 + hx.indexOf(key.substring(i * 2 + 1, i * 2 + 2));
  return chatPal[max(0, v) % chatPal.length];
}

void chatOpen() {
  chatOn = true;
  chatScroll = 0; chatWho = ""; chatBig = null;
  if (js != null) { String v = js.pref("chatview"); chatView = v.equals("1") ? 1 : v.equals("2") ? 2 : v.equals("3") ? 3 : 0; }
  chatPolled = -10000;
  chatPoll();
}

void chatClose() {
  chatOn = false;
  peopleGlobe = false;
  selApp = null;
  appSig = "";                       // APPify refills with apps
}

void chatPoll() {
  if (js == null || millis() - chatPolled < 1500) return;
  chatPolled = millis();
  String s = js.chatList();
  if (s == null || s.equals(chatRaw)) return;
  chatRaw = s;
  chatMsgs = new ArrayList();
  String[] ls = split(s, '\n');
  for (int i = 0; i < ls.length; i++) {
    String[] f = split(ls[i], '\t');
    if (f.length < 6) continue;
    ChatMsg m = new ChatMsg();
    m.mine = f[0].equals("1"); m.name = f[1]; m.key = f[2]; m.age = int(chatNum(f[3])); m.route = f[4]; m.text = f[5];
    chatMsgs.add(m);
  }
}

float chatNum(String s) {
  float v = 0;
  for (int i = 0; i < s.length(); i++) { char c = s.charAt(i); if (c < '0' || c > '9') break; v = v * 10 + (c - '0'); }
  return v;
}

String chatTime(int s) {
  if (s < 60) return "now";
  if (s < 3600) return (s / 60) + " min";
  if (s < 86400) return (s / 3600) + " h";
  return (s / 86400) + " d";
}

String chatMark(String r) {
  return r.equals("Bluetooth") ? "BT" : r.equals("Wi-Fi") ? "WI-FI" : r.equals("Internet") ? "NET" : r.equals("Light") ? "LIGHT" : r.toUpperCase();
}

String chatNameOf(String key) {
  for (int i = chatMsgs.size() - 1; i >= 0; i--) { ChatMsg m = (ChatMsg) chatMsgs.get(i); if (!m.mine && m.key.equals(key)) return m.name; }
  return "them";
}

ArrayList chatPeople() {            // key ids, newest talker first
  ArrayList out = new ArrayList();
  for (int i = chatMsgs.size() - 1; i >= 0; i--) {
    ChatMsg m = (ChatMsg) chatMsgs.get(i);
    if (!m.mine && !out.contains(m.key)) out.add(m.key);
  }
  return out;
}

int chatCount(String key) {
  int n = 0;
  for (int i = 0; i < chatMsgs.size(); i++) { ChatMsg m = (ChatMsg) chatMsgs.get(i); if (!m.mine && m.key.equals(key)) n++; }
  return n;
}

ChatMsg chatLastFrom(String key) {
  for (int i = chatMsgs.size() - 1; i >= 0; i--) { ChatMsg m = (ChatMsg) chatMsgs.get(i); if (!m.mine && m.key.equals(key)) return m; }
  return null;
}

ArrayList chatShown() {
  if (chatWho.length() == 0) return chatMsgs;
  ArrayList out = new ArrayList();
  for (int i = 0; i < chatMsgs.size(); i++) { ChatMsg m = (ChatMsg) chatMsgs.get(i); if (m.mine || m.key.equals(chatWho)) out.add(m); }
  return out;
}

// a person's tile for the globe: their key colours as stripes, their first letter on top
PImage chatTile(String key, String name) {
  PGraphics g = createGraphics(128, 128);
  g.beginDraw();
  g.noStroke();
  for (int s = 0; s < 6; s++) { g.fill(chatCol(key, s)); g.rect(0, s * 128 / 6.0, 128, 128 / 6.0 + 1); }
  g.fill(7, 11, 22, 170);
  g.ellipse(64, 64, 84, 84);
  g.fill(255);
  g.textAlign(CENTER, CENTER);
  g.textSize(54);
  g.text(name.length() > 0 ? name.substring(0, 1).toUpperCase() : "?", 64, 60);
  g.endDraw();
  return g.get();
}

// ------------------------------------------------------------------ layout
float chTop() { return 30 * ck; }
float chPillY() { return chTop() + 62 * ck; }
float chChipsY() { return chPillY() + 56 * ck; }
float chBodyY() { return chChipsY() + 58 * ck; }
float chWriteY() { return height - 86 * ck; }
float chBodyB() { return chWriteY() - 14 * ck; }
float chConvY() { return height * 0.62; }      // Orbit: the conversation under the globe
float chGlobeDY() { return 112 * ck; }          // Orbit: APPify's globe moved down, clear of the pills

// the film: everything above y is dark, then a short fade, so messages come out of the darkness like a tape
void chatFilm(float y, float fadeH) {
  noStroke();
  fill(#070B16); rect(0, 0, width, y);
  for (int i = 0; i < 24; i++) { fill(7, 11, 22, 255 * (1 - i / 24.0)); rect(0, y + i * fadeH / 24, width, fadeH / 24 + 1); }
}

void drawChat() {
  ck = min(width / 430.0, height / 900.0);
  chatPoll();
  chatHits = new ArrayList();
  chatHitMsg = new ArrayList();
  peopleGlobe = chatView == 0;
  if (chatView == 0) {
    background(#070B16);
    pushMatrix();
    translate(0, chGlobeDY());
    drawAppify();                                       // APPify's own globe, people as the tiles
    popMatrix();
    fill(#070B16); rect(0, chConvY(), width, height);
    chatBubbles(16 * ck, chConvY(), width - 32 * ck, chBodyB(), chatShown(), 1);
    fill(#070B16); rect(0, chConvY() - 40 * ck, width, 40 * ck);   // the tape comes out from under the globe
    for (int i = 0; i < 16; i++) { fill(7, 11, 22, 255 * (1 - i / 16.0)); rect(0, chConvY() + i * 3 * ck, width, 3 * ck + 1); }
    if (selApp == null) drawChatHeader(false);
  } else {
    background(#070B16);
    float z = chatZ;
    if (chatMsgs.size() == 0) { fill(#8A93A6); textAlign(CENTER, CENTER); textSizeQ(18 * ck); text("No messages yet. Say hello.", width / 2, (chBodyY() + chBodyB()) / 2); }
    else if (chatView == 1) drawRiver(z);
    else if (chatView == 2) drawNotes(z);
    else drawChatD(z);
    chatFilm(chatView == 3 ? chChipsY() - 6 * ck : chBodyY() - 8 * ck, 46 * ck);   // nothing runs over the pills
    if (chatView == 3) drawChatDContacts();
    drawChatHeader(chatView != 3);                       // Chat has its own people on the left
  }
  // the yellow pill
  float pad = 18 * ck, by = chWriteY();
  fill(#F5B942); rrect(pad, by, width - 2 * pad, 60 * ck, 30 * ck);
  fill(#070B16); textAlign(CENTER, CENTER); textSizeQ(19 * ck);
  boldText(chatWho.length() > 0 ? "Write to " + chatNameOf(chatWho) : "Write a message", width / 2, by + 29 * ck);
  if (chatBig != null) drawChatBig();
  textAlign(LEFT, BASELINE);
}

void drawChatHeader(boolean chips) {
  float pad = 18 * ck;
  fill(#E8EEFA); textAlign(LEFT, TOP); textSizeQ(28 * ck);
  boldText("CHATNOTE", pad, chTop());
  fill(#131C31); ellipse(width - pad - 22 * ck, chTop() + 18 * ck, 44 * ck, 44 * ck);
  stroke(#E8EEFA); strokeWeight(2.4 * ck);
  float cx = width - pad - 22 * ck, cy = chTop() + 18 * ck, k = 8 * ck;
  line(cx - k, cy - k, cx + k, cy + k); line(cx - k, cy + k, cx + k, cy - k); noStroke();
  String[] lb = { "Orbit", "River", "Notes", "Chat" };
  float pw = width - 2 * pad, ph = 44 * ck, py = chPillY(), sw = pw / 4;
  fill(#131C31); rrect(pad, py, pw, ph, ph / 2);
  for (int i = 0; i < 4; i++) {
    if (i == chatView) { fill(#4DA3FF); rrect(pad + i * sw + 3 * ck, py + 3 * ck, sw - 6 * ck, ph - 6 * ck, (ph - 6 * ck) / 2); }
    fill(i == chatView ? #070B16 : #C6CEDF); textAlign(CENTER, CENTER); textSizeQ(16 * ck);
    boldText(lb[i], pad + i * sw + sw / 2, py + ph / 2 - 1 * ck);
  }
  if (chips) chatChips(chChipsY());
}

// people as colour chips: tap one to pick that person (it pops), "All" for everyone
void chatChips(float y) {
  ArrayList ps = chatPeople();
  float x = 18 * ck, h = 42 * ck;
  textSizeQ(15 * ck);
  for (int i = -1; i < ps.size(); i++) {
    String key = i < 0 ? "" : (String) ps.get(i);
    String nm = i < 0 ? "All" : chatNameOf(key);
    if (nm.length() > 12) nm = nm.substring(0, 11) + "…";
    boolean on = chatWho.equals(key);
    float w = textWidth(nm) + (i < 0 ? 30 : 44) * ck, yy = on ? y - 3 * ck : y, hh = on ? h + 6 * ck : h;
    if (x + w > width - 10 * ck) break;
    fill(on ? #1E3A66 : #131C31); rrect(x, yy, w, hh, hh / 2);
    if (i >= 0) for (int s = 0; s < 6; s++) { fill(chatCol(key, s)); rect(x + 14 * ck + (s % 3) * 6 * ck, yy + hh / 2 - 7 * ck + floor(s / 3) * 8 * ck, 5 * ck, 6 * ck); }
    if (on) { noFill(); stroke(i < 0 ? #4DA3FF : chatCol(key, 0)); strokeWeight(2 * ck); rrectLine(x, yy, w, hh, hh / 2); noStroke(); }
    fill(on ? #FFFFFF : #C6CEDF); textAlign(LEFT, CENTER);
    text(nm, x + (i < 0 ? 15 : 36) * ck, yy + hh / 2 - 1 * ck);
    chatHits.add(new float[] { x, yy, w, hh, 0, i });
    x += w + 8 * ck;
  }
}

// ------------------------------------------------------------------ River
void drawRiver(float z) {
  ArrayList ms = chatShown();
  float s = ck * z, mid = (chBodyY() + chBodyB()) / 2, step = 150 * s, tw = 200 * s, th = 100 * s;
  float x0 = width - 30 * ck - tw - (ms.size() - 1) * step + chatScroll;
  stroke(#22304D); strokeWeight(2 * ck); line(0, mid, width, mid); noStroke();
  for (int i = 0; i < ms.size(); i++) {
    ChatMsg m = (ChatMsg) ms.get(i);
    float x = x0 + i * step;
    if (x > width || x + tw < 0) continue;
    float y = m.mine ? mid + 24 * s : mid - 24 * s - th;
    color c = chatCol(m.key, 0);
    fill(c); ellipse(x + 14 * s, mid, 9 * s, 9 * s);
    stroke(#22304D); strokeWeight(1.2 * ck); line(x + 14 * s, mid, x + 14 * s, m.mine ? y : y + th); noStroke();
    fill(red(c) * 0.22, green(c) * 0.22, blue(c) * 0.22 + 14); rrect(x, y, tw, th, 12 * s);
    fill(c); rect(x, y + 12 * s, 4 * s, th - 24 * s);
    fill(#8A93A6); textAlign(LEFT, TOP); textSizeQ(13 * s);
    text((m.mine ? "You" : m.name) + " · " + chatMark(m.route) + " · " + chatTime(m.age), x + 14 * s, y + 10 * s);
    fill(#E8EEFA); textSizeQ(16 * s);
    text(m.text, x + 14 * s, y + 32 * s, tw - 24 * s, th - 38 * s);
    chatHitMsg.add(m); chatHits.add(new float[] { x, y, tw, th, 1, chatHitMsg.size() - 1 });
  }
  fill(#8A93A6); textAlign(CENTER, TOP); textSizeQ(13 * ck);
  text("drag through time · pinch to zoom · theirs above, yours below", width / 2, chBodyY() - 4 * ck);
}

// ------------------------------------------------------------------ Notes
void drawNotes(float z) {
  ArrayList ms = chatShown();
  float s = ck * z, x = 18 * ck, w = width - 36 * ck, nh = 118 * s, gap = 12 * s;
  float total = ms.size() * (nh + gap), top = chBodyY();
  float y = (total < chBodyB() - top ? top + total - nh - gap : chBodyB() - nh) + chatScroll;
  for (int i = ms.size() - 1; i >= 0; i--) {
    ChatMsg m = (ChatMsg) ms.get(i);
    float nx = m.mine ? x + 40 * ck : x, nw = w - 40 * ck;
    if (y + nh > top && y < chBodyB()) {
      fill(#0D1424); rrect(nx, y, nw, nh, 12 * s);
      for (int k = 0; k < 6; k++) { fill(chatCol(m.key, k)); rect(nx + k * nw / 6, y, nw / 6 + 1, 8 * s); }
      fill(#E8EEFA); textAlign(LEFT, TOP); textSizeQ(17 * s);
      text(m.text, nx + 14 * s, y + 20 * s, nw - 28 * s, nh - 52 * s);
      fill(#8A93A6); textSizeQ(13 * s);
      text("postmark · " + chatMark(m.route) + " · " + chatTime(m.age) + " · " + (m.mine ? "you" : m.name + " · sealed ✓"), nx + 14 * s, y + nh - 26 * s);
      chatHitMsg.add(m); chatHits.add(new float[] { nx, y, nw, nh, 1, chatHitMsg.size() - 1 });
    }
    y -= nh + gap;
  }
}

// ------------------------------------------------------------------ Chat (traditional): contacts left, history right
void drawChatD(float z) {
  float lw = width * 0.30;
  chatBubbles(lw + 10 * ck, chChipsY() - 6 * ck, width - lw - 20 * ck, chBodyB(), chatShown(), z);
}

void drawChatDContacts() {
  ArrayList ps = chatPeople();
  float lw = width * 0.30, top = chChipsY();
  fill(#0D1424); rect(0, top, lw, chBodyB() - top);
  float y = top + 8 * ck;
  for (int i = -1; i < ps.size(); i++) {
    String key = i < 0 ? "" : (String) ps.get(i);
    boolean on = chatWho.equals(key);
    float h = 58 * ck;
    if (y + h > chBodyB()) break;
    if (on) { fill(#1E3A66); rect(0, y, lw, h); }
    if (i >= 0) for (int s = 0; s < 6; s++) { fill(chatCol(key, s)); rect(10 * ck, y + 10 * ck + s * 6.3 * ck, 8 * ck, 5 * ck); }
    fill(#E8EEFA); textAlign(LEFT, TOP); textSizeQ(15 * ck);
    String nm = i < 0 ? "Everyone" : chatNameOf(key);
    text(nm.length() > 11 ? nm.substring(0, 10) + "…" : nm, 26 * ck, y + 10 * ck);
    if (i >= 0) { ChatMsg l = chatLastFrom(key); fill(#8A93A6); textSizeQ(12 * ck); if (l != null) text(l.text.length() > 12 ? l.text.substring(0, 11) + "…" : l.text, 26 * ck, y + 32 * ck); }
    chatHits.add(new float[] { 0, y, lw, h, 0, i });
    y += h + 2 * ck;
  }
}

// bubbles from the bottom up: theirs left, yours right (Orbit's conversation and the Chat view)
void chatBubbles(float x, float top, float w, float bottom, ArrayList ms, float z) {
  float s = ck * z, y = bottom + chatScroll;
  for (int i = ms.size() - 1; i >= 0; i--) {
    ChatMsg m = (ChatMsg) ms.get(i);
    textSizeQ(16 * s);
    float maxW = w * 0.78, tw = min(maxW - 24 * s, textWidth(m.text));
    int lines = max(1, ceil(textWidth(m.text) / max(1, maxW - 24 * s)));
    float bw = max(tw, 120 * s) + 24 * s, bh = lines * 21 * s + 40 * s;
    y -= bh + 8 * s;
    if (y + bh < top) break;
    if (y > bottom) continue;
    float bx = m.mine ? x + w - bw : x;
    fill(m.mine ? #1E3A66 : #131C31); rrect(bx, y, bw, bh, 14 * s);
    for (int k = 0; k < 6; k++) { fill(chatCol(m.key, k)); rect(bx + 12 * s + k * 7 * s, y + 8 * s, 6 * s, 4 * s); }
    fill(#E8EEFA); textAlign(LEFT, TOP); textSizeQ(16 * s);
    text(m.text, bx + 12 * s, y + 16 * s, bw - 20 * s, bh - 30 * s);
    fill(#8A93A6); textSizeQ(11 * s);
    text((m.mine ? "you" : m.name) + " · " + chatMark(m.route) + " · " + chatTime(m.age) + (m.mine ? "" : " ✓"), bx + 12 * s, y + bh - 17 * s);
    chatHitMsg.add(m); chatHits.add(new float[] { bx, y, bw, bh, 1, chatHitMsg.size() - 1 });
  }
}

void drawChatBig() {
  fill(3, 5, 10, 220); rect(0, 0, width, height);
  ChatMsg m = chatBig;
  float x = 24 * ck, w = width - 48 * ck, y = height * 0.22, h = height * 0.5;
  fill(#0D1424); rrect(x, y, w, h, 20 * ck);
  for (int k = 0; k < 6; k++) { fill(chatCol(m.key, k)); rect(x + k * w / 6, y, w / 6 + 1, 12 * ck); }
  fill(#8A93A6); textAlign(LEFT, TOP); textSizeQ(16 * ck);
  text((m.mine ? "You" : m.name + " · sealed ✓") + " · " + chatMark(m.route) + " · " + chatTime(m.age), x + 22 * ck, y + 30 * ck);
  fill(#FFFFFF); textSizeQ(30 * ck);
  text(m.text, x + 22 * ck, y + 70 * ck, w - 44 * ck, h - 100 * ck);
  fill(#8A93A6); textAlign(CENTER, TOP); textSizeQ(14 * ck);
  text("tap to close", width / 2, y + h + 14 * ck);
}

// ------------------------------------------------------------------ Orbit: APPify's globe with people (called from Appify.pde)
void peopleRelease(float mx, float my, boolean wasDrag) {
  if (wasDrag) {
    AppIcon a = appAt(mx, my);
    if (a == null) { selApp = null; return; }
    String key = a.pkg.substring(5);
    if (a == selApp) { chatWho = key; if (js != null) js.chatWrite(); return; }
    chooseApp(a);
    chatWho = key;
    chatScroll = 0;
    return;
  }
  if (selApp != null && overInfo(mx, my)) {
    int bi = infoBtnAt(mx, my);
    String key = selApp.pkg.substring(5);
    if (bi == 0) { if (js != null) js.chatClear(key); chatPolled = -10000; selApp = null; chatWho = ""; appSig = ""; }
    else if (bi == 1) { selApp = null; chatWho = ""; }
    else if (bi == 2) { chatWho = key; if (js != null) js.chatWrite(); }
    return;
  }
  selApp = null;
  chatWho = "";
}

// ------------------------------------------------------------------ touch
void chatPress(float mx, float my) {
  chatPX = mx; chatPY = my; chatLX = mx; chatLY = my; chatMoved = false;
  chatGlobeDrag = chatView == 0 && chatBig == null && my < chConvY() - 10 * ck && (selApp != null || my > chPillY() + 50 * ck);
  if (chatGlobeDrag) appifyPressed(mx, my - chGlobeDY());
}

void chatDrag(float mx, float my) {
  if (abs(mx - chatPX) > 12 * ck || abs(my - chatPY) > 12 * ck) chatMoved = true;
  if (chatGlobeDrag) { appifyDragged(mx, my - chGlobeDY()); return; }
  if (chatView == 1) chatScroll += mx - chatLX;
  else chatScroll = max(0, chatScroll + my - chatLY);
  chatLX = mx; chatLY = my;
}

void chatRelease(float mx, float my) {
  if (chatBig != null) { if (!chatMoved) chatBig = null; return; }
  if (chatGlobeDrag) { appifyReleased(mx, my - chGlobeDY()); return; }
  if (chatMoved) return;
  float pad = 18 * ck;
  if (my > chWriteY()) { if (js != null) js.chatWrite(); return; }
  if (dist(mx, my, width - pad - 22 * ck, chTop() + 18 * ck) < 34 * ck) { chatClose(); return; }
  float py = chPillY(), ph = 44 * ck;
  if (my > py && my < py + ph && mx > pad && mx < width - pad) {
    int v = constrain(floor((mx - pad) / ((width - 2 * pad) / 4)), 0, 3);
    if (v != chatView) { chatView = v; chatScroll = 0; selApp = null; if (js != null) js.setPref("chatview", "" + v); }
    return;
  }
  for (int i = chatHits.size() - 1; i >= 0; i--) {
    float[] r = (float[]) chatHits.get(i);
    if (mx < r[0] || mx > r[0] + r[2] || my < r[1] || my > r[1] + r[3]) continue;
    if (r[4] == 0) {
      ArrayList ps = chatPeople();
      int k = int(r[5]);
      chatWho = k < 0 ? "" : (String) ps.get(k);
      chatScroll = 0;
    } else chatBig = (ChatMsg) chatHitMsg.get(int(r[5]));
    return;
  }
}

void chatPinch(float ratio) { if (chatView != 0) chatZ = constrain(chatZ * ratio, 0.6, 2.6); }
