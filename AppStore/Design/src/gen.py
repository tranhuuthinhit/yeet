import json, sys
LANG = sys.argv[1]
def t(en, vi): return vi if LANG == 'vi' else en

H = {  # top, mid, bottom, tileLight, tileDark, ink
 'violet': ('#2A1140','#56206A','#8A2C7E','#EC6AD2','#9B3BC4','#5A1E6E'),
 'green':  ('#0B2E2A','#135447','#1D7A5C','#45D6A0','#17936A','#0F4A3A'),
 'orange': ('#3A160C','#7A3014','#B5501C','#FFA552','#E0611D','#7A2E10'),
 'blue':   ('#0D1D47','#1A3A85','#2A5EC0','#62A2FF','#2D5FD8','#17357A'),
 'rose':   ('#36101F','#6A1C3A','#98294F','#FF8496','#D63A5C','#6A1C3A'),
 'indigo': ('#1B1246','#352285','#5536B8','#A48CFF','#6646E0','#2E1E78'),
}
I = {
 'grid':'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z','code':'M8 6l-6 6 6 6M16 6l6 6-6 6',
 'trash':'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13','file':'M14 3H6v18h12V7zM14 3v4h4','copy':'M8 8h12v12H8zM4 16V4h12',
 'globe':'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18','app':'M4 4h16v16H4zM4 9h16',
 'power':'M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0','trend':'M3 17l6-6 4 4 8-8M15 7h6v6','pulse':'M3 12h4l3-8 4 16 3-8h4',
 'hammer':'M14 6l4 4-9 9-4-4zM14 6l2-2 4 4-2 2','box':'M4 8l8-4 8 4v8l-8 4-8-4zM4 8l8 4 8-4M12 12v8','folder':'M3 6h6l2 2h10v11H3z',
 'stack':'M4 4h16v6H4zM4 14h16v6H4z','dl':'M12 4v11M7 10l5 5 5-5M5 20h14','video':'M4 6h12v12H4zM16 10l5-3v10l-5-3',
 'disc':'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M12 10a2 2 0 1 0 0 4a2 2 0 1 0 0-4','doc':'M14 3H6v18h12V7zM14 3v4h4M9 13h6M9 17h6',
 'lock':'M6 11V8a6 6 0 0 1 12 0v3M5 11h14v10H5z','check':'M5 12l4 4 10-10','warn':'M12 3l10 18H2zM12 10v5M12 18v.5',
 'chev':'M6 9l6 6 6-6','shield':'M12 3l8 3v6c0 5-3.5 8-8 9c-4.5-1-8-4-8-9V6zM8.5 12l2.5 2.5 4.5-5','refresh':'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7',
 'battery':'M3 8h15v8H3zM21 11v2','temp':'M10 14V5a2 2 0 0 1 4 0v9a4 4 0 1 1-4 0z',
}
def svg(name, size=14, stroke='#fff', w=2):
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{stroke}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"><path d="{I[name]}"/></svg>'
def tile(name, c1, c2, size=26, r=7, g=13):
    return f'<span class="tile" style="width:{size}px;height:{size}px;border-radius:{r}px;background:linear-gradient(135deg,{c1},{c2})">{svg(name,g)}</span>'
def badge(kind):
    m={'safe':(t('Safe','An toàn'),'rgba(69,214,160,.22)','#9CF2CC'),'re':(t('Re-download','Tải lại'),'rgba(247,192,79,.2)','#FFDC8F'),'ca':(t('Caution','Thận trọng'),'rgba(255,99,99,.22)','#FFB8B8')}[kind]
    return f'<span class="badge" style="background:{m[1]};color:{m[2]}">{m[0]}</span>'
def cb(on): return f'<span class="cb {"on" if on else ""}">{svg("check",11,"#1A1030",3) if on else ""}</span>'

