// Jester Treasure — routing endpoint URL vault.
//
// The domain of the backend that decides "portal (WebView)" vs "arena
// (native game)" is the single most identifying string in this binary.
// It is stored ONLY as XOR-scrambled bytes and stitched back together
// on demand by [buildRoutingUrl].
//
// If the endpoint moves, regenerate via `dart run tool/mint_secrets.dart`
// and paste the new arrays over `_hostBytes` / `_pathBytes` below.

import 'cipher.dart';

const List<int> _hostBytes = <int>[
  0xd8, 0x25, 0x26, 0x3e, 0x55, 0x9e, 0xb4, 0xaa, 0xc9, 0xc5, 0xde, 0x51,
  0xcc, 0xb1, 0x72, 0xde, 0xd3, 0xee, 0x5b, 0xe9, 0x3e, 0xe7, 0xbf, 0x10,
  0xdf, 0x3c,
];

const List<int> _pathBytes = <int>[
  0x9f, 0x32, 0x3d, 0x20, 0x40, 0xcd, 0xfc, 0xab, 0xd3, 0xc8, 0xdd,
];

String buildRoutingUrl() {
  if (_hostBytes.isEmpty || _pathBytes.isEmpty) return '';
  return unveil(_hostBytes) + unveil(_pathBytes);
}
