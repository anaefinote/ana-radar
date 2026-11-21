package com.novera.ana;

import android.content.Context;
import android.text.TextUtils;
import com.novera.ana.Engine;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;

/* loaded from: classes.dex */
final class Lessons {
    static final int READER = 1;
    static final boolean TEST_KEYS = true;
    static AnaRule rule;
    static final String[] TRUSTED = {"046ccf9b361b03195370d4ea27b07291b45923a37062a410e55295673ca2297b5a23099f458ca11e4129635df235f660db6bfb06199a83380c59885d75c9dbc3f5", "04975cef9f466270d282fbcb5b649e07370f08d195cf23eefa1cc51bc185d349e434d34e45ac32766ae865a229fd3b6c6920bdd0f9dc10a4d6e907e2cb92165825"};
    static final List<String> HIVES = Arrays.asList("watch");
    static final List<Lesson> list = new ArrayList();
    static Engine E = new Engine();
    static String problems = "";

    private Lessons() {
    }

    static final class Lesson {
        String file;
        String id;
        String keyId;
        LinkedHashMap<String, String> kv;
        int version;

        Lesson() {
        }

        String name() {
            return Lessons.nz(this.kv.get("coin|name"));
        }

        String ticker() {
            return Lessons.nz(this.kv.get("coin|ticker"));
        }
    }

    static String tier(Context context) {
        return context.getPackageName().endsWith("statia") ? "statia" : "ana";
    }

    static File dir(Context context) {
        File file = new File(context.getFilesDir(), "lessons");
        file.mkdirs();
        return file;
    }

    static synchronized void load(Context context) {
        List<Lesson> list2;
        synchronized (Lessons.class) {
            rule = fresh(context);
            list.clear();
            StringBuilder sb = new StringBuilder();
            List<String> readOrder = readOrder(context);
            int i = 0;
            while (i < 2) {
                for (String str : readOrder) {
                    byte[] read = read(new File(dir(context), str));
                    byte[] read2 = read(new File(dir(context), str + ".sha256"));
                    if (read != null) {
                        int classOf = classOf(read);
                        boolean z = TEST_KEYS;
                        boolean z2 = i == 0 ? READER : false;
                        if (classOf != 31 && classOf != 32) {
                            z = false;
                        }
                        String[] check = rule.check(read, read2);
                        if (check[0].equals("ACCEPT") && classOf == 30) {
                            Lesson lesson = new Lesson();
                            lesson.kv = rule.last.kv;
                            lesson.id = nz(lesson.kv.get("lesson|id"));
                            lesson.version = AnaRule.intOr(lesson.kv.get("lesson|version"), 0);
                            lesson.file = str;
                            lesson.keyId = rule.last.keyId;
                            int i2 = 0;
                            while (true) {
                                list2 = list;
                                if (i2 >= list2.size()) {
                                    break;
                                }
                                if (list2.get(i2).id.equals(lesson.id)) {
                                    list2.remove(i2);
                                    break;
                                }
                                i2 += READER;
                            }
                            list2.add(lesson);
                        } else if (!check[0].equals("ACCEPT")) {
                            sb.append(str);
                            sb.append(": ");
                            sb.append(say(check[0]));
                            sb.append("\n");
                        }
                    }
                }
                i += READER;
            }
            problems = sb.toString();
        }
    }

    static AnaRule fresh(Context context) {
        return new AnaRule(READER, tier(context), HIVES, Arrays.asList(TRUSTED));
    }

    static synchronized String[] preview(Context context, byte[] bArr, byte[] bArr2) {
        String str;
        String[] strArr;
        synchronized (Lessons.class) {
            if (rule == null) {
                load(context);
            }
            AnaRule anaRule = rule;
            List<Lesson> list2 = list;
            ArrayList arrayList = new ArrayList(list2);
            String str2 = problems;
            load(context);
            String[] check = rule.check(bArr, bArr2);
            String str3 = "";
            if (check[0].equals("ACCEPT") && classOf(bArr) == 30) {
                str3 = confirmText(rule.last.kv);
            }
            rule = anaRule;
            list2.clear();
            list2.addAll(arrayList);
            problems = str2;
            String str4 = check[0];
            String say = say(str4);
            if (!check[READER].isEmpty() && !check[0].equals("ACCEPT")) {
                str = " (" + check[READER] + ")";
                strArr = new String[]{str4, say + str, str3};
            }
            str = "";
            strArr = new String[]{str4, say + str, str3};
        }
        return strArr;
    }

