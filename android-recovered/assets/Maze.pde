// Maze.pde — Archive, the flat screen: EFINOTE (E electronic, FIN infinite, NOT notifications, E archive).
//
// Three balls side by side: PAST, PRESENT and FUTURE (Future.pde says what's future). Each is a ball of maze
// shells, one shell per day: the day's timeline built as a fingerprint maze wrapped round the ball:
//   ridges = the hours (midnight by the glowing core), doors = the notifications (each opens its hour's ridge
//   at its minute), walls = mirrored quarter-hour marks, beads = the notifications, with the app's icon.
// The balls are shaded per pixel on the GPU (glmaze.js), from the user's sphere sketches: PAST is gooey
// Volcanic Agate, PRESENT emerald glass, FUTURE etched Liquid Mercury. Without WebGL (and on the desktop)
// the same maze is drawn as glass-tube lines.
//
// Each ball sits in a round lens. The ball you touched last is the big one.
//   pinch on a ball (or + / -)   zoom INSIDE its lens: the surface grows, the lens stays the same size
//                                (so it costs the same at any zoom). Past the closest zoom you pass into the
//                                next day (older on PAST, further ahead on FUTURE); zoom back out to return.
//   drag                         turn the balls: LOCK turns all three together, FREE turns the one you touch
//   tap a ball                   bring it forward; with Full screen (Settings, experimental) it fills the screen
// Touch a bead: its card has the notification, the app's state, LAUNCH and SELECT. EXPORT / IMPORT / PICKED.

Entry mzSel = null;            // the notification touched
int mzSig = -1;

final int B_PAST = 0, B_PRESENT = 1, B_FUTURE = 2;
String[] ballName = { "PAST", "PRESENT", "FUTURE" };
int mzBall = B_PRESENT;        // the ball in front (the big lens, or the one full screen)
int efStart = 0;               // Settings: Archive opens on 0 PRESENT, 1 PAST, 2 FUTURE
boolean efFull = false;        // Settings: Full screen (experimental)
boolean mzLock = true;         // turn all three together
boolean mzFullOpen = false;    // a ball is full screen
float mzOpenT = 1;             // 0..1 growing into full screen
boolean mzStarted = false;

// each ball's days (its shells): PAST newest first, PRESENT today, FUTURE soonest first
String[] mzDaysPast = new String[0], mzDaysPresent = new String[0], mzDaysFuture = new String[0];

// per ball: zoom z = shell * ln(MAG_MAX) + ln(magnification), its turn, its spin, its lens size
final float MAG_MAX = 6;
float LOGM = log(MAG_MAX);
float[] mzZB = { 0, 0, 0 }, mzZBT = { 0, 0, 0 };
float[][] mzRotB = { { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, { 1, 0, 0, 0, 1, 0, 0, 0, 1 } };
float[] mzVXB = { 0, 0, 0 }, mzVYB = { 0, 0, 0 };
float[] mzLensR = { 0, 0, 0 };
int[] mzShellB = { 0, 0, 0 };
int[] mzFlashAt = { -9999, -9999, -9999 };
boolean[] mzFacedB = { false, false, false };
int mzDragBall = -2;           // -2: not decided yet this drag
boolean mzPinching = false;
int mzShell = 0;               // the front ball's shell
float[] mzRot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };   // the rotation being drawn / turned right now
int mzLastMs = 0;
final int MZ_CORE = 2;         // two small loops round the core before the first hour
final int MZ_RIDGES = MZ_CORE + 25, MZ_SAMP = 144;
float[] mzPX = new float[MZ_RIDGES * MZ_SAMP], mzPY = new float[MZ_RIDGES * MZ_SAMP], mzPZ = new float[MZ_RIDGES * MZ_SAMP];
boolean[] mzOpen = new boolean[MZ_RIDGES * MZ_SAMP];

// the GPU
boolean mzGL = false, mzGLChecked = false, mzGLShown = false;
PGraphics mzBgSent = null;
PGraphics[] mzDoorPG = new PGraphics[3];
String[] mzDoorKey = { "", "", "" };

class MazeNode {
  Entry e;
  int ball;                    // B_PAST / B_PRESENT / B_FUTURE
  int shell;                   // which day of that ball
  int ridge;                   // the ridge it opens a door in (its hour's outer wall)
  float phi;                   // where round the core (its minute)
  float dx, dy, dz;            // where on the shell (unit sphere, ball space)
  float sx, sy, sz, sd;        // this frame: on screen, facing, bead size (0 = not drawn)
  String when = "";            // the time it sits at (FUTURE: the time it points to)
}
ArrayList mzNodes = new ArrayList();

float mzCX() { return width * 0.5; }
float mzCY() { return (FY(200) + mazeBottom()) * 0.5; }
float mzR() { return min(width * 0.40, (mazeBottom() - FY(200)) * 0.40); }

float mzHash(int k, int j) {
  float s = sin(k * 12.9898 + j * 78.233) * 43758.5453;
  return s - floor(s);
}

// The angle from the core (pole) to ridge k at angle phi round it (phi = 0 at the top, clockwise).
// It depends only on cos(phi), so every ridge is mirrored left / right: a fingerprint loop, taller than wide.
// (glmaze.js uses the same formula.)
float mzRho(int sh, int k, float phi) {
  float base = (k + 1.0) / (MZ_RIDGES + 1.0) * PI * 0.97;
  float w = 1 + 0.10 * cos(phi) + 0.07 * cos(2 * phi);
  return min(base * w, PI * 0.985);
}

int mzHourRidge(int hour) { return MZ_CORE + hour + 1; }   // the ridge outside hour `hour`'s corridor

String[] daysOf(int b) { return b == B_PAST ? mzDaysPast : b == B_PRESENT ? mzDaysPresent : mzDaysFuture; }
String[] mzDays() { return daysOf(mzBall); }

int indexIn(String[] a, String s) {
  for (int i = 0; i < a.length; i++) if (a[i].equals(s)) return i;
  return -1;
}

// a ball's zoom: which day (shell) and how close
int shellOf(int b) {
  int n = daysOf(b).length;
  if (n == 0) return 0;
  return constrain(floor(max(0, mzZB[b]) / LOGM), 0, n - 1);
}
float magOf(int b) { return exp(mzZB[b] - shellOf(b) * LOGM); }
float zMinB(int b) { return mzFullOpen && b == mzBall ? log(0.5) : 0; }
float zMaxB(int b) { return max(0, daysOf(b).length - 1) * LOGM + LOGM * 0.995; }

