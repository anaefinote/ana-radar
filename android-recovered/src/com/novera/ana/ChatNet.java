package com.novera.ana;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import com.novera.ana.ChatNet;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

/* loaded from: classes.dex */
final class ChatNet {
    static final int PORT = 47474;
    private static final String TYPE = "_anachat._tcp.";
    private static NsdManager nsd;
    private static NsdManager.RegistrationListener reg;
    private static ServerSocket server;
    private static final Handler ui = new Handler(Looper.getMainLooper());

    interface Found {
        void found(List<Peer> list);
    }

    ChatNet() {
    }

    static final class Peer {
        final String host;
        final String name;
        final int port;

        Peer(String str, String str2, int i) {
            this.name = str;
            this.host = str2;
            this.port = i;
        }
    }

    static synchronized void start(Context context) {
        synchronized (ChatNet.class) {
            if (server != null) {
                return;
            }
            final Context applicationContext = context.getApplicationContext();
            new Thread(new Runnable() { // from class: com.novera.ana.ChatNet$$ExternalSyntheticLambda1
                @Override // java.lang.Runnable
                public final void run() {
                    ChatNet.lambda$start$1(applicationContext);
                }
            }).start();
        }
    }

    static /* synthetic */ void lambda$start$1(final Context context) {
        try {
            ServerSocket serverSocket = new ServerSocket();
            serverSocket.setReuseAddress(true);
            serverSocket.bind(new InetSocketAddress(PORT));
            synchronized (ChatNet.class) {
                server = serverSocket;
            }
            announce(context);
            while (!serverSocket.isClosed()) {
                final Socket accept = serverSocket.accept();
                new Thread(new Runnable() { // from class: com.novera.ana.ChatNet$$ExternalSyntheticLambda0
                    @Override // java.lang.Runnable
                    public final void run() {
                        ChatNet.take(context, accept);
                    }
                }).start();
            }
            synchronized (ChatNet.class) {
                server = null;
            }
        } catch (Exception unused) {
            synchronized (ChatNet.class) {
                server = null;
            }
        } catch (Throwable th) {
            synchronized (ChatNet.class) {
                server = null;
                throw th;
            }
        }
    }

    static synchronized void stop() {
        NsdManager.RegistrationListener registrationListener;
        synchronized (ChatNet.class) {
            try {
                ServerSocket serverSocket = server;
                if (serverSocket != null) {
                    serverSocket.close();
                }
            } catch (Exception unused) {
            }
            server = null;
            try {
                NsdManager nsdManager = nsd;
                if (nsdManager != null && (registrationListener = reg) != null) {
                    nsdManager.unregisterService(registrationListener);
                }
            } catch (Exception unused2) {
            }
            reg = null;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static void take(Context context, Socket socket) {
        String readLine;
        String str;
        try {
            socket.setSoTimeout(8000);
            readLine = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII)).readLine();
        } catch (Exception unused) {
        } catch (Throwable th) {
            try {
                socket.close();
            } catch (Exception unused2) {
            }
            throw th;
        }
        try {
            if (readLine != null && readLine.length() <= 8000) {
                String receive = Chat.receive(context, Base64.decode(readLine.trim(), 0), isTailnet(socket.getInetAddress()) ? "Internet" : "Wi-Fi");
                if (receive == null) {
                    str = "OK";
                } else {
                    str = "NO " + receive;
                }
                OutputStream outputStream = socket.getOutputStream();
                outputStream.write((str + "\n").getBytes(StandardCharsets.UTF_8));
                outputStream.flush();
                socket.close();
                return;
            }
            socket.close();
            return;
        } catch (Exception unused3) {
            return;
        }
        str = "NO too long";
        OutputStream outputStream2 = socket.getOutputStream();
        outputStream2.write((str + "\n").getBytes(StandardCharsets.UTF_8));
        outputStream2.flush();
    }

    static boolean isTailnet(InetAddress inetAddress) {
        byte[] address = inetAddress.getAddress();
        if (address.length != 4 || (address[0] & 255) != 100) {
            return false;
        }
        byte b = address[1];
        return (b & 255) >= 64 && (b & 255) <= 127;
    }

