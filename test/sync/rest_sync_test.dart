//: tests for `RestSyncProvider` —
// HTTP + JSON. Uses a local `HttpServer.bind` to
// stand up a fake backend (no mocking library
// needed).

import 'dart:convert';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.10 — RestSyncProvider: HTTP + JSON', () {
    late HttpServer server;
    late String baseUrl;
    final List<String> requestLog = <String>[];

    setUp(() async {
      // Bind a local server on a random port.
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      requestLog.clear();
      // Handle requests with a programmable
      // handler (we re-assign `handler` in each
      // test).
      server.listen((HttpRequest req) async {
        final String method = req.method;
        final String path = req.uri.path;
        requestLog.add('$method $path');
        if (method == 'POST' && path == '/sync') {
          // Read the request body.
          final String body = await utf8.decoder.bind(req).join();
          final Map<String, Object?> json =
              jsonDecode(body) as Map<String, Object?>;
          // Echo the envelope back with a different
          // `since` value (the server-side
          // watermark).
          json['since'] = 42;
          // Add a fake remote change.
          (json['changes']! as List<Object?>).add(<String, Object?>{
            'tableName': 'books',
            'pk': 'remote-1',
            'type': 'upsert',
            'payload': <String, Object?>{'id': 1, 'title': 'Remote'},
            'version': 42,
          });
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(json));
          await req.response.close();
        } else if (method == 'GET' && path == '/sync/watermark') {
          req.response
            ..statusCode = 200
            ..write('99');
          await req.response.close();
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('currentWatermarkAsync GETs the watermark', () async {
      final RestSyncProvider provider = RestSyncProvider(baseUrl: baseUrl);
      final int wm = await provider.currentWatermarkAsync();
      expect(wm, 99);
      // The request log has the GET.
      expect(requestLog, contains('GET /sync/watermark'));
      provider.close();
    });

    test('syncAsync POSTs the envelope + decodes the response', () async {
      final RestSyncProvider provider = RestSyncProvider(baseUrl: baseUrl);
      final SyncEnvelope out = await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-1',
          since: 0,
          changes: <SyncChange>[
            SyncChange(
              tableName: 'books',
              pk: '1',
              type: SyncChangeType.upsert,
              payload: <String, Object?>{'id': 1, 'title': 'Local'},
              version: 1,
            ),
          ],
        ),
      );
      // The server echoed back the envelope.
      expect(out.clientId, 'client-1');
      expect(out.since, 42);
      // The server added a fake remote change.
      expect(out.changes, hasLength(2));
      expect(out.changes.last.tableName, 'books');
      expect(out.changes.last.pk, 'remote-1');
      // The request log has the POST.
      expect(requestLog, contains('POST /sync'));
      provider.close();
    });

    test('RestSyncProvider sets Content-Type: application/json', () async {
      // Use a server that records the request
      // headers.
      await server.close(force: true);
      final List<String> contentTypes = <String>[];
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((HttpRequest req) async {
        contentTypes.add(req.headers.value('content-type') ?? '');
        final String body = await utf8.decoder.bind(req).join();
        final Map<String, Object?> json =
            jsonDecode(body) as Map<String, Object?>;
        json['since'] = 0;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(json));
        await req.response.close();
      });
      final RestSyncProvider provider = RestSyncProvider(baseUrl: baseUrl);
      await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-1',
          since: 0,
          changes: <SyncChange>[],
        ),
      );
      // The Content-Type header is application/json.
      expect(contentTypes, contains('application/json'));
      provider.close();
    });

    test('RestSyncProvider throws on a non-2xx response', () async {
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((HttpRequest req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      final RestSyncProvider provider = RestSyncProvider(baseUrl: baseUrl);
      expect(
        () => provider.currentWatermarkAsync(),
        throwsA(isA<RestSyncException>()),
      );
      provider.close();
    });
  });

  group('Fase 5.10 — SyncChange + SyncEnvelope JSON round-trip', () {
    test('SyncChange.toJson → fromJson is the identity', () {
      const SyncChange c = SyncChange(
        tableName: 'books',
        pk: '1',
        type: SyncChangeType.upsert,
        payload: <String, Object?>{'id': 1, 'title': 'Rex'},
        version: 7,
      );
      final Map<String, Object?> json = c.toJson();
      final SyncChange back = SyncChange.fromJson(json);
      expect(back.tableName, c.tableName);
      expect(back.pk, c.pk);
      expect(back.type, c.type);
      expect(back.payload, c.payload);
      expect(back.version, c.version);
    });

    test('SyncChange with a delete (payload=null) round-trips', () {
      const SyncChange c = SyncChange(
        tableName: 'books',
        pk: '1',
        type: SyncChangeType.delete,
        payload: null,
        version: 3,
      );
      final SyncChange back = SyncChange.fromJson(c.toJson());
      expect(back.type, SyncChangeType.delete);
      expect(back.payload, isNull);
    });

    test('SyncEnvelope.toJson → fromJson is the identity', () {
      const SyncEnvelope env = SyncEnvelope(
        clientId: 'client-1',
        since: 5,
        changes: <SyncChange>[
          SyncChange(
            tableName: 'books',
            pk: '1',
            type: SyncChangeType.upsert,
            payload: <String, Object?>{'id': 1, 'title': 'Rex'},
            version: 1,
          ),
        ],
      );
      final SyncEnvelope back = SyncEnvelope.fromJson(env.toJson());
      expect(back.clientId, 'client-1');
      expect(back.since, 5);
      expect(back.changes, hasLength(1));
      expect(back.changes.first.tableName, 'books');
    });
  });
}
