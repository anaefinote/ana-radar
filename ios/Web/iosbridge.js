// iosbridge.js: on iPhone / iPad, the app adds this before index.html runs (WKUserScript, at document start).
// It defines window.AndroidANA with the same methods the Android app gives the page, so index.html and the
// sketch run unchanged. Each call is a window.prompt("ana-bridge", {"m": method, "a": [args]}): the app's
// WKUIDelegate answers it straight away with the result as JSON, which makes the call synchronous, as the
// sketch expects (js.pref("tab") must return the value, not a promise).
window.__ANA_IOS = true;
(function () {
  var names = ['readSketch', 'ready', 'status', 'watchList', 'saveWatch', 'pref', 'setPref', 'skinData',
    'appIcon', 'appLabel', 'appCategory', 'launchApp', 'usageOk', 'openUsageAccess', 'usageToday',
    'appSettings', 'closeApp', 'clearNotifs', 'appStatus', 'sdkInt', 'openOwnInfo', 'scan', 'openAccess',
    'manualEntry', 'addReminder', 'exportLog', 'exportPngmesh', 'importFiles', 'iphoneLink', 'iphoneState', 'iphoneTimes', 'iphoneDismiss', 'copyText',
    'walletText', 'walletBusy', 'walletRefresh', 'walletAdd', 'walletEdit', 'lessonsText', 'lessonsOpen', 'billsText', 'billsOpen', 'chatOpen', 'chatList', 'chatWrite', 'chatClear', 'findAdd', 'findRemove',
    'walletReveal', 'walletBack', 'walletFront', 'radarOn', 'radarCount', 'radarPeers', 'radarName',
    'fenceCreate', 'fenceJoin', 'fenceRequest', 'fenceAccept', 'fenceDecline', 'fenceLeave', 'fenceInfo', 'fenceKnockers', 'fenceOffers',
    'walletTotals', 'gstSend', 'gstInbox', 'gstAsk', 'gstPick', 'gstAnswer',
    'roundTripShare', 'roundTripInbox', 'sealExport',
    'coSignRequest', 'coSignReply', 'coSignInbox', 'lanPeers', 'tailAdd', 'tailPeers', 'entryTrust',
    'flexKey', 'flexSign', 'flexVerify', 'flexHash'];
  var A = {};
  names.forEach(function (n) {
    A[n] = function () {
      var args = [];
      for (var i = 0; i < arguments.length; i++) args.push(arguments[i] == null ? '' : String(arguments[i]));
      var r = window.prompt('ana-bridge', JSON.stringify({ m: n, a: args }));
      if (r === null || r === undefined || r === '') return '';
      try { return JSON.parse(r); } catch (e) { return r; }
    };
  });
  window.AndroidANA = A;
})();
