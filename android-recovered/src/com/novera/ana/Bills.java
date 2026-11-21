package com.novera.ana;

import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.os.Build;
import android.text.TextUtils;
import android.util.Base64;
import com.novera.ana.BillCore;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import org.json.JSONArray;
import org.json.JSONObject;

/* loaded from: classes.dex */
final class Bills {
    static final String PKG = "ana.flex";
    private static boolean loaded;
    private static String myKey;
    static volatile Consumer<String> toIphone;
    static final List<Bill> list = new ArrayList();
    static final List<JSONObject> earned = new ArrayList();
    static final List<JSONObject> confirms = new ArrayList();
    static final Set<String> used = new HashSet();
    static final Set<String> seenHelps = new HashSet();
    private static final BillCore.Signer SIGNER = new Bills$$ExternalSyntheticLambda1();
    static final byte[] DOT = BillCore.unhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082");

    private Bills() {
    }

    static final class Help {
        long at;
        long cents;
        String hid = "";
        String helperKey = "";
        String helperName = "";
        String proof = "";
        String note = "";
        String occ = "";

        Help() {
        }

        JSONObject json() throws Exception {
            return new JSONObject().put("hid", this.hid).put("helperKey", this.helperKey).put("helperName", this.helperName).put("proof", this.proof).put("note", this.note).put("occ", this.occ).put("cents", this.cents).put("at", this.at);
        }

        static Help from(JSONObject jSONObject) {
            Help help = new Help();
            help.hid = jSONObject.optString("hid");
            help.helperKey = jSONObject.optString("helperKey");
            help.helperName = jSONObject.optString("helperName");
            help.proof = jSONObject.optString("proof");
            help.note = jSONObject.optString("note");
            help.occ = jSONObject.optString("occ");
            help.cents = jSONObject.optLong("cents");
            help.at = jSONObject.optLong("at");
            return help;
        }
    }

    static final class Occ {
        boolean onTime;
        long paidAt;
        double pts;
        String state = "open";
        String note = "";
        String key = "";

        Occ() {
        }

        JSONObject json() throws Exception {
            return new JSONObject().put("state", this.state).put("note", this.note).put("key", this.key).put("paidAt", this.paidAt).put("onTime", this.onTime).put("pts", this.pts);
        }

        static Occ from(JSONObject jSONObject) {
            Occ occ = new Occ();
            occ.state = jSONObject.optString("state", "open");
            occ.note = jSONObject.optString("note");
            occ.key = jSONObject.optString("key");
            occ.paidAt = jSONObject.optLong("paidAt");
            occ.onTime = jSONObject.optBoolean("onTime");
            occ.pts = jSONObject.optDouble("pts", 0.0d);
            return occ;
        }
    }

    static final class Bill {
        long billCents;
        long cents;
        int every;
        double helpPts;
        boolean shared;
        boolean thanked;
        String id = BillCore.newId();
        String kind = "plan";
        String name = "";
        String cur = "BBD";
        String due = "";
        String app = "";
        String appName = "";
        String unit = "month";
        long made = System.currentTimeMillis();
        String pic = "";
        String lock = "";
        String owner = "";
        String ownerLabel = "";
        String forBill = "";
        final LinkedHashMap<String, Occ> occ = new LinkedHashMap<>();
        final List<Help> helps = new ArrayList();
        String billId = "";
        String ownerKey = "";
        String ownerName = "";
        String hid = "";
        String reminded = "";

        Bill() {
        }

        boolean mine() {
            return this.owner.isEmpty();
        }

        List<String> dates() {
            ArrayList arrayList = new ArrayList();
            if (this.kind.equals("plan")) {
                return BillCore.schedule(this.due, this.every, this.unit);
            }
            arrayList.add(this.kind.equals("paid") ? BillCore.ymd(this.made) : "help");
            return arrayList;
        }

        Occ at(String str) {
            Occ occ = this.occ.get(str);
            if (occ != null) {
                return occ;
            }
            Occ occ2 = new Occ();
            this.occ.put(str, occ2);
            return occ2;
        }

        long helped(String str) {
            long j = 0;
            for (Help help : this.helps) {
                if (help.occ.equals(str) || help.occ.isEmpty()) {
                    j += help.cents;
                }
            }
            return j;
        }

        long[] window(String str) {
            if (this.kind.equals("plan")) {
                return BillCore.window(str, this.every, this.unit, this.made);
            }
            if (this.kind.equals("paid")) {
                long j = this.made;
                return new long[]{j - 604800000, j + 172800000, j + 172800000};
            }
            long j2 = this.made;
            return new long[]{j2 - 86400000, j2 + 1209600000, j2 + 1209600000};
        }

        String current() {
            long currentTimeMillis = System.currentTimeMillis();
            String str = null;
            for (String str2 : dates()) {
                Occ occ = this.occ.get(str2);
                if (occ == null || !"proven".equals(occ.state)) {
                    if (!this.kind.equals("plan") || this.cents - helped(str2) > 0) {
                        long[] window = window(str2);
                        if (window[2] >= currentTimeMillis || !this.kind.equals("plan")) {
                            if (window[0] <= currentTimeMillis) {
                                return str2;
                            }
                            if (str == null) {
                                str = str2;
                            }
                        }
                    }
                }
            }
            return str;
        }

        double pts() {
            Iterator<Occ> it = this.occ.values().iterator();
            double d = 0.0d;
            while (it.hasNext()) {
                d += it.next().pts;
            }
            return d + this.helpPts;
        }

        int provenCount() {
            Iterator<Occ> it = this.occ.values().iterator();
            int i = 0;
            while (it.hasNext()) {
                if ("proven".equals(it.next().state)) {
                    i++;
                }
            }
            return i;
        }

        JSONObject json() throws Exception {
            JSONArray jSONArray = new JSONArray();
            Iterator<Help> it = this.helps.iterator();
            while (it.hasNext()) {
                jSONArray.put(it.next().json());
            }
            JSONObject jSONObject = new JSONObject();
            for (Map.Entry<String, Occ> entry : this.occ.entrySet()) {
                jSONObject.put(entry.getKey(), entry.getValue().json());
            }
            return new JSONObject().put("id", this.id).put("kind", this.kind).put("name", this.name).put("cur", this.cur).put("due", this.due).put("app", this.app).put("appName", this.appName).put("every", this.every).put("unit", this.unit).put("cents", this.cents).put("made", this.made).put("pic", this.pic).put("lock", this.lock).put("owner", this.owner).put("ownerLabel", this.ownerLabel).put("shared", this.shared).put("occ", jSONObject).put("helps", jSONArray).put("billId", this.billId).put("ownerKey", this.ownerKey).put("ownerName", this.ownerName).put("hid", this.hid).put("reminded", this.reminded).put("billCents", this.billCents).put("thanked", this.thanked).put("helpPts", this.helpPts).put("forBill", this.forBill);
        }

        static Bill from(JSONObject jSONObject) {
            Bill bill = new Bill();
            bill.id = jSONObject.optString("id", bill.id);
            bill.kind = jSONObject.optString("kind", "plan");
            bill.name = jSONObject.optString("name");
            bill.cur = jSONObject.optString("cur", "BBD");
            bill.due = jSONObject.optString("due");
            bill.app = jSONObject.optString("app");
            bill.appName = jSONObject.optString("appName");
            bill.every = jSONObject.optInt("every");
            bill.unit = jSONObject.optString("unit", "month");
            bill.cents = jSONObject.optLong("cents");
            bill.made = jSONObject.optLong("made");
            bill.pic = jSONObject.optString("pic");
            bill.lock = jSONObject.optString("lock");
            bill.owner = jSONObject.optString("owner");
            bill.ownerLabel = jSONObject.optString("ownerLabel");
            bill.shared = jSONObject.optBoolean("shared");
            JSONObject optJSONObject = jSONObject.optJSONObject("occ");
            if (optJSONObject != null) {
                Iterator<String> keys = optJSONObject.keys();
                while (keys.hasNext()) {
                    String next = keys.next();
                    bill.occ.put(next, Occ.from(optJSONObject.optJSONObject(next)));
                }
            }
            JSONArray optJSONArray = jSONObject.optJSONArray("helps");
            if (optJSONArray != null) {
                for (int i = 0; i < optJSONArray.length(); i++) {
                    if (optJSONArray.optJSONObject(i) != null) {
                        bill.helps.add(Help.from(optJSONArray.optJSONObject(i)));
                    }
                }
            }
            bill.billId = jSONObject.optString("billId");
            bill.ownerKey = jSONObject.optString("ownerKey");
            bill.ownerName = jSONObject.optString("ownerName");
            bill.hid = jSONObject.optString("hid");
            bill.reminded = jSONObject.optString("reminded");
            bill.billCents = jSONObject.optLong("billCents");
            bill.thanked = jSONObject.optBoolean("thanked");
            bill.helpPts = jSONObject.optDouble("helpPts", 0.0d);
            bill.forBill = jSONObject.optString("forBill");
            return bill;
        }
    }