SIDE = [
 (t('OVERVIEW','TỔNG QUAN'), [('overview',t('Overview','Tổng quan'),'grid','#EC6AD2','#9B3BC4','58.4 GB')]),
 (t('CLEAN UP','DỌN DẸP'), [('dev',t('Developer Caches','Cache lập trình'),'code','#45D6A0','#17936A','35.9 GB'),
   ('junk',t('System Junk','Rác hệ thống'),'trash','#F7C04F','#D9861C','4.12 GB'),('large',t('Large & Old Files','File lớn & cũ'),'file','#FFA552','#E0611D','2.10 GB'),
   ('dupes',t('Duplicates','File trùng'),'copy','#A48CFF','#6646E0','108 MB'),('web',t('Browsers','Trình duyệt'),'globe','#62CCF7','#2585D1','3.30 GB')]),
 (t('APPS','ỨNG DỤNG'), [('apps',t('Uninstaller','Gỡ ứng dụng'),'app','#62A2FF','#2D5FD8','48'),('startup',t('Startup Items','Mục khởi động'),'power','#4FD6C8','#16918A','3')]),
 (t('MONITOR','THEO DÕI'), [('growth',t('Disk Growth','Tăng trưởng ổ đĩa'),'trend','#FF8496','#D63A5C','+2.40 GB'),('health',t('System Health','Sức khoẻ máy'),'pulse','#FF6FA0','#C92A62',t('Good','Tốt'))]),
]
def num(s):  # vi decimal comma
    return s.replace('.',',') if LANG=='vi' else s
def sidebar(active):
    out=['<div class="side"><div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>',
         '<div class="brand"><img src="icon.png"><b>Yeet</b><span class="v">v2</span></div>']
    for title, items in SIDE:
        out.append(f'<div class="sec">{title}</div>')
        for id_,label,ic,c1,c2,fig in items:
            out.append(f'<div class="srow {"act" if id_==active else ""}">{tile(ic,c1,c2,24,7,12)}<span class="sl">{label}</span><span class="sf">{num(fig)}</span></div>')
    out.append(f'<div class="disk"><div class="dn">{svg("stack",12)} {t("Startup Disk","Ổ khởi động")}</div><div class="bar"><i style="width:80%"></i></div><div class="df">{num(t("95.6 GB free of 494 GB","95.6 GB trống / 494 GB"))}</div></div></div>')
    return ''.join(out)
def header(title, sub, right=''):
    return f'<div class="hdr"><div><div class="ht">{title}</div><div class="hs">{sub}</div></div><div class="hr">{right}</div></div>'
def seg(opts, on, ink):
    return '<div class="seg">'+''.join(f'<span class="{"on" if i==on else ""}" style="{"color:"+ink if i==on else ""}">{o}</span>' for i,o in enumerate(opts))+'</div>'
def btn(label, icon=None): return f'<span class="btn">{svg(icon,13) if icon else ""}{label}</span>'
def primary(label, ink): return f'<span class="pbtn" style="color:{ink}">{label}</span>'
def bar(summary, detail, right):
    return f'<div class="abar"><div><div class="at">{summary}</div><div class="ad">{detail}</div></div><div class="ar">{right}</div></div>'

