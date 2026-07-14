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
import '../core/telemetry_beam.dart';
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

  // Analytics latches (§4 of the Clarity guide).
  bool _offerReached = false;
  bool _pageHadError = false;

  static const String _telemetryChannel = 'JtInsightBridge';

  static final RegExp _depositPattern = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerPattern = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginPattern = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

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

    TelemetryBeam.enterSurface('portal');
    TelemetryBeam.fireEvent('portal_open');

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(netChannel.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..addJavaScriptChannel(
        _telemetryChannel,
        onMessageReceived: (m) => _onWebSignal(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _errored = false;
            _spinning = true;
          });
          _pageHadError = false;
        },
        onPageFinished: (url) {
          if (!mounted) return;
          if (_errored) return; // don't lift spinner over error page
          setState(() => _spinning = false);
          _redirectRetryCount = 0;
          _injectViewportPatch();
          _injectKeyboardScroll();
          _installInsightProbe();
          _trackPortalPage(url);
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
          TelemetryBeam.fireEvent('portal_external');
          TelemetryBeam.writeTag('portal_external_scheme', scheme);
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
    if (state == AppLifecycleState.resumed) {
      _applyImmersive();
      TelemetryBeam.fireEvent('portal_foreground');
    } else if (state == AppLifecycleState.paused) {
      // Paused inside the WebView is the clearest drop-off marker.
      TelemetryBeam.fireEvent('portal_background');
    }
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

    _pageHadError = true;

    final desc = err.description.toLowerCase();
    final isRedirectLoop = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    // Classify + emit analytics before the recovery branches so we
    // always see WHY the WebView failed.
    final String reason = _classifyPortalError(err);
    final String failedUrl = _lastMainFrameUrl ?? widget.url;
    final String failedHost = Uri.tryParse(failedUrl)?.host ?? '';
    TelemetryBeam.fireEvent('portal_error');
    TelemetryBeam.writeTag('portal_error_reason', reason);
    TelemetryBeam.writeTag(
      'portal_last_error',
      '${err.errorCode}:${err.description}',
    );
    if (failedHost.isNotEmpty) {
      TelemetryBeam.writeTag('portal_error_host', failedHost);
    }
    if (!_offerReached) {
      TelemetryBeam.fireEvent('portal_offer_unreachable');
      TelemetryBeam.writeTag('offer_reached', 'false');
      TelemetryBeam.writeTag('offer_unreachable_reason', reason);
    } else {
      TelemetryBeam.fireEvent('portal_error_after_load');
    }

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

  // -- Analytics helpers ---------------------------------------------

  void _trackPortalPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    final label = uri == null ? url : '${uri.host}${uri.path}';
    TelemetryBeam.surfaceName('portal:$label');
    TelemetryBeam.fireEvent('portal_page');
    TelemetryBeam.writeTag('portal_last_url', url);

    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      TelemetryBeam.fireEvent('portal_offer_reached');
      TelemetryBeam.writeTag('offer_reached', 'true');
      if (uri?.host != null && uri!.host.isNotEmpty) {
        TelemetryBeam.writeTag('offer_host', uri.host);
      }
    }

    if (_depositPattern.hasMatch(url)) {
      TelemetryBeam.fireEvent('portal_cashier_page');
      TelemetryBeam.writeTag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String path) {
    if (_registerPattern.hasMatch(path)) {
      TelemetryBeam.fireEvent('portal_register_page');
      TelemetryBeam.writeTag('reached_register', 'true');
    } else if (_loginPattern.hasMatch(path)) {
      TelemetryBeam.fireEvent('portal_login_page');
      TelemetryBeam.writeTag('reached_login', 'true');
    }
  }

  static String _classifyPortalError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') ||
        d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') ||
        d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') || d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) {
      return 'ssl_error';
    }
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  void _installInsightProbe() {
    // The DOM inside the WebView is invisible to session replay, so we
    // observe it from a small idempotent JS probe. Reports:
    //   • SPA route changes
    //   • deposit / register / login clicks
    //   • auth form submits (login vs register heuristic)
    _web.runJavaScript(r'''
(function(){
  if (window.__jtInsightProbe) return; window.__jtInsightProbe = true;
  function send(t){ try { JtInsightBridge.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        TelemetryBeam.fireEvent('portal_spa_route');
        TelemetryBeam.writeTag('portal_last_path', data);
        if (_depositPattern.hasMatch(data)) {
          TelemetryBeam.fireEvent('portal_cashier_page');
          TelemetryBeam.writeTag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
        break;
      case 'deposit_click':
        TelemetryBeam.fireEvent('portal_deposit_click');
        TelemetryBeam.writeTag('deposit_intent', 'true');
        if (data.isNotEmpty) {
          TelemetryBeam.writeTag('deposit_label', data);
        }
        break;
      case 'register_click':
        TelemetryBeam.fireEvent('portal_register_click');
        TelemetryBeam.writeTag('register_intent', 'true');
        break;
      case 'login_click':
        TelemetryBeam.fireEvent('portal_login_click');
        TelemetryBeam.writeTag('login_intent', 'true');
        break;
      case 'auth_submit':
        if (data == 'register') {
          TelemetryBeam.fireEvent('portal_register_submit');
          TelemetryBeam.writeTag('attempted_register', 'true');
        } else {
          TelemetryBeam.fireEvent('portal_login_submit');
          TelemetryBeam.writeTag('attempted_login', 'true');
        }
        break;
      case 'form_submit':
        TelemetryBeam.fireEvent('portal_form_submit');
        break;
    }
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
