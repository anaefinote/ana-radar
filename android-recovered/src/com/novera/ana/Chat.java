package com.novera.ana;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.os.Build;
import android.widget.EditText;
import android.widget.Toast;
import com.novera.ana.BillCore;
import com.novera.ana.ChatNet;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONObject;

/* loaded from: classes.dex */
final class Chat {
    private static final int KEEP = 100;
    static final String PKG = "ana.chat";
    private static final String PREF = "chat_msgs";
    private static AlertDialog open;

    Chat() {
    }

    static final class Msg {
        long at;
        boolean mine;
        String name = "";
        String text = "";
        String route = "";
        String keyId = "";

        Msg() {
        }
    }

    static byte[] make(Context context, String str) throws Exception {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new String[]{"chat", "text", str});
        arrayList.add(new String[]{"chat", "name", myName(context)});
        arrayList.add(new String[]{"chat", "at", Long.toString(System.currentTimeMillis())});
        return BillCore.build(46, arrayList, new Bills$$ExternalSyntheticLambda1(), new byte[0]);
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public static synchronized String receive(Context context, byte[] bArr, String str) {
        synchronized (Chat.class) {
            BillCore.Signed read = BillCore.read(bArr);
            if (!read.ok) {
                return "Not a genuine CHATNOTE message (" + read.why + ")";
            }
            if (read.cls != 46) {
                return "Not a CHATNOTE message";
            }
            Msg msg = new Msg();
            msg.text = BillCore.clean500(read.get("chat|text"));
            msg.name = BillCore.clean(read.get("chat|name"));
            if (msg.name.isEmpty()) {
                msg.name = "Someone";
            }
            try {
                msg.at = Long.parseLong(read.get("chat|at"));
                msg.keyId = read.keyId;
                msg.route = str;
                msg.mine = read.keyId.equals(myKeyId());
                if (msg.mine) {
                    return "That's your own message";
                }
                for (Msg msg2 : all(context)) {
                    if (msg2.keyId.equals(msg.keyId) && msg2.at == msg.at) {
                        return "Already here";
                    }
                }
                keep(context, msg);
                return null;
            } catch (NumberFormatException unused) {
                return "No time in it";
            }
        }
    }

    static void sent(Context context, String str, String str2, long j) {
        Msg msg = new Msg();
        msg.text = str;
        msg.name = myName(context);
        msg.at = j;
        msg.route = str2;
        msg.mine = true;
        msg.keyId = myKeyId();
        keep(context, msg);
    }