def screen_overview(h):
    ink=h[5]
    segs=[(t('Documents & media','Tài liệu & media'),'141 GB',28.5,'#7EA8FF'),(t('Apps','Ứng dụng'),'92 GB',18.6,'#B48CFF'),(t('Developer Caches','Cache lập trình'),'35.9 GB',7.3,'#45D6A0'),
          (t('Large files','File lớn'),'2.10 GB',1.6,'#FFA552'),(t('System Junk','Rác hệ thống'),'4.12 GB',1.2,'#F7C04F'),(t('Everything else','Phần còn lại'),'123 GB',23.5,'#C9CFDB'),(t('Free','Trống'),'95.6 GB',19.3,'rgba(255,255,255,.16)')]
    barh=''.join(f'<i style="width:{p}%;background:{c}"></i>' for _,_,p,c in segs)
    leg=''.join(f'<div class="lg"><i style="background:{c}"></i><span>{n}</span><b>{num(s)}</b></div>' for n,s,_,c in segs)
    recs=[(t('Device Support · 3 old versions','Device Support · 3 bản cũ'),'~/Library/Developer/…/DeviceSupport','safe','9.99 GB','#45D6A0','#17936A','hammer',0),
          (t('Derived Data · 4 idle projects','Derived Data · 4 dự án cũ'),'~/Library/Developer/Xcode/DerivedData'.replace('Xcode/','…/'),'safe','6.80 GB','#45D6A0','#17936A','hammer',1),
          ('node_modules · '+t('6 old projects','6 dự án cũ'),'~/Projects/**/node_modules','re','4.20 GB','#45D6A0','#17936A','folder',0),
          ('npm cache','~/.npm/_cacache','safe','3.50 GB','#E03131','#B02020','box',1),
          (t('App caches (Slack, Discord, Chrome)','Cache ứng dụng (Slack, Discord, Chrome)'),'~/Library/Caches','safe','2.90 GB','#F7C04F','#D9861C','stack',1),
          (t('Installers in Downloads','Bộ cài trong Downloads'),'~/Downloads','ca','1.60 GB','#FFA552','#E0611D','dl',0)]
    rows=''.join(f'<div class="row">{cb(on)}{tile(ic,c1,c2,28,8,13)}<div class="nm"><div>{n}</div><div class="mono">{p}</div></div>{badge(r)}<b class="sz">{num(s)}</b></div>' for n,p,r,s,c1,c2,ic,on in recs)
    days=[.3,.1,.6,.2,.9,.1,.2]
    bars=''.join(f'<i style="height:{6+v*40}px;background:{"linear-gradient(#FFC2A0,#FF7A59)" if v>=.6 else "rgba(255,194,160,.4)"}"></i>' for v in days)
    body=f'''
    <div class="card pad"><div class="flex"><div><div class="muted">{t("Startup Disk","Ổ khởi động")}</div><div class="big">{num("95.6 GB")} <small>{num(t("free of 494 GB","trống trên 494 GB"))}</small></div></div>
      <div class="rt"><div class="muted">{t("Safe to free up","Có thể giải phóng an toàn")}</div><div class="green">{num("14.6 GB")}</div></div></div>
      <div class="segbar">{barh}</div><div class="legend">{leg}</div></div>
    <div class="cols"><div class="card grow"><div class="ch"><b>{t("Worth Cleaning","Nên dọn")}</b><span class="muted">{t("Largest first, from every module","Lớn nhất trước, từ mọi mục")}</span></div>{rows}</div>
      <div class="colr"><div class="card pad"><b>{t("Last 7 days","7 ngày qua")}</b><div class="peach">+{num("2.40 GB")}</div><div class="days">{bars}</div>
        <div class="muted sm">{t("Grew most:","Tăng nhiều nhất:")} <span class="mono w">~/Library/Developer/CoreSimulator</span> <b class="peach2">+{num("1.80 GB")}</b></div></div>
        <div class="card pad"><b>{t("System Health","Sức khoẻ máy")}</b>
          <div class="kv"><span>{t("Battery","Pin")}</span><b>{t("90% capacity","Dung lượng 90%")}</b></div><div class="kv"><span>{t("Temperature","Nhiệt độ")}</span><b>{t("Normal","Bình thường")}</b></div><div class="kv"><span>{t("Free space","Dung lượng trống")}</span><b>{num("95.6 GB")}</b></div></div></div></div>'''
    return (sidebar('overview') + '<div class="main">' + header(t('Overview','Tổng quan'), t('Everything Yeet can clean, in one place','Mọi thứ Yeet dọn được, ở cùng một chỗ'), btn(t('Scan Everything','Quét tất cả'),'refresh'))
            + f'<div class="content">{body}</div>' + bar(t('Selected 3 items · 13.2 GB','Đã chọn 3 mục · 13.2 GB').replace('13.2',num('13.2')), t('“Caution” items are never pre-selected','Mục “Thận trọng” không bao giờ được chọn sẵn'),
              btn(t('Select Safe Items','Chọn mục an toàn'),'shield')+primary(t('Review & Clean…','Xem lại & dọn…'),ink)) + '</div>')

