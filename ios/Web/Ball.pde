// ============================================================
// Ball.pde  —  the ANA control ball
//
// Built from BallGUI (BalGUI_load_MT8_LUT_anmation_physics, Processing 1.5.1). From that sketch:
// the ray-sphere maths, the lighting (diffuse, specular, rim, gloss streak), the luma bump,
// the bezel rings, the compass ring, the glow button / slider / toggle drawing, the trig LUT
// and the YES-nod / NO-shake engines.
//
// Changed so it runs in the phone's WebView (Processing.js has one thread):
//  - no thread pool: one pass, over the ball's own square only
//  - the ray-sphere hit of each pixel is worked out once (it changes only with the ball's size)
//  - the ball is traced again only when it moves or its texture changes. While it moves the
//    bump is skipped (draft); one full pass with the bump runs when it stops
//  - the GUI texture covers the front half of the ball, 1024 x 1024 (about 1 texel per pixel at
//    the centre on a phone); the back half shows the skin
//  - a tap is found from the texture position under the finger (no hit-buffer image, because
//    the browser smooths the edges of shapes and would mix the IDs)
//  - on the phone the shading runs on the GPU (glball.js, WebGL, like GLGraphics): every pixel, bump
//    included, 4 samples per pixel, every frame. The CPU trace below stays for the desktop and as the
//    fallback when a phone has no WebGL.
// ============================================================

// ── HIGH RESOLUTION TRIG LOOK-UP TABLES (LUT) ────────────────
final int LUT_SIZE = 7200;
float[] sinLUT = new float[LUT_SIZE];
float[] cosLUT = new float[LUT_SIZE];
float lutScale = LUT_SIZE / TWO_PI;

float fastSin(float a) {
  int idx = (int)(a * lutScale) % LUT_SIZE;
  if (idx < 0) idx += LUT_SIZE;
  return sinLUT[idx];
}

float fastCos(float a) {
  int idx = (int)(a * lutScale) % LUT_SIZE;
  if (idx < 0) idx += LUT_SIZE;
  return cosLUT[idx];
}

// ── light ────────────────────────────────────────────────────
float LX = -0.55, LY = -0.75, LZ = -0.35;
float HX, HY, HZ;                 // half vector, normalised once

// ── camera / ball (BallGUI: camDist 500, BALL_R at VOL 60%) ──
float BALL_R = 176;
float camDist = 500;
float fov = 460;                  // set so the ball fills sr pixels on screen
float brtVal = 0.45;              // LID

// ── animation engines ───────────────────────────────────────
// BallGUI counted these in frames (24 = 0.4 s at 60 fps). Here they run on the clock, so a slow
// phone shows the same motion, just with fewer frames.
int yesAt = -100000, noAt = -100000, spinAt = -100000;
final int ANIM_MS = 400;          // Length of kinetic response (BallGUI: 24 frames)
final int SPIN_MS = 800;          // one turn when a notification arrives or the tab changes
int lastTick = 0;
float yawOff = 0, rollOff = 0;    // dragging / scrolling turns the ball; it eases back to face you

// ── GUI texture: the front half of the ball ─────────────────
int TW = 1024, TH = 1024;
PGraphics guiTex;
int[] guiPix;
float[] guiLum;
int[] backPix;                    // the same texture before the panel goes on: shown on the back half
int backSkin = -1;
boolean useGL = false, glChecked = false, glFresh = true;
PGraphics backTex;                // the back half's texture for the GPU
boolean guiDirty = true;

// ── skins: 0 = BallGUI's own dark gradient, 1-5 = the data images ──
String[] skinFile = { "", "target.png", "target2.png", "target3.png", "target4.png", "target5.png" };
String[] skinName = { "MIDNIGHT", "GOLD WAVE", "COPPER", "JADE", "AMETHYST", "SLATE" };
int skin = 0;
PImage[] skinImg = new PImage[6];
int[] skinPix;                    // pixels of the current skin image (null for skin 0 / not loaded yet)
int skinW = 0, skinH = 0;
PImage defaultFront;              // skin 0's front gradient

// ── the traced ball ─────────────────────────────────────────
float sr = 150;                   // ball radius on screen, px
float ballCX, ballCY;
int bS = 0, bX0 = 0, bY0 = 0;     // the square the ball is traced in
PImage ballImg;
float[] gA, gNX, gNY, gNZ, gDiff, gSpec, gRim, gGloss;
float rCamX = 999, rCamY = 999, rBrt = -1;
int rPress = -2;
boolean rFull = false;
int pressCtl = 0;                 // control under the finger, lit while pressed

