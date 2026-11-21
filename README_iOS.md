# ANA Orbit on iPhone / iPad

ANA Relay plus APPify: the ball of the apps that notify you. Its own app (bundle ID com.novera.ana.ios.orbit), amber icon: it installs next to the others, with its own log and settings.


Core ANA: manual entry, the log, EXPORT and IMPORT .pngmesh (the same files as the Android app, both ways).
Your Processing sketch is the app, running in the iPhone's web view as it does on Android.

iOS doesn't let an app see other apps' notifications, icons or usage. So APPify, Notification / Usage access,
SCAN, CLEAR / STOP and LAUNCH are hidden. On Pulse, the round button (top right) is + : add an entry.

## Watch (v0.6): wallets, read-only

Settings has a third pill, **WATCH**: the wallets ANA keeps an eye on. Public addresses only (no keys, no
signing, no login); the phone reads public blockchain data itself (`ios/ANA/Wallets.swift`).

- **ether.fi Cash**: the Safe address (0x...) on Optimism. *Ready to spend* = the USDC in the Safe;
  *Earning* = what ether.fi has lent out for you, read from its LendGateway (`suppliedOf(safe, USDC)` on
  0x01F8cDFb1694eA8fE4ED6c38a0fD78d1188E03F4, Aave V4), interest included; borrowing (`debtOf`) is shown
  when there is any. *Activity* = every USDC transfer in and out, in plain words.
