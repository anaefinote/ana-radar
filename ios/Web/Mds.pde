// Mds.pde — ANA RADAR positioning. Turns the pairwise distance matrix (this phone + every
// peer, built from shared RSSI rows) into real 2D positions, so the scope shows WHERE devices
// are instead of a hashed angle. Classical MDS (double-centre + Jacobi eigensolve) — exact for
// clean distances, graceful under RSSI noise. Node 0 is always this phone.

float[][] mdsClassic(float[][] D, int n) {
  float[][] D2 = new float[n][n];
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) D2[i][j] = D[i][j] * D[i][j];

  float[] rm = new float[n];
  float gm = 0;
  for (int i = 0; i < n; i++) {
    float s = 0;
    for (int j = 0; j < n; j++) { s += D2[i][j]; gm += D2[i][j]; }
    rm[i] = s / n;
  }
  gm /= (float) (n * n);

  float[][] B = new float[n][n];                       // double-centred Gram matrix
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) B[i][j] = -0.5 * (D2[i][j] - rm[i] - rm[j] + gm);

  float[][] V = new float[n][n];                       // Jacobi eigenvectors
  for (int i = 0; i < n; i++) V[i][i] = 1;
  for (int sweep = 0; sweep < 100; sweep++) {
    int p = 0, q = 1;
    float mx = -1;
    for (int i = 0; i < n; i++)
      for (int j = i + 1; j < n; j++)
        if (abs(B[i][j]) > mx) { mx = abs(B[i][j]); p = i; q = j; }
    if (mx < 1e-9) break;
    float phi = 0.5 * atan2(2 * B[p][q], B[q][q] - B[p][p]);
    float c = cos(phi), sn = sin(phi);
    for (int i = 0; i < n; i++) { float a = B[i][p], b = B[i][q]; B[i][p] = c*a - sn*b; B[i][q] = sn*a + c*b; }
    for (int i = 0; i < n; i++) { float a = B[p][i], b = B[q][i]; B[p][i] = c*a - sn*b; B[q][i] = sn*a + c*b; }
    for (int i = 0; i < n; i++) { float a = V[i][p], b = V[i][q]; V[i][p] = c*a - sn*b; V[i][q] = sn*a + c*b; }
  }

  float[] val = new float[n];
  for (int i = 0; i < n; i++) val[i] = B[i][i];
  int k1 = 0;
  for (int i = 1; i < n; i++) if (val[i] > val[k1]) k1 = i;
  int k2 = -1;
  for (int i = 0; i < n; i++) { if (i == k1) continue; if (k2 < 0 || val[i] > val[k2]) k2 = i; }
  float s1 = sqrt(max(0.0, val[k1])), s2 = sqrt(max(0.0, val[k2]));

  float[][] P = new float[n][2];
  for (int i = 0; i < n; i++) { P[i][0] = V[i][k1] * s1; P[i][1] = V[i][k2] * s2; }
  return P;
}

// RSSI (dBm) -> a normalized distance, same curve the radial scope uses so it stays consistent.
float rdrDist(int rssi) {
  return constrain(map(rssi, -40, -100, 0.12, 0.95), 0.08, 1.0);
}