    static synchronized void load(Context context) {
        File file;
        synchronized (Bills.class) {
            if (!loaded && context != null) {
                loaded = true;
                try {
                    file = new File(context.getFilesDir(), "bills.json");
                } catch (Exception unused) {
                }
                if (file.exists()) {
                    JSONObject jSONObject = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                    JSONArray optJSONArray = jSONObject.optJSONArray("bills");
                    if (optJSONArray != null) {
                        for (int i = 0; i < optJSONArray.length(); i++) {
                            list.add(upgrade(optJSONArray.getJSONObject(i)));
                        }
                    }
                    JSONArray optJSONArray2 = jSONObject.optJSONArray("earned");
                    if (optJSONArray2 != null) {
                        for (int i2 = 0; i2 < optJSONArray2.length(); i2++) {
                            earned.add(optJSONArray2.getJSONObject(i2));
                        }
                    }
                    JSONArray optJSONArray3 = jSONObject.optJSONArray("confirms");
                    if (optJSONArray3 != null) {
                        for (int i3 = 0; i3 < optJSONArray3.length(); i3++) {
                            confirms.add(optJSONArray3.getJSONObject(i3));
                        }
                    }
                    JSONArray optJSONArray4 = jSONObject.optJSONArray("used");
                    if (optJSONArray4 != null) {
                        for (int i4 = 0; i4 < optJSONArray4.length(); i4++) {
                            used.add(optJSONArray4.getString(i4));
                        }
                    }
                    JSONArray optJSONArray5 = jSONObject.optJSONArray("seenHelps");
                    if (optJSONArray5 != null) {
                        for (int i5 = 0; i5 < optJSONArray5.length(); i5++) {
                            seenHelps.add(optJSONArray5.getString(i5));
                        }
                    }
                }
            }
        }
    }

    private static Bill upgrade(JSONObject jSONObject) {
        Bill from = Bill.from(jSONObject);
        if (from.occ.isEmpty() && jSONObject.has("state") && !"open".equals(jSONObject.optString("state"))) {
            List<String> dates = from.dates();
            if (!dates.isEmpty()) {
                Occ at = from.at(dates.get(0));
                at.state = jSONObject.optString("state");
                at.note = jSONObject.optString("proofNote");
                at.key = jSONObject.optString("proofKey");
                at.paidAt = jSONObject.optLong("paidAt");
                at.onTime = jSONObject.optBoolean("onTime");
                at.pts = jSONObject.optInt("pts");
            }
        }
        if (from.kind.equals("help") && jSONObject.has("pts") && from.thanked) {
            from.helpPts = jSONObject.optInt("pts");
        }
        return from;
    }

    static synchronized void save(Context context) {
        synchronized (Bills.class) {
            try {
                JSONArray jSONArray = new JSONArray();
                JSONArray jSONArray2 = new JSONArray();
                JSONArray jSONArray3 = new JSONArray();
                JSONArray jSONArray4 = new JSONArray();
                JSONArray jSONArray5 = new JSONArray();
                Iterator<Bill> it = list.iterator();
                while (it.hasNext()) {
                    jSONArray.put(it.next().json());
                }
                Iterator<JSONObject> it2 = earned.iterator();
                while (it2.hasNext()) {
                    jSONArray2.put(it2.next());
                }
                long currentTimeMillis = System.currentTimeMillis() - 3888000000L;
                for (JSONObject jSONObject : confirms) {
                    if (jSONObject.optLong("at") > currentTimeMillis) {
                        jSONArray3.put(jSONObject);
                    }
                }
                Iterator<String> it3 = used.iterator();
                while (it3.hasNext()) {
                    jSONArray4.put(it3.next());
                }
                Iterator<String> it4 = seenHelps.iterator();
                while (it4.hasNext()) {
                    jSONArray5.put(it4.next());
                }
                String jSONObject2 = new JSONObject().put("bills", jSONArray).put("earned", jSONArray2).put("confirms", jSONArray3).put("used", jSONArray4).put("seenHelps", jSONArray5).toString();
                File file = new File(context.getFilesDir(), "bills.json.tmp");
                FileOutputStream fileOutputStream = new FileOutputStream(file);
                try {
                    fileOutputStream.write(jSONObject2.getBytes(StandardCharsets.UTF_8));
                    fileOutputStream.close();
                    file.renameTo(new File(context.getFilesDir(), "bills.json"));
                } finally {
                }
            } catch (Exception unused) {
            }
        }
    }

    static synchronized Bill find(String str) {
        synchronized (Bills.class) {
            for (Bill bill : list) {
                if (bill.id.equals(str) && bill.mine()) {
                    return bill;
                }
            }
            return null;
        }
    }

    static synchronized double totalExact() {
        double d;
        synchronized (Bills.class) {
            Iterator<JSONObject> it = earned.iterator();
            d = 0.0d;
            while (it.hasNext()) {
                d += it.next().optDouble("pts", 0.0d);
            }
        }
        return d;
    }

    static int total() {
        return (int) Math.floor(totalExact() + 1.0E-9d);
    }

    static synchronized String text(Context context) {
        String str;
        synchronized (Bills.class) {
            load(context);
            int i = 0;
            int i2 = 0;
            for (Bill bill : list) {
                if (bill.mine()) {
                    i2++;
                    if (bill.kind.equals("help")) {
                        if (!bill.thanked) {
                            i++;
                        }
                    } else if (bill.current() != null) {
                        i++;
                    }
                }
            }
            Goal goal = goal();
            str = i + "\t" + total() + "\t" + i2 + "\t" + (goal.bills == 0 ? -1 : goal.pct);
        }
        return str;
    }

    static synchronized void earn(Context context, String str, double d, String str2) {
        synchronized (Bills.class) {
            if (d <= 0.0d) {
                return;
            }
            try {
                earned.add(new JSONObject().put("at", System.currentTimeMillis()).put("what", str).put("pts", d).put("pair", str2 == null ? "" : str2));
            } catch (Exception unused) {
            }
            AnaLog.append(context, "FLEX", System.currentTimeMillis(), PKG, "Bills", str + "  ·  +" + BillCore.pts(d) + " eFLEX", "bill-" + BillCore.newId(), 0L);
        }
    }

    static synchronized int pairCount(String str) {
        int i;
        synchronized (Bills.class) {
            long currentTimeMillis = System.currentTimeMillis() - 2592000000L;
            i = 1;
            for (JSONObject jSONObject : earned) {
                if (str.equals(jSONObject.optString("pair")) && jSONObject.optLong("at") > currentTimeMillis) {
                    i++;
                }
            }
        }
        return i;
    }

    static String pairOf(String str, String str2) {
        StringBuilder sb;
        if (str.compareTo(str2) < 0) {
            sb = new StringBuilder();
            sb.append(str);
            sb.append("|");
            sb.append(str2);
        } else {
            sb = new StringBuilder();
            sb.append(str2);
            sb.append("|");
            sb.append(str);
        }
        return sb.toString();
    }

    static String myKeyId() {
        String str = myKey;
        if (str != null) {
            return str;
        }
        byte[][] signRaw = Flex.signRaw("probe".getBytes(StandardCharsets.UTF_8));
        if (signRaw == null) {
            return "";
        }
        try {
            String hex = BillCore.hex(BillCore.sha(signRaw[0]));
            myKey = hex;
            return hex;
        } catch (Exception unused) {
            return "";
        }
    }

    static boolean genuine(Context context, String str) {
        try {
            PackageManager packageManager = context.getPackageManager();
            if ((packageManager.getApplicationInfo(str, 0).flags & 1) != 0) {
                return true;
            }
            return "com.android.vending".equals(Build.VERSION.SDK_INT >= 30 ? packageManager.getInstallSourceInfo(str).getInstallingPackageName() : packageManager.getInstallerPackageName(str));
        } catch (Exception unused) {
            return false;
        }
    }

