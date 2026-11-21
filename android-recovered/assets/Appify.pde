// Appify.pde — APPify: the apps your notifications come from, as icons on a glass ball.
// Touch an icon: the ball turns it to face you, its name shows over it, and the panel at the top (between
// ANA and Live) shows the app: name, category, counts, its latest notification, and OPEN. Touch the icon
// again, or OPEN, to open the app. Touch anywhere else to close the panel.
// The latest-notification card at the bottom stays there all the time.
// The three rings: Apps opens a list of the apps on the ball (busiest first); Categories steps the ball through
// one category at a time and back to All; Last Received turns the ball to the app that sent the newest
// notification. Back to the default view: tap APPify in the bar again (or each one's own close).
// Drag the ball to spin it; flick it and it keeps turning.
// PICKED / ALL / SELECTED at the top chooses which apps go on the ball:
//   PICKED    the apps ticked in Settings
//   ALL       every app that has sent a notification
//   SELECTED  the apps of the cards selected in Archive
//   ACTIVE    the apps used today, most screen time first (needs "Usage access", once, in Settings)
// The app panel has CLEAR (two toggles: its notifications from the shade, and closing the app as swiping it away does), STOP (its App info page, where Android's
// own Force stop is: Android doesn't let an app close other apps itself) and OPEN.
//
// The layout follows the APPify concept image (852 x 1846 px): every position in this tab is
// in that image's pixels, scaled by ak to this screen (drawn at 100% device pixels).
// Getting an app's icon and opening it is Java (Bridge: appIcon, appLabel, appCategory, launchApp).

final int A_PICKED = 0, A_ALL = 1, A_SELECTED = 2, A_ACTIVE = 3;
boolean appSpin = false;       // the finger went down somewhere on APPify: a drag turns the globe
boolean peopleGlobe = false;   // CHATNOTE Orbit (Chat.pde): this same globe, people as the tiles
int appMode = A_PICKED;
String[] appModeName = { "PICKED", "ALL", "SELECTED", "ACTIVE", "FIND" };
final int A_FIND = 4;          // FIND (experimental): type any app name, OPEN looks it up in the Play Store
boolean usageNeeded = false;            // ACTIVE without Usage access

ArrayList appCache = new ArrayList();   // every AppIcon made so far (icons are kept)
ArrayList apps = new ArrayList();       // the ones on the ball now
ArrayList appsAll = new ArrayList();    // the same before the category filter
String catFilter = "";                  // "" = all categories
boolean showList = false;               // the apps list (from the Apps ring)
float listScrollA = 0;
boolean listDragA = false;
String appSig = "";
int[] order = new int[0];               // draw order, back to front

float ak = 1, aX0 = 0, aY0 = 0;         // concept-image pixels -> screen
PGraphics appBg;
PImage appBgImg;                        // the parts that never move, drawn once per size

// ball
float ballR = 218, bCX = 430, bCY = 490; // in image pixels
float[] rot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
float spinVX = 0, spinVY = 0.0035;      // rad per frame at 60 fps; it idles slowly round
boolean appDrag = false;
int appLastMs = 0;
float appPressX, appPressY, appLastX, appLastY;
boolean appMoved = false;
String appMsg = "";
int appMsgAt = -10000;
AppIcon selApp = null;                  // the app touched last: its card shows at the bottom
int selAt = -10000;

class AppIcon {
  String pkg;
  String label = "", cat = "";
  boolean asked = false;      // icon asked for
  boolean infoAsked = false; // name + category asked for
  PImage img = null;
  boolean ready = false;
  color glow = #4DA3FF;
  float px, py, pz;          // place on the ball (unit sphere, ball space)
  float t1x, t1y, t1z, t2x, t2y, t2z;   // the tile's right and down directions there
  float sx, sy, sz;          // this frame: screen centre and depth (-1 back .. 1 front)
  float ax_, ay_, bx_, by_;  // this frame: the tile's projected right / down vectors
  int n = 0;                 // notifications (ACTIVE: seconds used today)
  int useS = 0, agoS = 0;    // ACTIVE: seconds in the foreground today, seconds since last used
  String status = "installed";   // EFINOTE: active / dormant / archived / uninstalled / installed
  int statusAt = -1;
  int flashAt = -10000;
  AppIcon(String pkg) { this.pkg = pkg; }
}

float AX(float x) { return aX0 + x * ak; }
float AY(float y) { return aY0 + y * ak; }

void appifyLayout() {
  ak = min(width / 852.0, (barY - 8 * u) / 1500.0);
  aX0 = (width - 852 * ak) * 0.5;
  aY0 = max(-84 * ak, barY - 10 * u - 1572 * ak);   // the card ends just above the bar, as in the concept
  buildAppBg();
}

// ---------------------------------------------------------------- which apps
void appifyRefresh() {
  int nSel = selectedCount();
  String sig = appMode + "/" + entries.size() + "/" + nSel + "/" + watch.size() + "/" + filterOn + "/" + catFilter;
  if (appMode == A_ACTIVE) sig += "/" + floor(millis() / (usageNeeded ? 2000.0 : 20000.0));   // usage moves on its own
  if (peopleGlobe) sig = "P/" + chatRaw;
  if (appMode == A_FIND && !peopleGlobe && js != null) sig = "F/" + js.pref("finds");
  if (sig.equals(appSig)) return;
  appSig = sig;

  ArrayList pk = new ArrayList();
  int[] cnt = new int[40];
  int[] ago = new int[40];
  usageNeeded = false;
  if (appMode == A_ACTIVE && !peopleGlobe) {
    if (js != null && js.usageOk()) {
      String[] lines = split(js.usageToday(), "\n");
      for (int i = 0; i < lines.length && pk.size() < 40; i++) {
        String[] f = split(lines[i], "\t");
        if (f.length < 3 || f[0].length() == 0) continue;
        cnt[pk.size()] = int(f[1]);
        ago[pk.size()] = int(f[2]);
        pk.add(f[0]);
      }
    }
    else usageNeeded = (js != null);
  }
  for (int i = 0; i < entries.size() && appMode != A_ACTIVE && appMode != A_FIND && !peopleGlobe; i++) {
    Entry e = (Entry) entries.get(i);
    if (e.src.equals("SYS") || e.src.equals("MANUAL")) continue;
    if (e.pkg.equals("manual") || e.pkg.startsWith("com.novera.ana")) continue;
    boolean take;
    if (appMode == A_PICKED) take = isWatched(e.watchKey());
    else if (appMode == A_SELECTED) take = e.selected;
    else take = true;
    if (!take) continue;
    int at = -1;
    for (int j = 0; j < pk.size(); j++) {
      String s = (String) pk.get(j);
      if (s.equals(e.pkg)) at = j;
    }
    if (at < 0) {
      if (pk.size() >= 40) continue;
      cnt[pk.size()] = 1;
      pk.add(e.pkg);
    }
    else cnt[at]++;
  }

  if (appMode == A_FIND && !peopleGlobe && js != null) {   // FIND: the names typed in
    String[] fs = split(js.pref("finds"), '\n');
    for (int i = 0; i < fs.length && pk.size() < 40; i++) if (trim(fs[i]).length() > 0) { cnt[pk.size()] = 1; pk.add("find:" + trim(fs[i])); }
  }
  if (peopleGlobe) {                                // CHATNOTE: the people who wrote, newest first
    ArrayList ps = chatPeople();
    for (int i = 0; i < ps.size() && pk.size() < 40; i++) { cnt[pk.size()] = chatCount((String) ps.get(i)); pk.add("chat:" + ps.get(i)); }
  }
  // every app for this source, with its name and category (cheap; icons come later)
  appsAll.clear();
  for (int i = 0; i < pk.size(); i++) {
    AppIcon a = appFor((String) pk.get(i));
    a.n = cnt[i];
    a.useS = appMode == A_ACTIVE ? cnt[i] : 0;
    a.agoS = appMode == A_ACTIVE ? ago[i] : 0;
    appInfo(a);
    appsAll.add(a);
  }
  // the category filter, if one is on
  ArrayList onBall = new ArrayList();
  for (int i = 0; i < appsAll.size(); i++) {
    AppIcon a = (AppIcon) appsAll.get(i);
    if (peopleGlobe || catFilter.length() == 0 || a.cat.equals(catFilter)) onBall.add(a);
  }
  if (onBall.size() == 0 && catFilter.length() > 0) {    // that category has gone: back to all
    catFilter = "";
    for (int i = 0; i < appsAll.size(); i++) onBall.add(appsAll.get(i));
  }

  apps.clear();
  int n = onBall.size();
  placeAxis = null;
  placeSetup(n);                                   // FIND / people: the newest tile goes where Settings says
  for (int i = 0; i < n; i++) {
    AppIcon a = (AppIcon) onBall.get(i);
    // even spread over the ball (Fibonacci sphere); the first (busiest-recent) app faces you
    float[] sp = tileSpot(i, n);
    a.px = sp[0]; a.py = sp[1]; a.pz = sp[2];
    // tile directions: right = up x p, down = p x right
    float rx = a.pz, ry = 0, rz = -a.px;
    float rl = sqrt(rx * rx + rz * rz);
    if (rl < 0.001) { rx = 1; rz = 0; rl = 1; }
    a.t1x = rx / rl; a.t1y = ry; a.t1z = rz / rl;
    a.t2x = a.py * a.t1z - a.pz * a.t1y;
    a.t2y = a.pz * a.t1x - a.px * a.t1z;
    a.t2z = a.px * a.t1y - a.py * a.t1x;
    apps.add(a);
  }
  order = new int[apps.size()];
  for (int i = 0; i < order.length; i++) order[i] = i;
  if (selApp != null && apps.indexOf(selApp) < 0) selApp = null;
}

AppIcon appFor(String pkg) {
  for (int i = 0; i < appCache.size(); i++) {
    AppIcon a = (AppIcon) appCache.get(i);
    if (a.pkg.equals(pkg)) return a;
  }
  AppIcon a = new AppIcon(pkg);
  appCache.add(a);
  return a;
}

