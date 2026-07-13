// Jester Treasure — mini WebView for legal / support pages surfaced
// from the arena menu. The remote pages are meant to be readable
// paperwork, so we deliberately override the site's own theme:
//   • WebView background is white
//   • Injected CSS forces every element to have a white background and
//     black foreground, with links kept blue for contrast
// This guarantees the privacy policy is legible regardless of what the
// hosting site's dark-mode styles do.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/net_channel.dart';

class LegalStage extends StatefulWidget {
  final String title;
  final String url;

  const LegalStage({super.key, required this.title, required this.url});

  @override
  State<LegalStage> createState() => _LegalStageState();
}

class _LegalStageState extends State<LegalStage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _done = false;

  static const String _readabilityCss = r'''
    html, body {
      background: #ffffff !important;
      color: #000000 !important;
    }
    body *, body {
      background-color: #ffffff !important;
      color: #000000 !important;
      text-shadow: none !important;
    }
    h1, h2, h3, h4, h5, h6, strong, b {
      color: #000000 !important;
    }
    a, a:link, a:visited {
      color: #0645ad !important;
    }
    p, li, td, span, div { color: #000000 !important; }
    hr { border-color: #cccccc !important; }
  ''';

  void _forceReadableTheme() {
    _controller.runJavaScript('''
      (function() {
        if (window.__jtLegalReadability) return;
        window.__jtLegalReadability = true;
        var style = document.createElement('style');
        style.setAttribute('data-jt', 'legal-readability');
        style.textContent = ${_encodeForJs(_readabilityCss)};
        (document.head || document.documentElement).appendChild(style);
        document.documentElement.style.background = '#ffffff';
        if (document.body) document.body.style.background = '#ffffff';
      })();
    ''');
  }

  static String _encodeForJs(String s) {
    final escaped = s
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(netChannel.userAgent)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => _forceReadableTheme(),
        onPageFinished: (_) {
          _forceReadableTheme();
          if (mounted) setState(() => _done = true);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C1250),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Stack(
          children: <Widget>[
            WebViewWidget(controller: _controller),
            if (!_done)
              LinearProgressIndicator(
                value: _progress / 100.0,
                backgroundColor: Colors.black12,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFFC107),
                ),
                minHeight: 3,
              ),
          ],
        ),
      ),
    );
  }
}
