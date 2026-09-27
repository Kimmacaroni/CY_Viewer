"""개인 Google Drive 동기화. 인증 토큰은 현재 실행의 메모리에만 유지합니다."""
from __future__ import annotations
import base64
import hashlib
import http.server
import json
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
try:
    from drive_build_config import CLIENT_SECRET
except ImportError:
    CLIENT_SECRET = ""

CLIENT_ID = '99146066883-tr494pci27mpsvc9fhdr7skp8p9o6j1n.apps.googleusercontent.com'
SCOPE = 'https://www.googleapis.com/auth/drive.file'


def valid_reading(value):
    result = {'v': 1}
    page = value.get('page')
    if isinstance(page, dict) and type(page.get('n')) is int and page['n'] > 0 and type(page.get('at')) is int and page['at'] >= 0:
        result['page'] = {'n': page['n'], 'at': page['at']}
    if isinstance(value.get('marks'), dict):
        result['marks'] = {str(n): {'on': v['on'], 'at': v['at']} for n, v in value['marks'].items()
            if str(n).isdigit() and int(n) > 0 and isinstance(v, dict) and type(v.get('on')) is bool and type(v.get('at')) is int and v['at'] >= 0}
    return result


def merge_reading(remote, local):
    remote, local = valid_reading(remote), valid_reading(local)
    marks = dict(remote.get('marks', {}))
    for key, value in local.get('marks', {}).items():
        if value['at'] >= marks.get(key, {}).get('at', 0):
            marks[key] = value
    page = remote.get('page', {'n': 1, 'at': 0})
    if local.get('page', {}).get('at', -1) >= page.get('at', 0):
        page = local['page']
    return {'v': 1, 'marks': marks, 'page': page}


def reading(row):
    try:
        value = json.loads(row.get('description', '{}'))
        return valid_reading(value) if isinstance(value, dict) else {}
    except (ValueError, TypeError):
        return {}


