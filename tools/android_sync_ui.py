"""Tkinter maintainer publication dialog. Worker threads communicate through a queue."""
import os,queue,threading,json
from pathlib import Path
from installer_core import Installer
from android_sync import check_updates,prepare,publish,normalize_version,suggested_version
from change_history import notice_preview_data
from android_sync import load_player_details

def confirm_publish_dialog(parent, rec, tk, ttk):
    """Hộp thoại xác nhận phát hành có thanh cuộn riêng, cố định nút bấm ở đáy."""
    confirmed = [False]
    dlg = tk.Toplevel(parent)
    dlg.title('Phát hành lên cộng đồng?')
    dlg.geometry('760x540')
    dlg.minsize(620, 420)
    dlg.transient(parent)

    frm = ttk.Frame(dlg, padding=16)
    frm.pack(fill='both', expand=True)

    # 1. Header ở trên cùng
    top_frame = ttk.Frame(frm)
    top_frame.pack(side='top', fill='x', pady=(0, 8))
    header = f"Bản {rec['version']} · {rec['unpublished_count']:,} mục thay đổi so với bản đã phát hành."
    ttk.Label(top_frame, text=header, font=('Segoe UI', 11, 'bold')).pack(anchor='w', pady=(0, 4))
    ttk.Label(top_frame, text='Nội dung thông báo phát hành gửi tới người chơi (cuộn để xem đầy đủ):').pack(anchor='w')

    # 2. Khung nút bấm cố định ở ĐÁY (pack side=bottom trước để luôn luôn hiển thị)
    bottom_frame = ttk.Frame(frm)
    bottom_frame.pack(side='bottom', fill='x', pady=(10, 0))

    sub_note = 'APK mới (giao diện, icon, chức năng), bản dịch và thông báo đã ký sẽ cùng được phát hành. Bạn có muốn phát hành?'
    ttk.Label(bottom_frame, text=sub_note, font=('Segoe UI', 9, 'italic')).pack(anchor='w', pady=(0, 10))

    btn_frame = ttk.Frame(bottom_frame)
    btn_frame.pack(fill='x')

    def on_ok():
        confirmed[0] = True
        dlg.destroy()

    def on_cancel():
        confirmed[0] = False
        dlg.destroy()

    btn_cancel = ttk.Button(btn_frame, text='Hủy bỏ', command=on_cancel, width=14)
    btn_cancel.pack(side='right', padx=(8, 0))

    btn_ok = ttk.Button(btn_frame, text='Xác nhận phát hành', command=on_ok, width=22)
    btn_ok.pack(side='right')

    # 3. Khung cuộn ở GIỮA (pack sau với expand=True để co giãn vừa vặn phần còn lại)
    text_frame = ttk.Frame(frm)
    text_frame.pack(side='top', fill='both', expand=True)

    txt = tk.Text(text_frame, wrap='word', font=('Segoe UI', 9), height=10)
    txt.pack(side='left', fill='both', expand=True)

    sb = ttk.Scrollbar(text_frame, orient='vertical', command=txt.yview)
    sb.pack(side='right', fill='y')
    txt.configure(yscrollcommand=sb.set)

    txt.insert('1.0', rec.get('notice', {}).get('body', ''))
    txt.configure(state='disabled')

    dlg.protocol('WM_DELETE_WINDOW', on_cancel)
    dlg.bind('<Escape>', lambda e: on_cancel())
    dlg.bind('<Return>', lambda e: on_ok())
    btn_ok.focus_set()

    # Căn giữa theo cửa sổ cha hoặc màn hình
    try:
        dlg.update_idletasks()
        pw, ph = parent.winfo_width(), parent.winfo_height()
        px, py = parent.winfo_rootx(), parent.winfo_rooty()
        dw, dh = dlg.winfo_width(), dlg.winfo_height()
        cx = max(0, px + (pw - dw) // 2)
        cy = max(0, py + (ph - dh) // 2)
        dlg.geometry(f"+{cx}+{cy}")
    except Exception:
        pass

    dlg.grab_set()
    parent.wait_window(dlg)
    return confirmed[0]

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
    header=ttk.Frame(frm);header.pack(fill='x',pady=(12,4))
    ttk.Label(header,text='Nội dung cập nhật bản dịch cho người chơi').pack(side='left')
    details_button=ttk.Button(header,text='Xem chi tiết / tìm nội dung',command=lambda:show_player_details(win,state['details'],tk,ttk));details_button.pack(side='right');details_button.configure(state='disabled')
    auto_frame=ttk.Frame(frm);auto_frame.pack(fill='x')
    automatic=tk.Text(auto_frame,height=8,wrap='word',font=('Segoe UI',10));automatic.pack(side='left',fill='x',expand=True)
    auto_scroll=ttk.Scrollbar(auto_frame,orient='vertical',command=automatic.yview);auto_scroll.pack(side='right',fill='y');automatic.configure(yscrollcommand=auto_scroll.set)
    automatic.insert('1.0','Bấm Kiểm tra cập nhật để xem phần đã thêm tiếng Việt, phần sửa bản dịch và vị trí cần kiểm tra.');automatic.configure(state='disabled')
    ttk.Label(frm,text='Ghi chú thêm vào thông báo trên APK (có thể để trống)').pack(anchor='w',pady=(8,4))
    body=tk.Text(frm,height=3,wrap='word',font=('Segoe UI',10));body.pack(fill='x')
    summary=tk.StringVar(value='1. Kiểm tra GitHub. 2. Dựng và kiểm tra gói. 3. Xem kết quả rồi Phát hành.')
    ttk.Label(frm,textvariable=summary,wraplength=780).pack(anchor='w',pady=10)
    row=ttk.Frame(frm);row.pack(fill='x');q=queue.Queue();state={'busy':False,'preview':None,'fields':None,'channel':None,'suggestion':'','details':None}
    logbox=tk.Text(frm,height=6,wrap='word',state='disabled');logbox.pack(fill='both',expand=True,pady=(12,0))
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
            if not confirm_publish_dialog(win, rec, tk, ttk):return
        state['busy']=True;app.busy=True
        for b in buttons+app.buttons+[details_button]:b.configure(state='disabled')
        for e in entries:e.configure(state='disabled')
        browse.configure(state='disabled');body.configure(state='disabled')
        def worker():
            try:
                if kind=='check':
                    channel=check_updates();details=notice_preview_data(app.home,channel);result={'channel':channel,'notice':details['text'],'details':details}
                elif kind=='prepare':
                    record=prepare(Installer(app.home,game_snapshot,log),snapshot[0],snapshot[1],snapshot[2],snapshot[3],log)
                    result={'record':record,'details':load_player_details(record)}
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
                    state['preview']=None;state['fields']=None
                    channel=value['channel'];state['channel']=channel;state['details']=value['details']
                    # Checking GitHub must preserve a version the maintainer typed.
                    if not version.get().strip() or version.get()==state['suggestion']:version.set(suggested_version(channel))
                    state['suggestion']=suggested_version(channel);set_automatic(value['notice'])
                    summary.set(f"GitHub: bản dịch {channel['patch_version']} · APK {channel['app_version']}. Gợi ý phiên bản chưa dùng: {state['suggestion']}.")
                    log(channel.get('changelog',''))
                elif kind=='prepare':
                    state['details']=value['details'];value=value['record']
                    version.set(value['version']);title.set(value['notice']['title']);set_automatic(value['automatic_notice'])
                    state['preview']=value;state['fields']=values();ev=value['evidence']
                    summary.set(f"Sẵn sàng: ứng dụng + bản dịch v{value['version']} · {value['unpublished_count']:,} mục thay đổi chưa phát hành.\nAPK: {value['app']['app_size']:,} byte · Gói dịch: {ev['bundle_bytes']:,} byte")
                elif kind=='publish':state['details']=None;summary.set('Đã phát hành và xác thực: '+value['url']);state['preview']=None;token.set('');set_automatic('Đã ghi nhận gói phát hành. Bấm Kiểm tra cập nhật để tổng hợp các thay đổi tiếp theo.')
                else:summary.set('Chưa hoàn tất: '+value);log(value)
                details_button.configure(state='normal' if state['details'] and state['details']['changes'] else 'disabled')
                buttons[2].configure(state='normal' if state['preview'] else 'disabled');buttons[3].configure(state='normal' if state['channel'] else 'disabled')
        except queue.Empty:pass
        win.after(100,poll)
    def close():
        if state['busy']:app.messagebox.showinfo('Đang xử lý','Chờ dựng/tải lên hoàn tất trước khi đóng.',parent=win);return
        token.set('');win.destroy()
    win.protocol('WM_DELETE_WINDOW',close);win.after(100,poll);win.after(200,lambda:work('check'))
    return win

def show_player_details(parent, details, tk, ttk):
    """Search the same frozen rows used to compose the release notification."""
    if not details:
        return
    window=tk.Toplevel(parent);window.title('Chi tiết nội dung cập nhật bản dịch');window.geometry('1120x780');window.minsize(850,600)
    frm=ttk.Frame(window,padding=12);frm.pack(fill='both',expand=True)
    ttk.Label(frm,text='Tìm bản đồ, chế độ, nhân vật, thẻ/kỹ năng hoặc một câu cần kiểm tra.',wraplength=1000).pack(anchor='w')
    query=tk.StringVar();search=ttk.Entry(frm,textvariable=query);search.pack(fill='x',pady=8)
    status=tk.StringVar();ttk.Label(frm,textvariable=status).pack(anchor='w')
    tree_frame=ttk.Frame(frm);tree_frame.pack(fill='both',expand=True,pady=8)
    columns=('section','entity','content','change','after')
    tree=ttk.Treeview(tree_frame,columns=columns,show='headings',selectmode='browse')
    for col,title,width in [('section','Khu vực / chế độ',150),('entity','Bản đồ / nhân vật / thẻ-kỹ năng',290),('content','Nội dung',160),('change','Loại thay đổi',130),('after','Bản dịch sau (trích)',330)]:
        tree.heading(col,text=title);tree.column(col,width=width,minwidth=90)
    tree.pack(side='left',fill='both',expand=True)
    scroll=ttk.Scrollbar(tree_frame,orient='vertical',command=tree.yview);scroll.pack(side='right',fill='y');tree.configure(yscrollcommand=scroll.set)
    explanation=tk.Text(frm,height=8,wrap='word',font=('Segoe UI',10),state='disabled');explanation.pack(fill='x')
    labels={'new':'Thêm tiếng Việt','edited':'Sửa bản dịch','removed':'Ngừng áp dụng'}
    rows=details['changes'];visible={}
    def filtered():
        needle=query.get().strip().casefold();tree.delete(*tree.get_children());visible.clear()
        for n,row in enumerate(rows):
            context=row['player_context'];cards=', '.join(context.get('mentioned_cards',[]))
            haystack=' '.join([context['section'],context['entity'],row['content_type'],cards,row['before_display'],row['after_display']]).casefold()
            if needle and needle not in haystack:continue
            key=str(n);visible[key]=row;tree.insert('', 'end',iid=key,values=(context['section'],context['entity'],row['content_type'],labels[row['kind']],row['after_display'][:100]))
        status.set(f'Hiện {len(visible):,}/{len(rows):,} dòng thay đổi. Chọn một dòng để xem trước và sau.')
    def selected(event=None):
        selection=tree.selection()
        if not selection:return
        row=visible[selection[0]];context=row['player_context']
        text=context['section']+' · '+context['entity']+'\n'+labels[row['kind']]+': '+row['content_type']+'\n'
        if context.get('mentioned_cards'):text+='Thẻ được nhắc tới: '+', '.join(context['mentioned_cards'])+'\n'
        if context['status']=='classification_pending':text+='Tên này chưa có phân loại kỹ năng/hiệu ứng đã duyệt.\n'
        if context['status'] in {'unresolved','ambiguous'}:text+='Chưa có đủ liên kết nguồn để xác định bản đồ hoặc nhân vật cụ thể.\n'
        text+='\nTrước:\n'+(row['before_display'] or '(Chưa có bản dịch trong bản nền)')+'\n\nSau:\n'+row['after_display']
        explanation.configure(state='normal');explanation.delete('1.0','end');explanation.insert('1.0',text);explanation.configure(state='disabled')
    tree.bind('<<TreeviewSelect>>',selected);query.trace_add('write',lambda *args:filtered());filtered();search.focus_set()