def screen_dev(h, dim=False):
    ink=h[5]
    chips=[(t('All','Tất cả'),'35.9 GB','#fff',0),(t('App Builds','Build ứng dụng'),'17.3 GB','#62A2FF',1),('Gradle','8.00 GB','#45D6A0',0),('Yarn','4.53 GB','#7EC8FF',0),('node_modules','4.20 GB','#9BE07A',0),('npm','3.51 GB','#FF7A7A',0),('Claude Code','820 MB','#F7C04F',0)]
    ch=''.join(f'<span class="chip {"on" if on else ""}" style="{"color:"+ink if on else ""}"><i style="background:{h[4] if on else c}"></i>{n} <span>{num(s)}</span></span>' for n,s,c,on in chips)
    tree=[(0,t('App Builds','Build ứng dụng'),'~/Library/Developer','', '17.31 GB','g'),(1,'Derived Data','~/Library/Developer/…/DerivedData','','3.49 GB','f'),
          (2,'Alpha-gxkqmzbfhvlc','…/DerivedData/Alpha-gxkqmzbfhvlc','re','2.14 GB','sel'),(2,'Beta-hdfeqpwnlkzr','…/DerivedData/Beta-hdfeqpwnlkzr','safe','1.02 GB','c'),
          (2,'Gamma-bqtyzxowmfae','…/DerivedData/Gamma-bqtyzxowmfae','safe','330 MB','c'),(1,'Device Support','~/Library/Developer/…/DeviceSupport','','9.99 GB','f'),
          (2,'17.5.1 (21F90)','…/DeviceSupport/17.5.1 (21F90)','safe','3.40 GB','c'),(2,'18.0 (22A3354)','…/DeviceSupport/18.0 (22A3354)','re','3.46 GB',''),
          (2,'10.4 (21T216)','…/DeviceSupport/10.4 (21T216)','safe','3.13 GB','c'),(1,t('Simulator caches','Cache Simulator'),'~/Library/Developer/CoreSimulator/Caches','safe','2.41 GB',''),
          (1,'Documentation Cache','~/Library/Developer/…/DocumentationCache','safe','180 MB','')]
    rows=''
    for d,n,p,r,s,k in tree:
        grp = k in ('g','f')
        ic = tile('hammer','#62A2FF','#2D5FD8',24,6,12) if k=='g' else f'<span class="ftile">{svg("folder",13,"#9CC4FF")}</span>'
        car = svg('chev',11,'rgba(255,255,255,.7)',3) if grp else ''
        rows+=f'<div class="trow {"sel" if k=="sel" else ""}"><div class="tn" style="padding-left:{d*22}px"><span class="car">{car}</span>{cb(k in ("sel","c"))}{ic}<div class="nm"><div class="{"b" if grp else ""}">{n}</div><div class="mono">{p}</div></div></div><div class="tr">{badge(r) if r else ""}</div><b class="sz {"b" if grp else ""}">{num(s)}</b></div>'
    insp=f'''<div class="card insp"><div class="flex0">{tile("hammer","#45D6A0","#17936A",44,12,22)}<div><div class="over">{t("APP BUILDS · DERIVED DATA","BUILD ỨNG DỤNG · DERIVED DATA")}</div><div class="it">Alpha-gxkqmzbfhvlc</div></div></div>
      <div class="big">{num("2.14 GB")}</div><div class="code light">~/Library/Developer/…/DerivedData/Alpha-gxkqmzbfhvlc</div>
      <div class="two">{btn(t("Copy","Sao chép"))}{btn(t("Show in Finder","Mở Finder"))}</div>
      <div class="facts"><div><span>{t("Files","Số tệp")}</span><b>48,210</b></div><div><span>{t("Last modified","Sửa lần cuối")}</span><b>{t("2 hours ago","2 giờ trước")}</b></div></div>
      <div class="over">{t("IMPACT OF DELETING","ẢNH HƯỞNG KHI XOÁ")}</div>{badge("re")}<p>{t("The next build of Alpha is slower because it is indexed and compiled from scratch. Your source code is not affected.","Lần build kế tiếp của Alpha sẽ chậm hơn vì phải index và biên dịch lại. Mã nguồn không bị ảnh hưởng.")}</p>
      <div class="over">{t("HOW IT’S CLEANED","CÁCH DỌN")}</div><div class="code">rm -rf ~/Library/Developer/…/DerivedData/Alpha-*</div></div>'''
    main=('<div class="main">'+header(t('Developer Caches','Cache lập trình'),t('17 tools · 35.9 GB · 14.6 GB safe to delete','17 công cụ · 35.9 GB · 14.6 GB an toàn để xoá').replace('35.9',num('35.9')).replace('14.6',num('14.6')),
          seg([t('All','Tất cả'),t('Safe','An toàn'),t('Re-download','Tải lại'),t('Caution','Thận trọng')],0,ink)+btn(t('Rescan','Quét lại'),'refresh'))
          +f'<div class="chips">{ch}</div><div class="content row2"><div class="card grow"><div class="thead"><span>{t("ITEM","MỤC")}</span><span>{t("IMPACT","MỨC ĐỘ")}</span><span>{t("SIZE","DUNG LƯỢNG")}</span></div>{rows}</div>{insp}</div>'
          +bar(t('Selected 5 items · 10.0 GB','Đã chọn 5 mục · 10.0 GB').replace('10.0',num('10.0')),t('Total: 35.9 GB · “Caution” items are never pre-selected','Tổng: 35.9 GB · Mục “Thận trọng” không bao giờ được chọn sẵn').replace('35.9',num('35.9')),
               btn(t('Select Safe Items','Chọn mục an toàn'),'shield')+primary(t('Review & Clean…','Xem lại & dọn…'),ink))+'</div>')
    return sidebar('dev')+main

