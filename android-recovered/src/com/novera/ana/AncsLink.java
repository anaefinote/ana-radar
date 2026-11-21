package com.novera.ana;

import android.R;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Base64;
import com.novera.ana.AncsLink;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;

/* loaded from: classes.dex */
public class AncsLink extends Service {
    private static final String CHANNEL = "ana_iphone";
    static volatile AncsLink instance;
    private AdvertiseData advData;
    private AdvertiseData advResp;
    private AdvertiseSettings advS;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothManager bm;
    private BluetoothGattCharacteristic cp;
    private byte[] curLine;
    private int curOff;
    private BluetoothGattCharacteristic ds;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic ns;
    private BluetoothDevice phone;
    private BluetoothGattCharacteristic relay;
    private BluetoothDevice relayTo;
    private BluetoothGattServer server;
    static final UUID ANCS = UUID.fromString("7905F431-B5CE-4E99-A40F-4B1E122D00D0");
    static final UUID NOTIF_SOURCE = UUID.fromString("9FBF120D-6301-42D9-8C58-25E699A21DBD");
    static final UUID CONTROL_POINT = UUID.fromString("69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9");
    static final UUID DATA_SOURCE = UUID.fromString("22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB");
    static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    static final UUID ANA_SERVICE = UUID.fromString("A7A0A001-0E0F-4A4E-8A00-414E41000001");
    static final UUID ANA_NAME = UUID.fromString("A7A0A002-0E0F-4A4E-8A00-414E41000001");
    static final UUID ANA_RELAY = UUID.fromString("A7A0A003-0E0F-4A4E-8A00-414E41000001");
    static final UUID ANA_CONTROL = UUID.fromString("A7A0A004-0E0F-4A4E-8A00-414E41000001");
    static volatile String state = "Off";
    static volatile long linkedAt = 0;
    static volatile long lastNotifAt = 0;
    static volatile long outSince = 0;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ArrayDeque<byte[]> requests = new ArrayDeque<>();
    private boolean waiting = false;
    private final ByteArrayOutputStream answer = new ByteArrayOutputStream();
    private final Set<String> seen = new HashSet();
    private final Set<String> askedName = new HashSet();
    private int mtu = 23;
    private final ArrayDeque<byte[]> lines = new ArrayDeque<>();
    private boolean sending = false;
    private int sendSeq = 0;
    private int reqSeq = 0;
    private int expectUid = -1;
    private String expectApp = null;
    private long gattAt = 0;
    private boolean ancsReady = false;
    private long lastRssiAt = 0;
    private int weak = 0;
    private int countdown = -1;
    private int tickN = 0;
    private final Map<String, Integer> uidOf = new HashMap();
    private final Map<Integer, String> keyOf = new HashMap();
    private final AdvertiseCallback advCallback = new AdvertiseCallback() { // from class: com.novera.ana.AncsLink.1
        @Override // android.bluetooth.le.AdvertiseCallback
        public void onStartFailure(int i) {
            AncsLink.this.say("Couldn't start Bluetooth advertising (error " + i + ")");
        }
    };
    private final BluetoothGattServerCallback serverCallback = new AnonymousClass2();
    private final BroadcastReceiver bondChanged = new AnonymousClass3();
    private final BluetoothGattCallback clientCallback = new AnonymousClass4();
    private final Map<String, String[]> billParts = new HashMap();
    private final Map<String, String[]> chatParts = new HashMap();
    private final Runnable tick = new Runnable() { // from class: com.novera.ana.AncsLink.5
        @Override // java.lang.Runnable
        public void run() {
            AncsLink.this.main.postDelayed(this, 1000L);
            long currentTimeMillis = System.currentTimeMillis();
            if (AncsLink.this.gatt == null || !AncsLink.this.ancsReady) {
                AncsLink.this.countdown = -1;
                return;
            }
            AncsLink ancsLink = AncsLink.this;
            int i = ancsLink.tickN + 1;
            ancsLink.tickN = i;
            if (i % 5 == 0) {
                try {
                    AncsLink.this.gatt.readRemoteRssi();
                } catch (SecurityException unused) {
                }
            }
            if (currentTimeMillis - AncsLink.this.lastRssiAt <= 12000 && AncsLink.this.weak < 3) {
                if (AncsLink.this.countdown >= 0) {
                    AncsLink.this.countdown = -1;
                    AncsLink.this.say("Receiving your iPhone's notifications");
                    return;
                }
                return;
            }
            if (AncsLink.this.countdown < 0) {
                AncsLink.this.countdown = 30;
            }
            if (AncsLink.this.countdown > 0) {
                AncsLink ancsLink2 = AncsLink.this;
                ancsLink2.say("iPhone out of range: disconnecting in " + ancsLink2.countdown + " s");
                AncsLink ancsLink3 = AncsLink.this;
                ancsLink3.countdown = ancsLink3.countdown + (-1);
                return;
            }
            AncsLink.this.countdown = -1;
            AncsLink.this.dropAll();
            AncsLink.outSince = currentTimeMillis;
            AncsLink.this.say("iPhone out of range since " + new SimpleDateFormat("h:mm a", Locale.US).format(new Date(currentTimeMillis)) + ": it reconnects when it's back");
        }
    };

    @Override // android.app.Service
    public IBinder onBind(Intent intent) {
        return null;
    }