void mazeRebuild() {
  futSig++;
  ArrayList dPast = new ArrayList(), dFut = new ArrayList();
  String td = today();
  mzNodes.clear();
  for (int i = 0; i < entries.size(); i++) {
    Entry e = (Entry) entries.get(i);
    if (!passes(e) || e.src.equals("SYS")) continue;
    MazeNode n = new MazeNode();
    n.e = e;
    if (isFuture(e)) { n.ball = B_FUTURE; n.when = futWhen(e); }
    else if (e.src.equals("REMIND")) continue;              // a reminder that has passed (or reminders are off)
    else if (e.ymd.equals(td)) { n.ball = B_PRESENT; n.when = e.ymd + " " + e.time; }
    else { n.ball = B_PAST; n.when = e.ymd + " " + e.time; }
    if (n.when.length() < 19) continue;
    String d = n.when.substring(0, 10);
    if (n.ball == B_PAST && dPast.indexOf(d) < 0) dPast.add(d);
    if (n.ball == B_FUTURE && dFut.indexOf(d) < 0) dFut.add(d);
    mzNodes.add(n);
  }
  mzDaysPast = toSorted(dPast, true);
  mzDaysPresent = new String[1];
  mzDaysPresent[0] = td;
  mzDaysFuture = toSorted(dFut, false);
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    n.shell = max(0, indexIn(daysOf(n.ball), n.when.substring(0, 10)));
    int hh = int(n.when.substring(11, 13));
    float mi = int(n.when.substring(14, 16)) + int(n.when.substring(17, 19)) / 60.0;
    // the hour's corridor (between ridge MZ_CORE+hh and the next), the minute round it from the top
    n.phi = mi / 60.0 * TWO_PI;
    n.ridge = mzHourRidge(hh);
    float rho = (mzRho(n.shell, n.ridge - 1, n.phi) + mzRho(n.shell, n.ridge, n.phi)) * 0.5;
    n.dx = sin(rho) * sin(n.phi);
    n.dy = -sin(rho) * cos(n.phi);
    n.dz = cos(rho);
  }
  for (int b = 0; b < 3; b++) {
    mzZB[b] = constrain(mzZB[b], zMinB(b), zMaxB(b));
    mzZBT[b] = constrain(mzZBT[b], zMinB(b), zMaxB(b));
    mzShellB[b] = shellOf(b);
  }
  for (int i = 0; i < 3; i++) mzDoorKey[i] = "";
}

String[] toSorted(ArrayList l, boolean newestFirst) {
  String[] d = new String[l.size()];
  for (int i = 0; i < d.length; i++) d[i] = (String) l.get(i);
  d = sort(d);
  return newestFirst ? reverse(d) : d;
}

// which ridge samples are open on shell `sh` of `ball`: the notifications' doors and the fingerprint loop
void buildOpen(int ball, int sh) {
  for (int q = 0; q < mzOpen.length; q++) mzOpen[q] = false;
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    if (n.ball != ball || n.shell != sh) continue;
    int j0 = round(n.phi / TWO_PI * MZ_SAMP);
    for (int d = -2; d <= 2; d++) mzOpen[n.ridge * MZ_SAMP + ((j0 + d) % MZ_SAMP + MZ_SAMP) % MZ_SAMP] = true;
  }
  // the fingerprint loop: the inner ridges are U shapes, open at the bottom (mirrored, narrowing outward)
  for (int k = 0; k < 11; k++) {
    float half = (0.30 - k * 0.025) * MZ_SAMP * 0.5 / PI;
    for (int d = -ceil(half); d <= ceil(half); d++) mzOpen[k * MZ_SAMP + 72 + d] = true;
  }
}

// is there a wall at sample j of corridor k? (mirrored, staggered quarter-hour marks)
boolean mzWall(int k, int j) {
  if (k < MZ_CORE || k >= MZ_RIDGES - 1) return false;
  int st = (floor((k - MZ_CORE) / 3.0) % 3 - 1) * 9;
  if ((k - MZ_CORE) % 3 == 0) return j == 36 + st || j == 108 - st;
  return j == 72;
}

// the doors / walls of a shell as a 256 x 32 texture for the GPU (red = door open, green = wall)
void mzDoorTexture(int slot, int ball, int sh) {
  String key = ball + ":" + sh + ":" + mzSig;
  if (mzDoorKey[slot].equals(key)) return;
  mzDoorKey[slot] = key;
  if (mzDoorPG[slot] == null) mzDoorPG[slot] = createGraphics(256, 32, JAVA2D);
  PGraphics g = mzDoorPG[slot];
  buildOpen(ball, sh);
  g.beginDraw();
  g.background(0);
  g.loadPixels();
  for (int k = 0; k < MZ_RIDGES; k++) {
    for (int c = 0; c < 256; c++) {
      int j = floor(c * MZ_SAMP / 256.0);
      int r = mzOpen[k * MZ_SAMP + j] ? 255 : 0;
      int gr = 0;
      for (int d = -2; d <= 2; d++) {                       // a wall, soft across 5 samples
        if (mzWall(k, (j + d + MZ_SAMP) % MZ_SAMP)) gr = max(gr, round(255 * (1 - abs(d) / 2.5)));
      }
      g.pixels[k * 256 + c] = 0xff000000 | (r << 16) | (gr << 8);
    }
  }
  g.updatePixels();
  g.endDraw();
  js.gmDoors(slot, g);
}

// turn mzRot: ax about the screen's vertical axis, ay about its horizontal axis
void mzRotate(float ax, float ay) {
  float cy = cos(ax), sy = sin(ax), cx = cos(ay), sx = sin(ay);
  float[] o = new float[9];
  for (int c = 0; c < 3; c++) {
    float x = mzRot[c], y = mzRot[3 + c], z = mzRot[6 + c];
    float x1 = x * cy - z * sy, z1 = x * sy + z * cy;
    float y2 = y * cx - z1 * sx, z2 = y * sx + z1 * cx;
    o[c] = x1; o[3 + c] = y2; o[6 + c] = z2;
  }
  for (int r = 0; r < 3; r++) {
    float l = sqrt(o[r * 3] * o[r * 3] + o[r * 3 + 1] * o[r * 3 + 1] + o[r * 3 + 2] * o[r * 3 + 2]);
    o[r * 3] /= l; o[r * 3 + 1] /= l; o[r * 3 + 2] /= l;
  }
  mzRot = o;
}

// turn ball b
void mzTurn(int b, float ax, float ay) {
  mzRot = mzRotB[b];
  mzRotate(ax, ay);
  mzRotB[b] = mzRot;
}

