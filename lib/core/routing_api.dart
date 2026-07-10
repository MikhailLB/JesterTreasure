// Jester Treasure — routing/config endpoint client.
//
// Uses the shared [netChannel] so the outgoing request carries the
// real-device User-Agent (with `appid`/`appname` suffix) instead of the
// bare Dart HTTP UA.

import 'dart:convert';

import '../data/routing_verdict.dart';
import '../env/app_facade.dart';
import 'local_vault.dart';
import 'net_channel.dart';

class RoutingApi {
  final LocalVault _vault;

  RoutingApi(this._vault);

  Future<RoutingVerdict> dispatch(Map<String, dynamic> body) async {
    final endpoint = AppFacade.routingUrl;
    if (endpoint.isEmpty) {
      return const RoutingVerdict.failure('endpoint_missing');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null) {
      return const RoutingVerdict.failure('endpoint_malformed');
    }

    try {
      final response = await netChannel
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            Duration(seconds: AppFacade.routingRequestTimeoutSeconds),
          );

      if (response.statusCode != 200) {
        return RoutingVerdict.failure('http_${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const RoutingVerdict.failure('body_shape');
      }
      final verdict = RoutingVerdict.fromJson(decoded);
      if (verdict.ok && verdict.hasUrl) {
        await _vault.storePortalUrl(verdict.url!);
        if (verdict.expires != null) {
          await _vault.storePortalExpires(verdict.expires!);
        }
      }
      return verdict;
    } catch (e) {
      return RoutingVerdict.failure(e.toString());
    }
  }
}