    static void start(Context context) {
        Intent intent = new Intent(context, (Class<?>) AncsLink.class);
        if (Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    static void stop(Context context) {
        context.stopService(new Intent(context, (Class<?>) AncsLink.class));
        state = "Off";
    }

    @Override // android.app.Service
    public int onStartCommand(Intent intent, int i, int i2) {
        if (instance != null) {
            return 1;
        }
        instance = this;
        foreground();
        SharedPreferences.Editor edit = prefs().edit();
        Iterator<String> it = AnaLog.readAll(this).iterator();
        while (it.hasNext()) {
            String[] split = it.next().split("\t", -1);
            if (split.length >= 7 && split[0].equals("IPHONE")) {
                this.seen.add(split[6]);
                if (split[3].length() > 0) {
                    if (!prefs().contains("ios_" + split[3])) {
                        edit.putString("ios_" + split[3], nameFromId(split[3]));
                    }
                }
            }
        }
        edit.apply();
        registerReceiver(this.bondChanged, new IntentFilter("android.bluetooth.device.action.BOND_STATE_CHANGED"));
        begin();
        this.main.postDelayed(this.tick, 1000L);
        return 1;
    }

    @Override // android.app.Service
    public void onDestroy() {
        instance = null;
        this.main.removeCallbacks(this.tick);
        linkedAt = 0L;
        try {
            unregisterReceiver(this.bondChanged);
        } catch (Exception unused) {
        }
        try {
            BluetoothLeAdvertiser bluetoothLeAdvertiser = this.advertiser;
            if (bluetoothLeAdvertiser != null) {
                bluetoothLeAdvertiser.stopAdvertising(this.advCallback);
            }
        } catch (Exception unused2) {
        }
        try {
            BluetoothGatt bluetoothGatt = this.gatt;
            if (bluetoothGatt != null) {
                bluetoothGatt.close();
            }
        } catch (Exception unused3) {
        }
        try {
            BluetoothGattServer bluetoothGattServer = this.server;
            if (bluetoothGattServer != null) {
                bluetoothGattServer.close();
            }
        } catch (Exception unused4) {
        }
        state = "Off";
        MainActivity.poke();
        super.onDestroy();
    }

    private void foreground() {
        Notification.Builder builder;
        NotificationManager notificationManager = (NotificationManager) getSystemService("notification");
        if (Build.VERSION.SDK_INT >= 26) {
            notificationManager.createNotificationChannel(new NotificationChannel(CHANNEL, "iPhone notifications", 2));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        builder.setSmallIcon(R.drawable.stat_sys_data_bluetooth).setContentTitle("ANA: iPhone notifications").setContentText("Receiving your iPhone's notifications over Bluetooth").setContentIntent(PendingIntent.getActivity(this, 0, new Intent(this, (Class<?>) MainActivity.class), 67108864)).setOngoing(true);
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(7, builder.build(), 16);
        } else {
            startForeground(7, builder.build());
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void say(String str) {
        state = str;
        MainActivity.poke();
    }

    private void begin() {
        try {
            BluetoothManager bluetoothManager = (BluetoothManager) getSystemService("bluetooth");
            this.bm = bluetoothManager;
            BluetoothAdapter adapter = bluetoothManager == null ? null : bluetoothManager.getAdapter();
            if (adapter == null) {
                say("No Bluetooth on this device");
                return;
            }
            if (!adapter.isEnabled()) {
                say("Bluetooth is off: turn it on, then switch this off and on");
                return;
            }
            BluetoothLeAdvertiser bluetoothLeAdvertiser = adapter.getBluetoothLeAdvertiser();
            this.advertiser = bluetoothLeAdvertiser;
            if (bluetoothLeAdvertiser != null && adapter.isMultipleAdvertisementSupported()) {
                this.server = this.bm.openGattServer(this, this.serverCallback);
                UUID uuid = ANA_SERVICE;
                BluetoothGattService bluetoothGattService = new BluetoothGattService(uuid, 0);
                bluetoothGattService.addCharacteristic(new BluetoothGattCharacteristic(ANA_NAME, 2, 2));
                BluetoothGattCharacteristic bluetoothGattCharacteristic = new BluetoothGattCharacteristic(ANA_RELAY, 16, 2);
                this.relay = bluetoothGattCharacteristic;
                bluetoothGattCharacteristic.addDescriptor(new BluetoothGattDescriptor(CCCD, 34));
                bluetoothGattService.addCharacteristic(this.relay);
                bluetoothGattService.addCharacteristic(new BluetoothGattCharacteristic(ANA_CONTROL, 8, 32));
                this.server.addService(bluetoothGattService);
                AdvertiseSettings build = new AdvertiseSettings.Builder().setAdvertiseMode(1).setTxPowerLevel(2).setConnectable(true).setTimeout(0).build();
                AdvertiseData build2 = new AdvertiseData.Builder().setIncludeDeviceName(false).addServiceUuid(new ParcelUuid(uuid)).build();
                AdvertiseData.Builder includeDeviceName = new AdvertiseData.Builder().setIncludeDeviceName(false);
                if (Build.VERSION.SDK_INT >= 31) {
                    includeDeviceName.addServiceSolicitationUuid(new ParcelUuid(ANCS));
                }
                this.advS = build;
                this.advData = build2;
                AdvertiseData build3 = includeDeviceName.build();
                this.advResp = build3;
                this.advertiser.startAdvertising(this.advS, this.advData, build3, this.advCallback);
                say("Waiting for the iPhone: open ANA on the iPhone, Settings > Connect to Android");
                return;
            }
            say("This device can't act as a Bluetooth accessory (no BLE peripheral mode)");
        } catch (SecurityException unused) {
            say("Needs Bluetooth permission: switch this off and on, and allow it");
        } catch (Exception e) {
            say("Bluetooth error: " + e.getMessage());
        }
    }

    /* renamed from: com.novera.ana.AncsLink$2, reason: invalid class name */
    class AnonymousClass2 extends BluetoothGattServerCallback {
        AnonymousClass2() {
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onConnectionStateChange(final BluetoothDevice bluetoothDevice, int i, int i2) {
            if (i2 == 2) {
                if (AncsLink.this.gatt != null) {
                    if (!bluetoothDevice.equals(AncsLink.this.phone) || System.currentTimeMillis() - AncsLink.this.gattAt < 5000) {
                        return;
                    } else {
                        AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda1
                            @Override // java.lang.Runnable
                            public final void run() {
                                AncsLink.AnonymousClass2.this.lambda$onConnectionStateChange$0();
                            }
                        });
                    }
                }
                AncsLink.this.phone = bluetoothDevice;
                AncsLink.this.say("iPhone connected: looking for its notifications...");
                AncsLink.this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda2
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.AnonymousClass2.this.lambda$onConnectionStateChange$1(bluetoothDevice);
                    }
                }, 400L);
                return;
            }
            if (i2 == 0) {
                if (AncsLink.this.phone == null || AncsLink.this.phone.equals(bluetoothDevice)) {
                    AncsLink.this.dropClient();
                    AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda3
                        @Override // java.lang.Runnable
                        public final void run() {
                            AncsLink.AnonymousClass2.this.lambda$onConnectionStateChange$2();
                        }
                    });
                    AncsLink.this.say("iPhone disconnected: waiting for it to come back");
                }
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onConnectionStateChange$0() {
            AncsLink.this.dropClient();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onConnectionStateChange$1(BluetoothDevice bluetoothDevice) {
            try {
                AncsLink.this.gattAt = System.currentTimeMillis();
                AncsLink ancsLink = AncsLink.this;
                ancsLink.gatt = bluetoothDevice.connectGatt(ancsLink, false, ancsLink.clientCallback, 2);
            } catch (SecurityException unused) {
                AncsLink.this.say("Needs Bluetooth permission");
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onConnectionStateChange$2() {
            AncsLink.this.relayTo = null;
            AncsLink.this.clearRelay();
            AncsLink.this.mtu = 23;
            Bills.toIphone = null;
            AncsLink.linkedAt = 0L;
            AncsLink.this.readvertise();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onMtuChanged$3(int i) {
            AncsLink.this.mtu = i;
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onMtuChanged(BluetoothDevice bluetoothDevice, final int i) {
            AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda5
                @Override // java.lang.Runnable
                public final void run() {
                    AncsLink.AnonymousClass2.this.lambda$onMtuChanged$3(i);
                }
            });
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onDescriptorWriteRequest(final BluetoothDevice bluetoothDevice, int i, BluetoothGattDescriptor bluetoothGattDescriptor, boolean z, boolean z2, int i2, byte[] bArr) {
            final boolean z3 = false;
            if (bArr != null && bArr.length > 0 && (bArr[0] & 1) != 0) {
                z3 = true;
            }
            if (AncsLink.this.phone == null || bluetoothDevice.equals(AncsLink.this.phone)) {
                AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda0
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.AnonymousClass2.this.lambda$onDescriptorWriteRequest$4(z3, bluetoothDevice);
                    }
                });
            }
            if (z2) {
                try {
                    AncsLink.this.server.sendResponse(bluetoothDevice, i, 0, 0, null);
                } catch (SecurityException unused) {
                }
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onDescriptorWriteRequest$4(boolean z, BluetoothDevice bluetoothDevice) {
            AncsLink ancsLink = AncsLink.this;
            if (!z) {
                bluetoothDevice = null;
            }
            ancsLink.relayTo = bluetoothDevice;
            if (!z) {
                AncsLink.this.clearRelay();
            }
            if (z && AncsLink.linkedAt == 0) {
                AncsLink.linkedAt = System.currentTimeMillis();
            }
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onDescriptorReadRequest(BluetoothDevice bluetoothDevice, int i, int i2, BluetoothGattDescriptor bluetoothGattDescriptor) {
            try {
                AncsLink.this.server.sendResponse(bluetoothDevice, i, 0, 0, AncsLink.this.relayTo != null ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE);
            } catch (SecurityException unused) {
            }
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onCharacteristicWriteRequest(final BluetoothDevice bluetoothDevice, int i, BluetoothGattCharacteristic bluetoothGattCharacteristic, boolean z, boolean z2, int i2, byte[] bArr) {
            if (z2) {
                try {
                    AncsLink.this.server.sendResponse(bluetoothDevice, i, 0, 0, null);
                } catch (SecurityException unused) {
                }
            }
            if (bArr == null || !bluetoothGattCharacteristic.getUuid().equals(AncsLink.ANA_CONTROL)) {
                return;
            }
            if (AncsLink.this.phone == null || bluetoothDevice.equals(AncsLink.this.phone)) {
                final String str = new String(bArr, StandardCharsets.UTF_8);
                AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda6
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.AnonymousClass2.this.lambda$onCharacteristicWriteRequest$5(bluetoothDevice, str);
                    }
                });
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onCharacteristicWriteRequest$5(BluetoothDevice bluetoothDevice, String str) {
            long j;
            AncsLink.this.relayTo = bluetoothDevice;
            if (str.startsWith("since:")) {
                try {
                    j = Long.parseLong(str.substring(6).trim());
                } catch (NumberFormatException unused) {
                    j = 0;
                }
                AncsLink.this.catchUp(j);
            } else {
                if (str.startsWith("bsch:")) {
                    AncsLink.this.billPiece(str.substring(5));
                    return;
                }
                if (str.startsWith("chat:")) {
                    AncsLink.this.chatPiece(str.substring(5));
                } else if (str.startsWith("clearapp:")) {
                    AncsLink.this.dismissApp(str.substring(9).trim());
                } else if (str.startsWith("clear:")) {
                    AncsLink.this.dismiss(str.substring(6));
                }
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onNotificationSent$6() {
            AncsLink.this.sending = false;
            AncsLink.this.pump();
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onNotificationSent(BluetoothDevice bluetoothDevice, int i) {
            AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$2$$ExternalSyntheticLambda4
                @Override // java.lang.Runnable
                public final void run() {
                    AncsLink.AnonymousClass2.this.lambda$onNotificationSent$6();
                }
            });
        }

        @Override // android.bluetooth.BluetoothGattServerCallback
        public void onCharacteristicReadRequest(BluetoothDevice bluetoothDevice, int i, int i2, BluetoothGattCharacteristic bluetoothGattCharacteristic) {
            byte[] bytes = ("ANA " + Build.MODEL).getBytes(StandardCharsets.UTF_8);
            try {
                AncsLink.this.server.sendResponse(bluetoothDevice, i, 0, i2, i2 >= bytes.length ? new byte[0] : Arrays.copyOfRange(bytes, i2, bytes.length));
            } catch (SecurityException unused) {
            }
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void dropClient() {
        try {
            BluetoothGatt bluetoothGatt = this.gatt;
            if (bluetoothGatt != null) {
                bluetoothGatt.disconnect();
            }
        } catch (Exception unused) {
        }
        try {
            BluetoothGatt bluetoothGatt2 = this.gatt;
            if (bluetoothGatt2 != null) {
                bluetoothGatt2.close();
            }
        } catch (Exception unused2) {
        }
        this.gatt = null;
        this.ancsReady = false;
        this.weak = 0;
        this.ds = null;
        this.ns = null;
        this.cp = null;
        this.requests.clear();
        this.waiting = false;
        this.answer.reset();
    }

    /* renamed from: com.novera.ana.AncsLink$3, reason: invalid class name */
    class AnonymousClass3 extends BroadcastReceiver {
        AnonymousClass3() {
        }

        @Override // android.content.BroadcastReceiver
        public void onReceive(Context context, Intent intent) {
            BluetoothDevice bluetoothDevice = (BluetoothDevice) intent.getParcelableExtra("android.bluetooth.device.extra.DEVICE");
            if (bluetoothDevice == null || AncsLink.this.phone == null || !bluetoothDevice.getAddress().equals(AncsLink.this.phone.getAddress())) {
                return;
            }
            int intExtra = intent.getIntExtra("android.bluetooth.device.extra.BOND_STATE", 10);
            if (intExtra == 12 && AncsLink.this.gatt != null) {
                AncsLink.this.say("Paired: subscribing to the iPhone's notifications...");
                AncsLink.this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$3$$ExternalSyntheticLambda0
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.AnonymousClass3.this.lambda$onReceive$0();
                    }
                }, 600L);
            } else if (intExtra == 11) {
                AncsLink.this.say("Pairing: accept it on the iPhone");
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onReceive$0() {
            try {
                AncsLink.this.gatt.discoverServices();
            } catch (SecurityException unused) {
            }
        }
    }

    /* renamed from: com.novera.ana.AncsLink$4, reason: invalid class name */
    class AnonymousClass4 extends BluetoothGattCallback {
        AnonymousClass4() {
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onConnectionStateChange(final BluetoothGatt bluetoothGatt, int i, int i2) {
            if (i2 == 2) {
                AncsLink.this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$4$$ExternalSyntheticLambda1
                    @Override // java.lang.Runnable
                    public final void run() {
                        bluetoothGatt.discoverServices();
                    }
                }, 600L);
            } else if (i2 == 0 && bluetoothGatt == AncsLink.this.gatt) {
                AncsLink.this.dropClient();
            }
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onServicesDiscovered(BluetoothGatt bluetoothGatt, int i) {
            BluetoothGattService service = bluetoothGatt.getService(AncsLink.ANCS);
            if (service == null) {
                if (AncsLink.this.phone != null && AncsLink.this.phone.getBondState() != 12) {
                    AncsLink.this.say("Pairing: tap Pair on the iPhone (open ANA BT there if no request shows)");
                    final BluetoothDevice bluetoothDevice = AncsLink.this.phone;
                    AncsLink.this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$4$$ExternalSyntheticLambda0
                        @Override // java.lang.Runnable
                        public final void run() {
                            AncsLink.AnonymousClass4.lambda$onServicesDiscovered$1(bluetoothDevice);
                        }
                    }, 10000L);
                    return;
                }
                AncsLink.this.say("Connected, but the iPhone isn't sharing notifications: in its Bluetooth settings, tap (i) next to this device and turn on Share System Notifications");
                return;
            }
            AncsLink.this.ns = service.getCharacteristic(AncsLink.NOTIF_SOURCE);
            AncsLink.this.cp = service.getCharacteristic(AncsLink.CONTROL_POINT);
            AncsLink.this.ds = service.getCharacteristic(AncsLink.DATA_SOURCE);
            if (AncsLink.this.ns == null || AncsLink.this.cp == null || AncsLink.this.ds == null) {
                AncsLink.this.say("The iPhone's notification service is incomplete");
            } else {
                AncsLink ancsLink = AncsLink.this;
                ancsLink.subscribe(bluetoothGatt, ancsLink.ds);
            }
        }

        static /* synthetic */ void lambda$onServicesDiscovered$1(BluetoothDevice bluetoothDevice) {
            try {
                if (bluetoothDevice.getBondState() == 10) {
                    bluetoothDevice.createBond();
                }
            } catch (SecurityException unused) {
            }
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onDescriptorWrite(BluetoothGatt bluetoothGatt, BluetoothGattDescriptor bluetoothGattDescriptor, int i) {
            if (i != 0) {
                AncsLink.this.say("Pairing: tap Pair on the iPhone (open ANA BT there if no request shows)");
                return;
            }
            if (bluetoothGattDescriptor.getCharacteristic().getUuid().equals(AncsLink.DATA_SOURCE)) {
                AncsLink ancsLink = AncsLink.this;
                ancsLink.subscribe(bluetoothGatt, ancsLink.ns);
            } else {
                AncsLink.this.ancsReady = true;
                AncsLink.this.lastRssiAt = System.currentTimeMillis();
                AncsLink.this.say("Receiving your iPhone's notifications");
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onCharacteristicWrite$2() {
            AncsLink.this.waiting = false;
            AncsLink.this.answer.reset();
            AncsLink.this.next();
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onCharacteristicWrite(BluetoothGatt bluetoothGatt, BluetoothGattCharacteristic bluetoothGattCharacteristic, int i) {
            if (i != 0) {
                AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$4$$ExternalSyntheticLambda3
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.AnonymousClass4.this.lambda$onCharacteristicWrite$2();
                    }
                });
            } else {
                if (AncsLink.this.waiting) {
                    return;
                }
                Handler handler = AncsLink.this.main;
                final AncsLink ancsLink = AncsLink.this;
                handler.post(new Runnable() { // from class: com.novera.ana.AncsLink$4$$ExternalSyntheticLambda4
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.this.next();
                    }
                });
            }
        }

        /* JADX INFO: Access modifiers changed from: private */
        public /* synthetic */ void lambda$onReadRemoteRssi$3(int i) {
            AncsLink.this.lastRssiAt = System.currentTimeMillis();
            AncsLink ancsLink = AncsLink.this;
            ancsLink.weak = i < -92 ? ancsLink.weak + 1 : 0;
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onReadRemoteRssi(BluetoothGatt bluetoothGatt, final int i, int i2) {
            if (i2 != 0) {
                return;
            }
            AncsLink.this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$4$$ExternalSyntheticLambda2
                @Override // java.lang.Runnable
                public final void run() {
                    AncsLink.AnonymousClass4.this.lambda$onReadRemoteRssi$3(i);
                }
            });
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onCharacteristicChanged(BluetoothGatt bluetoothGatt, BluetoothGattCharacteristic bluetoothGattCharacteristic, byte[] bArr) {
            AncsLink.this.changed(bluetoothGattCharacteristic.getUuid(), bArr);
        }

        @Override // android.bluetooth.BluetoothGattCallback
        public void onCharacteristicChanged(BluetoothGatt bluetoothGatt, BluetoothGattCharacteristic bluetoothGattCharacteristic) {
            AncsLink.this.changed(bluetoothGattCharacteristic.getUuid(), bluetoothGattCharacteristic.getValue());
        }
    }

    int dismissApp(String str) {
        int i = 0;
        if (str.isEmpty()) {
            return 0;
        }
        String str2 = "-" + str + "-";
        Iterator it = new ArrayList(this.uidOf.keySet()).iterator();
        while (it.hasNext()) {
            String str3 = (String) it.next();
            if (str3.contains(str2) && dismiss(str3)) {
                i++;
            }
        }
        return i;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void subscribe(BluetoothGatt bluetoothGatt, BluetoothGattCharacteristic bluetoothGattCharacteristic) {
        try {
            bluetoothGatt.setCharacteristicNotification(bluetoothGattCharacteristic, true);
            BluetoothGattDescriptor descriptor = bluetoothGattCharacteristic.getDescriptor(CCCD);
            if (descriptor == null) {
                return;
            }
            descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            bluetoothGatt.writeDescriptor(descriptor);
        } catch (SecurityException unused) {
            say("Needs Bluetooth permission");
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void changed(final UUID uuid, final byte[] bArr) {
        if (bArr == null) {
            return;
        }
        this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda3
            @Override // java.lang.Runnable
            public final void run() {
                AncsLink.this.lambda$changed$0(uuid, bArr);
            }
        });
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$changed$0(UUID uuid, byte[] bArr) {
        if (uuid.equals(NOTIF_SOURCE)) {
            notificationSource(bArr);
        } else if (uuid.equals(DATA_SOURCE)) {
            dataSource(bArr);
        }
    }

    private void notificationSource(byte[] bArr) {
        if (bArr.length < 8) {
            return;
        }
        byte b = bArr[0];
        if (b == 2) {
            String remove = this.keyOf.remove(Integer.valueOf(le32(bArr, 4)));
            if (remove != null) {
                this.uidOf.remove(remove);
                return;
            }
            return;
        }
        if (b != 0) {
            return;
        }
        this.requests.add(new byte[]{0, bArr[4], bArr[5], bArr[6], bArr[7], 0, 1, -1, 0, 2, Byte.MIN_VALUE, 0, 3, -12, 1, 5});
        next();
    }

    private static int le32(byte[] bArr, int i) {
        return ((bArr[i + 3] & 255) << 24) | (bArr[i] & 255) | ((bArr[i + 1] & 255) << 8) | ((bArr[i + 2] & 255) << 16);
    }

    boolean dismiss(String str) {
        Integer num = this.uidOf.get(str);
        if (num == null || this.gatt == null || this.cp == null) {
            return false;
        }
        int intValue = num.intValue();
        final byte[] bArr = {2, (byte) intValue, (byte) (intValue >> 8), (byte) (intValue >> 16), (byte) (intValue >> 24), 1};
        this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda0
            @Override // java.lang.Runnable
            public final void run() {
                AncsLink.this.lambda$dismiss$1(bArr);
            }
        });
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$dismiss$1(byte[] bArr) {
        this.requests.addFirst(bArr);
        next();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void next() {
        if (this.waiting || this.gatt == null || this.cp == null || this.requests.isEmpty()) {
            return;
        }
        byte[] poll = this.requests.poll();
        byte b = poll[0];
        this.waiting = b != 2;
        this.expectUid = b == 0 ? le32(poll, 1) : -1;
        this.expectApp = poll[0] == 1 ? new String(poll, 1, Math.max(0, poll.length - 3), StandardCharsets.UTF_8) : null;
        this.answer.reset();
        final int i = this.reqSeq + 1;
        this.reqSeq = i;
        try {
            this.cp.setValue(poll);
            this.cp.setWriteType(2);
            if (this.gatt.writeCharacteristic(this.cp)) {
                if (this.waiting) {
                    this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda9
                        @Override // java.lang.Runnable
                        public final void run() {
                            AncsLink.this.lambda$next$2(i);
                        }
                    }, 4000L);
                }
            } else {
                this.waiting = false;
                this.requests.addFirst(poll);
                this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda8
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.this.next();
                    }
                }, 200L);
            }
        } catch (SecurityException unused) {
            this.waiting = false;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$next$2(int i) {
        if (this.waiting && this.reqSeq == i) {
            this.waiting = false;
            this.answer.reset();
            next();
        }
    }

    private void dataSource(byte[] bArr) {
        if (!this.waiting) {
            this.answer.reset();
            return;
        }
        this.answer.write(bArr, 0, bArr.length);
        byte[] byteArray = this.answer.toByteArray();
        if (byteArray.length < 1) {
            return;
        }
        byte b = byteArray[0];
        if (b == 0) {
            parseNotification(byteArray);
        } else {
            if (b == 1) {
                parseApp(byteArray);
                return;
            }
            this.waiting = false;
            this.answer.reset();
            next();
        }
    }

    private static int u16(byte[] bArr, int i) {
        return ((bArr[i + 1] & 255) << 8) | (bArr[i] & 255);
    }

    private void parseNotification(byte[] bArr) {
        if (bArr.length < 5) {
            return;
        }
        if (this.expectUid != -1 && le32(bArr, 1) != this.expectUid) {
            this.answer.reset();
            return;
        }
        String[] strArr = new String[6];
        int i = 5;
        for (int i2 = 0; i2 < 5; i2++) {
            int i3 = i + 3;
            if (i3 > bArr.length) {
                return;
            }
            int i4 = bArr[i] & 255;
            int u16 = u16(bArr, i + 1);
            if (i3 + u16 > bArr.length) {
                return;
            }
            if (i4 < 6) {
                strArr[i4] = new String(bArr, i3, u16, StandardCharsets.UTF_8);
            }
            i += u16 + 3;
        }
        this.waiting = false;
        this.answer.reset();
        record(strArr, le32(bArr, 1));
        next();
    }

    private void parseApp(byte[] bArr) {
        int i;
        int i2 = 1;
        while (i2 < bArr.length && bArr[i2] != 0) {
            i2++;
        }
        if (i2 >= bArr.length || (i = i2 + 4) > bArr.length) {
            return;
        }
        String str = new String(bArr, 1, i2 - 1, StandardCharsets.UTF_8);
        String str2 = this.expectApp;
        if (str2 != null && !str.equals(str2)) {
            this.answer.reset();
            return;
        }
        int u16 = u16(bArr, i2 + 2);
        if (i + u16 > bArr.length) {
            return;
        }
        String str3 = new String(bArr, i, u16, StandardCharsets.UTF_8);
        this.waiting = false;
        this.answer.reset();
        if (str3.length() > 0) {
            prefs().edit().putString("ios_".concat(str), str3).putString("iosreal_".concat(str), "1").apply();
        }
        MainActivity.poke();
        next();
    }

    static String nameFromId(String str) {
        String[] split = str.split("\\.");
        String str2 = split.length > 0 ? split[split.length - 1] : str;
        if (str2.length() == 0) {
            return str;
        }
        return Character.toUpperCase(str2.charAt(0)) + str2.substring(1);
    }

    private void relayLine(String str) {
        if (this.relayTo == null) {
            return;
        }
        String[] split = str.split("\t", -1);
        String str2 = "";
        if (split.length > 3) {
            str2 = prefs().getString("ios_" + split[3], "");
        }
        this.lines.add((str + "\t" + AnaLog.clean(str2) + "\n").getBytes(StandardCharsets.UTF_8));
        pump();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void billPiece(String str) {
        String[] split = str.split(":", 4);
        if (split.length < 4) {
            return;
        }
        try {
            int parseInt = Integer.parseInt(split[1]);
            int parseInt2 = Integer.parseInt(split[2]);
            if (parseInt2 < 1 || parseInt2 > 200 || parseInt < 0 || parseInt >= parseInt2) {
                return;
            }
            String[] strArr = this.billParts.get(split[0]);
            if (strArr == null || strArr.length != parseInt2) {
                strArr = new String[parseInt2];
                this.billParts.put(split[0], strArr);
            }
            strArr[parseInt] = split[3];
            StringBuilder sb = new StringBuilder();
            for (String str2 : strArr) {
                if (str2 == null) {
                    return;
                }
                sb.append(str2);
            }
            this.billParts.remove(split[0]);
            final byte[] decode = Base64.decode(sb.toString(), 0);
            new Thread(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda1
                @Override // java.lang.Runnable
                public final void run() {
                    AncsLink.this.lambda$billPiece$3(decode);
                }
            }).start();
        } catch (NumberFormatException | Exception unused) {
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$billPiece$3(byte[] bArr) {
        String schedule = Bills.schedule(this, bArr, "your iPhone");
        if (schedule != null) {
            say(schedule);
        }
        BillsUi.onNotification(this);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void chatPiece(String str) {
        String[] split = str.split(":", 4);
        if (split.length < 4) {
            return;
        }
        try {
            int parseInt = Integer.parseInt(split[1]);
            int parseInt2 = Integer.parseInt(split[2]);
            if (parseInt2 < 1 || parseInt2 > 40 || parseInt < 0 || parseInt >= parseInt2) {
                return;
            }
            String[] strArr = this.chatParts.get(split[0]);
            if (strArr == null || strArr.length != parseInt2) {
                strArr = new String[parseInt2];
                this.chatParts.put(split[0], strArr);
            }
            strArr[parseInt] = split[3];
            StringBuilder sb = new StringBuilder();
            for (String str2 : strArr) {
                if (str2 == null) {
                    return;
                }
                sb.append(str2);
            }
            this.chatParts.remove(split[0]);
            final byte[] decode = Base64.decode(sb.toString(), 0);
            new Thread(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda5
                @Override // java.lang.Runnable
                public final void run() {
                    Chat.receive(this, decode, "Bluetooth");
                }
            }).start();
        } catch (NumberFormatException | Exception unused) {
        }
    }

    static boolean sendChat(byte[] bArr) {
        final AncsLink ancsLink = instance;
        if (ancsLink == null || ancsLink.relayTo == null) {
            return false;
        }
        final String encodeToString = Base64.encodeToString(bArr, 2);
        ancsLink.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda2
            @Override // java.lang.Runnable
            public final void run() {
                AncsLink.this.sendRaw("CHAT\t" + encodeToString + "\n");
            }
        });
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$billOk$6(String str) {
        sendRaw("BILLOK\t" + str + "\n");
    }

    void billOk(final String str) {
        this.main.post(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda10
            @Override // java.lang.Runnable
            public final void run() {
                AncsLink.this.lambda$billOk$6(str);
            }
        });
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void sendRaw(String str) {
        if (this.relayTo == null) {
            return;
        }
        this.lines.add(str.getBytes(StandardCharsets.UTF_8));
        pump();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void catchUp(long j) {
        long j2;
        this.lines.clear();
        Bills.toIphone = new Consumer() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda4
            @Override // java.util.function.Consumer
            public final void accept(Object obj) {
                AncsLink.this.billOk((String) obj);
            }
        };
        Iterator<String> it = Bills.confirmations(this).iterator();
        while (it.hasNext()) {
            sendRaw("BILLOK\t" + it.next() + "\n");
        }
        ArrayList arrayList = new ArrayList();
        for (String str : AnaLog.readAll(this)) {
            String[] split = str.split("\t", -1);
            if (split.length >= 8 && split[0].equals("IPHONE")) {
                try {
                    j2 = Long.parseLong(split[2]);
                } catch (NumberFormatException unused) {
                    j2 = 0;
                }
                if (j2 > j) {
                    if (split.length < 9) {
                        str = str + "\t0";
                    }
                    arrayList.add(str);
                }
            }
        }
        int max = Math.max(0, arrayList.size() - 500);
        for (int i = max; i < arrayList.size(); i++) {
            relayLine((String) arrayList.get(i));
        }
        int size = arrayList.size() - max;
        if (size > 0) {
            say("Receiving your iPhone's notifications (sent " + size + " back to ANA on the iPhone)");
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void pump() {
        if (this.sending || this.relayTo == null || this.server == null || this.relay == null) {
            return;
        }
        byte[] bArr = this.curLine;
        if (bArr == null || this.curOff >= bArr.length) {
            byte[] poll = this.lines.poll();
            this.curLine = poll;
            this.curOff = 0;
            if (poll == null) {
                return;
            }
        }
        int max = Math.max(20, this.mtu - 3);
        byte[] bArr2 = this.curLine;
        int i = this.curOff;
        byte[] copyOfRange = Arrays.copyOfRange(bArr2, i, Math.min(bArr2.length, max + i));
        this.sending = true;
        try {
            this.relay.setValue(copyOfRange);
            if (!this.server.notifyCharacteristicChanged(this.relayTo, this.relay, false)) {
                this.sending = false;
                this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda6
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.this.pump();
                    }
                }, 100L);
            } else {
                this.curOff += copyOfRange.length;
                final int i2 = this.sendSeq + 1;
                this.sendSeq = i2;
                this.main.postDelayed(new Runnable() { // from class: com.novera.ana.AncsLink$$ExternalSyntheticLambda7
                    @Override // java.lang.Runnable
                    public final void run() {
                        AncsLink.this.lambda$pump$7(i2);
                    }
                }, 2000L);
            }
        } catch (SecurityException unused) {
            this.sending = false;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public /* synthetic */ void lambda$pump$7(int i) {
        if (this.sending && this.sendSeq == i) {
            this.sending = false;
            pump();
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void clearRelay() {
        this.lines.clear();
        this.curLine = null;
        this.curOff = 0;
        this.sending = false;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void readvertise() {
        BluetoothLeAdvertiser bluetoothLeAdvertiser = this.advertiser;
        if (bluetoothLeAdvertiser == null || this.advS == null) {
            return;
        }
        try {
            bluetoothLeAdvertiser.stopAdvertising(this.advCallback);
        } catch (Exception unused) {
        }
        try {
            this.advertiser.startAdvertising(this.advS, this.advData, this.advResp, this.advCallback);
        } catch (Exception unused2) {
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void dropAll() {
        BluetoothDevice bluetoothDevice = this.phone;
        dropClient();
        this.relayTo = null;
        clearRelay();
        linkedAt = 0L;
        Bills.toIphone = null;
        if (bluetoothDevice != null) {
            try {
                BluetoothGattServer bluetoothGattServer = this.server;
                if (bluetoothGattServer != null) {
                    bluetoothGattServer.cancelConnection(bluetoothDevice);
                }
            } catch (Exception unused) {
            }
        }
        readvertise();
    }

    static String times() {
        String str;
        long currentTimeMillis = System.currentTimeMillis();
        if (linkedAt == 0) {
            return "";
        }
        String str2 = "Linked " + ago(currentTimeMillis - linkedAt);
        if (lastNotifAt <= 0) {
            return str2;
        }
        if (currentTimeMillis - lastNotifAt < 60000) {
            str = "just now";
        } else {
            str = ago(currentTimeMillis - lastNotifAt) + " ago";
        }
        return str2 + " · last notification " + str;
    }

    private static String ago(long j) {
        long j2 = j / 60000;
        if (j2 < 1) {
            return "under a minute";
        }
        if (j2 < 60) {
            return j2 + " min";
        }
        return (j2 / 60) + " h " + (j2 % 60) + " m";
    }

    private SharedPreferences prefs() {
        return getSharedPreferences("ana", 0);
    }

    private void record(String[] strArr, int i) {
        long j;
        String str;
        String str2;
        long j2;
        String str3 = strArr[0];
        String str4 = str3 == null ? "" : str3;
        String str5 = strArr[1];
        String str6 = str5 == null ? "" : str5;
        String str7 = strArr[2];
        if (str7 == null) {
            str7 = "";
        }
        String str8 = strArr[3];
        if (str8 == null) {
            str8 = "";
        }
        String str9 = strArr[5];
        String str10 = str9 != null ? str9 : "";
        long currentTimeMillis = System.currentTimeMillis();
        try {
            Date parse = new SimpleDateFormat("yyyyMMdd'T'HHmmss", Locale.US).parse(str10);
            j = parse != null ? parse.getTime() : currentTimeMillis;
        } catch (Exception unused) {
            j = currentTimeMillis;
        }
        if (str7.length() > 0) {
            str8 = str7 + " / " + str8;
        }
        String str11 = str8;
        String str12 = "ios-" + str10 + "-" + str4 + "-" + Integer.toHexString((str6 + "\n" + str11).hashCode());
        lastNotifAt = System.currentTimeMillis();
        this.uidOf.put(str12, Integer.valueOf(i));
        this.keyOf.put(Integer.valueOf(i), str12);
        if (this.seen.add(str12)) {
            if ("0".equals(prefs().getString("p_capture", "1"))) {
                str = str12;
                str2 = str11;
                j2 = j;
            } else {
                str = str12;
                str2 = str11;
                j2 = j;
                AnaLog.append(this, "IPHONE", j, str4, str6, str11, str, Math.max(0L, currentTimeMillis - j));
                if ("com.sixdays.trust".equals(str4)) {
                    Wallets.refreshAll(this);
                }
                BillsUi.onNotification(this);
                MainActivity.poke();
            }
            relayLine(AnaLog.clean("IPHONE") + "\t" + new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date(j2)) + "\t" + j2 + "\t" + AnaLog.clean(str4) + "\t" + AnaLog.clean(str6) + "\t" + AnaLog.clean(str2) + "\t" + AnaLog.clean(str) + "\t" + Math.max(0L, currentTimeMillis - j2) + "\t0");
            if (str4.length() > 0) {
                if (!prefs().contains("ios_" + str4)) {
                    prefs().edit().putString("ios_" + str4, nameFromId(str4)).apply();
                    MainActivity.poke();
                }
            }
            if (str4.length() > 0) {
                if (prefs().contains("iosreal_" + str4) || !this.askedName.add(str4)) {
                    return;
                }
                byte[] bytes = str4.getBytes(StandardCharsets.UTF_8);
                byte[] bArr = new byte[bytes.length + 3];
                bArr[0] = 1;
                System.arraycopy(bytes, 0, bArr, 1, bytes.length);
                bArr[bytes.length + 1] = 0;
                bArr[bytes.length + 2] = 0;
                this.requests.add(bArr);
            }
        }
    }
}
