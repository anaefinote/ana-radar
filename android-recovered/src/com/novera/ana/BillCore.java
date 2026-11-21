package com.novera.ana;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/* loaded from: classes.dex */
final class BillCore {
    static final long AHEAD = 604800000;
    static final double CLAIMED = 0.25d;
    static final int CLS_BILL = 40;
    static final int CLS_CHAT = 46;
    static final int CLS_HELP = 41;
    static final int CLS_JOURNEY = 45;
    static final int CLS_PAID = 44;
    static final int CLS_SCHED = 43;
    static final int CLS_THANKS = 42;
    static final long DAY = 86400000;
    static final long GOAL = 2592000000L;
    static final long HELP_WINDOW = 1209600000;
    static final long LATE_GRACE = 604800000;
    static final int MAX_OCC = 400;
    static final String NO_MONEY = "Novvera never touches money. Not yours, not your group's, not ever. ANA can't pay, hold, move, collect or send a single cent. You pay your billers yourself, in your own bank or biller app. ANA only keeps track, on your phone.";
    static final long PAID_AFTER = 172800000;
    static final long PAID_BEFORE = 604800000;
    static final long PAIR_DAYS = 2592000000L;
    static final double R_AHEAD = 1.25d;
    static final double R_HELPED = 0.5d;
    static final double R_HELPER = 1.0d;
    static final double R_LATE = 0.5d;
    static final double R_PAID = 0.5d;
    static final double R_PLAN = 1.0d;
    static final long SETTLE = 2592000000L;
    static final String[] UNITS = {"day", "week", "month", "year"};
    private static final Pattern MONEY = Pattern.compile("(?<![0-9.,])((?:\\$|BBD|USD|BDS)\\s*)?([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(\\.[0-9]{2})?(?![0-9])");

    interface Signer {
        byte[][] sign(byte[] bArr);
    }

    private BillCore() {
    }

    static List<String> schedule(String str, int i, String str2) {
        int i2;
        ArrayList arrayList = new ArrayList();
        Calendar cal = cal(str);
        if (cal == null) {
            return arrayList;
        }
        if (i <= 0) {
            arrayList.add(str);
            return arrayList;
        }
        Calendar calendar = (Calendar) cal.clone();
        calendar.add(2, 12);
        for (int i3 = 0; i3 < MAX_OCC; i3++) {
            Calendar calendar2 = (Calendar) cal.clone();
            if (str2.equals("day")) {
                i2 = 5;
            } else if (str2.equals("week")) {
                i2 = 3;
            } else {
                i2 = str2.equals("year") ? 1 : 2;
            }
            calendar2.add(i2, i3 * i);
            if (calendar2.after(calendar)) {
                break;
            }
            arrayList.add(ymd(calendar2));
        }
        return arrayList;
    }