// ── controls on the ball ────────────────────────────────────
final int C_NONE = 0, C_SCAN = 1, C_MANUAL = 2, C_ARMON = 3, C_ARMOFF = 4,
          C_EXPORT = 5, C_IMPORT = 6, C_PICKED = 7, C_ALL = 8, C_SELALL = 9, C_CLEAR = 10,
          C_PREV = 11, C_NEXT = 12, C_TODAY = 13, C_ACCESS = 14, C_LOG = 15, C_LID = 16,
          C_SKINPREV = 17, C_SKINNEXT = 18;
ArrayList ctls = new ArrayList();

class Ctl {
  int id;
  float x, y, w, h;
  Ctl(int id, float x, float y, float w, float h) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
  boolean has(float tx, float ty) {
    return tx >= x && tx <= x + w && ty >= y && ty <= y + h;
  }
}

void ballSetup() {
  for (int i = 0; i < LUT_SIZE; i++) {
    float angle = (i * TWO_PI) / LUT_SIZE;
    sinLUT[i] = sin(angle);
    cosLUT[i] = cos(angle);
  }
  float ll = sqrt(LX*LX + LY*LY + LZ*LZ);
  LX /= ll; LY /= ll; LZ /= ll;
  // BallGUI's half vector h = (-LX, -LY, -(LZ+1)), normalised
  HX = -LX; HY = -LY; HZ = -(LZ + 1);
  float hl = sqrt(HX*HX + HY*HY + HZ*HZ);
  HX /= hl; HY /= hl; HZ /= hl;

  guiTex = createGraphics(TW, TH, JAVA2D);
  guiPix = new int[TW * TH];
  guiLum = new float[TW * TH];

  // skin 0: BallGUI's radial gradient (rebuildGuiTex's background), made once
  defaultFront = createImage(TW, TH, RGB);
  defaultFront.loadPixels();
  for (int y = 0; y < TH; y++) for (int x = 0; x < TW; x++) {
    float dx = (x - TW*0.5) / (TW*0.5), dy = (y - TH*0.5) / (TH*0.5);
    float d = constrain(sqrt(dx*dx + dy*dy), 0, 1);
    defaultFront.pixels[y*TW + x] = cpack((int) lerp(18, 8, d), (int) lerp(26, 12, d), (int) lerp(52, 22, d));
  }
  defaultFront.updatePixels();
}

int cpack(int r, int g, int b) { return 0xff000000 | (r << 16) | (g << 8) | b; }

// ============================================================
// SIZE: work out each pixel's ray-sphere hit once
// ============================================================
void ballLayout(float radiusPx, float cx, float cy) {
  sr = radiusPx;
  ballCX = cx;
  ballCY = cy;
  // silhouette radius = fov * R / sqrt(d^2 - R^2)  ->  fov for the size we want
  fov = sr * sqrt(camDist*camDist - BALL_R*BALL_R) / BALL_R;

  bS = 2 * ceil(sr) + 4;
  bX0 = round(cx - bS * 0.5);
  bY0 = round(cy - bS * 0.5);
  ballImg = createImage(bS, bS, ARGB);

  int n = bS * bS;
  gA = new float[n]; gNX = new float[n]; gNY = new float[n]; gNZ = new float[n];
  gDiff = new float[n]; gSpec = new float[n]; gRim = new float[n]; gGloss = new float[n];

  float half = bS * 0.5;
  float c = camDist*camDist - BALL_R*BALL_R;
  for (int j = 0; j < bS; j++) {
    for (int i = 0; i < bS; i++) {
      int k = j * bS + i;
      float dx = i + 0.5 - half, dy = j + 0.5 - half;
      float a = sr - sqrt(dx*dx + dy*dy) + 0.5;           // soft edge, 1 px
      if (a <= 0) { gA[k] = 0; continue; }
      gA[k] = min(a, 1);

      float rdX = dx / fov, rdY = dy / fov, rdZ = 1.0;
      float mag = 1.0 / sqrt(rdX*rdX + rdY*rdY + rdZ*rdZ);
      rdX *= mag; rdY *= mag; rdZ *= mag;
      float b = -camDist * rdZ;                           // ro = (0, 0, -camDist)
      float disc = b*b - c;
      if (disc < 0) disc = 0;                             // the edge pixel just outside: use the rim
      float t = -b - sqrt(disc);
      float hitX = rdX * t, hitY = rdY * t, hitZ = -camDist + rdZ * t;
      float nX = hitX / BALL_R, nY = hitY / BALL_R, nZ = hitZ / BALL_R;
      float nm = 1.0 / sqrt(nX*nX + nY*nY + nZ*nZ);
      nX *= nm; nY *= nm; nZ *= nm;
      gNX[k] = nX; gNY[k] = nY; gNZ[k] = nZ;

      float diff = -(nX*LX + nY*LY + nZ*LZ);
      gDiff[k] = diff < 0 ? 0 : diff;
      float specTarget = nX*HX + nY*HY + nZ*HZ;
      gSpec[k] = specTarget > 0 ? pow(specTarget, 36) : 0;
      float rimTarget = 1.0 + nZ;
      gRim[k] = rimTarget > 0 ? pow(rimTarget, 2.5) * 0.6 : 0;

      float sx = hitX / BALL_R, sy = hitY / BALL_R;
      float sd2 = sx*sx + sy*sy;
      float g2 = 0;
      if (sd2 < 0.98) {
        float sz = sqrt(max(0, 1.0 - sd2));
        float glossTarget = -sx*0.55 - sy*0.80 + sz*0.05;
        float gloss = glossTarget > 0 ? pow(glossTarget, 14) * 0.9 : 0;
        float stkTarget = -sx*0.45 - sy*0.88;
        float stk = stkTarget > 0 ? pow(stkTarget, 34) * 1.4 : 0;
        g2 = min(gloss + stk, 1.0);
      }
      gGloss[k] = g2;
    }
  }
  rCamX = 999;
  glFresh = true;
}

