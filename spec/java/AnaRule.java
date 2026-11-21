import java.io.*;
import java.math.BigInteger;
import java.util.*;

// ANA Rule v1 - Java implementation (see ../SPEC.md). Written separately from the Python reference.
// The P-256 maths, SHA-256, base64, address checks and lint come from the Lesson Maker's Engine, unchanged.
// Plain Java 6 (no lambdas, no diamond, no try-with-resources) so the same code can go into Android and Processing.
public class AnaRule {

  public static final int CLASS_LESSON = 30, CLASS_PERMIT = 31, CLASS_REVOKE = 32;
  public static final String[] HIVES_ALL = { "watch", "efinote", "clipnote", "pacenote", "hivenote", "flex" };
  public static final String[] HIVES_LEVEL1 = { "watch" };

  final Engine E = new Engine();
  final int reader;
  final String tier;
  final List<String> hives;
  final LinkedHashMap<String, byte[]> trusted = new LinkedHashMap<String, byte[]>();   // key id -> raw public key
  int seq = 0;
  String head = zeros64();
  final HashMap<Integer, String> chain = new HashMap<Integer, String>();
  final HashSet<String> revoked = new HashSet<String>(), frozen = new HashSet<String>();
  final HashMap<String, String> lessonVer = new HashMap<String, String>(), lessonHash = new HashMap<String, String>();

  public AnaRule(int reader, String tier, List<String> hives, List<String> trustedRawHex) {
    this.reader = reader;
    this.tier = tier;
    this.hives = hives;
    for (int i = 0; i < trustedRawHex.size(); i++) {
      byte[] raw = E.fromHex(trustedRawHex.get(i));
      trusted.put(E.toHex(E.sha256(raw)), raw);
    }
  }

  static String zeros64() { StringBuilder s = new StringBuilder(); for (int i = 0; i < 64; i++) s.append('0'); return s.toString(); }

  // ---------------------------------------------------------------- the container
  static class Bad extends Exception { Bad(String m) { super(m); } }

  static class Signed {
    int cls;
    LinkedHashMap<String, String> kv = new LinkedHashMap<String, String>();   // "section|key" -> value, sig rows excluded
    byte[] body;
    String keyId;
    byte[] sig;
  }

  int u32(byte[] t, int[] p) throws Bad {
    if (p[0] + 4 > t.length) throw new Bad("short");
    int v = ((t[p[0]] & 255) << 24) | ((t[p[0] + 1] & 255) << 16) | ((t[p[0] + 2] & 255) << 8) | (t[p[0] + 3] & 255);
    p[0] += 4;
    return v;
  }

  String str(byte[] t, int[] p) throws Bad {
    int n = u32(t, p);
    if (n < 0 || n > 16777216 || p[0] + n > t.length) throw new Bad("bad string");
    try {
      java.nio.charset.CharsetDecoder d = java.nio.charset.Charset.forName("UTF-8").newDecoder();
      String s = d.decode(java.nio.ByteBuffer.wrap(t, p[0], n)).toString();
      p[0] += n;
      return s;
    } catch (Exception e) { throw new Bad("bad utf-8"); }
  }

  Signed parseSigned(byte[] f) throws Bad {
    if (f == null || f.length < 20) throw new Bad("too small");
    long tl = 0;
    for (int i = 0; i < 8; i++) tl = (tl << 8) | (f[f.length - 8 + i] & 255);
    long start = (long) f.length - 8 - tl;
    if (tl < 12 || start < 0) throw new Bad("no trailer");
    byte[] t = Arrays.copyOfRange(f, (int) start, f.length - 8);
    if (t[0] != 'P' || t[1] != 'M' || t[2] != 'S' || t[3] != 'H') throw new Bad("magic");
    int[] p = new int[] { 4 };
    if (u32(t, p) != 1 || u32(t, p) != 1) throw new Bad("version or parts");
    Signed s = new Signed();
    s.cls = u32(t, p);
    if (u32(t, p) != 3 || !str(t, p).equals("section") || !str(t, p).equals("key") || !str(t, p).equals("value")) throw new Bad("columns");
    int nr = u32(t, p);
    if (nr < 3 || nr > 100000) throw new Bad("rows");
    String[][] rows = new String[nr][];
    int last = 0;
    for (int i = 0; i < nr; i++) {
      if (i == nr - 1) last = p[0];
      rows[i] = new String[] { str(t, p), str(t, p), str(t, p) };
    }
    if (p[0] != t.length) throw new Bad("extra bytes");
    String[] kidRow = rows[nr - 2], sigRow = rows[nr - 1];
    if (!kidRow[0].equals("sig") || !kidRow[1].equals("key_id") || !sigRow[0].equals("sig") || !sigRow[1].equals("value")) throw new Bad("sig rows");
    if (!kidRow[2].matches("[0-9a-f]{64}") || !sigRow[2].matches("[0-9a-f]{128}")) throw new Bad("sig hex");
    String okSections = "|lesson|coin|address|reader|server|param|test|permit|chain|revoke|";
    for (int i = 0; i < nr - 2; i++) {
      if (okSections.indexOf("|" + rows[i][0] + "|") < 0) throw new Bad("section " + rows[i][0]);
      String k = rows[i][0] + "|" + rows[i][1];
      if (s.kv.containsKey(k)) throw new Bad("duplicate row " + k);
      s.kv.put(k, rows[i][2]);
    }
    s.body = Arrays.copyOfRange(t, 0, last);
    s.keyId = kidRow[2];
    s.sig = E.fromHex(sigRow[2]);
    return s;
  }

