// Bridge to the Android side.
// On desktop (Processing 1.5.1) js stays null and the sketch runs in SIM mode.
// In the APK, index.html calls bindJavascript() with an object that forwards
// to the native code (the standard Processing.js pattern).

interface JavaScript {
  void scan();          // test #2: read notifications already in the shade
  void openAccess();    // open Android "Notification access" settings
  void manualEntry();   // native dialog -> comes back through onNotif("MANUAL", ...)
  void exportLog();     // share the plain-text log
  void exportPngmesh(String lines);  // share the given log lines as .pngmesh + .pngmesh.sha256
  void importFiles();   // file picker for .pngmesh (+ .sha256) files
  String watchList();   // the picked apps, one key per line
  void saveWatch(String list);
  String pref(String k);              // small saved settings ("skin", "lid"); "" when not set
  void setPref(String k, String v);
  String skinData(String file);       // a skin image from the APK, as a data: URL
  String appIcon(String pkg);         // APPify: the app's icon as a data: URL ("" if not installed)
  String appLabel(String pkg);        // the app's name ("" if not installed)
  String appCategory(String pkg);     // Social, Productivity ... ("" if none)
  boolean launchApp(String pkg);      // open the app
  boolean usageOk();                  // ACTIVE: "Usage access" is on
  void openUsageAccess();             // open Settings > Usage access
  String usageToday();                // "pkg TAB foreground-seconds TAB seconds-since-used" lines, most used first
  void appSettings(String pkg);       // STOP: the app's App info page (Force stop is there)
  int clearNotifs(String pkg);        // CLEAR: remove its notifications from the shade (-1: no access)
  boolean closeApp(String pkg);       // CLEAR: close it in the background (as swiping it away in Recents does)
  String appStatus(String pkg);       // EFINOTE: active / dormant / archived / uninstalled / installed
  void addReminder();                 // EFINOTE: a reminder of your own (date + time dialog)
  boolean glOk();                     // the ball can be shaded on the GPU (glball.js, WebGL)
  void glTextures(PGraphics front, PGraphics back);   // upload the ball's textures (back may be null)
  void glBall(float x, float y, int size, boolean redraw, float[] a);   // shade + draw the ball (Ball.pde)
  boolean gmOk();                     // EFINOTE maze balls on the GPU (glmaze.js)
  void gmDoors(int slot, PGraphics pg);   // a shell's doors / walls texture
  void gmBegin(int w, int h);
  void gmLayer(int slot, float[] a);  // one ball: cx, cy, R, rot[9], material, goo, dark, alpha, see
  void gmEnd(float x, float y);
  void gmBg(PGraphics pg);            // the background under the balls (flatBg)
  void gmClear();                     // clear the sketch's canvas to see-through (the GPU layer is behind it)
  void gmHide();                      // leaving Archive: hide the GPU layer
  int sdkInt();                       // Android's API level (33 = Android 13)
  void openOwnInfo();                 // this app's own App info page (Allow restricted settings is in its menu)
  void iphoneLink(boolean on);         // Android: receive the iPhone's notifications over Bluetooth. iOS: connect to Android ANA
  String iphoneState();
  String iphoneTimes();                // Android: "Linked 2 h 14 m · last notification 3 min ago" ("" when not linked)                // what that link is doing, in words ("Off" when off)
  void copyText(String t);             // to the clipboard (the reader's COPY)
  boolean iphoneDismiss(String key);  // clear that notification on the iPhone (Bluetooth); false if it's gone / no link
  void radarOn(boolean on);            // RADAR: scan for nearby ANA devices (and beacon this one)
  int radarCount();                    // how many ANA devices are nearby right now
  String radarPeers();                 // "count\tid8,rssi,age,name;..." strongest signal first
  void radarName(String n);            // the display name this phone broadcasts ("the name people see you as")
  void fenceCreate(String name, int radius, int durMin);  // ANA FENCE: become the host
  void fenceJoin(String fid);          // legacy alias of fenceRequest
  void fenceRequest(String fid);       // knock on a fence seen nearby (awaits the host's accept)
  void fenceAccept(String id);         // host: admit a knocker
  void fenceDecline(String id);        // host: turn a knocker away
  void fenceLeave();                   // drop out / stop knocking
  String fenceInfo();                  // "fid\tname\thue\trole\tmembers\tt0\tt1"; role 0 member/1 host/2 knocking; "" if none
  String fenceKnockers();              // host: "id,rssi,name;..." of those awaiting acceptance
  String fenceOffers();                // fences nearby I could knock on: "fid,hue,count;..."
  String walletText();                 // WATCH: the wallets and their activity, tab-separated lines
  boolean walletBusy();                // WATCH: checking right now
  void walletRefresh();                // WATCH: check every wallet now
  String lessonsText();                // LESSONS: one line per coin a lesson taught ANA (id, name, ticker, version, servers)
  void lessonsOpen();                  // LESSONS: the list (remove one, or import a lesson)
  String billsText();                  // BILLS: "open TAB eFLEX-from-bills TAB all"
  void billsOpen();
  void chatOpen();
  String chatList();                   // CHATNOTE: one line per message, oldest first: mine \t name \t key id \t age s \t route \t text
  void chatWrite();
  void findAdd();                      // FIND (experimental): type any app name, it becomes a tile
  void findRemove(String name);
  void chatClear(String key);          // CHATNOTE: forget one person's messages                    // CHATNOTE: the phone's own box to type in, then the route                     // CHATNOTE (experimental): messages, and send by Bluetooth / Wi-Fi / Internet / Light                    // BILLS: the list (new bill, paid bill, help, import)
  void walletAdd();                    // WATCH: the "watch an address" dialog
  void walletEdit(String id);          // WATCH: rename / copy / check / stop watching one wallet
  void walletReveal();                 // SUB-WATCH: Check Now was held: Face ID / fingerprint, then open
  boolean walletBack();                // SUB-WATCH: open right now
  void walletFront();                  // SUB-WATCH: close it (back to the front face)
  String walletTotals();               // GST: "all TAB front", the dollar value of every watched wallet / those on the front
  void gstSend(String name, String head, String rows, String pics);   // GST: share packs as .pngmesh + .sha256
  String gstInbox();                   // GST: packs received since last asked (tab-separated rows, one per line)
  String roundTripShare(String body);  // L2: write body as .pngmesh, pop share sheet, return its sha256 (iOS)
  String roundTripInbox();             // L2: sha256 of each round-trip .pngmesh imported back since last asked
  void sealExport(String body);        // FENCE v0.3: seal this payload as a .pngmesh + .sha256 and share it
  String coSignRequest(String body);   // L1: share A's co-sign commitment (classCoSign), return its sha256
  void coSignReply(String body);       // L1: share the finished moment + both sigs (classCoSignReply)
  String coSignInbox();                // L1: "REQ\t<body>" / "REPLY\t<body>" of each co-sign file imported, @@@-separated
  String lanPeers();                   // PRESENCE MESH: ANAs reachable on this Wi-Fi, "tag~name;tag~name;..." (reachable, not near)
  void tailAdd();                      // PRESENCE MESH: pop the "add a Tailscale peer by address" dialog
  String tailPeers();                  // PRESENCE MESH: known tailnet peers + live flag, "addr~name~1/0;..." (reachable via Tailscale)
  void gstAsk(String id, String title, String msg, String spec);     // GST: a dialog with fields ("label|default|number" lines)
  void gstPick(String id, String title, String items);               // GST: a list to pick from (one item per line)
  String flexKey();                    // FLEX: this phone's public signing key (base64)
  String flexSign(String text);        // FLEX: sign with this phone's key (base64 DER)
  boolean flexVerify(String key, String text, String sig);           // FLEX: check someone's signature
  String flexHash(String text);        // FLEX: sha256 (hex)
  String gstAnswer(String id);         // GST: "" while waiting, "C" cancelled, "O TAB values..." (or "O TAB index")
  String status();      // CONNECTED / ENABLED - WAITING TO BIND / NO ACCESS ...
  int screenW();        // device pixels (100% pixels)
  int screenH();
}

JavaScript js;

void bindJavascript(JavaScript j) {
  js = j;
  size(js.screenW(), js.screenH());
}
