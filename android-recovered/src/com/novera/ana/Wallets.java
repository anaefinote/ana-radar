package com.novera.ana;

import android.content.Context;
import com.novera.ana.Lessons;
import com.novera.ana.Proof;
import com.novera.ana.Wallets;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/* loaded from: classes.dex */
final class Wallets {
    private static final String BTC_API = "https://mempool.space/api/";
    private static final String LEND_GATEWAY = "0x01f8cdfb1694ea8fe4ed6c38a0fd78d1188e03f4";
    private static final String LTC_API = "https://litecoinspace.org/api/";
    private static final String OP_EXPLORER = "https://explorer.optimism.io/api/v2/addresses/";
    private static final String OP_RPC = "https://mainnet.optimism.io";
    private static final String OP_USDC = "0x0b2c639c533813f4aa9d7837caf62653d097ff85";
    private static final String OP_USDCE = "0x7f5c764cbc14f9669b88837ca1490cca17c31607";
    private static final String PAD = "000000000000000000000000";
    private static final String PRICE = "https://api.coingecko.com/api/v3/simple/price?vs_currencies=usd&ids=";
    private static final String RHINO = "0x0bca65bf4b4c8803d2f0b49353ed57caaf3d66dc";
    private static final String SOL_RPC = "https://api.mainnet-beta.solana.com";
    private static final String SOL_USDC = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
    static final boolean STATIA = true;
    private static final String TRON_API = "https://api.trongrid.io/v1/accounts/";
    private static final String TRON_USDT = "TR7NHqjeKQxGTCi8q8ZYpPDdtsWPBQiYzr";
    private static volatile boolean again;
    private static volatile Context appCtx;
    static volatile boolean back;
    static volatile boolean busy;
    static volatile boolean capturing;
    static final List<Wallet> list = new ArrayList();
    static Listener listener;
    private static boolean loaded;
    static ProofListener proofListener;

    interface Listener {
        void onNews(Wallet wallet, List<Act> list);
    }

    interface ProofListener {
        void onProof(Wallet wallet);
    }

    Wallets() {
    }

    static final class Act {
        double amt;
        String id;
        String kind;
        String label;
        double t;
        String unit = "";

        Act(double d, double d2, String str, String str2, String str3) {
            this.t = d;
            this.amt = d2;
            this.kind = str;
            this.label = str2;
            this.id = str3;
        }

        JSONObject json() throws Exception {
            return new JSONObject().put("t", this.t).put("amt", this.amt).put("kind", this.kind).put("label", this.label).put("id", this.id).put("unit", this.unit);
        }

        static Act from(JSONObject jSONObject) {
            Act act = new Act(jSONObject.optDouble("t"), jSONObject.optDouble("amt"), jSONObject.optString("kind"), jSONObject.optString("label"), jSONObject.optString("id"));
            act.unit = jSONObject.optString("unit", "");
            return act;
        }
    }

    static final class Wallet {
        String addr;
        boolean earnExact;
        double earning;
        boolean hidden;
        double hideUntil;
        String id;
        String kind;
        String name;
        boolean primed;
        double ready;
        boolean shareHide;
        double sol;
        double updated;
        double debt = -1.0d;
        double borrowable = -1.0d;
        String status = "Not checked yet";
        List<Act> activity = new ArrayList();
        List<String> seen = new ArrayList();
        String proof = "";
        String proofNote = "";
        String proofTx = "";
        JSONObject proofDetail = new JSONObject();
        String lesson = "";

        Wallet() {
        }

        JSONObject json() throws Exception {
            JSONArray jSONArray = new JSONArray();
            JSONArray jSONArray2 = new JSONArray();
            Iterator<Act> it = this.activity.iterator();
            while (it.hasNext()) {
                jSONArray.put(it.next().json());
            }
            Iterator<String> it2 = this.seen.iterator();
            while (it2.hasNext()) {
                jSONArray2.put(it2.next());
            }
            return new JSONObject().put("id", this.id).put("name", this.name).put("kind", this.kind).put("addr", this.addr).put("ready", this.ready).put("earning", this.earning).put("sol", this.sol).put("updated", this.updated).put("debt", this.debt).put("borrowable", this.borrowable).put("earnExact", this.earnExact).put("primed", this.primed).put("status", this.status).put("activity", jSONArray).put("seen", jSONArray2).put("hidden", this.hidden).put("hideUntil", this.hideUntil).put("shareHide", this.shareHide).put("proof", this.proof).put("proofNote", this.proofNote).put("proofTx", this.proofTx).put("proofDetail", this.proofDetail).put("lesson", this.lesson);
        }

        static Wallet from(JSONObject jSONObject) {
            Wallet wallet = new Wallet();
            wallet.id = jSONObject.optString("id");
            wallet.name = jSONObject.optString("name");
            wallet.kind = jSONObject.optString("kind");
            wallet.addr = jSONObject.optString("addr");
            wallet.ready = jSONObject.optDouble("ready", 0.0d);
            wallet.earning = jSONObject.optDouble("earning", 0.0d);
            wallet.sol = jSONObject.optDouble("sol", 0.0d);
            wallet.updated = jSONObject.optDouble("updated", 0.0d);
            wallet.debt = jSONObject.optDouble("debt", -1.0d);
            wallet.borrowable = jSONObject.optDouble("borrowable", -1.0d);
            wallet.earnExact = jSONObject.optBoolean("earnExact");
            wallet.primed = jSONObject.optBoolean("primed");
            wallet.status = jSONObject.optString("status");
            wallet.hidden = jSONObject.optBoolean("hidden");
            wallet.hideUntil = jSONObject.optDouble("hideUntil", 0.0d);
            wallet.shareHide = jSONObject.optBoolean("shareHide");
            wallet.proof = jSONObject.optString("proof");
            wallet.proofNote = jSONObject.optString("proofNote");
            wallet.proofTx = jSONObject.optString("proofTx");
            wallet.lesson = jSONObject.optString("lesson");
            JSONObject optJSONObject = jSONObject.optJSONObject("proofDetail");
            if (optJSONObject != null) {
                wallet.proofDetail = optJSONObject;
            }
            JSONArray optJSONArray = jSONObject.optJSONArray("activity");
            JSONArray optJSONArray2 = jSONObject.optJSONArray("seen");
            if (optJSONArray != null) {
                for (int i = 0; i < optJSONArray.length(); i++) {
                    wallet.activity.add(Act.from(optJSONArray.optJSONObject(i)));
                }
            }
            if (optJSONArray2 != null) {
                for (int i2 = 0; i2 < optJSONArray2.length(); i2++) {
                    wallet.seen.add(optJSONArray2.optString(i2));
                }
            }
            return wallet;
        }

