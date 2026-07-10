// The router persists one of these values so that on subsequent launches
// we skip the attribution round-trip. Once a user is sealed into the
// arena they never see the portal again for the lifetime of the install.
//
// `undecided` is the fresh-install state.

enum RouteMode {
  portal,
  arena,
  undecided;

  static RouteMode parse(String? raw) {
    switch (raw) {
      case 'portal':
        return RouteMode.portal;
      case 'arena':
        return RouteMode.arena;
      default:
        return RouteMode.undecided;
    }
  }

  String stringify() {
    switch (this) {
      case RouteMode.portal:
        return 'portal';
      case RouteMode.arena:
        return 'arena';
      case RouteMode.undecided:
        return 'undecided';
    }
  }
}