// ── where the ball faces this frame ─────────────────────────
float ballCamX() {
  float cx = rollOff;
  int t = millis() - yesAt;
  if (t < ANIM_MS) {                       // YES NOD (Pitch/Tilt Offset)
    float progress = (float) t / ANIM_MS;
    cx += sin(progress * TWO_PI * 1.5) * 0.12 * sin(progress * PI);
  }
  return cx;
}

float ballCamY() {
  float cy = yawOff;
  int t = millis() - noAt;
  if (t < ANIM_MS) {                       // NO SHAKE (Yaw/Rotation Offset)
    float progress = (float) t / ANIM_MS;
    cy += sin(progress * TWO_PI * 1.5) * 0.15 * sin(progress * PI);
  }
  t = millis() - spinAt;
  if (t < SPIN_MS) {                       // one eased turn
    float p = (float) t / SPIN_MS;
    cy += TWO_PI * p * p * (3 - 2 * p);
  }
  return cy;
}

void nod()   { yesAt = millis(); }
void shake() { noAt = millis(); }
void spin()  { if (millis() - spinAt >= SPIN_MS) spinAt = millis(); }

// ============================================================
// TRACE: draft while moving, full (with the bump) once it stops
// ============================================================
void drawBall() {
  if (!glChecked) {
    glChecked = true;
    useGL = (js != null) && js.glOk();
  }
  if (guiDirty) rebuildGuiTex();
  float cX = ballCamX(), cY = ballCamY();
  if (useGL) {
    boolean redraw = glFresh || abs(cX - rCamX) > 0.00005 || abs(cY - rCamY) > 0.00005 || brtVal != rBrt || pressCtl != rPress;
    glFresh = false;
    rCamX = cX; rCamY = cY; rBrt = brtVal; rPress = pressCtl;
    float px = 0, py = 0, pw = -1, ph = -1;
    for (int i = 0; i < ctls.size(); i++) {
      Ctl o = (Ctl) ctls.get(i);
      if (o.id == pressCtl) { px = o.x; py = o.y; pw = o.w; ph = o.h; }
    }
    float[] a = { sr, fov, BALL_R, camDist, cX, cY, brtVal, px, py, pw, ph, LX, LY, LZ, HX, HY, HZ, TW, TH };
    js.glBall(bX0, bY0, bS, redraw, a);
    drawBezel();
    return;
  }
  boolean same = abs(cX - rCamX) < 0.0002 && abs(cY - rCamY) < 0.0002 && brtVal == rBrt && pressCtl == rPress;
  if (!same) {
    traceBall(cX, cY, false);
    rFull = false;
  }
  else if (!rFull) {
    traceBall(cX, cY, true);
    rFull = true;
  }
  image(ballImg, bX0, bY0);
  drawBezel();
}

// per-trace constants, set by traceBall for shadePixel
float tCosX, tSinX, tCosY, tSinY, tAmb, tDiff, tSpecS;
Ctl tPress;