    private static void announce(Context context) {
        try {
            nsd = (NsdManager) context.getSystemService("servicediscovery");
            NsdServiceInfo nsdServiceInfo = new NsdServiceInfo();
            nsdServiceInfo.setServiceName(tag() + " " + Chat.myName(context));
            nsdServiceInfo.setServiceType(TYPE);
            nsdServiceInfo.setPort(PORT);
            NsdManager.RegistrationListener registrationListener = new NsdManager.RegistrationListener() { // from class: com.novera.ana.ChatNet.1
                @Override // android.net.nsd.NsdManager.RegistrationListener
                public void onRegistrationFailed(NsdServiceInfo nsdServiceInfo2, int i) {
                }

                @Override // android.net.nsd.NsdManager.RegistrationListener
                public void onServiceRegistered(NsdServiceInfo nsdServiceInfo2) {
                }

                @Override // android.net.nsd.NsdManager.RegistrationListener
                public void onServiceUnregistered(NsdServiceInfo nsdServiceInfo2) {
                }

                @Override // android.net.nsd.NsdManager.RegistrationListener
                public void onUnregistrationFailed(NsdServiceInfo nsdServiceInfo2, int i) {
                }
            };
            reg = registrationListener;
            nsd.registerService(nsdServiceInfo, 1, registrationListener);
        } catch (Exception unused) {
        }
    }

    private static String tag() {
        String myKeyId = Chat.myKeyId();
        return myKeyId.length() >= 8 ? myKeyId.substring(0, 8) : "ana";
    }

    static void find(Context context, final Found found) {
        final NsdManager nsdManager = (NsdManager) context.getSystemService("servicediscovery");
        final ArrayList arrayList = new ArrayList();
        final ArrayDeque arrayDeque = new ArrayDeque();
        final boolean[] zArr = {false};
        String tag = tag();
        final Runnable[] runnableArr = new Runnable[1];
        runnableArr[0] = new Runnable() { // from class: com.novera.ana.ChatNet$$ExternalSyntheticLambda3
            @Override // java.lang.Runnable
            public final void run() {
                ChatNet.lambda$find$2(zArr, arrayDeque, nsdManager, runnableArr, arrayList);
            }
        };
        final AnonymousClass3 anonymousClass3 = new AnonymousClass3(tag, arrayDeque, runnableArr);
        try {
            nsdManager.discoverServices(TYPE, 1, anonymousClass3);
            ui.postDelayed(new Runnable() { // from class: com.novera.ana.ChatNet$$ExternalSyntheticLambda4
                @Override // java.lang.Runnable
                public final void run() {
                    ChatNet.lambda$find$4(nsdManager, anonymousClass3, found, arrayList);
                }
            }, 3000L);
        } catch (Exception unused) {
            found.found(arrayList);
        }
    }

    static /* synthetic */ void lambda$find$2(boolean[] zArr, ArrayDeque arrayDeque, NsdManager nsdManager, Runnable[] runnableArr, List list) {
        if (zArr[0] || arrayDeque.isEmpty()) {
            return;
        }
        zArr[0] = true;
        nsdManager.resolveService((NsdServiceInfo) arrayDeque.poll(), new AnonymousClass2(zArr, runnableArr, list));
    }

    /* renamed from: com.novera.ana.ChatNet$2, reason: invalid class name */
    class AnonymousClass2 implements NsdManager.ResolveListener {
        final /* synthetic */ Runnable[] val$nextResolve;
        final /* synthetic */ List val$peers;
        final /* synthetic */ boolean[] val$resolving;

        AnonymousClass2(boolean[] zArr, Runnable[] runnableArr, List list) {
            this.val$resolving = zArr;
            this.val$nextResolve = runnableArr;
            this.val$peers = list;
        }

        static /* synthetic */ void lambda$onResolveFailed$0(boolean[] zArr, Runnable[] runnableArr) {
            zArr[0] = false;
            runnableArr[0].run();
        }

        @Override // android.net.nsd.NsdManager.ResolveListener
        public void onResolveFailed(NsdServiceInfo nsdServiceInfo, int i) {
            Handler handler = ChatNet.ui;
            final boolean[] zArr = this.val$resolving;
            final Runnable[] runnableArr = this.val$nextResolve;
            handler.post(new Runnable() { // from class: com.novera.ana.ChatNet$2$$ExternalSyntheticLambda0
                @Override // java.lang.Runnable
                public final void run() {
                    ChatNet.AnonymousClass2.lambda$onResolveFailed$0(zArr, runnableArr);
                }
            });
        }

