import glob
from playwright.sync_api import sync_playwright
exe=None
for p in glob.glob('/root/.cache/ms-playwright/**/chrome-headless-shell',recursive=True):
    exe=p;break
print('chromium:',exe)
ids=['sv1','sv2','sv3','sv4','sv5','sv6','sv7','sv8','sv9']
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=exe,args=['--no-sandbox','--force-color-profile=srgb'])
    pg=b.new_page(viewport={'width':1300,'height':1000},device_scale_factor=3)
    pg.goto('file:///projects/sandbox/buildtrack_service.html')
    pg.wait_for_timeout(1600)
    for s in ids:
        pg.query_selector('#'+s).screenshot(path=f'/projects/sandbox/service_{s}.png')
        print('shot',s)
    b.close()
print('DONE')
