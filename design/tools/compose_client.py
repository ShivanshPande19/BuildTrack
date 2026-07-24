import glob
from PIL import Image, ImageDraw, ImageFont
BG=(215,211,198); INK=(29,28,24); ACC=(120,140,60); MUT=(138,132,120)
def font(sz,bold=False):
    c=glob.glob('/usr/share/fonts/**/DejaVuSans*.ttf',recursive=True)
    b=[x for x in c if 'Bold' in x]
    p=(b[0] if (bold and b) else (c[0] if c else None))
    try:return ImageFont.truetype(p,sz)
    except:return ImageFont.load_default()
order=['client_cM.png']+[f'client_c{i}.png' for i in range(1,10)]
caps=['My Trucks (list)','Truck dashboard','Build journey','Photos','Approve design','Documents','Raise request','Support','Notifications','Profile']
imgs=[Image.open(f).convert('RGB') for f in order]
PW=340; ratio=imgs[0].height/imgs[0].width; PH=int(PW*ratio)
cols=5;rows=2;gx=40;gy=60;mL=60;mT=200;capH=40
W=mL*2+cols*PW+(cols-1)*gx; H=mT+rows*(PH+capH)+(rows-1)*gy+60
sheet=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(sheet)
d.text((mL,64),'Azimuth BuildTrack',font=font(54,True),fill=INK)
d.text((mL,130),'Client  -  full app UI (multi-project)',font=font(30),fill=ACC)
for i,f in enumerate(order):
    r,c=divmod(i,cols); x=mL+c*(PW+gx); y=mT+r*(PH+capH+gy)
    ph=imgs[i].resize((PW,PH),Image.LANCZOS)
    mask=Image.new('L',(PW,PH),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,PW,PH],radius=40,fill=255)
    sheet.paste(ph,(x,y),mask)
    d.text((x+6,y+PH+8),f'{i+1}. {caps[i]}',font=font(22,True),fill=MUT)
sheet.save('BuildTrack_Client_Showcase.png'); sheet.save('BuildTrack_Client_Showcase.pdf','PDF',resolution=110)
print('saved',sheet.size)
