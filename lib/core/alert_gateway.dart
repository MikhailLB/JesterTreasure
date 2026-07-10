// Jester Treasure — push notification pipeline.
//
// Cold-tap URLs (`getInitialMessage`) are STORED to the vault and consumed
// once by `BootStage` on the next launch. Warm-tap URLs (foreground /
// backgrounded) fire the `onWarmLink` callback; they must NEVER be persisted
// — the product spec treats push URLs as one-shot.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'link_hygiene.dart';
import 'local_vault.dart';
import 'net_channel.dart';

const String _channelId = 'jt_flame_channel';
const String _channelLabel = 'Jester Treasure Alerts';

@pragma('vm:entry-point')
Future<void> _flameBackgroundIsolate(RemoteMessage message) async {
  // Background isolate has no UI access; the OS displays the notification.
  // Warm & cold tap handling happens in the main isolate below.
}

class AlertGateway {
  final LocalVault _vault;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _fcm;
  String? _token;
  bool _booted = false;

  /// Fires on warm foreground/background taps. Do NOT persist the URL.
  void Function(String url)? onWarmLink;

  /// Fires when the FCM token rotates.
  void Function(String token)? onTokenRotate;

  AlertGateway(this._vault);

  String? get pushToken => _token;

  Future<void> ignite() async {
    if (_booted) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_flameBackgroundIsolate);

      await _prepareLocalPlugin();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((rot) {
        _token = rot;
        onTokenRotate?.call(rot);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmBackgroundTap);

      final initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        await _onColdTap(initial);
      }

      _booted = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[alert] boot failed: $e');
      }
    }
  }

  Future<void> _prepareLocalPlugin() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_alert_flame');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localPlugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == null || resp.payload!.isEmpty) return;
        try {
          final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
          final url = extractPushLink(data);
          if (url != null) onWarmLink?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelLabel,
          description: 'Realtime alerts from Jester Treasure',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<bool> askOsPermission() async {
    final fcm = _fcm;
    if (fcm == null) return false;
    try {
      final settings = await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      await _vault.stampPromoGranted(granted);
      if (!granted &&
          settings.authorizationStatus == AuthorizationStatus.denied) {
        await _vault.stampPromoOsBlocked();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  // -- Message routers ------------------------------------------------

  Future<void> _onForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return; // iOS shows banners itself
    final n = message.notification;
    if (n == null) return;

    AndroidNotificationDetails details;
    final imageUrl = n.android?.imageUrl;
    Uint8List? picture;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      picture = await _downloadImage(imageUrl);
    }

    if (picture != null) {
      details = AndroidNotificationDetails(
        _channelId,
        _channelLabel,
        icon: '@drawable/ic_alert_flame',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigPictureStyleInformation(
          ByteArrayAndroidBitmap(picture),
          largeIcon:
              const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          hideExpandedLargeIcon: false,
        ),
      );
    } else {
      details = const AndroidNotificationDetails(
        _channelId,
        _channelLabel,
        icon: '@drawable/ic_alert_flame',
        importance: Importance.high,
        priority: Priority.high,
      );
    }

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _localPlugin.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  Future<void> _onWarmBackgroundTap(RemoteMessage message) async {
    final url = extractPushLink(message.data);
    if (url != null) onWarmLink?.call(url);
  }

  Future<void> _onColdTap(RemoteMessage message) async {
    final url = extractPushLink(message.data);
    if (url != null) await _vault.writeColdTapLink(url);
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response =
          await netChannel.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