    static List<BillCore.Note> notes(Context context) {
        ArrayList arrayList = new ArrayList();
        long currentTimeMillis = System.currentTimeMillis() - 34560000000L;
        HashMap hashMap = new HashMap();
        Iterator<String> it = AnaLog.readAll(context).iterator();
        while (it.hasNext()) {
            String[] split = it.next().split("\t", -1);
            if (split.length >= 7) {
                boolean z = split[0].equals("LIVE") || split[0].equals("SCAN");
                boolean equals = split[0].equals("IPHONE");
                if (z || equals) {
                    try {
                        long parseLong = Long.parseLong(split[2]);
                        if (parseLong >= currentTimeMillis) {
                            if (z) {
                                Boolean bool = (Boolean) hashMap.get(split[3]);
                                if (bool == null) {
                                    bool = Boolean.valueOf(genuine(context, split[3]));
                                    hashMap.put(split[3], bool);
                                }
                                if (!bool.booleanValue()) {
                                }
                            }
                            arrayList.add(new BillCore.Note(split[0], parseLong, split[3], split[4], split[5], split[6]));
                        }
                    } catch (NumberFormatException unused) {
                    }
                }
            }
        }
        return arrayList;
    }

    static List<String[]> recentApps(Context context) {
        ArrayList arrayList = new ArrayList();
        HashSet hashSet = new HashSet();
        List<BillCore.Note> notes = notes(context);
        long currentTimeMillis = System.currentTimeMillis() - 5184000000L;
        for (int size = notes.size() - 1; size >= 0; size--) {
            String str = notes.get(size).pkg;
            if (notes.get(size).at >= currentTimeMillis && !str.startsWith("ana.") && hashSet.add(str)) {
                arrayList.add(new String[]{str, notes.get(size).src});
            }
        }
        return arrayList;
    }

    static String fmtDay(long j) {
        return new SimpleDateFormat("EEE d MMM", Locale.US).format(new Date(j));
    }

    static String fmtDue(String str) {
        Calendar cal = BillCore.cal(str);
        return cal == null ? str : new SimpleDateFormat("EEE d MMM", Locale.US).format(cal.getTime());
    }

    static synchronized List<String> check(Context context) {
        ArrayList arrayList;
        List<BillCore.Note> list2;
        long j;
        ArrayList arrayList2;
        List<Long> list3;
        Iterator it;
        long j2;
        String str;
        synchronized (Bills.class) {
            load(context);
            arrayList = new ArrayList();
            Iterator<Bill> it2 = list.iterator();
            char c = 0;
            boolean z = false;
            while (it2.hasNext()) {
                if (!it2.next().app.isEmpty()) {
                    z = true;
                }
            }
            if (z) {
                List<BillCore.Note> notes = notes(context);
                long currentTimeMillis = System.currentTimeMillis();
                for (Bill bill : list) {
                    if (!bill.app.isEmpty() && (!bill.kind.equals("help") || !bill.thanked)) {
                        ArrayList arrayList3 = new ArrayList();
                        for (String str2 : bill.dates()) {
                            Occ occ = bill.occ.get(str2);
                            if (occ == null || !"proven".equals(occ.state)) {
                                if (!bill.kind.equals("plan") || bill.cents - bill.helped(str2) > 0) {
                                    if (bill.window(str2)[c] > currentTimeMillis) {
                                        break;
                                    }
                                    arrayList3.add(str2);
                                }
                            }
                        }
                        if (!arrayList3.isEmpty()) {
                            ArrayList arrayList4 = new ArrayList();
                            for (BillCore.Note note : notes) {
                                if (note.pkg.equals(bill.app) && !used.contains(note.key)) {
                                    arrayList4.add(note);
                                }
                            }
                            Collections.sort(arrayList4, new Comparator() { // from class: com.novera.ana.Bills$$ExternalSyntheticLambda0
                                @Override // java.util.Comparator
                                public final int compare(Object obj, Object obj2) {
                                    int compare;
                                    compare = Long.compare(((BillCore.Note) obj).at, ((BillCore.Note) obj2).at);
                                    return compare;
                                }
                            });
                            Iterator it3 = arrayList4.iterator();
                            while (true) {
                                if (!it3.hasNext()) {
                                    list2 = notes;
                                    j = currentTimeMillis;
                                    break;
                                }
                                BillCore.Note note2 = (BillCore.Note) it3.next();
                                List<Long> amountsIn = BillCore.amountsIn(note2.title + "\n" + note2.text);
                                Iterator it4 = arrayList3.iterator();
                                long j3 = Long.MAX_VALUE;
                                long j4 = 0L;
                                String str3 = null;
                                while (it4.hasNext()) {
                                    String str4 = (String) it4.next();
                                    long[] window = bill.window(str4);
                                    List<BillCore.Note> list4 = notes;
                                    if (note2.at >= window[c] && note2.at <= window[2]) {
                                        long helped = bill.cents - bill.helped(str4);
                                        long j5 = amountsIn.contains(Long.valueOf(bill.cents)) ? bill.cents : (helped <= 0 || helped >= bill.cents || !amountsIn.contains(Long.valueOf(helped))) ? -1L : helped;
                                        if (j5 >= 0) {
                                            List<Long> list5 = amountsIn;
                                            it = it4;
                                            long dayEnd = BillCore.dayEnd(BillCore.ymd(note2.at));
                                            list3 = list5;
                                            if (str4.equals("help")) {
                                                j2 = j5;
                                                str = BillCore.ymd(note2.at);
                                            } else {
                                                j2 = j5;
                                                str = str4;
                                            }
                                            long abs = Math.abs(dayEnd - BillCore.dayEnd(str)) / 86400000;
                                            if (abs < j3) {
                                                j3 = abs;
                                                str3 = str4;
                                                j4 = j2;
                                            }
                                            notes = list4;
                                            it4 = it;
                                            amountsIn = list3;
                                            c = 0;
                                        }
                                    }
                                    list3 = amountsIn;
                                    it = it4;
                                    notes = list4;
                                    it4 = it;
                                    amountsIn = list3;
                                    c = 0;
                                }
                                list2 = notes;
                                if (str3 != null) {
                                    long[] window2 = bill.window(str3);
                                    arrayList3.remove(str3);
                                    used.add(note2.key);
                                    Occ at = bill.at(str3);
                                    at.state = "proven";
                                    at.paidAt = note2.at;
                                    at.key = note2.key;
                                    at.onTime = note2.at <= window2[1];
                                    long j6 = j4;
                                    j = currentTimeMillis;
                                    at.note = "Proven: " + BillCore.money(j6, bill.cur) + " in a " + (bill.appName.isEmpty() ? bill.app : bill.appName) + " notification, " + fmtDay(note2.at) + (note2.src.equals("IPHONE") ? " (from the iPhone)" : "");
                                    if (bill.mine()) {
                                        arrayList2 = arrayList3;
                                        double award = award(bill, str3, j6);
                                        if (award > 0.0d) {
                                            earn(context, bill.name + " (" + (str3.equals("help") ? "help" : fmtDue(str3)) + "): " + (bill.kind.equals("plan") ? at.onTime ? "paid on time" : "paid late" : "paid"), award, null);
                                        }
                                        arrayList.add(bill.name + ": payment proven" + (award > 0.0d ? " (+" + BillCore.pts(award) + " eFLEX)" : ""));
                                        if (arrayList2.isEmpty()) {
                                            break;
                                        }
                                    } else {
                                        arrayList2 = arrayList3;
                                        arrayList.add((bill.ownerLabel.isEmpty() ? "iPhone" : bill.ownerLabel) + ": " + bill.name + " paid" + (confirm(context, bill, str3, j6, note2) ? ", confirmation sent" : ", confirmation waiting for the link"));
                                    }
                                    arrayList3 = arrayList2;
                                    currentTimeMillis = j;
                                }
                                notes = list2;
                                c = 0;
                            }
                            currentTimeMillis = j;
                            notes = list2;
                            c = 0;
                        }
                    }
                }
            }
            for (Bill bill2 : list) {
                if (bill2.mine()) {
                    remind(context, bill2);
                }
            }
            save(context);
        }
        return arrayList;
    }

