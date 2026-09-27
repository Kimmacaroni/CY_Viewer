import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'drive_auth.dart';

// Drive 설명은 사용자가 직접 수정할 수 있으므로 알려진 필드만 읽습니다.
Map<String, dynamic> validReading(Map value) {
  final result = <String, dynamic>{'v': 1};
  final page = value['page'];
  if (page is Map &&
      page['n'] is int &&
      page['n'] > 0 &&
      page['at'] is int &&
      page['at'] >= 0) {
    result['page'] = {'n': page['n'], 'at': page['at']};
  }
  if (value['marks'] is Map) {
    result['marks'] = <String, dynamic>{
      for (final e in (value['marks'] as Map).entries)
        if ((int.tryParse('${e.key}') ?? 0) > 0 &&
            e.value is Map &&
            e.value['on'] is bool &&
            e.value['at'] is int &&
            e.value['at'] >= 0)
          '${e.key}': {'on': e.value['on'], 'at': e.value['at']},
    };
  }
  return result;
}

/// Drive description에 저장하는 읽기 상태. 쪽별 변경 시각을 비교해 합칩니다.
Map<String, dynamic> mergeReading(
  Map<String, dynamic> remote,
  Map<String, dynamic> local,
) {
  remote = validReading(remote);
  local = validReading(local);
  final marks = <String, dynamic>{
    ...?(remote['marks'] as Map?)?.cast<String, dynamic>(),
  };
  for (final e in ((local['marks'] as Map?) ?? {}).entries) {
    final old = marks[e.key] as Map?;
    if (old == null || (e.value['at'] as num) >= (old['at'] as num)) {
      marks[e.key as String] = e.value;
    }
  }
  final r = remote['page'] as Map?, l = local['page'] as Map?;
  return {
    'v': 1,
    'marks': marks,
    'page': l != null && (r == null || (l['at'] as num) >= (r['at'] as num))
        ? l
        : r ?? {'n': 1, 'at': 0},
  };
}

class DrivePdf {
  DrivePdf(this.id, this.name, this.hash, this.state);
  final String id, name, hash;
  Map<String, dynamic> state;
  int get page => ((state['page'] as Map?)?['n'] as num? ?? 1).toInt();
  List<int> get bookmarks => [
    for (final e in ((state['marks'] as Map?) ?? {}).entries)
      if (e.value is Map &&
          e.value['on'] == true &&
          int.tryParse('${e.key}') != null)
        int.parse('${e.key}'),
  ]..sort();
  factory DrivePdf.fromJson(Map<String, dynamic> row) {
    Map<String, dynamic> state = {};
    try {
      state = validReading(
        jsonDecode(row['description'] as String? ?? '{}') as Map,
      );
    } catch (_) {
      /* 외부에서 바뀐 설명은 읽기 상태로 사용하지 않습니다. */
    }
    return DrivePdf(
      row['id'] as String,
      row['name'] as String? ?? 'PDF',
      (row['appProperties'] as Map?)?['cyHash'] as String? ?? '',
      state,
    );
  }
}

