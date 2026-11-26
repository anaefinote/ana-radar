import java.io.*;
import java.util.*;
// ANA Lesson Maker - Engine tab
// Plain Java 6 only. Nothing in this tab calls Processing, so it can be tested on its own.
// No "static" members anywhere: Processing tabs are inner classes and Java 6 forbids them there.

import java.math.BigInteger;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.MessageDigest;
import java.security.SecureRandom;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.awt.image.BufferedImage;
import java.awt.Graphics2D;
import java.awt.Color;
import java.awt.Font;
import java.awt.RenderingHints;
import javax.imageio.ImageIO;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

public class Engine {

  final int CLASS_LESSON = 30;           // pngmesh part class for lessons (20 = entries, 21 = GST, 3 = 3D shape)
  final String B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  final String B32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
  final String[] KNOWN_IDS = { "bitcoin", "litecoin", "ethereum", "cardano" };
  String coingeckoBase = "https://api.coingecko.com/api/v3";

  // ===================== bytes and text =====================

  public String toHex(byte[] b) {
    String d = "0123456789abcdef";
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < b.length; i++) { int v = b[i] & 255; sb.append(d.charAt(v >> 4)); sb.append(d.charAt(v & 15)); }
    return sb.toString();
  }

  public byte[] fromHex(String s) {
    s = s.trim();
    if (s.length() % 2 != 0) throw new IllegalArgumentException("odd-length hex");
    byte[] o = new byte[s.length() / 2];
    for (int i = 0; i < o.length; i++) {
      int hi = Character.digit(s.charAt(2 * i), 16), lo = Character.digit(s.charAt(2 * i + 1), 16);
      if (hi < 0 || lo < 0) throw new IllegalArgumentException("bad hex");
      o[i] = (byte) (hi * 16 + lo);
    }
    return o;
  }

  byte[] utf8(String s) { try { return s.getBytes("UTF-8"); } catch (Exception e) { throw new RuntimeException(e); } }
  String fromUtf8(byte[] b) { try { return new String(b, "UTF-8"); } catch (Exception e) { throw new RuntimeException(e); } }

  public byte[] sha256(byte[] d) {
    try { return MessageDigest.getInstance("SHA-256").digest(d); } catch (Exception e) { throw new RuntimeException(e); }
  }
  String sha256hex(byte[] d) { return toHex(sha256(d)); }

  public byte[] cat(byte[] a, byte[] b) {
    byte[] o = new byte[a.length + b.length];
    System.arraycopy(a, 0, o, 0, a.length);
    System.arraycopy(b, 0, o, a.length, b.length);
    return o;
  }

  public String b64enc(byte[] d) {
    String A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < d.length; i += 3) {
      int b0 = d[i] & 255;
      int b1 = (i + 1 < d.length) ? (d[i + 1] & 255) : 0;
      int b2 = (i + 2 < d.length) ? (d[i + 2] & 255) : 0;
      int n = (b0 << 16) | (b1 << 8) | b2;
      sb.append(A.charAt((n >> 18) & 63));
      sb.append(A.charAt((n >> 12) & 63));
      sb.append(i + 1 < d.length ? A.charAt((n >> 6) & 63) : '=');
      sb.append(i + 2 < d.length ? A.charAt(n & 63) : '=');
    }
    return sb.toString();
  }

  public byte[] b64dec(String s) {
    String A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    StringBuilder clean = new StringBuilder();
    for (int i = 0; i < s.length(); i++) { char c = s.charAt(i); if (c == '=' || A.indexOf(c) >= 0) clean.append(c); }
    String t = clean.toString();
    int pad = 0;
    while (t.length() > 0 && t.charAt(t.length() - 1) == '=') { t = t.substring(0, t.length() - 1); pad++; }
    ByteArrayOutputStream bo = new ByteArrayOutputStream();
    int buf = 0, bits = 0;
    for (int i = 0; i < t.length(); i++) {
      buf = (buf << 6) | A.indexOf(t.charAt(i)); bits += 6;
      if (bits >= 8) { bits -= 8; bo.write((buf >> bits) & 255); }
    }
    return bo.toByteArray();
  }

  // ===================== address checks =====================
  // These are the checks the app must also perform. Keep them identical on Android and iPhone.

  public byte[] b58dec(String s) {
    BigInteger n = BigInteger.ZERO, b = BigInteger.valueOf(58);
    for (int i = 0; i < s.length(); i++) {
      int ix = B58.indexOf(s.charAt(i));
      if (ix < 0) return null;
      n = n.multiply(b).add(BigInteger.valueOf(ix));
    }
    byte[] raw = n.signum() == 0 ? new byte[0] : n.toByteArray();
    if (raw.length > 1 && raw[0] == 0) { byte[] t = new byte[raw.length - 1]; System.arraycopy(raw, 1, t, 0, t.length); raw = t; }
    int zeros = 0;
    while (zeros < s.length() && s.charAt(zeros) == '1') zeros++;
    byte[] o = new byte[zeros + raw.length];
    System.arraycopy(raw, 0, o, zeros, raw.length);
    return o;
  }

  public String b58enc(byte[] d) {
    BigInteger n = new BigInteger(1, d), b = BigInteger.valueOf(58);
    StringBuilder sb = new StringBuilder();
    while (n.signum() > 0) { BigInteger[] qr = n.divideAndRemainder(b); sb.append(B58.charAt(qr[1].intValue())); n = qr[0]; }
    for (int i = 0; i < d.length && d[i] == 0; i++) sb.append('1');
    return sb.reverse().toString();
  }

  // 25 bytes: 1 version + 20 hash + 4 checksum
  public boolean b58checkOk(String a, String versions) {
    byte[] d = b58dec(a);
    if (d == null || d.length != 25) return false;
    byte[] body = new byte[21];
    System.arraycopy(d, 0, body, 0, 21);
    byte[] h = sha256(sha256(body));
    for (int i = 0; i < 4; i++) if (h[i] != d[21 + i]) return false;
    String[] vs = versions == null ? new String[0] : versions.split(",");
    for (int i = 0; i < vs.length; i++) {
      try { if (Integer.parseInt(vs[i].trim()) == (d[0] & 255)) return true; } catch (Exception e) { }
    }
    return false;
  }

  public int bech32Polymod(int[] v) {
    int[] gen = { 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 };
    int chk = 1;
    for (int i = 0; i < v.length; i++) {
      int top = chk >>> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v[i];
      for (int j = 0; j < 5; j++) if (((top >> j) & 1) != 0) chk ^= gen[j];
    }
    return chk;
  }

  // returns 0 = invalid, 1 = bech32, 2 = bech32m. No 90-character limit (Cardano addresses are longer).
  public int bech32Variant(String a, String hrp) {
    if (a == null || a.length() < 8) return 0;
    String low = a.toLowerCase();
    if (!a.equals(low) && !a.equals(a.toUpperCase())) return 0;
    int pos = low.lastIndexOf('1');
    if (pos < 1 || pos + 7 > low.length()) return 0;
    String h = low.substring(0, pos);
    if (hrp != null && hrp.length() > 0 && !h.equals(hrp.toLowerCase())) return 0;
    int dl = low.length() - pos - 1;
    int[] v = new int[h.length() * 2 + 1 + dl];
    int k = 0;
    for (int i = 0; i < h.length(); i++) { int c = h.charAt(i); if (c < 33 || c > 126) return 0; v[k++] = c >> 5; }
    v[k++] = 0;
    for (int i = 0; i < h.length(); i++) v[k++] = h.charAt(i) & 31;
    for (int i = pos + 1; i < low.length(); i++) { int ix = B32.indexOf(low.charAt(i)); if (ix < 0) return 0; v[k++] = ix; }
    int p = bech32Polymod(v);
    if (p == 1) return 1;
    if (p == 0x2bc830a3) return 2;
    return 0;
  }

  public boolean addrOk(String kind, String pattern, String hrp, String versions, String a) {
    if (a == null) return false;
    try {
      if (pattern != null && pattern.length() > 0 && !Pattern.compile(pattern).matcher(a).matches()) return false;
    } catch (Exception e) { return false; }
    if ("hex_evm".equals(kind)) return a.matches("0x[0-9a-fA-F]{40}");
    if ("base58check".equals(kind)) return b58checkOk(a, versions);
    if ("bech32".equals(kind)) return bech32Variant(a, hrp) != 0;
    if ("base58".equals(kind)) { byte[] d = b58dec(a); return d != null && d.length == 32; }   // plain base58, 32-byte key (Solana, no checksum)
    return false;
  }

  // ===================== P-256 ECDSA (SHA256withECDSA, DER, X.509 public key) =====================
  // Written with BigInteger so it works on the old Java inside Processing 1.5.1.
  // k is deterministic (RFC 6979). Not constant-time: fine for an offline signing tool on your own PC.

  final BigInteger P = new BigInteger("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16);
  final BigInteger N = new BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16);
  final BigInteger CB = new BigInteger("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16);
  final BigInteger GX = new BigInteger("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296", 16);
  final BigInteger GY = new BigInteger("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5", 16);
  final String SPKI_PREFIX = "3059301306072a8648ce3d020106082a8648ce3d030107034200";

  public BigInteger[] padd(BigInteger[] a, BigInteger[] b) {
    if (a == null) return b;
    if (b == null) return a;
    BigInteger l;
    if (a[0].equals(b[0])) {
      if (!a[1].equals(b[1]) || a[1].signum() == 0) return null;
      BigInteger three = BigInteger.valueOf(3);
      l = a[0].multiply(a[0]).multiply(three).subtract(three).multiply(a[1].shiftLeft(1).modInverse(P)).mod(P);
    } else {
      l = b[1].subtract(a[1]).multiply(b[0].subtract(a[0]).mod(P).modInverse(P)).mod(P);
    }
    BigInteger x = l.multiply(l).subtract(a[0]).subtract(b[0]).mod(P);
    BigInteger y = l.multiply(a[0].subtract(x)).subtract(a[1]).mod(P);
    return new BigInteger[] { x, y };
  }

  public BigInteger[] pmul(BigInteger k, BigInteger[] pt) {
    BigInteger[] r = null;
    for (int i = k.bitLength() - 1; i >= 0; i--) {
      r = padd(r, r);
      if (k.testBit(i)) r = padd(r, pt);
    }
    return r;
  }

  BigInteger[] gpoint() { return new BigInteger[] { GX, GY }; }

  public boolean onCurve(BigInteger[] q) {
    if (q == null) return false;
    BigInteger l = q[1].multiply(q[1]).mod(P);
    BigInteger r = q[0].multiply(q[0]).multiply(q[0]).subtract(q[0].multiply(BigInteger.valueOf(3))).add(CB).mod(P);
    return l.equals(r);
  }

  public byte[] i2o(BigInteger v) {           // 32-byte big-endian
    byte[] raw = v.toByteArray();
    byte[] o = new byte[32];
    int n = Math.min(raw.length, 32);
    System.arraycopy(raw, raw.length - n, o, 32 - n, n);
    return o;
  }

  public byte[] hmac(byte[] key, byte[] data) {
    try {
      Mac m = Mac.getInstance("HmacSHA256");
      m.init(new SecretKeySpec(key, "HmacSHA256"));
      return m.doFinal(data);
    } catch (Exception e) { throw new RuntimeException(e); }
  }

  public BigInteger rfc6979k(BigInteger x, byte[] h1) {
    byte[] xb = i2o(x);
    byte[] hb = i2o(new BigInteger(1, h1).mod(N));
    byte[] V = new byte[32];
    for (int i = 0; i < 32; i++) V[i] = 1;
    byte[] K = new byte[32];
    K = hmac(K, cat(cat(cat(V, new byte[] { 0 }), xb), hb));
    V = hmac(K, V);
    K = hmac(K, cat(cat(cat(V, new byte[] { 1 }), xb), hb));
    V = hmac(K, V);
    while (true) {
      V = hmac(K, V);
      BigInteger k = new BigInteger(1, V);
      if (k.signum() > 0 && k.compareTo(N) < 0) return k;
      K = hmac(K, cat(V, new byte[] { 0 }));
      V = hmac(K, V);
    }
  }

  public byte[] derInt(BigInteger v) {
    byte[] b = v.toByteArray();
    byte[] o = new byte[b.length + 2];
    o[0] = 2; o[1] = (byte) b.length;
    System.arraycopy(b, 0, o, 2, b.length);
    return o;
  }

  public byte[] signMsg(BigInteger d, byte[] msg) {
    byte[] h = sha256(msg);
    BigInteger z = new BigInteger(1, h);
    BigInteger k = rfc6979k(d, h);
    BigInteger[] R = pmul(k, gpoint());
    BigInteger r = R[0].mod(N);
    BigInteger s = k.modInverse(N).multiply(z.add(r.multiply(d))).mod(N);
    if (r.signum() == 0 || s.signum() == 0) throw new RuntimeException("signing failed, try again");
    byte[] ri = derInt(r), si = derInt(s);
    byte[] o = new byte[2 + ri.length + si.length];
    o[0] = 0x30; o[1] = (byte) (ri.length + si.length);
    System.arraycopy(ri, 0, o, 2, ri.length);
    System.arraycopy(si, 0, o, 2 + ri.length, si.length);
    return o;
  }

  public BigInteger[] parseDer(byte[] s) {
    try {
      if (s.length < 8 || s[0] != 0x30 || (s[1] & 255) != s.length - 2) return null;
      int i = 2;
      if (s[i] != 2) return null;
      int rl = s[i + 1] & 255;
      BigInteger r = new BigInteger(1, java.util.Arrays.copyOfRange(s, i + 2, i + 2 + rl));
      i += 2 + rl;
      if (s[i] != 2) return null;
      int sl = s[i + 1] & 255;
      if (i + 2 + sl != s.length) return null;
      BigInteger t = new BigInteger(1, java.util.Arrays.copyOfRange(s, i + 2, i + 2 + sl));
      return new BigInteger[] { r, t };
    } catch (Exception e) { return null; }
  }

  public boolean verifyMsg(byte[] spki, byte[] msg, byte[] der) {
    try {
      if (spki == null || spki.length != 91) return false;
      byte[] pre = fromHex(SPKI_PREFIX);
      for (int i = 0; i < pre.length; i++) if (spki[i] != pre[i]) return false;
      if (spki[26] != 4) return false;
      BigInteger[] q = new BigInteger[] {
        new BigInteger(1, java.util.Arrays.copyOfRange(spki, 27, 59)),
        new BigInteger(1, java.util.Arrays.copyOfRange(spki, 59, 91)) };
      if (!onCurve(q)) return false;
      BigInteger[] rs = parseDer(der);
      if (rs == null) return false;
      BigInteger r = rs[0], s = rs[1];
      if (r.signum() <= 0 || s.signum() <= 0 || r.compareTo(N) >= 0 || s.compareTo(N) >= 0) return false;
      BigInteger z = new BigInteger(1, sha256(msg));
      BigInteger w = s.modInverse(N);
      BigInteger[] R = padd(pmul(z.multiply(w).mod(N), gpoint()), pmul(r.multiply(w).mod(N), q));
      return R != null && R[0].mod(N).equals(r);
    } catch (Exception e) { return false; }
  }

  public byte[] spkiFor(BigInteger d) {
    BigInteger[] q = pmul(d, gpoint());
    byte[] pre = fromHex(SPKI_PREFIX + "04");
    return cat(cat(pre, i2o(q[0])), i2o(q[1]));
  }

  String keyIdOf(byte[] spki) { return toHex(sha256(spki)).substring(0, 16); }

  public BigInteger newPrivateKey() {
    SecureRandom sr = new SecureRandom();
    BigInteger d;
    do { d = new BigInteger(256, sr); } while (d.signum() == 0 || d.compareTo(N) >= 0);
    return d;
  }

  // key file: three lines  private=hex / public=base64 / id=hex.   Returns {privHex, pubB64, id} or null.
  public String[] readKeyFile(File f) {
    try {
      if (!f.exists()) return null;
      String priv = null, pub = null, id = null;
      BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
      String ln;
      while ((ln = br.readLine()) != null) {
        if (ln.startsWith("private=")) priv = ln.substring(8).trim();
        if (ln.startsWith("public=")) pub = ln.substring(7).trim();
        if (ln.startsWith("id=")) id = ln.substring(3).trim();
      }
      br.close();
      if (priv == null || pub == null || id == null) return null;
      BigInteger d = new BigInteger(priv, 16);
      byte[] spki = spkiFor(d);
      if (!b64enc(spki).equals(pub) || !keyIdOf(spki).equals(id)) return null;   // file was edited or damaged
      return new String[] { priv, pub, id };
    } catch (Exception e) { return null; }
  }

  public String[] createKeyFile(File f) throws IOException {
    BigInteger d = newPrivateKey();
    byte[] spki = spkiFor(d);
    String[] k = new String[] { toHex(i2o(d)), b64enc(spki), keyIdOf(spki) };
    File dir = f.getParentFile();
    if (dir != null) dir.mkdirs();
    PrintWriter pw = new PrintWriter(new OutputStreamWriter(new FileOutputStream(f), "UTF-8"));
    pw.println("# ANA Lesson Maker signing key. KEEP PRIVATE. Back it up somewhere safe. Never email it or put it in a synced folder.");
    pw.println("# Anyone holding the private line can sign lessons that every ANA will trust.");
    pw.println("private=" + k[0]);
    pw.println("public=" + k[1]);
    pw.println("id=" + k[2]);
    pw.close();
    return k;
  }

  // ===================== pngmesh container =====================
  // File = PNG image bytes, then a trailer, then an 8-byte big-endian length of the trailer.
  // Trailer = "PMSH", int version(1), int parts(1), int class, int ncols, ncols strings, int nrows, nrows*ncols strings.
  // String = int length + UTF-8 bytes.  Mirrors AnaMesh.write / AnaMesh.read in the Android build.

  public void wstr(DataOutputStream d, String s) throws IOException {
    byte[] b = utf8(s == null ? "" : s);
    d.writeInt(b.length);
    d.write(b);
  }

  public String rstr(DataInputStream d) throws IOException {
    int n = d.readInt();
    if (n < 0 || n > 16777216) throw new IOException("damaged string in pngmesh");
    byte[] b = new byte[n];
    d.readFully(b);
    return fromUtf8(b);
  }

  public byte[] trailerPrefix(String[][] rowsBeforeLast, int totalRows) throws IOException {
    ByteArrayOutputStream bo = new ByteArrayOutputStream();
    DataOutputStream d = new DataOutputStream(bo);
    d.writeBytes("PMSH");
    d.writeInt(1);
    d.writeInt(1);
    d.writeInt(CLASS_LESSON);
    d.writeInt(3);
    wstr(d, "section"); wstr(d, "key"); wstr(d, "value");
    d.writeInt(totalRows);
    for (int i = 0; i < rowsBeforeLast.length; i++)
      for (int j = 0; j < 3; j++) wstr(d, rowsBeforeLast[i][j]);
    d.flush();
    return bo.toByteArray();
  }

  public byte[] wrapFile(byte[] png, byte[] trailer) throws IOException {
    ByteArrayOutputStream bo = new ByteArrayOutputStream();
    DataOutputStream d = new DataOutputStream(bo);
    d.write(png);
    d.write(trailer);
    d.writeLong(trailer.length);
    d.flush();
    return bo.toByteArray();
  }

  class Parsed {
    int cls;
    String[][] rows;
    byte[] trailer;
    int lastRowOffset;      // where the final row starts inside the trailer
  }

  public Parsed parseFile(byte[] f) throws IOException {
    if (f.length < 20) throw new IOException("too small to be a .pngmesh");
    long tl = new DataInputStream(new ByteArrayInputStream(f, f.length - 8, 8)).readLong();
    long start = (long) (f.length - 8) - tl;
    if (tl < 12 || start < 0) throw new IOException("no pngmesh trailer");
    ByteArrayInputStream bis = new ByteArrayInputStream(f, (int) start, (int) tl);
    DataInputStream d = new DataInputStream(bis);
    byte[] magic = new byte[4];
    d.readFully(magic);
    if (magic[0] != 'P' || magic[1] != 'M' || magic[2] != 'S' || magic[3] != 'H') throw new IOException("not a pngmesh trailer");
    int ver = d.readInt();
    if (ver != 1) throw new IOException("pngmesh version " + ver + " is newer than this ANA");
    int parts = d.readInt();
    if (parts != 1) throw new IOException("a lesson holds exactly one part");
    Parsed p = new Parsed();
    p.cls = d.readInt();
    if (p.cls != CLASS_LESSON) throw new IOException("this .pngmesh is not a lesson (class " + p.cls + ")");
    int nc = d.readInt();
    if (nc != 3) throw new IOException("a lesson has exactly 3 columns");
    String c0 = rstr(d), c1 = rstr(d), c2 = rstr(d);
    if (!c0.equals("section") || !c1.equals("key") || !c2.equals("value")) throw new IOException("lesson columns are wrong");
    int nr = d.readInt();
    if (nr < 1 || nr > 100000) throw new IOException("lesson row count is wrong");
    p.rows = new String[nr][3];
    for (int i = 0; i < nr; i++) {
      if (i == nr - 1) p.lastRowOffset = (int) tl - bis.available();
      for (int j = 0; j < 3; j++) p.rows[i][j] = rstr(d);
    }
    if (bis.available() != 0) throw new IOException("extra bytes after the last row");
    p.trailer = java.util.Arrays.copyOfRange(f, (int) start, (int) start + (int) tl);
    return p;
  }

  String sidecarText(String name, byte[] data) { return sha256hex(data) + "\n" + name + "\n" + data.length + "\n"; }

  public String sidecarHash(byte[] sc) {
    if (sc == null || sc.length > 4096) return null;
    String s = fromUtf8(sc);
    int nl = s.indexOf('\n');
    String first = (nl >= 0 ? s.substring(0, nl) : s).trim().toLowerCase();
    return first.matches("[0-9a-f]{64}") ? first : null;
  }

  // ===================== lesson file: build and verify =====================

  String[] SECTIONS = { "lesson", "coin", "address", "reader", "server", "param", "test" };

  // Named class instead of an anonymous one: the Processing 1.5.1 preprocessor garbles anonymous classes that have generic type arguments.
  class ServerKeyOrder implements java.util.Comparator {
    public int compare(Object oa, Object ob) {
      String a = (String) oa, b = (String) ob;
      int x = 0, y = 0;
      try { x = Integer.parseInt(a.substring(7)); } catch (Exception ex) { }
      try { y = Integer.parseInt(b.substring(7)); } catch (Exception ex) { }
      return x < y ? -1 : (x > y ? 1 : 0);
    }
  }

  public String[][] rowsFrom(LinkedHashMap<String, String> kv) {
    ArrayList<String[]> out = new ArrayList<String[]>();
    for (int s = 0; s < SECTIONS.length; s++) {
      ArrayList<String> keys = new ArrayList<String>();
      for (String full : kv.keySet()) if (full.startsWith(SECTIONS[s] + "/")) keys.add(full);
      if (SECTIONS[s].equals("server")) {
        java.util.Collections.sort(keys, new ServerKeyOrder());
      }
      for (int i = 0; i < keys.size(); i++) {
        String full = keys.get(i);
        out.add(new String[] { SECTIONS[s], full.substring(SECTIONS[s].length() + 1), kv.get(full) });
      }
    }
    return out.toArray(new String[0][]);
  }

  // The signature message is the lowercase hex SHA-256 of the trailer bytes before the final row, as UTF-8 text.
  public byte[] buildLesson(LinkedHashMap<String, String> kv, BigInteger priv, byte[] png) throws IOException {
    byte[] spki = spkiFor(priv);
    String keyId = keyIdOf(spki);
    String[][] base = rowsFrom(kv);
    String[][] before = new String[base.length + 1][];
    System.arraycopy(base, 0, before, 0, base.length);
    before[base.length] = new String[] { "sig", "key_id", keyId };
    byte[] prefix = trailerPrefix(before, before.length + 1);
    byte[] sig = signMsg(priv, utf8(sha256hex(prefix)));
    ByteArrayOutputStream bo = new ByteArrayOutputStream();
    DataOutputStream d = new DataOutputStream(bo);
    d.write(prefix);
    wstr(d, "sig"); wstr(d, "value"); wstr(d, b64enc(sig));
    d.flush();
    return wrapFile(png, bo.toByteArray());
  }

  // Returns null if the lesson is good, otherwise a plain-words reason. trusted = list of {keyId, spkiBase64}.
  public String verifyLesson(byte[] file, byte[] sidecar, ArrayList<String[]> trusted) {
    try {
      String want = sidecarHash(sidecar);
      if (want == null) return "the .sha256 file is missing or unreadable";
      if (!want.equals(sha256hex(file))) return "the file does not match its .sha256 (damaged or changed)";
      Parsed p = parseFile(file);
      int n = p.rows.length;
      if (n < 3) return "lesson is too short";
      String[] last = p.rows[n - 1], kid = p.rows[n - 2];
      if (!last[0].equals("sig") || !last[1].equals("value")) return "lesson is not signed";
      if (!kid[0].equals("sig") || !kid[1].equals("key_id")) return "lesson has no key id";
      byte[] spki = null;
      for (int i = 0; i < trusted.size(); i++) if (trusted.get(i)[0].equals(kid[2])) spki = b64dec(trusted.get(i)[1]);
      if (spki == null) return "lesson is signed by a key this ANA does not trust";
      byte[] prefix = java.util.Arrays.copyOfRange(p.trailer, 0, p.lastRowOffset);
      if (!verifyMsg(spki, utf8(sha256hex(prefix)), b64dec(last[2]))) return "the signature does not check out";
      return null;
    } catch (IOException e) {
      return e.getMessage();
    } catch (Exception e) {
      return "lesson could not be read: " + e;
    }
  }

  public LinkedHashMap<String, String> kvFromRows(String[][] rows) {
    LinkedHashMap<String, String> kv = new LinkedHashMap<String, String>();
    for (int i = 0; i < rows.length; i++) kv.put(rows[i][0] + "/" + rows[i][1], rows[i][2]);
    return kv;
  }

  // ===================== draft text =====================

  public LinkedHashMap<String, String> parseDraft(String text) throws Exception {
    LinkedHashMap<String, String> kv = new LinkedHashMap<String, String>();
    String[] lines = text.split("\r?\n");
    for (int i = 0; i < lines.length; i++) {
      String ln = lines[i].trim();
      if (ln.length() == 0 || ln.startsWith("#")) continue;
      int eq = ln.indexOf('=');
      if (eq < 1) throw new Exception("line " + (i + 1) + ": expected  section/key = value");
      String k = ln.substring(0, eq).trim();
      String v = ln.substring(eq + 1).trim();
      if (!k.matches("[a-z_]+/[A-Za-z0-9_.-]+")) throw new Exception("line " + (i + 1) + ": bad key  " + k);
      if (kv.containsKey(k)) throw new Exception("line " + (i + 1) + ": " + k + " appears twice");
      kv.put(k, v);
    }
    return kv;
  }

  public void normalise(LinkedHashMap<String, String> kv) {
    String rd = kv.get("reader/name");
    for (String k : new ArrayList<String>(kv.keySet())) {
      if (k.startsWith("server/")) {
        String u = kv.get(k).trim();
        if ("esplora".equals(rd) && u.length() > 0 && !u.endsWith("/")) u = u + "/";
        kv.put(k, u);
      }
    }
  }

  // ===================== lint: every rule a lesson must pass before it is signed =====================

  public ArrayList<String> lint(LinkedHashMap<String, String> kv, boolean allowHttp) {
    ArrayList<String> e = new ArrayList<String>();
    ArrayList<String> flagged = new ArrayList<String>();     // keys that still say ?
    boolean structural = false;
    for (String k : kv.keySet()) {
      String sec = k.substring(0, k.indexOf('/'));
      boolean known = false;
      for (int i = 0; i < SECTIONS.length; i++) if (SECTIONS[i].equals(sec)) known = true;
      if (!known) { e.add(k + ": unknown section (the signature rows are added for you)"); structural = true; }
      if ("?".equals(kv.get(k))) { e.add(k + ": still says ?  - fill it in"); flagged.add(k); }
    }
    if (structural) return e;
    boolean formsIncomplete = false;
    for (int i = 0; i < flagged.size(); i++) if (flagged.get(i).startsWith("address/")) formsIncomplete = true;

    String id = kv.get("lesson/id");
    if (id == null || !id.matches("[a-z0-9][a-z0-9_-]{1,31}")) e.add("lesson/id: use 2-32 lowercase letters, digits, - or _");
    if (!isInt(kv.get("lesson/version"), 1, 1000000)) e.add("lesson/version: whole number, 1 or more");
    if (!isInt(kv.get("lesson/needs_reader"), 1, 1000)) e.add("lesson/needs_reader: whole number, 1 or more");
    if (isEmpty(kv.get("coin/name"))) e.add("coin/name: missing");
    if (kv.get("coin/ticker") == null || !kv.get("coin/ticker").matches("[A-Z0-9]{1,10}")) e.add("coin/ticker: 1-10 capital letters or digits");
    if (!isInt(kv.get("coin/decimals"), 0, 30)) e.add("coin/decimals: whole number 0-30");
    if (!isInt(kv.get("coin/display_decimals"), 0, 18)) e.add("coin/display_decimals: whole number 0-18");
    if (kv.get("coin/price_id") == null || !kv.get("coin/price_id").matches("[a-z0-9-]{1,60}")) e.add("coin/price_id: the CoinGecko id, lowercase");

    ArrayList<String[]> forms = formsOf(kv);
    if (forms.isEmpty()) e.add("address: need at least one address/form1.kind");
    for (int i = 0; i < forms.size(); i++) {
      String[] f = forms.get(i);   // name, kind, pattern, hrp, versions
      String nm = "address/" + f[0];
      if (!(f[1].equals("base58check") || f[1].equals("bech32") || f[1].equals("hex_evm") || f[1].equals("base58"))) e.add(nm + ".kind: must be base58check, base58, bech32 or hex_evm");
      try { Pattern.compile(f[2]); if (f[2].length() == 0) e.add(nm + ".pattern: missing"); } catch (Exception x) { e.add(nm + ".pattern: not a valid pattern"); }
      if (f[1].equals("bech32") && !f[3].matches("[a-z0-9]{1,20}")) e.add(nm + ".hrp: the address prefix, such as bc or addr");
      if (f[1].equals("base58check") && !f[4].matches("[0-9]{1,3}(,[0-9]{1,3})*")) e.add(nm + ".versions: numbers like 0,5");
    }

    String rd = kv.get("reader/name");
    if (rd == null || !(rd.equals("esplora") || rd.equals("evm") || rd.equals("json"))) e.add("reader/name: must be esplora, evm or json");

    int servers = 0;
    for (String k : kv.keySet()) {
      if (!k.startsWith("server/")) continue;
      servers++;
      String u = kv.get(k);
      if (!k.substring(7).matches("[0-9]{1,2}")) e.add(k + ": server keys are numbers, 1 2 3 ...");
      if (!(u.matches("https://[^/\\s@?#]+(/\\S*)?") || (allowHttp && u.matches("http://[^/\\s@?#]+(/\\S*)?"))))
        e.add(k + ": must be an https:// address with no username or password in it");
      if (u.toLowerCase().matches(".*[?&](api_?key|key|token|secret|project_id|auth|access_token)=.*"))
        e.add(k + ": looks like it carries a key. Lessons are readable by anyone, so they can never hold secrets");
    }
    if (servers < 1) e.add("server: need at least server/1");

    for (String k : kv.keySet()) {
      if (k.startsWith("test/")) continue;
      String v = kv.get(k).toLowerCase();
      if (v.matches(".*(apikey|api_key|api-key|x-api|authorization|bearer |project_id|secret).*"))
        e.add(k + ": looks like a secret. Lessons can never hold keys");
    }

    if ("json".equals(rd)) {
      String m = kv.get("param/method");
      if (m == null || !(m.equals("GET") || m.equals("POST"))) e.add("param/method: GET or POST");
      if (isEmpty(kv.get("param/balance_path"))) e.add("param/balance_path: where the balance sits in the reply, like 0.balance");
      String bt = kv.get("param/balance_type");
      if (bt == null || !(bt.equals("number") || bt.equals("text_integer"))) e.add("param/balance_type: number or text_integer");
      if ("POST".equals(m) && (kv.get("param/body") == null || !kv.get("param/body").contains("{address}"))) e.add("param/body: a POST body must contain {address}");
      if ("GET".equals(m)) for (String k : kv.keySet()) if (k.startsWith("server/") && !kv.get(k).contains("{address}")) e.add(k + ": a GET server address must contain {address}");
    }
    if ("evm".equals(rd) && !isInt(kv.get("param/chain_id"), 1, Integer.MAX_VALUE)) e.add("param/chain_id: whole number, like 1 for Ethereum");

    int good = 0, bad = 0;
    for (String k : kv.keySet()) {
      if (k.startsWith("test/good.")) { good++; if (!formsIncomplete && !anyFormOk(kv, kv.get(k))) e.add(k + ": this address should be valid but fails every address rule"); }
      if (k.startsWith("test/bad.")) { bad++; if (!formsIncomplete && anyFormOk(kv, kv.get(k))) e.add(k + ": this address should be rejected but passes an address rule"); }
    }
    if (!formsIncomplete && kv.containsKey("test/probe_address") && !anyFormOk(kv, kv.get("test/probe_address"))) e.add("test/probe_address: fails every address rule");
    if (good < 1) e.add("test/good.1: need at least one good address");
    if (bad < 1) e.add("test/bad.1: need at least one bad address");

    // a value that still says ? is reported once; drop the follow-on complaints about that same key
    ArrayList<String> out = new ArrayList<String>();
    for (int i = 0; i < e.size(); i++) {
      String msg = e.get(i);
      boolean follow = false;
      if (msg.indexOf("still says ?") < 0)
        for (int j = 0; j < flagged.size(); j++) if (msg.startsWith(flagged.get(j) + ":") || msg.startsWith(flagged.get(j) + ".")) follow = true;
      if (!follow) out.add(msg);
    }
    return out;
  }

  boolean isEmpty(String s) { return s == null || s.trim().length() == 0; }
  public boolean isInt(String s, int lo, int hi) {
    try { int v = Integer.parseInt(s.trim()); return v >= lo && v <= hi; } catch (Exception e) { return false; }
  }

  public ArrayList<String[]> formsOf(LinkedHashMap<String, String> kv) {
    ArrayList<String[]> out = new ArrayList<String[]>();
    for (String k : kv.keySet()) {
      Matcher m = Pattern.compile("address/(form[0-9]+)\\.kind").matcher(k);
      if (m.matches()) {
        String n = m.group(1);
        out.add(new String[] { n, kv.get(k), nz(kv.get("address/" + n + ".pattern")), nz(kv.get("address/" + n + ".hrp")), nz(kv.get("address/" + n + ".versions")) });
      }
    }
    return out;
  }
  String nz(String s) { return s == null ? "" : s; }

  public boolean anyFormOk(LinkedHashMap<String, String> kv, String addr) {
    ArrayList<String[]> forms = formsOf(kv);
    for (int i = 0; i < forms.size(); i++) {
      String[] f = forms.get(i);
      if (addrOk(f[1], f[2], f[3], f[4], addr)) return true;
    }
    return false;
  }

  // what the phone will say before it installs a lesson. Domains come from the server rows only.
  public String confirmText(LinkedHashMap<String, String> kv) {
    ArrayList<String> hosts = new ArrayList<String>();
    for (String k : kv.keySet()) {
      if (!k.startsWith("server/")) continue;
      String u = kv.get(k).replaceFirst("^https?://", "");
      int cut = u.length();
      for (int i = 0; i < u.length(); i++) { char c = u.charAt(i); if (c == '/' || c == ':' || c == '?' || c == '#') { cut = i; break; } }
      String h = u.substring(0, cut);
      if (!hosts.contains(h)) hosts.add(h);
    }
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < hosts.size(); i++) { if (i > 0) sb.append(", "); sb.append(hosts.get(i)); }
    return "Add " + kv.get("coin/name") + " (" + kv.get("coin/ticker") + ")?  ANA will send the addresses you watch to: " + sb;
  }

  // ===================== preview picture =====================

  public byte[] previewPng(String title, String l1, String l2, String l3) {
    try {
      BufferedImage im = new BufferedImage(640, 360, BufferedImage.TYPE_INT_RGB);
      Graphics2D g = im.createGraphics();
      g.setColor(new Color(18, 22, 30)); g.fillRect(0, 0, 640, 360);
      g.setColor(new Color(60, 120, 220)); g.fillRect(0, 0, 640, 10);
      try {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(new Color(150, 170, 200)); g.setFont(new Font("SansSerif", Font.BOLD, 22));
        g.drawString("ANA  \u00b7  LESSON", 32, 60);
        g.setColor(Color.WHITE); g.setFont(new Font("SansSerif", Font.BOLD, 44));
        g.drawString(title, 32, 140);
        g.setColor(new Color(200, 210, 225)); g.setFont(new Font("SansSerif", Font.PLAIN, 24));
        g.drawString(l1, 32, 200); g.drawString(l2, 32, 236); g.drawString(l3, 32, 272);
        g.setColor(new Color(120, 135, 160)); g.setFont(new Font("SansSerif", Font.PLAIN, 18));
        g.drawString(".pngmesh  \u00b7  check with its .sha256", 32, 330);
      } catch (Throwable t) { /* no fonts available: keep the plain card */ }
      g.dispose();
      ByteArrayOutputStream bo = new ByteArrayOutputStream();
      ImageIO.write(im, "png", bo);
      return bo.toByteArray();
    } catch (Throwable t) {
      return b64dec("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");
    }
  }

  // ===================== web: curl first (modern TLS on Windows 11), plain Java as a fallback =====================

  public String cq(String s) {
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
  }

  // returns { statusCode, body }.  statusCode "0" means the request itself failed (body then holds the reason)
  public String[] http(String method, String url, String body, int timeoutSec) {
    try {
      boolean win = System.getProperty("os.name", "").toLowerCase().indexOf("win") >= 0;
      StringBuilder c = new StringBuilder();
      c.append("silent\nshow-error\nlocation\nmax-time = ").append(timeoutSec).append("\n");
      c.append("user-agent = \"ANA-LessonMaker/1\"\nheader = \"accept: application/json\"\n");
      c.append("write-out = \"\\n|||%{http_code}\"\n");
      if (!"GET".equals(method)) c.append("request = \"").append(method).append("\"\n");
      if (body != null) c.append("header = \"content-type: application/json\"\ndata-binary = \"").append(cq(body)).append("\"\n");
      c.append("url = \"").append(cq(url)).append("\"\n");
      ProcessBuilder pb = new ProcessBuilder(win ? "curl.exe" : "curl", "-K", "-");
      pb.redirectErrorStream(true);
      Process pr = pb.start();
      OutputStream os = pr.getOutputStream();
      os.write(utf8(c.toString()));
      os.close();
      InputStream is = pr.getInputStream();
      ByteArrayOutputStream bo = new ByteArrayOutputStream();
      byte[] buf = new byte[8192];
      int n;
      while ((n = is.read(buf)) > 0) bo.write(buf, 0, n);
      pr.waitFor();
      String out = fromUtf8(bo.toByteArray());
      Matcher m = Pattern.compile("\\n\\|\\|\\|([0-9]{3})").matcher(out);
      int at = -1, endAt = 0;
      String code = "0";
      while (m.find()) { at = m.start(); endAt = m.end(); code = m.group(1); }
      if (at < 0) return new String[] { "0", out.trim() };
      String rest = out.substring(endAt).trim();
      if (code.equals("000")) return new String[] { "0", rest.length() > 0 ? rest : "could not connect" };
      return new String[] { code, out.substring(0, at) };
    } catch (IOException ioe) {
      return httpFallback(method, url, body, timeoutSec);
    } catch (Exception e) {
      return new String[] { "0", "" + e };
    }
  }

  public String[] httpFallback(String method, String url, String body, int timeoutSec) {
    try {
      HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
      c.setConnectTimeout(timeoutSec * 1000); c.setReadTimeout(timeoutSec * 1000);
      c.setRequestProperty("accept", "application/json");
      c.setRequestProperty("User-Agent", "ANA-LessonMaker/1");
      c.setRequestMethod(method);
      if (body != null) {
        c.setDoOutput(true);
        c.setRequestProperty("content-type", "application/json");
        OutputStream os = c.getOutputStream(); os.write(utf8(body)); os.close();
      }
      int code = c.getResponseCode();
      InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
      ByteArrayOutputStream bo = new ByteArrayOutputStream();
      if (is != null) { byte[] buf = new byte[8192]; int n; while ((n = is.read(buf)) > 0) bo.write(buf, 0, n); }
      return new String[] { "" + code, fromUtf8(bo.toByteArray()) };
    } catch (Exception e) {
      return new String[] { "0", "" + e };
    }
  }

  // ===================== tiny JSON reader =====================

  public Object jparse(String s) {
    int[] p = new int[] { 0 };
    Object o = jval(s, p);
    jws(s, p);
    if (p[0] != s.length()) throw new RuntimeException("extra text after JSON");
    return o;
  }
  void jws(String s, int[] p) { while (p[0] < s.length() && Character.isWhitespace(s.charAt(p[0]))) p[0]++; }
  public void jexpect(String s, int[] p, char c) {
    jws(s, p);
    if (p[0] >= s.length() || s.charAt(p[0]) != c) throw new RuntimeException("JSON: expected " + c);
    p[0]++;
  }
  public Object jval(String s, int[] p) {
    jws(s, p);
    if (p[0] >= s.length()) throw new RuntimeException("JSON ended early");
    char c = s.charAt(p[0]);
    if (c == '{') {
      p[0]++;
      LinkedHashMap<String, Object> m = new LinkedHashMap<String, Object>();
      jws(s, p);
      if (s.charAt(p[0]) == '}') { p[0]++; return m; }
      while (true) {
        jws(s, p);
        String k = jstr(s, p);
        jexpect(s, p, ':');
        m.put(k, jval(s, p));
        jws(s, p);
        char d = s.charAt(p[0]++);
        if (d == '}') return m;
        if (d != ',') throw new RuntimeException("JSON: expected , or }");
      }
    }
    if (c == '[') {
      p[0]++;
      ArrayList<Object> l = new ArrayList<Object>();
      jws(s, p);
      if (s.charAt(p[0]) == ']') { p[0]++; return l; }
      while (true) {
        l.add(jval(s, p));
        jws(s, p);
        char d = s.charAt(p[0]++);
        if (d == ']') return l;
        if (d != ',') throw new RuntimeException("JSON: expected , or ]");
      }
    }
    if (c == '"') return jstr(s, p);
    if (s.startsWith("true", p[0])) { p[0] += 4; return Boolean.TRUE; }
    if (s.startsWith("false", p[0])) { p[0] += 5; return Boolean.FALSE; }
    if (s.startsWith("null", p[0])) { p[0] += 4; return null; }
    int a = p[0];
    while (p[0] < s.length() && "+-0123456789.eE".indexOf(s.charAt(p[0])) >= 0) p[0]++;
    if (a == p[0]) throw new RuntimeException("JSON: unexpected character " + c);
    return new BigDecimal(s.substring(a, p[0]));
  }
  public String jstr(String s, int[] p) {
    if (s.charAt(p[0]) != '"') throw new RuntimeException("JSON: expected a string");
    p[0]++;
    StringBuilder sb = new StringBuilder();
    while (true) {
      char c = s.charAt(p[0]++);
      if (c == '"') break;
      if (c == '\\') {
        char e = s.charAt(p[0]++);
        if (e == 'n') sb.append('\n'); else if (e == 't') sb.append('\t'); else if (e == 'r') sb.append('\r');
        else if (e == 'b') sb.append('\b'); else if (e == 'f') sb.append('\f');
        else if (e == 'u') { sb.append((char) Integer.parseInt(s.substring(p[0], p[0] + 4), 16)); p[0] += 4; }
        else sb.append(e);
      } else sb.append(c);
    }
    return sb.toString();
  }
  public Object jpath(Object o, String path) {
    if (path == null || path.length() == 0) return o;
    String[] parts = path.split("\\.");
    for (int i = 0; i < parts.length; i++) {
      if (o instanceof Map) o = ((Map) o).get(parts[i]);
      else if (o instanceof List) {
        int ix = Integer.parseInt(parts[i]);
        List l = (List) o;
        o = (ix >= 0 && ix < l.size()) ? l.get(ix) : null;
      } else return null;
      if (o == null) return null;
    }
    return o;
  }
  public BigInteger bigAt(Object j, String path) {
    Object v = jpath(j, path);
    if (v instanceof BigDecimal) return ((BigDecimal) v).toBigInteger();
    if (v instanceof String) return new BigInteger(((String) v).trim());
    return null;
  }

  // ===================== probes: ask a real server about the address and see if it answers =====================

  public class Probe {
    public boolean ok;
    public long ms;
    public String reader = "", url = "", params = "", note = "";
    public BigInteger raw;
  }

  public LinkedHashMap<String, String> params(String p) {
    LinkedHashMap<String, String> m = new LinkedHashMap<String, String>();
    if (p == null) return m;
    String[] parts = p.split(";");
    for (int i = 0; i < parts.length; i++) {
      int eq = parts[i].indexOf('=');
      if (eq > 0) m.put(parts[i].substring(0, eq).trim(), parts[i].substring(eq + 1).trim());
    }
    return m;
  }

  public Probe runProbe(String reader, String url, String paramStr, String address) {
    Probe pr = new Probe();
    pr.reader = reader; pr.url = url; pr.params = paramStr;
    long t0 = System.currentTimeMillis();
    try {
      LinkedHashMap<String, String> pm = params(paramStr);
      String[] r;
      if (reader.equals("esplora")) {
        String base = url.endsWith("/") ? url : url + "/";
        r = http("GET", base + "address/" + address, null, 20);
        if (!r[0].startsWith("2")) throw new Exception(r[0].equals("0") ? r[1] : "server said " + r[0]);
        Object j = jparse(r[1]);
        BigInteger f = bigAt(j, "chain_stats.funded_txo_sum"), s = bigAt(j, "chain_stats.spent_txo_sum");
        if (f == null || s == null) throw new Exception("reply has no chain_stats");
        BigInteger bal = f.subtract(s);
        BigInteger mf = bigAt(j, "mempool_stats.funded_txo_sum"), ms = bigAt(j, "mempool_stats.spent_txo_sum");
        if (mf != null && ms != null) bal = bal.add(mf).subtract(ms);
        pr.raw = bal;
      } else if (reader.equals("evm")) {
        String body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"" + address + "\",\"latest\"]}";
        r = http("POST", url, body, 20);
        if (!r[0].startsWith("2")) throw new Exception(r[0].equals("0") ? r[1] : "server said " + r[0]);
        Object res = jpath(jparse(r[1]), "result");
        if (!(res instanceof String) || !((String) res).startsWith("0x")) throw new Exception("reply has no result");
        String hx = ((String) res).substring(2);
        pr.raw = hx.length() == 0 ? BigInteger.ZERO : new BigInteger(hx, 16);
      } else if (reader.equals("json")) {
        String m = pm.containsKey("method") ? pm.get("method") : "GET";
        String body = pm.containsKey("body") ? pm.get("body").replace("{address}", address) : null;
        r = http(m, url.replace("{address}", address), body, 20);
        if (!r[0].startsWith("2")) throw new Exception(r[0].equals("0") ? r[1] : "server said " + r[0]);
        BigInteger v = bigAt(jparse(r[1]), pm.get("balance_path"));
        if (v == null) throw new Exception("the balance was not where balance_path says");
        pr.raw = v;
      } else throw new Exception("unknown reader " + reader);
      pr.ok = true;
    } catch (Exception e) {
      pr.ok = false;
      pr.note = "" + e.getMessage();
    }
    pr.ms = System.currentTimeMillis() - t0;
    return pr;
  }

  public String fmtAmount(BigInteger raw, int decimals, int shown) {
    return new BigDecimal(raw).movePointLeft(decimals).setScale(shown, RoundingMode.DOWN).toPlainString();
  }

  // probes.txt lines:  reader | coin id | server | settings   (settings are  name=value;name=value)
  public ArrayList<String[]> readRecipes(String text) {
    ArrayList<String[]> out = new ArrayList<String[]>();
    String[] lines = text.split("\r?\n");
    for (int i = 0; i < lines.length; i++) {
      String ln = lines[i].trim();
      if (ln.length() == 0 || ln.startsWith("#")) continue;
      String[] p = ln.split("\\|", -1);
      if (p.length < 3) continue;
      out.add(new String[] { p[0].trim(), p[1].trim().toLowerCase(), p[2].trim(), p.length > 3 ? p[3].trim() : "" });
    }
    return out;
  }

  public String defaultRecipes() {
    return "# reader | coin id (CoinGecko id) | server | settings\n"
      + "# Starting points only. A server that no longer answers simply shows as failed when you press Detect.\n"
      + "# Add your own lines. Never put an API key in here: lessons are readable by anyone.\n"
      + "esplora | bitcoin | https://mempool.space/api/ |\n"
      + "esplora | litecoin | https://litecoinspace.org/api/ |\n"
      + "evm | ethereum | https://ethereum-rpc.publicnode.com | chain_id=1\n"
      + "json | cardano | https://api.koios.rest/api/v1/address_info | method=POST;body={\"_addresses\":[\"{address}\"]};balance_path=0.balance;balance_type=text_integer\n";
  }

  // ===================== coin knowledge =====================

  public String[] known(String id) {
    String B32C = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    String B58C = "[1-9A-HJ-NP-Za-km-z]";
    if (id.equals("bitcoin")) return new String[] { "Bitcoin", "BTC", "8", "6",
      "address/form1.kind = bech32\naddress/form1.hrp = bc\naddress/form1.pattern = ^bc1[" + B32C + "]{25,87}$\n"
      + "address/form2.kind = base58check\naddress/form2.versions = 0,5\naddress/form2.pattern = ^[13]" + B58C + "{25,34}$\n" };
    if (id.equals("litecoin")) return new String[] { "Litecoin", "LTC", "8", "4",
      "address/form1.kind = bech32\naddress/form1.hrp = ltc\naddress/form1.pattern = ^ltc1[" + B32C + "]{25,87}$\n"
      + "address/form2.kind = base58check\naddress/form2.versions = 48,50\naddress/form2.pattern = ^[LM]" + B58C + "{25,34}$\n" };
    if (id.equals("ethereum")) return new String[] { "Ethereum", "ETH", "18", "5",
      "address/form1.kind = hex_evm\naddress/form1.pattern = ^0x[0-9a-fA-F]{40}$\n" };
    if (id.equals("cardano")) return new String[] { "Cardano", "ADA", "6", "4",
      "address/form1.kind = bech32\naddress/form1.hrp = addr\naddress/form1.pattern = ^addr1[" + B32C + "]{50,120}$\n" };
    return null;
  }

  // what the pasted address looks like, in plain words (also used to learn a form for a coin we do not know)
  public String describeShape(String a) {
    if (a == null || a.trim().length() == 0) return "";
    a = a.trim();
    int v = bech32Variant(a, null);
    if (v != 0) return (v == 2 ? "bech32m" : "bech32") + " address, prefix " + a.substring(0, a.toLowerCase().lastIndexOf('1')).toLowerCase() + ", " + a.length() + " characters, checksum OK";
    byte[] d = b58dec(a);
    if (d != null && b58checkOk(a, "" + (d[0] & 255))) return "base58check address, version byte " + (d[0] & 255) + ", checksum OK";
    if (a.matches("0x[0-9a-fA-F]{40}")) return "0x address (EVM family: Ethereum, Optimism, Base, Polygon ...)";
    return "shape not recognised";
  }

  public String learnForm(String a) {
    String B32C = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    if (a == null) return "address/form1.kind = ?\n";
    a = a.trim();
    if (bech32Variant(a, null) != 0) {
      String h = a.substring(0, a.toLowerCase().lastIndexOf('1')).toLowerCase();
      return "address/form1.kind = bech32\naddress/form1.hrp = " + h + "\naddress/form1.pattern = ^" + h + "1[" + B32C + "]{20,120}$\n";
    }
    byte[] d = b58dec(a);
    if (d != null && b58checkOk(a, "" + (d[0] & 255)))
      return "address/form1.kind = base58check\naddress/form1.versions = " + (d[0] & 255) + "\naddress/form1.pattern = ^[1-9A-HJ-NP-Za-km-z]{25,35}$\n";
    if (a.matches("0x[0-9a-fA-F]{40}"))
      return "address/form1.kind = hex_evm\naddress/form1.pattern = ^0x[0-9a-fA-F]{40}$\n";
    return "address/form1.kind = ?\n";
  }

  // an address that has the right shape but must FAIL the checksum, for the bad-address test
  public String mutateBad(String a) {
    if (a.matches("0x[0-9a-fA-F]{40}")) return a.substring(0, a.length() - 1);
    int pos = a.toLowerCase().lastIndexOf('1');
    boolean bech = bech32Variant(a, null) != 0;
    String alpha = bech ? B32 : B58;
    for (int back = 1; back < a.length() - pos; back++) {
      int at = a.length() - back;
      char c = a.charAt(at);
      for (int t = 0; t < alpha.length(); t++) {
        char r = alpha.charAt(t);
        if (r == c || (bech && Character.isUpperCase(c))) continue;
        String m = a.substring(0, at) + r + a.substring(at + 1);
        if (bech ? bech32Variant(m, null) == 0 : !b58checkOk(m, "0,5,48,50,111,196")) return m;
      }
    }
    return a.substring(0, a.length() - 1);
  }

  // ===================== coin lookup =====================

  public ArrayList<String[]> candidates(String name) {
    ArrayList<String[]> out = new ArrayList<String[]>();
    String n = name.trim().toLowerCase();
    if (n.length() == 0) return out;
    for (int i = 0; i < KNOWN_IDS.length; i++) {
      String[] k = known(KNOWN_IDS[i]);
      if (KNOWN_IDS[i].equals(n) || k[0].toLowerCase().equals(n) || k[1].toLowerCase().equals(n)) {
        out.add(new String[] { KNOWN_IDS[i], k[0], k[1] });
        return out;
      }
    }
    try {
      String[] r = http("GET", coingeckoBase + "/search?query=" + URLEncoder.encode(name.trim(), "UTF-8"), null, 20);
      if (!r[0].startsWith("2")) return out;
      Object coins = jpath(jparse(r[1]), "coins");
      if (coins instanceof List) {
        List l = (List) coins;
        for (int i = 0; i < l.size() && out.size() < 6; i++) {
          Object id = jpath(l.get(i), "id"), nm = jpath(l.get(i), "name"), sy = jpath(l.get(i), "symbol");
          if (id instanceof String && nm instanceof String) out.add(new String[] { (String) id, (String) nm, sy instanceof String ? (String) sy : "" });
        }
      }
    } catch (Exception e) { }
    return out;
  }

  // candidates from the pasted address alone, when no coin name was given
  public ArrayList<String[]> candidatesFromAddress(String addr) {
    ArrayList<String[]> out = new ArrayList<String[]>();
    if (addr == null || addr.trim().length() == 0) return out;
    for (int i = 0; i < KNOWN_IDS.length; i++) {
      try {
        LinkedHashMap<String, String> kv = parseDraft(known(KNOWN_IDS[i])[4]);
        if (anyFormOk(kv, addr.trim())) { String[] k = known(KNOWN_IDS[i]); out.add(new String[] { KNOWN_IDS[i], k[0], k[1] }); }
      } catch (Exception e) { }
    }
    return out;
  }

  public String priceUsd(String coinId) {
    try {
      String[] r = http("GET", coingeckoBase + "/simple/price?ids=" + URLEncoder.encode(coinId, "UTF-8") + "&vs_currencies=usd", null, 20);
      if (!r[0].startsWith("2")) return null;
      Object v = jpath(jparse(r[1]), coinId + ".usd");
      return v instanceof BigDecimal ? ((BigDecimal) v).toPlainString() : null;
    } catch (Exception e) { return null; }
  }

  // ===================== draft builder =====================

  public String draftFor(String[] cand, String address, ArrayList<Probe> okProbes) {
    String id = cand[0].toLowerCase().replaceAll("[^a-z0-9_-]", "-");
    if (id.length() > 32) id = id.substring(0, 32);
    String[] k = known(cand[0]);
    StringBuilder sb = new StringBuilder();
    sb.append("# ANA lesson draft. Edit anything you like, then press Build & Sign.\n");
    sb.append("# Lines starting with # are ignored. A value of ? means you still have to fill it in.\n\n");
    sb.append("lesson/id = ").append(id).append("\nlesson/version = 1\nlesson/needs_reader = 1\n\n");
    sb.append("coin/name = ").append(k != null ? k[0] : cand[1]).append("\n");
    sb.append("coin/ticker = ").append(k != null ? k[1] : cand[2].toUpperCase()).append("\n");
    sb.append("coin/decimals = ").append(k != null ? k[2] : "?").append("\n");
    sb.append("coin/display_decimals = ").append(k != null ? k[3] : "4").append("\n");
    sb.append("coin/price_id = ").append(cand[0]).append("\n\n");
    String forms = k != null ? k[4] : learnForm(address);
    sb.append(forms).append("\n");
    String reader = "?";
    ArrayList<String> urls = new ArrayList<String>();
    String settings = "";
    for (int i = 0; i < okProbes.size(); i++) {
      Probe p = okProbes.get(i);
      if (reader.equals("?")) { reader = p.reader; settings = p.params; }
      if (p.reader.equals(reader) && !urls.contains(p.url)) urls.add(p.url);
    }
    sb.append("reader/name = ").append(reader).append("\n");
    if (urls.isEmpty()) sb.append("server/1 = ?\n"); else for (int i = 0; i < urls.size(); i++) sb.append("server/").append(i + 1).append(" = ").append(urls.get(i)).append("\n");
    LinkedHashMap<String, String> pm = params(settings);
    for (String pk : pm.keySet()) sb.append("param/").append(pk).append(" = ").append(pm.get(pk)).append("\n");
    sb.append("\n");
    if (address != null && address.trim().length() > 0) {
      String a = address.trim();
      sb.append("test/good.1 = ").append(a).append("\n");
      sb.append("test/bad.1 = ").append(mutateBad(a)).append("\n");
      sb.append("test/probe_address = ").append(a).append("\n");
    } else {
      sb.append("test/good.1 = ?\ntest/bad.1 = ?\n");
    }
    return sb.toString();
  }
}