        @Override // android.net.nsd.NsdManager.ResolveListener
        public void onServiceResolved(final NsdServiceInfo nsdServiceInfo) {
            Handler handler = ChatNet.ui;
            final boolean[] zArr = this.val$resolving;
            final List list = this.val$peers;
            final Runnable[] runnableArr = this.val$nextResolve;
            handler.post(new Runnable() { // from class: com.novera.ana.ChatNet$2$$ExternalSyntheticLambda1
                @Override // java.lang.Runnable
                public final void run() {
                    ChatNet.AnonymousClass2.lambda$onServiceResolved$1(zArr, nsdServiceInfo, list, runnableArr);
                }
            });
        }

        static /* synthetic */ void lambda$onServiceResolved$1(boolean[] zArr, NsdServiceInfo nsdServiceInfo, List list, Runnable[] runnableArr) {
            zArr[0] = false;
            if (nsdServiceInfo.getHost() != null) {
                String serviceName = nsdServiceInfo.getServiceName();
                int indexOf = serviceName.indexOf(32);
                if (indexOf > 0) {
                    serviceName = serviceName.substring(indexOf + 1);
                }
                list.add(new Peer(serviceName, nsdServiceInfo.getHost().getHostAddress(), nsdServiceInfo.getPort()));
            }
            runnableArr[0].run();
        }
    }

    /* renamed from: com.novera.ana.ChatNet$3, reason: invalid class name */
    class AnonymousClass3 implements NsdManager.DiscoveryListener {
        final /* synthetic */ String val$me;
        final /* synthetic */ Runnable[] val$nextResolve;
        final /* synthetic */ ArrayDeque val$toResolve;

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onDiscoveryStarted(String str) {
        }

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onDiscoveryStopped(String str) {
        }

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onServiceLost(NsdServiceInfo nsdServiceInfo) {
        }

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onStartDiscoveryFailed(String str, int i) {
        }

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onStopDiscoveryFailed(String str, int i) {
        }

        AnonymousClass3(String str, ArrayDeque arrayDeque, Runnable[] runnableArr) {
            this.val$me = str;
            this.val$toResolve = arrayDeque;
            this.val$nextResolve = runnableArr;
        }

        @Override // android.net.nsd.NsdManager.DiscoveryListener
        public void onServiceFound(final NsdServiceInfo nsdServiceInfo) {
            if (nsdServiceInfo.getServiceName().startsWith(this.val$me + " ")) {
                return;
            }
            Handler handler = ChatNet.ui;
            final ArrayDeque arrayDeque = this.val$toResolve;
            final Runnable[] runnableArr = this.val$nextResolve;
            handler.post(new Runnable() { // from class: com.novera.ana.ChatNet$3$$ExternalSyntheticLambda0
                @Override // java.lang.Runnable
                public final void run() {
                    ChatNet.AnonymousClass3.lambda$onServiceFound$0(arrayDeque, nsdServiceInfo, runnableArr);
                }
            });
        }

        static /* synthetic */ void lambda$onServiceFound$0(ArrayDeque arrayDeque, NsdServiceInfo nsdServiceInfo, Runnable[] runnableArr) {
            arrayDeque.add(nsdServiceInfo);
            runnableArr[0].run();
        }
    }

    static /* synthetic */ void lambda$find$4(NsdManager nsdManager, NsdManager.DiscoveryListener discoveryListener, final Found found, final List list) {
        try {
            nsdManager.stopServiceDiscovery(discoveryListener);
        } catch (Exception unused) {
        }
        ui.postDelayed(new Runnable() { // from class: com.novera.ana.ChatNet$$ExternalSyntheticLambda2
            @Override // java.lang.Runnable
            public final void run() {
                ChatNet.Found.this.found(list);
            }
        }, 800L);
    }

    static String send(String str, int i, byte[] bArr) {
        try {
            Socket socket = new Socket();
            try {
                socket.connect(new InetSocketAddress(str, i), 6000);
                socket.setSoTimeout(8000);
                OutputStream outputStream = socket.getOutputStream();
                outputStream.write((Base64.encodeToString(bArr, 2) + "\n").getBytes(StandardCharsets.US_ASCII));
                outputStream.flush();
                String readLine = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8)).readLine();
                if (readLine != null) {
                    if (readLine.equals("OK")) {
                        readLine = null;
                    } else if (readLine.startsWith("NO ")) {
                        readLine = readLine.substring(3);
                    }
                    socket.close();
                    return readLine;
                }
                socket.close();
                return "No answer";
            } finally {
            }
        } catch (Exception e) {
            return "Couldn't reach it (" + (e.getMessage() == null ? "no answer" : e.getMessage()) + ")";
        }
    }
}
