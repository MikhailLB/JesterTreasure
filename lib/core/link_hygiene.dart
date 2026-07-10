// Every URL received from a push payload, deep link, or GCD callback
// goes through [sanitiseInboundLink] before it is ever handed to the
// WebView. AppsFlyer test payloads still ship the placeholder
// "deep_link_test" — feeding that to `Uri.parse` succeeds (opaque URI)
// but drops the WebView into a black error page. We drop such values
// silently.

Uri? sanitiseInboundLink(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == 'deep_link_test') return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  if (!parsed.hasAuthority) return null;
  return parsed;
}

/// Walks the well-known landing-URL aliases in a push payload's data map
/// and returns the first one that survives the sanitiser.
String? extractPushLink(Map<String, dynamic> data) {
  const List<String> aliases = <String>[
    'url',
    'link',
    'landing_page',
    'deep_link_value',
    'redirect_url',
  ];
  for (final alias in aliases) {
    final candidate = data[alias];
    if (candidate is! String) continue;
    final uri = sanitiseInboundLink(candidate);
    if (uri != null) return uri.toString();
  }
  return null;
}