// Moving: one shade per 2 x 2 pixels (4x less work, keeps the drag smooth on a phone).
// Still: every pixel, with the bump: 100% pixels.
void traceBall(float cX_, float cY_, boolean full) {
  rCamX = cX_; rCamY = cY_; rBrt = brtVal; rPress = pressCtl;
  tCosX = cos(cX_); tSinX = sin(cX_);
  tCosY = cos(cY_); tSinY = sin(cY_);
  tAmb = 0.06 + (0.75 - 0.06) * brtVal;
  tDiff = 0.40 + (1.85 - 0.40) * brtVal;
  tSpecS = 1.1 + brtVal * 0.6;
  tPress = null;
  for (int i = 0; i < ctls.size(); i++) {
    Ctl o = (Ctl) ctls.get(i);
    if (o.id == pressCtl) tPress = o;
  }

  ballImg.loadPixels();
  if (full) {
    int n = bS * bS;
    for (int k = 0; k < n; k++) {
      float a = gA[k];
      if (a <= 0) ballImg.pixels[k] = 0;
      else ballImg.pixels[k] = ((int)(a * 255) << 24) | shadePixel(k, true);
    }
  }
  else {
    for (int j = 0; j < bS - 1; j += 2) {
      for (int i = 0; i < bS - 1; i += 2) {
        int k = j * bS + i;
        int src = k;
        if (gA[src] <= 0) src = k + bS + 1;
        if (gA[src] <= 0) src = k + 1;
        if (gA[src] <= 0) src = k + bS;
        if (gA[src] <= 0) {
          ballImg.pixels[k] = 0; ballImg.pixels[k + 1] = 0; ballImg.pixels[k + bS] = 0; ballImg.pixels[k + bS + 1] = 0;
          continue;
        }
        int c = shadePixel(src, false);
        ballImg.pixels[k]          = gA[k] > 0 ? ((int)(gA[k] * 255) << 24) | c : 0;
        ballImg.pixels[k + 1]      = gA[k + 1] > 0 ? ((int)(gA[k + 1] * 255) << 24) | c : 0;
        ballImg.pixels[k + bS]     = gA[k + bS] > 0 ? ((int)(gA[k + bS] * 255) << 24) | c : 0;
        ballImg.pixels[k + bS + 1] = gA[k + bS + 1] > 0 ? ((int)(gA[k + bS + 1] * 255) << 24) | c : 0;
      }
    }
  }
  ballImg.updatePixels();
}