    static synchronized String add(Context context, byte[] bArr, byte[] bArr2) {
        synchronized (Lessons.class) {
            String[] preview = preview(context, bArr, bArr2);
            if (!preview[0].equals("ACCEPT")) {
                return preview[READER];
            }
            String str = "f_" + E.sha256hex(bArr).substring(0, 16) + ".pngmesh";
            write(new File(dir(context), str), bArr);
            write(new File(dir(context), str + ".sha256"), (E.sha256hex(bArr) + "\n" + str + "\n" + bArr.length + "\n").getBytes(StandardCharsets.UTF_8));
            List<String> readOrder = readOrder(context);
            if (!readOrder.contains(str)) {
                readOrder.add(str);
            }
            writeOrder(context, readOrder);
            load(context);
            return "Added";
        }
    }

    static synchronized void remove(Context context, String str) {
        synchronized (Lessons.class) {
            List<String> readOrder = readOrder(context);
            Iterator it = new ArrayList(list).iterator();
            while (it.hasNext()) {
                Lesson lesson = (Lesson) it.next();
                if (lesson.id.equals(str)) {
                    readOrder.remove(lesson.file);
                    new File(dir(context), lesson.file).delete();
                    new File(dir(context), lesson.file + ".sha256").delete();
                }
            }
            writeOrder(context, readOrder);
            load(context);
        }
    }

    static synchronized Lesson find(String str) {
        synchronized (Lessons.class) {
            for (Lesson lesson : list) {
                if (lesson.id.equals(str)) {
                    return lesson;
                }
            }
            return null;
        }
    }

    static synchronized Lesson forAddress(String str) {
        synchronized (Lessons.class) {
            for (Lesson lesson : list) {
                if (E.anyFormOk(slash(lesson.kv), str)) {
                    return lesson;
                }
            }
            return null;
        }
    }

    static Object[] balance(Lesson lesson, String str) throws Exception {
        String nz = nz(lesson.kv.get("reader|name"));
        StringBuilder sb = new StringBuilder();
        for (String str2 : lesson.kv.keySet()) {
            if (str2.startsWith("param|")) {
                if (sb.length() > 0) {
                    sb.append(';');
                }
                sb.append(str2.substring(6));
                sb.append('=');
                sb.append(lesson.kv.get(str2));
            }
        }
        String str3 = "no server";
        for (int i = READER; i < 100; i += READER) {
            String str4 = lesson.kv.get("server|" + i);
            if (str4 == null) {
                break;
            }
            Engine.Probe runProbe = E.runProbe(nz, str4, sb.toString(), str);
            if (runProbe.ok) {
                return new Object[]{runProbe.raw, str4};
            }
            str3 = runProbe.note;
        }
        throw new Exception(str3);
    }

    static int decimals(Lesson lesson) {
        return AnaRule.intOr(lesson.kv.get("coin|decimals"), 0);
    }

    static int shown(Lesson lesson) {
        return AnaRule.intOr(lesson.kv.get("coin|display_decimals"), 4);
    }

    static double toCoin(BigInteger bigInteger, int i) {
        return new BigDecimal(bigInteger).movePointLeft(i).doubleValue();
    }

    static String confirmText(LinkedHashMap<String, String> linkedHashMap) {
        ArrayList arrayList = new ArrayList();
        for (String str : linkedHashMap.keySet()) {
            if (str.startsWith("server|")) {
                String replaceFirst = linkedHashMap.get(str).replaceFirst("^https?://", "");
                int length = replaceFirst.length();
                for (int i = 0; i < replaceFirst.length(); i += READER) {
                    char charAt = replaceFirst.charAt(i);
                    if (charAt == '/' || charAt == ':' || charAt == '?' || charAt == '#') {
                        length = i;
                        break;
                    }
                }
                String substring = replaceFirst.substring(0, length);
                if (!arrayList.contains(substring)) {
                    arrayList.add(substring);
                }
            }
        }
        return "Add " + nz(linkedHashMap.get("coin|name")) + " (" + nz(linkedHashMap.get("coin|ticker")) + ")?  ANA will send the addresses you watch to: " + TextUtils.join(", ", arrayList);
    }

