// Jester Treasure — WebView shell ("gray" experience).
//
// Applies every fix documented in `.cursor/rules/gray_part_pitfalls.md`:
//   • three-layer keyboard fix (Manifest adjustResize + Scaffold
//     resizeToAvoidBottomInset:false + JS scrollIntoView('auto'))
//   • immediate spinner cover on `onWebResourceError` so the native
//     Android error page never shows through
//   • VPN-friendly connectivity debounce (700 ms)
//   • redirect-loop retry (up to 3 hops)
//   • SPA-aware safe-area killer
//   • warm push URL delivered via callback (never persisted)

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/alert_gateway.dart';
import '../core/link_hygiene.dart';
import '../core/local_vault.dart';
import '../core/net_channel.dart';
import '../core/net_sensor.dart';
import 'tempest_stage.dart';

/// Called by BootStage via a deferred import so the WebView engine only
/// spins up if the routing verdict is `portal`. Currently a no-op; kept
/// because `content.loadLibrary()` still awaits it.
Future<void> primePortalEngine() async {}

class PortalStage extends StatefulWidget {
  final String url;
  final LocalVault vault;
  final AlertGateway gateway;
  final NetSensor netSensor;

  const PortalStage({
    super.key,
    required this.url,
    required this.vault,
    required this.gateway,
    required this.netSensor,
  });

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _spinning = true;
  bool _errored = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;
  bool _routedToTempest = false;

  String? _lastMainFrameUrl;
  int _redirectRetryCount = 0;