// turn ball b so its newest (PAST, PRESENT) or soonest (FUTURE) notification on the shell you're at faces you
void faceFirst(int b) {
  MazeNode best = null;
  int sh = shellOf(b);
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    if (n.ball != b || n.shell != sh) continue;
    if (best == null) best = n;
    else if (b == B_FUTURE ? whenCmp(n.when, best.when) < 0 : whenCmp(n.when, best.when) > 0) best = n;
  }
  if (best == null) return;
  mzFacedB[b] = true;
  float[] id = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
  mzRot = id;
  mzRotate(atan2(best.dx, best.dz), atan2(best.dy, sqrt(best.dx * best.dx + best.dz * best.dz)));
  mzRotate(-0.12, 0.10);                        // a little off centre, so the core shows beside it
  mzRotB[b] = mzRot;
  mzVXB[b] = 0;
  mzVYB[b] = 0;
}

// ---- where things are
float lensTarget(int b) {
  float area = mazeBottom() - FY(200);
  return b == mzBall ? min(width * 0.235, area * 0.30) : min(width * 0.115, area * 0.15);
}
float lensY() { return FY(200) + (mazeBottom() - FY(200)) * 0.44; }
float lensX(int b) {
  float g = width * 0.025;
  float total = 2 * (mzLensR[0] + mzLensR[1] + mzLensR[2]) + 2 * g;
  float x = (width - total) * 0.5 + mzLensR[0];
  if (b >= 1) x += mzLensR[0] + g + mzLensR[1];
  if (b >= 2) x += mzLensR[1] + g + mzLensR[2];
  return x;
}

// where ball b is drawn this frame: centre x, y, lens radius (the clip), sphere radius
float[] ballView(int b) {
  float lx = lensX(b), ly = lensY(), lr = mzLensR[b];
  float mag = magOf(b);
  float[] v = { lx, ly, lr, lr * mag };
  if (mzFullOpen && b == mzBall) {
    float k = mzOpenT * mzOpenT * (3 - 2 * mzOpenT);
    float fullR = mzR() * 1.9 * mag;
    v[0] = lerp(lx, mzCX(), k);
    v[1] = lerp(ly, mzCY(), k);
    v[2] = lerp(lr, width * 3, k);
    v[3] = lerp(lr * mag, fullR, k);
  }
  if (!mzGL) v[3] = min(v[3], v[2]);           // the line drawing can't be clipped: no magnifying
  return v;
}

int ballAt(float x, float y) {
  if (mzFullOpen) return mzBall;
  for (int b = 0; b < 3; b++) if (dist(x, y, lensX(b), lensY()) < mzLensR[b] * 1.12) return b;
  return -1;
}

void bringForward(int b) {
  if (b == mzBall) return;
  mzBall = b;
  mzSel = null;
}

void openFull(int b) {
  mzBall = b;
  mzFullOpen = true;
  mzOpenT = 0;
  mzSel = null;
}

void closeFull() {
  mzFullOpen = false;
  mzOpenT = 1;
  mzZB[mzBall] = max(0, mzZB[mzBall]);
  mzZBT[mzBall] = mzZB[mzBall];
  mzSel = null;
}

// the GPU layer is only on Archive
void mazeLeave() {
  if (mzGLShown && js != null) { js.gmHide(); mzGLShown = false; }
}