- **Solana** (a Jupiter wallet, or ether.fi's Solana deposit address): USDC and SOL; changes in USDC become activity.
- **TRON** (an address starting with T): USDT and TRX, from TronGrid; each USDT transfer in or out becomes activity.

### Sub-watch (v0.7)
Watch's front face shows only what you want people to see (in a meeting, on a screen share). Behind it:
- **Open it:** press and hold **Check now** for about 2 seconds, then Face ID (or the passcode). A plain tap still just checks.
- **Inside:** every wallet with where it is (on the front / hidden for a while / hidden until you bring it back). Tap one to hide it
  (1 hour, 8 hours, 1 day, a time you choose, or until you bring it back), bring it to the front, hide it while the screen is shared,
  rename it or stop watching it. **Add to sub-watch** adds an address that stays behind.
- **Hidden means hidden:** no card, no activity, no Pulse entry, no toast. Hidden wallets are still checked quietly.
- **Shut when it should be:** sub-watch closes when ANA leaves the front, and won't open while the screen is recorded, mirrored or shared.
- Checked when ANA comes to the front, every 2 minutes while it's open, and with *Check now*.
  Anything new is added to the log as a WATCH entry, so it shows on Pulse.
- Tap a wallet card to rename it, copy its address, check it now or stop watching it.

## Folders

- `ANA_PoC/`: the sketch (Processing 1.5.1 and Processing.js), from ANA LITE, with an iPhone mode (`onIOS`).
- `ios/Web/`: the page (`index.html`), Processing.js, the GPU shaders and `iosbridge.js`.
  - `sync_web.sh` copies the sketch in.
- `ios/ANA/`: Swift.
  - `ViewController.swift`: the web view and the bridge.
  - `AnaLog.swift`: the tab-separated log.
  - `AnaMesh.swift`: .pngmesh + .sha256.
  - `AppDelegate.swift`: files opened with ANA.
  - `Wallets.swift`: WATCH (ether.fi Safe on Optimism, Solana and TRON wallets).
- `ios/project.yml`: the Xcode project (XcodeGen).
- `.github/workflows/ios.yml`: the cloud build.

## Build it in the cloud (no Mac)

1. Make a new **private** repository on github.com (for example `ana-ios`).
2. Upload everything in this folder to it. On the repository page, use **Add file > Upload files** and drag
   the folder's contents in, including the hidden `.github` folder. If the upload skips `.github`, create the
   file `.github/workflows/ios.yml` with **Add file > Create new file** and paste it in.
3. Open the **Actions** tab. The build starts by itself (or choose **Build ANA for iPhone > Run workflow**).
   It takes about 5 minutes.
4. Open the finished run. Under **Artifacts**, download **ANA-iPhone**, then unzip it to get `ANA.ipa`.

## Install it with Sideloadly (on the Surface)

1. Install **iTunes** and **iCloud** from Apple's website (not the Microsoft Store versions), then **Sideloadly**
   (sideloadly.io).
2. Connect the iPhone by USB and tap **Trust** on the phone.
3. In Sideloadly, drop `ANA.ipa` in, type your Apple ID, and press **Start**.
4. On the iPhone:
   - **Settings > General > VPN & Device Management**: trust your Apple ID.
   - iOS 16 or newer: **Settings > Privacy & Security > Developer Mode**: turn it on (the phone restarts).

A free Apple ID's install runs for 7 days. Then press **Start** in Sideloadly again (your entries stay).
A paid Apple Developer account ($99 a year) lasts a year.

## Your data

- The log is `ana_log.txt` in the Files app: **On My iPhone > ANA**.
- EXPORT shares the `.pngmesh` and its `.sha256` together (AirDrop, Files, Mail, WhatsApp...).
- IMPORT (in Archive), or opening a `.pngmesh` / `.sha256` with ANA, adds the entries.
  - Both files are needed: the `.pngmesh` is read only when its `.sha256` matches.

## Tested so far (v0.1-ios)

- In a browser (Chromium, iPhone size 390x780 @3x), with a stand-in for the Swift bridge: the page, `iosbridge.js` and the sketch's iPhone mode.
  - Four tabs (no APPify), the iPHONE badge, + on Pulse (manual entry: the entries show on Pulse, Archive and Timeline).
  - Settings with only the parts that work on iPhone. Archive's three balls (GPU).
  - No page errors.
- The Swift code has not been compiled yet: there's no Mac or Swift here. The first cloud build is its first compile.
  If it fails, send me the build log (the run's red step) and I'll fix it.

## v0.2-ios: share this iPhone's notifications with ANA on Android

- Settings > Android > "Connect to Android ANA".
  - The app finds ANA LITE on Android nearby (Bluetooth) and keeps the link up, in the background too.
  - iOS then sends every notification to it: that's the Apple Notification Center Service, the way smartwatches get them.
- First time:
  1. Turn on "iPhone notifications" in ANA LITE (Android).
  2. Turn on "Connect to Android ANA" here.
  3. Accept the Bluetooth pairing request on the iPhone. If asked, allow notifications to be shared.
  4. If nothing arrives: Settings > Bluetooth > (i) next to the Android device > "Share System Notifications" on.

## v0.3-ios-bt: the relay

- ANA on Android sends every iPhone notification it receives straight back here over the same Bluetooth link.
  This app's log gets them all: Pulse, Timeline, EFINOTE, EXPORT.
- On reconnecting, it asks for what it missed while out of range.
- The reader (tap a notification) came over from ANA LITE:
  - COPY: to the clipboard.
  - SELECT: for EXPORT.
  - CLEAR ON iPHONE: asks ANA on Android to dismiss it here.
- The blue iPhone tag. iPhone entries always show, even with PICKED on.

## v0.4-ios-orbit: APPify on the iPhone

- APPify's ball holds the apps whose notifications ANA on Android relayed back.
- Icons, names and categories: looked up once per app by its bundle ID in Apple's public App Store directory
  (itunes.apple.com/lookup) and kept on the phone. Apple's own apps aren't there: they get a letter.
- Panel buttons:
  - OPEN: the app, where iOS allows a link (WhatsApp, Instagram, Telegram, Gmail...); otherwise its App Store page.
  - CLEAR: asks ANA on Android to clear that app's notifications on this iPhone.
  - STOP and ACTIVE (screen time) aren't possible on iOS, so they're hidden or explained.

## v0.5-ios-orbit
- APPify's Live pill and the bar's RECORDING follow the Android link (they said Off on the iPhone before).
- Coming back to the app asks ANA on Android for anything missed meanwhile.
- Keep only one ANA on the iPhone linked to Android at a time (Orbit). Needs ANA LITE v0.12 on Android.

### GST, Group Spend Technology (v0.8, Phase 1)
The fourth pill in Settings: ANA | EFINOTE | WATCH | GST. Everything is opt-in, and GST never holds money.
- **Personal pools:** split what you watch into pools (car, mortgage, gas) and top them up in rotation.
- **Groups:** a combined balance from what each member chooses to share (a number, never an address).
- **Spend alerts:** "about to spend 50 BBD on gas" to the group; received alerts also land on Pulse.
- **Turns and group buys:** sou-sou / meeting-turn order, and group buys with pledges.
- **Transport (default):** packs are sealed .pngmesh + .sha256 files (class 21, the same container as ANA's
  entries), shared however you like and opened with IMPORT. Bluetooth, Wi-Fi and a small server come later.

### FLEX (v0.9)
A FLEX chip at the top of the flat screens opens the Flex wallet: eFLEX earned (1 per $10 held per day, from
what ANA watches, counted at midnight), gifted eFLEX (shown apart) and FlexP (bought, never mixed; from Nov 30).
eFLEX gifts move through a GST group's ledger, and everyone in the group must hold the same ledger:
- every entry is signed by the sender's phone (P-256 key in the Keychain on this device only; Flex.swift);
- every entry carries the sha256 of the one before it (a chain); a tampered copy fails its check;
- two different versions of the same entry are a conflict: the group's transfers freeze, and it shows;
- a gift is pending until every member's ANA confirms (a signed ACK) the same ledger, then final.
Keys and signatures use the same forms as the Android app (X.509 public keys, DER signatures).
