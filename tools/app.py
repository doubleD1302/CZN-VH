from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import queue
import sys
import threading
import traceback
import uuid

from installer_core import Installer, VERSION, read_json, write_json
from elevation import needs_admin, run_elevated


def project_home():
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


class App:
    def __init__(self, home, game, smoke=False):
        import tkinter as tk
        from tkinter import ttk, filedialog, messagebox
        self.tk, self.ttk = tk, ttk
        self.filedialog, self.messagebox = filedialog, messagebox
        self.home = home
        self.q = queue.Queue()
        self.busy = False
        self.buttons = []
        self.root = tk.Tk()
        self.root.title('Chaos Zero Nightmare · Việt hóa JP → VI')
        self.root.geometry('1040x760')
        self.root.minsize(940, 700)
        self.root.configure(bg='#101827')
        style = ttk.Style(self.root)
        style.theme_use('clam')
        style.configure('.', font=('Segoe UI', 10))
        style.configure('Primary.TButton', background='#37b6a4', foreground='#081e24', padding=(20, 13), font=('Segoe UI', 11, 'bold'))
        style.map('Primary.TButton', background=[('active', '#7cddce'), ('disabled', '#334155')])
        style.configure('Action.TButton', background='#26384f', foreground='#f1f5f9', padding=(14, 10))
        style.map('Action.TButton', background=[('active', '#395673'), ('disabled', '#1e293b')])
        style.configure('Horizontal.TProgressbar', background='#37b6a4', troughcolor='#26384f', bordercolor='#26384f')
        self._label(self.root, 'CZN  /  VIỆT HÓA', 12, '#37b6a4', bold=True).pack(anchor='w', padx=32, pady=(25, 8))
        self._label(self.root, 'Chaos Zero Nightmare', 25, '#f8fafc', bold=True).pack(anchor='w', padx=30)
        self._label(self.root, 'Bộ cài JP → VI  •  v' + VERSION + '  •  Bản dịch cộng đồng, đang hoàn thiện theo từng đợt', 10, '#aabbd0').pack(anchor='w', padx=32, pady=(6, 20))
        path_card = tk.Frame(self.root, bg='#192539')
        path_card.pack(fill='x', padx=30)
        self._label(path_card, 'THƯ MỤC GAME', 9, '#8da2ba', bg='#192539', bold=True).pack(anchor='w', padx=18, pady=(14, 7))
        path_line = tk.Frame(path_card, bg='#192539')
        path_line.pack(fill='x', padx=18, pady=(0, 16))
        self.game_var = tk.StringVar(value=str(game))
        entry = tk.Entry(path_line, textvariable=self.game_var, font=('Segoe UI', 10), bg='#101827', fg='#e2e8f0', insertbackground='white', relief='flat')
        entry.pack(side='left', fill='x', expand=True, ipady=9, padx=(0, 12))
        self.path_entry = entry
        self._button(path_line, 'Chọn thư mục', self.choose_game).pack(side='right')
        stats = tk.Frame(self.root, bg='#101827')
        stats.pack(fill='x', padx=30, pady=16)
        self.stats_var = tk.StringVar(value='Chưa kiểm tra dữ liệu')
        self._label(stats, '', 14, '#f8fafc', bold=True, variable=self.stats_var).pack(anchor='w')
        self.status_var = tk.StringVar(value='Sẵn sàng. Đóng game trước khi cài hoặc cập nhật bản Việt hóa.')
        self._label(stats, '', 10, '#aabbd0', variable=self.status_var).pack(anchor='w', pady=(6, 0))
        actions = tk.Frame(self.root, bg='#101827')
        actions.pack(fill='x', padx=30, pady=(0, 12))
        self._button(actions, 'Cài Việt hóa', lambda: self.run('install'), primary=True).pack(side='left', padx=(0, 10))
        self._button(actions, 'Cập nhật theo game', lambda: self.run('update')).pack(side='left', padx=(0, 10))
        self._button(actions, 'Nhập bản dịch mới', self.import_file).pack(side='left', padx=(0, 10))
        self._button(actions, 'Khôi phục bản gốc', lambda: self.run('restore')).pack(side='left')
        self._label(self.root, 'Sau khi STOVE cập nhật xong: bấm Cập nhật theo game. Câu Nhật mới hoặc đã sửa sẽ được xuất để dịch tiếp.', 10, '#aabbd0').pack(anchor='w', padx=32, pady=(0, 12))
        utility = tk.Frame(self.root, bg='#101827')
        utility.pack(fill='x', padx=30, pady=(0, 12))
        self._button(utility, 'Kiểm tra & xuất danh sách cần dịch', lambda: self.run('sync')).pack(side='left')
        self._button(utility, 'Mở báo cáo', self.open_reports).pack(side='left', padx=(10, 0))
        self._button(utility, 'Đồng bộ Android / GitHub', self.android_sync).pack(side='left', padx=(10, 0))
        self.progress = ttk.Progressbar(self.root, mode='indeterminate')
        self.progress.pack(fill='x', padx=30, pady=(0, 12))
        log_frame = tk.Frame(self.root, bg='#101827')
        log_frame.pack(fill='both', expand=True, padx=30)
        self.output = tk.Text(log_frame, bg='#0b1220', fg='#d1dee9', font=('Consolas', 10), relief='flat', wrap='word', padx=15, pady=12, state='disabled')
        self.output.pack(side='left', fill='both', expand=True)
        scroll = ttk.Scrollbar(log_frame, command=self.output.yview)
        scroll.pack(side='right', fill='y')
        self.output.configure(yscrollcommand=scroll.set)
        self._label(self.root, 'Trong game, chọn ngôn ngữ văn bản 日本語 để hiển thị chữ Việt. Nhập bản dịch mới từ JSON hoặc CSV.', 10, '#8da2ba').pack(anchor='w', padx=32, pady=16)
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        self.refresh_status()
        self.root.after(5000, self.watch_status)
        self.root.after(100, self.poll)
        if smoke:
            self.root.withdraw()
            self.root.update_idletasks()
            self.smoke_result = {'title': self.root.title(), 'buttons': len(self.buttons),
                                 'width': self.root.winfo_width(), 'height': self.root.winfo_height()}
            self.root.destroy()

    def _label(self, parent, text, size, color, bold=False, bg='#101827', variable=None):
        return self.tk.Label(parent, text=text, textvariable=variable, font=('Segoe UI', size, 'bold' if bold else 'normal'), fg=color, bg=bg, anchor='w')

    def _button(self, parent, text, command, primary=False):
        b = self.ttk.Button(parent, text=text, command=command, style='Primary.TButton' if primary else 'Action.TButton')
        self.buttons.append(b)
        return b

    def log(self, message):
        self.q.put(('log', str(message)))

    def refresh_status(self, report=None):
        report = report or read_json(self.home / 'data/reports/TRANG_THAI.json', {})
        try:
            status = Installer(self.home, self.game_var.get(), log=lambda _: None).status()
            self.status_var.set(status['message'])
        except Exception as e:
            self.status_var.set('Chưa xác minh được file game: ' + str(e))
        if report:
            rows, ready = report.get('rows', 0), report.get('ready', report.get('translated', 0))
            percent = ready * 100 / max(rows, 1)
            self.stats_var.set(f'{ready:,} / {rows:,} mục sẵn sàng  ·  {percent:.1f}%')
            story = report.get('story', {})
            if story.get('enabled'):
                chapters = story.get('chapters', {})
                detail = '  ·  '.join(f'Chương {ch}: {data["translated"]}/{data["total"]}'
                                       for ch,data in chapters.items())
                self.stats_var.set(self.stats_var.get() + '  ·  ' + (detail or
                    f'Cốt truyện: {story.get("translated", 0)}/{story.get("total", 0)}'))

    def watch_status(self):
        if not self.busy:
            self.refresh_status()
        self.root.after(5000, self.watch_status)

    def choose_game(self):
        selected = self.filedialog.askdirectory(title='Chọn thư mục ChaosZeroNightmare', initialdir=self.game_var.get())
        if selected:
            self.game_var.set(selected)
            write_json(self.home / 'data/settings.json', {'game_dir': selected})
            self.refresh_status()

    def import_file(self):
        selected = self.filedialog.askopenfilename(title='Chọn bản dịch có ID, nguồn Nhật và tiếng Việt', filetypes=[('Bản dịch JSON / CSV', '*.json *.csv')])
        if selected:
            self.run('import', selected)

    def android_sync(self):
        if self.busy:
            return
        from android_sync_ui import show_android_sync
        show_android_sync(self)

    def open_reports(self):
        p = self.home / 'data/reports'
        p.mkdir(parents=True, exist_ok=True)
        os.startfile(p)

    def run(self, action, filename=None):
        if self.busy:
            return
        self.busy = True
        for b in self.buttons:
            b.configure(state='disabled')
        self.path_entry.configure(state='disabled')
        self.status_var.set('Đang xử lý dữ liệu...')
        self.progress.start(14)
        game = self.game_var.get()
        write_json(self.home / 'data/settings.json', {'game_dir': game})

        def worker():
            try:
                if action in ('install', 'update', 'restore') and needs_admin(game):
                    result_path = self.home / 'data/reports' / ('uac-' + uuid.uuid4().hex + '.json')
                    result = run_elevated(self.home, game, 'install' if action == 'update' else action, result_path, self.log)
                    self.q.put(('done', None if action == 'restore' else result))
                    return
                inst = Installer(self.home, game, self.log)
                if action in ('install', 'update'):
                    if action == 'update':
                        self.log('Đồng bộ game mới, giữ bản dịch có nguồn Nhật không đổi và dựng lại gói...')
                    result = inst.install()
                elif action == 'restore':
                    inst.restore()
                    result = None
                elif action == 'sync':
                    result = inst.sync()[3]
                else:
                    inst.import_translations(filename)
                    result = inst.sync()[3]
                self.q.put(('done', result))
            except Exception as e:
                self.log('LỖI: ' + str(e))
                atomic_error(self.home, traceback.format_exc())
                self.q.put(('error', str(e)))
        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        try:
            while True:
                event, value = self.q.get_nowait()
                if event == 'log':
                    self.output.configure(state='normal')
                    self.output.insert('end', value + '\n')
                    self.output.see('end')
                    self.output.configure(state='disabled')
                else:
                    self.busy = False
                    self.progress.stop()
                    for b in self.buttons:
                        b.configure(state='normal')
                    self.path_entry.configure(state='normal')
                    self.refresh_status(value if event == 'done' else None)
                    if event == 'error':
                        self.status_var.set('Thao tác chưa hoàn tất. Xem lý do trong nhật ký bên dưới.')
                        self.messagebox.showerror('Chưa hoàn tất', value)
                    else:
                        self.log('Hoàn tất. Bản sao lưu và lịch sử được lưu trong thư mục data.')
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def close(self):
        if self.busy:
            self.messagebox.showinfo('Đang xử lý', 'Hãy chờ thao tác hoàn tất trước khi đóng bộ cài.')
            return
        self.root.destroy()