// One pixel of the ball (BallGUI's renderSlice body): rotate the normal, find the texture,
// bump (full only), then diffuse + specular + rim + gloss. Returns 0xRRGGBB.
int shadePixel(int k, boolean full) {
  float nX = gNX[k], nY = gNY[k], nZ = gNZ[k];
  float y1 = nY * tCosX - nZ * tSinX;
  float z1 = nY * tSinX + nZ * tCosX;
  float rotNX = nX * tCosY + z1 * tSinY;
  float rotNY = y1;
  float rotNZ = -nX * tSinY + z1 * tCosY;
  if (rotNY > 1) rotNY = 1;
  if (rotNY < -1) rotNY = -1;
  float lon = atan2(rotNX, -rotNZ);
  float lat = asin(rotNY);

  boolean front = lon >= -HALF_PI && lon <= HALF_PI;
  int[] tex = guiPix;
  if (!front) {                          // back half: the skin and compass, no controls
    tex = backPix;
    lon = lon > 0 ? lon - PI : lon + PI;
  }
  float fx = (lon / PI + 0.5) * (TW - 1);
  float fy = (lat / PI + 0.5) * (TH - 1);
  if (fx > TW - 1.001) fx = TW - 1.001;
  if (fy > TH - 1.001) fy = TH - 1.001;
  if (fx < 0) fx = 0;
  if (fy < 0) fy = 0;
  int x0 = (int) fx, y0 = (int) fy;
  float ax = fx - x0, ay = fy - y0;
  int i0 = y0 * TW + x0;
  float w00 = (1 - ax) * (1 - ay), w10 = ax * (1 - ay), w01 = (1 - ax) * ay, w11 = ax * ay;
  float cr, cg, cb;
  if (full || !front) {                  // bilinear (BallGUI's getColorBilinear)
    int p00 = tex[i0], p10 = tex[i0 + 1], p01 = tex[i0 + TW], p11 = tex[i0 + TW + 1];
    cr = ((p00 >> 16) & 0xff) * w00 + ((p10 >> 16) & 0xff) * w10 + ((p01 >> 16) & 0xff) * w01 + ((p11 >> 16) & 0xff) * w11;
    cg = ((p00 >> 8) & 0xff) * w00 + ((p10 >> 8) & 0xff) * w10 + ((p01 >> 8) & 0xff) * w01 + ((p11 >> 8) & 0xff) * w11;
    cb = (p00 & 0xff) * w00 + (p10 & 0xff) * w10 + (p01 & 0xff) * w01 + (p11 & 0xff) * w11;
  }
  else {                                 // nearest while moving
    int p = tex[i0];
    cr = (p >> 16) & 0xff; cg = (p >> 8) & 0xff; cb = p & 0xff;
  }

  float diff = gDiff[k], spec = gSpec[k];
  if (front) {
    if (tPress != null && tPress.has(fx, fy)) {    // pressed: lit up, like BallGUI's yesFlash
      cr = min(255, cr * 1.45 + 30); cg = min(255, cg * 1.45 + 30); cb = min(255, cb * 1.45 + 30);
    }
    if (full) {
      // BallGUI's luma bump: height = brightness of the texture
      float hCenter = guiLum[i0] * w00 + guiLum[i0 + 1] * w10 + guiLum[i0 + TW] * w01 + guiLum[i0 + TW + 1] * w11;
      float du = (hCenter - guiLum[i0 + 1]) * 0.22;
      float dv = (hCenter - guiLum[i0 + TW]) * 0.22;
      float uu = 0.5 + lon / TWO_PI;
      float tanX = -fastSin(uu * TWO_PI);
      float tanZ = fastCos(uu * TWO_PI);
      float bx = nX + tanX * du, by = nY + dv, bz = nZ + tanZ * du;
      float nMag = 1.0 / sqrt(bx*bx + by*by + bz*bz);
      bx *= nMag; by *= nMag; bz *= nMag;
      diff = -(bx*LX + by*LY + bz*LZ);
      if (diff < 0) diff = 0;
      float st = bx*HX + by*HY + bz*HZ;
      spec = st > 0 ? pow(st, 36) : 0;
    }
  }

  float shadeFactor = tAmb + tDiff * diff;
  float sp2 = spec * tSpecS;
  float r = cr * shadeFactor + sp2 * 255;
  float g = cg * shadeFactor + sp2 * 255;
  float bVal = cb * shadeFactor + sp2 * 240;
  float rim = gRim[k];
  r += (60 - r) * rim * 0.45;
  g += (100 - g) * rim * 0.45;
  bVal += (200 - bVal) * rim * 0.65;
  float g2 = gGloss[k];
  if (g2 > 0.005) { r += g2 * 220; g += g2 * 230; bVal += g2 * 255; }

  int ri = r > 255 ? 255 : (r < 0 ? 0 : (int) r);
  int gi = g > 255 ? 255 : (g < 0 ? 0 : (int) g);
  int bi = bVal > 255 ? 255 : (bVal < 0 ? 0 : (int) bVal);
  return (ri << 16) | (gi << 8) | bi;
}

void drawBezel() {
  float k = sr / 173.0;                   // BallGUI's bezel was drawn for a ball about 173 px across
  float cx = ballCX, cy = ballCY;
  noFill();
  stroke(10, 12, 22, 200);    strokeWeight(6 * k);   ellipse(cx, cy, (sr + 8*k) * 2, (sr + 8*k) * 2);
  stroke(55, 65, 85, 220);    strokeWeight(4 * k);   ellipse(cx, cy, (sr + 5*k) * 2, (sr + 5*k) * 2);
  stroke(160, 175, 200, 200); strokeWeight(2.5 * k); ellipse(cx, cy, (sr + 3*k) * 2, (sr + 3*k) * 2);
  stroke(18, 22, 38, 180);    strokeWeight(2 * k);   ellipse(cx, cy, (sr - 1*k) * 2, (sr - 1*k) * 2);
  strokeWeight(1);
  noStroke();
}

// ============================================================
// TAPS: which control is under a screen point, and where on it
// ============================================================
// returns { texture x, texture y } or null when the point is off the ball or on its back
float[] texAt(float mx, float my) {
  int i = (int)(mx - bX0), j = (int)(my - bY0);
  if (i < 0 || j < 0 || i >= bS || j >= bS) return null;
  int k = j * bS + i;
  if (gA[k] < 0.5) return null;
  float cX = rCamX, cY = rCamY;
  float nX = gNX[k], nY = gNY[k], nZ = gNZ[k];
  float y1 = nY * cos(cX) - nZ * sin(cX);
  float z1 = nY * sin(cX) + nZ * cos(cX);
  float rotNX = nX * cos(cY) + z1 * sin(cY);
  float rotNZ = -nX * sin(cY) + z1 * cos(cY);
  float lon = atan2(rotNX, -rotNZ);
  float lat = asin(constrain(y1, -1, 1));
  if (lon < -HALF_PI || lon > HALF_PI) return null;
  float[] t = new float[2];
  t[0] = (lon / PI + 0.5) * (TW - 1);
  t[1] = (lat / PI + 0.5) * (TH - 1);
  return t;
}

