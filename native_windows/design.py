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
        'ink': '#F2F2F7' if dark else '#1D1D1F',
        'muted': '#AEAEB2' if dark else '#636366',
        'line': '#48484A' if dark else '#D1D1D6',
        'surface': '#242426' if dark else '#FFFFFF',
        'canvas': '#1C1C1E' if dark else '#F2F2F7',
        'blue': '#A9C5FF' if dark else '#245EDB',
        'blue_hover': '#BDD3FF' if dark else '#1D4ED8',
        'blue_pressed': '#91B5FF' if dark else '#1943B6',
        'on_blue': '#132746' if dark else '#FFFFFF',
        'blue_soft': '#223754' if dark else '#EAF1FF',
        'green': '#86EFAC' if dark else '#15803D',
        'red': '#FCA5A5' if dark else '#DC2626',
        'sidebar': '#242426' if dark else '#F2F2F7',
    }
