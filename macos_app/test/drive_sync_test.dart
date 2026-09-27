import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cy_viewer/drive_sync.dart';

void main() {
  test('두 기기의 서로 다른 책갈피와 삭제를 보존한다', () {
    final a = {
      'marks': {
        '2': {'on': true, 'at': 10},
        '3': {'on': false, 'at': 30},
      },
      'page': {'n': 8, 'at': 40},
    };
    final b = {
      'marks': {
        '4': {'on': true, 'at': 20},
        '3': {'on': true, 'at': 20},
      },
      'page': {'n': 2, 'at': 20},
    };
    final merged = mergeReading(a, b);
    expect((merged['marks'] as Map).keys, containsAll(['2', '3', '4']));
    expect(merged['marks']['3']['on'], false);
    expect(merged['page']['n'], 8);
    expect(mergeReading(b, a), merged);
  });
  test('로그아웃 이후 늦게 도착한 로그인은 적용하지 않는다', () async {
    final token = Completer<String>();
    final sync = DriveSync(authorize: () => token.future);
    final connecting = sync.connect();
    sync.disconnect();
    token.complete('unit-token');
    await connecting;
    expect(sync.connected, false);
    expect(sync.files, isEmpty);
  });
  test('기존 PDF를 재업로드하지 않고 최근 목록은 5개만 요청한다', () async {
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final requests = <http.Request>[];
    final row = {
      'id': 'file1',
      'name': 'a.pdf',
      'description': '{}',
      'appProperties': {'cyHash': sha256.convert(bytes).toString()},
    };
    final sync = DriveSync(
      authorize: () async => 'unit-token',
      clientFactory: () => MockClient((r) async {
        requests.add(r);
        expect(r.headers['Authorization'], 'Bearer unit-token');
        if (r.url.path.endsWith('/about')) {
          return http.Response(
            '{"user":{"emailAddress":"unit@example.test"}}',
            200,
          );
        }
        if (r.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({
              'files': [row],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    await sync.connect();
    await sync.open('a.pdf', bytes);
    expect(requests.any((r) => r.url.path.startsWith('/upload')), false);
    expect(
      requests
          .where((r) => r.url.queryParameters['orderBy'] != null)
          .single
          .url
          .queryParameters['pageSize'],
      '5',
    );
  });
  test('조건부 저장 충돌 시 최신 상태를 다시 읽고 병합한다', () async {
    var patches = 0;
    Map<String, dynamic>? saved;
    final sync = DriveSync(
      authorize: () async => 'unit-token',
      clientFactory: () => MockClient((r) async {
        if (r.url.path.endsWith('/about')) {
          return http.Response(
            '{"user":{"emailAddress":"unit@example.test"}}',
            200,
          );
        }
        if (r.url.path.endsWith('/files')) {
          return http.Response('{"files":[]}', 200);
        }
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 'f',
              'name': 'a.pdf',
              'description': jsonEncode({
                'marks': {
                  '9': {'on': true, 'at': 99},
                },
              }),
            }),
            200,
            headers: {'etag': 'version-$patches'},
          );
        }
        patches++;
        expect(r.headers['If-Match'], 'version-${patches - 1}');
        if (patches == 1) return http.Response('', 412);
        saved = jsonDecode(jsonDecode(r.body)['description']);
        return http.Response('{}', 200);
      }),
    );
    await sync.connect();
    await sync.save(DrivePdf('f', 'a.pdf', '', {}), {
      'marks': {
        '2': {'on': true, 'at': 10},
      },
    });
    expect(patches, 2);
    expect(saved!['marks'].keys, containsAll(['2', '9']));
  });
}
