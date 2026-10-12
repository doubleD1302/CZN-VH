"""Request normal Windows UAC only for operations that need protected file writes."""
import ctypes
import os
from pathlib import Path
import subprocess
import sys
from installer_core import check_write_access, read_json


def needs_admin(game):
    if os.name != 'nt' or ctypes.windll.shell32.IsUserAnAdmin():
        return False
    resources = Path(game) / 'bin/appdata/cznlive/gameres'
    manifest = resources / 'manifest.ssra'
    if not manifest.exists():
        return False
    try:
        metadata = [resources / name for name in ('manifest.ssra.etag', 'manifest.ssra.prev') if (resources / name).exists()]
        story_chunk = resources / 'chunks/base_b21_0.ssrc'
        check_write_access([manifest, *metadata, *(resources / 'chunks').glob('lang_ja_*.ssrc'),
                            *([story_chunk] if story_chunk.exists() else [])])
        return False
    except PermissionError:
        return True


def run_elevated(home, game, action, result_path, log):
    from ctypes import wintypes as wt

    class ShellInfo(ctypes.Structure):
        _fields_ = [
            ('cbSize', wt.DWORD), ('fMask', wt.ULONG), ('hwnd', wt.HWND),
            ('lpVerb', wt.LPCWSTR), ('lpFile', wt.LPCWSTR), ('lpParameters', wt.LPCWSTR),
            ('lpDirectory', wt.LPCWSTR), ('nShow', ctypes.c_int), ('hInstApp', wt.HINSTANCE),
            ('lpIDList', ctypes.c_void_p), ('lpClass', wt.LPCWSTR), ('hkeyClass', wt.HKEY),
            ('dwHotKey', wt.DWORD), ('hIcon', wt.HANDLE), ('hProcess', wt.HANDLE),
        ]

    home, game, result_path = Path(home).resolve(), Path(game).resolve(), Path(result_path).resolve()
    args = ['--' + action, '--home', str(home), '--game', str(game), '--result', str(result_path), '--no-elevate']
    if not getattr(sys, 'frozen', False):
        args.insert(0, str(Path(__file__).resolve().parent / 'app.py'))
    shell = ctypes.WinDLL('shell32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    ole = ctypes.OleDLL('ole32')
    info = ShellInfo()
    info.cbSize = ctypes.sizeof(info)
    info.fMask = 0x40
    info.lpVerb = 'runas'
    info.lpFile = sys.executable
    info.lpParameters = subprocess.list2cmdline(args)
    info.lpDirectory = str(home)
    info.nShow = 1
    shell.ShellExecuteExW.argtypes = [ctypes.POINTER(ShellInfo)]
    shell.ShellExecuteExW.restype = wt.BOOL
    kernel.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
    kernel.WaitForSingleObject.restype = wt.DWORD
    kernel.CloseHandle.argtypes = [wt.HANDLE]
    initialized = ole.CoInitializeEx(None, 2) in (0, 1)
    log('Windows cần quyền Administrator để ghi file game. Đang chờ xác nhận UAC...')
    try:
        if not shell.ShellExecuteExW(ctypes.byref(info)):
            error = ctypes.get_last_error()
            if error == 1223:
                raise RuntimeError('UAC đã bị hủy. Game được giữ nguyên; bấm thao tác lại khi sẵn sàng.')
            raise ctypes.WinError(error)
        if not info.hProcess:
            raise RuntimeError('Không lấy được trạng thái tiến trình nâng quyền.')
        log('Đã mở tiến trình cài đặt có quyền ghi. Đang dựng và kiểm tra dữ liệu...')
        while True:
            status = kernel.WaitForSingleObject(info.hProcess, 1000)
            if status == 0:
                break
            if status != 258:
                raise ctypes.WinError(ctypes.get_last_error())
        result = read_json(result_path)
        if not result:
            raise RuntimeError('Tiến trình nâng quyền chưa tạo báo cáo kết quả.')
        for line in result.get('log', []):
            log(line)
        if not result.get('ok'):
            raise RuntimeError(result.get('error', 'Thao tác nâng quyền không hoàn tất.'))
        return result['result']
    finally:
        if info.hProcess:
            kernel.CloseHandle(info.hProcess)
        if initialized:
            ole.CoUninitialize()