        Wallet copy() {
            try {
                return from(json());
            } catch (Exception unused) {
                return this;
            }
        }
    }

    static synchronized void load(Context context) {
        synchronized (Wallets.class) {
            if (loaded) {
                return;
            }
            loaded = STATIA;
            try {
                JSONArray jSONArray = new JSONArray(context.getSharedPreferences("ana", 0).getString("wallets_v1", "[]"));
                for (int i = 0; i < jSONArray.length(); i++) {
                    list.add(Wallet.from(jSONArray.getJSONObject(i)));
                }
            } catch (Exception unused) {
            }
        }
    }

    static synchronized void save(Context context) {
        synchronized (Wallets.class) {
            try {
                JSONArray jSONArray = new JSONArray();
                Iterator<Wallet> it = list.iterator();
                while (it.hasNext()) {
                    jSONArray.put(it.next().json());
                }
                context.getSharedPreferences("ana", 0).edit().putString("wallets_v1", jSONArray.toString()).apply();
            } catch (Exception unused) {
            }
        }
    }

    static String kindOf(String str) {
        String trim = str == null ? "" : str.trim();
        if (trim.matches("^0x[0-9a-fA-F]{40}$")) {
            return "etherfi";
        }
        if (Lessons.forAddress(trim) != null && !isLitecoin(trim) && !isBitcoin(trim)) {
            return "lesson";
        }
        if (isLitecoin(trim)) {
            return "litecoin";
        }
        if (isBitcoin(trim)) {
            return "bitcoin";
        }
        if (trim.matches("^T[1-9A-HJ-NP-Za-km-z]{33}$")) {
            return "tron";
        }
        if (trim.matches("^[1-9A-HJ-NP-Za-km-z]{32,44}$")) {
            return "solana";
        }
        return null;
    }

    static synchronized String add(Context context, String str, String str2) {
        String add;
        synchronized (Wallets.class) {
            add = add(context, str, str2, false);
        }
        return add;
    }

    static synchronized String add(Context context, String str, String str2, boolean z) {
        synchronized (Wallets.class) {
            String trim = str2 == null ? "" : str2.trim();
            String kindOf = kindOf(trim);
            if (kindOf == null) {
                return "That isn't an address ANA can watch yet (or a lesson for its coin)";
            }
            kindOf.equals("litecoin");
            kindOf.equals("bitcoin");
            Iterator<Wallet> it = list.iterator();
            while (it.hasNext()) {
                if (it.next().addr.equalsIgnoreCase(trim)) {
                    return "ANA is already watching that address";
                }
            }
            Wallet wallet = new Wallet();
            wallet.id = UUID.randomUUID().toString();
            String trim2 = str == null ? "" : str.trim();
            wallet.name = trim2.isEmpty() ? kindOf.equals("etherfi") ? "ether.fi Cash" : kindOf.equals("tron") ? "TRON wallet" : kindOf.equals("litecoin") ? "Litecoin" : kindOf.equals("bitcoin") ? "Bitcoin" : "Solana wallet" : trim2;
            wallet.kind = kindOf;
            if (kindOf.equals("lesson")) {
                Lessons.Lesson forAddress = Lessons.forAddress(trim);
                wallet.lesson = forAddress.id;
                if (trim2.isEmpty()) {
                    wallet.name = forAddress.name();
                }
            }
            wallet.addr = trim;
            wallet.hidden = z;
            list.add(wallet);
            save(context);
            refreshAll(context);
            return null;
        }
    }

    static synchronized void rename(Context context, String str, String str2) {
        synchronized (Wallets.class) {
            String trim = str2 == null ? "" : str2.trim();
            if (trim.isEmpty()) {
                return;
            }
            for (Wallet wallet : list) {
                if (wallet.id.equals(str)) {
                    wallet.name = trim;
                }
            }
            save(context);
        }
    }

    static synchronized void remove(Context context, String str) {
        synchronized (Wallets.class) {
            Iterator<Wallet> it = list.iterator();
            while (it.hasNext()) {
                if (it.next().id.equals(str)) {
                    it.remove();
                }
            }
            save(context);
        }
    }