    static double award(Bill bill, String str, long j) {
        if (bill.kind.equals("help") || !bill.forBill.isEmpty()) {
            return 0.0d;
        }
        Occ at = bill.at(str);
        if (j <= 0) {
            j = bill.cents;
        }
        double d = 0.5d;
        if (bill.kind.equals("plan") && at.onTime) {
            d = 1.0d;
        }
        if (bill.kind.equals("plan") && at.onTime && at.paidAt > 0 && at.paidAt <= BillCore.dayEnd(str) - 604800000) {
            d = 1.25d;
        }
        if ("claimed".equals(at.state)) {
            d *= 0.25d;
        }
        double points = BillCore.points(j, bill.cur, d);
        double max = Math.max(0.0d, points - at.pts);
        at.pts = Math.max(at.pts, points);
        return max;
    }

    static void remind(Context context, Bill bill) {
        String current;
        Calendar cal;
        String str;
        if (!bill.kind.equals("plan") || (current = bill.current()) == null || current.equals(bill.reminded)) {
            return;
        }
        Occ occ = bill.occ.get(current);
        if ((occ == null || "open".equals(occ.state)) && (cal = BillCore.cal(current)) != null) {
            cal.set(11, 9);
            List<String> dates = bill.dates();
            int size = (dates.size() - dates.indexOf(current)) - 1;
            long currentTimeMillis = System.currentTimeMillis();
            String str2 = "Bill due: " + bill.name;
            String money = BillCore.money(bill.cents, bill.cur);
            String repeatWords = BillCore.repeatWords(bill.every, bill.unit);
            if (size > 0) {
                str = "  ·  " + size + " more in the next 12 months";
            } else {
                str = "";
            }
            AnaLog.append(context, "REMIND", currentTimeMillis, PKG, str2, money + "  ·  " + repeatWords + str, "billdue-" + bill.id + "-" + current, 0L, cal.getTimeInMillis());
            bill.reminded = current;
        }
    }

    static boolean settled(Occ occ) {
        return occ != null && ("proven".equals(occ.state) || "claimed".equals(occ.state));
    }

    static long setAside(Bill bill) {
        String str = "";
        for (String str2 : bill.dates()) {
            if (settled(bill.occ.get(str2))) {
                str = str2;
            }
        }
        long j = 0;
        for (Bill bill2 : list) {
            if (bill2.forBill.equals(bill.id)) {
                for (Map.Entry<String, Occ> entry : bill2.occ.entrySet()) {
                    if (settled(entry.getValue()) && entry.getKey().compareTo(str) > 0) {
                        j += bill2.cents;
                    }
                }
            }
        }
        return j;
    }

    static final class Goal {
        int bills;
        long covered;
        final List<String> lines = new ArrayList();
        final List<String[]> open = new ArrayList();
        int pct;
        long total;

        Goal() {
        }
    }

    static synchronized Goal goal() {
        Goal goal;
        int i;
        long j;
        synchronized (Bills.class) {
            goal = new Goal();
            long currentTimeMillis = System.currentTimeMillis();
            long j2 = 2592000000L + currentTimeMillis;
            Iterator<Bill> it = list.iterator();
            while (true) {
                i = 0;
                if (!it.hasNext()) {
                    break;
                }
                Bill next = it.next();
                if (next.mine() && next.kind.equals("plan") && next.forBill.isEmpty()) {
                    long aside = setAside(next);
                    long j3 = 0;
                    long j4 = 0;
                    for (String str : next.dates()) {
                        long dayEnd = BillCore.dayEnd(str);
                        if (dayEnd >= currentTimeMillis) {
                            if (dayEnd > j2) {
                                break;
                            }
                            long helped = next.cents - next.helped(str);
                            long j5 = currentTimeMillis;
                            long round = Math.round(BillCore.usd(next.cents, next.cur) * 100.0d);
                            j3 += round;
                            if (!settled(next.occ.get(str)) && helped > 0) {
                                if (aside >= helped) {
                                    aside -= helped;
                                    j4 += round;
                                    currentTimeMillis = j5;
                                    i = 1;
                                } else {
                                    long j6 = j4;
                                    long j7 = j2;
                                    j = j6 + Math.round(BillCore.usd((next.cents - helped) + aside, next.cur) * 100.0d);
                                    List<String[]> list2 = goal.open;
                                    String str2 = next.id;
                                    String str3 = next.name;
                                    StringBuilder sb = new StringBuilder();
                                    sb.append(helped);
                                    list2.add(new String[]{str2, str3, sb.toString(), next.cur, str});
                                    j2 = j7;
                                    i = 1;
                                    aside = 0;
                                    j4 = j;
                                    currentTimeMillis = j5;
                                }
                            }
                            j = round + j4;
                            j2 = j2;
                            i = 1;
                            j4 = j;
                            currentTimeMillis = j5;
                        }
                    }
                    long j8 = currentTimeMillis;
                    long j9 = j2;
                    long j10 = j4;
                    if (i != 0) {
                        goal.bills++;
                        goal.total += j3;
                        goal.covered += j10;
                        goal.lines.add(next.name + ": " + (j10 >= j3 ? "settled" : Math.round((j10 * 100.0d) / Math.max(1L, j3)) + "% settled") + "  ·  " + ahead(next));
                    }
                    j2 = j9;
                    currentTimeMillis = j8;
                }
            }
            boolean z = false;
            for (Bill bill : list) {
                if (bill.mine() && bill.kind.equals("plan") && bill.forBill.isEmpty()) {
                    z = true;
                }
            }
            if (goal.bills == 0 && z) {
                goal.bills = 1;
                goal.pct = 100;
            } else {
                if (goal.total != 0) {
                    i = (int) Math.min(100.0d, Math.floor((goal.covered * 100.0d) / goal.total));
                }
                goal.pct = i;
            }
        }
        return goal;
    }

    static int aheadDays(Bill bill) {
        long currentTimeMillis = System.currentTimeMillis();
        long aside = setAside(bill);
        boolean z = true;
        for (String str : bill.dates()) {
            long dayEnd = BillCore.dayEnd(str);
            if (dayEnd >= currentTimeMillis) {
                long helped = bill.cents - bill.helped(str);
                boolean z2 = settled(bill.occ.get(str)) || helped <= 0;
                if (!z2 && aside >= helped) {
                    aside -= helped;
                    z2 = true;
                }
                if (!z2) {
                    if (z) {
                        return 0;
                    }
                    return (int) Math.max(0L, (dayEnd - currentTimeMillis) / 86400000);
                }
                z = false;
            }
        }
        return z ? 0 : 366;
    }

    static String ahead(Bill bill) {
        StringBuilder sb;
        String str;
        int aheadDays = aheadDays(bill);
        if (aheadDays >= 366) {
            return "settled for the year";
        }
        if (aheadDays >= 30) {
            sb = new StringBuilder();
            sb.append(aheadDays);
            str = " days ahead: off the payday cycle";
        } else {
            if (aheadDays <= 1) {
                return aheadDays == 1 ? "1 day ahead" : "not ahead yet";
            }
            sb = new StringBuilder();
            sb.append(aheadDays);
            str = " days ahead";
        }
        sb.append(str);
        return sb.toString();
    }

    static int enjoyed(Bill bill) {
        long currentTimeMillis = System.currentTimeMillis();
        long j = bill.made;
        Iterator<String> it = bill.dates().iterator();
        while (it.hasNext()) {
            long dayEnd = BillCore.dayEnd(it.next());
            if (dayEnd >= currentTimeMillis) {
                break;
            }
            j = dayEnd;
        }
        return (int) Math.max(0L, (currentTimeMillis - j) / 86400000);
    }

    static synchronized boolean passOn() {
        boolean z;
        synchronized (Bills.class) {
            z = false;
            boolean z2 = false;
            for (Bill bill : list) {
                if (bill.mine() && !bill.helps.isEmpty()) {
                    z2 = true;
                }
            }
            if (z2) {
                if (goal().pct >= 100) {
                    z = true;
                }
            }
        }
        return z;
    }

