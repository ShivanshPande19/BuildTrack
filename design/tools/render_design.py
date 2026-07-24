import glob
from playwright.sync_api import sync_playwright
exe=None
for p in glob.glob('/root/.cache/ms-playwright/**/chrome-headless-shell',recursive=True):
    exe=p;break
print('chromium:',exe)
ids=['d1','d2','d3','d4','d5','d6','d7','d8','d9']
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=exe,args=['--no-sandbox','--force-color-profile=srgb'])
    pg=b.new_page(viewport={'width':1300,'height':1000},device_scale_factor=3)
    pg.goto('file:///projects/sandbox/buildtrack_design.html')
    pg.wait_for_timeout(1600)
    for s in ids:
        pg.query_selector('#'+s).screenshot(path=f'/projects/sandbox/design_{s}.png')
        print('shot',s)
    b.close()
print('DONE')
