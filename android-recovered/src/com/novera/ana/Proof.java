package com.novera.ana;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import com.novera.ana.Proof;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONObject;

/* loaded from: classes.dex */
final class Proof {
    static final Map<String, Integer> DECIMALS;
    private static final Pattern HEAD;
    static final double LOOK_BACK_DAYS = 30.0d;
    private static final Pattern PARTY;
    static final String PLAY_STORE = "com.android.vending";
    static final String TRUST_ANDROID = "com.wallet.crypto.trustapp";
    static final String TRUST_IPHONE = "com.sixdays.trust";
    static final double WINDOW_AFTER = 3600.0d;
    static final double WINDOW_BEFORE = 3600.0d;

    private Proof() {
    }

    static {
        HashMap hashMap = new HashMap();
        DECIMALS = hashMap;
        hashMap.put("BTC", 8);
        hashMap.put("LTC", 8);
        HEAD = Pattern.compile("(Received|Sent)\\s*:?\\s*([0-9]+(?:\\.[0-9]+)?)\\s+([A-Z]{2,10})\\b");
        PARTY = Pattern.compile("\\b(From|To)\\s+([A-Za-z0-9]+)(?:\\.{3}|…)([A-Za-z0-9]+)");
    }

    static final class Cand {
        String amount;
        double at;
        boolean incoming;
        String key;
        String prefix;
        String suffix;
        String ticker;
        long units;
        String app = "";
        String via = "";

        Cand() {
        }
    }

    static final class Tx {
        boolean confirmed;
        double time;
        String txid;
        final List<String> inA = new ArrayList();
        final List<String> outA = new ArrayList();
        final List<Long> inV = new ArrayList();
        final List<Long> outV = new ArrayList();

        Tx() {
        }

        static Tx from(JSONObject jSONObject) {
            Tx tx = new Tx();
            tx.txid = jSONObject.optString("txid");
            JSONObject optJSONObject = jSONObject.optJSONObject("status");
            boolean z = optJSONObject != null && optJSONObject.optBoolean("confirmed");
            tx.confirmed = z;
            tx.time = z ? optJSONObject.optLong("block_time") : System.currentTimeMillis() / 1000.0d;
            JSONArray optJSONArray = jSONObject.optJSONArray("vin");
            JSONArray optJSONArray2 = jSONObject.optJSONArray("vout");
            if (optJSONArray != null) {
                for (int i = 0; i < optJSONArray.length(); i++) {
                    JSONObject optJSONObject2 = optJSONArray.optJSONObject(i) == null ? null : optJSONArray.optJSONObject(i).optJSONObject("prevout");
                    tx.inA.add(optJSONObject2 == null ? "" : optJSONObject2.optString("scriptpubkey_address"));
                    tx.inV.add(Long.valueOf(optJSONObject2 == null ? 0L : optJSONObject2.optLong("value")));
                }
            }
            if (optJSONArray2 != null) {
                for (int i2 = 0; i2 < optJSONArray2.length(); i2++) {
                    JSONObject optJSONObject3 = optJSONArray2.optJSONObject(i2);
                    tx.outA.add(optJSONObject3 == null ? "" : optJSONObject3.optString("scriptpubkey_address"));
                    tx.outV.add(Long.valueOf(optJSONObject3 == null ? 0L : optJSONObject3.optLong("value")));
                }
            }
            return tx;
        }

        long net(String str) {
            long j = 0;
            for (int i = 0; i < this.outA.size(); i++) {
                if (this.outA.get(i).equals(str)) {
                    j += this.outV.get(i).longValue();
                }
            }
            for (int i2 = 0; i2 < this.inA.size(); i2++) {
                if (this.inA.get(i2).equals(str)) {
                    j -= this.inV.get(i2).longValue();
                }
            }
            return j;
        }
    }

    static final class Result {
        final Map<String, String> detail = new HashMap();
        String note;
        String state;
        String txid;

        Result(String str, String str2, String str3) {
            this.state = str;
            this.note = str2;
            this.txid = str3;
        }
    }