    static synchronized Bill addSetAside(Context context, Bill bill) {
        synchronized (Bills.class) {
            for (Bill bill2 : list) {
                if (bill2.forBill.equals(bill.id)) {
                    return bill2;
                }
            }
            long max = Math.max(1L, BillCore.period(bill.every, bill.unit) / 86400000);
            Bill bill3 = new Bill();
            bill3.kind = "plan";
            bill3.name = "Set aside: " + bill.name;
            bill3.cur = bill.cur;
            bill3.every = 1;
            bill3.unit = "day";
            bill3.cents = ((bill.cents + max) - 1) / max;
            bill3.due = BillCore.ymd(System.currentTimeMillis());
            bill3.forBill = bill.id;
            lock(bill3);
            List<Bill> list2 = list;
            list2.add(list2.indexOf(bill) + 1, bill3);
            save(context);
            return bill3;
        }
    }

    static synchronized String shareJourney(Context context, String str, boolean z) throws Exception {
        String str2;
        String write;
        synchronized (Bills.class) {
            Goal goal = goal();
            int i = goal.pct;
            StringBuilder sb = new StringBuilder();
            sb.append(i);
            String sb2 = sb.toString();
            long j = goal.covered;
            StringBuilder sb3 = new StringBuilder();
            sb3.append(j);
            String sb4 = sb3.toString();
            long j2 = goal.total;
            StringBuilder sb5 = new StringBuilder();
            sb5.append(j2);
            String sb6 = sb5.toString();
            long currentTimeMillis = System.currentTimeMillis();
            StringBuilder sb7 = new StringBuilder();
            sb7.append(currentTimeMillis);
            List<String[]> rows = rows("journey", "version", "1", "owner_name", str, "pct", sb2, "covered_usd_cents", sb4, "total_usd_cents", sb6, "made_ms", sb7.toString());
            int i2 = 0;
            for (String[] strArr : goal.open) {
                if (i2 >= 8) {
                    break;
                }
                rows.add(new String[]{"journey", "bill" + i2, strArr[0] + "\u001f" + strArr[1] + "\u001f" + strArr[2] + "\u001f" + strArr[3] + "\u001f" + strArr[4]});
                i2++;
            }
            if (z) {
                LinkedHashSet linkedHashSet = new LinkedHashSet();
                for (Bill bill : list) {
                    if (bill.mine()) {
                        Iterator<Help> it = bill.helps.iterator();
                        while (it.hasNext()) {
                            linkedHashSet.add(it.next().helperName);
                        }
                    }
                }
                rows.add(new String[]{"journey", "helped_by", TextUtils.join(", ", linkedHashSet)});
            }
            BillCore.Signer signer = SIGNER;
            String str3 = str + ": " + goal.pct + "% of the way to 30 days ahead";
            if (goal.open.isEmpty()) {
                str2 = "Everything due in the next 30 days is settled.";
            } else {
                str2 = goal.open.size() + " bill" + (goal.open.size() == 1 ? "" : "s") + " left to settle. Open with ANA to step in.";
            }
            write = write(context, "journey_" + BillCore.newId() + ".pngmesh", BillCore.build(45, rows, signer, picture("ANA journey", str3, str2 + " Novvera never touches money: helpers pay the biller themselves.")));
        }
        return write;
    }

    static List<String[]> journeyBills(BillCore.Signed signed) {
        ArrayList arrayList = new ArrayList();
        for (int i = 0; i < 8; i++) {
            String str = signed.get("journey|bill" + i);
            if (str.isEmpty()) {
                break;
            }
            String[] split = str.split("\u001f", -1);
            if (split.length == 5) {
                arrayList.add(split);
            }
        }
        return arrayList;
    }

    static synchronized Bill acceptFromJourney(Context context, BillCore.Signed signed, String[] strArr, long j) {
        Bill bill;
        synchronized (Bills.class) {
            bill = new Bill();
            bill.kind = "help";
            bill.billId = strArr[0];
            bill.ownerKey = signed.keyId;
            bill.ownerName = BillCore.clean(signed.get("journey|owner_name"));
            bill.name = BillCore.clean(strArr[1] + " (" + bill.ownerName + ")");
            bill.cur = strArr[3];
            bill.due = strArr[4];
            bill.billCents = num(strArr[2]);
            bill.cents = Math.max(1L, Math.min(j, bill.billCents));
            bill.hid = BillCore.newId();
            lock(bill);
            list.add(0, bill);
            save(context);
        }
        return bill;
    }

    static synchronized Bill addPlan(Context context, String str, long j, String str2, String str3, int i, String str4) {
        Bill bill;
        synchronized (Bills.class) {
            load(context);
            bill = new Bill();
            bill.kind = "plan";
            bill.name = BillCore.clean(str);
            bill.cents = j;
            bill.cur = str2;
            bill.due = str3;
            bill.every = i;
            bill.unit = str4;
            lock(bill);
            list.add(0, bill);
            remind(context, bill);
            save(context);
        }
        return bill;
    }

    static synchronized Bill addPaid(Context context, String str, long j, String str2) {
        Bill bill;
        synchronized (Bills.class) {
            load(context);
            bill = new Bill();
            bill.kind = "paid";
            bill.name = BillCore.clean(str);
            bill.cents = j;
            bill.cur = str2;
            lock(bill);
            list.add(0, bill);
            save(context);
        }
        return bill;
    }

    static void lock(Bill bill) {
        try {
            bill.lock = BillCore.hex(BillCore.sha(schedFile(bill, false)));
        } catch (Exception unused) {
            bill.lock = "";
        }
    }

    static synchronized void setApp(Context context, Bill bill, String str, String str2) {
        synchronized (Bills.class) {
            bill.app = str;
            bill.appName = str2;
            save(context);
        }
    }

