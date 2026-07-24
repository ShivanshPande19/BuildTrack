import glob
from playwright.sync_api import sync_playwright
exe=None
for p in glob.glob('/root/.cache/ms-playwright/**/chrome-headless-shell',recursive=True):
    exe=p;break
print('chromium:',exe)
ids=['w1','w2','w3','w4','w5','w6','w7','w8','w9']
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=exe,args=['--no-sandbox','--force-color-profile=srgb'])
    pg=b.new_page(viewport={'width':1300,'height':1000},device_scale_factor=3)
    pg.goto('file:///projects/sandbox/buildtrack_workshop.html')
    pg.wait_for_timeout(1600)
    for s in ids:
        pg.query_selector('#'+s).screenshot(path=f'/projects/sandbox/ws_{s}.png')
        print('shot',s)
    b.close()
print('DONE')
