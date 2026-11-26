import sys
L=sys.argv[1]
def t(en,vi): return vi if L=='vi' else en
name=t("Yeet – Disk & Cache Cleaner","Yeet – Dọn ổ đĩa & cache")
sub=t("Clear caches, big files & apps","Dọn cache, file lớn, app thừa")
shots=["01-overview","02-dev-caches","03-review"] if L=='en' else ["01-tong-quan","02-cache-lap-trinh","03-xem-lai"]
css='''*{margin:0;padding:0;box-sizing:border-box}body{font-family:Inter,system-ui;background:#1E1E21;color:#F2F2F7;width:1440px;padding:40px 56px}
h2{font-size:13px;letter-spacing:.8px;color:#98989F;font-weight:600;margin:0 0 14px}
.res{background:#2A2A2E;border-radius:18px;padding:22px;display:flex;flex-direction:column;gap:18px;margin-bottom:44px}
.top{display:flex;gap:16px;align-items:center}.ic{width:84px;height:84px}.n{font-size:19px;font-weight:600}.s{font-size:14px;color:#AEAEB2;margin-top:3px}.c{font-size:12.5px;color:#8E8E93;margin-top:4px}
.get{margin-left:auto;background:#3A3A3F;color:#4DA3FF;font-weight:700;border-radius:16px;padding:7px 22px;font-size:14px}
.th{display:flex;gap:14px}.th img{width:calc((100% - 28px)/3);border-radius:10px;border:1px solid #3A3A3F}
.hd{display:flex;gap:28px;align-items:center;padding-bottom:26px;border-bottom:1px solid #3A3A3F}.hd .ic{width:150px;height:150px}
.hn{font-size:32px;font-weight:700;letter-spacing:-.4px}.hs{font-size:18px;color:#AEAEB2;margin-top:4px}.dev{font-size:14px;color:#4DA3FF;margin-top:8px}
.hb{display:flex;gap:12px;margin-top:16px}.blue{background:#0A84FF;color:#fff;border-radius:16px;padding:7px 24px;font-weight:700;font-size:14px}
.info{display:grid;grid-template-columns:repeat(5,1fr);margin-top:22px}.info div{text-align:center;border-right:1px solid #3A3A3F;padding:4px 0}.info div:last-child{border:0}
.info span{display:block;font-size:11px;letter-spacing:.6px;color:#8E8E93;font-weight:600}.info b{display:block;font-size:20px;margin:4px 0 2px;color:#C7C7CC}.info i{font-style:normal;font-size:12px;color:#8E8E93}
'''
th=''.join(f'<img src="{L}-{s}.png">' for s in shots)
html=f'''<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>
<h2>{t("SEARCH RESULT","KẾT QUẢ TÌM KIẾM")}</h2>
<div class="res"><div class="top"><img class="ic" src="icon.png"><div><div class="n">{name}</div><div class="s">{sub}</div><div class="c">{t("Utilities","Tiện ích")}</div></div><span class="get">{t("Get","Nhận")}</span></div><div class="th">{th}</div></div>
<h2>{t("PRODUCT PAGE HEADER","PHẦN ĐẦU TRANG SẢN PHẨM")}</h2>
<div class="hd"><img class="ic" src="icon.png"><div><div class="hn">{name}</div><div class="hs">{sub}</div><div class="dev">Steve Tran</div><div class="hb"><span class="blue">{t("Get","Nhận")}</span></div></div></div>
<div class="info"><div><span>{t("CATEGORY","DANH MỤC")}</span><b>{t("Utilities","Tiện ích")}</b><i>&nbsp;</i></div><div><span>{t("AGE","TUỔI")}</span><b>4+</b><i>{t("Years Old","Tuổi")}</i></div>
<div><span>{t("LANGUAGE","NGÔN NGỮ")}</span><b>EN</b><i>+ {t("1 More","1 ngôn ngữ")}</i></div><div><span>{t("PRIVACY","QUYỀN RIÊNG TƯ")}</span><b>{t("None","Không")}</b><i>{t("Data Not Collected","Không thu thập dữ liệu")}</i></div><div><span>{t("PRICE","GIÁ")}</span><b>[PRICE]</b><i>&nbsp;</i></div></div>
</body></html>'''
open(f'store-{L}.html','w').write(html)