    static String say(String str) {
        str.hashCode();
        switch (str) {
            case "BAD_SIGNATURE":
            case "HIGH_S":
                return "This file was changed after signing";
            case "UPDATE_FIRST":
                return "Update ANA to read this";
            case "EXPIRED":
                return "This signer's licence has ended";
            case "UNKNOWN_KEY":
                return "Signed by someone ANA doesn't trust";
            case "DUPLICATE":
                return "You already have this";
            case "BAD_SIDECAR":
                return "This file is damaged (it doesn't match its .sha256)";
            case "FORK":
                return "Two different files claim the same place";
            case "HOLE":
                return "Something earlier is missing; waiting for it";
            case "OLDER":
                return "You have a newer version";
            case "WRONG_HIVE":
                return "This lesson is for a hive this app doesn't have";
            case "WRONG_TIER":
                return "Part of ANA : STATIA, ANA's big sister";
            case "BAD_RULES":
                return "This lesson breaks a safety rule";
            case "BAD_FORMAT":
                return "This file is damaged";
            case "NOT_PERMITTED":
                return "This signer isn't licensed for this";
            case "REVOKED":
                return "This signer was switched off";
            case "ACCEPT":
                return "Added";
            case "FROZEN":
                return "This signer is frozen after a fork";
            default:
                return str;
        }
    }

    static synchronized String text() {
        String sb;
        synchronized (Lessons.class) {
            StringBuilder sb2 = new StringBuilder();
            for (Lesson lesson : list) {
                ArrayList arrayList = new ArrayList();
                for (String str : lesson.kv.keySet()) {
                    if (str.startsWith("server|")) {
                        arrayList.add(lesson.kv.get(str).replaceFirst("^https?://", "").replaceFirst("[/:?#].*$", ""));
                    }
                }
                sb2.append(lesson.id);
                sb2.append('\t');
                sb2.append(lesson.name());
                sb2.append('\t');
                sb2.append(lesson.ticker());
                sb2.append('\t');
                sb2.append(lesson.version);
                sb2.append('\t');
                sb2.append(TextUtils.join(", ", arrayList));
                sb2.append('\n');
            }
            sb = sb2.toString();
        }
        return sb;
    }

    static LinkedHashMap<String, String> slash(LinkedHashMap<String, String> linkedHashMap) {
        LinkedHashMap<String, String> linkedHashMap2 = new LinkedHashMap<>();
        for (String str : linkedHashMap.keySet()) {
            linkedHashMap2.put(str.replaceFirst("\\|", "/"), linkedHashMap.get(str));
        }
        return linkedHashMap2;
    }

    static int classOf(byte[] bArr) {
        long j = 0;
        for (int i = 0; i < 8; i += READER) {
            try {
                j = (j << 8) | (bArr[(bArr.length - 8) + i] & 255);
            } catch (Exception unused) {
                return -1;
            }
        }
        int length = (int) ((bArr.length - 8) - j);
        return (bArr[length + 15] & 255) | ((bArr[length + 12] & 255) << 24) | ((bArr[length + 13] & 255) << 16) | ((bArr[length + 14] & 255) << 8);
    }

    static String nz(String str) {
        return str == null ? "" : str;
    }

    static List<String> readOrder(Context context) {
        ArrayList arrayList = new ArrayList();
        byte[] read = read(new File(dir(context), "order.txt"));
        if (read == null) {
            return arrayList;
        }
        String[] split = new String(read, StandardCharsets.UTF_8).split("\n");
        int length = split.length;
        for (int i = 0; i < length; i += READER) {
            String str = split[i];
            if (str.trim().length() > 0) {
                arrayList.add(str.trim());
            }
        }
        return arrayList;
    }

    static void writeOrder(Context context, List<String> list2) {
        write(new File(dir(context), "order.txt"), (TextUtils.join("\n", list2) + "\n").getBytes(StandardCharsets.UTF_8));
    }

    static byte[] read(File file) {
        if (!file.exists()) {
            return null;
        }
        try {
            FileInputStream fileInputStream = new FileInputStream(file);
            try {
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                byte[] bArr = new byte[8192];
                while (true) {
                    int read = fileInputStream.read(bArr);
                    if (read <= 0) {
                        byte[] byteArray = byteArrayOutputStream.toByteArray();
                        fileInputStream.close();
                        return byteArray;
                    }
                    byteArrayOutputStream.write(bArr, 0, read);
                }
            } finally {
            }
        } catch (IOException unused) {
            return null;
        }
    }

    static void write(File file, byte[] bArr) {
        try {
            FileOutputStream fileOutputStream = new FileOutputStream(file);
            try {
                fileOutputStream.write(bArr);
                fileOutputStream.close();
            } finally {
            }
        } catch (IOException unused) {
        }
    }
}
