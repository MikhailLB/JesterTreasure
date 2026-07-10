// Jester Treasure — attribution & messaging credential vault.
//
// The AppsFlyer dev key and Firebase project number are XOR-scrambled
// to keep them out of `strings` dumps and static APK scanners. The GCD
// host/path halves are separated so no single grep for
// "gcdsdk.appsflyer.com" ever succeeds against the binary.

import 'cipher.dart';

// -- AppsFlyer dev key ---------------------------------------------
// Minted from KV8a2EpNUBCF8z36uM4LHD via tool/mint_secrets.dart.
const List<int> _attributionKeyBytes = <int>[
  0xfb, 0x07, 0x6a, 0x2f, 0x14, 0xe1, 0xeb, 0xcb, 0xf6, 0xe2, 0xee, 0x63,
  0x91, 0xb9, 0x35, 0x9a, 0xc3, 0xc2, 0x1c, 0xd0, 0x04, 0xc6,
];

String attributionKey() {
  if (_attributionKeyBytes.isEmpty) return '';
  return unveil(_attributionKeyBytes);
}

// -- Firebase project number ---------------------------------------
// Minted from 48216277421 (Firebase project jestertreasure-e007c) via
// tool/mint_secrets.dart.
const List<int> _messagingProjectBytes = <int>[
  0x84, 0x69, 0x60, 0x7f, 0x10, 0x96, 0xac, 0xb2, 0x97, 0x92, 0x9c,
];

String messagingProjectId() {
  if (_messagingProjectBytes.isEmpty) return '';
  return unveil(_messagingProjectBytes);
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