class Drive:
    def __init__(self):
        self.token = None
        self.account = None
        self.pending = {}

    def connect(self):
        if not CLIENT_SECRET:
            raise RuntimeError('배포용 Google 연결 설정이 없습니다. 최신 설치 파일을 사용해 주세요.')
        state, verifier = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        result = {}
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass  # 인증 코드/URL을 로그에 남기지 않습니다.
            def do_GET(self):
                url = urllib.parse.urlparse(self.path)
                query = urllib.parse.parse_qs(url.query)
                valid = url.path == '/oauth/callback' and secrets.compare_digest(query.get('state', [''])[0], state)
                self.send_response(200 if valid else 400)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write('<meta charset="utf-8"><p>CY뷰어로 돌아가 연결 결과를 확인하세요.</p>'.encode())
                if valid:
                    result.update(code=query.get('code', [None])[0], done=True)
        with http.server.HTTPServer(('127.0.0.1', 0), Handler) as server:
            server.timeout = 1
            redirect = f'http://127.0.0.1:{server.server_port}/oauth/callback'
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
            url = 'https://accounts.google.com/o/oauth2/v2/auth?' + urllib.parse.urlencode({
                'client_id': CLIENT_ID, 'redirect_uri': redirect, 'response_type': 'code', 'scope': SCOPE,
                'state': state, 'code_challenge': challenge, 'code_challenge_method': 'S256', 'prompt': 'select_account'})
            if not webbrowser.open(url):
                raise RuntimeError('브라우저를 열지 못했습니다.')
            deadline = time.monotonic() + 120
            while not result.get('done') and time.monotonic() < deadline:
                server.handle_request()
        if not result.get('code'):
            raise RuntimeError('Google 연결을 완료하지 못했습니다. 다시 연결해 주세요.')
        body = urllib.parse.urlencode({'client_id': CLIENT_ID, 'client_secret': CLIENT_SECRET, 'code': result['code'], 'code_verifier': verifier,
            'redirect_uri': redirect, 'grant_type': 'authorization_code'}).encode()
        try:
            with urllib.request.urlopen(urllib.request.Request('https://oauth2.googleapis.com/token', data=body), timeout=30) as response:
                token = json.load(response)
            if SCOPE not in token.get('scope', '').split():
                raise RuntimeError('Drive 파일 권한이 필요합니다.')
            self.token = token['access_token']
            self.account = self.request('GET', '/drive/v3/about', query={'fields': 'user(emailAddress)'})['user']['emailAddress']
        except Exception:
            self.token = None
            raise RuntimeError('Google 인증을 완료하지 못했습니다. 다시 연결해 주세요.') from None
        return self.recent()

    def request(self, method, path, query=None, data=None, raw=None, content_type=None, etag=None):
        if not self.token:
            raise RuntimeError('Google Drive에 연결해 주세요.')
        url = 'https://www.googleapis.com' + path
        if query:
            url += '?' + urllib.parse.urlencode(query)
        headers = {'Authorization': 'Bearer ' + self.token}
        if data is not None:
            raw = json.dumps(data, ensure_ascii=False).encode()
            content_type = 'application/json; charset=utf-8'
        if content_type:
            headers['Content-Type'] = content_type
        if etag:
            headers['If-Match'] = etag
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=raw, headers=headers, method=method), timeout=60) as response:
                body = response.read()
                if query and query.get('alt') == 'media':
                    return body
                result = json.loads(body) if body else {}
                result['_etag'] = response.headers.get('ETag')
                return result
        except urllib.error.HTTPError as error:
            if error.code == 412:
                raise Conflict() from None
            if error.code == 401:
                self.token = None
                raise RuntimeError('연결이 만료되었습니다. Google Drive에 다시 연결해 주세요.') from None
            raise RuntimeError('Drive 동기화에 실패했습니다. 연결과 저장 공간을 확인해 주세요.') from None

    def recent(self):
        return self.request('GET', '/drive/v3/files', query={
            'q': "trashed = false and mimeType = 'application/pdf' and appProperties has { key='cyViewer' and value='1' }",
            'orderBy': 'modifiedTime desc', 'pageSize': '5', 'fields': 'files(id,name,description,appProperties)'})['files']

    def download(self, row):
        data = self.request('GET', '/drive/v3/files/' + urllib.parse.quote(row['id'], safe=''), query={'alt': 'media'})
        if hashlib.sha256(data).hexdigest() != row.get('appProperties', {}).get('cyHash'):
            raise RuntimeError('Drive 파일 내용이 변경되었습니다. 원본을 다시 선택해 주세요.')
        return data

    def open(self, name, data):
        digest = hashlib.sha256(data).hexdigest()
        rows = self.request('GET', '/drive/v3/files', query={'q': "trashed = false and appProperties has { key='cyViewer' and value='1' } and appProperties has { key='cyHash' and value='" + digest + "' }", 'pageSize': '1', 'fields': 'files(id,name,description,appProperties)'})['files']
        if rows:
            row = rows[0]
            self.request('PATCH', '/drive/v3/files/' + row['id'], data={'modifiedTime': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
            return row
        boundary = 'cyviewer_drive_' + secrets.token_hex(16)
        metadata = json.dumps({'name': name, 'mimeType': 'application/pdf', 'appProperties': {'cyViewer': '1', 'cyHash': digest}, 'description': '{"v":1}'}, ensure_ascii=False)
        raw = ('--' + boundary + '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' + metadata + '\r\n--' + boundary + '\r\nContent-Type: application/pdf\r\n\r\n').encode() + data + ('\r\n--' + boundary + '--\r\n').encode()
        return self.request('POST', '/upload/drive/v3/files', query={'uploadType':'multipart', 'fields':'id,name,description,appProperties'}, raw=raw, content_type='multipart/related; boundary=' + boundary)

    def save(self, row, delta):
        delta = merge_reading(self.pending.get(row['id'], {}), delta)
        self.pending[row['id']] = delta
        for attempt in range(3):
            current = self.request('GET', '/drive/v3/files/' + row['id'], query={'fields':'id,name,description,appProperties'})
            merged = merge_reading(reading(current), delta)
            try:
                self.request('PATCH', '/drive/v3/files/' + row['id'], data={'description':json.dumps(merged)}, etag=current.get('_etag'))
                self.pending.pop(row['id'], None)
                row['description'] = json.dumps(merged)
                return
            except Conflict:
                if attempt == 2:
                    raise RuntimeError('동시에 변경된 읽기 상태를 저장하지 못했습니다. 다시 시도해 주세요.') from None


class Conflict(Exception):
    pass