  // ---------------------------------------------------------------- signatures (Spec section 4)
  byte[] message(int cls, byte[] body) {
    return E.cat(E.utf8("ANA-PMSH1|" + cls + "|"), E.sha256(body));
  }

  boolean highS(byte[] sig) { return new BigInteger(1, Arrays.copyOfRange(sig, 32, 64)).compareTo(E.N.shiftRight(1)) > 0; }

  boolean verify(byte[] raw, byte[] msg, byte[] sig) {
    if (raw == null || raw.length != 65 || raw[0] != 4 || sig.length != 64 || highS(sig)) return false;
    byte[] ri = E.derInt(new BigInteger(1, Arrays.copyOfRange(sig, 0, 32)));
    byte[] si = E.derInt(new BigInteger(1, Arrays.copyOfRange(sig, 32, 64)));
    byte[] der = new byte[2 + ri.length + si.length];
    der[0] = 0x30;
    der[1] = (byte) (ri.length + si.length);
    System.arraycopy(ri, 0, der, 2, ri.length);
    System.arraycopy(si, 0, der, 2 + ri.length, si.length);
    return E.verifyMsg(E.cat(E.fromHex(E.SPKI_PREFIX), raw), msg, der);
  }

  // ---------------------------------------------------------------- the check (Spec section 8)
  public String[] check(byte[] f, byte[] sidecar) {
    String want = sidecar == null ? null : E.sidecarHash(sidecar);
    if (want == null || !want.equals(E.sha256hex(f))) return v("BAD_SIDECAR", "");
    Signed s;
    try { s = parseSigned(f); } catch (Bad b) { return v("BAD_FORMAT", b.getMessage()); }
    if (s.cls != CLASS_LESSON && s.cls != CLASS_PERMIT && s.cls != CLASS_REVOKE) return v("BAD_FORMAT", "class");
    if (highS(s.sig)) return v("HIGH_S", "");
    byte[] msg = message(s.cls, s.body);
    String bh = E.sha256hex(s.body);

    if (s.cls != CLASS_LESSON) {
      if (!trusted.containsKey(s.keyId)) return v("UNKNOWN_KEY", "");
      if (frozen.contains(s.keyId)) return v("FROZEN", "");
      if (revoked.contains(s.keyId)) return v("REVOKED", "");
      if (!verify(trusted.get(s.keyId), msg, s.sig)) return v("BAD_SIGNATURE", "");
      return chainStep(s, bh);
    }

    byte[] raw = trusted.get(s.keyId);
    Signed permit = null;
    if (raw == null) {
      String pf = s.kv.get("permit|file");
      if (pf == null) return v("UNKNOWN_KEY", "");
      try {
        permit = parseSigned(E.b64dec(pf));
      } catch (Exception e) { return v("BAD_FORMAT", "permit"); }
      if (permit.cls != CLASS_PERMIT || highS(permit.sig)) return v("BAD_FORMAT", "permit");
      byte[] proot = trusted.get(permit.keyId);
      if (proot == null || !verify(proot, message(CLASS_PERMIT, permit.body), permit.sig)) return v("UNKNOWN_KEY", "permit");
      String pk = permit.kv.get("permit|key");
      if (pk == null || !pk.matches("[0-9a-f]{130}")) return v("BAD_FORMAT", "permit key");
      raw = E.fromHex(pk);
      if (!E.toHex(E.sha256(raw)).equals(s.keyId)) return v("UNKNOWN_KEY", "permit is for another key");
    }
    if (revoked.contains(s.keyId) || (permit != null && revoked.contains(permit.keyId))) return v("REVOKED", "");
    if (!verify(raw, msg, s.sig)) return v("BAD_SIGNATURE", "");

    int need = intOr(s.kv.get("lesson|needs_reader"), -1);
    if (need < 1) return v("BAD_RULES", "lesson|needs_reader");
    String hive = nz(s.kv.get("lesson|hive"));
    if (need > reader) return v("UPDATE_FIRST", "needs reader " + need);
    if (!in(hive, HIVES_LEVEL1)) return in(hive, HIVES_ALL) ? v("UPDATE_FIRST", "hive " + hive) : v("BAD_RULES", "lesson|hive");
    String lt = nz(s.kv.get("lesson|tier"));
    if (permit != null) {
      if (seq >= intOr(permit.kv.get("permit|until_seq"), 0)) return v("EXPIRED", "");
      String tk = nz(s.kv.get("coin|ticker"));
      List<String> tickers = list(permit.kv.get("permit|tickers"));
      if (!list(permit.kv.get("permit|tiers")).contains(lt) || !list(permit.kv.get("permit|hives")).contains(hive)
          || !(tickers.contains("*") || tickers.contains(tk))) return v("NOT_PERMITTED", "");
    }
    if (!hives.contains(hive)) return v("WRONG_HIVE", "");
    if (lt.equals("statia") && !tier.equals("statia")) return v("WRONG_TIER", "");
    String id = nz(s.kv.get("lesson|id"));
    int ver = intOr(s.kv.get("lesson|version"), -1);
    if (ver < 1) return v("BAD_RULES", "lesson|version");
    if (lessonVer.containsKey(id)) {
      int iv = Integer.parseInt(lessonVer.get(id));
      if (ver < iv) return v("OLDER", "");
      if (ver == iv) return lessonHash.get(id).equals(bh) ? v("DUPLICATE", "") : v("FORK", "");
    }
    ArrayList<String> errs = lintLesson(s.kv);
    if (!errs.isEmpty()) return v("BAD_RULES", errs.toString());
    lessonVer.put(id, "" + ver);
    lessonHash.put(id, bh);
    return v("ACCEPT", "");
  }