    /* JADX WARN: Removed duplicated region for block: B:34:0x0087 A[Catch: all -> 0x00fc, TryCatch #0 {, blocks: (B:4:0x0007, B:10:0x0011, B:15:0x0023, B:17:0x0037, B:21:0x0045, B:23:0x0049, B:25:0x004f, B:26:0x0051, B:28:0x0059, B:32:0x0065, B:34:0x0087, B:35:0x008e, B:37:0x0099, B:40:0x00aa, B:41:0x00a6, B:42:0x00c7, B:44:0x00ce, B:45:0x00e6), top: B:3:0x0007 }] */
    /* JADX WARN: Removed duplicated region for block: B:37:0x0099 A[Catch: all -> 0x00fc, TryCatch #0 {, blocks: (B:4:0x0007, B:10:0x0011, B:15:0x0023, B:17:0x0037, B:21:0x0045, B:23:0x0049, B:25:0x004f, B:26:0x0051, B:28:0x0059, B:32:0x0065, B:34:0x0087, B:35:0x008e, B:37:0x0099, B:40:0x00aa, B:41:0x00a6, B:42:0x00c7, B:44:0x00ce, B:45:0x00e6), top: B:3:0x0007 }] */
    /* JADX WARN: Removed duplicated region for block: B:44:0x00ce A[Catch: all -> 0x00fc, TryCatch #0 {, blocks: (B:4:0x0007, B:10:0x0011, B:15:0x0023, B:17:0x0037, B:21:0x0045, B:23:0x0049, B:25:0x004f, B:26:0x0051, B:28:0x0059, B:32:0x0065, B:34:0x0087, B:35:0x008e, B:37:0x0099, B:40:0x00aa, B:41:0x00a6, B:42:0x00c7, B:44:0x00ce, B:45:0x00e6), top: B:3:0x0007 }] */
    /* JADX WARN: Removed duplicated region for block: B:49:0x00e4  */
    /* JADX WARN: Removed duplicated region for block: B:50:0x008c  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    static synchronized java.lang.String claim(android.content.Context r9, com.novera.ana.Bills.Bill r10, java.lang.String r11) {
        /*
            Method dump skipped, instructions count: 255
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Bills.claim(android.content.Context, com.novera.ana.Bills$Bill, java.lang.String):java.lang.String");
    }

    static synchronized void remove(Context context, Bill bill) {
        synchronized (Bills.class) {
            list.remove(bill);
            save(context);
        }
    }

    static File dir(Context context) {
        File file = new File(context.getFilesDir(), "bills");
        file.mkdirs();
        return file;
    }

    private static List<String[]> rows(String str, String... strArr) {
        ArrayList arrayList = new ArrayList();
        for (int i = 0; i < strArr.length; i += 2) {
            arrayList.add(new String[]{str, strArr[i], strArr[i + 1]});
        }
        return arrayList;
    }

    private static byte[] picture(String str, String str2, String str3) {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new String[]{"FLEX", Wallets.when(System.currentTimeMillis() / 1000.0d), "", PKG, str2, str3});
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        AnaMesh.preview(arrayList, str).compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream);
        return byteArrayOutputStream.toByteArray();
    }

    private static String write(Context context, String str, byte[] bArr) throws Exception {
        File dir = AnaFiles.dir(context);
        dir.mkdirs();
        FileOutputStream fileOutputStream = new FileOutputStream(new File(dir, str));
        try {
            fileOutputStream.write(bArr);
            fileOutputStream.close();
            fileOutputStream = new FileOutputStream(new File(dir, str.substring(0, str.length() - 8) + ".sha256"));
            try {
                fileOutputStream.write(AnaMesh.sidecar(str, bArr).getBytes(StandardCharsets.UTF_8));
                fileOutputStream.close();
                return str;
            } finally {
            }
        } finally {
        }
    }

    static byte[] schedFile(Bill bill, boolean z) throws Exception {
        String str = bill.id;
        String str2 = bill.kind;
        String str3 = bill.name;
        long j = bill.cents;
        StringBuilder sb = new StringBuilder();
        sb.append(j);
        String sb2 = sb.toString();
        String str4 = bill.cur;
        String str5 = bill.kind.equals("plan") ? bill.due : "";
        int i = bill.every;
        StringBuilder sb3 = new StringBuilder();
        sb3.append(i);
        String sb4 = sb3.toString();
        String str6 = bill.unit;
        long j2 = bill.made;
        StringBuilder sb5 = new StringBuilder();
        sb5.append(j2);
        List<String[]> rows = rows("sched", "version", "1", "id", str, "kind", str2, "name", str3, "cents", sb2, "currency", str4, "first_due", str5, "every", sb4, "unit", str6, "made_ms", sb5.toString());
        if (z) {
            rows.add(new String[]{"sched", "app", bill.app});
        }
        return BillCore.build(43, rows, SIGNER, DOT);
    }

    static synchronized String shareBill(Context context, Bill bill, String str) throws Exception {
        String write;
        synchronized (Bills.class) {
            String current = bill.current();
            if (current == null) {
                throw new Exception("nothing due");
            }
            long helped = bill.cents - bill.helped(current);
            String str2 = bill.id;
            String str3 = bill.name;
            StringBuilder sb = new StringBuilder();
            sb.append(helped);
            String sb2 = sb.toString();
            String str4 = bill.cur;
            long j = bill.made;
            StringBuilder sb3 = new StringBuilder();
            sb3.append(j);
            byte[] build = BillCore.build(40, rows("bill", "version", "1", "id", str2, "name", str3, "cents", sb2, "currency", str4, "due", current, "occ", current, "owner_name", str, "made_ms", sb3.toString()), SIGNER, picture("ANA bill", "Help pay: " + bill.name, BillCore.money(helped, bill.cur) + ", due " + current + ". Open with ANA to help. You both earn eFLEX."));
            bill.shared = true;
            save(context);
            write = write(context, "bill_" + bill.id + "_" + current + ".pngmesh", build);
        }
        return write;
    }

    static synchronized String shareReceipt(Context context, Bill bill, String str) throws Exception {
        Object obj;
        synchronized (Bills.class) {
            try {
                Occ at = bill.at("help");
                String str2 = bill.hid;
                String str3 = bill.billId;
                String str4 = bill.due;
                String str5 = bill.ownerKey;
                obj = Bills.class;
                try {
                    long j = bill.cents;
                    StringBuilder sb = new StringBuilder();
                    sb.append(j);
                    String sb2 = sb.toString();
                    String str6 = bill.cur;
                    String str7 = at.state;
                    String str8 = at.note;
                    long j2 = at.paidAt;
                    StringBuilder sb3 = new StringBuilder();
                    sb3.append(j2);
                    String write = write(context, "help_" + bill.hid + ".pngmesh", BillCore.build(41, rows("help", "version", "1", "id", str2, "bill_id", str3, "occ", str4, "owner_key_id", str5, "cents", sb2, "currency", str6, "proof", str7, "note", str8, "paid_ms", sb3.toString(), "helper_name", str), SIGNER, picture("ANA help receipt", str + " helped pay: " + bill.name, BillCore.money(bill.cents, bill.cur) + ". Open with ANA to confirm.")));
                    return write;
                } catch (Throwable th) {
                    th = th;
                    throw th;
                }
            } catch (Throwable th2) {
                th = th2;
                obj = Bills.class;
            }
        }
    }

    static String shareThanks(Context context, Bill bill, Help help) throws Exception {
        String str = bill.id;
        String str2 = help.hid;
        String str3 = help.helperKey;
        long j = help.cents;
        StringBuilder sb = new StringBuilder();
        sb.append(j);
        String sb2 = sb.toString();
        String str4 = bill.cur;
        long currentTimeMillis = System.currentTimeMillis();
        StringBuilder sb3 = new StringBuilder();
        sb3.append(currentTimeMillis);
        return write(context, "thanks_" + help.hid + ".pngmesh", BillCore.build(42, rows("thanks", "version", "1", "bill_id", str, "help_id", str2, "helper_key_id", str3, "cents", sb2, "currency", str4, "confirmed_ms", sb3.toString()), SIGNER, picture("ANA thanks", "Thank you: " + bill.name, BillCore.money(help.cents, bill.cur) + " confirmed. Open with ANA for your eFLEX.")));
    }

    static synchronized String schedule(Context context, byte[] bArr, String str) {
        synchronized (Bills.class) {
            load(context);
            BillCore.Signed read = BillCore.read(bArr);
            if (read.ok && read.cls == 43) {
                if (read.keyId.equals(myKeyId())) {
                    return null;
                }
                Bill bill = null;
                for (Bill bill2 : list) {
                    if (!bill2.mine() && bill2.owner.equals(read.keyId) && bill2.id.equals(read.get("sched|id"))) {
                        bill = bill2;
                    }
                }
                if (bill != null) {
                    if (bill.name.equals(BillCore.clean(read.get("sched|name")))) {
                        long j = bill.cents;
                        StringBuilder sb = new StringBuilder();
                        sb.append(j);
                        if (sb.toString().equals(read.get("sched|cents")) && bill.cur.equals(read.get("sched|currency")) && bill.due.equals(read.get("sched|first_due"))) {
                            int i = bill.every;
                            StringBuilder sb2 = new StringBuilder();
                            sb2.append(i);
                            if (sb2.toString().equals(read.get("sched|every")) && bill.unit.equals(read.get("sched|unit"))) {
                                if (bill.app.equals(read.get("sched|app"))) {
                                    return null;
                                }
                                bill.app = read.get("sched|app");
                                save(context);
                                return null;
                            }
                        }
                    }
                    return "A bill schedule changed after it was locked: refused (" + bill.name + ")";
                }
                Bill bill3 = new Bill();
                bill3.owner = read.keyId;
                if (str == null || str.isEmpty()) {
                    str = "iPhone";
                }
                bill3.ownerLabel = str;
                bill3.id = read.get("sched|id");
                bill3.kind = read.get("sched|kind");
                bill3.name = BillCore.clean(read.get("sched|name"));
                bill3.cur = read.get("sched|currency");
                bill3.due = read.get("sched|first_due");
                bill3.unit = read.get("sched|unit");
                bill3.app = read.get("sched|app");
                bill3.cents = num(read.get("sched|cents"));
                bill3.every = (int) Math.max(0L, num(read.get("sched|every")));
                bill3.made = num(read.get("sched|made_ms"));
                try {
                    bill3.lock = BillCore.hex(BillCore.sha(bArr));
                } catch (Exception unused) {
                }
                if (bill3.cents > 0 && (bill3.kind.equals("plan") || bill3.kind.equals("paid") || bill3.kind.equals("help"))) {
                    list.add(bill3);
                    save(context);
                    return "Now checking " + bill3.ownerLabel + "'s bill: " + bill3.name + " (" + BillCore.money(bill3.cents, bill3.cur) + ", " + BillCore.repeatWords(bill3.every, bill3.unit) + ")";
                }
                return "Bill schedule not accepted: incomplete";
            }
            return "Bill schedule not accepted: " + read.why;
        }
    }

    static boolean confirm(Context context, Bill bill, String str, long j, BillCore.Note note) {
        try {
            String str2 = bill.id;
            String str3 = bill.owner;
            StringBuilder sb = new StringBuilder();
            sb.append(j);
            String sb2 = sb.toString();
            String str4 = bill.cur;
            long j2 = note.at;
            StringBuilder sb3 = new StringBuilder();
            sb3.append(j2);
            String sb4 = sb3.toString();
            String str5 = bill.app;
            String money = BillCore.money(j, bill.cur);
            String str6 = bill.appName.isEmpty() ? bill.app : bill.appName;
            String encodeToString = Base64.encodeToString(BillCore.build(44, rows("paid", "version", "1", "bill_id", str2, "owner_key_id", str3, "due", str, "cents", sb2, "currency", str4, "notified_ms", sb4, "app", str5, "note", money + " in a " + str6 + " notification, " + fmtDay(note.at)), SIGNER, DOT), 2);
            confirms.add(new JSONObject().put("at", System.currentTimeMillis()).put("b64", encodeToString));
            Consumer<String> consumer = toIphone;
            if (consumer == null) {
                return false;
            }
            consumer.accept(encodeToString);
            return true;
        } catch (Exception unused) {
            return false;
        }
    }

    static synchronized List<String> confirmations(Context context) {
        ArrayList arrayList;
        synchronized (Bills.class) {
            load(context);
            arrayList = new ArrayList();
            long currentTimeMillis = System.currentTimeMillis() - 3888000000L;
            for (JSONObject jSONObject : confirms) {
                if (jSONObject.optLong("at") > currentTimeMillis) {
                    arrayList.add(jSONObject.optString("b64"));
                }
            }
        }
        return arrayList;
    }

    static synchronized String[] look(Context context, BillCore.Signed signed) {
        synchronized (Bills.class) {
            load(context);
            if (!signed.ok) {
                return new String[]{"no", "Not accepted: " + signed.why};
            }
            String myKeyId = myKeyId();
            if (signed.cls == 40) {
                if (signed.keyId.equals(myKeyId)) {
                    return new String[]{"no", "That's your own bill. Share it with someone who'll help."};
                }
                long num = num(signed.get("bill|cents"));
                if (num <= 0) {
                    return new String[]{"no", "The bill has no amount"};
                }
                for (Bill bill : list) {
                    if (bill.kind.equals("help") && bill.billId.equals(signed.get("bill|id")) && bill.ownerKey.equals(signed.keyId) && bill.due.equals(signed.get("bill|occ"))) {
                        return new String[]{"no", "You're already helping with this bill"};
                    }
                }
                return new String[]{"ok", signed.get("bill|owner_name") + " asks for help with a bill:\n\n" + signed.get("bill|name") + "   " + BillCore.money(num, signed.get("bill|currency")) + (signed.get("bill|due").isEmpty() ? "" : "\nDue " + signed.get("bill|due")) + "\n\nPay the biller yourself (ANA never handles money). When " + signed.get("bill|owner_name") + " confirms you helped, you both earn eFLEX."};
            }
            if (signed.cls == 41) {
                Bill find = find(signed.get("help|bill_id"));
                if (find != null && find.kind.equals("plan")) {
                    if (!signed.get("help|owner_key_id").equals(myKeyId)) {
                        return new String[]{"no", "This receipt is for someone else's bill"};
                    }
                    if (signed.keyId.equals(myKeyId)) {
                        return new String[]{"no", "You can't help yourself"};
                    }
                    if (seenHelps.contains(signed.get("help|id"))) {
                        return new String[]{"no", "Already confirmed"};
                    }
                    long num2 = num(signed.get("help|cents"));
                    String str = signed.get("help|occ");
                    if (num2 > 0 && num2 <= find.cents - find.helped(str)) {
                        return new String[]{"ok", signed.get("help|helper_name") + " says they helped pay " + find.name + (str.isEmpty() ? "" : " (due " + str + ")") + ":\n\n" + BillCore.money(num2, find.cur) + ("proven".equals(signed.get("help|proof")) ? "\nProven by their payment notification" : "\nClaimed (no payment notification)") + "\n" + signed.get("help|note") + "\n\nDid " + signed.get("help|helper_name") + " help you? Confirming sends them a signed thank-you, and you both earn eFLEX."};
                    }
                    return new String[]{"no", "The amount is more than what's left on the bill"};
                }
                return new String[]{"no", "This receipt is for a bill that isn't on this phone"};
            }
            if (signed.cls == 42) {
                Bill bill2 = null;
                for (Bill bill3 : list) {
                    if (bill3.kind.equals("help") && bill3.hid.equals(signed.get("thanks|help_id"))) {
                        bill2 = bill3;
                    }
                }
                if (bill2 == null) {
                    return new String[]{"no", "This thank-you is for help that isn't on this phone"};
                }
                if (signed.keyId.equals(bill2.ownerKey) && signed.get("thanks|bill_id").equals(bill2.billId)) {
                    if (!signed.get("thanks|helper_key_id").equals(myKeyId)) {
                        return new String[]{"no", "This thank-you is for someone else"};
                    }
                    if (bill2.thanked) {
                        return new String[]{"no", "Already counted"};
                    }
                    return new String[]{"ok", bill2.ownerName + " confirmed your help with " + bill2.name + ": " + BillCore.money(bill2.cents, bill2.cur)};
                }
                return new String[]{"no", "Not signed by the bill's owner"};
            }
            return new String[]{"no", "That bill file is for ANA on iPhone"};
        }
    }

    static long num(String str) {
        try {
            return Long.parseLong(str.trim());
        } catch (Exception unused) {
            return -1L;
        }
    }

    static synchronized Bill acceptBill(Context context, BillCore.Signed signed, long j) {
        Bill bill;
        synchronized (Bills.class) {
            bill = new Bill();
            bill.kind = "help";
            bill.billId = signed.get("bill|id");
            bill.ownerKey = signed.keyId;
            bill.ownerName = BillCore.clean(signed.get("bill|owner_name"));
            bill.name = BillCore.clean(signed.get("bill|name") + " (" + bill.ownerName + ")");
            bill.cur = signed.get("bill|currency");
            bill.due = signed.get("bill|occ");
            bill.billCents = num(signed.get("bill|cents"));
            bill.cents = Math.max(1L, Math.min(j, bill.billCents));
            bill.hid = BillCore.newId();
            lock(bill);
            list.add(0, bill);
            save(context);
        }
        return bill;
    }

    static synchronized String confirmHelp(Context context, BillCore.Signed signed) throws Exception {
        String shareThanks;
        synchronized (Bills.class) {
            Bill find = find(signed.get("help|bill_id"));
            Help help = new Help();
            help.hid = signed.get("help|id");
            help.helperKey = signed.keyId;
            help.helperName = BillCore.clean(signed.get("help|helper_name"));
            help.proof = signed.get("help|proof");
            help.note = signed.get("help|note");
            help.occ = signed.get("help|occ");
            help.cents = Long.parseLong(signed.get("help|cents"));
            help.at = System.currentTimeMillis();
            find.helps.add(help);
            seenHelps.add(help.hid);
            String pairOf = pairOf(myKeyId(), help.helperKey);
            earn(context, find.name + ": " + help.helperName + " helped pay " + BillCore.money(help.cents, find.cur), BillCore.shared(BillCore.points(help.cents, find.cur, 0.5d), pairCount(pairOf)), pairOf);
            save(context);
            shareThanks = shareThanks(context, find, help);
        }
        return shareThanks;
    }

    static synchronized String thanked(Context context, BillCore.Signed signed) {
        synchronized (Bills.class) {
            Bill bill = null;
            for (Bill bill2 : list) {
                if (bill2.kind.equals("help") && bill2.hid.equals(signed.get("thanks|help_id"))) {
                    bill = bill2;
                }
            }
            if (bill == null) {
                return "Not found";
            }
            bill.thanked = true;
            String pairOf = pairOf(myKeyId(), bill.ownerKey);
            double shared = BillCore.shared(BillCore.points(bill.cents, bill.cur, 1.0d * ("proven".equals(bill.at("help").state) ? 1.0d : 0.25d)), pairCount(pairOf));
            bill.helpPts = shared;
            earn(context, "Helped " + bill.ownerName + " pay " + bill.name + " (" + BillCore.money(bill.cents, bill.cur) + ")", shared, pairOf);
            save(context);
            return "Thank-you from " + bill.ownerName + ": +" + BillCore.pts(shared) + " eFLEX";
        }
    }

    static String line(Bill bill) {
        String str;
        StringBuilder sb;
        String str2;
        String str3 = BillCore.money(bill.cents, bill.cur) + "  " + bill.name;
        if (!bill.mine()) {
            return str3 + " · for " + bill.ownerLabel + " · " + bill.provenCount() + " confirmed";
        }
        if (bill.kind.equals("help")) {
            String str4 = bill.at("help").state;
            if (bill.thanked) {
                String pts = BillCore.pts(bill.helpPts);
                sb = new StringBuilder("Thanked · ");
                sb.append(pts);
                sb.append(" eFLEX");
            } else {
                if ("open".equals(str4)) {
                    str2 = "To pay";
                    return str3 + " · helping · " + str2;
                }
                String cap = cap(str4);
                sb = new StringBuilder();
                sb.append(cap);
                sb.append(", send receipt");
            }
            str2 = sb.toString();
            return str3 + " · helping · " + str2;
        }
        String str5 = "";
        if (bill.kind.equals("paid")) {
            String cap2 = cap(bill.at(bill.dates().get(0)).state);
            if (bill.pts() > 0.0d) {
                str5 = " · " + BillCore.pts(bill.pts()) + " eFLEX";
            }
            return str3 + " · paid · " + cap2 + str5;
        }
        String current = bill.current();
        if (!bill.forBill.isEmpty()) {
            return str3 + " · daily · " + (current == null ? "done" : settled(bill.occ.get(current)) ? "set aside today" : "set aside today?");
        }
        String repeatWords = BillCore.repeatWords(bill.every, bill.unit);
        if (current == null) {
            str = " · done";
        } else {
            str = " · settle up " + fmtDue(current);
        }
        String ahead = ahead(bill);
        if (bill.pts() > 0.0d) {
            str5 = " · " + BillCore.pts(bill.pts()) + " eFLEX";
        }
        return str3 + " · " + repeatWords + str + " · " + ahead + str5;
    }

    static String cap(String str) {
        if (str.isEmpty()) {
            return str;
        }
        return Character.toUpperCase(str.charAt(0)) + str.substring(1);
    }

    static String detail(Bill bill) {
        StringBuilder sb;
        String str;
        String str2;
        String sb2;
        String str3;
        String str4;
        String str5;
        long j;
        int i;
        StringBuilder sb3 = new StringBuilder();
        sb3.append(BillCore.money(bill.cents, bill.cur));
        if (!bill.mine()) {
            sb3.append("\nChecked here for ");
            sb3.append(bill.ownerLabel);
            sb3.append(": this phone watches for the payment notification and sends a signed confirmation back.");
        }
        String str6 = "\n";
        String str7 = "";
        if (bill.kind.equals("plan") && bill.forBill.isEmpty() && bill.mine()) {
            String current = bill.current();
            sb3.append("\n\nYou've had ");
            sb3.append(enjoyed(bill));
            sb3.append(" days of ");
            sb3.append(bill.name);
            sb3.append(" since the last settle-up.");
            sb3.append(current == null ? "" : " Time to settle up by " + fmtDue(current) + ".");
            sb3.append("\n");
            sb3.append(cap(ahead(bill)));
            long aside = setAside(bill);
            if (aside > 0) {
                sb3.append("\nSet aside so far: ");
                sb3.append(BillCore.money(aside, bill.cur));
            }
        }
        if (!bill.forBill.isEmpty()) {
            sb3.append("\nA little each day, so the settle-up is ready before it's due. It moves your 30-day goal (it earns no eFLEX itself).");
        }
        if (bill.kind.equals("plan")) {
            sb3.append("\nRepeats: ");
            sb3.append(BillCore.repeatWords(bill.every, bill.unit));
            sb3.append(", first due ");
            sb3.append(bill.due);
            sb3.append(" (locked)");
        }
        if (bill.kind.equals("paid")) {
            sb3.append("\nAlready paid (reported after)");
        }
        String str8 = ")";
        if (bill.kind.equals("help")) {
            sb3.append("\nYou're helping ");
            sb3.append(bill.ownerName);
            sb3.append(" (their bill: ");
            sb3.append(BillCore.money(bill.billCents, bill.cur));
            sb3.append(", due ");
            sb3.append(bill.due);
            sb3.append(")");
        }
        sb3.append("\nPayment app: ");
        sb3.append(bill.app.isEmpty() ? "not picked yet" : bill.appName.isEmpty() ? bill.app : bill.appName);
        List<String> dates = bill.dates();
        long currentTimeMillis = System.currentTimeMillis();
        StringBuilder sb4 = new StringBuilder();
        Iterator<String> it = dates.iterator();
        int i2 = 0;
        int i3 = 0;
        int i4 = 0;
        int i5 = 0;
        while (it.hasNext()) {
            String str9 = str7;
            String next = it.next();
            Iterator<String> it2 = it;
            Occ occ = bill.occ.get(next);
            if (occ == null) {
                str5 = str6;
                str3 = str8;
                str4 = "open";
            } else {
                str3 = str8;
                str4 = occ.state;
                str5 = str6;
            }
            if ("proven".equals(str4)) {
                i2++;
            } else if ("claimed".equals(str4)) {
                i3++;
            } else if (bill.kind.equals("plan") && bill.window(next)[2] < currentTimeMillis) {
                i4++;
                str4 = "missed";
            }
            if (occ == null && bill.kind.equals("plan")) {
                if (bill.window(next)[0] > currentTimeMillis + 604800000) {
                    j = currentTimeMillis;
                    i = i5;
                    i5 = i;
                    it = it2;
                    str7 = str9;
                    str8 = str3;
                    str6 = str5;
                    currentTimeMillis = j;
                }
            }
            j = currentTimeMillis;
            i = i5;
            if (i < 6) {
                sb4.append("\n  ");
                sb4.append(next.equals("help") ? "Your payment" : fmtDue(next));
                sb4.append(": ");
                sb4.append(str4);
                sb4.append((occ == null || occ.note.isEmpty()) ? str9 : "  ·  " + occ.note);
                i5 = i + 1;
                it = it2;
                str7 = str9;
                str8 = str3;
                str6 = str5;
                currentTimeMillis = j;
            }
            i5 = i;
            it = it2;
            str7 = str9;
            str8 = str3;
            str6 = str5;
            currentTimeMillis = j;
        }
        String str10 = str6;
        String str11 = str7;
        String str12 = str8;
        if (bill.kind.equals("plan") && dates.size() > 1) {
            sb3.append("\n\n");
            sb3.append(dates.size());
            sb3.append(" due dates in 12 months: ");
            sb3.append(i2);
            sb3.append(" proven, ");
            sb3.append(i3);
            sb3.append(" claimed");
            sb3.append(i4 > 0 ? ", " + i4 + " missed" : str11);
        }
        sb3.append(str10);
        sb3.append((CharSequence) sb4);
        if (!bill.helps.isEmpty()) {
            sb3.append("\n\nHelped by:");
            for (Help help : bill.helps) {
                sb3.append("\n  ");
                sb3.append(help.helperName);
                sb3.append("  ");
                sb3.append(BillCore.money(help.cents, bill.cur));
                if (help.occ.isEmpty()) {
                    sb2 = str11;
                    str2 = str12;
                } else {
                    String str13 = help.occ;
                    StringBuilder sb5 = new StringBuilder("  (");
                    sb5.append(str13);
                    str2 = str12;
                    sb5.append(str2);
                    sb2 = sb5.toString();
                }
                sb3.append(sb2);
                sb3.append("  ");
                sb3.append(help.proof);
                str12 = str2;
            }
        }
        if (bill.kind.equals("help")) {
            if (bill.thanked) {
                String pts = BillCore.pts(bill.helpPts);
                sb = new StringBuilder("\n\nThanked: +");
                sb.append(pts);
                str = " eFLEX";
            } else {
                String str14 = bill.ownerName;
                sb = new StringBuilder("\n\nWhen it's paid, send your receipt to ");
                sb.append(str14);
                str = ". You earn when they confirm.";
            }
            sb.append(str);
            sb3.append(sb.toString());
        } else if (bill.mine() && bill.pts() > 0.0d) {
            sb3.append("\n\neFLEX earned: ");
            sb3.append(BillCore.pts(bill.pts()));
        }
        return sb3.toString();
    }
}
