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
  float maxr = 0.001;
  for (int i = 0; i < n; i++) { float dx = P[i][0]-ox, dy = P[i][1]-oy; maxr = max(maxr, sqrt(dx*dx+dy*dy)); }
  float sc = (R * 0.9) / maxr;

  float[] X = new float[n], Y = new float[n];
  for (int i = 0; i < n; i++) { X[i] = cx + (P[i][0]-ox) * sc; Y[i] = cy + (P[i][1]-oy) * sc; }

  stroke(77, 226, 196, 70);                            // the rails: edges between devices
  strokeWeight(2 * fk);
  for (int i = 0; i < n; i++)
    for (int j = i + 1; j < n; j++) line(X[i], Y[i], X[j], Y[j]);
  noStroke();

  for (int i = 1; i < n; i++) {                        // peer dots at real positions
    for (int g = 4; g >= 1; g--) { fill(77, 226, 196, 30); ellipse(X[i], Y[i], (14+g*7)*fk, (14+g*7)*fk); }
    fill(150, 255, 232, 235); ellipse(X[i], Y[i], 15 * fk, 15 * fk);
  }
  fill(255, 255, 255, 235);                            // this phone, at centre
  ellipse(X[0], Y[0], 12 * fk, 12 * fk);
}
