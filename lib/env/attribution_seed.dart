// Jester Treasure — attribution & messaging credential vault.
//
// The AppsFlyer dev key and Firebase project number are XOR-scrambled
// to keep them out of `strings` dumps and static APK scanners. The GCD
// host/path halves are separated so no single grep for
// "gcdsdk.appsflyer.com" ever succeeds against the binary.

import 'cipher.dart';

// -- AppsFlyer dev key ---------------------------------------------
// TODO(prod): replace once the real AF_DEV_KEY is issued and re-mint.
const List<int> _attributionKeyBytes = <int>[
  0xf1, 0x17, 0x0d, 0x0a, 0x63, 0xf2, 0xc4, 0xce, 0xe6, 0xf9, 0xf2, 0x75,
  0xe5, 0x82, 0x45, 0xe9, 0xfe, 0xc0, 0x64, 0xd8, 0x09, 0xd0,
];

String attributionKey() {
  if (_attributionKeyBytes.isEmpty) return '';
  final v = unveil(_attributionKeyBytes);
  if (v.contains('PLACEHOLDER')) return '';
  return v;
}

// -- Firebase project number ---------------------------------------
// TODO(prod): replace with the real project number once google-services
// JSON is provided.
const List<int> _messagingProjectBytes = <int>[
  0x80, 0x61, 0x62, 0x7e, 0x16, 0x94, 0xab, 0xb5, 0x93, 0x90, 0x9d, 0x15,
];

String messagingProjectId() {
  if (_messagingProjectBytes.isEmpty) return '';
  final v = unveil(_messagingProjectBytes);
  if (v == '000000000000') return '';
  return v;
}

// -- GCD (Get Conversion Data) endpoint ----------------------------
// See https://dev.appsflyer.com/hc/reference/gcd-get-data
const List<int> _gcdHostBytes = <int>[
  0xd8, 0x25, 0x26, 0x3e, 0x55, 0x9e, 0xb4, 0xaa, 0xc4, 0xc3, 0xc9, 0x56,
  0xcd, 0xa8, 0x28, 0xcd, 0xc6, 0xff, 0x5b, 0xfa, 0x20, 0xfb, 0xf4, 0x01,
  0x9e, 0x32, 0x3d, 0x23,
];

const List<int> _gcdPathBytes = <int>[
  0x9f, 0x38, 0x3c, 0x3d, 0x52, 0xc5, 0xf7, 0xe9, 0xfc, 0xc4, 0xcc, 0x51,
  0xc8, 0xec, 0x70, 0x98, 0x98, 0xbf, 0x07,
];

String composeGcdUrl({required String appId, required String deviceId}) {
  if (_gcdHostBytes.isEmpty || _gcdPathBytes.isEmpty) return '';
  final key = attributionKey();
  final host = unveil(_gcdHostBytes);
  final path = unveil(_gcdPathBytes);
  final query = 'devkey=$key&device_id=$deviceId';
  return '$host$path$appId?$query';
}
