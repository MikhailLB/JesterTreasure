// DTO returned by the config endpoint. The backend returns JSON in this
// shape:
//   { "ok": true,  "url": "https://...", "expires": 1750000000 }   → portal
//   { "ok": false, "message": "organic" }                          → arena
//
// `expires` is a Unix timestamp in seconds. If the value is null we
// treat the URL as never-expiring.

class RoutingVerdict {
  final bool ok;
  final String? url;
  final String? note;
  final int? expires;

  const RoutingVerdict({
    required this.ok,
    this.url,
    this.note,
    this.expires,
  });

  factory RoutingVerdict.fromJson(Map<String, dynamic> json) {
    final rawOk = json['ok'];
    return RoutingVerdict(
      ok: rawOk is bool ? rawOk : rawOk?.toString().toLowerCase() == 'true',
      url: json['url'] is String ? json['url'] as String : null,
      note: json['message'] is String ? json['message'] as String : null,
      expires: json['expires'] is int
          ? json['expires'] as int
          : int.tryParse(json['expires']?.toString() ?? ''),
    );
  }

  const RoutingVerdict.failure(String note)
      : ok = false,
        url = null,
        note = note,
        expires = null;

  bool get hasUrl => (url ?? '').isNotEmpty;
}
