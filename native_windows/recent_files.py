"""최근 성공적으로 열린 파일 경로 5개만 기기에 저장한다."""
import json
import os
from pathlib import Path


def store_path():
    return Path(os.environ.get('APPDATA', Path.home())) / 'CYViewer' / 'recent-files.json'


def load_recent():
    try:
        values = json.loads(store_path().read_text(encoding='utf-8'))
        if not isinstance(values, list): return []
        result = []
        seen = set()
        for value in values:
            if not isinstance(value, str): continue
            key = os.path.normcase(os.path.abspath(value))
            if key not in seen:
                result.append(value)
                seen.add(key)
        return result[:5]
    except (OSError, ValueError):
        return []


def remember(path):
    path = str(Path(path).resolve())
    key = os.path.normcase(path)
    values = [path] + [p for p in load_recent() if os.path.normcase(os.path.abspath(p)) != key]
    values = values[:5]
    target = store_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(values, ensure_ascii=False), encoding='utf-8')
    temporary.replace(target)
    return values