    private static void keep(Context context, final Msg msg) {
        List<Msg> all = all(context);
        all.add(msg);
        while (all.size() > KEEP) {
            all.remove(0);
        }
        JSONArray jSONArray = new JSONArray();
        try {
            for (Msg msg2 : all) {
                jSONArray.put(new JSONObject().put("n", msg2.name).put("t", msg2.text).put("r", msg2.route).put("k", msg2.keyId).put("at", msg2.at).put("me", msg2.mine));
            }
        } catch (Exception unused) {
        }
        prefs(context).edit().putString(PREF, jSONArray.toString()).apply();
        String str = msg.mine ? "You" : msg.name;
        long j = msg.at;
        String str2 = str + " · " + msg.route + (msg.mine ? "" : " · verified");
        String str3 = msg.text;
        String substring = msg.keyId.length() >= 12 ? msg.keyId.substring(0, 12) : msg.keyId;
        AnaLog.append(context, "CHAT", j, PKG, str2, str3, "chat-" + substring + "-" + msg.at, 0L);
        MainActivity.poke();
        final MainActivity mainActivity = MainActivity.current;
        if (msg.mine || mainActivity == null) {
            return;
        }
        mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda4
            @Override // java.lang.Runnable
            public final void run() {
                Chat.lambda$keep$0(MainActivity.this, msg);
            }
        });
    }

    static /* synthetic */ void lambda$keep$0(MainActivity mainActivity, Msg msg) {
        Toast.makeText(mainActivity, "CHATNOTE from " + msg.name + ": " + msg.text, 1).show();
        AlertDialog alertDialog = open;
        if (alertDialog == null || !alertDialog.isShowing()) {
            return;
        }
        open.dismiss();
        show(mainActivity);
    }

    static List<Msg> all(Context context) {
        ArrayList arrayList = new ArrayList();
        try {
            JSONArray jSONArray = new JSONArray(prefs(context).getString(PREF, "[]"));
            for (int i = 0; i < jSONArray.length(); i++) {
                JSONObject jSONObject = jSONArray.getJSONObject(i);
                Msg msg = new Msg();
                msg.name = jSONObject.optString("n");
                msg.text = jSONObject.optString("t");
                msg.route = jSONObject.optString("r");
                msg.keyId = jSONObject.optString("k");
                msg.at = jSONObject.optLong("at");
                msg.mine = jSONObject.optBoolean("me");
                arrayList.add(msg);
            }
        } catch (Exception unused) {
        }
        return arrayList;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("ana", 0);
    }

    static String myName(Context context) {
        String string = prefs(context).getString("bill_name", "");
        if (!string.isEmpty()) {
            return string;
        }
        return "ANA on " + Build.MODEL;
    }

    static String myKeyId() {
        try {
            byte[][] signRaw = Flex.signRaw("probe".getBytes(StandardCharsets.UTF_8));
            if (signRaw == null) {
                return "";
            }
            return BillCore.hex(BillCore.sha(signRaw[0]));
        } catch (Exception unused) {
            return "";
        }
    }

    static String list(Context context) {
        StringBuilder sb = new StringBuilder();
        long currentTimeMillis = System.currentTimeMillis();
        for (Msg msg : all(context)) {
            if (sb.length() > 0) {
                sb.append('\n');
            }
            sb.append(msg.mine ? "1" : "0");
            sb.append('\t');
            sb.append(msg.name.replace('\t', ' ').replace('\n', ' '));
            sb.append('\t');
            sb.append(msg.keyId);
            sb.append('\t');
            sb.append(Math.max(0L, (currentTimeMillis - msg.at) / 1000));
            sb.append('\t');
            sb.append(msg.route);
            sb.append('\t');
            sb.append(msg.text.replace('\t', ' ').replace('\n', ' '));
        }
        return sb.toString();
    }

    static synchronized void clear(Context context, String str) {
        synchronized (Chat.class) {
            List<Msg> all = all(context);
            JSONArray jSONArray = new JSONArray();
            try {
                for (Msg msg : all) {
                    if (msg.mine || !msg.keyId.equals(str)) {
                        jSONArray.put(new JSONObject().put("n", msg.name).put("t", msg.text).put("r", msg.route).put("k", msg.keyId).put("at", msg.at).put("me", msg.mine));
                    }
                }
            } catch (Exception unused) {
            }
            prefs(context).edit().putString(PREF, jSONArray.toString()).apply();
        }
    }

    static void write(final MainActivity mainActivity) {
        final EditText editText = new EditText(mainActivity);
        editText.setHint("Type a message");
        editText.setMaxLines(4);
        new AlertDialog.Builder(mainActivity).setTitle("CHATNOTE").setView(editText).setPositiveButton("Send...", new DialogInterface.OnClickListener() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda8
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                Chat.lambda$write$1(editText, mainActivity, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$write$1(EditText editText, MainActivity mainActivity, DialogInterface dialogInterface, int i) {
        String trim = editText.getText().toString().trim();
        if (trim.isEmpty()) {
            return;
        }
        if (trim.length() > 500) {
            trim = trim.substring(0, 500);
        }
        pickRoute(mainActivity, trim);
    }

    static void show(final MainActivity mainActivity) {
        StringBuilder sb = new StringBuilder();
        SimpleDateFormat simpleDateFormat = new SimpleDateFormat("h:mm a", Locale.US);
        List<Msg> all = all(mainActivity);
        for (int max = Math.max(0, all.size() - 12); max < all.size(); max++) {
            Msg msg = all.get(max);
            sb.append(msg.mine ? "You" : msg.name + " ✓");
            sb.append("  · ");
            sb.append(simpleDateFormat.format(new Date(msg.at)));
            sb.append(" · ");
            sb.append(msg.route);
            sb.append("\n");
            sb.append(msg.text);
            sb.append("\n\n");
        }
        if (all.isEmpty()) {
            sb.append("No messages yet. Say hello.\n\n");
        }
        sb.append("Signed by this phone, so the other phone knows it's you. Not secret yet: whoever carries it could read it.");
        final EditText editText = new EditText(mainActivity);
        editText.setHint("Type a message");
        editText.setSingleLine(false);
        editText.setMaxLines(4);
        open = new AlertDialog.Builder(mainActivity).setTitle("CHATNOTE (experimental)").setMessage(sb.toString()).setView(editText).setPositiveButton("Send...", new DialogInterface.OnClickListener() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda2
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                Chat.lambda$show$2(editText, mainActivity, dialogInterface, i);
            }
        }).setNegativeButton("Close", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$show$2(EditText editText, MainActivity mainActivity, DialogInterface dialogInterface, int i) {
        String trim = editText.getText().toString().trim();
        if (trim.isEmpty()) {
            return;
        }
        if (trim.length() > 500) {
            trim = trim.substring(0, 500);
        }
        pickRoute(mainActivity, trim);
    }

    private static void pickRoute(final MainActivity mainActivity, final String str) {
        new AlertDialog.Builder(mainActivity).setTitle("Send by").setItems(new String[]{"Bluetooth (your paired iPhone)", "Wi-Fi (same network)", "Internet (Tailscale address)", "Light (QR code, experimental)"}, new DialogInterface.OnClickListener() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda6
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                Chat.lambda$pickRoute$3(MainActivity.this, str, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$pickRoute$3(MainActivity mainActivity, String str, DialogInterface dialogInterface, int i) {
        if (i == 0) {
            sendBluetooth(mainActivity, str);
            return;
        }
        if (i == 1) {
            pickWifi(mainActivity, str);
        } else if (i == 2) {
            askAddress(mainActivity, str);
        } else {
            Toast.makeText(mainActivity, "Light is coming next", 1).show();
        }
    }

    private static void pickWifi(final MainActivity mainActivity, final String str) {
        Toast.makeText(mainActivity, "Looking for ANA on this Wi-Fi...", 0).show();
        ChatNet.find(mainActivity, new ChatNet.Found() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda3
            @Override // com.novera.ana.ChatNet.Found
            public final void found(List list) {
                Chat.lambda$pickWifi$5(MainActivity.this, str, list);
            }
        });
    }

    static /* synthetic */ void lambda$pickWifi$5(final MainActivity mainActivity, final String str, final List list) {
        if (list.isEmpty()) {
            new AlertDialog.Builder(mainActivity).setTitle("No ANA found on this Wi-Fi").setMessage("Open ANA on the other phone, on the same Wi-Fi, and try again. Or send by Internet with its address.").setPositiveButton("OK", (DialogInterface.OnClickListener) null).show();
            return;
        }
        int size = list.size();
        String[] strArr = new String[size];
        for (int i = 0; i < size; i++) {
            strArr[i] = ((ChatNet.Peer) list.get(i)).name + "  (" + ((ChatNet.Peer) list.get(i)).host + ")";
        }
        new AlertDialog.Builder(mainActivity).setTitle("Send to").setItems(strArr, new DialogInterface.OnClickListener() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda1
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                Chat.sendNet(MainActivity.this, str, ((ChatNet.Peer) r2.get(i2)).host, ((ChatNet.Peer) list.get(i2)).port, "Wi-Fi");
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    private static void askAddress(final MainActivity mainActivity, final String str) {
        final EditText editText = new EditText(mainActivity);
        editText.setHint("100.x.y.z (its Tailscale address)");
        editText.setSingleLine(true);
        editText.setText(prefs(mainActivity).getString("chat_addr", ""));
        new AlertDialog.Builder(mainActivity).setTitle("Send over the Internet").setMessage("Type the other phone's address. With Tailscale on both phones, it's the 100.x.y.z address Tailscale shows for it.").setView(editText).setPositiveButton("Send", new DialogInterface.OnClickListener() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda5
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                Chat.lambda$askAddress$6(editText, mainActivity, str, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    static /* synthetic */ void lambda$askAddress$6(EditText editText, MainActivity mainActivity, String str, DialogInterface dialogInterface, int i) {
        String trim = editText.getText().toString().trim();
        if (trim.isEmpty()) {
            return;
        }
        prefs(mainActivity).edit().putString("chat_addr", trim).apply();
        sendNet(mainActivity, str, trim, 47474, "Internet");
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static void sendNet(final MainActivity mainActivity, final String str, final String str2, final int i, final String str3) {
        new Thread(new Runnable() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda0
            @Override // java.lang.Runnable
            public final void run() {
                Chat.lambda$sendNet$8(MainActivity.this, str, str2, i, str3);
            }
        }).start();
    }

    static /* synthetic */ void lambda$sendNet$8(final MainActivity mainActivity, final String str, String str2, int i, final String str3) {
        String message;
        long j = 0;
        try {
            byte[] make = make(mainActivity, str);
            j = Long.parseLong(BillCore.read(make).get("chat|at"));
            message = ChatNet.send(str2, i, make);
        } catch (Exception e) {
            message = e.getMessage();
        }
        final String str4 = message;
        final long j2 = j;
        mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.Chat$$ExternalSyntheticLambda7
            @Override // java.lang.Runnable
            public final void run() {
                Chat.lambda$sendNet$7(str4, mainActivity, str, str3, j2);
            }
        });
    }

    static /* synthetic */ void lambda$sendNet$7(String str, MainActivity mainActivity, String str2, String str3, long j) {
        if (str != null) {
            Toast.makeText(mainActivity, "Not sent: " + str, 1).show();
        } else {
            sent(mainActivity, str2, str3, j);
            Toast.makeText(mainActivity, "Sent over " + str3, 0).show();
        }
    }

    private static void sendBluetooth(MainActivity mainActivity, String str) {
        try {
            byte[] make = make(mainActivity, str);
            long parseLong = Long.parseLong(BillCore.read(make).get("chat|at"));
            if (!AncsLink.sendChat(make)) {
                Toast.makeText(mainActivity, "No iPhone linked: turn on iPhone notifications and connect the iPhone first", 1).show();
            } else {
                sent(mainActivity, str, "Bluetooth", parseLong);
                Toast.makeText(mainActivity, "Sent to your iPhone over Bluetooth", 0).show();
            }
        } catch (Exception e) {
            Toast.makeText(mainActivity, "Couldn't send: " + e.getMessage(), 1).show();
        }
    }
}
