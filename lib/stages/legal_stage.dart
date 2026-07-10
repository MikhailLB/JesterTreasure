// Jester Treasure — mini WebView for legal/support pages surfaced from
// the arena menu. Uses the same user-agent as the portal so tracking
// domains treat every touch consistently.

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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(netChannel.userAgent)
      ..setBackgroundColor(const Color(0xFF1A0B2E))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageFinished: (_) => setState(() => _done = true),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0B2E),
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
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (!_done)
            LinearProgressIndicator(
              value: _progress / 100.0,
              backgroundColor: Colors.black26,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFC107),
              ),
              minHeight: 3,
            ),
        ],
      ),
    );
  }
}
