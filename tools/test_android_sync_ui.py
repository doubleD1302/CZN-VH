import tempfile
import time
import tkinter as tk
from tkinter import ttk
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock,patch
from android_sync_ui import show_android_sync

class SyncUITests(unittest.TestCase):
    def test_check_keeps_typed_version_and_fills_separate_automatic_notice(self):
        root=tk.Tk();root.withdraw();self.addCleanup(root.destroy)
        with tempfile.TemporaryDirectory() as temp:
            app=SimpleNamespace(tk=tk,ttk=ttk,root=root,home=Path(temp),busy=False,buttons=[],
                                game_var=tk.StringVar(master=root,value=temp),filedialog=Mock(),messagebox=Mock())
            channel={'patch_version':'1.4.3','patch_code':10403,'app_version':'1.5.1','app_code':10501,'changelog':'fixture'}
            with patch('android_sync_ui.check_updates',return_value=channel),patch('android_sync_ui.notice_preview',return_value='5 mục Việt hóa mới'):
                win=show_android_sync(app);win.withdraw()
                def children(widget):
                    result=[]
                    for child in widget.winfo_children():result.append(child);result.extend(children(child))
                    return result
                widgets=children(win);entries=[w for w in widgets if isinstance(w,ttk.Entry)]
                entries[0].insert(0,'1.6')
                manual=next(w for w in widgets if isinstance(w,tk.Text) and str(w.cget('height'))=='3')
                manual.insert('1.0','Ghi chú người dùng')
                check=next(w for w in widgets if isinstance(w,ttk.Button) and w.cget('text')=='Kiểm tra cập nhật')
                check.invoke()
                until=time.monotonic()+2
                while time.monotonic()<until:
                    root.update()
                    if not app.busy and time.monotonic()>until-1:break
                    time.sleep(.01)
                self.assertEqual(entries[0].get(),'1.6')
                self.assertEqual(manual.get('1.0','end-1c'),'Ghi chú người dùng')
                automatic=next(w for w in widgets if isinstance(w,tk.Text) and str(w.cget('height'))=='6')
                self.assertEqual(automatic.get('1.0','end-1c'),'5 mục Việt hóa mới')
                self.assertEqual(str(automatic.cget('state')),'disabled')
                entries[0].event_generate('<FocusOut>');root.update()
                self.assertEqual(entries[0].get(),'1.6.0')
                app.messagebox.showerror.assert_not_called()
                win.destroy()

if __name__=='__main__':unittest.main()
