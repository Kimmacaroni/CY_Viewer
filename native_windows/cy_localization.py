"""기기 언어 감지, 다음 실행의 언어 설정 및 공용 번역."""
import ctypes
import json
import locale
import os
from pathlib import Path
from cy_translations import ENGLISH


def settings_path():
    return Path(os.environ.get('APPDATA', Path.home())) / 'CYViewer' / 'language.json'


def system_language():
    try:
        return 'ko' if ctypes.windll.kernel32.GetUserDefaultUILanguage() & 0x3ff == 0x12 else 'en'
    except AttributeError:
        return 'ko' if (locale.getlocale()[0] or '').lower().startswith('ko') else 'en'


def load_mode():
    try:
        mode = json.loads(settings_path().read_text(encoding='utf-8')).get('language')
        return mode if mode in ('system', 'ko', 'en') else 'system'
    except (OSError, ValueError, AttributeError):
        return 'system'


MODE = load_mode()
LANGUAGE = system_language() if MODE == 'system' else MODE


def save_mode(mode):
    if mode not in ('system', 'ko', 'en'):
        raise ValueError('Unsupported language')
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps({'language': mode}), encoding='utf-8')
    temporary.replace(path)


def tr(source, *args):
    import re
    template = source if LANGUAGE == 'ko' else ENGLISH.get(source, source)
    return re.sub(r'\{(\d+)\}', lambda m: str(args[int(m[1])]) if int(m[1]) < len(args) else m[0], template)