Ctl ctlAt(float mx, float my) {
  float[] t = texAt(mx, my);
  if (t == null) return null;
  for (int i = 0; i < ctls.size(); i++) {
    Ctl c = (Ctl) ctls.get(i);
    if (c.has(t[0], t[1])) return c;
  }
  return null;
}

boolean onBall(float mx, float my) {
  return dist(mx, my, ballCX, ballCY) <= sr;
}

// ============================================================
// SKINS
// ============================================================
void setSkin(int s) {
  skin = (s + skinFile.length) % skinFile.length;
  skinPix = null;
  skinW = 0;
  skinH = 0;
  if (skin > 0 && skinImg[skin] == null) {
    if (js != null) skinImg[skin] = loadImage(js.skinData(skinFile[skin]));
    else skinImg[skin] = loadImage(skinFile[skin]);
  }
  guiDirty = true;
}

// Images load in the background in the browser: pick up the pixels once the image has arrived.
void skinPoll() {
  if (skin == 0 || skinPix != null) return;
  PImage im = skinImg[skin];
  if (im == null || im.width <= 0) return;
  im.loadPixels();
  skinW = im.width;
  skinH = im.height;
  skinPix = new int[skinW * skinH];
  for (int i = 0; i < skinPix.length; i++) skinPix[i] = im.pixels[i];
  guiDirty = true;
}

// ============================================================
// GUI TEXTURE  (BallGUI mode 1, one panel per tab)
// ============================================================
void rebuildGuiTex() {
  guiDirty = false;
  guiTex.beginDraw();
  guiTex.smooth();
  drawSkinBase(guiTex);
  boolean newBack = backSkin != skin + (skinPix != null ? 100 : 0);
  if (newBack) {
    backSkin = skin + (skinPix != null ? 100 : 0);
    if (useGL) {
      if (backTex == null) backTex = createGraphics(TW, TH, JAVA2D);
      backTex.beginDraw();
      backTex.smooth();
      drawSkinBase(backTex);
      backTex.endDraw();
    }
    else {
      guiTex.loadPixels();
      if (backPix == null) backPix = new int[TW * TH];
      for (int i = 0; i < TW * TH; i++) backPix[i] = guiTex.pixels[i];
    }
  }

  guiTex.noStroke();
  guiTex.fill(10, 15, 38, skin == 0 ? 215 : 105);   // BallGUI's panel; lighter on a skin so the skin shows
  customRectProcedure(guiTex, 168, 196, 688, 640);

  ctls.clear();
  if (tab == T_PULSE) panelPulse(guiTex);
  else if (tab == T_ARCHIVE) panelArchive(guiTex);
  else if (tab == T_TIMELINE) panelTimeline(guiTex);
  else panelSettings(guiTex);

  guiTex.endDraw();
  if (useGL) {
    js.glTextures(guiTex, newBack ? backTex : null);   // straight from the canvases to the GPU
  }
  else {
    guiTex.loadPixels();
    for (int i = 0; i < TW * TH; i++) {
      int p = guiTex.pixels[i];
      guiPix[i] = p;
      guiLum[i] = (((p >> 16) & 0xff) + ((p >> 8) & 0xff) + (p & 0xff)) * 0.3333;
    }
  }
  rCamX = 999;
  glFresh = true;
}

// the skin and BallGUI's compass ring: the whole back half, and the front half under the panel
void drawSkinBase(PGraphics g) {
  // The front half of the ball shows 2 x 2 of the 4 x 2 skin tiles round the ball.
  if (skin == 0 || skinPix == null) g.image(defaultFront, 0, 0, TW, TH);
  else {
    PImage im = skinImg[skin];
    for (int ty = 0; ty < 2; ty++) for (int tx = 0; tx < 2; tx++) g.image(im, tx * TW * 0.5, ty * TH * 0.5, TW * 0.5, TH * 0.5);
  }
  drawCompass(g);
}

