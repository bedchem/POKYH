import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pockyh/services/update_service.dart';

void main() {
  group('UpdateService version compare', () {
    test('erkennt neuere Version mit Prefix/Suffix korrekt', () {
      expect(UpdateService.debugIsRemoteNewer('v1.2.4', '1.2.3'), isTrue);
      expect(UpdateService.debugIsRemoteNewer('1.2.3-beta.1', '1.2.2'), isTrue);
      expect(UpdateService.debugIsRemoteNewer('1.2.3+45', '1.2.3'), isTrue);
      expect(UpdateService.debugIsRemoteNewer('1.2.3', '1.2.3+99'), isFalse);
      expect(UpdateService.debugIsRemoteNewer('1.2.3', '1.2.3'), isFalse);
    });
  });

  group('UpdateService release fetch', () {
    test('liest latest release korrekt aus', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v2.0.1',
              'html_url': 'https://github.com/bedchem/POKYH/releases/tag/v2.0.1',
              'assets': [
                {
                  'name': 'app-release.apk',
                  'browser_download_url': 'https://example.com/app-release.apk',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final info = await UpdateService.debugFetchLatestInfo(client);
      expect(info, isNotNull);
      expect(info!['version'], equals('2.0.1'));
      expect(info['assetsCount'], equals(1));
      expect((info['releasePageUrl'] as String).contains('/releases/tag/'), isTrue);
    });

    test('nutzt tags fallback wenn latest fehlschlaegt', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response('rate limit', 403);
        }
        if (request.url.path.contains('/tags')) {
          return http.Response(
            jsonEncode([
              {'name': 'v1.9.0'},
              {'name': 'v1.10.0'},
              {'name': 'test-tag'},
            ]),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final info = await UpdateService.debugFetchLatestInfo(client);
      expect(info, isNotNull);
      expect(info!['version'], equals('1.10.0'));
      expect((info['releasePageUrl'] as String).contains('/releases/latest'), isTrue);
    });
  });
}