  void Function(String)? _previousWarmHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(netChannel.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _errored = false;
            _spinning = true;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          if (_errored) return; // don't lift spinner over error page
          setState(() => _spinning = false);
          _redirectRetryCount = 0;
          _injectViewportPatch();
          _injectKeyboardScroll();
        },
        onWebResourceError: _handleWebError,
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final scheme = uri.scheme;
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            if (request.isMainFrame) _lastMainFrameUrl = request.url;
            return NavigationDecision.navigate;
          }
          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      ));

    _configureAndroidLayer();
    _web.loadRequest(Uri.parse(widget.url));

    // Warm push handler — snapshot the previous one so we do not orphan
    // the shell-level fallback (see pitfalls §12).
    _previousWarmHandler = widget.gateway.onWarmLink;
    widget.gateway.onWarmLink = (url) {
      final sanitised = sanitiseInboundLink(url);
      if (sanitised != null && mounted) {
        _web.loadRequest(sanitised);
      }
    };

    _connSub = widget.netSensor.statusStream.listen(_onConnectivityChange);

    // If the app booted OFFLINE, `AlertGateway.getToken()` failed
    // silently. Reaching the portal means we now have connectivity,
    // so nudge the gateway to retry token acquisition. Idempotent
    // once a token is held.
    unawaited(widget.gateway.reattemptWithNetwork());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _configureAndroidLayer() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final ctrl = _web.platform as AndroidWebViewController;

    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnShowFileSelector(_openFilePicker);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(ctrl, true);
  }

  Future<List<String>> _openFilePicker(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files
            .where((f) => f.path != null && f.path!.isNotEmpty)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // -- Error / offline handling --------------------------------------

  void _handleWebError(WebResourceError err) {
    // Only bail out on EXPLICIT sub-frame errors — see pitfalls §4.
    if (err.isForMainFrame == false) return;
    if (!mounted) return;

    final desc = err.description.toLowerCase();
    final isRedirectLoop = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    if (isRedirectLoop &&
        _lastMainFrameUrl != null &&
        _redirectRetryCount < 3) {
      _redirectRetryCount++;
      _web.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    setState(() {
      _errored = true;
      _spinning = true; // cover the native error page immediately
    });

    final isDnsOrDisconnect = desc.contains('name_not_resolved') ||
        desc.contains('err_name_not_resolved') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        desc.contains('address_unreachable') ||
        desc.contains('connection_refused') ||
        desc.contains('connection_reset') ||
        desc.contains('connection_timed_out') ||
        err.errorCode == -2 ||
        err.errorCode == -6 ||
        err.errorCode == -7 ||
        err.errorCode == -21 ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -109 ||
        err.errorCode == -118;

    if (isDnsOrDisconnect) {
      _routeToTempest(); // skip the redundant DNS probe
    } else {
      _routeToTempestIfDown();
    }
  }

  Future<void> _routeToTempestIfDown() async {
    if (_routedToTempest) return;
    final live = await widget.netSensor.canReachInternet();
    if (live || !mounted) {
      if (mounted) setState(() => _spinning = false);
      return;
    }
    await _routeToTempest();
  }

  Future<void> _routeToTempest() async {
    if (_routedToTempest || !mounted) return;
    _routedToTempest = true;

    // Snapshot whatever page the user was actually on so that when the
    // network comes back and they tap "Try again", the WebView reloads
    // exactly that URL — not the original landing page we booted with.
    String resumeUrl = widget.url;
    try {
      final current = await _web.currentUrl();
      if (current != null && current.isNotEmpty) {
        final uri = Uri.tryParse(current);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.hasAuthority) {
          resumeUrl = current;
        }
      }
    } catch (_) {}
    // Fall back to the last main-frame URL if we captured it earlier.
    if (_lastMainFrameUrl != null &&
        _lastMainFrameUrl!.isNotEmpty &&
        resumeUrl == widget.url) {
      resumeUrl = _lastMainFrameUrl!;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TempestStage(
          onRetry: (_) => PortalStage(
            url: resumeUrl,
            vault: widget.vault,
            gateway: widget.gateway,
            netSensor: widget.netSensor,
          ),
        ),
      ),
    );
  }

  void _onConnectivityChange(List<ConnectivityResult> results) {
    final allNone = results.every((r) => r == ConnectivityResult.none);
    if (!allNone) {
      _offlineDebounce?.cancel();
      _offlineDebounce = null;
      return;
    }
    _offlineDebounce?.cancel();
    _offlineDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      final live = await widget.netSensor.hasLiveInterface();
      if (live) return;
      _routeToTempest();
    });
  }

  // -- Injections ----------------------------------------------------

  void _injectKeyboardScroll() {
    _web.runJavaScript(r'''
(function() {
  if (window.__jtKbInj) return;
  window.__jtKbInj = true;

  function isEditable(el) {
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }
  function reveal() {
    var el = document.activeElement;
    if (!isEditable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var r = el.getBoundingClientRect();
      var floor = vp.offsetTop + vp.height;
      if (r.bottom > floor - 22 || r.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }
  document.addEventListener('focusin', function(e) {
    if (isEditable(e.target)) setTimeout(reveal, 350);
  });
  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prev) setTimeout(reveal, 120);
      prev = h;
    });
  }
})();
''');
  }

  void _injectViewportPatch() {
    _web.runJavaScript(r'''
(function() {
  if (window.__jtSafeArea) return;
  window.__jtSafeArea = true;

  var ID = '__jt_safe_area_patch';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}';

  function kbOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.78;
  }

  function apply() {
    if (kbOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var c = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var style = document.getElementById(ID);
    if (!style) {
      style = document.createElement('style');
      style.id = ID;
      head.appendChild(style);
    }
    if (style.textContent !== CSS) style.textContent = CSS;
    if (head.lastElementChild !== style) head.appendChild(style);
  }

  apply();

  ['pushState', 'replaceState'].forEach(function(fn) {
    var original = history[fn];
    history[fn] = function() {
      var r = original.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  // -- Lifecycle -----------------------------------------------------

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineDebounce?.cancel();
    _connSub?.cancel();
    widget.gateway.onWarmLink = _previousWarmHandler;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false; // never exit
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // required by the keyboard fix
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // One-source-of-truth safe-area handling. SafeArea already
            // pads by viewPadding on all edges; wrapping it in another
            // Padding that adds viewPadding.left/right (as the earlier
            // version did) doubles the inset in landscape.
            SafeArea(
              top: true,
              left: true,
              right: true,
              bottom: false,
              child: WebViewWidget(controller: _web),
            ),
            if (_spinning)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFC107),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