// BallGUI's compass ring, at 2x for the 1024 texture
void drawCompass(PGraphics g) {
  float c = TW * 0.5;
  String[] dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
  for (int i = 0; i < 8; i++) {
    float a = TWO_PI * i / 8 - HALF_PI;
    boolean card = (i % 2 == 0);
    g.stroke(i == 0 ? color(220, 40, 40) : card ? color(160, 175, 205) : color(60, 75, 110));
    g.strokeWeight(card ? 3 : 1.6);
    g.line(c + fastCos(a) * 120, c + fastSin(a) * 120, c + fastCos(a) * 430, c + fastSin(a) * 430);
    if (card) {
      g.noStroke();
      g.fill(i == 0 ? color(220, 40, 40) : color(160, 175, 205));
      g.textAlign(CENTER, CENTER);
      g.textSize(i == 0 ? 44 : 34);
      g.text(dirs[i], c + fastCos(a) * 472, c + fastSin(a) * 472);
    }
  }
  for (int deg = 0; deg < 360; deg += 5) {
    float a = radians(deg - 90);
    boolean maj = (deg % 30 == 0), med = (deg % 10 == 0);
    g.stroke(maj ? color(220, 232, 248) : med ? color(140, 155, 185) : color(80, 95, 125));
    g.strokeWeight(maj ? 3 : 1.6);
    float r0 = maj ? 392 : med ? 408 : 420;
    g.line(c + fastCos(a) * r0, c + fastSin(a) * r0, c + fastCos(a) * 440, c + fastSin(a) * 440);
  }
  g.noStroke();
}

void panelTitle(PGraphics g, String t) {
  g.fill(80, 160, 255);
  g.textAlign(CENTER, CENTER);
  g.textSize(48);
  g.text(t, TW * 0.5, 252);
}

void panelFooter(PGraphics g, String t) {
  g.fill(160, 175, 205);
  g.textAlign(CENTER, CENTER);
  g.textSize(30);
  g.text(t, TW * 0.5, 790);
}

void addBtn(PGraphics g, int id, int x, int y, int w, int h, String lbl, int r, int gg, int b, boolean lit) {
  // BallGUI's YES/NO colours: edge 64%, fill 36%. Lit: full edge, fill 50% (the label is the edge colour)
  drawGlowBtn(g, x, y, w, h, lbl, lit ? color(r, gg, b) : color(r * 0.64, gg * 0.64, b * 0.64),
              lit ? color(r * 0.5, gg * 0.5, b * 0.5) : color(r * 0.36, gg * 0.36, b * 0.36));
  ctls.add(new Ctl(id, x - 12, y - 12, w + 24, h + 24));
}

void addTog(PGraphics g, int id, int x, int y, int w, int h, String lbl, boolean active, color ac) {
  drawTogBtn(g, x, y, w, h, lbl, active, ac);
  ctls.add(new Ctl(id, x - 8, y - 8, w + 16, h + 16));
}

void panelPulse(PGraphics g) {
  panelTitle(g, "PULSE");
  addBtn(g, C_SCAN, 196, 306, 300, 140, "SCAN", 30, 220, 80, false);
  addBtn(g, C_MANUAL, 528, 306, 300, 140, "MANUAL", 245, 185, 66, false);
  addTog(g, C_ARMON, 252, 500, 208, 92, "ARM", armed, color(30, 200, 70));
  addTog(g, C_ARMOFF, 564, 500, 208, 92, "OFF", !armed, color(200, 35, 35));
  panelFooter(g, "Listener: " + status);
}

void panelArchive(PGraphics g) {
  panelTitle(g, "ARCHIVE");
  int nSel = selectedCount();
  addBtn(g, C_EXPORT, 196, 306, 300, 140, nSel > 0 ? "EXPORT " + nSel : "EXPORT", 245, 185, 66, nSel > 0);
  addBtn(g, C_IMPORT, 528, 306, 300, 140, "IMPORT", 180, 140, 255, false);
  addTog(g, C_PICKED, 252, 494, 208, 84, "PICKED", filterOn, color(77, 163, 255));
  addTog(g, C_ALL, 564, 494, 208, 84, "ALL", !filterOn, color(77, 163, 255));
  addTog(g, C_SELALL, 220, 618, 270, 84, "SELECT ALL", allShownSelected(), color(245, 185, 66));
  addTog(g, C_CLEAR, 534, 618, 270, 84, "CLEAR", false, color(245, 185, 66));
  panelFooter(g, nSel + " selected");
}

void panelTimeline(PGraphics g) {
  panelTitle(g, "TIMELINE");
  g.fill(232, 238, 245);
  g.textAlign(CENTER, CENTER);
  g.textSize(60);
  g.text(tlDay.equals(today()) ? "TODAY" : tlDay, TW * 0.5, 350);
  addBtn(g, C_PREV, 196, 430, 300, 130, "< OLDER", 242, 176, 97, false);
  addBtn(g, C_NEXT, 528, 430, 300, 130, "NEWER >", 242, 176, 97, false);
  addTog(g, C_TODAY, 408, 612, 208, 84, "TODAY", tlDay.equals(today()), color(242, 176, 97));
  panelFooter(g, countDay(tlDay) + " on this day");
}

