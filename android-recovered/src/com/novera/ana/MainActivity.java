package com.novera.ana;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.AppOpsManager;
import android.app.KeyguardManager;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.Drawable;
import android.hardware.biometrics.BiometricPrompt;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.Parcelable;
import android.os.Process;
import android.provider.Settings;
import android.service.notification.NotificationListenerService;
import android.text.TextUtils;
import android.util.Base64;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.DatePicker;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.NumberPicker;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.TimePicker;
import android.widget.Toast;
import com.novera.ana.Lessons;
import com.novera.ana.MainActivity;
import com.novera.ana.Wallets;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Consumer;
import org.json.JSONObject;

/* loaded from: classes.dex */
public class MainActivity extends Activity {
    static final boolean EXPERIMENTAL_LESSONS = false;
    static final int REQ_BT = 42;
    static final int REQ_IMPORT = 41;
    static final int REQ_SUBWATCH = 42;
    static volatile MainActivity current;
    private Consumer<Integer> recWatch;
    private boolean revealing;
    private WebView web;
    private static final int BG = Color.rgb(5, 7, 12);
    private static final Map<String, Object[]> waitingMesh = new HashMap();
    private static final Set<String> waitingSidecar = new HashSet();
    static final List<String> gstInbox = new ArrayList();
    static final Map<String, String> gstAnswers = new HashMap();
    private boolean pageReady = EXPERIMENTAL_LESSONS;
    private int delivered = BG;
    private final Handler watchTimer = new Handler(Looper.getMainLooper());
    private final Runnable watchTick = new Runnable() { // from class: com.novera.ana.MainActivity.1
        @Override // java.lang.Runnable
        public void run() {
            Wallets.refreshAll(MainActivity.this);
            MainActivity.this.watchTimer.postDelayed(this, 120000L);
        }
    };
    private Map<String, Long> lastUsedMap = new HashMap();
    private long lastUsedAt = 0;

