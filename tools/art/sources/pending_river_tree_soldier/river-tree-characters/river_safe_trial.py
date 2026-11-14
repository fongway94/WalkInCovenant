from pathlib import Path
from PIL import Image,ImageChops,ImageFilter
import numpy as np
root=Path('build/river-tree-characters');p=Path('build/river-tree-warrior-probe');out=root/'river-candidates'
ref=Image.open('art/scenes_painted/world_elah_reference.png').convert('RGB').crop((0,398*2,1024,462*2))
a=np.asarray(ref,dtype=np.int16);r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
stone=(r-g>22)&(g-b>17)&(r>95)&(g>70)&(b>28)
full=Image.new('RGB',(2048,3072));full.paste(Image.open('art/scenes_painted/world_elah_refined_top.png'),(0,0));full.paste(Image.open('art/scenes_painted/world_elah_refined_bottom.png'),(0,1536))
box=(0,398*4,2048,462*4);base=full.crop(box)
new=Image.open(root/'river-detail-retry.png').convert('RGB').resize((2048,1152),Image.Resampling.NEAREST).crop((0,(398-320)*4,2048,(462-320)*4))
wm=Image.open(p/'water-mask-restricted.png').convert('L')
for rad in (5,11,17):
 shield=Image.fromarray((stone*255).astype('uint8')).filter(ImageFilter.MaxFilter(rad)).resize((2048,256),Image.Resampling.NEAREST)
 mask=ImageChops.multiply(wm,ImageChops.invert(shield))
 mask.save(root/f'water-protected-{rad}.png')
 for alpha in (0.55,0.72):
  label=f'ctx{round(alpha*100)}-guard{rad}';water=Image.composite(Image.blend(base,new,alpha),base,mask)
  img=full.copy();img.paste(water,box[:2]);d=out/label;d.mkdir(parents=True,exist_ok=True)
  for part,y in [('top',0),('bottom',1536)]:img.crop((0,y,2048,y+1536)).save(d/f'elah-{part}.png',compress_level=3)
  print('built',label,flush=True)