// icons and names come from the phone, one or two per frame, and arrive in the background
// Settings: where a new tile goes (FIND and CHATNOTE people: the newest is tile 0)
int tilePlace = 1;                     // 0 random, 1 front, 2 right, 3 left, 4 top, 5 bottom
String[] tilePlaceName = { "Random", "Front", "Right", "Left", "Top", "Bottom" };
float[] placeAxis = null;              // this refill's turn (axis x, y, z, angle), or null
int placeN = -1;

// a tile's place on the ball (unit sphere, ball space): APPify's spread, turned for the newest tile's spot
float[] tileSpot(int i, int n) {
  float y = n == 1 ? 0 : 1 - 2 * (i + 0.5) / n;
  float r = sqrt(max(0, 1 - y * y));
  float phi = i * 2.39996;
  if (n > 1 && n <= 8 && (peopleGlobe || appMode == 4 || (onIOS && appMode == A_ACTIVE))) {   // FIND / people: a few tiles, none behind another
    y = i % 2 == 0 ? 0.32 : -0.32;
    r = sqrt(1 - y * y);
    phi = TWO_PI * i / n;
  }
  float px = sin(phi) * r;
  float py = y * 0.92;
  float pz = cos(phi) * r;
  float l = sqrt(px * px + py * py + pz * pz);
  px /= l; py /= l; pz /= l;
  float[] p = { px, py, pz };
  if (placeAxis != null) p = turnBy(p, placeAxis);
  return p;
}

boolean placeMode() { return peopleGlobe || appMode == 4 || (onIOS && appMode == A_ACTIVE); }

// before a refill: the turn that takes tile 0 to the chosen spot on screen (rot's inverse = its transpose)
void placeSetup(int n) {
  placeAxis = null;
  if (!placeMode() || n < 1) return;
  float[] d;
  if (tilePlace == 0) { float t = random(TWO_PI), u = random(-0.7, 0.7); d = new float[] { cos(t) * sqrt(1 - u * u), u, abs(sin(t)) * sqrt(1 - u * u) + 0.2 }; }
  else if (tilePlace == 2) d = new float[] { 0.85, 0, 0.53 };
  else if (tilePlace == 3) d = new float[] { -0.85, 0, 0.53 };
  else if (tilePlace == 4) d = new float[] { 0, -0.75, 0.66 };
  else if (tilePlace == 5) d = new float[] { 0, 0.75, 0.66 };
  else d = new float[] { 0, 0, 1 };
  float[] t = { rot[0] * d[0] + rot[3] * d[1] + rot[6] * d[2], rot[1] * d[0] + rot[4] * d[1] + rot[7] * d[2], rot[2] * d[0] + rot[5] * d[1] + rot[8] * d[2] };
  float tl = sqrt(t[0] * t[0] + t[1] * t[1] + t[2] * t[2]);
  t[0] /= tl; t[1] /= tl; t[2] /= tl;
  float[] p0 = tileSpot(0, n);
  float ax = p0[1] * t[2] - p0[2] * t[1], ay = p0[2] * t[0] - p0[0] * t[2], az = p0[0] * t[1] - p0[1] * t[0];
  float s = sqrt(ax * ax + ay * ay + az * az), c = p0[0] * t[0] + p0[1] * t[1] + p0[2] * t[2];
  if (s < 0.0001) { if (c < 0) placeAxis = new float[] { 0, 1, 0, PI }; return; }
  placeAxis = new float[] { ax / s, ay / s, az / s, atan2(s, c) };
}

float[] turnBy(float[] v, float[] q) {   // Rodrigues: v turned about axis q[0..2] by q[3]
  float c = cos(q[3]), s = sin(q[3]);
  float d = q[0] * v[0] + q[1] * v[1] + q[2] * v[2];
  float cx = q[1] * v[2] - q[2] * v[1], cy = q[2] * v[0] - q[0] * v[2], cz = q[0] * v[1] - q[1] * v[0];
  return new float[] { v[0] * c + cx * s + q[0] * d * (1 - c), v[1] * c + cy * s + q[1] * d * (1 - c), v[2] * c + cz * s + q[2] * d * (1 - c) };
}

void appifyLoadIcons() {
  int asked = 0;
  for (int i = 0; i < apps.size() && asked < 2; i++) {
    AppIcon a = (AppIcon) apps.get(i);
    if (!a.asked) {
      a.asked = true;
      asked++;
      appInfo(a);
      if (a.pkg.startsWith("chat:")) a.img = chatTile(a.pkg.substring(5), a.label);   // CHATNOTE: a person's colours
      else if (js != null) {
        String d = js.appIcon(a.pkg);
        if (d.length() > 0) a.img = loadImage(d);
      }
    }
    if (!a.ready && a.img != null && a.img.width > 0) {
      a.ready = true;
      a.glow = averageColour(a.img);
    }
  }
}

void appInfo(AppIcon a) {
  if (a.infoAsked) return;
  a.infoAsked = true;
  if (a.pkg.startsWith("chat:")) { a.label = chatNameOf(a.pkg.substring(5)); a.cat = "CHATNOTE"; return; }
  if (a.pkg.startsWith("find:")) { a.label = a.pkg.substring(5); a.cat = "Play Store"; return; }   // FIND
  if (js != null) {
    a.label = js.appLabel(a.pkg);
    a.cat = js.appCategory(a.pkg);
  }
  if (a.label.length() == 0) a.label = shortName(a.pkg);
}

String shortName(String pkg) {
  String[] parts = split(pkg, ".");
  String s = parts[parts.length - 1];
  if (s.length() <= 2 && parts.length > 1) s = parts[parts.length - 2];
  return s.substring(0, 1).toUpperCase() + s.substring(1);
}

color averageColour(PImage im) {
  im.loadPixels();
  float r = 0, g = 0, b = 0, w = 0;
  for (int i = 0; i < im.pixels.length; i += 7) {
    int p = im.pixels[i];
    float a = ((p >> 24) & 0xff) / 255.0;
    float sat = max(max((p >> 16) & 0xff, (p >> 8) & 0xff), p & 0xff) - min(min((p >> 16) & 0xff, (p >> 8) & 0xff), p & 0xff);
    float k = a * (0.2 + sat / 255.0);           // favour the colourful pixels
    r += ((p >> 16) & 0xff) * k; g += ((p >> 8) & 0xff) * k; b += (p & 0xff) * k; w += k;
  }
  if (w <= 0) return #4DA3FF;
  return color(min(255, r / w * 1.15), min(255, g / w * 1.15), min(255, b / w * 1.15));
}

// a colour for apps without an icon (desktop, or not installed)
color pkgColour(String pkg) {
  int h = pkgHash(pkg);
  colorMode(HSB, 360, 100, 100);
  color c = color(h % 360, 70, 95);
  colorMode(RGB, 255);
  return c;
}

// ---------------------------------------------------------------- rotation
// rot = R(angle about screen axis) * rot
void rotScreen(float ax, float ay) {
  // ax: about the screen's vertical axis (drag sideways), ay: about the horizontal axis (drag up/down)
  float cy = cos(ax), sy = sin(ax), cx = cos(ay), sx = sin(ay);
  // Ry(ax): x' = x cy + z sy ; z' = -x sy + z cy
  // Rx(ay): y' = y cx + z sx ; z' = -y sx + z cx   (front moves down for ay > 0)
  float[] m = rot;
  float[] o = new float[9];
  for (int c = 0; c < 3; c++) {
    float x = m[c], y = m[3 + c], z = m[6 + c];
    float x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
    float y2 = y * cx + z1 * sx, z2 = -y * sx + z1 * cx;
    o[c] = x1; o[3 + c] = y2; o[6 + c] = z2;
  }
  // keep it a clean rotation (re-orthonormalise rows)
  for (int r = 0; r < 3; r++) {
    float l = sqrt(o[r * 3] * o[r * 3] + o[r * 3 + 1] * o[r * 3 + 1] + o[r * 3 + 2] * o[r * 3 + 2]);
    o[r * 3] /= l; o[r * 3 + 1] /= l; o[r * 3 + 2] /= l;
  }
  rot = o;
}

void appifyPhysics() {
  int now = millis();
  float dt = constrain((now - appLastMs) / 16.7, 0, 6);
  appLastMs = now;
  if (!appDrag) {
    rotScreen(spinVX * dt, spinVY * dt);
    spinVX *= pow(0.95, dt);
    spinVY *= pow(0.95, dt);
    // drift back to the slow idle turn (not while an app is chosen: it stays facing you)
    if (selApp == null && abs(spinVX) < 0.0035) spinVX += (0.0035 - spinVX) * 0.02 * dt;
    if (selApp != null) {
      // turn the chosen icon to the front: move it a little toward the centre each frame
      float x = rot[0] * selApp.px + rot[1] * selApp.py + rot[2] * selApp.pz;
      float y = rot[3] * selApp.px + rot[4] * selApp.py + rot[5] * selApp.pz;
      float z = rot[6] * selApp.px + rot[7] * selApp.py + rot[8] * selApp.pz;
      float k = min(1, 0.16 * dt);
      float ax = -atan2(x, max(z, 0.05)) * k, ay = -atan2(y, max(z, 0.05)) * k;
      rotScreen(ax, ay);
      spinVX = 0;
      spinVY = 0;
    }
  }
  float R = ballR * ak;
  for (int i = 0; i < apps.size(); i++) {
    AppIcon a = (AppIcon) apps.get(i);
    float x = rot[0] * a.px + rot[1] * a.py + rot[2] * a.pz;
    float y = rot[3] * a.px + rot[4] * a.py + rot[5] * a.pz;
    float z = rot[6] * a.px + rot[7] * a.py + rot[8] * a.pz;
    float persp = 1 + z * 0.12;                    // front a little larger
    a.sx = AX(bCX) + x * R * 0.76 * persp;
    a.sy = AY(bCY) + y * R * 0.76 * persp;
    a.sz = z;
    a.ax_ = rot[0] * a.t1x + rot[1] * a.t1y + rot[2] * a.t1z;
    a.ay_ = rot[3] * a.t1x + rot[4] * a.t1y + rot[5] * a.t1z;
    a.bx_ = rot[0] * a.t2x + rot[1] * a.t2y + rot[2] * a.t2z;
    a.by_ = rot[3] * a.t2x + rot[4] * a.t2y + rot[5] * a.t2z;
  }
  // back to front
  for (int i = 1; i < order.length; i++) {
    int k = order[i];
    float z = ((AppIcon) apps.get(k)).sz;
    int j = i - 1;
    while (j >= 0 && ((AppIcon) apps.get(order[j])).sz > z) {
      order[j + 1] = order[j];
      j--;
    }
    order[j + 1] = k;
  }
}

