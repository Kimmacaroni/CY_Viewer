import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _clientId =
    '99146066883-tr494pci27mpsvc9fhdr7skp8p9o6j1n.apps.googleusercontent.com';
String _random() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
Future<String> driveAuthorize() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final state = _random(), verifier = _random();
  final redirect = 'http://127.0.0.1:${server.port}/oauth/callback';
  final result = Completer<String>();
  final subscription = server.listen((request) async {
    if (request.method != 'GET' ||
        request.uri.path != '/oauth/callback' ||
        request.uri.queryParameters['state'] != state) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    final code = request.uri.queryParameters['code'];
    request.response.headers.contentType = ContentType.html;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(
      '<!doctype html><meta charset="utf-8"><title>CY뷰어</title><p>CY뷰어로 돌아가 연결 결과를 확인하세요.</p>',
    );
    await request.response.close();
    if (!result.isCompleted) {
      if (code == null) {
        result.completeError(StateError('Google 연결이 취소되었습니다.'));
      } else {
        result.complete(code);
      }
    }
  });
  try {
    final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': 'https://www.googleapis.com/auth/drive.file',
      'state': state,
      'code_challenge': base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', ''),
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('브라우저를 열지 못했습니다.');
    }
    final code = await result.future.timeout(const Duration(minutes: 2));
    final response = await http
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {
            'client_id': _clientId,
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirect,
            'grant_type': 'authorization_code',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Google 인증을 완료하지 못했습니다. 다시 연결해 주세요.');
    }
    final data = jsonDecode(response.body) as Map;
    if (!(data['scope'] as String? ?? '')
        .split(' ')
        .contains('https://www.googleapis.com/auth/drive.file')) {
      throw StateError('Drive 파일 권한이 필요합니다.');
    }
    return data['access_token'] as String;
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}
