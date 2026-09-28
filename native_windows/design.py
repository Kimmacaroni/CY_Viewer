"""Mac의 공통 디자인 토큰. Windows 앱 테마 설정을 실행 시 따른다."""
import sys


def system_dark():
    if sys.platform != 'win32':
        return False
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                            r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') as key:
            return winreg.QueryValueEx(key, 'AppsUseLightTheme')[0] == 0
    except OSError:
        return False


def palette(dark=False):
    return {
        'ink': '#E8EDF5' if dark else '#182235',
        'muted': '#ACB8CA' if dark else '#526174',
        'line': '#354154' if dark else '#DCE2EB',
        'surface': '#191F2A' if dark else '#FFFFFF',
        'canvas': '#10141C' if dark else '#F4F6F9',
        'blue': '#A9C5FF' if dark else '#245EDB',
        'on_blue': '#132746' if dark else '#FFFFFF',
        'blue_soft': '#223754' if dark else '#EAF1FF',
        'green': '#86EFAC' if dark else '#15803D',
        'red': '#FCA5A5' if dark else '#DC2626',
        'sidebar': '#191F2A' if dark else '#FFFFFF',
    }
