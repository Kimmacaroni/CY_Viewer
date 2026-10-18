# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = [
    ('native_windows/tessdata', 'tessdata'),
    ('personal_pdf_viewer/windows/runner/resources/app_icon.ico', 'assets'),
    ('personal_pdf_viewer/assets/cy_viewer_icon.png', 'assets'),
]
datas.append(('build/pdfcraft/THIRD_PARTY_NOTICES.txt', 'pdfcraft'))
datas.append(('build/pdf-workbench/bin/THIRD_PARTY_NOTICES.txt', 'pdfcraft/workbench'))
datas.append(('build/pdf-workbench/bin/models', 'pdfcraft/models'))
binaries = [('build/pdfcraft/cy-pdfcraft.exe', 'pdfcraft'), ('build/pdf-workbench/bin/cy-pdf-workbench.exe', 'pdfcraft')]
hiddenimports = ['win32ui']
tmp_ret = collect_all('tkinterdnd2')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    ['native_windows/cy_viewer.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='CYViewer',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['personal_pdf_viewer/windows/runner/resources/app_icon.ico'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='CYViewer',
)