class DriveSync extends ChangeNotifier {
  DriveSync({
    http.Client Function()? clientFactory,
    Future<String> Function()? authorize,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _authorize = authorize ?? driveAuthorize;
  final http.Client Function() _clientFactory;
  final Future<String> Function() _authorize;
  static final instance = DriveSync();
  final Map<String, Map<String, dynamic>> _pending = {};
  void reportError(String message) {
    error = message;
    notifyListeners();
  }

  String? _token;
  int _generation = 0;
  bool busy = false;
  String? account, error;
  String status = 'Drive 연결 전';
  List<DrivePdf> files = [];
  Future<void> _tail = Future.value();
  bool get connected => _token != null;
  void disconnect() {
    _generation++;
    _pending.clear();
    _token = null;
    status = 'Drive 연결 전';
    account = null;
    files = [];
    error = null;
    busy = false;
    notifyListeners();
  }

  Future<void> connect() async {
    if (busy) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final token = await _authorize();
      if (generation != _generation) return;
      _token = token;
      final data = await _request(
        'GET',
        '/drive/v3/about',
        query: {'fields': 'user(emailAddress)'},
      );
      if (generation != _generation) return;
      account = (data['user'] as Map)['emailAddress'] as String;
      status = 'Drive 연결 완료. 이후 여는 PDF를 동기화합니다.';
      await refresh();
    } catch (_) {
      if (generation == _generation) {
        _token = null;
        account = null;
        error = 'Google Drive 연결을 완료하지 못했습니다. 다시 연결해 주세요.';
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    Uint8List? bytes,
    String? contentType,
    Map<String, String>? headers,
  }) async {
    final token = _token, generation = _generation;
    if (token == null) throw StateError('Google Drive에 연결해 주세요.');
    final request = http.Request(
      method,
      Uri.https('www.googleapis.com', path, query),
    );
    request.headers.addAll({'Authorization': 'Bearer $token', ...?headers});
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    if (bytes != null) {
      request.headers['Content-Type'] = contentType!;
      request.bodyBytes = bytes;
    }
    final client = _clientFactory();
    try {
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 60));
      if (generation != _generation) throw StateError('계정 연결이 변경되었습니다.');
      if (response.statusCode == 401) {
        disconnect();
        throw StateError('연결이 만료되었습니다. Google Drive에 다시 연결해 주세요.');
      }
      if (response.statusCode == 412) throw const _Conflict();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Drive 동기화 실패 (${response.statusCode}). 저장 공간과 연결을 확인해 주세요.',
        );
      }
      if (query?['alt'] == 'media') return {'bytes': response.bodyBytes};
      final result = response.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      result['_etag'] = response.headers['etag'];
      return result;
    } finally {
      client.close();
    }
  }

  Future<void> refresh() async {
    final generation = _generation;
    try {
      final data = await _request(
        'GET',
        '/drive/v3/files',
        query: {
          'q': "trashed = false and mimeType = 'application/pdf' and appProperties has { key='cyViewer' and value='1' }",
          'orderBy': 'modifiedTime desc',
          'pageSize': '5',
          'fields': 'files(id,name,description,appProperties)',
        },
      );
      if (generation != _generation) return;
      files = [
        for (final row in data['files'] as List)
          DrivePdf.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      error = null;
    } catch (_) {
      if (generation == _generation) {
        error = 'Drive 목록을 불러오지 못했습니다. 다시 연결하거나 새로고침해 주세요.';
      }
    }
    notifyListeners();
  }

  Future<Uint8List> download(DrivePdf file) async {
    final result = await _request(
      'GET',
      '/drive/v3/files/${Uri.encodeComponent(file.id)}',
      query: {'alt': 'media'},
    );
    final bytes = result['bytes'] as Uint8List;
    if (sha256.convert(bytes).toString() != file.hash) {
      throw StateError('Drive 파일 내용이 변경되었습니다. 원본을 다시 선택해 주세요.');
    }
    return bytes;
  }

  Future<DrivePdf> open(String name, Uint8List bytes) async {
    final generation = _generation;
    status = 'Drive 동기화 중…';
    notifyListeners();
    final hash = sha256.convert(bytes).toString();
    final data = await _request(
      'GET',
      '/drive/v3/files',
      query: {
        'q':
            "trashed = false and appProperties has { key='cyViewer' and value='1' } and appProperties has { key='cyHash' and value='$hash' }",
        'fields': 'files(id,name,description,appProperties)',
        'pageSize': '1',
      },
    );
    final rows = data['files'] as List;
    if (rows.isNotEmpty) {
      final file = DrivePdf.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
      // PDF 원본을 다시 전송하지 않고 최근 열람 순서만 갱신합니다.
      await _request(
        'PATCH',
        '/drive/v3/files/${file.id}',
        json: {'modifiedTime': DateTime.now().toUtc().toIso8601String()},
      );
      status = 'Drive 동기화 완료';
      notifyListeners();
      return file;
    }
    const boundary = 'cyviewer_drive_upload_boundary';
    final metadata = jsonEncode({
      'name': name,
      'mimeType': 'application/pdf',
      'appProperties': {'cyViewer': '1', 'cyHash': hash},
      'description': jsonEncode({'v': 1}),
    });
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/pdf\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final row = await _request(
      'POST',
      '/upload/drive/v3/files',
      query: {
        'uploadType': 'multipart',
        'fields': 'id,name,description,appProperties',
      },
      bytes: body.takeBytes(),
      contentType: 'multipart/related; boundary=$boundary',
    );
    if (generation != _generation) throw StateError('계정이 변경되었습니다.');
    status = 'Drive 동기화 완료';
    notifyListeners();
    return DrivePdf.fromJson(row);
  }

  Future<void> save(DrivePdf file, Map<String, dynamic> delta) {
    final generation = _generation;
    status = 'Drive 동기화 중…';
    notifyListeners();
    _pending[file.id] = mergeReading(_pending[file.id] ?? {}, delta);
    final operation = _tail.then((_) async {
      if (generation != _generation || !connected) return;
      final pending = _pending[file.id];
      if (pending == null) return;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final row = await _request(
            'GET',
            '/drive/v3/files/${file.id}',
            query: {'fields': 'id,name,description,appProperties'},
          );
          final merged = mergeReading(DrivePdf.fromJson(row).state, pending);
          await _request(
            'PATCH',
            '/drive/v3/files/${file.id}',
            json: {'description': jsonEncode(merged)},
            headers: row['_etag'] == null
                ? null
                : {'If-Match': row['_etag'] as String},
          );
          if (identical(_pending[file.id], pending)) _pending.remove(file.id);
          file.state = merged;
          error = null;
          status = 'Drive 동기화 완료';
          notifyListeners();
          return;
        } on _Conflict {
          if (attempt == 2) rethrow;
        }
      }
    });
    _tail = operation.catchError((Object _) {
      if (generation == _generation) {
        error = '읽기 상태를 Drive에 저장하지 못했습니다. 연결을 확인해 주세요.';
        notifyListeners();
      }
    });
    return _tail;
  }
}