    /* JADX WARN: Code restructure failed: missing block: B:16:0x002f, code lost:
    
        if (r9.shareHide != false) goto L17;
     */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    static synchronized boolean offFront(com.novera.ana.Wallets.Wallet r9) {
        /*
            java.lang.Class<com.novera.ana.Wallets> r0 = com.novera.ana.Wallets.class
            monitor-enter(r0)
            long r1 = java.lang.System.currentTimeMillis()     // Catch: java.lang.Throwable -> L34
            double r1 = (double) r1     // Catch: java.lang.Throwable -> L34
            r3 = 4652007308841189376(0x408f400000000000, double:1000.0)
            double r1 = r1 / r3
            boolean r3 = r9.hidden     // Catch: java.lang.Throwable -> L34
            r4 = 0
            if (r3 == 0) goto L25
            double r5 = r9.hideUntil     // Catch: java.lang.Throwable -> L34
            r7 = 0
            int r3 = (r5 > r7 ? 1 : (r5 == r7 ? 0 : -1))
            if (r3 <= 0) goto L25
            double r5 = r9.hideUntil     // Catch: java.lang.Throwable -> L34
            int r1 = (r1 > r5 ? 1 : (r1 == r5 ? 0 : -1))
            if (r1 < 0) goto L25
            r9.hidden = r4     // Catch: java.lang.Throwable -> L34
            r9.hideUntil = r7     // Catch: java.lang.Throwable -> L34
        L25:
            boolean r1 = r9.hidden     // Catch: java.lang.Throwable -> L34
            if (r1 != 0) goto L31
            boolean r1 = com.novera.ana.Wallets.capturing     // Catch: java.lang.Throwable -> L34
            if (r1 == 0) goto L32
            boolean r9 = r9.shareHide     // Catch: java.lang.Throwable -> L34
            if (r9 == 0) goto L32
        L31:
            r4 = 1
        L32:
            monitor-exit(r0)
            return r4
        L34:
            r9 = move-exception
            monitor-exit(r0)
            throw r9
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Wallets.offFront(com.novera.ana.Wallets$Wallet):boolean");
    }

    static synchronized void hide(Context context, String str, double d) {
        synchronized (Wallets.class) {
            Wallet find = find(str);
            if (find == null) {
                return;
            }
            find.hidden = d >= 0.0d ? STATIA : false;
            find.hideUntil = d > 0.0d ? (System.currentTimeMillis() / 1000.0d) + d : 0.0d;
            save(context);
        }
    }

    static synchronized void shareHide(Context context, String str, boolean z) {
        synchronized (Wallets.class) {
            Wallet find = find(str);
            if (find == null) {
                return;
            }
            find.shareHide = z;
            save(context);
        }
    }

    static String left(double d) {
        long max = Math.max(60L, (long) d);
        long j = max / 86400;
        long j2 = (max % 86400) / 3600;
        long j3 = (max % 3600) / 60;
        if (j > 0) {
            return j + "d " + j2 + "h";
        }
        if (j2 > 0) {
            return j2 + "h " + j3 + "m";
        }
        return j3 + "m";
    }

    static synchronized String state(Wallet wallet) {
        synchronized (Wallets.class) {
            offFront(wallet);
            if (!wallet.hidden) {
                return "On the front";
            }
            if (wallet.hideUntil <= 0.0d) {
                return "Hidden until you bring it back";
            }
            return "Hidden  ·  back in " + left(wallet.hideUntil - (System.currentTimeMillis() / 1000.0d));
        }
    }

    static synchronized Wallet find(String str) {
        synchronized (Wallets.class) {
            for (Wallet wallet : list) {
                if (wallet.id.equals(str)) {
                    return wallet;
                }
            }
            return null;
        }
    }

    static void refreshAll(Context context) {
        final ArrayList arrayList = new ArrayList();
        synchronized (Wallets.class) {
            if (busy) {
                again = STATIA;
                return;
            }
            List<Wallet> list2 = list;
            if (list2.isEmpty()) {
                return;
            }
            busy = STATIA;
            Iterator<Wallet> it = list2.iterator();
            while (it.hasNext()) {
                arrayList.add(it.next().copy());
            }
            final Context applicationContext = context.getApplicationContext();
            appCtx = applicationContext;
            new Thread(new Runnable() { // from class: com.novera.ana.Wallets$$ExternalSyntheticLambda0
                @Override // java.lang.Runnable
                public final void run() {
                    Wallets.lambda$refreshAll$0(arrayList, applicationContext);
                }
            }, "ana-watch").start();
        }
    }

    static /* synthetic */ void lambda$refreshAll$0(List list2, Context context) {
        ArrayList arrayList = new ArrayList();
        Iterator it = list2.iterator();
        while (it.hasNext()) {
            arrayList.add(check((Wallet) it.next()));
        }
        ArrayList<Object[]> arrayList2 = new ArrayList();
        ArrayList arrayList3 = new ArrayList();
        synchronized (Wallets.class) {
            Iterator it2 = arrayList.iterator();
            while (true) {
                int i = 0;
                if (!it2.hasNext()) {
                    break;
                }
                Wallet wallet = (Wallet) it2.next();
                while (true) {
                    List<Wallet> list3 = list;
                    if (i < list3.size()) {
                        if (list3.get(i).id.equals(wallet.id)) {
                            Wallet wallet2 = list3.get(i);
                            wallet.name = wallet2.name;
                            wallet.hidden = wallet2.hidden;
                            wallet.hideUntil = wallet2.hideUntil;
                            wallet.shareHide = wallet2.shareHide;
                            List<Act> newActivity = newActivity(wallet);
                            if ("proven".equals(wallet.proof) && !wallet.proofTx.isEmpty() && !wallet.proofTx.equals(wallet2.proofTx)) {
                                arrayList3.add(wallet);
                            } else if ("proven".equals(wallet.proof) && !Witness.exists(context, wallet)) {
                                Witness.save(context, wallet);
                            }
                            list3.set(i, wallet);
                            if (!newActivity.isEmpty() && !offFront(wallet)) {
                                arrayList2.add(new Object[]{wallet, newActivity});
                            }
                        }
                        i++;
                    }
                }
            }
            busy = false;
            save(context);
        }
        Listener listener2 = listener;
        if (listener2 != null) {
            for (Object[] objArr : arrayList2) {
                listener2.onNews((Wallet) objArr[0], (List) objArr[1]);
            }
        }
        ProofListener proofListener2 = proofListener;
        if (proofListener2 != null) {
            Iterator it3 = arrayList3.iterator();
            while (it3.hasNext()) {
                proofListener2.onProof((Wallet) it3.next());
            }
        }
        if (again) {
            again = false;
            refreshAll(context);
        }
    }

    private static List<Act> newActivity(Wallet wallet) {
        HashSet hashSet = new HashSet(wallet.seen);
        ArrayList arrayList = new ArrayList();
        for (int size = wallet.activity.size() - 1; size >= 0; size--) {
            Act act = wallet.activity.get(size);
            if (!hashSet.contains(act.id)) {
                hashSet.add(act.id);
                wallet.seen.add(act.id);
                if (wallet.primed) {
                    arrayList.add(act);
                }
            }
        }
        while (wallet.seen.size() > 600) {
            wallet.seen.remove(0);
        }
        wallet.primed = STATIA;
        return arrayList;
    }

    private static Wallet check(Wallet wallet) {
        try {
            wallet.status = "";
            if (wallet.kind.equals("etherfi")) {
                checkEtherfi(wallet);
            } else if (wallet.kind.equals("tron")) {
                checkTron(wallet);
            } else if (isCoin(wallet.kind)) {
                checkCoin(wallet);
            } else if (wallet.kind.equals("lesson")) {
                checkLesson(wallet);
            } else {
                checkSolana(wallet);
            }
            wallet.updated = System.currentTimeMillis() / 1000.0d;
        } catch (Exception e) {
            wallet.status = "Couldn't check: " + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
        }
        return wallet;
    }

    /* JADX WARN: Removed duplicated region for block: B:112:0x0281  */
    /* JADX WARN: Removed duplicated region for block: B:94:0x0229  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    private static void checkEtherfi(com.novera.ana.Wallets.Wallet r27) throws java.lang.Exception {
        /*
            Method dump skipped, instructions count: 682
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Wallets.checkEtherfi(com.novera.ana.Wallets$Wallet):void");
    }

    private static double gatewayAmount(String str, String str2) throws Exception {
        String ethCall = ethCall(LEND_GATEWAY, str + PAD + str2.substring(2) + "0000000000000000000000000b2c639c533813f4aa9d7837caf62653d097ff85");
        BigInteger bigInteger = new BigInteger(ethCall.substring(2).isEmpty() ? "0" : ethCall.substring(2), 16);
        double scaled = scaled(bigInteger, 6);
        return scaled > 1.0E12d ? scaled(bigInteger, 18) : scaled;
    }

    private static String friendly(String str, String str2) {
        String lowerCase = str.toLowerCase(Locale.US);
        if (str2.equals(RHINO) || lowerCase.contains("rhino")) {
            return "Rhino.fi bridge";
        }
        return lowerCase.contains("cctp") ? "Circle's bridge" : lowerCase.contains("settlement") ? "card payment" : (lowerCase.contains("proxy") || lowerCase.startsWith("erc1967")) ? "" : str;
    }

    private static double erc20Balance(String str, String str2) throws Exception {
        String ethCall = ethCall(str, "0x70a08231000000000000000000000000" + str2.substring(2));
        return scaled(new BigInteger(ethCall.substring(2).isEmpty() ? "0" : ethCall.substring(2), 16), 6);
    }

    private static String ethCall(String str, String str2) throws Exception {
        String optString = rpc(OP_RPC, "eth_call", new JSONArray().put(new JSONObject().put("to", str).put("data", str2)).put("latest")).optString("result", "");
        if (optString.startsWith("0x")) {
            return optString;
        }
        throw new Exception("No answer from Optimism");
    }

    private static boolean isZero(String str) {
        String substring = str.substring(2);
        if (substring.isEmpty() || new BigInteger(substring, 16).signum() == 0) {
            return STATIA;
        }
        return false;
    }

    private static void checkSolana(Wallet wallet) throws Exception {
        double d;
        JSONObject optJSONObject = rpc(SOL_RPC, "getBalance", new JSONArray().put(wallet.addr)).optJSONObject("result");
        if (optJSONObject != null) {
            wallet.sol = optJSONObject.optDouble("value", 0.0d) / 1.0E9d;
        }
        JSONObject optJSONObject2 = rpc(SOL_RPC, "getTokenAccountsByOwner", new JSONArray().put(wallet.addr).put(new JSONObject().put("mint", SOL_USDC)).put(new JSONObject().put("encoding", "jsonParsed"))).optJSONObject("result");
        JSONArray optJSONArray = optJSONObject2 == null ? null : optJSONObject2.optJSONArray("value");
        if (optJSONArray != null) {
            d = 0.0d;
            for (int i = 0; i < optJSONArray.length(); i++) {
                JSONObject optJSONObject3 = optJSONArray.getJSONObject(i).optJSONObject("account");
                JSONObject optJSONObject4 = optJSONObject3 == null ? null : optJSONObject3.optJSONObject("data");
                JSONObject optJSONObject5 = optJSONObject4 == null ? null : optJSONObject4.optJSONObject("parsed");
                JSONObject optJSONObject6 = optJSONObject5 == null ? null : optJSONObject5.optJSONObject("info");
                JSONObject optJSONObject7 = optJSONObject6 == null ? null : optJSONObject6.optJSONObject("tokenAmount");
                if (optJSONObject7 != null) {
                    d += Double.parseDouble(optJSONObject7.optString("uiAmountString", "0"));
                }
            }
        } else {
            d = 0.0d;
        }
        double d2 = d - wallet.ready;
        if (wallet.primed && Math.abs(d2) >= 0.005d) {
            double currentTimeMillis = System.currentTimeMillis() / 1000.0d;
            List<Act> list2 = wallet.activity;
            double abs = Math.abs(d2);
            String str = d2 > 0.0d ? "in" : "out";
            list2.add(0, new Act(currentTimeMillis, abs, str, d2 > 0.0d ? "USDC arrived" : "USDC left", "bal-" + ((long) currentTimeMillis)));
            while (wallet.activity.size() > 40) {
                wallet.activity.remove(wallet.activity.size() - 1);
            }
        }
        wallet.ready = d;
    }

    private static void checkTron(Wallet wallet) throws Exception {
        double d;
        double d2;
        JSONArray optJSONArray = getJSON(TRON_API + wallet.addr).optJSONArray("data");
        double d3 = 0.0d;
        if (optJSONArray == null || optJSONArray.length() <= 0) {
            d = 0.0d;
            d2 = 0.0d;
        } else {
            JSONObject jSONObject = optJSONArray.getJSONObject(0);
            d = decimalValue(String.valueOf(jSONObject.optLong("balance", 0L)), 6);
            JSONArray optJSONArray2 = jSONObject.optJSONArray("trc20");
            if (optJSONArray2 != null) {
                d2 = 0.0d;
                for (int i = 0; i < optJSONArray2.length(); i++) {
                    JSONObject optJSONObject = optJSONArray2.optJSONObject(i);
                    if (optJSONObject != null && optJSONObject.has(TRON_USDT)) {
                        d2 += decimalValue(optJSONObject.optString(TRON_USDT, "0"), 6);
                    }
                }
            } else {
                d2 = 0.0d;
            }
        }
        wallet.sol = d;
        wallet.ready = d2;
        JSONArray optJSONArray3 = getJSON(TRON_API + wallet.addr + "/transactions/trc20?limit=40&contract_address=TR7NHqjeKQxGTCi8q8ZYpPDdtsWPBQiYzr").optJSONArray("data");
        ArrayList arrayList = new ArrayList();
        if (optJSONArray3 != null) {
            int i2 = 0;
            while (i2 < optJSONArray3.length()) {
                JSONObject jSONObject2 = optJSONArray3.getJSONObject(i2);
                JSONObject optJSONObject2 = jSONObject2.optJSONObject("token_info");
                double decimalValue = decimalValue(jSONObject2.optString("value", "0"), optJSONObject2 == null ? 6 : optJSONObject2.optInt("decimals", 6));
                if (decimalValue != d3) {
                    boolean equals = wallet.addr.equals(jSONObject2.optString("to"));
                    String optString = jSONObject2.optString(equals ? "from" : "to");
                    String shortAddr = shortAddr(optString);
                    StringBuilder sb = equals ? new StringBuilder("USDT arrived from ") : new StringBuilder("USDT sent to ");
                    sb.append(shortAddr);
                    String sb2 = sb.toString();
                    double optLong = jSONObject2.optLong("block_timestamp", 0L) / 1000.0d;
                    arrayList.add(new Act(optLong, decimalValue, equals ? "in" : "out", sb2, jSONObject2.optString("transaction_id", UUID.randomUUID().toString()) + "#" + optString + "#" + jSONObject2.optString("value")));
                }
                i2++;
                d3 = 0.0d;
            }
        }
        Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.Wallets$$ExternalSyntheticLambda5
            @Override // java.util.Comparator
            public final int compare(Object obj, Object obj2) {
                int compare;
                compare = Double.compare(((Wallets.Act) obj2).t, ((Wallets.Act) obj).t);
                return compare;
            }
        });
        wallet.activity = new ArrayList(arrayList.subList(0, Math.min(40, arrayList.size())));
    }

    static boolean isLitecoin(String str) {
        if (str.matches("^ltc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$")) {
            return STATIA;
        }
        if (str.matches("^[LM][1-9A-HJ-NP-Za-km-z]{32,33}$")) {
            return base58check(str, 48, 50);
        }
        return false;
    }

    static boolean isBitcoin(String str) {
        if (str.matches("^bc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$")) {
            return STATIA;
        }
        if (str.matches("^[13][1-9A-HJ-NP-Za-km-z]{25,34}$")) {
            return base58check(str, 0, 5);
        }
        return false;
    }

    static boolean isCoin(String str) {
        if (str.equals("litecoin") || str.equals("bitcoin")) {
            return STATIA;
        }
        return false;
    }

    private static void checkLesson(Wallet wallet) throws Exception {
        Object[] objArr;
        long j;
        Lessons.Lesson find = Lessons.find(wallet.lesson);
        if (find == null) {
            throw new Exception("its lesson was removed");
        }
        Object[] balance = Lessons.balance(find, wallet.addr);
        int decimals = Lessons.decimals(find);
        int i = 0;
        wallet.sol = Lessons.toCoin((BigInteger) balance[0], decimals);
        try {
            String nz = Lessons.nz(find.kv.get("coin|price_id"));
            JSONObject optJSONObject = getJSON(PRICE + nz).optJSONObject(nz);
            if (optJSONObject != null && optJSONObject.optDouble("usd", 0.0d) > 0.0d) {
                wallet.earning = optJSONObject.optDouble("usd");
            }
        } catch (Exception unused) {
        }
        wallet.ready = wallet.sol * wallet.earning;
        String str = "";
        wallet.status = "";
        if (!"esplora".equals(find.kv.get("reader|name"))) {
            wallet.proof = "";
            wallet.proofNote = "";
            wallet.proofTx = "";
            return;
        }
        String str2 = (String) balance[1];
        if (!str2.endsWith("/")) {
            str2 = str2 + "/";
        }
        JSONArray jSONArray = new JSONArray(readText(str2 + "address/" + wallet.addr + "/txs"));
        ArrayList arrayList = new ArrayList();
        double pow = Math.pow(10.0d, (double) decimals);
        int i2 = 0;
        while (i2 < jSONArray.length()) {
            JSONObject jSONObject = jSONArray.getJSONObject(i2);
            JSONArray optJSONArray = jSONObject.optJSONArray("vout");
            JSONArray optJSONArray2 = jSONObject.optJSONArray("vin");
            String str3 = str;
            if (optJSONArray != null) {
                j = 0;
                while (i < optJSONArray.length()) {
                    Object[] objArr2 = balance;
                    if (wallet.addr.equals(optJSONArray.getJSONObject(i).optString("scriptpubkey_address"))) {
                        j += optJSONArray.getJSONObject(i).optLong("value");
                    }
                    i++;
                    balance = objArr2;
                }
                objArr = balance;
            } else {
                objArr = balance;
                j = 0;
            }
            long j2 = 0;
            if (optJSONArray2 != null) {
                for (int i3 = 0; i3 < optJSONArray2.length(); i3++) {
                    JSONObject optJSONObject2 = optJSONArray2.getJSONObject(i3).optJSONObject("prevout");
                    if (optJSONObject2 != null && wallet.addr.equals(optJSONObject2.optString("scriptpubkey_address"))) {
                        j2 += optJSONObject2.optLong("value");
                    }
                }
            }
            long j3 = j - j2;
            if (j3 != 0) {
                JSONObject optJSONObject3 = jSONObject.optJSONObject("status");
                boolean z = (optJSONObject3 == null || !optJSONObject3.optBoolean("confirmed")) ? false : STATIA;
                Act act = new Act(z ? optJSONObject3.optLong("block_time") : System.currentTimeMillis() / 1000.0d, Math.abs(j3) / pow, j3 > 0 ? "in" : "out", find.name() + (j3 > 0 ? " arrived" : " sent") + (z ? str3 : " (pending)"), jSONObject.optString("txid") + (z ? str3 : "#p"));
                act.unit = find.ticker();
                arrayList.add(act);
            }
            i2++;
            str = str3;
            balance = objArr;
            i = 0;
        }
        String str4 = str;
        Object[] objArr3 = balance;
        Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.Wallets$$ExternalSyntheticLambda4
            @Override // java.util.Comparator
            public final int compare(Object obj, Object obj2) {
                int compare;
                compare = Double.compare(((Wallets.Act) obj2).t, ((Wallets.Act) obj).t);
                return compare;
            }
        });
        wallet.activity = new ArrayList(arrayList.subList(0, Math.min(40, arrayList.size())));
        if (!Proof.DECIMALS.containsKey(find.ticker())) {
            Proof.DECIMALS.put(find.ticker(), Integer.valueOf(decimals));
        }
        ArrayList arrayList2 = new ArrayList();
        for (int i4 = 0; i4 < jSONArray.length(); i4++) {
            arrayList2.add(Proof.Tx.from(jSONArray.getJSONObject(i4)));
        }
        Proof.Result evaluate = Proof.evaluate(appCtx, wallet.addr, find.ticker(), arrayList2, ((BigInteger) objArr3[0]).longValue());
        wallet.proof = evaluate.state;
        wallet.proofNote = evaluate.note;
        wallet.proofTx = evaluate.txid == null ? str4 : evaluate.txid;
        wallet.proofDetail = new JSONObject(evaluate.detail);
    }

    static String lessonAmount(Wallet wallet) {
        Lessons.Lesson find = Lessons.find(wallet.lesson);
        int shown = find == null ? 4 : Lessons.shown(find);
        return String.format(Locale.US, "%." + shown + "f %s", Double.valueOf(wallet.sol), find == null ? "" : find.ticker());
    }

    private static boolean base58check(String str, int i, int i2) {
        byte[] base58 = base58(str);
        if (base58 != null && base58.length == 25) {
            byte b = base58[0];
            if ((b & 255) == i || (b & 255) == i2) {
                try {
                    MessageDigest messageDigest = MessageDigest.getInstance("SHA-256");
                    byte[] digest = messageDigest.digest(messageDigest.digest(Arrays.copyOfRange(base58, 0, 21)));
                    for (int i3 = 0; i3 < 4; i3++) {
                        if (digest[i3] != base58[i3 + 21]) {
                            return false;
                        }
                    }
                    return STATIA;
                } catch (Exception unused) {
                }
            }
        }
        return false;
    }

    private static byte[] base58(String str) {
        BigInteger bigInteger = BigInteger.ZERO;
        int i = 0;
        for (int i2 = 0; i2 < str.length(); i2++) {
            int indexOf = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".indexOf(str.charAt(i2));
            if (indexOf < 0) {
                return null;
            }
            bigInteger = bigInteger.multiply(BigInteger.valueOf(58L)).add(BigInteger.valueOf(indexOf));
        }
        byte[] byteArray = bigInteger.toByteArray();
        int i3 = 0;
        while (i3 < str.length() && str.charAt(i3) == '1') {
            i3++;
        }
        if (byteArray.length > 1 && byteArray[0] == 0) {
            i = 1;
        }
        byte[] bArr = new byte[(byteArray.length + i3) - i];
        System.arraycopy(byteArray, i, bArr, i3, byteArray.length - i);
        return bArr;
    }

    private static void checkCoin(Wallet wallet) throws Exception {
        String str;
        long j;
        long j2;
        String str2 = "bitcoin";
        boolean equals = wallet.kind.equals("bitcoin");
        String str3 = equals ? BTC_API : LTC_API;
        String str4 = equals ? "BTC" : "LTC";
        String str5 = equals ? "Bitcoin" : "Litecoin";
        JSONObject json = getJSON(str3 + "address/" + wallet.addr);
        JSONObject optJSONObject = json.optJSONObject("chain_stats");
        JSONObject optJSONObject2 = json.optJSONObject("mempool_stats");
        long optLong = optJSONObject != null ? optJSONObject.optLong("funded_txo_sum") - optJSONObject.optLong("spent_txo_sum") : 0L;
        long optLong2 = optJSONObject2 == null ? 0L : optJSONObject2.optLong("funded_txo_sum") - optJSONObject2.optLong("spent_txo_sum");
        long j3 = optLong + optLong2;
        wallet.sol = j3 / 1.0E8d;
        try {
            JSONObject json2 = getJSON(PRICE.concat(equals ? "bitcoin" : "litecoin"));
            if (!equals) {
                str2 = "litecoin";
            }
            JSONObject optJSONObject3 = json2.optJSONObject(str2);
            if (optJSONObject3 != null && optJSONObject3.optDouble("usd", 0.0d) > 0.0d) {
                wallet.earning = optJSONObject3.optDouble("usd");
            }
        } catch (Exception unused) {
        }
        wallet.ready = wallet.sol * wallet.earning;
        String str6 = "";
        wallet.status = optLong2 != 0 ? "Pending: " + String.format(Locale.US, equals ? "%+.6f BTC" : "%+.4f LTC", Double.valueOf(optLong2 / 1.0E8d)) : "";
        JSONArray jSONArray = new JSONArray(readText(str3 + "address/" + wallet.addr + "/txs"));
        ArrayList arrayList = new ArrayList();
        int i = 0;
        while (i < jSONArray.length()) {
            JSONObject jSONObject = jSONArray.getJSONObject(i);
            JSONArray optJSONArray = jSONObject.optJSONArray("vout");
            JSONArray optJSONArray2 = jSONObject.optJSONArray("vin");
            if (optJSONArray != null) {
                int i2 = 0;
                j = 0;
                while (i2 < optJSONArray.length()) {
                    JSONObject jSONObject2 = optJSONArray.getJSONObject(i2);
                    String str7 = str6;
                    JSONArray jSONArray2 = optJSONArray;
                    if (wallet.addr.equals(jSONObject2.optString("scriptpubkey_address"))) {
                        j += jSONObject2.optLong("value");
                    }
                    i2++;
                    str6 = str7;
                    optJSONArray = jSONArray2;
                }
                str = str6;
            } else {
                str = str6;
                j = 0;
            }
            if (optJSONArray2 != null) {
                j2 = 0;
                for (int i3 = 0; i3 < optJSONArray2.length(); i3++) {
                    JSONObject optJSONObject4 = optJSONArray2.getJSONObject(i3).optJSONObject("prevout");
                    if (optJSONObject4 != null && wallet.addr.equals(optJSONObject4.optString("scriptpubkey_address"))) {
                        j2 += optJSONObject4.optLong("value");
                    }
                }
            } else {
                j2 = 0;
            }
            long j4 = j - j2;
            if (j4 != 0) {
                JSONObject optJSONObject5 = jSONObject.optJSONObject("status");
                boolean z = (optJSONObject5 == null || !optJSONObject5.optBoolean("confirmed")) ? false : STATIA;
                Act act = new Act(z ? optJSONObject5.optLong("block_time") : System.currentTimeMillis() / 1000.0d, Math.abs(j4) / 1.0E8d, j4 > 0 ? "in" : "out", str5 + (j4 > 0 ? " arrived" : " sent") + (z ? str : " (pending)"), jSONObject.optString("txid") + (z ? str : "#p"));
                act.unit = str4;
                arrayList.add(act);
            }
            i++;
            str6 = str;
        }
        String str8 = str6;
        Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.Wallets$$ExternalSyntheticLambda3
            @Override // java.util.Comparator
            public final int compare(Object obj, Object obj2) {
                int compare;
                compare = Double.compare(((Wallets.Act) obj2).t, ((Wallets.Act) obj).t);
                return compare;
            }
        });
        wallet.activity = new ArrayList(arrayList.subList(0, Math.min(40, arrayList.size())));
        ArrayList arrayList2 = new ArrayList();
        for (int i4 = 0; i4 < jSONArray.length(); i4++) {
            arrayList2.add(Proof.Tx.from(jSONArray.getJSONObject(i4)));
        }
        Proof.Result evaluate = Proof.evaluate(appCtx, wallet.addr, str4, arrayList2, j3);
        wallet.proof = evaluate.state;
        wallet.proofNote = evaluate.note;
        wallet.proofTx = evaluate.txid == null ? str8 : evaluate.txid;
        wallet.proofDetail = new JSONObject(evaluate.detail);
    }

    private static String readText(String str) throws Exception {
        HttpURLConnection httpURLConnection = (HttpURLConnection) new URL(str).openConnection();
        httpURLConnection.setConnectTimeout(20000);
        httpURLConnection.setReadTimeout(20000);
        httpURLConnection.setRequestProperty("Accept", "application/json");
        return read(httpURLConnection);
    }

    private static JSONObject rpc(String str, String str2, JSONArray jSONArray) throws Exception {
        JSONObject put = new JSONObject().put("jsonrpc", "2.0").put("id", 1).put("method", str2).put("params", jSONArray);
        HttpURLConnection httpURLConnection = (HttpURLConnection) new URL(str).openConnection();
        httpURLConnection.setConnectTimeout(20000);
        httpURLConnection.setReadTimeout(20000);
        httpURLConnection.setRequestMethod("POST");
        httpURLConnection.setDoOutput(STATIA);
        httpURLConnection.setRequestProperty("Content-Type", "application/json");
        OutputStream outputStream = httpURLConnection.getOutputStream();
        try {
            outputStream.write(put.toString().getBytes(StandardCharsets.UTF_8));
            if (outputStream != null) {
                outputStream.close();
            }
            JSONObject jSONObject = new JSONObject(read(httpURLConnection));
            JSONObject optJSONObject = jSONObject.optJSONObject("error");
            if (optJSONObject == null) {
                return jSONObject;
            }
            throw new Exception(optJSONObject.optString("message", "Error from " + str2));
        } catch (Throwable th) {
            if (outputStream != null) {
                try {
                    outputStream.close();
                } catch (Throwable th2) {
                    th.addSuppressed(th2);
                }
            }
            throw th;
        }
    }

    private static JSONObject getJSON(String str) throws Exception {
        HttpURLConnection httpURLConnection = (HttpURLConnection) new URL(str).openConnection();
        httpURLConnection.setConnectTimeout(20000);
        httpURLConnection.setReadTimeout(20000);
        httpURLConnection.setRequestProperty("Accept", "application/json");
        httpURLConnection.setInstanceFollowRedirects(STATIA);
        return httpURLConnection.getResponseCode() == 404 ? new JSONObject().put("items", new JSONArray()) : new JSONObject(read(httpURLConnection));
    }

    private static String read(HttpURLConnection httpURLConnection) throws Exception {
        int responseCode = httpURLConnection.getResponseCode();
        try {
            InputStream errorStream = responseCode >= 400 ? httpURLConnection.getErrorStream() : httpURLConnection.getInputStream();
            try {
                if (errorStream == null) {
                    throw new Exception("HTTP " + responseCode);
                }
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                byte[] bArr = new byte[16384];
                while (true) {
                    int read = errorStream.read(bArr);
                    if (read <= 0) {
                        break;
                    }
                    byteArrayOutputStream.write(bArr, 0, read);
                }
                if (responseCode >= 400) {
                    throw new Exception("HTTP " + responseCode);
                }
                String str = new String(byteArrayOutputStream.toByteArray(), StandardCharsets.UTF_8);
                if (errorStream != null) {
                    errorStream.close();
                }
                return str;
            } finally {
            }
        } finally {
            httpURLConnection.disconnect();
        }
    }

    private static double scaled(BigInteger bigInteger, int i) {
        return new BigDecimal(bigInteger).movePointLeft(i).doubleValue();
    }

    private static double decimalValue(String str, int i) {
        try {
            return new BigDecimal(new BigInteger(str.trim())).movePointLeft(i).doubleValue();
        } catch (Exception unused) {
            return 0.0d;
        }
    }

    private static double isoSeconds(String str) {
        try {
            new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).setTimeZone(TimeZone.getTimeZone("UTC"));
            return r0.parse(str.substring(0, 19)).getTime() / 1000.0d;
        } catch (Exception unused) {
            return 0.0d;
        }
    }

    static String money(double d) {
        return String.format(Locale.US, "$%.2f", Double.valueOf(d));
    }

    static String actAmount(Act act) {
        if (act.unit.isEmpty()) {
            return money(act.amt);
        }
        return String.format(Locale.US, act.unit.equals("BTC") ? "%.6f %s" : "%.4f %s", Double.valueOf(act.amt), act.unit);
    }

    static synchronized String totals() {
        String format;
        synchronized (Wallets.class) {
            double d = 0.0d;
            double d2 = 0.0d;
            double d3 = 0.0d;
            for (Wallet wallet : list) {
                double max = wallet.kind.equals("etherfi") ? (wallet.ready + wallet.earning) - Math.max(0.0d, wallet.debt) : wallet.ready;
                d += max;
                if (!offFront(wallet)) {
                    d2 += max;
                }
                if ("proven".equals(wallet.proof)) {
                    d3 += max;
                }
            }
            format = String.format(Locale.US, "%.2f\t%.2f\t%s\t%.2f", Double.valueOf(d), Double.valueOf(d2), capturing ? "1" : "0", Double.valueOf(d3));
        }
        return format;
    }

    static String coinAmount(Wallet wallet) {
        return wallet.kind.equals("bitcoin") ? String.format(Locale.US, "%.6f BTC", Double.valueOf(wallet.sol)) : String.format(Locale.US, "%.4f LTC", Double.valueOf(wallet.sol));
    }

    static String shortAddr(String str) {
        if (str.length() <= 12) {
            return str;
        }
        return str.substring(0, 6) + "..." + str.substring(str.length() - 4);
    }

    static String ago(double d) {
        if (d <= 0.0d) {
            return "Not checked yet";
        }
        long currentTimeMillis = (long) ((System.currentTimeMillis() / 1000.0d) - d);
        if (currentTimeMillis < 60) {
            return "Checked just now";
        }
        if (currentTimeMillis < 3600) {
            return "Checked " + (currentTimeMillis / 60) + " min ago";
        }
        if (currentTimeMillis < 86400) {
            return "Checked " + (currentTimeMillis / 3600) + " h ago";
        }
        return "Checked " + (currentTimeMillis / 86400) + " days ago";
    }

    static String when(double d) {
        return new SimpleDateFormat("MMM d, HH:mm", Locale.US).format(new Date((long) (d * 1000.0d)));
    }

    private static String line(String... strArr) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < strArr.length; i++) {
            if (i > 0) {
                sb.append('\t');
            }
            sb.append(AnaLog.clean(strArr[i]));
        }
        return sb.toString();
    }

    /* JADX WARN: Removed duplicated region for block: B:105:0x037f  */
    /* JADX WARN: Removed duplicated region for block: B:108:0x0364  */
    /* JADX WARN: Removed duplicated region for block: B:78:0x0361  */
    /* JADX WARN: Removed duplicated region for block: B:81:0x0375 A[Catch: all -> 0x04cc, TryCatch #0 {, blocks: (B:4:0x0003, B:6:0x000e, B:7:0x0014, B:9:0x001a, B:11:0x002a, B:12:0x0054, B:14:0x005e, B:16:0x0064, B:17:0x006b, B:18:0x006f, B:21:0x00b3, B:24:0x00dd, B:28:0x00e7, B:32:0x007d, B:35:0x008a, B:38:0x0097, B:41:0x00a4, B:45:0x003b, B:47:0x0043, B:49:0x0049, B:50:0x004e, B:52:0x00f5, B:56:0x00fd, B:57:0x0103, B:59:0x0109, B:62:0x0116, B:145:0x0130, B:148:0x013f, B:153:0x015c, B:171:0x016c, B:173:0x0192, B:174:0x019b, B:176:0x01b8, B:177:0x01c1, B:156:0x01de, B:158:0x0204, B:162:0x0218, B:164:0x022f, B:165:0x0238, B:168:0x0214, B:182:0x014c, B:184:0x0154, B:185:0x0157, B:186:0x013b, B:65:0x024d, B:122:0x0255, B:125:0x0268, B:129:0x027f, B:131:0x02a5, B:132:0x02ae, B:134:0x02c7, B:135:0x02d0, B:139:0x0271, B:141:0x0279, B:142:0x027c, B:68:0x02ed, B:70:0x02f5, B:73:0x030a, B:79:0x036b, B:81:0x0375, B:86:0x038a, B:89:0x03ad, B:96:0x03b3, B:92:0x03dc, B:99:0x0393, B:102:0x039c, B:111:0x032a, B:115:0x0339, B:120:0x02fc, B:191:0x03fd, B:192:0x0408, B:194:0x040e, B:197:0x041a, B:198:0x0420, B:200:0x0426, B:204:0x044a, B:206:0x0452, B:208:0x047c, B:209:0x045a, B:212:0x046b, B:214:0x043a, B:222:0x049e, B:223:0x04a7, B:225:0x04b3, B:227:0x04c4), top: B:3:0x0003 }] */
    /* JADX WARN: Removed duplicated region for block: B:86:0x038a A[Catch: all -> 0x04cc, TryCatch #0 {, blocks: (B:4:0x0003, B:6:0x000e, B:7:0x0014, B:9:0x001a, B:11:0x002a, B:12:0x0054, B:14:0x005e, B:16:0x0064, B:17:0x006b, B:18:0x006f, B:21:0x00b3, B:24:0x00dd, B:28:0x00e7, B:32:0x007d, B:35:0x008a, B:38:0x0097, B:41:0x00a4, B:45:0x003b, B:47:0x0043, B:49:0x0049, B:50:0x004e, B:52:0x00f5, B:56:0x00fd, B:57:0x0103, B:59:0x0109, B:62:0x0116, B:145:0x0130, B:148:0x013f, B:153:0x015c, B:171:0x016c, B:173:0x0192, B:174:0x019b, B:176:0x01b8, B:177:0x01c1, B:156:0x01de, B:158:0x0204, B:162:0x0218, B:164:0x022f, B:165:0x0238, B:168:0x0214, B:182:0x014c, B:184:0x0154, B:185:0x0157, B:186:0x013b, B:65:0x024d, B:122:0x0255, B:125:0x0268, B:129:0x027f, B:131:0x02a5, B:132:0x02ae, B:134:0x02c7, B:135:0x02d0, B:139:0x0271, B:141:0x0279, B:142:0x027c, B:68:0x02ed, B:70:0x02f5, B:73:0x030a, B:79:0x036b, B:81:0x0375, B:86:0x038a, B:89:0x03ad, B:96:0x03b3, B:92:0x03dc, B:99:0x0393, B:102:0x039c, B:111:0x032a, B:115:0x0339, B:120:0x02fc, B:191:0x03fd, B:192:0x0408, B:194:0x040e, B:197:0x041a, B:198:0x0420, B:200:0x0426, B:204:0x044a, B:206:0x0452, B:208:0x047c, B:209:0x045a, B:212:0x046b, B:214:0x043a, B:222:0x049e, B:223:0x04a7, B:225:0x04b3, B:227:0x04c4), top: B:3:0x0003 }] */
    /* JADX WARN: Removed duplicated region for block: B:99:0x0393 A[Catch: all -> 0x04cc, TryCatch #0 {, blocks: (B:4:0x0003, B:6:0x000e, B:7:0x0014, B:9:0x001a, B:11:0x002a, B:12:0x0054, B:14:0x005e, B:16:0x0064, B:17:0x006b, B:18:0x006f, B:21:0x00b3, B:24:0x00dd, B:28:0x00e7, B:32:0x007d, B:35:0x008a, B:38:0x0097, B:41:0x00a4, B:45:0x003b, B:47:0x0043, B:49:0x0049, B:50:0x004e, B:52:0x00f5, B:56:0x00fd, B:57:0x0103, B:59:0x0109, B:62:0x0116, B:145:0x0130, B:148:0x013f, B:153:0x015c, B:171:0x016c, B:173:0x0192, B:174:0x019b, B:176:0x01b8, B:177:0x01c1, B:156:0x01de, B:158:0x0204, B:162:0x0218, B:164:0x022f, B:165:0x0238, B:168:0x0214, B:182:0x014c, B:184:0x0154, B:185:0x0157, B:186:0x013b, B:65:0x024d, B:122:0x0255, B:125:0x0268, B:129:0x027f, B:131:0x02a5, B:132:0x02ae, B:134:0x02c7, B:135:0x02d0, B:139:0x0271, B:141:0x0279, B:142:0x027c, B:68:0x02ed, B:70:0x02f5, B:73:0x030a, B:79:0x036b, B:81:0x0375, B:86:0x038a, B:89:0x03ad, B:96:0x03b3, B:92:0x03dc, B:99:0x0393, B:102:0x039c, B:111:0x032a, B:115:0x0339, B:120:0x02fc, B:191:0x03fd, B:192:0x0408, B:194:0x040e, B:197:0x041a, B:198:0x0420, B:200:0x0426, B:204:0x044a, B:206:0x0452, B:208:0x047c, B:209:0x045a, B:212:0x046b, B:214:0x043a, B:222:0x049e, B:223:0x04a7, B:225:0x04b3, B:227:0x04c4), top: B:3:0x0003 }] */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    static synchronized java.lang.String pageText() {
        /*
            Method dump skipped, instructions count: 1231
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: com.novera.ana.Wallets.pageText():java.lang.String");
    }
}
