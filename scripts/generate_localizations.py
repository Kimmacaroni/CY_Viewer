"""공용 번역 원본에서 Flutter 번역 맵을 생성한다."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
values = json.loads((ROOT / 'localization/en.json').read_text())
def dart(value):
    return json.dumps(value, ensure_ascii=False).replace('$', r'\$')
(ROOT / 'macos_app/lib/cy_translations.dart').write_text(
    '// scripts/generate_localizations.py로 생성합니다.\n'
    'const cyEnglish = <String, String>{\n' +
    ''.join(f'  {dart(k)}: {dart(v)},\n' for k, v in values.items()) + '} ;\n')

(ROOT / 'native_windows/cy_translations.py').write_text(
    '# scripts/generate_localizations.py로 생성합니다.\nENGLISH = ' + repr(values) + '\n')

import re
swift = ROOT / 'macos_app/macos/Runner/MainFlutterWindow.swift'
body = 'private let cyNativeEnglish: [String: String] = [\n' + ''.join(
    '  ' + json.dumps(k, ensure_ascii=False) + ': ' + json.dumps(v, ensure_ascii=False) + ',\n'
    for k, v in values.items()) + ']\n'
text = swift.read_text()
text = re.sub(r'// BEGIN GENERATED TRANSLATIONS[\s\S]*?// END GENERATED TRANSLATIONS',
              lambda _: '// BEGIN GENERATED TRANSLATIONS\n' + body + '// END GENERATED TRANSLATIONS', text)
swift.write_text(text)
(ROOT / 'site/download/translations.js').write_text(
    '// scripts/generate_localizations.py로 생성합니다.\n'
    'globalThis.CyEnglish = ' + json.dumps(values, ensure_ascii=False) + ';\n')