def screen_review(h):
    ink=h[5]
    base=screen_dev(h)
    groups=[(1,'#FFA552',t('Delete permanently','Xoá vĩnh viễn'),t('Caches that are recreated automatically','Cache tự tạo lại được'),
             [('Derived Data · Alpha','~/Library/Developer/…/DerivedData/Alpha-gxkqmzbfhvlc','2.14 GB'),('Derived Data · Beta','~/Library/Developer/…/DerivedData/Beta-hdfeqpwnlkzr','1.02 GB'),('npm · _cacache','~/.npm/_cacache','3.50 GB')]),
            (2,'#45D6A0',t('Move to Trash','Chuyển vào Thùng rác'),t('You can put these back from the Trash','Khôi phục được từ Thùng rác'),
             [('Device Support · 17.5.1','~/Library/Developer/…/DeviceSupport/17.5.1 (21F90)','3.40 GB')])]
    g=''
    for n,c,title,hint,items in groups:
        its=''.join(f'<div class="ri"><div><div>{a}</div><div class="mono">{p}</div></div><b>{num(s)}</b></div>' for a,p,s in items)
        g+=f'<div class="rg"><div class="rgh"><span class="num" style="background:{c}">{n}</span><b>{title}</b><span class="muted sm">{hint}</span></div><div class="card r12">{its}</div></div>'
    sheet=f'''<div class="dim"><div class="sheet"><div class="sh"><span class="tile" style="width:44px;height:44px;border-radius:12px;background:linear-gradient(135deg,{h[3]},{h[4]})">{svg("check",20)}</span>
      <div><div class="it">{t("Review Before Cleaning","Xem lại trước khi dọn")}</div><div class="muted sm">{t("4 items · 10.1 GB. Nothing is removed until you confirm.","4 mục · 10.1 GB. Không xoá gì cho đến khi bạn xác nhận.").replace("10.1",num("10.1"))}</div></div></div>
      <div class="tot"><div><span>{t("Delete permanently","Xoá vĩnh viễn")}</span><b>{num("6.66 GB")}</b></div><div><span>{t("Move to Trash","Chuyển vào Thùng rác")}</span><b>{num("3.40 GB")}</b></div></div>
      <div class="sbody"><div class="warnb">{svg("warn",14,"#FFD98A")} <span>{t("Running: Slack. Quit it (⌘Q) first, or its cache will be skipped.","Đang chạy: Slack. Thoát hẳn (⌘Q) trước, nếu không cache của nó sẽ bị bỏ qua.")}</span></div>{g}</div>
      <div class="sf2">{btn(t("Cancel","Huỷ"))}{primary(t("Clean","Dọn")+" "+num("10.1 GB"),ink)}</div></div></div>'''
    return base+sheet