def atomic_error(home, message):
    from installer_core import atomic_bytes
    atomic_bytes(home / 'data/reports/LOI_CHI_TIET.txt', message.encode('utf-8'))


def main():
    p = argparse.ArgumentParser(description='Bộ cài Việt hóa Chaos Zero Nightmare')
    p.add_argument('--home', type=Path, default=project_home())
    p.add_argument('--game', type=Path)
    p.add_argument('--result', type=Path)
    p.add_argument('--no-elevate', action='store_true', help=argparse.SUPPRESS)
    group = p.add_mutually_exclusive_group()
    for action in ('sync', 'build', 'install', 'restore', 'status', 'ui-smoke', 'android-check'):
        group.add_argument('--' + action, action='store_true')
    group.add_argument('--import-file', type=Path)
    args = p.parse_args()
    home = args.home.resolve()
    game = args.game or Path(read_json(home / 'data/settings.json', {}).get('game_dir', home.parent))
    lines = []

    def logger(message):
        lines.append(str(message))
        if sys.stdout:
            print(message, flush=True)

    try:
        if args.android_check:
            from android_sync import check_updates
            result = check_updates()
        elif args.ui_smoke:
            result = App(home, game, smoke=True).smoke_result
        elif any((args.sync, args.build, args.install, args.restore, args.status, args.import_file)):
            if (args.install or args.restore) and not args.no_elevate and needs_admin(game):
                result_path = args.result or home / 'data/reports' / ('uac-' + uuid.uuid4().hex + '.json')
                run_elevated(home, game, 'install' if args.install else 'restore', result_path, logger)
                return 0
            inst = Installer(home, game, logger)
            if args.sync:
                result = inst.sync()[3]
            elif args.build:
                _, build, result = inst.build()
                result = result | {'build_path': str(build)}
            elif args.install:
                result = inst.install()
            elif args.restore:
                inst.restore()
                result = {'restored': True}
            elif args.import_file:
                result = inst.import_translations(args.import_file)
            else:
                result = inst.status() | {'report': read_json(home / 'data/reports/TRANG_THAI.json', {})}
        else:
            app = App(home, game)
            app.root.mainloop()
            return 0
        if args.result:
            write_json(args.result, {'ok': True, 'result': result, 'log': lines})
        elif sys.stdout:
            print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as e:
        logger(str(e))
        atomic_error(home, traceback.format_exc())
        if args.result:
            write_json(args.result, {'ok': False, 'error': str(e), 'log': lines})
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