  String[] chainStep(Signed s, String bh) {
    int n = intOr(s.kv.get("chain|seq"), -1);
    String prev = s.kv.get("chain|prev");
    if (n < 1 || prev == null || !prev.matches("[0-9a-f]{64}")) return v("BAD_FORMAT", "chain rows");
    if (chain.containsKey(n)) {
      if (chain.get(n).equals(bh)) return v("DUPLICATE", "");
      frozen.addAll(trusted.keySet());
      return v("FORK", "");
    }
    if (n > seq + 1) return v("HOLE", "have " + seq);
    if (!prev.equals(head)) { frozen.addAll(trusted.keySet()); return v("FORK", "prev"); }
    if (s.cls == CLASS_PERMIT) {
      String pk = s.kv.get("permit|key");
      if (pk == null || !pk.matches("04[0-9a-f]{128}") || intOr(s.kv.get("permit|until_seq"), -1) < 0) return v("BAD_FORMAT", "permit rows");
    } else {
      List<String> ks = list(s.kv.get("revoke|keys"));
      if (ks.isEmpty()) return v("BAD_FORMAT", "revoke rows");
      for (int i = 0; i < ks.size(); i++) if (!ks.get(i).matches("[0-9a-f]{64}")) return v("BAD_FORMAT", "revoke rows");
      revoked.addAll(ks);
    }
    chain.put(n, bh);
    seq = n;
    head = bh;
    return v("ACCEPT", "");
  }

  // The Lesson Maker's own lint (Engine.lint), fed in its "section/key" form, plus the two rows it predates.
  ArrayList<String> lintLesson(LinkedHashMap<String, String> kv) {
    LinkedHashMap<String, String> old = new LinkedHashMap<String, String>();
    for (Map.Entry<String, String> e : kv.entrySet()) {
      String k = e.getKey();
      if (k.startsWith("permit|") || k.equals("lesson|hive") || k.equals("lesson|tier")) continue;
      old.put(k.replaceFirst("\\|", "/"), e.getValue());
    }
    ArrayList<String> errs = E.lint(old, false);
    String t = nz(kv.get("lesson|tier"));
    if (!t.equals("ana") && !t.equals("statia")) errs.add("lesson|tier: ana or statia");
    return errs;
  }

  // ---------------------------------------------------------------- small helpers
  static String[] v(String verdict, String why) { return new String[] { verdict, why }; }
  static String nz(String s) { return s == null ? "" : s; }
  static boolean in(String s, String[] a) { for (int i = 0; i < a.length; i++) if (a[i].equals(s)) return true; return false; }
  static int intOr(String s, int d) { try { return Integer.parseInt(s.trim()); } catch (Exception e) { return d; } }
  static List<String> list(String s) {
    ArrayList<String> o = new ArrayList<String>();
    if (s == null) return o;
    String[] p = s.split(",");
    for (int i = 0; i < p.length; i++) if (p[i].trim().length() > 0) o.add(p[i].trim());
    return o;
  }
}