    @Override // android.app.Activity
    protected void onCreate(Bundle bundle) {
        super.onCreate(bundle);
        WebView webView = new WebView(this);
        this.web = webView;
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        this.web.setWebChromeClient(new WebChromeClient());
        this.web.addJavascriptInterface(new Bridge(), "AndroidANA");
        this.web.setBackgroundColor(BG);
        try {
            AnaLog.prune(this, Integer.parseInt(getSharedPreferences("ana", BG).getString("p_retention", "0")));
        } catch (NumberFormatException unused) {
        }
        setContentView(insetHost(this.web));
        this.web.loadUrl("file:///android_asset/index.html");
        handleIncoming(getIntent());
        if ("1".equals(getSharedPreferences("ana", BG).getString("p_iphone", "")) && btAllowed()) {
            AncsLink.start(this);
        }
        Wallets.load(this);
        Lessons.load(this);
        final Context applicationContext = getApplicationContext();
        Wallets.proofListener = new Wallets.ProofListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda8
            @Override // com.novera.ana.Wallets.ProofListener
            public final void onProof(Wallets.Wallet wallet) {
                MainActivity.lambda$onCreate$0(applicationContext, wallet);
            }
        };
        Wallets.listener = new Wallets.Listener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda9
            @Override // com.novera.ana.Wallets.Listener
            public final void onNews(Wallets.Wallet wallet, List list) {
                MainActivity.lambda$onCreate$1(applicationContext, wallet, list);
            }
        };
    }

    static /* synthetic */ void lambda$onCreate$0(Context context, Wallets.Wallet wallet) {
        String str;
        String save = Witness.save(context, wallet);
        long currentTimeMillis = System.currentTimeMillis();
        String str2 = wallet.name;
        String str3 = wallet.proofNote;
        if (save == null) {
            str = "";
        } else {
            str = "  ·  Signed witness: " + save;
        }
        AnaLog.append(context, "WATCH", currentTimeMillis, "ana.watch", str2, "Ownership proven. " + str3 + str, "proof-" + wallet.proofTx, 0L);
        MainActivity mainActivity = current;
        if (mainActivity != null) {
            Objects.requireNonNull(mainActivity);
            mainActivity.runOnUiThread(new MainActivity$$ExternalSyntheticLambda4(mainActivity));
            mainActivity.toast(wallet.name + ": ownership proven");
        }
    }

    static /* synthetic */ void lambda$onCreate$1(Context context, Wallets.Wallet wallet, List list) {
        String str;
        Iterator it = list.iterator();
        while (true) {
            str = "-";
            if (!it.hasNext()) {
                break;
            }
            Wallets.Act act = (Wallets.Act) it.next();
            if (act.kind.equals("in")) {
                str = "+";
            } else if (!act.kind.equals("out")) {
                str = "";
            }
            AnaLog.append(context, "WATCH", (long) (act.t * 1000.0d), "ana.watch", wallet.name, str + Wallets.actAmount(act) + "  " + act.label, "watch-" + act.id, 0L);
        }
        MainActivity mainActivity = current;
        if (mainActivity == null || list.isEmpty()) {
            return;
        }
        Wallets.Act act2 = (Wallets.Act) list.get(list.size() - 1);
        if (act2.kind.equals("in")) {
            str = "+";
        } else if (!act2.kind.equals("out")) {
            str = "";
        }
        Objects.requireNonNull(mainActivity);
        mainActivity.runOnUiThread(new MainActivity$$ExternalSyntheticLambda4(mainActivity));
        mainActivity.toast(wallet.name + ": " + str + Wallets.actAmount(act2) + " " + act2.label.toLowerCase(Locale.US));
    }

    boolean btAllowed() {
        if (Build.VERSION.SDK_INT < 31) {
            return true;
        }
        if (checkSelfPermission("android.permission.BLUETOOTH_ADVERTISE") == 0 && checkSelfPermission("android.permission.BLUETOOTH_CONNECT") == 0) {
            return true;
        }
        return EXPERIMENTAL_LESSONS;
    }

    void iphoneOn(boolean z) {
        getSharedPreferences("ana", BG).edit().putString("p_iphone", z ? "1" : "0").apply();
        if (!z) {
            AncsLink.stop(this);
            return;
        }
        if (btAllowed()) {
            AncsLink.start(this);
            return;
        }
        ArrayList arrayList = new ArrayList();
        arrayList.add("android.permission.BLUETOOTH_ADVERTISE");
        arrayList.add("android.permission.BLUETOOTH_CONNECT");
        if (Build.VERSION.SDK_INT >= 33) {
            arrayList.add("android.permission.POST_NOTIFICATIONS");
        }
        AncsLink.state = "Allow Bluetooth for ANA";
        requestPermissions((String[]) arrayList.toArray(new String[BG]), 42);
    }

    @Override // android.app.Activity
    public void onRequestPermissionsResult(int i, String[] strArr, int[] iArr) {
        super.onRequestPermissionsResult(i, strArr, iArr);
        if (i != 42) {
            return;
        }
        if (btAllowed()) {
            AncsLink.start(this);
        } else {
            AncsLink.state = "Bluetooth not allowed: switch this on again to allow it";
        }
    }

    @Override // android.app.Activity
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIncoming(intent);
    }

    @Override // android.app.Activity
    protected void onResume() {
        super.onResume();
        current = this;
        ChatNet.start(this);
        if (AnaListener.instance == null && accessEnabled()) {
            NotificationListenerService.requestRebind(new ComponentName(this, (Class<?>) AnaListener.class));
        }
        deliverPending();
        this.watchTimer.removeCallbacks(this.watchTick);
        this.watchTimer.post(this.watchTick);
    }

    @Override // android.app.Activity
    protected void onStart() {
        super.onStart();
        if (Build.VERSION.SDK_INT >= 35) {
            try {
                Consumer<Integer> consumer = new Consumer() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda24
                    @Override // java.util.function.Consumer
                    public final void accept(Object obj) {
                        MainActivity.lambda$onStart$2((Integer) obj);
                    }
                };
                this.recWatch = consumer;
                consumer.accept(Integer.valueOf(getWindowManager().addScreenRecordingCallback(getMainExecutor(), this.recWatch)));
            } catch (Exception unused) {
                this.recWatch = null;
            }
        }
    }

    static /* synthetic */ void lambda$onStart$2(Integer num) {
        Wallets.capturing = num.intValue() != 1 ? BG : true;
        if (Wallets.capturing) {
            Wallets.back = EXPERIMENTAL_LESSONS;
        }
    }

    @Override // android.app.Activity
    protected void onStop() {
        if (Build.VERSION.SDK_INT >= 35 && this.recWatch != null) {
            try {
                getWindowManager().removeScreenRecordingCallback(this.recWatch);
            } catch (Exception unused) {
            }
            this.recWatch = null;
        }
        super.onStop();
    }

    @Override // android.app.Activity
    protected void onPause() {
        if (!this.revealing) {
            Wallets.back = EXPERIMENTAL_LESSONS;
        }
        this.watchTimer.removeCallbacks(this.watchTick);
        current = null;
        ChatNet.stop();
        super.onPause();
    }

    private FrameLayout insetHost(WebView webView) {
        FrameLayout frameLayout = new FrameLayout(this);
        int i = BG;
        frameLayout.setBackgroundColor(i);
        frameLayout.addView(webView, new FrameLayout.LayoutParams(-1, -1));
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(EXPERIMENTAL_LESSONS);
            getWindow().setStatusBarColor(BG);
            getWindow().setNavigationBarColor(BG);
            frameLayout.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda14
                @Override // android.view.View.OnApplyWindowInsetsListener
                public final WindowInsets onApplyWindowInsets(View view, WindowInsets windowInsets) {
                    return MainActivity.lambda$insetHost$3(view, windowInsets);
                }
            });
        } else {
            getWindow().setStatusBarColor(i);
            getWindow().setNavigationBarColor(i);
        }
        return frameLayout;
    }

    static /* synthetic */ WindowInsets lambda$insetHost$3(View view, WindowInsets windowInsets) {
        Insets insets = windowInsets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
        view.setPadding(insets.left, insets.top, insets.right, insets.bottom);
        return WindowInsets.CONSUMED;
    }

    static void poke() {
        MainActivity mainActivity = current;
        if (mainActivity != null) {
            Objects.requireNonNull(mainActivity);
            mainActivity.runOnUiThread(new MainActivity$$ExternalSyntheticLambda4(mainActivity));
        }
    }

    void deliverPending() {
        if (this.pageReady) {
            List<String> readAll = AnaLog.readAll(this);
            if (this.delivered >= readAll.size()) {
                return;
            }
            StringBuilder sb = new StringBuilder();
            for (int i = this.delivered; i < readAll.size(); i++) {
                String[] split = readAll.get(i).split("\t", -1);
                if (split.length >= 8) {
                    sb.append("anaDeliver(");
                    sb.append(q(split[BG]));
                    sb.append(',');
                    sb.append(q(split[1]));
                    sb.append(',');
                    sb.append(q(split[3]));
                    sb.append(',');
                    sb.append(q(split[4]));
                    sb.append(',');
                    sb.append(q(split[5]));
                    sb.append(',');
                    sb.append(q(split[6]));
                    sb.append(',');
                    sb.append(q(split[7]));
                    sb.append(',');
                    sb.append(i);
                    sb.append(',');
                    sb.append(q(evWhen(split.length > 8 ? split[8] : "")));
                    sb.append(");\n");
                }
            }
            this.delivered = readAll.size();
            this.web.evaluateJavascript(sb.toString(), null);
        }
    }

    static String evWhen(String str) {
        try {
            long parseLong = Long.parseLong(str);
            if (parseLong <= 0) {
                return "";
            }
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date(parseLong));
        } catch (NumberFormatException unused) {
            return "";
        }
    }

    private static String q(String str) {
        return JSONObject.quote(str);
    }

    boolean accessEnabled() {
        String string = Settings.Secure.getString(getContentResolver(), "enabled_notification_listeners");
        if (string == null || !string.contains(getPackageName())) {
            return EXPERIMENTAL_LESSONS;
        }
        return true;
    }

    String status() {
        return AnaListener.instance != null ? "CONNECTED" : accessEnabled() ? "ENABLED - WAITING TO BIND" : "NO ACCESS - tap ACCESS";
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    /* renamed from: showLessonImport, reason: merged with bridge method [inline-methods] */
    public void lambda$importUris$19(final byte[] bArr, final byte[] bArr2) {
        String[] preview = Lessons.preview(this, bArr, bArr2);
        if (!preview[BG].equals("ACCEPT")) {
            toast("Lesson: " + preview[1]);
            return;
        }
        if (preview[2].isEmpty()) {
            toast("Root chain: " + Lessons.add(this, bArr, bArr2));
            return;
        }
        new AlertDialog.Builder(this).setTitle("Add a lesson  (TEST build)").setMessage(preview[2] + "\n\nThis build trusts TEST keys only. Never share it.").setPositiveButton("Add", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda1
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showLessonImport$4(bArr, bArr2, dialogInterface, i);
            }
        }).setNegativeButton("Not now", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showLessonImport$4(byte[] bArr, byte[] bArr2, DialogInterface dialogInterface, int i) {
        toast(Lessons.add(this, bArr, bArr2));
        poke();
    }

    void showLessons() {
        final ArrayList arrayList = new ArrayList(Lessons.list);
        String[] strArr = new String[arrayList.size() + 1];
        for (int i = BG; i < arrayList.size(); i++) {
            Lessons.Lesson lesson = (Lessons.Lesson) arrayList.get(i);
            strArr[i] = lesson.name() + " (" + lesson.ticker() + ")   version " + lesson.version;
        }
        strArr[arrayList.size()] = "Import a lesson...";
        new AlertDialog.Builder(this).setTitle("Lessons  ·  TEST keys").setItems(strArr, new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda13
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                MainActivity.this.lambda$showLessons$6(arrayList, dialogInterface, i2);
            }
        }).setNegativeButton("Close", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showLessons$6(List list, DialogInterface dialogInterface, int i) {
        String str;
        if (i == list.size()) {
            pickFiles();
            return;
        }
        final Lessons.Lesson lesson = (Lessons.Lesson) list.get(i);
        AlertDialog.Builder title = new AlertDialog.Builder(this).setTitle(lesson.name() + " (" + lesson.ticker() + ")");
        String replace = Lessons.confirmText(lesson.kv).replace("Add ", "Learned ").replace("?  ANA will send", ".  ANA sends");
        String str2 = lesson.id;
        int i2 = lesson.version;
        String substring = lesson.keyId.substring(BG, 16);
        if (Lessons.problems.isEmpty()) {
            str = "";
        } else {
            str = "\n\nNot in use:\n" + Lessons.problems;
        }
        title.setMessage(replace + "\n\nLesson " + str2 + ", version " + i2 + "\nSigned by key " + substring + str).setPositiveButton("Remove", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda2
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface2, int i3) {
                MainActivity.this.lambda$showLessons$5(lesson, dialogInterface2, i3);
            }
        }).setNegativeButton("Close", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showLessons$5(Lessons.Lesson lesson, DialogInterface dialogInterface, int i) {
        Lessons.remove(this, lesson.id);
        toast("Removed " + lesson.name());
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$toast$7(String str) {
        Toast.makeText(this, str, BG).show();
    }

    /* JADX INFO: Access modifiers changed from: package-private */
    public void toast(final String str) {
        runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda21
            @Override // java.lang.Runnable
            public final void run() {
                MainActivity.this.lambda$toast$7(str);
            }
        });
    }

    String readSketch() {
        StringBuilder sb = new StringBuilder();
        try {
            String[] list = getAssets().list("");
            ArrayList arrayList = new ArrayList();
            if (list != null) {
                int length = list.length;
                for (int i = BG; i < length; i++) {
                    String str = list[i];
                    if (str.endsWith(".pde") && !str.equals("ANA_PoC.pde")) {
                        arrayList.add(str);
                    }
                }
            }
            Collections.sort(arrayList);
            arrayList.add(BG, "ANA_PoC.pde");
            Iterator it = arrayList.iterator();
            while (it.hasNext()) {
                sb.append(readAsset((String) it.next()));
                sb.append('\n');
            }
        } catch (IOException e) {
            toast("Could not load sketch: " + e.getMessage());
        }
        return sb.toString();
    }

    private String readAsset(String str) throws IOException {
        InputStream open = getAssets().open(str);
        try {
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            byte[] bArr = new byte[8192];
            while (true) {
                int read = open.read(bArr);
                if (read <= 0) {
                    break;
                }
                byteArrayOutputStream.write(bArr, BG, read);
            }
            String str2 = new String(byteArrayOutputStream.toByteArray(), StandardCharsets.UTF_8);
            if (open != null) {
                open.close();
            }
            return str2;
        } catch (Throwable th) {
            if (open != null) {
                try {
                    open.close();
                } catch (Throwable th2) {
                    th.addSuppressed(th2);
                }
            }
            throw th;
        }
    }

    void showManualDialog() {
        LinearLayout linearLayout = new LinearLayout(this);
        linearLayout.setOrientation(1);
        linearLayout.setPadding(48, 16, 48, BG);
        final EditText editText = new EditText(this);
        editText.setHint("Amount (e.g. 12.50)");
        editText.setInputType(8194);
        final EditText editText2 = new EditText(this);
        editText2.setHint("Merchant");
        linearLayout.addView(editText);
        linearLayout.addView(editText2);
        new AlertDialog.Builder(this).setTitle("Manual entry").setView(linearLayout).setPositiveButton("Save", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda15
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showManualDialog$8(editText2, editText, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showManualDialog$8(EditText editText, EditText editText2, DialogInterface dialogInterface, int i) {
        long currentTimeMillis = System.currentTimeMillis();
        AnaLog.append(this, "MANUAL", currentTimeMillis, "manual", editText.getText().toString(), "Amount: " + editText2.getText().toString(), "manual-" + currentTimeMillis, 0L);
        deliverPending();
    }

    void revealSubWatch() {
        if (Wallets.capturing) {
            toast("Sub-watch stays shut while the screen is shared or recorded");
            return;
        }
        WebView webView = this.web;
        if (webView != null) {
            webView.performHapticFeedback(BG);
        }
        KeyguardManager keyguardManager = (KeyguardManager) getSystemService("keyguard");
        if (keyguardManager == null || !keyguardManager.isDeviceSecure()) {
            Wallets.back = true;
            toast("Set a screen lock and sub-watch will ask for your fingerprint or PIN");
            return;
        }
        this.revealing = true;
        try {
            if (Build.VERSION.SDK_INT >= 28) {
                BiometricPrompt.Builder subtitle = new BiometricPrompt.Builder(this).setTitle("Sub-watch").setSubtitle("Only you can open it");
                if (Build.VERSION.SDK_INT >= 30) {
                    subtitle.setAllowedAuthenticators(33023);
                } else if (Build.VERSION.SDK_INT >= 29) {
                    subtitle.setDeviceCredentialAllowed(true);
                } else {
                    subtitle.setNegativeButton("Cancel", getMainExecutor(), new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda5
                        @Override // android.content.DialogInterface.OnClickListener
                        public final void onClick(DialogInterface dialogInterface, int i) {
                            MainActivity.this.lambda$revealSubWatch$9(dialogInterface, i);
                        }
                    });
                }
                subtitle.build().authenticate(new CancellationSignal(), getMainExecutor(), new BiometricPrompt.AuthenticationCallback() { // from class: com.novera.ana.MainActivity.2
                    @Override // android.hardware.biometrics.BiometricPrompt.AuthenticationCallback
                    public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult authenticationResult) {
                        MainActivity.this.revealing = MainActivity.EXPERIMENTAL_LESSONS;
                        if (Wallets.capturing) {
                            return;
                        }
                        Wallets.back = true;
                    }

                    @Override // android.hardware.biometrics.BiometricPrompt.AuthenticationCallback
                    public void onAuthenticationError(int i, CharSequence charSequence) {
                        MainActivity.this.revealing = MainActivity.EXPERIMENTAL_LESSONS;
                    }
                });
                return;
            }
            Intent createConfirmDeviceCredentialIntent = keyguardManager.createConfirmDeviceCredentialIntent("Sub-watch", "Only you can open it");
            if (createConfirmDeviceCredentialIntent == null) {
                this.revealing = EXPERIMENTAL_LESSONS;
                Wallets.back = true;
            } else {
                startActivityForResult(createConfirmDeviceCredentialIntent, 42);
            }
        } catch (Exception e) {
            this.revealing = EXPERIMENTAL_LESSONS;
            toast("Couldn't ask for your fingerprint: " + e.getMessage());
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$revealSubWatch$9(DialogInterface dialogInterface, int i) {
        this.revealing = EXPERIMENTAL_LESSONS;
    }

    void showHideMenu(final String str) {
        new AlertDialog.Builder(this).setTitle("Hide it from the front").setItems(new String[]{"For 1 hour", "For 8 hours", "For 1 day", "For a time I choose...", "Until I bring it back"}, new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda7
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showHideMenu$10(str, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showHideMenu$10(String str, DialogInterface dialogInterface, int i) {
        if (i == 0) {
            Wallets.hide(this, str, 3600.0d);
            return;
        }
        if (i == 1) {
            Wallets.hide(this, str, 28800.0d);
            return;
        }
        if (i == 2) {
            Wallets.hide(this, str, 86400.0d);
        } else if (i == 3) {
            showHideCustom(str);
        } else {
            Wallets.hide(this, str, 0.0d);
        }
    }

    void showHideCustom(final String str) {
        LinearLayout linearLayout = new LinearLayout(this);
        linearLayout.setOrientation(BG);
        linearLayout.setGravity(17);
        linearLayout.setPadding(24, 24, 24, BG);
        final NumberPicker[] numberPickerArr = new NumberPicker[3];
        String[] strArr = {"days", "hours", "minutes"};
        int[] iArr = {30, 23, 59};
        int[] iArr2 = {BG, 2, BG};
        for (int i = BG; i < 3; i++) {
            LinearLayout linearLayout2 = new LinearLayout(this);
            linearLayout2.setOrientation(1);
            linearLayout2.setGravity(17);
            linearLayout2.setPadding(18, BG, 18, BG);
            NumberPicker numberPicker = new NumberPicker(this);
            numberPickerArr[i] = numberPicker;
            numberPicker.setMinValue(BG);
            numberPickerArr[i].setMaxValue(iArr[i]);
            numberPickerArr[i].setValue(iArr2[i]);
            TextView textView = new TextView(this);
            textView.setText(strArr[i]);
            textView.setGravity(17);
            linearLayout2.addView(numberPickerArr[i]);
            linearLayout2.addView(textView);
            linearLayout.addView(linearLayout2);
        }
        new AlertDialog.Builder(this).setTitle("Hide it for").setView(linearLayout).setPositiveButton("Hide", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda20
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                MainActivity.this.lambda$showHideCustom$11(numberPickerArr, str, dialogInterface, i2);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showHideCustom$11(NumberPicker[] numberPickerArr, String str, DialogInterface dialogInterface, int i) {
        double value = (numberPickerArr[BG].getValue() * 86400.0d) + (numberPickerArr[1].getValue() * 3600.0d) + (numberPickerArr[2].getValue() * 60.0d);
        if (value < 60.0d) {
            toast("Pick at least a minute");
        } else {
            Wallets.hide(this, str, value);
        }
    }

    void showWalletAdd() {
        CharSequence text;
        final boolean z = Wallets.back;
        LinearLayout linearLayout = new LinearLayout(this);
        linearLayout.setOrientation(1);
        linearLayout.setPadding(48, 16, 48, BG);
        final EditText editText = new EditText(this);
        editText.setHint("Name (e.g. ether.fi Cash, Jupiter)");
        final EditText editText2 = new EditText(this);
        editText2.setHint("Address");
        editText2.setInputType(524289);
        try {
            ClipboardManager clipboardManager = (ClipboardManager) getSystemService("clipboard");
            if (clipboardManager != null && clipboardManager.hasPrimaryClip() && clipboardManager.getPrimaryClip().getItemCount() > 0 && (text = clipboardManager.getPrimaryClip().getItemAt(BG).getText()) != null && Wallets.kindOf(text.toString()) != null) {
                editText2.setText(text.toString().trim());
            }
        } catch (Exception unused) {
        }
        linearLayout.addView(editText);
        linearLayout.addView(editText2);
        new AlertDialog.Builder(this).setTitle(z ? "Add to sub-watch" : "Watch an address").setMessage("A public address only: an ether.fi Safe (0x..., on Optimism), a Solana wallet, a TRON wallet (T...) or a Litecoin or Bitcoin wallet you hold yourself (ltc1... / bc1...). ANA never needs keys or recovery words.").setView(linearLayout).setPositiveButton("Watch", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda16
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showWalletAdd$12(editText, editText2, z, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showWalletAdd$12(EditText editText, EditText editText2, boolean z, DialogInterface dialogInterface, int i) {
        String add = Wallets.add(this, editText.getText().toString(), editText2.getText().toString(), z);
        if (add == null) {
            add = z ? "In sub-watch, hidden from the front: checking now" : "Watching it: checking now";
        }
        toast(add);
    }

    void showWalletEdit(final String str) {
        final String[] strArr;
        final Wallets.Wallet find = Wallets.find(str);
        if (find == null) {
            return;
        }
        boolean z = Wallets.back;
        boolean z2 = (Wallets.offFront(find) && find.hidden) ? true : BG;
        String str2 = "Hide it from the front...";
        if (z) {
            if (z2) {
                str2 = "Bring it to the front";
            }
            strArr = new String[]{str2, "Hide while the screen is shared: ".concat(find.shareHide ? "ON" : "OFF"), "Rename", "Copy the address", "Check now", "Stop watching"};
        } else {
            strArr = new String[]{"Rename", "Copy the address", "Check now", "Hide it from the front...", "Stop watching"};
        }
        if ("proven".equals(find.proof) && find.proofDetail.length() > 0) {
            String[] strArr2 = new String[strArr.length + 1];
            strArr2[BG] = "Ownership: Proven (details)";
            System.arraycopy(strArr, BG, strArr2, 1, strArr.length);
            strArr = strArr2;
        }
        new AlertDialog.Builder(this).setTitle(find.name + "\n" + find.addr).setItems(strArr, new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda23
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showWalletEdit$14(strArr, find, str, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showWalletEdit$14(String[] strArr, Wallets.Wallet wallet, final String str, DialogInterface dialogInterface, int i) {
        String str2 = strArr[i];
        if (str2.startsWith("Ownership:")) {
            showProof(wallet);
            return;
        }
        if (str2.equals("Bring it to the front")) {
            Wallets.hide(this, str, -1.0d);
            return;
        }
        if (str2.startsWith("Hide it from")) {
            showHideMenu(str);
            return;
        }
        if (str2.startsWith("Hide while")) {
            Wallets.shareHide(this, str, !wallet.shareHide);
            return;
        }
        char c = str2.equals("Rename") ? (char) 0 : str2.startsWith("Copy") ? (char) 1 : str2.equals("Check now") ? (char) 2 : (char) 3;
        if (c == 0) {
            final EditText editText = new EditText(this);
            editText.setText(wallet.name);
            new AlertDialog.Builder(this).setTitle("Rename").setView(editText).setPositiveButton("Save", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda0
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface2, int i2) {
                    MainActivity.this.lambda$showWalletEdit$13(str, editText, dialogInterface2, i2);
                }
            }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
        } else {
            if (c == 1) {
                ClipboardManager clipboardManager = (ClipboardManager) getSystemService("clipboard");
                if (clipboardManager != null) {
                    clipboardManager.setPrimaryClip(ClipData.newPlainText("address", wallet.addr));
                }
                toast("Address copied");
                return;
            }
            if (c == 2) {
                Wallets.refreshAll(this);
            } else {
                Wallets.remove(this, str);
            }
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showWalletEdit$13(String str, EditText editText, DialogInterface dialogInterface, int i) {
        Wallets.rename(this, str, editText.getText().toString());
    }

    void showProof(Wallets.Wallet wallet) {
        String str;
        String str2;
        JSONObject jSONObject = wallet.proofDetail;
        boolean equals = "in".equals(jSONObject.optString("direction"));
        long optLong = jSONObject.optLong("block_time");
        long optLong2 = jSONObject.optLong("notified_ms") / 1000;
        long j = optLong2 - optLong;
        String optString = jSONObject.optString("app");
        String optString2 = jSONObject.optString("via");
        String optString3 = jSONObject.optString("party");
        StringBuilder sb = new StringBuilder();
        sb.append(equals ? "Received " : "Sent ");
        sb.append(jSONObject.optString("amount"));
        sb.append(' ');
        sb.append(jSONObject.optString("coin"));
        sb.append("\n(exactly ");
        sb.append(jSONObject.optString("units"));
        sb.append(jSONObject.optString("coin").equals("BTC") ? " satoshis)" : " litoshis)");
        if (!optString3.isEmpty()) {
            sb.append(equals ? "\nfrom " : "\nto ");
            sb.append(optString3);
        }
        sb.append("\n\nOn the chain\n");
        sb.append(Wallets.when(optLong));
        sb.append("  ·  confirmed\n");
        sb.append(jSONObject.optString("txid"));
        sb.append("\n\nYour wallet's notification\n");
        sb.append(Wallets.when(optLong2));
        sb.append("  ·  ");
        if (optString.equals("com.wallet.crypto.trustapp") || optString.equals("com.sixdays.trust")) {
            optString = "Trust Wallet";
        }
        sb.append(optString);
        sb.append(optString2.equals("android") ? " on this phone (installed from Google Play)" : " on the iPhone, relayed to this phone");
        sb.append("\n");
        if (j >= 0) {
            str = "Push came " + (j / 60) + " min " + (j % 60) + " s after the block";
        } else {
            str = "Push came before the block";
        }
        sb.append(str);
        final String fileName = Witness.fileName(wallet);
        boolean z = (Witness.exists(this, wallet) && fileName != null && new File(Witness.dir(this), fileName).exists()) ? true : EXPERIMENTAL_LESSONS;
        sb.append("\n\nSigned witness\n");
        if (z) {
            str2 = fileName + "\nsigned by this phone's own key";
        } else {
            str2 = "not saved yet (Check now)";
        }
        sb.append(str2);
        AlertDialog.Builder negativeButton = new AlertDialog.Builder(this).setTitle(wallet.name + ": ownership proven").setMessage(sb.toString()).setNegativeButton("Close", (DialogInterface.OnClickListener) null);
        if (z) {
            negativeButton.setPositiveButton("Share signed witness", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda3
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    MainActivity.this.lambda$showProof$15(fileName, dialogInterface, i);
                }
            });
        }
        negativeButton.show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showProof$15(String str, DialogInterface dialogInterface, int i) {
        shareWitness(str);
    }

    void shareWitness(String str) {
        try {
            File dir = Witness.dir(this);
            File dir2 = AnaFiles.dir(this);
            String str2 = str.substring(BG, str.length() - 8) + ".sha256";
            File file = new File(dir2, str);
            File file2 = new File(dir2, str2);
            copy(new File(dir, str), file);
            copy(new File(dir, str2), file2);
            Uri uriFor = AnaFiles.uriFor(this, file);
            Uri uriFor2 = AnaFiles.uriFor(this, file2);
            ArrayList<? extends Parcelable> arrayList = new ArrayList<>();
            arrayList.add(uriFor);
            arrayList.add(uriFor2);
            Intent intent = new Intent("android.intent.action.SEND_MULTIPLE");
            intent.setType("*/*");
            intent.putParcelableArrayListExtra("android.intent.extra.STREAM", arrayList);
            ClipData newRawUri = ClipData.newRawUri(str, uriFor);
            newRawUri.addItem(new ClipData.Item(uriFor2));
            intent.setClipData(newRawUri);
            intent.addFlags(1);
            startActivity(Intent.createChooser(intent, "Signed ownership witness (2 files: .pngmesh + .sha256)"));
        } catch (IOException e) {
            toast("Share failed: " + e.getMessage());
        }
    }

    private static void copy(File file, File file2) throws IOException {
        FileInputStream fileInputStream = new FileInputStream(file);
        try {
            FileOutputStream fileOutputStream = new FileOutputStream(file2);
            try {
                byte[] bArr = new byte[8192];
                while (true) {
                    int read = fileInputStream.read(bArr);
                    if (read <= 0) {
                        fileOutputStream.close();
                        fileInputStream.close();
                        return;
                    }
                    fileOutputStream.write(bArr, BG, read);
                }
            } finally {
            }
        } catch (Throwable th) {
            try {
                fileInputStream.close();
            } catch (Throwable th2) {
                th.addSuppressed(th2);
            }
            throw th;
        }
    }

    void showReminderDialog() {
        LinearLayout linearLayout = new LinearLayout(this);
        linearLayout.setOrientation(1);
        linearLayout.setPadding(48, 16, 48, BG);
        final EditText editText = new EditText(this);
        editText.setHint("Reminder");
        linearLayout.addView(editText);
        final DatePicker datePicker = new DatePicker(this);
        final TimePicker timePicker = new TimePicker(this);
        timePicker.setIs24HourView(Boolean.valueOf(EXPERIMENTAL_LESSONS));
        linearLayout.addView(datePicker);
        linearLayout.addView(timePicker);
        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(linearLayout);
        new AlertDialog.Builder(this).setTitle("New reminder").setView(scrollView).setPositiveButton("Save", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda6
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.this.lambda$showReminderDialog$16(timePicker, datePicker, editText, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$showReminderDialog$16(TimePicker timePicker, DatePicker datePicker, EditText editText, DialogInterface dialogInterface, int i) {
        Calendar calendar = Calendar.getInstance();
        calendar.set(datePicker.getYear(), datePicker.getMonth(), datePicker.getDayOfMonth(), timePicker.getHour(), timePicker.getMinute(), BG);
        long currentTimeMillis = System.currentTimeMillis();
        String trim = editText.getText().toString().trim();
        if (trim.length() <= 0) {
            trim = "Reminder";
        }
        AnaLog.append(this, "REMIND", currentTimeMillis, "ana.reminder", trim, "Reminder", "remind-" + currentTimeMillis, 0L, calendar.getTimeInMillis());
        deliverPending();
    }

    void exportLog() {
        Intent intent = new Intent("android.intent.action.SEND");
        intent.setType("text/plain");
        intent.putExtra("android.intent.extra.SUBJECT", "ANA notification log");
        intent.putExtra("android.intent.extra.TEXT", AnaLog.readText(this));
        startActivity(Intent.createChooser(intent, "Export ANA log"));
    }

    void exportPngmesh(String str) {
        List<String> readAll = AnaLog.readAll(this);
        ArrayList arrayList = new ArrayList();
        String[] split = str.split(",");
        int length = split.length;
        for (int i = BG; i < length; i++) {
            try {
                int parseInt = Integer.parseInt(split[i].trim());
                if (parseInt >= 0 && parseInt < readAll.size()) {
                    String[] split2 = readAll.get(parseInt).split("\t", -1);
                    if (split2.length >= 8) {
                        arrayList.add(split2);
                    }
                }
            } catch (NumberFormatException unused) {
            }
        }
        if (arrayList.isEmpty()) {
            toast("Nothing to export");
            return;
        }
        try {
            File dir = AnaFiles.dir(this);
            File[] listFiles = dir.listFiles();
            if (listFiles != null) {
                int length2 = listFiles.length;
                for (int i2 = BG; i2 < length2; i2++) {
                    listFiles[i2].delete();
                }
            }
            String str2 = "ana_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + "_" + arrayList.size() + ".pngmesh";
            byte[] write = AnaMesh.write(arrayList);
            File file = new File(dir, str2);
            File file2 = new File(dir, str2 + ".sha256");
            FileOutputStream fileOutputStream = new FileOutputStream(file);
            try {
                fileOutputStream.write(write);
                fileOutputStream.close();
                fileOutputStream = new FileOutputStream(file2);
                try {
                    fileOutputStream.write(AnaMesh.sidecar(str2, write).getBytes(StandardCharsets.UTF_8));
                    fileOutputStream.close();
                    Uri uriFor = AnaFiles.uriFor(this, file);
                    Uri uriFor2 = AnaFiles.uriFor(this, file2);
                    ArrayList<? extends Parcelable> arrayList2 = new ArrayList<>();
                    arrayList2.add(uriFor);
                    arrayList2.add(uriFor2);
                    Intent intent = new Intent("android.intent.action.SEND_MULTIPLE");
                    intent.setType("*/*");
                    intent.putParcelableArrayListExtra("android.intent.extra.STREAM", arrayList2);
                    ClipData newRawUri = ClipData.newRawUri(str2, uriFor);
                    newRawUri.addItem(new ClipData.Item(uriFor2));
                    intent.setClipData(newRawUri);
                    intent.addFlags(1);
                    startActivity(Intent.createChooser(intent, "Export " + arrayList.size() + " entr" + (arrayList.size() == 1 ? "y" : "ies") + " (2 files: .pngmesh + .sha256)"));
                } finally {
                }
            } finally {
                try {
                    fileOutputStream.close();
                } catch (Throwable th) {
                    th.addSuppressed(th);
                }
            }
        } catch (IOException e) {
            toast("Export failed: " + e.getMessage());
        }
    }

    Map<String, Long> lastUsed() {
        long currentTimeMillis = System.currentTimeMillis();
        if (currentTimeMillis - this.lastUsedAt < 60000) {
            return this.lastUsedMap;
        }
        this.lastUsedAt = currentTimeMillis;
        HashMap hashMap = new HashMap();
        try {
            List<UsageStats> queryUsageStats = ((UsageStatsManager) getSystemService("usagestats")).queryUsageStats(3, currentTimeMillis - 63072000000L, currentTimeMillis);
            if (queryUsageStats != null) {
                for (UsageStats usageStats : queryUsageStats) {
                    Long l = (Long) hashMap.get(usageStats.getPackageName());
                    if (l == null || usageStats.getLastTimeUsed() > l.longValue()) {
                        hashMap.put(usageStats.getPackageName(), Long.valueOf(usageStats.getLastTimeUsed()));
                    }
                }
            }
        } catch (Exception unused) {
        }
        this.lastUsedMap = hashMap;
        return hashMap;
    }

    void pickFiles() {
        Intent intent = new Intent("android.intent.action.OPEN_DOCUMENT");
        intent.addCategory("android.intent.category.OPENABLE");
        intent.setType("*/*");
        intent.putExtra("android.intent.extra.ALLOW_MULTIPLE", true);
        startActivityForResult(intent, REQ_IMPORT);
    }

    @Override // android.app.Activity
    protected void onActivityResult(int i, int i2, Intent intent) {
        super.onActivityResult(i, i2, intent);
        if (i == 42) {
            this.revealing = EXPERIMENTAL_LESSONS;
            if (i2 != -1 || Wallets.capturing) {
                return;
            }
            Wallets.back = true;
            return;
        }
        if (i == 43) {
            if (i2 == -1) {
                BillsUi.pictureResult(this, intent);
            }
        } else if (i == REQ_IMPORT && i2 == -1 && intent != null) {
            ArrayList arrayList = new ArrayList();
            if (intent.getClipData() != null) {
                for (int i3 = BG; i3 < intent.getClipData().getItemCount(); i3++) {
                    arrayList.add(intent.getClipData().getItemAt(i3).getUri());
                }
            } else if (intent.getData() != null) {
                arrayList.add(intent.getData());
            }
            importUris(arrayList);
        }
    }

    void handleIncoming(Intent intent) {
        ArrayList parcelableArrayListExtra;
        if (intent == null || intent.getAction() == null) {
            return;
        }
        ArrayList arrayList = new ArrayList();
        String action = intent.getAction();
        if ("android.intent.action.VIEW".equals(action) && intent.getData() != null) {
            arrayList.add(intent.getData());
        } else if ("android.intent.action.SEND".equals(action)) {
            Uri uri = (Uri) intent.getParcelableExtra("android.intent.extra.STREAM");
            if (uri != null) {
                arrayList.add(uri);
            }
        } else if ("android.intent.action.SEND_MULTIPLE".equals(action) && (parcelableArrayListExtra = intent.getParcelableArrayListExtra("android.intent.extra.STREAM")) != null) {
            arrayList.addAll(parcelableArrayListExtra);
        }
        if (arrayList.isEmpty() && intent.getClipData() != null && !"android.intent.action.MAIN".equals(action)) {
            for (int i = BG; i < intent.getClipData().getItemCount(); i++) {
                Uri uri2 = intent.getClipData().getItemAt(i).getUri();
                if (uri2 != null) {
                    arrayList.add(uri2);
                }
            }
        }
        intent.setAction("android.intent.action.MAIN");
        if (arrayList.isEmpty()) {
            return;
        }
        importUris(arrayList);
    }

    void importUris(final List<Uri> list) {
        new Thread(new Runnable() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda22
            @Override // java.lang.Runnable
            public final void run() {
                MainActivity.this.lambda$importUris$20(list);
            }
        }).start();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$importUris$20(List list) {
        int i;
        int i2;
        int i3;
        ArrayList<String> arrayList = new ArrayList();
        synchronized (waitingMesh) {
            Iterator it = list.iterator();
            while (it.hasNext()) {
                Uri uri = (Uri) it.next();
                String displayName = displayName(uri);
                try {
                    byte[] readUri = readUri(uri);
                    if (AnaMesh.looksLikePngmesh(readUri)) {
                        waitingMesh.put(AnaMesh.sha256(readUri), new Object[]{displayName, readUri});
                    } else {
                        String sidecarHash = AnaMesh.sidecarHash(readUri);
                        if (sidecarHash != null) {
                            waitingSidecar.add(sidecarHash);
                        } else {
                            arrayList.add(displayName + " is not a .pngmesh or .sha256");
                        }
                    }
                } catch (IOException e) {
                    arrayList.add(displayName + ": " + e.getMessage());
                }
            }
            Iterator it2 = new ArrayList(waitingMesh.keySet()).iterator();
            i = BG;
            i2 = i;
            i3 = i2;
            while (it2.hasNext()) {
                String str = (String) it2.next();
                Set<String> set = waitingSidecar;
                if (set.contains(str)) {
                    Object[] remove = waitingMesh.remove(str);
                    set.remove(str);
                    try {
                        final byte[] bArr = (byte[]) remove[1];
                        if (AnaMesh.classOf(bArr) == 21) {
                            i += gstReceived(AnaMesh.readGst(bArr));
                        } else {
                            int classOf = BillCore.classOf(bArr);
                            if (classOf == 46) {
                                runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda17
                                    @Override // java.lang.Runnable
                                    public final void run() {
                                        MainActivity.this.lambda$importUris$17(bArr);
                                    }
                                });
                            } else if (classOf >= 40 && classOf <= 45) {
                                runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda18
                                    @Override // java.lang.Runnable
                                    public final void run() {
                                        MainActivity.this.lambda$importUris$18(bArr);
                                    }
                                });
                            } else {
                                int classOf2 = Lessons.classOf(bArr);
                                if (classOf2 != 30 && classOf2 != 31 && classOf2 != 32) {
                                    int[] addToLog = addToLog(AnaMesh.read(bArr));
                                    i2 += addToLog[BG];
                                    i3 += addToLog[1];
                                }
                                final byte[] bytes = (str + "\n").getBytes(StandardCharsets.UTF_8);
                                runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda19
                                    @Override // java.lang.Runnable
                                    public final void run() {
                                        MainActivity.this.lambda$importUris$19(bArr, bytes);
                                    }
                                });
                            }
                        }
                    } catch (IOException e2) {
                        arrayList.add(String.valueOf(remove[BG]) + ": " + e2.getMessage());
                    }
                }
            }
            Iterator<Object[]> it3 = waitingMesh.values().iterator();
            while (it3.hasNext()) {
                arrayList.add(String.valueOf(it3.next()[BG]) + ": waiting for its .sha256 (IMPORT it too)");
            }
            if (!waitingSidecar.isEmpty() && waitingMesh.isEmpty() && i2 == 0 && i3 == 0 && i == 0) {
                arrayList.add("got a .sha256: now IMPORT its .pngmesh");
            }
        }
        StringBuilder sb = new StringBuilder();
        if (i2 + i3 > 0) {
            sb.append("Imported ");
            sb.append(i2);
            sb.append(i3 > 0 ? ", " + i3 + " already here" : "");
        }
        if (i > 0) {
            sb.append(sb.length() > 0 ? "\n" : "");
            sb.append("GST: ");
            sb.append(i);
            sb.append(i == 1 ? " update" : " updates");
            sb.append(" received");
        }
        for (String str2 : arrayList) {
            sb.append(sb.length() > 0 ? "\n" : "");
            sb.append(str2);
        }
        if (sb.length() > 0) {
            toast(sb.toString());
        }
        poke();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$importUris$17(byte[] bArr) {
        String receive = Chat.receive(this, bArr, "File");
        if (receive != null) {
            Toast.makeText(this, receive, 1).show();
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$importUris$18(byte[] bArr) {
        BillsUi.received(this, bArr);
    }

    private int[] addToLog(List<String[]> list) {
        long currentTimeMillis;
        long j;
        String str;
        HashSet hashSet = new HashSet();
        Iterator<String> it = AnaLog.readAll(this).iterator();
        while (it.hasNext()) {
            String[] split = it.next().split("\t", -1);
            if (split.length >= 8) {
                hashSet.add(split[2] + "\t" + split[6] + "\t" + split[5]);
            }
        }
        int i = BG;
        int i2 = BG;
        for (String[] strArr : list) {
            String str2 = strArr[2] + "\t" + strArr[6] + "\t" + strArr[5];
            if (hashSet.contains(str2)) {
                i2++;
            } else {
                try {
                    currentTimeMillis = Long.parseLong(strArr[2]);
                } catch (NumberFormatException unused) {
                    currentTimeMillis = System.currentTimeMillis();
                }
                long j2 = currentTimeMillis;
                long j3 = 0;
                try {
                    j = Long.parseLong(strArr[7]);
                } catch (NumberFormatException unused2) {
                    j = 0;
                }
                try {
                    if (strArr.length > 8 && (str = strArr[8]) != null) {
                        j3 = Long.parseLong(str);
                    }
                } catch (NumberFormatException unused3) {
                }
                AnaLog.append(this, "IMPORT", j2, strArr[3], strArr[4], strArr[5], strArr[6], j, j3);
                hashSet.add(str2);
                i++;
            }
        }
        return new int[]{i, i2};
    }

    private byte[] readUri(Uri uri) throws IOException {
        InputStream openInputStream = getContentResolver().openInputStream(uri);
        try {
            if (openInputStream == null) {
                throw new IOException("can't open");
            }
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            byte[] bArr = new byte[65536];
            do {
                int read = openInputStream.read(bArr);
                if (read > 0) {
                    byteArrayOutputStream.write(bArr, BG, read);
                } else {
                    byte[] byteArray = byteArrayOutputStream.toByteArray();
                    if (openInputStream != null) {
                        openInputStream.close();
                    }
                    return byteArray;
                }
            } while (byteArrayOutputStream.size() <= 67108864);
            throw new IOException("file too big");
        } catch (Throwable th) {
            if (openInputStream != null) {
                try {
                    openInputStream.close();
                } catch (Throwable th2) {
                    th.addSuppressed(th2);
                }
            }
            throw th;
        }
    }

    private String displayName(Uri uri) {
        try {
            Cursor query = getContentResolver().query(uri, new String[]{"_display_name"}, null, null, null);
            if (query != null) {
                try {
                    if (query.moveToFirst() && query.getString(BG) != null) {
                        String string = query.getString(BG);
                        if (query != null) {
                            query.close();
                        }
                        return string;
                    }
                } finally {
                }
            }
            if (query != null) {
                query.close();
            }
        } catch (Exception unused) {
        }
        String lastPathSegment = uri.getLastPathSegment();
        return lastPathSegment != null ? lastPathSegment : "file";
    }

    private int gstReceived(List<String[]> list) {
        long currentTimeMillis;
        synchronized (gstInbox) {
            Iterator<String[]> it = list.iterator();
            while (it.hasNext()) {
                gstInbox.add(TextUtils.join("\t", it.next()));
            }
        }
        for (String[] strArr : list) {
            if ("ALERT".equals(strArr[1])) {
                try {
                    currentTimeMillis = Long.parseLong(strArr[5]);
                } catch (NumberFormatException unused) {
                    currentTimeMillis = System.currentTimeMillis();
                }
                AnaLog.append(this, "GST", currentTimeMillis, "ana.gst", "Spend alert from " + strArr[4], "About to spend " + strArr[6] + " " + strArr[7] + (strArr[8].isEmpty() ? "" : " on " + strArr[8]), "gst-" + strArr[BG], 0L);
            }
        }
        return list.size();
    }

    void gstSend(String str, String str2, String str3, String str4) {
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        String[] split = str3.split("\n");
        int length = split.length;
        for (int i = BG; i < length; i++) {
            String str5 = split[i];
            if (!str5.isEmpty()) {
                arrayList.add(str5.split("\t", -1));
            }
        }
        String format = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(new Date());
        String[] split2 = str4.split("\n");
        int length2 = split2.length;
        for (int i2 = BG; i2 < length2; i2++) {
            String str6 = split2[i2];
            if (!str6.isEmpty()) {
                String[] split3 = str6.split("\t", -1);
                arrayList2.add(new String[]{"GST", format, "", "GST", split3[BG], split3.length > 1 ? split3[1] : ""});
            }
        }
        if (arrayList.isEmpty()) {
            return;
        }
        try {
            File dir = AnaFiles.dir(this);
            File[] listFiles = dir.listFiles();
            if (listFiles != null) {
                int length3 = listFiles.length;
                for (int i3 = BG; i3 < length3; i3++) {
                    listFiles[i3].delete();
                }
            }
            String str7 = "gst_" + str.replaceAll("[^A-Za-z0-9_-]+", "_") + "_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".pngmesh";
            byte[] writeGst = AnaMesh.writeGst(arrayList, arrayList2, str2);
            File file = new File(dir, str7);
            File file2 = new File(dir, str7 + ".sha256");
            FileOutputStream fileOutputStream = new FileOutputStream(file);
            try {
                fileOutputStream.write(writeGst);
                fileOutputStream.close();
                fileOutputStream = new FileOutputStream(file2);
                try {
                    fileOutputStream.write(AnaMesh.sidecar(str7, writeGst).getBytes(StandardCharsets.UTF_8));
                    fileOutputStream.close();
                    Uri uriFor = AnaFiles.uriFor(this, file);
                    Uri uriFor2 = AnaFiles.uriFor(this, file2);
                    ArrayList<? extends Parcelable> arrayList3 = new ArrayList<>();
                    arrayList3.add(uriFor);
                    arrayList3.add(uriFor2);
                    Intent intent = new Intent("android.intent.action.SEND_MULTIPLE");
                    intent.setType("*/*");
                    intent.putParcelableArrayListExtra("android.intent.extra.STREAM", arrayList3);
                    ClipData newRawUri = ClipData.newRawUri(str7, uriFor);
                    newRawUri.addItem(new ClipData.Item(uriFor2));
                    intent.setClipData(newRawUri);
                    intent.addFlags(1);
                    startActivity(Intent.createChooser(intent, "Send " + str2 + " (2 files: .pngmesh + .sha256)"));
                } finally {
                    try {
                        fileOutputStream.close();
                        throw th;
                    } catch (Throwable th) {
                        th.addSuppressed(th);
                    }
                }
            } finally {
            }
        } catch (IOException e) {
            toast("Couldn't make the GST file: " + e.getMessage());
        }
    }

    void gstAsk(final String str, String str2, String str3, String str4) {
        LinearLayout linearLayout = new LinearLayout(this);
        linearLayout.setOrientation(1);
        linearLayout.setPadding(48, 16, 48, BG);
        final ArrayList arrayList = new ArrayList();
        String[] split = str4.split("\n");
        int length = split.length;
        for (int i = BG; i < length; i++) {
            String str5 = split[i];
            if (!str5.isEmpty()) {
                String[] split2 = str5.split("\\|", -1);
                EditText editText = new EditText(this);
                editText.setHint(split2[BG]);
                if (split2.length > 1) {
                    editText.setText(split2[1]);
                }
                if (split2.length > 2 && split2[2].equals("number")) {
                    editText.setInputType(8194);
                } else {
                    editText.setInputType(16385);
                }
                editText.setSingleLine(true);
                linearLayout.addView(editText);
                arrayList.add(editText);
            }
        }
        AlertDialog.Builder title = new AlertDialog.Builder(this).setTitle(str2);
        if (str3.isEmpty()) {
            str3 = null;
        }
        title.setMessage(str3).setView(linearLayout).setPositiveButton("OK", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda10
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                MainActivity.lambda$gstAsk$21(arrayList, str, dialogInterface, i2);
            }
        }).setNegativeButton("Cancel", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda11
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i2) {
                MainActivity.lambda$gstAsk$22(str, dialogInterface, i2);
            }
        }).setOnCancelListener(new DialogInterface.OnCancelListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda12
            @Override // android.content.DialogInterface.OnCancelListener
            public final void onCancel(DialogInterface dialogInterface) {
                MainActivity.lambda$gstAsk$23(str, dialogInterface);
            }
        }).show();
    }

    static /* synthetic */ void lambda$gstAsk$21(List list, String str, DialogInterface dialogInterface, int i) {
        StringBuilder sb = new StringBuilder("O");
        Iterator it = list.iterator();
        while (it.hasNext()) {
            EditText editText = (EditText) it.next();
            sb.append('\t');
            sb.append(editText.getText().toString().replace('\t', ' ').replace('\n', ' ').trim());
        }
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, sb.toString());
        }
    }

    static /* synthetic */ void lambda$gstAsk$22(String str, DialogInterface dialogInterface, int i) {
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, "C");
        }
    }

    static /* synthetic */ void lambda$gstAsk$23(String str, DialogInterface dialogInterface) {
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, "C");
        }
    }

    void gstPick(final String str, String str2, String str3) {
        new AlertDialog.Builder(this).setTitle(str2).setItems(str3.split("\n"), new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda25
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.lambda$gstPick$24(str, dialogInterface, i);
            }
        }).setNegativeButton("Cancel", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda26
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                MainActivity.lambda$gstPick$25(str, dialogInterface, i);
            }
        }).setOnCancelListener(new DialogInterface.OnCancelListener() { // from class: com.novera.ana.MainActivity$$ExternalSyntheticLambda27
            @Override // android.content.DialogInterface.OnCancelListener
            public final void onCancel(DialogInterface dialogInterface) {
                MainActivity.lambda$gstPick$26(str, dialogInterface);
            }
        }).show();
    }

    static /* synthetic */ void lambda$gstPick$24(String str, DialogInterface dialogInterface, int i) {
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, "O\t" + i);
        }
    }

    static /* synthetic */ void lambda$gstPick$25(String str, DialogInterface dialogInterface, int i) {
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, "C");
        }
    }

    static /* synthetic */ void lambda$gstPick$26(String str, DialogInterface dialogInterface) {
        Map<String, String> map = gstAnswers;
        synchronized (map) {
            map.put(str, "C");
        }
    }

    class Bridge {
        Bridge() {
        }

        @JavascriptInterface
        public String readSketch() {
            return MainActivity.this.readSketch();
        }

        @JavascriptInterface
        public void ready() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda26
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$ready$0();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$ready$0() {
            MainActivity.this.pageReady = true;
            MainActivity.this.delivered = MainActivity.BG;
            MainActivity.this.deliverPending();
        }

        @JavascriptInterface
        public String status() {
            return MainActivity.this.status();
        }

        @JavascriptInterface
        public String watchList() {
            return MainActivity.this.getSharedPreferences("ana", MainActivity.BG).getString("watch", "");
        }

        @JavascriptInterface
        public void saveWatch(String str) {
            SharedPreferences.Editor edit = MainActivity.this.getSharedPreferences("ana", MainActivity.BG).edit();
            if (str == null) {
                str = "";
            }
            edit.putString("watch", str).apply();
        }

        @JavascriptInterface
        public String pref(String str) {
            return MainActivity.this.getSharedPreferences("ana", MainActivity.BG).getString("p_" + str, "");
        }

        @JavascriptInterface
        public void setPref(String str, String str2) {
            SharedPreferences.Editor edit = MainActivity.this.getSharedPreferences("ana", MainActivity.BG).edit();
            String str3 = "p_" + str;
            if (str2 == null) {
                str2 = "";
            }
            edit.putString(str3, str2).apply();
        }

        @JavascriptInterface
        public String appIcon(String str) {
            try {
                Drawable applicationIcon = MainActivity.this.getPackageManager().getApplicationIcon(str);
                Bitmap createBitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888);
                Canvas canvas = new Canvas(createBitmap);
                applicationIcon.setBounds(MainActivity.BG, MainActivity.BG, 192, 192);
                applicationIcon.draw(canvas);
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                createBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream);
                createBitmap.recycle();
                return "data:image/png;base64," + Base64.encodeToString(byteArrayOutputStream.toByteArray(), 2);
            } catch (Exception unused) {
                return "";
            }
        }

        @JavascriptInterface
        public String appLabel(String str) {
            if ("ana.watch".equals(str)) {
                return "Watch";
            }
            if ("ana.gst".equals(str)) {
                return "GST";
            }
            if ("ana.flex".equals(str)) {
                return "Bills";
            }
            if ("ana.chat".equals(str)) {
                return "CHATNOTE";
            }
            try {
                PackageManager packageManager = MainActivity.this.getPackageManager();
                return packageManager.getApplicationLabel(packageManager.getApplicationInfo(str, MainActivity.BG)).toString();
            } catch (Exception unused) {
                return MainActivity.this.getSharedPreferences("ana", MainActivity.BG).getString("ios_" + str, "");
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$iphoneLink$1(boolean z) {
            MainActivity.this.iphoneOn(z);
        }

        @JavascriptInterface
        public void iphoneLink(final boolean z) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda9
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$iphoneLink$1(z);
                }
            });
        }

        @JavascriptInterface
        public void copyText(final String str) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda6
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$copyText$2(str);
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$copyText$2(String str) {
            ClipboardManager clipboardManager = (ClipboardManager) MainActivity.this.getSystemService("clipboard");
            if (clipboardManager != null) {
                clipboardManager.setPrimaryClip(ClipData.newPlainText("ANA", str));
            }
        }

        @JavascriptInterface
        public boolean iphoneDismiss(String str) {
            AncsLink ancsLink = AncsLink.instance;
            if (ancsLink == null || !ancsLink.dismiss(str)) {
                return MainActivity.EXPERIMENTAL_LESSONS;
            }
            return true;
        }

        @JavascriptInterface
        public String iphoneState() {
            return AncsLink.state;
        }

        @JavascriptInterface
        public String iphoneTimes() {
            return AncsLink.times();
        }

        @JavascriptInterface
        public String appCategory(String str) {
            if (Build.VERSION.SDK_INT < 26) {
                return "";
            }
            try {
                CharSequence categoryTitle = ApplicationInfo.getCategoryTitle(MainActivity.this, MainActivity.this.getPackageManager().getApplicationInfo(str, MainActivity.BG).category);
                return categoryTitle == null ? "" : categoryTitle.toString();
            } catch (Exception unused) {
                return "";
            }
        }

        @JavascriptInterface
        public boolean usageOk() {
            try {
                if (((AppOpsManager) MainActivity.this.getSystemService("appops")).checkOpNoThrow("android:get_usage_stats", Process.myUid(), MainActivity.this.getPackageName()) == 0) {
                    return true;
                }
                return MainActivity.EXPERIMENTAL_LESSONS;
            } catch (Exception unused) {
                return MainActivity.EXPERIMENTAL_LESSONS;
            }
        }

        @JavascriptInterface
        public void openUsageAccess() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda4
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$openUsageAccess$3();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$openUsageAccess$3() {
            try {
                MainActivity.this.startActivity(new Intent("android.settings.USAGE_ACCESS_SETTINGS"));
            } catch (Exception unused) {
                MainActivity.this.toast("Open Settings > Usage access, and turn it on for ANA");
            }
        }

        @JavascriptInterface
        public String usageToday() {
            try {
                UsageStatsManager usageStatsManager = (UsageStatsManager) MainActivity.this.getSystemService("usagestats");
                Calendar calendar = Calendar.getInstance();
                calendar.set(11, MainActivity.BG);
                calendar.set(12, MainActivity.BG);
                calendar.set(13, MainActivity.BG);
                calendar.set(14, MainActivity.BG);
                Map<String, UsageStats> queryAndAggregateUsageStats = usageStatsManager.queryAndAggregateUsageStats(calendar.getTimeInMillis(), System.currentTimeMillis());
                ArrayList arrayList = new ArrayList();
                PackageManager packageManager = MainActivity.this.getPackageManager();
                for (UsageStats usageStats : queryAndAggregateUsageStats.values()) {
                    if (usageStats.getTotalTimeInForeground() >= 1000 && !MainActivity.this.getPackageName().equals(usageStats.getPackageName()) && packageManager.getLaunchIntentForPackage(usageStats.getPackageName()) != null) {
                        arrayList.add(usageStats);
                    }
                }
                Collections.sort(arrayList, new Comparator() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda14
                    @Override // java.util.Comparator
                    public final int compare(Object obj, Object obj2) {
                        int compare;
                        compare = Long.compare(((UsageStats) obj2).getTotalTimeInForeground(), ((UsageStats) obj).getTotalTimeInForeground());
                        return compare;
                    }
                });
                StringBuilder sb = new StringBuilder();
                long currentTimeMillis = System.currentTimeMillis();
                for (int i = MainActivity.BG; i < arrayList.size() && i < 40; i++) {
                    UsageStats usageStats2 = (UsageStats) arrayList.get(i);
                    sb.append(usageStats2.getPackageName());
                    sb.append('\t');
                    sb.append(usageStats2.getTotalTimeInForeground() / 1000);
                    sb.append('\t');
                    sb.append(Math.max(0L, currentTimeMillis - usageStats2.getLastTimeUsed()) / 1000);
                    sb.append('\n');
                }
                return sb.toString();
            } catch (Exception unused) {
                return "";
            }
        }

        @JavascriptInterface
        public String appStatus(String str) {
            if (MainActivity.this.getSharedPreferences("ana", MainActivity.BG).contains("ios_" + str)) {
                return "iphone";
            }
            PackageManager packageManager = MainActivity.this.getPackageManager();
            try {
                if (Build.VERSION.SDK_INT >= 35) {
                    if (packageManager.getApplicationInfo(str, PackageManager.ApplicationInfoFlags.of(4294967296L)).isArchived) {
                        return "archived";
                    }
                } else {
                    packageManager.getApplicationInfo(str, MainActivity.BG);
                }
                if (!usageOk()) {
                    return "installed";
                }
                Long l = MainActivity.this.lastUsed().get(str);
                return (l == null ? Long.MAX_VALUE : System.currentTimeMillis() - l.longValue()) < 2592000000L ? "active" : "dormant";
            } catch (Exception unused) {
                return "uninstalled";
            }
        }

        @JavascriptInterface
        public void appSettings(final String str) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda15
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$appSettings$5(str);
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$appSettings$5(String str) {
            Intent intent = new Intent("android.settings.APPLICATION_DETAILS_SETTINGS", Uri.parse("package:" + str));
            intent.addFlags(268435456);
            try {
                MainActivity.this.startActivity(intent);
            } catch (Exception unused) {
                MainActivity.this.toast("Can't open App info for " + str);
            }
        }

        @JavascriptInterface
        public int clearNotifs(String str) {
            return AnaListener.clear(str);
        }

        @JavascriptInterface
        public int sdkInt() {
            return Build.VERSION.SDK_INT;
        }

        @JavascriptInterface
        public void openOwnInfo() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda23
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$openOwnInfo$6();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$openOwnInfo$6() {
            Intent intent = new Intent("android.settings.APPLICATION_DETAILS_SETTINGS", Uri.parse("package:" + MainActivity.this.getPackageName()));
            intent.addFlags(268435456);
            try {
                MainActivity.this.startActivity(intent);
            } catch (Exception unused) {
                MainActivity.this.toast("Can't open App info");
            }
        }

        @JavascriptInterface
        public boolean closeApp(String str) {
            try {
                MainActivity.this.getPackageManager().getApplicationInfo(str, MainActivity.BG);
                ((ActivityManager) MainActivity.this.getSystemService("activity")).killBackgroundProcesses(str);
                return true;
            } catch (Exception unused) {
                return MainActivity.EXPERIMENTAL_LESSONS;
            }
        }

        @JavascriptInterface
        public boolean launchApp(String str) {
            if (str != null && str.startsWith("find:")) {
                final String encode = Uri.encode(str.substring(5));
                MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda21
                    @Override // java.lang.Runnable
                    public final void run() {
                        MainActivity.Bridge.this.lambda$launchApp$7(encode);
                    }
                });
                return true;
            }
            final Intent launchIntentForPackage = MainActivity.this.getPackageManager().getLaunchIntentForPackage(str);
            if (launchIntentForPackage == null) {
                MainActivity.this.toast("Can't open " + str + " (not installed here)");
                return MainActivity.EXPERIMENTAL_LESSONS;
            }
            launchIntentForPackage.addFlags(268435456);
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda22
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$launchApp$8(launchIntentForPackage);
                }
            });
            return true;
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$launchApp$7(String str) {
            try {
                MainActivity.this.startActivity(new Intent("android.intent.action.VIEW", Uri.parse("market://search?q=" + str + "&c=apps")).addFlags(268435456));
            } catch (Exception unused) {
                MainActivity.this.startActivity(new Intent("android.intent.action.VIEW", Uri.parse("https://play.google.com/store/search?q=" + str + "&c=apps")).addFlags(268435456));
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$launchApp$8(Intent intent) {
            MainActivity.this.startActivity(intent);
        }

        @JavascriptInterface
        public String skinData(String str) {
            if (str != null && str.matches("[A-Za-z0-9_]+\\.png")) {
                try {
                    InputStream open = MainActivity.this.getAssets().open(str);
                    try {
                        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                        byte[] bArr = new byte[16384];
                        while (true) {
                            int read = open.read(bArr);
                            if (read <= 0) {
                                break;
                            }
                            byteArrayOutputStream.write(bArr, MainActivity.BG, read);
                        }
                        String str2 = "data:image/png;base64," + Base64.encodeToString(byteArrayOutputStream.toByteArray(), 2);
                        if (open != null) {
                            open.close();
                        }
                        return str2;
                    } finally {
                    }
                } catch (IOException unused) {
                }
            }
            return "";
        }

        @JavascriptInterface
        public void scan() {
            new Thread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda10
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$scan$9();
                }
            }).start();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$scan$9() {
            int scan = AnaListener.scan(MainActivity.this);
            if (scan < 0) {
                MainActivity.this.toast("Listener not connected - tap ACCESS");
                return;
            }
            MainActivity.this.toast("Scan: " + scan + " notification(s) in the shade");
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$openAccess$10() {
            MainActivity.this.startActivity(new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"));
        }

        @JavascriptInterface
        public void openAccess() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda0
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$openAccess$10();
                }
            });
        }

        @JavascriptInterface
        public void manualEntry() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda20
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.showManualDialog();
                }
            });
        }

        @JavascriptInterface
        public void addReminder() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda5
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.showReminderDialog();
                }
            });
        }

        @JavascriptInterface
        public void exportLog() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda16
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.exportLog();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$exportPngmesh$11(String str) {
            MainActivity.this.exportPngmesh(str);
        }

        @JavascriptInterface
        public void exportPngmesh(final String str) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda1
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$exportPngmesh$11(str);
                }
            });
        }

        @JavascriptInterface
        public void importFiles() {
            MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new BillsUi$$ExternalSyntheticLambda26(mainActivity));
        }

        @JavascriptInterface
        public String walletText() {
            return Wallets.pageText();
        }

        @JavascriptInterface
        public boolean walletBusy() {
            return Wallets.busy;
        }

        @JavascriptInterface
        public void walletRefresh() {
            Wallets.refreshAll(MainActivity.this);
        }

        @JavascriptInterface
        public String lessonsText() {
            return Lessons.text();
        }

        @JavascriptInterface
        public void lessonsOpen() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda11
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.showLessons();
                }
            });
        }

        @JavascriptInterface
        public String billsText() {
            return Bills.text(MainActivity.this);
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$billsOpen$12() {
            BillsUi.open(MainActivity.this);
        }

        @JavascriptInterface
        public void billsOpen() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda8
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$billsOpen$12();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$chatOpen$13() {
            Chat.show(MainActivity.this);
        }

        @JavascriptInterface
        public void chatOpen() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda12
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$chatOpen$13();
                }
            });
        }

        @JavascriptInterface
        public String chatList() {
            return Chat.list(MainActivity.this);
        }

        @JavascriptInterface
        public void chatClear(String str) {
            MainActivity mainActivity = MainActivity.this;
            if (str == null) {
                str = "";
            }
            Chat.clear(mainActivity, str);
        }

        @JavascriptInterface
        public void findAdd() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda24
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$findAdd$15();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$findAdd$15() {
            final EditText editText = new EditText(MainActivity.this);
            editText.setHint("App name");
            editText.setSingleLine(true);
            new AlertDialog.Builder(MainActivity.this).setTitle("Find an app").setMessage("Type any app's name. It goes on the globe; OPEN looks it up in the Play Store.").setView(editText).setPositiveButton("Add", new DialogInterface.OnClickListener() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda7
                @Override // android.content.DialogInterface.OnClickListener
                public final void onClick(DialogInterface dialogInterface, int i) {
                    MainActivity.Bridge.this.lambda$findAdd$14(editText, dialogInterface, i);
                }
            }).setNegativeButton("Cancel", (DialogInterface.OnClickListener) null).show();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$findAdd$14(EditText editText, DialogInterface dialogInterface, int i) {
            String trim = editText.getText().toString().replace('\n', ' ').trim();
            if (trim.isEmpty()) {
                return;
            }
            int length = trim.length();
            if (length > 40) {
                trim = trim.substring(MainActivity.BG, 40);
            }
            SharedPreferences sharedPreferences = MainActivity.this.getSharedPreferences("ana", MainActivity.BG);
            StringBuilder sb = new StringBuilder(trim);
            String[] split = sharedPreferences.getString("p_finds", "").split("\n");
            int length2 = split.length;
            int i2 = 1;
            for (int i3 = MainActivity.BG; i3 < length2; i3++) {
                String str = split[i3];
                if (!str.isEmpty() && !str.equals(trim)) {
                    int i4 = i2 + 1;
                    if (i2 < 40) {
                        sb.append('\n');
                        sb.append(str);
                    }
                    i2 = i4;
                }
            }
            sharedPreferences.edit().putString("p_finds", sb.toString()).apply();
        }

        @JavascriptInterface
        public void findRemove(String str) {
            MainActivity mainActivity = MainActivity.this;
            SharedPreferences sharedPreferences = mainActivity.getSharedPreferences("ana", MainActivity.BG);
            StringBuilder sb = new StringBuilder();
            String[] split = sharedPreferences.getString("p_finds", "").split("\n");
            int length = split.length;
            for (int i = MainActivity.BG; i < length; i++) {
                String str2 = split[i];
                if (!str2.isEmpty() && !str2.equals(str)) {
                    if (sb.length() > 0) {
                        sb.append('\n');
                    }
                    sb.append(str2);
                }
            }
            sharedPreferences.edit().putString("p_finds", sb.toString()).apply();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$chatWrite$16() {
            Chat.write(MainActivity.this);
        }

        @JavascriptInterface
        public void chatWrite() {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda25
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$chatWrite$16();
                }
            });
        }

        @JavascriptInterface
        public void walletAdd() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda2
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.showWalletAdd();
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$walletEdit$17(String str) {
            MainActivity.this.showWalletEdit(str);
        }

        @JavascriptInterface
        public void walletEdit(final String str) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda18
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$walletEdit$17(str);
                }
            });
        }

        @JavascriptInterface
        public void walletReveal() {
            final MainActivity mainActivity = MainActivity.this;
            mainActivity.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda3
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.this.revealSubWatch();
                }
            });
        }

        @JavascriptInterface
        public boolean walletBack() {
            return Wallets.back;
        }

        @JavascriptInterface
        public void walletFront() {
            Wallets.back = MainActivity.EXPERIMENTAL_LESSONS;
        }

        @JavascriptInterface
        public String walletTotals() {
            return Wallets.totals();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$gstSend$18(String str, String str2, String str3, String str4) {
            MainActivity.this.gstSend(str, str2, str3, str4);
        }

        @JavascriptInterface
        public void gstSend(final String str, final String str2, final String str3, final String str4) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda19
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$gstSend$18(str, str2, str3, str4);
                }
            });
        }

        @JavascriptInterface
        public String gstInbox() {
            String join;
            synchronized (MainActivity.gstInbox) {
                join = TextUtils.join("\n", MainActivity.gstInbox);
                MainActivity.gstInbox.clear();
            }
            return join;
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$gstAsk$19(String str, String str2, String str3, String str4) {
            MainActivity.this.gstAsk(str, str2, str3, str4);
        }

        @JavascriptInterface
        public void gstAsk(final String str, final String str2, final String str3, final String str4) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda13
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$gstAsk$19(str, str2, str3, str4);
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$gstPick$20(String str, String str2, String str3) {
            MainActivity.this.gstPick(str, str2, str3);
        }

        @JavascriptInterface
        public void gstPick(final String str, final String str2, final String str3) {
            MainActivity.this.runOnUiThread(new Runnable() { // from class: com.novera.ana.MainActivity$Bridge$$ExternalSyntheticLambda17
                @Override // java.lang.Runnable
                public final void run() {
                    MainActivity.Bridge.this.lambda$gstPick$20(str, str2, str3);
                }
            });
        }

        @JavascriptInterface
        public String flexKey() {
            return Flex.publicKey();
        }

        @JavascriptInterface
        public String flexSign(String str) {
            return Flex.sign(str);
        }

        @JavascriptInterface
        public boolean flexVerify(String str, String str2, String str3) {
            return Flex.verify(str, str2, str3);
        }

        @JavascriptInterface
        public String flexHash(String str) {
            return Flex.sha256(str);
        }

        @JavascriptInterface
        public String gstAnswer(String str) {
            String remove;
            synchronized (MainActivity.gstAnswers) {
                remove = MainActivity.gstAnswers.remove(str);
                if (remove == null) {
                    remove = "";
                }
            }
            return remove;
        }
    }
}