    static long units(String str, String str2) {
        Integer num = DECIMALS.get(str2);
        if (num == null) {
            return -1L;
        }
        int indexOf = str.indexOf(46);
        String substring = indexOf < 0 ? str : str.substring(0, indexOf);
        String substring2 = indexOf < 0 ? "" : str.substring(indexOf + 1);
        if (substring2.length() > num.intValue()) {
            return -1L;
        }
        StringBuilder sb = new StringBuilder(substring2);
        while (sb.length() < num.intValue()) {
            sb.append('0');
        }
        long j = 1;
        for (int i = 0; i < num.intValue(); i++) {
            j *= 10;
        }
        try {
            return (Long.parseLong(substring) * j) + Long.parseLong(sb.toString());
        } catch (NumberFormatException unused) {
            return -1L;
        }
    }

    static Cand parse(String str, String str2, double d, String str3) {
        String str4 = str + "\n" + str2;
        Matcher matcher = HEAD.matcher(str4);
        if (!matcher.find()) {
            return null;
        }
        long units = units(matcher.group(2), matcher.group(3));
        if (units < 0) {
            return null;
        }
        Cand cand = new Cand();
        cand.incoming = matcher.group(1).equals("Received");
        cand.amount = matcher.group(2);
        cand.ticker = matcher.group(3);
        cand.units = units;
        cand.at = d;
        cand.key = str3;
        Matcher matcher2 = PARTY.matcher(str4);
        if (matcher2.find()) {
            cand.prefix = matcher2.group(2);
            cand.suffix = matcher2.group(3);
        }
        return cand;
    }

    static boolean fitsParty(Cand cand, String str) {
        return cand.prefix == null || (str.startsWith(cand.prefix) && str.endsWith(cand.suffix));
    }

    static boolean genuineHere(Context context) {
        String installerPackageName;
        if (context == null) {
            return false;
        }
        try {
            PackageManager packageManager = context.getPackageManager();
            if (Build.VERSION.SDK_INT >= 30) {
                installerPackageName = packageManager.getInstallSourceInfo(TRUST_ANDROID).getInstallingPackageName();
            } else {
                installerPackageName = packageManager.getInstallerPackageName(TRUST_ANDROID);
            }
            return PLAY_STORE.equals(installerPackageName);
        } catch (Exception unused) {
            return false;
        }
    }