class _Conflict implements Exception {
  const _Conflict();
}

/// 한 문서의 변경분만 전송합니다. 로그아웃/계정 변경 후의 늦은 작업을 차단합니다.
class DriveReading {
  DriveReading(this.file, this.generation);
  final DrivePdf file;
  final int generation;
  Timer? _timer;
  final Map<String, dynamic> _marks = {};
  Map<String, dynamic>? _page;
  static Future<DriveReading?> open(String name, Uint8List bytes) async {
    final sync = DriveSync.instance;
    if (!sync.connected) return null;
    final generation = sync._generation;
    try {
      final file = await sync.open(name, bytes);
      if (generation != sync._generation) return null;
      return DriveReading(file, generation);
    } catch (_) {
      if (generation == sync._generation) {
        sync.reportError('PDF를 Drive에 동기화하지 못했습니다. 원본은 이 기기에서 계속 읽을 수 있습니다.');
      }
      return null;
    }
  }

  void page(int n) {
    _page = {'n': n, 'at': DateTime.now().millisecondsSinceEpoch};
    _schedule();
  }

  void bookmarks(List<int> before, List<int> after) {
    final at = DateTime.now().millisecondsSinceEpoch;
    for (final n in {...before, ...after}) {
      if (before.contains(n) != after.contains(n)) {
        _marks['$n'] = {'on': after.contains(n), 'at': at};
      }
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), flush);
  }

  void flush() {
    _timer?.cancel();
    if (generation != DriveSync.instance._generation) return;
    if (_page == null && _marks.isEmpty) return;
    final delta = <String, dynamic>{
      'marks': Map<String, dynamic>.from(_marks),
      if (_page != null) 'page': _page,
    };
    _marks.clear();
    _page = null;
    unawaited(DriveSync.instance.save(file, delta));
  }
}