def screen_large(h):
    ink=h[5]
    kinds=[(t('Video','Video'),'472 MB',1),(t('Installers & disk images','Bộ cài & ảnh đĩa'),'629 MB',1),(t('Models & data','Mô hình & dữ liệu'),'629 MB',1),(t('Archives','Lưu trữ nén'),'199 MB',1),(t('Documents','Tài liệu'),'126 MB',1)]
    kl=''.join(f'<div class="kr">{cb(o)}<span>{n}</span><b>{num(s)}</b></div>' for n,s,o in kinds)
    files=[('llama-3b.safetensors','~/models',t('Model','Mô hình'),t('Today','Hôm nay'),0,'629 MB','#FFA552','#E0611D','box',0),
           ('trip-2023.mov','~/Movies','Video',t('3 years ago','3 năm trước'),1,'472 MB','#FF7A9A','#D6335E','video',1),
           ('installer-15.xip','~/Downloads',t('Installer','Bộ cài'),t('Today','Hôm nay'),0,'336 MB','#A48CFF','#6646E0','disc',0),
           ('ubuntu-24.04.iso','~/Downloads',t('Disk image','Ảnh đĩa'),t('2 years ago','2 năm trước'),1,'294 MB','#A48CFF','#6646E0','disc',1),
           ('dataset.zip','~/Downloads',t('Archive','Lưu trữ'),t('Today','Hôm nay'),0,'199 MB','#F7C04F','#D9861C','stack',0),
           ('scanned-archive.pdf','~/Documents',t('Document','Tài liệu'),t('13 months ago','13 tháng trước'),1,'126 MB','#62A2FF','#2D5FD8','doc',0)]
    rows=''.join(f'<div class="frow">{cb(on)}{tile(ic,c1,c2,28,8,13)}<div class="nm"><div>{n}</div><div class="mono">{p}</div></div><span class="muted">{k}</span><span class="{"old" if old else "muted"}">{a}</span><b class="sz">{num(s)}</b></div>' for n,p,k,a,old,s,c1,c2,ic,on in files)
    body=f'''<div class="content row2"><div class="card filt"><div class="over">{t("FILE KINDS","LOẠI FILE")}</div>{kl}<div class="over mt">{t("NOT OPENED SINCE","KHÔNG MỞ TỪ")}</div>
      <div class="kr"><span class="rad"></span>{t("Any time","Mọi lúc")}</div><div class="kr"><span class="rad on"></span>{t("Over 6 months","Hơn 6 tháng")}</div><div class="kr"><span class="rad"></span>{t("Over a year","Hơn 1 năm")}</div>
      <div class="over mt">{t("LARGER THAN","LỚN HƠN")}</div><div class="dd">100 MB</div></div>
      <div class="card grow"><div class="ch"><span class="big">{num("2.10 GB")}</span><span class="muted">{t("in 6 files larger than 100 MB","trong 6 file lớn hơn 100 MB")}</span></div>
      <div class="fhead"><span></span><span>{t("NAME","TÊN")}</span><span>{t("KIND","LOẠI")}</span><span>{t("LAST OPENED","MỞ LẦN CUỐI")}</span><span>{t("SIZE ↓","DUNG LƯỢNG ↓")}</span></div>{rows}
      <div class="hint">{t("Press Space for Quick Look. Selected files go to the Trash.","Bấm Space để xem nhanh. File đã chọn được chuyển vào Thùng rác.")}</div></div></div>'''
    return sidebar('large')+'<div class="main">'+header(t('Large & Old Files','File lớn & cũ'),t('In your Home folder · app data and hidden folders are skipped','Trong thư mục Home · bỏ qua dữ liệu app và thư mục ẩn'),btn(t('Rescan','Quét lại'),'refresh'))+body+bar(t('Selected 2 files · 766 MB','Đã chọn 2 file · 766 MB'),t('Nothing is deleted permanently','Không xoá vĩnh viễn file nào'),btn(t('Deselect','Bỏ chọn'))+primary(t('Move to Trash','Chuyển vào Thùng rác'),ink))+'</div>'

def screen_apps(h):
    ink=h[5]
    apps=[('Photon Editor','P',t('Store','Cửa hàng'),'5.0','Universal',t('Never','Chưa từng mở'),1,'157 MB','246 MB','#FF7A59','#D6335E',1,1),
          ('Ghostly','G',t('Direct download','Tải trực tiếp'),'2.4.1','Arm',t('Yesterday','Hôm qua'),0,'12 MB','94 MB','#A48CFF','#6646E0',0,0),
          ('Zipper','Z',t('Store','Cửa hàng'),'3.2','Universal',t('3 weeks ago','3 tuần trước'),0,'4 MB','35 MB','#45D6A0','#17936A',0,0),
          ('OldTool','O',t('Direct download','Tải trực tiếp'),'1.0.3','Intel',t('2 years ago','2 năm trước'),1,'3 MB','15 MB','#C9CFDB','#7A8699',1,0),
          ('Mapster','M',t('Store','Cửa hàng'),'8.1','Arm',t('6 months ago','6 tháng trước'),1,'0 KB','12 MB','#62CCF7','#2585D1',0,0)]
    archc={'Universal':('rgba(255,255,255,.14)','#fff'),'Arm':('rgba(69,214,160,.22)','#9CF2CC'),'Intel':('rgba(247,192,79,.22)','#FFDC8F')}
    rows=''
    for n,ini,src,ver,arch,age,old,data,tot,c1,c2,on,op in apps:
        a=archc[arch]
        rows+=f'<div class="arow {"open" if op else ""}"><div class="ag">{cb(on)}<span class="aicon" style="background:linear-gradient(135deg,{c1},{c2})">{ini}</span><div class="nm"><div class="b">{n}</div><div class="muted sm">{src}</div></div><span class="muted">{ver}</span><span class="badge" style="background:{a[0]};color:{a[1]}">{arch}</span><span class="{"old" if old else "muted"}">{age}</span><span class="muted r">{num(data)}</span><b class="sz">{num(tot)}</b></div>'
        if op:
            lo=[(t('Cache','Cache'),'~/Library/Caches/io.photon.editor','126 MB',1,0),(t('Logs','Nhật ký'),'~/Library/Logs/Photon Editor','12 MB',1,0),(t('Preferences','Tuỳ chọn'),'~/Library/Preferences/io.photon.editor.plist','24 KB',1,0),(t('Your data','Dữ liệu của bạn'),'~/Library/Application Support/Photon Editor','19 MB',0,1)]
            rows+='<div class="leftovers"><div class="muted sm lk">'+svg('lock',12,'rgba(255,255,255,.75)')+' '+t('Items marked “Your data” are kept unless you tick them.','Mục “Dữ liệu của bạn” được giữ lại trừ khi bạn tự chọn.')+'</div>'
            rows+=''.join(f'<div class="lo">{cb(o)}<span class="badge" style="{"background:rgba(255,99,99,.22);color:#FFB8B8" if mine else "background:rgba(255,255,255,.12);color:#fff"}">{k}</span><span class="mono w">{p}</span><b>{num(s)}</b></div>' for k,p,s,o,mine in lo)+'</div>'
        rows+='</div>'
    body=f'''<div class="content"><div class="card"><div class="ahead"><span></span><span>{t("APP","ỨNG DỤNG")}</span><span>{t("VERSION","PHIÊN BẢN")}</span><span>{t("ARCHITECTURE","KIẾN TRÚC")}</span><span>{t("LAST OPENED","MỞ LẦN CUỐI")}</span><span class="r">{t("DATA","DỮ LIỆU")}</span><span class="r">{t("TOTAL ↓","TỔNG ↓")}</span></div>{rows}</div></div>'''
    return sidebar('apps')+'<div class="main">'+header(t('Uninstaller','Gỡ ứng dụng'),t('48 apps · 21.7 GB including their data','48 ứng dụng · 21.7 GB gồm dữ liệu đi kèm').replace('21.7',num('21.7')),seg([t('Name','Tên'),t('Size','Dung lượng'),t('Last opened','Mở gần nhất')],1,ink)+'<span class="search">'+t('Search apps','Tìm ứng dụng')+'</span>')+body+bar(t('2 apps selected · 261 MB','Đã chọn 2 ứng dụng · 261 MB'),t('Apps and their leftovers go to the Trash','Ứng dụng và dữ liệu thừa được chuyển vào Thùng rác'),primary(t('Uninstall…','Gỡ cài đặt…'),ink))+'</div>'

