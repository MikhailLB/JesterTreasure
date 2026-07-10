// Jester Treasure — central app-level configuration facade.
//
// Every service, stage, and screen reads its identifiers through this
// class. Individual secrets are still hidden behind the cipher unlockers;
// what lives here is the assembly logic and the safe plaintext.

import 'attribution_seed.dart';
import 'legal_uris.dart';
import 'routing_endpoint.dart';

class AppFacade {
  AppFacade._();

  // -- Immutable identity ------------------------------------------
  static const String bundleId = 'com.jestertreas.jesterstreasure';
  static const String storeId = 'com.jestertreas.jesterstreasure';
  static const String displayName = 'JesterTreasure';
  static const String appIdentityTag = 'JesterTreasure';

  // -- Routing / analytics resolvers -------------------------------
  static String get routingUrl => buildRoutingUrl();
  static String get analyticsKey => attributionKey();
  static String get messagingProject => messagingProjectId();

  // -- Legal / support --------------------------------------------
  static String get privacyUri => privacyPolicyPage;
  static String get supportUri => supportPage;
  static String get siteUri => officialSitePage;

  // -- Timings -----------------------------------------------------
  /// Delay before re-showing the push-permission promo after the user
  /// tapped Skip. 3 days per the product spec.
  static const int alertPromoSnoozeSeconds = 3 * 24 * 60 * 60;

  /// Wait this long before firing the GCD retry when AppsFlyer initially
  /// classifies a paid install as Organic.
  static const int organicRetrySeconds = 5;

  /// First-launch attribution ceiling. After this, we hand over to the
  /// GCD poller if the deep-link callback said "non-organic" but the
  /// install callback is still pending.
  static const int firstLaunchAttributionSeconds = 25;

  /// Returning-user attribution ceiling. Short because the previous
  /// verdict already exists in local storage.
  static const int returningAttributionSeconds = 10;

  /// Deep-link callback ceiling.
  static const int deepLinkSeconds = 5;

  /// Configuration POST timeout.
  static const int routingRequestTimeoutSeconds = 15;
}