// Draw the constellation: this phone at centre, peers at their solved spots, edges between all
// (2 = line, 3 = triangle, 4+ = fence). mtx is the ';'-separated RSSI matrix; node 0 is this phone.
void drawConstellation(float cx, float cy, float R, String mtx) {
  String[] mr = split(mtx, ';');
  int n = mr.length;
  if (n < 2) return;

  float[][] D = new float[n][n];
  float sumKnown = 0; int cntKnown = 0;
  for (int i = 0; i < n; i++) {
    String[] e = split(mr[i], ',');
    for (int j = 0; j < n; j++) {
      if (i == j) { D[i][j] = 0; continue; }
      if (j >= e.length || trim(e[j]).length() == 0) { D[i][j] = -1; continue; }   // unknown
      int rs = int(e[j]);
      if (rs >= -1) { D[i][j] = -1; continue; }                                    // 0/invalid rssi = unknown
      D[i][j] = rdrDist(rs);
      sumKnown += D[i][j]; cntKnown++;
    }
  }
  float meanD = cntKnown > 0 ? sumKnown / cntKnown : 0.5;
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++)
      if (i != j && D[i][j] < 0) D[i][j] = meanD;        // fill gaps so a missed reading can't collapse the shape

  float[][] P = mdsClassic(D, n);

  float ox = P[0][0], oy = P[0][1];                    // centre on this phone (node 0)
  float[][] C = new float[n][2];
  for (int i = 0; i < n; i++) { C[i][0] = P[i][0]-ox; C[i][1] = P[i][1]-oy; }

  // MDS is free up to rotation + mirror, so the raw solution spins/flips every frame. Lock this
  // frame's orientation to the last one, then ease toward it — the shape settles instead of flying.
  if (mdsPrev != null && mdsPrevN == n) {
    C = mdsAlign(C, mdsPrev, n);
    for (int i = 0; i < n; i++) {
      C[i][0] = lerp(mdsPrev[i][0], C[i][0], 0.22);
      C[i][1] = lerp(mdsPrev[i][1], C[i][1], 0.22);
    }
  }
  mdsPrev = C; mdsPrevN = n;

  float maxr = 0.001;
  for (int i = 0; i < n; i++) maxr = max(maxr, sqrt(C[i][0]*C[i][0] + C[i][1]*C[i][1]));
  float target = (R * 0.9) / maxr;
  mdsScale = mdsScale <= 0 ? target : lerp(mdsScale, target, 0.18);   // smooth the zoom too

  float[] X = new float[n], Y = new float[n];
  for (int i = 0; i < n; i++) { X[i] = cx + C[i][0] * mdsScale; Y[i] = cy + C[i][1] * mdsScale; }

  color base = (rdrTintHue >= 0) ? fenceCol(rdrTintHue) : color(77, 226, 196);    // fence colour when fenced
  color core = (rdrTintHue >= 0) ? lerpColor(base, color(255, 255, 255), 0.45) : color(150, 255, 232);

  stroke(red(base), green(base), blue(base), 70);      // the rails: edges between devices
  strokeWeight(2 * fk);
  for (int i = 0; i < n; i++)
    for (int j = i + 1; j < n; j++) line(X[i], Y[i], X[j], Y[j]);
  noStroke();

  for (int i = 1; i < n; i++) {                        // peer dots at real positions
    for (int g = 4; g >= 1; g--) { fill(red(base), green(base), blue(base), 30); ellipse(X[i], Y[i], (14+g*7)*fk, (14+g*7)*fk); }
    fill(core); ellipse(X[i], Y[i], 15 * fk, 15 * fk);
  }
  fill(255, 255, 255, 235);                            // this phone, at centre
  ellipse(X[0], Y[0], 12 * fk, 12 * fk);
}

// ANA FENCE colour: a fenceId's hue (0..359) -> a vivid RGB, so a fence reads as one colour on
// every member's scope. Manual HSV->RGB (s .72, v 1) to avoid touching the global colorMode.
int rdrTintHue = -1;                                   // -1 = default teal; >=0 = active fence hue
color fenceCol(int hue) {
  float h = (((hue % 360) + 360) % 360), s = 0.72, v = 1.0;
  float c = v * s, x = c * (1 - abs(((h / 60.0) % 2) - 1)), m = v - c;
  float r, g, b;
  if      (h <  60) { r = c; g = x; b = 0; }
  else if (h < 120) { r = x; g = c; b = 0; }
  else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; }
  else if (h < 300) { r = x; g = 0; b = c; }
  else              { r = c; g = 0; b = x; }
  return color((r + m) * 255, (g + m) * 255, (b + m) * 255);
}

// ---- orientation + smoothing state so the constellation settles instead of spinning
float[][] mdsPrev = null;
int mdsPrevN = 0;
float mdsScale = 0;

/** best-fit rotation (and optional mirror) of A onto B, matched by node index, both centred at origin */
float[][] mdsAlign(float[][] A, float[][] B, int n) {
  float[][] rot = mdsRotateToFit(A, B, n, false);
  float[][] mir = mdsRotateToFit(A, B, n, true);
  return mdsFit(mir, B, n) < mdsFit(rot, B, n) ? mir : rot;
}
float[][] mdsRotateToFit(float[][] A, float[][] B, int n, boolean mirror) {
  float num = 0, den = 0;
  for (int i = 0; i < n; i++) {
    float ax = A[i][0], ay = mirror ? -A[i][1] : A[i][1];
    num += ax * B[i][1] - ay * B[i][0];
    den += ax * B[i][0] + ay * B[i][1];
  }
  float th = atan2(num, den), c = cos(th), s = sin(th);
  float[][] R = new float[n][2];
  for (int i = 0; i < n; i++) {
    float ax = A[i][0], ay = mirror ? -A[i][1] : A[i][1];
    R[i][0] = c * ax - s * ay;
    R[i][1] = s * ax + c * ay;
  }
  return R;
}
float mdsFit(float[][] A, float[][] B, int n) {
  float e = 0;
  for (int i = 0; i < n; i++) { float dx = A[i][0]-B[i][0], dy = A[i][1]-B[i][1]; e += dx*dx + dy*dy; }
  return e;
}