def screen_growth(h):
    ink=h[5]
    vals=[389.2,389.4,389.1,389.9,390.3,390.1,390.8,391.0,390.6,391.4,391.9,391.7,392.4,392.8,393.0,393.3,393.1,394.0,394.4,394.2,395.0,396.0,395.8,396.1,396.4,396.6,397.5,397.7,398.0,398.4]
    pts=' '.join(f'{10+i*580/29:.0f},{140-(v-385)/15*120:.0f}' for i,v in enumerate(vals))
    area='M10,150 L'+' L'.join(f'{10+i*580/29:.0f},{140-(v-385)/15*120:.0f}' for i,v in enumerate(vals))+' L590,150 Z'
    diffs=[('~/Library/Developer/CoreSimulator',1.8,'+1.80 GB'),('~/Library/Caches/com.tinyspeck.slackmacgap',.6,'+610 MB'),('~/Downloads',.45,'+452 MB'),('~/.gradle/caches',.3,'+298 MB'),('~/.npm/_cacache',-.9,'−905 MB')]
    dr=''.join(f'<div class="drow"><span class="mono w">{p}</span><div class="dbar"><i style="width:{abs(g)/1.8*100:.0f}%;background:{"linear-gradient(90deg,#FFC2D0,#FF7A9A)" if g>0 else "#7FE0B5"}"></i></div><b style="color:{"#FFC2D0" if g>0 else "#9CF2CC"}">{num(s)}</b></div>' for p,g,s in diffs)
    hl=[('battery',t('Battery','Pin'),'90%',t('291 of 1,000 cycles','291 / 1.000 lần sạc'),'#45D6A0','#17936A',t('Normal','Bình thường')),('stack',t('Storage','Ổ đĩa'),'95.6 GB',t('free of 494 GB','trống trên 494 GB'),'#62A2FF','#2D5FD8',t('OK','Tốt')),('temp',t('Thermal','Nhiệt độ máy'),t('Nominal','Bình thường'),t('Reported by the system','Do hệ thống báo'),'#FFA552','#E0611D',t('Cool','Mát'))]
    hc=''.join(f'<div class="card hc">{tile(ic,c1,c2,38,10,18)}<div class="grow"><div class="muted sm">{n}</div><div class="hv">{num(v)}</div><div class="muted sm">{s}</div></div>{badge("safe").replace(t("Safe","An toàn"),st)}</div>' for ic,n,v,s,c1,c2,st in hl)
    body=f'''<div class="content"><div class="row2"><div class="card grow pad"><div class="muted">{t("Used space · 30 days","Dung lượng đã dùng · 30 ngày")}</div><div class="big">+{num("2.40 GB")} <small>{t("vs 7 days ago","so với 7 ngày trước")}</small></div>
      <svg viewBox="0 0 600 170" style="width:100%;height:190px"><defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF9AB0" stop-opacity=".5"/><stop offset="1" stop-color="#FF9AB0" stop-opacity="0"/></linearGradient></defs>
      <line x1="0" y1="20" x2="600" y2="20" stroke="rgba(255,255,255,.1)"/><line x1="0" y1="80" x2="600" y2="80" stroke="rgba(255,255,255,.1)"/><line x1="0" y1="140" x2="600" y2="140" stroke="rgba(255,255,255,.1)"/>
      <path d="{area}" fill="url(#f)"/><polyline points="{pts}" fill="none" stroke="#FFC2D0" stroke-width="2.5" stroke-linejoin="round"/><line x1="450" y1="10" x2="450" y2="150" stroke="#fff" stroke-dasharray="3 4" stroke-opacity=".7"/></svg></div>
      <div class="colr">{hc}</div></div>
      <div class="card"><div class="ch"><b>{t("Folders that changed most","Thư mục thay đổi nhiều nhất")}</b><span class="muted">{t("over the last 7 days","trong 7 ngày qua")}</span></div>{dr}</div></div>'''
    return sidebar('growth')+'<div class="main">'+header(t('Disk Growth','Tăng trưởng ổ đĩa'),t('Measured once a day, quietly from the menu bar','Đo mỗi ngày một lần, chạy nền trên thanh menu'),seg([t('Yesterday','Hôm qua'),t('7 days','7 ngày'),t('30 days','30 ngày')],1,ink))+body+'</div>'