void drawMaze() {
  int sig = entries.size() * 7 + (filterOn ? 1 : 0) + watch.size() * 131 + (futEvent ? 3 : 0) + (futText ? 5 : 0) + (futRemind ? 11 : 0) + floor(millis() / 60000.0) * 1009;
  if (sig != mzSig) { mzSig = sig; mazeRebuild(); }
  if (!mzStarted) {
    mzStarted = true;
    mzBall = efStart == 1 ? B_PAST : efStart == 2 ? B_FUTURE : B_PRESENT;
    for (int b = 0; b < 3; b++) mzLensR[b] = lensTarget(b);
    if (efFull) { mzFullOpen = true; mzOpenT = 1; }
  }
  for (int b = 0; b < 3; b++) if (!mzFacedB[b] && mzDragBall == -2) faceFirst(b);
  if (!mzGLChecked) {
    mzGLChecked = true;
    mzGL = js != null && js.gmOk();
  }
  if (mzFullOpen && !efFull) closeFull();
  int now = millis();
  float dt = constrain((now - mzLastMs) / 16.7, 0, 6);
  mzLastMs = now;
  boolean dragging = dragMode == D_LIST && tab == T_ARCHIVE && mousePressed;
  for (int b = 0; b < 3; b++) {
    if (!dragging && (mzVXB[b] != 0 || mzVYB[b] != 0)) {
      mzTurn(b, mzVXB[b] * dt, mzVYB[b] * dt);
      mzVXB[b] *= pow(0.92, dt);
      mzVYB[b] *= pow(0.92, dt);
      if (abs(mzVXB[b]) < 0.0002 && abs(mzVYB[b]) < 0.0002) { mzVXB[b] = 0; mzVYB[b] = 0; }
    }
    if (!mzPinching) {
      mzZB[b] += (mzZBT[b] - mzZB[b]) * min(1, 0.2 * dt);
      if (abs(mzZBT[b] - mzZB[b]) < 0.0005) mzZB[b] = mzZBT[b];
    }
    float t = lensTarget(b);
    mzLensR[b] += (t - mzLensR[b]) * min(1, 0.18 * dt);
    if (abs(t - mzLensR[b]) < 0.3) mzLensR[b] = t;
    int s = shellOf(b);
    if (s != mzShellB[b]) {                          // passed into another day
      mzShellB[b] = s;
      mzFlashAt[b] = now;
      mzSel = null;
      faceFirst(b);                                  // the new day's first notification toward you
    }
  }
  if (mzFullOpen && mzOpenT < 1) mzOpenT = min(1, mzOpenT + 0.08 * dt);
  // zoomed right out of the full screen ball: back to the three
  if (mzFullOpen && !mzPinching && mzZBT[mzBall] < log(0.75) && mzZB[mzBall] < log(0.8)) closeFull();
  mzShell = shellOf(mzBall);

  if (mzGL) {
    js.gmClear();                                   // the sketch's canvas: see-through, the GPU layer is behind
    if (mzBgSent != flatBg) { js.gmBg(flatBg); mzBgSent = flatBg; }
    js.gmBegin(width, height);
    mzGLShown = true;
  }
  else image(flatBgImg, 0, 0);

  for (int b = 0; b < 3; b++) {
    if (mzFullOpen && b != mzBall) continue;
    float[] v = ballView(b);
    mzRot = mzRotB[b];
    drawBallAt(b, shellOf(b), v[0], v[1], v[3], 1, b, v[2]);
  }
  if (mzGL) js.gmEnd(0, 0);
  for (int i = 0; i < mzNodes.size(); i++) ((MazeNode) mzNodes.get(i)).sd = 0;
  for (int b = 0; b < 3; b++) {
    if (mzFullOpen && b != mzBall) continue;
    float[] v = ballView(b);
    mzRot = mzRotB[b];
    drawBeads(b, shellOf(b), v[0], v[1], v[3], 1, v[2]);
    if (!mzFullOpen) drawLens(b, v[0], v[1], v[2]);
  }

  // cover the area outside the maze (no clip in 1.5.1)
  noStroke();
  fill(5, 7, 12, 240);
  rect(0, 0, width, FY(200));
  if (mzFullOpen) rect(0, mazeBottom(), width, height - mazeBottom());

  String[] days = mzDays();
  String d = days.length > mzShell ? days[mzShell] : today();
  int nHere = 0;
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    if (n.ball == mzBall && n.shell == mzShell) nHere++;
  }
  String dl = d.equals(today()) ? "today" : longDate(d);
  String where = ballName[mzBall].substring(0, 1) + ballName[mzBall].substring(1).toLowerCase() + "  ·  " + dl + "  ·  " + nHere + " here";
  flatHeader("efinote", where, true);
  float bx = FX(800);
  int nSel = selectedCount();
  bx = mazeButton(bx, FY(104), nSel > 0 ? "EXPORT " + nSel : "EXPORT", nSel > 0 ? color(245, 185, 66) : color(90, 100, 130), 0);
  bx = mazeButton(bx, FY(104), "IMPORT", color(180, 140, 255), 1);
  mazeButton(bx, FY(104), filterOn ? "PICKED" : "ALL", color(77, 163, 255), 2);

  if (mzFullOpen && mzDays().length > 1) drawDepthGauge();

  // zoom in / out, and LOCK / FREE
  float zx = FX(62), zy = mazeBottom() - 120 * fk;
  for (int i = 0; i < 2; i++) {
    fill(14, 20, 38, 230);
    ellipse(zx, zy + i * 66 * fk, 54 * fk, 54 * fk);
    stroke(#C9D3E6);
    strokeWeight(2.6 * fk);
    line(zx - 11 * fk, zy + i * 66 * fk, zx + 11 * fk, zy + i * 66 * fk);
    if (i == 0) line(zx, zy - 11 * fk, zx, zy + 11 * fk);
    noStroke();
  }
  if (!mzFullOpen) drawLockButton(zx, zy - 76 * fk);

  if (mzSel != null) drawMazeCard(mzSel);
  else {
    fill(#7A8BA0);
    textAlign(CENTER, CENTER);
    textSizeQ(21 * fk);
    String hint = mzFullOpen ? "Pinch to zoom, further to " + (mzBall == B_PAST ? "go back a day" : mzBall == B_FUTURE ? "go a day ahead" : "get closer") + ". Pinch in to leave."
                : "Pinch a ball to zoom into it. Drag to turn " + (mzLock ? "all three." : "one.") + " Touch a bead.";
    text(hint, FX(426), mazeBottom() + 40 * fk);
  }
}

// one ball (one shell of it) at cx, cy, sphere radius Rs, inside a lens of radius clip
void drawBallAt(int ball, int sh, float cx, float cy, float Rs, float al, int slot, float clip) {
  if (al <= 0.01 || Rs < 4) return;
  if (daysOf(ball).length == 0) {
    // nothing in this ball yet: an empty glass ball
    float r = min(Rs, clip);
    noStroke();
    fill(14, 22, 44, 200 * al);
    ellipse(cx, cy, 2 * r, 2 * r);
    fill(#7A8BA0);
    textAlign(CENTER, CENTER);
    textSizeQ(min(22 * fk, r * 0.16));
    text(ball == B_FUTURE ? "Nothing ahead yet" : "Nothing before today", cx, cy);
    return;
  }
  if (mzGL) {
    mzDoorTexture(slot, ball, sh);
    float[] a = { cx, cy, Rs, mzRot[0], mzRot[1], mzRot[2], mzRot[3], mzRot[4], mzRot[5], mzRot[6], mzRot[7], mzRot[8],
                  ball, ball == B_PAST ? 0.55 : ball == B_PRESENT ? 0.25 : 0.08, ball == B_PAST ? 0.6 : 0.4, al, 0.35, clip };
    js.gmLayer(slot, a);
  }
  else drawShellVec(ball, sh, cx, cy, min(Rs, clip), al);
}

// the lens: a glass ring round each ball, its name, the day and the zoom under it
void drawLens(int b, float cx, float cy, float r) {
  color c = b == B_PAST ? color(224, 160, 96) : b == B_PRESENT ? color(61, 220, 151) : color(201, 211, 230);
  boolean front = b == mzBall;
  noFill();
  stroke(red(c), green(c), blue(c), front ? 150 : 80);
  strokeWeight((front ? 3 : 2) * fk);
  ellipse(cx, cy, 2 * r + 6 * fk, 2 * r + 6 * fk);
  stroke(255, 255, 255, 40);
  strokeWeight(1.2 * fk);
  ellipse(cx, cy, 2 * r + 14 * fk, 2 * r + 14 * fk);
  float fl = (millis() - mzFlashAt[b]) / 450.0;     // passed into another day: a ring goes out
  if (fl < 1) {
    stroke(red(c), green(c), blue(c), 220 * (1 - fl));
    strokeWeight(4 * fk * (1 - fl) + 1);
    ellipse(cx, cy, 2 * r * (1 + 0.25 * fl), 2 * r * (1 + 0.25 * fl));
  }
  noStroke();
  String[] days = daysOf(b);
  int sh = shellOf(b);
  float ty = cy + r + 30 * fk;
  fill(c);
  textAlign(CENTER, TOP);
  textSizeQ((front ? 25 : 20) * fk);
  boldTextF(ballName[b], cx, ty);
  fill(#9AA6C0);
  textSizeQ((front ? 19 : 16) * fk);
  String dl = days.length == 0 ? "empty" : days[sh].equals(today()) ? "today" : monthName(int(days[sh].substring(5, 7))).substring(0, 3) + " " + int(days[sh].substring(8, 10));
  String line2 = dl + (days.length > 1 ? "  ·  day " + (sh + 1) + "/" + days.length : "");
  float mag = magOf(b);
  if (mag > 1.05) line2 += "\n" + nf(mag, 1, 1) + "x";
  text(line2, cx, ty + (front ? 34 : 28) * fk);
}

// LOCK (all three turn together) / FREE (each on its own)
void drawLockButton(float x, float y) {
  fill(14, 20, 38, 230);
  ellipse(x, y, 54 * fk, 54 * fk);
  color c = mzLock ? color(245, 185, 66) : color(150, 165, 190);
  fill(c);
  rect(x - 10 * fk, y - 2 * fk, 20 * fk, 15 * fk);
  noFill();
  stroke(c);
  strokeWeight(2.6 * fk);
  beginShape();
  float sx = mzLock ? 0 : 5 * fk;                    // FREE: the shackle lifted, to one side
  for (int i = 0; i <= 12; i++) {
    float a = PI + PI * i / 12.0;
    vertex(x + sx + cos(a) * 7 * fk, y - 2 * fk - (mzLock ? 0 : 5 * fk) + sin(a) * 9 * fk);
  }
  endShape();
  noStroke();
  fill(#8FA3B8);
  textAlign(LEFT, CENTER);
  textSizeQ(16 * fk);
  text(mzLock ? "LOCK" : "FREE", x + 34 * fk, y);
}

// The CPU fallback (desktop 1.5.1, and a phone without WebGL): the shell drawn as glass-tube lines.
void drawShellVec(int ball, int sh, float cx, float cy, float Rs, float al) {
  if (al <= 0.01 || Rs < 4) return;
  noStroke();
  for (int i = 12; i >= 1; i--) {                          // halo
    float t = i / 12.0;
    fill(30, 90, 255, 8 * al);
    ellipse(cx, cy, 2 * Rs * (1 + 0.28 * t), 2 * Rs * (1 + 0.28 * t));
  }
  for (int i = 10; i >= 1; i--) {                          // glass body, darker at the centre
    float t = i / 10.0;
    fill(8 + 10 * t, 20 + 20 * t, 60 + 40 * t, 26 * al);
    ellipse(cx, cy, 2 * Rs * t, 2 * Rs * t);
  }

  // where the doors are (the notifications) and the fingerprint loop's opening
  buildOpen(ball, sh);

  // project every ridge point once
  for (int k = 0; k < MZ_RIDGES; k++) {
    for (int j = 0; j < MZ_SAMP; j++) {
      float phi = TWO_PI * j / MZ_SAMP;
      float rho = mzRho(sh, k, phi);
      float x = sin(rho) * sin(phi), y = -sin(rho) * cos(phi), z = cos(rho);
      int q = k * MZ_SAMP + j;
      float rz = mzRot[6] * x + mzRot[7] * y + mzRot[8] * z;
      mzPX[q] = cx + (mzRot[0] * x + mzRot[1] * y + mzRot[2] * z) * Rs;
      mzPY[q] = cy + (mzRot[3] * x + mzRot[4] * y + mzRot[5] * z) * Rs;
      mzPZ[q] = rz;
    }
  }

  // glass tubes: shadow, glow, rim, body, core, highlight (light from the top left)
  float W = Rs * 0.072;
  for (int pass = 0; pass < 6; pass++) {
    float ox = 0, oy = 0;
    if (pass == 0) { ox = W * 0.22; oy = W * 0.3; }
    if (pass == 5) { ox = -W * 0.16; oy = -W * 0.2; }
    for (int k = 0; k < MZ_RIDGES; k++) {
      for (int j0 = 0; j0 < MZ_SAMP; j0 += 12) {
        int qc = k * MZ_SAMP + j0;
        float zm = mzPZ[qc];
        if (zm < 0.02) continue;
        int qe = k * MZ_SAMP + ((j0 + 12) % MZ_SAMP);       // off screen: skip the run
        if ((mzPX[qc] < -W * 4 && mzPX[qe] < -W * 4) || (mzPX[qc] > width + W * 4 && mzPX[qe] > width + W * 4)
          || (mzPY[qc] < FY(200) - W * 4 && mzPY[qe] < FY(200) - W * 4) || (mzPY[qc] > mazeBottom() + W * 4 && mzPY[qe] > mazeBottom() + W * 4)) continue;
        mzTubeStyle(ball, pass, W * (0.55 + 0.45 * zm), (0.3 + 0.7 * zm) * al);
        boolean on = false;
        for (int j = j0; j <= j0 + 12; j++) {
          int q = k * MZ_SAMP + (j % MZ_SAMP);
          if (mzPZ[q] < 0.0 || mzOpen[q]) {
            if (on) { endShape(); on = false; }
            continue;
          }
          if (!on) { beginShape(); on = true; }
          vertex(mzPX[q] + ox, mzPY[q] + oy);
        }
        if (on) endShape();
      }
    }
    // walls: mirrored, staggered quarter-hour marks (mzWall)
    for (int k = MZ_CORE; k < MZ_RIDGES - 1; k++) {
      for (int j = 0; j < MZ_SAMP; j++) {
        if (!mzWall(k, j)) continue;
        int qa = k * MZ_SAMP + j, qb = (k + 1) * MZ_SAMP + j;
        if (mzPZ[qa] < 0.02 || mzPZ[qb] < 0.02 || mzOpen[qa] || mzOpen[qb]) continue;
        mzTubeStyle(ball, pass, W * (0.55 + 0.45 * mzPZ[qa]), (0.3 + 0.7 * mzPZ[qa]) * al);
        line(mzPX[qa] + ox, mzPY[qa] + oy, mzPX[qb] + ox, mzPY[qb] + oy);
      }
    }
  }
  noStroke();

  // red specks in the dark grooves (the concept's circuit glints)
  for (int i = 0; i < 260; i++) {
    float u1 = mzHash(i, 3 + sh * 7), u2 = mzHash(i, 4 + sh * 7);
    float zz = 1 - 2 * u1, rr = sqrt(max(0, 1 - zz * zz)), ph = TWO_PI * u2;
    float x = rr * cos(ph), y = rr * sin(ph);
    float rz = mzRot[6] * x + mzRot[7] * y + mzRot[8] * zz;
    if (rz < 0.1) continue;
    float sx = cx + (mzRot[0] * x + mzRot[1] * y + mzRot[2] * zz) * Rs, sy = cy + (mzRot[3] * x + mzRot[4] * y + mzRot[5] * zz) * Rs;
    if (sx < 0 || sx > width || sy < FY(200) || sy > mazeBottom()) continue;
    float d = max(2.4 * fk, Rs * 0.006);
    fill(255, 80, 50, 70 * al * rz);
    ellipse(sx, sy, d * 2.6, d * 2.6);
    fill(255, 120, 80, 210 * al * rz);
    ellipse(sx, sy, d, d);
  }

  // the core: warm light at the pole
  float pz = mzRot[8];
  if (pz > 0) {
    float px = cx + mzRot[2] * Rs, py = cy + mzRot[5] * Rs;
    for (int i = 16; i >= 1; i--) {
      float t = i / 16.0;
      fill(255, 100 + 60 * (1 - t), 30, 16 * al * pz);
      ellipse(px, py, Rs * 0.42 * t, Rs * 0.62 * t);
    }
    fill(255, 235, 200, 240 * al * pz);
    ellipse(px, py, Rs * 0.05, Rs * 0.09);
  }

  // the glass over it all: a window reflection top left, a lit rim
  for (int i = 0; i < 10; i++) {
    fill(255, 255, 255, 5 * al);
    ellipse(cx - Rs * 0.38, cy - Rs * 0.5, Rs * (0.9 - i * 0.07), Rs * (0.42 - i * 0.03));
  }
  noFill();
  stroke(255, 255, 255, 90 * al);
  strokeWeight(3 * fk);
  arcPath(cx, cy, Rs * 0.93, PI + 0.35, PI + 1.3);
  stroke(120, 190, 255, 150 * al);
  strokeWeight(2.4 * fk);
  ellipse(cx, cy, 2 * Rs, 2 * Rs);
  stroke(255, 150, 70, 80 * al);
  strokeWeight(3 * fk);
  arcPath(cx, cy, Rs * 0.985, -0.6, 0.7);
  noStroke();
}


// the beads of one shell, inside its lens: glass, glowing in the app's state colour, the app's icon inside
void drawBeads(int ball, int sh, float cx, float cy, float Rs, float al, float clip) {
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    if (n.ball != ball || n.shell != sh) continue;
    float rz = mzRot[6] * n.dx + mzRot[7] * n.dy + mzRot[8] * n.dz;
    n.sx = cx + (mzRot[0] * n.dx + mzRot[1] * n.dy + mzRot[2] * n.dz) * Rs;
    n.sy = cy + (mzRot[3] * n.dx + mzRot[4] * n.dy + mzRot[5] * n.dz) * Rs;
    n.sz = rz;
    if (rz < 0.05) continue;
    float d = mzBead(Rs, clip) * (0.55 + 0.45 * rz);
    if (dist(n.sx, n.sy, cx, cy) > clip - d * 0.3) continue;            // outside the lens
    if (n.sy < FY(160) || n.sy > height) continue;
    n.sd = d;
    AppIcon a = appFor(n.e.pkg);
    boolean rem = n.e.src.equals("REMIND");
    String st = rem ? "active" : appState(a);
    color c = ball == B_FUTURE ? color(190, 215, 255) : st.equals("uninstalled") ? color(150, 150, 160) : st.equals("archived") ? color(170, 120, 255) : st.equals("dormant") ? color(230, 140, 60) : ball == B_PRESENT ? color(80, 240, 150) : color(255, 135, 50);
    for (int g = 3; g >= 1; g--) {
      fill(red(c), green(c), blue(c), 34 * al * rz);
      ellipse(n.sx, n.sy, d * (1 + g * 0.35), d * (1 + g * 0.35));
    }
    fill(red(c) * 0.3, green(c) * 0.3, blue(c) * 0.3, 235 * al);
    ellipse(n.sx, n.sy, d, d);
    if (rem) icoClock(n.sx, n.sy, d * 0.24, color(230, 240, 255));
    else if (d > 44 * fk && rz > 0.35 && al > 0.5) drawAppIconAt(a, n.sx - d * 0.3, n.sy - d * 0.3, d * 0.6);
    else {
      fill(min(255, red(c) + 60), min(255, green(c) + 70), min(255, blue(c) + 70), 255 * al);
      ellipse(n.sx, n.sy, d * 0.45, d * 0.45);
    }
    noFill();
    stroke(red(c), green(c), blue(c), 220 * al);
    strokeWeight(max(1.5 * fk, d * 0.06));
    ellipse(n.sx, n.sy, d, d);
    noStroke();
    fill(255, 255, 255, 150 * al);
    ellipse(n.sx - d * 0.2, n.sy - d * 0.24, d * 0.3, d * 0.16);
    if (ball == B_FUTURE && al > 0.5 && d > 40 * fk) {                  // how far ahead
      String lbl = inLabel(n.when);
      textSizeQ(max(14 * fk, d * 0.26));
      float lw = textWidth(lbl) + 14 * fk;
      fill(10, 16, 32, 220 * al);
      rrect(n.sx - lw * 0.5, n.sy + d * 0.58, lw, d * 0.36, d * 0.18);
      fill(220, 235, 255, 255 * al);
      textAlign(CENTER, CENTER);
      text(lbl, n.sx, n.sy + d * 0.76 - 1 * fk);
    }
    if (n.e.selected) {
      noFill();
      stroke(245, 185, 66, 255 * al);
      strokeWeight(3 * fk);
      ellipse(n.sx, n.sy, d * 1.45, d * 1.45);
      noStroke();
    }
    if (n.e == mzSel) {
      noFill();
      stroke(255, 255, 255, 230 * al);
      strokeWeight(2.4 * fk);
      float p = 1 + 0.1 * sin(millis() / 180.0);
      ellipse(n.sx, n.sy, d * 1.75 * p, d * 1.75 * p);
      noStroke();
    }
  }
}

// bead size: grows with the zoom, up to app-icon size; never more than a third of the lens
float mzBead(float Rs, float clip) { return min(constrain(Rs * 0.12, 26 * fk, 140 * fk), clip * 0.34); }

// the six passes of a glass tube (the CPU fallback), coloured per ball
void mzTubeStyle(int ball, int pass, float w, float a) {
  color edge = ball == B_PAST ? color(255, 170, 90) : ball == B_PRESENT ? color(90, 255, 170) : color(200, 220, 255);
  color rim = ball == B_PAST ? color(110, 50, 20) : ball == B_PRESENT ? color(10, 90, 50) : color(70, 80, 100);
  color body = ball == B_PAST ? color(190, 100, 40) : ball == B_PRESENT ? color(30, 170, 100) : color(150, 160, 180);
  color core = ball == B_PAST ? color(240, 160, 90) : ball == B_PRESENT ? color(110, 240, 170) : color(220, 230, 245);
  if (pass == 0) { stroke(0, 0, 10, 110 * a); strokeWeight(w * 1.05); }
  else if (pass == 1) { stroke(red(edge), green(edge), blue(edge), 26 * a); strokeWeight(w * 1.4); }
  else if (pass == 2) { stroke(red(rim), green(rim), blue(rim), 240 * a); strokeWeight(w); }
  else if (pass == 3) { stroke(red(body), green(body), blue(body), 235 * a); strokeWeight(w * 0.72); }
  else if (pass == 4) { stroke(red(core), green(core), blue(core), 220 * a); strokeWeight(w * 0.4); }
  else { stroke(240, 250, 255, 190 * a); strokeWeight(w * 0.14); }
}

// the depth gauge (full screen), right side: the first day at the top (PAST: latest; FUTURE: the soonest)
float gTop() { return FY(250); }
float gBot() { return mazeBottom() - 40 * fk; }

void drawDepthGauge() {
  float x = FX(806), t = gTop(), b = gBot();
  String[] days = mzDays();
  int n = max(1, days.length);
  fill(12, 18, 34, 220);
  rrect(x - 14 * fk, t - 16 * fk, 28 * fk, b - t + 32 * fk, 14 * fk);
  stroke(60, 110, 220, 160);
  strokeWeight(2 * fk);
  line(x, t, x, b);
  noStroke();
  for (int i = 0; i < n; i++) {
    float y = n == 1 ? t : lerp(t, b, i / (float) (n - 1));
    fill(i == mzShell ? #4DA3FF : #3A5590);
    rect(x - 7 * fk, y - 1 * fk, 14 * fk, 2 * fk);
  }
  fill(#8FA3B8);
  textAlign(RIGHT, CENTER);
  textSizeQ(16 * fk);
  text(mzBall == B_FUTURE ? "SOONEST" : "LATEST", x - 24 * fk, t);
  if (n > 1) text(n + " days", x - 24 * fk, b);
  float dep = constrain(max(0, mzZB[mzBall]) / LOGM, 0, n - 1);
  float my = n == 1 ? t : lerp(t, b, dep / (n - 1));
  for (int i = 4; i >= 1; i--) {
    fill(255, 140, 50, 30);
    ellipse(x, my, (18 + i * 7) * fk, (18 + i * 7) * fk);
  }
  fill(#FFB070);
  ellipse(x, my, 18 * fk, 18 * fk);
  String lbl = days.length > mzShell ? (days[mzShell].equals(today()) ? "Today" : longDate(days[mzShell])) : "";
  textSizeQ(18 * fk);
  float lw = textWidth(lbl) + 26 * fk;
  fill(20, 26, 44, 235);
  rrect(x - 30 * fk - lw, my - 18 * fk, lw, 36 * fk, 18 * fk);
  fill(#FFD9B0);
  textAlign(CENTER, CENTER);
  text(lbl, x - 30 * fk - lw * 0.5, my - 1 * fk);
}

// pinch (from the page): ratio > 1 = fingers apart = zoom in. It zooms the ball under the fingers.
void pinchStart() {
  poke();
  if (chatOn) return;                              // CHATNOTE: chatPinch
  moved = true;
  dragMode = D_NONE;
  mzPinching = true;
  if (tab == T_ARCHIVE && flatTab()) {
    int b = ballAt(mouseX, mouseY);
    if (b >= 0) bringForward(b);
  }
}

void pinch(float ratio) {
  poke();
  if (chatOn) { chatPinch(ratio); return; }
  if (tab != T_ARCHIVE || !flatTab()) return;
  int b = mzBall;
  mzZB[b] = constrain(mzZB[b] + log(max(0.2, ratio)) * 1.15, zMinB(b), zMaxB(b));
  mzZBT[b] = mzZB[b];
}

void pinchEnd() {
  mzPinching = false;
  mzZBT[mzBall] = mzZB[mzBall];
  mzDragBall = -2;
}

// + / -: zoom the front ball a step
void mazeDive(int d) {
  int b = mzBall;
  mzZBT[b] = constrain(mzZBT[b] + d * 0.45, zMinB(b), zMaxB(b));
}

float mazeBottom() { return barY - 10 * u - 190 * fk; }

// right-aligned pill buttons along the top; returns the next x to the left
float[] mzBtnX = new float[6];
float mazeButton(float right, float y, String lbl, color c, int i) {
  textSizeQ(19 * fk);
  float w = textWidth(lbl) + 36 * fk, h = 46 * fk;
  float x = right - w;
  fill(red(c) * 0.22, green(c) * 0.22, blue(c) * 0.22, 235);
  rrect(x, y, w, h, h * 0.5);
  stroke(red(c), green(c), blue(c), 200);
  strokeWeight(1.5 * fk);
  rrectLine(x, y, w, h, h * 0.5);
  noStroke();
  fill(#F4F7FF);
  textAlign(CENTER, CENTER);
  text(lbl, x + w * 0.5, y + h * 0.5 - 1 * fk);
  mzBtnX[i * 2] = x;
  mzBtnX[i * 2 + 1] = x + w;
  return x - 10 * fk;
}

// an app's state, asked once a minute (Android knows: installed, archived, last used)
String appState(AppIcon a) {
  if (a.statusAt < 0 || millis() - a.statusAt > 60000) {
    if (iconBudget > 0 || a.statusAt < 0) {
      if (iconBudget > 0) iconBudget--;
      a.statusAt = millis();
      a.status = (js != null) ? js.appStatus(a.pkg) : "installed";
    }
  }
  return a.status;
}

void drawMazeCard(Entry e) {
  float x = FX(40), y = mazeBottom() + 8 * fk, w = 772 * fk, h = 176 * fk;
  AppIcon a = appFor(e.pkg);
  String st = appState(a);
  glassCard(x, y, w, h, 34 * fk, color(255, 140, 60));
  drawAppIconAt(a, x + 24 * fk, y + 24 * fk, 64 * fk);
  fill(#F4F7FF);
  textAlign(LEFT, BASELINE);
  textSizeQ(28 * fk);
  String name = e.src.equals("MANUAL") ? "Manual entry" : a.label;
  boldTextF(fitText(name, 300 * fk), x + 108 * fk, y + 50 * fk);
  // state chip
  String sl = st.equals("installed") ? "INSTALLED" : st.equals("iphone") ? "iPHONE" : st.toUpperCase();
  color sc = st.equals("iphone") ? color(77, 163, 255) : st.equals("active") ? color(61, 220, 151) : st.equals("dormant") ? color(245, 185, 66) : st.equals("archived") ? color(170, 120, 255) : st.equals("uninstalled") ? color(255, 107, 107) : color(140, 160, 190);
  textSizeQ(16 * fk);
  float cw = textWidth(sl) + 24 * fk;
  float chx = x + 108 * fk + min(textWidthAt(name, 28 * fk), 300 * fk) + 18 * fk;
  fill(red(sc) * 0.2, green(sc) * 0.2, blue(sc) * 0.2);
  rrect(chx, y + 26 * fk, cw, 32 * fk, 16 * fk);
  fill(sc);
  textAlign(CENTER, CENTER);
  text(sl, chx + cw * 0.5, y + 41 * fk);
  fill(#C9D3E6);
  textAlign(LEFT, BASELINE);
  textSizeQ(21 * fk);
  String body = e.title.length() > 0 && !e.title.equals(name) ? e.title + ": " + e.body : e.body;
  text(fitText(body, 420 * fk), x + 108 * fk, y + 88 * fk);
  fill(#8A93C6);
  textSizeQ(19 * fk);
  text(longDate(e.ymd) + "  ·  " + ampm(e.time) + "  ·  " + e.pkg, x + 108 * fk, y + 122 * fk);
  text(fitText(stateLine(st), 440 * fk), x + 108 * fk, y + 152 * fk);
  // LAUNCH / SELECT
  if (!st.equals("iphone")) mazeCardBtn(0, st.equals("uninstalled") ? "GONE" : "LAUNCH", st.equals("uninstalled") ? color(110, 110, 120) : color(255, 140, 60));
  mazeCardBtn(1, e.selected ? "SELECTED" : "SELECT", color(245, 185, 66));
}

String stateLine(String st) {
  if (st.equals("iphone")) return "From your iPhone, over Bluetooth";
  if (st.equals("active")) return "Active: used in the last 30 days";
  if (st.equals("dormant")) return "Dormant: installed, not used for 30+ days";
  if (st.equals("archived")) return "Archived by Android: tap LAUNCH to restore it";
  if (st.equals("uninstalled")) return "Uninstalled: this app is no longer on the phone";
  return "Installed (turn on Usage access to see active / dormant)";
}

float textWidthAt(String s, float sz) {
  textSizeQ(sz);
  return textWidth(s);
}

float[] mazeCardBtnRect(int i) {
  float x = FX(40), y = mazeBottom() + 8 * fk, w = 772 * fk;
  float[] r = new float[4];
  r[2] = 150 * fk;
  r[3] = 48 * fk;
  r[0] = x + w - 24 * fk - r[2];
  r[1] = y + 24 * fk + i * 62 * fk;
  return r;
}

void mazeCardBtn(int i, String lbl, color c) {
  float[] r = mazeCardBtnRect(i);
  fill(red(c) * 0.25, green(c) * 0.25, blue(c) * 0.25, 240);
  rrect(r[0], r[1], r[2], r[3], r[3] * 0.5);
  stroke(red(c), green(c), blue(c), 220);
  strokeWeight(1.6 * fk);
  rrectLine(r[0], r[1], r[2], r[3], r[3] * 0.5);
  noStroke();
  fill(#FFFFFF);
  textAlign(CENTER, CENTER);
  textSizeQ(19 * fk);
  text(lbl, r[0] + r[2] * 0.5, r[1] + r[3] * 0.5 - 1 * fk);
}

boolean inRect(float mx, float my, float[] r) {
  return mx >= r[0] - 6 * fk && mx <= r[0] + r[2] + 6 * fk && my >= r[1] - 6 * fk && my <= r[1] + r[3] + 6 * fk;
}

// taps on the maze screen
void mazeTap(float mx, float my) {
  mzDragBall = -2;
  if (my >= FY(96) && my <= FY(160)) {                       // header buttons
    if (mx >= mzBtnX[0] && mx <= mzBtnX[1]) {                 // EXPORT
      if (selectedCount() > 0) {
        if (js != null) js.exportPngmesh(selectedLines());
        else dumpSelected();
        clearSelection();
      }
      else { appMsg = "Select beads in the maze first"; appMsgAt = millis(); }
      return;
    }
    if (mx >= mzBtnX[2] && mx <= mzBtnX[3]) {                 // IMPORT
      if (js != null) js.importFiles();
      else println("IMPORT: phone only");
      return;
    }
    if (mx >= mzBtnX[4] && mx <= mzBtnX[5]) {                 // PICKED / ALL
      filterOn = !filterOn;
      mzSel = null;
      return;
    }
  }
  float zx = FX(62), zy = mazeBottom() - 120 * fk;
  if (dist(mx, my, zx, zy) < 34 * fk) { mazeDive(1); return; }            // + zoom in
  if (dist(mx, my, zx, zy + 66 * fk) < 34 * fk) { mazeDive(-1); return; } // - zoom out
  if (!mzFullOpen && dist(mx, my, zx, zy - 76 * fk) < 34 * fk) {         // LOCK / FREE
    mzLock = !mzLock;
    savePref("eflock", mzLock ? "1" : "0");
    return;
  }
  if (mzFullOpen && mzDays().length > 1 && mx > FX(770) && my > gTop() - 24 * fk && my < gBot() + 24 * fk) {   // the depth gauge
    int n = mzDays().length;
    int to = constrain(round((my - gTop()) / (gBot() - gTop()) * (n - 1)), 0, n - 1);
    mzZBT[mzBall] = to * LOGM;
    mzSel = null;
    return;
  }
  if (mzSel != null && my > mazeBottom()) {
    if (inRect(mx, my, mazeCardBtnRect(0)) && !appState(appFor(mzSel.pkg)).equals("iphone")) {
      AppIcon a = appFor(mzSel.pkg);
      if (!mzSel.src.equals("REMIND") && !appState(a).equals("uninstalled")) openApp(a);
      return;
    }
    if (inRect(mx, my, mazeCardBtnRect(1))) { mzSel.selected = !mzSel.selected; return; }
    return;
  }
  if (my < FY(200) || (mzFullOpen && my > mazeBottom())) return;
  // the nearest bead drawn
  float best = 30 * fk;
  MazeNode hit = null;
  for (int i = 0; i < mzNodes.size(); i++) {
    MazeNode n = (MazeNode) mzNodes.get(i);
    if (n.sd <= 0) continue;
    float d = dist(mx, my, n.sx, n.sy) - n.sd * 0.5;
    if (d < best) { best = d; hit = n; }
  }
  if (hit != null) {
    mzSel = hit.e;
    if (!mzFullOpen) bringForward(hit.ball);
    return;
  }
  // a ball: bring it forward (Full screen: open it)
  int b = ballAt(mx, my);
  if (b >= 0 && !mzFullOpen) {
    if (efFull) openFull(b);
    else bringForward(b);
    return;
  }
  mzSel = null;
}

// drag: turn the ball under the finger (LOCK: all three), so its surface follows the finger
void mazeDrag(float dx, float dy) {
  if (mzDragBall == -2) mzDragBall = ballAt(pressX, pressY);
  int b = mzDragBall >= 0 ? mzDragBall : mzBall;
  if (mzDragBall < 0 && !mzLock && !mzFullOpen) return;     // FREE, and not on a ball: nothing to turn
  float[] v = ballView(b);
  float R = max(v[3], 40 * fk);
  float ax = -dx / R, ay = -dy / R;
  for (int k = 0; k < 3; k++) {
    if (k != b && (!mzLock || mzFullOpen)) continue;
    mzTurn(k, ax, ay);
    mzVXB[k] = ax;
    mzVYB[k] = ay;
  }
}

void mazeRelease() { mzDragBall = -2; }

// is anything on the maze screen still moving? (the frame governor asks)
boolean mazeBusy() {
  if (mzPinching || (mzFullOpen && mzOpenT < 1)) return true;
  for (int b = 0; b < 3; b++) {
    if (mzVXB[b] != 0 || mzVYB[b] != 0 || mzZB[b] != mzZBT[b] || mzLensR[b] != lensTarget(b)) return true;
    if (millis() - mzFlashAt[b] < 500) return true;
  }
  return false;
}
