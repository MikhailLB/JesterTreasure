// Jester Treasure — obfuscation primitives.
//
// Sensitive credentials (routing endpoint host, attribution dev-key,
// messaging project number, WebKit/Chromium build fragments used in the
// User-Agent) never appear as plain string literals inside the APK.
// They live as byte arrays produced by `tool/mint_secrets.dart` and are
// unlocked on demand at process boot with [unveil].
//
// The scheme is symmetric and stateless: xor each byte against a 24-byte
// rolling key derived from a project-specific seed word. The seed word
// below is the ONLY project-unique value — swapping it invalidates every
// stored payload and forces a re-mint via `tool/mint_secrets.dart`.
//
// If you fork this codebase to another game, replace both:
//   - the `_seedWord` below (any 6-14 char ASCII string)
//   - every byte array in env/routing_endpoint.dart,
//     env/attribution_seed.dart, and core/net_channel.dart

import 'dart:typed_data';

const String _seedWord = 'jester_hoard_v2';

const int _lcgMultiplier = 22695477;
const int _lcgIncrement = 1;
const int _lcgMask = 0x7FFFFFFF;
const int _foldShift = 7;
const int _keyStretch = 24;

Uint8List _forgeKey() {
  final codes = _seedWord.codeUnits;
  if (codes.isEmpty) {
    return Uint8List(_keyStretch);
  }
  int accumulator = 0x9E3779B1;
  for (final c in codes) {
    accumulator = (((accumulator << _foldShift) - accumulator) + c) & 0xFFFFFFFF;
  }
  final key = Uint8List(_keyStretch);
  int state = accumulator == 0 ? 0xDEADBEEF : accumulator;
  for (int i = 0; i < key.length; i++) {
    state = (state * _lcgMultiplier + _lcgIncrement) & _lcgMask;
    key[i] = (state >> 3) & 0xFF;
  }
  return key;
}

final Uint8List _keyStream = _forgeKey();

/// Decodes a byte payload produced by [seal] (see `tool/mint_secrets.dart`)
/// back into its UTF-8 string form.
String unveil(List<int> payload) {
  if (payload.isEmpty) return '';
  final out = Uint8List(payload.length);
  final key = _keyStream;
  final klen = key.length;
  for (int i = 0; i < payload.length; i++) {
    out[i] = (payload[i] ^ key[i % klen]) & 0xFF;
  }
  return String.fromCharCodes(out);
}

/// Inverse of [unveil]; ONLY used by the offline mint tool.
/// Kept here so the two sides never drift apart.
List<int> seal(String plaintext) {
  final input = plaintext.codeUnits;
  final out = List<int>.filled(input.length, 0);
  final key = _keyStream;
  final klen = key.length;
  for (int i = 0; i < input.length; i++) {
    out[i] = (input[i] ^ key[i % klen]) & 0xFF;
  }
  return out;
}