SHOTS = [
 ('01-overview','01-tong-quan','violet',screen_overview,t('Your whole disk, cleaned with care','Dọn cả ổ đĩa, cẩn thận từng mục'),t('Caches, large files, duplicates, browsers and apps — in one place.','Cache, file lớn, file trùng, trình duyệt và ứng dụng — ở cùng một nơi.')),
 ('02-dev-caches','02-cache-lap-trinh','green',screen_dev,t('Every developer cache, explained','Mọi cache lập trình, giải thích rõ'),t('Path, size and what happens if you delete — for every folder.','Đường dẫn, dung lượng và ảnh hưởng khi xoá — cho từng thư mục.')),
 ('03-review','03-xem-lai','green',screen_review,t('Nothing goes without your review','Không xoá gì khi bạn chưa xem lại'),t('See what is deleted, what goes to the Trash, and what is still running.','Biết mục nào xoá hẳn, mục nào vào Thùng rác, app nào đang chạy.')),
 ('04-large-files','04-file-lon','orange',screen_large,t('Find large, forgotten files','Tìm file lớn bị bỏ quên'),t('Filter by kind and age. Everything goes to the Trash, never gone for good.','Lọc theo loại và tuổi. Mọi thứ vào Thùng rác, không mất vĩnh viễn.')),
 ('05-uninstaller','05-go-ung-dung','blue',screen_apps,t('Uninstall apps, leftovers too','Gỡ app sạch cả dữ liệu thừa'),t('Caches, logs and preferences go with the app. Your data stays unless you say so.','Cache, log, tuỳ chọn được gỡ cùng app. Dữ liệu của bạn được giữ lại.')),
 ('06-growth','06-tang-truong','rose',screen_growth,t('See what made your disk grow','Biết vì sao ổ đĩa đầy lên'),t('Daily snapshots show which folders grew — plus battery, storage and thermal health.','Ảnh chụp mỗi ngày chỉ ra thư mục nào tăng — kèm sức khoẻ pin, ổ đĩa, nhiệt độ.')),
]
css=open('style.css').read()
out=[]
for en,vi,hue,fn,head,sub in SHOTS:
    h=H[hue]
    name = vi if LANG=='vi' else en
    html=f'''<!doctype html><html lang="{LANG}"><head><meta charset="utf-8"><style>{css}
    :root{{--t:{h[0]};--m:{h[1]};--b:{h[2]};--l:{h[3]};--d:{h[4]}}}</style></head><body>
    <div class="stage"><div class="headline"><h1>{head}</h1><p>{sub}</p></div><div class="win">{fn(h)}</div></div></body></html>'''
    open(f'{LANG}-{name}.html','w').write(html); out.append(name)
print(json.dumps(out))
