"""Tkinter maintainer publication dialog. Worker threads communicate through a queue."""
import os,queue,threading
from pathlib import Path
from installer_core import Installer
from android_sync import check_updates,prepare,publish,normalize_version,suggested_version
from change_history import notice_preview

def show_android_sync(app):
    tk,ttk=app.tk,app.ttk
    win=tk.Toplevel(app.root);win.title('Đồng bộ Android · GitHub CZN-VH');win.geometry('880x850');win.minsize(760,760)
    frm=ttk.Frame(win,padding=18);frm.pack(fill='both',expand=True)
    ttk.Label(frm,text='Phát hành bản Việt hóa cho APK',font=('Segoe UI',16,'bold')).pack(anchor='w')
    ttk.Label(frm,text='Kho: doubleD1302/CZN-VH · Chỉ tài khoản quản trị có quyền push mới phát hành được.').pack(anchor='w',pady=5)
    ttk.Label(frm,text='Dựng từ catalog đã nhập, chỉ lấy bản dịch đúng nguồn JP. Không ghi tài nguyên game PC.',wraplength=780).pack(anchor='w')
    fields=ttk.Frame(frm);fields.pack(fill='x',pady=12);fields.columnconfigure(1,weight=1)
    version=tk.StringVar(value='');title=tk.StringVar(value='CZN Việt Hóa có bản cập nhật');key=tk.StringVar();token=tk.StringVar()
    default=app.home/'czn_android_patcher/.signing/update-private.pk8'
    if not default.is_file():default=app.home/'.signing/update-private.pk8'
    if default.is_file():key.set(str(default))
    entries=[]
    for row,(label,var,mask) in enumerate([('Phiên bản bản dịch',version,False),('Tiêu đề thông báo',title,False),('Khóa ký cập nhật (.pk8)',key,False),('Token GitHub (tùy chọn)',token,True)]):
        ttk.Label(fields,text=label).grid(row=row,column=0,sticky='w',padx=(0,10),pady=5)
        entry=ttk.Entry(fields,textvariable=var,show='*' if mask else '');entry.grid(row=row,column=1,sticky='ew',pady=5);entries.append(entry)
    def choose():
        path=app.filedialog.askopenfilename(parent=win,title='Chọn khóa update-private.pk8',filetypes=[('Khóa cập nhật','*.pk8')])
        if path:key.set(path)
    browse=ttk.Button(fields,text='Chọn khóa',command=choose);browse.grid(row=2,column=2,padx=(8,0))
    ttk.Label(fields,text='Nhập 1.5, 1.5.0 hoặc v1.5.0; số phiên bản được chuẩn hóa khi dựng gói.').grid(row=4,column=1,sticky='w')
    ttk.Label(frm,text='Token chỉ dùng trong phiên này. Để trống nếu đã đăng nhập Git Credential Manager. Cần PowerShell 7.',wraplength=780).pack(anchor='w')
    ttk.Label(frm,text='Thay đổi chưa phát hành · tự điền khi kiểm tra; đối chiếu lại với gói khi dựng').pack(anchor='w',pady=(12,4))
    automatic=tk.Text(frm,height=6,wrap='word',font=('Segoe UI',10));automatic.pack(fill='x');automatic.insert('1.0','Bấm Kiểm tra cập nhật để lấy bản nền và tổng hợp thay đổi.');automatic.configure(state='disabled')
    ttk.Label(frm,text='Ghi chú thêm vào thông báo trên APK (có thể để trống)').pack(anchor='w',pady=(8,4))
    body=tk.Text(frm,height=3,wrap='word',font=('Segoe UI',10));body.pack(fill='x')
    summary=tk.StringVar(value='1. Kiểm tra GitHub. 2. Dựng và kiểm tra gói. 3. Xem kết quả rồi Phát hành.')
    ttk.Label(frm,textvariable=summary,wraplength=780).pack(anchor='w',pady=10)
    row=ttk.Frame(frm);row.pack(fill='x');q=queue.Queue();state={'busy':False,'preview':None,'fields':None,'channel':None,'suggestion':''}
    logbox=tk.Text(frm,height=8,wrap='word',state='disabled');logbox.pack(fill='both',expand=True,pady=(12,0))
    buttons=[]
    def log(text):q.put(('log',str(text)))
    def values():return version.get().strip(),title.get().strip(),body.get('1.0','end-1c').strip(),key.get().strip()
    def set_automatic(text):
        automatic.configure(state='normal');automatic.delete('1.0','end');automatic.insert('1.0',text);automatic.configure(state='disabled')
    def normalize_entry(event=None):
        try:version.set(normalize_version(version.get()))
        except ValueError:pass
    entries[0].bind('<FocusOut>',normalize_entry)
    def work(kind):
        if state['busy'] or app.busy:return
        if kind=='prepare':normalize_entry()
        snapshot=values();secret=token.get().strip();game_snapshot=app.game_var.get()
        if kind=='publish':
            if not state['preview'] or snapshot!=state['fields']:
                app.messagebox.showinfo('Dựng lại trước', 'Nội dung đã đổi. Hãy dùng phiên bản mới và dựng lại gói.',parent=win);return
            rec=state['preview']
            if not app.messagebox.askyesno('Phát hành lên cộng đồng?',f"Bản {rec['version']}\n{rec['unpublished_count']:,} mục thay đổi so với bản đã phát hành.\n\n{rec['notice']['body']}\n\nGói và thông báo đã ký sẽ trở thành bản mới nhất để APK tự tải. Phát hành?",parent=win):return
        state['busy']=True;app.busy=True
        for b in buttons+app.buttons:b.configure(state='disabled')
        for e in entries:e.configure(state='disabled')
        browse.configure(state='disabled');body.configure(state='disabled')
        def worker():
            try:
                if kind=='check':
                    channel=check_updates();result={'channel':channel,'notice':notice_preview(app.home,channel)}
                elif kind=='prepare':result=prepare(Installer(app.home,game_snapshot,log),snapshot[0],snapshot[1],snapshot[2],snapshot[3],log)
                else:result=publish(state['preview'],secret,log)
                q.put((kind,result))
            except Exception as e:q.put(('error',str(e)))
        threading.Thread(target=worker,daemon=True).start()
    for label,kind in [('Kiểm tra cập nhật','check'),('Dựng & kiểm tra gói','prepare'),('Phát hành lên GitHub','publish')]:
        b=ttk.Button(row,text=label,command=lambda k=kind:work(k));b.pack(side='left',padx=(0,8));buttons.append(b)
    def download():
        channel=state['channel']
        if channel:os.startfile(channel['app_url'])
    b=ttk.Button(row,text='Tải / cập nhật APK',command=download);b.pack(side='left');buttons.append(b)
    buttons[2].configure(state='disabled');buttons[3].configure(state='disabled')
    def poll():
        if not win.winfo_exists():return
        try:
            while True:
                kind,value=q.get_nowait()
                if kind=='log':
                    logbox.configure(state='normal');logbox.insert('end',value+'\n');logbox.see('end');logbox.configure(state='disabled');continue
                state['busy']=False;app.busy=False
                for e in entries:e.configure(state='normal')
                browse.configure(state='normal');body.configure(state='normal')
                for b in buttons+app.buttons:b.configure(state='normal')
                if kind=='check':
                    channel=value['channel'];state['channel']=channel
                    # Checking GitHub must preserve a version the maintainer typed.
                    if not version.get().strip() or version.get()==state['suggestion']:version.set(suggested_version(channel))
                    state['suggestion']=suggested_version(channel);set_automatic(value['notice'])
                    summary.set(f"GitHub: bản dịch {channel['patch_version']} · APK {channel['app_version']}. Gợi ý phiên bản chưa dùng: {state['suggestion']}.")
                    log(channel.get('changelog',''))
                elif kind=='prepare':
                    version.set(value['version']);title.set(value['notice']['title']);set_automatic(value['automatic_notice'])
                    state['preview']=value;state['fields']=values();ev=value['evidence']
                    summary.set(f"Sẵn sàng: v{value['version']} · {value['unpublished_count']:,} mục thay đổi chưa phát hành.\nGói: {ev['bundle_bytes']:,} byte · SHA-256 {ev['bundle_sha256']}")
                elif kind=='publish':summary.set('Đã phát hành và xác thực: '+value['url']);state['preview']=None;token.set('');set_automatic('Đã ghi nhận gói phát hành. Bấm Kiểm tra cập nhật để tổng hợp các thay đổi tiếp theo.')
                else:summary.set('Chưa hoàn tất: '+value);log(value)
                buttons[2].configure(state='normal' if state['preview'] else 'disabled');buttons[3].configure(state='normal' if state['channel'] else 'disabled')
        except queue.Empty:pass
        win.after(100,poll)
    def close():
        if state['busy']:app.messagebox.showinfo('Đang xử lý','Chờ dựng/tải lên hoàn tất trước khi đóng.',parent=win);return
        token.set('');win.destroy()
    win.protocol('WM_DELETE_WINDOW',close);win.after(100,poll);win.after(200,lambda:work('check'))
    return win