void panelSettings(PGraphics g) {
  panelTitle(g, "SETTINGS");
  addBtn(g, C_ACCESS, 196, 306, 300, 130, "ACCESS", 77, 163, 255, false);
  addBtn(g, C_LOG, 528, 306, 300, 130, "LOG", 160, 175, 205, false);
  drawSlider(g, 214, 480, 596, 68, "LID", brtVal);
  ctls.add(new Ctl(C_LID, 290, 460, 440, 108));
  addTog(g, C_SKINPREV, 220, 604, 160, 84, "<", false, color(160, 175, 205));
  addTog(g, C_SKINNEXT, 644, 604, 160, 84, ">", false, color(160, 175, 205));
  g.fill(232, 238, 245);
  g.textAlign(CENTER, CENTER);
  g.textSize(34);
  g.text("SKIN", TW * 0.5, 628);
  g.fill(160, 175, 205);
  g.textSize(26);
  g.text(skinName[skin], TW * 0.5, 668);
  panelFooter(g, "Pick the apps to show below");
}

// slider value from a texture x (the track of drawSlider at x 214, w 596)
float sliderVal(float tx) {
  int lw = 92, sw = 596 - lw - 108;
  return constrain((tx - (214 + lw)) / sw, 0, 1);
}

// ── BallGUI's widgets, at 2x ─────────────────────────────────
void customRectProcedure(PGraphics g, float x, float y, float w, float h) {
  g.quad(x, y, x + w, y, x + w, y + h, x, y + h);
}

void drawGlowBtn(PGraphics g, int x, int y, int w, int h, String lbl, color edge, color fill_) {
  g.noStroke(); g.fill(red(edge), green(edge), blue(edge), 45);
  customRectProcedure(g, x - 12, y - 12, w + 24, h + 24);
  g.fill(red(fill_), green(fill_), blue(fill_)); customRectProcedure(g, x, y, w, h);
  g.fill(255, 255, 255, 22); customRectProcedure(g, x, y, w, h / 3.0);
  g.noFill(); g.stroke(red(edge), green(edge), blue(edge), 240); g.strokeWeight(5); customRectProcedure(g, x, y, w, h);
  g.noStroke(); g.fill(red(edge), green(edge), blue(edge)); g.textAlign(CENTER, CENTER); g.textSize(lbl.length() > 5 ? 42 : 50); g.text(lbl, x + w * 0.5, y + h * 0.5);
}

void drawSlider(PGraphics g, int x, int y, int w, int h, String lbl, float val) {
  int lw = 92, sw = w - lw - 108;
  g.noStroke(); g.fill(80, 160, 255); g.textAlign(RIGHT, CENTER); g.textSize(36);
  g.text(lbl, x + lw - 8, y + h * 0.5);
  g.fill(18, 26, 52); customRectProcedure(g, x + lw, y + h * 0.5 - 14, sw, 28);
  g.fill(30, 130, 255); customRectProcedure(g, x + lw, y + h * 0.5 - 14, sw * val, 28);
  float kx = x + lw + sw * val;
  g.fill(0, 0, 0, 80); g.ellipse(kx + 4, y + h * 0.5 + 4, 44, 44);
  g.fill(190, 205, 230); g.ellipse(kx, y + h * 0.5, 44, 44);
  g.fill(255, 255, 255, 120); g.ellipse(kx - 6, y + h * 0.5 - 6, 20, 20);
  g.fill(190, 205, 230); g.textAlign(LEFT, CENTER); g.textSize(32);
  g.text((int)(val * 100) + "%", x + lw + sw + 16, y + h * 0.5);
}

void drawTogBtn(PGraphics g, int x, int y, int w, int h, String lbl, boolean active, color ac) {
  g.noStroke();
  if (active) {
    g.fill(red(ac), green(ac), blue(ac), 50); customRectProcedure(g, x - 8, y - 8, w + 16, h + 16);
    g.fill(red(ac) * 0.18, green(ac) * 0.18, blue(ac) * 0.18); customRectProcedure(g, x, y, w, h);
    g.noFill(); g.stroke(red(ac), green(ac), blue(ac), 230); g.strokeWeight(4); customRectProcedure(g, x, y, w, h);
    g.noStroke(); g.fill(red(ac), green(ac), blue(ac));
  }
  else {
    g.fill(22, 32, 58); customRectProcedure(g, x, y, w, h);
    g.noFill(); g.stroke(45, 58, 88, 200); g.strokeWeight(3); customRectProcedure(g, x, y, w, h);
    g.noStroke(); g.fill(65, 80, 110);
  }
  g.textAlign(CENTER, CENTER); g.textSize(40); g.text(lbl, x + w * 0.5, y + h * 0.5);
}
