import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cy_viewer/drive_sync.dart';
import 'package:cy_viewer/drive_panel.dart';

void main() {
  testWidgets('홈에서 Drive 최근 5개를 열고 연결 해제 시 숨긴다', (tester) async {
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final sync = DriveSync(
      authorize: () async => 'test-token',
      clientFactory: () => MockClient((r) async {
        if (r.url.path.endsWith('/about')) {
          return http.Response(
            '{"user":{"emailAddress":"test@example.test"}}',
            200,
          );
        }
        if (r.url.queryParameters['alt'] == 'media') {
          return http.Response.bytes(bytes, 200);
        }
        return http.Response(
          jsonEncode({
            'files': List.generate(
              6,
              (i) => {
                'id': 'file$i',
                'name': 'document$i.pdf',
                'appProperties': {'cyHash': sha256.convert(bytes).toString()},
                'description': jsonEncode({
                  'page': {'n': 4, 'at': 1},
                }),
              },
            ),
          }),
          200,
        );
      }),
    );
    await sync.connect();
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriveHomeRecent(
              sync: sync,
              onOpen: (name, data) async {
                opened = name;
                expect(data, bytes);
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('document0.pdf'), findsOneWidget);
    expect(find.text('document5.pdf'), findsNothing);
    await tester.tap(find.text('document0.pdf'));
    await tester.pumpAndSettle();
    expect(opened, 'document0.pdf');
    sync.disconnect();
    await tester.pump();
    expect(find.text('document0.pdf'), findsNothing);
  });
}