// ---------------------------------------------------------------- the still parts, drawn once
void buildAppBg() {
  appBg = createGraphics(width, height, JAVA2D);
  appBg.beginDraw();
  appBg.smooth();
  appBg.background(#05070C);
  appBg.noStroke();
  // deep blue haze round the ball and a warm one to the right
  for (int i = 40; i >= 1; i--) {
    float t = i / 40.0;
    appBg.fill(20, 60, 160, 5);
    appBg.ellipse(AX(430), AY(560), 900 * ak * t, 760 * ak * t);
  }
  for (int i = 24; i >= 1; i--) {
    float t = i / 24.0;
    appBg.fill(150, 90, 30, 3);
    appBg.ellipse(AX(700), AY(560), 420 * ak * t, 300 * ak * t);
  }
  // the light falling from the ball onto the platform
  for (int i = 30; i >= 1; i--) {
    float t = i / 30.0;
    appBg.fill(60, 140, 255, 6);
    appBg.ellipse(AX(430), AY(760), 520 * ak * t, 90 * ak * t);
  }
  // the large faint dish round the count
  appBg.noFill();
  appBg.stroke(40, 70, 130, 90);
  appBg.strokeWeight(1.5 * ak);
  appBg.ellipse(AX(432), AY(866), 800 * ak, 220 * ak);
  appBg.stroke(30, 50, 100, 60);
  appBg.ellipse(AX(432), AY(866), 640 * ak, 170 * ak);
  // platform
  appBg.noStroke();
  appBg.fill(6, 10, 22);
  appBg.ellipse(AX(430), AY(778), 600 * ak, 92 * ak);
  appBg.fill(10, 18, 38);
  appBg.ellipse(AX(430), AY(770), 470 * ak, 62 * ak);
  for (int i = 8; i >= 1; i--) {
    appBg.noFill();
    appBg.stroke(70, 160, 255, 14 + (8 - i) * 6);
    appBg.strokeWeight(i * 2.2 * ak);
    appBg.ellipse(AX(430), AY(770), 470 * ak, 62 * ak);
  }
  appBg.stroke(170, 220, 255, 230);
  appBg.strokeWeight(2.2 * ak);
  appBg.ellipse(AX(430), AY(770), 470 * ak, 62 * ak);
  appBg.stroke(90, 150, 255, 140);
  appBg.strokeWeight(1.4 * ak);
  appBg.ellipse(AX(430), AY(778), 600 * ak, 92 * ak);
  appBg.ellipse(AX(430), AY(772), 340 * ak, 40 * ak);
  // the hot spot under the ball
  appBg.noStroke();
  for (int i = 14; i >= 1; i--) {
    float t = i / 14.0;
    appBg.fill(150, 210, 255, 16);
    appBg.ellipse(AX(430), AY(752), 150 * ak * t, 22 * ak * t);
  }
  appBg.endDraw();
  appBgImg = appBg.get();
}

// ---------------------------------------------------------------- draw
void drawAppify() {
  if (appBg == null || appBg.width != width) appifyLayout();
  appifyRefresh();
  appifyLoadIcons();
  appifyPhysics();

  image(appBgImg, 0, 0);
  if (!peopleGlobe) drawAppHeader();
  drawBubbles();
  drawOrbit(false);
  drawGlassBack();
  for (int i = 0; i < order.length; i++) {
    AppIcon a = (AppIcon) apps.get(order[i]);
    if (a.sz < 0) drawAppTile(a);
  }
  drawGlassMid();
  for (int i = 0; i < order.length; i++) {
    AppIcon a = (AppIcon) apps.get(order[i]);
    if (a.sz >= 0) drawAppTile(a);
  }
  drawGlassFront();
  drawOrbit(true);
  if (selApp != null) drawAppLabel(selApp);
  if (apps.size() == 0) {
    fill(#9AA6C0);
    textAlign(CENTER, CENTER);
    textSizeQ(24 * ak);
    String why = appMode == A_PICKED ? "No picked apps yet\n(Settings)" : appMode == A_SELECTED ? "No cards selected\n(Archive)" : "No notifications yet";
    if (appMode == A_ACTIVE) why = usageNeeded ? "Tap here to allow\nUsage access for ANA" : js == null ? "ACTIVE is phone only" : "No apps used yet today";
    if (peopleGlobe) why = "No one has written yet";
    if (appMode == A_FIND && !peopleGlobe) why = "Tap FIND again\nto look up any app";
    text(why, AX(bCX), AY(bCY));
  }
  if (!peopleGlobe) {                              // CHATNOTE Orbit: the conversation sits here instead
    drawAppCount();
    drawGauges();
    drawFlow();
    drawLatest();
    if (catFilter.length() > 0) drawFilterPill();
    if (showList) drawAppList();
  }
  if (selApp != null) drawAppInfo(selApp);
  if (millis() - appMsgAt < 2500) {
    fill(#F5B942);
    textAlign(CENTER, CENTER);
    textSizeQ(22 * ak);
    text(appMsg, AX(426), AY(1385));
  }
}

void drawAppHeader() {
  // ANA logo + subtitle (the concept's "NOTiFY / Your Digital Memory")
  textAlign(LEFT, BASELINE);
  fill(80, 150, 255, 60);
  textSizeQ(58 * ak);
  text("ANA", AX(60) - 1.5 * ak, AY(143) + 1.5 * ak);
  fill(#F4F7FF);
  text("ANA", AX(60), AY(143));
  text("ANA", AX(60) + 1.4 * ak, AY(143));
  // the subtitle steps aside while the app panel uses the top
  float sub = selApp == null ? 1 : max(0, 1 - (millis() - selAt) / 180.0);
  if (sub > 0) {
    fill(154, 166, 192, 255 * sub);
    textSizeQ(26 * ak);
    text("Notification Compiler", AX(60), AY(182));
  }

  // Live pill
  boolean live = status.equals("CONNECTED") || status.equals("DESKTOP SIM");
  float px = AX(684), py = AY(98), pw = 128 * ak, ph = 56 * ak;
  fill(14, 22, 36, 230);
  rrect(px, py, pw, ph, ph * 0.5);
  stroke(60, 90, 140, 120);
  strokeWeight(1.2 * ak);
  rrectLine(px, py, pw, ph, ph * 0.5);
  noStroke();
  color dot = live ? #22D36B : #FF5A5A;
  for (int i = 6; i >= 1; i--) {
    fill(red(dot), green(dot), blue(dot), 22);
    ellipse(px + 30 * ak, py + ph * 0.5, (10 + i * 4) * ak, (10 + i * 4) * ak);
  }
  fill(dot);
  ellipse(px + 30 * ak, py + ph * 0.5, 16 * ak, 16 * ak);
  fill(#F4F7FF);
  textAlign(LEFT, CENTER);
  textSizeQ(27 * ak);
  text(live ? "Live" : "Off", px + 58 * ak, py + ph * 0.5 - 2 * ak);

  // PICKED / ALL / SELECTED / ACTIVE (they step aside while the app panel is open)
  if (selApp != null) return;
  float cw = 128 * ak, chh = 40 * ak, cy = AY(222), cx0 = AX(426) - cw * 2.5 - 16 * ak;
  textSizeQ(17 * ak);
  textAlign(CENTER, CENTER);
  for (int i = 0; i < 5; i++) {
    float cx = cx0 + i * (cw + 8 * ak);
    boolean on = (i == appMode);
    fill(on ? color(30, 70, 140, 220) : color(14, 22, 36, 200));
    rrect(cx, cy, cw, chh, chh * 0.5);
    stroke(on ? color(90, 170, 255, 220) : color(50, 70, 110, 140));
    strokeWeight(1.2 * ak);
    rrectLine(cx, cy, cw, chh, chh * 0.5);
    noStroke();
    fill(on ? #FFFFFF : #8A93A6);
    text(appModeName[i], cx + cw * 0.5, cy + chh * 0.5 - 1 * ak);
  }
}

int modeAt(float mx, float my) {
  if (selApp != null) return -1;
  float cw = 128 * ak, chh = 40 * ak, cy = AY(222), cx0 = AX(426) - cw * 2.5 - 16 * ak;
  if (my < cy - 6 * ak || my > cy + chh + 6 * ak) return -1;
  for (int i = 0; i < 5; i++) {
    float cx = cx0 + i * (cw + 8 * ak);
    if (mx >= cx && mx <= cx + cw) return i;
  }
  return -1;
}

void drawBubbles() {
  float t = millis() / 1000.0;
  bubble(115, 365 + sin(t * 0.9) * 6, 13);
  bubble(791, 318 + sin(t * 0.7 + 1) * 8, 26);
  bubble(62, 650 + sin(t * 1.1 + 2) * 5, 11);
  bubble(812, 560 + sin(t * 0.8 + 3) * 5, 6);
}

void bubble(float x, float y, float r) {
  noStroke();
  fill(10, 20, 45, 220);
  ellipse(AX(x), AY(y), 2 * r * ak, 2 * r * ak);
  noFill();
  stroke(120, 170, 255, 150);
  strokeWeight(1.3 * ak);
  ellipse(AX(x), AY(y), 2 * r * ak, 2 * r * ak);
  noStroke();
  fill(230, 240, 255, 200);
  ellipse(AX(x - r * 0.35), AY(y - r * 0.4), r * 0.55 * ak, r * 0.4 * ak);
}

// two tilted rings round the ball; the back half is drawn before the ball, the front half after
void drawOrbit(boolean front) {
  float tilt = -0.21;
  ring(430, 528, 392, 112, tilt, front, 4.2, 1.0);
  ring(436, 540, 348, 92, tilt + 0.03, front, 1.6, 0.6);
  ring(430, 610, 372, 44, -0.08, front, 1.1, 0.4);
}

void ring(float cx, float cy, float rx, float ry, float tilt, boolean front, float w, float bright) {
  // Drawn as runs of 6 steps, each one stroke (one colour): a glowing line made of short
  // separate segments shows beads where the see-through segments overlap.
  int N = 120, RUN = 10;
  float ct = cos(tilt), st = sin(tilt);
  float comet = (millis() / 2600.0) % 1.0 * TWO_PI;
  noFill();
  for (int pass = 0; pass < 2; pass++) {
    for (int i0 = 0; i0 < N; i0 += RUN) {
      float tm = TWO_PI * (i0 + RUN * 0.5) / N;
      if ((sin(tm) > 0) != front) continue;
      float k = (cos(tm) + 1) * 0.5;                       // blue on the left, gold on the right
      float r = lerp(60, 255, k), g = lerp(140, 170, k), b = lerp(255, 70, k);
      float d = abs(atan2(sin(tm - comet), cos(tm - comet)));
      float hot = max(0, 1 - d / 1.2);                     // the travelling bright streak
      float al = (0.45 + 0.55 * hot) * bright * (front ? 1.0 : 0.5);
      if (pass == 0) {
        stroke(r, g, b, 50 * al);
        strokeWeight((w * 5 + hot * 10) * ak);
      }
      else {
        stroke(min(255, r + 60), min(255, g + 60), min(255, b + 60), 255 * al);
        strokeWeight((w + hot * 1.5) * ak);
      }
      beginShape();
      for (int i = i0; i <= i0 + RUN; i++) {
        float t = TWO_PI * i / N;
        float ex = cos(t) * rx, ey = sin(t) * ry;
        vertex(AX(cx + ex * ct - ey * st), AY(cy + ex * st + ey * ct));
      }
      endShape();
    }
  }
  noStroke();
}

void drawGlassBack() {
  float cx = AX(bCX), cy = AY(bCY), R = ballR * ak;
  noStroke();
  for (int i = 12; i >= 1; i--) {                         // soft blue body
    float t = i / 12.0;
    fill(20, 50, 120, 10);
    ellipse(cx, cy + R * 0.15 * (1 - t), 2 * R * t, 2 * R * t);
  }
  fill(8, 16, 40, 120);
  ellipse(cx, cy, 2 * R, 2 * R);
}

void drawGlassMid() {
  // the glass between the back icons and the front ones
  float cx = AX(bCX), cy = AY(bCY), R = ballR * ak;
  noStroke();
  fill(14, 30, 72, 120);
  ellipse(cx, cy, 2 * R, 2 * R);
  // faint latitude lines, like the concept's inner reflections
  noFill();
  stroke(120, 170, 255, 26);
  strokeWeight(1.2 * ak);
  ellipse(cx, cy, 2 * R * 0.97, 2 * R * 0.32);
  ellipse(cx, cy - R * 0.45, 2 * R * 0.86, 2 * R * 0.24);
  ellipse(cx, cy + R * 0.45, 2 * R * 0.86, 2 * R * 0.24);
  ellipse(cx, cy, 2 * R * 0.36, 2 * R * 0.97);
  noStroke();
}

void drawGlassFront() {
  float cx = AX(bCX), cy = AY(bCY), R = ballR * ak;
  // rim: bright blue low-left, fading top-right. Drawn in runs of 5 steps, each one stroke,
  // so the see-through glow has no beads where pieces would overlap.
  int N = 90, RUN = 5;
  noFill();
  for (int pass = 0; pass < 2; pass++) {
    for (int i0 = 0; i0 < N; i0 += RUN) {
      float am = TWO_PI * (i0 + RUN * 0.5) / N;
      float k = (cos(am - 2.45) + 1) * 0.5;               // brightest at lower left
      float k2 = (cos(am + 0.9) + 1) * 0.5;               // a second, softer one top right
      float br = max(k * k, 0.35 * k2 * k2);
      if (pass == 0) { stroke(90, 170, 255, 70 * br); strokeWeight((6 + 10 * br) * ak); }
      else { stroke(170, 225, 255, 70 + 185 * br); strokeWeight((1.2 + 1.6 * br) * ak); }
      beginShape();
      for (int i = i0; i <= i0 + RUN; i++) {
        float t = TWO_PI * i / N;
        vertex(cx + cos(t) * R, cy + sin(t) * R);
      }
      endShape();
    }
  }
  // warm reflection on the right (the gold ring lighting the glass)
  noFill();
  for (int i = 0; i < 6; i++) {
    stroke(255, 170, 70, 26);
    strokeWeight((14 - i * 2) * ak);
    arcPath(cx, cy, R * 0.97, -0.55, 0.75);
  }
  stroke(255, 205, 140, 170);
  strokeWeight(2 * ak);
  arcPath(cx, cy, R * 0.985, -0.35, 0.55);
  // inner rim
  noFill();
  stroke(140, 190, 255, 50);
  strokeWeight(1.5 * ak);
  ellipse(cx, cy, 2 * R * 0.93, 2 * R * 0.93);
  // the window reflection top left
  noStroke();
  for (int i = 0; i < 10; i++) {
    fill(255, 255, 255, 9);
    ellipse(cx - R * 0.42, cy - R * 0.55, R * (0.62 - i * 0.04), R * (0.30 - i * 0.02));
  }
  stroke(255, 255, 255, 120);
  strokeWeight(2.4 * ak);
  noFill();
  arcPath(cx, cy, R * 0.88, PI + 0.35, PI + 1.25);
  stroke(255, 255, 255, 50);
  strokeWeight(5 * ak);
  arcPath(cx, cy, R * 0.88, PI + 0.4, PI + 1.15);
  noStroke();
}

void drawAppTile(AppIcon a) {
  float front = (a.sz + 1) * 0.5;                          // 0 back .. 1 front
  float size = 118 * ak * (0.70 + 0.30 * front);
  float fl = millis() - a.flashAt < 450 ? 1 - (millis() - a.flashAt) / 450.0 : 0;
  size *= 1 + fl * 0.25;
  float alpha = a.sz < 0 ? 0.22 + 0.25 * front : 0.55 + 0.45 * front;
  color gc = a.ready ? a.glow : pkgColour(a.pkg);

  // The tile lies on the ball: its right / down directions (a.ax_, a.ay_) / (a.bx_, a.by_) come from the
  // ball's turn. That 2 x 2 matrix is built from rotate + shearX + scale (Processing.js has no 6-number applyMatrix).
  float ma = a.ax_, mb = a.ay_, mc = a.bx_, md = a.by_;
  float th = atan2(mb, ma);
  float scx = sqrt(ma * ma + mb * mb);
  float ct = cos(th), st = sin(th);
  float m12 = mc * ct + md * st;          // R(-th) * M = [[scx, m12], [0, scy]]
  float scy = -mc * st + md * ct;
  if (abs(scy) < 0.03 || scx < 0.03) return;   // edge-on: nothing to see
  pushMatrix();
  translate(a.sx, a.sy);
  rotate(th);
  shearX(atan(m12 / scy));
  scale(scx, scy);
  float h = size * 0.5;
  if (a == selApp) {                                       // chosen: a brighter, pulsing halo
    float pz = 0.5 + 0.5 * sin((millis() - selAt) / 260.0);
    for (int i = 6; i >= 1; i--) {
      fill(red(gc), green(gc), blue(gc), (14 + 10 * pz) * alpha);
      rrect(-h - i * 7 * ak, -h - i * 7 * ak, size + i * 14 * ak, size + i * 14 * ak, (18 + i * 7) * ak);
    }
  }
  if (a.sz > 0) {                                         // glow
    for (int i = 4; i >= 1; i--) {
      fill(red(gc), green(gc), blue(gc), 26 * alpha * front);
      rrect(-h - i * 5 * ak, -h - i * 5 * ak, size + i * 10 * ak, size + i * 10 * ak, (16 + i * 5) * ak);
    }
  }
  fill(16, 28, 58, 210 * alpha);                         // glass tile
  rrect(-h, -h, size, size, 18 * ak);
  stroke(red(gc), green(gc), blue(gc), 150 * alpha);
  strokeWeight(1.6 * ak);
  rrectLine(-h, -h, size, size, 18 * ak);
  noStroke();
  fill(255, 255, 255, 18 * alpha);
  rect(-h + 10 * ak, -h + 3 * ak, size - 20 * ak, size * 0.28);

  float ic = size * 0.74;
  if (a.ready) image(a.img, -ic * 0.5, -ic * 0.5, ic, ic);   // the back ones are dimmed by the glass drawn over them
  else {                                                 // no icon (desktop, or not installed)
    fill(red(gc), green(gc), blue(gc), 230 * alpha);
    rrect(-ic * 0.5, -ic * 0.5, ic, ic, 16 * ak);
    fill(255, 255, 255, 255 * alpha);
    textAlign(CENTER, CENTER);
    textSizeQ(ic * 0.45);
    text(a.label.length() > 0 ? a.label.substring(0, 1) : "?", 0, -ic * 0.04);
  }
  popMatrix();
}

AppIcon appAt(float mx, float my) {
  AppIcon best = null;
  for (int i = order.length - 1; i >= 0; i--) {             // front first
    AppIcon a = (AppIcon) apps.get(order[i]);
    if (a.sz < 0.15) continue;
    float size = 118 * ak * (0.70 + 0.30 * (a.sz + 1) * 0.5);
    if (abs(mx - a.sx) < size * 0.6 && abs(my - a.sy) < size * 0.6) return a;
  }
  return best;
}

void openApp(AppIcon a) {
  a.flashAt = millis();
  if (appState(a).equals("iphone")) {            // a notification from the iPhone (Bluetooth): its app is there
    appMsg = "From your iPhone: open " + a.label + " there";
    appMsgAt = millis();
    return;
  }
  if (js != null) {
    if (!js.launchApp(a.pkg)) {
      appMsg = "Can't open " + a.label + " (not installed here)";
      appMsgAt = millis();
    }
  }
  else {
    println("APPify: open " + a.pkg + " (phone only)");
    appMsg = "Open " + a.label + " (on the phone)";
    appMsgAt = millis();
  }
}

// ---------------------------------------------------------------- numbers
int countToday() {
  String td = today();
  int n = 0;
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (e.ymd.equals(td) && !e.src.equals("SYS")) n++;
  }
  return n;
}

void drawAppCount() {
  int n = countToday();
  fill(#F4F7FF);
  textAlign(CENTER, BASELINE);
  textSizeQ(124 * ak);
  String s = "" + n;
  text(s, AX(426) - 1.5 * ak, AY(905));
  text(s, AX(426) + 1.5 * ak, AY(905));
  fill(#C9D3E6);
  textSizeQ(32 * ak);
  text("Notifications Today", AX(426), AY(952));
}

void drawGauges() {
  int nApps = apps.size();
  String[] cl = catList();
  int nCat = cl.length;
  int secs = -1;
  for (int i = 0; i < entries.size() && secs < 0; i++) {
    Entry e = (Entry) entries.get(i);
    if (e.src.equals("LIVE") || e.src.equals("SCAN")) secs = secondsAgo(e);
  }
  gauge(173, 1100, nApps, min(1, nApps / 20.0), "" + nApps, "Apps", color(40, 170, 255));
  if (catFilter.length() > 0) {
    int at = 0;
    for (int i = 0; i < cl.length; i++) if (cl[i].equals(catFilter)) at = i;
    gauge(425, 1100, nCat, (at + 1) / (float) max(1, nCat), (at + 1) + "/" + nCat, fitTextSized(catFilter, 140 * ak, 23 * ak), color(150, 100, 255));
  }
  else gauge(425, 1100, nCat, min(1, nCat / 10.0), "" + nCat, "Categories", color(150, 100, 255));
  if (appMode == A_ACTIVE) {
    int tot = 0;
    for (int i = 0; i < appsAll.size(); i++) tot += ((AppIcon) appsAll.get(i)).useS;
    gauge(677, 1100, tot, min(1, tot / (8 * 3600.0)), dur(tot), "Screen Time", color(255, 170, 40));
    return;
  }
  String last = secs < 0 ? "-" : ago(secs);
  gauge(677, 1100, secs, secs < 0 ? 0 : max(0.08, 1 - min(1, secs / 3600.0)), last, "Last Received", color(255, 170, 40));
}

void gauge(float x, float y, int v, float frac, String big, String label, color c) {
  float r = 80 * ak;
  noFill();
  stroke(18, 26, 42);
  strokeWeight(12 * ak);
  ellipse(AX(x), AY(y), 2 * r, 2 * r);
  stroke(26, 36, 56);
  strokeWeight(1.5 * ak);
  ellipse(AX(x), AY(y), 2 * r - 22 * ak, 2 * r - 22 * ak);
  float a0 = -HALF_PI, a1 = -HALF_PI + TWO_PI * max(0.001, frac);
  stroke(red(c), green(c), blue(c), 45);
  strokeWeight(20 * ak);
  arcPath(AX(x), AY(y), r, a0, a1);
  stroke(c);
  strokeWeight(7 * ak);
  arcPath(AX(x), AY(y), r, a0, a1);
  noStroke();
  fill(#F4F7FF);
  textAlign(CENTER, BASELINE);
  textSizeQ(46 * ak);
  text(big, AX(x), AY(y + 12));
  fill(#C9D3E6);
  textSizeQ(23 * ak);
  text(label, AX(x), AY(y + 52));
}

// notifications per hour today, as a glowing line; the marker is now
void drawFlow() {
  int[] bins = new int[24];
  String td = today();
  int mx = 1;
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!e.ymd.equals(td) || e.src.equals("SYS") || e.time.length() < 2) continue;
    int h = int(e.time.substring(0, 2));
    if (h >= 0 && h < 24) {
      bins[h]++;
      mx = max(mx, bins[h]);
    }
  }
  float x0 = -10, x1 = 862, base = 1300, amp = 62;
  int N = 96, RUN = 16;
  float nowF = (hour() + minute() / 60.0) / 24.0;
  float nowX = 0, nowY = 0;
  float[] fx = new float[N + 1], fy = new float[N + 1];
  for (int i = 0; i <= N; i++) {
    float f = (float) i / N;
    // smooth: hourly counts blended with their neighbours
    float hf = f * 23;
    int h0 = floor(hf);
    int h1 = min(23, h0 + 1);
    float t = hf - h0;
    t = t * t * (3 - 2 * t);
    float v = lerp(bins[h0], bins[h1], t) / mx;
    float wave = sin(f * PI) * 0.35;                    // the concept's arc, under the data
    fy[i] = AY(base - (wave + v * 0.65) * amp);
    fx[i] = AX(lerp(x0, x1, f));
    if (abs(f - nowF) < 0.5 / N + 0.0001) { nowX = fx[i]; nowY = fy[i]; }
  }
  noFill();
  for (int pass = 0; pass < 2; pass++) {
    for (int i0 = 0; i0 < N; i0 += RUN) {
      float f = (i0 + RUN * 0.5) / N;
      float r = lerp(70, 255, f), g = lerp(150, 170, f), b = lerp(255, 60, f);
      if (pass == 0) { stroke(r, g, b, 45); strokeWeight(9 * ak); }
      else { stroke(min(255, r + 50), min(255, g + 50), min(255, b + 50), 230); strokeWeight(2.4 * ak); }
      beginShape();
      for (int i = i0; i <= min(N, i0 + RUN); i++) vertex(fx[i], fy[i]);
      endShape();
    }
  }
  noStroke();
  // dots on the hours that had notifications
  for (int h = 0; h < 24; h++) {
    if (bins[h] == 0) continue;
    float f = h / 23.0;
    float x = AX(lerp(x0, x1, f));
    float y = AY(base - (sin(f * PI) * 0.35 + bins[h] / (float) mx * 0.65) * amp);
    color c = lerpColor(color(70, 150, 255), color(255, 170, 60), f);
    for (int i = 4; i >= 1; i--) {
      fill(red(c), green(c), blue(c), 30);
      ellipse(x, y, (8 + i * 6) * ak, (8 + i * 6) * ak);
    }
    fill(c);
    ellipse(x, y, 10 * ak, 10 * ak);
  }
  // now
  if (nowX == 0) { nowX = AX(lerp(x0, x1, nowF)); nowY = AY(base); }
  stroke(90, 150, 255, 120);
  strokeWeight(1.4 * ak);
  line(nowX, AY(1190), nowX, AY(1385));
  noStroke();
  for (int i = 6; i >= 1; i--) {
    fill(110, 170, 255, 30);
    ellipse(nowX, nowY, (16 + i * 7) * ak, (16 + i * 7) * ak);
  }
  fill(#EAF2FF);
  ellipse(nowX, nowY, 22 * ak, 22 * ak);
  fill(#9AA6C0);
  textAlign(CENTER, CENTER);
  textSizeQ(23 * ak);
  text("Activity Flow", AX(426), AY(1337));
}

// the newest notification from an app on the ball
Entry latestEntry() {
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (e.src.equals("SYS") || e.src.equals("MANUAL")) continue;
    for (int j = 0; j < apps.size(); j++) {
      AppIcon a = (AppIcon) apps.get(j);
      if (a.pkg.equals(e.pkg)) return e;
    }
  }
  return null;
}

void drawLatest() {
  Entry e = latestEntry();
  float x = AX(40), y = AY(1412), w = 770 * ak, h = 152 * ak, r = 38 * ak;
  // the stacked glass edge behind
  stroke(70, 110, 200, 60);
  strokeWeight(1.4 * ak);
  rrectLine(AX(24), AY(1404), w + 16 * ak, h + 20 * ak, r + 6 * ak);
  noStroke();
  fill(12, 20, 42, 235);
  rrect(x, y, w, h, r);
  AppIcon a = e == null ? null : appFor(e.pkg);
  color gc = (a != null && a.ready) ? a.glow : (a != null ? pkgColour(a.pkg) : color(60, 120, 220));
  for (int i = 10; i >= 1; i--) {                          // the app's colour glowing at the left
    fill(red(gc), green(gc), blue(gc), 7);
    ellipse(x + 76 * ak, y + h * 0.5, (120 + i * 20) * ak, (100 + i * 8) * ak);
  }
  stroke(80, 130, 230, 170);
  strokeWeight(1.6 * ak);
  rrectLine(x, y, w, h, r);
  noStroke();
  if (e == null) {
    fill(#9AA6C0);
    textAlign(LEFT, CENTER);
    textSizeQ(26 * ak);
    text("The newest notification shows here", x + 40 * ak, y + h * 0.5);
    return;
  }
  float ic = 78 * ak, ix = x + 38 * ak, iy = y + (h - ic) * 0.5;
  if (a.ready) image(a.img, ix, iy, ic, ic);
  else {
    fill(gc);
    rrect(ix, iy, ic, ic, 18 * ak);
    fill(255);
    textAlign(CENTER, CENTER);
    textSizeQ(36 * ak);
    text(a.label.length() > 0 ? a.label.substring(0, 1) : "?", ix + ic * 0.5, iy + ic * 0.47);
  }
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(31 * ak);
  String name = a.label.length() > 0 ? a.label : e.pkg;
  text(name, x + 142 * ak, y + 62 * ak);
  text(name, x + 142 * ak + 0.9 * ak, y + 62 * ak);
  fill(#C9D3E6);
  textSizeQ(24 * ak);
  String body = e.title.length() > 0 && !e.title.equals(name) ? e.title + ": " + e.body : e.body;
  if (body.length() > 46) body = body.substring(0, 45) + "...";
  text(body, x + 142 * ak, y + 104 * ak);
  fill(#9AA6C0);
  textAlign(RIGHT, BASELINE);
  textSizeQ(22 * ak);
  text(ago(secondsAgo(e)) + " ago", x + w - 56 * ak, y + 58 * ak);
  fill(#2F8BFF);
  ellipse(x + w - 32 * ak, y + 50 * ak, 12 * ak, 12 * ak);
}

boolean overLatest(float mx, float my) {
  return mx >= AX(40) && mx <= AX(810) && my >= AY(1412) && my <= AY(1564);
}

int secondsAgo(Entry e) {
  if (!e.ymd.equals(today()) || e.time.length() < 8) return 99999;
  int h = int(e.time.substring(0, 2)), m = int(e.time.substring(3, 5)), s = int(e.time.substring(6, 8));
  return max(0, (hour() * 3600 + minute() * 60 + second()) - (h * 3600 + m * 60 + s));
}

String ago(int s) {
  if (s >= 99999) return "1d+";
  if (s < 60) return s + "s";
  if (s < 3600) return floor(s / 60.0) + "m";
  return floor(s / 3600.0) + "h";
}

// ---------------------------------------------------------------- touch (called from the main tab)
void appifyPressed(float mx, float my) {
  appPressX = mx; appPressY = my; appLastX = mx; appLastY = my;
  appMoved = false;
  listDragA = showList && overList(mx, my);
  if (listDragA) { appDrag = false; return; }
  appDrag = dist(mx, my, AX(bCX), AY(bCY)) < ballR * ak * 1.15;
  if (appDrag) { spinVX = 0; spinVY = 0; }
  appSpin = true;                                  // a drag that starts anywhere turns the globe (as the Archive's balls)
}

void appifyDragged(float mx, float my) {
  if (abs(mx - appPressX) > 12 * u || abs(my - appPressY) > 12 * u) appMoved = true;
  if (listDragA) {
    listScrollA -= my - appLastY;
    appLastY = my;
    return;
  }
  if (!appDrag && !appSpin) return;
  if (!appMoved) return;                           // a tap stays a tap: turning starts once the finger moves
  float R = ballR * ak;
  float dx = (mx - appLastX) / R, dy = (my - appLastY) / R;
  rotScreen(dx, dy);
  spinVX = dx;
  spinVY = dy;
  appLastX = mx;
  appLastY = my;
}

void appifyReleased(float mx, float my) {
  boolean wasDrag = appDrag;
  appDrag = false;
  if (appMoved) return;                            // a flick: keeps spinning (spinVX/VY)
  if (peopleGlobe) { peopleRelease(mx, my, wasDrag); return; }   // CHATNOTE Orbit
  // the apps list takes taps first while it's open
  if (showList) {
    if (overListClose(mx, my)) { showList = false; return; }
    if (overList(mx, my)) {
      AppIcon a = listRowAt(mx, my);
      if (a != null) {
        showList = false;
        chooseApp(a);
      }
      return;
    }
    if (gaugeAt(mx, my) != 0) { showList = false; return; }  // anywhere else closes it (the Apps ring too)
  }
  int g = gaugeAt(mx, my);
  if (g == 0) {
    showList = !showList;
    listScrollA = 0;
    return;
  }
  if (g == 1) { nextCategory(); return; }
  if (g == 2) {
    if (appMode == A_ACTIVE) mostUsed();
    else lastReceived();
    return;
  }
  if (apps.size() == 0 && usageNeeded && dist(mx, my, AX(bCX), AY(bCY)) < ballR * ak) {
    js.openUsageAccess();
    return;
  }
  if (catFilter.length() > 0 && overFilterPill(mx, my)) {
    catFilter = "";
    appSig = "";
    spinVX = 0.12;
    return;
  }
  spinVX = 0.0035;
  spinVY = 0;
  int m = modeAt(mx, my);
  if (m == A_FIND && appMode == A_FIND) { if (js != null) js.findAdd(); return; }   // FIND again: type a name
  if (m >= 0) {
    if (m != appMode) {
      appMode = m;
      appSig = "";
      spinVX = 0.12;                               // a quick turn as the ball refills
      savePref("appmode", "" + m);
    }
    return;
  }
  if (wasDrag) {
    AppIcon a = appAt(mx, my);
    if (a == null) selApp = null;                // the glass, not an icon
    else if (a == selApp) openApp(a);            // second touch opens it
    else chooseApp(a);
    return;
  }
  if (selApp != null && overInfo(mx, my)) {
    int bi = infoBtnAt(mx, my);
    if (clearing()) {
      if (bi == 0) clearFor = null;                                  // BACK
      else if (bi == 2) { clearApp(selApp); clearFor = null; }       // CLEAR (what the toggles say)
      else if (bi < 0) {
        for (int i = 0; i < 2; i++) {
          if (abs(my - clearRowY(i)) < 19 * ak && mx > infoX() + 90 * ak) {
            if (i == 0) clearN = !clearN; else clearA = !clearA;
            savePref(i == 0 ? "clear_n" : "clear_a", (i == 0 ? clearN : clearA) ? "1" : "0");
          }
        }
      }
      return;
    }
    if (bi == 0 && selApp.pkg.startsWith("find:")) { if (js != null) js.findRemove(selApp.pkg.substring(5)); selApp = null; appSig = ""; }   // FIND: CLEAR takes the tile away
    else if (bi == 0) { loadClearPrefs(); clearFor = selApp; }
    else if (bi == 1) stopApp(selApp);
    else if (bi == 2) openApp(selApp);
    return;
  }
  if (overLatest(mx, my)) {
    Entry e = latestEntry();
    if (e != null) openApp(appFor(e.pkg));
    return;
  }
  selApp = null;
}

// the APPify icon for the bar: a small ball with an orbit
void drawAppifyIcon(float cx, float cy, float s, boolean on) {
  stroke(on ? #6CE0FF : #4A9AB8);
  strokeWeight(2.2 * u);
  noFill();
  ellipse(cx, cy, 1.5 * s, 1.5 * s);
  pushMatrix();
  translate(cx, cy);
  rotate(-0.35);
  ellipse(0, 0, 2.3 * s, 0.75 * s);
  popMatrix();
  noStroke();
  fill(on ? #6CE0FF : #4A9AB8);
  ellipse(cx - s * 0.2, cy - s * 0.15, 3.2 * u, 3.2 * u);
  ellipse(cx + s * 0.25, cy + s * 0.2, 3.2 * u, 3.2 * u);
}

// ---------------------------------------------------------------- the touched app
// its name, in a pill over the icon
void drawAppLabel(AppIcon a) {
  if (a.sz < 0.2) return;
  String name = a.label.length() > 0 ? a.label : a.pkg;
  textSizeQ(24 * ak);
  float tw = textWidth(name), pw = tw + 40 * ak, ph = 44 * ak;
  float size = 118 * ak * (0.70 + 0.30 * (a.sz + 1) * 0.5);
  float px = a.sx - pw * 0.5, py = a.sy - size * 0.62 - ph - 10 * ak;
  px = constrain(px, AX(8), AX(844) - pw);
  color gc = a.ready ? a.glow : pkgColour(a.pkg);
  float fade = constrain((millis() - selAt) / 200.0, 0, 1);
  fill(8, 14, 30, 225 * fade);
  rrect(px, py, pw, ph, ph * 0.5);
  stroke(red(gc), green(gc), blue(gc), 200 * fade);
  strokeWeight(1.6 * ak);
  rrectLine(px, py, pw, ph, ph * 0.5);
  noStroke();
  fill(244, 247, 255, 255 * fade);
  textAlign(CENTER, CENTER);
  text(name, px + pw * 0.5, py + ph * 0.5 - 2 * ak);
}

// the panel at the top, between ANA and Live, for the touched app
float infoX() { return AX(214); }
float infoY() { return AY(78); }
float infoW() { return 458 * ak; }
float infoH() { return 172 * ak; }
String[] infoBtn = { "CLEAR", "STOP", "OPEN" };
String[] peopleBtn = { "CLEAR", "CLOSE", "CHAT" };   // CHATNOTE Orbit
String[] clearBtn = { "BACK", "", "CLEAR" };

// CLEAR has two toggles (kept between uses): the app's notifications in the shade, and the app itself
// (closed in the background, as swiping it away in Recents does). Tap CLEAR: the panel shows the two
// toggles; tap CLEAR again to do it, BACK to leave. STOP stays: Android's App info page with Force stop.
AppIcon clearFor = null;                 // the panel shows CLEAR's toggles for this app
boolean clearN = true, clearA = false, clearPrefs = false;

boolean clearing() { return clearFor != null && clearFor == selApp; }

void loadClearPrefs() {
  if (clearPrefs || js == null) return;
  clearPrefs = true;
  clearN = !js.pref("clear_n").equals("0");
  clearA = js.pref("clear_a").equals("1");
}

// the two toggle rows: y centre of row i
float clearRowY(int i) { return infoY() + 44 * ak + i * 38 * ak; }

void miniToggle(float x, float cy, boolean on, float al) {
  float w = 58 * ak, h = 30 * ak;
  noStroke();
  fill(on ? color(30, 107, 255, 255 * al) : color(35, 43, 61, 255 * al));
  rrect(x, cy - h * 0.5, w, h, h * 0.5);
  fill(on ? color(255, 255, 255, 255 * al) : color(138, 147, 166, 255 * al));
  ellipse(on ? x + w - h * 0.5 : x + h * 0.5, cy, h * 0.78, h * 0.78);
}

// button i (0 CLEAR, 1 STOP, 2 OPEN): x, y, w, h
float[] infoBtnRect(int i) {
  float bw = 128 * ak, bh = 42 * ak, gap = 10 * ak;
  float x0 = infoX() + infoW() - 16 * ak - (bw * 3 + gap * 2);
  float[] r = new float[4];
  r[0] = x0 + i * (bw + gap);
  r[1] = infoY() + infoH() - bh - 14 * ak;
  r[2] = bw;
  r[3] = bh;
  return r;
}

void drawAppInfo(AppIcon a) {
  float fade = constrain((millis() - selAt) / 220.0, 0, 1);
  float x = infoX(), y = infoY() + (1 - fade) * 10 * ak, w = infoW(), h = infoH(), r = 30 * ak;
  color gc = a.ready ? a.glow : pkgColour(a.pkg);
  fill(10, 18, 38, 235 * fade);
  rrect(x, y, w, h, r);
  for (int i = 8; i >= 1; i--) {
    fill(red(gc), green(gc), blue(gc), 7 * fade);
    ellipse(x + 56 * ak, y + 62 * ak, (80 + i * 14) * ak, (70 + i * 8) * ak);
  }
  stroke(red(gc), green(gc), blue(gc), 190 * fade);
  strokeWeight(1.6 * ak);
  rrectLine(x, y, w, h, r);
  noStroke();

  float ic = 66 * ak, ix = x + 22 * ak, iy = y + 26 * ak;
  if (a.ready) image(a.img, ix, iy, ic, ic);
  else {
    fill(red(gc), green(gc), blue(gc), 255 * fade);
    rrect(ix, iy, ic, ic, 16 * ak);
    fill(255, 255, 255, 255 * fade);
    textAlign(CENTER, CENTER);
    textSizeQ(30 * ak);
    text(a.label.length() > 0 ? a.label.substring(0, 1) : "?", ix + ic * 0.5, iy + ic * 0.47);
  }

  // CLEAR / STOP / OPEN
  for (int i = 0; i < 3; i++) {
    float[] br = infoBtnRect(i);
    String lbl = peopleGlobe ? peopleBtn[i] : clearing() ? clearBtn[i] : infoBtn[i];
    if (lbl.length() == 0) continue;
    color bc = clearing() ? (i == 0 ? color(120, 135, 160) : (clearN || clearA) ? color(77, 163, 255) : color(70, 80, 100))
             : i == 0 ? color(77, 163, 255) : i == 1 ? color(255, 95, 95) : gc;
    fill(red(bc) * 0.3, green(bc) * 0.3, blue(bc) * 0.3, 230 * fade);
    rrect(br[0], br[1] + (1 - fade) * 10 * ak, br[2], br[3], br[3] * 0.5);
    stroke(red(bc), green(bc), blue(bc), 230 * fade);
    strokeWeight(1.6 * ak);
    rrectLine(br[0], br[1] + (1 - fade) * 10 * ak, br[2], br[3], br[3] * 0.5);
    noStroke();
    fill(255, 255, 255, 255 * fade);
    textAlign(CENTER, CENTER);
    textSizeQ(18 * ak);
    text(lbl, br[0] + br[2] * 0.5 - 0.4 * ak, br[1] + (1 - fade) * 10 * ak + br[3] * 0.5 - 1.5 * ak);
    text(lbl, br[0] + br[2] * 0.5 + 0.4 * ak, br[1] + (1 - fade) * 10 * ak + br[3] * 0.5 - 1.5 * ak);
  }

  float tx = x + 104 * ak, tw = x + w - 20 * ak - tx;
  if (clearing()) {
    String nm = a.label.length() > 0 ? a.label : a.pkg;
    String[] t = { "Notifications", "Close " + nm };
    String[] sub = { "Remove them from the shade", "Like swiping it away in Recents" };
    boolean[] on = { clearN, clearA };
    for (int i = 0; i < 2; i++) {
      float ry = clearRowY(i);
      fill(244, 247, 255, 255 * fade);
      textAlign(LEFT, BASELINE);
      textSizeQ(19 * ak);
      text(fitText(t[i], tw - 80 * ak), tx, ry - 1 * ak);
      fill(143, 163, 184, 255 * fade);
      textSizeQ(14 * ak);
      text(fitText(sub[i], tw - 80 * ak), tx, ry + 15 * ak);
      miniToggle(x + w - 20 * ak - 58 * ak, ry, on[i], fade);
    }
    return;
  }

  // name / category + counts (ACTIVE: screen time) / latest notification
  String name = a.label.length() > 0 ? a.label : a.pkg;
  fill(244, 247, 255, 255 * fade);
  textAlign(LEFT, BASELINE);
  textSizeQ(25 * ak);
  name = fitText(name, tw);
  text(name, tx, y + 44 * ak);
  text(name, tx + 0.8 * ak, y + 44 * ak);

  if (peopleGlobe) {                               // CHATNOTE: the person and their last message
    String pk = a.pkg.substring(5);
    ChatMsg lm = chatLastFrom(pk);
    fill(143, 163, 184, 255 * fade);
    textSizeQ(17 * ak);
    text(fitText("CHATNOTE  \u00b7  " + chatCount(pk) + " messages  \u00b7  sealed \u2713", tw), tx, y + 72 * ak);
    fill(201, 211, 230, 255 * fade);
    text(fitText(lm == null ? "" : chatTime(lm.age) + ":  " + lm.text, tw), tx, y + 100 * ak);
    return;
  }
  int nToday = 0, all = 0;
  Entry last = null;
  String td = today();
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!e.pkg.equals(a.pkg) || e.src.equals("SYS")) continue;
    all++;
    if (e.ymd.equals(td)) nToday++;
    if (last == null) last = e;
  }
  fill(143, 163, 184, 255 * fade);
  textSizeQ(17 * ak);
  String info = (a.cat.length() > 0 ? a.cat + "  ·  " : "");
  if (appMode == A_ACTIVE) info += dur(a.useS) + " today  ·  used " + ago(a.agoS) + " ago";
  else info += nToday + " today  ·  " + all + " in all";
  text(fitText(info, tw), tx, y + 72 * ak);
  fill(201, 211, 230, 255 * fade);
  String lastS = last == null ? "No notifications from it" : ago(secondsAgo(last)) + " ago:  " + (last.title.length() > 0 && !last.title.equals(name) ? last.title + ": " : "") + last.body;
  text(fitText(lastS, tw), tx, y + 100 * ak);
}

boolean overInfo(float mx, float my) {
  return mx >= infoX() && mx <= infoX() + infoW() && my >= infoY() && my <= infoY() + infoH();
}

int infoBtnAt(float mx, float my) {
  for (int i = 0; i < 3; i++) {
    float[] r = infoBtnRect(i);
    if (mx >= r[0] - 4 * ak && mx <= r[0] + r[2] + 4 * ak && my >= r[1] - 12 * ak && my <= r[1] + r[3] + 12 * ak) return i;
  }
  return -1;
}

// CLEAR: what its toggles say: the app's notifications out of the shade, and / or the app closed in the
// background (as swiping it away in Recents does)
void clearApp(AppIcon a) {
  a.flashAt = millis();
  if (!clearN && !clearA) appMsg = "Turn on Notifications or Close first";
  else if (js == null) {
    println("APPify: clear " + a.pkg + (clearN ? " notifications" : "") + (clearA ? " + close it" : "") + " (phone only)");
    appMsg = "Clear " + a.label + " (on the phone)";
  }
  else {
    String m = "";
    if (clearN) {
      int n = js.clearNotifs(a.pkg);
      if (n < 0) m = "Clearing notifications needs Notification access";
      else if (n == 0) m = "No notifications in the shade";
      else m = "Cleared " + n + " notification" + (n == 1 ? "" : "s");
    }
    if (clearA) {
      boolean ok = js.closeApp(a.pkg);
      m += (m.length() > 0 ? "  ·  " : "") + (ok ? "closed " + a.label : "couldn't close " + a.label);
    }
    appMsg = m.substring(0, 1).toUpperCase() + m.substring(1);
  }
  appMsgAt = millis();
}

// STOP: Android's own App info page, where Force stop is
void stopApp(AppIcon a) {
  if (js == null) {
    println("APPify: App info for " + a.pkg + " (phone only)");
    appMsg = "Stop " + a.label + " (on the phone)";
  }
  else {
    js.appSettings(a.pkg);
    appMsg = "Tap Force stop on the App info page";
  }
  appMsgAt = millis();
}

// the most used app today (ACTIVE): turn to it
void mostUsed() {
  AppIcon best = null;
  for (int i = 0; i < appsAll.size(); i++) {
    AppIcon a = (AppIcon) appsAll.get(i);
    if (best == null || a.useS > best.useS) best = a;
  }
  if (best == null) {
    appMsg = usageNeeded ? "Allow Usage access first (tap the ball)" : "No apps used yet today";
    appMsgAt = millis();
    return;
  }
  if (apps.indexOf(best) < 0) {
    catFilter = "";
    appSig = "";
    appifyRefresh();
  }
  chooseApp(best);
}

// 1h 05m / 12m / 40s
String dur(int s) {
  if (s < 60) return s + "s";
  if (s < 3600) return floor(s / 60.0) + "m";
  int h = floor(s / 3600.0), m = floor((s - h * 3600) / 60.0);
  return h + "h " + nf(m, 2) + "m";
}

// shorten s with "..." to fit w (current text size)
String fitText(String s, float w) {
  if (textWidth(s) <= w) return s;
  int n = s.length();
  while (n > 1 && textWidth(s.substring(0, n) + "...") > w) n--;
  return s.substring(0, n) + "...";
}

// an arc as one path (Processing.js draws arc() in short pieces: see-through, they show beads)
void arcPath(float cx, float cy, float r, float a0, float a1) {
  int n = max(8, ceil(abs(a1 - a0) / 0.05));
  noFill();
  beginShape();
  for (int i = 0; i <= n; i++) {
    float t = a0 + (a1 - a0) * i / n;
    vertex(cx + cos(t) * r, cy + sin(t) * r);
  }
  endShape();
}

// ---------------------------------------------------------------- the three rings
void chooseApp(AppIcon a) {
  selApp = a;
  selAt = millis();
  a.flashAt = millis();
}

// 0 Apps, 1 Categories, 2 Last Received, -1 none
int gaugeAt(float mx, float my) {
  float r = 92 * ak;
  if (dist(mx, my, AX(173), AY(1100)) < r) return 0;
  if (dist(mx, my, AX(425), AY(1100)) < r) return 1;
  if (dist(mx, my, AX(677), AY(1100)) < r) return 2;
  return -1;
}

// the categories of the apps for this source, most apps first
String[] catList() {
  ArrayList names = new ArrayList();
  int[] cnt = new int[64];
  for (int i = 0; i < appsAll.size(); i++) {
    AppIcon a = (AppIcon) appsAll.get(i);
    if (a.cat.length() == 0) continue;
    int at = -1;
    for (int j = 0; j < names.size(); j++) {
      String c = (String) names.get(j);
      if (c.equals(a.cat)) at = j;
    }
    if (at < 0 && names.size() < 64) { cnt[names.size()] = 1; names.add(a.cat); }
    else if (at >= 0) cnt[at]++;
  }
  String[] out = new String[names.size()];
  for (int i = 0; i < out.length; i++) out[i] = (String) names.get(i);
  for (int i = 1; i < out.length; i++) {                 // by count, most first
    String sv = out[i];
    int cv = cnt[i];
    int j = i - 1;
    while (j >= 0 && cnt[j] < cv) { out[j + 1] = out[j]; cnt[j + 1] = cnt[j]; j--; }
    out[j + 1] = sv;
    cnt[j + 1] = cv;
  }
  return out;
}

// All -> first category -> next ... -> last -> All
void nextCategory() {
  String[] cl = catList();
  if (cl.length == 0) {
    appMsg = "No categories for these apps";
    appMsgAt = millis();
    return;
  }
  int at = -1;
  for (int i = 0; i < cl.length; i++) if (cl[i].equals(catFilter)) at = i;
  catFilter = (at + 1 < cl.length) ? cl[at + 1] : "";
  appSig = "";
  selApp = null;
  spinVX = 0.12;                                          // a quick turn as the ball refills
}

// the app that sent the newest notification: turn to it and open its panel
void lastReceived() {
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!(e.src.equals("LIVE") || e.src.equals("SCAN"))) continue;
    for (int j = 0; j < appsAll.size(); j++) {
      AppIcon a = (AppIcon) appsAll.get(j);
      if (!a.pkg.equals(e.pkg)) continue;
      if (apps.indexOf(a) < 0) {                          // filtered out: show all again so it's on the ball
        catFilter = "";
        appSig = "";
        appifyRefresh();
      }
      chooseApp(a);
      return;
    }
  }
  appMsg = "Nothing received from these apps yet";
  appMsgAt = millis();
}

// tap APPify in the bar again: back to the default view
void appifyHome() {
  catFilter = "";
  showList = false;
  selApp = null;
  appSig = "";
  spinVX = 0.12;
  spinVY = 0;
}

// "Finance  x" under the ball while a category is on
float pillW() {
  textSizeQ(20 * ak);
  return textWidth(catFilter + "   x") + 44 * ak;
}

void drawFilterPill() {
  float pw = pillW(), ph = 40 * ak, px = AX(426) - pw * 0.5, py = AY(708);
  fill(30, 20, 60, 230);
  rrect(px, py, pw, ph, ph * 0.5);
  stroke(150, 100, 255, 220);
  strokeWeight(1.6 * ak);
  rrectLine(px, py, pw, ph, ph * 0.5);
  noStroke();
  fill(#FFFFFF);
  textAlign(CENTER, CENTER);
  textSizeQ(20 * ak);
  text(catFilter + "   x", px + pw * 0.5, py + ph * 0.5 - 1.5 * ak);
}

boolean overFilterPill(float mx, float my) {
  float pw = pillW(), ph = 40 * ak, px = AX(426) - pw * 0.5, py = AY(708);
  return mx >= px - 10 * ak && mx <= px + pw + 10 * ak && my >= py - 10 * ak && my <= py + ph + 10 * ak;
}

// ---------------------------------------------------------------- the apps list (Apps ring)
float alX() { return AX(40); }
float alY() { return AY(258); }
float alW() { return 772 * ak; }
float alH() { return 560 * ak; }
float alRow() { return 78 * ak; }
float alTop() { return alY() + 70 * ak; }

ArrayList listOrder() {
  ArrayList o = new ArrayList();
  for (int i = 0; i < apps.size(); i++) {
    AppIcon a = (AppIcon) apps.get(i);
    int j = 0;
    while (j < o.size()) {
      AppIcon b = (AppIcon) o.get(j);
      if (b.n < a.n) break;
      j++;
    }
    o.add(j, a);
  }
  return o;
}

void drawAppList() {
  float x = alX(), y = alY(), w = alW(), h = alH();
  fill(6, 10, 24, 245);
  rrect(x, y, w, h, 34 * ak);
  stroke(40, 170, 255, 170);
  strokeWeight(1.6 * ak);
  rrectLine(x, y, w, h, 34 * ak);
  noStroke();
  fill(#F4F7FF);
  textAlign(LEFT, CENTER);
  textSizeQ(26 * ak);
  String t = apps.size() + " apps" + (catFilter.length() > 0 ? "  ·  " + catFilter : "") + (appMode == A_ACTIVE ? "  ·  most used first" : "  ·  busiest first");
  text(fitText(t, w - 120 * ak), x + 30 * ak, y + 36 * ak);
  text(fitText(t, w - 120 * ak), x + 30.8 * ak, y + 36 * ak);
  // close
  fill(30, 44, 70);
  ellipse(x + w - 42 * ak, y + 36 * ak, 44 * ak, 44 * ak);
  stroke(#C9D3E6);
  strokeWeight(2.4 * ak);
  line(x + w - 50 * ak, y + 28 * ak, x + w - 34 * ak, y + 44 * ak);
  line(x + w - 34 * ak, y + 28 * ak, x + w - 50 * ak, y + 44 * ak);
  noStroke();

  ArrayList o = listOrder();
  float top = alTop(), bottom = y + h - 16 * ak, rh = alRow();
  listScrollA = constrain(listScrollA, 0, max(0, o.size() * rh - (bottom - top)));
  String td = today();
  for (int i = 0; i < o.size(); i++) {
    float ry = top + i * rh - listScrollA;
    if (ry + rh < top || ry > bottom) continue;
    AppIcon a = (AppIcon) o.get(i);
    if (ry < top || ry + rh > bottom + 1) continue;      // whole rows only (no clip in 1.5.1)
    color gc = a.ready ? a.glow : pkgColour(a.pkg);
    fill(14, 22, 44, 200);
    rrect(x + 16 * ak, ry + 4 * ak, w - 32 * ak, rh - 8 * ak, 20 * ak);
    float ic = 50 * ak, ix = x + 30 * ak, iy = ry + (rh - ic) * 0.5;
    if (a.ready) image(a.img, ix, iy, ic, ic);
    else {
      fill(gc);
      rrect(ix, iy, ic, ic, 12 * ak);
      fill(255);
      textAlign(CENTER, CENTER);
      textSizeQ(24 * ak);
      text(a.label.substring(0, 1), ix + ic * 0.5, iy + ic * 0.47);
    }
    int nT = 0;
    for (int k = 0; k < entries.size(); k++) {
      Entry e = (Entry) entries.get(k);
      if (e.pkg.equals(a.pkg) && e.ymd.equals(td)) nT++;
    }
    fill(#F4F7FF);
    textAlign(LEFT, BASELINE);
    textSizeQ(23 * ak);
    text(fitText(a.label, w - 330 * ak), x + 100 * ak, ry + 36 * ak);
    fill(#8FA3B8);
    textSizeQ(17 * ak);
    text(fitText(a.cat.length() > 0 ? a.cat : a.pkg, w - 330 * ak), x + 100 * ak, ry + 60 * ak);
    fill(red(gc), green(gc), blue(gc));
    textAlign(RIGHT, BASELINE);
    textSizeQ(26 * ak);
    text(appMode == A_ACTIVE ? dur(a.useS) : "" + a.n, x + w - 40 * ak, ry + 38 * ak);
    fill(#8FA3B8);
    textSizeQ(16 * ak);
    text(appMode == A_ACTIVE ? "used " + ago(a.agoS) + " ago" : nT + " today", x + w - 40 * ak, ry + 60 * ak);
  }
  if (o.size() == 0) {
    fill(#9AA6C0);
    textAlign(CENTER, CENTER);
    textSizeQ(22 * ak);
    text("No apps here yet", x + w * 0.5, y + h * 0.5);
  }
}

boolean overList(float mx, float my) {
  return mx >= alX() && mx <= alX() + alW() && my >= alY() && my <= alY() + alH();
}

boolean overListClose(float mx, float my) {
  return dist(mx, my, alX() + alW() - 42 * ak, alY() + 36 * ak) < 34 * ak;
}

AppIcon listRowAt(float mx, float my) {
  if (my < alTop()) return null;
  ArrayList o = listOrder();
  int i = floor((my - alTop() + listScrollA) / alRow());
  if (i < 0 || i >= o.size()) return null;
  return (AppIcon) o.get(i);
}

// fitText at a given size (leaves the text size as it was)
String fitTextSized(String s, float w, float sz) {
  textSizeQ(sz);
  return fitText(s, w);
}
