// Jester Treasure — local persistence facade.
//
// Uses `flutter_secure_storage` for the sensitive gray-flow URLs (they
// contain affiliate identifiers) and `shared_preferences` for everything
// else (mode enum, promo counters, flags).
//
// All calls are defensive: missing/malformed values fall back to safe
// defaults rather than throwing during boot.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/route_mode.dart';

class LocalVault {
  static const String _kMode = 'jt.route_mode';
  static const String _kPortalUrl = 'jt.portal.url';
  static const String _kPortalExpires = 'jt.portal.expires';
  static const String _kPromoSnoozeUntil = 'jt.promo.snooze';
  static const String _kPromoGranted = 'jt.promo.granted';
  static const String _kPromoOsBlocked = 'jt.promo.os_blocked';
  static const String _kColdTapUrl = 'jt.push.cold_tap';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  Future<void> warmUp() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final ref = _prefs;
    if (ref == null) {
      throw StateError('LocalVault.warmUp() was not awaited before use.');
    }
    return ref;
  }

  // -- Mode -----------------------------------------------------------

  RouteMode currentMode() => RouteMode.parse(_p.getString(_kMode));

  Future<void> stampMode(RouteMode mode) =>
      _p.setString(_kMode, mode.stringify());

  // -- Portal URL cache ----------------------------------------------

  Future<String?> cachedPortalUrl() async {
    try {
      return await _secure.read(key: _kPortalUrl);
    } catch (_) {
      return null;
    }
  }

  Future<void> storePortalUrl(String url) async {
    try {
      await _secure.write(key: _kPortalUrl, value: url);
    } catch (_) {}
  }

  int? cachedPortalExpires() => _p.getInt(_kPortalExpires);

  Future<void> storePortalExpires(int expires) =>
      _p.setInt(_kPortalExpires, expires);

  bool portalCacheExpired() {
    final expires = cachedPortalExpires();
    if (expires == null || expires <= 0) return false; // treat as never-expires
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec >= expires;
  }

  // -- Push promo bookkeeping ----------------------------------------

  bool promoGranted() => _p.getBool(_kPromoGranted) ?? false;

  Future<void> stampPromoGranted(bool granted) =>
      _p.setBool(_kPromoGranted, granted);

  bool promoOsBlocked() => _p.getBool(_kPromoOsBlocked) ?? false;

  Future<void> stampPromoOsBlocked() => _p.setBool(_kPromoOsBlocked, true);

  int? promoSnoozeUntil() => _p.getInt(_kPromoSnoozeUntil);

  Future<void> stampPromoSnooze(int untilEpoch) =>
      _p.setInt(_kPromoSnoozeUntil, untilEpoch);

  bool shouldPresentPromo() {
    if (promoGranted()) return false;
    if (promoOsBlocked()) return false;
    final until = promoSnoozeUntil();
    if (until == null) return true;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSec >= until;
  }

  // -- Cold-tap push URL ---------------------------------------------
  // Written only on `getInitialMessage`. Read + wiped by BootStage
  // before any routing decisions.

  Future<String?> readColdTapLink() async {
    try {
      return await _secure.read(key: _kColdTapUrl);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeColdTapLink(String url) async {
    try {
      await _secure.write(key: _kColdTapUrl, value: url);
    } catch (_) {}
  }

  Future<String?> pluckColdTapLink() async {
    final v = await readColdTapLink();
    if (v != null) {
      try {
        await _secure.delete(key: _kColdTapUrl);
      } catch (_) {}
    }
    return v;
  }
}
