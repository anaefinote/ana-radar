# Android source — RECOVERED from ANA_STATIA_v1.33_TEST_latest.apk

Decompiled with jadx (classes.dex) + unzipped assets, on 2026-11-20. This is the Android
wrapper that was never committed before — now it is, so it can't be lost again.

- `src/com/novera/ana/*.java` — the Java shell (MainActivity + the AndroidANA Bridge,
  AncsLink BLE, AnaListener notifications, Chat, Wallets, Bills, Flex, Lessons, …).
- `assets/` — the Processing sketch + WebView page (same ANA_PoC sketch, verbatim).
- `AndroidManifest.xml` — decoded (package com.novera.ana.statia).

NOT yet a buildable gradle project: jadx output needs cleanup to compile, and a gradle
wrapper + Android build (via CI) still has to be set up. Next: reconstruct a buildable
project, add RadarLink.java + the radar bridge methods + the Radar tab, build LITE+STATIA.
