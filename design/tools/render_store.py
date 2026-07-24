import glob
from playwright.sync_api import sync_playwright
exe=None
for p in glob.glob('/root/.cache/ms-playwright/**/chrome-headless-shell',recursive=True):
    exe=p;break
print('chromium:',exe)
ids=['st1','st2','st3','st4','st5','st6','st7','st8','st9']
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=exe,args=['--no-sandbox','--force-color-profile=srgb'])
    pg=b.new_page(viewport={'width':1300,'height':1000},device_scale_factor=3)
    pg.goto('file:///projects/sandbox/buildtrack_store.html')
    pg.wait_for_timeout(1600)
    for s in ids:
        pg.query_selector('#'+s).screenshot(path=f'/projects/sandbox/store_{s}.png')
        print('shot',s)
    b.close()
print('DONE')