    static List<Cand> candidates(Context context, String str) {
        Cand parse;
        double currentTimeMillis = (System.currentTimeMillis() / 1000.0d) - 2592000.0d;
        boolean genuineHere = genuineHere(context);
        ArrayList arrayList = new ArrayList();
        if (context == null) {
            return arrayList;
        }
        Iterator<String> it = AnaLog.readAll(context).iterator();
        while (it.hasNext()) {
            String[] split = it.next().split("\t", -1);
            if (split.length >= 7) {
                boolean z = false;
                boolean z2 = (split[0].equals("LIVE") || split[0].equals("SCAN")) && split[3].equals(TRUST_ANDROID) && genuineHere;
                if (split[0].equals("IPHONE") && split[3].equals(TRUST_IPHONE)) {
                    z = true;
                }
                if (z2 || z) {
                    try {
                        double parseLong = Long.parseLong(split[2]) / 1000.0d;
                        if (parseLong >= currentTimeMillis && (parse = parse(split[4], split[5], parseLong, split[6])) != null && parse.ticker.equals(str)) {
                            parse.app = split[3];
                            parse.via = z2 ? "android" : "iphone-relay-on-android";
                            arrayList.add(parse);
                        }
                    } catch (NumberFormatException unused) {
                    }
                }
            }
        }
        Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.Proof$$ExternalSyntheticLambda0
            @Override // java.util.Comparator
            public final int compare(Object obj, Object obj2) {
                int compare;
                compare = Double.compare(((Proof.Cand) obj2).at, ((Proof.Cand) obj).at);
                return compare;
            }
        });
        return arrayList;
    }

    static boolean fits(Cand cand, Tx tx, String str) {
        if (tx.confirmed && tx.time >= cand.at - 3600.0d && tx.time <= cand.at + 3600.0d) {
            if (cand.incoming) {
                boolean z = false;
                for (int i = 0; i < tx.outA.size(); i++) {
                    if (tx.outA.get(i).equals(str) && tx.outV.get(i).longValue() == cand.units) {
                        z = true;
                    }
                }
                if (!z) {
                    return false;
                }
                if (cand.prefix == null) {
                    return true;
                }
                Iterator<String> it = tx.inA.iterator();
                while (it.hasNext()) {
                    if (fitsParty(cand, it.next())) {
                        return true;
                    }
                }
                return false;
            }
            if (!tx.inA.contains(str)) {
                return false;
            }
            for (int i2 = 0; i2 < tx.outA.size(); i2++) {
                String str2 = tx.outA.get(i2);
                if (!str2.equals(str) && tx.outV.get(i2).longValue() == cand.units && fitsParty(cand, str2)) {
                    return true;
                }
            }
        }
        return false;
    }

    static Result evaluate(Context context, String str, String str2, List<Tx> list, long j) {
        String str3;
        if (j <= 0) {
            return new Result("watching", "Empty: proof starts again with the next Received", null);
        }
        ArrayList<Tx> arrayList = new ArrayList(list);
        Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.Proof$$ExternalSyntheticLambda1
            @Override // java.util.Comparator
            public final int compare(Object obj, Object obj2) {
                int compare;
                compare = Double.compare(((Proof.Tx) obj2).time, ((Proof.Tx) obj).time);
                return compare;
            }
        });
        long j2 = j;
        double d = 0.0d;
        for (Tx tx : arrayList) {
            if (j2 == 0 && d == 0.0d) {
                d = tx.time;
            }
            j2 -= tx.net(str);
        }
        double currentTimeMillis = System.currentTimeMillis() / 1000.0d;
        Iterator<Cand> it = candidates(context, str2).iterator();
        Cand cand = null;
        boolean z = false;
        while (true) {
            if (!it.hasNext()) {
                if (cand != null) {
                    return new Result("proving", "Wallet notification caught (" + cand.amount + " " + str2 + "), waiting for the chain", null);
                }
                return new Result("watching", z ? "Two transactions fit one notification: not proven" : "", null);
            }
            Cand next = it.next();
            ArrayList arrayList2 = new ArrayList();
            for (Tx tx2 : list) {
                if (fits(next, tx2, str)) {
                    arrayList2.add(tx2);
                }
            }
            if (arrayList2.size() == 1) {
                Tx tx3 = (Tx) arrayList2.get(0);
                if (tx3.time > d) {
                    int i = (int) (next.at - tx3.time);
                    if (next.prefix == null) {
                        str3 = "";
                    } else {
                        str3 = (next.incoming ? " from " : " to ") + next.prefix + "..." + next.suffix;
                    }
                    String str4 = i >= 0 ? "push " + (i / 60) + " min " + (i % 60) + " s after the block" : "push " + ((-i) / 60) + " min before the block";
                    String str5 = "Proven: " + (next.incoming ? "+" : "-") + next.amount + " " + str2 + str3 + "  ·  " + Wallets.when(next.at) + "  ·  " + str4;
                    Result result = new Result("proven", str5, tx3.txid);
                    result.detail.put("coin", str2);
                    result.detail.put("address", str);
                    result.detail.put("direction", next.incoming ? "in" : "out");
                    result.detail.put("units", String.valueOf(next.units));
                    result.detail.put("amount", next.amount);
                    result.detail.put("txid", tx3.txid);
                    result.detail.put("block_time", String.valueOf((long) tx3.time));
                    result.detail.put("notified_ms", String.valueOf((long) (next.at * 1000.0d)));
                    result.detail.put("app", next.app);
                    result.detail.put("via", next.via);
                    result.detail.put("party", next.prefix != null ? next.prefix + "..." + next.suffix : "");
                    result.detail.put("note", str5);
                    return result;
                }
            } else {
                if (arrayList2.size() > 1) {
                    z = true;
                }
                if (arrayList2.isEmpty() && cand == null && currentTimeMillis - next.at < 3600.0d) {
                    cand = next;
                }
            }
        }
    }

    static String badge(String str) {
        return "proven".equals(str) ? "Proven" : "proving".equals(str) ? "Proving..." : "Watching";
    }
}