    static Calendar cal(String str) {
        if (str == null || !str.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}")) {
            return null;
        }
        Calendar calendar = Calendar.getInstance();
        calendar.clear();
        calendar.set(Integer.parseInt(str.substring(0, 4)), Integer.parseInt(str.substring(5, 7)) - 1, Integer.parseInt(str.substring(8, 10)));
        if (ymd(calendar).equals(str)) {
            return calendar;
        }
        return null;
    }

    static String ymd(Calendar calendar) {
        return String.format(Locale.US, "%04d-%02d-%02d", Integer.valueOf(calendar.get(1)), Integer.valueOf(calendar.get(2) + 1), Integer.valueOf(calendar.get(5)));
    }

    static String ymd(long j) {
        Calendar calendar = Calendar.getInstance();
        calendar.setTimeInMillis(j);
        return ymd(calendar);
    }

    static long dayEnd(String str) {
        Calendar cal = cal(str);
        if (cal == null) {
            return 0L;
        }
        cal.add(5, 1);
        return cal.getTimeInMillis() - 1;
    }

    static long period(int i, String str) {
        long j = 2592000000L;
        if (i <= 0) {
            return 2592000000L;
        }
        if (str.equals("day")) {
            j = DAY;
        } else if (str.equals("week")) {
            j = 604800000;
        } else if (str.equals("year")) {
            j = 31536000000L;
        }
        return i * j;
    }

    static long[] window(String str, int i, String str2, long j) {
        long dayEnd = dayEnd(str);
        long period = period(i, str2);
        return new long[]{Math.max(j - DAY, dayEnd - Math.min(2592000000L, period)), dayEnd, Math.min(604800000L, period) + dayEnd};
    }

    static String repeatWords(int i, String str) {
        if (i <= 0) {
            return "once";
        }
        if (i == 1) {
            if (str.equals("day")) {
                return "daily";
            }
            return str + "ly";
        }
        return "every " + i + " " + str + "s";
    }

    static long cents(String str) {
        if (str == null) {
            return -1L;
        }
        String replace = str.trim().replace("$", "").replace(",", "").replace(" ", "");
        if (!replace.matches("[0-9]{1,9}(\\.[0-9]{1,2})?")) {
            return -1L;
        }
        int indexOf = replace.indexOf(CLS_CHAT);
        if (indexOf < 0) {
            return Long.parseLong(replace) * 100;
        }
        String substring = replace.substring(indexOf + 1);
        if (substring.length() == 1) {
            substring = substring + "0";
        }
        return (Long.parseLong(replace.substring(0, indexOf)) * 100) + Long.parseLong(substring);
    }

    static String money(long j, String str) {
        long abs = Math.abs(j);
        String valueOf = String.valueOf(abs / 100);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < valueOf.length(); i++) {
            if (i > 0 && (valueOf.length() - i) % 3 == 0) {
                sb.append(',');
            }
            sb.append(valueOf.charAt(i));
        }
        long j2 = abs % 100;
        return (j < 0 ? "-" : "") + str + " " + String.valueOf(sb) + "." + (j2 < 10 ? "0" : "") + j2;
    }

    static String clean500(String str) {
        if (str == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            char charAt = str.charAt(i);
            if ((charAt < ' ' && charAt != '\n') || charAt == 127) {
                charAt = ' ';
            }
            sb.append(charAt);
        }
        String trim = sb.toString().trim();
        return trim.length() > 500 ? trim.substring(0, 500) : trim;
    }

    static String clean(String str) {
        if (str == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            char charAt = str.charAt(i);
            if (charAt < ' ' || charAt == 127) {
                charAt = ' ';
            }
            sb.append(charAt);
        }
        String replaceAll = sb.toString().trim().replaceAll(" {2,}", " ");
        return replaceAll.length() > 80 ? replaceAll.substring(0, 80) : replaceAll;
    }

    static double usd(long j, String str) {
        return j / ("BBD".equals(str) ? 200.0d : 100.0d);
    }

    static List<Long> amountsIn(String str) {
        ArrayList arrayList = new ArrayList();
        if (str == null) {
            return arrayList;
        }
        Matcher matcher = MONEY.matcher(str);
        while (matcher.find()) {
            if (matcher.group(1) != null || matcher.group(3) != null) {
                long cents = cents(matcher.group(2) + (matcher.group(3) == null ? "" : matcher.group(3)));
                if (cents > 0) {
                    arrayList.add(Long.valueOf(cents));
                }
            }
        }
        return arrayList;
    }

    static double points(long j, String str, double d) {
        if (j <= 0 || d <= 0.0d) {
            return 0.0d;
        }
        return Math.floor(((usd(j, str) * d) * 1000.0d) + 1.0E-6d) / 1000.0d;
    }

    static double shared(double d, int i) {
        if (d <= 0.0d) {
            return 0.0d;
        }
        return Math.floor((d * 1000.0d) / Math.max(1, i)) / 1000.0d;
    }

    static String pts(double d) {
        if (d == Math.floor(d)) {
            return String.valueOf((long) d);
        }
        return String.format(Locale.US, d < 10.0d ? "%.2f" : "%.1f", Double.valueOf(d)).replaceAll("0+$", "").replaceAll("\\.$", "");
    }

    static final class Note {
        long at;
        String key;
        String pkg;
        String src;
        String text;
        String title;

        Note(String str, long j, String str2, String str3, String str4, String str5) {
            this.src = str;
            this.at = j;
            this.pkg = str2;
            this.title = str3;
            this.text = str4;
            this.key = str5;
        }
    }

    static Note match(List<Note> list, String str, long j, long j2, long j3, Set<String> set) {
        Note note = null;
        if (str != null && !str.isEmpty() && j > 0) {
            for (Note note2 : list) {
                if (str.equals(note2.pkg) && note2.at >= j2 && note2.at <= j3 && (set == null || !set.contains(note2.key))) {
                    if (amountsIn(note2.title + "\n" + note2.text).contains(Long.valueOf(j)) && (note == null || note2.at < note.at)) {
                        note = note2;
                    }
                }
            }
        }
        return note;
    }

    static byte[] build(int i, List<String[]> list, Signer signer, byte[] bArr) throws Exception {
        byte[][] sign = signer.sign("probe".getBytes(StandardCharsets.UTF_8));
        if (sign == null) {
            throw new Exception("this phone can't sign");
        }
        ArrayList arrayList = new ArrayList(list);
        arrayList.add(new String[]{"phone", "key", hex(sign[0])});
        arrayList.add(new String[]{"sig", "key_id", hex(sha(sign[0]))});
        byte[] trailerPrefix = trailerPrefix(i, arrayList, arrayList.size() + 1);
        byte[][] sign2 = signer.sign(message(i, trailerPrefix));
        if (sign2 == null || !Arrays.equals(sign2[0], sign[0])) {
            throw new Exception("signing failed");
        }
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        byteArrayOutputStream.write(trailerPrefix);
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        str(dataOutputStream, "sig");
        str(dataOutputStream, "value");
        str(dataOutputStream, hex(sign2[1]));
        dataOutputStream.flush();
        byte[] byteArray = byteArrayOutputStream.toByteArray();
        ByteArrayOutputStream byteArrayOutputStream2 = new ByteArrayOutputStream();
        byteArrayOutputStream2.write(bArr);
        byteArrayOutputStream2.write(byteArray);
        DataOutputStream dataOutputStream2 = new DataOutputStream(byteArrayOutputStream2);
        dataOutputStream2.writeLong(byteArray.length);
        dataOutputStream2.flush();
        return byteArrayOutputStream2.toByteArray();
    }

    static byte[] message(int i, byte[] bArr) throws Exception {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        byteArrayOutputStream.write(("ANA-PMSH1|" + i + "|").getBytes(StandardCharsets.US_ASCII));
        byteArrayOutputStream.write(sha(bArr));
        return byteArrayOutputStream.toByteArray();
    }

    static byte[] trailerPrefix(int i, List<String[]> list, int i2) throws Exception {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        DataOutputStream dataOutputStream = new DataOutputStream(byteArrayOutputStream);
        dataOutputStream.write("PMSH".getBytes(StandardCharsets.US_ASCII));
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(1);
        dataOutputStream.writeInt(i);
        dataOutputStream.writeInt(3);
        str(dataOutputStream, "section");
        str(dataOutputStream, "key");
        str(dataOutputStream, "value");
        dataOutputStream.writeInt(i2);
        for (String[] strArr : list) {
            for (String str : strArr) {
                str(dataOutputStream, str);
            }
        }
        dataOutputStream.flush();
        return byteArrayOutputStream.toByteArray();
    }

    private static void str(DataOutputStream dataOutputStream, String str) throws Exception {
        byte[] bytes = str.getBytes(StandardCharsets.UTF_8);
        dataOutputStream.writeInt(bytes.length);
        dataOutputStream.write(bytes);
    }

    static final class Signed {
        boolean ok;
        int cls = -1;
        final LinkedHashMap<String, String> kv = new LinkedHashMap<>();
        String keyId = "";
        String why = "";

        Signed() {
        }

        String get(String str) {
            String str2 = this.kv.get(str);
            return str2 == null ? "" : str2;
        }
    }

    static Signed read(byte[] bArr) {
        Signed signed = new Signed();
        if (bArr != null) {
            try {
            } catch (Exception e) {
                signed.why = e.getMessage() == null ? "unreadable" : e.getMessage();
                signed.ok = false;
            }
            if (bArr.length >= 20) {
                long j = 0;
                for (int i = 0; i < 8; i++) {
                    j = (j << 8) | (bArr[(bArr.length - 8) + i] & 255);
                }
                long length = (bArr.length - 8) - j;
                if (j < 12 || length < 0) {
                    throw new Exception("no trailer");
                }
                byte[] copyOfRange = Arrays.copyOfRange(bArr, (int) length, bArr.length - 8);
                if (copyOfRange[0] != 80 || copyOfRange[1] != 77 || copyOfRange[2] != 83 || copyOfRange[3] != 72) {
                    throw new Exception("not a pngmesh");
                }
                int[] iArr = {4};
                if (u32(copyOfRange, iArr) != 1 || u32(copyOfRange, iArr) != 1) {
                    throw new Exception("version");
                }
                signed.cls = u32(copyOfRange, iArr);
                if (signed.cls < CLS_BILL || signed.cls > CLS_CHAT) {
                    throw new Exception("not a bill file");
                }
                if (u32(copyOfRange, iArr) != 3 || !rs(copyOfRange, iArr).equals("section") || !rs(copyOfRange, iArr).equals("key") || !rs(copyOfRange, iArr).equals("value")) {
                    throw new Exception("columns");
                }
                int u32 = u32(copyOfRange, iArr);
                if (u32 < 4 || u32 > 1000) {
                    throw new Exception("rows");
                }
                String[][] strArr = new String[u32][];
                int i2 = 0;
                for (int i3 = 0; i3 < u32; i3++) {
                    if (i3 == u32 - 1) {
                        i2 = iArr[0];
                    }
                    strArr[i3] = new String[]{rs(copyOfRange, iArr), rs(copyOfRange, iArr), rs(copyOfRange, iArr)};
                }
                if (iArr[0] != copyOfRange.length) {
                    throw new Exception("extra bytes");
                }
                int i4 = u32 - 2;
                String[] strArr2 = strArr[i4];
                String[] strArr3 = strArr[u32 - 1];
                if (!strArr2[0].equals("sig") || !strArr2[1].equals("key_id") || !strArr3[0].equals("sig") || !strArr3[1].equals("value")) {
                    throw new Exception("sig rows");
                }
                if (!strArr2[2].matches("[0-9a-f]{64}") || !strArr3[2].matches("[0-9a-f]{128}")) {
                    throw new Exception("sig hex");
                }
                String str = signed.cls == CLS_BILL ? "bill" : signed.cls == CLS_HELP ? "help" : signed.cls == CLS_THANKS ? "thanks" : signed.cls == CLS_SCHED ? "sched" : signed.cls == CLS_PAID ? "paid" : signed.cls == CLS_CHAT ? "chat" : "journey";
                for (int i5 = 0; i5 < i4; i5++) {
                    if (!strArr[i5][0].equals(str) && !strArr[i5][0].equals("phone")) {
                        throw new Exception("section " + strArr[i5][0]);
                    }
                    String[] strArr4 = strArr[i5];
                    String str2 = strArr4[0] + "|" + strArr4[1];
                    if (signed.kv.containsKey(str2)) {
                        throw new Exception("duplicate " + str2);
                    }
                    signed.kv.put(str2, strArr[i5][2]);
                }
                byte[] unhex = unhex(signed.get("phone|key"));
                if (unhex == null || unhex.length != 65 || unhex[0] != 4) {
                    throw new Exception("phone key");
                }
                if (!hex(sha(unhex)).equals(strArr2[2])) {
                    throw new Exception("key id doesn't match the key");
                }
                if (!new AnaRule(1, "ana", new ArrayList(), new ArrayList()).verify(unhex, message(signed.cls, Arrays.copyOfRange(copyOfRange, 0, i2)), unhex(strArr3[2]))) {
                    throw new Exception("signature doesn't match: changed or not signed by that phone");
                }
                signed.keyId = strArr2[2];
                signed.ok = true;
                return signed;
            }
        }
        throw new Exception("too small");
    }

    static int classOf(byte[] bArr) {
        long j = 0;
        for (int i = 0; i < 8; i++) {
            try {
                j = (j << 8) | (bArr[(bArr.length - 8) + i] & 255);
            } catch (Exception unused) {
            }
        }
        int length = (int) ((bArr.length - 8) - j);
        if (bArr[length] == 80 && bArr[length + 1] == 77) {
            return (bArr[length + 15] & 255) | ((bArr[length + 12] & 255) << 24) | ((bArr[length + 13] & 255) << 16) | ((bArr[length + 14] & 255) << 8);
        }
        return -1;
    }

    private static int u32(byte[] bArr, int[] iArr) throws Exception {
        int i = iArr[0];
        if (i + 4 > bArr.length) {
            throw new Exception("short");
        }
        int i2 = (bArr[i + 3] & 255) | ((bArr[i] & 255) << 24) | ((bArr[i + 1] & 255) << 16) | ((bArr[i + 2] & 255) << 8);
        iArr[0] = i + 4;
        return i2;
    }

    private static String rs(byte[] bArr, int[] iArr) throws Exception {
        int u32 = u32(bArr, iArr);
        if (u32 >= 0 && u32 <= 65536) {
            int i = iArr[0];
            if (i + u32 <= bArr.length) {
                String str = new String(bArr, i, u32, StandardCharsets.UTF_8);
                iArr[0] = iArr[0] + u32;
                return str;
            }
        }
        throw new Exception("bad string");
    }

    static byte[] sha(byte[] bArr) throws Exception {
        return MessageDigest.getInstance("SHA-256").digest(bArr);
    }

    static String hex(byte[] bArr) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bArr) {
            sb.append(String.format("%02x", Integer.valueOf(b & 255)));
        }
        return sb.toString();
    }

    static byte[] unhex(String str) {
        if (str == null || str.length() % 2 != 0 || !str.matches("[0-9a-fA-F]*")) {
            return null;
        }
        int length = str.length() / 2;
        byte[] bArr = new byte[length];
        for (int i = 0; i < length; i++) {
            int i2 = i * 2;
            bArr[i] = (byte) Integer.parseInt(str.substring(i2, i2 + 2), 16);
        }
        return bArr;
    }

    static String newId() {
        byte[] bArr = new byte[6];
        new SecureRandom().nextBytes(bArr);
        return hex(bArr);
    }
}
