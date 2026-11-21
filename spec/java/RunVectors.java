import java.io.*;
import java.util.*;

// Runs every scenario in vectors.json through AnaRule (a fresh phone per scenario) and compares each verdict.
// Usage: java RunVectors ../vectors
public class RunVectors {
  public static void main(String[] args) throws Exception {
    File dir = new File(args.length > 0 ? args[0] : "../vectors");
    Engine E = new Engine();
    Map doc = (Map) E.jparse(new String(read(new File(dir, "vectors.json")), "UTF-8"));
    List trusted = (List) doc.get("trusted_raw");
    Map builds = (Map) doc.get("builds");
    List scen = (List) doc.get("scenarios");
    int total = 0, fails = 0;
    for (int i = 0; i < scen.size(); i++) {
      Map sc = (Map) scen.get(i);
      Map b = (Map) builds.get(sc.get("build"));
      ArrayList<String> hv = new ArrayList<String>();
      List h = (List) b.get("hives");
      for (int j = 0; j < h.size(); j++) hv.add((String) h.get(j));
      ArrayList<String> tr = new ArrayList<String>();
      for (int j = 0; j < trusted.size(); j++) tr.add((String) trusted.get(j));
      AnaRule phone = new AnaRule(((java.math.BigDecimal) b.get("reader")).intValue(), (String) b.get("tier"), hv, tr);
      List steps = (List) sc.get("steps");
      for (int j = 0; j < steps.size(); j++) {
        Map st = (Map) steps.get(j);
        String name = (String) st.get("file");
        String[] got = phone.check(read(new File(dir, name)), read(new File(dir, name + ".sha256")));
        boolean ok = got[0].equals(st.get("expect"));
        total++;
        if (!ok) fails++;
        System.out.println((ok ? "ok   " : "FAIL ") + pad((String) sc.get("name"), 19) + pad(name, 37) + got[0] + (ok ? "" : "  expected " + st.get("expect") + "  " + got[1]));
      }
    }
    System.out.println("java: " + (total - fails) + "/" + total + " verdicts as expected");
    System.exit(fails == 0 ? 0 : 1);
  }

  static String pad(String s, int n) { StringBuilder b = new StringBuilder(s); while (b.length() < n) b.append(' '); return b.toString(); }

  static byte[] read(File f) throws IOException {
    if (!f.exists()) return null;
    FileInputStream in = new FileInputStream(f);
    ByteArrayOutputStream o = new ByteArrayOutputStream();
    byte[] buf = new byte[8192];
    int n;
    while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
    in.close();
    return o.toByteArray();
  }
}
